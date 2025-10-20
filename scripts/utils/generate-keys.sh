#!/usr/bin/env bash
#
# generate-keys.sh - Generate Solana validator keypairs locally
#
# This script generates the three keypairs needed for a Jito validator:
# 1. Validator identity keypair
# 2. Vote account keypair
# 3. Authorized withdrawer keypair
#
# Usage: ./scripts/utils/generate-keys.sh [--force]
#   --force: Overwrite existing keypairs without prompting (non-interactive mode)

set -euo pipefail

# Parse arguments
FORCE_MODE=false
for arg in "$@"; do
    case $arg in
        --force|-f)
            FORCE_MODE=true
            shift
            ;;
    esac
done

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh"

# Configuration
KEYS_DIR="${PROJECT_ROOT}/keys"
VALIDATOR_KEYPAIR="${KEYS_DIR}/validator-keypair.json"
VOTE_ACCOUNT_KEYPAIR="${KEYS_DIR}/vote-account-keypair.json"
WITHDRAWER_KEYPAIR="${KEYS_DIR}/authorized-withdrawer-keypair.json"

# =============================================================================
# Main Functions
# =============================================================================

check_solana_cli() {
    log_info "Checking for Solana CLI installation..."

    if ! command -v solana &> /dev/null; then
        log_error "Solana CLI not found. Please install it first:"
        log_info "  sh -c \"\$(curl -sSfL https://release.solana.com/stable/install)\""
        exit 1
    fi

    local solana_version
    solana_version=$(solana --version | head -n1)
    log_success "Found Solana CLI: ${solana_version}"
}

create_keys_directory() {
    log_info "Creating keys directory..."

    if [[ ! -d "${KEYS_DIR}" ]]; then
        mkdir -p "${KEYS_DIR}"
        chmod 700 "${KEYS_DIR}"
        log_success "Created keys directory: ${KEYS_DIR}"
    else
        log_info "Keys directory already exists: ${KEYS_DIR}"
    fi
}

check_existing_keypair() {
    local keypair_path=$1
    local keypair_name=$2

    if [[ -f "${keypair_path}" ]]; then
        # Show the public key
        local pubkey
        pubkey=$(solana-keygen pubkey "${keypair_path}")

        if [[ "${FORCE_MODE}" == "true" ]]; then
            log_warn "Keypair already exists: ${keypair_path}"
            log_info "  Public key: ${pubkey}"
            log_warn "Force mode enabled - overwriting existing keypair..."
        else
            log_warn "Keypair already exists: ${keypair_path}"
            log_info "  Public key: ${pubkey}"
            log_info "Skipping ${keypair_name} generation (use --force to overwrite)"
            return 1
        fi
    fi
    return 0
}

generate_validator_keypair() {
    log_section "Generating Validator Identity Keypair"

    if ! check_existing_keypair "${VALIDATOR_KEYPAIR}" "validator identity"; then
        return 0
    fi

    log_info "Generating validator identity keypair..."
    solana-keygen new --no-bip39-passphrase --outfile "${VALIDATOR_KEYPAIR}" --silent

    local pubkey
    pubkey=$(solana-keygen pubkey "${VALIDATOR_KEYPAIR}")

    log_success "Validator identity keypair generated"
    log_info "  Location: ${VALIDATOR_KEYPAIR}"
    log_info "  Public key: ${pubkey}"

    # Set restrictive permissions
    chmod 600 "${VALIDATOR_KEYPAIR}"
}

generate_vote_account_keypair() {
    log_section "Generating Vote Account Keypair"

    if ! check_existing_keypair "${VOTE_ACCOUNT_KEYPAIR}" "vote account"; then
        return 0
    fi

    log_info "Generating vote account keypair..."
    solana-keygen new --no-bip39-passphrase --outfile "${VOTE_ACCOUNT_KEYPAIR}" --silent

    local pubkey
    pubkey=$(solana-keygen pubkey "${VOTE_ACCOUNT_KEYPAIR}")

    log_success "Vote account keypair generated"
    log_info "  Location: ${VOTE_ACCOUNT_KEYPAIR}"
    log_info "  Public key: ${pubkey}"

    # Set restrictive permissions
    chmod 600 "${VOTE_ACCOUNT_KEYPAIR}"
}

generate_withdrawer_keypair() {
    log_section "Generating Authorized Withdrawer Keypair"

    if ! check_existing_keypair "${WITHDRAWER_KEYPAIR}" "authorized withdrawer"; then
        return 0
    fi

    log_info "Generating authorized withdrawer keypair..."
    solana-keygen new --no-bip39-passphrase --outfile "${WITHDRAWER_KEYPAIR}" --silent

    local pubkey
    pubkey=$(solana-keygen pubkey "${WITHDRAWER_KEYPAIR}")

    log_success "Authorized withdrawer keypair generated"
    log_info "  Location: ${WITHDRAWER_KEYPAIR}"
    log_info "  Public key: ${pubkey}"

    # Set restrictive permissions
    chmod 600 "${WITHDRAWER_KEYPAIR}"

    log_warn "SECURITY WARNING: The authorized withdrawer keypair should be stored offline!"
    log_warn "This keypair will NOT be deployed to the validator VM."
}

display_summary() {
    log_section "Key Generation Summary"

    echo ""
    echo "Generated keypairs:"
    echo ""

    if [[ -f "${VALIDATOR_KEYPAIR}" ]]; then
        local validator_pubkey
        validator_pubkey=$(solana-keygen pubkey "${VALIDATOR_KEYPAIR}")
        log_info "✓ Validator Identity"
        echo "    Public key: ${validator_pubkey}"
        echo "    File: ${VALIDATOR_KEYPAIR}"
        echo ""
    fi

    if [[ -f "${VOTE_ACCOUNT_KEYPAIR}" ]]; then
        local vote_pubkey
        vote_pubkey=$(solana-keygen pubkey "${VOTE_ACCOUNT_KEYPAIR}")
        log_info "✓ Vote Account"
        echo "    Public key: ${vote_pubkey}"
        echo "    File: ${VOTE_ACCOUNT_KEYPAIR}"
        echo ""
    fi

    if [[ -f "${WITHDRAWER_KEYPAIR}" ]]; then
        local withdrawer_pubkey
        withdrawer_pubkey=$(solana-keygen pubkey "${WITHDRAWER_KEYPAIR}")
        log_info "✓ Authorized Withdrawer"
        echo "    Public key: ${withdrawer_pubkey}"
        echo "    File: ${WITHDRAWER_KEYPAIR}"
        echo ""
    fi

    log_section "Next Steps"
    log_info "1. Fund the validator and vote accounts with testnet SOL"
    log_info "   Run: ./scripts/utils/fund-accounts.sh"
    log_info ""
    log_info "2. Keep the authorized withdrawer keypair OFFLINE and secure"
    log_info "3. Validator and vote account keypairs will be transferred to the VM during setup"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    log_section "Solana Validator Keypair Generation"

    if [[ "${FORCE_MODE}" == "true" ]]; then
        log_info "Running in force mode (non-interactive)"
    fi

    check_solana_cli
    create_keys_directory

    echo ""
    log_info "Generating three keypairs:"
    log_info "  1. Validator identity keypair (identifies your validator)"
    log_info "  2. Vote account keypair (for voting on the network)"
    log_info "  3. Authorized withdrawer keypair (controls vote account funds - KEEP OFFLINE)"
    echo ""

    generate_validator_keypair
    generate_vote_account_keypair
    generate_withdrawer_keypair

    display_summary

    log_success "Key generation completed successfully!"
}

# Run main function
main "$@"
