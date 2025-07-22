# Infrastructure as Code for Document Processing with AI Intelligence and Logic Apps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Document Processing with AI Intelligence and Logic Apps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login`)
- Azure subscription with Contributor permissions
- Appropriate permissions for resource creation:
  - Cognitive Services Contributor
  - Storage Account Contributor
  - Logic Apps Contributor
  - Key Vault Contributor
  - Service Bus Contributor
- For Bicep: Azure CLI with Bicep extension
- For Terraform: Terraform CLI (v1.0+)

## Architecture Overview

This solution deploys:
- **Azure AI Document Intelligence**: For intelligent document processing
- **Logic Apps**: For workflow orchestration
- **Azure Storage**: For document input/output storage
- **Azure Key Vault**: For secure credential management
- **Azure Service Bus**: For reliable message processing
- **System-assigned Managed Identity**: For secure service authentication

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group your-resource-group \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration

### Required Parameters

- `resourceGroupName`: Name of the resource group
- `location`: Azure region for deployment (default: eastus)
- `storageAccountName`: Name for the storage account (must be globally unique)
- `keyVaultName`: Name for the Key Vault (must be globally unique)
- `documentIntelligenceName`: Name for the Document Intelligence service
- `logicAppName`: Name for the Logic App
- `serviceBusNamespaceName`: Name for the Service Bus namespace

### Optional Parameters

- `storageAccountSku`: Storage account SKU (default: Standard_LRS)
- `documentIntelligenceSku`: Document Intelligence pricing tier (default: S0)
- `serviceBusSku`: Service Bus pricing tier (default: Standard)
- `tags`: Resource tags for organization and cost tracking

## Deployment Steps

### 1. Prepare Environment

```bash
# Set environment variables
export RESOURCE_GROUP="rg-docprocessing-demo"
export LOCATION="eastus"
export STORAGE_ACCOUNT="stdocs$(openssl rand -hex 3)"
export KEY_VAULT_NAME="kv-docs-$(openssl rand -hex 3)"

# Create resource group
az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION
```

### 2. Deploy Infrastructure

Choose one of the deployment methods below:

#### Option A: Bicep Deployment

```bash
# Deploy with Bicep
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file bicep/main.bicep \
    --parameters location=$LOCATION \
                storageAccountName=$STORAGE_ACCOUNT \
                keyVaultName=$KEY_VAULT_NAME
```

#### Option B: Terraform Deployment

```bash
# Initialize and deploy with Terraform
cd terraform/
terraform init
terraform plan -var="resource_group_name=$RESOURCE_GROUP" \
               -var="location=$LOCATION" \
               -var="storage_account_name=$STORAGE_ACCOUNT" \
               -var="key_vault_name=$KEY_VAULT_NAME"
terraform apply
```

#### Option C: Bash Script Deployment

```bash
# Deploy with bash scripts
./scripts/deploy.sh
```

### 3. Post-Deployment Configuration

After deployment, the Logic App workflow will need to be configured with API connections:

```bash
# The deployment creates the base Logic App
# API connections will be automatically configured by the deployment scripts
# Check the Logic App in Azure Portal to verify connections
```

## Validation

### Verify Deployment

```bash
# Check resource group resources
az resource list --resource-group $RESOURCE_GROUP --output table

# Test storage account
az storage account show --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP

# Test Key Vault
az keyvault show --name $KEY_VAULT_NAME --resource-group $RESOURCE_GROUP

# Test Document Intelligence
az cognitiveservices account show --name your-doc-intelligence-name --resource-group $RESOURCE_GROUP
```

### Test Document Processing

```bash
# Upload a test document
echo "Sample Invoice - Test Document" > test-invoice.txt
az storage blob upload \
    --account-name $STORAGE_ACCOUNT \
    --container-name input-documents \
    --file test-invoice.txt \
    --name test-invoice.txt

# Check Logic App execution
az logic workflow show --name your-logic-app-name --resource-group $RESOURCE_GROUP
```

## Monitoring and Troubleshooting

### Check Logic App Runs

```bash
# View Logic App run history
az logic workflow list-runs \
    --resource-group $RESOURCE_GROUP \
    --name your-logic-app-name
```

### View Service Bus Messages

```bash
# Check Service Bus queue
az servicebus queue show \
    --resource-group $RESOURCE_GROUP \
    --namespace-name your-servicebus-namespace \
    --name processed-docs-queue
```

### Monitor Document Intelligence

```bash
# Check Document Intelligence metrics
az monitor metrics list \
    --resource /subscriptions/your-subscription/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/your-doc-intelligence-name \
    --metric TotalCalls
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

## Cost Optimization

### Estimated Monthly Costs

- **Document Intelligence S0**: ~$1.50 per 1,000 pages (500 pages free monthly)
- **Logic Apps**: ~$0.000025 per action execution
- **Storage Account**: ~$0.045 per GB stored
- **Key Vault**: ~$0.03 per 10,000 operations
- **Service Bus Standard**: ~$0.05 per million operations

### Cost Reduction Tips

1. Use Document Intelligence free tier for development/testing
2. Implement Logic App consumption model for variable workloads
3. Use cool storage tier for archived documents
4. Set up budget alerts for cost monitoring

## Security Best Practices

### Implemented Security Features

- **Managed Identity**: Eliminates credential management
- **Key Vault**: Centralized secret management
- **RBAC**: Role-based access control
- **Private Endpoints**: Network isolation (optional)
- **Encryption**: Data encrypted at rest and in transit

### Additional Security Recommendations

1. Enable Azure Security Center recommendations
2. Implement Azure Policy for compliance
3. Use Azure Monitor for security event monitoring
4. Regular security assessments and updates

## Troubleshooting

### Common Issues

1. **Logic App Not Triggering**
   - Check blob container permissions
   - Verify API connection authentication
   - Review Logic App trigger configuration

2. **Document Intelligence Errors**
   - Verify API key and endpoint configuration
   - Check document format compatibility
   - Review service quota limits

3. **Key Vault Access Issues**
   - Verify managed identity configuration
   - Check Key Vault access policies
   - Review RBAC permissions

### Debug Commands

```bash
# Check Logic App connections
az logic workflow show \
    --name your-logic-app-name \
    --resource-group $RESOURCE_GROUP \
    --query "parameters"

# View Key Vault access policies
az keyvault show \
    --name $KEY_VAULT_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "properties.accessPolicies"
```

## Customization

### Extending the Solution

1. **Add Custom Document Models**
   - Train custom models in Document Intelligence Studio
   - Update Logic App workflow to use custom models

2. **Integrate with Power Platform**
   - Connect to Power Automate for advanced workflows
   - Use Power BI for document processing analytics

3. **Add Notification Systems**
   - Integrate with Teams or Slack
   - Email notifications for processing status

### Configuration Files

- **Bicep**: Edit `bicep/main.bicep` and `bicep/parameters.json`
- **Terraform**: Modify `terraform/variables.tf` and `terraform/terraform.tfvars`
- **Scripts**: Update environment variables in `scripts/deploy.sh`

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Azure service documentation
3. Verify CLI tool versions and authentication
4. Review Azure resource provider status

## Additional Resources

- [Azure AI Document Intelligence Documentation](https://docs.microsoft.com/en-us/azure/ai-services/document-intelligence/)
- [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Architecture Center](https://docs.microsoft.com/en-us/azure/architecture/)