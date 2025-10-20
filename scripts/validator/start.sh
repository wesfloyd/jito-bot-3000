#!/usr/bin/env bash
# Start Validator Instance
# Starts a stopped Terraform-managed EC2 instance

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

    log_section "Start Validator Instance"

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

    if [[ "$current_status" == "running" ]]; then
        log_warn "Instance is already running"
        show_connection_info
        exit 0
    fi

    if [[ "$current_status" == "pending" ]]; then
        log_info "Instance is already starting"
        wait_for_instance_and_ssh
        exit 0
    fi

    if [[ "$current_status" == "terminated" ]]; then
        log_error "Instance has been terminated"
        log_info "You need to provision a new instance with ./scripts/infra/deploy.sh"
        exit 1
    fi

    # Show cost warning
    show_cost_warning

    # Confirm action
    if ! prompt_confirmation "Start the validator instance?"; then
        log_info "Start cancelled by user"
        exit 0
    fi

    # Start instance
    log_info "Starting instance: $instance_id"
    if ! aws ec2 start-instances --region "$region" --instance-ids "$instance_id" >/dev/null; then
        log_error "Failed to start instance"
        exit 1
    fi

    log_success "Instance is starting"

    # Wait for running state and SSH
    wait_for_instance_and_ssh

    # Show connection info
    show_connection_info

    log_success "Instance is ready!"
}

# ============================================================================
# Wait for Instance and SSH
# ============================================================================

wait_for_instance_and_ssh() {
    local instance_id
    instance_id=$(get_terraform_output "instance_id" 2>/dev/null || echo "")

    # Wait for running
    log_info "Waiting for instance to be running..."
    if ! aws ec2 wait instance-running --region "$region" --instance-ids "$instance_id"; then
        log_error "Instance failed to start"
        exit 1
    fi

    # Get new IP from Terraform (may have changed)
    log_info "Retrieving new public IP..."
    local public_ip
    public_ip=$(get_terraform_output "public_ip" 2>/dev/null || echo "")

    if [[ -z "$public_ip" || "$public_ip" == "None" ]]; then
        log_error "Failed to get instance public IP"
        exit 1
    fi

    log_success "Instance is running: $public_ip"

    # Wait for SSH
    local ssh_key_file
    ssh_key_file=$(get_terraform_output "ssh_key_file" 2>/dev/null || echo "../keys/jito-validator-key.pem")
    local ssh_user="ubuntu"

    log_info "Waiting for SSH to be available..."
    local ssh_attempts=0
    local max_attempts=30
    
    while [[ $ssh_attempts -lt $max_attempts ]]; do
        if ssh -i "$ssh_key_file" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            -o ConnectTimeout=10 \
            "$ssh_user@$public_ip" \
            "echo 'SSH connection successful'" >/dev/null 2>&1; then
            log_success "SSH is ready"
            return 0
        fi
        
        ssh_attempts=$((ssh_attempts + 1))
        log_info "SSH attempt $ssh_attempts/$max_attempts failed, retrying in 10s..."
        sleep 10
    done

    log_error "SSH not available after waiting"
    log_info "Instance is running but SSH may need more time"
    log_info "Try connecting manually in a few minutes"
    exit 1
}

# ============================================================================
# Cost Warning
# ============================================================================

show_cost_warning() {
    log_section "Cost Warning"

    local instance_type
    instance_type=$(get_terraform_output "instance_type" 2>/dev/null || echo "m7i.4xlarge")
    local hourly_cost="0.81"  # Approximate cost for m7i.4xlarge

    echo "${BOLD}Starting the instance will resume charges:${RESET}"
    echo ""
    printf "  ${YELLOW}\$%.2f per hour${RESET}\n" "$hourly_cost"
    printf "  ${YELLOW}\$%.2f per day${RESET}\n" "$(echo "$hourly_cost * 24" | bc -l)"
    echo ""
    echo "  ${CYAN}Don't forget to stop when done testing!${RESET}"
    echo ""
}

# ============================================================================
# Connection Info
# ============================================================================

show_connection_info() {
    log_section "Connection Information"

    local instance_id
    instance_id=$(get_terraform_output "instance_id" 2>/dev/null || echo "")
    local public_ip
    public_ip=$(get_terraform_output "public_ip" 2>/dev/null || echo "unknown")
    local ssh_key_file
    ssh_key_file=$(get_terraform_output "ssh_key_file" 2>/dev/null || echo "../keys/jito-validator-key.pem")
    local ssh_user="ubuntu"

    echo "${BOLD}SSH Connection:${RESET}"
    echo ""
    echo "  ${CYAN}ssh -i $ssh_key_file ${ssh_user}@${public_ip}${RESET}"
    echo ""

    echo "${BOLD}Next Steps:${RESET}"
    echo ""
    echo "  - If validator was previously running, it should restart automatically"
    echo "  - Check validator status: ssh to instance and run 'sudo systemctl status jito-validator'"
    echo "  - View logs: ssh to instance and run 'tail -f /home/sol/jito-validator.log'"
    echo ""
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
