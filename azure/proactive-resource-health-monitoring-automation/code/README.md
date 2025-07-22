# Infrastructure as Code for Proactive Resource Health Monitoring with Service Bus

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Proactive Resource Health Monitoring with Service Bus".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or higher installed and configured (or Azure CloudShell)
- Azure subscription with appropriate permissions for:
  - Creating Service Bus namespaces
  - Creating Logic Apps
  - Creating Action Groups and Resource Health alerts
  - Creating Log Analytics workspaces
  - Creating Virtual Machines (for demonstration)
- Resource Contributor or Owner permissions on the target subscription
- Estimated cost: $50-100/month for Service Bus, Logic Apps, and monitoring resources

## Quick Start

### Using Bicep (Recommended)

1. **Deploy the infrastructure**:
   ```bash
   cd bicep/
   
   # Deploy with default parameters
   az deployment group create \
       --name health-monitoring-deployment \
       --resource-group <your-resource-group> \
       --template-file main.bicep
   
   # Or deploy with custom parameters
   az deployment group create \
       --name health-monitoring-deployment \
       --resource-group <your-resource-group> \
       --template-file main.bicep \
       --parameters @parameters.json
   ```

2. **Verify deployment**:
   ```bash
   # Check deployment status
   az deployment group show \
       --name health-monitoring-deployment \
       --resource-group <your-resource-group> \
       --query "properties.provisioningState"
   
   # List created resources
   az resource list \
       --resource-group <your-resource-group> \
       --output table
   ```

### Using Terraform

1. **Initialize and deploy**:
   ```bash
   cd terraform/
   
   # Initialize Terraform
   terraform init
   
   # Review planned changes
   terraform plan
   
   # Apply the configuration
   terraform apply
   ```

2. **Verify deployment**:
   ```bash
   # Show Terraform outputs
   terraform output
   
   # Check resource status
   terraform state list
   ```

### Using Bash Scripts

1. **Set environment variables**:
   ```bash
   export RESOURCE_GROUP="rg-health-monitoring-demo"
   export LOCATION="eastus"
   export RANDOM_SUFFIX=$(openssl rand -hex 3)
   ```

2. **Deploy infrastructure**:
   ```bash
   chmod +x scripts/deploy.sh
   ./scripts/deploy.sh
   ```

3. **Verify deployment**:
   ```bash
   # The deploy script includes validation steps
   # Check Service Bus namespace
   az servicebus namespace list \
       --resource-group ${RESOURCE_GROUP} \
       --output table
   
   # Check Logic Apps
   az logic workflow list \
       --resource-group ${RESOURCE_GROUP} \
       --output table
   ```

## Architecture Overview

This solution deploys:

- **Service Bus Namespace** with queues and topics for message processing
- **Logic Apps** for health event orchestration and remediation handling
- **Action Groups** for Resource Health alert notifications
- **Log Analytics Workspace** for monitoring and analytics
- **Resource Health Alerts** for proactive monitoring
- **Sample VM** for health monitoring demonstration

## Configuration Options

### Bicep Parameters

Customize your deployment by modifying `parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "serviceBusNamespace": {
      "value": "sb-health-monitoring-custom"
    },
    "logicAppName": {
      "value": "la-health-orchestrator-custom"
    },
    "createDemoVM": {
      "value": true
    }
  }
}
```

### Terraform Variables

Customize your deployment by creating a `terraform.tfvars` file:

```hcl
location            = "East US"
resource_group_name = "rg-health-monitoring-custom"
service_bus_sku     = "Standard"
create_demo_vm      = true
vm_size            = "Standard_B1s"

tags = {
  Environment = "Production"
  Project     = "HealthMonitoring"
  Owner       = "Platform Team"
}
```

### Script Environment Variables

The bash scripts support these environment variables:

```bash
export RESOURCE_GROUP="rg-health-monitoring-prod"
export LOCATION="westus2"
export SERVICE_BUS_SKU="Premium"  # Standard, Premium
export VM_SIZE="Standard_B2s"     # For demo VM
export ENABLE_DEMO_VM="true"      # true/false
```

## Testing the Solution

### 1. Verify Service Bus Messaging

```bash
# Check Service Bus namespace status
az servicebus namespace show \
    --name <service-bus-namespace> \
    --resource-group <resource-group> \
    --query "{Name:name,Status:status,Location:location}"

# Test message sending (requires Service Bus Explorer or custom application)
```

### 2. Test Logic Apps Workflow

```bash
# Get Logic Apps trigger URL
LOGIC_APP_URL=$(az logic workflow show \
    --name <logic-app-name> \
    --resource-group <resource-group> \
    --query "accessEndpoint" --output tsv)

# Send test health event
curl -X POST "${LOGIC_APP_URL}" \
    -H "Content-Type: application/json" \
    -d '{
      "resourceId": "/subscriptions/<subscription-id>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/test-vm",
      "status": "Unavailable",
      "eventTime": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'",
      "resourceType": "Microsoft.Compute/virtualMachines"
    }'
```

### 3. Monitor Health Events

```bash
# Query Log Analytics for health events
az monitor log-analytics query \
    --workspace <workspace-id> \
    --analytics-query "AzureActivity | where CategoryValue == 'ResourceHealth' | top 10 by TimeGenerated desc"
```

## Troubleshooting

### Common Issues

1. **Service Bus Connection Issues**:
   - Verify namespace is in "Active" state
   - Check connection string permissions
   - Ensure queues and topics are created

2. **Logic Apps Not Triggering**:
   - Verify Action Group webhook URL is correct
   - Check Logic Apps trigger configuration
   - Review Logic Apps run history for errors

3. **Resource Health Alerts Not Firing**:
   - Verify alert rules are enabled
   - Check target resource scope configuration
   - Ensure Action Group is properly configured

### Debugging Commands

```bash
# Check Logic Apps run history
az logic workflow run list \
    --workflow-name <logic-app-name> \
    --resource-group <resource-group>

# Monitor Service Bus metrics
az monitor metrics list \
    --resource <service-bus-resource-id> \
    --metric "Messages"

# View Action Group notifications
az monitor activity-log list \
    --resource-group <resource-group> \
    --caller "Microsoft.Insights"
```

## Cleanup

### Using Bicep

```bash
# Delete the deployment (this doesn't delete resources)
az deployment group delete \
    --name health-monitoring-deployment \
    --resource-group <resource-group>

# Delete the entire resource group
az group delete \
    --name <resource-group> \
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

## Security Considerations

- **Service Bus**: Uses managed identity where possible, connection strings are stored securely
- **Logic Apps**: Trigger URLs are protected, consider using managed identity for Service Bus connections
- **Resource Health**: Alerts are scoped to specific resources to prevent unauthorized access
- **VM Demo**: Created with minimal configuration, SSH keys are generated automatically

## Cost Optimization

- **Service Bus**: Standard tier is sufficient for most scenarios, consider Basic for development
- **Logic Apps**: Consumption plan scales to zero when not in use
- **Log Analytics**: Configure appropriate retention periods
- **VM Demo**: Use smallest size for demonstration, deallocate when not needed

## Monitoring and Maintenance

### Key Metrics to Monitor

- Service Bus message processing rates
- Logic Apps execution success rates
- Resource Health alert frequency
- System response times to health events

### Regular Maintenance Tasks

- Review and update Logic Apps workflows
- Monitor Service Bus performance and scaling
- Update Resource Health alert scopes as resources change
- Review Log Analytics queries and dashboards

## Additional Resources

- [Azure Service Bus Documentation](https://docs.microsoft.com/en-us/azure/service-bus-messaging/)
- [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Azure Resource Health Documentation](https://docs.microsoft.com/en-us/azure/service-health/resource-health-overview)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Azure documentation for specific services
4. Check Azure service health status

For questions about extending or customizing this solution, refer to the Challenge section in the original recipe.