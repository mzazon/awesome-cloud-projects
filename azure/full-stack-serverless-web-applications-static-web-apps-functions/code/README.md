# Infrastructure as Code for Full-Stack Serverless Web Applications with Azure Static Web Apps and Azure Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Full-Stack Serverless Web Applications with Azure Static Web Apps and Azure Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.39.0 or later installed and configured
- Azure account with active subscription
- Appropriate permissions for:
  - Creating resource groups
  - Deploying Static Web Apps
  - Creating Storage Accounts
  - Managing Azure Functions
- Node.js 18.x or later (for local development)
- Git installed and configured with GitHub account

## Architecture Overview

This infrastructure deploys a complete serverless full-stack web application consisting of:

- **Azure Static Web App**: Hosts the React frontend with global CDN distribution
- **Azure Functions**: Provides serverless backend API with HTTP triggers
- **Azure Storage Account**: Stores application data using Table Storage
- **GitHub Integration**: Automated CI/CD pipeline for continuous deployment

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the Bicep directory
cd bicep/

# Login to Azure (if not already logged in)
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-fullstack-serverless" \
    --template-file main.bicep \
    --parameters @parameters.json

# Get deployment outputs
az deployment group show \
    --resource-group "rg-fullstack-serverless" \
    --name "main" \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
az staticwebapp list --output table
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export RESOURCE_GROUP="rg-fullstack-serverless"
export LOCATION="eastus"
export STATIC_WEB_APP_NAME="swa-fullstack-app"
export STORAGE_ACCOUNT_NAME="stfullstack$(openssl rand -hex 6)"
export GITHUB_REPO_URL="https://github.com/YOUR_USERNAME/YOUR_REPO"
```

### Bicep Parameters

Edit `bicep/parameters.json` to customize your deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "staticWebAppName": {
      "value": "swa-fullstack-app"
    },
    "storageAccountName": {
      "value": "stfullstack123456"
    },
    "location": {
      "value": "eastus"
    },
    "repositoryUrl": {
      "value": "https://github.com/YOUR_USERNAME/YOUR_REPO"
    },
    "branch": {
      "value": "main"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize your deployment:

```hcl
resource_group_name     = "rg-fullstack-serverless"
location               = "eastus"
static_web_app_name    = "swa-fullstack-app"
storage_account_name   = "stfullstack123456"
repository_url         = "https://github.com/YOUR_USERNAME/YOUR_REPO"
branch                = "main"
```

## Application Structure

The deployed infrastructure supports this application structure:

```
fullstack-serverless-app/
├── src/                          # React frontend source
│   ├── components/
│   │   └── TaskManager.js
│   ├── services/
│   │   └── api.js
│   └── App.js
├── api/                          # Azure Functions backend
│   ├── tasks/
│   │   ├── index.js
│   │   └── function.json
│   └── host.json
├── staticwebapp.config.json      # Static Web Apps configuration
└── .github/workflows/            # GitHub Actions workflow
```

## Deployment Process

### 1. Infrastructure Deployment

The IaC creates:
- Resource Group for organizing resources
- Storage Account with Table Storage for data persistence
- Static Web App with GitHub integration
- Application settings for Azure Functions

### 2. Application Deployment

After infrastructure deployment:

1. **Push code to GitHub**: The Static Web App monitors your repository
2. **Automatic build**: GitHub Actions builds React frontend and Functions backend
3. **Deployment**: Built artifacts are deployed to Azure Static Web Apps
4. **Global distribution**: Content is distributed via Azure CDN

### 3. Configuration

The deployment automatically configures:
- Storage connection strings for Azure Functions
- API routing rules for frontend-backend integration
- Security headers and CORS policies
- Node.js runtime settings

## Monitoring and Troubleshooting

### Deployment Status

```bash
# Check Static Web App status
az staticwebapp show \
    --name "swa-fullstack-app" \
    --resource-group "rg-fullstack-serverless" \
    --query "{name:name,status:repositoryUrl,defaultHostname:defaultHostname}"

# Check GitHub Actions deployment
az staticwebapp deployment list \
    --name "swa-fullstack-app" \
    --resource-group "rg-fullstack-serverless"
```

### Application Logs

```bash
# View Functions logs
az staticwebapp functions show \
    --name "swa-fullstack-app" \
    --resource-group "rg-fullstack-serverless"

# Check application settings
az staticwebapp appsettings list \
    --name "swa-fullstack-app" \
    --resource-group "rg-fullstack-serverless"
```

### Common Issues

1. **GitHub Integration**: Ensure repository URL is correct and accessible
2. **Build Failures**: Check Node.js version compatibility (18.x required)
3. **API Errors**: Verify storage connection string configuration
4. **CORS Issues**: Review staticwebapp.config.json routing rules

## Testing

### Infrastructure Validation

```bash
# Test Static Web App accessibility
curl -I https://$(az staticwebapp show \
    --name "swa-fullstack-app" \
    --resource-group "rg-fullstack-serverless" \
    --query "defaultHostname" -o tsv)

# Test API endpoints
curl https://$(az staticwebapp show \
    --name "swa-fullstack-app" \
    --resource-group "rg-fullstack-serverless" \
    --query "defaultHostname" -o tsv)/api/tasks
```

### Storage Validation

```bash
# Check table creation
az storage table exists \
    --name tasks \
    --account-name "your-storage-account-name"

# List storage tables
az storage table list \
    --account-name "your-storage-account-name"
```

## Cost Optimization

### Free Tier Resources

- **Azure Static Web Apps**: Free tier includes 100GB bandwidth and custom domains
- **Azure Functions**: Consumption plan with 1 million free requests per month
- **Storage Account**: Pay-per-use pricing for Table Storage transactions

### Cost Monitoring

```bash
# View resource costs
az consumption usage list \
    --resource-group "rg-fullstack-serverless" \
    --start-date "2024-01-01" \
    --end-date "2024-01-31"

# Set up cost alerts
az monitor action-group create \
    --resource-group "rg-fullstack-serverless" \
    --name "cost-alerts" \
    --short-name "costalert"
```

## Security Considerations

### Applied Security Measures

- **HTTPS Only**: All traffic encrypted in transit
- **Storage Account**: Secure connection strings and access keys
- **CORS Configuration**: Restricted to application domains
- **Security Headers**: X-Frame-Options, X-Content-Type-Options, X-XSS-Protection

### Additional Security

```bash
# Enable Storage Account firewall
az storage account update \
    --name "your-storage-account-name" \
    --resource-group "rg-fullstack-serverless" \
    --default-action Deny

# Configure Static Web App authentication (if needed)
az staticwebapp identity assign \
    --name "swa-fullstack-app" \
    --resource-group "rg-fullstack-serverless"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name "rg-fullstack-serverless" \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group exists --name "rg-fullstack-serverless"
```

## Extending the Solution

### Add Authentication

```bash
# Configure Azure AD authentication
az staticwebapp identity assign \
    --name "swa-fullstack-app" \
    --resource-group "rg-fullstack-serverless"

# Add authentication configuration to staticwebapp.config.json
```

### Add Application Insights

```bash
# Create Application Insights resource
az monitor app-insights component create \
    --app "fullstack-app-insights" \
    --location "eastus" \
    --resource-group "rg-fullstack-serverless"

# Configure connection string
az staticwebapp appsettings set \
    --name "swa-fullstack-app" \
    --resource-group "rg-fullstack-serverless" \
    --setting-names APPLICATIONINSIGHTS_CONNECTION_STRING="your-connection-string"
```

## Support and Resources

### Documentation

- [Azure Static Web Apps Documentation](https://docs.microsoft.com/en-us/azure/static-web-apps/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Storage Tables Documentation](https://docs.microsoft.com/en-us/azure/storage/tables/)

### Troubleshooting

- [Static Web Apps Troubleshooting Guide](https://docs.microsoft.com/en-us/azure/static-web-apps/troubleshooting)
- [Azure Functions Troubleshooting](https://docs.microsoft.com/en-us/azure/azure-functions/functions-diagnostics)

### Community

- [Azure Static Web Apps GitHub](https://github.com/Azure/static-web-apps)
- [Azure Functions GitHub](https://github.com/Azure/azure-functions)

## Version History

- **1.0**: Initial infrastructure implementation
- **1.1**: Added monitoring and security enhancements
- **1.2**: Improved error handling and documentation

For issues with this infrastructure code, refer to the original recipe documentation or the Azure documentation links provided above.