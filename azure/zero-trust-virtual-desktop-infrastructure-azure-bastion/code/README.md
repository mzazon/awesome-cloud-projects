# Infrastructure as Code for Zero-Trust Virtual Desktop Infrastructure with Azure Virtual Desktop and Bastion

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Zero-Trust Virtual Desktop Infrastructure with Azure Virtual Desktop and Bastion".

## Available Implementations

- **Bicep**: Azure native infrastructure as code language
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.61.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Virtual Network and subnet creation
  - Virtual Machine deployment
  - Azure Virtual Desktop resource management
  - Azure Bastion deployment
  - Azure Key Vault management
  - Network Security Group configuration
- Sufficient Azure quota for:
  - Standard_D4s_v3 virtual machines (minimum 2 instances)
  - Standard public IP addresses
  - Azure Bastion Basic SKU
  - Standard Key Vault

## Quick Start

### Using Bicep

```bash
# Navigate to Bicep directory
cd bicep/

# Review and customize parameters
cp parameters.json.example parameters.json
# Edit parameters.json with your desired values

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-avd-infra" \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment progress
az deployment group show \
    --resource-group "rg-avd-infra" \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment logs
tail -f deployment.log
```

## Architecture Components

This IaC deployment creates the following Azure resources:

- **Resource Group**: Container for all AVD resources
- **Virtual Network**: Network foundation with dedicated subnets
- **Network Security Groups**: Traffic filtering and security rules
- **Azure Bastion**: Secure administrative access without public IPs
- **Azure Virtual Desktop Host Pool**: Multi-session desktop environment
- **Session Host VMs**: Windows 11 Enterprise multi-session virtual machines
- **Application Group**: Desktop application collection
- **Workspace**: User-facing interface for virtual desktop access
- **Azure Key Vault**: Certificate and secret management

## Configuration Parameters

### Bicep Parameters

Key parameters in `parameters.json`:

```json
{
  "location": "eastus",
  "resourcePrefix": "avd-demo",
  "virtualNetworkAddressPrefix": "10.0.0.0/16",
  "avdSubnetAddressPrefix": "10.0.1.0/24",
  "bastionSubnetAddressPrefix": "10.0.2.0/27",
  "vmSize": "Standard_D4s_v3",
  "maxSessionLimit": 10,
  "adminUsername": "avdadmin"
}
```

### Terraform Variables

Key variables in `terraform.tfvars`:

```hcl
location              = "East US"
resource_group_name   = "rg-avd-infra"
resource_prefix       = "avd-demo"
vnet_address_space    = ["10.0.0.0/16"]
avd_subnet_prefix     = "10.0.1.0/24"
bastion_subnet_prefix = "10.0.2.0/27"
vm_size              = "Standard_D4s_v3"
session_host_count   = 2
max_session_limit    = 10
admin_username       = "avdadmin"
```

## Post-Deployment Configuration

After successful deployment:

1. **Assign Users to Application Group**:
   ```bash
   # Add users to the desktop application group
   az role assignment create \
       --assignee "user@domain.com" \
       --role "Desktop Virtualization User" \
       --scope "/subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.DesktopVirtualization/applicationGroups/{app-group-name}"
   ```

2. **Configure Session Host Registration**:
   - Session hosts will automatically register with the host pool
   - Monitor registration status in Azure portal or via CLI

3. **Access Virtual Desktop**:
   - Users can access desktops via https://rdweb.wvd.microsoft.com
   - Or through the Windows Desktop client application

4. **Administrative Access via Bastion**:
   - Navigate to Azure Portal > Virtual Machines
   - Select session host VM > Connect > Bastion
   - Use admin credentials to access session hosts securely

## Validation Commands

Verify successful deployment:

```bash
# Check host pool status
az desktopvirtualization hostpool show \
    --name "hp-multi-session-{suffix}" \
    --resource-group "rg-avd-infra" \
    --query '{name:name,hostPoolType:hostPoolType,loadBalancerType:loadBalancerType}'

# List session hosts
az desktopvirtualization sessionhost list \
    --host-pool-name "hp-multi-session-{suffix}" \
    --resource-group "rg-avd-infra" \
    --query '[].{name:name,status:status,sessions:sessions}'

# Verify Bastion deployment
az network bastion show \
    --name "bastion-avd-{suffix}" \
    --resource-group "rg-avd-infra" \
    --query '{name:name,provisioningState:provisioningState}'

# Check workspace configuration
az desktopvirtualization workspace show \
    --name "ws-remote-desktop-{suffix}" \
    --resource-group "rg-avd-infra" \
    --query '{name:name,applicationGroupReferences:applicationGroupReferences}'
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name "rg-avd-infra" \
    --yes \
    --no-wait

# Verify deletion
az group show \
    --name "rg-avd-infra" \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Security Considerations

This implementation includes several security best practices:

- **Network Isolation**: Session hosts deployed in dedicated subnet without public IPs
- **Secure Access**: Azure Bastion provides encrypted administrative access
- **Traffic Filtering**: Network Security Groups control inbound and outbound traffic
- **Certificate Management**: Azure Key Vault handles SSL certificates and secrets
- **Identity Integration**: Azure Active Directory provides user authentication
- **Encryption**: Data encrypted at rest and in transit

## Cost Optimization

To optimize costs:

1. **VM Sizing**: Adjust VM sizes based on actual user requirements
2. **Auto-scaling**: Implement Azure Automation for start/stop schedules
3. **Reserved Instances**: Use Azure Reserved VM Instances for predictable workloads
4. **Session Limits**: Configure appropriate session limits per host
5. **Monitoring**: Use Azure Cost Management to track and optimize expenses

## Troubleshooting

Common issues and solutions:

1. **Session Host Registration Failures**:
   - Verify network connectivity to Azure Virtual Desktop services
   - Check registration token validity
   - Review VM extension deployment logs

2. **Bastion Connection Issues**:
   - Ensure proper subnet configuration (/27 minimum)
   - Verify NSG rules allow Bastion traffic
   - Check Azure Bastion service status

3. **User Access Problems**:
   - Verify user assignments to application groups
   - Check Azure AD authentication configuration
   - Review workspace application group references

4. **Performance Issues**:
   - Monitor VM resource utilization
   - Adjust session limits per host
   - Consider scaling up VM sizes or adding hosts

## Customization

Common customizations:

- **Additional Session Hosts**: Modify `session_host_count` parameter
- **Different VM Sizes**: Update `vm_size` parameter based on workload requirements
- **Custom Network Ranges**: Adjust subnet address prefixes
- **Enhanced Security**: Add custom NSG rules or integrate with Azure Firewall
- **Monitoring**: Add Azure Monitor and Log Analytics integration
- **Backup**: Configure Azure Backup for session host VMs

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure Virtual Desktop documentation: https://learn.microsoft.com/en-us/azure/virtual-desktop/
3. Consult Azure Bastion documentation: https://learn.microsoft.com/en-us/azure/bastion/
4. Visit Azure support resources for additional help

## Estimated Costs

Approximate monthly costs (East US region):

- **Session Host VMs (2x Standard_D4s_v3)**: $400-500
- **Azure Bastion (Basic)**: $140
- **Storage (OS Disks)**: $20-30
- **Networking**: $10-20
- **Key Vault**: $1-5

**Total Estimated Cost**: $570-695/month

> **Note**: Costs vary by region, usage patterns, and additional services. Use Azure Pricing Calculator for accurate estimates.