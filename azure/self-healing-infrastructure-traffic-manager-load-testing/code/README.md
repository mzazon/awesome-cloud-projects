# Infrastructure as Code for Self-Healing Infrastructure with Traffic Manager and Load Testing

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Self-Healing Infrastructure with Traffic Manager and Load Testing".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.15.0 or later installed and configured
- Azure subscription with Owner or Contributor access
- Appropriate permissions for resource creation across multiple regions
- Basic understanding of DNS routing and load balancing concepts
- Knowledge of Azure monitoring and alerting mechanisms

### Cost Estimation

- Estimated cost: $50-100/month for test infrastructure
- Costs vary based on:
  - Number of regions deployed
  - Web App service plans (B1 SKU)
  - Function App consumption
  - Traffic Manager queries
  - Load Testing execution time
  - Application Insights data ingestion

### Required Permissions

- Traffic Manager Contributor
- Web App Contributor
- Function App Contributor
- Load Test Contributor
- Monitor Contributor
- Application Insights Component Contributor

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Set deployment parameters
export RESOURCE_GROUP="rg-selfhealing-demo"
export LOCATION="eastus"
export DEPLOYMENT_NAME="selfhealing-$(date +%Y%m%d-%H%M%S)"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --template-file main.bicep \
    --parameters location=${LOCATION}

# Monitor deployment progress
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --query properties.provisioningState
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

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az network traffic-manager profile list \
    --resource-group rg-selfhealing-demo \
    --output table
```

## Architecture Overview

The infrastructure creates a self-healing system with the following components:

### Multi-Region Web Applications
- **East US**: Primary web application endpoint
- **West US**: Secondary web application endpoint  
- **West Europe**: Tertiary web application endpoint
- **App Service Plans**: B1 SKU Linux plans in each region

### Traffic Management
- **Traffic Manager Profile**: Performance-based routing with health monitoring
- **Endpoint Monitoring**: 30-second intervals with 3-failure threshold
- **DNS Configuration**: 30-second TTL for rapid failover

### Monitoring & Automation
- **Application Insights**: Centralized telemetry collection
- **Log Analytics Workspace**: Unified logging and analysis
- **Azure Functions**: Serverless automation for self-healing logic
- **Alert Rules**: Automated response to performance degradation

### Load Testing
- **Azure Load Testing**: Proactive performance validation
- **Synthetic Monitoring**: Continuous endpoint health validation
- **Performance Baselines**: Automated performance regression detection

## Configuration Options

### Bicep Parameters

```bicep
@description('Primary deployment region')
param location string = 'eastus'

@description('Environment suffix for resource naming')
param environmentSuffix string = 'demo'

@description('Traffic Manager monitoring interval in seconds')
param monitoringInterval int = 30

@description('Traffic Manager failure threshold')
param failureThreshold int = 3

@description('App Service plan SKU')
param appServicePlanSku string = 'B1'

@description('Enable Application Insights')
param enableApplicationInsights bool = true

@description('Enable automated load testing')
param enableLoadTesting bool = true
```

### Terraform Variables

```hcl
variable "location" {
  description = "Primary deployment region"
  type        = string
  default     = "East US"
}

variable "environment_suffix" {
  description = "Environment suffix for resource naming"
  type        = string
  default     = "demo"
}

variable "monitoring_interval" {
  description = "Traffic Manager monitoring interval in seconds"
  type        = number
  default     = 30
}

variable "failure_threshold" {
  description = "Traffic Manager failure threshold"
  type        = number
  default     = 3
}

variable "app_service_plan_sku" {
  description = "App Service plan SKU"
  type        = string
  default     = "B1"
}

variable "enable_application_insights" {
  description = "Enable Application Insights"
  type        = bool
  default     = true
}

variable "enable_load_testing" {
  description = "Enable automated load testing"
  type        = bool
  default     = true
}
```

## Deployment Validation

### Verify Traffic Manager Configuration

```bash
# Check Traffic Manager profile status
az network traffic-manager profile show \
    --name tm-selfhealing-demo \
    --resource-group rg-selfhealing-demo \
    --query '{status:profileStatus,dnsName:dnsConfig.fqdn}' \
    --output table

# Verify endpoint health
az network traffic-manager endpoint list \
    --profile-name tm-selfhealing-demo \
    --resource-group rg-selfhealing-demo \
    --type azureEndpoints \
    --query '[].{name:name,status:endpointStatus,monitorStatus:endpointMonitorStatus}' \
    --output table
```

### Test Self-Healing Function

```bash
# Get Function App URL
FUNCTION_URL=$(az functionapp function show \
    --function-name self-healing \
    --name func-monitor-demo \
    --resource-group rg-selfhealing-demo \
    --query invokeUrlTemplate \
    --output tsv)

# Test function response
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{"test": "validation"}'
```

### Validate Load Testing Resource

```bash
# Check Load Testing resource
az load test show \
    --name alt-selfhealing-demo \
    --resource-group rg-selfhealing-demo \
    --query '{name:name,location:location,provisioningState:provisioningState}' \
    --output table
```

## Testing the Self-Healing System

### Simulate Endpoint Failure

```bash
# Disable a web app to test failover
az webapp stop \
    --name webapp-east-demo \
    --resource-group rg-selfhealing-demo

# Monitor Traffic Manager response
az network traffic-manager endpoint show \
    --name east-endpoint \
    --profile-name tm-selfhealing-demo \
    --resource-group rg-selfhealing-demo \
    --type azureEndpoints \
    --query '{name:name,status:endpointStatus,monitorStatus:endpointMonitorStatus}'

# Restart the web app
az webapp start \
    --name webapp-east-demo \
    --resource-group rg-selfhealing-demo
```

### Monitor Alert Rules

```bash
# List configured alerts
az monitor metrics alert list \
    --resource-group rg-selfhealing-demo \
    --query '[].{name:name,enabled:enabled,condition:criteria.allOf[0].metricName}' \
    --output table

# Check alert rule firing history
az monitor metrics alert show \
    --name alert-response-time \
    --resource-group rg-selfhealing-demo \
    --query 'actions[0].actionGroupId'
```

## Monitoring and Observability

### Application Insights Queries

```kusto
# Query for response time trends
requests
| where timestamp > ago(1h)
| summarize avg(duration) by bin(timestamp, 5m), cloud_RoleName
| render timechart

# Query for availability metrics
requests
| where timestamp > ago(1h)
| summarize success_rate = avg(success) by bin(timestamp, 5m), cloud_RoleName
| render timechart
```

### Log Analytics Queries

```kusto
# Function App execution logs
FunctionAppLogs
| where TimeGenerated > ago(1h)
| where FunctionName == "self-healing"
| project TimeGenerated, Level, Message
| order by TimeGenerated desc

# Traffic Manager health check logs
AzureDiagnostics
| where Category == "TrafficManagerProbeHealthStatusEvents"
| where TimeGenerated > ago(1h)
| project TimeGenerated, Resource, ResultDescription
| order by TimeGenerated desc
```

## Security Considerations

### Network Security
- Web applications use HTTPS with TLS 1.2 minimum
- Traffic Manager endpoints configured with secure monitoring
- Function App uses system-assigned managed identity

### Access Control
- Least privilege RBAC assignments
- Function App permissions limited to Traffic Manager operations
- Application Insights data access restricted to authorized users

### Compliance
- All resources tagged for governance
- Audit logs enabled for all management operations
- Encryption at rest enabled for all supported services

## Troubleshooting

### Common Issues

1. **Traffic Manager endpoints showing as degraded**
   ```bash
   # Check web app health
   az webapp show \
       --name webapp-east-demo \
       --resource-group rg-selfhealing-demo \
       --query '{name:name,state:state,hostNames:defaultHostName}'
   
   # Review Traffic Manager monitoring configuration
   az network traffic-manager profile show \
       --name tm-selfhealing-demo \
       --resource-group rg-selfhealing-demo \
       --query 'monitorConfig'
   ```

2. **Function App not responding to alerts**
   ```bash
   # Check Function App logs
   az webapp log tail \
       --name func-monitor-demo \
       --resource-group rg-selfhealing-demo
   
   # Verify managed identity permissions
   az role assignment list \
       --assignee $(az functionapp identity show \
           --name func-monitor-demo \
           --resource-group rg-selfhealing-demo \
           --query principalId \
           --output tsv) \
       --output table
   ```

3. **Load Testing resource not accessible**
   ```bash
   # Check resource status
   az load test show \
       --name alt-selfhealing-demo \
       --resource-group rg-selfhealing-demo \
       --query '{name:name,provisioningState:provisioningState}'
   
   # Verify permissions
   az role assignment list \
       --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-selfhealing-demo/providers/Microsoft.LoadTestService/loadTests/alt-selfhealing-demo" \
       --output table
   ```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-selfhealing-demo \
    --yes \
    --no-wait

# Verify deletion
az group exists --name rg-selfhealing-demo
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual verification
az group list \
    --query "[?name=='rg-selfhealing-demo']" \
    --output table
```

### Manual Cleanup (if needed)

```bash
# Stop all web apps first
az webapp stop --name webapp-east-demo --resource-group rg-selfhealing-demo
az webapp stop --name webapp-west-demo --resource-group rg-selfhealing-demo
az webapp stop --name webapp-europe-demo --resource-group rg-selfhealing-demo

# Delete Traffic Manager profile
az network traffic-manager profile delete \
    --name tm-selfhealing-demo \
    --resource-group rg-selfhealing-demo

# Delete Load Testing resource
az load test delete \
    --name alt-selfhealing-demo \
    --resource-group rg-selfhealing-demo \
    --yes

# Delete Function App
az functionapp delete \
    --name func-monitor-demo \
    --resource-group rg-selfhealing-demo

# Delete resource group
az group delete \
    --name rg-selfhealing-demo \
    --yes
```

## Customization

### Adding Additional Regions

1. Update the Bicep template or Terraform configuration to include additional regions
2. Add corresponding web app and app service plan resources
3. Update Traffic Manager endpoint configuration
4. Modify monitoring alerts for new endpoints

### Implementing Custom Health Checks

1. Create custom health check endpoints in web applications
2. Update Traffic Manager monitoring path configuration
3. Implement business logic validation in health checks
4. Add custom metrics to Application Insights

### Extending Load Testing Scenarios

1. Create custom load testing scripts
2. Implement different testing scenarios (peak load, endurance)
3. Add automated test result analysis
4. Integrate with CI/CD pipelines for continuous testing

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation
3. Verify resource quotas and limits
4. Review Azure service health dashboard
5. Check subscription permissions and policies

## Performance Optimization

### Traffic Manager Optimization
- Adjust monitoring intervals based on application requirements
- Configure appropriate failure thresholds
- Use geographic routing for better performance in specific regions

### Application Performance
- Enable Application Insights profiling
- Implement custom performance counters
- Configure auto-scaling for App Service plans
- Optimize web application code for performance

### Cost Optimization
- Use Azure Cost Management for monitoring
- Implement auto-scaling to reduce costs during low usage
- Consider Azure Reserved Instances for predictable workloads
- Review and optimize monitoring data retention policies

## Advanced Features

### Disaster Recovery
- Implement database replication across regions
- Add storage account geo-replication
- Configure automated backup procedures
- Test disaster recovery scenarios regularly

### Security Enhancements
- Implement Azure Security Center recommendations
- Add Web Application Firewall (WAF)
- Configure Azure Key Vault for secrets management
- Enable Azure AD authentication for web applications

### Monitoring Enhancements
- Add custom dashboards in Azure Monitor
- Implement predictive analytics for capacity planning
- Configure notification channels (Teams, Slack, email)
- Add synthetic transactions for end-to-end monitoring