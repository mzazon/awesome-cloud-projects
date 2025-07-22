# Infrastructure as Code for Secure User Onboarding Workflows with Azure Entra ID and Azure Service Bus

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure User Onboarding Workflows with Azure Entra ID and Azure Service Bus".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.50.0 or later)
- Azure subscription with appropriate permissions (Owner or Contributor role)
- Azure Entra ID Premium P1 or P2 licenses for advanced identity governance features
- Basic understanding of Azure Resource Manager templates
- PowerShell or Bash environment for script execution

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-user-onboarding \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment status
az deployment group show \
    --resource-group rg-user-onboarding \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# Verify deployment
terraform output
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

## Configuration

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
    "resourcePrefix": {
      "value": "onboarding"
    },
    "environment": {
      "value": "demo"
    },
    "enableSoftDelete": {
      "value": true
    },
    "keyVaultSku": {
      "value": "standard"
    },
    "serviceBusSku": {
      "value": "Standard"
    },
    "logicAppSku": {
      "value": "WS1"
    }
  }
}
```

### Terraform Variables

Modify `terraform/variables.tf` or create a `terraform.tfvars` file:

```hcl
# terraform.tfvars
location = "eastus"
resource_prefix = "onboarding"
environment = "demo"
enable_soft_delete = true
key_vault_sku = "standard"
service_bus_sku = "Standard"
logic_app_sku = "WS1"
```

### Environment Variables for Scripts

Set these environment variables before running bash scripts:

```bash
export AZURE_LOCATION="eastus"
export RESOURCE_PREFIX="onboarding"
export ENVIRONMENT="demo"
export ENABLE_SOFT_DELETE="true"
export KEY_VAULT_SKU="standard"
export SERVICE_BUS_SKU="Standard"
export LOGIC_APP_SKU="WS1"
```

## Deployed Resources

This IaC creates the following Azure resources:

### Core Infrastructure
- **Resource Group**: Container for all resources
- **Azure Key Vault**: Secure storage for credentials and secrets
- **Azure Service Bus Namespace**: Messaging infrastructure
- **Azure Storage Account**: Logic Apps state management
- **Azure Logic App**: Workflow orchestration

### Service Bus Components
- **Queue**: `user-onboarding-queue` for processing requests
- **Topic**: `user-onboarding-events` for event broadcasting
- **Authorization Rules**: Secure access policies

### Security Configuration
- **Azure Entra ID App Registration**: Service principal for automation
- **RBAC Assignments**: Least privilege access controls
- **Key Vault Access Policies**: Secure credential management
- **Managed Identity**: Service-to-service authentication

### Monitoring and Logging
- **Application Insights**: Performance monitoring
- **Log Analytics Workspace**: Centralized logging
- **Azure Monitor**: Alerting and dashboards

## Validation

After deployment, verify the infrastructure:

### Check Resource Group
```bash
az group show --name rg-user-onboarding --query properties.provisioningState
```

### Verify Key Vault
```bash
az keyvault show --name <key-vault-name> --query properties.vaultUri
```

### Test Service Bus
```bash
az servicebus namespace show --name <service-bus-namespace> --resource-group rg-user-onboarding --query status
```

### Validate Logic Apps
```bash
az logicapp show --name <logic-app-name> --resource-group rg-user-onboarding --query state
```

## Testing the Solution

### Test Service Bus Messaging
```bash
# Send test message to onboarding queue
az servicebus message send \
    --namespace-name <service-bus-namespace> \
    --queue-name user-onboarding-queue \
    --body '{"userName":"testuser","email":"test@company.com","department":"IT","role":"Developer"}' \
    --content-type "application/json"
```

### Test Logic Apps Workflow
```bash
# Get Logic Apps trigger URL
TRIGGER_URL=$(az logicapp show --name <logic-app-name> --resource-group rg-user-onboarding --query defaultHostName --output tsv)

# Test workflow with sample data
curl -X POST \
    -H "Content-Type: application/json" \
    -d '{"userName":"john.doe","email":"john.doe@company.com","department":"Sales","manager":"jane.smith@company.com","role":"Account Manager"}' \
    "https://${TRIGGER_URL}/triggers/manual/invoke"
```

## Monitoring

### Application Insights
- Navigate to Application Insights in Azure Portal
- View request rates, response times, and failure rates
- Set up custom alerts for onboarding failures

### Log Analytics
- Query logs using KQL (Kusto Query Language)
- Monitor workflow execution patterns
- Track security events and access patterns

### Service Bus Metrics
- Monitor queue length and message processing rates
- Set up alerts for dead letter queue messages
- Track throughput and latency metrics

## Security Considerations

### Key Vault Security
- RBAC authorization enabled
- Soft delete protection configured
- Network access restrictions applied
- Audit logging enabled

### Service Bus Security
- Shared access signatures for fine-grained access
- Virtual network integration available
- Message encryption at rest and in transit

### Logic Apps Security
- Managed identity for authentication
- Secure parameter handling
- Input/output encryption
- Access control policies

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Verify Azure CLI authentication: `az account show`
   - Check subscription permissions: `az role assignment list`

2. **Resource Name Conflicts**
   - Azure resources require globally unique names
   - Modify resource prefix or add random suffix

3. **Deployment Failures**
   - Check deployment logs: `az deployment group show`
   - Verify resource quotas and limits

4. **Logic Apps Workflow Errors**
   - Review workflow run history in Azure Portal
   - Check connector configurations and permissions

### Debugging Commands

```bash
# Check deployment status
az deployment group list --resource-group rg-user-onboarding

# View deployment logs
az deployment group show --resource-group rg-user-onboarding --name main

# Check resource health
az resource list --resource-group rg-user-onboarding --query "[].{Name:name,Type:type,Status:properties.provisioningState}"
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group and all resources
az group delete --name rg-user-onboarding --yes --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Cleanup Verification
```bash
# Verify resource group deletion
az group exists --name rg-user-onboarding

# Check for remaining resources
az resource list --resource-group rg-user-onboarding 2>/dev/null || echo "Resource group successfully deleted"

# Clean up application registration
az ad app delete --id <app-registration-id>
```

## Cost Optimization

### Resource Sizing
- Use Standard tier for Service Bus in production
- Consider Basic tier for development/testing
- Monitor Logic Apps execution frequency

### Storage Costs
- Configure appropriate storage account tier
- Enable lifecycle management for older logs
- Use Azure Storage cost optimization features

### Monitoring Costs
- Set up budget alerts for resource spending
- Use Azure Cost Management for detailed analysis
- Consider reserved instances for predictable workloads

## Customization

### Adding New Onboarding Steps
1. Modify Logic Apps workflow definition
2. Add new Service Bus topics/queues as needed
3. Update Key Vault secrets configuration
4. Extend monitoring and alerting

### Integration with Existing Systems
- Modify triggers to accept different input formats
- Add connectors for existing HR systems
- Implement custom authentication flows
- Extend notification mechanisms

### Multi-Environment Support
- Create separate parameter files for each environment
- Use Azure DevOps or GitHub Actions for CI/CD
- Implement environment-specific configurations
- Set up appropriate RBAC for each environment

## Production Considerations

### High Availability
- Deploy across multiple availability zones
- Configure Service Bus geo-disaster recovery
- Implement Logic Apps redundancy
- Set up cross-region backup strategies

### Performance Optimization
- Monitor and tune Logic Apps execution
- Optimize Service Bus message processing
- Implement caching where appropriate
- Use connection pooling for external services

### Compliance
- Enable audit logging for all components
- Implement data retention policies
- Configure encryption at rest and in transit
- Maintain compliance documentation

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Azure service documentation
3. Consult Azure support resources
4. Review troubleshooting section above

## Additional Resources

- [Azure Entra ID Documentation](https://learn.microsoft.com/en-us/azure/active-directory/)
- [Azure Service Bus Documentation](https://learn.microsoft.com/en-us/azure/service-bus-messaging/)
- [Azure Logic Apps Documentation](https://learn.microsoft.com/en-us/azure/logic-apps/)
- [Azure Key Vault Documentation](https://learn.microsoft.com/en-us/azure/key-vault/)
- [Azure Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)