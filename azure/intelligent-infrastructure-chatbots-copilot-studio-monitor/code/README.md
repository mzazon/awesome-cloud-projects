# Infrastructure as Code for Intelligent Infrastructure ChatBots with Azure Copilot Studio and Azure Monitor

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Infrastructure ChatBots with Azure Copilot Studio and Azure Monitor".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Appropriate Azure subscription permissions for:
  - Resource Group creation and management
  - Azure Functions deployment
  - Log Analytics workspace creation
  - Application Insights configuration
  - Storage Account management
- Power Platform developer license or trial for Azure Copilot Studio
- Basic understanding of conversational AI concepts and Azure monitoring

## Architecture Overview

This solution deploys:
- Azure Functions App for query processing
- Log Analytics workspace for monitoring data collection
- Application Insights for telemetry and performance monitoring
- Storage Account for Function App requirements
- Necessary IAM roles and permissions for secure integration

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Review and customize parameters
az deployment group create \
    --resource-group your-resource-group \
    --template-file main.bicep \
    --parameters @parameters.json
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
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration

### Bicep Parameters

Key parameters you can customize in `bicep/parameters.json`:

- `location`: Azure region for resource deployment (default: eastus)
- `resourcePrefix`: Prefix for resource naming (default: infra-bot)
- `functionAppSku`: Function App hosting plan SKU
- `logAnalyticsWorkspaceSku`: Log Analytics workspace pricing tier

### Terraform Variables

Key variables you can customize in `terraform/terraform.tfvars`:

- `location`: Azure region for deployment
- `resource_group_name`: Name of the resource group
- `function_app_name`: Name for the Function App
- `storage_account_name`: Name for the storage account
- `log_analytics_workspace_name`: Name for Log Analytics workspace

### Environment Variables

The following environment variables are used by the bash scripts:

```bash
export RESOURCE_GROUP="rg-chatbot-infrastructure"
export LOCATION="eastus"
export FUNCTION_APP_NAME="func-infra-bot"
export STORAGE_ACCOUNT_NAME="stinfrabot"
export LOG_ANALYTICS_WORKSPACE="law-infra-bot"
export APP_INSIGHTS_NAME="ai-infra-bot"
```

## Post-Deployment Configuration

After deploying the infrastructure, complete these additional steps:

1. **Configure Azure Copilot Studio**:
   - Access the Power Platform Admin Center
   - Create a new bot in Azure Copilot Studio
   - Configure the Function App endpoint as a webhook

2. **Set up Conversational Topics**:
   - Import the provided topic configuration
   - Configure trigger phrases for infrastructure queries
   - Test conversational flows

3. **Configure Monitoring Data Sources**:
   - Connect existing Azure resources to the Log Analytics workspace
   - Verify data collection for Virtual Machines, App Services, and Storage Accounts

## Validation

### Verify Function App Deployment

```bash
# Check Function App status
az functionapp show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${FUNCTION_APP_NAME} \
    --query state

# Test function endpoint (after deployment)
curl -X POST "https://${FUNCTION_APP_NAME}.azurewebsites.net/api/QueryProcessor" \
    -H "Content-Type: application/json" \
    -d '{"query": "show me CPU usage"}'
```

### Verify Log Analytics Integration

```bash
# Check workspace status
az monitor log-analytics workspace show \
    --resource-group ${RESOURCE_GROUP} \
    --workspace-name ${LOG_ANALYTICS_WORKSPACE}

# Test query execution
az monitor log-analytics query \
    --workspace ${WORKSPACE_ID} \
    --analytics-query "Heartbeat | take 5"
```

### Verify Application Insights

```bash
# Check Application Insights configuration
az monitor app-insights component show \
    --app ${APP_INSIGHTS_NAME} \
    --resource-group ${RESOURCE_GROUP}
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name your-resource-group \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

## Cost Considerations

This solution uses consumption-based pricing for most services:

- **Azure Functions**: Pay-per-execution (Consumption plan)
- **Log Analytics**: Pay-per-GB ingested and retained
- **Application Insights**: Pay-per-GB ingested
- **Storage Account**: Standard LRS pricing

Estimated daily cost: $10-20 for moderate usage scenarios.

## Security Features

The deployed infrastructure includes:

- Managed Identity for secure Azure Monitor access
- Function-level authorization keys
- Application Insights instrumentation for monitoring
- Secure storage account configuration
- Log Analytics workspace with appropriate retention policies

## Troubleshooting

### Common Issues

1. **Function App deployment fails**:
   - Verify Azure CLI authentication
   - Check resource group permissions
   - Ensure storage account name is globally unique

2. **Log Analytics queries return no data**:
   - Verify data sources are configured
   - Check workspace permissions
   - Allow time for data ingestion (5-10 minutes)

3. **Application Insights not receiving telemetry**:
   - Verify instrumentation key configuration
   - Check Function App application settings
   - Ensure Application Insights is in the same region

### Debug Commands

```bash
# Check Function App logs
az functionapp log tail \
    --resource-group ${RESOURCE_GROUP} \
    --name ${FUNCTION_APP_NAME}

# View Application Insights live metrics
az monitor app-insights events show \
    --app ${APP_INSIGHTS_NAME} \
    --resource-group ${RESOURCE_GROUP}
```

## Customization

### Adding New Query Types

Extend the solution by modifying the Function App code:

1. Update the `convert_to_kql()` function in `QueryProcessor/__init__.py`
2. Add new KQL queries for additional metrics
3. Update Azure Copilot Studio topics to handle new query types

### Integration with Teams

Configure Microsoft Teams integration:

1. Enable Teams channel in Azure Copilot Studio
2. Configure webhook endpoints for Teams notifications
3. Add proactive messaging capabilities for alerts

### Enhanced Security

Implement additional security measures:

1. Configure Azure Key Vault for secrets management
2. Enable Azure Active Directory authentication
3. Implement network security groups and private endpoints

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service health status
3. Consult Azure Functions and Azure Monitor documentation
4. Verify Azure Copilot Studio configuration in Power Platform

## Contributing

When updating this infrastructure code:

1. Test all deployment methods
2. Update documentation for any new parameters
3. Verify security configurations
4. Update cost estimates if needed