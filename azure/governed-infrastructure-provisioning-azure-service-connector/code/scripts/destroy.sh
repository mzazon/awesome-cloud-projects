#!/bin/bash

# Azure Self-Service Infrastructure Provisioning - Cleanup Script
# This script removes all resources created by the deployment script
# in the proper order to handle dependencies

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Enable verbose logging for debugging
if [[ "${DEBUG:-false}" == "true" ]]; then
    set -x
fi

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# Function to prompt for confirmation
confirm_deletion() {
    if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
        echo ""
        log_warning "⚠️  WARNING: This will delete ALL resources in the following resource group:"
        echo "Resource Group: ${RESOURCE_GROUP:-rg-selfservice-infra}"
        echo ""
        echo "This action cannot be undone!"
        echo ""
        read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
        
        if [[ "$confirmation" != "yes" ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Function to discover resources from existing deployment
discover_resources() {
    log_info "Discovering deployed resources..."
    
    # Set resource group name (allow override via environment variable)
    export RESOURCE_GROUP="${RESOURCE_GROUP_NAME:-rg-selfservice-infra}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Resource group $RESOURCE_GROUP does not exist. Nothing to clean up."
        exit 0
    fi
    
    # Discover resources by listing them in the resource group
    log_info "Found resource group: $RESOURCE_GROUP"
    
    # Get DevCenter name if it exists
    export DEVCENTER_NAME=$(az devcenter admin devcenter list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Get Project name if it exists
    export PROJECT_NAME=$(az devcenter admin project list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Get Logic App names
    export LOGIC_APP_NAME=$(az logic workflow list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'approval')].name" --output tsv 2>/dev/null || echo "")
    export LIFECYCLE_LOGIC_APP=$(az logic workflow list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'lifecycle')].name" --output tsv 2>/dev/null || echo "")
    
    # Get SQL Server name
    export SQL_SERVER=$(az sql server list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")
    export SQL_DATABASE="webapp-db"
    
    # Get Key Vault name
    export KEY_VAULT_NAME=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Get Event Grid topic name
    export EVENT_GRID_TOPIC=$(az eventgrid topic list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Get Storage Account name
    export STORAGE_ACCOUNT=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    log_info "Resource discovery completed"
}

# Function to remove sample environments
remove_sample_environments() {
    if [[ -n "$PROJECT_NAME" && -n "$DEVCENTER_NAME" ]]; then
        log_info "Removing sample environments..."
        
        # List and delete all environments in the project
        local environments=$(az devcenter dev environment list \
            --project-name "$PROJECT_NAME" \
            --dev-center-name "$DEVCENTER_NAME" \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$environments" ]]; then
            while IFS= read -r env_name; do
                if [[ -n "$env_name" ]]; then
                    log_info "Deleting environment: $env_name"
                    az rest \
                        --method DELETE \
                        --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DevCenter/projects/${PROJECT_NAME}/users/me/environments/${env_name}" 2>/dev/null || log_warning "Failed to delete environment $env_name"
                fi
            done <<< "$environments"
            
            # Wait for environment deletions to complete
            log_info "Waiting for environment deletions to complete..."
            sleep 30
        fi
        
        log_success "Sample environments cleanup completed"
    else
        log_info "No DevCenter/Project found, skipping environment cleanup"
    fi
}

# Function to remove Event Grid subscriptions
remove_event_grid_subscriptions() {
    if [[ -n "$PROJECT_NAME" ]]; then
        log_info "Removing Event Grid subscriptions..."
        
        local subscription_name="deployment-approval-subscription"
        
        # Check if subscription exists and delete it
        if az eventgrid event-subscription show \
            --name "$subscription_name" \
            --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DevCenter/projects/${PROJECT_NAME}" >/dev/null 2>&1; then
            
            az eventgrid event-subscription delete \
                --name "$subscription_name" \
                --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DevCenter/projects/${PROJECT_NAME}" \
                --yes 2>/dev/null || log_warning "Failed to delete Event Grid subscription"
            
            log_success "Event Grid subscription deleted"
        else
            log_info "Event Grid subscription not found"
        fi
    fi
}

# Function to remove Logic Apps
remove_logic_apps() {
    log_info "Removing Logic Apps..."
    
    # Remove approval Logic App
    if [[ -n "$LOGIC_APP_NAME" ]]; then
        if az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            az logic workflow delete \
                --name "$LOGIC_APP_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes 2>/dev/null || log_warning "Failed to delete Logic App: $LOGIC_APP_NAME"
            
            log_success "Approval Logic App deleted: $LOGIC_APP_NAME"
        fi
    fi
    
    # Remove lifecycle Logic App
    if [[ -n "$LIFECYCLE_LOGIC_APP" ]]; then
        if az logic workflow show --name "$LIFECYCLE_LOGIC_APP" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            az logic workflow delete \
                --name "$LIFECYCLE_LOGIC_APP" \
                --resource-group "$RESOURCE_GROUP" \
                --yes 2>/dev/null || log_warning "Failed to delete Logic App: $LIFECYCLE_LOGIC_APP"
            
            log_success "Lifecycle Logic App deleted: $LIFECYCLE_LOGIC_APP"
        fi
    fi
}

# Function to remove Event Grid topic
remove_event_grid_topic() {
    if [[ -n "$EVENT_GRID_TOPIC" ]]; then
        log_info "Removing Event Grid topic: $EVENT_GRID_TOPIC..."
        
        if az eventgrid topic show --name "$EVENT_GRID_TOPIC" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            az eventgrid topic delete \
                --name "$EVENT_GRID_TOPIC" \
                --resource-group "$RESOURCE_GROUP" \
                --yes 2>/dev/null || log_warning "Failed to delete Event Grid topic"
            
            log_success "Event Grid topic deleted: $EVENT_GRID_TOPIC"
        else
            log_info "Event Grid topic not found"
        fi
    fi
}

# Function to remove Deployment Environments resources
remove_deployment_environments() {
    log_info "Removing Azure Deployment Environments resources..."
    
    # Remove Project first (this will also remove environment types)
    if [[ -n "$PROJECT_NAME" ]]; then
        if az devcenter admin project show --name "$PROJECT_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            az devcenter admin project delete \
                --name "$PROJECT_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes 2>/dev/null || log_warning "Failed to delete project: $PROJECT_NAME"
            
            log_success "Project deleted: $PROJECT_NAME"
        fi
    fi
    
    # Remove Catalog
    if [[ -n "$DEVCENTER_NAME" ]]; then
        # Get catalog name
        local catalog_name=$(az devcenter admin catalog list \
            --devcenter-name "$DEVCENTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query "[0].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$catalog_name" ]]; then
            az devcenter admin catalog delete \
                --name "$catalog_name" \
                --devcenter-name "$DEVCENTER_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes 2>/dev/null || log_warning "Failed to delete catalog: $catalog_name"
            
            log_success "Catalog deleted: $catalog_name"
        fi
        
        # Remove DevCenter
        if az devcenter admin devcenter show --name "$DEVCENTER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            az devcenter admin devcenter delete \
                --name "$DEVCENTER_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes 2>/dev/null || log_warning "Failed to delete DevCenter: $DEVCENTER_NAME"
            
            log_success "DevCenter deleted: $DEVCENTER_NAME"
        fi
    fi
}

# Function to remove SQL Database and Server
remove_sql_resources() {
    if [[ -n "$SQL_SERVER" ]]; then
        log_info "Removing SQL Database and Server..."
        
        # Delete database first
        if az sql db show --name "$SQL_DATABASE" --server "$SQL_SERVER" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            az sql db delete \
                --name "$SQL_DATABASE" \
                --server "$SQL_SERVER" \
                --resource-group "$RESOURCE_GROUP" \
                --yes 2>/dev/null || log_warning "Failed to delete SQL database: $SQL_DATABASE"
            
            log_success "SQL Database deleted: $SQL_DATABASE"
        fi
        
        # Delete server
        if az sql server show --name "$SQL_SERVER" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            az sql server delete \
                --name "$SQL_SERVER" \
                --resource-group "$RESOURCE_GROUP" \
                --yes 2>/dev/null || log_warning "Failed to delete SQL server: $SQL_SERVER"
            
            log_success "SQL Server deleted: $SQL_SERVER"
        fi
    fi
}

# Function to remove Key Vault
remove_key_vault() {
    if [[ -n "$KEY_VAULT_NAME" ]]; then
        log_info "Removing Key Vault: $KEY_VAULT_NAME..."
        
        if az keyvault show --name "$KEY_VAULT_NAME" >/dev/null 2>&1; then
            # Delete Key Vault (this will soft-delete it)
            az keyvault delete \
                --name "$KEY_VAULT_NAME" \
                --resource-group "$RESOURCE_GROUP" 2>/dev/null || log_warning "Failed to delete Key Vault: $KEY_VAULT_NAME"
            
            # Purge Key Vault permanently (optional, requires additional permissions)
            if [[ "${PURGE_KEY_VAULT:-false}" == "true" ]]; then
                log_info "Purging Key Vault permanently..."
                az keyvault purge \
                    --name "$KEY_VAULT_NAME" \
                    --location "$(az keyvault show-deleted --name "$KEY_VAULT_NAME" --query properties.location --output tsv 2>/dev/null)" 2>/dev/null || log_warning "Failed to purge Key Vault (may require additional permissions)"
            fi
            
            log_success "Key Vault deleted: $KEY_VAULT_NAME"
        else
            log_info "Key Vault not found"
        fi
    fi
}

# Function to remove Storage Account
remove_storage_account() {
    if [[ -n "$STORAGE_ACCOUNT" ]]; then
        log_info "Removing Storage Account: $STORAGE_ACCOUNT..."
        
        if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            az storage account delete \
                --name "$STORAGE_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --yes 2>/dev/null || log_warning "Failed to delete storage account: $STORAGE_ACCOUNT"
            
            log_success "Storage Account deleted: $STORAGE_ACCOUNT"
        else
            log_info "Storage Account not found"
        fi
    fi
}

# Function to remove any remaining web apps and service connections
remove_web_resources() {
    log_info "Checking for any remaining web apps and service connections..."
    
    # List and delete any web apps in the resource group
    local webapps=$(az webapp list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$webapps" ]]; then
        while IFS= read -r webapp_name; do
            if [[ -n "$webapp_name" ]]; then
                log_info "Deleting web app: $webapp_name"
                
                # Delete service connections first
                local connections=$(az webapp connection list \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$webapp_name" \
                    --query "[].name" --output tsv 2>/dev/null || echo "")
                
                if [[ -n "$connections" ]]; then
                    while IFS= read -r connection_name; do
                        if [[ -n "$connection_name" ]]; then
                            az webapp connection delete \
                                --resource-group "$RESOURCE_GROUP" \
                                --name "$webapp_name" \
                                --connection "$connection_name" \
                                --yes 2>/dev/null || log_warning "Failed to delete connection: $connection_name"
                        fi
                    done <<< "$connections"
                fi
                
                # Delete the web app
                az webapp delete \
                    --name "$webapp_name" \
                    --resource-group "$RESOURCE_GROUP" 2>/dev/null || log_warning "Failed to delete web app: $webapp_name"
            fi
        done <<< "$webapps"
        
        log_success "Web apps and service connections cleanup completed"
    fi
}

# Function to remove resource group
remove_resource_group() {
    log_info "Removing resource group: $RESOURCE_GROUP..."
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        # Option to delete entire resource group (faster but removes everything)
        if [[ "${DELETE_RESOURCE_GROUP:-true}" == "true" ]]; then
            log_info "Deleting entire resource group (this may take several minutes)..."
            az group delete \
                --name "$RESOURCE_GROUP" \
                --yes \
                --no-wait
            
            log_success "Resource group deletion initiated: $RESOURCE_GROUP"
            log_info "Note: Complete deletion may take several minutes and will continue in the background"
        else
            log_info "Skipping resource group deletion (DELETE_RESOURCE_GROUP=false)"
        fi
    else
        log_info "Resource group $RESOURCE_GROUP not found"
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    if [[ "${DELETE_RESOURCE_GROUP:-true}" != "true" ]]; then
        # Check remaining resources if we didn't delete the entire resource group
        local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining_resources" -gt 0 ]]; then
            log_warning "Some resources may still remain in the resource group:"
            az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output table 2>/dev/null || true
        else
            log_success "All resources have been successfully removed"
        fi
    fi
}

# Function to display cleanup summary
display_summary() {
    log_success "🎉 Cleanup completed!"
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo ""
    
    if [[ "${DELETE_RESOURCE_GROUP:-true}" == "true" ]]; then
        echo "✅ Resource group deletion initiated"
        echo "✅ All resources will be removed automatically"
        echo ""
        echo "Note: Complete resource group deletion may take several minutes"
        echo "You can check the status in the Azure portal or with:"
        echo "az group show --name $RESOURCE_GROUP"
    else
        echo "✅ Individual resources have been cleaned up"
        echo "✅ Resource group preserved"
        echo ""
        echo "To remove the resource group completely, run:"
        echo "az group delete --name $RESOURCE_GROUP --yes"
    fi
    echo ""
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    log_error "An error occurred during cleanup. Some resources may still exist."
    log_info "You can:"
    log_info "1. Re-run this script to attempt cleanup again"
    log_info "2. Manually delete resources through the Azure portal"
    log_info "3. Delete the entire resource group: az group delete --name $RESOURCE_GROUP --yes"
    exit 1
}

# Main cleanup function
main() {
    log_info "Starting Azure Self-Service Infrastructure cleanup..."
    echo "=== Azure Deployment Environments Cleanup ==="
    echo ""
    
    # Set up error handling
    trap handle_cleanup_error ERR
    
    # Execute cleanup steps
    validate_prerequisites
    discover_resources
    confirm_deletion
    
    # Remove resources in dependency order
    remove_sample_environments
    remove_event_grid_subscriptions
    remove_logic_apps
    remove_event_grid_topic
    remove_deployment_environments
    remove_web_resources
    remove_sql_resources
    remove_storage_account
    remove_key_vault
    remove_resource_group
    
    # Verify and display results
    verify_cleanup
    display_summary
}

# Print usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help                    Show this help message"
    echo "  --resource-group NAME     Specify resource group name (default: rg-selfservice-infra)"
    echo "  --force                   Skip confirmation prompts"
    echo "  --keep-resource-group     Don't delete the resource group, only individual resources"
    echo "  --purge-key-vault        Permanently purge Key Vault (requires additional permissions)"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP_NAME      Override default resource group name"
    echo "  FORCE_DELETE=true        Skip confirmation prompts"
    echo "  DELETE_RESOURCE_GROUP=false  Preserve the resource group"
    echo "  PURGE_KEY_VAULT=true     Permanently purge Key Vault"
    echo "  DEBUG=true               Enable verbose logging"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup with confirmation"
    echo "  $0 --force                           # Skip confirmation prompts"
    echo "  $0 --resource-group my-rg --force    # Cleanup specific resource group"
    echo "  $0 --keep-resource-group             # Keep resource group, remove resources"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            usage
            exit 0
            ;;
        --resource-group)
            export RESOURCE_GROUP_NAME="$2"
            shift 2
            ;;
        --force)
            export FORCE_DELETE="true"
            shift
            ;;
        --keep-resource-group)
            export DELETE_RESOURCE_GROUP="false"
            shift
            ;;
        --purge-key-vault)
            export PURGE_KEY_VAULT="true"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi