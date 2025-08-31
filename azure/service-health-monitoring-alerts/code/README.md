# Infrastructure as Code for Service Health Monitoring with Azure Service Health and Monitor

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Service Health Monitoring with Azure Service Health and Monitor".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with appropriate permissions
- Basic understanding of Azure Monitor and Service Health concepts
- Valid email address and phone number for notifications
- For Terraform: Terraform CLI installed (version >= 1.0)
- For Bicep: Azure CLI with Bicep extension installed

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Set your notification details
export NOTIFICATION_EMAIL="admin@yourcompany.com"
export NOTIFICATION_PHONE="+1234567890"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-service-health-monitoring" \
    --template-file main.bicep \
    --parameters notificationEmail=$NOTIFICATION_EMAIL \
                 notificationPhone=$NOTIFICATION_PHONE \
                 location="eastus"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
resource_group_name = "rg-service-health-monitoring"
location = "eastus"
notification_email = "admin@yourcompany.com"
notification_phone = "+1234567890"
environment = "production"
EOF

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Set environment variables
export NOTIFICATION_EMAIL="admin@yourcompany.com"
export NOTIFICATION_PHONE="+1234567890"
export RESOURCE_GROUP="rg-service-health-monitoring"
export LOCATION="eastus"

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy the infrastructure
./deploy.sh
```

## Architecture Overview

This infrastructure deploys:

1. **Resource Group**: Container for all monitoring resources
2. **Action Group**: Defines notification channels (email, SMS, webhook)
3. **Activity Log Alert Rules**: Monitor for different types of service health events:
   - Service Issues
   - Planned Maintenance
   - Health Advisories
   - Critical Services Monitoring

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | No |
| `notificationEmail` | Email address for alerts | - | Yes |
| `notificationPhone` | Phone number for SMS alerts | - | Yes |
| `actionGroupName` | Name of the action group | `ServiceHealthAlerts` | No |
| `environment` | Environment tag | `production` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `resource_group_name` | Name of the resource group | `string` | - | Yes |
| `location` | Azure region | `string` | `eastus` | No |
| `notification_email` | Email for notifications | `string` | - | Yes |
| `notification_phone` | Phone for SMS notifications | `string` | - | Yes |
| `environment` | Environment tag | `string` | `production` | No |

### Bash Script Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `NOTIFICATION_EMAIL` | Email address for alerts | `admin@company.com` |
| `NOTIFICATION_PHONE` | Phone number for SMS | `+1234567890` |
| `RESOURCE_GROUP` | Resource group name | `rg-service-health` |
| `LOCATION` | Azure region | `eastus` |

## Testing and Validation

After deployment, validate the setup:

```bash
# Check action group configuration
az monitor action-group show \
    --name "ServiceHealthAlerts" \
    --resource-group "rg-service-health-monitoring"

# List all alert rules
az monitor activity-log alert list \
    --resource-group "rg-service-health-monitoring" \
    --output table

# Test notifications
az monitor action-group test-notifications create \
    --action-group-name "ServiceHealthAlerts" \
    --resource-group "rg-service-health-monitoring" \
    --alert-type servicehealth
```

## Outputs

All implementations provide these outputs:

- **Action Group ID**: Resource ID of the created action group
- **Action Group Name**: Name of the action group for reference
- **Alert Rule IDs**: Resource IDs of all created alert rules
- **Resource Group Name**: Name of the resource group containing all resources

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name "rg-service-health-monitoring" \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
cd scripts/
./destroy.sh
```

## Cost Considerations

- **Action Groups**: Free for email notifications
- **SMS Notifications**: Charges apply per SMS sent (varies by region)
- **Activity Log Alerts**: Free for service health monitoring
- **Resource Group**: No cost for the container itself

> **Note**: SMS charges are typically $0.50-$2.00 per message depending on your region and mobile carrier.

## Security Best Practices

This implementation follows Azure security best practices:

1. **Least Privilege**: Resources are assigned minimal required permissions
2. **Global Scope**: Action groups use global scope for reliability during regional outages
3. **Secure Communications**: All notifications use encrypted channels
4. **Resource Tagging**: Resources are tagged for governance and cost management

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your account has Contributor or Monitoring Contributor role
2. **Invalid Phone Number**: Phone numbers must include country code (e.g., +1234567890)
3. **Action Group Region**: Action groups must be created in "Global" region for service health alerts
4. **Email Validation**: Ensure email addresses are valid and accessible

### Debug Commands

```bash
# Check subscription context
az account show

# Verify resource group exists
az group exists --name "rg-service-health-monitoring"

# Check activity log for deployment issues
az monitor activity-log list \
    --resource-group "rg-service-health-monitoring" \
    --max-events 10
```

## Customization

### Adding Additional Notification Channels

You can extend the action group to include:

- **Webhooks**: For integration with ITSM systems
- **Logic Apps**: For complex notification workflows  
- **Azure Functions**: For custom notification processing
- **Voice Calls**: For critical escalations

### Filtering by Service Types

Modify alert rules to monitor specific Azure services:

```bash
# Example: Monitor only Virtual Machines and Storage
az monitor activity-log alert create \
    --name "VmStorageAlert" \
    --resource-group "rg-service-health-monitoring" \
    --condition category=ServiceHealth \
    --action-group $ACTION_GROUP_ID \
    --description "Alert for VM and Storage service issues"
```

## Integration Examples

### Microsoft Teams Integration

Add webhook receiver to action group:

```bash
az monitor action-group create \
    --name "ServiceHealthAlerts" \
    --resource-group "rg-service-health-monitoring" \
    --webhook-receivers name="teams-webhook" \
                       service-uri="https://your-teams-webhook-url"
```

### ServiceNow Integration

Configure webhook for ServiceNow incident creation:

```bash
az monitor action-group create \
    --name "ServiceHealthAlerts" \
    --resource-group "rg-service-health-monitoring" \
    --webhook-receivers name="servicenow" \
                       service-uri="https://your-instance.service-now.com/api/webhook"
```

## Support and Documentation

- [Azure Service Health Documentation](https://docs.microsoft.com/en-us/azure/service-health/)
- [Azure Monitor Action Groups](https://docs.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups)
- [Activity Log Alerts](https://docs.microsoft.com/en-us/azure/azure-monitor/alerts/activity-log-alerts)
- [Azure CLI Monitor Commands](https://docs.microsoft.com/en-us/cli/azure/monitor)

## Contributing

For issues with this infrastructure code, refer to the original recipe documentation or submit issues to the repository maintainers.

## License

This infrastructure code is provided as-is under the same license as the parent repository.