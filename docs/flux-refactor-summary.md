# Flux GitOps Refactor Summary

**Date:** 2025-11-02
**Status:** ✅ Completed - Ready for Testing

---

## Overview

Refactored Kubernetes manifests from cluster-specific duplicates to a shared base + overlay pattern, preparing for dual-cluster deployment (lab homelab + phx cloud).

---

## New Structure

```
k8s/
├── base/                           # Shared infrastructure (NEW)
│   └── infrastructure/
│       ├── metallb/                # Base MetalLB HelmRelease
│       ├── traefik/                # Base Traefik HelmRelease
│       └── external-dns/           # Base external-dns HelmRelease
│
└── clusters/
    ├── lab/                        # Homelab cluster (REFACTORED)
    │   └── infrastructure/
    │       ├── metallb/            # Overlay: nodeSelector for N5
    │       ├── traefik/            # Overlay: LoadBalancer, DNS-01, storage
    │       └── external-dns/       # Overlay: AdGuard webhook
    │
    └── phx/                        # Cloud cluster (NEW)
        └── infrastructure/
            ├── traefik/            # Overlay: hostNetwork, HTTP-01
            └── external-dns/       # Overlay: Cloudflare provider
```

---

## Key Changes

### 1. **Shared Base Infrastructure** (`k8s/base/`)

Created base HelmReleases for:
- **MetalLB** - Minimal base config
- **Traefik** - Core settings (IngressRoute, security context)
- **External-DNS** - Common settings (sources, policy, interval)

### 2. **Lab Cluster Overlays** (`clusters/lab/infrastructure/`)

**MetalLB:**
- Patches `speaker.nodeSelector` to run only on N5 node
- References base + applies cluster-specific node selector

**Traefik:**
- LoadBalancer service with MetalLB IP: `192.168.8.50`
- Persistent storage: `openebs-zfs-homelab`
- **DNS-01 challenge** for Let's Encrypt (behind NAT)
- Cloudflare API token for DNS validation
- Email: `admin@jaxon.cloud` (NEW DOMAIN)

**External-DNS:**
- Provider: **AdGuard Home webhook**
- Manages internal `*.jaxon.home` DNS records
- txtOwnerId: `lab-cluster`

### 3. **PHX Cluster Overlays** (`clusters/phx/infrastructure/`)

**NO MetalLB** (not needed on single-node)

**Traefik:**
- **`hostNetwork: true`** - Binds directly to ports 80/443
- Service type: `ClusterIP` (not LoadBalancer/NodePort)
- Persistent storage: `local-path`
- **HTTP-01 challenge** for Let's Encrypt (public IP)
- NO Cloudflare token needed (HTTP-01 is simpler)
- Email: `admin@jaxon.cloud`

**External-DNS:**
- Provider: **Cloudflare**
- Manages public `*.jaxon.cloud` DNS records
- Domain filter: `jaxon.cloud`
- txtOwnerId: `phx-cluster`

---

## Cluster Comparison

| Component | Lab (Homelab) | PHX (Cloud VPS) |
|-----------|---------------|-----------------|
| **MetalLB** | ✅ Yes (L2 mode on VLAN 8) | ❌ No (not needed) |
| **Traefik Service** | LoadBalancer (192.168.8.50) | ClusterIP + hostNetwork |
| **Traefik Ports** | 80/443 via MetalLB | 80/443 via hostNetwork |
| **Let's Encrypt** | DNS-01 (Cloudflare) | HTTP-01 (direct) |
| **Storage** | OpenEBS ZFS | local-path |
| **External-DNS** | AdGuard webhook (internal) | Cloudflare (public) |
| **Domain** | `*.jaxon.home` | `*.jaxon.cloud` |

---

## Files Removed

Cleaned up old duplicate files from lab cluster:

```bash
# Removed from clusters/lab/infrastructure/
- metallb.yaml                      # Now in base + overlay
- traefik.yaml                      # Now in base + overlay
- traefik-namespace.yaml            # Now in base
- traefik-cloudflare.secret.yaml   # Moved to traefik/ overlay

# Removed from clusters/lab/infrastructure-config/
- external-dns/                     # Moved to infrastructure/ as overlay
```

---

## New Files Created

### Base Infrastructure
- `k8s/base/infrastructure/metallb/helmrepo.yaml`
- `k8s/base/infrastructure/metallb/helmrelease.yaml`
- `k8s/base/infrastructure/metallb/kustomization.yaml`
- `k8s/base/infrastructure/traefik/namespace.yaml`
- `k8s/base/infrastructure/traefik/helmrepo.yaml`
- `k8s/base/infrastructure/traefik/helmrelease.yaml`
- `k8s/base/infrastructure/traefik/kustomization.yaml`
- `k8s/base/infrastructure/external-dns/namespace.yaml`
- `k8s/base/infrastructure/external-dns/helmrepo.yaml`
- `k8s/base/infrastructure/external-dns/helmrelease.yaml`
- `k8s/base/infrastructure/external-dns/kustomization.yaml`
- `k8s/base/infrastructure/kustomization.yaml`

### Lab Cluster Overlays
- `k8s/clusters/lab/infrastructure/metallb/kustomization.yaml`
- `k8s/clusters/lab/infrastructure/traefik/kustomization.yaml`
- `k8s/clusters/lab/infrastructure/traefik/cloudflare-secret.sops.yaml`
- `k8s/clusters/lab/infrastructure/external-dns/kustomization.yaml`
- `k8s/clusters/lab/infrastructure/external-dns/adguard-secret.sops.yaml`

### PHX Cluster Overlays
- `k8s/clusters/phx/infrastructure/traefik/kustomization.yaml`
- `k8s/clusters/phx/infrastructure/external-dns/kustomization.yaml`
- `k8s/clusters/phx/infrastructure/external-dns/cloudflare-secret.sops.yaml`
- `k8s/clusters/phx/infrastructure/kustomization.yaml`
- `k8s/clusters/phx/infrastructure-config/kustomization.yaml`

### Bootstrap
- `bootstrap/phx-k0sctl.yaml` - k0s config for cloud VPS

---

## Configuration Highlights

### PHX k0s Config (`bootstrap/phx-k0sctl.yaml`)

```yaml
spec:
  network:
    nodeLocalLoadBalancing:
      enabled: false  # Prevents port 80 conflicts
    provider: kuberouter
```

**Key decision:** Disabled Node-Local Load Balancing to avoid envoy blocking port 80.

### PHX Traefik Config

```yaml
deployment:
  kind: Deployment
  replicas: 1

hostNetwork: true  # Bind directly to host ports 80/443
dnsPolicy: ClusterFirstWithHostNet

service:
  type: ClusterIP  # NOT LoadBalancer or NodePort
```

**Why hostNetwork?**
- ✅ Simpler than NodePort (no port range hacks)
- ✅ No MetalLB needed on single-node
- ✅ Direct port binding (better performance)
- ✅ Recommended approach for k0s bare-metal/VPS

---

## Domain Migration

### Old Domain
- `jax-lab.dev` (has hyphen, harder to type)

### New Domains
- **`jaxon.cloud`** - Public-facing services (phx cluster)
- **`jaxon.home`** - Internal homelab services (lab cluster)

**Let's Encrypt Email Changed:**
- Old: `admin@jax-lab.dev`
- New: `admin@jaxon.cloud`

---

## Next Steps

### Before Testing
1. ✅ Get new Cloudflare API token for `jaxon.cloud`
2. ✅ Encrypt secrets with SOPS (both clusters use same age key)
3. ✅ Update AdGuard Home DNS rewrites for `*.jaxon.home`
4. ✅ Set up new Twingate network

### Testing
1. Test lab cluster with refactored structure (dry-run first)
2. Verify Traefik gets certificates for `*.jaxon.cloud`
3. Verify external-dns creates AdGuard records

### Deployment
1. Bootstrap k0s on `phx.jaxon.cloud` (85.31.234.30)
2. Bootstrap Flux CD on phx cluster
3. Verify Traefik binds to ports 80/443 via hostNetwork
4. Create first IngressRoute and test Let's Encrypt HTTP-01

---

## Benefits of Refactor

✅ **DRY (Don't Repeat Yourself)**
- Infrastructure defined once in `base/`
- Clusters only define differences via overlays

✅ **Easier Maintenance**
- Update MetalLB/Traefik version once in base
- All clusters inherit updates automatically

✅ **Clear Separation**
- Base = what's shared
- Overlays = what's different
- Easy to see cluster-specific configs

✅ **Scalable**
- Adding new cluster = create new overlay directory
- Inherit all base infrastructure automatically

✅ **Consistent**
- Both clusters use same Helm charts
- Only values differ per environment

---

## Testing Strategy

### Lab Cluster (Low Risk)
1. Dry-run: `kubectl apply -k k8s/clusters/lab/infrastructure --dry-run=client`
2. Check diff: `kubectl diff -k k8s/clusters/lab/infrastructure`
3. Apply: `flux reconcile kustomization infrastructure --with-source`
4. Monitor: `kubectl get pods -n traefik -w`

### PHX Cluster (New Deployment)
1. Bootstrap k0s: `k0sctl apply --config bootstrap/phx-k0sctl.yaml`
2. Bootstrap Flux: `flux bootstrap github ...`
3. Monitor deployments: `watch kubectl get pods -A`
4. Test Traefik: `curl -k https://phx.jaxon.cloud`

---

## Rollback Plan

If refactor breaks lab cluster:

1. **Immediate:** Revert Git commits
2. **Flux:** `flux reconcile kustomization infrastructure --with-source`
3. **Verify:** Services come back online with old config

Old config still in Git history for emergency rollback.

---

## Known Limitations

### PHX Cluster
- ❌ **Single-node only** - hostNetwork won't scale to multi-node without changes
- ❌ **Port conflicts** - Only one service can bind to 80/443 on host
- ✅ **Acceptable** - Cloud VPS is single-node by design

### Lab Cluster
- ❌ **MetalLB speaker only on N5** - If N5 dies, LoadBalancers stop working
- ✅ **Mitigated** - Can remove nodeSelector for multi-node deployment later

---

## Success Criteria

**Lab Cluster:**
- [ ] Flux reconciles without errors
- [ ] MetalLB assigns `192.168.8.50` to Traefik
- [ ] Traefik gets Let's Encrypt cert for `*.jaxon.cloud` via DNS-01
- [ ] External-DNS creates records in AdGuard Home
- [ ] All apps accessible via `*.jaxon.home`

**PHX Cluster:**
- [ ] k0s cluster bootstraps successfully
- [ ] Flux deploys Traefik with hostNetwork
- [ ] Traefik binds to ports 80/443 on host
- [ ] Let's Encrypt HTTP-01 challenge succeeds
- [ ] External-DNS creates Cloudflare DNS records
- [ ] Test app accessible via `*.jaxon.cloud`
