# Bicep Template: Basic Database Web App with SQL Database and App Service

This Bicep template deploys a complete web application infrastructure on Azure, including:

- Azure SQL Database with logical server
- Azure App Service with Basic tier hosting plan
- System-assigned managed identity for secure authentication
- Firewall rules for Azure service connectivity
- Database schema initialization with sample data
- Secure connection string configuration

## Architecture

The template creates a production-ready infrastructure following Azure best practices:

- **Azure SQL Database**: Managed database service with automatic backups and security features
- **Azure App Service**: Fully managed web hosting platform with built-in scaling and monitoring
- **Managed Identity**: Secure authentication between services without storing credentials
- **Network Security**: Firewall rules restricting database access to Azure services only

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with appropriate permissions
- Resource group creation permissions
- SQL Database and App Service creation permissions

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | Resource Group Location | Azure region for resource deployment |
| `uniqueSuffix` | string | Auto-generated | Unique suffix for globally unique resource names |
| `resourceNamePrefix` | string | webapp-demo | Prefix for all resource names |
| `sqlDatabaseName` | string | TasksDB | Name of the SQL database |
| `sqlAdminUsername` | string | sqladmin | SQL Server administrator username |
| `sqlAdminPassword` | securestring | *Required* | SQL Server administrator password |
| `sqlDatabaseSku` | string | Basic | SQL Database pricing tier (Basic, S0, S1, S2) |
| `appServicePlanSku` | string | B1 | App Service Plan pricing tier (B1, B2, B3, S1, S2, S3) |
| `dotnetVersion` | string | v8.0 | .NET runtime version for the web application |
| `tags` | object | See template | Resource tags for organization and cost tracking |

## Quick Deployment

### 1. Clone or download the template files

```bash
# Ensure you have the template files
# - main.bicep
# - parameters.json
```

### 2. Customize parameters

Edit the `parameters.json` file and update the following required values:

```json
{
  "sqlAdminPassword": {
    "value": "YourSecurePassword123!"
  },
  "location": {
    "value": "East US"
  }
}
```

**Important**: Replace `REPLACE_WITH_SECURE_PASSWORD_SecurePass123!` with a strong password that meets Azure SQL Database requirements:
- At least 8 characters
- Contains uppercase and lowercase letters
- Contains numbers
- Contains special characters

### 3. Create resource group and deploy

```bash
# Set variables
RESOURCE_GROUP="rg-webapp-demo-$(openssl rand -hex 3)"
LOCATION="eastus"

# Create resource group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

# Deploy the Bicep template
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters @parameters.json
```

### 4. Alternative: Deploy with inline parameters

```bash
# Deploy with parameters specified directly
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters \
    sqlAdminPassword='YourSecurePassword123!' \
    location='eastus' \
    resourceNamePrefix='myapp'
```

## Post-Deployment Steps

After successful deployment:

1. **Access the web application**: Use the `webAppUrl` output value to access your deployed application
2. **Verify database connectivity**: The deployment script automatically creates the database schema and sample data
3. **Configure application code**: Update your application to use the configured connection string
4. **Enable monitoring**: Consider enabling Application Insights for performance monitoring

## Outputs

The template provides the following outputs:

| Output | Description |
|--------|-------------|
| `resourceGroupName` | Name of the resource group |
| `sqlServerName` | Name of the SQL Server |
| `sqlServerFqdn` | Fully qualified domain name of the SQL Server |
| `sqlDatabaseName` | Name of the SQL Database |
| `appServicePlanName` | Name of the App Service Plan |
| `webAppName` | Name of the Web App |
| `webAppUrl` | HTTPS URL of the deployed web application |
| `webAppManagedIdentityPrincipalId` | Principal ID of the web app's managed identity |
| `sqlConnectionString` | Complete connection string for the database |

## Viewing Outputs

```bash
# View all deployment outputs
az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name <deployment-name> \
  --query properties.outputs

# Get specific output (e.g., web app URL)
az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name <deployment-name> \
  --query properties.outputs.webAppUrl.value \
  --output tsv
```

## Security Considerations

This template implements several security best practices:

- **HTTPS Only**: Web app configured to redirect HTTP traffic to HTTPS
- **TLS 1.2 Minimum**: Both SQL Server and App Service enforce TLS 1.2 or higher
- **Managed Identity**: System-assigned managed identity for secure service-to-service authentication
- **Network Isolation**: SQL Server firewall configured to allow only Azure services
- **Secure Parameters**: Database password marked as secure parameter
- **FTP Security**: FTPS only enabled for deployment security

## Cost Optimization

- **Basic Tier Resources**: Template uses Basic tiers to minimize costs for development/testing
- **Local Backup Redundancy**: Uses locally redundant storage for database backups to reduce costs
- **Single Region Deployment**: Deploys all resources in the same region to minimize data transfer costs

For production workloads, consider:
- Upgrading to Standard or Premium tiers for better performance and SLA
- Enabling geo-redundant backups for disaster recovery
- Implementing auto-scaling policies

## Troubleshooting

### Common Issues

1. **Password Requirements**: Ensure SQL password meets complexity requirements
2. **Resource Names**: Some resource names must be globally unique (handled by uniqueSuffix)
3. **Permissions**: Verify you have Contributor or Owner permissions on the subscription
4. **Quotas**: Check that your subscription has sufficient quota for the selected SKUs

### Validation

```bash
# Validate template before deployment
az deployment group validate \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters @parameters.json

# Check deployment status
az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name <deployment-name> \
  --query properties.provisioningState
```

## Cleanup

To remove all resources created by this template:

```bash
# Delete the entire resource group and all contained resources
az group delete \
  --name $RESOURCE_GROUP \
  --yes \
  --no-wait

# Verify deletion
az group exists --name $RESOURCE_GROUP
```

## Customization

### Adding Application Insights

To add monitoring capabilities, add this resource to the main.bicep template:

```bicep
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${resourceNamePrefix}-ai-${uniqueSuffix}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}
```

### Enabling Managed Identity Database Authentication

To use managed identity for database authentication instead of SQL authentication, refer to the Challenge section in the original recipe for implementation guidance.

## Support

- [Azure Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure SQL Database Documentation](https://learn.microsoft.com/en-us/azure/azure-sql/database/)
- [Azure App Service Documentation](https://learn.microsoft.com/en-us/azure/app-service/)

For issues with this template, refer to the original recipe documentation or Azure support resources.