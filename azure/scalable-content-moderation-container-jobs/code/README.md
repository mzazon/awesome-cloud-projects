# Infrastructure as Code for Scalable Content Moderation with Container Apps Jobs

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scalable Content Moderation with Container Apps Jobs".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with Owner or Contributor permissions
- Docker knowledge for containerized job creation
- Understanding of event-driven architectures and message queuing concepts
- Basic knowledge of REST APIs and content moderation principles

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension installed
- PowerShell 7.0+ (if using PowerShell deployment scripts)

#### For Terraform
- Terraform v1.5.0 or later installed
- Azure Provider for Terraform
- Service Principal with appropriate permissions (optional but recommended)

#### For Bash Scripts
- jq for JSON parsing
- openssl for generating random suffixes
- curl for API testing

## Quick Start

### Using Bicep
```bash
# Navigate to bicep directory
cd bicep/

# Review and customize parameters
cp parameters.json.template parameters.json
# Edit parameters.json with your specific values

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform
```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts for configuration
```

## Architecture Overview

This infrastructure deploys a complete content moderation solution including:

- **Azure AI Content Safety**: Intelligent content analysis for text and images
- **Azure Container Apps Jobs**: Serverless batch processing with event-driven scaling
- **Azure Service Bus**: Reliable message queuing for content processing workflows
- **Azure Storage Account**: Persistent storage for moderation results and audit trails
- **Azure Monitor**: Comprehensive logging and alerting for system observability

## Configuration Options

### Key Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `resourceGroupName` | Resource group name | `rg-content-moderation` | Yes |
| `contentSafetyName` | Content Safety service name | Generated | No |
| `containerEnvironmentName` | Container Apps environment name | Generated | No |
| `serviceBusNamespace` | Service Bus namespace | Generated | No |
| `storageAccountName` | Storage account name | Generated | No |
| `enableMonitoring` | Enable Azure Monitor integration | `true` | No |

### Environment Variables

The following environment variables are used across all implementations:

```bash
# Core Azure settings
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_RESOURCE_GROUP="rg-content-moderation"
export AZURE_LOCATION="eastus"

# Service-specific settings
export CONTENT_SAFETY_TIER="S0"
export SERVICE_BUS_SKU="Standard"
export STORAGE_ACCOUNT_TYPE="Standard_LRS"
export CONTAINER_APPS_ENVIRONMENT_TYPE="Consumption"
```

## Deployment Details

### Bicep Deployment

The Bicep template creates all required resources with Azure best practices:

```bash
# Deploy with custom parameters
az deployment group create \
    --resource-group myResourceGroup \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters contentSafetyName=myContentSafety \
    --parameters enableMonitoring=true
```

### Terraform Deployment

The Terraform configuration supports multiple deployment scenarios:

```bash
# Deploy with variables file
terraform apply -var-file="production.tfvars"

# Deploy with inline variables
terraform apply \
    -var="location=eastus" \
    -var="resource_group_name=rg-content-moderation" \
    -var="enable_monitoring=true"
```

### Script Deployment

The bash scripts provide interactive deployment with validation:

```bash
# Deploy with prompts
./scripts/deploy.sh

# Deploy with environment variables
AZURE_LOCATION=eastus \
ENABLE_MONITORING=true \
./scripts/deploy.sh
```

## Validation & Testing

After deployment, validate the infrastructure:

### 1. Verify Content Safety API
```bash
# Test Content Safety endpoint
curl -X POST \
    "https://<content-safety-name>.cognitiveservices.azure.com/contentsafety/text:analyze?api-version=2023-10-01" \
    -H "Ocp-Apim-Subscription-Key: <your-key>" \
    -H "Content-Type: application/json" \
    -d '{"text": "Test content", "categories": ["Hate", "Violence"]}'
```

### 2. Test Service Bus Queue
```bash
# Send test message
az servicebus queue send \
    --namespace-name <service-bus-namespace> \
    --queue-name content-queue \
    --body '{"contentId": "test-001", "text": "Test message"}'
```

### 3. Verify Container Apps Job
```bash
# Check job status
az containerapp job execution list \
    --name <job-name> \
    --resource-group <resource-group> \
    --output table
```

### 4. Validate Storage Account
```bash
# List containers
az storage container list \
    --account-name <storage-account> \
    --output table
```

## Monitoring & Observability

The infrastructure includes comprehensive monitoring:

### Azure Monitor Integration
- Log Analytics workspace for centralized logging
- Application Insights for application performance monitoring
- Metric alerts for queue depth and processing failures
- Action groups for notification routing

### Key Metrics to Monitor
- Content Safety API request volume and latency
- Service Bus queue depth and processing time
- Container Apps Job execution success rate
- Storage account access patterns and costs

### Sample Kusto Queries
```kusto
// Monitor Content Safety API usage
requests
| where url contains "contentsafety"
| summarize RequestCount = count() by bin(timestamp, 1h)
| render timechart

// Track Container Apps Job executions
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "job-content-processor"
| where Log_s contains "Content processed"
| summarize ProcessedCount = count() by bin(TimeGenerated, 1h)
```

## Security Considerations

### Identity and Access Management
- Managed Identity enabled for Container Apps Jobs
- Role-based access control (RBAC) for Service Bus and Storage
- Key Vault integration for sensitive configuration (optional)

### Network Security
- Private endpoints for Storage Account (optional)
- Service Bus access policies with least privilege
- Container Apps environment network isolation

### Data Protection
- Encryption at rest for Storage Account
- Encryption in transit for all API communications
- Content Safety API data residency compliance

## Cost Optimization

### Resource Pricing
- **Content Safety**: Pay-per-transaction model (~$1 per 1000 text transactions)
- **Container Apps Jobs**: Consumption-based pricing for execution time
- **Service Bus**: Standard tier with message-based pricing
- **Storage**: Standard LRS with access tier optimization

### Cost Management Tips
1. Use Azure Cost Management to track spending
2. Set up budget alerts for cost thresholds
3. Configure Container Apps Job scaling to minimize idle time
4. Implement storage lifecycle policies for audit logs
5. Monitor Content Safety API usage patterns

## Troubleshooting

### Common Issues

#### Container Apps Job Not Triggering
```bash
# Check Service Bus connection
az servicebus queue show \
    --namespace-name <namespace> \
    --name content-queue \
    --query "messageCount"

# Verify job scaling rules
az containerapp job show \
    --name <job-name> \
    --resource-group <resource-group> \
    --query "properties.configuration.eventTriggerConfig"
```

#### Content Safety API Errors
```bash
# Check API key and endpoint
az cognitiveservices account show \
    --name <content-safety-name> \
    --resource-group <resource-group> \
    --query "properties.endpoint"

# Verify API quota
az cognitiveservices account usage list \
    --name <content-safety-name> \
    --resource-group <resource-group>
```

#### Storage Access Issues
```bash
# Check storage account permissions
az storage account show \
    --name <storage-account> \
    --resource-group <resource-group> \
    --query "primaryEndpoints"

# Verify container permissions
az storage container show-permission \
    --name moderation-results \
    --account-name <storage-account>
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <resource-group-name> \
    --yes \
    --no-wait
```

### Using Terraform
```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

### Manual Cleanup Verification
```bash
# Verify all resources are deleted
az resource list \
    --resource-group <resource-group-name> \
    --output table

# Check for any remaining billable resources
az consumption usage list \
    --start-date $(date -d "1 day ago" +%Y-%m-%d) \
    --end-date $(date +%Y-%m-%d) \
    --query "[?contains(instanceName, 'content-moderation')]"
```

## Customization

### Adding Custom Content Categories
Modify the Container Apps Job configuration to include custom categories:

```json
{
    "categories": ["Hate", "SelfHarm", "Sexual", "Violence", "Custom1", "Custom2"]
}
```

### Implementing Human Review Workflow
Extend the solution with Azure Logic Apps for human review escalation:

1. Add Logic Apps resources to IaC templates
2. Configure approval workflows for high-confidence harmful content
3. Integrate with notification systems (Teams, email, etc.)

### Multi-Region Deployment
For global deployments, consider:

1. Deploy to multiple Azure regions
2. Use Azure Traffic Manager for request routing
3. Implement cross-region replication for audit data
4. Configure region-specific content policies

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation:
   - [Azure AI Content Safety](https://learn.microsoft.com/en-us/azure/ai-services/content-safety/)
   - [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/)
   - [Azure Service Bus](https://learn.microsoft.com/en-us/azure/service-bus-messaging/)
3. Consult provider-specific troubleshooting guides
4. Use Azure support channels for service-specific issues

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate against Azure best practices
3. Update documentation for any new features
4. Consider backward compatibility for existing deployments

---

*This infrastructure code is generated based on the recipe "Scalable Content Moderation with Container Apps Jobs" and follows Azure best practices for production deployments.*