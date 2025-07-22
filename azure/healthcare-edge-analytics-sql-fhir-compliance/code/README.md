# Infrastructure as Code for Healthcare Edge Analytics with SQL Edge and FHIR Compliance

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Healthcare Edge Analytics with SQL Edge and FHIR Compliance".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM template language)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az --version` should show v2.0 or higher)
- Azure subscription with appropriate permissions for creating:
  - Resource Groups
  - IoT Hub
  - Azure Health Data Services (Health Data Services Workspace and FHIR Service)
  - Azure Functions and App Service Plans
  - Storage Accounts
  - Log Analytics Workspaces
  - Application Insights
- For Terraform: Terraform CLI installed (v1.0 or higher)
- For IoT Edge deployment: IoT Edge-capable device or VM (Ubuntu 20.04 LTS recommended)
- Estimated cost: $150-200/month for a small deployment

## Quick Start

### Using Bicep
```bash
cd bicep/

# Login to Azure
az login

# Set subscription (if needed)
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-healthcare-edge \
    --template-file main.bicep \
    --parameters @parameters.json

# Note: Create resource group first if it doesn't exist
# az group create --name rg-healthcare-edge --location eastus
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply

# When prompted, type 'yes' to confirm
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for any required parameters
# and deploy all resources automatically
```

## Architecture Components

This IaC deployment creates:

- **IoT Hub**: Central communication hub for IoT Edge devices
- **Azure Health Data Services Workspace**: Unified workspace for healthcare data services
- **FHIR Service**: Standards-compliant healthcare data storage and exchange
- **Azure Functions**: Serverless compute for alert processing and data transformation
- **Storage Account**: Backend storage for Functions and data processing
- **Log Analytics Workspace**: Centralized monitoring and diagnostics
- **Application Insights**: Application performance monitoring
- **IoT Edge Device Registration**: Pre-configured edge device for SQL Edge deployment

## Configuration Options

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
      "value": "dev"
    },
    "iotHubSku": {
      "value": "S1"
    }
  }
}
```

### Terraform Variables

Customize `terraform/terraform.tfvars`:

```hcl
location = "East US"
environment = "dev"
iot_hub_sku_name = "S1"
iot_hub_sku_capacity = 1
```

### Bash Script Configuration

The deployment script accepts environment variables:

```bash
export LOCATION="eastus"
export ENVIRONMENT="dev"
export IOT_HUB_SKU="S1"
./scripts/deploy.sh
```

## Post-Deployment Steps

After infrastructure deployment, complete these manual steps:

1. **Configure IoT Edge Runtime** on your edge device:
   ```bash
   # Get device connection string from deployment output
   EDGE_CONNECTION_STRING="<from-deployment-output>"
   
   # Configure IoT Edge
   sudo iotedge config mp --connection-string "$EDGE_CONNECTION_STRING"
   sudo iotedge config apply
   ```

2. **Deploy SQL Edge Module**:
   ```bash
   # Apply the deployment manifest
   az iot edge set-modules \
       --hub-name <iot-hub-name> \
       --device-id <edge-device-id> \
       --content deployment.json
   ```

3. **Configure FHIR Service Authentication**:
   ```bash
   # Get FHIR service URL from deployment output
   FHIR_URL="<from-deployment-output>"
   
   # Test FHIR service access
   ACCESS_TOKEN=$(az account get-access-token \
       --resource "https://azurehealthcareapis.com" \
       --query accessToken \
       --output tsv)
   
   curl -X GET "${FHIR_URL}/metadata" \
       -H "Authorization: Bearer ${ACCESS_TOKEN}"
   ```

## Validation

Verify your deployment with these commands:

```bash
# Check IoT Hub status
az iot hub show --name <iot-hub-name> --query properties.state

# Verify FHIR service
az healthcareapis service fhir show \
    --resource-group <resource-group> \
    --workspace-name <workspace-name> \
    --fhir-service-name <fhir-service-name>

# Check Function App status
az functionapp show --name <function-app-name> \
    --resource-group <resource-group> \
    --query state

# Verify Log Analytics workspace
az monitor log-analytics workspace show \
    --name <workspace-name> \
    --resource-group <resource-group>
```

## Monitoring and Troubleshooting

Access monitoring dashboards:

1. **Azure Portal**: Navigate to your resource group to view all deployed resources
2. **Log Analytics**: Query telemetry and diagnostic data
3. **Application Insights**: Monitor Function App performance
4. **IoT Hub**: View device connectivity and message routing

Common troubleshooting commands:

```bash
# Check IoT Edge device status
az iot hub device-identity show \
    --hub-name <iot-hub-name> \
    --device-id <edge-device-id> \
    --query connectionState

# View Function App logs
az webapp log tail --name <function-app-name> \
    --resource-group <resource-group>

# Query recent telemetry in Log Analytics
az monitor log-analytics query \
    --workspace <workspace-name> \
    --analytics-query "AzureDiagnostics | take 10"
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete --name rg-healthcare-edge --yes --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy

# When prompted, type 'yes' to confirm
```

### Using Bash Scripts
```bash
./scripts/destroy.sh

# Follow the prompts to confirm deletion
```

### Manual Edge Device Cleanup
If using a test VM for IoT Edge:

```bash
# Uninstall IoT Edge runtime
sudo apt-get remove --purge iotedge
sudo apt-get remove --purge moby-engine
sudo apt-get autoremove
```

## Security Considerations

This deployment implements several security best practices:

- **Managed Identities**: All services use managed identities where possible
- **RBAC**: Role-based access control for all resources
- **Network Security**: Private endpoints and network access controls
- **Encryption**: Data encryption at rest and in transit
- **HIPAA Compliance**: Health Data Services provides HIPAA-compliant infrastructure

## Cost Optimization

To minimize costs in development environments:

- Use consumption-based pricing for Azure Functions
- Choose appropriate IoT Hub tier (B1 for development, S1+ for production)
- Monitor Log Analytics data ingestion
- Clean up resources when not in use

## Important Notes

> **Warning**: Azure SQL Edge will be retired on September 30, 2025. Consider migration planning for long-term deployments. See the [Azure SQL Edge migration guide](https://docs.microsoft.com/en-us/azure/azure-sql-edge/migrate) for alternatives.

> **Note**: FHIR service requires additional configuration for production use, including proper authentication, authorization, and data governance policies.

> **Tip**: Use Azure Policy to enforce compliance and governance across your healthcare infrastructure.

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for architectural guidance
2. Refer to Azure documentation for service-specific issues
3. Use Azure support channels for platform-related problems
4. Review Terraform/Bicep documentation for IaC-specific questions

## Additional Resources

- [Azure Health Data Services Documentation](https://docs.microsoft.com/en-us/azure/healthcare-apis/)
- [Azure IoT Edge Documentation](https://docs.microsoft.com/en-us/azure/iot-edge/)
- [Azure SQL Edge Documentation](https://docs.microsoft.com/en-us/azure/azure-sql-edge/)
- [FHIR R4 Specification](http://hl7.org/fhir/R4/)
- [Azure Security Best Practices](https://docs.microsoft.com/en-us/azure/security/)