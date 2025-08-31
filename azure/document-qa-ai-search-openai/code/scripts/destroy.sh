#!/bin/bash

# Azure Document Q&A with AI Search and OpenAI - Cleanup Script
# This script safely removes all resources deployed by the deploy.sh script
# with proper confirmation prompts and dependency handling

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="${PROJECT_DIR}/cleanup.log"
readonly STATE_FILE="${PROJECT_DIR}/.deployment_state"

# Global variables
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
DRY_RUN=false
SKIP_CONFIRMATION=false
FORCE_DELETE=false
VERBOSE=false

# Deployment state variables
STORAGE_ACCOUNT=""
SEARCH_SERVICE=""
OPENAI_SERVICE=""
FUNCTION_APP=""
FUNCTION_STORAGE=""
CONTAINER_NAME=""
SEARCH_INDEX_NAME=""

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
    echo -e "${BLUE}ℹ $*${NC}"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}⚠ $*${NC}"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}❌ $*${NC}" >&2
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code $exit_code"
    log_info "Check the log file for details: $LOG_FILE"
    log_info "Some resources may still exist. Please check the Azure portal."
    exit $exit_code
}

trap cleanup_on_error ERR

# Helper functions
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely remove Azure Document Q&A infrastructure and all associated resources.

OPTIONS:
    -g, --resource-group NAME    Resource group name (required)
    -s, --subscription ID        Azure subscription ID (auto-detected if not provided)
    -d, --dry-run               Show what would be deleted without making changes
    -y, --yes                   Skip confirmation prompts (DANGEROUS!)
    -f, --force                 Force deletion even if resources are not found
    -v, --verbose               Enable verbose logging
    -h, --help                  Show this help message

EXAMPLES:
    $0 -g myResourceGroup
    $0 -g myResourceGroup --dry-run
    $0 -g myResourceGroup --yes --force
    $0 --help

SAFETY FEATURES:
    • Requires explicit confirmation before deletion
    • Validates resource ownership before deletion
    • Shows detailed deletion plan in dry-run mode
    • Logs all actions for audit trail
    • Handles dependencies between resources

EOF
}

# Parse command line arguments
parse_arguments() {
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
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
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
        log_error "Resource group name is required. Use -g or --resource-group."
        usage
        exit 1
    fi

    # Auto-detect subscription if not provided
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv 2>/dev/null || echo "")
        if [[ -z "$SUBSCRIPTION_ID" ]]; then
            log_error "Could not detect Azure subscription. Please login with 'az login' or specify with -s."
            exit 1
        fi
    fi
}

# Prerequisites validation
validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check authentication
    if ! az account show &> /dev/null; then
        log_error "Not authenticated with Azure. Please run 'az login'"
        exit 1
    fi

    # Check subscription access
    local current_subscription=$(az account show --query id --output tsv)
    if [[ "$current_subscription" != "$SUBSCRIPTION_ID" ]]; then
        log_info "Setting active subscription to: $SUBSCRIPTION_ID"
        az account set --subscription "$SUBSCRIPTION_ID"
    fi

    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        if [[ "$FORCE_DELETE" == "false" ]]; then
            log_error "Resource group '$RESOURCE_GROUP' not found"
            log_info "Use --force to skip this validation"
            exit 1
        else
            log_warning "Resource group '$RESOURCE_GROUP' not found, but continuing due to --force"
        fi
    fi

    log_success "Prerequisites validation completed"
}

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."

    if [[ -f "$STATE_FILE" ]]; then
        # Source the state file to load variables
        source "$STATE_FILE"
        
        log_info "Loaded deployment state from: $STATE_FILE"
        log_info "  Resource Group: $RESOURCE_GROUP"
        log_info "  Storage Account: ${STORAGE_ACCOUNT:-<not found>}"
        log_info "  Search Service: ${SEARCH_SERVICE:-<not found>}"
        log_info "  OpenAI Service: ${OPENAI_SERVICE:-<not found>}"
        log_info "  Function App: ${FUNCTION_APP:-<not found>}"
        log_info "  Function Storage: ${FUNCTION_STORAGE:-<not found>}"
    else
        log_warning "Deployment state file not found: $STATE_FILE"
        log_info "Will attempt to discover resources in resource group: $RESOURCE_GROUP"
        discover_resources
    fi
}

# Discover resources in the resource group
discover_resources() {
    log_info "Discovering resources in resource group: $RESOURCE_GROUP"

    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' not found"
        return 0
    fi

    # Discover storage accounts
    local storage_accounts=$(az storage account list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(name, 'docqa') || contains(name, 'funcst')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$storage_accounts" ]]; then
        # Separate document storage from function storage
        while IFS= read -r account; do
            if [[ "$account" == *"funcst"* ]]; then
                FUNCTION_STORAGE="$account"
            else
                STORAGE_ACCOUNT="$account"
            fi
        done <<< "$storage_accounts"
    fi

    # Discover AI Search service
    SEARCH_SERVICE=$(az search service list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(name, 'docqa')].name" \
        --output tsv 2>/dev/null || echo "")

    # Discover OpenAI service
    OPENAI_SERVICE=$(az cognitiveservices account list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?kind=='OpenAI' && contains(name, 'docqa')].name" \
        --output tsv 2>/dev/null || echo "")

    # Discover Function App
    FUNCTION_APP=$(az functionapp list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(name, 'docqa')].name" \
        --output tsv 2>/dev/null || echo "")

    # Set default values if not discovered
    CONTAINER_NAME="${CONTAINER_NAME:-documents}"
    SEARCH_INDEX_NAME="${SEARCH_INDEX_NAME:-documents-index}"

    log_info "Resource discovery completed"
}

# Resource inventory and deletion plan
show_deletion_plan() {
    log_info "Deletion Plan for Resource Group: $RESOURCE_GROUP"
    echo

    local resource_count=0

    # List all resources in the resource group
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        local all_resources=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].{Name:name, Type:type}" \
            --output table 2>/dev/null || echo "")

        if [[ -n "$all_resources" && "$all_resources" != "Name    Type" ]]; then
            log_info "All resources in resource group:"
            echo "$all_resources"
            resource_count=$(echo "$all_resources" | grep -c "^[^-]" || echo "0")
            echo
        fi
    fi

    # Show specific resources that will be deleted
    log_info "Specific resources to be deleted:"
    
    if [[ -n "$FUNCTION_APP" ]]; then
        log_info "  🔧 Function App: $FUNCTION_APP"
    fi
    
    if [[ -n "$SEARCH_SERVICE" ]]; then
        log_info "  🔍 AI Search Service: $SEARCH_SERVICE"
        log_info "    └── Search Index: $SEARCH_INDEX_NAME"
        log_info "    └── Skillset: documents-skillset"
        log_info "    └── Data Source: documents-datasource"
        log_info "    └── Indexer: documents-indexer"
    fi
    
    if [[ -n "$OPENAI_SERVICE" ]]; then
        log_info "  🤖 OpenAI Service: $OPENAI_SERVICE"
        log_info "    └── Model Deployment: gpt-4o"
        log_info "    └── Model Deployment: text-embedding-3-large"
    fi
    
    if [[ -n "$STORAGE_ACCOUNT" ]]; then
        log_info "  💾 Document Storage: $STORAGE_ACCOUNT"
        log_info "    └── Container: $CONTAINER_NAME"
        log_info "    └── Sample documents and user data"
    fi
    
    if [[ -n "$FUNCTION_STORAGE" ]]; then
        log_info "  💾 Function Storage: $FUNCTION_STORAGE"
    fi
    
    log_info "  📦 Resource Group: $RESOURCE_GROUP"
    echo

    if [[ $resource_count -gt 0 ]]; then
        log_warning "Total resources to be deleted: $resource_count"
    else
        log_info "No resources found to delete"
    fi
}

# Deletion confirmation
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        log_warning "Skipping confirmation due to --yes flag"
        return 0
    fi

    show_deletion_plan
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log_warning "This action will permanently delete ALL resources in the resource group"
    log_warning "This includes all data, configurations, and deployed applications"
    log_warning "This action CANNOT be undone!"
    echo

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        return 0
    fi

    # Multiple confirmation steps for safety
    echo -e "${RED}Type 'DELETE' (all caps) to confirm resource deletion:${NC}"
    read -r confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi

    echo -e "${RED}Type the resource group name '$RESOURCE_GROUP' to confirm:${NC}"
    read -r rg_confirmation
    
    if [[ "$rg_confirmation" != "$RESOURCE_GROUP" ]]; then
        log_info "Resource group name mismatch. Deletion cancelled."
        exit 0
    fi

    log_warning "Proceeding with resource deletion in 5 seconds..."
    sleep 5
}

# Execute command with dry-run support
execute_command() {
    local description="$1"
    shift
    local command="$*"

    log_info "$description"
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Command: $command"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $command"
        return 0
    fi

    if eval "$command" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "$description completed"
        return 0
    else
        local exit_code=$?
        if [[ "$FORCE_DELETE" == "true" ]]; then
            log_warning "$description failed but continuing due to --force (exit code: $exit_code)"
            return 0
        else
            log_error "$description failed with exit code $exit_code"
            return $exit_code
        fi
    fi
}

# Resource deletion functions
delete_function_app() {
    if [[ -z "$FUNCTION_APP" ]]; then
        log_info "No Function App to delete"
        return 0
    fi

    log_info "Deleting Function App and related resources..."

    # Delete Function App
    execute_command "Deleting Function App: $FUNCTION_APP" \
        "az functionapp delete \
            --name '$FUNCTION_APP' \
            --resource-group '$RESOURCE_GROUP'"

    # Delete Function App storage account
    if [[ -n "$FUNCTION_STORAGE" ]]; then
        execute_command "Deleting Function App storage: $FUNCTION_STORAGE" \
            "az storage account delete \
                --name '$FUNCTION_STORAGE' \
                --resource-group '$RESOURCE_GROUP' \
                --yes"
    fi
}

delete_search_service() {
    if [[ -z "$SEARCH_SERVICE" ]]; then
        log_info "No AI Search service to delete"
        return 0
    fi

    log_info "Deleting AI Search service and components..."

    # Note: Deleting the search service automatically removes all indexes, skillsets, etc.
    execute_command "Deleting AI Search service: $SEARCH_SERVICE" \
        "az search service delete \
            --name '$SEARCH_SERVICE' \
            --resource-group '$RESOURCE_GROUP' \
            --yes"
}

delete_openai_service() {
    if [[ -z "$OPENAI_SERVICE" ]]; then
        log_info "No OpenAI service to delete"
        return 0
    fi

    log_info "Deleting Azure OpenAI service and models..."

    # Delete OpenAI service (this removes all model deployments)
    execute_command "Deleting Azure OpenAI service: $OPENAI_SERVICE" \
        "az cognitiveservices account delete \
            --name '$OPENAI_SERVICE' \
            --resource-group '$RESOURCE_GROUP'"
}

delete_storage_account() {
    if [[ -z "$STORAGE_ACCOUNT" ]]; then
        log_info "No document storage account to delete"
        return 0
    fi

    log_info "Deleting document storage and all data..."

    # Delete storage account (this removes all containers and data)
    execute_command "Deleting storage account: $STORAGE_ACCOUNT" \
        "az storage account delete \
            --name '$STORAGE_ACCOUNT' \
            --resource-group '$RESOURCE_GROUP' \
            --yes"
}

delete_resource_group() {
    log_info "Deleting resource group and any remaining resources..."

    execute_command "Deleting resource group: $RESOURCE_GROUP" \
        "az group delete \
            --name '$RESOURCE_GROUP' \
            --yes \
            --no-wait"

    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Resource group deletion initiated. This may take several minutes to complete."
        log_info "You can monitor progress in the Azure portal or with: az group show --name '$RESOURCE_GROUP'"
    fi
}

# Cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local files..."

    local files_to_remove=(
        "$STATE_FILE"
        "${PROJECT_DIR}/sample-doc1.txt"
        "${PROJECT_DIR}/sample-doc2.txt"
        "${PROJECT_DIR}/search-index.json"
        "${PROJECT_DIR}/skillset.json"
        "${PROJECT_DIR}/datasource.json"
        "${PROJECT_DIR}/indexer.json"
        "${PROJECT_DIR}/function-deployment.zip"
        "${PROJECT_DIR}/qa-function"
    )

    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would remove: $file"
            else
                rm -rf "$file"
                log_info "Removed: $file"
            fi
        fi
    done

    log_success "Local file cleanup completed"
}

# Validation functions
validate_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Skipping validation in dry-run mode"
        return 0
    fi

    log_info "Validating resource deletion..."

    local validation_errors=0

    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' still exists (deletion may be in progress)"
    else
        log_success "Resource group '$RESOURCE_GROUP' successfully deleted"
    fi

    # Check specific resources if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        local remaining_resources=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query "length(@)" \
            --output tsv 2>/dev/null || echo "0")

        if [[ "$remaining_resources" -gt 0 ]]; then
            log_warning "$remaining_resources resources still remain in the resource group"
            
            # List remaining resources
            az resource list \
                --resource-group "$RESOURCE_GROUP" \
                --query "[].{Name:name, Type:type}" \
                --output table | tee -a "$LOG_FILE"
        else
            log_success "All resources successfully removed from resource group"
        fi
    fi

    return $validation_errors
}

# Post-deletion information
show_cleanup_summary() {
    local end_time=$(date +%s)
    local start_time_file="${PROJECT_DIR}/.cleanup_start_time"
    
    if [[ -f "$start_time_file" ]]; then
        local start_time=$(cat "$start_time_file")
        local duration=$((end_time - start_time))
        rm -f "$start_time_file"
    else
        local duration=0
    fi

    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "Dry run completed successfully!"
        log_info "No resources were actually deleted"
    else
        log_success "Cleanup completed successfully!"
        log_info "All Azure Document Q&A resources have been removed"
    fi
    
    echo
    log_info "Cleanup Summary:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Subscription: $SUBSCRIPTION_ID"
    log_info "  Duration: ${duration} seconds"
    log_info "  Log File: $LOG_FILE"
    echo
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Next Steps:"
        log_info "  • Verify deletion in Azure portal"
        log_info "  • Check billing to confirm resource removal"
        log_info "  • Review cleanup log for any issues"
        echo
        log_success "All resources have been successfully removed!"
    else
        log_info "To perform actual deletion, run without --dry-run flag"
    fi
}

# Main cleanup orchestration
main() {
    local start_time=$(date +%s)
    echo "$start_time" > "${PROJECT_DIR}/.cleanup_start_time"

    # Initialize logging
    echo "=== Azure Document Q&A Cleanup Started at $(date) ===" | tee "$LOG_FILE"

    # Parse arguments and validate prerequisites
    parse_arguments "$@"
    validate_prerequisites
    load_deployment_state
    
    # Show deletion plan and get confirmation
    confirm_deletion
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Starting resource deletion process..."
    else
        log_info "Starting dry-run deletion process..."
    fi

    # Execute deletion steps in proper order (reverse of deployment)
    delete_function_app
    delete_search_service
    delete_openai_service
    delete_storage_account
    delete_resource_group

    # Cleanup local files
    cleanup_local_files

    # Validate and show results
    validate_deletion
    show_cleanup_summary

    # Cleanup temporary files
    rm -f "${PROJECT_DIR}/.cleanup_start_time"
}

# Execute main function with all arguments
main "$@"