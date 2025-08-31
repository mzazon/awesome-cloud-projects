#!/bin/bash

# =============================================================================
# Azure Automated Video Analysis with Video Indexer and Functions - Destroy Script
# =============================================================================
# This script safely removes all resources created for the automated video 
# analysis pipeline, including:
# - Azure AI Video Indexer account
# - Azure Functions app and associated resources
# - Azure Blob Storage account and containers
# - Resource group and all contained resources
#
# Prerequisites:
# - Azure CLI installed and logged in (az login)
# - Azure subscription access with permissions to delete resources
#
# Usage: ./destroy.sh [options]
# Options:
#   -g, --resource-group    Specify resource group name to delete
#   -f, --force            Skip confirmation prompts
#   -h, --help             Show help message
#   --dry-run              Show what would be deleted without executing
#   --keep-rg              Delete resources but keep the resource group
#
# =============================================================================

set -euo pipefail  # Exit on any error, undefined variables, or pipe failures

# =============================================================================
# CONFIGURATION AND DEFAULTS
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
RESOURCE_GROUP=""
FORCE_DELETE=false
DRY_RUN=false
KEEP_RESOURCE_GROUP=false

# =============================================================================
# LOGGING AND OUTPUT FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}❌ $*${NC}" >&2
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

show_help() {
    cat << EOF
Azure Automated Video Analysis Cleanup Script

This script safely removes all resources created for the automated video analysis
pipeline, including Azure AI Video Indexer, Azure Functions, and storage resources.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -g, --resource-group NAME    Specify resource group name to delete
    -f, --force                 Skip confirmation prompts (use with caution)
    -h, --help                  Show this help message
    --dry-run                   Show what would be deleted without executing
    --keep-rg                   Delete resources but keep the resource group

EXAMPLES:
    $0                          # Interactive deletion - will prompt for RG name
    $0 -g my-video-rg           # Delete specific resource group
    $0 -g my-video-rg --force   # Delete without confirmation prompts
    $0 --dry-run -g my-video-rg # Preview what would be deleted

SAFETY FEATURES:
    - Lists all resources before deletion
    - Requires confirmation unless --force is used
    - Provides dry-run mode to preview actions
    - Logs all operations for audit trail

WARNING:
    This operation is irreversible. All data in the specified resource group
    will be permanently deleted, including videos and analysis results.

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites"
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi

    local subscription_name=$(az account show --query name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    log_success "Logged in to Azure subscription: $subscription_name ($subscription_id)"
}

prompt_for_resource_group() {
    if [[ -z "$RESOURCE_GROUP" ]]; then
        echo
        log_info "Available resource groups in your subscription:"
        az group list --query "[].{Name:name, Location:location, Tags:tags}" --output table
        echo
        
        read -p "Enter the resource group name to delete: " RESOURCE_GROUP
        
        if [[ -z "$RESOURCE_GROUP" ]]; then
            log_error "Resource group name cannot be empty"
            exit 1
        fi
    fi
}

validate_resource_group() {
    log_info "Validating resource group: $RESOURCE_GROUP"
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group '$RESOURCE_GROUP' does not exist or you don't have access to it"
        exit 1
    fi
    
    log_success "Resource group validated: $RESOURCE_GROUP"
}

list_resources_in_group() {
    log_info "Listing resources in resource group: $RESOURCE_GROUP"
    
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table)
    
    if [[ -z "$resources" || "$resources" == "[]" ]]; then
        log_warning "No resources found in resource group: $RESOURCE_GROUP"
        return 1
    fi
    
    echo
    echo -e "${YELLOW}📋 Resources that will be deleted:${NC}"
    echo "$resources"
    echo
    
    # Count resources
    local resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv)
    log_info "Total resources to delete: $resource_count"
    
    return 0
}

estimate_deletion_time() {
    local resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv)
    
    if [[ $resource_count -gt 0 ]]; then
        local estimated_minutes=$((resource_count * 2))  # Rough estimate: 2 minutes per resource
        log_info "Estimated deletion time: ${estimated_minutes} minutes"
    fi
}

confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo
    echo -e "${RED}⚠️  WARNING: This action is IRREVERSIBLE!${NC}"
    echo -e "${RED}⚠️  All data will be permanently deleted, including:${NC}"
    echo -e "${RED}   - Video files and analysis results${NC}"
    echo -e "${RED}   - Function app code and configuration${NC}"
    echo -e "${RED}   - Video Indexer processed data${NC}"
    echo -e "${RED}   - All other resources in the resource group${NC}"
    echo
    
    read -p "Type 'DELETE' to confirm deletion of resource group '$RESOURCE_GROUP': " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_warning "Deletion confirmed by user"
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

cleanup_local_files() {
    log_info "Cleaning up local deployment artifacts"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    local files_to_clean=(
        "video-analysis-function.zip"
        "video-analysis-function/"
        "insights-result.json"
        "deploy_*.log"
    )
    
    for file in "${files_to_clean[@]}"; do
        if [[ -e "$file" ]]; then
            rm -rf "$file"
            log_info "Removed local file: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

delete_individual_resources() {
    log_info "Deleting individual resources (alternative to resource group deletion)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete individual resources"
        return 0
    fi
    
    # Get list of resources in the group
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{id:id,type:type,name:name}" --output json)
    
    if [[ "$resources" == "[]" ]]; then
        log_info "No resources to delete"
        return 0
    fi
    
    # Parse and delete resources in dependency order
    echo "$resources" | jq -r '.[] | "\(.type)|\(.name)|\(.id)"' | while IFS='|' read -r resource_type resource_name resource_id; do
        case "$resource_type" in
            "Microsoft.Web/sites")
                log_info "Deleting Function App: $resource_name"
                az functionapp delete --name "$resource_name" --resource-group "$RESOURCE_GROUP" --slot production || true
                ;;
            "Microsoft.CognitiveServices/accounts")
                log_info "Deleting Cognitive Services account: $resource_name"
                az cognitiveservices account delete --name "$resource_name" --resource-group "$RESOURCE_GROUP" || true
                ;;
            "Microsoft.Storage/storageAccounts")
                log_info "Deleting Storage Account: $resource_name"
                az storage account delete --name "$resource_name" --resource-group "$RESOURCE_GROUP" --yes || true
                ;;
            *)
                log_info "Deleting resource: $resource_name ($resource_type)"
                az resource delete --ids "$resource_id" || true
                ;;
        esac
        
        # Brief pause between deletions
        sleep 5
    done
    
    log_success "Individual resources deleted"
}

delete_resource_group() {
    log_info "Deleting resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Delete resource group
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
    log_info "Note: Deletion may take several minutes to complete in the background"
}

wait_for_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_info "Waiting for resource group deletion to complete..."
    
    local max_wait_minutes=30
    local wait_count=0
    
    while az group show --name "$RESOURCE_GROUP" &> /dev/null; do
        if [[ $wait_count -ge $max_wait_minutes ]]; then
            log_warning "Deletion is taking longer than expected. Check Azure portal for status."
            break
        fi
        
        echo -n "."
        sleep 60
        ((wait_count++))
    done
    
    echo
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_success "Resource group deletion completed: $RESOURCE_GROUP"
    else
        log_warning "Resource group may still be deleting. Check Azure portal for current status."
    fi
}

verify_deletion() {
    log_info "Verifying deletion"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify deletion"
        return 0
    fi
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_success "Confirmed: Resource group no longer exists"
    else
        log_warning "Resource group still exists - deletion may be in progress"
        
        # Check if any resources remain
        local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining_resources" -eq 0 ]]; then
            log_info "Resource group is empty - deletion should complete shortly"
        else
            log_warning "$remaining_resources resources still remain in the group"
        fi
    fi
}

# =============================================================================
# MAIN CLEANUP LOGIC
# =============================================================================

main() {
    log_info "Starting Azure Automated Video Analysis cleanup"
    log_info "Log file: $LOG_FILE"
    
    # Check prerequisites
    check_prerequisites
    
    # Get resource group name if not provided
    prompt_for_resource_group
    
    # Validate resource group exists
    validate_resource_group
    
    # List resources that will be deleted
    if ! list_resources_in_group; then
        log_info "Resource group is already empty"
        if [[ "$KEEP_RESOURCE_GROUP" != "true" ]]; then
            log_info "Deleting empty resource group"
            if [[ "$DRY_RUN" != "true" ]]; then
                az group delete --name "$RESOURCE_GROUP" --yes
            fi
            log_success "Empty resource group deleted"
        fi
        exit 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "=== DRY RUN MODE - No resources will be deleted ==="
        log_info "Resource Group: $RESOURCE_GROUP"
        log_info "Keep Resource Group: $KEEP_RESOURCE_GROUP"
        log_info "=== END DRY RUN PREVIEW ==="
        return 0
    fi
    
    # Estimate deletion time
    estimate_deletion_time
    
    # Confirm deletion
    confirm_deletion
    
    # Main cleanup steps
    log_info "=== CLEANUP STARTED ==="
    
    if [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
        delete_individual_resources
        log_success "Resources deleted, resource group preserved"
    else
        delete_resource_group
        wait_for_deletion
        verify_deletion
    fi
    
    # Clean up local files
    cleanup_local_files
    
    log_success "=== CLEANUP COMPLETED ==="
    echo
    echo -e "${GREEN}🧹 Azure Automated Video Analysis Pipeline Cleanup Completed!${NC}"
    echo
    echo "📋 Cleanup Summary:"
    echo "  Resource Group: $RESOURCE_GROUP"
    if [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
        echo "  Status: Resources deleted, resource group preserved"
    else
        echo "  Status: Resource group and all resources deleted"
    fi
    echo
    echo "📖 Cleanup log saved: $LOG_FILE"
    echo
    if [[ "$KEEP_RESOURCE_GROUP" != "true" ]]; then
        echo "💡 The resource group has been permanently deleted."
        echo "   All video files, analysis results, and configurations are gone."
    fi
    echo "   Thank you for using Azure Automated Video Analysis!"
}

# =============================================================================
# COMMAND LINE ARGUMENT PARSING
# =============================================================================

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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --keep-rg)
            KEEP_RESOURCE_GROUP=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main cleanup
main