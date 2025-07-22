# Azure DevOps Monitoring Live Dashboards - Bicep Implementation

This directory contains the Bicep Infrastructure as Code (IaC) implementation for deploying a real-time monitoring dashboard system for Azure DevOps environments.

## Overview

The Bicep template deploys a complete monitoring infrastructure that includes:

- **Azure SignalR Service** for real-time web communication
- **Azure Functions App** for processing DevOps webhook events
- **Azure Web App** for hosting the monitoring dashboard
- **Azure Storage Account** for function app storage
- **Log Analytics Workspace** for centralized logging
- **Application Insights** for application performance monitoring
- **Azure Monitor Alerts** for proactive monitoring
- **RBAC roles** for secure service-to-service communication

## Architecture

The deployed infrastructure follows this architecture:

```
Azure DevOps → Function App → SignalR Service → Web App Dashboard
                    ↓
              Azure Monitor ← Log Analytics ← Application Insights
```

## Files Structure

```
bicep/
├── main.bicep                 # Main Bicep template
├── parameters.json            # Default parameters (demo environment)
├── parameters.prod.json       # Production environment parameters
├── parameters.test.json       # Test environment parameters
├── deploy.sh                  # Deployment script
├── cleanup.sh                 # Resource cleanup script
├── validate.sh                # Template validation script
└── README.md                  # This file
```

## Prerequisites

- Azure CLI 2.37.0 or later
- Bicep CLI (optional, for advanced features)
- jq (optional, for JSON processing)
- Appropriate Azure subscription permissions:
  - Contributor role on the target resource group
  - User Access Administrator role (for RBAC assignments)

## Quick Start

### 1. Validate the Template

```bash
# Validate template and parameters
./validate.sh -g rg-monitoring-demo

# Validate with specific environment
./validate.sh -g rg-monitoring-prod -e prod -p parameters.prod.json
```

### 2. Deploy to Demo Environment

```bash
# Deploy with default parameters
./deploy.sh -g rg-monitoring-demo

# Deploy with custom location
./deploy.sh -g rg-monitoring-demo -l westus2
```

### 3. Deploy to Production Environment

```bash
# Deploy to production with enhanced security
./deploy.sh -g rg-monitoring-prod -e prod -p parameters.prod.json
```

### 4. Deploy to Test Environment

```bash
# Deploy to test environment with cost optimization
./deploy.sh -g rg-monitoring-test -e test -p parameters.test.json
```

## Parameters

### Core Parameters

| Parameter | Description | Default | Allowed Values |
|-----------|-------------|---------|----------------|
| `resourcePrefix` | Prefix for all resource names | "monitor" | String |
| `location` | Azure region | Resource group location | Valid Azure regions |
| `environment` | Environment tag | "demo" | dev, test, staging, prod, demo |

### Service Configuration

| Parameter | Description | Default | Allowed Values |
|-----------|-------------|---------|----------------|
| `signalrSku` | SignalR Service pricing tier | "Standard_S1" | Free_F1, Standard_S1 |
| `functionAppSku` | Function App pricing tier | "Y1" | Y1 (Consumption) |
| `webAppSku` | Web App pricing tier | "B1" | B1, B2, S1, S2 |
| `storageAccountType` | Storage account replication | "Standard_LRS" | Standard_LRS, Standard_GRS, Standard_ZRS |
| `logAnalyticsSku` | Log Analytics pricing tier | "PerGB2018" | PerGB2018, Free, Standalone, PerNode |

### Security Parameters

| Parameter | Description | Default | Notes |
|-----------|-------------|---------|-------|
| `enableDiagnostics` | Enable diagnostic settings | `true` | Sends logs to Log Analytics |
| `enableNetworkRestrictions` | Enable IP restrictions | `false` | Recommended for production |
| `allowedIpAddresses` | Allowed IP address ranges | `[]` | Array of CIDR ranges |

## Environment-Specific Deployments

### Demo Environment (parameters.json)
- Cost-optimized settings
- Standard SignalR Service
- Basic Web App tier
- No network restrictions
- Full diagnostic logging

### Test Environment (parameters.test.json)
- Free SignalR Service tier
- Auto-shutdown tags
- Minimal resource configuration
- Used for testing and development

### Production Environment (parameters.prod.json)
- Enhanced security settings
- Geo-redundant storage
- Network restrictions enabled
- Premium service tiers
- Production-grade monitoring

## Deployment Options

### Option 1: Using Scripts (Recommended)

```bash
# Validate before deployment
./validate.sh -g <resource-group> -p <parameters-file>

# Deploy the infrastructure
./deploy.sh -g <resource-group> -p <parameters-file>

# Clean up resources
./cleanup.sh -g <resource-group>
```

### Option 2: Using Azure CLI Directly

```bash
# Create resource group
az group create --name rg-monitoring-demo --location eastus

# Deploy template
az deployment group create \
    --resource-group rg-monitoring-demo \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Option 3: Using Azure Portal

1. Navigate to the Azure Portal
2. Create a new deployment
3. Upload the `main.bicep` file
4. Configure parameters
5. Deploy

## Post-Deployment Configuration

After successful deployment, complete these steps:

### 1. Deploy Function Code

```bash
# Get function app name from deployment output
FUNCTION_APP=$(az deployment group show --resource-group <rg-name> --name <deployment-name> --query "properties.outputs.functionAppName.value" -o tsv)

# Deploy function code (see main recipe for code)
az functionapp deployment source config-zip \
    --resource-group <rg-name> \
    --name $FUNCTION_APP \
    --src function-app.zip
```

### 2. Deploy Dashboard Application

```bash
# Get web app name from deployment output
WEB_APP=$(az deployment group show --resource-group <rg-name> --name <deployment-name> --query "properties.outputs.webAppName.value" -o tsv)

# Deploy dashboard code (see main recipe for code)
az webapp deployment source config-zip \
    --resource-group <rg-name> \
    --name $WEB_APP \
    --src dashboard-app.zip
```

### 3. Configure Azure DevOps Service Hooks

1. Get the webhook URL from deployment outputs
2. Navigate to your Azure DevOps project settings
3. Go to Service hooks
4. Create new webhook with the provided URL
5. Configure for Build completed and Release deployment events

## Monitoring and Diagnostics

### Application Insights

The template automatically configures Application Insights for:
- Function App performance monitoring
- Web App diagnostics
- Custom telemetry collection
- Dependency tracking

### Log Analytics

Centralized logging includes:
- Function execution logs
- Web application logs
- SignalR service logs
- Azure Monitor metrics

### Azure Monitor Alerts

Pre-configured alerts for:
- Function App errors (threshold: >5 errors in 5 minutes)
- SignalR connection issues (threshold: <1 connection for 15 minutes)
- Custom webhook notifications

## Security Features

### Identity and Access Management

- System-assigned managed identities for all services
- RBAC roles for SignalR service access
- Monitoring metrics publisher role for custom metrics

### Network Security

- HTTPS enforcement on all web services
- TLS 1.2 minimum requirement
- Optional IP restrictions for production environments
- CORS configuration for dashboard access

### Data Protection

- Encryption at rest for storage accounts
- Encryption in transit for all communications
- Secure connection strings using Key Vault references (optional)

## Cost Optimization

### Resource Sizing

- Consumption-based Function App pricing
- Appropriately sized App Service plans
- Locally redundant storage for non-critical data

### Monitoring Costs

- Log Analytics retention policies
- Application Insights sampling
- Alert frequency optimization

### Environment-Specific Optimization

- Free tiers for test environments
- Auto-shutdown tags for temporary resources
- Resource scaling based on usage patterns

## Troubleshooting

### Common Issues

1. **Deployment Validation Errors**
   ```bash
   # Check template syntax
   ./validate.sh -g <resource-group> -v
   
   # Validate with specific parameters
   ./validate.sh -g <resource-group> -p parameters.prod.json
   ```

2. **Resource Group Already Exists**
   ```bash
   # Use existing resource group
   ./deploy.sh -g <existing-resource-group>
   
   # Or use different name
   ./deploy.sh -g <new-resource-group-name>
   ```

3. **Permission Errors**
   ```bash
   # Check current permissions
   az role assignment list --assignee $(az account show --query user.name -o tsv) --scope /subscriptions/$(az account show --query id -o tsv)
   ```

4. **Resource Naming Conflicts**
   - Resource names include a unique suffix
   - Modify `resourcePrefix` parameter if needed
   - Check existing resources in the region

### Debug Mode

Enable verbose output for troubleshooting:

```bash
# Validate with verbose output
./validate.sh -g <resource-group> -v

# Deploy with verbose output
./deploy.sh -g <resource-group> -v
```

## Cleanup

### Partial Cleanup (Keep Resource Group)

```bash
# Remove all resources but keep resource group
./cleanup.sh -g <resource-group> -k
```

### Complete Cleanup

```bash
# Remove resource group and all resources
./cleanup.sh -g <resource-group>

# Force cleanup without confirmation
./cleanup.sh -g <resource-group> -f
```

## Advanced Configuration

### Custom Domain Names

For production deployments, configure custom domains:

```bash
# Add custom domain to Web App
az webapp config hostname add \
    --resource-group <rg-name> \
    --webapp-name <web-app-name> \
    --hostname <custom-domain>
```

### Private Endpoints

For enhanced security, configure private endpoints:

```bash
# Create private endpoint for SignalR
az network private-endpoint create \
    --resource-group <rg-name> \
    --name signalr-pe \
    --vnet-name <vnet-name> \
    --subnet <subnet-name> \
    --private-connection-resource-id <signalr-resource-id> \
    --group-id signalr \
    --connection-name signalr-connection
```

### Key Vault Integration

For production security, integrate with Azure Key Vault:

```bash
# Create Key Vault
az keyvault create \
    --resource-group <rg-name> \
    --name <keyvault-name> \
    --location <location>

# Store connection strings
az keyvault secret set \
    --vault-name <keyvault-name> \
    --name SignalRConnectionString \
    --value <connection-string>
```

## Support

For issues with this Bicep implementation:

1. Validate the template using `validate.sh`
2. Check the deployment logs in Azure Portal
3. Review the troubleshooting section above
4. Consult the main recipe documentation
5. Check Azure service health and limits

## Contributing

When modifying the Bicep template:

1. Update parameter validation
2. Add appropriate resource dependencies
3. Include diagnostic settings for new resources
4. Update the README with new parameters
5. Test in all environments (dev, test, prod)

## Version History

- v1.0: Initial Bicep implementation
- v1.1: Added diagnostic settings and security enhancements
- v1.2: Added environment-specific parameter files
- v1.3: Added network restrictions and advanced monitoring