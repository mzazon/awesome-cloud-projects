#!/bin/bash

# Azure Multi-Modal Content Processing Workflow - Cleanup Script
# This script safely removes all resources created for the content processing workflow

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "Prerequisites check completed"
}

# Function to set default values and validate inputs
set_defaults() {
    log "Setting default values..."
    
    # Set default values or use environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-content-processing-demo}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    # Try to detect resources if suffix not provided
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        log "Attempting to detect existing resources..."
        
        # Try to find existing resources by pattern
        local storage_accounts=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[?starts_with(name, 'stcontentproc')].name" -o tsv 2>/dev/null || echo "")
        local event_hubs=$(az eventhubs namespace list --resource-group "$RESOURCE_GROUP" --query "[?starts_with(name, 'eh-content-proc-')].name" -o tsv 2>/dev/null || echo "")
        local cognitive_services=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[?starts_with(name, 'cs-text-analytics-')].name" -o tsv 2>/dev/null || echo "")
        local logic_apps=$(az logic workflow list --resource-group "$RESOURCE_GROUP" --query "[?starts_with(name, 'la-content-workflow-')].name" -o tsv 2>/dev/null || echo "")
        
        # Extract suffix from first found resource
        if [ -n "$storage_accounts" ]; then
            export RANDOM_SUFFIX=$(echo "$storage_accounts" | head -1 | sed 's/stcontentproc//')
        elif [ -n "$event_hubs" ]; then
            export RANDOM_SUFFIX=$(echo "$event_hubs" | head -1 | sed 's/eh-content-proc-//')
        elif [ -n "$cognitive_services" ]; then
            export RANDOM_SUFFIX=$(echo "$cognitive_services" | head -1 | sed 's/cs-text-analytics-//')
        elif [ -n "$logic_apps" ]; then
            export RANDOM_SUFFIX=$(echo "$logic_apps" | head -1 | sed 's/la-content-workflow-//')
        else
            warning "No existing resources found. Using empty suffix."
            export RANDOM_SUFFIX=""
        fi
        
        if [ -n "$RANDOM_SUFFIX" ]; then
            info "Detected resource suffix: $RANDOM_SUFFIX"
        fi
    fi
    
    # Set resource names
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stcontentproc${RANDOM_SUFFIX}}"
    export EVENT_HUB_NAMESPACE="${EVENT_HUB_NAMESPACE:-eh-content-proc-${RANDOM_SUFFIX}}"
    export COGNITIVE_SERVICE="${COGNITIVE_SERVICE:-cs-text-analytics-${RANDOM_SUFFIX}}"
    export LOGIC_APP="${LOGIC_APP:-la-content-workflow-${RANDOM_SUFFIX}}"
    
    info "Configuration:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    info "  Subscription ID: $SUBSCRIPTION_ID"
    info "  Random Suffix: $RANDOM_SUFFIX"
    info "  Storage Account: $STORAGE_ACCOUNT"
    info "  Event Hub Namespace: $EVENT_HUB_NAMESPACE"
    info "  Cognitive Service: $COGNITIVE_SERVICE"
    info "  Logic App: $LOGIC_APP"
}

# Function to confirm deletion
confirm_deletion() {
    if [ "${FORCE_DELETE:-false}" = "true" ]; then
        log "Force delete mode enabled. Skipping confirmation."
        return 0
    fi
    
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    warning "This script will permanently delete the following resources:"
    warning "  - Resource Group: $RESOURCE_GROUP"
    warning "  - Storage Account: $STORAGE_ACCOUNT (and ALL data)"
    warning "  - Event Hub Namespace: $EVENT_HUB_NAMESPACE"
    warning "  - Cognitive Service: $COGNITIVE_SERVICE"
    warning "  - Logic App: $LOGIC_APP"
    warning "  - All API connections"
    warning "  - All processed data and configurations"
    echo ""
    
    read -p "Are you sure you want to continue? (Type 'DELETE' to confirm): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log "Operation cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed. Proceeding with cleanup..."
}

# Function to check if resource group exists
check_resource_group() {
    log "Checking if resource group exists..."
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group $RESOURCE_GROUP does not exist. Nothing to clean up."
        exit 0
    fi
    
    log "Resource group $RESOURCE_GROUP found"
}

# Function to list resources to be deleted
list_resources() {
    log "Listing resources to be deleted..."
    
    echo ""
    echo "=== RESOURCES TO BE DELETED ==="
    
    # List all resources in the resource group
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null || echo "No resources found")
    
    if [ "$resources" != "No resources found" ]; then
        echo "$resources"
    else
        warning "No resources found in resource group $RESOURCE_GROUP"
    fi
    
    echo "================================"
    echo ""
}

# Function to delete Logic App and connections
delete_logic_app() {
    log "Deleting Logic App and connections..."
    
    # Delete Logic App
    if az logic workflow show --name "$LOGIC_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        info "Deleting Logic App: $LOGIC_APP"
        az logic workflow delete \
            --name "$LOGIC_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        
        if [ $? -eq 0 ]; then
            log "✅ Logic App $LOGIC_APP deleted successfully"
        else
            error "❌ Failed to delete Logic App $LOGIC_APP"
        fi
    else
        info "Logic App $LOGIC_APP not found. Skipping."
    fi
    
    # Delete API connections
    local connections=("eventhub-connection" "cognitiveservices-connection" "azureblob-connection")
    
    for connection in "${connections[@]}"; do
        if az resource show --resource-group "$RESOURCE_GROUP" --resource-type Microsoft.Web/connections --name "$connection" &> /dev/null; then
            info "Deleting API connection: $connection"
            az resource delete \
                --resource-group "$RESOURCE_GROUP" \
                --resource-type Microsoft.Web/connections \
                --name "$connection"
            
            if [ $? -eq 0 ]; then
                log "✅ API connection $connection deleted successfully"
            else
                error "❌ Failed to delete API connection $connection"
            fi
        else
            info "API connection $connection not found. Skipping."
        fi
    done
    
    log "Logic App and connections cleanup completed"
}

# Function to delete Event Hubs resources
delete_event_hubs() {
    log "Deleting Event Hubs resources..."
    
    if az eventhubs namespace show --name "$EVENT_HUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        info "Deleting Event Hub namespace: $EVENT_HUB_NAMESPACE"
        
        # Delete Event Hub namespace (this will delete all hubs and authorization rules)
        az eventhubs namespace delete \
            --name "$EVENT_HUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP"
        
        if [ $? -eq 0 ]; then
            log "✅ Event Hub namespace $EVENT_HUB_NAMESPACE deleted successfully"
        else
            error "❌ Failed to delete Event Hub namespace $EVENT_HUB_NAMESPACE"
        fi
    else
        info "Event Hub namespace $EVENT_HUB_NAMESPACE not found. Skipping."
    fi
    
    log "Event Hubs resources cleanup completed"
}

# Function to delete Cognitive Services
delete_cognitive_services() {
    log "Deleting Cognitive Services resources..."
    
    if az cognitiveservices account show --name "$COGNITIVE_SERVICE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        info "Deleting Cognitive Services resource: $COGNITIVE_SERVICE"
        
        az cognitiveservices account delete \
            --name "$COGNITIVE_SERVICE" \
            --resource-group "$RESOURCE_GROUP"
        
        if [ $? -eq 0 ]; then
            log "✅ Cognitive Services resource $COGNITIVE_SERVICE deleted successfully"
        else
            error "❌ Failed to delete Cognitive Services resource $COGNITIVE_SERVICE"
        fi
    else
        info "Cognitive Services resource $COGNITIVE_SERVICE not found. Skipping."
    fi
    
    log "Cognitive Services resources cleanup completed"
}

# Function to delete storage account
delete_storage_account() {
    log "Deleting storage account..."
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        info "Deleting storage account: $STORAGE_ACCOUNT"
        warning "This will permanently delete all data in the storage account"
        
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        
        if [ $? -eq 0 ]; then
            log "✅ Storage account $STORAGE_ACCOUNT deleted successfully"
        else
            error "❌ Failed to delete storage account $STORAGE_ACCOUNT"
        fi
    else
        info "Storage account $STORAGE_ACCOUNT not found. Skipping."
    fi
    
    log "Storage account cleanup completed"
}

# Function to delete any remaining resources
delete_remaining_resources() {
    log "Checking for any remaining resources..."
    
    # Get list of remaining resources
    local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output tsv 2>/dev/null || echo "")
    
    if [ -n "$remaining_resources" ]; then
        warning "Found remaining resources:"
        echo "$remaining_resources"
        
        # Delete each remaining resource
        while IFS=$'\t' read -r name type; do
            if [ -n "$name" ] && [ -n "$type" ]; then
                info "Deleting remaining resource: $name ($type)"
                az resource delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$name" \
                    --resource-type "$type" \
                    --verbose
                
                if [ $? -eq 0 ]; then
                    log "✅ Resource $name deleted successfully"
                else
                    error "❌ Failed to delete resource $name"
                fi
            fi
        done <<< "$remaining_resources"
    else
        log "No remaining resources found"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group..."
    
    if [ "${DELETE_RESOURCE_GROUP:-true}" = "true" ]; then
        info "Deleting resource group: $RESOURCE_GROUP"
        warning "This will permanently delete the resource group and any remaining resources"
        
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        
        if [ $? -eq 0 ]; then
            log "✅ Resource group $RESOURCE_GROUP deletion initiated"
            log "Note: Complete deletion may take several minutes"
        else
            error "❌ Failed to delete resource group $RESOURCE_GROUP"
        fi
    else
        info "Skipping resource group deletion (DELETE_RESOURCE_GROUP=false)"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # List of temporary files that might have been created
    local temp_files=(
        "/tmp/workflow-definition.json"
        "/tmp/test_content.py"
        "/tmp/deployment-info.json"
        "/tmp/azure-cleanup.log"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -f "$file" ]; then
            info "Removing temporary file: $file"
            rm -f "$file"
        fi
    done
    
    log "Local files cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group $RESOURCE_GROUP still exists"
        
        # List any remaining resources
        local remaining=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [ -n "$remaining" ]; then
            warning "Remaining resources:"
            echo "$remaining"
        else
            info "Resource group exists but contains no resources"
        fi
    else
        log "✅ Resource group $RESOURCE_GROUP has been deleted"
    fi
    
    # Check specific resources
    local resources_to_check=(
        "$STORAGE_ACCOUNT:storage account"
        "$EVENT_HUB_NAMESPACE:event hub namespace"
        "$COGNITIVE_SERVICE:cognitive service"
        "$LOGIC_APP:logic app"
    )
    
    for resource_info in "${resources_to_check[@]}"; do
        IFS=':' read -r resource_name resource_type <<< "$resource_info"
        
        case "$resource_type" in
            "storage account")
                if az storage account show --name "$resource_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                    warning "Storage account $resource_name still exists"
                else
                    log "✅ Storage account $resource_name has been deleted"
                fi
                ;;
            "event hub namespace")
                if az eventhubs namespace show --name "$resource_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                    warning "Event Hub namespace $resource_name still exists"
                else
                    log "✅ Event Hub namespace $resource_name has been deleted"
                fi
                ;;
            "cognitive service")
                if az cognitiveservices account show --name "$resource_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                    warning "Cognitive Service $resource_name still exists"
                else
                    log "✅ Cognitive Service $resource_name has been deleted"
                fi
                ;;
            "logic app")
                if az logic workflow show --name "$resource_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                    warning "Logic App $resource_name still exists"
                else
                    log "✅ Logic App $resource_name has been deleted"
                fi
                ;;
        esac
    done
    
    log "Cleanup verification completed"
}

# Function to save cleanup summary
save_cleanup_summary() {
    log "Saving cleanup summary..."
    
    local summary_file="/tmp/cleanup-summary.json"
    
    cat > "$summary_file" << EOF
{
    "cleanup_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "resource_group": "$RESOURCE_GROUP",
    "location": "$LOCATION",
    "subscription_id": "$SUBSCRIPTION_ID",
    "random_suffix": "$RANDOM_SUFFIX",
    "deleted_resources": {
        "storage_account": "$STORAGE_ACCOUNT",
        "event_hub_namespace": "$EVENT_HUB_NAMESPACE",
        "cognitive_service": "$COGNITIVE_SERVICE",
        "logic_app": "$LOGIC_APP"
    },
    "cleanup_status": "completed"
}
EOF
    
    log "Cleanup summary saved to $summary_file"
    
    # Display summary
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    echo "Cleanup completed at: $(date)"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo ""
    echo "Deleted Resources:"
    echo "  - Storage Account: $STORAGE_ACCOUNT"
    echo "  - Event Hub Namespace: $EVENT_HUB_NAMESPACE"
    echo "  - Cognitive Service: $COGNITIVE_SERVICE"
    echo "  - Logic App: $LOGIC_APP"
    echo "  - All API connections"
    echo ""
    echo "Status: All resources have been deleted"
    echo "Note: Some resources may take additional time to fully delete"
    echo "======================="
}

# Main cleanup function
main() {
    log "Starting Azure Multi-Modal Content Processing Workflow cleanup..."
    
    # Check if dry run mode
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log "DRY RUN MODE: No actual resources will be deleted"
        check_prerequisites
        set_defaults
        check_resource_group
        list_resources
        exit 0
    fi
    
    # Run all cleanup steps
    check_prerequisites
    set_defaults
    check_resource_group
    list_resources
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_logic_app
    delete_event_hubs
    delete_cognitive_services
    delete_storage_account
    delete_remaining_resources
    delete_resource_group
    
    cleanup_local_files
    verify_cleanup
    save_cleanup_summary
    
    log "✅ Cleanup completed successfully!"
    log "All Azure Multi-Modal Content Processing Workflow resources have been deleted"
    
    # Clean up the summary file
    rm -f /tmp/cleanup-summary.json
}

# Handle script interruption
trap 'error "Cleanup interrupted"; exit 1' INT TERM

# Display usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run              Show what would be deleted without actually deleting"
    echo "  --force                Skip confirmation prompts"
    echo "  --keep-rg              Keep the resource group after deleting resources"
    echo "  --help                 Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP         Resource group name (default: rg-content-processing-demo)"
    echo "  RANDOM_SUFFIX          Resource name suffix (auto-detected if not provided)"
    echo "  FORCE_DELETE           Set to 'true' to skip confirmation (default: false)"
    echo "  DELETE_RESOURCE_GROUP  Set to 'false' to keep resource group (default: true)"
    echo "  DRY_RUN               Set to 'true' for dry run mode (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0                     # Interactive cleanup"
    echo "  $0 --dry-run           # Show what would be deleted"
    echo "  $0 --force             # Skip confirmation prompts"
    echo "  RESOURCE_GROUP=my-rg $0 # Use custom resource group"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            export DRY_RUN=true
            shift
            ;;
        --force)
            export FORCE_DELETE=true
            shift
            ;;
        --keep-rg)
            export DELETE_RESOURCE_GROUP=false
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@"