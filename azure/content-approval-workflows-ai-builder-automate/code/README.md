# Infrastructure as Code for Content Approval Workflows with AI Builder and Power Automate

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Content Approval Workflows with AI Builder and Power Automate".

## Available Implementations

- **Bicep**: Azure native infrastructure as code language
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts for manual configuration

## Prerequisites

### General Requirements
- Azure subscription with appropriate permissions
- Microsoft 365 E3/E5 subscription or Power Platform premium licenses
- Azure CLI installed and configured (`az login` completed)
- PowerShell 7+ with PnP PowerShell module installed
- SharePoint Online admin permissions
- Power Platform environment admin permissions

### Tool-Specific Prerequisites

#### For Bicep Deployment
- Azure CLI with Bicep extension installed
- Resource group creation permissions
- Power Platform admin role

#### For Terraform Deployment
- Terraform 1.0+ installed
- Azure authentication configured (Service Principal or Managed Identity)
- Power Platform terraform provider access

#### For Bash Scripts
- PnP PowerShell module: `Install-Module PnP.PowerShell -Force -AllowClobber`
- Azure PowerShell module: `Install-Module Az -Force -AllowClobber`
- Microsoft.Graph PowerShell SDK: `Install-Module Microsoft.Graph -Force -AllowClobber`

### Permission Requirements
- SharePoint Online Administrator
- Power Platform Administrator
- Teams Administrator
- Global Administrator (for tenant-wide settings)

## Quick Start

### Using Bicep

```bash
# Set deployment variables
export RESOURCE_GROUP_NAME="rg-content-approval-workflows"
export LOCATION="eastus"
export TENANT_NAME="yourtenant"

# Create resource group
az group create \
    --name $RESOURCE_GROUP_NAME \
    --location $LOCATION

# Deploy infrastructure
az deployment group create \
    --resource-group $RESOURCE_GROUP_NAME \
    --template-file bicep/main.bicep \
    --parameters tenantName=$TENANT_NAME \
    --parameters location=$LOCATION
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan \
    -var="tenant_name=yourtenant" \
    -var="location=East US"

# Apply infrastructure
terraform apply \
    -var="tenant_name=yourtenant" \
    -var="location=East US"
```

### Using Bash Scripts

```bash
# Set environment variables
export TENANT_NAME="yourtenant"
export TENANT_DOMAIN="${TENANT_NAME}.onmicrosoft.com"

# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh
```

## Deployment Components

This infrastructure deployment creates and configures:

### SharePoint Online Components
- Team site for content approval workflows
- Document library with content approval enabled
- Custom columns for AI analysis results
- Content types for document categorization
- Permission groups for approval workflows

### Power Platform Components
- Power Automate cloud flow for approval workflow
- AI Builder custom prompt for content analysis
- SharePoint connector configuration
- Teams connector for adaptive cards
- Approval connector for workflow management

### Microsoft Teams Integration
- Custom adaptive card templates
- Teams app registration for workflow bot
- Channel notification configurations
- Approval action configurations

### Security and Governance
- Managed identities for secure service connections
- Least privilege access controls
- Data loss prevention (DLP) policy configurations
- Audit logging and compliance settings

## Configuration Options

### Environment Variables

#### Required Variables
```bash
export TENANT_NAME="yourtenant"              # Your M365 tenant name
export LOCATION="eastus"                     # Azure region for resources
export RESOURCE_GROUP_NAME="rg-approval"    # Resource group name
```

#### Optional Variables
```bash
export SITE_SUFFIX="workflows"               # SharePoint site name suffix
export LIBRARY_NAME="DocumentsForApproval"  # Document library name
export AI_PROMPT_NAME="ContentAnalyzer"     # AI Builder prompt name
export FLOW_NAME="ContentApprovalFlow"      # Power Automate flow name
```

### Bicep Parameters

```bicep
// Required parameters
param tenantName string              // M365 tenant name
param location string               // Azure region

// Optional parameters
param siteSuffix string = 'workflows'
param libraryName string = 'DocumentsForApproval'
param aiPromptName string = 'ContentAnalyzer'
param flowName string = 'ContentApprovalFlow'
param enableContentApproval bool = true
param riskLevels array = ['Low', 'Medium', 'High', 'Critical']
```

### Terraform Variables

```hcl
variable "tenant_name" {
  description = "Microsoft 365 tenant name"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "site_suffix" {
  description = "SharePoint site name suffix"
  type        = string
  default     = "workflows"
}

variable "library_name" {
  description = "SharePoint document library name"
  type        = string
  default     = "DocumentsForApproval"
}

variable "enable_content_approval" {
  description = "Enable SharePoint content approval"
  type        = bool
  default     = true
}
```

## Post-Deployment Configuration

After infrastructure deployment, complete these manual configuration steps:

### 1. AI Builder Prompt Configuration

```bash
# Navigate to Power Apps portal
# 1. Sign in to https://make.powerapps.com/
# 2. Select "AI hub" > "Prompts"
# 3. Configure the "Content Approval Analyzer" prompt
# 4. Test the prompt with sample content
# 5. Publish the prompt for production use
```

### 2. Power Automate Flow Setup

```bash
# Configure the approval workflow
# 1. Go to https://make.powerautomate.com/
# 2. Edit "Intelligent Content Approval Workflow"
# 3. Configure SharePoint site and library connections
# 4. Map AI Builder prompt to content analysis step
# 5. Configure Teams adaptive card templates
# 6. Test the complete workflow
```

### 3. Teams Integration

```bash
# Set up Teams notifications
# 1. Create Teams channels for notifications
# 2. Configure adaptive card permissions
# 3. Test approval cards in Teams
# 4. Verify channel notification delivery
```

## Validation and Testing

### Infrastructure Validation

```bash
# Verify SharePoint site creation
az rest --method GET \
    --url "https://${TENANT_NAME}.sharepoint.com/sites/content-approval-workflows/_api/web" \
    --resource "https://${TENANT_NAME}.sharepoint.com"

# Check Power Platform environment
az rest --method GET \
    --url "https://api.powerapps.com/providers/Microsoft.PowerApps/environments" \
    --resource "https://service.powerapps.com"
```

### Workflow Testing

```bash
# Test document upload and workflow trigger
# 1. Upload test document to SharePoint library
# 2. Verify Power Automate flow execution
# 3. Check AI Builder prompt processing
# 4. Confirm Teams adaptive card delivery
# 5. Test approval/rejection actions
```

### Security Validation

```bash
# Verify access controls
# 1. Test SharePoint library permissions
# 2. Validate Power Automate connection security
# 3. Confirm Teams integration permissions
# 4. Review audit logs for compliance
```

## Troubleshooting

### Common Issues

#### SharePoint Site Creation Failures
```bash
# Check SharePoint admin permissions
# Verify tenant domain configuration
# Ensure site collection limits not exceeded
# Review SharePoint service health status
```

#### Power Automate Flow Errors
```bash
# Verify connector permissions
# Check AI Builder credit availability
# Validate SharePoint library configuration
# Review flow run history for error details
```

#### Teams Integration Issues
```bash
# Confirm Teams app permissions
# Verify adaptive card schema validation
# Check Teams channel accessibility
# Review Microsoft Graph API permissions
```

### Log Analysis

```bash
# Power Automate flow logs
# Navigate to flow run history in Power Automate portal
# Review each step execution status
# Check connector authentication status

# SharePoint audit logs
# Access SharePoint admin center
# Review site collection audit logs
# Check document library activity logs

# Teams activity logs
# Use Microsoft 365 admin center
# Review Teams usage reports
# Check adaptive card delivery status
```

## Cleanup

### Using Bicep

```bash
# Delete resource group and all resources
az group delete \
    --name $RESOURCE_GROUP_NAME \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Destroy all Terraform-managed resources
cd terraform/
terraform destroy \
    -var="tenant_name=yourtenant" \
    -var="location=East US"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual cleanup verification
# 1. Verify SharePoint site deletion
# 2. Confirm Power Automate flow removal
# 3. Check AI Builder prompt deletion
# 4. Validate Teams integration cleanup
```

### Manual Cleanup Steps

```bash
# Remove Power Platform resources
# 1. Delete Power Automate flows
# 2. Remove AI Builder prompts
# 3. Clean up SharePoint connections
# 4. Remove Teams app registrations

# SharePoint cleanup
# 1. Delete site collection from recycle bin
# 2. Remove custom content types
# 3. Clear document library templates
# 4. Reset SharePoint app permissions
```

## Cost Considerations

### Azure Resources
- Power Platform premium licenses: ~$20/user/month
- AI Builder credits: $500/month for 1M credits
- SharePoint Online storage: Included with M365 licenses
- Azure AD Premium (if required): $6/user/month

### Usage-Based Costs
- AI Builder prompt executions: Variable based on usage
- Power Automate premium connector usage: Variable
- SharePoint storage overage: $0.20/GB/month
- Teams phone system (if used): $8/user/month

### Cost Optimization Tips
- Monitor AI Builder credit consumption
- Use conditional logic to reduce unnecessary workflow runs
- Implement document size limits to control processing costs
- Review and optimize approval routing logic regularly

## Security Best Practices

### Authentication and Authorization
- Use managed identities for service connections
- Implement least privilege access controls
- Enable multi-factor authentication for admin accounts
- Regular access reviews for SharePoint and Power Platform

### Data Protection
- Enable SharePoint Online encryption at rest
- Configure data loss prevention (DLP) policies
- Implement information barriers if required
- Regular backup of critical workflow configurations

### Compliance and Auditing
- Enable audit logging for all components
- Configure retention policies for approval records
- Implement eDiscovery holds if required
- Regular compliance reporting and review

## Support and Maintenance

### Monitoring and Alerting
- Set up Power Automate flow failure notifications
- Monitor AI Builder credit consumption
- Track SharePoint storage usage
- Configure Teams channel health monitoring

### Regular Maintenance Tasks
- Review and update AI Builder prompts
- Optimize Power Automate flow performance
- Clean up inactive SharePoint sites
- Update Teams adaptive card templates

### Backup and Recovery
- Export Power Automate flow definitions
- Backup SharePoint site templates
- Document AI Builder prompt configurations
- Maintain Teams integration settings backup

## Additional Resources

- [SharePoint Online Documentation](https://docs.microsoft.com/en-us/sharepoint/)
- [Power Automate Documentation](https://docs.microsoft.com/en-us/power-automate/)
- [AI Builder Documentation](https://docs.microsoft.com/en-us/ai-builder/)
- [Microsoft Teams Platform Documentation](https://docs.microsoft.com/en-us/microsoftteams/platform/)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or Microsoft's official documentation for each service.