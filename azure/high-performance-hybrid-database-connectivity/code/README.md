# Infrastructure as Code for High-Performance Hybrid Database Connectivity with ExpressRoute

This directory contains Infrastructure as Code (IaC) implementations for the recipe "High-Performance Hybrid Database Connectivity with ExpressRoute".

## Available Implementations

- **Bicep**: Azure's recommended domain-specific language (DSL) for deploying Azure resources
- **Terraform**: Multi-cloud infrastructure as code using the Azure provider
- **Scripts**: Bash deployment and cleanup scripts for manual deployment

## Prerequisites

- Azure CLI v2.61.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - ExpressRoute Gateway creation and management
  - Application Gateway deployment and configuration
  - PostgreSQL Flexible Server provisioning
  - Virtual Network and subnet management
  - Network Security Group configuration
  - Private DNS zone management
- ExpressRoute circuit provisioned by your connectivity provider (required for production use)
- SSL certificate for Application Gateway (can be self-signed for testing)
- Basic understanding of Azure networking, BGP routing, and database connectivity

> **Important**: ExpressRoute circuits require coordination with your connectivity provider and may take 2-4 weeks to provision. This implementation assumes you have an active ExpressRoute circuit or are using ExpressRoute Direct.

## Cost Estimation

Expected monthly costs for this infrastructure:
- ExpressRoute Gateway: $150-300/month (depending on SKU)
- ExpressRoute Circuit: $500-800/month (varies by provider and bandwidth)
- Application Gateway v2: $200-400/month (based on usage)
- PostgreSQL Flexible Server: $100-300/month (depending on compute tier)
- **Total Estimated Cost**: $950-1,800/month

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to the bicep directory
cd bicep/

# Review and customize parameters
cp parameters.json.example parameters.json
# Edit parameters.json with your specific values

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-hybrid-db-connectivity \
    --template-file main.bicep \
    --parameters @parameters.json \
    --confirm-with-what-if

# Monitor deployment progress
az deployment group show \
    --resource-group rg-hybrid-db-connectivity \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
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

# Review configuration variables in deploy.sh
nano scripts/deploy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment progress
# The script will provide status updates throughout deployment
```

## Configuration Parameters

### Required Parameters

- **resourceGroupName**: Name of the resource group for all resources
- **location**: Azure region for resource deployment (e.g., "eastus")
- **vnetAddressPrefix**: Address space for the hub virtual network (e.g., "10.1.0.0/16")
- **expressRouteCircuitId**: Resource ID of your existing ExpressRoute circuit
- **postgresAdminUsername**: Administrator username for PostgreSQL server
- **postgresAdminPassword**: Administrator password for PostgreSQL server (must meet complexity requirements)

### Optional Parameters

- **applicationGatewaySku**: SKU for Application Gateway (default: "WAF_v2")
- **postgresSkuName**: SKU for PostgreSQL Flexible Server (default: "Standard_D2s_v3")
- **postgresTier**: Pricing tier for PostgreSQL (default: "GeneralPurpose")
- **postgresVersion**: PostgreSQL version (default: "14")
- **storageSize**: Storage size in GB for PostgreSQL (default: 128)

## Post-Deployment Configuration

### 1. ExpressRoute Circuit Connection

After deployment, you'll need to configure your ExpressRoute circuit connection:

```bash
# Verify ExpressRoute Gateway deployment
az network vnet-gateway show \
    --name ergw-hub-[suffix] \
    --resource-group rg-hybrid-db-connectivity \
    --query "provisioningState"

# Create connection to your ExpressRoute circuit
az network vpn-connection create \
    --name connection-expressroute \
    --resource-group rg-hybrid-db-connectivity \
    --location eastus \
    --vnet-gateway1 ergw-hub-[suffix] \
    --express-route-circuit2 [your-circuit-id] \
    --connection-type ExpressRoute
```

### 2. SSL Certificate Configuration

Configure SSL certificates for Application Gateway:

```bash
# Upload your SSL certificate (replace with your certificate path)
az network application-gateway ssl-cert create \
    --resource-group rg-hybrid-db-connectivity \
    --gateway-name appgw-db-[suffix] \
    --name ssl-cert-db \
    --cert-file /path/to/your/certificate.pfx \
    --cert-password [certificate-password]
```

### 3. Database Configuration

Configure PostgreSQL for your specific requirements:

```bash
# Set additional database parameters
az postgres flexible-server parameter set \
    --name postgres-hybrid-[suffix] \
    --resource-group rg-hybrid-db-connectivity \
    --parameter-name log_statement \
    --value all

# Create application database
az postgres flexible-server db create \
    --resource-group rg-hybrid-db-connectivity \
    --server-name postgres-hybrid-[suffix] \
    --database-name applicationdb
```

## Validation & Testing

### 1. Verify Infrastructure Deployment

```bash
# Check all resource deployment status
az resource list \
    --resource-group rg-hybrid-db-connectivity \
    --query "[].{Name:name, Type:type, Status:provisioningState}" \
    --output table

# Verify ExpressRoute Gateway connectivity
az network vnet-gateway show \
    --name ergw-hub-[suffix] \
    --resource-group rg-hybrid-db-connectivity \
    --query "bgpSettings.asn"
```

### 2. Test Database Connectivity

```bash
# Test PostgreSQL connectivity from within Azure
POSTGRES_FQDN=$(az postgres flexible-server show \
    --name postgres-hybrid-[suffix] \
    --resource-group rg-hybrid-db-connectivity \
    --query "fullyQualifiedDomainName" \
    --output tsv)

echo "PostgreSQL FQDN: ${POSTGRES_FQDN}"

# Test DNS resolution
nslookup ${POSTGRES_FQDN}
```

### 3. Validate Application Gateway Health

```bash
# Check Application Gateway operational state
az network application-gateway show \
    --name appgw-db-[suffix] \
    --resource-group rg-hybrid-db-connectivity \
    --query "operationalState"

# Verify backend pool health
az network application-gateway show-backend-health \
    --name appgw-db-[suffix] \
    --resource-group rg-hybrid-db-connectivity
```

## Monitoring and Troubleshooting

### Enable Diagnostic Logging

```bash
# Create Log Analytics workspace for monitoring
az monitor log-analytics workspace create \
    --resource-group rg-hybrid-db-connectivity \
    --workspace-name law-hybrid-monitoring \
    --location eastus

# Enable Application Gateway diagnostic logging
az monitor diagnostic-settings create \
    --name appgw-diagnostics \
    --resource $(az network application-gateway show \
        --name appgw-db-[suffix] \
        --resource-group rg-hybrid-db-connectivity \
        --query "id" --output tsv) \
    --workspace law-hybrid-monitoring \
    --logs '[{"category":"ApplicationGatewayAccessLog","enabled":true},{"category":"ApplicationGatewayPerformanceLog","enabled":true}]' \
    --metrics '[{"category":"AllMetrics","enabled":true}]'
```

### Common Troubleshooting Steps

1. **ExpressRoute Connectivity Issues**:
   ```bash
   # Check ExpressRoute circuit status
   az network express-route show \
       --name [your-circuit-name] \
       --resource-group [your-circuit-rg] \
       --query "circuitProvisioningState"
   ```

2. **Application Gateway Backend Health Issues**:
   ```bash
   # Check NSG rules affecting connectivity
   az network nsg rule list \
       --resource-group rg-hybrid-db-connectivity \
       --nsg-name nsg-database-subnet \
       --output table
   ```

3. **PostgreSQL Connection Issues**:
   ```bash
   # Verify PostgreSQL server firewall rules
   az postgres flexible-server firewall-rule list \
       --name postgres-hybrid-[suffix] \
       --resource-group rg-hybrid-db-connectivity
   ```

## Security Considerations

### Network Security

- Network Security Groups (NSGs) are configured with least-privilege access
- Application Gateway WAF policies protect against common threats
- Private DNS ensures database connections use private IP addresses
- ExpressRoute provides private connectivity bypassing the public internet

### Database Security

- PostgreSQL Flexible Server is deployed with private access only
- SSL/TLS encryption is enforced for all database connections
- Azure AD authentication can be enabled for additional security
- Database audit logging is configured for compliance requirements

### SSL/TLS Configuration

- Application Gateway terminates SSL connections with strong cipher suites
- TLS 1.2 minimum version is enforced
- Custom SSL policies can be configured for specific compliance requirements

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-hybrid-db-connectivity \
    --yes \
    --no-wait

# Verify deletion
az group exists --name rg-hybrid-db-connectivity
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
# Run the cleanup script
./scripts/destroy.sh

# Confirm resource deletion
az group exists --name rg-hybrid-db-connectivity
```

## Customization

### Scaling Considerations

- **Application Gateway**: Supports autoscaling from 2-125 instances
- **PostgreSQL**: Can be scaled vertically (compute) and horizontally (read replicas)
- **ExpressRoute**: Bandwidth can be increased up to circuit limits

### High Availability Options

- Deploy across multiple Availability Zones for resilience
- Configure PostgreSQL read replicas for disaster recovery
- Use Application Gateway zone redundancy for improved availability

### Performance Optimization

- Tune Application Gateway instance count based on traffic patterns
- Optimize PostgreSQL configuration parameters for your workload
- Monitor ExpressRoute bandwidth utilization and scale as needed

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for architectural guidance
2. Consult Azure documentation for service-specific configuration
3. Check Azure Service Health for any ongoing service issues
4. Use Azure Support for production deployments

## Additional Resources

- [Azure ExpressRoute Documentation](https://docs.microsoft.com/en-us/azure/expressroute/)
- [Azure Application Gateway Documentation](https://docs.microsoft.com/en-us/azure/application-gateway/)
- [Azure Database for PostgreSQL Documentation](https://docs.microsoft.com/en-us/azure/postgresql/)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)