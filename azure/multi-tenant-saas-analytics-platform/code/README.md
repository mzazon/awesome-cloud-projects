# Infrastructure as Code for Multi-Tenant SaaS Analytics and Cost Attribution Platform

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Tenant SaaS Analytics and Cost Attribution Platform".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Application Insights
  - Log Analytics Workspace
  - Azure Data Explorer
  - Cost Management
  - Resource Group management
- For Terraform: Terraform CLI v1.0 or later installed
- For Bicep: Bicep CLI installed (included with Azure CLI v2.20+)
- Basic understanding of multi-tenant SaaS architecture
- OpenSSL (for generating random suffixes in bash scripts)

## Architecture Overview

This solution implements a comprehensive multi-tenant SaaS analytics platform that combines:

- **Azure Application Insights** for application performance monitoring
- **Log Analytics Workspace** for centralized logging and data storage
- **Azure Data Explorer** for advanced analytics and real-time querying
- **Azure Cost Management** for cost attribution and budgeting
- **Custom telemetry enrichment** for tenant-specific monitoring

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters location=eastus \
                 environmentName=production \
                 tenantMonitoringEnabled=true

# Monitor deployment progress
az deployment group show \
    --resource-group <your-resource-group> \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="location=eastus" \
               -var="environment=production"

# Apply the infrastructure
terraform apply -var="location=eastus" \
                -var="environment=production"

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the script prompts for configuration
# The script will create all necessary resources with proper naming conventions
```

## Configuration Options

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `eastus` | Azure region for resource deployment |
| `environmentName` | string | `production` | Environment identifier for tagging |
| `tenantMonitoringEnabled` | bool | `true` | Enable tenant-specific monitoring features |
| `dataRetentionDays` | int | `90` | Log Analytics data retention period |
| `costBudgetAmount` | int | `200` | Monthly cost budget in USD |
| `adxSkuName` | string | `Standard_D11_v2` | Azure Data Explorer SKU |
| `adxSkuTier` | string | `Standard` | Azure Data Explorer tier |
| `adxCapacity` | int | `2` | Azure Data Explorer cluster capacity |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `location` | string | `eastus` | Azure region for resource deployment |
| `environment` | string | `production` | Environment identifier |
| `resource_group_name` | string | `null` | Resource group name (auto-generated if null) |
| `tenant_monitoring_enabled` | bool | `true` | Enable tenant-specific monitoring |
| `log_analytics_retention_days` | number | `90` | Log Analytics retention period |
| `cost_budget_amount` | number | `200` | Monthly cost budget in USD |
| `data_explorer_sku` | string | `Standard_D11_v2` | Azure Data Explorer SKU |
| `data_explorer_capacity` | number | `2` | Azure Data Explorer capacity |
| `tags` | map(string) | `{}` | Additional tags for resources |

### Bash Script Environment Variables

The deployment script accepts these environment variables:

```bash
export LOCATION="eastus"                    # Azure region
export ENVIRONMENT="production"             # Environment name
export TENANT_MONITORING_ENABLED="true"    # Enable tenant monitoring
export DATA_RETENTION_DAYS="90"            # Log Analytics retention
export COST_BUDGET_AMOUNT="200"            # Monthly budget in USD
export ADX_SKU="Standard_D11_v2"           # Data Explorer SKU
export ADX_CAPACITY="2"                    # Data Explorer capacity
```

## Post-Deployment Configuration

### Application Integration

After deploying the infrastructure, configure your SaaS application to send telemetry:

1. **Get Application Insights Connection String**:
   ```bash
   # Using Azure CLI
   az monitor app-insights component show \
       --resource-group <resource-group-name> \
       --app <app-insights-name> \
       --query connectionString --output tsv
   ```

2. **Configure Application Telemetry**:
   ```javascript
   // Example Node.js configuration
   const appInsights = require('applicationinsights');
   appInsights.setup('<CONNECTION_STRING>');
   
   // Add tenant context to all telemetry
   appInsights.defaultClient.addTelemetryProcessor((envelope) => {
       envelope.tags['ai.user.id'] = getTenantId();
       envelope.data.baseData.properties = envelope.data.baseData.properties || {};
       envelope.data.baseData.properties.tenantId = getTenantId();
       envelope.data.baseData.properties.costCenter = getCostCenter();
       return true;
   });
   ```

3. **Set up Custom Metrics**:
   ```javascript
   // Track tenant-specific metrics
   appInsights.defaultClient.trackMetric({
       name: 'TenantResourceUsage',
       value: resourceUsage,
       properties: {
           tenantId: getTenantId(),
           resourceType: 'compute'
       }
   });
   ```

### Analytics Queries

The solution includes pre-configured Kusto queries for common analytics scenarios:

1. **Tenant Performance Analysis**:
   ```kusto
   requests
   | where timestamp > ago(24h)
   | extend TenantId = tostring(customDimensions.tenantId)
   | summarize 
       RequestCount = count(),
       AvgDuration = avg(duration),
       P95Duration = percentile(duration, 95),
       FailureRate = countif(success == false) * 100.0 / count()
   by TenantId, bin(timestamp, 1h)
   | order by timestamp desc
   ```

2. **Cost Attribution Analysis**:
   ```kusto
   union 
   (requests | extend MetricType = "Performance"),
   (dependencies | extend MetricType = "Dependencies")
   | where timestamp > ago(7d)
   | extend TenantId = tostring(customDimensions.tenantId)
   | summarize 
       TotalOperations = count(),
       EstimatedCost = sum(itemCount * 0.001)
   by TenantId, MetricType, bin(timestamp, 1d)
   | order by EstimatedCost desc
   ```

## Monitoring and Alerting

### Cost Monitoring

The solution automatically configures:

- Monthly budget alerts at 80% and 100% thresholds
- Cost anomaly detection for unusual spending patterns
- Tenant-specific cost attribution tracking

### Performance Monitoring

Key performance indicators monitored include:

- Request duration percentiles (P50, P95, P99)
- Error rates and failure patterns
- Dependency performance and reliability
- Resource utilization patterns

### Custom Alerts

Create custom alerts for tenant-specific scenarios:

```bash
# Example: High error rate alert for specific tenant
az monitor metrics alert create \
    --name "HighErrorRateTenant" \
    --resource-group <resource-group-name> \
    --scopes <app-insights-resource-id> \
    --condition "count requests/failed > 10" \
    --description "Alert when tenant error rate exceeds threshold"
```

## Security Considerations

### Data Isolation

- Each tenant's data is tagged with tenant identifiers
- Row-level security can be implemented in Azure Data Explorer
- Access controls should be configured based on tenant requirements

### Access Control

- Use Azure Active Directory for authentication
- Implement role-based access control (RBAC)
- Consider managed identities for service-to-service authentication

### Compliance

- Configure data retention policies according to compliance requirements
- Enable audit logging for all analytics operations
- Implement data encryption at rest and in transit

## Troubleshooting

### Common Issues

1. **Data Explorer Connection Issues**:
   - Verify cluster is running and accessible
   - Check network security group rules
   - Validate authentication credentials

2. **Missing Telemetry Data**:
   - Confirm Application Insights instrumentation key is correct
   - Check sampling settings in Application Insights
   - Verify application is sending telemetry with tenant context

3. **Cost Attribution Issues**:
   - Ensure custom properties include tenant identifiers
   - Verify cost management permissions
   - Check budget alert configuration

### Diagnostic Commands

```bash
# Check Application Insights data ingestion
az monitor app-insights query \
    --resource-group <resource-group-name> \
    --app <app-insights-name> \
    --analytics-query "requests | top 10 by timestamp desc"

# Verify Data Explorer cluster status
az kusto cluster show \
    --cluster-name <cluster-name> \
    --resource-group <resource-group-name> \
    --query provisioningState

# Check cost budget status
az consumption budget show \
    --resource-group <resource-group-name> \
    --budget-name <budget-name>
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <resource-group-name> \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="location=eastus" \
                  -var="environment=production"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
# The script will remove resources in the correct order
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
az resource list \
    --resource-group <resource-group-name> \
    --output table

# Check for any remaining cost alerts
az monitor action-group list \
    --resource-group <resource-group-name> \
    --output table
```

## Cost Optimization

### Expected Costs

- **Log Analytics Workspace**: ~$2-10/GB ingested
- **Application Insights**: ~$2-5/GB ingested
- **Azure Data Explorer**: ~$100-300/month for Standard_D11_v2 cluster
- **Cost Management**: No additional charges for basic features

### Optimization Strategies

1. **Configure appropriate data retention periods**
2. **Use sampling for high-volume applications**
3. **Implement data archiving for historical analysis**
4. **Monitor and optimize query performance**
5. **Use auto-scaling for Data Explorer clusters**

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation:
   - [Application Insights](https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)
   - [Azure Data Explorer](https://docs.microsoft.com/en-us/azure/data-explorer/)
   - [Cost Management](https://docs.microsoft.com/en-us/azure/cost-management-billing/)
3. Consult provider-specific troubleshooting guides
4. Review Azure Monitor best practices

## Contributing

When modifying this infrastructure code:

1. Follow Azure naming conventions
2. Maintain compatibility with all IaC implementations
3. Update documentation for any new parameters
4. Test changes in a development environment
5. Validate security configurations

## License

This infrastructure code is provided as-is for educational and implementation purposes. Refer to your organization's policies for production deployments.