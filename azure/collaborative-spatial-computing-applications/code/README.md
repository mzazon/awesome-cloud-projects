# Infrastructure as Code for Collaborative Spatial Computing Applications with Cloud Rendering

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Collaborative Spatial Computing Applications with Cloud Rendering".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50+ installed and configured
- Appropriate Azure subscription with sufficient credits
- Azure permissions for creating:
  - Resource Groups
  - Storage Accounts
  - Mixed Reality services (Remote Rendering and Spatial Anchors)
  - Service Principals
  - Role Assignments
- Unity 2022.3 LTS or later (for application development)
- Visual Studio 2022 with UWP and C++ workloads (for HoloLens development)

> **Warning**: Azure Remote Rendering will be retired on September 30, 2025, and Azure Spatial Anchors on November 20, 2024. This infrastructure demonstrates current capabilities before retirement.

## Cost Considerations

- **Azure Remote Rendering**: $1-3 per hour of active rendering session (S1 SKU)
- **Azure Spatial Anchors**: $5 per 10,000 anchor queries (S1 SKU)
- **Storage Account**: Standard LRS ~$0.02 per GB per month
- **Estimated total cost**: $15-25 per hour of active development/testing

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Set deployment parameters
RESOURCE_GROUP="rg-spatialcomputing-demo"
LOCATION="eastus"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file main.bicep \
    --parameters location=${LOCATION} \
                 environmentName=demo \
                 costCenter=innovation

# Get deployment outputs
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="location=eastus" \
    -var="environment_name=demo" \
    -var="cost_center=innovation"

# Apply infrastructure
terraform apply \
    -var="location=eastus" \
    -var="environment_name=demo" \
    -var="cost_center=innovation"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set environment variables
export RESOURCE_GROUP="rg-spatialcomputing-demo"
export LOCATION="eastus"
export ENVIRONMENT_NAME="demo"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
az group show --name ${RESOURCE_GROUP} --query properties.provisioningState
```

## Configuration Parameters

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `eastus` | Azure region for resource deployment |
| `environmentName` | string | `dev` | Environment suffix for resource naming |
| `costCenter` | string | `innovation` | Cost center tag for resource billing |
| `arrAccountSku` | string | `S1` | Remote Rendering account SKU |
| `asaAccountSku` | string | `S1` | Spatial Anchors account SKU |
| `storageAccountSku` | string | `Standard_LRS` | Storage account replication type |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `location` | string | `"eastus"` | Azure region for resource deployment |
| `environment_name` | string | `"dev"` | Environment suffix for resource naming |
| `cost_center` | string | `"innovation"` | Cost center tag for resource billing |
| `arr_account_sku` | string | `"S1"` | Remote Rendering account SKU |
| `asa_account_sku` | string | `"S1"` | Spatial Anchors account SKU |
| `storage_account_tier` | string | `"Standard"` | Storage account performance tier |
| `storage_replication_type` | string | `"LRS"` | Storage account replication type |

### Bash Script Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `RESOURCE_GROUP` | Resource group name | `rg-spatialcomputing-demo` |
| `LOCATION` | Azure region | `eastus` |
| `ENVIRONMENT_NAME` | Environment suffix | `demo` |
| `COST_CENTER` | Cost center for billing | `innovation` |

## Deployment Outputs

All implementations provide the following outputs:

- **Remote Rendering Account ID**: For Unity application configuration
- **Remote Rendering Account Domain**: For client authentication
- **Spatial Anchors Account ID**: For Unity application configuration
- **Spatial Anchors Account Domain**: For client authentication
- **Storage Account Name**: For 3D model asset storage
- **Storage Container Name**: For organized asset management
- **Service Principal Client ID**: For application authentication
- **Resource Group Name**: For additional resource management

## Post-Deployment Steps

### 1. Configure Unity Application

Use the deployment outputs to configure your Unity project:

```json
{
  "RemoteRenderingSettings": {
    "AccountId": "[OUTPUT: remoteRenderingAccountId]",
    "AccountDomain": "[OUTPUT: remoteRenderingAccountDomain]",
    "PreferredSessionSize": "Standard"
  },
  "SpatialAnchorsSettings": {
    "AccountId": "[OUTPUT: spatialAnchorsAccountId]",
    "AccountDomain": "[OUTPUT: spatialAnchorsAccountDomain]"
  }
}
```

### 2. Upload 3D Models

```bash
# Get storage account details from outputs
STORAGE_ACCOUNT="[OUTPUT: storageAccountName]"
CONTAINER_NAME="[OUTPUT: storageContainerName]"

# Upload your 3D models
az storage blob upload \
    --account-name ${STORAGE_ACCOUNT} \
    --container-name ${CONTAINER_NAME} \
    --name "models/your-model.gltf" \
    --file ./path/to/your-model.gltf \
    --auth-mode login
```

### 3. Configure Service Principal Authentication

```bash
# Get service principal details (stored in Key Vault)
SP_CLIENT_ID="[OUTPUT: servicePrincipalClientId]"

# Retrieve client secret from Key Vault
SP_CLIENT_SECRET=$(az keyvault secret show \
    --vault-name "[OUTPUT: keyVaultName]" \
    --name "service-principal-secret" \
    --query value --output tsv)
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="location=eastus" \
    -var="environment_name=demo" \
    -var="cost_center=innovation"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group show --name ${RESOURCE_GROUP} 2>/dev/null || echo "Resource group successfully deleted"
```

## Development Workflow

### Local Development Setup

1. **Install Unity Mixed Reality Toolkit 3.0**:
   ```bash
   # Use Unity Package Manager or download from:
   # https://github.com/microsoft/MixedRealityToolkit-Unity
   ```

2. **Configure Azure Mixed Reality SDK**:
   ```bash
   # Add Azure Remote Rendering and Spatial Anchors packages
   # in Unity Package Manager
   ```

3. **Set up HoloLens Development**:
   - Enable Windows Developer Mode
   - Install Visual Studio 2022 with UWP workload
   - Configure Windows Device Portal for HoloLens

### Testing and Validation

1. **Test Remote Rendering Connection**:
   ```csharp
   // Unity C# code to test connection
   var sessionManager = new RenderingSessionManager();
   var sessionParams = new RenderingSessionCreationParams
   {
       Size = RenderingSessionVmSize.Standard,
       MaxLeaseTimeMinutes = 30
   };
   
   var session = await sessionManager.CreateNewRenderingSessionAsync(sessionParams);
   ```

2. **Test Spatial Anchors Creation**:
   ```csharp
   // Unity C# code to test anchor creation
   var cloudSpatialAnchor = new CloudSpatialAnchor();
   cloudSpatialAnchor.LocalAnchor = localAnchor;
   
   await spatialAnchorSession.CreateAnchorAsync(cloudSpatialAnchor);
   ```

## Troubleshooting

### Common Issues

1. **Service Principal Permission Errors**:
   - Ensure the service principal has "Mixed Reality Administrator" role
   - Verify tenant ID and subscription ID are correct

2. **Remote Rendering Session Failures**:
   - Check account quotas and limits
   - Verify network connectivity and firewall settings
   - Ensure model files are properly formatted (glTF 2.0)

3. **Spatial Anchors Not Persisting**:
   - Verify sufficient environmental features for tracking
   - Check network connectivity for cloud anchor storage
   - Ensure proper coordinate system transformations

### Debug Commands

```bash
# Check Mixed Reality account status
az mixed-reality remote-rendering-account show \
    --name "[OUTPUT: remoteRenderingAccountName]" \
    --resource-group ${RESOURCE_GROUP}

# Verify storage account access
az storage blob list \
    --account-name "[OUTPUT: storageAccountName]" \
    --container-name "[OUTPUT: storageContainerName]" \
    --auth-mode login

# Test service principal authentication
az login --service-principal \
    --username "[OUTPUT: servicePrincipalClientId]" \
    --password "[SECRET_FROM_KEYVAULT]" \
    --tenant "[TENANT_ID]"
```

## Security Considerations

- Service principal credentials are stored in Azure Key Vault
- Storage accounts use private endpoints where possible
- Mixed Reality accounts use Azure AD authentication
- Network security groups restrict access to necessary ports only
- All resources are tagged for compliance and cost tracking

## Customization

### Adding Additional Features

1. **Custom Material Processing**:
   - Modify storage container structure for material libraries
   - Add conversion pipeline for material optimization

2. **Multi-Region Deployment**:
   - Extend Terraform/Bicep for multiple regions
   - Implement geo-distributed spatial anchor sharing

3. **Advanced Analytics**:
   - Add Application Insights for usage analytics
   - Implement custom metrics for spatial performance

### Resource Scaling

- **Remote Rendering**: Adjust session size based on model complexity
- **Spatial Anchors**: Configure retention policies for anchor cleanup
- **Storage**: Implement lifecycle policies for 3D asset management

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../developing-spatial-computing-applications-with-azure-remote-rendering-and-azure-spatial-anchors.md)
2. Review [Azure Mixed Reality documentation](https://docs.microsoft.com/en-us/azure/remote-rendering/)
3. Consult [Azure Spatial Anchors documentation](https://docs.microsoft.com/en-us/azure/spatial-anchors/)
4. Check [service retirement timelines](https://azure.microsoft.com/updates/v2/azure-remote-rendering-retirement/)

## Migration Planning

Given the upcoming retirement of Azure Remote Rendering and Spatial Anchors:

1. **Alternative Rendering Solutions**:
   - Unity Cloud Build for cloud-based rendering
   - Third-party cloud GPU services
   - Local device optimization strategies

2. **Spatial Positioning Alternatives**:
   - Azure Object Anchors (limited to specific objects)
   - Platform-native ARCore/ARKit anchors
   - Custom spatial synchronization solutions

3. **Timeline Considerations**:
   - Plan migration before November 2024 (Spatial Anchors)
   - Complete Remote Rendering migration before September 2025
   - Test alternative solutions in parallel deployments