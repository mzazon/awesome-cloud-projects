# Infrastructure as Code for Scalable Browser Testing Pipeline with Playwright Testing and Application Insights

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scalable Browser Testing Pipeline with Playwright Testing and Application Insights".

## Available Implementations

- **Bicep**: Azure native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code  
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.57.0 or later installed and configured
- Node.js 18.x or later with npm package manager
- Appropriate Azure permissions for resource creation:
  - Contributor role on target subscription/resource group
  - Key Vault Secrets Officer role for credential management
  - Application Insights Component Contributor role
- Basic knowledge of Playwright testing framework

## Quick Start

### Using Bicep

```bash
# Navigate to bicep directory
cd bicep/

# Create resource group
az group create \
    --name "rg-playwright-testing" \
    --location "eastus"

# Deploy infrastructure
az deployment group create \
    --resource-group "rg-playwright-testing" \
    --template-file main.bicep \
    --parameters @parameters.json

# Get deployment outputs
az deployment group show \
    --resource-group "rg-playwright-testing" \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment summary
cat deployment-summary.txt
```

## Architecture Components

This infrastructure deployment creates:

- **Resource Group**: Container for all testing resources
- **Application Insights**: Monitoring and telemetry collection
- **Log Analytics Workspace**: Backend for Application Insights
- **Azure Key Vault**: Secure storage for test credentials and secrets
- **Role Assignments**: Appropriate RBAC permissions for services
- **Alert Rules**: Monitoring alerts for test failure rates

## Configuration Parameters

### Bicep Parameters

Edit `bicep/parameters.json` to customize the deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "environment": {
      "value": "testing"
    },
    "keyVaultName": {
      "value": "kv-playwright-unique"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize the deployment:

```hcl
location = "East US"
environment = "testing"
key_vault_name = "kv-playwright-unique"
application_insights_name = "ai-playwright-testing"
enable_public_access = true
```

### Script Configuration

Edit variables at the top of `scripts/deploy.sh`:

```bash
# Configuration variables
RESOURCE_GROUP="rg-playwright-testing"
LOCATION="eastus"
ENVIRONMENT="testing"
```

## Post-Deployment Setup

After deploying the infrastructure, complete these manual steps:

### 1. Create Playwright Testing Workspace

The Azure Playwright Testing workspace must be created through the Azure Portal:

1. Navigate to: https://aka.ms/mpt/portal
2. Sign in with your Azure account
3. Click "+ New workspace"
4. Select your subscription and region
5. Enter a unique workspace name
6. Click "Create workspace"
7. Copy the service endpoint URL for test configuration

### 2. Initialize Test Project

```bash
# Create test project directory
mkdir playwright-azure-tests && cd playwright-azure-tests

# Initialize npm project
npm init -y

# Install dependencies
npm install --save-dev @playwright/test
npm install --save-dev @azure/microsoft-playwright-testing
npm install --save-dev @azure/keyvault-secrets @azure/identity
npm install --save-dev applicationinsights

# Initialize Playwright Testing configuration
npx init @azure/microsoft-playwright-testing@latest
```

### 3. Configure Environment Variables

```bash
# Set required environment variables
export PLAYWRIGHT_SERVICE_URL="https://eastus.api.playwright.microsoft.com"
export KEYVAULT_NAME="your-keyvault-name"
export AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
```

## Validation & Testing

### Verify Infrastructure

```bash
# Check resource group
az group show --name "rg-playwright-testing"

# Verify Application Insights
az monitor app-insights component show \
    --app "ai-playwright-testing" \
    --resource-group "rg-playwright-testing"

# Verify Key Vault
az keyvault show \
    --name "your-keyvault-name" \
    --resource-group "rg-playwright-testing"
```

### Test Playwright Integration

```bash
# Run sample tests locally
npm run test:local

# Run tests on Azure Playwright Testing
npm run test:azure

# View test reports
npx playwright show-report
```

## Monitoring and Alerts

The deployment includes pre-configured monitoring:

- **Application Insights Dashboard**: Custom queries for test analytics
- **Alert Rules**: Notifications for high test failure rates
- **Custom Metrics**: Test duration and success rate tracking
- **Log Analytics**: Centralized logging for all test execution

Access monitoring through:
- Azure Portal → Application Insights → Overview
- Azure Portal → Monitor → Alerts
- Playwright Testing Portal: https://aka.ms/mpt/portal

## Security Considerations

- **Key Vault Access**: Uses Azure RBAC for fine-grained permissions
- **Managed Identity**: Recommended for production CI/CD pipelines
- **Network Security**: Consider private endpoints for production environments
- **Secret Rotation**: Implement automated credential rotation

## Cost Optimization

- **Pay-per-use**: Azure Playwright Testing charges only for test execution time
- **Application Insights**: Uses pay-as-you-go pricing model
- **Key Vault**: Low-cost secret storage with transaction-based pricing
- **Estimated Monthly Cost**: $50-100 for moderate test volume

## Cleanup

### Using Bicep

```bash
# Delete resource group and all resources
az group delete \
    --name "rg-playwright-testing" \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group show --name "rg-playwright-testing" \
    --query "properties.provisioningState" || echo "Resource group deleted"
```

## Troubleshooting

### Common Issues

1. **Key Vault Access Denied**
   ```bash
   # Assign yourself Key Vault Secrets Officer role
   az role assignment create \
       --role "Key Vault Secrets Officer" \
       --assignee $(az ad signed-in-user show --query id -o tsv) \
       --scope $(az keyvault show --name your-keyvault-name --query id -o tsv)
   ```

2. **Playwright Service Connection Failed**
   - Verify the service endpoint URL is correct
   - Check that the workspace was created in the same region
   - Ensure Azure authentication is properly configured

3. **Application Insights Data Missing**
   - Verify the connection string is correctly configured
   - Check that telemetry client is properly initialized
   - Allow 5-10 minutes for data to appear in Application Insights

### Debug Commands

```bash
# Check Azure CLI authentication
az account show

# Verify resource deployment status
az deployment group list \
    --resource-group "rg-playwright-testing" \
    --query "[].{Name:name, State:properties.provisioningState}"

# Test Key Vault connectivity
az keyvault secret list --vault-name "your-keyvault-name"
```

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check Azure service health status
3. Review Azure Monitor logs for detailed error information
4. Consult the [Azure Playwright Testing documentation](https://docs.microsoft.com/en-us/azure/playwright-testing/)

## Contributing

When modifying this infrastructure:
1. Test changes in a development environment first
2. Update parameter documentation
3. Verify all deployment methods work correctly
4. Update this README with any new requirements or steps