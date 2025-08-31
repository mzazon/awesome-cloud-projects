# Infrastructure as Code for Simple Configuration Management with App Configuration and App Service

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Configuration Management with App Configuration and App Service".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login` completed)
- Active Azure subscription with appropriate permissions
- For Bicep: Azure CLI with Bicep extension (`az bicep install`)
- For Terraform: Terraform CLI installed (version >= 1.0)
- For ASP.NET Core deployment: .NET 8.0 SDK
- Permissions required:
  - Create resource groups
  - Create Azure App Configuration stores
  - Create Azure App Service resources
  - Assign role-based access control (RBAC) permissions

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy infrastructure
az deployment group create \
    --resource-group rg-config-demo \
    --template-file bicep/main.bicep \
    --parameters location=eastus

# Get deployment outputs
az deployment group show \
    --resource-group rg-config-demo \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy complete solution
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Solution Components

This IaC deployment creates the following Azure resources:

- **Resource Group**: Container for organizing related resources
- **Azure App Configuration**: Centralized configuration store with sample key-value pairs
- **App Service Plan**: Hosting plan for the web application (Free tier)
- **App Service**: Web application with managed identity enabled
- **Role Assignment**: Grants App Configuration Data Reader permissions to the managed identity
- **Application Settings**: Configures the web app with App Configuration endpoint

## Configuration Values

The deployment automatically creates these sample configuration keys in App Configuration:

- `DemoApp:Settings:Title`: "Configuration Management Demo"
- `DemoApp:Settings:BackgroundColor`: "#2563eb"
- `DemoApp:Settings:Message`: "Hello from Azure App Configuration!"
- `DemoApp:Settings:RefreshInterval`: "30"

## Deployment Parameters

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | No |
| `resourceGroupName` | Name of the resource group | `rg-config-demo-{uniqueString}` | No |
| `appConfigName` | App Configuration store name | `appconfig-{uniqueString}` | No |
| `appServiceName` | App Service name | `webapp-config-{uniqueString}` | No |
| `environment` | Environment tag | `demo` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for resources | `East US` | No |
| `resource_group_name` | Name of the resource group | `rg-config-demo` | No |
| `app_config_name` | App Configuration store name | Generated | No |
| `app_service_name` | App Service name | Generated | No |
| `environment` | Environment tag | `demo` | No |

## Post-Deployment Steps

After infrastructure deployment, you'll need to deploy the ASP.NET Core application:

1. **Build the sample application**:
   ```bash
   # Create sample ASP.NET Core app (if not already created)
   dotnet new webapp --framework net8.0 --name ConfigDemoApp
   cd ConfigDemoApp
   
   # Add required packages
   dotnet add package Microsoft.Extensions.Configuration.AzureAppConfiguration
   dotnet add package Azure.Identity
   ```

2. **Deploy application to App Service**:
   ```bash
   # Build and publish
   dotnet publish --configuration Release --output ./publish
   
   # Create deployment package
   cd publish && zip -r ../deploy.zip . && cd ..
   
   # Deploy to App Service
   az webapp deployment source config-zip \
       --name <app-service-name> \
       --resource-group <resource-group-name> \
       --src deploy.zip
   ```

3. **Test the deployment**:
   ```bash
   # Get the application URL
   APP_URL=$(az webapp show --name <app-service-name> --resource-group <resource-group-name> --query defaultHostName -o tsv)
   echo "Application URL: https://${APP_URL}"
   
   # Test HTTP connectivity
   curl -I https://${APP_URL}
   ```

## Validation

### Verify Infrastructure

```bash
# Check App Configuration store
az appconfig show --name <app-config-name> --resource-group <resource-group-name>

# List configuration keys
az appconfig kv list --name <app-config-name>

# Check App Service status
az webapp show --name <app-service-name> --resource-group <resource-group-name> --query state

# Verify managed identity
az webapp identity show --name <app-service-name> --resource-group <resource-group-name>
```

### Test Dynamic Configuration

```bash
# Update a configuration value
az appconfig kv set \
    --name <app-config-name> \
    --key "DemoApp:Settings:Message" \
    --value "Configuration updated dynamically!"

# Check the web application after 30 seconds to see the change
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name <resource-group-name> --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Cost Considerations

This solution uses Azure free tier services:

- **Azure App Configuration**: Free tier (1,000 requests/day, 10MB storage)
- **App Service**: Free tier (1GB storage, 165 minutes/day compute)
- **Resource Group**: No cost

Total estimated cost: **$0/month** for development/testing scenarios within free tier limits.

For production workloads, consider:
- App Configuration Standard tier for higher limits and additional features
- App Service Basic or Standard tiers for custom domains and scaling
- Application Insights for monitoring and telemetry

## Security Features

This implementation includes security best practices:

- **Managed Identity**: Eliminates need for connection strings or access keys
- **Role-Based Access Control**: Minimal permissions (App Configuration Data Reader)
- **HTTPS Enforcement**: All web traffic encrypted in transit
- **Resource Tagging**: Proper resource organization and cost tracking

## Troubleshooting

### Common Issues

1. **Deployment fails with permissions error**:
   - Ensure your Azure account has Contributor role on the subscription
   - Check that all required resource providers are registered

2. **Application shows configuration errors**:
   - Verify managed identity is enabled and has proper role assignment
   - Check that APP_CONFIG_ENDPOINT application setting is correct

3. **Configuration values not updating**:
   - Ensure 30-second refresh interval has passed
   - Check that configuration keys exist in App Configuration store

### Debug Commands

```bash
# Check Azure CLI login status
az account show

# List resource providers
az provider list --query "[?namespace=='Microsoft.AppConfiguration']" -o table

# View App Service logs
az webapp log tail --name <app-service-name> --resource-group <resource-group-name>

# Check role assignments
az role assignment list --assignee <managed-identity-principal-id>
```

## Customization

### Environment-Specific Configurations

To customize for different environments:

1. **Update parameter files**:
   - Modify `bicep/parameters.json` for Bicep
   - Update `terraform/terraform.tfvars` for Terraform

2. **Add environment-specific configuration keys**:
   ```bash
   az appconfig kv set --name <app-config-name> --key "DemoApp:Settings:Environment" --value "Production"
   ```

3. **Scale App Service tier**:
   - Update `sku` parameter in templates for production workloads

### Additional Features

Consider extending the solution with:

- Feature flags using App Configuration's feature management
- Integration with Azure Key Vault for sensitive values
- Application Insights for monitoring and telemetry
- Custom domains and SSL certificates
- Auto-scaling rules for App Service

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation:
   - [Azure App Configuration](https://docs.microsoft.com/azure/azure-app-configuration/)
   - [Azure App Service](https://docs.microsoft.com/azure/app-service/)
3. Consult provider-specific documentation:
   - [Bicep documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)
   - [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Next Steps

After successful deployment, explore these advanced scenarios:

1. Implement feature flags for A/B testing
2. Set up multiple environments with App Configuration labels
3. Integrate with Azure DevOps for CI/CD pipelines
4. Add monitoring and alerting with Application Insights
5. Implement configuration validation and rollback strategies