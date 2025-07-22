#!/bin/bash

# =============================================================================
# Azure Unified Security Operations Deployment Script
# =============================================================================
# This script deploys automated security incident response infrastructure
# using Azure Unified Operations and Azure Monitor Workbooks
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# Configuration and Variables
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging configuration
LOG_DIR="./logs"
LOG_FILE="${LOG_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "${LOG_DIR}"

# Default configuration
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP_PREFIX="rg-security-ops"
DEFAULT_WORKSPACE_PREFIX="law-security"
DEFAULT_SENTINEL_PREFIX="sentinel"
DEFAULT_LOGIC_APP_PREFIX="la-incident-response"

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "$*"
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    log "SUCCESS" "$*"
    echo -e "${GREEN}✅${NC} $*"
}

log_warning() {
    log "WARNING" "$*"
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    log "ERROR" "$*"
    echo -e "${RED}❌${NC} $*"
}

# =============================================================================
# Utility Functions
# =============================================================================

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Unified Security Operations infrastructure.

OPTIONS:
    -h, --help                    Show this help message
    -l, --location LOCATION       Azure region (default: ${DEFAULT_LOCATION})
    -g, --resource-group NAME     Resource group name (default: auto-generated)
    -w, --workspace NAME          Log Analytics workspace name (default: auto-generated)
    -s, --sentinel NAME           Sentinel instance name (default: auto-generated)
    -a, --logic-app NAME          Logic App name (default: auto-generated)
    -d, --dry-run                 Show what would be deployed without executing
    -v, --verbose                 Enable verbose logging
    --skip-prereqs               Skip prerequisite checks
    --force                      Force deployment even if resources exist

EXAMPLES:
    $0                           # Deploy with default settings
    $0 -l westus2 -g my-rg      # Deploy to specific region and resource group
    $0 --dry-run                 # Show deployment plan without executing
    $0 --verbose                 # Enable detailed logging

EOF
}

generate_random_suffix() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 3
    elif command -v od >/dev/null 2>&1; then
        od -An -tx1 -N3 /dev/urandom | tr -d ' \n' | head -c 6
    else
        echo $(( RANDOM % 1000000 )) | printf "%06d\n" | head -c 6
    fi
}

check_command() {
    local cmd=$1
    local package=${2:-$cmd}
    
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command '$cmd' not found. Please install $package."
        exit 1
    fi
}

wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local resource_group=$3
    local timeout=${4:-300}
    local interval=${5:-10}
    
    log_info "Waiting for $resource_type '$resource_name' to be ready..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if az "$resource_type" show \
            --name "$resource_name" \
            --resource-group "$resource_group" \
            --query "provisioningState" \
            --output tsv 2>/dev/null | grep -q "Succeeded"; then
            log_success "$resource_type '$resource_name' is ready"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        log_info "Still waiting... ($elapsed/${timeout}s)"
    done
    
    log_error "Timeout waiting for $resource_type '$resource_name'"
    return 1
}

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required commands
    check_command "az" "azure-cli"
    check_command "jq" "jq"
    
    # Check Azure CLI login
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged into Azure CLI. Please run 'az login'"
        exit 1
    fi
    
    # Get subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    TENANT_ID=$(az account show --query tenantId --output tsv)
    
    log_info "Using subscription: $SUBSCRIPTION_ID"
    log_info "Using tenant: $TENANT_ID"
    
    # Check required Azure providers
    local required_providers=(
        "Microsoft.SecurityInsights"
        "Microsoft.Logic"
        "Microsoft.OperationalInsights"
        "Microsoft.Insights"
    )
    
    for provider in "${required_providers[@]}"; do
        log_info "Checking provider registration: $provider"
        if ! az provider show --namespace "$provider" --query "registrationState" --output tsv | grep -q "Registered"; then
            log_info "Registering provider: $provider"
            az provider register --namespace "$provider"
        fi
    done
    
    # Check permissions
    log_info "Checking permissions..."
    local user_roles=$(az role assignment list --assignee $(az account show --query user.name --output tsv) --query "[].roleDefinitionName" --output tsv)
    
    if echo "$user_roles" | grep -qE "(Owner|Security Admin|Contributor)"; then
        log_success "Sufficient permissions detected"
    else
        log_warning "Limited permissions detected. Deployment may fail."
    fi
    
    log_success "Prerequisites check completed"
}

# =============================================================================
# Resource Deployment Functions
# =============================================================================

create_resource_group() {
    local rg_name=$1
    local location=$2
    
    log_info "Creating resource group: $rg_name"
    
    if az group show --name "$rg_name" >/dev/null 2>&1; then
        if [ "$FORCE_DEPLOY" = "true" ]; then
            log_warning "Resource group exists, continuing with force flag"
        else
            log_error "Resource group '$rg_name' already exists. Use --force to continue."
            exit 1
        fi
    else
        az group create \
            --name "$rg_name" \
            --location "$location" \
            --tags "purpose=security-operations" "environment=production" "deployment-method=script"
        
        log_success "Resource group created: $rg_name"
    fi
}

create_log_analytics_workspace() {
    local workspace_name=$1
    local resource_group=$2
    local location=$3
    
    log_info "Creating Log Analytics workspace: $workspace_name"
    
    az monitor log-analytics workspace create \
        --resource-group "$resource_group" \
        --workspace-name "$workspace_name" \
        --location "$location" \
        --sku "pergb2018" \
        --retention-time 90 \
        --tags "component=security-workspace" "data-retention=90-days"
    
    # Wait for workspace to be ready
    wait_for_resource "monitor log-analytics workspace" "$workspace_name" "$resource_group"
    
    # Get workspace ID
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$resource_group" \
        --workspace-name "$workspace_name" \
        --query id --output tsv)
    
    log_success "Log Analytics workspace created with ID: $WORKSPACE_ID"
}

enable_sentinel() {
    local workspace_name=$1
    local resource_group=$2
    
    log_info "Enabling Microsoft Sentinel on workspace: $workspace_name"
    
    # Enable Sentinel
    az sentinel workspace create \
        --resource-group "$resource_group" \
        --workspace-name "$workspace_name"
    
    # Configure UEBA settings
    log_info "Configuring User and Entity Behavior Analytics (UEBA)..."
    
    az rest \
        --method PUT \
        --uri "https://management.azure.com${WORKSPACE_ID}/providers/Microsoft.SecurityInsights/settings/Ueba?api-version=2021-10-01-preview" \
        --body '{
            "kind": "Ueba",
            "properties": {
                "dataSources": ["AuditLogs", "AzureActivity", "SecurityEvent", "SigninLogs"]
            }
        }'
    
    log_success "Microsoft Sentinel enabled with UEBA analytics"
}

configure_data_connectors() {
    local workspace_id=$1
    local random_suffix=$2
    
    log_info "Configuring data connectors..."
    
    # Azure AD connector
    log_info "Enabling Azure AD connector..."
    az rest \
        --method PUT \
        --uri "https://management.azure.com${workspace_id}/providers/Microsoft.SecurityInsights/dataConnectors/azuread-${random_suffix}?api-version=2021-10-01-preview" \
        --body '{
            "kind": "AzureActiveDirectory",
            "properties": {
                "dataTypes": {
                    "signInLogs": { "state": "Enabled" },
                    "auditLogs": { "state": "Enabled" }
                }
            }
        }'
    
    # Azure Activity connector
    log_info "Enabling Azure Activity connector..."
    az rest \
        --method PUT \
        --uri "https://management.azure.com${workspace_id}/providers/Microsoft.SecurityInsights/dataConnectors/azureactivity-${random_suffix}?api-version=2021-10-01-preview" \
        --body '{
            "kind": "AzureActivity",
            "properties": {
                "dataTypes": {
                    "azureActivity": { "state": "Enabled" }
                }
            }
        }'
    
    # Security Events connector
    log_info "Enabling Security Events connector..."
    az rest \
        --method PUT \
        --uri "https://management.azure.com${workspace_id}/providers/Microsoft.SecurityInsights/dataConnectors/securityevents-${random_suffix}?api-version=2021-10-01-preview" \
        --body '{
            "kind": "SecurityEvents",
            "properties": {
                "dataTypes": {
                    "securityEvents": { "state": "Enabled" }
                }
            }
        }'
    
    log_success "Data connectors configured for comprehensive security coverage"
}

create_analytics_rules() {
    local workspace_id=$1
    local random_suffix=$2
    
    log_info "Creating analytics rules for threat detection..."
    
    # Suspicious sign-in attempts rule
    log_info "Creating suspicious sign-in detection rule..."
    az rest \
        --method PUT \
        --uri "https://management.azure.com${workspace_id}/providers/Microsoft.SecurityInsights/alertRules/suspicious-signin-${random_suffix}?api-version=2021-10-01-preview" \
        --body '{
            "kind": "Scheduled",
            "properties": {
                "displayName": "Multiple Failed Sign-in Attempts",
                "description": "Detects multiple failed sign-in attempts from same user",
                "severity": "Medium",
                "enabled": true,
                "query": "SigninLogs | where ResultType != 0 | summarize FailedAttempts = count() by UserPrincipalName, bin(TimeGenerated, 5m) | where FailedAttempts >= 5",
                "queryFrequency": "PT5M",
                "queryPeriod": "PT5M",
                "triggerOperator": "GreaterThan",
                "triggerThreshold": 0,
                "suppressionDuration": "PT1H",
                "suppressionEnabled": false,
                "tactics": ["CredentialAccess"],
                "eventGroupingSettings": {
                    "aggregationKind": "SingleAlert"
                }
            }
        }'
    
    # Privilege escalation rule
    log_info "Creating privilege escalation detection rule..."
    az rest \
        --method PUT \
        --uri "https://management.azure.com${workspace_id}/providers/Microsoft.SecurityInsights/alertRules/privilege-escalation-${random_suffix}?api-version=2021-10-01-preview" \
        --body '{
            "kind": "Scheduled",
            "properties": {
                "displayName": "Privilege Escalation Detected",
                "description": "Detects potential privilege escalation activities",
                "severity": "High",
                "enabled": true,
                "query": "AuditLogs | where OperationName in (\"Add member to role\", \"Add app role assignment\") | where ResultType == \"success\"",
                "queryFrequency": "PT10M",
                "queryPeriod": "PT10M",
                "triggerOperator": "GreaterThan",
                "triggerThreshold": 0,
                "suppressionDuration": "PT1H",
                "suppressionEnabled": false,
                "tactics": ["PrivilegeEscalation"],
                "eventGroupingSettings": {
                    "aggregationKind": "AlertPerResult"
                }
            }
        }'
    
    log_success "Analytics rules created for threat detection"
}

configure_unified_operations() {
    local workspace_id=$1
    local random_suffix=$2
    
    log_info "Configuring Unified Security Operations platform..."
    
    # Enable Sentinel in Defender portal
    az rest \
        --method POST \
        --uri "https://management.azure.com${workspace_id}/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2021-10-01-preview" \
        --body '{
            "properties": {
                "customerManagedKey": false
            }
        }'
    
    # Configure XDR data connector
    log_info "Configuring XDR data connector..."
    az rest \
        --method PUT \
        --uri "https://management.azure.com${workspace_id}/providers/Microsoft.SecurityInsights/dataConnectors/defender-xdr-${random_suffix}?api-version=2021-10-01-preview" \
        --body '{
            "kind": "MicrosoftThreatIntelligence",
            "properties": {
                "dataTypes": {
                    "microsoftDefenderThreatIntelligence": {
                        "state": "Enabled",
                        "lookbackPeriod": "P7D"
                    }
                }
            }
        }'
    
    log_success "Unified security operations platform configured"
    log_info "Access unified portal at: https://security.microsoft.com"
}

create_logic_app() {
    local logic_app_name=$1
    local resource_group=$2
    local location=$3
    
    log_info "Creating Logic App for automated incident response: $logic_app_name"
    
    # Create the Logic App with incident response workflow
    az logic workflow create \
        --resource-group "$resource_group" \
        --name "$logic_app_name" \
        --location "$location" \
        --definition '{
            "$schema": "https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json",
            "contentVersion": "1.0.0.0",
            "triggers": {
                "When_a_response_to_an_Azure_Sentinel_alert_is_triggered": {
                    "type": "ApiConnectionWebhook",
                    "inputs": {
                        "host": {
                            "connection": {
                                "name": "@parameters(\"$connections\")[\"azuresentinel\"][\"connectionId\"]"
                            }
                        },
                        "body": {
                            "callback_url": "@{listCallbackUrl()}"
                        },
                        "path": "/subscribe"
                    }
                }
            },
            "actions": {
                "Initialize_response_variable": {
                    "type": "InitializeVariable",
                    "inputs": {
                        "variables": [{
                            "name": "ResponseActions",
                            "type": "String",
                            "value": "Incident processed automatically"
                        }]
                    }
                },
                "Check_incident_severity": {
                    "type": "Switch",
                    "expression": "@triggerBody()?[\"Severity\"]",
                    "cases": {
                        "High": {
                            "case": "High",
                            "actions": {
                                "Send_high_severity_notification": {
                                    "type": "Http",
                                    "inputs": {
                                        "method": "POST",
                                        "uri": "https://hooks.slack.com/services/YOUR_WEBHOOK",
                                        "body": {
                                            "text": "High severity incident detected: @{triggerBody()?[\"Title\"]}"
                                        }
                                    }
                                }
                            }
                        }
                    },
                    "default": {
                        "actions": {
                            "Log_standard_response": {
                                "type": "Http",
                                "inputs": {
                                    "method": "POST",
                                    "uri": "https://your-logging-endpoint.com/log",
                                    "body": {
                                        "incident": "@{triggerBody()?[\"Title\"]}",
                                        "severity": "@{triggerBody()?[\"Severity\"]}"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }'
    
    log_success "Logic App created for automated incident response"
}

create_security_playbook() {
    local playbook_name=$1
    local resource_group=$2
    local location=$3
    local subscription_id=$4
    
    log_info "Creating security playbook: $playbook_name"
    
    # Create Azure AD connection first
    az rest \
        --method PUT \
        --uri "https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Web/connections/azuread-connection?api-version=2016-06-01" \
        --body '{
            "properties": {
                "displayName": "Azure AD Connection",
                "api": {
                    "id": "/subscriptions/'${subscription_id}'/providers/Microsoft.Web/locations/'${location}'/managedApis/azuread"
                }
            }
        }'
    
    # Create the playbook
    az logic workflow create \
        --resource-group "$resource_group" \
        --name "$playbook_name" \
        --location "$location" \
        --definition '{
            "$schema": "https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json",
            "contentVersion": "1.0.0.0",
            "triggers": {
                "manual": {
                    "type": "Request",
                    "kind": "Http",
                    "inputs": {
                        "schema": {
                            "type": "object",
                            "properties": {
                                "incidentId": { "type": "string" },
                                "userPrincipalName": { "type": "string" },
                                "action": { "type": "string" }
                            }
                        }
                    }
                }
            },
            "actions": {
                "Parse_incident_data": {
                    "type": "ParseJson",
                    "inputs": {
                        "content": "@triggerBody()",
                        "schema": {
                            "type": "object",
                            "properties": {
                                "incidentId": { "type": "string" },
                                "userPrincipalName": { "type": "string" },
                                "action": { "type": "string" }
                            }
                        }
                    }
                },
                "Condition_check_action": {
                    "type": "If",
                    "expression": {
                        "and": [{
                            "equals": ["@body(\"Parse_incident_data\")?[\"action\"]", "disable_user"]
                        }]
                    },
                    "actions": {
                        "Add_incident_comment": {
                            "type": "Http",
                            "inputs": {
                                "method": "POST",
                                "uri": "https://management.azure.com/subscriptions/'${subscription_id}'/providers/Microsoft.SecurityInsights/incidents/@{body(\"Parse_incident_data\")?[\"incidentId\"]}/comments/@{guid()}?api-version=2021-10-01-preview",
                                "headers": {
                                    "Authorization": "Bearer @{variables(\"AuthToken\")}"
                                },
                                "body": {
                                    "properties": {
                                        "message": "Automated response: User account @{body(\"Parse_incident_data\")?[\"userPrincipalName\"]} flagged for review"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }'
    
    log_success "Security playbook created for user account response"
}

create_workbook() {
    local workbook_name=$1
    local resource_group=$2
    local location=$3
    local subscription_id=$4
    local workspace_name=$5
    
    log_info "Creating Azure Monitor Workbook: $workbook_name"
    
    az rest \
        --method PUT \
        --uri "https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Insights/workbooks/security-ops-workbook?api-version=2021-03-08" \
        --body '{
            "location": "'${location}'",
            "kind": "shared",
            "properties": {
                "displayName": "Security Operations Dashboard",
                "serializedData": "{\"version\":\"Notebook/1.0\",\"items\":[{\"type\":1,\"content\":{\"json\":\"## Security Operations Overview\\n\\nThis dashboard provides real-time visibility into security incidents, threat trends, and response metrics.\"},\"name\":\"text - 0\"},{\"type\":3,\"content\":{\"version\":\"KqlItem/1.0\",\"query\":\"SecurityIncident\\n| where TimeGenerated >= ago(24h)\\n| summarize Count = count() by Severity\\n| render piechart\",\"size\":0,\"title\":\"Incidents by Severity (24h)\",\"queryType\":0,\"resourceType\":\"microsoft.operationalinsights/workspaces\",\"crossComponentResources\":[\"/subscriptions/'${subscription_id}'/resourceGroups/'${resource_group}'/providers/Microsoft.OperationalInsights/workspaces/'${workspace_name}'\"]},\"name\":\"query - 1\"},{\"type\":3,\"content\":{\"version\":\"KqlItem/1.0\",\"query\":\"SigninLogs\\n| where TimeGenerated >= ago(24h)\\n| where ResultType != 0\\n| summarize FailedSignins = count() by bin(TimeGenerated, 1h)\\n| render timechart\",\"size\":0,\"title\":\"Failed Sign-ins Trend (24h)\",\"queryType\":0,\"resourceType\":\"microsoft.operationalinsights/workspaces\",\"crossComponentResources\":[\"/subscriptions/'${subscription_id}'/resourceGroups/'${resource_group}'/providers/Microsoft.OperationalInsights/workspaces/'${workspace_name}'\"]},\"name\":\"query - 2\"},{\"type\":3,\"content\":{\"version\":\"KqlItem/1.0\",\"query\":\"SecurityIncident\\n| where TimeGenerated >= ago(7d)\\n| summarize IncidentCount = count() by Status\\n| render barchart\",\"size\":0,\"title\":\"Incident Status Distribution (7d)\",\"queryType\":0,\"resourceType\":\"microsoft.operationalinsights/workspaces\",\"crossComponentResources\":[\"/subscriptions/'${subscription_id}'/resourceGroups/'${resource_group}'/providers/Microsoft.OperationalInsights/workspaces/'${workspace_name}'\"]},\"name\":\"query - 3\"}],\"fallbackResourceIds\":[\"/subscriptions/'${subscription_id}'/resourceGroups/'${resource_group}'/providers/Microsoft.OperationalInsights/workspaces/'${workspace_name}'\"],\"fromTemplateId\":\"sentinel-UserAndEntityBehaviorAnalytics\"}"
            }
        }'
    
    log_success "Azure Monitor Workbook deployed with security visualizations"
}

# =============================================================================
# Main Deployment Function
# =============================================================================

main() {
    log_info "Starting Azure Unified Security Operations deployment..."
    log_info "Log file: $LOG_FILE"
    
    # Generate unique suffix for resource names
    local random_suffix=$(generate_random_suffix)
    log_info "Using random suffix: $random_suffix"
    
    # Set resource names
    local resource_group="${RESOURCE_GROUP:-${DEFAULT_RESOURCE_GROUP_PREFIX}-${random_suffix}}"
    local workspace_name="${WORKSPACE_NAME:-${DEFAULT_WORKSPACE_PREFIX}-${random_suffix}}"
    local sentinel_name="${SENTINEL_NAME:-${DEFAULT_SENTINEL_PREFIX}-${random_suffix}}"
    local logic_app_name="${LOGIC_APP_NAME:-${DEFAULT_LOGIC_APP_PREFIX}-${random_suffix}}"
    local playbook_name="playbook-user-response-${random_suffix}"
    local workbook_name="Security Operations Dashboard"
    
    # Display deployment plan
    log_info "Deployment Plan:"
    log_info "  Resource Group: $resource_group"
    log_info "  Location: $LOCATION"
    log_info "  Workspace: $workspace_name"
    log_info "  Sentinel: $sentinel_name"
    log_info "  Logic App: $logic_app_name"
    log_info "  Playbook: $playbook_name"
    log_info "  Workbook: $workbook_name"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "Dry run mode - no resources will be created"
        return 0
    fi
    
    # Confirm deployment
    if [ "$FORCE_DEPLOY" != "true" ]; then
        echo
        read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    log_info "Beginning deployment process..."
    
    # Step 1: Create resource group
    create_resource_group "$resource_group" "$LOCATION"
    
    # Step 2: Create Log Analytics workspace
    create_log_analytics_workspace "$workspace_name" "$resource_group" "$LOCATION"
    
    # Step 3: Enable Sentinel
    enable_sentinel "$workspace_name" "$resource_group"
    
    # Step 4: Configure data connectors
    configure_data_connectors "$WORKSPACE_ID" "$random_suffix"
    
    # Step 5: Create analytics rules
    create_analytics_rules "$WORKSPACE_ID" "$random_suffix"
    
    # Step 6: Configure unified operations
    configure_unified_operations "$WORKSPACE_ID" "$random_suffix"
    
    # Step 7: Create Logic App
    create_logic_app "$logic_app_name" "$resource_group" "$LOCATION"
    
    # Step 8: Create security playbook
    create_security_playbook "$playbook_name" "$resource_group" "$LOCATION" "$SUBSCRIPTION_ID"
    
    # Step 9: Create workbook
    create_workbook "$workbook_name" "$resource_group" "$LOCATION" "$SUBSCRIPTION_ID" "$workspace_name"
    
    # Save deployment info
    cat > "${LOG_DIR}/deployment_info.json" << EOF
{
    "deployment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "resource_group": "$resource_group",
    "location": "$LOCATION",
    "workspace_name": "$workspace_name",
    "workspace_id": "$WORKSPACE_ID",
    "sentinel_name": "$sentinel_name",
    "logic_app_name": "$logic_app_name",
    "playbook_name": "$playbook_name",
    "workbook_name": "$workbook_name",
    "subscription_id": "$SUBSCRIPTION_ID",
    "random_suffix": "$random_suffix"
}
EOF
    
    log_success "Deployment completed successfully!"
    log_info "Deployment information saved to: ${LOG_DIR}/deployment_info.json"
    
    # Display next steps
    echo
    log_info "Next Steps:"
    log_info "1. Access the unified security portal at: https://security.microsoft.com"
    log_info "2. Configure your notification endpoints in the Logic App"
    log_info "3. Review and customize analytics rules in Sentinel"
    log_info "4. Access the Security Operations Dashboard in Azure Monitor Workbooks"
    log_info "5. Test incident response by triggering test alerts"
    
    echo
    log_success "Azure Unified Security Operations deployment completed!"
}

# =============================================================================
# Command Line Argument Parsing
# =============================================================================

# Default values
LOCATION="$DEFAULT_LOCATION"
RESOURCE_GROUP=""
WORKSPACE_NAME=""
SENTINEL_NAME=""
LOGIC_APP_NAME=""
DRY_RUN="false"
VERBOSE="false"
SKIP_PREREQS="false"
FORCE_DEPLOY="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -w|--workspace)
            WORKSPACE_NAME="$2"
            shift 2
            ;;
        -s|--sentinel)
            SENTINEL_NAME="$2"
            shift 2
            ;;
        -a|--logic-app)
            LOGIC_APP_NAME="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -v|--verbose)
            VERBOSE="true"
            shift
            ;;
        --skip-prereqs)
            SKIP_PREREQS="true"
            shift
            ;;
        --force)
            FORCE_DEPLOY="true"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# =============================================================================
# Script Execution
# =============================================================================

# Set verbose mode
if [ "$VERBOSE" = "true" ]; then
    set -x
fi

# Run prerequisite checks
if [ "$SKIP_PREREQS" != "true" ]; then
    check_prerequisites
fi

# Execute main deployment
main

exit 0