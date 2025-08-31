# Azure File Upload Processing - Bicep Infrastructure as Code

This directory contains Bicep Infrastructure as Code (IaC) templates for deploying a serverless file processing solution using Azure Functions and Blob Storage. The solution automatically processes files uploaded to a blob container using event-driven triggers.

## Architecture Overview

The Bicep template deploys the following Azure resources:

- **Storage Account**: Provides blob storage for file uploads with configurable access tiers and security settings
- **Blob Container**: Container for file uploads that triggers function execution
- **Function App**: Serverless compute platform with consumption-based billing
- **App Service Plan**: Hosting infrastructure for the Function App (Consumption or Premium)
- **Application Insights**: Application performance monitoring and telemetry collection
- **Log Analytics Workspace**: Centralized logging and monitoring backend
- **Role Assignments**: Managed identity permissions for secure resource access

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Azure CLI** installed and configured (version 2.50 or later)
2. **Bicep CLI** installed (comes with Azure CLI or install separately)
3. An **Azure subscription** with appropriate permissions to create resources
4. **Resource Group** already created or permissions to create one
5. Understanding of Azure Functions and Blob Storage concepts

### Required Azure Permissions

Your Azure account needs the following permissions:
- `Contributor` role on the target resource group
- `User Access Administrator` role for role assignments (or equivalent permissions)

## Quick Start Deployment

### 1. Clone and Navigate

```bash
# Navigate to the Bicep directory
cd azure/file-upload-processing-functions-blob/code/bicep/
```

### 2. Deploy with Default Parameters

```bash
# Create resource group (if it doesn't exist)
az group create \
    --name rg-fileproc-dev \
    --location eastus

# Deploy the Bicep template with default parameters
az deployment group create \
    --resource-group rg-fileproc-dev \
    --template-file main.bicep \
    --parameters parameters.json
```

### 3. Deploy with Custom Parameters

```bash
# Deploy with custom parameter values
az deployment group create \
    --resource-group rg-fileproc-prod \
    --template-file main.bicep \
    --parameters environment=prod \
                 applicationName=myfileapp \
                 location=westus2 \
                 functionAppHostingPlan=Premium \
                 storageAccountSku=Standard_GRS
```

## Parameter Configuration

The template supports the following parameters for customization:

### Core Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `environment` | string | `dev` | Environment name (dev, test, prod) |
| `applicationName` | string | `fileproc` | Application name prefix for resources |
| `location` | string | Resource Group location | Azure region for deployment |

### Storage Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `storageAccountSku` | string | `Standard_LRS` | Storage account redundancy level |
| `storageAccessTier` | string | `Hot` | Storage access tier (Hot/Cool) |
| `blobContainerName` | string | `uploads` | Container name for file uploads |
| `blobContainerPublicAccess` | string | `None` | Public access level for container |

### Function App Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `functionAppRuntime` | string | `node` | Runtime stack (node, dotnet, python, java, powershell) |
| `functionAppRuntimeVersion` | string | `18` | Runtime version |
| `functionAppHostingPlan` | string | `Consumption` | Hosting plan (Consumption/Premium) |

### Monitoring Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `enableApplicationInsights` | bool | `true` | Enable Application Insights monitoring |
| `resourceTags` | object | See parameters.json | Resource tags for governance |

## Deployment Examples

### Development Environment

```bash
az deployment group create \
    --resource-group rg-fileproc-dev \
    --template-file main.bicep \
    --parameters environment=dev \
                 applicationName=fileproc \
                 functionAppHostingPlan=Consumption \
                 storageAccountSku=Standard_LRS
```

### Production Environment

```bash
az deployment group create \
    --resource-group rg-fileproc-prod \
    --template-file main.bicep \
    --parameters environment=prod \
                 applicationName=fileproc \
                 functionAppHostingPlan=Premium \
                 storageAccountSku=Standard_GRS \
                 storageAccessTier=Hot
```

### Multi-Language Support

```bash
# Deploy with Python runtime
az deployment group create \
    --resource-group rg-fileproc-python \
    --template-file main.bicep \
    --parameters functionAppRuntime=python \
                 functionAppRuntimeVersion=3.9

# Deploy with .NET runtime
az deployment group create \
    --resource-group rg-fileproc-dotnet \
    --template-file main.bicep \
    --parameters functionAppRuntime=dotnet \
                 functionAppRuntimeVersion=6.0
```

## Validation and Testing

### 1. Verify Deployment

```bash
# Check deployment status
az deployment group show \
    --resource-group rg-fileproc-dev \
    --name main \
    --query "properties.provisioningState"

# List deployed resources
az resource list \
    --resource-group rg-fileproc-dev \
    --output table
```

### 2. Test Storage Account Access

```bash
# Get storage account name from deployment output
STORAGE_ACCOUNT=$(az deployment group show \
    --resource-group rg-fileproc-dev \
    --name main \
    --query "properties.outputs.storageAccountName.value" \
    --output tsv)

# Test blob container accessibility
az storage blob list \
    --account-name $STORAGE_ACCOUNT \
    --container-name uploads \
    --auth-mode login
```

### 3. Verify Function App Configuration

```bash
# Get Function App name from deployment output
FUNCTION_APP=$(az deployment group show \
    --resource-group rg-fileproc-dev \
    --name main \
    --query "properties.outputs.functionAppName.value" \
    --output tsv)

# Check Function App settings
az functionapp config appsettings list \
    --name $FUNCTION_APP \
    --resource-group rg-fileproc-dev \
    --output table
```

## Post-Deployment Configuration

### 1. Deploy Function Code

After infrastructure deployment, deploy your function code:

```bash
# Create function code package (example for Node.js)
mkdir function-code && cd function-code

# Create function.json
cat > function.json << 'EOF'
{
  "bindings": [
    {
      "name": "myBlob",
      "type": "blobTrigger",
      "direction": "in",
      "path": "uploads/{name}",
      "connection": "STORAGE_CONNECTION_STRING"
    }
  ]
}
EOF

# Create index.js with your processing logic
cat > index.js << 'EOF'
module.exports = async function (context, myBlob) {
    const fileName = context.bindingData.name;
    const fileSize = myBlob.length;
    
    context.log(`Processing file: ${fileName} (${fileSize} bytes)`);
    
    // Add your file processing logic here
    
    context.log(`File processing completed: ${fileName}`);
};
EOF

# Deploy to Function App
zip -r ../function-deploy.zip .
az functionapp deployment source config-zip \
    --src ../function-deploy.zip \
    --name $FUNCTION_APP \
    --resource-group rg-fileproc-dev
```

### 2. Configure Monitoring Alerts

```bash
# Create alert rule for function failures
az monitor metrics alert create \
    --name "FunctionApp-Errors" \
    --resource-group rg-fileproc-dev \
    --scopes "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-fileproc-dev/providers/Microsoft.Web/sites/$FUNCTION_APP" \
    --condition "count Http5xx > 5" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --description "Function App error rate alert"
```

## Monitoring and Troubleshooting

### Application Insights Integration

The template automatically configures Application Insights for comprehensive monitoring:

- **Function execution metrics**: Duration, success rate, failures
- **Dependency tracking**: Storage account interactions
- **Custom telemetry**: Add custom metrics in your function code
- **Log correlation**: Correlate logs across the entire request flow

### Access Application Insights

```bash
# Get Application Insights details
az deployment group show \
    --resource-group rg-fileproc-dev \
    --name main \
    --query "properties.outputs.applicationInsightsConnectionString.value"
```

### Common Issues and Solutions

1. **Function not triggering on blob upload**:
   - Verify storage connection string configuration
   - Check blob container permissions
   - Ensure managed identity has Storage Blob Data Contributor role

2. **Function deployment failures**:
   - Verify Function App runtime configuration
   - Check for syntax errors in function code
   - Ensure proper zip package structure

3. **Storage access issues**:
   - Verify network access rules
   - Check Azure AD authentication settings
   - Confirm role assignments are properly configured

## Security Considerations

The Bicep template implements several security best practices:

### Data Protection
- **HTTPS Only**: All traffic encrypted in transit
- **TLS 1.2 Minimum**: Modern encryption standards
- **Storage Encryption**: Data encrypted at rest by default

### Access Control
- **Managed Identity**: Function App uses system-assigned identity
- **RBAC**: Role-based access control for storage operations
- **Least Privilege**: Minimal required permissions granted

### Network Security
- **Storage Firewall**: Configurable network access rules
- **Private Endpoints**: Can be enabled for enhanced security
- **CORS Configuration**: Restrictive cross-origin policies

## Cost Optimization

### Consumption Plan Benefits
- **Pay-per-execution**: Only charged for actual function runs
- **Automatic scaling**: Scales to zero when not in use
- **Free tier**: 1M executions and 400,000 GB-seconds monthly

### Storage Cost Management
- **Access Tiers**: Hot for frequently accessed files, Cool for archives
- **Lifecycle Policies**: Automatically move files to cheaper tiers
- **Redundancy Options**: Choose appropriate redundancy level

### Monitoring Costs
```bash
# Monitor resource costs using Azure CLI
az consumption usage list \
    --start-date 2025-01-01 \
    --end-date 2025-01-31 \
    --query "[?contains(instanceId, 'fileproc')]"
```

## Cleanup and Resource Removal

### Complete Resource Cleanup

```bash
# Delete the entire resource group and all resources
az group delete \
    --name rg-fileproc-dev \
    --yes \
    --no-wait

# Verify deletion (optional)
az group exists --name rg-fileproc-dev
```

### Selective Resource Cleanup

```bash
# Delete specific resources while keeping others
az functionapp delete \
    --name $FUNCTION_APP \
    --resource-group rg-fileproc-dev

az storage account delete \
    --name $STORAGE_ACCOUNT \
    --resource-group rg-fileproc-dev \
    --yes
```

## Advanced Configuration

### Custom Domain Configuration

```bash
# Add custom domain to Function App (after deployment)
az functionapp config hostname add \
    --webapp-name $FUNCTION_APP \
    --resource-group rg-fileproc-dev \
    --hostname "api.yourdomain.com"
```

### Virtual Network Integration

To integrate with existing VNet infrastructure, modify the Bicep template to include:

```bicep
// Add VNet integration properties to Function App
vnetRouteAllEnabled: true
vnetImagePullEnabled: false
vnetContentShareEnabled: false
```

### Premium Plan Features

When using Premium plan, additional features become available:

- **VNet Integration**: Private network connectivity
- **Always Ready Instances**: Eliminate cold starts
- **Unlimited Execution Duration**: Long-running processes
- **More CPU and Memory**: Enhanced performance

## Support and Documentation

### Official Documentation
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Blob Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/blobs/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)

### Troubleshooting Resources
- [Function App Troubleshooting Guide](https://docs.microsoft.com/en-us/azure/azure-functions/functions-troubleshoot)
- [Storage Account Troubleshooting](https://docs.microsoft.com/en-us/azure/storage/common/storage-monitoring-troubleshooting-overview)

### Community Support
- [Azure Functions GitHub Repository](https://github.com/Azure/Azure-Functions)
- [Azure Storage GitHub Repository](https://github.com/Azure/azure-storage-net)
- [Microsoft Q&A Forum](https://docs.microsoft.com/en-us/answers/topics/azure-functions.html)

## Contributing

To contribute improvements to this Bicep template:

1. Test changes in a development environment
2. Validate template syntax: `az bicep build --file main.bicep`
3. Follow Azure Bicep best practices
4. Update documentation for any parameter changes
5. Include examples for new features

## Version History

- **v1.0**: Initial Bicep template with core functionality
- **v1.1**: Added Application Insights integration and enhanced security
- **v1.2**: Improved parameter validation and documentation
- **v1.3**: Added multi-runtime support and advanced configuration options