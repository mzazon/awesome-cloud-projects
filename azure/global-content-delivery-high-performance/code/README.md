# Infrastructure as Code for Global Content Delivery with High-Performance Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Global Content Delivery with High-Performance Storage".

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code using the Azure provider
- **Scripts**: Bash deployment and cleanup scripts for step-by-step deployment

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with Owner or Contributor permissions
- Understanding of Azure networking concepts (VNets, Private Endpoints, Private Link)
- Knowledge of content delivery networks and caching strategies
- Estimated cost: $200-400/month for test environment (varies by region and usage)

> **Note**: Azure NetApp Files requires registration and capacity pool minimum commitments. Review [Azure NetApp Files pricing](https://azure.microsoft.com/pricing/details/netapp/) for detailed cost information.

## Quick Start

### Using Bicep

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group myResourceGroup \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json

# Monitor deployment status
az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# Show outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
./scripts/verify.sh
```

## Architecture Overview

This solution implements a globally distributed content delivery architecture featuring:

- **Azure Front Door Premium**: Global edge distribution with integrated WAF and Private Link connectivity
- **Azure NetApp Files Premium**: Ultra-high-performance storage backend with up to 64 MiB/s per TiB throughput
- **Multi-Regional Deployment**: Primary (East US) and secondary (West Europe) regions for high availability
- **Private Link Security**: Secure connectivity without public internet exposure
- **Azure Monitor Integration**: Comprehensive monitoring and alerting

## Configuration

### Environment Variables

The following environment variables are used across all deployment methods:

```bash
# Required variables
export RESOURCE_GROUP="rg-content-delivery-${RANDOM_SUFFIX}"
export LOCATION_PRIMARY="eastus"
export LOCATION_SECONDARY="westeurope"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# NetApp Files configuration
export ANF_ACCOUNT_PRIMARY="anf-primary-${RANDOM_SUFFIX}"
export ANF_ACCOUNT_SECONDARY="anf-secondary-${RANDOM_SUFFIX}"
export CAPACITY_POOL_NAME="pool-premium"
export VOLUME_NAME="content-volume"

# Front Door configuration
export FRONT_DOOR_NAME="fd-content-${RANDOM_SUFFIX}"
```

### Resource Naming

Resources are named with a consistent pattern using a random suffix for uniqueness:

- Resource Group: `rg-content-delivery-{suffix}`
- Azure NetApp Files Account: `anf-primary-{suffix}` / `anf-secondary-{suffix}`
- Front Door Profile: `fd-content-{suffix}`
- Virtual Networks: `vnet-primary-{suffix}` / `vnet-secondary-{suffix}`
- Log Analytics Workspace: `law-content-{suffix}`

### Service Tiers and Configuration

- **Azure NetApp Files**: Premium tier with 4 TiB capacity pools
- **Azure Front Door**: Premium SKU with integrated WAF
- **Virtual Networks**: /16 address spaces with dedicated /24 subnets
- **Monitoring**: Log Analytics workspace with diagnostic settings

## Validation and Testing

### Verify Deployment

After deployment, validate the infrastructure:

```bash
# Check Azure NetApp Files volume status
az netappfiles volume show \
    --resource-group ${RESOURCE_GROUP} \
    --account-name ${ANF_ACCOUNT_PRIMARY} \
    --pool-name ${CAPACITY_POOL_NAME} \
    --volume-name ${VOLUME_NAME} \
    --query "provisioningState"

# Test Front Door endpoint
ENDPOINT_HOSTNAME=$(az afd endpoint show \
    --resource-group ${RESOURCE_GROUP} \
    --profile-name ${FRONT_DOOR_NAME} \
    --endpoint-name "content-endpoint" \
    --query "hostName" --output tsv)

curl -I "https://${ENDPOINT_HOSTNAME}/"
```

### Performance Testing

```bash
# Monitor performance metrics
az monitor metrics list \
    --resource ${FRONT_DOOR_NAME} \
    --resource-type Microsoft.Cdn/profiles \
    --resource-group ${RESOURCE_GROUP} \
    --metric "RequestCount" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

## Security Considerations

This infrastructure implements several security best practices:

- **Private Link Connectivity**: All traffic between Front Door and origins uses private connectivity
- **Web Application Firewall**: Integrated WAF with managed rule sets and rate limiting
- **Network Isolation**: Virtual networks with proper subnet delegation and security groups
- **Monitoring and Alerting**: Comprehensive logging and monitoring for security events

## Cost Optimization

- **Azure NetApp Files**: Use Premium tier for optimal performance-to-cost ratio
- **Front Door Premium**: Leverage global caching to reduce origin server load
- **Regional Deployment**: Strategic placement in East US and West Europe for cost-effective global coverage
- **Monitoring**: Use Azure Monitor to track costs and optimize resource utilization

## Troubleshooting

### Common Issues

1. **NetApp Files Registration**: Ensure Microsoft.NetApp provider is registered
2. **Capacity Pool Limits**: Check subscription limits for NetApp Files capacity pools
3. **Front Door Propagation**: Allow 10-15 minutes for global propagation
4. **Private Link Connectivity**: Verify subnet delegation and private endpoint configuration

### Diagnostic Commands

```bash
# Check provider registration
az provider show --namespace Microsoft.NetApp --query registrationState

# Verify subnet delegation
az network vnet subnet show \
    --name anf-subnet \
    --resource-group ${RESOURCE_GROUP} \
    --vnet-name ${VNET_PRIMARY} \
    --query delegations

# Check Front Door health
az afd origin-group show \
    --resource-group ${RESOURCE_GROUP} \
    --profile-name ${FRONT_DOOR_NAME} \
    --origin-group-name "content-origins" \
    --query healthProbeSettings
```

## Performance Characteristics

### Azure NetApp Files Performance

- **Premium Tier**: Up to 64 MiB/s per TiB throughput
- **Latency**: Submillisecond response times
- **Protocol**: NFS v3 for high-performance file sharing
- **Concurrent Access**: Optimized for multiple origin server connections

### Azure Front Door Performance

- **Global Edge Network**: 118+ points of presence worldwide
- **Anycast Routing**: Automatic routing to nearest edge location
- **Caching**: Intelligent caching with customizable TTL policies
- **SSL Termination**: Edge-optimized SSL/TLS processing

## Monitoring and Alerts

The solution includes comprehensive monitoring:

- **Front Door Access Logs**: Request patterns and performance metrics
- **NetApp Files Metrics**: Storage performance and utilization
- **WAF Logs**: Security events and blocked requests
- **Custom Alerts**: High latency and error rate notifications

## Extensions and Customization

### Multi-Region Content Synchronization

Implement cross-region replication for Azure NetApp Files:

```bash
# Enable cross-region replication
az netappfiles volume replication create \
    --resource-group ${RESOURCE_GROUP} \
    --account-name ${ANF_ACCOUNT_PRIMARY} \
    --pool-name ${CAPACITY_POOL_NAME} \
    --volume-name ${VOLUME_NAME} \
    --replication-schedule _10minutely \
    --remote-volume-resource-id $REMOTE_VOLUME_ID
```

### Advanced Caching Policies

Configure intelligent caching rules:

```bash
# Create advanced caching rule
az afd rule create \
    --resource-group ${RESOURCE_GROUP} \
    --profile-name ${FRONT_DOOR_NAME} \
    --rule-set-name "advanced-caching" \
    --rule-name "geo-based-caching" \
    --conditions '[{"name":"RemoteAddress","parameters":{"operator":"GeoMatch","matchValues":["US"]}}]' \
    --actions '[{"name":"CacheExpiration","parameters":{"cacheBehavior":"SetIfMissing","cacheType":"All","cacheDuration":"1.00:00:00"}}]'
```

## Support and Documentation

- [Azure NetApp Files Documentation](https://docs.microsoft.com/en-us/azure/azure-netapp-files/)
- [Azure Front Door Premium Documentation](https://docs.microsoft.com/en-us/azure/frontdoor/)
- [Azure Private Link Documentation](https://docs.microsoft.com/en-us/azure/private-link/)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)

For issues with this infrastructure code, refer to the original recipe documentation or the respective Azure service documentation.