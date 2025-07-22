# Infrastructure as Code for Centralized Configuration Management with App Configuration and Key Vault

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Centralized Configuration Management with App Configuration and Key Vault".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login` completed)
- Appropriate Azure permissions for:
  - Resource group creation and management
  - App Configuration store creation and management
  - Key Vault creation and management
  - Web App and App Service Plan creation
  - Role assignments and managed identity configuration
- For Terraform: Terraform v1.0+ installed
- For Bicep: Azure CLI with Bicep extension installed
- Estimated cost: $5-15 USD for resources created during deployment

## Architecture Overview

This solution deploys:
- **Azure App Configuration**: Centralized configuration store for application settings and feature flags
- **Azure Key Vault**: Secure storage for sensitive configuration data (secrets, connection strings, API keys)
- **Azure Web App**: Demo application with managed identity integration
- **App Service Plan**: Hosting environment for the web application
- **Role Assignments**: Proper RBAC permissions for secure access

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-config-mgmt \
    --template-file main.bicep \
    --parameters @parameters.json

# View deployment outputs
az deployment group show \
    --resource-group rg-config-mgmt \
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

# Apply the configuration
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

# View deployment status
./scripts/status.sh
```

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "appConfigName": {
      "value": "ac-config-demo"
    },
    "keyVaultName": {
      "value": "kv-secrets-demo"
    },
    "webAppName": {
      "value": "wa-demo-app"
    },
    "appServicePlanName": {
      "value": "asp-demo-plan"
    },
    "environment": {
      "value": "demo"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
location                = "eastus"
resource_group_name     = "rg-config-mgmt"
app_config_name         = "ac-config-demo"
key_vault_name          = "kv-secrets-demo"
web_app_name            = "wa-demo-app"
app_service_plan_name   = "asp-demo-plan"
environment             = "demo"
```

### Bash Script Environment Variables

Set these variables before running deployment scripts:

```bash
export LOCATION="eastus"
export RESOURCE_GROUP="rg-config-mgmt"
export APP_CONFIG_NAME="ac-config-demo"
export KEY_VAULT_NAME="kv-secrets-demo"
export WEB_APP_NAME="wa-demo-app"
export APP_SERVICE_PLAN="asp-demo-plan"
```

## Deployment Verification

After deployment, verify the solution works correctly:

1. **Test Web Application**:
   ```bash
   # Get web app URL from outputs
   WEB_APP_URL=$(az webapp show --name <web-app-name> --resource-group <resource-group> --query defaultHostName -o tsv)
   
   # Test the application
   curl -s "https://${WEB_APP_URL}" | jq '.'
   ```

2. **Verify Configuration Access**:
   ```bash
   # Check App Configuration settings
   az appconfig kv list --name <app-config-name> --query "[].{Key:key, Value:value}" -o table
   
   # Check Key Vault secrets (names only)
   az keyvault secret list --vault-name <key-vault-name> --query "[].name" -o tsv
   ```

3. **Test Managed Identity**:
   ```bash
   # Verify managed identity is assigned
   az webapp identity show --name <web-app-name> --resource-group <resource-group>
   ```

## Security Features

This implementation includes several security best practices:

- **Managed Identity**: Eliminates credential storage in code
- **Role-Based Access Control**: Least privilege access to configuration services
- **Key Vault Integration**: Secure storage and retrieval of sensitive data
- **Soft Delete Protection**: Key Vault configured with soft delete and purge protection
- **Network Security**: Resources deployed with appropriate network configurations

## Monitoring and Troubleshooting

### View Application Logs

```bash
# Stream web app logs
az webapp log tail --name <web-app-name> --resource-group <resource-group>

# Download log files
az webapp log download --name <web-app-name> --resource-group <resource-group>
```

### Check Configuration Status

```bash
# View App Configuration access logs
az monitor activity-log list --resource-group <resource-group> --caller <managed-identity-id>

# Check Key Vault access logs
az monitor activity-log list --resource-id /subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.KeyVault/vaults/<key-vault-name>
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name rg-config-mgmt --yes --no-wait

# If you need to purge Key Vault separately
az keyvault purge --name <key-vault-name> --location <location>
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Cost Optimization

To minimize costs during testing:

- Use **Basic** tier for App Service Plan (B1)
- Use **Standard** tier for App Configuration (includes feature flags)
- Use **Standard** tier for Key Vault (adequate for most scenarios)
- Clean up resources immediately after testing

## Customization

### Adding Configuration Settings

To add more configuration settings after deployment:

```bash
# Add new App Configuration setting
az appconfig kv set \
    --name <app-config-name> \
    --key "NewSetting" \
    --value "NewValue" \
    --label "Production"

# Add new Key Vault secret
az keyvault secret set \
    --vault-name <key-vault-name> \
    --name "NewSecret" \
    --value "SecretValue"
```

### Implementing Feature Flags

```bash
# Create feature flag
az appconfig feature set \
    --name <app-config-name> \
    --feature "NewFeature" \
    --label "Production"

# Enable/disable feature flag
az appconfig feature enable \
    --name <app-config-name> \
    --feature "NewFeature" \
    --label "Production"
```

### Multi-Environment Setup

For production deployments, consider:

1. **Separate Resource Groups**: Deploy each environment in its own resource group
2. **Environment-Specific Labels**: Use App Configuration labels for environment isolation
3. **Separate Key Vaults**: Use different Key Vaults for each environment
4. **Private Endpoints**: Enable private endpoints for enhanced security
5. **Backup and Recovery**: Implement backup strategies for configuration data

## Integration with CI/CD

### Azure DevOps Integration

```yaml
# azure-pipelines.yml example
trigger:
  branches:
    include:
      - main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: AzureCLI@2
  inputs:
    azureSubscription: 'Azure-Connection'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
      cd bicep/
      az deployment group create \
        --resource-group $(resourceGroup) \
        --template-file main.bicep \
        --parameters @parameters.json
```

### GitHub Actions Integration

```yaml
# .github/workflows/deploy.yml example
name: Deploy Infrastructure

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Deploy Bicep
      run: |
        cd bicep/
        az deployment group create \
          --resource-group ${{ secrets.RESOURCE_GROUP }} \
          --template-file main.bicep \
          --parameters @parameters.json
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../implementing-centralized-application-configuration-management-with-azure-app-configuration-and-azure-key-vault.md)
2. Review [Azure App Configuration documentation](https://docs.microsoft.com/en-us/azure/azure-app-configuration/)
3. Review [Azure Key Vault documentation](https://docs.microsoft.com/en-us/azure/key-vault/)
4. Check [Azure Web Apps documentation](https://docs.microsoft.com/en-us/azure/app-service/)

## License

This infrastructure code is provided as-is under the same license as the parent repository.