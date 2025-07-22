# Infrastructure as Code for Centralized Infrastructure Provisioning with Azure Automation and ARM Templates

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Centralized Infrastructure Provisioning with Azure Automation and ARM Templates".

## Available Implementations

- **Bicep**: Microsoft's recommended domain-specific language (DSL) for Azure infrastructure
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with Owner or Contributor permissions
- Basic knowledge of ARM templates and PowerShell
- Understanding of Azure Resource Manager concepts
- For Terraform: Terraform CLI installed (version 1.0+)
- For Bicep: Bicep CLI installed (latest version)

## Quick Start

### Using Bicep
```bash
# Deploy using Bicep
cd bicep/
az deployment group create \
    --resource-group rg-automation-demo \
    --template-file main.bicep \
    --parameters location=eastus automationAccountName=aa-infra-provisioning
```

### Using Terraform
```bash
# Deploy using Terraform
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts
```bash
# Make scripts executable and deploy
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure deploys:

- **Azure Automation Account** with system-assigned managed identity
- **Azure Storage Account** with file share for ARM template storage
- **Log Analytics Workspace** for centralized monitoring and logging
- **PowerShell Runbooks** for automated infrastructure deployment
- **Role-Based Access Control (RBAC)** assignments for secure operations
- **Sample ARM Templates** for demonstration purposes

## Resource Details

### Core Components

1. **Automation Account**: Provides cloud-based automation and configuration management
2. **Storage Account**: Centralized storage for ARM templates and deployment artifacts
3. **Log Analytics**: Monitoring and logging infrastructure for audit trails
4. **Managed Identity**: Secure authentication mechanism for runbook execution
5. **PowerShell Runbooks**: Automation scripts for infrastructure deployment

### Security Features

- Managed identity authentication (no stored credentials)
- Role-based access control with least privilege principle
- Secure storage with private endpoints
- Audit logging and monitoring capabilities
- Encryption at rest and in transit

## Deployment Options

### Option 1: Complete Infrastructure (Recommended)
Deploys the full automation infrastructure including monitoring and sample templates.

### Option 2: Minimal Infrastructure
Deploys only the core automation components without additional monitoring.

### Option 3: Custom Configuration
Allows customization of resource names, locations, and configurations.

## Configuration Parameters

| Parameter | Description | Default Value | Required |
|-----------|-------------|---------------|----------|
| `location` | Azure region for resource deployment | `eastus` | Yes |
| `resourceGroupName` | Name of the resource group | `rg-automation-demo` | Yes |
| `automationAccountName` | Name of the automation account | `aa-infra-provisioning` | Yes |
| `storageAccountName` | Name of the storage account | Auto-generated | No |
| `logAnalyticsWorkspaceName` | Name of the Log Analytics workspace | `law-automation-monitoring` | No |
| `environment` | Environment tag for resources | `demo` | No |

## Post-Deployment Steps

After infrastructure deployment, complete these steps:

1. **Upload ARM Templates**:
   ```bash
   # Upload sample ARM template to storage
   az storage file upload \
       --share-name arm-templates \
       --source infrastructure-template.json \
       --path infrastructure-template.json \
       --account-name <storage-account-name>
   ```

2. **Import PowerShell Modules**:
   ```bash
   # Install required Az modules
   az automation module install \
       --resource-group rg-automation-demo \
       --automation-account-name aa-infra-provisioning \
       --name "Az.Accounts"
   ```

3. **Test Runbook Execution**:
   ```bash
   # Start deployment runbook
   az automation runbook start \
       --resource-group rg-automation-demo \
       --automation-account-name aa-infra-provisioning \
       --name "Deploy-Infrastructure"
   ```

## Monitoring and Logging

### Log Analytics Integration
The solution includes comprehensive logging through Azure Monitor and Log Analytics:

- Runbook execution logs
- Resource deployment tracking
- Error and exception monitoring
- Performance metrics

### Monitoring Queries
Access monitoring data using these sample KQL queries:

```kusto
// Runbook execution status
AzureDiagnostics
| where Category == "JobLogs"
| summarize count() by ResultType, bin(TimeGenerated, 1h)

// Deployment success rate
AzureDiagnostics
| where Category == "JobStreams"
| where StreamType_s == "Output"
| where ResultDescription contains "✅"
```

## Troubleshooting

### Common Issues

1. **Module Installation Failures**:
   - Ensure automation account has required permissions
   - Check module compatibility with PowerShell runtime version
   - Verify network connectivity for module downloads

2. **Runbook Authentication Errors**:
   - Verify managed identity is properly configured
   - Check RBAC role assignments
   - Ensure subscription permissions are sufficient

3. **Template Deployment Failures**:
   - Validate ARM template syntax
   - Check resource name uniqueness
   - Verify resource limits and quotas

### Debugging Steps

1. **Check Automation Account Status**:
   ```bash
   az automation account show \
       --resource-group rg-automation-demo \
       --name aa-infra-provisioning
   ```

2. **Review Runbook Logs**:
   ```bash
   az automation job output \
       --resource-group rg-automation-demo \
       --automation-account-name aa-infra-provisioning \
       --job-id <job-id>
   ```

3. **Validate Storage Access**:
   ```bash
   az storage file list \
       --share-name arm-templates \
       --account-name <storage-account-name>
   ```

## Security Considerations

### Best Practices Implemented

- **Managed Identity**: Eliminates credential storage risks
- **Least Privilege**: RBAC assignments follow minimal access principle
- **Encryption**: Data encrypted at rest and in transit
- **Audit Logging**: Comprehensive logging for security monitoring
- **Network Security**: Private endpoints for secure communication

### Additional Security Recommendations

1. **Network Isolation**: Implement private endpoints for storage accounts
2. **Key Management**: Use Azure Key Vault for sensitive configuration
3. **Compliance Monitoring**: Integrate with Azure Policy for governance
4. **Regular Updates**: Keep PowerShell modules and runbooks updated

## Cost Optimization

### Cost Considerations

- **Automation Account**: Consumption-based pricing for runbook execution
- **Storage Account**: Standard LRS tier for cost-effective template storage
- **Log Analytics**: Pay-per-GB ingestion model
- **Compute**: No persistent compute resources deployed

### Cost Optimization Tips

1. **Runbook Efficiency**: Optimize runbook execution time
2. **Log Retention**: Configure appropriate log retention policies
3. **Resource Tagging**: Implement comprehensive tagging for cost tracking
4. **Monitoring**: Set up cost alerts and budgets

## Cleanup

### Using Bicep
```bash
# Delete resource group (removes all resources)
az group delete --name rg-automation-demo --yes --no-wait
```

### Using Terraform
```bash
# Destroy infrastructure
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
# Run cleanup script
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Cleanup (if needed)
```bash
# Delete specific resources
az automation account delete \
    --resource-group rg-automation-demo \
    --name aa-infra-provisioning

az storage account delete \
    --resource-group rg-automation-demo \
    --name <storage-account-name>

az monitor log-analytics workspace delete \
    --resource-group rg-automation-demo \
    --workspace-name law-automation-monitoring
```

## Customization

### Environment-Specific Configuration

Modify the following parameters for different environments:

```bash
# Development Environment
environment="dev"
location="eastus"
automationAccountName="aa-dev-automation"

# Production Environment
environment="prod"
location="eastus2"
automationAccountName="aa-prod-automation"
```

### Template Customization

1. **Add Custom ARM Templates**: Upload additional templates to the storage account
2. **Extend Runbook Logic**: Modify PowerShell runbooks for specific requirements
3. **Configure Schedules**: Set up automated deployment schedules
4. **Add Approval Workflows**: Implement approval processes for production deployments

## Integration Options

### CI/CD Integration
- **Azure DevOps**: Integrate with Azure Pipelines for automated deployments
- **GitHub Actions**: Use GitHub workflows for infrastructure updates
- **Jenkins**: Configure Jenkins pipelines for enterprise environments

### Monitoring Integration
- **Azure Monitor**: Enhanced monitoring and alerting
- **Application Insights**: Application performance monitoring
- **Third-party Tools**: Integration with monitoring platforms

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for detailed explanations
2. **Azure Documentation**: Consult [Azure Automation documentation](https://docs.microsoft.com/en-us/azure/automation/)
3. **ARM Templates**: Review [ARM template best practices](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/best-practices)
4. **Community Support**: Azure community forums and Stack Overflow
5. **Microsoft Support**: Official Microsoft support channels

## Additional Resources

- [Azure Automation Overview](https://docs.microsoft.com/en-us/azure/automation/automation-intro)
- [ARM Template Reference](https://docs.microsoft.com/en-us/azure/templates/)
- [PowerShell in Azure Automation](https://docs.microsoft.com/en-us/azure/automation/automation-powershell)
- [Managed Identity Best Practices](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview)
- [Azure Monitor for Automation](https://docs.microsoft.com/en-us/azure/automation/automation-manage-send-joblogs-log-analytics)