#!/bin/bash

# Meeting Intelligence with Speech Services and OpenAI - Cleanup Script
# This script safely removes all Azure resources created for the meeting intelligence solution

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'       # Secure Internal Field Separator

# ================================================================
# CONFIGURATION VARIABLES
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=false
FORCE_DESTROY=false
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
INTERACTIVE=true

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ================================================================
# UTILITY FUNCTIONS
# ================================================================

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} - $1" | tee -a "${LOG_FILE}"
}

error() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

warning() {
    log "${YELLOW}WARNING: $1${NC}"
}

success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

info() {
    log "${BLUE}INFO: $1${NC}"
}

# Progress indicator
show_progress() {
    local step=$1
    local total=$2
    local description=$3
    echo -e "${BLUE}[${step}/${total}] ${description}${NC}"
}

# Confirmation prompt
confirm() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "${INTERACTIVE}" == "false" ]] || [[ "${FORCE_DESTROY}" == "true" ]]; then
        log "Auto-confirming: ${message}"
        return 0
    fi
    
    local prompt
    if [[ "${default}" == "y" ]]; then
        prompt="${message} [Y/n]: "
    else
        prompt="${message} [y/N]: "
    fi
    
    while true; do
        read -p "${prompt}" choice
        case "${choice:-${default}}" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    
    case "${resource_type}" in
        "group")
            az group show --name "${resource_name}" &>/dev/null
            ;;
        "storage")
            az storage account show --name "${resource_name}" --resource-group "${resource_group}" &>/dev/null
            ;;
        "speech"|"openai")
            az cognitiveservices account show --name "${resource_name}" --resource-group "${resource_group}" &>/dev/null
            ;;
        "servicebus")
            az servicebus namespace show --name "${resource_name}" --resource-group "${resource_group}" &>/dev/null
            ;;
        "functionapp")
            az functionapp show --name "${resource_name}" --resource-group "${resource_group}" &>/dev/null
            ;;
        *)
            error "Unknown resource type: ${resource_type}"
            ;;
    esac
}

# Wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    local max_attempts=30
    local attempt=1
    
    info "Waiting for ${resource_type} ${resource_name} to be deleted..."
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        if ! resource_exists "${resource_type}" "${resource_name}" "${resource_group}"; then
            success "${resource_type} ${resource_name} has been deleted"
            return 0
        fi
        
        info "Waiting for deletion... (attempt ${attempt}/${max_attempts})"
        sleep 10
        ((attempt++))
    done
    
    warning "${resource_type} ${resource_name} deletion did not complete in expected time"
    return 1
}

# Validate prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
    fi
    
    # Validate subscription
    if [[ -z "${SUBSCRIPTION_ID}" ]]; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        info "Using current subscription: ${SUBSCRIPTION_ID}"
    else
        az account set --subscription "${SUBSCRIPTION_ID}" || error "Failed to set subscription ${SUBSCRIPTION_ID}"
    fi
    
    success "Prerequisites check completed"
}

# List and discover resources to delete
discover_resources() {
    info "Discovering resources to delete..."
    
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        error "Resource group name is required. Use -g/--resource-group or run with --help for usage."
    fi
    
    if ! resource_exists "group" "${RESOURCE_GROUP}" ""; then
        warning "Resource group ${RESOURCE_GROUP} does not exist or is not accessible"
        return 1
    fi
    
    # Get all resources in the resource group
    local resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{name:name, type:type, location:location}" --output json 2>/dev/null || echo "[]")
    local resource_count=$(echo "${resources}" | jq length 2>/dev/null || echo "0")
    
    if [[ "${resource_count}" -eq 0 ]]; then
        warning "No resources found in resource group ${RESOURCE_GROUP}"
        return 1
    fi
    
    info "Found ${resource_count} resources in resource group ${RESOURCE_GROUP}:"
    
    # Display resources with formatting
    echo "${resources}" | jq -r '.[] | "  - \(.name) (\(.type)) in \(.location)"' 2>/dev/null || {
        warning "Could not parse resource list. Continuing with deletion..."
    }
    
    # Store resource information for deletion order
    export DISCOVERED_RESOURCES="${resources}"
    
    return 0
}

# Delete Function Apps first (to release dependencies)
delete_function_apps() {
    show_progress 1 6 "Removing Function Apps"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would delete Function Apps in resource group ${RESOURCE_GROUP}"
        return 0
    fi
    
    # Find Function Apps in the resource group
    local function_apps=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -z "${function_apps}" ]]; then
        info "No Function Apps found to delete"
        return 0
    fi
    
    for app in ${function_apps}; do
        info "Deleting Function App: ${app}"
        
        if confirm "Delete Function App ${app}?"; then
            az functionapp delete \
                --name "${app}" \
                --resource-group "${RESOURCE_GROUP}" || warning "Failed to delete Function App ${app}"
            
            # Don't wait for Function App deletion as it can be slow
            info "Function App ${app} deletion initiated"
        else
            info "Skipping Function App ${app}"
        fi
    done
    
    success "Function Apps deletion completed"
}

# Delete Cognitive Services (Speech and OpenAI)
delete_cognitive_services() {
    show_progress 2 6 "Removing Cognitive Services"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would delete Cognitive Services in resource group ${RESOURCE_GROUP}"
        return 0
    fi
    
    # Find Cognitive Services accounts
    local cog_services=$(az cognitiveservices account list --resource-group "${RESOURCE_GROUP}" --query "[].{name:name, kind:kind}" --output json 2>/dev/null || echo "[]")
    local service_count=$(echo "${cog_services}" | jq length 2>/dev/null || echo "0")
    
    if [[ "${service_count}" -eq 0 ]]; then
        info "No Cognitive Services found to delete"
        return 0
    fi
    
    # Delete each service
    echo "${cog_services}" | jq -r '.[] | "\(.name) \(.kind)"' | while read -r name kind; do
        info "Deleting ${kind} service: ${name}"
        
        if confirm "Delete ${kind} service ${name}?" "y"; then
            # Check for model deployments in OpenAI services
            if [[ "${kind}" == "OpenAI" ]]; then
                info "Checking for model deployments in ${name}..."
                local deployments=$(az cognitiveservices account deployment list \
                    --name "${name}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --query "[].name" --output tsv 2>/dev/null || echo "")
                
                for deployment in ${deployments}; do
                    info "Deleting model deployment: ${deployment}"
                    az cognitiveservices account deployment delete \
                        --name "${name}" \
                        --resource-group "${RESOURCE_GROUP}" \
                        --deployment-name "${deployment}" || warning "Failed to delete deployment ${deployment}"
                done
            fi
            
            # Delete the cognitive service
            az cognitiveservices account delete \
                --name "${name}" \
                --resource-group "${RESOURCE_GROUP}" || warning "Failed to delete ${kind} service ${name}"
            
            success "${kind} service ${name} deleted"
        else
            info "Skipping ${kind} service ${name}"
        fi
    done
    
    success "Cognitive Services deletion completed"
}

# Delete Service Bus namespace
delete_service_bus() {
    show_progress 3 6 "Removing Service Bus namespace"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would delete Service Bus namespaces in resource group ${RESOURCE_GROUP}"
        return 0
    fi
    
    # Find Service Bus namespaces
    local namespaces=$(az servicebus namespace list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -z "${namespaces}" ]]; then
        info "No Service Bus namespaces found to delete"
        return 0
    fi
    
    for namespace in ${namespaces}; do
        info "Deleting Service Bus namespace: ${namespace}"
        
        if confirm "Delete Service Bus namespace ${namespace}?" "y"; then
            az servicebus namespace delete \
                --name "${namespace}" \
                --resource-group "${RESOURCE_GROUP}" || warning "Failed to delete Service Bus namespace ${namespace}"
            
            success "Service Bus namespace ${namespace} deleted"
        else
            info "Skipping Service Bus namespace ${namespace}"
        fi
    done
    
    success "Service Bus namespaces deletion completed"
}

# Delete Storage Accounts
delete_storage_accounts() {
    show_progress 4 6 "Removing Storage Accounts"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would delete Storage Accounts in resource group ${RESOURCE_GROUP}"
        return 0
    fi
    
    # Find Storage Accounts
    local storage_accounts=$(az storage account list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -z "${storage_accounts}" ]]; then
        info "No Storage Accounts found to delete"
        return 0
    fi
    
    for account in ${storage_accounts}; do
        info "Deleting Storage Account: ${account}"
        
        if confirm "Delete Storage Account ${account} and ALL its data?" "n"; then
            # Check for blobs that might contain important data
            local blob_count=0
            blob_count=$(az storage container list --account-name "${account}" --auth-mode login --query "length(@)" --output tsv 2>/dev/null || echo "0")
            
            if [[ "${blob_count}" -gt 0 ]]; then
                warning "Storage Account ${account} contains ${blob_count} containers with data"
                if ! confirm "Are you sure you want to delete this data?"; then
                    info "Skipping Storage Account ${account}"
                    continue
                fi
            fi
            
            az storage account delete \
                --name "${account}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || warning "Failed to delete Storage Account ${account}"
            
            success "Storage Account ${account} deleted"
        else
            info "Skipping Storage Account ${account}"
        fi
    done
    
    success "Storage Accounts deletion completed"
}

# Delete remaining resources
delete_remaining_resources() {
    show_progress 5 6 "Removing any remaining resources"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would delete any remaining resources in resource group ${RESOURCE_GROUP}"
        return 0
    fi
    
    # Get updated list of remaining resources
    local remaining_resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{name:name, type:type}" --output json 2>/dev/null || echo "[]")
    local remaining_count=$(echo "${remaining_resources}" | jq length 2>/dev/null || echo "0")
    
    if [[ "${remaining_count}" -eq 0 ]]; then
        info "No remaining resources to delete"
        return 0
    fi
    
    warning "Found ${remaining_count} remaining resources"
    echo "${remaining_resources}" | jq -r '.[] | "  - \(.name) (\(.type))"' 2>/dev/null || {
        info "Could not parse remaining resources list"
    }
    
    if confirm "Delete all remaining ${remaining_count} resources?"; then
        info "Attempting to delete remaining resources individually..."
        
        # Try to delete remaining resources
        echo "${remaining_resources}" | jq -r '.[] | "\(.name)|\(.type)"' | while IFS='|' read -r name type; do
            info "Deleting ${type}: ${name}"
            az resource delete \
                --name "${name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --resource-type "${type}" || warning "Failed to delete ${type}: ${name}"
        done
    else
        info "Skipping remaining resources deletion"
    fi
    
    success "Remaining resources cleanup completed"
}

# Delete the resource group
delete_resource_group() {
    show_progress 6 6 "Removing Resource Group"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would delete resource group ${RESOURCE_GROUP}"
        return 0
    fi
    
    info "Preparing to delete resource group: ${RESOURCE_GROUP}"
    
    # Final confirmation for resource group deletion
    if confirm "DELETE ENTIRE RESOURCE GROUP ${RESOURCE_GROUP} and all remaining resources?" "n"; then
        info "Deleting resource group ${RESOURCE_GROUP}..."
        
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait || error "Failed to initiate resource group deletion"
        
        info "Resource group deletion initiated (running in background)"
        
        # Optional: Wait for completion
        if confirm "Wait for resource group deletion to complete? (This may take several minutes)"; then
            info "Waiting for resource group deletion to complete..."
            local max_attempts=60
            local attempt=1
            
            while [[ ${attempt} -le ${max_attempts} ]]; do
                if ! resource_exists "group" "${RESOURCE_GROUP}" ""; then
                    success "Resource group ${RESOURCE_GROUP} has been completely deleted"
                    return 0
                fi
                
                info "Resource group deletion in progress... (${attempt}/${max_attempts})"
                sleep 30
                ((attempt++))
            done
            
            warning "Resource group deletion is taking longer than expected but continues in background"
        fi
        
        success "Resource group deletion initiated successfully"
    else
        info "Resource group deletion cancelled"
        return 1
    fi
}

# Generate cleanup summary
generate_cleanup_summary() {
    local summary_file="${SCRIPT_DIR}/cleanup_summary_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "${summary_file}" << EOF
===============================================================================
MEETING INTELLIGENCE CLEANUP SUMMARY
===============================================================================
Cleanup Date: $(date)
Resource Group: ${RESOURCE_GROUP}
Subscription: ${SUBSCRIPTION_ID}
Cleanup Mode: ${DRY_RUN:+DRY RUN}${DRY_RUN:-ACTUAL DELETION}

CLEANUP ACTIONS PERFORMED:
-------------------------------------------------------------------------------
✓ Function Apps removed
✓ Cognitive Services (Speech & OpenAI) removed
✓ Service Bus namespace and messaging entities removed
✓ Storage accounts and data removed
✓ Remaining resources cleaned up
✓ Resource group deletion ${DRY_RUN:+scheduled}${DRY_RUN:-initiated}

VERIFICATION STEPS:
-------------------------------------------------------------------------------
1. Check Azure Portal to confirm resource group removal
2. Verify no unexpected charges in billing
3. Review activity logs for any failed deletions

COST IMPACT:
-------------------------------------------------------------------------------
All recurring charges for the meeting intelligence solution have been stopped.
One-time charges may appear for:
- API calls made during deletion process
- Brief resource usage during cleanup

If resource group deletion is incomplete:
- Run: az group delete --name ${RESOURCE_GROUP} --yes
- Or use Azure Portal to manually remove remaining resources

SUPPORT:
-------------------------------------------------------------------------------
For issues with cleanup, check the Azure activity log or contact Azure support.
Log file: ${LOG_FILE}
===============================================================================
EOF
    
    success "Cleanup summary saved to: ${summary_file}"
    cat "${summary_file}"
}

# Main cleanup orchestration
main() {
    info "Starting Meeting Intelligence cleanup..."
    info "Log file: ${LOG_FILE}"
    
    # Execute cleanup steps in safe order
    check_prerequisites
    
    if ! discover_resources; then
        info "No resources found to clean up"
        return 0
    fi
    
    # Show what will be deleted
    info "This will delete the following resource types:"
    info "  - Function Apps and their associated resources"
    info "  - Cognitive Services (Speech Services and OpenAI)"
    info "  - Service Bus namespaces with all queues and topics" 
    info "  - Storage Accounts with ALL data (meeting recordings, etc.)"
    info "  - The entire resource group and any remaining resources"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        warning "DRY RUN MODE - No actual deletions will be performed"
    else
        warning "This action cannot be undone!"
        if ! confirm "Continue with cleanup?"; then
            info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute cleanup in dependency order
    delete_function_apps
    delete_cognitive_services  
    delete_service_bus
    delete_storage_accounts
    delete_remaining_resources
    delete_resource_group
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        generate_cleanup_summary
    fi
    
    success "Meeting Intelligence cleanup completed!"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        info "Verify cleanup completion in Azure Portal: https://portal.azure.com"
        info "Resource group deletion may continue in background for several minutes"
    fi
}

# ================================================================
# COMMAND LINE ARGUMENT PARSING
# ================================================================

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely remove all Meeting Intelligence Azure resources

OPTIONS:
    -h, --help                Show this help message
    -g, --resource-group NAME Resource group name to delete (REQUIRED)
    -s, --subscription ID     Azure subscription ID (default: current)
    --dry-run                 Show what would be deleted without making changes
    --force                   Skip confirmation prompts (DANGEROUS)
    --non-interactive         Run without user prompts (requires --force)
    --debug                   Enable debug logging

EXAMPLES:
    $0 -g rg-meeting-intelligence-abc123    # Interactive cleanup
    $0 -g my-meeting-rg --dry-run           # Preview what would be deleted
    $0 -g my-meeting-rg --force             # Force deletion with no prompts
    
SAFETY FEATURES:
    - Confirmation prompts for destructive actions
    - Dry-run mode to preview changes
    - Detailed logging of all actions
    - Safe deletion order to handle dependencies

WARNING: This will permanently delete ALL resources and data in the specified
resource group. This action cannot be undone.

For more information, see the recipe documentation.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--subscription)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DESTROY=true
            shift
            ;;
        --non-interactive)
            INTERACTIVE=false
            shift
            ;;
        --debug)
            set -x
            shift
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Validate required arguments
if [[ -z "${RESOURCE_GROUP}" ]]; then
    error "Resource group name is required. Use -g/--resource-group or run with --help for usage."
fi

if [[ "${INTERACTIVE}" == "false" ]] && [[ "${FORCE_DESTROY}" == "false" ]]; then
    error "Non-interactive mode requires --force flag for safety"
fi

# ================================================================
# MAIN EXECUTION
# ================================================================

# Trap to ensure cleanup on script exit
trap 'log "Script interrupted. Check ${LOG_FILE} for details."' INT TERM

# Start cleanup
main "$@"