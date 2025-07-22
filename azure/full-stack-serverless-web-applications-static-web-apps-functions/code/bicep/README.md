# Bicep Templates for Full-Stack Serverless Web Applications

This directory contains Bicep Infrastructure as Code (IaC) templates for deploying a full-stack serverless web application using Azure Static Web Apps and Azure Functions.

## Architecture Overview

The Bicep templates deploy the following resources:

- **Azure Static Web App**: Hosts the React frontend and provides integrated Azure Functions backend
- **Azure Storage Account**: Provides data persistence with Table Storage
- **Table Storage**: Stores task data for the application
- **Application Settings**: Configures the Static Web App with necessary environment variables

## Files Description

### Core Templates

- **`main.bicep`**: Main template that deploys all resources
- **`parameters.json`**: Example parameters for development/demo environment
- **`deploy.bicep`**: Deployment wrapper that uses the main template as a module
- **`deploy.parameters.json`**: Example parameters for production deployment
- **`README.md`**: This documentation file

### Template Features

#### Security Features
- TLS 1.2 minimum enforcement
- Blob public access disabled
- HTTPS-only traffic enforced
- Proper encryption configuration
- Secure parameter handling for GitHub tokens

#### Scalability Features
- Configurable SKUs for Static Web App and Storage Account
- Proper resource naming with unique suffixes
- Staging environment support
- Global CDN distribution through Static Web Apps

#### Monitoring and Management
- Comprehensive resource tagging
- Detailed outputs for integration
- Basic authentication for staging environments
- Application settings for Functions runtime

## Prerequisites

Before deploying these templates, ensure you have:

1. **Azure CLI** installed and configured
2. **Bicep CLI** installed (usually comes with Azure CLI)
3. **Active Azure subscription** with appropriate permissions
4. **GitHub repository** with your application code (optional for basic deployment)
5. **GitHub personal access token** (required for automated deployments)

## Quick Start

### 1. Deploy Development Environment

```bash
# Create resource group
az group create \
    --name rg-fullstack-serverless-dev \
    --location eastus

# Deploy using main template
az deployment group create \
    --resource-group rg-fullstack-serverless-dev \
    --template-file main.bicep \
    --parameters @parameters.json
```

### 2. Deploy Production Environment

```bash
# Create resource group
az group create \
    --name rg-fullstack-serverless-prod \
    --location eastus

# Deploy using deployment wrapper
az deployment group create \
    --resource-group rg-fullstack-serverless-prod \
    --template-file deploy.bicep \
    --parameters @deploy.parameters.json
```

### 3. Deploy with Inline Parameters

```bash
# Deploy with custom parameters
az deployment group create \
    --resource-group rg-fullstack-serverless \
    --template-file main.bicep \
    --parameters \
        staticWebAppName=my-custom-app \
        storageAccountName=stmycustomapp \
        repositoryUrl=https://github.com/myuser/myrepo \
        branch=main \
        staticWebAppSku=Standard
```

## Parameter Configuration

### Required Parameters

- **`staticWebAppName`**: Name for the Static Web App (must be globally unique)
- **`storageAccountName`**: Name for the Storage Account (must be globally unique)

### Optional Parameters

- **`location`**: Azure region for deployment (defaults to resource group location)
- **`repositoryUrl`**: GitHub repository URL for automated deployments
- **`branch`**: Git branch to deploy from (defaults to 'main')
- **`repositoryToken`**: GitHub personal access token (secure parameter)
- **`appLocation`**: Location of frontend app source code (defaults to '/')
- **`apiLocation`**: Location of API source code (defaults to 'api')
- **`outputLocation`**: Location of built app content (defaults to 'build')
- **`staticWebAppSku`**: SKU for Static Web App ('Free' or 'Standard')
- **`storageAccountSku`**: SKU for Storage Account (various options available)
- **`tags`**: Object containing resource tags

### Example Parameter Files

#### Development Environment
```json
{
  "staticWebAppName": { "value": "swa-fullstack-dev" },
  "storageAccountName": { "value": "stfullstackdev" },
  "staticWebAppSku": { "value": "Free" },
  "tags": {
    "value": {
      "purpose": "development",
      "environment": "dev"
    }
  }
}
```

#### Production Environment
```json
{
  "staticWebAppName": { "value": "swa-fullstack-prod" },
  "storageAccountName": { "value": "stfullstackprod" },
  "staticWebAppSku": { "value": "Standard" },
  "storageAccountSku": { "value": "Standard_GRS" },
  "tags": {
    "value": {
      "purpose": "production",
      "environment": "prod"
    }
  }
}
```

## Deployment Commands

### Basic Deployment
```bash
az deployment group create \
    --resource-group your-resource-group \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Validate Before Deployment
```bash
az deployment group validate \
    --resource-group your-resource-group \
    --template-file main.bicep \
    --parameters @parameters.json
```

### What-If Analysis
```bash
az deployment group what-if \
    --resource-group your-resource-group \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Deploy with Confirmation
```bash
az deployment group create \
    --resource-group your-resource-group \
    --template-file main.bicep \
    --parameters @parameters.json \
    --confirm-with-what-if
```

## Outputs

After successful deployment, the templates provide the following outputs:

- **`staticWebAppName`**: Name of the deployed Static Web App
- **`staticWebAppUrl`**: Full URL of the deployed application
- **`staticWebAppHostname`**: Hostname of the Static Web App
- **`storageAccountName`**: Name of the Storage Account
- **`storageConnectionString`**: Connection string for the Storage Account
- **`apiKey`**: API key for the Static Web App
- **`tasksTableName`**: Name of the tasks table in Table Storage

### Accessing Outputs
```bash
# Get deployment outputs
az deployment group show \
    --resource-group your-resource-group \
    --name your-deployment-name \
    --query properties.outputs
```

## Post-Deployment Configuration

### 1. Configure GitHub Integration

If you didn't provide a repository URL during deployment, you can configure it later:

```bash
# Set up GitHub integration
az staticwebapp environment set \
    --name your-static-web-app \
    --resource-group your-resource-group \
    --source https://github.com/your-username/your-repo
```

### 2. Update Application Settings

```bash
# Add additional application settings
az staticwebapp appsettings set \
    --name your-static-web-app \
    --resource-group your-resource-group \
    --setting-names CUSTOM_SETTING=value
```

### 3. Configure Custom Domain

```bash
# Add custom domain
az staticwebapp hostname set \
    --name your-static-web-app \
    --resource-group your-resource-group \
    --hostname your-custom-domain.com
```

## Monitoring and Troubleshooting

### View Deployment Logs
```bash
az deployment group show \
    --resource-group your-resource-group \
    --name your-deployment-name \
    --query properties.provisioningState
```

### Check Resource Status
```bash
# Check Static Web App status
az staticwebapp show \
    --name your-static-web-app \
    --resource-group your-resource-group \
    --query properties.defaultHostname

# Check Storage Account status
az storage account show \
    --name your-storage-account \
    --resource-group your-resource-group \
    --query provisioningState
```

### View Application Logs
```bash
# View Static Web App logs
az staticwebapp show \
    --name your-static-web-app \
    --resource-group your-resource-group \
    --query properties.buildProperties
```

## Cleanup

To remove all resources created by the templates:

```bash
# Delete the entire resource group
az group delete \
    --name your-resource-group \
    --yes \
    --no-wait
```

Or delete individual resources:

```bash
# Delete Static Web App
az staticwebapp delete \
    --name your-static-web-app \
    --resource-group your-resource-group \
    --yes

# Delete Storage Account
az storage account delete \
    --name your-storage-account \
    --resource-group your-resource-group \
    --yes
```

## Best Practices

### Security
- Use secure parameters for sensitive values like GitHub tokens
- Enable minimum TLS 1.2 for all resources
- Disable public blob access on Storage Accounts
- Use managed identities where possible

### Naming Conventions
- Use consistent naming patterns across environments
- Include environment indicators in resource names
- Use `uniqueString()` function for globally unique names

### Resource Organization
- Use meaningful resource groups per environment
- Apply consistent tagging strategy
- Group related resources together

### Cost Optimization
- Use Free tier for development environments
- Choose appropriate SKUs based on requirements
- Monitor usage and costs regularly

## Troubleshooting Common Issues

### Issue: Static Web App deployment fails
**Solution**: Ensure the repository URL is accessible and the GitHub token has appropriate permissions.

### Issue: Storage Account name conflict
**Solution**: Use the `uniqueString()` function or add a unique suffix to the storage account name.

### Issue: Functions not connecting to Storage
**Solution**: Verify the storage connection string is properly configured in application settings.

### Issue: GitHub Actions workflow not triggering
**Solution**: Check the repository token permissions and ensure the workflow file is in the correct location.

## Support and Resources

- [Azure Static Web Apps Documentation](https://docs.microsoft.com/en-us/azure/static-web-apps/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure CLI Reference](https://docs.microsoft.com/en-us/cli/azure/)

## License

This template is provided as-is under the MIT License. See the main repository for full license details.