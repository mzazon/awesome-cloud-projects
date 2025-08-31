# Infrastructure as Code for Resource Organization with Resource Groups and Tags

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Resource Organization with Resource Groups and Tags".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM template language)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.10.0 or later)
- Active Azure subscription with contributor or owner permissions
- For Terraform: Terraform CLI installed (version 1.0 or later)
- For Bicep: Bicep CLI installed (latest version)
- Understanding of Azure resource hierarchy and organizational structure

## Quick Start

### Using Bicep
```bash
cd bicep/

# Deploy the infrastructure
az deployment sub create \
    --location eastus \
    --template-file main.bicep \
    --parameters location=eastus \
                 environment=demo \
                 randomSuffix=$(openssl rand -hex 3)
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment
az group list --query "[?contains(name, 'rg-demo')].{Name:name, Location:location, Tags:tags}" --output table
```

## Architecture Overview

This implementation creates a structured resource organization pattern with:

- **Three Resource Groups**: Development, Production, and Shared environments
- **Standardized Tagging Strategy**: Functional, accounting, and classification tags
- **Sample Resources**: Storage accounts and App Service plans demonstrating tag inheritance
- **Cost Management Integration**: Tags designed for accurate cost allocation and reporting

## Resource Components

### Resource Groups
- Development environment resource group with dev-specific tags
- Production environment resource group with enhanced governance tags
- Shared resource group for cross-environment infrastructure

### Sample Resources
- Storage accounts in each environment with appropriate performance tiers
- App Service plans demonstrating different SKUs for dev/prod environments
- Environment-specific tagging for cost allocation and compliance

### Tagging Strategy
- **Functional Tags**: Environment, purpose, project identification
- **Accounting Tags**: Department, cost center, owner assignment
- **Classification Tags**: SLA requirements, backup schedules, compliance standards

## Customization

### Bicep Parameters
- `location`: Azure region for resource deployment
- `environment`: Environment identifier (dev, prod, shared)
- `randomSuffix`: Unique suffix for resource naming
- `department`: Department tag for cost allocation
- `costCenter`: Cost center identifier for financial reporting

### Terraform Variables
- `location`: Azure region for deployment
- `random_suffix`: Unique identifier for resource names
- `tags_common`: Common tags applied to all resources
- `department`: Department for cost allocation
- `project_name`: Project identifier for resource grouping

### Environment Variables
The bash scripts use these environment variables for customization:
- `LOCATION`: Azure region (default: eastus)
- `SUBSCRIPTION_ID`: Azure subscription identifier
- `RANDOM_SUFFIX`: Unique suffix for resource naming

## Tag Categories

### Functional Tags
- `environment`: Environment classification (development, production, shared)
- `purpose`: Resource purpose (demo, infrastructure, application)
- `project`: Project identifier for resource grouping

### Accounting Tags
- `department`: Organizational department for cost allocation
- `costcenter`: Cost center identifier for financial reporting
- `owner`: Resource owner or responsible team

### Classification Tags
- `sla`: Service level agreement requirements (high, medium, standard)
- `backup`: Backup schedule requirements (daily, weekly, none)
- `compliance`: Regulatory compliance requirements (sox, hipaa, pci)

## Cost Management Integration

The tagging strategy supports Azure Cost Management features:

- **Tag Inheritance**: Resource group tags automatically apply to usage records
- **Cost Allocation**: Department and cost center tags enable accurate chargeback
- **Budget Alerts**: Environment and project tags support automated budget monitoring
- **Reporting**: Consistent tagging enables detailed financial reporting

## Validation Commands

After deployment, verify the setup with these commands:

```bash
# List all resource groups with tags
az group list --query "[?contains(name, 'rg-demo')].{Name:name, Tags:tags}" --output table

# Query resources by environment
az resource list --tag environment=development --query "[].{Name:name, Type:type}" --output table

# Generate cost allocation report
az resource list --query "[?tags.costcenter != null].{Name:name, Environment:tags.environment, CostCenter:tags.costcenter}" --output table

# Check tag inheritance on individual resources
az storage account list --query "[?contains(name, 'stdev')].{Name:name, Tags:tags}" --output json
```

## Cleanup

### Using Bicep
```bash
# Delete resource groups (this will delete all contained resources)
az group delete --name rg-demo-dev-<suffix> --yes --no-wait
az group delete --name rg-demo-prod-<suffix> --yes --no-wait
az group delete --name rg-demo-shared-<suffix> --yes --no-wait
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

## Best Practices Implemented

### Security
- Least privilege access patterns through resource group organization
- Production environment isolation with enhanced tagging
- Sensitive data classification through security tags

### Cost Optimization
- Environment-specific resource tiers (Basic for dev, Premium for prod)
- Shared resource groups to avoid duplication
- Comprehensive tagging for accurate cost allocation

### Operational Excellence
- Consistent naming conventions across all resources
- Standardized tagging strategy for automation support
- Clear ownership and responsibility assignment

### Governance
- Policy-ready tag structure for automated enforcement
- Compliance tags for regulatory requirements
- Audit trail support through management tags

## Troubleshooting

### Common Issues

1. **Resource Group Creation Fails**
   - Verify Azure CLI authentication: `az account show`
   - Check subscription permissions: `az role assignment list --assignee $(az account show --query user.name -o tsv)`

2. **Tag Application Issues**
   - Ensure tag values don't exceed Azure limits (512 characters)
   - Verify tag names follow Azure naming conventions

3. **Storage Account Creation Fails**
   - Storage account names must be globally unique
   - Names must be 3-24 characters, lowercase letters and numbers only

4. **Cost Management Not Showing Tags**
   - Tag inheritance may take 24-48 hours to appear in cost reports
   - Verify tags are applied at both resource group and resource levels

## Extension Opportunities

This implementation can be extended with:

- **Azure Policy Integration**: Automated tag enforcement and compliance monitoring
- **Cost Management Automation**: Budget alerts and automated cost optimization
- **Governance Frameworks**: Management group hierarchies with consistent policies
- **Lifecycle Management**: Automated resource lifecycle based on tags
- **Advanced Reporting**: Custom dashboards and automated compliance reports

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation in the parent directory
2. Consult Azure Resource Manager and tagging documentation
3. Check Azure CLI command reference for latest syntax
4. Verify Azure subscription limits and quotas

## Additional Resources

- [Azure Resource Manager documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/)
- [Azure tagging strategies](https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/tag-resources)
- [Azure Cost Management best practices](https://docs.microsoft.com/en-us/azure/cost-management-billing/)
- [Azure naming conventions](https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/naming-and-tagging)