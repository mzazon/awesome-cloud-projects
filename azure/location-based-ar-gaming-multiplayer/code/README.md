# Infrastructure as Code for Location-Based AR Gaming with Multiplayer Support

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Location-Based AR Gaming with Multiplayer Support".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with appropriate permissions
- Terraform installed (if using Terraform implementation)
- PlayFab account and title created
- Mobile development environment (Android SDK or Xcode)
- Unity 2022.3 LTS or later with AR Foundation
- Understanding of AR/VR concepts and spatial coordinate systems

### Required Azure Permissions

- Contributor role on the target resource group
- Spatial Anchors Account Contributor
- Application Developer (Azure AD)
- Function App Contributor
- Storage Account Contributor
- EventGrid Contributor

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Set required parameters
export RESOURCE_GROUP="rg-ar-gaming-demo"
export LOCATION="eastus"
export PLAYFAB_TITLE_ID="YOUR_PLAYFAB_TITLE_ID"
export PLAYFAB_SECRET_KEY="YOUR_PLAYFAB_SECRET_KEY"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Deploy infrastructure
az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file main.bicep \
    --parameters location=$LOCATION \
    --parameters playFabTitleId=$PLAYFAB_TITLE_ID \
    --parameters playFabSecretKey=$PLAYFAB_SECRET_KEY
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
resource_group_name = "rg-ar-gaming-demo"
location = "eastus"
playfab_title_id = "YOUR_PLAYFAB_TITLE_ID"
playfab_secret_key = "YOUR_PLAYFAB_SECRET_KEY"
environment = "demo"
EOF

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Set environment variables
export RESOURCE_GROUP="rg-ar-gaming-demo"
export LOCATION="eastus"
export PLAYFAB_TITLE_ID="YOUR_PLAYFAB_TITLE_ID"
export PLAYFAB_SECRET_KEY="YOUR_PLAYFAB_SECRET_KEY"

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy infrastructure
./deploy.sh
```

## Architecture Overview

The infrastructure deploys the following Azure services:

- **Azure Spatial Anchors Account**: Provides persistent spatial coordinate storage
- **Azure Function App**: Serverless compute for location processing and event handling
- **Azure Storage Account**: Stores function dependencies and anchor metadata
- **Azure AD Application**: Handles Mixed Reality authentication
- **Azure Event Grid**: Processes real-time spatial anchor events
- **Application Insights**: Monitors function performance and debugging

## Configuration

### Environment Variables

The deployment requires these environment variables:

```bash
export RESOURCE_GROUP="your-resource-group"
export LOCATION="eastus"  # or your preferred region
export PLAYFAB_TITLE_ID="your-playfab-title-id"
export PLAYFAB_SECRET_KEY="your-playfab-secret-key"
```

### PlayFab Configuration

Before deploying, ensure you have:

1. Created a PlayFab title in the Game Manager
2. Obtained your Title ID and Secret Key
3. Configured multiplayer settings in PlayFab
4. Set up player authentication methods

### Unity Client Configuration

After deployment, configure your Unity project with the output values:

```csharp
// PlayFab Settings
PlayFabSettings.staticSettings.TitleId = "YOUR_PLAYFAB_TITLE_ID";
PlayFabSettings.staticSettings.DeveloperSecretKey = "YOUR_PLAYFAB_SECRET_KEY";

// Spatial Anchors Settings
spatialAnchorsManager.SpatialAnchorsAccountId = "OUTPUT_ACCOUNT_ID";
spatialAnchorsManager.SpatialAnchorsAccountDomain = "OUTPUT_ACCOUNT_DOMAIN";
spatialAnchorsManager.SpatialAnchorsAccountKey = "OUTPUT_ACCOUNT_KEY";
```

## Deployment Outputs

After successful deployment, you'll receive:

- **Spatial Anchors Account ID**: For Unity client configuration
- **Spatial Anchors Account Domain**: For Unity client configuration
- **Function App URL**: For API endpoint configuration
- **Storage Account Connection String**: For client data storage
- **Application Insights Key**: For telemetry and monitoring

## Validation

### Verify Deployment

```bash
# Check resource group contents
az resource list --resource-group $RESOURCE_GROUP --output table

# Verify Spatial Anchors account
az spatialanchors-account show \
    --name "sa-[suffix]" \
    --resource-group $RESOURCE_GROUP

# Test Function App
curl -X GET "https://func-ar-gaming-[suffix].azurewebsites.net/api/health"

# Verify PlayFab connectivity
curl -X POST "https://[titleid].playfabapi.com/Client/LoginWithCustomID" \
    -H "Content-Type: application/json" \
    -d '{"TitleId": "'$PLAYFAB_TITLE_ID'", "CustomId": "test-user", "CreateAccount": true}'
```

### Testing AR Functionality

1. **Spatial Anchor Creation**: Use the Unity client to create and store spatial anchors
2. **Multiplayer Lobby**: Test player discovery and matchmaking
3. **Real-time Synchronization**: Verify object synchronization across devices
4. **Persistence**: Confirm anchors persist across sessions

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Confirm when prompted
```

## Customization

### Scaling Configuration

Modify these parameters to adjust for your usage patterns:

```bash
# Function App scaling
export FUNCTION_APP_PLAN_SKU="Y1"  # Consumption plan
export MAX_BURST_INSTANCES="10"

# Spatial Anchors configuration
export ANCHOR_RETENTION_DAYS="30"
export MAX_ANCHORS_PER_ACCOUNT="10000"

# Storage configuration
export STORAGE_ACCOUNT_SKU="Standard_LRS"
export STORAGE_REPLICATION="LRS"
```

### Security Hardening

Consider these security enhancements:

1. **Network Security**: Implement VNet integration for Function Apps
2. **Authentication**: Use Managed Identity where possible
3. **Encryption**: Enable customer-managed keys for storage
4. **Access Control**: Implement least privilege RBAC
5. **Monitoring**: Set up security alerts and audit logging

### Performance Optimization

For production deployments:

1. **Function App**: Consider Premium plan for better cold start performance
2. **Storage**: Use Premium storage for high-throughput scenarios
3. **Spatial Anchors**: Implement regional deployment for global applications
4. **Caching**: Add Redis cache for frequently accessed data

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   - Verify Azure CLI authentication: `az account show`
   - Check resource name availability and uniqueness
   - Ensure sufficient permissions in target subscription

2. **Function App Issues**:
   - Check Application Insights logs for errors
   - Verify environment variable configuration
   - Test function endpoints individually

3. **Spatial Anchors Problems**:
   - Validate account key and domain configuration
   - Check client device AR capabilities
   - Verify network connectivity from client devices

4. **PlayFab Integration**:
   - Confirm Title ID and Secret Key accuracy
   - Check PlayFab title configuration
   - Verify API endpoint accessibility

### Debugging Commands

```bash
# Check deployment status
az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name "main"

# View Function App logs
az functionapp log tail \
    --name "func-ar-gaming-[suffix]" \
    --resource-group $RESOURCE_GROUP

# Monitor spatial anchor usage
az monitor metrics list \
    --resource "/subscriptions/[sub-id]/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.MixedReality/spatialAnchorsAccounts/sa-[suffix]" \
    --metric "AnchorsQueried"
```

## Cost Optimization

### Estimated Monthly Costs

- **Function App (Consumption)**: $0-10 for development usage
- **Storage Account**: $5-15 depending on data volume
- **Spatial Anchors**: $20-50 based on query volume
- **Application Insights**: $0-5 for basic telemetry
- **Event Grid**: $0-2 for event processing

### Cost Reduction Strategies

1. **Use Consumption Plans**: Leverage serverless pricing where possible
2. **Implement Lifecycle Policies**: Auto-delete old anchors and data
3. **Optimize Storage**: Use appropriate storage tiers
4. **Monitor Usage**: Set up cost alerts and budgets
5. **Regional Deployment**: Choose cost-effective regions

## Support

### Documentation Resources

- [Azure Spatial Anchors Documentation](https://docs.microsoft.com/azure/spatial-anchors/)
- [PlayFab Documentation](https://docs.microsoft.com/gaming/playfab/)
- [Azure Functions Documentation](https://docs.microsoft.com/azure/azure-functions/)
- [Unity AR Foundation Documentation](https://docs.unity3d.com/Packages/com.unity.xr.arfoundation@latest)

### Community Resources

- [Azure Mixed Reality Community](https://docs.microsoft.com/azure/mixed-reality/community)
- [PlayFab Community Forums](https://community.playfab.com/)
- [Unity AR Community](https://forum.unity.com/forums/ar-vr.80/)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Azure service documentation
4. Open issues in the repository
5. Contact Azure support for service-specific issues

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Azure naming conventions
3. Update documentation for any changes
4. Consider backward compatibility
5. Submit pull requests with detailed descriptions

---

*Generated infrastructure code for Azure PlayFab and Spatial Anchors gaming platform. Last updated: 2025-07-12*