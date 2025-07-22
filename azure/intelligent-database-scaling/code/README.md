# Infrastructure as Code for Intelligent Database Scaling with SQL Hyperscale and Logic Apps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Database Scaling with SQL Hyperscale and Logic Apps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az --version` should show 2.60.0 or later)
- Azure subscription with Contributor access
- PowerShell 7+ (for Bicep) or Bash (for scripts)
- Terraform 1.0+ (if using Terraform implementation)
- Understanding of Azure SQL Database Hyperscale pricing model
- Estimated cost: $50-100 per month for development/testing

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-intelligent-scaling \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json

# Monitor deployment status
az deployment group show \
    --resource-group rg-intelligent-scaling \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan -var-file="terraform.tfvars"

# Apply the configuration
terraform apply -var-file="terraform.tfvars"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy all resources
./scripts/deploy.sh

# Verify deployment
az sql db show \
    --resource-group rg-intelligent-scaling \
    --server sql-hyperscale-* \
    --name hyperscale-db \
    --query "{Name:name, Edition:edition, Status:status}"
```

## Architecture Overview

This solution deploys:

- **Azure SQL Database Hyperscale**: Elastic compute and storage scaling
- **Azure Logic Apps**: Serverless workflow orchestration for scaling logic
- **Azure Monitor**: Performance monitoring and alerting
- **Azure Key Vault**: Secure credential and configuration management
- **Log Analytics Workspace**: Centralized logging and analytics

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "location": "eastus",
  "environmentName": "dev",
  "sqlAdminUsername": "sqladmin",
  "sqlAdminPassword": "SecureP@ssw0rd123!",
  "hyperscaleServiceObjective": "HS_Gen5_2",
  "scalingThresholds": {
    "cpuScaleUpThreshold": 80,
    "cpuScaleDownThreshold": 30,
    "maxVCores": 40,
    "minVCores": 2
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars`:

```hcl
location = "East US"
environment = "dev"
sql_admin_username = "sqladmin"
sql_admin_password = "SecureP@ssw0rd123!"
hyperscale_service_objective = "HS_Gen5_2"
cpu_scale_up_threshold = 80
cpu_scale_down_threshold = 30
max_vcores = 40
min_vcores = 2
```

### Bash Script Environment Variables

Modify variables in `scripts/deploy.sh`:

```bash
export RESOURCE_GROUP="rg-intelligent-scaling"
export LOCATION="eastus"
export SQL_ADMIN_USERNAME="sqladmin"
export SQL_ADMIN_PASSWORD="SecureP@ssw0rd123!"
export HYPERSCALE_SERVICE_OBJECTIVE="HS_Gen5_2"
```

## Deployment Details

### Resource Naming Convention

All resources follow the pattern: `{resource-type}-{solution-name}-{random-suffix}`

- SQL Server: `sql-hyperscale-{suffix}`
- Database: `hyperscale-db`
- Logic App: `scaling-logic-app-{suffix}`
- Key Vault: `kv-scaling-{suffix}`
- Log Analytics: `la-scaling-{suffix}`

### Security Configuration

- **Key Vault**: RBAC-enabled with managed identity access
- **SQL Database**: Azure AD authentication configured
- **Logic Apps**: System-assigned managed identity
- **Network Security**: Firewall rules for Azure services only

### Monitoring Setup

- **CPU Scale-Up Alert**: Triggers when CPU > 80% for 5 minutes
- **CPU Scale-Down Alert**: Triggers when CPU < 30% for 15 minutes
- **Custom Metrics**: Database scaling operations logged to Log Analytics
- **Action Groups**: Webhook integration with Logic Apps

## Validation & Testing

### Verify Deployment

```bash
# Check database configuration
az sql db show \
    --resource-group rg-intelligent-scaling \
    --server sql-hyperscale-* \
    --name hyperscale-db \
    --query "{Edition:edition, ServiceObjective:currentServiceObjectiveName, Status:status}"

# Verify Logic Apps workflow
az logic workflow show \
    --resource-group rg-intelligent-scaling \
    --name scaling-logic-app-* \
    --query "{Name:name, State:state, Location:location}"

# Check monitoring alerts
az monitor metrics alert list \
    --resource-group rg-intelligent-scaling \
    --query "[].{Name:name, Enabled:enabled, Condition:criteria.allOf[0].threshold}"
```

### Test Scaling Operations

```bash
# Get Logic Apps trigger URL
TRIGGER_URL=$(az logic workflow trigger list-callback-url \
    --resource-group rg-intelligent-scaling \
    --name scaling-logic-app-* \
    --trigger-name "When_a_HTTP_request_is_received" \
    --query value --output tsv)

# Test scale-up trigger
curl -X POST "${TRIGGER_URL}" \
    -H "Content-Type: application/json" \
    -d '{
      "alertType": "CPU-Scale-Up-Alert",
      "resourceId": "/subscriptions/.../databases/hyperscale-db",
      "metricValue": 85.5
    }'

# Check workflow run history
az logic workflow run list \
    --resource-group rg-intelligent-scaling \
    --name scaling-logic-app-* \
    --top 1 \
    --query "[0].{Status:status, StartTime:startTime}"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-intelligent-scaling \
    --yes \
    --no-wait

# Verify deletion
az group exists --name rg-intelligent-scaling
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var-file="terraform.tfvars"

# Confirm all resources are deleted
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manually verify cleanup if needed
az group list --query "[?name=='rg-intelligent-scaling']"
```

## Troubleshooting

### Common Issues

1. **SQL Database Creation Fails**
   - Verify subscription has sufficient quota for Hyperscale databases
   - Check region availability for Hyperscale service tier
   - Ensure SQL admin password meets complexity requirements

2. **Logic Apps Permissions Error**
   - Verify managed identity has been assigned appropriate roles
   - Check that RBAC role assignments have propagated (may take up to 10 minutes)
   - Validate Key Vault access policies

3. **Monitoring Alerts Not Triggering**
   - Verify webhook URL is correctly configured in Action Groups
   - Check that Logic Apps trigger URL is accessible
   - Confirm alert rule conditions match expected metrics

### Debug Commands

```bash
# Check resource group deployment status
az deployment group list \
    --resource-group rg-intelligent-scaling \
    --query "[].{Name:name, State:properties.provisioningState}"

# View Logic Apps workflow runs
az logic workflow run list \
    --resource-group rg-intelligent-scaling \
    --name scaling-logic-app-* \
    --query "[].{Status:status, Error:properties.error}"

# Check Key Vault access
az keyvault secret list \
    --vault-name kv-scaling-* \
    --query "[].{Name:name, Enabled:attributes.enabled}"
```

## Cost Optimization

### Monitoring Costs

- **SQL Database Hyperscale**: Primary cost driver based on vCores and storage
- **Logic Apps**: Consumption-based pricing per workflow execution
- **Azure Monitor**: Charges for data ingestion and retention
- **Key Vault**: Minimal cost for secret operations

### Cost Reduction Strategies

1. **Set Maximum vCore Limits**: Configure `maxVCores` to prevent runaway scaling
2. **Optimize Alert Thresholds**: Adjust CPU thresholds to reduce unnecessary scaling
3. **Use Reserved Capacity**: Consider reserved instances for predictable workloads
4. **Monitor Scaling Patterns**: Review Log Analytics data to optimize scaling logic

## Customization

### Extending Scaling Logic

The Logic Apps workflow can be enhanced with additional scaling criteria:

1. **Memory-Based Scaling**: Add memory utilization metrics
2. **Connection Count Scaling**: Scale based on active connections
3. **Query Performance**: Incorporate query duration and wait statistics
4. **Time-Based Scaling**: Implement scheduled scaling for predictable patterns

### Integration Options

- **Power BI**: Connect Log Analytics for scaling analytics dashboards
- **Azure Functions**: Replace Logic Apps with custom scaling algorithms
- **Service Bus**: Queue scaling operations for complex orchestration
- **Application Insights**: Integrate application performance metrics

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for detailed explanations
2. Check Azure SQL Database Hyperscale documentation for service-specific guidance
3. Consult Azure Logic Apps documentation for workflow troubleshooting
4. Refer to Azure Monitor documentation for alerting configuration

## Additional Resources

- [Azure SQL Database Hyperscale Documentation](https://docs.microsoft.com/azure/azure-sql/database/service-tier-hyperscale)
- [Azure Logic Apps Documentation](https://docs.microsoft.com/azure/logic-apps/)
- [Azure Monitor Metrics and Alerting](https://docs.microsoft.com/azure/azure-monitor/alerts/)
- [Azure Key Vault Security Best Practices](https://docs.microsoft.com/azure/key-vault/general/security-features)