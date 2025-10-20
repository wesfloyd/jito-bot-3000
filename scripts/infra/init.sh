#!/usr/bin/env bash
# Script 01: Terraform Initialization
# Initializes Terraform and validates configuration

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

    log_section "Terraform Initialization"

    # Check prerequisites
    check_prerequisites

    # Initialize Terraform (validation happens after providers are installed)
    if ! terraform_init; then
        log_error "Terraform initialization failed"
        exit 1
    fi

    # Validate Terraform configuration
    if ! terraform_validate; then
        log_error "Terraform configuration validation failed"
        exit 1
    fi

    # Show cost estimate
    show_cost_estimate

    log_success "Terraform initialization complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Review configuration: terraform/terraform.tfvars"
    log_info "  2. Run: ./scripts/02-terraform-plan.sh"
    log_info ""
}

# ============================================================================
# Prerequisites Check
# ============================================================================

check_prerequisites() {
    log_section "Checking Prerequisites"

    # Check if Terraform is installed
    if ! command -v terraform >/dev/null 2>&1; then
        log_error "Terraform is not installed"
        log_info "Please install Terraform: https://developer.hashicorp.com/terraform/downloads"
        exit 1
    fi

    # Check Terraform version
    local tf_version
    tf_version=$(terraform version -json | jq -r '.terraform_version')
    log_success "Terraform version: $tf_version"

    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI not configured"
        log_info "Please run: aws configure"
        exit 1
    fi

    # Check AWS credentials
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    log_success "AWS authenticated (Account: $account_id)"

    # Check if terraform.tfvars exists
    local terraform_dir
    terraform_dir=$(get_terraform_dir)
    if [[ ! -f "$terraform_dir/terraform.tfvars" ]]; then
        log_warn "terraform.tfvars not found"
        log_info "Creating from example..."
        
        if [[ -f "$terraform_dir/terraform.tfvars.example" ]]; then
            cp "$terraform_dir/terraform.tfvars.example" "$terraform_dir/terraform.tfvars"
            log_success "Created terraform.tfvars from example"
            log_warn "Please review and edit: $terraform_dir/terraform.tfvars"
        else
            log_error "No terraform.tfvars.example found"
            exit 1
        fi
    fi

    log_success "Prerequisites check complete"
}

# ============================================================================
# Cost Estimation
# ============================================================================

show_cost_estimate() {
    log_section "Cost Estimate"

    local terraform_dir
    terraform_dir=$(get_terraform_dir)
    
    # Read variables from tfvars
    local instance_type
    instance_type=$(grep "instance_type" "$terraform_dir/terraform.tfvars" | cut -d'"' -f2)
    local volume_size
    volume_size=$(grep "volume_size" "$terraform_dir/terraform.tfvars" | cut -d'=' -f2 | tr -d ' ')
    local auto_stop_hours
    auto_stop_hours=$(grep "auto_stop_hours" "$terraform_dir/terraform.tfvars" | cut -d'=' -f2 | tr -d ' ')

    log_warn "You are about to provision AWS resources that will incur costs:"
    echo ""
    echo "  ${BOLD}Instance:${RESET} $instance_type"
    echo "  ${BOLD}Storage:${RESET} ${volume_size}GB gp3"
    echo ""

    # Calculate costs based on instance type
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
            log_warn "Unknown instance type, using estimated rate: \$${hourly_cost}/hour"
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
    printf "  ${BOLD}Storage:${RESET} ${YELLOW}\$%.2f/month${RESET} (${volume_size}GB @ \$0.08/GB)\n" "$storage_monthly"
    echo ""

    # Auto-stop reminder
    if [[ "$auto_stop_hours" -gt 0 ]]; then
        log_info "Auto-stop configured: Instance will be tagged to stop after $auto_stop_hours hours"
        local auto_stop_cost=$(echo "$hourly_cost * $auto_stop_hours" | bc -l)
        printf "  ${CYAN}Estimated cost for this session: \$%.2f${RESET}\n" "$auto_stop_cost"
        echo ""
    else
        log_warn "No auto-stop configured - remember to stop/terminate instance when done!"
        echo ""
    fi
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
