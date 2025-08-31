# Infrastructure as Code for Infrastructure Inventory Reports with Resource Graph

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure Inventory Reports with Resource Graph".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts with Azure CLI

## Prerequisites

- Azure CLI installed and configured (version 2.22.0 or higher)
- Azure account with Reader permissions across target subscriptions
- Azure Resource Graph CLI extension installed
- Basic understanding of KQL (Kusto Query Language) syntax
- Appropriate permissions for query execution across subscriptions

### Installing Prerequisites

```bash
# Install Azure CLI (if not already installed)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Login to Azure
az login

# Install Resource Graph extension
az extension add --name resource-graph

# Verify extension installation
az extension list --query "[?name=='resource-graph']" --output table
```

## Quick Start

### Using Bicep

Bicep provides Azure-native infrastructure as code with strong typing and excellent Azure integration.

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the Resource Graph inventory solution
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters location=eastus

# Verify deployment
az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

Terraform provides multi-cloud infrastructure as code with extensive provider ecosystem.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Verify deployment
terraform output
```

### Using Bash Scripts

Bash scripts provide direct Azure CLI automation for rapid deployment and testing.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# Verify Resource Graph access
az graph query -q "Resources | limit 5" --output table
```

## Solution Components

This infrastructure deploys components for comprehensive Azure resource inventory management:

### Core Components

1. **Azure Resource Graph Queries**: Pre-configured KQL queries for comprehensive inventory reporting
2. **Resource Analysis Scripts**: Automated scripts for resource discovery and compliance checking
3. **Export Functionality**: JSON and CSV export capabilities for governance reporting
4. **Tagging Analysis**: Compliance monitoring for resource tagging policies

### Query Templates Included

- **Basic Resource Inventory**: Complete resource listing with metadata
- **Resource Type Distribution**: Aggregated counts by resource type
- **Location-Based Analysis**: Geographic distribution reporting
- **Tagging Compliance**: Tag coverage and compliance analysis
- **Security Posture**: Basic security configuration inventory

## Configuration Options

### Bicep Parameters

```bicep
// Location for metadata storage (if applicable)
param location string = 'eastus'

// Target subscription scope
param subscriptionId string = subscription().subscriptionId

// Report output configuration
param enableJsonExport bool = true
param enableCsvExport bool = true
```

### Terraform Variables

```hcl
# Location for resource deployment
variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

# Subscription scope for queries
variable "subscription_id" {
  description = "Target subscription ID for inventory"
  type        = string
  default     = null
}

# Export configuration
variable "enable_exports" {
  description = "Enable inventory export functionality"
  type        = bool
  default     = true
}
```

### Script Configuration

Environment variables for bash scripts:

```bash
# Export configuration
export LOCATION="eastus"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
export ENABLE_EXPORTS="true"

# Query customization
export MAX_RESULTS="1000"
export EXPORT_FORMAT="json"
```

## Usage Examples

### Running Inventory Queries

After deployment, execute comprehensive inventory analysis:

```bash
# Basic resource inventory
az graph query -q "Resources | project name, type, location, resourceGroup | limit 50" --output table

# Resource count by type
az graph query -q "Resources | summarize count() by type | order by count_ desc" --output table

# Location distribution
az graph query -q "Resources | where location != '' | summarize count() by location | order by count_ desc" --output table

# Tagging compliance
az graph query -q "Resources | extend HasTags = case(array_length(todynamic(tags)) > 0, 'Tagged', 'Untagged') | summarize count() by HasTags" --output table
```

### Generating Reports

Export comprehensive inventory reports:

```bash
# Generate JSON inventory export
az graph query -q "Resources | project name, type, location, resourceGroup, subscriptionId, tags" --output json > inventory-$(date +%Y%m%d).json

# Create CSV format for spreadsheet analysis
az graph query -q "Resources | project name, type, location, resourceGroup" --output tsv > inventory-$(date +%Y%m%d).csv

# Generate compliance summary
az graph query -q "Resources | summarize TotalResources=count(), TaggedResources=countif(array_length(todynamic(tags)) > 0)" --output table
```

### Advanced Queries

Execute complex governance and compliance queries:

```bash
# Identify untagged resources
az graph query -q "Resources | where tags !has 'Environment' or tags !has 'Owner' | project name, type, resourceGroup, location" --output table

# Security analysis - public IP exposure
az graph query -q "Resources | where type == 'microsoft.network/publicipaddresses' | project name, resourceGroup, location" --output table

# Cost optimization - unused resources
az graph query -q "Resources | where type contains 'microsoft.compute' and properties.provisioningState == 'Succeeded' | project name, type, location" --output table
```

## Monitoring and Alerts

### Setting Up Automated Inventory

Create scheduled inventory collection:

```bash
# Create Azure Automation runbook for scheduled inventory
# (requires additional Azure Automation Account setup)

# Set up Logic App for automated reporting
# (requires additional Logic Apps configuration)

# Configure Azure Monitor alerts for compliance violations
# (requires additional Azure Monitor setup)
```

### Performance Optimization

Resource Graph query optimization techniques:

```bash
# Use specific resource types for faster queries
az graph query -q "Resources | where type == 'microsoft.compute/virtualmachines' | project name, location" --output table

# Limit result sets for large environments
az graph query -q "Resources | limit 100" --output table

# Use summarize for aggregated data
az graph query -q "Resources | summarize count() by resourceGroup" --output table
```

## Cleanup

### Using Bicep

```bash
# Remove the resource group and all contained resources
az group delete --name myResourceGroup --yes --no-wait

# Clean up deployment history
az deployment group delete --resource-group myResourceGroup --name main
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all managed resources
terraform destroy

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manually clean up exported files
rm -f inventory-*.json inventory-*.csv

# Clear environment variables
unset LOCATION SUBSCRIPTION_ID ENABLE_EXPORTS
```

## Customization

### Query Customization

Modify queries in the implementation files to match your organization's needs:

1. **Resource Filtering**: Add specific resource type filters
2. **Tag Requirements**: Customize required tag validation
3. **Compliance Rules**: Implement organization-specific compliance checks
4. **Export Formats**: Modify output formatting for integration needs

### Integration Options

- **Power BI**: Export JSON data for dashboard creation
- **Excel**: Use CSV exports for spreadsheet analysis  
- **SIEM Integration**: Export security-relevant resource data
- **Cost Management**: Integrate with Azure Cost Management APIs
- **Governance Tools**: Feed data into third-party governance platforms

### Scaling Considerations

For large Azure environments:

1. **Query Pagination**: Implement result paging for large datasets
2. **Subscription Batching**: Process multiple subscriptions in batches
3. **Caching**: Implement query result caching for frequently accessed data
4. **Rate Limiting**: Handle Azure Resource Graph API limits

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure Reader access across all target subscriptions
2. **Extension Missing**: Verify Azure Resource Graph CLI extension is installed
3. **Query Timeouts**: Optimize queries for large environments
4. **Export Failures**: Check file system permissions for export operations

### Debugging

```bash
# Enable debug logging
az config set core.enable_debug=true

# Test basic connectivity
az graph query -q "Resources | limit 1" --debug

# Verify subscription access
az account list --output table

# Check extension status
az extension show --name resource-graph
```

### Support Resources

- [Azure Resource Graph Documentation](https://learn.microsoft.com/en-us/azure/governance/resource-graph/)
- [KQL Query Language Reference](https://learn.microsoft.com/en-us/azure/governance/resource-graph/concepts/query-language)
- [Azure Resource Graph Sample Queries](https://learn.microsoft.com/en-us/azure/governance/resource-graph/samples/starter)
- [Azure CLI Resource Graph Extension](https://learn.microsoft.com/en-us/cli/azure/graph)

## Contributing

To improve this infrastructure code:

1. Test queries against your Azure environment
2. Optimize performance for large-scale deployments
3. Add organization-specific compliance queries
4. Enhance export formats and integration options
5. Document custom query patterns and use cases

## License

This infrastructure code is provided as-is for educational and implementation purposes. Refer to your organization's policies for usage guidelines.