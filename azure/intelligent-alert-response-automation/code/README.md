# Infrastructure as Code for Intelligent Alert Response Automation with Monitor Workbooks and Azure Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Alert Response Automation with Monitor Workbooks and Azure Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.57.0 or later installed and configured
- Azure account with appropriate permissions for creating:
  - Azure Monitor resources
  - Azure Functions
  - Event Grid topics
  - Logic Apps
  - Cosmos DB
  - Key Vault
  - Storage accounts
  - Log Analytics workspaces
- Basic understanding of Azure monitoring concepts, serverless functions, and event-driven architectures
- Familiarity with KQL (Kusto Query Language) for log analytics and workbook queries
- Estimated cost: $15-30 per month for development/testing (varies by region and usage patterns)

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the bicep directory
cd bicep/

# Set required parameters
export LOCATION="eastus"
export RESOURCE_GROUP_NAME="rg-intelligent-alerts-$(openssl rand -hex 3)"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP_NAME} \
    --location ${LOCATION}

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --template-file main.bicep \
    --parameters @parameters.json \
    --parameters location=${LOCATION}
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# When ready to cleanup
./scripts/destroy.sh
```

## Architecture Overview

This solution deploys an intelligent alert response system that includes:

- **Azure Monitor Workbooks**: Interactive dashboards for alert visualization
- **Azure Functions**: Serverless alert processing and automated responses
- **Event Grid**: Event-driven orchestration for alert routing
- **Logic Apps**: Workflow orchestration for notifications and approvals
- **Cosmos DB**: State management for alert tracking and analytics
- **Key Vault**: Secure storage for configuration and secrets
- **Storage Account**: Backend storage for Function Apps
- **Log Analytics**: Centralized logging and monitoring

## Configuration

### Bicep Parameters

The Bicep deployment uses parameters defined in `parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourcePrefix": {
      "value": "intelligent-alerts"
    },
    "environment": {
      "value": "demo"
    },
    "enableMonitoring": {
      "value": true
    },
    "cosmosDbThroughput": {
      "value": 400
    }
  }
}
```

### Terraform Variables

Key variables in `terraform/variables.tf`:

- `location`: Azure region for resource deployment
- `resource_group_name`: Name of the resource group
- `environment`: Environment tag (dev, staging, prod)
- `enable_monitoring`: Enable Application Insights monitoring
- `cosmos_db_throughput`: Cosmos DB provisioned throughput

### Environment Variables

Set these environment variables before deployment:

```bash
export LOCATION="eastus"
export RESOURCE_GROUP_NAME="rg-intelligent-alerts-$(openssl rand -hex 3)"
export ENVIRONMENT="demo"
export ENABLE_MONITORING="true"
```

## Deployment Process

### Phase 1: Foundation Resources
1. Resource Group creation
2. Storage Account for Function Apps
3. Key Vault for secure configuration
4. Log Analytics workspace

### Phase 2: Data Services
1. Cosmos DB for alert state management
2. Event Grid topic for event orchestration

### Phase 3: Compute Services
1. Azure Functions for alert processing
2. Logic Apps for notification workflows

### Phase 4: Monitoring & Visualization
1. Azure Monitor Workbooks for dashboards
2. Application Insights for monitoring
3. Alert rules for testing

## Post-Deployment Configuration

After infrastructure deployment, complete these steps:

1. **Configure Function App Code**:
   ```bash
   # Deploy function code (handled by scripts)
   cd ../
   zip -r function-code.zip function-app/
   az functionapp deployment source config-zip \
       --name ${FUNCTION_APP_NAME} \
       --resource-group ${RESOURCE_GROUP_NAME} \
       --src function-code.zip
   ```

2. **Set up Event Grid Subscriptions**:
   ```bash
   # Create subscriptions for alert routing
   az eventgrid event-subscription create \
       --name "alerts-to-function" \
       --source-resource-id ${EVENT_GRID_TOPIC_ID} \
       --endpoint-type azurefunction \
       --endpoint ${FUNCTION_ENDPOINT}
   ```

3. **Configure Key Vault Secrets**:
   ```bash
   # Store connection strings securely
   az keyvault secret set \
       --vault-name ${KEY_VAULT_NAME} \
       --name "cosmos-connection" \
       --value ${COSMOS_CONNECTION_STRING}
   ```

## Testing & Validation

### Verify Deployment

```bash
# Check resource group contents
az resource list \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --output table

# Test Function App
az functionapp show \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --query "state" \
    --output tsv
```

### Test Alert Processing

```bash
# Send test event to Event Grid
az eventgrid event send \
    --topic-name ${EVENT_GRID_TOPIC} \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --events '[{
        "id": "test-alert-001",
        "eventType": "Microsoft.AlertManagement.Alert.Activated",
        "subject": "Test Alert",
        "eventTime": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "data": {
            "alertId": "test-alert-001",
            "severity": "high",
            "resourceId": "/test/resource",
            "alertContext": {"condition": "CPU > 80%"}
        }
    }]'
```

### Access Workbook Dashboard

1. Navigate to Azure Portal
2. Go to Azure Monitor > Workbooks
3. Find "Intelligent Alert Response Dashboard"
4. View alert patterns and system health metrics

## Monitoring & Troubleshooting

### Key Metrics to Monitor

- Function App execution success rate
- Event Grid delivery success rate
- Cosmos DB request units consumed
- Alert response time metrics

### Common Issues

1. **Function App Cold Start**: Enable Always On for production
2. **Event Grid Delivery Failures**: Check endpoint configuration
3. **Cosmos DB Throttling**: Increase provisioned throughput
4. **Key Vault Access**: Verify managed identity permissions

### Logs and Diagnostics

```bash
# Check Function App logs
az monitor app-insights events show \
    --app ${APP_INSIGHTS_NAME} \
    --event traces \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)

# Check Event Grid metrics
az monitor metrics list \
    --resource ${EVENT_GRID_TOPIC_ID} \
    --metric "PublishedEvents"
```

## Security Considerations

- All secrets stored in Key Vault with appropriate access policies
- Managed identities used for service-to-service authentication
- RBAC implemented for resource access control
- Network security groups configured for appropriate access
- Diagnostic logging enabled for all resources

## Cost Optimization

### Development/Testing
- Use consumption plan for Function Apps
- Set Cosmos DB to minimum throughput (400 RU/s)
- Use Basic tier for Log Analytics
- Enable auto-pause for development resources

### Production
- Consider dedicated App Service Plans for consistent performance
- Implement auto-scaling for Cosmos DB
- Use reserved capacity for predictable workloads
- Monitor costs with Azure Cost Management

## Cleanup

### Using Bicep
```bash
# Delete the resource group and all resources
az group delete \
    --name ${RESOURCE_GROUP_NAME} \
    --yes \
    --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Customization

### Extending the Solution

1. **Add ML-based Alert Prediction**: Integrate Azure Machine Learning for predictive analytics
2. **Multi-tenant Support**: Implement resource isolation for different teams
3. **Advanced Remediation**: Add Azure Automation runbooks for automated fixes
4. **External Integrations**: Connect to ServiceNow, Jira, or other ITSM tools
5. **Enhanced Dashboards**: Create custom workbooks for specific use cases

### Configuration Options

- Modify alert severity thresholds
- Customize notification templates
- Add new data sources to workbooks
- Implement custom remediation logic
- Configure additional event sources

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Azure service documentation
3. Verify resource permissions and configuration
4. Check deployment logs for error details
5. Validate network connectivity and security settings

## Additional Resources

- [Azure Monitor Workbooks Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Event Grid Documentation](https://docs.microsoft.com/en-us/azure/event-grid/)
- [Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Cosmos DB Documentation](https://docs.microsoft.com/en-us/azure/cosmos-db/)
- [Azure Key Vault Documentation](https://docs.microsoft.com/en-us/azure/key-vault/)