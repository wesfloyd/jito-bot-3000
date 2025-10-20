#!/usr/bin/env bash
# Solana-specific helper functions for CLI operations and validator management

# Source common utilities if not already sourced
if [[ -z "${COMMON_LIB_LOADED:-}" ]]; then
    _LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=scripts/lib/common.sh
    source "${_LIB_DIR}/common.sh"
fi

# ============================================================================
# Solana CLI Installation
# ============================================================================

install_solana_cli() {
    log_info "Installing Solana CLI..."

    if command -v solana >/dev/null 2>&1; then
        local version
        version=$(solana --version | awk '{print $2}')
        log_info "Solana CLI already installed: $version"
        return 0
    fi

    # Install Solana CLI
    sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"

    # Add to PATH
    export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"

    # Verify installation
    if ! command -v solana >/dev/null 2>&1; then
        log_error "Solana CLI installation failed"
        return 1
    fi

    local version
    version=$(solana --version | awk '{print $2}')
    log_success "Solana CLI installed: $version"

    return 0
}

configure_solana_cli() {
    local cluster=${1:-testnet}

    log_info "Configuring Solana CLI for $cluster..."

    case "$cluster" in
        mainnet|mainnet-beta)
            solana config set --url https://api.mainnet-beta.solana.com
            ;;
        testnet)
            solana config set --url https://api.testnet.solana.com
            ;;
        devnet)
            solana config set --url https://api.devnet.solana.com
            ;;
        *)
            log_error "Unknown cluster: $cluster"
            return 1
            ;;
    esac

    log_success "Configured for $cluster"

    return 0
}

set_solana_keypair() {
    local keypair_path=$1

    if [[ ! -f "$keypair_path" ]]; then
        log_error "Keypair file not found: $keypair_path"
        return 1
    fi

    log_debug "Setting default keypair: $keypair_path"

    solana config set --keypair "$keypair_path"

    return 0
}

# ============================================================================
# Keypair Generation
# ============================================================================

generate_keypair() {
    local output_file=$1
    local passphrase=${2:-""}

    ensure_directory "$(dirname "$output_file")"

    log_info "Generating keypair: $output_file"

    if [[ -f "$output_file" ]]; then
        log_warn "Keypair already exists: $output_file"
        if ! prompt_confirmation "Overwrite existing keypair?"; then
            log_info "Using existing keypair"
            return 0
        fi
        backup_file "$output_file"
    fi

    if [[ -n "$passphrase" ]]; then
        solana-keygen new -o "$output_file" --word-count 12
    else
        solana-keygen new -o "$output_file" --no-bip39-passphrase --force
    fi

    chmod 600 "$output_file"

    local pubkey
    pubkey=$(solana-keygen pubkey "$output_file")
    log_success "Generated keypair - Pubkey: $pubkey"

    echo "$pubkey"
    return 0
}

get_keypair_pubkey() {
    local keypair_path=$1

    if [[ ! -f "$keypair_path" ]]; then
        log_error "Keypair file not found: $keypair_path"
        return 1
    fi

    solana-keygen pubkey "$keypair_path"
}

verify_keypair() {
    local keypair_path=$1

    if [[ ! -f "$keypair_path" ]]; then
        log_error "Keypair file not found: $keypair_path"
        return 1
    fi

    if ! solana-keygen verify "$(solana-keygen pubkey "$keypair_path")" "$keypair_path" >/dev/null 2>&1; then
        log_error "Keypair verification failed: $keypair_path"
        return 1
    fi

    log_debug "Keypair verified: $keypair_path"
    return 0
}

# ============================================================================
# Balance & Funding
# ============================================================================

get_balance() {
    local address=${1:-}

    if [[ -n "$address" ]]; then
        solana balance "$address" 2>/dev/null | awk '{print $1}'
    else
        solana balance 2>/dev/null | awk '{print $1}'
    fi
}

wait_for_balance() {
    local min_balance=$1
    local address=${2:-}
    local max_attempts=${3:-60}
    local delay=${4:-5}

    log_info "Waiting for balance >= $min_balance SOL..."

    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local balance
        balance=$(get_balance "$address")

        if [[ -z "$balance" ]]; then
            balance=0
        fi

        log_debug "Attempt $attempt/$max_attempts: Balance = $balance SOL"

        if (( $(echo "$balance >= $min_balance" | bc -l) )); then
            log_success "Balance requirement met: $balance SOL"
            return 0
        fi

        sleep "$delay"
        attempt=$((attempt + 1))
    done

    log_error "Balance requirement not met after $max_attempts attempts"
    return 1
}

request_airdrop() {
    local amount=${1:-1}
    local address=${2:-}

    log_info "Requesting airdrop: $amount SOL"

    local result
    if [[ -n "$address" ]]; then
        result=$(solana airdrop "$amount" "$address" 2>&1)
    else
        result=$(solana airdrop "$amount" 2>&1)
    fi

    if echo "$result" | grep -q "Error\|error\|rate"; then
        log_warn "Airdrop failed (likely rate limited)"
        return 1
    fi

    log_success "Airdrop requested: $amount SOL"
    return 0
}

fund_with_faucet() {
    local pubkey=$1
    local min_balance=${2:-5}

    log_section "Funding Account"

    log_info "Target account: $pubkey"
    log_info "Minimum required: $min_balance SOL"

    # Try automated airdrop first
    log_info "Attempting automated airdrop..."

    local airdrop_success=false
    for i in {1..3}; do
        if request_airdrop 2 "$pubkey"; then
            sleep 5
            local balance
            balance=$(get_balance "$pubkey")
            log_info "Current balance: $balance SOL"

            if (( $(echo "$balance >= $min_balance" | bc -l) )); then
                airdrop_success=true
                break
            fi
        fi
        sleep 10
    done

    if $airdrop_success; then
        log_success "Account funded via airdrop"
        return 0
    fi

    # Fallback to manual faucet
    log_warn "Automated airdrop rate limited"
    log_info ""
    log_info "Please use one of these web faucets to fund your account:"
    log_info "  1. https://faucet.solana.com (select 'testnet')"
    log_info "  2. https://faucet.quicknode.com/solana/testnet"
    log_info ""
    log_info "Account to fund: ${BOLD}${GREEN}$pubkey${RESET}"
    log_info ""

    if ! prompt_confirmation "Have you funded the account?"; then
        log_error "Account funding cancelled"
        return 1
    fi

    # Verify balance
    if ! wait_for_balance "$min_balance" "$pubkey" 30 5; then
        log_error "Balance verification failed"
        return 1
    fi

    log_success "Account funded successfully"
    return 0
}

# ============================================================================
# Vote Account Management
# ============================================================================

create_vote_account() {
    local vote_keypair=$1
    local validator_keypair=$2
    local withdrawer_keypair=$3
    local fee_payer=${4:-$validator_keypair}

    log_info "Creating vote account..."

    # Verify all keypairs exist
    for keypair in "$vote_keypair" "$validator_keypair" "$withdrawer_keypair" "$fee_payer"; do
        if [[ ! -f "$keypair" ]]; then
            log_error "Keypair not found: $keypair"
            return 1
        fi
    done

    # Get pubkeys for logging
    local vote_pubkey
    vote_pubkey=$(get_keypair_pubkey "$vote_keypair")
    local validator_pubkey
    validator_pubkey=$(get_keypair_pubkey "$validator_keypair")

    log_info "Vote account: $vote_pubkey"
    log_info "Validator identity: $validator_pubkey"

    # Create vote account
    if ! solana create-vote-account -ut \
        --fee-payer "$fee_payer" \
        "$vote_keypair" \
        "$validator_keypair" \
        "$withdrawer_keypair"; then

        log_error "Failed to create vote account"
        return 1
    fi

    log_success "Vote account created: $vote_pubkey"

    return 0
}

verify_vote_account() {
    local vote_account=$1

    log_info "Verifying vote account: $vote_account"

    if ! solana vote-account "$vote_account" >/dev/null 2>&1; then
        log_error "Vote account not found or invalid"
        return 1
    fi

    log_success "Vote account verified"

    return 0
}

get_vote_account_info() {
    local vote_account=$1

    solana vote-account "$vote_account"
}

get_vote_credits() {
    local vote_account=$1

    solana vote-account "$vote_account" 2>/dev/null | \
        grep "Credits" | \
        awk '{print $2}' | \
        tr -d ','
}

# ============================================================================
# Validator Status & Monitoring
# ============================================================================

get_validator_info() {
    local validator_pubkey=$1

    solana validators | grep "$validator_pubkey"
}

check_validator_in_gossip() {
    local validator_pubkey=$1

    log_info "Checking gossip for validator: $validator_pubkey"

    if solana gossip | grep -q "$validator_pubkey"; then
        log_success "Validator found in gossip network"
        return 0
    else
        log_warn "Validator not found in gossip network"
        return 1
    fi
}

check_validator_in_set() {
    local validator_pubkey=$1

    log_info "Checking validator set for: $validator_pubkey"

    if solana validators | grep -q "$validator_pubkey"; then
        log_success "Validator found in validator set"
        return 0
    else
        log_warn "Validator not found in validator set"
        return 1
    fi
}

get_catchup_status() {
    local validator_pubkey=$1

    solana catchup "$validator_pubkey" 2>&1
}

is_validator_caught_up() {
    local validator_pubkey=$1

    local status
    status=$(get_catchup_status "$validator_pubkey")

    if echo "$status" | grep -q "caught up"; then
        return 0
    else
        return 1
    fi
}

wait_for_catchup() {
    local validator_pubkey=$1
    local max_minutes=${2:-90}

    log_info "Monitoring catchup status (max: ${max_minutes}m)..."
    log_info "This may take 30-90 minutes depending on network conditions"

    local start_time
    start_time=$(date +%s)
    local max_seconds=$((max_minutes * 60))

    while true; do
        local elapsed=$(($(date +%s) - start_time))

        if [[ $elapsed -gt $max_seconds ]]; then
            log_warn "Catchup timeout after ${max_minutes} minutes"
            log_info "Validator may still be catching up - check manually"
            return 1
        fi

        local status
        status=$(get_catchup_status "$validator_pubkey")

        if echo "$status" | grep -q "caught up"; then
            log_success "Validator has caught up!"
            return 0
        elif echo "$status" | grep -q "Error\|error"; then
            log_error "Error checking catchup status"
            return 1
        fi

        # Show progress
        local minutes_elapsed=$((elapsed / 60))
        log_info "[$minutes_elapsed/$max_minutes min] Still catching up..."

        sleep 60
    done
}

# ============================================================================
# Network & Cluster Info
# ============================================================================

get_current_slot() {
    solana slot 2>/dev/null
}

get_epoch_info() {
    solana epoch-info
}

get_cluster_version() {
    solana cluster-version
}

check_cluster_health() {
    local cluster=$1

    log_info "Checking cluster health: $cluster"

    if ! solana cluster-version >/dev/null 2>&1; then
        log_error "Cannot connect to cluster"
        return 1
    fi

    log_success "Cluster is reachable"
    return 0
}

# ============================================================================
# Transaction Helpers
# ============================================================================

get_transaction_fee() {
    # Get approximate transaction fee
    solana fees 2>/dev/null | grep "Lamports per signature" | awk '{print $4}'
}

wait_for_confirmation() {
    local signature=$1
    local max_attempts=${2:-30}

    log_debug "Waiting for transaction confirmation: $signature"

    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if solana confirm "$signature" >/dev/null 2>&1; then
            log_debug "Transaction confirmed"
            return 0
        fi

        sleep 2
        attempt=$((attempt + 1))
    done

    log_error "Transaction not confirmed"
    return 1
}
