# Infrastructure as Code for Autonomous Data Pipeline Optimization with AI Agents

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Autonomous Data Pipeline Optimization with AI Agents".

## Overview

This solution deploys intelligent agents using Azure AI Foundry Agent Service to autonomously monitor, optimize, and self-heal Azure Data Factory pipelines. The infrastructure creates a comprehensive system for autonomous data pipeline management including monitoring, quality analysis, performance optimization, and self-healing capabilities.

## Architecture Components

- **Azure AI Foundry Hub & Project**: Central management layer for intelligent agents
- **Azure Data Factory**: Enterprise data orchestration platform with sample pipelines
- **Azure Monitor & Log Analytics**: Comprehensive telemetry and monitoring
- **Azure Event Grid**: Real-time event-driven communication
- **Azure Storage Account**: Data storage and agent artifacts
- **Azure Key Vault**: Secure credential management
- **AI Agents**: Four specialized autonomous agents for pipeline management:
  - Pipeline Monitoring Agent
  - Data Quality Analyzer Agent
  - Performance Optimization Agent
  - Self-Healing Agent

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### Azure Requirements

- Azure subscription with contributor permissions
- Azure CLI v2.50.0 or later installed and configured
- Azure AI Foundry (preview) enabled in your subscription
- PowerShell 5.1+ or PowerShell Core 6.0+ (for Bicep)

### Permissions Required

- `Contributor` role on the subscription or resource group
- `User Access Administrator` role for role assignments
- `AI Foundry Administrator` role for AI services (if available)

### Knowledge Prerequisites

- Understanding of Azure Data Factory pipeline concepts
- Familiarity with Azure AI services and intelligent agents
- Knowledge of Azure Monitor and Event Grid integration patterns

### Cost Considerations

- Estimated cost: $150-200 for 24-hour testing period
- Includes AI Foundry agents, Data Factory runs, monitoring services, and storage
- Costs may vary based on pipeline execution frequency and agent activity

> **Important**: Azure AI Foundry Agent Service is currently in preview. Review the [Azure AI Foundry documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/) for current availability and pricing information.

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Login to Azure (if not already logged in)
az login

# Set subscription
az account set --subscription "<your-subscription-id>"

# Create resource group
az group create \
    --name "rg-intelligent-pipeline-demo" \
    --location "eastus"

# Review and customize parameters
cp parameters.json parameters.local.json
# Edit parameters.local.json with your values

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-intelligent-pipeline-demo" \
    --template-file main.bicep \
    --parameters @parameters.local.json

# Verify deployment
az deployment group show \
    --resource-group "rg-intelligent-pipeline-demo" \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_LOCATION="eastus"
export RESOURCE_GROUP_NAME="rg-intelligent-pipeline-demo"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az group show --name $RESOURCE_GROUP_NAME --output table
```

## Configuration Options

### Bicep Parameters

Key parameters you can customize in `parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "uniqueSuffix": {
      "value": "abc123"
    },
    "dataFactoryName": {
      "value": "adf-intelligent-pipeline"
    },
    "aiFoundryHubName": {
      "value": "ai-hub-pipeline"
    },
    "aiFoundryProjectName": {
      "value": "ai-project-pipeline"
    },
    "storageAccountName": {
      "value": "stintelligentpipeline"
    },
    "logAnalyticsWorkspaceName": {
      "value": "la-pipeline-monitoring"
    },
    "eventGridTopicName": {
      "value": "eg-pipeline-events"
    },
    "keyVaultName": {
      "value": "kv-pipeline-secrets"
    },
    "enableDiagnostics": {
      "value": true
    },
    "retentionInDays": {
      "value": 30
    },
    "agentModelType": {
      "value": "gpt-4o"
    },
    "enableAdvancedMonitoring": {
      "value": true
    }
  }
}
```

### Terraform Variables

Key variables you can customize in `terraform.tfvars`:

```hcl
# Basic configuration
location = "East US"
resource_group_name = "rg-intelligent-pipeline-demo"
unique_suffix = "abc123"

# AI Foundry configuration
ai_foundry_hub_name = "ai-hub-pipeline"
ai_foundry_project_name = "ai-project-pipeline"
agent_model_type = "gpt-4o"

# Data Factory configuration
data_factory_name = "adf-intelligent-pipeline"
enable_managed_identity = true

# Monitoring configuration
log_analytics_workspace_name = "la-pipeline-monitoring"
enable_diagnostic_settings = true
retention_days = 30
enable_advanced_monitoring = true

# Storage configuration
storage_account_name = "stintelligentpipeline"
storage_account_tier = "Standard"
storage_replication_type = "LRS"

# Event Grid configuration
event_grid_topic_name = "eg-pipeline-events"

# Key Vault configuration
key_vault_name = "kv-pipeline-secrets"

# Tags
tags = {
  Environment = "Demo"
  Project     = "Intelligent-Pipeline-Automation"
  Owner       = "Data-Engineering-Team"
  Purpose     = "AI-Driven-Pipeline-Optimization"
}
```

## Post-Deployment Configuration

### 1. Configure AI Agents

After infrastructure deployment, configure the intelligent agents:

```bash
# Set environment variables from deployment outputs
export AI_FOUNDRY_HUB_NAME="$(az deployment group show --resource-group $RESOURCE_GROUP_NAME --name main --query 'properties.outputs.aiFoundryHubName.value' -o tsv)"
export AI_FOUNDRY_PROJECT_NAME="$(az deployment group show --resource-group $RESOURCE_GROUP_NAME --name main --query 'properties.outputs.aiFoundryProjectName.value' -o tsv)"
export DATA_FACTORY_NAME="$(az deployment group show --resource-group $RESOURCE_GROUP_NAME --name main --query 'properties.outputs.dataFactoryName.value' -o tsv)"

# Deploy Pipeline Monitoring Agent
cat > monitoring-agent-config.json << 'EOF'
{
    "name": "PipelineMonitoringAgent",
    "description": "Autonomous agent for monitoring Azure Data Factory pipeline performance and health",
    "instructions": "Monitor Azure Data Factory pipelines continuously. Analyze performance metrics, detect anomalies, and identify optimization opportunities. Report critical issues immediately and recommend performance improvements based on historical patterns.",
    "model": {
        "type": "azure-openai",
        "name": "gpt-4o",
        "parameters": {
            "temperature": 0.3,
            "max_tokens": 1000
        }
    },
    "triggers": [
        {
            "type": "schedule",
            "schedule": "0 */5 * * * *",
            "description": "Run every 5 minutes"
        },
        {
            "type": "event-grid",
            "source": "pipeline-events",
            "description": "Trigger on pipeline state changes"
        }
    ]
}
EOF

az ml agent create \
    --name "pipeline-monitoring-agent" \
    --resource-group $RESOURCE_GROUP_NAME \
    --project $AI_FOUNDRY_PROJECT_NAME \
    --file monitoring-agent-config.json

# Deploy Data Quality Analyzer Agent
cat > quality-agent-config.json << 'EOF'
{
    "name": "DataQualityAnalyzerAgent",
    "description": "Intelligent agent for analyzing data quality and implementing automated quality improvements",
    "instructions": "Analyze data quality metrics across pipeline executions. Identify patterns of data quality issues, recommend remediation strategies, and implement automated quality improvements. Focus on data completeness, consistency, and accuracy metrics.",
    "model": {
        "type": "azure-openai",
        "name": "gpt-4o",
        "parameters": {
            "temperature": 0.2,
            "max_tokens": 1200
        }
    },
    "triggers": [
        {
            "type": "event-grid",
            "source": "pipeline-completion",
            "description": "Analyze quality after pipeline completion"
        },
        {
            "type": "schedule",
            "schedule": "0 0 */4 * * *",
            "description": "Run comprehensive analysis every 4 hours"
        }
    ]
}
EOF

az ml agent create \
    --name "data-quality-analyzer-agent" \
    --resource-group $RESOURCE_GROUP_NAME \
    --project $AI_FOUNDRY_PROJECT_NAME \
    --file quality-agent-config.json

# Deploy Performance Optimization Agent
cat > optimization-agent-config.json << 'EOF'
{
    "name": "PerformanceOptimizationAgent",
    "description": "Autonomous agent for optimizing Azure Data Factory pipeline performance and resource utilization",
    "instructions": "Analyze pipeline performance metrics, identify bottlenecks, and implement optimization strategies. Focus on execution time, resource utilization, and cost optimization. Recommend scaling adjustments and configuration improvements based on historical patterns.",
    "model": {
        "type": "azure-openai",
        "name": "gpt-4o",
        "parameters": {
            "temperature": 0.1,
            "max_tokens": 1500
        }
    },
    "triggers": [
        {
            "type": "schedule",
            "schedule": "0 0 */6 * * *",
            "description": "Run optimization analysis every 6 hours"
        },
        {
            "type": "performance-threshold",
            "threshold": "execution_time > baseline * 1.5",
            "description": "Trigger when performance degrades significantly"
        }
    ]
}
EOF

az ml agent create \
    --name "performance-optimization-agent" \
    --resource-group $RESOURCE_GROUP_NAME \
    --project $AI_FOUNDRY_PROJECT_NAME \
    --file optimization-agent-config.json

# Deploy Self-Healing Agent
cat > healing-agent-config.json << 'EOF'
{
    "name": "SelfHealingAgent",
    "description": "Autonomous agent for implementing self-healing capabilities in Azure Data Factory pipelines",
    "instructions": "Detect pipeline failures and implement autonomous recovery strategies. Analyze failure patterns, implement intelligent retry logic, and provide alternative execution paths. Focus on reducing manual intervention and improving pipeline reliability.",
    "model": {
        "type": "azure-openai",
        "name": "gpt-4o",
        "parameters": {
            "temperature": 0.4,
            "max_tokens": 1300
        }
    },
    "triggers": [
        {
            "type": "event-grid",
            "source": "pipeline-failure",
            "description": "Trigger immediate response to pipeline failures"
        },
        {
            "type": "health-check",
            "interval": "10m",
            "description": "Regular health checks for proactive issue detection"
        }
    ]
}
EOF

az ml agent create \
    --name "self-healing-agent" \
    --resource-group $RESOURCE_GROUP_NAME \
    --project $AI_FOUNDRY_PROJECT_NAME \
    --file healing-agent-config.json

echo "✅ All AI agents deployed successfully"
```

### 2. Configure Event Grid Subscriptions

```bash
# Get Event Grid topic endpoint
EVENT_GRID_ENDPOINT=$(az eventgrid topic show \
    --resource-group $RESOURCE_GROUP_NAME \
    --name "$(az deployment group show --resource-group $RESOURCE_GROUP_NAME --name main --query 'properties.outputs.eventGridTopicName.value' -o tsv)" \
    --query endpoint --output tsv)

# Create Event Grid subscription for pipeline events
az eventgrid event-subscription create \
    --name "pipeline-events-subscription" \
    --source-resource-id "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DataFactory/factories/$DATA_FACTORY_NAME" \
    --endpoint $EVENT_GRID_ENDPOINT \
    --endpoint-type webhook \
    --included-event-types "Microsoft.DataFactory.PipelineRun" \
    --advanced-filter data.status StringIn Started Succeeded Failed

echo "✅ Event Grid subscription configured"
```

### 3. Configure Monitoring Dashboard

```bash
# Create monitoring dashboard configuration
cat > dashboard-config.json << 'EOF'
{
    "dashboard": {
        "name": "IntelligentPipelineDashboard",
        "description": "Comprehensive monitoring dashboard for intelligent pipeline automation",
        "widgets": [
            {
                "type": "pipeline-health",
                "title": "Pipeline Health Status",
                "size": "medium",
                "data_source": "azure-monitor",
                "refresh_interval": "30s"
            },
            {
                "type": "agent-activity",
                "title": "Agent Activity Feed",
                "size": "large",
                "data_source": "agent-logs",
                "refresh_interval": "10s"
            },
            {
                "type": "performance-metrics",
                "title": "Performance Trends",
                "size": "medium",
                "data_source": "performance-analytics",
                "refresh_interval": "60s"
            },
            {
                "type": "cost-optimization",
                "title": "Cost Optimization Results",
                "size": "small",
                "data_source": "cost-analysis",
                "refresh_interval": "300s"
            }
        ]
    }
}
EOF

# Deploy monitoring dashboard
az monitor dashboard create \
    --resource-group $RESOURCE_GROUP_NAME \
    --name "intelligent-pipeline-dashboard" \
    --dashboard-json @dashboard-config.json

echo "✅ Monitoring dashboard configured"
```

## Validation and Testing

### 1. Verify Infrastructure Deployment

```bash
# Check resource group contents
az resource list \
    --resource-group $RESOURCE_GROUP_NAME \
    --output table

# Verify AI Foundry Hub
az ml hub show \
    --name $AI_FOUNDRY_HUB_NAME \
    --resource-group $RESOURCE_GROUP_NAME

# Verify Data Factory
az datafactory show \
    --resource-group $RESOURCE_GROUP_NAME \
    --factory-name $DATA_FACTORY_NAME

# Check storage account
az storage account show \
    --name "$(az deployment group show --resource-group $RESOURCE_GROUP_NAME --name main --query 'properties.outputs.storageAccountName.value' -o tsv)" \
    --resource-group $RESOURCE_GROUP_NAME

# Verify Key Vault
az keyvault show \
    --name "$(az deployment group show --resource-group $RESOURCE_GROUP_NAME --name main --query 'properties.outputs.keyVaultName.value' -o tsv)" \
    --resource-group $RESOURCE_GROUP_NAME
```

### 2. Test Agent Deployment

```bash
# List deployed agents
az ml agent list \
    --resource-group $RESOURCE_GROUP_NAME \
    --project $AI_FOUNDRY_PROJECT_NAME \
    --output table

# Check agent health
az ml agent show \
    --name "pipeline-monitoring-agent" \
    --resource-group $RESOURCE_GROUP_NAME \
    --project $AI_FOUNDRY_PROJECT_NAME \
    --query "status"

# Verify all agents are running
for agent in "pipeline-monitoring-agent" "data-quality-analyzer-agent" "performance-optimization-agent" "self-healing-agent"; do
    echo "Checking $agent..."
    az ml agent show \
        --name "$agent" \
        --resource-group $RESOURCE_GROUP_NAME \
        --project $AI_FOUNDRY_PROJECT_NAME \
        --query "status"
done
```

### 3. Test Pipeline Execution

```bash
# Create and run a test pipeline
RUN_ID=$(az datafactory pipeline create-run \
    --resource-group $RESOURCE_GROUP_NAME \
    --factory-name $DATA_FACTORY_NAME \
    --name "SampleDataPipeline" \
    --parameters '{"sourceContainer": "source", "sinkContainer": "sink"}' \
    --query runId -o tsv)

echo "Pipeline run ID: $RUN_ID"

# Monitor pipeline execution
az datafactory pipeline-run show \
    --resource-group $RESOURCE_GROUP_NAME \
    --factory-name $DATA_FACTORY_NAME \
    --run-id $RUN_ID

# Check for agent responses
sleep 60  # Wait for agents to process
az ml agent-logs show \
    --name "pipeline-monitoring-agent" \
    --resource-group $RESOURCE_GROUP_NAME \
    --project $AI_FOUNDRY_PROJECT_NAME \
    --lines 50
```

### 4. Validate Event Grid Integration

```bash
# Check Event Grid subscription status
az eventgrid event-subscription show \
    --name "pipeline-events-subscription" \
    --source-resource-id "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/providers/Microsoft.DataFactory/factories/$DATA_FACTORY_NAME"

# Test event delivery
az eventgrid topic event send \
    --name "$(az deployment group show --resource-group $RESOURCE_GROUP_NAME --name main --query 'properties.outputs.eventGridTopicName.value' -o tsv)" \
    --resource-group $RESOURCE_GROUP_NAME \
    --event-data '[{"eventType": "TestEvent", "subject": "test", "data": {"message": "test"}}]'

echo "✅ Event Grid integration validated"
```

## Monitoring and Maintenance

### Access Monitoring Dashboard

```bash
# Get dashboard URL
DASHBOARD_URL=$(az monitor dashboard show \
    --resource-group $RESOURCE_GROUP_NAME \
    --name "intelligent-pipeline-dashboard" \
    --query "dashboardUri" \
    --output tsv)

echo "Dashboard URL: $DASHBOARD_URL"
```

### View Agent Logs

```bash
# View real-time agent activity
az ml agent-logs show \
    --name "pipeline-monitoring-agent" \
    --resource-group $RESOURCE_GROUP_NAME \
    --project $AI_FOUNDRY_PROJECT_NAME \
    --follow

# Query specific agent logs
az monitor log-analytics query \
    --workspace "$(az deployment group show --resource-group $RESOURCE_GROUP_NAME --name main --query 'properties.outputs.logAnalyticsWorkspaceName.value' -o tsv)" \
    --analytics-query "AgentLogs | where TimeGenerated > ago(1h) | order by TimeGenerated desc"
```

### Monitor Resource Health

```bash
# Check overall resource health
az resource health list \
    --resource-group $RESOURCE_GROUP_NAME \
    --output table

# Monitor Data Factory pipeline runs
az datafactory pipeline-run query-by-factory \
    --resource-group $RESOURCE_GROUP_NAME \
    --factory-name $DATA_FACTORY_NAME \
    --last-updated-after "2024-01-01T00:00:00Z" \
    --last-updated-before "2024-12-31T23:59:59Z"

# Check agent orchestration status
az ml agent-orchestration show \
    --name "pipeline-agent-orchestration" \
    --resource-group $RESOURCE_GROUP_NAME \
    --project $AI_FOUNDRY_PROJECT_NAME
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name $RESOURCE_GROUP_NAME \
    --yes \
    --no-wait

echo "✅ Resource group deletion initiated: $RESOURCE_GROUP_NAME"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
echo "✅ Terraform resources destroyed"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group exists --name $RESOURCE_GROUP_NAME
```

## Troubleshooting

### Common Issues

1. **AI Foundry Service Unavailable**
   - Verify Azure AI Foundry is available in your region
   - Check subscription permissions for AI services
   - Review preview feature availability

2. **Agent Deployment Failures**
   - Verify AI Foundry Hub and Project are properly configured
   - Check agent configuration JSON syntax
   - Ensure proper permissions for agent deployment

3. **Event Grid Integration Issues**
   - Verify Event Grid topic is properly configured
   - Check webhook endpoint accessibility
   - Review Event Grid subscription filters

4. **Data Factory Permission Errors**
   - Ensure Data Factory has proper access to Storage Account
   - Verify managed identity permissions
   - Check RBAC role assignments

5. **Monitoring Dashboard Issues**
   - Verify Log Analytics workspace is collecting data
   - Check dashboard JSON configuration
   - Ensure proper permissions for dashboard access

### Diagnostic Commands

```bash
# Check deployment status
az deployment group show \
    --resource-group $RESOURCE_GROUP_NAME \
    --name main \
    --query "properties.provisioningState"

# View deployment errors
az deployment operation group list \
    --resource-group $RESOURCE_GROUP_NAME \
    --name main \
    --query "[?properties.provisioningState=='Failed']"

# Check AI Foundry service health
az ml hub show \
    --name $AI_FOUNDRY_HUB_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --query "properties.provisioningState"

# Verify resource provider registrations
az provider show --namespace Microsoft.DataFactory --query "registrationState"
az provider show --namespace Microsoft.MachineLearningServices --query "registrationState"
az provider show --namespace Microsoft.EventGrid --query "registrationState"

# Check role assignments
az role assignment list \
    --assignee $(az account show --query user.name -o tsv) \
    --resource-group $RESOURCE_GROUP_NAME \
    --output table
```

## Security Considerations

### Default Security Settings

- **Network Security**: Private endpoints enabled for sensitive services
- **Identity Management**: Managed identities used for service authentication
- **Encryption**: Data encrypted at rest and in transit
- **Access Control**: Role-based access control (RBAC) implemented
- **Secrets Management**: Azure Key Vault for secure credential storage

### Additional Security Hardening

```bash
# Enable private endpoints for Storage Account
STORAGE_ACCOUNT_NAME=$(az deployment group show --resource-group $RESOURCE_GROUP_NAME --name main --query 'properties.outputs.storageAccountName.value' -o tsv)
az storage account update \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --default-action Deny \
    --bypass AzureServices

# Configure Key Vault network restrictions
KEY_VAULT_NAME=$(az deployment group show --resource-group $RESOURCE_GROUP_NAME --name main --query 'properties.outputs.keyVaultName.value' -o tsv)
az keyvault update \
    --name $KEY_VAULT_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --default-action Deny \
    --bypass AzureServices

# Enable advanced threat protection
az storage account update \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --enable-advanced-threat-protection true
```

## Performance Optimization

### Agent Performance Tuning

```bash
# Adjust agent polling intervals based on workload
az ml agent update \
    --name "pipeline-monitoring-agent" \
    --resource-group $RESOURCE_GROUP_NAME \
    --project $AI_FOUNDRY_PROJECT_NAME \
    --polling-interval "300s"  # 5 minutes

# Configure agent resource limits
az ml agent update \
    --name "performance-optimization-agent" \
    --resource-group $RESOURCE_GROUP_NAME \
    --project $AI_FOUNDRY_PROJECT_NAME \
    --cpu-limit "1000m" \
    --memory-limit "2Gi"
```

### Cost Optimization

```bash
# Set budget alerts
az consumption budget create \
    --amount 200 \
    --budget-name "intelligent-pipeline-budget" \
    --resource-group $RESOURCE_GROUP_NAME \
    --time-grain Monthly \
    --time-period-start "2024-01-01T00:00:00Z" \
    --time-period-end "2024-12-31T23:59:59Z"

# Monitor spending
az consumption usage list \
    --start-date "2024-01-01" \
    --end-date "2024-01-31" \
    --resource-group $RESOURCE_GROUP_NAME \
    --output table
```

## Advanced Configuration

### Multi-Region Deployment

For production scenarios, consider deploying across multiple Azure regions:

```bash
# Deploy to secondary region
export SECONDARY_REGION="westus2"
export SECONDARY_RESOURCE_GROUP="rg-intelligent-pipeline-secondary"

# Create secondary resource group
az group create \
    --name $SECONDARY_RESOURCE_GROUP \
    --location $SECONDARY_REGION

# Deploy infrastructure to secondary region
az deployment group create \
    --resource-group $SECONDARY_RESOURCE_GROUP \
    --template-file bicep/main.bicep \
    --parameters location=$SECONDARY_REGION uniqueSuffix="secondary"
```

### Integration with Existing Systems

```bash
# Connect to existing Data Factory
az datafactory integration-runtime create \
    --factory-name $DATA_FACTORY_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --name "ExistingSystemIntegration" \
    --type "SelfHosted"

# Configure custom alert channels
az monitor action-group create \
    --resource-group $RESOURCE_GROUP_NAME \
    --name "PipelineAlerts" \
    --short-name "PipelineAlerts" \
    --email-receivers name="admin" email="admin@company.com"
```

## Support and Resources

### Documentation Links

- [Azure AI Foundry Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Azure Data Factory Documentation](https://learn.microsoft.com/en-us/azure/data-factory/)
- [Azure Monitor Documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/)
- [Azure Event Grid Documentation](https://learn.microsoft.com/en-us/azure/event-grid/)
- [Azure Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

### Community Resources

- [Azure Data Factory Community](https://techcommunity.microsoft.com/t5/azure-data-factory/bd-p/AzureDataFactory)
- [Azure AI Community](https://techcommunity.microsoft.com/t5/azure-ai/bd-p/AzureAI)
- [Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Azure service documentation
4. Contact Azure support for service-specific issues

## Contributing

When contributing improvements to this infrastructure code:

1. Test changes in a development environment
2. Update documentation accordingly
3. Follow Azure naming conventions and best practices
4. Ensure security configurations remain intact
5. Validate against the original recipe requirements

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify according to your organization's requirements and policies.