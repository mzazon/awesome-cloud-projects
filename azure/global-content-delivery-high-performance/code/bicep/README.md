# High-Performance Multi-Regional Content Delivery - Bicep Templates

This directory contains Bicep Infrastructure as Code (IaC) templates for deploying a high-performance multi-regional content delivery solution using Azure Front Door Premium and Azure NetApp Files.

## Architecture Overview

The solution deploys:

- **Azure Front Door Premium** - Global content delivery network with WAF protection
- **Azure NetApp Files** - High-performance storage backend in multiple regions
- **Virtual Networks** - Isolated networking in primary and secondary regions
- **Private Link Services** - Secure connectivity between Front Door and origins
- **Azure Monitor** - Comprehensive monitoring and alerting
- **Web Application Firewall** - Advanced security protection

## Files Structure

```
bicep/
├── main.bicep                    # Main Bicep template
├── modules/
│   └── region.bicep             # Regional resources module
├── parameters.json              # Example parameters file
├── main.parameters.json         # Alternative parameters file
├── deploy.ps1                   # PowerShell deployment script
├── cleanup.ps1                  # PowerShell cleanup script
└── README.md                    # This documentation
```

## Prerequisites

Before deploying this solution, ensure you have:

1. **Azure CLI** or **Azure PowerShell** installed
2. **Bicep CLI** installed (version 0.24.0 or later)
3. **Azure subscription** with appropriate permissions
4. **Resource providers** registered:
   - Microsoft.NetApp
   - Microsoft.Cdn
   - Microsoft.Network
   - Microsoft.OperationalInsights
   - Microsoft.Insights

### Install Bicep CLI

```bash
# Install Bicep CLI
az bicep install

# Verify installation
az bicep version
```

### Register Resource Providers

```bash
# Register required resource providers
az provider register --namespace Microsoft.NetApp
az provider register --namespace Microsoft.Cdn
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Insights
```

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd azure/creating-high-performance-multi-regional-content-delivery-with-azure-front-door-premium-and-azure-netapp-files/code/bicep/
```

### 2. Customize Parameters

Edit the `parameters.json` file to customize the deployment:

```json
{
  "primaryLocation": {
    "value": "eastus"
  },
  "secondaryLocation": {
    "value": "westeurope"
  },
  "resourcePrefix": {
    "value": "your-company-content"
  },
  "environment": {
    "value": "prod"
  },
  "netAppServiceLevel": {
    "value": "Premium"
  },
  "capacityPoolSize": {
    "value": 4
  },
  "volumeSize": {
    "value": 1000
  }
}
```

### 3. Deploy Using Azure CLI

```bash
# Create resource group
az group create --name rg-content-delivery --location eastus

# Deploy the solution
az deployment group create \
  --resource-group rg-content-delivery \
  --template-file main.bicep \
  --parameters @parameters.json
```

### 4. Deploy Using PowerShell

```powershell
# Connect to Azure
Connect-AzAccount

# Run deployment script
.\deploy.ps1 -SubscriptionId "your-subscription-id" -ResourceGroupName "rg-content-delivery"
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `primaryLocation` | string | `eastus` | Primary Azure region |
| `secondaryLocation` | string | `westeurope` | Secondary Azure region |
| `resourcePrefix` | string | `content-delivery` | Prefix for resource names |
| `environment` | string | `prod` | Environment (dev/staging/prod) |
| `netAppServiceLevel` | string | `Premium` | NetApp Files service level |
| `capacityPoolSize` | int | `4` | Capacity pool size in TiB |
| `volumeSize` | int | `1000` | Volume size in GiB |
| `enableWaf` | bool | `true` | Enable Web Application Firewall |
| `wafMode` | string | `Prevention` | WAF mode (Prevention/Detection) |
| `enableMonitoring` | bool | `true` | Enable monitoring and diagnostics |

## Deployment Options

### Option 1: Azure CLI

```bash
# Basic deployment
az deployment group create \
  --resource-group rg-content-delivery \
  --template-file main.bicep \
  --parameters @parameters.json

# What-if deployment (preview changes)
az deployment group what-if \
  --resource-group rg-content-delivery \
  --template-file main.bicep \
  --parameters @parameters.json
```

### Option 2: PowerShell

```powershell
# Basic deployment
New-AzResourceGroupDeployment \
  -ResourceGroupName "rg-content-delivery" \
  -TemplateFile "main.bicep" \
  -TemplateParameterFile "parameters.json"

# What-if deployment
New-AzResourceGroupDeployment \
  -ResourceGroupName "rg-content-delivery" \
  -TemplateFile "main.bicep" \
  -TemplateParameterFile "parameters.json" \
  -WhatIf
```

### Option 3: Deployment Script

```powershell
# Deploy with script
.\deploy.ps1 -SubscriptionId "your-sub-id" -ResourceGroupName "rg-content-delivery"

# What-if deployment
.\deploy.ps1 -SubscriptionId "your-sub-id" -ResourceGroupName "rg-content-delivery" -WhatIf
```

## Outputs

The deployment provides these outputs:

| Output | Description |
|--------|-------------|
| `frontDoorEndpointHostname` | Front Door endpoint hostname |
| `frontDoorProfileId` | Front Door profile resource ID |
| `wafPolicyId` | WAF policy resource ID |
| `logAnalyticsWorkspaceId` | Log Analytics workspace ID |
| `primaryRegionOutputs` | Primary region resource details |
| `secondaryRegionOutputs` | Secondary region resource details |

## Post-Deployment Configuration

After deployment, complete these steps:

### 1. Configure Origin Servers

Mount the Azure NetApp Files volumes on your origin servers:

```bash
# Mount NetApp Files volume (example)
sudo mkdir -p /mnt/content
sudo mount -t nfs -o vers=3,proto=tcp \
  <netapp-volume-ip>:/content-volume /mnt/content
```

### 2. Upload Content

Upload your content to the mounted NetApp Files volumes:

```bash
# Upload content to NetApp Files
cp -r /path/to/your/content/* /mnt/content/
```

### 3. Test the Solution

Test the Front Door endpoint:

```bash
# Test Front Door endpoint
curl -I https://<front-door-hostname>/
```

### 4. Configure Custom Domain (Optional)

Add a custom domain to your Front Door endpoint:

```bash
# Add custom domain
az afd custom-domain create \
  --resource-group rg-content-delivery \
  --profile-name <front-door-profile> \
  --custom-domain-name "www-example-com" \
  --host-name "www.example.com"
```

## Monitoring and Troubleshooting

### View Deployment Status

```bash
# Check deployment status
az deployment group show \
  --resource-group rg-content-delivery \
  --name <deployment-name>
```

### Monitor Resources

```bash
# View Front Door metrics
az monitor metrics list \
  --resource <front-door-resource-id> \
  --metric "RequestCount"

# View NetApp Files metrics
az monitor metrics list \
  --resource <netapp-account-resource-id> \
  --metric "VolumeLogicalSize"
```

### Common Issues

1. **NetApp Files Registration**: Ensure Microsoft.NetApp provider is registered
2. **Capacity Pool Limits**: Check Azure NetApp Files capacity limits in your region
3. **Front Door Propagation**: Front Door changes may take 5-10 minutes to propagate
4. **Private Link Approval**: Private Link connections may require approval

## Security Considerations

The solution implements these security best practices:

- **Private Link** connectivity between Front Door and origins
- **Web Application Firewall** with managed rule sets
- **Network Security Groups** for subnet protection
- **Azure Monitor** for security event logging
- **HTTPS enforcement** for all traffic

## Cost Optimization

To optimize costs:

1. **NetApp Files**: Use appropriate service level for your performance needs
2. **Front Door**: Monitor cache hit ratio and optimize caching rules
3. **Resource Groups**: Use consistent tagging for cost allocation
4. **Monitoring**: Set up cost alerts and budgets

## Cleanup

To remove all resources:

### Option 1: PowerShell Script

```powershell
.\cleanup.ps1 -SubscriptionId "your-sub-id" -ResourceGroupName "rg-content-delivery"
```

### Option 2: Azure CLI

```bash
# Delete resource group (removes all resources)
az group delete --name rg-content-delivery --yes --no-wait
```

### Option 3: Manual Cleanup

Delete resources in this order:
1. Front Door routes and security policies
2. NetApp Files volumes
3. NetApp Files capacity pools
4. NetApp Files accounts
5. Other resources
6. Resource group

## Support

For issues with this infrastructure code:

1. Check the [Azure NetApp Files documentation](https://docs.microsoft.com/azure/azure-netapp-files/)
2. Review [Azure Front Door documentation](https://docs.microsoft.com/azure/frontdoor/)
3. Consult the [Azure Bicep documentation](https://docs.microsoft.com/azure/azure-resource-manager/bicep/)
4. Refer to the original recipe documentation

## Contributing

To contribute improvements:

1. Test changes in a development environment
2. Follow Azure Bicep best practices
3. Update documentation as needed
4. Ensure all parameters are properly validated

## License

This infrastructure code is provided as-is under the MIT License. See the repository license for details.