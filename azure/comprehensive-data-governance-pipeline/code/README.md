# Infrastructure as Code for Comprehensive Data Governance Pipeline with Purview Discovery

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Comprehensive Data Governance Pipeline with Purview Discovery".

## Available Implementations

- **Bicep**: Azure native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with Owner or Contributor permissions
- Terraform 1.0+ (for Terraform deployment)
- Basic understanding of data governance concepts and Azure storage
- Familiarity with Azure Synapse Analytics and data pipeline concepts
- Estimated cost: $50-100 USD for testing environment (depends on data volume and scan frequency)

> **Note**: Azure Purview follows consumption-based pricing for data scanning and catalog operations. Review the [Azure Purview pricing guide](https://azure.microsoft.com/pricing/details/azure-purview/) to understand cost implications before proceeding.

## Quick Start

### Using Bicep
```bash
# Navigate to bicep directory
cd bicep/

# Login to Azure (if not already logged in)
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-purview-governance-demo" \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform
```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh
```

## Architecture Components

This IaC deployment creates the following Azure resources:

- **Azure Purview Account**: Central data governance and catalog service
- **Azure Data Lake Storage Gen2**: Hierarchical storage for enterprise data lakes
- **Azure Synapse Analytics Workspace**: Integrated analytics platform
- **Storage Containers**: Organized data containers (raw-data, processed-data, sensitive-data)
- **IAM Role Assignments**: Proper permissions for Purview-Storage integration
- **Firewall Rules**: Secure access configuration for development

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
    "purviewAccountName": {
      "value": "purview-governance-demo"
    },
    "storageAccountName": {
      "value": "datalakegovernance"
    },
    "synapseWorkspaceName": {
      "value": "synapse-governance-demo"
    }
  }
}
```

### Terraform Variables

Customize `terraform/terraform.tfvars`:

```hcl
location                = "East US"
resource_group_name     = "rg-purview-governance-demo"
purview_account_name    = "purview-governance-demo"
storage_account_name    = "datalakegovernance"
synapse_workspace_name  = "synapse-governance-demo"
environment            = "demo"
```

### Bash Script Environment Variables

The deploy.sh script uses environment variables for configuration:

```bash
export RESOURCE_GROUP="rg-purview-governance-demo"
export LOCATION="eastus"
export PURVIEW_ACCOUNT="purview-governance-demo"
export STORAGE_ACCOUNT="datalakegovernance"
export SYNAPSE_WORKSPACE="synapse-governance-demo"
```

## Post-Deployment Configuration

After the infrastructure is deployed, you'll need to complete these manual steps:

1. **Register Data Sources in Purview**:
   - Navigate to Azure Purview Studio
   - Register your Data Lake Storage account as a data source
   - Configure scan rules and schedules

2. **Configure Data Classification**:
   - Set up custom classification rules
   - Define sensitivity labels
   - Configure automated scanning policies

3. **Set Up Synapse Integration**:
   - Connect Synapse workspace to Purview
   - Configure lineage tracking
   - Deploy data pipelines for governance testing

4. **Create Sample Data**:
   - Upload sample datasets to test classification
   - Verify data discovery and cataloging
   - Test governance workflows

## Validation

### Verify Azure Purview Account
```bash
az purview account show \
    --resource-group "rg-purview-governance-demo" \
    --name "your-purview-account-name" \
    --query '{name:name,state:properties.provisioningState}' \
    --output table
```

### Verify Data Lake Storage
```bash
az storage account show \
    --resource-group "rg-purview-governance-demo" \
    --name "your-storage-account-name" \
    --query '{name:name,kind:kind,hierarchicalNamespace:isHnsEnabled}' \
    --output table
```

### Verify Synapse Workspace
```bash
az synapse workspace show \
    --resource-group "rg-purview-governance-demo" \
    --name "your-synapse-workspace-name" \
    --query '{name:name,state:provisioningState}' \
    --output table
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete \
    --name "rg-purview-governance-demo" \
    --yes \
    --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
# Run the destroy script
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Purview Account Name Conflicts**:
   - Purview account names must be globally unique
   - Modify the account name in your parameters

2. **Storage Account Name Conflicts**:
   - Storage account names must be globally unique and lowercase
   - Update the storage account name in your configuration

3. **Insufficient Permissions**:
   - Ensure you have Owner or Contributor permissions on the subscription
   - Verify Azure resource providers are registered

4. **Firewall Access Issues**:
   - The deployment configures firewall rules for current IP
   - Update firewall rules if accessing from different locations

### Resource Provider Registration

If you encounter resource provider errors, register them manually:

```bash
az provider register --namespace Microsoft.Purview
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Synapse
az provider register --namespace Microsoft.KeyVault
```

## Cost Management

### Expected Costs

- **Azure Purview**: Consumption-based pricing for scanning and cataloging
- **Data Lake Storage Gen2**: Storage costs based on data volume
- **Synapse Analytics**: Compute costs based on usage
- **Estimated Total**: $50-100 USD for testing environment

### Cost Optimization Tips

1. **Purview Scanning**: Schedule scans during off-peak hours
2. **Storage Tiers**: Use appropriate storage tiers for different data types
3. **Synapse Compute**: Pause compute resources when not in use
4. **Resource Cleanup**: Remove test resources promptly after validation

## Security Considerations

### Implemented Security Features

- **Managed Identity**: Purview uses managed identity for storage access
- **RBAC**: Role-based access control with least privilege principles
- **Network Security**: Firewall rules restrict access to authorized IPs
- **Encryption**: Data encryption at rest and in transit

### Additional Security Recommendations

1. **Private Endpoints**: Consider private endpoints for production environments
2. **Azure AD Integration**: Use Azure AD for user authentication
3. **Network Isolation**: Implement VNet integration for enhanced security
4. **Monitoring**: Enable Azure Monitor and Security Center

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../implementing-automated-data-governance-with-azure-purview-and-azure-data-lake-storage.md)
- [Azure Purview documentation](https://docs.microsoft.com/en-us/azure/purview/)
- [Azure Data Lake Storage documentation](https://docs.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-introduction)
- [Azure Synapse Analytics documentation](https://docs.microsoft.com/en-us/azure/synapse-analytics/)

## Contributing

To improve this IaC implementation:

1. Follow Azure best practices and naming conventions
2. Test changes in a development environment
3. Update documentation for any configuration changes
4. Ensure backward compatibility when possible