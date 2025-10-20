# ============================================================================
# Provider Configuration
# ============================================================================

provider "aws" {
  region = var.aws_region
}

# ============================================================================
# Data Sources
# ============================================================================

# Get current public IP for admin access
data "http" "admin_ip" {
  count = var.admin_cidr == "" ? 1 : 0
  url   = "https://checkip.amazonaws.com"
}

# Get default VPC
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Use specified VPC
data "aws_vpc" "selected" {
  count = var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

# Get available subnets in the VPC
data "aws_subnets" "available" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
}

# Get instance type offerings to find compatible AZs
data "aws_ec2_instance_type_offerings" "available" {
  location_type = "availability-zone"
  
  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

# Get latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ============================================================================
# Local Values
# ============================================================================

locals {
  # Use selected VPC or default VPC
  vpc_id = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  
  # Use auto-detected admin IP or specified CIDR
  admin_cidr = var.admin_cidr != "" ? var.admin_cidr : "${chomp(data.http.admin_ip[0].response_body)}/32"
  
  # Use first available subnet (Terraform will handle AZ compatibility during apply)
  selected_subnet = data.aws_subnets.available.ids[0]
  
  # Calculate auto-stop time if enabled
  auto_stop_time = var.auto_stop_hours > 0 ? timeadd(timestamp(), "${var.auto_stop_hours}h") : null
}

# Get subnet details
data "aws_subnet" "subnets" {
  for_each = toset(data.aws_subnets.available.ids)
  id       = each.value
}

# ============================================================================
# Security Group
# ============================================================================

resource "aws_security_group" "jito_validator" {
  name_prefix = "${var.security_group_name}-"
  description = "Security group for Jito validator"
  vpc_id      = local.vpc_id

  # SSH access from admin IP
  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  # Solana gossip protocol (UDP)
  ingress {
    description = "Solana gossip UDP"
    from_port   = 8000
    to_port     = 8020
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Solana gossip protocol (TCP)
  ingress {
    description = "Solana gossip TCP"
    from_port   = 8000
    to_port     = 8020
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # RPC ports (required for external RPC access and validator health checks)
  ingress {
    description = "RPC endpoints"
    from_port   = 8899
    to_port     = 8900
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Use local.admin_cidr to restrict to your IP only
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = var.security_group_name
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    CreatedAt   = timestamp()
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# SSH Key Pair
# ============================================================================

resource "aws_key_pair" "jito_validator" {
  key_name   = var.key_name
  public_key = file("${var.keys_dir}/${var.key_name}.pub")

  tags = {
    Name        = var.key_name
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    CreatedAt   = timestamp()
  }
}

# ============================================================================
# EC2 Instance
# ============================================================================

resource "aws_instance" "jito_validator" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name              = aws_key_pair.jito_validator.key_name
  vpc_security_group_ids = [aws_security_group.jito_validator.id]
  subnet_id             = local.selected_subnet

  # Root volume configuration
  root_block_device {
    volume_size           = var.volume_size
    volume_type           = var.volume_type
    iops                  = var.volume_type == "gp3" ? var.volume_iops : null
    throughput            = var.volume_type == "gp3" ? var.volume_throughput : null
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.instance_name}-root"
    }
  }

  # Enable detailed monitoring if needed
  monitoring = false

  # Tags including auto-stop if configured
  tags = merge(
    {
      Name        = var.instance_name
      Description = "Jito Solana Testnet Validator"
    },
    local.auto_stop_time != null ? {
      AutoStopTime = local.auto_stop_time
    } : {}
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# Optional: Elastic IP (uncomment if needed)
# ============================================================================

# resource "aws_eip" "jito_validator" {
#   instance = aws_instance.jito_validator.id
#   domain   = "vpc"
# 
#   tags = {
#     Name = "${var.instance_name}-eip"
#   }
# 
#   depends_on = [aws_instance.jito_validator]
# }
