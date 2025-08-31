# Infrastructure as Code for Meeting Intelligence with Speech Services and OpenAI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Meeting Intelligence with Speech Services and OpenAI".

## Solution Overview

This recipe deploys an intelligent meeting analysis system that automatically processes audio recordings using Azure Speech Services for transcription with speaker identification, Azure OpenAI for extracting insights and action items, and Azure Service Bus with Functions for reliable serverless processing workflows.

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure deploys the following Azure resources:

- **Resource Group**: Container for all resources
- **Storage Account**: Blob storage for meeting recordings
- **Speech Services**: AI service for audio transcription with speaker diarization
- **OpenAI Service**: GPT-4 model deployment for meeting intelligence extraction
- **Service Bus Namespace**: Messaging infrastructure with queues and topics
- **Function App**: Serverless compute for processing workflows
- **Application Insights**: Monitoring and logging (optional)

## Prerequisites

### General Requirements

- Azure subscription with appropriate permissions
- Azure CLI installed and configured (`az --version` >= 2.50.0)
- Bash shell environment (Linux, macOS, or WSL on Windows)

### Service-Specific Requirements

- **Owner** or **Contributor** role on the Azure subscription
- **Cognitive Services Contributor** role for AI services
- **Storage Account Contributor** role for blob storage
- **Service Bus Data Owner** role for messaging resources

### Tool-Specific Prerequisites

#### For Bicep Deployment
```bash
# Verify Bicep CLI is available
az bicep version
```

#### For Terraform Deployment
```bash
# Install Terraform (version 1.5+)
# On macOS with Homebrew:
brew install terraform

# On Ubuntu/Debian:
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
sudo apt update && sudo apt install terraform

# Verify installation
terraform version
```

## Quick Start

### Using Bicep (Recommended)

Bicep is Microsoft's domain-specific language for deploying Azure resources with native Azure integration.

```bash
cd bicep/

# Login to Azure (if not already authenticated)
az login

# Set subscription (replace with your subscription ID)
az account set --subscription "your-subscription-id"

# Deploy infrastructure
az deployment sub create \
  --location "East US" \
  --template-file main.bicep \
  --parameters @parameters.json \
  --parameters resourceNameSuffix=$(openssl rand -hex 3)

# Monitor deployment progress
az deployment sub show \
  --name main \
  --query "properties.provisioningState"
```

### Using Terraform

Terraform provides multi-cloud infrastructure management with comprehensive state management.

```bash
cd terraform/

# Initialize Terraform working directory
terraform init

# Authenticate with Azure (if not already authenticated)
az login

# Review planned infrastructure changes
terraform plan \
  -var="resource_name_suffix=$(openssl rand -hex 3)" \
  -var="location=East US"

# Apply infrastructure changes
terraform apply \
  -var="resource_name_suffix=$(openssl rand -hex 3)" \
  -var="location=East US"

# View infrastructure outputs
terraform output
```

### Using Bash Scripts

Automated deployment scripts provide streamlined infrastructure provisioning with built-in error handling.

```bash
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy infrastructure with random suffix
./deploy.sh

# Deploy with custom configuration
AZURE_LOCATION="West US 2" \
RESOURCE_SUFFIX="prod01" \
./deploy.sh
```

## Configuration Options

### Environment Variables

Set these environment variables to customize the deployment:

```bash
# Required
export AZURE_SUBSCRIPTION_ID="your-subscription-id"

# Optional (defaults provided)
export AZURE_LOCATION="East US"                    # Azure region
export RESOURCE_SUFFIX="$(openssl rand -hex 3)"    # Unique suffix for resources
export RESOURCE_GROUP_NAME="rg-meeting-intelligence-${RESOURCE_SUFFIX}"
export STORAGE_ACCOUNT_NAME="meetingstorage${RESOURCE_SUFFIX}"
export SPEECH_SERVICE_NAME="speech-meeting-${RESOURCE_SUFFIX}"
export OPENAI_SERVICE_NAME="openai-meeting-${RESOURCE_SUFFIX}"
export FUNCTION_APP_NAME="func-meeting-${RESOURCE_SUFFIX}"
export SERVICEBUS_NAMESPACE="sb-meeting-${RESOURCE_SUFFIX}"
```

### Bicep Parameters

Customize deployment by modifying `bicep/parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "East US"
    },
    "resourceNameSuffix": {
      "value": "demo"
    },
    "speechServiceSku": {
      "value": "S0"
    },
    "openaiServiceSku": {
      "value": "S0"
    },
    "functionAppPlan": {
      "value": "Consumption"
    },
    "enableApplicationInsights": {
      "value": true
    }
  }
}
```

### Terraform Variables

Customize deployment by modifying variables in `terraform/terraform.tfvars`:

```hcl
# Core configuration
location = "East US"
resource_name_suffix = "demo"

# Service tiers
speech_service_sku = "S0"
openai_service_sku = "S0"
storage_account_tier = "Standard"
storage_account_replication = "LRS"

# Function App configuration
function_app_runtime = "python"
function_app_version = "3.11"

# OpenAI model deployment
openai_model_name = "gpt-4o"
openai_model_version = "2024-11-20"
openai_deployment_capacity = 1

# Optional features
enable_application_insights = true
enable_advanced_threat_protection = false

# Tags
tags = {
  Environment = "Development"
  Project     = "Meeting Intelligence"
  Owner       = "AI Team"
}
```

## Post-Deployment Configuration

### 1. Verify Resource Deployment

```bash
# Check resource group contents
az resource list \
  --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}" \
  --output table

# Verify Function App is running
az functionapp show \
  --name "func-meeting-${RESOURCE_SUFFIX}" \
  --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}" \
  --query "state"
```

### 2. Deploy Function Code

The infrastructure creates the Function App, but you need to deploy the function code:

```bash
# Navigate to the function code directory (create from recipe)
mkdir -p meeting-functions && cd meeting-functions

# Deploy using Azure Functions Core Tools
func azure functionapp publish "func-meeting-${RESOURCE_SUFFIX}" --python
```

### 3. Test the Solution

```bash
# Get storage account connection details
STORAGE_ACCOUNT="meetingstorage${RESOURCE_SUFFIX}"
CONTAINER_NAME="meeting-recordings"

# Generate SAS URL for file upload (valid for 1 hour)
az storage container generate-sas \
  --account-name ${STORAGE_ACCOUNT} \
  --name ${CONTAINER_NAME} \
  --permissions rwl \
  --expiry $(date -u -d '1 hour' +%Y-%m-%dT%H:%MZ) \
  --auth-mode login

# Upload a test audio file
az storage blob upload \
  --account-name ${STORAGE_ACCOUNT} \
  --container-name ${CONTAINER_NAME} \
  --name "test-meeting.wav" \
  --file "/path/to/your/audio-file.wav" \
  --auth-mode login
```

### 4. Monitor Processing

```bash
# Monitor Function App logs
az functionapp logs tail \
  --name "func-meeting-${RESOURCE_SUFFIX}" \
  --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}"

# Check Service Bus queue metrics
az servicebus queue show \
  --namespace-name "sb-meeting-${RESOURCE_SUFFIX}" \
  --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}" \
  --name "transcript-processing" \
  --query "{activeMessages:messageCount, deadLetterMessages:deadLetterMessageCount}"
```

## Cost Optimization

### Estimated Costs (USD per month)

Based on moderate usage (10 hours of audio per month):

| Service | Configuration | Estimated Cost |
|---------|--------------|----------------|
| Speech Services | S0 tier | $15-25 |
| OpenAI Service | GPT-4 usage | $10-20 |
| Functions | Consumption plan | $1-5 |
| Service Bus | Standard tier | $10 |
| Storage Account | Standard LRS | $1-3 |
| **Total** | | **$37-63** |

### Cost Optimization Tips

1. **Use consumption-based pricing** for Functions to pay only for execution time
2. **Monitor OpenAI usage** and implement request throttling if needed
3. **Configure storage lifecycle policies** to automatically archive old recordings
4. **Use Standard tier Service Bus** instead of Premium if advanced features aren't needed
5. **Enable auto-pause** for development environments

## Security Considerations

### Implemented Security Features

- **Managed Identity**: Function App uses system-assigned managed identity
- **Key Vault Integration**: Sensitive configuration stored in Azure Key Vault
- **Private Endpoints**: Optional private network access for storage and AI services
- **Network Security Groups**: Restrictive network access rules
- **Encryption**: Data encrypted at rest and in transit
- **RBAC**: Role-based access control for all resources

### Additional Security Recommendations

1. **Enable Azure Defender** for advanced threat protection
2. **Configure diagnostic logging** for all resources
3. **Implement network segmentation** using VNets and subnets
4. **Regular security assessments** using Azure Security Center
5. **Audit access logs** regularly for unauthorized activity

## Troubleshooting

### Common Issues

#### 1. Function App Not Starting

```bash
# Check Function App logs
az functionapp logs tail --name "func-meeting-${RESOURCE_SUFFIX}" --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}"

# Verify configuration settings
az functionapp config appsettings list --name "func-meeting-${RESOURCE_SUFFIX}" --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}"
```

#### 2. Speech Services Access Denied

```bash
# Verify Speech Services key
az cognitiveservices account keys list --name "speech-meeting-${RESOURCE_SUFFIX}" --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}"

# Test API access
curl -H "Ocp-Apim-Subscription-Key: YOUR_KEY" "https://eastus.api.cognitive.microsoft.com/speechtotext/v3.2/transcriptions" -I
```

#### 3. OpenAI Model Not Available

```bash
# Check model deployment status
az cognitiveservices account deployment list --name "openai-meeting-${RESOURCE_SUFFIX}" --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}"

# Verify available models in region
az cognitiveservices account list-models --name "openai-meeting-${RESOURCE_SUFFIX}" --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}"
```

#### 4. Service Bus Connection Issues

```bash
# Verify Service Bus connection string
az servicebus namespace authorization-rule keys list --namespace-name "sb-meeting-${RESOURCE_SUFFIX}" --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}" --name RootManageSharedAccessKey

# Check queue status
az servicebus queue show --namespace-name "sb-meeting-${RESOURCE_SUFFIX}" --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}" --name "transcript-processing"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
  --name "rg-meeting-intelligence-${RESOURCE_SUFFIX}" \
  --yes \
  --no-wait

# Verify deletion
az group exists --name "rg-meeting-intelligence-${RESOURCE_SUFFIX}"
```

### Using Terraform

```bash
cd terraform/

# Destroy all infrastructure
terraform destroy \
  -var="resource_name_suffix=${RESOURCE_SUFFIX}" \
  -var="location=East US"

# Clean up Terraform state files (optional)
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts

```bash
cd scripts/

# Run cleanup script
./destroy.sh

# Verify cleanup completed successfully
echo $?  # Should return 0 for success
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
az resource list \
  --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}" \
  --output table

# Check for any remaining cognitive services
az cognitiveservices account list \
  --query "[?contains(name, '${RESOURCE_SUFFIX}')]" \
  --output table
```

## Advanced Configuration

### Scaling Configuration

For production workloads, consider these scaling options:

#### Function App Scaling

```bash
# Configure maximum instance count
az functionapp config appsettings set \
  --name "func-meeting-${RESOURCE_SUFFIX}" \
  --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}" \
  --settings "FUNCTIONS_WORKER_RUNTIME_MAX_INSTANCES=20"
```

#### Service Bus Scaling

```bash
# Upgrade to Premium tier for higher throughput
az servicebus namespace update \
  --name "sb-meeting-${RESOURCE_SUFFIX}" \
  --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}" \
  --sku Premium
```

### Multi-Region Deployment

For global deployments, consider:

1. **Deploy to multiple regions** for reduced latency
2. **Use Traffic Manager** for intelligent routing
3. **Implement cross-region replication** for storage
4. **Configure geo-redundant backups** for critical data

### Integration Patterns

#### Microsoft Teams Integration

```bash
# Configure Teams webhook for notifications
az functionapp config appsettings set \
  --name "func-meeting-${RESOURCE_SUFFIX}" \
  --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}" \
  --settings "TEAMS_WEBHOOK_URL=https://your-org.webhook.office.com/..."
```

#### Power BI Dashboard

```bash
# Configure Power BI streaming dataset
az functionapp config appsettings set \
  --name "func-meeting-${RESOURCE_SUFFIX}" \
  --resource-group "rg-meeting-intelligence-${RESOURCE_SUFFIX}" \
  --settings "POWERBI_STREAMING_URL=https://api.powerbi.com/beta/..."
```

## Support and Documentation

### Official Documentation

- [Azure Speech Services](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/)
- [Azure OpenAI Service](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/)
- [Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/)
- [Azure Service Bus](https://learn.microsoft.com/en-us/azure/service-bus-messaging/)
- [Azure Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

### Community Resources

- [Azure Functions GitHub](https://github.com/Azure/Azure-Functions)
- [Azure Speech SDK Samples](https://github.com/Azure-Samples/cognitive-services-speech-sdk)
- [Azure OpenAI Examples](https://github.com/Azure/azure-openai-samples)

### Getting Help

For issues with this infrastructure code:

1. **Check the troubleshooting section** above
2. **Review Azure resource logs** in the Azure portal
3. **Consult the original recipe documentation** for implementation details
4. **Open an issue** in the recipe repository with detailed error information

---

**Note**: This infrastructure code is generated based on the Meeting Intelligence recipe. Customize the configuration variables to match your specific requirements and organizational policies.