#!/usr/bin/env bash
# Script 02: Terraform Planning
# Shows planned changes before applying

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

    log_section "Terraform Planning"

    # Check if Terraform is initialized
    if ! terraform_status >/dev/null 2>&1; then
        log_warn "Terraform not initialized"
        log_info "Running initialization first..."
        
        if ! terraform_init; then
            log_error "Failed to initialize Terraform"
            exit 1
        fi
    fi

    # Validate configuration
    if ! terraform_validate; then
        log_error "Terraform configuration validation failed"
        exit 1
    fi

    # Create plan
    if ! terraform_plan; then
        log_error "Failed to create Terraform plan"
        exit 1
    fi

    # Show plan details
    show_plan_summary

    log_success "Terraform planning complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Review the plan above"
    log_info "  2. Run: ./scripts/infra/deploy.sh"
    log_info "  3. Or run: ./scripts/infra/destroy.sh (to cleanup)"
    log_info ""
}

# ============================================================================
# Plan Summary
# ============================================================================

show_plan_summary() {
    log_section "Plan Summary"

    local terraform_dir
    terraform_dir=$(get_terraform_dir)
    
    cd "$terraform_dir" || return 1

    log_info "Resources to be created:"
    terraform plan -out=tfplan | grep -E "Plan:|# |\+ " | head -20
    
    echo ""
    log_info "For full plan details, run: terraform plan"
    echo ""
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
