# Infrastructure as Code for Golden Image Automation with CI/CD Pipelines

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Golden Image Automation with CI/CD Pipelines".

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code using the Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - VM Image Builder (requires `Microsoft.VirtualMachineImages` resource provider)
  - Private DNS Resolver (requires `Microsoft.Network` resource provider)
  - Azure Compute Gallery (requires `Microsoft.Compute` resource provider)
- PowerShell Core 7.0+ (for Bicep advanced features)
- Terraform v1.5.0 or later (for Terraform implementation)
- Azure DevOps organization with project administrator permissions
- Estimated cost: $50-100 for resources created during deployment

> **Note**: VM Image Builder requires specific Azure resource provider registrations and service principal permissions. Ensure the following resource providers are registered in your subscription:
> - Microsoft.VirtualMachineImages
> - Microsoft.Network
> - Microsoft.Compute
> - Microsoft.Storage

## Quick Start

### Using Bicep

```bash
# Navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters @parameters.json \
    --parameters location=eastus

# Verify deployment
az deployment group show \
    --resource-group <your-resource-group> \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment status
az group show --name <generated-resource-group-name> --query properties.provisioningState
```

## Architecture Overview

This infrastructure deploys:

1. **Hub Virtual Network**: Contains the Azure Private DNS Resolver with inbound and outbound endpoints
2. **Build Virtual Network**: Isolated network for VM Image Builder operations with DNS resolver integration
3. **Private DNS Resolver**: Provides hybrid DNS resolution between Azure and on-premises environments
4. **Azure Compute Gallery**: Centralized image management and distribution
5. **VM Image Builder Template**: Automated golden image creation pipeline
6. **Managed Identity**: Service principal for VM Image Builder with appropriate permissions
7. **Azure DevOps Pipeline**: CI/CD integration for automated image builds

## Resource Configuration

### Key Resources Created

- **Resource Group**: Container for all golden image pipeline resources
- **Hub Virtual Network** (10.0.0.0/16): Network hosting the DNS resolver
- **Build Virtual Network** (10.1.0.0/16): Isolated network for image building
- **Private DNS Resolver**: Hybrid DNS solution with inbound/outbound endpoints
- **Azure Compute Gallery**: Image versioning and distribution platform
- **VM Image Builder Template**: Ubuntu 20.04 LTS hardened image definition
- **Managed Identity**: RBAC-enabled service principal for image builder
- **Virtual Network Peering**: Connectivity between hub and build networks

### Security Features

- **Network Isolation**: Build process runs in isolated virtual network
- **Managed Identity**: No credential management required for VM Image Builder
- **RBAC Permissions**: Least privilege access for image building operations
- **Private Endpoints**: Secure communication between Azure services
- **Security Hardening**: Automated security baseline configuration in golden images

## Customization

### Bicep Parameters

Edit `bicep/parameters.json` to customize your deployment:

```json
{
  "location": {
    "value": "eastus"
  },
  "resourcePrefix": {
    "value": "golden-image"
  },
  "hubVnetAddressPrefix": {
    "value": "10.0.0.0/16"
  },
  "buildVnetAddressPrefix": {
    "value": "10.1.0.0/16"
  },
  "vmImageBuilderTimeout": {
    "value": 80
  },
  "computeGalleryName": {
    "value": "myGallery"
  }
}
```

### Terraform Variables

Edit `terraform/variables.tf` or create a `terraform.tfvars` file:

```hcl
# terraform.tfvars
location = "eastus"
resource_prefix = "golden-image"
hub_vnet_address_prefix = "10.0.0.0/16"
build_vnet_address_prefix = "10.1.0.0/16"
vm_image_builder_timeout = 80
compute_gallery_name = "myGallery"
tags = {
  Environment = "Production"
  Purpose = "GoldenImage"
}
```

### Script Configuration

Edit environment variables in `scripts/deploy.sh`:

```bash
# Customize these variables
export LOCATION="eastus"
export RESOURCE_PREFIX="golden-image"
export HUB_VNET_PREFIX="10.0.0.0/16"
export BUILD_VNET_PREFIX="10.1.0.0/16"
export VM_SIZE="Standard_D2s_v3"
export BUILD_TIMEOUT=80
```

## Image Template Customization

### Adding Custom Software

Modify the VM Image Builder template customization steps:

```json
{
  "type": "Shell",
  "name": "InstallCustomSoftware",
  "inline": [
    "sudo apt-get update -y",
    "sudo apt-get install -y docker.io",
    "sudo systemctl enable docker",
    "sudo usermod -aG docker azureuser"
  ]
}
```

### Security Hardening

Add additional security configurations:

```json
{
  "type": "Shell",
  "name": "SecurityHardening",
  "inline": [
    "sudo apt-get install -y clamav clamav-daemon",
    "sudo freshclam",
    "sudo systemctl enable clamav-daemon",
    "sudo ufw default deny incoming",
    "sudo ufw default allow outgoing"
  ]
}
```

## DNS Configuration

### On-Premises Integration

Configure DNS forwarding rules for your corporate domains:

```bash
# Add DNS forwarding rule for corporate domain
az dns-resolver forwarding-rule create \
    --name "corporate-domain" \
    --resource-group <resource-group> \
    --ruleset-name "corporate-ruleset" \
    --domain-name "corp.contoso.com" \
    --forwarding-rule-state "Enabled" \
    --target-dns-servers '[{"ipAddress":"10.0.0.4","port":53}]'
```

### Private DNS Zones

Link Azure Private DNS zones to the resolver:

```bash
# Create and link private DNS zone
az network private-dns zone create \
    --resource-group <resource-group> \
    --name "privatelink.azurecr.io"

az network private-dns link vnet create \
    --resource-group <resource-group> \
    --zone-name "privatelink.azurecr.io" \
    --name "build-vnet-link" \
    --virtual-network <build-vnet-id> \
    --registration-enabled false
```

## DevOps Integration

### Azure DevOps Pipeline

The infrastructure includes an Azure DevOps pipeline configuration (`azure-pipelines.yml`) that provides:

- **Template Validation**: Syntax and configuration validation
- **Automated Building**: Triggered image creation on code changes
- **Progress Monitoring**: Build status tracking and notifications
- **Version Publishing**: Automated image versioning and tagging

### Service Connection Setup

Configure Azure DevOps service connection:

```bash
# Create service principal for DevOps
az ad sp create-for-rbac \
    --name "golden-image-devops" \
    --role "Contributor" \
    --scopes "/subscriptions/<subscription-id>/resourceGroups/<resource-group>"
```

## Monitoring and Troubleshooting

### Build Monitoring

Monitor VM Image Builder operations:

```bash
# Check image builder template status
az image builder show \
    --name <template-name> \
    --resource-group <resource-group> \
    --query properties.lastRunStatus

# View build logs
az image builder logs \
    --name <template-name> \
    --resource-group <resource-group>
```

### DNS Resolution Testing

Test DNS resolution from build network:

```bash
# Test DNS resolution from build VM
nslookup corp.contoso.com
dig @10.0.1.4 corp.contoso.com
```

### Common Issues

1. **Build Timeouts**: Increase `buildTimeoutInMinutes` in the template
2. **Permission Errors**: Verify managed identity role assignments
3. **Network Connectivity**: Check virtual network peering and DNS forwarding rules
4. **DNS Resolution**: Validate DNS resolver endpoints and forwarding rules

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name <your-resource-group> \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
az group show --name <resource-group-name> --query properties.provisioningState
```

## Cost Optimization

### Resource Sizing

- **VM Image Builder**: Use appropriate VM size for build workloads (Standard_D2s_v3 recommended)
- **Storage**: Use Standard_LRS for cost-effective image storage
- **Network**: Leverage existing virtual networks when possible

### Scheduling

- **Build Frequency**: Schedule image builds during off-peak hours
- **Retention**: Implement lifecycle policies for old image versions
- **Cleanup**: Use Azure Automation to clean up temporary build resources

## Security Considerations

### Network Security

- Build virtual network is isolated from production environments
- Private DNS Resolver provides secure hybrid connectivity
- Network security groups restrict unnecessary traffic

### Identity and Access

- Managed identity eliminates credential management
- Role-based access control (RBAC) provides least privilege access
- Service principals scoped to specific resource groups

### Image Security

- Automated security updates during image creation
- Security baseline configuration applied to all images
- Vulnerability scanning integration available through Azure Security Center

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../deploying-automated-golden-image-pipelines-with-azure-vm-image-builder-and-azure-private-dns-resolver.md)
- [Azure VM Image Builder documentation](https://docs.microsoft.com/azure/virtual-machines/image-builder-overview)
- [Azure Private DNS Resolver documentation](https://docs.microsoft.com/azure/dns/private-resolver-overview)
- [Azure Compute Gallery documentation](https://docs.microsoft.com/azure/virtual-machines/shared-image-galleries)

## Additional Resources

- [Azure VM Image Builder troubleshooting](https://docs.microsoft.com/azure/virtual-machines/image-builder-troubleshoot)
- [Hybrid DNS best practices](https://docs.microsoft.com/azure/dns/private-resolver-hybrid-dns)
- [Azure DevOps integration patterns](https://docs.microsoft.com/azure/devops/pipelines/ecosystems/azure)
- [Golden image security guidelines](https://docs.microsoft.com/azure/security/fundamentals/virtual-machines-overview)