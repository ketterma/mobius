# Bootstrap

One-time setup scripts and configurations to bootstrap the Mobius homelab infrastructure.

## k0s Management Cluster (Phase 0)

This is the foundational step that must be completed before anything else.

### Prerequisites

- `k0sctl` installed locally
  ```bash
  brew install k0sproject/tap/k0sctl
  ```
- SSH access to N5 (`192.168.8.8` as user `jax`)
- Git repo cloned locally

### Deploy k0s Management Cluster

```bash
# Deploy k0s cluster
k0sctl apply --config bootstrap/k0sctl.yaml

# Get kubeconfig and merge into default config
cp ~/.kube/config ~/.kube/config.backup.$(date +%Y%m%d-%H%M%S)
k0sctl kubeconfig --config bootstrap/k0sctl.yaml > ~/.kube/mobius-management.yaml
KUBECONFIG=~/.kube/config:~/.kube/mobius-management.yaml kubectl config view --flatten > ~/.kube/config.merged
mv ~/.kube/config.merged ~/.kube/config

# Switch to mobius context
kubectl config use-context mobius

# Verify cluster is ready
kubectl get nodes
kubectl get pods -A
```

**Note:** The k0sctl config includes `noTaints: true` for the controller+worker node, which automatically allows workloads to schedule on this single-node cluster.

### Install cert-manager

k0smotron requires cert-manager for webhook certificates:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
```

### Install k0smotron

```bash
kubectl apply --server-side=true -f https://docs.k0smotron.io/stable/install.yaml

# Wait for k0smotron to be ready
kubectl wait --for=condition=ready pod -l control-plane=controller-manager -n k0smotron --timeout=300s

# Verify installation
kubectl get pods -A
```

Once all pods are `Running`, proceed to Phase 1 (Flux bootstrap) in `k8s/README.md`.
