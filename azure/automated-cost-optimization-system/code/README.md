# Infrastructure as Code for Automated Cost Optimization with Intelligent Monitoring

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Cost Optimization with Intelligent Monitoring".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.40.0 or later installed and configured
- Azure subscription with Contributor or Cost Management Contributor permissions
- PowerShell 7.0+ (for Bicep deployment) or Bash (for scripts)
- Basic understanding of Azure Cost Management and budgeting concepts
- Access to Azure Cost Management APIs and budget creation permissions

### Required Azure Permissions

- `Cost Management Contributor` - For creating budgets and cost exports
- `Logic App Contributor` - For deploying Logic Apps workflows
- `Storage Account Contributor` - For cost data storage
- `Monitoring Contributor` - For creating alerts and action groups

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the Bicep directory
cd bicep/

# Review and customize parameters
cp parameters.json.template parameters.json
# Edit parameters.json with your specific values

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts for configuration
```

## Architecture Overview

This IaC deployment creates:

- **Storage Account**: For cost data exports and analysis
- **Logic Apps**: Automated workflow for cost optimization
- **Log Analytics Workspace**: Cost monitoring and analytics
- **Budget**: Automated spending alerts and thresholds
- **Cost Export**: Daily cost data export configuration
- **Action Groups**: Alert notifications for cost thresholds
- **Service Principal**: Secure API access for automation
- **Monitor Alerts**: Cost anomaly detection and alerting

## Configuration Parameters

### Bicep Parameters

Key parameters in `parameters.json`:

```json
{
  "resourceGroupName": "rg-cost-optimization",
  "location": "eastus",
  "storageAccountName": "stcostopt",
  "logicAppName": "la-cost-optimization",
  "workspaceName": "law-cost-optimization",
  "budgetName": "budget-optimization",
  "budgetAmount": 1000,
  "teamsWebhookUrl": "https://outlook.office.com/webhook/YOUR_WEBHOOK_URL"
}
```

### Terraform Variables

Key variables in `terraform.tfvars`:

```hcl
resource_group_name = "rg-cost-optimization"
location           = "East US"
budget_amount      = 1000
teams_webhook_url  = "https://outlook.office.com/webhook/YOUR_WEBHOOK_URL"
```

## Post-Deployment Configuration

### 1. Configure Teams Integration

Replace the placeholder webhook URL with your actual Teams channel webhook:

```bash
# Update Teams webhook URL in Logic App settings
az logicapp config appsettings set \
    --name <logic-app-name> \
    --resource-group <resource-group> \
    --settings "TEAMS_WEBHOOK_URL=<your-teams-webhook-url>"
```

### 2. Test Budget Alerts

```bash
# Verify budget configuration
az consumption budget show \
    --budget-name <budget-name> \
    --query "{Name:name, Amount:amount, Status:status}"
```

### 3. Validate Cost Export

```bash
# Check cost export status
az consumption export show \
    --export-name <export-name> \
    --query "{Name:name, Status:runHistory.status}"
```

## Monitoring and Validation

### Check Azure Advisor Recommendations

```bash
# List current cost optimization recommendations
az advisor recommendation list \
    --category Cost \
    --query "[].{Resource:resourceMetadata.resourceId, Impact:impact, Description:shortDescription.solution}" \
    --output table
```

### Test Logic App Workflow

```bash
# Get workflow trigger URL
az logicapp workflow show \
    --resource-group <resource-group> \
    --name <logic-app-name> \
    --workflow-name workflow \
    --query "accessEndpoint"
```

### Monitor Cost Anomalies

```bash
# Check cost anomaly alerts
az monitor metrics alert list \
    --resource-group <resource-group> \
    --query "[?contains(name, 'cost-anomaly')].{Name:name, Condition:condition, Status:enabled}"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name <resource-group-name> \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

### Manual Cleanup (if needed)

```bash
# Delete service principal
az ad sp delete --id <service-principal-id>

# Delete budget (if not in resource group)
az consumption budget delete --budget-name <budget-name>

# Delete cost export
az consumption export delete --export-name <export-name>
```

## Customization

### Budget Thresholds

Modify budget alert thresholds in the IaC templates:

- **80% threshold**: Warning alert
- **100% threshold**: Critical alert
- **120% threshold**: Emergency alert

### Cost Export Frequency

Change export frequency options:
- `Daily`: Daily cost exports
- `Weekly`: Weekly aggregated exports
- `Monthly`: Monthly cost summaries

### Logic App Workflow

Extend the Logic App workflow for additional actions:
- Resource right-sizing automation
- Reserved instance recommendations
- Unused resource identification
- Cost allocation tag enforcement

### Integration Options

- **Power BI**: Connect exported cost data to Power BI for advanced visualization
- **Azure DevOps**: Integrate with Azure Boards for cost optimization tasks
- **ServiceNow**: Create tickets for cost optimization recommendations
- **Slack**: Alternative to Teams for notifications

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Verify required permissions
   az role assignment list --assignee <your-user-id> --all
   ```

2. **Budget Creation Failed**
   ```bash
   # Check subscription limits
   az consumption budget list --query "length(@)"
   ```

3. **Logic App Deployment Issues**
   ```bash
   # Check Logic App logs
   az logicapp log show --name <logic-app-name> --resource-group <resource-group>
   ```

4. **Cost Export Failures**
   ```bash
   # Verify storage account permissions
   az storage account show --name <storage-account> --resource-group <resource-group>
   ```

### Debug Commands

```bash
# Check all resources in the resource group
az resource list --resource-group <resource-group> --output table

# Verify service principal permissions
az ad sp show --id <service-principal-id> --query "appRoles"

# Test webhook connectivity
curl -X POST <teams-webhook-url> -H "Content-Type: application/json" -d '{"text":"Test message"}'
```

## Cost Estimates

### Monthly Operating Costs

- **Logic Apps Standard**: ~$10-15/month
- **Storage Account**: ~$2-5/month
- **Log Analytics**: ~$5-10/month
- **Total estimated cost**: ~$20-30/month

### Cost Optimization Potential

This solution typically identifies:
- 10-30% potential cost savings
- Unused resources worth $100-1000/month
- Right-sizing opportunities worth $50-500/month

## Security Considerations

### Implemented Security Measures

- Service principal with least privilege access
- Storage account with private access only
- Logic Apps with managed identity authentication
- Encrypted cost data storage
- Secure webhook communications

### Additional Security Recommendations

- Enable Azure Key Vault for webhook URL storage
- Implement Azure Private Endpoints for storage access
- Use Azure AD conditional access for Logic Apps
- Enable audit logging for all cost management operations

## Support

For issues with this infrastructure code:

1. Check the [Azure Cost Management documentation](https://docs.microsoft.com/en-us/azure/cost-management-billing/)
2. Review the [Azure Advisor documentation](https://docs.microsoft.com/en-us/azure/advisor/)
3. Consult the [Logic Apps documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
4. Refer to the original recipe documentation for detailed implementation guidance

## Contributing

To improve this IaC implementation:

1. Follow Azure naming conventions
2. Implement proper error handling
3. Add comprehensive comments
4. Test all configurations
5. Update documentation accordingly

## Version History

- **v1.0**: Initial implementation with Bicep, Terraform, and Bash scripts
- Supports Azure Advisor integration, Cost Management automation, and Teams notifications
- Includes comprehensive monitoring and alerting capabilities