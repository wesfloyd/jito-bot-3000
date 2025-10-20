# Infrastructure Management Scripts

Scripts for managing AWS infrastructure using Terraform.

## Workflow Order

1. **`init.sh`** - Initialize Terraform
2. **`plan.sh`** - Review planned changes
3. **`deploy.sh`** - Deploy infrastructure
4. **`start.sh`** / **`stop.sh`** - Manage running state
5. **`destroy.sh`** - Cleanup everything

## Scripts

### `init.sh`
Initializes Terraform workspace:
- Downloads provider plugins
- Validates configuration
- Sets up backend state
- Shows cost estimates

**Usage**: `./scripts/infra/init.sh`

### `plan.sh`
Shows planned infrastructure changes:
- Displays what will be created/modified
- Shows cost estimates
- Saves plan for apply

**Usage**: `./scripts/infra/plan.sh`

### `deploy.sh`
Deploys infrastructure to AWS:
- Creates EC2 instance
- Sets up security groups
- Configures networking
- Shows connection information

**Usage**: `./scripts/infra/deploy.sh`

### `start.sh`
Starts stopped infrastructure:
- Resumes EC2 instance
- Updates connection info
- Resumes compute costs

**Usage**: `./scripts/infra/start.sh`

### `stop.sh`
Stops infrastructure to save costs:
- Stops EC2 instance
- Preserves data on EBS
- Stops compute costs

**Usage**: `./scripts/infra/stop.sh`

### `destroy.sh`
Completely destroys infrastructure:
- Terminates EC2 instance
- Removes security groups
- Cleans up all resources
- Stops all costs

**Usage**: `./scripts/infra/destroy.sh`

## Cost Management

- **Deploy**: Creates resources, starts billing
- **Start**: Resumes compute costs (~$0.81/hour)
- **Stop**: Pauses compute costs, keeps storage (~$163.84/month)
- **Destroy**: Stops all costs completely
