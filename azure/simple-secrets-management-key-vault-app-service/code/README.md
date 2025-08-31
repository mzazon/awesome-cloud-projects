# Infrastructure as Code for Simple Secrets Management with Key Vault and App Service

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Secrets Management with Key Vault and App Service".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az --version` should show 2.50.0 or later)
- Azure subscription with permissions to create:
  - Resource Groups
  - Key Vault instances
  - App Service Plans and Web Apps
  - Role assignments (Key Vault RBAC)
- For Bicep: Azure CLI with Bicep extension (`az bicep install`)
- For Terraform: Terraform installed (version 1.5.0 or later)
- Basic understanding of Azure managed identities and Key Vault concepts

## Architecture Overview

This infrastructure creates:
- Azure Key Vault with RBAC authorization
- App Service Plan (Basic tier)
- Web App with Node.js runtime
- System-assigned managed identity for the web app
- RBAC role assignments for Key Vault access
- Sample secrets and Key Vault references

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Create resource group
az group create \
    --name rg-secrets-demo \
    --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-secrets-demo \
    --template-file main.bicep \
    --parameters webAppName=webapp-secrets-demo \
                keyVaultName=kv-secrets-demo

# The deployment will output the web app URL
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure changes
terraform apply

# View outputs including web app URL
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output the web app URL when complete
```

## Configuration Options

### Bicep Parameters

Customize the deployment by providing parameters:

```bash
az deployment group create \
    --resource-group rg-secrets-demo \
    --template-file bicep/main.bicep \
    --parameters \
        webAppName=my-secure-app \
        keyVaultName=my-key-vault \
        location=westus2 \
        appServicePlanSku=B1 \
        nodeVersion=18-lts
```

### Terraform Variables

Create a `terraform.tfvars` file or set variables:

```hcl
# terraform.tfvars
resource_group_name = "rg-secrets-demo"
location           = "East US"
web_app_name       = "my-secure-app"
key_vault_name     = "my-key-vault"
app_service_sku    = "B1"
node_version       = "18-lts"
```

Or use command line:

```bash
terraform apply \
    -var="web_app_name=my-secure-app" \
    -var="key_vault_name=my-key-vault"
```

### Script Environment Variables

Set environment variables before running bash scripts:

```bash
export RESOURCE_GROUP="rg-secrets-demo"
export LOCATION="eastus"
export WEB_APP_NAME="my-secure-app"
export KEY_VAULT_NAME="my-key-vault"

./scripts/deploy.sh
```

## Post-Deployment Verification

After deployment, verify the solution:

1. **Check Key Vault Secrets**:
   ```bash
   az keyvault secret list --vault-name <key-vault-name> --output table
   ```

2. **Verify Managed Identity**:
   ```bash
   az webapp identity show --name <web-app-name> --resource-group <resource-group>
   ```

3. **Test Web Application**:
   - Navigate to the web app URL (provided in deployment outputs)
   - Verify that secrets are displayed as "Retrieved from Key Vault"

4. **Check Role Assignments**:
   ```bash
   az role assignment list --scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.KeyVault/vaults/<key-vault-name>"
   ```

## Security Considerations

This implementation follows Azure security best practices:

- **Managed Identity**: Eliminates need for stored credentials
- **RBAC Authorization**: Uses Azure RBAC instead of access policies
- **Least Privilege**: Web app gets minimal Key Vault permissions (Secrets User)
- **Key Vault References**: Secrets retrieved at runtime, not stored in app settings
- **Audit Logging**: Key Vault access is automatically logged

## Troubleshooting

### Common Issues

1. **Role Assignment Propagation**:
   - Wait 30-60 seconds after role assignment before testing
   - Check role assignments with `az role assignment list`

2. **Key Vault Access Denied**:
   - Verify RBAC is enabled on Key Vault
   - Confirm managed identity has correct role assignment
   - Check that you have "Key Vault Secrets Officer" role for secret management

3. **Web App Not Starting**:
   - Check App Service logs: `az webapp log tail --name <web-app-name> --resource-group <resource-group>`
   - Verify Node.js runtime is correctly configured

4. **Key Vault References Not Resolving**:
   - Ensure Key Vault reference syntax is correct in app settings
   - Verify managed identity is enabled and assigned

### Diagnostic Commands

```bash
# Check deployment status (Bicep/ARM)
az deployment group show --name <deployment-name> --resource-group <resource-group>

# View web app configuration
az webapp config appsettings list --name <web-app-name> --resource-group <resource-group>

# Check Key Vault diagnostic logs
az monitor diagnostic-settings list --resource "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv-name>"
```

## Cleanup

### Using Bicep
```bash
# Delete resource group and all resources
az group delete --name rg-secrets-demo --yes --no-wait
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

Expected monthly costs (East US region):
- **Key Vault**: ~$0.03 per 10,000 operations (minimal for demo)
- **App Service Plan B1**: ~$56/month
- **Total**: Approximately $56-60/month

Cost reduction strategies:
- Use **Free tier** App Service Plan for development (limited capabilities)
- Delete resources when not in use
- Consider **Consumption plan** for Azure Functions alternative

## Customization Examples

### Adding Additional Secrets

1. **Via Bicep**: Add to the `secrets` array in parameters
2. **Via Terraform**: Extend the `secrets` variable
3. **Via Scripts**: Add additional `az keyvault secret set` commands

### Configuring Custom Domain

Add custom domain configuration to your IaC:

```bash
# After deployment, configure custom domain
az webapp config hostname add \
    --webapp-name <web-app-name> \
    --resource-group <resource-group> \
    --hostname yourdomain.com
```

### Enabling Application Insights

Extend the infrastructure to include monitoring:

```bash
# Create Application Insights instance
az monitor app-insights component create \
    --app <web-app-name>-insights \
    --location <location> \
    --resource-group <resource-group> \
    --application-type web
```

## Integration with CI/CD

### Azure DevOps Pipeline

```yaml
trigger:
  branches:
    include:
    - main

pool:
  vmImage: 'ubuntu-latest'

variables:
  azureServiceConnection: 'your-service-connection'
  resourceGroupName: 'rg-secrets-demo'

stages:
- stage: Deploy
  jobs:
  - job: DeployInfrastructure
    steps:
    - task: AzureCLI@2
      inputs:
        azureSubscription: $(azureServiceConnection)
        scriptType: bash
        scriptLocation: inlineScript
        inlineScript: |
          az deployment group create \
            --resource-group $(resourceGroupName) \
            --template-file bicep/main.bicep \
            --parameters webAppName=webapp-$(Build.BuildId)
```

### GitHub Actions

```yaml
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
        az deployment group create \
          --resource-group rg-secrets-demo \
          --template-file bicep/main.bicep \
          --parameters webAppName=webapp-${{ github.run_id }}
```

## Advanced Configuration

### Multi-Environment Setup

Structure your infrastructure for multiple environments:

```bash
# Development environment
az deployment group create \
    --resource-group rg-secrets-dev \
    --template-file bicep/main.bicep \
    --parameters @parameters/dev.json

# Production environment  
az deployment group create \
    --resource-group rg-secrets-prod \
    --template-file bicep/main.bicep \
    --parameters @parameters/prod.json
```

### Backup and Disaster Recovery

Configure Key Vault backup:

```bash
# Enable Key Vault logging
az monitor diagnostic-settings create \
    --name KeyVaultDiagnostics \
    --resource "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv-name>" \
    --logs '[{"category":"AuditEvent","enabled":true}]' \
    --workspace "<log-analytics-workspace-id>"
```

## Support and Documentation

- **Azure Key Vault**: [Official Documentation](https://docs.microsoft.com/en-us/azure/key-vault/)
- **Azure App Service**: [Official Documentation](https://docs.microsoft.com/en-us/azure/app-service/)
- **Managed Identities**: [Official Documentation](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)
- **Bicep**: [Language Reference](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- **Terraform Azure Provider**: [Registry Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest)

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.