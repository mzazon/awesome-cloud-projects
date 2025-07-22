#!/bin/bash

# Cleanup script for Progressive Web Apps with Static Hosting and CDN
# This script removes all resources created by the deployment script to avoid ongoing costs.

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "Prerequisites check completed."
}

# Set defaults and load configuration
set_defaults() {
    # Try to load configuration from environment or use defaults
    export RESOURCE_GROUP="${RESOURCE_GROUP:-}"
    export SWA_NAME="${SWA_NAME:-}"
    export CDN_PROFILE="${CDN_PROFILE:-}"
    export AI_NAME="${AI_NAME:-}"
    export DRY_RUN="${DRY_RUN:-false}"
    export FORCE_DELETE="${FORCE_DELETE:-false}"
    export SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"
}

# Auto-discover resources if not provided
discover_resources() {
    log "Discovering resources..."
    
    # If resource group is not provided, try to discover it
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log "No resource group specified. Searching for PWA demo resources..."
        
        # Look for resource groups with PWA demo pattern
        local rg_candidates
        rg_candidates=$(az group list --query "[?contains(name, 'rg-pwa-demo')].name" --output tsv)
        
        if [[ -n "$rg_candidates" ]]; then
            local rg_count
            rg_count=$(echo "$rg_candidates" | wc -l)
            
            if [[ $rg_count -eq 1 ]]; then
                export RESOURCE_GROUP="$rg_candidates"
                log "Found resource group: $RESOURCE_GROUP"
            else
                error "Multiple PWA demo resource groups found. Please specify RESOURCE_GROUP:"
                echo "$rg_candidates"
                exit 1
            fi
        else
            error "No PWA demo resource groups found. Please specify RESOURCE_GROUP."
            exit 1
        fi
    fi
    
    # Verify resource group exists
    if ! az group exists --name "$RESOURCE_GROUP" 2>/dev/null; then
        error "Resource group '$RESOURCE_GROUP' does not exist."
        exit 1
    fi
    
    # Auto-discover resource names if not provided
    if [[ -z "$SWA_NAME" ]]; then
        SWA_NAME=$(az staticwebapp list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")
    fi
    
    if [[ -z "$CDN_PROFILE" ]]; then
        CDN_PROFILE=$(az cdn profile list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")
    fi
    
    if [[ -z "$AI_NAME" ]]; then
        AI_NAME=$(az monitor app-insights component list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")
    fi
}

# Display resources to be deleted
display_resources() {
    log "Resources to be deleted:"
    echo ""
    echo "  Resource Group: $RESOURCE_GROUP"
    
    if [[ -n "$SWA_NAME" ]]; then
        echo "  Static Web App: $SWA_NAME"
    fi
    
    if [[ -n "$CDN_PROFILE" ]]; then
        echo "  CDN Profile: $CDN_PROFILE"
    fi
    
    if [[ -n "$AI_NAME" ]]; then
        echo "  Application Insights: $AI_NAME"
    fi
    
    echo ""
    echo "  Dry Run: $DRY_RUN"
    echo "  Force Delete: $FORCE_DELETE"
    echo "  Skip Confirmation: $SKIP_CONFIRMATION"
    echo ""
}

# List all resources in the resource group
list_resources() {
    log "Listing all resources in resource group '$RESOURCE_GROUP'..."
    
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null)
    
    if [[ -n "$resources" ]]; then
        echo "$resources"
        echo ""
    else
        info "No resources found in resource group '$RESOURCE_GROUP'."
    fi
}

# Delete CDN resources
delete_cdn() {
    if [[ -n "$CDN_PROFILE" ]]; then
        log "Deleting CDN resources..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "DRY RUN: Would delete CDN Profile: $CDN_PROFILE"
            return
        fi
        
        # List CDN endpoints before deletion
        local endpoints
        endpoints=$(az cdn endpoint list --profile-name "$CDN_PROFILE" --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$endpoints" ]]; then
            log "Deleting CDN endpoints..."
            while IFS= read -r endpoint; do
                if [[ -n "$endpoint" ]]; then
                    info "Deleting CDN endpoint: $endpoint"
                    az cdn endpoint delete \
                        --name "$endpoint" \
                        --profile-name "$CDN_PROFILE" \
                        --resource-group "$RESOURCE_GROUP" \
                        --yes \
                        --output none 2>/dev/null || warning "Failed to delete CDN endpoint: $endpoint"
                fi
            done <<< "$endpoints"
        fi
        
        # Delete CDN profile
        log "Deleting CDN profile: $CDN_PROFILE"
        az cdn profile delete \
            --name "$CDN_PROFILE" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none 2>/dev/null
        
        if [[ $? -eq 0 ]]; then
            log "✅ CDN profile deleted: $CDN_PROFILE"
        else
            warning "Failed to delete CDN profile: $CDN_PROFILE"
        fi
    else
        info "No CDN profile specified. Skipping CDN cleanup."
    fi
}

# Delete Static Web App
delete_static_web_app() {
    if [[ -n "$SWA_NAME" ]]; then
        log "Deleting Static Web App..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "DRY RUN: Would delete Static Web App: $SWA_NAME"
            return
        fi
        
        log "Deleting Static Web App: $SWA_NAME"
        az staticwebapp delete \
            --name "$SWA_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none 2>/dev/null
        
        if [[ $? -eq 0 ]]; then
            log "✅ Static Web App deleted: $SWA_NAME"
        else
            warning "Failed to delete Static Web App: $SWA_NAME"
        fi
    else
        info "No Static Web App specified. Skipping Static Web App cleanup."
    fi
}

# Delete Application Insights
delete_application_insights() {
    if [[ -n "$AI_NAME" ]]; then
        log "Deleting Application Insights..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "DRY RUN: Would delete Application Insights: $AI_NAME"
            return
        fi
        
        log "Deleting Application Insights: $AI_NAME"
        az monitor app-insights component delete \
            --app "$AI_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none 2>/dev/null
        
        if [[ $? -eq 0 ]]; then
            log "✅ Application Insights deleted: $AI_NAME"
        else
            warning "Failed to delete Application Insights: $AI_NAME"
        fi
    else
        info "No Application Insights specified. Skipping Application Insights cleanup."
    fi
}

# Delete resource group
delete_resource_group() {
    log "Deleting resource group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete resource group: $RESOURCE_GROUP"
        return
    fi
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log "Force deleting resource group: $RESOURCE_GROUP"
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output none
        
        log "✅ Resource group deletion initiated: $RESOURCE_GROUP"
        log "Note: Deletion will continue in the background and may take several minutes to complete."
    else
        # Check if resource group has any remaining resources
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining_resources" -gt 0 ]]; then
            warning "Resource group '$RESOURCE_GROUP' still contains $remaining_resources resources."
            
            if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
                read -p "Do you want to delete the entire resource group and all remaining resources? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log "Resource group deletion cancelled by user."
                    return
                fi
            fi
        fi
        
        log "Deleting resource group: $RESOURCE_GROUP"
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output none
        
        log "✅ Resource group deletion initiated: $RESOURCE_GROUP"
        log "Note: Deletion will continue in the background and may take several minutes to complete."
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would remove local pwa-demo directory"
        return
    fi
    
    if [[ -d "pwa-demo" ]]; then
        if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
            read -p "Do you want to remove the local pwa-demo directory? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf pwa-demo
                log "✅ Local pwa-demo directory removed"
            else
                log "Local pwa-demo directory preserved"
            fi
        else
            rm -rf pwa-demo
            log "✅ Local pwa-demo directory removed"
        fi
    else
        info "No local pwa-demo directory found"
    fi
    
    # Clear environment variables
    unset RESOURCE_GROUP SWA_NAME CDN_PROFILE AI_NAME
    unset SWA_URL CDN_URL AI_INSTRUMENTATION_KEY AI_CONNECTION_STRING
    
    log "✅ Environment variables cleared"
}

# Verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would verify deletion of resources"
        return
    fi
    
    # Check if resource group still exists
    if az group exists --name "$RESOURCE_GROUP" 2>/dev/null; then
        warning "Resource group '$RESOURCE_GROUP' still exists (deletion may be in progress)"
        
        # List any remaining resources
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining_resources" -gt 0 ]]; then
            warning "Resource group contains $remaining_resources resources that are still being deleted"
        fi
    else
        log "✅ Resource group '$RESOURCE_GROUP' has been deleted"
    fi
}

# Display cleanup summary
cleanup_summary() {
    log "=== CLEANUP SUMMARY ==="
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "🔍 DRY RUN COMPLETED - No resources were actually deleted"
    else
        echo "🧹 CLEANUP COMPLETED"
    fi
    echo ""
    echo "Actions performed:"
    echo "  • CDN Profile and endpoints deletion"
    echo "  • Static Web App deletion"
    echo "  • Application Insights deletion"
    echo "  • Resource group deletion"
    echo "  • Local files cleanup"
    echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "💡 Note: Resource deletion may take several minutes to complete in the background."
        echo "You can monitor the progress in the Azure Portal or by running:"
        echo "  az group exists --name '$RESOURCE_GROUP'"
        echo ""
    fi
    
    echo "✅ Progressive Web App cleanup completed!"
}

# Main cleanup function
main() {
    log "Starting Azure Progressive Web App cleanup..."
    
    check_prerequisites
    set_defaults
    discover_resources
    display_resources
    
    if [[ "$DRY_RUN" != "true" && "$SKIP_CONFIRMATION" != "true" ]]; then
        echo ""
        warning "This will permanently delete all resources listed above!"
        read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user."
            exit 0
        fi
    fi
    
    list_resources
    
    # Delete resources in order (highest level first)
    delete_cdn
    delete_static_web_app
    delete_application_insights
    delete_resource_group
    cleanup_local_files
    
    # Wait a moment for operations to complete
    if [[ "$DRY_RUN" != "true" ]]; then
        sleep 5
    fi
    
    verify_deletion
    cleanup_summary
    
    log "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup interrupted! Some resources may not have been deleted."; exit 1' INT TERM

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
        --yes)
            export SKIP_CONFIRMATION=true
            shift
            ;;
        --resource-group)
            export RESOURCE_GROUP="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --dry-run              Show what would be deleted without actually deleting"
            echo "  --force                Force deletion without additional prompts"
            echo "  --yes                  Skip confirmation prompts"
            echo "  --resource-group RG    Specify resource group name"
            echo "  --help                 Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  RESOURCE_GROUP         Resource group name"
            echo "  SWA_NAME              Static Web App name"
            echo "  CDN_PROFILE           CDN Profile name"
            echo "  AI_NAME               Application Insights name"
            echo ""
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"