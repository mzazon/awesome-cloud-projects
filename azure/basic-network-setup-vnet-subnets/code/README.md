# Infrastructure as Code for Basic Network Setup with Virtual Network and Subnets

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Basic Network Setup with Virtual Network and Subnets".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### Common Requirements
- Azure CLI installed and configured (version 2.57 or later)
- Active Azure subscription with appropriate permissions
- Permissions to create Resource Groups, Virtual Networks, and Network Security Groups
- Basic understanding of networking concepts (CIDR notation, subnetting)

### Tool-Specific Requirements

#### For Bicep
- Azure CLI with Bicep extension (automatically installed with latest Azure CLI)
- No additional installations required

#### For Terraform
- Terraform installed (version 1.0 or later)
- Azure CLI authenticated with `az login`

#### For Bash Scripts
- Bash shell environment (Linux, macOS, or Windows with WSL)
- OpenSSL for random string generation

## Quick Start

### Using Bicep (Recommended)

```bash
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-basic-network \
    --template-file main.bicep \
    --parameters location=eastus

# Or create resource group and deploy in one command
az deployment sub create \
    --location eastus \
    --template-file main.bicep \
    --parameters resourceGroupName=rg-basic-network location=eastus
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# When prompted, type 'yes' to confirm deployment
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure location and naming
```

## Configuration Options

### Bicep Parameters

The Bicep template supports the following parameters:

- `location`: Azure region for deployment (default: eastus)
- `resourceGroupName`: Name of the resource group (when using subscription-level deployment)
- `vnetName`: Virtual Network name (default: auto-generated with suffix)
- `vnetAddressSpace`: VNet address space (default: 10.0.0.0/16)
- `environment`: Environment tag (default: demo)
- `purpose`: Purpose tag (default: recipe)

### Terraform Variables

The Terraform configuration supports these variables:

- `location`: Azure region (default: East US)
- `resource_group_name`: Resource group name (default: auto-generated)
- `vnet_address_space`: VNet CIDR block (default: ["10.0.0.0/16"])
- `subnet_configs`: Subnet configuration map with names and address prefixes
- `tags`: Resource tags map

### Bash Script Environment Variables

Set these environment variables before running the scripts:

```bash
export LOCATION="eastus"                    # Azure region
export RESOURCE_GROUP="rg-basic-network"   # Resource group name
export VNET_NAME="vnet-basic-network"      # Virtual network name
```

## Architecture Deployed

The infrastructure code deploys:

1. **Resource Group**: Container for all networking resources
2. **Virtual Network**: Primary network with 10.0.0.0/16 address space
3. **Three Subnets**:
   - Frontend subnet (10.0.1.0/24)
   - Backend subnet (10.0.2.0/24)
   - Database subnet (10.0.3.0/24)
4. **Network Security Groups**: One for each subnet with appropriate rules
5. **NSG Associations**: Security groups attached to respective subnets

## Security Configuration

### Network Security Group Rules

- **Frontend NSG**: Allows HTTP traffic (port 80) from any source
- **Backend NSG**: Allows traffic on port 8080 from frontend subnet only
- **Database NSG**: Allows PostgreSQL traffic (port 5432) from backend subnet only

### Default Security

All NSGs include Azure's default security rules that:
- Allow VNet-to-VNet communication
- Allow Azure Load Balancer traffic
- Deny all other inbound traffic
- Allow all outbound traffic

## Validation

After deployment, verify the infrastructure:

```bash
# Check Virtual Network
az network vnet show \
    --resource-group <resource-group-name> \
    --name <vnet-name> \
    --output table

# List all subnets
az network vnet subnet list \
    --resource-group <resource-group-name> \
    --vnet-name <vnet-name> \
    --output table

# Verify NSG associations
az network vnet subnet show \
    --resource-group <resource-group-name> \
    --vnet-name <vnet-name> \
    --name <subnet-name> \
    --query "networkSecurityGroup.id"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name <resource-group-name> \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# When prompted, type 'yes' to confirm destruction
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Cost Considerations

- **Virtual Networks**: Free of charge
- **Subnets**: Free of charge
- **Network Security Groups**: Free of charge
- **Data Transfer**: Standard Azure data transfer rates apply for traffic between regions

This foundational networking setup incurs **no additional charges** beyond standard Azure data transfer costs.

## Customization

### Adding Additional Subnets

To add more subnets, modify the configuration files:

#### Bicep
Add subnet definitions in the `subnets` array within `main.bicep`

#### Terraform
Extend the `subnet_configs` variable in `terraform.tfvars` or `variables.tf`

#### Bash Scripts
Add subnet creation commands in the deployment script

### Modifying Security Rules

Update NSG rule definitions in the respective IaC files to match your security requirements. Consider:
- Source IP ranges
- Port ranges
- Protocol types (TCP, UDP, Any)
- Rule priorities (100-4096)

### Changing Address Spaces

Modify the VNet and subnet CIDR blocks to match your network design:
- Ensure subnets don't overlap
- Plan for future growth
- Consider integration with on-premises networks

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**: Ensure your account has Contributor role on the subscription or resource group
2. **Resource Name Conflicts**: Use unique suffixes or modify naming patterns
3. **Address Space Conflicts**: Verify CIDR blocks don't conflict with existing networks
4. **Quota Limits**: Check Azure subscription limits for VNets and NSGs

### Debug Commands

```bash
# Check Azure CLI authentication
az account show

# List available locations
az account list-locations --output table

# Verify resource group exists
az group exists --name <resource-group-name>

# Check resource deployment status
az deployment group show \
    --resource-group <resource-group-name> \
    --name <deployment-name>
```

## Best Practices

1. **Naming Conventions**: Use consistent, descriptive resource names
2. **Tagging Strategy**: Apply comprehensive tags for cost tracking and governance
3. **Security**: Implement least-privilege access in NSG rules
4. **Documentation**: Maintain infrastructure documentation alongside code
5. **Version Control**: Store IaC files in version control systems
6. **Testing**: Validate deployments in non-production environments first

## Next Steps

After deploying this foundational network:

1. Deploy virtual machines or container instances in the subnets
2. Configure Azure Bastion for secure management access
3. Implement VNet peering for multi-VNet architectures
4. Add Azure Firewall for advanced security filtering
5. Configure Network Watcher for monitoring and diagnostics

## Support

For issues with this infrastructure code:
- Refer to the original recipe documentation
- Consult Azure networking documentation
- Check Azure CLI and tool-specific documentation
- Review Azure subscription limits and quotas

For Azure-specific guidance, visit the [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/well-architected/) and [Azure networking best practices](https://learn.microsoft.com/en-us/azure/security/fundamentals/network-best-practices).