# Homelab Kubernetes GitOps

Flux-managed Kubernetes configuration for homelab infrastructure.

## Phase 1: Bootstrap Only (Current)

Minimal scaffolding to get k0smotron clusters running:

```
k8s/
└── clusters/
    └── management/
        ├── flux-system/          # Flux bootstrap
        ├── kustomization.yaml    # Management cluster kustomization
        ├── cloud-cluster.yaml    # k0smotron Cluster CRD
        ├── homelab-cluster.yaml  # k0smotron Cluster CRD
        └── sandbox-cluster.yaml  # k0smotron Cluster CRD
```

## Quick Start

### 1. Install k0s Management Cluster on N5

First, create a standalone k0s cluster on N5 that will become the management cluster for k0smotron.

**Option A: Using k0sctl (Recommended)**

Create `k0smotron-management-config.yaml`:
```yaml
apiVersion: k0sctl.k0sproject.io/v1beta1
kind: Cluster
metadata:
  name: k0smotron-management
spec:
  hosts:
    - role: controller+worker
      hostname: n5.jax-lab.dev
      connection:
        address: 192.168.8.8
        user: jax
        keyPath: ~/.ssh/id_rsa
  k0s:
    version: v1.34.1+k0s.0
    config:
      apiVersion: k0s.k0sproject.io/v1beta1
      kind: ClusterConfig
      metadata:
        name: k0smotron-management
      spec:
        api:
          address: 192.168.8.8
        networking:
          provider: kube-router
```

Then deploy:
```bash
k0sctl apply --config k0smotron-management-config.yaml
```

**Option B: Manual Installation**

```bash
# SSH to N5
ssh jax@192.168.8.8

# Download and install k0s
curl -sSLf https://get.k0s.sh | sudo sh
sudo k0s install controller --enable-worker

# Start k0s
sudo systemctl start k0scontroller

# Get kubeconfig
sudo k0s kubeconfig admin
```

### 2. Install k0smotron in Management Cluster

Once the k0s management cluster is running:

```bash
# Apply k0smotron manifests
kubectl apply --server-side=true -f https://docs.k0smotron.io/stable/install.yaml

# Wait for k0smotron to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=k0smotron \
  -n k0smotron \
  --timeout=300s
```

### 3. Bootstrap Flux

Flux will manage the k0smotron Cluster CRDs that define the workload clusters:

```bash
# Bootstrap Flux in the management cluster
flux bootstrap github \
  --owner=your-user \
  --repository=homelab \
  --path=k8s/clusters/management \
  --personal
```

### 4. Deploy Workload Clusters

Flux will automatically create k0smotron Cluster CRDs:
- **cloud-cluster**: VPS workload cluster (control plane on N5, worker on VPS)
- **homelab-cluster**: N5 workload cluster (control plane on N5, worker on N5)
- **sandbox-cluster**: Testing cluster (control plane on N5)

Monitor cluster creation:
```bash
kubectl get clusters -A
kubectl logs -n k0smotron -l app.kubernetes.io/name=k0smotron -f
```

### 5. Join Worker Nodes to Workload Clusters

For each workload cluster, retrieve the join token and add worker nodes:

```bash
# Get join token for cloud-cluster
kubectl exec -it -n cloud-cluster pod/k0s-controller \
  -- k0s token create --role=worker

# On VPS, join the cluster
k0s token create --role=worker | k0s worker --token-file -

# Repeat for other clusters as needed
```

Verify nodes joined:
```bash
# From management cluster, switch to workload cluster context
kubectl config use-context cloud-cluster

# Check nodes
kubectl get nodes -o wide
```

## Next Phases (After Bootstrap Validation)

Once k0smotron clusters are running and Flux is syncing:
- Phase 2: Add infrastructure (Traefik, external-dns, OpenEBS, KubeVirt, Multus)
- Phase 3: Add applications (uptime-kuma, home-assistant, n8n, etc.)

Each phase will be committed separately after validation.

## Validation Steps

After each phase:
1. Check Flux sync: `flux get all -A`
2. Check cluster status: `k0s status` on management cluster
3. Verify workload cluster kubeconfigs are created
4. Test kubectl access to each workload cluster
