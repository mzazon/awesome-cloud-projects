# AI-Powered Email Marketing Infrastructure - Bicep Template

This directory contains Azure Bicep templates for deploying the complete infrastructure needed for the "AI-Powered Email Marketing Campaigns with Azure OpenAI and Logic Apps" recipe.

## Architecture Overview

The infrastructure includes:

- **Azure OpenAI Service** with GPT-4o model deployment for content generation
- **Azure Communication Services** for email delivery
- **Logic Apps Standard** (Function App) for workflow orchestration
- **Storage Account** for Logic Apps runtime state
- **Key Vault** for secure secret management
- **Application Insights** and Log Analytics for monitoring
- **Email Communication Services** with Azure Managed Domain

## Files Structure

```
bicep/
├── main.bicep                    # Main Bicep template
├── modules/
│   └── emailService.bicep        # Email services module
├── parameters.json               # Development environment parameters
├── parameters.prod.json          # Production environment parameters
├── bicepconfig.json             # Bicep configuration
└── README.md                    # This file
```

## Prerequisites

1. **Azure CLI** installed and configured (version 2.50+)
2. **Bicep CLI** installed (latest version)
3. **Azure subscription** with appropriate permissions:
   - Contributor role on the target resource group
   - User Access Administrator role (for role assignments)
   - Azure OpenAI service quota approved
4. **Resource quotas** verified for:
   - Azure OpenAI Service (requires approval)
   - Communication Services
   - Logic Apps Standard

## Quick Start

### 1. Clone and Navigate

```bash
# Navigate to the bicep directory
cd azure/ai-email-marketing-openai-logic-apps/code/bicep/
```

### 2. Login to Azure

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "your-subscription-id"
```

### 3. Create Resource Group

```bash
# Create resource group
az group create \
    --name "rg-email-marketing-dev" \
    --location "eastus" \
    --tags Environment=dev Project="AI Email Marketing"
```

### 4. Review and Customize Parameters

Edit `parameters.json` to customize the deployment:

```json
{
  "parameters": {
    "projectName": {
      "value": "yourproject"
    },
    "uniqueSuffix": {
      "value": "001"
    },
    "location": {
      "value": "eastus"
    },
    "environment": {
      "value": "dev"
    }
  }
}
```

### 5. Validate Template

```bash
# Validate the template
az deployment group validate \
    --resource-group "rg-email-marketing-dev" \
    --template-file main.bicep \
    --parameters @parameters.json
```

### 6. Deploy Infrastructure

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-email-marketing-dev" \
    --template-file main.bicep \
    --parameters @parameters.json \
    --mode Incremental
```

### 7. Verify Deployment

```bash
# Check deployment status
az deployment group show \
    --resource-group "rg-email-marketing-dev" \
    --name main \
    --output table

# List created resources
az resource list \
    --resource-group "rg-email-marketing-dev" \
    --output table
```

## Parameter Reference

### Required Parameters

| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `location` | string | Azure region for resources | `eastus` |
| `environment` | string | Environment (dev/staging/prod) | `dev` |
| `projectName` | string | Project name for resource naming | `emailmarketing` |

### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `uniqueSuffix` | string | `uniqueString(resourceGroup().id)` | Unique suffix for resource names |
| `openAiSku` | string | `S0` | Azure OpenAI service tier |
| `gptModelCapacity` | int | `10` | GPT-4o model capacity (TPM) |
| `emailDomainType` | string | `AzureManaged` | Email domain type |
| `customEmailDomain` | string | `""` | Custom email domain name |

## Environment-Specific Deployments

### Development Environment

```bash
az deployment group create \
    --resource-group "rg-email-marketing-dev" \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Production Environment

```bash
az deployment group create \
    --resource-group "rg-email-marketing-prod" \
    --template-file main.bicep \
    --parameters @parameters.prod.json
```

## Post-Deployment Configuration

### 1. Verify Azure OpenAI Model Deployment

```bash
# Check OpenAI deployments
az cognitiveservices account deployment list \
    --name "emailmarketing-openai-{suffix}" \
    --resource-group "rg-email-marketing-dev" \
    --output table
```

### 2. Configure Email Domain (Custom Domain Only)

If using a custom email domain, add the DNS verification records provided in the deployment outputs:

```bash
# Get DNS verification records
az deployment group show \
    --resource-group "rg-email-marketing-dev" \
    --name main \
    --query "properties.outputs.dnsVerificationRecords.value"
```

### 3. Deploy Logic App Workflows

The Logic Apps Standard instance requires workflow definitions to be deployed separately:

```bash
# Create workflows directory structure
mkdir -p workflows/EmailMarketingWorkflow

# Deploy workflow definitions (example)
func azure functionapp publish emailmarketing-logicapp-{suffix} --force
```

### 4. Test the System

```bash
# Test OpenAI endpoint
curl -X POST "https://emailmarketing-openai-{suffix}.openai.azure.com/openai/deployments/gpt-4o-marketing/chat/completions?api-version=2024-08-01-preview" \
    -H "Content-Type: application/json" \
    -H "api-key: YOUR_API_KEY" \
    -d '{"messages":[{"role":"user","content":"Generate a marketing email subject"}],"max_tokens":100}'
```

## Monitoring and Troubleshooting

### Application Insights

Monitor your deployment through Application Insights:

```bash
# Get Application Insights connection string
az monitor app-insights component show \
    --app "emailmarketing-insights-{suffix}" \
    --resource-group "rg-email-marketing-dev" \
    --query "connectionString"
```

### Common Issues

1. **Azure OpenAI Access Denied**
   - Ensure your subscription has Azure OpenAI access approved
   - Check role assignments (Cognitive Services OpenAI User)

2. **Email Domain Verification Failed**
   - Verify DNS records are correctly configured
   - Wait for DNS propagation (up to 48 hours)

3. **Logic Apps Runtime Issues**
   - Check storage account connectivity
   - Verify Key Vault access permissions
   - Review Application Insights logs

### Diagnostic Commands

```bash
# Check resource health
az resource list \
    --resource-group "rg-email-marketing-dev" \
    --query "[].{Name:name,Type:type,Location:location,Status:properties.provisioningState}" \
    --output table

# View deployment logs
az deployment group show \
    --resource-group "rg-email-marketing-dev" \
    --name main \
    --query "properties.error"
```

## Cost Optimization

### Development Environment

- Use minimal OpenAI model capacity (10 TPM)
- Enable auto-shutdown for non-production resources
- Monitor usage through Cost Management

### Production Environment

- Scale OpenAI capacity based on usage patterns
- Implement budget alerts
- Use reserved instances for predictable workloads

```bash
# Set up budget alert
az consumption budget create \
    --resource-group "rg-email-marketing-prod" \
    --budget-name "email-marketing-monthly" \
    --amount 500 \
    --time-grain Monthly \
    --time-period start-date=2025-01-01 end-date=2025-12-31
```

## Security Considerations

### Key Vault Integration

All sensitive information is stored in Azure Key Vault:
- OpenAI API keys
- Communication Services connection strings
- Application secrets

### Network Security

- Storage accounts disable public blob access
- HTTPS-only traffic enforced
- Managed identity authentication where possible

### Role-Based Access Control

The template configures minimal required permissions:
- Logic Apps gets Cognitive Services OpenAI User role
- Logic Apps gets Communication Services Contributor role
- Key Vault access via managed identity

## Cleanup

### Delete Resource Group

```bash
# Delete entire resource group (WARNING: This deletes all resources)
az group delete \
    --name "rg-email-marketing-dev" \
    --yes \
    --no-wait
```

### Selective Resource Deletion

```bash
# Delete specific resources
az cognitiveservices account delete \
    --name "emailmarketing-openai-{suffix}" \
    --resource-group "rg-email-marketing-dev"

az communication delete \
    --name "emailmarketing-comms-{suffix}" \
    --resource-group "rg-email-marketing-dev"
```

## Advanced Configuration

### Custom Email Domain Setup

For production deployments with custom domains:

1. Set `emailDomainType` to `CustomDomain`
2. Set `customEmailDomain` to your domain
3. Deploy the template
4. Configure DNS records from deployment outputs
5. Wait for domain verification

### Scaling Configuration

Adjust resources based on expected load:

```json
{
  "gptModelCapacity": {
    "value": 100
  },
  "functionAppPlan": {
    "sku": "WS2",
    "capacity": 2
  }
}
```

### Multi-Region Deployment

Deploy to multiple regions for high availability:

```bash
# Primary region
az deployment group create \
    --resource-group "rg-email-marketing-east" \
    --template-file main.bicep \
    --parameters location=eastus

# Secondary region
az deployment group create \
    --resource-group "rg-email-marketing-west" \
    --template-file main.bicep \
    --parameters location=westus
```

## Support and Contributing

For issues with this infrastructure template:

1. Check the troubleshooting section above
2. Review Azure service health status
3. Consult the original recipe documentation
4. Submit issues to the repository

For Azure service-specific issues, refer to:
- [Azure OpenAI Documentation](https://learn.microsoft.com/azure/cognitive-services/openai/)
- [Azure Communication Services Documentation](https://learn.microsoft.com/azure/communication-services/)
- [Azure Logic Apps Documentation](https://learn.microsoft.com/azure/logic-apps/)

## License

This template is part of the Azure Recipes project and follows the same licensing terms.