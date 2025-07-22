# Infrastructure as Code for Proactive Infrastructure Health Monitoring with Azure Service Health and Azure Update Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Proactive Infrastructure Health Monitoring with Azure Service Health and Azure Update Manager".

## Available Implementations

- **Bicep**: Microsoft's recommended domain-specific language for deploying Azure resources
- **Terraform**: Multi-cloud infrastructure as code using the Azure provider
- **Scripts**: Bash deployment and cleanup scripts for Azure CLI-based deployment

## Prerequisites

- Azure CLI v2.48.0 or later installed and configured
- Azure subscription with appropriate permissions
- Azure Resource Manager roles: Contributor or Owner for resource group management
- At least one Azure virtual machine for monitoring and patch management
- For Bicep: Azure CLI with Bicep extension installed
- For Terraform: Terraform v1.0+ and Azure CLI authentication configured

## Architecture Overview

This solution deploys:
- Azure Service Health alert rules for proactive incident monitoring
- Azure Update Manager policies for automated patch assessment
- Azure Logic Apps for intelligent correlation workflows
- Azure Monitor alert rules for patch compliance monitoring
- Azure Automation Account for automated remediation
- Log Analytics workspace for centralized monitoring
- Azure Workbook for comprehensive health dashboard

## Quick Start

### Using Bicep

```bash
# Navigate to the Bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-health-monitoring \
    --template-file main.bicep \
    --parameters adminEmail=admin@company.com \
    --parameters location=eastus

# Get deployment outputs
az deployment group show \
    --resource-group rg-health-monitoring \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="admin_email=admin@company.com" \
    -var="location=eastus"

# Apply the configuration
terraform apply -var="admin_email=admin@company.com" \
    -var="location=eastus"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export ADMIN_EMAIL="admin@company.com"
export LOCATION="eastus"

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
az group show --name rg-health-monitoring-* --output table
```

## Configuration Parameters

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `admin_email` | Email address for alert notifications | - | Yes |
| `location` | Azure region for resource deployment | `eastus` | No |
| `resource_group_name` | Name of the resource group | `rg-health-monitoring-{random}` | No |
| `environment` | Environment tag for resources | `production` | No |

### Bicep Parameters

```bicep
// Located in bicep/main.bicep
param adminEmail string
param location string = 'eastus'
param resourceGroupName string = 'rg-health-monitoring-${uniqueString(resourceGroup().id)}'
param environment string = 'production'
```

### Terraform Variables

```hcl
# Located in terraform/variables.tf
variable "admin_email" {
  description = "Email address for alert notifications"
  type        = string
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment tag for resources"
  type        = string
  default     = "production"
}
```

## Deployed Resources

The infrastructure deployment creates the following Azure resources:

### Core Monitoring Resources
- **Log Analytics Workspace**: Centralized logging and monitoring
- **Action Group**: Notification routing for alerts
- **Azure Monitor Alert Rules**: Service health and patch compliance monitoring

### Automation Resources
- **Azure Logic App**: Intelligent correlation workflows
- **Azure Automation Account**: Automated remediation capabilities
- **Maintenance Configuration**: Scheduled patch management

### Policy and Compliance
- **Azure Policy Assignment**: Update Manager assessment enablement
- **Azure Workbook**: Health monitoring dashboard

## Outputs

### Bicep Outputs

```bash
# View all outputs
az deployment group show \
    --resource-group rg-health-monitoring \
    --name main \
    --query properties.outputs

# Specific outputs include:
# - logAnalyticsWorkspaceId
# - logicAppTriggerUrl
# - automationAccountName
# - actionGroupName
# - workbookId
```

### Terraform Outputs

```bash
# View all outputs
terraform output

# Specific outputs include:
# - log_analytics_workspace_id
# - logic_app_trigger_url
# - automation_account_name
# - action_group_name
# - workbook_id
```

## Validation and Testing

### Verify Deployment

```bash
# Check Service Health alert rule
az monitor activity-log alert show \
    --name "Service Health Issues" \
    --resource-group rg-health-monitoring-*

# Verify Update Manager policy
az policy assignment show \
    --name "Enable-UpdateManager-Assessment" \
    --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-health-monitoring-*"

# Test Logic App endpoint
LOGIC_APP_URL=$(az logic workflow show \
    --name la-health-correlation-* \
    --resource-group rg-health-monitoring-* \
    --query accessEndpoint -o tsv)

curl -X POST "${LOGIC_APP_URL}" \
    -H "Content-Type: application/json" \
    -d '{"schemaId": "Microsoft.Insights/activityLogs", "data": {"status": "Active"}}'
```

### Monitor Health Dashboard

```bash
# Open Azure Workbook in browser
az monitor app-insights workbook show \
    --name "Health-Monitoring-Dashboard" \
    --resource-group rg-health-monitoring-* \
    --query id -o tsv | xargs -I {} az rest --method GET --url "https://portal.azure.com/#@{}/resource{}"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-health-monitoring-* \
    --yes \
    --no-wait

# Verify deletion
az group exists --name rg-health-monitoring-*
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="admin_email=admin@company.com" \
    -var="location=eastus"

# Verify state file is clean
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource group deletion
az group exists --name rg-health-monitoring-*
```

## Customization

### Adding Additional Alert Rules

Modify the templates to include additional monitoring scenarios:

```bicep
// Add to bicep/main.bicep
resource additionalAlert 'Microsoft.Insights/scheduledQueryRules@2021-08-01' = {
  name: 'Custom-Health-Alert'
  location: location
  properties: {
    description: 'Custom alert for specific health scenarios'
    severity: 2
    enabled: true
    // Additional configuration...
  }
}
```

### Extending Automation Workflows

Add custom remediation runbooks:

```hcl
# Add to terraform/main.tf
resource "azurerm_automation_runbook" "custom_remediation" {
  name                    = "Custom-Remediation-Runbook"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name
  runbook_type           = "PowerShell"
  
  content = file("${path.module}/runbooks/custom-remediation.ps1")
}
```

### Environment-Specific Configuration

Create separate parameter files for different environments:

```bash
# Development environment
terraform apply -var-file="environments/dev.tfvars"

# Production environment
terraform apply -var-file="environments/prod.tfvars"
```

## Security Considerations

### Access Control

The deployed infrastructure includes:
- **Least Privilege IAM**: Role assignments follow principle of least privilege
- **Managed Identity**: Logic Apps and Automation Account use managed identities
- **Network Security**: Resources are deployed with appropriate network configurations
- **Encryption**: All data at rest and in transit is encrypted using Azure-managed keys

### Security Best Practices

1. **Regular Security Reviews**: Periodically review and update IAM permissions
2. **Alert Monitoring**: Monitor alert configurations for potential security incidents
3. **Compliance Scanning**: Use Azure Security Center for compliance monitoring
4. **Audit Logging**: Enable diagnostic logging for all critical resources

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   ```bash
   # Check deployment logs
   az deployment group show \
       --resource-group rg-health-monitoring-* \
       --name main \
       --query properties.error
   ```

2. **Logic App Trigger Issues**:
   ```bash
   # Check Logic App run history
   az logic workflow run list \
       --name la-health-correlation-* \
       --resource-group rg-health-monitoring-* \
       --output table
   ```

3. **Policy Assignment Problems**:
   ```bash
   # Verify policy compliance
   az policy state list \
       --resource-group rg-health-monitoring-* \
       --output table
   ```

### Support Resources

- [Azure Service Health Documentation](https://docs.microsoft.com/en-us/azure/service-health/)
- [Azure Update Manager Documentation](https://docs.microsoft.com/en-us/azure/update-manager/)
- [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)

## Cost Optimization

### Resource Costs

Estimated monthly costs for this solution:
- **Logic Apps**: $10-30 (based on execution frequency)
- **Azure Monitor**: $20-50 (based on log ingestion and alert rules)
- **Automation Account**: $5-15 (based on runbook execution time)
- **Log Analytics**: $30-100 (based on data ingestion volume)

### Cost Management

1. **Right-sizing**: Adjust Log Analytics retention periods based on requirements
2. **Alert Optimization**: Fine-tune alert thresholds to reduce false positives
3. **Resource Scheduling**: Use automation to stop/start non-production resources
4. **Monitoring**: Set up cost alerts for unexpected spending

## Contributing

To contribute improvements to this infrastructure code:

1. Fork the repository
2. Create a feature branch
3. Make your changes following the coding standards
4. Test your changes thoroughly
5. Submit a pull request with detailed description

## License

This infrastructure code is provided under the same license as the parent recipe repository.

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult the Azure service documentation
4. Open an issue in the repository with detailed error information

---

*This README was generated for the Azure infrastructure health monitoring recipe. For the complete solution walkthrough, refer to the original recipe documentation.*