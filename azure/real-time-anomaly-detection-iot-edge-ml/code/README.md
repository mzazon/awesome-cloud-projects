# Infrastructure as Code for Real-Time Anomaly Detection with Azure IoT Edge and Azure ML

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Anomaly Detection with Azure IoT Edge and Azure ML".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50+ installed and configured
- Azure subscription with contributor access
- Ubuntu 20.04+ VM or physical device for IoT Edge (minimum 2 vCPU, 4GB RAM)
- Appropriate permissions for creating:
  - Resource Groups
  - IoT Hubs
  - Azure Machine Learning workspaces
  - Storage Accounts
  - Stream Analytics jobs
  - Log Analytics workspaces

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Set deployment parameters
export LOCATION="eastus"
export RESOURCE_PREFIX="anomaly-$(openssl rand -hex 3)"

# Deploy infrastructure
az deployment group create \
    --resource-group "rg-${RESOURCE_PREFIX}" \
    --template-file main.bicep \
    --parameters @parameters.json \
    --parameters location=${LOCATION} \
    --parameters resourcePrefix=${RESOURCE_PREFIX}

# Register IoT Edge device
az iot hub device-identity create \
    --device-id "factory-edge-device-01" \
    --hub-name "iot-hub-${RESOURCE_PREFIX}" \
    --edge-enabled
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# Get IoT Edge device connection string
terraform output -raw iot_edge_connection_string
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration
# The script will output connection strings and configuration details
```

## Architecture Overview

The infrastructure deploys:

- **Azure IoT Hub**: Central message hub for device connectivity
- **Azure Machine Learning Workspace**: Platform for model training and deployment
- **Azure Storage Account**: Persistent storage for models and data
- **Stream Analytics Job**: Real-time data processing at the edge
- **Log Analytics Workspace**: Monitoring and diagnostics
- **Compute Instance**: Auto-scaling compute for model training

## Configuration Parameters

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "location": "eastus",
  "resourcePrefix": "anomaly-detection",
  "iotHubSku": "S1",
  "mlWorkspaceName": "ml-anomaly-detection",
  "storageAccountSku": "Standard_LRS",
  "enableDiagnostics": true
}
```

### Terraform Variables

Edit `terraform/variables.tf` or create `terraform.tfvars`:

```hcl
location = "East US"
resource_prefix = "anomaly-detection"
iot_hub_sku = "S1"
ml_workspace_name = "ml-anomaly-detection"
storage_account_replication_type = "LRS"
enable_diagnostics = true
```

### Bash Script Environment Variables

The deploy script uses these environment variables:

```bash
export LOCATION="eastus"
export RESOURCE_PREFIX="anomaly-$(openssl rand -hex 3)"
export IOT_HUB_SKU="S1"
export ML_WORKSPACE_NAME="ml-anomaly-detection"
export STORAGE_REPLICATION="Standard_LRS"
```

## Post-Deployment Steps

### 1. Configure IoT Edge Device

After infrastructure deployment, configure your edge device:

```bash
# Get connection string from outputs
CONNECTION_STRING=$(az iot hub device-identity connection-string show \
    --device-id factory-edge-device-01 \
    --hub-name iot-hub-${RESOURCE_PREFIX} \
    --query connectionString --output tsv)

# Install IoT Edge runtime on your device
curl https://packages.microsoft.com/config/ubuntu/20.04/multiarch/prod.list > ./microsoft-prod.list
sudo cp ./microsoft-prod.list /etc/apt/sources.list.d/
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo cp ./microsoft.gpg /etc/apt/trusted.gpg.d/
sudo apt-get update
sudo apt-get install aziot-edge

# Configure edge device
sudo aziotctl config apply -c '/etc/aziot/config.toml'
```

### 2. Deploy Anomaly Detection Module

```bash
# Apply edge deployment manifest
az iot edge deployment create \
    --deployment-id "anomaly-detection-deployment" \
    --hub-name iot-hub-${RESOURCE_PREFIX} \
    --content deployment-manifest.json \
    --target-condition "deviceId='factory-edge-device-01'" \
    --priority 10
```

### 3. Verify Deployment

```bash
# Check device status
az iot hub device-identity show \
    --device-id factory-edge-device-01 \
    --hub-name iot-hub-${RESOURCE_PREFIX} \
    --query "[deviceId, status, connectionState]" \
    --output table

# Check Stream Analytics job
az stream-analytics job show \
    --resource-group rg-${RESOURCE_PREFIX} \
    --name asa-edge-anomaly-job \
    --query "jobState" \
    --output tsv
```

## Monitoring and Troubleshooting

### View Logs

```bash
# IoT Hub diagnostics
az monitor log-analytics query \
    --workspace log-anomaly-detection \
    --analytics-query "IoTHubDiagnostics | limit 10"

# Stream Analytics metrics
az monitor metrics list \
    --resource /subscriptions/{subscription-id}/resourceGroups/rg-${RESOURCE_PREFIX}/providers/Microsoft.StreamAnalytics/streamingjobs/asa-edge-anomaly-job \
    --metric "InputEvents"
```

### Device Troubleshooting

```bash
# Check IoT Edge runtime status on device
sudo aziotctl system status

# View module logs
sudo aziotctl logs edgeAgent
sudo aziotctl logs edgeHub
```

## Testing the Solution

### Send Test Data

```bash
# Send anomalous sensor data
az iot device send-d2c-message \
    --hub-name iot-hub-${RESOURCE_PREFIX} \
    --device-id factory-edge-device-01 \
    --data '{"temperature": 95, "pressure": 180, "vibration": 4.5, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'

# Send normal sensor data
az iot device send-d2c-message \
    --hub-name iot-hub-${RESOURCE_PREFIX} \
    --device-id factory-edge-device-01 \
    --data '{"temperature": 72, "pressure": 120, "vibration": 1.2, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
```

### Monitor Results

```bash
# Check Stream Analytics output
az monitor log-analytics query \
    --workspace log-anomaly-detection \
    --analytics-query "AzureDiagnostics | where ResourceProvider == 'MICROSOFT.STREAMANALYTICS' | limit 20"
```

## Cleanup

### Using Bicep

```bash
# Delete resource group and all resources
az group delete --name rg-${RESOURCE_PREFIX} --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm resource deletion when prompted
```

## Cost Optimization

### Resource Scaling

- **IoT Hub**: Start with S1 tier, scale based on device count
- **ML Compute**: Use auto-scaling clusters (0 minimum instances)
- **Storage**: Implement lifecycle policies for data archival
- **Stream Analytics**: Use streaming units based on throughput needs

### Cost Monitoring

```bash
# Set up cost alerts
az consumption budget create \
    --budget-name "anomaly-detection-budget" \
    --amount 100 \
    --time-grain Monthly \
    --start-date $(date -u +%Y-%m-01) \
    --end-date $(date -u -d '+1 year' +%Y-%m-01)
```

## Security Considerations

### Network Security

- IoT Hub uses TLS 1.2 encryption
- Edge devices authenticate using X.509 certificates
- All inter-service communication encrypted in transit

### Access Control

- Use Azure Active Directory for authentication
- Implement least privilege access for service principals
- Enable Azure Policy for compliance enforcement

### Data Protection

- Enable encryption at rest for storage accounts
- Use Azure Key Vault for secrets management
- Implement data retention policies

## Customization

### Adding New Sensors

Modify the Stream Analytics query to include additional sensor types:

```sql
-- Add new sensor types to the query
SELECT
    deviceId,
    temperature,
    pressure,
    vibration,
    humidity,  -- New sensor
    rpm,       -- New sensor
    ANOMALYDETECTION(humidity) OVER (PARTITION BY deviceId LIMIT DURATION(minute, 5)) AS humidity_scores
FROM sensorInput
```

### Custom ML Models

Replace the pre-built anomaly detector with custom models:

1. Train custom model in Azure ML workspace
2. Package as container image
3. Update deployment manifest with custom image
4. Deploy to edge device

### Integration with External Systems

Add webhook notifications for anomaly alerts:

```bash
# Create Logic App for notifications
az logic workflow create \
    --resource-group rg-${RESOURCE_PREFIX} \
    --name anomaly-alert-workflow \
    --definition @logic-app-definition.json
```

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../architecting-real-time-anomaly-detection-with-azure-iot-edge-and-azure-ml.md)
- [Azure IoT Edge documentation](https://docs.microsoft.com/en-us/azure/iot-edge/)
- [Azure Machine Learning documentation](https://docs.microsoft.com/en-us/azure/machine-learning/)
- [Azure Stream Analytics documentation](https://docs.microsoft.com/en-us/azure/stream-analytics/)

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate against Azure best practices
3. Update documentation accordingly
4. Submit pull requests with detailed descriptions

## License

This infrastructure code is provided under the same license as the recipe collection.