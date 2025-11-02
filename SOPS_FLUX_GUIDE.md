# Comprehensive Guide: Transparent SOPS Encryption with Flux GitOps

## Executive Summary

This guide covers best practices for implementing transparent SOPS encryption with Flux GitOps to securely manage Kubernetes secrets in version control. The recommended approach uses **age encryption** (modern, simple, designed for files) rather than SSH keys or PGP, combined with Flux's native SOPS decryption provider.

**Key Takeaway:** Age is the recommended encryption method for SOPS because it's simpler than PGP, has smaller keys, and is specifically designed for file encryption. SSH keys can be used as an alternative but require conversion.

---

## Table of Contents

1. [Transparent SOPS Encryption Setup](#transparent-sops-encryption-setup)
2. [Key Management Options](#key-management-options)
3. [Flux Integration](#flux-integration)
4. [Workflow Recommendations](#workflow-recommendations)
5. [Step-by-Step Setup Instructions](#step-by-step-setup-instructions)
6. [Configuration Examples](#configuration-examples)
7. [Common Pitfalls & Solutions](#common-pitfalls--solutions)
8. [Authoritative Sources](#authoritative-sources)

---

## Transparent SOPS Encryption Setup

### Overview

Transparent encryption means developers work with plaintext secrets locally, but commits to Git are automatically encrypted. There are two approaches:

1. **Manual approach:** Developers manually encrypt files before committing (not truly "transparent")
2. **Git integration approach:** Git filters automatically encrypt/decrypt files (true transparency)

### Git Filters vs. Manual Encryption

SOPS doesn't natively support Git filters due to **non-deterministic encryption**—encrypting the same plaintext twice produces different ciphertexts because age uses random IVs. This makes Git unable to detect if the encrypted content has actually changed.

#### Option 1: Git Filters with SOPS (Workaround)

While not officially recommended, you can implement Git filters to automate encryption:

```bash
# Configure smudge filter (decrypts on checkout)
git config --local filter.sops.smudge 'sops --decrypt /dev/stdin'

# Configure clean filter (encrypts on stage)
git config --local filter.sops.clean 'sops --encrypt /dev/stdin'

# Make filter required (prevents accidental commits of plaintext)
git config --local filter.sops.required true
```

**.gitattributes** (in repository root):
```
secrets/** filter=sops
**/secrets.yaml filter=sops
*.secrets.yaml filter=sops
```

**Caveat:** Git will always see encrypted files as "changed" even if plaintext hasn't changed. Use `git diff --cached` to see actual plaintext differences.

#### Option 2: Third-Party Tool (git-sops)

The **git-sops** tool (github.com/cycneuramus/git-sops) provides better Git integration:

```bash
# Initialize git-sops in repository
git-sops init

# Automatically sets up filters and .gitattributes
# Detects encrypted files by looking for SOPS marker: "ENC["
```

**Advantages:**
- Handles non-deterministic encryption better
- Transparent workflow for developers
- Automatic detection of SOPS-encrypted files

**Disadvantage:** Additional tool dependency outside SOPS ecosystem.

#### Option 3: SOPS Edit Command (Recommended for Manual Approach)

For most Flux GitOps workflows, the simplest approach is **manual encryption** using `sops edit`:

```bash
# Edit plaintext, SOPS automatically encrypts on save
sops secrets/app-secret.yaml

# Or encrypt existing file in-place
sops --encrypt --in-place secrets/app-secret.yaml

# Decrypt to view (doesn't modify file)
sops secrets/app-secret.yaml --decrypt
```

**Advantages:**
- Simple, reliable, no Git filter complexity
- Integrates naturally with editor workflows
- Developers understand what's being encrypted

**How it works:**
1. Developer runs `sops secrets/db-password.yaml`
2. SOPS decrypts and opens in `$EDITOR`
3. Developer modifies plaintext
4. SOPS automatically re-encrypts on save
5. Git sees only encrypted content

### Best Practices for .gitattributes

If using Git filters, follow these practices:

```bash
# .gitattributes - Specify which files use SOPS filter

# All files in secrets directories
secrets/** filter=sops

# Specific filename patterns
**/secrets.yaml filter=sops
**/secrets.enc.yaml filter=sops
*.secrets.* filter=sops

# Environment files (if encrypting env vars)
.env.production filter=sops
.env.*.enc filter=sops

# Mark filters as required to prevent plaintext commits
[attr]encrypted diff=sops merge=sops -text
secrets/** encrypted
```

### .gitignore Configuration

**Critical security practice:** Always add local secret files to .gitignore:

```bash
# .gitignore - Prevent accidental plaintext commits

# Local SOPS keys
age.agekey
sops-key.txt
.sops/

# SSH keys (if using ssh-to-age conversion)
.ssh/

# Environment files before encryption
.env.local
.env.*.local
secrets/*.tmp
secrets/*.plain

# Temporary editor files
secrets/*~
secrets/*.swp
```

---

## Key Management Options

### Age Keys (Recommended)

Age is a modern, simple encryption tool specifically designed for file encryption.

#### Advantages:
- **Simple:** Minimal configuration, sensible defaults
- **Small keys:** Easier copy/paste, avoids PGP key management complexity
- **File-focused design:** Built specifically for encrypting files
- **Modern cryptography:** X25519 (Elliptic Curve), more secure than RSA
- **No infrastructure required:** Works offline, no key servers needed
- **Multi-recipient support:** One file encrypted for multiple keys easily

#### Disadvantages:
- **No backward compatibility:** Cannot use existing PGP keys without conversion
- **Cannot encrypt keys at rest:** Private keys must be stored unencrypted (mitigate with strong file permissions)
- **Newer tool:** Less historical usage than PGP (but actively maintained)

#### Setup:

```bash
# Install age and age-keygen
# macOS
brew install age

# Linux
sudo apt-get install age  # or use binary from github.com/FiloSottile/age

# Generate keypair
age-keygen -o age.agekey
# Output includes:
# Private key: AGE-SECRET-KEY-1...
# Public key: age1...

# Save public key in .sops.yaml (safe to share)
# Keep private key in age.agekey (NEVER commit to Git)
echo 'age.agekey' >> .gitignore
```

#### Multiple Recipients (Multi-User Team):

```bash
# Encrypt file for multiple team members' public keys
sops --age=age1-dev,age1-ops,age1-devops --encrypt secrets/database.yaml

# Update .sops.yaml with all team public keys
# Each developer can decrypt with their own private key
```

---

### SSH Keys (Alternative Approach)

SOPS supports using SSH public keys (ed25519 and rsa) as age recipients.

#### Advantages:
- **Reuses existing infrastructure:** No need for separate key distribution
- **Team already uses SSH:** Leverages github.com identities or GitLab keys
- **Decentralized identity:** Public keys are already published (GitHub profiles)

#### Disadvantages:
- **Not designed for file encryption:** Age is more modern alternative
- **Key lifecycle complexity:** SSH keys have specific purposes (authentication vs. encryption)
- **Cannot directly use SSH private keys:** Must convert using ssh-to-age first
- **Limited key formats:** Only ssh-ed25519 and ssh-rsa supported

#### SSH Key Usage with SOPS (Direct):

```bash
# Using SSH public keys directly as SOPS recipients
# (Doesn't require ssh-to-age conversion)

# SOPS can encrypt with SSH public key format
sops --age=ssh-ed25519 AAAA... --encrypt secrets/app.yaml

# For decryption, SOPS looks for:
# 1. ~/.ssh/id_ed25519
# 2. ~/.ssh/id_rsa (fallback)

# Or specify explicit private key location
export SOPS_AGE_SSH_PRIVATE_KEY_FILE=~/.ssh/custom_key
sops secrets/app.yaml
```

**Note:** SOPS automatically detects SSH keys in standard locations. This is useful if you already have SSH keys and want to avoid managing separate age keys.

#### Converting SSH Keys to Age (ssh-to-age):

If you want to convert SSH Ed25519 keys to age format for better encryption/decryption separation:

```bash
# Install ssh-to-age
# macOS
brew install Mic92/ssh-to-age/ssh-to-age

# Linux - install from github.com/Mic92/ssh-to-age

# Convert SSH private key to age format
ssh-to-age -private-key -i ~/.ssh/id_ed25519 -o age.agekey

# For encrypted SSH keys, export passphrase
export SSH_TO_AGE_PASSPHRASE="your-ssh-key-passphrase"
ssh-to-age -private-key -i ~/.ssh/id_ed25519 -o age.agekey

# Convert SSH public key (for reference)
ssh-to-age -i ~/.ssh/id_ed25519.pub
# Output: age1...
```

**Use Cases:**
- You want age format but already have SSH keys
- You're consolidating authentication and encryption keys
- You need to export public keys for team sharing

---

### Key Management Best Practices

Regardless of method (age or SSH):

1. **Backup privately generated keys offline**
   ```bash
   # For age keys generated just for SOPS
   cp age.agekey ~/Backups/age.agekey.backup
   chmod 600 ~/Backups/age.agekey.backup

   # Store in password manager (1Password, Bitwarden, etc.)
   # Or encrypted offline storage (Hardware key, USB drive)
   ```

2. **Use strong file permissions**
   ```bash
   chmod 600 age.agekey          # Only owner can read
   chmod 600 ~/.ssh/id_ed25519   # SSH keys also restricted
   ```

3. **Never commit private keys**
   ```bash
   # Verify before committing
   git status
   # Should NOT show age.agekey or .ssh/ files
   ```

4. **Rotate keys periodically**
   ```bash
   # SOPS provides key rotation
   sops --rotate-age secrets/database.yaml
   # Re-encrypts file with new key, can remove old recipients
   ```

5. **Use SOPS updatekeys for team onboarding**
   ```bash
   # Add new team member's public key to encrypted files
   sops updatekeys secrets/database.yaml
   # Prompts to add/remove keys
   ```

6. **For multiple clusters/environments, use separate keys**
   ```bash
   # Development cluster
   age-keygen -o age-dev.agekey

   # Production cluster
   age-keygen -o age-prod.agekey

   # Different .sops.yaml per directory
   # See "Flux Integration" section
   ```

---

## Flux Integration

### Architecture Overview

Flux's kustomize-controller handles SOPS decryption automatically:

```
1. Git Repository
   └── secrets/
       └── database.yaml (SOPS encrypted)

2. Flux GitRepository watches Git

3. kustomize-controller finds Kustomization with decryption provider

4. kustomize-controller retrieves sops-age Secret from flux-system namespace

5. kustomize-controller calls SOPS to decrypt using Secret's private key

6. Decrypted secret is applied to cluster

7. SOPS encrypted file remains in Git (plaintext never stored)
```

### Step 1: Generate Age Key

```bash
# Generate keypair
age-keygen -o age.agekey

# Extract public key (save to .sops.yaml)
grep "public key:" age.agekey
# Output: public key: age1helqcqsh9464r8chnwc2fzj8uv7vr5ntnsft0tn45v2xtz0hpfwq98cmsg

# Extract private key (for creating Kubernetes Secret)
cat age.agekey
```

### Step 2: Create Kubernetes Secret

Store the age private key in flux-system namespace:

```bash
# Method 1: From file
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age.agekey \
  --dry-run=client -o yaml | kubectl apply -f -

# Method 2: Using kubectl directly
cat age.agekey | kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/dev/stdin

# Method 3: YAML manifest (for GitOps)
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age.agekey \
  --dry-run=client -o yaml > sops-age-secret.yaml

# Then commit sops-age-secret.yaml (not age.agekey!)
# The Secret resource gets encrypted by Flux SOPS
```

**Important:** The filename MUST end with `.agekey` for SOPS to recognize it as an age key.

### Step 3: Create .sops.yaml

Configure SOPS to know which key encrypts which files:

```yaml
# .sops.yaml - SOPS configuration (repository root)

creation_rules:
  # Match any secret files and use age encryption
  - path_regex: ^secrets/.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: age1helqcqsh9464r8chnwc2fzj8uv7vr5ntnsft0tn45v2xtz0hpfwq98cmsg
```

**Key points:**
- `path_regex`: Which files this rule applies to
- `encrypted_regex`: Only encrypt `data` and `stringData` fields (not metadata)
- `age`: Public key for encryption

### Step 4: Encrypt Secrets

```bash
# Create a test secret
cat > secrets/database.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
  namespace: default
type: Opaque
data:
  username: admin
  password: supersecret123
EOF

# Encrypt using SOPS (reads .sops.yaml automatically)
sops --encrypt --in-place secrets/database.yaml

# Verify encryption
cat secrets/database.yaml
# Should show: "ENC[AES256_GCM,data:...]" for encrypted fields
```

### Step 5: Configure Flux Kustomization

Update your Flux Kustomization to use SOPS decryption:

```yaml
# clusters/my-cluster/kustomization.yaml
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
  path: ./secrets
  prune: true

  # Add decryption configuration
  decryption:
    provider: sops
    secretRef:
      name: sops-age  # Must exist in flux-system namespace
```

### Flux Reconciliation Flow

Once configured, Flux automatically:

1. **Watches repository:** GitRepository source checks for changes every interval
2. **Detects encrypted files:** Kustomization finds YAML files with SOPS markers
3. **Retrieves decryption key:** Reads sops-age Secret from flux-system
4. **Decrypts:** Calls SOPS binary with age key to decrypt
5. **Applies resources:** Sends unencrypted Secret to Kubernetes API
6. **Stores encrypted in Git:** Original repository retains encrypted files

```bash
# Monitor reconciliation
flux logs -f -k Kustomization/secrets

# Check SOPS decryption status
kubectl describe kustomization secrets -n flux-system

# View decrypted secret (in cluster only, not Git)
kubectl get secret database-credentials -o yaml
```

### Multiple Clusters with Different Keys

For production setups with separate dev/staging/prod clusters:

```
├── .sops.yaml                    # Default config
├── clusters/
│   ├── dev/
│   │   ├── .sops.yaml            # Uses dev age key
│   │   ├── secrets/
│   │   │   └── database.yaml      # Encrypted with dev key
│   │   └── kustomization.yaml
│   ├── prod/
│   │   ├── .sops.yaml            # Uses prod age key
│   │   ├── secrets/
│   │   │   └── database.yaml      # Encrypted with prod key
│   │   └── kustomization.yaml
```

**clusters/dev/.sops.yaml:**
```yaml
creation_rules:
  - path_regex: ^.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: age1dev...  # Development key
```

**clusters/prod/.sops.yaml:**
```yaml
creation_rules:
  - path_regex: ^.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: age1prod... # Production key
```

Each cluster's Kustomization references its own sops-age Secret in its namespace.

---

## Workflow Recommendations

### Developer Workflow

Developers should follow this process:

```bash
# 1. Clone repository
git clone <flux-repo>
cd <flux-repo>

# 2. Create new secret
cat > secrets/new-api-key.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: api-credentials
  namespace: default
data:
  api-key: "my-secret-key-123"
EOF

# 3. Encrypt with SOPS
sops --encrypt --in-place secrets/new-api-key.yaml

# 4. Verify encryption (should show ENC[...])
grep -A2 "data:" secrets/new-api-key.yaml

# 5. Commit encrypted file
git add secrets/new-api-key.yaml
git commit -m "Add API credentials secret"
git push

# 6. Delete local plaintext copies (if not in .gitignore)
rm -f secrets/*.tmp
```

### Edit Existing Secret

```bash
# SOPS handles encryption/decryption transparently
sops secrets/database.yaml

# Opens decrypted file in $EDITOR
# On save, SOPS automatically re-encrypts
# Commit encrypted file

git add secrets/database.yaml
git commit -m "Update database password"
git push
```

### View Secret Without Editing

```bash
# Decrypt to stdout (doesn't modify file)
sops -d secrets/database.yaml

# Or use sops' JSON output
sops -d -o json secrets/database.yaml | jq .data
```

### Team Collaboration

When a new team member joins:

```bash
# New team member generates their age key
age-keygen -o ~/.sops/key.txt

# Share public key with team
grep "public key:" ~/.sops/key.txt
# age1newteammember...

# Team lead adds to .sops.yaml and existing files
sops updatekeys secrets/database.yaml
# Prompts to add/remove keys

# Or add directly to .sops.yaml and re-encrypt all files
# Update .sops.yaml with new public key
vi .sops.yaml
# age: age1existing,age1newteammember

# Re-encrypt all secrets to include new key
for file in secrets/*.yaml; do
  sops --encrypt --in-place "$file"
done

git add .sops.yaml secrets/
git commit -m "Add team member to SOPS encryption"
```

### Directory Structure

Recommended structure for multi-environment setups:

```
flux-repo/
├── .gitignore
├── .sops.yaml                   # Root SOPS config
├── .github/
│   └── workflows/               # GitHub Actions (if using)
├── clusters/
│   ├── dev/
│   │   ├── .sops.yaml          # Dev-specific config (optional)
│   │   ├── kustomization.yaml
│   │   └── secrets/
│   │       ├── database.yaml    # SOPS encrypted
│   │       ├── api-keys.yaml
│   │       └── tls-certs.yaml
│   ├── staging/
│   │   ├── .sops.yaml          # Staging-specific config
│   │   ├── kustomization.yaml
│   │   └── secrets/
│   │       ├── database.yaml    # Different key than dev
│   │       └── api-keys.yaml
│   └── prod/
│       ├── .sops.yaml          # Prod-specific config
│       ├── kustomization.yaml
│       └── secrets/
│           ├── database.yaml    # Different key than staging
│           └── api-keys.yaml
├── infrastructure/
│   ├── flux-system/
│   │   ├── gotk-components.yaml
│   │   ├── gotk-sync.yaml
│   │   └── kustomization.yaml
│   └── traefik/
│       └── kustomization.yaml
└── README.md
```

### Avoiding Common Mistakes

1. **Don't commit unencrypted secrets**
   ```bash
   # BAD: File committed plaintext
   git add secrets/password.yaml  # Oops!

   # GOOD: Always encrypt first
   sops --encrypt --in-place secrets/password.yaml
   git add secrets/password.yaml
   ```

2. **Don't use kubectl apply on encrypted files**
   ```bash
   # BAD: kubectl can't decrypt
   kubectl apply -f secrets/database.yaml  # Error!

   # GOOD: Let Flux handle it
   # Just commit to Git, Flux decrypts and applies
   ```

3. **Don't lose age private key**
   ```bash
   # Keep backup
   cp age.agekey ~/Backups/

   # Store passphrase in password manager
   # (Though age keys are unencrypted, you can password-protect backup)
   ```

4. **Don't mix encrypted and plaintext in same file**
   ```yaml
   # BAD: Mixing encrypted and plaintext
   data:
     username: admin              # plaintext
     password: ENC[AES256_GCM...] # encrypted

   # GOOD: Encrypt entire data section
   data: ENC[AES256_GCM,data:...]
   ```

5. **Don't forget .gitignore**
   ```bash
   # Must add before committing
   echo 'age.agekey' >> .gitignore
   echo '.sops/' >> .gitignore

   # Verify with
   git check-ignore age.agekey
   ```

---

## Step-by-Step Setup Instructions

### Complete Setup from Scratch

#### Prerequisites

```bash
# Install required tools
brew install sops age                    # macOS
# or
sudo apt-get install sops age            # Ubuntu/Debian

# Verify installations
sops --version    # v3.x.x
age --version     # 1.x.x

# Flux must be installed on cluster
flux --version    # v2.x.x
```

#### Phase 1: Local Setup

```bash
# 1. Generate age keypair
age-keygen -o age.agekey

# 2. Extract public key
PUB_KEY=$(grep "public key:" age.agekey | cut -d' ' -f3)
echo "Public key: $PUB_KEY"

# 3. Create .sops.yaml at repo root
cat > .sops.yaml << EOF
creation_rules:
  - path_regex: ^clusters/.*secrets/.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: $PUB_KEY
EOF

# 4. Add to .gitignore
cat >> .gitignore << 'EOF'
# SOPS encryption keys
age.agekey
.sops/
sops-key.txt

# Local secret files
.env.local
secrets/*.tmp
EOF

# 5. Test encryption
mkdir -p clusters/dev/secrets
cat > clusters/dev/secrets/test.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: test
data:
  key: "plaintext-value"
EOF

sops --encrypt --in-place clusters/dev/secrets/test.yaml

# Verify encryption
grep "ENC\[" clusters/dev/secrets/test.yaml  # Should show encrypted marker

# 6. Commit to repository
git add .sops.yaml .gitignore clusters/dev/secrets/test.yaml
git commit -m "Add SOPS encryption configuration"
```

#### Phase 2: Kubernetes Setup

```bash
# 1. Create sops-age Secret in cluster
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age.agekey \
  --dry-run=client -o yaml > sops-age-secret.yaml

# 2. Review secret (don't commit age.agekey!)
cat sops-age-secret.yaml

# 3. Apply to cluster
kubectl apply -f sops-age-secret.yaml

# 4. Verify secret exists
kubectl get secret sops-age -n flux-system -o yaml

# 5. Delete local age.agekey if you have backup
# (Optional - keep if you need to decrypt locally)
```

#### Phase 3: Flux Configuration

```bash
# 1. Update Kustomization with decryption
cat > clusters/dev/kustomization.yaml << 'EOF'
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
  path: ./clusters/dev/secrets
  prune: true
  decryption:
    provider: sops
    secretRef:
      name: sops-age
EOF

# 2. Apply Kustomization
kubectl apply -f clusters/dev/kustomization.yaml

# 3. Monitor reconciliation
flux logs -f -k Kustomization/secrets

# 4. Verify secret was decrypted and applied
kubectl get secret test -n default -o yaml
# Should show decrypted value
```

#### Phase 4: Production Setup

```bash
# 1. Generate separate keys for each environment
age-keygen -o age-prod.agekey
age-keygen -o age-staging.agekey

# 2. Create separate .sops.yaml files
mkdir -p clusters/prod clusters/staging

# For prod/
cat > clusters/prod/.sops.yaml << EOF
creation_rules:
  - path_regex: ^.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: $(grep "public key:" age-prod.agekey | cut -d' ' -f3)
EOF

# For staging/
cat > clusters/staging/.sops.yaml << EOF
creation_rules:
  - path_regex: ^.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: $(grep "public key:" age-staging.agekey | cut -d' ' -f3)
EOF

# 3. Create secrets in each cluster namespace
kubectl create secret generic sops-age \
  --namespace=prod-system \
  --from-file=age.agekey=age-prod.agekey \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic sops-age \
  --namespace=staging-system \
  --from-file=age.agekey=age-staging.agekey \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. Update Kustomizations for each environment
# (Each references sops-age in its namespace)
```

---

## Configuration Examples

### Basic .sops.yaml (Single Environment)

```yaml
creation_rules:
  - path_regex: ^secrets/.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: age1helqcqsh9464r8chnwc2fzj8uv7vr5ntnsft0tn45v2xtz0hpfwq98cmsg
```

### Multi-Environment .sops.yaml

```yaml
creation_rules:
  # Development secrets
  - path_regex: ^clusters/dev/.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: age1dev-key-goes-here

  # Staging secrets
  - path_regex: ^clusters/staging/.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: age1staging-key-goes-here

  # Production secrets
  - path_regex: ^clusters/prod/.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: age1prod-key-goes-here

  # Fallback rule (matches everything else)
  - encrypted_regex: ^(data|stringData)$
    age: age1default-key-goes-here
```

### Multi-User Team .sops.yaml

```yaml
creation_rules:
  - path_regex: ^secrets/.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    # All team members can decrypt with their own key
    age: |
      age1alice-public-key-here,
      age1bob-public-key-here,
      age1charlie-public-key-here
```

### Kubernetes Secret Example (Encrypted)

```yaml
# Before encryption (development only)
apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
  namespace: default
type: Opaque
data:
  username: YWRtaW4=            # base64(admin)
  password: cGFzc3dvcmQxMjM=    # base64(password123)
```

```yaml
# After SOPS encryption
apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
  namespace: default
type: Opaque
data:
  username: ENC[AES256_GCM,data:t3FHOwECrA==,iv:OW1U7KKmXo2Mg/tV+O8r/hkddjRRfnFBYfSU1q7YJJ8=,tag:n1yfHJHa/3g3F3s7a8E0Mw==,type:str]
  password: ENC[AES256_GCM,data:YK8rwB==,iv:zHJU1QRzYQ==,tag:aT/lPRs=,type:str]
sops:
  kms: []
  gcp_kms: []
  azure_kms: []
  hc_vault: []
  age:
    - recipient: age1helqcqsh9464r8chnwc2fzj8uv7vr5ntnsft0tn45v2xtz0hpfwq98cmsg
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        AgEEAg0A...
        -----END AGE ENCRYPTED FILE-----
  lastmodified: "2024-01-15T10:30:00Z"
  mac: ENC[AES256_GCM,data:abc123==,iv:xyz==,tag:def==,type:str]
  pgp: []
  unencrypted_suffix: _unencrypted
  version: 3.7.3
```

### Flux Kustomization with SOPS

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: secrets
  namespace: flux-system
spec:
  interval: 10m0s
  retryInterval: 1m0s
  timeout: 5m0s

  # Git source
  sourceRef:
    kind: GitRepository
    name: flux-system

  # Secrets location in repo
  path: ./clusters/prod/secrets

  # Prune removed resources
  prune: true
  wait: true

  # SOPS decryption configuration
  decryption:
    provider: sops
    secretRef:
      name: sops-age
      # Optional: specify different namespace
      # namespace: custom-namespace

  # Post-build substitutions (if needed)
  postBuild:
    substitute:
      ENV: production
```

### GitRepository with SOPS

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 1m0s
  url: https://github.com/your-org/flux-config.git
  ref:
    branch: main
  secretRef:
    name: flux-system  # Git credentials if private repo
  ignore: |
    # Untracked patterns
    age.agekey
    .sops/
    **/*.tmp
```

### Environment-Specific Secrets

```yaml
# clusters/prod/secrets/database.yaml (encrypted with prod key)
apiVersion: v1
kind: Secret
metadata:
  name: postgres
  namespace: databases
type: Opaque
data:
  host: ENC[AES256_GCM,...]      # prod.db.example.com
  port: ENC[AES256_GCM,...]       # 5432
  username: ENC[AES256_GCM,...]   # prod_user
  password: ENC[AES256_GCM,...]   # secure_prod_password
```

```yaml
# clusters/dev/secrets/database.yaml (encrypted with dev key)
apiVersion: v1
kind: Secret
metadata:
  name: postgres
  namespace: databases
type: Opaque
data:
  host: ENC[AES256_GCM,...]      # dev.db.local
  port: ENC[AES256_GCM,...]       # 5433
  username: ENC[AES256_GCM,...]   # dev_user
  password: ENC[AES256_GCM,...]   # dev_password
```

---

## Common Pitfalls & Solutions

### Pitfall 1: Non-Deterministic Encryption

**Symptom:** Git shows file as "changed" every time you decrypt/re-encrypt, even though plaintext hasn't changed.

**Root Cause:** Age encryption uses random IVs, so encrypting the same plaintext twice produces different ciphertexts.

**Solutions:**
1. **Accept it:** Use `git diff --cached` to view plaintext differences, not encrypted diffs
2. **Use git-sops:** Third-party tool that handles this better
3. **Manual workflow:** Only encrypt files when actually modified (don't re-encrypt unnecessarily)

```bash
# Check what actually changed (not just encryption)
sops -d clusters/dev/secrets/database.yaml > /tmp/old.txt
# Make changes...
sops --encrypt --in-place clusters/dev/secrets/database.yaml
sops -d clusters/dev/secrets/database.yaml > /tmp/new.txt
diff /tmp/old.txt /tmp/new.txt  # Actual plaintext changes
```

### Pitfall 2: Accidental Plaintext Commits

**Symptom:** Plaintext secrets accidentally committed to Git history.

**Root Causes:**
- Forgot to encrypt before committing
- File not in .gitignore
- Git filter not properly configured

**Solutions:**

```bash
# 1. Add to .gitignore immediately
echo 'age.agekey' >> .gitignore
echo 'secrets/*.tmp' >> .gitignore

# 2. Use git hooks to prevent commits
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Prevent committing unencrypted secrets

if git diff --cached --name-only | grep -E "secrets/.*\.yaml"; then
  for file in $(git diff --cached --name-only | grep -E "secrets/.*\.yaml"); do
    if ! grep -q "ENC\[" "$file"; then
      echo "ERROR: $file is not encrypted!"
      echo "Run: sops --encrypt --in-place $file"
      exit 1
    fi
  done
fi
EOF
chmod +x .git/hooks/pre-commit

# 3. If already committed, rotate the key
age-keygen -o age-new.agekey
# Update all secrets with new key
# Force-push Git history (dangerous, coordinate with team)
```

### Pitfall 3: Lost Age Private Key

**Symptom:** Cannot decrypt secrets; age.agekey file deleted or lost.

**Root Causes:**
- No backup of age.agekey
- Key stored only locally without backup
- Machine failure before backup created

**Solutions:**

```bash
# PREVENTION: Backup immediately
cp age.agekey ~/Backups/age.agekey.backup.$(date +%Y%m%d)
chmod 600 ~/Backups/age.agekey.backup.*

# Store in password manager
# Example: 1Password, Bitwarden, LastPass
# - Save both public and private key
# - Keep copy offline

# RECOVERY: If cluster has sops-age Secret
# Extract from cluster to new machine
kubectl get secret sops-age -n flux-system -o yaml
# Decode base64 and reconstruct age.agekey

# Or rotate to new key
# Generate new key, update all secrets, re-deploy
```

### Pitfall 4: Wrong Secret Reference in Kustomization

**Symptom:** Decryption fails with "secret not found" error.

**Root Causes:**
- Secret name mismatch (sops-age vs. sops-age-key)
- Secret in wrong namespace
- Secret key doesn't end with `.agekey`

**Solutions:**

```bash
# Verify secret exists
kubectl get secret sops-age -n flux-system -o yaml

# Check secret has correct key
kubectl get secret sops-age -n flux-system -o jsonpath='{.data}' | jq keys

# Verify Kustomization references correct secret
kubectl get kustomization secrets -n flux-system -o yaml | grep -A3 decryption

# Re-create secret if needed
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age.agekey \
  --dry-run=client -o yaml | kubectl apply -f -

# Check Flux logs
flux logs -f -k Kustomization/secrets
```

### Pitfall 5: Encryption with Wrong Public Key

**Symptom:** Cluster cannot decrypt secrets; "no matching key" error.

**Root Causes:**
- Used wrong age public key in .sops.yaml
- Public key mismatch between .sops.yaml and sops-age Secret
- Used dev key to encrypt prod secrets

**Solutions:**

```bash
# Verify public key matches
# From sops-age Secret
kubectl get secret sops-age -n flux-system -o jsonpath='{.data.age\.agekey}' | \
  base64 -d | grep "public key:"

# From .sops.yaml
grep -A5 "creation_rules:" .sops.yaml | grep "age:"

# If mismatch, regenerate:
# 1. Generate new age key
age-keygen -o age.agekey

# 2. Update .sops.yaml with new public key
# 3. Re-encrypt all secrets
for file in clusters/prod/secrets/*.yaml; do
  sops --encrypt --in-place "$file"
done

# 4. Update cluster Secret
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age.agekey \
  --dry-run=client -o yaml | kubectl apply -f -

# 5. Commit to Git
git add .sops.yaml clusters/prod/secrets/
git commit -m "Rotate SOPS encryption keys"
```

### Pitfall 6: SOPS Binary Not Found in Container

**Symptom:** Flux reconciliation fails: "sops not found" or "command not found".

**Root Cause:** kustomize-controller image doesn't include SOPS binary.

**Solutions:**

```bash
# 1. Check Flux version (modern versions include SOPS)
flux --version  # v2.x.x should include sops

# 2. Upgrade Flux if needed
flux bootstrap github \
  --owner=your-org \
  --repo=flux-config \
  --branch=main \
  --path=clusters/dev

# 3. Or use custom Flux controller image with SOPS
# Create custom Dockerfile with SOPS included
# This is rarely needed with recent Flux versions

# Verify SOPS is available
kubectl exec -it -n flux-system \
  deployment/kustomize-controller -- \
  which sops
```

### Pitfall 7: Flux Cannot Access Private Git Repository

**Symptom:** GitRepository fails to sync; "authentication failed" error.

**Root Cause:** Git credentials not provided when repository is private.

**Solutions:**

```bash
# 1. Create Git credential Secret
kubectl create secret generic flux-system \
  --namespace=flux-system \
  --from-literal=username=your-github-user \
  --from-literal=password=your-github-token \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. Reference in GitRepository
cat > clusters/dev/git-source.yaml << 'EOF'
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system
  namespace: flux-system
spec:
  url: https://github.com/your-org/flux-config.git
  ref:
    branch: main
  secretRef:
    name: flux-system  # References credential Secret
EOF

# 3. Or use SSH
kubectl create secret generic flux-system \
  --namespace=flux-system \
  --from-file=identity=/path/to/ssh/key \
  --from-file=identity.pub=/path/to/ssh/key.pub \
  --from-file=known_hosts=/path/to/known_hosts \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Pitfall 8: Encrypted Metadata (Kind, ApiVersion)

**Symptom:** Flux fails to recognize resource type; "unknown kind" error.

**Root Cause:** Encrypted metadata instead of just data/stringData.

**Solutions:**

```bash
# WRONG: Entire Secret encrypted
apiVersion: v1
kind: ENC[AES256_GCM,...]    # ❌ Encrypted!
metadata: ENC[...]

# RIGHT: Only data section encrypted
apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
data: ENC[AES256_GCM,...]     # ✅ Only data encrypted

# Verify with
cat secrets/database.yaml | head -10
# Should show plaintext kind, apiVersion, metadata
# Should show ENC[...] only in data section
```

---

## Authoritative Sources

### Official Documentation

1. **Flux GitOps - SOPS Integration**
   - https://fluxcd.io/flux/guides/mozilla-sops/
   - Official Flux documentation on SOPS setup
   - Step-by-step instructions for age + Flux
   - Configuration examples and best practices

2. **Mozilla SOPS GitHub Repository**
   - https://github.com/getsops/sops
   - Source code, examples, and issue tracking
   - Comprehensive README with all features
   - Discussion forum for advanced topics

3. **age Encryption Tool**
   - https://github.com/FiloSottile/age
   - Official age repository
   - Installation instructions for all platforms
   - Small, readable codebase

4. **Flux Documentation - Secrets Management**
   - https://fluxcd.io/flux/security/secrets-management/
   - Overview of secret management strategies with Flux
   - Comparison of SOPS, Sealed Secrets, and External Secrets Operator
   - Security best practices

### Community Resources

5. **Encrypted GitOps Secrets with Flux and age** (Major Hayden)
   - https://major.io/p/encrypted-gitops-secrets-with-flux-and-age/
   - Practical walkthrough with real examples
   - Security considerations
   - Common mistakes and solutions

6. **Using SOPS with Age and Git like a Pro** (devops.datenkollektiv.de)
   - https://devops.datenkollektiv.de/using-sops-with-age-and-git-like-a-pro.html
   - Advanced Git integration techniques
   - Multi-user team setup
   - Git filter configuration

7. **Flux Secret Management with SOPS age** (Budiman JoJo)
   - https://budimanjojo.com/2021/10/23/flux-secret-management-with-sops-age/
   - Step-by-step practical guide
   - Multiple cluster setup
   - Production considerations

8. **A Comprehensive Guide to SOPS** (GitGuardian)
   - https://blog.gitguardian.com/a-comprehensive-guide-to-sops/
   - In-depth feature overview
   - Multiple encryption backends
   - Advanced usage patterns

### Tool Documentation

9. **ssh-to-age Tool**
   - https://github.com/Mic92/ssh-to-age
   - Convert SSH Ed25519 keys to age format
   - Useful if migrating from SSH-based encryption
   - Works with sops-nix projects

10. **git-sops Integration Tool**
    - https://github.com/cycneuramus/git-sops
    - Git filter integration for transparent encryption
    - Addresses non-deterministic encryption issue
    - Simplified workflow for teams

### Related Flux Components

11. **Kustomize Controller - Decryption**
    - https://fluxcd.io/flux/components/kustomize/kustomizations/#decryption
    - Configuration options for SOPS decryption
    - Multiple provider support
    - Secret reference configuration

12. **External Secrets Operator** (Alternative)
    - https://external-secrets.io/
    - Alternative to SOPS for external secret management
    - Integration with vaults (HashiCorp, AWS Secrets Manager, etc.)
    - Use when centralized secret management preferred

---

## Summary & Recommendations

### Quick Decision Tree

**Should you use SOPS with Flux?**
- ✅ YES if: You want secrets in Git with local encryption
- ✅ YES if: Your team is distributed and needs audit trails
- ✅ YES if: You prefer GitOps with everything in version control
- ❌ NO if: You already have external secret vault (use External Secrets Operator instead)

**Which encryption method (age vs SSH)?**
- ✅ **Use age** if: New projects, team comfort with new tools, modern cryptography preferred
- ✅ **Use SSH** if: Team already has SSH infrastructure, want to reuse existing keys
- ✅ **Use ssh-to-age** if: Migrating from SSH, want age benefits with existing key infrastructure

### Recommended Approach

For most teams:

1. **Use age encryption** (modern, simple, designed for files)
2. **Manual workflow** with `sops edit` (no Git filter complexity)
3. **Separate keys per environment** (dev/staging/prod isolation)
4. **Backup keys offline** (password manager or encrypted USB)
5. **Use Flux Kustomization decryption provider** (native, no external tools)

### Production Checklist

Before deploying to production:

- [ ] Age keys generated and backed up securely
- [ ] sops-age Secret created in all clusters
- [ ] All sensitive files encrypted with SOPS
- [ ] .sops.yaml configured correctly for each environment
- [ ] Kustomization resources have decryption provider configured
- [ ] GitRepository has authentication configured
- [ ] .gitignore includes all local secret files
- [ ] Pre-commit hooks prevent plaintext commits
- [ ] Team trained on SOPS workflow
- [ ] Key rotation plan documented
- [ ] Disaster recovery tested (can decrypt without original machine)
- [ ] Access logs and audit trail configured

### Next Steps

1. **Start with test cluster:** Set up SOPS on dev/staging cluster first
2. **Document for team:** Create team runbook with examples
3. **Automate where possible:** Pre-commit hooks, CI/CD validation
4. **Review regularly:** Audit encrypted files, verify key access
5. **Plan for rotation:** Schedule regular key rotation (annually recommended)

---

## Appendix: Useful Commands

### SOPS Operations

```bash
# Encrypt a file
sops --encrypt --in-place secrets/database.yaml

# Decrypt a file
sops --decrypt secrets/database.yaml

# Edit and re-encrypt transparently
sops secrets/database.yaml

# Check if file is encrypted
grep "ENC\[" secrets/database.yaml

# Rotate encryption keys
sops --rotate-age secrets/database.yaml

# Update encryption recipients
sops updatekeys secrets/database.yaml

# Encrypt only specific fields
sops --encrypted-regex '^(data|stringData)$' --encrypt --in-place secrets/file.yaml

# Bulk encrypt directory
for file in secrets/*.yaml; do
  sops --encrypt --in-place "$file"
done
```

### Age Operations

```bash
# Generate key pair
age-keygen -o age.agekey

# Extract public key
grep "public key:" age.agekey

# Extract private key for Kubernetes Secret
cat age.agekey

# Encrypt file directly with age (not using SOPS)
age -r age1... plaintext.txt > plaintext.txt.age

# Decrypt with age
age -d age.agekey plaintext.txt.age > plaintext.txt
```

### Flux Operations

```bash
# Create SOPS Secret
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=age.agekey

# View Secret
kubectl get secret sops-age -n flux-system -o yaml

# Check Kustomization status
kubectl get kustomization -A

# View Kustomization details
kubectl describe kustomization secrets -n flux-system

# Monitor reconciliation
flux logs -f -k Kustomization/secrets

# Trigger manual reconciliation
flux reconcile kustomization secrets --with-source -v

# Check decrypted secrets in cluster
kubectl get secret database-credentials -o yaml
```

### Debugging

```bash
# Check if sops is available
kubectl exec -it -n flux-system deployment/kustomize-controller -- which sops

# Check Flux controller logs
flux logs -f -k Kustomization

# Test SOPS locally
sops secrets/database.yaml  # Should open in editor

# Verify file encryption
file secrets/database.yaml | grep -i encrypted
# or
head -5 secrets/database.yaml | grep ENC

# List all keys in encrypted file
sops -d secrets/database.yaml | jq keys

# Check .sops.yaml is valid YAML
yamllint .sops.yaml
```

---

**Last Updated:** 2025-01-15
**Status:** Production Ready
**Maintenance:** Review and update documentation annually
