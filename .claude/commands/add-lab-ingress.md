---
description: Add external ingress for homelab service via PHX cluster
argument-hint: <service-name> <domain> <backend-ip:port>
allowed-tools: Read, Write, Edit, Bash(git *)
---

# Add External Ingress for Homelab Service

Create PHX cluster configuration to expose a homelab service to the public internet via Twingate VPN.

## Arguments

- `$1` - Service name (e.g., "homeassistant", "adguard")
- `$2` - Public domain (e.g., "home.jaxon.cloud", "dns.jaxon.cloud")
- `$3` - Backend IP and port (e.g., "192.168.64.2:8123", "192.168.4.53:80")

## Prerequisites

The service MUST already be configured in the lab cluster with:
1. IngressRoute in lab cluster pointing to the backend
2. Let's Encrypt certificate configured
3. Same domain (`$2`) used in lab IngressRoute

## Task Steps

1. **Validate arguments**
   - Ensure all three arguments are provided
   - Verify service name is lowercase and alphanumeric
   - Verify domain format is valid (contains dots)
   - Verify backend format is IP:PORT

2. **Check if service already exists**
   - Check if `k8s/clusters/phx/apps/$1-proxy/` directory exists
   - If it exists, ask user if they want to overwrite or exit

3. **Create directory structure**
   ```bash
   mkdir -p k8s/clusters/phx/apps/$1-proxy
   ```

4. **Create namespace.yaml**
   ```yaml
   ---
   apiVersion: v1
   kind: Namespace
   metadata:
     name: $1-proxy
   ```

5. **Create service.yaml**
   - ALWAYS point to `192.168.8.50` (lab Traefik LoadBalancer IP)
   - ALWAYS use port `443` (HTTPS)
   - Do NOT use the backend IP/port from $3 here
   ```yaml
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: $1-lab
     namespace: $1-proxy
   spec:
     type: ExternalName
     externalName: 192.168.8.50
     ports:
       - name: https
         port: 443
         protocol: TCP
         targetPort: 443
   ```

6. **Create serverstransport.yaml**
   ```yaml
   ---
   apiVersion: traefik.io/v1alpha1
   kind: ServersTransport
   metadata:
     name: lab-transport
     namespace: $1-proxy
   spec:
     serverName: $2
   ```

7. **Create ingressroute.yaml**
   ```yaml
   ---
   apiVersion: traefik.io/v1alpha1
   kind: IngressRoute
   metadata:
     name: $1-lab
     namespace: $1-proxy
     annotations:
       external-dns.alpha.kubernetes.io/hostname: $2
       external-dns.alpha.kubernetes.io/target: 85.31.234.30
   spec:
     entryPoints:
       - websecure
     routes:
       - match: Host(`$2`)
         kind: Rule
         services:
           - name: $1-lab
             port: 443
             serversTransport: lab-transport
     tls:
       certResolver: letsencrypt
   ```

8. **Create kustomization.yaml**
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

9. **Update apps kustomization**
   - Read `k8s/clusters/phx/apps/kustomization.yaml`
   - Add `- $1-proxy` to the resources list (alphabetically sorted)
   - Write the updated file

10. **Verify lab cluster configuration**
    - Check if IngressRoute exists in lab cluster for domain $2
    - Show warning if not found, but continue
    - Remind user to ensure lab cluster has the service configured

11. **Git operations**
    - Show git diff of changes
    - Ask user if they want to commit and push
    - If yes, create commit with descriptive message:
      ```
      Add $1 proxy to PHX cluster via Twingate

      Deploy external ingress for $1 through PHX VPS:
      - Public DNS ($2) → 85.31.234.30 (PHX Traefik)
      - PHX Traefik → Twingate tunnel → 192.168.8.50:443 (Lab Traefik)
      - Lab Traefik → $3 ($1)

      Configuration follows the external ingress pattern documented in
      docs/external-ingress-pattern.md

      🤖 Generated with [Claude Code](https://claude.com/claude-code)

      Co-Authored-By: Claude <noreply@anthropic.com>
      ```

12. **Deploy to PHX**
    - Ask user if they want to reconcile Flux on PHX cluster
    - If yes, run:
      ```bash
      flux --context phx reconcile source git flux-system
      flux --context phx reconcile kustomization apps
      ```

13. **Verify deployment**
    - Check resources created: `kubectl --context phx get ingressroute,service,serverstransport -n $1-proxy`
    - Check DNS record: `dig +short $2 @1.1.1.1`
    - If DNS not resolving, suggest restarting external-dns

14. **Test connectivity**
    - Test from PHX to lab Traefik: `ssh root@85.31.234.30 "curl -k -I https://192.168.8.50 -H 'Host: $2'"`
    - Test public endpoint: `curl -I https://$2`

15. **Summary**
    - Show complete traffic flow diagram
    - Provide next steps (e.g., updating split-horizon DNS in AdGuard if needed)
    - Reference documentation: `docs/external-ingress-pattern.md`

## Important Notes

- **ALWAYS** point ExternalName service to `192.168.8.50:443` (lab Traefik)
- **NEVER** point directly to the backend service ($3)
- The backend IP:port ($3) is only used for documentation and user information
- Lab Traefik must already have an IngressRoute configured for the domain
- The domain must have a valid Let's Encrypt certificate in the lab cluster
- External-DNS may need a restart to pick up new IngressRoutes

## Example Usage

```bash
# Add Home Assistant proxy
/add-lab-ingress homeassistant home.jaxon.cloud 192.168.64.2:8123

# Add AdGuard Home proxy
/add-lab-ingress adguard dns.jaxon.cloud 192.168.4.53:80

# Add Pocket-ID proxy
/add-lab-ingress pocketid auth.jaxon.cloud 192.168.8.50:80
```

## Error Handling

- Validate all arguments before starting
- Check for existing configurations
- Verify git status is clean before committing
- Handle missing kubectl contexts gracefully
- Provide clear error messages with remediation steps
