# Infrastructure as Code for Predictive Maintenance with IoT Edge Analytics

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Predictive Maintenance with IoT Edge Analytics".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login` completed)
- Azure subscription with Contributor access
- Physical IoT Edge device or Ubuntu VM (18.04 or later) with at least 2GB RAM
- Docker installed on the edge device (automatically installed with IoT Edge runtime)
- For Terraform: Terraform v1.0+ installed
- For Bicep: Azure CLI v2.20.0+ (includes Bicep)
- Appropriate permissions for creating IoT Hub, Storage, Stream Analytics, and monitoring resources

## Solution Overview

This infrastructure deploys a complete edge-based predictive maintenance solution that:

- Processes sensor data locally on industrial equipment using Azure IoT Edge
- Performs real-time anomaly detection with Stream Analytics
- Sends alerts through Azure Monitor for maintenance notifications
- Archives historical telemetry data in Azure Storage
- Operates effectively even with intermittent cloud connectivity

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-predictive-maintenance \
    --template-file main.bicep \
    --parameters @parameters.json

# Configure IoT Edge device (replace with your device)
DEVICE_CONNECTION_STRING=$(az iot hub device-identity connection-string show \
    --device-id edge-device-01 \
    --hub-name $(az deployment group show \
        --resource-group rg-predictive-maintenance \
        --name main \
        --query properties.outputs.iotHubName.value -o tsv) \
    --query connectionString -o tsv)

echo "Configure your IoT Edge device with this connection string:"
echo "${DEVICE_CONNECTION_STRING}"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Get the device connection string
terraform output iot_edge_connection_string
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output the IoT Edge device connection string
```

## Configuration Parameters

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
    "environmentName": {
      "value": "demo"
    },
    "deviceId": {
      "value": "edge-device-01"
    },
    "alertEmailAddress": {
      "value": "maint@example.com"
    },
    "alertPhoneNumber": {
      "value": "+15551234567"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize your deployment:

```hcl
location = "East US"
environment = "demo"
device_id = "edge-device-01"
alert_email = "maint@example.com"
alert_phone = "+15551234567"
```

## Deployment Architecture

The infrastructure creates:

1. **IoT Hub** (Standard S1) - Device management and message routing
2. **Stream Analytics Job** - Edge-deployed anomaly detection
3. **Storage Account** - Telemetry archival and Stream Analytics artifacts
4. **Log Analytics Workspace** - Monitoring and diagnostics
5. **Action Groups** - Alert notifications via email and SMS
6. **Metric Alerts** - Automated alerting for high message volumes
7. **IoT Edge Device Identity** - Secure device authentication

## Post-Deployment Setup

### 1. Configure IoT Edge Device

After deployment, configure your IoT Edge device with the connection string:

```bash
# On your IoT Edge device, install the IoT Edge runtime
curl https://packages.microsoft.com/config/ubuntu/18.04/multiarch/prod.list > ./microsoft-prod.list
sudo cp ./microsoft-prod.list /etc/apt/sources.list.d/
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo cp ./microsoft.gpg /etc/apt/trusted.gpg.d/
sudo apt-get update
sudo apt-get install iotedge

# Configure with your connection string
sudo iotedge config mp --connection-string "YOUR_CONNECTION_STRING"
sudo iotedge config apply
```

### 2. Deploy Edge Modules

The infrastructure includes a deployment manifest that will automatically deploy:

- **SimulatedTemperatureSensor** - For testing and demonstration
- **Stream Analytics Module** - Real-time anomaly detection
- **Message routing** - Proper data flow between modules

### 3. Monitor the Solution

```bash
# Check device status
az iot hub device-identity show \
    --device-id edge-device-01 \
    --hub-name YOUR_HUB_NAME

# Monitor telemetry
az iot hub monitor-events \
    --hub-name YOUR_HUB_NAME \
    --device-id edge-device-01

# Check Stream Analytics job status
az stream-analytics job show \
    --name YOUR_SA_JOB_NAME \
    --resource-group rg-predictive-maintenance
```

## Anomaly Detection Logic

The Stream Analytics job monitors temperature readings and triggers alerts when:

- **Average temperature** exceeds 75°C in any 30-second window
- **Maximum temperature** exceeds 85°C in any 30-second window

These thresholds can be customized in the Stream Analytics query after deployment.

## Cost Considerations

Estimated monthly costs for this solution:

- IoT Hub (S1): ~$25
- Stream Analytics (1 SU): ~$80
- Storage Account: ~$5
- Log Analytics: ~$10
- **Total**: ~$120/month

> **Note**: Costs may vary based on usage patterns and region. The edge processing approach significantly reduces data transmission costs compared to cloud-only solutions.

## Security Features

- **Device Authentication**: X.509 certificates or symmetric keys
- **Data Encryption**: TLS 1.2 for all communications
- **Access Control**: Azure AD integration for management operations
- **Network Security**: Private endpoints and firewall rules
- **Audit Logging**: Complete audit trail in Azure Monitor

## Troubleshooting

### Common Issues

1. **Module deployment fails**:
   ```bash
   # Check edge agent logs
   sudo iotedge logs edgeAgent
   
   # Check edge hub logs
   sudo iotedge logs edgeHub
   ```

2. **Stream Analytics job not starting**:
   ```bash
   # Check job status and errors
   az stream-analytics job show \
       --name YOUR_SA_JOB_NAME \
       --resource-group rg-predictive-maintenance \
       --query "{state: jobState, errors: lastOutputEventTimestamp}"
   ```

3. **No telemetry data**:
   ```bash
   # Verify device connectivity
   az iot hub device-identity show \
       --device-id edge-device-01 \
       --hub-name YOUR_HUB_NAME \
       --query connectionState
   ```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-predictive-maintenance \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

## Customization

### Extending the Solution

1. **Add Real Sensors**: Replace SimulatedTemperatureSensor with actual industrial sensor modules
2. **Custom Analytics**: Modify the Stream Analytics query for your specific use case
3. **Additional Alerts**: Add more sophisticated alerting rules in Azure Monitor
4. **Machine Learning**: Integrate Azure ML modules for advanced predictive capabilities
5. **Visualization**: Connect to Power BI for real-time dashboards

### Production Considerations

- Use Azure Key Vault for secrets management
- Implement proper backup and disaster recovery
- Set up proper network segmentation
- Configure Azure Security Center monitoring
- Implement proper logging and monitoring strategies

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for detailed explanations
2. Review Azure IoT Edge documentation: https://docs.microsoft.com/en-us/azure/iot-edge/
3. Consult Stream Analytics documentation: https://docs.microsoft.com/en-us/azure/stream-analytics/
4. Check Azure Monitor documentation: https://docs.microsoft.com/en-us/azure/azure-monitor/

## License

This infrastructure code is provided as-is under the MIT License. See the recipe documentation for full terms and conditions.