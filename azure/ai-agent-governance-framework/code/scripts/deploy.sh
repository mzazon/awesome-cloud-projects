#!/bin/bash

# =============================================================================
# Azure AI Agent Governance Deployment Script
# =============================================================================
# This script deploys the complete Azure infrastructure for autonomous AI agent
# governance using Azure Entra Agent ID and Logic Apps.
#
# Prerequisites:
# - Azure CLI v2.50.0 or later
# - Global Administrator or Security Administrator permissions
# - Bash shell (Linux/macOS/WSL)
#
# Usage: ./deploy.sh [OPTIONS]
# Options:
#   -h, --help          Show this help message
#   -v, --verbose       Enable verbose output
#   -d, --dry-run       Show what would be deployed without executing
#   -r, --region        Azure region (default: eastus)
#   -g, --resource-group Custom resource group name
#
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
VERBOSE=false
DRY_RUN=false
REGION="eastus"
CUSTOM_RG=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

verbose_log() {
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "$1"
    fi
}

# Help function
show_help() {
    cat << EOF
Azure AI Agent Governance Deployment Script

This script deploys the complete Azure infrastructure for autonomous AI agent
governance using Azure Entra Agent ID and Logic Apps.

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -d, --dry-run       Show what would be deployed without executing
    -r, --region        Azure region (default: eastus)
    -g, --resource-group Custom resource group name

Examples:
    $0                                  # Deploy with default settings
    $0 -v -r westus2                   # Deploy in West US 2 with verbose output
    $0 -d                              # Dry run to see what would be deployed
    $0 -g my-ai-governance-rg          # Use custom resource group name

Prerequisites:
    - Azure CLI v2.50.0 or later
    - Global Administrator or Security Administrator permissions
    - Bash shell (Linux/macOS/WSL)

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -g|--resource-group)
                CUSTOM_RG="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI v2.50.0 or later."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    local min_version="2.50.0"
    
    if ! printf '%s\n%s' "$min_version" "$az_version" | sort -V -C; then
        log_error "Azure CLI version $az_version is too old. Please upgrade to v2.50.0 or later."
        exit 1
    fi
    
    verbose_log "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required tools are available
    local required_tools=("openssl" "curl" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool '$tool' is not installed."
            exit 1
        fi
    done
    
    log "✅ Prerequisites check passed"
}

# Validate Azure permissions
validate_permissions() {
    log "Validating Azure permissions..."
    
    local current_user
    current_user=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$current_user" ]]; then
        log_error "Cannot determine current user. Please ensure you have proper Azure AD permissions."
        exit 1
    fi
    
    verbose_log "Current user: $current_user"
    
    # Check if user has sufficient permissions (simplified check)
    local subscription_id
    subscription_id=$(az account show --query id -o tsv)
    
    if [[ -z "$subscription_id" ]]; then
        log_error "Cannot access Azure subscription. Please check your permissions."
        exit 1
    fi
    
    verbose_log "Subscription ID: $subscription_id"
    
    log "✅ Permission validation passed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names
    if [[ -n "$CUSTOM_RG" ]]; then
        RESOURCE_GROUP="$CUSTOM_RG"
    else
        RESOURCE_GROUP="rg-ai-governance-${RANDOM_SUFFIX}"
    fi
    
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    LOG_WORKSPACE="law-aigovernance-${RANDOM_SUFFIX}"
    KEY_VAULT="kv-aigovern-${RANDOM_SUFFIX}"
    LOGIC_APP_NAME="la-ai-governance-${RANDOM_SUFFIX}"
    COMPLIANCE_WORKFLOW="la-compliance-monitor-${RANDOM_SUFFIX}"
    ACCESS_CONTROL_WORKFLOW="la-access-control-${RANDOM_SUFFIX}"
    AUDIT_WORKFLOW="la-audit-reporting-${RANDOM_SUFFIX}"
    MONITORING_WORKFLOW="la-agent-monitoring-${RANDOM_SUFFIX}"
    
    # Export variables for use in dry-run mode
    export RESOURCE_GROUP REGION SUBSCRIPTION_ID LOG_WORKSPACE KEY_VAULT
    export LOGIC_APP_NAME COMPLIANCE_WORKFLOW ACCESS_CONTROL_WORKFLOW
    export AUDIT_WORKFLOW MONITORING_WORKFLOW RANDOM_SUFFIX
    
    verbose_log "Resource Group: $RESOURCE_GROUP"
    verbose_log "Region: $REGION"
    verbose_log "Random Suffix: $RANDOM_SUFFIX"
    
    log "✅ Environment variables configured"
}

# Create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in region: $REGION"
        return 0
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$REGION" \
            --tags purpose=ai-governance environment=production \
            --output table
        
        log "✅ Resource group created: $RESOURCE_GROUP"
    fi
}

# Enable Azure Entra Agent ID features
enable_agent_id_features() {
    log "Enabling Azure Entra Agent ID features..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable Entra Agent ID preview features"
        return 0
    fi
    
    # Register the feature (may already be registered)
    az feature register \
        --namespace Microsoft.EntraAgentID \
        --name AgentIdentityPreview \
        --output table || true
    
    log "✅ Azure Entra Agent ID features enabled"
}

# Create Log Analytics workspace
create_log_analytics_workspace() {
    log "Creating Log Analytics workspace..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Log Analytics workspace: $LOG_WORKSPACE"
        return 0
    fi
    
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_WORKSPACE" \
        --location "$REGION" \
        --sku PerGB2018 \
        --output table
    
    log "✅ Log Analytics workspace created: $LOG_WORKSPACE"
}

# Create Key Vault
create_key_vault() {
    log "Creating Key Vault..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Key Vault: $KEY_VAULT"
        return 0
    fi
    
    az keyvault create \
        --name "$KEY_VAULT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$REGION" \
        --sku standard \
        --enable-soft-delete true \
        --retention-days 90 \
        --output table
    
    log "✅ Key Vault created: $KEY_VAULT"
}

# Create Logic Apps workflows
create_logic_apps() {
    log "Creating Logic Apps workflows..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Logic Apps workflows:"
        log_info "  - $LOGIC_APP_NAME"
        log_info "  - $COMPLIANCE_WORKFLOW"
        log_info "  - $ACCESS_CONTROL_WORKFLOW"
        log_info "  - $AUDIT_WORKFLOW"
        log_info "  - $MONITORING_WORKFLOW"
        return 0
    fi
    
    # Create main AI governance Logic App
    az logic workflow create \
        --resource-group "$RESOURCE_GROUP" \
        --location "$REGION" \
        --name "$LOGIC_APP_NAME" \
        --definition '{
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "triggers": {
                "Recurrence": {
                    "recurrence": {
                        "frequency": "Hour",
                        "interval": 1
                    },
                    "type": "Recurrence"
                }
            },
            "actions": {
                "Get_Agent_Identities": {
                    "type": "Http",
                    "inputs": {
                        "method": "GET",
                        "uri": "https://graph.microsoft.com/v1.0/applications?$filter=applicationtype eq '\''AgentID'\''"
                    }
                }
            }
        }' \
        --output table
    
    log "✅ Main Logic App created: $LOGIC_APP_NAME"
    
    # Create compliance monitoring workflow
    az logic workflow create \
        --resource-group "$RESOURCE_GROUP" \
        --location "$REGION" \
        --name "$COMPLIANCE_WORKFLOW" \
        --definition '{
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "triggers": {
                "When_Agent_Event_Occurs": {
                    "type": "HttpRequest",
                    "kind": "Http"
                }
            },
            "actions": {
                "Analyze_Agent_Permissions": {
                    "type": "Http",
                    "inputs": {
                        "method": "GET",
                        "uri": "https://graph.microsoft.com/v1.0/applications/@{triggerBody()?['\''objectId'\'']}/appRoleAssignments"
                    }
                },
                "Check_Compliance_Rules": {
                    "type": "Compose",
                    "inputs": {
                        "complianceCheck": "Evaluate permissions against policy",
                        "riskLevel": "@if(greater(length(body('\''Analyze_Agent_Permissions'\'')?['\''value'\'']), 5), '\''high'\'', '\''low'\'')"
                    }
                }
            }
        }' \
        --output table
    
    log "✅ Compliance monitoring workflow created: $COMPLIANCE_WORKFLOW"
    
    # Create access control workflow
    az logic workflow create \
        --resource-group "$RESOURCE_GROUP" \
        --location "$REGION" \
        --name "$ACCESS_CONTROL_WORKFLOW" \
        --definition '{
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "triggers": {
                "Risk_Assessment_Trigger": {
                    "type": "HttpRequest",
                    "kind": "Http"
                }
            },
            "actions": {
                "Evaluate_Agent_Risk": {
                    "type": "Compose",
                    "inputs": {
                        "riskFactors": {
                            "unusualActivity": "@triggerBody()?['\''anomalousAccess'\'']",
                            "permissionChanges": "@triggerBody()?['\''permissionModifications'\'']",
                            "resourceAccess": "@triggerBody()?['\''sensitiveResourceAccess'\'']"
                        }
                    }
                }
            }
        }' \
        --output table
    
    log "✅ Access control workflow created: $ACCESS_CONTROL_WORKFLOW"
    
    # Create audit workflow
    az logic workflow create \
        --resource-group "$RESOURCE_GROUP" \
        --location "$REGION" \
        --name "$AUDIT_WORKFLOW" \
        --definition '{
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "triggers": {
                "Daily_Report_Schedule": {
                    "recurrence": {
                        "frequency": "Day",
                        "interval": 1
                    },
                    "type": "Recurrence"
                }
            },
            "actions": {
                "Generate_Compliance_Report": {
                    "type": "Compose",
                    "inputs": {
                        "reportDate": "@{utcNow()}",
                        "complianceStatus": "Evaluated"
                    }
                }
            }
        }' \
        --output table
    
    log "✅ Audit workflow created: $AUDIT_WORKFLOW"
    
    # Create monitoring workflow
    az logic workflow create \
        --resource-group "$RESOURCE_GROUP" \
        --location "$REGION" \
        --name "$MONITORING_WORKFLOW" \
        --definition '{
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "contentVersion": "1.0.0.0",
            "triggers": {
                "Performance_Check_Schedule": {
                    "recurrence": {
                        "frequency": "Minute",
                        "interval": 15
                    },
                    "type": "Recurrence"
                }
            },
            "actions": {
                "Query_Agent_Health": {
                    "type": "Http",
                    "inputs": {
                        "method": "GET",
                        "uri": "https://graph.microsoft.com/v1.0/applications?$filter=applicationtype eq '\''AgentID'\''"
                    }
                }
            }
        }' \
        --output table
    
    log "✅ Monitoring workflow created: $MONITORING_WORKFLOW"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    # Check resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group $RESOURCE_GROUP not found"
        return 1
    fi
    
    # Check Log Analytics workspace
    if ! az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_WORKSPACE" &> /dev/null; then
        log_error "Log Analytics workspace $LOG_WORKSPACE not found"
        return 1
    fi
    
    # Check Key Vault
    if ! az keyvault show --name "$KEY_VAULT" &> /dev/null; then
        log_error "Key Vault $KEY_VAULT not found"
        return 1
    fi
    
    # Check Logic Apps
    local workflows=("$LOGIC_APP_NAME" "$COMPLIANCE_WORKFLOW" "$ACCESS_CONTROL_WORKFLOW" "$AUDIT_WORKFLOW" "$MONITORING_WORKFLOW")
    for workflow in "${workflows[@]}"; do
        if ! az logic workflow show --resource-group "$RESOURCE_GROUP" --name "$workflow" &> /dev/null; then
            log_error "Logic App workflow $workflow not found"
            return 1
        fi
    done
    
    log "✅ Deployment validation passed"
}

# Display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Summary of what would be deployed:"
    else
        log_info "Deployment Summary:"
    fi
    
    echo ""
    echo "=== Resource Details ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Region: $REGION"
    echo "Subscription ID: $SUBSCRIPTION_ID"
    echo ""
    echo "=== Created Resources ==="
    echo "Log Analytics Workspace: $LOG_WORKSPACE"
    echo "Key Vault: $KEY_VAULT"
    echo "Logic Apps:"
    echo "  - Main Governance: $LOGIC_APP_NAME"
    echo "  - Compliance Monitoring: $COMPLIANCE_WORKFLOW"
    echo "  - Access Control: $ACCESS_CONTROL_WORKFLOW"
    echo "  - Audit Reporting: $AUDIT_WORKFLOW"
    echo "  - Agent Monitoring: $MONITORING_WORKFLOW"
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "=== Next Steps ==="
        echo "1. Review the Logic Apps workflows in the Azure portal"
        echo "2. Configure authentication for Microsoft Graph API calls"
        echo "3. Test the compliance monitoring workflow"
        echo "4. Set up custom compliance rules as needed"
        echo "5. Monitor the Log Analytics workspace for governance events"
        echo ""
        echo "=== Cleanup ==="
        echo "To remove all resources, run: ./destroy.sh -g $RESOURCE_GROUP"
    fi
    
    echo ""
    log "Deployment log saved to: $LOG_FILE"
}

# Error handling
handle_error() {
    local exit_code=$?
    log_error "Script failed with exit code $exit_code"
    log_error "Check the log file for details: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_warning "You may need to manually clean up partially created resources"
        log_warning "Use the destroy.sh script to remove any created resources"
    fi
    
    exit $exit_code
}

# Main execution
main() {
    # Set up error handling
    trap handle_error ERR
    
    # Initialize log file
    echo "Azure AI Agent Governance Deployment Log" > "$LOG_FILE"
    echo "Started: $(date)" >> "$LOG_FILE"
    echo "=========================================" >> "$LOG_FILE"
    
    # Parse command line arguments
    parse_args "$@"
    
    log "Starting Azure AI Agent Governance deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE: No resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    validate_permissions
    setup_environment
    create_resource_group
    enable_agent_id_features
    create_log_analytics_workspace
    create_key_vault
    create_logic_apps
    
    if [[ "$DRY_RUN" == "false" ]]; then
        validate_deployment
    fi
    
    display_summary
    
    log "Deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"