#!/bin/bash

# Secure User Onboarding Workflows with Azure Entra ID and Azure Service Bus - Destroy Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--dry-run] [--force] [--help]"
            echo "  --dry-run    Show what would be done without making changes"
            echo "  --force      Skip confirmation prompts"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

if [[ "$DRY_RUN" == "true" ]]; then
    info "Running in dry-run mode - no resources will be deleted"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would execute: $cmd"
        info "DRY-RUN: $description"
        return 0
    else
        info "$description"
        eval "$cmd"
        return $?
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Get current user info
    local current_user=$(az account show --query user.name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    
    info "Current user: $current_user"
    info "Subscription: $subscription_name ($subscription_id)"
    
    log "Prerequisites check completed"
}

# Function to load environment variables
load_environment_variables() {
    log "Loading environment variables..."
    
    # Check if .env file exists
    if [[ ! -f ".env" ]]; then
        error "Environment file .env not found. Please run this script from the same directory as deploy.sh"
    fi
    
    # Load environment variables from .env file
    export $(grep -v '^#' .env | xargs)
    
    # Verify required variables are set
    local required_vars=("RESOURCE_GROUP" "LOCATION" "SUBSCRIPTION_ID" "SERVICE_BUS_NAMESPACE" "KEY_VAULT_NAME" "LOGIC_APP_NAME" "STORAGE_ACCOUNT_NAME")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required environment variable $var is not set"
        fi
    done
    
    # Display loaded variables
    info "Loaded environment variables:"
    info "  RESOURCE_GROUP: $RESOURCE_GROUP"
    info "  LOCATION: $LOCATION"
    info "  SERVICE_BUS_NAMESPACE: $SERVICE_BUS_NAMESPACE"
    info "  KEY_VAULT_NAME: $KEY_VAULT_NAME"
    info "  LOGIC_APP_NAME: $LOGIC_APP_NAME"
    info "  STORAGE_ACCOUNT_NAME: $STORAGE_ACCOUNT_NAME"
    
    log "Environment variables loaded successfully"
}

# Function to prompt for confirmation
confirm_destruction() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log "Force delete enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    warn "This script will permanently delete the following resources:"
    warn "  - Resource Group: $RESOURCE_GROUP"
    warn "  - Key Vault: $KEY_VAULT_NAME (with 90-day soft delete)"
    warn "  - Service Bus: $SERVICE_BUS_NAMESPACE"
    warn "  - Logic Apps: $LOGIC_APP_NAME"
    warn "  - Storage Account: $STORAGE_ACCOUNT_NAME"
    warn "  - Azure AD Application Registration (if exists)"
    warn "  - Lifecycle Workflows (if exists)"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would prompt for confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed by user"
}

# Function to check if resources exist
check_resource_existence() {
    log "Checking resource existence..."
    
    # Check resource group
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        info "✓ Resource group exists: $RESOURCE_GROUP"
        RESOURCE_GROUP_EXISTS=true
    else
        info "✗ Resource group does not exist: $RESOURCE_GROUP"
        RESOURCE_GROUP_EXISTS=false
    fi
    
    # Check Key Vault
    if az keyvault show --name "$KEY_VAULT_NAME" &> /dev/null; then
        info "✓ Key Vault exists: $KEY_VAULT_NAME"
        KEY_VAULT_EXISTS=true
    else
        info "✗ Key Vault does not exist: $KEY_VAULT_NAME"
        KEY_VAULT_EXISTS=false
    fi
    
    # Check Service Bus
    if az servicebus namespace show --name "$SERVICE_BUS_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        info "✓ Service Bus exists: $SERVICE_BUS_NAMESPACE"
        SERVICE_BUS_EXISTS=true
    else
        info "✗ Service Bus does not exist: $SERVICE_BUS_NAMESPACE"
        SERVICE_BUS_EXISTS=false
    fi
    
    # Check Logic Apps
    if az logicapp show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        info "✓ Logic Apps exists: $LOGIC_APP_NAME"
        LOGIC_APP_EXISTS=true
    else
        info "✗ Logic Apps does not exist: $LOGIC_APP_NAME"
        LOGIC_APP_EXISTS=false
    fi
    
    # Check Storage Account
    if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        info "✓ Storage Account exists: $STORAGE_ACCOUNT_NAME"
        STORAGE_ACCOUNT_EXISTS=true
    else
        info "✗ Storage Account does not exist: $STORAGE_ACCOUNT_NAME"
        STORAGE_ACCOUNT_EXISTS=false
    fi
    
    # Check Application Registration
    if [[ -n "${APP_REGISTRATION:-}" ]]; then
        if az ad app show --id "$APP_REGISTRATION" &> /dev/null; then
            info "✓ Application Registration exists: $APP_REGISTRATION"
            APP_REGISTRATION_EXISTS=true
        else
            info "✗ Application Registration does not exist: $APP_REGISTRATION"
            APP_REGISTRATION_EXISTS=false
        fi
    else
        info "✗ Application Registration ID not found in environment"
        APP_REGISTRATION_EXISTS=false
    fi
    
    log "Resource existence check completed"
}

# Function to remove Application Registration
remove_app_registration() {
    if [[ "$APP_REGISTRATION_EXISTS" == "true" ]]; then
        log "Removing Azure AD Application Registration..."
        
        local cmd="az ad app delete --id ${APP_REGISTRATION}"
        execute_command "$cmd" "Deleting Application Registration: $APP_REGISTRATION"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            # Verify deletion
            if ! az ad app show --id "$APP_REGISTRATION" &> /dev/null; then
                log "✅ Application Registration removed successfully"
            else
                warn "Application Registration may still exist - check manually"
            fi
        fi
    else
        info "Application Registration does not exist or ID not found - skipping"
    fi
}

# Function to remove Lifecycle Workflows
remove_lifecycle_workflows() {
    log "Removing Lifecycle Workflows..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # List existing workflows
        local workflows=$(az rest --method GET --url "https://graph.microsoft.com/beta/identityGovernance/lifecycleWorkflows/workflows" --query "value[?displayName=='Automated User Onboarding'].id" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$workflows" ]]; then
            for workflow_id in $workflows; do
                info "Removing lifecycle workflow: $workflow_id"
                az rest --method DELETE --url "https://graph.microsoft.com/beta/identityGovernance/lifecycleWorkflows/workflows/$workflow_id" || warn "Failed to remove lifecycle workflow: $workflow_id"
            done
            log "✅ Lifecycle workflows removed"
        else
            info "No lifecycle workflows found to remove"
        fi
    else
        info "DRY-RUN: Would remove lifecycle workflows"
    fi
}

# Function to handle Key Vault soft delete
handle_key_vault_soft_delete() {
    if [[ "$KEY_VAULT_EXISTS" == "true" ]]; then
        log "Handling Key Vault soft delete..."
        
        if [[ "$DRY_RUN" == "false" ]]; then
            # First, delete the Key Vault
            info "Deleting Key Vault (will be soft-deleted): $KEY_VAULT_NAME"
            az keyvault delete --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" || warn "Failed to delete Key Vault"
            
            # Wait a moment for deletion to process
            sleep 10
            
            # Check if Key Vault is in soft-deleted state
            local soft_deleted=$(az keyvault list-deleted --query "[?name=='$KEY_VAULT_NAME'].name" --output tsv 2>/dev/null || echo "")
            
            if [[ -n "$soft_deleted" ]]; then
                info "Key Vault is soft-deleted. Purging permanently..."
                az keyvault purge --name "$KEY_VAULT_NAME" --location "$LOCATION" || warn "Failed to purge Key Vault - may need manual cleanup"
                
                # Wait for purge to complete
                sleep 30
                
                # Verify purge
                local still_soft_deleted=$(az keyvault list-deleted --query "[?name=='$KEY_VAULT_NAME'].name" --output tsv 2>/dev/null || echo "")
                if [[ -z "$still_soft_deleted" ]]; then
                    log "✅ Key Vault purged successfully"
                else
                    warn "Key Vault may still be in soft-deleted state - check manually"
                fi
            else
                log "✅ Key Vault deleted successfully"
            fi
        else
            info "DRY-RUN: Would delete and purge Key Vault"
        fi
    else
        info "Key Vault does not exist - skipping"
    fi
}

# Function to remove individual resources (for granular control)
remove_individual_resources() {
    log "Removing individual resources..."
    
    # Remove Logic Apps
    if [[ "$LOGIC_APP_EXISTS" == "true" ]]; then
        info "Removing Logic Apps..."
        local cmd="az logicapp delete --name ${LOGIC_APP_NAME} --resource-group ${RESOURCE_GROUP} --yes"
        execute_command "$cmd" "Deleting Logic Apps: $LOGIC_APP_NAME"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            sleep 10
            log "✅ Logic Apps removed"
        fi
    fi
    
    # Remove Storage Account
    if [[ "$STORAGE_ACCOUNT_EXISTS" == "true" ]]; then
        info "Removing Storage Account..."
        local cmd="az storage account delete --name ${STORAGE_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} --yes"
        execute_command "$cmd" "Deleting Storage Account: $STORAGE_ACCOUNT_NAME"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            sleep 10
            log "✅ Storage Account removed"
        fi
    fi
    
    # Remove Service Bus
    if [[ "$SERVICE_BUS_EXISTS" == "true" ]]; then
        info "Removing Service Bus..."
        local cmd="az servicebus namespace delete --name ${SERVICE_BUS_NAMESPACE} --resource-group ${RESOURCE_GROUP}"
        execute_command "$cmd" "Deleting Service Bus: $SERVICE_BUS_NAMESPACE"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            sleep 15
            log "✅ Service Bus removed"
        fi
    fi
}

# Function to remove resource group
remove_resource_group() {
    if [[ "$RESOURCE_GROUP_EXISTS" == "true" ]]; then
        log "Removing Resource Group..."
        
        local cmd="az group delete --name ${RESOURCE_GROUP} --yes --no-wait"
        execute_command "$cmd" "Deleting Resource Group: $RESOURCE_GROUP"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            info "Resource group deletion initiated (running in background)"
            info "You can check status with: az group show --name $RESOURCE_GROUP"
            log "✅ Resource group removal initiated"
        fi
    else
        info "Resource group does not exist - skipping"
    fi
}

# Function to wait for resource group deletion
wait_for_resource_group_deletion() {
    if [[ "$DRY_RUN" == "false" && "$RESOURCE_GROUP_EXISTS" == "true" ]]; then
        log "Waiting for resource group deletion to complete..."
        
        local max_attempts=60  # 10 minutes maximum
        local attempt=0
        
        while [[ $attempt -lt $max_attempts ]]; do
            if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
                log "✅ Resource group successfully deleted"
                return 0
            fi
            
            info "Resource group still exists... waiting (attempt $((attempt + 1))/$max_attempts)"
            sleep 10
            ((attempt++))
        done
        
        warn "Resource group deletion is taking longer than expected"
        warn "You can check the status manually: az group show --name $RESOURCE_GROUP"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(".env" "workflow-definition.json")
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "false" ]]; then
                rm -f "$file"
                info "Removed local file: $file"
            else
                info "DRY-RUN: Would remove local file: $file"
            fi
        fi
    done
    
    log "✅ Local files cleaned up"
}

# Function to display destruction summary
display_summary() {
    log "Destruction Summary"
    echo "=================================="
    echo "Resource Group: $RESOURCE_GROUP (${RESOURCE_GROUP_EXISTS:-false})"
    echo "Key Vault: $KEY_VAULT_NAME (${KEY_VAULT_EXISTS:-false})"
    echo "Service Bus: $SERVICE_BUS_NAMESPACE (${SERVICE_BUS_EXISTS:-false})"
    echo "Logic Apps: $LOGIC_APP_NAME (${LOGIC_APP_EXISTS:-false})"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME (${STORAGE_ACCOUNT_EXISTS:-false})"
    echo "App Registration: ${APP_REGISTRATION:-N/A} (${APP_REGISTRATION_EXISTS:-false})"
    echo "=================================="
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "Cleanup completed. Resources may take a few minutes to fully delete."
        echo "Key Vault has been purged (not just soft-deleted) to avoid naming conflicts."
        echo "You can verify deletion by checking the Azure portal or using Azure CLI commands."
    fi
}

# Main destruction function
main() {
    log "Starting Azure User Onboarding Automation cleanup..."
    
    # Execute cleanup steps
    check_prerequisites
    load_environment_variables
    confirm_destruction
    check_resource_existence
    
    # Remove resources in reverse order of creation
    remove_lifecycle_workflows
    remove_app_registration
    handle_key_vault_soft_delete
    remove_individual_resources
    remove_resource_group
    wait_for_resource_group_deletion
    cleanup_local_files
    display_summary
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "✅ Cleanup completed successfully!"
        log "All resources have been removed or marked for deletion"
    else
        log "✅ Dry-run completed successfully!"
    fi
}

# Trap to handle script interruption
trap 'error "Script interrupted. Some resources may not have been fully cleaned up. Please check manually."' INT TERM

# Execute main function
main "$@"