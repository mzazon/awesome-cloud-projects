# Infrastructure as Code for Inclusive AI Chatbots with Accessibility Features

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Inclusive AI Chatbots with Accessibility Features".

## Overview

This solution demonstrates how to create an inclusive customer service chatbot that combines Azure Immersive Reader with Azure Bot Framework to provide accessible text experiences for users with diverse reading abilities, learning differences, and language barriers. The infrastructure includes cognitive services, web hosting, secure configuration management, and comprehensive monitoring.

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts with comprehensive error handling

## Architecture Components

- **Azure Immersive Reader**: Cognitive service providing inclusive reading capabilities
- **Azure Bot Framework**: Bot registration and multi-channel communication
- **Azure Language Understanding (LUIS)**: Natural language processing and intent recognition
- **Azure App Service**: Managed hosting platform for the bot application
- **Azure Key Vault**: Secure storage for configuration secrets and API keys
- **Azure Storage Account**: Bot state management and conversation persistence
- **Application Insights**: Comprehensive monitoring and telemetry

## Prerequisites

- Azure subscription with appropriate permissions for:
  - Cognitive Services (Immersive Reader, LUIS)
  - App Service and App Service Plans
  - Key Vault and secret management
  - Storage accounts and blob containers
  - Bot Framework registration
  - Application Insights and monitoring
- Azure CLI v2.50.0 or later installed and configured
- Node.js 18.x or later for Bot Framework development
- Appropriate Azure RBAC permissions for resource creation and management
- Basic understanding of conversational AI and accessibility principles

## Estimated Costs

- **Development/Testing**: $15-30 per month
- **Production**: $50-150 per month (varies with usage)
- **Key cost factors**: Cognitive Services usage, App Service tier, storage transactions

> **Note**: Azure Immersive Reader is available in multiple regions but may have specific regional limitations. Verify service availability in your target deployment region before proceeding.

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to the bicep directory
cd bicep/

# Review and customize parameters
cp parameters.json.example parameters.json
# Edit parameters.json with your specific values

# Deploy the infrastructure
az deployment group create \
    --resource-group your-resource-group \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment group show \
    --resource-group your-resource-group \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export RESOURCE_GROUP="rg-accessible-bot-demo"
export LOCATION="eastus"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az resource list --resource-group $RESOURCE_GROUP --output table
```

## Configuration

### Environment Variables

The following environment variables are required for deployment:

```bash
# Core Azure configuration
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export RESOURCE_GROUP="rg-accessible-bot-demo"
export LOCATION="eastus"

# Resource naming (optional - will be generated if not provided)
export RANDOM_SUFFIX=$(openssl rand -hex 3)
export BOT_NAME="accessible-customer-bot"
export IMMERSIVE_READER_NAME="immersive-reader-${RANDOM_SUFFIX}"
export LUIS_APP_NAME="customer-service-luis-${RANDOM_SUFFIX}"
export KEY_VAULT_NAME="kv-bot-${RANDOM_SUFFIX}"
export STORAGE_ACCOUNT_NAME="stbot${RANDOM_SUFFIX}"
export APP_SERVICE_NAME="app-accessible-bot-${RANDOM_SUFFIX}"
```

### Customization Options

#### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "resourcePrefix": {
      "value": "accessible-bot"
    },
    "appServicePlanSku": {
      "value": "B1"
    },
    "immersiveReaderSku": {
      "value": "S0"
    },
    "enableApplicationInsights": {
      "value": true
    }
  }
}
```

#### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
# Core configuration
location = "East US"
resource_group_name = "rg-accessible-bot-demo"
resource_prefix = "accessible-bot"

# Service configuration
app_service_plan_sku = "B1"
immersive_reader_sku = "S0"
luis_sku = "S0"
storage_account_tier = "Standard"
storage_account_replication = "LRS"

# Feature flags
enable_application_insights = true
enable_key_vault_rbac = false

# Tags
tags = {
  Environment = "Development"
  Purpose = "Accessibility Demo"
  Compliance = "Accessibility"
}
```

## Post-Deployment Steps

1. **Bot Application Deployment**:
   ```bash
   # The infrastructure creates the hosting environment
   # Deploy your bot application code to the App Service
   
   # Example using ZIP deployment
   az webapp deployment source config-zip \
       --name $APP_SERVICE_NAME \
       --resource-group $RESOURCE_GROUP \
       --src bot-application.zip
   ```

2. **LUIS Model Training**:
   ```bash
   # Configure and train your LUIS model
   # Use the authoring key and endpoint from Key Vault
   
   # Example: Import and train LUIS model
   az cognitiveservices account keys list \
       --name $LUIS_APP_NAME \
       --resource-group $RESOURCE_GROUP
   ```

3. **Bot Channel Configuration**:
   ```bash
   # Configure additional channels (Teams, Slack, etc.)
   az bot webchat show \
       --name $BOT_NAME \
       --resource-group $RESOURCE_GROUP
   ```

## Validation & Testing

### Infrastructure Validation

```bash
# Verify all resources are created
az resource list \
    --resource-group $RESOURCE_GROUP \
    --output table

# Test Immersive Reader service
az cognitiveservices account show \
    --name $IMMERSIVE_READER_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "properties.provisioningState"

# Verify Key Vault access
az keyvault secret list \
    --vault-name $KEY_VAULT_NAME \
    --query "[].name"

# Test App Service availability
curl -I https://$APP_SERVICE_NAME.azurewebsites.net/api/messages
```

### Bot Framework Testing

```bash
# Test bot endpoint
az bot show \
    --name $BOT_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "properties.endpoint"

# Verify bot registration
az bot webchat show \
    --name $BOT_NAME \
    --resource-group $RESOURCE_GROUP
```

### Accessibility Testing

```bash
# Test Immersive Reader API endpoint
IMMERSIVE_READER_ENDPOINT=$(az cognitiveservices account show \
    --name $IMMERSIVE_READER_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "properties.endpoint" \
    --output tsv)

echo "Immersive Reader Endpoint: $IMMERSIVE_READER_ENDPOINT"

# Verify LUIS authoring endpoint
LUIS_ENDPOINT=$(az cognitiveservices account show \
    --name $LUIS_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "properties.endpoint" \
    --output tsv)

echo "LUIS Authoring Endpoint: $LUIS_ENDPOINT"
```

## Monitoring & Troubleshooting

### Application Insights Queries

```bash
# View bot conversation analytics
az monitor app-insights query \
    --app $APP_SERVICE_NAME \
    --analytics-query "requests | where timestamp > ago(1h) | summarize count() by bin(timestamp, 5m)"

# Monitor accessibility feature usage
az monitor app-insights query \
    --app $APP_SERVICE_NAME \
    --analytics-query "customEvents | where name == 'ImmersiveReaderUsage' | summarize count() by bin(timestamp, 1h)"
```

### Common Issues

1. **Key Vault Access Issues**:
   ```bash
   # Verify managed identity permissions
   az webapp identity show \
       --name $APP_SERVICE_NAME \
       --resource-group $RESOURCE_GROUP
   
   # Check Key Vault access policies
   az keyvault show \
       --name $KEY_VAULT_NAME \
       --resource-group $RESOURCE_GROUP \
       --query "properties.accessPolicies"
   ```

2. **Cognitive Services Quota**:
   ```bash
   # Check Immersive Reader usage
   az cognitiveservices account show \
       --name $IMMERSIVE_READER_NAME \
       --resource-group $RESOURCE_GROUP \
       --query "properties.quotaUsage"
   ```

3. **Bot Framework Connectivity**:
   ```bash
   # Test bot endpoint connectivity
   curl -X POST https://$APP_SERVICE_NAME.azurewebsites.net/api/messages \
       -H "Content-Type: application/json" \
       -d '{"type": "message", "text": "test"}'
   ```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name $RESOURCE_GROUP \
    --yes \
    --no-wait

# Verify deletion
az group exists --name $RESOURCE_GROUP
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources are deleted
az resource list \
    --resource-group $RESOURCE_GROUP \
    --output table
```

### Manual Cleanup Verification

```bash
# Check for any remaining resources
az resource list \
    --resource-group $RESOURCE_GROUP \
    --output table

# Remove any orphaned resources
az resource delete \
    --ids $(az resource list --resource-group $RESOURCE_GROUP --query "[].id" -o tsv)

# Final resource group cleanup
az group delete \
    --name $RESOURCE_GROUP \
    --yes \
    --no-wait
```

## Security Considerations

### Key Vault Best Practices

- All sensitive configuration stored in Key Vault
- Managed identity used for secure access
- Secret rotation should be implemented for production
- Access policies follow principle of least privilege

### Network Security

- App Service configured with HTTPS only
- Cognitive Services endpoints use secure connections
- Bot Framework channels use encrypted communication
- Storage account configured for secure transfer

### Compliance & Accessibility

- Solution follows WCAG 2.1 AA accessibility guidelines
- Immersive Reader provides inclusive reading experiences
- Bot Framework supports screen reader compatibility
- Comprehensive audit logging enabled

## Cost Optimization

### Resource Sizing

- App Service Plan: Start with B1, scale based on usage
- Cognitive Services: S0 tier for development, scale for production
- Storage: Standard tier with LRS replication for development

### Monitoring Costs

```bash
# Monitor monthly spending
az consumption usage list \
    --start-date $(date -d "1 month ago" '+%Y-%m-%d') \
    --end-date $(date '+%Y-%m-%d') \
    --resource-group $RESOURCE_GROUP
```

## Support & Documentation

### Official Documentation

- [Azure Immersive Reader Documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/immersive-reader/)
- [Azure Bot Framework Documentation](https://docs.microsoft.com/en-us/azure/bot-service/)
- [Azure LUIS Documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/luis/)
- [Azure App Service Documentation](https://docs.microsoft.com/en-us/azure/app-service/)

### Accessibility Resources

- [Microsoft Inclusive Design Guidelines](https://docs.microsoft.com/en-us/azure/architecture/guide/design-principles/inclusive-design)
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [Azure Accessibility Documentation](https://docs.microsoft.com/en-us/azure/accessibility/)

For issues with this infrastructure code, refer to the original recipe documentation or the Azure provider's documentation.