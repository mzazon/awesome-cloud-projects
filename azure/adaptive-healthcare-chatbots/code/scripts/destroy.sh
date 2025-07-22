#!/bin/bash

# ==============================================================================
# CLEANUP SCRIPT: Personalized Healthcare Chatbots
# ==============================================================================
# This script safely removes all Azure resources created by the healthcare
# chatbot deployment script.
#
# Recipe: Developing Personalized Healthcare Chatbots with Azure Health Bot 
#         and Azure Personalizer
# Version: 1.0
# ==============================================================================

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="healthcare-chatbot-cleanup-$(date +%Y%m%d-%H%M%S).log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENV_FILE="${SCRIPT_DIR}/.env"

# Global variables
declare -a CLEANUP_ERRORS=()
declare -g CONFIRMATION_REQUIRED=true
declare -g DRY_RUN=false

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "$*"
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    log "SUCCESS" "$*"
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "$*"
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "$*"
    echo -e "${RED}❌ $*${NC}"
    CLEANUP_ERRORS+=("$*")
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --force             Skip confirmation prompts
    --dry-run           Show what would be deleted without actually deleting
    --resource-group    Specify resource group name (overrides .env file)
    --help              Show this help message

Examples:
    $0                  # Interactive cleanup with confirmations
    $0 --force          # Force cleanup without prompts
    $0 --dry-run        # Preview what would be deleted
    $0 --resource-group my-rg --force

EOF
}

confirm_action() {
    local action="$1"
    local resource="$2"
    
    if [[ "$CONFIRMATION_REQUIRED" == "false" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}⚠️  About to ${action}: ${resource}${NC}"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Skipped ${action} for ${resource}"
        return 1
    fi
    return 0
}

check_prerequisites() {
    log_info "Checking cleanup prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' and try again."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

load_environment() {
    log_info "Loading environment configuration..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "Environment file not found: $ENV_FILE"
        log_error "Cannot determine resources to clean up. Please specify --resource-group manually."
        exit 1
    fi
    
    # Source environment variables
    set -a
    source "$ENV_FILE"
    set +a
    
    log_info "Loaded environment variables from: $ENV_FILE"
    log_info "Resource Group: ${RESOURCE_GROUP:-not set}"
    log_info "Random Suffix: ${RANDOM_SUFFIX:-not set}"
    
    # Validate required variables
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_error "RESOURCE_GROUP not found in environment file"
        exit 1
    fi
}

# ==============================================================================
# RESOURCE CLEANUP FUNCTIONS
# ==============================================================================

cleanup_api_management() {
    local service_name="${APIM_NAME:-apim-${RANDOM_SUFFIX}}"
    
    log_info "Cleaning up API Management service: $service_name"
    
    if ! confirm_action "delete API Management service" "$service_name"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete API Management service: $service_name"
        return 0
    fi
    
    if az apim show --name "$service_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Deleting API Management service (this may take 30+ minutes)..."
        
        if az apim delete \
            --name "$service_name" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --no-wait; then
            log_success "API Management service deletion initiated: $service_name"
        else
            log_error "Failed to delete API Management service: $service_name"
        fi
    else
        log_info "API Management service not found: $service_name"
    fi
}

cleanup_function_app() {
    local function_name="${FUNCTION_APP_NAME:-func-${RANDOM_SUFFIX}}"
    
    log_info "Cleaning up Function App: $function_name"
    
    if ! confirm_action "delete Function App" "$function_name"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Function App: $function_name"
        return 0
    fi
    
    if az functionapp show --name "$function_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        if az functionapp delete \
            --name "$function_name" \
            --resource-group "$RESOURCE_GROUP"; then
            log_success "Function App deleted: $function_name"
        else
            log_error "Failed to delete Function App: $function_name"
        fi
    else
        log_info "Function App not found: $function_name"
    fi
}

cleanup_storage_account() {
    local storage_name="${STORAGE_ACCOUNT_NAME:-st${RANDOM_SUFFIX}}"
    
    log_info "Cleaning up storage account: $storage_name"
    
    if ! confirm_action "delete storage account" "$storage_name"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete storage account: $storage_name"
        return 0
    fi
    
    if az storage account show --name "$storage_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        if az storage account delete \
            --name "$storage_name" \
            --resource-group "$RESOURCE_GROUP" \
            --yes; then
            log_success "Storage account deleted: $storage_name"
        else
            log_error "Failed to delete storage account: $storage_name"
        fi
    else
        log_info "Storage account not found: $storage_name"
    fi
}

cleanup_sql_managed_instance() {
    local sql_mi_name="${SQL_MI_NAME:-sqlmi-${RANDOM_SUFFIX}}"
    
    log_info "Cleaning up SQL Managed Instance: $sql_mi_name"
    log_warning "SQL Managed Instance deletion will take 2-4 hours"
    
    if ! confirm_action "delete SQL Managed Instance" "$sql_mi_name"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete SQL Managed Instance: $sql_mi_name"
        return 0
    fi
    
    if az sql mi show --name "$sql_mi_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Deleting SQL Managed Instance (this will take 2-4 hours)..."
        
        if az sql mi delete \
            --name "$sql_mi_name" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --no-wait; then
            log_success "SQL Managed Instance deletion initiated: $sql_mi_name"
        else
            log_error "Failed to delete SQL Managed Instance: $sql_mi_name"
        fi
    else
        log_info "SQL Managed Instance not found: $sql_mi_name"
    fi
}

cleanup_network_resources() {
    local vnet_name="${VNET_NAME:-vnet-sqlmi}"
    local subnet_name="${SUBNET_NAME:-subnet-sqlmi}"
    
    log_info "Cleaning up network resources"
    
    if ! confirm_action "delete virtual network" "$vnet_name"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete virtual network: $vnet_name"
        return 0
    fi
    
    # Check if SQL MI deletion is still in progress
    local sql_mi_name="${SQL_MI_NAME:-sqlmi-${RANDOM_SUFFIX}}"
    if az sql mi show --name "$sql_mi_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "SQL Managed Instance still exists. Network resources will be cleaned up automatically."
        return 0
    fi
    
    # Delete virtual network (this will also delete the subnet)
    if az network vnet show --name "$vnet_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        if az network vnet delete \
            --name "$vnet_name" \
            --resource-group "$RESOURCE_GROUP"; then
            log_success "Virtual network deleted: $vnet_name"
        else
            log_error "Failed to delete virtual network: $vnet_name"
        fi
    else
        log_info "Virtual network not found: $vnet_name"
    fi
}

cleanup_personalizer() {
    local personalizer_name="${PERSONALIZER_NAME:-personalizer-${RANDOM_SUFFIX}}"
    
    log_info "Cleaning up Personalizer service: $personalizer_name"
    
    if ! confirm_action "delete Personalizer service" "$personalizer_name"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Personalizer service: $personalizer_name"
        return 0
    fi
    
    if az cognitiveservices account show --name "$personalizer_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        if az cognitiveservices account delete \
            --name "$personalizer_name" \
            --resource-group "$RESOURCE_GROUP"; then
            log_success "Personalizer service deleted: $personalizer_name"
        else
            log_error "Failed to delete Personalizer service: $personalizer_name"
        fi
    else
        log_info "Personalizer service not found: $personalizer_name"
    fi
}

cleanup_health_bot() {
    local health_bot_name="${HEALTH_BOT_NAME:-healthbot-${RANDOM_SUFFIX}}"
    
    log_info "Cleaning up Health Bot: $health_bot_name"
    
    if ! confirm_action "delete Health Bot" "$health_bot_name"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Health Bot: $health_bot_name"
        return 0
    fi
    
    if az healthbot show --name "$health_bot_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        if az healthbot delete \
            --name "$health_bot_name" \
            --resource-group "$RESOURCE_GROUP" \
            --yes; then
            log_success "Health Bot deleted: $health_bot_name"
        else
            log_error "Failed to delete Health Bot: $health_bot_name"
        fi
    else
        log_info "Health Bot not found: $health_bot_name"
    fi
}

cleanup_key_vault() {
    local keyvault_name="${KEYVAULT_NAME:-kv-${RANDOM_SUFFIX}}"
    
    log_info "Cleaning up Key Vault: $keyvault_name"
    
    if ! confirm_action "delete Key Vault" "$keyvault_name"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Key Vault: $keyvault_name"
        return 0
    fi
    
    if az keyvault show --name "$keyvault_name" &> /dev/null; then
        # Soft delete Key Vault
        if az keyvault delete \
            --name "$keyvault_name" \
            --resource-group "$RESOURCE_GROUP"; then
            log_success "Key Vault soft-deleted: $keyvault_name"
            
            # Purge Key Vault to completely remove it
            log_info "Purging Key Vault to complete deletion..."
            if az keyvault purge --name "$keyvault_name" --no-wait; then
                log_success "Key Vault purge initiated: $keyvault_name"
            else
                log_warning "Failed to purge Key Vault (may require manual cleanup): $keyvault_name"
            fi
        else
            log_error "Failed to delete Key Vault: $keyvault_name"
        fi
    else
        log_info "Key Vault not found: $keyvault_name"
    fi
}

cleanup_resource_group() {
    log_info "Cleaning up resource group: $RESOURCE_GROUP"
    
    if ! confirm_action "delete entire resource group" "$RESOURCE_GROUP"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Deleting entire resource group (this will remove ALL resources)..."
        
        if az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait; then
            log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        else
            log_error "Failed to delete resource group: $RESOURCE_GROUP"
        fi
    else
        log_info "Resource group not found: $RESOURCE_GROUP"
    fi
}

cleanup_configuration_files() {
    log_info "Cleaning up configuration files"
    
    if ! confirm_action "delete configuration files" "local files"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete configuration files"
        return 0
    fi
    
    local files_to_remove=(
        "${SCRIPT_DIR}/.env"
        "${SCRIPT_DIR}/scenario-config.json"
        "${SCRIPT_DIR}/create-schema.sql"
        "${SCRIPT_DIR}/PersonalizerIntegration.cs"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if rm "$file"; then
                log_success "Deleted configuration file: $(basename "$file")"
            else
                log_error "Failed to delete configuration file: $(basename "$file")"
            fi
        else
            log_info "Configuration file not found: $(basename "$file")"
        fi
    done
}

# ==============================================================================
# MAIN CLEANUP WORKFLOW
# ==============================================================================

print_banner() {
    echo "========================================================================"
    echo "  Azure Healthcare Chatbot Cleanup Script"
    echo "========================================================================"
    echo "  Recipe: Personalized Healthcare Chatbots"
    echo "  This script will PERMANENTLY DELETE all healthcare chatbot resources"
    echo "========================================================================"
    echo ""
}

print_warning() {
    echo -e "${RED}⚠️  WARNING: DESTRUCTIVE OPERATION ⚠️${NC}"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "  • Azure Health Bot instance"
    echo "  • Azure Personalizer service"
    echo "  • Azure SQL Managed Instance (including all databases)"
    echo "  • Azure Function App"
    echo "  • Azure API Management service"
    echo "  • Azure Key Vault (including all secrets)"
    echo "  • Azure Storage Account (including all data)"
    echo "  • Virtual Network and Subnet"
    echo "  • Resource Group (if --force-delete-rg is specified)"
    echo ""
    echo -e "${YELLOW}Long-running deletions:${NC}"
    echo "  • SQL Managed Instance: 2-4 hours"
    echo "  • API Management: 30-45 minutes"
    echo ""
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo ""
}

ask_deletion_preference() {
    if [[ "$CONFIRMATION_REQUIRED" == "false" ]]; then
        return 0
    fi
    
    echo "Choose cleanup option:"
    echo "1) Delete individual resources (recommended)"
    echo "2) Delete entire resource group (faster, but removes ALL resources)"
    echo "3) Cancel cleanup"
    echo ""
    read -p "Enter your choice (1-3): " -n 1 -r choice
    echo ""
    
    case $choice in
        1)
            return 0
            ;;
        2)
            cleanup_resource_group
            cleanup_configuration_files
            exit 0
            ;;
        3)
            log_info "Cleanup cancelled by user"
            exit 0
            ;;
        *)
            log_error "Invalid choice. Cleanup cancelled."
            exit 1
            ;;
    esac
}

print_cleanup_summary() {
    log_info "Cleanup Summary:"
    log_info "================"
    
    if [[ ${#CLEANUP_ERRORS[@]} -eq 0 ]]; then
        log_success "All cleanup operations completed successfully"
    else
        log_warning "Cleanup completed with ${#CLEANUP_ERRORS[@]} errors:"
        for error in "${CLEANUP_ERRORS[@]}"; do
            log_error "  - $error"
        done
    fi
    
    echo ""
    log_info "Notes:"
    log_info "• SQL Managed Instance deletion takes 2-4 hours"
    log_info "• API Management deletion takes 30-45 minutes"
    log_info "• Key Vault enters soft-delete state before permanent deletion"
    log_info "• Check Azure portal to confirm all resources are removed"
    echo ""
    log_info "Cleanup log saved to: $LOG_FILE"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                CONFIRMATION_REQUIRED=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                CONFIRMATION_REQUIRED=false
                shift
                ;;
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

main() {
    parse_arguments "$@"
    
    print_banner
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY RUN mode - no resources will be deleted"
        echo ""
    fi
    
    check_prerequisites
    
    # Load environment if resource group not specified
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        load_environment
    fi
    
    print_warning
    ask_deletion_preference
    
    # Execute cleanup in reverse order of creation
    cleanup_api_management
    cleanup_function_app
    cleanup_storage_account
    cleanup_sql_managed_instance
    cleanup_network_resources
    cleanup_personalizer
    cleanup_health_bot
    cleanup_key_vault
    cleanup_configuration_files
    
    print_cleanup_summary
}

# Run main function with all arguments
main "$@"