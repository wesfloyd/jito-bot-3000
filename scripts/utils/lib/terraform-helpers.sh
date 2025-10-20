#!/usr/bin/env bash
# Terraform-specific helper functions for infrastructure management

# Source common utilities if not already sourced
if [[ -z "${COMMON_LIB_LOADED:-}" ]]; then
    _LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=scripts/lib/common.sh
    source "${_LIB_DIR}/common.sh"
fi

# ============================================================================
# Terraform Directory Management
# ============================================================================

get_terraform_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(dirname "$(dirname "$script_dir")")/terraform"
}

ensure_terraform_dir() {
    local terraform_dir
    terraform_dir=$(get_terraform_dir)
    
    if [[ ! -d "$terraform_dir" ]]; then
        log_error "Terraform directory not found: $terraform_dir"
        return 1
    fi
    
    echo "$terraform_dir"
}

# ============================================================================
# Terraform State Management
# ============================================================================

terraform_init() {
    local terraform_dir
    terraform_dir=$(ensure_terraform_dir) || return 1
    
    log_info "Initializing Terraform..."
    
    cd "$terraform_dir" || return 1
    
    if terraform init; then
        log_success "Terraform initialized successfully"
        return 0
    else
        log_error "Failed to initialize Terraform"
        return 1
    fi
}

terraform_plan() {
    local terraform_dir
    terraform_dir=$(ensure_terraform_dir) || return 1
    
    log_info "Creating Terraform plan..."
    
    cd "$terraform_dir" || return 1
    
    if terraform plan -out=tfplan; then
        log_success "Terraform plan created successfully"
        return 0
    else
        log_error "Failed to create Terraform plan"
        return 1
    fi
}

terraform_apply() {
    local terraform_dir
    terraform_dir=$(ensure_terraform_dir) || return 1
    
    log_info "Applying Terraform configuration..."
    
    cd "$terraform_dir" || return 1
    
    if terraform apply -auto-approve tfplan; then
        log_success "Terraform applied successfully"
        return 0
    else
        log_error "Failed to apply Terraform configuration"
        return 1
    fi
}

terraform_destroy() {
    local terraform_dir
    terraform_dir=$(ensure_terraform_dir) || return 1
    
    log_warn "Destroying Terraform infrastructure..."
    
    cd "$terraform_dir" || return 1
    
    if terraform destroy -auto-approve; then
        log_success "Terraform infrastructure destroyed"
        return 0
    else
        log_error "Failed to destroy Terraform infrastructure"
        return 1
    fi
}

# ============================================================================
# Terraform Output Management
# ============================================================================

get_terraform_output() {
    local output_name=$1
    local terraform_dir
    terraform_dir=$(ensure_terraform_dir) || return 1
    
    cd "$terraform_dir" || return 1
    
    terraform output -raw "$output_name" 2>/dev/null
}

get_instance_ip() {
    get_terraform_output "public_ip"
}

get_instance_id() {
    get_terraform_output "instance_id"
}

get_ssh_command() {
    get_terraform_output "ssh_command"
}

get_ssh_key_file() {
    get_terraform_output "ssh_key_file"
}

# ============================================================================
# Terraform State Information
# ============================================================================

terraform_show() {
    local terraform_dir
    terraform_dir=$(ensure_terraform_dir) || return 1
    
    log_info "Showing Terraform state..."
    
    cd "$terraform_dir" || return 1
    
    terraform show
}

terraform_status() {
    local terraform_dir
    terraform_dir=$(ensure_terraform_dir) || return 1
    
    log_info "Checking Terraform status..."
    
    cd "$terraform_dir" || return 1
    
    if terraform show >/dev/null 2>&1; then
        log_success "Terraform state is valid"
        return 0
    else
        log_warn "No Terraform state found or state is invalid"
        return 1
    fi
}

# ============================================================================
# Terraform Validation
# ============================================================================

terraform_validate() {
    local terraform_dir
    terraform_dir=$(ensure_terraform_dir) || return 1
    
    log_info "Validating Terraform configuration..."
    
    cd "$terraform_dir" || return 1
    
    if terraform validate; then
        log_success "Terraform configuration is valid"
        return 0
    else
        log_error "Terraform configuration validation failed"
        return 1
    fi
}

terraform_format() {
    local terraform_dir
    terraform_dir=$(ensure_terraform_dir) || return 1
    
    log_info "Formatting Terraform files..."
    
    cd "$terraform_dir" || return 1
    
    if terraform fmt -recursive; then
        log_success "Terraform files formatted"
        return 0
    else
        log_error "Failed to format Terraform files"
        return 1
    fi
}

# ============================================================================
# Terraform Cost Estimation
# ============================================================================

terraform_cost() {
    local terraform_dir
    terraform_dir=$(ensure_terraform_dir) || return 1
    
    log_info "Estimating Terraform costs..."
    
    cd "$terraform_dir" || return 1
    
    # Check if infracost is available
    if command -v infracost >/dev/null 2>&1; then
        infracost breakdown --path . --format table
    else
        log_warn "Infracost not available - showing basic cost estimates"
        log_info "Instance type costs (approximate):"
        log_info "  m7i.4xlarge: ~$0.81/hour (~$19.44/day)"
        log_info "  m7i.2xlarge: ~$0.40/hour (~$9.60/day)"
        log_info "  Storage (2TB gp3): ~$164/month"
    fi
}

# ============================================================================
# Terraform Cleanup
# ============================================================================

terraform_cleanup() {
    local terraform_dir
    terraform_dir=$(ensure_terraform_dir) || return 1
    
    log_info "Cleaning up Terraform files..."
    
    cd "$terraform_dir" || return 1
    
    # Remove plan files
    rm -f tfplan
    
    # Remove lock files (be careful with this)
    # rm -f .terraform.lock.hcl
    
    log_success "Terraform cleanup completed"
}

# ============================================================================
# Terraform Workflow Helpers
# ============================================================================

terraform_deploy() {
    log_section "Terraform Deployment"
    
    if ! terraform_validate; then
        log_error "Terraform validation failed"
        return 1
    fi
    
    if ! terraform_init; then
        log_error "Terraform initialization failed"
        return 1
    fi
    
    if ! terraform_plan; then
        log_error "Terraform planning failed"
        return 1
    fi
    
    if ! terraform_apply; then
        log_error "Terraform application failed"
        return 1
    fi
    
    log_success "Terraform deployment completed successfully"
    return 0
}

terraform_undeploy() {
    log_section "Terraform Undeployment"
    
    if ! terraform_status; then
        log_warn "No Terraform state found - nothing to destroy"
        return 0
    fi
    
    if ! prompt_confirmation "Are you sure you want to destroy all infrastructure?"; then
        log_info "Destruction cancelled"
        return 0
    fi
    
    if ! terraform_destroy; then
        log_error "Terraform destruction failed"
        return 1
    fi
    
    log_success "Terraform undeployment completed successfully"
    return 0
}
