# Infrastructure as Code for Automated Content Safety Moderation with Logic Apps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Content Safety Moderation with Logic Apps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions to create resources
- For Terraform: Terraform v1.0 or later installed
- For Bicep: Azure CLI with Bicep extension installed
- Appropriate Azure permissions for:
  - Creating resource groups
  - Deploying Azure AI Services (Content Safety)
  - Creating Logic Apps and Event Grid topics
  - Managing Azure Storage accounts
  - Configuring monitoring and logging

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-content-moderation \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters environmentName=demo

# Monitor deployment status
az deployment group show \
    --resource-group rg-content-moderation \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan -var="location=eastus" -var="environment=demo"

# Apply the configuration
terraform apply -var="location=eastus" -var="environment=demo"

# Show outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts to configure environment variables
# Script will create all required resources automatically
```

## Architecture Overview

This infrastructure deploys:

- **Azure AI Content Safety**: Multi-modal content analysis service
- **Azure Logic Apps**: Workflow orchestration for content moderation
- **Azure Storage Account**: Content storage with organized containers
- **Azure Event Grid**: Event-driven content processing triggers
- **Azure Functions**: Custom processing logic (optional)
- **Log Analytics Workspace**: Monitoring and audit logging

## Configuration Parameters

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| location | string | eastus | Azure region for deployment |
| environmentName | string | demo | Environment identifier |
| storageAccountSku | string | Standard_LRS | Storage account SKU |
| contentSafetyTier | string | S0 | AI Content Safety pricing tier |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| location | string | eastus | Azure region for deployment |
| environment | string | demo | Environment identifier |
| resource_group_name | string | rg-content-moderation | Resource group name |
| storage_sku | string | Standard_LRS | Storage account SKU |

### Bash Script Environment Variables

The deployment script will prompt for or generate:

- `RESOURCE_GROUP`: Resource group name
- `LOCATION`: Azure region
- `RANDOM_SUFFIX`: Unique identifier for resources
- `STORAGE_ACCOUNT`: Storage account name
- `AI_SERVICES_NAME`: Content Safety service name

## Post-Deployment Configuration

### 1. Configure Logic App Workflow

After deployment, configure the Logic App with content moderation logic:

```bash
# Get Logic App information
az logic workflow show \
    --name logic-content-mod-${RANDOM_SUFFIX} \
    --resource-group rg-content-moderation

# Update workflow definition with content analysis logic
# (See recipe steps for detailed workflow configuration)
```

### 2. Set Up Event Grid Subscription

```bash
# Create event subscription for blob storage events
az eventgrid event-subscription create \
    --name content-upload-subscription \
    --source-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-content-moderation/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
    --endpoint-type webhook \
    --endpoint "${EVENT_GRID_ENDPOINT}" \
    --included-event-types Microsoft.Storage.BlobCreated
```

### 3. Configure Content Safety Policies

```bash
# Test Content Safety service
curl -X POST "${AI_ENDPOINT}contentsafety/text:analyze?api-version=2023-10-01" \
    -H "Ocp-Apim-Subscription-Key: ${AI_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
        "text": "Test content for moderation",
        "categories": ["Hate", "Violence", "Sexual", "SelfHarm"],
        "outputType": "FourSeverityLevels"
    }'
```

## Validation & Testing

### 1. Verify Resource Deployment

```bash
# Check all resources in resource group
az resource list \
    --resource-group rg-content-moderation \
    --output table

# Verify AI Content Safety service
az cognitiveservices account show \
    --name ai-content-safety-${RANDOM_SUFFIX} \
    --resource-group rg-content-moderation
```

### 2. Test Content Upload

```bash
# Create test content
echo "This is test content for moderation" > test-content.txt

# Upload to storage
az storage blob upload \
    --container-name uploads \
    --file test-content.txt \
    --name test-content.txt \
    --connection-string "${STORAGE_CONNECTION}"

# Verify Logic App execution
az logic workflow run list \
    --name logic-content-mod-${RANDOM_SUFFIX} \
    --resource-group rg-content-moderation
```

### 3. Monitor System Health

```bash
# Check Log Analytics workspace
az monitor log-analytics workspace show \
    --name law-content-${RANDOM_SUFFIX} \
    --resource-group rg-content-moderation

# Query workflow execution logs
az monitor log-analytics query \
    --workspace law-content-${RANDOM_SUFFIX} \
    --analytics-query "AzureDiagnostics | where ResourceType == 'WORKFLOWS' | take 10"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-content-moderation \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="location=eastus" -var="environment=demo"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Customization

### Storage Configuration

Modify storage containers and access policies:

```bash
# Create additional containers
az storage container create \
    --name custom-content \
    --connection-string "${STORAGE_CONNECTION}" \
    --public-access off
```

### Content Safety Thresholds

Adjust content analysis sensitivity in Logic App workflow:

```json
{
    "categories": ["Hate", "Violence", "Sexual", "SelfHarm"],
    "outputType": "FourSeverityLevels",
    "thresholdLevel": "Medium"
}
```

### Monitoring Alerts

Configure alerts for content moderation events:

```bash
# Create alert rule for high-severity content
az monitor metrics alert create \
    --name high-severity-content-alert \
    --resource-group rg-content-moderation \
    --scopes /subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-content-moderation/providers/Microsoft.Logic/workflows/logic-content-mod-${RANDOM_SUFFIX} \
    --condition "count Microsoft.Logic/workflows WorkflowRunsCompleted > 10" \
    --description "Alert when content moderation workflow runs exceed threshold"
```

## Security Considerations

### Access Control

- Logic Apps use managed identity for secure service communication
- Storage accounts implement private endpoints where possible
- AI Content Safety keys are stored securely in Key Vault integration
- Event Grid topics use access keys with proper rotation policies

### Data Protection

- All data at rest is encrypted using Azure Storage encryption
- Content in quarantine containers has restricted access
- Audit logs are retained according to compliance requirements
- Personally identifiable information is handled per privacy regulations

### Network Security

- Consider implementing private endpoints for production deployments
- Use Azure Private Link for secure service communication
- Implement network security groups for additional access control
- Consider VNet integration for Logic Apps in sensitive environments

## Troubleshooting

### Common Issues

1. **Content Safety API Access Denied**
   - Verify service is approved for your subscription
   - Check API key configuration
   - Ensure proper service tier is selected

2. **Logic App Workflow Failures**
   - Check workflow run history in Azure portal
   - Verify Event Grid subscription configuration
   - Validate storage account permissions

3. **Event Grid Delivery Issues**
   - Verify endpoint configuration
   - Check event subscription filters
   - Review delivery attempt logs

### Debugging Commands

```bash
# Check Logic App run history
az logic workflow run list \
    --name logic-content-mod-${RANDOM_SUFFIX} \
    --resource-group rg-content-moderation \
    --query "[0].{status:status, startTime:startTime, error:error}"

# View Event Grid topic metrics
az monitor metrics list \
    --resource /subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-content-moderation/providers/Microsoft.EventGrid/topics/eg-content-${RANDOM_SUFFIX} \
    --metric "PublishSuccessCount,PublishFailCount"
```

## Cost Optimization

### Monitoring Costs

- Use Azure Cost Management to track resource spending
- Set up budget alerts for unexpected cost increases
- Monitor AI Content Safety usage and tier appropriately
- Review storage costs and implement lifecycle policies

### Optimization Tips

- Use consumption-based pricing for Logic Apps
- Implement storage lifecycle management for old content
- Consider reserved instances for predictable workloads
- Optimize Event Grid subscription filters to reduce unnecessary events

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service status and known issues
3. Consult Azure documentation for specific services
4. Use Azure Support for service-specific problems

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Ensure compatibility with all deployment methods
3. Update documentation for any parameter changes
4. Validate security and compliance requirements