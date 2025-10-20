#!/usr/bin/env bash
# Comprehensive Validator Status & Health Monitoring Script
#
# This script provides a detailed overview of validator health, including:
# - Infrastructure status (AWS EC2)
# - Validator process status
# - Network connectivity
# - Vote account status
# - Recent performance metrics
# - Disk usage
# - Log analysis
#
# Usage:
#   ./scripts/utils/status.sh [options]
#
# Options:
#   --full          Show full detailed status
#   --quick         Show quick status overview (default)
#   --watch         Continuously monitor status (refresh every 30s)
#   --json          Output status as JSON
#   -h, --help      Show this help message

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

MODE="quick"
WATCH_MODE=false
JSON_OUTPUT=false
WATCH_INTERVAL=30

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --full)
                MODE="full"
                shift
                ;;
            --quick)
                MODE="quick"
                shift
                ;;
            --watch)
                WATCH_MODE=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
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
Usage: $0 [options]

Comprehensive validator status and health monitoring.

Options:
  --full          Show full detailed status with all metrics
  --quick         Show quick status overview (default)
  --watch         Continuously monitor status (refresh every ${WATCH_INTERVAL}s)
  --json          Output status as JSON
  -h, --help      Show this help message

Examples:
  # Quick status check
  $0

  # Full detailed status
  $0 --full

  # Continuous monitoring
  $0 --watch

  # Get status as JSON
  $0 --json

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

ssh_exec() {
    local ssh_host=$1
    local ssh_key=$2
    local command=$3

    ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ConnectTimeout=5 \
        "$ssh_host" "$command" 2>/dev/null
}

# ============================================================================
# Status Collection Functions
# ============================================================================

get_infrastructure_status() {
    local terraform_dir="${PROJECT_ROOT}/terraform"
    cd "$terraform_dir"

    local instance_id
    instance_id=$(terraform output -raw instance_id 2>/dev/null || echo "unknown")

    local instance_type
    instance_type=$(terraform output -raw instance_type 2>/dev/null || echo "unknown")

    local region
    region=$(terraform output -raw aws_region 2>/dev/null || echo "unknown")

    local public_ip
    public_ip=$(terraform output -raw public_ip 2>/dev/null || echo "unknown")

    echo "$instance_id|$instance_type|$region|$public_ip"
}

is_validator_running() {
    local ssh_host=$1
    local ssh_key=$2

    local running
    running=$(ssh_exec "$ssh_host" "$ssh_key" \
        "pgrep -f agave-validator >/dev/null && echo 'yes' || echo 'no'")

    [[ "$running" == "yes" ]]
}

get_validator_process_info() {
    local ssh_host=$1
    local ssh_key=$2

    if ! is_validator_running "$ssh_host" "$ssh_key"; then
        echo "not_running||||"
        return 0
    fi

    local pid
    pid=$(ssh_exec "$ssh_host" "$ssh_key" "pgrep -f agave-validator" || echo "unknown")

    local uptime
    uptime=$(ssh_exec "$ssh_host" "$ssh_key" \
        "ps -p $pid -o etime= 2>/dev/null | tr -d ' '" || echo "unknown")

    local cpu
    cpu=$(ssh_exec "$ssh_host" "$ssh_key" \
        "ps -p $pid -o %cpu= 2>/dev/null | tr -d ' '" || echo "unknown")

    local mem
    mem=$(ssh_exec "$ssh_host" "$ssh_key" \
        "ps -p $pid -o %mem= 2>/dev/null | tr -d ' '" || echo "unknown")

    echo "running|$pid|$uptime|$cpu|$mem"
}

get_vote_account_status() {
    local ssh_host=$1
    local ssh_key=$2

    local vote_info
    vote_info=$(ssh_exec "$ssh_host" "$ssh_key" \
        "export PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\" && \
         solana vote-account \$(solana-keygen pubkey ~/validator/keys/vote-account-keypair.json) 2>&1" || echo "")

    if [[ -z "$vote_info" ]]; then
        echo "unknown|0|0|0"
        return 0
    fi

    local balance
    balance=$(echo "$vote_info" | grep "Account Balance:" | awk '{print $3}' || echo "0")

    local credits
    credits=$(echo "$vote_info" | grep "^Credits:" | awk '{print $2}' || echo "0")

    local commission
    commission=$(echo "$vote_info" | grep "Commission:" | awk '{print $2}' || echo "0")

    local root_slot
    root_slot=$(echo "$vote_info" | grep "Root Slot:" | awk '{print $3}' || echo "0")

    echo "$balance|$credits|$commission|$root_slot"
}

get_rpc_status() {
    local ssh_host=$1
    local ssh_key=$2

    local health
    health=$(ssh_exec "$ssh_host" "$ssh_key" \
        "curl -s -X POST -H 'Content-Type: application/json' \
         -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getHealth\"}' \
         http://localhost:8899 2>/dev/null" || echo "")

    if echo "$health" | grep -q "ok"; then
        echo "healthy"
    else
        echo "unavailable"
    fi
}

get_disk_usage() {
    local ssh_host=$1
    local ssh_key=$2

    local disk_info
    disk_info=$(ssh_exec "$ssh_host" "$ssh_key" \
        "df -h ~/validator | tail -1" || echo "")

    if [[ -z "$disk_info" ]]; then
        echo "unknown|unknown|unknown"
        return 0
    fi

    local total
    total=$(echo "$disk_info" | awk '{print $2}')

    local used
    used=$(echo "$disk_info" | awk '{print $3}')

    local percent
    percent=$(echo "$disk_info" | awk '{print $5}')

    echo "$total|$used|$percent"
}

get_log_summary() {
    local ssh_host=$1
    local ssh_key=$2

    local latest_log
    latest_log=$(ssh_exec "$ssh_host" "$ssh_key" \
        "ls -t ~/validator/logs/*.log 2>/dev/null | head -1" || echo "")

    if [[ -z "$latest_log" ]]; then
        echo "no_logs|0|0|0"
        return 0
    fi

    local errors
    errors=$(ssh_exec "$ssh_host" "$ssh_key" \
        "grep -c ERROR $latest_log 2>/dev/null || echo 0")

    local warnings
    warnings=$(ssh_exec "$ssh_host" "$ssh_key" \
        "grep -c WARN $latest_log 2>/dev/null || echo 0")

    local lines
    lines=$(ssh_exec "$ssh_host" "$ssh_key" \
        "wc -l < $latest_log 2>/dev/null || echo 0")

    echo "$latest_log|$errors|$warnings|$lines"
}

get_network_connectivity() {
    local ssh_host=$1
    local ssh_key=$2

    # Test connectivity to key Solana/Jito endpoints
    local testnet_rpc
    testnet_rpc=$(ssh_exec "$ssh_host" "$ssh_key" \
        "timeout 3 curl -s -o /dev/null -w '%{http_code}' https://api.testnet.solana.com/health || echo '000'")

    local jito_block_engine
    jito_block_engine=$(ssh_exec "$ssh_host" "$ssh_key" \
        "timeout 3 curl -s -o /dev/null -w '%{http_code}' https://ny.testnet.block-engine.jito.wtf/api/v1/bundles || echo '000'")

    echo "$testnet_rpc|$jito_block_engine"
}

# ============================================================================
# Display Functions
# ============================================================================

display_quick_status() {
    local infra_info=$1
    local process_info=$2
    local vote_info=$3
    local rpc_status=$4
    local disk_info=$5

    # Parse info
    local instance_id
    instance_id=$(echo "$infra_info" | cut -d'|' -f1)
    local instance_type
    instance_type=$(echo "$infra_info" | cut -d'|' -f2)
    local region
    region=$(echo "$infra_info" | cut -d'|' -f3)

    local process_status
    process_status=$(echo "$process_info" | cut -d'|' -f1)
    local uptime
    uptime=$(echo "$process_info" | cut -d'|' -f3)

    local vote_balance
    vote_balance=$(echo "$vote_info" | cut -d'|' -f1)
    local vote_credits
    vote_credits=$(echo "$vote_info" | cut -d'|' -f2)

    local disk_used
    disk_used=$(echo "$disk_info" | cut -d'|' -f2)
    local disk_percent
    disk_percent=$(echo "$disk_info" | cut -d'|' -f3)

    log_section "Validator Status Overview"

    # Infrastructure
    echo "Infrastructure:"
    echo "  Instance: $instance_id ($instance_type)"
    echo "  Region:   $region"
    echo ""

    # Validator Process
    echo "Validator:"
    if [[ "$process_status" == "running" ]]; then
        log_success "  Status:   RUNNING (uptime: $uptime)"
    else
        log_error "  Status:   NOT RUNNING"
    fi
    echo ""

    # Vote Account
    echo "Vote Account:"
    echo "  Balance:  $vote_balance SOL"
    echo "  Credits:  $vote_credits"
    echo ""

    # RPC
    echo "RPC:"
    if [[ "$rpc_status" == "healthy" ]]; then
        log_success "  Status:   HEALTHY"
    else
        log_warn "  Status:   UNAVAILABLE"
    fi
    echo ""

    # Disk
    echo "Disk Usage:"
    echo "  Used:     $disk_used ($disk_percent)"
    echo ""

    log_info "For detailed status, run: $0 --full"
}

display_full_status() {
    local ssh_host=$1
    local ssh_key=$2
    local infra_info=$3
    local process_info=$4
    local vote_info=$5
    local rpc_status=$6
    local disk_info=$7
    local log_info=$8
    local network_info=$9

    # Parse infrastructure info
    local instance_id
    instance_id=$(echo "$infra_info" | cut -d'|' -f1)
    local instance_type
    instance_type=$(echo "$infra_info" | cut -d'|' -f2)
    local region
    region=$(echo "$infra_info" | cut -d'|' -f3)
    local public_ip
    public_ip=$(echo "$infra_info" | cut -d'|' -f4)

    # Parse process info
    local process_status
    process_status=$(echo "$process_info" | cut -d'|' -f1)
    local pid
    pid=$(echo "$process_info" | cut -d'|' -f2)
    local uptime
    uptime=$(echo "$process_info" | cut -d'|' -f3)
    local cpu
    cpu=$(echo "$process_info" | cut -d'|' -f4)
    local mem
    mem=$(echo "$process_info" | cut -d'|' -f5)

    # Parse vote info
    local vote_balance
    vote_balance=$(echo "$vote_info" | cut -d'|' -f1)
    local vote_credits
    vote_credits=$(echo "$vote_info" | cut -d'|' -f2)
    local vote_commission
    vote_commission=$(echo "$vote_info" | cut -d'|' -f3)
    local root_slot
    root_slot=$(echo "$vote_info" | cut -d'|' -f4)

    # Parse disk info
    local disk_total
    disk_total=$(echo "$disk_info" | cut -d'|' -f1)
    local disk_used
    disk_used=$(echo "$disk_info" | cut -d'|' -f2)
    local disk_percent
    disk_percent=$(echo "$disk_info" | cut -d'|' -f3)

    # Parse log info
    local latest_log
    latest_log=$(echo "$log_info" | cut -d'|' -f1)
    local log_errors
    log_errors=$(echo "$log_info" | cut -d'|' -f2)
    local log_warnings
    log_warnings=$(echo "$log_info" | cut -d'|' -f3)
    local log_lines
    log_lines=$(echo "$log_info" | cut -d'|' -f4)

    # Parse network info
    local testnet_status
    testnet_status=$(echo "$network_info" | cut -d'|' -f1)
    local jito_status
    jito_status=$(echo "$network_info" | cut -d'|' -f2)

    log_section "Comprehensive Validator Status"

    # Infrastructure Status
    echo ""
    log_subsection "Infrastructure"
    echo "  Instance ID:     $instance_id"
    echo "  Instance Type:   $instance_type"
    echo "  Region:          $region"
    echo "  Public IP:       $public_ip"

    # Validator Process Status
    echo ""
    log_subsection "Validator Process"
    if [[ "$process_status" == "running" ]]; then
        log_success "  Status:          RUNNING"
        echo "  Process ID:      $pid"
        echo "  Uptime:          $uptime"
        echo "  CPU Usage:       ${cpu}%"
        echo "  Memory Usage:    ${mem}%"
    else
        log_error "  Status:          NOT RUNNING"
    fi

    # Vote Account Status
    echo ""
    log_subsection "Vote Account"
    echo "  Balance:         $vote_balance SOL"
    echo "  Credits:         $vote_credits"
    echo "  Commission:      $vote_commission"
    echo "  Root Slot:       $root_slot"

    # RPC Status
    echo ""
    log_subsection "RPC Endpoint"
    if [[ "$rpc_status" == "healthy" ]]; then
        log_success "  Status:          HEALTHY"
        echo "  Endpoint:        http://${public_ip}:8899"
    else
        log_warn "  Status:          UNAVAILABLE (may be catching up)"
        echo "  Endpoint:        http://${public_ip}:8899"
    fi

    # Network Connectivity
    echo ""
    log_subsection "Network Connectivity"
    if [[ "$testnet_status" == "200" ]]; then
        log_success "  Testnet RPC:     CONNECTED"
    else
        log_warn "  Testnet RPC:     ISSUES (HTTP $testnet_status)"
    fi

    if [[ "$jito_status" == "200" ]] || [[ "$jito_status" == "405" ]]; then
        log_success "  Jito Block Eng:  REACHABLE"
    else
        log_warn "  Jito Block Eng:  ISSUES (HTTP $jito_status)"
    fi

    # Disk Usage
    echo ""
    log_subsection "Disk Usage"
    echo "  Total:           $disk_total"
    echo "  Used:            $disk_used"
    echo "  Percentage:      $disk_percent"

    # Log Analysis
    echo ""
    log_subsection "Recent Logs"
    if [[ "$latest_log" != "no_logs" ]]; then
        echo "  Latest Log:      $(basename "$latest_log")"
        echo "  Total Lines:     $log_lines"
        echo "  Warnings:        $log_warnings"
        echo "  Errors:          $log_errors"
    else
        log_warn "  No log files found"
    fi

    # Quick Actions
    echo ""
    log_subsection "Quick Actions"
    echo "  View logs:       ./scripts/validator/launch.sh logs --follow"
    echo "  Check health:    ./scripts/validator/launch.sh health"
    echo "  Stop validator:  ./scripts/validator/launch.sh stop"
    echo "  Start validator: ./scripts/validator/launch.sh start"
}

# ============================================================================
# Main Function
# ============================================================================

collect_and_display_status() {
    # Get SSH connection info
    local connection_info
    connection_info=$(get_ssh_connection_info)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to get SSH connection info"
        return 1
    fi

    local ssh_host
    ssh_host=$(echo "$connection_info" | cut -d'|' -f1)

    local ssh_key
    ssh_key=$(echo "$connection_info" | cut -d'|' -f2)

    # Test SSH connection
    if ! ssh_exec "$ssh_host" "$ssh_key" "echo test" >/dev/null 2>&1; then
        log_error "Cannot connect to remote instance: $ssh_host"
        return 1
    fi

    # Collect status information
    log_info "Collecting status information..."

    local infra_info
    infra_info=$(get_infrastructure_status)

    local process_info
    process_info=$(get_validator_process_info "$ssh_host" "$ssh_key")

    local vote_info
    vote_info=$(get_vote_account_status "$ssh_host" "$ssh_key")

    local rpc_status
    rpc_status=$(get_rpc_status "$ssh_host" "$ssh_key")

    local disk_info
    disk_info=$(get_disk_usage "$ssh_host" "$ssh_key")

    # Display status based on mode
    if [[ "$MODE" == "quick" ]]; then
        display_quick_status "$infra_info" "$process_info" "$vote_info" "$rpc_status" "$disk_info"
    else
        local log_info
        log_info=$(get_log_summary "$ssh_host" "$ssh_key")

        local network_info
        network_info=$(get_network_connectivity "$ssh_host" "$ssh_key")

        display_full_status "$ssh_host" "$ssh_key" "$infra_info" "$process_info" \
            "$vote_info" "$rpc_status" "$disk_info" "$log_info" "$network_info"
    fi
}

main() {
    print_banner

    # Parse arguments
    parse_args "$@"

    if [[ "$WATCH_MODE" == true ]]; then
        log_info "Starting continuous monitoring (refresh every ${WATCH_INTERVAL}s)"
        log_info "Press Ctrl+C to exit"
        echo ""

        while true; do
            clear
            print_banner
            collect_and_display_status
            sleep "$WATCH_INTERVAL"
        done
    else
        collect_and_display_status
    fi

    exit 0
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
