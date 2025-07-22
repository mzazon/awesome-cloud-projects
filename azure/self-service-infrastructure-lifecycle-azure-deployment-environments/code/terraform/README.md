# Azure Deployment Environments - Terraform Infrastructure

This Terraform configuration deploys a complete self-service infrastructure lifecycle platform using Azure Deployment Environments and Azure DevCenter.

## Overview

This infrastructure enables development teams to provision, manage, and teardown standardized environments on-demand while maintaining enterprise governance, cost controls, and security policies.

## Architecture

The solution deploys the following components:

- **Azure DevCenter**: Central hub for managing development environments
- **DevCenter Project**: Organizational unit for development teams
- **Environment Types**: Different deployment targets (development, staging, production)
- **Catalog**: Repository of infrastructure templates
- **Storage Account**: Secure storage for ARM templates and infrastructure definitions
- **RBAC Assignments**: Role-based access control for self-service capabilities
- **Monitoring**: Log Analytics and Application Insights integration
- **Cost Management**: Budget monitoring and alerts

## Prerequisites

1. **Azure CLI** installed and authenticated
2. **Terraform** >= 1.0 installed
3. **Azure subscription** with appropriate permissions:
   - Contributor access to the subscription
   - User Access Administrator role (for RBAC assignments)
4. **Azure Provider Features**: Microsoft.DevCenter resource provider registered

## Quick Start

### 1. Clone and Initialize

```bash
# Clone the repository
git clone <repository-url>
cd azure/self-service-infrastructure-lifecycle-azure-deployment-environments/code/terraform

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Basic Configuration
project_name = "myproject"
location     = "East US"
environment  = "dev"

# Optional: Custom resource names
resource_group_name    = "rg-devcenter-myproject"
devcenter_name        = "dc-myproject"
devcenter_project_name = "proj-myproject"
storage_account_name  = "stmyproject123"

# Cost Management
cost_management_budget = 1000
notification_emails    = ["admin@company.com"]

# Environment Configuration
environment_types = [
  {
    name        = "development"
    description = "Development environment with cost controls"
    tags = {
      tier         = "development"
      cost-center  = "engineering"
      auto-delete  = "true"
    }
  },
  {
    name        = "staging"
    description = "Staging environment with monitoring"
    tags = {
      tier         = "staging"
      cost-center  = "engineering"
      monitoring   = "enhanced"
    }
  }
]

# Tagging
tags = {
  purpose     = "infrastructure-lifecycle"
  managed-by  = "terraform"
  team        = "platform-engineering"
  project     = "myproject"
}
```

### 3. Plan and Apply

```bash
# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### 4. Verify Deployment

```bash
# Check deployment status
terraform output

# Test Azure CLI integration
az devcenter dev environment list \
  --project-name $(terraform output -raw project_name) \
  --endpoint $(terraform output -raw devcenter_dev_center_uri)
```

## Configuration Options

### Environment Types

Configure different environment types for various deployment targets:

```hcl
environment_types = [
  {
    name        = "development"
    description = "Development environment with cost controls"
    tags = {
      tier         = "development"
      cost-center  = "engineering"
      auto-delete  = "true"
      max-duration = "72h"
    }
  },
  {
    name        = "staging"
    description = "Staging environment with monitoring"
    tags = {
      tier         = "staging"
      cost-center  = "engineering"
      monitoring   = "enhanced"
      max-duration = "168h"
    }
  },
  {
    name        = "production"
    description = "Production environment with full monitoring"
    tags = {
      tier         = "production"
      cost-center  = "engineering"
      monitoring   = "full"
      backup       = "enabled"
    }
  }
]
```

### Monitoring Configuration

Enable comprehensive monitoring:

```hcl
enable_monitoring          = true
log_analytics_retention_days = 90
```

### Cost Management

Configure budget alerts:

```hcl
cost_management_budget           = 1000
budget_alert_threshold_actual    = 80
budget_alert_threshold_forecast  = 90
notification_emails             = ["admin@company.com", "team@company.com"]
```

### Security Configuration

Configure RBAC and security:

```hcl
enable_rbac_assignments = true
allowed_locations       = ["East US", "East US 2", "West US 2"]
```

## Usage

### Azure Developer CLI Integration

Configure Azure Developer CLI for seamless integration:

```bash
# Configure azd for DevCenter
azd config set platform.type devcenter

# Initialize application
azd init --template minimal

# Deploy environment
azd provision --environment development
```

### Azure CLI Commands

Manage environments using Azure CLI:

```bash
# List available environments
az devcenter dev environment list \
  --project-name <project-name> \
  --endpoint <devcenter-endpoint>

# Create environment
az devcenter dev environment create \
  --project-name <project-name> \
  --endpoint <devcenter-endpoint> \
  --environment-name "my-webapp-dev" \
  --environment-type "development" \
  --catalog-name "catalog-templates" \
  --environment-definition-name "webapp-env"

# Delete environment
az devcenter dev environment delete \
  --project-name <project-name> \
  --endpoint <devcenter-endpoint> \
  --environment-name "my-webapp-dev"
```

## Outputs

The configuration provides comprehensive outputs for integration:

- `devcenter_name`: Name of the DevCenter
- `project_name`: Name of the DevCenter project
- `devcenter_dev_center_uri`: DevCenter API endpoint
- `deployment_environments_info`: Complete connection information
- `useful_commands`: Azure CLI commands for management
- `azd_configuration`: Azure Developer CLI configuration

## Customization

### Adding Custom Templates

1. Create ARM templates in the storage account
2. Add environment manifests for Azure Developer CLI
3. Update the catalog to include new templates

### Custom Environment Types

Add new environment types by extending the `environment_types` variable:

```hcl
environment_types = [
  # ... existing types
  {
    name        = "testing"
    description = "Testing environment for QA"
    tags = {
      tier         = "testing"
      cost-center  = "qa"
      monitoring   = "standard"
    }
  }
]
```

### Advanced Monitoring

Enable advanced monitoring with custom Log Analytics queries:

```hcl
enable_monitoring = true
log_analytics_retention_days = 180
```

## Troubleshooting

### Common Issues

1. **Provider Registration**: Ensure Microsoft.DevCenter provider is registered
2. **Permissions**: Verify Contributor and User Access Administrator roles
3. **Naming Conflicts**: Use unique resource names or rely on auto-generation
4. **Region Availability**: Ensure Azure DevCenter is available in your region

### Debugging

Enable Terraform debug logging:

```bash
export TF_LOG=DEBUG
terraform apply
```

Check Azure CLI connectivity:

```bash
az account show
az provider show --namespace Microsoft.DevCenter
```

## Cost Optimization

- Enable auto-deletion for development environments
- Configure appropriate environment type SKUs
- Set up budget alerts and monitoring
- Use cost-effective storage tiers
- Implement resource tagging for cost tracking

## Security Best Practices

- Use managed identities for authentication
- Enable HTTPS-only for storage accounts
- Implement least privilege RBAC
- Use Azure Policy for governance
- Enable audit logging

## Support

For issues and questions:

1. Check the Terraform Azure Provider documentation
2. Review Azure DevCenter documentation
3. Consult Azure Deployment Environments guides
4. Submit issues to the repository

## License

This configuration is provided under the [MIT License](LICENSE).