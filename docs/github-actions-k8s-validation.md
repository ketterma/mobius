# Kubernetes Manifest Validation GitHub Action

## Overview

This GitHub Action (`k8s-validate.yml`) provides comprehensive validation of Kubernetes manifests before they are merged to the main branch. It ensures that all k8s configurations are syntactically correct, conform to Kubernetes schemas, and can be successfully built by Kustomize and Flux.

## What It Validates

### 1. YAML Syntax Validation (yamllint)
- Checks all YAML files for syntax errors
- Ensures consistent indentation and formatting
- Validates YAML structure including SOPS-encrypted files

### 2. Kubernetes Schema Validation (kubeconform)
- Validates manifests against Kubernetes API schemas
- Supports Custom Resource Definitions (CRDs) from common operators
- Uses both default k8s schemas and community CRD catalog
- Skips SOPS-encrypted files (they're encrypted so can't be schema-validated)
- Skips Flux-generated files (`gotk-components.yaml`, `gotk-sync.yaml`)

### 3. Kustomize Build Validation
- Finds all `kustomization.yaml` files in the repository
- Attempts to build each kustomization
- Ensures that all resources are correctly referenced
- Validates that patches, transformers, and generators work correctly

### 4. Flux Resource Validation
- Validates Flux-specific resources (Kustomization, HelmRelease, etc.)
- Ensures Flux Kustomizations have required fields (`sourceRef`, `spec`, etc.)
- Validates that the flux-system can be built

### 5. Additional Checks
- Detects potential hardcoded passwords or secrets
- Warns about resources missing namespace declarations
- Checks for duplicate resource names within directories
- All additional checks are non-blocking (warnings only)

## When It Runs

The workflow triggers on:
- **Pull Requests** that modify:
  - `k8s/**/*.yaml` or `k8s/**/*.yml`
  - `bootstrap/**/*.yaml` or `bootstrap/**/*.yml`
  - The workflow file itself (`.github/workflows/k8s-validate.yml`)
- **Pushes to main branch** with the same path filters

## Making It a Required PR Check

To make this workflow a required check before merging PRs:

### Option 1: GitHub Branch Protection Rules (Recommended)

1. Go to your repository on GitHub
2. Navigate to **Settings** → **Branches**
3. Under "Branch protection rules", click **Add rule** or edit the existing rule for `main`
4. Configure the following settings:
   - Branch name pattern: `main`
   - ✅ **Require status checks to pass before merging**
   - ✅ **Require branches to be up to date before merging**
   - Search for and select: `validate` (this is the job name from the workflow)
5. Optionally enable:
   - ✅ **Require pull request reviews before merging**
   - ✅ **Dismiss stale pull request approvals when new commits are pushed**
6. Click **Save changes**

### Option 2: GitHub Rulesets (New GitHub Feature)

1. Go to your repository on GitHub
2. Navigate to **Settings** → **Rules** → **Rulesets**
3. Click **New ruleset** → **New branch ruleset**
4. Configure:
   - Ruleset Name: "Main branch protection"
   - Enforcement status: **Active**
   - Target: **Default branch** or specify `main`
   - Rules:
     - ✅ **Require status checks to pass**
     - Add required check: `validate`
     - ✅ **Require pull request before merging**
5. Click **Create**

## Testing Locally

You can test the validation steps locally before pushing:

```bash
# Install tools (one-time setup)
# kubeconform
KUBECONFORM_VERSION=0.6.4
wget https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz
tar xzf kubeconform-linux-amd64.tar.gz
sudo mv kubeconform /usr/local/bin/

# kustomize
KUSTOMIZE_VERSION=5.3.0
wget https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz
tar xzf kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz
sudo mv kustomize /usr/local/bin/

# flux
curl -s https://fluxcd.io/install.sh | sudo bash

# yamllint
sudo apt-get install yamllint  # Ubuntu/Debian
# or
brew install yamllint  # macOS

# Run validations
yamllint k8s/ bootstrap/

# Validate a specific file
kubeconform k8s/clusters/lab/apps/adguard/deployment.yaml

# Build a specific kustomization
kustomize build k8s/clusters/lab/apps/adguard

# Validate all kustomizations
find k8s -name "kustomization.yaml" | while read k; do
  echo "Building: $(dirname $k)"
  kustomize build $(dirname $k) > /dev/null
done
```

## Workflow Details

### Tools Used

| Tool | Version | Purpose |
|------|---------|---------|
| **kubeconform** | 0.6.4 | Kubernetes schema validation |
| **kustomize** | 5.3.0 | Kustomize build validation |
| **flux** | latest | Flux resource validation |
| **yamllint** | latest | YAML syntax validation |

### Exit Codes

- **0**: All validations passed ✅
- **1**: One or more validations failed ❌
- The workflow will fail the PR check if any validation step fails

### Performance

- Typical runtime: **2-5 minutes** depending on repository size
- Validation is run in parallel where possible
- Only validates changed files in PRs (via path filters)

## Troubleshooting

### Validation fails for a SOPS-encrypted file

**Solution**: SOPS files are automatically excluded from schema validation. They are only validated for YAML syntax.

### Kustomize build fails with "file not found"

**Solution**: Ensure that all resources referenced in `kustomization.yaml` exist and paths are correct. Common issues:
- Incorrect relative paths
- Missing `namespace.yaml` or other base resources
- Typos in resource names

### False positives for CRDs

**Solution**: The workflow uses the CRDs-catalog from datree.io. If a CRD is not in the catalog, you can:
1. Add it to the catalog (open a PR to datree.io)
2. Temporarily skip validation for that file
3. Add a custom schema location to kubeconform

### Workflow times out or takes too long

**Solution**: Consider:
- Breaking up large kustomizations into smaller ones
- Using `kustomize build --load-restrictor=LoadRestrictionsNone` for complex builds
- Increasing the workflow timeout (default is unlimited for jobs)

## Future Enhancements

Potential improvements to consider:

1. **OPA Policy Validation**: Add Open Policy Agent for custom policy checks
2. **Security Scanning**: Integrate tools like `kube-score` or `polaris` for security best practices
3. **Cost Estimation**: Add kubecost or similar for resource cost estimation
4. **Diff Visualization**: Show what changed between current and new manifests
5. **Auto-fix**: Automatically fix common issues (formatting, missing fields, etc.)
6. **Notification**: Post validation results as PR comments
7. **Caching**: Cache tool installations for faster runs

## Related Documentation

- [Network Topology](lab-network.md) - Network infrastructure and IP allocation
- [Home Assistant VM](lab-vm-haos.md) - VM configuration and management
- [CLAUDE.md](../CLAUDE.md) - Repository overview and common tasks
