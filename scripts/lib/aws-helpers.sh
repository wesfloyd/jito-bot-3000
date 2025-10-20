#!/usr/bin/env bash
# AWS-specific helper functions for EC2, security groups, and instance management

# Source common utilities if not already sourced
if [[ -z "${COMMON_LIB_LOADED:-}" ]]; then
    _LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=scripts/lib/common.sh
    source "${_LIB_DIR}/common.sh"
fi

# ============================================================================
# AWS Authentication & Setup
# ============================================================================

verify_aws_credentials() {
    log_info "Verifying AWS credentials..."

    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid"
        log_info "Please run: aws configure"
        return 1
    fi

    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    log_success "AWS authenticated (Account: $account_id)"

    return 0
}

check_aws_region() {
    local region=${1:-$AWS_REGION}

    if [[ -z "$region" ]]; then
        log_error "AWS region not specified"
        return 1
    fi

    log_debug "Using AWS region: $region"
    export AWS_DEFAULT_REGION="$region"

    return 0
}

# ============================================================================
# SSH Key Management
# ============================================================================

create_or_get_keypair() {
    local key_name=$1
    local key_file=$2
    local region=${3:-$AWS_REGION}

    log_info "Checking for SSH keypair: $key_name"

    # Check if keypair already exists in AWS
    if aws ec2 describe-key-pairs --key-names "$key_name" --region "$region" >/dev/null 2>&1; then
        log_info "Keypair '$key_name' already exists in AWS"

        if [[ ! -f "$key_file" ]]; then
            log_error "Keypair exists in AWS but local key file not found: $key_file"
            log_info "Either delete the AWS keypair or provide the local key file"
            return 1
        fi

        log_success "Using existing keypair"
        return 0
    fi

    # Create new keypair
    log_info "Creating new SSH keypair: $key_name"

    ensure_directory "$(dirname "$key_file")"

    aws ec2 create-key-pair \
        --key-name "$key_name" \
        --region "$region" \
        --query 'KeyMaterial' \
        --output text > "$key_file"

    chmod 600 "$key_file"

    log_success "Created SSH keypair: $key_file"

    return 0
}

# ============================================================================
# Security Group Management
# ============================================================================

create_security_group() {
    local sg_name=$1
    local description=$2
    local region=${3:-$AWS_REGION}
    local vpc_id=${4:-${AWS_VPC_ID:-}}

    log_info "Checking for security group: $sg_name" >&2

    # Check if security group already exists
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$sg_name" \
        --region "$region" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null)

    if [[ -n "$sg_id" && "$sg_id" != "None" ]]; then
        log_info "Security group already exists: $sg_id" >&2
        echo "$sg_id"
        return 0
    fi

    # Create security group
    log_info "Creating security group: $sg_name" >&2

    if [[ -n "$vpc_id" ]]; then
        sg_id=$(aws ec2 create-security-group \
            --group-name "$sg_name" \
            --description "$description" \
            --vpc-id "$vpc_id" \
            --region "$region" \
            --query 'GroupId' \
            --output text)
    else
        sg_id=$(aws ec2 create-security-group \
            --group-name "$sg_name" \
            --description "$description" \
            --region "$region" \
            --query 'GroupId' \
            --output text)
    fi

    log_success "Created security group: $sg_id" >&2

    echo "$sg_id"
    return 0
}

add_security_group_rule() {
    local sg_id=$1
    local port=$2
    local protocol=${3:-tcp}
    local cidr=${4:-0.0.0.0/0}
    local description=${5:-""}
    local region=${6:-$AWS_REGION}

    log_debug "Adding rule to $sg_id: $protocol/$port from $cidr"

    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol "$protocol" \
        --port "$port" \
        --cidr "$cidr" \
        --region "$region" \
        ${description:+--description "$description"} \
        >/dev/null 2>&1 || log_debug "Rule may already exist"

    return 0
}

configure_validator_security_group() {
    local sg_id=$1
    local region=${2:-$AWS_REGION}
    local my_ip=${3:-""}

    log_info "Configuring security group rules for validator..."

    # Get current public IP if not provided
    if [[ -z "$my_ip" ]]; then
        my_ip=$(curl -s https://checkip.amazonaws.com)
        log_info "Detected your IP: $my_ip"
    fi

    # SSH - restrict to your IP for security
    add_security_group_rule "$sg_id" "22" "tcp" "${my_ip}/32" "SSH from admin IP" "$region"

    # Solana gossip protocol (UDP)
    add_security_group_rule "$sg_id" "8000-8020" "udp" "0.0.0.0/0" "Solana gossip" "$region"

    # Solana gossip protocol (TCP)
    add_security_group_rule "$sg_id" "8000-8020" "tcp" "0.0.0.0/0" "Solana gossip" "$region"

    # RPC port (optional - uncomment if you want public RPC)
    # add_security_group_rule "$sg_id" "8899" "tcp" "${my_ip}/32" "RPC from admin IP" "$region"

    log_success "Security group rules configured"

    return 0
}

# ============================================================================
# AMI Selection
# ============================================================================

find_latest_ubuntu_ami() {
    local region=${1:-$AWS_REGION}

    log_info "Finding latest Ubuntu 22.04 AMI in $region..." >&2

    local ami_id
    ami_id=$(aws ec2 describe-images \
        --owners 099720109477 \
        --filters \
            "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            "Name=state,Values=available" \
        --region "$region" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text)

    if [[ -z "$ami_id" || "$ami_id" == "None" ]]; then
        log_error "Could not find Ubuntu 22.04 AMI" >&2
        return 1
    fi

    log_success "Found AMI: $ami_id" >&2
    echo "$ami_id"

    return 0
}

# ============================================================================
# EC2 Instance Management
# ============================================================================

launch_ec2_instance() {
    local instance_type=$1
    local ami_id=$2
    local key_name=$3
    local sg_id=$4
    local instance_name=$5
    local volume_size=$6
    local region=${7:-$AWS_REGION}
    local vpc_id=${8:-${AWS_VPC_ID:-}}

    log_info "Launching EC2 instance..." >&2
    log_info "  Type: $instance_type" >&2
    log_info "  AMI: $ami_id" >&2
    log_info "  Storage: ${volume_size}GB" >&2

    # Get subnet ID for the VPC in a supported AZ
    local subnet_id
    if [[ -n "$vpc_id" ]]; then
        # Get supported availability zones for this instance type
        local supported_azs
        supported_azs=$(aws ec2 describe-instance-type-offerings \
            --location-type availability-zone \
            --filters "Name=instance-type,Values=$instance_type" \
            --region "$region" \
            --query 'InstanceTypeOfferings[*].Location' \
            --output text)
        
        log_info "Supported AZs for $instance_type: $supported_azs" >&2
        
        # Find a subnet in a supported AZ
        subnet_id=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --region "$region" \
            --query "Subnets[?AvailabilityZone==\`$(echo $supported_azs | awk '{print $1}')\`].SubnetId" \
            --output text)
        
        # If first AZ doesn't work, try others
        if [[ -z "$subnet_id" || "$subnet_id" == "None" ]]; then
            for az in $supported_azs; do
                subnet_id=$(aws ec2 describe-subnets \
                    --filters "Name=vpc-id,Values=$vpc_id" \
                    --region "$region" \
                    --query "Subnets[?AvailabilityZone==\`$az\`].SubnetId" \
                    --output text)
                if [[ -n "$subnet_id" && "$subnet_id" != "None" ]]; then
                    break
                fi
            done
        fi
        
        if [[ -z "$subnet_id" || "$subnet_id" == "None" ]]; then
            log_error "No subnet found in VPC $vpc_id for supported AZs: $supported_azs" >&2
            return 1
        fi
        log_info "  Subnet: $subnet_id" >&2
    fi

    local instance_id
    if [[ -n "$subnet_id" ]]; then
        instance_id=$(aws ec2 run-instances \
            --image-id "$ami_id" \
            --instance-type "$instance_type" \
            --key-name "$key_name" \
            --security-group-ids "$sg_id" \
            --subnet-id "$subnet_id" \
            --block-device-mappings "[{
                \"DeviceName\": \"/dev/sda1\",
                \"Ebs\": {
                    \"VolumeSize\": $volume_size,
                    \"VolumeType\": \"gp3\",
                    \"Iops\": 16000,
                    \"Throughput\": 1000,
                    \"DeleteOnTermination\": true
                }
            }]" \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance_name}]" \
            --region "$region" \
            --query 'Instances[0].InstanceId' \
            --output text)
    else
        instance_id=$(aws ec2 run-instances \
            --image-id "$ami_id" \
            --instance-type "$instance_type" \
            --key-name "$key_name" \
            --security-group-ids "$sg_id" \
            --block-device-mappings "[{
                \"DeviceName\": \"/dev/sda1\",
                \"Ebs\": {
                    \"VolumeSize\": $volume_size,
                    \"VolumeType\": \"gp3\",
                    \"Iops\": 16000,
                    \"Throughput\": 1000,
                    \"DeleteOnTermination\": true
                }
            }]" \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance_name}]" \
            --region "$region" \
            --query 'Instances[0].InstanceId' \
            --output text)
    fi

    if [[ -z "$instance_id" ]]; then
        log_error "Failed to launch instance"
        return 1
    fi

    log_success "Instance launched: $instance_id" >&2
    echo "$instance_id"

    return 0
}

wait_for_instance_running() {
    local instance_id=$1
    local region=${2:-$AWS_REGION}

    log_info "Waiting for instance to be running..."

    aws ec2 wait instance-running \
        --instance-ids "$instance_id" \
        --region "$region"

    log_success "Instance is running"

    return 0
}

get_instance_ip() {
    local instance_id=$1
    local region=${2:-$AWS_REGION}

    local ip
    ip=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$region" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    echo "$ip"
}

wait_for_ssh() {
    local host=$1
    local ssh_key=$2
    local max_attempts=${3:-30}
    local delay=${4:-10}

    log_info "Waiting for SSH to be available on $host..."

    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "SSH attempt $attempt/$max_attempts"

        if ssh -i "$ssh_key" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 \
            -o LogLevel=ERROR \
            "$host" \
            "echo 'SSH ready'" >/dev/null 2>&1; then

            log_success "SSH is ready"
            return 0
        fi

        sleep "$delay"
        attempt=$((attempt + 1))
    done

    log_error "SSH not available after $max_attempts attempts"
    return 1
}

stop_instance() {
    local instance_id=$1
    local region=${2:-$AWS_REGION}

    log_info "Stopping instance: $instance_id"

    aws ec2 stop-instances \
        --instance-ids "$instance_id" \
        --region "$region" \
        >/dev/null

    log_success "Instance stop initiated"

    return 0
}

start_instance() {
    local instance_id=$1
    local region=${2:-$AWS_REGION}

    log_info "Starting instance: $instance_id"

    aws ec2 start-instances \
        --instance-ids "$instance_id" \
        --region "$region" \
        >/dev/null

    log_success "Instance start initiated"

    return 0
}

terminate_instance() {
    local instance_id=$1
    local region=${2:-$AWS_REGION}

    log_warn "Terminating instance: $instance_id"

    aws ec2 terminate-instances \
        --instance-ids "$instance_id" \
        --region "$region" \
        >/dev/null

    log_success "Instance termination initiated"

    return 0
}

get_instance_status() {
    local instance_id=$1
    local region=${2:-$AWS_REGION}

    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$region" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text
}

# ============================================================================
# Auto-Stop Scheduling
# ============================================================================

schedule_instance_stop() {
    local instance_id=$1
    local hours=$2
    local region=${3:-$AWS_REGION}

    log_info "Scheduling instance stop in $hours hours"

    # Calculate stop time
    local stop_time
    stop_time=$(date -u -d "+${hours} hours" '+%Y-%m-%dT%H:%M:%S')

    # Create a tag to track scheduled stop time
    aws ec2 create-tags \
        --resources "$instance_id" \
        --tags "Key=AutoStopTime,Value=$stop_time" \
        --region "$region"

    log_success "Scheduled stop time: $stop_time UTC"
    log_info "Run './scripts/stop-validator.sh' to stop manually before scheduled time"

    return 0
}

check_auto_stop() {
    local instance_id=$1
    local region=${2:-$AWS_REGION}

    # Get the auto-stop time tag
    local stop_time
    stop_time=$(aws ec2 describe-tags \
        --filters \
            "Name=resource-id,Values=$instance_id" \
            "Name=key,Values=AutoStopTime" \
        --region "$region" \
        --query 'Tags[0].Value' \
        --output text 2>/dev/null)

    if [[ -z "$stop_time" || "$stop_time" == "None" ]]; then
        return 0
    fi

    # Check if current time is past stop time
    local current_time
    current_time=$(date -u '+%Y-%m-%dT%H:%M:%S')

    if [[ "$current_time" > "$stop_time" ]]; then
        log_warn "Auto-stop time reached: $stop_time UTC"
        return 1
    fi

    return 0
}

# ============================================================================
# Cost Tracking
# ============================================================================

estimate_instance_cost() {
    local instance_type=$1
    local hours=$2

    # Pricing for common instance types (approximate, varies by region)
    local hourly_rate
    case "$instance_type" in
        m7i.4xlarge)
            hourly_rate=0.8064
            ;;
        m7i.2xlarge)
            hourly_rate=0.4032
            ;;
        m7i-flex.4xlarge)
            hourly_rate=0.65
            ;;
        m6i.4xlarge)
            hourly_rate=0.768
            ;;
        m6i.2xlarge)
            hourly_rate=0.384
            ;;
        t3.2xlarge)
            hourly_rate=0.3328
            ;;
        *)
            hourly_rate=0.5
            log_warn "Unknown instance type, using estimated rate: \$${hourly_rate}/hour"
            ;;
    esac

    local total_cost
    total_cost=$(calculate_cost "$hours" "$hourly_rate")

    echo "$total_cost"

    return 0
}

get_instance_uptime() {
    local instance_id=$1
    local region=${2:-$AWS_REGION}

    local launch_time
    launch_time=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$region" \
        --query 'Reservations[0].Instances[0].LaunchTime' \
        --output text)

    if [[ -z "$launch_time" ]]; then
        echo "0"
        return
    fi

    # Convert to epoch and calculate hours
    local launch_epoch
    launch_epoch=$(date -d "$launch_time" +%s)
    local current_epoch
    current_epoch=$(date +%s)

    local uptime_seconds=$((current_epoch - launch_epoch))
    local uptime_hours=$((uptime_seconds / 3600))

    echo "$uptime_hours"
}
