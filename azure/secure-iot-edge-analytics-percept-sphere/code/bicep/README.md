# Secure IoT Edge Analytics with Azure Percept and Sphere - Bicep Deployment

This directory contains Azure Bicep templates for deploying a comprehensive IoT edge analytics solution that combines Azure Percept and Azure Sphere for secure, real-time processing of industrial IoT data.

## Architecture Overview

The solution deploys the following Azure resources:

### Core IoT Infrastructure
- **Azure IoT Hub** - Central message hub for device-to-cloud and cloud-to-device messaging
- **Azure Stream Analytics** - Real-time data processing with anomaly detection
- **Azure Storage Account** - Data Lake Gen2 for telemetry data storage
- **Azure Key Vault** - Secure storage for connection strings and certificates

### Monitoring & Alerting
- **Log Analytics Workspace** - Centralized logging and monitoring
- **Application Insights** - Application performance monitoring
- **Azure Monitor Alerts** - Proactive alerting for critical events
- **Action Group** - Email notifications for alerts

### Security Features
- Hardware-level security with Azure Sphere
- X.509 certificate-based device authentication
- Encrypted data storage with customer-managed keys
- Network security with private endpoints (configurable)
- RBAC-enabled Key Vault access

## File Structure

```
bicep/
├── main.bicep                 # Main Bicep template
├── parameters.json           # Development environment parameters
├── parameters.prod.json      # Production environment parameters
└── README.md                # This file
```

## Prerequisites

Before deploying this solution, ensure you have:

1. **Azure CLI** (version 2.50.0 or later) or **Azure PowerShell**
2. **Bicep CLI** (latest version)
3. **Azure subscription** with appropriate permissions:
   - Contributor role on the target resource group
   - User Access Administrator for Key Vault role assignments
4. **Hardware devices** (for complete solution):
   - Azure Sphere development kit
   - Azure Percept DK
5. **Email address** for alert notifications

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd azure/secure-iot-edge-analytics-percept-sphere/code/bicep
```

### 2. Customize Parameters

Edit the appropriate parameters file:

```bash
# For development deployment
vi parameters.json

# For production deployment
vi parameters.prod.json
```

Key parameters to customize:
- `uniqueSuffix`: Unique identifier for your deployment (3-8 characters)
- `adminEmail`: Email address for alert notifications
- `location`: Azure region for deployment
- `environment`: Environment name (dev, test, prod)

### 3. Deploy the Solution

#### Option A: Using Azure CLI

```bash
# Create resource group
az group create --name "rg-iot-analytics-dev" --location "eastus"

# Deploy with development parameters
az deployment group create \
    --resource-group "rg-iot-analytics-dev" \
    --template-file main.bicep \
    --parameters @parameters.json

# Deploy with production parameters
az deployment group create \
    --resource-group "rg-iot-analytics-prod" \
    --template-file main.bicep \
    --parameters @parameters.prod.json
```

#### Option B: Using Azure PowerShell

```powershell
# Create resource group
New-AzResourceGroup -Name "rg-iot-analytics-dev" -Location "eastus"

# Deploy with development parameters
New-AzResourceGroupDeployment `
    -ResourceGroupName "rg-iot-analytics-dev" `
    -TemplateFile "main.bicep" `
    -TemplateParameterFile "parameters.json"
```

### 4. Verify Deployment

After deployment, verify the resources:

```bash
# List deployed resources
az resource list --resource-group "rg-iot-analytics-dev" --output table

# Check IoT Hub status
az iot hub show --name "iot-edge-dev-abc123-hub" --resource-group "rg-iot-analytics-dev"

# Verify Stream Analytics job
az stream-analytics job show --name "iot-edge-dev-abc123-stream" --resource-group "rg-iot-analytics-dev"
```

## Configuration Guide

### IoT Hub Configuration

After deployment, configure your IoT devices:

1. **Create device identities** for Azure Percept and Azure Sphere
2. **Configure device twins** with desired properties
3. **Set up routing rules** for telemetry data
4. **Enable monitoring** and diagnostics

### Stream Analytics Configuration

The template includes a pre-configured Stream Analytics query for:
- **Anomaly detection** using spike and dip detection
- **Data aggregation** in 5-minute windows
- **Filtering** for specific device types
- **Output formatting** for storage

### Storage Account Configuration

The solution creates two containers:
- `processed-telemetry`: For Stream Analytics output
- `raw-telemetry`: For direct IoT Hub routing

Data is partitioned by date and hour for efficient querying.

## Security Considerations

### Network Security
- IoT Hub uses TLS 1.2 for all communications
- Storage account requires HTTPS traffic only
- Key Vault uses RBAC for access control

### Data Protection
- Data at rest encryption using Azure-managed keys
- Data in transit encryption using TLS 1.2
- Soft delete enabled for Key Vault and storage

### Device Security
- Azure Sphere provides hardware-level security
- X.509 certificates for device authentication
- Regular security updates through Azure Sphere Security Service

## Monitoring and Alerting

The solution includes pre-configured alerts for:

1. **Stream Analytics Failures** - Runtime errors in data processing
2. **Device Connectivity** - When device count drops below threshold
3. **High Telemetry Volume** - Unusual message volume patterns
4. **Storage Capacity** - Storage account approaching capacity limits

### Custom Alerts

Add custom alerts by modifying the Bicep template:

```bicep
resource customAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'CustomAlertName'
  location: 'Global'
  properties: {
    // Alert configuration
  }
}
```

## Cost Optimization

### Development Environment
- IoT Hub: S1 tier (1 unit) - ~$25/month
- Stream Analytics: 1 streaming unit - ~$80/month
- Storage: Standard_LRS - ~$5/month
- **Total estimated cost: ~$110/month**

### Production Environment
- IoT Hub: S2 tier (2 units) - ~$400/month
- Stream Analytics: 3 streaming units - ~$240/month
- Storage: Standard_GRS - ~$10/month
- **Total estimated cost: ~$650/month**

### Cost Reduction Tips
1. Use Azure Hybrid Benefit for Windows VMs
2. Configure auto-scaling for Stream Analytics
3. Use lifecycle management for storage
4. Monitor usage with Azure Cost Management

## Troubleshooting

### Common Issues

1. **Deployment Failures**
   - Check Azure resource quotas
   - Verify permissions on resource group
   - Ensure unique suffix values

2. **IoT Hub Connection Issues**
   - Verify device connection strings
   - Check firewall rules
   - Validate certificate configuration

3. **Stream Analytics Errors**
   - Review input data format
   - Check query syntax
   - Verify output permissions

### Diagnostic Commands

```bash
# Check resource group deployment status
az deployment group list --resource-group "rg-iot-analytics-dev"

# View IoT Hub metrics
az monitor metrics list --resource "/subscriptions/.../providers/Microsoft.Devices/IotHubs/..." --metric "d2c.telemetry.ingress.success"

# Check Stream Analytics job status
az stream-analytics job show --name "..." --resource-group "..." --query "jobState"
```

## Advanced Configuration

### Custom Stream Analytics Query

Modify the Stream Analytics query in `main.bicep` to customize data processing:

```sql
-- Example: Add temperature threshold filtering
SELECT
    deviceId,
    timestamp,
    temperature,
    humidity,
    vibration
FROM IoTHubInput
WHERE temperature > 80 OR humidity > 70
```

### Additional Storage Outputs

Add more storage outputs for different data types:

```bicep
resource additionalOutput 'Microsoft.StreamAnalytics/streamingjobs/outputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'AdditionalOutput'
  properties: {
    // Output configuration
  }
}
```

## Support and Maintenance

### Regular Maintenance Tasks
1. **Monthly**: Review alert configurations and thresholds
2. **Quarterly**: Update IoT device firmware and certificates
3. **Semi-annually**: Review and optimize Stream Analytics queries
4. **Annually**: Conduct security assessment and compliance review

### Getting Help
- **Azure IoT Documentation**: https://docs.microsoft.com/azure/iot-hub/
- **Stream Analytics Documentation**: https://docs.microsoft.com/azure/stream-analytics/
- **Azure Sphere Documentation**: https://docs.microsoft.com/azure-sphere/

## License

This solution is provided under the MIT License. See LICENSE file for details.

## Contributing

Contributions are welcome! Please submit pull requests with:
- Clear description of changes
- Updated parameter files
- Testing evidence
- Documentation updates

---

**Note**: This template is designed for educational and demonstration purposes. For production deployments, conduct thorough testing and security reviews before implementation.