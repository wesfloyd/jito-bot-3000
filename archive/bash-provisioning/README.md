# Bash-Only Provisioning Code Archive

This directory contains the original bash-only AWS provisioning code that was replaced by Terraform.

## Archived Files

- `01-provision-aws.sh` - Original AWS infrastructure provisioning script
- `get-status.sh` - Original status checking script  
- `aws-helpers.sh` - Original AWS CLI helper functions

## Migration Reason

These files were replaced by Terraform-based provisioning for the following reasons:

### Problems with Bash-Only Approach:
- ❌ Manual AWS CLI calls with complex error handling
- ❌ No state management (hard to track what's created)
- ❌ Difficult to handle edge cases (VPCs, subnets, AZs)
- ❌ No rollback capability if something fails
- ❌ Manual retry logic needed for rate limits
- ❌ API rate limiting issues during AWS outages

### Benefits of Terraform Approach:
- ✅ **Declarative**: Describe what you want, not how to get there
- ✅ **State management**: Tracks what's created/destroyed
- ✅ **Dependency resolution**: Automatically handles VPC → Subnet → Instance
- ✅ **Built-in retry logic**: Handles AWS API rate limits automatically
- ✅ **Plan before apply**: See what will be created before doing it
- ✅ **Easy cleanup**: `terraform destroy` removes everything

## Replacement Files

The following Terraform-based files replaced the archived bash scripts:

- `scripts/01-terraform-init.sh` - Terraform initialization and validation
- `scripts/02-terraform-plan.sh` - Show planned changes
- `scripts/03-terraform-apply.sh` - Apply infrastructure
- `scripts/10-monitor.sh` - Status monitoring (Terraform-based)
- `scripts/11-terraform-destroy.sh` - Cleanup infrastructure
- `scripts/lib/terraform-helpers.sh` - Terraform utility functions

## Migration Date

Archived on: October 20, 2025

## Note

These files are kept for reference and potential rollback if needed, but the Terraform approach is the recommended way forward.
