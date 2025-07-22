# Infrastructure as Code for Secure Cross-Organization Data Sharing with Data Share and Service Fabric

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure Cross-Organization Data Sharing with Data Share and Service Fabric".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a comprehensive cross-organization data collaboration platform including:

- Azure Data Share account for secure data sharing
- Azure Service Fabric cluster for governance microservices
- Azure Storage accounts for data repositories
- Azure Key Vaults for secrets management
- Azure Monitor and Log Analytics for comprehensive observability
- Sample datasets and sharing configurations

## Prerequisites

### General Requirements
- Azure CLI v2.50.0 or later installed and configured
- Active Azure subscription with sufficient permissions
- Understanding of cross-organization data sharing concepts
- Two Azure subscriptions or resource groups (for provider/consumer simulation)

### Tool-Specific Prerequisites

#### For Bicep Deployment
- Azure CLI with Bicep extension installed
- Bicep CLI v0.20.0 or later
- Contributor role on target subscription

#### For Terraform Deployment
- Terraform v1.5.0 or later
- Azure provider v3.70.0 or later
- Service Principal with appropriate permissions

#### For Bash Scripts
- Azure CLI authenticated and configured
- Bash shell (Linux/macOS) or WSL on Windows
- OpenSSL for random string generation

### Permissions Required
- Microsoft.DataShare/register
- Microsoft.ServiceFabric/register
- Microsoft.KeyVault/register
- Microsoft.Storage/register
- Microsoft.OperationalInsights/register
- Contributor access to target resource groups

## Estimated Costs

**Monthly Cost Estimate**: $150-200 for test environment
- Service Fabric cluster (5 nodes): ~$100-120
- Storage accounts: ~$10-20
- Data Share account: ~$10
- Key Vaults: ~$5-10
- Log Analytics workspace: ~$10-20
- Network egress: ~$5-15

> **Note**: Costs may vary based on region, usage patterns, and data transfer volumes. Use Azure Pricing Calculator for precise estimates.

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the Bicep directory
cd bicep/

# Validate the Bicep template
az bicep build --file main.bicep

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-data-share-provider \
    --template-file main.bicep \
    --parameters \
        location=eastus \
        environment=demo \
        deploymentSuffix=$(openssl rand -hex 3)

# Monitor deployment progress
az deployment group show \
    --resource-group rg-data-share-provider \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="location=eastus" \
    -var="environment=demo" \
    -var="deployment_suffix=$(openssl rand -hex 3)"

# Apply the configuration
terraform apply \
    -var="location=eastus" \
    -var="environment=demo" \
    -var="deployment_suffix=$(openssl rand -hex 3)"

# View deployment outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export AZURE_LOCATION="eastus"
export AZURE_ENVIRONMENT="demo"

# Deploy the infrastructure
./scripts/deploy.sh

# Monitor Service Fabric cluster deployment (takes 15-20 minutes)
az sf cluster show \
    --cluster-name sf-governance-$(cat .deployment_suffix) \
    --resource-group rg-data-share-provider-$(cat .deployment_suffix) \
    --query "clusterState"
```

## Post-Deployment Configuration

After successful deployment, complete these additional setup steps:

### 1. Configure Data Share Invitations

```bash
# Create data share invitation for consumer organization
az datashare invitation create \
    --account-name datashare$(cat .deployment_suffix) \
    --resource-group rg-data-share-provider-$(cat .deployment_suffix) \
    --share-name financial-collaboration-share \
    --invitation-name consumer-org-invite \
    --target-email consumer@organization.com

# Retrieve invitation details
az datashare invitation show \
    --account-name datashare$(cat .deployment_suffix) \
    --resource-group rg-data-share-provider-$(cat .deployment_suffix) \
    --share-name financial-collaboration-share \
    --invitation-name consumer-org-invite
```

### 2. Set Up Service Fabric Applications

```bash
# Connect to Service Fabric cluster (requires certificate)
sfctl cluster select \
    --endpoint https://sf-governance-$(cat .deployment_suffix).eastus.cloudapp.azure.com:19080 \
    --pem ./certs/cluster-cert.pem \
    --no-verify

# Deploy governance application package
sfctl application upload \
    --path ./governance-app \
    --application-type DataGovernanceApp

# Create application instance
sfctl application create \
    --app-name fabric:/DataGovernanceApp \
    --app-type DataGovernanceApp \
    --app-version 1.0.0
```

### 3. Configure Monitoring Dashboards

```bash
# Create Log Analytics query for data sharing activities
az monitor log-analytics query \
    --workspace law-datashare-$(cat .deployment_suffix) \
    --analytics-query "
    union DataShareAccount_CL, StorageAccount_CL, ServiceFabric_CL
    | where TimeGenerated > ago(24h)
    | summarize count() by bin(TimeGenerated, 1h), Type_s
    | render timechart"
```

## Validation & Testing

### 1. Verify Infrastructure Deployment

```bash
# Check all resource groups
az group list --query "[?contains(name, '$(cat .deployment_suffix)')].{Name:name, State:properties.provisioningState}" --output table

# Verify Data Share account
az datashare account show \
    --account-name datashare$(cat .deployment_suffix) \
    --resource-group rg-data-share-provider-$(cat .deployment_suffix) \
    --query "{Name:name, State:provisioningState, Location:location}"

# Check Service Fabric cluster health
az sf cluster show \
    --cluster-name sf-governance-$(cat .deployment_suffix) \
    --resource-group rg-data-share-provider-$(cat .deployment_suffix) \
    --query "{Name:name, State:clusterState, Nodes:nodeTypes[0].vmInstanceCount}"
```

### 2. Test Data Sharing Workflow

```bash
# List available data shares
az datashare share list \
    --account-name datashare$(cat .deployment_suffix) \
    --resource-group rg-data-share-provider-$(cat .deployment_suffix) \
    --output table

# Verify dataset is attached to share
az datashare dataset list \
    --account-name datashare$(cat .deployment_suffix) \
    --resource-group rg-data-share-provider-$(cat .deployment_suffix) \
    --share-name financial-collaboration-share \
    --output table
```

### 3. Validate Security Configuration

```bash
# Check Key Vault access policies
az keyvault show \
    --name kv-provider-$(cat .deployment_suffix) \
    --resource-group rg-data-share-provider-$(cat .deployment_suffix) \
    --query "properties.accessPolicies[].{ObjectId:objectId, Permissions:permissions}"

# Verify storage account security settings
az storage account show \
    --name stprovider$(cat .deployment_suffix) \
    --resource-group rg-data-share-provider-$(cat .deployment_suffix) \
    --query "{Name:name, HttpsOnly:enableHttpsTrafficOnly, PublicAccess:allowBlobPublicAccess}"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group deployment
az group delete \
    --name rg-data-share-provider-$(cat .deployment_suffix) \
    --yes \
    --no-wait

az group delete \
    --name rg-data-share-consumer-$(cat .deployment_suffix) \
    --yes \
    --no-wait

# Purge Key Vaults (if soft-delete is enabled)
az keyvault purge \
    --name kv-provider-$(cat .deployment_suffix) \
    --location eastus

az keyvault purge \
    --name kv-consumer-$(cat .deployment_suffix) \
    --location eastus
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy \
    -var="location=eastus" \
    -var="environment=demo" \
    -var="deployment_suffix=$(cat ../.deployment_suffix)"

# Clean up Terraform state
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify resource cleanup
az group list --query "[?contains(name, '$(cat .deployment_suffix)')].name" --output table
```

## Customization

### Key Parameters

#### Bicep Parameters
- `location`: Azure region for deployment (default: eastus)
- `environment`: Environment tag (dev/staging/prod)
- `deploymentSuffix`: Unique suffix for resource names
- `serviceFabricNodeCount`: Number of nodes in SF cluster (default: 5)
- `storageAccountSku`: Storage account performance tier (default: Standard_LRS)

#### Terraform Variables
- `location`: Azure region for deployment
- `environment`: Environment designation
- `deployment_suffix`: Unique identifier for resources
- `sf_vm_size`: Service Fabric VM size (default: Standard_D2s_v3)
- `enable_monitoring`: Enable comprehensive monitoring (default: true)

#### Bash Script Environment Variables
- `AZURE_LOCATION`: Target Azure region
- `AZURE_ENVIRONMENT`: Environment type
- `SF_NODE_COUNT`: Service Fabric cluster node count
- `ENABLE_HTTPS_ONLY`: Force HTTPS-only storage access

### Advanced Configuration

#### Multi-Region Deployment
```bash
# Deploy to multiple regions for high availability
az deployment group create \
    --resource-group rg-data-share-provider \
    --template-file bicep/main.bicep \
    --parameters location=eastus primaryRegion=true

az deployment group create \
    --resource-group rg-data-share-secondary \
    --template-file bicep/main.bicep \
    --parameters location=westus2 primaryRegion=false
```

#### Custom Data Governance Policies
```bash
# Apply custom Azure Policy for data governance
az policy assignment create \
    --name DataShareGovernance \
    --scope /subscriptions/$SUBSCRIPTION_ID \
    --policy-definition-name "Data Share accounts should use customer-managed keys for encryption"
```

## Troubleshooting

### Common Issues

#### Service Fabric Deployment Timeout
```bash
# Check deployment status
az sf cluster show \
    --cluster-name sf-governance-$(cat .deployment_suffix) \
    --resource-group rg-data-share-provider-$(cat .deployment_suffix) \
    --query "clusterState"

# If deployment hangs, check cluster events
az monitor activity-log list \
    --resource-group rg-data-share-provider-$(cat .deployment_suffix) \
    --max-events 50 \
    --query "[?contains(resourceId.value, 'Microsoft.ServiceFabric')]"
```

#### Data Share Permission Issues
```bash
# Verify Data Share service principal permissions
az role assignment list \
    --assignee $(az ad sp list --display-name "Microsoft.DataShare" --query "[0].objectId" -o tsv) \
    --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-data-share-provider-$(cat .deployment_suffix)
```

#### Key Vault Access Denied
```bash
# Check current user permissions
az keyvault show \
    --name kv-provider-$(cat .deployment_suffix) \
    --query "properties.accessPolicies[?objectId=='$(az ad signed-in-user show --query objectId -o tsv)']"

# Grant access if needed
az keyvault set-policy \
    --name kv-provider-$(cat .deployment_suffix) \
    --object-id $(az ad signed-in-user show --query objectId -o tsv) \
    --secret-permissions get list set
```

### Log Analysis

```bash
# Query Log Analytics for deployment issues
az monitor log-analytics query \
    --workspace law-datashare-$(cat .deployment_suffix) \
    --analytics-query "
    AzureActivity
    | where TimeGenerated > ago(2h)
    | where OperationNameValue contains 'Microsoft.DataShare'
       or OperationNameValue contains 'Microsoft.ServiceFabric'
    | project TimeGenerated, OperationNameValue, ActivityStatusValue, Caller
    | order by TimeGenerated desc"
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown for detailed explanations
2. **Azure Documentation**: [Azure Data Share](https://learn.microsoft.com/en-us/azure/data-share/), [Azure Service Fabric](https://learn.microsoft.com/en-us/azure/service-fabric/)
3. **Community Support**: [Azure Community Forums](https://techcommunity.microsoft.com/t5/azure/ct-p/Azure)
4. **GitHub Issues**: Report infrastructure code issues in the recipes repository

## Security Considerations

- All storage accounts enforce HTTPS-only access
- Key Vaults use Azure RBAC for access control
- Service Fabric cluster uses certificate-based security
- Data Share accounts implement Microsoft Entra ID authentication
- Network security groups restrict inbound traffic to essential ports
- Azure Monitor provides comprehensive audit logging

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment
2. Validate Bicep templates with `az bicep build`
3. Run Terraform plan before applying changes
4. Update README.md with any new parameters or procedures
5. Ensure cleanup scripts remove all created resources