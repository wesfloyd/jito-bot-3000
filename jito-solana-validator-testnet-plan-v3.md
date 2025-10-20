# Jito-Solana Testnet Automation Plan v3

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
├── 00-setup-local.sh           # Local prerequisites and Terraform setup
├── 01-terraform-init.sh        # Terraform initialization
├── 02-terraform-plan.sh        # Show planned changes
├── 03-terraform-apply.sh       # Apply infrastructure
├── 04-generate-keys.sh         # Keypair generation (local)
├── 05-fund-accounts.sh         # Testnet SOL funding automation
├── 06-setup-validator.sh       # Remote VM setup via SSH
├── 07-build-jito.sh           # Jito-Solana compilation on VM
├── 08-configure-validator.sh   # Generate validator.sh script
├── 09-launch-validator.sh      # Start validator and verify
├── 10-monitor.sh              # Health checks and monitoring
├── 11-terraform-destroy.sh    # Cleanup infrastructure
└── lib/
    ├── common.sh              # Shared functions, logging, error handling
    ├── terraform-helpers.sh   # Terraform-specific utilities
    └── solana-helpers.sh      # Solana CLI wrappers

config/
├── terraform.tfvars           # Terraform variables (gitignored)
├── jito-config.env            # Jito endpoints and program IDs
└── validator-template.sh      # Template for validator launch script

keys/                          # Created at runtime, gitignored
├── validator-keypair.json
├── vote-account-keypair.json
└── authorized-withdrawer-keypair.json

logs/                          # Created at runtime
└── deployment-{timestamp}.log

terraform.tfstate              # Terraform state (gitignored)
terraform.tfstate.backup       # Terraform state backup (gitignored)
```

---

## Phase 1: Environment Setup (Terraform + Local)

### 1.1 Prerequisites
- [ ] Install Terraform CLI
- [ ] Verify AWS CLI configuration
- [ ] Create terraform/ directory structure
- [ ] Initialize Terraform providers

### 1.2 Terraform Configuration
- [ ] Create main.tf with provider configuration
- [ ] Define variables in variables.tf
- [ ] Create outputs.tf for connection info
- [ ] Set up terraform.tfvars for configuration

---

## Phase 2: Infrastructure Provisioning (Terraform)

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

## Phase 3: Key Management (Bash)

### 3.1 Local Key Generation
- [ ] Generate validator keypair
- [ ] Generate vote account keypair  
- [ ] Generate authorized withdrawer keypair
- [ ] Store keys securely in keys/ directory

---

## Phase 4: Account Funding (Bash)

### 4.1 Testnet SOL Funding
- [ ] Connect to testnet
- [ ] Request SOL airdrop for validator account
- [ ] Request SOL airdrop for vote account
- [ ] Verify account balances

---

## Phase 5: Validator Setup (SSH + Bash)

### 5.1 Remote VM Configuration
- [ ] SSH to provisioned instance
- [ ] Update system packages
- [ ] Install required dependencies (Rust, build tools)
- [ ] Configure system settings

### 5.2 Jito-Solana Compilation
- [ ] Clone Jito-Solana repository
- [ ] Build validator binary
- [ ] Install validator binary
- [ ] Verify installation

---

## Phase 6: Validator Configuration (Bash)

### 6.1 Configuration Generation
- [ ] Generate validator.sh script from template
- [ ] Configure RPC endpoints
- [ ] Set up logging configuration
- [ ] Configure performance settings

---

## Phase 7: Validator Launch (Bash)

### 7.1 Validator Startup
- [ ] Start validator service
- [ ] Verify validator is running
- [ ] Check validator logs
- [ ] Monitor validator health

---

## Phase 8: Monitoring & Management (Bash)

### 8.1 Health Monitoring
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

## Migration Tasks

### Task 1: Create Terraform Infrastructure
- [ ] Create terraform/ directory
- [ ] Write main.tf with provider configuration
- [ ] Create variables.tf with all necessary variables
- [ ] Create outputs.tf for connection information
- [ ] Create terraform.tfvars.example

### Task 2: Update Scripts
- [ ] Modify 01-provision-aws.sh to use Terraform
- [ ] Create 01-terraform-init.sh
- [ ] Create 02-terraform-plan.sh
- [ ] Create 03-terraform-apply.sh
- [ ] Create 11-terraform-destroy.sh

### Task 3: Update Configuration
- [ ] Create terraform.tfvars from aws-config.env
- [ ] Update .gitignore for Terraform files
- [ ] Create terraform-helpers.sh library

### Task 4: Clean Up Old Code
- [ ] Remove aws-helpers.sh (replace with Terraform)
- [ ] Update common.sh to work with Terraform
- [ ] Remove manual AWS CLI provisioning logic

### Task 5: Testing & Validation
- [ ] Test Terraform plan
- [ ] Test Terraform apply
- [ ] Test Terraform destroy
- [ ] Validate all scripts work together

---

## Benefits of Terraform Approach

### Reliability
- ✅ Built-in retry logic for AWS API calls
- ✅ Proper dependency management
- ✅ State consistency checks
- ✅ Rollback capabilities

### Maintainability
- ✅ Declarative configuration
- ✅ Version control for infrastructure
- ✅ Easy to modify and extend
- ✅ Industry standard practices

### Flexibility
- ✅ Easy region switching
- ✅ Multiple environment support
- ✅ Module-based architecture
- ✅ Resource tagging and organization

---

## Next Steps

1. **Create Terraform configuration files**
2. **Update existing scripts to use Terraform**
3. **Test the complete workflow**
4. **Document the new process**

This approach will be much more robust and maintainable than the previous bash-only approach! 🚀
