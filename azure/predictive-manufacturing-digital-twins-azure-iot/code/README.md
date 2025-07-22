# Infrastructure as Code for Predictive Manufacturing Digital Twins with Azure IoT Hub and Digital Twins

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Predictive Manufacturing Digital Twins with Azure IoT Hub and Digital Twins".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50+ installed and configured
- Azure subscription with appropriate permissions for:
  - Azure Digital Twins
  - Azure IoT Hub
  - Azure Time Series Insights
  - Azure Machine Learning
  - Azure Storage
  - Resource Group management
- For Terraform: Terraform v1.0+ installed
- For Python simulation: Python 3.8+ with pip

### Required Azure Permissions

Your Azure account needs the following role assignments:
- `Contributor` or `Owner` on the target subscription/resource group
- `Azure Digital Twins Data Owner` (will be assigned during deployment)

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Review and customize parameters
cp parameters.json.example parameters.json
# Edit parameters.json with your specific values

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters @parameters.json

# Note: Resource group will be created if it doesn't exist
```

### Using Terraform

```bash
# Navigate to terraform directory
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

# Deploy the complete solution
./scripts/deploy.sh

# Follow the interactive prompts to configure your deployment
```

## Architecture Overview

This IaC deployment creates:

- **Azure IoT Hub** (Standard S1 tier) for device connectivity and message routing
- **Azure Digital Twins** instance with DTDL models for manufacturing equipment
- **Azure Time Series Insights** Gen2 environment for telemetry analytics
- **Azure Machine Learning** workspace for predictive maintenance models
- **Azure Storage Account** with hierarchical namespace for TSI storage
- **IoT Device registrations** for manufacturing equipment simulation
- **RBAC assignments** for proper access control

## Configuration Options

### Bicep Parameters

Key parameters you can customize in `parameters.json`:

```json
{
  "resourceGroupName": "rg-manufacturing-twins",
  "location": "eastus",
  "resourcePrefix": "mfg",
  "iotHubSku": "S1",
  "timeSeriesWarmStoreDays": 7,
  "enableSimulation": true,
  "tags": {
    "environment": "demo",
    "purpose": "smart-manufacturing"
  }
}
```

### Terraform Variables

Customize your deployment by setting these variables in `terraform.tfvars`:

```hcl
resource_group_name = "rg-manufacturing-twins"
location           = "East US"
resource_prefix    = "mfg"
iot_hub_sku       = "S1"
tsi_warm_store_days = 7
enable_simulation  = true

tags = {
  environment = "demo"
  purpose     = "smart-manufacturing"
}
```

## Post-Deployment Steps

After successful infrastructure deployment:

1. **Start Device Simulation** (if enabled):
   ```bash
   # The deployment will output device connection strings
   # Use these to run the provided Python simulation script
   python scripts/simulate_manufacturing_devices.py
   ```

2. **Access Azure Digital Twins Explorer**:
   - Navigate to your Digital Twins instance in Azure Portal
   - Use the Digital Twins Explorer to visualize your twin graph
   - Query twins and relationships using the query interface

3. **Configure Time Series Insights**:
   - Access TSI Explorer through Azure Portal
   - Create time series queries to analyze equipment telemetry
   - Set up alerts for anomaly detection

4. **Set Up Machine Learning Models**:
   - Open Azure Machine Learning Studio
   - Import manufacturing telemetry data
   - Create automated ML experiments for predictive maintenance

## Validation

Verify your deployment with these commands:

```bash
# Check IoT Hub status
az iot hub show --name <your-iot-hub-name> --resource-group <your-rg>

# Verify Digital Twins instance
az dt show --dt-name <your-dt-name> --resource-group <your-rg>

# List digital twin models
az dt model list --dt-name <your-dt-name>

# Check Time Series Insights environment
az tsi environment show --environment-name <your-tsi-name> --resource-group <your-rg>

# Monitor IoT Hub messages (if simulation is running)
az iot hub monitor-events --hub-name <your-iot-hub-name> --timeout 30
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name <your-resource-group> --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
# Follow prompts to confirm resource deletion
```

## Cost Considerations

**Estimated daily costs for demo environment:**
- IoT Hub (S1): ~$25/month
- Digital Twins: ~$0.35/1000 operations
- Time Series Insights: ~$1/GB stored
- Machine Learning: ~$0 (free tier available)
- Storage: ~$0.024/GB/month

**Total estimated cost: $150-300 for 24-hour testing period**

> **Important**: Remember to clean up resources after testing to avoid ongoing charges.

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**:
   ```bash
   # Verify your Azure CLI login and permissions
   az account show
   az role assignment list --assignee $(az account show --query user.name -o tsv)
   ```

2. **Resource Name Conflicts**:
   - Digital Twins and IoT Hub names must be globally unique
   - Modify the `resourcePrefix` parameter to ensure uniqueness

3. **Location Availability**:
   - Not all Azure services are available in all regions
   - Use `az account list-locations` to verify service availability

4. **Digital Twins RBAC Issues**:
   ```bash
   # Manually assign Digital Twins Data Owner role if needed
   az role assignment create \
       --role "Azure Digital Twins Data Owner" \
       --assignee $(az account show --query user.name -o tsv) \
       --scope "/subscriptions/<subscription-id>/resourceGroups/<rg>/providers/Microsoft.DigitalTwins/digitalTwinsInstances/<dt-name>"
   ```

### Getting Help

- Check the [original recipe documentation](../orchestrating-smart-manufacturing-digital-twins-with-azure-iot-hub-and-azure-digital-twins.md)
- Review [Azure Digital Twins documentation](https://docs.microsoft.com/en-us/azure/digital-twins/)
- Consult [Azure IoT Hub documentation](https://docs.microsoft.com/en-us/azure/iot-hub/)
- Visit [Azure Time Series Insights documentation](https://docs.microsoft.com/en-us/azure/time-series-insights/)

## Security Best Practices

This IaC implementation follows Azure security best practices:

- **Least Privilege Access**: RBAC roles are assigned with minimal required permissions
- **Secure Communication**: All services use HTTPS/TLS encryption
- **Network Security**: Default network security rules are applied
- **Key Management**: Service-managed keys are used for encryption at rest
- **Identity Management**: Azure AD integration for authentication

## Extending the Solution

Consider these enhancements for production deployments:

1. **Private Endpoints**: Configure private networking for enhanced security
2. **Azure Monitor**: Add comprehensive monitoring and alerting
3. **Azure Key Vault**: Store sensitive configuration in Key Vault
4. **CI/CD Integration**: Implement automated deployment pipelines
5. **Multi-Environment**: Create separate deployments for dev/test/prod

## Support

For issues with this infrastructure code:
1. Review the troubleshooting section above
2. Check Azure service status at [Azure Status](https://status.azure.com/)
3. Consult the original recipe documentation
4. Review Azure provider documentation for Terraform issues
5. Check Azure Bicep documentation for template issues

## Contributing

To improve this IaC implementation:
1. Test thoroughly in a development environment
2. Follow Azure naming conventions and best practices
3. Update documentation for any changes
4. Ensure backward compatibility where possible