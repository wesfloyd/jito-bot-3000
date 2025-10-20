#!/usr/bin/env bash
# Script 03: Terraform Apply
# Applies Terraform configuration to create infrastructure

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

    log_section "Terraform Apply"

    # Check if plan exists
    local terraform_dir
    terraform_dir=$(get_terraform_dir)
    
    if [[ ! -f "$terraform_dir/tfplan" ]]; then
        log_warn "No Terraform plan found"
        log_info "Creating plan first..."
        
        if ! terraform_plan; then
            log_error "Failed to create Terraform plan"
            exit 1
        fi
    fi

    # Show cost warning
    show_cost_warning

    # Confirm before applying (unless AUTO_CONFIRM is set)
    if [[ "${AUTO_CONFIRM:-}" != "true" ]]; then
        if ! prompt_confirmation "Do you want to apply the Terraform configuration?"; then
            log_info "Apply cancelled by user"
            exit 0
        fi
    else
        log_info "Auto-confirm enabled, proceeding with apply..."
    fi

    # Apply Terraform configuration
    if ! terraform_apply; then
        log_error "Failed to apply Terraform configuration"
        exit 1
    fi

    # Display deployment summary
    display_deployment_summary

    log_success "Infrastructure provisioning complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Wait 2-3 minutes for instance initialization"
    log_info "  2. Run: ./scripts/utils/setup/ssh-keys.sh"
    log_info "  3. Check status: ./scripts/infra/status.sh"
    log_info ""
}

# ============================================================================
# Cost Warning
# ============================================================================

show_cost_warning() {
    log_section "Cost Warning"

    local terraform_dir
    terraform_dir=$(get_terraform_dir)
    
    # Read variables from tfvars
    local instance_type
    instance_type=$(grep "instance_type" "$terraform_dir/terraform.tfvars" | cut -d'"' -f2)
    local volume_size
    volume_size=$(grep "volume_size" "$terraform_dir/terraform.tfvars" | cut -d'=' -f2 | tr -d ' ')
    local auto_stop_hours
    auto_stop_hours=$(grep "auto_stop_hours" "$terraform_dir/terraform.tfvars" | cut -d'=' -f2 | tr -d ' ')

    log_warn "You are about to create AWS resources that will incur costs:"
    echo ""
    echo "  ${BOLD}Instance:${RESET} $instance_type"
    echo "  ${BOLD}Storage:${RESET} ${volume_size}GB gp3"
    echo ""

    # Calculate costs
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

    local daily_cost
    daily_cost=$(echo "$hourly_cost * 24" | bc -l)
    local monthly_cost
    monthly_cost=$(echo "$hourly_cost * 730" | bc -l)

    echo "  ${BOLD}Estimated Costs:${RESET}"
    printf "    Per hour:  ${YELLOW}\$%.2f${RESET}\n" "$hourly_cost"
    printf "    Per day:   ${YELLOW}\$%.2f${RESET}\n" "$daily_cost"
    printf "    Per month: ${YELLOW}\$%.2f${RESET}\n" "$monthly_cost"
    echo ""

    # Storage costs
    local storage_monthly=$(echo "$volume_size * 0.08" | bc -l)
    printf "  ${BOLD}Storage:${RESET} ${YELLOW}\$%.2f/month${RESET}\n" "$storage_monthly"
    echo ""

    # Auto-stop reminder
    if [[ "$auto_stop_hours" -gt 0 ]]; then
        log_info "Auto-stop configured: Instance will be tagged to stop after $auto_stop_hours hours"
        local auto_stop_cost=$(echo "$hourly_cost * $auto_stop_hours" | bc -l)
        printf "  ${CYAN}Estimated cost for this session: \$%.2f${RESET}\n" "$auto_stop_cost"
        echo ""
    else
        log_warn "No auto-stop configured - remember to stop instance when done!"
        echo ""
    fi
}

# ============================================================================
# Deployment Summary
# ============================================================================

display_deployment_summary() {
    log_section "Deployment Summary"

    # Get outputs from Terraform
    local instance_id
    instance_id=$(get_instance_id)
    local public_ip
    public_ip=$(get_instance_ip)
    local ssh_command
    ssh_command=$(get_ssh_command)
    local ssh_key_file
    ssh_key_file=$(get_ssh_key_file)

    echo "${BOLD}AWS Resources Created:${RESET}"
    echo ""
    echo "  ${BOLD}Instance ID:${RESET} $instance_id"
    echo "  ${BOLD}Public IP:${RESET} $public_ip"
    echo "  ${BOLD}SSH Key:${RESET} $ssh_key_file"
    echo ""

    echo "${BOLD}SSH Connection:${RESET}"
    echo ""
    echo "  ${CYAN}$ssh_command${RESET}"
    echo ""

    # Save connection info to state file
    local state_file="deployment.state"
    cat > "$state_file" << EOF
{
  "deployment": {
    "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
    "method": "terraform"
  },
  "infrastructure": {
    "instance_id": "$instance_id",
    "public_ip": "$public_ip",
    "ssh_key_file": "$ssh_key_file",
    "ssh_command": "$ssh_command"
  },
  "terraform": {
    "state_file": "terraform/terraform.tfstate",
    "plan_file": "terraform/tfplan"
  }
}
EOF

    echo "${BOLD}State File:${RESET}"
    echo ""
    echo "  $state_file"
    echo ""

    # Auto-stop reminder
    local auto_stop_hours
    auto_stop_hours=$(grep "auto_stop_hours" "$(get_terraform_dir)/terraform.tfvars" | cut -d'=' -f2 | tr -d ' ')
    if [[ "$auto_stop_hours" -gt 0 ]]; then
        local stop_time
        stop_time=$(date -u -d "+${auto_stop_hours} hours" '+%Y-%m-%d %H:%M:%S UTC')
        echo "${BOLD}Auto-Stop:${RESET}"
        echo ""
        echo "  Scheduled for: ${YELLOW}$stop_time${RESET}"
        echo "  (${auto_stop_hours} hours from now)"
        echo ""
    fi
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
