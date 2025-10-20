#!/usr/bin/env bash
# Fund validator and vote accounts with testnet SOL
#
# This script automates the process of funding Jito validator accounts on testnet.
# It will:
# 1. Verify Solana CLI is installed and configured for testnet
# 2. Load keypairs and extract public keys
# 3. Request SOL airdrops from the testnet faucet
# 4. Verify account balances meet minimum requirements
#
# Usage:
#   ./scripts/utils/fund-accounts.sh [--force] [--validator-amount AMOUNT] [--vote-amount AMOUNT]
#
# Options:
#   --force                Skip confirmation prompts (for automation)
#   --validator-amount N   Amount of SOL to fund validator account (default: 5)
#   --vote-amount N        Amount of SOL to fund vote account (default: 1)
#
# Exit codes:
#   0 - Success
#   1 - Error (dependencies missing, funding failed, etc.)

set -euo pipefail

# ============================================================================
# Setup
# ============================================================================

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common utilities and Solana helpers
# shellcheck source=scripts/utils/lib/common.sh
source "${PROJECT_ROOT}/scripts/utils/lib/common.sh"
# shellcheck source=scripts/utils/lib/solana-helpers.sh
source "${PROJECT_ROOT}/scripts/utils/lib/solana-helpers.sh"

# ============================================================================
# Configuration
# ============================================================================

# Default amounts (in SOL)
VALIDATOR_AMOUNT=5
VOTE_AMOUNT=1

# Force mode (non-interactive)
FORCE_MODE=false

# Keypair paths
VALIDATOR_KEYPAIR="${KEYS_DIR}/validator-keypair.json"
VOTE_KEYPAIR="${KEYS_DIR}/vote-account-keypair.json"

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
            --validator-amount)
                VALIDATOR_AMOUNT="$2"
                shift 2
                ;;
            --vote-amount)
                VOTE_AMOUNT="$2"
                shift 2
                ;;
            -h|--help)
                cat << EOF
Usage: $0 [OPTIONS]

Fund validator and vote accounts with testnet SOL.

Options:
  --force                Skip confirmation prompts (for automation)
  --validator-amount N   Amount of SOL to fund validator account (default: 5)
  --vote-amount N        Amount of SOL to fund vote account (default: 1)
  -h, --help            Show this help message

Examples:
  # Interactive mode with defaults
  $0

  # Non-interactive mode with custom amounts
  $0 --force --validator-amount 10 --vote-amount 2

  # Automation/CI mode
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

check_solana_cli_installed() {
    log_info "Checking Solana CLI installation..."

    if ! command -v solana >/dev/null 2>&1; then
        log_error "Solana CLI is not installed"
        log_info "Please install it first:"
        log_info "  sh -c \"\$(curl -sSfL https://release.anza.xyz/stable/install)\""
        return 1
    fi

    local version
    version=$(solana --version | awk '{print $2}')
    log_success "Solana CLI found: $version"

    return 0
}

check_testnet_configured() {
    log_info "Checking Solana CLI configuration..."

    local current_url
    current_url=$(solana config get | grep "RPC URL" | awk '{print $3}')

    if [[ "$current_url" != *"testnet"* ]]; then
        log_warn "Solana CLI is not configured for testnet"
        log_info "Current RPC URL: $current_url"

        if [[ "$FORCE_MODE" == false ]]; then
            if prompt_confirmation "Configure for testnet now?"; then
                configure_solana_cli testnet
            else
                log_error "Testnet configuration required"
                return 1
            fi
        else
            log_info "Configuring for testnet (force mode)..."
            configure_solana_cli testnet
        fi
    else
        log_success "Configured for testnet: $current_url"
    fi

    return 0
}

check_keypairs_exist() {
    log_info "Checking for required keypairs..."

    local missing=()

    if [[ ! -f "$VALIDATOR_KEYPAIR" ]]; then
        missing+=("validator-keypair.json")
    fi

    if [[ ! -f "$VOTE_KEYPAIR" ]]; then
        missing+=("vote-account-keypair.json")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing keypair files:"
        for keypair in "${missing[@]}"; do
            log_error "  - $keypair"
        done
        log_info ""
        log_info "Generate keypairs first:"
        log_info "  ./scripts/utils/generate-keys.sh"
        return 1
    fi

    log_success "All required keypairs found"
    return 0
}

verify_cluster_connectivity() {
    log_info "Verifying testnet connectivity..."

    if ! check_cluster_health testnet; then
        log_error "Cannot connect to Solana testnet"
        log_info "Please check your internet connection and try again"
        return 1
    fi

    log_success "Testnet is reachable"
    return 0
}

# ============================================================================
# Funding Functions
# ============================================================================

fund_validator_account() {
    local validator_pubkey=$1
    local amount=$2

    log_section "Funding Validator Account"

    log_info "Validator pubkey: ${BOLD}${GREEN}${validator_pubkey}${RESET}"
    log_info "Target amount: ${amount} SOL"

    # Check current balance
    local current_balance
    current_balance=$(get_balance "$validator_pubkey" || echo "0")
    log_info "Current balance: ${current_balance} SOL"

    # Check if already funded
    if (( $(echo "$current_balance >= $amount" | bc -l) )); then
        log_success "Validator account already has sufficient balance"
        return 0
    fi

    # Fund the account
    if ! fund_with_faucet "$validator_pubkey" "$amount"; then
        log_error "Failed to fund validator account"
        return 1
    fi

    # Verify final balance
    local final_balance
    final_balance=$(get_balance "$validator_pubkey")
    log_success "Validator account funded: ${final_balance} SOL"

    return 0
}

fund_vote_account() {
    local vote_pubkey=$1
    local amount=$2

    log_section "Funding Vote Account"

    log_info "Vote account pubkey: ${BOLD}${GREEN}${vote_pubkey}${RESET}"
    log_info "Target amount: ${amount} SOL"

    # Check current balance
    local current_balance
    current_balance=$(get_balance "$vote_pubkey" || echo "0")
    log_info "Current balance: ${current_balance} SOL"

    # Check if already funded
    if (( $(echo "$current_balance >= $amount" | bc -l) )); then
        log_success "Vote account already has sufficient balance"
        return 0
    fi

    # Fund the account
    if ! fund_with_faucet "$vote_pubkey" "$amount"; then
        log_error "Failed to fund vote account"
        return 1
    fi

    # Verify final balance
    local final_balance
    final_balance=$(get_balance "$vote_pubkey")
    log_success "Vote account funded: ${final_balance} SOL"

    return 0
}

# ============================================================================
# Summary Functions
# ============================================================================

print_funding_summary() {
    local validator_pubkey=$1
    local vote_pubkey=$2

    log_section "Funding Summary"

    log_info "Validator Account:"
    log_info "  Pubkey:  ${BOLD}${validator_pubkey}${RESET}"
    log_info "  Balance: $(get_balance "$validator_pubkey") SOL"
    echo ""

    log_info "Vote Account:"
    log_info "  Pubkey:  ${BOLD}${vote_pubkey}${RESET}"
    log_info "  Balance: $(get_balance "$vote_pubkey") SOL"
    echo ""

    log_success "All accounts funded successfully!"
    echo ""
    log_info "Next steps:"
    log_info "  1. Create vote account on-chain"
    log_info "  2. Set up validator infrastructure (AWS)"
    log_info "  3. Deploy and start validator"
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    print_banner
    log_section "Testnet Account Funding"

    # Parse command-line arguments
    parse_args "$@"

    # Display configuration
    log_info "Configuration:"
    log_info "  Validator amount: ${VALIDATOR_AMOUNT} SOL"
    log_info "  Vote amount:      ${VOTE_AMOUNT} SOL"
    log_info "  Force mode:       ${FORCE_MODE}"
    echo ""

    # Prerequisites check
    log_section "Prerequisites Check"

    if ! check_solana_cli_installed; then
        exit 1
    fi

    if ! check_testnet_configured; then
        exit 1
    fi

    if ! check_keypairs_exist; then
        exit 1
    fi

    if ! verify_cluster_connectivity; then
        exit 1
    fi

    # Extract public keys
    log_section "Loading Keypairs"

    local validator_pubkey
    validator_pubkey=$(get_keypair_pubkey "$VALIDATOR_KEYPAIR")
    log_info "Validator pubkey: ${validator_pubkey}"

    local vote_pubkey
    vote_pubkey=$(get_keypair_pubkey "$VOTE_KEYPAIR")
    log_info "Vote pubkey:      ${vote_pubkey}"

    # Confirmation prompt (unless force mode)
    if [[ "$FORCE_MODE" == false ]]; then
        echo ""
        log_warn "This will request testnet SOL from the faucet"
        log_info "Faucet requests are rate-limited - you may need to use web faucets if automated requests fail"
        echo ""
        if ! prompt_confirmation "Proceed with funding?"; then
            log_info "Funding cancelled by user"
            exit 0
        fi
    fi

    # Fund accounts
    if ! fund_validator_account "$validator_pubkey" "$VALIDATOR_AMOUNT"; then
        exit 1
    fi

    if ! fund_vote_account "$vote_pubkey" "$VOTE_AMOUNT"; then
        exit 1
    fi

    # Print summary
    print_funding_summary "$validator_pubkey" "$vote_pubkey"

    log_success "Account funding complete!"
    exit 0
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
