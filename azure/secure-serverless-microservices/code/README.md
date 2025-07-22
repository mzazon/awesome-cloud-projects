# Infrastructure as Code for Secure Serverless Microservices with Container Apps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure Serverless Microservices with Container Apps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.54.0 or later installed and configured
- Azure subscription with appropriate permissions:
  - Contributor role on subscription or resource group
  - Key Vault Contributor role for secret management
  - Container Registry Contributor role for image management
- Docker Desktop (optional, for local container development)
- For Terraform: Terraform v1.0+ installed
- For Bicep: Azure CLI with Bicep extension installed

## Architecture Overview

This solution deploys:

- **Azure Container Registry**: Private container image repository
- **Azure Key Vault**: Centralized secret management with managed identity access
- **Azure Container Apps Environment**: Serverless container hosting platform
- **Two Container Apps**: API service (external ingress) and worker service (internal ingress)
- **Azure Monitor**: Log Analytics workspace and Application Insights for monitoring
- **Managed Identities**: System-assigned identities for secure resource access

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the bicep directory
cd bicep/

# Login to Azure (if not already authenticated)
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Create a resource group
az group create \
    --name rg-secure-containers \
    --location eastus

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-secure-containers \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment progress
az deployment group show \
    --resource-group rg-secure-containers \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply

# Confirm deployment when prompted
# Type 'yes' to proceed
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts for configuration
```

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize your deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "environment": {
      "value": "demo"
    },
    "containerAppsEnvironmentName": {
      "value": "cae-secure-containers"
    },
    "keyVaultName": {
      "value": "kv-secure-containers"
    },
    "containerRegistryName": {
      "value": "acrsecurecontainers"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize your deployment:

```hcl
location                = "East US"
resource_group_name     = "rg-secure-containers"
environment            = "demo"
container_registry_name = "acrsecurecontainers"
key_vault_name         = "kv-secure-containers"
environment_name       = "cae-secure-containers"

# Optional: Customize app settings
api_app_name           = "api-service"
worker_app_name        = "worker-service"
min_replicas          = 1
max_replicas          = 5
```

### Bash Script Configuration

The bash scripts will prompt for configuration or use environment variables:

```bash
# Set environment variables before running deploy.sh
export LOCATION="eastus"
export RESOURCE_GROUP="rg-secure-containers"
export ENVIRONMENT="demo"
```

## Post-Deployment Configuration

### 1. Build and Push Container Images

After infrastructure deployment, build and push your container images:

```bash
# Login to your container registry
az acr login --name your-registry-name

# Build and push sample API image
docker build -t your-registry.azurecr.io/api-service:v1 ./api-service/
docker push your-registry.azurecr.io/api-service:v1

# Build and push sample worker image
docker build -t your-registry.azurecr.io/worker-service:v1 ./worker-service/
docker push your-registry.azurecr.io/worker-service:v1
```

### 2. Configure Application Secrets

Add your application secrets to Key Vault:

```bash
# Set database connection string
az keyvault secret set \
    --vault-name your-key-vault-name \
    --name "DatabaseConnectionString" \
    --value "your-database-connection-string"

# Set API keys
az keyvault secret set \
    --vault-name your-key-vault-name \
    --name "ApiKey" \
    --value "your-api-key"

# Set service bus connection
az keyvault secret set \
    --vault-name your-key-vault-name \
    --name "ServiceBusConnection" \
    --value "your-service-bus-connection"
```

### 3. Update Container Apps with Images

Update the Container Apps with your custom images:

```bash
# Update API service
az containerapp update \
    --name api-service \
    --resource-group rg-secure-containers \
    --image your-registry.azurecr.io/api-service:v1

# Update worker service
az containerapp update \
    --name worker-service \
    --resource-group rg-secure-containers \
    --image your-registry.azurecr.io/worker-service:v1
```

## Validation

### Verify Deployment

```bash
# Check Container Apps status
az containerapp list \
    --resource-group rg-secure-containers \
    --query "[].{Name:name,Status:properties.runningStatus}" \
    --output table

# Get application URLs
az containerapp show \
    --name api-service \
    --resource-group rg-secure-containers \
    --query properties.configuration.ingress.fqdn \
    --output tsv

# Test Key Vault access
az keyvault secret list \
    --vault-name your-key-vault-name \
    --query "[].name" \
    --output table
```

### Monitor Applications

```bash
# View container logs
az containerapp logs show \
    --name api-service \
    --resource-group rg-secure-containers \
    --tail 50

# Query Log Analytics
az monitor log-analytics query \
    --workspace your-log-analytics-workspace-id \
    --analytics-query "ContainerAppConsoleLogs_CL | take 10"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-secure-containers \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
# Type 'yes' to proceed
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts for confirmation
```

## Security Considerations

- **Managed Identities**: All authentication between services uses managed identities
- **Key Vault Integration**: Secrets are stored in Key Vault and accessed via managed identities
- **Network Security**: Worker service uses internal ingress only
- **Container Registry**: Private registry with Azure AD authentication
- **Monitoring**: Comprehensive logging and monitoring enabled

## Cost Optimization

- **Consumption-based pricing**: Container Apps scale to zero when not in use
- **Shared environment**: Both apps share the same Container Apps Environment
- **Right-sizing**: CPU and memory allocations optimized for workload
- **Monitoring**: Application Insights helps identify optimization opportunities

## Troubleshooting

### Common Issues

1. **Container App won't start**:
   - Check container logs: `az containerapp logs show`
   - Verify image is accessible in registry
   - Check managed identity permissions

2. **Key Vault access denied**:
   - Verify managed identity has appropriate Key Vault permissions
   - Check Key Vault access policies
   - Ensure secrets exist in Key Vault

3. **Image pull failures**:
   - Verify Container Registry permissions
   - Check managed identity configuration
   - Ensure images exist in registry

### Debug Commands

```bash
# Check managed identity details
az containerapp show \
    --name api-service \
    --resource-group rg-secure-containers \
    --query identity

# Verify Key Vault access policies
az keyvault show \
    --name your-key-vault-name \
    --query properties.accessPolicies

# Check Container Registry permissions
az acr show \
    --name your-registry-name \
    --query adminUserEnabled
```

## Support

For issues with this infrastructure code, refer to:

- [Azure Container Apps documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Azure Key Vault documentation](https://learn.microsoft.com/en-us/azure/key-vault/)
- [Original recipe documentation](../implementing-secure-container-orchestration-with-azure-container-apps-and-azure-key-vault.md)

## Additional Resources

- [Container Apps best practices](https://learn.microsoft.com/en-us/azure/container-apps/best-practices)
- [Key Vault security recommendations](https://learn.microsoft.com/en-us/azure/key-vault/general/security-recommendations)
- [Azure Monitor for Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/monitor)
- [Managed Identity documentation](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)