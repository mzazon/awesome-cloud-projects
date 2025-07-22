# Infrastructure as Code for Global Traffic Distribution with Traffic Manager and Application Gateway

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Global Traffic Distribution with Traffic Manager and Application Gateway".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login` completed)
- Azure subscription with appropriate permissions for:
  - Resource Group creation and management
  - Virtual Network and subnet creation
  - Public IP address allocation
  - Traffic Manager profile management
  - Application Gateway deployment and configuration
  - Virtual Machine Scale Set creation
  - Log Analytics workspace creation
  - Diagnostic settings configuration
- For Terraform: Terraform CLI v1.0+ installed
- For Bicep: Azure CLI with Bicep extension installed
- Estimated cost: $150-300 per month (varies by traffic volume and instance sizes)

## Architecture Overview

This solution deploys a global traffic distribution system across three Azure regions (East US, UK South, Southeast Asia) with:

- **Traffic Manager**: DNS-based global load balancing with performance routing
- **Application Gateway**: Regional layer-7 load balancing with Web Application Firewall
- **VM Scale Sets**: Scalable backend infrastructure with nginx web servers
- **Virtual Networks**: Isolated network infrastructure per region
- **Monitoring**: Comprehensive logging and monitoring with Azure Monitor

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Review and customize parameters
cp parameters.json.example parameters.json
# Edit parameters.json with your preferred values

# Deploy the infrastructure
az deployment sub create \
    --location eastus \
    --template-file main.bicep \
    --parameters @parameters.json

# Get deployment outputs
az deployment sub show \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your preferred values

# Initialize Terraform
terraform init

# Review the deployment plan
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

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for any required inputs
# and provide progress updates during deployment
```

## Configuration Options

### Key Parameters

- **resourceGroupPrefix**: Prefix for resource group names (default: "rg-global-traffic")
- **trafficManagerName**: Name for the Traffic Manager profile (must be globally unique)
- **applicationGatewayPrefix**: Prefix for Application Gateway names
- **vmScaleSetPrefix**: Prefix for VM Scale Set names
- **regions**: Array of Azure regions for deployment
- **instanceCount**: Number of VM instances per Scale Set (default: 2)
- **vmSize**: Size of VM instances (default: "Standard_B2s")

### Customization

1. **Regions**: Modify the regions array to deploy to different Azure regions
2. **Scaling**: Adjust instance counts and VM sizes based on expected load
3. **Networking**: Customize virtual network address spaces and subnet configurations
4. **Security**: Configure WAF policies and NSG rules for your security requirements
5. **Monitoring**: Adjust Log Analytics workspace configuration and diagnostic settings

## Validation

After deployment, verify the infrastructure:

```bash
# Check Traffic Manager profile status
az network traffic-manager profile show \
    --resource-group rg-global-traffic-primary \
    --name your-traffic-manager-name \
    --query "{Status:profileStatus, FQDN:dnsConfig.fqdn}"

# Test endpoint health
az network traffic-manager endpoint list \
    --resource-group rg-global-traffic-primary \
    --profile-name your-traffic-manager-name \
    --query "[].{Name:name, Status:endpointStatus}"

# Test application access
curl -I http://your-traffic-manager-fqdn.trafficmanager.net
```

## Monitoring and Troubleshooting

### Built-in Monitoring

- **Log Analytics**: Centralized logging for all components
- **Application Insights**: Application performance monitoring
- **Azure Monitor**: Metrics and alerting for infrastructure components
- **Diagnostic Settings**: Enabled for Traffic Manager and Application Gateways

### Common Issues

1. **Endpoint Health**: Check Application Gateway backend pool health
2. **DNS Resolution**: Verify Traffic Manager profile DNS configuration
3. **SSL/TLS**: Ensure proper certificate configuration for HTTPS
4. **WAF Blocking**: Review WAF logs for legitimate traffic being blocked

### Troubleshooting Commands

```bash
# Check Application Gateway backend health
az network application-gateway show-backend-health \
    --resource-group rg-global-traffic-primary \
    --name your-application-gateway-name

# View Traffic Manager metrics
az monitor metrics list \
    --resource /subscriptions/your-subscription-id/resourceGroups/rg-global-traffic-primary/providers/Microsoft.Network/trafficManagerProfiles/your-traffic-manager-name \
    --metric "QpsByEndpoint"

# Check WAF logs
az monitor log-analytics query \
    --workspace your-workspace-id \
    --analytics-query "AzureDiagnostics | where ResourceProvider == 'MICROSOFT.NETWORK' and Category == 'ApplicationGatewayFirewallLog'"
```

## Performance Optimization

### Traffic Manager

- **TTL Settings**: Adjust DNS TTL values based on failover requirements
- **Routing Method**: Consider geographic or weighted routing for specific use cases
- **Health Check Intervals**: Optimize probe frequency for your availability requirements

### Application Gateway

- **Instance Count**: Scale Application Gateway instances based on expected load
- **Health Probes**: Configure custom health probes for better backend monitoring
- **Connection Draining**: Enable connection draining for graceful maintenance

### VM Scale Sets

- **Auto-scaling**: Configure auto-scaling rules based on CPU, memory, or custom metrics
- **Instance Distribution**: Ensure even distribution across availability zones
- **Health Checks**: Configure application health checks for proper load balancing

## Security Considerations

### Web Application Firewall

- **OWASP Rules**: Enabled with latest OWASP Core Rule Set
- **Custom Rules**: Add application-specific security rules
- **Monitoring**: Monitor WAF logs for attack patterns and false positives

### Network Security

- **NSG Rules**: Restrict traffic to necessary ports and protocols
- **Private Endpoints**: Consider private endpoints for backend communication
- **SSL/TLS**: Implement end-to-end encryption for sensitive applications

### Access Control

- **RBAC**: Implement role-based access control for resource management
- **Key Vault**: Use Azure Key Vault for certificate and secret management
- **Managed Identity**: Use managed identities for service-to-service authentication

## Cost Optimization

### Resource Sizing

- **Right-sizing**: Monitor resource utilization and adjust sizes accordingly
- **Reserved Instances**: Consider reserved instances for predictable workloads
- **Spot Instances**: Use spot instances for non-critical workloads

### Traffic Manager

- **Endpoint Monitoring**: Optimize health check frequency to balance cost and availability
- **DNS Queries**: Monitor DNS query volumes and optimize TTL settings

### Application Gateway

- **Capacity Planning**: Use Application Gateway v2 for better cost efficiency
- **WAF Policies**: Optimize WAF rules to reduce processing overhead

## Cleanup

### Using Bicep

```bash
# Delete the deployment (this will remove all resources)
az deployment sub delete --name main

# Alternatively, delete resource groups individually
az group delete --name rg-global-traffic-primary --yes --no-wait
az group delete --name rg-global-traffic-secondary --yes --no-wait
az group delete --name rg-global-traffic-tertiary --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before destroying resources
```

## Advanced Configuration

### Multi-Region Deployment

To add additional regions:

1. **Bicep**: Add new region parameters to the parameters file
2. **Terraform**: Extend the regions variable in terraform.tfvars
3. **Scripts**: Modify the LOCATIONS array in deploy.sh

### Custom Domain Configuration

To use a custom domain:

1. Configure DNS CNAME record pointing to Traffic Manager FQDN
2. Add SSL certificates to Application Gateway
3. Update health probe configurations

### Integration with CI/CD

Example Azure DevOps pipeline integration:

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include:
    - main
  paths:
    include:
    - azure/optimizing-global-traffic-distribution-with-azure-traffic-manager-and-application-gateway/code/*

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: AzureCLI@2
  displayName: 'Deploy Infrastructure'
  inputs:
    azureSubscription: 'your-service-connection'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
      cd azure/optimizing-global-traffic-distribution-with-azure-traffic-manager-and-application-gateway/code/bicep/
      az deployment sub create \
        --location eastus \
        --template-file main.bicep \
        --parameters @parameters.json
```

## Support and Documentation

### Additional Resources

- [Azure Traffic Manager Documentation](https://docs.microsoft.com/en-us/azure/traffic-manager/)
- [Azure Application Gateway Documentation](https://docs.microsoft.com/en-us/azure/application-gateway/)
- [Azure Load Balancing Options](https://docs.microsoft.com/en-us/azure/architecture/guide/technology-choices/load-balancing-overview)
- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)

### Getting Help

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation
3. Verify Azure CLI and tool versions
4. Review Azure service limits and quotas
5. Check Azure service health status

### Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Follow Azure naming conventions
3. Update documentation accordingly
4. Validate with Azure best practices
5. Test deployment and cleanup procedures

## Version Information

- **Recipe Version**: 1.0
- **Last Updated**: 2025-07-12
- **Bicep Version**: Latest stable
- **Terraform Version**: >= 1.0
- **Azure CLI Version**: >= 2.50.0

---

*This infrastructure code is generated based on the recipe "Global Traffic Distribution with Traffic Manager and Application Gateway" and follows Azure best practices for global traffic distribution and high availability.*