#!/usr/bin/env bash
# Jito-Solana Build Script
#
# This script builds the Jito-Solana validator binary on the remote EC2 instance.
# It performs the following tasks:
# 1. Clones the Jito-Solana repository
# 2. Checks out the appropriate version/tag
# 3. Builds the validator binary
# 4. Installs the binary to the system
# 5. Verifies the installation
#
# Usage:
#   ./scripts/validator/build.sh [--version VERSION] [--force]
#
# Options:
#   --version VERSION    Jito-Solana version to build (default: latest testnet-compatible)
#   --force             Skip confirmation prompts
#
# Exit codes:
#   0 - Success
#   1 - Error (SSH connection failed, build failed, etc.)

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
# Default to v2.1.3-jito which is testnet-compatible
JITO_VERSION="${JITO_VERSION:-v2.1.3-jito}"

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                JITO_VERSION="$2"
                shift 2
                ;;
            --force)
                FORCE_MODE=true
                shift
                ;;
            -h|--help)
                cat << EOF
Usage: $0 [OPTIONS]

Build Jito-Solana validator binary on the remote EC2 instance.

Options:
  --version VERSION   Jito-Solana version to build (default: $JITO_VERSION)
  --force            Skip confirmation prompts
  -h, --help         Show this help message

Examples:
  # Build default version
  $0

  # Build specific version
  $0 --version v2.1.3-jito

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
# Remote Build Functions
# ============================================================================

generate_remote_build_script() {
    local version=$1

    cat << REMOTE_SCRIPT
#!/usr/bin/env bash
# This script runs on the remote EC2 instance to build Jito-Solana
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "\${BLUE}[INFO]\${NC} \$*"
}

log_success() {
    echo -e "\${GREEN}[SUCCESS]\${NC} \$*"
}

log_warn() {
    echo -e "\${YELLOW}[WARN]\${NC} \$*"
}

log_error() {
    echo -e "\${RED}[ERROR]\${NC} \$*"
}

echo "================================"
echo " Jito-Solana Build"
echo "================================"
echo ""

# Ensure Rust and Solana CLI are in PATH
export PATH="\$HOME/.cargo/bin:\$HOME/.local/share/solana/install/active_release/bin:\$PATH"

JITO_VERSION="$version"
JITO_DIR="\$HOME/jito-solana"

# ============================================================================
# Clone or Update Repository
# ============================================================================

if [[ -d "\$JITO_DIR" ]]; then
    log_info "Jito-Solana repository already exists"
    cd "\$JITO_DIR"

    log_info "Fetching latest changes..."
    git fetch --all --tags

    log_info "Cleaning workspace..."
    git clean -fdx
    git reset --hard
else
    log_info "Cloning Jito-Solana repository..."
    git clone https://github.com/jito-foundation/jito-solana.git "\$JITO_DIR"
    cd "\$JITO_DIR"
fi

# ============================================================================
# Checkout Version
# ============================================================================

log_info "Checking out version: \$JITO_VERSION"
git checkout "\$JITO_VERSION"

COMMIT_HASH=\$(git rev-parse --short HEAD)
log_info "Building from commit: \$COMMIT_HASH"

# ============================================================================
# Build Validator
# ============================================================================

log_info "Building Jito-Solana validator..."
log_warn "This will take 20-30 minutes on m7i.4xlarge..."
echo ""

# Set build flags for optimal performance
export RUSTFLAGS="-C target-cpu=native"

# Build with release profile
if cargo build --release --bin solana-validator; then
    log_success "Validator binary built successfully"
else
    log_error "Build failed"
    exit 1
fi

# ============================================================================
# Install Binaries
# ============================================================================

log_info "Installing binaries..."

# Create bin directory if it doesn't exist
mkdir -p "\$HOME/.local/bin"

# Copy binaries
cp target/release/solana-validator "\$HOME/.local/bin/"
cp target/release/solana "\$HOME/.local/bin/" 2>/dev/null || true
cp target/release/solana-keygen "\$HOME/.local/bin/" 2>/dev/null || true

# Add to PATH if not already there
if ! grep -q ".local/bin" "\$HOME/.bashrc"; then
    echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> "\$HOME/.bashrc"
fi

export PATH="\$HOME/.local/bin:\$PATH"

# Verify installation
if command -v solana-validator >/dev/null 2>&1; then
    VALIDATOR_VERSION=\$(solana-validator --version | head -1)
    log_success "Jito-Solana validator installed: \$VALIDATOR_VERSION"
else
    log_error "Validator installation verification failed"
    exit 1
fi

# ============================================================================
# Build Information
# ============================================================================

log_info "Build Information:"
echo "  Version: \$JITO_VERSION"
echo "  Commit: \$COMMIT_HASH"
echo "  Binary: \$HOME/.local/bin/solana-validator"

# Check binary size
BINARY_SIZE=\$(du -h "\$HOME/.local/bin/solana-validator" | cut -f1)
echo "  Size: \$BINARY_SIZE"

# ============================================================================
# Completion
# ============================================================================

log_success "Jito-Solana build complete!"
echo ""
log_info "Next steps:"
log_info "  1. Upload validator keypairs"
log_info "  2. Configure validator startup script"
log_info "  3. Start the validator"

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

run_remote_build() {
    local ssh_host=$1
    local ssh_key=$2
    local version=$3

    log_section "Building Jito-Solana"

    log_info "Connecting to: $ssh_host"
    log_info "Building version: $version"

    # Generate and upload the build script
    local temp_script
    temp_script=$(mktemp)
    generate_remote_build_script "$version" > "$temp_script"

    log_info "Uploading build script..."
    scp -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "$temp_script" "${ssh_host}:~/remote-build.sh"

    rm "$temp_script"

    log_info "Starting build process..."
    log_warn "Build will take 20-30 minutes. Please be patient..."
    echo ""

    # Execute the build script and show output
    if ssh -i "$ssh_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o ServerAliveInterval=60 \
        "$ssh_host" "bash ~/remote-build.sh"; then

        log_success "Build completed successfully"
        return 0
    else
        log_error "Build failed"
        return 1
    fi
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    print_banner
    log_section "Jito-Solana Build"

    # Parse arguments
    parse_args "$@"

    log_info "Jito-Solana version: $JITO_VERSION"

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

    # Test SSH connection
    if ! test_ssh_connection "$ssh_host" "$ssh_key"; then
        log_error "Cannot connect to remote instance"
        log_info "Make sure the instance is running and setup.sh has been run"
        exit 1
    fi

    # Confirm before proceeding (unless force mode)
    if [[ "$FORCE_MODE" == false ]]; then
        echo ""
        log_warn "This will build Jito-Solana validator from source"
        log_info "Build details:"
        log_info "  Version: $JITO_VERSION"
        log_info "  Duration: ~20-30 minutes"
        log_info "  CPU usage: High (all cores)"
        echo ""
        if ! prompt_confirmation "Proceed with build?"; then
            log_info "Build cancelled by user"
            exit 0
        fi
    fi

    # Run remote build
    local start_time
    start_time=$(start_timer)

    if ! run_remote_build "$ssh_host" "$ssh_key" "$JITO_VERSION"; then
        exit 1
    fi

    local duration
    duration=$(end_timer "$start_time")

    # Success summary
    log_section "Build Complete"

    log_success "Jito-Solana validator built successfully"
    log_info "Build duration: $duration"
    echo ""
    log_info "Next steps:"
    log_info "  1. Upload validator keypairs to remote instance"
    log_info "  2. Configure validator startup script"
    log_info "  3. Start the validator"

    exit 0
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
