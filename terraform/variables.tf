# ============================================================================
# AWS Configuration
# ============================================================================

variable "aws_region" {
  description = "AWS region to deploy in"
  type        = string
  default     = "us-west-1"
}

# ============================================================================
# EC2 Instance Configuration
# ============================================================================

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "m7i.4xlarge"
  
  validation {
    condition = can(regex("^[a-z][0-9][a-z]\\.[0-9]+xlarge$", var.instance_type))
    error_message = "Instance type must be a valid AWS instance type."
  }
}

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "jito-testnet-validator"
}

variable "ssh_user" {
  description = "SSH user for the instance (default for Ubuntu)"
  type        = string
  default     = "ubuntu"
}

# ============================================================================
# Storage Configuration
# ============================================================================

variable "volume_size" {
  description = "EBS volume size in GB"
  type        = number
  default     = 2048
  
  validation {
    condition     = var.volume_size >= 8
    error_message = "Volume size must be at least 8 GB."
  }
}

variable "volume_type" {
  description = "EBS volume type"
  type        = string
  default     = "gp3"
  
  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.volume_type)
    error_message = "Volume type must be gp2, gp3, io1, or io2."
  }
}

variable "volume_iops" {
  description = "IOPS for gp3 volumes"
  type        = number
  default     = 16000
  
  validation {
    condition     = var.volume_iops >= 3000 && var.volume_iops <= 16000
    error_message = "IOPS must be between 3000 and 16000 for gp3 volumes."
  }
}

variable "volume_throughput" {
  description = "Throughput for gp3 volumes in MB/s"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.volume_throughput >= 125 && var.volume_throughput <= 1000
    error_message = "Throughput must be between 125 and 1000 MB/s for gp3 volumes."
  }
}

# ============================================================================
# Network Configuration
# ============================================================================

variable "key_name" {
  description = "Name of the AWS key pair"
  type        = string
  default     = "jito-validator-key"
}

variable "security_group_name" {
  description = "Name of the security group"
  type        = string
  default     = "jito-validator-sg"
}

variable "admin_cidr" {
  description = "CIDR block for admin SSH access (auto-detected if empty)"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID to use (uses default VPC if empty)"
  type        = string
  default     = ""
}

# ============================================================================
# Auto-Stop Configuration
# ============================================================================

variable "auto_stop_hours" {
  description = "Automatically stop instance after X hours (0 to disable)"
  type        = number
  default     = 8
  
  validation {
    condition     = var.auto_stop_hours >= 0 && var.auto_stop_hours <= 8760
    error_message = "Auto-stop hours must be between 0 and 8760 (1 year)."
  }
}

# ============================================================================
# Paths and Directories
# ============================================================================

variable "keys_dir" {
  description = "Directory containing SSH keys"
  type        = string
  default     = "../keys"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "jito-validator"
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "testnet"
}
