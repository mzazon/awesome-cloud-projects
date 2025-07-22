# Infrastructure as Code for Quantum Supply Chain Network Optimization with Azure Quantum and Digital Twins

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Quantum Supply Chain Network Optimization with Azure Quantum and Digital Twins".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.45.0 or later installed and configured
- Azure subscription with appropriate permissions for creating:
  - Quantum workspaces
  - Digital Twins instances
  - Function Apps
  - Stream Analytics jobs
  - Event Hubs
  - Cosmos DB accounts
  - Storage accounts
  - Application Insights
  - Log Analytics workspaces
- For Terraform: Terraform v1.0+ installed
- For development: Python 3.8+ with Azure SDK libraries
- Understanding of quantum computing concepts and supply chain optimization

## Cost Considerations

- **Azure Quantum**: $500-1000 USD for quantum computing resources during development/testing
- **Supporting Services**: $200-400 USD for Digital Twins, Functions, Stream Analytics, and storage
- **Total Estimated Cost**: $700-1400 USD for complete solution testing

> **Warning**: Azure Quantum pricing varies by quantum provider and algorithm complexity. Monitor usage carefully and review the [Azure Quantum pricing documentation](https://docs.microsoft.com/en-us/azure/quantum/pricing) for detailed cost estimates.

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone or navigate to the recipe directory
cd azure/quantum-supply-chain-network-optimization/code

# Set deployment parameters
export RESOURCE_GROUP="rg-quantum-supplychain-$(openssl rand -hex 3)"
export LOCATION="eastus"
export DEPLOYMENT_NAME="quantum-supplychain-deployment"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure using Bicep
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json \
    --parameters location=${LOCATION} \
    --name ${DEPLOYMENT_NAME}

# Verify deployment
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your preferred values

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-quantum-supplychain-$(openssl rand -hex 3)"
export LOCATION="eastus"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az group show --name ${RESOURCE_GROUP} --query properties.provisioningState
```

## Architecture Overview

This infrastructure deploys:

1. **Azure Quantum Workspace** - Quantum computing environment with optimization providers
2. **Azure Digital Twins** - Digital representation of supply chain network
3. **Azure Functions** - Serverless orchestration for quantum optimization workflows
4. **Azure Stream Analytics** - Real-time supply chain data processing
5. **Azure Event Hubs** - Data ingestion for IoT sensors and ERP systems
6. **Azure Cosmos DB** - Storage for optimization results and analytics
7. **Azure Monitor & Application Insights** - Comprehensive monitoring and analytics
8. **Azure Storage** - Supporting storage for functions and data

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize your deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourceNameSuffix": {
      "value": "demo"
    },
    "location": {
      "value": "eastus"
    },
    "quantumProviders": {
      "value": ["microsoft-qio", "1qbit"]
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize your deployment:

```hcl
resource_group_name = "rg-quantum-supplychain-demo"
location           = "East US"
resource_suffix    = "demo"
environment        = "dev"

# Quantum configuration
quantum_providers = ["microsoft-qio", "1qbit"]

# Function App configuration
function_app_runtime = "python"
function_app_version = "3.9"

# Tags
tags = {
  Environment = "demo"
  Project     = "quantum-supply-chain"
  Purpose     = "optimization"
}
```

### Environment Variables

The scripts automatically set up these environment variables:

```bash
export RESOURCE_GROUP="rg-quantum-supplychain-${RANDOM_SUFFIX}"
export LOCATION="eastus"
export QUANTUM_WORKSPACE="quantum-workspace-${RANDOM_SUFFIX}"
export DIGITAL_TWINS_INSTANCE="dt-supplychain-${RANDOM_SUFFIX}"
export FUNCTION_APP="func-optimizer-${RANDOM_SUFFIX}"
export STREAM_ANALYTICS_JOB="asa-supplychain-${RANDOM_SUFFIX}"
```

## Post-Deployment Configuration

After infrastructure deployment, complete these additional setup steps:

### 1. Deploy Digital Twin Models

```bash
# Upload supply chain models to Digital Twins
az dt model create \
    --dt-name ${DIGITAL_TWINS_INSTANCE} \
    --models supplier-model.json warehouse-model.json

# Create sample digital twins
az dt twin create \
    --dt-name ${DIGITAL_TWINS_INSTANCE} \
    --dtmi "dtmi:supplychain:Supplier;1" \
    --twin-id "supplier-001" \
    --properties '{"capacity": 1000, "location": "Dallas, TX", "cost_per_unit": 15.50}'
```

### 2. Deploy Function App Code

```bash
# Deploy quantum optimization functions
func azure functionapp publish ${FUNCTION_APP}

# Configure function app settings
az functionapp config appsettings set \
    --resource-group ${RESOURCE_GROUP} \
    --name ${FUNCTION_APP} \
    --settings \
    "AZURE_QUANTUM_WORKSPACE=${QUANTUM_WORKSPACE}" \
    "AZURE_DIGITAL_TWINS_ENDPOINT=https://${DIGITAL_TWINS_INSTANCE}.api.eus.digitaltwins.azure.net"
```

### 3. Configure Stream Analytics

```bash
# Start the Stream Analytics job
az stream-analytics job start \
    --resource-group ${RESOURCE_GROUP} \
    --name ${STREAM_ANALYTICS_JOB} \
    --output-start-mode JobStartTime
```

## Validation

### Verify Quantum Workspace

```bash
# Check quantum workspace status
az quantum workspace show \
    --resource-group ${RESOURCE_GROUP} \
    --workspace-name ${QUANTUM_WORKSPACE} \
    --output table

# List available quantum providers
az quantum offerings list \
    --resource-group ${RESOURCE_GROUP} \
    --workspace-name ${QUANTUM_WORKSPACE}
```

### Test Digital Twins

```bash
# Query digital twins
az dt twin query \
    --dt-name ${DIGITAL_TWINS_INSTANCE} \
    --query-command "SELECT * FROM DIGITALTWINS"

# Test relationship queries
az dt twin query \
    --dt-name ${DIGITAL_TWINS_INSTANCE} \
    --query-command "SELECT warehouse, supplier FROM DIGITALTWINS warehouse JOIN supplier RELATED warehouse.connected_to"
```

### Test Optimization Function

```bash
# Test the optimization endpoint
curl -X POST "https://${FUNCTION_APP}.azurewebsites.net/api/optimization" \
    -H "Content-Type: application/json" \
    -d '{
      "suppliers": [{"id": "001", "capacity": 1000, "location": "Dallas, TX", "cost_per_unit": 15.50}],
      "warehouses": [{"id": "001", "location": "Atlanta, GA", "storage_capacity": 5000}],
      "demand": [800]
    }'
```

## Monitoring and Troubleshooting

### View Deployment Status

```bash
# Check resource group resources
az resource list \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# Check specific service status
az quantum workspace show \
    --resource-group ${RESOURCE_GROUP} \
    --workspace-name ${QUANTUM_WORKSPACE}

az dt show \
    --dt-name ${DIGITAL_TWINS_INSTANCE} \
    --resource-group ${RESOURCE_GROUP}
```

### Access Logs and Metrics

```bash
# View Function App logs
az functionapp log tail \
    --resource-group ${RESOURCE_GROUP} \
    --name ${FUNCTION_APP}

# Query Application Insights
az monitor app-insights query \
    --app ${APPLICATION_INSIGHTS_NAME} \
    --analytics-query "requests | where timestamp > ago(1h) | summarize count() by bin(timestamp, 5m)"
```

### Common Issues

1. **Quantum Workspace Creation Fails**
   - Ensure Azure Quantum preview features are enabled
   - Verify subscription has appropriate quotas
   - Check region availability for quantum services

2. **Digital Twins Access Issues**
   - Verify managed identity permissions
   - Check Azure AD authentication configuration
   - Ensure proper RBAC assignments

3. **Function App Deployment Issues**
   - Verify storage account accessibility
   - Check Python runtime compatibility
   - Ensure proper application settings configuration

## Cleanup

### Using Bicep

```bash
# Delete the entire resource group
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait

# Verify deletion
az group exists --name ${RESOURCE_GROUP}
```

### Using Terraform

```bash
# Navigate to terraform directory
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

# Verify resource group deletion
az group exists --name ${RESOURCE_GROUP}
```

### Manual Cleanup Verification

```bash
# Check for any remaining quantum workspaces
az quantum workspace list --output table

# Check for any remaining digital twins instances
az dt list --output table

# Remove local files
rm -f supplier-model.json warehouse-model.json
rm -f quantum-optimization.py
```

## Security Considerations

This infrastructure implements security best practices:

- **Identity and Access Management**: Uses Azure Managed Identity for service-to-service authentication
- **Network Security**: Configures appropriate network access controls and private endpoints where applicable
- **Data Protection**: Enables encryption at rest and in transit for all storage services
- **Monitoring**: Implements comprehensive logging and alerting for security events
- **Least Privilege**: Assigns minimal required permissions to all service principals

## Cost Optimization

To minimize costs:

1. **Azure Quantum**: Use development/test quantum providers for initial testing
2. **Digital Twins**: Implement appropriate query throttling and data retention policies
3. **Function Apps**: Configure appropriate scaling limits and consumption plans
4. **Stream Analytics**: Use appropriate streaming units based on data volume
5. **Storage**: Implement lifecycle policies for data archival

## Scaling Considerations

This infrastructure supports scaling through:

- **Azure Quantum**: Quantum workspace supports multiple concurrent optimization jobs
- **Digital Twins**: Scales to handle thousands of digital twins and relationships
- **Function Apps**: Automatic scaling based on demand and configured limits
- **Stream Analytics**: Configurable streaming units for data processing throughput
- **Event Hubs**: Partition-based scaling for high-throughput scenarios

## Support and Documentation

- [Azure Quantum Documentation](https://docs.microsoft.com/en-us/azure/quantum/)
- [Azure Digital Twins Documentation](https://docs.microsoft.com/en-us/azure/digital-twins/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Stream Analytics Documentation](https://docs.microsoft.com/en-us/azure/stream-analytics/)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Contributing

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.

## License

This infrastructure code is provided under the same license as the parent recipe repository.

