#!/bin/bash

# Voice-to-Multilingual Content Pipeline Cleanup Script
# This script destroys Azure resources created for the voice processing pipeline

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

# Configuration variables  
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_GROUP=""
DRY_RUN=false
FORCE=false
DELETE_RESOURCE_GROUP=false

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Azure Voice-to-Multilingual Content Pipeline resources

OPTIONS:
    -g, --resource-group        Azure resource group name (required)
    -r, --delete-resource-group Delete the entire resource group
    -f, --force                 Skip confirmation prompts
    -d, --dry-run              Show what would be deleted without actually deleting
    -h, --help                 Show this help message

EXAMPLES:
    $0 -g my-voice-pipeline-rg
    $0 -g my-voice-pipeline-rg --delete-resource-group
    $0 -g my-voice-pipeline-rg --force --dry-run

SAFETY:
    This script will DELETE resources and cannot be undone.
    Always review what will be deleted before proceeding.

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -r|--delete-resource-group)
            DELETE_RESOURCE_GROUP=true
            shift
            ;;
        -f|--force)
            FORCE=true
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
    log_error "Resource group name is required. Use -g or --resource-group"
    usage
    exit 1
fi

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group '$RESOURCE_GROUP' does not exist"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to list resources in resource group
list_resources() {
    log_info "Resources in resource group '$RESOURCE_GROUP':"
    
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table)
    
    if [[ -z "$resources" || "$resources" == "[]" ]]; then
        log_warning "No resources found in resource group '$RESOURCE_GROUP'"
        return 1
    fi
    
    echo "$resources"
    echo ""
    
    # Count resources
    local resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv)
    log_info "Total resources: $resource_count"
    
    return 0
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will permanently delete the following:"
    
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        echo "- The entire resource group: $RESOURCE_GROUP"
        echo "- ALL resources within the resource group"
    else
        echo "- Individual voice pipeline resources in: $RESOURCE_GROUP"
    fi
    
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
}

# Function to delete individual resources
delete_individual_resources() {
    log_info "Deleting individual voice pipeline resources..."
    
    # Get all resources in the resource group
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{id:id, name:name, type:type}" --output json)
    
    if [[ "$resources" == "[]" ]]; then
        log_warning "No resources found to delete"
        return
    fi
    
    # Parse resource types and delete in proper order
    local function_apps=$(echo "$resources" | jq -r '.[] | select(.type=="Microsoft.Web/sites") | .name')
    local storage_accounts=$(echo "$resources" | jq -r '.[] | select(.type=="Microsoft.Storage/storageAccounts") | .name')
    local cognitive_services=$(echo "$resources" | jq -r '.[] | select(.type=="Microsoft.CognitiveServices/accounts") | .name')
    local app_service_plans=$(echo "$resources" | jq -r '.[] | select(.type=="Microsoft.Web/serverfarms") | .name')
    
    # Delete Function Apps first
    for app in $function_apps; do
        if [[ -n "$app" ]]; then
            log_info "Deleting Function App: $app"
            if [[ "$DRY_RUN" == "false" ]]; then
                az functionapp delete \
                    --name "$app" \
                    --resource-group "$RESOURCE_GROUP"
                log_success "Function App deleted: $app"
            else
                log_info "[DRY RUN] Would delete Function App: $app"
            fi
        fi
    done
    
    # Delete App Service Plans
    for plan in $app_service_plans; do
        if [[ -n "$plan" ]]; then
            log_info "Deleting App Service Plan: $plan"
            if [[ "$DRY_RUN" == "false" ]]; then
                az appservice plan delete \
                    --name "$plan" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes
                log_success "App Service Plan deleted: $plan"
            else
                log_info "[DRY RUN] Would delete App Service Plan: $plan"
            fi
        fi
    done
    
    # Delete Cognitive Services
    for service in $cognitive_services; do
        if [[ -n "$service" ]]; then
            log_info "Deleting Cognitive Service: $service"
            if [[ "$DRY_RUN" == "false" ]]; then
                az cognitiveservices account delete \
                    --name "$service" \
                    --resource-group "$RESOURCE_GROUP"
                log_success "Cognitive Service deleted: $service"
            else
                log_info "[DRY RUN] Would delete Cognitive Service: $service"
            fi
        fi
    done
    
    # Delete Storage Accounts last
    for storage in $storage_accounts; do
        if [[ -n "$storage" ]]; then
            log_info "Deleting Storage Account: $storage"
            if [[ "$DRY_RUN" == "false" ]]; then
                az storage account delete \
                    --name "$storage" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes
                log_success "Storage Account deleted: $storage"
            else
                log_info "[DRY RUN] Would delete Storage Account: $storage"
            fi
        fi
    done
}

# Function to delete entire resource group
delete_resource_group() {
    log_info "Deleting entire resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return
    fi
    
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
    log_info "Note: Complete deletion may take several minutes"
}

# Function to verify deletion
verify_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return
    fi
    
    log_info "Verifying resource deletion..."
    
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        # Check if resource group still exists
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log_warning "Resource group still exists (deletion in progress)"
        else
            log_success "Resource group successfully deleted"
        fi
    else
        # Check remaining resources
        local remaining=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining" -eq 0 ]]; then
            log_success "All voice pipeline resources deleted"
        else
            log_warning "$remaining resources still remain in the resource group"
            list_resources
        fi
    fi
}

# Function to cleanup local environment variables
cleanup_environment() {
    log_info "Cleaning up environment variables..."
    
    # Note: This only affects the current script session
    unset RESOURCE_GROUP 2>/dev/null || true
    unset RANDOM_SUFFIX 2>/dev/null || true
    unset STORAGE_ACCOUNT 2>/dev/null || true
    unset FUNCTION_APP 2>/dev/null || true
    unset SPEECH_SERVICE 2>/dev/null || true
    unset OPENAI_SERVICE 2>/dev/null || true
    unset TRANSLATOR_SERVICE 2>/dev/null || true
    
    log_info "Environment variables cleared"
}

# Function to display cleanup summary
display_summary() {
    log_info "Cleanup Summary"
    echo "=================================="
    echo "Resource Group: $RESOURCE_GROUP"
    
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        echo "Action: Deleted entire resource group"
    else
        echo "Action: Deleted individual resources"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Mode: DRY RUN (no resources actually deleted)"
    else
        echo "Mode: LIVE DELETION"
    fi
    
    echo ""
    echo "What was cleaned up:"
    echo "- Azure Function Apps"
    echo "- App Service Plans"
    echo "- Cognitive Services (Speech, OpenAI, Translator)"
    echo "- Storage Accounts and containers"
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        echo "- Resource Group"
    fi
    echo "=================================="
}

# Main cleanup function
main() {
    log_info "Starting Voice-to-Multilingual Content Pipeline cleanup"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Execute cleanup steps
    check_prerequisites
    
    # List resources before deletion
    if ! list_resources; then
        log_info "No resources to clean up"
        exit 0
    fi
    
    # Confirm deletion
    confirm_deletion
    
    # Perform deletion
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        delete_resource_group
    else
        delete_individual_resources
    fi
    
    # Verify and summarize
    verify_deletion
    cleanup_environment
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed successfully"
    else
        log_success "Cleanup completed successfully!"
    fi
    
    display_summary
}

# Trap errors
trap 'log_error "Cleanup failed at line $LINENO"' ERR

# Run main function
main "$@"