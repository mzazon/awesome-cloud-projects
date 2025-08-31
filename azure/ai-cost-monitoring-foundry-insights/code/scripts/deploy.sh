#!/bin/bash

# Azure AI Cost Monitoring with Foundry and Application Insights - Deployment Script
# This script deploys the complete infrastructure for AI cost monitoring
# Version: 1.0
# Last Updated: 2025-01-16

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Starting cleanup of partially created resources..."
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if az group exists --name "${RESOURCE_GROUP}" --output tsv 2>/dev/null; then
            warn "Cleaning up resource group: ${RESOURCE_GROUP}"
            az group delete --name "${RESOURCE_GROUP}" --yes --no-wait 2>/dev/null || true
        fi
    fi
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version (minimum 2.60.0)
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    local required_version="2.60.0"
    
    if ! printf '%s\n%s' "$required_version" "$az_version" | sort -V -C; then
        error "Azure CLI version $required_version or higher is required. Current version: $az_version"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check for required utilities
    for cmd in openssl python3; do
        if ! command -v "$cmd" &> /dev/null; then
            error "Required command '$cmd' is not available"
            exit 1
        fi
    done
    
    log "Prerequisites check passed ✅"
}

# Configuration validation
validate_configuration() {
    log "Validating configuration..."
    
    # Validate location
    if ! az account list-locations --query "[?name=='${LOCATION}']" -o table | grep -q "${LOCATION}"; then
        error "Invalid Azure location: ${LOCATION}"
        exit 1
    fi
    
    # Check subscription permissions
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    local role_assignments
    role_assignments=$(az role assignment list --assignee "$(az account show --query user.name -o tsv)" --scope "/subscriptions/${subscription_id}" --query "[?roleDefinitionName=='Owner' || roleDefinitionName=='Contributor'].roleDefinitionName" -o tsv)
    
    if [[ -z "$role_assignments" ]]; then
        error "Insufficient permissions. Owner or Contributor role required."
        exit 1
    fi
    
    log "Configuration validation passed ✅"
}

# Resource existence check
check_resource_existence() {
    log "Checking for existing resources..."
    
    if az group exists --name "${RESOURCE_GROUP}" --output tsv; then
        if [[ "${FORCE_DEPLOY:-false}" != "true" ]]; then
            error "Resource group '${RESOURCE_GROUP}' already exists. Use --force to overwrite or choose a different name."
            exit 1
        else
            warn "Resource group exists but --force flag is set. Will proceed with deployment."
        fi
    fi
    
    log "Resource existence check completed ✅"
}

# Main deployment function
deploy_infrastructure() {
    log "Starting infrastructure deployment..."
    
    # Step 1: Create Resource Group
    log "Creating resource group: ${RESOURCE_GROUP}"
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=ai-monitoring environment=demo deployment-script=true \
        --output none
    
    info "Resource group created successfully"
    
    # Step 2: Create Log Analytics Workspace
    log "Creating Log Analytics workspace: ${LOG_ANALYTICS_NAME}"
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --location "${LOCATION}" \
        --tags purpose=ai-monitoring \
        --output none
    
    # Get Log Analytics workspace ID
    local log_analytics_id
    log_analytics_id=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --query id --output tsv)
    
    info "Log Analytics workspace created: ${LOG_ANALYTICS_NAME}"
    
    # Step 3: Create Application Insights
    log "Creating Application Insights: ${APP_INSIGHTS_NAME}"
    az monitor app-insights component create \
        --app "${APP_INSIGHTS_NAME}" \
        --location "${LOCATION}" \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace "${log_analytics_id}" \
        --kind web \
        --tags purpose=ai-monitoring \
        --output none
    
    # Get Application Insights key and connection string
    local appins_key appins_connection
    appins_key=$(az monitor app-insights component show \
        --app "${APP_INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query instrumentationKey --output tsv)
    
    appins_connection=$(az monitor app-insights component show \
        --app "${APP_INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString --output tsv)
    
    info "Application Insights created with key: ${appins_key}"
    
    # Step 4: Create Storage Account
    log "Creating storage account: ${STORAGE_ACCOUNT_NAME}"
    az storage account create \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --tags purpose=ai-foundry \
        --output none
    
    info "Storage account created: ${STORAGE_ACCOUNT_NAME}"
    
    # Step 5: Deploy Azure AI Foundry Hub
    log "Creating AI Foundry Hub: ${AI_HUB_NAME}"
    az ml workspace create \
        --kind hub \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AI_HUB_NAME}" \
        --location "${LOCATION}" \
        --storage-account "${STORAGE_ACCOUNT_NAME}" \
        --application-insights "${appins_key}" \
        --tags purpose=ai-foundry environment=monitoring \
        --output none
    
    # Get Hub ID for project creation
    local hub_id
    hub_id=$(az ml workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AI_HUB_NAME}" \
        --query id --output tsv)
    
    info "AI Foundry Hub created successfully"
    
    # Step 6: Create AI Foundry Project
    log "Creating AI Foundry Project: ${AI_PROJECT_NAME}"
    az ml workspace create \
        --kind project \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AI_PROJECT_NAME}" \
        --hub-id "${hub_id}" \
        --tags purpose=ai-project parent-hub="${AI_HUB_NAME}" \
        --output none
    
    info "AI Foundry Project created successfully"
    
    # Step 7: Configure Custom Metrics in Application Insights
    log "Configuring custom metrics in Application Insights..."
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    
    az rest \
        --method PATCH \
        --url "https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Insights/components/${APP_INSIGHTS_NAME}?api-version=2020-02-02" \
        --body '{
          "properties": {
            "customMetricsOptedInType": "WithDimensions"
          }
        }' \
        --output none 2>/dev/null || warn "Custom metrics configuration may have failed"
    
    info "Custom metrics configuration completed"
    
    # Step 8: Create AI Cost Monitoring Budget
    log "Creating AI cost monitoring budget..."
    local start_date end_date
    start_date=$(date -d "first day of this month" +%Y-%m-01)
    end_date=$(date -d "first day of next year" +%Y-01-01)
    
    # Create budget with error handling
    if ! az consumption budget create-with-rg \
        --budget-name "ai-foundry-budget-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --amount 100 \
        --time-grain Monthly \
        --time-period start="${start_date}" end="${end_date}" \
        --category Cost \
        --notifications '{
          "80Percent": {
            "enabled": true,
            "operator": "GreaterThan",
            "threshold": 80,
            "contactEmails": ["'"${ALERT_EMAIL}"'"]
          },
          "100Percent": {
            "enabled": true,
            "operator": "GreaterThan", 
            "threshold": 100,
            "contactEmails": ["'"${ALERT_EMAIL}"'"]
          }
        }' \
        --output none 2>/dev/null; then
        warn "Budget creation failed - this may require additional permissions"
    else
        info "AI cost budget created with thresholds at 80% and 100%"
    fi
    
    # Step 9: Create Action Group for Cost Alerts
    log "Creating Action Group for cost alerts..."
    az monitor action-group create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "ai-cost-alerts-${RANDOM_SUFFIX}" \
        --short-name "AIAlerts" \
        --email admin "${ALERT_EMAIL}" \
        --tags purpose=cost-monitoring \
        --output none
    
    info "Action Group created for cost alerts"
    
    # Step 10: Create Monitoring Dashboard
    log "Creating Azure Monitor Dashboard..."
    
    # Create workbook template
    cat > "/tmp/ai-monitoring-workbook-${RANDOM_SUFFIX}.json" << EOF
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "# AI Cost Monitoring Dashboard\\n\\nComprehensive view of AI token usage, costs, and performance metrics."
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "customEvents\\n| where name == \\"tokenUsage\\"\\n| summarize TotalCost = sum(todouble(customMeasurements.estimatedCost)), TotalTokens = sum(todouble(customMeasurements.totalTokens)) by bin(timestamp, 1h)\\n| render timechart",
        "queryType": 0,
        "resourceType": "microsoft.insights/components"
      }
    }
  ]
}
EOF
    
    # Deploy workbook
    if az monitor workbook create \
        --resource-group "${RESOURCE_GROUP}" \
        --display-name "AI Cost Monitoring Dashboard" \
        --serialized-data "$(cat "/tmp/ai-monitoring-workbook-${RANDOM_SUFFIX}.json")" \
        --location "${LOCATION}" \
        --tags purpose=ai-monitoring \
        --output none 2>/dev/null; then
        info "AI monitoring dashboard created successfully"
    else
        warn "Dashboard creation failed - workbook may need manual creation"
    fi
    
    # Cleanup temporary file
    rm -f "/tmp/ai-monitoring-workbook-${RANDOM_SUFFIX}.json"
    
    # Step 11: Create sample configuration files
    log "Creating sample configuration files..."
    
    # Create cost tracking Python script
    cat > "/tmp/cost_tracker_${RANDOM_SUFFIX}.py" << EOF
#!/usr/bin/env python3
"""
AI Cost Tracking Integration for Azure Application Insights
This script demonstrates how to track AI token usage and costs.
"""

import json
import time
import os
from typing import Dict, Any

# Application Insights connection string
APPINS_CONNECTION = "${appins_connection}"

def track_ai_costs(model_name: str, prompt_tokens: int, completion_tokens: int, total_cost: float) -> None:
    """
    Track AI costs and token usage in Application Insights
    
    Args:
        model_name: Name of the AI model used
        prompt_tokens: Number of tokens in the prompt
        completion_tokens: Number of tokens in the completion
        total_cost: Total cost of the request
    """
    try:
        # Configure Application Insights telemetry
        from azure.monitor.opentelemetry import configure_azure_monitor
        from opentelemetry import trace
        
        configure_azure_monitor(connection_string=APPINS_CONNECTION)
        tracer = trace.get_tracer(__name__)
        
        with tracer.start_as_current_span("ai_token_usage") as span:
            span.set_attributes({
                "ai.model.name": model_name,
                "ai.usage.prompt_tokens": prompt_tokens,
                "ai.usage.completion_tokens": completion_tokens,
                "ai.usage.total_tokens": prompt_tokens + completion_tokens,
                "ai.cost.total": total_cost,
                "ai.timestamp": int(time.time())
            })
        
        print(f"✅ Tracked usage for {model_name}: {prompt_tokens + completion_tokens} tokens, \${total_cost:.4f}")
        
    except ImportError:
        print("⚠️  Azure Monitor OpenTelemetry package not installed. Run: pip install azure-monitor-opentelemetry")
    except Exception as e:
        print(f"❌ Error tracking AI costs: {e}")

def simulate_usage():
    """Simulate AI usage for testing"""
    track_ai_costs("gpt-35-turbo", 150, 75, 0.003)
    track_ai_costs("gpt-4", 200, 100, 0.012)

if __name__ == "__main__":
    print("AI Cost Tracking Script")
    print("Connection String:", APPINS_CONNECTION[:50] + "...")
    simulate_usage()
EOF
    
    info "Sample configuration files created in /tmp/"
    
    log "Deployment completed successfully! 🎉"
}

# Generate deployment summary
generate_summary() {
    log "Generating deployment summary..."
    
    cat << EOF

╔══════════════════════════════════════════════════════════════════════════════╗
║                           DEPLOYMENT SUMMARY                                ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ Resource Group:         ${RESOURCE_GROUP}
║ Location:              ${LOCATION}
║ AI Foundry Hub:        ${AI_HUB_NAME}
║ AI Foundry Project:    ${AI_PROJECT_NAME}
║ Application Insights:  ${APP_INSIGHTS_NAME}
║ Log Analytics:         ${LOG_ANALYTICS_NAME}
║ Storage Account:       ${STORAGE_ACCOUNT_NAME}
║ Random Suffix:         ${RANDOM_SUFFIX}
╠══════════════════════════════════════════════════════════════════════════════╣
║                              NEXT STEPS                                      ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ 1. Review the Azure AI Foundry Hub in the Azure portal                      ║
║ 2. Check Application Insights for telemetry data                            ║
║ 3. Configure your AI applications to use the monitoring                     ║
║ 4. Set up cost alerts and budgets as needed                                 ║
║ 5. Use the sample Python script to test cost tracking                       ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                            IMPORTANT NOTES                                   ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ • Sample cost tracking script: /tmp/cost_tracker_${RANDOM_SUFFIX}.py        ║
║ • Budget alerts will be sent to: ${ALERT_EMAIL}                             ║
║ • Monthly budget limit: \$100 (configurable)                                ║
║ • To clean up resources, run: ./destroy.sh                                  ║
╚══════════════════════════════════════════════════════════════════════════════╝

EOF

    info "Summary generated successfully"
}

# Save deployment state
save_deployment_state() {
    local state_file="./.deployment_state"
    
    cat > "${state_file}" << EOF
# Azure AI Cost Monitoring Deployment State
# Generated on: $(date)
RESOURCE_GROUP="${RESOURCE_GROUP}"
LOCATION="${LOCATION}"
AI_HUB_NAME="${AI_HUB_NAME}"
AI_PROJECT_NAME="${AI_PROJECT_NAME}"
APP_INSIGHTS_NAME="${APP_INSIGHTS_NAME}"
LOG_ANALYTICS_NAME="${LOG_ANALYTICS_NAME}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME}"
RANDOM_SUFFIX="${RANDOM_SUFFIX}"
ALERT_EMAIL="${ALERT_EMAIL}"
DEPLOYMENT_DATE="$(date -Iseconds)"
EOF
    
    info "Deployment state saved to ${state_file}"
}

# Main execution
main() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Azure AI Cost Monitoring Deployment                      ║
║                         Foundry + Application Insights                      ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Set default values
    export LOCATION="${LOCATION:-eastus}"
    export ALERT_EMAIL="${ALERT_EMAIL:-admin@company.com}"
    
    # Generate unique suffix
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names
    export RESOURCE_GROUP="rg-ai-monitoring-${RANDOM_SUFFIX}"
    export AI_HUB_NAME="aihub-${RANDOM_SUFFIX}"
    export AI_PROJECT_NAME="aiproject-${RANDOM_SUFFIX}"
    export APP_INSIGHTS_NAME="appins-ai-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_NAME="logs-ai-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stor${RANDOM_SUFFIX}"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --email)
                ALERT_EMAIL="$2"
                shift 2
                ;;
            --force)
                FORCE_DEPLOY="true"
                shift
                ;;
            --help)
                cat << EOF
Usage: $0 [OPTIONS]

Options:
    --location LOCATION    Azure region for deployment (default: eastus)
    --email EMAIL         Email for cost alerts (default: admin@company.com)  
    --force               Force deployment even if resources exist
    --help                Show this help message

Examples:
    $0                                          # Deploy with defaults
    $0 --location westus2 --email me@corp.com  # Custom location and email
    $0 --force                                  # Force overwrite existing resources

EOF
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    validate_configuration
    check_resource_existence
    deploy_infrastructure
    save_deployment_state
    generate_summary
    
    log "Deployment script completed successfully! ✅"
}

# Execute main function
main "$@"