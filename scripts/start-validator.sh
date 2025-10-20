#!/usr/bin/env bash
# Start Validator Instance
# Starts a stopped EC2 instance and updates deployment state

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

    log_section "Start Validator Instance"

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
        log_info "You need to provision a new instance with ./scripts/01-provision-aws.sh"
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
    if ! start_instance "$instance_id" "$region"; then
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
    instance_id=$(get_state "aws.instance_id")
    local region
    region=$(get_state "aws.region")

    # Wait for running
    log_info "Waiting for instance to be running..."
    if ! wait_for_instance_running "$instance_id" "$region"; then
        log_error "Instance failed to start"
        exit 1
    fi

    # Get new IP (may have changed)
    log_info "Retrieving new public IP..."
    local public_ip
    public_ip=$(get_instance_ip "$instance_id" "$region")

    if [[ -z "$public_ip" ]]; then
        log_error "Failed to get instance public IP"
        exit 1
    fi

    # Update state with new IP
    local old_ip
    old_ip=$(get_state "aws.public_ip")
    if [[ "$old_ip" != "$public_ip" ]]; then
        log_info "Public IP changed: $old_ip -> $public_ip"
        save_state "aws.public_ip" "$public_ip"
    fi

    log_success "Instance is running: $public_ip"

    # Wait for SSH
    local ssh_key_file
    ssh_key_file=$(get_state "aws.ssh_key_file")
    local ssh_user="${SSH_USER:-ubuntu}"

    log_info "Waiting for SSH to be available..."
    if ! wait_for_ssh "${ssh_user}@${public_ip}" "$ssh_key_file" 30 10; then
        log_error "SSH not available after waiting"
        log_info "Instance is running but SSH may need more time"
        log_info "Try connecting manually in a few minutes"
        exit 1
    fi

    log_success "SSH is ready"
}

# ============================================================================
# Cost Warning
# ============================================================================

show_cost_warning() {
    log_section "Cost Warning"

    local instance_type
    instance_type=$(get_state "aws.instance_type")

    local hourly_cost
    hourly_cost=$(estimate_instance_cost "$instance_type" 1)

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

    local public_ip
    public_ip=$(get_state "aws.public_ip")
    local ssh_key_file
    ssh_key_file=$(get_state "aws.ssh_key_file")
    local ssh_user="${SSH_USER:-ubuntu}"

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
