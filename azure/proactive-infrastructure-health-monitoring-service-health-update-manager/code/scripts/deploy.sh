#!/bin/bash

# Azure Proactive Infrastructure Health Monitoring Deployment Script
# This script deploys Azure Service Health and Azure Update Manager monitoring solution

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Default configuration
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP_PREFIX="rg-health-monitoring"
DEFAULT_ADMIN_EMAIL="admin@company.com"
DEFAULT_LOGIC_APP_WEBHOOK_URL="https://your-logic-app-url.com/trigger"

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_LOG="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false
SKIP_PREREQUISITES=false
FORCE_DEPLOY=false

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Proactive Infrastructure Health Monitoring Solution

OPTIONS:
    -l, --location LOCATION              Azure region (default: ${DEFAULT_LOCATION})
    -g, --resource-group PREFIX          Resource group prefix (default: ${DEFAULT_RESOURCE_GROUP_PREFIX})
    -e, --admin-email EMAIL              Admin email for alerts (default: ${DEFAULT_ADMIN_EMAIL})
    -w, --webhook-url URL                Logic App webhook URL (default: ${DEFAULT_LOGIC_APP_WEBHOOK_URL})
    -d, --dry-run                        Show what would be deployed without executing
    -s, --skip-prerequisites             Skip prerequisite checks
    -f, --force                          Force deployment even if resources exist
    -h, --help                           Show this help message

Examples:
    $0 --location westus2 --admin-email ops@mycompany.com
    $0 --dry-run --location eastus
    $0 --force --resource-group rg-prod-monitoring

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP_PREFIX="$2"
            shift 2
            ;;
        -e|--admin-email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        -w|--webhook-url)
            LOGIC_APP_WEBHOOK_URL="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -s|--skip-prerequisites)
            SKIP_PREREQUISITES=true
            shift
            ;;
        -f|--force)
            FORCE_DEPLOY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Set defaults if not provided
LOCATION=${LOCATION:-$DEFAULT_LOCATION}
RESOURCE_GROUP_PREFIX=${RESOURCE_GROUP_PREFIX:-$DEFAULT_RESOURCE_GROUP_PREFIX}
ADMIN_EMAIL=${ADMIN_EMAIL:-$DEFAULT_ADMIN_EMAIL}
LOGIC_APP_WEBHOOK_URL=${LOGIC_APP_WEBHOOK_URL:-$DEFAULT_LOGIC_APP_WEBHOOK_URL}

# Validate email format
validate_email() {
    local email=$1
    if [[ ! $email =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        error "Invalid email format: $email"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    if [[ "$SKIP_PREREQUISITES" == "true" ]]; then
        warn "Skipping prerequisite checks"
        return 0
    fi

    log "Checking prerequisites..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi

    # Check Azure CLI version
    local az_version=$(az --version | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    log "Azure CLI version: $az_version"

    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    # Get subscription info
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    log "Using subscription: $subscription_name ($subscription_id)"

    # Validate email format
    validate_email "$ADMIN_EMAIL"

    # Check if location is valid
    if ! az account list-locations --query "[?name=='$LOCATION']" --output tsv | grep -q "$LOCATION"; then
        error "Invalid Azure location: $LOCATION"
        exit 1
    fi

    # Check required providers
    log "Checking required Azure providers..."
    local required_providers=(
        "Microsoft.AlertsManagement"
        "Microsoft.Automation"
        "Microsoft.Insights"
        "Microsoft.Logic"
        "Microsoft.Maintenance"
        "Microsoft.OperationalInsights"
        "Microsoft.ResourceHealth"
    )

    for provider in "${required_providers[@]}"; do
        local status=$(az provider show --namespace "$provider" --query "registrationState" --output tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$status" != "Registered" ]]; then
            log "Registering provider: $provider"
            if [[ "$DRY_RUN" == "false" ]]; then
                az provider register --namespace "$provider" --wait
            fi
        fi
    done

    success "Prerequisites check completed"
}

# Generate unique suffix
generate_suffix() {
    local suffix=""
    if command -v openssl &> /dev/null; then
        suffix=$(openssl rand -hex 3)
    elif command -v head &> /dev/null && command -v /dev/urandom &> /dev/null; then
        suffix=$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)
    else
        suffix=$(date +%s | tail -c 7)
    fi
    echo "$suffix"
}

# Create resource group
create_resource_group() {
    local suffix=$(generate_suffix)
    RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX}-${suffix}"
    
    log "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return 0
    fi

    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        if [[ "$FORCE_DEPLOY" == "false" ]]; then
            error "Resource group $RESOURCE_GROUP already exists. Use --force to continue."
            exit 1
        fi
        warn "Resource group $RESOURCE_GROUP already exists. Continuing with force deployment."
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=health-monitoring environment=production deployment-script=true
        
        success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Create Log Analytics workspace
create_log_analytics() {
    local suffix=$(echo "$RESOURCE_GROUP" | grep -oE '[a-z0-9]+$')
    WORKSPACE_NAME="law-health-monitoring-${suffix}"
    
    log "Creating Log Analytics workspace: $WORKSPACE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Log Analytics workspace: $WORKSPACE_NAME"
        return 0
    fi

    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --location "$LOCATION" \
        --sku PerGB2018 \
        --retention-time 30 \
        --tags purpose=health-monitoring

    # Get workspace ID
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --query customerId --output tsv)

    success "Log Analytics workspace created: $WORKSPACE_NAME"
    log "Workspace ID: $WORKSPACE_ID"
}

# Create action group
create_action_group() {
    local suffix=$(echo "$RESOURCE_GROUP" | grep -oE '[a-z0-9]+$')
    ACTION_GROUP_NAME="ag-service-health-${suffix}"
    
    log "Creating action group: $ACTION_GROUP_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create action group: $ACTION_GROUP_NAME with email: $ADMIN_EMAIL"
        return 0
    fi

    az monitor action-group create \
        --name "$ACTION_GROUP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --short-name "SvcHealth" \
        --action email admin "$ADMIN_EMAIL" \
        --action webhook health-webhook "$LOGIC_APP_WEBHOOK_URL" \
        --tags purpose=health-monitoring

    success "Action group created: $ACTION_GROUP_NAME"
}

# Create Service Health alert rule
create_service_health_alert() {
    log "Creating Service Health alert rule"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Service Health alert rule"
        return 0
    fi

    az monitor activity-log alert create \
        --name "Service Health Issues" \
        --resource-group "$RESOURCE_GROUP" \
        --condition category=ServiceHealth \
        --action-group "$ACTION_GROUP_NAME" \
        --description "Alert for Azure Service Health incidents" \
        --enabled true

    success "Service Health alert rule created"
}

# Create Update Manager policy
create_update_manager_policy() {
    log "Creating Update Manager assessment policy"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Update Manager assessment policy"
        return 0
    fi

    local subscription_id=$(az account show --query id --output tsv)
    
    az policy assignment create \
        --name "Enable-UpdateManager-Assessment" \
        --policy "/providers/Microsoft.Authorization/policyDefinitions/59efceea-0c96-497e-a4a1-4eb2290dac15" \
        --scope "/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}" \
        --params '{
            "assessmentMode": {"value": "AutomaticByPlatform"},
            "assessmentSchedule": {"value": "Daily"}
        }' \
        --description "Enable Update Manager periodic assessment"

    success "Update Manager assessment policy created"
}

# Create maintenance configuration
create_maintenance_config() {
    local suffix=$(echo "$RESOURCE_GROUP" | grep -oE '[a-z0-9]+$')
    SCHEDULE_NAME="critical-patches-${suffix}"
    
    log "Creating maintenance configuration: $SCHEDULE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create maintenance configuration: $SCHEDULE_NAME"
        return 0
    fi

    # Calculate start date (next Monday at 2 AM)
    local start_date=$(date -d "next monday" '+%Y-%m-%d')
    
    az maintenance configuration create \
        --name "$SCHEDULE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --maintenance-scope InGuestPatch \
        --reboot-setting IfRequired \
        --start-date-time "${start_date} 02:00" \
        --duration "04:00" \
        --recur-every "1 Week" \
        --tags purpose=health-monitoring

    success "Maintenance configuration created: $SCHEDULE_NAME"
}

# Create Logic App
create_logic_app() {
    local suffix=$(echo "$RESOURCE_GROUP" | grep -oE '[a-z0-9]+$')
    LOGIC_APP_NAME="la-health-correlation-${suffix}"
    
    log "Creating Logic App: $LOGIC_APP_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Logic App: $LOGIC_APP_NAME"
        return 0
    fi

    # Create Logic App with basic workflow
    az logic workflow create \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --definition '{
            "$schema": "https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {},
            "triggers": {
                "service_health_webhook": {
                    "type": "Request",
                    "kind": "Http",
                    "inputs": {
                        "schema": {
                            "type": "object",
                            "properties": {
                                "schemaId": {"type": "string"},
                                "data": {"type": "object"}
                            }
                        }
                    }
                }
            },
            "actions": {
                "parse_service_health": {
                    "type": "ParseJson",
                    "inputs": {
                        "content": "@triggerBody()",
                        "schema": {
                            "type": "object",
                            "properties": {
                                "schemaId": {"type": "string"},
                                "data": {"type": "object"}
                            }
                        }
                    }
                }
            }
        }' \
        --tags purpose=health-monitoring

    # Get trigger URL
    TRIGGER_URL=$(az logic workflow show \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query accessEndpoint --output tsv)

    success "Logic App created: $LOGIC_APP_NAME"
    log "Trigger URL: $TRIGGER_URL"
}

# Create Azure Monitor alert rules
create_monitor_alerts() {
    log "Creating Azure Monitor alert rules"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Azure Monitor alert rules"
        return 0
    fi

    local subscription_id=$(az account show --query id --output tsv)

    # Critical patch compliance alert
    az monitor scheduled-query create \
        --name "Critical-Patch-Compliance-Alert" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}" \
        --condition "count 'UpdateSummary | where Classification == \"Critical Updates\" and Computer != \"\" and UpdateState == \"Needed\" | distinct Computer' > 0" \
        --condition-query "UpdateSummary | where Classification == 'Critical Updates' and Computer != '' and UpdateState == 'Needed' | distinct Computer" \
        --description "Alert when VMs have critical patches missing" \
        --evaluation-frequency "PT15M" \
        --window-size "PT15M" \
        --severity 2 \
        --action-groups "$ACTION_GROUP_NAME"

    # Update installation failure alert
    az monitor scheduled-query create \
        --name "Update-Installation-Failures" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}" \
        --condition "count 'UpdateRunProgress | where InstallationStatus == \"Failed\" | distinct Computer' > 0" \
        --condition-query "UpdateRunProgress | where InstallationStatus == 'Failed' | distinct Computer" \
        --description "Alert when update installations fail" \
        --evaluation-frequency "PT5M" \
        --window-size "PT5M" \
        --severity 1 \
        --action-groups "$ACTION_GROUP_NAME"

    success "Azure Monitor alert rules created"
}

# Create Automation Account
create_automation_account() {
    local suffix=$(echo "$RESOURCE_GROUP" | grep -oE '[a-z0-9]+$')
    AUTOMATION_ACCOUNT="aa-health-remediation-${suffix}"
    
    log "Creating Automation Account: $AUTOMATION_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Automation Account: $AUTOMATION_ACCOUNT"
        return 0
    fi

    az automation account create \
        --name "$AUTOMATION_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Basic \
        --tags purpose=health-monitoring

    # Create remediation runbook
    RUNBOOK_NAME="Remediate-Critical-Patches"
    az automation runbook create \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$RUNBOOK_NAME" \
        --type PowerShell \
        --description "Automated remediation for critical patch issues"

    # Create webhook
    WEBHOOK_NAME="health-remediation-webhook"
    az automation webhook create \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WEBHOOK_NAME" \
        --runbook-name "$RUNBOOK_NAME" \
        --expiry-time "2026-01-01T00:00:00Z"

    success "Automation Account created: $AUTOMATION_ACCOUNT"
}

# Create monitoring workbook
create_monitoring_workbook() {
    WORKBOOK_NAME="Health-Monitoring-Dashboard"
    
    log "Creating monitoring workbook: $WORKBOOK_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create monitoring workbook: $WORKBOOK_NAME"
        return 0
    fi

    # Create Application Insights workbook
    az monitor app-insights workbook create \
        --name "$WORKBOOK_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --display-name "Infrastructure Health Monitoring" \
        --description "Comprehensive dashboard for service health and patch compliance" \
        --category "health-monitoring" \
        --workbook-template '{
            "version": "Notebook/1.0",
            "items": [
                {
                    "type": 3,
                    "content": {
                        "version": "KqlItem/1.0",
                        "query": "ServiceHealthResources | where type == \"microsoft.resourcehealth/events\" | summarize count() by tostring(properties.eventType)",
                        "size": 0,
                        "title": "Service Health Events Summary"
                    }
                },
                {
                    "type": 3,
                    "content": {
                        "version": "KqlItem/1.0",
                        "query": "UpdateSummary | where Classification == \"Critical Updates\" | summarize count() by UpdateState",
                        "size": 0,
                        "title": "Critical Patch Compliance Status"
                    }
                }
            ]
        }' \
        --tags purpose=health-monitoring

    success "Monitoring workbook created: $WORKBOOK_NAME"
}

# Create automation effectiveness metric
create_effectiveness_metric() {
    log "Creating automation effectiveness metric"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create automation effectiveness metric"
        return 0
    fi

    local subscription_id=$(az account show --query id --output tsv)

    az monitor metrics alert create \
        --name "Automation-Effectiveness-Metric" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}" \
        --condition "avg customMetrics/AutomationSuccessRate < 90" \
        --description "Alert when automation success rate drops below 90%" \
        --evaluation-frequency "PT5M" \
        --window-size "PT15M" \
        --severity 3 \
        --action-groups "$ACTION_GROUP_NAME"

    success "Automation effectiveness monitoring configured"
}

# Save deployment configuration
save_deployment_config() {
    local config_file="${SCRIPT_DIR}/deployment-config.json"
    
    log "Saving deployment configuration to: $config_file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would save deployment configuration"
        return 0
    fi

    cat > "$config_file" << EOF
{
    "deployment_time": "$(date -Iseconds)",
    "resource_group": "$RESOURCE_GROUP",
    "location": "$LOCATION",
    "admin_email": "$ADMIN_EMAIL",
    "workspace_name": "$WORKSPACE_NAME",
    "workspace_id": "$WORKSPACE_ID",
    "action_group_name": "$ACTION_GROUP_NAME",
    "logic_app_name": "$LOGIC_APP_NAME",
    "trigger_url": "$TRIGGER_URL",
    "automation_account": "$AUTOMATION_ACCOUNT",
    "schedule_name": "$SCHEDULE_NAME",
    "runbook_name": "$RUNBOOK_NAME",
    "webhook_name": "$WEBHOOK_NAME",
    "workbook_name": "$WORKBOOK_NAME"
}
EOF

    success "Deployment configuration saved"
}

# Main deployment function
main() {
    log "Starting Azure Proactive Infrastructure Health Monitoring deployment"
    log "Location: $LOCATION"
    log "Resource Group Prefix: $RESOURCE_GROUP_PREFIX"
    log "Admin Email: $ADMIN_EMAIL"
    log "Dry Run: $DRY_RUN"
    
    # Start logging
    exec 1> >(tee -a "$DEPLOY_LOG")
    exec 2> >(tee -a "$DEPLOY_LOG" >&2)
    
    # Check prerequisites
    check_prerequisites
    
    # Create resources
    create_resource_group
    create_log_analytics
    create_action_group
    create_service_health_alert
    create_update_manager_policy
    create_maintenance_config
    create_logic_app
    create_monitor_alerts
    create_automation_account
    create_monitoring_workbook
    create_effectiveness_metric
    
    # Save configuration
    save_deployment_config
    
    if [[ "$DRY_RUN" == "false" ]]; then
        success "Deployment completed successfully!"
        log "Resource Group: $RESOURCE_GROUP"
        log "Log Analytics Workspace: $WORKSPACE_NAME"
        log "Action Group: $ACTION_GROUP_NAME"
        log "Logic App: $LOGIC_APP_NAME"
        log "Automation Account: $AUTOMATION_ACCOUNT"
        log "Deployment log saved to: $DEPLOY_LOG"
        log "Configuration saved to: ${SCRIPT_DIR}/deployment-config.json"
    else
        success "Dry run completed. No resources were created."
    fi
}

# Trap to handle cleanup on script exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Deployment failed with exit code $exit_code"
        log "Check the deployment log for details: $DEPLOY_LOG"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Run main function
main "$@"