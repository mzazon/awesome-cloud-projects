# Infrastructure as Code for Carbon-Intelligent Manufacturing with Azure Industrial IoT and Sustainability Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Carbon-Intelligent Manufacturing with Azure Industrial IoT and Sustainability Manager".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az cli` version 2.57.0 or later)
- Appropriate Azure subscription with permissions for:
  - IoT Hub management
  - Event Grid topic creation
  - Azure Data Explorer cluster deployment
  - Function App deployment
  - Event Hub namespace creation
  - Storage account management
  - Resource group management
- For Terraform: Terraform installed (version 1.0 or later)
- For Bicep: Bicep CLI installed (latest version)

> **Important**: Azure Sustainability Manager is currently in preview and requires enrollment in the preview program. Contact your Microsoft representative for access.

## Architecture Overview

This solution deploys:
- **Azure IoT Hub**: Industrial device connectivity and management
- **Azure Data Explorer**: High-performance time-series analytics
- **Azure Event Grid**: Event-driven workflow orchestration
- **Azure Functions**: Serverless carbon calculation processing
- **Azure Event Hub**: High-throughput data ingestion
- **Azure Storage**: Function app storage requirements

## Cost Estimation

- **Development Environment**: $150-300/month
- **Production Environment**: $500-1500/month (varies by data volume and compute usage)
- **Key Cost Drivers**:
  - Data Explorer cluster (largest component)
  - IoT Hub message throughput
  - Function App execution time
  - Event Hub throughput units

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Deploy the infrastructure
cd bicep/
az deployment group create \
    --resource-group rg-smart-factory-carbon \
    --template-file main.bicep \
    --parameters location=eastus \
                 environmentName=production \
                 uniqueSuffix=$(openssl rand -hex 3)

# Verify deployment
az deployment group show \
    --resource-group rg-smart-factory-carbon \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan \
    -var="location=eastus" \
    -var="environment=production" \
    -var="resource_group_name=rg-smart-factory-carbon"

# Deploy infrastructure
terraform apply \
    -var="location=eastus" \
    -var="environment=production" \
    -var="resource_group_name=rg-smart-factory-carbon"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
az group show --name rg-smart-factory-carbon --query properties.provisioningState
```

## Configuration Options

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `environment` | Environment name (dev/test/prod) | `production` | Yes |
| `resource_group_name` | Resource group name | `rg-smart-factory-carbon` | Yes |
| `unique_suffix` | Unique suffix for resource names | Auto-generated | No |

### Advanced Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `iot_hub_sku` | IoT Hub pricing tier | `S1` |
| `data_explorer_sku` | Data Explorer cluster SKU | `Standard_D11_v2` |
| `function_app_plan` | Function App hosting plan | `consumption` |
| `event_hub_throughput` | Event Hub throughput units | `2` |

## Post-Deployment Configuration

### 1. Configure IoT Devices

```bash
# Create test device
DEVICE_ID="factory-sensor-001"
IOT_HUB_NAME="<your-iot-hub-name>"

az iot hub device-identity create \
    --hub-name ${IOT_HUB_NAME} \
    --device-id ${DEVICE_ID}

# Get device connection string
az iot hub device-identity connection-string show \
    --hub-name ${IOT_HUB_NAME} \
    --device-id ${DEVICE_ID}
```

### 2. Deploy Function Code

```bash
# Deploy carbon calculation function
FUNCTION_APP_NAME="<your-function-app-name>"
az functionapp deployment source config-zip \
    --name ${FUNCTION_APP_NAME} \
    --resource-group rg-smart-factory-carbon \
    --src function-code.zip
```

### 3. Configure Data Explorer Tables

```bash
# Create carbon monitoring table
az kusto database script create \
    --cluster-name "<your-data-explorer-cluster>" \
    --database-name "CarbonMonitoring" \
    --resource-group rg-smart-factory-carbon \
    --script-content ".create table CarbonMetrics (DeviceId: string, Timestamp: datetime, EnergyConsumption: real, ProductionUnits: int, TotalEmissions: real, EmissionsPerUnit: real)"
```

## Validation & Testing

### Verify IoT Hub Connectivity

```bash
# Send test telemetry data
az iot device send-d2c-message \
    --hub-name "<your-iot-hub-name>" \
    --device-id "factory-sensor-001" \
    --data '{"deviceId":"factory-sensor-001","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","telemetry":{"energyKwh":15.5,"productionUnits":100,"temperature":22.5,"humidity":45}}'
```

### Test Carbon Calculation Function

```bash
# Test function endpoint
curl -X POST "https://<function-app-name>.azurewebsites.net/api/ProcessCarbonData" \
    -H "Content-Type: application/json" \
    -d '{"deviceId":"test-device","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","telemetry":{"energyKwh":25.0,"productionUnits":150}}'
```

### Monitor Resource Health

```bash
# Check all resources status
az resource list \
    --resource-group rg-smart-factory-carbon \
    --query "[].{Name:name, Type:type, Status:properties.provisioningState}" \
    --output table
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-smart-factory-carbon \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy \
    -var="location=eastus" \
    -var="environment=production" \
    -var="resource_group_name=rg-smart-factory-carbon"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm resource group deletion
az group exists --name rg-smart-factory-carbon
```

## Troubleshooting

### Common Issues

1. **Azure Sustainability Manager Access**: Ensure preview program enrollment
2. **IoT Hub Message Limits**: Monitor message quotas in Azure portal
3. **Data Explorer Cluster Startup**: Allow 10-15 minutes for cluster initialization
4. **Function App Cold Start**: First execution may take longer than expected

### Monitoring and Logging

```bash
# View Function App logs
az functionapp logs tail \
    --name "<function-app-name>" \
    --resource-group rg-smart-factory-carbon

# Check Event Grid topic metrics
az monitor metrics list \
    --resource "/subscriptions/<subscription-id>/resourceGroups/rg-smart-factory-carbon/providers/Microsoft.EventGrid/topics/<topic-name>" \
    --metric "PublishSuccessCount"
```

## Security Considerations

- All resources use managed identities where possible
- Network access is restricted using Azure Private Link (in production configurations)
- IoT device certificates are managed through Azure IoT Hub
- Function App uses Azure Key Vault for sensitive configuration
- Data encryption at rest and in transit is enabled by default

## Customization

### Scaling for Production

- Increase Data Explorer cluster size based on data volume
- Configure IoT Hub scaling based on device count
- Implement Function App premium plan for consistent performance
- Add Azure Monitor alerts for sustainability thresholds

### Integration with Existing Systems

- Configure Event Grid custom topics for enterprise event routing
- Implement Azure Logic Apps for sustainability workflow automation
- Add Power BI integration for sustainability dashboards
- Configure Azure API Management for external system integration

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Azure service documentation
3. Verify prerequisite requirements
4. Contact your Azure support team for service-specific issues

## Additional Resources

- [Azure IoT Hub Documentation](https://docs.microsoft.com/en-us/azure/iot-hub/)
- [Azure Data Explorer Documentation](https://docs.microsoft.com/en-us/azure/data-explorer/)
- [Azure Sustainability Manager Documentation](https://docs.microsoft.com/en-us/azure/sustainability/)
- [Azure Industrial IoT Platform](https://docs.microsoft.com/en-us/azure/industrial-iot/)