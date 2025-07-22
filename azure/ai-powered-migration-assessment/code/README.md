# Infrastructure as Code for AI-Powered Migration Assessment and Modernization Planning

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI-Powered Migration Assessment and Modernization Planning".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM template language)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.57.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Azure Migrate
  - Azure OpenAI Service (requires approval)
  - Azure Functions
  - Azure Storage Account
  - Azure Cognitive Services
- For Terraform: Terraform v1.0+ installed
- For Bicep: Bicep CLI installed (or use Azure CLI with Bicep extension)
- Bash shell environment (Linux, macOS, or Windows WSL)
- Access to Azure OpenAI Service (requires approval)

## Quick Start

### Using Bicep
```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-migrate-ai-assessment \
    --template-file bicep/main.bicep \
    --parameters bicep/parameters.json

# Verify deployment
az deployment group show \
    --resource-group rg-migrate-ai-assessment \
    --name main \
    --query properties.provisioningState
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

# Verify deployment
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment status
az group show --name rg-migrate-ai-assessment --query properties.provisioningState
```

## Architecture Overview

This solution deploys the following Azure resources:

- **Azure Migrate Project**: Centralized hub for workload discovery and assessment
- **Azure OpenAI Service**: AI-powered analysis engine with GPT-4 model deployment
- **Azure Functions**: Serverless processing for AI assessment workflows
- **Azure Storage Account**: Secure storage for assessment data and AI insights
- **Storage Containers**: Organized data management for assessment inputs and outputs

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

- `location`: Azure region for deployment
- `storageAccountName`: Name for the storage account
- `functionAppName`: Name for the Azure Functions app
- `openAiServiceName`: Name for the Azure OpenAI service
- `migrateProjectName`: Name for the Azure Migrate project

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

- `resource_group_name`: Name for the resource group
- `location`: Azure region for deployment
- `storage_account_name`: Name for the storage account
- `function_app_name`: Name for the Azure Functions app
- `openai_service_name`: Name for the Azure OpenAI service
- `migrate_project_name`: Name for the Azure Migrate project

### Environment Variables (Bash Scripts)

The deployment script uses these environment variables:

```bash
export RESOURCE_GROUP="rg-migrate-ai-assessment"
export LOCATION="eastus"
export STORAGE_ACCOUNT="stamigrate$(openssl rand -hex 3)"
export FUNCTION_APP="func-migrate-ai-$(openssl rand -hex 3)"
export OPENAI_SERVICE="openai-migrate-$(openssl rand -hex 3)"
export MIGRATE_PROJECT="migrate-project-$(openssl rand -hex 3)"
```

## Post-Deployment Configuration

### Azure OpenAI Service Setup

1. **Apply for Azure OpenAI Access**: If not already approved, apply for access at the Azure OpenAI portal
2. **Deploy GPT-4 Model**: The infrastructure includes model deployment automation
3. **Configure API Keys**: Keys are automatically configured in Function App settings

### Function App Configuration

1. **Deploy Function Code**: Upload the AI assessment processing code
2. **Configure Application Settings**: OpenAI endpoint and keys are configured automatically
3. **Test Function Endpoint**: Verify the AI assessment processing functionality

### Storage Account Setup

1. **Create Containers**: Assessment data, AI insights, and report containers are created automatically
2. **Configure Access Policies**: Secure access controls are applied during deployment
3. **Upload Sample Data**: Use provided sample assessment data for testing

## Testing the Deployment

### Validate Resource Creation

```bash
# Check resource group
az group show --name rg-migrate-ai-assessment

# Verify Azure Migrate project
az migrate project show \
    --name $MIGRATE_PROJECT \
    --resource-group $RESOURCE_GROUP

# Check OpenAI service
az cognitiveservices account show \
    --name $OPENAI_SERVICE \
    --resource-group $RESOURCE_GROUP

# Verify Function App
az functionapp show \
    --name $FUNCTION_APP \
    --resource-group $RESOURCE_GROUP
```

### Test AI Assessment Processing

```bash
# Get Function App URL and key
FUNCTION_URL=$(az functionapp function show \
    --resource-group $RESOURCE_GROUP \
    --name $FUNCTION_APP \
    --function-name migrate-ai-assessment \
    --query invokeUrlTemplate \
    --output tsv)

FUNCTION_KEY=$(az functionapp keys list \
    --resource-group $RESOURCE_GROUP \
    --name $FUNCTION_APP \
    --query functionKeys.default \
    --output tsv)

# Test with sample data
curl -X POST "${FUNCTION_URL}&code=${FUNCTION_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
        "timestamp": "2025-07-12T10:00:00Z",
        "project": "migrate-project-demo",
        "servers": [
            {
                "name": "web-server-01",
                "os": "Windows Server 2016",
                "cpu_cores": 4,
                "memory_gb": 16,
                "applications": ["IIS", "ASP.NET"]
            }
        ]
    }'
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-migrate-ai-assessment \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

## Cost Considerations

### Estimated Monthly Costs

- **Azure Migrate Project**: Free tier available
- **Azure OpenAI Service**: $0.03 per 1K tokens (varies by model)
- **Azure Functions**: Consumption plan charges per execution
- **Azure Storage Account**: $0.018 per GB for Standard LRS
- **Total Estimated Cost**: $50-100/month for testing workloads

### Cost Optimization Tips

1. **Use Consumption Plans**: Azure Functions consumption pricing scales with usage
2. **Monitor OpenAI Usage**: Track token consumption to manage AI processing costs
3. **Optimize Storage Tiers**: Use appropriate storage tiers for different data types
4. **Clean Up Test Resources**: Remove resources after testing to avoid ongoing charges

## Troubleshooting

### Common Issues

1. **Azure OpenAI Service Access**: Ensure you have applied for and received approval for Azure OpenAI Service access

2. **Function App Deployment**: If function deployment fails, check that the storage account is properly configured and accessible

3. **Regional Availability**: Some services may not be available in all regions. Verify service availability in your target region

4. **Resource Naming Conflicts**: If resource names conflict, modify the random suffix generation or use explicit naming

### Debug Commands
```bash
# Check Azure CLI authentication
az account show

# Verify resource group permissions
az group show --name rg-migrate-ai-assessment

# Check deployment logs
az deployment group list \
    --resource-group rg-migrate-ai-assessment \
    --query "[0].properties.error"

# Review Function App logs
az functionapp logs tail \
    --name func-migrate-ai-${RANDOM_SUFFIX} \
    --resource-group rg-migrate-ai-assessment
```

## Security Considerations

### Access Controls

- **Role-Based Access Control (RBAC)**: Implemented for all resources
- **Key Management**: OpenAI keys stored securely in Function App settings
- **Network Security**: Storage accounts configured with secure access policies
- **Data Encryption**: All data encrypted at rest and in transit

### Best Practices

1. **Least Privilege**: Function App uses minimum required permissions
2. **Secure Storage**: Private containers with controlled access
3. **API Security**: Function endpoints protected with access keys
4. **Audit Logging**: Enable monitoring and logging for all resources

## Customization

### Adding Custom Analysis Logic

1. **Modify Function Code**: Update the AI assessment processing logic
2. **Add New Models**: Deploy additional OpenAI models for specialized analysis
3. **Extend Storage**: Add new containers for different data types
4. **Integrate External Systems**: Connect to existing migration tools

### Scaling Considerations

1. **Function App Scaling**: Configure auto-scaling rules for high-volume processing
2. **Storage Performance**: Use premium storage tiers for high-throughput scenarios
3. **OpenAI Rate Limits**: Implement queue-based processing for large assessments
4. **Multi-Region Deployment**: Deploy across multiple regions for global coverage

## Integration Examples

### Power BI Integration

```bash
# Configure Power BI data source
az powerbi dataset create \
    --name "Migration Assessment Insights" \
    --data-source "Azure Storage" \
    --connection-string $STORAGE_CONNECTION_STRING
```

### Logic Apps Integration

```bash
# Create Logic App for automated processing
az logic workflow create \
    --name "migration-assessment-workflow" \
    --resource-group $RESOURCE_GROUP \
    --definition @logic-app-definition.json
```

## Support

For issues with this infrastructure code, refer to:

- [Original Recipe Documentation](../ai-powered-migration-assessment.md)
- [Azure Migrate Documentation](https://docs.microsoft.com/en-us/azure/migrate/)
- [Azure OpenAI Service Documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/openai/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/)

## Contributing

To contribute improvements to this infrastructure code:

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with detailed description

## License

This infrastructure code is provided under the same license as the parent recipe repository.