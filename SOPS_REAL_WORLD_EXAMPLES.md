# SOPS + Flux: Real-World Examples

This document contains practical, copy-paste ready examples for common scenarios.

---

## Example 1: Simple Single-Cluster Setup

### Repository Structure
```
flux-config/
├── .gitignore
├── .sops.yaml
├── clusters/
│   └── homelab/
│       ├── kustomization.yaml
│       └── secrets/
│           ├── database.yaml
│           ├── api-keys.yaml
│           └── tls-certs.yaml
└── README.md
```

### Step 1: Generate Age Key
```bash
cd ~/projects/flux-config
age-keygen -o age.agekey

# Output shows:
# Public key: age1abc123def456ghi789jkl012mno345pqr678stu9vwxyz012345
```

### Step 2: Create .sops.yaml
```bash
cat > .sops.yaml << 'EOF'
creation_rules:
  - path_regex: ^clusters/homelab/secrets/.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: age1abc123def456ghi789jkl012mno345pqr678stu9vwxyz012345
EOF
```

### Step 3: Create .gitignore
```bash
cat >> .gitignore << 'EOF'

# SOPS encryption keys - NEVER commit!
age.agekey
sops-key.txt
.sops/
age-*.agekey
EOF
```

### Step 4: Create and Encrypt Secrets

**Create plaintext secret (locally only):**
```bash
cat > clusters/homelab/secrets/database.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: databases
type: Opaque
data:
  host: postgres.databases.svc.cluster.local
  port: "5432"
  username: postgres
  password: my-secure-postgres-password-123
EOF
```

**Encrypt the secret:**
```bash
sops --encrypt --in-place clusters/homelab/secrets/database.yaml

# Verify encryption
cat clusters/homelab/secrets/database.yaml | head -20
# Should show: data: ENC[AES256_GCM,...]
```

### Step 5: Create Flux Kustomization
```bash
cat > clusters/homelab/kustomization.yaml << 'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: secrets
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./clusters/homelab/secrets
  prune: true
  decryption:
    provider: sops
    secretRef:
      name: sops-age
EOF
```

### Step 6: Create Kubernetes Secret (One-time Setup)
```bash
# Only on the cluster, NOT in Git
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age.agekey \
  --dry-run=client -o yaml | kubectl apply -f -

# Verify
kubectl get secret sops-age -n flux-system -o yaml
```

### Step 7: Commit to Git
```bash
# Verify age.agekey won't be committed
git check-ignore age.agekey
# Output: age.agekey

# Add only encrypted files and configuration
git add .sops.yaml .gitignore clusters/homelab/

# Commit
git commit -m "Add SOPS encryption and database secret"

# Push
git push origin main
```

### Step 8: Verify on Cluster
```bash
# Monitor reconciliation
flux logs -f -k Kustomization/secrets

# After reconciliation completes, verify secret was created
kubectl get secret postgres-credentials -n databases -o yaml

# The secret should be decrypted and accessible
kubectl get secret postgres-credentials -n databases \
  -o jsonpath='{.data.password}' | base64 -d
# Output: my-secure-postgres-password-123
```

---

## Example 2: Multi-Cluster Setup (Dev/Staging/Prod)

### Repository Structure
```
flux-config/
├── .gitignore
├── .sops.yaml                    # Root config (fallback)
├── clusters/
│   ├── dev/
│   │   ├── .sops.yaml           # Dev-specific
│   │   ├── kustomization.yaml
│   │   └── secrets/
│   │       ├── database.yaml
│   │       └── api-keys.yaml
│   ├── staging/
│   │   ├── .sops.yaml           # Staging-specific
│   │   ├── kustomization.yaml
│   │   └── secrets/
│   │       ├── database.yaml
│   │       └── api-keys.yaml
│   └── prod/
│       ├── .sops.yaml           # Prod-specific
│       ├── kustomization.yaml
│       └── secrets/
│           ├── database.yaml
│           └── api-keys.yaml
└── README.md
```

### Step 1: Generate Separate Keys Per Environment
```bash
# Development key
age-keygen -o age-dev.agekey
DEV_KEY=$(grep "public key:" age-dev.agekey | cut -d' ' -f3)
echo "Dev key: $DEV_KEY"

# Staging key
age-keygen -o age-staging.agekey
STAGING_KEY=$(grep "public key:" age-staging.agekey | cut -d' ' -f3)
echo "Staging key: $STAGING_KEY"

# Production key
age-keygen -o age-prod.agekey
PROD_KEY=$(grep "public key:" age-prod.agekey | cut -d' ' -f3)
echo "Prod key: $PROD_KEY"
```

### Step 2: Create Environment-Specific .sops.yaml Files

**clusters/dev/.sops.yaml:**
```bash
cat > clusters/dev/.sops.yaml << EOF
creation_rules:
  - path_regex: ^.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: $DEV_KEY
EOF
```

**clusters/staging/.sops.yaml:**
```bash
cat > clusters/staging/.sops.yaml << EOF
creation_rules:
  - path_regex: ^.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: $STAGING_KEY
EOF
```

**clusters/prod/.sops.yaml:**
```bash
cat > clusters/prod/.sops.yaml << EOF
creation_rules:
  - path_regex: ^.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: $PROD_KEY
EOF
```

### Step 3: Create Root .sops.yaml (Fallback)
```bash
cat > .sops.yaml << EOF
creation_rules:
  - encrypted_regex: ^(data|stringData)$
    age: $DEV_KEY  # Default to dev if no environment-specific config
EOF
```

### Step 4: Create Environment-Specific Secrets

**Development database secret:**
```bash
cat > clusters/dev/secrets/database.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: databases
type: Opaque
data:
  host: postgres-dev.databases.svc.cluster.local
  port: "5432"
  username: dev_user
  password: dev-password-123
  dbname: dev_database
EOF

sops --encrypt --in-place clusters/dev/secrets/database.yaml
```

**Staging database secret (different credentials):**
```bash
cat > clusters/staging/secrets/database.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: databases
type: Opaque
data:
  host: postgres-staging.databases.svc.cluster.local
  port: "5432"
  username: staging_user
  password: staging-secure-password-456
  dbname: staging_database
EOF

sops --encrypt --in-place clusters/staging/secrets/database.yaml
```

**Production database secret (encrypted with prod key):**
```bash
cat > clusters/prod/secrets/database.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: databases
type: Opaque
data:
  host: postgres-prod.example.com
  port: "5432"
  username: prod_user
  password: prod-super-secure-password-xyz789
  dbname: production
EOF

sops --encrypt --in-place clusters/prod/secrets/database.yaml
```

### Step 5: Create Environment-Specific Kustomizations

**clusters/dev/kustomization.yaml:**
```bash
cat > clusters/dev/kustomization.yaml << 'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: dev-secrets
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./clusters/dev/secrets
  prune: true
  decryption:
    provider: sops
    secretRef:
      name: sops-age
      namespace: flux-system
EOF
```

**clusters/staging/kustomization.yaml:**
```bash
cat > clusters/staging/kustomization.yaml << 'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: staging-secrets
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./clusters/staging/secrets
  prune: true
  decryption:
    provider: sops
    secretRef:
      name: sops-age
      namespace: flux-system
EOF
```

**clusters/prod/kustomization.yaml:**
```bash
cat > clusters/prod/kustomization.yaml << 'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: prod-secrets
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./clusters/prod/secrets
  prune: true
  decryption:
    provider: sops
    secretRef:
      name: sops-age
      namespace: flux-system
EOF
```

### Step 6: Create Cluster-Specific Kubernetes Secrets

**On dev cluster:**
```bash
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age-dev.agekey \
  --dry-run=client -o yaml | kubectl apply -f -
```

**On staging cluster:**
```bash
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age-staging.agekey \
  --dry-run=client -o yaml | kubectl apply -f -
```

**On prod cluster:**
```bash
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age-prod.agekey \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Step 7: Commit to Git
```bash
# Add and commit (NOT age-*.agekey files!)
git add clusters/ .sops.yaml .gitignore
git commit -m "Add multi-cluster SOPS encryption with environment-specific keys"
git push origin main
```

### Step 8: Verify on Each Cluster
```bash
# Dev cluster
kubectl config use-context dev-cluster
flux logs -f -k Kustomization/dev-secrets
kubectl get secret postgres-credentials -n databases

# Staging cluster
kubectl config use-context staging-cluster
flux logs -f -k Kustomization/staging-secrets
kubectl get secret postgres-credentials -n databases

# Prod cluster
kubectl config use-context prod-cluster
flux logs -f -k Kustomization/prod-secrets
kubectl get secret postgres-credentials -n databases
```

---

## Example 3: Team Workflow (Multiple Developers)

### Scenario: Development Team with 3 Members
- Alice (Team Lead)
- Bob (Developer)
- Carol (DevOps Engineer)

### Step 1: Each Member Generates Their Age Key
```bash
# Alice generates key
age-keygen -o ~/.sops/alice-key.txt
# Public key: age1alice...

# Bob generates key
age-keygen -o ~/.sops/bob-key.txt
# Public key: age1bob...

# Carol generates key
age-keygen -o ~/.sops/carol-key.txt
# Public key: age1carol...
```

### Step 2: Team Lead Creates Shared .sops.yaml

Alice creates config with all team members' public keys:

```bash
cat > .sops.yaml << 'EOF'
creation_rules:
  - path_regex: ^secrets/.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: |
      age1alice1111111111111111111111111111111111111111111111,
      age1bob2222222222222222222222222222222222222222222222,
      age1carol3333333333333333333333333333333333333333333333
EOF

git add .sops.yaml
git commit -m "Add shared SOPS config with team members' keys"
git push origin main
```

### Step 3: Set Environment Variable for Decryption
Each team member configures their local environment:

```bash
# In ~/.bashrc or ~/.zshrc
export SOPS_AGE_KEY_FILE=~/.sops/alice-key.txt  # Or bob/carol for them

# Or set it per-command
SOPS_AGE_KEY_FILE=~/.sops/alice-key.txt sops secrets/database.yaml
```

### Step 4: Team Members Decrypt Secrets
```bash
# Alice decrypts using her key (automatically uses SOPS_AGE_KEY_FILE)
sops secrets/database.yaml

# Bob can decrypt same file using his key
SOPS_AGE_KEY_FILE=~/.sops/bob-key.txt sops secrets/database.yaml

# Carol can decrypt using her key
SOPS_AGE_KEY_FILE=~/.sops/carol-key.txt sops secrets/database.yaml
```

### Step 5: Adding New Team Member
When a new team member (David) joins:

```bash
# David generates his age key
age-keygen -o ~/.sops/david-key.txt
# Shares public key: age1david...

# Alice updates .sops.yaml
cat > .sops.yaml << 'EOF'
creation_rules:
  - path_regex: ^secrets/.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: |
      age1alice1111111111111111111111111111111111111111111111,
      age1bob2222222222222222222222222222222222222222222222,
      age1carol3333333333333333333333333333333333333333333333,
      age1david4444444444444444444444444444444444444444444444
EOF

# Alice re-encrypts all secrets to include David's key
for file in secrets/*.yaml; do
  sops --encrypt --in-place "$file"
done

# Commit and push
git add .sops.yaml secrets/
git commit -m "Add David to SOPS encryption"
git push origin main

# David can now decrypt all secrets with his key
```

### Step 6: Removing Team Member
When team member Bob leaves:

```bash
# Alice removes Bob's key from .sops.yaml
cat > .sops.yaml << 'EOF'
creation_rules:
  - path_regex: ^secrets/.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: |
      age1alice1111111111111111111111111111111111111111111111,
      age1carol3333333333333333333333333333333333333333333333,
      age1david4444444444444444444444444444444444444444444444
EOF

# Re-encrypt all secrets without Bob's key
for file in secrets/*.yaml; do
  sops --encrypt --in-place "$file"
done

# Commit and push
git add .sops.yaml secrets/
git commit -m "Remove Bob's access to secrets"
git push origin main

# Bob can no longer decrypt secrets
```

---

## Example 4: Editing Encrypted Secrets

### Edit Existing Secret
```bash
# SOPS handles decryption → editor → re-encryption
sops clusters/dev/secrets/database.yaml

# In the editor, modify plaintext values:
# Before:
#   password: "old-password-123"
# After:
#   password: "new-password-456"

# Save and exit editor
# SOPS automatically re-encrypts the file with new values
```

### View Encrypted Secret (Without Editing)
```bash
# Decrypt to stdout
sops -d clusters/dev/secrets/database.yaml | less

# Or view specific field
sops -d clusters/dev/secrets/database.yaml | grep password
```

### Add New Secret Field
```bash
# Method 1: Using sops edit
sops clusters/dev/secrets/database.yaml
# Add new line: new_field: "new-value"
# Save and exit

# Method 2: Using stdin
cat >> clusters/dev/secrets/database.yaml << 'EOF'
new_field: unencrypted-value
EOF

# Re-encrypt the file
sops --encrypt --in-place clusters/dev/secrets/database.yaml
```

### Remove Field from Secret
```bash
sops clusters/dev/secrets/database.yaml

# In editor, delete the lines you want to remove
# Save and exit
# SOPS re-encrypts without that field
```

---

## Example 5: Verify Encryption is Working

### Check File is Encrypted
```bash
# Should show ENC[ markers
grep "ENC\[" clusters/dev/secrets/database.yaml

# If no output, file is not encrypted!
cat clusters/dev/secrets/database.yaml | head -20
```

### Test Decryption Locally
```bash
# This should work if you have the correct age key
sops -d clusters/dev/secrets/database.yaml | head -10

# If error: "no matching key" - wrong age key configured
```

### Verify Git Won't Commit Plaintext
```bash
# Add to git staging
git add clusters/dev/secrets/database.yaml

# Check what git sees (should be encrypted)
git diff --cached clusters/dev/secrets/database.yaml | head -20
# Should show: +data: ENC[AES256_GCM,...]
# NOT plaintext values
```

### Check Kubernetes Secret
```bash
# After Flux reconciliation, verify secret is decrypted in cluster
kubectl get secret postgres-credentials -n databases -o yaml | grep password

# Output should be base64-encoded actual password value
# Example: cGFzc3dvcmQtMTIz  (base64 for password-123)
```

---

## Example 6: Key Rotation

### Rotate Single Environment Key
```bash
# Generate new key
age-keygen -o age-dev-new.agekey
NEW_KEY=$(grep "public key:" age-dev-new.agekey | cut -d' ' -f3)

# Update .sops.yaml
cat > clusters/dev/.sops.yaml << EOF
creation_rules:
  - path_regex: ^.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: $NEW_KEY
EOF

# Re-encrypt all secrets with new key
for file in clusters/dev/secrets/*.yaml; do
  sops --encrypt --in-place "$file"
done

# Update Kubernetes Secret (in cluster)
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age-dev-new.agekey \
  --dry-run=client -o yaml | kubectl apply -f -

# Commit changes
git add clusters/dev/.sops.yaml clusters/dev/secrets/
git commit -m "Rotate dev cluster SOPS encryption key"

# Cleanup old key
rm age-dev.agekey  # Or backup first
mv age-dev-new.agekey age-dev.agekey
```

### Rotate All Environment Keys
```bash
# Development
age-keygen -o age-dev-new.agekey
DEV_KEY=$(grep "public key:" age-dev-new.agekey | cut -d' ' -f3)

# Staging
age-keygen -o age-staging-new.agekey
STAGING_KEY=$(grep "public key:" age-staging-new.agekey | cut -d' ' -f3)

# Production
age-keygen -o age-prod-new.agekey
PROD_KEY=$(grep "public key:" age-prod-new.agekey | cut -d' ' -f3)

# Update all .sops.yaml files
for env in dev staging prod; do
  VAR="${env^^}_KEY"  # Convert to uppercase
  cat > "clusters/$env/.sops.yaml" << EOF
creation_rules:
  - path_regex: ^.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: ${!VAR}
EOF
done

# Re-encrypt all secrets
for cluster in dev staging prod; do
  for file in clusters/$cluster/secrets/*.yaml; do
    sops --encrypt --in-place "$file"
  done
done

# Update all cluster secrets
for cluster in dev staging prod; do
  kubectl --context="$cluster" create secret generic sops-age \
    --namespace=flux-system \
    --from-file=age.agekey="age-${cluster}-new.agekey" \
    --dry-run=client -o yaml | kubectl --context="$cluster" apply -f -
done

# Commit changes
git add clusters/*/
git commit -m "Rotate all environment SOPS encryption keys"
```

---

## Example 7: Troubleshooting

### Scenario: Forgot to Encrypt Secret

**Problem:** Accidentally committed plaintext secret to Git.

**Solution:**
```bash
# 1. Rotate the compromised key
age-keygen -o age-dev-new.agekey

# 2. Re-encrypt all secrets
for file in clusters/dev/secrets/*.yaml; do
  sops --encrypt --in-place "$file"
done

# 3. Force-push history (⚠️ Coordinate with team!)
git reset --hard HEAD~1  # Go back to before plaintext commit
git push --force origin main

# 4. Update cluster secret
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age-dev-new.agekey \
  --dry-run=client -o yaml | kubectl apply -f -

# 5. Commit correctly encrypted version
git add clusters/dev/secrets/
git commit -m "Add encrypted secrets"
git push origin main
```

### Scenario: Decryption Fails in Flux

**Problem:** Kustomization fails with "no matching key" error.

**Solution:**
```bash
# 1. Verify Kubernetes secret exists
kubectl get secret sops-age -n flux-system -o yaml

# 2. Check secret has correct key
kubectl get secret sops-age -n flux-system -o jsonpath='{.data.age\.agekey}' | \
  base64 -d | grep "public key:"

# 3. Compare with .sops.yaml
grep "age:" clusters/dev/.sops.yaml

# 4. If mismatch, update cluster secret
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age-dev.agekey \
  --dry-run=client -o yaml | kubectl apply -f -

# 5. Trigger Flux reconciliation
flux reconcile kustomization secrets --with-source -v

# 6. Check logs
flux logs -f -k Kustomization/secrets
```

### Scenario: Lost Age Private Key

**Problem:** age.agekey file deleted but needed to decrypt.

**Solution:**
```bash
# If sops-age Secret still exists in cluster, extract it
kubectl get secret sops-age -n flux-system -o yaml > sops-age-secret.yaml
# Edit to extract and base64 decode the age.agekey value

# If secret is gone:
# 1. Rotate to new key
age-keygen -o age-dev-new.agekey

# 2. Re-encrypt all secrets
for file in clusters/dev/secrets/*.yaml; do
  sops --encrypt --in-place "$file"
done

# 3. Create new cluster secret
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age-dev-new.agekey \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. Commit changes
git add clusters/dev/.sops.yaml clusters/dev/secrets/
git commit -m "Rotate to new SOPS key after key loss"
```

---

## Example 8: Production Best Practices

### Complete Production Setup
```bash
#!/bin/bash
# Complete production SOPS setup script

set -e

ENVIRONMENT="prod"
DOMAIN="example.com"
CLUSTER="prod-cluster"

echo "Setting up SOPS for $ENVIRONMENT environment..."

# 1. Generate production key
age-keygen -o "age-${ENVIRONMENT}.agekey"
PUB_KEY=$(grep "public key:" "age-${ENVIRONMENT}.agekey" | cut -d' ' -f3)

# 2. Create production .sops.yaml
mkdir -p "clusters/$ENVIRONMENT/secrets"
cat > "clusters/$ENVIRONMENT/.sops.yaml" << EOF
creation_rules:
  - path_regex: ^.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: $PUB_KEY
EOF

# 3. Add key to .gitignore
grep -q "age-${ENVIRONMENT}.agekey" .gitignore || \
  echo "age-${ENVIRONMENT}.agekey" >> .gitignore

# 4. Create sample secrets
cat > "clusters/$ENVIRONMENT/secrets/database.yaml" << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: databases
type: Opaque
data:
  host: postgres.example.com
  port: "5432"
  username: prod_user
  password: CHANGEME_SECURE_PASSWORD_HERE
EOF

# 5. Encrypt sample secret
sops --encrypt --in-place "clusters/$ENVIRONMENT/secrets/database.yaml"

# 6. Create Kustomization
cat > "clusters/$ENVIRONMENT/kustomization.yaml" << 'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: prod-secrets
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./clusters/prod/secrets
  prune: true
  wait: true
  decryption:
    provider: sops
    secretRef:
      name: sops-age
EOF

# 7. Create cluster secret (on production cluster only)
echo "Create Kubernetes secret on production cluster:"
echo "kubectl create secret generic sops-age \\"
echo "  --namespace=flux-system \\"
echo "  --from-file=age.agekey=age-${ENVIRONMENT}.agekey"

# 8. Add to Git
git add "clusters/$ENVIRONMENT/" .gitignore
git commit -m "Add production SOPS encryption setup"

# 9. Backup key
echo "Backing up production key..."
mkdir -p ~/.sops-backup
cp "age-${ENVIRONMENT}.agekey" ~/.sops-backup/
chmod 600 ~/.sops-backup/*

echo "Production SOPS setup complete!"
echo "Important: Store backup key in secure location (password manager, hardware key)"
```

---

## Example 9: Advanced - GitHub Actions Integration

### Workflow: Encrypt Secrets on PR
```yaml
# .github/workflows/sops-encrypt.yaml

name: SOPS Encryption Check

on:
  pull_request:
    paths:
      - 'clusters/**/secrets/**'

jobs:
  encrypt-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install SOPS
        run: |
          wget https://github.com/getsops/sops/releases/download/v3.7.3/sops-v3.7.3.linux.amd64
          chmod +x sops-v3.7.3.linux.amd64
          sudo mv sops-v3.7.3.linux.amd64 /usr/local/bin/sops

      - name: Check secrets are encrypted
        run: |
          EXIT_CODE=0
          for file in $(find clusters -name "*.yaml" -path "*/secrets/*"); do
            if [[ -f "$file" ]] && ! grep -q "ENC\[" "$file"; then
              echo "ERROR: $file is not encrypted!"
              EXIT_CODE=1
            fi
          done
          exit $EXIT_CODE

      - name: Verify SOPS syntax
        run: |
          for file in $(find clusters -name "*.yaml" -path "*/secrets/*"); do
            sops -d "$file" > /dev/null 2>&1 || {
              echo "ERROR: Cannot decrypt $file"
              exit 1
            }
          done
```

---

## Example 10: Disaster Recovery Testing

### Test Decryption Without Original Machine
```bash
#!/bin/bash
# DR test: Can we decrypt secrets with backed-up key?

echo "Disaster Recovery Test"
echo "====================="

# 1. Restore key from backup
BACKUP_KEY="$HOME/Backups/age-prod.agekey.backup"

if [[ ! -f "$BACKUP_KEY" ]]; then
  echo "ERROR: Backup key not found at $BACKUP_KEY"
  exit 1
fi

# 2. Try decrypting a production secret
export SOPS_AGE_KEY_FILE="$BACKUP_KEY"

for file in clusters/prod/secrets/*.yaml; do
  echo "Testing: $file"
  if sops -d "$file" > /dev/null 2>&1; then
    echo "✓ Successfully decrypted"
  else
    echo "✗ Failed to decrypt"
    exit 1
  fi
done

echo ""
echo "DR Test Passed! Can recover secrets from backup."
```

---

**Last Updated:** January 15, 2025
**Status:** Production Ready
