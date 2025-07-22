# Infrastructure as Code for Event-Driven Data Validation with Azure Table Storage and Event Grid

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Event-Driven Data Validation with Azure Table Storage and Event Grid".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Storage accounts
  - Event Grid topics and subscriptions
  - Logic Apps
  - Azure Functions
  - Log Analytics workspaces
  - Application Insights
- Bash shell environment (Linux, macOS, or Windows with WSL)
- For Terraform: Terraform v1.0+ installed
- For Bicep: Bicep CLI installed (included with Azure CLI 2.20+)

## Architecture Overview

This solution deploys a complete real-time data validation system including:

- **Azure Storage Account** with Table Storage for data and validation rules
- **Azure Event Grid Topic** for event distribution
- **Azure Functions** for lightweight data validation
- **Azure Logic Apps** for complex validation workflows
- **Event Grid Subscriptions** to connect storage events to validation services
- **Monitoring Infrastructure** with Log Analytics and Application Insights

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the bicep directory
cd bicep/

# Set deployment parameters
RESOURCE_GROUP="rg-data-validation-demo"
LOCATION="eastus"
UNIQUE_SUFFIX=$(openssl rand -hex 3)

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file main.bicep \
    --parameters uniqueSuffix=${UNIQUE_SUFFIX} \
                 location=${LOCATION}

# Check deployment status
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan \
    -var="resource_group_name=rg-data-validation-demo" \
    -var="location=eastus" \
    -var="unique_suffix=$(openssl rand -hex 3)"

# Apply the configuration
terraform apply \
    -var="resource_group_name=rg-data-validation-demo" \
    -var="location=eastus" \
    -var="unique_suffix=$(openssl rand -hex 3)"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Navigate to the scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-data-validation-demo"
export LOCATION="eastus"
export UNIQUE_SUFFIX=$(openssl rand -hex 3)

# Deploy infrastructure
./deploy.sh

# Verify deployment
az resource list \
    --resource-group ${RESOURCE_GROUP} \
    --output table
```

## Configuration Options

### Bicep Parameters

The Bicep template accepts the following parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `uniqueSuffix` | string | Required | Unique suffix for resource names (6 characters max) |
| `location` | string | `eastus` | Azure region for deployment |
| `storageAccountSku` | string | `Standard_LRS` | Storage account SKU |
| `functionAppRuntime` | string | `python` | Function app runtime stack |
| `logAnalyticsRetentionDays` | int | `30` | Log Analytics data retention period |

### Terraform Variables

The Terraform configuration supports these variables:

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `resource_group_name` | string | Required | Name of the resource group |
| `location` | string | `eastus` | Azure region for deployment |
| `unique_suffix` | string | Required | Unique suffix for resource names |
| `storage_account_tier` | string | `Standard` | Storage account tier |
| `storage_account_replication_type` | string | `LRS` | Storage account replication type |
| `function_app_service_plan_tier` | string | `Dynamic` | Function app service plan tier |
| `tags` | map(string) | `{}` | Resource tags |

### Environment Variables (Bash Scripts)

The bash scripts use these environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `RESOURCE_GROUP` | Yes | Name of the resource group |
| `LOCATION` | Yes | Azure region for deployment |
| `UNIQUE_SUFFIX` | Yes | Unique suffix for resource names |
| `STORAGE_ACCOUNT_SKU` | No | Storage account SKU (default: Standard_LRS) |
| `FUNCTION_RUNTIME` | No | Function app runtime (default: python) |

## Post-Deployment Setup

After deploying the infrastructure, you'll need to:

1. **Deploy Function Code**: Upload the validation function code to the Azure Functions app
2. **Configure Logic App**: Set up the validation workflow in Logic Apps
3. **Insert Validation Rules**: Add sample validation rules to the ValidationRules table
4. **Test the Workflow**: Insert test data to verify the validation pipeline

### Deploy Function Code

```bash
# Get function app name from deployment outputs
FUNCTION_APP_NAME=$(az functionapp list \
    --resource-group ${RESOURCE_GROUP} \
    --query "[0].name" --output tsv)

# Create function code package (see original recipe for code)
mkdir -p /tmp/validation-function
cd /tmp/validation-function
# ... (create function files as shown in recipe)

# Deploy function code
az functionapp deployment source config-zip \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --src function-app.zip
```

### Configure Validation Rules

```bash
# Get storage connection string
STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
    --name ${STORAGE_ACCOUNT_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query connectionString --output tsv)

# Insert sample validation rules
az storage entity insert \
    --connection-string "${STORAGE_CONNECTION_STRING}" \
    --table-name "ValidationRules" \
    --entity PartitionKey="OrderValidation" RowKey="MinAmount" \
    Rule="amount >= 1" Description="Minimum order amount validation"
```

## Monitoring and Troubleshooting

### View Application Insights

```bash
# Get Application Insights name
INSIGHTS_NAME=$(az monitor app-insights component list \
    --resource-group ${RESOURCE_GROUP} \
    --query "[0].name" --output tsv)

# View recent events
az monitor app-insights events show \
    --app ${INSIGHTS_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --type traces \
    --offset 1h
```

### Check Function App Logs

```bash
# Stream function logs
az functionapp log tail \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP}
```

### Verify Event Grid Subscriptions

```bash
# List Event Grid subscriptions
az eventgrid event-subscription list \
    --resource-group ${RESOURCE_GROUP} \
    --output table
```

## Testing the Solution

### Insert Test Data

```bash
# Insert test order to trigger validation
az storage entity insert \
    --connection-string "${STORAGE_CONNECTION_STRING}" \
    --table-name "CustomerOrders" \
    --entity PartitionKey="Test" RowKey="Order001" \
    amount=1500 customerEmail="test@example.com" orderId="ORD001"

# Check validation results in function logs
az functionapp logs tail \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP}
```

### Monitor Event Flow

```bash
# View Event Grid metrics
az monitor metrics list \
    --resource ${EVENT_GRID_TOPIC_ID} \
    --metric "PublishSuccessCount" \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ)
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
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

# Destroy all resources
terraform destroy \
    -var="resource_group_name=rg-data-validation-demo" \
    -var="location=eastus" \
    -var="unique_suffix=your-suffix"

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Verify cleanup
az group exists --name ${RESOURCE_GROUP}
```

## Cost Optimization

This solution uses consumption-based pricing for most services. To optimize costs:

1. **Storage Account**: Use appropriate tier and replication settings
2. **Function App**: Consumption plan scales to zero when not in use
3. **Event Grid**: Pay-per-operation pricing with free tier allowances
4. **Logic Apps**: Consumption plan charges per action execution
5. **Log Analytics**: Set appropriate retention periods

### Estimated Monthly Costs (Development Environment)

- Storage Account: $1-5
- Function App: $0-10 (depends on executions)
- Event Grid: $0-5 (includes 100K operations free)
- Logic Apps: $0-10 (depends on workflow executions)
- Log Analytics: $2-15 (depends on data ingestion)

**Total Estimated Cost: $3-45/month**

*Note: Costs will vary based on actual usage, region, and configuration.*

## Security Considerations

The deployed infrastructure includes:

- **Storage Account**: Configured with secure defaults and access controls
- **Function App**: Managed identity enabled for secure resource access
- **Event Grid**: Webhook security with authentication
- **Logic Apps**: Managed identity for secure service connections
- **Monitoring**: Secure log aggregation and access controls

### Security Best Practices

1. Review and customize access policies for your environment
2. Enable Azure Security Center recommendations
3. Configure appropriate network security groups if needed
4. Use Azure Key Vault for sensitive configuration values
5. Implement least privilege access principles

## Troubleshooting

### Common Issues

1. **Deployment Failures**: Check resource naming conflicts and quotas
2. **Function App Issues**: Verify runtime version and dependencies
3. **Event Grid Problems**: Check subscription filters and endpoints
4. **Storage Access**: Verify connection strings and permissions
5. **Logic App Failures**: Check connector configurations and authentication

### Debug Commands

```bash
# Check resource deployment status
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query properties.provisioningState

# View deployment operations
az deployment operation group list \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --output table

# Check function app configuration
az functionapp config show \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP}
```

## Customization

### Adding Custom Validation Rules

Extend the validation logic by:

1. Adding new rules to the ValidationRules table
2. Updating the Function App validation code
3. Modifying Logic App workflows for complex scenarios
4. Adding new Event Grid subscriptions for additional triggers

### Scaling Considerations

For production environments, consider:

1. **Premium Function Plan**: For consistent performance
2. **Storage Account**: Higher tier for better performance
3. **Event Grid**: Custom topics for better organization
4. **Logic Apps**: Standard plan for predictable costs
5. **Multi-region**: Deployment for high availability

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation
3. Verify deployment parameters and prerequisites
4. Review Azure Monitor logs for runtime issues
5. Consult Azure support for service-specific problems

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Validate against the original recipe requirements
3. Ensure compatibility with all supported deployment methods
4. Update documentation as needed
5. Follow Azure resource naming conventions

---

*This infrastructure code is generated from the recipe "Event-Driven Data Validation with Azure Table Storage and Event Grid" - version 1.0*