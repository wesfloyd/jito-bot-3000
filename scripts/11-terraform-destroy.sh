#!/usr/bin/env bash
# Script 11: Terraform Destroy
# Destroys Terraform infrastructure to clean up resources

set -euo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=scripts/lib/terraform-helpers.sh
source "${SCRIPT_DIR}/lib/terraform-helpers.sh"

# ============================================================================
# Main Function
# ============================================================================

main() {
    print_banner

    log_section "Terraform Destroy"

    # Check if Terraform state exists
    if ! terraform_status >/dev/null 2>&1; then
        log_warn "No Terraform state found"
        log_info "Nothing to destroy"
        exit 0
    fi

    # Show current resources
    show_current_resources

    # Show cost information
    show_cost_information

    # Confirm destruction
    if ! prompt_confirmation "Are you sure you want to destroy ALL infrastructure?"; then
        log_info "Destruction cancelled by user"
        exit 0
    fi

    # Destroy infrastructure
    if ! terraform_destroy; then
        log_error "Failed to destroy Terraform infrastructure"
        exit 1
    fi

    # Cleanup local files
    cleanup_local_files

    log_success "Infrastructure destruction complete!"
    log_info ""
    log_info "All AWS resources have been destroyed."
    log_info "Local files have been cleaned up."
    log_info ""
}

# ============================================================================
# Current Resources
# ============================================================================

show_current_resources() {
    log_section "Current Resources"

    local terraform_dir
    terraform_dir=$(get_terraform_dir)
    
    cd "$terraform_dir" || return 1

    log_info "Resources that will be destroyed:"
    terraform show -json | jq -r '.values.root_module.resources[]? | select(.type == "aws_instance") | "  - " + .values.tags.Name + " (" + .values.id + ")"' 2>/dev/null || log_info "  No resources found"
    
    echo ""
}

# ============================================================================
# Cost Information
# ============================================================================

show_cost_information() {
    log_section "Cost Information"

    local terraform_dir
    terraform_dir=$(get_terraform_dir)
    
    cd "$terraform_dir" || return 1

    # Get instance information
    local instance_id
    instance_id=$(terraform output -raw instance_id 2>/dev/null || echo "")

    if [[ -n "$instance_id" ]]; then
        # Get instance launch time
        local launch_time
        launch_time=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].LaunchTime' \
            --output text 2>/dev/null || echo "")

        if [[ -n "$launch_time" ]]; then
            # Calculate uptime
            local launch_epoch
            launch_epoch=$(date -d "$launch_time" +%s)
            local current_epoch
            current_epoch=$(date +%s)
            local uptime_seconds=$((current_epoch - launch_epoch))
            local uptime_hours=$((uptime_seconds / 3600))

            log_info "Instance uptime: ${uptime_hours} hours"

            # Estimate costs
            local instance_type
            instance_type=$(terraform output -raw instance_type 2>/dev/null || echo "unknown")
            
            local hourly_cost=0
            case "$instance_type" in
                m7i.4xlarge)
                    hourly_cost=0.8064
                    ;;
                m7i.2xlarge)
                    hourly_cost=0.4032
                    ;;
                m7i-flex.4xlarge)
                    hourly_cost=0.65
                    ;;
                *)
                    hourly_cost=0.5
                    ;;
            esac

            local total_cost
            total_cost=$(echo "$hourly_cost * $uptime_hours" | bc -l)
            
            printf "  ${BOLD}Total compute cost:${RESET} ${YELLOW}\$%.2f${RESET}\n" "$total_cost"
            echo ""
            
            local savings_per_hour
            savings_per_hour=$(echo "$hourly_cost * 24" | bc -l)
            printf "  ${BOLD}Daily savings:${RESET} ${GREEN}\$%.2f${RESET}\n" "$savings_per_hour"
            echo ""
        fi
    fi
}

# ============================================================================
# Cleanup Local Files
# ============================================================================

cleanup_local_files() {
    log_section "Cleaning Up Local Files"

    # Remove deployment state file
    if [[ -f "deployment.state" ]]; then
        rm -f deployment.state
        log_info "Removed deployment.state"
    fi

    # Cleanup Terraform files
    terraform_cleanup

    # Remove logs (optional)
    if prompt_confirmation "Do you want to remove log files?"; then
        rm -rf logs/
        log_info "Removed log files"
    fi

    log_success "Local cleanup complete"
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
