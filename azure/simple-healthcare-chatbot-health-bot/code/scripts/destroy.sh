#!/bin/bash

# Azure Health Bot Cleanup Script  
# This script removes all resources created by the Health Bot deployment
# Generated for recipe: simple-healthcare-chatbot-health-bot

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "Prerequisites check completed successfully."
}

# Function to load deployment variables
load_deployment_variables() {
    log "Loading deployment variables..."
    
    if [[ -f .deployment_vars ]]; then
        # Source the variables file
        source .deployment_vars
        
        info "Loaded variables from previous deployment:"
        info "  Resource Group: ${RESOURCE_GROUP:-Not found}"
        info "  Health Bot Name: ${HEALTH_BOT_NAME:-Not found}"
        info "  Location: ${LOCATION:-Not found}"
        info "  Subscription: ${SUBSCRIPTION_ID:-Not found}"
        
        # Validate required variables are present
        if [[ -z "${RESOURCE_GROUP:-}" ]] || [[ -z "${HEALTH_BOT_NAME:-}" ]]; then
            warn "Some deployment variables are missing from .deployment_vars"
            return 1
        fi
        
        log "Successfully loaded deployment variables."
        return 0
    else
        warn "No .deployment_vars file found."
        return 1
    fi
}

# Function to prompt for manual variable input
prompt_for_variables() {
    log "Manual variable input required..."
    
    echo "Please provide the following information for cleanup:"
    
    # Prompt for resource group name
    read -p "Enter Resource Group name (e.g., rg-healthbot-abc123): " RESOURCE_GROUP
    if [[ -z "$RESOURCE_GROUP" ]]; then
        error "Resource Group name is required."
        exit 1
    fi
    
    # Prompt for Health Bot name
    read -p "Enter Health Bot name (e.g., healthbot-abc123): " HEALTH_BOT_NAME
    if [[ -z "$HEALTH_BOT_NAME" ]]; then
        error "Health Bot name is required."
        exit 1
    fi
    
    export RESOURCE_GROUP
    export HEALTH_BOT_NAME
    
    log "Manual variables configured:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Health Bot Name: $HEALTH_BOT_NAME"
}

# Function to get user confirmation for destructive actions
get_user_confirmation() {
    echo ""
    warn "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "  🗑️  Health Bot Service: ${HEALTH_BOT_NAME:-Unknown}"
    echo "  🗑️  Resource Group: ${RESOURCE_GROUP:-Unknown} (and ALL contained resources)"
    echo ""
    warn "This action cannot be undone!"
    echo ""
    
    # Require explicit confirmation
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    log "User confirmed deletion. Proceeding with cleanup..."
}

# Function to list resources before deletion
list_resources_for_deletion() {
    log "Listing resources that will be deleted..."
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        info "Resource group '$RESOURCE_GROUP' exists and contains:"
        
        # List all resources in the resource group
        az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].{Name:name, Type:type, Location:location}" \
            --output table 2>/dev/null || warn "Could not list resources in resource group"
    else
        warn "Resource group '$RESOURCE_GROUP' does not exist or is not accessible."
    fi
    
    echo ""
}

# Function to delete Health Bot service
delete_health_bot() {
    log "Deleting Health Bot service: $HEALTH_BOT_NAME"
    
    # Check if Health Bot exists
    if ! az healthbot show --name "$HEALTH_BOT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Health Bot '$HEALTH_BOT_NAME' does not exist or is already deleted."
        return 0
    fi
    
    # Delete Health Bot instance
    info "Deleting Health Bot instance (this may take a few minutes)..."
    az healthbot delete \
        --name "$HEALTH_BOT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --yes \
        --output table
    
    if [[ $? -eq 0 ]]; then
        # Wait for deletion to complete
        log "Waiting for Health Bot deletion to complete..."
        local timeout=300  # 5 minutes timeout
        local elapsed=0
        local interval=10
        
        while [[ $elapsed -lt $timeout ]]; do
            if ! az healthbot show --name "$HEALTH_BOT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                log "✅ Health Bot service deleted successfully"
                break
            fi
            
            info "Health Bot still exists (waiting ${interval}s...)"
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        if [[ $elapsed -ge $timeout ]]; then
            warn "Health Bot deletion verification timed out, but deletion command was issued"
        fi
    else
        error "Failed to delete Health Bot service: $HEALTH_BOT_NAME"
        error "You may need to delete it manually in the Azure portal"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group: $RESOURCE_GROUP"
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group '$RESOURCE_GROUP' does not exist or is already deleted."
        return 0
    fi
    
    # Delete resource group and all contained resources
    info "Deleting resource group and all contained resources (this may take several minutes)..."
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output table
    
    if [[ $? -eq 0 ]]; then
        log "✅ Resource group deletion initiated: $RESOURCE_GROUP"
        info "Note: Deletion may take several minutes to complete in the background"
        
        # Optional: Wait for deletion to complete (can be slow)
        if [[ "${WAIT_FOR_COMPLETION:-false}" == "true" ]]; then
            log "Waiting for resource group deletion to complete..."
            local timeout=600  # 10 minutes timeout
            local elapsed=0
            local interval=30
            
            while [[ $elapsed -lt $timeout ]]; do
                if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
                    log "✅ Resource group deleted completely"
                    break
                fi
                
                info "Resource group still exists (waiting ${interval}s...)"
                sleep $interval
                elapsed=$((elapsed + interval))
            done
            
            if [[ $elapsed -ge $timeout ]]; then
                warn "Resource group deletion verification timed out, but deletion was initiated"
            fi
        fi
    else
        error "Failed to delete resource group: $RESOURCE_GROUP"
        error "You may need to delete it manually in the Azure portal"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local deployment files..."
    
    local files_to_remove=(".deployment_vars")
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            info "Removed local file: $file"
        fi
    done
    
    log "✅ Local file cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_success=true
    
    # Check if Health Bot still exists
    if az healthbot show --name "$HEALTH_BOT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Health Bot '$HEALTH_BOT_NAME' still exists"
        cleanup_success=false
    else
        log "✅ Health Bot service cleanup verified"
    fi
    
    # Check if resource group still exists (may take time)
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group '$RESOURCE_GROUP' still exists (deletion may still be in progress)"
        info "Check Azure portal to monitor deletion progress"
    else
        log "✅ Resource group cleanup verified"
    fi
    
    if [[ "$cleanup_success" == "true" ]]; then
        log "✅ Cleanup verification completed successfully"
    else
        warn "Some resources may still exist. Check the Azure portal for manual cleanup."
    fi
}

# Function to display post-cleanup information
display_cleanup_summary() {
    log "🧹 Cleanup Summary:"
    echo ""
    echo "The following actions were performed:"
    echo "  ✅ Health Bot service deletion initiated"
    echo "  ✅ Resource group deletion initiated"
    echo "  ✅ Local deployment files removed"
    echo ""
    warn "Note: Azure resource deletion can take several minutes to complete."
    echo "You can monitor the deletion progress in the Azure portal:"
    echo "  🔗 https://portal.azure.com/#view/HubsExtension/BrowseResourceGroups"
    echo ""
    info "If any resources were not deleted properly, you can remove them manually:"
    echo "  1. Go to the Azure portal"
    echo "  2. Navigate to Resource Groups"
    echo "  3. Find and delete: $RESOURCE_GROUP"
    echo ""
    log "💰 Your Azure charges for these resources should stop once deletion is complete."
}

# Main cleanup function
main() {
    log "Starting Azure Health Bot cleanup..."
    log "Recipe: Simple Healthcare Chatbot with Azure Health Bot"
    
    # Check prerequisites
    check_prerequisites
    
    # Try to load variables from deployment file, fallback to manual input
    if ! load_deployment_variables; then
        prompt_for_variables
    fi
    
    # Show what will be deleted and get user confirmation
    list_resources_for_deletion
    get_user_confirmation
    
    # Perform cleanup steps
    delete_health_bot
    delete_resource_group
    cleanup_local_files
    verify_cleanup
    
    log "🎉 Cleanup completed!"
    echo ""
    display_cleanup_summary
}

# Handle script interruption
cleanup_on_error() {
    error "Cleanup script interrupted."
    warn "Some resources may not have been deleted properly."
    warn "Please check the Azure portal and complete cleanup manually if needed."
    exit 1
}

trap cleanup_on_error INT TERM

# Show help information
show_help() {
    echo "Azure Health Bot Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  --wait-for-completion   Wait for resource deletion to complete (slower)"
    echo "  --force                 Skip confirmation prompts (use with caution)"
    echo ""
    echo "Environment Variables:"
    echo "  WAIT_FOR_COMPLETION     Set to 'true' to wait for deletion completion"
    echo "  FORCE_DELETE           Set to 'true' to skip confirmation prompts"
    echo ""
    echo "Examples:"
    echo "  $0                      Interactive cleanup with confirmations"
    echo "  $0 --wait-for-completion  Wait for all deletions to complete"
    echo "  FORCE_DELETE=true $0    Skip confirmations (dangerous!)"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --wait-for-completion)
            export WAIT_FOR_COMPLETION=true
            shift
            ;;
        --force)
            export FORCE_DELETE=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Override confirmation if forced
if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
    get_user_confirmation() {
        warn "Force delete mode enabled - skipping confirmation"
        log "Proceeding with cleanup..."
    }
fi

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi