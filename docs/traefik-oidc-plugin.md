# Traefik OIDC Plugin Integration Guide

## Overview
This guide covers integrating the [traefikoidc plugin](https://github.com/lukaszraczylo/traefikoidc) with our homelab Traefik deployment to provide OIDC authentication for services that don't natively support it.

## Architecture

**Current Setup:**
- Traefik v37.2.x deployed via Helm chart
- Pocket-ID OIDC provider at `https://auth.jaxon.cloud`
- IngressRoute CRDs for routing
- Let's Encrypt DNS-01 certificates via Cloudflare

**Integration Goal:**
- Add traefikoidc plugin to Traefik
- Create reusable OIDC authentication middleware
- Protect services like AdGuard Home, UniFi Controller, etc.

## Implementation Steps

### 1. Enable Plugin in Traefik

Add plugin configuration to the Traefik HelmRelease. Update `k8s/clusters/lab/infrastructure/traefik/kustomization.yaml`:

```yaml
patches:
  - patch: |-
      apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      metadata:
        name: traefik
        namespace: flux-system
      spec:
        values:
          # ... existing configuration ...

          # Enable experimental plugins
          experimental:
            plugins:
              traefikoidc:
                moduleName: github.com/lukaszraczylo/traefikoidc
                version: v0.7.10

          # Add plugin arguments to additional arguments
          additionalArguments:
            # ... existing cert resolver args ...
            - "--experimental.plugins.traefikoidc.moduleName=github.com/lukaszraczylo/traefikoidc"
            - "--experimental.plugins.traefikoidc.version=v0.7.10"
```

**Note:** The plugin follows Traefik helm chart versions closely. If the plugin fails to load, update to the latest version.

### 2. Create OAuth Client in Pocket-ID

Before configuring the middleware, create an OAuth 2.0 client in Pocket-ID:

1. Access Pocket-ID at `https://auth.jaxon.cloud`
2. Create a new OAuth client with:
   - **Client ID**: Generate or specify (e.g., `traefik-oidc`)
   - **Client Secret**: Generate securely
   - **Redirect URIs**: Add callback URLs for each protected service
     - Format: `https://<service-domain>/oauth2/callback`
     - Example: `https://dns.jaxon.cloud/oauth2/callback`
   - **Scopes**: `openid`, `profile`, `email`
   - **Grant Types**: Authorization Code
   - **Response Types**: code

3. Save the Client ID and Client Secret for the next step

### 3. Create Kubernetes Secret for Plugin

Create an encrypted secret with the OAuth credentials:

**File:** `k8s/clusters/lab/infrastructure/traefik/oidc-secret.sops.yaml`

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: traefik-oidc-config
  namespace: traefik
type: Opaque
stringData:
  # OAuth credentials from Pocket-ID
  client-id: "traefik-oidc"
  client-secret: "YOUR_CLIENT_SECRET_HERE"

  # Session encryption key (minimum 32 bytes)
  session-key: "generate-a-secure-random-32-byte-key-here-use-openssl-rand-base64-32"
```

**Encrypt with SOPS:**
```bash
sops --encrypt --in-place k8s/clusters/lab/infrastructure/traefik/oidc-secret.sops.yaml
```

**Add to kustomization:**
Update `k8s/clusters/lab/infrastructure/traefik/kustomization.yaml`:
```yaml
resources:
  - ../../../../base/infrastructure/traefik
  - cloudflare-secret.sops.yaml
  - oidc-secret.sops.yaml  # Add this
```

### 4. Create Reusable OIDC Middleware

Create a middleware resource that can be referenced by any IngressRoute:

**File:** `k8s/clusters/lab/infrastructure/traefik/oidc-middleware.yaml`

```yaml
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: oidc-auth
  namespace: traefik
spec:
  plugin:
    traefikoidc:
      # Pocket-ID OIDC configuration
      providerURL: "https://auth.jaxon.cloud"

      # OAuth client credentials (from secret)
      clientID: "traefik-oidc"
      clientSecret: "{{ env "OIDC_CLIENT_SECRET" }}"

      # Session encryption
      sessionEncryptionKey: "{{ env "OIDC_SESSION_KEY" }}"

      # Callback configuration
      callbackURL: "/oauth2/callback"

      # CRITICAL: Force HTTPS for redirect URIs
      # Without this, OAuth callbacks will fail with http:// URLs
      forceHTTPS: true

      # Logging
      logLevel: "info"

      # Scopes (default mode - append to openid, profile, email)
      overrideScopes: false
      scopes:
        - "openid"
        - "profile"
        - "email"

      # Optional: Restrict access by email domain
      # allowedUserDomains:
      #   - "jaxon.cloud"

      # Optional: Restrict access by specific users
      # allowedUsers:
      #   - "admin@jaxon.cloud"

      # Rate limiting
      rateLimit: 100

      # Enable PKCE for enhanced security
      enablePKCE: true
```

**Note on Environment Variables:**
The middleware needs access to secrets. We have two options:

**Option A: Use Traefik's env vars (Recommended)**
Mount the secret as environment variables in Traefik deployment:

Update the Traefik HelmRelease patch:
```yaml
env:
  - name: CF_DNS_API_TOKEN
    valueFrom:
      secretKeyRef:
        name: cloudflare-api-token
        key: CF_DNS_API_TOKEN
  # Add OIDC secrets
  - name: OIDC_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: traefik-oidc-config
        key: client-secret
  - name: OIDC_SESSION_KEY
    valueFrom:
      secretKeyRef:
        name: traefik-oidc-config
        key: session-key
```

Then update middleware to use env vars:
```yaml
clientSecret: "{{ env \"OIDC_CLIENT_SECRET\" }}"
sessionEncryptionKey: "{{ env \"OIDC_SESSION_KEY\" }}"
```

**Option B: Hardcode in middleware (Less secure)**
If env var substitution doesn't work, hardcode the values directly:
```yaml
clientID: "traefik-oidc"
clientSecret: "your-actual-secret-here"
sessionEncryptionKey: "your-actual-session-key-here"
```

### 5. Apply Middleware to IngressRoutes

Protect services by adding the middleware to their IngressRoutes.

**Example: Protect AdGuard Home**

Update `k8s/clusters/lab/apps/adguard/ingressroute.yaml`:

```yaml
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: adguard-home
  namespace: adguard-home
  annotations:
    external-dns.alpha.kubernetes.io/hostname: dns.jaxon.cloud
    external-dns.alpha.kubernetes.io/target: 192.168.8.50
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`dns.jaxon.cloud`)
      kind: Rule
      # Add OIDC authentication middleware
      middlewares:
        - name: oidc-auth
          namespace: traefik
      services:
        - name: adguard-home-web
          port: 80
  tls:
    certResolver: letsencrypt
```

**Example: Protect UniFi Controller**

Update `k8s/clusters/lab/apps/unifi/ingressroute.yaml`:

```yaml
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: unifi
  namespace: unifi
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`unifi.jax-lab.dev`)
      kind: Rule
      middlewares:
        - name: oidc-auth
          namespace: traefik
      services:
        - name: unifi
          port: 8443
  tls:
    certResolver: letsencrypt
```

### 6. Update Pocket-ID Redirect URIs

For each protected service, add the callback URL to Pocket-ID's OAuth client:

```
https://dns.jaxon.cloud/oauth2/callback
https://unifi.jax-lab.dev/oauth2/callback
https://studio.supabase.jax-lab.dev/oauth2/callback
```

Alternatively, use a wildcard redirect URI if Pocket-ID supports it:
```
https://*.jaxon.cloud/oauth2/callback
https://*.jax-lab.dev/oauth2/callback
```

## Authentication Flow

1. User accesses protected service (e.g., `https://dns.jaxon.cloud`)
2. Traefik OIDC middleware intercepts the request
3. User is redirected to Pocket-ID login (`https://auth.jaxon.cloud`)
4. User authenticates with Pocket-ID
5. Pocket-ID redirects back to `https://dns.jaxon.cloud/oauth2/callback`
6. Plugin validates the token and creates a session
7. User is redirected to original URL with authenticated session
8. Future requests use session cookie (no re-authentication needed)

## Advanced Configuration Options

### Path Exclusions

Exclude specific paths from authentication (e.g., health checks, API endpoints):

```yaml
spec:
  plugin:
    traefikoidc:
      # ... other config ...
      excludedURLs:
        - "/health"
        - "/api/public/*"
        - "/.well-known/*"
```

### Role-Based Access Control

Restrict access based on user roles/groups (if Pocket-ID includes these claims):

```yaml
spec:
  plugin:
    traefikoidc:
      # ... other config ...
      allowedRolesAndGroups:
        - "admin"
        - "homelab-users"
```

### Multi-Replica Deployments

If running multiple Traefik replicas, disable replay detection:

```yaml
spec:
  plugin:
    traefikoidc:
      # ... other config ...
      disableReplayDetection: true
```

### Token Introspection (for opaque tokens)

If Pocket-ID uses opaque tokens instead of JWTs:

```yaml
spec:
  plugin:
    traefikoidc:
      # ... other config ...
      allowOpaqueTokens: true
      requireTokenIntrospection: true
```

## Troubleshooting

### Plugin fails to load
- **Cause:** Version mismatch with Traefik helm chart
- **Solution:** Update plugin version to match latest Traefik release

### OAuth callback fails with "redirect_uri_mismatch"
- **Cause:** Redirect URI not registered in Pocket-ID
- **Solution:** Add exact callback URL to OAuth client in Pocket-ID

### Redirects use http:// instead of https://
- **Cause:** Missing `forceHTTPS: true` configuration
- **Solution:** Add `forceHTTPS: true` to middleware config

### "Session encryption key too short" error
- **Cause:** Session key less than 32 bytes
- **Solution:** Generate longer key: `openssl rand -base64 32`

### User can't access after authentication
- **Cause:** Domain/user restrictions too strict
- **Solution:** Check `allowedUserDomains` and `allowedUsers` settings

### High memory usage
- **Cause:** Session cache growing unbounded
- **Solution:** Plugin has automatic LRU eviction; check for goroutine leaks

## Security Considerations

1. **Session Key:** Use a cryptographically secure random key (≥32 bytes)
2. **Client Secret:** Store in SOPS-encrypted secret, never commit plaintext
3. **PKCE:** Enable for enhanced security against authorization code interception
4. **Scopes:** Request minimum necessary scopes (openid, profile, email)
5. **HTTPS:** Always use `forceHTTPS: true` to prevent token leakage
6. **Domain Restrictions:** Use `allowedUserDomains` to limit access to trusted domains

## Testing

1. **Deploy configuration:**
   ```bash
   git add k8s/clusters/lab/infrastructure/traefik/
   git commit -m "Add traefikoidc plugin and OIDC authentication middleware"
   git push

   # Force Flux reconciliation
   flux reconcile source git flux-system
   flux reconcile kustomization infrastructure
   ```

2. **Verify plugin loaded:**
   ```bash
   kubectl -n traefik logs deployment/traefik | grep -i plugin
   ```

3. **Test authentication flow:**
   - Access protected service in incognito/private browser
   - Should redirect to Pocket-ID login
   - Authenticate with valid credentials
   - Should redirect back to service with access granted

4. **Check session persistence:**
   - Refresh page or navigate away and back
   - Should NOT be prompted to login again (session cookie valid)

## Next Steps

1. Deploy plugin configuration to Traefik
2. Create OAuth client in Pocket-ID
3. Create and encrypt the OIDC secret
4. Deploy the OIDC middleware
5. Update IngressRoutes for services to protect
6. Test authentication flow
7. Monitor logs for issues

## References

- Plugin Repository: https://github.com/lukaszraczylo/traefikoidc
- Traefik Plugin Documentation: https://doc.traefik.io/traefik/plugins/
- Pocket-ID Documentation: https://github.com/stonith404/pocket-id
- OAuth 2.0 / OIDC Spec: https://openid.net/connect/
