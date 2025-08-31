# Infrastructure as Code for Simple Store Locator with Azure Maps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Store Locator with Azure Maps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM templates with simplified syntax)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login` completed)
- Appropriate Azure subscription with permissions to create:
  - Resource Groups
  - Azure Maps accounts
- For Terraform: Terraform CLI installed (version >= 1.0)
- For Bicep: Azure CLI with Bicep extension installed
- Basic knowledge of web development (HTML, CSS, JavaScript)
- Text editor for customizing store locations

## Quick Start

### Using Bicep

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-storemaps-demo \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters mapsAccountName=mapstore$(date +%s)

# Get the Azure Maps key for your application
az maps account keys list \
    --resource-group rg-storemaps-demo \
    --account-name <your-maps-account-name> \
    --query primaryKey \
    --output tsv
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply

# Get output values (including Azure Maps key)
terraform output azure_maps_key
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output the Azure Maps key and setup instructions
```

## Architecture Overview

This infrastructure creates:

1. **Resource Group**: Container for all Azure Maps resources
2. **Azure Maps Account**: Gen2 pricing tier with enterprise-grade mapping services
3. **Configuration**: Proper authentication setup for web application integration

The infrastructure supports:
- Interactive mapping with clustering
- Search functionality
- Geolocation services
- Mobile-responsive design
- Up to 1,000 free monthly transactions

## Configuration Options

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `eastus` | Azure region for resource deployment |
| `mapsAccountName` | string | `mapstore{uniqueString}` | Name for Azure Maps account |
| `resourceGroupName` | string | `rg-storemaps-demo` | Resource group name |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `location` | string | `East US` | Azure region for resources |
| `resource_group_name` | string | `rg-storemaps-demo` | Resource group name |
| `maps_account_name` | string | `mapstore{random}` | Azure Maps account name |
| `tags` | map | `{}` | Tags to apply to resources |

### Environment Variables (Bash Scripts)

| Variable | Description |
|----------|-------------|
| `AZURE_LOCATION` | Azure region (default: eastus) |
| `RESOURCE_GROUP` | Resource group name |
| `MAPS_ACCOUNT_NAME` | Azure Maps account name |

## Post-Deployment Setup

After deploying the infrastructure, complete these steps:

1. **Create the Web Application**:

   ```bash
   # Create project directory
   mkdir store-locator && cd store-locator
   
   # Create store data file
   curl -o stores.json https://raw.githubusercontent.com/example/store-data.json
   
   # Create HTML, CSS, and JavaScript files (see recipe for full code)
   ```

2. **Configure Azure Maps Authentication**:

   ```bash
   # Get your Azure Maps key
   MAPS_KEY=$(az maps account keys list \
       --resource-group <your-resource-group> \
       --account-name <your-maps-account> \
       --query primaryKey \
       --output tsv)
   
   # Update app.js with your key
   sed -i "s/YOUR_AZURE_MAPS_KEY/${MAPS_KEY}/g" app.js
   ```

3. **Test the Application**:

   ```bash
   # Start local development server
   python3 -m http.server 8000
   
   # Open browser to http://localhost:8000
   ```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-storemaps-demo \
    --yes \
    --no-wait
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

- **Azure Maps Gen2**: Includes 1,000 free monthly transactions
- **Resource Group**: No cost for the container itself
- **Storage**: Minimal cost for storing map tiles in browser cache

**Estimated Monthly Cost**: $0 for development/small applications within free tier limits.

For production applications exceeding 1,000 monthly transactions, review [Azure Maps pricing](https://azure.microsoft.com/en-us/pricing/details/azure-maps/).

## Security Best Practices

The infrastructure implements several security measures:

1. **Subscription Key Authentication**: Secure access to Azure Maps services
2. **Resource Tagging**: Proper resource identification and management
3. **Least Privilege**: Minimal permissions required for operation
4. **Gen2 Security Features**: Enhanced security compared to deprecated Gen1 tiers

### Production Security Recommendations

For production deployments:

1. **Use Microsoft Entra ID Authentication**: Replace subscription keys with Azure AD authentication
2. **Implement CORS Policies**: Restrict map access to specific domains
3. **Enable Logging**: Use Azure Monitor for usage tracking and security monitoring
4. **Use Key Vault**: Store sensitive configuration in Azure Key Vault

## Troubleshooting

### Common Issues

1. **Maps Not Loading**:
   - Verify Azure Maps key is correctly configured
   - Check browser console for authentication errors
   - Ensure subscription has active status

2. **Search Not Working**:
   - Confirm Azure Maps Search API is enabled
   - Check transaction limits in Azure portal
   - Verify network connectivity

3. **Geolocation Issues**:
   - Ensure HTTPS is used for geolocation API access
   - Check browser permissions for location access
   - Verify fallback search functionality

### Validation Commands

```bash
# Check Azure Maps account status
az maps account show \
    --resource-group <resource-group-name> \
    --account-name <maps-account-name>

# Verify subscription key
az maps account keys list \
    --resource-group <resource-group-name> \
    --account-name <maps-account-name>

# Test API access
curl -X GET "https://atlas.microsoft.com/search/address/json?api-version=1.0&subscription-key=<your-key>&query=Seattle"
```

## Customization

### Adding Your Store Locations

1. **Update stores.json**:
   ```json
   [
     {
       "name": "Your Store Name",
       "address": "123 Your Street, City, State ZIP",
       "phone": "(555) 123-4567",
       "hours": "Mon-Fri 9:00AM-6:00PM",
       "latitude": 47.6062,
       "longitude": -122.3321,
       "services": ["Service1", "Service2"]
     }
   ]
   ```

2. **Modify Map Center**:
   Update the `center` coordinates in `app.js` to focus on your primary business area.

3. **Customize Styling**:
   Modify `styles.css` to match your brand colors and typography.

4. **Add Features**:
   Extend the JavaScript to include additional functionality like directions, store hours validation, or inventory integration.

### Integration Options

- **Azure Cosmos DB**: Store dynamic store information
- **Azure Functions**: Server-side store management APIs  
- **Azure Static Web Apps**: Host the complete application with CI/CD
- **Azure Application Insights**: Monitor application usage and performance

## Support

- **Recipe Documentation**: Refer to the original recipe for detailed implementation guidance
- **Azure Maps Documentation**: [https://docs.microsoft.com/en-us/azure/azure-maps/](https://docs.microsoft.com/en-us/azure/azure-maps/)
- **Azure Support**: Use Azure portal support options for infrastructure issues
- **Community**: Azure Maps community forums and Stack Overflow

## Version Information

- **Recipe Version**: 1.1
- **Azure Maps SDK**: Web SDK v3
- **Bicep**: Latest stable version
- **Terraform Azure Provider**: ~> 3.0
- **Last Updated**: 2025-07-12

For the most current versions and updates, check the [Azure Maps release notes](https://docs.microsoft.com/en-us/azure/azure-maps/release-notes) and respective tool documentation.