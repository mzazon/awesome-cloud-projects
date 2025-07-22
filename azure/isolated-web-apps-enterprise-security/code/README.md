# Infrastructure as Code for Isolated Web Apps with Enterprise Security Controls

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Isolated Web Apps with Enterprise Security Controls".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Active Azure subscription with Owner or Contributor permissions
- Understanding of Azure networking concepts (VNets, subnets, private DNS)
- Appropriate permissions for App Service Environment deployment
- Estimated cost: $1,000-$2,000 per month for dedicated ASE infrastructure

> **Warning**: Azure App Service Environment v3 incurs significant costs (~$1,000/month base) for dedicated infrastructure even when no applications are running. This solution is designed for enterprise workloads requiring complete isolation and dedicated resources.

## Architecture Overview

This solution deploys:
- Azure App Service Environment v3 with internal load balancer
- Azure Private DNS zone for internal service discovery
- Azure NAT Gateway for predictable outbound connectivity
- Azure Virtual Network with properly segmented subnets
- Azure Bastion for secure management access
- Management VM for testing and administration
- Web application with enterprise-grade isolation

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Review and customize parameters
cp parameters.json.example parameters.json
# Edit parameters.json with your specific values

# Deploy the infrastructure
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment (ASE takes 60-90 minutes)
az deployment group show \
    --resource-group myResourceGroup \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan the deployment
terraform plan

# Apply the configuration (ASE deployment takes 60-90 minutes)
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-ase-enterprise-$(openssl rand -hex 3)"
export LOCATION="eastus"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Deploy the infrastructure
./scripts/deploy.sh

# The script will guide you through the deployment process
# Note: ASE deployment takes 60-90 minutes to complete
```

## Configuration Options

### Key Parameters

- **Location**: Azure region for deployment (default: eastus)
- **Resource Group**: Name of the resource group to create
- **App Service Environment Name**: Name for the ASE v3 instance
- **Virtual Network Address Space**: CIDR block for the VNet (default: 10.0.0.0/16)
- **Private DNS Zone**: Internal domain name (default: enterprise.internal)
- **NAT Gateway**: Configuration for predictable outbound connectivity
- **Bastion Configuration**: Secure management access settings

### Security Configuration

- **Network Isolation**: Complete isolation with internal load balancer
- **Private DNS**: Internal service discovery without public DNS exposure
- **NAT Gateway**: Predictable outbound IP addresses for compliance
- **Azure Bastion**: Secure administrative access without public IPs
- **Service Endpoints**: Secure access to Azure services

## Validation

After deployment, verify the infrastructure:

```bash
# Check App Service Environment status
az appservice ase show \
    --name <ase-name> \
    --resource-group <resource-group> \
    --query "{name:name,provisioningState:provisioningState,internalIP:internalInboundIpAddress}"

# Verify private DNS zone
az network private-dns zone show \
    --name enterprise.internal \
    --resource-group <resource-group>

# Check NAT Gateway configuration
az network nat gateway show \
    --name <nat-gateway-name> \
    --resource-group <resource-group>

# Test web application
az webapp show \
    --name <webapp-name> \
    --resource-group <resource-group> \
    --query "{name:name,state:state,defaultHostName:defaultHostName}"
```

## Accessing the Application

### Internal Access
- Applications are accessible via private DNS: `webapp.enterprise.internal`
- Connect through Azure Bastion to management VM for internal testing
- Use private IP addresses for direct access within the VNet

### Management Access
- Use Azure Bastion to connect to the management VM
- Administrative tasks can be performed through the secure Bastion connection
- No direct internet access to VMs for enhanced security

## Monitoring and Management

### Azure Monitor Integration
- Enable Application Insights for application performance monitoring
- Configure Log Analytics for centralized logging
- Set up alerts for ASE health and performance metrics

### Security Monitoring
- Monitor NAT Gateway for outbound traffic patterns
- Review Azure Activity Logs for administrative actions
- Implement Azure Security Center recommendations

## Cleanup

### Using Bicep
```bash
# Delete the resource group (this will remove all resources)
az group delete \
    --name myResourceGroup \
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
./scripts/destroy.sh
```

> **Note**: ASE deletion takes substantial time (60-90 minutes). The cleanup process is initiated but may take several hours to complete fully.

## Cost Considerations

### Fixed Costs
- **App Service Environment v3**: ~$1,000/month base cost
- **Azure NAT Gateway**: ~$45/month plus data processing charges
- **Azure Bastion Standard**: ~$140/month
- **Private DNS Zone**: ~$0.50/month for the first zone

### Variable Costs
- **App Service Plan**: Based on selected SKU (I1v2, I2v2, I3v2)
- **Virtual Network**: No additional charges for VNet and subnets
- **Public IP addresses**: ~$3.50/month per static IP
- **Management VM**: Based on selected VM size and usage

### Cost Optimization Tips
- Use multiple applications on the same ASE to amortize fixed costs
- Monitor and right-size App Service Plan SKUs based on actual usage
- Consider reserved instances for predictable workloads
- Implement auto-scaling to optimize resource utilization

## Troubleshooting

### Common Issues

1. **ASE Deployment Timeout**
   - ASE deployment takes 60-90 minutes normally
   - Check Azure portal for deployment status
   - Verify subnet has sufficient address space (/24 minimum)

2. **DNS Resolution Issues**
   - Verify private DNS zone is linked to VNet
   - Check DNS records point to correct ASE internal IP
   - Ensure VM is using Azure DNS (168.63.129.16)

3. **Network Connectivity Problems**
   - Verify NAT Gateway is associated with ASE subnet
   - Check Network Security Group rules if implemented
   - Ensure proper subnet configuration for each service

4. **Application Access Issues**
   - Verify ASE is using internal load balancer
   - Check application health and startup logs
   - Ensure proper application configuration for ASE

### Support Resources

- [Azure App Service Environment v3 Documentation](https://learn.microsoft.com/en-us/azure/app-service/environment/overview)
- [Azure Private DNS Documentation](https://learn.microsoft.com/en-us/azure/dns/private-dns-overview)
- [Azure NAT Gateway Documentation](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-overview)
- [Azure Bastion Documentation](https://learn.microsoft.com/en-us/azure/bastion/bastion-overview)

## Security Best Practices

### Network Security
- Use Network Security Groups to control traffic flow
- Implement Azure Firewall for additional security layers
- Enable DDoS Protection for public-facing resources
- Regular security assessments and penetration testing

### Identity and Access
- Use Azure AD integration for application authentication
- Implement role-based access control (RBAC)
- Enable multi-factor authentication for administrative access
- Regular access reviews and privilege management

### Compliance
- Enable Azure Security Center for security recommendations
- Implement Azure Policy for governance and compliance
- Configure audit logging for compliance requirements
- Regular compliance assessments and reporting

## Customization

### Advanced Configurations

1. **Multi-Region Deployment**
   - Deploy identical infrastructure in multiple regions
   - Implement Azure Traffic Manager for global load balancing
   - Configure cross-region backup and disaster recovery

2. **Enhanced Security**
   - Integrate with Azure Application Gateway and WAF
   - Implement Azure Key Vault for certificate management
   - Configure Azure Security Center for threat detection

3. **DevOps Integration**
   - Set up Azure DevOps pipelines for automated deployment
   - Implement blue-green deployment strategies
   - Configure automated testing and security scanning

4. **Monitoring and Alerting**
   - Set up comprehensive monitoring with Azure Monitor
   - Configure Application Insights for application performance
   - Implement custom dashboards and alerting rules

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Azure service documentation for specific services
3. Consult Azure support for service-specific issues
4. Review deployment logs for detailed error information

## Contributing

When modifying this infrastructure code:
1. Follow Azure naming conventions and best practices
2. Test changes in a non-production environment
3. Update documentation to reflect changes
4. Consider security implications of modifications