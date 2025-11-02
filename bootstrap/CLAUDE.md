# Bootstrap Guide

Complete guide for bootstrapping Kubernetes clusters in the Mobius homelab infrastructure.

## Overview

The infrastructure consists of two k0s Kubernetes clusters:
- **lab**: On-premises homelab cluster (N5 + M1-ubuntu nodes)
- **phx**: Cloud VPS cluster (single-node at phx.jaxon.cloud)

Both clusters are managed via GitOps using Flux CD, with secrets encrypted using SOPS with age encryption.

## Prerequisites

### Tools Required
```bash
# k0sctl - k0s cluster management
brew install k0sproject/tap/k0sctl

# flux - GitOps toolkit
brew install fluxcd/tap/flux

# sops - Secret encryption
brew install sops

# age - Encryption tool for SOPS
brew install age

# ssh-to-age - Convert SSH keys to age keys
brew install ssh-to-age
```

### SSH Access
- **Lab (N5)**: `ssh jax@192.168.4.5` (passwordless sudo)
- **PHX (VPS)**: `ssh root@cloud.jax-lab.dev` or `ssh root@85.31.234.30`

### GitHub Personal Access Token
Create a GitHub PAT with `repo` permissions for Flux bootstrap:
- Go to: https://github.com/settings/tokens
- Generate new token (classic)
- Scopes: `repo` (all sub-scopes)
- Save token securely

---

## Lab Cluster Bootstrap

### 1. Deploy k0s Cluster

```bash
# Deploy k0s to N5 + M1-ubuntu
k0sctl apply --config bootstrap/homelab-k0sctl.yaml

# Get kubeconfig
k0sctl kubeconfig --config bootstrap/homelab-k0sctl.yaml > ~/.kube/homelab-config

# Merge with existing kubeconfig
cp ~/.kube/config ~/.kube/config.backup.$(date +%Y%m%d-%H%M%S)
KUBECONFIG=~/.kube/config:~/.kube/homelab-config kubectl config view --flatten > ~/.kube/config.merged
mv ~/.kube/config.merged ~/.kube/config

# Switch to homelab context
kubectl config use-context k0s

# Verify cluster
kubectl get nodes
kubectl get pods -A
```

### 2. Generate SOPS Age Key

```bash
# SSH into N5
ssh jax@192.168.4.5

# Generate age key from SSH key
ssh-to-age < ~/.ssh/id_ed25519 > ~/age.agekey

# Display the age public key (starts with age1...)
ssh-to-age -y < ~/.ssh/id_ed25519

# Exit N5
exit
```

**Save the age public key** - you'll need it for `.sops.yaml` configuration and PHX cluster.

### 3. Create SOPS Age Secret in Kubernetes

```bash
# On N5, create the secret
ssh jax@192.168.4.5 "kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f - && kubectl create secret generic sops-age --namespace=flux-system --from-file=age.agekey=\$HOME/age.agekey"
```

### 4. Bootstrap Flux CD

```bash
# Set GitHub token
export GITHUB_TOKEN=<your-github-pat>

# Bootstrap Flux
flux bootstrap github \
  --owner=ketterma \
  --repository=mobius \
  --branch=main \
  --path=./k8s/clusters/lab \
  --personal \
  --token-auth

# Verify Flux installation
flux check
kubectl get pods -n flux-system
flux get kustomizations
```

### 5. Verify Deployment

```bash
# Check kustomizations
flux get kustomizations

# Check HelmReleases
flux get helmreleases -A

# Check infrastructure pods
kubectl get pods -n metallb-system
kubectl get pods -n traefik
kubectl get pods -n external-dns

# Check LoadBalancer services
kubectl get svc -A | grep LoadBalancer
```

All kustomizations should show `Applied revision` and HelmReleases should be `Ready`.

---

## PHX Cluster Bootstrap

### 1. Deploy k0s Cluster

```bash
# Deploy k0s to PHX VPS
k0sctl apply --config bootstrap/phx-k0sctl.yaml

# Get kubeconfig
k0sctl kubeconfig --config bootstrap/phx-k0sctl.yaml > ~/.kube/phx-config

# Merge with existing kubeconfig
cp ~/.kube/config ~/.kube/config.backup.$(date +%Y%m%d-%H%M%S)
KUBECONFIG=~/.kube/config:~/.kube/phx-config kubectl config view --flatten > ~/.kube/config.merged
mv ~/.kube/config.merged ~/.kube/config

# Switch to phx context
kubectl config use-context phx-jaxon-cloud

# Verify cluster
kubectl get nodes
kubectl get pods -A
```

### 2. Create SOPS Age Secret in Kubernetes

**Use the SAME age key from lab cluster** to ensure secrets encrypted in the repo can be decrypted on both clusters.

```bash
# On PHX VPS, create the secret using the same age key
# First, copy the age key from N5 to PHX
scp jax@192.168.4.5:~/age.agekey /tmp/age.agekey
scp /tmp/age.agekey root@cloud.jax-lab.dev:/root/age.agekey

# Create the secret on PHX
ssh root@cloud.jax-lab.dev "kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f - && kubectl create secret generic sops-age --namespace=flux-system --from-file=age.agekey=/root/age.agekey"

# Clean up
rm /tmp/age.agekey
```

### 3. Bootstrap Flux CD

```bash
# Set GitHub token
export GITHUB_TOKEN=<your-github-pat>

# Switch to PHX context
kubectl config use-context phx-jaxon-cloud

# Bootstrap Flux
flux bootstrap github \
  --owner=ketterma \
  --repository=mobius \
  --branch=main \
  --path=./k8s/clusters/phx \
  --personal \
  --token-auth

# Verify Flux installation
flux check
kubectl get pods -n flux-system
flux get kustomizations
```

### 4. Configure Twingate Connector

The Twingate connector secret has placeholder values that need to be replaced with real credentials:

```bash
# 1. Go to jaxlab.twingate.com dashboard
# 2. Create a new connector for PHX
# 3. Copy the ACCESS_TOKEN and REFRESH_TOKEN
# 4. Update the secret locally:

# Create plaintext secret file
cat > /tmp/twingate-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: twingate-connector
  namespace: twingate
type: Opaque
stringData:
  TWINGATE_ACCESS_TOKEN: "<paste-access-token>"
  TWINGATE_REFRESH_TOKEN: "<paste-refresh-token>"
EOF

# Encrypt with SOPS
sops --encrypt --in-place /tmp/twingate-secret.yaml

# Replace the file in the repo
cp /tmp/twingate-secret.yaml k8s/clusters/phx/infrastructure-config/twingate/secret.sops.yaml

# Commit and push
git add k8s/clusters/phx/infrastructure-config/twingate/secret.sops.yaml
git commit -m "Update PHX Twingate connector credentials"
git push

# Clean up
rm /tmp/twingate-secret.yaml
```

### 5. Verify Deployment

```bash
# Check kustomizations
flux get kustomizations

# Check HelmReleases
flux get helmreleases -A

# Check Traefik (should use hostNetwork)
kubectl get pods -n traefik
kubectl get svc -n traefik

# Check Twingate connector
kubectl get pods -n twingate
kubectl logs -n twingate deployment/twingate-connector

# Test external access
curl -I https://phx.jaxon.cloud
```

---

## Infrastructure Components

### Lab Cluster
- **MetalLB**: L2 LoadBalancer (192.168.4.50-59, 192.168.8.50-79)
- **Traefik**: Ingress with Let's Encrypt (DNS-01 challenge via Cloudflare)
- **External-DNS**: Automatic DNS via AdGuard Home webhook
- **Storage**: OpenEBS ZFS LocalPV (3 pools: ai, vms, tank)

### PHX Cluster
- **Traefik**: Ingress with hostNetwork (Let's Encrypt HTTP-01 challenge)
- **External-DNS**: Automatic DNS via Cloudflare API
- **Storage**: local-path (default k0s storage)
- **Twingate**: VPN connector for homelab access

---

## SOPS Configuration

All encrypted secrets use age encryption with the public key derived from the N5 SSH key.

### Encrypting New Secrets

```bash
# Create plaintext secret
cat > secret.sops.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: default
type: Opaque
stringData:
  key: value
EOF

# Encrypt (uses .sops.yaml config automatically)
sops --encrypt --in-place secret.sops.yaml

# Verify encryption
cat secret.sops.yaml
```

### Decrypting Secrets (for verification)

```bash
# On N5 (has the age private key)
export SOPS_AGE_KEY_FILE=~/age.agekey
sops --decrypt secret.sops.yaml
```

---

## Troubleshooting

### Flux Not Reconciling
```bash
# Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization infrastructure

# Check logs
kubectl logs -n flux-system deployment/kustomize-controller
kubectl logs -n flux-system deployment/source-controller
```

### SOPS Decryption Failures
```bash
# Verify secret exists
kubectl get secret sops-age -n flux-system

# Check kustomization has decryption config
kubectl get kustomization infrastructure -n flux-system -o yaml | grep -A 3 decryption
```

### Certificate Issues (Traefik)
```bash
# Check Traefik logs
kubectl logs -n traefik deployment/traefik

# Verify Cloudflare token
kubectl get secret cloudflare-api-token -n traefik -o jsonpath='{.data.CF_DNS_API_TOKEN}' | base64 -d

# Delete acme.json to force fresh cert request
kubectl exec -n traefik deployment/traefik -- rm -f /data/acme.json
kubectl rollout restart deployment/traefik -n traefik
```

### Twingate Connector Issues
```bash
# Check connector logs
kubectl logs -n twingate deployment/twingate-connector

# Common issues:
# - Invalid credentials: Generate new connector in dashboard
# - Network unreachable: Check VPS firewall/security groups
# - Connector offline in dashboard: Verify tokens are correct
```

---

## Maintenance

### Updating k0s
```bash
# Update k0sctl.yaml with new version
# Then apply
k0sctl apply --config bootstrap/homelab-k0sctl.yaml
# or
k0sctl apply --config bootstrap/phx-k0sctl.yaml
```

### Updating Flux
```bash
# Check for updates
flux check --pre

# Update Flux
flux install --export > k8s/clusters/lab/flux-system/gotk-components.yaml
# Commit and push
```

### Rotating SOPS Keys
If you need to rotate the age key:
1. Generate new age key
2. Update `.sops.yaml` with new public key
3. Re-encrypt all secrets: `find k8s -name "*.sops.yaml" -exec sops updatekeys {} \;`
4. Update `sops-age` secret in both clusters
5. Commit and push

---

## References

- [k0s Documentation](https://docs.k0sproject.io/)
- [Flux Documentation](https://fluxcd.io/docs/)
- [SOPS Documentation](https://github.com/getsops/sops)
- [Age Encryption](https://age-encryption.org/)
- [Repository Structure](../CLAUDE.md)
