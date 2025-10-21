#!/usr/bin/env bash
# BAM Validator Build Script
#
# This script builds the BAM validator binary on the remote EC2 instance.
# BAM (Block Auction Mechanism) is Jito's enhanced validator client with TEE support.
#
# It performs the following tasks:
# 1. Clones the bam-client repository (Jito's BAM-enabled validator fork)
# 2. Checks out the appropriate version/tag
# 3. Builds the validator binary
# 4. Installs the binary to the system
# 5. Verifies the installation
#
# Usage:
#   ./scripts/validator/build.sh [--version VERSION] [--force]
#
# Options:
#   --version VERSION    BAM client version to build (default: v3.0.6-bam)
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
# Default to v3.0.6-bam which is the latest BAM-enabled version
BAM_VERSION="${BAM_VERSION:-v3.0.6-bam}"

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                BAM_VERSION="$2"
                shift 2
                ;;
            --force)
                FORCE_MODE=true
                shift
                ;;
            -h|--help)
                cat << EOF
Usage: $0 [OPTIONS]

Build BAM validator binary on the remote EC2 instance.

Options:
  --version VERSION   BAM client version to build (default: $BAM_VERSION)
  --force            Skip confirmation prompts
  -h, --help         Show this help message

Examples:
  # Build default version (v3.0.6-bam)
  $0

  # Build specific version
  $0 --version v3.0.6-bam

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
# This script runs on the remote EC2 instance to build BAM validator
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
echo " BAM Validator Build"
echo "================================"
echo ""

# Ensure Rust and Solana CLI are in PATH
export PATH="\$HOME/.cargo/bin:\$HOME/.local/share/solana/install/active_release/bin:\$PATH"

BAM_VERSION="$version"
BAM_DIR="\$HOME/bam-client"

# ============================================================================
# Backup existing binary if it exists
# ============================================================================

if [[ -f "\$HOME/.local/bin/agave-validator" ]]; then
    log_info "Backing up existing agave-validator binary..."
    cp "\$HOME/.local/bin/agave-validator" "\$HOME/.local/bin/agave-validator.backup-\$(date +%Y%m%d-%H%M%S)"
    log_success "Backup created"
fi

# ============================================================================
# Clone or Update Repository
# ============================================================================

if [[ -d "\$BAM_DIR" ]]; then
    log_info "BAM client repository already exists"
    cd "\$BAM_DIR"

    log_info "Fetching latest changes..."
    git fetch --all --tags

    log_info "Cleaning workspace..."
    git clean -fdx
    git reset --hard
else
    log_info "Cloning BAM client repository..."
    git clone https://github.com/jito-labs/bam-client.git "\$BAM_DIR"
    cd "\$BAM_DIR"
fi

# ============================================================================
# Checkout Version
# ============================================================================

log_info "Checking out version: \$BAM_VERSION"
git checkout "\$BAM_VERSION"

COMMIT_HASH=\$(git rev-parse --short HEAD)
log_info "Building from commit: \$COMMIT_HASH"

# ============================================================================
# Initialize Submodules
# ============================================================================

log_info "Initializing Git submodules..."
git submodule update --init --recursive

log_success "Submodules initialized"

# ============================================================================
# Build Validator
# ============================================================================

log_info "Building BAM validator..."
log_warn "This will take 20-30 minutes on m7i.4xlarge..."
echo ""

# Set build flags for optimal performance
export RUSTFLAGS="-C target-cpu=native"

# Build with release profile
# BAM client builds the agave-validator binary with BAM support
if cargo build --release --bin agave-validator; then
    log_success "BAM validator binary built successfully"
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
cp target/release/agave-validator "\$HOME/.local/bin/"
cp target/release/solana "\$HOME/.local/bin/" 2>/dev/null || true
cp target/release/solana-keygen "\$HOME/.local/bin/" 2>/dev/null || true

# Create symlink for backward compatibility
ln -sf "\$HOME/.local/bin/agave-validator" "\$HOME/.local/bin/solana-validator" 2>/dev/null || true

# Add to PATH if not already there
if ! grep -q ".local/bin" "\$HOME/.bashrc"; then
    echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> "\$HOME/.bashrc"
fi

export PATH="\$HOME/.local/bin:\$PATH"

# Verify installation
if command -v agave-validator >/dev/null 2>&1; then
    VALIDATOR_VERSION=\$(agave-validator --version | head -1)
    log_success "BAM validator installed: \$VALIDATOR_VERSION"

    # Verify BAM support
    if agave-validator --help 2>&1 | grep -q "bam-url"; then
        log_success "BAM support verified: --bam-url flag available"
    else
        log_warn "BAM flag not found in help output (might be version-specific)"
    fi
else
    log_error "Validator installation verification failed"
    exit 1
fi

# ============================================================================
# Build Information
# ============================================================================

log_info "Build Information:"
echo "  Version: \$BAM_VERSION"
echo "  Commit: \$COMMIT_HASH"
echo "  Binary: \$HOME/.local/bin/agave-validator"

# Check binary size
BINARY_SIZE=\$(du -h "\$HOME/.local/bin/agave-validator" | cut -f1)
echo "  Size: \$BINARY_SIZE"

# ============================================================================
# Completion
# ============================================================================

log_success "BAM validator build complete!"
echo ""
log_info "Next steps:"
log_info "  1. Upload validator keypairs (if not already done)"
log_info "  2. Configure validator startup script with --bam-url flag"
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

    log_section "Building BAM Validator"

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
    log_section "BAM Validator Build"

    # Parse arguments
    parse_args "$@"

    log_info "BAM client version: $BAM_VERSION"

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
        log_warn "This will build BAM validator from source"
        log_info "Build details:"
        log_info "  Version: $BAM_VERSION"
        log_info "  Repository: jito-labs/bam-client"
        log_info "  Duration: ~20-30 minutes"
        log_info "  CPU usage: High (all cores)"
        log_warn "  Note: This will replace existing agave-validator binary"
        echo ""
        if ! prompt_confirmation "Proceed with build?"; then
            log_info "Build cancelled by user"
            exit 0
        fi
    fi

    # Run remote build
    local start_time
    start_time=$(start_timer)

    if ! run_remote_build "$ssh_host" "$ssh_key" "$BAM_VERSION"; then
        exit 1
    fi

    local duration
    duration=$(end_timer "$start_time")

    # Success summary
    log_section "Build Complete"

    log_success "BAM validator built successfully"
    log_info "Build duration: $duration"
    echo ""
    log_info "Next steps:"
    log_info "  1. Verify --bam-url flag is available"
    log_info "  2. Update validator startup script with BAM configuration"
    log_info "  3. Restart the validator with BAM enabled"

    exit 0
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
