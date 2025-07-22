# Infrastructure as Code for Precision Agriculture Analytics with AI-Driven Insights

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Precision Agriculture Analytics with AI-Driven Insights".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.40.0 or higher installed and configured
- Azure subscription with appropriate permissions for creating resources
- Access to Azure Data Manager for Agriculture preview (requires approval)
- For Terraform: Terraform v1.0+ installed
- For Bicep: Bicep CLI installed (included with Azure CLI v2.20.0+)
- Appropriate permissions for:
  - Creating resource groups
  - Deploying Azure Data Manager for Agriculture instances
  - Creating IoT Hub and Stream Analytics jobs
  - Creating Azure AI Services and Azure Maps accounts
  - Creating Storage accounts and Function Apps

> **Note**: Azure Data Manager for Agriculture is currently in preview and requires registration approval. Submit your access request using the [preview registration form](https://aka.ms/agridatamanager) before beginning deployment.

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to the bicep directory
cd bicep/

# Set your parameters
RESOURCE_GROUP="rg-precision-ag-$(openssl rand -hex 3)"
LOCATION="eastus"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Deploy the infrastructure
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters location=$LOCATION \
    --parameters resourceNameSuffix=$(openssl rand -hex 3)
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Enter 'yes' when prompted to confirm deployment
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure deployment parameters
```

## Deployment Configuration

### Bicep Parameters

The Bicep template accepts the following parameters:

- `location`: Azure region for resource deployment (default: East US)
- `resourceNameSuffix`: Unique suffix for resource names (auto-generated if not provided)
- `admaInstanceSku`: SKU for Azure Data Manager for Agriculture (default: Standard)
- `iotHubSku`: SKU for IoT Hub (default: S1)
- `storageAccountSku`: Storage account SKU (default: Standard_LRS)
- `aiServicesSku`: Azure AI Services SKU (default: S0)
- `mapsAccountSku`: Azure Maps account SKU (default: S1)

### Terraform Variables

Key variables in `terraform/variables.tf`:

- `resource_group_name`: Name of the resource group
- `location`: Azure region for deployment
- `resource_name_suffix`: Unique suffix for resource names
- `tags`: Tags to apply to all resources
- `enable_advanced_analytics`: Enable advanced AI analytics features

### Environment Variables

Set these environment variables before deployment:

```bash
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_TENANT_ID="your-tenant-id"
export AZURE_CLIENT_ID="your-client-id"           # For service principal auth
export AZURE_CLIENT_SECRET="your-client-secret"   # For service principal auth
```

## Post-Deployment Configuration

After infrastructure deployment, complete these setup steps:

1. **Configure Farm and Field Entities**:
   ```bash
   # Get Data Manager endpoint from deployment outputs
   ADMA_ENDPOINT=$(az deployment group show \
       --resource-group $RESOURCE_GROUP \
       --name main \
       --query properties.outputs.admaEndpoint.value -o tsv)
   
   # Create sample farm entity
   curl -X POST "${ADMA_ENDPOINT}/farmers/demo-farm" \
       -H "Content-Type: application/json" \
       -H "Authorization: Bearer $(az account get-access-token --query accessToken -o tsv)" \
       -d '{
         "name": "Demo Precision Farm",
         "description": "Sample farm for precision agriculture analytics",
         "status": "Active"
       }'
   ```

2. **Configure IoT Device**:
   ```bash
   # Get IoT Hub name from outputs
   IOT_HUB_NAME=$(az deployment group show \
       --resource-group $RESOURCE_GROUP \
       --name main \
       --query properties.outputs.iotHubName.value -o tsv)
   
   # Create sample IoT device
   az iot hub device-identity create \
       --hub-name $IOT_HUB_NAME \
       --device-id soil-sensor-field-01
   ```

3. **Start Stream Analytics Job**:
   ```bash
   # Get Stream Analytics job name
   STREAM_JOB_NAME=$(az deployment group show \
       --resource-group $RESOURCE_GROUP \
       --name main \
       --query properties.outputs.streamAnalyticsJobName.value -o tsv)
   
   # Start the job
   az stream-analytics job start \
       --resource-group $RESOURCE_GROUP \
       --name $STREAM_JOB_NAME
   ```

## Validation

### Verify Deployment Success

```bash
# Check all resources are deployed
az resource list --resource-group $RESOURCE_GROUP --output table

# Verify Azure Data Manager for Agriculture
az datamgr-for-agriculture show \
    --resource-group $RESOURCE_GROUP \
    --name $(az deployment group show \
        --resource-group $RESOURCE_GROUP \
        --name main \
        --query properties.outputs.admaInstanceName.value -o tsv)

# Test IoT Hub connectivity
az iot hub device-identity show \
    --hub-name $IOT_HUB_NAME \
    --device-id soil-sensor-field-01
```

### Send Test Data

```bash
# Send sample sensor data
az iot device simulate \
    --hub-name $IOT_HUB_NAME \
    --device-id soil-sensor-field-01 \
    --data '{
      "deviceId": "soil-sensor-field-01",
      "soilMoisture": 65.4,
      "soilTemperature": 18.2,
      "location": {"lat": 41.8781, "lon": -87.6298}
    }' \
    --msg-count 3
```

## Monitoring and Operations

### View Resource Metrics

```bash
# Monitor IoT Hub message throughput
az monitor metrics list \
    --resource $IOT_HUB_NAME \
    --resource-group $RESOURCE_GROUP \
    --resource-type "Microsoft.Devices/IotHubs" \
    --metric "d2c.telemetry.ingress.allProtocol"

# Check Stream Analytics job status
az stream-analytics job show \
    --resource-group $RESOURCE_GROUP \
    --name $STREAM_JOB_NAME \
    --query "jobState"
```

### Access Logs

```bash
# View Function App logs
az webapp log tail \
    --resource-group $RESOURCE_GROUP \
    --name $(az deployment group show \
        --resource-group $RESOURCE_GROUP \
        --name main \
        --query properties.outputs.functionAppName.value -o tsv)
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Steps

If automated cleanup fails, manually remove resources in this order:

1. Stop Stream Analytics job
2. Delete Function App
3. Delete Azure Data Manager for Agriculture instance
4. Delete IoT Hub
5. Delete AI Services and Maps accounts
6. Delete Storage account
7. Delete resource group

```bash
# Stop Stream Analytics job first
az stream-analytics job stop \
    --resource-group $RESOURCE_GROUP \
    --name $STREAM_JOB_NAME

# Then delete the resource group
az group delete --name $RESOURCE_GROUP --yes
```

## Customization

### Modifying Resource Configuration

1. **Bicep**: Edit `bicep/main.bicep` and adjust resource properties
2. **Terraform**: Modify variables in `terraform/variables.tf`
3. **Scripts**: Update environment variables in `scripts/deploy.sh`

### Adding Additional Services

To extend the solution with additional Azure services:

1. Add the service configuration to your chosen IaC template
2. Update the deployment scripts with necessary configuration
3. Modify the validation steps to include the new service
4. Update cleanup procedures

### Environment-Specific Configurations

Create parameter files for different environments:

```bash
# Development environment
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters @parameters.dev.json

# Production environment
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters @parameters.prod.json
```

## Cost Management

### Estimated Costs

- Azure Data Manager for Agriculture: ~$50/month (Standard tier)
- IoT Hub S1: ~$25/month
- Stream Analytics: ~$80/month (1 SU)
- AI Services: ~$1-10/month (depending on usage)
- Storage Account: ~$5-20/month (depending on data volume)
- Function App: ~$0-15/month (consumption plan)
- Azure Maps: ~$0-50/month (depending on usage)

**Total estimated monthly cost: $161-250**

### Cost Optimization

```bash
# Monitor costs
az consumption usage list \
    --start-date $(date -d "30 days ago" +%Y-%m-%d) \
    --end-date $(date +%Y-%m-%d)

# Set up budget alerts
az consumption budget create \
    --budget-name precision-ag-budget \
    --amount 200 \
    --resource-group $RESOURCE_GROUP
```

## Troubleshooting

### Common Issues

1. **Azure Data Manager for Agriculture Access Denied**:
   - Ensure you have preview access approval
   - Verify correct Azure subscription

2. **IoT Hub Connection Issues**:
   - Check device connection string
   - Verify IoT Hub endpoint configuration

3. **Stream Analytics Job Failures**:
   - Review job query syntax
   - Check input/output configurations

4. **Function App Deployment Errors**:
   - Verify storage account accessibility
   - Check function app runtime configuration

### Debugging Commands

```bash
# Check deployment logs
az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name main \
    --query properties.error

# View activity logs
az monitor activity-log list \
    --resource-group $RESOURCE_GROUP \
    --start-time $(date -d "1 hour ago" -u +%Y-%m-%dT%H:%M:%SZ)
```

## Security Considerations

- All resources use managed identity where possible
- Storage accounts have private endpoints enabled
- IoT Hub uses device certificates for authentication
- AI Services keys are stored in Key Vault
- Network security groups restrict access appropriately

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation for specific services
3. Consult Azure CLI reference for command syntax
4. Review deployment logs for specific error messages

## Additional Resources

- [Azure Data Manager for Agriculture Documentation](https://docs.microsoft.com/en-us/azure/data-manager-for-agri/)
- [Azure IoT Hub Documentation](https://docs.microsoft.com/en-us/azure/iot-hub/)
- [Azure Stream Analytics Documentation](https://docs.microsoft.com/en-us/azure/stream-analytics/)
- [Azure AI Services Documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/)
- [Azure Maps Documentation](https://docs.microsoft.com/en-us/azure/azure-maps/)