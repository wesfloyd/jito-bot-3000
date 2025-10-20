# jito-bot-3000
Terraform-based automation to launch Jito Solana validator on testnet

<img src="public/jito-bot-logo-ascii.png" alt="Jito Bot Logo" width="250px">


## Purpose
This repo provides a complete automation solution for standing up a Jito Solana validator client on testnet using Terraform for infrastructure management.

**Goal:** Maximize automation with minimal user interactions. Uses Terraform for reliable infrastructure provisioning and bash scripts for validator setup.

## Architecture

- **Infrastructure**: Terraform manages AWS resources (EC2, VPC, Security Groups)
- **Configuration**: Declarative infrastructure as code
- **Automation**: Bash scripts handle validator setup and management
- **Monitoring**: Built-in status tracking and cost management

## Quick Start

### Prerequisites

- AWS CLI configured with credentials
- Solana CLI installed locally
- Terraform (auto-installed by setup script)
- SSH client

### Complete Deployment (End-to-End)

Follow these steps in order to deploy a complete Jito validator on testnet:

#### 1. Local Setup & Key Generation
```bash
# Install prerequisites and Terraform
./scripts/utils/setup/local.sh

# Generate SSH keys for EC2 access
./scripts/utils/setup/ssh-keys.sh

# Generate Solana validator keypairs (validator identity, vote account, withdrawer)
./scripts/utils/generate-keys.sh --force

# Fund accounts on testnet (5 SOL validator, 1 SOL vote account)
# Use solana faucet at: https://faucet.solana.com/ w/ Testnet
./scripts/utils/fund-accounts.sh --force
```

**Expected Output**: Three keypairs generated in `keys/`, accounts funded on testnet

#### 2. Infrastructure Deployment
```bash
# Initialize Terraform
./scripts/infra/init.sh

# Preview infrastructure changes
./scripts/infra/plan.sh

# Deploy AWS infrastructure (EC2 instance, security groups, networking)
./scripts/infra/deploy.sh
```

**Expected Output**: EC2 instance running in AWS, SSH access configured

**Note**: Infrastructure includes auto-stop after 8 hours to prevent runaway costs. The instance can be restarted with `./scripts/infra/start.sh`.

#### 3. Remote Validator Setup
```bash
# Configure remote instance (dependencies, Rust, Solana CLI, system tuning)
./scripts/validator/setup.sh --force

# Build Jito-Solana validator binary (takes ~7 minutes)
./scripts/validator/build.sh --force

# Upload validator keypairs to remote instance
./scripts/validator/upload-keys.sh --force
```

**Expected Output**: Remote instance configured with all dependencies, Jito validator binary compiled

#### 4. Validator Configuration & Launch
```bash
# Generate validator configuration and startup script
./scripts/validator/configure.sh --force

# Create vote account on-chain
./scripts/validator/create-vote-account.sh --force

# Start the validator
./scripts/validator/launch.sh start
```

**Expected Output**: Validator running, vote account created, catching up with network

#### 5. Monitor & Verify
```bash
# Quick status check
./scripts/utils/status.sh

# Comprehensive status with all metrics
./scripts/utils/status.sh --full

# Continuous monitoring (refreshes every 30s)
./scripts/utils/status.sh --watch

# View live validator logs
./scripts/validator/launch.sh logs --follow

# Check validator health
./scripts/validator/launch.sh health
```

**Expected Output**: Validator status showing RUNNING, vote account with credits accumulating

### Lifecycle Management

```bash
# Stop validator (validator only, instance keeps running)
./scripts/validator/launch.sh stop

# Start validator
./scripts/validator/launch.sh start

# Restart validator
./scripts/validator/launch.sh restart

# Check validator status
./scripts/validator/launch.sh status

# Stop EC2 instance (save costs, keep infrastructure)
./scripts/infra/stop.sh

# Start stopped EC2 instance
./scripts/infra/start.sh

# Check infrastructure status
./scripts/infra/status.sh

# Complete cleanup (destroy all AWS resources)
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

## Troubleshooting

### Validator Not Starting

1. **Check logs**: `./scripts/validator/launch.sh logs`
2. **Verify keypairs uploaded**: Check `~/validator/keys/` on remote instance
3. **Check vote account**: `./scripts/validator/launch.sh health`
4. **Verify RPC connectivity**: May take 5-10 minutes after startup

### Infrastructure Issues

1. **SSH connection failed**:
   - Check security group allows your IP
   - Verify instance is running: `./scripts/infra/status.sh`
   - Check SSH key permissions: `chmod 400 keys/*.pem`

2. **Terraform state issues**:
   - Ensure `terraform/terraform.tfstate` exists
   - Re-initialize if needed: `./scripts/infra/init.sh`

### Account Funding Issues

1. **Testnet faucet rate limits**:
   - The script will provide web faucet URLs as fallback
   - Use multiple faucets if one is rate-limited
   - Wait 1-2 hours between requests

2. **Insufficient balance**:
   - Vote account creation requires ~0.03 SOL
   - Validator requires minimum 5 SOL to start

### Performance Issues

1. **High disk usage**: Monitor with `./scripts/utils/status.sh --full`
2. **Slow catchup**: Normal for initial sync, check logs for progress
3. **Memory issues**: Ensure instance type has sufficient RAM (64GB+ recommended)

### Getting Help

- Check validator logs: `./scripts/validator/launch.sh logs --follow`
- Review configuration: `cat ~/validator/start-validator.sh` on remote instance
- Jito documentation: https://docs.jito.wtf/
- Solana documentation: https://docs.solana.com/

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