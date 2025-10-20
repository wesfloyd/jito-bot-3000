#!/usr/bin/env bash
# Configure BAM (Block Assembly Marketplace) for Jito validator
# This script prepares the validator for BAM integration

set -euo pipefail

# ============================================================================
# Source common utilities
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source common utilities
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/scripts/utils/lib/common.sh"

# ============================================================================
# Configuration
# ============================================================================

BAM_CONFIG_FILE="${CONFIG_DIR}/bam-config.env"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

# Parse command line arguments
FORCE_MODE=false
ENABLE_BAM=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_MODE=true
            shift
            ;;
        --enable)
            ENABLE_BAM=true
            shift
            ;;
        --disable)
            ENABLE_BAM=false
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Usage: $0 [--force] [--enable|--disable]"
            exit 1
            ;;
    esac
done

# ============================================================================
# Functions
# ============================================================================

check_prerequisites() {
    log_info "Checking BAM prerequisites..."

    # Check if BAM config exists
    if [[ ! -f "$BAM_CONFIG_FILE" ]]; then
        log_error "BAM configuration file not found: $BAM_CONFIG_FILE"
        log_error "Run this from project root or ensure config/bam-config.env exists"
        return 1
    fi

    # Source BAM config
    # shellcheck disable=SC1090
    source "$BAM_CONFIG_FILE"

    # Check if validator is operational
    log_info "Checking validator status..."

    # Get SSH connection info
    local ssh_key ssh_host ssh_user
    ssh_key=$(get_terraform_output "ssh_key_file" 2>/dev/null || echo "")
    ssh_host=$(get_terraform_output "instance_public_ip" 2>/dev/null || echo "")
    ssh_user=$(get_terraform_output "ssh_user" 2>/dev/null || echo "ubuntu")

    if [[ -z "$ssh_host" ]]; then
        log_error "Cannot determine instance IP. Is infrastructure deployed?"
        return 1
    fi

    # Check if validator process is running
    local validator_running
    validator_running=$(ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o LogLevel=ERROR \
        "$ssh_user@$ssh_host" "pgrep -f agave-validator >/dev/null && echo 'yes' || echo 'no'")

    if [[ "$validator_running" != "yes" ]]; then
        log_error "Validator is not running. Start validator first with:"
        log_error "  ./scripts/validator/launch.sh start"
        return 1
    fi

    log_success "Validator process is running"

    # Check if validator is caught up (optional warning, not blocking)
    log_info "Checking validator catchup status..."
    local catchup_output
    catchup_output=$(ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o LogLevel=ERROR \
        "$ssh_user@$ssh_host" \
        "export PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\" && \
         solana catchup \$(solana-keygen pubkey ~/validator/keys/validator-keypair.json) -ut 2>&1 || echo 'catchup-check-failed'")

    if echo "$catchup_output" | grep -q "is caught up"; then
        log_success "Validator is caught up"
    else
        log_warn "Validator may still be catching up"
        log_warn "BAM works best when validator is fully synced"
        if [[ "$FORCE_MODE" == false ]]; then
            log_info "Consider waiting for catchup to complete, or use --force to continue anyway"
            return 1
        fi
    fi

    # Check disk space for RPC transaction history
    log_info "Checking disk space for RPC transaction history..."
    local disk_usage
    disk_usage=$(ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o LogLevel=ERROR \
        "$ssh_user@$ssh_host" "df -h ~ | tail -1 | awk '{print \$5}' | sed 's/%//'")

    if [[ -n "$disk_usage" ]] && [[ "$disk_usage" -gt 50 ]]; then
        log_warn "Disk usage is at ${disk_usage}% - consider adding more storage"
        log_warn "RPC transaction history requires significant disk space"
    else
        log_success "Disk space: ${disk_usage}% used - sufficient for RPC history"
    fi

    # Check leader schedule (warning only, not blocking on testnet)
    log_info "Checking leader schedule status..."
    local leader_slots
    leader_slots=$(ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o LogLevel=ERROR \
        "$ssh_user@$ssh_host" \
        "export PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\" && \
         solana leader-schedule -ut 2>/dev/null | grep -c \$(solana-keygen pubkey ~/validator/keys/validator-keypair.json) || echo '0'")

    if [[ "$leader_slots" -eq 0 ]]; then
        log_warn "Validator has 0 leader slots in current epoch"
        log_warn "BAM integration requires stake and leader slots for full functionality"
        log_warn "On testnet with 0 stake, BAM will be enabled but won't produce blocks"
    else
        log_success "Validator has $leader_slots leader slots in current epoch"
    fi

    log_success "Prerequisites check completed"
}

update_validator_config() {
    log_info "Updating validator configuration for BAM..."

    # Source BAM config
    # shellcheck disable=SC1090
    source "$BAM_CONFIG_FILE"

    # Get SSH connection info
    local ssh_key ssh_host ssh_user
    ssh_key=$(get_terraform_output "ssh_key_file")
    ssh_host=$(get_terraform_output "instance_public_ip")
    ssh_user=$(get_terraform_output "ssh_user" 2>/dev/null || echo "ubuntu")

    # Create BAM configuration script
    local config_script
    config_script=$(cat <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

VALIDATOR_DIR="$HOME/validator"
START_SCRIPT="$VALIDATOR_DIR/start-validator.sh"
BAM_ENABLED="__BAM_ENABLED__"
BAM_URL="__BAM_URL__"
BAM_METRICS_HOST="__BAM_METRICS_HOST__"
BAM_METRICS_DB="__BAM_METRICS_DB__"
BAM_METRICS_USER="__BAM_METRICS_USER__"
BAM_METRICS_PASSWORD="__BAM_METRICS_PASSWORD__"

# Backup current config
cp "$START_SCRIPT" "${START_SCRIPT}.bak-$(date +%Y%m%d-%H%M%S)"

# Read current startup script
STARTUP_SCRIPT=$(cat "$START_SCRIPT")

# Remove existing BAM flags if present
STARTUP_SCRIPT=$(echo "$STARTUP_SCRIPT" | grep -v "bam-url" || true)
STARTUP_SCRIPT=$(echo "$STARTUP_SCRIPT" | grep -v "enable-rpc-transaction-history" || true)

if [[ "$BAM_ENABLED" == "true" ]]; then
    echo "Enabling BAM integration..."

    # Add BAM flags before the final line (which contains the validator identity)
    # Insert before the last line that starts with exec
    TEMP_FILE=$(mktemp)
    echo "$STARTUP_SCRIPT" | sed '/^exec.*agave-validator/i\
  --bam-url '"$BAM_URL"' \\\
  --enable-rpc-transaction-history \\' > "$TEMP_FILE"

    # Also export metrics environment variable
    cat > "$START_SCRIPT" <<SCRIPT_END
#!/usr/bin/env bash
set -euo pipefail

# BAM Metrics Configuration
export SOLANA_METRICS_CONFIG="host=${BAM_METRICS_HOST},db=${BAM_METRICS_DB},u=${BAM_METRICS_USER},p=${BAM_METRICS_PASSWORD}"

SCRIPT_END
    cat "$TEMP_FILE" >> "$START_SCRIPT"
    rm "$TEMP_FILE"

    chmod +x "$START_SCRIPT"
    echo "BAM integration enabled"
else
    echo "BAM integration disabled (keeping existing configuration)"
    # Just restore the script without BAM flags
    echo "$STARTUP_SCRIPT" > "$START_SCRIPT"
    chmod +x "$START_SCRIPT"
fi

echo "Validator configuration updated successfully"
EOF
)

    # Replace placeholders
    config_script="${config_script//__BAM_ENABLED__/$ENABLE_BAM}"
    config_script="${config_script//__BAM_URL__/$BAM_URL}"
    config_script="${config_script//__BAM_METRICS_HOST__/$BAM_METRICS_HOST}"
    config_script="${config_script//__BAM_METRICS_DB__/$BAM_METRICS_DB}"
    config_script="${config_script//__BAM_METRICS_USER__/$BAM_METRICS_USER}"
    config_script="${config_script//__BAM_METRICS_PASSWORD__/$BAM_METRICS_PASSWORD}"

    # Upload and execute configuration script
    echo "$config_script" | ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o LogLevel=ERROR \
        "$ssh_user@$ssh_host" "cat > /tmp/configure-bam.sh && bash /tmp/configure-bam.sh && rm /tmp/configure-bam.sh"

    if [[ "$ENABLE_BAM" == "true" ]]; then
        log_success "BAM integration enabled in validator configuration"
        log_info "Restart validator to apply changes:"
        log_info "  ./scripts/validator/launch.sh restart"
    else
        log_success "BAM integration disabled in validator configuration"
    fi
}

update_bam_config_file() {
    log_info "Updating BAM configuration file..."

    # Update ENABLE_BAM value in config file
    if [[ "$ENABLE_BAM" == "true" ]]; then
        sed -i.bak 's/^ENABLE_BAM="false"/ENABLE_BAM="true"/' "$BAM_CONFIG_FILE"
        log_success "Set ENABLE_BAM=true in $BAM_CONFIG_FILE"
    else
        sed -i.bak 's/^ENABLE_BAM="true"/ENABLE_BAM="false"/' "$BAM_CONFIG_FILE"
        log_success "Set ENABLE_BAM=false in $BAM_CONFIG_FILE"
    fi

    rm -f "${BAM_CONFIG_FILE}.bak"
}

# ============================================================================
# Main
# ============================================================================

print_banner "BAM Configuration"

log_info "BAM (Block Assembly Marketplace) Configuration"
log_info "Mode: $(if [[ "$ENABLE_BAM" == "true" ]]; then echo "ENABLE"; else echo "DISABLE"; fi)"
echo ""

# Check prerequisites
if ! check_prerequisites; then
    log_error "Prerequisites check failed"
    exit 1
fi

echo ""

# Update validator configuration
if ! update_validator_config; then
    log_error "Failed to update validator configuration"
    exit 1
fi

# Update BAM config file
update_bam_config_file

echo ""
log_success "BAM configuration completed successfully"
echo ""

if [[ "$ENABLE_BAM" == "true" ]]; then
    log_info "Next steps:"
    log_info "1. Restart validator: ./scripts/validator/launch.sh restart"
    log_info "2. Monitor logs: ./scripts/validator/launch.sh logs --follow"
    log_info "3. Verify BAM connection: ./scripts/utils/verify-bam.sh (coming soon)"
else
    log_info "BAM has been disabled. Restart validator to apply changes."
fi
