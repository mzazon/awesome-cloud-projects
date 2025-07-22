#!/bin/bash

# Azure Chaos Studio and Application Insights Deployment Script
# Implements resilience testing with chaos engineering and monitoring
# Version: 1.0

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly TEMP_DIR=$(mktemp -d)

# Cleanup temp directory on exit
trap 'rm -rf "${TEMP_DIR}"' EXIT

# Logging functions
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    exit 1
}

# Prerequisite checks
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az >/dev/null 2>&1; then
        error_exit "Azure CLI is not installed. Please install Azure CLI first."
    fi
    
    # Check Azure CLI version
    local az_version=$(az --version | head -n1 | awk '{print $2}')
    log_info "Azure CLI version: ${az_version}"
    
    # Check if logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl >/dev/null 2>&1; then
        error_exit "OpenSSL is not installed. Required for generating random strings."
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables with defaults
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Allow override via environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-chaos-testing-$(openssl rand -hex 3)}"
    export LOCATION="${LOCATION:-eastus}"
    export VM_NAME="${VM_NAME:-vm-target-$(openssl rand -hex 3)}"
    export APP_INSIGHTS_NAME="${APP_INSIGHTS_NAME:-appi-chaos-$(openssl rand -hex 3)}"
    export WORKSPACE_NAME="${WORKSPACE_NAME:-log-chaos-$(openssl rand -hex 3)}"
    export IDENTITY_NAME="${IDENTITY_NAME:-id-chaos-$(openssl rand -hex 3)}"
    
    # Save variables to file for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
VM_NAME=${VM_NAME}
APP_INSIGHTS_NAME=${APP_INSIGHTS_NAME}
WORKSPACE_NAME=${WORKSPACE_NAME}
IDENTITY_NAME=${IDENTITY_NAME}
EOF
    
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "VM Name: ${VM_NAME}"
    log_info "Application Insights: ${APP_INSIGHTS_NAME}"
    log_info "Log Analytics Workspace: ${WORKSPACE_NAME}"
    log_info "Managed Identity: ${IDENTITY_NAME}"
    
    log_success "Environment variables configured"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=chaos-testing environment=demo \
            --output table
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Create Log Analytics workspace
create_log_analytics_workspace() {
    log_info "Creating Log Analytics workspace: ${WORKSPACE_NAME}"
    
    if az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${WORKSPACE_NAME}" >/dev/null 2>&1; then
        log_warning "Log Analytics workspace ${WORKSPACE_NAME} already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${WORKSPACE_NAME}" \
            --location "${LOCATION}" \
            --output table
        
        log_success "Log Analytics workspace created: ${WORKSPACE_NAME}"
    fi
    
    # Get workspace ID and save for later use
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${WORKSPACE_NAME}" \
        --query id --output tsv)
    
    echo "WORKSPACE_ID=${WORKSPACE_ID}" >> "${SCRIPT_DIR}/.env"
    log_info "Workspace ID: ${WORKSPACE_ID}"
}

# Create Application Insights
create_application_insights() {
    log_info "Creating Application Insights: ${APP_INSIGHTS_NAME}"
    
    if az monitor app-insights component show \
        --app "${APP_INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Application Insights ${APP_INSIGHTS_NAME} already exists"
    else
        az monitor app-insights component create \
            --app "${APP_INSIGHTS_NAME}" \
            --location "${LOCATION}" \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace "${WORKSPACE_ID}" \
            --application-type web \
            --output table
        
        log_success "Application Insights created: ${APP_INSIGHTS_NAME}"
    fi
    
    # Get instrumentation key
    INSTRUMENTATION_KEY=$(az monitor app-insights component show \
        --app "${APP_INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query instrumentationKey --output tsv)
    
    echo "INSTRUMENTATION_KEY=${INSTRUMENTATION_KEY}" >> "${SCRIPT_DIR}/.env"
    log_info "Application Insights instrumentation key retrieved"
}

# Create virtual machine
create_virtual_machine() {
    log_info "Creating virtual machine: ${VM_NAME}"
    
    if az vm show --name "${VM_NAME}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Virtual machine ${VM_NAME} already exists"
    else
        az vm create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${VM_NAME}" \
            --image Ubuntu2204 \
            --size Standard_B2s \
            --admin-username azureuser \
            --generate-ssh-keys \
            --public-ip-sku Standard \
            --output table
        
        # Wait for VM to be fully provisioned
        log_info "Waiting for VM to be fully provisioned..."
        az vm wait --created --resource-group "${RESOURCE_GROUP}" --name "${VM_NAME}"
        
        log_success "Virtual machine created: ${VM_NAME}"
    fi
    
    # Get VM resource ID
    VM_RESOURCE_ID=$(az vm show \
        --name "${VM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    echo "VM_RESOURCE_ID=${VM_RESOURCE_ID}" >> "${SCRIPT_DIR}/.env"
    log_info "VM Resource ID: ${VM_RESOURCE_ID}"
}

# Create managed identity
create_managed_identity() {
    log_info "Creating managed identity: ${IDENTITY_NAME}"
    
    if az identity show \
        --name "${IDENTITY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Managed identity ${IDENTITY_NAME} already exists"
    else
        az identity create \
            --name "${IDENTITY_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --output table
        
        log_success "Managed identity created: ${IDENTITY_NAME}"
    fi
    
    # Get identity details
    IDENTITY_ID=$(az identity show \
        --name "${IDENTITY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    IDENTITY_PRINCIPAL_ID=$(az identity show \
        --name "${IDENTITY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query principalId --output tsv)
    
    echo "IDENTITY_ID=${IDENTITY_ID}" >> "${SCRIPT_DIR}/.env"
    echo "IDENTITY_PRINCIPAL_ID=${IDENTITY_PRINCIPAL_ID}" >> "${SCRIPT_DIR}/.env"
    
    log_info "Identity ID: ${IDENTITY_ID}"
    log_info "Identity Principal ID: ${IDENTITY_PRINCIPAL_ID}"
}

# Register and enable Chaos Studio
enable_chaos_studio() {
    log_info "Enabling Chaos Studio on target resources..."
    
    # Register Chaos Studio resource provider
    log_info "Registering Microsoft.Chaos resource provider..."
    az provider register --namespace Microsoft.Chaos --output table
    
    # Wait for registration to complete
    log_info "Waiting for provider registration to complete..."
    while [ "$(az provider show --namespace Microsoft.Chaos --query registrationState --output tsv)" != "Registered" ]; do
        log_info "Provider registration in progress..."
        sleep 10
    done
    
    log_success "Microsoft.Chaos provider registered"
    
    # Enable VM as chaos target
    log_info "Enabling VM as chaos target..."
    
    local target_url="https://management.azure.com${VM_RESOURCE_ID}/providers/Microsoft.Chaos/targets/Microsoft-VirtualMachine?api-version=2024-01-01"
    
    az rest --method put \
        --url "${target_url}" \
        --body '{"properties":{}}' \
        --output table
    
    log_success "Chaos Studio enabled on virtual machine"
}

# Install Chaos Agent
install_chaos_agent() {
    log_info "Installing Chaos Agent with Application Insights integration..."
    
    # Check if extension is already installed
    if az vm extension show \
        --resource-group "${RESOURCE_GROUP}" \
        --vm-name "${VM_NAME}" \
        --name ChaosAgent >/dev/null 2>&1; then
        log_warning "Chaos Agent already installed on ${VM_NAME}"
    else
        # Create settings JSON for the extension
        cat > "${TEMP_DIR}/chaos-agent-settings.json" << EOF
{
    "profile": "Node",
    "auth": {
        "msi": {
            "clientId": "${IDENTITY_PRINCIPAL_ID}"
        }
    },
    "appInsightsSettings": {
        "isEnabled": true,
        "instrumentationKey": "${INSTRUMENTATION_KEY}",
        "logLevel": "Information"
    }
}
EOF
        
        az vm extension set \
            --resource-group "${RESOURCE_GROUP}" \
            --vm-name "${VM_NAME}" \
            --name ChaosAgent \
            --publisher Microsoft.Azure.Chaos \
            --version 1.0 \
            --settings @"${TEMP_DIR}/chaos-agent-settings.json" \
            --output table
        
        log_success "Chaos Agent installed with Application Insights integration"
    fi
    
    # Verify agent installation
    local agent_status=$(az vm extension show \
        --resource-group "${RESOURCE_GROUP}" \
        --vm-name "${VM_NAME}" \
        --name ChaosAgent \
        --query provisioningState --output tsv)
    
    if [ "${agent_status}" = "Succeeded" ]; then
        log_success "Chaos Agent installation verified"
    else
        log_warning "Chaos Agent status: ${agent_status}"
    fi
}

# Create chaos experiment
create_chaos_experiment() {
    log_info "Creating chaos experiment..."
    
    EXPERIMENT_NAME="exp-vm-shutdown-$(openssl rand -hex 3)"
    echo "EXPERIMENT_NAME=${EXPERIMENT_NAME}" >> "${SCRIPT_DIR}/.env"
    
    # Create experiment definition
    cat > "${TEMP_DIR}/experiment.json" << EOF
{
    "location": "${LOCATION}",
    "identity": {
        "type": "UserAssigned",
        "userAssignedIdentities": {
            "${IDENTITY_ID}": {}
        }
    },
    "properties": {
        "steps": [
            {
                "name": "Step 1",
                "branches": [
                    {
                        "name": "Branch 1",
                        "actions": [
                            {
                                "type": "continuous",
                                "name": "VM Shutdown",
                                "selectorId": "Selector1",
                                "duration": "PT5M",
                                "parameters": [
                                    {
                                        "key": "abruptShutdown",
                                        "value": "true"
                                    }
                                ]
                            }
                        ]
                    }
                ]
            }
        ],
        "selectors": [
            {
                "id": "Selector1",
                "type": "List",
                "targets": [
                    {
                        "type": "ChaosTarget",
                        "id": "${VM_RESOURCE_ID}/providers/Microsoft.Chaos/targets/Microsoft-VirtualMachine"
                    }
                ]
            }
        ]
    }
}
EOF
    
    # Create the experiment
    local subscription_id=$(az account show --query id -o tsv)
    local experiment_url="https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Chaos/experiments/${EXPERIMENT_NAME}?api-version=2024-01-01"
    
    az rest --method put \
        --url "${experiment_url}" \
        --body @"${TEMP_DIR}/experiment.json" \
        --output table
    
    log_success "Chaos experiment created: ${EXPERIMENT_NAME}"
}

# Grant permissions for experiment
grant_experiment_permissions() {
    log_info "Granting permissions for experiment execution..."
    
    # Get experiment principal ID
    local subscription_id=$(az account show --query id -o tsv)
    local experiment_url="https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Chaos/experiments/${EXPERIMENT_NAME}?api-version=2024-01-01"
    
    EXPERIMENT_PRINCIPAL_ID=$(az rest --method get \
        --url "${experiment_url}" \
        --query identity.principalId --output tsv)
    
    if [ -n "${EXPERIMENT_PRINCIPAL_ID}" ] && [ "${EXPERIMENT_PRINCIPAL_ID}" != "null" ]; then
        # Assign Virtual Machine Contributor role
        az role assignment create \
            --assignee "${EXPERIMENT_PRINCIPAL_ID}" \
            --role "Virtual Machine Contributor" \
            --scope "${VM_RESOURCE_ID}" \
            --output table
        
        echo "EXPERIMENT_PRINCIPAL_ID=${EXPERIMENT_PRINCIPAL_ID}" >> "${SCRIPT_DIR}/.env"
        log_success "Permissions granted to chaos experiment"
    else
        log_warning "Could not retrieve experiment principal ID. May need manual role assignment."
    fi
}

# Configure alerts
configure_alerts() {
    log_info "Configuring Application Insights alerts..."
    
    # Create action group for notifications
    ACTION_GROUP_NAME="ag-chaos-alerts"
    echo "ACTION_GROUP_NAME=${ACTION_GROUP_NAME}" >> "${SCRIPT_DIR}/.env"
    
    if az monitor action-group show \
        --name "${ACTION_GROUP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Action group ${ACTION_GROUP_NAME} already exists"
    else
        az monitor action-group create \
            --name "${ACTION_GROUP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --short-name ChaosAlert \
            --output table
        
        log_success "Action group created: ${ACTION_GROUP_NAME}"
    fi
    
    # Create alert rule for chaos events
    ALERT_RULE_NAME="Chaos Experiment Active"
    
    if az monitor metrics alert show \
        --name "${ALERT_RULE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Alert rule '${ALERT_RULE_NAME}' already exists"
    else
        az monitor metrics alert create \
            --name "${ALERT_RULE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --scopes "${VM_RESOURCE_ID}" \
            --condition "avg Percentage CPU > 80" \
            --window-size 5m \
            --evaluation-frequency 1m \
            --action "${ACTION_GROUP_NAME}" \
            --description "Alert when chaos experiment affects VM performance" \
            --output table
        
        log_success "Alert rule created: ${ALERT_RULE_NAME}"
    fi
}

# Display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "========================== DEPLOYMENT SUMMARY =========================="
    echo "Resource Group:          ${RESOURCE_GROUP}"
    echo "Location:               ${LOCATION}"
    echo "Virtual Machine:        ${VM_NAME}"
    echo "Application Insights:   ${APP_INSIGHTS_NAME}"
    echo "Log Analytics:          ${WORKSPACE_NAME}"
    echo "Managed Identity:       ${IDENTITY_NAME}"
    echo "Chaos Experiment:       ${EXPERIMENT_NAME}"
    echo "Action Group:           ${ACTION_GROUP_NAME}"
    echo ""
    echo "Next Steps:"
    echo "1. Run validation tests using the validation commands from the recipe"
    echo "2. Start chaos experiments to test resilience"
    echo "3. Monitor results in Application Insights"
    echo "4. Run cleanup script when testing is complete"
    echo ""
    echo "Configuration saved to: ${SCRIPT_DIR}/.env"
    echo "Deployment log: ${LOG_FILE}"
    echo "======================================================================"
}

# Main deployment function
main() {
    local start_time=$(date +%s)
    
    log_info "Starting Azure Chaos Studio and Application Insights deployment..."
    log_info "Script directory: ${SCRIPT_DIR}"
    log_info "Log file: ${LOG_FILE}"
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_log_analytics_workspace
    create_application_insights
    create_virtual_machine
    create_managed_identity
    enable_chaos_studio
    install_chaos_agent
    create_chaos_experiment
    grant_experiment_permissions
    configure_alerts
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    display_summary
    log_success "Deployment completed in ${duration} seconds"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi