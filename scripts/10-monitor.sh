#!/usr/bin/env bash
# Script 10: Monitor Infrastructure
# Shows current status of Terraform-managed infrastructure

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

    log_section "Infrastructure Status"

    # Check if Terraform state exists
    if ! terraform_status >/dev/null 2>&1; then
        log_warn "No Terraform state found"
        log_info "Run ./scripts/01-terraform-init.sh first"
        exit 0
    fi

    # Show infrastructure status
    show_infrastructure_status

    # Show cost information
    show_cost_information

    # Show connection information
    show_connection_information

    log_success "Status check complete"
}

# ============================================================================
# Infrastructure Status
# ============================================================================

show_infrastructure_status() {
    log_section "Infrastructure Status"

    local terraform_dir
    terraform_dir=$(get_terraform_dir)
    
    cd "$terraform_dir" || return 1

    # Get instance information
    local instance_id
    instance_id=$(terraform output -raw instance_id 2>/dev/null || echo "")
    local public_ip
    public_ip=$(terraform output -raw public_ip 2>/dev/null || echo "")
    local instance_type
    instance_type=$(terraform output -raw instance_type 2>/dev/null || echo "")
    local availability_zone
    availability_zone=$(terraform output -raw availability_zone 2>/dev/null || echo "")

    if [[ -n "$instance_id" ]]; then
        echo "${BOLD}Instance Information:${RESET}"
        echo ""
        echo "  ${BOLD}Instance ID:${RESET} $instance_id"
        echo "  ${BOLD}Instance Type:${RESET} $instance_type"
        echo "  ${BOLD}Public IP:${RESET} $public_ip"
        echo "  ${BOLD}Availability Zone:${RESET} $availability_zone"
        echo ""

        # Get current instance state
        local instance_state
        instance_state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "unknown")

        echo "  ${BOLD}Current State:${RESET} $instance_state"
        echo ""

        # Show auto-stop information
        local auto_stop_time
        auto_stop_time=$(terraform output -raw auto_stop_time 2>/dev/null || echo "")
        if [[ -n "$auto_stop_time" && "$auto_stop_time" != "null" ]]; then
            echo "  ${BOLD}Auto-Stop:${RESET} $auto_stop_time"
            echo ""
        fi
    else
        log_warn "No instance information available"
    fi
}

# ============================================================================
# Cost Information
# ============================================================================

show_cost_information() {
    log_section "Cost Information"

    local terraform_dir
    terraform_dir=$(get_terraform_dir)
    
    cd "$terraform_dir" || return 1

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
            local uptime_minutes=$(((uptime_seconds % 3600) / 60))

            echo "${BOLD}Uptime:${RESET} ${uptime_hours}h ${uptime_minutes}m"
            echo ""

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
            
            echo "  ${BOLD}Compute Costs:${RESET}"
            printf "    Per hour:  ${YELLOW}\$%.2f${RESET}\n" "$hourly_cost"
            printf "    Total:     ${YELLOW}\$%.2f${RESET}\n" "$total_cost"
            echo ""

            # Storage costs (estimate)
            local volume_size
            volume_size=$(grep "volume_size" terraform.tfvars | cut -d'=' -f2 | tr -d ' ')
            local storage_daily
            storage_daily=$(echo "$volume_size * 0.08 / 30" | bc -l)
            
            echo "  ${BOLD}Storage Costs:${RESET}"
            printf "    Per day:   ${YELLOW}\$%.2f${RESET}\n" "$storage_daily"
            echo ""
        fi
    fi
}

# ============================================================================
# Connection Information
# ============================================================================

show_connection_information() {
    log_section "Connection Information"

    local terraform_dir
    terraform_dir=$(get_terraform_dir)
    
    cd "$terraform_dir" || return 1

    local ssh_command
    ssh_command=$(terraform output -raw ssh_command 2>/dev/null || echo "")
    local ssh_key_file
    ssh_key_file=$(terraform output -raw ssh_key_file 2>/dev/null || echo "")

    if [[ -n "$ssh_command" ]]; then
        echo "${BOLD}SSH Connection:${RESET}"
        echo ""
        echo "  ${CYAN}$ssh_command${RESET}"
        echo ""

        if [[ -f "$ssh_key_file" ]]; then
            echo "  ${BOLD}SSH Key:${RESET} $ssh_key_file"
        else
            log_warn "SSH key file not found: $ssh_key_file"
        fi
        echo ""
    fi

    # Show control commands
    echo "${BOLD}Control Commands:${RESET}"
    echo ""
    echo "  ${GREEN}Start instance:${RESET}    ./scripts/start-validator.sh"
    echo "  ${RED}Stop instance:${RESET}     ./scripts/stop-validator.sh"
    echo "  ${YELLOW}Destroy all:${RESET}       ./scripts/11-terraform-destroy.sh"
    echo ""
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
