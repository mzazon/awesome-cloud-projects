# Infrastructure as Code for Chaos Engineering for Application Resilience Testing

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Chaos Engineering for Application Resilience Testing".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with Owner or Contributor permissions
- Basic understanding of chaos engineering principles
- Familiarity with Azure Monitor and Application Insights concepts
- Appropriate permissions for:
  - Creating resource groups and virtual machines
  - Managing Azure Chaos Studio experiments
  - Configuring Application Insights and Log Analytics
  - Assigning Azure RBAC roles

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the Bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-chaos-testing-$(openssl rand -hex 3)" \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment group show \
    --resource-group <your-resource-group> \
    --name main \
    --query properties.provisioningState
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

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment status
echo "Check Azure portal or use Azure CLI to verify resources"
```

## Architecture Overview

This IaC deployment creates:

- **Log Analytics Workspace**: Centralized logging and analytics
- **Application Insights**: Application performance monitoring and telemetry
- **Virtual Machine**: Target resource for chaos experiments
- **User-Assigned Managed Identity**: Secure authentication for Chaos Studio
- **Chaos Studio Experiment**: VM shutdown fault injection scenario
- **Azure Monitor Alerts**: Notifications for chaos experiment events
- **RBAC Assignments**: Proper permissions for experiment execution

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "vmSize": {
      "value": "Standard_B2s"
    },
    "adminUsername": {
      "value": "azureuser"
    },
    "experimentDuration": {
      "value": "PT5M"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
location = "eastus"
vm_size = "Standard_B2s"
admin_username = "azureuser"
experiment_duration = "PT5M"
environment = "demo"
```

### Bash Script Environment Variables

Edit environment variables in `scripts/deploy.sh`:

```bash
export LOCATION="eastus"
export VM_SIZE="Standard_B2s"
export ADMIN_USERNAME="azureuser"
export EXPERIMENT_DURATION="PT5M"
```

## Post-Deployment Steps

After successful deployment, complete these manual steps:

1. **Install Chaos Agent** (if not automated):
   ```bash
   # Get resource information
   RESOURCE_GROUP="<your-resource-group>"
   VM_NAME="<your-vm-name>"
   
   # Install Chaos Agent with Application Insights
   az vm extension set \
       --resource-group ${RESOURCE_GROUP} \
       --vm-name ${VM_NAME} \
       --name ChaosAgent \
       --publisher Microsoft.Azure.Chaos \
       --version 1.0 \
       --settings @agent-settings.json
   ```

2. **Verify Chaos Studio Configuration**:
   ```bash
   # Check target enablement
   az rest --method get \
       --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachines/${VM_NAME}/providers/Microsoft.Chaos/targets/Microsoft-VirtualMachine?api-version=2024-01-01"
   ```

3. **Test Chaos Experiment**:
   ```bash
   # Start experiment
   EXPERIMENT_NAME="<your-experiment-name>"
   az rest --method post \
       --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Chaos/experiments/${EXPERIMENT_NAME}/start?api-version=2024-01-01"
   ```

## Validation and Testing

### Verify Infrastructure

```bash
# Check resource group contents
az resource list --resource-group <your-resource-group> --output table

# Verify VM status
az vm get-instance-view \
    --name <your-vm-name> \
    --resource-group <your-resource-group> \
    --query instanceView.statuses[1].displayStatus

# Check Application Insights telemetry
az monitor app-insights query \
    --app <your-app-insights-name> \
    --resource-group <your-resource-group> \
    --analytics-query "customEvents | where name contains 'Chaos' | take 10"
```

### Monitor Chaos Experiments

- Access Application Insights in Azure Portal
- Review Live Metrics during experiments
- Check Custom Events for chaos telemetry
- Monitor Azure Monitor alerts

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
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm deletion
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group show --name <your-resource-group> 2>/dev/null || echo "Resource group deleted"
```

## Cost Considerations

This infrastructure incurs the following approximate monthly costs:

- **Standard_B2s VM**: ~$30-40/month
- **Application Insights**: ~$2-10/month (based on data ingestion)
- **Log Analytics**: ~$2-5/month (based on data retention)
- **Chaos Studio**: Pay-per-experiment execution (~$0.10-1.00 per experiment)

> **Important**: Always run cleanup after testing to avoid unnecessary charges.

## Troubleshooting

### Common Issues

1. **Chaos Agent Installation Fails**:
   - Verify VM is running and accessible
   - Check managed identity permissions
   - Review extension installation logs

2. **Experiment Execution Fails**:
   - Verify RBAC assignments are complete
   - Check experiment status in Azure Portal
   - Review Chaos Studio audit logs

3. **Application Insights No Data**:
   - Verify instrumentation key configuration
   - Check agent settings JSON
   - Allow 5-10 minutes for data ingestion

### Debug Commands

```bash
# Check Chaos Studio provider registration
az provider show --namespace Microsoft.Chaos --query registrationState

# Verify managed identity assignment
az identity show --name <identity-name> --resource-group <resource-group>

# Check VM extension status
az vm extension list --vm-name <vm-name> --resource-group <resource-group>
```

## Security Best Practices

This implementation follows Azure security best practices:

- **Managed Identity**: Password-free authentication for Chaos Studio
- **Least Privilege RBAC**: Minimal permissions for experiment execution
- **Network Security**: Default NSG rules for VM access
- **Key Management**: SSH key generation for VM access
- **Monitoring**: Comprehensive logging with Application Insights

## Customization Examples

### Add CPU Stress Experiment

```json
{
  "type": "continuous",
  "name": "CPU Stress",
  "selectorId": "Selector1",
  "duration": "PT10M",
  "parameters": [
    {
      "key": "pressureLevel",
      "value": "95"
    }
  ]
}
```

### Configure Advanced Monitoring

```bash
# Create custom KQL queries
az monitor app-insights query \
    --app <app-insights-name> \
    --resource-group <resource-group> \
    --analytics-query "customEvents 
    | where name == 'ChaosExperimentStarted' 
    | summarize count() by bin(timestamp, 1h)"
```

## Support and Resources

- [Azure Chaos Studio Documentation](https://docs.microsoft.com/en-us/azure/chaos-studio/)
- [Application Insights Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/app/)
- [Azure Well-Architected Framework - Reliability](https://docs.microsoft.com/en-us/azure/architecture/framework/resiliency/)
- [Chaos Engineering Best Practices](https://docs.microsoft.com/en-us/azure/well-architected/reliability/testing-strategy)

For issues with this infrastructure code, refer to the original recipe documentation or the Azure documentation links above.