# Infrastructure as Code for Smart Energy Grid Analytics with Digital Twins

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Energy Grid Analytics with Digital Twins".

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code with official Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an intelligent energy grid analytics platform that combines:

- **Azure Data Manager for Energy**: OSDU-compliant data platform for energy industry data
- **Azure Digital Twins**: Live digital models of energy grid infrastructure
- **Azure AI Services**: Machine learning and cognitive analytics for predictive insights
- **Azure Time Series Insights**: Specialized time-series analytics for IoT and operational data
- **Azure IoT Hub**: Scalable IoT data ingestion and device management
- **Azure Functions**: Serverless integration and data processing
- **Azure Event Grid**: Real-time event routing and alerting
- **Azure Storage**: Persistent storage for ML models and configuration data
- **Azure Monitor**: Comprehensive monitoring and observability

## Prerequisites

- Azure CLI v2.60.0 or later installed and configured
- Azure subscription with Owner or Contributor permissions
- Understanding of energy grid operations and OSDU data standards
- Basic knowledge of digital twin concepts and DTDL modeling
- **Special Requirements**: 
  - Azure Data Manager for Energy requires special provisioning and OSDU certification
  - Contact Azure support for availability in your region and subscription enablement
  - Estimated cost: $800-1200 USD per month for production workloads

## Quick Start

### Using Bicep

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Create resource group
az group create --name rg-energy-grid-analytics --location eastus

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-energy-grid-analytics \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters environmentName=demo \
    --parameters projectName=smart-grid

# Monitor deployment progress
az deployment group show \
    --resource-group rg-energy-grid-analytics \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="location=eastus" -var="environment=demo"

# Apply the infrastructure
terraform apply -var="location=eastus" -var="environment=demo"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export RESOURCE_GROUP="rg-energy-grid-analytics"
export LOCATION="eastus"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az group show --name $RESOURCE_GROUP --query "properties.provisioningState"
```

## Configuration Parameters

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `resourceGroupName` | Name of the resource group | `rg-energy-grid-analytics` | Yes |
| `environmentName` | Environment tag (demo, dev, prod) | `demo` | Yes |
| `projectName` | Project identifier for naming | `smart-grid` | Yes |

### Advanced Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `energyDataManagerSku` | Azure Data Manager SKU | `S1` | No |
| `digitalTwinsLocation` | Digital Twins region | `eastus` | No |
| `aiServicesSku` | AI Services pricing tier | `S0` | No |
| `timeSeriesInsightsSku` | TSI environment SKU | `S1` | No |
| `iotHubSku` | IoT Hub pricing tier | `S1` | No |
| `storageAccountType` | Storage account replication | `Standard_LRS` | No |

## Post-Deployment Configuration

### 1. Configure DTDL Models

After deployment, upload the Digital Twin Definition Language models:

```bash
# Set Digital Twins instance name
DIGITAL_TWINS_INSTANCE="adt-grid-<unique-suffix>"

# Upload energy grid models
az dt model create \
    --dt-name $DIGITAL_TWINS_INSTANCE \
    --models dtdl-models/PowerGenerator.json

az dt model create \
    --dt-name $DIGITAL_TWINS_INSTANCE \
    --models dtdl-models/GridNode.json
```

### 2. Initialize Sample Data

Create sample digital twin instances:

```bash
# Create sample power generator
az dt twin create \
    --dt-name $DIGITAL_TWINS_INSTANCE \
    --dtmi "dtmi:energygrid:PowerGenerator;1" \
    --twin-id "solar-farm-01" \
    --properties '{
        "generatorType": "solar",
        "location": {"latitude": 40.7589, "longitude": -73.9851}
    }'

# Create sample grid node
az dt twin create \
    --dt-name $DIGITAL_TWINS_INSTANCE \
    --dtmi "dtmi:energygrid:GridNode;1" \
    --twin-id "substation-central" \
    --properties '{"nodeType": "substation"}'
```

### 3. Configure AI Analytics

Upload analytics configuration:

```bash
# Upload analytics configuration to storage
STORAGE_ACCOUNT="stenergy<unique-suffix>"

az storage blob upload \
    --account-name $STORAGE_ACCOUNT \
    --container-name analytics-config \
    --name analytics-config.json \
    --file analytics-config.json
```

## Monitoring and Validation

### Health Checks

Verify all components are operational:

```bash
# Check Azure Data Manager for Energy
az energy-data-service show \
    --resource-group $RESOURCE_GROUP \
    --name $ENERGY_DATA_MANAGER \
    --query "properties.provisioningState"

# Verify Digital Twins
az dt show \
    --resource-group $RESOURCE_GROUP \
    --name $DIGITAL_TWINS_INSTANCE \
    --query "provisioningState"

# Check Time Series Insights
az tsi environment show \
    --resource-group $RESOURCE_GROUP \
    --name $TIME_SERIES_INSIGHTS \
    --query "provisioningState"

# Validate AI Services
az cognitiveservices account show \
    --resource-group $RESOURCE_GROUP \
    --name $AI_SERVICES_ACCOUNT \
    --query "properties.provisioningState"
```

### Monitoring Dashboard

Access monitoring through Azure Portal:

1. Navigate to Log Analytics workspace: `law-energy-<unique-suffix>`
2. Use pre-configured queries for energy grid metrics
3. Set up alerts for critical grid operations
4. Monitor digital twin telemetry and AI analytics results

## Security Considerations

### Data Protection

- All data is encrypted at rest using Azure-managed keys
- Network traffic is secured with TLS 1.2 or higher
- Access control through Azure Active Directory integration
- Private endpoints configured for sensitive data services

### Identity and Access Management

- Managed identities used for service-to-service authentication
- Role-based access control (RBAC) for user permissions
- Least privilege principle applied to all service accounts
- Regular access reviews and permission audits

### Compliance

- OSDU data standards compliance through Azure Data Manager for Energy
- Industry-specific security controls for energy sector
- Audit logging for all data access and modifications
- Compliance monitoring through Azure Policy

## Troubleshooting

### Common Issues

1. **Azure Data Manager for Energy provisioning fails**:
   - Verify subscription has required permissions
   - Contact Azure support for OSDU certification
   - Check regional availability

2. **Digital Twins model upload errors**:
   - Validate DTDL model syntax
   - Ensure proper authentication and permissions
   - Check model dependencies and relationships

3. **Time Series Insights data ingestion issues**:
   - Verify IoT Hub connection and routing
   - Check event source configuration
   - Validate timestamp property settings

4. **AI Services authentication failures**:
   - Verify service principal permissions
   - Check managed identity configuration
   - Validate endpoint and key settings

### Diagnostic Commands

```bash
# Check resource group status
az group show --name $RESOURCE_GROUP --query "properties.provisioningState"

# Verify resource provider registrations
az provider show --namespace Microsoft.DigitalTwins --query "registrationState"
az provider show --namespace Microsoft.TimeSeriesInsights --query "registrationState"
az provider show --namespace Microsoft.CognitiveServices --query "registrationState"

# Check diagnostic logs
az monitor log-analytics workspace show \
    --resource-group $RESOURCE_GROUP \
    --workspace-name $LOG_WORKSPACE
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name rg-energy-grid-analytics --yes --no-wait

# Verify deletion
az group show --name rg-energy-grid-analytics --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="location=eastus" -var="environment=demo"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources are deleted
az group show --name $RESOURCE_GROUP --query "properties.provisioningState"
```

## Cost Optimization

### Cost Estimation

- Azure Data Manager for Energy: ~$400-600/month (S1 tier)
- Digital Twins: ~$50-100/month (based on operations)
- AI Services: ~$100-200/month (S0 tier)
- Time Series Insights: ~$50-100/month (S1 tier)
- IoT Hub: ~$25-50/month (S1 tier)
- Storage and Functions: ~$25-50/month
- **Total Estimated Monthly Cost: $800-1200**

### Cost Optimization Strategies

1. **Right-size resources**: Start with lower SKUs and scale up based on usage
2. **Use consumption-based pricing**: Leverage serverless components where possible
3. **Implement data lifecycle policies**: Archive old data to lower-cost storage tiers
4. **Monitor usage patterns**: Use Azure Cost Management for optimization insights
5. **Schedule non-production environments**: Shut down dev/test resources when not needed

## Support and Resources

### Documentation

- [Azure Data Manager for Energy Documentation](https://learn.microsoft.com/en-us/azure/energy-data-services/)
- [Azure Digital Twins Documentation](https://learn.microsoft.com/en-us/azure/digital-twins/)
- [Azure AI Services Documentation](https://learn.microsoft.com/en-us/azure/ai-services/)
- [Azure Time Series Insights Documentation](https://learn.microsoft.com/en-us/azure/time-series-insights/)

### Community and Support

- [Azure Energy & Utilities Community](https://techcommunity.microsoft.com/t5/azure-energy-utilities/ct-p/AzureEnergyUtilities)
- [Azure Digital Twins Community](https://techcommunity.microsoft.com/t5/azure-digital-twins-blog/bg-p/AzureDigitalTwinsBlog)
- [Azure AI Services Community](https://techcommunity.microsoft.com/t5/azure-ai-services-blog/bg-p/AzureAIServicesBlog)

### Additional Resources

- [OSDU Data Platform](https://osduforum.org/)
- [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/architecture/framework/)
- [Azure Energy Reference Architectures](https://learn.microsoft.com/en-us/azure/architecture/industries/energy/)

## Contributing

For issues with this infrastructure code, refer to the original recipe documentation or submit issues through the appropriate channels. Contributions and improvements are welcome following the established development guidelines.

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify security configurations for production deployments.