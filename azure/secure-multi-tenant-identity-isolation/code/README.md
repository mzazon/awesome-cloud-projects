# Infrastructure as Code for Secure Multi-Tenant Identity Isolation with External ID

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure Multi-Tenant Identity Isolation with External ID".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.49.0 or later installed and authenticated
- PowerShell 7.0 or later (for External ID tenant management)
- Appropriate Azure permissions:
  - Owner or Contributor role on target subscription
  - Ability to create Azure External ID tenants
  - Network Contributor role for VNet and private endpoint creation
- Understanding of Azure networking, identity management, and private endpoints
- Estimated cost: $200-400 per month for development environment

> **Note**: This solution requires creating multiple Azure External ID tenants, which may have additional licensing costs. Review [Azure External ID pricing](https://learn.microsoft.com/en-us/entra/external-id/external-identities-pricing) before proceeding.

## Architecture Overview

This solution implements comprehensive multi-tenant customer identity management with:

- **Azure External ID Customer Tenants**: Complete identity boundary isolation for each customer
- **Azure Resource Manager Private Link**: Secure network connectivity for management operations
- **Azure API Management**: Centralized API gateway with tenant-specific routing and security
- **Azure Key Vault**: Per-tenant secret isolation with private endpoint connectivity
- **Virtual Network**: Private network infrastructure with dedicated subnets
- **Monitoring & Alerting**: Comprehensive tenant isolation monitoring and violation detection

## Quick Start

### Using Bicep (Recommended for Azure)

1. **Deploy the infrastructure**:
   ```bash
   cd bicep/
   
   # Deploy with default parameters
   az deployment group create \
       --resource-group rg-multitenant-identity \
       --template-file main.bicep \
       --parameters location=eastus
   
   # Or deploy with custom parameters
   az deployment group create \
       --resource-group rg-multitenant-identity \
       --template-file main.bicep \
       --parameters @parameters.json
   ```

2. **Create Azure External ID tenants** (manual step):
   ```bash
   # Run the PowerShell script for tenant creation guidance
   pwsh scripts/create-external-id-tenants.ps1
   ```

3. **Configure API Management policies**:
   ```bash
   # Apply tenant isolation policies
   az apim api policy set \
       --resource-group rg-multitenant-identity \
       --service-name $(az deployment group show --resource-group rg-multitenant-identity --name main --query properties.outputs.apimName.value -o tsv) \
       --api-id tenant-isolation-api \
       --policy-format xml \
       --value @policies/tenant-isolation-policy.xml
   ```

### Using Terraform

1. **Initialize and deploy**:
   ```bash
   cd terraform/
   
   # Initialize Terraform
   terraform init
   
   # Review deployment plan
   terraform plan -var-file="terraform.tfvars"
   
   # Apply configuration
   terraform apply -var-file="terraform.tfvars"
   ```

2. **Create Azure External ID tenants** (manual step):
   ```bash
   # Follow the tenant creation guide
   pwsh ../scripts/create-external-id-tenants.ps1
   ```

3. **Configure post-deployment settings**:
   ```bash
   # Run post-deployment configuration
   bash ../scripts/configure-tenant-policies.sh
   ```

### Using Bash Scripts

1. **Set environment variables**:
   ```bash
   export LOCATION="eastus"
   export RESOURCE_GROUP="rg-multitenant-identity"
   export UNIQUE_SUFFIX=$(openssl rand -hex 4)
   ```

2. **Deploy infrastructure**:
   ```bash
   chmod +x scripts/deploy.sh
   ./scripts/deploy.sh
   ```

3. **Follow guided setup**:
   ```bash
   # The script will guide you through:
   # - Infrastructure deployment
   # - External ID tenant creation (manual steps)
   # - API Management configuration
   # - Monitoring setup
   ```

## Configuration Options

### Bicep Parameters

Key parameters you can customize in `parameters.json`:

```json
{
  "location": {
    "value": "eastus"
  },
  "resourcePrefix": {
    "value": "mt-identity"
  },
  "vnetAddressPrefix": {
    "value": "10.0.0.0/16"
  },
  "apimSku": {
    "value": "Developer"
  },
  "keyVaultSku": {
    "value": "premium"
  },
  "enableSoftDelete": {
    "value": true
  },
  "retentionDays": {
    "value": 90
  }
}
```

### Terraform Variables

Customize deployment in `terraform.tfvars`:

```hcl
location             = "eastus"
resource_group_name  = "rg-multitenant-identity"
resource_prefix      = "mt-identity"
vnet_address_space   = ["10.0.0.0/16"]
apim_sku_name       = "Developer_1"
key_vault_sku_name  = "premium"
enable_soft_delete  = true
retention_days      = 90

# Tenant configuration
tenant_names = [
  "customer-a-external",
  "customer-b-external"
]

# Monitoring settings
log_retention_days = 30
alert_severity     = 2
```

### Environment Variables for Bash Scripts

```bash
# Required variables
export LOCATION="eastus"
export RESOURCE_GROUP="rg-multitenant-identity"
export SUBSCRIPTION_ID="your-subscription-id"

# Optional customization
export VNET_ADDRESS_PREFIX="10.0.0.0/16"
export APIM_SKU="Developer"
export KEYVAULT_SKU="premium"
export LOG_RETENTION_DAYS="30"
```

## Post-Deployment Configuration

### 1. Azure External ID Tenant Setup

External ID tenant creation requires manual portal-based workflow:

```powershell
# Run the tenant creation guidance script
pwsh scripts/create-external-id-tenants.ps1

# Manual steps in Azure portal:
# 1. Navigate to Azure AD External Identities
# 2. Create new customer tenant for each customer
# 3. Configure external collaboration settings
# 4. Set up custom branding (optional)
```

### 2. API Management Policy Configuration

```bash
# Apply tenant isolation policies
APIM_NAME=$(az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query properties.outputs.apimName.value -o tsv)

az apim api policy set \
    --resource-group ${RESOURCE_GROUP} \
    --service-name ${APIM_NAME} \
    --api-id tenant-isolation-api \
    --policy-format xml \
    --value @policies/tenant-isolation-policy.xml
```

### 3. Monitoring and Alerting Setup

```bash
# Configure custom monitoring queries
az monitor log-analytics workspace show \
    --resource-group ${RESOURCE_GROUP} \
    --workspace-name law-tenant-isolation

# Import custom KQL queries for tenant monitoring
# Queries will be available in the workspace for alert configuration
```

## Validation and Testing

### 1. Verify Private Endpoint Connectivity

```bash
# Test private endpoint resolution
nslookup ${APIM_NAME}.azure-api.net
nslookup ${KEYVAULT_NAME}.vault.azure.net

# Verify private IP assignment
az network private-endpoint list \
    --resource-group ${RESOURCE_GROUP} \
    --output table
```

### 2. Test Tenant Isolation

```bash
# Test API calls with different tenant headers
APIM_GATEWAY_URL="https://${APIM_NAME}.azure-api.net"

# Valid tenant A request
curl -X GET "${APIM_GATEWAY_URL}/api/test" \
     -H "X-Tenant-ID: tenant-a" \
     -H "Content-Type: application/json"

# Valid tenant B request  
curl -X GET "${APIM_GATEWAY_URL}/api/test" \
     -H "X-Tenant-ID: tenant-b" \
     -H "Content-Type: application/json"

# Invalid tenant request (should return 403)
curl -X GET "${APIM_GATEWAY_URL}/api/test" \
     -H "X-Tenant-ID: invalid-tenant" \
     -H "Content-Type: application/json"
```

### 3. Monitor Tenant Isolation

```bash
# Check monitoring logs for isolation violations
az monitor log-analytics query \
    --workspace $(az monitor log-analytics workspace show --resource-group ${RESOURCE_GROUP} --workspace-name law-tenant-isolation --query customerId -o tsv) \
    --analytics-query "ApiManagementGatewayLogs | where TimeGenerated > ago(1h) | extend TenantId = tostring(parse_json(RequestHeaders)[\"X-Tenant-ID\"]) | where isempty(TenantId) or TenantId !in (\"tenant-a\", \"tenant-b\")"
```

## Troubleshooting

### Common Issues

1. **External ID Tenant Creation Failures**:
   - Verify sufficient permissions for tenant creation
   - Check Azure AD license requirements
   - Ensure unique tenant names

2. **Private Endpoint Resolution Issues**:
   - Verify DNS configuration within VNet
   - Check network security group rules
   - Validate private endpoint configuration

3. **API Management Policy Errors**:
   - Verify managed identity configuration
   - Check Key Vault access policies
   - Validate policy XML syntax

4. **Monitoring Configuration Issues**:
   - Verify Log Analytics workspace deployment
   - Check diagnostic settings configuration
   - Validate KQL query syntax

### Debug Commands

```bash
# Check resource deployment status
az deployment group list \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# Verify private endpoint status
az network private-endpoint list \
    --resource-group ${RESOURCE_GROUP} \
    --query "[].{Name:name,ProvisioningState:provisioningState,ConnectionState:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" \
    --output table

# Check API Management status
az apim show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${APIM_NAME} \
    --query "{Name:name,State:provisioningState,GatewayUrl:gatewayUrl}" \
    --output table
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-multitenant-identity \
    --yes \
    --no-wait

# Delete management resource group
az group delete \
    --name rg-tenant-management \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var-file="terraform.tfvars"

# Clean up state files (optional)
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Cleanup Steps

1. **External ID Tenants** (manual):
   ```
   - Navigate to Azure portal
   - Delete Customer A External ID tenant
   - Delete Customer B External ID tenant
   - Verify complete tenant removal
   ```

2. **Key Vault Purge** (if purge protection enabled):
   ```bash
   # List deleted Key Vaults
   az keyvault list-deleted --subscription ${SUBSCRIPTION_ID}
   
   # Purge Key Vault (if needed)
   az keyvault purge --name ${KEYVAULT_NAME} --location ${LOCATION}
   ```

## Security Considerations

- **Identity Isolation**: External ID tenants provide complete identity boundary separation
- **Network Security**: All communication flows through private endpoints
- **Secret Management**: Per-tenant secret namespacing with RBAC controls
- **Monitoring**: Comprehensive logging and alerting for isolation violations
- **Access Control**: Least privilege principle enforced throughout

## Cost Optimization

- Use Azure Cost Management to monitor ongoing costs
- Consider API Management consumption tier for lower usage scenarios
- Implement automated scaling policies for variable workloads
- Review Key Vault transaction costs and optimize secret access patterns

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure documentation for specific services
3. Validate prerequisites and permissions
4. Review deployment logs for specific error messages

## Additional Resources

- [Azure External ID Documentation](https://learn.microsoft.com/en-us/entra/external-id/)
- [Azure API Management Best Practices](https://learn.microsoft.com/en-us/azure/api-management/)
- [Azure Private Link Documentation](https://learn.microsoft.com/en-us/azure/private-link/)
- [Azure Key Vault Security](https://learn.microsoft.com/en-us/azure/key-vault/general/security-features)