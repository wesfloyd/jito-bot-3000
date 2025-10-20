#!/usr/bin/env bash
# Remote Validator Setup Script
#
# This script configures the remote EC2 instance for running a Jito validator.
# It performs the following tasks:
# 1. Updates system packages
# 2. Installs required dependencies (Rust, build tools, etc.)
# 3. Configures system settings for optimal validator performance
# 4. Installs and configures Solana CLI
#
# Usage:
#   ./scripts/validator/setup.sh [--force]
#
# Options:
#   --force    Skip confirmation prompts
#
# Exit codes:
#   0 - Success
#   1 - Error (SSH connection failed, setup failed, etc.)

set -euo pipefail

# ============================================================================
# Setup
# ============================================================================

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common utilities
# shellcheck source=scripts/utils/lib/common.sh
source "${PROJECT_ROOT}/scripts/utils/lib/common.sh"
# shellcheck source=scripts/utils/lib/terraform-helpers.sh
source "${PROJECT_ROOT}/scripts/utils/lib/terraform-helpers.sh"

# ============================================================================
# Configuration
# ============================================================================

FORCE_MODE=false

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_MODE=true
                shift
                ;;
            -h|--help)
                cat << EOF
Usage: $0 [OPTIONS]

Configure the remote EC2 instance for running a Jito validator.

Options:
  --force         Skip confirmation prompts
  -h, --help     Show this help message

Examples:
  # Interactive mode
  $0

  # Non-interactive mode
  $0 --force

EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                log_info "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# Remote Setup Functions
# ============================================================================

# This function generates the remote setup script that will run on the EC2 instance
generate_remote_setup_script() {
    cat << 'REMOTE_SCRIPT'
#!/usr/bin/env bash
# This script runs on the remote EC2 instance
set -euo pipefail

echo "================================"
echo " Jito Validator Remote Setup"
echo "================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# ============================================================================
# System Update
# ============================================================================

log_info "Updating system packages..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
log_success "System packages updated"

# ============================================================================
# Install Build Dependencies
# ============================================================================

log_info "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    build-essential \
    pkg-config \
    libudev-dev \
    llvm \
    libclang-dev \
    protobuf-compiler \
    libssl-dev \
    cmake \
    git \
    curl \
    wget \
    jq \
    htop \
    iotop \
    sysstat \
    vim \
    tmux \
    unzip

log_success "Build dependencies installed"

# ============================================================================
# Install Rust
# ============================================================================

if command -v rustc >/dev/null 2>&1; then
    RUST_VERSION=$(rustc --version | awk '{print $2}')
    log_info "Rust already installed: $RUST_VERSION"
else
    log_info "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    source "$HOME/.cargo/env"
    log_success "Rust installed: $(rustc --version)"
fi

# Ensure Rust is in PATH for this session
export PATH="$HOME/.cargo/env:$PATH"

# ============================================================================
# Configure System for Validator Performance
# ============================================================================

log_info "Configuring system for validator performance..."

# Increase file descriptor limits
sudo tee /etc/security/limits.d/90-solana-nofiles.conf > /dev/null <<EOF
# Increase file descriptor limits for Solana validator
* soft nofile 1000000
* hard nofile 1000000
EOF

# Set sysctl parameters for optimal network performance
sudo tee /etc/sysctl.d/21-solana-validator.conf > /dev/null <<EOF
# Solana validator performance tuning
net.core.rmem_default = 134217728
net.core.rmem_max = 134217728
net.core.wmem_default = 134217728
net.core.wmem_max = 134217728
vm.max_map_count = 1000000
fs.nr_open = 1000000
EOF

# Apply sysctl settings
sudo sysctl -p /etc/sysctl.d/21-solana-validator.conf >/dev/null

log_success "System configured for validator performance"

# ============================================================================
# Install Solana CLI
# ============================================================================

if command -v solana >/dev/null 2>&1; then
    SOLANA_VERSION=$(solana --version | awk '{print $2}')
    log_info "Solana CLI already installed: $SOLANA_VERSION"
else
    log_info "Installing Solana CLI..."
    sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"

    # Add to PATH for this session
    export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"

    # Add to .bashrc for future sessions
    if ! grep -q "solana/install/active_release/bin" "$HOME/.bashrc"; then
        echo 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' >> "$HOME/.bashrc"
    fi

    SOLANA_VERSION=$(solana --version | awk '{print $2}')
    log_success "Solana CLI installed: $SOLANA_VERSION"
fi

# Configure Solana CLI for testnet
log_info "Configuring Solana CLI for testnet..."
solana config set --url https://api.testnet.solana.com
log_success "Solana CLI configured for testnet"

# ============================================================================
# Create Validator Directory Structure
# ============================================================================

log_info "Creating validator directory structure..."
mkdir -p ~/validator
mkdir -p ~/validator/config
mkdir -p ~/validator/ledger
mkdir -p ~/validator/accounts
mkdir -p ~/validator/snapshots
mkdir -p ~/validator/logs
mkdir -p ~/validator/keys

log_success "Validator directories created"

# ============================================================================
# System Information
# ============================================================================

log_info "System Information:"
echo "  OS: $(lsb_release -d | cut -f2-)"
echo "  Kernel: $(uname -r)"
echo "  CPU: $(nproc) cores"
echo "  RAM: $(free -h | awk '/^Mem:/ {print $2}')"
echo "  Disk: $(df -h / | awk 'NR==2 {print $2}')"
echo "  Rust: $(rustc --version | awk '{print $2}')"
echo "  Solana: $(solana --version | awk '{print $2}')"

# ============================================================================
# Completion
# ============================================================================

log_success "Remote validator setup complete!"
echo ""
log_info "Next steps:"
log_info "  1. Upload validator keypairs to ~/validator/keys/"
log_info "  2. Build Jito-Solana validator binary"
log_info "  3. Configure and start the validator"

REMOTE_SCRIPT
}

# ============================================================================
# SSH Helper Functions
# ============================================================================

get_ssh_connection_info() {
    local terraform_dir="${PROJECT_ROOT}/terraform"

    if [[ ! -f "$terraform_dir/terraform.tfstate" ]]; then
        log_error "Terraform state not found. Deploy infrastructure first."
        return 1
    fi

    cd "$terraform_dir"

    local ssh_host
    ssh_host=$(terraform output -raw ssh_host 2>/dev/null || echo "")

    local ssh_key
    ssh_key=$(terraform output -raw ssh_key_file 2>/dev/null || echo "")

    if [[ -z "$ssh_host" || -z "$ssh_key" ]]; then
        log_error "Could not get SSH connection info from Terraform"
        return 1
    fi

    # Make path absolute - handle relative paths from terraform directory
    if [[ "$ssh_key" == ../* ]]; then
        ssh_key="${PROJECT_ROOT}/terraform/${ssh_key}"
    elif [[ "$ssh_key" != /* ]]; then
        ssh_key="${PROJECT_ROOT}/${ssh_key}"
    fi

    echo "$ssh_host|$ssh_key"
}

test_ssh_connection() {
    local ssh_host=$1
    local ssh_key=$2

    log_info "Testing SSH connection to $ssh_host..."

    if ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o LogLevel=ERROR \
        "$ssh_host" "echo 'SSH connection successful'" >/dev/null 2>&1; then

        log_success "SSH connection successful"
        return 0
    else
        log_error "SSH connection failed"
        return 1
    fi
}

run_remote_setup() {
    local ssh_host=$1
    local ssh_key=$2

    log_section "Running Remote Setup"

    log_info "Connecting to: $ssh_host"

    # Generate and upload the setup script
    local temp_script
    temp_script=$(mktemp)
    generate_remote_setup_script > "$temp_script"

    log_info "Uploading setup script..."
    scp -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$temp_script" "${ssh_host}:~/remote-setup.sh"

    rm "$temp_script"

    log_info "Executing setup script on remote instance..."
    log_warn "This may take 5-10 minutes..."
    echo ""

    # Execute the script and show output
    if ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$ssh_host" "bash ~/remote-setup.sh"; then

        log_success "Remote setup completed successfully"
        return 0
    else
        log_error "Remote setup failed"
        return 1
    fi
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    print_banner
    log_section "Validator Remote Setup"

    # Parse arguments
    parse_args "$@"

    # Get SSH connection info from Terraform
    log_info "Getting connection information from Terraform..."

    local connection_info
    connection_info=$(get_ssh_connection_info)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to get SSH connection info"
        exit 1
    fi

    local ssh_host
    ssh_host=$(echo "$connection_info" | cut -d'|' -f1)

    local ssh_key
    ssh_key=$(echo "$connection_info" | cut -d'|' -f2)

    log_info "SSH Host: $ssh_host"
    log_info "SSH Key: $ssh_key"

    # Test SSH connection
    if ! test_ssh_connection "$ssh_host" "$ssh_key"; then
        log_error "Cannot connect to remote instance"
        log_info "Make sure the instance is running and security group allows SSH"
        exit 1
    fi

    # Confirm before proceeding (unless force mode)
    if [[ "$FORCE_MODE" == false ]]; then
        echo ""
        log_warn "This will configure the remote instance for validator operation"
        log_info "The following will be installed/configured:"
        log_info "  - System package updates"
        log_info "  - Build dependencies (gcc, cmake, etc.)"
        log_info "  - Rust toolchain"
        log_info "  - Solana CLI"
        log_info "  - System performance tuning"
        echo ""
        if ! prompt_confirmation "Proceed with remote setup?"; then
            log_info "Setup cancelled by user"
            exit 0
        fi
    fi

    # Run remote setup
    if ! run_remote_setup "$ssh_host" "$ssh_key"; then
        exit 1
    fi

    # Success summary
    log_section "Setup Complete"

    log_success "Validator instance is configured and ready"
    echo ""
    log_info "SSH connection:"
    log_info "  ${BOLD}ssh -i $ssh_key $ssh_host${RESET}"
    echo ""
    log_info "Next steps:"
    log_info "  1. Run: ./scripts/validator/build.sh (to build Jito-Solana)"
    log_info "  2. Upload validator keypairs"
    log_info "  3. Configure and start the validator"

    exit 0
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
