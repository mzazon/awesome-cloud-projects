# Infrastructure as Code for Site Recovery Automation with Integrated Update Management

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Site Recovery Automation with Integrated Update Management".

## Available Implementations

- **Bicep**: Azure's recommended infrastructure as code language
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts for Azure CLI

## Prerequisites

- Azure CLI installed and configured (version 2.50.0 or later)
- Azure subscription with appropriate permissions
- Contributor or Owner role in the target subscription
- Two Azure regions identified for primary and secondary sites
- Basic understanding of Azure networking and virtual machines

## Quick Start

### Using Bicep
```bash
# Navigate to Bicep directory
cd bicep/

# Create resource group for deployment
az group create \
    --name "rg-dr-deployment" \
    --location "eastus"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-dr-deployment" \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration Parameters

### Bicep Parameters
The `bicep/parameters.json` file contains customizable parameters:

```json
{
  "primaryLocation": {
    "value": "eastus"
  },
  "secondaryLocation": {
    "value": "westus"
  },
  "vmAdminUsername": {
    "value": "azureuser"
  },
  "vmAdminPassword": {
    "value": "P@ssw0rd123!"
  },
  "vmSize": {
    "value": "Standard_B2s"
  }
}
```

### Terraform Variables
The `terraform/variables.tf` file defines customizable variables:

- `primary_location`: Primary Azure region (default: "eastus")
- `secondary_location`: Secondary Azure region (default: "westus")
- `vm_admin_username`: Admin username for virtual machines
- `vm_admin_password`: Admin password for virtual machines
- `vm_size`: Virtual machine size (default: "Standard_B2s")
- `environment`: Environment tag (default: "dev")

## Deployed Resources

This infrastructure creates the following Azure resources:

### Primary Region Resources
- Resource Group for primary region
- Virtual Network with subnet
- Network Security Group with RDP access rule
- Windows Virtual Machine (Windows Server 2019)
- Azure Automation Account for update management
- Log Analytics Workspace for monitoring

### Secondary Region Resources
- Resource Group for secondary region
- Virtual Network with subnet (non-overlapping address space)
- Recovery Services Vault for Site Recovery
- Action Group for alerting
- Monitoring and alerting rules

### Cross-Region Resources
- Azure Site Recovery replication configuration
- Azure Update Manager integration
- Azure Monitor alerts and dashboards
- Recovery plans for automated failover

## Estimated Costs

Running this infrastructure will incur costs for:
- Virtual machines: ~$50-100/month per VM
- Storage for replication: ~$30-50/month
- Recovery Services Vault: ~$20-40/month
- Network traffic between regions: ~$10-20/month
- Log Analytics workspace: ~$10-30/month

**Total estimated cost: $150-300/month for testing environment**

> **Note**: Costs vary based on VM size, storage requirements, and data transfer volumes. Use Azure Cost Management to monitor actual spending.

## Validation

After deployment, verify the infrastructure is working correctly:

### Check Site Recovery Status
```bash
# List protected items in the vault
az backup item list \
    --resource-group "rg-dr-secondary" \
    --vault-name "rsv-dr-vault" \
    --output table

# Check replication health
az backup job list \
    --resource-group "rg-dr-secondary" \
    --vault-name "rsv-dr-vault" \
    --status InProgress
```

### Verify Update Manager Configuration
```bash
# Check Log Analytics workspace
az monitor log-analytics workspace show \
    --resource-group "rg-dr-primary" \
    --workspace-name "law-dr-workspace" \
    --output table

# Verify VM extension installation
az vm extension list \
    --resource-group "rg-dr-primary" \
    --vm-name "vm-primary" \
    --output table
```

### Test Monitoring and Alerting
```bash
# List configured alerts
az monitor metrics alert list \
    --resource-group "rg-dr-primary" \
    --output table

# Check action group configuration
az monitor action-group list \
    --resource-group "rg-dr-primary" \
    --output table
```

## Cleanup

### Using Bicep
```bash
# Delete the resource groups (this will remove all resources)
az group delete \
    --name "rg-dr-primary" \
    --yes \
    --no-wait

az group delete \
    --name "rg-dr-secondary" \
    --yes \
    --no-wait
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh
```

## Security Considerations

This infrastructure implements several security best practices:

- **Network Security**: Network Security Groups restrict access to VMs
- **Identity and Access**: Uses Azure managed identities where possible
- **Encryption**: Enables encryption at rest for all storage resources
- **Monitoring**: Comprehensive logging and alerting for security events
- **Backup**: Geo-redundant storage for backup data

### Security Recommendations

1. **Password Management**: Replace default passwords with Azure Key Vault secrets
2. **Network Access**: Configure VPN or ExpressRoute for secure connectivity
3. **RBAC**: Implement role-based access control for disaster recovery operations
4. **Compliance**: Enable Azure Policy for regulatory compliance
5. **Monitoring**: Configure Azure Security Center for threat detection

## Troubleshooting

### Common Issues

1. **Replication Failures**:
   - Check VM agent status
   - Verify network connectivity between regions
   - Ensure sufficient permissions for Site Recovery

2. **Update Manager Issues**:
   - Verify Log Analytics workspace connectivity
   - Check VM extension installation status
   - Ensure proper RBAC permissions

3. **Monitoring Problems**:
   - Validate action group email addresses
   - Check alert rule configurations
   - Verify Log Analytics workspace access

### Support Resources

- [Azure Site Recovery documentation](https://docs.microsoft.com/en-us/azure/site-recovery/)
- [Azure Update Manager overview](https://docs.microsoft.com/en-us/azure/update-manager/overview)
- [Azure disaster recovery best practices](https://docs.microsoft.com/en-us/azure/site-recovery/site-recovery-best-practices)

## Customization

### Modifying VM Configuration
To change VM specifications, update the parameters in:
- `bicep/parameters.json` for Bicep deployments
- `terraform/variables.tf` for Terraform deployments
- Environment variables in `scripts/deploy.sh` for bash deployments

### Adding Additional VMs
To protect additional VMs with Site Recovery:
1. Add VM resources to the appropriate IaC template
2. Configure Site Recovery protection for each VM
3. Update recovery plans to include new VMs
4. Modify monitoring rules for additional resources

### Customizing Recovery Plans
Recovery plans can be customized by:
- Modifying startup order of protected VMs
- Adding custom scripts for application-specific recovery
- Configuring network mappings for complex environments
- Implementing database recovery procedures

## Advanced Features

### Multi-Tier Application Recovery
For complex applications spanning multiple tiers:
- Configure application-consistent recovery points
- Implement database recovery procedures
- Set up load balancer configurations in secondary region
- Configure DNS failover for automatic traffic routing

### Cross-Subscription Recovery
To implement disaster recovery across subscriptions:
- Configure cross-subscription permissions
- Set up Azure Lighthouse for centralized management
- Implement separate billing and governance policies
- Configure cross-tenant authentication

### Hybrid Cloud Integration
To extend protection to on-premises workloads:
- Deploy Site Recovery configuration servers
- Configure Hyper-V or VMware replication
- Set up Azure Arc for hybrid management
- Implement hybrid network connectivity

## Support

For issues with this infrastructure code:
1. Review the troubleshooting section above
2. Check Azure service health status
3. Consult the original recipe documentation
4. Reference Azure provider documentation for Terraform/Bicep
5. Contact Azure support for service-specific issues

## Version History

- **v1.0**: Initial infrastructure code generation
- Compatible with Azure CLI 2.50.0+
- Supports Terraform 1.5+ and Bicep 0.20+
- Tested with Azure Resource Manager API version 2023-04-01