# Infrastructure as Code for Real-Time Collaborative Workspace with Video Integration

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Collaborative Workspace with Video Integration".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Active Azure subscription with Contributor permissions
- Node.js 18.x or later (for Function App deployment)
- Terraform v1.0+ (if using Terraform implementation)
- Bicep CLI (if using Bicep implementation)
- Appropriate permissions for resource creation:
  - Microsoft.Communication/communicationServices
  - Microsoft.FluidRelay/fluidRelayServers
  - Microsoft.Web/sites
  - Microsoft.Storage/storageAccounts
  - Microsoft.KeyVault/vaults

## Architecture Overview

This solution deploys:

- **Azure Communication Services**: Provides video/audio conferencing and chat capabilities
- **Azure Fluid Relay**: Handles real-time synchronization of collaborative content
- **Azure Functions**: Serverless backend for token generation and business logic
- **Azure Storage Account**: Persistent storage for whiteboards and recordings
- **Azure Key Vault**: Secure storage for connection strings and secrets
- **Application Insights**: Monitoring and observability

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Set deployment parameters
export RESOURCE_GROUP="rg-collab-app"
export LOCATION="eastus"
export DEPLOYMENT_NAME="collab-app-$(date +%Y%m%d-%H%M%S)"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file main.bicep \
    --parameters @parameters.json \
    --name ${DEPLOYMENT_NAME}
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

# Optionally save plan for review
terraform plan -out=tfplan
terraform apply tfplan
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration
```

## Configuration

### Bicep Parameters

Edit `bicep/parameters.json` to customize your deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "resourceNamePrefix": {
      "value": "collab"
    },
    "environment": {
      "value": "demo"
    },
    "functionAppSku": {
      "value": "Y1"
    },
    "storageAccountSku": {
      "value": "Standard_LRS"
    }
  }
}
```

### Terraform Variables

Customize `terraform/terraform.tfvars`:

```hcl
# Basic configuration
location = "East US"
resource_name_prefix = "collab"
environment = "demo"

# Optional customizations
function_app_sku = "Y1"
storage_account_replication_type = "LRS"
key_vault_sku = "standard"
fluid_relay_sku = "basic"

# Tags
tags = {
  Environment = "Demo"
  Project     = "Collaborative-Apps"
  Owner       = "DevTeam"
}
```

## Post-Deployment Configuration

### Function App Deployment

After infrastructure deployment, deploy the Function App code:

```bash
# Create local function project
mkdir collab-functions && cd collab-functions

# Initialize function app
func init --worker-runtime node --language javascript

# Create token generation function
func new --name GetAcsToken --template "HTTP trigger"

# Deploy functions (replace with your Function App name)
func azure functionapp publish <your-function-app-name>
```

### Enable CORS

```bash
# Configure CORS for web application access
az functionapp cors add \
    --name <your-function-app-name> \
    --resource-group <your-resource-group> \
    --allowed-origins "*"
```

### Verify Deployment

```bash
# Test ACS token generation endpoint
curl -X POST https://<your-function-app>.azurewebsites.net/api/GetAcsToken \
    -H "Content-Type: application/json" \
    -d '{"userId": "testuser"}'

# Check Fluid Relay availability
az fluid-relay server show \
    --name <your-fluid-relay-name> \
    --resource-group <your-resource-group>
```

## Monitoring and Observability

### Application Insights

Monitor your collaborative application using the deployed Application Insights instance:

- **Function App Performance**: Monitor token generation latency and success rates
- **Custom Metrics**: Track collaborative session metrics
- **Availability Tests**: Set up synthetic monitoring for critical endpoints

### Azure Monitor

Key metrics to monitor:
- Azure Communication Services token generation rate
- Fluid Relay connection count and latency
- Function App execution time and errors
- Storage account request patterns

## Security Considerations

### Key Vault Integration

- All sensitive configuration is stored in Azure Key Vault
- Function App uses managed identity for secure access
- Secrets are referenced using Key Vault references in app settings

### Network Security

- Consider implementing Azure Private Endpoints for production deployments
- Use Azure Application Gateway with WAF for additional security
- Implement Azure AD authentication for user access

### Access Control

- Managed identities eliminate the need for stored credentials
- Role-based access control (RBAC) is configured for all resources
- Principle of least privilege is applied throughout

## Cleanup

### Using Bicep

```bash
# Delete resource group (removes all resources)
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait

# Verify deletion
az group exists --name ${RESOURCE_GROUP}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

## Troubleshooting

### Common Issues

1. **Function App Deployment Fails**:
   - Verify Azure CLI version and authentication
   - Check that the Function App runtime version matches your local development environment
   - Ensure all required app settings are configured

2. **Fluid Relay Connection Issues**:
   - Verify the Fluid Relay service is in the same region as your Function App
   - Check that the tenant ID and key are correctly configured
   - Ensure CORS is properly configured for web applications

3. **Token Generation Errors**:
   - Verify Azure Communication Services connection string is valid
   - Check that managed identity has access to Key Vault
   - Review Function App logs in Application Insights

### Getting Help

- Check Application Insights logs for detailed error information
- Review Azure Activity Log for deployment issues
- Consult the [Azure Communication Services documentation](https://docs.microsoft.com/en-us/azure/communication-services/)
- Reference the [Fluid Framework documentation](https://fluidframework.com/docs/)

## Cost Optimization

### Resource Sizing

- **Function App**: Uses Consumption plan for cost-effective scaling
- **Storage Account**: Standard LRS for basic durability requirements
- **Fluid Relay**: Basic SKU suitable for development and testing

### Cost Monitoring

```bash
# Set up cost alerts
az consumption budget create \
    --budget-name "collab-app-budget" \
    --amount 100 \
    --time-grain Monthly \
    --time-period start-date=$(date -d "first day of this month" +%Y-%m-%d) \
    --resource-group ${RESOURCE_GROUP}
```

## Scaling Considerations

### Production Deployment

For production workloads, consider:

- **Function App**: Upgrade to Premium plan for better performance
- **Storage Account**: Use Zone-redundant storage (ZRS) for higher availability
- **Fluid Relay**: Upgrade to Standard SKU for increased limits
- **Key Vault**: Consider Premium SKU for HSM-backed keys

### Multi-Region Deployment

For global applications:
- Deploy Function Apps in multiple regions
- Use Azure Front Door for global load balancing
- Consider geo-replication for storage accounts

## Customization

### Environment-Specific Configuration

Create separate parameter files for different environments:

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

### Additional Features

Extend the solution by adding:
- Azure Cosmos DB for persistent collaboration data
- Azure SignalR Service for enhanced real-time messaging
- Azure Active Directory B2C for user authentication
- Azure API Management for API governance

## Support

For issues with this infrastructure code:
1. Review the troubleshooting section above
2. Check the original recipe documentation
3. Consult Azure provider documentation
4. Review Azure service-specific documentation

## License

This infrastructure code is provided as-is under the same license as the recipes repository.