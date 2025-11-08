# External Ingress Pattern for Homelab Services

This document describes the pattern for exposing homelab services to the public internet via the PHX VPS cluster with Twingate VPN connectivity.

## Architecture Overview

```
Internet Client
    ↓
    DNS: home.jaxon.cloud → 85.31.234.30 (Cloudflare)
    ↓
PHX Traefik (85.31.234.30:443)
    - Terminates TLS with Let's Encrypt
    - Validates backend certificate
    ↓
Twingate VPN Tunnel
    ↓
Lab Traefik (192.168.8.50:443)
    - Terminates TLS with Let's Encrypt
    - Routes to backend service
    ↓
Backend Service (e.g., 192.168.64.2:8123)
```

## Traffic Flow Details

1. **Public DNS Resolution**
   - External clients: `home.jaxon.cloud` → `85.31.234.30` (Cloudflare DNS)
   - Internal clients: `home.jaxon.cloud` → `192.168.8.50` (AdGuard split-horizon DNS)

2. **TLS/SSL Certificates**
   - PHX Traefik obtains Let's Encrypt certificate for the public domain
   - PHX→Lab connection uses HTTPS with SNI validation
   - Lab Traefik has its own Let's Encrypt certificate
   - End-to-end encryption maintained throughout the chain

3. **Twingate Connectivity**
   - Twingate headless client runs as DaemonSet on PHX cluster
   - Provides secure VPN tunnel to homelab network (192.168.x.x ranges)
   - No port forwarding or firewall rules required on home network

## Implementation Steps

### 1. Create Directory Structure

```bash
mkdir -p k8s/clusters/phx/apps/<service-name>-proxy
```

### 2. Create Namespace

**File:** `k8s/clusters/phx/apps/<service-name>-proxy/namespace.yaml`

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: <service-name>-proxy
```

### 3. Create ExternalName Service

**File:** `k8s/clusters/phx/apps/<service-name>-proxy/service.yaml`

This service points to the **lab Traefik LoadBalancer IP** (not the final backend service).

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: <service-name>-lab
  namespace: <service-name>-proxy
spec:
  type: ExternalName
  externalName: 192.168.8.50  # Lab Traefik LoadBalancer IP
  ports:
    - name: https
      port: 443
      protocol: TCP
      targetPort: 443
```

**Key points:**
- Always point to `192.168.8.50` (lab Traefik) on port `443`
- Do NOT point directly to the backend service
- This allows lab Traefik to handle routing and certificate management

### 4. Create ServersTransport

**File:** `k8s/clusters/phx/apps/<service-name>-proxy/serverstransport.yaml`

This configures secure HTTPS connection to the lab Traefik backend.

```yaml
---
apiVersion: traefik.io/v1alpha1
kind: ServersTransport
metadata:
  name: lab-transport
  namespace: <service-name>-proxy
spec:
  serverName: <public-domain>  # e.g., home.jaxon.cloud
```

**Key points:**
- `serverName` must match the domain that lab Traefik has a certificate for
- Do NOT use `insecureSkipVerify: true` (lab Traefik has valid Let's Encrypt certs)
- SNI validation ensures secure connection

### 5. Create IngressRoute

**File:** `k8s/clusters/phx/apps/<service-name>-proxy/ingressroute.yaml`

```yaml
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: <service-name>-lab
  namespace: <service-name>-proxy
  annotations:
    external-dns.alpha.kubernetes.io/hostname: <public-domain>
    external-dns.alpha.kubernetes.io/target: 85.31.234.30
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`<public-domain>`)
      kind: Rule
      services:
        - name: <service-name>-lab
          port: 443
          serversTransport: lab-transport
  tls:
    certResolver: letsencrypt
```

**Key points:**
- **Both** external-dns annotations are required:
  - `hostname`: The DNS name to create
  - `target`: The PHX VPS IP (85.31.234.30)
- `serversTransport` reference enables secure backend connection
- `certResolver: letsencrypt` obtains public certificate

### 6. Create Kustomization

**File:** `k8s/clusters/phx/apps/<service-name>-proxy/kustomization.yaml`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - service.yaml
  - serverstransport.yaml
  - ingressroute.yaml
```

### 7. Update Apps Kustomization

**File:** `k8s/clusters/phx/apps/kustomization.yaml`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - <service-name>-proxy
  - uptime-kuma
  # ... other apps
```

### 8. Ensure Lab Traefik Configuration

The service must already be configured in the **lab cluster** with:

**IngressRoute** (`k8s/clusters/lab/apps/<service-name>/ingressroute.yaml`):
```yaml
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: <service-name>
  namespace: traefik
  annotations:
    external-dns.alpha.kubernetes.io/hostname: <public-domain>
    external-dns.alpha.kubernetes.io/target: 192.168.8.50
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`<public-domain>`)
      kind: Rule
      services:
        - name: <service-name>
          port: <backend-port>
  tls:
    certResolver: letsencrypt
```

**Service** (if backend is external to Kubernetes):
```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: <service-name>
  namespace: traefik
spec:
  type: ExternalName
  externalName: <backend-ip>  # e.g., 192.168.64.2
  ports:
    - name: http
      port: <backend-port>
      protocol: TCP
      targetPort: <backend-port>
```

### 9. Deploy and Verify

```bash
# Commit and push changes
git add k8s/clusters/phx/apps/
git commit -m "Add <service-name> proxy to PHX cluster via Twingate"
git push

# Reconcile Flux on PHX cluster
flux --context phx reconcile source git flux-system
flux --context phx reconcile kustomization apps

# Verify resources
kubectl --context phx get ingressroute,service,serverstransport -n <service-name>-proxy

# Check external-dns created DNS record
dig +short <public-domain> @1.1.1.1
# Should return: 85.31.234.30

# Test end-to-end connectivity
curl -I https://<public-domain>
```

## Example: Home Assistant

Here's a complete example for exposing Home Assistant:

**Service Details:**
- Public domain: `home.jaxon.cloud`
- Backend: Home Assistant VM at `192.168.64.2:8123`
- Lab Traefik: `192.168.8.50:443`
- PHX VPS: `85.31.234.30`

**Files created:**
- `k8s/clusters/phx/apps/homeassistant-proxy/namespace.yaml`
- `k8s/clusters/phx/apps/homeassistant-proxy/service.yaml`
- `k8s/clusters/phx/apps/homeassistant-proxy/serverstransport.yaml`
- `k8s/clusters/phx/apps/homeassistant-proxy/ingressroute.yaml`
- `k8s/clusters/phx/apps/homeassistant-proxy/kustomization.yaml`

See the actual files in the repository for reference implementation.

## Security Considerations

1. **TLS Encryption**: End-to-end HTTPS encryption from client → PHX → Lab → Backend
2. **Certificate Validation**: SNI validation prevents MITM attacks in Twingate tunnel
3. **Zero Trust**: Twingate provides zero-trust network access (no exposed ports)
4. **Least Privilege**: Only specific services are exposed via explicit IngressRoutes
5. **Split-Horizon DNS**: Internal clients bypass PHX VPS for better performance

## Troubleshooting

### DNS Record Not Created

**Symptom:** `dig +short <domain> @1.1.1.1` returns nothing

**Solution:**
1. Verify both external-dns annotations are present on IngressRoute
2. Check external-dns logs: `kubectl --context phx logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=30`
3. Restart external-dns: `kubectl --context phx rollout restart deployment -n external-dns external-dns`

### Connection Timeout

**Symptom:** `curl https://<domain>` times out

**Solution:**
1. Test PHX → Lab connectivity: `ssh root@85.31.234.30 "curl -k -I https://192.168.8.50 -H 'Host: <domain>'"`
2. Check Twingate client status: `kubectl --context phx get pods -n twingate-client`
3. Verify lab Traefik has certificate: `kubectl --context homelab get certificate -n traefik`

### Certificate Errors

**Symptom:** SSL certificate validation fails

**Solution:**
1. Verify `serverName` in ServersTransport matches the domain
2. Check lab Traefik certificate: `kubectl --context homelab get certificate -n traefik`
3. Ensure Let's Encrypt certificates are valid (not expired)

### 404 Not Found

**Symptom:** HTTPS works but returns 404

**Solution:**
1. Verify lab IngressRoute exists: `kubectl --context homelab get ingressroute -n traefik`
2. Check Host match in lab IngressRoute matches public domain
3. Verify backend service is accessible from lab Traefik

## Performance Considerations

- **Latency**: Adds ~50ms latency due to Twingate tunnel and double-proxy
- **Bandwidth**: Limited by home internet upload speed and VPS bandwidth
- **Split-Horizon**: Internal clients bypass PHX VPS entirely (use AdGuard DNS rewrites)
- **Caching**: Consider adding Traefik middleware for static content caching

## Future Improvements

1. **Health Checks**: Add Traefik health check middleware for backend services
2. **Rate Limiting**: Implement rate limiting on PHX Traefik for public services
3. **Geographic Routing**: Add additional VPS locations for lower latency
4. **Monitoring**: Implement metrics collection for proxy performance
5. **Authentication**: Add Traefik ForwardAuth middleware for additional security layer
