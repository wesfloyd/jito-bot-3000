#!/usr/bin/env bash
# Stop Validator Instance
# Stops the EC2 instance to save costs (preserves EBS volumes)

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

    log_section "Stop Validator Instance"

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

    if [[ -z "$instance_id" ]]; then
        log_error "No instance ID found in deployment state"
        exit 1
    fi

    log_info "Instance ID: $instance_id"
    log_info "Region: $region"

    # Check current status
    local current_status
    current_status=$(get_instance_status "$instance_id" "$region")
    log_info "Current status: $current_status"

    if [[ "$current_status" == "stopped" ]]; then
        log_warn "Instance is already stopped"
        exit 0
    fi

    if [[ "$current_status" == "stopping" ]]; then
        log_info "Instance is already stopping"
        exit 0
    fi

    if [[ "$current_status" == "terminated" ]]; then
        log_error "Instance has been terminated"
        exit 1
    fi

    # Show cost savings
    show_cost_savings "$instance_id" "$region"

    # Confirm action
    if ! prompt_confirmation "Stop the validator instance?"; then
        log_info "Stop cancelled by user"
        exit 0
    fi

    # Stop instance
    if ! stop_instance "$instance_id" "$region"; then
        log_error "Failed to stop instance"
        exit 1
    fi

    log_success "Instance is stopping"
    log_info ""
    log_info "The instance will stop in 1-2 minutes"
    log_info "Your data (ledger, accounts) is preserved on the EBS volume"
    log_info ""
    log_info "To restart the instance:"
    log_info "  ./scripts/start-validator.sh"
    log_info ""
    log_info "Note: You still pay for EBS storage while instance is stopped (~\$200/month)"
    log_info ""
}

# ============================================================================
# Cost Savings Display
# ============================================================================

show_cost_savings() {
    local instance_id=$1
    local region=$2

    log_section "Cost Information"

    # Get instance type
    local instance_type
    instance_type=$(get_state "aws.instance_type")

    # Get uptime
    local uptime_hours
    uptime_hours=$(get_instance_uptime "$instance_id" "$region")

    # Calculate costs
    local total_cost
    total_cost=$(estimate_instance_cost "$instance_type" "$uptime_hours")

    echo "${BOLD}Current Session:${RESET}"
    echo ""
    echo "  Uptime: ${uptime_hours} hours"
    printf "  Cost so far: ${YELLOW}\$%.2f${RESET}\n" "$total_cost"
    echo ""

    # Hourly rate
    local hourly_cost
    hourly_cost=$(estimate_instance_cost "$instance_type" 1)

    echo "${BOLD}Stopping will save:${RESET}"
    echo ""
    printf "  ${GREEN}\$%.2f per hour${RESET}\n" "$hourly_cost"
    printf "  ${GREEN}\$%.2f per day${RESET}\n" "$(echo "$hourly_cost * 24" | bc -l)"
    echo ""
    echo "  ${CYAN}Note: EBS storage charges continue (~\$200/month)${RESET}"
    echo ""
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
