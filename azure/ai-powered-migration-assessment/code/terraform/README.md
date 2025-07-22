# Terraform Infrastructure for AI-Powered Migration Assessment

This Terraform configuration deploys a complete AI-powered migration assessment solution on Microsoft Azure. The infrastructure combines Azure Migrate's discovery capabilities with Azure OpenAI Service to provide intelligent workload modernization recommendations.

## Architecture Overview

The solution deploys the following Azure resources:

- **Azure Migrate Project**: Centralized hub for workload discovery and assessment
- **Azure OpenAI Service**: AI-powered analysis and recommendation engine
- **Azure Functions**: Serverless processing for assessment data
- **Azure Storage Account**: Secure storage for assessment data and AI insights
- **Application Insights**: Monitoring and diagnostics
- **Log Analytics Workspace**: Centralized logging and monitoring

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Azure CLI** installed and configured
   ```bash
   az --version
   az account show
   ```

2. **Terraform** installed (version >= 1.0)
   ```bash
   terraform --version
   ```

3. **Azure Subscription** with appropriate permissions:
   - Contributor role on the subscription or resource group
   - User Access Administrator role for RBAC assignments
   - Azure OpenAI Service access (requires approval)

4. **Azure OpenAI Service Access**: 
   - Apply for access at [Azure OpenAI Service](https://azure.microsoft.com/products/ai-services/openai-service/)
   - Ensure your subscription is approved for OpenAI services

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd azure/ai-powered-migration-assessment/code/terraform
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review and Customize Variables

Create a `terraform.tfvars` file to customize the deployment:

```hcl
# terraform.tfvars
resource_group_name = "rg-my-migration-assessment"
location = "East US"
environment = "dev"

# OpenAI configuration
openai_location = "East US"
gpt_model_name = "gpt-4"
gpt_deployment_capacity = 20

# Storage configuration
storage_account_prefix = "stamyassess"

# Function App configuration
function_app_name = "func-my-assessment"

# Tags
tags = {
  "Project" = "My Migration Assessment"
  "Environment" = "Development"
  "Owner" = "Migration Team"
  "CostCenter" = "IT"
}
```

### 4. Plan and Apply

```bash
# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### 5. Verify Deployment

```bash
# Check resource group
az group show --name rg-my-migration-assessment

# Check OpenAI service
az cognitiveservices account show --name <openai-service-name> --resource-group rg-my-migration-assessment

# Check Function App
az functionapp show --name <function-app-name> --resource-group rg-my-migration-assessment
```

## Configuration Options

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `resource_group_name` | Name of the resource group | `"rg-migrate-assessment"` |
| `location` | Azure region | `"East US"` |

### Optional Variables

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `environment` | Environment name | `"dev"` | `dev`, `staging`, `prod` |
| `openai_location` | OpenAI service region | `"East US"` | [Available regions](https://learn.microsoft.com/azure/ai-services/openai/concepts/models#model-summary-table-and-region-availability) |
| `gpt_model_name` | GPT model to deploy | `"gpt-4"` | `gpt-4`, `gpt-35-turbo` |
| `gpt_deployment_capacity` | Model capacity (TPM) | `20` | `1-120` |
| `storage_account_prefix` | Storage account name prefix | `"stamigrate"` | 3-11 lowercase chars |
| `function_app_name` | Function app name prefix | `"func-migrate-ai"` | 2-50 chars |

### Advanced Configuration

```hcl
# Security settings
min_tls_version = "TLS1_2"
enable_https_only = true
enable_soft_delete = true
soft_delete_retention_days = 30

# Monitoring settings
log_retention_days = 30
application_insights_sampling_percentage = 100
enable_debug_logging = false

# Cost management
monthly_budget_amount = 1000
enable_cost_anomaly_detection = true
```

## Post-Deployment Configuration

### 1. Deploy Function Code

After the infrastructure is deployed, deploy the function code:

```bash
# Get function app name from Terraform output
FUNCTION_APP_NAME=$(terraform output -raw function_app_name)
RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)

# Deploy function code
az functionapp deployment source config-zip \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --name ${FUNCTION_APP_NAME} \
    --src function-app.zip
```

### 2. Test the Deployment

```bash
# Get function URL
FUNCTION_URL=$(terraform output -raw ai_assessment_function_url)

# Get function key
FUNCTION_KEY=$(az functionapp keys list \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --name ${FUNCTION_APP_NAME} \
    --query functionKeys.default \
    --output tsv)

# Test the function
curl -X POST "${FUNCTION_URL}?code=${FUNCTION_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
        "timestamp": "2025-01-20T10:00:00Z",
        "project": "test-migration",
        "servers": [{
            "name": "web-server-01",
            "os": "Windows Server 2019",
            "cpu_cores": 4,
            "memory_gb": 16,
            "storage_gb": 500
        }]
    }'
```

### 3. Set Up Azure Migrate Appliance

1. **Download Azure Migrate Appliance**:
   ```bash
   # Get migrate project name
   MIGRATE_PROJECT=$(terraform output -raw migrate_project_name)
   
   # Get project details
   az migrate project show \
       --name ${MIGRATE_PROJECT} \
       --resource-group ${RESOURCE_GROUP_NAME}
   ```

2. **Deploy Appliance** following the [Azure Migrate appliance setup guide](https://learn.microsoft.com/azure/migrate/migrate-appliance)

## Usage

### 1. Discover Workloads

Use the Azure Migrate appliance to discover on-premises workloads:

1. Configure the appliance with your Azure Migrate project details
2. Start discovery of servers, applications, and dependencies
3. Wait for assessment data to be collected

### 2. Generate AI Insights

Send assessment data to the Function App for AI analysis:

```bash
# Example assessment data
curl -X POST "${FUNCTION_URL}?code=${FUNCTION_KEY}" \
    -H "Content-Type: application/json" \
    -d @assessment-data.json
```

### 3. Review Insights

Access AI-generated insights:

```bash
# List insights in storage
az storage blob list \
    --account-name $(terraform output -raw storage_account_name) \
    --container-name ai-insights \
    --output table

# Download specific insight
az storage blob download \
    --account-name $(terraform output -raw storage_account_name) \
    --container-name ai-insights \
    --name assessment_project_20250120.json \
    --file insights.json
```

## Monitoring and Maintenance

### Application Insights

Monitor Function App performance:

```bash
# Get Application Insights details
az monitor app-insights component show \
    --app $(terraform output -raw application_insights_name) \
    --resource-group ${RESOURCE_GROUP_NAME}
```

### Log Analytics

Query logs for troubleshooting:

```bash
# Get Log Analytics workspace details
az monitor log-analytics workspace show \
    --workspace-name $(terraform output -raw log_analytics_workspace_name) \
    --resource-group ${RESOURCE_GROUP_NAME}
```

### Cost Management

Monitor costs:

```bash
# Check current costs
az consumption usage list \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --start-date $(date -d "1 month ago" +%Y-%m-%d) \
    --end-date $(date +%Y-%m-%d)
```

## Security Considerations

### Network Security

- Storage accounts are configured with secure transfer required
- Function Apps use system-assigned managed identities
- RBAC assignments follow principle of least privilege

### Data Protection

- Blob soft delete is enabled with 30-day retention
- Blob versioning is enabled for data protection
- All data is encrypted at rest and in transit

### Access Control

- OpenAI service uses API keys (consider Azure AD authentication for production)
- Function Apps use function-level authorization
- Storage containers use private access

## Troubleshooting

### Common Issues

1. **OpenAI Service Not Available**:
   - Ensure your subscription has OpenAI service access
   - Check region availability
   - Verify quota limits

2. **Function App Deployment Issues**:
   - Check function app logs in Application Insights
   - Verify environment variables are set correctly
   - Ensure storage account connectivity

3. **Storage Access Issues**:
   - Verify RBAC assignments
   - Check storage account network rules
   - Ensure container permissions

### Debugging

Enable debug logging:

```bash
# Enable debug logging in Function App
az functionapp config appsettings set \
    --name ${FUNCTION_APP_NAME} \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --settings "FUNCTIONS_WORKER_RUNTIME_VERSION=~4" \
                "LOGGING__LOGLEVEL__DEFAULT=Debug"
```

## Cleanup

To remove all resources:

```bash
# Destroy infrastructure
terraform destroy

# Verify resource group is empty
az group show --name ${RESOURCE_GROUP_NAME} --query "properties.provisioningState"
```

## Cost Optimization

### Estimated Monthly Costs

| Resource | Estimated Cost (USD) |
|----------|---------------------|
| Azure OpenAI Service | $50-200 (usage-based) |
| Azure Functions | $0-50 (consumption plan) |
| Storage Account | $10-30 |
| Application Insights | $5-20 |
| Log Analytics | $10-30 |
| **Total** | **$75-330** |

### Cost-Saving Tips

1. **Use consumption plan** for Function Apps
2. **Set spending limits** on OpenAI service
3. **Configure lifecycle policies** for storage
4. **Monitor usage** with Azure Cost Management

## Support and Documentation

- [Azure Migrate Documentation](https://learn.microsoft.com/azure/migrate/)
- [Azure OpenAI Service Documentation](https://learn.microsoft.com/azure/ai-services/openai/)
- [Azure Functions Documentation](https://learn.microsoft.com/azure/azure-functions/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest)

## Contributing

When contributing to this Terraform configuration:

1. Follow [Terraform best practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/)
2. Update documentation for any variable changes
3. Test changes in a development environment
4. Use semantic versioning for releases

## License

This infrastructure code is provided under the same license as the parent repository.