# Infrastructure as Code for Code Tutorial Generator with OpenAI and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Code Tutorial Generator with OpenAI and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login` completed)
- Azure subscription with appropriate permissions for:
  - Creating resource groups
  - Creating storage accounts and containers
  - Creating Azure OpenAI services and model deployments
  - Creating Azure Functions and app service plans
  - Managing IAM roles and permissions
- Azure OpenAI service access (requires special approval)
- For Terraform: Terraform CLI installed (version 1.0+)
- For Bicep: Bicep CLI installed (included with Azure CLI 2.20.0+)

> **Note**: Estimated deployment cost: $15-25 per month for moderate usage (includes OpenAI token costs)

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters uniqueSuffix=$(openssl rand -hex 3)

# Monitor deployment status
az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="location=eastus" \
    -var="unique_suffix=$(openssl rand -hex 3)"

# Apply infrastructure
terraform apply \
    -var="location=eastus" \
    -var="unique_suffix=$(openssl rand -hex 3)"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export LOCATION="eastus"
export RESOURCE_GROUP_PREFIX="rg-tutorial-gen"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment results
echo "Deployment completed. Check Azure portal for resources."
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | Yes |
| `uniqueSuffix` | Suffix for globally unique names | Generated | No |
| `storageAccountSku` | Storage account SKU | `Standard_LRS` | No |
| `openAiSku` | Azure OpenAI service SKU | `S0` | No |
| `functionAppSku` | Function app hosting plan | `Y1` (Consumption) | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | Yes |
| `unique_suffix` | Suffix for globally unique names | Random | No |
| `resource_group_name` | Name of resource group | Auto-generated | No |
| `storage_sku` | Storage account replication | `Standard_LRS` | No |
| `openai_sku` | OpenAI service pricing tier | `S0` | No |
| `tags` | Resource tags | `{}` | No |

### Bash Script Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `LOCATION` | Azure region | Yes |
| `RESOURCE_GROUP_PREFIX` | Resource group name prefix | No |
| `STORAGE_SKU` | Storage account SKU | No |
| `OPENAI_SKU` | OpenAI service SKU | No |

## Post-Deployment Configuration

After successful deployment, additional manual steps are required:

### 1. Deploy Function Code

```bash
# Get function app name from deployment outputs
FUNCTION_APP_NAME=$(az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query "properties.outputs.functionAppName.value" -o tsv)

# Create function project locally
mkdir tutorial-function && cd tutorial-function

# Copy function code from recipe and deploy
# (Refer to the original recipe for complete function code)
```

### 2. Configure CORS

```bash
# Enable CORS for web applications
az functionapp cors add \
    --name $FUNCTION_APP_NAME \
    --resource-group myResourceGroup \
    --allowed-origins "*"
```

### 3. Test the Deployment

```bash
# Get function app URL
FUNCTION_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net"

# Test tutorial generation
curl -X POST "${FUNCTION_URL}/api/generate" \
     -H "Content-Type: application/json" \
     -d '{
         "topic": "Python Functions",
         "difficulty": "beginner",
         "language": "python"
     }'
```

## Outputs

Each implementation provides the following outputs:

- **Resource Group Name**: Name of the created resource group
- **Storage Account Name**: Name of the storage account for tutorial content
- **Storage Account Key**: Access key for storage operations
- **Function App Name**: Name of the Azure Functions app
- **Function App URL**: HTTPS endpoint for the function app
- **OpenAI Endpoint**: Azure OpenAI service endpoint URL
- **OpenAI Key**: Access key for OpenAI service

## Monitoring and Management

### View Deployment Status

```bash
# Check resource group contents
az resource list \
    --resource-group myResourceGroup \
    --output table

# Monitor function app logs
az functionapp log tail \
    --name $FUNCTION_APP_NAME \
    --resource-group myResourceGroup
```

### Cost Monitoring

```bash
# Enable cost analysis for the resource group
az consumption budget create \
    --budget-name tutorial-generator-budget \
    --amount 50 \
    --resource-group myResourceGroup \
    --time-grain Monthly
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name myResourceGroup \
    --yes \
    --no-wait

# Verify deletion
az group exists --name myResourceGroup
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="location=eastus" \
    -var="unique_suffix=your-suffix"

# Clean up Terraform state
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resources are deleted
az group exists --name $RESOURCE_GROUP_NAME
```

## Troubleshooting

### Common Issues

1. **Azure OpenAI Access Denied**:
   - Ensure your subscription has access to Azure OpenAI services
   - Request access through the Azure portal if needed

2. **Function Deployment Fails**:
   - Check that all required application settings are configured
   - Verify the function runtime version is supported

3. **Storage Access Errors**:
   - Confirm storage account keys are correctly configured
   - Check container permissions and access levels

4. **Model Deployment Timeout**:
   - OpenAI model deployments can take several minutes
   - Use `az cognitiveservices account deployment show` to check status

### Debug Commands

```bash
# Check deployment logs
az deployment group show \
    --resource-group myResourceGroup \
    --name main

# View function app configuration
az functionapp config show \
    --name $FUNCTION_APP_NAME \
    --resource-group myResourceGroup

# Test storage connectivity
az storage account show \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group myResourceGroup
```

## Security Considerations

- **Secrets Management**: OpenAI keys and storage keys are stored in function app settings
- **CORS Configuration**: Adjust CORS settings for production use
- **Access Control**: Configure appropriate RBAC roles for service principals
- **Network Security**: Consider using private endpoints for production deployments
- **Key Rotation**: Implement regular rotation of storage and OpenAI access keys

## Customization

### Scaling Configuration

To handle higher loads, modify the function app configuration:

```bash
# Upgrade to Premium plan for better performance
az functionapp plan update \
    --name $FUNCTION_APP_NAME \
    --resource-group myResourceGroup \
    --sku P1V2
```

### Storage Optimization

For better performance with large tutorial libraries:

```bash
# Enable storage analytics
az storage logging update \
    --account-name $STORAGE_ACCOUNT_NAME \
    --services b \
    --log-types rwd \
    --retention-days 7
```

### Regional Deployment

To deploy in multiple regions, customize the location parameter and consider:

- Data residency requirements for OpenAI services
- Cross-region replication for storage accounts
- Traffic routing with Azure Front Door

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../code-tutorial-generator-openai-functions.md)
2. Check Azure service health and status pages
3. Consult Azure documentation for specific services:
   - [Azure Functions documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
   - [Azure OpenAI documentation](https://docs.microsoft.com/en-us/azure/ai-services/openai/)
   - [Azure Blob Storage documentation](https://docs.microsoft.com/en-us/azure/storage/blobs/)

## Version History

- **v1.0**: Initial infrastructure implementation
- **v1.1**: Added Terraform support and enhanced monitoring

---

*Generated for recipe: Code Tutorial Generator with OpenAI and Functions*  
*Last updated: 2025-07-12*