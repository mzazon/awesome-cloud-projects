# Infrastructure as Code for File Upload Processing with Functions and Blob Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "File Upload Processing with Functions and Blob Storage". This serverless solution automatically processes files uploaded to Azure Blob Storage using Azure Functions with event-driven triggers.

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.4 or later)
- Active Azure subscription with appropriate permissions
- For Terraform: Terraform CLI installed (version 1.0 or later)
- Text editor for customizing variables (optional)
- Estimated cost: $0.10-$2.00 USD for resources created

### Required Azure Permissions

- Contributor role on subscription or resource group
- Permission to create:
  - Resource Groups
  - Storage Accounts
  - Function Apps
  - Application Insights (created automatically with Function Apps)

## Quick Start

### Using Bicep (Recommended)

Bicep is Microsoft's domain-specific language for deploying Azure resources and is the recommended approach for Azure infrastructure.

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-file-processing-demo" \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters environmentSuffix=$(openssl rand -hex 3)

# Monitor deployment status
az deployment group show \
    --resource-group "rg-file-processing-demo" \
    --name main \
    --query "properties.provisioningState" \
    --output tsv
```

### Using Terraform

Terraform provides a consistent workflow across multiple cloud providers and offers advanced state management capabilities.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="location=eastus" \
    -var="environment_suffix=$(openssl rand -hex 3)"

# Apply the configuration
terraform apply \
    -var="location=eastus" \
    -var="environment_suffix=$(openssl rand -hex 3)"

# View outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide a simple deployment method that closely follows the original recipe steps with automation enhancements.

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy the infrastructure
./deploy.sh

# Follow prompts for customization options
```

## Configuration Options

### Bicep Parameters

Customize your deployment by modifying parameters in the Bicep template:

- `location`: Azure region for resource deployment (default: eastus)
- `environmentSuffix`: Unique suffix for resource names (auto-generated if not provided)
- `storageAccountSku`: Storage account SKU (default: Standard_LRS)
- `functionAppPlan`: Function App hosting plan (default: Y1 Consumption)

Example with custom parameters:

```bash
az deployment group create \
    --resource-group "rg-file-processing-prod" \
    --template-file main.bicep \
    --parameters location=westus2 \
    --parameters environmentSuffix=prod001 \
    --parameters storageAccountSku=Standard_GRS
```

### Terraform Variables

Customize your deployment using variables in `terraform.tfvars`:

```hcl
# terraform.tfvars
location = "westus2"
environment_suffix = "prod001"
resource_group_name = "rg-file-processing-prod"
storage_account_sku = "Standard_GRS"
function_app_sku = "Y1"

# Optional: Add custom tags
tags = {
  Environment = "Production"
  Owner       = "Platform Team"
  CostCenter  = "Engineering"
}
```

### Bash Script Configuration

The bash scripts support environment variables for customization:

```bash
# Set custom configuration before running deploy.sh
export LOCATION="westus2"
export ENVIRONMENT_SUFFIX="prod001"
export RESOURCE_GROUP_NAME="rg-file-processing-prod"
export STORAGE_ACCOUNT_SKU="Standard_GRS"

# Run deployment with custom settings
./scripts/deploy.sh
```

## Deployment Validation

### Verify Infrastructure Deployment

After deployment, validate that all resources are created and configured correctly:

```bash
# Check resource group contents
az resource list \
    --resource-group "rg-file-processing-demo" \
    --output table

# Verify function app status
az functionapp show \
    --name "func-file-processing-<suffix>" \
    --resource-group "rg-file-processing-demo" \
    --query "state" \
    --output tsv

# Check storage account accessibility
az storage account show \
    --name "stfileproc<suffix>" \
    --resource-group "rg-file-processing-demo" \
    --query "provisioningState" \
    --output tsv
```

### Test File Processing

Test the deployed solution by uploading files to trigger function execution:

```bash
# Get storage connection string
STORAGE_CONNECTION=$(az storage account show-connection-string \
    --name "stfileproc<suffix>" \
    --resource-group "rg-file-processing-demo" \
    --query connectionString \
    --output tsv)

# Create and upload test files
echo "Test document content" > test-document.txt
echo "Test image simulation" > test-image.jpg

# Upload files to trigger processing
az storage blob upload \
    --file test-document.txt \
    --name "test-document-$(date +%s).txt" \
    --container-name uploads \
    --connection-string "${STORAGE_CONNECTION}"

az storage blob upload \
    --file test-image.jpg \
    --name "test-image-$(date +%s).jpg" \
    --container-name uploads \
    --connection-string "${STORAGE_CONNECTION}"

# Monitor function logs
az webapp log tail \
    --name "func-file-processing-<suffix>" \
    --resource-group "rg-file-processing-demo"
```

## Monitoring and Troubleshooting

### Application Insights Integration

All implementations automatically configure Application Insights for comprehensive monitoring:

```bash
# View Application Insights data
az monitor app-insights component show \
    --app "func-file-processing-<suffix>" \
    --resource-group "rg-file-processing-demo"

# Query recent function executions
az monitor app-insights query \
    --app "func-file-processing-<suffix>" \
    --analytics-query "requests | limit 10" \
    --resource-group "rg-file-processing-demo"
```

### Common Issues and Solutions

**Function Not Triggering**: Verify storage connection string configuration and blob container permissions.

**Deployment Failures**: Check Azure subscription limits and ensure sufficient permissions for resource creation.

**Cost Concerns**: Monitor resource usage through Azure Cost Management and consider scaling down for development environments.

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all contained resources
az group delete \
    --name "rg-file-processing-demo" \
    --yes \
    --no-wait

# Verify deletion status
az group exists --name "rg-file-processing-demo"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all managed resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Follow confirmation prompts
```

## Security Considerations

### Implemented Security Features

- **Storage Account Security**: Private blob container access with connection string authentication
- **Function App Security**: Managed identity integration and secure application settings
- **Network Security**: HTTPS-only communication enforced for all endpoints
- **Access Control**: Least privilege IAM configurations using built-in Azure roles

### Additional Security Recommendations

For production deployments, consider implementing:

- **Virtual Network Integration**: Deploy Function Apps in dedicated subnets
- **Private Endpoints**: Use private endpoints for storage account access
- **Key Vault Integration**: Store connection strings and secrets in Azure Key Vault
- **Monitoring and Alerting**: Configure security alerts for suspicious activities

```bash
# Example: Enable HTTPS-only after deployment
az functionapp update \
    --name "func-file-processing-<suffix>" \
    --resource-group "rg-file-processing-demo" \
    --set httpsOnly=true
```

## Cost Optimization

### Consumption Plan Benefits

The implementation uses Azure Functions Consumption Plan for optimal cost efficiency:

- **Pay-per-execution**: Charges only for actual function runtime
- **Automatic scaling**: Scales to zero during idle periods
- **Free tier**: 1 million executions and 400,000 GB-seconds monthly
- **No upfront costs**: No reserved capacity requirements

### Cost Monitoring

```bash
# Monitor resource costs
az consumption usage list \
    --billing-period-name $(az billing period list --query "[0].name" -o tsv) \
    --resource-group "rg-file-processing-demo"

# Set up cost alerts (requires additional configuration)
az monitor action-group create \
    --name "cost-alert-group" \
    --resource-group "rg-file-processing-demo" \
    --short-name "CostAlert"
```

## Customization and Extensions

### Adding Custom Processing Logic

Modify the function code to implement specific file processing requirements:

1. **Image Processing**: Integrate with Azure Computer Vision for image analysis
2. **Document Processing**: Use Azure Form Recognizer for document data extraction
3. **Data Pipeline**: Connect to Azure Data Factory for complex ETL workflows
4. **Notifications**: Add Service Bus or Event Grid integration for downstream processing

### Scaling Considerations

For high-volume scenarios, consider:

- **Premium Plan**: Provides pre-warmed instances and VNet integration
- **Dedicated Plan**: Offers predictable costs and advanced scaling options
- **Durable Functions**: Implements stateful functions for complex workflows

## Support and Documentation

### Additional Resources

- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Blob Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/blobs/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

### Getting Help

For issues with this infrastructure code:

1. Review the original recipe documentation for implementation details
2. Check Azure service health and regional availability
3. Consult provider documentation for resource-specific troubleshooting
4. Use Azure Support for subscription and service-level issues

### Contributing

To improve this infrastructure code:

1. Test changes thoroughly in development environments
2. Follow Azure naming conventions and best practices
3. Update documentation for any configuration changes
4. Validate security implications of modifications