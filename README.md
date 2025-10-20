# jito-bot-3000
Terraform-based automation to launch Jito Solana validator on testnet

## Purpose
This repo provides a complete automation solution for standing up a Jito Solana validator client on testnet using Terraform for infrastructure management.

**Goal:** Maximize automation with minimal user interactions. Uses Terraform for reliable infrastructure provisioning and bash scripts for validator setup.

## Architecture

- **Infrastructure**: Terraform manages AWS resources (EC2, VPC, Security Groups)
- **Configuration**: Declarative infrastructure as code
- **Automation**: Bash scripts handle validator setup and management
- **Monitoring**: Built-in status tracking and cost management

## Quick Start

1. **Setup (First Time)**:
   ```bash
   # Install prerequisites
   ./scripts/utils/setup/local.sh
   
   # Generate SSH keys
   ./scripts/utils/setup/ssh-keys.sh
   ```

2. **Deploy Infrastructure**:
   ```bash
   # Initialize Terraform
   ./scripts/infra/init.sh
   
   # Plan deployment
   ./scripts/infra/plan.sh
   
   # Deploy infrastructure
   ./scripts/infra/deploy.sh
   ```

3. **Monitor & Manage**:
   ```bash
   # Check status
   ./scripts/utils/status.sh
   
   # Stop instance (save costs, keep infrastructure)
   ./scripts/infra/stop.sh
   
   # Start stopped instance
   ./scripts/infra/start.sh
   
   # Complete cleanup (destroy everything)
   ./scripts/infra/destroy.sh
   ```

## Script Organization

Scripts are organized by functionality in logical folders:

- **`infra/`** - Infrastructure management (Terraform)
- **`validator/`** - Validator instance management  
- **`utils/`** - Setup, utilities, and shared libraries
  - `setup/` - Initial setup and prerequisites
  - `lib/` - Shared helper functions
  - Utility scripts for monitoring and maintenance

See `scripts/README.md` for detailed documentation of each script.

## Configuration

Edit `terraform/terraform.tfvars` to customize:
- Instance type and size
- Storage configuration
- Auto-stop settings
- Network configuration

## Key Features

- ✅ **Terraform-based**: Reliable infrastructure provisioning
- ✅ **Auto-stop**: Prevents runaway costs with automatic shutdown
- ✅ **Cost estimation**: Built-in cost tracking and alerts
- ✅ **Multi-region**: Easy region switching
- ✅ **State management**: Proper resource tracking
- ✅ **Easy cleanup**: Complete infrastructure removal

## References

- https://docs.jito.wtf/
- https://github.com/jito-foundation/jito-solana
- https://developer.hashicorp.com/terraform/docs

## Migration

This project was migrated from bash-only AWS CLI provisioning to Terraform for improved reliability and maintainability. Old bash-only code is archived in `archive/bash-provisioning/`.