# Infrastructure as Code for Event-Driven Security Governance with Event Grid and Managed Identity

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Event-Driven Security Governance with Event Grid and Managed Identity".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI 2.50.0 or later installed and configured
- Azure subscription with Contributor permissions
- PowerShell or Bash shell environment
- Basic understanding of Azure Event Grid and Managed Identity concepts
- Estimated cost: $5-15 per month for testing resources

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to the bicep directory
cd bicep/

# Create a resource group
az group create --name rg-security-governance --location eastus

# Deploy the Bicep template
az deployment group create \
    --resource-group rg-security-governance \
    --template-file main.bicep \
    --parameters @parameters.json

# Get deployment outputs
az deployment group show \
    --resource-group rg-security-governance \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
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

# Verify deployment
az resource list --resource-group rg-security-governance --output table
```

## Architecture Overview

This solution creates an event-driven security governance system with the following components:

- **Event Grid Topic**: Centralized event collection and routing
- **Event Grid Subscription**: Filters and routes security-relevant events
- **Azure Function**: Serverless security assessment and remediation
- **Managed Identity**: Secure, credential-free authentication
- **Storage Account**: Function runtime and compliance artifacts storage
- **Log Analytics**: Centralized logging and monitoring
- **Alert Rules**: Proactive security violation notifications

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize the deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "resourcePrefix": {
      "value": "security-governance"
    },
    "environment": {
      "value": "demo"
    },
    "alertEmail": {
      "value": "security@company.com"
    }
  }
}
```

### Terraform Variables

Customize `terraform/terraform.tfvars`:

```hcl
location = "East US"
resource_prefix = "security-governance"
environment = "demo"
alert_email = "security@company.com"
function_runtime = "python"
log_retention_days = 30
```

### Environment Variables for Scripts

Set these variables before running the bash scripts:

```bash
export RESOURCE_GROUP="rg-security-governance"
export LOCATION="eastus"
export ALERT_EMAIL="security@company.com"
export ENVIRONMENT="demo"
```

## Post-Deployment Configuration

### 1. Deploy Function Code

After infrastructure deployment, deploy the security assessment function:

```bash
# Navigate to the function directory created during deployment
cd security-function/

# Package the function code
zip -r ../security-function.zip .

# Deploy to the Function App
az functionapp deployment source config-zip \
    --name func-security-[suffix] \
    --resource-group rg-security-governance \
    --src security-function.zip
```

### 2. Test the Security Governance System

Create a test resource to trigger security events:

```bash
# Create a test VM to trigger security assessment
az vm create \
    --name test-vm \
    --resource-group rg-security-governance \
    --image Ubuntu2204 \
    --size Standard_B1s \
    --admin-username azureuser \
    --generate-ssh-keys

# Monitor function logs
az functionapp logs tail \
    --name func-security-[suffix] \
    --resource-group rg-security-governance
```

### 3. Configure Alert Recipients

Update the action group with appropriate security team contacts:

```bash
# Add additional email recipients
az monitor action-group update \
    --name ag-security-[suffix] \
    --resource-group rg-security-governance \
    --add-receivers email name=SecurityTeam2 email=security2@company.com
```

## Monitoring and Maintenance

### View Security Events

```bash
# Query Log Analytics for security events
az monitor log-analytics query \
    --workspace [workspace-id] \
    --analytics-query "traces | where message contains 'security' | order by timestamp desc"
```

### Monitor Function Performance

```bash
# View function execution metrics
az monitor metrics list \
    --resource "/subscriptions/[subscription-id]/resourceGroups/rg-security-governance/providers/Microsoft.Web/sites/func-security-[suffix]" \
    --metric FunctionExecutionCount \
    --interval 1h
```

### Update Security Policies

The function code can be updated to include new security checks:

1. Modify the function code in `security-function/`
2. Redeploy using the zip deployment method
3. Test with sample resources
4. Monitor logs for proper execution

## Troubleshooting

### Common Issues

1. **Function Not Triggering**: Verify Event Grid subscription is active and function endpoint is correct
2. **Permission Errors**: Ensure managed identity has appropriate RBAC assignments
3. **Alert Not Firing**: Check alert rule conditions and action group configuration

### Debugging Commands

```bash
# Check Event Grid subscription status
az eventgrid event-subscription show \
    --name security-governance-subscription \
    --source-resource-id "/subscriptions/[subscription-id]/resourceGroups/rg-security-governance"

# Verify managed identity assignments
az role assignment list \
    --assignee [managed-identity-principal-id] \
    --all

# Test function manually
az functionapp function invoke \
    --name func-security-[suffix] \
    --resource-group rg-security-governance \
    --function-name SecurityEventProcessor
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name rg-security-governance --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup Verification

```bash
# Verify resource group deletion
az group exists --name rg-security-governance

# Check for any remaining resources
az resource list --resource-group rg-security-governance --output table
```

## Security Considerations

### Best Practices Implemented

- **Managed Identity**: Eliminates credential management and storage
- **Least Privilege**: RBAC assignments follow minimum required permissions
- **Encryption**: All data encrypted at rest and in transit
- **Network Security**: Private endpoints where applicable
- **Monitoring**: Comprehensive logging and alerting

### Additional Security Recommendations

1. **Network Isolation**: Consider using private endpoints for Function App
2. **Key Rotation**: Implement automated key rotation for storage accounts
3. **Compliance**: Enable Azure Policy for additional governance
4. **Backup**: Configure backup for Log Analytics workspace
5. **Disaster Recovery**: Implement cross-region replication for critical components

## Cost Optimization

### Resource Costs

- **Event Grid**: Pay-per-operation pricing
- **Azure Functions**: Consumption plan with automatic scaling
- **Storage**: Standard LRS for cost optimization
- **Log Analytics**: Pay-per-ingestion pricing

### Cost Reduction Tips

1. **Function Optimization**: Optimize function execution time
2. **Log Retention**: Adjust retention periods based on compliance requirements
3. **Alert Frequency**: Tune alert thresholds to reduce noise
4. **Resource Scaling**: Use appropriate SKUs for workload requirements

## Support and Resources

### Documentation Links

- [Azure Event Grid Documentation](https://docs.microsoft.com/en-us/azure/event-grid/)
- [Azure Managed Identity Documentation](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)

### Getting Help

1. **Azure Support**: Contact Azure support for service-specific issues
2. **Community**: Use Azure forums and Stack Overflow for community help
3. **Documentation**: Refer to official Azure documentation for detailed guidance
4. **Recipe Issues**: Report issues with the recipe implementation

## Contributing

When extending this solution:

1. Follow Azure naming conventions
2. Implement proper error handling
3. Add comprehensive logging
4. Update documentation
5. Test thoroughly before deployment
6. Consider security implications of changes

## Version History

- **v1.0**: Initial implementation with basic security governance
- **v1.1**: Enhanced monitoring and alerting capabilities
- **Current**: Improved documentation and deployment options

For updates and enhancements, refer to the original recipe documentation.