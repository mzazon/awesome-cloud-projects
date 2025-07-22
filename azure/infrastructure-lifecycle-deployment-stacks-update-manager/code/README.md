# Infrastructure as Code for Infrastructure Lifecycle Management with Deployment Stacks and Update Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure Lifecycle Management with Deployment Stacks and Update Manager".

## Available Implementations

- **Bicep**: Azure's recommended infrastructure as code language
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.61.0 or later installed and configured
- Azure subscription with Contributor or Owner permissions
- Basic understanding of Azure Resource Manager templates and Bicep
- Familiarity with Azure virtual machines and networking concepts
- For Terraform: Terraform v1.0 or later installed
- Estimated cost: $50-100 for running resources during deployment

## Quick Start

### Using Bicep

```bash
# Navigate to bicep directory
cd bicep/

# Create resource group
az group create --name rg-infra-lifecycle --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-infra-lifecycle \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply
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

This solution deploys:

- **Azure Deployment Stacks**: Manages infrastructure as atomic units with lifecycle management
- **Azure Update Manager**: Provides automated patch management and maintenance scheduling
- **Virtual Machine Scale Set**: Web tier infrastructure with load balancing
- **Azure Monitor**: Comprehensive monitoring and logging for infrastructure and updates
- **Azure Policy**: Governance and compliance enforcement
- **Networking Components**: Virtual network, security groups, and load balancer

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "location": "eastus",
  "adminUsername": "azureuser",
  "adminPassword": "ComplexP@ssw0rd123!",
  "vmSize": "Standard_B2s",
  "instanceCount": 2
}
```

### Terraform Variables

Edit `terraform/variables.tf` or create `terraform.tfvars`:

```hcl
location = "eastus"
admin_username = "azureuser"
admin_password = "ComplexP@ssw0rd123!"
vm_size = "Standard_B2s"
instance_count = 2
```

### Environment Variables (Bash Scripts)

The deploy script uses these environment variables:

```bash
export RESOURCE_GROUP="rg-infra-lifecycle"
export LOCATION="eastus"
export ADMIN_USERNAME="azureuser"
export ADMIN_PASSWORD="ComplexP@ssw0rd123!"
export VM_SIZE="Standard_B2s"
export INSTANCE_COUNT="2"
```

## Deployment Details

### Key Features

1. **Deployment Stacks**: Infrastructure managed as atomic units with deny settings for protection
2. **Maintenance Configurations**: Weekly update schedules for critical and security patches
3. **Monitoring Integration**: Log Analytics workspace for comprehensive monitoring
4. **Policy Enforcement**: Azure Policy ensures consistent governance
5. **Automated Reporting**: Workbooks for compliance and update status visualization

### Security Considerations

- Virtual machines deployed with latest Ubuntu LTS image
- Network security groups configured with minimal required ports
- Deployment stack deny settings prevent unauthorized modifications
- Maintenance windows scheduled during low-traffic periods
- Log Analytics workspace for security monitoring and compliance

### Cost Optimization

- Standard_B2s VMs provide cost-effective compute for web workloads
- Scheduled maintenance during off-peak hours
- Automated resource lifecycle management prevents resource sprawl
- Log Analytics workspace with 30-day retention to manage costs

## Validation & Testing

### Post-Deployment Verification

1. **Check Deployment Stack Status**:
   ```bash
   az stack group show --name stack-web-tier --resource-group rg-infra-lifecycle
   ```

2. **Verify Update Manager Configuration**:
   ```bash
   az maintenance configuration show --resource-group rg-infra-lifecycle --resource-name mc-weekly-updates
   ```

3. **Test Load Balancer**:
   ```bash
   # Get public IP
   LB_IP=$(az network public-ip show --resource-group rg-infra-lifecycle --name pip-webtier-lb --query ipAddress -o tsv)
   
   # Test connectivity
   curl -I http://$LB_IP
   ```

4. **Validate Resource Protection**:
   ```bash
   # Attempt to modify protected resource (should fail)
   az network nsg rule create --resource-group rg-infra-lifecycle --nsg-name nsg-webtier --name test-rule --priority 2000 --direction Inbound --access Allow --protocol Tcp --source-address-prefix '*' --source-port-range '*' --destination-address-prefix '*' --destination-port-range '8080'
   ```

### Monitoring and Compliance

- Access the Infrastructure Lifecycle Management Dashboard in Azure Monitor Workbooks
- Review update compliance reports in the Log Analytics workspace
- Monitor deployment stack status and resource health
- Validate policy compliance in Azure Policy dashboard

## Cleanup

### Using Bicep

```bash
# Delete deployment stack (removes all managed resources)
az stack group delete --name stack-web-tier --resource-group rg-infra-lifecycle --yes

# Delete resource group
az group delete --name rg-infra-lifecycle --yes
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

## Troubleshooting

### Common Issues

1. **Deployment Stack Creation Fails**:
   - Verify Azure CLI version (requires v2.61.0+)
   - Check subscription permissions
   - Validate Bicep template syntax

2. **Update Manager Configuration Issues**:
   - Ensure proper maintenance configuration parameters
   - Verify resource assignments are correct
   - Check maintenance schedule format

3. **Resource Protection Errors**:
   - Deployment stack deny settings may prevent modifications
   - Remove resources from stack before manual changes
   - Check Azure Policy assignments

4. **Monitoring Data Missing**:
   - Verify Log Analytics workspace configuration
   - Check diagnostic settings on resources
   - Validate workbook permissions

### Support Resources

- [Azure Deployment Stacks Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deployment-stacks)
- [Azure Update Manager Documentation](https://learn.microsoft.com/en-us/azure/update-manager/overview)
- [Azure Policy Documentation](https://learn.microsoft.com/en-us/azure/governance/policy/)
- [Azure Monitor Workbooks](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview)

## Customization

### Extending the Solution

1. **Multi-Environment Support**: Modify parameters for different environments (dev, staging, prod)
2. **Additional Maintenance Windows**: Create separate configurations for different application tiers
3. **Enhanced Monitoring**: Add custom metrics and alerts for specific business requirements
4. **Integration**: Connect with external ITSM tools for change management workflows

### Advanced Configurations

- **Custom Update Classifications**: Modify maintenance configurations for specific update types
- **Disaster Recovery**: Integrate with Azure Site Recovery for automated failover
- **Cost Management**: Add budget alerts and cost optimization automation
- **Compliance Reporting**: Create custom workbooks for regulatory compliance

## Best Practices

1. **Resource Naming**: Use consistent naming conventions across all resources
2. **Tagging Strategy**: Implement comprehensive tagging for cost allocation and governance
3. **Security**: Regularly review and update security configurations
4. **Monitoring**: Set up alerts for critical infrastructure and update failures
5. **Documentation**: Maintain up-to-date documentation for operational procedures

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation for latest features
3. Validate Azure CLI and tool versions
4. Review Azure service health and known issues
5. Contact Azure support for service-specific issues

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment first
2. Update documentation to reflect changes
3. Validate security configurations
4. Update cost estimates if resource requirements change
5. Follow Azure Well-Architected Framework principles