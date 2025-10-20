# Jito-Solana Testnet Automation Plan

## Technology Choice: **Bash**

**Rationale**: Bash is the optimal choice because:
- 90% of workflow is CLI command orchestration (AWS CLI, Solana CLI, SSH)
- Minimal dependencies (bash, AWS CLI, SSH - standard on most systems)
- Natural fit for infrastructure provisioning and remote system administration
- Faster development with less boilerplate
- Easy debugging and manual testing of individual commands

**Alternative**: TypeScript could be added later for web UI, complex retry logic, or multi-validator state management, but bash is ideal for the core automation.

---

## Architecture Overview

### Script Structure
```
scripts/
├── 00-setup-local.sh           # Local prerequisites and AWS CLI setup
├── 01-provision-aws.sh         # EC2 instance provisioning
├── 02-generate-keys.sh         # Keypair generation (local)
├── 03-fund-accounts.sh         # Testnet SOL funding automation
├── 04-setup-validator.sh       # Remote VM setup via SSH
├── 05-build-jito.sh           # Jito-Solana compilation on VM
├── 06-configure-validator.sh   # Generate validator.sh script
├── 07-launch-validator.sh      # Start validator and verify
├── 08-monitor.sh              # Health checks and monitoring
└── lib/
    ├── common.sh              # Shared functions, logging, error handling
    ├── aws-helpers.sh         # AWS-specific utilities
    └── solana-helpers.sh      # Solana CLI wrappers

config/
├── aws-config.env             # AWS instance specs, region, etc.
├── jito-config.env            # Jito endpoints and program IDs
└── validator-template.sh      # Template for validator launch script

keys/                          # Created at runtime, gitignored
├── validator-keypair.json
├── vote-account-keypair.json
└── authorized-withdrawer-keypair.json

logs/                          # Created at runtime
└── deployment-{timestamp}.log
```

---

## Implementation Details

### Logging System

**Chosen approach: `tput` for colored terminal output**

Rationale:
- Pre-installed on virtually all Unix systems (part of ncurses)
- More portable across different terminal types than raw ANSI codes
- Gracefully degrades when colors aren't supported
- Zero external dependencies
- Industry standard (used by Homebrew, Docker installers, Kubernetes scripts)

Implementation in `scripts/lib/common.sh`:
```bash
# Initialize colors using tput
if command -v tput >/dev/null 2>&1 && tput setaf 1 >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    RESET=$(tput sgr0)
else
    # Fallback to no colors if tput unavailable
    RED="" GREEN="" YELLOW="" BLUE="" RESET=""
fi
```

All scripts use consistent logging functions:
- `log_info()` - Blue, general information
- `log_success()` - Green, successful operations
- `log_warn()` - Yellow, warnings
- `log_error()` - Red, errors (outputs to stderr)
- `log_section()` - Bold cyan headers for major sections

### Auto-Stop Functionality

**Purpose**: Prevent accidentally leaving expensive EC2 instances running during testnet testing

**Implementation approach**: Hybrid scheduling + manual controls

#### Option 1: Scheduled Auto-Stop (Default)
- Set `AUTO_STOP_HOURS` in `config/aws-config.env`
- During deployment, schedule instance stop time is tagged on the EC2 instance
- AWS tag: `AutoStopTime=2025-10-20T16:00:00Z`
- Monitoring script checks tag and warns when approaching stop time
- Manual override always available via stop/start scripts

#### Option 2: Manual Control Scripts
- `scripts/stop-validator.sh` - Stops EC2 instance (preserves EBS volumes)
- `scripts/start-validator.sh` - Restarts stopped instance
- `scripts/get-status.sh` - Shows instance status, uptime, and estimated costs

#### Implementation in `scripts/lib/aws-helpers.sh`:
```bash
schedule_instance_stop() {
    local instance_id=$1
    local hours=$2

    # Calculate stop time
    stop_time=$(date -u -d "+${hours} hours" '+%Y-%m-%dT%H:%M:%S')

    # Tag instance with scheduled stop time
    aws ec2 create-tags \
        --resources "$instance_id" \
        --tags "Key=AutoStopTime,Value=$stop_time"
}

check_auto_stop() {
    # Monitoring scripts check this tag and warn users
    # Does NOT automatically stop (requires manual script or external scheduler)
}
```

#### Cost Tracking Features:
- Display estimated costs during deployment
- Show running costs in monitoring dashboard
- Warn when costs exceed `COST_ALERT_THRESHOLD`
- Log total uptime and costs in deployment state

#### Additional Manual Control Scripts (Phase 1 Extension):
```bash
scripts/
├── stop-validator.sh       # Stop instance to save costs
├── start-validator.sh      # Resume stopped instance
├── get-status.sh          # Instance status + cost tracking
└── cost-report.sh         # Detailed cost breakdown
```

**Benefits for testnet testing:**
- Set `AUTO_STOP_HOURS=8` to automatically limit to work day
- Easy stop/start for overnight pauses
- Cost tracking prevents surprise bills
- State preserved across stop/start cycles

---

## Prerequisites (Manual Setup Required)

Before running any automation scripts, complete these manual setup steps:

### AWS Account Setup

#### 1. Create AWS IAM User

**Important:** Do not use your AWS root account credentials. Create a dedicated IAM user for this deployment.

**Steps:**

1. **Log into AWS Console**
   - Navigate to https://console.aws.amazon.com/
   - Sign in with your root account or existing admin user

2. **Navigate to IAM Service**
   - Search for "IAM" in the console search bar
   - Click on **IAM** (Identity and Access Management)

3. **Create New User**
   - Click **Users** in left sidebar
   - Click **Create user** button
   - User name: `jito-validator-admin` (or your preference)
   - Click **Next**

4. **Set Permissions**

   **For testnet (recommended):**
   - Choose: **Attach policies directly**
   - Select these AWS managed policies:
     - ✅ **AmazonEC2FullAccess** - Launch and manage EC2 instances
     - ✅ **IAMReadOnlyAccess** - Verify credentials (optional)
   - Click **Next**

   **For production (more restrictive):**
   - Create custom policy with minimal permissions:
     - `ec2:*` operations
     - `sts:GetCallerIdentity` for verification

5. **Review and Create**
   - Review user details
   - Click **Create user**

6. **Create Access Keys**
   - Click on the newly created user name
   - Go to **Security credentials** tab
   - Scroll to **Access keys** section
   - Click **Create access key**
   - Select use case: **Command Line Interface (CLI)**
   - Check confirmation box
   - Click **Next**
   - Optional: Add description tag (e.g., "Jito testnet validator deployment")
   - Click **Create access key**

7. **⚠️ Save Credentials Immediately**

   You'll see:
   - **Access key ID**: `AKIA...`
   - **Secret access key**: Long string (shown only once!)

   **Save these now:**
   - Click **Download .csv file** (recommended)
   - Or copy to secure password manager
   - **NEVER** commit to git or share publicly

   Click **Done** when saved

#### 2. Configure AWS CLI

After creating the IAM user, configure your local AWS CLI:

```bash
aws configure
```

Enter the credentials:
```
AWS Access Key ID [None]: AKIA... (paste your access key ID)
AWS Secret Access Key [None]: (paste your secret access key)
Default region name [None]: us-east-1 (or your preferred region)
Default output format [None]: json
```

#### 3. Verify AWS Configuration

Test that credentials are working:

```bash
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AIDA...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/jito-validator-admin"
}
```

If this command succeeds, you're ready to proceed!

---

## Detailed Implementation Plan

### Phase 1: Foundation Scripts

#### Script 1: `scripts/lib/common.sh`
**Purpose**: Shared utilities used by all scripts

**Functions**:
- `log_info()`, `log_error()`, `log_success()` - Colored logging
- `check_dependencies()` - Verify required commands exist
- `load_config()` - Load and validate .env files
- `prompt_confirmation()` - Require user confirmation for critical operations
- `retry_command()` - Retry with exponential backoff
- `ssh_exec()` - Execute commands on remote VM with error handling

**Manual Input**: None

---

#### Script 2: `scripts/00-setup-local.sh`
**Purpose**: Verify local environment prerequisites

**Tasks**:
1. Check for required tools: `aws`, `ssh`, `jq`, `curl`
2. Verify AWS CLI is configured (`aws sts get-caller-identity`)
3. Check AWS credentials and permissions
4. Create necessary directories (`keys/`, `logs/`, `config/`)
5. Validate config files exist or create templates

**Manual Input Required**:
- User must have AWS credentials configured (`aws configure`)
- User should review/edit generated config templates

**Success Criteria**: All dependencies present, AWS authenticated

---

#### Script 3: `config/aws-config.env`
**Purpose**: AWS infrastructure configuration template

**Parameters**:
```bash
AWS_REGION=us-east-1
AWS_INSTANCE_TYPE=m7i.4xlarge  # or r7i.4xlarge
AWS_AMI=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-*  # Latest Ubuntu 22.04
AWS_VOLUME_SIZE=2048  # GB
AWS_VOLUME_TYPE=gp3
AWS_VOLUME_IOPS=16000
AWS_KEY_NAME=jito-validator-key
AWS_SECURITY_GROUP_NAME=jito-validator-sg
AWS_INSTANCE_NAME=jito-testnet-validator
SSH_USER=ubuntu
```

**Manual Input**: User can customize instance type, region, etc.

---

#### Script 4: `config/jito-config.env`
**Purpose**: Jito-specific configuration (mostly static for testnet)

**Parameters**:
```bash
JITO_VERSION=v1.16.17-jito
SOLANA_CLUSTER=testnet
SOLANA_RPC_URL=https://api.testnet.solana.com
EXPECTED_GENESIS_HASH=4uhcVJyU9pJkvQyS88uRDiswHXSCkY3zQawwpjk2NsNY

# Jito Endpoints
BLOCK_ENGINE_URL=https://ny.testnet.block-engine.jito.wtf
RELAYER_URL=nyc.testnet.relayer.jito.wtf:8100
SHRED_RECEIVER_ADDR=141.98.216.97:1002

# Jito Program IDs
TIP_PAYMENT_PROGRAM=GJHtFqM9agxPmkeKjHny6qiRKrXZALvvFGiKf11QE7hy
TIP_DISTRIBUTION_PROGRAM=F2Zu7QZiTYUhPd7u9ukRVwxh7B71oA3NMJcHuCHc29P2
MERKLE_ROOT_AUTHORITY=GZctHpWXmsZC1YHACTGGcHhYxjdRqQvTpYkb9LMvxDib

# Paths on remote VM
LEDGER_PATH=/mnt/ledger
ACCOUNTS_PATH=/mnt/accounts
LOG_PATH=/home/sol/jito-validator.log
```

**Manual Input**: None (defaults work for testnet)

---

### Phase 2: AWS Infrastructure Provisioning

#### Script 5: `scripts/01-provision-aws.sh`
**Purpose**: Create and configure AWS EC2 instance

**Tasks**:
1. Create SSH keypair if doesn't exist: `aws ec2 create-key-pair`
2. Create security group with rules:
   - SSH (22) from user's IP
   - Solana gossip (8000-8020)
   - RPC (8899)
   - Custom Jito ports
3. Find latest Ubuntu 22.04 AMI: `aws ec2 describe-images`
4. Launch EC2 instance with:
   - Configured instance type and specs
   - 2TB gp3 EBS volume
   - User data script for basic setup
5. Wait for instance to be running
6. Get instance public IP and store in `deployment.state`
7. Wait for SSH to be available
8. Run initial setup commands:
   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo adduser --disabled-password --gecos "" sol
   sudo mkdir -p /mnt/ledger /mnt/accounts
   sudo chown sol:sol /mnt/ledger /mnt/accounts
   ```

**Manual Input Required**:
- User confirmation before creating AWS resources (cost warning)
- Option to use existing security group/keypair

**Output**:
- Instance ID, Public IP saved to `deployment.state`
- SSH key saved to `keys/aws-ssh-key.pem`

**Success Criteria**: SSH connection to VM works, `sol` user created

---

### Phase 3: Key Management

#### Script 6: `scripts/02-generate-keys.sh`
**Purpose**: Generate Solana keypairs locally

**Tasks**:
1. Check if Solana CLI is installed, if not:
   ```bash
   sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"
   export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
   ```
2. Configure Solana CLI for testnet:
   ```bash
   solana config set --url https://api.testnet.solana.com
   ```
3. Generate three keypairs:
   ```bash
   solana-keygen new -o keys/validator-keypair.json --no-bip39-passphrase
   solana-keygen new -o keys/vote-account-keypair.json --no-bip39-passphrase
   solana-keygen new -o keys/authorized-withdrawer-keypair.json --no-bip39-passphrase
   ```
4. Set validator keypair as default:
   ```bash
   solana config set --keypair ./keys/validator-keypair.json
   ```
5. Display public keys:
   ```bash
   echo "Validator Identity: $(solana-keygen pubkey keys/validator-keypair.json)"
   echo "Vote Account: $(solana-keygen pubkey keys/vote-account-keypair.json)"
   echo "Withdrawer: $(solana-keygen pubkey keys/authorized-withdrawer-keypair.json)"
   ```
6. Save pubkeys to `deployment.state`

**Manual Input Required**:
- **CRITICAL**: Inform user to backup `authorized-withdrawer-keypair.json` offline
- Confirmation that user has backed up withdrawer key before proceeding

**Security Note**: Script should warn about key security and offer to encrypt keys

**Success Criteria**: Three keypair files created, pubkeys displayed and saved

---

#### Script 7: `scripts/03-fund-accounts.sh`
**Purpose**: Obtain testnet SOL for validator operations

**Tasks**:
1. Check current balance:
   ```bash
   solana balance
   ```
2. Attempt automated airdrops:
   ```bash
   solana airdrop 2
   ```
3. If airdrop fails (rate limiting), provide fallback:
   - Display validator pubkey
   - Provide links to web faucets:
     - https://faucet.solana.com (select testnet)
     - https://faucet.quicknode.com/solana/testnet
   - Wait for user confirmation that they've funded the account
4. Verify balance is sufficient (at least 5 SOL recommended)
5. Wait for confirmation after balance check

**Manual Input Required**:
- If airdrop fails: User must manually use web faucet and confirm funding
- User confirmation to proceed once funded

**Success Criteria**: Validator identity has at least 5 SOL

---

#### Script 8: `scripts/lib/solana-helpers.sh`
**Purpose**: Solana CLI wrapper functions

**Functions**:
- `wait_for_balance()` - Poll balance until target reached
- `create_vote_account()` - Wrapper for vote account creation
- `verify_vote_account()` - Check vote account exists and is valid
- `get_validator_info()` - Query validator status from gossip

---

### Phase 4: Remote VM Setup

#### Script 9: `scripts/04-setup-validator.sh`
**Purpose**: Configure VM and install dependencies

**Tasks**:
1. Read instance IP from `deployment.state`
2. Copy validator and vote keypairs to VM:
   ```bash
   scp -i keys/aws-ssh-key.pem keys/validator-keypair.json sol@$IP:/home/sol/
   scp -i keys/aws-ssh-key.pem keys/vote-account-keypair.json sol@$IP:/home/sol/
   ```
3. SSH to VM and execute setup commands:
   ```bash
   # Install build dependencies
   sudo apt install -y libssl-dev libudev-dev pkg-config zlib1g-dev \
     llvm clang cmake make libprotobuf-dev protobuf-compiler git

   # Install Rust
   curl https://sh.rustup.rs -sSf | sh -s -- -y
   source $HOME/.cargo/env
   rustup update

   # Install Solana CLI
   sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"
   echo 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' >> ~/.bashrc
   ```
4. Configure Solana CLI on VM:
   ```bash
   solana config set --url https://api.testnet.solana.com
   solana config set --keypair /home/sol/validator-keypair.json
   ```
5. Verify installations:
   ```bash
   rustc --version
   solana --version
   ```

**Manual Input**: None (fully automated)

**Success Criteria**: All dependencies installed, Solana CLI working on VM

---

### Phase 5: Jito-Solana Build

#### Script 10: `scripts/05-build-jito.sh`
**Purpose**: Clone and compile Jito-Solana on VM

**Tasks**:
1. SSH to VM and clone Jito-Solana:
   ```bash
   git clone https://github.com/jito-foundation/jito-solana.git --recurse-submodules
   cd jito-solana
   ```
2. Checkout specific version tag:
   ```bash
   export TAG=v1.16.17-jito
   git checkout tags/$TAG
   ```
3. Build validator binaries:
   ```bash
   CI_COMMIT=$(git rev-parse HEAD) scripts/cargo-install-all.sh \
     --validator-only ~/.local/share/solana/install/releases/"$TAG"
   ```
4. Verify build:
   ```bash
   ~/.local/share/solana/install/releases/$TAG/bin/solana-validator --version
   ```
5. Create symlink for easy access:
   ```bash
   mkdir -p ~/bin
   ln -sf ~/.local/share/solana/install/releases/$TAG/bin/solana-validator ~/bin/
   ```

**Manual Input**: None

**Note**: This step takes 30-60 minutes, script should show progress updates

**Success Criteria**: `solana-validator` binary exists and shows correct version

---

### Phase 6: Vote Account Creation

#### Script 11: `scripts/03-fund-accounts.sh` (Part 2)
**Purpose**: Create vote account on testnet

**Tasks** (runs on local machine):
1. Ensure validator identity is funded (checked in earlier step)
2. Create vote account:
   ```bash
   solana create-vote-account -ut \
     --fee-payer ./keys/validator-keypair.json \
     ./keys/vote-account-keypair.json \
     ./keys/validator-keypair.json \
     ./keys/authorized-withdrawer-keypair.json
   ```
3. Verify vote account creation:
   ```bash
   solana vote-account $(solana-keygen pubkey keys/vote-account-keypair.json)
   ```
4. Save vote account address to `deployment.state`

**Manual Input**: None (automated after funding)

**Success Criteria**: Vote account visible on-chain, shows validator as node identity

---

### Phase 7: Validator Configuration

#### Script 12: `scripts/06-configure-validator.sh`
**Purpose**: Generate validator launch script on VM

**Tasks**:
1. Read all config from `jito-config.env` and `deployment.state`
2. Generate `/home/sol/bin/validator.sh` on VM from template:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail

   LEDGER=/mnt/ledger
   ACCOUNTS=/mnt/accounts
   LOG=/home/sol/jito-validator.log
   BIN="$HOME/.local/share/solana/install/releases/v1.16.17-jito/bin"

   BLOCK_ENGINE_URL="https://ny.testnet.block-engine.jito.wtf"
   RELAYER_URL="nyc.testnet.relayer.jito.wtf:8100"
   SHRED_RECEIVER_ADDR="141.98.216.97:1002"

   TIP_PAYMENT=GJHtFqM9agxPmkeKjHny6qiRKrXZALvvFGiKf11QE7hy
   TIP_DISTRIB=F2Zu7QZiTYUhPd7u9ukRVwxh7B71oA3NMJcHuCHc29P2
   MERKLE_AUTH=GZctHpWXmsZC1YHACTGGcHhYxjdRqQvTpYkb9LMvxDib

   exec "$BIN/solana-validator" \
     --identity /home/sol/validator-keypair.json \
     --vote-account /home/sol/vote-account-keypair.json \
     --ledger "$LEDGER" \
     --accounts "$ACCOUNTS" \
     --log "$LOG" \
     --rpc-port 8899 \
     --dynamic-port-range 8000-8020 \
     --entrypoint entrypoint.testnet.solana.com:8001 \
     --expected-genesis-hash 4uhcVJyU9pJkvQyS88uRDiswHXSCkY3zQawwpjk2NsNY \
     --tip-payment-program-pubkey "$TIP_PAYMENT" \
     --tip-distribution-program-pubkey "$TIP_DISTRIB" \
     --merkle-root-upload-authority "$MERKLE_AUTH" \
     --block-engine-url "$BLOCK_ENGINE_URL" \
     --relayer-url "$RELAYER_URL" \
     --shred-receiver-address "$SHRED_RECEIVER_ADDR"
   ```
3. Make script executable:
   ```bash
   chmod +x /home/sol/bin/validator.sh
   ```
4. Create systemd service file for auto-restart:
   ```bash
   sudo tee /etc/systemd/system/jito-validator.service <<EOF
   [Unit]
   Description=Jito Solana Validator
   After=network.target

   [Service]
   Type=simple
   User=sol
   WorkingDirectory=/home/sol
   ExecStart=/home/sol/bin/validator.sh
   Restart=on-failure
   RestartSec=10

   [Install]
   WantedBy=multi-user.target
   EOF
   ```
5. Enable but don't start service yet:
   ```bash
   sudo systemctl enable jito-validator
   ```

**Manual Input**: None

**Success Criteria**: `validator.sh` script created and executable, systemd service configured

---

### Phase 8: Launch & Verification

#### Script 13: `scripts/07-launch-validator.sh`
**Purpose**: Start validator and verify it's running correctly

**Tasks**:
1. Start validator via systemd:
   ```bash
   sudo systemctl start jito-validator
   ```
2. Wait 30 seconds for initial startup
3. Check service status:
   ```bash
   sudo systemctl status jito-validator
   ```
4. Tail logs and look for errors:
   ```bash
   tail -n 50 /home/sol/jito-validator.log
   ```
5. Run verification checks:
   ```bash
   PUBKEY=$(solana-keygen pubkey /home/sol/validator-keypair.json)

   # Check gossip
   solana gossip | grep "$PUBKEY"

   # Check validator list (may take time to appear)
   solana validators | grep "$PUBKEY"

   # Check catchup status
   solana catchup "$PUBKEY"
   ```
6. Display connection to Jito infrastructure:
   - Check logs for "block-engine" connection messages
   - Verify shred receiver connection

**Manual Input Required**:
- User should review logs for any errors
- User confirmation that validator appears healthy before considering deployment complete

**Success Criteria**:
- Service running
- Validator appears in gossip
- No critical errors in logs
- Catching up to network

---

#### Script 14: `scripts/08-monitor.sh`
**Purpose**: Ongoing health checks and monitoring

**Functions**:
- `check_service_status()` - Verify systemd service is active
- `check_catchup_status()` - Monitor sync progress
- `check_vote_credits()` - Track voting performance
- `check_skip_rate()` - Monitor skip rate
- `check_disk_space()` - Alert if disk filling up
- `check_log_errors()` - Grep logs for common errors
- `display_dashboard()` - Show summary of all metrics

**Usage**: Can be run continuously or as a cron job

**Manual Input**: None (monitoring only)

---

### Phase 9: Orchestration

#### Script 15: `deploy-jito-validator.sh` (Main Orchestrator)
**Purpose**: Run all scripts in sequence with proper error handling

**Flow**:
```bash
#!/bin/bash
set -euo pipefail

source scripts/lib/common.sh

log_info "=== Jito Validator Deployment Starting ==="

# Phase 1: Prerequisites
./scripts/00-setup-local.sh || exit 1

# Phase 2: AWS Infrastructure
./scripts/01-provision-aws.sh || exit 1

# Phase 3: Key Generation & Funding
./scripts/02-generate-keys.sh || exit 1
./scripts/03-fund-accounts.sh || exit 1

# Phase 4: VM Setup
./scripts/04-setup-validator.sh || exit 1

# Phase 5: Build Jito
./scripts/05-build-jito.sh || exit 1

# Phase 6: Configure
./scripts/06-configure-validator.sh || exit 1

# Phase 7: Launch
./scripts/07-launch-validator.sh || exit 1

log_success "=== Deployment Complete ==="
log_info "Monitor your validator with: ./scripts/08-monitor.sh"
```

**Manual Input Points Throughout**:
1. AWS resource creation confirmation (cost warning)
2. Withdrawer key backup confirmation
3. Manual funding if airdrop fails
4. Final health check review

---

## State Management

### `deployment.state` File Format
```json
{
  "timestamp": "2025-10-20T12:34:56Z",
  "aws": {
    "instance_id": "i-1234567890abcdef0",
    "public_ip": "203.0.113.42",
    "region": "us-east-1",
    "ssh_key": "keys/aws-ssh-key.pem"
  },
  "validator": {
    "identity_pubkey": "ABC123...",
    "vote_account_pubkey": "DEF456...",
    "withdrawer_pubkey": "GHI789..."
  },
  "jito": {
    "version": "v1.16.17-jito",
    "build_complete": true,
    "validator_running": true
  },
  "status": "running"
}
```

---

## Error Handling Strategy

### Common Failure Points & Mitigations

1. **AWS Resource Creation Fails**
   - Check AWS quotas and limits
   - Verify IAM permissions
   - Retry with exponential backoff

2. **SSH Connection Fails**
   - Wait longer for instance initialization
   - Check security group rules
   - Verify SSH key permissions (chmod 600)

3. **Jito Build Fails**
   - Common cause: insufficient memory
   - Solution: Add swap space or use larger instance temporarily
   - Retry mechanism for transient network issues

4. **Airdrop Rate Limiting**
   - Fallback to manual web faucet flow
   - Consider implementing faucet API integration if available

5. **Validator Fails to Start**
   - Check ledger directory permissions
   - Verify keypair file paths
   - Review validator logs for specific errors
   - Common: genesis hash mismatch, port conflicts

### Logging
- All scripts log to `logs/deployment-{timestamp}.log`
- Structured log format: `[TIMESTAMP] [LEVEL] [SCRIPT] MESSAGE`
- Critical errors also echo to stderr
- Success checkpoints logged for resume capability

---

## Testing Strategy

### Unit Testing
- Test each helper function in isolation
- Mock AWS CLI and SSH commands for local testing
- Use `shellcheck` for static analysis

### Integration Testing
- Dry-run mode that simulates without creating resources
- Test against localnet before testnet
- Validate generated config files before deployment

### Manual Testing Checklist
- [ ] Run on clean AWS account
- [ ] Test with minimal instance type
- [ ] Verify all manual prompts are clear
- [ ] Test error recovery (kill script mid-execution and resume)
- [ ] Verify validator actually votes on testnet

---

## Future Enhancements

### Phase 2 Features
1. **Multi-validator deployment** - Deploy multiple validators in parallel
2. **Update automation** - Script to safely upgrade Jito version
3. **Monitoring dashboard** - Web UI showing validator health metrics
4. **Alert system** - Notifications for validator issues (email/Slack/Discord)
5. **Cost optimization** - Automatic instance resizing during low activity
6. **Backup/restore** - Automated ledger and account snapshots
7. **Mainnet support** - Adapt scripts for mainnet deployment with additional safety checks

### Optional TypeScript Components
- State management service (track multiple validators)
- REST API for deployment status
- Web UI for monitoring and management
- Integration with Jito block engine metrics API

---

## Security Considerations

### Key Management
- **NEVER** commit keypair files to git (`.gitignore` must include `keys/`)
- Authorized withdrawer key should be immediately moved offline after generation
- Consider using AWS KMS for encrypting validator and vote account keys
- Rotate SSH keys periodically

### AWS Security
- Restrict security group rules to minimum required ports
- Use IAM roles with least privilege
- Enable CloudTrail logging
- Consider using AWS Systems Manager Session Manager instead of direct SSH
- Enable EBS encryption

### Network Security
- Implement rate limiting on RPC endpoint if exposing publicly
- Consider running validator in private subnet with bastion host
- Use VPC flow logs for monitoring

### Operational Security
- Regularly update system packages
- Monitor for suspicious activity in validator logs
- Keep withdrawer key in cold storage (hardware wallet or paper wallet)
- Document recovery procedures

---

## Estimated Timeline

- **Script Development**: 2-3 days
- **Testing & Debugging**: 1-2 days
- **Documentation**: 0.5 days
- **Total**: ~4-6 days

**Per-deployment time**:
- Manual steps: ~10 minutes (confirmations, key backup)
- Automated execution: ~60-90 minutes (most time in Jito build)

---

## Success Metrics

### Deployment Success
- [ ] AWS instance provisioned and accessible
- [ ] All keypairs generated and backed up
- [ ] Vote account created on testnet
- [ ] Jito-Solana built successfully
- [ ] Validator service running
- [ ] Validator appears in `solana validators` list
- [ ] Validator is catching up to network
- [ ] No critical errors in logs

### Automation Success
- [ ] Single command deployment works end-to-end
- [ ] Manual input required only for security decisions
- [ ] Clear error messages with remediation steps
- [ ] Deployment completes in < 90 minutes
- [ ] State persists and allows resume after failure

---

## Validation & Testing Guide

### Post-Deployment Validation Steps

After running the automation scripts, follow these steps to confirm your Jito validator is working properly:

#### 1. Basic Health Checks

**Check validator service is running:**
```bash
# On the VM
ssh -i keys/aws-ssh-key.pem sol@<VM_IP>
sudo systemctl status jito-validator

# Should show: Active: active (running)
```

**Check validator logs for errors:**
```bash
# Look for critical errors
tail -f /home/sol/jito-validator.log | grep -E "ERROR|WARN"

# Positive indicators to look for:
# - "Shred version: ..." (shows version negotiation)
# - "Cluster info initialized"
# - No repeated error messages
```

#### 2. Network Connectivity

**Verify validator appears in gossip network:**
```bash
# Get your validator identity pubkey
PUBKEY=$(solana-keygen pubkey keys/validator-keypair.json)

# Check gossip (should show your validator)
solana gossip | grep "$PUBKEY"
# Expected: One line with your pubkey, IP, and version
```

**Check validator is in the validator set:**
```bash
solana validators | grep "$PUBKEY"
# Expected: Shows your pubkey with "active" status
# Note: May take 5-10 minutes to appear after first start
```

**Verify entrypoint connection:**
```bash
# Check that you're connected to testnet entrypoints
solana gossip | head -20
# Should see entrypoint.testnet.solana.com listed
```

#### 3. Sync Status

**Check catchup status:**
```bash
solana catchup "$PUBKEY"
# Expected: Shows slot numbers and indicates catching up or "has caught up"
# Initial catchup can take 30-60 minutes depending on network
```

**Monitor sync progress:**
```bash
# Check current slot vs your validator's slot
solana slot
solana catchup "$PUBKEY" --follow
# Your slot should increase and converge toward network slot
```

#### 4. Vote Account Validation

**Verify vote account exists and is associated:**
```bash
VOTE_PUBKEY=$(solana-keygen pubkey keys/vote-account-keypair.json)

# Get vote account details
solana vote-account "$VOTE_PUBKEY"

# Expected output should show:
# - Account Balance (should have some SOL)
# - Vote Authority: <your validator pubkey>
# - Withdrawer Authority: <your withdrawer pubkey>
# - Credits and Commission details
```

**Check if validator is voting:**
```bash
# After validator has caught up, check for vote credits
solana vote-account "$VOTE_PUBKEY" | grep "Credits"
# Credits should be increasing over time (check multiple times)
```

#### 5. Jito-Specific Validation

**Verify Jito block engine connection:**
```bash
# Check logs for block engine connection
grep -i "block.engine" /home/sol/jito-validator.log | tail -20
# Should see successful connection messages, not repeated errors
```

**Verify Jito relayer connection:**
```bash
# Check logs for relayer connection
grep -i "relayer" /home/sol/jito-validator.log | tail -20
# Should see connection established messages
```

**Verify shred receiver configuration:**
```bash
# Check that shred receiver is configured
grep -i "shred.receiver" /home/sol/jito-validator.log | tail -10
# Should show the configured shred receiver address
```

**Check Jito-specific flags are active:**
```bash
# View running process
ps aux | grep solana-validator
# Should include all Jito flags: --block-engine-url, --relayer-url, etc.
```

#### 6. Performance Metrics

**Check skip rate (after validator has caught up):**
```bash
solana validators | grep "$PUBKEY"
# Look at the "Skip Rate" column - should be low (<10%)
# Note: Will show N/A until validator has produced blocks
```

**Monitor block production:**
```bash
# Check if validator is producing blocks (after 1-2 epochs)
solana block-production | grep "$PUBKEY"
# Shows leader slots and blocks produced
# Note: Testnet validators may get few leader slots
```

**Check validator uptime:**
```bash
solana validators --sort skip-rate | grep "$PUBKEY"
# Shows skip rate and helps identify performance issues
```

#### 7. Resource Utilization

**Check disk space:**
```bash
ssh -i keys/aws-ssh-key.pem sol@<VM_IP> "df -h"
# Verify /mnt/ledger and /mnt/accounts have sufficient space
# Ledger grows continuously - should have 1+ TB free
```

**Check memory usage:**
```bash
ssh -i keys/aws-ssh-key.pem sol@<VM_IP> "free -h"
# Validator uses significant RAM - ensure not swapping heavily
```

**Check CPU usage:**
```bash
ssh -i keys/aws-ssh-key.pem sol@<VM_IP> "top -bn1 | head -20"
# solana-validator process should be using CPU but not maxed at 100% constantly
```

#### 8. RPC Endpoint Testing

**Test local RPC endpoint:**
```bash
# From your local machine
curl http://<VM_IP>:8899 -X POST -H "Content-Type: application/json" -d '
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "getHealth"
}
'
# Expected: {"jsonrpc":"2.0","result":"ok","id":1}
```

**Test validator identity via RPC:**
```bash
curl http://<VM_IP>:8899 -X POST -H "Content-Type: application/json" -d '
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "getIdentity"
}
'
# Should return your validator pubkey
```

#### 9. End-to-End Integration Test

**Full validator health script** (`scripts/09-validate-deployment.sh`):
```bash
#!/bin/bash
# Comprehensive validation script

source scripts/lib/common.sh

log_info "=== Validator Deployment Validation ==="

# Load state
PUBKEY=$(jq -r '.validator.identity_pubkey' deployment.state)
VOTE_PUBKEY=$(jq -r '.validator.vote_account_pubkey' deployment.state)
VM_IP=$(jq -r '.aws.public_ip' deployment.state)

# Test 1: Service Status
log_info "1. Checking service status..."
ssh -i keys/aws-ssh-key.pem sol@"$VM_IP" "sudo systemctl is-active jito-validator" || {
  log_error "Validator service is not active!"
  exit 1
}
log_success "✓ Service is running"

# Test 2: Gossip presence
log_info "2. Checking gossip network..."
solana gossip | grep -q "$PUBKEY" || {
  log_error "Validator not found in gossip!"
  exit 1
}
log_success "✓ Validator in gossip network"

# Test 3: Validator list
log_info "3. Checking validator list..."
solana validators | grep -q "$PUBKEY" || {
  log_error "Validator not in validator set!"
  exit 1
}
log_success "✓ Validator in validator set"

# Test 4: Vote account
log_info "4. Checking vote account..."
solana vote-account "$VOTE_PUBKEY" > /dev/null || {
  log_error "Vote account not found!"
  exit 1
}
log_success "✓ Vote account exists"

# Test 5: Sync status
log_info "5. Checking sync status..."
CATCHUP=$(solana catchup "$PUBKEY" 2>&1)
echo "$CATCHUP"
if echo "$CATCHUP" | grep -q "caught up"; then
  log_success "✓ Validator has caught up"
elif echo "$CATCHUP" | grep -q "slot"; then
  log_info "⚠ Validator is catching up (this is normal for new validators)"
else
  log_error "Unable to determine sync status"
fi

# Test 6: RPC health
log_info "6. Checking RPC endpoint..."
RPC_HEALTH=$(curl -s http://"$VM_IP":8899 -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}')
if echo "$RPC_HEALTH" | grep -q "ok"; then
  log_success "✓ RPC endpoint is healthy"
else
  log_error "RPC endpoint is not responding correctly"
fi

# Test 7: Jito connections
log_info "7. Checking Jito infrastructure connections..."
BLOCK_ENGINE_LOGS=$(ssh -i keys/aws-ssh-key.pem sol@"$VM_IP" "grep -i 'block.engine' /home/sol/jito-validator.log | tail -5")
if [ -n "$BLOCK_ENGINE_LOGS" ]; then
  log_success "✓ Block engine connection logs present"
  echo "$BLOCK_ENGINE_LOGS"
else
  log_error "No block engine connection logs found"
fi

# Test 8: Recent errors
log_info "8. Checking for recent errors in logs..."
RECENT_ERRORS=$(ssh -i keys/aws-ssh-key.pem sol@"$VM_IP" "tail -100 /home/sol/jito-validator.log | grep -c ERROR")
if [ "$RECENT_ERRORS" -eq 0 ]; then
  log_success "✓ No recent errors in logs"
else
  log_error "Found $RECENT_ERRORS errors in recent logs. Review manually."
fi

# Summary
log_success "=== Validation Complete ==="
log_info "Next steps:"
log_info "1. Monitor validator with: ./scripts/08-monitor.sh"
log_info "2. Check vote credits accumulation: solana vote-account $VOTE_PUBKEY"
log_info "3. Monitor catchup: solana catchup $PUBKEY --follow"
log_info "4. View logs: ssh sol@$VM_IP tail -f /home/sol/jito-validator.log"
```

#### 10. Expected Timeline for Full Validation

- **0-5 minutes**: Service starts, gossip connection established
- **5-15 minutes**: Validator appears in validator set
- **15-60 minutes**: Initial catchup to network (downloading ledger history)
- **60-90 minutes**: Fully caught up, ready to vote
- **1-2 epochs**: First vote credits accumulate
- **2-3 epochs**: Eligible for leader slots (testnet may have fewer)

#### 11. Troubleshooting Common Issues

**Issue: Validator not in gossip**
```bash
# Check if validator is actually running
sudo systemctl status jito-validator

# Check network connectivity
ping -c 3 entrypoint.testnet.solana.com

# Check firewall rules on AWS security group
# Ensure ports 8000-8020 are open
```

**Issue: Slow catchup or stalled sync**
```bash
# Check disk I/O
iostat -x 2 5

# Check network bandwidth
iftop

# Consider using snapshot for faster catchup
# (can be added to automation scripts)
```

**Issue: Vote account not voting**
```bash
# Ensure validator has caught up first
solana catchup "$PUBKEY"

# Check vote account has sufficient balance
solana balance keys/vote-account-keypair.json

# Review validator logs for vote transaction errors
grep -i "vote" /home/sol/jito-validator.log | tail -50
```

**Issue: Jito connections failing**
```bash
# Test block engine connectivity
curl -I https://ny.testnet.block-engine.jito.wtf

# Check if URLs are correct in validator config
ps aux | grep solana-validator | grep block-engine

# Review Jito-specific errors
grep -i "jito\|block.engine\|relayer" /home/sol/jito-validator.log | grep -i error
```

#### 12. Continuous Monitoring Commands

**Create a monitoring script to run regularly:**
```bash
#!/bin/bash
# Quick health check - run every 5 minutes via cron

PUBKEY="<your-validator-pubkey>"
VOTE_PUBKEY="<your-vote-account-pubkey>"

# Check service
systemctl is-active --quiet jito-validator || echo "ALERT: Service down!"

# Check disk space
DISK_USAGE=$(df /mnt/ledger | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 80 ]; then
  echo "ALERT: Disk usage at ${DISK_USAGE}%"
fi

# Check if still in gossip
solana gossip | grep -q "$PUBKEY" || echo "ALERT: Not in gossip!"

# Check vote credits (should increase)
CREDITS=$(solana vote-account "$VOTE_PUBKEY" | grep "Credits" | awk '{print $2}')
echo "Current vote credits: $CREDITS"

# Check for errors in last 100 lines
ERROR_COUNT=$(tail -100 /home/sol/jito-validator.log | grep -c ERROR)
if [ "$ERROR_COUNT" -gt 5 ]; then
  echo "ALERT: $ERROR_COUNT errors in recent logs"
fi
```

#### 13. Success Checklist

Use this checklist to confirm deployment success:

- [ ] AWS EC2 instance is running and accessible via SSH
- [ ] Validator service shows "active (running)" status
- [ ] No critical errors in validator logs
- [ ] Validator pubkey appears in `solana gossip` output
- [ ] Validator pubkey appears in `solana validators` output
- [ ] Vote account exists and shows correct authorities
- [ ] Validator is catching up or has caught up to network slot
- [ ] RPC endpoint responds to health checks
- [ ] Block engine connection logs show successful connections
- [ ] Relayer connection logs show successful connections
- [ ] Shred receiver address is configured correctly
- [ ] Disk space is adequate (>1TB free on ledger volume)
- [ ] Memory usage is reasonable (not excessive swapping)
- [ ] Vote credits are accumulating (after 1-2 epochs)
- [ ] Skip rate is reasonable (<20% for testnet)

Once all items are checked, your Jito validator is successfully deployed and operating!

---

## Next Steps

1. **Review this plan** - Confirm approach and architecture
2. **Set up development environment** - Ensure AWS CLI, shellcheck, etc.
3. **Create repository structure** - Scaffold directories and files
4. **Implement Phase 1** - Foundation scripts and helpers
5. **Implement Phase 2-8** - Core automation scripts
6. **Test on personal AWS account** - Deploy test validator
7. **Run validation suite** - Use the testing guide above to confirm everything works
8. **Document and refine** - Update README with usage instructions
9. **Optional: Add monitoring dashboard** - TypeScript/web UI for visibility
