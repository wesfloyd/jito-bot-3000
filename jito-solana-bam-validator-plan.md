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

## Phase 5: Validator Setup (SSH + Bash)

### 5.1 Remote VM Configuration
- [ ] Create `scripts/validator/setup.sh` for SSH to provisioned instance
- [ ] Update system packages
- [ ] Install required dependencies (Rust, build tools)
- [ ] Configure system settings

### 5.2 Jito-Solana Compilation
- [ ] Create `scripts/validator/build.sh` for Jito-Solana compilation
- [ ] Clone Jito-Solana repository
- [ ] Build validator binary
- [ ] Install validator binary
- [ ] Verify installation

---

## Phase 6: Validator Configuration (Bash)

### 6.1 Configuration Generation
- [ ] Create `scripts/validator/configure.sh` for configuration generation
- [ ] Generate validator.sh script from template
- [ ] Configure RPC endpoints
- [ ] Set up logging configuration
- [ ] Configure performance settings

---

## Phase 7: Validator Launch (Bash)

### 7.1 Validator Startup
- [ ] Create `scripts/validator/launch.sh` for validator startup
- [ ] Start validator service
- [ ] Verify validator is running
- [ ] Check validator logs
- [ ] Monitor validator health

---

## Phase 8: Monitoring & Management (Bash)

### 8.1 Health Monitoring
- [ ] Create `scripts/utils/status.sh` for health checks
- [ ] Implement health checks
- [ ] Set up log monitoring
- [ ] Create status dashboard
- [ ] Implement alerting

### 8.2 Lifecycle Management
- [ ] Start/stop validator
- [ ] Restart validator
- [ ] Update validator
- [ ] Cleanup resources

---

## Phase 9: BAM Integration (Block Assembly Marketplace)

### 9.1 What is BAM?

**BAM (Block Assembly Marketplace)** is Jito's next-generation block building system that brings private, verifiable block construction to Solana. BAM introduces trusted execution environments (TEEs) and attestations to enable tamper-proof transaction ordering, protecting against MEV and mempool attacks.

**Key Benefits:**
- **Private Transaction Ordering**: Transactions are processed in a secure, private environment
- **Verifiable Block Building**: Cryptographic attestations prove blocks were built correctly
- **Enhanced Security**: TEE-based architecture prevents manipulation
- **Programmable Sequencing**: Future support for custom ordering logic

### 9.2 BAM Architecture Overview

BAM consists of two main components:

1. **BAM Nodes**: Off-chain block builders running in Trusted Execution Environments (TEEs)
   - Receive transactions from searchers and users
   - Assemble blocks according to specified rules
   - Provide cryptographic attestations of proper execution
   - Send ordered transaction bundles to validators

2. **BAM Validators**: On-chain validators running updated Jito-Solana client
   - Receive ordered transactions from BAM Nodes
   - Execute transactions as instructed
   - Must be in the leader schedule to participate
   - Report metrics back to BAM infrastructure

---

## Phase 10: BAM Testnet Enablement

### 10.1 BAM Testnet Status

**Current Status (as of January 2025):**
- ✅ BAM is **LIVE on testnet**
- ✅ Initial set of validators running BAM client
- ⏳ Public testnet access coming soon
- ⏳ Mainnet deployment planned after testnet validation

**Important Notes:**
- BAM testnet is currently running with an initial validator cluster
- Public testnet participation will open soon
- Mainnet deployment will follow testnet validation
- Validators must be in the leader schedule to connect to BAM

### 10.2 Prerequisites for BAM Integration

Before enabling BAM, ensure:
- [ ] Jito-Solana validator is fully operational on testnet
- [ ] Validator is in the leader schedule (BAM only connects to scheduled leaders)
- [ ] Sufficient stake to receive leader slots regularly
- [ ] RPC transaction history enabled on the validator
- [ ] Network connectivity to BAM nodes

### 10.3 BAM Configuration Requirements

To enable BAM on your Jito-Solana validator, you must add **two mandatory flags**:

#### Required Configuration Flags

```bash
# 1. BAM Node Connection
--bam-url http://ny.testnet.bam.jito.wtf

# 2. Enable RPC Transaction History (required for fee payment confirmation)
--enable-rpc-transaction-history
```

#### Optional: Metrics Collection

To enable metrics reporting to BAM infrastructure:

```bash
# Export metrics configuration
export SOLANA_METRICS_CONFIG="host=http://bam-public-metrics.jito.wtf:8086,db=testnet-bam-validators,u=testnet-bam-validator,p=wambamdamn"
```

### 10.4 Implementation Steps

#### Step 1: Create BAM Configuration File
- [ ] Create `config/bam-config.env` with BAM-specific settings
```bash
# config/bam-config.env
BAM_URL="http://ny.testnet.bam.jito.wtf"
BAM_METRICS_HOST="http://bam-public-metrics.jito.wtf:8086"
BAM_METRICS_DB="testnet-bam-validators"
BAM_METRICS_USER="testnet-bam-validator"
BAM_METRICS_PASSWORD="wambamdamn"
```

#### Step 2: Update Validator Launch Script
- [ ] Modify `scripts/validator/launch.sh` or validator template to include BAM flags
- [ ] Add conditional logic to enable/disable BAM via environment variable
```bash
# Example addition to validator launch script
if [ "${ENABLE_BAM}" = "true" ]; then
  BAM_FLAGS="--bam-url ${BAM_URL} --enable-rpc-transaction-history"

  # Set metrics if configured
  if [ -n "${BAM_METRICS_HOST}" ]; then
    export SOLANA_METRICS_CONFIG="host=${BAM_METRICS_HOST},db=${BAM_METRICS_DB},u=${BAM_METRICS_USER},p=${BAM_METRICS_PASSWORD}"
  fi
else
  BAM_FLAGS=""
fi
```

#### Step 3: Update Validator Configuration Script
- [ ] Create `scripts/validator/configure-bam.sh` for BAM-specific configuration
- [ ] Add logic to check validator is in leader schedule before enabling BAM
- [ ] Validate RPC transaction history requirements

#### Step 4: Enable RPC Transaction History
- [ ] Ensure validator has sufficient storage for transaction history
  - Transaction history can consume significant disk space
  - Consider adding `--enable-extended-tx-metadata-storage` for full history
- [ ] Update root_block_device size in Terraform if needed
- [ ] Monitor disk usage after enabling

#### Step 5: Verify BAM Connection
- [ ] Create `scripts/utils/verify-bam.sh` for BAM connectivity checks
- [ ] Check validator logs for BAM connection messages
- [ ] Verify metrics are being reported (if configured)
- [ ] Monitor for BAM-related errors

---

## Phase 11: BAM Monitoring & Validation

### 11.1 BAM Health Checks
- [ ] Add BAM connection status to `scripts/utils/status.sh`
- [ ] Monitor BAM node connectivity
- [ ] Track transaction processing through BAM
- [ ] Verify block building attestations

### 11.2 BAM Metrics Monitoring
- [ ] Monitor metrics submissions to BAM infrastructure
- [ ] Track BAM-specific performance metrics
- [ ] Set up alerts for BAM disconnections
- [ ] Monitor leader slot utilization with BAM

### 11.3 BAM Troubleshooting
- [ ] Document common BAM connection issues
- [ ] Create debug script for BAM problems
- [ ] Add BAM-specific logging
- [ ] Monitor for validator consensus with BAM blocks

---

## Assessment: BAM Integration Feasibility

### Is BAM Available on Testnet?

**✅ YES** - BAM is currently live on testnet with an initial validator cluster.

**Status:**
- Currently in limited testnet with initial validators
- Public testnet access coming soon
- Requires being in leader schedule to participate
- Mainnet deployment planned after testnet validation

### Are the Instructions Sufficient?

**⚠️ PARTIALLY SUFFICIENT** - The available documentation provides the core configuration requirements but lacks some details:

**What We Know:**
- ✅ Required flags: `--bam-url` and `--enable-rpc-transaction-history`
- ✅ Testnet BAM URL: `http://ny.testnet.bam.jito.wtf`
- ✅ Metrics configuration format
- ✅ Prerequisite: Must be in leader schedule

**What's Missing/Unclear:**
- ❓ Detailed bam-client repository documentation (requires direct GitHub access)
- ❓ Minimum stake requirements for consistent leader slots
- ❓ Storage requirements for RPC transaction history on testnet
- ❓ Process for joining public testnet when it opens
- ❓ Expected behavior/logs when BAM is properly connected
- ❓ Troubleshooting guide for BAM connection issues

### Recommendations

1. **For Immediate Testing:**
   - Follow the configuration steps in Phase 10
   - Add the two required flags to validator launch
   - Monitor logs for BAM connection attempts
   - Verify validator is getting leader slots

2. **For Production Readiness:**
   - Wait for public testnet announcement
   - Review official bam-client documentation when accessible
   - Test with sufficient stake for regular leader slots
   - Implement comprehensive monitoring before enabling on mainnet

3. **Additional Research Needed:**
   - Access https://github.com/jito-labs/bam-client for detailed docs
   - Join Jito Discord/community for BAM testnet updates
   - Monitor https://bam.dev/validators/ for updated documentation
   - Review Jito-Solana changelog for BAM-related updates

---

## Next Steps

1. Complete Phases 4-8 to get a fully operational Jito-Solana validator
2. Ensure validator receives regular leader slots (sufficient stake)
3. Monitor for public BAM testnet announcement
4. Implement BAM configuration (Phase 10) when testnet access is available
5. Validate BAM integration on testnet before considering mainnet

---

## References

- **BAM Documentation**: https://bam.dev/validators/
- **BAM Client Repository**: https://github.com/jito-labs/bam-client
- **Jito-Solana Docs**: https://jito-foundation.gitbook.io/mev/
- **Jito-Solana Repository**: https://github.com/jito-foundation/jito-solana
- **Jito Official Docs**: https://docs.jito.wtf/
