#!/bin/bash

# deploy.sh - Azure Proactive Application Health Monitoring Deployment Script
# This script deploys the complete health monitoring solution with Azure Resource Health and Service Bus
# Recipe: Proactive Resource Health Monitoring with Service Bus

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
START_TIME=$(date)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message function
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    info "Azure CLI version: ${az_version}"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if jq is installed for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some advanced JSON processing may be limited."
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is required for generating random strings. Please install it."
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    info "Setting up environment variables..."
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-health-monitoring-$(openssl rand -hex 3)"
    export LOCATION="eastus"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Service Bus configuration
    export SERVICE_BUS_NAMESPACE="sb-health-monitoring-${RANDOM_SUFFIX}"
    export HEALTH_QUEUE_NAME="health-events"
    export REMEDIATION_TOPIC_NAME="remediation-actions"
    
    # Logic Apps configuration
    export LOGIC_APP_NAME="la-health-orchestrator-${RANDOM_SUFFIX}"
    export CONSUMPTION_PLAN_NAME="plan-health-monitoring-${RANDOM_SUFFIX}"
    
    # Monitoring configuration
    export LOG_ANALYTICS_WORKSPACE="log-health-monitoring-${RANDOM_SUFFIX}"
    export ACTION_GROUP_NAME="ag-health-alerts-${RANDOM_SUFFIX}"
    
    # Additional variables for script execution
    export VM_NAME="vm-health-demo-${RANDOM_SUFFIX}"
    export RESTART_HANDLER_NAME="la-restart-handler-${RANDOM_SUFFIX}"
    
    info "Environment variables configured:"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  Location: ${LOCATION}"
    info "  Service Bus Namespace: ${SERVICE_BUS_NAMESPACE}"
    info "  Logic App: ${LOGIC_APP_NAME}"
}

# Function to create resource group
create_resource_group() {
    info "Creating resource group..."
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=health-monitoring environment=demo \
        --output none || error_exit "Failed to create resource group"
    
    success "Resource group created: ${RESOURCE_GROUP}"
}

# Function to create Service Bus namespace and messaging topology
create_service_bus() {
    info "Creating Service Bus infrastructure..."
    
    # Create Service Bus namespace
    az servicebus namespace create \
        --name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard \
        --tags purpose=health-monitoring \
        --output none || error_exit "Failed to create Service Bus namespace"
    
    # Wait for namespace to be ready
    info "Waiting for Service Bus namespace to be ready..."
    sleep 30
    
    # Get Service Bus connection string
    export SERVICE_BUS_CONNECTION=$(az servicebus namespace \
        authorization-rule keys list \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString --output tsv) || error_exit "Failed to get Service Bus connection string"
    
    # Create health events queue
    az servicebus queue create \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${HEALTH_QUEUE_NAME}" \
        --max-size 2048 \
        --enable-duplicate-detection true \
        --duplicate-detection-history-time-window PT10M \
        --output none || error_exit "Failed to create health events queue"
    
    # Create remediation topic
    az servicebus topic create \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${REMEDIATION_TOPIC_NAME}" \
        --max-size 2048 \
        --enable-duplicate-detection true \
        --output none || error_exit "Failed to create remediation topic"
    
    # Create subscriptions for remediation handlers
    az servicebus topic subscription create \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --topic-name "${REMEDIATION_TOPIC_NAME}" \
        --name auto-scale-handler \
        --max-delivery-count 3 \
        --output none || error_exit "Failed to create auto-scale subscription"
    
    az servicebus topic subscription create \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --topic-name "${REMEDIATION_TOPIC_NAME}" \
        --name restart-handler \
        --max-delivery-count 3 \
        --output none || error_exit "Failed to create restart subscription"
    
    success "Service Bus infrastructure created successfully"
}

# Function to create Log Analytics workspace
create_log_analytics() {
    info "Creating Log Analytics workspace..."
    
    az monitor log-analytics workspace create \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=health-monitoring \
        --output none || error_exit "Failed to create Log Analytics workspace"
    
    # Get workspace ID
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query customerId --output tsv) || error_exit "Failed to get workspace ID"
    
    success "Log Analytics workspace created: ${LOG_ANALYTICS_WORKSPACE}"
}

# Function to create main Logic Apps workflow
create_main_logic_app() {
    info "Creating main Logic Apps workflow..."
    
    # Create the workflow definition as a temporary file
    cat > "/tmp/main-workflow.json" << EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json",
  "contentVersion": "1.0.0.0",
  "triggers": {
    "When_a_resource_health_alert_is_fired": {
      "type": "request",
      "kind": "http",
      "inputs": {
        "schema": {
          "type": "object",
          "properties": {
            "resourceId": {"type": "string"},
            "status": {"type": "string"},
            "eventTime": {"type": "string"},
            "resourceType": {"type": "string"}
          }
        }
      }
    }
  },
  "actions": {
    "Send_to_Health_Queue": {
      "type": "Http",
      "inputs": {
        "method": "POST",
        "uri": "https://httpbin.org/post",
        "body": {
          "action": "log_health_event",
          "data": "@triggerBody()",
          "timestamp": "@utcnow()"
        }
      }
    },
    "Determine_Remediation_Action": {
      "type": "Switch",
      "expression": "@triggerBody()['status']",
      "cases": {
        "Unavailable": {
          "case": "Unavailable",
          "actions": {
            "Send_Restart_Action": {
              "type": "Http",
              "inputs": {
                "method": "POST",
                "uri": "https://httpbin.org/post",
                "body": {
                  "action": "restart",
                  "resourceId": "@triggerBody()['resourceId']",
                  "timestamp": "@utcnow()"
                }
              }
            }
          }
        },
        "Degraded": {
          "case": "Degraded",
          "actions": {
            "Send_Scale_Action": {
              "type": "Http",
              "inputs": {
                "method": "POST",
                "uri": "https://httpbin.org/post",
                "body": {
                  "action": "scale",
                  "resourceId": "@triggerBody()['resourceId']",
                  "timestamp": "@utcnow()"
                }
              }
            }
          }
        }
      }
    }
  }
}
EOF
    
    # Create Logic App with the workflow definition
    az logic workflow create \
        --name "${LOGIC_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --definition @/tmp/main-workflow.json \
        --output none || error_exit "Failed to create main Logic App workflow"
    
    # Clean up temporary file
    rm -f /tmp/main-workflow.json
    
    success "Main Logic Apps workflow created: ${LOGIC_APP_NAME}"
}

# Function to create Action Group
create_action_group() {
    info "Creating Action Group for health alerts..."
    
    # Get Logic App trigger URL
    local logic_app_url=$(az logic workflow show \
        --name "${LOGIC_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "accessEndpoint" --output tsv) || error_exit "Failed to get Logic App URL"
    
    # Create Action Group with webhook
    az monitor action-group create \
        --name "${ACTION_GROUP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --short-name "HealthAlert" \
        --action webhook healthWebhook "${logic_app_url}" \
        --output none || error_exit "Failed to create Action Group"
    
    success "Action Group created: ${ACTION_GROUP_NAME}"
}

# Function to create demo VM and health alert
create_demo_vm_and_alert() {
    info "Creating demo VM for health monitoring..."
    
    # Create VM
    az vm create \
        --name "${VM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --image Ubuntu2204 \
        --admin-username azureuser \
        --generate-ssh-keys \
        --size Standard_B1s \
        --tags purpose=health-monitoring-demo \
        --output none || error_exit "Failed to create demo VM"
    
    # Get VM resource ID
    local vm_resource_id=$(az vm show \
        --name "${VM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv) || error_exit "Failed to get VM resource ID"
    
    # Create Resource Health alert for the VM
    az monitor activity-log alert create \
        --name "vm-health-alert-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --scopes "${vm_resource_id}" \
        --condition category=ResourceHealth \
        --action-groups "${ACTION_GROUP_NAME}" \
        --description "Alert when VM health status changes" \
        --output none || error_exit "Failed to create Resource Health alert"
    
    success "Demo VM and health alert created successfully"
}

# Function to create restart handler Logic App
create_restart_handler() {
    info "Creating restart handler Logic App..."
    
    # Create the restart handler workflow definition
    cat > "/tmp/restart-workflow.json" << EOF
{
  "\$schema": "https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json",
  "contentVersion": "1.0.0.0",
  "triggers": {
    "When_a_restart_message_is_received": {
      "type": "request",
      "kind": "http",
      "inputs": {
        "schema": {
          "type": "object",
          "properties": {
            "resourceId": {"type": "string"},
            "action": {"type": "string"}
          }
        }
      }
    }
  },
  "actions": {
    "Log_Restart_Action": {
      "type": "Http",
      "inputs": {
        "method": "POST",
        "uri": "https://httpbin.org/post",
        "body": {
          "action": "restart",
          "resourceId": "@triggerBody()['resourceId']",
          "timestamp": "@utcnow()",
          "status": "processing"
        }
      }
    }
  }
}
EOF
    
    # Create restart handler Logic App
    az logic workflow create \
        --name "${RESTART_HANDLER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --definition @/tmp/restart-workflow.json \
        --output none || error_exit "Failed to create restart handler Logic App"
    
    # Clean up temporary file
    rm -f /tmp/restart-workflow.json
    
    success "Restart handler Logic App created: ${RESTART_HANDLER_NAME}"
}

# Function to create monitoring queries
create_monitoring_queries() {
    info "Creating monitoring queries..."
    
    # Create monitoring queries file
    cat > "${SCRIPT_DIR}/health_monitoring_queries.kql" << 'EOF'
// Health Events Analysis
AzureActivity
| where CategoryValue == "ResourceHealth"
| summarize count() by ResourceId, Status, bin(TimeGenerated, 1h)
| order by TimeGenerated desc

// Remediation Actions Tracking
AzureActivity
| where OperationNameValue contains "Logic"
| where ResourceProvider == "Microsoft.Logic"
| summarize count() by bin(TimeGenerated, 1h), OperationNameValue
| order by TimeGenerated desc

// Service Bus Message Processing
ServiceBusLogs
| where Category == "OperationalLogs"
| summarize count() by bin(TimeGenerated, 15m), Status
| order by TimeGenerated desc
EOF
    
    success "Monitoring queries created: ${SCRIPT_DIR}/health_monitoring_queries.kql"
}

# Function to validate deployment
validate_deployment() {
    info "Validating deployment..."
    
    # Check resource group
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        error_exit "Resource group validation failed"
    fi
    
    # Check Service Bus namespace
    local sb_status=$(az servicebus namespace show \
        --name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query status --output tsv 2>/dev/null || echo "NotFound")
    
    if [[ "${sb_status}" != "Active" ]]; then
        error_exit "Service Bus namespace is not active: ${sb_status}"
    fi
    
    # Check Logic Apps
    local la_status=$(az logic workflow show \
        --name "${LOGIC_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query state --output tsv 2>/dev/null || echo "NotFound")
    
    if [[ "${la_status}" != "Enabled" ]]; then
        warning "Logic App may not be enabled: ${la_status}"
    fi
    
    # Check VM
    local vm_status=$(az vm get-instance-view \
        --name "${VM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query instanceView.statuses[1].displayStatus \
        --output tsv 2>/dev/null || echo "NotFound")
    
    if [[ "${vm_status}" == *"running"* ]]; then
        success "VM is running: ${vm_status}"
    else
        warning "VM status: ${vm_status}"
    fi
    
    success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    info "Deployment Summary"
    echo "=================================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Service Bus Namespace: ${SERVICE_BUS_NAMESPACE}"
    echo "Health Queue: ${HEALTH_QUEUE_NAME}"
    echo "Remediation Topic: ${REMEDIATION_TOPIC_NAME}"
    echo "Main Logic App: ${LOGIC_APP_NAME}"
    echo "Restart Handler: ${RESTART_HANDLER_NAME}"
    echo "Log Analytics: ${LOG_ANALYTICS_WORKSPACE}"
    echo "Action Group: ${ACTION_GROUP_NAME}"
    echo "Demo VM: ${VM_NAME}"
    echo "=================================="
    echo ""
    
    # Get Logic App trigger URL for testing
    local trigger_url=$(az logic workflow show \
        --name "${LOGIC_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "accessEndpoint" --output tsv 2>/dev/null || echo "Unable to retrieve")
    
    echo "Testing Information:"
    echo "Logic App Trigger URL: ${trigger_url}"
    echo ""
    echo "To test the health monitoring system, you can send a POST request to the Logic App trigger URL:"
    echo "curl -X POST '${trigger_url}' \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -d '{"
    echo "    \"resourceId\": \"/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachines/${VM_NAME}\","
    echo "    \"status\": \"Unavailable\","
    echo "    \"eventTime\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\","
    echo "    \"resourceType\": \"Microsoft.Compute/virtualMachines\""
    echo "  }'"
    echo ""
    echo "Deployment completed at: $(date)"
    echo "Total deployment time: $(($(date +%s) - $(date -d "${START_TIME}" +%s))) seconds"
}

# Main deployment function
main() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "  Azure Health Monitoring Deployment Script"
    echo "=================================================="
    echo -e "${NC}"
    
    log "Starting deployment process"
    
    # Execute deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_service_bus
    create_log_analytics
    create_main_logic_app
    create_action_group
    create_demo_vm_and_alert
    create_restart_handler
    create_monitoring_queries
    validate_deployment
    display_summary
    
    success "🎉 Deployment completed successfully!"
    info "Check the deployment log for details: ${LOG_FILE}"
}

# Trap signals for cleanup
trap 'echo -e "${RED}Deployment interrupted${NC}"; exit 1' INT TERM

# Execute main function
main "$@"