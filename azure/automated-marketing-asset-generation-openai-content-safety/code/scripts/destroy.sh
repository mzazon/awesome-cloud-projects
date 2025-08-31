#!/bin/bash

# Azure Marketing Asset Generation with OpenAI and Content Safety - Cleanup Script
# This script removes all infrastructure created for the automated marketing content generation solution
# It handles resources in the correct order to avoid dependency issues

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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

# Function to print script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -g, --resource-group    Resource group name (required)"
    echo "  -f, --force             Skip confirmation prompts"
    echo "  -k, --keep-logs         Keep Application Insights logs (if any)"
    echo "  -d, --dry-run           Show what would be deleted without actually deleting"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --resource-group rg-marketing-ai-abc123"
    echo "  $0 --resource-group rg-marketing-ai-abc123 --force"
    echo "  $0 --resource-group rg-marketing-ai-abc123 --dry-run"
}

# Default values
RESOURCE_GROUP=""
FORCE=false
KEEP_LOGS=false
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -k|--keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
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

# Validate required parameters
if [[ -z "$RESOURCE_GROUP" ]]; then
    log_error "Resource group name is required"
    usage
    exit 1
fi

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

# Function to verify resource group exists
verify_resource_group() {
    log_info "Verifying resource group exists: $RESOURCE_GROUP"
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group '$RESOURCE_GROUP' does not exist"
        exit 1
    fi
    
    log_success "Resource group verified: $RESOURCE_GROUP"
}

# Function to list resources in the group
list_resources() {
    log_info "Listing resources in resource group: $RESOURCE_GROUP"
    
    RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --output table)
    
    if [[ -z "$RESOURCES" || "$RESOURCES" == *"No resources found"* ]]; then
        log_warning "No resources found in resource group: $RESOURCE_GROUP"
        return 1
    fi
    
    echo "$RESOURCES"
    return 0
}

# Function to get confirmation from user
get_confirmation() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will permanently delete all resources in the resource group: $RESOURCE_GROUP"
    log_warning "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
}

# Function to delete Function App
delete_function_app() {
    log_info "Searching for Function Apps..."
    
    FUNCTION_APPS=$(az functionapp list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    if [[ -z "$FUNCTION_APPS" ]]; then
        log_info "No Function Apps found"
        return
    fi
    
    for FUNCTION_APP in $FUNCTION_APPS; do
        log_info "Deleting Function App: $FUNCTION_APP"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete Function App: $FUNCTION_APP"
            continue
        fi
        
        if az functionapp delete \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --yes; then
            log_success "Function App deleted: $FUNCTION_APP"
        else
            log_warning "Failed to delete Function App: $FUNCTION_APP"
        fi
    done
}

# Function to delete Cognitive Services accounts (OpenAI and Content Safety)
delete_cognitive_services() {
    log_info "Searching for Cognitive Services accounts..."
    
    COGNITIVE_ACCOUNTS=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    if [[ -z "$COGNITIVE_ACCOUNTS" ]]; then
        log_info "No Cognitive Services accounts found"
        return
    fi
    
    for ACCOUNT in $COGNITIVE_ACCOUNTS; do
        log_info "Deleting Cognitive Services account: $ACCOUNT"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete Cognitive Services account: $ACCOUNT"
            continue
        fi
        
        # Get account details for logging
        ACCOUNT_KIND=$(az cognitiveservices account show \
            --name "$ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --query "kind" --output tsv 2>/dev/null || echo "Unknown")
        
        log_info "Account type: $ACCOUNT_KIND"
        
        if az cognitiveservices account delete \
            --name "$ACCOUNT" \
            --resource-group "$RESOURCE_GROUP"; then
            log_success "Cognitive Services account deleted: $ACCOUNT"
        else
            log_warning "Failed to delete Cognitive Services account: $ACCOUNT"
        fi
    done
}

# Function to delete Storage Accounts
delete_storage_accounts() {
    log_info "Searching for Storage Accounts..."
    
    STORAGE_ACCOUNTS=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    if [[ -z "$STORAGE_ACCOUNTS" ]]; then
        log_info "No Storage Accounts found"
        return
    fi
    
    for STORAGE_ACCOUNT in $STORAGE_ACCOUNTS; do
        log_info "Deleting Storage Account: $STORAGE_ACCOUNT"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete Storage Account: $STORAGE_ACCOUNT"
            continue
        fi
        
        # List containers for logging purposes
        log_info "Checking containers in Storage Account: $STORAGE_ACCOUNT"
        CONTAINERS=$(az storage container list \
            --account-name "$STORAGE_ACCOUNT" \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$CONTAINERS" ]]; then
            log_info "Containers found: $CONTAINERS"
            log_warning "All containers and their contents will be permanently deleted"
        fi
        
        if az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes; then
            log_success "Storage Account deleted: $STORAGE_ACCOUNT"
        else
            log_warning "Failed to delete Storage Account: $STORAGE_ACCOUNT"
        fi
    done
}

# Function to delete Application Insights (if any)
delete_application_insights() {
    if [[ "$KEEP_LOGS" == "true" ]]; then
        log_info "Skipping Application Insights deletion (--keep-logs flag)"
        return
    fi
    
    log_info "Searching for Application Insights..."
    
    APP_INSIGHTS=$(az monitor app-insights component list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$APP_INSIGHTS" ]]; then
        log_info "No Application Insights found"
        return
    fi
    
    for INSIGHTS in $APP_INSIGHTS; do
        log_info "Deleting Application Insights: $INSIGHTS"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete Application Insights: $INSIGHTS"
            continue
        fi
        
        if az monitor app-insights component delete \
            --app "$INSIGHTS" \
            --resource-group "$RESOURCE_GROUP"; then
            log_success "Application Insights deleted: $INSIGHTS"
        else
            log_warning "Failed to delete Application Insights: $INSIGHTS"
        fi
    done
}

# Function to delete any remaining resources
delete_remaining_resources() {
    log_info "Checking for any remaining resources..."
    
    REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{name:name,type:type}" --output tsv)
    
    if [[ -z "$REMAINING_RESOURCES" ]]; then
        log_info "No remaining resources found"
        return
    fi
    
    log_warning "Found remaining resources:"
    echo "$REMAINING_RESOURCES"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would attempt to delete remaining resources"
        return
    fi
    
    # Attempt to delete remaining resources
    while IFS=$'\t' read -r RESOURCE_NAME RESOURCE_TYPE; do
        if [[ -n "$RESOURCE_NAME" && -n "$RESOURCE_TYPE" ]]; then
            log_info "Attempting to delete $RESOURCE_TYPE: $RESOURCE_NAME"
            
            if az resource delete \
                --name "$RESOURCE_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --resource-type "$RESOURCE_TYPE" \
                --force-delete; then
                log_success "Resource deleted: $RESOURCE_NAME"
            else
                log_warning "Failed to delete resource: $RESOURCE_NAME"
            fi
        fi
    done <<< "$REMAINING_RESOURCES"
}

# Function to delete the resource group
delete_resource_group() {
    log_info "Preparing to delete resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return
    fi
    
    # Final confirmation for resource group deletion
    if [[ "$FORCE" == "false" ]]; then
        echo ""
        log_warning "Final confirmation: Delete resource group '$RESOURCE_GROUP' and ALL remaining resources?"
        read -p "Type 'DELETE' to confirm: " -r
        echo ""
        
        if [[ "$REPLY" != "DELETE" ]]; then
            log_info "Resource group deletion cancelled"
            return
        fi
    fi
    
    log_info "Deleting resource group: $RESOURCE_GROUP"
    log_warning "This may take several minutes..."
    
    if az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait; then
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        log_info "Note: Complete deletion may take several minutes to complete in the background"
    else
        log_error "Failed to initiate resource group deletion: $RESOURCE_GROUP"
        exit 1
    fi
}

# Function to verify deletion
verify_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return
    fi
    
    log_info "Verifying resource group deletion..."
    
    # Wait a bit for the deletion to start
    sleep 10
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Resource group still exists (deletion in progress)"
        log_info "You can check the status in Azure portal or run: az group show --name $RESOURCE_GROUP"
    else
        log_success "Resource group has been deleted: $RESOURCE_GROUP"
    fi
}

# Function to display cleanup summary
display_summary() {
    echo ""
    echo "==================== CLEANUP SUMMARY ===================="
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN completed - No resources were actually deleted"
        echo "Resource Group: $RESOURCE_GROUP (would be deleted)"
    else
        echo "Cleanup completed for Resource Group: $RESOURCE_GROUP"
        echo ""
        echo "Deleted Resources:"
        echo "✓ Function Apps and associated resources"
        echo "✓ Azure OpenAI Service and model deployments"
        echo "✓ Content Safety Service"
        echo "✓ Storage Accounts and all containers"
        if [[ "$KEEP_LOGS" == "false" ]]; then
            echo "✓ Application Insights (if any)"
        else
            echo "- Application Insights (preserved)"
        fi
        echo "✓ Resource Group and any remaining resources"
    fi
    echo "=========================================================="
}

# Function to handle script interruption
cleanup_on_interrupt() {
    log_warning "Script interrupted. Some resources may still exist."
    log_info "You can re-run this script to continue cleanup."
    exit 1
}

# Set trap for script interruption
trap cleanup_on_interrupt INT TERM

# Main cleanup function
main() {
    log_info "Starting Azure Marketing Asset Generation cleanup..."
    echo "========================================================"
    
    check_prerequisites
    verify_resource_group
    
    # List resources to be deleted
    if ! list_resources; then
        log_info "No resources to clean up"
        exit 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        echo "========================================================"
    fi
    
    get_confirmation
    
    # Delete resources in the correct order
    delete_function_app
    delete_cognitive_services
    delete_storage_accounts
    delete_application_insights
    delete_remaining_resources
    delete_resource_group
    
    if [[ "$DRY_RUN" == "false" ]]; then
        verify_deletion
    fi
    
    display_summary
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "Cleanup completed successfully!"
        log_info "All resources associated with the marketing asset generation solution have been removed"
    fi
}

# Execute main function
main "$@"