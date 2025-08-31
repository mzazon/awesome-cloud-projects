# Infrastructure as Code for Simple File Compression with Functions and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple File Compression with Functions and Storage".

## Recipe Overview

This solution creates a serverless file compression service using Azure Functions with Event Grid-based blob triggers that automatically compresses uploaded files and stores the compressed versions in Azure Blob Storage. The event-driven architecture eliminates infrastructure management while providing cost-effective scaling and instant processing of uploaded files.

## Architecture Components

- **Azure Storage Account**: Primary storage for both input (raw-files) and output (compressed-files) containers
- **Azure Function App**: Serverless compute running Python v2 programming model for file compression
- **Event Grid System Topic**: Provides reliable, low-latency event delivery for blob storage events
- **Event Grid Subscription**: Connects blob storage events to Azure Function for instant processing
- **Azure Resource Group**: Logical container for all related resources

## Available Implementations

- **Bicep**: Azure-native Infrastructure as Code using declarative syntax
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts for automated provisioning

## Prerequisites

### General Requirements

- Azure account with active subscription
- Appropriate permissions for resource creation:
  - Resource Group Contributor or higher
  - Storage Account Contributor
  - Azure Functions Contributor
  - EventGrid Contributor
- Azure CLI installed and configured (version 2.15.0 or later)
- Git (for cloning and version control)

### Tool-Specific Prerequisites

#### For Bicep Deployment
- Bicep CLI installed (`az bicep install`)
- Azure CLI with Bicep support (version 2.20.0 or later)
- Visual Studio Code with Bicep extension (recommended for development)

#### for Terraform Deployment  
- Terraform installed (version 1.0 or later)
- Azure CLI configured for authentication
- Terraform Azure provider (automatically downloaded during `terraform init`)

#### For Bash Script Deployment
- Bash shell (Linux, macOS, or Windows with WSL)
- Azure CLI configured with appropriate permissions
- Basic command-line tools: `openssl`, `zip`, `sleep`

### Cost Considerations

- **Estimated cost for testing**: $0.50-2.00 USD
- **Azure Functions**: Consumption plan charges per execution (first 1M executions free monthly)
- **Azure Storage**: Standard LRS pricing (first 5 GB free)
- **Event Grid**: First 100K operations free monthly
- **Bandwidth**: Minimal costs for intra-region transfers

## Quick Start

### Using Bicep

Bicep provides the most Azure-native experience with immediate support for new Azure features and excellent integration with Azure services.

```bash
# Navigate to Bicep directory
cd bicep/

# Validate the Bicep template
az deployment group validate \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters location=eastus

# Deploy the infrastructure
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters location=eastus \
                 storageAccountName=compress$(openssl rand -hex 3) \
                 functionAppName=file-compressor-$(openssl rand -hex 3)

# Monitor deployment progress
az deployment group show \
    --resource-group myResourceGroup \
    --name main
```

### Using Terraform

Terraform provides excellent state management and is ideal for multi-cloud scenarios or when you need to integrate with other cloud providers.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform and download providers
terraform init

# Review the planned changes
terraform plan \
    -var="location=East US" \
    -var="resource_group_name=rg-recipe-$(openssl rand -hex 3)"

# Apply the configuration
terraform apply \
    -var="location=East US" \
    -var="resource_group_name=rg-recipe-$(openssl rand -hex 3)"

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide the most direct approach, closely following the original recipe steps with enhanced automation and error handling.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Optionally specify custom parameters
LOCATION="West US 2" RESOURCE_PREFIX="mytest" ./scripts/deploy.sh
```

## Configuration Options

### Bicep Parameters

The Bicep template supports the following parameters for customization:

```bicep
param location string = resourceGroup().location
param storageAccountName string = 'compress${uniqueString(resourceGroup().id)}'
param functionAppName string = 'file-compressor-${uniqueString(resourceGroup().id)}'
param functionRuntime string = 'python'
param functionVersion string = '3.11'
param storageAccountTier string = 'Standard'
param storageReplication string = 'LRS'
```

### Terraform Variables

Configure deployment through `terraform.tfvars` file or command-line variables:

```hcl
location              = "East US"
resource_group_name   = "rg-file-compression"
storage_account_name  = "compressstorage"
function_app_name     = "file-compressor-app"
storage_tier          = "Standard"
storage_replication   = "LRS"
python_version        = "3.11"
```

### Script Environment Variables

Customize bash script deployment using environment variables:

```bash
export LOCATION="East US"
export RESOURCE_PREFIX="prod"
export STORAGE_TIER="Standard"
export STORAGE_REPLICATION="GRS"  # For production workloads
export FUNCTION_RUNTIME_VERSION="3.11"
```

## Testing and Validation

After deployment, validate the solution functionality:

### 1. Verify Resource Creation

```bash
# Check resource group contents
az resource list \
    --resource-group <your-resource-group> \
    --output table

# Verify storage containers
az storage container list \
    --account-name <storage-account-name> \
    --auth-mode login \
    --output table
```

### 2. Test File Compression

```bash
# Create a test file
echo "This is a test file for compression validation." > test-upload.txt

# Upload to trigger compression
az storage blob upload \
    --account-name <storage-account-name> \
    --container-name raw-files \
    --name test-upload.txt \
    --file test-upload.txt \
    --auth-mode login

# Wait for processing (20-30 seconds)
sleep 30

# Verify compressed file creation
az storage blob list \
    --account-name <storage-account-name> \
    --container-name compressed-files \
    --auth-mode login \
    --output table
```

### 3. Monitor Function Performance

```bash
# View function execution logs
az functionapp logs tail \
    --name <function-app-name> \
    --resource-group <resource-group-name>

# Check function app status
az functionapp show \
    --name <function-app-name> \
    --resource-group <resource-group-name> \
    --query "state"
```

## Advanced Configuration

### Production Optimizations

For production deployments, consider these enhancements:

#### Storage Optimization
```bash
# Configure lifecycle management for cost optimization
az storage account management-policy create \
    --account-name <storage-account-name> \
    --policy @lifecycle-policy.json
```

#### Monitoring and Alerting
```bash
# Enable Application Insights for detailed monitoring
az monitor app-insights component create \
    --app <function-app-name>-insights \
    --location <location> \
    --resource-group <resource-group-name>
```

#### Security Hardening
```bash
# Enable managed identity for secure access
az functionapp identity assign \
    --name <function-app-name> \
    --resource-group <resource-group-name>

# Configure storage account firewall rules
az storage account network-rule add \
    --account-name <storage-account-name> \
    --action Allow \
    --subnet <subnet-id>
```

### Multi-Environment Support

Deploy to multiple environments using parameter files:

```bash
# Development environment
az deployment group create \
    --resource-group rg-compression-dev \
    --template-file main.bicep \
    --parameters @parameters.dev.json

# Production environment  
az deployment group create \
    --resource-group rg-compression-prod \
    --template-file main.bicep \
    --parameters @parameters.prod.json
```

## Cleanup

### Using Bicep

```bash
# Delete the deployment (removes all resources created by the template)
az deployment group delete \
    --resource-group <resource-group-name> \
    --name main

# Optionally delete the entire resource group
az group delete \
    --name <resource-group-name> \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all managed resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Execute cleanup script
./scripts/destroy.sh

# Script will prompt for confirmation before deletion
```

### Manual Cleanup Verification

Verify complete resource removal:

```bash
# Confirm resource group deletion
az group exists --name <resource-group-name>

# Should return: false
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Function Deployment Failures

**Problem**: Function deployment fails during zip deployment
```bash
# Solution: Check function app logs
az functionapp logs tail --name <function-app-name> --resource-group <resource-group-name>

# Redeploy function code
az functionapp deployment source config-zip \
    --name <function-app-name> \
    --resource-group <resource-group-name> \
    --src function.zip
```

#### 2. Event Grid Subscription Issues

**Problem**: Function not triggered by blob uploads
```bash
# Solution: Verify Event Grid subscription
az eventgrid system-topic event-subscription show \
    --name blob-compression-subscription \
    --system-topic-name <storage-account>-topic \
    --resource-group <resource-group-name>

# Check function key configuration
az functionapp keys list \
    --name <function-app-name> \
    --resource-group <resource-group-name>
```

#### 3. Storage Access Permissions

**Problem**: Function cannot access storage containers
```bash
# Solution: Verify storage connection string
az functionapp config appsettings list \
    --name <function-app-name> \
    --resource-group <resource-group-name> \
    --query "[?name=='STORAGE_CONNECTION_STRING']"

# Update if necessary
az functionapp config appsettings set \
    --name <function-app-name> \
    --resource-group <resource-group-name> \
    --settings "STORAGE_CONNECTION_STRING=<connection-string>"
```

### Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
# Enable verbose logging for Azure CLI
export AZURE_CLI_DIAGNOSTICS_VERBOSITY=debug

# Enable function app debug logging
az functionapp config appsettings set \
    --name <function-app-name> \
    --resource-group <resource-group-name> \
    --settings "FUNCTIONS_WORKER_RUNTIME_VERSION=~4" \
             "SCM_DO_BUILD_DURING_DEPLOYMENT=true" \
             "ENABLE_ORYX_BUILD=true"
```

## Performance Considerations

### Scaling Configuration

For high-volume scenarios, consider these optimizations:

```bash
# Configure function app scaling settings
az functionapp config set \
    --name <function-app-name> \
    --resource-group <resource-group-name> \
    --generic-configurations '{"functionAppScaleLimit": 200, "minimumElasticInstanceCount": 1}'

# Configure storage account for high-throughput
az storage account update \
    --name <storage-account-name> \
    --resource-group <resource-group-name> \
    --access-tier Hot \
    --https-only true
```

### Cost Optimization

Monitor and optimize costs:

```bash
# Set up cost alerts
az consumption budget create \
    --budget-name compression-budget \
    --amount 50 \
    --resource-group <resource-group-name> \
    --time-grain Monthly \
    --time-period startDate=2025-01-01

# Configure storage lifecycle policies for automatic tiering
az storage account management-policy create \
    --account-name <storage-account-name> \
    --policy @storage-lifecycle.json
```

## Support and Additional Resources

### Documentation Links

- [Azure Functions Infrastructure as Code](https://learn.microsoft.com/en-us/azure/azure-functions/functions-infrastructure-as-code)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Storage Event Grid Integration](https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blob-event-overview)
- [Azure Functions Python Programming Model](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-python)

### Community and Support

- [Azure Functions GitHub Repository](https://github.com/Azure/azure-functions-host)
- [Bicep Community](https://github.com/Azure/bicep)
- [Terraform Azure Provider Issues](https://github.com/hashicorp/terraform-provider-azurerm/issues)
- [Microsoft Q&A - Azure Functions](https://docs.microsoft.com/en-us/answers/topics/azure-functions.html)

### Best Practices

For production deployments, follow these Azure Well-Architected Framework principles:

1. **Reliability**: Use multiple regions and availability zones for critical deployments
2. **Security**: Implement managed identities, network restrictions, and encryption
3. **Cost Optimization**: Use appropriate storage tiers and function scaling limits
4. **Operational Excellence**: Implement monitoring, logging, and automated deployment pipelines
5. **Performance Efficiency**: Configure appropriate function memory allocation and storage performance tiers

For issues with this infrastructure code, refer to the original recipe documentation or consult the Azure documentation links provided above.