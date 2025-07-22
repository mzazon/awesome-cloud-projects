# Infrastructure as Code for Intelligent Invoice Processing Workflows with Azure Logic Apps and AI Document Intelligence

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Invoice Processing Workflows with Azure Logic Apps and AI Document Intelligence".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Logic Apps
  - AI Document Intelligence (Cognitive Services)
  - Service Bus
  - Blob Storage
  - Resource Groups
- For Terraform: Terraform v1.0+ installed
- For Bicep: Bicep CLI installed (included with Azure CLI v2.20.0+)
- Bash shell environment (Linux, macOS, or WSL on Windows)

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
cd bicep/

# Login to Azure
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-invoice-processing" \
    --template-file main.bicep \
    --parameters parameters.json
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Login to Azure
az login

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
```

## Architecture Overview

This infrastructure deploys:

- **Azure Blob Storage**: Document storage and event triggers
- **Azure AI Document Intelligence**: AI-powered invoice data extraction
- **Azure Logic Apps**: Workflow orchestration and business process automation
- **Azure Service Bus**: Enterprise messaging and system integration
- **Azure Function App**: Additional processing capabilities
- **Event Grid**: Event-driven automation triggers

## Configuration Parameters

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `resourceGroupName` | Name of the resource group | `rg-invoice-processing` | Yes |
| `location` | Azure region for deployment | `East US` | Yes |
| `storageAccountName` | Storage account name (must be globally unique) | Auto-generated | No |
| `documentIntelligenceName` | AI Document Intelligence service name | Auto-generated | No |
| `logicAppName` | Logic App name | Auto-generated | No |
| `serviceBusNamespace` | Service Bus namespace name | Auto-generated | No |
| `functionAppName` | Function App name | Auto-generated | No |

### Bicep-Specific Parameters

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
      "value": "dev"
    }
  }
}
```

### Terraform-Specific Variables

Edit `terraform/terraform.tfvars` to customize your deployment:

```hcl
location            = "East US"
environment         = "dev"
invoice_volume     = "standard"
approval_threshold = 1000
```

## Deployment Process

### Pre-Deployment

1. **Resource Group**: Create or use existing resource group
2. **Permissions**: Ensure adequate permissions for all services
3. **Naming**: Verify globally unique names for storage and other services
4. **Quotas**: Check service quotas in target region

### Post-Deployment Configuration

After infrastructure deployment, additional configuration is required:

1. **Logic App Connections**: Configure API connections in Azure portal
2. **Event Grid Subscriptions**: Set up blob storage event triggers
3. **Service Bus Policies**: Configure access policies for applications
4. **Document Intelligence Models**: Train custom models if needed

### Integration Points

The deployed infrastructure includes these integration capabilities:

- **Email Integration**: Office 365 connector for approval workflows
- **ERP Integration**: Service Bus queues for system connectivity
- **Monitoring Integration**: Application Insights for observability
- **Security Integration**: Key Vault for secret management

## Testing the Deployment

### Validation Steps

1. **Storage Account**: Verify blob container creation and access
   ```bash
   az storage container list --account-name <storage-account-name>
   ```

2. **AI Document Intelligence**: Test API endpoint
   ```bash
   curl -X GET \
       -H "Ocp-Apim-Subscription-Key: <key>" \
       "<endpoint>/formrecognizer/info"
   ```

3. **Logic App**: Check workflow definition and status
   ```bash
   az logic workflow show --name <logic-app-name> --resource-group <rg-name>
   ```

4. **Service Bus**: Verify namespace and queue creation
   ```bash
   az servicebus namespace show --name <namespace> --resource-group <rg-name>
   ```

### Sample Invoice Upload

```bash
# Upload a test invoice to trigger the workflow
az storage blob upload \
    --account-name <storage-account-name> \
    --container-name invoices \
    --name test-invoice.pdf \
    --file sample-invoice.pdf
```

## Monitoring and Troubleshooting

### Application Insights

Monitor workflow execution and performance:
- Logic App run history and metrics
- Function App execution logs
- AI Document Intelligence API usage
- Service Bus message processing

### Common Issues

1. **Authentication Failures**: Verify managed identity assignments
2. **Timeout Issues**: Adjust Logic App timeout settings
3. **Throughput Limits**: Monitor AI Document Intelligence quotas
4. **Message Processing**: Check Service Bus dead letter queues

### Logging

Enable diagnostic settings for comprehensive logging:
- Logic Apps execution history
- Storage account access logs
- Service Bus operational logs
- Function App application logs

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name "rg-invoice-processing" --yes --no-wait
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
```

### Manual Cleanup Verification

After automated cleanup, verify removal of:
- Resource group and all contained resources
- Any custom domain configurations
- Service principal assignments (if created)
- Key Vault access policies (if configured)

## Cost Optimization

### Pricing Considerations

- **Logic Apps**: Consumption plan charges per action execution
- **AI Document Intelligence**: Pay-per-transaction pricing
- **Service Bus**: Standard tier supports auto-scaling
- **Storage**: Use appropriate access tiers (Hot/Cool/Archive)
- **Function Apps**: Consumption plan for variable workloads

### Cost Monitoring

Set up cost alerts and budgets:
```bash
az consumption budget create \
    --resource-group "rg-invoice-processing" \
    --budget-name "invoice-processing-budget" \
    --amount 100 \
    --time-grain Monthly
```

## Security Considerations

### Best Practices Implemented

- **Managed Identity**: Passwordless authentication between services
- **Network Security**: Virtual network integration where applicable
- **Data Encryption**: Encryption at rest and in transit
- **Access Control**: Role-based access control (RBAC)
- **Key Management**: Azure Key Vault for secrets

### Security Validation

1. **Network Access**: Verify firewall rules and access restrictions
2. **Authentication**: Test managed identity assignments
3. **Encryption**: Confirm encryption settings for storage and messaging
4. **Monitoring**: Enable security monitoring and alerts

## Customization

### Business Logic Customization

Modify workflow behavior by:
1. **Approval Thresholds**: Adjust amount-based routing logic
2. **Document Types**: Add support for additional document formats
3. **Integration Endpoints**: Configure connections to specific ERP systems
4. **Notification Templates**: Customize email and alert templates

### Scaling Configuration

Adjust for different processing volumes:
- **Logic Apps**: Configure concurrency and retry policies
- **Service Bus**: Scale messaging tier based on throughput needs
- **Storage**: Implement lifecycle management policies
- **AI Services**: Consider dedicated capacity for high volumes

## Advanced Features

### Multi-Environment Support

Deploy across multiple environments:
```bash
# Development environment
./scripts/deploy.sh --environment dev

# Production environment
./scripts/deploy.sh --environment prod
```

### Custom Document Models

Train specialized models for industry-specific invoices:
1. Collect sample documents (minimum 5 per document type)
2. Use Document Intelligence Studio for model training
3. Update Logic App to reference custom model IDs

### Disaster Recovery

Implement backup and recovery procedures:
- Enable geo-redundant storage for critical documents
- Configure Service Bus geo-disaster recovery
- Document restoration procedures and RTO/RPO targets

## Support

### Documentation Resources

- [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Azure AI Document Intelligence Documentation](https://docs.microsoft.com/en-us/azure/ai-services/document-intelligence/)
- [Azure Service Bus Documentation](https://docs.microsoft.com/en-us/azure/service-bus-messaging/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

### Getting Help

For issues with this infrastructure code:
1. Check the original recipe documentation for business logic guidance
2. Review Azure service-specific documentation for configuration details
3. Use Azure support channels for service-related issues
4. Consult community forums for implementation patterns

### Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Validate against recipe requirements
3. Update documentation accordingly
4. Follow Azure naming conventions and best practices