#!/bin/bash

################################################################################
# SOPS + Flux Quick Start Setup Script
#
# This script automates the initial setup of SOPS encryption with Flux GitOps
#
# Usage: ./SOPS_QUICK_START.sh [setup|encrypt-all|decrypt-all|rotate-keys]
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${FLUX_NAMESPACE:-flux-system}"
SECRET_NAME="sops-age"
CLUSTERS="${CLUSTERS:-dev staging prod}"
REPO_ROOT="${REPO_ROOT:-.}"

################################################################################
# Utility Functions
################################################################################

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

check_command() {
  if ! command -v "$1" &> /dev/null; then
    log_error "$1 is not installed. Please install it first."
    exit 1
  fi
}

check_prerequisites() {
  log_info "Checking prerequisites..."
  check_command "sops"
  check_command "age"
  check_command "kubectl"
  check_command "git"
  log_success "All prerequisites met"
}

################################################################################
# 1. SETUP PHASE - Generate keys and create Kubernetes Secret
################################################################################

setup_sops() {
  log_info "Starting SOPS setup..."

  # Check if we're in a git repository
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log_error "Not in a git repository. Please run this from your Flux repository root."
    exit 1
  fi

  # Generate age key
  log_info "Generating age keypair..."
  AGE_KEYFILE="age.agekey"

  if [[ -f "$AGE_KEYFILE" ]]; then
    log_warn "$AGE_KEYFILE already exists. Using existing key."
    PUB_KEY=$(grep "public key:" "$AGE_KEYFILE" | cut -d' ' -f3)
  else
    age-keygen -o "$AGE_KEYFILE"
    PUB_KEY=$(grep "public key:" "$AGE_KEYFILE" | cut -d' ' -f3)
    log_success "Generated age keypair"
    echo -e "${YELLOW}Public key: $PUB_KEY${NC}"
  fi

  # Create .sops.yaml
  log_info "Creating .sops.yaml..."
  cat > "$REPO_ROOT/.sops.yaml" << EOF
creation_rules:
  - path_regex: ^clusters/.*secrets/.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: $PUB_KEY
EOF

  log_success "Created .sops.yaml"

  # Update .gitignore
  log_info "Updating .gitignore..."

  # Create .gitignore if doesn't exist
  if [[ ! -f "$REPO_ROOT/.gitignore" ]]; then
    touch "$REPO_ROOT/.gitignore"
  fi

  # Add SOPS files to .gitignore if not already there
  if ! grep -q "age.agekey" "$REPO_ROOT/.gitignore"; then
    cat >> "$REPO_ROOT/.gitignore" << 'EOF'

# SOPS encryption keys
age.agekey
sops-key.txt
.sops/
age-*.agekey
EOF
    log_success "Updated .gitignore"
  else
    log_warn ".gitignore already contains SOPS entries"
  fi

  # Verify age.agekey won't be committed
  if git check-ignore "age.agekey" &> /dev/null; then
    log_success "age.agekey is properly ignored by Git"
  else
    log_error "age.agekey will be committed! Check .gitignore"
    exit 1
  fi

  # Create Kubernetes Secret YAML
  log_info "Creating Kubernetes Secret YAML..."
  kubectl create secret generic "$SECRET_NAME" \
    --namespace="$NAMESPACE" \
    --from-file=age.agekey="$AGE_KEYFILE" \
    --dry-run=client -o yaml > sops-age-secret.yaml

  log_success "Created sops-age-secret.yaml"

  # Instructions
  echo ""
  echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║${NC} SOPS Setup Complete! Next steps:${NC}"
  echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo "1. Apply the Kubernetes Secret to your cluster:"
  echo -e "   ${BLUE}kubectl apply -f sops-age-secret.yaml${NC}"
  echo ""
  echo "2. Commit .sops.yaml and .gitignore to Git:"
  echo -e "   ${BLUE}git add .sops.yaml .gitignore${NC}"
  echo -e "   ${BLUE}git commit -m 'Add SOPS encryption configuration'${NC}"
  echo ""
  echo "3. IMPORTANT: Do NOT commit sops-age-secret.yaml or age.agekey"
  echo ""
  echo "4. Create encrypted secrets:"
  echo -e "   ${BLUE}sops --encrypt --in-place clusters/dev/secrets/database.yaml${NC}"
  echo ""
  echo "5. Update your Kustomization resources with decryption provider:"
  echo -e "   ${BLUE}See SOPS_FLUX_GUIDE.md for Kustomization examples${NC}"
  echo ""
}

################################################################################
# 2. ENCRYPT ALL SECRETS IN DIRECTORY
################################################################################

encrypt_directory() {
  local dir="$1"

  if [[ ! -d "$dir" ]]; then
    log_error "Directory $dir does not exist"
    exit 1
  fi

  log_info "Encrypting secrets in $dir..."

  local count=0
  for file in $(find "$dir" -name "*.yaml" -o -name "*.yml" 2>/dev/null); do
    if ! grep -q "ENC\[" "$file" 2>/dev/null; then
      log_info "Encrypting $file..."
      sops --encrypt --in-place "$file"
      ((count++))
    fi
  done

  if [[ $count -eq 0 ]]; then
    log_warn "No unencrypted files found in $dir"
  else
    log_success "Encrypted $count files"
  fi
}

################################################################################
# 3. DECRYPT FILE FOR VIEWING
################################################################################

decrypt_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    log_error "File $file does not exist"
    exit 1
  fi

  log_info "Decrypting $file..."
  sops -d "$file"
}

################################################################################
# 4. EDIT ENCRYPTED SECRET
################################################################################

edit_secret() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    log_error "File $file does not exist"
    exit 1
  fi

  log_info "Opening $file in editor (SOPS will handle encryption)..."
  sops "$file"
  log_success "Secret updated and re-encrypted"
}

################################################################################
# 5. ROTATE ENCRYPTION KEYS
################################################################################

rotate_keys() {
  log_info "Rotating SOPS encryption keys..."

  # Generate new age key
  log_info "Generating new age keypair..."
  NEW_AGE_KEY="age-new.agekey"
  age-keygen -o "$NEW_AGE_KEY"
  NEW_PUB_KEY=$(grep "public key:" "$NEW_AGE_KEY" | cut -d' ' -f3)

  log_success "Generated new key: $NEW_PUB_KEY"

  # Update .sops.yaml
  log_info "Updating .sops.yaml with new public key..."
  cat > "$REPO_ROOT/.sops.yaml" << EOF
creation_rules:
  - path_regex: ^clusters/.*secrets/.*\.ya?ml$
    encrypted_regex: ^(data|stringData)$
    age: $NEW_PUB_KEY
EOF

  # Re-encrypt all secrets
  log_info "Re-encrypting all secrets..."
  for cluster in $CLUSTERS; do
    encrypt_directory "$REPO_ROOT/clusters/$cluster/secrets"
  done

  # Update Kubernetes Secret
  log_info "Creating new Kubernetes Secret YAML..."
  kubectl create secret generic "$SECRET_NAME" \
    --namespace="$NAMESPACE" \
    --from-file=age.agekey="$NEW_AGE_KEY" \
    --dry-run=client -o yaml > sops-age-secret-new.yaml

  log_success "Key rotation complete!"

  echo ""
  echo -e "${YELLOW}Next steps:${NC}"
  echo "1. Review and commit changes:"
  echo -e "   ${BLUE}git add .sops.yaml clusters/*/secrets/${NC}"
  echo -e "   ${BLUE}git commit -m 'Rotate SOPS encryption keys'${NC}"
  echo ""
  echo "2. Apply new secret to cluster:"
  echo -e "   ${BLUE}kubectl apply -f sops-age-secret-new.yaml${NC}"
  echo ""
  echo "3. Backup new key:"
  echo -e "   ${BLUE}cp $NEW_AGE_KEY ~/Backups/$NEW_AGE_KEY${NC}"
  echo ""
}

################################################################################
# 6. VERIFY SETUP
################################################################################

verify_setup() {
  log_info "Verifying SOPS setup..."

  local errors=0

  # Check .sops.yaml exists
  if [[ ! -f "$REPO_ROOT/.sops.yaml" ]]; then
    log_error ".sops.yaml not found"
    ((errors++))
  else
    log_success ".sops.yaml exists"
  fi

  # Check age key exists
  if [[ ! -f "age.agekey" ]]; then
    log_warn "age.agekey not found (may be stored elsewhere)"
  else
    log_success "age.agekey exists"
  fi

  # Check Kubernetes secret
  if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
    log_success "Kubernetes Secret sops-age exists in $NAMESPACE"
  else
    log_warn "Kubernetes Secret sops-age not found in $NAMESPACE"
  fi

  # Check .gitignore
  if [[ -f "$REPO_ROOT/.gitignore" ]] && grep -q "age.agekey" "$REPO_ROOT/.gitignore"; then
    log_success "age.agekey is in .gitignore"
  else
    log_warn "age.agekey not found in .gitignore"
    ((errors++))
  fi

  # Try encrypting a test file
  log_info "Testing encryption..."
  cat > /tmp/test-sops.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: test
data:
  key: "test-value"
EOF

  if sops --encrypt /tmp/test-sops.yaml > /tmp/test-sops-enc.yaml 2>/dev/null; then
    log_success "Encryption test passed"
    rm -f /tmp/test-sops.yaml /tmp/test-sops-enc.yaml
  else
    log_error "Encryption test failed"
    ((errors++))
  fi

  if [[ $errors -eq 0 ]]; then
    log_success "SOPS setup verification passed!"
  else
    log_error "SOPS setup verification failed with $errors errors"
    exit 1
  fi
}

################################################################################
# 7. HELP MESSAGE
################################################################################

show_help() {
  cat << 'EOF'
SOPS + Flux Quick Start Setup Script

Usage: ./SOPS_QUICK_START.sh [COMMAND] [OPTIONS]

Commands:
  setup                 Initialize SOPS in current Git repository
  encrypt-all <dir>     Encrypt all unencrypted YAML files in directory
  decrypt-file <file>   Decrypt and display a secret file
  edit-secret <file>    Edit a secret (SOPS handles encryption)
  rotate-keys           Generate new encryption keys and re-encrypt secrets
  verify                Verify SOPS setup is correct
  help                  Show this help message

Environment Variables:
  FLUX_NAMESPACE    Kubernetes namespace (default: flux-system)
  REPO_ROOT         Repository root directory (default: .)
  CLUSTERS          Cluster names for key rotation (default: dev staging prod)

Examples:
  # Initial setup
  ./SOPS_QUICK_START.sh setup

  # Encrypt all dev secrets
  ./SOPS_QUICK_START.sh encrypt-all clusters/dev/secrets

  # Edit a secret
  ./SOPS_QUICK_START.sh edit-secret clusters/dev/secrets/database.yaml

  # View encrypted secret
  ./SOPS_QUICK_START.sh decrypt-file clusters/dev/secrets/database.yaml

  # Rotate keys (annual maintenance)
  ./SOPS_QUICK_START.sh rotate-keys

  # Verify everything is working
  ./SOPS_QUICK_START.sh verify

For more information, see SOPS_FLUX_GUIDE.md
EOF
}

################################################################################
# MAIN SCRIPT
################################################################################

main() {
  local command="${1:-help}"

  case "$command" in
    setup)
      check_prerequisites
      setup_sops
      ;;
    encrypt-all)
      check_prerequisites
      if [[ -z "$2" ]]; then
        log_error "Directory path required"
        echo "Usage: $0 encrypt-all <directory>"
        exit 1
      fi
      encrypt_directory "$2"
      ;;
    decrypt-file)
      check_prerequisites
      if [[ -z "$2" ]]; then
        log_error "File path required"
        echo "Usage: $0 decrypt-file <file>"
        exit 1
      fi
      decrypt_file "$2"
      ;;
    edit-secret)
      check_prerequisites
      if [[ -z "$2" ]]; then
        log_error "File path required"
        echo "Usage: $0 edit-secret <file>"
        exit 1
      fi
      edit_secret "$2"
      ;;
    rotate-keys)
      check_prerequisites
      rotate_keys
      ;;
    verify)
      check_prerequisites
      verify_setup
      ;;
    help|-h|--help)
      show_help
      ;;
    *)
      log_error "Unknown command: $command"
      show_help
      exit 1
      ;;
  esac
}

# Run main function with all arguments
main "$@"
