# Infrastructure as Code for Serverless Infrastructure Deployment with Container Apps Jobs and ARM Templates

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Serverless Infrastructure Deployment with Container Apps Jobs and ARM Templates".

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with Owner or Contributor permissions
- Basic understanding of ARM templates and Azure Resource Manager
- Familiarity with containerization and Azure Container Apps concepts
- Git repository for storing ARM templates and deployment scripts
- For Terraform: Terraform v1.0 or later installed
- For Bicep: Bicep CLI installed (comes with Azure CLI 2.20.0+)

## Architecture Overview

This solution implements an automated infrastructure deployment workflow using:

- **Azure Container Apps Jobs**: Serverless, event-driven execution platform
- **Azure Resource Manager**: Infrastructure management and ARM template deployment
- **Azure Storage Account**: Secure storage for deployment artifacts and logs
- **Azure Key Vault**: Enterprise-grade secret and credential management
- **Managed Identity**: Secure, credential-free authentication
- **RBAC**: Fine-grained access control and permissions management

## Quick Start

### Using Bicep

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-deployment-automation" \
    --template-file main.bicep \
    --parameters environmentName="demo" \
    --parameters location="eastus"

# Verify deployment
az containerapp job list \
    --resource-group "rg-deployment-automation" \
    --output table
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az containerapp job list \
    --resource-group "rg-deployment-automation" \
    --output table
```

## Customization

### Key Configuration Options

#### Bicep Parameters
- `environmentName`: Environment identifier (dev, staging, prod)
- `location`: Azure region for resource deployment
- `containerCpuCores`: CPU allocation for container jobs (default: 0.5)
- `containerMemory`: Memory allocation for container jobs (default: 1.0Gi)
- `scheduleCronExpression`: Cron expression for scheduled jobs (default: "0 2 * * *")

#### Terraform Variables
- `resource_group_name`: Name of the resource group
- `location`: Azure region for resources
- `environment`: Environment identifier
- `container_cpu`: CPU allocation for containers
- `container_memory`: Memory allocation for containers
- `schedule_cron`: Cron expression for scheduled execution

#### Environment Variables (Bash Scripts)
- `RESOURCE_GROUP`: Resource group name
- `LOCATION`: Azure region
- `CONTAINER_APPS_ENV`: Container Apps environment name
- `JOB_NAME`: Container Apps job name
- `KEY_VAULT_NAME`: Key Vault name
- `STORAGE_ACCOUNT`: Storage account name

### Deployment Scenarios

#### Development Environment
```bash
# Bicep
az deployment group create \
    --resource-group "rg-deployment-dev" \
    --template-file main.bicep \
    --parameters environmentName="dev" \
    --parameters containerCpuCores=0.25 \
    --parameters containerMemory="0.5Gi"

# Terraform
terraform apply -var="environment=dev" -var="container_cpu=0.25"
```

#### Production Environment
```bash
# Bicep
az deployment group create \
    --resource-group "rg-deployment-prod" \
    --template-file main.bicep \
    --parameters environmentName="prod" \
    --parameters containerCpuCores=1.0 \
    --parameters containerMemory="2.0Gi"

# Terraform
terraform apply -var="environment=prod" -var="container_cpu=1.0"
```

## Testing the Deployment

### 1. Verify Container Apps Job Creation

```bash
# Check job status
az containerapp job show \
    --name "deployment-job" \
    --resource-group "rg-deployment-automation" \
    --output table

# Verify managed identity assignment
az containerapp job show \
    --name "deployment-job" \
    --resource-group "rg-deployment-automation" \
    --query "identity.userAssignedIdentities"
```

### 2. Test Manual Job Execution

```bash
# Start manual job execution
JOB_EXECUTION_NAME=$(az containerapp job start \
    --name "deployment-job" \
    --resource-group "rg-deployment-automation" \
    --query "name" --output tsv)

# Monitor execution
az containerapp job execution show \
    --name ${JOB_EXECUTION_NAME} \
    --job-name "deployment-job" \
    --resource-group "rg-deployment-automation" \
    --output table
```

### 3. Verify Deployment Artifacts

```bash
# Check storage containers
az storage container list \
    --account-name <storage-account-name> \
    --auth-mode login \
    --output table

# Verify Key Vault access
az keyvault secret list \
    --vault-name <key-vault-name> \
    --output table
```

## Security Considerations

### Managed Identity Configuration
- User-assigned managed identity for secure authentication
- RBAC permissions follow principle of least privilege
- No stored credentials in container configurations

### Key Vault Integration
- Enterprise-grade secret management
- RBAC-based access control
- Audit logging for all secret access

### Network Security
- Private endpoints for storage account access
- Container Apps environment isolation
- Secure communication between all components

### Best Practices Implemented
- Managed identity authentication
- Least privilege access controls
- Encrypted storage for all artifacts
- Audit logging for all operations
- Secure container image sources

## Monitoring and Logging

### Azure Monitor Integration
```bash
# Enable Container Apps monitoring
az monitor log-analytics workspace create \
    --resource-group "rg-deployment-automation" \
    --workspace-name "law-deployment-monitoring"

# View job execution logs
az containerapp job execution logs show \
    --name <execution-name> \
    --job-name "deployment-job" \
    --resource-group "rg-deployment-automation"
```

### Key Metrics to Monitor
- Job execution success/failure rates
- Deployment duration and performance
- Resource utilization during execution
- Error rates and failure patterns
- Storage account usage and costs

## Troubleshooting

### Common Issues

#### Job Execution Failures
```bash
# Check job logs
az containerapp job execution logs show \
    --name <execution-name> \
    --job-name "deployment-job" \
    --resource-group "rg-deployment-automation"

# Verify managed identity permissions
az role assignment list \
    --assignee <managed-identity-client-id> \
    --output table
```

#### Storage Access Issues
```bash
# Verify storage account permissions
az storage container show \
    --name "arm-templates" \
    --account-name <storage-account-name> \
    --auth-mode login

# Check RBAC assignments
az role assignment list \
    --scope "/subscriptions/<subscription-id>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<storage-account>"
```

#### Key Vault Access Problems
```bash
# Verify Key Vault permissions
az keyvault show \
    --name <key-vault-name> \
    --resource-group "rg-deployment-automation"

# Check RBAC assignments
az role assignment list \
    --scope "/subscriptions/<subscription-id>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv-name>"
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete \
    --name "rg-deployment-automation" \
    --yes \
    --no-wait

# Also clean up any target resource groups created by deployments
az group delete \
    --name "rg-deployment-target" \
    --yes \
    --no-wait
```

### Using Terraform
```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before destroying resources
```

### Manual Cleanup Verification
```bash
# Verify all resources are removed
az group list \
    --query "[?contains(name, 'deployment')]" \
    --output table

# Check for any remaining storage accounts
az storage account list \
    --query "[?contains(name, 'deploy')]" \
    --output table
```

## Cost Optimization

### Resource Sizing Recommendations

#### Development Environment
- Container CPU: 0.25 cores
- Container Memory: 0.5Gi
- Storage: Standard_LRS
- Key Vault: Standard tier

#### Production Environment
- Container CPU: 1.0 cores
- Container Memory: 2.0Gi
- Storage: Standard_ZRS
- Key Vault: Premium tier

### Cost Monitoring
```bash
# Enable cost alerts
az consumption budget create \
    --resource-group "rg-deployment-automation" \
    --budget-name "deployment-budget" \
    --amount 100 \
    --time-grain Monthly
```

## Advanced Configuration

### Event-Driven Deployments
Configure Container Apps Jobs to respond to external events:

```bash
# Create event-driven job (example with webhook)
az containerapp job create \
    --name "deployment-job-webhook" \
    --resource-group "rg-deployment-automation" \
    --environment "cae-deployment-env" \
    --trigger-type "Event" \
    --scale-rule-name "webhook-scale" \
    --scale-rule-type "http"
```

### Multi-Environment Support
Deploy separate instances for different environments:

```bash
# Development environment
terraform apply -var="environment=dev" -var="location=eastus"

# Staging environment
terraform apply -var="environment=staging" -var="location=westus2"

# Production environment
terraform apply -var="environment=prod" -var="location=eastus2"
```

## Support and Documentation

### Additional Resources
- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [Azure Resource Manager Templates](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/)
- [Azure Key Vault Documentation](https://docs.microsoft.com/en-us/azure/key-vault/)
- [Managed Identity Documentation](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)

### Getting Help
For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review Azure service documentation
3. Consult the original recipe documentation
4. Contact your Azure support team

### Contributing
To improve this infrastructure code:
1. Test changes in a development environment
2. Follow Azure best practices
3. Update documentation as needed
4. Verify security configurations
5. Test cleanup procedures

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Modify as needed for your specific requirements.