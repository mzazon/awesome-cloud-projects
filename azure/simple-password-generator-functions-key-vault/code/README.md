# Infrastructure as Code for Simple Password Generator with Functions and Key Vault

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Password Generator with Functions and Key Vault".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.0 or later)
- Azure subscription with appropriate permissions for:
  - Creating Resource Groups
  - Creating Azure Functions and App Service Plans
  - Creating Azure Key Vault
  - Creating Storage Accounts
  - Managing Role Assignments (Owner or User Access Administrator role)
- Node.js 18.x or later (for Function App deployment)
- Azure Functions Core Tools v4 (for local function deployment)

## Quick Start

### Using Bicep (Recommended)

Azure Bicep is Microsoft's domain-specific language for deploying Azure resources with simplified syntax and strong typing.

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-password-gen-demo \
    --template-file bicep/main.bicep \
    --parameters location=eastus

# Deploy the function code (after infrastructure deployment)
cd function-app/
func azure functionapp publish $(az deployment group show \
    --resource-group rg-password-gen-demo \
    --name main \
    --query properties.outputs.functionAppName.value -o tsv)
```

### Using Terraform

Terraform provides infrastructure as code with a declarative configuration language and comprehensive state management.

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# Deploy the function code (after infrastructure deployment)
cd ../function-app/
func azure functionapp publish $(terraform output -raw function_app_name)
```

### Using Bash Scripts

The bash scripts provide a straightforward deployment approach using Azure CLI commands with proper error handling and validation.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# The deploy script will:
# 1. Create all Azure resources
# 2. Configure managed identity and permissions
# 3. Deploy the function code
# 4. Provide testing instructions
```

## Architecture Overview

The infrastructure creates the following Azure resources:

- **Resource Group**: Container for all resources
- **Azure Key Vault**: Secure storage for generated passwords
- **Storage Account**: Required for Azure Functions runtime
- **Function App**: Serverless compute for password generation
- **Managed Identity**: Secure authentication between services
- **RBAC Role Assignment**: Key Vault access permissions

## Configuration Options

### Bicep Parameters

```bicep
// Location for all resources
param location string = resourceGroup().location

// Unique suffix for resource names (optional)
param uniqueSuffix string = uniqueString(resourceGroup().id)

// Key Vault configuration
param enableSoftDelete bool = true
param softDeleteRetentionInDays int = 7

// Function App configuration
param functionAppRuntime string = 'node'
param functionAppRuntimeVersion string = '20'
```

### Terraform Variables

```hcl
# Location for all resources
variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "East US"
}

# Unique suffix for resource naming
variable "unique_suffix" {
  description = "Unique suffix for resource names"
  type        = string
  default     = null
}

# Environment tag for resources
variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
}
```

### Bash Script Configuration

Set environment variables before running the deployment script:

```bash
# Optional: Customize deployment settings
export LOCATION="eastus"
export ENVIRONMENT="demo"
export ENABLE_SOFT_DELETE="true"
export RETENTION_DAYS="7"

# Run deployment
./scripts/deploy.sh
```

## Testing the Deployment

After successful deployment, test the password generator function:

### Get Function URL and Access Key

```bash
# Using Azure CLI
RESOURCE_GROUP=$(az group list --query "[?contains(name, 'password-gen')].name" -o tsv)
FUNCTION_APP=$(az functionapp list -g $RESOURCE_GROUP --query "[0].name" -o tsv)
FUNCTION_KEY=$(az functionapp keys list -g $RESOURCE_GROUP -n $FUNCTION_APP --query masterKey -o tsv)
FUNCTION_URL="https://${FUNCTION_APP}.azurewebsites.net"
```

### Test Password Generation

```bash
# Generate a password and store in Key Vault
curl -X POST "${FUNCTION_URL}/api/generatePassword?code=${FUNCTION_KEY}" \
     -H "Content-Type: application/json" \
     -d '{"secretName": "test-password", "length": 16}'

# Expected response:
# {
#   "message": "Password generated and stored successfully",
#   "secretName": "test-password",
#   "vaultUri": "https://kv-passgen-xxxxx.vault.azure.net/"
# }
```

### Verify Password Storage

```bash
# List secrets in Key Vault
KEY_VAULT=$(az keyvault list -g $RESOURCE_GROUP --query "[0].name" -o tsv)
az keyvault secret list --vault-name $KEY_VAULT --query "[].name" -o table

# Retrieve the generated password (for verification)
az keyvault secret show --vault-name $KEY_VAULT --name "test-password" --query "value" -o tsv
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name rg-password-gen-demo --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# 1. Prompt for confirmation
# 2. Delete all created resources
# 3. Clean up local temporary files
```

## Security Considerations

This infrastructure implements several security best practices:

- **Managed Identity**: Eliminates need for connection strings or access keys
- **Key Vault RBAC**: Fine-grained access control using Azure role-based access control
- **Soft Delete**: Protection against accidental secret deletion
- **HTTPS Only**: Function App configured for secure communication
- **Principle of Least Privilege**: Minimal required permissions granted

## Cost Optimization

The infrastructure uses cost-effective Azure services:

- **Function App Consumption Plan**: Pay-per-execution pricing
- **Standard Storage**: Lower-cost storage tier for Function App requirements
- **Key Vault Standard Tier**: Cost-effective secrets management

Estimated monthly cost for light usage: $5-15 USD

## Monitoring and Observability

Monitor the solution using these Azure services:

```bash
# View Function App logs
az monitor app-insights query \
    --app $FUNCTION_APP \
    --analytics-query "traces | where timestamp > ago(1h)" \
    --output table

# Monitor Key Vault access
az monitor activity-log list \
    --resource-group $RESOURCE_GROUP \
    --max-events 10 \
    --output table
```

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   - Verify Azure Functions Core Tools installation
   - Check Node.js version compatibility (18.x required)
   - Ensure Storage Account is accessible

2. **Key Vault access denied**:
   - Verify managed identity is enabled
   - Check RBAC role assignment
   - Confirm Key Vault URI configuration

3. **Resource naming conflicts**:
   - Key Vault names must be globally unique
   - Storage Account names must be globally unique
   - Consider using different unique suffix

### Debug Commands

```bash
# Check managed identity status
az functionapp identity show -g $RESOURCE_GROUP -n $FUNCTION_APP

# Verify role assignments
az role assignment list --assignee $(az functionapp identity show -g $RESOURCE_GROUP -n $FUNCTION_APP --query principalId -o tsv)

# Test Key Vault connectivity
az keyvault secret set --vault-name $KEY_VAULT --name "test-connection" --value "success"
```

## Customization

### Function Code Updates

The function code is located in the `function-app/` directory. To modify the password generation logic:

1. Edit `src/functions/generatePassword.js`
2. Test locally using `func start`
3. Redeploy using `func azure functionapp publish $FUNCTION_APP`

### Infrastructure Modifications

- **Bicep**: Edit `bicep/main.bicep` and redeploy using `az deployment group create`
- **Terraform**: Modify `.tf` files and run `terraform plan` then `terraform apply`
- **Bash**: Update scripts and re-run deployment

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service status and limitations
3. Consult Azure documentation for specific services
4. Use Azure support channels for service-specific issues

## Additional Resources

- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Key Vault Documentation](https://docs.microsoft.com/en-us/azure/key-vault/)
- [Azure Managed Identity Documentation](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest)