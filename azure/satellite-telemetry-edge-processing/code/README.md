# Infrastructure as Code for Satellite Telemetry Edge Processing with Azure Orbital and Azure Local

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Satellite Telemetry Edge Processing with Azure Orbital and Azure Local".

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.60.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Azure Orbital Ground Station Service (preview access required)
  - Azure Local (Azure Stack HCI)
  - Azure IoT Hub
  - Azure Event Grid
  - Azure Storage
  - Azure Functions
  - Azure Monitor and Log Analytics
- Azure Orbital preview access (contact MSAzureOrbital@microsoft.com)
- Physical Azure Local hardware deployed and configured
- Satellite registration with NORAD ID and Two-Line Element (TLE) data
- Basic understanding of satellite communications and edge computing concepts

> **Note**: Azure Orbital Ground Station is currently in preview and requires approval for access. Estimated monthly cost: $2,500-5,000 for satellite contacts, edge processing, and cloud resources.

## Quick Start

### Using Bicep
```bash
# Clone or navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-orbital-edge \
    --template-file main.bicep \
    --parameters spacecraftName=earth-obs-sat \
                 iotHubName=iot-orbital-hub \
                 eventGridTopicName=orbital-events \
                 storageAccountName=stororbital001 \
                 azureLocalName=local-edge-cluster

# Monitor deployment progress
az deployment group show \
    --resource-group rg-orbital-edge \
    --name main \
    --query properties.provisioningState
```

### Using Terraform
```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan \
    -var="spacecraft_name=earth-obs-sat" \
    -var="location=eastus" \
    -var="resource_group_name=rg-orbital-edge"

# Apply the configuration
terraform apply \
    -var="spacecraft_name=earth-obs-sat" \
    -var="location=eastus" \
    -var="resource_group_name=rg-orbital-edge"
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set environment variables
export RESOURCE_GROUP="rg-orbital-edge"
export LOCATION="eastus"
export SPACECRAFT_NAME="earth-obs-sat"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az resource list \
    --resource-group ${RESOURCE_GROUP} \
    --output table
```

## Configuration Parameters

### Bicep Parameters
- `spacecraftName`: Name for the spacecraft registration
- `iotHubName`: Name for the IoT Hub instance
- `eventGridTopicName`: Name for the Event Grid topic
- `storageAccountName`: Name for the storage account (must be globally unique)
- `azureLocalName`: Name for the Azure Local cluster
- `location`: Azure region for resource deployment
- `noradId`: NORAD ID for satellite registration
- `tleLine1`: First line of Two-Line Element data
- `tleLine2`: Second line of Two-Line Element data

### Terraform Variables
- `spacecraft_name`: Name for the spacecraft registration
- `location`: Azure region for resource deployment
- `resource_group_name`: Name of the resource group
- `iot_hub_name`: Name for the IoT Hub instance
- `event_grid_topic_name`: Name for the Event Grid topic
- `storage_account_name`: Name for the storage account
- `azure_local_name`: Name for the Azure Local cluster
- `norad_id`: NORAD ID for satellite registration
- `tle_line1`: First line of Two-Line Element data
- `tle_line2`: Second line of Two-Line Element data

## Architecture Components

The Infrastructure as Code deploys the following Azure services:

### Core Services
- **Azure Orbital Ground Station**: Managed satellite communication service
- **Azure Local**: Edge computing infrastructure with Arc-enabled Kubernetes
- **Azure IoT Hub**: Satellite telemetry ingestion and device management
- **Azure Event Grid**: Event-driven orchestration and messaging
- **Azure Storage**: Data lake for satellite imagery and telemetry archive
- **Azure Functions**: Serverless compute for data processing workflows

### Supporting Services
- **Azure Monitor**: Comprehensive monitoring and alerting
- **Log Analytics Workspace**: Centralized logging and analytics
- **Application Insights**: Application performance monitoring
- **Azure Arc**: Hybrid cloud management for edge infrastructure

### Security and Compliance
- **Azure Key Vault**: Secure storage for connection strings and keys
- **Azure Private Link**: Private connectivity for secure communication
- **Azure RBAC**: Role-based access control for service principals
- **Network Security Groups**: Network-level security controls

## Deployment Validation

### Verify Core Infrastructure
```bash
# Check resource group deployment
az group show --name ${RESOURCE_GROUP}

# Verify IoT Hub deployment
az iot hub show --name ${IOT_HUB_NAME}

# Check Event Grid topic
az eventgrid topic show \
    --name ${EVENT_GRID_TOPIC} \
    --resource-group ${RESOURCE_GROUP}

# Validate storage account
az storage account show \
    --name ${STORAGE_ACCOUNT} \
    --resource-group ${RESOURCE_GROUP}
```

### Test Satellite Communication
```bash
# Register test device in IoT Hub
az iot hub device-identity create \
    --hub-name ${IOT_HUB_NAME} \
    --device-id test-satellite-device

# Send test telemetry
az iot device send-d2c-message \
    --hub-name ${IOT_HUB_NAME} \
    --device-id test-satellite-device \
    --data '{"temperature":25.5,"altitude":408000,"velocity":7658}'

# Monitor events
az iot hub monitor-events \
    --hub-name ${IOT_HUB_NAME} \
    --timeout 60
```

### Validate Edge Processing
```bash
# Check Azure Local cluster status
az stack-hci cluster show \
    --name ${AZURE_LOCAL_NAME} \
    --resource-group ${RESOURCE_GROUP}

# Verify Kubernetes connectivity
kubectl get nodes --kubeconfig ~/.kube/azure-local-config

# Check satellite processor deployment
kubectl get pods -n orbital --kubeconfig ~/.kube/azure-local-config
```

## Post-Deployment Configuration

### Satellite Registration
1. Contact Azure Orbital team for spacecraft registration approval
2. Provide NORAD ID and current TLE data
3. Configure contact profile for your satellite's communication parameters
4. Schedule initial satellite contact for testing

### Edge Processing Setup
1. Deploy containerized satellite processing workloads to Azure Local
2. Configure data flow from IoT Hub to edge processing units
3. Set up monitoring and alerting for edge infrastructure
4. Test end-to-end data processing pipeline

### Mission Control Dashboard
1. Configure Power BI workspace for orbital operations
2. Set up real-time data connections to IoT Hub and Storage
3. Create dashboard visualizations for satellite tracking
4. Configure automated reports for mission operations

## Monitoring and Troubleshooting

### Key Metrics to Monitor
- Satellite contact success rate
- Telemetry message throughput
- Edge processing latency
- Storage capacity utilization
- Event Grid delivery success rate

### Common Issues and Solutions

#### Satellite Contact Failures
```bash
# Check ground station availability
az orbital available-ground-station list \
    --spacecraft-name ${SPACECRAFT_NAME} \
    --resource-group ${RESOURCE_GROUP}

# Verify contact profile configuration
az orbital contact-profile show \
    --name earth-obs-profile \
    --resource-group ${RESOURCE_GROUP}
```

#### IoT Hub Connection Issues
```bash
# Check IoT Hub connection status
az iot hub connection-string show \
    --hub-name ${IOT_HUB_NAME} \
    --key primary

# Verify device authentication
az iot hub device-identity show \
    --hub-name ${IOT_HUB_NAME} \
    --device-id test-satellite-device
```

#### Edge Processing Problems
```bash
# Check Azure Local cluster health
az stack-hci cluster show \
    --name ${AZURE_LOCAL_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query status

# Verify Kubernetes workload status
kubectl describe pods -n orbital --kubeconfig ~/.kube/azure-local-config
```

## Cost Optimization

### Monitoring Costs
- Use Azure Cost Management to track satellite contact charges
- Monitor storage costs for telemetry data retention
- Optimize Function App consumption based on processing patterns
- Review Event Grid usage patterns for cost efficiency

### Cost Reduction Strategies
- Implement intelligent satellite contact scheduling
- Use storage lifecycle policies for data archival
- Optimize edge processing resource allocation
- Configure auto-scaling for variable workloads

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-orbital-edge \
    --yes \
    --no-wait

# Or delete specific deployment
az deployment group delete \
    --resource-group rg-orbital-edge \
    --name main
```

### Using Terraform
```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="spacecraft_name=earth-obs-sat" \
    -var="location=eastus" \
    -var="resource_group_name=rg-orbital-edge"

# Clean up terraform state
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
az resource list \
    --resource-group ${RESOURCE_GROUP} \
    --output table
```

### Manual Cleanup (if needed)
```bash
# Cancel any scheduled satellite contacts
az orbital contact list \
    --resource-group ${RESOURCE_GROUP} \
    --query "[?status=='Scheduled'].name" \
    --output tsv | while read contact; do
    az orbital contact delete \
        --name "$contact" \
        --resource-group ${RESOURCE_GROUP} \
        --yes
done

# Disconnect Azure Arc resources
az connectedk8s delete \
    --name azure-local-k8s \
    --resource-group ${RESOURCE_GROUP} \
    --yes

# Remove Azure Local cluster
az stack-hci cluster delete \
    --name ${AZURE_LOCAL_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --yes
```

## Security Considerations

### Best Practices Implemented
- Azure Key Vault for secure credential storage
- Private endpoints for secure service communication
- Network security groups for traffic filtering
- Role-based access control (RBAC) for service principals
- Encryption at rest for all storage services
- TLS encryption for all data in transit

### Security Configuration
```bash
# Create Key Vault for secure storage
az keyvault create \
    --name kv-orbital-secrets \
    --resource-group ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --sku standard

# Store connection strings securely
az keyvault secret set \
    --vault-name kv-orbital-secrets \
    --name iot-hub-connection-string \
    --value "${IOT_CONNECTION_STRING}"

# Configure network security group rules
az network nsg rule create \
    --resource-group ${RESOURCE_GROUP} \
    --nsg-name nsg-orbital-edge \
    --name allow-satellite-traffic \
    --protocol tcp \
    --priority 1000 \
    --destination-port-ranges 22 443 8883
```

## Customization

### Extending the Solution
1. **Multi-constellation support**: Modify templates to support multiple satellite types
2. **Advanced analytics**: Add Azure Machine Learning for satellite data analysis
3. **Global deployment**: Extend to multiple Azure regions for worldwide coverage
4. **Compliance features**: Add Azure Policy for governance and compliance
5. **Disaster recovery**: Implement cross-region backup and failover

### Template Modifications
- Update Bicep parameters for different satellite configurations
- Modify Terraform variables for custom deployment scenarios
- Enhance bash scripts with additional validation and error handling
- Add environment-specific configuration files

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check Azure Orbital documentation: https://docs.microsoft.com/en-us/azure/orbital/
3. Review Azure Local documentation: https://docs.microsoft.com/en-us/azure/azure-local/
4. Contact Azure support for service-specific issues
5. Review Azure Architecture Center for best practices

## Contributing

When modifying this infrastructure code:
1. Follow Azure naming conventions
2. Maintain parameter consistency across all implementations
3. Update documentation for any changes
4. Test all modifications before deployment
5. Ensure security best practices are maintained

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Refer to your Azure subscription terms for usage rights and restrictions.