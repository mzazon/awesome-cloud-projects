# Infrastructure as Code for Simple Service Status Page with Static Web Apps and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Service Status Page with Static Web Apps and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (Bicep DSL)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Azure CLI installed and configured (version 2.29.0 or later)
- Azure subscription with appropriate permissions for Static Web Apps and Functions
- Node.js v18+ for local development and testing
- Git (for deployment workflows)

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension installed
- Azure PowerShell (optional, for advanced scenarios)

#### For Terraform
- Terraform installed (version 1.0 or later)
- Azure CLI authenticated with appropriate subscription

#### For Bash Scripts
- bash shell environment
- curl and jq utilities for testing
- npm and Static Web Apps CLI for deployment

### Required Permissions
- Contributor role on the target resource group
- Static Web Apps Contributor role
- Application Insights Contributor role (if monitoring is enabled)

## Quick Start

### Using Bicep
```bash
# Navigate to Bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters \
        appName=status-page-demo \
        location=eastus

# Get deployment outputs
az deployment group show \
    --resource-group <your-resource-group> \
    --name main \
    --query properties.outputs
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="resource_group_name=<your-resource-group>" \
               -var="location=eastus" \
               -var="app_name=status-page-demo"

# Apply the configuration
terraform apply -var="resource_group_name=<your-resource-group>" \
                -var="location=eastus" \
                -var="app_name=status-page-demo"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export RESOURCE_GROUP="rg-status-page-demo"
export LOCATION="eastus"
export APP_NAME="status-page-demo"

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
az staticwebapp list --resource-group $RESOURCE_GROUP --output table
```

## Configuration Options

### Bicep Parameters
- `appName`: Name prefix for all resources (default: "status-page")
- `location`: Azure region for resource deployment (default: "eastus")
- `sku`: Static Web Apps SKU tier (default: "Free")
- `environment`: Environment tag value (default: "demo")

### Terraform Variables
- `resource_group_name`: Target resource group name (required)
- `location`: Azure region for deployment (default: "East US")
- `app_name`: Application name prefix (default: "status-page")
- `tags`: Resource tags (default: environment=demo)

### Environment Variables (Bash Scripts)
- `RESOURCE_GROUP`: Target resource group name
- `LOCATION`: Azure region (default: "eastus")
- `APP_NAME`: Application name prefix
- `SUBSCRIPTION_ID`: Azure subscription ID (auto-detected if not set)

## Deployment Architecture

The infrastructure creates the following Azure resources:

1. **Azure Static Web App**
   - Hosts the frontend status dashboard
   - Provides managed Azure Functions API integration
   - Includes global CDN distribution
   - Configured with custom routing rules

2. **Managed Azure Functions** (integrated with Static Web Apps)
   - HTTP-triggered function for service status checks
   - Node.js 18 runtime environment
   - Automatic scaling based on demand

3. **Resource Group** (if created by scripts)
   - Contains all recipe resources
   - Tagged for identification and cost management

## Application Code Structure

The deployment expects the following code structure:

```
project-root/
├── public/
│   ├── index.html              # Frontend status dashboard
│   └── staticwebapp.config.json # Static Web Apps configuration
└── api/
    ├── src/functions/
    │   └── status.js           # Service monitoring function
    ├── host.json               # Functions host configuration
    └── package.json            # Node.js dependencies
```

## Post-Deployment Steps

1. **Deploy Application Code**:
   ```bash
   # Install Static Web Apps CLI
   npm install -g @azure/static-web-apps-cli

   # Get deployment token
   DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
       --name <your-app-name> \
       --resource-group <your-resource-group> \
       --query "properties.apiKey" --output tsv)

   # Deploy application
   swa deploy ./public \
       --api-location ./api \
       --deployment-token $DEPLOYMENT_TOKEN
   ```

2. **Verify Deployment**:
   ```bash
   # Get application URL
   APP_URL=$(az staticwebapp show \
       --name <your-app-name> \
       --resource-group <your-resource-group> \
       --query "defaultHostname" --output tsv)

   # Test API endpoint
   curl "https://$APP_URL/api/status" | jq '.'
   ```

## Monitoring and Troubleshooting

### View Static Web App Logs
```bash
# Stream function logs (requires Application Insights integration)
az monitor app-insights query \
    --app <app-insights-name> \
    --analytics-query "requests | where name contains 'status'"
```

### Check Deployment Status
```bash
# Check Static Web App status
az staticwebapp show \
    --name <your-app-name> \
    --resource-group <your-resource-group> \
    --query "{name:name, status:repositoryUrl, defaultHostname:defaultHostname}"
```

### Common Issues

1. **Function Runtime Errors**: Check `host.json` configuration and Node.js version compatibility
2. **API Routing Issues**: Verify `staticwebapp.config.json` routing rules
3. **CORS Problems**: Static Web Apps handles CORS automatically for `/api/*` routes
4. **Deployment Failures**: Ensure deployment token is valid and not expired

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <your-resource-group> \
    --yes \
    --no-wait
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy -var="resource_group_name=<your-resource-group>" \
                  -var="location=eastus" \
                  -var="app_name=status-page-demo"
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az staticwebapp list --resource-group $RESOURCE_GROUP --output table
```

## Customization

### Adding Services to Monitor

Edit the `SERVICES` array in `api/src/functions/status.js`:

```javascript
const SERVICES = [
    { name: 'Your API', url: 'https://api.yourservice.com/health' },
    { name: 'Database', url: 'https://db.yourservice.com/status' },
    // Add more services as needed
];
```

### Modifying Check Intervals

Update the JavaScript timer in `public/index.html`:

```javascript
// Change from 30 seconds to desired interval
setInterval(loadStatus, 60000); // 60 seconds
```

### Custom Styling

Modify the CSS in `public/index.html` to match your organization's branding:

```css
/* Update colors, fonts, and layout */
.status.operational { background: #your-brand-color; }
```

## Security Considerations

- **Anonymous Access**: The API endpoint allows anonymous access for public status visibility
- **Rate Limiting**: Azure Static Web Apps includes built-in DDoS protection
- **HTTPS Only**: All traffic is automatically encrypted with managed SSL certificates
- **No Secrets**: The application doesn't store sensitive configuration data

## Cost Optimization

- **Free Tier**: Uses Azure Static Web Apps free tier with generous limits
- **Serverless**: Functions scale to zero when not in use
- **CDN Included**: Global distribution with no additional CDN costs
- **No Database**: Uses in-memory status checks to minimize ongoing costs

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure Static Web Apps documentation: https://docs.microsoft.com/azure/static-web-apps/
3. Consult Azure Functions documentation: https://docs.microsoft.com/azure/azure-functions/
4. Verify Azure CLI version and authentication status

## Additional Resources

- [Azure Static Web Apps Overview](https://docs.microsoft.com/azure/static-web-apps/overview)
- [Azure Functions JavaScript Developer Guide](https://docs.microsoft.com/azure/azure-functions/functions-reference-node)
- [Static Web Apps CLI Documentation](https://azure.github.io/static-web-apps-cli/)
- [Bicep Language Documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)