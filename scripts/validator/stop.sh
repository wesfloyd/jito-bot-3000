#!/usr/bin/env bash
# Stop Validator Instance
# Stops the Terraform-managed EC2 instance to save costs (preserves EBS volumes)

set -euo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/utils/lib/common.sh
source "${SCRIPT_DIR}/../utils/lib/common.sh"
# shellcheck source=scripts/utils/lib/terraform-helpers.sh
source "${SCRIPT_DIR}/../utils/lib/terraform-helpers.sh"

# ============================================================================
# Main Function
# ============================================================================

main() {
    print_banner

    log_section "Stop Validator Instance"

    # Check if Terraform state exists
    if ! terraform_status >/dev/null 2>&1; then
        log_error "No Terraform state found"
        log_info "Have you run ./scripts/infra/deploy.sh yet?"
        exit 1
    fi

    # Get instance information from Terraform
    local instance_id
    instance_id=$(get_terraform_output "instance_id" 2>/dev/null || echo "")
    local region
    region=$(get_terraform_output "region" 2>/dev/null || echo "")

    if [[ -z "$instance_id" ]]; then
        log_error "No instance ID found in Terraform state"
        exit 1
    fi

    log_info "Instance ID: $instance_id"
    log_info "Region: $region"

    # Check current status from Terraform
    local current_status
    current_status=$(get_terraform_output "instance_state" 2>/dev/null || echo "unknown")
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
    log_info "Stopping instance: $instance_id"
    if ! aws ec2 stop-instances --region "$region" --instance-ids "$instance_id" >/dev/null; then
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
    instance_type=$(get_terraform_output "instance_type" 2>/dev/null || echo "m7i.4xlarge")
    local hourly_cost="0.81"  # Approximate cost for m7i.4xlarge

    echo "${BOLD}Stopping will save:${RESET}"
    echo ""
    printf "  ${GREEN}\$%.2f per hour${RESET}\n" "$hourly_cost"
    printf "  ${GREEN}\$%.2f per day${RESET}\n" "$(echo "$hourly_cost * 24" | bc -l)"
    echo ""
    echo "  ${CYAN}Note: EBS storage charges continue (~\$163.84/month)${RESET}"
    echo ""
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
