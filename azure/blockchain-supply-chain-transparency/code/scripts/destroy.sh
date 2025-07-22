#!/bin/bash

# Blockchain Supply Chain Transparency - Cleanup Script
# This script removes all Azure resources created by the deployment script
# Use with caution - this will permanently delete all resources!

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
CONFIG_FILE="deployment-config.json"
DRY_RUN="${DRY_RUN:-false}"
FORCE_DELETE="${FORCE_DELETE:-false}"

# Logging functions
log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Azure Blockchain Supply Chain Transparency resources.

OPTIONS:
    -c, --config FILE           Configuration file (default: deployment-config.json)
    -g, --resource-group NAME   Resource group name (overrides config file)
    -d, --dry-run               Show what would be deleted without actually deleting
    -f, --force                 Skip confirmation prompts
    -h, --help                  Show this help message

EXAMPLES:
    $0                          # Destroy using deployment-config.json
    $0 -c my-config.json       # Destroy using custom config file
    $0 -g my-resource-group    # Destroy specific resource group
    $0 --dry-run               # Preview what would be deleted
    $0 --force                 # Skip confirmation prompts

WARNING: This script will permanently delete all resources. Use with caution!
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -f|--force)
            FORCE_DELETE="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if logged in
    if ! az account show >/dev/null 2>&1; then
        error_exit "Not logged into Azure. Please run 'az login' first."
    fi
    
    # Check subscription
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    log_info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    
    log_success "Prerequisites validation completed"
}

# Load configuration
load_configuration() {
    log_info "Loading configuration..."
    
    # If resource group is provided via command line, use it
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_info "Using resource group from command line: $RESOURCE_GROUP"
        return
    fi
    
    # Try to load from config file
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from: $CONFIG_FILE"
        
        # Extract values from JSON config
        RESOURCE_GROUP=$(jq -r '.resourceGroup' "$CONFIG_FILE" 2>/dev/null || echo "")
        LOCATION=$(jq -r '.location' "$CONFIG_FILE" 2>/dev/null || echo "")
        RANDOM_SUFFIX=$(jq -r '.randomSuffix' "$CONFIG_FILE" 2>/dev/null || echo "")
        SKIP_APIM=$(jq -r '.skipApim' "$CONFIG_FILE" 2>/dev/null || echo "false")
        
        # Extract individual resource names
        LEDGER_NAME=$(jq -r '.resources.ledgerName' "$CONFIG_FILE" 2>/dev/null || echo "")
        COSMOS_ACCOUNT=$(jq -r '.resources.cosmosAccount' "$CONFIG_FILE" 2>/dev/null || echo "")
        STORAGE_ACCOUNT=$(jq -r '.resources.storageAccount' "$CONFIG_FILE" 2>/dev/null || echo "")
        KEYVAULT_NAME=$(jq -r '.resources.keyVaultName' "$CONFIG_FILE" 2>/dev/null || echo "")
        LOGIC_APP_NAME=$(jq -r '.resources.logicAppName' "$CONFIG_FILE" 2>/dev/null || echo "")
        EVENT_GRID_TOPIC=$(jq -r '.resources.eventGridTopic' "$CONFIG_FILE" 2>/dev/null || echo "")
        APIM_NAME=$(jq -r '.resources.apimName' "$CONFIG_FILE" 2>/dev/null || echo "")
        APPINSIGHTS_NAME=$(jq -r '.resources.appInsightsName' "$CONFIG_FILE" 2>/dev/null || echo "")
        WORKSPACE_NAME=$(jq -r '.resources.workspaceName' "$CONFIG_FILE" 2>/dev/null || echo "")
        IDENTITY_NAME=$(jq -r '.resources.identityName' "$CONFIG_FILE" 2>/dev/null || echo "")
        
        if [[ -z "$RESOURCE_GROUP" ]]; then
            error_exit "Could not load resource group from config file"
        fi
        
        log_info "Configuration loaded successfully"
        log_info "Resource Group: $RESOURCE_GROUP"
        log_info "Location: $LOCATION"
        log_info "Random Suffix: $RANDOM_SUFFIX"
    else
        error_exit "Configuration file not found: $CONFIG_FILE. Please specify resource group with -g option or ensure config file exists."
    fi
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return
    fi
    
    echo
    log_warning "⚠️  DANGER: This will permanently delete all resources in:"
    log_warning "   Resource Group: $RESOURCE_GROUP"
    log_warning "   Subscription: $SUBSCRIPTION_NAME"
    echo
    log_warning "The following resources will be deleted:"
    
    # List resources that will be deleted
    if [[ -n "${LEDGER_NAME:-}" ]]; then
        log_warning "   - Confidential Ledger: $LEDGER_NAME"
    fi
    if [[ -n "${COSMOS_ACCOUNT:-}" ]]; then
        log_warning "   - Cosmos DB: $COSMOS_ACCOUNT"
    fi
    if [[ -n "${KEYVAULT_NAME:-}" ]]; then
        log_warning "   - Key Vault: $KEYVAULT_NAME"
    fi
    if [[ -n "${LOGIC_APP_NAME:-}" ]]; then
        log_warning "   - Logic App: $LOGIC_APP_NAME"
    fi
    if [[ -n "${EVENT_GRID_TOPIC:-}" ]]; then
        log_warning "   - Event Grid: $EVENT_GRID_TOPIC"
    fi
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        log_warning "   - Storage Account: $STORAGE_ACCOUNT"
    fi
    if [[ -n "${APIM_NAME:-}" && "$SKIP_APIM" != "true" ]]; then
        log_warning "   - API Management: $APIM_NAME"
    fi
    if [[ -n "${APPINSIGHTS_NAME:-}" ]]; then
        log_warning "   - Application Insights: $APPINSIGHTS_NAME"
    fi
    if [[ -n "${WORKSPACE_NAME:-}" ]]; then
        log_warning "   - Log Analytics: $WORKSPACE_NAME"
    fi
    if [[ -n "${IDENTITY_NAME:-}" ]]; then
        log_warning "   - Managed Identity: $IDENTITY_NAME"
    fi
    
    echo
    log_warning "This action cannot be undone!"
    echo
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    echo
    
    if [[ $REPLY != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource deletion..."
}

# Delete API Management
delete_api_management() {
    if [[ -z "${APIM_NAME:-}" ]] || [[ "$SKIP_APIM" == "true" ]]; then
        log_info "Skipping API Management deletion"
        return
    fi
    
    log_info "Deleting API Management: $APIM_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete API Management: $APIM_NAME"
        return
    fi
    
    if az apim show --name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Deleting API Management (this may take several minutes)..."
        az apim delete \
            --name "$APIM_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --no-wait || log_warning "Failed to delete API Management"
        
        log_success "API Management deletion initiated"
    else
        log_info "API Management not found: $APIM_NAME"
    fi
}

# Delete Logic Apps
delete_logic_apps() {
    if [[ -z "${LOGIC_APP_NAME:-}" ]]; then
        log_info "Skipping Logic App deletion - name not found"
        return
    fi
    
    log_info "Deleting Logic App: $LOGIC_APP_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Logic App: $LOGIC_APP_NAME"
        return
    fi
    
    if az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        az logic workflow delete \
            --name "$LOGIC_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes || log_warning "Failed to delete Logic App"
        
        log_success "Logic App deleted: $LOGIC_APP_NAME"
    else
        log_info "Logic App not found: $LOGIC_APP_NAME"
    fi
}

# Delete Event Grid
delete_event_grid() {
    if [[ -z "${EVENT_GRID_TOPIC:-}" ]]; then
        log_info "Skipping Event Grid deletion - name not found"
        return
    fi
    
    log_info "Deleting Event Grid Topic: $EVENT_GRID_TOPIC"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Event Grid Topic: $EVENT_GRID_TOPIC"
        return
    fi
    
    if az eventgrid topic show --name "$EVENT_GRID_TOPIC" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        az eventgrid topic delete \
            --name "$EVENT_GRID_TOPIC" \
            --resource-group "$RESOURCE_GROUP" \
            --yes || log_warning "Failed to delete Event Grid Topic"
        
        log_success "Event Grid Topic deleted: $EVENT_GRID_TOPIC"
    else
        log_info "Event Grid Topic not found: $EVENT_GRID_TOPIC"
    fi
}

# Delete Cosmos DB
delete_cosmos_db() {
    if [[ -z "${COSMOS_ACCOUNT:-}" ]]; then
        log_info "Skipping Cosmos DB deletion - name not found"
        return
    fi
    
    log_info "Deleting Cosmos DB Account: $COSMOS_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cosmos DB Account: $COSMOS_ACCOUNT"
        return
    fi
    
    if az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        az cosmosdb delete \
            --name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes || log_warning "Failed to delete Cosmos DB Account"
        
        log_success "Cosmos DB Account deleted: $COSMOS_ACCOUNT"
    else
        log_info "Cosmos DB Account not found: $COSMOS_ACCOUNT"
    fi
}

# Delete Confidential Ledger
delete_confidential_ledger() {
    if [[ -z "${LEDGER_NAME:-}" ]]; then
        log_info "Skipping Confidential Ledger deletion - name not found"
        return
    fi
    
    log_info "Deleting Confidential Ledger: $LEDGER_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Confidential Ledger: $LEDGER_NAME"
        return
    fi
    
    if az confidentialledger show --name "$LEDGER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        az confidentialledger delete \
            --name "$LEDGER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes || log_warning "Failed to delete Confidential Ledger"
        
        log_success "Confidential Ledger deleted: $LEDGER_NAME"
    else
        log_info "Confidential Ledger not found: $LEDGER_NAME"
    fi
}

# Delete Storage Account
delete_storage_account() {
    if [[ -z "${STORAGE_ACCOUNT:-}" ]]; then
        log_info "Skipping Storage Account deletion - name not found"
        return
    fi
    
    log_info "Deleting Storage Account: $STORAGE_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Storage Account: $STORAGE_ACCOUNT"
        return
    fi
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes || log_warning "Failed to delete Storage Account"
        
        log_success "Storage Account deleted: $STORAGE_ACCOUNT"
    else
        log_info "Storage Account not found: $STORAGE_ACCOUNT"
    fi
}

# Delete Key Vault
delete_key_vault() {
    if [[ -z "${KEYVAULT_NAME:-}" ]]; then
        log_info "Skipping Key Vault deletion - name not found"
        return
    fi
    
    log_info "Deleting Key Vault: $KEYVAULT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Key Vault: $KEYVAULT_NAME"
        return
    fi
    
    if az keyvault show --name "$KEYVAULT_NAME" >/dev/null 2>&1; then
        # Delete Key Vault (soft-delete enabled by default)
        az keyvault delete \
            --name "$KEYVAULT_NAME" \
            --resource-group "$RESOURCE_GROUP" || log_warning "Failed to delete Key Vault"
        
        # Purge Key Vault to completely remove it
        log_info "Purging Key Vault to permanently delete..."
        az keyvault purge \
            --name "$KEYVAULT_NAME" \
            --location "$LOCATION" || log_warning "Failed to purge Key Vault"
        
        log_success "Key Vault deleted and purged: $KEYVAULT_NAME"
    else
        log_info "Key Vault not found: $KEYVAULT_NAME"
    fi
}

# Delete Managed Identity
delete_managed_identity() {
    if [[ -z "${IDENTITY_NAME:-}" ]]; then
        log_info "Skipping Managed Identity deletion - name not found"
        return
    fi
    
    log_info "Deleting Managed Identity: $IDENTITY_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Managed Identity: $IDENTITY_NAME"
        return
    fi
    
    if az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        az identity delete \
            --name "$IDENTITY_NAME" \
            --resource-group "$RESOURCE_GROUP" || log_warning "Failed to delete Managed Identity"
        
        log_success "Managed Identity deleted: $IDENTITY_NAME"
    else
        log_info "Managed Identity not found: $IDENTITY_NAME"
    fi
}

# Delete monitoring resources
delete_monitoring_resources() {
    log_info "Deleting monitoring resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete monitoring resources"
        return
    fi
    
    # Delete Application Insights
    if [[ -n "${APPINSIGHTS_NAME:-}" ]]; then
        if az monitor app-insights component show --app "$APPINSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            az monitor app-insights component delete \
                --app "$APPINSIGHTS_NAME" \
                --resource-group "$RESOURCE_GROUP" || log_warning "Failed to delete Application Insights"
            
            log_success "Application Insights deleted: $APPINSIGHTS_NAME"
        else
            log_info "Application Insights not found: $APPINSIGHTS_NAME"
        fi
    fi
    
    # Delete Log Analytics workspace
    if [[ -n "${WORKSPACE_NAME:-}" ]]; then
        if az monitor log-analytics workspace show --workspace-name "$WORKSPACE_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            az monitor log-analytics workspace delete \
                --workspace-name "$WORKSPACE_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes || log_warning "Failed to delete Log Analytics workspace"
            
            log_success "Log Analytics workspace deleted: $WORKSPACE_NAME"
        else
            log_info "Log Analytics workspace not found: $WORKSPACE_NAME"
        fi
    fi
}

# Delete Azure AD application
delete_azure_ad_app() {
    log_info "Searching for Azure AD applications to delete..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Azure AD applications"
        return
    fi
    
    # Find and delete Azure AD applications created by the deployment
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local app_name="SupplyChainLedgerApp${RANDOM_SUFFIX}"
        local app_id=$(az ad app list --display-name "$app_name" --query "[0].appId" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$app_id" && "$app_id" != "null" ]]; then
            log_info "Deleting Azure AD application: $app_name"
            
            # Delete service principal first
            az ad sp delete --id "$app_id" 2>/dev/null || log_warning "Failed to delete service principal"
            
            # Delete application
            az ad app delete --id "$app_id" || log_warning "Failed to delete Azure AD application"
            
            log_success "Azure AD application deleted: $app_name"
        else
            log_info "Azure AD application not found: $app_name"
        fi
    else
        log_info "Random suffix not found - cannot determine Azure AD application name"
    fi
}

# Delete entire resource group
delete_resource_group() {
    log_info "Deleting entire resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return
    fi
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Deleting resource group (this may take several minutes)..."
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait || error_exit "Failed to delete resource group"
        
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
    else
        log_info "Resource group not found: $RESOURCE_GROUP"
    fi
}

# Verify deletion
verify_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify deletion"
        return
    fi
    
    log_info "Verifying resource deletion..."
    
    # Wait a bit for deletion to process
    sleep 5
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Resource group still exists (deletion may be in progress)"
    else
        log_success "Resource group successfully deleted"
    fi
}

# Cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete local files"
        return
    fi
    
    # Remove configuration file
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
        log_success "Deleted configuration file: $CONFIG_FILE"
    fi
    
    # Remove any temporary files
    rm -f workflow-definition.json 2>/dev/null || true
    rm -f /tmp/workflow-definition.json 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

# Display summary
display_summary() {
    echo
    log_success "=== Cleanup Summary ==="
    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN - No resources were actually deleted"
    else
        log_info "Resource Group: $RESOURCE_GROUP"
        log_info "All resources in the resource group have been scheduled for deletion"
        log_info "Deletion may take several minutes to complete"
    fi
    echo
    log_warning "Note: Some resources may take additional time to be completely removed"
    log_warning "Check the Azure portal to verify all resources have been deleted"
}

# Main cleanup function
main() {
    log_info "Starting Azure Blockchain Supply Chain Transparency cleanup..."
    echo
    
    validate_prerequisites
    load_configuration
    
    if [[ "$DRY_RUN" != "true" ]]; then
        confirm_deletion
    fi
    
    # Delete resources in reverse order (most dependent first)
    delete_api_management
    delete_logic_apps
    delete_event_grid
    delete_cosmos_db
    delete_confidential_ledger
    delete_storage_account
    delete_key_vault
    delete_managed_identity
    delete_monitoring_resources
    delete_azure_ad_app
    
    # Finally, delete the entire resource group
    delete_resource_group
    
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_deletion
        cleanup_local_files
    fi
    
    display_summary
    
    log_success "Cleanup completed successfully!"
}

# Error handling
trap 'log_error "Cleanup failed at line $LINENO"' ERR

# Run main function
main "$@"