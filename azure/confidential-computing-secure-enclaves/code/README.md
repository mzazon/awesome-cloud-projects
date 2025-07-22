# Infrastructure as Code for Confidential Computing with Hardware-Protected Enclaves

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Confidential Computing with Hardware-Protected Enclaves".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.40.0 or later installed and configured
- Azure subscription with appropriate permissions to create:
  - Confidential VMs (DCasv5/DCadsv5/ECasv5/ECadsv5 series)
  - Azure Managed HSM
  - Azure Attestation services
  - Key Vault Premium tier
  - Storage accounts with customer-managed keys
- Contributor or Owner role on the subscription
- Basic understanding of confidential computing concepts
- Estimated cost: ~$500-800/month for basic setup

> **Note**: Azure Confidential Computing requires specific VM sizes (DCasv5/DCadsv5/ECasv5/ECadsv5 series) available in select regions. Verify [regional availability](https://docs.microsoft.com/en-us/azure/confidential-computing/virtual-machine-solutions) before deployment.

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Login to Azure (if not already authenticated)
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-confidential-computing \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment progress
az deployment group list \
    --resource-group rg-confidential-computing \
    --query "[].{Name:name, State:properties.provisioningState}" \
    --output table
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow interactive prompts for configuration
```

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize your deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "resourcePrefix": {
      "value": "conf"
    },
    "vmSize": {
      "value": "Standard_DC4as_v5"
    },
    "adminUsername": {
      "value": "azureuser"
    }
  }
}
```

### Terraform Variables

Customize `terraform/variables.tf` or create a `terraform.tfvars` file:

```hcl
location        = "eastus"
resource_prefix = "conf"
vm_size        = "Standard_DC4as_v5"
admin_username = "azureuser"
environment    = "demo"
```

## Architecture Overview

This infrastructure deploys:

1. **Azure Attestation Provider** - Validates TEE integrity
2. **Azure Managed HSM** - FIPS 140-3 Level 3 hardware security module
3. **Confidential Virtual Machine** - AMD SEV-SNP enabled VM
4. **Azure Key Vault Premium** - HSM-backed key management
5. **Azure Storage Account** - Customer-managed key encryption
6. **Managed Identities** - Secure service authentication
7. **Network Security Groups** - Network isolation and protection

## Post-Deployment Steps

After infrastructure deployment, follow these steps to complete the setup:

1. **Initialize Managed HSM Security Domain**:

   ```bash
   # Download security domain (backup)
   az keyvault security-domain download \
       --hsm-name <hsm-name> \
       --security-domain-file SecurityDomain.json \
       --sd-exchange-key SecurityDomainExchangeKey.pem
   ```

2. **Configure Attestation Policies**:

   ```bash
   # Apply custom attestation policy for AMD SEV-SNP
   az attestation policy set \
       --name <attestation-provider-name> \
       --resource-group <resource-group> \
       --policy-format JWT \
       --policy <base64-encoded-policy> \
       --tee-type SevSnpVm
   ```

3. **Deploy Sample Application**:

   ```bash
   # SSH to confidential VM
   ssh azureuser@<vm-public-ip>
   
   # Install required packages and deploy application
   # (Refer to original recipe for detailed application deployment)
   ```

## Validation

### Verify Deployment

```bash
# Check resource group resources
az resource list \
    --resource-group <resource-group-name> \
    --output table

# Verify attestation provider
az attestation show \
    --name <attestation-provider-name> \
    --resource-group <resource-group-name>

# Check managed HSM status
az keyvault show \
    --hsm-name <hsm-name>

# Verify confidential VM
az vm show \
    --resource-group <resource-group-name> \
    --name <vm-name> \
    --query "{Name:name, PowerState:powerState, SecurityType:securityProfile.securityType}"
```

### Test Confidential Computing Features

```bash
# SSH to VM and verify SEV-SNP
ssh azureuser@<vm-public-ip>

# Check SEV-SNP status
sudo dmesg | grep -i sev

# Verify confidential VM features
ls -la /dev/sev-guest
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-confidential-computing \
    --yes \
    --no-wait

# Purge soft-deleted Key Vault and HSM
az keyvault purge \
    --name <key-vault-name> \
    --location <location>

az keyvault purge \
    --hsm-name <hsm-name> \
    --location <location>
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm with 'yes' when prompted

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

## Security Considerations

This infrastructure implements several security best practices:

- **Hardware-based Security**: Uses AMD SEV-SNP for memory encryption
- **Attestation**: Validates TEE integrity before key release
- **HSM Protection**: FIPS 140-3 Level 3 hardware security modules
- **Customer-Managed Keys**: Full control over encryption keys
- **Network Isolation**: Restricted network access and security groups
- **Managed Identities**: Secure authentication without stored credentials
- **Role-Based Access Control**: Least privilege access principles

## Troubleshooting

### Common Issues

1. **Regional Availability**: Confidential VMs are only available in select regions
2. **VM Size Constraints**: Only specific VM sizes support confidential computing
3. **HSM Provisioning Time**: Managed HSM creation takes 20-25 minutes
4. **Quota Limits**: Verify subscription quotas for confidential VM cores
5. **Network Connectivity**: Ensure proper NSG rules for application access

### Debugging Commands

```bash
# Check VM extensions and status
az vm extension list \
    --resource-group <resource-group> \
    --vm-name <vm-name>

# Monitor deployment logs
az deployment group show \
    --resource-group <resource-group> \
    --name <deployment-name>

# View activity logs
az monitor activity-log list \
    --resource-group <resource-group> \
    --max-events 50
```

## Cost Optimization

To minimize costs during testing:

1. **Use Smaller VM Sizes**: Start with Standard_DC2as_v5 for testing
2. **Auto-shutdown**: Configure VM auto-shutdown schedules
3. **Resource Cleanup**: Always clean up test resources promptly
4. **HSM Considerations**: Managed HSM incurs charges even when idle
5. **Storage Tiers**: Use appropriate storage tiers for your use case

## Advanced Configuration

### Custom Attestation Policies

Create custom attestation policies for specific security requirements:

```json
{
  "version": "1.0",
  "rules": [
    {
      "claim": "[x-ms-compliance-status]",
      "operator": "equals",
      "value": "azure-compliant"
    },
    {
      "claim": "[x-ms-attestation-type]",
      "operator": "equals", 
      "value": "sevsnpvm"
    }
  ]
}
```

### Multi-Region Deployment

For production scenarios, consider deploying across multiple regions:

- Configure HSM backup and restore procedures
- Implement attestation policy synchronization
- Set up cross-region networking
- Plan for disaster recovery scenarios

## Support and Documentation

- [Azure Confidential Computing Documentation](https://docs.microsoft.com/en-us/azure/confidential-computing/)
- [Azure Attestation Overview](https://docs.microsoft.com/en-us/azure/attestation/overview)
- [Managed HSM Best Practices](https://docs.microsoft.com/en-us/azure/key-vault/managed-hsm/best-practices)
- [Confidential VM Troubleshooting](https://docs.microsoft.com/en-us/azure/confidential-computing/troubleshoot-confidential-vm)

For issues with this infrastructure code, refer to the original recipe documentation or Azure support resources.

## Next Steps

After successful deployment, consider implementing:

1. **Application Integration**: Integrate your applications with the confidential computing infrastructure
2. **Monitoring**: Set up Azure Monitor for infrastructure and application monitoring
3. **Backup Strategy**: Implement backup procedures for HSM security domains
4. **Compliance**: Configure compliance monitoring and reporting
5. **Scaling**: Plan for horizontal scaling of confidential workloads

## Contributing

To improve this infrastructure code:

1. Test deployments in different regions
2. Validate with various VM sizes
3. Enhance error handling in scripts
4. Add additional monitoring capabilities
5. Improve documentation based on user feedback