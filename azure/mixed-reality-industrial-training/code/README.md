# Infrastructure as Code for Mixed Reality Industrial Training with Remote Rendering and Object Anchors

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Mixed Reality Industrial Training with Remote Rendering and Object Anchors".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with appropriate permissions
- HoloLens 2 device with Windows Mixed Reality configured
- Unity 2022.3 LTS or later with Mixed Reality Toolkit (MRTK) 3.0
- Visual Studio 2022 with Universal Windows Platform development tools
- Basic knowledge of C# programming and Unity development
- Understanding of 3D modeling and industrial equipment visualization
- Estimated cost: $200-500 for testing (Remote Rendering sessions, storage, and compute resources)

> **Warning**: Azure Remote Rendering will be retired on September 30, 2025. Consider this timeline when planning production deployments and explore alternative solutions such as Unity Cloud Build or custom GPU-based rendering solutions.

## Quick Start

### Using Bicep (Recommended)
```bash
cd bicep/

# Deploy with default parameters
az deployment group create \
    --resource-group rg-industrial-training \
    --template-file main.bicep

# Deploy with custom parameters
az deployment group create \
    --resource-group rg-industrial-training \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Deploy infrastructure
terraform apply

# Confirm deployment
terraform apply -auto-approve
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration
```

## Architecture Overview

This implementation creates:

- **Azure Remote Rendering Account**: Cloud-based rendering of high-fidelity 3D industrial models
- **Azure Spatial Anchors Account**: Cross-platform spatial positioning for persistent content placement
- **Azure Storage Account**: Centralized storage for 3D models and training content
- **Azure Active Directory Application**: Enterprise-grade authentication and authorization
- **Resource Group**: Logical container for all training platform resources

## Configuration Parameters

### Bicep Parameters
Edit `bicep/parameters.json` to customize:
- `resourceGroupName`: Name of the resource group
- `location`: Azure region for deployment
- `storageAccountName`: Name of the storage account
- `remoteRenderingAccountName`: Name of the Remote Rendering account
- `spatialAnchorsAccountName`: Name of the Spatial Anchors account
- `applicationName`: Name of the Azure AD application

### Terraform Variables
Edit `terraform/variables.tf` or provide values:
- `resource_group_name`: Name of the resource group
- `location`: Azure region for deployment
- `storage_account_name`: Name of the storage account
- `remote_rendering_account_name`: Name of the Remote Rendering account
- `spatial_anchors_account_name`: Name of the Spatial Anchors account
- `application_name`: Name of the Azure AD application

### Bash Script Configuration
The deployment script will prompt for:
- Resource group name
- Azure region
- Storage account name
- Remote Rendering account name
- Spatial Anchors account name
- Application name

## Post-Deployment Configuration

After successful deployment, complete these steps:

1. **Unity Project Setup**:
   ```bash
   # Extract Unity configuration files
   unzip unity-azure-config.zip -d ./unity-project/
   
   # Import configuration into Unity project
   # Configure MRTK 3.0 for HoloLens 2 development
   ```

2. **Upload 3D Models**:
   ```bash
   # Upload industrial 3D models to storage
   az storage blob upload \
       --file ./models/pump-assembly.gltf \
       --container-name "3d-models" \
       --name "pump-assembly/model.gltf" \
       --account-name <storage-account-name>
   ```

3. **Configure Training Scenarios**:
   ```bash
   # Upload training scenario configurations
   az storage blob upload \
       --file ./scenarios/pump-maintenance.json \
       --container-name "training-content" \
       --name "scenarios/pump-maintenance.json" \
       --account-name <storage-account-name>
   ```

4. **Test Remote Rendering**:
   ```bash
   # Create test rendering session
   az mixed-reality remote-rendering session create \
       --account-name <remote-rendering-account> \
       --resource-group <resource-group> \
       --session-id "test-session" \
       --size "standard" \
       --lease-time 60
   ```

## Unity Integration

### Configuration Steps
1. Import the generated `unity-azure-config.zip` into your Unity project
2. Configure the Azure services settings in Unity:
   - Remote Rendering account details
   - Spatial Anchors account details
   - Storage account connection strings
   - Azure AD application configuration

### Required Unity Packages
- Mixed Reality Toolkit (MRTK) 3.0
- Azure Remote Rendering SDK
- Azure Spatial Anchors SDK
- Windows Mixed Reality SDK

### Sample Unity Script Integration
```csharp
using Microsoft.Azure.RemoteRendering;
using Microsoft.Azure.SpatialAnchors;
using UnityEngine;

public class IndustrialTrainingManager : MonoBehaviour
{
    public AzureServicesConfig config;
    
    private void Start()
    {
        InitializeAzureServices();
    }
    
    private void InitializeAzureServices()
    {
        // Initialize Azure Remote Rendering
        // Initialize Azure Spatial Anchors
        // Load training scenarios
    }
}
```

## Validation & Testing

### Infrastructure Validation
```bash
# Verify Remote Rendering account
az mixed-reality remote-rendering-account show \
    --name <account-name> \
    --resource-group <resource-group> \
    --output table

# Verify Spatial Anchors account
az mixed-reality spatial-anchors-account show \
    --name <account-name> \
    --resource-group <resource-group> \
    --output table

# Test storage connectivity
az storage blob list \
    --container-name "3d-models" \
    --account-name <storage-account-name> \
    --output table
```

### Training Content Validation
```bash
# Verify uploaded training scenarios
az storage blob list \
    --container-name "training-content" \
    --account-name <storage-account-name> \
    --output table

# Test blob download
az storage blob download \
    --container-name "training-content" \
    --name "scenarios/pump-maintenance.json" \
    --file "./test-download.json" \
    --account-name <storage-account-name>
```

## Security Considerations

### Authentication
- Azure AD application provides enterprise-grade authentication
- Service principal configured with minimal required permissions
- Secure storage account access with managed keys

### Network Security
- Storage account configured with HTTPS-only access
- Private endpoints can be configured for enhanced security
- Virtual network integration available for enterprise deployments

### Data Protection
- Encryption at rest enabled for all storage accounts
- Encryption in transit enforced for all communications
- Access keys rotated regularly following security best practices

## Cost Optimization

### Resource Sizing
- Storage account uses Standard_LRS for cost-effective development
- Remote Rendering sessions are session-based (pay-per-use)
- Spatial Anchors charged based on anchor queries and storage

### Cost Monitoring
```bash
# Monitor Azure costs
az consumption usage list \
    --resource-group <resource-group> \
    --output table

# Set up budget alerts
az consumption budget create \
    --resource-group <resource-group> \
    --budget-name "industrial-training-budget" \
    --amount 500 \
    --time-grain Monthly
```

## Troubleshooting

### Common Issues

1. **Remote Rendering Session Failures**:
   - Verify account status and quotas
   - Check session parameters and lease time
   - Ensure proper authentication configuration

2. **Spatial Anchors Not Persisting**:
   - Verify account configuration and keys
   - Check network connectivity
   - Ensure proper spatial mapping on HoloLens

3. **Storage Access Issues**:
   - Verify account keys and connection strings
   - Check container permissions
   - Ensure HTTPS-only access configuration

4. **Unity Integration Problems**:
   - Verify all required packages are installed
   - Check Azure service configuration in Unity
   - Ensure proper HoloLens 2 deployment settings

### Diagnostic Commands
```bash
# Check resource group status
az group show --name <resource-group>

# Verify service availability
az mixed-reality remote-rendering-account list
az mixed-reality spatial-anchors-account list

# Test storage connectivity
az storage account show --name <storage-account-name>
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-industrial-training \
    --yes \
    --no-wait
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

### Manual Cleanup Verification
```bash
# Verify resource group deletion
az group exists --name <resource-group>

# Check for remaining resources
az resource list --resource-group <resource-group>
```

## Development Workflow

### Local Development
1. Clone the repository
2. Choose your preferred IaC tool (Bicep recommended)
3. Configure parameters for your environment
4. Deploy infrastructure
5. Set up Unity development environment
6. Import Azure configuration
7. Develop and test HoloLens 2 application
8. Deploy to HoloLens 2 for testing

### CI/CD Integration
- Bicep templates can be integrated with Azure DevOps
- Terraform supports GitOps workflows
- Bash scripts can be used in any CI/CD pipeline

## Support and Resources

### Documentation
- [Azure Remote Rendering Documentation](https://docs.microsoft.com/en-us/azure/remote-rendering/)
- [Azure Spatial Anchors Documentation](https://docs.microsoft.com/en-us/azure/spatial-anchors/)
- [Mixed Reality Toolkit Documentation](https://docs.microsoft.com/en-us/windows/mixed-reality/mrtk-unity/)
- [HoloLens 2 Development Guide](https://docs.microsoft.com/en-us/windows/mixed-reality/develop/development)

### Community
- [Azure Mixed Reality Community](https://techcommunity.microsoft.com/t5/mixed-reality/ct-p/MixedReality)
- [HoloLens Developer Forum](https://forums.hololens.com/)
- [Unity Mixed Reality Forum](https://forum.unity.com/forums/ar-vr-xr-discussion.80/)

### Migration Planning
Given the retirement of Azure Remote Rendering on September 30, 2025:
- Evaluate Unity Cloud Build as an alternative
- Consider custom GPU rendering solutions
- Plan migration timeline for production workloads
- Test alternative rendering approaches

## License

This infrastructure code is provided as-is for educational and development purposes. Review Azure service terms and conditions for production use.