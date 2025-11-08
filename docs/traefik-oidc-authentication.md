# Traefik OIDC Authentication Setup

## Overview
This guide documents how to add OIDC authentication to services using the Traefik OIDC plugin and Pocket-ID as the identity provider.

## Prerequisites
- Traefik v3.x deployed via Helm
- Pocket-ID running as OIDC provider
- SOPS configured with age encryption for secrets

## Architecture
- **OIDC Provider**: Pocket-ID at `https://auth.jaxon.cloud`
- **OIDC Plugin**: `lukaszraczylo/traefikoidc` v0.7.10
- **Per-app Configuration**: Each app has its own OAuth client and middleware
- **Secret Management**: SOPS-encrypted credentials in middleware YAML

## Step 1: Enable OIDC Plugin in Traefik

Edit `k8s/clusters/lab/infrastructure/traefik/kustomization.yaml`:

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
          # Let's Encrypt DNS-01 challenge (behind NAT)
          additionalArguments:
            # ... existing cert resolver args ...
            - "--experimental.plugins.traefikoidc.moduleName=github.com/lukaszraczylo/traefikoidc"
            - "--experimental.plugins.traefikoidc.version=v0.7.10"

          # Enable experimental plugins
          experimental:
            plugins:
              traefikoidc:
                moduleName: github.com/lukaszraczylo/traefikoidc
                version: v0.7.10

          # ... existing env vars ...
```

**Note**: The plugin does NOT support Go template syntax for environment variables. Credentials must be hardcoded in the middleware YAML (encrypted with SOPS).

## Step 2: Create OAuth Client in Pocket-ID

1. Access Pocket-ID at `https://auth.jaxon.cloud`
2. Navigate to OAuth Clients
3. Create a new client:
   - **Client ID**: Generate UUID (e.g., `a6f4cfca-7627-4fcc-9519-81ce2ecd767c`)
   - **Client Secret**: Generate secure random string (e.g., using `openssl rand -base64 32`)
   - **Redirect URIs**: `https://<service-domain>/oauth2/callback`
     - Example: `https://dns.jaxon.cloud/oauth2/callback`
   - **Scopes**: `openid`, `profile`, `email`
   - **Grant Types**: Authorization Code
   - **Response Types**: code

4. Save the Client ID and Client Secret for the next step

## Step 3: Generate Session Encryption Key

```bash
openssl rand -base64 32
```

Save this value - it will be used to encrypt session cookies.

## Step 4: Create SOPS-Encrypted Middleware

Create `k8s/clusters/lab/apps/<app-name>/oidc-middleware.sops.yaml`:

```yaml
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: <app-name>-oidc-auth
  namespace: <app-namespace>
spec:
  plugin:
    traefikoidc:
      # Provider configuration
      providerURL: "https://auth.jaxon.cloud"

      # OAuth credentials (from Pocket-ID)
      clientID: "<client-id-from-step-2>"
      clientSecret: "<client-secret-from-step-2>"

      # Session encryption key (from step 3)
      sessionEncryptionKey: "<session-key-from-step-3>"

      # Callback configuration
      callbackURL: "/oauth2/callback"

      # Force HTTPS for redirect URIs
      forceHTTPS: true

      # Scopes to request
      scopes:
        - openid
        - profile
        - email

      # Session configuration
      sessionName: "_<app-name>_oauth"
      sessionValidity: 86400  # 24 hours

      # Logging
      logLevel: "info"

      # Cookie settings
      overrideScopes: false
```

## Step 5: Encrypt Sensitive Fields with SOPS

```bash
sops --encrypt \
  --encrypted-regex '^(clientSecret|sessionEncryptionKey)$' \
  --in-place k8s/clusters/lab/apps/<app-name>/oidc-middleware.sops.yaml
```

This encrypts only the `clientSecret` and `sessionEncryptionKey` fields while leaving other configuration readable.

## Step 6: Update App Kustomization

Edit `k8s/clusters/lab/apps/<app-name>/kustomization.yaml`:

```yaml
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
  - ingressroute.yaml
  - oidc-middleware.sops.yaml  # Add this line
```

## Step 7: Update IngressRoute to Use Middleware

Edit `k8s/clusters/lab/apps/<app-name>/ingressroute.yaml`:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: <app-name>
  namespace: <app-namespace>
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`<app-domain>`)
      kind: Rule
      middlewares:
        - name: <app-name>-oidc-auth  # Add this middleware reference
      services:
        - name: <app-service>
          port: <port>
  tls:
    certResolver: letsencrypt
```

## Step 8: Deploy

```bash
# Commit changes
git add .
git commit -m "Add OIDC authentication to <app-name>"
git push

# Reconcile Flux
flux reconcile source git flux-system
flux reconcile kustomization infrastructure
flux reconcile kustomization apps
```

## Example: AdGuard Home Configuration

**OAuth Client:**
- Client ID: `a6f4cfca-7627-4fcc-9519-81ce2ecd767c`
- Client Secret: `XWbBALOsMX7WxqxHdjnM4CwGyIafsPmX`
- Redirect URI: `https://dns.jaxon.cloud/oauth2/callback`

**Files:**
- Middleware: `k8s/clusters/lab/apps/adguard/oidc-middleware.sops.yaml`
- IngressRoute: `k8s/clusters/lab/apps/adguard/ingressroute.yaml`
- Kustomization: `k8s/clusters/lab/apps/adguard/kustomization.yaml`

## Troubleshooting

### Authentication fails with "Invalid client secret"

**Cause**: The traefikoidc plugin does not support Go template syntax (`{{ env "VAR" }}`). Environment variables are not evaluated.

**Solution**: Use SOPS-encrypted credentials directly in the middleware YAML.

### "Critical session error: Failed to get even a new session"

**Cause**: Invalid session encryption key or old cookies from previous configuration.

**Solution**:
1. Clear browser cookies for the domain
2. Verify the session encryption key is valid base64
3. Try in incognito/private browsing mode

### "DNS loop" or connection timeout to auth.jaxon.cloud

**Cause**: This was initially suspected but proven false. Traefik CAN reach its own LoadBalancer IP.

**Solution**: Use the external URL `https://auth.jaxon.cloud` - it works correctly from within Traefik pods.

### Middleware changes not applied

**Cause**: Flux might be caching or applying old configuration.

**Solution**:
```bash
# Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization apps

# Or suspend/resume to force full reapplication
flux suspend kustomization apps
flux resume kustomization apps
flux reconcile kustomization apps
```

## Security Considerations

1. **SOPS Encryption**: Always encrypt `clientSecret` and `sessionEncryptionKey` fields
2. **Per-App Isolation**: Each app should have its own OAuth client and credentials
3. **Session Cookie**: Configure `secure`, `httpOnly`, and `sameSite` appropriately
4. **Redirect URI Validation**: Ensure Pocket-ID only allows expected callback URLs
5. **Secret Rotation**: Rotate OAuth credentials and session keys periodically

## Limitations

- The traefikoidc plugin does not support environment variable substitution
- Each app requires its own middleware with embedded (encrypted) credentials
- Cannot use cross-namespace secret references for OAuth credentials
- Session state is stored in cookies (not distributed/shared across instances)

## References

- Plugin: https://github.com/lukaszraczylo/traefikoidc
- Traefik Plugins: https://plugins.traefik.io/
- SOPS: https://github.com/getsops/sops
- OAuth 2.0 / OIDC: https://oauth.net/2/
