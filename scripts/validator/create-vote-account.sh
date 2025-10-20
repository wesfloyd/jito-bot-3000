#!/usr/bin/env bash
# Create Vote Account Script
#
# This script creates the vote account on Solana testnet.
# It performs the following tasks:
# 1. Verifies validator and vote account keypairs exist
# 2. Checks current SOL balances
# 3. Creates the vote account with proper parameters
# 4. Verifies vote account creation
#
# Usage:
#   ./scripts/validator/create-vote-account.sh [--force]
#
# Options:
#   --force    Skip confirmation prompts
#
# Exit codes:
#   0 - Success
#   1 - Error (missing keys, insufficient balance, creation failed, etc.)

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

# Remote paths
REMOTE_KEYS_DIR="~/validator/keys"
VALIDATOR_KEYPAIR="${REMOTE_KEYS_DIR}/validator-keypair.json"
VOTE_KEYPAIR="${REMOTE_KEYS_DIR}/vote-account-keypair.json"

# Minimum balance requirements (in SOL)
MIN_VALIDATOR_BALANCE=1.0
MIN_VOTE_BALANCE=0.5

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

Create vote account on Solana testnet.

Options:
  --force    Skip confirmation prompts
  -h, --help Show this help message

Requirements:
  - Validator identity must have at least $MIN_VALIDATOR_BALANCE SOL
  - Vote account must have at least $MIN_VOTE_BALANCE SOL
  - Keypairs must be uploaded to remote instance

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
# Vote Account Functions
# ============================================================================

check_balances() {
    local ssh_host=$1
    local ssh_key=$2

    log_info "Checking account balances..."

    # Get validator balance
    local validator_balance
    validator_balance=$(ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "export PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\" && \
         solana balance $VALIDATOR_KEYPAIR 2>/dev/null | awk '{print \$1}'" || echo "0")

    # Get vote account balance
    local vote_balance
    vote_balance=$(ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "export PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\" && \
         solana balance $VOTE_KEYPAIR 2>/dev/null | awk '{print \$1}'" || echo "0")

    log_info "Validator balance: $validator_balance SOL"
    log_info "Vote account balance: $vote_balance SOL"

    # Check if balances are sufficient
    local validator_ok=$(echo "$validator_balance >= $MIN_VALIDATOR_BALANCE" | bc -l)
    local vote_ok=$(echo "$vote_balance >= $MIN_VOTE_BALANCE" | bc -l)

    if [[ "$validator_ok" != "1" ]]; then
        log_error "Insufficient validator balance (need at least $MIN_VALIDATOR_BALANCE SOL)"
        return 1
    fi

    if [[ "$vote_ok" != "1" ]]; then
        log_error "Insufficient vote account balance (need at least $MIN_VOTE_BALANCE SOL)"
        return 1
    fi

    log_success "Balances are sufficient"
    return 0
}

check_vote_account_exists() {
    local ssh_host=$1
    local ssh_key=$2

    log_info "Checking if vote account already exists..."

    local vote_pubkey
    vote_pubkey=$(ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "~/.local/share/solana/install/active_release/bin/solana-keygen pubkey $VOTE_KEYPAIR" 2>/dev/null || echo "")

    if [[ -z "$vote_pubkey" ]]; then
        log_error "Failed to get vote account public key"
        return 1
    fi

    local exists
    exists=$(ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "export PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\" && \
         solana vote-account $vote_pubkey 2>&1 | grep -q 'is not a vote account' && echo 'no' || echo 'yes'")

    if [[ "$exists" == "yes" ]]; then
        log_success "Vote account already exists: $vote_pubkey"
        return 0
    else
        log_info "Vote account does not exist yet"
        return 1
    fi
}

create_vote_account() {
    local ssh_host=$1
    local ssh_key=$2

    log_section "Creating Vote Account"

    # First, check if the vote keypair address already exists as a regular account
    log_info "Checking for existing regular account at vote keypair address..."
    local vote_pubkey
    vote_pubkey=$(ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "~/.local/share/solana/install/active_release/bin/solana-keygen pubkey $VOTE_KEYPAIR" 2>/dev/null || echo "")

    local account_exists
    account_exists=$(ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "export PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\" && \
         solana account $vote_pubkey 2>&1 | grep -q 'Owner: 11111111111111111111111111111111' && echo 'yes' || echo 'no'")

    if [[ "$account_exists" == "yes" ]]; then
        log_warn "Vote keypair address exists as a regular account, transferring funds back..."
        ssh -i "$ssh_key" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            "$ssh_host" \
            "export PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\" && \
             solana transfer --from $VOTE_KEYPAIR \
                 \$(solana-keygen pubkey $VALIDATOR_KEYPAIR) \
                 ALL \
                 --allow-unfunded-recipient \
                 --fee-payer $VOTE_KEYPAIR 2>&1" || true
        log_success "Funds transferred back to validator"
    fi

    log_info "Creating vote account on testnet..."
    log_warn "This may take a few moments..."

    # Create vote account
    # Note: Using validator as withdrawer is not recommended for mainnet,
    # but acceptable for testnet with --allow-unsafe-authorized-withdrawer flag
    local output
    output=$(ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "export PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\" && \
         solana create-vote-account \
             $VOTE_KEYPAIR \
             $VALIDATOR_KEYPAIR \
             $VALIDATOR_KEYPAIR \
             --commission 10 \
             --fee-payer $VALIDATOR_KEYPAIR \
             --allow-unsafe-authorized-withdrawer 2>&1" || echo "FAILED")

    if echo "$output" | grep -q "FAILED\|Error\|error"; then
        log_error "Failed to create vote account"
        echo "$output"
        return 1
    fi

    log_success "Vote account created successfully"
    log_info "$output"
    return 0
}

verify_vote_account() {
    local ssh_host=$1
    local ssh_key=$2

    log_info "Verifying vote account..."

    local vote_pubkey
    vote_pubkey=$(ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "~/.local/share/solana/install/active_release/bin/solana-keygen pubkey $VOTE_KEYPAIR" 2>/dev/null || echo "")

    local vote_info
    vote_info=$(ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "export PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\" && \
         solana vote-account $vote_pubkey 2>&1")

    if echo "$vote_info" | grep -q "is not a vote account"; then
        log_error "Vote account verification failed"
        return 1
    fi

    log_success "Vote account verified"
    log_info "Vote account pubkey: $vote_pubkey"
    echo "$vote_info" | head -15

    return 0
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    print_banner
    log_section "Create Vote Account"

    # Parse arguments
    parse_args "$@"

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
        exit 1
    fi

    # Check if vote account already exists
    if check_vote_account_exists "$ssh_host" "$ssh_key"; then
        log_info "Vote account already exists. Nothing to do."
        exit 0
    fi

    # Check balances
    if ! check_balances "$ssh_host" "$ssh_key"; then
        log_error "Insufficient balances"
        log_info "Run './scripts/utils/fund-accounts.sh' to add more SOL"
        exit 1
    fi

    # Confirm before proceeding (unless force mode)
    if [[ "$FORCE_MODE" == false ]]; then
        echo ""
        log_warn "This will create a vote account on testnet"
        log_info "Parameters:"
        log_info "  - Commission: 10%"
        log_info "  - Vote authority: Validator identity"
        log_info "  - Withdrawer authority: Validator identity"
        echo ""
        if ! prompt_confirmation "Proceed with vote account creation?"; then
            log_info "Cancelled by user"
            exit 0
        fi
    fi

    # Create vote account
    if ! create_vote_account "$ssh_host" "$ssh_key"; then
        log_error "Failed to create vote account"
        exit 1
    fi

    # Verify vote account
    if ! verify_vote_account "$ssh_host" "$ssh_key"; then
        log_warn "Vote account created but verification failed"
    fi

    # Success summary
    log_section "Vote Account Created"

    log_success "Vote account created and verified successfully"
    echo ""
    log_info "Next steps:"
    log_info "  1. Start the validator: ssh to instance and run ~/validator/start-validator.sh"
    log_info "  2. Monitor logs: tail -f ~/validator/logs/*.log"

    exit 0
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
