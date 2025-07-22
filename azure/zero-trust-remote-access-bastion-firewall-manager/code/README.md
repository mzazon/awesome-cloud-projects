# Infrastructure as Code for Zero-Trust Remote Access with Bastion and Firewall Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Zero-Trust Remote Access with Bastion and Firewall Manager".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.45 or later installed and configured
- Azure subscription with Contributor role permissions
- PowerShell Core 6.0+ (for some Bicep features) or Bash shell
- Understanding of Azure networking concepts (VNets, peering, NSGs)
- Knowledge of zero-trust security principles
- Estimated cost: ~$300/month (Bastion Standard: ~$140, Firewall Premium: ~$875, adjust based on usage)

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension installed
- Visual Studio Code with Bicep extension (recommended for development)

#### For Terraform
- Terraform v1.0+ installed
- Azure CLI authenticated (`az login`)

## Architecture Overview

This implementation deploys:

- **Hub Virtual Network** with Azure Bastion and Azure Firewall subnets
- **Azure Bastion Standard SKU** for secure remote access
- **Azure Firewall Premium** with advanced threat protection
- **Spoke Virtual Networks** for production and development workloads
- **VNet Peering** for hub-spoke connectivity
- **Firewall Manager Policy** with zero-trust rules
- **Network Security Groups** for defense-in-depth
- **Route Tables** for forced tunneling
- **Azure Policy** for compliance enforcement
- **Log Analytics Workspace** for monitoring and threat detection

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Review and customize parameters (optional)
# Edit parameters.json to match your requirements

# Deploy the infrastructure
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment progress
az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Confirm deployment when prompted
# Type 'yes' to proceed
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export LOCATION="eastus"
export RESOURCE_GROUP="rg-zerotrust-demo"

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts and wait for completion
```

## Configuration Options

### Bicep Parameters

Key parameters you can customize in `parameters.json`:

```json
{
  "location": "eastus",
  "resourcePrefix": "zerotrust",
  "hubVnetAddressPrefix": "10.0.0.0/16",
  "spoke1VnetAddressPrefix": "10.1.0.0/16",
  "spoke2VnetAddressPrefix": "10.2.0.0/16",
  "bastionSkuName": "Standard",
  "firewallSkuTier": "Premium",
  "enableDiagnosticSettings": true,
  "logRetentionDays": 30
}
```

### Terraform Variables

Key variables you can customize in `terraform.tfvars`:

```hcl
location = "East US"
resource_group_name = "rg-zerotrust-demo"
hub_vnet_address_space = ["10.0.0.0/16"]
spoke1_vnet_address_space = ["10.1.0.0/16"]
spoke2_vnet_address_space = ["10.2.0.0/16"]
bastion_sku = "Standard"
firewall_sku_tier = "Premium"
enable_diagnostics = true
log_retention_days = 30
```

## Validation

After deployment, verify the infrastructure:

### Check Bastion Status

```bash
# Verify Bastion deployment
az network bastion show \
    --name bastion-${RANDOM_SUFFIX} \
    --resource-group ${RESOURCE_GROUP} \
    --query "provisioningState"
```

### Verify VNet Peering

```bash
# Check peering connectivity
az network vnet peering list \
    --resource-group ${RESOURCE_GROUP} \
    --vnet-name vnet-hub \
    --output table
```

### Test Firewall Policy

```bash
# Validate firewall rules
az network firewall policy rule-collection-group show \
    --name rcg-zerotrust \
    --policy-name fwpolicy-zerotrust-${RANDOM_SUFFIX} \
    --resource-group ${RESOURCE_GROUP} \
    --query "ruleCollections[].name"
```

### Verify Policy Compliance

```bash
# Check Azure Policy compliance
az policy state list \
    --resource-group ${RESOURCE_GROUP} \
    --query "[?policyAssignmentName=='nsg-enforcement'].complianceState"
```

## Security Features

This implementation includes:

- **Zero-Trust Network Access**: Azure Bastion eliminates public IP exposure on VMs
- **Centralized Policy Management**: Firewall Manager ensures consistent security policies
- **Defense in Depth**: Multiple security layers including NSGs, firewall rules, and routing
- **Advanced Threat Protection**: Azure Firewall Premium with IDPS and TLS inspection
- **Compliance Enforcement**: Azure Policy prevents non-compliant resource creation
- **Comprehensive Monitoring**: Log Analytics and diagnostic settings for all components

## Cost Optimization

To optimize costs:

1. **Right-size Bastion**: Consider Basic SKU (~$90/month) for smaller deployments
2. **Firewall SKU**: Use Standard SKU (~$395/month) if Premium features aren't required
3. **Scale Units**: Adjust Bastion scale units based on concurrent session requirements
4. **Log Retention**: Configure appropriate retention periods for diagnostic logs
5. **Resource Scheduling**: Consider automation to start/stop non-production resources

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name myResourceGroup \
    --yes \
    --no-wait

# Or delete specific deployment
az deployment group delete \
    --resource-group myResourceGroup \
    --name main
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm destruction when prompted
# Type 'yes' to proceed
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
# Note: This will delete the entire resource group
```

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**
   - Ensure your account has Contributor role on the subscription
   - Verify Azure CLI is authenticated: `az account show`

2. **Address Space Conflicts**
   - Verify VNet address spaces don't overlap with existing networks
   - Check peered networks for address conflicts

3. **Bastion Deployment Failures**
   - Ensure AzureBastionSubnet is exactly /26 or larger
   - Verify subnet name is exactly "AzureBastionSubnet"

4. **Firewall Policy Issues**
   - Check that firewall policy is associated with the firewall
   - Verify rule collection priorities don't conflict

5. **Route Table Problems**
   - Ensure UDRs don't create routing loops
   - Verify next-hop IP addresses are correct

### Diagnostic Commands

```bash
# Check deployment status
az deployment group list \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# View deployment logs
az deployment operation group list \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --output table

# Check resource provisioning states
az resource list \
    --resource-group ${RESOURCE_GROUP} \
    --query "[].{Name:name, Type:type, State:properties.provisioningState}" \
    --output table
```

## Customization

### Adding Additional Spoke Networks

To add more spoke VNets:

1. **Bicep**: Add spoke VNet modules in `main.bicep`
2. **Terraform**: Add spoke VNet resources in `main.tf`
3. **Scripts**: Add spoke creation commands in `deploy.sh`

### Modifying Firewall Rules

Update firewall policies to match your organization's requirements:

1. Edit application rules for specific FQDNs
2. Modify network rules for service endpoints
3. Add DNAT rules for published applications
4. Configure threat intelligence feeds

### Customizing Network Security Groups

Adjust NSG rules based on your security requirements:

1. Modify source address prefixes
2. Add application-specific port rules
3. Configure service tags for Azure services
4. Implement microsegmentation rules

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation for specific resources
3. Consult Azure Well-Architected Framework security guidance
4. Review Azure Bastion and Firewall Manager best practices

## Additional Resources

- [Azure Bastion Documentation](https://docs.microsoft.com/en-us/azure/bastion/)
- [Azure Firewall Manager Overview](https://docs.microsoft.com/en-us/azure/firewall-manager/)
- [Azure Zero Trust Architecture](https://docs.microsoft.com/en-us/security/zero-trust/)
- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)

## Version Information

- Recipe Version: 1.1
- Infrastructure Code Generated: 2025-07-12
- Azure CLI Version Required: 2.45+
- Terraform Version Required: 1.0+
- Bicep Version Required: Latest stable