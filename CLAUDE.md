# Mobius Homelab - Network Documentation

## Overview
Hybrid homelab infrastructure spanning on-premises and cloud resources, connected via Twingate.

## Infrastructure Architecture

### Operating System & Security
- **Base OS**: Ubuntu 24.04.3 LTS (all servers)
- **Extended Security**: Ubuntu Pro subscription (long-term support and livepatch)

### Cloud Server (VPS)

**Hardware:**
- CPU: AMD EPYC 9354P (2 vCPU, 1 thread per core)
- RAM: 7.8 GB
- Provider: Hostinger

**Network Configuration:**
- Single WAN interface for all connectivity
- Public IP: `85.31.234.30`
- Hostname: `cloud.jax-lab.dev`

**User & Access:**
- Root user only
- SSH key authentication
- Platform: **Dokploy** (Docker-based orchestration)

### Homelab Server (N5)

**Hardware:**
- CPU: AMD Ryzen AI 9 HX PRO 370 w/ Radeon 890M (24 cores, 48 threads)
- RAM: 91 GB
- Type: High-performance workstation/server

**Network Configuration:**
- **Primary Interface**: `enp197s0` (10G NIC, main host interface)
- **Secondary Interface**: `eno1` (5G NIC, bridge master for VM/container workloads)
  - Member of `bridge0` for network sharing to VMs and containers
  - VM (Home Assistant) attached via `vnet1`
  - Docker containers access via bridge0

**User & Access:**
- User: `jax` (passwordless sudo for administrative tasks)
- SSH key authentication
- Platform: **Kubernetes** (k0s cluster with Flux CD GitOps)

**Workload Architecture:**
- **Kubernetes**: k0s cluster (N5 + M1 workers)
  - Flux CD for GitOps
  - OpenEBS ZFS storage (ai/homelab, vms/homelab, tank/homelab)
  - MetalLB LoadBalancer (192.168.8.50-79)
  - Traefik ingress controller
- **VMs**: KVM via libvirt (Home Assistant on bridge0)
- **Legacy Docker**: Dokploy for remaining Docker services

## Locations

### Home (On-Premises)
- Current WAN IP: `72.220.103.105`
- Gateway: UDM Pro (UniFi Dream Machine Pro)
- Primary Server: N5 (detailed above)

### Cloud (VPS)
- Provider: Hostinger
- Public IP: `85.31.234.30`
- Hostname: `cloud.jax-lab.dev`
- Server Details: (detailed above)

## Network Topology

### Home Networks
- **Infra VLAN**: `192.168.4.x` (network infrastructure)
- **Services VLAN**: `192.168.8.0/24` (applications and services)

### Key Systems
- **N5**: `n5.jax-lab.dev` → `192.168.8.8` (Services VLAN)
  - Kubernetes cluster (k0s with Flux CD)
  - Traefik LoadBalancer: `192.168.8.50`
  - AdGuard Home: `192.168.8.53`
  - Home Assistant VM: `192.168.8.10:8123`
  - Twingate Connector (homelab network)
- **VPS**: `cloud.jax-lab.dev` → `85.31.234.30`
  - Dokploy platform for public-facing services
  - Twingate Client + Connector
  - Uptime Kuma monitoring

## Access Credentials

### cloud.jax-lab.dev (VPS)
- User: `root`
- Auth: SSH key

### n5.jax-lab.dev (N5)
- User: `jax`
- Auth: SSH key
- Privileges: sudo access

## DNS Configuration

### Domain
- **Primary**: `jax-lab.dev`
- **Provider**: Cloudflare
- **Old domain**: `jaxonk.com` (migrating away)

### Public DNS (Cloudflare)
```dns
A:     cloud.jax-lab.dev → 85.31.234.30
CNAME: *.jax-lab.dev → cloud.jax-lab.dev
```

### Local DNS Resolvers

**AdGuard Home** (Split-Horizon DNS)
- **Address**: `192.168.8.53`
- **Purpose**: Provides split-horizon DNS for local network clients
- **Hosted On**: Kubernetes (N5 k0s cluster)
- **Web UI**: `https://dns.jax-lab.dev`

**DNS Rewrites in AdGuard Home:**
```dns
home.jax-lab.dev → 192.168.8.50  # Traefik LoadBalancer
dns.jax-lab.dev → 192.168.8.50   # Traefik LoadBalancer
n8n.jax-lab.dev → 192.168.8.50   # Traefik LoadBalancer
# Additional internal services as configured
```

**Benefits:**
- Internal clients bypass VPS and access services directly via Kubernetes Traefik
- Faster response times (no external hop)
- Reduces load on VPS and Twingate tunnel
- Let's Encrypt certificates (via DNS-01) are valid for these domains

**Reverse DNS (PTR):**
- UDM Pro at `192.168.4.1` provides PTR lookups for private IP ranges
- AdGuard Home configured to use UDM Pro for private reverse DNS
- Resolves IPs like `192.168.8.10` to hostnames (e.g., `home.lab`)
- Improves client identification in AdGuard Home logs

**UDM Pro Local DNS:**
```dns
n5.jax-lab.dev → 192.168.8.8
```

**Note:** The wildcard CNAME `*.jax-lab.dev` points all subdomains to the VPS, which acts as a reverse proxy to internal services via Twingate. Split-horizon DNS allows internal clients to bypass this.

## Twingate Configuration

**Organization**: `mobius.twingate.com`

### Networks
1. **Homelab** - Connected to home network via N5
2. **Cloud** - Connected to VPS

### Connectors & Clients

#### VPS (cloud.jax-lab.dev)
- **Connector**: ✅ Installed (allows external access to VPS resources)
- **Client**: ✅ Installed (allows VPS to access homelab resources)
  - Type: Service account (headless, persistent)
  - Account: "cloud-connector" (ServiceAccountKey)
  - Device: "cloud-connector-cloud-ops"
  - Access: `192.168.0.0/16` network resource

#### N5 (n5.jax-lab.dev)
- **Connector**: ✅ Installed (Docker: `ix-twingate-twingate-1`)
  - Exposes homelab network to Twingate

### Connectivity Verification
```bash
# VPS can reach homelab services via Twingate
$ ping 192.168.8.8
✅ ICMP works (note: ICMP forwarding has limitations, use TCP for monitoring)

$ nc -zv 192.168.8.8 443
✅ Connection to 192.168.8.8 443 port [tcp/https] succeeded!

# Twingate tunnel interface on VPS
$ ip link show sdwan0
sdwan0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1500

# Routes installed for homelab access
$ ip route show | grep 192.168
192.168.0.0/16 dev sdwan0 proto static scope host metric 25
```

## Traefik Reverse Proxy Architecture

### Kubernetes Traefik (N5 Homelab Cluster)

**Platform:** Kubernetes (k0s) with Flux CD
**Location:** `k8s/clusters/lab/infrastructure/traefik.yaml`

**Key Features:**
- **LoadBalancer IP**: `192.168.8.50` (via MetalLB)
- **Let's Encrypt DNS-01**: Cloudflare provider for certificate issuance
- **Storage**: Persistent volume on OpenEBS ZFS (`openebs-zfs-homelab`)
- **ACME Permissions**: `fsGroupChangePolicy: OnRootMismatch` for proper file permissions
- **ExternalName Support**: Enabled for Home Assistant routing

**Configuration:**
```yaml
service:
  type: LoadBalancer
  annotations:
    metallb.universe.tf/loadBalancerIPs: 192.168.8.50

additionalArguments:
  - "--certificatesresolvers.letsencrypt.acme.dnschallenge=true"
  - "--certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare"

providers:
  kubernetesCRD:
    allowExternalNameServices: true
```

**Managed Services:**
- Home Assistant: `https://home.jax-lab.dev` (IngressRoute → ExternalName → 192.168.8.10:8123)
- AdGuard Home: `https://dns.jax-lab.dev` (IngressRoute → ClusterIP)

### VPS Traefik Configuration

**Location:** `/etc/dokploy/traefik/`

#### Main Config (`traefik.yml`)
```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@jax-lab.dev
      storage: /etc/dokploy/traefik/dynamic/acme.json
      httpChallenge:
        entryPoint: web

# Access logs stored outside dynamic folder to prevent config rescans
accessLog:
  filePath: /var/log/dokploy/traefik/access.log
```

**Key Features:**
- HTTP-01 challenge for Let's Encrypt certificates (VPS is publicly accessible)
- No automatic `certResolver` on websecure entrypoint (prevents ACME spam from random domains)
- Access logs in `/var/log/dokploy/traefik/access.log` (not in `dynamic/` to avoid constant rescans)

#### Catch-All Routing (`dynamic/lab.yml`)
Forwards all unmatched `*.jax-lab.dev` traffic to internal N5 Traefik via Twingate:

```yaml
http:
  routers:
    lab-traefik-http:
      rule: HostRegexp(`^.+\.jax-lab\.dev$`)
      entryPoints: [ "web" ]
      priority: -1000
      service: internal-http

    lab-traefik:
      rule: HostRegexp(`^.+\.jax-lab\.dev$`)
      entryPoints: [ "websecure" ]
      tls: true
      priority: -1000
      service: internal-https

  services:
    internal-http:
      loadBalancer:
        servers:
          - url: "http://192.168.8.8"
        passHostHeader: true

    internal-https:
      loadBalancer:
        serversTransport: internal-https
        servers:
          - url: "https://192.168.8.8"
        passHostHeader: true

  serversTransports:
    internal-https:
      insecureSkipVerify: true
```

**Behavior:**
- **HTTP requests**: Forwarded to N5's Traefik on port 80 (for ACME challenges)
- **HTTPS requests**: Forwarded to N5's Traefik on port 443 (passthrough)
- **Priority**: -1000 (lowest priority - only matches if no specific router exists)
- **Security**: Only matches `*.jax-lab.dev` domains (blocks random scanner traffic)

### Legacy Docker Traefik (Deprecated)

**Note:** Docker-based Traefik on N5 has been replaced by Kubernetes Traefik. The configuration below is for historical reference.

**Previous Location:** `/etc/dokploy/traefik/` (Docker)
- Used DNS-01 challenge with Cloudflare
- Routed to services on Services VLAN
- Now superseded by Kubernetes IngressRoutes

## Current Architecture & Traffic Flow

### Public Traffic Flow (External → Homelab)
```
1. User requests https://home.jax-lab.dev
2. DNS resolves to VPS (85.31.234.30)
3. VPS Traefik receives request
4. VPS catch-all router forwards to https://192.168.8.50 via Twingate
5. Kubernetes Traefik (LoadBalancer) receives request
6. IngressRoute routes to Home Assistant ExternalName service (192.168.8.10:8123)
7. Response flows back through same path
```

**Certificate Chain:**
- VPS terminates TLS with Let's Encrypt cert (HTTP-01)
- Re-encrypts for transit over Twingate
- Kubernetes Traefik terminates with Let's Encrypt cert (DNS-01)
- Double encryption provides defense in depth

### Monitoring Traffic Flow (VPS → Homelab)
```
1. Uptime Kuma on VPS monitors https://192.168.8.50
2. Request goes directly through Twingate tunnel (sdwan0)
3. Reaches Kubernetes Traefik LoadBalancer
4. Service responds with status
```

**Note:** Uptime Kuma had NSCD (Name Service Cache Daemon) disabled to prevent DNS caching issues causing false positives.

## Services

### VPS Services
- **Uptime Kuma**: Monitoring homelab services
  - URL: `https://uptime.jax-lab.dev`
  - Monitors via Twingate tunnel
- **Dokploy**: Container orchestration
  - URL: `https://dokploy.jax-lab.dev`

### N5 Kubernetes Services
- **Traefik**: Ingress controller and LoadBalancer
  - IP: `192.168.8.50`
  - Let's Encrypt DNS-01 certificates
- **AdGuard Home**: DNS server with ad-blocking
  - DNS: `192.168.8.53`
  - Web UI: `https://dns.jax-lab.dev`
- **Home Assistant**: Smart home automation (VM, not in K8s)
  - Internal: `http://192.168.8.10:8123`
  - External: `https://home.jax-lab.dev` (via Traefik IngressRoute)

## Traefik v3 Migration Notes

### Syntax Changes (v2 → v3)
**Old (v2) - Named RegExp:**
```yaml
rule: HostRegexp(`{host:.+}`)  # ❌ Deprecated in v3
```

**New (v3) - Pure RegExp:**
```yaml
rule: HostRegexp(`^.+\.jax-lab\.dev$`)  # ✅ Correct v3 syntax
```

**References:**
- [Traefik Community: HostRegexp v3 and named regexp](https://community.traefik.io/t/hostregexp-v3-and-named-regexp/19802)
- Named regexp groups removed in Traefik v3
- Use pure Go regexp patterns only

## Security Considerations

### ACME Challenge Protection
**Problem Solved:** Random internet scanners hitting the VPS would trigger Let's Encrypt certificate requests, potentially hitting rate limits.

**Solution:**
1. Removed automatic `certResolver` from VPS websecure entrypoint
2. Only explicit routers (like `dokploy.jax-lab.dev`) request certificates
3. Catch-all router has `tls: true` but no `certResolver`
4. Random domains get 404 from Traefik, no ACME attempt

### Traffic Filtering
- VPS catch-all only matches `^.+\.jax-lab\.dev$` pattern
- Random scanner traffic (e.g., `adegavicosa.com.br`) gets 404 from VPS Traefik
- No forwarding of malicious traffic to internal network

### Access Logs
- Location: `/var/log/dokploy/traefik/access.log` (VPS)
- Format: JSON
- Min duration filter: 10ms (reduces noise from ultra-fast 404s)
- **Important:** Logs stored outside `/etc/dokploy/traefik/dynamic/` to prevent Traefik from rescanning configs on every request

## Recent Changes (2025-10-29/30)

### ✅ Completed
1. **Kubernetes Homelab Cluster Deployment**
   - Deployed k0s cluster on N5 + M1 workers
   - Configured Flux CD for GitOps management
   - OpenEBS ZFS storage with StorageClass patches for all ZFS pools
   - MetalLB LoadBalancer pool (192.168.8.50-79)

2. **Traefik Migration to Kubernetes**
   - Deployed Traefik via Helm with Flux
   - Let's Encrypt DNS-01 with Cloudflare provider
   - Fixed ACME permissions with `fsGroupChangePolicy: OnRootMismatch`
   - Enabled ExternalName services for Home Assistant routing
   - LoadBalancer IP: 192.168.8.50

3. **AdGuard Home Migration to Kubernetes**
   - Migrated Docker AdGuard to Kubernetes
   - Copied configuration and data (work/conf volumes)
   - Switched to production DNS IP (192.168.8.53)
   - Web UI accessible at `https://dns.jax-lab.dev`
   - Fixed service port mapping (targetPort 80)

4. **Service Verification**
   - Home Assistant: `https://home.jax-lab.dev` ✅
   - AdGuard Home: `https://dns.jax-lab.dev` ✅
   - DNS queries on 192.168.8.53 ✅
   - All Let's Encrypt certificates issued ✅

## Previous Changes (2025-10-28)

### ✅ Completed
1. **Split-Horizon DNS via AdGuard Home**
   - Configured DNS rewrites for `home.jax-lab.dev` and `n8n.jax-lab.dev` → `192.168.8.8`
   - Internal clients now bypass VPS and access N5 services directly
   - Verified UDM Pro supports PTR lookups for reverse DNS (resolves `192.168.8.10` to `home.lab`)
   - AdGuard Home now displays client hostnames instead of raw IPs

## Previous Changes (2025-10-26)

### ✅ Completed
1. **Fixed Traefik v3 Catch-All Routing**
   - Updated from v2 syntax `{host:.+}` to v3 syntax `.+`
   - Restricted to `*.jax-lab.dev` only (security improvement)

2. **Configured Dual Traefik Architecture**
   - VPS: HTTP-01 challenge for public services
   - N5: DNS-01 challenge for internal services (behind NAT)
   - Added HTTP pass-through for ACME challenges from VPS to N5

3. **SSL/TLS Certificate Management**
   - VPS: Let's Encrypt via HTTP-01 (publicly accessible)
   - N5: Let's Encrypt via DNS-01 with Cloudflare provider
   - Successfully obtained certs for `home.jax-lab.dev`, `n8n.jax-lab.dev`

4. **Traefik Configuration Cleanup**
   - Moved access logs out of `dynamic/` folder (prevents config reload loops)
   - Removed auto `certResolver` to prevent ACME spam
   - Backed up old `acme.json` and cleared for fresh DNS challenge start

5. **Home Assistant Routing**
   - Created `/etc/dokploy/traefik/dynamic/homeassistant.yml` on N5
   - Routes `home.jax-lab.dev` → `192.168.8.10:8123`
   - Valid Let's Encrypt certificate via DNS-01

6. **Monitoring Improvements**
   - Disabled NSCD in Uptime Kuma to prevent DNS caching issues
   - Uptime Kuma now reliably monitors homelab via Twingate

### Configuration Files Changed

#### VPS (`cloud.jax-lab.dev`)
- `/etc/dokploy/traefik/traefik.yml` - Removed auto certResolver, updated log path
- `/etc/dokploy/traefik/dynamic/lab.yml` - Added catch-all routing with v3 syntax
- Traefik container - Added volume mount for `/var/log/dokploy/traefik`

#### N5 (`n5.jax-lab.dev`)
- `/etc/dokploy/traefik/traefik.yml` - Changed from HTTP-01 to DNS-01 challenge
- `/etc/dokploy/traefik/dynamic/homeassistant.yml` - Created new routing config
- `/etc/dokploy/traefik/dynamic/acme.json` - Cleared and rebuilt with DNS certs
- Traefik container - Added `CF_DNS_API_TOKEN` environment variable

## Troubleshooting

### ICMP (Ping) Limitations
**Symptom:** Ping doesn't work through Twingate tunnel, but TCP connections work fine.

**Explanation:**
- Twingate authorizes ICMP in policy logs
- ICMP packets don't appear on tunnel interface (tcpdump shows 0 packets)
- Likely a limitation of Docker connector or service account setup

**Solution:** Use TCP-based health checks in monitoring (HTTP/HTTPS), not ICMP ping.

### Let's Encrypt Rate Limits
**Symptom:** `unable to obtain ACME certificate` errors for random domains.

**Cause:** Automatic certificate resolver was requesting certs for any domain hitting the VPS.

**Solution:** Remove `certResolver` from entrypoint defaults, only add to specific routers.

### Traefik Config Reload Loops
**Symptom:** High CPU usage, constant file watching activity.

**Cause:** Access logs or ACME storage in `/etc/dokploy/traefik/dynamic/` trigger config reloads on every write.

**Solution:**
- Access logs: `/var/log/dokploy/traefik/access.log`
- ACME storage can stay in `dynamic/` (only updates on cert renewal, not constantly)

### DNS-01 Challenge Failures
**Symptom:** `cannot get ACME client cloudflare: some credentials information are missing`

**Cause:** Incorrect environment variable name.

**Correct Variables:**
- `CF_DNS_API_TOKEN` (or `CLOUDFLARE_DNS_API_TOKEN`)
- NOT `CF_API_TOKEN` (doesn't exist)

**Permissions Required:**
- Zone/Zone/Read
- Zone/DNS/Edit
- Apply to all zones or specific zone

## Useful Commands

### Traefik Debugging
```bash
# VPS: Check access logs for routing decisions
tail -f /var/log/dokploy/traefik/access.log | jq -r '{host: .RequestHost, router: .RouterName, backend: .ServiceURL, status: .DownstreamStatus}'

# VPS: Check Traefik container logs
docker logs dokploy-traefik --tail 50 -f

# N5: Check certificate status
cat /etc/dokploy/traefik/dynamic/acme.json | jq '.letsencrypt.Certificates[] | {domain: .domain.main}'

# N5: Check Traefik logs for ACME activity
sudo docker logs dokploy-traefik --tail 100 | grep -i acme
```

### Twingate Debugging
```bash
# VPS: Check Twingate status
twingate status

# VPS: Check Twingate routes
ip route show | grep sdwan0

# VPS: Test connectivity to homelab
nc -zv 192.168.8.8 443
curl -v http://192.168.8.8

# N5: Check Twingate connector status
sudo docker ps | grep twingate
sudo docker logs ix-twingate-twingate-1
```

### Certificate Verification
```bash
# Check certificate issuer and validity
openssl s_client -connect home.jax-lab.dev:443 -servername home.jax-lab.dev 2>/dev/null | openssl x509 -noout -subject -issuer -dates

# Test HTTPS connection
curl -v https://home.jax-lab.dev 2>&1 | grep -E 'subject|issuer|SSL connection'
```

## Future Considerations

### DNS Cleanup (Optional)
Currently using wildcard `*.jax-lab.dev → cloud.jax-lab.dev` for simplicity. Could be cleaned up with explicit records:

```dns
# Explicit records for public services (instead of wildcard)
dokploy.jax-lab.dev → 85.31.234.30
uptime.jax-lab.dev → 85.31.234.30
home.jax-lab.dev → 85.31.234.30

# Remove wildcard (or keep for convenience)
*.jax-lab.dev → cloud.jax-lab.dev
```

**Pros:**
- More explicit control
- Better documentation of public vs internal services

**Cons:**
- More DNS records to manage
- Current wildcard + catch-all works well

### Split DNS
For internal users to bypass VPS and access homelab directly:

**AdGuard Home DNS Rewrites:**
```dns
home.jax-lab.dev → 192.168.8.8
n8n.jax-lab.dev → 192.168.8.8
# etc.
```

**Benefits:**
- Faster access from home network (no VPS hop)
- N5's Let's Encrypt certs already valid via DNS-01
- Reduces load on VPS and Twingate

**Current Status:** ✅ Implemented via AdGuard Home DNS rewrites (2025-10-28)

## Notes
- Twingate provides secure connectivity between home and cloud resources without VPN complexity
- UDM Pro handles local DNS resolution for home resources
- Infra VLAN (192.168.4.x) contains network infrastructure (gateway, routers, switches, APs)
- Services VLAN (192.168.8.0/24) contains application servers and services
- All Traefik configs use YAML format and file provider with directory watching
