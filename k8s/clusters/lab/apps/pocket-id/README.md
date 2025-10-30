# Pocket ID - Kubernetes Deployment

This directory contains Flux-managed Kubernetes manifests for deploying Pocket ID authentication service to the homelab K8s cluster.

## Manifests Overview

### helmrepo.yaml
- Helm repository source for the Pocket ID Helm chart
- Uses OCI registry: `ghcr.io/hobbit44/pocket-id-helm`
- Auto-refreshes every hour for latest chart updates

### namespace.yaml
- Creates dedicated `pocket-id` namespace for isolation

### pvc.yaml
- PersistentVolumeClaim for Pocket ID data
- Size: 2Gi
- Storage class: `openebs-zfs-homelab` (ZFS-backed storage)
- Access mode: ReadWriteOnce

### helmrelease.yaml
**Key Configuration:**
- Chart: `pocket-id` from OCI registry
- Image: `ghcr.io/pocket-id/pocket-id:v1`
- Encryption Key: `C0VMk+NxiHcc/CRvORp6zNfOW5L3NaUON/rremGhonA=` (imported from cloud VPS)
- App URL: `https://auth.jax-lab.dev`
- Trust Proxy: `true` (for Traefik headers)
- Resource limits: 500m CPU / 512Mi RAM
- Pod security: Non-root user (UID 1000)
- Persistence: Uses PVC (pocket-id-data)

### service.yaml
- ClusterIP service exposing port 80 (internal)
- Target port 1411 (Pocket ID application port)
- Labels for pod selection

### ingressroute.yaml
**Traefik IngressRoute Configuration:**
- Hostname: `auth.jax-lab.dev`
- Entry points: `web` (HTTP) and `websecure` (HTTPS)
- Middleware: HTTP to HTTPS redirect (redirect-to-https)
- TLS: Let's Encrypt DNS-01 certificate resolver
- Certificate domain: `auth.jax-lab.dev`

### kustomization.yaml
- Aggregates all manifests in dependency order
- HelmRepository must be applied first (helmrepo.yaml)
- Then namespace, storage, deployment, service, and routing

## Next Steps

### 1. Flux Deployment
Flux will automatically deploy when you push this directory:
```bash
git add k8s/clusters/lab/apps/pocket-id/
git commit -m "Add Pocket ID Kubernetes deployment"
git push
```

The `apps` kustomization has been updated to include `pocket-id`.

### 2. Data Migration from Cloud VPS
Before deployment, you should:
1. Export the SQLite database from cloud VPS:
   ```bash
   ssh root@cloud.jax-lab.dev
   docker cp services-pocketid-ygayik-pocket-id-1:/app/data/pocket-id.db /tmp/
   ```

2. Verify the database files:
   - `pocket-id.db` (main database)
   - `pocket-id.db-shm` (shared memory)
   - `pocket-id.db-wal` (write-ahead log)

3. Once Pocket ID pod is running in K8s, restore the database files to the PVC.

### 3. DNS Configuration
Update AdGuard Home split-horizon DNS:
- Add rewrite: `auth.jax-lab.dev` → `192.168.8.50` (K8s Traefik LoadBalancer)
- This allows lab clients to access Pocket ID directly without routing through cloud VPS

### 4. OAuth Integration
Update any OAuth clients (e.g., TinyAuth) to use the new Pocket ID URL:
- Update callback URLs to point to `https://auth.jax-lab.dev` if needed
- Verify OIDC endpoints are reachable

## Configuration Notes

### Encryption Key
The deployment uses the same encryption key from the cloud VPS:
```
ENCRYPTION_KEY=C0VMk+NxiHcc/CRvORp6zNfOW5L3NaUON/rremGhonA=
```

This is critical for data compatibility when migrating the database.

### Storage Class
Uses OpenEBS ZFS storage class (`openebs-zfs-homelab`):
- Persistent storage backed by ZFS pool
- Automatic snapshots and backup capabilities
- Integrated with Kubernetes lifecycle

### Helm Chart
The Pocket ID Helm chart source:
- GitHub: https://github.com/hobbit44/pocket-id-helm
- Image source: https://github.com/pocket-id/pocket-id
- Chart version: Latest (auto-updated by Flux)

## Troubleshooting

### Database Issues
If the database doesn't migrate correctly:
1. Check encryption key matches cloud VPS value
2. Verify SQLite database file format compatibility
3. Check pod logs: `kubectl logs -n pocket-id pocket-id-*`

### Certificate Issues
If Let's Encrypt certificates fail:
1. Verify Traefik DNS-01 challenge is working
2. Check Cloudflare API token permissions
3. Verify domain `auth.jax-lab.dev` is in DNS

### Connectivity
Test access from inside the cluster:
```bash
kubectl run -it --rm debug --image=curl:latest --restart=Never -n pocket-id -- curl http://pocket-id/health
```

## Related Resources
- Pocket ID Documentation: https://github.com/pocket-id/pocket-id
- Helm Chart: https://github.com/hobbit44/pocket-id-helm
- Traefik IngressRoute Docs: https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/
