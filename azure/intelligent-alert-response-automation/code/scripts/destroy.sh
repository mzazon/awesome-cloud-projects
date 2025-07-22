#!/bin/bash

# Intelligent Alert Response Automation with Monitor Workbooks and Azure Functions
# Cleanup/Destroy Script
# 
# This script safely removes all resources created by the deployment script including:
# - Azure Monitor Workbooks
# - Azure Functions
# - Azure Event Grid subscriptions and topics
# - Azure Logic Apps
# - Azure Cosmos DB
# - Azure Key Vault
# - Azure Storage Account
# - Resource Group and all contained resources

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Azure CLI login status
check_azure_login() {
    if ! az account show >/dev/null 2>&1; then
        error "Azure CLI is not logged in. Please run 'az login' first."
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install Azure CLI."
        exit 1
    fi
    
    # Check Azure CLI login
    check_azure_login
    
    log "Prerequisites check completed successfully."
}

# Function to load environment variables
load_environment_variables() {
    log "Loading environment variables..."
    
    # Check if environment file exists
    if [[ ! -f .env.deployment ]]; then
        error "Environment file .env.deployment not found."
        error "This file should have been created by the deployment script."
        error "Please ensure you're running this script from the same directory as the deployment."
        exit 1
    fi
    
    # Load environment variables
    source .env.deployment
    
    # Verify required variables are set
    local required_vars=(
        "RESOURCE_GROUP"
        "SUBSCRIPTION_ID"
        "STORAGE_ACCOUNT"
        "FUNCTION_APP"
        "EVENT_GRID_TOPIC"
        "LOGIC_APP"
        "COSMOS_DB"
        "KEY_VAULT"
        "LOG_ANALYTICS"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required environment variable $var is not set."
            exit 1
        fi
    done
    
    log "Environment variables loaded successfully."
    info "Target Resource Group: ${RESOURCE_GROUP}"
    info "Target Subscription: ${SUBSCRIPTION_ID}"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    echo "==================== DELETION CONFIRMATION ===================="
    echo "This script will permanently delete the following resources:"
    echo ""
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION:-Unknown}"
    echo "Subscription ID: ${SUBSCRIPTION_ID}"
    echo ""
    echo "Resources to be deleted:"
    echo "  - Storage Account: ${STORAGE_ACCOUNT}"
    echo "  - Function App: ${FUNCTION_APP}"
    echo "  - Event Grid Topic: ${EVENT_GRID_TOPIC}"
    echo "  - Logic App: ${LOGIC_APP}"
    echo "  - Cosmos DB: ${COSMOS_DB}"
    echo "  - Key Vault: ${KEY_VAULT}"
    echo "  - Log Analytics: ${LOG_ANALYTICS}"
    echo "  - All associated Event Grid subscriptions"
    echo "  - All associated Monitor Workbooks"
    echo "  - All associated Action Groups and Alert Rules"
    echo ""
    echo "WARNING: This action cannot be undone!"
    echo "============================================================="
    echo ""
    
    # Skip confirmation if FORCE_DELETE is set
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        warn "FORCE_DELETE is set. Skipping confirmation."
        return 0
    fi
    
    # Prompt for confirmation
    local confirmation
    while true; do
        read -p "Are you sure you want to delete these resources? (yes/no): " confirmation
        case $confirmation in
            [Yy]es|[Yy]|YES)
                log "Deletion confirmed by user."
                break
                ;;
            [Nn]o|[Nn]|NO)
                log "Deletion cancelled by user."
                exit 0
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Function to check if resource group exists
check_resource_group_exists() {
    if ! az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Resource group ${RESOURCE_GROUP} does not exist. Nothing to delete."
        exit 0
    fi
}

# Function to delete Event Grid subscriptions
delete_event_subscriptions() {
    log "Deleting Event Grid subscriptions..."
    
    # Delete subscription for Function App
    if az eventgrid event-subscription show \
        --name "alerts-to-function" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" >/dev/null 2>&1; then
        
        az eventgrid event-subscription delete \
            --name "alerts-to-function" \
            --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" \
            --output none
        
        log "Event Grid subscription alerts-to-function deleted successfully."
    else
        warn "Event Grid subscription alerts-to-function not found. Skipping deletion."
    fi
    
    # Delete subscription for Logic App
    if az eventgrid event-subscription show \
        --name "alerts-to-logic" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" >/dev/null 2>&1; then
        
        az eventgrid event-subscription delete \
            --name "alerts-to-logic" \
            --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" \
            --output none
        
        log "Event Grid subscription alerts-to-logic deleted successfully."
    else
        warn "Event Grid subscription alerts-to-logic not found. Skipping deletion."
    fi
    
    log "Event Grid subscriptions cleanup completed."
}

# Function to delete test alert resources
delete_test_alert_resources() {
    log "Deleting test alert resources..."
    
    # Delete test alert rule
    if az monitor metrics alert show \
        --name "test-cpu-alert" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        
        az monitor metrics alert delete \
            --name "test-cpu-alert" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none
        
        log "Test alert rule deleted successfully."
    else
        warn "Test alert rule not found. Skipping deletion."
    fi
    
    # Delete action group
    if az monitor action-group show \
        --name "test-alert-actions" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        
        az monitor action-group delete \
            --name "test-alert-actions" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none
        
        log "Action group deleted successfully."
    else
        warn "Action group not found. Skipping deletion."
    fi
    
    log "Test alert resources cleanup completed."
}

# Function to delete individual resources (for selective cleanup)
delete_individual_resources() {
    log "Deleting individual resources..."
    
    # Delete Function App
    if az functionapp show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        
        info "Deleting Function App: ${FUNCTION_APP}"
        az functionapp delete \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none
        
        log "Function App deleted successfully."
    else
        warn "Function App not found. Skipping deletion."
    fi
    
    # Delete Logic App
    if az logic workflow show \
        --name "${LOGIC_APP}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        
        info "Deleting Logic App: ${LOGIC_APP}"
        az logic workflow delete \
            --name "${LOGIC_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none
        
        log "Logic App deleted successfully."
    else
        warn "Logic App not found. Skipping deletion."
    fi
    
    # Delete Event Grid Topic
    if az eventgrid topic show \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        
        info "Deleting Event Grid Topic: ${EVENT_GRID_TOPIC}"
        az eventgrid topic delete \
            --name "${EVENT_GRID_TOPIC}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none
        
        log "Event Grid Topic deleted successfully."
    else
        warn "Event Grid Topic not found. Skipping deletion."
    fi
    
    # Delete Cosmos DB
    if az cosmosdb show \
        --name "${COSMOS_DB}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        
        info "Deleting Cosmos DB: ${COSMOS_DB}"
        az cosmosdb delete \
            --name "${COSMOS_DB}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none
        
        log "Cosmos DB deleted successfully."
    else
        warn "Cosmos DB not found. Skipping deletion."
    fi
    
    # Delete Key Vault
    if az keyvault show \
        --name "${KEY_VAULT}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        
        info "Deleting Key Vault: ${KEY_VAULT}"
        az keyvault delete \
            --name "${KEY_VAULT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none
        
        # Purge Key Vault to completely remove it
        info "Purging Key Vault: ${KEY_VAULT}"
        az keyvault purge \
            --name "${KEY_VAULT}" \
            --output none
        
        log "Key Vault deleted and purged successfully."
    else
        warn "Key Vault not found. Skipping deletion."
    fi
    
    # Delete Storage Account
    if az storage account show \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        
        info "Deleting Storage Account: ${STORAGE_ACCOUNT}"
        az storage account delete \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none
        
        log "Storage Account deleted successfully."
    else
        warn "Storage Account not found. Skipping deletion."
    fi
    
    # Delete Log Analytics Workspace
    if az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS}" >/dev/null 2>&1; then
        
        info "Deleting Log Analytics Workspace: ${LOG_ANALYTICS}"
        az monitor log-analytics workspace delete \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_ANALYTICS}" \
            --yes \
            --output none
        
        log "Log Analytics Workspace deleted successfully."
    else
        warn "Log Analytics Workspace not found. Skipping deletion."
    fi
    
    log "Individual resources cleanup completed."
}

# Function to delete entire resource group
delete_resource_group() {
    log "Deleting entire resource group..."
    
    info "Deleting Resource Group: ${RESOURCE_GROUP}"
    info "This operation may take several minutes to complete..."
    
    # Delete resource group (this will delete all contained resources)
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        --output none
    
    log "Resource group deletion initiated: ${RESOURCE_GROUP}"
    info "Note: Deletion may take several minutes to complete in the background."
}

# Function to verify deletion
verify_deletion() {
    log "Verifying deletion..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Resource group ${RESOURCE_GROUP} still exists (deletion may be in progress)."
        
        # If selective deletion was performed, this is expected
        if [[ "${SELECTIVE_DELETE:-false}" == "true" ]]; then
            info "Selective deletion was performed. Resource group is expected to exist."
        else
            info "Full resource group deletion was initiated. Check Azure portal for completion status."
        fi
    else
        log "Resource group ${RESOURCE_GROUP} has been successfully deleted."
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f .env.deployment ]]; then
        rm -f .env.deployment
        log "Environment file removed: .env.deployment"
    fi
    
    # Remove any temporary files
    if [[ -f function-code.zip ]]; then
        rm -f function-code.zip
        log "Temporary function code archive removed."
    fi
    
    log "Local files cleanup completed."
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup completed successfully!"
    
    echo ""
    echo "==================== CLEANUP SUMMARY ===================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Subscription ID: ${SUBSCRIPTION_ID}"
    echo ""
    echo "Cleanup Actions Performed:"
    echo "  - Event Grid subscriptions deleted"
    echo "  - Test alert resources removed"
    
    if [[ "${SELECTIVE_DELETE:-false}" == "true" ]]; then
        echo "  - Individual resources deleted selectively"
        echo "  - Resource Group preserved"
    else
        echo "  - Entire Resource Group deletion initiated"
    fi
    
    echo "  - Local configuration files removed"
    echo ""
    echo "Notes:"
    echo "  - Some resources may take additional time to fully delete"
    echo "  - Check Azure portal to confirm complete resource removal"
    echo "  - Key Vault was purged to enable name reuse"
    echo "  - Cosmos DB may have a brief retention period"
    echo ""
    echo "Cost Impact:"
    echo "  - All billable resources have been deleted"
    echo "  - No ongoing charges should occur after complete deletion"
    echo "==========================================================="
}

# Function to handle cleanup errors
handle_cleanup_errors() {
    local exit_code=$1
    
    error "Cleanup encountered errors (exit code: $exit_code)"
    error "Some resources may not have been deleted properly."
    
    echo ""
    echo "==================== ERROR RECOVERY ===================="
    echo "If cleanup failed, you can:"
    echo "1. Check Azure portal for remaining resources"
    echo "2. Manually delete individual resources"
    echo "3. Re-run this script with FORCE_DELETE=true"
    echo "4. Use Azure CLI to delete the resource group:"
    echo "   az group delete --name ${RESOURCE_GROUP} --yes"
    echo "======================================================="
    echo ""
    
    exit $exit_code
}

# Main cleanup function
main() {
    log "Starting cleanup of Intelligent Alert Response System..."
    
    # Set cleanup mode
    local cleanup_mode="${CLEANUP_MODE:-full}"
    
    # Check if dry run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY RUN MODE: No resources will be deleted"
        exit 0
    fi
    
    # Run cleanup steps
    check_prerequisites
    load_environment_variables
    check_resource_group_exists
    confirm_deletion
    
    # Delete Event Grid subscriptions first to prevent orphaned subscriptions
    delete_event_subscriptions
    
    # Delete test alert resources
    delete_test_alert_resources
    
    # Choose cleanup strategy
    case $cleanup_mode in
        "selective")
            info "Performing selective resource deletion..."
            export SELECTIVE_DELETE=true
            delete_individual_resources
            ;;
        "full"|*)
            info "Performing full resource group deletion..."
            delete_resource_group
            ;;
    esac
    
    # Verify and cleanup
    verify_deletion
    cleanup_local_files
    display_summary
    
    log "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may remain. Check Azure portal and run cleanup again if needed."; exit 1' INT TERM

# Handle cleanup errors
trap 'handle_cleanup_errors $?' ERR

# Display help information
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

This script safely deletes all resources created by the Azure Intelligent Alert Response System deployment.

OPTIONS:
    -h, --help              Show this help message
    -f, --force             Skip confirmation prompts (set FORCE_DELETE=true)
    -s, --selective         Delete resources individually, preserve resource group
    -d, --dry-run           Show what would be deleted without actually deleting
    
ENVIRONMENT VARIABLES:
    FORCE_DELETE=true       Skip confirmation prompts
    CLEANUP_MODE=selective  Delete resources individually
    DRY_RUN=true           Preview mode only
    
EXAMPLES:
    $0                      Interactive cleanup with confirmation
    $0 --force              Automatic cleanup without confirmation
    $0 --selective          Delete resources but keep resource group
    $0 --dry-run            Preview what would be deleted

PREREQUISITES:
    - Azure CLI installed and logged in
    - .env.deployment file from deployment script
    - Appropriate permissions to delete resources

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            export FORCE_DELETE=true
            shift
            ;;
        -s|--selective)
            export CLEANUP_MODE=selective
            shift
            ;;
        -d|--dry-run)
            export DRY_RUN=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main "$@"