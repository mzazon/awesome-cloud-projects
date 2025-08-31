#!/bin/bash

#######################################
# Azure URL Shortener Cleanup Script
# Removes Azure Functions and Table Storage resources
# Author: Recipe Generator
# Version: 1.0
#######################################

set -euo pipefail
IFS=$'\n\t'

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Configuration variables
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
LOCATION="${LOCATION:-eastus}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}"
FUNCTION_APP="${FUNCTION_APP:-}"
TABLE_NAME="${TABLE_NAME:-urlmappings}"
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"
DELETE_RESOURCE_GROUP="${DELETE_RESOURCE_GROUP:-true}"
BACKUP_DATA="${BACKUP_DATA:-false}"

# Display banner
echo "=================================================="
echo "Azure URL Shortener Cleanup Script"
echo "=================================================="

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI first."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Get subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    log_info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    
    log_success "Prerequisites check completed"
}

# Auto-discover resources if not specified
discover_resources() {
    log_info "Discovering resources..."
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log_info "Searching for URL shortener resource groups..."
        
        # Find resource groups with url-shortener tag or name pattern
        CANDIDATE_RGS=$(az group list \
            --query "[?contains(name, 'url-shortener') || tags.purpose=='recipe'].name" \
            --output tsv)
        
        if [[ -z "$CANDIDATE_RGS" ]]; then
            log_warning "No URL shortener resource groups found automatically"
            return 1
        fi
        
        # If multiple candidates found, list them
        if [[ $(echo "$CANDIDATE_RGS" | wc -l) -gt 1 ]]; then
            log_info "Multiple resource groups found:"
            echo "$CANDIDATE_RGS" | nl
            
            if [[ "$FORCE" != "true" ]]; then
                echo -n "Enter the number of the resource group to delete (or 0 to cancel): "
                read -r SELECTION
                
                if [[ "$SELECTION" == "0" ]]; then
                    log_info "Operation cancelled by user"
                    exit 0
                fi
                
                RESOURCE_GROUP=$(echo "$CANDIDATE_RGS" | sed -n "${SELECTION}p")
            else
                # In force mode, take the first one
                RESOURCE_GROUP=$(echo "$CANDIDATE_RGS" | head -n1)
                log_warning "Force mode: Using first resource group: $RESOURCE_GROUP"
            fi
        else
            RESOURCE_GROUP="$CANDIDATE_RGS"
        fi
        
        log_info "Selected resource group: $RESOURCE_GROUP"
    fi
    
    # Verify resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error_exit "Resource group '$RESOURCE_GROUP' not found"
    fi
    
    # Auto-discover resources within the resource group
    if [[ -z "$FUNCTION_APP" ]]; then
        FUNCTION_APP=$(az functionapp list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[0].name" \
            --output tsv 2>/dev/null || echo "")
    fi
    
    if [[ -z "$STORAGE_ACCOUNT" ]]; then
        STORAGE_ACCOUNT=$(az storage account list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[0].name" \
            --output tsv 2>/dev/null || echo "")
    fi
    
    log_info "Discovered resources:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Function App: ${FUNCTION_APP:-'Not found'}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT:-'Not found'}"
    log_info "  Table Name: $TABLE_NAME"
}

# Backup table data
backup_table_data() {
    if [[ "$BACKUP_DATA" != "true" ]] || [[ -z "$STORAGE_ACCOUNT" ]]; then
        return 0
    fi
    
    log_info "Backing up table data..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup table data"
        return 0
    fi
    
    # Get storage account connection string
    STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$STORAGE_CONNECTION" ]]; then
        log_warning "Could not get storage connection string - skipping backup"
        return 0
    fi
    
    # Create backup directory
    BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Export table data
    if az storage entity query \
        --table-name "$TABLE_NAME" \
        --connection-string "$STORAGE_CONNECTION" \
        --output json > "$BACKUP_DIR/table-data.json" 2>/dev/null; then
        log_success "Table data backed up to: $BACKUP_DIR/table-data.json"
    else
        log_warning "Could not backup table data"
        rmdir "$BACKUP_DIR" 2>/dev/null || true
    fi
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   Resource Group: $RESOURCE_GROUP"
    if [[ -n "$FUNCTION_APP" ]]; then
        echo "   Function App: $FUNCTION_APP"
    fi
    if [[ -n "$STORAGE_ACCOUNT" ]]; then
        echo "   Storage Account: $STORAGE_ACCOUNT (including all data)"
        echo "   Table: $TABLE_NAME (including all URL mappings)"
    fi
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        echo -n "Type 'DELETE' to confirm deletion of the entire resource group: "
    else
        echo -n "Type 'DELETE' to confirm deletion of individual resources: "
    fi
    
    read -r CONFIRMATION
    
    if [[ "$CONFIRMATION" != "DELETE" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with deletion..."
}

# Delete individual resources
delete_individual_resources() {
    log_info "Deleting individual resources..."
    
    # Delete Function App
    if [[ -n "$FUNCTION_APP" ]]; then
        log_info "Deleting Function App: $FUNCTION_APP"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete Function App: $FUNCTION_APP"
        else
            if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                az functionapp delete \
                    --name "$FUNCTION_APP" \
                    --resource-group "$RESOURCE_GROUP" \
                    --output table
                log_success "Function App deleted: $FUNCTION_APP"
            else
                log_warning "Function App not found: $FUNCTION_APP"
            fi
        fi
    fi
    
    # Delete Table (before deleting storage account)
    if [[ -n "$STORAGE_ACCOUNT" ]]; then
        log_info "Deleting table: $TABLE_NAME"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete table: $TABLE_NAME"
        else
            # Get storage account connection string
            STORAGE_CONNECTION=$(az storage account show-connection-string \
                --name "$STORAGE_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --query connectionString \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "$STORAGE_CONNECTION" ]]; then
                if az storage table exists \
                    --name "$TABLE_NAME" \
                    --connection-string "$STORAGE_CONNECTION" \
                    --query exists \
                    --output tsv 2>/dev/null | grep -q "true"; then
                    
                    az storage table delete \
                        --name "$TABLE_NAME" \
                        --connection-string "$STORAGE_CONNECTION" \
                        --output table
                    log_success "Table deleted: $TABLE_NAME"
                else
                    log_warning "Table not found: $TABLE_NAME"
                fi
            else
                log_warning "Could not get storage connection string"
            fi
        fi
    fi
    
    # Delete Storage Account
    if [[ -n "$STORAGE_ACCOUNT" ]]; then
        log_info "Deleting Storage Account: $STORAGE_ACCOUNT"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete Storage Account: $STORAGE_ACCOUNT"
        else
            if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                az storage account delete \
                    --name "$STORAGE_ACCOUNT" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes \
                    --output table
                log_success "Storage Account deleted: $STORAGE_ACCOUNT"
            else
                log_warning "Storage Account not found: $STORAGE_ACCOUNT"
            fi
        fi
    fi
}

# Delete entire resource group
delete_resource_group() {
    log_info "Deleting resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group not found: $RESOURCE_GROUP"
        return 0
    fi
    
    # Delete the resource group and all resources within it
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output table
    
    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
    log_info "Note: Deletion may take several minutes to complete"
}

# Verify deletion
verify_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify deletion"
        return 0
    fi
    
    log_info "Verifying deletion..."
    
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        # For resource group deletion, just check if it's gone
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log_success "Resource group successfully deleted: $RESOURCE_GROUP"
        else
            log_warning "Resource group may still be deleting: $RESOURCE_GROUP"
            log_info "You can check deletion status with: az group show --name $RESOURCE_GROUP"
        fi
    else
        # For individual resource deletion, check each one
        local all_deleted=true
        
        if [[ -n "$FUNCTION_APP" ]] && az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log_warning "Function App still exists: $FUNCTION_APP"
            all_deleted=false
        fi
        
        if [[ -n "$STORAGE_ACCOUNT" ]] && az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log_warning "Storage Account still exists: $STORAGE_ACCOUNT"
            all_deleted=false
        fi
        
        if [[ "$all_deleted" == "true" ]]; then
            log_success "All specified resources have been deleted"
        else
            log_warning "Some resources may still be deleting"
        fi
    fi
}

# Main cleanup function
main() {
    log_info "Starting cleanup process"
    
    check_prerequisites
    discover_resources
    backup_table_data
    confirm_deletion
    
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        delete_resource_group
    else
        delete_individual_resources
    fi
    
    verify_deletion
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log_success "Cleanup completed successfully!"
        
        if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
            log_info "Resource group deletion initiated - it may take a few minutes to complete"
        fi
    else
        log_info "Dry run completed - no resources were deleted"
    fi
}

# Script usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group       Resource group name (auto-discovered if not specified)"
    echo "  -s, --storage-account      Storage account name (auto-discovered if not specified)"
    echo "  -f, --function-app         Function app name (auto-discovered if not specified)"
    echo "  -t, --table-name           Table name (default: urlmappings)"
    echo "  --individual               Delete individual resources instead of entire resource group"
    echo "  --backup                   Backup table data before deletion"
    echo "  --force                    Skip confirmation prompts"
    echo "  -d, --dry-run             Perform dry run without deleting resources"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP            Override resource group name"
    echo "  STORAGE_ACCOUNT           Override storage account name"
    echo "  FUNCTION_APP              Override function app name"
    echo "  TABLE_NAME                Override table name"
    echo "  DELETE_RESOURCE_GROUP     Set to 'false' to delete individual resources"
    echo "  BACKUP_DATA               Set to 'true' to backup table data"
    echo "  FORCE                     Set to 'true' to skip confirmations"
    echo "  DRY_RUN                   Set to 'true' for dry run"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Auto-discover and delete resource group"
    echo "  $0 --dry-run                         # Show what would be deleted"
    echo "  $0 --individual --backup             # Delete individual resources with backup"
    echo "  $0 --resource-group my-rg --force    # Delete specific resource group without confirmation"
    echo "  BACKUP_DATA=true $0                  # Backup data before deletion"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--storage-account)
            STORAGE_ACCOUNT="$2"
            shift 2
            ;;
        -f|--function-app)
            FUNCTION_APP="$2"
            shift 2
            ;;
        -t|--table-name)
            TABLE_NAME="$2"
            shift 2
            ;;
        --individual)
            DELETE_RESOURCE_GROUP="false"
            shift
            ;;
        --backup)
            BACKUP_DATA="true"
            shift
            ;;
        --force)
            FORCE="true"
            shift
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate configuration
if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY RUN MODE: No resources will be deleted"
    echo "=================================================="
fi

if [[ "$DELETE_RESOURCE_GROUP" == "false" ]]; then
    log_info "Individual resource deletion mode"
else
    log_info "Resource group deletion mode"
fi

# Run main function with error handling
if ! main; then
    error_exit "Cleanup failed"
fi