# Validator Management Scripts

Scripts for managing the Solana validator instance.

## Scripts

### `start.sh`
Starts the validator instance:
- Powers on the EC2 instance
- Waits for SSH availability
- Shows connection information
- Provides validator status guidance

**Usage**: `./scripts/validator/start.sh`

### `stop.sh`
Stops the validator instance:
- Powers off the EC2 instance
- Preserves validator data
- Saves compute costs
- Shows cost savings

**Usage**: `./scripts/validator/stop.sh`

## Relationship to Infrastructure Scripts

These scripts work with Terraform-managed infrastructure:
- **Infrastructure scripts** (`scripts/infra/`) manage AWS resources
- **Validator scripts** (`scripts/validator/`) manage the validator application

Both can be used interchangeably for instance management, but validator scripts provide validator-specific guidance and status information.
