# Infrastructure as Code for Hybrid DNS Resolution with Private Resolver and Network Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Hybrid DNS Resolution with Private Resolver and Network Manager".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (Bicep language)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Appropriate Azure permissions for creating:
  - DNS Private Resolver and related components
  - Azure Virtual Network Manager
  - Virtual Networks and subnets
  - Private DNS zones and records
  - Storage accounts and private endpoints
- For Terraform: Terraform v1.0+ installed
- For Bicep: Azure CLI with Bicep extension installed
- On-premises network connectivity to Azure (VPN Gateway or ExpressRoute) or Azure VM simulating on-premises environment
- Estimated cost: $50-100/month for DNS Private Resolver, VNet Manager, and supporting infrastructure

## Quick Start

### Using Bicep

```bash
# Navigate to the bicep directory
cd bicep/

# Review and customize parameters
az deployment group create \
    --resource-group rg-hybrid-dns-demo \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts and provide required parameters
```

## Detailed Setup Instructions

### Pre-deployment Configuration

1. **Set up environment variables** (for bash scripts):

   ```bash
   export RESOURCE_GROUP="rg-hybrid-dns-$(openssl rand -hex 3)"
   export LOCATION="eastus"
   export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
   ```

2. **Customize parameters** (for Bicep/Terraform):
   - Edit `bicep/parameters.json` or `terraform/terraform.tfvars`
   - Adjust virtual network address spaces
   - Configure on-premises DNS server IP addresses
   - Set appropriate resource names and locations

### Architecture Overview

The infrastructure deploys:

- **Hub Virtual Network** with DNS resolver subnets
- **Spoke Virtual Networks** for workload placement
- **Azure DNS Private Resolver** with inbound and outbound endpoints
- **Azure Virtual Network Manager** for centralized connectivity
- **Private DNS Zone** for Azure resource resolution
- **DNS Forwarding Ruleset** for on-premises resolution
- **Storage Account with Private Endpoint** for testing
- **Network connectivity** using hub-and-spoke topology

### Network Configuration

The solution creates the following network topology:

- **Hub VNet**: 10.10.0.0/16
  - DNS Inbound Subnet: 10.10.0.0/24
  - DNS Outbound Subnet: 10.10.1.0/24
- **Spoke VNet 1**: 10.20.0.0/16
- **Spoke VNet 2**: 10.30.0.0/16
- **On-premises simulation**: 10.100.0.0/16

## Validation and Testing

After deployment, validate the solution:

1. **Check DNS Private Resolver status**:

   ```bash
   az dns-resolver show \
       --name <dns-resolver-name> \
       --resource-group <resource-group> \
       --query "provisioningState"
   ```

2. **Verify inbound endpoint IP**:

   ```bash
   az dns-resolver inbound-endpoint show \
       --dns-resolver-name <dns-resolver-name> \
       --resource-group <resource-group> \
       --name inbound-endpoint \
       --query "ipConfigurations[0].privateIpAddress"
   ```

3. **Test DNS resolution from Azure VM**:

   ```bash
   # Create test VM and run DNS lookup
   az vm run-command invoke \
       --resource-group <resource-group> \
       --name <test-vm-name> \
       --command-id RunShellScript \
       --scripts "nslookup test-vm.azure.contoso.com"
   ```

4. **Verify Virtual Network Manager connectivity**:

   ```bash
   az network manager list-active-connectivity-config \
       --resource-group <resource-group> \
       --network-manager-name <network-manager-name> \
       --regions <location>
   ```

## Configuration Customization

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "uniqueSuffix": {
      "value": "demo"
    },
    "hubVnetAddressPrefix": {
      "value": "10.10.0.0/16"
    },
    "onPremisesDnsServerIp": {
      "value": "10.100.0.2"
    },
    "privateDnsZoneName": {
      "value": "azure.contoso.com"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
location = "East US"
unique_suffix = "demo"
hub_vnet_address_prefix = "10.10.0.0/16"
spoke1_vnet_address_prefix = "10.20.0.0/16"
spoke2_vnet_address_prefix = "10.30.0.0/16"
onpremises_dns_server_ip = "10.100.0.2"
private_dns_zone_name = "azure.contoso.com"
onpremises_domain_name = "contoso.com"
```

### Environment-Specific Configuration

For different environments (dev/staging/prod):

1. **Development**: Use smaller VM sizes and single-region deployment
2. **Staging**: Include additional monitoring and logging resources
3. **Production**: Enable zone redundancy and cross-region replication

## Cleanup

### Using Bicep

```bash
# Delete the resource group containing all resources
az group delete \
    --name <resource-group-name> \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

### Manual Cleanup Verification

After automated cleanup, verify removal of:

1. Virtual Network Manager configurations and deployments
2. DNS Private Resolver and associated rulesets
3. Private DNS zones and records
4. Virtual networks and subnets
5. Storage accounts and private endpoints

## Troubleshooting

### Common Issues

1. **DNS resolution not working**:
   - Verify DNS Private Resolver provisioning state
   - Check virtual network links to private DNS zones
   - Validate forwarding ruleset configuration

2. **Network connectivity issues**:
   - Confirm Virtual Network Manager deployment status
   - Verify hub-and-spoke topology configuration
   - Check network security group rules

3. **Private endpoint resolution failures**:
   - Validate private DNS zone group configuration
   - Ensure correct private DNS zone for service type
   - Check virtual network links for private DNS zones

4. **On-premises DNS forwarding not working**:
   - Verify on-premises DNS server accessibility
   - Check DNS forwarding rule target configuration
   - Validate network connectivity to outbound endpoint

### Debugging Commands

```bash
# Check resource deployment status
az deployment group show \
    --resource-group <resource-group> \
    --name <deployment-name> \
    --query "properties.provisioningState"

# List all DNS resolver endpoints
az dns-resolver inbound-endpoint list \
    --dns-resolver-name <resolver-name> \
    --resource-group <resource-group>

# Check Virtual Network Manager effective configurations
az network manager list-effective-connectivity-config \
    --resource-group <resource-group> \
    --virtual-network-name <vnet-name>
```

## Security Considerations

- **Network Security**: All DNS traffic remains within private network boundaries
- **Access Control**: Use Azure RBAC for resource access management
- **Encryption**: DNS queries are encrypted in transit within Azure backbone
- **Monitoring**: Enable diagnostic settings for DNS Private Resolver and Virtual Network Manager
- **Compliance**: Solution supports Azure Policy enforcement for governance

## Cost Optimization

- **DNS Private Resolver**: Consumption-based pricing for queries processed
- **Virtual Network Manager**: Charges based on managed virtual networks
- **Private Endpoints**: Standard charges per endpoint and data processing
- **Storage**: Use appropriate storage tiers for cost optimization

Monitor costs using Azure Cost Management and set up budget alerts for proactive cost control.

## Performance Considerations

- **DNS Query Latency**: Expect <10ms additional latency for hybrid resolution
- **Throughput**: DNS Private Resolver supports high query volumes with automatic scaling
- **Caching**: Configure appropriate TTL values for DNS records
- **Network Topology**: Hub-and-spoke design optimizes routing efficiency

## Support and Documentation

- [Azure DNS Private Resolver Documentation](https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-overview)
- [Azure Virtual Network Manager Documentation](https://learn.microsoft.com/en-us/azure/virtual-network-manager/overview)
- [Azure Private DNS Documentation](https://learn.microsoft.com/en-us/azure/dns/private-dns-overview)
- [Azure Networking Best Practices](https://learn.microsoft.com/en-us/azure/architecture/framework/services/networking)

For issues with this infrastructure code, refer to the original recipe documentation or the Azure support channels.