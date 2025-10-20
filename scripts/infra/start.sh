#!/usr/bin/env bash
# Script 13: Terraform Start
# Starts stopped Terraform-managed EC2 instances

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

    log_section "Terraform Start"

    # Check if Terraform state exists
    if ! terraform_status >/dev/null 2>&1; then
        log_warn "No Terraform state found"
        log_info "Use ./scripts/infra/deploy.sh to create infrastructure"
        exit 0
    fi

    # Get current instance information
    local instance_id
    instance_id=$(get_terraform_output "instance_id" 2>/dev/null || echo "")

    if [[ -z "$instance_id" ]]; then
        log_warn "No instance found in Terraform state"
        log_info "Use ./scripts/infra/deploy.sh to create infrastructure"
        exit 0
    fi

    # Check current instance state from Terraform
    local current_state
    current_state=$(get_terraform_output "instance_state" 2>/dev/null || echo "unknown")

    log_info "Instance ID: $instance_id"
    log_info "Current state: $current_state"

    case "$current_state" in
        "running")
            log_info "Instance is already running"
            log_success "Nothing to do - instance is already running"
            show_running_status
            exit 0
            ;;
        "starting")
            log_info "Instance is already starting"
            log_info "Please wait for the start operation to complete"
            exit 0
            ;;
        "stopped")
            # Show cost information before starting
            show_start_cost_info
            
            # Confirm before starting
            if [[ "${AUTO_CONFIRM:-}" != "true" ]]; then
                if ! prompt_confirmation "Start the instance (will resume compute costs)?"; then
                    log_info "Start cancelled by user"
                    exit 0
                fi
            else
                log_info "Auto-confirm enabled, proceeding with start..."
            fi

            # Start the instance
            log_info "Starting instance: $instance_id"
            local aws_region
            aws_region=$(get_terraform_output "region" 2>/dev/null || echo "us-west-1")
            if aws ec2 start-instances --region "$aws_region" --instance-ids "$instance_id" >/dev/null; then
                log_success "Instance start initiated successfully"
                log_info "Instance will start in a few moments"
                
                # Wait for instance to start
                log_info "Waiting for instance to start..."
                aws ec2 wait instance-running --region "$aws_region" --instance-ids "$instance_id"
                log_success "Instance started successfully"
                
                # Get updated instance information
                show_running_status
            else
                log_error "Failed to start instance"
                exit 1
            fi
            ;;
        "terminated")
            log_error "Instance is terminated and cannot be started"
            log_info "Use ./scripts/infra/deploy.sh to recreate infrastructure"
            exit 1
            ;;
        *)
            log_error "Unknown instance state: $current_state"
            exit 1
            ;;
    esac
}

# ============================================================================
# Helper Functions
# ============================================================================

show_start_cost_info() {
    log_info "Cost Information:"
    log_info "  Starting instance will resume compute costs (~$0.81/hour)"
    log_info "  Auto-stop is configured for 8 hours"
    log_info "  Use ./scripts/infra/stop.sh to stop and save costs"
}

show_running_status() {
    local instance_id
    instance_id=$(get_terraform_output "instance_id" 2>/dev/null || echo "")

    if [[ -n "$instance_id" ]]; then
        # Get fresh instance information
        local public_ip
        local private_ip
        local ssh_command
        
        public_ip=$(get_terraform_output "public_ip" 2>/dev/null || echo "unknown")
        private_ip=$(get_terraform_output "private_ip" 2>/dev/null || echo "unknown")

        log_section "Instance Status"
        log_info "Instance ID: $instance_id"
        log_info "Public IP: $public_ip"
        log_info "Private IP: $private_ip"
        log_info "State: running"
        
        if [[ "$public_ip" != "unknown" && "$public_ip" != "None" ]]; then
            log_success "Instance is running and accessible"
            log_info ""
            log_info "SSH Connection:"
            log_info "  ssh -i keys/jito-validator-key.pem ubuntu@$public_ip"
            log_info ""
            log_info "To stop the instance:"
            log_info "  ./scripts/infra/stop.sh"
            log_info ""
            log_info "To completely destroy infrastructure:"
            log_info "  ./scripts/infra/destroy.sh"
        fi
    fi
}

# ============================================================================
# Script Execution
# ============================================================================

# Run main function
main "$@"
