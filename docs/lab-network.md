# Homelab Network Topology & Configuration

**Last Updated:** 2025-11-01

## Network Architecture

### VLANs

| VLAN | Network | Purpose | Gateway | Notes |
|------|---------|---------|---------|-------|
| 1 | 192.168.4.0/24 | Infrastructure (untagged) | 192.168.4.1 | Services, k0s nodes, SSH, NAS |
| 8 | 192.168.8.0/24 | MetalLB Services | 192.168.8.1 | LoadBalancer VIPs only |
| 16 | 192.168.16.0/20 | Sandbox/Untrusted | 192.168.16.1 | Reserved for future use |
| 64 | 192.168.64.0/20 | IoT | 192.168.64.1 | IoT devices, VMs |

## Hardware Inventory

### Cloud VPS (Hostinger)
- **Hostname:** `cloud.jax-lab.dev`
- **Public IP:** `85.31.234.30`
- **CPU:** AMD EPYC 9354P (2 vCPU, 1 thread/core)
- **RAM:** 7.8 GB
- **OS:** Ubuntu 24.04.3 LTS (Ubuntu Pro)
- **Platform:** Dokploy (Docker-based orchestration)
- **User:** `root` (SSH key auth)

### N5 Server (On-Premises Controller)
- **Hostname:** `n5.jax-lab.dev`
- **IP:** `192.168.4.5` (VLAN 1, untagged)
- **CPU:** AMD Ryzen AI 9 HX PRO 370 w/ Radeon 890M (24 cores, 48 threads)
- **RAM:** 91 GB
- **OS:** Ubuntu 24.04.3 LTS (Ubuntu Pro)
- **Kernel:** 6.14.0-33-generic
- **Platform:** Kubernetes (k0s v1.32.8+k0s, control-plane + worker)
- **User:** `jax` (passwordless sudo, SSH key auth)

#### N5 Network Interfaces
| Interface | Type | VLAN | IP | Purpose |
|-----------|------|------|-------|---------|
| `enp197s0` | 10G Physical | 1 (untagged) | 192.168.4.5/24 | Host IP, default route, k0s traffic |
| `enp197s0.8` | VLAN sub-if | 8 | 192.168.8.254/24 | MetalLB L2 routing |
| `enp197s0.16` | VLAN sub-if | 16 | 192.168.16.254/20 | Sandbox routing (future) |
| `eno1` | 5G Physical | - | No IP | Bridge master for IoT |
| `eno1.64` | VLAN sub-if | 64 | No IP | IoT VLAN (attached to bridge64) |
| `bridge64` | Bridge | 64 | 192.168.64.1/20 | IoT network gateway |
| `bridge0` | CNI Bridge | - | 10.244.0.1/24 | kube-router pod network |

### M1-ubuntu Server (Worker Node)
- **Hostname:** `m1-ubuntu.local`
- **IP:** `192.168.4.81` (VLAN 1, untagged)
- **OS:** Ubuntu 24.04.3 LTS
- **Kernel:** 6.8.0-86-generic
- **Platform:** Kubernetes (k0s v1.32.8+k0s, worker only)
- **Interface:** `enp0s1` (192.168.4.81/24)

### Home Assistant VM
- **IP:** `192.168.64.2`
- **Network:** VLAN 64 (IoT)
- **Gateway:** `192.168.64.1` (N5 bridge64)
- **Connection:** KVM/libvirt via `vnet1` → `bridge64`

### UDM Pro (Gateway)
- **Model:** UniFi Dream Machine Pro
- **Gateway IPs:**
  - VLAN 1: `192.168.4.1`
  - VLAN 8: `192.168.8.1`
  - VLAN 16: `192.168.16.1`
  - VLAN 64: `192.168.64.1` (secondary, N5 is primary)
- **WAN IP:** `72.220.103.105`

### USW-24-Pro-HD Switch
- **N5 Connection:** SFP+ port (10G)
- **Port Config:** Native VLAN 1, allows all tagged VLANs (1, 8, 16, 64)

## Kubernetes Configuration

### Cluster Details
- **Distribution:** k0s v1.32.8
- **CNI:** kube-router (default, no custom config)
- **Pod Network:** 10.244.0.0/16
- **Service Network:** 10.96.0.0/12
- **GitOps:** Flux CD

### Storage
- **Provider:** OpenEBS ZFS LocalPV
- **Pools:**
  - `openebs-zfs-ai` → ZFS pool: `ai/homelab`
  - `openebs-zfs-vms` → ZFS pool: `vms/homelab`
  - `openebs-zfs-homelab` → ZFS pool: `tank/homelab`

### MetalLB LoadBalancer

#### IP Address Pools
| Pool Name | VLAN | IP Range | Purpose |
|-----------|------|----------|---------|
| `infra-pool-vlan4` | 1 | 192.168.4.50-192.168.4.59 | DNS, critical infrastructure |
| `services-pool-vlan8` | 8 | 192.168.8.50-192.168.8.79 | Application services |

#### L2 Advertisements
| Name | Pool | Node | Interface | Notes |
|------|------|------|-----------|-------|
| `l2-vlan4` | `infra-pool-vlan4` | N5 | `enp197s0` | VLAN 1 (untagged) |
| `l2-vlan8` | `services-pool-vlan8` | N5 | `enp197s0.8` | VLAN 8 (tagged) |

**Important:** VLAN interfaces require IP addresses for proper routing. Without them, LoadBalancer IPs are unreachable from other networks.

## Services

### Kubernetes Services

| Service | Type | IP | VLAN | Port(s) | URL |
|---------|------|-----|------|---------|-----|
| AdGuard Home (DNS) | LoadBalancer | 192.168.4.53 | 1 | 53/TCP, 53/UDP, 853/TCP, 784/UDP | `https://dns.jax-lab.dev` |
| AdGuard Home (Web) | ClusterIP | 10.96.227.77 | - | 80/TCP | Via Traefik |
| Traefik | LoadBalancer | 192.168.8.50 | 8 | 80/TCP, 443/TCP | - |
| Home Assistant | ExternalName | - | - | - | `https://home.jax-lab.dev` |

**Service Routes:**
- Home Assistant ExternalName → `192.168.64.2:8123` (VLAN 64)
- All HTTPS services → Traefik → IngressRoute

### VPS Services
| Service | URL | Purpose |
|---------|-----|---------|
| Dokploy | `https://dokploy.jax-lab.dev` | Container orchestration |
| Uptime Kuma | `https://uptime.jax-lab.dev` | Monitoring |

## DNS Configuration

### Public DNS (Cloudflare)
- **Domain:** `jax-lab.dev`
- **Records:**
  - `A cloud.jax-lab.dev` → `85.31.234.30`
  - `CNAME *.jax-lab.dev` → `cloud.jax-lab.dev`

### Split-Horizon DNS (AdGuard Home)
- **Address:** `192.168.4.53` (VLAN 1)
- **Web UI:** `https://dns.jax-lab.dev`
- **Purpose:** Internal clients resolve to internal IPs

**DNS Rewrites (AdGuard Home):**
| Domain | Internal IP | External IP |
|--------|-------------|-------------|
| `home.jax-lab.dev` | `192.168.8.50` | `85.31.234.30` |
| `dns.jax-lab.dev` | `192.168.8.50` | `85.31.234.30` |
| `n8n.jax-lab.dev` | `192.168.8.50` | `85.31.234.30` |

**Reverse DNS:** UDM Pro at `192.168.4.1` provides PTR lookups for private ranges.

### Upstream DNS
- **Primary:** `192.168.4.1` (UDM Pro)
- **Fallback:** `1.1.1.1` (Cloudflare)

## SSL/TLS Certificates

### Kubernetes Traefik
- **Method:** Let's Encrypt DNS-01 challenge
- **Provider:** Cloudflare
- **Token:** Stored in `traefik-cloudflare-api-token` secret (SOPS-encrypted)
- **Storage:** Persistent volume on OpenEBS ZFS

### VPS Traefik
- **Method:** Let's Encrypt HTTP-01 challenge
- **Storage:** `/etc/dokploy/traefik/dynamic/acme.json`

## Twingate VPN

### Organization
- **URL:** `mobius.twingate.com`

### Networks
1. **Homelab** - N5 connector exposes on-premises resources
2. **Cloud** - VPS connector + client for VPS ↔ homelab communication

### Connectors
| Location | Type | Device | Access |
|----------|------|--------|--------|
| VPS | Connector | - | Exposes VPS to Twingate |
| VPS | Client (headless) | `cloud-connector-cloud-ops` | Accesses `192.168.0.0/16` |
| N5 | Connector | `ix-twingate-twingate-1` | Exposes homelab to Twingate |

### Access Verification
```bash
# From VPS to homelab services
$ nc -zv 192.168.4.5 443        # ✓ N5 host HTTPS
$ nc -zv 192.168.8.50 443       # ✓ Traefik LoadBalancer
$ dig @192.168.4.53 google.com  # ✓ AdGuard DNS
```

## Traffic Flows

### Public Traffic (External → Homelab)
```
User
  ↓ DNS: *.jax-lab.dev → 85.31.234.30
VPS Traefik (85.31.234.30:443)
  ↓ Twingate tunnel (sdwan0)
Kubernetes Traefik (192.168.8.50:443)
  ↓ IngressRoute
Pod or ExternalName Service
```

### Internal Traffic (LAN → Homelab)
```
User
  ↓ DNS: *.jax-lab.dev → 192.168.8.50 (AdGuard rewrite)
Kubernetes Traefik (192.168.8.50:443)
  ↓ IngressRoute
Pod or ExternalName Service
```

### Inter-VLAN Routing
- **VLAN 1 ↔ VLAN 8:** N5 routes via `enp197s0` (VLAN 1) and `enp197s0.8` (VLAN 8)
- **VLAN 1 ↔ VLAN 64:** N5 routes via `enp197s0` and `bridge64`
- **Other VLANs:** Routed by UDM Pro between VLANs

## Secrets Management

### SOPS Encryption
- **Tool:** Mozilla SOPS with age encryption
- **Age Public Key:** `age1hhwgd0zzsuqrg7gad42kh547lkgfeqsu03uql375uzslz0vqc37sknuux0`
- **Age Private Key:** Derived from SSH Ed25519 key via `ssh-to-age`
- **Kubernetes Secret:** `sops-age` in `flux-system` namespace

### Encrypted Secrets
- `k8s/clusters/lab/infrastructure/traefik-cloudflare.secret.yaml`
- Additional secrets as needed

## Configuration Files

### Network Configuration
- **N5 Netplan:** `/etc/netplan/01-netcfg.yaml` (source: `bootstrap/n5-netplan.yaml`)
- **Key requirement:** VLAN interfaces must have IP addresses for MetalLB routing

### Kubernetes Configuration
- **k0s Config:** `bootstrap/homelab-k0sctl.yaml`
- **Flux Config:** `k8s/clusters/lab/`
- **MetalLB Config:** `k8s/clusters/lab/infrastructure-config/metallb-config.yaml`

### Traefik Configuration
- **VPS Main:** `/etc/dokploy/traefik/traefik.yml`
- **VPS Dynamic:** `/etc/dokploy/traefik/dynamic/`
  - `lab.yml` - Catch-all routing to homelab (priority: -1000)
- **Kubernetes:** Deployed via Helm with Flux

## IP Address Allocation

### VLAN 1 (192.168.4.0/24)
| IP | Host/Service | Type |
|----|--------------|------|
| 192.168.4.1 | UDM Pro | Gateway |
| 192.168.4.5 | N5 | Host |
| 192.168.4.50-59 | MetalLB infra pool | LoadBalancer IPs |
| 192.168.4.53 | AdGuard Home DNS | LoadBalancer |
| 192.168.4.81 | M1-ubuntu | Host |

### VLAN 8 (192.168.8.0/24)
| IP | Host/Service | Type |
|----|--------------|------|
| 192.168.8.1 | UDM Pro | Gateway |
| 192.168.8.50-79 | MetalLB services pool | LoadBalancer IPs |
| 192.168.8.50 | Traefik | LoadBalancer |
| 192.168.8.254 | N5 enp197s0.8 | Host (routing) |

### VLAN 16 (192.168.16.0/20)
| IP | Host/Service | Type |
|----|--------------|------|
| 192.168.16.1 | UDM Pro | Gateway |
| 192.168.16.254 | N5 enp197s0.16 | Host (routing) |

### VLAN 64 (192.168.64.0/20)
| IP | Host/Service | Type |
|----|--------------|------|
| 192.168.64.1 | N5 bridge64 | Gateway |
| 192.168.64.2 | Home Assistant VM | VM |

### Pod Network (10.244.0.0/16)
| Network | Node | Purpose |
|---------|------|---------|
| 10.244.0.0/24 | N5 | Pod IPs on controller |
| 10.244.1.0/24 | M1-ubuntu | Pod IPs on worker |
