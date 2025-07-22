# Infrastructure as Code for Smart Factory Edge-to-Cloud Analytics with IoT Operations and Event Hubs

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Factory Edge-to-Cloud Analytics with IoT Operations and Event Hubs".

## Available Implementations

- **Bicep**: Azure native infrastructure as code using Bicep language
- **Terraform**: Multi-cloud infrastructure as code using HashiCorp Terraform
- **Scripts**: Bash deployment and cleanup scripts for Azure CLI

## Prerequisites

- Azure CLI v2.50+ installed and configured
- Azure subscription with Owner or Contributor permissions
- Basic understanding of Kubernetes, MQTT protocols, and manufacturing OPC UA standards
- Docker Desktop or container runtime for edge deployment simulation
- Knowledge of IoT data ingestion patterns and stream processing concepts
- Estimated cost: $50-150 per month for development environment (varies by data volume and retention)

### Tool-specific Prerequisites

#### For Bicep Deployment
- Azure CLI with Bicep extension installed
- Azure PowerShell (optional, for advanced scenarios)

#### For Terraform Deployment
- Terraform v1.0+ installed
- Azure CLI configured for authentication

#### For Bash Scripts
- Azure CLI v2.50+ with required extensions
- OpenSSL for random string generation
- Python 3.7+ with pip for telemetry simulation

## Quick Start

### Using Bicep
```bash
# Navigate to Bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-manufacturing-analytics \
    --template-file main.bicep \
    --parameters parameters.json

# Verify deployment
az deployment group show \
    --resource-group rg-manufacturing-analytics \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the solution
./scripts/deploy.sh

# Monitor deployment progress
# Follow the script output for deployment status and configuration steps
```

## Configuration Options

### Environment Variables

The following environment variables can be customized before deployment:

```bash
# Required Azure settings
export RESOURCE_GROUP="rg-manufacturing-analytics-${RANDOM_SUFFIX}"
export LOCATION="eastus"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Manufacturing analytics component names
export IOT_OPERATIONS_NAME="manufacturing-iot-ops-${RANDOM_SUFFIX}"
export EVENT_HUBS_NAMESPACE="eh-manufacturing-${RANDOM_SUFFIX}"
export EVENT_HUB_NAME="telemetry-hub"
export STREAM_ANALYTICS_JOB="sa-equipment-analytics-${RANDOM_SUFFIX}"
export ARC_CLUSTER_NAME="arc-edge-cluster-${RANDOM_SUFFIX}"
export MONITOR_WORKSPACE="law-manufacturing-${RANDOM_SUFFIX}"
```

### Bicep Parameters

Customize the deployment by modifying `bicep/parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "environment": {
      "value": "demo"
    },
    "eventHubsSkuName": {
      "value": "Standard"
    },
    "eventHubPartitionCount": {
      "value": 4
    },
    "streamAnalyticsSkuName": {
      "value": "Standard"
    }
  }
}
```

### Terraform Variables

Customize the deployment by modifying `terraform/terraform.tfvars`:

```hcl
location = "East US"
environment = "demo"
solution_name = "manufacturing-analytics"

# Event Hubs configuration
eventhubs_sku = "Standard"
eventhub_partition_count = 4
eventhub_message_retention = 3

# Stream Analytics configuration
stream_analytics_sku = "Standard"

# Monitoring configuration
log_analytics_sku = "pergb2018"
```

## Post-Deployment Steps

After successful infrastructure deployment, complete these additional configuration steps:

1. **Configure IoT Operations Data Flows**:
   ```bash
   # Apply IoT Operations configuration
   kubectl apply -f iot-operations-config.yaml
   ```

2. **Deploy Telemetry Simulation**:
   ```bash
   # Install Python dependencies
   pip install azure-eventhub azure-identity
   
   # Start telemetry simulator
   python manufacturing-telemetry-simulator.py
   ```

3. **Configure Stream Analytics Queries**:
   ```bash
   # Apply analytics queries for real-time processing
   az stream-analytics job start \
       --resource-group ${RESOURCE_GROUP} \
       --name ${STREAM_ANALYTICS_JOB}
   ```

4. **Access Manufacturing Dashboard**:
   - Navigate to Azure Portal > Dashboards
   - Open "Manufacturing Operations Dashboard"
   - Monitor real-time telemetry flow and equipment metrics

## Validation & Testing

### Verify Infrastructure Deployment

```bash
# Check Event Hubs deployment
az eventhubs namespace show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${EVENT_HUBS_NAMESPACE} \
    --query '{name:name,status:status,location:location}' \
    --output table

# Verify Stream Analytics job
az stream-analytics job show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${STREAM_ANALYTICS_JOB} \
    --query '{name:name,jobState:jobState}' \
    --output table

# Check monitoring workspace
az monitor log-analytics workspace show \
    --resource-group ${RESOURCE_GROUP} \
    --workspace-name ${MONITOR_WORKSPACE} \
    --query '{name:name,provisioningState:provisioningState}' \
    --output table
```

### Test Telemetry Pipeline

```bash
# Monitor telemetry ingestion
az monitor metrics list \
    --resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventHub/namespaces/${EVENT_HUBS_NAMESPACE}" \
    --metric IncomingMessages \
    --interval PT1M \
    --output table
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group and all resources
az group delete \
    --name rg-manufacturing-analytics \
    --yes \
    --no-wait
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Architecture Overview

This infrastructure deploys a complete edge-to-cloud manufacturing analytics solution:

### Edge Layer
- **Azure IoT Operations**: Kubernetes-native edge services for local processing
- **MQTT Broker**: Message bus for manufacturing device communications
- **Data Flows**: Real-time transformation and routing of telemetry

### Cloud Layer
- **Azure Event Hubs**: Scalable telemetry ingestion with 4 partitions
- **Azure Stream Analytics**: Real-time processing for OEE and anomaly detection
- **Azure Monitor**: Dashboards and alerts for operational visibility
- **Log Analytics**: Centralized logging and monitoring workspace

### Integration Points
- **Azure Arc**: Hybrid cloud management for edge Kubernetes clusters
- **Shared Access Policies**: Secure connectivity between edge and cloud
- **Action Groups**: Automated alerting for maintenance teams

## Security Considerations

- All communication uses encrypted channels (TLS/SSL)
- Shared Access Policies follow least privilege principles
- Resource groups provide isolation boundaries
- Network security groups restrict access to necessary ports only
- Azure Monitor provides audit logging for all operations

## Troubleshooting

### Common Issues

1. **Event Hubs Connection Errors**:
   ```bash
   # Verify connection string format
   az eventhubs eventhub authorization-rule keys list \
       --resource-group ${RESOURCE_GROUP} \
       --namespace-name ${EVENT_HUBS_NAMESPACE} \
       --eventhub-name ${EVENT_HUB_NAME} \
       --name IoTOperationsPolicy
   ```

2. **Stream Analytics Job Failures**:
   ```bash
   # Check job diagnostics
   az stream-analytics job show \
       --resource-group ${RESOURCE_GROUP} \
       --name ${STREAM_ANALYTICS_JOB} \
       --expand inputs,outputs,transformation
   ```

3. **Telemetry Simulation Issues**:
   ```bash
   # Verify Python dependencies
   pip list | grep azure
   
   # Check Event Hubs metrics
   az monitor metrics list \
       --resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventHub/namespaces/${EVENT_HUBS_NAMESPACE}" \
       --metric IncomingMessages
   ```

## Cost Management

### Estimated Monthly Costs (Development Environment)
- Event Hubs Standard: $20-40
- Stream Analytics Standard: $15-30
- Log Analytics: $10-20
- Storage and networking: $5-15
- **Total**: $50-105 per month

### Cost Optimization Tips
- Use auto-scaling features to minimize idle resource costs
- Configure appropriate retention periods for telemetry data
- Monitor usage patterns and adjust SKUs accordingly
- Implement lifecycle policies for long-term data storage

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Azure service status at [Azure Status](https://status.azure.com/)
3. Consult Azure IoT Operations documentation at [Microsoft Learn](https://learn.microsoft.com/en-us/azure/iot-operations/)
4. Review Event Hubs troubleshooting guide at [Microsoft Docs](https://learn.microsoft.com/en-us/azure/event-hubs/)

## Additional Resources

- [Azure IoT Operations Overview](https://learn.microsoft.com/en-us/azure/iot-operations/overview-iot-operations)
- [Event Hubs Performance and Scaling](https://learn.microsoft.com/en-us/azure/event-hubs/event-hubs-scalability)
- [Stream Analytics Query Language Reference](https://learn.microsoft.com/en-us/stream-analytics-query/stream-analytics-query-language-reference)
- [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/architecture/framework/)
- [Manufacturing Analytics with Azure](https://azure.microsoft.com/en-us/solutions/manufacturing/)