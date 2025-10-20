#!/usr/bin/env bash
# Script 01: AWS Infrastructure Provisioning
# Provisions EC2 instance for Jito validator deployment

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

    log_section "AWS Infrastructure Provisioning"

    # Load configurations
    load_configurations

    # Show cost warning
    show_cost_warning

    # Verify AWS credentials
    if ! verify_aws_credentials; then
        log_error "AWS credentials not configured"
        exit 1
    fi

    # Set AWS region
    check_aws_region "$AWS_REGION"

    # Provision infrastructure
    provision_ssh_keypair
    provision_security_group
    provision_ec2_instance

    # Schedule auto-stop if configured
    if [[ ${AUTO_STOP_HOURS:-0} -gt 0 ]]; then
        schedule_auto_stop
    fi

    # Display summary
    display_summary

    log_success "AWS infrastructure provisioning complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Verify you can SSH to the instance (wait 2-3 minutes for initialization)"
    log_info "  2. Run: ./scripts/02-generate-keys.sh"
    log_info ""
}

# ============================================================================
# Configuration Loading
# ============================================================================

load_configurations() {
    log_section "Loading Configuration"

    local aws_config="${CONFIG_DIR}/aws-config.env"
    local jito_config="${CONFIG_DIR}/jito-config.env"

    if [[ ! -f "$aws_config" ]]; then
        log_error "AWS config not found: $aws_config"
        exit 1
    fi

    if [[ ! -f "$jito_config" ]]; then
        log_error "Jito config not found: $jito_config"
        exit 1
    fi

    # shellcheck disable=SC1090
    source "$aws_config"
    # shellcheck disable=SC1090
    source "$jito_config"

    log_success "Configuration loaded"

    # Validate required variables
    local required_vars=(
        "AWS_REGION"
        "AWS_INSTANCE_TYPE"
        "AWS_INSTANCE_NAME"
        "AWS_KEY_NAME"
        "AWS_SECURITY_GROUP_NAME"
        "AWS_VOLUME_SIZE"
    )

    if ! validate_config "${required_vars[@]}"; then
        exit 1
    fi

    log_info "Configuration validated"
}

# ============================================================================
# Cost Warning
# ============================================================================

show_cost_warning() {
    log_section "Cost Estimate"

    log_warn "You are about to provision AWS resources that will incur costs:"
    echo ""
    echo "  ${BOLD}Instance:${RESET} $AWS_INSTANCE_TYPE"
    echo "  ${BOLD}Storage:${RESET} ${AWS_VOLUME_SIZE}GB ${AWS_VOLUME_TYPE}"
    echo "  ${BOLD}Region:${RESET} $AWS_REGION"
    echo ""

    # Calculate costs
    local hourly_cost
    hourly_cost=$(estimate_instance_cost "$AWS_INSTANCE_TYPE" 1)
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
    local storage_monthly=$(echo "$AWS_VOLUME_SIZE * 0.08" | bc -l)
    printf "  ${BOLD}Storage:${RESET} ${YELLOW}\$%.2f/month${RESET} (${AWS_VOLUME_SIZE}GB @ \$0.08/GB)\n" "$storage_monthly"
    echo ""

    # Auto-stop reminder
    if [[ ${AUTO_STOP_HOURS:-0} -gt 0 ]]; then
        log_info "Auto-stop configured: Instance will be tagged to stop after $AUTO_STOP_HOURS hours"
        local auto_stop_cost=$(echo "$hourly_cost * $AUTO_STOP_HOURS" | bc -l)
        printf "  ${CYAN}Estimated cost for this session: \$%.2f${RESET}\n" "$auto_stop_cost"
        echo ""
    else
        log_warn "No auto-stop configured - remember to stop/terminate instance when done!"
        echo ""
    fi

    if ! prompt_confirmation "Do you want to proceed with provisioning?"; then
        log_info "Provisioning cancelled by user"
        exit 0
    fi
}

# ============================================================================
# SSH Keypair Provisioning
# ============================================================================

provision_ssh_keypair() {
    log_section "SSH Keypair Setup"

    local key_file="${KEYS_DIR}/${AWS_KEY_NAME}.pem"

    if ! create_or_get_keypair "$AWS_KEY_NAME" "$key_file" "$AWS_REGION"; then
        log_error "Failed to create/get SSH keypair"
        exit 1
    fi

    # Save to state
    save_state "aws.ssh_key_name" "$AWS_KEY_NAME"
    save_state "aws.ssh_key_file" "$key_file"

    log_success "SSH keypair ready: $AWS_KEY_NAME"
}

# ============================================================================
# Security Group Provisioning
# ============================================================================

provision_security_group() {
    log_section "Security Group Setup"

    local sg_id
    sg_id=$(create_security_group \
        "$AWS_SECURITY_GROUP_NAME" \
        "Security group for Jito validator" \
        "$AWS_REGION" \
        "${AWS_VPC_ID:-}")

    if [[ -z "$sg_id" ]]; then
        log_error "Failed to create security group"
        exit 1
    fi

    log_info "Security group: $sg_id"

    # Get admin IP
    local admin_ip="${ADMIN_IP:-auto}"
    if [[ "$admin_ip" == "auto" ]]; then
        admin_ip=$(curl -s https://checkip.amazonaws.com)
        log_info "Detected your public IP: $admin_ip"
    fi

    # Configure security group rules
    if ! configure_validator_security_group "$sg_id" "$AWS_REGION" "$admin_ip"; then
        log_error "Failed to configure security group rules"
        exit 1
    fi

    # Save to state
    save_state "aws.security_group_id" "$sg_id"

    log_success "Security group configured: $sg_id"
}

# ============================================================================
# EC2 Instance Provisioning
# ============================================================================

provision_ec2_instance() {
    log_section "EC2 Instance Provisioning"

    # Get AMI ID
    local ami_id="${AWS_AMI_ID:-}"
    if [[ -z "$ami_id" ]]; then
        log_info "Finding latest Ubuntu 22.04 AMI..."
        ami_id=$(find_latest_ubuntu_ami "$AWS_REGION")
        if [[ -z "$ami_id" ]]; then
            log_error "Failed to find Ubuntu AMI"
            exit 1
        fi
    fi

    log_info "Using AMI: $ami_id"

    # Get security group and key name from state
    local sg_id
    sg_id=$(get_state "aws.security_group_id")
    local key_name
    key_name=$(get_state "aws.ssh_key_name")

    # Launch instance
    log_info "Launching EC2 instance (this may take a minute)..."
    local instance_id
    instance_id=$(launch_ec2_instance \
        "$AWS_INSTANCE_TYPE" \
        "$ami_id" \
        "$key_name" \
        "$sg_id" \
        "$AWS_INSTANCE_NAME" \
        "$AWS_VOLUME_SIZE" \
        "$AWS_REGION" \
        "${AWS_VPC_ID:-}")

    if [[ -z "$instance_id" ]]; then
        log_error "Failed to launch EC2 instance"
        exit 1
    fi

    log_success "Instance launched: $instance_id"

    # Save to state
    save_state "aws.instance_id" "$instance_id"
    save_state "aws.instance_type" "$AWS_INSTANCE_TYPE"
    save_state "aws.region" "$AWS_REGION"
    save_state "deployment.timestamp" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    # Wait for instance to be running
    if ! wait_for_instance_running "$instance_id" "$AWS_REGION"; then
        log_error "Instance failed to start"
        exit 1
    fi

    # Get public IP
    log_info "Retrieving instance public IP..."
    local public_ip
    public_ip=$(get_instance_ip "$instance_id" "$AWS_REGION")

    if [[ -z "$public_ip" ]]; then
        log_error "Failed to get instance public IP"
        exit 1
    fi

    log_success "Instance public IP: $public_ip"

    # Save to state
    save_state "aws.public_ip" "$public_ip"

    # Wait for SSH to be ready
    local ssh_key_file
    ssh_key_file=$(get_state "aws.ssh_key_file")
    local ssh_user="${SSH_USER:-ubuntu}"

    if ! wait_for_ssh "${ssh_user}@${public_ip}" "$ssh_key_file" 30 10; then
        log_error "SSH not available after waiting"
        log_info "Instance is running but SSH may need more time to initialize"
        log_info "Try connecting manually: ssh -i $ssh_key_file ${ssh_user}@${public_ip}"
        exit 1
    fi

    log_success "SSH is ready"
}

# ============================================================================
# Auto-Stop Scheduling
# ============================================================================

schedule_auto_stop() {
    log_section "Auto-Stop Configuration"

    local instance_id
    instance_id=$(get_state "aws.instance_id")

    if ! schedule_instance_stop "$instance_id" "$AUTO_STOP_HOURS" "$AWS_REGION"; then
        log_warn "Failed to schedule auto-stop"
        return 1
    fi

    log_success "Instance scheduled to stop in $AUTO_STOP_HOURS hours"
    log_info "Manual controls:"
    log_info "  Stop now:  ./scripts/stop-validator.sh"
    log_info "  Check status: ./scripts/get-status.sh"
}

# ============================================================================
# Summary
# ============================================================================

display_summary() {
    log_section "Deployment Summary"

    local instance_id
    instance_id=$(get_state "aws.instance_id")
    local public_ip
    public_ip=$(get_state "aws.public_ip")
    local ssh_key_file
    ssh_key_file=$(get_state "aws.ssh_key_file")
    local ssh_user="${SSH_USER:-ubuntu}"

    echo "${BOLD}AWS Resources Created:${RESET}"
    echo ""
    echo "  ${BOLD}Instance ID:${RESET} $instance_id"
    echo "  ${BOLD}Instance Type:${RESET} $AWS_INSTANCE_TYPE"
    echo "  ${BOLD}Public IP:${RESET} $public_ip"
    echo "  ${BOLD}Region:${RESET} $AWS_REGION"
    echo "  ${BOLD}SSH Key:${RESET} $ssh_key_file"
    echo ""

    echo "${BOLD}SSH Connection:${RESET}"
    echo ""
    echo "  ${CYAN}ssh -i $ssh_key_file ${ssh_user}@${public_ip}${RESET}"
    echo ""

    if [[ ${AUTO_STOP_HOURS:-0} -gt 0 ]]; then
        local stop_time
        stop_time=$(date -u -d "+${AUTO_STOP_HOURS} hours" '+%Y-%m-%d %H:%M:%S UTC')
        echo "${BOLD}Auto-Stop:${RESET}"
        echo ""
        echo "  Scheduled for: ${YELLOW}$stop_time${RESET}"
        echo "  (${AUTO_STOP_HOURS} hours from now)"
        echo ""
    fi

    echo "${BOLD}State File:${RESET}"
    echo ""
    echo "  $STATE_FILE"
    echo ""
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
