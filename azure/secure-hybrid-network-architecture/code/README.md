# Infrastructure as Code for Secure Hybrid Network Architecture with VPN Gateway and Private Link

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure Hybrid Network Architecture with VPN Gateway and Private Link".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a secure hybrid network architecture that includes:

- **Hub Virtual Network** with VPN Gateway for encrypted site-to-site connectivity
- **Spoke Virtual Network** with application and private endpoint subnets
- **VNet Peering** between hub and spoke networks with gateway transit
- **Azure VPN Gateway** (Basic SKU) with public IP for on-premises connectivity
- **Azure Key Vault** with RBAC authorization for centralized secret management
- **Azure Storage Account** with public access disabled for private endpoint testing
- **Private DNS Zones** for service resolution (`privatelink.vault.azure.net`, `privatelink.blob.core.windows.net`)
- **Private Endpoints** for Key Vault and Storage Account with DNS integration
- **Test Virtual Machine** with managed identity for connectivity validation

## Prerequisites

### General Requirements
- Azure subscription with Owner or Contributor permissions
- Azure CLI v2.50.0 or later installed and configured
- On-premises VPN device or simulated environment for testing (optional for infrastructure deployment)
- Basic understanding of Azure networking concepts and IPsec VPN fundamentals

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension
- PowerShell 7.0+ or Bash shell

#### For Terraform
- Terraform v1.0+ installed
- Azure CLI authenticated (`az login`)

#### For Bash Scripts
- Bash shell environment
- `openssl` utility for random string generation
- `jq` utility for JSON parsing (recommended)

### Estimated Costs
- **VPN Gateway (Basic SKU)**: ~$35/month (~$0.048/hour)
- **Virtual Machines (Standard_B2s)**: ~$30/month per VM
- **Storage Account (Standard LRS)**: ~$5/month for 100GB
- **Private Endpoints**: ~$7/month per endpoint
- **Total estimated cost**: $150-200/month for complete solution

> **Warning**: VPN Gateway charges apply immediately upon creation. Consider using the Basic SKU for testing to minimize costs.

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Review and customize parameters
# Edit parameters.json file to adjust resource names and settings

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-hybrid-network \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment progress
az deployment group show \
    --resource-group rg-hybrid-network \
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
terraform plan -var-file="terraform.tfvars"

# Apply the configuration
terraform apply -var-file="terraform.tfvars"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-hybrid-network-demo"
export LOCATION="eastus"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
az resource list --resource-group $RESOURCE_GROUP --output table
```

## Configuration Options

### Customizable Parameters

| Parameter | Description | Default Value | Bicep Variable | Terraform Variable |
|-----------|-------------|---------------|----------------|-------------------|
| Resource Group | Target resource group name | `rg-hybrid-network` | `resourceGroupName` | `resource_group_name` |
| Location | Azure region for deployment | `eastus` | `location` | `location` |
| Hub VNet CIDR | Hub virtual network address space | `10.0.0.0/16` | `hubVnetAddressPrefix` | `hub_vnet_address_space` |
| Spoke VNet CIDR | Spoke virtual network address space | `10.1.0.0/16` | `spokeVnetAddressPrefix` | `spoke_vnet_address_space` |
| VPN Gateway SKU | VPN Gateway performance tier | `Basic` | `vpnGatewaySku` | `vpn_gateway_sku` |
| VM Admin Username | Test VM administrator username | `azureuser` | `vmAdminUsername` | `vm_admin_username` |
| Environment Tag | Environment tag for resources | `demo` | `environmentTag` | `environment_tag` |

### Security Configurations

The solution implements several security best practices:

- **Network Isolation**: Separate subnets for applications and private endpoints
- **Zero Trust Access**: Private endpoints eliminate internet exposure for PaaS services
- **Identity-Based Authentication**: Managed identities for service-to-service authentication
- **Encryption**: IPsec VPN tunnels for encrypted hybrid connectivity
- **Least Privilege**: RBAC roles with minimal required permissions
- **Private DNS**: Custom DNS zones for private endpoint resolution

## Validation & Testing

### Post-Deployment Verification

1. **Check VPN Gateway Status**:
   ```bash
   # Verify VPN Gateway deployment
   az network vnet-gateway show \
       --resource-group $RESOURCE_GROUP \
       --name vpngw-demo \
       --query '{Name:name,State:provisioningState,SKU:sku.name}' \
       --output table
   ```

2. **Test Private Endpoint Resolution**:
   ```bash
   # Test Key Vault private endpoint DNS resolution
   az vm run-command invoke \
       --resource-group $RESOURCE_GROUP \
       --name vm-test \
       --command-id RunShellScript \
       --scripts "nslookup kv-demo.vault.azure.net"
   ```

3. **Validate Service Connectivity**:
   ```bash
   # Create and retrieve test secret via private endpoint
   az keyvault secret set \
       --vault-name kv-demo \
       --name test-secret \
       --value "Private endpoint test"
   
   az keyvault secret show \
       --vault-name kv-demo \
       --name test-secret \
       --query value --output tsv
   ```

4. **Verify Network Security**:
   ```bash
   # Confirm storage account blocks public access
   az storage account show \
       --resource-group $RESOURCE_GROUP \
       --name stdemo \
       --query 'networkRuleSet.defaultAction' --output tsv
   ```

### Connectivity Testing from On-Premises

To test the complete hybrid connectivity:

1. Configure your on-premises VPN device with the VPN Gateway's public IP
2. Establish IPsec tunnel using pre-shared key
3. Test connectivity to spoke network resources (10.1.0.0/16)
4. Verify private endpoint resolution from on-premises DNS

## Troubleshooting

### Common Issues

1. **VPN Gateway Deployment Timeout**:
   - VPN Gateway creation takes 20-45 minutes
   - Monitor deployment status with `az network vnet-gateway show`
   - Ensure sufficient quota for VPN Gateway in selected region

2. **Private Endpoint DNS Resolution**:
   - Verify private DNS zones are linked to both hub and spoke VNets
   - Check that DNS records point to correct private IP addresses
   - Ensure VM uses Azure DNS (168.63.129.16) for resolution

3. **Managed Identity Authentication**:
   - Verify VM has system-assigned managed identity enabled
   - Check RBAC role assignments on Key Vault
   - Ensure Key Vault has RBAC authorization enabled

4. **Network Connectivity**:
   - Verify VNet peering is configured with gateway transit
   - Check network security group rules allow required traffic
   - Validate route tables for proper traffic routing

### Diagnostic Commands

```bash
# Check resource deployment status
az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name main \
    --query "properties.{State:provisioningState,Timestamp:timestamp}"

# Verify VNet peering status
az network vnet peering list \
    --resource-group $RESOURCE_GROUP \
    --vnet-name vnet-hub \
    --output table

# Check private endpoint connections
az network private-endpoint list \
    --resource-group $RESOURCE_GROUP \
    --query "[].{Name:name,State:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" \
    --output table

# Monitor VPN Gateway metrics
az monitor metrics list \
    --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworkGateways/vpngw-demo" \
    --metric "AverageBandwidth" \
    --interval PT1H
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name $RESOURCE_GROUP \
    --yes \
    --no-wait

# Monitor deletion progress
az group show \
    --name $RESOURCE_GROUP \
    --query "properties.provisioningState" 2>/dev/null || echo "Resource group deleted"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var-file="terraform.tfvars"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
az resource list --resource-group $RESOURCE_GROUP --output table 2>/dev/null || echo "All resources cleaned up"
```

### Manual Cleanup (if needed)

```bash
# Delete VPN Gateway first (takes 10-20 minutes)
az network vnet-gateway delete \
    --resource-group $RESOURCE_GROUP \
    --name vpngw-demo \
    --no-wait

# Delete other resources
az keyvault delete --name kv-demo --resource-group $RESOURCE_GROUP
az storage account delete --name stdemo --resource-group $RESOURCE_GROUP --yes

# Finally delete resource group
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

## Cost Optimization

### Cost-Saving Recommendations

1. **VPN Gateway SKU Selection**:
   - Use Basic SKU ($35/month) for development/testing
   - Upgrade to VpnGw1+ ($140+/month) only for production with high throughput needs

2. **Resource Lifecycle Management**:
   - Delete resources when not in use, especially VPN Gateway
   - Use Azure DevTest subscription discounts if available
   - Consider scheduled shutdown for test VMs

3. **Storage Optimization**:
   - Use Standard LRS for non-critical data
   - Implement lifecycle policies for blob storage
   - Monitor storage usage and delete unnecessary data

4. **Regional Considerations**:
   - Deploy in cost-effective regions (avoid premium regions unless required)
   - Consider data transfer costs for hybrid scenarios

### Cost Monitoring

```bash
# Check current month costs for resource group
az consumption usage list \
    --start-date $(date -d "$(date +%Y-%m-01)" +%Y-%m-%d) \
    --end-date $(date +%Y-%m-%d) \
    --query "[?contains(instanceName, '$RESOURCE_GROUP')]"

# Set up budget alerts (requires additional configuration)
az consumption budget create \
    --budget-name hybrid-network-budget \
    --amount 200 \
    --time-grain Monthly \
    --time-period start-date=$(date +%Y-%m-01) \
    --resource-group $RESOURCE_GROUP
```

## Security Hardening

### Additional Security Measures

1. **Network Security Groups**:
   - Implement restrictive NSG rules for application subnet
   - Use application security groups for micro-segmentation
   - Enable NSG flow logs for security monitoring

2. **Azure Firewall Integration**:
   - Deploy Azure Firewall in hub VNet for advanced threat protection
   - Configure IDPS and URL filtering rules
   - Implement forced tunneling for internet-bound traffic

3. **Key Vault Security**:
   - Enable soft delete and purge protection
   - Use customer-managed keys for additional encryption
   - Implement access policies with time-based restrictions

4. **Monitoring and Alerting**:
   - Enable Azure Monitor and Log Analytics integration
   - Configure security alerts for suspicious activities
   - Implement compliance monitoring with Azure Policy

## Extensions and Integration

### Common Integration Scenarios

1. **ExpressRoute Coexistence**:
   - Add ExpressRoute gateway to hub VNet
   - Configure route precedence and failover scenarios
   - Implement BGP routing for dynamic path selection

2. **Multi-Spoke Architecture**:
   - Create additional spoke VNets for different application tiers
   - Implement hub-spoke connectivity with shared services
   - Use Azure Firewall for inter-spoke communication

3. **Hybrid Identity Integration**:
   - Connect Azure AD with on-premises Active Directory
   - Implement Azure AD Domain Services for managed domain
   - Configure conditional access policies for hybrid access

4. **Disaster Recovery**:
   - Replicate architecture to secondary Azure region
   - Implement Azure Site Recovery for VM protection
   - Configure cross-region VNet peering for backup connectivity

## Support and Documentation

### Official Azure Documentation
- [Azure VPN Gateway Documentation](https://docs.microsoft.com/en-us/azure/vpn-gateway/)
- [Azure Private Link Documentation](https://docs.microsoft.com/en-us/azure/private-link/)
- [Azure Virtual Network Documentation](https://docs.microsoft.com/en-us/azure/virtual-network/)
- [Azure Key Vault Documentation](https://docs.microsoft.com/en-us/azure/key-vault/)

### Best Practices References
- [Azure Architecture Center - Hybrid Networks](https://docs.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/)
- [Azure Security Best Practices](https://docs.microsoft.com/en-us/azure/security/fundamentals/network-best-practices)
- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/well-architected/)

### Community Resources
- [Azure VPN Gateway Troubleshooting](https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-troubleshoot)
- [Private Link Service Limits](https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/azure-subscription-service-limits#private-link-limits)

For issues with this infrastructure code, refer to the original recipe documentation or the official Azure documentation links provided above.