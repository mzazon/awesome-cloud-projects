# Infrastructure as Code for Simple Website Hosting with Static Web Apps and CLI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Website Hosting with Static Web Apps and CLI".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Azure account with active subscription
- Azure CLI installed and configured (version 2.29.0 or higher)
- Appropriate permissions for creating Azure Static Web Apps and Resource Groups
- Basic understanding of static web development (HTML/CSS/JavaScript)

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension (automatically included in recent versions)
- PowerShell or Bash shell environment

#### For Terraform
- Terraform installed (version 1.0+)
- Azure CLI authenticated with your subscription

#### For Bash Scripts
- Bash shell environment (Linux, macOS, or WSL on Windows)
- Node.js installed (version 16+) for Static Web Apps CLI
- Static Web Apps CLI (`npm install -g @azure/static-web-apps-cli@latest`)

## Architecture Overview

This infrastructure deploys:
- Azure Static Web App resource with global CDN distribution
- Automatic SSL certificate provisioning
- Security headers and performance optimization
- Global content delivery through Azure's edge network

**Estimated Cost**: Free tier provides 100GB bandwidth and global hosting at no cost.

## Quick Start

### Using Bicep (Recommended for Azure)

Deploy the infrastructure:

```bash
# Set deployment parameters
export LOCATION="eastus"
export DEPLOYMENT_NAME="swa-deployment-$(date +%s)"

# Deploy using Azure CLI
az deployment sub create \
    --location $LOCATION \
    --template-file bicep/main.bicep \
    --name $DEPLOYMENT_NAME \
    --parameters location=$LOCATION
```

Deploy your website content:

```bash
# Get the Static Web App details
RESOURCE_GROUP=$(az deployment sub show --name $DEPLOYMENT_NAME --query 'properties.outputs.resourceGroupName.value' -o tsv)
STATIC_WEB_APP_NAME=$(az deployment sub show --name $DEPLOYMENT_NAME --query 'properties.outputs.staticWebAppName.value' -o tsv)

# Deploy website content using SWA CLI
swa deploy ./website \
    --env production \
    --resource-group $RESOURCE_GROUP \
    --app-name $STATIC_WEB_APP_NAME
```

### Using Terraform

Initialize and deploy:

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Deploy website content (after infrastructure is created)
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
STATIC_WEB_APP_NAME=$(terraform output -raw static_web_app_name)

swa deploy ./website \
    --env production \
    --resource-group $RESOURCE_GROUP \
    --app-name $STATIC_WEB_APP_NAME
```

### Using Bash Scripts

Execute the deployment script:

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment
./scripts/deploy.sh

# Follow prompts to configure your deployment
# The script will create resources and deploy sample content
```

## Website Content Structure

Your website should follow this structure in the deployment directory:

```
website/
├── index.html                 # Main page
├── styles.css                # Styling
├── script.js                 # JavaScript functionality
└── staticwebapp.config.json  # Azure Static Web Apps configuration
```

### Sample Configuration (staticwebapp.config.json)

```json
{
  "navigationFallback": {
    "rewrite": "/index.html"
  },
  "routes": [
    {
      "route": "/",
      "serve": "/index.html",
      "statusCode": 200
    },
    {
      "route": "/*.{css,js,png,jpg,jpeg,gif,svg,ico}",
      "headers": {
        "cache-control": "public, max-age=31536000, immutable"
      }
    }
  ],
  "responseOverrides": {
    "404": {
      "rewrite": "/index.html"
    }
  },
  "globalHeaders": {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "X-XSS-Protection": "1; mode=block",
    "Strict-Transport-Security": "max-age=31536000; includeSubDomains"
  }
}
```

## Validation & Testing

After deployment, verify your Static Web App:

```bash
# Get the deployed URL
# For Bicep:
STATIC_WEB_APP_URL=$(az deployment sub show --name $DEPLOYMENT_NAME --query 'properties.outputs.staticWebAppUrl.value' -o tsv)

# For Terraform:
STATIC_WEB_APP_URL=$(terraform output -raw static_web_app_url)

# Test the deployment
echo "Testing deployment at: https://$STATIC_WEB_APP_URL"
curl -I "https://$STATIC_WEB_APP_URL"

# Verify SSL certificate
echo | openssl s_client -servername $STATIC_WEB_APP_URL -connect $STATIC_WEB_APP_URL:443 2>/dev/null | openssl x509 -noout -dates

# Check security headers
curl -sI "https://$STATIC_WEB_APP_URL" | grep -E "(X-|Strict-Transport)"
```

## Customization

### Bicep Parameters

Customize the deployment by modifying parameters in `bicep/main.bicep`:

- `staticWebAppName`: Name for your Static Web App
- `location`: Azure region for deployment
- `tags`: Resource tags for organization

### Terraform Variables

Edit `terraform/variables.tf` to customize:

- `static_web_app_name`: Name for your Static Web App
- `location`: Azure region for deployment
- `resource_group_name`: Custom resource group name
- `tags`: Resource tags for organization

### Bash Script Configuration

Modify variables at the top of `scripts/deploy.sh`:

- `LOCATION`: Preferred Azure region
- `RESOURCE_PREFIX`: Prefix for resource naming
- `TAGS`: Resource tags for cost management

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
RESOURCE_GROUP=$(az deployment sub show --name $DEPLOYMENT_NAME --query 'properties.outputs.resourceGroupName.value' -o tsv)
az group delete --name $RESOURCE_GROUP --yes --no-wait

echo "✅ Cleanup initiated for resource group: $RESOURCE_GROUP"
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

## Advanced Configuration

### Custom Domain Setup

After deployment, configure a custom domain:

```bash
# Add custom domain to Static Web App
az staticwebapp hostname set \
    --name $STATIC_WEB_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --hostname "www.yourdomain.com"

# Configure DNS records as shown in Azure portal
```

### Environment Variables

Set environment-specific configurations:

```bash
# Production environment
export AZURE_ENVIRONMENT="production"
export ENABLE_MONITORING="true"
export CUSTOM_DOMAIN="www.yourdomain.com"

# Development environment
export AZURE_ENVIRONMENT="development"
export ENABLE_MONITORING="false"
```

### CI/CD Integration

For automated deployments, integrate with GitHub Actions:

```yaml
# .github/workflows/deploy.yml
name: Deploy to Azure Static Web Apps
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Deploy to Azure Static Web Apps
        uses: Azure/static-web-apps-deploy@v1
        with:
          azure_static_web_apps_api_token: ${{ secrets.AZURE_STATIC_WEB_APPS_API_TOKEN }}
          repo_token: ${{ secrets.GITHUB_TOKEN }}
          action: "upload"
          app_location: "/"
```

## Monitoring and Maintenance

### Performance Monitoring

Monitor your Static Web App performance:

```bash
# View deployment logs
az staticwebapp logs show \
    --name $STATIC_WEB_APP_NAME \
    --resource-group $RESOURCE_GROUP

# Check resource usage
az monitor metrics list \
    --resource "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/staticSites/$STATIC_WEB_APP_NAME" \
    --metric "Requests"
```

### Security Updates

Regular maintenance tasks:

1. Update Static Web Apps CLI: `npm update -g @azure/static-web-apps-cli`
2. Review security headers configuration
3. Monitor SSL certificate auto-renewal
4. Check for Azure service updates

## Troubleshooting

### Common Issues

**Deployment fails with authentication error:**
```bash
# Re-authenticate with Azure
az login
az account set --subscription "your-subscription-id"
```

**SWA CLI deployment fails:**
```bash
# Clear authentication cache
swa logout
swa login --resource-group $RESOURCE_GROUP --app-name $STATIC_WEB_APP_NAME
```

**Static Web App not accessible:**
```bash
# Check resource status
az staticwebapp show \
    --name $STATIC_WEB_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "{status:state,url:defaultHostname}"
```

### Getting Help

- [Azure Static Web Apps Documentation](https://docs.microsoft.com/en-us/azure/static-web-apps/)
- [Static Web Apps CLI Documentation](https://azure.github.io/static-web-apps-cli/)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Support

For issues with this infrastructure code, refer to:

1. The original recipe documentation in the parent directory
2. Azure Static Web Apps troubleshooting guides
3. Provider-specific documentation (Bicep, Terraform)
4. Azure support channels for service-specific issues

## Cost Optimization

### Free Tier Limits

Azure Static Web Apps Free tier includes:
- 100GB bandwidth per month
- 250MB storage per app
- Custom domains with SSL
- Global CDN distribution
- Built-in authentication

### Monitoring Costs

```bash
# Check current usage against free tier limits
az staticwebapp usage show \
    --name $STATIC_WEB_APP_NAME \
    --resource-group $RESOURCE_GROUP

# Set up billing alerts
az monitor action-group create \
    --name "static-web-app-alerts" \
    --resource-group $RESOURCE_GROUP \
    --short-name "swa-alerts"
```

## Security Best Practices

This implementation follows Azure security best practices:

- Automatic HTTPS enforcement
- Security headers (HSTS, X-Frame-Options, CSP)
- Azure-managed SSL certificates
- Global WAF protection through Azure CDN
- Least privilege access controls

Review and customize security settings based on your requirements.