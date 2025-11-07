# Supabase - Kubernetes Deployment

This directory contains Flux-managed Kubernetes manifests for deploying Supabase (open-source Firebase alternative) to the homelab K8s cluster.

## Overview

Supabase deployment with **authentication disabled** for simplified initial setup. Auth can be integrated later with Pocket-ID OIDC provider.

## Deployed Components

### Enabled Services
- ✅ **PostgreSQL** (15.1.0.147) - Database with Supabase extensions
- ✅ **Studio** - Web-based database dashboard
- ✅ **PostgREST** - Auto-generated REST API from database schema
- ✅ **Realtime** - WebSocket subscriptions to database changes
- ✅ **Meta** - Database metadata service
- ✅ **Storage** - Object storage (file-based, 50GB)
- ✅ **ImgProxy** - Image transformation service

### Disabled Services
- ❌ **Auth (GoTrue)** - Disabled (can add Pocket-ID integration later)
- ❌ **Kong** - Not needed (using Traefik instead)
- ❌ **Analytics** - Not needed for homelab
- ❌ **Vector** - Not needed for homelab
- ❌ **Functions** - Not needed initially
- ❌ **MinIO** - Using file storage instead

## Infrastructure

### Storage
- **Database**: 100Gi ZFS persistent volume (`openebs-zfs-homelab`)
- **Object Storage**: 50Gi ZFS persistent volume (`openebs-zfs-homelab`)
- **Storage Backend**: File-based (not S3)

### Network
- **LoadBalancer IP**: Assigned from MetalLB `l2-vlan8` pool (192.168.8.50-79)
- **Ingress**: Traefik with Let's Encrypt DNS-01 certificates
- **Domains**:
  - Studio: `https://studio.supabase.jax-lab.dev`
  - API: `https://api.supabase.jax-lab.dev`

### Resources
**Estimated Usage:**
- CPU: ~1-2 cores idle, ~3-4 cores under load
- Memory: ~6-8GB
- Storage: ~150GB total

## Access

### Supabase Studio (Dashboard)
```bash
# URL
https://studio.supabase.jax-lab.dev

# Credentials (SOPS encrypted in secret.secret.yaml)
Username: supabase
Password: <see encrypted secret>
```

### API Access
```bash
# REST API endpoint
https://api.supabase.jax-lab.dev

# Get service role key (bypasses RLS)
kubectl -n supabase get secret supabase-secrets -o jsonpath='{.data.service-key}' | base64 -d
```

### Database Access
```bash
# Port-forward to PostgreSQL
kubectl -n supabase port-forward svc/supabase-db 5432:5432

# Connect with psql
kubectl -n supabase get secret supabase-secrets -o jsonpath='{.data.db-password}' | base64 -d
psql -h localhost -U postgres -d postgres
```

## Client Usage

### JavaScript/TypeScript
```typescript
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://api.supabase.jax-lab.dev'
const supabaseKey = 'YOUR_SERVICE_ROLE_KEY'  // From secret

const supabase = createClient(supabaseUrl, supabaseKey)

// Query example
const { data, error } = await supabase
  .from('users')
  .select('*')
```

### Direct REST API
```bash
# Get service key
export SUPABASE_KEY=$(kubectl -n supabase get secret supabase-secrets -o jsonpath='{.data.service-key}' | base64 -d)

# Query table
curl -X GET 'https://api.supabase.jax-lab.dev/rest/v1/users' \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SUPABASE_KEY"
```

## Configuration Files

### Manifests
- **`namespace.yaml`** - Dedicated namespace
- **`secret.secret.yaml`** - SOPS-encrypted secrets (JWT, DB, Dashboard)
- **`configmap.yaml`** - Helm chart values
- **`helmrepo.yaml`** - Supabase Helm repository
- **`helmrelease.yaml`** - Flux HelmRelease
- **`services.yaml`** - LoadBalancer and ClusterIP services
- **`ingressroute.yaml`** - Traefik routing with TLS
- **`kustomization.yaml`** - Aggregates all manifests

### Key Configuration
```yaml
# Auth disabled
auth:
  enabled: false

# PostgreSQL
db:
  persistence:
    storageClassName: openebs-zfs-homelab
    size: 100Gi

# Storage (file-based)
storage:
  environment:
    STORAGE_BACKEND: file
  persistence:
    size: 50Gi
```

## Deployment

### Deploy via Flux
```bash
# Commit and push changes
git add k8s/clusters/lab/apps/supabase/
git commit -m "Add Supabase deployment"
git push

# Flux will automatically reconcile (or force it)
flux reconcile source git flux-system
flux reconcile kustomization apps
```

### Monitor Deployment
```bash
# Watch pods
kubectl -n supabase get pods -w

# Check HelmRelease
kubectl -n supabase get helmrelease supabase

# View logs
kubectl -n supabase logs -l app.kubernetes.io/instance=supabase -f
```

## DNS Configuration

### AdGuard Home Rewrites
Add split-horizon DNS rewrites in AdGuard Home:
```
studio.supabase.jax-lab.dev → 192.168.8.5x  (MetalLB LoadBalancer IP)
api.supabase.jax-lab.dev    → 192.168.8.5x  (MetalLB LoadBalancer IP)
```

This allows internal clients to access Supabase directly without routing through VPS.

## Adding Pocket-ID Authentication (Future)

When ready to add authentication:

1. **Update Helm values** - Enable auth with Keycloak provider pointing to Pocket-ID
2. **Create OAuth client in Pocket-ID**:
   - Client ID: `supabase`
   - Redirect URI: `https://api.supabase.jax-lab.dev/auth/v1/callback`
3. **Update secrets** with Pocket-ID client credentials
4. **Deploy changes** via Flux

See `CLAUDE.md` in repository root for detailed Pocket-ID integration guide.

## Troubleshooting

### Pods Not Starting
```bash
# Check events
kubectl -n supabase get events --sort-by='.lastTimestamp'

# Check pod details
kubectl -n supabase describe pod <pod-name>

# Check logs
kubectl -n supabase logs <pod-name>
```

### Database Connection Issues
```bash
# Verify PostgreSQL is ready
kubectl -n supabase exec -it deployment/supabase-db -- pg_isready -U postgres

# Check database logs
kubectl -n supabase logs -l app.kubernetes.io/name=supabase-db
```

### Storage Issues
```bash
# Check PVCs
kubectl -n supabase get pvc

# Check PV binding
kubectl get pv | grep supabase
```

### Certificate Issues
```bash
# Check Traefik logs
kubectl -n traefik logs -l app.kubernetes.io/name=traefik

# Check certificate
kubectl -n supabase get certificate
```

### API Not Responding
```bash
# Test from inside cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://supabase-api.supabase.svc.cluster.local/

# Check service endpoints
kubectl -n supabase get endpoints
```

## Common Operations

### Backup Database
```bash
# Dump entire database
kubectl -n supabase exec deployment/supabase-db -- \
  pg_dumpall -U postgres > supabase-backup-$(date +%Y%m%d).sql

# Restore
kubectl -n supabase exec -i deployment/supabase-db -- \
  psql -U postgres < supabase-backup-20250106.sql
```

### View Secrets
```bash
# Decrypt and view all secrets
sops -d k8s/clusters/lab/apps/supabase/secret.secret.yaml

# Get specific secret
kubectl -n supabase get secret supabase-secrets -o jsonpath='{.data.anon-key}' | base64 -d
```

### Update Configuration
```bash
# Edit values
vim k8s/clusters/lab/apps/supabase/configmap.yaml

# Commit and push (Flux will reconcile)
git add k8s/clusters/lab/apps/supabase/configmap.yaml
git commit -m "Update Supabase configuration"
git push
```

### Scale Services
```bash
# Scale REST API replicas
kubectl -n supabase scale deployment supabase-rest --replicas=3

# For persistent scaling, update configmap.yaml
```

## Related Resources

- **Supabase Docs**: https://supabase.com/docs
- **Helm Chart**: https://github.com/supabase-community/supabase-kubernetes
- **PostgREST**: https://postgrest.org/
- **Traefik IngressRoute**: https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/
- **Project CLAUDE.md**: See repository root for Pocket-ID integration guide
