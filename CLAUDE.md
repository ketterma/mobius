# Mobius Homelab

## Overview
Hybrid homelab infrastructure spanning on-premises Kubernetes cluster and cloud VPS, connected via Twingate VPN.

**Documentation:**
- **Network Topology:** See [`docs/lab-network.md`](docs/lab-network.md) for detailed network inventory
- **Home Assistant VM:** See [`docs/lab-vm-haos.md`](docs/lab-vm-haos.md) for VM configuration and management
- **Repository:** Infrastructure-as-Code using GitOps (Flux CD)

## Quick Reference

### Infrastructure
- **PHX:** `phx.jaxon.cloud` (85.31.234.30) - Cloud VPS in Phoenix, AZ. Single-node k0s cluster (Ubuntu 24.04), public ingress gateway with Traefik, Twingate VPN connector to homelab
- **N5:** `n5.jax-lab.dev` (192.168.4.5) - On-premises k0s control-plane, AMD Ryzen AI 9 HX PRO 370, 91GB RAM
- **M1-ubuntu:** `m1-ubuntu.local` (192.168.4.81) - On-premises k0s worker node

### Access
- **SSH:** Key-based authentication
  - PHX: `ssh root@85.31.234.30`
  - N5: `ssh jax@192.168.4.5` (passwordless sudo)
- **Kubernetes:** `kubectl` contexts for both `phx-jaxon-cloud` and `homelab` clusters
- **Domain:** `jaxon.cloud` (Cloudflare DNS, public), `jaxon.home` (internal)

### Network (Multi-VLAN)
- **VLAN 1** (192.168.4.0/24): Infrastructure - k0s nodes, SSH, services
- **VLAN 8** (192.168.8.0/24): LoadBalancer VIPs - Traefik, applications
- **VLAN 16** (192.168.16.0/20): Sandbox - Reserved for untrusted workloads
- **VLAN 64** (192.168.64.0/20): IoT - Home Assistant, smart devices

### Key Services
- **AdGuard Home:** `192.168.4.53` (DNS) - `https://dns.jaxon.home`
- **Traefik (Homelab):** `192.168.8.50` (Ingress) - Kubernetes LoadBalancer
- **Traefik (PHX):** `85.31.234.30` (Public Ingress) - Kubernetes LoadBalancer
- **Home Assistant:** `192.168.64.2:8123` (VM) - `https://home.jaxon.home`
- **Pocket-ID:** Authentication service - `https://auth.jaxon.home`
- **Twingate:** VPN connector on PHX bridging to homelab

## Repository Structure

### Configuration Files
- **`bootstrap/`** - Infrastructure bootstrap configs
  - `n5-netplan.yaml` - N5 network configuration (netplan)
  - `homelab-k0sctl.yaml` - Homelab k0s cluster configuration
  - `phx-k0sctl.yaml` - PHX k0s cluster configuration
  - `metallb-config.yaml` - MetalLB LoadBalancer pools
  - `homelab-storageclasses.yaml` - OpenEBS ZFS StorageClasses
  - `homeassistant-vm.xml` - Home Assistant VM libvirt definition
- **`k8s/`** - Kubernetes manifests (Flux CD GitOps)
  - `clusters/lab/` - Homelab cluster configuration
    - `flux-system/` - Flux CD system components
    - `infrastructure-config/` - Infrastructure services (MetalLB, Traefik, AdGuard)
    - `apps/` - Application deployments (AdGuard, Pocket-ID)
  - `clusters/phx/` - PHX cloud cluster configuration
    - `flux-system/` - Flux CD system components
    - `infrastructure/` - Infrastructure overlays (Traefik, MetalLB, External-DNS)
    - `infrastructure-config/` - MetalLB IP pools, Twingate connector

### Documentation
- **`docs/lab-network.md`** - Complete network topology and IP inventory
- **`docs/lab-vm-haos.md`** - Home Assistant VM configuration and management
- **`docs/jaxon-cloud-architecture.md`** - PHX cloud architecture and multi-cluster design
- **`CLAUDE.md`** - This file (repository overview)

## Technologies

### Kubernetes Stack
- **Distribution:** k0s v1.32.8 (minimal Kubernetes)
- **CNI:** kube-router (default, no custom configuration)
- **GitOps:** Flux CD (continuous deployment from Git)
- **LoadBalancer:** MetalLB (L2 mode, ARP-based)
- **Ingress:** Traefik v3 (Let's Encrypt DNS-01 via Cloudflare)
- **Storage:** OpenEBS ZFS LocalPV (3x ZFS pools)
- **DNS:** AdGuard Home (split-horizon DNS, ad-blocking)

### Security
- **OS:** Ubuntu 24.04.3 LTS with Ubuntu Pro (extended security, livepatch)
- **Secrets:** Mozilla SOPS with age encryption (encrypted secrets in Git)
- **VPN:** Twingate (zero-trust network access between VPS and homelab)
- **Certificates:** Let's Encrypt (automated via Traefik)

### Infrastructure
- **Gateway:** UniFi Dream Machine Pro (UDM Pro) - VLANs, routing, firewall
- **Switch:** USW-24-Pro-HD - 10G SFP+ uplink to N5
- **Virtualization:** KVM/libvirt (Home Assistant VM on dedicated IoT VLAN)

## Important Notes

### VLAN Interface Routing
**Critical:** VLAN interfaces on N5 require IP addresses for proper routing. Without them, MetalLB LoadBalancer IPs are unreachable from other networks because the kernel cannot route packets arriving on VLAN interfaces.

Current configuration:
- `enp197s0` (VLAN 1, untagged): `192.168.4.5/24` ✓
- `enp197s0.8` (VLAN 8): `192.168.8.254/24` ✓ (required for Traefik LoadBalancer routing)
- `enp197s0.16` (VLAN 16): `192.168.16.254/20` ✓ (required for future sandbox workloads)

### Split-Horizon DNS
AdGuard Home provides DNS rewrites so internal clients resolve `*.jax-lab.dev` to internal Traefik IP (`192.168.8.50`) instead of the public VPS IP. This provides:
- Faster response times (no external hop)
- Reduced load on VPS and Twingate tunnel
- Same Let's Encrypt certificates work for both internal and external access

### MetalLB L2 Mode
MetalLB uses Layer 2 (ARP) to advertise LoadBalancer IPs on specific VLAN interfaces:
- `l2-vlan4`: Advertises `192.168.4.50-59` on `enp197s0` (VLAN 1)
- `l2-vlan8`: Advertises `192.168.8.50-79` on `enp197s0.8` (VLAN 8)

Only N5 advertises LoadBalancer IPs (specified via `nodeSelectors`). For high availability, M1-ubuntu would need matching VLAN interfaces and L2Advertisements.

### SOPS Encryption
Sensitive secrets (e.g., Cloudflare API token) are encrypted using SOPS with age encryption:
- Age public key: `age1hhwgd0zzsuqrg7gad42kh547lkgfeqsu03uql375uzslz0vqc37sknuux0`
- Age private key: Derived from SSH Ed25519 key using `ssh-to-age`
- Flux automatically decrypts secrets during deployment

### External-DNS with Traefik IngressRoutes

**IMPORTANT:** External-DNS is configured on BOTH clusters and automatically manages DNS records. **DO NOT manually create DNS rewrites in AdGuard Home or Cloudflare** - they are automatically created from IngressRoute annotations.

**Homelab Cluster (AdGuard Home via webhook):**
For external-dns to automatically create DNS rewrites in AdGuard Home from Traefik IngressRoutes, **both** annotations are required:
- `external-dns.alpha.kubernetes.io/hostname: <domain>` - Specifies the DNS hostname to create
- `external-dns.alpha.kubernetes.io/target: <ip>` - Specifies the target IP address (typically `192.168.8.50` for Traefik)

Example (homelab):
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  annotations:
    external-dns.alpha.kubernetes.io/hostname: leantime.jaxon.cloud
    external-dns.alpha.kubernetes.io/target: 192.168.8.50
```

**PHX Cluster (Cloudflare API):**
For external-dns to automatically create DNS records in Cloudflare from Traefik IngressRoutes, **both** annotations are required:
- `external-dns.alpha.kubernetes.io/hostname: <domain>` - Specifies the DNS hostname to create
- `external-dns.alpha.kubernetes.io/target: <ip>` - Specifies the target IP address (typically `85.31.234.30` for PHX public IP)

**Without the `target` annotation, external-dns will NOT create DNS records** even though it's watching the IngressRoute resource.

## Common Tasks

### Deploy Configuration Changes
```bash
# Commit and push changes
git add .
git commit -m "Description of changes"
git push

# Flux will automatically reconcile (or force it)
flux reconcile source git flux-system
flux reconcile kustomization infrastructure-config
```

### Check Service Status
```bash
# List all LoadBalancer services
kubectl get svc -A | grep LoadBalancer

# Check MetalLB
kubectl -n metallb-system get pods
kubectl -n metallb-system get ipaddresspools
kubectl -n metallb-system get l2advertisements

# Check Flux
flux get kustomizations
flux get helmreleases
```

### Update N5 Network Configuration
```bash
# Edit netplan on N5
ssh jax@192.168.4.5
sudo nano /etc/netplan/01-netcfg.yaml

# Apply changes
sudo netplan apply

# Verify interfaces
ip addr show
ip route show
```

### Clear AdGuard Home DNS Cache
```bash
# Clear DNS cache via API (useful when AdGuard caches NXDOMAIN responses)
curl -X POST -H "Content-Type: application/json" https://dns.jaxon.cloud/control/cache_clear
```

### Access Services
```bash
# DNS query via AdGuard
dig @192.168.4.53 google.com

# Test Traefik (with split-horizon DNS or --resolve)
curl -k https://dns.jax-lab.dev
curl -k --resolve dns.jax-lab.dev:443:192.168.8.50 https://dns.jax-lab.dev

# SSH to hosts
ssh jax@192.168.4.5    # N5
ssh jax@192.168.4.81   # M1-ubuntu
ssh root@85.31.234.30  # PHX
```

## Recent Changes

### 2025-11-08: Twingate Headless Client Deployment to PHX
- ✅ Deployed Twingate headless client as DaemonSet on PHX cluster for accessing homelab resources
- ✅ Implemented Ubuntu-based deployment with official Twingate installer
- ✅ Fixed DNS resolution by using host DNS policy instead of cluster DNS
- ✅ Service key SOPS-encrypted and mounted correctly
- ✅ **Full connectivity verified**: TCP, UDP, and ICMP all working
- ✅ Configured `ping_group_range` sysctl on N5 for ICMP/ping support
- ✅ Fixed kubectl context: removed broken `phx-jaxon-cloud`, renamed to `phx`
- ✅ Documentation: [`docs/twingate-icmp-setup.md`](docs/twingate-icmp-setup.md) - ICMP configuration guide

**Key learnings:**
1. **DNS policy critical for external connectivity** - Use `dnsPolicy: Default` with hostNetwork for Twingate client to resolve controller domains
2. **ICMP requires sysctl configuration** - Set `net.ipv4.ping_group_range = 0 2147483647` on connector nodes (official Twingate recommendation)
3. **Service key mounting** - Mount at non-conflicting path (`/twingate-key/`) to avoid read-only issues with `/etc/twingate`
4. **Ping works but some hosts block ICMP** - TCP/UDP connectivity is what matters; ICMP ping is bonus

**PHX→Homelab connectivity verified:**
- DNS queries: `dig @192.168.4.53` ✅
- HTTP/HTTPS: AdGuard, Traefik working ✅
- ICMP ping: N5 (192.168.4.5) responding ✅
- Latency: ~50ms average via Twingate tunnel

### 2025-11-07: Data Recovery & Clean Slate Recovery
- ✅ Recovered from accidental deletion of apps kustomization (which garbage collected all apps)
- ✅ Created ZFS snapshots before recovery (`pre-flux-restore-20251107-001809`)
- ✅ Backed up AdGuard and Pocket-ID data to `/home/jax/homelab-backups/20251107-005754/`
- ✅ Cleaned up all manual PV/PVC manifests and orphaned ZFS datasets
- ✅ Let apps redeploy with fresh dynamic PVC provisioning
- ✅ Successfully restored data from backups
- ✅ Removed Open-WebUI and Supabase (not needed)

**Critical lessons learned:**
1. **NEVER delete Flux kustomizations without understanding garbage collection** - Flux will delete ALL managed resources when a kustomization is removed
2. **Always create ZFS snapshots BEFORE any destructive operations** - Snapshots saved us from total data loss
3. **Always create file-based backups in addition to snapshots** - Tar backups to `/home/jax/homelab-backups/` for easy restoration
4. **Verify volume mappings carefully** - Check actual file contents, not just sizes, when mapping PVCs to existing volumes
5. **Don't rush destructive commands** - Take time to verify what will be affected before deleting PVs, PVCs, or ZFS datasets
6. **PV reclaim policy matters** - Set to `Retain` during recovery to prevent accidental data loss
7. **Flux can get stuck on old revisions** - Sometimes need to delete and recreate kustomizations to force new revision
8. **OpenEBS ZFS uses UUID naming** - Cannot customize dataset names for dynamically provisioned volumes (use `pvc-{uuid}`)
9. **Home Assistant needs external DNS names** - Not Kubernetes service names for OAuth providers

**Recovery checklist for future incidents:**
1. Immediately suspend Flux: `flux suspend kustomization apps`
2. Create ZFS snapshots: `sudo zfs snapshot -r vms/homelab@emergency-$(date +%Y%m%d-%H%M%S)`
3. Create file backups of critical data to `/home/jax/homelab-backups/`
4. Change PV reclaim policy to Retain: `kubectl patch pv <name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'`
5. Never delete datasets until you're 100% sure they're not needed

### 2025-11-01: VLAN Migration & Routing Fix
- ✅ Migrated from single-VLAN (192.168.8.x) to multi-VLAN architecture
- ✅ Fixed MetalLB routing by adding IP addresses to VLAN interfaces
- ✅ Deployed k0s cluster with Flux CD GitOps
- ✅ Migrated AdGuard Home and Pocket-ID to Kubernetes
- ✅ Configured split-horizon DNS via AdGuard Home
- ✅ Fixed SOPS decryption for secrets (Cloudflare API token)
- ✅ Removed legacy Docker Traefik and obsolete bridge configurations

**Key learnings:**
- VLAN interfaces without IP addresses cannot route packets properly
- MetalLB L2 announcements require host IPs on VLAN interfaces for cross-VLAN access
- Used VLAN 1 (untagged) instead of VLAN 4 (tagged) for simpler configuration
