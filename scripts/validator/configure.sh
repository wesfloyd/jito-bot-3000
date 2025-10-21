#!/usr/bin/env bash
# Validator Configuration Script
#
# This script generates the validator startup script on the remote EC2 instance.
# It performs the following tasks:
# 1. Creates validator startup script with Jito-specific parameters
# 2. Configures RPC endpoints for testnet
# 3. Sets up logging configuration
# 4. Configures performance settings
# 5. Sets up systemd service (optional)
#
# Usage:
#   ./scripts/validator/configure.sh [--force]
#
# Options:
#   --force    Skip confirmation prompts
#
# Exit codes:
#   0 - Success
#   1 - Error (SSH connection failed, configuration failed, etc.)

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

# Jito-specific configuration
JITO_BLOCK_ENGINE_URL="https://ny.testnet.block-engine.jito.wtf"
JITO_RELAYER_URL="nyc.testnet.relayer.jito.wtf:8100"
JITO_SHRED_RECEIVER_ADDR="141.98.216.97:1002"

# Solana testnet configuration - MULTIPLE ENTRYPOINTS for better discovery
TESTNET_ENTRYPOINT1="entrypoint.testnet.solana.com:8001"
TESTNET_ENTRYPOINT2="entrypoint2.testnet.solana.com:8001"
TESTNET_ENTRYPOINT3="entrypoint3.testnet.solana.com:8001"
TESTNET_RPC="https://api.testnet.solana.com"

# Remote paths
REMOTE_VALIDATOR_DIR="~/validator"
REMOTE_KEYS_DIR="${REMOTE_VALIDATOR_DIR}/keys"
REMOTE_LEDGER_DIR="${REMOTE_VALIDATOR_DIR}/ledger"
REMOTE_ACCOUNTS_DIR="${REMOTE_VALIDATOR_DIR}/accounts"
REMOTE_LOG_DIR="${REMOTE_VALIDATOR_DIR}/logs"
REMOTE_SNAPSHOTS_DIR="${REMOTE_VALIDATOR_DIR}/snapshots"

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

Generate validator startup script on the remote EC2 instance.

Options:
  --force    Skip confirmation prompts
  -h, --help Show this help message

Configuration Details:
  - Jito Block Engine: $JITO_BLOCK_ENGINE_URL
  - Jito Relayer: $JITO_RELAYER_URL
  - Jito Shred Receiver: $JITO_SHRED_RECEIVER_ADDR
  - Testnet Entrypoint: $TESTNET_ENTRYPOINT
  - Testnet RPC: $TESTNET_RPC

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
# Configuration Generation Functions
# ============================================================================

generate_validator_script() {
    cat << 'EOF_VALIDATOR_SCRIPT'
#!/usr/bin/env bash
# Jito-Solana Validator Startup Script
# Generated by scripts/validator/configure.sh
#
# This script starts the Jito-Solana validator with all required parameters
# for testnet operation with MEV integration.

set -euo pipefail

# Add Solana CLI to PATH
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# Validator directories
VALIDATOR_DIR="$HOME/validator"
KEYS_DIR="$VALIDATOR_DIR/keys"
LEDGER_DIR="$VALIDATOR_DIR/ledger"
ACCOUNTS_DIR="$VALIDATOR_DIR/accounts"
LOG_DIR="$VALIDATOR_DIR/logs"
SNAPSHOTS_DIR="$VALIDATOR_DIR/snapshots"

# Keypairs
IDENTITY_KEYPAIR="$KEYS_DIR/validator-keypair.json"
VOTE_ACCOUNT="$KEYS_DIR/vote-account-keypair.json"

# Jito configuration
BLOCK_ENGINE_URL="BLOCK_ENGINE_URL_PLACEHOLDER"
RELAYER_URL="RELAYER_URL_PLACEHOLDER"
SHRED_RECEIVER_ADDR="SHRED_RECEIVER_ADDR_PLACEHOLDER"

# Testnet configuration - MULTIPLE ENTRYPOINTS for better discovery
ENTRYPOINT1="ENTRYPOINT1_PLACEHOLDER"
ENTRYPOINT2="ENTRYPOINT2_PLACEHOLDER"
ENTRYPOINT3="ENTRYPOINT3_PLACEHOLDER"
EXPECTED_GENESIS_HASH="4uhcVJyU9pJkvQyS88uRDiswHXSCkY3zQawwpjk2NsNY"

# Create log directory
mkdir -p "$LOG_DIR"

# Log files with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/validator-$TIMESTAMP.log"
ERROR_LOG="$LOG_DIR/validator-$TIMESTAMP.err"

echo "Starting Jito-Solana Validator..."
echo "Log file: $LOG_FILE"
echo "Error log: $ERROR_LOG"

# Enable Rust backtrace for better error messages
export RUST_BACKTRACE=1
export RUST_LOG=info

# UPDATED: Active validators running 3.0.6 (from solana validators -ut)
# Using actively voting validators for better RPC peer discovery
KNOWN_VALIDATORS=(
    "FQmkXYMLeo1BjqJ2u29gPffzCP4c8ukLQn3qADdPAAgH"  # Active 3.0.6
    "thorNNMs3a7UKRMH48uSaB5KA6BC5zZPEKN5v8YPJyL"   # Active 3.0.6
    "4JVC4HKsWkra2hkcAKaCTM3T7awMBikpwQZ67Zhaq8v3"  # Active 3.0.6 (50% commission)
    "FBMv4JP8heqqXFPgbBKp9Pc8e4BcFzHeXosHpTSRoixo"  # Active 3.0.6
    "AYSACY1Qv7KKUESKZ2a3mM1mBES4qJbyxa39A79T8bE4"  # Active 3.0.6
    "BUZdr8LsrpAMtf2VyQ5QBH8cwa6TEkwM3BQ1b3zhsxf"   # Active 3.0.6
)

# Start validator with MULTIPLE ENTRYPOINTS for better RPC discovery
exec agave-validator \
    --identity "$IDENTITY_KEYPAIR" \
    --vote-account "$VOTE_ACCOUNT" \
    --ledger "$LEDGER_DIR" \
    --accounts "$ACCOUNTS_DIR" \
    --snapshots "$SNAPSHOTS_DIR" \
    --log "$LOG_FILE" \
    --rpc-port 8899 \
    --dynamic-port-range 8000-8025 \
    --entrypoint "$ENTRYPOINT1" \
    --entrypoint "$ENTRYPOINT2" \
    --entrypoint "$ENTRYPOINT3" \
    --expected-genesis-hash "$EXPECTED_GENESIS_HASH" \
    --known-validator "${KNOWN_VALIDATORS[0]}" \
    --known-validator "${KNOWN_VALIDATORS[1]}" \
    --known-validator "${KNOWN_VALIDATORS[2]}" \
    --known-validator "${KNOWN_VALIDATORS[3]}" \
    --known-validator "${KNOWN_VALIDATORS[4]}" \
    --known-validator "${KNOWN_VALIDATORS[5]}" \
    --wal-recovery-mode skip_any_corrupted_record \
    --limit-ledger-size 50000000 \
    --block-engine-url "$BLOCK_ENGINE_URL" \
    --relayer-url "$RELAYER_URL" \
    --shred-receiver-address "$SHRED_RECEIVER_ADDR" \
    --rpc-bind-address 0.0.0.0 \
    --full-rpc-api \
    --tip-payment-program-pubkey GJHtFqM9agxPmkeKjHny6qiRKrXZALvvFGiKf11QE7hy \
    --tip-distribution-program-pubkey F2Zu7QZiTYUhPd7u9ukRVwxh7B71oA3NMJcHuCHc29P2 \
    --merkle-root-upload-authority GZctHpWXmsZC1YHACTGGcHhYxjdRqQvTpYkb9LMvxDib \
    --commission-bps 800 \
    2>> "$ERROR_LOG"

EOF_VALIDATOR_SCRIPT
}

upload_validator_script() {
    local ssh_host=$1
    local ssh_key=$2

    log_section "Generating Validator Configuration"

    # Generate script with placeholders
    local temp_script
    temp_script=$(mktemp)
    generate_validator_script > "$temp_script"

    # Replace placeholders with actual values
    sed -i.bak \
        -e "s|BLOCK_ENGINE_URL_PLACEHOLDER|${JITO_BLOCK_ENGINE_URL}|g" \
        -e "s|RELAYER_URL_PLACEHOLDER|${JITO_RELAYER_URL}|g" \
        -e "s|SHRED_RECEIVER_ADDR_PLACEHOLDER|${JITO_SHRED_RECEIVER_ADDR}|g" \
        -e "s|ENTRYPOINT1_PLACEHOLDER|${TESTNET_ENTRYPOINT1}|g" \
        -e "s|ENTRYPOINT2_PLACEHOLDER|${TESTNET_ENTRYPOINT2}|g" \
        -e "s|ENTRYPOINT3_PLACEHOLDER|${TESTNET_ENTRYPOINT3}|g" \
        "$temp_script"

    log_info "Uploading validator startup script..."
    scp -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$temp_script" \
        "${ssh_host}:${REMOTE_VALIDATOR_DIR}/start-validator.sh"

    rm "$temp_script" "$temp_script.bak"

    # Make script executable
    log_info "Making script executable..."
    ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "chmod +x ${REMOTE_VALIDATOR_DIR}/start-validator.sh"

    log_success "Validator startup script configured"
}

create_systemd_service() {
    local ssh_host=$1
    local ssh_key=$2

    log_info "Creating systemd service (optional)..."

    # Generate systemd service file
    local service_content
    service_content=$(cat << 'EOF_SERVICE'
[Unit]
Description=Jito-Solana Validator
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/validator
ExecStart=/home/ubuntu/validator/start-validator.sh
Restart=on-failure
RestartSec=10
LimitNOFILE=1000000
LimitMEMLOCK=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF_SERVICE
    )

    # Upload service file
    echo "$service_content" | ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "sudo tee /etc/systemd/system/jito-validator.service > /dev/null"

    # Reload systemd
    ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" \
        "sudo systemctl daemon-reload"

    log_success "Systemd service created (not enabled)"
    log_info "To enable: sudo systemctl enable jito-validator"
    log_info "To start: sudo systemctl start jito-validator"
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    print_banner
    log_section "Validator Configuration"

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

    # Confirm before proceeding (unless force mode)
    if [[ "$FORCE_MODE" == false ]]; then
        echo ""
        log_warn "This will create validator startup configuration"
        log_info "Configuration details:"
        log_info "  - Jito Block Engine: $JITO_BLOCK_ENGINE_URL"
        log_info "  - Jito Relayer: $JITO_RELAYER_URL"
        log_info "  - Jito Shred Receiver: $JITO_SHRED_RECEIVER_ADDR"
        log_info "  - Testnet Entrypoints: $TESTNET_ENTRYPOINT1, $TESTNET_ENTRYPOINT2, $TESTNET_ENTRYPOINT3"
        echo ""
        if ! prompt_confirmation "Proceed with configuration?"; then
            log_info "Configuration cancelled by user"
            exit 0
        fi
    fi

    # Upload validator script
    if ! upload_validator_script "$ssh_host" "$ssh_key"; then
        log_error "Failed to upload validator script"
        exit 1
    fi

    # Create systemd service
    if ! create_systemd_service "$ssh_host" "$ssh_key"; then
        log_warn "Failed to create systemd service (non-fatal)"
    fi

    # Success summary
    log_section "Configuration Complete"

    log_success "Validator configured successfully"
    echo ""
    log_info "Startup script: ~/validator/start-validator.sh"
    log_info "Systemd service: jito-validator.service"
    echo ""
    log_info "Next steps:"
    log_info "  1. Create vote account (if not already created)"
    log_info "  2. Start the validator: ./validator/start-validator.sh"
    log_info "  OR use systemd: sudo systemctl start jito-validator"

    exit 0
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
