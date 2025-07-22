# Infrastructure as Code for Intelligent DDoS Protection with Adaptive BGP Routing

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent DDoS Protection with Adaptive BGP Routing".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (declarative)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (or Azure Cloud Shell)
- Azure subscription with Owner or Contributor permissions for resource group management
- Basic understanding of Azure networking concepts (VNets, subnets, BGP routing)
- Familiarity with network security principles and DDoS attack patterns
- Estimated cost: $150-200 per month for DDoS Protection Standard plus compute and networking costs

## Quick Start

### Using Bicep

```bash
cd bicep/

# Login to Azure (if not already authenticated)
az login

# Set your subscription (replace with your subscription ID)
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-adaptive-network-security \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment progress
az deployment group show \
    --resource-group rg-adaptive-network-security \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply

# Confirm when prompted by typing 'yes'
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Run the deployment script
./scripts/deploy.sh

# The script will:
# - Create resource group
# - Deploy DDoS Protection Plan
# - Create hub and spoke VNets with peering
# - Deploy Azure Route Server
# - Configure Azure Firewall
# - Set up monitoring and alerting
```

## Configuration Parameters

The following parameters can be customized in each implementation:

### Common Parameters

- **Resource Group**: `rg-adaptive-network-security`
- **Location**: `East US` (configurable)
- **Hub VNet CIDR**: `10.0.0.0/16`
- **Spoke VNet CIDR**: `10.1.0.0/16`
- **DDoS Protection**: Standard tier enabled
- **Monitoring**: Log Analytics workspace with 30-day retention

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "location": "eastus",
  "hubVnetAddressPrefix": "10.0.0.0/16",
  "spokeVnetAddressPrefix": "10.1.0.0/16",
  "logRetentionDays": 30
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` or use CLI variables:

```bash
terraform apply \
  -var="location=eastus" \
  -var="hub_vnet_address_space=10.0.0.0/16" \
  -var="spoke_vnet_address_space=10.1.0.0/16"
```

## Deployed Resources

This infrastructure creates the following Azure resources:

### Network Security
- **DDoS Protection Plan (Standard)**: Advanced DDoS protection with always-on monitoring
- **Hub Virtual Network**: Central connectivity with DDoS protection enabled
- **Spoke Virtual Network**: Application workload network
- **VNet Peering**: Secure hub-spoke connectivity
- **Network Security Groups**: Subnet-level security rules

### Routing and Traffic Management
- **Azure Route Server**: BGP-based dynamic routing
- **Azure Firewall**: Application-aware traffic inspection
- **Public IP Addresses**: Standard SKU for Route Server and Firewall

### Monitoring and Alerting
- **Log Analytics Workspace**: Centralized logging and analytics
- **Network Watcher**: Network monitoring and diagnostics
- **Azure Monitor Alert Rules**: DDoS attack detection and traffic volume monitoring
- **Action Groups**: Alert notification configuration

## Security Features

### DDoS Protection Capabilities
- **Always-on Traffic Monitoring**: Continuous analysis of traffic patterns
- **Adaptive Real-time Tuning**: Machine learning-based attack detection
- **Attack Analytics**: Detailed telemetry and reporting
- **Cost Protection**: Financial protection during large-scale attacks

### Network Security Controls
- **BGP Route Advertisement**: Dynamic routing based on security policies
- **Application-layer Inspection**: Deep packet inspection through Azure Firewall
- **Network Segmentation**: Hub-spoke architecture with controlled connectivity
- **Flow Logging**: Detailed network traffic analysis

## Validation and Testing

After deployment, verify the infrastructure:

### Check DDoS Protection Status

```bash
# Verify DDoS Protection Plan
az network ddos-protection show \
    --name ddos-plan-[suffix] \
    --resource-group rg-adaptive-network-security

# Confirm VNet protection is enabled
az network vnet show \
    --name vnet-hub-[suffix] \
    --resource-group rg-adaptive-network-security \
    --query "enableDdosProtection"
```

### Validate Route Server Configuration

```bash
# Check Route Server status
az network routeserver show \
    --name rs-adaptive-[suffix] \
    --resource-group rg-adaptive-network-security \
    --query "provisioningState"

# List BGP peers (if configured)
az network routeserver peering list \
    --routeserver rs-adaptive-[suffix] \
    --resource-group rg-adaptive-network-security
```

### Test Monitoring and Alerting

```bash
# Verify Log Analytics workspace
az monitor log-analytics workspace show \
    --workspace-name law-adaptive-[suffix] \
    --resource-group rg-adaptive-network-security

# List configured alert rules
az monitor metrics alert list \
    --resource-group rg-adaptive-network-security \
    --query "[].{Name:name,Severity:severity,Enabled:enabled}"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-adaptive-network-security \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted by typing 'yes'
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# - Remove alert rules and action groups
# - Delete Route Server and Firewall
# - Remove VNets and DDoS Protection Plan
# - Clean up monitoring resources
# - Delete the resource group
```

## Cost Optimization

### DDoS Protection Standard Pricing
- **Monthly Base Fee**: ~$2,944 per month
- **Per Protected Public IP**: ~$30 per month per IP
- **Cost Protection**: Credits during qualifying attacks

### Resource Optimization Tips
- Use Standard SKU public IPs only where required
- Configure Log Analytics retention based on compliance needs
- Monitor unused Network Security Group rules
- Review firewall rules for optimization opportunities

## Troubleshooting

### Common Issues

**DDoS Protection Plan Creation Fails**
```bash
# Verify subscription quota
az network ddos-protection list --query "length(@)"

# Check resource provider registration
az provider show --namespace Microsoft.Network --query "registrationState"
```

**Route Server Deployment Issues**
```bash
# Verify subnet configuration
az network vnet subnet show \
    --name RouteServerSubnet \
    --vnet-name vnet-hub-[suffix] \
    --resource-group rg-adaptive-network-security \
    --query "addressPrefix"

# Check route server requirements (minimum /27 subnet)
```

**BGP Peering Problems**
```bash
# Verify Route Server is in Succeeded state
az network routeserver show \
    --name rs-adaptive-[suffix] \
    --resource-group rg-adaptive-network-security \
    --query "provisioningState"

# Check ASN configuration (must be 65515 for Azure Route Server)
```

### Support Resources

- [Azure DDoS Protection Documentation](https://docs.microsoft.com/en-us/azure/ddos-protection/)
- [Azure Route Server Documentation](https://docs.microsoft.com/en-us/azure/route-server/)
- [Azure Firewall Documentation](https://docs.microsoft.com/en-us/azure/firewall/)
- [Azure Network Watcher Documentation](https://docs.microsoft.com/en-us/azure/network-watcher/)

## Advanced Configuration

### Custom BGP Configuration

To add custom BGP peers to the Route Server:

```bash
# Add BGP peer
az network routeserver peering create \
    --name "custom-peer" \
    --routeserver rs-adaptive-[suffix] \
    --resource-group rg-adaptive-network-security \
    --peer-asn 65001 \
    --peer-ip 10.0.3.10
```

### Enhanced Monitoring

Add custom alert rules for specific scenarios:

```bash
# Create custom alert for BGP session status
az monitor metrics alert create \
    --name "BGP-Session-Down" \
    --resource-group rg-adaptive-network-security \
    --scopes "/subscriptions/.../providers/Microsoft.Network/virtualHubs/rs-adaptive-[suffix]" \
    --condition "avg BgpSessionAvailability < 100" \
    --description "Alert when BGP session goes down"
```

## Customization

Refer to the variable definitions in each implementation to customize the deployment for your environment:

- **Network Address Spaces**: Modify CIDR blocks to match your network architecture
- **Security Rules**: Customize NSG rules for your security requirements
- **Monitoring Configuration**: Adjust retention periods and alert thresholds
- **Resource Naming**: Update naming conventions to match your standards

## Support

For issues with this infrastructure code, refer to the original recipe documentation or the Azure documentation for specific services. The infrastructure follows Azure Well-Architected Framework principles for security, reliability, and cost optimization.