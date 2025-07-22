# Infrastructure as Code for Multi-Language Content Localization Workflows with Azure Translator and Azure AI Document Intelligence

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Language Content Localization Workflows with Azure Translator and Azure AI Document Intelligence".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az --version` should show 2.0 or later)
- Appropriate Azure subscription with permissions for:
  - Resource group creation
  - Cognitive Services resource creation
  - Storage account creation and management
  - Logic Apps creation and configuration
  - API connections management
- Basic understanding of Azure resource management
- Estimated cost: $50-100/month for development and testing scenarios

> **Note**: Azure Translator and Document Intelligence services are available in specific regions. This implementation defaults to East US which supports both services.

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Create resource group
az group create --name rg-localization-workflow --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-localization-workflow \
    --template-file main.bicep \
    --parameters @parameters.json

# Get deployment outputs
az deployment group show \
    --resource-group rg-localization-workflow \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will create all resources and display connection information
```

## Architecture Overview

This implementation creates the following Azure resources:

- **Resource Group**: Container for all localization workflow resources
- **Azure Translator**: Cognitive service for multi-language text translation
- **Azure AI Document Intelligence**: Service for intelligent text extraction from documents
- **Azure Storage Account**: Storage for source documents, processing workspace, and localized output
- **Azure Logic App**: Workflow orchestration for automated document processing
- **API Connections**: Secure connections between Logic Apps and Azure services

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourceGroupName": {
      "value": "rg-localization-workflow"
    },
    "location": {
      "value": "eastus"
    },
    "storageAccountName": {
      "value": "stlocalization"
    },
    "translatorName": {
      "value": "translator-service"
    },
    "documentIntelligenceName": {
      "value": "doc-intelligence-service"
    },
    "logicAppName": {
      "value": "logic-localization-workflow"
    },
    "translatorSku": {
      "value": "S1"
    },
    "documentIntelligenceSku": {
      "value": "S0"
    },
    "targetLanguages": {
      "value": ["es", "fr", "de", "it", "pt"]
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
resource_group_name = "rg-localization-workflow"
location = "eastus"
storage_account_name = "stlocalization"
translator_name = "translator-service"
document_intelligence_name = "doc-intelligence-service"
logic_app_name = "logic-localization-workflow"
translator_sku = "S1"
document_intelligence_sku = "S0"
target_languages = ["es", "fr", "de", "it", "pt"]
```

### Bash Script Environment Variables

The deploy script uses these environment variables (auto-generated with random suffixes):

```bash
export RESOURCE_GROUP="rg-localization-workflow"
export LOCATION="eastus"
export STORAGE_ACCOUNT="st$(openssl rand -hex 6)"
export TRANSLATOR_NAME="translator-$(openssl rand -hex 4)"
export DOC_INTELLIGENCE_NAME="doc-intel-$(openssl rand -hex 4)"
export LOGIC_APP_NAME="logic-localization-$(openssl rand -hex 4)"
```

## Testing the Deployment

After deployment, test the localization workflow:

1. **Upload a test document**:
   ```bash
   # Create test document
   echo "Welcome to our global organization. This document contains important business information." > test-document.txt
   
   # Upload to source container
   az storage blob upload \
       --file test-document.txt \
       --name test-document.txt \
       --container-name source-documents \
       --account-name <storage-account-name>
   ```

2. **Monitor workflow execution**:
   ```bash
   # Check Logic App run history
   az logic workflow list-runs \
       --name <logic-app-name> \
       --resource-group <resource-group-name>
   ```

3. **Verify translated output**:
   ```bash
   # List translated documents
   az storage blob list \
       --container-name localized-output \
       --account-name <storage-account-name> \
       --output table
   ```

## Monitoring and Troubleshooting

### View Logic App Execution History

```bash
# Get recent workflow runs
az logic workflow list-runs \
    --name <logic-app-name> \
    --resource-group <resource-group-name> \
    --query '[].{startTime:startTime,status:status,triggerName:trigger.name}' \
    --output table
```

### Check Service Health

```bash
# Verify Translator service
az cognitiveservices account show \
    --name <translator-name> \
    --resource-group <resource-group-name> \
    --query '{name:name,location:location,status:properties.provisioningState}'

# Verify Document Intelligence service
az cognitiveservices account show \
    --name <doc-intelligence-name> \
    --resource-group <resource-group-name> \
    --query '{name:name,location:location,status:properties.provisioningState}'
```

### Monitor Costs

```bash
# Check current month's costs for the resource group
az consumption usage list \
    --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/<resource-group-name>" \
    --start-date $(date -d "$(date +%Y-%m-01)" +%Y-%m-%d) \
    --end-date $(date +%Y-%m-%d)
```

## Security Considerations

This implementation follows Azure security best practices:

- **Managed Identity**: Services use managed identities where possible
- **Private Endpoints**: Consider enabling private endpoints for production
- **Key Vault Integration**: Secrets are managed through secure Azure services
- **RBAC**: Role-based access control for service authentication
- **Encryption**: All data is encrypted at rest and in transit

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name rg-localization-workflow --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Cost Optimization

- **Storage Lifecycle**: Implement lifecycle policies for processed documents
- **Translator Usage**: Monitor translation volume and consider batch processing
- **Logic App Pricing**: Use consumption plan for variable workloads
- **Document Intelligence**: Optimize document processing frequency

## Scaling Considerations

- **Parallel Processing**: Logic Apps can process multiple documents concurrently
- **Regional Distribution**: Deploy in multiple regions for global performance
- **Batch Processing**: Group documents for more efficient processing
- **Queue Management**: Use Service Bus for high-volume document processing

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for configuration details
2. Review Azure service documentation for specific service issues
3. Verify all prerequisites are met
4. Check Azure service health status
5. Review Logic App execution logs for workflow issues

## Extended Features

This implementation can be extended with:

- **Custom Translation Models**: Train domain-specific models
- **Approval Workflows**: Add human-in-the-loop approval processes
- **Multi-format Output**: Generate multiple output formats
- **Real-time Translation**: Build web interfaces for live translation
- **Analytics Dashboard**: Add comprehensive monitoring and reporting

For detailed implementation guidance, refer to the original recipe documentation.