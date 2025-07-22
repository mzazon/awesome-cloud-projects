# Infrastructure as Code for Virtual Desktop Cost Optimization with Reserved Instances

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Virtual Desktop Cost Optimization with Reserved Instances".

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50+ installed and configured
- Azure subscription with Owner or Contributor permissions
- Understanding of Azure Virtual Desktop concepts and Reserved VM Instance pricing
- Basic knowledge of Azure Logic Apps and Cost Management APIs
- Estimated cost: $150-300 for testing environment

## Quick Start

### Using Bicep
```bash
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-avd-cost-optimization \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment progress
az deployment group show \
    --resource-group rg-avd-cost-optimization \
    --name main \
    --query properties.provisioningState
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy infrastructure
./deploy.sh

# Monitor deployment status
echo "Deployment completed. Check Azure portal for resource status."
```

## Architecture Overview

This solution deploys:

- **Azure Virtual Desktop**: Workspace and host pools with cost-optimized configuration
- **VM Scale Sets**: Auto-scaling compute resources with Reserved Instance optimization
- **Cost Management**: Budgets, alerts, and automated cost tracking
- **Logic Apps**: Automation for cost optimization workflows
- **Azure Functions**: Reserved Instance analysis and recommendations
- **Storage Account**: Cost reporting and analytics data storage
- **Monitoring**: Log Analytics workspace and performance monitoring

## Configuration

### Environment Variables

The following environment variables are used across all implementations:

```bash
export RESOURCE_GROUP="rg-avd-cost-optimization"
export LOCATION="eastus"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
export RANDOM_SUFFIX=$(openssl rand -hex 3)
```

### Bicep Parameters

Key parameters in `bicep/parameters.json`:

- `location`: Azure region for deployment
- `resourcePrefix`: Prefix for resource naming
- `vmSize`: VM SKU for cost optimization (default: Standard_D2s_v3)
- `maxSessionLimit`: Maximum sessions per VM (default: 10)
- `budgetAmount`: Monthly budget limit (default: 1000)
- `departmentTags`: Cost attribution tags for departments

### Terraform Variables

Key variables in `terraform/variables.tf`:

- `resource_group_name`: Resource group for all resources
- `location`: Azure region
- `vm_sku`: Virtual machine size for host pool
- `min_capacity`: Minimum VM instances for scale set
- `max_capacity`: Maximum VM instances for scale set
- `budget_threshold_actual`: Budget alert threshold for actual costs
- `budget_threshold_forecast`: Budget alert threshold for forecasted costs

## Post-Deployment Configuration

After infrastructure deployment, complete these manual steps:

1. **Configure AVD Host Pool Registration**:
   ```bash
   # Get registration token for host pool
   az desktopvirtualization hostpool retrieve-registration-token \
       --name hp-cost-optimized-${RANDOM_SUFFIX} \
       --resource-group ${RESOURCE_GROUP}
   ```

2. **Set Up Reserved Instance Analysis**:
   - Configure Cost Management API permissions for Function App
   - Deploy Reserved Instance analysis function code
   - Set up automated reporting schedules

3. **Enable Cost Attribution**:
   - Apply department-specific tags to user sessions
   - Configure cost center mapping in Azure Cost Management
   - Set up automated chargeback reports

4. **Configure Auto-Scaling Schedules**:
   - Create business hours scaling profiles
   - Set up weekend and holiday scaling rules
   - Configure emergency scaling thresholds

## Monitoring and Validation

### Verify Deployment
```bash
# Check AVD workspace status
az desktopvirtualization workspace show \
    --name avd-workspace-${RANDOM_SUFFIX} \
    --resource-group ${RESOURCE_GROUP} \
    --query "{Name:name, State:objectId}"

# Verify VM Scale Set configuration
az vmss show \
    --name vmss-avd-${RANDOM_SUFFIX} \
    --resource-group ${RESOURCE_GROUP} \
    --query "{Name:name, Capacity:sku.capacity, Tags:tags}"

# Check budget configuration
az consumption budget show \
    --budget-name budget-avd-${RANDOM_SUFFIX} \
    --resource-group ${RESOURCE_GROUP}
```

### Cost Monitoring
```bash
# View current month costs by tags
az consumption usage list \
    --start-date $(date -d "first day of this month" +%Y-%m-%d) \
    --end-date $(date +%Y-%m-%d) \
    --include-additional-properties \
    --output table

# Check auto-scaling metrics
az monitor metrics list \
    --resource vmss-avd-${RANDOM_SUFFIX} \
    --resource-group ${RESOURCE_GROUP} \
    --resource-type Microsoft.Compute/virtualMachineScaleSets \
    --metric "Percentage CPU"
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-avd-cost-optimization \
    --yes \
    --no-wait

# Or delete specific deployment
az deployment group delete \
    --resource-group rg-avd-cost-optimization \
    --name main
```

### Using Terraform
```bash
cd terraform/

# Destroy all infrastructure
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts
```bash
cd scripts/

# Run cleanup script
./destroy.sh

# Verify resource deletion
az group show --name rg-avd-cost-optimization --query id
```

## Cost Optimization Features

### Automated Cost Management
- **Budget Alerts**: Proactive notifications at 80% actual and 100% forecasted usage
- **Auto-Scaling**: Intelligent scaling based on CPU utilization (scale out >75%, scale in <25%)
- **Reserved Instance Analysis**: Automated recommendations for cost savings up to 72%
- **Department Attribution**: Granular cost tracking and chargeback capabilities

### Performance Optimization
- **Load Balancing**: Breadth-first distribution for optimal resource utilization
- **Session Limits**: Configurable maximum sessions per VM (default: 10)
- **Multi-Session VMs**: Cost-effective pooled desktop deployment
- **Monitoring**: Comprehensive performance and cost analytics

## Customization

### Scaling Configuration
Modify auto-scaling rules in the infrastructure code:

```bash
# Business hours profile (8 AM - 6 PM)
--min-count 2 --max-count 8 --count 4

# Off-hours profile (6 PM - 8 AM)
--min-count 1 --max-count 3 --count 1
```

### Cost Attribution Tags
Add custom department tags for precise cost tracking:

```json
{
  "department": "finance",
  "cost-center": "100",
  "project": "virtual-desktop",
  "environment": "production"
}
```

### Reserved Instance Strategy
Configure Reserved Instance purchasing based on usage patterns:

- **1-year terms**: For predictable baseline capacity
- **3-year terms**: For stable long-term workloads
- **Scope optimization**: Shared scope for flexible capacity allocation

## Troubleshooting

### Common Issues

1. **AVD Registration Failures**:
   - Verify host pool has valid registration token
   - Check VM network connectivity to Azure backbone
   - Validate Azure AD domain join configuration

2. **Auto-Scaling Not Triggering**:
   - Verify CPU metrics are being collected
   - Check auto-scaling rule thresholds and time windows
   - Ensure sufficient subscription quota for scaling

3. **Cost Attribution Missing**:
   - Verify resource tags are properly applied
   - Check Cost Management API permissions
   - Validate department tag format and values

4. **Function App Errors**:
   - Check Function App logs in Azure Portal
   - Verify Cost Management API access permissions
   - Validate storage account connection strings

### Support Resources

- [Azure Virtual Desktop Documentation](https://docs.microsoft.com/en-us/azure/virtual-desktop/)
- [Azure Cost Management Best Practices](https://docs.microsoft.com/en-us/azure/cost-management-billing/costs/cost-mgt-best-practices)
- [Azure Reserved VM Instances Pricing](https://azure.microsoft.com/en-us/pricing/reserved-vm-instances/)
- [Azure Auto-scaling Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/autoscale/)

## Security Considerations

- **Network Security**: VMs deployed in dedicated subnets with NSG protection
- **Identity Management**: Integration with Azure AD for user authentication
- **Data Encryption**: Encryption at rest and in transit for all storage
- **Access Control**: Role-based access control (RBAC) for administrative functions
- **Cost Security**: Budget alerts prevent runaway costs and resource abuse

For additional security hardening, refer to the [Azure Security Benchmark](https://docs.microsoft.com/en-us/security/benchmark/azure/) and [Azure Virtual Desktop security best practices](https://docs.microsoft.com/en-us/azure/virtual-desktop/security-guide).