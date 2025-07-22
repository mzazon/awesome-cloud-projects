#!/bin/bash

# Azure Intelligent Data Pipeline Automation - Deployment Script
# This script deploys Azure AI Foundry Agent Service and Azure Data Factory for intelligent pipeline automation

set -e
set -o pipefail

# Script configuration
SCRIPT_NAME="Azure Intelligent Pipeline Automation Deploy"
LOG_FILE="deployment_$(date +%Y%m%d_%H%M%S).log"
ERROR_COUNT=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling function
handle_error() {
    local exit_code=$?
    ERROR_COUNT=$((ERROR_COUNT + 1))
    echo -e "${RED}❌ Error occurred in function: ${FUNCNAME[1]}, line: $1${NC}" | tee -a "$LOG_FILE"
    echo -e "${RED}Exit code: $exit_code${NC}" | tee -a "$LOG_FILE"
    
    if [ $ERROR_COUNT -ge 3 ]; then
        echo -e "${RED}💥 Multiple errors detected. Stopping deployment.${NC}" | tee -a "$LOG_FILE"
        exit 1
    fi
}

trap 'handle_error $LINENO' ERR

# Progress indicator
show_progress() {
    local current=$1
    local total=$2
    local message=$3
    local percent=$((current * 100 / total))
    echo -e "${BLUE}[${current}/${total}] (${percent}%) ${message}${NC}"
}

# Validation functions
check_prerequisites() {
    log "🔍 Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        echo -e "${RED}❌ Azure CLI is not installed. Please install it first.${NC}"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        echo -e "${RED}❌ Not logged into Azure. Please run 'az login' first.${NC}"
        exit 1
    fi
    
    # Check if required extensions are available
    local extensions=("ml" "datafactory")
    for ext in "${extensions[@]}"; do
        if ! az extension show --name "$ext" &> /dev/null; then
            echo -e "${YELLOW}⚠️  Installing Azure CLI extension: $ext${NC}"
            az extension add --name "$ext" --yes
        fi
    done
    
    # Check if OpenSSL is available for random string generation
    if ! command -v openssl &> /dev/null; then
        echo -e "${RED}❌ OpenSSL is not available. Required for generating random suffixes.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check completed${NC}"
}

validate_azure_subscription() {
    log "🔍 Validating Azure subscription..."
    
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    
    if [ -z "$subscription_id" ]; then
        echo -e "${RED}❌ Could not determine Azure subscription ID${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Using Azure subscription: $subscription_name ($subscription_id)${NC}"
    export SUBSCRIPTION_ID="$subscription_id"
}

# Configuration function
setup_environment() {
    log "🛠️  Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-intelligent-pipeline-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    
    # Define resource names
    export DATA_FACTORY_NAME="adf-intelligent-${RANDOM_SUFFIX}"
    export AI_FOUNDRY_HUB_NAME="ai-hub-${RANDOM_SUFFIX}"
    export AI_FOUNDRY_PROJECT_NAME="ai-project-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stintelligent${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_NAME="la-intelligent-${RANDOM_SUFFIX}"
    export EVENT_GRID_TOPIC_NAME="eg-pipeline-events-${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-intelligent-${RANDOM_SUFFIX}"
    
    # Validate storage account name length (must be 3-24 characters)
    if [ ${#STORAGE_ACCOUNT_NAME} -gt 24 ]; then
        echo -e "${RED}❌ Storage account name too long: ${STORAGE_ACCOUNT_NAME}${NC}"
        exit 1
    fi
    
    # Validate Key Vault name length (must be 3-24 characters)
    if [ ${#KEY_VAULT_NAME} -gt 24 ]; then
        echo -e "${RED}❌ Key Vault name too long: ${KEY_VAULT_NAME}${NC}"
        exit 1
    fi
    
    log "Environment configured with suffix: ${RANDOM_SUFFIX}"
    echo -e "${GREEN}✅ Environment variables configured${NC}"
}

# Main deployment functions
create_resource_group() {
    show_progress 1 10 "Creating resource group..."
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=intelligent-pipeline-automation environment=demo \
        >> "$LOG_FILE" 2>&1
    
    log "✅ Resource group created: ${RESOURCE_GROUP}"
}

create_log_analytics_workspace() {
    show_progress 2 10 "Creating Log Analytics workspace..."
    
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --location "${LOCATION}" \
        --sku pergb2018 \
        >> "$LOG_FILE" 2>&1
    
    log "✅ Log Analytics workspace created: ${LOG_ANALYTICS_NAME}"
}

create_storage_account() {
    show_progress 3 10 "Creating storage account..."
    
    az storage account create \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --hierarchical-namespace true \
        --tags purpose=intelligent-pipeline-automation \
        >> "$LOG_FILE" 2>&1
    
    log "✅ Storage account created: ${STORAGE_ACCOUNT_NAME}"
}

create_key_vault() {
    show_progress 4 10 "Creating Key Vault..."
    
    az keyvault create \
        --name "${KEY_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku standard \
        --enable-rbac-authorization true \
        --tags purpose=intelligent-pipeline-automation \
        >> "$LOG_FILE" 2>&1
    
    log "✅ Key Vault created: ${KEY_VAULT_NAME}"
}

create_ai_foundry_resources() {
    show_progress 5 10 "Creating AI Foundry Hub and Project..."
    
    # Create AI Foundry Hub
    az ml hub create \
        --name "${AI_FOUNDRY_HUB_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --storage-account "${STORAGE_ACCOUNT_NAME}" \
        --key-vault "${KEY_VAULT_NAME}" \
        --tags purpose=intelligent-pipeline-automation \
        >> "$LOG_FILE" 2>&1
    
    # Wait for hub creation to complete
    echo "Waiting for AI Foundry Hub to be ready..."
    sleep 30
    
    # Create AI Foundry Project
    az ml project create \
        --name "${AI_FOUNDRY_PROJECT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --hub "${AI_FOUNDRY_HUB_NAME}" \
        --tags purpose=intelligent-pipeline-automation \
        >> "$LOG_FILE" 2>&1
    
    log "✅ AI Foundry Hub and Project created successfully"
}

create_data_factory() {
    show_progress 6 10 "Creating Azure Data Factory..."
    
    az datafactory create \
        --resource-group "${RESOURCE_GROUP}" \
        --factory-name "${DATA_FACTORY_NAME}" \
        --location "${LOCATION}" \
        --tags purpose=intelligent-pipeline-automation \
        >> "$LOG_FILE" 2>&1
    
    # Create sample pipeline configuration
    cat > pipeline-config.json << 'EOF'
{
    "name": "SampleDataPipeline",
    "properties": {
        "activities": [
            {
                "name": "CopyData",
                "type": "Copy",
                "typeProperties": {
                    "source": {
                        "type": "BlobSource"
                    },
                    "sink": {
                        "type": "BlobSink"
                    }
                },
                "inputs": [
                    {
                        "referenceName": "SourceDataset",
                        "type": "DatasetReference"
                    }
                ],
                "outputs": [
                    {
                        "referenceName": "SinkDataset",
                        "type": "DatasetReference"
                    }
                ]
            }
        ],
        "parameters": {
            "sourceContainer": {
                "type": "String"
            },
            "sinkContainer": {
                "type": "String"
            }
        }
    }
}
EOF
    
    # Create sample pipeline
    az datafactory pipeline create \
        --resource-group "${RESOURCE_GROUP}" \
        --factory-name "${DATA_FACTORY_NAME}" \
        --name SampleDataPipeline \
        --pipeline @pipeline-config.json \
        >> "$LOG_FILE" 2>&1
    
    log "✅ Data Factory and sample pipelines created"
}

configure_monitoring() {
    show_progress 7 10 "Configuring Azure Monitor integration..."
    
    # Get Log Analytics workspace ID
    local log_analytics_id=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --query id --output tsv)
    
    # Configure Data Factory diagnostic settings
    az monitor diagnostic-settings create \
        --resource "${DATA_FACTORY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --resource-type Microsoft.DataFactory/factories \
        --name "DataFactoryDiagnostics" \
        --workspace "${log_analytics_id}" \
        --logs '[
            {
                "category": "PipelineRuns",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            },
            {
                "category": "ActivityRuns",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            },
            {
                "category": "TriggerRuns",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            }
        ]' \
        --metrics '[
            {
                "category": "AllMetrics",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            }
        ]' \
        >> "$LOG_FILE" 2>&1
    
    log "✅ Azure Monitor integration configured"
}

create_event_grid() {
    show_progress 8 10 "Creating Event Grid topic..."
    
    # Create Event Grid topic
    az eventgrid topic create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${EVENT_GRID_TOPIC_NAME}" \
        --location "${LOCATION}" \
        --tags purpose=intelligent-pipeline-automation \
        >> "$LOG_FILE" 2>&1
    
    # Get Event Grid topic endpoint
    local event_grid_endpoint=$(az eventgrid topic show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${EVENT_GRID_TOPIC_NAME}" \
        --query endpoint --output tsv)
    
    # Create Event Grid subscription for pipeline events
    az eventgrid event-subscription create \
        --name "pipeline-events-subscription" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DataFactory/factories/${DATA_FACTORY_NAME}" \
        --endpoint "${event_grid_endpoint}" \
        --endpoint-type webhook \
        --included-event-types "Microsoft.DataFactory.PipelineRun" \
        --advanced-filter data.status StringIn Started Succeeded Failed \
        >> "$LOG_FILE" 2>&1
    
    log "✅ Event Grid topic and subscription created"
}

deploy_ai_agents() {
    show_progress 9 10 "Deploying AI agents..."
    
    # Create agent configuration files
    create_agent_configs
    
    # Deploy Pipeline Monitoring Agent
    az ml agent create \
        --name "pipeline-monitoring-agent" \
        --resource-group "${RESOURCE_GROUP}" \
        --project "${AI_FOUNDRY_PROJECT_NAME}" \
        --file monitoring-agent-config.json \
        >> "$LOG_FILE" 2>&1 || echo "⚠️  Agent deployment may require manual configuration"
    
    # Deploy Data Quality Analyzer Agent
    az ml agent create \
        --name "data-quality-analyzer-agent" \
        --resource-group "${RESOURCE_GROUP}" \
        --project "${AI_FOUNDRY_PROJECT_NAME}" \
        --file quality-agent-config.json \
        >> "$LOG_FILE" 2>&1 || echo "⚠️  Agent deployment may require manual configuration"
    
    # Deploy Performance Optimization Agent
    az ml agent create \
        --name "performance-optimization-agent" \
        --resource-group "${RESOURCE_GROUP}" \
        --project "${AI_FOUNDRY_PROJECT_NAME}" \
        --file optimization-agent-config.json \
        >> "$LOG_FILE" 2>&1 || echo "⚠️  Agent deployment may require manual configuration"
    
    # Deploy Self-Healing Agent
    az ml agent create \
        --name "self-healing-agent" \
        --resource-group "${RESOURCE_GROUP}" \
        --project "${AI_FOUNDRY_PROJECT_NAME}" \
        --file healing-agent-config.json \
        >> "$LOG_FILE" 2>&1 || echo "⚠️  Agent deployment may require manual configuration"
    
    log "✅ AI agents deployment initiated"
}

create_agent_configs() {
    # Create monitoring agent configuration
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
    "tools": [
        {
            "type": "azure-monitor",
            "name": "query-metrics",
            "description": "Query Azure Monitor for pipeline metrics and logs"
        },
        {
            "type": "azure-data-factory",
            "name": "pipeline-status",
            "description": "Check pipeline execution status and history"
        },
        {
            "type": "alert-system",
            "name": "send-alert",
            "description": "Send alerts for critical pipeline issues"
        }
    ],
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

    # Create quality agent configuration
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
    "tools": [
        {
            "type": "data-profiling",
            "name": "analyze-data-quality",
            "description": "Analyze data quality metrics and patterns"
        },
        {
            "type": "azure-monitor",
            "name": "query-quality-metrics",
            "description": "Query data quality metrics from Azure Monitor"
        },
        {
            "type": "data-factory",
            "name": "implement-quality-checks",
            "description": "Implement automated data quality checks in pipelines"
        }
    ],
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

    # Create optimization agent configuration
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
    "tools": [
        {
            "type": "performance-analytics",
            "name": "analyze-performance-metrics",
            "description": "Analyze pipeline performance and resource utilization"
        },
        {
            "type": "azure-data-factory",
            "name": "optimize-pipeline-config",
            "description": "Optimize pipeline configurations for performance"
        },
        {
            "type": "cost-analysis",
            "name": "analyze-cost-patterns",
            "description": "Analyze cost patterns and optimize resource allocation"
        }
    ],
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

    # Create healing agent configuration
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
    "tools": [
        {
            "type": "failure-analysis",
            "name": "analyze-failure-patterns",
            "description": "Analyze pipeline failure patterns and root causes"
        },
        {
            "type": "azure-data-factory",
            "name": "implement-recovery-actions",
            "description": "Implement recovery actions and retry strategies"
        },
        {
            "type": "notification-system",
            "name": "escalate-issues",
            "description": "Escalate critical issues that require human intervention"
        }
    ],
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
}

configure_monitoring_dashboard() {
    show_progress 10 10 "Configuring monitoring dashboard..."
    
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
        --resource-group "${RESOURCE_GROUP}" \
        --name "intelligent-pipeline-dashboard" \
        --dashboard-json @dashboard-config.json \
        >> "$LOG_FILE" 2>&1 || echo "⚠️  Dashboard creation may require manual configuration"
    
    # Configure alert rules for agent failures
    az monitor metrics alert create \
        --name "agent-failure-alert" \
        --resource-group "${RESOURCE_GROUP}" \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        --condition "count 'agent_errors' > 5" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --severity 2 \
        >> "$LOG_FILE" 2>&1 || echo "⚠️  Alert rule creation may require manual configuration"
    
    log "✅ Monitoring dashboard and alerts configured"
}

# Validation functions
validate_deployment() {
    echo -e "${BLUE}🔍 Validating deployment...${NC}"
    
    local validation_errors=0
    
    # Check resource group
    if az group show --name "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Resource group exists${NC}"
    else
        echo -e "${RED}❌ Resource group not found${NC}"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check Data Factory
    if az datafactory show --resource-group "${RESOURCE_GROUP}" --factory-name "${DATA_FACTORY_NAME}" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Data Factory exists${NC}"
    else
        echo -e "${RED}❌ Data Factory not found${NC}"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check AI Foundry Hub
    if az ml hub show --name "${AI_FOUNDRY_HUB_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ AI Foundry Hub exists${NC}"
    else
        echo -e "${RED}❌ AI Foundry Hub not found${NC}"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check Storage Account
    if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Storage Account exists${NC}"
    else
        echo -e "${RED}❌ Storage Account not found${NC}"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check Event Grid Topic
    if az eventgrid topic show --name "${EVENT_GRID_TOPIC_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Event Grid Topic exists${NC}"
    else
        echo -e "${RED}❌ Event Grid Topic not found${NC}"
        validation_errors=$((validation_errors + 1))
    fi
    
    if [ $validation_errors -eq 0 ]; then
        echo -e "${GREEN}🎉 Deployment validation successful!${NC}"
        return 0
    else
        echo -e "${RED}❌ Deployment validation failed with $validation_errors errors${NC}"
        return 1
    fi
}

cleanup_temp_files() {
    log "🧹 Cleaning up temporary files..."
    
    rm -f pipeline-config.json
    rm -f monitoring-agent-config.json
    rm -f quality-agent-config.json
    rm -f optimization-agent-config.json
    rm -f healing-agent-config.json
    rm -f dashboard-config.json
    
    echo -e "${GREEN}✅ Temporary files cleaned up${NC}"
}

display_deployment_summary() {
    echo ""
    echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}📋 Deployment Summary:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${YELLOW}Resource Group:${NC} ${RESOURCE_GROUP}"
    echo -e "${YELLOW}Location:${NC} ${LOCATION}"
    echo -e "${YELLOW}Data Factory:${NC} ${DATA_FACTORY_NAME}"
    echo -e "${YELLOW}AI Foundry Hub:${NC} ${AI_FOUNDRY_HUB_NAME}"
    echo -e "${YELLOW}AI Foundry Project:${NC} ${AI_FOUNDRY_PROJECT_NAME}"
    echo -e "${YELLOW}Storage Account:${NC} ${STORAGE_ACCOUNT_NAME}"
    echo -e "${YELLOW}Key Vault:${NC} ${KEY_VAULT_NAME}"
    echo -e "${YELLOW}Log Analytics:${NC} ${LOG_ANALYTICS_NAME}"
    echo -e "${YELLOW}Event Grid Topic:${NC} ${EVENT_GRID_TOPIC_NAME}"
    echo ""
    echo -e "${BLUE}📊 Next Steps:${NC}"
    echo "1. Access the Azure portal to configure AI agents"
    echo "2. Review the monitoring dashboard for pipeline insights"
    echo "3. Test pipeline execution and agent responses"
    echo "4. Configure additional data sources and pipelines as needed"
    echo ""
    echo -e "${BLUE}📝 Important Notes:${NC}"
    echo "• AI Foundry Agent Service is in preview - some features may require manual configuration"
    echo "• Review agent configurations and update as needed for your specific requirements"
    echo "• Monitor costs and adjust resource configurations based on usage patterns"
    echo ""
    echo -e "${YELLOW}🔗 Useful Links:${NC}"
    echo "• Azure Data Factory: https://portal.azure.com/#resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DataFactory/factories/${DATA_FACTORY_NAME}"
    echo "• AI Foundry Hub: https://portal.azure.com/#resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/hubs/${AI_FOUNDRY_HUB_NAME}"
    echo ""
    echo -e "${GREEN}📋 Log file saved as: ${LOG_FILE}${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main execution
main() {
    echo -e "${BLUE}🚀 Starting ${SCRIPT_NAME}${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    log "Starting deployment of Azure Intelligent Data Pipeline Automation"
    
    # Pre-deployment checks
    check_prerequisites
    validate_azure_subscription
    setup_environment
    
    # Main deployment
    create_resource_group
    create_log_analytics_workspace
    create_storage_account
    create_key_vault
    create_ai_foundry_resources
    create_data_factory
    configure_monitoring
    create_event_grid
    deploy_ai_agents
    configure_monitoring_dashboard
    
    # Post-deployment
    validate_deployment
    cleanup_temp_files
    display_deployment_summary
    
    log "Deployment completed successfully"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi