# Infrastructure as Code for Unified Customer Communication Platform with Event-Driven Messaging

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Unified Customer Communication Platform with Event-Driven Messaging".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM template language)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az --version` to verify)
- Appropriate Azure subscription with sufficient permissions
- PowerShell 7+ or Bash shell environment
- Resource creation permissions for:
  - Azure Communication Services
  - Azure Event Grid
  - Azure Functions
  - Azure Cosmos DB
  - Azure Storage Accounts
  - Resource Groups

### Required Azure Permissions

- `Contributor` role on the subscription or resource group
- `Communication Services Contributor` role for Azure Communication Services
- `EventGrid Contributor` role for Event Grid resources
- `Cosmos DB Account Reader Writer` role for Cosmos DB operations

## Architecture Overview

This solution deploys a complete multi-channel customer communication platform including:

- **Azure Communication Services**: Multi-channel messaging infrastructure (email, SMS, WhatsApp)
- **Azure Event Grid**: Event-driven architecture for real-time message processing
- **Azure Functions**: Serverless compute for message routing and processing
- **Azure Cosmos DB**: NoSQL database for conversation and message storage
- **Azure Storage Account**: Backend storage for Azure Functions runtime

## Quick Start

### Using Bicep

```bash
# Navigate to the bicep directory
cd bicep/

# Login to Azure (if not already authenticated)
az login

# Set your preferred Azure subscription
az account set --subscription "your-subscription-id"

# Create resource group
az group create \
    --name "rg-multi-channel-comms" \
    --location "East US"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-multi-channel-comms" \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment status
az deployment group show \
    --resource-group "rg-multi-channel-comms" \
    --name "main"
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="resource_group_name=rg-multi-channel-comms" \
    -var="location=East US"

# Apply the configuration
terraform apply \
    -var="resource_group_name=rg-multi-channel-comms" \
    -var="location=East US"

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters:
# - Resource group name
# - Azure region
# - Environment tag (dev/staging/prod)
```

## Configuration Options

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
    "environment": {
      "value": "dev"
    },
    "communicationServiceName": {
      "value": "acs-platform"
    },
    "cosmosAccountName": {
      "value": "cosmos-comms"
    }
  }
}
```

### Terraform Variables

Customize `terraform/terraform.tfvars`:

```hcl
resource_group_name = "rg-multi-channel-comms"
location           = "East US"
environment        = "development"

# Optional: Override default resource names
communication_service_name = "acs-platform-custom"
cosmos_account_name       = "cosmos-comms-custom"
function_app_name        = "func-comms-custom"
```

### Environment Variables for Scripts

Set these environment variables before running bash scripts:

```bash
export AZURE_RESOURCE_GROUP="rg-multi-channel-comms"
export AZURE_LOCATION="eastus"
export AZURE_ENVIRONMENT="dev"
export COMMUNICATION_SERVICE_NAME="acs-platform"
export COSMOS_ACCOUNT_NAME="cosmos-comms"
```

## Post-Deployment Configuration

### 1. Configure Communication Services Channels

After deployment, configure the communication channels:

```bash
# Get the Communication Services resource name
COMM_SERVICE_NAME=$(az communication list \
    --resource-group "rg-multi-channel-comms" \
    --query "[0].name" --output tsv)

# Configure email domain (requires domain verification)
az communication email domain create \
    --email-service-name "${COMM_SERVICE_NAME}" \
    --resource-group "rg-multi-channel-comms" \
    --domain-name "your-domain.com"

# Note: SMS and WhatsApp require additional setup through Azure portal
```

### 2. Test the Deployment

```bash
# Get Function App URL
FUNCTION_URL=$(az functionapp show \
    --name "func-comms-processor-${RANDOM_SUFFIX}" \
    --resource-group "rg-multi-channel-comms" \
    --query "defaultHostName" --output tsv)

# Test message routing endpoint
curl -X POST "https://${FUNCTION_URL}/api/MessageRouter" \
    -H "Content-Type: application/json" \
    -d '{
        "customerId": "test-customer-123",
        "message": "Hello from the communication platform",
        "channels": ["email", "sms"],
        "priority": "normal"
    }'
```

### 3. Monitor Resources

```bash
# Check all deployed resources
az resource list \
    --resource-group "rg-multi-channel-comms" \
    --output table

# Monitor Function App logs
az functionapp logs tail \
    --name "func-comms-processor-${RANDOM_SUFFIX}" \
    --resource-group "rg-multi-channel-comms"
```

## Cost Optimization

### Development Environment

For development and testing, consider these cost-saving options:

- Use Azure Communication Services free tier limits
- Deploy Functions on Consumption plan (pay-per-execution)
- Use Cosmos DB free tier (400 RU/s, 5GB storage)
- Set up budget alerts in Azure Cost Management

### Production Environment

For production deployments:

- Consider Azure Communication Services volume discounts
- Implement Cosmos DB autoscale for variable workloads
- Use Azure Functions Premium plan for consistent performance
- Enable Azure Monitor for comprehensive observability

## Security Considerations

### Network Security

```bash
# Enable private endpoints for Cosmos DB (post-deployment)
az cosmosdb private-endpoint-connection create \
    --account-name "cosmos-comms-${RANDOM_SUFFIX}" \
    --resource-group "rg-multi-channel-comms" \
    --name "cosmos-private-endpoint"
```

### Identity and Access Management

- The deployment creates managed identities for secure service-to-service communication
- Function Apps use system-assigned managed identities
- Cosmos DB access is controlled through Azure AD authentication

### Secrets Management

- Connection strings and API keys are stored in Azure Key Vault
- Function Apps retrieve secrets using managed identity
- No sensitive information is stored in application code

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name "rg-multi-channel-comms" \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy \
    -var="resource_group_name=rg-multi-channel-comms" \
    -var="location=East US"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will ask for confirmation before deleting resources
```

### Manual Verification

```bash
# Verify all resources are deleted
az resource list \
    --resource-group "rg-multi-channel-comms" \
    --output table

# If empty, delete the resource group
az group delete \
    --name "rg-multi-channel-comms" \
    --yes
```

## Troubleshooting

### Common Issues

1. **Communication Services Provisioning Failure**
   ```bash
   # Check service availability in your region
   az communication list-sku \
       --location "eastus"
   ```

2. **Function App Deployment Timeout**
   ```bash
   # Check deployment status
   az functionapp deployment list \
       --name "func-comms-processor-${RANDOM_SUFFIX}" \
       --resource-group "rg-multi-channel-comms"
   ```

3. **Cosmos DB Connection Issues**
   ```bash
   # Verify Cosmos DB endpoint and keys
   az cosmosdb show \
       --name "cosmos-comms-${RANDOM_SUFFIX}" \
       --resource-group "rg-multi-channel-comms" \
       --query "{endpoint:documentEndpoint, status:provisioningState}"
   ```

### Getting Help

- Review Azure service documentation for specific configuration issues
- Check Azure Status page for service outages
- Use Azure Support for production environment issues
- Reference the original recipe documentation for architectural guidance

## Integration Examples

### CRM Integration

```javascript
// Example Function App code for CRM webhook integration
module.exports = async function (context, req) {
    const { customerId, crmEventType, metadata } = req.body;
    
    // Process CRM events and trigger appropriate communications
    if (crmEventType === 'new_lead') {
        await sendWelcomeMessage(customerId, metadata);
    }
};
```

### Analytics Dashboard

```bash
# Deploy Power BI workspace for communication analytics
az resource create \
    --resource-group "rg-multi-channel-comms" \
    --resource-type "Microsoft.PowerBIDedicated/capacities" \
    --name "powerbi-comms-analytics" \
    --properties '{
        "administration": {
            "members": ["admin@yourdomain.com"]
        },
        "sku": {
            "name": "A1",
            "tier": "PBIE_Azure"
        }
    }'
```

## Support

For issues with this infrastructure code:

1. **Infrastructure Issues**: Check Azure Resource Manager deployment logs
2. **Application Issues**: Review Function App logs and Application Insights
3. **Recipe Questions**: Refer to the original recipe documentation
4. **Azure Services**: Consult official Azure documentation

## License

This infrastructure code is provided as-is under the same license as the parent recipe repository.