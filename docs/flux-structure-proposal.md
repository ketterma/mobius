# Flux GitOps Structure Proposal

## Overview
Refactor to use shared base infrastructure with cluster-specific overlays.

## Current Issues
1. ❌ Duplicate infrastructure definitions (MetalLB, Traefik in each cluster)
2. ❌ No clear separation of CRDs vs applications
3. ❌ Hard to maintain consistency across clusters

## Proposed Structure

```
k8s/
├── base/                           # Shared base resources
│   ├── crds/                       # CRDs installed first (phase 0)
│   │   ├── kustomization.yaml
│   │   ├── metallb-crds.yaml       # MetalLB CRDs
│   │   └── traefik-crds.yaml       # Traefik CRDs (if needed)
│   │
│   ├── infrastructure/             # Core infrastructure (phase 1)
│   │   ├── kustomization.yaml
│   │   ├── metallb/
│   │   │   ├── kustomization.yaml
│   │   │   ├── helmrepo.yaml
│   │   │   └── helmrelease.yaml    # Base MetalLB chart
│   │   ├── traefik/
│   │   │   ├── kustomization.yaml
│   │   │   ├── namespace.yaml
│   │   │   ├── helmrepo.yaml
│   │   │   └── helmrelease.yaml    # Base Traefik chart
│   │   └── external-dns/
│   │       ├── kustomization.yaml
│   │       ├── namespace.yaml
│   │       ├── helmrepo.yaml
│   │       └── helmrelease.yaml    # Base external-dns chart
│   │
│   └── storage/                    # Storage providers (phase 1, parallel with infra)
│       ├── kustomization.yaml
│       └── openebs/
│           ├── kustomization.yaml
│           ├── helmrepo.yaml
│           └── helmrelease.yaml    # Base OpenEBS chart
│
├── clusters/
│   ├── lab/                        # Homelab cluster
│   │   ├── flux-system/            # Flux bootstrap
│   │   │
│   │   ├── crds.yaml               # Phase 0: CRDs
│   │   │   # Points to: k8s/base/crds
│   │   │
│   │   ├── infrastructure.yaml     # Phase 1: Infrastructure
│   │   │   # Points to: k8s/base/infrastructure + overlays
│   │   │
│   │   ├── infrastructure/         # Cluster-specific infrastructure overlays
│   │   │   ├── kustomization.yaml
│   │   │   ├── metallb/
│   │   │   │   └── kustomization.yaml   # Overlay: adds cluster-specific values
│   │   │   ├── traefik/
│   │   │   │   ├── kustomization.yaml
│   │   │   │   └── values.yaml          # Overlay: cluster-specific values
│   │   │   └── external-dns/
│   │   │       ├── kustomization.yaml
│   │   │       └── values.yaml
│   │   │
│   │   ├── storage.yaml            # Phase 1: Storage (parallel)
│   │   │   # Points to: k8s/base/storage + overlays
│   │   │
│   │   ├── storage/                # Cluster-specific storage overlays
│   │   │   ├── kustomization.yaml
│   │   │   ├── storage-classes.yaml     # OpenEBS ZFS storage classes
│   │   │   └── openebs/
│   │   │       └── values.yaml
│   │   │
│   │   ├── infrastructure-config.yaml   # Phase 2: Infrastructure config
│   │   │   # Points to: clusters/lab/infrastructure-config/
│   │   │
│   │   ├── infrastructure-config/  # Cluster-specific infra config (NOT shared)
│   │   │   ├── kustomization.yaml
│   │   │   ├── metallb-config.yaml      # IPAddressPool for 192.168.8.x
│   │   │   ├── traefik-config/
│   │   │   │   ├── cloudflare-secret.sops.yaml
│   │   │   │   └── middleware.yaml
│   │   │   └── twingate/
│   │   │       ├── deployment.yaml
│   │   │       └── secret.sops.yaml
│   │   │
│   │   ├── apps.yaml               # Phase 3: Applications
│   │   │   # Points to: clusters/lab/apps/
│   │   │
│   │   ├── apps/                   # Cluster-specific apps (NOT shared)
│   │   │   ├── kustomization.yaml
│   │   │   ├── adguard/
│   │   │   ├── homeassistant/
│   │   │   ├── pocket-id/
│   │   │   └── unifi/
│   │   │
│   │   └── kustomization.yaml      # Root: references all phases
│   │
│   └── phx/                        # Cloud cluster
│       ├── flux-system/
│       │
│       ├── crds.yaml               # Phase 0: Same CRDs as lab
│       │   # Points to: k8s/base/crds
│       │
│       ├── infrastructure.yaml     # Phase 1: Same base infra
│       │   # Points to: k8s/base/infrastructure + overlays
│       │
│       ├── infrastructure/         # Cloud-specific overlays
│       │   ├── kustomization.yaml
│       │   ├── metallb/
│       │   │   └── kustomization.yaml   # Different from lab
│       │   ├── traefik/
│       │   │   └── values.yaml          # Different ingress config
│       │   └── external-dns/
│       │       └── values.yaml          # Points to Cloudflare directly
│       │
│       ├── storage.yaml            # Phase 1: Storage
│       │   # NO OpenEBS, uses local-path-provisioner instead
│       │
│       ├── storage/
│       │   ├── kustomization.yaml
│       │   └── local-path/              # Simple local storage
│       │       └── helmrelease.yaml
│       │
│       ├── infrastructure-config.yaml   # Phase 2
│       │
│       ├── infrastructure-config/
│       │   ├── kustomization.yaml
│       │   ├── metallb-config.yaml      # IPAddressPool for 85.31.234.30
│       │   ├── traefik-config/
│       │   │   └── cloudflare-secret.sops.yaml
│       │   └── twingate/
│       │       └── deployment.yaml
│       │
│       ├── apps.yaml               # Phase 3
│       │
│       ├── apps/                   # Cloud-specific apps
│       │   ├── kustomization.yaml
│       │   └── uptime-kuma/
│       │       └── ...
│       │
│       └── kustomization.yaml
│
└── infrastructure/                 # Legacy? Can be removed
    └── storage/
```

## Flux Phases & Dependencies

### Phase 0: CRDs (crds.yaml)
- **Purpose:** Install CustomResourceDefinitions first
- **Contents:** MetalLB CRDs, Traefik CRDs (if any)
- **Depends on:** flux-system
- **Wait:** true (must complete before phase 1)

### Phase 1: Infrastructure (infrastructure.yaml, storage.yaml)
- **Purpose:** Install base infrastructure components
- **Contents:**
  - MetalLB HelmRelease (no config yet)
  - Traefik HelmRelease (no config yet)
  - external-dns HelmRelease (no config yet)
  - Storage providers (OpenEBS or local-path)
- **Depends on:** crds
- **Wait:** true (must complete before phase 2)
- **Parallel:** infrastructure.yaml and storage.yaml can run in parallel

### Phase 2: Infrastructure Config (infrastructure-config.yaml)
- **Purpose:** Configure infrastructure components
- **Contents:**
  - MetalLB IPAddressPools, L2Advertisements
  - Traefik Middlewares, TLS configs, secrets
  - Twingate connectors
- **Depends on:** infrastructure, storage
- **Wait:** true (must complete before phase 3)

### Phase 3: Applications (apps.yaml)
- **Purpose:** Deploy applications
- **Contents:** All user-facing applications
- **Depends on:** infrastructure-config
- **Wait:** false (can fail without blocking)

## Kustomize Overlay Pattern

### Base HelmRelease (k8s/base/infrastructure/metallb/helmrelease.yaml)
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: metallb
  namespace: flux-system
spec:
  interval: 30m
  chart:
    spec:
      chart: metallb
      version: 0.14.x
      sourceRef:
        kind: HelmRepository
        name: metallb
  targetNamespace: metallb-system
  install:
    createNamespace: true
  values:
    # Base values - minimal/default
    speaker:
      tolerateMaster: true
```

### Cluster Overlay (clusters/lab/infrastructure/metallb/kustomization.yaml)
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../../base/infrastructure/metallb

patches:
  - patch: |-
      apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      metadata:
        name: metallb
        namespace: flux-system
      spec:
        values:
          speaker:
            nodeSelector:
              kubernetes.io/hostname: n5
    target:
      kind: HelmRelease
      name: metallb
```

## Benefits

✅ **DRY (Don't Repeat Yourself)**
- Infrastructure defined once in `base/`
- Clusters only define differences

✅ **Clear Phases**
- CRDs → Infrastructure → Config → Apps
- Proper dependency ordering
- No race conditions

✅ **Easy Multi-Cluster**
- Add new cluster = create overlay directory
- Inherit all base infrastructure
- Override only what's different

✅ **Maintainability**
- Update MetalLB version once in base
- All clusters get update automatically
- Cluster-specific changes isolated to overlays

## Migration Path

1. Create `k8s/base/` structure
2. Move shared components to base
3. Convert cluster dirs to overlays
4. Update Flux Kustomizations to point to overlays
5. Test on homelab cluster first
6. Apply same pattern to cloud cluster

## Questions to Resolve

1. **Do we need apps-config.yaml?**
   - Probably not - most app configs are in the app itself
   - Unless you have shared app configurations?

2. **Should storage be separate phase or part of infrastructure?**
   - Current proposal: Parallel with infrastructure (phase 1)
   - Storage is foundational, apps need it

3. **SOPS secrets in base or clusters?**
   - Always cluster-specific (different age keys per cluster?)
   - Keep in `clusters/*/infrastructure-config/`

4. **External-DNS: base or cluster-specific?**
   - Base: HelmRelease
   - Cluster: Provider config (AdGuard vs Cloudflare)
