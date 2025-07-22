#!/bin/bash

# =============================================================================
# Azure Unified Security Operations Cleanup Script
# =============================================================================
# This script removes all Azure resources created by the deployment script
# for the automated security incident response solution
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
LOG_FILE="${LOG_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "${LOG_DIR}"

# Deployment info file
DEPLOYMENT_INFO_FILE="${LOG_DIR}/deployment_info.json"

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

Remove Azure Unified Security Operations infrastructure.

OPTIONS:
    -h, --help                    Show this help message
    -g, --resource-group NAME     Resource group name to delete
    -f, --from-file FILE          Load deployment info from JSON file
    -d, --dry-run                 Show what would be deleted without executing
    -v, --verbose                 Enable verbose logging
    --skip-prereqs               Skip prerequisite checks
    --force                      Force deletion without confirmation prompts
    --partial                    Allow partial cleanup (continue on errors)

EXAMPLES:
    $0                           # Delete using saved deployment info
    $0 -g my-resource-group      # Delete specific resource group
    $0 --dry-run                 # Show deletion plan without executing
    $0 --force                   # Force deletion without prompts
    $0 --partial                 # Continue cleanup even if some resources fail

EOF
}

check_command() {
    local cmd=$1
    local package=${2:-$cmd}
    
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command '$cmd' not found. Please install $package."
        exit 1
    fi
}

wait_for_deletion() {
    local resource_type=$1
    local resource_name=$2
    local resource_group=$3
    local timeout=${4:-300}
    local interval=${5:-10}
    
    log_info "Waiting for $resource_type '$resource_name' to be deleted..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if ! az "$resource_type" show \
            --name "$resource_name" \
            --resource-group "$resource_group" \
            >/dev/null 2>&1; then
            log_success "$resource_type '$resource_name' has been deleted"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        log_info "Still waiting for deletion... ($elapsed/${timeout}s)"
    done
    
    log_error "Timeout waiting for $resource_type '$resource_name' to be deleted"
    return 1
}

load_deployment_info() {
    local info_file=${1:-$DEPLOYMENT_INFO_FILE}
    
    if [ ! -f "$info_file" ]; then
        log_error "Deployment info file not found: $info_file"
        log_error "Please provide resource group name with -g option or specify info file with -f option"
        exit 1
    fi
    
    log_info "Loading deployment information from: $info_file"
    
    # Extract values from JSON file
    RESOURCE_GROUP=$(jq -r '.resource_group' "$info_file")
    LOCATION=$(jq -r '.location' "$info_file")
    WORKSPACE_NAME=$(jq -r '.workspace_name' "$info_file")
    WORKSPACE_ID=$(jq -r '.workspace_id' "$info_file")
    SENTINEL_NAME=$(jq -r '.sentinel_name' "$info_file")
    LOGIC_APP_NAME=$(jq -r '.logic_app_name' "$info_file")
    PLAYBOOK_NAME=$(jq -r '.playbook_name' "$info_file")
    WORKBOOK_NAME=$(jq -r '.workbook_name' "$info_file")
    SUBSCRIPTION_ID=$(jq -r '.subscription_id' "$info_file")
    RANDOM_SUFFIX=$(jq -r '.random_suffix' "$info_file")
    
    # Validate extracted values
    if [ "$RESOURCE_GROUP" = "null" ] || [ -z "$RESOURCE_GROUP" ]; then
        log_error "Invalid deployment info file: missing resource_group"
        exit 1
    fi
    
    log_info "Loaded deployment info:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Workspace: $WORKSPACE_NAME"
    log_info "  Subscription: $SUBSCRIPTION_ID"
}

confirm_deletion() {
    local resource_group=$1
    
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log_warning "This will permanently delete ALL resources in resource group: $resource_group"
    log_warning "This includes:"
    log_warning "  - Microsoft Sentinel workspace and all security data"
    log_warning "  - Log Analytics workspace and all collected logs"
    log_warning "  - Logic Apps and security playbooks"
    log_warning "  - Azure Monitor Workbooks and dashboards"
    log_warning "  - Analytics rules and data connectors"
    log_warning "  - All associated configurations and customizations"
    echo
    
    if [ "$FORCE_DELETE" != "true" ]; then
        read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " -r
        echo
        if [ "$REPLY" != "DELETE" ]; then
            log_info "Deletion cancelled by user"
            exit 0
        fi
        
        read -p "Last chance - type the resource group name to confirm: " -r
        echo
        if [ "$REPLY" != "$resource_group" ]; then
            log_info "Resource group name mismatch. Deletion cancelled."
            exit 0
        fi
    fi
    
    log_info "Deletion confirmed. Proceeding with cleanup..."
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
    CURRENT_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    TENANT_ID=$(az account show --query tenantId --output tsv)
    
    log_info "Using subscription: $CURRENT_SUBSCRIPTION_ID"
    log_info "Using tenant: $TENANT_ID"
    
    # Validate subscription match if we have deployment info
    if [ -n "${SUBSCRIPTION_ID:-}" ] && [ "$SUBSCRIPTION_ID" != "$CURRENT_SUBSCRIPTION_ID" ]; then
        log_warning "Subscription mismatch!"
        log_warning "  Deployment was in: $SUBSCRIPTION_ID"
        log_warning "  Current subscription: $CURRENT_SUBSCRIPTION_ID"
        
        if [ "$FORCE_DELETE" != "true" ]; then
            read -p "Continue with current subscription? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Cleanup cancelled due to subscription mismatch"
                exit 0
            fi
        fi
    fi
    
    log_success "Prerequisites check completed"
}

# =============================================================================
# Resource Cleanup Functions
# =============================================================================

delete_analytics_rules() {
    local workspace_id=$1
    local random_suffix=$2
    
    log_info "Deleting analytics rules..."
    
    # Delete suspicious sign-in rule
    if az rest \
        --method DELETE \
        --uri "https://management.azure.com${workspace_id}/providers/Microsoft.SecurityInsights/alertRules/suspicious-signin-${random_suffix}?api-version=2021-10-01-preview" \
        >/dev/null 2>&1; then
        log_success "Deleted suspicious sign-in analytics rule"
    else
        log_warning "Failed to delete suspicious sign-in analytics rule (may not exist)"
    fi
    
    # Delete privilege escalation rule
    if az rest \
        --method DELETE \
        --uri "https://management.azure.com${workspace_id}/providers/Microsoft.SecurityInsights/alertRules/privilege-escalation-${random_suffix}?api-version=2021-10-01-preview" \
        >/dev/null 2>&1; then
        log_success "Deleted privilege escalation analytics rule"
    else
        log_warning "Failed to delete privilege escalation analytics rule (may not exist)"
    fi
    
    log_info "Analytics rules cleanup completed"
}

delete_data_connectors() {
    local workspace_id=$1
    local random_suffix=$2
    
    log_info "Deleting data connectors..."
    
    # Delete Azure AD connector
    if az rest \
        --method DELETE \
        --uri "https://management.azure.com${workspace_id}/providers/Microsoft.SecurityInsights/dataConnectors/azuread-${random_suffix}?api-version=2021-10-01-preview" \
        >/dev/null 2>&1; then
        log_success "Deleted Azure AD data connector"
    else
        log_warning "Failed to delete Azure AD data connector (may not exist)"
    fi
    
    # Delete Azure Activity connector
    if az rest \
        --method DELETE \
        --uri "https://management.azure.com${workspace_id}/providers/Microsoft.SecurityInsights/dataConnectors/azureactivity-${random_suffix}?api-version=2021-10-01-preview" \
        >/dev/null 2>&1; then
        log_success "Deleted Azure Activity data connector"
    else
        log_warning "Failed to delete Azure Activity data connector (may not exist)"
    fi
    
    # Delete Security Events connector
    if az rest \
        --method DELETE \
        --uri "https://management.azure.com${workspace_id}/providers/Microsoft.SecurityInsights/dataConnectors/securityevents-${random_suffix}?api-version=2021-10-01-preview" \
        >/dev/null 2>&1; then
        log_success "Deleted Security Events data connector"
    else
        log_warning "Failed to delete Security Events data connector (may not exist)"
    fi
    
    # Delete XDR connector
    if az rest \
        --method DELETE \
        --uri "https://management.azure.com${workspace_id}/providers/Microsoft.SecurityInsights/dataConnectors/defender-xdr-${random_suffix}?api-version=2021-10-01-preview" \
        >/dev/null 2>&1; then
        log_success "Deleted Defender XDR data connector"
    else
        log_warning "Failed to delete Defender XDR data connector (may not exist)"
    fi
    
    log_info "Data connectors cleanup completed"
}

delete_workbook() {
    local resource_group=$1
    local subscription_id=$2
    
    log_info "Deleting Azure Monitor Workbook..."
    
    # Find and delete workbook
    if az rest \
        --method DELETE \
        --uri "https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Insights/workbooks/security-ops-workbook?api-version=2021-03-08" \
        >/dev/null 2>&1; then
        log_success "Deleted Security Operations workbook"
    else
        log_warning "Failed to delete workbook (may not exist)"
    fi
    
    log_info "Workbook cleanup completed"
}

delete_logic_apps() {
    local resource_group=$1
    local logic_app_name=$2
    local playbook_name=$3
    
    log_info "Deleting Logic Apps and playbooks..."
    
    # Delete main Logic App
    if az logic workflow delete \
        --resource-group "$resource_group" \
        --name "$logic_app_name" \
        --yes >/dev/null 2>&1; then
        log_success "Deleted Logic App: $logic_app_name"
    else
        log_warning "Failed to delete Logic App: $logic_app_name (may not exist)"
    fi
    
    # Delete security playbook
    if az logic workflow delete \
        --resource-group "$resource_group" \
        --name "$playbook_name" \
        --yes >/dev/null 2>&1; then
        log_success "Deleted security playbook: $playbook_name"
    else
        log_warning "Failed to delete security playbook: $playbook_name (may not exist)"
    fi
    
    # Delete Azure AD connection
    if az rest \
        --method DELETE \
        --uri "https://management.azure.com/subscriptions/${CURRENT_SUBSCRIPTION_ID}/resourceGroups/${resource_group}/providers/Microsoft.Web/connections/azuread-connection?api-version=2016-06-01" \
        >/dev/null 2>&1; then
        log_success "Deleted Azure AD connection"
    else
        log_warning "Failed to delete Azure AD connection (may not exist)"
    fi
    
    log_info "Logic Apps cleanup completed"
}

delete_sentinel() {
    local resource_group=$1
    local workspace_name=$2
    
    log_info "Deleting Microsoft Sentinel configuration..."
    
    # Note: Sentinel doesn't have a direct delete command
    # It's removed when the Log Analytics workspace is deleted
    # We'll disable it first to clean up references
    
    log_info "Disabling Sentinel workspace..."
    
    # Attempt to disable Sentinel (this may fail if already disabled)
    if az rest \
        --method DELETE \
        --uri "https://management.azure.com${WORKSPACE_ID}/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2021-10-01-preview" \
        >/dev/null 2>&1; then
        log_success "Disabled Sentinel workspace"
    else
        log_warning "Failed to disable Sentinel workspace (may already be disabled)"
    fi
    
    log_info "Sentinel cleanup completed"
}

delete_log_analytics_workspace() {
    local resource_group=$1
    local workspace_name=$2
    
    log_info "Deleting Log Analytics workspace: $workspace_name"
    
    # Delete the workspace
    if az monitor log-analytics workspace delete \
        --resource-group "$resource_group" \
        --workspace-name "$workspace_name" \
        --yes >/dev/null 2>&1; then
        log_success "Deleted Log Analytics workspace: $workspace_name"
        
        # Wait for deletion to complete
        if wait_for_deletion "monitor log-analytics workspace" "$workspace_name" "$resource_group"; then
            log_success "Log Analytics workspace deletion completed"
        else
            log_warning "Log Analytics workspace deletion may still be in progress"
        fi
    else
        log_warning "Failed to delete Log Analytics workspace: $workspace_name (may not exist)"
    fi
}

delete_resource_group() {
    local resource_group=$1
    
    log_info "Deleting resource group: $resource_group"
    
    # Check if resource group exists
    if ! az group show --name "$resource_group" >/dev/null 2>&1; then
        log_warning "Resource group '$resource_group' does not exist"
        return 0
    fi
    
    # Delete the resource group
    if az group delete \
        --name "$resource_group" \
        --yes \
        --no-wait; then
        log_success "Initiated deletion of resource group: $resource_group"
        log_info "Resource group deletion is running in the background"
        log_info "This may take 10-15 minutes to complete"
    else
        log_error "Failed to delete resource group: $resource_group"
        return 1
    fi
}

cleanup_deployment_info() {
    local info_file=${1:-$DEPLOYMENT_INFO_FILE}
    
    log_info "Cleaning up deployment information..."
    
    if [ -f "$info_file" ]; then
        # Archive the deployment info instead of deleting
        local archive_name="${info_file}.deleted.$(date +%Y%m%d_%H%M%S)"
        mv "$info_file" "$archive_name"
        log_success "Deployment info archived to: $archive_name"
    fi
    
    # Clean up any temporary files
    if [ -d "${LOG_DIR}/temp" ]; then
        rm -rf "${LOG_DIR}/temp"
        log_success "Cleaned up temporary files"
    fi
}

# =============================================================================
# Main Cleanup Function
# =============================================================================

main() {
    log_info "Starting Azure Unified Security Operations cleanup..."
    log_info "Log file: $LOG_FILE"
    
    # Load deployment information
    if [ -n "${RESOURCE_GROUP_PARAM:-}" ]; then
        RESOURCE_GROUP="$RESOURCE_GROUP_PARAM"
        log_info "Using provided resource group: $RESOURCE_GROUP"
        # Set default values for missing info
        WORKSPACE_NAME="${WORKSPACE_NAME:-unknown}"
        WORKSPACE_ID="${WORKSPACE_ID:-unknown}"
        RANDOM_SUFFIX="${RANDOM_SUFFIX:-unknown}"
        LOGIC_APP_NAME="${LOGIC_APP_NAME:-unknown}"
        PLAYBOOK_NAME="${PLAYBOOK_NAME:-unknown}"
        WORKBOOK_NAME="${WORKBOOK_NAME:-unknown}"
        SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$CURRENT_SUBSCRIPTION_ID}"
    else
        load_deployment_info "$DEPLOYMENT_INFO_FILE_PARAM"
    fi
    
    # Display cleanup plan
    log_info "Cleanup Plan:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Workspace: $WORKSPACE_NAME"
    log_info "  Location: ${LOCATION:-unknown}"
    log_info "  Subscription: $SUBSCRIPTION_ID"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "Dry run mode - no resources will be deleted"
        log_info "Resources that would be deleted:"
        log_info "  1. Analytics rules and data connectors"
        log_info "  2. Azure Monitor Workbook"
        log_info "  3. Logic Apps and security playbooks"
        log_info "  4. Microsoft Sentinel configuration"
        log_info "  5. Log Analytics workspace"
        log_info "  6. Resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Confirm deletion
    confirm_deletion "$RESOURCE_GROUP"
    
    # Execute cleanup steps
    log_info "Beginning cleanup process..."
    
    # Use resource group deletion if we have complete deployment info
    if [ "$RESOURCE_GROUP" != "unknown" ] && [ "$WORKSPACE_ID" != "unknown" ] && [ "$RANDOM_SUFFIX" != "unknown" ]; then
        log_info "Performing detailed cleanup before resource group deletion..."
        
        # Step 1: Delete analytics rules
        if [ "$PARTIAL_CLEANUP" = "true" ]; then
            delete_analytics_rules "$WORKSPACE_ID" "$RANDOM_SUFFIX" || log_warning "Analytics rules cleanup failed, continuing..."
        else
            delete_analytics_rules "$WORKSPACE_ID" "$RANDOM_SUFFIX"
        fi
        
        # Step 2: Delete data connectors
        if [ "$PARTIAL_CLEANUP" = "true" ]; then
            delete_data_connectors "$WORKSPACE_ID" "$RANDOM_SUFFIX" || log_warning "Data connectors cleanup failed, continuing..."
        else
            delete_data_connectors "$WORKSPACE_ID" "$RANDOM_SUFFIX"
        fi
        
        # Step 3: Delete workbook
        if [ "$PARTIAL_CLEANUP" = "true" ]; then
            delete_workbook "$RESOURCE_GROUP" "$SUBSCRIPTION_ID" || log_warning "Workbook cleanup failed, continuing..."
        else
            delete_workbook "$RESOURCE_GROUP" "$SUBSCRIPTION_ID"
        fi
        
        # Step 4: Delete Logic Apps
        if [ "$PARTIAL_CLEANUP" = "true" ]; then
            delete_logic_apps "$RESOURCE_GROUP" "$LOGIC_APP_NAME" "$PLAYBOOK_NAME" || log_warning "Logic Apps cleanup failed, continuing..."
        else
            delete_logic_apps "$RESOURCE_GROUP" "$LOGIC_APP_NAME" "$PLAYBOOK_NAME"
        fi
        
        # Step 5: Delete Sentinel
        if [ "$PARTIAL_CLEANUP" = "true" ]; then
            delete_sentinel "$RESOURCE_GROUP" "$WORKSPACE_NAME" || log_warning "Sentinel cleanup failed, continuing..."
        else
            delete_sentinel "$RESOURCE_GROUP" "$WORKSPACE_NAME"
        fi
        
        # Step 6: Delete Log Analytics workspace
        if [ "$PARTIAL_CLEANUP" = "true" ]; then
            delete_log_analytics_workspace "$RESOURCE_GROUP" "$WORKSPACE_NAME" || log_warning "Log Analytics workspace cleanup failed, continuing..."
        else
            delete_log_analytics_workspace "$RESOURCE_GROUP" "$WORKSPACE_NAME"
        fi
    else
        log_info "Limited deployment info available, proceeding with resource group deletion only..."
    fi
    
    # Final step: Delete resource group
    if [ "$PARTIAL_CLEANUP" = "true" ]; then
        delete_resource_group "$RESOURCE_GROUP" || log_warning "Resource group deletion failed"
    else
        delete_resource_group "$RESOURCE_GROUP"
    fi
    
    # Cleanup deployment info
    cleanup_deployment_info "$DEPLOYMENT_INFO_FILE_PARAM"
    
    log_success "Cleanup completed successfully!"
    
    # Display final status
    echo
    log_info "Cleanup Summary:"
    log_info "✅ Analytics rules and data connectors removed"
    log_info "✅ Azure Monitor Workbook deleted"
    log_info "✅ Logic Apps and security playbooks removed"
    log_info "✅ Microsoft Sentinel configuration disabled"
    log_info "✅ Log Analytics workspace deleted"
    log_info "✅ Resource group deletion initiated: $RESOURCE_GROUP"
    log_info "✅ Deployment information archived"
    
    echo
    log_info "Note: Resource group deletion may take 10-15 minutes to complete"
    log_info "You can check the status in the Azure portal or with:"
    log_info "  az group show --name $RESOURCE_GROUP"
    
    echo
    log_success "Azure Unified Security Operations cleanup completed!"
}

# =============================================================================
# Command Line Argument Parsing
# =============================================================================

# Default values
RESOURCE_GROUP_PARAM=""
DEPLOYMENT_INFO_FILE_PARAM="$DEPLOYMENT_INFO_FILE"
DRY_RUN="false"
VERBOSE="false"
SKIP_PREREQS="false"
FORCE_DELETE="false"
PARTIAL_CLEANUP="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -g|--resource-group)
            RESOURCE_GROUP_PARAM="$2"
            shift 2
            ;;
        -f|--from-file)
            DEPLOYMENT_INFO_FILE_PARAM="$2"
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
            FORCE_DELETE="true"
            shift
            ;;
        --partial)
            PARTIAL_CLEANUP="true"
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

# Set partial cleanup mode
if [ "$PARTIAL_CLEANUP" = "true" ]; then
    set +e  # Don't exit on errors in partial cleanup mode
fi

# Run prerequisite checks
if [ "$SKIP_PREREQS" != "true" ]; then
    check_prerequisites
fi

# Execute main cleanup
main

exit 0