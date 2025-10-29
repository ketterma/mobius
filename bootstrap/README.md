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

### Troubleshooting SSH Authentication

If you get `ssh: unable to authenticate` errors:

1. **Verify SSH key exists**:
   ```bash
   ls -la ~/.ssh/id_rsa
   ```

2. **Test SSH connection manually**:
   ```bash
   ssh -i ~/.ssh/id_rsa jax@192.168.8.8
   ```

3. **Check k0sctl logs**:
   ```bash
   cat ~/Library/Caches/k0sctl/k0sctl.log
   ```

4. **Verify N5 has your public key**:
   ```bash
   ssh jax@192.168.8.8 cat ~/.ssh/authorized_keys
   ```

Once all nodes are `Ready` and pods are running, proceed to Phase 1 in `k8s/README.md`.
