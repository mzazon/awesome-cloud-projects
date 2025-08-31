# Infrastructure as Code for Simple URL Shortener with Functions and Table Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple URL Shortener with Functions and Table Storage".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts with Azure CLI

## Prerequisites

- Azure CLI installed and configured (version 2.60.0 or later)
- Active Azure subscription with permissions to create:
  - Resource Groups
  - Storage Accounts
  - Function Apps
  - Application Insights resources
- Node.js 18+ for Function App development
- Appropriate Azure RBAC permissions:
  - Contributor role on subscription or resource group
  - Storage Account Contributor for Table Storage operations

## Quick Start

### Using Bicep (Recommended)

Bicep is Microsoft's domain-specific language (DSL) for deploying Azure resources and is the recommended approach for Azure infrastructure.

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-url-shortener" \
    --template-file main.bicep \
    --parameters location="eastus" \
    --parameters appNamePrefix="urlshort$(openssl rand -hex 3)"

# Get deployment outputs
az deployment group show \
    --resource-group "rg-url-shortener" \
    --name "main" \
    --query properties.outputs
```

### Using Terraform

Terraform provides a consistent workflow across multiple cloud providers and enables infrastructure versioning.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Direct Azure CLI deployment scripts provide maximum control and transparency over resource creation.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Architecture Overview

This infrastructure deploys:

- **Azure Function App**: Serverless compute hosting URL shortening and redirect functions
- **Azure Storage Account**: Provides both Function App storage and Table Storage for URL mappings
- **Azure Table Storage**: NoSQL storage for URL mappings with partition/row key optimization
- **Application Insights**: Monitoring and telemetry for Function App performance
- **Consumption Plan**: Pay-per-execution hosting plan for optimal cost efficiency

## Configuration Options

### Bicep Parameters

```bash
# Deploy with custom parameters
az deployment group create \
    --resource-group "rg-url-shortener" \
    --template-file bicep/main.bicep \
    --parameters location="westus2" \
    --parameters appNamePrefix="myurlshort" \
    --parameters storageAccountSku="Standard_GRS" \
    --parameters functionAppRuntime="node" \
    --parameters functionAppRuntimeVersion="20"
```

### Terraform Variables

Create a `terraform.tfvars` file in the terraform directory:

```hcl
# terraform.tfvars example
location = "westus2"
resource_group_name = "rg-url-shortener-prod"
app_name_prefix = "production-urlshort"
storage_account_replication = "GRS"
environment = "production"

tags = {
  Environment = "production"
  Project     = "url-shortener"
  Owner       = "platform-team"
}
```

### Bash Script Environment Variables

```bash
# Set custom configuration before running deploy.sh
export LOCATION="westus2"
export RESOURCE_GROUP="rg-url-shortener-prod"
export APP_NAME_PREFIX="prod-urlshort"
export STORAGE_SKU="Standard_GRS"
export ENVIRONMENT="production"

./scripts/deploy.sh
```

## Deployment Validation

After deployment, validate the infrastructure:

### Function App Endpoints

```bash
# Get Function App URL
FUNCTION_URL=$(az functionapp show \
    --resource-group "rg-url-shortener" \
    --name "your-function-app-name" \
    --query defaultHostName \
    --output tsv)

# Test shorten endpoint
curl -X POST "https://${FUNCTION_URL}/api/shorten" \
    -H "Content-Type: application/json" \
    -d '{"url": "https://learn.microsoft.com/azure/"}'

# Test redirect (replace 'abc123' with actual short code)
curl -I "https://${FUNCTION_URL}/api/abc123"
```

### Storage Account Verification

```bash
# Verify Table Storage
az storage table list \
    --account-name "your-storage-account" \
    --query "[].name" \
    --output table

# Check table entities
az storage entity query \
    --table-name "urlmappings" \
    --account-name "your-storage-account"
```

### Application Insights

```bash
# Get Application Insights details
az monitor app-insights component show \
    --resource-group "rg-url-shortener" \
    --app "your-function-app-name" \
    --query "{Name:name,InstrumentationKey:instrumentationKey,ConnectionString:connectionString}"
```

## Monitoring and Observability

The deployed infrastructure includes comprehensive monitoring:

- **Application Insights**: Function execution telemetry, performance metrics, and error tracking
- **Azure Monitor**: Infrastructure-level metrics and alerts
- **Function App Logs**: Detailed execution logs and debugging information
- **Storage Analytics**: Table Storage operation metrics and performance data

Access monitoring data:

```bash
# View Function App logs
az functionapp log tail \
    --resource-group "rg-url-shortener" \
    --name "your-function-app-name"

# Query Application Insights
az monitor app-insights query \
    --app "your-function-app-name" \
    --analytics-query "requests | limit 10"
```

## Cost Optimization

This serverless architecture is designed for cost efficiency:

- **Consumption Plan**: Pay only for function executions (1M free requests/month)
- **Table Storage**: Pay per transaction and storage used (~$0.10/month for development)
- **Application Insights**: 5GB free data ingestion per month
- **Storage Account**: LRS replication for development, GRS for production scenarios

Estimated monthly costs:
- **Development/Testing**: $0.10 - $0.50
- **Production (1000 requests/day)**: $1.00 - $5.00
- **High Volume (100K requests/day)**: $10.00 - $25.00

## Security Considerations

The infrastructure implements security best practices:

- **Function App**: Anonymous auth level for public API, HTTPS-only communication
- **Storage Account**: Secure defaults with connection string-based access
- **Table Storage**: Partition/row key design prevents unauthorized data access
- **Application Insights**: Telemetry data encryption in transit and at rest
- **Network Security**: Azure platform-managed DDoS protection and TLS encryption

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name "rg-url-shortener" \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
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

# Verify resource deletion
az group show --name "rg-url-shortener" --query "properties.provisioningState"
```

## Troubleshooting

### Common Issues

**Function App deployment failures:**
```bash
# Check deployment status
az functionapp deployment list-publishing-profiles \
    --resource-group "rg-url-shortener" \
    --name "your-function-app-name"

# Restart Function App
az functionapp restart \
    --resource-group "rg-url-shortener" \
    --name "your-function-app-name"
```

**Storage Account connection issues:**
```bash
# Verify storage account access
az storage account show-connection-string \
    --resource-group "rg-url-shortener" \
    --name "your-storage-account"

# Test table accessibility
az storage table exists \
    --name "urlmappings" \
    --account-name "your-storage-account"
```

**Function execution errors:**
```bash
# View detailed logs
az functionapp log tail \
    --resource-group "rg-url-shortener" \
    --name "your-function-app-name" \
    --provider applicationInsights

# Check Function App configuration
az functionapp config appsettings list \
    --resource-group "rg-url-shortener" \
    --name "your-function-app-name"
```

## Customization

### Adding Custom Domains

```bash
# Add custom domain to Function App
az functionapp config hostname add \
    --resource-group "rg-url-shortener" \
    --name "your-function-app-name" \
    --hostname "api.yourdomain.com"
```

### Scaling Configuration

```bash
# Configure Function App scaling (if using Premium plan)
az functionapp plan update \
    --resource-group "rg-url-shortener" \
    --name "your-function-plan" \
    --max-burst 20 \
    --min-instances 1
```

### Environment-Specific Deployments

For multiple environments, use parameter files:

```bash
# Development environment
az deployment group create \
    --resource-group "rg-url-shortener-dev" \
    --template-file bicep/main.bicep \
    --parameters @parameters/dev.parameters.json

# Production environment
az deployment group create \
    --resource-group "rg-url-shortener-prod" \
    --template-file bicep/main.bicep \
    --parameters @parameters/prod.parameters.json
```

## Additional Resources

- [Azure Functions Best Practices](https://learn.microsoft.com/en-us/azure/azure-functions/functions-best-practices)
- [Azure Table Storage Performance Guide](https://learn.microsoft.com/en-us/azure/storage/tables/storage-performance-checklist)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure CLI Reference](https://learn.microsoft.com/en-us/cli/azure/)

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Azure service-specific documentation
3. Refer to the original recipe documentation
4. Consult Azure support resources

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment first
2. Update documentation to reflect changes
3. Validate security configurations
4. Ensure cost implications are understood
5. Update parameter descriptions and examples