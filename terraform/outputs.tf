# ============================================================================
# Instance Information
# ============================================================================

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.jito_validator.id
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = aws_instance.jito_validator.arn
}

output "instance_type" {
  description = "Type of the EC2 instance"
  value       = aws_instance.jito_validator.instance_type
}

output "instance_state" {
  description = "State of the EC2 instance"
  value       = aws_instance.jito_validator.instance_state
}

# ============================================================================
# Network Information
# ============================================================================

output "public_ip" {
  description = "Public IP address of the instance"
  value       = aws_instance.jito_validator.public_ip
}

output "private_ip" {
  description = "Private IP address of the instance"
  value       = aws_instance.jito_validator.private_ip
}

output "public_dns" {
  description = "Public DNS name of the instance"
  value       = aws_instance.jito_validator.public_dns
}

output "private_dns" {
  description = "Private DNS name of the instance"
  value       = aws_instance.jito_validator.private_dns
}

output "subnet_id" {
  description = "ID of the subnet where the instance is deployed"
  value       = aws_instance.jito_validator.subnet_id
}

output "vpc_id" {
  description = "ID of the VPC where the instance is deployed"
  value       = local.vpc_id
}

output "availability_zone" {
  description = "Availability zone of the instance"
  value       = aws_instance.jito_validator.availability_zone
}

# ============================================================================
# Security Information
# ============================================================================

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.jito_validator.id
}

output "key_pair_name" {
  description = "Name of the SSH key pair"
  value       = aws_key_pair.jito_validator.key_name
}

# ============================================================================
# Connection Information
# ============================================================================

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${var.keys_dir}/${var.key_name}.pem ${var.ssh_user}@${aws_instance.jito_validator.public_ip}"
}

output "ssh_host" {
  description = "SSH host information"
  value       = "${var.ssh_user}@${aws_instance.jito_validator.public_ip}"
}

output "ssh_key_file" {
  description = "Path to the SSH private key file"
  value       = "${var.keys_dir}/${var.key_name}.pem"
}

# ============================================================================
# Cost and Monitoring
# ============================================================================

output "estimated_hourly_cost" {
  description = "Estimated hourly cost of the instance"
  value       = var.instance_type == "m7i.4xlarge" ? "~$0.81" : "Check AWS pricing"
}

output "auto_stop_time" {
  description = "Scheduled auto-stop time (if configured)"
  value       = local.auto_stop_time
}

# ============================================================================
# Deployment Information
# ============================================================================

output "region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "ami_id" {
  description = "AMI ID used for the instance"
  value       = aws_instance.jito_validator.ami
}

output "deployment_timestamp" {
  description = "Timestamp when resources were created"
  value       = timestamp()
}
