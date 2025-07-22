# Infrastructure as Code for Quantum-Enhanced Manufacturing Quality Control with Azure Quantum and Machine Learning

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Quantum-Enhanced Manufacturing Quality Control with Azure Quantum and Machine Learning".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50+ installed and configured
- Azure subscription with appropriate permissions for Quantum, Machine Learning, and IoT services
- Azure Quantum workspace access (requires special approval - see [Azure Quantum documentation](https://docs.microsoft.com/en-us/azure/quantum/))
- Terraform v1.0+ (for Terraform deployment)
- Understanding of quantum computing concepts and manufacturing processes
- Python 3.8+ with Azure SDK packages for development work
- Estimated cost: $150-250 for a 3-hour session including quantum compute time

## Architecture Overview

This solution deploys a quantum-enhanced manufacturing quality control system that combines:

- **Azure Quantum**: Quantum optimization algorithms for production parameter tuning
- **Azure Machine Learning**: Predictive models for defect detection and quality control
- **Azure IoT Hub**: Real-time data ingestion from manufacturing sensors
- **Azure Stream Analytics**: Real-time processing of quality control data
- **Azure Cosmos DB**: Real-time dashboard data storage
- **Azure Functions**: Serverless compute for dashboard APIs
- **Azure Storage**: Data lake capabilities for analytics and ML training

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone the repository and navigate to the code directory
cd azure/optimizing-manufacturing-quality-control-with-azure-quantum-and-azure-machine-learning/code

# Set deployment parameters
export RESOURCE_GROUP="rg-quantum-manufacturing-${RANDOM}"
export LOCATION="eastus"
export DEPLOYMENT_NAME="quantum-manufacturing-$(date +%s)"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure using Bicep
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json \
    --name ${DEPLOYMENT_NAME}

# Verify deployment
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment status
az resource list --resource-group ${RESOURCE_GROUP} --output table
```

## Post-Deployment Configuration

### 1. Request Azure Quantum Access

```bash
# Request access to Azure Quantum (if not already done)
# Visit: https://aka.ms/aq/preview
# This requires manual approval and may take 1-2 business days
```

### 2. Configure IoT Device Simulation

```bash
# Create IoT device identity for testing
az iot hub device-identity create \
    --hub-name $(terraform output -raw iot_hub_name) \
    --device-id "production-line-01" \
    --auth-method shared_private_key

# Send test telemetry
az iot device send-d2c-message \
    --hub-name $(terraform output -raw iot_hub_name) \
    --device-id "production-line-01" \
    --data '{"temperature": 185.5, "pressure": 2.8, "speed": 145, "quality_score": 98.5}'
```

### 3. Initialize Machine Learning Workspace

```bash
# Configure ML workspace
az ml workspace update \
    --name $(terraform output -raw ml_workspace_name) \
    --resource-group ${RESOURCE_GROUP} \
    --public-network-access Enabled

# Create compute cluster
az ml compute create \
    --name "quantum-ml-cluster" \
    --type amlcompute \
    --workspace-name $(terraform output -raw ml_workspace_name) \
    --resource-group ${RESOURCE_GROUP} \
    --min-instances 0 \
    --max-instances 4 \
    --size "Standard_DS3_v2"
```

### 4. Deploy Quality Control Models

```bash
# Upload sample training data
az ml data create \
    --name "manufacturing-quality-dataset" \
    --workspace-name $(terraform output -raw ml_workspace_name) \
    --resource-group ${RESOURCE_GROUP} \
    --type uri_folder \
    --path "azureml://datastores/workspaceblobstore/paths/quality-data/"

# Submit model training job
az ml job create \
    --file training-job.yml \
    --workspace-name $(terraform output -raw ml_workspace_name) \
    --resource-group ${RESOURCE_GROUP}
```

## Validation & Testing

### 1. Verify Core Infrastructure

```bash
# Check resource group deployment
az group show --name ${RESOURCE_GROUP} --query properties.provisioningState

# Verify Azure Quantum workspace
az quantum workspace show \
    --name $(terraform output -raw quantum_workspace_name) \
    --resource-group ${RESOURCE_GROUP}

# Check IoT Hub connectivity
az iot hub show \
    --name $(terraform output -raw iot_hub_name) \
    --query properties.state
```

### 2. Test Data Flow

```bash
# Monitor IoT Hub telemetry
az iot hub monitor-events \
    --hub-name $(terraform output -raw iot_hub_name) \
    --timeout 30

# Check Stream Analytics job status
az stream-analytics job show \
    --job-name $(terraform output -raw stream_analytics_job_name) \
    --resource-group ${RESOURCE_GROUP} \
    --query jobState
```

### 3. Validate Machine Learning Components

```bash
# Check ML workspace status
az ml workspace show \
    --name $(terraform output -raw ml_workspace_name) \
    --resource-group ${RESOURCE_GROUP} \
    --query provisioningState

# List available compute targets
az ml compute list \
    --workspace-name $(terraform output -raw ml_workspace_name) \
    --resource-group ${RESOURCE_GROUP}
```

### 4. Test Quantum Integration

```bash
# Verify quantum providers
az quantum workspace provider list \
    --workspace-name $(terraform output -raw quantum_workspace_name) \
    --resource-group ${RESOURCE_GROUP}

# Test quantum optimization (Python script)
python3 -c "
from azure.quantum import Workspace
workspace = Workspace(
    subscription_id='$(az account show --query id -o tsv)',
    resource_group='${RESOURCE_GROUP}',
    name='$(terraform output -raw quantum_workspace_name)',
    location='${LOCATION}'
)
print('Quantum workspace connection successful')
"
```

## Monitoring and Troubleshooting

### Common Issues

1. **Quantum Workspace Access Denied**
   - Ensure you have requested and received approval for Azure Quantum preview
   - Check that your subscription is approved for quantum services

2. **IoT Hub Connection Issues**
   - Verify device identity is properly created
   - Check connection string configuration
   - Ensure IoT Hub is in the correct region

3. **Machine Learning Compute Errors**
   - Verify quota availability for ML compute instances
   - Check that workspace is properly configured
   - Ensure storage account permissions are correct

### Monitoring Commands

```bash
# Monitor resource health
az resource list \
    --resource-group ${RESOURCE_GROUP} \
    --query "[].{Name:name,Type:type,Location:location,Status:properties.provisioningState}" \
    --output table

# Check activity logs
az monitor activity-log list \
    --resource-group ${RESOURCE_GROUP} \
    --max-events 10 \
    --output table

# Monitor costs
az consumption usage list \
    --billing-period-name $(az billing period show --query name -o tsv) \
    --top 10
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait

# Verify deletion
az group exists --name ${RESOURCE_GROUP}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
az resource list --resource-group ${RESOURCE_GROUP} --output table
```

## Customization

### Key Variables

#### Bicep Parameters (`bicep/parameters.json`)
- `location`: Azure region for deployment
- `resourcePrefix`: Prefix for all resource names
- `quantumWorkspaceName`: Name for the quantum workspace
- `mlWorkspaceName`: Name for the ML workspace
- `iotHubName`: Name for the IoT Hub
- `streamAnalyticsJobName`: Name for the Stream Analytics job

#### Terraform Variables (`terraform/variables.tf`)
- `resource_group_name`: Resource group name
- `location`: Azure region
- `tags`: Common tags for all resources
- `quantum_workspace_name`: Quantum workspace name
- `ml_workspace_name`: ML workspace name
- `iot_hub_sku`: IoT Hub pricing tier
- `stream_analytics_streaming_units`: Stream Analytics capacity

### Environment-Specific Configuration

#### Development Environment
```bash
# Use smaller instance sizes
export VM_SIZE="Standard_B2s"
export IOT_HUB_SKU="S1"
export STREAM_ANALYTICS_UNITS="1"
```

#### Production Environment
```bash
# Use production-optimized settings
export VM_SIZE="Standard_DS3_v2"
export IOT_HUB_SKU="S2"
export STREAM_ANALYTICS_UNITS="3"
```

## Security Considerations

### Default Security Features

- **Azure Key Vault**: Secure storage for connection strings and secrets
- **Managed Identity**: Service-to-service authentication without credentials
- **Network Security**: Private endpoints for sensitive services
- **RBAC**: Role-based access control for all resources
- **Encryption**: Data encryption at rest and in transit

### Additional Security Hardening

```bash
# Enable diagnostic logging
az monitor diagnostic-settings create \
    --name "quantum-manufacturing-diagnostics" \
    --resource $(terraform output -raw quantum_workspace_id) \
    --logs '[{"category": "Microsoft.Quantum/Workspaces/Jobs", "enabled": true}]' \
    --storage-account $(terraform output -raw storage_account_name)

# Configure network restrictions
az ml workspace update \
    --name $(terraform output -raw ml_workspace_name) \
    --resource-group ${RESOURCE_GROUP} \
    --public-network-access Disabled
```

## Performance Optimization

### Quantum Optimization
- Use quantum simulators for development and testing
- Reserve quantum hardware time for production workloads
- Implement quantum error mitigation techniques

### Machine Learning Optimization
- Use GPU-enabled compute instances for model training
- Implement model caching and versioning
- Configure auto-scaling for compute clusters

### IoT and Streaming Optimization
- Configure IoT Hub partitioning for high throughput
- Use Stream Analytics windowing for real-time aggregation
- Implement data compression for network efficiency

## Cost Management

### Cost Optimization Tips

1. **Quantum Services**: Use simulators for development, reserve hardware for production
2. **ML Compute**: Configure auto-scaling with appropriate min/max instances
3. **IoT Hub**: Choose appropriate pricing tier based on message volume
4. **Storage**: Use lifecycle policies for data archiving

### Cost Monitoring

```bash
# Set up cost alerts
az consumption budget create \
    --budget-name "quantum-manufacturing-budget" \
    --amount 500 \
    --time-grain Monthly \
    --time-period-start $(date -d "first day of this month" +%Y-%m-01) \
    --time-period-end $(date -d "last day of this month" +%Y-%m-%d)
```

## Support and Documentation

### Official Documentation
- [Azure Quantum Documentation](https://docs.microsoft.com/en-us/azure/quantum/)
- [Azure Machine Learning Documentation](https://docs.microsoft.com/en-us/azure/machine-learning/)
- [Azure IoT Hub Documentation](https://docs.microsoft.com/en-us/azure/iot-hub/)
- [Azure Stream Analytics Documentation](https://docs.microsoft.com/en-us/azure/stream-analytics/)

### Community Resources
- [Azure Quantum GitHub](https://github.com/Microsoft/Quantum)
- [Azure Machine Learning Examples](https://github.com/Azure/MachineLearningNotebooks)
- [Azure IoT Samples](https://github.com/Azure/azure-iot-sdk-c)

### Support Channels
- Azure Support Portal for technical issues
- Stack Overflow for community support
- Azure Quantum Community for quantum-specific questions

For issues with this infrastructure code, refer to the original recipe documentation or the provider's documentation.