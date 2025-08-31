# Infrastructure as Code for Simple Container App Deployment with Container Apps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Container App Deployment with Container Apps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.28.0 or higher)
- Active Azure subscription with appropriate permissions
- For Bicep: Azure CLI with Bicep extension installed
- For Terraform: Terraform installed (version 1.0+)
- Basic understanding of containerized applications

### Required Azure Permissions

- Contributor role on the subscription or resource group
- Ability to register resource providers (Microsoft.App, Microsoft.OperationalInsights)

## Quick Start

### Using Bicep (Recommended)

Bicep is Microsoft's domain-specific language for deploying Azure resources with simplified syntax and excellent tooling support.

```bash
# Navigate to the bicep directory
cd bicep/

# Create a resource group (if not exists)
az group create --name rg-containerapp-demo --location eastus

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-containerapp-demo \
    --template-file main.bicep \
    --parameters containerAppName=hello-app-demo

# Get the application URL
az deployment group show \
    --resource-group rg-containerapp-demo \
    --name main \
    --query properties.outputs.applicationUrl.value
```

### Using Terraform

Terraform provides consistent workflow across multiple cloud providers with extensive provider ecosystem support.

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform (download providers and modules)
terraform init

# Review the planned changes
terraform plan -var="container_app_name=hello-app-demo"

# Apply the configuration
terraform apply -var="container_app_name=hello-app-demo"

# Get the application URL
terraform output application_url
```

### Using Bash Scripts

Automated deployment scripts that follow the recipe's step-by-step approach with enhanced error handling and validation.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output the application URL upon completion
```

## Configuration Options

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `resourceGroup().location` | Azure region for resources |
| `containerAppName` | string | `hello-app-${uniqueString(resourceGroup().id)}` | Name for the container app |
| `environmentName` | string | `env-${containerAppName}` | Container Apps environment name |
| `containerImage` | string | `mcr.microsoft.com/k8se/quickstart:latest` | Container image to deploy |
| `targetPort` | int | `80` | Port the container listens on |
| `minReplicas` | int | `0` | Minimum number of replicas |
| `maxReplicas` | int | `5` | Maximum number of replicas |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `location` | string | `"East US"` | Azure region for resources |
| `resource_group_name` | string | `"rg-containerapp-demo"` | Resource group name |
| `container_app_name` | string | `"hello-app-demo"` | Name for the container app |
| `environment_name` | string | `"env-demo"` | Container Apps environment name |
| `container_image` | string | `"mcr.microsoft.com/k8se/quickstart:latest"` | Container image to deploy |
| `target_port` | number | `80` | Port the container listens on |
| `min_replicas` | number | `0` | Minimum number of replicas |
| `max_replicas` | number | `5` | Maximum number of replicas |

### Bash Script Environment Variables

The deployment script accepts these environment variables for customization:

```bash
export RESOURCE_GROUP="rg-containerapp-demo"
export LOCATION="eastus"
export CONTAINER_APP_NAME="hello-app-demo"
export CONTAINER_IMAGE="mcr.microsoft.com/k8se/quickstart:latest"
```

## Architecture Components

The infrastructure creates these Azure resources:

- **Resource Group**: Logical container for all resources
- **Log Analytics Workspace**: Provides monitoring and logging capabilities
- **Container Apps Environment**: Secure boundary for container applications
- **Container App**: Serverless container deployment with:
  - Automatic HTTPS ingress
  - Scale-to-zero capabilities
  - Built-in load balancing
  - Integrated monitoring

## Outputs

All implementations provide these outputs:

- `application_url`: The HTTPS URL of the deployed container application
- `resource_group_name`: Name of the created resource group
- `container_app_name`: Name of the deployed container app
- `environment_name`: Name of the Container Apps environment

## Validation and Testing

After deployment, validate the infrastructure:

```bash
# Test the application endpoint
curl -I https://<application_url>

# Check container app status
az containerapp show \
    --name <container_app_name> \
    --resource-group <resource_group_name> \
    --query "properties.provisioningState"

# View application logs
az containerapp logs show \
    --name <container_app_name> \
    --resource-group <resource_group_name>
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name rg-containerapp-demo --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="container_app_name=hello-app-demo"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

## Cost Considerations

Azure Container Apps follows a consumption-based pricing model:

- **Free tier**: 180,000 vCPU-seconds and 360,000 GiB-seconds per month
- **Pay-per-use**: $0.000024 per vCPU-second and $0.000024 per GiB-second
- **Estimated cost**: $0.10-$2.00 for this demo (depending on usage)

Scale-to-zero capabilities ensure you only pay for actual resource consumption.

## Security Features

The infrastructure implements these security best practices:

- **Automatic HTTPS**: SSL/TLS certificates managed by Azure
- **Network isolation**: Container Apps environment provides secure boundaries
- **Managed identity**: No stored credentials required
- **Log Analytics**: Comprehensive audit and monitoring capabilities
- **Private endpoints**: Optional for enhanced network security

## Troubleshooting

### Common Issues

1. **Resource provider not registered**:
   ```bash
   az provider register --namespace Microsoft.App
   az provider register --namespace Microsoft.OperationalInsights
   ```

2. **Container image pull failures**:
   - Verify the container image exists and is publicly accessible
   - Check container app logs for detailed error messages

3. **Environment creation timeout**:
   - Ensure sufficient quota in the selected region
   - Try a different Azure region if resources are constrained

4. **Application not accessible**:
   - Verify ingress is configured as "external"
   - Check that target port matches container's listening port

### Debug Commands

```bash
# Check deployment status
az deployment group show \
    --resource-group <resource_group_name> \
    --name <deployment_name>

# View container app details
az containerapp show \
    --name <container_app_name> \
    --resource-group <resource_group_name>

# Check environment status
az containerapp env show \
    --name <environment_name> \
    --resource-group <resource_group_name>
```

## Customization

### Using Custom Container Images

To deploy your own container image:

1. **Build and push to Azure Container Registry**:
   ```bash
   # Create Azure Container Registry
   az acr create --name myregistry --resource-group rg-containerapp-demo --sku Basic
   
   # Build and push image
   az acr build --registry myregistry --image myapp:v1 .
   ```

2. **Update deployment parameters**:
   - Bicep: Set `containerImage` parameter to `myregistry.azurecr.io/myapp:v1`
   - Terraform: Set `container_image` variable
   - Bash: Set `CONTAINER_IMAGE` environment variable

### Adding Environment Variables

Modify the infrastructure to include application configuration:

```bash
# Example environment variables for container app
az containerapp update \
    --name <container_app_name> \
    --resource-group <resource_group_name> \
    --set-env-vars API_KEY=secretref:api-key DATABASE_URL=postgresql://...
```

### Scaling Configuration

Adjust scaling parameters based on your workload:

```bash
# Update scaling rules
az containerapp update \
    --name <container_app_name> \
    --resource-group <resource_group_name> \
    --min-replicas 1 \
    --max-replicas 10
```

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# Azure DevOps Pipeline example
steps:
- task: AzureCLI@2
  displayName: 'Deploy Container App'
  inputs:
    azureSubscription: 'Azure-Subscription'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
      cd bicep/
      az deployment group create \
        --resource-group $(resourceGroupName) \
        --template-file main.bicep \
        --parameters containerAppName=$(Build.BuildId)
```

### GitHub Actions Integration

```yaml
# GitHub Actions workflow example
- name: Deploy to Azure Container Apps
  uses: azure/CLI@v1
  with:
    azcliversion: 2.30.0
    inlineScript: |
      cd terraform/
      terraform init
      terraform apply -auto-approve \
        -var="container_app_name=myapp-${{ github.sha }}"
```

## Next Steps

1. **Add monitoring**: Integrate with Azure Application Insights for detailed telemetry
2. **Implement secrets**: Use Azure Key Vault for sensitive configuration
3. **Configure custom domains**: Add your own domain with SSL certificate
4. **Set up CI/CD**: Automate deployments from your source control
5. **Scale configuration**: Adjust based on production requirements

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../simple-container-deployment-container-apps.md)
2. Consult [Azure Container Apps documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
3. Check [Azure CLI reference](https://docs.microsoft.com/en-us/cli/azure/containerapp)
4. Visit [Terraform Azure Provider documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest)

## Contributing

When modifying this infrastructure code:

1. Test all deployment methods (Bicep, Terraform, Bash)
2. Update documentation for any parameter changes
3. Validate cost estimates and security configurations
4. Ensure cleanup procedures work correctly