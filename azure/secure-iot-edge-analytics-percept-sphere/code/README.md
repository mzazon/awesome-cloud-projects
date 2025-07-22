# Infrastructure as Code for Secure IoT Edge Analytics with Azure Percept and Sphere

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure IoT Edge Analytics with Azure Percept and Sphere".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (declarative ARM templates)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az --version` should be 2.50.0 or later)
- Appropriate Azure permissions for resource creation:
  - IoT Hub Contributor
  - Storage Account Contributor
  - Stream Analytics Contributor
  - Monitor Contributor
  - Resource Group Contributor
- Azure Sphere development kit and Azure Percept DK hardware (for complete solution)
- Visual Studio Code with Azure IoT Tools extension (recommended)
- OpenSSL for generating random suffixes
- Basic understanding of IoT protocols and edge computing concepts

### Required Azure Permissions

Your Azure account needs the following role assignments:
- `Contributor` role on the target subscription or resource group
- `IoT Hub Contributor` role for device management
- `Stream Analytics Contributor` role for analytics jobs
- `Storage Account Contributor` role for data lake storage
- `Monitoring Contributor` role for alerts and monitoring

## Quick Start

### Using Bicep

```bash
cd bicep/

# Deploy infrastructure
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query properties.outputs
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
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az resource list --resource-group rg-iot-edge-analytics-* --output table
```

## Configuration

### Environment Variables

Before deploying, set these environment variables or modify the parameter files:

```bash
# Required variables
export AZURE_LOCATION="eastus"
export ADMIN_EMAIL="admin@company.com"

# Optional variables (will be generated if not set)
export RESOURCE_GROUP_NAME="rg-iot-edge-analytics-$(openssl rand -hex 3)"
export IOT_HUB_NAME="iot-hub-$(openssl rand -hex 3)"
export STORAGE_ACCOUNT_NAME="stiot$(openssl rand -hex 3)"
```

### Bicep Parameters

Edit `bicep/parameters.json` to customize your deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "adminEmail": {
      "value": "admin@company.com"
    },
    "iotHubSku": {
      "value": "S1"
    },
    "storageAccountSku": {
      "value": "Standard_LRS"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize your deployment:

```hcl
location = "eastus"
admin_email = "admin@company.com"
iot_hub_sku = "S1"
storage_account_sku = "Standard_LRS"
```

## Architecture Overview

The IaC deploys the following Azure resources:

- **Azure IoT Hub**: Central message hub for device-to-cloud communication
- **Azure Storage Account**: Data Lake Gen2 for telemetry data storage
- **Azure Stream Analytics**: Real-time analytics and anomaly detection
- **Azure Monitor Action Group**: Email notifications for alerts
- **Azure Monitor Alerts**: Proactive monitoring rules
- **Resource Group**: Logical container for all resources

## Security Features

- **X.509 Certificate Authentication**: Secure device authentication
- **RBAC Integration**: Role-based access control for all resources
- **Network Security**: Proper network isolation and security groups
- **Encryption**: Data encryption at rest and in transit
- **Monitoring**: Comprehensive alerting and monitoring

## Cost Estimation

Approximate monthly costs for resources (East US region):

- Azure IoT Hub (S1): ~$25/month
- Azure Storage Account (LRS): ~$5/month for 100GB
- Azure Stream Analytics (1 SU): ~$80/month
- Azure Monitor Alerts: ~$1/month per alert rule
- **Total Estimated Cost**: ~$115/month

> **Note**: Costs may vary based on actual usage, region, and current Azure pricing.

## Validation

After deployment, verify the infrastructure:

### Check Resource Group

```bash
az group show --name <resource-group-name> --output table
```

### Verify IoT Hub

```bash
az iot hub show --name <iot-hub-name> --resource-group <resource-group-name> --query '{name:name,state:state,location:location}' --output table
```

### Check Stream Analytics Job

```bash
az stream-analytics job show --name <job-name> --resource-group <resource-group-name> --query '{name:name,state:jobState}' --output table
```

### Test Device Connection

```bash
# Create test device
az iot hub device-identity create --hub-name <iot-hub-name> --device-id test-device

# Send test message
az iot device send-d2c-message --hub-name <iot-hub-name> --device-id test-device --data '{"temperature":25.0,"humidity":60.0}'
```

## Cleanup

### Using Bicep

```bash
# Delete resource group and all resources
az group delete --name <resource-group-name> --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Authentication Errors**: Ensure Azure CLI is logged in with `az login`
2. **Permission Errors**: Verify your account has required Azure permissions
3. **Resource Name Conflicts**: Use unique names or let scripts generate random suffixes
4. **Location Issues**: Some resources may not be available in all regions

### Debug Commands

```bash
# Check Azure CLI authentication
az account show

# List available locations
az account list-locations --output table

# Check resource provider registration
az provider show --namespace Microsoft.Devices --query registrationState
az provider show --namespace Microsoft.StreamAnalytics --query registrationState
```

### Logs and Monitoring

```bash
# Check deployment logs
az deployment group list --resource-group <resource-group-name> --output table

# View Stream Analytics logs
az stream-analytics job show --name <job-name> --resource-group <resource-group-name> --query 'lastOutputEventTime'

# Monitor IoT Hub metrics
az monitor metrics list --resource <iot-hub-resource-id> --metric "ConnectedDeviceCount"
```

## Next Steps

After successful deployment:

1. **Configure Physical Devices**: Set up Azure Sphere and Azure Percept hardware
2. **Deploy Edge Modules**: Install IoT Edge runtime and custom modules
3. **Configure Custom Analytics**: Modify Stream Analytics queries for your use case
4. **Set Up Dashboards**: Create Azure Monitor dashboards for visualization
5. **Implement CI/CD**: Set up automated deployment pipelines

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation in the parent directory
2. Review Azure service documentation:
   - [Azure IoT Hub](https://docs.microsoft.com/en-us/azure/iot-hub/)
   - [Azure Stream Analytics](https://docs.microsoft.com/en-us/azure/stream-analytics/)
   - [Azure Percept](https://docs.microsoft.com/en-us/azure/azure-percept/)
   - [Azure Sphere](https://docs.microsoft.com/en-us/azure-sphere/)
3. Check Azure service status at [Azure Status](https://status.azure.com/)
4. Use Azure CLI help: `az iot hub --help`

## Contributing

When updating this infrastructure code:

1. Test all changes in a development environment
2. Update documentation for any new parameters or outputs
3. Ensure security best practices are maintained
4. Update cost estimates if resource configurations change
5. Validate with latest Azure CLI and Terraform versions