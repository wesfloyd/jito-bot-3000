#!/bin/bash

# Jito-Solana Validator SSH Key Generation
# This script generates the SSH key pair required for Terraform

set -euo pipefail

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Configuration
KEY_NAME="jito-validator-key"
KEYS_DIR="${SCRIPT_DIR}/../keys"

log_section "SSH Key Generation"

# Create keys directory if it doesn't exist
mkdir -p "$KEYS_DIR"

# Check if key already exists
if [[ -f "${KEYS_DIR}/${KEY_NAME}.pem" && -f "${KEYS_DIR}/${KEY_NAME}.pub" ]]; then
    log_info "SSH key pair already exists: ${KEY_NAME}"
    log_info "Private key: ${KEYS_DIR}/${KEY_NAME}.pem"
    log_info "Public key: ${KEYS_DIR}/${KEY_NAME}.pub"
    exit 0
fi

log_info "Generating SSH key pair: ${KEY_NAME}"

# Generate SSH key pair
ssh-keygen -t rsa -b 4096 -f "${KEYS_DIR}/${KEY_NAME}.pem" -N "" -C "jito-validator-key"

# Rename the public key to match expected naming convention
mv "${KEYS_DIR}/${KEY_NAME}.pem.pub" "${KEYS_DIR}/${KEY_NAME}.pub"

# Set proper permissions
chmod 600 "${KEYS_DIR}/${KEY_NAME}.pem"
chmod 644 "${KEYS_DIR}/${KEY_NAME}.pub"

log_success "SSH key pair generated successfully!"
log_info "Private key: ${KEYS_DIR}/${KEY_NAME}.pem"
log_info "Public key: ${KEYS_DIR}/${KEY_NAME}.pub"

log_info ""
log_info "Next steps:"
log_info "  1. Run: ./scripts/infra/plan.sh"
log_info "  2. Run: ./scripts/infra/deploy.sh"
