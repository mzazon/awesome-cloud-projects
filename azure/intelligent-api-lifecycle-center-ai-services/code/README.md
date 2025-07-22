# Infrastructure as Code for Intelligent API Lifecycle with API Center and AI Services

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent API Lifecycle with API Center and AI Services".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.55.0 or later installed and configured
- Azure subscription with appropriate permissions to create resources:
  - API Center (Microsoft.ApiCenter)
  - Cognitive Services (Microsoft.CognitiveServices)
  - API Management (Microsoft.ApiManagement)
  - Monitor (Microsoft.Insights)
  - Logic Apps (Microsoft.Logic)
  - Storage (Microsoft.Storage)
- Basic understanding of API management concepts and REST APIs
- For Terraform: Terraform v1.0+ installed
- Estimated cost: ~$50-100/month for minimal production setup

> **Note**: Azure API Center offers both Free and Standard plans. This recipe uses the Free plan for demonstration, but production workloads should use the Standard plan for advanced features.

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to the bicep directory
cd bicep/

# Login to Azure (if not already logged in)
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Create resource group
az group create --name rg-api-lifecycle --location eastus

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-api-lifecycle \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure your deployment
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
    "resourcePrefix": {
      "value": "apilc"
    },
    "environment": {
      "value": "demo"
    },
    "deployApiManagement": {
      "value": true
    },
    "apiManagementSku": {
      "value": "Consumption"
    },
    "openAiSku": {
      "value": "S0"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize your deployment:

```hcl
# Basic Configuration
location = "East US"
resource_prefix = "apilc"
environment = "demo"

# API Management Configuration
deploy_api_management = true
api_management_sku = "Consumption"
api_management_publisher_email = "admin@contoso.com"
api_management_publisher_name = "Contoso"

# AI Services Configuration
openai_sku = "S0"
anomaly_detector_sku = "F0"

# Monitoring Configuration
log_analytics_retention_days = 30

# Tags
tags = {
  Environment = "demo"
  Project     = "api-lifecycle"
  Owner       = "platform-team"
}
```

## Post-Deployment Configuration

After deploying the infrastructure, complete these manual steps:

### 1. Configure API Center Metadata Schema

```bash
# Set variables (replace with your actual values)
RESOURCE_GROUP="rg-api-lifecycle"
API_CENTER_NAME="apic-xxxxx"

# Create custom metadata schema
az apic metadata-schema create \
    --resource-group ${RESOURCE_GROUP} \
    --service-name ${API_CENTER_NAME} \
    --metadata-schema-name "api-lifecycle" \
    --schema '{
      "type": "object",
      "properties": {
        "lifecycleStage": {
          "type": "string",
          "enum": ["design", "development", "testing", "production", "deprecated"]
        },
        "businessDomain": {
          "type": "string",
          "enum": ["finance", "hr", "operations", "customer", "analytics"]
        },
        "dataClassification": {
          "type": "string",
          "enum": ["public", "internal", "confidential", "restricted"]
        }
      }
    }'
```

### 2. Register Sample APIs

```bash
# Register a sample API
az apic api create \
    --resource-group ${RESOURCE_GROUP} \
    --service-name ${API_CENTER_NAME} \
    --api-id "customer-api" \
    --title "Customer Management API" \
    --type REST \
    --description "API for managing customer data and operations"

# Create API version
az apic api version create \
    --resource-group ${RESOURCE_GROUP} \
    --service-name ${API_CENTER_NAME} \
    --api-id "customer-api" \
    --version-id "v1" \
    --title "Version 1.0" \
    --lifecycle-stage "production"
```

### 3. Configure OpenAI Model Deployment

```bash
# Get OpenAI service name from deployment outputs
OPENAI_NAME=$(az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query 'properties.outputs.openAiServiceName.value' \
    --output tsv)

# Deploy GPT-4 model
az cognitiveservices account deployment create \
    --name ${OPENAI_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --deployment-name "gpt-4" \
    --model-name "gpt-4" \
    --model-version "0613" \
    --model-format OpenAI \
    --scale-settings-scale-type "Standard"
```

## Validation

### Verify API Center Deployment

```bash
# List API Center services
az apic service list \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# Check API Center details
az apic service show \
    --resource-group ${RESOURCE_GROUP} \
    --service-name ${API_CENTER_NAME} \
    --output json
```

### Verify AI Services

```bash
# Check OpenAI service
az cognitiveservices account show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${OPENAI_NAME} \
    --output table

# List deployed models
az cognitiveservices account deployment list \
    --resource-group ${RESOURCE_GROUP} \
    --name ${OPENAI_NAME} \
    --output table
```

### Verify Monitoring Infrastructure

```bash
# Check Application Insights
az monitor app-insights component list \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# List configured alerts
az monitor metrics alert list \
    --resource-group ${RESOURCE_GROUP} \
    --output table
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-api-lifecycle \
    --yes \
    --no-wait

# Verify deletion
az group exists --name rg-api-lifecycle
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Architecture Overview

The deployed infrastructure includes:

- **Azure API Center**: Centralized API inventory and governance
- **Azure OpenAI Service**: AI-powered documentation generation
- **Azure API Management**: Runtime API gateway (optional)
- **Azure Monitor**: Comprehensive observability and alerting
- **Application Insights**: Application performance monitoring
- **Anomaly Detector**: AI-powered anomaly detection
- **Logic Apps**: Automated workflows for documentation
- **Storage Account**: Portal assets and static content

## Security Considerations

The infrastructure implements several security best practices:

- **Managed Identity**: Used for service-to-service authentication
- **Private Endpoints**: Configured for sensitive services where applicable
- **Network Security**: Appropriate network access controls
- **RBAC**: Role-based access control for resource access
- **Key Vault**: Secure storage for sensitive configuration (if deployed)

## Cost Optimization

To optimize costs:

- Use **Free tier** of API Center for development/testing
- Select **Consumption pricing** for API Management
- Monitor AI service usage to control costs
- Use **F0 tier** for Anomaly Detector in non-production environments
- Configure appropriate retention periods for Log Analytics

## Monitoring and Alerts

The solution includes:

- **Application Insights** for application performance monitoring
- **Azure Monitor** for infrastructure metrics
- **Anomaly Detector** for AI-powered anomaly detection
- **Alert rules** for proactive issue detection
- **Log Analytics** for centralized logging

## Troubleshooting

### Common Issues

1. **API Center deployment fails**: Ensure the API Center provider is registered in your subscription
2. **OpenAI model deployment fails**: Check quota availability in the selected region
3. **Permission errors**: Verify your account has sufficient permissions for all required resource types
4. **Network connectivity issues**: Check firewall rules and network security groups

### Debug Commands

```bash
# Check resource provider registration
az provider show --namespace Microsoft.ApiCenter --query registrationState

# View deployment logs
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query 'properties.error'

# Check activity logs
az monitor activity-log list \
    --resource-group ${RESOURCE_GROUP} \
    --start-time 2024-01-01 \
    --output table
```

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for detailed explanations
2. Review Azure service documentation for specific resource configurations
3. Consult the troubleshooting section above
4. Check Azure service health for any ongoing issues

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Validate against the original recipe requirements
3. Update documentation as needed
4. Follow Azure best practices and security guidelines

## License

This infrastructure code is provided under the same license as the recipe collection.