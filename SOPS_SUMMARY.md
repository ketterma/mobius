# SOPS + Flux GitOps Implementation Summary

## Quick Reference

### Recommended Approach
- **Encryption Method:** Age (modern, simple, file-focused)
- **Key Distribution:** Separate keys per environment (dev/staging/prod)
- **Workflow:** Manual with `sops edit` (simplest, most reliable)
- **Flux Integration:** Native SOPS decryption provider in Kustomization

### Architecture Flow
```
Git Repository
  └── SOPS-encrypted secrets (plaintext never stored)
      ├── clusters/dev/secrets/
      ├── clusters/staging/secrets/
      └── clusters/prod/secrets/

                    ↓

        Flux GitRepository watches

                    ↓

kustomize-controller detects Kustomization
  with: decryption.provider=sops

                    ↓

Retrieves sops-age Secret from cluster
  (contains age private key)

                    ↓

SOPS decrypts secrets using age key

                    ↓

Decrypted Secret applied to Kubernetes
  (plaintext never stored in Git)
```

---

## Setup Checklist

- [ ] Install tools: `brew install sops age` (macOS) or `apt-get install sops age` (Linux)
- [ ] Generate age keypair: `age-keygen -o age.agekey`
- [ ] Extract public key: `grep "public key:" age.agekey`
- [ ] Create `.sops.yaml` with public key in repository root
- [ ] Add `age.agekey` to `.gitignore`
- [ ] Create test secret and encrypt: `sops --encrypt --in-place test.yaml`
- [ ] Create Kubernetes Secret: `kubectl create secret generic sops-age --namespace=flux-system --from-file=age.agekey=age.agekey`
- [ ] Update Kustomization with `decryption.provider: sops`
- [ ] Verify Flux reconciliation with encrypted secrets
- [ ] Document workflow for team
- [ ] Backup age.agekey offline (password manager or encrypted storage)

---

## Key Decision Points

### 1. Encryption Method
| Method | Pros | Cons | Best For |
|--------|------|------|----------|
| **Age** | Simple, modern, file-focused | No backward compatibility | New projects ✓ |
| **SSH Keys** | Reuses existing keys | Complex, not designed for files | Legacy SSH infrastructure |
| **PGP** | Long history, mature | Complex, key management overhead | Not recommended anymore |

**Recommendation:** Use **age** for all new setups.

### 2. Key Management
| Approach | Pros | Cons | Best For |
|----------|------|------|----------|
| **Single key for all** | Simple | Single point of failure | Dev/test environments |
| **Separate per environment** | Better isolation, security | More keys to manage | Production ✓ |
| **Per-team-member key** | Decentralized, audit trail | Complex rotation | Large teams |

**Recommendation:** Separate keys per environment (dev/staging/prod).

### 3. Git Filter vs Manual Encryption
| Approach | Pros | Cons | Best For |
|----------|------|------|----------|
| **Git filter (sops)** | Automatic, transparent | Non-deterministic, git sees constant changes | Development workflows |
| **git-sops tool** | Better transparency | External tool dependency | Teams that need smooth Git UX |
| **Manual `sops edit`** | Simple, reliable, no filter complexity | Requires manual steps | Production ✓ |

**Recommendation:** Use **manual workflow** with `sops edit` for simplicity and reliability.

### 4. Secret Storage Location
| Pattern | Example | Use Case |
|---------|---------|----------|
| **secrets/ prefix** | `secrets/database.yaml` | Simple projects |
| **Cluster-specific** | `clusters/prod/secrets/` | Multi-cluster setups ✓ |
| **App-namespace** | `apps/database/secrets/` | App-scoped secrets |
| **Kustomize patches** | `kustomization.yaml` patches | Dynamic secret generation |

**Recommendation:** Cluster-specific approach with `clusters/{env}/secrets/` structure.

---

## Core Concepts

### What SOPS Encrypts
```yaml
# ✅ Good - Only data encrypted
apiVersion: v1
kind: Secret
metadata:
  name: database
data:
  password: ENC[AES256_GCM,...]  # Encrypted

# ❌ Bad - Metadata encrypted (Kubernetes won't recognize)
apiVersion: ENC[AES256_GCM,...]  # ❌ Don't do this!
kind: ENC[AES256_GCM,...]
```

### SOPS File Format
Encrypted secrets use SOPS metadata at end:
```yaml
data:
  password: ENC[AES256_GCM,data:...,iv:...,tag:...,type:str]
  username: ENC[AES256_GCM,...]
sops:
  age:
    - recipient: age1...
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        AgEEAg...
        -----END AGE ENCRYPTED FILE-----
  lastmodified: "2024-01-15T10:30:00Z"
  version: 3.7.3
```

### Age Key Format
```
# age.agekey file contains both keys
# -----BEGIN AGE ENCRYPTED FILE-----
# ... (for encrypted keys, optional)
# -----END AGE ENCRYPTED FILE-----
# age-secret-key-1...  ← Private key (NEVER commit)
# public key: age1...  ← Public key (share with .sops.yaml)
```

---

## Team Workflows

### Scenario 1: Single Developer
```bash
# 1. Generate personal age key
age-keygen -o ~/.sops/key.txt

# 2. Create .sops.yaml with public key
cat > .sops.yaml << EOF
creation_rules:
  - path_regex: ^secrets/.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: age1...  # Your public key
EOF

# 3. Add to .gitignore
echo 'age-*.agekey' >> .gitignore

# 4. Create and encrypt secrets
sops secrets/database.yaml  # Opens editor
# (SOPS encrypts on save)

# 5. Commit encrypted file
git add secrets/database.yaml .sops.yaml .gitignore
git commit -m "Add encrypted database secret"
```

### Scenario 2: Team with Multiple Developers
```bash
# 1. Each developer generates own age key
age-keygen -o ~/.sops/key.txt

# 2. Team lead collects all public keys
# Alice: age1alice...
# Bob:   age1bob...
# Carol: age1carol...

# 3. Create team .sops.yaml
cat > .sops.yaml << EOF
creation_rules:
  - path_regex: ^secrets/.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: |
      age1alice...,
      age1bob...,
      age1carol...
EOF

# 4. Re-encrypt secrets with multiple keys
sops updatekeys secrets/database.yaml
# (prompts to add/remove keys)

# 5. Any team member can decrypt with their own key
sops secrets/database.yaml  # Uses ~/.sops/key.txt automatically

# 6. New team member joins
# - Generates own age key
# - Updates .sops.yaml with their public key
# - Re-encrypts all secrets
# - Now can decrypt secrets with their key
```

### Scenario 3: Multi-Cluster Production Setup
```
Cluster Structure:
  dev/           (uses age1dev...)
  staging/       (uses age1staging...)
  prod/          (uses age1prod...)

Key Distribution:
  Dev team → age1dev.agekey (in dev-system namespace)
  Staging team → age1staging.agekey (in staging-system namespace)
  Prod team (restricted) → age1prod.agekey (in prod-system namespace, encrypted Vault)

Access Control:
  Dev team: Can decrypt dev secrets, cannot decrypt staging/prod
  Staging team: Can decrypt staging, cannot decrypt prod
  Prod team: Can decrypt prod secrets only

Rotation Schedule:
  Development: Quarterly
  Staging: Biannually
  Production: Annually
```

---

## Common Issues & Solutions

### Issue 1: "sops: not found" error
**Solution:** Update Flux to version 2.0+ (includes SOPS binary)
```bash
flux bootstrap github ...  # Uses v2.x.x which includes sops
```

### Issue 2: Git shows files as "changed" after decryption
**Solution:** Expected behavior due to non-deterministic encryption. Use:
```bash
# View plaintext differences
sops -d old.yaml > /tmp/old.txt
sops -d new.yaml > /tmp/new.txt
diff /tmp/old.txt /tmp/new.txt
```

### Issue 3: Accidentally committed unencrypted secret
**Solution:** Rotate keys immediately and recreate secrets
```bash
# Rotate all keys
age-keygen -o age-new.agekey
# Update .sops.yaml and re-encrypt all files
# Force-push Git history (coordinate with team)
```

### Issue 4: Cannot decrypt with new key after rotation
**Cause:** Public key mismatch between .sops.yaml and cluster Secret
**Solution:**
```bash
# Verify keys match
grep "age:" .sops.yaml
kubectl get secret sops-age -n flux-system -o jsonpath='{.data.age\.agekey}' | \
  base64 -d | grep "public key:"
# If different, re-create cluster Secret with correct key
```

### Issue 5: Decryption fails in Flux reconciliation
**Debug steps:**
```bash
# Check secret exists
kubectl get secret sops-age -n flux-system

# Check Kustomization config
kubectl describe kustomization secrets -n flux-system

# View Flux logs
flux logs -f -k Kustomization

# Manually test sops on pod
kubectl exec -it -n flux-system deployment/kustomize-controller -- \
  sops -d /path/to/secret.yaml
```

---

## Security Best Practices

### 1. Key Storage
- ✅ **Do:** Store age.agekey in password manager (1Password, Bitwarden, LastPass)
- ✅ **Do:** Keep offline backup on encrypted USB or hardware key
- ✅ **Do:** Restrict file permissions: `chmod 600 age.agekey`
- ❌ **Don't:** Commit to Git
- ❌ **Don't:** Email or Slack
- ❌ **Don't:** Store in unencrypted backups

### 2. Kubernetes Secret Security
- ✅ **Do:** Use etcd encryption-at-rest in Kubernetes
- ✅ **Do:** Restrict RBAC access to sops-age Secret
- ✅ **Do:** Use separate Secret per cluster/environment
- ✅ **Do:** Rotate keys annually
- ❌ **Don't:** Export Secret to plaintext files
- ❌ **Don't:** Share Secret between clusters

### 3. Developer Workflow
- ✅ **Do:** Use `sops edit` for modifications (handles encryption)
- ✅ **Do:** Verify files encrypted before committing (`grep "ENC\[" file.yaml`)
- ✅ **Do:** Use `.gitignore` for local keys
- ✅ **Do:** Set up pre-commit hooks to catch unencrypted files
- ❌ **Don't:** `kubectl apply` encrypted secrets
- ❌ **Don't:** Mix plaintext and encrypted fields in same file

### 4. Audit & Monitoring
- ✅ **Do:** Enable Kubernetes audit logging for Secret access
- ✅ **Do:** Log SOPS decryption operations in Flux
- ✅ **Do:** Review Git history for secret changes
- ✅ **Do:** Set up alerts for failed decryptions
- ❌ **Don't:** Log plaintext secret values
- ❌ **Don't:** Ignore rotation audit trail

---

## Maintenance Tasks

### Monthly
- [ ] Review Git history for secret changes: `git log --oneline -- 'clusters/*/secrets/'`
- [ ] Verify SOPS reconciliation status: `flux logs -k Kustomization`

### Quarterly
- [ ] Test disaster recovery (decrypt without original machine)
- [ ] Check key permissions: `ls -la age*.agekey`
- [ ] Verify backup key accessibility

### Annually
- [ ] Rotate all encryption keys (or per environment)
- [ ] Review and update access controls
- [ ] Audit team members with key access
- [ ] Update documentation with lessons learned

### As Needed
- [ ] When team member leaves: Rotate keys for their access
- [ ] After security incident: Rotate all keys
- [ ] Adding new cluster: Generate new environment key
- [ ] System compromise: Full key rotation and re-encryption

---

## Links to Resources

### Official Documentation
- [Flux SOPS Guide](https://fluxcd.io/flux/guides/mozilla-sops/)
- [Flux Secrets Management](https://fluxcd.io/flux/security/secrets-management/)
- [Mozilla SOPS GitHub](https://github.com/getsops/sops)
- [Age Encryption Tool](https://github.com/FiloSottile/age)

### Community Guides
- [Encrypted GitOps with Flux and age](https://major.io/p/encrypted-gitops-secrets-with-flux-and-age/)
- [SOPS with Age and Git like a Pro](https://devops.datenkollektiv.de/using-sops-with-age-and-git-like-a-pro.html)
- [Flux Secret Management](https://budimanjojo.com/2021/10/23/flux-secret-management-with-sops-age/)
- [A Comprehensive Guide to SOPS](https://blog.gitguardian.com/a-comprehensive-guide-to-sops/)

### Tools
- [ssh-to-age](https://github.com/Mic92/ssh-to-age) - Convert SSH keys to age
- [git-sops](https://github.com/cycneuramus/git-sops) - Git integration for SOPS
- [SOPS Nix](https://github.com/Mic92/sops-nix) - NixOS SOPS integration

---

## Document Files in This Guide

1. **SOPS_FLUX_GUIDE.md** (this document)
   - Comprehensive 5000+ line guide covering all aspects
   - Best practices, architecture, troubleshooting
   - Real-world examples and configuration details

2. **SOPS_CONFIGURATION_TEMPLATES.yaml**
   - Ready-to-use YAML templates
   - `.sops.yaml` examples for different scenarios
   - Kubernetes manifests and Flux configurations
   - Directory structure examples

3. **SOPS_QUICK_START.sh**
   - Automated setup script
   - Interactive initialization
   - Key rotation automation
   - Verification commands

4. **SOPS_SUMMARY.md** (this file)
   - Quick reference guide
   - Decision matrices
   - Team workflow scenarios
   - Common issues and solutions

---

## Getting Started

### Absolute First Steps
1. Install tools: `brew install sops age`
2. Generate key: `age-keygen -o age.agekey`
3. Extract public key: `grep "public key:" age.agekey`
4. Create `.sops.yaml`: See templates in SOPS_CONFIGURATION_TEMPLATES.yaml
5. Add to `.gitignore`: `echo 'age.agekey' >> .gitignore`
6. Test encryption: `sops secrets/test.yaml`

### For Existing Clusters
Run the quick-start script:
```bash
chmod +x SOPS_QUICK_START.sh
./SOPS_QUICK_START.sh setup
```

### For Teams
1. Designate team lead
2. Generate team `.sops.yaml` with all members' public keys
3. Re-encrypt all secrets with team keys
4. Distribute via password manager or secure channel
5. Add onboarding steps to team documentation

---

**Last Updated:** January 15, 2025
**Flux Version:** v2.0+
**SOPS Version:** v3.7+
**Status:** Production Ready
