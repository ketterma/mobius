# Jaxon Cloud Architecture

## Overview
Dual-cluster architecture with separate cloud and homelab Kubernetes clusters, connected via Twingate VPN for secure inter-cluster communication.

**Created:** 2025-11-02
**Status:** Planning → Implementation

---

## Domain Strategy

### Public Domain: `jaxon.cloud`
- **DNS Provider:** Cloudflare
- **Purpose:** Public-facing services, accessible from internet
- **SSL/TLS:** Let's Encrypt via Traefik (DNS-01 challenge)
- **Services:** Uptime monitoring, public APIs, proxied homelab services

### Internal Domain: `jaxon.home`
- **DNS Provider:** AdGuard Home (split-horizon DNS)
- **Purpose:** Internal homelab services, LAN-only access
- **SSL/TLS:** Let's Encrypt via Traefik (DNS-01 challenge, using jaxon.cloud for validation)
- **Services:** Infrastructure, home automation, internal tools

### Migration from `jax-lab.dev`
- **Old domain:** `jax-lab.dev` (has hyphen, harder to type)
- **New domain:** `jaxon.cloud` (no hyphen, same length, more memorable)
- **Timeline:** Gradual migration, run both domains in parallel initially
- **Deprecation:** TBD after all services validated on new domain

---

## Infrastructure Layout

### Cloud Cluster: `phx.jaxon.cloud`
**Location:** Phoenix, AZ (VPS)
**IP Address:** 85.31.234.30
**OS:** Ubuntu 24.04 LTS (fresh install)
**Role:** Standalone k0s cluster (control-plane + worker)

**Purpose:**
- Public-facing ingress (Traefik)
- Uptime monitoring (Uptime Kuma)
- Public services and APIs
- Reverse proxy to homelab (via Twingate)

**Network:**
- Public IP: 85.31.234.30
- Twingate connector: Bridges to homelab network
- DNS: Cloudflare (public resolution)

### Homelab Cluster: `lab.jaxon.home`
**Location:** On-premises
**Nodes:**
- `n5.jaxon.home` (192.168.4.5) - k0s control-plane + worker
- `m1-ubuntu.jaxon.home` (192.168.4.81) - k0s worker

**Purpose:**
- Internal services (AdGuard, Home Assistant, etc.)
- Private workloads
- IoT and smart home infrastructure
- Development and testing

**Network:**
- VLAN 1 (192.168.4.0/24): Infrastructure
- VLAN 8 (192.168.8.0/24): LoadBalancer VIPs
- VLAN 16 (192.168.16.0/20): Sandbox
- VLAN 64 (192.168.64.0/20): IoT
- Gateway: UniFi Dream Machine Pro
- Twingate connector: Exposes services to cloud cluster

---

## Service Distribution

### Cloud Cluster Services (`*.jaxon.cloud`)

| Service | FQDN | Purpose | Exposure |
|---------|------|---------|----------|
| Traefik | `traefik.jaxon.cloud` | Public ingress controller | Public dashboard |
| Uptime Kuma | `uptime.jaxon.cloud` | Public uptime monitoring | Public (read-only) |
| Twingate Connector | - | VPN bridge to homelab | Internal only |
| (Future) Public APIs | `api.jaxon.cloud` | Public-facing APIs | Public |

### Homelab Cluster Services (`*.jaxon.home`)

| Service | FQDN | Purpose | Exposure |
|---------|------|---------|----------|
| Traefik | `traefik.jaxon.home` | Internal ingress controller | Internal LAN |
| AdGuard Home | `dns.jaxon.home` | DNS + ad-blocking | Internal LAN |
| Home Assistant | `home.jaxon.home` | Smart home platform | Internal (+ proxied via cloud) |
| Pocket-ID | `auth.jaxon.home` | SSO/authentication | Internal (+ proxied via cloud) |
| UniFi Controller | `unifi.jaxon.home` | Network management | Internal LAN |
| Twingate Connector | - | VPN client to cloud | Internal only |

### Proxied Services (homelab → cloud)

These run on homelab but are exposed via cloud cluster:

| Service | Cloud FQDN | Homelab FQDN | Notes |
|---------|------------|---------------|-------|
| Home Assistant | `home.jaxon.cloud` | `home.jaxon.home` | Proxied via Twingate |
| Pocket-ID | `auth.jaxon.cloud` | `auth.jaxon.home` | Proxied via Twingate |

---

## Technology Stack

### Both Clusters
- **Kubernetes:** k0s (minimal, self-contained)
- **GitOps:** Flux CD (continuous deployment)
- **Ingress:** Traefik v3
- **Secrets:** Mozilla SOPS with age encryption
- **Certificates:** Let's Encrypt (DNS-01 via Cloudflare)
- **VPN:** Twingate (zero-trust network access)

### Cloud Cluster Specifics
- **LoadBalancer:** Cloud provider's native (or MetalLB if needed)
- **Storage:** Cloud provider's block storage (or local)
- **DNS:** Cloudflare (authoritative)

### Homelab Cluster Specifics
- **LoadBalancer:** MetalLB (L2 mode, ARP-based)
- **Storage:** OpenEBS ZFS LocalPV
- **DNS:** AdGuard Home (split-horizon, internal authoritative for .home)
- **CNI:** kube-router (default)

---

## DNS Configuration

### Cloudflare DNS (`jaxon.cloud`)

```
# A records
phx.jaxon.cloud.          A    85.31.234.30
*.jaxon.cloud.            A    85.31.234.30  (wildcard for all services)

# Or individual records
traefik.jaxon.cloud.      A    85.31.234.30
uptime.jaxon.cloud.       A    85.31.234.30
home.jaxon.cloud.         A    85.31.234.30  (proxied to homelab)
auth.jaxon.cloud.         A    85.31.234.30  (proxied to homelab)
```

### AdGuard Home DNS (`jaxon.home`)

**DNS Rewrites (split-horizon):**
```
# Internal resolution for .home domain
*.jaxon.home              →  192.168.8.50  (Traefik LoadBalancer IP)

# Rewrite .cloud to internal when on LAN (optional, for faster access)
*.jaxon.cloud             →  192.168.8.50  (use internal path if Twingate allows)
```

**Upstream DNS:**
- External queries → Cloudflare DNS (1.1.1.1)
- Internal queries for `.home` → AdGuard's own records

---

## Network Flow Examples

### External User → Cloud Service
1. User browses to `uptime.jaxon.cloud`
2. Cloudflare DNS → 85.31.234.30 (phx VPS)
3. Traefik on cloud cluster → Uptime Kuma pod
4. Response returned

### External User → Proxied Homelab Service
1. User browses to `home.jaxon.cloud`
2. Cloudflare DNS → 85.31.234.30 (phx VPS)
3. Traefik on cloud cluster → Twingate tunnel → Homelab
4. Home Assistant on homelab cluster responds
5. Response proxied back through Twingate → Traefik → User

### Internal User → Homelab Service
1. User (on LAN) browses to `dns.jaxon.home`
2. AdGuard Home DNS → 192.168.8.50 (Traefik LoadBalancer)
3. Traefik on homelab → AdGuard Home pod
4. Response returned (no external hop)

### Internal User → Cloud Service (optional optimization)
1. User (on LAN) browses to `uptime.jaxon.cloud`
2. **Option A:** Cloudflare DNS → 85.31.234.30 → normal internet path
3. **Option B:** AdGuard rewrite → Twingate tunnel → cloud cluster (if configured)

---

## Security Considerations

### Cloud Cluster
- ✅ Public IP exposed (necessary for public services)
- ✅ Traefik enforces HTTPS (Let's Encrypt)
- ✅ Firewall rules: Only 80/443/22 open
- ✅ Twingate provides secure tunnel to homelab (no exposed homelab IPs)
- ⚠️ DDoS protection via Cloudflare proxy (optional)

### Homelab Cluster
- ✅ No public IP exposure (NAT behind UDM Pro)
- ✅ Twingate connector outbound-only (no inbound ports)
- ✅ VLAN segmentation (infrastructure, IoT, sandbox isolated)
- ✅ Split-horizon DNS (internal services not leaked to public DNS)
- ✅ Let's Encrypt certs via DNS-01 (no HTTP exposure needed)

### Secrets Management
- ✅ SOPS encryption for all secrets (age-encrypted)
- ✅ Cloudflare API token encrypted in Git
- ✅ Twingate keys encrypted
- ✅ Age private key derived from SSH key (not in Git)

---

## Deployment Strategy

### Phase 1: Cloud Cluster Setup
1. Provision `phx.jaxon.cloud` VPS (Ubuntu 24.04)
2. Install k0s (single-node cluster)
3. Deploy Flux CD
4. Deploy Traefik + Let's Encrypt (jaxon.cloud)
5. Deploy Uptime Kuma
6. Deploy Twingate connector
7. Test public access via `*.jaxon.cloud`

### Phase 2: Homelab Migration
1. Update AdGuard Home DNS rewrites (jaxon.home)
2. Update Traefik IngressRoutes (jax-lab.dev → jaxon.cloud/jaxon.home)
3. Update Let's Encrypt certificates
4. Test internal access via `*.jaxon.home`
5. Test proxied access via `*.jaxon.cloud`

### Phase 3: Dual-Domain Operation
1. Run both `jax-lab.dev` and `jaxon.cloud` in parallel
2. Validate all services accessible on new domains
3. Update bookmarks/links/documentation
4. Monitor for issues

### Phase 4: Deprecation
1. Set up redirects from `jax-lab.dev` → `jaxon.cloud`
2. Sunset old domain (TBD timeline)
3. Remove old IngressRoutes
4. Archive old certificates

---

## Monitoring & Observability

### Uptime Monitoring
- **Uptime Kuma** on cloud cluster monitors both clusters
- Public endpoint: `uptime.jaxon.cloud`
- Monitors: Cloud services, homelab services (via Twingate), external endpoints

### Metrics (Future)
- Prometheus + Grafana (TBD which cluster)
- kube-state-metrics on both clusters
- Cross-cluster federation (optional)

---

## Backup & Disaster Recovery

### Cloud Cluster
- **Flux GitOps:** All config in Git (repo is source of truth)
- **Persistent data:** Cloud block storage snapshots
- **Recovery:** Redeploy from Git + restore data volumes

### Homelab Cluster
- **Flux GitOps:** All config in Git
- **Persistent data:** ZFS snapshots (scheduled)
- **Recovery:** Redeploy from Git + ZFS restore

### Runbook
- **Cloud cluster loss:** Provision new VPS, run k0s + Flux bootstrap
- **Homelab cluster loss:** Rebuild nodes, run k0s + Flux bootstrap, restore ZFS
- **DNS loss:** Cloudflare has API, can rebuild via Terraform/scripts
- **Secrets loss:** Age private key backed up offline (SSH key based)

---

## Future Enhancements

### Potential Additions
- [ ] Multi-cloud: Add `nyc.jaxon.cloud`, `sfo.jaxon.cloud` for HA
- [ ] Cross-cluster service mesh (Linkerd/Cilium)
- [ ] Centralized logging (Loki + Grafana)
- [ ] External-DNS automation (auto-create DNS records from IngressRoutes)
- [ ] ArgoCD for GitOps (alternative to Flux)
- [ ] Velero for cluster backups
- [ ] OPA/Kyverno for policy enforcement

### Scaling Considerations
- Cloud cluster: Can add more VPS nodes if needed
- Homelab cluster: Can add more nodes (limited by hardware budget)
- Cross-cluster workload migration: Via GitOps (move manifests between repos/clusters)

---

## References
- Main repo: `/Users/jax/Documents/homelab`
- Network docs: `docs/lab-network.md`
- HAOS VM docs: `docs/lab-vm-haos.md`
- Bootstrap configs: `bootstrap/`
- Kubernetes manifests: `k8s/clusters/lab/`
