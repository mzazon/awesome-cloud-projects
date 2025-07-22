# Infrastructure as Code for Trusted Container Supply Chain with Attestation Service and Image Builder

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Trusted Container Supply Chain with Attestation Service and Image Builder".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Azure CLI v2.54.0 or later installed and configured
- Azure subscription with appropriate permissions
- Contributor access to create Azure Attestation Service and Image Builder resources
- Understanding of container concepts and attestation security

### Tool-Specific Prerequisites

#### For Bicep
- Bicep CLI installed (`az bicep install`)
- Azure PowerShell (optional, for advanced scenarios)

#### For Terraform
- Terraform v1.5.0 or later installed
- Azure provider v3.50.0 or later

#### For Bash Scripts
- OpenSSL for generating random suffixes
- jq for JSON processing
- Basic understanding of Azure CLI commands

### Required Azure Permissions
- Microsoft.Attestation/* (for Azure Attestation Service)
- Microsoft.VirtualMachineImages/* (for Azure Image Builder)
- Microsoft.ContainerRegistry/* (for Azure Container Registry)
- Microsoft.KeyVault/* (for Azure Key Vault)
- Microsoft.ManagedIdentity/* (for Managed Identity)
- Microsoft.Authorization/roleAssignments/* (for role assignments)

### Estimated Costs
- **Basic Usage**: $50-100/month
- **Production Workloads**: $200-500/month
- Cost components include attestation operations, image builds, registry storage, and key vault operations

## Architecture Overview

This solution deploys:
- **Azure Attestation Service**: Hardware-based attestation for build environment verification
- **Azure Image Builder**: Automated, secure container image creation
- **Azure Container Registry**: Secure image storage with content trust
- **Azure Key Vault**: Cryptographic key management for image signing
- **Managed Identity**: Secure authentication between services

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to Bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-container-supply-chain \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters uniqueSuffix=$(openssl rand -hex 3)
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="location=eastus" -var="unique_suffix=$(openssl rand -hex 3)"

# Apply the configuration
terraform apply -var="location=eastus" -var="unique_suffix=$(openssl rand -hex 3)"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh
```

## Detailed Deployment Instructions

### 1. Prepare Your Environment

```bash
# Set common environment variables
export AZURE_LOCATION="eastus"
export RESOURCE_GROUP_NAME="rg-container-supply-chain"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Create resource group (if using scripts)
az group create \
    --name ${RESOURCE_GROUP_NAME} \
    --location ${AZURE_LOCATION}
```

### 2. Choose Your Deployment Method

#### Option A: Bicep Deployment

```bash
# Deploy with custom parameters
az deployment group create \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json
```

#### Option B: Terraform Deployment

```bash
# Initialize and plan
cd terraform/
terraform init
terraform plan -out=tfplan

# Apply the plan
terraform apply tfplan
```

#### Option C: Bash Script Deployment

```bash
# Run automated deployment
./scripts/deploy.sh

# Monitor deployment progress
az deployment group list \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --query "[].{Name:name, State:properties.provisioningState}"
```

### 3. Post-Deployment Configuration

After deployment, complete the setup:

```bash
# Get attestation endpoint
ATTESTATION_ENDPOINT=$(az attestation show \
    --name "attestation-$(cat .unique_suffix)" \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --query attestUri --output tsv)

# Configure attestation policies
az attestation policy set \
    --name "attestation-$(cat .unique_suffix)" \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --policy-format Text \
    --new-attestation-policy $(base64 -w 0 attestation-policy.txt) \
    --attestation-type AzureVM

# Test attestation service
echo "Testing attestation service at: ${ATTESTATION_ENDPOINT}"
```

## Validation & Testing

### Verify Deployment

```bash
# Check all resources are deployed
az resource list \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --output table

# Verify attestation provider
az attestation show \
    --name "attestation-$(cat .unique_suffix)" \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --query status

# Verify container registry content trust
az acr config content-trust show \
    --name "acr$(cat .unique_suffix)" \
    --query status

# Check Key Vault access
az keyvault key list \
    --vault-name "kv-$(cat .unique_suffix)"
```

### Test the Supply Chain

```bash
# Run the complete supply chain test
./scripts/test-supply-chain.sh

# Verify image signing workflow
./scripts/verify-signatures.sh
```

## Customization

### Bicep Parameters

Modify `bicep/parameters.json` to customize:
- `location`: Azure region for deployment
- `attestationProviderName`: Custom name for attestation service
- `keyVaultSku`: Key Vault pricing tier (standard/premium)
- `containerRegistrySku`: ACR pricing tier (Basic/Standard/Premium)
- `enableContentTrust`: Enable/disable content trust (default: true)

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:
```hcl
location = "eastus"
resource_group_name = "rg-container-supply-chain-custom"
enable_advanced_threat_protection = true
key_vault_sku = "premium"
container_registry_sku = "Premium"
```

### Environment-Specific Configurations

For different environments (dev/staging/prod):

```bash
# Development environment
export ENVIRONMENT="dev"
export ENABLE_MONITORING="false"
export KEY_VAULT_SKU="standard"

# Production environment
export ENVIRONMENT="prod"
export ENABLE_MONITORING="true"
export KEY_VAULT_SKU="premium"
export ENABLE_ADVANCED_THREAT_PROTECTION="true"
```

## Security Considerations

### Network Security
- All services are configured with private endpoints where supported
- Network Security Groups restrict access to necessary ports only
- Azure Firewall rules can be customized for additional protection

### Identity and Access Management
- Managed identities are used throughout for service-to-service authentication
- Role-based access control (RBAC) follows principle of least privilege
- Key Vault access policies are restrictive and audited

### Data Protection
- All data is encrypted at rest using Azure-managed keys
- Key Vault uses Hardware Security Modules (HSMs) in premium tier
- Container registry supports customer-managed encryption keys

## Monitoring and Logging

### Built-in Monitoring
- Azure Monitor is configured for all services
- Application Insights tracks attestation and signing operations
- Log Analytics workspace aggregates security events

### Custom Monitoring Setup

```bash
# Enable diagnostic settings
az monitor diagnostic-settings create \
    --resource $(az keyvault show --name "kv-$(cat .unique_suffix)" --resource-group ${RESOURCE_GROUP_NAME} --query id -o tsv) \
    --name "kv-diagnostics" \
    --logs '[{"category":"AuditEvent","enabled":true}]' \
    --workspace $(az monitor log-analytics workspace show --resource-group ${RESOURCE_GROUP_NAME} --workspace-name "law-$(cat .unique_suffix)" --query id -o tsv)
```

## Troubleshooting

### Common Issues

1. **Attestation Provider Creation Fails**
   ```bash
   # Check regional availability
   az provider show --namespace Microsoft.Attestation --query "resourceTypes[?resourceType=='attestationProviders'].locations[]"
   ```

2. **Image Builder Permissions**
   ```bash
   # Verify managed identity permissions
   az role assignment list --assignee $(az identity show --name "mi-imagebuilder-$(cat .unique_suffix)" --resource-group ${RESOURCE_GROUP_NAME} --query principalId -o tsv)
   ```

3. **Container Registry Access**
   ```bash
   # Test registry connectivity
   az acr check-health --name "acr$(cat .unique_suffix)"
   ```

### Debug Commands

```bash
# Enable debug logging
export AZURE_CLI_DEBUG=1

# Check resource provisioning status
az deployment group show \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --name mainDeployment \
    --query properties.provisioningState

# View deployment errors
az deployment group show \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --name mainDeployment \
    --query properties.error
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete \
    --name ${RESOURCE_GROUP_NAME} \
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

# Verify cleanup completion
az resource list \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --output table
```

### Manual Cleanup (if needed)

```bash
# Purge Key Vault (required for complete cleanup)
az keyvault purge \
    --name "kv-$(cat .unique_suffix)" \
    --location ${AZURE_LOCATION}

# Remove any remaining role assignments
az role assignment list \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --query "[].id" \
    --output tsv | xargs -I {} az role assignment delete --ids {}
```

## Advanced Usage

### Integration with CI/CD Pipelines

#### Azure DevOps Pipeline Example

```yaml
# azure-pipelines.yml
trigger:
- main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: AzureCLI@2
  displayName: 'Deploy Infrastructure'
  inputs:
    azureSubscription: '$(serviceConnection)'
    scriptType: 'bash'
    scriptPath: 'scripts/deploy.sh'
    arguments: '$(Build.BuildId)'
```

#### GitHub Actions Example

```yaml
# .github/workflows/deploy.yml
name: Deploy Container Supply Chain
on:
  push:
    branches: [main]
    
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    - name: Deploy Infrastructure
      run: ./scripts/deploy.sh
```

### Multi-Environment Deployment

```bash
# Deploy to multiple environments
for env in dev staging prod; do
    export ENVIRONMENT=${env}
    export RESOURCE_GROUP_NAME="rg-container-supply-chain-${env}"
    ./scripts/deploy.sh
done
```

## Performance Optimization

### Cost Optimization
- Use Azure Spot VMs for Image Builder when appropriate
- Implement lifecycle policies for container registry images
- Configure appropriate Key Vault access patterns to minimize costs

### Scaling Considerations
- Image Builder can be configured for parallel builds
- Container Registry supports geo-replication for global access
- Attestation Service automatically scales with demand

## Compliance and Governance

### Regulatory Compliance
- SOC 2 Type II compliance through Azure security controls
- HIPAA/HITECH compliance with additional configuration
- ISO 27001 compliance through Azure compliance offerings

### Azure Policy Integration

```bash
# Apply governance policies
az policy assignment create \
    --name "container-security-policy" \
    --policy "/providers/Microsoft.Authorization/policyDefinitions/c25d9a16-bc35-4e15-a7e5-9db606bf9ed4" \
    --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_NAME}"
```

## Support and Documentation

### Additional Resources
- [Azure Attestation Service Documentation](https://docs.microsoft.com/en-us/azure/attestation/)
- [Azure Image Builder Documentation](https://docs.microsoft.com/en-us/azure/virtual-machines/image-builder-overview)
- [Container Registry Documentation](https://docs.microsoft.com/en-us/azure/container-registry/)
- [Azure Key Vault Documentation](https://docs.microsoft.com/en-us/azure/key-vault/)

### Getting Help
- For infrastructure issues: Check Azure Service Health and create support tickets
- For recipe-specific questions: Refer to the original recipe documentation
- For community support: Use Azure forums and Stack Overflow with appropriate tags

### Contributing
To improve this infrastructure code:
1. Fork the repository
2. Make your changes
3. Test thoroughly in a development environment
4. Submit a pull request with detailed description

## Version History

- **v1.0**: Initial implementation with basic attestation and signing
- **v1.1**: Added advanced monitoring and compliance features
- **v1.2**: Enhanced security with HSM support and network isolation

---

**Note**: This infrastructure code implements the complete trusted container supply chain solution. Ensure you understand the security implications and compliance requirements before deploying to production environments.