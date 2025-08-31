#!/bin/bash

# ==============================================================================
# Azure RAG Knowledge Base Cleanup Script
# ==============================================================================
# This script safely removes all Azure resources created by the RAG Knowledge
# Base deployment, including proper cleanup order and confirmation prompts.
# ==============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.env"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ==============================================================================
# Utility Functions
# ==============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "${RED}❌ $*${NC}"
}

print_banner() {
    echo ""
    echo "=================================================================="
    echo "  Azure RAG Knowledge Base Cleanup Script"
    echo "=================================================================="
    echo ""
}

# ==============================================================================
# Configuration Loading and Validation
# ==============================================================================

load_configuration() {
    log_info "Loading configuration from deployment..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_error "This script requires the configuration file created during deployment."
        exit 1
    fi
    
    # Source the configuration file
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    
    # Validate required variables
    local required_vars=(
        "RESOURCE_GROUP"
        "STORAGE_ACCOUNT"
        "SEARCH_SERVICE"
        "FUNCTION_APP"
        "OPENAI_SERVICE"
        "SUBSCRIPTION_ID"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var is not set in configuration file"
            exit 1
        fi
    done
    
    log_info "Configuration loaded successfully"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Subscription: $SUBSCRIPTION_ID"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI login status
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    # Verify we're in the correct subscription
    local current_subscription
    current_subscription=$(az account show --query id --output tsv)
    
    if [[ "$current_subscription" != "$SUBSCRIPTION_ID" ]]; then
        log_warning "Current subscription ($current_subscription) differs from deployment subscription ($SUBSCRIPTION_ID)"
        read -p "Do you want to switch to the deployment subscription? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            az account set --subscription "$SUBSCRIPTION_ID"
            log_info "Switched to subscription: $SUBSCRIPTION_ID"
        else
            log_error "Cleanup cancelled - subscription mismatch"
            exit 1
        fi
    fi
    
    log_success "Prerequisites check passed"
}

# ==============================================================================
# Resource Validation and Confirmation
# ==============================================================================

validate_resources() {
    log_info "Validating resources to be deleted..."
    
    local resources_found=0
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_info "✓ Resource Group: $RESOURCE_GROUP"
        ((resources_found++))
        
        # List all resources in the group
        local resource_list
        resource_list=$(az resource list --resource-group "$RESOURCE_GROUP" \
            --query "[].{Name:name, Type:type}" \
            --output table 2>/dev/null)
        
        if [[ -n "$resource_list" ]]; then
            echo ""
            echo "Resources in $RESOURCE_GROUP:"
            echo "$resource_list"
            echo ""
        fi
    else
        log_warning "Resource Group not found: $RESOURCE_GROUP"
    fi
    
    # Check individual resources
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "✓ Storage Account: $STORAGE_ACCOUNT"
        ((resources_found++))
    fi
    
    if az search service show --name "$SEARCH_SERVICE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "✓ Search Service: $SEARCH_SERVICE"
        ((resources_found++))
    fi
    
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "✓ Function App: $FUNCTION_APP"
        ((resources_found++))
    fi
    
    if az cognitiveservices account show --name "$OPENAI_SERVICE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "✓ OpenAI Service: $OPENAI_SERVICE"
        ((resources_found++))
    fi
    
    if [[ $resources_found -eq 0 ]]; then
        log_warning "No resources found to delete. They may have already been cleaned up."
        exit 0
    fi
    
    log_info "Found $resources_found resources to be deleted"
}

confirm_deletion() {
    echo ""
    echo "=================================================================="
    echo "⚠️  WARNING: DESTRUCTIVE OPERATION"
    echo "=================================================================="
    echo ""
    echo "This will permanently delete the following resources:"
    echo "  • Resource Group: $RESOURCE_GROUP"
    echo "  • All resources within the resource group"
    echo "  • All data stored in these resources"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    # Double confirmation for safety
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    if [[ "$REPLY" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    read -p "Final confirmation - Type the resource group name to proceed: " -r
    if [[ "$REPLY" != "$RESOURCE_GROUP" ]]; then
        log_error "Resource group name mismatch. Cleanup cancelled for safety."
        exit 1
    fi
    
    log_info "Deletion confirmed by user"
}

# ==============================================================================
# Resource Cleanup Functions
# ==============================================================================

cleanup_individual_resources() {
    log_info "Starting individual resource cleanup (safer approach)..."
    
    # Delete Function App first (dependent on storage)
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Deleting Function App: $FUNCTION_APP"
        az functionapp delete \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --output none 2>/dev/null || log_warning "Failed to delete Function App"
        log_success "Function App deleted: $FUNCTION_APP"
    fi
    
    # Delete Search Service
    if az search service show --name "$SEARCH_SERVICE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Deleting AI Search Service: $SEARCH_SERVICE"
        az search service delete \
            --name "$SEARCH_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none 2>/dev/null || log_warning "Failed to delete Search Service"
        log_success "AI Search Service deleted: $SEARCH_SERVICE"
    fi
    
    # Delete OpenAI Service
    if az cognitiveservices account show --name "$OPENAI_SERVICE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Deleting OpenAI Service: $OPENAI_SERVICE"
        az cognitiveservices account delete \
            --name "$OPENAI_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --output none 2>/dev/null || log_warning "Failed to delete OpenAI Service"
        log_success "OpenAI Service deleted: $OPENAI_SERVICE"
    fi
    
    # Delete Storage Account last
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Deleting Storage Account: $STORAGE_ACCOUNT"
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none 2>/dev/null || log_warning "Failed to delete Storage Account"
        log_success "Storage Account deleted: $STORAGE_ACCOUNT"
    fi
}

cleanup_resource_group() {
    log_info "Deleting Resource Group: $RESOURCE_GROUP"
    
    # Use --no-wait for faster completion, but then wait for completion
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none
    
    # Wait for resource group deletion to complete
    log_info "Waiting for resource group deletion to complete..."
    local max_wait_minutes=15
    local wait_count=0
    
    while az group show --name "$RESOURCE_GROUP" &> /dev/null; do
        if [[ $wait_count -ge $max_wait_minutes ]]; then
            log_warning "Resource group deletion is taking longer than expected"
            log_info "You can check the status in the Azure portal or run: az group show --name $RESOURCE_GROUP"
            break
        fi
        
        sleep 60
        ((wait_count++))
        log_info "Still waiting... ($wait_count/$max_wait_minutes minutes)"
    done
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_success "Resource Group deleted successfully: $RESOURCE_GROUP"
    else
        log_warning "Resource Group deletion may still be in progress: $RESOURCE_GROUP"
    fi
}

cleanup_local_files() {
    log_info "Cleaning up local files and configuration..."
    
    # Remove temporary files that might have been created
    local temp_files=(
        "sample-doc1.txt"
        "sample-doc2.txt"
        "search-index.json"
        "data-source.json"
        "indexer.json"
        "function-package.zip"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed temporary file: $file"
        fi
    done
    
    # Remove function directory if it exists
    if [[ -d "rag-function" ]]; then
        rm -rf rag-function
        log_info "Removed function directory"
    fi
    
    # Optionally remove configuration file
    echo ""
    read -p "Do you want to remove the configuration file ($CONFIG_FILE)? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$CONFIG_FILE"
        log_success "Configuration file removed"
    else
        log_info "Configuration file preserved for reference"
    fi
}

# ==============================================================================
# Cost Estimation and Warnings
# ==============================================================================

show_cost_warnings() {
    echo ""
    echo "=================================================================="
    echo "💰 COST CONSIDERATIONS"
    echo "=================================================================="
    echo ""
    echo "Please note the following regarding potential charges:"
    echo ""
    echo "• Storage Account: Charges may continue until deletion completes"
    echo "• AI Search Service: Billing stops when service is deleted"
    echo "• OpenAI Service: Check for any remaining token usage charges"
    echo "• Function App: Consumption plan has no idle charges"
    echo ""
    echo "• Deleted resources may take up to 24 hours to stop billing"
    echo "• Check your Azure bill to ensure no unexpected charges"
    echo ""
}

# ==============================================================================
# Main Cleanup Process
# ==============================================================================

main() {
    print_banner
    
    log_info "Starting Azure RAG Knowledge Base cleanup..."
    log_info "Log file: $LOG_FILE"
    
    # Load configuration and validate
    load_configuration
    check_prerequisites
    validate_resources
    
    # Confirm deletion with user
    confirm_deletion
    
    # Show cost warnings
    show_cost_warnings
    
    # Perform cleanup
    log_info "Starting resource cleanup process..."
    
    # Method 1: Delete individual resources first (safer)
    cleanup_individual_resources
    
    # Wait a moment for resources to be fully deleted
    log_info "Waiting for individual resource deletions to complete..."
    sleep 30
    
    # Method 2: Delete entire resource group
    cleanup_resource_group
    
    # Clean up local files
    cleanup_local_files
    
    # Final success message
    echo ""
    echo "=================================================================="
    log_success "Azure RAG Knowledge Base cleanup completed!"
    echo "=================================================================="
    echo ""
    echo "Resources deleted:"
    echo "  • Resource Group: $RESOURCE_GROUP"
    echo "  • Storage Account: $STORAGE_ACCOUNT"
    echo "  • Search Service: $SEARCH_SERVICE"
    echo "  • Function App: $FUNCTION_APP"
    echo "  • OpenAI Service: $OPENAI_SERVICE"
    echo ""
    echo "Cleanup log: $LOG_FILE"
    echo ""
    echo "⚠️  Important reminders:"
    echo "• Check your Azure portal to ensure all resources are deleted"
    echo "• Monitor your Azure bill for any remaining charges"
    echo "• Resource deletions may take several minutes to complete"
    echo ""
}

# ==============================================================================
# Script Options and Help
# ==============================================================================

show_help() {
    echo "Azure RAG Knowledge Base Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h          Show this help message"
    echo "  --force             Skip confirmation prompts (dangerous!)"
    echo "  --config FILE       Use custom configuration file"
    echo ""
    echo "Examples:"
    echo "  $0                  Interactive cleanup with confirmations"
    echo "  $0 --force          Non-interactive cleanup (use with caution)"
    echo "  $0 --config .env    Use custom configuration file"
    echo ""
}

# Parse command line arguments
FORCE_MODE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --force)
            FORCE_MODE=true
            shift
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Override confirmation function if force mode is enabled
if [[ "$FORCE_MODE" == "true" ]]; then
    confirm_deletion() {
        log_warning "Force mode enabled - skipping confirmation prompts"
        log_warning "This will delete all resources without further confirmation!"
        sleep 3
    }
fi

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi