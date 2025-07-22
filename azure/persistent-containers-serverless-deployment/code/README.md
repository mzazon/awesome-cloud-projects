# Infrastructure as Code for Persistent Containers with Serverless Deployment

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Persistent Containers with Serverless Deployment".

## Available Implementations

- **Bicep**: Azure's recommended Infrastructure as Code language
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions:
  - Contributor role on target resource group
  - Storage Account Contributor for Azure Files
  - AcrPull role for Azure Container Registry
- For Terraform: Terraform v1.0+ installed
- For Bicep: Azure CLI with Bicep extension installed
- Basic understanding of container concepts and Azure services

## Quick Start

### Using Bicep

```bash
# Navigate to the Bicep directory
cd bicep/

# Create a resource group
az group create \
    --name rg-stateful-containers \
    --location eastus

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-stateful-containers \
    --template-file main.bicep \
    --parameters @parameters.json

# Check deployment status
az deployment group show \
    --resource-group rg-stateful-containers \
    --name main
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
az container list --resource-group rg-stateful-containers --output table
```

## Architecture Overview

This implementation deploys:

- **Azure Storage Account** with Azure Files file share for persistent storage
- **Azure Container Registry** for private container image storage
- **Azure Container Instances** for serverless container hosting:
  - PostgreSQL database container with persistent storage
  - Application container (Nginx) with shared storage access
  - Background worker container for processing tasks
  - Monitoring-enabled container with Log Analytics integration
- **Log Analytics Workspace** for centralized logging and monitoring
- **Networking** configuration for secure container communication

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "storageAccountName": {
      "value": "statefulstorage"
    },
    "containerRegistryName": {
      "value": "statefulregistry"
    },
    "fileShareName": {
      "value": "containerdata"
    },
    "fileShareQuota": {
      "value": 100
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
location                 = "eastus"
resource_group_name      = "rg-stateful-containers"
storage_account_name     = "statefulstorage"
container_registry_name  = "statefulregistry"
file_share_name         = "containerdata"
file_share_quota        = 100
postgres_password       = "SecurePassword123!"
```

## Deployment Steps

### 1. Pre-deployment Validation

```bash
# Verify Azure CLI authentication
az account show

# Check resource provider registrations
az provider show --namespace Microsoft.ContainerInstance --query "registrationState"
az provider show --namespace Microsoft.Storage --query "registrationState"
az provider show --namespace Microsoft.ContainerRegistry --query "registrationState"
```

### 2. Resource Group Creation

```bash
# Create resource group (if not using IaC)
az group create \
    --name rg-stateful-containers \
    --location eastus \
    --tags purpose=recipe environment=demo
```

### 3. Deploy Infrastructure

Choose one of the deployment methods above based on your preference and organizational standards.

### 4. Post-deployment Verification

```bash
# Verify storage account and file share
az storage account show \
    --resource-group rg-stateful-containers \
    --name <storage-account-name>

# Check container instances status
az container list \
    --resource-group rg-stateful-containers \
    --output table

# Test application endpoint
curl -I http://<app-fqdn>

# View container logs
az container logs \
    --resource-group rg-stateful-containers \
    --name app-stateful
```

## Validation & Testing

### Storage Integration Test

```bash
# Test Azure Files connectivity
az storage file list \
    --share-name containerdata \
    --account-name <storage-account-name> \
    --output table

# Upload test file
echo "Test persistence" > test-file.txt
az storage file upload \
    --share-name containerdata \
    --source test-file.txt \
    --path test-file.txt \
    --account-name <storage-account-name>
```

### Container Functionality Test

```bash
# Test database container
az container exec \
    --resource-group rg-stateful-containers \
    --name postgres-stateful \
    --exec-command "psql -U postgres -d appdb -c 'SELECT version();'"

# Test application container
az container show \
    --resource-group rg-stateful-containers \
    --name app-stateful \
    --query "ipAddress.fqdn"
```

### Monitoring and Logging

```bash
# View Log Analytics workspace
az monitor log-analytics workspace show \
    --resource-group rg-stateful-containers \
    --workspace-name <workspace-name>

# Query container logs
az monitor log-analytics query \
    --workspace <workspace-id> \
    --analytics-query "ContainerInstanceLog_CL | limit 10"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-stateful-containers \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group exists --name rg-stateful-containers
```

## Troubleshooting

### Common Issues

1. **Storage Account Name Conflicts**
   - Storage account names must be globally unique
   - Use the random suffix generation in scripts
   - Check name availability: `az storage account check-name --name <name>`

2. **Container Registry Access Issues**
   - Ensure admin user is enabled on ACR
   - Verify container instances have correct registry credentials
   - Check firewall rules if using private registry

3. **Azure Files Mount Issues**
   - Verify storage account key is correct
   - Check file share permissions and quota
   - Ensure container has proper Linux capabilities

4. **Container Startup Failures**
   - Check container logs: `az container logs --name <container-name>`
   - Verify environment variables are set correctly
   - Check resource constraints (CPU/memory limits)

### Debugging Commands

```bash
# Check deployment status
az deployment group show \
    --resource-group rg-stateful-containers \
    --name <deployment-name>

# View container events
az container show \
    --resource-group rg-stateful-containers \
    --name <container-name> \
    --query "containers[0].instanceView.events"

# Check storage account connectivity
az storage account show-connection-string \
    --resource-group rg-stateful-containers \
    --name <storage-account-name>
```

## Cost Optimization

### Estimated Costs

- **Azure Container Instances**: $0.0000125 per vCPU-second + $0.0000014 per GB-second
- **Azure Files**: $0.06 per GB per month (Standard tier)
- **Azure Container Registry**: $5 per month (Basic tier)
- **Log Analytics**: $2.30 per GB ingested

### Cost Optimization Tips

1. **Right-size container resources** based on actual usage
2. **Use Azure Files Standard tier** for development/testing
3. **Configure container restart policies** to avoid unnecessary restarts
4. **Monitor Log Analytics ingestion** to control logging costs
5. **Use Azure Cost Management** to set budgets and alerts

## Security Considerations

### Implemented Security Features

- **Storage account encryption** at rest and in transit
- **Container Registry** with admin user authentication
- **Private container networking** within Azure backbone
- **Log Analytics** for security monitoring and auditing
- **Resource tagging** for governance and compliance

### Additional Security Recommendations

1. **Enable Azure Active Directory integration** for container registry
2. **Use Azure Key Vault** for sensitive configuration management
3. **Implement network security groups** for container isolation
4. **Enable Azure Security Center** for container security monitoring
5. **Use managed identity** instead of storage account keys

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Azure Documentation**: [Azure Container Instances](https://docs.microsoft.com/en-us/azure/container-instances/)
3. **Azure Files Documentation**: [Azure Files](https://docs.microsoft.com/en-us/azure/storage/files/)
4. **Community Support**: [Azure Community](https://docs.microsoft.com/en-us/answers/products/azure)

## Contributing

To improve this infrastructure code:

1. Test changes thoroughly in a development environment
2. Follow Azure best practices and security guidelines
3. Update documentation for any configuration changes
4. Validate against the original recipe requirements