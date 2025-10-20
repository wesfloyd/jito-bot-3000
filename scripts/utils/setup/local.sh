#!/usr/bin/env bash
# Script 00: Local Environment Setup
# Verifies all prerequisites and prepares local environment for deployment

set -euo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/utils/lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=scripts/utils/lib/solana-helpers.sh
source "${SCRIPT_DIR}/../lib/solana-helpers.sh"

# ============================================================================
# Main Function
# ============================================================================

main() {
    print_banner

    log_section "Local Environment Setup"

    log_info "This script will verify that your local machine is ready for deployment"
    echo ""

    # Check required commands
    if ! check_dependencies; then
        exit 1
    fi

    # Create directory structure
    setup_directories

    # Verify AWS credentials
    if ! verify_aws_setup; then
        exit 1
    fi

    # Setup configuration files
    setup_config_files

    # Install Solana CLI if needed
    setup_solana_cli

    # Display summary
    print_setup_summary

    log_success "Local environment setup complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Review and customize config files:"
    log_info "     - config/aws-config.env"
    log_info "     - config/jito-config.env"
    log_info "  2. Run deployment: ./scripts/infra/deploy.sh"
    log_info ""
}

# ============================================================================
# Dependency Checking
# ============================================================================

check_dependencies() {
    log_section "Checking Dependencies"

    local required_commands=(
        "aws"
        "ssh"
        "jq"
        "curl"
        "bc"
    )

    local optional_commands=(
        "solana"
        "solana-keygen"
    )

    local all_good=true

    # Check required commands
    log_info "Checking required commands..."
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Missing required command: $cmd"
            all_good=false

            # Provide installation hints
            case "$cmd" in
                aws)
                    log_info "Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
                    log_info "Or with pip: pip install awscli"
                    ;;
                jq)
                    log_info "Install: brew install jq  (macOS) or  apt install jq  (Ubuntu)"
                    ;;
                bc)
                    log_info "Install: brew install bc  (macOS) or  apt install bc  (Ubuntu)"
                    ;;
            esac
        else
            log_success "✓ $cmd"
        fi
    done

    # Check optional commands
    log_info ""
    log_info "Checking optional commands (will be installed if missing)..."
    for cmd in "${optional_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_success "✓ $cmd"
        else
            log_warn "○ $cmd (will be installed during deployment)"
        fi
    done

    if ! $all_good; then
        log_error "Please install missing dependencies before continuing"
        return 1
    fi

    log_success "All required dependencies found"
    return 0
}

# ============================================================================
# Directory Setup
# ============================================================================

setup_directories() {
    log_section "Setting Up Directory Structure"

    local dirs=(
        "$KEYS_DIR"
        "$LOGS_DIR"
        "$CONFIG_DIR"
    )

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_info "Creating directory: $dir"
            mkdir -p "$dir"
        else
            log_debug "Directory exists: $dir"
        fi
    done

    # Set proper permissions on keys directory
    chmod 700 "$KEYS_DIR" 2>/dev/null || true

    log_success "Directory structure ready"
}

# ============================================================================
# AWS Setup
# ============================================================================

verify_aws_setup() {
    log_section "Verifying AWS Configuration"

    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured"
        log_info ""
        log_info "Please configure AWS CLI with your credentials:"
        log_info "  $ aws configure"
        log_info ""
        log_info "You will need:"
        log_info "  - AWS Access Key ID"
        log_info "  - AWS Secret Access Key"
        log_info "  - Default region (e.g., us-east-1)"
        log_info ""
        return 1
    fi

    # Display AWS account info
    local account_id
    local username
    account_id=$(aws sts get-caller-identity --query Account --output text)
    username=$(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2)

    log_success "AWS credentials configured"
    log_info "  Account ID: $account_id"
    log_info "  User/Role: $username"

    # Check for default region
    local region
    region=$(aws configure get region)

    if [[ -z "$region" ]]; then
        log_warn "No default AWS region configured"
        log_info "This is okay - region can be set in config/aws-config.env"
    else
        log_info "  Default region: $region"
    fi

    return 0
}

# ============================================================================
# Configuration Files
# ============================================================================

setup_config_files() {
    log_section "Configuration Files"

    # Check if config files exist
    local aws_config="${CONFIG_DIR}/aws-config.env"
    local jito_config="${CONFIG_DIR}/jito-config.env"

    if [[ -f "$aws_config" ]]; then
        log_info "AWS config exists: $aws_config"
    else
        log_warn "AWS config not found (this shouldn't happen)"
    fi

    if [[ -f "$jito_config" ]]; then
        log_info "Jito config exists: $jito_config"
    else
        log_warn "Jito config not found (this shouldn't happen)"
    fi

    log_info ""
    log_info "Please review the configuration files before deployment:"
    log_info "  - ${BLUE}$aws_config${RESET}"
    log_info "  - ${BLUE}$jito_config${RESET}"
    log_info ""

    # Load configs to validate they're parseable
    if [[ -f "$aws_config" ]]; then
        # shellcheck disable=SC1090
        source "$aws_config" && log_debug "AWS config loaded successfully"
    fi

    if [[ -f "$jito_config" ]]; then
        # shellcheck disable=SC1090
        source "$jito_config" && log_debug "Jito config loaded successfully"
    fi

    log_success "Configuration files ready"
}

# ============================================================================
# Solana CLI Setup
# ============================================================================

setup_solana_cli() {
    log_section "Solana CLI Setup"

    if command -v solana >/dev/null 2>&1; then
        local version
        version=$(solana --version 2>/dev/null | head -1)
        log_success "Solana CLI installed: $version"
        return 0
    fi

    log_info "Solana CLI not found"

    if prompt_confirmation "Install Solana CLI now?"; then
        log_info "Installing Solana CLI..."

        if install_solana_cli; then
            local version
            version=$(solana --version 2>/dev/null | head -1)
            log_success "Solana CLI installed: $version"

            # Add to PATH for current session
            export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"

            log_info ""
            log_info "Add this to your shell profile (~/.bashrc or ~/.zshrc):"
            log_info '  export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"'
            log_info ""
        else
            log_error "Solana CLI installation failed"
            log_info "You can install it manually later with:"
            log_info '  sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"'
        fi
    else
        log_info "Skipping Solana CLI installation"
        log_info "It will be installed on the validator VM during deployment"
    fi
}

# ============================================================================
# Summary
# ============================================================================

print_setup_summary() {
    log_section "Setup Summary"

    echo "${BOLD}Environment Status:${RESET}"
    echo ""

    # AWS
    if aws sts get-caller-identity >/dev/null 2>&1; then
        echo "  ${GREEN}✓${RESET} AWS CLI configured"
    else
        echo "  ${RED}✗${RESET} AWS CLI not configured"
    fi

    # Solana
    if command -v solana >/dev/null 2>&1; then
        echo "  ${GREEN}✓${RESET} Solana CLI installed"
    else
        echo "  ${YELLOW}○${RESET} Solana CLI not installed (optional for local machine)"
    fi

    # Directories
    if [[ -d "$KEYS_DIR" && -d "$LOGS_DIR" && -d "$CONFIG_DIR" ]]; then
        echo "  ${GREEN}✓${RESET} Directory structure created"
    else
        echo "  ${RED}✗${RESET} Directory structure incomplete"
    fi

    # Config files
    if [[ -f "${CONFIG_DIR}/aws-config.env" && -f "${CONFIG_DIR}/jito-config.env" ]]; then
        echo "  ${GREEN}✓${RESET} Configuration files present"
    else
        echo "  ${RED}✗${RESET} Configuration files missing"
    fi

    echo ""

    # Estimated costs
    echo "${BOLD}Cost Estimates:${RESET}"
    echo ""
    echo "  Instance cost (m7i.4xlarge):"
    echo "    - Per hour: ${YELLOW}\$0.81${RESET}"
    echo "    - Per day: ${YELLOW}\$19.44${RESET}"
    echo "    - Per month: ${YELLOW}\$583.20${RESET}"
    echo ""
    echo "  Storage cost (2TB gp3):"
    echo "    - Per month: ${YELLOW}\$200-320${RESET}"
    echo ""
    echo "  ${BOLD}Total estimated: \$800-900/month${RESET}"
    echo ""
    echo "  ${CYAN}Tip: Use AUTO_STOP_HOURS in config to limit costs during testing${RESET}"
    echo ""
}

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
