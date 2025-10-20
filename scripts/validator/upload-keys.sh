#!/usr/bin/env bash
# Validator Keypair Upload Script
#
# This script uploads the locally generated validator keypairs to the remote
# EC2 instance. It performs the following tasks:
# 1. Verifies local keypairs exist
# 2. Gets SSH connection info from Terraform
# 3. Creates remote keys directory
# 4. Uploads validator and vote account keypairs (NOT withdrawer)
# 5. Sets secure permissions on remote keypairs
#
# Usage:
#   ./scripts/validator/upload-keys.sh [--force]
#
# Options:
#   --force    Skip confirmation prompts
#
# Exit codes:
#   0 - Success
#   1 - Error (missing keys, SSH connection failed, etc.)
#
# SECURITY NOTE:
#   The authorized withdrawer keypair is NOT uploaded to the remote instance.
#   It should remain offline for security purposes.

set -euo pipefail

# ============================================================================
# Setup
# ============================================================================

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common utilities
# shellcheck source=scripts/utils/lib/common.sh
source "${PROJECT_ROOT}/scripts/utils/lib/common.sh"
# shellcheck source=scripts/utils/lib/terraform-helpers.sh
source "${PROJECT_ROOT}/scripts/utils/lib/terraform-helpers.sh"

# ============================================================================
# Configuration
# ============================================================================

FORCE_MODE=false
KEYS_DIR="${PROJECT_ROOT}/keys"

# Keypair files to upload
VALIDATOR_KEYPAIR="${KEYS_DIR}/validator-keypair.json"
VOTE_KEYPAIR="${KEYS_DIR}/vote-account-keypair.json"
# NOTE: withdrawer keypair is NOT uploaded for security

# Remote directory for keys
REMOTE_KEYS_DIR="~/validator/keys"

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_MODE=true
                shift
                ;;
            -h|--help)
                cat << EOF
Usage: $0 [OPTIONS]

Upload validator keypairs to the remote EC2 instance.

Options:
  --force    Skip confirmation prompts
  -h, --help Show this help message

Security Notes:
  - Only validator and vote account keypairs are uploaded
  - Authorized withdrawer keypair remains local (offline storage)
  - Remote keypairs are set to 600 permissions (owner read/write only)

Examples:
  # Interactive mode
  $0

  # Non-interactive mode
  $0 --force

EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                log_info "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_local_keypairs() {
    log_info "Validating local keypairs..."

    local missing_keys=false

    if [[ ! -f "$VALIDATOR_KEYPAIR" ]]; then
        log_error "Validator keypair not found: $VALIDATOR_KEYPAIR"
        missing_keys=true
    fi

    if [[ ! -f "$VOTE_KEYPAIR" ]]; then
        log_error "Vote account keypair not found: $VOTE_KEYPAIR"
        missing_keys=true
    fi

    if [[ "$missing_keys" == true ]]; then
        log_error "Missing required keypairs"
        log_info "Run './scripts/utils/generate-keys.sh' to generate keypairs"
        return 1
    fi

    log_success "Local keypairs validated"
    return 0
}

# ============================================================================
# SSH Helper Functions
# ============================================================================

get_ssh_connection_info() {
    local terraform_dir="${PROJECT_ROOT}/terraform"

    if [[ ! -f "$terraform_dir/terraform.tfstate" ]]; then
        log_error "Terraform state not found. Deploy infrastructure first."
        return 1
    fi

    cd "$terraform_dir"

    local ssh_host
    ssh_host=$(terraform output -raw ssh_host 2>/dev/null || echo "")

    local ssh_key
    ssh_key=$(terraform output -raw ssh_key_file 2>/dev/null || echo "")

    if [[ -z "$ssh_host" || -z "$ssh_key" ]]; then
        log_error "Could not get SSH connection info from Terraform"
        return 1
    fi

    # Make path absolute
    if [[ "$ssh_key" == ../* ]]; then
        ssh_key="${PROJECT_ROOT}/terraform/${ssh_key}"
    elif [[ "$ssh_key" != /* ]]; then
        ssh_key="${PROJECT_ROOT}/${ssh_key}"
    fi

    echo "$ssh_host|$ssh_key"
}

test_ssh_connection() {
    local ssh_host=$1
    local ssh_key=$2

    log_info "Testing SSH connection to $ssh_host..."

    if ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o LogLevel=ERROR \
        "$ssh_host" "echo 'SSH connection successful'" >/dev/null 2>&1; then

        log_success "SSH connection successful"
        return 0
    else
        log_error "SSH connection failed"
        return 1
    fi
}

# ============================================================================
# Upload Functions
# ============================================================================

upload_keypairs() {
    local ssh_host=$1
    local ssh_key=$2

    log_section "Uploading Keypairs"

    # Create remote keys directory
    log_info "Creating remote keys directory..."
    ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "mkdir -p $REMOTE_KEYS_DIR && chmod 700 $REMOTE_KEYS_DIR"

    # Upload validator keypair
    log_info "Uploading validator keypair..."
    scp -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$VALIDATOR_KEYPAIR" \
        "${ssh_host}:${REMOTE_KEYS_DIR}/validator-keypair.json"

    # Upload vote account keypair
    log_info "Uploading vote account keypair..."
    scp -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$VOTE_KEYPAIR" \
        "${ssh_host}:${REMOTE_KEYS_DIR}/vote-account-keypair.json"

    # Set secure permissions on remote keypairs
    log_info "Setting secure permissions on remote keypairs..."
    ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "chmod 600 ${REMOTE_KEYS_DIR}/*.json"

    log_success "Keypairs uploaded successfully"
}

verify_remote_keypairs() {
    local ssh_host=$1
    local ssh_key=$2

    log_info "Verifying remote keypairs..."

    # Get public keys from remote (use full path to solana-keygen)
    local validator_pubkey
    validator_pubkey=$(ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "~/.local/share/solana/install/active_release/bin/solana-keygen pubkey ${REMOTE_KEYS_DIR}/validator-keypair.json" 2>/dev/null || echo "")

    local vote_pubkey
    vote_pubkey=$(ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "~/.local/share/solana/install/active_release/bin/solana-keygen pubkey ${REMOTE_KEYS_DIR}/vote-account-keypair.json" 2>/dev/null || echo "")

    if [[ -z "$validator_pubkey" || -z "$vote_pubkey" ]]; then
        log_error "Failed to verify remote keypairs"
        return 1
    fi

    log_success "Remote keypairs verified"
    log_info "Validator pubkey: $validator_pubkey"
    log_info "Vote account pubkey: $vote_pubkey"

    return 0
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    print_banner
    log_section "Validator Keypair Upload"

    # Parse arguments
    parse_args "$@"

    # Validate local keypairs exist
    if ! validate_local_keypairs; then
        exit 1
    fi

    # Get SSH connection info from Terraform
    log_info "Getting connection information from Terraform..."

    local connection_info
    connection_info=$(get_ssh_connection_info)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to get SSH connection info"
        exit 1
    fi

    local ssh_host
    ssh_host=$(echo "$connection_info" | cut -d'|' -f1)

    local ssh_key
    ssh_key=$(echo "$connection_info" | cut -d'|' -f2)

    log_info "SSH Host: $ssh_host"

    # Test SSH connection
    if ! test_ssh_connection "$ssh_host" "$ssh_key"; then
        log_error "Cannot connect to remote instance"
        log_info "Make sure the instance is running"
        exit 1
    fi

    # Confirm before proceeding (unless force mode)
    if [[ "$FORCE_MODE" == false ]]; then
        echo ""
        log_warn "This will upload keypairs to the remote instance"
        log_info "Keypairs to upload:"
        log_info "  - Validator identity keypair"
        log_info "  - Vote account keypair"
        echo ""
        log_warn "Security note: Withdrawer keypair will NOT be uploaded (offline storage)"
        echo ""
        if ! prompt_confirmation "Proceed with upload?"; then
            log_info "Upload cancelled by user"
            exit 0
        fi
    fi

    # Upload keypairs
    if ! upload_keypairs "$ssh_host" "$ssh_key"; then
        log_error "Failed to upload keypairs"
        exit 1
    fi

    # Verify upload
    if ! verify_remote_keypairs "$ssh_host" "$ssh_key"; then
        log_error "Keypair verification failed"
        exit 1
    fi

    # Success summary
    log_section "Upload Complete"

    log_success "Validator keypairs uploaded successfully"
    echo ""
    log_info "Next steps:"
    log_info "  1. Configure validator startup script"
    log_info "  2. Start the validator"

    exit 0
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
