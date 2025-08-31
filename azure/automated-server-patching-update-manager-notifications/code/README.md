# Infrastructure as Code for Automated Server Patching with Update Manager and Notifications

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Server Patching with Update Manager and Notifications".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This IaC deploys the following Azure resources:

- Virtual Machine (Windows Server 2022) configured for automated patching
- Maintenance Configuration with weekly patching schedule
- Action Group for email notifications
- Activity Log Alerts for patch deployment monitoring
- Required networking components (VNet, Subnet, NSG)
- Virtual Machine assignment to maintenance configuration

## Prerequisites

### General Requirements
- Azure subscription with appropriate permissions:
  - Virtual Machine Contributor
  - Monitoring Contributor
  - Resource Group Contributor
- Valid email address for receiving patch notifications
- Azure CLI installed and configured (version 2.37.0 or later)

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension
- Bicep CLI version 0.15.0 or later

#### For Terraform
- Terraform CLI version 1.3.0 or later
- Azure CLI authenticated (`az login`)

#### For Bash Scripts
- Azure CLI installed and configured
- Bash shell (Linux/macOS) or WSL/Git Bash (Windows)
- `openssl` command available for random string generation

## Cost Estimates

- Standard B2s VM: ~$0.08/hour
- Storage (Premium SSD): ~$0.15/month
- Monitoring alerts: Minimal cost
- Total estimated cost for testing: $5-10 USD for 20 minutes

## Quick Start

### Using Bicep (Recommended for Azure)

1. **Deploy the infrastructure:**
   ```bash
   cd bicep/
   
   # Login to Azure (if not already authenticated)
   az login
   
   # Set your subscription
   az account set --subscription "your-subscription-id"
   
   # Deploy with your email address
   az deployment group create \
       --resource-group "rg-patching-demo" \
       --template-file main.bicep \
       --parameters adminEmail="your-email@domain.com" \
       --parameters adminUsername="azureuser" \
       --parameters adminPassword="YourSecurePassword123!"
   ```

2. **Verify deployment:**
   ```bash
   # Check resource group resources
   az resource list --resource-group "rg-patching-demo" --output table
   ```

### Using Terraform

1. **Initialize and deploy:**
   ```bash
   cd terraform/
   
   # Initialize Terraform
   terraform init
   
   # Review the deployment plan
   terraform plan \
       -var="admin_email=your-email@domain.com" \
       -var="admin_username=azureuser" \
       -var="admin_password=YourSecurePassword123!"
   
   # Apply the configuration
   terraform apply \
       -var="admin_email=your-email@domain.com" \
       -var="admin_username=azureuser" \
       -var="admin_password=YourSecurePassword123!"
   ```

2. **View outputs:**
   ```bash
   terraform output
   ```

### Using Bash Scripts

1. **Set environment variables:**
   ```bash
   export ADMIN_EMAIL="your-email@domain.com"
   export ADMIN_USERNAME="azureuser"
   export ADMIN_PASSWORD="YourSecurePassword123!"
   export AZURE_LOCATION="eastus"
   ```

2. **Deploy:**
   ```bash
   chmod +x scripts/deploy.sh
   ./scripts/deploy.sh
   ```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `adminEmail` | Email address for patch notifications | - | Yes |
| `adminUsername` | VM administrator username | `azureuser` | No |
| `adminPassword` | VM administrator password | - | Yes |
| `location` | Azure region for deployment | `eastus` | No |
| `vmSize` | Virtual machine size | `Standard_B2s` | No |
| `maintenanceStartTime` | Maintenance window start time | `02:00` | No |
| `maintenanceDay` | Day of week for maintenance | `Saturday` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `admin_email` | Email address for patch notifications | - | Yes |
| `admin_username` | VM administrator username | `azureuser` | No |
| `admin_password` | VM administrator password | - | Yes |
| `location` | Azure region for deployment | `eastus` | No |
| `vm_size` | Virtual machine size | `Standard_B2s` | No |
| `maintenance_start_time` | Maintenance window start time | `02:00` | No |
| `maintenance_day` | Day of week for maintenance | `Saturday` | No |

### Environment Variables (Bash Scripts)

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `ADMIN_EMAIL` | Email address for patch notifications | - | Yes |
| `ADMIN_USERNAME` | VM administrator username | `azureuser` | No |
| `ADMIN_PASSWORD` | VM administrator password | - | Yes |
| `AZURE_LOCATION` | Azure region for deployment | `eastus` | No |

## Validation and Testing

After deployment, validate the solution:

1. **Check VM patch configuration:**
   ```bash
   az vm show \
       --resource-group "rg-patching-demo" \
       --name "vm-demo" \
       --query "osProfile.windowsConfiguration.patchSettings"
   ```

2. **Verify maintenance configuration:**
   ```bash
   az maintenance configuration list \
       --resource-group "rg-patching-demo" \
       --output table
   ```

3. **Test Action Group notifications:**
   ```bash
   az monitor action-group test-notifications create \
       --resource-group "rg-patching-demo" \
       --action-group-name "ag-patching" \
       --notification-type Email \
       --receivers email1
   ```

4. **Review maintenance assignments:**
   ```bash
   az maintenance assignment list \
       --resource-group "rg-patching-demo" \
       --resource-name "vm-demo" \
       --resource-type "virtualMachines" \
       --provider-name "Microsoft.Compute"
   ```

## Maintenance Window Configuration

The default maintenance configuration includes:

- **Schedule**: Every Saturday at 2:00 AM EST
- **Duration**: 2-hour maintenance window
- **Patch Classifications**: Critical, Security, Updates
- **Reboot Policy**: If Required
- **Time Zone**: Eastern Standard Time

To modify the maintenance schedule, update the maintenance configuration parameters in your chosen IaC implementation.

## Notification Configuration

The Action Group is configured to send email notifications for:

- Patch deployment activities
- Maintenance configuration changes
- Maintenance assignment operations

Email notifications will be sent to the address specified in the `admin_email` parameter.

## Security Considerations

This implementation follows Azure security best practices:

- VM uses Azure Managed Identity where possible
- Network Security Group restricts inbound access
- Patch management uses Customer Managed Schedules for controlled updates
- Activity logging enabled for audit purposes
- Least privilege access for service accounts

## Customization Examples

### Different Maintenance Schedule

To change the maintenance schedule to monthly on the first Sunday:

**Bicep:**
```bicep
maintenanceDay: 'Sunday'
maintenanceRecurrence: '1Month'
maintenanceWeekOfMonth: 'First'
```

**Terraform:**
```hcl
variable "maintenance_recurrence" {
  default = "1Month"
}

variable "maintenance_week_of_month" {
  default = "First"
}
```

### Multiple Email Recipients

To add multiple email recipients to the Action Group:

**Bicep:**
```bicep
param additionalEmails array = [
  'admin2@domain.com'
  'admin3@domain.com'
]
```

**Terraform:**
```hcl
variable "notification_emails" {
  type = list(string)
  default = ["admin1@domain.com", "admin2@domain.com"]
}
```

### Different VM Configuration

To use a different VM size or OS:

**Bicep:**
```bicep
param vmSize string = 'Standard_D2s_v3'
param osImage string = 'Win2019Datacenter'
```

**Terraform:**
```hcl
variable "vm_size" {
  default = "Standard_D2s_v3"
}

variable "os_image" {
  default = "2019-Datacenter"
}
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group and all resources
az group delete \
    --name "rg-patching-demo" \
    --yes \
    --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy \
    -var="admin_email=your-email@domain.com" \
    -var="admin_username=azureuser" \
    -var="admin_password=YourSecurePassword123!"
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **VM not receiving patches:**
   - Verify maintenance configuration assignment
   - Check patch orchestration mode is set to "AutomaticByPlatform"
   - Ensure maintenance window timing is correct

2. **Email notifications not received:**
   - Verify Action Group configuration
   - Check spam/junk folders
   - Test Action Group with test notification

3. **Maintenance configuration assignment fails:**
   - Ensure VM is in running state
   - Verify proper permissions for Update Manager
   - Check maintenance configuration is in same region as VM

### Debug Commands

```bash
# Check VM status
az vm get-instance-view \
    --resource-group "rg-patching-demo" \
    --name "vm-demo" \
    --query "statuses"

# Review Activity Log for errors
az monitor activity-log list \
    --resource-group "rg-patching-demo" \
    --start-time 2025-01-01T00:00:00Z \
    --query "[?level=='Error']"

# Check maintenance assignment status
az maintenance assignment show \
    --resource-group "rg-patching-demo" \
    --resource-name "vm-demo" \
    --resource-type "virtualMachines" \
    --provider-name "Microsoft.Compute" \
    --configuration-assignment-name "assign-maintenance-config"
```

## Support and Documentation

- [Azure Update Manager Documentation](https://learn.microsoft.com/en-us/azure/update-manager/)
- [Maintenance Configurations](https://learn.microsoft.com/en-us/azure/virtual-machines/maintenance-configurations)
- [Azure Action Groups](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or the Azure provider's documentation.

## Contributing

When modifying this IaC:

1. Test changes in a development environment first
2. Update parameter documentation for any new variables
3. Validate security configurations
4. Update this README with any new customization options
5. Ensure cleanup procedures are updated for new resources