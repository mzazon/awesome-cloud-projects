#!/bin/bash

# =============================================================================
# Azure Playwright Testing and Application Insights Cleanup Script
# Recipe: Scalable Browser Testing Pipeline with Playwright Testing and Application Insights
# =============================================================================

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "${LOG_FILE}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "${LOG_FILE}"
}

# Default values
DRY_RUN=false
FORCE_DELETE=false
SKIP_CONFIRMATION=false
RESOURCE_GROUP=""

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup Azure Playwright Testing and Application Insights infrastructure.

OPTIONS:
    -g, --resource-group NAME    Resource group name to delete
    -d, --dry-run               Show what would be deleted without executing
    -f, --force                 Force deletion without prompting for each resource
    -y, --yes                   Skip all confirmation prompts (DANGEROUS)
    -h, --help                  Show this help message

EXAMPLES:
    $0                          # Interactive cleanup (prompts for resource group)
    $0 -g my-rg                 # Cleanup specific resource group
    $0 --dry-run                # Preview cleanup without executing
    $0 -g my-rg -f -y           # Force delete everything without prompts (DANGEROUS)

SAFETY NOTES:
    - This script will delete ALL resources in the specified resource group
    - Use --dry-run first to preview what will be deleted
    - Individual resource deletion is safer than --force mode
    - Always backup important data before running cleanup

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    USER_NAME=$(az account show --query user.name --output tsv)
    
    log "Current Azure subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
    log "Current user: ${USER_NAME}"
    
    log "Prerequisites check completed successfully"
}

# Function to load deployment environment
load_deployment_environment() {
    if [[ -f "${SCRIPT_DIR}/deployment.env" ]]; then
        log "Loading deployment environment from deployment.env"
        source "${SCRIPT_DIR}/deployment.env"
        
        # Use resource group from environment if not specified
        if [[ -z "${RESOURCE_GROUP}" ]]; then
            RESOURCE_GROUP="${RESOURCE_GROUP:-}"
        fi
        
        log "Found deployment environment:"
        log "  Resource Group: ${RESOURCE_GROUP:-'Not set'}"
        log "  Location: ${LOCATION:-'Not set'}"
        log "  Key Vault: ${KEYVAULT_NAME:-'Not set'}"
    else
        warn "No deployment.env file found. Manual resource group specification required."
    fi
}

# Function to prompt for resource group if not specified
prompt_for_resource_group() {
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        log "Available resource groups in your subscription:"
        az group list --query "[].name" --output table
        echo
        
        read -p "Enter the resource group name to delete: " RESOURCE_GROUP
        
        if [[ -z "${RESOURCE_GROUP}" ]]; then
            error "Resource group name is required"
            exit 1
        fi
    fi
    
    # Verify resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        error "Resource group '${RESOURCE_GROUP}' does not exist or you don't have access to it"
        exit 1
    fi
    
    log "Target resource group: ${RESOURCE_GROUP}"
}

# Function to list resources in the resource group
list_resources() {
    log "Discovering resources in resource group: ${RESOURCE_GROUP}"
    
    # Get all resources in the resource group
    RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null || echo "")
    
    if [[ -z "${RESOURCES}" ]] || [[ "${RESOURCES}" == *"[]"* ]]; then
        warn "No resources found in resource group: ${RESOURCE_GROUP}"
        return 1
    fi
    
    log "Found the following resources:"
    echo "${RESOURCES}"
    echo
    
    # Count resources
    RESOURCE_COUNT=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" --output tsv 2>/dev/null || echo "0")
    log "Total resources: ${RESOURCE_COUNT}"
    
    return 0
}

# Function to show cleanup plan
show_cleanup_plan() {
    log "Cleanup Plan:"
    echo "============================================"
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Deletion Method: ${FORCE_DELETE:+Force Delete Resource Group}${FORCE_DELETE:-Individual Resource Cleanup}"
    echo "Dry Run: ${DRY_RUN}"
    echo "============================================"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN MODE - No resources will be deleted"
        return 0
    fi
    
    if [[ "${SKIP_CONFIRMATION}" == "false" ]]; then
        warn "This will permanently delete all resources in the resource group!"
        warn "This action cannot be undone!"
        echo
        read -p "Are you absolutely sure you want to proceed? (type 'DELETE' to confirm): " CONFIRMATION
        
        if [[ "${CONFIRMATION}" != "DELETE" ]]; then
            info "Cleanup cancelled by user"
            exit 0
        fi
    fi
}

# Function to clean up Key Vault secrets (optional, for security)
cleanup_key_vault_secrets() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would clean up Key Vault secrets"
        return 0
    fi
    
    # Load Key Vault name from environment
    if [[ -f "${SCRIPT_DIR}/deployment.env" ]]; then
        source "${SCRIPT_DIR}/deployment.env"
    fi
    
    if [[ -z "${KEYVAULT_NAME:-}" ]]; then
        warn "Key Vault name not found in deployment environment"
        return 0
    fi
    
    log "Cleaning up Key Vault secrets: ${KEYVAULT_NAME}"
    
    # Check if Key Vault exists
    if ! az keyvault show --name "${KEYVAULT_NAME}" &> /dev/null; then
        warn "Key Vault ${KEYVAULT_NAME} not found or already deleted"
        return 0
    fi
    
    # List and delete secrets
    SECRET_NAMES=$(az keyvault secret list --vault-name "${KEYVAULT_NAME}" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${SECRET_NAMES}" ]]; then
        for SECRET_NAME in ${SECRET_NAMES}; do
            log "Deleting secret: ${SECRET_NAME}"
            az keyvault secret delete --vault-name "${KEYVAULT_NAME}" --name "${SECRET_NAME}" --output none 2>/dev/null || warn "Failed to delete secret: ${SECRET_NAME}"
        done
        
        log "✅ Key Vault secrets cleaned up"
    else
        log "No secrets found in Key Vault"
    fi
}

# Function to delete individual resources (safer approach)
delete_resources_individually() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete resources individually"
        return 0
    fi
    
    log "Deleting resources individually..."
    
    # Get all resource IDs
    RESOURCE_IDS=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].id" --output tsv 2>/dev/null || echo "")
    
    if [[ -z "${RESOURCE_IDS}" ]]; then
        warn "No resources found to delete"
        return 0
    fi
    
    # Delete each resource
    echo "${RESOURCE_IDS}" | while read -r RESOURCE_ID; do
        if [[ -n "${RESOURCE_ID}" ]]; then
            RESOURCE_NAME=$(az resource show --ids "${RESOURCE_ID}" --query "name" --output tsv 2>/dev/null || echo "unknown")
            RESOURCE_TYPE=$(az resource show --ids "${RESOURCE_ID}" --query "type" --output tsv 2>/dev/null || echo "unknown")
            
            log "Deleting ${RESOURCE_TYPE}: ${RESOURCE_NAME}"
            
            if az resource delete --ids "${RESOURCE_ID}" --output none 2>/dev/null; then
                log "✅ Deleted: ${RESOURCE_NAME}"
            else
                warn "Failed to delete: ${RESOURCE_NAME} (${RESOURCE_TYPE})"
            fi
        fi
    done
    
    log "Individual resource deletion completed"
}

# Function to delete resource group (nuclear option)
delete_resource_group() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete entire resource group: ${RESOURCE_GROUP}"
        return 0
    fi
    
    log "Deleting entire resource group: ${RESOURCE_GROUP}"
    
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        # Force delete without waiting
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait
        
        log "✅ Resource group deletion initiated (running in background)"
        log "Note: Complete deletion may take 5-15 minutes"
    else
        # Interactive delete with progress
        log "Starting resource group deletion (this may take several minutes)..."
        
        if az group delete --name "${RESOURCE_GROUP}" --yes; then
            log "✅ Resource group deleted successfully: ${RESOURCE_GROUP}"
        else
            error "Failed to delete resource group: ${RESOURCE_GROUP}"
            error "Some resources may still exist. Check the Azure Portal."
            return 1
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    log "Cleaning up local files..."
    
    # List files that would be deleted
    FILES_TO_DELETE=(
        "${SCRIPT_DIR}/deployment.env"
        "${SCRIPT_DIR}/deployment-summary.txt"
        "${SCRIPT_DIR}/setup-test-env.sh"
        "${SCRIPT_DIR}/../playwright-tests"
        "${LOG_FILE}"
    )
    
    for FILE_PATH in "${FILES_TO_DELETE[@]}"; do
        if [[ -e "${FILE_PATH}" ]]; then
            log "Removing: ${FILE_PATH}"
            rm -rf "${FILE_PATH}" 2>/dev/null || warn "Failed to remove: ${FILE_PATH}"
        fi
    done
    
    log "✅ Local files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would verify cleanup completion"
        return 0
    fi
    
    log "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        # If resource group exists, check if it has any resources
        REMAINING_RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" --output tsv 2>/dev/null || echo "0")
        
        if [[ "${REMAINING_RESOURCES}" -gt 0 ]]; then
            warn "Resource group still contains ${REMAINING_RESOURCES} resources"
            log "Remaining resources:"
            az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" --output table
            return 1
        else
            log "Resource group exists but is empty"
            
            if [[ "${FORCE_DELETE}" == "false" ]] && [[ "${SKIP_CONFIRMATION}" == "false" ]]; then
                read -p "Delete the empty resource group? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    az group delete --name "${RESOURCE_GROUP}" --yes --no-wait
                    log "Empty resource group deletion initiated"
                fi
            fi
        fi
    else
        log "✅ Resource group no longer exists: ${RESOURCE_GROUP}"
    fi
    
    log "Cleanup verification completed"
}

# Function to handle Playwright Testing workspace cleanup
handle_playwright_workspace_cleanup() {
    log "Azure Playwright Testing workspace cleanup reminder:"
    echo "============================================"
    echo "⚠️  MANUAL ACTION REQUIRED:"
    echo "Azure Playwright Testing workspaces must be deleted manually through the portal:"
    echo ""
    echo "1. Navigate to: https://aka.ms/mpt/portal"
    echo "2. Sign in with your Azure account"
    echo "3. Find your workspace (if any were created)"
    echo "4. Select the workspace and click 'Delete workspace'"
    echo "5. Confirm the deletion"
    echo ""
    echo "Note: If you didn't complete the manual workspace creation during deployment,"
    echo "      there may be no workspace to delete."
    echo "============================================"
}

# Main cleanup function
main() {
    log "Starting Azure Playwright Testing cleanup"
    log "Script version: 1.0.0"
    
    # Initialize log file
    echo "Cleanup started at $(date)" > "${LOG_FILE}"
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_environment
    prompt_for_resource_group
    
    # List resources and show cleanup plan
    if list_resources; then
        show_cleanup_plan
        
        if [[ "${DRY_RUN}" == "false" ]]; then
            # Clean up Key Vault secrets first (optional security step)
            cleanup_key_vault_secrets
            
            # Choose deletion method
            if [[ "${FORCE_DELETE}" == "true" ]]; then
                delete_resource_group
            else
                # Ask user preference
                if [[ "${SKIP_CONFIRMATION}" == "false" ]]; then
                    echo "Choose deletion method:"
                    echo "1. Delete individual resources (safer, slower)"
                    echo "2. Delete entire resource group (faster, nuclear option)"
                    read -p "Enter your choice (1 or 2): " -n 1 -r
                    echo
                    
                    if [[ $REPLY == "2" ]]; then
                        delete_resource_group
                    else
                        delete_resources_individually
                    fi
                else
                    delete_resources_individually
                fi
            fi
            
            # Verify cleanup
            sleep 5  # Wait a moment for deletions to process
            verify_cleanup
            
            # Clean up local files
            cleanup_local_files
            
            # Handle manual Playwright workspace cleanup
            handle_playwright_workspace_cleanup
            
            log "🎉 Cleanup completed!"
            log ""
            log "Summary:"
            log "- Azure resources have been deleted from resource group: ${RESOURCE_GROUP}"
            log "- Local deployment files have been cleaned up"
            log "- Please manually delete any Playwright Testing workspaces if created"
            log ""
            warn "Remember to check your Azure bill to ensure all resources are properly deleted"
        fi
    else
        log "No resources found in resource group. Checking if the resource group itself should be deleted..."
        
        if [[ "${DRY_RUN}" == "false" ]] && [[ "${SKIP_CONFIRMATION}" == "false" ]]; then
            read -p "Delete the empty resource group '${RESOURCE_GROUP}'? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                delete_resource_group
            fi
        fi
        
        cleanup_local_files
        log "Cleanup completed for empty resource group"
    fi
}

# Safety trap to prevent accidental execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Show safety warning for direct execution
    if [[ "${SKIP_CONFIRMATION}" == "false" ]] && [[ "${DRY_RUN}" == "false" ]]; then
        echo "============================================"
        echo "⚠️  DANGER: RESOURCE DELETION SCRIPT"
        echo "============================================"
        echo "This script will permanently delete Azure resources."
        echo "This action cannot be undone!"
        echo ""
        echo "Recommended: Run with --dry-run first to preview changes"
        echo "Example: $0 --dry-run"
        echo ""
        read -p "Do you understand the risks and want to continue? (type 'YES' to proceed): " SAFETY_CONFIRMATION
        
        if [[ "${SAFETY_CONFIRMATION}" != "YES" ]]; then
            echo "Safety check failed. Exiting."
            exit 0
        fi
    fi
    
    # Run main function
    main "$@"
fi