# Infrastructure as Code for Progressive Web Apps with Static Hosting and CDN

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Progressive Web Apps with Static Hosting and CDN".

## Available Implementations

- **Bicep**: Azure's recommended infrastructure as code language
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login` completed)
- GitHub account for source code repository and CI/CD integration
- Node.js v18+ and npm installed locally (for PWA development)
- Appropriate Azure permissions for:
  - Resource Groups
  - Static Web Apps
  - CDN Profiles and Endpoints
  - Application Insights
  - Monitor resources
- Estimated cost: $5-15/month for small to medium traffic

## Quick Start

### Using Bicep

```bash
# Navigate to bicep directory
cd bicep/

# Create resource group
az group create --name rg-pwa-demo --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-pwa-demo \
    --template-file main.bicep \
    --parameters @parameters.json

# Get deployment outputs
az deployment group show \
    --resource-group rg-pwa-demo \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/status.sh
```

## Architecture Overview

This infrastructure deploys:

- **Azure Static Web Apps**: Serverless hosting for PWA with integrated CI/CD
- **Azure CDN**: Global content delivery network for performance optimization
- **Application Insights**: Comprehensive monitoring and analytics
- **Resource Group**: Logical container for all resources

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "appName": {
      "value": "pwa-demo"
    },
    "location": {
      "value": "eastus"
    },
    "githubRepository": {
      "value": "https://github.com/yourusername/your-pwa-repo"
    },
    "githubBranch": {
      "value": "main"
    },
    "cdnSku": {
      "value": "Standard_Microsoft"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars`:

```hcl
resource_group_name = "rg-pwa-demo"
location           = "East US"
app_name           = "pwa-demo"
github_repository  = "https://github.com/yourusername/your-pwa-repo"
github_branch      = "main"
cdn_sku           = "Standard_Microsoft"
tags = {
  Environment = "Production"
  Project     = "PWA-Demo"
}
```

### Bash Script Environment Variables

Edit environment variables in `scripts/deploy.sh`:

```bash
export APP_NAME="pwa-demo"
export LOCATION="eastus"
export GITHUB_REPOSITORY="https://github.com/yourusername/your-pwa-repo"
export GITHUB_BRANCH="main"
export CDN_SKU="Standard_Microsoft"
```

## Deployment Process

### 1. Pre-Deployment Steps

Before deploying infrastructure, prepare your PWA code:

```bash
# Create PWA project structure
mkdir pwa-demo && cd pwa-demo
mkdir -p src/{css,js,images,api}

# Initialize Git repository
git init
git remote add origin YOUR_GITHUB_REPOSITORY_URL
```

### 2. Infrastructure Deployment

Choose your preferred deployment method from the Quick Start section above.

### 3. Post-Deployment Steps

After infrastructure deployment:

```bash
# Get Static Web App deployment token (for GitHub Actions)
az staticwebapp secrets list \
    --name YOUR_SWA_NAME \
    --resource-group YOUR_RESOURCE_GROUP \
    --query "properties.apiKey"

# Configure GitHub repository secrets
# Add the deployment token as AZURE_STATIC_WEB_APPS_API_TOKEN
```

## Resource Details

### Static Web App

- **Purpose**: Hosts the PWA with automatic CI/CD from GitHub
- **Features**: 
  - Automatic HTTPS
  - Global distribution
  - Integrated serverless API
  - Custom domains support
- **Pricing**: Free tier includes 100GB bandwidth/month

### CDN Profile and Endpoint

- **Purpose**: Global content delivery for improved performance
- **Features**:
  - Edge caching
  - Compression
  - Custom caching rules
  - Global points of presence
- **Pricing**: Pay-per-use based on data transfer

### Application Insights

- **Purpose**: Comprehensive monitoring and analytics
- **Features**:
  - Real-time performance monitoring
  - User behavior analytics
  - Custom event tracking
  - Dependency tracking
- **Pricing**: Based on data ingestion volume

## Monitoring and Validation

### Health Checks

```bash
# Check Static Web App status
az staticwebapp show \
    --name YOUR_SWA_NAME \
    --resource-group YOUR_RESOURCE_GROUP \
    --query "properties.defaultHostname"

# Check CDN endpoint status
az cdn endpoint show \
    --name YOUR_CDN_ENDPOINT \
    --profile-name YOUR_CDN_PROFILE \
    --resource-group YOUR_RESOURCE_GROUP \
    --query "provisioningState"

# Check Application Insights
az monitor app-insights component show \
    --app YOUR_APP_INSIGHTS_NAME \
    --resource-group YOUR_RESOURCE_GROUP \
    --query "provisioningState"
```

### Performance Testing

```bash
# Test CDN performance
curl -I https://YOUR_CDN_ENDPOINT/manifest.json

# Test Static Web App API
curl https://YOUR_SWA_URL/api/hello

# Test PWA features in browser
# 1. Open Developer Tools > Application > Service Workers
# 2. Verify service worker registration
# 3. Test offline functionality
# 4. Check for install prompt
```

## Troubleshooting

### Common Issues

1. **GitHub Actions Deployment Failures**
   - Verify deployment token is correctly set in GitHub secrets
   - Check GitHub Actions workflow file syntax
   - Ensure proper app/api location paths

2. **CDN Caching Issues**
   - Clear CDN cache: `az cdn endpoint purge`
   - Verify caching rules configuration
   - Check origin server response headers

3. **Application Insights Not Collecting Data**
   - Verify instrumentation key configuration
   - Check JavaScript SDK initialization
   - Validate connection string format

### Logs and Diagnostics

```bash
# View Static Web App logs
az staticwebapp show \
    --name YOUR_SWA_NAME \
    --resource-group YOUR_RESOURCE_GROUP

# Query Application Insights
az monitor app-insights query \
    --app YOUR_APP_INSIGHTS_NAME \
    --analytics-query "requests | take 10" \
    --resource-group YOUR_RESOURCE_GROUP

# Check CDN diagnostics
az cdn endpoint show \
    --name YOUR_CDN_ENDPOINT \
    --profile-name YOUR_CDN_PROFILE \
    --resource-group YOUR_RESOURCE_GROUP \
    --query "optimizationType"
```

## Security Considerations

### Best Practices Implemented

- **HTTPS Enforcement**: Automatic HTTPS for all Static Web Apps
- **CDN Security**: Proper origin configuration and access controls
- **Application Insights**: Secure instrumentation key management
- **Resource Access**: Least privilege principle for all resources

### Additional Security Measures

```bash
# Enable CDN custom domain with SSL
az cdn custom-domain create \
    --endpoint-name YOUR_CDN_ENDPOINT \
    --name YOUR_CUSTOM_DOMAIN \
    --profile-name YOUR_CDN_PROFILE \
    --resource-group YOUR_RESOURCE_GROUP \
    --hostname your-custom-domain.com

# Configure CDN security policies
az cdn endpoint rule add \
    --name YOUR_CDN_ENDPOINT \
    --profile-name YOUR_CDN_PROFILE \
    --resource-group YOUR_RESOURCE_GROUP \
    --rule-name "SecurityHeaders" \
    --order 1 \
    --action-name ModifyResponseHeader \
    --header-action Append \
    --header-name "X-Content-Type-Options" \
    --header-value "nosniff"
```

## Cleanup

### Using Bicep

```bash
# Delete resource group (removes all resources)
az group delete \
    --name rg-pwa-demo \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up state files
rm -f terraform.tfstate*
rm -rf .terraform/
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group show --name rg-pwa-demo --query "properties.provisioningState"
```

## Customization

### Scaling Options

- **Static Web App**: Automatically scales based on traffic
- **CDN**: Global distribution with multiple pricing tiers
- **Application Insights**: Configurable sampling rates and retention

### Performance Optimization

```bash
# Configure CDN caching rules
az cdn endpoint rule add \
    --name YOUR_CDN_ENDPOINT \
    --profile-name YOUR_CDN_PROFILE \
    --resource-group YOUR_RESOURCE_GROUP \
    --rule-name "OptimizeCaching" \
    --order 1 \
    --match-variable RequestPath \
    --operator BeginsWith \
    --match-values "/static/" \
    --action-name CacheExpiration \
    --cache-behavior Override \
    --cache-duration 30.00:00:00
```

### Cost Optimization

- Monitor bandwidth usage through Azure Cost Management
- Configure Application Insights sampling to reduce costs
- Use CDN Standard tier for cost-effective global distribution
- Implement proper caching strategies to reduce origin requests

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../building-progressive-web-apps-with-azure-static-web-apps-and-cdn.md)
2. Refer to [Azure Static Web Apps documentation](https://docs.microsoft.com/en-us/azure/static-web-apps/)
3. Review [Azure CDN documentation](https://docs.microsoft.com/en-us/azure/cdn/)
4. Consult [Application Insights documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/app/javascript)

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate against Azure best practices
3. Update documentation accordingly
4. Submit pull requests with clear descriptions

---

**Note**: This infrastructure code is generated based on the Progressive Web Apps recipe and follows Azure best practices for security, performance, and cost optimization.