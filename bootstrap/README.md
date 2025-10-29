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
cd bootstrap/

# Review the config
cat k0smotron-management-config.yaml

# Deploy
k0sctl apply --config k0smotron-management-config.yaml

# Get kubeconfig
k0sctl kubeconfig > ~/.kube/mobius-management.yaml
export KUBECONFIG=~/.kube/mobius-management.yaml

# Verify cluster is ready
kubectl get nodes
kubectl get pods -A
```

Once all nodes are `Ready` and pods are running, proceed to Phase 1 in `k8s/README.md`.
