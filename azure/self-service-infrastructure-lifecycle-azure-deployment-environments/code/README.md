# Infrastructure as Code for Self-Service Infrastructure Lifecycle with Azure Deployment Environments

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Self-Service Infrastructure Lifecycle with Azure Deployment Environments and Developer CLI".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using the Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure Developer CLI (azd) v1.5.0 or later installed
- Azure subscription with Contributor access or higher
- Git repository access for storing infrastructure templates
- Understanding of Azure Resource Manager templates and infrastructure as code
- Terraform CLI (if using Terraform implementation)
- Appropriate permissions for Azure DevCenter and Deployment Environments
- Required Azure resource providers registered:
  - Microsoft.DevCenter
  - Microsoft.DeploymentEnvironments
- Estimated cost: $50-150/month depending on deployed environments

## Solution Overview

This infrastructure deploys a comprehensive self-service platform that enables developers to provision, manage, and teardown standardized environments on-demand while maintaining enterprise governance and security controls.

### Core Components

- **Azure DevCenter**: Central hub for managing development environments across your organization
- **Azure Deployment Environments**: Service for provisioning standardized, governed environments
- **Azure Resource Manager**: Template-based infrastructure deployment with built-in governance
- **Storage Account**: Secure repository for infrastructure templates and artifacts
- **RBAC Integration**: Role-based access control for granular permission management

### Key Features

- **Self-Service Environment Provisioning**: Developers can deploy environments instantly without IT involvement
- **Enterprise Governance**: Centralized policy enforcement, cost controls, and compliance management
- **Template Management**: Curated catalog of approved infrastructure templates with version control
- **Developer Experience**: Seamless integration with Azure Developer CLI and developer workflows
- **Cost Optimization**: Automated lifecycle policies and comprehensive cost tracking
- **Security Controls**: Managed identity authentication and comprehensive audit logging

### Architecture

The solution creates a multi-layered self-service infrastructure platform:

1. **Management Layer**: DevCenter provides centralized configuration and governance
2. **Organization Layer**: Projects organize development teams and define resource access
3. **Policy Layer**: Environment types enforce governance policies and deployment targets
4. **Template Layer**: Catalogs store and version approved infrastructure templates
5. **Deployment Layer**: Environments represent deployed instances with lifecycle management

## Quick Start

### Using Bicep

```bash
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters location=eastus

# View outputs
az deployment group show \
    --resource-group <your-resource-group> \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
az devcenter admin devcenter list --output table
```

## Configuration Options

### Bicep Parameters

The Bicep template supports the following parameters:

- `location`: Azure region for deployment (default: eastus)
- `resourceGroupName`: Name of the resource group
- `devCenterName`: Name of the Azure DevCenter (must be globally unique)
- `projectName`: Name of the DevCenter project
- `storageAccountName`: Name of the storage account for templates (must be globally unique)
- `environmentTypes`: Array of environment types to create (default: ["development", "staging"])
- `tags`: Common tags applied to all resources

### Terraform Variables

Customize the deployment by modifying `terraform.tfvars`:

```hcl
location = "eastus"
resource_group_name = "rg-devcenter-example"
devcenter_name = "dc-selfservice-example"
project_name = "proj-webapp-example"
storage_account_name = "stexampletemplates"
environment_types = ["development", "staging"]
tags = {
  Environment = "Demo"
  Purpose     = "Self-Service Infrastructure"
  Team        = "Platform Engineering"
}
```

### Script Configuration

The bash scripts use environment variables for configuration:

```bash
export RESOURCE_GROUP="rg-devcenter-demo"
export LOCATION="eastus"
export DEVCENTER_NAME="dc-selfservice-demo"
export PROJECT_NAME="proj-webapp-demo"
export STORAGE_ACCOUNT="stdemotemplates"
export ENVIRONMENT_TYPES="development,staging"
```

### Common Configuration Parameters

Both implementations support these key configuration options:

- **Location**: Azure region (recommend: eastus, westus2, or northeurope for full feature support)
- **Resource Naming**: All resources include unique suffixes to prevent naming conflicts
- **Environment Types**: Configurable list of deployment targets with governance policies
- **Tags**: Comprehensive tagging strategy for cost tracking and resource management
- **Security**: Managed identity and RBAC integration for secure operations

## Deployment Architecture

The infrastructure creates:

1. **Azure DevCenter**: Central hub for development environment management
2. **DevCenter Project**: Organizes development teams and environment access
3. **Storage Account**: Repository for infrastructure templates
4. **Environment Types**: Development and staging environment configurations
5. **Catalog**: Collection of approved infrastructure templates
6. **Environment Definitions**: Specific template configurations
7. **RBAC Assignments**: Role-based access control for developers

## Deployment Steps

### 1. Prepare Environment

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription <your-subscription-id>

# Create resource group
az group create \
    --name <resource-group-name> \
    --location <location>

# Register required providers
az provider register --namespace Microsoft.DevCenter
az provider register --namespace Microsoft.DeploymentEnvironments

# Verify provider registration
az provider show --namespace Microsoft.DevCenter --query "registrationState"
```

### 2. Deploy Infrastructure

Choose one of the deployment methods above based on your preference and organizational standards.

### 3. Post-Deployment Configuration

After deploying the infrastructure, complete these steps:

1. **Upload Infrastructure Templates**:
   ```bash
   # Upload sample web app template
   az storage blob upload \
       --file webapp-template.json \
       --name webapp-environment.json \
       --container-name templates \
       --account-name <storage-account-name> \
       --auth-mode login
   ```

2. **Configure Azure Developer CLI**:
   ```bash
   # Set platform type for azd
   azd config set platform.type devcenter
   
   # Verify configuration
   azd config show
   ```

3. **Set Up Environment Definitions**:
   ```bash
   # Create environment definition
   az devcenter admin environment-definition create \
       --name "webapp-env" \
       --catalog-name "catalog-templates" \
       --devcenter-name <devcenter-name> \
       --resource-group <resource-group-name> \
       --template-path "webapp-environment.json" \
       --description "Standard web application environment"
   ```

4. **Configure User Access**:
   ```bash
   # Get current user ID
   USER_ID=$(az ad signed-in-user show --query id --output tsv)
   
   # Assign Deployment Environments User role
   az role assignment create \
       --assignee ${USER_ID} \
       --role "Deployment Environments User" \
       --scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.DevCenter/projects/<project-name>"
   ```

5. **Test Environment Deployment**:
   ```bash
   # Create test environment
   az devcenter dev environment create \
       --project-name <project-name> \
       --endpoint "https://<devcenter-name>-<location>.devcenter.azure.com/" \
       --environment-name "test-env" \
       --environment-type "development" \
       --catalog-name "catalog-templates" \
       --environment-definition-name "webapp-env"
   ```

## Developer Experience

### Self-Service Environment Creation

Developers can create environments using multiple methods:

1. **Azure CLI**:
   ```bash
   az devcenter dev environment create \
       --project-name <project-name> \
       --endpoint <devcenter-endpoint> \
       --environment-name <env-name> \
       --environment-type development \
       --catalog-name catalog-templates \
       --environment-definition-name webapp-env
   ```

2. **Azure Developer CLI**:
   ```bash
   azd provision --environment development
   ```

3. **Azure Developer Portal**: Access through the Azure portal's Developer Center interface

### Environment Management

```bash
# List environments
az devcenter dev environment list \
    --project-name <project-name> \
    --endpoint <devcenter-endpoint>

# Get environment details
az devcenter dev environment show \
    --project-name <project-name> \
    --endpoint <devcenter-endpoint> \
    --environment-name <env-name>

# Delete environment
az devcenter dev environment delete \
    --project-name <project-name> \
    --endpoint <devcenter-endpoint> \
    --environment-name <env-name>
```

## Security Considerations

The infrastructure implements several security best practices:

- **Managed Identity**: DevCenter uses system-assigned managed identity
- **RBAC**: Role-based access control for environment management
- **Storage Security**: Storage account with disabled public access
- **Network Security**: Private endpoints can be configured for enhanced security
- **Audit Logging**: Azure Monitor integration for compliance tracking

## Cost Management

### Cost Optimization Features

- **Free Tier Resources**: Sample templates use free tier services
- **Automated Cleanup**: Environment lifecycle policies
- **Cost Alerts**: Integration with Azure Cost Management
- **Resource Tagging**: Comprehensive tagging for cost tracking

### Monitoring Costs

```bash
# View cost analysis for resource group
az consumption usage list \
    --scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group>" \
    --start-date 2025-01-01 \
    --end-date 2025-01-31
```

## Validation

After deployment, validate the setup with these commands:

```bash
# Check DevCenter status
az devcenter admin devcenter show \
    --name <devcenter-name> \
    --resource-group <resource-group-name> \
    --query "provisioningState" \
    --output tsv

# List environment types
az devcenter admin environment-type list \
    --devcenter-name <devcenter-name> \
    --resource-group <resource-group-name> \
    --output table

# Verify project configuration
az devcenter admin project show \
    --name <project-name> \
    --resource-group <resource-group-name> \
    --output json

# Test environment deployment
az devcenter dev environment create \
    --project-name <project-name> \
    --endpoint "https://<devcenter-name>-<location>.devcenter.azure.com/" \
    --environment-name "test-env" \
    --environment-type "development" \
    --catalog-name "catalog-templates" \
    --environment-definition-name "webapp-env"
```

Expected results:
- DevCenter should show "Succeeded" provisioning state
- Environment types should be listed with "Enabled" status
- Project should show associated environment types
- Test environment should deploy successfully

## Troubleshooting

### Common Issues

1. **DevCenter Creation Fails**:
   - Verify resource providers are registered: `az provider register --namespace Microsoft.DevCenter`
   - Check subscription permissions (Contributor or higher required)
   - Ensure region supports Azure DevCenter (use eastus, westus2, or northeurope)
   - Verify DevCenter name is globally unique

2. **Environment Deployment Fails**:
   - Verify template syntax in storage account
   - Check RBAC permissions: `az role assignment list --scope <resource-scope>`
   - Validate environment type configuration
   - Ensure storage account container exists and is accessible

3. **Azure Developer CLI Issues**:
   - Verify azd authentication: `azd auth login`
   - Check platform configuration: `azd config show`
   - Validate project configuration in azure.yaml
   - Ensure azd version is 1.5.0 or later

4. **Storage Account Access Issues**:
   - Verify managed identity has "Storage Blob Data Reader" role
   - Check that public blob access is disabled
   - Ensure templates container exists

### Debug Commands

```bash
# Check deployment status
az deployment group show \
    --resource-group <resource-group-name> \
    --name <deployment-name> \
    --query "properties.provisioningState"

# View activity logs
az monitor activity-log list \
    --resource-group <resource-group-name> \
    --start-time 2025-01-01T00:00:00Z \
    --output table

# Check resource provider registration
az provider show \
    --namespace Microsoft.DevCenter \
    --query "registrationState"

# Verify RBAC assignments
az role assignment list \
    --scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>" \
    --output table

# Test storage account access
az storage blob list \
    --container-name templates \
    --account-name <storage-account-name> \
    --auth-mode login
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name <resource-group-name> \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource group deletion
az group exists --name <resource-group-name>
```

## Advanced Configuration

### Custom Environment Templates

Create custom ARM templates for specific use cases:

```json
{
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "environmentName": {
            "type": "string"
        }
    },
    "resources": [
        // Your custom resources
    ]
}
```

### Multi-Environment Governance

Configure different policies for environment types:

```bash
# Create production environment type with stricter policies
az devcenter admin environment-type create \
    --name "production" \
    --devcenter-name <devcenter-name> \
    --resource-group <resource-group> \
    --tags tier=production compliance=required
```

### Integration with CI/CD

Example GitHub Actions workflow:

```yaml
name: Deploy Environment
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Deploy Environment
        run: |
          az devcenter dev environment create \
            --project-name ${{ secrets.PROJECT_NAME }} \
            --endpoint ${{ secrets.DEVCENTER_ENDPOINT }} \
            --environment-name "pr-${{ github.event.number }}" \
            --environment-type development
```

## Support

For issues with this infrastructure code, refer to:

### Documentation Resources
- [Original recipe documentation](../self-service-infrastructure-lifecycle-azure-deployment-environments.md)
- [Azure Deployment Environments documentation](https://docs.microsoft.com/en-us/azure/deployment-environments/)
- [Azure Developer CLI documentation](https://docs.microsoft.com/en-us/azure/developer/azure-developer-cli/)
- [Azure DevCenter documentation](https://docs.microsoft.com/en-us/azure/dev-center/)
- [Azure Resource Manager template documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/)
- [Terraform Azure Provider documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

### Best Practices and Guidance
- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)
- [Azure DevOps best practices](https://docs.microsoft.com/en-us/azure/devops/learn/)
- [Azure security best practices](https://docs.microsoft.com/en-us/azure/security/fundamentals/)
- [Azure cost optimization](https://docs.microsoft.com/en-us/azure/cost-management-billing/)

### Community Resources
- [Azure DevCenter community](https://techcommunity.microsoft.com/t5/azure-developer-community/bd-p/AzureDeveloperCommunity)
- [Azure Deployment Environments samples](https://github.com/Azure/deployment-environments)
- [Azure Developer CLI samples](https://github.com/Azure/azure-dev)

## Contributing

When modifying this infrastructure:

1. Follow Azure naming conventions and best practices
2. Implement proper resource tagging for cost tracking and governance
3. Include comprehensive parameter validation and error handling
4. Update documentation to reflect changes
5. Test changes in a non-production environment first
6. Consider backward compatibility with existing deployments
7. Follow the principle of least privilege for RBAC assignments

## License

This infrastructure code is provided as-is under the same license as the parent repository. See the recipe documentation for full terms and conditions.