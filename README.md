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

1. **Prerequisites**:
   ```bash
   # Install Terraform
   brew install terraform
   
   # Configure AWS CLI
   aws configure
   ```

2. **Deploy Infrastructure**:
   ```bash
   # Initialize Terraform
   ./scripts/01-terraform-init.sh
   
   # Plan deployment
   ./scripts/02-terraform-plan.sh
   
   # Deploy infrastructure
   ./scripts/03-terraform-apply.sh
   ```

3. **Monitor & Manage**:
   ```bash
   # Check status
   ./scripts/10-monitor.sh
   
   # Cleanup when done
   ./scripts/11-terraform-destroy.sh
   ```

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