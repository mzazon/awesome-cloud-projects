# Infrastructure as Code for Multi-Tenant SaaS Isolation with Resource Governance

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Tenant SaaS Isolation with Resource Governance".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts for automated provisioning

## Prerequisites

- Azure CLI v2.45.0 or later installed and configured
- Azure subscription with Owner or Contributor permissions
- Understanding of Azure Resource Manager templates and multi-tenant architecture patterns
- Familiarity with Azure Policy and governance concepts
- Basic knowledge of OAuth 2.0 and OpenID Connect protocols
- **For Bicep**: Azure CLI with Bicep extension installed
- **For Terraform**: Terraform v1.0+ installed
- **For Scripts**: Bash shell environment (Linux/macOS/WSL)

## Architecture Overview

This solution implements a multi-tenant SaaS architecture with:

- **Control Plane**: Centralized management for tenant lifecycle operations
- **Tenant Isolation**: Dedicated resource groups and resources per tenant
- **Workload Identity**: Secure, keyless authentication for tenant workloads
- **Governance**: Azure Policy-based compliance and security enforcement
- **Monitoring**: Centralized logging and alerting across all tenants
- **Automation**: Scripted tenant onboarding, updates, and offboarding

## Estimated Costs

- **Control Plane**: $20-30/month (Key Vault, Log Analytics, Application Insights)
- **Per Tenant**: $50-100/month (Storage, Network, Compute resources)
- **Monitoring**: $10-20/month per tenant (Log Analytics ingestion)

> **Note**: Costs vary based on resource usage, region, and tenant activity levels.

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to the bicep directory
cd bicep/

# Set deployment parameters
export RESOURCE_GROUP="rg-saas-control-plane"
export LOCATION="eastus"
export DEPLOYMENT_NAME="multi-tenant-saas-$(date +%Y%m%d-%H%M%S)"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy the infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file main.bicep \
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
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Navigate to the scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy the infrastructure
./deploy.sh

# Verify deployment status
az group list --query "[?contains(name, 'rg-saas-') || contains(name, 'rg-tenant-')].{Name:name, Location:location, Status:properties.provisioningState}" --output table
```

## Deployment Components

### Control Plane Resources

- **Resource Group**: Central management resource group
- **Key Vault**: Secure storage for tenant configurations and secrets
- **Managed Identity**: Identity for deployment automation
- **Log Analytics Workspace**: Centralized logging and monitoring
- **Application Insights**: Platform performance monitoring
- **Custom Azure Policies**: Governance rules for tenant isolation

### Per-Tenant Resources

- **Resource Group**: Isolated resource group per tenant
- **Storage Account**: Tenant-specific storage with security policies
- **Virtual Network**: Isolated network infrastructure
- **Network Security Group**: Tenant-specific security rules
- **Deployment Stack**: Declarative resource lifecycle management

### Security Features

- **Workload Identity**: Keyless authentication for tenant workloads
- **RBAC**: Custom roles for tenant administrators and users
- **Network Isolation**: Tenant-specific VNets and security groups
- **Policy Enforcement**: Automatic compliance monitoring
- **Audit Logging**: Comprehensive activity tracking

## Configuration

### Bicep Parameters

Key parameters you can customize in the Bicep deployment:

```bicep
// Location for all resources
param location string = 'eastus'

// Environment type (dev, staging, prod)
param environment string = 'production'

// SaaS platform prefix for resource naming
param saasPrefix string = 'saas${uniqueString(resourceGroup().id)}'

// Number of sample tenants to create
param initialTenantCount int = 2

// Enable advanced monitoring features
param enableAdvancedMonitoring bool = true

// Storage account tier for tenants
param storageAccountTier string = 'Standard_LRS'
```

### Terraform Variables

Key variables you can customize in the Terraform deployment:

```hcl
# Azure region
variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

# Environment
variable "environment" {
  description = "Environment type"
  type        = string
  default     = "production"
}

# SaaS platform configuration
variable "saas_prefix" {
  description = "Prefix for SaaS resources"
  type        = string
  default     = "saas"
}

# Tenant configuration
variable "initial_tenant_count" {
  description = "Number of initial tenants to create"
  type        = number
  default     = 2
}
```

## Post-Deployment Configuration

### 1. Configure Workload Identity

```bash
# Get the deployed workload identity details
WORKLOAD_APP_ID=$(az ad app list --display-name "SaaS-Tenant-Workload-*" --query '[0].appId' -o tsv)

# Configure federated identity credentials
az ad app federated-credential create \
    --id ${WORKLOAD_APP_ID} \
    --parameters '{
        "name": "tenant-workload-federation",
        "issuer": "https://sts.windows.net/'$(az account show --query tenantId -o tsv)'",
        "subject": "system:serviceaccount:tenant-namespace:tenant-workload",
        "audiences": ["api://AzureADTokenExchange"]
    }'
```

### 2. Test Tenant Provisioning

```bash
# Source the tenant lifecycle functions
source scripts/tenant-lifecycle.sh

# Provision a test tenant
onboard_tenant "test001" "Test Company" "admin@test.com"

# Verify tenant resources
az group show --name "rg-tenant-test001"
az storage account show --name "tenanttest001storage" --resource-group "rg-tenant-test001"
```

### 3. Validate Policy Compliance

```bash
# Check policy assignments
az policy assignment list --query "[?contains(displayName, 'Tenant')].{Name:displayName, Policy:policyDefinitionId}" --output table

# Verify compliance state
az policy state list --query "[?complianceState=='NonCompliant'].{Resource:resourceId, Policy:policyDefinitionName}" --output table
```

## Monitoring and Operations

### Key Metrics to Monitor

1. **Tenant Resource Usage**: CPU, memory, storage consumption per tenant
2. **Security Events**: Failed authentication attempts, policy violations
3. **Deployment Health**: Stack deployment success/failure rates
4. **Cost Tracking**: Resource costs per tenant for chargeback

### Useful Azure Monitor Queries

```kql
// Tenant resource usage summary
AzureActivity
| where TimeGenerated > ago(24h)
| extend TenantId = tostring(parse_json(Properties).TenantId)
| where isnotempty(TenantId)
| summarize Operations = count() by TenantId, OperationName
| order by Operations desc

// Security events by tenant
AzureActivity
| where TimeGenerated > ago(24h)
| where ActivityStatus == "Failed"
| extend TenantId = tostring(parse_json(Properties).TenantId)
| summarize FailedOperations = count() by TenantId
| order by FailedOperations desc
```

## Tenant Lifecycle Management

### Onboarding a New Tenant

```bash
# Use the automated onboarding function
onboard_tenant "tenant004" "New Customer Corp" "admin@newcustomer.com"

# Verify tenant setup
az group show --name "rg-tenant-tenant004"
az policy assignment list --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-tenant-tenant004"
```

### Updating Tenant Configuration

```bash
# Update tenant resources
update_tenant "tenant004" "storageAccountTier=Standard_GRS"

# Verify updates
az storage account show --name "tenanttenant004storage" --resource-group "rg-tenant-tenant004" --query sku.name
```

### Offboarding a Tenant

```bash
# Safely offboard a tenant
offboard_tenant "tenant004"

# Verify cleanup
az group show --name "rg-tenant-tenant004" 2>/dev/null || echo "Tenant successfully offboarded"
```

## Security Best Practices

### 1. Regular Security Reviews

- Review RBAC assignments monthly
- Audit policy compliance weekly
- Monitor security alerts daily
- Rotate managed identity credentials quarterly

### 2. Network Security

- Implement network security groups for all subnets
- Use private endpoints for storage accounts
- Enable DDoS protection for production workloads
- Regularly review firewall rules

### 3. Data Protection

- Enable encryption at rest for all storage accounts
- Use Azure Key Vault for secret management
- Implement backup strategies for tenant data
- Regular disaster recovery testing

## Troubleshooting

### Common Issues

1. **Deployment Failures**
   ```bash
   # Check deployment logs
   az deployment group show --resource-group ${RESOURCE_GROUP} --name ${DEPLOYMENT_NAME} --query properties.error
   
   # Review activity logs
   az monitor activity-log list --resource-group ${RESOURCE_GROUP} --max-events 50
   ```

2. **Policy Compliance Issues**
   ```bash
   # Check policy state
   az policy state list --resource-group "rg-tenant-${TENANT_ID}" --query "[?complianceState=='NonCompliant']"
   
   # Review policy assignment
   az policy assignment show --name "tenant-${TENANT_ID}-tagging"
   ```

3. **Workload Identity Authentication**
   ```bash
   # Test token acquisition
   az account get-access-token --resource https://management.azure.com/
   
   # Verify service principal permissions
   az role assignment list --assignee ${WORKLOAD_SP_ID}
   ```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name ${RESOURCE_GROUP} --yes --no-wait

# Clean up Azure AD applications
az ad app delete --id ${WORKLOAD_APP_ID}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Clean up state files
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify cleanup
az group list --query "[?contains(name, 'rg-saas-') || contains(name, 'rg-tenant-')]" --output table
```

### Manual Cleanup Verification

```bash
# Check for remaining resources
az resource list --query "[?contains(resourceGroup, 'saas') || contains(resourceGroup, 'tenant')]" --output table

# Remove any remaining policy definitions
az policy definition delete --name "require-tenant-tags"
az policy definition delete --name "require-network-security-groups"

# Remove custom RBAC roles
az role definition delete --name "Tenant Administrator"
az role definition delete --name "Tenant User"
```

## Advanced Configuration

### Scaling Considerations

- **Horizontal Scaling**: Add more tenants by running the onboarding process
- **Vertical Scaling**: Increase resource sizes in tenant templates
- **Geographic Distribution**: Deploy control planes in multiple regions
- **Performance Optimization**: Use premium storage tiers for high-throughput tenants

### Integration Options

- **CI/CD Integration**: Incorporate tenant provisioning into DevOps pipelines
- **Monitoring Integration**: Connect to SIEM systems for security monitoring
- **Backup Integration**: Implement automated backup schedules
- **Cost Management**: Integrate with Azure Cost Management APIs

## Support and Documentation

- **Azure Deployment Stacks**: [Official Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/deployment-stacks)
- **Azure Workload Identity**: [Best Practices Guide](https://docs.microsoft.com/en-us/azure/active-directory/workload-identities/workload-identity-federation)
- **Multi-tenant Architecture**: [Azure Architecture Center](https://docs.microsoft.com/en-us/azure/architecture/guide/multitenant/)
- **Azure Policy**: [Governance Documentation](https://docs.microsoft.com/en-us/azure/governance/policy/)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update documentation for any parameter changes
3. Validate security configurations
4. Test tenant lifecycle operations
5. Update monitoring queries as needed

## License

This infrastructure code is provided as-is under the same license as the original recipe documentation.