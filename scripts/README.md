# Scripts Directory

This directory contains all automation scripts organized by functionality.

## 📁 Directory Structure

### `infra/` - Infrastructure Management
Scripts for managing AWS infrastructure using Terraform.

- `init.sh` - Initialize Terraform (download providers, validate config)
- `plan.sh` - Show planned infrastructure changes
- `deploy.sh` - Deploy infrastructure to AWS
- `start.sh` - Start stopped infrastructure (resume compute costs)
- `stop.sh` - Stop infrastructure (pause compute costs)
- `destroy.sh` - Completely destroy infrastructure

### `validator/` - Validator Management
Scripts for managing the Solana validator instance.

- `start.sh` - Start validator instance
- `stop.sh` - Stop validator instance

### `utils/` - Utilities and Setup
Helper scripts, setup tools, and shared libraries.

**Setup Scripts:**
- `setup/local.sh` - Install local prerequisites (Terraform, AWS CLI)
- `setup/ssh-keys.sh` - Generate SSH key pairs for AWS access

**Utility Scripts:**
- `status.sh` - Check infrastructure and validator status

**Shared Libraries:**
- `lib/common.sh` - Shared utilities, logging, error handling
- `lib/terraform-helpers.sh` - Terraform-specific functions
- `lib/solana-helpers.sh` - Solana CLI wrappers

## 🚀 Quick Start Workflow

```bash
# 1. Setup (first time only)
./scripts/utils/setup/local.sh
./scripts/utils/setup/ssh-keys.sh

# 2. Deploy infrastructure
./scripts/infra/init.sh
./scripts/infra/plan.sh
./scripts/infra/deploy.sh

# 3. Manage infrastructure
./scripts/utils/status.sh
./scripts/infra/stop.sh    # Save costs
./scripts/infra/start.sh   # Resume costs

# 4. Cleanup when done
./scripts/infra/destroy.sh
```

## 💡 Best Practices

- **Always run `plan.sh`** before `deploy.sh` to review changes
- **Use `stop.sh`** to pause compute costs when not actively testing
- **Use `destroy.sh`** for complete cleanup when finished
- **Check `status.sh`** to verify everything is working correctly
