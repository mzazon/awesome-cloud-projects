# Bicep Templates for Resource Organization with Resource Groups and Tags

This directory contains Bicep templates for implementing resource organization with standardized tagging strategies in Azure.

## Files

- `main.bicep` - Main Bicep template that creates storage accounts and App Service plans with comprehensive tagging
- `parameters.json` - Example parameters for development environment
- `parameters-production.json` - Example parameters for production environment  
- `parameters-shared.json` - Example parameters for shared infrastructure environment

## Architecture

The template demonstrates Azure resource organization best practices by:

- Creating resources with environment-specific configurations
- Implementing a three-tier tagging strategy (functional, accounting, classification)
- Supporting different deployment scenarios for dev, prod, and shared environments
- Following Azure Well-Architected Framework principles

## Prerequisites

- Azure CLI installed and configured
- Bicep CLI installed (comes with Azure CLI 2.20.0+)
- Appropriate Azure permissions to create resource groups and resources
- An Azure subscription

## Quick Start

### 1. Create Resource Groups

First, create the resource groups for each environment:

```bash
# Set variables
LOCATION="eastus"
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Create development resource group
az group create \
    --name "rg-demo-dev-${RANDOM_SUFFIX}" \
    --location ${LOCATION} \
    --tags environment=development purpose=demo department=engineering

# Create production resource group  
az group create \
    --name "rg-demo-prod-${RANDOM_SUFFIX}" \
    --location ${LOCATION} \
    --tags environment=production purpose=demo department=engineering

# Create shared resource group
az group create \
    --name "rg-demo-shared-${RANDOM_SUFFIX}" \
    --location ${LOCATION} \
    --tags environment=shared purpose=infrastructure department=platform
```

### 2. Deploy to Development Environment

```bash
az deployment group create \
    --resource-group "rg-demo-dev-${RANDOM_SUFFIX}" \
    --template-file main.bicep \
    --parameters parameters.json \
    --parameters uniqueSuffix=${RANDOM_SUFFIX}
```

### 3. Deploy to Production Environment

```bash
az deployment group create \
    --resource-group "rg-demo-prod-${RANDOM_SUFFIX}" \
    --template-file main.bicep \
    --parameters parameters-production.json \
    --parameters uniqueSuffix=${RANDOM_SUFFIX}
```

### 4. Deploy to Shared Environment

```bash
az deployment group create \
    --resource-group "rg-demo-shared-${RANDOM_SUFFIX}" \
    --template-file main.bicep \
    --parameters parameters-shared.json \
    --parameters uniqueSuffix=${RANDOM_SUFFIX}
```

## Parameter Customization

### Required Parameters

- `costCenter` - Cost center for billing allocation
- `owner` - Owner of the resources

### Optional Parameters

- `uniqueSuffix` - Unique suffix for resource names (defaults to generated value)
- `location` - Azure region (defaults to resource group location)
- `environment` - Environment type (development, production, shared)
- `department` - Department responsible for resources
- `projectName` - Project name for organization
- `purpose` - Purpose of the resources
- `storageAccountSku` - Storage account performance tier
- `appServicePlanSku` - App Service plan pricing tier
- `createSampleResources` - Whether to create demo resources

### Environment-Specific Parameters

**Production Environment:**
- `slaRequirement` - Service level agreement requirement
- `backupRequirement` - Backup frequency requirement  
- `complianceRequirement` - Compliance framework requirement

## Tagging Strategy

The template implements a comprehensive tagging strategy:

### Common Tags (Applied to All Resources)
- `environment` - Environment designation
- `purpose` - Resource purpose
- `department` - Owning department
- `costcenter` - Cost allocation center
- `owner` - Resource owner
- `project` - Project name
- `lastUpdated` - Last modification date
- `managedBy` - Management tool
- `automation` - Automation status

### Environment-Specific Tags
- **Production**: `sla`, `backup`, `compliance`, `auditRequired`
- **Shared**: `scope` (multi-environment)

### Resource-Specific Tags
- **Storage Account**: `tier`, `dataclass`, `encryption`, `backup`
- **App Service Plan**: `tier`, `workload`, `monitoring`

## Validation

After deployment, validate the resources and tags:

```bash
# List resources with tags
az resource list \
    --resource-group "rg-demo-dev-${RANDOM_SUFFIX}" \
    --query "[].{Name:name, Type:type, Tags:tags}" \
    --output table

# Query by environment tag
az resource list \
    --tag environment=development \
    --query "[].{Name:name, Type:type, ResourceGroup:resourceGroup}" \
    --output table
```

## Cost Management Integration

The tagging strategy supports Azure Cost Management features:

- **Cost Allocation**: Use `costcenter` and `department` tags
- **Budget Alerts**: Filter by `environment` or `project` tags  
- **Chargeback/Showback**: Combine `department`, `costcenter`, and `owner` tags

## Cleanup

Remove the resource groups and all contained resources:

```bash
# Delete all created resource groups
az group delete --name "rg-demo-dev-${RANDOM_SUFFIX}" --yes --no-wait
az group delete --name "rg-demo-prod-${RANDOM_SUFFIX}" --yes --no-wait  
az group delete --name "rg-demo-shared-${RANDOM_SUFFIX}" --yes --no-wait
```

## Best Practices Implemented

1. **Security**: HTTPS-only storage, TLS 1.2 minimum, disabled public blob access
2. **Naming**: Consistent naming conventions with environment and uniqueness
3. **Tagging**: Comprehensive three-tier tagging strategy
4. **Parameterization**: Flexible parameter system for different environments
5. **Outputs**: Detailed outputs for integration and validation
6. **Documentation**: Extensive inline comments and documentation

## Extending the Template

Common extensions:

1. **Add more resource types** (Virtual Networks, Key Vaults, etc.)
2. **Implement Azure Policy** for tag enforcement  
3. **Add monitoring resources** (Log Analytics, Application Insights)
4. **Create Bicep modules** for reusable components
5. **Add deployment scripts** for automation

## Support

For issues with this template:
- Review the original recipe documentation
- Check Azure Bicep documentation
- Validate parameter values and permissions
- Review Azure Resource Manager deployment logs