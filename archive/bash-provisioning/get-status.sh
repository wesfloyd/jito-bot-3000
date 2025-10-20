#!/usr/bin/env bash
# Get Validator Status
# Shows instance status, uptime, costs, and connection info

set -euo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=scripts/lib/aws-helpers.sh
source "${SCRIPT_DIR}/lib/aws-helpers.sh"

# ============================================================================
# Main Function
# ============================================================================

main() {
    print_banner

    log_section "Validator Status"

    # Check if deployment state exists
    if [[ ! -f "$STATE_FILE" ]]; then
        log_error "Deployment state not found: $STATE_FILE"
        log_info "Have you run ./scripts/01-provision-aws.sh yet?"
        exit 1
    fi

    # Load state
    local instance_id
    instance_id=$(get_state "aws.instance_id")
    local region
    region=$(get_state "aws.region")
    local public_ip
    public_ip=$(get_state "aws.public_ip")

    if [[ -z "$instance_id" ]]; then
        log_error "No instance ID found in deployment state"
        exit 1
    fi

    # Display status sections
    show_instance_status "$instance_id" "$region" "$public_ip"
    show_cost_information "$instance_id" "$region"
    show_connection_info "$public_ip"
    show_auto_stop_info "$instance_id" "$region"
    show_control_commands

    log_info ""
}

# ============================================================================
# Instance Status
# ============================================================================

show_instance_status() {
    local instance_id=$1
    local region=$2
    local public_ip=$3

    log_section "Instance Status"

    local status
    status=$(get_instance_status "$instance_id" "$region")

    local instance_type
    instance_type=$(get_state "aws.instance_type")

    # Color code the status
    local status_color=""
    case "$status" in
        running)
            status_color="${GREEN}RUNNING${RESET}"
            ;;
        stopped)
            status_color="${YELLOW}STOPPED${RESET}"
            ;;
        stopping|pending)
            status_color="${YELLOW}${status^^}${RESET}"
            ;;
        terminated)
            status_color="${RED}TERMINATED${RESET}"
            ;;
        *)
            status_color="${GRAY}${status^^}${RESET}"
            ;;
    esac

    echo "${BOLD}AWS Instance:${RESET}"
    echo ""
    echo "  Instance ID:   $instance_id"
    echo "  Status:        $status_color"
    echo "  Instance Type: $instance_type"
    echo "  Region:        $region"

    if [[ "$status" == "running" ]]; then
        echo "  Public IP:     ${CYAN}$public_ip${RESET}"
    else
        echo "  Public IP:     ${GRAY}(unavailable when stopped)${RESET}"
    fi
    echo ""
}

# ============================================================================
# Cost Information
# ============================================================================

show_cost_information() {
    local instance_id=$1
    local region=$2

    log_section "Cost Information"

    local instance_type
    instance_type=$(get_state "aws.instance_type")

    local status
    status=$(get_instance_status "$instance_id" "$region")

    # Get deployment timestamp
    local deploy_time
    deploy_time=$(get_state "deployment.timestamp")

    # Calculate uptime
    local uptime_hours
    uptime_hours=$(get_instance_uptime "$instance_id" "$region")

    # Hourly and total costs
    local hourly_cost
    hourly_cost=$(estimate_instance_cost "$instance_type" 1)
    local total_compute_cost
    total_compute_cost=$(estimate_instance_cost "$instance_type" "$uptime_hours")

    # Storage cost (rough estimate)
    local storage_monthly=200
    local hours_since_deploy=0
    if [[ -n "$deploy_time" ]]; then
        local deploy_epoch
        deploy_epoch=$(date -d "$deploy_time" +%s 2>/dev/null || echo "0")
        local current_epoch
        current_epoch=$(date +%s)
        hours_since_deploy=$(( (current_epoch - deploy_epoch) / 3600 ))
    fi

    local storage_hourly
    storage_hourly=$(echo "$storage_monthly / 730" | bc -l)
    local total_storage_cost
    total_storage_cost=$(echo "$storage_hourly * $hours_since_deploy" | bc -l)

    local total_cost
    total_cost=$(echo "$total_compute_cost + $total_storage_cost" | bc -l)

    echo "${BOLD}Current Session (since deployment):${RESET}"
    echo ""
    echo "  Deployed:      $deploy_time"
    echo "  Instance uptime: ${uptime_hours} hours"
    echo ""

    echo "${BOLD}Costs:${RESET}"
    echo ""
    printf "  Compute:       ${YELLOW}\$%.2f${RESET} (${uptime_hours}h @ \$%.2f/hr)\n" "$total_compute_cost" "$hourly_cost"
    printf "  Storage:       ${YELLOW}\$%.2f${RESET} (~${hours_since_deploy}h @ \$%.2f/hr)\n" "$total_storage_cost" "$storage_hourly"
    printf "  ${BOLD}Total so far:  \$%.2f${RESET}\n" "$total_cost"
    echo ""

    if [[ "$status" == "running" ]]; then
        local daily_cost
        daily_cost=$(echo "$hourly_cost * 24" | bc -l)
        printf "  ${CYAN}Currently accruing: \$%.2f/hour (\$%.2f/day)${RESET}\n" "$hourly_cost" "$daily_cost"
        echo ""
    else
        printf "  ${GREEN}Instance stopped - only storage costs (\$%.2f/hr)${RESET}\n" "$storage_hourly"
        echo ""
    fi
}

# ============================================================================
# Connection Info
# ============================================================================

show_connection_info() {
    local public_ip=$1

    local status
    local instance_id
    instance_id=$(get_state "aws.instance_id")
    local region
    region=$(get_state "aws.region")
    status=$(get_instance_status "$instance_id" "$region")

    log_section "Connection"

    if [[ "$status" != "running" ]]; then
        echo "${YELLOW}Instance is not running - no connection available${RESET}"
        echo ""
        echo "Start the instance with: ./scripts/start-validator.sh"
        echo ""
        return
    fi

    local ssh_key_file
    ssh_key_file=$(get_state "aws.ssh_key_file")
    local ssh_user="${SSH_USER:-ubuntu}"

    echo "${BOLD}SSH Command:${RESET}"
    echo ""
    echo "  ${CYAN}ssh -i $ssh_key_file ${ssh_user}@${public_ip}${RESET}"
    echo ""

    # Show validator status if deployed
    local validator_deployed
    validator_deployed=$(get_state "validator.deployed" "false")

    if [[ "$validator_deployed" == "true" ]]; then
        echo "${BOLD}Check Validator:${RESET}"
        echo ""
        echo "  Status:  ssh -i $ssh_key_file ${ssh_user}@${public_ip} 'sudo systemctl status jito-validator'"
        echo "  Logs:    ssh -i $ssh_key_file ${ssh_user}@${public_ip} 'tail -f /home/sol/jito-validator.log'"
        echo ""
    fi
}

# ============================================================================
# Auto-Stop Info
# ============================================================================

show_auto_stop_info() {
    local instance_id=$1
    local region=$2

    # Get auto-stop time from AWS tags
    local stop_time
    stop_time=$(aws ec2 describe-tags \
        --filters \
            "Name=resource-id,Values=$instance_id" \
            "Name=key,Values=AutoStopTime" \
        --region "$region" \
        --query 'Tags[0].Value' \
        --output text 2>/dev/null || echo "")

    if [[ -z "$stop_time" || "$stop_time" == "None" ]]; then
        return
    fi

    log_section "Auto-Stop"

    local current_time
    current_time=$(date -u '+%Y-%m-%dT%H:%M:%S')

    echo "${BOLD}Scheduled Stop Time:${RESET}"
    echo ""
    echo "  ${YELLOW}$stop_time UTC${RESET}"
    echo ""

    # Check if past stop time
    if [[ "$current_time" > "$stop_time" ]]; then
        echo "  ${RED}⚠ Auto-stop time has passed!${RESET}"
        echo "  Consider stopping the instance to save costs"
        echo ""
    else
        # Calculate time remaining
        local stop_epoch
        stop_epoch=$(date -d "$stop_time" +%s 2>/dev/null || echo "0")
        local current_epoch
        current_epoch=$(date -u +%s)
        local remaining_seconds=$((stop_epoch - current_epoch))
        local remaining_hours=$((remaining_seconds / 3600))

        if [[ $remaining_hours -gt 0 ]]; then
            echo "  Time remaining: ~${remaining_hours} hours"
            echo ""
        fi
    fi
}

# ============================================================================
# Control Commands
# ============================================================================

show_control_commands() {
    log_section "Control Commands"

    local status
    local instance_id
    instance_id=$(get_state "aws.instance_id")
    local region
    region=$(get_state "aws.region")
    status=$(get_instance_status "$instance_id" "$region")

    echo "${BOLD}Available Commands:${RESET}"
    echo ""

    if [[ "$status" == "running" ]]; then
        echo "  ${CYAN}./scripts/stop-validator.sh${RESET}"
        echo "    Stop instance to save costs"
        echo ""
    elif [[ "$status" == "stopped" ]]; then
        echo "  ${CYAN}./scripts/start-validator.sh${RESET}"
        echo "    Start the stopped instance"
        echo ""
    fi

    echo "  ${CYAN}./scripts/get-status.sh${RESET}"
    echo "    Refresh this status display"
    echo ""

    # Show next deployment step if applicable
    local validator_deployed
    validator_deployed=$(get_state "validator.deployed" "false")

    if [[ "$validator_deployed" != "true" ]]; then
        echo "  ${BOLD}Next Deployment Step:${RESET}"
        echo ""
        echo "  ${CYAN}./scripts/02-generate-keys.sh${RESET}"
        echo "    Generate Solana keypairs"
        echo ""
    fi
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
