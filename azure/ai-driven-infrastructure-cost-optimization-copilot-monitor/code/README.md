# Infrastructure as Code for AI-Driven Infrastructure Cost Optimization with Azure Copilot and Azure Monitor

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI-Driven Infrastructure Cost Optimization with Azure Copilot and Azure Monitor".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (v2.50.0 or later)
- PowerShell 7.0 or later for runbook development
- Appropriate Azure permissions (Owner or Contributor role)
- Basic understanding of Azure Cost Management and FinOps principles

## Quick Start

### Using Bicep
```bash
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters @parameters.json

# Or use the deployment script
chmod +x ../scripts/deploy.sh
../scripts/deploy.sh
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply

# Confirm with 'yes' when prompted
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts and wait for completion
```

## Architecture Overview

This infrastructure deploys:

- **Log Analytics Workspace**: Centralized logging and monitoring data collection
- **Azure Automation Account**: Hosts PowerShell runbooks for cost optimization
- **Cost Management Budgets**: Proactive spending controls and alerts
- **Azure Monitor Alerts**: Automated triggers for cost anomalies
- **Logic Apps**: Orchestration workflows for automated responses
- **PowerShell Runbooks**: Automated optimization scripts (VM resizing, storage tier adjustments)

## Configuration Options

### Bicep Parameters

Key parameters you can customize in `bicep/parameters.json`:

- `location`: Azure region for resource deployment
- `workspaceName`: Log Analytics workspace name
- `automationAccountName`: Azure Automation account name
- `budgetAmount`: Monthly budget threshold in USD
- `costThreshold`: Cost alert threshold percentage

### Terraform Variables

Key variables you can customize in `terraform/variables.tf`:

- `resource_group_name`: Target resource group name
- `location`: Azure region for resources
- `budget_amount`: Monthly spending limit
- `workspace_retention_days`: Log retention period
- `automation_account_sku`: Automation account pricing tier

## Cost Considerations

**Estimated monthly costs:**
- Log Analytics Workspace: $2-15 (based on data ingestion)
- Azure Automation Account: $5-20 (based on runbook execution time)
- Logic Apps: $1-5 (based on workflow executions)
- Storage for runbooks and logs: $1-3

**Total estimated cost: $9-43/month** (varies based on usage and monitored resources)

> **Note**: The cost optimization implemented by this solution typically saves 20-30% on overall Azure spending, providing significant ROI.

## Post-Deployment Configuration

After deploying the infrastructure:

1. **Configure Azure Copilot Integration**:
   - Navigate to Azure Portal and open Copilot
   - Test with prompts like "What are my top cost optimization opportunities?"

2. **Set Up Cost Alerts**:
   - Review and adjust budget thresholds in Azure Cost Management
   - Configure notification recipients for cost alerts

3. **Test Automation Runbooks**:
   - Verify runbooks are published and ready
   - Test with a non-production VM to ensure proper functionality

4. **Enable Additional Monitoring**:
   - Configure diagnostic settings for critical resources
   - Set up custom metrics for specific cost optimization scenarios

## Validation & Testing

### Verify Deployment
```bash
# Check resource group resources
az resource list --resource-group <your-resource-group> --output table

# Verify Log Analytics workspace
az monitor log-analytics workspace show \
    --resource-group <your-resource-group> \
    --workspace-name <workspace-name>

# Check automation account status
az automation account show \
    --name <automation-account-name> \
    --resource-group <your-resource-group>
```

### Test Cost Optimization
```bash
# Create a test VM for optimization testing
az vm create \
    --resource-group <your-resource-group> \
    --name test-vm-optimize \
    --image Ubuntu2204 \
    --size Standard_D4s_v3 \
    --admin-username azureuser \
    --generate-ssh-keys

# Monitor the automation runbook execution
az automation job list \
    --automation-account-name <automation-account-name> \
    --resource-group <your-resource-group> \
    --output table
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group and all resources
az group delete --name <your-resource-group> --yes --no-wait
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### Adding Custom Runbooks

To add additional cost optimization runbooks:

1. Create PowerShell scripts for specific optimization scenarios
2. Update the Bicep/Terraform templates to include new runbooks
3. Modify automation schedules as needed
4. Test thoroughly in a non-production environment

### Extending Monitoring

To monitor additional Azure services:

1. Update diagnostic settings in templates
2. Add custom Log Analytics queries
3. Configure additional Azure Monitor alerts
4. Extend Logic Apps workflows for new scenarios

### Integration with Azure Copilot

The deployed infrastructure integrates with Azure Copilot for:

- Natural language cost analysis queries
- AI-driven optimization recommendations
- Predictive cost modeling
- Automated insight generation

Try these prompts in Azure Copilot after deployment:
- "How can I reduce my VM costs this month?"
- "Show me cost trends for the last 30 days"
- "What are my top 5 cost optimization opportunities?"
- "Predict my spending for next month based on current usage"

## Troubleshooting

### Common Issues

**Automation runbook failures:**
- Verify managed identity permissions
- Check PowerShell module dependencies
- Review runbook execution logs

**Cost alert not triggering:**
- Verify budget configuration
- Check alert rule conditions
- Ensure proper email notifications setup

**Logic App workflow errors:**
- Review workflow run history
- Verify webhook configurations
- Check authentication settings

### Support Resources

- [Azure Cost Management Documentation](https://docs.microsoft.com/en-us/azure/cost-management-billing/)
- [Azure Monitor Best Practices](https://docs.microsoft.com/en-us/azure/azure-monitor/best-practices)
- [Azure Automation Documentation](https://docs.microsoft.com/en-us/azure/automation/)
- [FinOps Framework](https://www.finops.org/framework/)

## Security Considerations

This infrastructure implements several security best practices:

- **Managed Identity**: Automation account uses system-assigned managed identity
- **Least Privilege**: Role assignments follow principle of least privilege
- **Secure Communication**: All API calls use HTTPS and Azure AD authentication
- **Audit Logging**: All optimization actions are logged for compliance

## Support

For issues with this infrastructure code, refer to:
1. The original recipe documentation
2. Azure provider documentation for Terraform/Bicep
3. Azure CLI documentation for troubleshooting commands
4. Azure Cost Management best practices guide

## License

This infrastructure code is provided as-is for educational and implementation purposes. Review and test thoroughly before using in production environments.