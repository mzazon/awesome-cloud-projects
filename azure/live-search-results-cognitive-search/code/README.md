# Infrastructure as Code for Live Search Results with Cognitive Search and SignalR

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Live Search Results with Cognitive Search and SignalR".

## Available Implementations

- **Bicep**: Azure native infrastructure as code using Bicep language
- **Terraform**: Multi-cloud infrastructure as code with Azure Resource Manager provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a complete real-time search infrastructure including:

- **Azure Cognitive Search**: Full-text search service with custom index
- **Azure SignalR Service**: Real-time communication hub for WebSocket connections
- **Azure Functions**: Serverless compute for index updates and notifications
- **Azure Event Grid**: Event routing and delivery service
- **Azure Cosmos DB**: Document database with change feed capabilities
- **Azure Storage Account**: Storage for Azure Functions runtime

## Prerequisites

### General Requirements

- Azure CLI v2.50+ installed and configured
- Azure subscription with appropriate permissions
- Bash shell environment (Linux, macOS, or WSL on Windows)

### Resource Creation Permissions

Your Azure account needs the following permissions:
- Contributor role on the target subscription or resource group
- Ability to create and manage:
  - Azure Cognitive Search services
  - Azure SignalR Service
  - Azure Functions and App Service Plans
  - Azure Cosmos DB accounts
  - Azure Event Grid topics
  - Azure Storage accounts
  - Azure Event Grid subscriptions

### Tool-Specific Prerequisites

#### For Bicep Deployment
- Azure CLI with Bicep support (included by default in CLI v2.20+)
- Verify Bicep installation: `az bicep version`

#### For Terraform Deployment
- Terraform v1.0+ installed ([download here](https://www.terraform.io/downloads.html))
- Azure CLI configured with: `az login`

#### For Bash Scripts
- Azure CLI v2.50+ configured
- jq installed for JSON processing
- Node.js 18+ for Azure Functions development

## Cost Estimates

Expected monthly costs for moderate usage (US East region):

| Service | Tier/SKU | Estimated Cost |
|---------|----------|----------------|
| Azure Cognitive Search | Basic (1 SU) | ~$250/month |
| Azure SignalR Service | Standard S1 (1 unit) | ~$50/month |
| Azure Functions | Consumption Plan | ~$5-20/month |
| Azure Cosmos DB | 400 RU/s provisioned | ~$25/month |
| Azure Event Grid | Standard tier | ~$2/month |
| Azure Storage | Standard LRS | ~$5/month |
| **Total** | | **~$337-352/month** |

> **Note**: Costs vary by region and actual usage. Use the [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) for precise estimates.

## Quick Start

### Using Bicep

Deploy the complete infrastructure with Azure's native Bicep language:

```bash
# Clone or navigate to the code directory
cd bicep/

# Deploy with default parameters
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters location=eastus

# Deploy with custom parameters
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform

Deploy using Terraform for infrastructure as code:

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Confirm deployment when prompted
# Type 'yes' to proceed
```

### Using Bash Scripts

Deploy using the automated bash scripts:

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts and confirm deployment
```

## Configuration Options

### Bicep Parameters

Key parameters you can customize in `bicep/main.bicep`:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `eastus` | Azure region for deployment |
| `environmentName` | string | `dev` | Environment prefix for naming |
| `searchServiceSku` | string | `basic` | Search service pricing tier |
| `signalRServiceSku` | string | `Standard_S1` | SignalR service pricing tier |
| `cosmosDbThroughput` | int | `400` | Cosmos DB provisioned throughput |

### Terraform Variables

Customize your deployment by modifying `terraform/variables.tf` or using a `terraform.tfvars` file:

```hcl
# terraform.tfvars example
location = "eastus"
environment = "prod"
search_service_sku = "standard"
signalr_sku = "Standard_S1"
cosmos_throughput = 800
```

### Script Configuration

The bash scripts use environment variables for configuration:

```bash
# Set before running deploy.sh
export LOCATION="eastus"
export ENVIRONMENT="staging"
export SEARCH_SKU="basic"
export SIGNALR_SKU="Standard_S1"
```

## Deployment Details

### Resource Naming Convention

All implementations follow this naming pattern:
- Resource Group: `rg-realtimesearch-{environment}`
- Search Service: `search-{environment}-{random}`
- SignalR Service: `signalr-{environment}-{random}`
- Function App: `func-{environment}-{random}`
- Cosmos DB: `cosmos-{environment}-{random}`
- Storage Account: `st{environment}{random}`
- Event Grid Topic: `topic-{environment}-{random}`

### Security Configurations

All implementations include these security best practices:

- **Managed Identity**: Functions use system-assigned managed identities
- **HTTPS Only**: All services configured for HTTPS-only communication
- **Network Security**: Private endpoints where applicable
- **Access Controls**: Least privilege access patterns
- **Key Vault Integration**: Secrets stored in Azure Key Vault (Bicep/Terraform)

### Monitoring and Diagnostics

Each deployment includes:

- **Application Insights**: Function app monitoring and telemetry
- **Diagnostic Settings**: Logging for all major services
- **Health Checks**: Built-in service health monitoring
- **Alerts**: Basic alerting on service availability

## Validation

After deployment, verify the infrastructure:

### Check Service Status

```bash
# Verify Search service
az search service show \
    --name <search-service-name> \
    --resource-group <resource-group> \
    --query "{name:name, status:status, sku:sku.name}"

# Verify SignalR service
az signalr show \
    --name <signalr-service-name> \
    --resource-group <resource-group> \
    --query "{name:name, hostName:hostName, sku:sku.name}"

# Verify Function app
az functionapp show \
    --name <function-app-name> \
    --resource-group <resource-group> \
    --query "{name:name, state:state, kind:kind}"
```

### Test Connectivity

```bash
# Test search service endpoint
curl -X GET "https://<search-service>.search.windows.net/indexes?api-version=2021-04-30-Preview" \
    -H "api-key: <admin-key>"

# Test SignalR negotiate endpoint (should return auth challenge)
curl -i "https://<signalr-service>.service.signalr.net/client/negotiate?hub=searchHub"
```

## Troubleshooting

### Common Issues

#### Deployment Failures

1. **Insufficient Permissions**: Ensure your account has Contributor role
2. **Resource Name Conflicts**: Use unique names or different regions
3. **Quota Limits**: Check service quotas in your subscription
4. **Region Availability**: Verify all services are available in target region

#### Function Deployment Issues

1. **Package Size**: Ensure function packages are under size limits
2. **Runtime Version**: Verify Node.js 18 compatibility
3. **Connection Strings**: Validate all service connection strings
4. **Binding Configurations**: Check function binding configurations

### Debugging Commands

```bash
# Check resource group deployment status
az deployment group list \
    --resource-group <resource-group> \
    --query "[0].{name:name, state:properties.provisioningState, timestamp:properties.timestamp}"

# View detailed error messages
az deployment group show \
    --resource-group <resource-group> \
    --name <deployment-name> \
    --query "properties.error"

# Check function logs
az functionapp logs tail \
    --name <function-app-name> \
    --resource-group <resource-group>
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <resource-group-name> \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
# Type 'yes' to proceed
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

### Manual Cleanup Verification

```bash
# Verify resource group deletion
az group exists --name <resource-group-name>

# Should return: false
```

## Customization

### Adding Custom Resources

1. **Bicep**: Add resources to `bicep/main.bicep` or create modules in `bicep/modules/`
2. **Terraform**: Add resources to `terraform/main.tf` or create separate `.tf` files
3. **Scripts**: Modify `scripts/deploy.sh` to include additional Azure CLI commands

### Scaling Configuration

For production workloads, consider these modifications:

```hcl
# Terraform example for production scaling
variable "search_service_sku" {
  default = "standard"  # Up from basic
}

variable "signalr_sku" {
  default = "Standard_S1"  # Multiple units for scale
}

variable "cosmos_throughput" {
  default = 1000  # Higher throughput
}
```

### Multi-Environment Setup

Use different parameter files for various environments:

```bash
# Development environment
az deployment group create \
    --template-file main.bicep \
    --parameters @parameters.dev.json

# Production environment
az deployment group create \
    --template-file main.bicep \
    --parameters @parameters.prod.json
```

## Performance Optimization

### Search Service Optimization

- **Indexing Strategy**: Use batch indexing for large datasets
- **Query Optimization**: Implement caching for frequent queries
- **Replica Scaling**: Add replicas for read-heavy workloads

### SignalR Optimization

- **Connection Management**: Implement connection pooling
- **Message Batching**: Batch multiple updates when possible
- **Scaling Units**: Add units based on concurrent connection needs

### Function Performance

- **Cold Start Mitigation**: Use Premium plan for production
- **Memory Allocation**: Optimize function memory settings
- **Concurrency**: Configure appropriate concurrency limits

## Support and Documentation

### Official Documentation

- [Azure Cognitive Search Documentation](https://docs.microsoft.com/en-us/azure/search/)
- [Azure SignalR Service Documentation](https://docs.microsoft.com/en-us/azure/azure-signalr/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Event Grid Documentation](https://docs.microsoft.com/en-us/azure/event-grid/)
- [Azure Cosmos DB Documentation](https://docs.microsoft.com/en-us/azure/cosmos-db/)

### IaC Tool Documentation

- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure CLI Reference](https://docs.microsoft.com/en-us/cli/azure/)

### Getting Help

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service status at [Azure Status](https://status.azure.com/)
3. Consult the Azure documentation links above
4. Use Azure support channels for service-specific issues

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow the existing code patterns and conventions
3. Update documentation for any new parameters or resources
4. Ensure all implementations (Bicep, Terraform, Scripts) remain synchronized