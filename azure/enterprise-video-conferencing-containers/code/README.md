# Infrastructure as Code for Enterprise Video Conferencing with Container Deployment

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise Video Conferencing with Container Deployment".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.67.0 or higher installed and configured
- Azure subscription with appropriate permissions for:
  - Azure Communication Services
  - Azure Web App for Containers
  - Azure Container Registry
  - Azure Blob Storage
  - Azure Application Insights
  - Azure App Service Plans
  - Azure Monitor (for auto-scaling)
- Docker installed locally for container development and testing
- Git for version control and deployment
- For Terraform: Terraform v1.0+ installed
- For Bicep: Bicep CLI installed (or use Azure CLI with Bicep support)

## Architecture Overview

This solution deploys a scalable video conferencing application using:

- **Azure Web App for Containers**: Hosts the containerized Node.js application
- **Azure Communication Services**: Provides video calling and recording capabilities
- **Azure Container Registry**: Stores and manages container images
- **Azure Blob Storage**: Stores call recordings and application assets
- **Azure Application Insights**: Monitors application performance and usage
- **Azure Monitor**: Provides auto-scaling capabilities based on demand

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-video-conferencing-app \
    --template-file main.bicep \
    --parameters @parameters.json

# Or deploy with inline parameters
az deployment group create \
    --resource-group rg-video-conferencing-app \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters environmentName=dev
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply
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

### Environment Variables

Set these environment variables before deployment:

```bash
export RESOURCE_GROUP="rg-video-conferencing-app"
export LOCATION="eastus"
export ENVIRONMENT="dev"
```

### Bicep Parameters

Customize the deployment by modifying `bicep/parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "environmentName": {
      "value": "dev"
    },
    "appServicePlanSku": {
      "value": "P1V2"
    },
    "containerRegistryName": {
      "value": "acrvideo"
    },
    "communicationServiceDataLocation": {
      "value": "UnitedStates"
    }
  }
}
```

### Terraform Variables

Customize the deployment by modifying `terraform/terraform.tfvars`:

```hcl
location = "East US"
environment = "dev"
app_service_plan_sku = "P1V2"
container_registry_name = "acrvideo"
communication_service_data_location = "UnitedStates"
```

## Deployment Steps

### 1. Pre-deployment Setup

```bash
# Create resource group
az group create --name rg-video-conferencing-app --location eastus

# Login to Azure (if not already logged in)
az login

# Set active subscription
az account set --subscription "your-subscription-id"
```

### 2. Deploy Infrastructure

Choose one of the deployment methods above based on your preference and requirements.

### 3. Application Deployment

After infrastructure deployment, deploy your application:

```bash
# Build and push container image
docker build -t youracr.azurecr.io/video-conferencing-app:latest .
az acr login --name youracr
docker push youracr.azurecr.io/video-conferencing-app:latest

# Update web app to use the new image
az webapp config container set \
    --name your-webapp-name \
    --resource-group rg-video-conferencing-app \
    --container-image-name youracr.azurecr.io/video-conferencing-app:latest
```

### 4. Validation

Verify the deployment:

```bash
# Check web app status
az webapp show --name your-webapp-name --resource-group rg-video-conferencing-app

# Test the application
curl https://your-webapp-name.azurewebsites.net/health

# Check auto-scaling configuration
az monitor autoscale show \
    --resource-group rg-video-conferencing-app \
    --name video-conferencing-autoscale
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name rg-video-conferencing-app --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Monitoring and Scaling

### Application Insights

Monitor your application performance:

```bash
# View Application Insights metrics
az monitor app-insights component show \
    --app video-conferencing-insights \
    --resource-group rg-video-conferencing-app
```

### Auto-scaling Configuration

The infrastructure includes auto-scaling rules that:
- Scale out when CPU usage > 70% for 5 minutes
- Scale in when CPU usage < 30% for 5 minutes
- Minimum instances: 1
- Maximum instances: 10

### Custom Metrics

Set up custom metrics for video conferencing specific monitoring:
- Active call count
- Recording storage usage
- Token generation rate
- Connection success rate

## Security Considerations

### Network Security

- Web App for Containers uses HTTPS by default
- Container Registry access is restricted to authorized users
- Application Insights data is encrypted at rest and in transit

### Identity and Access Management

- Azure Communication Services uses connection strings for authentication
- Container Registry credentials are managed through Azure Key Vault integration
- Application settings are encrypted and securely stored

### Data Protection

- Call recordings are stored in Azure Blob Storage with encryption
- Connection strings and sensitive data are stored as secure application settings
- All data transfers use TLS encryption

## Cost Optimization

### Resource Sizing

- **App Service Plan**: P1V2 tier provides good balance of performance and cost
- **Container Registry**: Basic tier suitable for development/testing
- **Storage Account**: Standard LRS for cost-effective recording storage
- **Communication Services**: Pay-per-use pricing model

### Scaling Recommendations

- Use auto-scaling to optimize costs based on actual usage
- Consider Azure Reserved Instances for predictable workloads
- Implement storage lifecycle policies for old recordings
- Monitor Application Insights for optimization opportunities

## Troubleshooting

### Common Issues

1. **Container deployment fails**:
   - Check Container Registry credentials
   - Verify image exists and is accessible
   - Review container logs in App Service

2. **Communication Services token generation fails**:
   - Verify connection string is correct
   - Check service availability in target region
   - Review Application Insights for detailed errors

3. **Auto-scaling not working**:
   - Verify scaling rules are correctly configured
   - Check that App Service Plan supports auto-scaling
   - Review metric thresholds and time windows

### Debugging Commands

```bash
# Check web app logs
az webapp log tail --name your-webapp-name --resource-group rg-video-conferencing-app

# View container logs
az webapp log config --name your-webapp-name --resource-group rg-video-conferencing-app --docker-container-logging filesystem

# Check Application Insights
az monitor app-insights component show --app video-conferencing-insights --resource-group rg-video-conferencing-app
```

## Extensions and Customizations

### Additional Features

1. **Content Delivery Network (CDN)**:
   - Add Azure CDN for global content delivery
   - Cache static assets for improved performance

2. **Azure SignalR Service**:
   - Implement real-time notifications
   - Add presence indicators for users

3. **Azure Key Vault**:
   - Store sensitive configuration securely
   - Implement certificate management

4. **Azure Front Door**:
   - Add global load balancing
   - Implement Web Application Firewall

### Performance Optimization

1. **Caching Strategy**:
   - Implement Redis cache for session management
   - Cache frequently accessed data

2. **Database Integration**:
   - Add Azure SQL Database for user management
   - Implement call history and analytics

3. **Content Optimization**:
   - Optimize container images for faster startup
   - Implement efficient video encoding settings

## Support and Documentation

### Azure Documentation

- [Azure Web App for Containers](https://docs.microsoft.com/en-us/azure/app-service/containers/)
- [Azure Communication Services](https://docs.microsoft.com/en-us/azure/communication-services/)
- [Azure Container Registry](https://docs.microsoft.com/en-us/azure/container-registry/)
- [Azure Blob Storage](https://docs.microsoft.com/en-us/azure/storage/blobs/)
- [Azure Application Insights](https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)

### Best Practices

- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)
- [Container Security Best Practices](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-best-practices)
- [Communication Services Security](https://docs.microsoft.com/en-us/azure/communication-services/concepts/security)

### Community Resources

- [Azure Communication Services Samples](https://github.com/Azure-Samples/communication-services-web-calling-tutorial)
- [Azure Container Apps Community](https://github.com/microsoft/azure-container-apps)
- [Azure Architecture Center](https://docs.microsoft.com/en-us/azure/architecture/)

## License

This infrastructure code is provided as-is for educational and development purposes. Review and modify according to your organization's requirements and policies.

## Contributing

To contribute improvements to this infrastructure code:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.