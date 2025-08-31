# Simple Password Generator - Bicep Infrastructure as Code

This directory contains Azure Bicep templates to deploy a serverless password generator solution using Azure Functions and Azure Key Vault.

## Architecture Overview

The solution deploys the following Azure resources:

- **Azure Functions**: Serverless compute platform hosting the password generator API
- **Azure Key Vault**: Secure storage for generated passwords with RBAC access control
- **Storage Account**: Required for Azure Functions runtime and execution logs
- **Application Insights**: Application performance monitoring and logging
- **Log Analytics Workspace**: Centralized logging and monitoring data storage
- **App Service Plan**: Consumption-based hosting plan for cost-effective serverless execution

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Azure CLI** installed and configured (version 2.50.0 or later)
   ```bash
   az --version
   az login
   ```

2. **Azure subscription** with appropriate permissions:
   - Contributor role on the target resource group
   - User Access Administrator role (for RBAC assignments)

3. **Resource Group** created for deployment:
   ```bash
   az group create --name rg-password-generator --location "East US"
   ```

4. **Bicep CLI** installed (comes with Azure CLI 2.20.0+):
   ```bash
   az bicep version
   ```

## Quick Start

### 1. Clone and Navigate

```bash
# Navigate to the bicep directory
cd azure/simple-password-generator-functions-key-vault/code/bicep/
```

### 2. Review Parameters

Edit `parameters.json` to customize your deployment:

```json
{
  "location": "East US",           # Azure region for deployment
  "environment": "dev",            # Environment designation (dev/test/staging/prod)
  "uniqueSuffix": "abc123",        # Custom suffix for globally unique names
  "functionAppNodeVersion": "20",  # Node.js runtime version (18 or 20)
  "enableKeyVaultSoftDelete": true # Enable soft delete protection
}
```

### 3. Deploy Infrastructure

```bash
# Deploy using Azure CLI with parameter file
az deployment group create \
  --resource-group rg-password-generator \
  --template-file main.bicep \
  --parameters @parameters.json

# Alternative: Deploy with inline parameters
az deployment group create \
  --resource-group rg-password-generator \
  --template-file main.bicep \
  --parameters location="East US" environment="dev"
```

### 4. Verify Deployment

```bash
# Check deployment status
az deployment group list \
  --resource-group rg-password-generator \
  --output table

# List deployed resources
az resource list \
  --resource-group rg-password-generator \
  --output table
```

## Configuration Options

### Environment Settings

The template supports multiple environment configurations:

| Environment | Description | Recommended Settings |
|-------------|-------------|---------------------|
| `dev` | Development environment | Soft delete enabled, purge protection disabled |
| `test` | Testing environment | Soft delete enabled, purge protection disabled |
| `staging` | Pre-production environment | Soft delete enabled, purge protection enabled |
| `prod` | Production environment | Soft delete enabled, purge protection enabled |

### Key Vault Configuration

| Parameter | Description | Default | Production Recommendation |
|-----------|-------------|---------|--------------------------|
| `enableKeyVaultSoftDelete` | Enable soft delete protection | `true` | `true` |
| `keyVaultRetentionDays` | Soft delete retention period | `7` | `90` |
| `enableKeyVaultPurgeProtection` | Enable purge protection | `false` | `true` |

### Function App Configuration

| Parameter | Description | Options | Recommendation |
|-----------|-------------|---------|----------------|
| `functionAppNodeVersion` | Node.js runtime version | `18`, `20` | `20` (latest LTS) |

## Security Features

### Managed Identity

The Function App uses **system-assigned managed identity** for secure authentication:
- No connection strings or access keys required
- Automatic credential lifecycle management
- Azure AD-based authentication

### RBAC Integration

The template automatically grants the Function App:
- **Key Vault Secrets Officer** role on the Key Vault
- Permissions to create, read, and manage secrets
- Least privilege access model

### Network Security

- **HTTPS only** enforcement on Function App
- **TLS 1.2 minimum** for all connections
- **FTPS only** for deployment scenarios
- **Blob public access disabled** on storage account

## Monitoring and Observability

### Application Insights

Automatically configured for comprehensive monitoring:
- Function execution metrics and logs
- Performance counters and dependency tracking
- Custom telemetry and alerts capability

### Log Analytics Integration

Centralized logging with:
- 30-day retention for cost optimization
- 1GB daily quota for development environments
- Integration with Azure Monitor and alerts

## Cost Optimization

The template includes several cost optimization features:

### Consumption-Based Pricing
- **Pay-per-execution** model for Azure Functions
- **No idle costs** when functions are not running
- **Automatic scaling** from zero to meet demand

### Storage Optimization
- **Standard LRS** storage for cost efficiency
- **Hot access tier** for frequent Function App operations
- **Lifecycle management** ready for long-term cost control

### Monitoring Costs
- **1GB daily quota** on Log Analytics to control costs
- **30-day retention** for development environments
- **Per-GB pricing** model for predictable costs

## Deployment Validation

After deployment, validate the infrastructure:

### 1. Check Function App Status

```bash
# Get Function App details
FUNCTION_APP_NAME=$(az deployment group show \
  --resource-group rg-password-generator \
  --name main \
  --query 'properties.outputs.functionAppName.value' \
  --output tsv)

# Check Function App status
az functionapp show \
  --name $FUNCTION_APP_NAME \
  --resource-group rg-password-generator \
  --query '{name:name, state:state, hostNames:hostNames}'
```

### 2. Verify Key Vault Access

```bash
# Get Key Vault name
KEY_VAULT_NAME=$(az deployment group show \
  --resource-group rg-password-generator \
  --name main \
  --query 'properties.outputs.keyVaultName.value' \
  --output tsv)

# Check RBAC assignments
az role assignment list \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-password-generator/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME" \
  --output table
```

### 3. Test Application Insights

```bash
# Get Application Insights details
AI_NAME=$(az deployment group show \
  --resource-group rg-password-generator \
  --name main \
  --query 'properties.outputs.applicationInsightsName.value' \
  --output tsv)

# Check Application Insights configuration
az monitor app-insights component show \
  --app $AI_NAME \
  --resource-group rg-password-generator \
  --query '{name:name, instrumentationKey:instrumentationKey}'
```

## Troubleshooting

### Common Issues

1. **Deployment Fails - Name Already Exists**
   - Update the `uniqueSuffix` parameter with a different value
   - Ensure global uniqueness for storage account and Key Vault names

2. **RBAC Assignment Fails**
   - Verify you have User Access Administrator role
   - Check that managed identity is enabled on Function App

3. **Key Vault Access Denied**
   - Confirm RBAC role assignment completed successfully
   - Verify managed identity is properly configured

### Validation Commands

```bash
# Check deployment outputs
az deployment group show \
  --resource-group rg-password-generator \
  --name main \
  --query 'properties.outputs'

# Validate resource creation
az resource list \
  --resource-group rg-password-generator \
  --query '[].{Name:name, Type:type, Location:location}' \
  --output table
```

## Cleanup

To remove all resources and avoid ongoing costs:

```bash
# Delete the entire resource group (removes all resources)
az group delete \
  --name rg-password-generator \
  --yes \
  --no-wait

# Verify deletion
az group exists --name rg-password-generator
```

## Best Practices

### Production Deployment

For production environments, consider these additional configurations:

1. **Enhanced Security**:
   - Enable purge protection on Key Vault
   - Implement private endpoints for network isolation
   - Configure custom domains with SSL certificates

2. **Monitoring & Alerting**:
   - Set up Azure Monitor alerts for failures and performance
   - Configure log retention based on compliance requirements
   - Implement health checks and availability monitoring

3. **Governance**:
   - Apply Azure Policy for compliance enforcement
   - Implement proper tagging strategy for cost allocation
   - Set up budget alerts and cost management

### Maintenance

- Regular updates to Function App runtime versions
- Monitor Key Vault access patterns and audit logs
- Review and rotate any additional secrets or keys
- Update Bicep templates as Azure services evolve

## Support and Documentation

- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure Functions Best Practices](https://docs.microsoft.com/en-us/azure/azure-functions/functions-best-practices)
- [Azure Key Vault Security Guide](https://docs.microsoft.com/en-us/azure/key-vault/general/security-features)
- [Managed Identity Documentation](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)

For issues specific to this template, refer to the original recipe documentation or Azure support channels.