# Mobius Homelab

## Overview
Hybrid homelab infrastructure spanning on-premises Kubernetes cluster and cloud VPS, connected via Twingate VPN.

**Documentation:**
- **Network Topology:** See [`docs/lab-network.md`](docs/lab-network.md) for detailed network inventory
- **Home Assistant VM:** See [`docs/lab-vm-haos.md`](docs/lab-vm-haos.md) for VM configuration and management
- **Repository:** Infrastructure-as-Code using GitOps (Flux CD)

## Quick Reference

### Infrastructure
- **VPS:** `cloud.jax-lab.dev` (85.31.234.30) - Dokploy platform, Ubuntu 24.04.3 LTS
- **N5:** `n5.jax-lab.dev` (192.168.4.5) - k0s control-plane, AMD Ryzen AI 9 HX PRO 370, 91GB RAM
- **M1-ubuntu:** `m1-ubuntu.local` (192.168.4.81) - k0s worker node

### Access
- **SSH:** Key-based authentication
  - VPS: `ssh root@cloud.jax-lab.dev`
  - N5: `ssh jax@192.168.4.5` (passwordless sudo)
- **Kubernetes:** `kubectl` configured for N5 cluster
- **Domain:** `jax-lab.dev` (Cloudflare DNS)

### Network (Multi-VLAN)
- **VLAN 1** (192.168.4.0/24): Infrastructure - k0s nodes, SSH, services
- **VLAN 8** (192.168.8.0/24): LoadBalancer VIPs - Traefik, applications
- **VLAN 16** (192.168.16.0/20): Sandbox - Reserved for untrusted workloads
- **VLAN 64** (192.168.64.0/20): IoT - Home Assistant, smart devices

### Key Services
- **AdGuard Home:** `192.168.4.53` (DNS) - `https://dns.jax-lab.dev`
- **Traefik:** `192.168.8.50` (Ingress) - Kubernetes LoadBalancer
- **Home Assistant:** `192.168.64.2:8123` (VM) - `https://home.jax-lab.dev`
- **Uptime Kuma:** `https://uptime.jax-lab.dev` (VPS monitoring)
- **Dokploy:** `https://dokploy.jax-lab.dev` (VPS container platform)

## Repository Structure

### Configuration Files
- **`bootstrap/`** - Infrastructure bootstrap configs
  - `n5-netplan.yaml` - N5 network configuration (netplan)
  - `homelab-k0sctl.yaml` - k0s cluster configuration
  - `metallb-config.yaml` - MetalLB LoadBalancer pools
  - `homelab-storageclasses.yaml` - OpenEBS ZFS StorageClasses
  - `homeassistant-vm.xml` - Home Assistant VM libvirt definition
- **`k8s/`** - Kubernetes manifests (Flux CD GitOps)
  - `clusters/lab/` - Homelab cluster configuration
  - `clusters/lab/flux-system/` - Flux CD system components
  - `clusters/lab/infrastructure-config/` - Infrastructure services (MetalLB, Traefik, AdGuard)
  - `clusters/lab/apps/` - Application deployments

### Documentation
- **`docs/lab-network.md`** - Complete network topology and IP inventory
- **`docs/lab-vm-haos.md`** - Home Assistant VM configuration and management
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

### Access Services
```bash
# DNS query via AdGuard
dig @192.168.4.53 google.com

# Test Traefik (with split-horizon DNS or --resolve)
curl -k https://dns.jax-lab.dev
curl -k --resolve dns.jax-lab.dev:443:192.168.8.50 https://dns.jax-lab.dev

# SSH to hosts
ssh jax@192.168.4.5        # N5
ssh jax@192.168.4.81       # M1-ubuntu
ssh root@cloud.jax-lab.dev # VPS
```

## Recent Changes

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
