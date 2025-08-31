#!/bin/bash

# AI-Powered Email Marketing Campaigns with OpenAI and Logic Apps - Cleanup Script
# This script removes all Azure infrastructure created by the deployment script
# Usage: ./destroy.sh [--resource-group <name>] [--force] [--dry-run]

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default configuration
FORCE_DELETE=false
DRY_RUN=false
VERBOSE=false
RESOURCE_GROUP=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handler
error_exit() {
    log "ERROR" "Cleanup failed: $1"
    log "ERROR" "Check log file at: $LOG_FILE"
    exit 1
}

# Trap errors
trap 'error_exit "Unexpected error occurred at line $LINENO"' ERR

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up AI-Powered Email Marketing infrastructure from Azure

OPTIONS:
    -g, --resource-group NAME     Specific resource group to delete
    -f, --force                   Skip confirmation prompts
    -d, --dry-run                 Show what would be deleted without actually deleting
    -v, --verbose                 Enable verbose logging
    -h, --help                    Show this help message

EXAMPLES:
    $0                           # Delete resources from deployment state file
    $0 -g my-resource-group      # Delete specific resource group
    $0 --dry-run                 # Preview what would be deleted
    $0 --force                   # Skip confirmation prompts
    $0 --verbose                 # Enable detailed logging

SAFETY NOTES:
    - This script will permanently delete Azure resources
    - By default, you will be prompted to confirm deletion
    - Use --force to skip confirmation prompts (use with caution)
    - Use --dry-run to preview changes without making them

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Get and display subscription
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    log "INFO" "Using Azure subscription: $subscription_name ($subscription_id)"
    
    log "INFO" "Prerequisites check completed successfully"
}

# Load deployment state
load_deployment_state() {
    if [[ -n "$RESOURCE_GROUP" ]]; then
        log "INFO" "Using provided resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
        error_exit "Deployment state file not found: $DEPLOYMENT_STATE_FILE. Please provide --resource-group option."
    fi
    
    log "INFO" "Loading deployment state from: $DEPLOYMENT_STATE_FILE"
    source "$DEPLOYMENT_STATE_FILE"
    
    # Validate required variables
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        error_exit "Resource group not found in deployment state file"
    fi
    
    log "INFO" "Loaded deployment state:"
    log "DEBUG" "Resource Group: $RESOURCE_GROUP"
    log "DEBUG" "Location: ${LOCATION:-'Not specified'}"
    log "DEBUG" "Deployment Date: ${DEPLOYMENT_DATE:-'Not specified'}"
}

# Confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "=================================="
    echo "        DELETION WARNING"
    echo "=================================="
    echo "This will permanently delete:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  All contained resources"
    echo "=================================="
    echo ""
    
    # List resources that will be deleted
    log "INFO" "Checking resources in resource group..."
    if az group exists --name "$RESOURCE_GROUP" 2>/dev/null; then
        local resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")
        if [[ "$resource_count" -gt 0 ]]; then
            echo "Resources to be deleted:"
            az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null || echo "Unable to list resources"
            echo ""
        else
            log "WARN" "No resources found in resource group $RESOURCE_GROUP"
        fi
    else
        log "WARN" "Resource group $RESOURCE_GROUP does not exist"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "INFO" "Deletion cancelled by user"
        exit 0
    fi
    
    read -p "Please type the resource group name to confirm: " -r
    if [[ "$REPLY" != "$RESOURCE_GROUP" ]]; then
        log "ERROR" "Resource group name does not match. Deletion cancelled."
        exit 1
    fi
    
    log "INFO" "User confirmed deletion of resource group: $RESOURCE_GROUP"
}

# Check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local resource_group=${3:-$RESOURCE_GROUP}
    
    case $resource_type in
        "group")
            az group exists --name "$resource_name" 2>/dev/null || echo "false"
            ;;
        "openai")
            az cognitiveservices account show --name "$resource_name" --resource-group "$resource_group" &>/dev/null && echo "true" || echo "false"
            ;;
        "functionapp")
            az functionapp show --name "$resource_name" --resource-group "$resource_group" &>/dev/null && echo "true" || echo "false"
            ;;
        "communication")
            az communication show --name "$resource_name" --resource-group "$resource_group" &>/dev/null && echo "true" || echo "false"
            ;;
        "email")
            az communication email show --name "$resource_name" --resource-group "$resource_group" &>/dev/null && echo "true" || echo "false"
            ;;
        "storage")
            az storage account show --name "$resource_name" --resource-group "$resource_group" &>/dev/null && echo "true" || echo "false"
            ;;
        *)
            echo "false"
            ;;
    esac
}

# Delete individual resources (for granular cleanup if needed)
delete_individual_resources() {
    log "INFO" "Attempting granular resource cleanup..."
    
    # Load deployment state variables if available
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        source "$DEPLOYMENT_STATE_FILE" 2>/dev/null || true
    fi
    
    # Delete Function App (Logic Apps)
    if [[ -n "${LOGIC_APP_NAME:-}" ]] && [[ "$(resource_exists functionapp "$LOGIC_APP_NAME")" == "true" ]]; then
        log "INFO" "Deleting Function App: $LOGIC_APP_NAME"
        if [[ "$DRY_RUN" == "false" ]]; then
            az functionapp delete --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP" || log "WARN" "Failed to delete Function App"
        else
            log "INFO" "[DRY-RUN] Would delete Function App: $LOGIC_APP_NAME"
        fi
    fi
    
    # Delete Communication Services Email Domain
    if [[ -n "${EMAIL_SERVICE_NAME:-}" ]]; then
        log "INFO" "Deleting email domain: AzureManagedDomain"
        if [[ "$DRY_RUN" == "false" ]]; then
            az communication email domain delete \
                --domain-name "AzureManagedDomain" \
                --resource-group "$RESOURCE_GROUP" \
                --email-service-name "$EMAIL_SERVICE_NAME" \
                --yes 2>/dev/null || log "WARN" "Failed to delete email domain"
        else
            log "INFO" "[DRY-RUN] Would delete email domain: AzureManagedDomain"
        fi
    fi
    
    # Delete Email Communication Service
    if [[ -n "${EMAIL_SERVICE_NAME:-}" ]] && [[ "$(resource_exists email "$EMAIL_SERVICE_NAME")" == "true" ]]; then
        log "INFO" "Deleting Email Communication Service: $EMAIL_SERVICE_NAME"
        if [[ "$DRY_RUN" == "false" ]]; then
            az communication email delete --name "$EMAIL_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --yes || log "WARN" "Failed to delete Email Service"
        else
            log "INFO" "[DRY-RUN] Would delete Email Service: $EMAIL_SERVICE_NAME"
        fi
    fi
    
    # Delete Communication Services
    if [[ -n "${COMMUNICATION_SERVICE_NAME:-}" ]] && [[ "$(resource_exists communication "$COMMUNICATION_SERVICE_NAME")" == "true" ]]; then
        log "INFO" "Deleting Communication Services: $COMMUNICATION_SERVICE_NAME"
        if [[ "$DRY_RUN" == "false" ]]; then
            az communication delete --name "$COMMUNICATION_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --yes || log "WARN" "Failed to delete Communication Services"
        else
            log "INFO" "[DRY-RUN] Would delete Communication Services: $COMMUNICATION_SERVICE_NAME"
        fi
    fi
    
    # Delete OpenAI model deployment first
    if [[ -n "${OPENAI_SERVICE_NAME:-}" ]] && [[ "$(resource_exists openai "$OPENAI_SERVICE_NAME")" == "true" ]]; then
        log "INFO" "Deleting OpenAI model deployment: gpt-4o-marketing"
        if [[ "$DRY_RUN" == "false" ]]; then
            az cognitiveservices account deployment delete \
                --name "$OPENAI_SERVICE_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --deployment-name gpt-4o-marketing 2>/dev/null || log "WARN" "Failed to delete model deployment"
        else
            log "INFO" "[DRY-RUN] Would delete model deployment: gpt-4o-marketing"
        fi
    fi
    
    # Delete OpenAI Service
    if [[ -n "${OPENAI_SERVICE_NAME:-}" ]] && [[ "$(resource_exists openai "$OPENAI_SERVICE_NAME")" == "true" ]]; then
        log "INFO" "Deleting OpenAI Service: $OPENAI_SERVICE_NAME"
        if [[ "$DRY_RUN" == "false" ]]; then
            az cognitiveservices account delete --name "$OPENAI_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" --yes || log "WARN" "Failed to delete OpenAI Service"
        else
            log "INFO" "[DRY-RUN] Would delete OpenAI Service: $OPENAI_SERVICE_NAME"
        fi
    fi
    
    # Delete Storage Account
    if [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]] && [[ "$(resource_exists storage "$STORAGE_ACCOUNT_NAME")" == "true" ]]; then
        log "INFO" "Deleting Storage Account: $STORAGE_ACCOUNT_NAME"
        if [[ "$DRY_RUN" == "false" ]]; then
            az storage account delete --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" --yes || log "WARN" "Failed to delete Storage Account"
        else
            log "INFO" "[DRY-RUN] Would delete Storage Account: $STORAGE_ACCOUNT_NAME"
        fi
    fi
    
    log "INFO" "Granular resource cleanup completed"
}

# Delete resource group (primary cleanup method)
delete_resource_group() {
    log "INFO" "Deleting resource group: $RESOURCE_GROUP"
    
    # Check if resource group exists
    if [[ "$(resource_exists group "$RESOURCE_GROUP")" != "true" ]]; then
        log "WARN" "Resource group $RESOURCE_GROUP does not exist"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would delete resource group: $RESOURCE_GROUP and all contained resources"
        
        # Show what would be deleted
        local resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")
        if [[ "$resource_count" -gt 0 ]]; then
            log "INFO" "[DRY-RUN] Resources that would be deleted:"
            az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output table 2>/dev/null || log "WARN" "Unable to list resources"
        fi
        return 0
    fi
    
    # Get resource count before deletion
    local resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")
    log "INFO" "Found $resource_count resources in resource group"
    
    # Attempt fast deletion (delete entire resource group)
    log "INFO" "Attempting to delete resource group (this may take several minutes)..."
    
    # Start async deletion
    if az group delete --name "$RESOURCE_GROUP" --yes --no-wait; then
        log "INFO" "Resource group deletion initiated successfully"
        
        # Wait for deletion to complete (with timeout)
        log "INFO" "Waiting for resource group deletion to complete..."
        local max_wait=600  # 10 minutes
        local wait_time=0
        local check_interval=30
        
        while [[ $wait_time -lt $max_wait ]]; do
            if [[ "$(resource_exists group "$RESOURCE_GROUP")" != "true" ]]; then
                log "INFO" "✅ Resource group deleted successfully"
                break
            fi
            
            log "DEBUG" "Resource group still exists, waiting... ($wait_time/$max_wait seconds)"
            sleep $check_interval
            wait_time=$((wait_time + check_interval))
        done
        
        if [[ $wait_time -ge $max_wait ]]; then
            log "WARN" "Resource group deletion is taking longer than expected"
            log "WARN" "Deletion may still be in progress. Check Azure Portal for status."
        fi
    else
        log "ERROR" "Failed to initiate resource group deletion"
        log "INFO" "Attempting granular resource cleanup..."
        delete_individual_resources
    fi
}

# Cleanup deployment state file
cleanup_deployment_state() {
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]] && [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "Removing deployment state file"
        rm -f "$DEPLOYMENT_STATE_FILE" || log "WARN" "Failed to remove deployment state file"
    elif [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would remove deployment state file: $DEPLOYMENT_STATE_FILE"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log "INFO" "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if [[ "$(resource_exists group "$RESOURCE_GROUP")" == "true" ]]; then
        # List remaining resources
        local remaining_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")
        if [[ "$remaining_count" -gt 0 ]]; then
            log "WARN" "Resource group still contains $remaining_count resources"
            log "INFO" "Remaining resources:"
            az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, State:properties.provisioningState}" --output table 2>/dev/null || true
            log "WARN" "Some resources may still be deleting. Check Azure Portal for current status."
        else
            log "INFO" "Resource group exists but contains no resources"
        fi
    else
        log "INFO" "✅ Resource group successfully deleted"
    fi
}

# Display cleanup summary
display_summary() {
    echo ""
    echo "=================================="
    echo "      CLEANUP SUMMARY"
    echo "=================================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN COMPLETED"
        echo "No resources were actually deleted"
        echo "Run without --dry-run to perform actual cleanup"
    else
        echo "CLEANUP COMPLETED"
        echo "Resource Group: $RESOURCE_GROUP"
        
        if [[ "$(resource_exists group "$RESOURCE_GROUP")" == "true" ]]; then
            echo "Status: Deletion in progress or incomplete"
            echo "Check Azure Portal for current status"
        else
            echo "Status: Successfully deleted"
        fi
        
        echo ""
        echo "Deployment state file: ${DEPLOYMENT_STATE_FILE}"
        if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
            echo "State file status: Not removed (manual cleanup required)"
        else
            echo "State file status: Successfully removed"
        fi
    fi
    
    echo "=================================="
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "Cleanup process completed at $(date)"
        log "INFO" "If any resources remain, they may still be deleting or require manual cleanup"
    fi
}

# Main execution
main() {
    echo "AI-Powered Email Marketing Campaigns - Cleanup Script"
    echo "====================================================="
    echo ""
    
    # Initialize logging
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_state
    confirm_deletion
    
    # Perform cleanup
    delete_resource_group
    cleanup_deployment_state
    verify_cleanup
    
    display_summary
    
    log "INFO" "Cleanup script completed at $(date)"
}

# Execute main function with all arguments
main "$@"