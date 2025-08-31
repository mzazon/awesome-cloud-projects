# Infrastructure as Code for AI Cost Monitoring with Foundry and Application Insights

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI Cost Monitoring with Foundry and Application Insights".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.60.0 or later)
- Azure subscription with Owner or Contributor permissions
- Basic understanding of Azure AI services and cost management concepts
- Familiarity with KQL (Kusto Query Language) for custom queries
- Estimated cost: $50-100 for testing depending on model usage and retention settings

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension (automatically included in recent versions)
- PowerShell or Bash terminal

#### For Terraform
- Terraform installed (version 1.0 or later)
- Azure CLI authentication configured

## Quick Start

### Using Bicep (Recommended for Azure)

Deploy the complete AI cost monitoring infrastructure:

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Set deployment parameters
export LOCATION="eastus"
export RANDOM_SUFFIX=$(openssl rand -hex 3)

# Deploy using Azure CLI
az deployment group create \
    --resource-group "rg-ai-monitoring-${RANDOM_SUFFIX}" \
    --template-file main.bicep \
    --parameters location=${LOCATION} \
    --parameters randomSuffix=${RANDOM_SUFFIX} \
    --parameters adminEmail="admin@company.com"
```

### Using Terraform

Initialize and deploy the infrastructure:

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply

# When prompted, enter 'yes' to confirm deployment
```

### Using Bash Scripts

Automated deployment with error handling:

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# Follow the prompts for configuration
```

## Configuration Options

### Bicep Parameters

The Bicep template supports the following parameters:

- `location`: Azure region for resource deployment (default: eastus)
- `randomSuffix`: Unique suffix for resource names (auto-generated if not provided)
- `adminEmail`: Email address for cost alerts and notifications
- `budgetAmount`: Monthly budget limit in USD (default: 100)
- `alertThresholds`: Array of budget alert thresholds (default: [80, 100])

### Terraform Variables

Customize the deployment by setting these variables in `terraform.tfvars`:

```hcl
# terraform.tfvars example
location = "eastus"
admin_email = "admin@company.com"
budget_amount = 100
alert_thresholds = [80, 100]
environment = "demo"
```

### Environment Variables for Scripts

The bash scripts use these environment variables:

```bash
export LOCATION="eastus"                    # Azure region
export ADMIN_EMAIL="admin@company.com"     # Alert recipient
export BUDGET_AMOUNT="100"                 # Monthly budget in USD
export ENVIRONMENT="demo"                  # Environment tag
```

## Post-Deployment Configuration

After successful deployment, complete these additional steps:

### 1. Configure AI Model Deployment

```bash
# Set environment variables from deployment outputs
export AI_HUB_NAME="<hub-name-from-output>"
export AI_PROJECT_NAME="<project-name-from-output>"
export RESOURCE_GROUP="<resource-group-name>"

# Deploy a sample GPT model (optional)
az ml model create \
    --resource-group ${RESOURCE_GROUP} \
    --workspace-name ${AI_PROJECT_NAME} \
    --name gpt-35-turbo \
    --type custom_model
```

### 2. Set Up Custom Telemetry Collection

```bash
# Get Application Insights connection string
export APPINS_CONNECTION=$(az monitor app-insights component show \
    --app "<app-insights-name>" \
    --resource-group ${RESOURCE_GROUP} \
    --query connectionString --output tsv)

# Configure your AI application to use this connection string
echo "Application Insights Connection String: ${APPINS_CONNECTION}"
```

### 3. Access Monitoring Dashboard

```bash
# Get Azure portal links for key resources
echo "Azure Portal Links:"
echo "Application Insights: https://portal.azure.com/#resource/subscriptions/<subscription-id>/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Insights/components/<app-insights-name>"
echo "AI Foundry Hub: https://portal.azure.com/#resource/subscriptions/<subscription-id>/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/workspaces/<hub-name>"
```

## Monitoring and Validation

### Verify Deployment

Check the status of deployed resources:

```bash
# List all resources in the resource group
az resource list \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# Check AI Foundry hub status
az ml workspace show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${AI_HUB_NAME} \
    --query '{name:name,location:location,provisioningState:provisioningState}'

# Verify budget configuration
az consumption budget list \
    --resource-group ${RESOURCE_GROUP} \
    --query '[].{name:name,amount:amount,currentSpend:currentSpend.amount}'
```

### Test Telemetry Collection

```bash
# Test Application Insights connectivity
az monitor app-insights query \
    --app ${APP_INSIGHTS_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --analytics-query "requests | limit 1"
```

### Access Monitoring Dashboards

1. **Azure Monitor Workbook**: Navigate to Azure Portal > Monitor > Workbooks > "AI Cost Monitoring Dashboard"
2. **Application Insights**: Navigate to the Application Insights resource for detailed telemetry
3. **Cost Management**: Navigate to Cost Management + Billing for budget and spending analysis

## Customization

### Adding Custom Metrics

To track additional AI-specific metrics, modify the Application Insights configuration:

```bash
# Add custom event tracking in your AI application
# Example Python code for token usage tracking:
cat > token_tracker_example.py << EOF
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry import trace

configure_azure_monitor(connection_string="${APPINS_CONNECTION}")
tracer = trace.get_tracer(__name__)

def track_ai_request(model_name, prompt_tokens, completion_tokens, cost):
    with tracer.start_as_current_span("ai_request") as span:
        span.set_attributes({
            "ai.model.name": model_name,
            "ai.usage.prompt_tokens": prompt_tokens,
            "ai.usage.completion_tokens": completion_tokens,
            "ai.cost.total": cost
        })
EOF
```

### Modifying Budget Thresholds

Update budget alerts through Azure CLI:

```bash
# Update budget with new thresholds
az consumption budget create-with-rg \
    --budget-name "ai-foundry-budget-${RANDOM_SUFFIX}" \
    --resource-group ${RESOURCE_GROUP} \
    --amount 200 \
    --notifications '{
        "50Percent": {"enabled": true, "operator": "GreaterThan", "threshold": 50, "contactEmails": ["admin@company.com"]},
        "75Percent": {"enabled": true, "operator": "GreaterThan", "threshold": 75, "contactEmails": ["admin@company.com"]},
        "100Percent": {"enabled": true, "operator": "GreaterThan", "threshold": 100, "contactEmails": ["admin@company.com"]}
    }'
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name "rg-ai-monitoring-${RANDOM_SUFFIX}" \
    --yes \
    --no-wait

echo "✅ Resource group deletion initiated"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all infrastructure
terraform destroy

# When prompted, enter 'yes' to confirm destruction
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

Verify all resources have been removed:

```bash
# Check if resource group still exists
az group exists --name "rg-ai-monitoring-${RANDOM_SUFFIX}"

# List any remaining resources (should be empty)
az resource list \
    --resource-group "rg-ai-monitoring-${RANDOM_SUFFIX}" \
    --output table
```

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**
   ```bash
   # Check your current Azure permissions
   az role assignment list --assignee $(az account show --query user.name --output tsv)
   ```

2. **Resource Name Conflicts**
   ```bash
   # Generate a new random suffix if names conflict
   export RANDOM_SUFFIX=$(openssl rand -hex 4)
   ```

3. **Budget Creation Failures**
   ```bash
   # Ensure you have Cost Management permissions
   az role assignment create \
       --assignee $(az account show --query user.name --output tsv) \
       --role "Cost Management Contributor" \
       --scope "/subscriptions/$(az account show --query id --output tsv)"
   ```

4. **Application Insights Query Failures**
   ```bash
   # Wait for data ingestion (can take 5-10 minutes)
   echo "Waiting for telemetry data ingestion..."
   sleep 300
   ```

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
# For Azure CLI commands
export AZURE_CLI_DEBUG=1

# For Terraform
export TF_LOG=DEBUG

# For bash scripts
bash -x scripts/deploy.sh
```

### Getting Help

- **Azure Support**: Use `az support` commands or Azure Portal
- **Recipe Issues**: Refer to the original recipe documentation
- **Provider Documentation**: 
  - [Azure AI Foundry Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)
  - [Application Insights Documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)
  - [Azure Cost Management Documentation](https://learn.microsoft.com/en-us/azure/cost-management-billing/)

## Architecture Overview

This infrastructure deploys:

- **Azure AI Foundry Hub and Project** for centralized AI resource management
- **Application Insights** for comprehensive telemetry collection
- **Log Analytics Workspace** for centralized logging
- **Azure Monitor Workbook** for cost visualization dashboards
- **Azure Budget** with automated alerting at 80% and 100% thresholds
- **Action Groups** for automated cost alert notifications
- **Storage Account** for AI Foundry dependencies

The solution provides real-time token usage tracking, automated cost alerting, and detailed analytics dashboards for proactive AI cost management.

## Security Considerations

- All resources are deployed with Azure security best practices
- Network access can be restricted using private endpoints (requires additional configuration)
- Application Insights data is encrypted at rest and in transit
- Budget alerts help prevent cost overruns
- IAM roles follow least privilege principle

## Performance and Scaling

- Application Insights automatically scales with telemetry volume
- AI Foundry supports multiple projects under a single hub for cost consolidation
- Log Analytics workspace can be shared across multiple AI projects
- Budget thresholds can be adjusted based on actual usage patterns

For production deployments, consider implementing additional monitoring, backup strategies, and security hardening based on your organization's requirements.