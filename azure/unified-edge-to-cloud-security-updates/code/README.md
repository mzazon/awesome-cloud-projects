# Infrastructure as Code for Unified Edge-to-Cloud Security Updates with IoT Device Update and Update Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Unified Edge-to-Cloud Security Updates with IoT Device Update and Update Manager".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts for Azure CLI

## Prerequisites

### General Requirements
- Azure CLI version 2.30.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - IoT Hub creation and management
  - Device Update account and instance creation
  - Storage account creation
  - Virtual machine creation and management
  - Log Analytics workspace creation
  - Azure Monitor configuration
  - Logic Apps creation
- PowerShell (for Windows) or Bash (for Linux/macOS)

### Tool-Specific Prerequisites

#### Bicep
- Azure CLI with Bicep extension installed
```bash
az bicep install
az bicep upgrade
```

#### Terraform
- Terraform version 1.0+ installed
- Azure CLI authenticated with appropriate subscription
```bash
terraform --version
az login
az account set --subscription "your-subscription-id"
```

### Required Permissions
- Contributor role on the target resource group
- IoT Hub Data Contributor for device management
- Storage Blob Data Contributor for update artifacts
- Virtual Machine Contributor for infrastructure patching
- Log Analytics Contributor for monitoring setup

## Quick Start

### Using Bicep (Recommended for Azure)
```bash
# Navigate to the bicep directory
cd bicep/

# Set deployment parameters
RESOURCE_GROUP="rg-iot-updates-demo"
LOCATION="eastus"
DEPLOYMENT_NAME="iot-updates-deployment"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Deploy infrastructure
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --name $DEPLOYMENT_NAME \
    --parameters location=$LOCATION

# Get deployment outputs
az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name $DEPLOYMENT_NAME \
    --query properties.outputs
```

### Using Terraform
```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables (optional - script will prompt if not set)
export RESOURCE_GROUP="rg-iot-updates-demo"
export LOCATION="eastus"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
az group show --name $RESOURCE_GROUP --output table
```

## Architecture Overview

The infrastructure deploys the following Azure resources:

### Core IoT Services
- **Azure IoT Hub**: Central communication hub for IoT devices
- **Azure IoT Device Update Account**: Service for managing over-the-air updates
- **Azure IoT Device Update Instance**: Specific instance linked to IoT Hub
- **Azure Storage Account**: Secure storage for update artifacts and packages

### Infrastructure Management
- **Azure Virtual Machine**: Test VM for demonstrating Update Manager capabilities
- **Azure Update Manager**: Automated patch management for VMs and hybrid infrastructure

### Monitoring and Orchestration
- **Log Analytics Workspace**: Centralized logging and monitoring
- **Azure Monitor**: Metrics, alerts, and dashboards for update operations
- **Logic App**: Orchestration workflow for coordinated updates
- **Alert Rules**: Automated notifications for failed updates

### Security Features
- **Managed Identity**: Secure authentication between services
- **RBAC**: Role-based access control for service permissions
- **TLS Encryption**: Secure communication channels
- **Network Security**: Proper firewall and access controls

## Configuration Options

### Bicep Parameters
Customize the deployment by modifying parameters in `main.bicep`:

```bicep
param location string = 'eastus'
param resourcePrefix string = 'iotupdate'
param iotHubSku string = 'S1'
param vmSize string = 'Standard_B2s'
param enableMonitoring bool = true
param vmAdminUsername string = 'azureuser'
```

### Terraform Variables
Customize the deployment by modifying `terraform.tfvars`:

```hcl
location = "eastus"
resource_group_name = "rg-iot-updates"
resource_prefix = "iotupdate"
iot_hub_sku = "S1"
vm_size = "Standard_B2s"
enable_monitoring = true
vm_admin_username = "azureuser"
```

### Environment Variables for Scripts
Set these environment variables before running bash scripts:

```bash
export RESOURCE_GROUP="rg-iot-updates-demo"
export LOCATION="eastus"
export RESOURCE_PREFIX="iotupdate"
export IOT_HUB_SKU="S1"
export VM_SIZE="Standard_B2s"
export VM_ADMIN_USERNAME="azureuser"
```

## Post-Deployment Configuration

### Device Registration
After deployment, register your IoT devices:

```bash
# Get IoT Hub name from deployment outputs
IOT_HUB_NAME=$(az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name $DEPLOYMENT_NAME \
    --query properties.outputs.iotHubName.value -o tsv)

# Create device identity
az iot hub device-identity create \
    --hub-name $IOT_HUB_NAME \
    --device-id "your-device-id"
```

### Update Package Upload
Upload your firmware update packages:

```bash
# Get storage account name
STORAGE_ACCOUNT=$(az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name $DEPLOYMENT_NAME \
    --query properties.outputs.storageAccountName.value -o tsv)

# Upload update package
az storage blob upload \
    --account-name $STORAGE_ACCOUNT \
    --container-name updates \
    --name your-update-package.json \
    --file ./path/to/your-update-package.json
```

### Monitoring Setup
Access your monitoring dashboard:

```bash
# Get monitoring workspace ID
WORKSPACE_ID=$(az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name $DEPLOYMENT_NAME \
    --query properties.outputs.logAnalyticsWorkspaceId.value -o tsv)

echo "Log Analytics Workspace ID: $WORKSPACE_ID"
```

## Validation and Testing

### Verify IoT Hub Configuration
```bash
# Check IoT Hub status
az iot hub show --name $IOT_HUB_NAME --resource-group $RESOURCE_GROUP

# List device identities
az iot hub device-identity list --hub-name $IOT_HUB_NAME
```

### Test Device Update Service
```bash
# Check Device Update account
az iot du account show \
    --account $DEVICE_UPDATE_ACCOUNT \
    --resource-group $RESOURCE_GROUP

# List available updates
az iot du update list \
    --account $DEVICE_UPDATE_ACCOUNT \
    --instance $DEVICE_UPDATE_INSTANCE
```

### Verify Update Manager Configuration
```bash
# Check VM patch compliance
az vm assess-patches \
    --name $VM_NAME \
    --resource-group $RESOURCE_GROUP

# View patch installation status
az vm install-patches \
    --name $VM_NAME \
    --resource-group $RESOURCE_GROUP \
    --maximum-duration PT2H
```

### Monitor Update Operations
```bash
# Query update logs
az monitor log-analytics query \
    --workspace $WORKSPACE_ID \
    --analytics-query "
        Update
        | where TimeGenerated > ago(1d)
        | summarize count() by Classification
    "
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Or manually delete resource group
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

### Selective Cleanup
To remove specific resources while keeping others:

```bash
# Stop VM to avoid charges
az vm deallocate --name $VM_NAME --resource-group $RESOURCE_GROUP

# Delete Logic App workflow
az logic workflow delete \
    --name "update-orchestration-workflow" \
    --resource-group $RESOURCE_GROUP

# Remove device identities
az iot hub device-identity delete \
    --hub-name $IOT_HUB_NAME \
    --device-id "your-device-id"
```

## Troubleshooting

### Common Issues

#### IoT Hub Creation Fails
- Verify subscription has available IoT Hub quota
- Check if IoT Hub name is globally unique
- Ensure proper permissions for IoT Hub creation

#### Device Update Service Errors
- Verify IoT Hub and Device Update service are in same region
- Check that Device Update account name is unique
- Ensure proper RBAC permissions for Device Update

#### Update Manager Issues
- Verify VM has proper Update Manager extension installed
- Check that VM operating system is supported
- Ensure VM has internet connectivity for patch downloads

#### Storage Account Access Denied
- Verify storage account name is globally unique
- Check RBAC permissions for storage operations
- Ensure proper authentication configuration

### Diagnostic Commands
```bash
# Check resource deployment status
az deployment group list --resource-group $RESOURCE_GROUP --output table

# View activity logs
az monitor activity-log list \
    --resource-group $RESOURCE_GROUP \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)

# Check service health
az resource list --resource-group $RESOURCE_GROUP --query "[].{Name:name,Type:type,State:properties.provisioningState}" --output table
```

## Cost Optimization

### Resource Sizing Recommendations
- **IoT Hub**: Start with S1 tier, scale based on device count and message volume
- **Storage Account**: Use Standard LRS for development, consider GRS for production
- **Virtual Machine**: Use B-series burstable VMs for development and testing
- **Log Analytics**: Set data retention based on compliance requirements

### Cost Monitoring
```bash
# Set up budget alerts
az consumption budget create \
    --resource-group $RESOURCE_GROUP \
    --budget-name "iot-updates-budget" \
    --amount 100 \
    --time-grain Monthly \
    --start-date $(date +%Y-%m-01) \
    --end-date $(date -d "+1 year" +%Y-%m-01)
```

## Security Considerations

### Network Security
- Configure IoT Hub with private endpoints for production
- Implement network security groups for VM access
- Use Azure Firewall for additional network protection

### Identity and Access Management
- Use managed identities for service-to-service authentication
- Implement least privilege access principles
- Regular review and rotation of access keys

### Data Protection
- Enable encryption at rest for all storage accounts
- Configure TLS 1.2 minimum for all communications
- Implement proper backup and retention policies

## Support and Documentation

### Azure Documentation
- [Azure IoT Device Update](https://docs.microsoft.com/en-us/azure/iot-hub-device-update/)
- [Azure Update Manager](https://docs.microsoft.com/en-us/azure/update-manager/)
- [Azure IoT Hub](https://docs.microsoft.com/en-us/azure/iot-hub/)
- [Azure Monitor](https://docs.microsoft.com/en-us/azure/azure-monitor/)

### Additional Resources
- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)
- [Azure IoT Reference Architecture](https://docs.microsoft.com/en-us/azure/architecture/reference-architectures/iot)
- [Azure Security Best Practices](https://docs.microsoft.com/en-us/azure/security/fundamentals/best-practices-and-patterns)

### Community Support
- [Azure IoT Developer Community](https://techcommunity.microsoft.com/t5/internet-of-things-iot/ct-p/IoT)
- [Stack Overflow - Azure IoT](https://stackoverflow.com/questions/tagged/azure-iot-hub)
- [GitHub - Azure IoT Samples](https://github.com/Azure-Samples/azure-iot-samples-csharp)

## Contributing

For issues with this infrastructure code, please:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Azure service documentation
4. Open an issue with detailed error information and deployment logs

---

*This infrastructure code is generated from the recipe "Unified Edge-to-Cloud Security Updates with IoT Device Update and Update Manager". For the complete implementation guide, refer to the original recipe documentation.*