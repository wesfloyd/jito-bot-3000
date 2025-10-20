# Jito-Solana Testnet Automation Plan v4 (with BAM Integration)

## Technology Choice: **Terraform + Bash**

**Rationale**: Terraform is the optimal choice because:
- **Infrastructure as Code**: Declarative approach for AWS resources
- **Built-in retry logic**: Handles AWS API rate limits automatically
- **State management**: Tracks what's created/destroyed
- **Dependency resolution**: Automatically handles VPC → Subnet → Instance
- **Multi-region support**: Easy to switch regions
- **Plan before apply**: See what will be created before doing it
- **Easy cleanup**: `terraform destroy` removes everything

**Bash remains for**:
- Local key generation and management
- Remote VM setup via SSH
- Solana CLI operations
- Monitoring and health checks

---

## Architecture Overview

### New Structure
```
terraform/
├── main.tf                     # Main infrastructure configuration
├── variables.tf                # Input variables
├── outputs.tf                  # Output values
├── versions.tf                 # Provider versions
└── modules/
    └── validator/
        ├── main.tf            # Validator instance module
        ├── variables.tf       # Module variables
        └── outputs.tf         # Module outputs

scripts/
├── infra/                      # Infrastructure management (Terraform)
│   ├── init.sh                # Terraform initialization
│   ├── plan.sh                # Show planned changes
│   ├── deploy.sh              # Apply infrastructure
│   ├── start.sh               # Start stopped infrastructure
│   ├── stop.sh                # Stop infrastructure (save costs)
│   ├── status.sh              # Infrastructure status checks
│   ├── destroy.sh             # Cleanup infrastructure
│   └── README.md              # Infrastructure documentation
├── validator/                  # Validator management
│   ├── start.sh               # Start validator instance
│   ├── stop.sh                # Stop validator instance
│   └── README.md              # Validator documentation
├── utils/                      # Utilities, setup, and shared libraries
│   ├── setup/                  # Initial setup scripts
│   │   ├── local.sh           # Local prerequisites and Terraform setup
│   │   └── ssh-keys.sh        # SSH keypair generation
│   └── lib/                    # Shared libraries
│       ├── common.sh          # Shared functions, logging, error handling
│       ├── terraform-helpers.sh # Terraform-specific utilities
│       └── solana-helpers.sh  # Solana CLI wrappers
├── logs/                       # Runtime logs
│   └── deployment-{timestamp}.log
└── README.md                   # Scripts documentation

config/
├── terraform.tfvars           # Terraform variables (gitignored)
├── jito-config.env            # Jito endpoints and program IDs
├── bam-config.env             # BAM endpoints and configuration
└── validator-template.sh      # Template for validator launch script

keys/                          # Created at runtime, gitignored
├── validator-keypair.json
├── vote-account-keypair.json
└── authorized-withdrawer-keypair.json

terraform.tfstate              # Terraform state (gitignored)
terraform.tfstate.backup       # Terraform state backup (gitignored)
```

---

## Phase 1: Environment Setup (Terraform + Local)

### 1.1 Prerequisites
- [x] Install Terraform CLI (`./scripts/utils/setup/local.sh`)
- [x] Verify AWS CLI configuration
- [x] Create terraform/ directory structure
- [x] Generate SSH keys (`./scripts/utils/setup/ssh-keys.sh`)
- [x] Initialize Terraform providers (`./scripts/infra/init.sh`)

### 1.2 Terraform Configuration
- [x] Create main.tf with provider configuration
- [x] Define variables in variables.tf
- [x] Create outputs.tf for connection info
- [x] Set up terraform.tfvars for configuration

---

## Phase 2: Infrastructure Provisioning (Terraform) ✅ COMPLETED

### 2.1 Network Infrastructure
```hcl
# VPC (use default or create new)
data "aws_vpc" "default" {
  default = true
}

# Subnets (auto-select based on instance type availability)
data "aws_subnets" "available" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group
resource "aws_security_group" "jito_validator" {
  name_prefix = "jito-validator-"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    from_port   = 8000
    to_port     = 8020
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8000
    to_port     = 8020
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### 2.2 Compute Infrastructure
```hcl
# SSH Key Pair
resource "aws_key_pair" "jito_validator" {
  key_name   = var.key_name
  public_key = file("${var.keys_dir}/${var.key_name}.pub")
}

# Latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# EC2 Instance
resource "aws_instance" "jito_validator" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name              = aws_key_pair.jito_validator.key_name
  vpc_security_group_ids = [aws_security_group.jito_validator.id]
  subnet_id             = data.aws_subnets.available.ids[0]

  root_block_device {
    volume_size = var.volume_size
    volume_type = var.volume_type
    iops        = var.volume_iops
    throughput  = var.volume_throughput
  }

  tags = {
    Name        = var.instance_name
    Environment = "testnet"
    Project     = "jito-validator"
  }

  # Auto-stop tag
  dynamic "tags" {
    for_each = var.auto_stop_hours > 0 ? [1] : []
    content {
      AutoStopTime = timeadd(timestamp(), "${var.auto_stop_hours}h")
    }
  }
}
```

---

## Phase 3: Key Management (Bash) ✅ COMPLETED

### 3.1 Local Key Generation
- [x] Generate validator keypair
- [x] Generate vote account keypair
- [x] Generate authorized withdrawer keypair
- [x] Store keys securely in keys/ directory
- [x] Create `scripts/utils/generate-keys.sh` for automated key generation

---

## Phase 4: Account Funding (Bash) ✅ COMPLETED

### 4.1 Testnet SOL Funding
- [x] Create `scripts/utils/fund-accounts.sh` for SOL funding automation
- [x] Connect to testnet
- [x] Request SOL airdrop for validator account
- [x] Request SOL airdrop for vote account
- [x] Verify account balances

---

## Phase 5: Validator Setup (SSH + Bash) ✅ COMPLETED

### 5.1 Remote VM Configuration
- [x] Create `scripts/validator/setup.sh` for SSH to provisioned instance
- [x] Update system packages
- [x] Install required dependencies (Rust, build tools)
- [x] Configure system settings

### 5.2 Jito-Solana Compilation Scripts
- [x] Create `scripts/validator/build.sh` for Jito-Solana compilation
- [x] Clone Jito-Solana repository (done via build script)
- [x] Initialize Git submodules (anchor, jito-programs, jito-protos)
- [x] Update build script to use `agave-validator` binary name (v2.x change)
- [x] Build validator binary (agave-validator 2.3.13, build time: 6m35s)
- [x] Install validator binary (installed to ~/.local/bin/)
- [x] Verify installation (verified: JitoLabs client, commit 4d83054f93)

---

## Phase 6: Validator Configuration (Bash)

### 6.1 Keypair Upload
- [x] Create `scripts/validator/upload-keys.sh` for keypair upload
- [x] Upload validator identity keypair (2wZd77kQgoHPPoCgJmgPDa5q1TFVzSJnhjMcnxgFfepg)
- [x] Upload vote account keypair (6Vmd8LLb61dgdjwipfvhmEYo2jF3FNqWzGyQPCMciGtj)
- [x] Set secure permissions (600) on remote keypairs
- [x] Verify keypairs on remote instance

### 6.2 Configuration Generation
- [x] Create `scripts/validator/configure.sh` for configuration generation
- [x] Generate validator startup script (~/validator/start-validator.sh)
- [x] Configure Jito endpoints (block-engine, relayer, shred-receiver)
- [x] Configure RPC endpoints (testnet)
- [x] Set up logging configuration
- [x] Configure performance settings
- [x] Create systemd service (jito-validator.service)

### 6.3 Vote Account Creation
- [x] Create `scripts/validator/create-vote-account.sh` for vote account setup
- [x] Cleanup existing regular account at vote keypair address
- [x] Create vote account on-chain (commission: 10%)
- [x] Link validator identity to vote account
- [x] Verify vote account creation (balance: 0.0270744 SOL)

---

## Phase 7: Validator Launch (Bash) ✅ COMPLETED

### 7.1 Validator Startup
- [x] Create `scripts/validator/launch.sh` for validator startup
- [x] Start validator service
- [x] Verify validator is running
- [x] Check validator logs
- [x] Monitor validator health

### 7.2 Implementation Details
- **Script**: `scripts/validator/launch.sh` - Comprehensive validator lifecycle management
- **Commands Implemented**:
  - `start` - Start validator (systemd or direct script)
  - `stop` - Stop validator gracefully
  - `restart` - Restart validator
  - `status` - Show validator process status and recent logs
  - `logs` - View validator logs (with --follow for real-time)
  - `health` - Comprehensive health checks (RPC, vote account)
- **Features**:
  - SSH connection via Terraform state
  - Both systemd and direct script execution modes
  - Process monitoring and uptime tracking
  - RPC health endpoint checks
  - Vote account status verification
  - Real-time log tailing support

### 7.3 Validator Status (2025-10-20)
- **Validator Process**: Running (agave-validator 2.3.13)
- **Validator Identity**: 2wZd77kQgoHPPoCgJmgPDa5q1TFVzSJnhjMcnxgFfepg
- **Vote Account**: 6Vmd8LLb61dgdjwipfvhmEYo2jF3FNqWzGyQPCMciGtj (Active, 10% commission)
- **Network**: Testnet, Jito-enabled with MEV integration
- **Ports**: UDP/TCP 8000-8020 configured and reachable

---

## Phase 8: Monitoring & Management (Bash) ✅ COMPLETED

### 8.1 Health Monitoring
- [x] Create `scripts/utils/status.sh` for health checks
- [x] Implement health checks
- [x] Set up log monitoring
- [x] Create status dashboard
- [x] Implement alerting (via log analysis)

### 8.2 Lifecycle Management
- [x] Start/stop validator (via `launch.sh`)
- [x] Restart validator (via `launch.sh`)
- [x] Update validator (manual process documented)
- [x] Cleanup resources (via infrastructure scripts)

### 8.3 Documentation
- [x] Update README.md with comprehensive getting started guide
  - [x] Prerequisites (AWS CLI, Terraform, Solana CLI)
  - [x] Step-by-step script execution order (complete end-to-end workflow)
  - [x] Manual steps required (all automated with --force flags)
  - [x] Expected outputs at each phase
  - [x] Troubleshooting common issues

### 8.4 Implementation Summary

**Status Monitoring Script**: `scripts/utils/status.sh`
- **Quick Mode** (`--quick`): Fast overview of validator status
- **Full Mode** (`--full`): Comprehensive metrics including:
  - Infrastructure status (AWS instance details)
  - Validator process info (PID, uptime, CPU, memory)
  - Vote account status (balance, credits, commission)
  - RPC endpoint health
  - Network connectivity (Testnet RPC, Jito Block Engine)
  - Disk usage monitoring
  - Log analysis (errors, warnings, line counts)
  - Quick action commands
- **Watch Mode** (`--watch`): Continuous monitoring with 30s refresh

**Lifecycle Management**: All functionality implemented in `scripts/validator/launch.sh`
- Start/stop/restart validator
- Status checks and health monitoring
- Log viewing (live tail support)
- Both systemd and direct script execution modes

**Documentation**: `README.md` updated with:
- Complete end-to-end deployment workflow
- Prerequisites and setup instructions
- Infrastructure deployment steps
- Validator configuration and launch
- Monitoring and verification commands
- Lifecycle management commands
- Comprehensive troubleshooting section
- Expected outputs at each phase

---

## Phase 9: BAM Configuration ⏳ IN PROGRESS

### 9.1 Prerequisites Check
- [x] Check available disk space (RPC tx history requires additional storage)
  - ✅ 2TB total, 11GB used (1%) - **plenty of space for RPC history**
  - Validator directories still initializing (catchup in progress)
- [ ] Verify validator is fully operational on testnet (BLOCKED: validator catching up)
- [ ] Confirm validator has stake and receives leader slots (BLOCKED: testnet, 0 stake)

### 9.2 Configuration File
- [x] Create `config/bam-config.env` with BAM endpoints and credentials
  - BAM URL: `http://ny.testnet.bam.jito.wtf`
  - Metrics: `http://bam-public-metrics.jito.wtf:8086`
  - Database: `testnet-bam-validators`
  - Default: `ENABLE_BAM="false"` (toggle to enable)

### 9.3 Validator Configuration Script
- [x] Create `scripts/validator/configure-bam.sh`
  - Automated prerequisite checks (validator running, catchup status, disk space)
  - Leader schedule verification (warning only on testnet)
  - BAM flag injection into startup script
  - Enable/disable toggle: `--enable` / `--disable` flags
  - Force mode: `--force` to bypass catchup checks
  - Automatic backup of existing configuration
- [ ] Execute script to enable BAM (BLOCKED: waiting for validator catchup)

---

## Phase 10: BAM Integration

### 10.1 Update Validator Launch Configuration
- [ ] Modify `scripts/validator/configure.sh` to add BAM flags conditionally
- [ ] Add `--bam-url http://ny.testnet.bam.jito.wtf`
- [ ] Add `--enable-rpc-transaction-history`
- [ ] Add metrics export if enabled:
```bash
export SOLANA_METRICS_CONFIG="host=${BAM_METRICS_HOST},db=${BAM_METRICS_DB},u=${BAM_METRICS_USER},p=${BAM_METRICS_PASSWORD}"
```

### 10.2 Enable/Disable Toggle
- [ ] Add environment variable `ENABLE_BAM` (default: false)
- [ ] Implement conditional BAM flags in startup script
- [ ] Test validator startup with BAM disabled (default)
- [ ] Test validator startup with BAM enabled

### 10.3 Deploy BAM Configuration
- [ ] Restart validator with BAM flags enabled
- [ ] Monitor logs for BAM connection messages
- [ ] Verify BAM endpoint connectivity

---

## Phase 11: BAM Monitoring & Validation

### 11.1 Connection Verification
- [ ] Create `scripts/utils/verify-bam.sh`
- [ ] Check BAM node connectivity (`http://ny.testnet.bam.jito.wtf`)
- [ ] Verify metrics submission to BAM infrastructure
- [ ] Monitor validator logs for BAM connection status

### 11.2 Status Script Updates
- [ ] Update `scripts/utils/status.sh` with BAM checks:
  - [ ] BAM connection status
  - [ ] BAM endpoint health
  - [ ] Metrics reporting status
  - [ ] Leader slot utilization

### 11.3 Monitoring & Alerts
- [ ] Track BAM-specific performance metrics
- [ ] Monitor disk usage (RPC transaction history)
- [ ] Set up alerts for BAM disconnections
- [ ] Document BAM connection issues in logs

### 11.4 Documentation
- [ ] Update README.md with BAM enable/disable instructions
- [ ] Document BAM troubleshooting steps
- [ ] Add BAM-specific health checks to troubleshooting guide

---

## References

- **BAM Documentation**: https://bam.dev/validators/
- **BAM Client Repository**: https://github.com/jito-labs/bam-client
- **Jito-Solana Repository**: https://github.com/jito-foundation/jito-solana
- **Jito Official Docs**: https://docs.jito.wtf/
