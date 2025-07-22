# Infrastructure as Code for Proactive Cost Anomaly Detection with Serverless Analytics

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Proactive Cost Anomaly Detection with Serverless Analytics".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.60.0 or later installed and configured
- Azure subscription with Owner or Contributor permissions
- Basic knowledge of Azure Cost Management and billing concepts
- Understanding of serverless computing patterns and Azure Functions
- Familiarity with Azure Logic Apps and workflow automation
- Estimated cost: $15-30 per month for moderate usage (Function Apps, Cosmos DB, Storage)

> **Note**: This solution requires access to Azure Cost Management billing APIs. Ensure your account has the necessary permissions to access billing data for the target subscriptions.

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to the bicep directory
cd bicep/

# Review and customize parameters
vi parameters.json

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-cost-anomaly-detection \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This solution deploys the following Azure resources:

- **Azure Functions App**: Serverless compute for cost data processing and anomaly detection
- **Azure Storage Account**: Storage for function app and temporary data
- **Azure Cosmos DB**: NoSQL database for storing cost data and anomaly results
- **Azure Logic Apps**: Workflow automation for alerting and notifications
- **Azure Monitor**: Monitoring and logging for the solution
- **Managed Identity**: Secure authentication between services

## Configuration

### Bicep Parameters

The Bicep implementation supports the following parameters (defined in `parameters.json`):

- `resourceGroupName`: Name of the resource group
- `location`: Azure region for deployment
- `functionAppName`: Name of the Azure Functions app
- `storageAccountName`: Name of the storage account
- `cosmosAccountName`: Name of the Cosmos DB account
- `logicAppName`: Name of the Logic App
- `anomalyThreshold`: Percentage threshold for anomaly detection (default: 20)
- `lookbackDays`: Number of days to look back for baseline calculation (default: 30)

### Terraform Variables

The Terraform implementation supports the following variables (defined in `variables.tf`):

- `resource_group_name`: Name of the resource group
- `location`: Azure region for deployment
- `function_app_name`: Name of the Azure Functions app
- `storage_account_name`: Name of the storage account
- `cosmos_account_name`: Name of the Cosmos DB account
- `logic_app_name`: Name of the Logic App
- `anomaly_threshold`: Percentage threshold for anomaly detection
- `lookback_days`: Number of days to look back for baseline calculation

## Deployment Steps

### Pre-deployment

1. **Create Resource Group**:
   ```bash
   az group create \
       --name rg-cost-anomaly-detection \
       --location eastus
   ```

2. **Set Environment Variables**:
   ```bash
   export RESOURCE_GROUP="rg-cost-anomaly-detection"
   export LOCATION="eastus"
   export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
   ```

### Post-deployment

1. **Deploy Function Code**:
   ```bash
   # The function code needs to be deployed separately
   # Follow the function deployment steps in the main recipe
   ```

2. **Configure Permissions**:
   ```bash
   # Assign necessary role permissions
   # This is handled automatically by the IaC templates
   ```

3. **Test the Solution**:
   ```bash
   # Verify function app deployment
   az functionapp show \
       --name <function-app-name> \
       --resource-group ${RESOURCE_GROUP}
   ```

## Monitoring and Alerts

The solution includes built-in monitoring through:

- **Azure Monitor**: Application and infrastructure monitoring
- **Function App Insights**: Detailed function execution metrics
- **Cosmos DB Metrics**: Database performance and usage metrics
- **Custom Alerts**: Cost anomaly notifications through Logic Apps

## Security Features

- **Managed Identity**: Secure authentication between Azure services
- **RBAC**: Role-based access control for Cost Management APIs
- **Key Vault Integration**: Secure storage of connection strings and secrets
- **Network Security**: Private endpoints for sensitive resources (optional)

## Customization

### Anomaly Detection Tuning

Adjust the following parameters to fine-tune anomaly detection:

- `anomalyThreshold`: Lower values increase sensitivity
- `lookbackDays`: More days provide better baseline but slower adaptation
- Severity levels: Customize high/medium/low thresholds

### Notification Channels

Extend the Logic App to support additional notification channels:

- Microsoft Teams webhooks
- Slack integration
- SMS notifications
- Custom webhook endpoints

### Cost Analysis Enhancements

Modify the functions to include:

- Multi-subscription support
- Resource-level cost analysis
- Trend analysis and forecasting
- Custom cost allocation logic

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-cost-anomaly-detection \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Function App Deployment Failures**:
   - Verify storage account is accessible
   - Check function app naming constraints
   - Ensure proper permissions for managed identity

2. **Cosmos DB Connection Issues**:
   - Verify connection string configuration
   - Check firewall settings
   - Validate role assignments

3. **Cost Management API Access**:
   - Verify subscription permissions
   - Check API quota limits
   - Ensure proper role assignments

### Debug Commands

```bash
# Check function app logs
az functionapp logs tail \
    --name <function-app-name> \
    --resource-group ${RESOURCE_GROUP}

# Verify Cosmos DB connectivity
az cosmosdb show \
    --name <cosmos-account-name> \
    --resource-group ${RESOURCE_GROUP}

# Test Cost Management API access
az consumption usage list \
    --top 5
```

## Performance Optimization

### Function App Optimization

- Use consumption plan for cost efficiency
- Configure function timeout appropriately
- Implement proper error handling and retries
- Use Application Insights for performance monitoring

### Cosmos DB Optimization

- Configure appropriate request units (RU/s)
- Use efficient partition key strategies
- Implement proper indexing policies
- Monitor and optimize query performance

### Cost Management API Optimization

- Implement proper API rate limiting
- Use efficient query patterns
- Cache results when appropriate
- Minimize API calls through batching

## Compliance and Governance

### Security Compliance

- All resources use managed identities
- Network access is restricted where possible
- Audit logging is enabled
- Encryption at rest and in transit

### Cost Governance

- Resource tagging for cost allocation
- Budget alerts and controls
- Regular cost review and optimization
- Automated resource lifecycle management

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation
3. Verify permissions and configuration
4. Review Azure Monitor logs and Application Insights
5. Consult Azure Cost Management documentation

## Version Information

- **Recipe Version**: 1.0
- **IaC Generator Version**: 1.3
- **Last Updated**: 2025-07-12
- **Azure CLI Version**: 2.60.0+
- **Terraform Version**: 1.5.0+
- **Bicep Version**: 0.20.0+

## Additional Resources

- [Azure Cost Management Documentation](https://docs.microsoft.com/en-us/azure/cost-management-billing/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Cosmos DB Documentation](https://docs.microsoft.com/en-us/azure/cosmos-db/)
- [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)