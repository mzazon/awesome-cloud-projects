# Infrastructure as Code for AI-Powered Email Marketing Campaigns with Azure OpenAI and Logic Apps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI-Powered Email Marketing Campaigns with Azure OpenAI and Logic Apps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.50+)
- Active Azure subscription with Contributor access
- Azure OpenAI access approval (requires request form submission)
- Basic understanding of AI prompt engineering concepts
- Terraform installed (version 1.0+ for Terraform deployment)

## Architecture Overview

This solution deploys:
- Azure OpenAI Service with GPT-4o model deployment
- Azure Communication Services with Email Services
- Azure Function App (Logic Apps Standard runtime)
- Storage Account for workflow state management
- Managed domain configuration for email delivery

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Set deployment parameters
export RESOURCE_GROUP="rg-email-marketing-$(openssl rand -hex 3)"
export LOCATION="eastus"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file bicep/main.bicep \
    --parameters location=${LOCATION}
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review deployment plan
terraform plan \
    -var="resource_group_name=rg-email-marketing-$(openssl rand -hex 3)" \
    -var="location=eastus"

# Deploy infrastructure
terraform apply \
    -var="resource_group_name=rg-email-marketing-$(openssl rand -hex 3)" \
    -var="location=eastus"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration parameters
```

## Configuration Parameters

### Required Parameters

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `location` | Azure region for deployment | `eastus` | `westus2`, `northeurope` |
| `resource_group_name` | Name for the resource group | Auto-generated | `rg-email-marketing-dev` |

### Optional Parameters

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `openai_model_version` | GPT-4o model version | `2024-11-20` | `2024-11-20` |
| `openai_capacity` | Model deployment capacity | `10` | `20` |
| `storage_sku` | Storage account SKU | `Standard_LRS` | `Standard_GRS` |
| `tags` | Resource tags | `{"purpose": "recipe", "environment": "demo"}` | Custom tags object |

## Post-Deployment Configuration

### 1. Configure Email Domain

After deployment, configure the email domain for Communication Services:

```bash
# Get deployment outputs
COMMUNICATION_SERVICE_NAME=$(az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query properties.outputs.communicationServiceName.value \
    --output tsv)

EMAIL_SERVICE_NAME=$(az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query properties.outputs.emailServiceName.value \
    --output tsv)

# Add managed domain
az communication email domain create \
    --domain-name "AzureManagedDomain" \
    --resource-group ${RESOURCE_GROUP} \
    --email-service-name ${EMAIL_SERVICE_NAME} \
    --domain-management "AzureManaged"

# Connect domain to Communication Service
az communication email domain connect \
    --domain-name "AzureManagedDomain" \
    --resource-group ${RESOURCE_GROUP} \
    --email-service-name ${EMAIL_SERVICE_NAME} \
    --communication-service-name ${COMMUNICATION_SERVICE_NAME}
```

### 2. Deploy Marketing Workflow

```bash
# Get Function App name
FUNCTION_APP_NAME=$(az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query properties.outputs.functionAppName.value \
    --output tsv)

# Create workflow package
mkdir -p workflows
cp ../workflow-definition.json workflows/EmailMarketingWorkflow.json
zip -r workflow-package.zip workflows/

# Deploy workflow
az functionapp deployment source config-zip \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --src workflow-package.zip
```

## Validation

### Verify Deployment

```bash
# Check Azure OpenAI deployment
az cognitiveservices account deployment list \
    --name $(az deployment group show \
        --resource-group ${RESOURCE_GROUP} \
        --name main \
        --query properties.outputs.openaiServiceName.value \
        --output tsv) \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# Verify Communication Services
az communication list \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# Check Function App status
az functionapp list \
    --resource-group ${RESOURCE_GROUP} \
    --output table
```

### Test AI Content Generation

```bash
# Get OpenAI endpoint and key
OPENAI_ENDPOINT=$(az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query properties.outputs.openaiEndpoint.value \
    --output tsv)

OPENAI_KEY=$(az cognitiveservices account keys list \
    --name $(az deployment group show \
        --resource-group ${RESOURCE_GROUP} \
        --name main \
        --query properties.outputs.openaiServiceName.value \
        --output tsv) \
    --resource-group ${RESOURCE_GROUP} \
    --query key1 --output tsv)

# Test content generation
curl -X POST "${OPENAI_ENDPOINT}openai/deployments/gpt-4o-marketing/chat/completions?api-version=2024-08-01-preview" \
    -H "Content-Type: application/json" \
    -H "api-key: ${OPENAI_KEY}" \
    -d '{
      "messages": [
        {
          "role": "user",
          "content": "Generate a professional email subject line for a software product launch"
        }
      ],
      "max_tokens": 100,
      "temperature": 0.7
    }'
```

## Cleanup

### Using Bicep

```bash
# Delete resource group and all resources
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait

echo "✅ Resource group deletion initiated"
echo "Note: Deletion may take several minutes to complete"
```

### Using Terraform

```bash
cd terraform/
terraform destroy \
    -var="resource_group_name=${RESOURCE_GROUP}" \
    -var="location=${LOCATION}"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

## Customization

### Bicep Customization

Edit `bicep/main.bicep` to modify:
- Resource naming conventions
- SKU sizes and performance tiers
- Network security configurations
- Monitoring and logging settings

### Terraform Customization

Edit `terraform/variables.tf` to modify:
- Default parameter values
- Variable validation rules
- Description and help text

Edit `terraform/main.tf` to modify:
- Resource configurations
- Dependencies between resources
- Provider settings

### Workflow Customization

Modify the workflow definition to:
- Change AI prompt templates
- Add customer segmentation logic
- Implement A/B testing capabilities
- Add custom email templates
- Configure delivery scheduling

## Cost Considerations

### Estimated Monthly Costs (Development)

- Azure OpenAI Service (GPT-4o): $15-25
- Function App (Consumption): $2-5
- Communication Services: $0.50-2
- Storage Account: $1-3
- **Total: ~$20-35/month**

### Production Scaling

For production workloads, consider:
- Upgrading to Function App Premium plan for better performance
- Implementing Azure OpenAI rate limiting and quota management
- Using Azure Monitor for comprehensive observability
- Configuring auto-scaling policies based on email volume

## Security Best practices

### Implemented Security Features

- Managed Identity authentication between services
- Key Vault integration for sensitive configuration
- Network security groups for traffic control
- Data encryption at rest and in transit
- Role-based access control (RBAC)

### Additional Security Recommendations

1. **Network Isolation**: Configure private endpoints for services
2. **Content Filtering**: Enable Azure OpenAI content filters
3. **Monitoring**: Set up Azure Sentinel for security monitoring
4. **Compliance**: Review GDPR/CAN-SPAM compliance requirements
5. **Access Control**: Implement conditional access policies

## Troubleshooting

### Common Issues

1. **Azure OpenAI Access Denied**
   ```bash
   # Check if Azure OpenAI approval is pending
   az cognitiveservices account show \
       --name ${OPENAI_SERVICE_NAME} \
       --resource-group ${RESOURCE_GROUP}
   ```

2. **Email Delivery Failures**
   ```bash
   # Check email domain status
   az communication email domain show \
       --domain-name "AzureManagedDomain" \
       --resource-group ${RESOURCE_GROUP} \
       --email-service-name ${EMAIL_SERVICE_NAME}
   ```

3. **Function App Deployment Issues**
   ```bash
   # Check deployment logs
   az functionapp log deployment list \
       --name ${FUNCTION_APP_NAME} \
       --resource-group ${RESOURCE_GROUP}
   ```

## Monitoring and Observability

### Application Insights Integration

The deployment includes Application Insights for monitoring:
- AI model usage and performance metrics
- Email delivery success rates
- Function execution statistics
- Error tracking and debugging

### Key Metrics to Monitor

- OpenAI token consumption rates
- Email bounce and delivery rates  
- Function App execution duration
- Storage account transaction volume
- Cost optimization opportunities

## Support

### Azure Resources

- [Azure OpenAI Service Documentation](https://docs.microsoft.com/azure/cognitive-services/openai/)
- [Azure Communication Services Documentation](https://docs.microsoft.com/azure/communication-services/)
- [Azure Functions Documentation](https://docs.microsoft.com/azure/azure-functions/)
- [Bicep Documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)

### Community Support

- [Azure OpenAI GitHub Repository](https://github.com/Azure/azure-openai-service)
- [Azure Communication Services Samples](https://github.com/Azure/communication-services-samples)
- [Azure Functions Community](https://github.com/Azure/azure-functions)

For issues with this infrastructure code, refer to the original recipe documentation or submit issues to the appropriate Azure service repository.