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

## Phase 9: BAM Client Migration (Testnet) 🔄 IN PROGRESS

### Strategy Update (2025-10-21)
**Revised Approach**: Replace jito-solana with bam-client binary
- ❌ **Original plan**: Add `--bam-url` flag to existing jito-solana binary
- ✅ **New plan**: Build and install bam-client (v3.0.6-bam) which includes BAM support
- **Reason**: The `--bam-url` flag only exists in jito-labs/bam-client fork, not jito-foundation/jito-solana

### 9.1 Architecture Decision
**Single Instance, Binary Replacement Approach**:
- ✅ Replace existing agave-validator binary with BAM-enabled version
- ✅ Reuse existing validator identity, vote account, and ledger data
- ✅ Cost-efficient: No second EC2 instance needed
- ✅ BAM client includes all Jito MEV features + BAM capabilities
- ✅ Same configuration files, just different binary

**Repository Change**:
- **Old**: `https://github.com/jito-foundation/jito-solana` (v3.0.6-jito)
- **New**: `https://github.com/jito-labs/bam-client` (v3.0.6-bam)

### 9.2 Prerequisites Verification
- [x] Check available disk space (RPC tx history requires additional storage)
  - ✅ 2TB total, 11GB used (1%) - **plenty of space for RPC history**
- [x] Verify validator is fully operational on testnet
  - ✅ Validator caught up and voting on slot 365156866
  - ✅ Processing transactions normally
  - ✅ Vote account active with 34,209 credits
- [x] Confirm validator stake status (expected: 0 SOL on testnet - no leader slots)
  - ✅ Verified: No stake accounts found (expected on testnet)
  - ⚠️ Without stake: BAM will show "not in leader schedule" (expected)
  - ℹ️ This is OK for dry run configuration testing

### 9.3 Build Script Updates
- [x] **Updated `scripts/validator/build.sh`** to use bam-client repository
  - Changed repository URL from jito-foundation/jito-solana to jito-labs/bam-client
  - Updated default version from v2.1.3-jito to v3.0.6-bam
  - Added automatic backup of existing agave-validator binary
  - Added verification step to confirm `--bam-url` flag is available
  - Updated all documentation and help text

### 9.4 Validator Startup Script Updates
- [x] **Backup current configuration**
  - Created: `~/validator/start-validator.sh.pre-bam`

- [x] **Updated `~/validator/start-validator.sh`** with BAM configuration
  - Added BAM URL: `--bam-url http://ny.testnet.bam.jito.wtf`
  - Added RPC history: `--enable-rpc-transaction-history`
  - Added metrics: `export SOLANA_METRICS_CONFIG="host=http://bam-public-metrics.jito.wtf:8086,db=testnet-bam-validators,u=testnet-bam-validator,p=wambamdamn"`
  - Updated startup message to indicate BAM is enabled

### 9.5 BAM Client Build (In Progress)
- [x] **Initiated build**: `./scripts/validator/build.sh --force`
  - Building version: v3.0.6-bam
  - Repository: jito-labs/bam-client
  - Status: Cloning and building (~20-30 minutes)
  - Automatic binary backup created before replacement

**Check build status**:
```bash
# Check if build is still running
ps aux | grep "scripts/validator/build.sh"

# Or check validator build progress on EC2 instance
ssh -i keys/jito-validator-key.pem ubuntu@54.215.235.126 "ps aux | grep 'cargo build'"
```

### 9.6 Next Steps (After Build Completes)
- [ ] **Verify build success**
  ```bash
  ssh -i keys/jito-validator-key.pem ubuntu@54.215.235.126 "agave-validator --version"
  # Expected: agave-validator with "bam" in version string
  ```

- [ ] **Verify BAM flag support**
  ```bash
  ssh -i keys/jito-validator-key.pem ubuntu@54.215.235.126 "agave-validator --help | grep bam-url"
  # Expected: --bam-url flag should be present
  ```

- [ ] **Restart validator with BAM configuration**
  ```bash
  ssh -i keys/jito-validator-key.pem ubuntu@54.215.235.126 "sudo systemctl restart jito-validator"
  ```

- [ ] **Monitor logs for BAM-related messages**
  ```bash
  ssh -i keys/jito-validator-key.pem ubuntu@54.215.235.126 "tail -f ~/validator/logs/validator-*.log | grep -i bam"
  # Expected: BAM connection attempts, no errors
  # Expected: "Not in leader schedule" is normal without stake
  ```

- [ ] **Verify validator stability**
  ```bash
  ./scripts/validator/launch.sh status
  # Should show validator running normally with BAM flags
  ```

---

## Phase 10: BAM Integration Validation

### 10.1 Configuration Verification (15-30 minutes)
- [ ] Verify validator accepts BAM flags without errors
  ```bash
  # Check validator process started successfully
  sudo systemctl status jito-validator

  # Verify BAM flags in process arguments
  ps aux | grep agave-validator | grep -o 'bam-url'
  ```

- [ ] Check BAM endpoint connectivity
  ```bash
  # Test BAM endpoint is reachable
  curl -I http://ny.testnet.bam.jito.wtf

  # Expected: HTTP 200 or redirect (confirms endpoint exists)
  ```

- [ ] Verify RPC transaction history is enabled
  ```bash
  # Check validator logs for RPC history messages
  grep "enable-rpc-transaction-history" ~/validator/logs/validator-*.log
  ```

### 10.2 Expected Outcomes (Without Leader Slots)
**What WILL work** (configuration validation):
- ✅ BAM flags accepted without errors
- ✅ Validator starts and runs normally
- ✅ BAM endpoint connectivity confirmed
- ✅ RPC transaction history enabled
- ✅ Metrics potentially being sent to BAM infrastructure

**What WON'T work** (requires stake):
- ❌ Won't produce BAM blocks (not in leader schedule)
- ❌ Won't receive BAM block assembly requests
- ⚠️ "Not in leader schedule" messages are EXPECTED

### 10.3 Automation Script (Optional)
- [ ] Create `scripts/validator/configure-bam.sh` for automated BAM setup
  - Automated prerequisite checks (validator running, disk space)
  - Leader schedule verification (warning only on testnet)
  - BAM flag injection into startup script
  - Enable/disable toggle: `--enable` / `--disable` flags
  - Force mode: `--force` to bypass checks
  - Automatic backup of existing configuration

---

## Phase 11: BAM Monitoring & Production Readiness

### 11.1 Dry Run Results Analysis
- [ ] Document BAM connection attempts in logs
  ```bash
  # Extract BAM-related log messages
  grep -i bam ~/validator/logs/validator-*.log | tail -50
  ```

- [ ] Verify no errors related to BAM configuration
  ```bash
  # Check for BAM errors
  grep -i "bam.*error\|bam.*failed" ~/validator/logs/validator-*.log
  ```

- [ ] Confirm validator stability with BAM flags
  ```bash
  # Validator should remain stable and voting
  solana catchup <validator-identity> -ut
  solana vote-account <vote-account> -ut
  ```

### 11.2 Leader Schedule Path (Future - Requires Stake)
**For actual BAM block production, you would need**:
- [ ] Request testnet stake delegation from Solana Foundation
- [ ] Wait for epoch boundary (stake activation)
- [ ] Receive leader slots → BAM will connect
- [ ] Produce BAM blocks with verifiable execution

**Alternative paths to test BAM block production**:
1. **Mainnet** (not recommended for testing):
   - Requires significant SOL stake (~10,000+ SOL)
   - High cost, production environment

2. **Solana Foundation Testnet Delegation**:
   - Apply for testnet stake delegation
   - May take days/weeks to receive
   - Free, but requires application process

3. **Local Network with Stake** (complex):
   - Set up local Solana cluster
   - Configure your own BAM infrastructure
   - Much more complex than testnet

### 11.3 Status Monitoring Updates
- [ ] Update `scripts/utils/status.sh` with BAM checks:
  ```bash
  # Add to status.sh:
  - BAM configuration status (enabled/disabled)
  - BAM endpoint connectivity
  - RPC transaction history status
  - Leader slot count (if any)
  - BAM-specific metrics (if available)
  ```

### 11.4 Documentation
- [ ] Document BAM dry run results in README.md
- [ ] Add BAM troubleshooting section:
  - "Not in leader schedule" - expected without stake
  - BAM endpoint connectivity issues
  - RPC transaction history disk usage
  - Metrics submission verification
- [ ] Create BAM testing summary:
  - What was tested (dry run configuration)
  - What worked (configuration acceptance)
  - What's blocked (block production requires stake)
  - Next steps (stake delegation or mainnet)

### 11.5 Production Readiness Checklist
**For moving BAM to mainnet**:
- [ ] Dry run on testnet successful ✅
- [ ] No configuration errors ✅
- [ ] BAM endpoint connectivity verified ✅
- [ ] Validator stable with BAM flags ✅
- [ ] Sufficient disk space for RPC history ✅
- [ ] Monitoring and alerts configured
- [ ] Stake acquisition plan (mainnet requires real SOL)
- [ ] Backup and recovery procedures tested

---

## References

- **BAM Documentation**: https://bam.dev/validators/
- **BAM Client Repository**: https://github.com/jito-labs/bam-client
- **Jito-Solana Repository**: https://github.com/jito-foundation/jito-solana
- **Jito Official Docs**: https://docs.jito.wtf/
