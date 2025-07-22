#!/bin/bash

# =============================================================================
# Azure Container Apps and Dapr Cleanup/Destroy Script
# =============================================================================
# This script safely removes all resources created for the distributed
# application patterns solution using Azure Container Apps with Dapr
# =============================================================================

set -euo pipefail

# Configuration and logging
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"
readonly MAX_RETRIES=3
readonly RETRY_DELAY=10

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration (can be overridden via environment variables)
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-dapr-microservices}"
LOCATION="${LOCATION:-eastus}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-aca-env-dapr}"
LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-dapr-microservices}"

# Control flags
FORCE_DELETE=false
SKIP_CONFIRMATION=false
DELETE_RESOURCE_GROUP=false
PRESERVE_STORAGE=false

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "Script failed at line $line_number with exit code $exit_code"
    log_error "Check $LOG_FILE for detailed error information"
    
    if [[ $exit_code -ne 0 ]]; then
        log_warning "Some resources may not have been deleted completely"
        log_warning "Please check the Azure Portal for any remaining resources"
    fi
    
    exit "$exit_code"
}

trap 'handle_error $? $LINENO' ERR

# Utility functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI v2.53.0 or later."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' does not exist"
        log_info "Nothing to clean up"
        exit 0
    fi
    
    log_success "Prerequisites check completed"
}

confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    log_warning "This will delete the following resources:"
    log_warning "  - Resource Group: $RESOURCE_GROUP"
    log_warning "  - All Container Apps and environment"
    log_warning "  - Service Bus namespace and all messages"
    log_warning "  - Cosmos DB account and all data"
    log_warning "  - Key Vault and all secrets"
    log_warning "  - Log Analytics workspace and all logs"
    log_warning "  - Application Insights data"
    echo
    log_error "THIS ACTION CANNOT BE UNDONE!"
    echo
    
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        log_warning "The entire resource group will be deleted!"
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Cleanup confirmed, proceeding..."
}

wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    local max_wait="${4:-300}" # Default 5 minutes
    local wait_interval=30
    local elapsed=0
    
    log_info "Waiting for $resource_type '$resource_name' deletion..."
    
    while [ $elapsed -lt $max_wait ]; do
        local exists=false
        
        case "$resource_type" in
            "cosmosdb")
                if az cosmosdb show --name "$resource_name" --resource-group "$resource_group" &> /dev/null; then
                    exists=true
                fi
                ;;
            "servicebus")
                if az servicebus namespace show --name "$resource_name" --resource-group "$resource_group" &> /dev/null; then
                    exists=true
                fi
                ;;
            "containerapp-env")
                if az containerapp env show --name "$resource_name" --resource-group "$resource_group" &> /dev/null; then
                    exists=true
                fi
                ;;
            "containerapp")
                if az containerapp show --name "$resource_name" --resource-group "$resource_group" &> /dev/null; then
                    exists=true
                fi
                ;;
            "keyvault")
                if az keyvault show --name "$resource_name" --resource-group "$resource_group" &> /dev/null; then
                    exists=true
                fi
                ;;
            *)
                log_warning "Unknown resource type: $resource_type"
                return 0
                ;;
        esac
        
        if [[ "$exists" == "false" ]]; then
            log_success "$resource_type '$resource_name' deleted successfully"
            return 0
        fi
        
        log_info "Still deleting... (${elapsed}s/${max_wait}s)"
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    log_warning "Timeout waiting for $resource_type '$resource_name' deletion"
    return 1
}

retry_command() {
    local command="$1"
    local description="$2"
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        log_info "Attempt $attempt/$MAX_RETRIES: $description"
        
        if eval "$command"; then
            log_success "$description completed successfully"
            return 0
        else
            log_warning "$description failed (attempt $attempt/$MAX_RETRIES)"
            if [ $attempt -lt $MAX_RETRIES ]; then
                log_info "Retrying in ${RETRY_DELAY}s..."
                sleep $RETRY_DELAY
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_warning "$description failed after $MAX_RETRIES attempts"
    return 1
}

# Discovery functions to find resources
discover_resources() {
    log_info "Discovering resources in resource group '$RESOURCE_GROUP'..."
    
    # Discover Container Apps
    export CONTAINER_APPS
    CONTAINER_APPS=$(az containerapp list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    # Discover Container App Environment
    export CONTAINER_ENV
    CONTAINER_ENV=$(az containerapp env list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Discover Service Bus namespaces
    export SERVICE_BUS_NAMESPACES
    SERVICE_BUS_NAMESPACES=$(az servicebus namespace list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    # Discover Cosmos DB accounts
    export COSMOS_ACCOUNTS
    COSMOS_ACCOUNTS=$(az cosmosdb list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    # Discover Key Vaults
    export KEY_VAULTS
    KEY_VAULTS=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    # Discover Log Analytics workspaces
    export LOG_WORKSPACES
    LOG_WORKSPACES=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    # Discover Application Insights
    export APP_INSIGHTS
    APP_INSIGHTS=$(az monitor app-insights component show --app insights-dapr-demo --resource-group "$RESOURCE_GROUP" --query name --output tsv 2>/dev/null || echo "")
    
    log_info "Resource discovery completed"
}

# Main cleanup functions
delete_container_apps() {
    if [[ -z "$CONTAINER_APPS" ]]; then
        log_info "No Container Apps found to delete"
        return 0
    fi
    
    log_info "Deleting Container Apps..."
    
    for app in $CONTAINER_APPS; do
        log_info "Deleting Container App: $app"
        
        if [[ "$FORCE_DELETE" == "true" ]]; then
            retry_command \
                "az containerapp delete --name '$app' --resource-group '$RESOURCE_GROUP' --yes" \
                "Force deleting Container App '$app'"
        else
            retry_command \
                "az containerapp delete --name '$app' --resource-group '$RESOURCE_GROUP' --yes" \
                "Deleting Container App '$app'"
        fi
        
        # Wait for deletion to complete
        wait_for_deletion "containerapp" "$app" "$RESOURCE_GROUP" 180
    done
    
    log_success "Container Apps deletion completed"
}

delete_container_apps_environment() {
    if [[ -z "$CONTAINER_ENV" ]]; then
        log_info "No Container Apps environment found to delete"
        return 0
    fi
    
    log_info "Deleting Container Apps environment: $CONTAINER_ENV"
    
    # Environment deletion also removes Dapr components
    retry_command \
        "az containerapp env delete --name '$CONTAINER_ENV' --resource-group '$RESOURCE_GROUP' --yes" \
        "Deleting Container Apps environment"
    
    wait_for_deletion "containerapp-env" "$CONTAINER_ENV" "$RESOURCE_GROUP" 300
    
    log_success "Container Apps environment deleted"
}

delete_service_bus() {
    if [[ -z "$SERVICE_BUS_NAMESPACES" ]]; then
        log_info "No Service Bus namespaces found to delete"
        return 0
    fi
    
    log_info "Deleting Service Bus namespaces..."
    
    for namespace in $SERVICE_BUS_NAMESPACES; do
        log_info "Deleting Service Bus namespace: $namespace"
        
        retry_command \
            "az servicebus namespace delete --name '$namespace' --resource-group '$RESOURCE_GROUP'" \
            "Deleting Service Bus namespace '$namespace'"
        
        wait_for_deletion "servicebus" "$namespace" "$RESOURCE_GROUP" 180
    done
    
    log_success "Service Bus namespaces deletion completed"
}

delete_cosmos_db() {
    if [[ -z "$COSMOS_ACCOUNTS" ]]; then
        log_info "No Cosmos DB accounts found to delete"
        return 0
    fi
    
    log_info "Deleting Cosmos DB accounts..."
    
    for account in $COSMOS_ACCOUNTS; do
        log_info "Deleting Cosmos DB account: $account"
        
        if [[ "$PRESERVE_STORAGE" == "true" ]]; then
            log_warning "Preserving Cosmos DB account '$account' (--preserve-storage flag set)"
            continue
        fi
        
        retry_command \
            "az cosmosdb delete --name '$account' --resource-group '$RESOURCE_GROUP' --yes" \
            "Deleting Cosmos DB account '$account'"
        
        wait_for_deletion "cosmosdb" "$account" "$RESOURCE_GROUP" 300
    done
    
    log_success "Cosmos DB accounts deletion completed"
}

delete_key_vaults() {
    if [[ -z "$KEY_VAULTS" ]]; then
        log_info "No Key Vaults found to delete"
        return 0
    fi
    
    log_info "Deleting Key Vaults..."
    
    for vault in $KEY_VAULTS; do
        log_info "Deleting Key Vault: $vault"
        
        # Key Vault deletion is soft delete by default
        retry_command \
            "az keyvault delete --name '$vault' --resource-group '$RESOURCE_GROUP'" \
            "Soft deleting Key Vault '$vault'"
        
        # Optionally purge the Key Vault completely
        if [[ "$FORCE_DELETE" == "true" ]]; then
            log_info "Purging Key Vault '$vault' permanently..."
            retry_command \
                "az keyvault purge --name '$vault'" \
                "Purging Key Vault '$vault'"
        else
            log_warning "Key Vault '$vault' is soft-deleted (can be recovered for 90 days)"
            log_info "To permanently delete: az keyvault purge --name '$vault'"
        fi
    done
    
    log_success "Key Vaults deletion completed"
}

delete_monitoring() {
    # Delete Application Insights
    if [[ -n "$APP_INSIGHTS" ]]; then
        log_info "Deleting Application Insights: $APP_INSIGHTS"
        
        retry_command \
            "az monitor app-insights component delete --app '$APP_INSIGHTS' --resource-group '$RESOURCE_GROUP'" \
            "Deleting Application Insights '$APP_INSIGHTS'"
    fi
    
    # Delete Log Analytics workspace
    if [[ -n "$LOG_WORKSPACES" ]]; then
        log_info "Deleting Log Analytics workspaces..."
        
        for workspace in $LOG_WORKSPACES; do
            log_info "Deleting Log Analytics workspace: $workspace"
            
            if [[ "$PRESERVE_STORAGE" == "true" ]]; then
                log_warning "Preserving Log Analytics workspace '$workspace' (--preserve-storage flag set)"
                continue
            fi
            
            retry_command \
                "az monitor log-analytics workspace delete --workspace-name '$workspace' --resource-group '$RESOURCE_GROUP' --yes" \
                "Deleting Log Analytics workspace '$workspace'"
        done
    fi
    
    log_success "Monitoring resources deletion completed"
}

delete_resource_group() {
    if [[ "$DELETE_RESOURCE_GROUP" != "true" ]]; then
        log_info "Skipping resource group deletion (use --delete-rg to delete)"
        return 0
    fi
    
    log_warning "Deleting entire resource group: $RESOURCE_GROUP"
    
    retry_command \
        "az group delete --name '$RESOURCE_GROUP' --yes --no-wait" \
        "Initiating resource group deletion"
    
    log_success "Resource group deletion initiated"
    log_info "Note: Complete deletion may take several minutes"
}

cleanup_local_files() {
    log_info "Cleaning up local temporary files..."
    
    # Remove any temporary component files that might exist
    rm -f pubsub-servicebus.yaml 2>/dev/null || true
    rm -f statestore-cosmosdb.yaml 2>/dev/null || true
    rm -f test-service-invocation.sh 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

validate_cleanup() {
    log_info "Validating cleanup..."
    
    local remaining_resources=0
    
    # Check for remaining Container Apps
    local remaining_apps
    remaining_apps=$(az containerapp list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
    if [[ "$remaining_apps" -gt 0 ]]; then
        log_warning "$remaining_apps Container App(s) still exist"
        remaining_resources=$((remaining_resources + remaining_apps))
    fi
    
    # Check for remaining Container App environments
    local remaining_envs
    remaining_envs=$(az containerapp env list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
    if [[ "$remaining_envs" -gt 0 ]]; then
        log_warning "$remaining_envs Container App environment(s) still exist"
        remaining_resources=$((remaining_resources + remaining_envs))
    fi
    
    # Check for remaining Service Bus namespaces
    local remaining_sb
    remaining_sb=$(az servicebus namespace list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
    if [[ "$remaining_sb" -gt 0 ]]; then
        log_warning "$remaining_sb Service Bus namespace(s) still exist"
        remaining_resources=$((remaining_resources + remaining_sb))
    fi
    
    # Check for remaining Cosmos DB accounts
    if [[ "$PRESERVE_STORAGE" != "true" ]]; then
        local remaining_cosmos
        remaining_cosmos=$(az cosmosdb list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
        if [[ "$remaining_cosmos" -gt 0 ]]; then
            log_warning "$remaining_cosmos Cosmos DB account(s) still exist"
            remaining_resources=$((remaining_resources + remaining_cosmos))
        fi
    fi
    
    if [[ "$remaining_resources" -eq 0 ]]; then
        log_success "All resources cleaned up successfully"
    else
        log_warning "$remaining_resources resource(s) may still exist"
        log_info "This is normal for some resources that take time to delete"
        log_info "Check the Azure Portal in a few minutes to verify complete deletion"
    fi
}

print_cleanup_summary() {
    log_success "=== CLEANUP SUMMARY ==="
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Cleanup completed at: $(date)"
    log_info ""
    log_info "Resources processed:"
    log_info "  - Container Apps: $(echo $CONTAINER_APPS | wc -w | tr -d ' ')"
    log_info "  - Container App Environment: $(if [[ -n "$CONTAINER_ENV" ]]; then echo "1"; else echo "0"; fi)"
    log_info "  - Service Bus Namespaces: $(echo $SERVICE_BUS_NAMESPACES | wc -w | tr -d ' ')"
    log_info "  - Cosmos DB Accounts: $(echo $COSMOS_ACCOUNTS | wc -w | tr -d ' ')"
    log_info "  - Key Vaults: $(echo $KEY_VAULTS | wc -w | tr -d ' ')"
    log_info "  - Log Analytics Workspaces: $(echo $LOG_WORKSPACES | wc -w | tr -d ' ')"
    
    if [[ "$PRESERVE_STORAGE" == "true" ]]; then
        log_info ""
        log_warning "Storage resources were preserved:"
        log_warning "  - Cosmos DB data retained"
        log_warning "  - Log Analytics data retained"
    fi
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_info ""
        log_warning "Force delete was used:"
        log_warning "  - Key Vaults were permanently purged"
    else
        log_info ""
        log_info "Soft-deleted resources (recoverable):"
        log_info "  - Key Vaults (90-day recovery period)"
    fi
    
    log_info ""
    log_info "Log file saved: $LOG_FILE"
    log_success "========================="
}

# Main cleanup function
main() {
    log_info "Starting Azure Container Apps and Dapr cleanup..."
    log_info "Script: $SCRIPT_NAME"
    log_info "Log file: $LOG_FILE"
    log_info "Timestamp: $(date)"
    
    check_prerequisites
    confirm_deletion
    discover_resources
    delete_container_apps
    delete_container_apps_environment
    delete_service_bus
    delete_cosmos_db
    delete_key_vaults
    delete_monitoring
    cleanup_local_files
    delete_resource_group
    validate_cleanup
    print_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Help function
show_help() {
    cat << EOF
Azure Container Apps and Dapr Cleanup Script

USAGE:
    $SCRIPT_NAME [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -g, --resource-group    Resource group name (default: rg-dapr-microservices)
    -f, --force             Force delete resources without confirmation
    -y, --yes               Skip confirmation prompts
    --delete-rg             Delete the entire resource group
    --preserve-storage      Preserve storage resources (Cosmos DB, Log Analytics)
    --force-delete          Permanently purge soft-deleted resources

ENVIRONMENT VARIABLES:
    RESOURCE_GROUP          Resource group name
    LOCATION               Azure region
    ENVIRONMENT_NAME       Container Apps environment name
    LOG_ANALYTICS_WORKSPACE Log Analytics workspace name

EXAMPLES:
    # Interactive cleanup (with confirmation)
    $SCRIPT_NAME

    # Cleanup specific resource group
    $SCRIPT_NAME -g my-rg

    # Force cleanup without confirmation
    $SCRIPT_NAME -f -y

    # Delete entire resource group
    $SCRIPT_NAME --delete-rg -y

    # Preserve storage data
    $SCRIPT_NAME --preserve-storage

    # Complete cleanup with permanent deletion
    $SCRIPT_NAME --force-delete --delete-rg -y

SAFETY FEATURES:
    - Confirmation required by default
    - Soft delete for Key Vaults (90-day recovery)
    - Option to preserve storage resources
    - Detailed logging of all operations
    - Validation of cleanup completion

For more information, see the recipe documentation.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --delete-rg)
            DELETE_RESOURCE_GROUP=true
            shift
            ;;
        --preserve-storage)
            PRESERVE_STORAGE=true
            shift
            ;;
        --force-delete)
            FORCE_DELETE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main "$@"