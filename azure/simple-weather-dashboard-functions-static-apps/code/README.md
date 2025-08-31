# Infrastructure as Code for Simple Weather Dashboard with Functions and Static Web Apps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Weather Dashboard with Functions and Static Web Apps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.50 or later)
- Node.js 18.x or later installed locally
- Appropriate Azure permissions for resource creation:
  - Contributor role on subscription or resource group
  - Ability to create Static Web Apps and Azure Functions
- Free OpenWeatherMap API key (register at openweathermap.org)
- Basic knowledge of HTML, JavaScript, and REST APIs

## Architecture Overview

This solution deploys:
- **Azure Static Web App**: Hosts the weather dashboard frontend (HTML/CSS/JavaScript)
- **Azure Functions**: Provides serverless API backend integrated with Static Web Apps
- **Application Settings**: Securely stores OpenWeatherMap API key
- **Resource Group**: Contains all related resources with proper tagging

The architecture provides:
- Automatic HTTPS with SSL certificates
- Global CDN distribution
- Serverless scaling based on demand
- Integrated Functions API without CORS complexity
- Free tier eligibility for cost optimization

## Quick Start

### Using Bicep (Recommended for Azure)

1. **Deploy the infrastructure**:
   ```bash
   # Clone or navigate to the bicep directory
   cd bicep/
   
   # Set deployment parameters
   export RESOURCE_GROUP="rg-weather-dashboard-$(openssl rand -hex 3)"
   export LOCATION="eastus"
   export APP_NAME="weather-app-$(openssl rand -hex 3)"
   
   # Create resource group
   az group create --name ${RESOURCE_GROUP} --location ${LOCATION}
   
   # Deploy infrastructure
   az deployment group create \
       --resource-group ${RESOURCE_GROUP} \
       --template-file main.bicep \
       --parameters appName=${APP_NAME} location=${LOCATION}
   ```

2. **Configure API key**:
   ```bash
   # Add your OpenWeatherMap API key
   read -p "Enter your OpenWeatherMap API key: " WEATHER_API_KEY
   
   az staticwebapp appsettings set \
       --name ${APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --setting-names OPENWEATHER_API_KEY="${WEATHER_API_KEY}"
   ```

3. **Deploy application code**:
   ```bash
   # Navigate to parent directory with src/ and api/ folders
   cd ..
   
   # Deploy to Static Web App (requires Azure Static Web Apps CLI)
   npm install -g @azure/static-web-apps-cli
   swa deploy --app-location ./src --api-location ./api
   ```

### Using Terraform

1. **Initialize and deploy**:
   ```bash
   cd terraform/
   
   # Initialize Terraform
   terraform init
   
   # Review planned changes
   terraform plan -var="app_name=weather-app-$(openssl rand -hex 3)"
   
   # Deploy infrastructure
   terraform apply -var="app_name=weather-app-$(openssl rand -hex 3)"
   ```

2. **Configure API key**:
   ```bash
   # Get the app name from Terraform outputs
   export APP_NAME=$(terraform output -raw static_web_app_name)
   export RESOURCE_GROUP=$(terraform output -raw resource_group_name)
   
   # Add your OpenWeatherMap API key
   read -p "Enter your OpenWeatherMap API key: " WEATHER_API_KEY
   
   az staticwebapp appsettings set \
       --name ${APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --setting-names OPENWEATHER_API_KEY="${WEATHER_API_KEY}"
   ```

### Using Bash Scripts

1. **Deploy with automated script**:
   ```bash
   cd scripts/
   
   # Make scripts executable
   chmod +x deploy.sh destroy.sh
   
   # Run deployment script
   ./deploy.sh
   ```

   The script will:
   - Prompt for required parameters
   - Create all Azure resources
   - Configure application settings
   - Provide deployment status and URLs

## Application Deployment

After infrastructure deployment, deploy your application code:

1. **Prepare application files**:
   ```bash
   # Ensure you have the following structure:
   # src/
   # ├── index.html
   # ├── styles.css
   # └── app.js
   # api/
   # ├── weather.js
   # ├── package.json
   # └── host.json
   ```

2. **Deploy to Static Web App**:
   ```bash
   # Option 1: Using Azure CLI (if supported)
   az staticwebapp environment create \
       --name ${APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --source ./
   
   # Option 2: Using SWA CLI (recommended)
   npx @azure/static-web-apps-cli deploy \
       --app-location ./src \
       --api-location ./api \
       --resource-group ${RESOURCE_GROUP} \
       --app-name ${APP_NAME}
   ```

## Configuration Options

### Bicep Parameters

- `appName`: Name for the Static Web App (must be globally unique)
- `location`: Azure region for deployment (default: eastus)
- `sku`: Static Web App pricing tier (default: Free)
- `tags`: Resource tags for organization and cost tracking

### Terraform Variables

- `app_name`: Name for the Static Web App (must be globally unique)
- `location`: Azure region for deployment (default: East US)
- `resource_group_name`: Resource group name (auto-generated if not specified)
- `environment`: Environment tag (default: demo)

### Environment Variables

Set these variables before deployment:

```bash
export RESOURCE_GROUP="your-resource-group-name"
export LOCATION="eastus"
export APP_NAME="your-unique-app-name"
export WEATHER_API_KEY="your-openweathermap-api-key"
```

## Validation & Testing

1. **Verify infrastructure deployment**:
   ```bash
   # Check Static Web App status
   az staticwebapp show \
       --name ${APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --query "{name:name,url:defaultHostname,status:repositoryUrl}"
   ```

2. **Test API functionality**:
   ```bash
   # Get the app URL
   export SWA_URL=$(az staticwebapp show \
       --name ${APP_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --query "defaultHostname" -o tsv)
   
   # Test weather API
   curl "https://${SWA_URL}/api/weather?city=London" \
       -H "Accept: application/json"
   ```

3. **Access the application**:
   ```bash
   echo "🌤️ Open your weather dashboard at: https://${SWA_URL}"
   ```

## Monitoring and Troubleshooting

### Application Insights Integration

Azure Static Web Apps automatically integrates with Application Insights for monitoring:

```bash
# View application metrics
az monitor app-insights component show \
    --app ${APP_NAME} \
    --resource-group ${RESOURCE_GROUP}

# Query logs
az monitor app-insights query \
    --app ${APP_NAME} \
    --analytics-query "requests | limit 10"
```

### Common Issues

1. **API Key Not Working**: Verify the API key is set correctly in application settings
2. **CORS Issues**: Static Web Apps automatically handles CORS for integrated Functions
3. **Function Not Loading**: Check function app logs and ensure proper package.json configuration
4. **City Not Found**: Verify OpenWeatherMap API key has appropriate permissions

### Logs and Diagnostics

```bash
# Enable logging
az staticwebapp environment set \
    --name ${APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --environment-name default \
    --settings "AZURE_FUNCTIONS_ENVIRONMENT=Development"

# View function logs
az staticwebapp functions show \
    --name ${APP_NAME} \
    --resource-group ${RESOURCE_GROUP}
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group and all resources
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait

echo "✅ Resource group deletion initiated: ${RESOURCE_GROUP}"
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve

echo "✅ Infrastructure destroyed"
```

### Using Bash Scripts
```bash
cd scripts/
./destroy.sh

# Follow prompts to confirm resource deletion
```

## Cost Optimization

This solution is designed for cost efficiency:

- **Free Tier Eligible**: Azure Static Web Apps and Azure Functions both offer generous free tiers
- **Consumption-Based**: Functions only charge for actual execution time
- **No Always-On Costs**: Static sites and serverless functions scale to zero when not in use
- **Estimated Monthly Cost**: $0-2 for typical usage patterns

### Cost Management

```bash
# Set up budget alerts (optional)
az consumption budget create \
    --resource-group ${RESOURCE_GROUP} \
    --budget-name "weather-dashboard-budget" \
    --amount 10 \
    --time-grain Monthly \
    --start-date $(date -d "first day of this month" +%Y-%m-%d) \
    --end-date $(date -d "first day of next month + 1 year" +%Y-%m-%d)
```

## Security Considerations

This implementation follows Azure security best practices:

- **HTTPS Everywhere**: Automatic SSL certificates and HTTPS enforcement
- **Managed Identity**: Functions use managed identity where possible
- **Secret Management**: API keys stored securely in application settings
- **Network Security**: Static Web Apps provide built-in DDoS protection
- **Access Control**: Functions can be configured with authentication if needed

### Security Best Practices

1. **API Key Rotation**: Regularly rotate your OpenWeatherMap API key
2. **Rate Limiting**: Consider implementing rate limiting for production use
3. **Input Validation**: The Function includes input validation for city names
4. **Error Handling**: Comprehensive error handling prevents information disclosure

## Customization

### Adding Custom Domains

```bash
# Add custom domain to Static Web App
az staticwebapp hostname set \
    --name ${APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --hostname "weather.yourdomain.com"
```

### Scaling Configuration

```bash
# Configure Function app settings for performance
az staticwebapp appsettings set \
    --name ${APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --setting-names \
        "FUNCTIONS_WORKER_RUNTIME=node" \
        "WEBSITE_NODE_DEFAULT_VERSION=~18" \
        "FUNCTIONS_EXTENSION_VERSION=~4"
```

### Environment-Specific Deployments

Create separate environments for development, staging, and production:

```bash
# Deploy to different environments
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file main.bicep \
    --parameters appName=${APP_NAME}-dev environment=development

az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file main.bicep \
    --parameters appName=${APP_NAME}-prod environment=production
```

## Support and Documentation

- **Azure Static Web Apps**: [Official Documentation](https://docs.microsoft.com/en-us/azure/static-web-apps/)
- **Azure Functions**: [Node.js v4 Developer Guide](https://docs.microsoft.com/en-us/azure/azure-functions/functions-reference-node)
- **OpenWeatherMap API**: [API Documentation](https://openweathermap.org/api)
- **Azure CLI Reference**: [Static Web Apps Commands](https://docs.microsoft.com/en-us/cli/azure/staticwebapp)

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.

## Advanced Features

### CI/CD Integration

Connect with GitHub for automatic deployments:

```bash
# Link Static Web App to GitHub repository
az staticwebapp create \
    --name ${APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --source "https://github.com/yourusername/weather-dashboard" \
    --branch "main" \
    --app-location "/src" \
    --api-location "/api" \
    --token ${GITHUB_TOKEN}
```

### Authentication Integration

Add user authentication:

```bash
# Configure authentication providers
az staticwebapp identity assign \
    --name ${APP_NAME} \
    --resource-group ${RESOURCE_GROUP}

# Add Azure AD authentication
az staticwebapp identity show \
    --name ${APP_NAME} \
    --resource-group ${RESOURCE_GROUP}
```

### Performance Optimization

Optimize for production workloads:

```bash
# Enable Application Insights
az staticwebapp appsettings set \
    --name ${APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --setting-names \
        "APPINSIGHTS_INSTRUMENTATIONKEY=${INSTRUMENTATION_KEY}" \
        "APPLICATIONINSIGHTS_CONNECTION_STRING=${CONNECTION_STRING}"
```

This comprehensive IaC implementation provides a solid foundation for deploying and managing your weather dashboard application on Azure with best practices for security, performance, and cost optimization.