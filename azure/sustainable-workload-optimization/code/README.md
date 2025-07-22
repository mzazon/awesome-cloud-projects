# Infrastructure as Code for Sustainable Workload Optimization for Carbon Reduction

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Sustainable Workload Optimization for Carbon Reduction".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM templates with simplified syntax)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI 2.50.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Resource group creation and management
  - Azure Automation account creation
  - Azure Monitor workspace creation
  - Role assignments (Carbon Optimization Reader, Contributor)
  - Azure Monitor workbook creation
- PowerShell 7.0 or later for runbook development
- Understanding of Azure resource management and monitoring concepts
- Terraform 1.5+ (for Terraform deployment)
- Bash shell environment (Linux, macOS, or Windows Subsystem for Linux)

## Architecture Overview

This solution creates an intelligent workload optimization system that:

- Leverages Azure Carbon Optimization for granular emissions tracking
- Uses Azure Advisor for AI-driven recommendations
- Implements Azure Monitor for comprehensive observability
- Provides Azure Automation for automated remediation
- Creates monitoring workbooks for visualization and reporting

## Quick Start

### Using Bicep

```bash
# Navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group your-resource-group \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment status
az deployment group list \
    --resource-group your-resource-group \
    --query "[0].properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
echo "Deployment completed. Check Azure portal for resources."
```

## Configuration

### Environment Variables

The following environment variables are used across implementations:

```bash
# Required variables
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_RESOURCE_GROUP="rg-carbon-optimization"
export AZURE_LOCATION="eastus"

# Optional customization
export AUTOMATION_ACCOUNT_NAME="aa-carbon-opt"
export WORKSPACE_NAME="law-carbon-opt"
export WORKBOOK_NAME="carbon-optimization-dashboard"
```

### Bicep Parameters

Customize the deployment by modifying `parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "automationAccountName": {
      "value": "aa-carbon-opt"
    },
    "workspaceName": {
      "value": "law-carbon-opt"
    },
    "enableAutomatedRemediation": {
      "value": true
    },
    "monitoringSchedule": {
      "value": "Daily"
    }
  }
}
```

### Terraform Variables

Customize the deployment by modifying `terraform.tfvars`:

```hcl
# Resource configuration
resource_group_name = "rg-carbon-optimization"
location           = "eastus"

# Automation configuration
automation_account_name = "aa-carbon-opt"
workspace_name         = "law-carbon-opt"
workbook_name         = "carbon-optimization-dashboard"

# Feature flags
enable_automated_remediation = true
enable_high_impact_alerts   = true

# Tags
tags = {
  purpose     = "sustainability"
  environment = "production"
  project     = "carbon-optimization"
}
```

## Post-Deployment Configuration

### 1. Verify Carbon Optimization Access

```bash
# Check Carbon Optimization Reader role assignment
az role assignment list \
    --assignee $(az ad signed-in-user show --query id --output tsv) \
    --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}" \
    --query "[?roleDefinitionName=='Carbon Optimization Reader']"
```

### 2. Test Automation Account

```bash
# Verify automation account status
az automation account show \
    --resource-group ${AZURE_RESOURCE_GROUP} \
    --name ${AUTOMATION_ACCOUNT_NAME} \
    --query "{name:name, identity:identity.type, state:state}"
```

### 3. Validate Monitoring Setup

```bash
# Check Log Analytics workspace
az monitor log-analytics workspace show \
    --resource-group ${AZURE_RESOURCE_GROUP} \
    --workspace-name ${WORKSPACE_NAME} \
    --query "{name:name, provisioningState:provisioningState}"

# Verify workbook deployment
az monitor workbook list \
    --resource-group ${AZURE_RESOURCE_GROUP} \
    --query "[?contains(name,'carbon-optimization')]"
```

### 4. Configure Alert Notifications

Update the email address in the action group:

```bash
# Update action group with your email
az monitor action-group update \
    --resource-group ${AZURE_RESOURCE_GROUP} \
    --name "CarbonOptimizationAlerts" \
    --add-action email "your-email@company.com"
```

## Monitoring and Operations

### Dashboard Access

Access the Carbon Optimization Dashboard:

1. Navigate to Azure Monitor in the Azure portal
2. Select "Workbooks" from the left menu
3. Find "Carbon Optimization Dashboard" in your resource group
4. Click to open the interactive dashboard

### Key Metrics

The solution tracks the following metrics:

- **Carbon Emissions**: Resource-level CO2 emissions data
- **Optimization Opportunities**: Count and impact of recommendations
- **Automated Actions**: Number of successful optimizations
- **Cost Savings**: Financial impact of carbon optimizations
- **Compliance Status**: Adherence to sustainability policies

### Runbook Operations

Monitor runbook execution:

```bash
# List recent automation jobs
az automation job list \
    --resource-group ${AZURE_RESOURCE_GROUP} \
    --automation-account-name ${AUTOMATION_ACCOUNT_NAME} \
    --query "[].{jobId:jobId, runbook:runbookName, status:status, startTime:startTime}"

# Get job output
az automation job output show \
    --resource-group ${AZURE_RESOURCE_GROUP} \
    --automation-account-name ${AUTOMATION_ACCOUNT_NAME} \
    --job-id "your-job-id"
```

## Troubleshooting

### Common Issues

1. **Carbon Optimization API Access Denied**
   - Ensure you have the "Carbon Optimization Reader" role
   - Verify the role is assigned at the subscription level

2. **Automation Account Identity Issues**
   - Check that the managed identity has proper permissions
   - Verify the identity is assigned at the subscription level

3. **Runbook Execution Failures**
   - Review job logs in the Azure portal
   - Check PowerShell module dependencies
   - Verify API endpoint availability

4. **Missing Monitoring Data**
   - Confirm Log Analytics workspace ingestion
   - Check custom log table creation
   - Verify data retention policies

### Diagnostic Commands

```bash
# Check resource deployment status
az deployment group show \
    --resource-group ${AZURE_RESOURCE_GROUP} \
    --name "sustainable-workload-optimization" \
    --query "properties.provisioningState"

# Verify role assignments
az role assignment list \
    --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}" \
    --query "[?contains(principalName, 'carbon') || contains(roleDefinitionName, 'Carbon')]"

# Test API connectivity
az rest --method GET \
    --url "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/providers/Microsoft.Sustainability/carbonEmissions?api-version=2023-11-01-preview"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name ${AZURE_RESOURCE_GROUP} \
    --yes \
    --no-wait

# Or delete individual resources
az deployment group delete \
    --resource-group ${AZURE_RESOURCE_GROUP} \
    --name "sustainable-workload-optimization"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify cleanup completed
az group show --name ${AZURE_RESOURCE_GROUP} --query "properties.provisioningState"
```

## Security Considerations

### Identity and Access Management

- The solution uses managed identities for secure authentication
- Follows least privilege principle for role assignments
- Carbon Optimization Reader role provides read-only access to emissions data
- Automation account permissions are scoped to necessary resources only

### Data Protection

- All data is encrypted at rest in Azure services
- Network traffic uses HTTPS/TLS encryption
- Log Analytics workspace access is controlled via Azure RBAC
- Sensitive configuration is stored in Azure Key Vault (if implemented)

### Compliance

- Supports audit logging for all optimization actions
- Maintains data residency requirements based on resource location
- Provides compliance reporting through Azure Monitor workbooks
- Follows Azure security baseline recommendations

## Cost Optimization

### Estimated Monthly Costs

- **Azure Automation**: $5-10 (based on job execution minutes)
- **Log Analytics Workspace**: $5-15 (based on data ingestion)
- **Azure Monitor Alerts**: $1-5 (based on alert rules)
- **Total Estimated**: $15-25 per month

### Cost Monitoring

```bash
# Monitor automation account costs
az consumption usage list \
    --start-date "2025-01-01" \
    --end-date "2025-01-31" \
    --include-meter-details \
    --query "[?contains(instanceName, 'automation')]"

# Check Log Analytics costs
az monitor log-analytics workspace get-shared-keys \
    --resource-group ${AZURE_RESOURCE_GROUP} \
    --workspace-name ${WORKSPACE_NAME}
```

## Performance Optimization

### Runbook Performance

- Optimize PowerShell scripts for faster execution
- Use parallel processing for bulk operations
- Implement caching for frequently accessed data
- Set appropriate timeout values for long-running tasks

### Monitoring Efficiency

- Configure appropriate log retention policies
- Use sampling for high-volume metrics
- Implement alert threshold tuning
- Schedule heavy operations during off-peak hours

## Extension Points

### Custom Optimization Logic

Add custom optimization rules by modifying the remediation runbook:

```powershell
# Example: Custom VM sizing logic
if ($recommendation.Category -eq "Performance") {
    # Implement custom performance optimization
    Write-Output "Applying custom performance optimization"
}
```

### Integration APIs

Extend the solution with external integrations:

- **ServiceNow**: Create tickets for manual optimization tasks
- **Slack**: Send notifications to team channels
- **Power BI**: Create executive sustainability dashboards
- **Third-party Tools**: Integrate with external carbon tracking systems

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation for specific components
3. Consult Azure support for service-specific issues
4. Use Azure Resource Health for service status updates

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Validate against the original recipe requirements
3. Ensure all IaC implementations remain synchronized
4. Update documentation for any configuration changes

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Ensure compliance with your organization's policies and Azure service terms before production use.