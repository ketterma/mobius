# Kubernetes Architecture Design - Mobius Homelab

## Status: PLANNING

This document outlines the proposed Kubernetes architecture to replace the current Dokploy setup.

---

## Goals

1. **Unified Management**: Manage VMs (KubeVirt) and containers (Docker) through Kubernetes
2. **Sandbox Environments**: Enable isolated staging/sandbox clusters for testing before production
3. **ZFS Integration**: Native ZFS storage management across 3 tiers (ai/vms/tank)
4. **Minimal Disruption**: Maintain existing networking (Twingate, Traefik, split-horizon DNS)
5. **Learning Platform**: Gain Kubernetes skills transferable to enterprise environments
6. **AI Integration**: Dedicated inference host (M4) + flexible AI workload capacity (N5)

---

## IP Allocation (VLAN Architecture)

### VLAN 4 (192.168.4.0/24) - Services/k0s Nodes
| Host | IP | Purpose | Notes |
|------|----|---------|-------|
| Gateway | 192.168.4.1 | UDM Pro gateway | Default route |
| N5 | 192.168.4.5 | k0s controller+worker, host SSH | Primary server |
| **M1 macOS host** | **192.168.4.11** | **Mac Mini M1 host (UTM hypervisor)** | **M1 = 11** |
| **M4** | **192.168.4.14** | **AI inference (Osaurus on macOS)** | **M4 = 14** |
| AdGuard Home | 192.168.4.53 | Split-horizon DNS (LoadBalancer) | DNS port 53 |
| **M1 Ubuntu VM** | **192.168.4.81** | **Monitoring + CI/CD (k8s worker)** | **Worker node** |

### VLAN 8 (192.168.8.0/24) - Infrastructure VIPs
| Service | IP | Purpose | Notes |
|---------|----|---------|----- |
| Traefik | 192.168.8.50 | Ingress LoadBalancer | MetalLB pool |
| Services pool | 192.168.8.51-79 | Additional LoadBalancers | MetalLB pool |

### VLAN 64 (192.168.64.0/20) - IoT / VMs
| Host | IP | Purpose | Notes |
|------|----|---------|-------|
| Gateway | 192.168.64.1 | N5 bridge64 | VM gateway |
| Home Assistant VM | 192.168.64.2 | Smart home automation (KubeVirt VM) | IoT network |

### VLAN 16 (192.168.16.0/20) - Sandbox / Untrusted
| Purpose | Notes |
|---------|-------|
| Future sandbox workloads | Reserved for future use |

### External
| Host | IP | Purpose | Notes |
|------|----|---------|-------|
| VPS | 85.31.234.30 | Public ingress (cloud-cluster worker) | Public IP |

---

## Key Decisions

### ✅ Kubernetes Distribution: k0smotron on N5

**Decision**: Use **k0smotron** to manage multiple independent clusters

**Architecture**:
- **Management Cluster**: k0s on N5 (runs k0smotron operator)
- **Workload Clusters** (control planes as pods on N5):
  - **Homelab Cluster**: Workers on N5 (VMs, storage, internal services)
  - **Cloud Cluster**: Workers on VPS (public-facing services)
  - **Sandbox Cluster**: Workers on N5 (experiments, testing)

**Rationale**:
- Resource optimization: N5 has 91GB RAM, VPS only 7.8GB
- VPS runs workers only (~200MB vs ~600MB for control plane)
- Control planes survive VPS issues
- True cluster isolation (homelab ≠ cloud ≠ sandbox)
- Explicit cross-cluster dependencies via Twingate

**Tradeoff**: N5 downtime = all control planes down (acceptable for homelab)

### ✅ Cluster Topology: Multi-Cluster via k0smotron

**Architecture**:
```
N5 (Management Cluster - k0s)
├─ k0smotron operator
├─ Control Plane Pods:
│  ├─ homelab-cluster (API server, etcd, controllers)
│  ├─ cloud-cluster (API server, etcd, controllers)
│  └─ sandbox-cluster (API server, etcd, controllers)
│
└─ Workers (join homelab + sandbox clusters):
   ├─ N5 itself (primary worker)
   └─ M1 VM (monitoring, CI/CD)

VPS (Worker-only)
└─ Joins cloud-cluster via token

M4 (External - non-Kubernetes)
└─ AI inference (Osaurus)
   └─ Exposed as ExternalName service
```

**Benefits**:
- Independent failure domains (VPS issues ≠ homelab cluster issues)
- Clear cross-cluster dependencies (explicit Twingate service endpoints)
- Resource efficiency (VPS = worker-only, ~200MB overhead)
- Sandbox isolation (true separate cluster, not just namespace)
- Monitoring isolation (M1 survives N5 reboots)
- Native AI performance (M4 outside k8s, maximum efficiency)

---

## Infrastructure Components

### Compute Nodes

| Node | Role | Resources | Purpose |
|------|------|-----------|---------|
| **N5** | Management + Worker | 91GB RAM, 24 cores, ZFS pools | k0smotron mgmt, VMs, storage, flexible for AI |
| **VPS** | Worker only | 7.8GB RAM, 2 cores | Public-facing services (cloud-cluster) |
| **M1** | Worker only | 8GB RAM (6GB to VM), 8 cores | Monitoring, CI/CD (Ubuntu VM via UTM) |
| **M4** | External (non-k8s) | 24GB RAM, 10 cores | AI inference (Osaurus native on macOS) |

### Mac Mini Integration

#### M4 Mac Mini (AI Inference Host)

**Hardware**: 24GB RAM, M4 chip (10 cores)

**Role**: Dedicated AI inference server (non-Kubernetes)

**Software Stack**:
- macOS native (no VM, no containers)
- Osaurus (LLM inference server)
- Exposed as external service to Kubernetes

**Why not Kubernetes:**
- Metal Performance Shaders (native GPU acceleration)
- Unified Memory (24GB shared CPU/GPU for large models)
- MLX framework optimization
- Zero container overhead

**Kubernetes Integration**:
```yaml
# External service definition in homelab-cluster
apiVersion: v1
kind: Service
metadata:
  name: osaurus
  namespace: ai
spec:
  type: ExternalName
  externalName: m4.jax-lab.dev  # Static IP: 192.168.4.14
  ports:
    - port: 8080
      name: api
```

**Network**: `192.168.4.14` on Services VLAN 4 (M4 = 14)

---

#### M1 Mac Mini (Monitoring & CI/CD Node)

**Hardware**: 8GB RAM, M1 chip (8 cores)

**Role**: Kubernetes worker for non-critical workloads

**Deployment Strategy**: Ubuntu VM via UTM hypervisor

**VM Configuration**:
- OS: Ubuntu 24.04 ARM64
- CPU: 4 cores (of 8)
- RAM: 6GB (leave 2GB for macOS host)
- Disk: 50GB thin-provisioned
- Network: Bridged to Services VLAN 4
- Static IP: `192.168.4.81` (M1 VM = 81)

**macOS Host Network**: `192.168.4.11` (M1 = 11)

**Joins**: homelab-cluster as worker node

**Node Labels**:
```bash
kubectl label node m1-worker role=monitoring
kubectl label node m1-worker role=ci-cd
kubectl label node m1-worker arch=arm64
```

**Workloads** (deployed via node selectors):
- **Monitoring Stack**: Prometheus, Grafana, Loki, Alertmanager
- **CI/CD**: GitHub Actions self-hosted runner, Flux notification-controller
- **Build Tools**: Renovate bot, image scanning (Trivy)

**Why VM instead of native macOS**:
- Real Linux kernel (proper k8s behavior)
- Better networking (bridge to Services VLAN)
- Lighter than Docker Desktop
- Full k0s compatibility

**Resource Allocation**:
- macOS host: 2GB (UTM hypervisor + system)
- Ubuntu VM: 6GB (k0s worker + workloads)

**Failure Impact**: Non-critical
- Monitoring dashboard temporarily unavailable
- CI/CD builds pause
- GitOps unaffected (core Flux on N5)
- Can restore from VM snapshot

---

### Storage Architecture

**ZFS Pools** (N5 only):
- **ai**: 3.62TB NVMe (fast, AI/ML workloads)
- **vms**: 1.86TB SSD (medium, VM disks, databases)
- **tank**: 18.2TB HDD (bulk, media, backups)

**Kubernetes Integration**: OpenEBS ZFS LocalPV CSI driver

**CSI Driver**: OpenEBS ZFS LocalPV (CNCF Sandbox project)

**StorageClasses** (per ZFS pool/tier):

```yaml
# AI Tier (NVMe - Fast)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: zfs-ai
provisioner: zfs.csi.openebs.io
parameters:
  poolname: "ai"
  fstype: "zfs"
  compression: "lz4"        # Inherited from pool
  dedup: "off"
  thinprovision: "yes"
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain

# VMs Tier (SSD - Medium, for zvols/block devices)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: zfs-vms
provisioner: zfs.csi.openebs.io
parameters:
  poolname: "vms"
  fstype: "ext4"            # Creates zvol (block device)
  compression: "lz4"        # Inherited from pool
  dedup: "off"
  thinprovision: "yes"
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain

# Tank Tier (HDD - Bulk)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: zfs-tank
provisioner: zfs.csi.openebs.io
parameters:
  poolname: "tank"
  fstype: "zfs"
  compression: "lz4"        # Inherited from pool
  dedup: "off"
  thinprovision: "yes"
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
```

**Note**: StorageClasses inherit pool properties (compression=lz4, recordsize=128K, atime=off from pool defaults). No custom overrides applied to preserve data consistency with existing datasets.

**Home Assistant VM Storage**:
- Existing zvol: `vms/HomeAssistant` (128GB, will expand to 256GB)
- Migration approach: Static PV pointing to existing zvol
- Managed by KubeVirt via PVC

**Features**:
- Volume snapshots (VolumeSnapshot CRD)
- Volume cloning (instant ZFS clones)
- Volume expansion (online resize)
- CRD observability (ZFSVolume, ZFSNode, ZFSSnapshot)

---

## Application Architecture

### Virtualization: KubeVirt (homelab-cluster only)

**Purpose**: Manage VMs (Home Assistant) as Kubernetes resources

**Deployment**: homelab-cluster on N5 only (VMs require ZFS storage)

**Components**:
- KubeVirt operator
- CDI (Containerized Data Importer) for disk management
- KubeVirt Manager (web UI, optional) - accessible via Traefik ingress
- Multus CNI (REQUIRED for multi-network attachment)

**Networking (Dual-Interface Configuration):**

**Primary Interface (eth0):**
- Binding: masquerade (kube-router pod network)
- Purpose: Pod-to-pod communication (OAuth with pocket-id, cluster services)
- IP: Dynamic pod IP (10.x.x.x range)

**Secondary Interface (eth1):**
- Binding: bridge (via Multus NetworkAttachmentDefinition)
- Bridge: `bridge64` (IoT VLAN bridge on eno1.64 - 5G NIC)
- IP: `192.168.64.2/20` (static, configured via cloud-init)
- Purpose: IoT VLAN access for device discovery (mDNS, ARP, SSDP)
- Gateway: `192.168.64.1` (N5 bridge64)
- DNS: `192.168.4.53` (AdGuard Home on VLAN 4)

**NetworkAttachmentDefinition:**
```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: iot-vlan-bridge
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "bridge",
      "bridge": "bridge64",
      "disableContainerInterface": true,
      "macspoofchk": true
    }
```

**Rationale:**
- Multus is **required** - KubeVirt secondary networks only work with Multus
- Bridge binding is **required** - only way to support Layer 2 protocols (mDNS/SSDP/ARP)
- Dual network allows both cluster communication AND IoT device discovery
- Static IP via cloud-init (not CNI IPAM) for full control
- Preserves existing libvirt networking behavior

**Storage**:
- VM disks backed by ZFS zvols (vms pool)
- Home Assistant: Static PV pointing to existing `vms/HomeAssistant` zvol (128GB)

### Networking

**CNI**: kube-router (k0s default)
- Native Linux networking, no overlay by default
- Network policy support built-in
- Lighter weight than Calico

**Ingress**: Traefik v3 (per-cluster deployment via Helm)

**cloud-cluster (VPS):**
- Serves VPS-native services directly (Uptime Kuma, monitoring)
- Catch-all IngressRoute: `*.jax-lab.dev` → proxy to homelab-cluster via Twingate
- Let's Encrypt HTTP-01 certificates (VPS is publicly accessible)

**homelab-cluster (N5):**
- Serves N5 services (Home Assistant, AdGuard, internal apps)
- Let's Encrypt DNS-01 certificates (behind NAT)
- Accessible locally during partition

**sandbox-cluster (N5):**
- Independent Traefik instance for testing
- No production traffic routing

**DNS Automation**: external-dns
- **Cloudflare Provider**: Auto-create A/CNAME records from Ingress resources
  - Removes need for wildcard `*.jax-lab.dev` CNAME
  - Creates explicit records: `home.jax-lab.dev`, `uptime.jax-lab.dev`, etc.
- **AdGuard Home Provider**: Auto-create DNS rewrites for split-horizon
  - Internal clients get Traefik LoadBalancer IP (`192.168.8.50`) for services
  - External clients get VPS IP (`85.31.234.30`)

**Multi-attach Networking**: Multus CNI
- Allows VMs to attach to `bridge64` (eno1.64) for IoT VLAN access

**Twingate Integration**:
- VPS can access N5 services via `192.168.0.0/16` route
- No changes to existing Twingate connector/client setup

**Split-Horizon DNS**:
- AdGuard Home rewrites maintained (`home.jax-lab.dev` → `192.168.8.50`)
- Internal clients bypass VPS, external clients hit VPS reverse proxy

---

## Service Migration Strategy

### Phase Approach (High-Level)

**Phase 1**: Foundation
- Install k3s on N5 (and/or VPS)
- Install OpenEBS ZFS CSI, KubeVirt, Multus
- Verify Traefik ingress working

**Phase 2**: Test Workload
- Migrate one simple service (e.g., Uptime Kuma)
- Validate DNS, ingress, certificates
- Build confidence

**Phase 3**: VM Migration
- Import Home Assistant zvol as static PV
- Create KubeVirt VM definition
- Migrate to KubeVirt (cutover)

**Phase 4**: Remaining Services
- Migrate other Dokploy containers
- Decommission Dokploy

---

## Declarative Infrastructure Management

### DNS Management (external-dns)

**Goal**: Manage DNS records through Kubernetes Ingress annotations

**Architecture**:
```
Kubernetes Ingress/Service
    ↓ (watches)
external-dns controller
    ↓ (creates/updates)
    ├─ Cloudflare API (public DNS)
    └─ AdGuard Home API (split-horizon DNS)
```

**Example Workflow**:
```yaml
# Create Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: home-assistant
  annotations:
    external-dns.alpha.kubernetes.io/target: "85.31.234.30"  # VPS IP
    external-dns.alpha.kubernetes.io/internal-target: "192.168.8.50"  # Traefik LoadBalancer
spec:
  rules:
    - host: home.jax-lab.dev
```

**What happens**:
1. external-dns (Cloudflare provider) creates: `home.jax-lab.dev A 85.31.234.30`
2. external-dns (AdGuard provider) creates DNS rewrite: `home.jax-lab.dev → 192.168.8.50`
3. Delete Ingress → DNS records auto-removed

**Providers**:
- `external-dns` with Cloudflare provider (official, built-in)
- `external-dns` with AdGuard Home webhook provider: `muhlba91/external-dns-provider-adguard`
  - Deploys as sidecar container alongside external-dns
  - Manages DNS rewrites via AdGuard Home filtering rules
  - Supports A, AAAA, CNAME, TXT, SRV, NS, PTR, MX records
  - OCI image: `ghcr.io/muhlba91/external-dns-provider-adguard`

**Implementation**:
- Two external-dns deployments:
  1. **external-dns-cloudflare** (VPS): Manages public DNS records
  2. **external-dns-adguard** (N5): Manages split-horizon DNS rewrites

**Note**: AdGuard provider takes ownership of matching dnsrewrite rules. Manual DNS rewrites should be defined as DNSEndpoint CRDs to avoid conflicts.

---

### VM Management (KubeVirt)

**Goal**: Define VMs as Kubernetes resources, version controlled

**Example Home Assistant VM**:
```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: homeassistant
  namespace: vms
spec:
  running: true
  template:
    metadata:
      labels:
        app: homeassistant
    spec:
      domain:
        cpu:
          cores: 2
        devices:
          disks:
            - name: root
              disk:
                bus: virtio
          interfaces:
            - name: default
              masquerade: {}
            - name: services-vlan
              bridge: {}
        resources:
          requests:
            memory: 4Gi
      networks:
        - name: default
          pod: {}
        - name: iot-vlan
          multus:
            networkName: iot-vlan-bridge
      volumes:
        - name: root
          persistentVolumeClaim:
            claimName: homeassistant-disk
```

**Benefits**:
- VM definition in Git
- `kubectl apply -f homeassistant-vm.yaml` to create/update
- Version control VM config changes
- CI/CD can validate VM definitions

---

### ZFS Dataset Management

**Challenge**: ZFS pools/datasets are not natively Kubernetes resources

**Approach Options**:

**Option 1: OpenEBS ZFS CSI (Dynamic Provisioning)**
- PVCs automatically create ZFS datasets/zvols
- Limited control over dataset properties
- Works well for ephemeral workloads

**Option 2: Static PVs with Pre-created Datasets**
- Manually create ZFS datasets with desired properties
- Create Kubernetes PV pointing to dataset
- Full control over ZFS features (compression, recordsize, etc.)

**Option 3: ZFS Operator (Custom Controller)**
- Create CRD for ZFS datasets
- Controller reconciles desired state
- **Does not exist yet** - would need to build

**DECISION NEEDED**: Start with Option 2 (static PVs), evaluate Option 3 if needed

**Example Static PV Workflow**:
```bash
# Create ZFS dataset with desired properties
zfs create -o compression=lz4 -o recordsize=1M tank/media-library

# Create PV pointing to it
apiVersion: v1
kind: PersistentVolume
metadata:
  name: media-library
spec:
  capacity:
    storage: 5Ti
  volumeMode: Filesystem
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: zfs-tank
  local:
    path: /tank/media-library
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values: [n5]
```

**Future**: Could build Kubernetes operator to manage ZFS declaratively via CRDs

---

## GitOps Architecture

### Tool: Flux CD (v2) + Weave GitOps UI

**Flux Components**:
- source-controller (Git repository sync)
- kustomize-controller (Kustomization reconciliation)
- helm-controller (HelmRelease management)
- notification-controller (Events/alerts)

**Weave GitOps UI** (~50MB additional):
- Web dashboard for Flux resources
- Shows sync status, diffs, reconciliation errors
- Read-mostly UI (discourages manual changes)
- Access: `https://gitops.jax-lab.dev` (via Traefik ingress)

**Why Flux + Weave over ArgoCD**:
- Lighter weight (~250MB total vs ~550MB for ArgoCD)
- Native Cluster API support (k0smotron integration)
- Modular architecture (can disable unused controllers)
- Pure declarative with optional UI visibility
- Weave GitOps addresses "hard to visualize sync status" concern

### Repository Structure (Monorepo)

```
homelab-gitops/
├── flux-system/              # Flux installation
├── infrastructure/
│   ├── base/                 # Shared configs
│   │   ├── storage/         # OpenEBS ZFS
│   │   ├── networking/      # Traefik, external-dns
│   │   └── kubevirt/        # VM operator
│   └── overlays/
│       ├── homelab/         # N5-specific
│       ├── cloud/           # VPS-specific
│       └── sandbox/         # Testing
├── apps/
│   ├── home-assistant/
│   ├── traefik/
│   └── adguard-home/
├── clusters/                 # k0smotron cluster definitions
│   ├── homelab-cluster.yaml
│   ├── cloud-cluster.yaml
│   └── sandbox-cluster.yaml
└── secrets/                  # Encrypted with Sealed Secrets
    ├── homelab-secrets.yaml
    └── cloud-secrets.yaml
```

### Secrets Management: Sealed Secrets

**Approach**: Encrypt secrets before committing to Git
- Each cluster has its own sealing key
- Secrets decrypted at apply time by sealed-secrets controller
- No external dependencies (no Vault, no cloud KMS)

**Workflow**:
```bash
# Create secret, seal it, commit encrypted version
echo -n "token" | kubectl create secret generic api-token \
  --from-file=- --dry-run=client -o yaml | \
  kubeseal > secrets/sealed/api-token.yaml

git add secrets/sealed/api-token.yaml
git commit -m "Add API token"
```

### Progressive Delivery

**Pattern**: sandbox → cloud → homelab

- **sandbox-cluster**: Latest/experimental versions (immediate sync)
- **cloud-cluster**: Staging (tested in sandbox first)
- **homelab-cluster**: Production (stable, tested in cloud first)

**Implementation**: Use Flux dependencies and sync intervals per cluster

### Bootstrap Process

```bash
# On management cluster (N5)
flux bootstrap github \
  --owner=yourusername \
  --repo=homelab-gitops \
  --path=flux-system \
  --personal \
  --private=true

# Flux creates:
# - flux-system namespace
# - GitRepository pointing to repo
# - Kustomization for Flux components
# - SSH deploy key in GitHub
```

### Recovery

**If Flux controller fails**: Auto-recovers within 5m (reconciliation interval)

**If entire management cluster lost**:
1. Rebuild k0s management cluster
2. Re-run `flux bootstrap` (same repo)
3. Restore sealed-secrets keys from backup
4. Git history rebuilds everything automatically

---

## Open Questions & Decisions Needed

### 1. Cluster Topology
- [x] **DECISION**: k0smotron on N5 managing 3 independent clusters
  - **homelab-cluster**: N5 workers (VMs, storage, internal services)
  - **cloud-cluster**: VPS workers (public-facing services)
  - **sandbox-cluster**: N5 workers (experiments, testing)
- [x] All control planes as pods on N5 management cluster
- [x] Cross-cluster communication via Twingate (explicit dependencies)

### 2. Networking
- [x] **DECISION**: Use kube-router (k0s default CNI)
  - **Rationale**: Default = less config, native Linux networking (no overlay), lighter weight
  - Network policy support available if needed
  - Twingate confirmed CNI-agnostic (works with any CNI)

### 3. Traefik Version & Architecture
- [x] **DECISION**: Install Traefik v3 via Helm in each cluster
- [x] **DECISION**: Dual-Traefik architecture (per-cluster deployment)
  - **cloud-cluster** (VPS): Public ingress + catch-all proxy to homelab Traefik at 192.168.8.50
  - **homelab-cluster** (N5): Internal services + DNS-01 certificates at 192.168.8.50 (VLAN 8)
  - **sandbox-cluster** (N5): Independent ingress for testing
- [x] **Rationale**:
  - Partition resilience (N5 Traefik accessible locally during outage)
  - No unnecessary hops (VPS serves VPS resources directly)
  - VPS routes wildcard `*.jax-lab.dev` to Traefik LoadBalancer via Twingate

### 4. Storage
- [x] **DECISION**: Use OpenEBS ZFS LocalPV CSI driver
  - **Rationale**: CNCF-backed, simple config, multi-pool support, CRD observability
  - StorageClass per pool/tier (ai/vms/tank)
  - Dynamic provisioning for new workloads
  - Static PV for existing Home Assistant zvol
- [x] **DECISION**: Expand Home Assistant zvol to 256GB before migration
  - Currently 130GB used of 128GB (over capacity)
- [x] **Alternative evaluated**: democratic-csi (better for TrueNAS, not needed here)

### 5. Sandbox Strategy
- [x] **DECISION**: Sandbox-cluster via k0smotron (true cluster isolation)
  - Independent failure domain from homelab-cluster
  - Safe to break without affecting production

### 6. GitOps Strategy
- [x] **DECISION**: Flux CD (v2) + Weave GitOps UI
  - **Rationale**: Lightweight, native k0smotron support, declarative-first
  - **UI**: Weave GitOps for visibility/observability (addresses Flux CLI-only concerns)
  - **Repository**: Monorepo structure with overlays per cluster
  - **Secrets**: Sealed Secrets (no external dependencies, per-cluster keys)
  - **Progressive delivery**: sandbox → cloud → homelab
  - **Bootstrap**: `flux bootstrap github` on management cluster
  - **Future**: Can add Kubero/Agnost for Railway-like app deployments if needed

### 7. Monitoring & Observability
- [ ] Prometheus/Grafana stack?
- [ ] Continue using Uptime Kuma or switch to k8s-native monitoring?

---

## Design Principles

1. **Declarative Everything**: Infrastructure, DNS, VMs, and storage as code
2. **Incremental Migration**: Don't replace everything at once
3. **Network Segmentation**: VLAN-based architecture isolates services, infrastructure VIPs, and IoT networks
4. **Retain Policies**: ZFS retain policy (don't delete datasets on PVC deletion)
5. **GitOps-Ready**: All configs in YAML, version controlled
6. **Failure Domains**: Understand what breaks if N5 or VPS goes down

---

## Current vs Future State

### Current (Dokploy)
```
VPS (Dokploy)                          N5 (Dokploy)
├─ Traefik                             ├─ Traefik
├─ Uptime Kuma                         ├─ AdGuard Home
└─ Public services                     ├─ Home Assistant (libvirt VM)
                                       └─ Internal services
        ↕ (Twingate tunnel)
```

### Future (Kubernetes)
```
VPS (k3s worker?)                      N5 (k3s control+worker?)
├─ Traefik (Ingress)                   ├─ KubeVirt
├─ Uptime Kuma (pod)                   │  └─ Home Assistant VM
└─ Public services (pods)              ├─ AdGuard Home (pod)
                                       ├─ OpenEBS ZFS CSI
                                       └─ Internal services (pods)
        ↕ (Twingate tunnel, unchanged)
```

---

## Next Steps

1. **Review & Decide**: Go through "Open Questions" section
2. **Validate Assumptions**: Confirm ZFS dataset strategy, networking requirements
3. **Design Refinement**: Finalize cluster topology, component choices
4. **Migration Plan**: Create detailed runbook (separate document)

---

## Notes

- Document created: 2025-10-28
- Contributors: Jax + Claude
- Related docs: `CLAUDE.md` (current architecture)
