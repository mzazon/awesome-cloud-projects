# Infrastructure as Code for Simple Schedule Reminders with Logic Apps and Outlook

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Schedule Reminders with Logic Apps and Outlook".

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys:
- Azure Logic App with recurrence trigger (weekly schedule)
- Office 365 Outlook connection for sending emails
- Resource group for organizing resources
- Necessary IAM permissions and configurations

## Prerequisites

- Azure CLI installed and configured (`az login` completed)
- Azure subscription with appropriate permissions
- Office 365 account with work or school email (e.g., user@company.onmicrosoft.com)
- Logic Apps Contributor role or higher for the target resource group
- For Terraform: Terraform >= 1.0 installed
- For Bicep: Azure CLI with Bicep extension

> **Note**: Personal Microsoft accounts (@outlook.com, @hotmail.com) require the Outlook.com connector instead of Office 365 Outlook connector.

## Quick Start

### Using Bicep
```bash
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters \
        logicAppName="la-schedule-reminders-$(openssl rand -hex 3)" \
        recipientEmail="user@company.com" \
        location="eastus"
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="recipient_email=user@company.com" \
    -var="resource_group_location=eastus"

# Apply the configuration
terraform apply \
    -var="recipient_email=user@company.com" \
    -var="resource_group_location=eastus"
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RECIPIENT_EMAIL="user@company.com"
export LOCATION="eastus"

# Deploy the solution
./scripts/deploy.sh
```

## Configuration Parameters

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `logicAppName` | string | Generated | Name for the Logic App resource |
| `recipientEmail` | string | Required | Email address to receive reminders |
| `location` | string | `eastus` | Azure region for deployment |
| `scheduleFrequency` | string | `Week` | Recurrence frequency (Week, Day, Month) |
| `scheduleInterval` | int | `1` | Interval between executions |
| `scheduleHour` | int | `9` | Hour to send reminder (24-hour format) |
| `scheduleWeekDay` | string | `Monday` | Day of week for weekly reminders |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `resource_group_name` | string | Generated | Name for the resource group |
| `resource_group_location` | string | `eastus` | Azure region for deployment |
| `logic_app_name` | string | Generated | Name for the Logic App resource |
| `recipient_email` | string | Required | Email address to receive reminders |
| `schedule_frequency` | string | `Week` | Recurrence frequency |
| `schedule_interval` | number | `1` | Interval between executions |
| `schedule_hour` | number | `9` | Hour to send reminder (24-hour format) |
| `schedule_weekday` | string | `Monday` | Day of week for weekly reminders |

## Post-Deployment Setup

After deploying the infrastructure, you'll need to complete the Office 365 connection setup:

1. **Navigate to the Azure Portal**:
   - Go to your resource group
   - Select the created Logic App

2. **Configure Office 365 Connection**:
   - In the Logic App, click "API connections" in the left menu
   - Click "+ Add" to create a new connection
   - Search for "Office 365 Outlook" and select it
   - Click "Create" and sign in with your Office 365 account
   - Name the connection "office365" to match the workflow

3. **Update Connection Parameters** (if using scripts):
   ```bash
   # The deployment scripts will guide you through this process
   # Follow the on-screen instructions to complete the connection setup
   ```

## Testing the Solution

### Manual Testing
```bash
# Trigger the Logic App manually for testing
az logic workflow trigger run \
    --resource-group <your-resource-group> \
    --workflow-name <your-logic-app-name> \
    --trigger-name Recurrence

# Check run history
az logic workflow run list \
    --resource-group <your-resource-group> \
    --workflow-name <your-logic-app-name> \
    --top 5
```

### Validation Steps
1. Verify Logic App is in "Enabled" state
2. Check that the Office 365 connection is authenticated
3. Confirm email delivery to the specified recipient
4. Review run history for successful executions

## Customization

### Email Content Customization
To modify the email subject and body, update the workflow definition in:
- **Bicep**: `main.bicep` - Modify the `workflowDefinition` property
- **Terraform**: `main.tf` - Update the `definition` block in the Logic App resource
- **Scripts**: The deployment script will prompt for customization options

### Schedule Customization
Adjust the recurrence schedule by modifying:
- Frequency: `Day`, `Week`, `Month`, or `Year`
- Interval: Number of frequency units between executions
- Schedule: Specific times and days for execution

### Advanced Features
Consider extending the solution with:
- Dynamic content from SharePoint or databases
- Conditional logic based on business rules
- Multiple recipients with personalized content
- Integration with Microsoft Teams or other services

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <your-resource-group> \
    --yes \
    --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy \
    -var="recipient_email=user@company.com" \
    -var="resource_group_location=eastus"
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

## Cost Considerations

- **Logic Apps Consumption**: ~$0.05-0.10 per month for weekly reminders
- **API Connection**: No additional cost for Office 365 Outlook connector
- **Storage**: Minimal costs for run history and logs

## Troubleshooting

### Common Issues

1. **Connection Authentication Failures**:
   - Ensure you're signed in with a work/school account
   - Verify the account has permission to send emails
   - Check that the connection name matches the workflow definition

2. **Logic App Not Triggering**:
   - Verify the Logic App is in "Enabled" state
   - Check the recurrence schedule configuration
   - Review the run history for error details

3. **Email Not Received**:
   - Check spam/junk folders
   - Verify the recipient email address is correct
   - Ensure the Office 365 connection is properly authenticated

### Monitoring and Logging

Enable Azure Monitor for comprehensive logging:
```bash
# Enable diagnostic settings for the Logic App
az monitor diagnostic-settings create \
    --resource <logic-app-resource-id> \
    --name "LogicAppDiagnostics" \
    --workspace <log-analytics-workspace-id> \
    --logs '[{"category":"WorkflowRuntime","enabled":true}]' \
    --metrics '[{"category":"AllMetrics","enabled":true}]'
```

## Security Best Practices

- Use Azure Key Vault for sensitive configuration values
- Enable Azure Policy for governance and compliance
- Implement proper RBAC for Logic App access
- Monitor connection usage and authentication
- Regular review of run history and logs

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Azure Logic Apps documentation: https://docs.microsoft.com/en-us/azure/logic-apps/
3. Consult Office 365 Outlook connector documentation
4. Review Azure CLI and Terraform provider documentation

## Version Information

- Recipe Version: 1.1
- Last Updated: 2025-07-12
- Bicep Language Version: Latest stable
- Terraform Azure Provider: ~> 3.0
- Azure CLI: Latest stable version required