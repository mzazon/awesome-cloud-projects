# Infrastructure as Code for Governed Cross-Tenant Data Collaboration with Data Share and Purview

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Governed Cross-Tenant Data Collaboration with Data Share and Purview".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI version 2.50.0 or later installed and configured
- Two Azure subscriptions (one for provider tenant, one for consumer tenant)
- Owner or Contributor permissions on both subscriptions
- Azure AD permissions to configure B2B collaboration and cross-tenant access
- Basic understanding of Azure storage services and data governance concepts
- PowerShell Core 7.x or Bash shell environment

## Cost Considerations

- Azure Purview requires minimum 1 capacity unit (CU) with hourly charges (~$1.44/hour)
- Azure Data Share costs based on snapshots and data transfer
- Storage accounts incur standard storage and transaction costs
- Estimated monthly cost: $50-100 for testing environments

> **Warning**: Azure Purview incurs charges immediately upon deployment. Plan your deployment schedule to minimize costs during testing.

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Set parameters for your environment
# Edit parameters.json with your specific values:
# - providerSubscriptionId
# - consumerSubscriptionId
# - tenantId
# - location
# - uniqueSuffix

# Login to Azure
az login

# Deploy provider resources
az deployment sub create \
    --location eastus \
    --template-file main.bicep \
    --parameters @parameters.json \
    --parameters deploymentType=provider

# Deploy consumer resources
az deployment sub create \
    --location eastus \
    --template-file main.bicep \
    --parameters @parameters.json \
    --parameters deploymentType=consumer
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# Confirm deployment when prompted
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export PROVIDER_SUBSCRIPTION_ID="your-provider-subscription-id"
export CONSUMER_SUBSCRIPTION_ID="your-consumer-subscription-id"
export LOCATION="eastus"

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `providerSubscriptionId` | Provider tenant subscription ID | `12345678-1234-1234-1234-123456789012` |
| `consumerSubscriptionId` | Consumer tenant subscription ID | `87654321-4321-4321-4321-210987654321` |
| `location` | Azure region for deployment | `eastus` |
| `uniqueSuffix` | Unique suffix for resource names | `abc123` |

### Optional Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `purviewSku` | Purview account SKU | `Standard_4` |
| `storageAccountType` | Storage account replication type | `Standard_LRS` |
| `enableHierarchicalNamespace` | Enable ADLS Gen2 features | `true` |

## Manual Configuration Steps

After infrastructure deployment, the following manual steps are required:

### 1. Configure Cross-Tenant Access Settings

```bash
# In Azure Portal, navigate to:
# Azure AD > External Identities > Cross-tenant access settings
# 1. Add consumer tenant as allowed tenant
# 2. Configure B2B collaboration settings
# 3. Enable data share service permissions
```

### 2. Configure Azure Purview Scanning

```bash
# For each Purview instance:
# 1. Open Purview Studio
# 2. Navigate to Data Map > Sources
# 3. Register storage accounts as data sources
# 4. Create scan schedules with automated classification
# 5. Configure data lineage tracking
```

### 3. Create Data Share and Invitation

```bash
# In Azure Portal, navigate to Data Share account
# 1. Create new share with appropriate datasets
# 2. Configure synchronization settings
# 3. Send invitation to consumer tenant
# 4. Configure access permissions
```

## Validation

### Verify Infrastructure Deployment

```bash
# Check provider resources
az account set --subscription ${PROVIDER_SUBSCRIPTION_ID}
az resource list --resource-group rg-datashare-provider --output table

# Check consumer resources
az account set --subscription ${CONSUMER_SUBSCRIPTION_ID}
az resource list --resource-group rg-datashare-consumer --output table
```

### Test Purview Connectivity

```bash
# Test Purview endpoints (requires authentication)
curl -s -o /dev/null -w "%{http_code}" \
    https://purview-provider-{suffix}.purview.azure.com/catalog/api/atlas/v2/types/typedefs

curl -s -o /dev/null -w "%{http_code}" \
    https://purview-consumer-{suffix}.purview.azure.com/catalog/api/atlas/v2/types/typedefs
```

## Cleanup

### Using Bicep

```bash
# Delete provider resources
az group delete --name rg-datashare-provider --yes --no-wait

# Delete consumer resources
az group delete --name rg-datashare-consumer --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup

```bash
# Remove cross-tenant access settings:
# 1. Azure AD > External Identities > Cross-tenant access
# 2. Remove configured tenant access settings
# 3. Remove any guest users created during setup
```

## Troubleshooting

### Common Issues

1. **Purview Deployment Timeout**
   - Purview deployment can take 10-15 minutes
   - Check Azure Portal for deployment status
   - Verify subscription has adequate capacity units available

2. **Cross-Tenant Access Denied**
   - Ensure B2B collaboration is enabled
   - Verify cross-tenant access settings are configured
   - Check Azure AD conditional access policies

3. **Storage Account Access Issues**
   - Verify Purview managed identity has correct permissions
   - Check storage account firewall settings
   - Ensure hierarchical namespace is enabled for ADLS Gen2

4. **Data Share Invitation Failures**
   - Verify consumer tenant is correctly configured
   - Check Data Share service permissions
   - Ensure guest user has necessary access rights

### Diagnostic Commands

```bash
# Check Purview account status
az purview account show --name purview-provider-{suffix} --resource-group rg-datashare-provider

# Verify role assignments
az role assignment list --assignee {purview-managed-identity-id} --output table

# Check Data Share account
az datashare account show --name share-provider-{suffix} --resource-group rg-datashare-provider
```

## Security Considerations

- All storage accounts use encryption at rest by default
- Purview managed identities use least privilege access
- Cross-tenant access is restricted to specific services
- Data Share uses Azure AD authentication for all operations
- Network security groups and private endpoints can be added for additional security

## Best Practices

1. **Resource Naming**: Use consistent naming conventions with environment prefixes
2. **Tagging**: Apply comprehensive tags for cost tracking and governance
3. **Monitoring**: Enable Azure Monitor for all deployed resources
4. **Backup**: Configure backup policies for critical data
5. **Access Control**: Implement role-based access control (RBAC) for all resources

## Customization

### Adding Private Endpoints

Modify the Bicep or Terraform templates to include private endpoints for enhanced security:

```bicep
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: 'pe-datashare-${uniqueSuffix}'
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'datashare-connection'
        properties: {
          privateLinkServiceId: dataShareAccount.id
          groupIds: ['datashare']
        }
      }
    ]
  }
}
```

### Adding Monitoring and Alerts

Configure Azure Monitor alerts for operational monitoring:

```bash
# Create alert rule for Purview capacity usage
az monitor metrics alert create \
    --name "purview-capacity-alert" \
    --resource-group rg-datashare-provider \
    --scopes /subscriptions/{subscription-id}/resourceGroups/rg-datashare-provider/providers/Microsoft.Purview/accounts/purview-provider-{suffix} \
    --condition "avg PurviewCapacityUnits >= 80" \
    --description "Alert when Purview capacity usage exceeds 80%"
```

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for solution-specific guidance
2. Review Azure Data Share documentation: https://docs.microsoft.com/en-us/azure/data-share/
3. Review Azure Purview documentation: https://docs.microsoft.com/en-us/azure/purview/
4. Check Azure CLI documentation for command syntax
5. Review Terraform Azure Provider documentation for resource configurations

## Additional Resources

- [Azure Data Share Overview](https://docs.microsoft.com/en-us/azure/data-share/overview)
- [Azure Purview Data Governance](https://docs.microsoft.com/en-us/azure/purview/overview)
- [Azure AD B2B Collaboration](https://docs.microsoft.com/en-us/azure/active-directory/external-identities/what-is-b2b)
- [Cross-Tenant Access Settings](https://docs.microsoft.com/en-us/azure/active-directory/external-identities/cross-tenant-access-overview)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)