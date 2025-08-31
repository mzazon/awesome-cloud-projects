# Infrastructure as Code for Simple QR Code Generator with Functions and Blob Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple QR Code Generator with Functions and Blob Storage".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.60.0 or later)
- Active Azure subscription with appropriate permissions for:
  - Creating resource groups
  - Creating storage accounts and blob containers
  - Creating and configuring Function Apps
  - Managing application settings and deployments
- For Terraform: Terraform CLI installed (version 1.0 or later)
- Basic understanding of serverless computing and HTTP APIs

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure using Bicep
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
                 appNamePrefix=qrgen \
                 storageAccountSku=Standard_LRS

# Deploy the function code (after infrastructure is ready)
cd ../function-code
zip -r ../code/qr-function.zip . 
az functionapp deployment source config-zip \
    --resource-group <your-resource-group> \
    --name <function-app-name> \
    --src qr-function.zip \
    --build-remote true
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan -var="location=eastus" -var="app_name_prefix=qrgen"

# Deploy the infrastructure
terraform apply -var="location=eastus" -var="app_name_prefix=qrgen"

# Deploy the function code using Azure CLI
cd ../function-code
zip -r ../terraform/qr-function.zip .
az functionapp deployment source config-zip \
    --resource-group $(terraform output -raw resource_group_name) \
    --name $(terraform output -raw function_app_name) \
    --src qr-function.zip \
    --build-remote true
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy with default settings
./scripts/deploy.sh

# Or deploy with custom parameters
./scripts/deploy.sh --location westus2 --prefix myqr
```

## Architecture Overview

This infrastructure deploys:

- **Azure Resource Group**: Container for all resources
- **Azure Storage Account**: Stores generated QR code images
- **Blob Container**: Organizes QR code files with public read access
- **Azure Function App**: Serverless HTTP-triggered function
- **Application Settings**: Secure configuration for storage connection

The solution uses consumption-based pricing, ensuring cost efficiency for variable workloads.

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | No |
| `appNamePrefix` | Prefix for resource names | `qrgen` | No |
| `storageAccountSku` | Storage account performance tier | `Standard_LRS` | No |
| `functionAppRuntime` | Function runtime version | `python` | No |
| `functionAppVersion` | Functions runtime version | `~4` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | No |
| `app_name_prefix` | Prefix for resource names | `qrgen` | No |
| `storage_account_sku` | Storage account performance tier | `Standard_LRS` | No |
| `resource_group_name` | Custom resource group name | Auto-generated | No |

### Script Options

| Option | Description | Default |
|--------|-------------|---------|
| `--location` | Azure region | `eastus` |
| `--prefix` | Resource name prefix | `qrgen` |
| `--resource-group` | Custom resource group name | Auto-generated |

## Testing the Deployment

After successful deployment, test the QR code generator:

```bash
# Get the function URL (replace with your function app name)
FUNCTION_URL="https://<your-function-app>.azurewebsites.net"

# Test QR code generation
curl -X POST "${FUNCTION_URL}/api/generate-qr" \
    -H "Content-Type: application/json" \
    -d '{"text": "Hello from Infrastructure as Code!"}' \
    | jq '.'

# Expected response includes:
# - success: true
# - filename: qr_code_<timestamp>.png
# - url: <blob-storage-url>
# - text: "Hello from Infrastructure as Code!"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all contained resources
az group delete --name <your-resource-group> --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="location=eastus" -var="app_name_prefix=qrgen"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Or specify custom resource group
./scripts/destroy.sh --resource-group <your-resource-group>
```

## Customization

### Adding Custom Function Settings

Modify the `appSettings` in Bicep or `app_settings` in Terraform to include additional configuration:

```bicep
// In Bicep main.bicep
appSettings: [
  {
    name: 'STORAGE_CONNECTION_STRING'
    value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=storage-connection)'
  }
  {
    name: 'QR_ERROR_CORRECTION'
    value: 'L'
  }
  {
    name: 'QR_BOX_SIZE'
    value: '10'
  }
]
```

### Enabling Advanced Features

1. **Add Application Insights**: Uncomment monitoring sections in templates
2. **Enable Authentication**: Add Azure AD authentication configuration
3. **Custom Domain**: Configure custom domain for the Function App
4. **Key Vault Integration**: Store sensitive settings in Azure Key Vault
5. **Managed Identity**: Enable system-assigned managed identity for secure access

### Storage Configuration

Modify storage settings for different use cases:

```bicep
// For higher performance requirements
storageAccountSku: 'Standard_ZRS'

// For geo-redundancy
storageAccountSku: 'Standard_GRS'

// For premium performance
storageAccountSku: 'Premium_LRS'
```

## Monitoring and Observability

The deployment includes Application Insights integration (when enabled) for:

- Function execution monitoring
- Performance metrics
- Error tracking and alerting
- Usage analytics

Access monitoring through:
- Azure Portal → Function App → Monitoring
- Application Insights dashboard
- Azure Monitor workbooks

## Security Considerations

This implementation follows Azure security best practices:

- **Least Privilege**: Function App uses managed identity when possible
- **Network Security**: Storage account allows public blob access only for generated QR codes
- **Data Encryption**: All data encrypted at rest and in transit
- **Access Control**: Function uses anonymous auth level for demo purposes (customize for production)

For production deployments, consider:
- Enabling Azure AD authentication
- Implementing API Management for additional security layers
- Using private endpoints for storage account access
- Enabling Azure Security Center recommendations

## Cost Optimization

- **Consumption Plan**: Pay only for function executions
- **Storage Tiers**: Automatically tier old QR codes to cool storage
- **Monitoring**: Set up budget alerts to track usage
- **Lifecycle Policies**: Implement blob lifecycle management for cost control

Estimated monthly costs for light usage (100 executions/month):
- Function App: $0.00 (free tier)
- Storage Account: $0.05-0.10
- Bandwidth: $0.01-0.05

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   ```bash
   # Check function app status
   az functionapp show --name <function-app> --resource-group <rg> --query "state"
   
   # View deployment logs
   az functionapp log deployment show --name <function-app> --resource-group <rg>
   ```

2. **Storage connection issues**:
   ```bash
   # Verify storage account connection string
   az storage account show-connection-string --name <storage-account> --resource-group <rg>
   
   # Test blob container access
   az storage blob list --container-name qr-codes --account-name <storage-account>
   ```

3. **Function runtime errors**:
   ```bash
   # Stream function logs
   az functionapp log tail --name <function-app> --resource-group <rg>
   ```

### Support Resources

- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Blob Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/blobs/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate against Azure best practices
3. Update documentation for any new parameters
4. Ensure backward compatibility when possible

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.