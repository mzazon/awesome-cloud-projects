# Infrastructure as Code for Microservices Observability with Service Fabric and Application Insights

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Microservices Observability with Service Fabric and Application Insights".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (declarative)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az --version` should show 2.40.0 or later)
- Azure subscription with appropriate permissions for:
  - Creating Service Fabric managed clusters
  - Creating Application Insights and Log Analytics workspaces
  - Creating Azure Functions and Event Hubs
  - Creating monitoring dashboards and alerts
- Basic understanding of microservices architecture and distributed systems
- Familiarity with Azure Service Fabric and Application Insights concepts

## Estimated Costs

- **Development/Testing**: $50-100 per day
- **Production**: Varies based on cluster size and throughput requirements

## Quick Start

### Using Bicep

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-microservices-monitoring" \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment progress
az deployment group show \
    --resource-group "rg-microservices-monitoring" \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts and monitor progress
```

## Architecture Overview

This solution implements comprehensive distributed monitoring by creating:

- **Service Fabric Managed Cluster**: Hosts microservices with built-in monitoring
- **Application Insights**: Provides telemetry collection and distributed tracing
- **Log Analytics Workspace**: Stores and analyzes monitoring data
- **Event Hub**: Handles real-time event streaming from microservices
- **Azure Functions**: Processes events and provides intelligent monitoring
- **Azure Monitor**: Unified monitoring platform with dashboards and alerts

## Configuration

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "clusterName": {
      "value": "sf-cluster-demo"
    },
    "adminUsername": {
      "value": "azureuser"
    },
    "adminPassword": {
      "value": "ComplexPassword123!"
    },
    "enableAutoScale": {
      "value": true
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
location = "eastus"
resource_group_name = "rg-microservices-monitoring"
cluster_name = "sf-cluster-demo"
admin_username = "azureuser"
admin_password = "ComplexPassword123!"
enable_auto_scale = true
tags = {
  Environment = "demo"
  Purpose = "microservices-monitoring"
}
```

### Bash Script Environment Variables

The deployment script uses these environment variables (automatically generated):

```bash
RESOURCE_GROUP="rg-microservices-monitoring-${RANDOM_SUFFIX}"
LOCATION="eastus"
SF_CLUSTER_NAME="sf-cluster-${RANDOM_SUFFIX}"
APP_INSIGHTS_NAME="ai-monitoring-${RANDOM_SUFFIX}"
FUNCTION_APP_NAME="fn-eventprocessor-${RANDOM_SUFFIX}"
EVENT_HUB_NAMESPACE="eh-namespace-${RANDOM_SUFFIX}"
```

## Validation

After deployment, verify the infrastructure:

### Check Service Fabric Cluster

```bash
# Verify cluster status
az sf managed-cluster show \
    --resource-group "rg-microservices-monitoring" \
    --cluster-name "sf-cluster-demo" \
    --query '{name:name,state:clusterState,health:healthState}' \
    --output table
```

### Test Application Insights

```bash
# Query telemetry data
az monitor app-insights query \
    --app "ai-monitoring-demo" \
    --resource-group "rg-microservices-monitoring" \
    --analytics-query "union traces, requests | where timestamp > ago(1h) | summarize count() by itemType" \
    --output table
```

### Verify Event Hub

```bash
# Check Event Hub metrics
az monitor metrics list \
    --resource "eh-namespace-demo" \
    --resource-group "rg-microservices-monitoring" \
    --resource-type Microsoft.EventHub/namespaces \
    --metric IncomingMessages \
    --interval 1m \
    --output table
```

## Monitoring Features

### Distributed Tracing

- **W3C Trace Context**: Standards-compliant request correlation
- **Service Map**: Visual representation of service dependencies
- **End-to-End Tracing**: Request flows across all microservices
- **Performance Insights**: Latency and throughput metrics

### Real-Time Monitoring

- **Live Metrics Stream**: Real-time performance monitoring
- **Custom Dashboards**: Service health and KPI visualization
- **Automated Alerts**: Proactive issue detection
- **Health Checks**: Comprehensive service health monitoring

### Event Processing

- **Serverless Functions**: Intelligent event processing
- **Stream Analytics**: Real-time data correlation
- **Anomaly Detection**: Machine learning-based issue detection
- **Automated Remediation**: Configurable response workflows

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name "rg-microservices-monitoring" \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Troubleshooting

### Common Issues

1. **Service Fabric Cluster Creation Timeout**
   - Cluster creation can take 20-30 minutes
   - Check Azure portal for detailed deployment status
   - Verify sufficient quota for VM cores in the region

2. **Application Insights Data Delay**
   - Telemetry data may take 2-3 minutes to appear
   - Check instrumentation key configuration
   - Verify network connectivity from services

3. **Event Hub Connection Issues**
   - Verify connection string format
   - Check Event Hub namespace permissions
   - Ensure proper firewall configuration

4. **Function App Deployment Failures**
   - Verify storage account accessibility
   - Check Application Insights configuration
   - Review function app logs for errors

### Debugging Commands

```bash
# Check resource group status
az group show --name "rg-microservices-monitoring" --query properties.provisioningState

# View deployment logs
az deployment group list \
    --resource-group "rg-microservices-monitoring" \
    --query "[].{name:name,state:properties.provisioningState,timestamp:properties.timestamp}" \
    --output table

# Check Function App logs
az functionapp log tail \
    --name "fn-eventprocessor-demo" \
    --resource-group "rg-microservices-monitoring"
```

## Security Considerations

### Best Practices Implemented

- **Managed Identity**: Service-to-service authentication without credentials
- **Network Security**: Private endpoints for sensitive resources
- **Encryption**: Data encryption at rest and in transit
- **Access Control**: Role-based access control (RBAC)
- **Monitoring**: Comprehensive audit logging

### Security Recommendations

1. **Use Azure Key Vault** for storing sensitive configuration
2. **Enable Azure AD integration** for Service Fabric cluster access
3. **Configure network security groups** to restrict traffic
4. **Enable diagnostic settings** for all resources
5. **Regular security reviews** of access permissions

## Performance Optimization

### Service Fabric Cluster

- **Node Types**: Use appropriate VM sizes for workload requirements
- **Scaling**: Configure auto-scaling based on resource utilization
- **Placement Constraints**: Optimize service placement for performance
- **Resource Governance**: Set resource limits for services

### Application Insights

- **Sampling**: Configure appropriate sampling rates to balance cost and visibility
- **Custom Metrics**: Implement business-specific KPIs
- **Continuous Export**: Set up data export for long-term analysis
- **Retention**: Configure appropriate data retention policies

### Event Processing

- **Throughput Units**: Scale Event Hub based on message volume
- **Partitioning**: Optimize partition count for parallel processing
- **Consumer Groups**: Use multiple consumer groups for different processing scenarios
- **Batch Processing**: Configure appropriate batch sizes for efficiency

## Extensions and Customization

### Adding Custom Metrics

```bash
# Example: Add custom telemetry to microservices
# Include in service code:
TelemetryClient.TrackMetric("CustomBusinessMetric", value);
TelemetryClient.TrackEvent("CustomBusinessEvent", properties);
```

### Custom Alerts

```bash
# Create custom alert rule
az monitor metrics alert create \
    --name "Custom Service Alert" \
    --resource-group "rg-microservices-monitoring" \
    --scopes "/subscriptions/{subscription-id}/resourceGroups/rg-microservices-monitoring/providers/Microsoft.Insights/components/ai-monitoring-demo" \
    --condition "avg customMetrics/CustomBusinessMetric > 100" \
    --description "Alert when custom metric exceeds threshold"
```

### Dashboard Customization

- **Azure Portal**: Create custom dashboards with KPI widgets
- **Power BI**: Connect to Application Insights for advanced analytics
- **Grafana**: Use Azure Monitor data source for custom visualizations
- **API Integration**: Build custom monitoring applications

## Support and Resources

### Documentation Links

- [Azure Service Fabric Documentation](https://docs.microsoft.com/en-us/azure/service-fabric/)
- [Application Insights Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)
- [Event Hubs Documentation](https://docs.microsoft.com/en-us/azure/event-hubs/)

### Community Resources

- [Azure Service Fabric GitHub](https://github.com/Azure/service-fabric)
- [Application Insights SDK](https://github.com/Microsoft/ApplicationInsights-dotnet)
- [Azure Monitor Community](https://techcommunity.microsoft.com/t5/azure-monitor/bd-p/AzureMonitor)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Azure documentation for specific services
4. Contact Azure support for service-specific issues

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Modify as needed for your specific requirements.