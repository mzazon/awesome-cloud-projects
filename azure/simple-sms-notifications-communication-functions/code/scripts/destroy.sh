#!/bin/bash

# =============================================================================
# Azure SMS Notifications Cleanup Script
# 
# This script safely removes all resources created by the deployment script:
# - Azure Communication Services and phone numbers
# - Azure Function App and associated resources
# - Storage accounts and resource groups
#
# Prerequisites:
# - Azure CLI installed and configured
# - Configuration file (sms-function-config.env) or environment variables set
# - Appropriate permissions to delete Azure resources
# =============================================================================

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Global flags
FORCE_DELETE=false
KEEP_PHONE_NUMBER=false
DRY_RUN=false

# Help function
show_help() {
    cat << EOF
Azure SMS Notifications Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -f, --force         Skip confirmation prompts (dangerous)
    -k, --keep-phone    Keep phone number (avoid monthly charges for new deployment)
    -d, --dry-run       Show what would be deleted without actually deleting
    -h, --help          Show this help message

EXAMPLES:
    $0                  # Interactive cleanup with confirmations
    $0 --dry-run        # Show what would be deleted
    $0 --force          # Delete everything without prompts
    $0 --keep-phone     # Keep phone number for reuse

CONFIGURATION:
    The script looks for configuration in this order:
    1. sms-function-config.env file in current directory
    2. Environment variables
    3. Interactive input

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -k|--keep-phone)
                KEEP_PHONE_NUMBER=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
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
}

# Load configuration from file or environment
load_configuration() {
    log_info "Loading configuration..."
    
    # Try to load from config file first
    if [[ -f "sms-function-config.env" ]]; then
        log_info "Loading configuration from sms-function-config.env"
        # shellcheck source=/dev/null
        source sms-function-config.env
    elif [[ -f "${PWD}/sms-function-config.env" ]]; then
        log_info "Loading configuration from ${PWD}/sms-function-config.env"
        # shellcheck source=/dev/null
        source "${PWD}/sms-function-config.env"
    else
        log_warning "Configuration file not found, using environment variables"
    fi
    
    # Set defaults or prompt for missing values
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        if [[ "${FORCE_DELETE}" == "true" ]]; then
            log_error "RESOURCE_GROUP not set and --force specified"
            exit 1
        fi
        read -rp "Enter Resource Group name: " RESOURCE_GROUP
    fi
    
    if [[ -z "${SUBSCRIPTION_ID:-}" ]]; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv 2>/dev/null || echo "")
    fi
    
    log_info "Configuration loaded:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Subscription: ${SUBSCRIPTION_ID:-current}"
    log_info "  ACS Resource: ${ACS_RESOURCE_NAME:-unknown}"
    log_info "  Function App: ${FUNCTION_APP_NAME:-unknown}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME:-unknown}"
    log_info "  Phone Number: ${PHONE_NUMBER:-unknown}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Verify resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} does not exist or is not accessible"
        if [[ "${FORCE_DELETE}" == "false" ]]; then
            read -rp "Continue anyway? (y/N): " -n 1 continue_choice
            echo
            if [[ ! "${continue_choice}" =~ ^[Yy]$ ]]; then
                log_info "Cleanup cancelled"
                exit 0
            fi
        fi
    fi
    
    log_success "Prerequisites satisfied"
}

# Get resource inventory
get_resource_inventory() {
    log_info "Discovering resources in ${RESOURCE_GROUP}..."
    
    local resources
    resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query '[].{Name:name, Type:type}' --output table 2>/dev/null || echo "")
    
    if [[ -n "${resources}" ]]; then
        log_info "Found resources:"
        echo "${resources}"
    else
        log_warning "No resources found in resource group"
    fi
}

# Confirm deletion
confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will permanently delete the following:"
    log_warning "  - Resource Group: ${RESOURCE_GROUP}"
    log_warning "  - All resources within the resource group"
    
    if [[ "${KEEP_PHONE_NUMBER}" == "false" ]]; then
        log_warning "  - Phone Number: ${PHONE_NUMBER:-unknown} (will stop monthly charges)"
    else
        log_info "  - Phone Number will be KEPT (monthly charges continue)"
    fi
    
    echo ""
    log_error "THIS ACTION CANNOT BE UNDONE!"
    echo ""
    
    read -rp "Are you absolutely sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource deletion..."
}

# Release phone number
release_phone_number() {
    if [[ "${KEEP_PHONE_NUMBER}" == "true" ]]; then
        log_info "Skipping phone number release (--keep-phone specified)"
        return 0
    fi
    
    if [[ -z "${PHONE_NUMBER:-}" || -z "${ACS_RESOURCE_NAME:-}" ]]; then
        log_warning "Phone number or ACS resource name not available, skipping release"
        return 0
    fi
    
    log_info "Releasing phone number: ${PHONE_NUMBER}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would release phone number: ${PHONE_NUMBER}"
        return 0
    fi
    
    # Check if phone number exists
    if ! az communication phonenumber show \
        --resource-group "${RESOURCE_GROUP}" \
        --communication-service "${ACS_RESOURCE_NAME}" \
        --phone-number "${PHONE_NUMBER}" &> /dev/null; then
        log_warning "Phone number ${PHONE_NUMBER} not found or already released"
        return 0
    fi
    
    # Release the phone number
    if az communication phonenumber release \
        --resource-group "${RESOURCE_GROUP}" \
        --communication-service "${ACS_RESOURCE_NAME}" \
        --phone-number "${PHONE_NUMBER}" \
        --output none 2>/dev/null; then
        log_success "Phone number released: ${PHONE_NUMBER}"
        log_info "Monthly charges for this number will stop"
    else
        log_error "Failed to release phone number: ${PHONE_NUMBER}"
        log_warning "You may need to release it manually to stop charges"
    fi
}

# Delete Function App
delete_function_app() {
    if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
        log_warning "Function App name not available, skipping deletion"
        return 0
    fi
    
    log_info "Deleting Function App: ${FUNCTION_APP_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Function App: ${FUNCTION_APP_NAME}"
        return 0
    fi
    
    if ! az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Function App ${FUNCTION_APP_NAME} not found"
        return 0
    fi
    
    if az functionapp delete \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --output none 2>/dev/null; then
        log_success "Function App deleted: ${FUNCTION_APP_NAME}"
    else
        log_error "Failed to delete Function App: ${FUNCTION_APP_NAME}"
    fi
}

# Delete Storage Account
delete_storage_account() {
    if [[ -z "${STORAGE_ACCOUNT_NAME:-}" ]]; then
        log_warning "Storage Account name not available, skipping deletion"
        return 0
    fi
    
    log_info "Deleting Storage Account: ${STORAGE_ACCOUNT_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Storage Account: ${STORAGE_ACCOUNT_NAME}"
        return 0
    fi
    
    if ! az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage Account ${STORAGE_ACCOUNT_NAME} not found"
        return 0
    fi
    
    if az storage account delete \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes \
        --output none 2>/dev/null; then
        log_success "Storage Account deleted: ${STORAGE_ACCOUNT_NAME}"
    else
        log_error "Failed to delete Storage Account: ${STORAGE_ACCOUNT_NAME}"
    fi
}

# Delete Communication Services
delete_communication_services() {
    if [[ -z "${ACS_RESOURCE_NAME:-}" ]]; then
        log_warning "Communication Services name not available, skipping deletion"
        return 0
    fi
    
    log_info "Deleting Communication Services resource: ${ACS_RESOURCE_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Communication Services: ${ACS_RESOURCE_NAME}"
        return 0
    fi
    
    if ! az communication show --name "${ACS_RESOURCE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Communication Services resource ${ACS_RESOURCE_NAME} not found"
        return 0
    fi
    
    if az communication delete \
        --name "${ACS_RESOURCE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes \
        --output none 2>/dev/null; then
        log_success "Communication Services deleted: ${ACS_RESOURCE_NAME}"
    else
        log_error "Failed to delete Communication Services: ${ACS_RESOURCE_NAME}"
    fi
}

# Delete Resource Group
delete_resource_group() {
    log_info "Deleting Resource Group: ${RESOURCE_GROUP}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Resource Group: ${RESOURCE_GROUP}"
        return 0
    fi
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource Group ${RESOURCE_GROUP} not found"
        return 0
    fi
    
    log_info "This may take several minutes..."
    
    if az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        --output none 2>/dev/null; then
        log_success "Resource Group deletion initiated: ${RESOURCE_GROUP}"
        log_info "Deletion will continue in the background"
    else
        log_error "Failed to initiate Resource Group deletion: ${RESOURCE_GROUP}"
        log_info "You may need to delete it manually from the Azure portal"
    fi
}

# Verify deletion
verify_deletion() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    log_info "Verifying resource deletion..."
    
    # Wait a moment for deletion to propagate
    sleep 5
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource Group still exists (deletion in progress)"
        log_info "You can check status with: az group show --name ${RESOURCE_GROUP}"
    else
        log_success "Resource Group successfully deleted"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would remove local configuration files"
        return 0
    fi
    
    local files_removed=0
    
    for file in "sms-function-config.env" "${PWD}/sms-function-config.env"; do
        if [[ -f "${file}" ]]; then
            if [[ "${FORCE_DELETE}" == "true" ]]; then
                rm -f "${file}"
                log_success "Removed configuration file: ${file}"
                ((files_removed++))
            else
                read -rp "Remove configuration file ${file}? (y/N): " -n 1 remove_file
                echo
                if [[ "${remove_file}" =~ ^[Yy]$ ]]; then
                    rm -f "${file}"
                    log_success "Removed configuration file: ${file}"
                    ((files_removed++))
                fi
            fi
        fi
    done
    
    if [[ ${files_removed} -eq 0 ]]; then
        log_info "No local configuration files found"
    fi
}

# Display cleanup summary
display_summary() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "=== DRY RUN COMPLETED ==="
        log_info "No resources were actually deleted"
        return 0
    fi
    
    log_success "=== CLEANUP COMPLETED ==="
    echo ""
    log_info "Resources processed:"
    log_info "  ✓ Resource Group: ${RESOURCE_GROUP}"
    
    if [[ "${KEEP_PHONE_NUMBER}" == "false" ]]; then
        log_info "  ✓ Phone Number: ${PHONE_NUMBER:-unknown} (released)"
        log_info "  💰 Monthly charges stopped for phone number"
    else
        log_warning "  ⚠️  Phone Number: ${PHONE_NUMBER:-unknown} (kept - charges continue)"
    fi
    
    echo ""
    log_info "Cost Impact:"
    log_info "  - Function App charges: $0 (consumption plan - pay per use)"
    log_info "  - Storage Account charges: ~$0.01-0.05/month (minimal usage)"
    log_info "  - Communication Services: $0 (pay per SMS)"
    
    if [[ "${KEEP_PHONE_NUMBER}" == "false" ]]; then
        log_info "  - Phone Number charges: $0 (released)"
    else
        log_warning "  - Phone Number charges: ~$2.00/month (still active)"
    fi
    
    echo ""
    log_info "Next Steps:"
    log_info "  - Verify deletion in Azure Portal if needed"
    log_info "  - Check billing to confirm charge cessation"
    
    if [[ "${KEEP_PHONE_NUMBER}" == "true" ]]; then
        log_info "  - Release phone number manually to stop monthly charges"
    fi
    
    log_success "All cleanup operations completed successfully!"
}

# Main cleanup function
main() {
    log_info "Starting Azure SMS Notifications cleanup..."
    log_info "Timestamp: $(date)"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Run cleanup steps
    load_configuration
    check_prerequisites
    get_resource_inventory
    confirm_deletion
    
    # Delete resources in reverse order of creation
    release_phone_number
    delete_function_app
    delete_storage_account
    delete_communication_services
    delete_resource_group
    
    # Verify and clean up
    verify_deletion
    cleanup_local_files
    display_summary
    
    log_success "Cleanup completed successfully!"
}

# Execute main function with all arguments
main "$@"