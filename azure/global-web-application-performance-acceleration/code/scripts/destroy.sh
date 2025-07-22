#!/bin/bash

# Cleanup script for Azure Web Application Performance Optimization
# Recipe: optimizing-web-application-performance-with-azure-cache-for-redis-and-azure-cdn
# This script destroys Azure resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECIPE_NAME="optimizing-web-application-performance-with-azure-cache-for-redis-and-azure-cdn"
CLEANUP_LOG_FILE="${SCRIPT_DIR}/cleanup-$(date +%Y%m%d-%H%M%S).log"

# Configuration variables
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}
DELETE_RESOURCE_GROUP=${DELETE_RESOURCE_GROUP:-true}
INDIVIDUAL_RESOURCES=${INDIVIDUAL_RESOURCES:-false}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Azure Web Application Performance Optimization infrastructure.

REQUIRED OPTIONS:
    -g, --resource-group <name>    Resource group name to destroy

OPTIONS:
    -s, --subscription <id>        Azure subscription ID
    -d, --dry-run                  Show what would be destroyed without actually destroying
    -f, --force                    Force deletion without confirmation prompts
    -y, --yes                      Skip confirmation prompts (same as --force)
    --skip-rg                      Don't delete the resource group, only individual resources
    --individual                   Delete individual resources instead of resource group
    -h, --help                     Show this help message

EXAMPLES:
    $0 -g rg-webapp-perf-abc123               # Destroy resource group and all resources
    $0 -g rg-webapp-perf-abc123 --dry-run     # Show what would be destroyed
    $0 -g rg-webapp-perf-abc123 --force       # Force deletion without confirmation
    $0 -g rg-webapp-perf-abc123 --individual  # Delete individual resources only
    
ENVIRONMENT VARIABLES:
    DRY_RUN                 Set to 'true' for dry run mode
    FORCE                   Set to 'true' to force deletion without confirmation
    SKIP_CONFIRMATION       Set to 'true' to skip confirmation prompts
    DELETE_RESOURCE_GROUP   Set to 'false' to keep resource group
    INDIVIDUAL_RESOURCES    Set to 'true' to delete individual resources

EOF
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get subscription ID if not provided
    if [ -z "$SUBSCRIPTION_ID" ]; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        if [ -z "$SUBSCRIPTION_ID" ]; then
            error "Could not determine subscription ID. Please specify with -s option."
            exit 1
        fi
    fi
    
    # Check if resource group exists
    if [ -z "$RESOURCE_GROUP" ]; then
        error "Resource group name is required. Use -g option."
        exit 1
    fi
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group '$RESOURCE_GROUP' does not exist or is not accessible."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to list resources in the resource group
list_resources() {
    log "Listing resources in resource group: $RESOURCE_GROUP"
    
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].{Name:name, Type:type, Location:location}' --output table)
    
    if [ -z "$resources" ]; then
        warn "No resources found in resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    echo ""
    echo "Resources in $RESOURCE_GROUP:"
    echo "$resources"
    echo ""
}

# Function to confirm destruction
confirm_destruction() {
    if [ "$SKIP_CONFIRMATION" = "true" ] || [ "$FORCE" = "true" ]; then
        return 0
    fi
    
    echo ""
    warn "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo ""
    echo "This will permanently delete the following:"
    
    if [ "$DELETE_RESOURCE_GROUP" = "true" ] && [ "$INDIVIDUAL_RESOURCES" = "false" ]; then
        echo "  • Resource group: $RESOURCE_GROUP"
        echo "  • ALL resources within the resource group"
    else
        echo "  • Individual resources in: $RESOURCE_GROUP"
        echo "  • Resource group will be preserved"
    fi
    
    echo ""
    echo "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Operation cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Please type the resource group name to confirm: " rg_confirmation
    
    if [ "$rg_confirmation" != "$RESOURCE_GROUP" ]; then
        error "Resource group name confirmation failed. Operation cancelled."
        exit 1
    fi
    
    log "Confirmation received. Proceeding with destruction..."
}

# Function to delete individual resources
delete_individual_resources() {
    log "Deleting individual resources in resource group: $RESOURCE_GROUP"
    
    if [ "$DRY_RUN" = "true" ]; then
        info "[DRY RUN] Would delete individual resources in: $RESOURCE_GROUP"
        return 0
    fi
    
    # Get all resources in the resource group
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].{id:id, name:name, type:type}' --output json)
    
    if [ "$resources" = "[]" ]; then
        warn "No resources found to delete in resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Parse resources and delete them in reverse dependency order
    local resource_types=("Microsoft.Cdn/profiles/endpoints" "Microsoft.Cdn/profiles" "Microsoft.Web/sites" "Microsoft.Web/serverfarms" "Microsoft.Cache/Redis" "Microsoft.DBforPostgreSQL/flexibleServers" "Microsoft.Insights/components")
    
    for resource_type in "${resource_types[@]}"; do
        local matching_resources=$(echo "$resources" | jq -r ".[] | select(.type == \"$resource_type\") | .id")
        
        if [ -n "$matching_resources" ]; then
            while IFS= read -r resource_id; do
                if [ -n "$resource_id" ]; then
                    local resource_name=$(echo "$resource_id" | sed 's/.*\///')
                    log "Deleting $resource_type: $resource_name"
                    
                    # Special handling for CDN endpoints
                    if [[ "$resource_type" == "Microsoft.Cdn/profiles/endpoints" ]]; then
                        local profile_name=$(echo "$resource_id" | sed 's/.*\/profiles\/\([^\/]*\)\/.*/\1/')
                        az cdn endpoint delete --resource-group "$RESOURCE_GROUP" --profile-name "$profile_name" --name "$resource_name" --yes &
                    else
                        az resource delete --ids "$resource_id" --verbose &
                    fi
                    
                    # Limit concurrent deletions
                    local job_count=$(jobs -r | wc -l)
                    if [ "$job_count" -ge 5 ]; then
                        wait
                    fi
                fi
            done <<< "$matching_resources"
            
            # Wait for all deletion jobs to complete
            wait
        fi
    done
    
    log "✅ Individual resources deleted successfully"
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group: $RESOURCE_GROUP"
    
    if [ "$DRY_RUN" = "true" ]; then
        info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Delete resource group with all resources
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output table
    
    if [ $? -eq 0 ]; then
        log "✅ Resource group deletion initiated: $RESOURCE_GROUP"
        info "Note: Deletion may take several minutes to complete"
        
        # Optional: Wait for completion
        if [ "${WAIT_FOR_COMPLETION:-false}" = "true" ]; then
            log "Waiting for resource group deletion to complete..."
            
            while az group show --name "$RESOURCE_GROUP" &> /dev/null; do
                info "Resource group still exists. Waiting..."
                sleep 30
            done
            
            log "✅ Resource group deletion completed: $RESOURCE_GROUP"
        else
            info "Deletion is running in the background. Check Azure portal for progress."
        fi
    else
        error "Failed to delete resource group: $RESOURCE_GROUP"
        exit 1
    fi
}

# Function to verify deletion
verify_deletion() {
    if [ "$DRY_RUN" = "true" ]; then
        return 0
    fi
    
    log "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        if [ "$DELETE_RESOURCE_GROUP" = "true" ] && [ "$INDIVIDUAL_RESOURCES" = "false" ]; then
            warn "Resource group still exists (deletion may be in progress)"
        else
            # Check if individual resources were deleted
            local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
            
            if [ -z "$remaining_resources" ]; then
                log "✅ All resources deleted successfully"
            else
                warn "Some resources may still exist:"
                echo "$remaining_resources"
            fi
        fi
    else
        log "✅ Resource group and all resources deleted successfully"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup completed!"
    
    echo ""
    echo "=========================================="
    echo "         CLEANUP SUMMARY"
    echo "=========================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Subscription: $SUBSCRIPTION_ID"
    echo ""
    
    if [ "$DRY_RUN" = "true" ]; then
        echo "Mode: DRY RUN (no resources were deleted)"
    else
        if [ "$DELETE_RESOURCE_GROUP" = "true" ] && [ "$INDIVIDUAL_RESOURCES" = "false" ]; then
            echo "Action: Resource group and all resources deleted"
        else
            echo "Action: Individual resources deleted"
        fi
    fi
    
    echo ""
    echo "Cleanup completed at: $(date)"
    echo "Log file: $CLEANUP_LOG_FILE"
    echo "=========================================="
}

# Function to handle cleanup errors
handle_cleanup_error() {
    error "Cleanup failed or was interrupted"
    
    if [ "$DRY_RUN" != "true" ]; then
        warn "Some resources may still exist. Please check the Azure portal."
        warn "You may need to manually delete remaining resources."
    fi
    
    exit 1
}

# Main function
main() {
    local start_time=$(date +%s)
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -s|--subscription)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --skip-rg)
                DELETE_RESOURCE_GROUP=false
                shift
                ;;
            --individual)
                INDIVIDUAL_RESOURCES=true
                DELETE_RESOURCE_GROUP=false
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
    
    # Start cleanup
    log "Starting cleanup of Azure Web Application Performance Optimization infrastructure"
    info "Recipe: $RECIPE_NAME"
    info "Cleanup log: $CLEANUP_LOG_FILE"
    
    # Setup error handling
    trap handle_cleanup_error ERR
    
    # Execute cleanup steps
    check_prerequisites
    list_resources
    confirm_destruction
    
    if [ "$DRY_RUN" = "true" ]; then
        info "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Choose deletion method
    if [ "$DELETE_RESOURCE_GROUP" = "true" ] && [ "$INDIVIDUAL_RESOURCES" = "false" ]; then
        delete_resource_group
    else
        delete_individual_resources
    fi
    
    verify_deletion
    
    # Calculate cleanup time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    display_cleanup_summary
    log "Cleanup completed in ${duration} seconds"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@" 2>&1 | tee "$CLEANUP_LOG_FILE"
fi