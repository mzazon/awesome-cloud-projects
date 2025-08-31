# Infrastructure as Code for Simple Event Notifications with Event Grid and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Event Notifications with Event Grid and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a serverless event notification system using:
- **Azure Event Grid Custom Topic**: Receives and routes custom application events
- **Azure Functions**: Processes events with serverless compute
- **Application Insights**: Provides monitoring and logging
- **Storage Account**: Required for Azure Functions runtime

## Prerequisites

- Azure CLI installed and configured (`az --version` should show 2.50.0 or later)
- Azure subscription with appropriate permissions:
  - `Contributor` role on target resource group
  - `EventGrid Contributor` role for Event Grid operations
  - `Storage Account Contributor` role for storage operations
- For Terraform: Terraform CLI installed (version 1.5.0 or later)
- For Bicep: Bicep CLI installed (version 0.20.0 or later)
- Basic understanding of serverless computing and event-driven architectures

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Set deployment parameters
export RESOURCE_GROUP="rg-recipe-$(openssl rand -hex 3)"
export LOCATION="eastus"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file main.bicep \
    --parameters location=${LOCATION}

# Get deployment outputs
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
resource_group_name = "rg-recipe-$(openssl rand -hex 3)"
location = "eastus"
environment = "demo"
EOF

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-recipe-$(openssl rand -hex 3)"
export LOCATION="eastus"

# Deploy infrastructure
./deploy.sh

# View created resources
az resource list \
    --resource-group ${RESOURCE_GROUP} \
    --output table
```

## Testing the Deployment

After deployment, test the event notification system:

```bash
# Get Event Grid topic endpoint and key (adjust based on your deployment method)
export TOPIC_ENDPOINT=$(az eventgrid topic show \
    --name "topic-notifications-${RANDOM_SUFFIX}" \
    --resource-group ${RESOURCE_GROUP} \
    --query "endpoint" --output tsv)

export TOPIC_KEY=$(az eventgrid topic key list \
    --name "topic-notifications-${RANDOM_SUFFIX}" \
    --resource-group ${RESOURCE_GROUP} \
    --query "key1" --output tsv)

# Send test event
EVENT_DATA=$(cat << EOF
[{
  "id": "$(uuidgen)",
  "source": "test-deployment",
  "specversion": "1.0",
  "type": "notification.test",
  "subject": "deployment/validation",
  "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "data": {
    "message": "Infrastructure deployment test",
    "priority": "high",
    "deploymentMethod": "IaC"
  }
}]
EOF
)

curl -X POST \
    -H "aeg-sas-key: ${TOPIC_KEY}" \
    -H "Content-Type: application/json" \
    -d "${EVENT_DATA}" \
    "${TOPIC_ENDPOINT}/api/events"

echo "✅ Test event sent! Check Function App logs for processing confirmation."
```

## Monitoring and Logs

### View Function Logs

```bash
# Stream live logs from Function App
FUNCTION_APP_NAME="func-processor-${RANDOM_SUFFIX}"
az webapp log tail \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP}

# View recent invocations
az monitor activity-log list \
    --resource-group ${RESOURCE_GROUP} \
    --max-items 10 \
    --output table
```

### Application Insights Queries

Access Application Insights in the Azure portal to run these queries:

```kusto
// View all function invocations
requests
| where timestamp > ago(1h)
| project timestamp, name, success, duration
| order by timestamp desc

// View custom events and traces
traces
| where timestamp > ago(1h)
| where message contains "Event Grid"
| project timestamp, message, severityLevel
| order by timestamp desc
```

## Customization

### Environment Variables

Each implementation supports customization through variables:

**Bicep Parameters:**
- `location`: Azure region for deployment (default: resource group location)
- `environment`: Environment tag value (default: "demo")
- `functionAppSku`: Function App service plan SKU (default: "Y1" for consumption)

**Terraform Variables:**
- `resource_group_name`: Name of the resource group
- `location`: Azure region for deployment
- `environment`: Environment tag for resources
- `storage_account_tier`: Storage account performance tier (default: "Standard")
- `storage_account_replication`: Storage replication type (default: "LRS")

**Bash Script Variables:**
Set these environment variables before running deploy.sh:
- `RESOURCE_GROUP`: Target resource group name
- `LOCATION`: Azure region
- `ENVIRONMENT`: Environment tag (optional, defaults to "demo")

### Function Code Customization

To modify the event processing logic:

1. Update the function code in the deployment templates
2. Customize event filtering in the Event Grid subscription
3. Add additional output bindings for processed events (e.g., to Cosmos DB, Service Bus)

### Advanced Configuration

**Event Grid Topic Settings:**
- Modify `inputSchema` to support different event formats
- Configure advanced filtering rules in subscriptions
- Add multiple event subscriptions for fan-out scenarios

**Function App Settings:**
- Adjust runtime version and language stack
- Configure application settings for custom behavior
- Enable additional monitoring and diagnostics

**Security Enhancements:**
- Implement managed identity authentication
- Configure private endpoints for secure communication
- Add Key Vault integration for sensitive configuration

## Cleanup

### Using Bicep

```bash
# Delete resource group and all resources
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait

echo "✅ Resource group deletion initiated"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
# Type 'yes' to confirm destruction
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Follow prompts to confirm resource deletion
```

## Cost Optimization

This solution uses consumption-based pricing:

**Estimated Monthly Costs (Low Volume):**
- Event Grid: $0.60 per million operations
- Azure Functions: $0.20 per million executions + $0.000016 per GB-second
- Storage Account: $0.045 per GB (minimal usage for function metadata)
- Application Insights: First 5GB free, then $2.88 per GB

**Total Estimated Cost:** $2-5 per month for development/testing scenarios

**Cost Optimization Tips:**
- Functions automatically scale to zero when not processing events
- Use consumption plan for variable workloads
- Monitor Application Insights data retention settings
- Set up billing alerts for unexpected usage

## Troubleshooting

### Common Issues

**Event Grid Topic Creation Fails:**
- Verify Event Grid resource provider is registered
- Check regional availability of Event Grid services
- Ensure proper permissions for Event Grid operations

**Function Deployment Issues:**
- Verify Function App runtime version compatibility
- Check storage account accessibility
- Ensure Application Insights is properly configured

**Event Processing Failures:**
- Check function logs in Application Insights
- Verify Event Grid subscription webhook endpoint
- Test event format matches Cloud Events v1.0 schema

### Diagnostic Commands

```bash
# Check resource provider registration
az provider show --namespace Microsoft.EventGrid --query registrationState

# Verify function app status
az functionapp show \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query state

# Test Event Grid topic connectivity
az eventgrid topic show \
    --name ${TOPIC_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query provisioningState
```

## Support and Documentation

- [Azure Event Grid Documentation](https://learn.microsoft.com/en-us/azure/event-grid/)
- [Azure Functions Documentation](https://learn.microsoft.com/en-us/azure/azure-functions/)
- [Cloud Events v1.0 Specification](https://cloudevents.io/)
- [Azure Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or the Azure documentation links above.

## Security Considerations

**Production Recommendations:**
- Enable managed identity for Function App authentication
- Use Azure Key Vault for sensitive configuration values
- Implement network security groups and private endpoints
- Enable Azure Security Center recommendations
- Configure diagnostic logging for security monitoring
- Use Azure Policy for governance and compliance

**Development Guidelines:**
- Never commit API keys or connection strings to source control
- Use Azure CLI or Azure PowerShell for secure deployments
- Implement least privilege access for all service principals
- Regularly review and rotate access keys
- Enable Azure Monitor alerts for security events