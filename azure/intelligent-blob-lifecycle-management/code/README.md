# Infrastructure as Code for Implementing Automated Blob Storage Lifecycle Management

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Blob Storage Lifecycle Management with Cost Optimization".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (declarative JSON-based language)
- **Terraform**: Multi-cloud infrastructure as code using HashiCorp Configuration Language
- **Scripts**: Bash deployment and cleanup scripts for Azure CLI

## Prerequisites

- Azure CLI v2.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Resource group creation
  - Storage account management
  - Azure Monitor and Log Analytics workspace creation
  - Logic Apps deployment
  - Alert rule configuration
- Basic understanding of Azure Storage tiers and lifecycle management
- Estimated cost: $5-15 per month for storage, monitoring, and Logic Apps (depends on data volume)

## Quick Start

### Using Bicep

```bash
# Deploy the infrastructure using Bicep
az deployment group create \
    --resource-group rg-lifecycle-demo \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
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

## Architecture Overview

This infrastructure deploys:

- **Azure Storage Account** (General Purpose v2) with lifecycle management capabilities
- **Blob containers** for documents and logs with different retention policies
- **Lifecycle management policies** for automated tier transitions
- **Log Analytics workspace** for comprehensive monitoring
- **Diagnostic settings** for storage account monitoring
- **Azure Monitor alerts** for cost and capacity monitoring
- **Logic Apps** for automated alerting and workflow automation

## Deployment Details

### Resource Configuration

The deployment creates the following resources:

1. **Resource Group**: Container for all lifecycle management resources
2. **Storage Account**: GPv2 account with hot access tier and lifecycle management
3. **Blob Containers**: Separate containers for documents and logs
4. **Lifecycle Policy**: Automated rules for tier transitions and deletion
5. **Log Analytics Workspace**: Central monitoring and analytics platform
6. **Diagnostic Settings**: Storage account monitoring configuration
7. **Action Group**: Notification group for alerts
8. **Metric Alerts**: Capacity and transaction monitoring
9. **Logic App**: Automated workflow for advanced alerting

### Lifecycle Management Rules

The implementation includes two lifecycle policies:

**Document Lifecycle Policy**:
- Move to Cool tier after 30 days
- Move to Archive tier after 90 days
- Delete after 365 days

**Log Lifecycle Policy**:
- Move to Cool tier after 7 days
- Move to Archive tier after 30 days
- Delete after 180 days

### Monitoring and Alerting

The solution includes comprehensive monitoring:

- **Storage Capacity Alerts**: Triggered when storage exceeds 1GB
- **Transaction Alerts**: Triggered when transaction count is high
- **Diagnostic Logging**: Captures storage read/write operations
- **Metrics Collection**: Monitors capacity and transaction patterns

## Customization

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourceGroupName": {
      "value": "rg-lifecycle-demo"
    },
    "storageAccountName": {
      "value": "stlifecycledemo"
    },
    "location": {
      "value": "eastus"
    },
    "environment": {
      "value": "development"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
resource_group_name = "rg-lifecycle-demo"
location           = "eastus"
storage_account_name = "stlifecycledemo"
environment        = "development"
```

### Lifecycle Policy Customization

To modify lifecycle rules, update the policy configuration in your chosen IaC tool:

- **Cool tier transition**: Adjust `daysAfterModificationGreaterThan` values
- **Archive tier transition**: Modify archive transition timelines
- **Deletion policies**: Update retention periods
- **Container filters**: Add or modify `prefixMatch` patterns

## Validation

After deployment, validate the infrastructure:

```bash
# Check lifecycle management policy
az storage account management-policy show \
    --account-name <storage-account-name> \
    --resource-group <resource-group-name>

# Verify monitoring alerts
az monitor metrics alert list \
    --resource-group <resource-group-name>

# Check storage account diagnostics
az monitor diagnostic-settings list \
    --resource <storage-account-id>
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-lifecycle-demo \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Destroy the infrastructure
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

## Security Considerations

The infrastructure implements security best practices:

- **Storage Account**: Configured with secure defaults and access restrictions
- **Diagnostic Settings**: Secure log collection with retention policies
- **Monitoring**: Alerts configured to detect anomalous activity
- **Access Control**: Resources tagged for proper governance
- **Network Security**: Storage account configured with appropriate access controls

## Cost Optimization

This solution implements several cost optimization strategies:

- **Automated Tiering**: Reduces storage costs through lifecycle management
- **Retention Policies**: Prevents unnecessary data accumulation
- **Monitoring**: Provides visibility into storage costs and usage patterns
- **Alerting**: Enables proactive cost management
- **Right-sizing**: Uses appropriate storage tiers for different data types

## Monitoring and Observability

The solution provides comprehensive monitoring through:

- **Azure Monitor**: Real-time metrics and alerts
- **Log Analytics**: Centralized log collection and analysis
- **Storage Analytics**: Detailed storage operation insights
- **Cost Monitoring**: Tracks storage costs and tier distribution
- **Automated Alerting**: Proactive notification of issues

## Troubleshooting

Common issues and solutions:

1. **Storage Account Name Conflicts**: Ensure globally unique storage account names
2. **Permission Issues**: Verify appropriate Azure RBAC permissions
3. **Lifecycle Policy Errors**: Validate JSON syntax and rule configurations
4. **Monitoring Setup**: Ensure Log Analytics workspace is properly configured
5. **Alert Configuration**: Verify action groups and notification settings

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure documentation for latest service configurations
3. Validate resource configurations against Azure best practices
4. Ensure CLI tools are updated to latest versions

## Additional Resources

- [Azure Storage Lifecycle Management Documentation](https://docs.microsoft.com/en-us/azure/storage/blobs/lifecycle-management-overview)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)
- [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Azure Storage Access Tiers](https://docs.microsoft.com/en-us/azure/storage/blobs/access-tiers-overview)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)