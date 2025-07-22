# Infrastructure as Code for Satellite Imagery Analytics with Azure Orbital and AI Services

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Satellite Imagery Analytics with Azure Orbital and AI Services".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50+ installed and configured
- Appropriate Azure subscription with permissions for:
  - Azure Orbital (requires pre-registration and approval)
  - Azure Synapse Analytics
  - Azure AI Services
  - Azure Maps
  - Azure Cosmos DB
  - Azure Data Lake Storage Gen2
  - Azure Event Hubs
  - Azure Key Vault
- Azure Orbital service pre-approval (contact Microsoft for enablement)
- Estimated cost: $500-800 for full deployment during testing

> **Important**: Azure Orbital requires special approval from Microsoft. Contact the Azure Orbital team before attempting to deploy this infrastructure.

## Architecture Overview

This infrastructure deploys a comprehensive satellite data analytics platform including:

- **Data Ingestion**: Azure Event Hubs for real-time satellite data streaming
- **Storage**: Azure Data Lake Storage Gen2 with hierarchical namespace
- **Processing**: Azure Synapse Analytics with Spark and SQL pools
- **AI Analysis**: Azure AI Services (Computer Vision, Custom Vision, Form Recognizer)
- **Visualization**: Azure Maps for geospatial data display
- **Database**: Azure Cosmos DB for metadata and results storage
- **Security**: Azure Key Vault for credential management
- **Ground Station**: Azure Orbital integration (manual configuration required)

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to Bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-orbital-analytics" \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment status
az deployment group show \
    --resource-group "rg-orbital-analytics" \
    --name "main"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the infrastructure
terraform apply

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for resource configuration
```

## Configuration Parameters

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `resourceGroupName` | Name of the resource group | `rg-orbital-analytics` | Yes |
| `location` | Azure region for deployment | `eastus` | Yes |
| `randomSuffix` | Unique suffix for resource names | Auto-generated | No |
| `storageAccountName` | Data Lake Storage account name | `storbitdata{suffix}` | No |
| `synapseWorkspaceName` | Synapse Analytics workspace name | `syn-orbital-{suffix}` | No |
| `eventHubNamespace` | Event Hubs namespace name | `eh-orbital-{suffix}` | No |
| `aiServicesAccountName` | AI Services account name | `ai-orbital-{suffix}` | No |
| `mapsAccountName` | Azure Maps account name | `maps-orbital-{suffix}` | No |
| `cosmosAccountName` | Cosmos DB account name | `cosmos-orbital-{suffix}` | No |
| `keyVaultName` | Key Vault name | `kv-orbital-{suffix}` | No |

### Bicep Parameters

Create a `parameters.json` file in the `bicep/` directory:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "resourceGroupName": {
      "value": "rg-orbital-analytics"
    },
    "randomSuffix": {
      "value": "abc123"
    }
  }
}
```

### Terraform Variables

Create a `terraform.tfvars` file in the `terraform/` directory:

```hcl
location              = "East US"
resource_group_name   = "rg-orbital-analytics"
random_suffix        = "abc123"
```

## Post-Deployment Configuration

### Azure Orbital Setup

After infrastructure deployment, complete these manual steps:

1. **Contact Azure Orbital Team**: Request approval for Azure Orbital services
2. **Ground Station Configuration**: Configure contact profiles and spacecraft connections
3. **Frequency Coordination**: Obtain necessary frequency approvals
4. **Testing**: Schedule test satellite passes for validation

### AI Services Configuration

1. **Custom Vision Training**: Upload and train custom models for satellite imagery analysis
2. **API Integration**: Configure Synapse notebooks with AI Services endpoints
3. **Processing Pipeline**: Set up automated triggers for satellite data processing

### Data Pipeline Activation

1. **Synapse Pipelines**: Import and configure data processing pipelines
2. **Event Hub Integration**: Connect Azure Orbital data streams to Event Hubs
3. **Cosmos DB Setup**: Initialize database containers and indexes
4. **Azure Maps Integration**: Configure geospatial visualization dashboards

## Validation & Testing

### Infrastructure Validation

```bash
# Verify resource group and resources
az group show --name "rg-orbital-analytics"

# Check storage account configuration
az storage account show \
    --name "storbitdata{suffix}" \
    --resource-group "rg-orbital-analytics"

# Validate Synapse workspace
az synapse workspace show \
    --name "syn-orbital-{suffix}" \
    --resource-group "rg-orbital-analytics"

# Test AI Services connectivity
curl -H "Ocp-Apim-Subscription-Key: {key}" \
     -H "Content-Type: application/json" \
     "{endpoint}/vision/v3.2/analyze?visualFeatures=Description" \
     -d '{"url":"https://example.com/test-image.jpg"}'
```

### Component Testing

```bash
# Test Event Hubs connectivity
az eventhubs eventhub show \
    --name "satellite-imagery-stream" \
    --namespace-name "eh-orbital-{suffix}" \
    --resource-group "rg-orbital-analytics"

# Verify Cosmos DB containers
az cosmosdb sql container list \
    --account-name "cosmos-orbital-{suffix}" \
    --database-name "SatelliteAnalytics" \
    --resource-group "rg-orbital-analytics"

# Check Azure Maps account
az maps account show \
    --name "maps-orbital-{suffix}" \
    --resource-group "rg-orbital-analytics"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name "rg-orbital-analytics" \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

### Manual Cleanup

If automated cleanup fails, manually delete these high-cost resources first:

```bash
# Delete Synapse SQL pool to avoid ongoing charges
az synapse sql pool delete \
    --name "sqlpool01" \
    --workspace-name "syn-orbital-{suffix}" \
    --resource-group "rg-orbital-analytics" \
    --yes

# Delete Synapse Spark pool
az synapse spark pool delete \
    --name "sparkpool01" \
    --workspace-name "syn-orbital-{suffix}" \
    --resource-group "rg-orbital-analytics" \
    --yes
```

## Customization

### Storage Configuration

Modify storage settings in your IaC templates:

- **Performance Tier**: Change from Standard_LRS to Premium_LRS for higher performance
- **Replication**: Adjust replication strategy (LRS, GRS, RA-GRS) based on requirements
- **Access Tier**: Configure Hot, Cool, or Archive tiers for cost optimization

### Synapse Analytics Scaling

Adjust compute resources based on processing requirements:

- **Spark Pool Size**: Modify node count and size for processing capacity
- **SQL Pool DWU**: Adjust data warehouse units for analytical performance
- **Auto-scaling**: Configure min/max nodes for variable workloads

### AI Services Pricing Tiers

Select appropriate pricing tiers for AI Services:

- **S0 Standard**: For development and testing
- **S1-S3**: For production workloads with higher throughput requirements
- **Custom Vision Training**: Configure based on model training frequency

### Cosmos DB Performance

Configure Cosmos DB for optimal performance:

- **Throughput**: Adjust RU/s based on expected query patterns
- **Consistency Level**: Choose appropriate consistency for your use case
- **Partitioning**: Optimize partition keys for satellite data access patterns

## Monitoring and Observability

### Azure Monitor Integration

Configure monitoring for key components:

```bash
# Enable diagnostic settings for Synapse
az monitor diagnostic-settings create \
    --name "synapse-diagnostics" \
    --resource "/subscriptions/{subscription}/resourceGroups/rg-orbital-analytics/providers/Microsoft.Synapse/workspaces/syn-orbital-{suffix}" \
    --logs '[{"category":"SynapseRbacOperations","enabled":true}]' \
    --workspace "/subscriptions/{subscription}/resourceGroups/rg-orbital-analytics/providers/Microsoft.OperationalInsights/workspaces/log-analytics-workspace"

# Configure Event Hubs monitoring
az monitor diagnostic-settings create \
    --name "eventhub-diagnostics" \
    --resource "/subscriptions/{subscription}/resourceGroups/rg-orbital-analytics/providers/Microsoft.EventHub/namespaces/eh-orbital-{suffix}" \
    --metrics '[{"category":"AllMetrics","enabled":true}]'
```

### Cost Management

Set up cost alerts and budgets:

```bash
# Create budget for the resource group
az consumption budget create \
    --budget-name "orbital-analytics-budget" \
    --amount 1000 \
    --time-grain Monthly \
    --start-date "2025-01-01" \
    --end-date "2025-12-31" \
    --resource-group "rg-orbital-analytics"
```

## Troubleshooting

### Common Issues

1. **Azure Orbital Access**: Ensure pre-approval is completed before deployment
2. **Resource Naming**: Verify all resource names meet Azure naming requirements
3. **Regional Availability**: Confirm all services are available in your chosen region
4. **Permission Issues**: Validate subscription permissions for all required services
5. **Quota Limits**: Check subscription quotas for compute and storage resources

### Debug Commands

```bash
# Check deployment status
az deployment group list \
    --resource-group "rg-orbital-analytics" \
    --query "[].{Name:name,State:properties.provisioningState}"

# View deployment logs
az deployment group show \
    --resource-group "rg-orbital-analytics" \
    --name "main" \
    --query "properties.error"

# Validate network connectivity
az network vnet list \
    --resource-group "rg-orbital-analytics"
```

## Security Considerations

### Key Vault Integration

All sensitive credentials are stored in Azure Key Vault:

- AI Services API keys
- Event Hubs connection strings
- Cosmos DB access keys
- Storage account keys

### Network Security

Consider implementing additional security measures:

- Virtual Network integration for Synapse workspace
- Private endpoints for storage and database access
- Network security groups for traffic filtering
- Azure Firewall for advanced threat protection

### Access Control

Configure role-based access control (RBAC):

```bash
# Assign Synapse Administrator role
az role assignment create \
    --role "Synapse Administrator" \
    --assignee "{user-principal-id}" \
    --scope "/subscriptions/{subscription}/resourceGroups/rg-orbital-analytics/providers/Microsoft.Synapse/workspaces/syn-orbital-{suffix}"

# Grant AI Services access
az role assignment create \
    --role "Cognitive Services User" \
    --assignee "{user-principal-id}" \
    --scope "/subscriptions/{subscription}/resourceGroups/rg-orbital-analytics/providers/Microsoft.CognitiveServices/accounts/ai-orbital-{suffix}"
```

## Support and Documentation

### Azure Documentation

- [Azure Orbital Documentation](https://docs.microsoft.com/en-us/azure/orbital/)
- [Azure Synapse Analytics](https://docs.microsoft.com/en-us/azure/synapse-analytics/)
- [Azure AI Services](https://docs.microsoft.com/en-us/azure/cognitive-services/)
- [Azure Maps](https://docs.microsoft.com/en-us/azure/azure-maps/)
- [Azure Cosmos DB](https://docs.microsoft.com/en-us/azure/cosmos-db/)

### Contact Information

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service status pages
3. Contact Azure Orbital team for ground station issues
4. Submit support requests through Azure portal

### Community Resources

- Azure Architecture Center
- Azure Samples on GitHub
- Azure Tech Community forums
- Stack Overflow (azure tag)

---

**Note**: This infrastructure requires Azure Orbital service approval. Ensure you have completed the pre-registration process with Microsoft before deploying the complete solution.