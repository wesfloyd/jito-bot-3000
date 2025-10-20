#!/usr/bin/env bash
# Script 12: Terraform Stop
# Stops Terraform-managed EC2 instances without destroying infrastructure

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

    log_section "Terraform Stop"

    # Check if Terraform state exists
    if ! terraform_status >/dev/null 2>&1; then
        log_warn "No Terraform state found"
        log_info "Nothing to stop"
        exit 0
    fi

    # Get current instance information
    local instance_id
    instance_id=$(get_terraform_output "instance_id" 2>/dev/null || echo "")

    if [[ -z "$instance_id" ]]; then
        log_warn "No instance found in Terraform state"
        log_info "Nothing to stop"
        exit 0
    fi

    # Check current instance state
    local current_state
    current_state=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "unknown")

    log_info "Instance ID: $instance_id"
    log_info "Current state: $current_state"

    case "$current_state" in
        "stopped")
            log_info "Instance is already stopped"
            log_success "Nothing to do - instance is already stopped"
            exit 0
            ;;
        "stopping")
            log_info "Instance is already stopping"
            log_info "Please wait for the stop operation to complete"
            exit 0
            ;;
        "terminated")
            log_warn "Instance is terminated"
            log_info "Cannot stop a terminated instance"
            exit 0
            ;;
        "running")
            # Show cost information before stopping
            show_stop_cost_savings
            
            # Confirm before stopping
            if [[ "${AUTO_CONFIRM:-}" != "true" ]]; then
                if ! prompt_confirmation "Stop the instance to save compute costs?"; then
                    log_info "Stop cancelled by user"
                    exit 0
                fi
            else
                log_info "Auto-confirm enabled, proceeding with stop..."
            fi

            # Stop the instance
            log_info "Stopping instance: $instance_id"
            if aws ec2 stop-instances --instance-ids "$instance_id" >/dev/null; then
                log_success "Instance stop initiated successfully"
                log_info "Instance will stop in a few moments"
                
                # Wait for instance to stop
                log_info "Waiting for instance to stop..."
                aws ec2 wait instance-stopped --instance-ids "$instance_id"
                log_success "Instance stopped successfully"
            else
                log_error "Failed to stop instance"
                exit 1
            fi
            ;;
        *)
            log_error "Unknown instance state: $current_state"
            exit 1
            ;;
    esac

    # Show status after stop
    show_stop_status
}

# ============================================================================
# Helper Functions
# ============================================================================

show_stop_cost_savings() {
    log_info "Cost Savings Information:"
    log_info "  Instance will stop - compute costs will stop immediately"
    log_info "  Storage costs will continue (~$163.84/month for 2TB)"
    log_info "  Use ./scripts/13-terraform-start.sh to restart"
    log_info "  Use ./scripts/11-terraform-destroy.sh to completely remove"
}

show_stop_status() {
    local instance_id
    instance_id=$(get_terraform_output "instance_id" 2>/dev/null || echo "")

    if [[ -n "$instance_id" ]]; then
        local current_state
        current_state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "unknown")

        log_section "Instance Status"
        log_info "Instance ID: $instance_id"
        log_info "State: $current_state"
        
        if [[ "$current_state" == "stopped" ]]; then
            log_success "Instance is stopped and not incurring compute costs"
            log_info ""
            log_info "To restart the instance:"
            log_info "  ./scripts/13-terraform-start.sh"
            log_info ""
            log_info "To completely destroy infrastructure:"
            log_info "  ./scripts/11-terraform-destroy.sh"
        fi
    fi
}

# ============================================================================
# Script Execution
# ============================================================================

# Run main function
main "$@"
