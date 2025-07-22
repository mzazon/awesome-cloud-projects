# Infrastructure as Code for Scalable AI Prompt Workflows with Azure AI Studio and Container Apps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scalable AI Prompt Workflows with Azure AI Studio and Container Apps".

## Solution Overview

This recipe implements a serverless architecture that combines Azure AI Studio's Prompt Flow for visual prompt engineering with Azure Container Apps for automatic scaling. The solution containerizes prompt flows, deploys them as serverless endpoints with scale-to-zero capabilities, and provides comprehensive monitoring through Azure Monitor.

## Available Implementations

- **Bicep**: Azure's recommended Infrastructure as Code language
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts with error handling

## Architecture Components

The infrastructure includes:
- Azure AI Hub and Project for prompt flow development
- Azure Container Registry for container image storage
- Azure Container Apps environment with auto-scaling
- Azure OpenAI service with GPT model deployment
- Log Analytics workspace and Application Insights for monitoring
- Storage account for AI Hub requirements

## Prerequisites

### Azure CLI and Tools
- Azure CLI v2.60.0 or later installed and configured
- Azure subscription with appropriate permissions
- Docker installed locally for container image building
- Bash shell (Linux, macOS, or WSL on Windows)

### Azure Permissions
Your Azure account needs the following permissions:
- Contributor role on the target subscription or resource group
- Ability to create and manage:
  - Resource Groups
  - Azure AI Hub and Projects
  - Azure OpenAI resources
  - Container Apps and environments
  - Container Registry
  - Storage Accounts
  - Log Analytics workspaces
  - Application Insights

### Azure Quotas
Ensure your subscription has sufficient quota for:
- Azure Container Apps in your target region
- Azure OpenAI services (GPT-3.5-turbo model)
- Container Registry storage

### Cost Considerations
- Estimated cost for testing: $5-20 (varies based on usage)
- Main cost drivers: Azure OpenAI API calls, Container Apps consumption, Container Registry storage
- Scale-to-zero capability minimizes idle costs

## Quick Start

### Using Bicep (Recommended for Azure)

1. **Deploy the infrastructure:**
   ```bash
   cd bicep/
   
   # Create resource group
   az group create --name rg-ai-serverless --location eastus
   
   # Deploy Bicep template
   az deployment group create \
       --resource-group rg-ai-serverless \
       --template-file main.bicep \
       --parameters location=eastus
   ```

2. **Build and deploy the container:**
   ```bash
   # The Bicep deployment outputs will include ACR name and Container Apps details
   # Follow the container build and deployment steps in the outputs
   ```

### Using Terraform

1. **Initialize and deploy:**
   ```bash
   cd terraform/
   
   # Initialize Terraform
   terraform init
   
   # Review the deployment plan
   terraform plan
   
   # Apply the configuration
   terraform apply
   ```

2. **Configure variables (optional):**
   ```bash
   # Create terraform.tfvars file for customization
   cat > terraform.tfvars << EOF
   location = "eastus"
   resource_group_name = "rg-ai-serverless-custom"
   environment_name = "production"
   EOF
   ```

### Using Bash Scripts

1. **Deploy with scripts:**
   ```bash
   cd scripts/
   
   # Make scripts executable
   chmod +x deploy.sh destroy.sh
   
   # Run deployment
   ./deploy.sh
   ```

2. **Follow the interactive prompts** for configuration options.

## Deployment Process

The infrastructure deployment follows these logical steps:

1. **Foundation Resources**
   - Resource group creation
   - Storage account for AI Hub
   - Log Analytics workspace for monitoring

2. **AI Platform Setup**
   - Azure AI Hub with integrated security
   - AI Project for prompt flow development
   - Azure OpenAI resource with GPT-3.5-turbo deployment

3. **Container Platform**
   - Azure Container Registry with admin access
   - Container Apps environment with monitoring integration
   - KEDA autoscaling configuration

4. **Application Deployment**
   - Container Apps application with:
     - External ingress on port 8080
     - Scale-to-zero configuration (min: 0, max: 10)
     - HTTP-based scaling rules
     - Environment variables for OpenAI integration

5. **Monitoring Setup**
   - Application Insights for detailed telemetry
   - Custom alerts for response time monitoring
   - Integration with Container Apps logs

## Configuration Options

### Environment Variables

All implementations support these key configuration parameters:

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `resource_group_name` | Name of the resource group | Auto-generated | No |
| `ai_hub_name` | Azure AI Hub name | Auto-generated | No |
| `container_registry_name` | ACR name (must be globally unique) | Auto-generated | No |
| `container_app_name` | Container Apps application name | Auto-generated | No |
| `openai_deployment_name` | OpenAI model deployment name | `gpt-35-turbo` | No |
| `min_replicas` | Minimum container instances | `0` | No |
| `max_replicas` | Maximum container instances | `10` | No |

### Bicep Parameters

Customize the Bicep deployment by creating a `parameters.json` file:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "environmentName": {
      "value": "production"
    },
    "minReplicas": {
      "value": 0
    },
    "maxReplicas": {
      "value": 10
    }
  }
}
```

Then deploy with: `az deployment group create --parameters @parameters.json`

### Terraform Variables

Customize the Terraform deployment by modifying `variables.tf` or creating `terraform.tfvars`:

```hcl
location = "eastus"
resource_group_name = "rg-ai-serverless-prod"
environment_name = "production"
min_replicas = 0
max_replicas = 20
openai_sku = "S0"
```

## Post-Deployment Steps

After infrastructure deployment, complete these steps:

1. **Build and Push Container Image:**
   ```bash
   # Get ACR login server from deployment outputs
   ACR_NAME="<your-acr-name>"
   
   # Build the prompt flow container
   docker build -t promptflow-app:latest .
   docker tag promptflow-app:latest ${ACR_NAME}.azurecr.io/promptflow-app:latest
   
   # Login and push
   az acr login --name ${ACR_NAME}
   docker push ${ACR_NAME}.azurecr.io/promptflow-app:latest
   ```

2. **Update Container App Image:**
   ```bash
   # Update Container App with the pushed image
   az containerapp update \
       --name <container-app-name> \
       --resource-group <resource-group> \
       --image ${ACR_NAME}.azurecr.io/promptflow-app:latest
   ```

3. **Verify Deployment:**
   ```bash
   # Get Container App URL
   APP_URL=$(az containerapp show \
       --name <container-app-name> \
       --resource-group <resource-group> \
       --query properties.configuration.ingress.fqdn -o tsv)
   
   # Test the endpoint
   curl -X POST "https://${APP_URL}/score" \
       -H "Content-Type: application/json" \
       -d '{"question": "What is Azure Container Apps?"}'
   ```

## Monitoring and Observability

The deployed infrastructure includes comprehensive monitoring:

### Application Insights
- Real-time performance metrics
- Request/response tracking
- Custom telemetry and logging
- Dependency tracking for OpenAI calls

### Log Analytics
- Container Apps system logs
- Custom application logs
- Query capabilities with KQL

### Azure Monitor Alerts
- Response time threshold alerts
- Error rate monitoring
- Resource utilization alerts

### Accessing Monitoring Data

```bash
# View Container App logs
az containerapp logs show \
    --name <container-app-name> \
    --resource-group <resource-group> \
    --type system

# Access Application Insights in Azure Portal
echo "View metrics at: https://portal.azure.com/#resource/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/microsoft.insights/components/<app-insights-name>/overview"
```

## Testing and Validation

### Load Testing

Generate load to test auto-scaling:

```bash
# Install testing tools
apt-get update && apt-get install -y apache2-utils

# Generate concurrent requests
ab -n 100 -c 10 -p data.json -T application/json https://${APP_URL}/score

# Monitor scaling
watch "az containerapp replica list --name <container-app-name> --resource-group <resource-group> --output table"
```

### Performance Validation

```bash
# Check response times
curl -w "@curl-format.txt" -X POST "https://${APP_URL}/score" \
    -H "Content-Type: application/json" \
    -d '{"question": "Performance test"}'

# Verify scale-to-zero (after 5 minutes of no traffic)
az containerapp replica list \
    --name <container-app-name> \
    --resource-group <resource-group> \
    --output table
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete --name rg-ai-serverless --yes --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
cd scripts/
./destroy.sh
```

### Manual Cleanup (if needed)
```bash
# List all resources in the resource group
az resource list --resource-group <resource-group-name> --output table

# Delete specific resources if needed
az containerapp delete --name <container-app-name> --resource-group <resource-group-name>
az acr delete --name <acr-name> --resource-group <resource-group-name>
```

## Troubleshooting

### Common Issues

1. **Container App deployment fails:**
   - Check ACR credentials and image availability
   - Verify Container Apps environment is healthy
   - Review deployment logs in Azure Portal

2. **OpenAI API errors:**
   - Verify OpenAI resource deployment status
   - Check API key configuration
   - Ensure sufficient quota for your region

3. **Scaling issues:**
   - Review KEDA scaling configuration
   - Check Container Apps environment capacity
   - Monitor Application Insights for performance bottlenecks

4. **Authentication errors:**
   - Verify Azure CLI login: `az account show`
   - Check subscription permissions
   - Ensure resource provider registrations

### Debug Commands

```bash
# Check Container App status
az containerapp show --name <name> --resource-group <rg> --query properties.provisioningState

# View Container App configuration
az containerapp show --name <name> --resource-group <rg> --output yaml

# Check Container Apps environment
az containerapp env show --name <env-name> --resource-group <rg>

# Verify OpenAI deployment
az cognitiveservices account deployment list --name <openai-name> --resource-group <rg>
```

## Security Considerations

The infrastructure implements several security best practices:

- **Network Security**: Container Apps use HTTPS-only ingress with automatic certificate management
- **Identity Management**: Managed identities for secure service-to-service communication
- **Secrets Management**: Secure storage of API keys and connection strings
- **Container Security**: Private container registry with vulnerability scanning
- **Access Control**: RBAC-based permissions for all resources

### Additional Security Hardening

Consider implementing these additional security measures for production:

1. **Private Endpoints**: Configure private endpoints for ACR and AI services
2. **Network Isolation**: Use virtual networks and private subnets
3. **API Management**: Add Azure API Management for authentication and rate limiting
4. **Key Vault**: Store secrets in Azure Key Vault instead of environment variables

## Customization Examples

### Multi-Environment Deployment

```bash
# Development environment
az deployment group create \
    --resource-group rg-ai-dev \
    --template-file main.bicep \
    --parameters environmentName=development minReplicas=0 maxReplicas=3

# Production environment  
az deployment group create \
    --resource-group rg-ai-prod \
    --template-file main.bicep \
    --parameters environmentName=production minReplicas=1 maxReplicas=20
```

### Custom Scaling Rules

Modify the Container App configuration for custom scaling:

```bash
az containerapp update \
    --name <container-app-name> \
    --resource-group <resource-group> \
    --scale-rule-name cpu-rule \
    --scale-rule-type cpu \
    --scale-rule-metadata targetCpuUtilization=70 \
    --min-replicas 1 \
    --max-replicas 15
```

## Support and Documentation

### Additional Resources

- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [Azure AI Studio Documentation](https://docs.microsoft.com/en-us/azure/ai-studio/)
- [Prompt Flow Documentation](https://docs.microsoft.com/en-us/azure/machine-learning/prompt-flow/)
- [Azure OpenAI Service Documentation](https://docs.microsoft.com/en-us/azure/ai-services/openai/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

### Community and Support

- For infrastructure code issues, refer to the original recipe documentation
- For Azure service-specific issues, consult the official Azure documentation
- For Terraform issues, check the Azure provider documentation
- For Bicep issues, refer to the Azure Resource Manager documentation

---

**Note**: This infrastructure code is generated based on the recipe "Scalable AI Prompt Workflows with Azure AI Studio and Container Apps". For the most up-to-date version and detailed implementation steps, refer to the original recipe documentation.