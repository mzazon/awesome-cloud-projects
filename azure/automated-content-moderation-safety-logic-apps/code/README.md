# Infrastructure as Code for Automated Content Moderation with Content Safety and Logic Apps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Content Moderation with Content Safety and Logic Apps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az --version`)
- Azure subscription with appropriate permissions for:
  - Azure AI Services (Content Safety)
  - Logic Apps
  - Storage Accounts
  - Resource Groups
  - Event Grid (for blob storage events)
- Terraform installed (version 1.0+) if using Terraform implementation
- Bash shell environment
- `jq` command-line JSON processor (for scripts)
- Estimated cost: $15-25 for testing resources

> **Note**: Azure AI Content Safety has usage limits on the free tier. Review current pricing at [Azure AI Content Safety pricing](https://azure.microsoft.com/pricing/details/cognitive-services/content-safety/) before deployment.

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Create resource group
az group create \
    --name rg-content-moderation-demo \
    --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-content-moderation-demo \
    --template-file main.bicep \
    --parameters location=eastus

# Get deployment outputs
az deployment group show \
    --resource-group rg-content-moderation-demo \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View created resources
az resource list --resource-group rg-content-moderation-* --output table
```

## Architecture Overview

This implementation creates:

- **Azure AI Content Safety**: AI service for analyzing content across multiple harm categories
- **Storage Account**: Blob storage for content uploads with event grid integration
- **Logic App**: Workflow orchestration for automated content moderation
- **API Connections**: Managed connections between Logic Apps and Azure services
- **Event Grid**: Automatic triggering of workflows on blob creation/modification

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | No |
| `resourcePrefix` | Prefix for resource names | `contentmod` | No |
| `contentSafetyTier` | Content Safety pricing tier | `S0` | No |
| `storageAccountTier` | Storage account performance tier | `Standard_LRS` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for resources | `East US` | No |
| `resource_prefix` | Prefix for resource names | `contentmod` | No |
| `content_safety_sku` | Content Safety service SKU | `S0` | No |
| `storage_replication_type` | Storage replication type | `LRS` | No |
| `tags` | Resource tags | `{}` | No |

### Script Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AZURE_LOCATION` | Deployment region | `eastus` |
| `RESOURCE_PREFIX` | Resource name prefix | `contentmod` |
| `CONTENT_SAFETY_SKU` | Content Safety pricing tier | `S0` |

## Post-Deployment Configuration

After deploying the infrastructure, complete these steps:

1. **Test Content Safety API**:
   ```bash
   # Get endpoint and key from deployment outputs
   ENDPOINT=$(az cognitiveservices account show --name <content-safety-name> --resource-group <rg-name> --query properties.endpoint -o tsv)
   KEY=$(az cognitiveservices account keys list --name <content-safety-name> --resource-group <rg-name> --query key1 -o tsv)
   
   # Test API connectivity
   curl -X POST "${ENDPOINT}/contentsafety/text:analyze?api-version=2024-09-01" \
        -H "Ocp-Apim-Subscription-Key: ${KEY}" \
        -H "Content-Type: application/json" \
        -d '{"text": "Test content", "outputType": "FourSeverityLevels"}'
   ```

2. **Verify Logic App Workflow**:
   ```bash
   # Check Logic App status
   az logic workflow show \
       --resource-group <rg-name> \
       --name <logic-app-name> \
       --query "{state:state, location:location}"
   ```

3. **Test Content Upload**:
   ```bash
   # Upload test file to trigger workflow
   echo "Test content for moderation" > test-file.txt
   az storage blob upload \
       --file test-file.txt \
       --name test-upload.txt \
       --container-name content-uploads \
       --account-name <storage-account-name> \
       --auth-mode login
   ```

## Monitoring and Troubleshooting

### Check Logic App Runs

```bash
# View recent workflow executions
az logic workflow list-runs \
    --resource-group <rg-name> \
    --name <logic-app-name> \
    --top 10 \
    --query "value[].{status:status, startTime:startTime, endTime:endTime}" \
    --output table
```

### Monitor Content Safety Usage

```bash
# Check Content Safety metrics
az monitor metrics list \
    --resource <content-safety-resource-id> \
    --metric "TotalCalls" \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-12-31T23:59:59Z
```

### View Storage Account Activity

```bash
# List recent blob uploads
az storage blob list \
    --container-name content-uploads \
    --account-name <storage-account-name> \
    --auth-mode login \
    --query "[].{name:name, lastModified:properties.lastModified}" \
    --output table
```

## Security Considerations

- **Private Storage Access**: Blob containers are configured with private access
- **Managed Identity**: Logic Apps use managed identity where possible
- **API Key Security**: Content Safety keys are managed through Azure Key Vault integration
- **Network Security**: Consider implementing VNet integration for production deployments
- **Access Control**: Use Azure RBAC for fine-grained permission management

## Cost Optimization

- **Content Safety Tier**: Start with S0 tier and monitor usage patterns
- **Storage Access Tier**: Use Hot tier for active content processing
- **Logic App Consumption Plan**: Pay-per-execution model scales with usage
- **Resource Cleanup**: Implement retention policies for processed content

## Cleanup

### Using Bicep

```bash
# Delete resource group and all resources
az group delete \
    --name rg-content-moderation-demo \
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
```

### Manual Cleanup Verification

```bash
# Verify resource group deletion
az group exists --name rg-content-moderation-demo

# List any remaining resources
az resource list --query "[?contains(name, 'contentmod')]" --output table
```

## Customization

### Extending the Logic App Workflow

The Logic App workflow can be customized for additional scenarios:

1. **Add Email Notifications**: Integrate with Office 365 or SendGrid connectors
2. **Custom Approval Workflows**: Add human-in-the-loop approval processes
3. **Database Logging**: Store moderation results in Azure SQL or Cosmos DB
4. **Multi-Modal Content**: Extend to analyze images and videos
5. **Compliance Reporting**: Generate compliance reports for audit purposes

### Content Safety Configuration

Adjust content moderation sensitivity by modifying:

- **Severity Thresholds**: Change auto-approval/rejection levels
- **Category Filtering**: Focus on specific content categories
- **Custom Blocklists**: Implement organization-specific content rules
- **Language Support**: Configure multi-language content analysis

### Storage Account Optimization

Configure storage for specific use cases:

- **Lifecycle Policies**: Automatically tier or delete old content
- **Backup Strategies**: Implement geo-redundant storage for critical content
- **Access Patterns**: Optimize for read-heavy or write-heavy workloads
- **Performance Tiers**: Use Premium storage for high-throughput scenarios

## Troubleshooting

### Common Issues

1. **Logic App Not Triggering**:
   - Verify storage account event grid configuration
   - Check blob container permissions
   - Validate Logic App trigger configuration

2. **Content Safety API Errors**:
   - Verify API key and endpoint configuration
   - Check service quota limits
   - Validate request format and API version

3. **Storage Access Issues**:
   - Confirm authentication method (managed identity vs. connection string)
   - Verify container exists and has proper permissions
   - Check storage account firewall settings

4. **Deployment Failures**:
   - Validate Azure CLI authentication: `az account show`
   - Check resource naming conflicts
   - Verify subscription permissions and quotas

### Diagnostic Commands

```bash
# Check Azure CLI login status
az account show

# Validate resource group
az group show --name <rg-name>

# Test network connectivity to endpoints
curl -I https://cognitiveservices.azure.com

# Check Azure service health
az rest --method get --url "https://management.azure.com/subscriptions/{subscription-id}/providers/Microsoft.ResourceHealth/availabilityStatuses?api-version=2020-05-01"
```

## Support and Documentation

- [Azure AI Content Safety Documentation](https://docs.microsoft.com/en-us/azure/ai-services/content-safety/)
- [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Azure Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.

## Contributing

To improve this IaC implementation:

1. Test deployments in different Azure regions
2. Validate with different subscription types
3. Enhance error handling in scripts
4. Add support for additional Azure services
5. Implement infrastructure testing with tools like Terratest or Pester

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Refer to your organization's policies for production usage guidelines.