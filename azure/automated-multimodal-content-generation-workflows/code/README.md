# Infrastructure as Code for Automated Multimodal Content Generation Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Multimodal Content Generation Workflows".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.61.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Azure AI Foundry (Machine Learning services)
  - Azure Container Registry
  - Azure Event Grid
  - Azure Key Vault
  - Azure Functions
  - Azure Storage
- Docker Desktop for building custom AI model containers
- Python 3.9+ for Function App development
- Estimated cost: $50-100 for initial setup and testing

## Quick Start

### Using Bicep (Recommended)

```bash
cd bicep/

# Login to Azure and set subscription
az login
az account set --subscription <your-subscription-id>

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters @parameters.json

# Note: Update parameters.json with your specific values before deployment
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# Confirm deployment when prompted
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-multimodal-content-demo"
export LOCATION="eastus"

# Deploy infrastructure
./scripts/deploy.sh

# The script will create all necessary resources and provide output values
```

## Architecture Components

The infrastructure includes:

- **Azure AI Foundry Hub and Project**: Central orchestration platform for multi-modal AI workflows
- **Azure Container Registry**: Secure storage for custom AI model containers with Premium tier features
- **Azure Event Grid**: Event-driven workflow orchestration with custom topics
- **Azure Key Vault**: Centralized secure storage for API keys and configuration
- **Azure Functions**: Serverless orchestration of content generation workflows
- **Azure Storage Account**: Content output storage with blob containers

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
      "value": "multimodal"
    },
    "environment": {
      "value": "demo"
    }
  }
}
```

### Terraform Variables

Customize `terraform/terraform.tfvars`:

```hcl
resource_group_name = "rg-multimodal-content-demo"
location           = "eastus"
resource_prefix    = "multimodal"
environment        = "demo"
enable_monitoring  = true
```

### Environment Variables for Scripts

Set these variables before running bash scripts:

```bash
export RESOURCE_GROUP="rg-multimodal-content-demo"
export LOCATION="eastus"
export SUBSCRIPTION_ID="your-subscription-id"
```

## Post-Deployment Steps

1. **Deploy AI Models**: After infrastructure deployment, deploy GPT-4o and DALL-E 3 models using Azure AI Foundry Studio or CLI
2. **Build Custom Container**: Build and push your custom AI model container to the created Azure Container Registry
3. **Configure Function App**: Deploy the content generation function code to the created Function App
4. **Test Event Grid**: Send test events to validate the end-to-end workflow

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name <your-resource-group> --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Validation

After deployment, verify the infrastructure:

```bash
# Check AI Foundry workspace
az ml workspace show --name <ai-foundry-project-name> --resource-group <resource-group>

# Verify Container Registry
az acr show --name <registry-name> --resource-group <resource-group>

# Test Event Grid topic
az eventgrid topic show --name <topic-name> --resource-group <resource-group>

# Check Key Vault access
az keyvault show --name <vault-name> --resource-group <resource-group>
```

## Security Considerations

- All resources use managed identities where possible
- Key Vault implements RBAC authorization instead of access policies
- Container Registry uses Premium tier with vulnerability scanning
- Storage accounts disable public blob access by default
- Event Grid uses secured endpoints with access keys stored in Key Vault

## Monitoring and Observability

The infrastructure includes:

- Azure Monitor integration for all services
- Application Insights for Function App monitoring
- Container Registry activity logs
- Event Grid delivery metrics
- Key Vault audit logging

## Troubleshooting

### Common Issues

1. **AI Foundry Model Deployment Failures**
   - Verify compute quota in the target region
   - Check model availability in Azure AI Foundry catalog
   - Ensure proper permissions for model deployment

2. **Container Registry Access Issues**
   - Verify managed identity assignments
   - Check network access rules if using private endpoints
   - Validate Docker login credentials

3. **Event Grid Delivery Failures**
   - Check Function App endpoint configuration
   - Verify Event Grid topic permissions
   - Review Function App logs for errors

4. **Key Vault Access Denied**
   - Verify RBAC role assignments
   - Check network access policies
   - Validate managed identity configuration

### Support Resources

- [Azure AI Foundry Documentation](https://docs.microsoft.com/en-us/azure/ai-foundry/)
- [Azure Container Registry Documentation](https://docs.microsoft.com/en-us/azure/container-registry/)
- [Azure Event Grid Documentation](https://docs.microsoft.com/en-us/azure/event-grid/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)

## Customization

### Adding Custom AI Models

1. Build your custom model container following the provided Dockerfile template
2. Push to the deployed Azure Container Registry
3. Update Function App configuration to include new model endpoints
4. Modify Event Grid subscription filters as needed

### Scaling Considerations

- Function App: Uses consumption plan for automatic scaling
- AI Foundry: Scale model deployments based on expected load
- Container Registry: Premium tier supports geo-replication for global deployments
- Event Grid: Automatically scales to handle event volume

## Cost Optimization

- Use Azure Cost Management to monitor spending
- Configure auto-scaling policies for AI model deployments
- Implement lifecycle policies for container images
- Consider reserved instances for predictable workloads
- Monitor and optimize storage usage patterns

## Support

For issues with this infrastructure code, refer to:

1. The original recipe documentation
2. Azure provider documentation for specific resources
3. Azure support channels for service-specific issues
4. Community forums for best practices and troubleshooting