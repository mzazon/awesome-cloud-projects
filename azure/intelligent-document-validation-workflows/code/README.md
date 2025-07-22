# Infrastructure as Code for Intelligent Document Validation Workflows with Dataverse and AI Document Intelligence

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Document Validation Workflows with Dataverse and AI Document Intelligence".

## Available Implementations

- **Bicep**: Azure native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code  
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az --version` should show v2.50.0 or later)
- Azure subscription with appropriate permissions for:
  - AI services (Cognitive Services)
  - Logic Apps
  - Storage Accounts
  - Key Vault
  - Monitor and Application Insights
- Microsoft 365 or Power Platform license for Azure Dataverse and Power Apps
- Power Platform administrator permissions for environment creation
- SharePoint Online or OneDrive for Business for document storage
- Appropriate Azure RBAC permissions:
  - Contributor role on target resource group
  - Cognitive Services Contributor
  - Logic App Contributor
  - Storage Account Contributor
  - Key Vault Administrator

## Architecture Overview

This solution creates an automated document processing and validation system that includes:

- **Azure AI Document Intelligence**: Intelligent data extraction from business documents
- **Azure Logic Apps**: Workflow orchestration for document processing
- **Azure Dataverse**: Secure data storage with business rules enforcement
- **Power Apps**: User-friendly validation interfaces
- **Azure Key Vault**: Secure credential management
- **Azure Storage**: Document storage and training data
- **Azure Monitor**: Comprehensive observability and alerting

## Quick Start

### Using Bicep

```bash
# Navigate to bicep directory
cd bicep/

# Login to Azure (if not already authenticated)
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Create resource group
az group create --name rg-doc-validation --location eastus

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-doc-validation \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment status
az deployment group show \
    --resource-group rg-doc-validation \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply

# Confirm when prompted by typing 'yes'
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# Follow the interactive prompts for configuration
```

## Configuration

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
    "environment": {
      "value": "prod"
    },
    "documentIntelligenceSku": {
      "value": "S0"
    },
    "storageAccountSku": {
      "value": "Standard_LRS"
    }
  }
}
```

### Terraform Variables

Customize `terraform/terraform.tfvars`:

```hcl
# Required variables
location = "East US"
environment = "prod"

# Optional variables
document_intelligence_sku = "S0"
storage_account_tier = "Standard"
storage_account_replication_type = "LRS"

# Tags
tags = {
  Environment = "Production"
  Project     = "DocumentValidation"
  Owner       = "DataTeam"
}
```

### Environment Variables (Bash Scripts)

The bash scripts use these environment variables (set automatically or customize as needed):

```bash
export RESOURCE_GROUP="rg-doc-validation-${RANDOM_SUFFIX}"
export LOCATION="eastus"
export DOC_INTEL_NAME="docint-${RANDOM_SUFFIX}"
export LOGIC_APP_NAME="logic-docvalidation-${RANDOM_SUFFIX}"
export STORAGE_ACCOUNT="stdocval${RANDOM_SUFFIX}"
export KEYVAULT_NAME="kv-docval-${RANDOM_SUFFIX}"
```

## Post-Deployment Configuration

After deploying the Azure infrastructure, you'll need to complete these manual steps:

### 1. Power Platform Environment Setup

1. Navigate to [Power Platform Admin Center](https://admin.powerplatform.microsoft.com/)
2. Create a new environment for document validation
3. Enable Dataverse for the environment
4. Note the environment URL for Logic Apps configuration

### 2. Dataverse Table Creation

Create custom tables in Dataverse for document validation:

```bash
# Example table structure for invoice validation
# This requires Power Platform CLI or manual creation through maker portal
# Tables needed:
# - DocumentProcessing (main table)
# - ValidationRules (business rules)
# - ApprovalQueue (pending approvals)
```

### 3. Logic Apps Configuration

1. Open the created Logic App in Azure Portal
2. Add connections to:
   - SharePoint Online (for document triggers)
   - Azure AI Document Intelligence (using Key Vault secrets)
   - Dataverse (for data storage)
3. Configure the workflow triggers and actions

### 4. Power Apps Creation

1. Navigate to [Power Apps maker portal](https://make.powerapps.com/)
2. Create a canvas app connected to your Dataverse environment
3. Build screens for document review and approval workflows
4. Publish the app for business users

### 5. SharePoint Document Library

1. Create a SharePoint document library for document uploads
2. Configure the Logic App trigger to monitor this library
3. Set appropriate permissions for document uploaders

## Validation & Testing

### Verify Infrastructure Deployment

```bash
# Check resource group contents
az resource list --resource-group rg-doc-validation --output table

# Verify Document Intelligence service
az cognitiveservices account show \
    --name your-docint-name \
    --resource-group rg-doc-validation

# Test Key Vault access
az keyvault secret list --vault-name your-keyvault-name

# Check Logic App status
az logic workflow show \
    --name your-logic-app-name \
    --resource-group rg-doc-validation \
    --query "state"
```

### Test Document Processing

1. Upload a test document to the configured SharePoint library
2. Monitor Logic App runs in Azure Portal
3. Verify extracted data appears in Dataverse
4. Test approval workflow in Power Apps

### Monitor System Health

```bash
# View Logic App run history
az logic workflow run list \
    --workflow-name your-logic-app-name \
    --resource-group rg-doc-validation

# Check Application Insights metrics
az monitor app-insights metrics show \
    --app your-app-insights-name \
    --resource-group rg-doc-validation \
    --metric requests/count
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name rg-doc-validation --yes --no-wait

# Verify deletion
az group exists --name rg-doc-validation
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted by typing 'yes'
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Required

After running automated cleanup, manually remove:

1. **Power Platform Environment**: Delete through Power Platform Admin Center
2. **Power Apps**: Remove any created apps from maker portal
3. **SharePoint Configuration**: Clean up document library triggers if needed

## Customization

### Scaling Configuration

- **Document Intelligence**: Upgrade to F0 (free) for testing or higher SKUs for production volume
- **Storage Account**: Configure lifecycle management for cost optimization
- **Logic Apps**: Implement parallel processing for high-volume scenarios

### Security Enhancements

- **Key Vault**: Enable soft delete and purge protection
- **Storage Account**: Configure private endpoints and disable public access
- **Logic Apps**: Implement managed identity authentication
- **Dataverse**: Configure field-level security and audit logging

### Integration Options

- **SharePoint**: Configure multiple document libraries for different document types
- **Teams**: Add Teams notifications for approval workflows
- **Power BI**: Create analytics dashboards for processing metrics
- **Azure Synapse**: Implement advanced analytics on document data

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   - Verify subscription limits and quotas
   - Check resource naming conflicts
   - Ensure proper permissions

2. **Logic App Connection Issues**:
   - Verify service principal permissions
   - Check Key Vault access policies
   - Validate connection strings

3. **Document Processing Errors**:
   - Review Document Intelligence model compatibility
   - Check document format requirements
   - Verify storage account access

### Monitoring and Debugging

- **Application Insights**: Monitor application performance and errors
- **Logic Apps**: Use run history and trigger history for debugging
- **Key Vault**: Review access logs for authentication issues
- **Storage Account**: Monitor blob access patterns and errors

## Cost Optimization

### Resource Optimization

- Use Azure Advisor recommendations for cost optimization
- Implement storage lifecycle policies for document archival
- Consider consumption-based pricing for Logic Apps
- Monitor Document Intelligence usage and optimize model selection

### Estimated Monthly Costs

- **Document Intelligence**: $0.50 per 1,000 pages (S0 tier)
- **Logic Apps**: $0.000025 per action execution
- **Storage Account**: $0.018 per GB (Standard LRS)
- **Key Vault**: $0.03 per 10,000 operations
- **Application Insights**: $2.88 per GB of data ingested

## Support

### Documentation Resources

- [Azure AI Document Intelligence Documentation](https://docs.microsoft.com/en-us/azure/ai-services/document-intelligence/)
- [Azure Dataverse Documentation](https://docs.microsoft.com/en-us/power-platform/admin/dataverse-best-practices)
- [Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Power Apps Documentation](https://docs.microsoft.com/en-us/power-apps/)

### Community Support

- [Azure Community Forums](https://techcommunity.microsoft.com/t5/azure/ct-p/Azure)
- [Power Platform Community](https://powerusers.microsoft.com/)
- [Stack Overflow - Azure](https://stackoverflow.com/questions/tagged/azure)

### Professional Support

For production deployments, consider:
- Azure Professional Direct support
- Power Platform premium support
- Microsoft consulting services for complex implementations

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate against Azure best practices
3. Update documentation for any configuration changes
4. Follow the repository's contribution guidelines

---

For issues with this infrastructure code, refer to the original recipe documentation or the Azure documentation links provided above.