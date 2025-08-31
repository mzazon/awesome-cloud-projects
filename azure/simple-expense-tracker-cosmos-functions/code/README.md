# Infrastructure as Code for Simple Expense Tracker with Cosmos DB and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Expense Tracker with Cosmos DB and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a serverless expense tracking API with the following components:

- **Azure Cosmos DB**: Serverless NoSQL database for expense storage
- **Azure Functions**: HTTP-triggered functions for expense management operations
- **Azure Storage Account**: Backend storage for Function App runtime
- **Resource Group**: Container for all resources

## Prerequisites

- Azure CLI installed and configured (`az --version` to verify)
- Azure subscription with appropriate permissions for:
  - Creating resource groups
  - Creating Cosmos DB accounts
  - Creating Function Apps and Storage Accounts
  - Managing application settings
- For Bicep deployment: Azure CLI with Bicep extension
- For Terraform deployment: Terraform >= 1.0 installed
- Basic understanding of serverless architectures and REST APIs

## Cost Estimates

This solution uses Azure's serverless offerings with consumption-based pricing:

- **Cosmos DB Serverless**: ~$0.25 per million request units + $0.25 per GB storage/month
- **Azure Functions Consumption**: ~$0.20 per million executions + compute time
- **Storage Account**: ~$0.02 per GB/month (minimal usage for function metadata)

**Expected monthly cost for light usage**: $0.01 - $5.00

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-expense-tracker-demo \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters uniqueSuffix=$(openssl rand -hex 3)
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="location=eastus" -var="unique_suffix=$(openssl rand -hex 3)"

# Deploy the infrastructure
terraform apply -var="location=eastus" -var="unique_suffix=$(openssl rand -hex 3)"
```

### Using Bash Scripts

```bash
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy the complete solution
./deploy.sh
```

## Deployment Details

### Bicep Deployment

The Bicep template creates all necessary Azure resources with best practices:

- Serverless Cosmos DB account with optimized consistency settings
- Function App with Node.js runtime and consumption plan
- Automatic configuration of connection strings and app settings
- Proper resource tagging and naming conventions

### Terraform Deployment

The Terraform configuration uses official Azure provider modules:

- Modular resource definitions for maintainability
- Variable-driven configuration for customization
- Comprehensive output values for integration
- State management for infrastructure lifecycle

### Bash Script Deployment

The deployment scripts provide a step-by-step automated approach:

- Environment validation and prerequisite checks
- Resource creation with proper error handling
- Function code deployment and configuration
- Verification and testing procedures

## Configuration Options

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | eastus | Yes |
| `unique_suffix` | Unique suffix for resource names | random | Yes |
| `environment` | Environment tag (dev/test/prod) | demo | No |

### Bicep Parameters

Additional Bicep-specific parameters in `main.bicep`:

- `cosmosAccountName`: Custom Cosmos DB account name
- `functionAppName`: Custom Function App name
- `storageAccountName`: Custom storage account name

### Terraform Variables

Additional Terraform variables in `variables.tf`:

- `resource_group_name`: Custom resource group name
- `tags`: Additional resource tags
- `function_runtime_version`: Azure Functions runtime version

## Post-Deployment

### Verify Deployment

1. **Check resource status**:
   ```bash
   # Verify all resources are running
   az resource list --resource-group rg-expense-tracker-<suffix> --output table
   ```

2. **Get function URLs**:
   ```bash
   # Get function app name from deployment outputs
   FUNCTION_APP=$(az functionapp list --resource-group rg-expense-tracker-<suffix> --query "[0].name" -o tsv)
   
   # Get function URLs for testing
   az functionapp function show --name $FUNCTION_APP --resource-group rg-expense-tracker-<suffix> --function-name CreateExpense
   ```

### Test the API

1. **Create an expense**:
   ```bash
   curl -X POST "https://<function-app>.azurewebsites.net/api/CreateExpense?code=<function-key>" \
        -H "Content-Type: application/json" \
        -d '{
          "amount": 15.50,
          "category": "food",
          "description": "Lunch at cafe",
          "userId": "user123"
        }'
   ```

2. **Retrieve expenses**:
   ```bash
   curl "https://<function-app>.azurewebsites.net/api/GetExpenses?code=<function-key>&userId=user123"
   ```

## Monitoring and Operations

### Application Insights

The deployment includes Application Insights integration for:

- Function performance monitoring
- Error tracking and diagnostics
- Usage analytics and metrics
- Custom telemetry and alerts

### Cosmos DB Monitoring

Monitor your Cosmos DB usage through:

- Azure portal metrics dashboard
- Request unit consumption tracking
- Storage utilization monitoring
- Query performance analysis

### Cost Management

- Set up Azure Cost Management alerts for budget monitoring
- Use Azure Advisor recommendations for cost optimization
- Monitor serverless consumption patterns
- Implement resource auto-shutdown for development environments

## Security Considerations

### Function App Security

- Function keys are automatically generated for API access
- HTTPS enforcement is enabled by default
- CORS settings should be configured for web client access
- Consider implementing Azure Active Directory authentication for production

### Cosmos DB Security

- Connection strings are stored securely in Function App settings
- Network access can be restricted using firewall rules
- Consider enabling Azure Private Link for enhanced network security
- Implement role-based access control (RBAC) for fine-grained permissions

### Best Practices Applied

- All secrets stored in Azure Key Vault or Function App settings
- Least privilege access principles followed
- Resource-level locks prevent accidental deletion
- Audit logging enabled for compliance tracking

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name rg-expense-tracker-<suffix> --yes --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all managed infrastructure
terraform destroy -var="location=eastus" -var="unique_suffix=<your-suffix>"
```

### Using Bash Scripts

```bash
cd scripts/

# Run the cleanup script
./destroy.sh
```

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   - Verify storage account is accessible
   - Check Function App runtime settings
   - Ensure Cosmos DB connection string is valid

2. **Cosmos DB connection errors**:
   - Verify firewall settings allow Function App access
   - Check connection string format and permissions
   - Ensure database and container exist

3. **Resource naming conflicts**:
   - Use a different unique suffix
   - Check for existing resources with same names
   - Verify resource name length limits

### Debug Commands

```bash
# Check Function App logs
az functionapp log tail --name <function-app-name> --resource-group <resource-group>

# Test Cosmos DB connectivity
az cosmosdb sql database list --account-name <cosmos-account> --resource-group <resource-group>

# Verify Function App configuration
az functionapp config appsettings list --name <function-app-name> --resource-group <resource-group>
```

## Customization

### Adding New Functions

1. Create new function directories in the deployment scripts
2. Update the Bicep/Terraform templates to include new function configurations
3. Modify the deployment scripts to deploy additional function code

### Database Schema Changes

1. Update the Cosmos DB container configuration in IaC templates
2. Modify function code to handle new document structures
3. Consider implementing database migration patterns for existing data

### Scaling Considerations

For production environments, consider:

- Implementing API Management for rate limiting and caching
- Using Premium Function plans for consistent performance
- Implementing multi-region deployment for global availability
- Adding Azure Front Door for global load balancing

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for architectural guidance
2. Check Azure documentation for service-specific configurations
3. Consult provider documentation for IaC tool usage
4. Review Azure status page for any service outages

### Useful Links

- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Cosmos DB Documentation](https://docs.microsoft.com/en-us/azure/cosmos-db/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [Azure CLI Reference](https://docs.microsoft.com/en-us/cli/azure/)

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment first
2. Follow Azure naming conventions and best practices
3. Update documentation for any new parameters or outputs
4. Ensure cleanup procedures work correctly
5. Validate security configurations meet organizational requirements