#!/usr/bin/env bash
# Validator Launch Script
#
# This script provides a convenient interface to manage the Jito-Solana validator
# from your local machine. It handles SSH connections and validator lifecycle.
#
# Usage:
#   ./scripts/validator/launch.sh <command> [options]
#
# Commands:
#   start       Start the validator
#   stop        Stop the validator
#   restart     Restart the validator
#   status      Show validator status
#   logs        Show validator logs (live tail)
#   health      Check validator health
#
# Options:
#   --systemd   Use systemd service (default: direct script execution)
#   --follow    Follow logs in real-time (for 'logs' command)
#
# Examples:
#   ./scripts/validator/launch.sh start
#   ./scripts/validator/launch.sh status
#   ./scripts/validator/launch.sh logs --follow
#   ./scripts/validator/launch.sh start --systemd

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

USE_SYSTEMD=false
FOLLOW_LOGS=false
COMMAND=""

# Remote paths
REMOTE_VALIDATOR_DIR="~/validator"
REMOTE_START_SCRIPT="${REMOTE_VALIDATOR_DIR}/start-validator.sh"
REMOTE_LOG_DIR="${REMOTE_VALIDATOR_DIR}/logs"

# Systemd service
SYSTEMD_SERVICE="jito-validator.service"

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    COMMAND=$1
    shift

    while [[ $# -gt 0 ]]; do
        case $1 in
            --systemd)
                USE_SYSTEMD=true
                shift
                ;;
            --follow)
                FOLLOW_LOGS=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
Usage: $0 <command> [options]

Manage the Jito-Solana validator from your local machine.

Commands:
  start       Start the validator
  stop        Stop the validator
  restart     Restart the validator
  status      Show validator status
  logs        Show validator logs
  health      Check validator health and metrics

Options:
  --systemd   Use systemd service (default: direct script)
  --follow    Follow logs in real-time (for 'logs' command)
  -h, --help  Show this help message

Examples:
  # Start validator using direct script
  $0 start

  # Start validator using systemd
  $0 start --systemd

  # Check status
  $0 status

  # View logs (last 50 lines)
  $0 logs

  # Follow logs in real-time
  $0 logs --follow

  # Check validator health
  $0 health

  # Stop validator
  $0 stop

  # Restart validator
  $0 restart

EOF
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

    if ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o LogLevel=ERROR \
        "$ssh_host" "echo 'SSH connection successful'" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

ssh_exec() {
    local ssh_host=$1
    local ssh_key=$2
    local command=$3

    ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" "$command"
}

# ============================================================================
# Validator Control Functions
# ============================================================================

start_validator() {
    local ssh_host=$1
    local ssh_key=$2

    log_section "Starting Validator"

    # Check if already running
    if is_validator_running "$ssh_host" "$ssh_key"; then
        log_warn "Validator is already running"
        log_info "Use 'restart' to restart, or 'stop' then 'start'"
        return 0
    fi

    if [[ "$USE_SYSTEMD" == true ]]; then
        log_info "Starting validator using systemd..."
        ssh_exec "$ssh_host" "$ssh_key" "sudo systemctl start $SYSTEMD_SERVICE"

        sleep 3

        if ssh_exec "$ssh_host" "$ssh_key" "sudo systemctl is-active $SYSTEMD_SERVICE" | grep -q "active"; then
            log_success "Validator started via systemd"
            log_info "Check status: sudo systemctl status $SYSTEMD_SERVICE"
            log_info "View logs: sudo journalctl -u $SYSTEMD_SERVICE -f"
        else
            log_error "Validator failed to start"
            return 1
        fi
    else
        log_info "Starting validator using direct script..."
        log_warn "Note: This will run in the background. Use 'logs --follow' to monitor."

        # Start validator in background using nohup
        ssh_exec "$ssh_host" "$ssh_key" \
            "cd ${REMOTE_VALIDATOR_DIR} && nohup ./start-validator.sh > /dev/null 2>&1 &"

        sleep 5

        if is_validator_running "$ssh_host" "$ssh_key"; then
            log_success "Validator started successfully"
            log_info "Monitor logs: $0 logs --follow"
        else
            log_error "Validator failed to start"
            log_info "Check logs for errors: $0 logs"
            return 1
        fi
    fi

    return 0
}

stop_validator() {
    local ssh_host=$1
    local ssh_key=$2

    log_section "Stopping Validator"

    if ! is_validator_running "$ssh_host" "$ssh_key"; then
        log_warn "Validator is not running"
        return 0
    fi

    if [[ "$USE_SYSTEMD" == true ]]; then
        log_info "Stopping validator via systemd..."
        ssh_exec "$ssh_host" "$ssh_key" "sudo systemctl stop $SYSTEMD_SERVICE"

        sleep 3

        if ! is_validator_running "$ssh_host" "$ssh_key"; then
            log_success "Validator stopped"
        else
            log_error "Failed to stop validator"
            return 1
        fi
    else
        log_info "Stopping validator process..."
        ssh_exec "$ssh_host" "$ssh_key" "pkill -f agave-validator || true"

        sleep 3

        if ! is_validator_running "$ssh_host" "$ssh_key"; then
            log_success "Validator stopped"
        else
            log_error "Failed to stop validator"
            return 1
        fi
    fi

    return 0
}

restart_validator() {
    local ssh_host=$1
    local ssh_key=$2

    log_section "Restarting Validator"

    if stop_validator "$ssh_host" "$ssh_key"; then
        sleep 2
        start_validator "$ssh_host" "$ssh_key"
    else
        log_error "Failed to stop validator, cannot restart"
        return 1
    fi
}

# ============================================================================
# Status & Monitoring Functions
# ============================================================================

is_validator_running() {
    local ssh_host=$1
    local ssh_key=$2

    local running
    running=$(ssh_exec "$ssh_host" "$ssh_key" \
        "pgrep -f agave-validator >/dev/null && echo 'yes' || echo 'no'")

    [[ "$running" == "yes" ]]
}

show_status() {
    local ssh_host=$1
    local ssh_key=$2

    log_section "Validator Status"

    # Check if running
    if is_validator_running "$ssh_host" "$ssh_key"; then
        log_success "Validator is RUNNING"

        # Get process info
        local pid
        pid=$(ssh_exec "$ssh_host" "$ssh_key" "pgrep -f agave-validator")
        log_info "Process ID: $pid"

        # Get uptime
        local uptime
        uptime=$(ssh_exec "$ssh_host" "$ssh_key" \
            "ps -p $pid -o etime= 2>/dev/null | tr -d ' '" || echo "unknown")
        log_info "Uptime: $uptime"

    else
        log_warn "Validator is NOT RUNNING"
    fi

    # Check systemd status if available
    if [[ "$USE_SYSTEMD" == true ]]; then
        echo ""
        log_info "Systemd service status:"
        ssh_exec "$ssh_host" "$ssh_key" "sudo systemctl status $SYSTEMD_SERVICE --no-pager" || true
    fi

    # Show recent log entries
    echo ""
    log_info "Recent log entries (last 10 lines):"
    local latest_log
    latest_log=$(ssh_exec "$ssh_host" "$ssh_key" "ls -t ${REMOTE_LOG_DIR}/*.log 2>/dev/null | head -1" || echo "")

    if [[ -n "$latest_log" ]]; then
        ssh_exec "$ssh_host" "$ssh_key" "tail -10 $latest_log 2>/dev/null" || true
    else
        log_warn "No log files found"
    fi
}

show_logs() {
    local ssh_host=$1
    local ssh_key=$2

    log_section "Validator Logs"

    # Find latest log file
    local latest_log
    latest_log=$(ssh_exec "$ssh_host" "$ssh_key" "ls -t ${REMOTE_LOG_DIR}/*.log 2>/dev/null | head -1" || echo "")

    if [[ -z "$latest_log" ]]; then
        log_error "No log files found in ${REMOTE_LOG_DIR}"
        return 1
    fi

    log_info "Log file: $latest_log"
    echo ""

    if [[ "$FOLLOW_LOGS" == true ]]; then
        log_info "Following logs (Ctrl+C to exit)..."
        echo ""
        ssh -i "$ssh_key" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            "$ssh_host" "tail -f $latest_log"
    else
        ssh_exec "$ssh_host" "$ssh_key" "tail -50 $latest_log"
    fi
}

check_health() {
    local ssh_host=$1
    local ssh_key=$2

    log_section "Validator Health Check"

    # Check if running
    if ! is_validator_running "$ssh_host" "$ssh_key"; then
        log_error "Validator is not running"
        return 1
    fi

    log_success "Validator process is running"
    echo ""

    # Check RPC health (if enabled)
    log_info "Checking RPC endpoint..."
    local rpc_check
    rpc_check=$(ssh_exec "$ssh_host" "$ssh_key" \
        "curl -s -X POST -H 'Content-Type: application/json' \
         -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getHealth\"}' \
         http://localhost:8899 2>/dev/null || echo 'failed'")

    if echo "$rpc_check" | grep -q "ok"; then
        log_success "RPC endpoint is healthy"
    else
        log_warn "RPC endpoint check failed (may be starting up)"
    fi

    echo ""

    # Check vote account
    log_info "Checking vote account..."
    local vote_info
    vote_info=$(ssh_exec "$ssh_host" "$ssh_key" \
        "export PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\" && \
         solana vote-account \$(solana-keygen pubkey ${REMOTE_VALIDATOR_DIR}/keys/vote-account-keypair.json) 2>&1 | head -10" || echo "")

    if echo "$vote_info" | grep -q "Credits"; then
        log_success "Vote account is active"
        echo "$vote_info"
    else
        log_warn "Vote account check inconclusive"
    fi

    echo ""
    log_info "For detailed metrics, check the logs with: $0 logs --follow"
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    print_banner

    # Parse arguments
    parse_args "$@"

    # Get SSH connection info
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

    # Test SSH connection
    if ! test_ssh_connection "$ssh_host" "$ssh_key"; then
        log_error "Cannot connect to remote instance"
        log_info "Instance: $ssh_host"
        exit 1
    fi

    # Execute command
    case "$COMMAND" in
        start)
            start_validator "$ssh_host" "$ssh_key"
            ;;
        stop)
            stop_validator "$ssh_host" "$ssh_key"
            ;;
        restart)
            restart_validator "$ssh_host" "$ssh_key"
            ;;
        status)
            show_status "$ssh_host" "$ssh_key"
            ;;
        logs)
            show_logs "$ssh_host" "$ssh_key"
            ;;
        health)
            check_health "$ssh_host" "$ssh_key"
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac

    exit 0
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
