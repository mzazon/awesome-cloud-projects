# Infrastructure as Code for Hybrid Network Threat Protection with Premium Firewall

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Hybrid Network Threat Protection with Premium Firewall".

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.55.0 or later installed and configured
- Azure subscription with appropriate permissions for creating networking and security resources
- Understanding of hybrid networking concepts, BGP routing, and Azure security principles
- Existing on-premises network infrastructure with BGP routing capabilities
- ExpressRoute circuit already provisioned through a connectivity provider (for full implementation)
- Estimated cost: $800-1200 USD per month for Azure Firewall Premium, ExpressRoute Gateway, and monitoring resources

> **Warning**: Azure Firewall Premium and ExpressRoute Gateway are premium services that incur significant costs. Review the [Azure Firewall pricing](https://azure.microsoft.com/pricing/details/azure-firewall/) and [ExpressRoute pricing](https://azure.microsoft.com/pricing/details/expressroute/) before deploying to production environments.

## Architecture Overview

This implementation deploys a comprehensive hybrid network security architecture that includes:

- **Hub Virtual Network** (10.0.0.0/16) with specialized subnets for Azure Firewall and ExpressRoute Gateway
- **Spoke Virtual Network** (10.1.0.0/16) for application workloads
- **Azure Firewall Premium** with advanced threat protection, IDPS, and TLS inspection
- **ExpressRoute Gateway** for private connectivity to on-premises networks
- **Log Analytics Workspace** for comprehensive monitoring and security analytics
- **Network Security Rules** for controlled hybrid traffic flow
- **User-Defined Routes** for traffic steering through the firewall

## Quick Start

### Using Bicep

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Login to Azure (if not already authenticated)
az login

# Set your subscription (replace with your subscription ID)
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-hybrid-security" \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters hubVnetPrefix=10.0.0.0/16 \
    --parameters spokeVnetPrefix=10.1.0.0/16

# Monitor deployment progress
az deployment group show \
    --resource-group "rg-hybrid-security" \
    --name "main" \
    --query "properties.provisioningState"
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

# Confirm deployment by typing 'yes' when prompted
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts for configuration options
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default Value | Required |
|-----------|-------------|---------------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `hubVnetPrefix` | Hub virtual network address space | `10.0.0.0/16` | Yes |
| `spokeVnetPrefix` | Spoke virtual network address space | `10.1.0.0/16` | Yes |
| `firewallSubnetPrefix` | Azure Firewall subnet address space | `10.0.1.0/24` | Yes |
| `gatewaySubnetPrefix` | ExpressRoute Gateway subnet address space | `10.0.2.0/24` | Yes |
| `workloadSubnetPrefix` | Workload subnet address space | `10.1.1.0/24` | Yes |
| `enableDiagnostics` | Enable diagnostic logging | `true` | No |
| `logRetentionDays` | Log retention period in days | `30` | No |

### Terraform Variables

| Variable | Description | Default Value | Required |
|----------|-------------|---------------|----------|
| `resource_group_name` | Name of the resource group | `rg-hybrid-security` | Yes |
| `location` | Azure region for deployment | `East US` | Yes |
| `hub_vnet_prefix` | Hub virtual network address space | `["10.0.0.0/16"]` | Yes |
| `spoke_vnet_prefix` | Spoke virtual network address space | `["10.1.0.0/16"]` | Yes |
| `firewall_subnet_prefix` | Azure Firewall subnet address space | `["10.0.1.0/24"]` | Yes |
| `gateway_subnet_prefix` | ExpressRoute Gateway subnet address space | `["10.0.2.0/24"]` | Yes |
| `workload_subnet_prefix` | Workload subnet address space | `["10.1.1.0/24"]` | Yes |
| `enable_diagnostics` | Enable diagnostic logging | `true` | No |
| `log_retention_days` | Log retention period in days | `30` | No |
| `tags` | Resource tags | `{}` | No |

## Post-Deployment Configuration

### ExpressRoute Circuit Connection

After deploying the infrastructure, you'll need to connect your ExpressRoute circuit to the gateway:

```bash
# Replace with your actual ExpressRoute circuit resource ID
CIRCUIT_ID="/subscriptions/your-subscription-id/resourceGroups/rg-expressroute/providers/Microsoft.Network/expressRouteCircuits/your-circuit-name"

# Create the connection
az network vpn-connection create \
    --resource-group "rg-hybrid-security" \
    --name "connection-expressroute" \
    --vnet-gateway1 "ergw-your-suffix" \
    --express-route-circuit2 "${CIRCUIT_ID}" \
    --location "eastus"
```

### Firewall Rules Customization

The deployment includes basic security rules for hybrid connectivity. Customize these rules based on your specific requirements:

```bash
# Add additional network rules
az network firewall policy rule-collection-group collection add-filter-collection \
    --resource-group "rg-hybrid-security" \
    --policy-name "azfw-policy-your-suffix" \
    --rule-collection-group-name "HybridNetworkRules" \
    --name "CustomApplicationRules" \
    --collection-priority 1300 \
    --action Allow \
    --rule-name "AllowCustomApp" \
    --rule-type ApplicationRule \
    --target-fqdns "*.yourdomain.com" \
    --source-addresses "10.1.0.0/16" \
    --protocols "https=443"
```

## Monitoring and Validation

### Verify Deployment

```bash
# Check Azure Firewall status
az network firewall show \
    --resource-group "rg-hybrid-security" \
    --name "azfw-premium-your-suffix" \
    --query "{name:name, tier:sku.tier, provisioningState:provisioningState}"

# Check ExpressRoute Gateway status
az network vnet-gateway show \
    --resource-group "rg-hybrid-security" \
    --name "ergw-your-suffix" \
    --query "{name:name, gatewayType:gatewayType, provisioningState:provisioningState}"

# Verify virtual network peering
az network vnet peering list \
    --resource-group "rg-hybrid-security" \
    --vnet-name "vnet-hub-your-suffix" \
    --query "[].{name:name, peeringState:peeringState}"
```

### Log Analytics Queries

Access the Log Analytics workspace to monitor firewall activity:

```kusto
// View recent firewall network rule logs
AzureDiagnostics
| where Category == "AzureFirewallNetworkRule"
| order by TimeGenerated desc
| take 100

// Monitor threat intelligence alerts
AzureDiagnostics
| where Category == "AZFWThreatIntel"
| order by TimeGenerated desc
| take 100

// Check IDPS signature matches
AzureDiagnostics
| where Category == "AZFWIdpsSignature"
| order by TimeGenerated desc
| take 100
```

## Security Considerations

### Network Security

- Azure Firewall Premium provides advanced threat protection with IDPS, URL filtering, and TLS inspection
- All traffic between on-premises and Azure resources is routed through the firewall
- Network security rules follow the principle of least privilege
- Comprehensive logging enables security monitoring and incident response

### Access Control

- Use Azure Role-Based Access Control (RBAC) to limit administrative access
- Implement service principals for automation and CI/CD integration
- Enable Azure Active Directory integration for centralized identity management

### Compliance

- Log retention is configured for 30 days (customizable)
- Diagnostic settings capture all relevant security events
- Network traffic inspection capabilities support compliance requirements

## Cleanup

### Using Bicep

```bash
# Delete the entire resource group and all resources
az group delete \
    --name "rg-hybrid-security" \
    --yes \
    --no-wait

# Monitor deletion progress
az group show \
    --name "rg-hybrid-security" \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction by typing 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

1. **ExpressRoute Gateway Deployment Timeout**
   - Gateway deployment typically takes 15-20 minutes
   - Use `--no-wait` flag and monitor progress separately
   - Verify subnet configuration meets Azure requirements

2. **Firewall Policy Configuration Errors**
   - Ensure rule collection priorities don't conflict
   - Verify source and destination address formats
   - Check protocol and port specifications

3. **Virtual Network Peering Issues**
   - Verify address spaces don't overlap
   - Check that gateway transit settings are correct
   - Ensure both sides of peering are configured

4. **Log Analytics Connectivity Problems**
   - Verify workspace exists and is accessible
   - Check diagnostic settings configuration
   - Validate Azure Monitor permissions

### Support Resources

- [Azure Firewall Premium Documentation](https://docs.microsoft.com/en-us/azure/firewall/premium-features)
- [ExpressRoute Documentation](https://docs.microsoft.com/en-us/azure/expressroute/)
- [Azure Virtual Network Documentation](https://docs.microsoft.com/en-us/azure/virtual-network/)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)

## Cost Optimization

### Resource Scaling

- Azure Firewall Premium: Consider using Standard SKU for non-production environments
- ExpressRoute Gateway: Choose appropriate SKU based on bandwidth requirements
- Log Analytics: Implement data retention policies to control storage costs

### Monitoring Costs

- Use Azure Cost Management to track spending
- Set up billing alerts for unexpected cost increases
- Review resource utilization regularly and optimize as needed

## Customization

### Network Addressing

Modify the address spaces in the variables to match your network requirements:

```bash
# Example: Using different address spaces
hub_vnet_prefix = ["172.16.0.0/16"]
spoke_vnet_prefix = ["172.17.0.0/16"]
firewall_subnet_prefix = ["172.16.1.0/24"]
gateway_subnet_prefix = ["172.16.2.0/24"]
workload_subnet_prefix = ["172.17.1.0/24"]
```

### Security Rules

Customize firewall rules based on your specific application requirements:

```bash
# Add application-specific rules
# Modify the rule collections in the IaC templates
# Configure custom threat intelligence feeds
# Implement custom IDPS signatures
```

### Monitoring

Extend monitoring capabilities with custom dashboards and alerts:

```bash
# Create custom Azure Monitor workbooks
# Configure alert rules for security events
# Implement automated response workflows
# Integrate with external SIEM systems
```

## Additional Resources

- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)
- [Azure Security Best Practices](https://docs.microsoft.com/en-us/azure/security/fundamentals/best-practices-and-patterns)
- [Azure Networking Best Practices](https://docs.microsoft.com/en-us/azure/security/fundamentals/network-best-practices)
- [Hub-spoke network topology](https://docs.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)

---

**Note**: This infrastructure deployment creates premium Azure services that incur significant costs. Always review pricing and consider using development/test subscriptions for initial deployment and testing.