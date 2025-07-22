# Infrastructure as Code for Governed Infrastructure Provisioning with Azure Deployment Environments and Service Connector

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Governed Infrastructure Provisioning with Azure Deployment Environments and Service Connector".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (v2.50.0 or later)
- Azure subscription with appropriate permissions for:
  - Creating Azure Deployment Environments resources
  - Creating Logic Apps and Event Grid resources
  - Creating Azure SQL Database and Key Vault resources
  - Managing Azure AD roles and service principals
- The following Azure AD roles are required:
  - DevCenter Admin
  - Project Admin
  - Contributor (on target subscription/resource group)
- Appropriate permissions for resource creation and role assignments
- Basic understanding of Infrastructure as Code concepts
- Familiarity with Azure Logic Apps and workflow design

## Architecture Overview

This solution implements a comprehensive self-service infrastructure platform that includes:

- **Azure Deployment Environments**: DevCenter and project configuration for environment management
- **Azure Service Connector**: Automated service connectivity and authentication
- **Azure Logic Apps**: Workflow orchestration for approval processes and lifecycle management
- **Azure Event Grid**: Event-driven automation for deployment workflows
- **Azure Key Vault**: Secure storage for secrets and connection strings
- **Azure SQL Database**: Sample backing service with automated connectivity

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the bicep directory
cd bicep/

# Create a resource group
az group create \
    --name rg-selfservice-infra \
    --location eastus

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-selfservice-infra \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration Options

### Bicep Parameters

The Bicep implementation uses a `parameters.json` file with the following configurable values:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "environmentPrefix": {
      "value": "selfservice"
    },
    "sqlAdminUsername": {
      "value": "sqladmin"
    },
    "sqlAdminPassword": {
      "value": "P@ssw0rd123!"
    },
    "catalogRepoUrl": {
      "value": "https://github.com/Azure/deployment-environments"
    },
    "catalogBranch": {
      "value": "main"
    },
    "catalogPath": {
      "value": "/Environments"
    }
  }
}
```

### Terraform Variables

The Terraform implementation supports the following variables in `terraform.tfvars`:

```hcl
location = "East US"
environment_prefix = "selfservice"
sql_admin_username = "sqladmin"
sql_admin_password = "P@ssw0rd123!"
catalog_repo_url = "https://github.com/Azure/deployment-environments"
catalog_branch = "main"
catalog_path = "/Environments"
max_dev_boxes_per_user = 3
environment_expiry_days = 7
tags = {
  purpose = "selfservice-infrastructure"
  environment = "demo"
  owner = "platform-team"
}
```

### Script Configuration

The bash scripts use environment variables for configuration:

```bash
export LOCATION="eastus"
export ENVIRONMENT_PREFIX="selfservice"
export SQL_ADMIN_USERNAME="sqladmin"
export SQL_ADMIN_PASSWORD="P@ssw0rd123!"
export CATALOG_REPO_URL="https://github.com/Azure/deployment-environments"
export CATALOG_BRANCH="main"
export CATALOG_PATH="/Environments"
```

## Post-Deployment Configuration

After deploying the infrastructure, complete these additional setup steps:

### 1. Configure User Access

```bash
# Assign users to the DevCenter Project Admin role
az role assignment create \
    --assignee <user-principal-id> \
    --role "DevCenter Project Admin" \
    --scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.DevCenter/projects/<project-name>"

# Assign users to the DevCenter Dev Box User role
az role assignment create \
    --assignee <user-principal-id> \
    --role "DevCenter Dev Box User" \
    --scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.DevCenter/projects/<project-name>"
```

### 2. Customize Environment Catalog

The default deployment uses Microsoft's sample environment catalog. To use your own templates:

```bash
# Update the catalog to point to your repository
az devcenter admin catalog update \
    --name <catalog-name> \
    --devcenter-name <devcenter-name> \
    --resource-group <resource-group> \
    --git-hub-repo-url "https://github.com/your-org/your-environment-templates" \
    --git-hub-branch "main" \
    --git-hub-path "/templates"
```

### 3. Configure Approval Workflows

Customize the Logic Apps workflows to integrate with your organization's approval systems:

- Modify the approval Logic App to integrate with Microsoft Teams, ServiceNow, or other systems
- Update the lifecycle management Logic App to implement your organization's policies
- Configure Event Grid filters to process only relevant deployment events

## Testing the Deployment

### 1. Verify DevCenter Configuration

```bash
# List available environment definitions
az devcenter dev environment-definition list \
    --project-name <project-name> \
    --dev-center-name <devcenter-name>

# Check catalog synchronization status
az devcenter admin catalog show \
    --name <catalog-name> \
    --devcenter-name <devcenter-name> \
    --resource-group <resource-group> \
    --query "syncState"
```

### 2. Test Environment Provisioning

```bash
# Create a test environment
az devcenter dev environment create \
    --project-name <project-name> \
    --dev-center-name <devcenter-name> \
    --environment-name "test-webapp-env" \
    --environment-type "Development" \
    --catalog-name <catalog-name> \
    --environment-definition-name "WebApp" \
    --parameters '{"name": "test-webapp-001"}'

# Monitor environment deployment status
az devcenter dev environment show \
    --project-name <project-name> \
    --dev-center-name <devcenter-name> \
    --environment-name "test-webapp-env"
```

### 3. Validate Service Connections

```bash
# List service connections for deployed web apps
az webapp connection list \
    --resource-group <target-resource-group> \
    --name <webapp-name>

# Test connection health
az webapp connection validate \
    --resource-group <target-resource-group> \
    --name <webapp-name> \
    --connection-name <connection-name>
```

## Monitoring and Operations

### Key Metrics to Monitor

- Environment provisioning success rate
- Average deployment time
- Resource utilization and costs
- Security compliance status
- User adoption and satisfaction

### Logging and Diagnostics

```bash
# Enable diagnostic settings for DevCenter
az monitor diagnostic-settings create \
    --name "devcenter-diagnostics" \
    --resource "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.DevCenter/devcenters/<devcenter-name>" \
    --logs '[{"category":"Audit","enabled":true}]' \
    --workspace "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.OperationalInsights/workspaces/<workspace-name>"

# Monitor Logic Apps execution history
az logic workflow show \
    --name <logic-app-name> \
    --resource-group <resource-group> \
    --query "state"
```

## Security Considerations

### Identity and Access Management

- Use Azure AD integration for user authentication
- Implement least privilege access principles
- Regularly review and audit role assignments
- Use managed identities for service-to-service authentication

### Network Security

- Configure private endpoints for sensitive services
- Implement network security groups (NSGs) for traffic filtering
- Use Azure Firewall or Application Gateway for additional protection
- Enable Azure Private Link for secure service connectivity

### Data Protection

- Enable encryption at rest for all storage services
- Use Azure Key Vault for secrets management
- Implement data classification and protection policies
- Enable audit logging for compliance requirements

## Troubleshooting

### Common Issues

1. **Catalog Synchronization Failures**
   ```bash
   # Check catalog sync status and errors
   az devcenter admin catalog show \
       --name <catalog-name> \
       --devcenter-name <devcenter-name> \
       --resource-group <resource-group> \
       --query "{syncState: syncState, lastSyncStats: lastSyncStats}"
   ```

2. **Environment Deployment Failures**
   ```bash
   # Get detailed error information
   az devcenter dev environment show \
       --project-name <project-name> \
       --dev-center-name <devcenter-name> \
       --environment-name <environment-name> \
       --query "provisioningState"
   ```

3. **Service Connection Issues**
   ```bash
   # Validate service connections
   az webapp connection validate \
       --resource-group <resource-group> \
       --name <webapp-name> \
       --connection-name <connection-name>
   ```

### Getting Help

- Review the [Azure Deployment Environments documentation](https://learn.microsoft.com/en-us/azure/deployment-environments/)
- Check the [Azure Service Connector troubleshooting guide](https://learn.microsoft.com/en-us/azure/service-connector/troubleshoot-common-issues)
- Use Azure Support for production issues
- Consult the original recipe documentation for implementation details

## Cost Optimization

### Resource Cost Management

- Implement environment expiration policies to automatically clean up unused resources
- Use Azure Cost Management to monitor spending and set budget alerts
- Choose appropriate service tiers based on usage requirements
- Implement scheduled scaling for non-production environments

### Estimated Costs

**Development Environment (Monthly)**:
- DevCenter: ~$10-20
- Logic Apps: ~$5-15 (based on executions)
- Event Grid: ~$1-5
- Key Vault: ~$1-3
- SQL Database (S0): ~$15-25
- Storage Account: ~$1-5
- **Total: ~$33-73 per month**

**Production Environment (Monthly)**:
- Scale up based on user count and environment usage
- Estimate $100-500+ depending on scale and resource types

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-selfservice-infra \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Destroy all resources
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification

After running the automated cleanup, verify that all resources have been removed:

```bash
# List any remaining resources in the resource group
az resource list \
    --resource-group rg-selfservice-infra \
    --output table

# Check for any orphaned role assignments
az role assignment list \
    --all \
    --query "[?contains(scope, 'rg-selfservice-infra')]"
```

## Customization

### Adding Custom Environment Templates

1. Create a new repository with your environment templates
2. Update the catalog configuration to point to your repository
3. Ensure templates follow Azure Resource Manager or Bicep standards
4. Test templates in a development environment before production use

### Extending Approval Workflows

1. Modify the Logic Apps to integrate with your approval systems
2. Add conditional logic based on environment type, cost, or user roles
3. Implement multi-stage approval processes for production environments
4. Add notifications via email, Teams, or other communication platforms

### Integrating with Existing Systems

1. Use Azure Service Connector to integrate with existing databases and services
2. Configure network connectivity to on-premises systems
3. Implement single sign-on (SSO) integration with existing identity providers
4. Add monitoring and alerting integration with existing ITSM tools

## Support

For issues with this infrastructure code, refer to:

1. The original recipe documentation
2. Azure provider documentation
3. Community forums and Stack Overflow
4. Azure Support for production environments

## Contributing

To contribute improvements to this infrastructure code:

1. Follow the code generation standards outlined in CLAUDE.iac.md
2. Test all changes thoroughly
3. Update documentation accordingly
4. Submit changes following the project's contribution guidelines