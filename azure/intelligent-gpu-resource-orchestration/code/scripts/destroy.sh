#!/bin/bash

#################################################################
# Azure GPU Orchestration Cleanup Script
# Recipe: Orchestrating Dynamic GPU Resource Allocation with 
#         Azure Container Apps and Azure Batch
# 
# This script safely removes all resources created by the
# deployment script to avoid ongoing charges.
#################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    # Try to load from saved file first
    if [ -f "/tmp/azure-gpu-deployment-info.env" ]; then
        log "Found deployment info file, loading..."
        source /tmp/azure-gpu-deployment-info.env
        log_success "Deployment information loaded from file"
    else
        log_warning "No deployment info file found, using environment variables or defaults"
        
        # Set default values if not provided
        export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-gpu-orchestration}"
        export LOCATION="${LOCATION:-westus3}"
        export RANDOM_SUFFIX="${RANDOM_SUFFIX:-}"
        
        if [ -z "$RANDOM_SUFFIX" ]; then
            log_error "RANDOM_SUFFIX not provided and no deployment info file found."
            log_error "Please provide the suffix used during deployment or the resource group name."
            log_error "Usage: RESOURCE_GROUP=your-rg-name ./destroy.sh"
            exit 1
        fi
        
        # Set resource names with suffix
        export ACA_ENVIRONMENT="aca-env-${RANDOM_SUFFIX}"
        export ACA_APP="ml-inference-app"
        export BATCH_ACCOUNT="batch${RANDOM_SUFFIX}"
        export BATCH_POOL="gpu-pool"
        export KEY_VAULT="kv-gpu-${RANDOM_SUFFIX}"
        export STORAGE_ACCOUNT="storage${RANDOM_SUFFIX}"
        export LOG_WORKSPACE="logs-gpu-${RANDOM_SUFFIX}"
        export FUNCTION_APP="router-func-${RANDOM_SUFFIX}"
    fi
    
    log "Resource Group: $RESOURCE_GROUP"
    log "Random Suffix: ${RANDOM_SUFFIX:-'not set'}"
}

# Function to confirm deletion
confirm_deletion() {
    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    log_warning "This script will DELETE ALL resources in resource group: $RESOURCE_GROUP"
    log_warning "This action is IRREVERSIBLE and will result in:"
    log_warning "- Complete loss of all data and configurations"
    log_warning "- Termination of all running workloads"
    log_warning "- Deletion of all monitoring and alert configurations"
    log_warning "- Purging of Key Vault (permanent deletion)"
    echo ""
    
    # Show estimated cost savings
    log "Estimated cost savings after cleanup:"
    log "- Container Apps GPU: ~\$0.526-3.06/hour (depending on GPU type)"
    log "- Batch GPU VMs: ~\$0.526/hour per low-priority node"
    log "- Storage and other services: ~\$5-20/month"
    echo ""
    
    if [ "${FORCE_DELETE:-false}" = "true" ]; then
        log_warning "FORCE_DELETE is set, skipping confirmation"
        return 0
    fi
    
    # Interactive confirmation
    echo -n "Type 'DELETE' to confirm deletion of all resources: "
    read -r confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    # Second confirmation for safety
    echo -n "Are you absolutely sure? Type 'YES' to proceed: "
    read -r final_confirmation
    
    if [ "$final_confirmation" != "YES" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "User confirmed deletion. Proceeding with cleanup..."
}

# Function to check resource group existence
check_resource_group() {
    log "Checking if resource group exists: $RESOURCE_GROUP"
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP does not exist"
        log "Nothing to clean up. Exiting."
        exit 0
    fi
    
    log_success "Resource group found: $RESOURCE_GROUP"
}

# Function to delete Container Apps resources
delete_container_apps() {
    log "=== Deleting Container Apps Resources ==="
    
    # Delete Container App
    if az containerapp show --name "$ACA_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting Container App: $ACA_APP..."
        az containerapp delete \
            --name "$ACA_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --yes > /dev/null 2>&1
        log_success "Container App deleted: $ACA_APP"
    else
        log_warning "Container App $ACA_APP not found, skipping"
    fi
    
    # Delete Container Apps environment
    if az containerapp env show --name "$ACA_ENVIRONMENT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting Container Apps environment: $ACA_ENVIRONMENT..."
        az containerapp env delete \
            --name "$ACA_ENVIRONMENT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes > /dev/null 2>&1
        log_success "Container Apps environment deleted: $ACA_ENVIRONMENT"
    else
        log_warning "Container Apps environment $ACA_ENVIRONMENT not found, skipping"
    fi
}

# Function to delete Azure Batch resources
delete_batch_resources() {
    log "=== Deleting Azure Batch Resources ==="
    
    # Set Batch account for subsequent commands (if it exists)
    if az batch account show --name "$BATCH_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az batch account set \
            --name "$BATCH_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" 2>/dev/null || true
        
        # Delete Batch pool first
        if az batch pool show --pool-id "$BATCH_POOL" &> /dev/null; then
            log "Deleting Batch pool: $BATCH_POOL..."
            az batch pool delete \
                --pool-id "$BATCH_POOL" \
                --yes > /dev/null 2>&1
            log_success "Batch pool deleted: $BATCH_POOL"
            
            # Wait for pool deletion to complete
            log "Waiting for pool deletion to complete..."
            local timeout=300  # 5 minutes
            local elapsed=0
            while az batch pool show --pool-id "$BATCH_POOL" &> /dev/null && [ $elapsed -lt $timeout ]; do
                sleep 10
                elapsed=$((elapsed + 10))
                echo -n "."
            done
            echo ""
            
            if [ $elapsed -ge $timeout ]; then
                log_warning "Pool deletion timed out, continuing with Batch account deletion"
            else
                log_success "Pool deletion completed"
            fi
        else
            log_warning "Batch pool $BATCH_POOL not found, skipping"
        fi
        
        # Delete Batch account
        log "Deleting Batch account: $BATCH_ACCOUNT..."
        az batch account delete \
            --name "$BATCH_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes > /dev/null 2>&1
        log_success "Batch account deleted: $BATCH_ACCOUNT"
    else
        log_warning "Batch account $BATCH_ACCOUNT not found, skipping"
    fi
}

# Function to delete Function App
delete_function_app() {
    log "=== Deleting Function App ==="
    
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting Function App: $FUNCTION_APP..."
        az functionapp delete \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" > /dev/null 2>&1
        log_success "Function App deleted: $FUNCTION_APP"
    else
        log_warning "Function App $FUNCTION_APP not found, skipping"
    fi
}

# Function to delete Storage Account
delete_storage_account() {
    log "=== Deleting Storage Account ==="
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting Storage Account: $STORAGE_ACCOUNT..."
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes > /dev/null 2>&1
        log_success "Storage Account deleted: $STORAGE_ACCOUNT"
    else
        log_warning "Storage Account $STORAGE_ACCOUNT not found, skipping"
    fi
}

# Function to delete Key Vault
delete_key_vault() {
    log "=== Deleting Key Vault ==="
    
    if az keyvault show --name "$KEY_VAULT" &> /dev/null; then
        log "Deleting Key Vault: $KEY_VAULT..."
        az keyvault delete \
            --name "$KEY_VAULT" \
            --resource-group "$RESOURCE_GROUP" > /dev/null 2>&1
        log_success "Key Vault soft-deleted: $KEY_VAULT"
        
        # Purge Key Vault to prevent name conflicts and ensure complete cleanup
        log "Purging Key Vault to prevent name conflicts..."
        if az keyvault purge --name "$KEY_VAULT" --no-wait > /dev/null 2>&1; then
            log_success "Key Vault purge initiated: $KEY_VAULT"
        else
            log_warning "Key Vault purge failed (may not have permissions or already purged)"
        fi
    else
        log_warning "Key Vault $KEY_VAULT not found, skipping"
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log "=== Deleting Monitoring Resources ==="
    
    # Delete metric alerts
    local alerts=("HighGPUUtilization" "HighBatchQueueDepth" "HighGPUCost")
    
    for alert in "${alerts[@]}"; do
        if az monitor metrics alert show --name "$alert" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log "Deleting alert rule: $alert..."
            az monitor metrics alert delete \
                --name "$alert" \
                --resource-group "$RESOURCE_GROUP" > /dev/null 2>&1
            log_success "Alert rule deleted: $alert"
        else
            log_warning "Alert rule $alert not found, skipping"
        fi
    done
    
    # Delete Log Analytics workspace
    if az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_WORKSPACE" &> /dev/null; then
        log "Deleting Log Analytics workspace: $LOG_WORKSPACE..."
        az monitor log-analytics workspace delete \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_WORKSPACE" \
            --force true > /dev/null 2>&1
        log_success "Log Analytics workspace deleted: $LOG_WORKSPACE"
    else
        log_warning "Log Analytics workspace $LOG_WORKSPACE not found, skipping"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "=== Deleting Resource Group ==="
    
    # Final safety check
    if [ "${SKIP_RG_DELETE:-false}" = "true" ]; then
        log_warning "SKIP_RG_DELETE is set, preserving resource group"
        return 0
    fi
    
    log "Deleting resource group: $RESOURCE_GROUP..."
    log_warning "This will delete ALL remaining resources in the group"
    
    # Delete resource group and all remaining resources
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait > /dev/null 2>&1
    
    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
    log "Note: Complete deletion may take several minutes to complete"
    
    # Optionally wait for deletion to complete
    if [ "${WAIT_FOR_COMPLETION:-false}" = "true" ]; then
        log "Waiting for resource group deletion to complete..."
        local timeout=1800  # 30 minutes
        local elapsed=0
        while az group exists --name "$RESOURCE_GROUP" && [ $elapsed -lt $timeout ]; do
            sleep 30
            elapsed=$((elapsed + 30))
            echo -n "."
        done
        echo ""
        
        if [ $elapsed -ge $timeout ]; then
            log_warning "Resource group deletion timed out (this is normal for large deletions)"
        else
            log_success "Resource group deletion completed"
        fi
    fi
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log "=== Cleaning up temporary files ==="
    
    # Remove deployment info file
    if [ -f "/tmp/azure-gpu-deployment-info.env" ]; then
        rm -f /tmp/azure-gpu-deployment-info.env
        log_success "Removed deployment info file"
    fi
    
    # Remove any other temporary files that might have been created
    rm -f /tmp/batch-pool-config.json 2>/dev/null || true
    
    log_success "Temporary file cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "=== Verifying Cleanup Completion ==="
    
    # Check if resource group still exists
    if az group exists --name "$RESOURCE_GROUP"; then
        log_warning "Resource group still exists (deletion may be in progress)"
        
        # List remaining resources
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" \
            --query "[].{Name:name, Type:type}" --output table 2>/dev/null || echo "Error listing resources")
        
        if [ "$remaining_resources" != "Error listing resources" ] && [ -n "$remaining_resources" ]; then
            log_warning "Remaining resources in $RESOURCE_GROUP:"
            echo "$remaining_resources"
        fi
    else
        log_success "Resource group has been completely removed"
    fi
    
    # Check Key Vault purge status
    if az keyvault list-deleted --query "[?name=='$KEY_VAULT']" --output tsv | grep -q "$KEY_VAULT"; then
        log_warning "Key Vault is in soft-deleted state. It will be automatically purged after the retention period."
    fi
    
    log_success "Cleanup verification completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "=== CLEANUP COMPLETED ==="
    echo ""
    log "Resources cleaned up:"
    log "├── Resource Group: $RESOURCE_GROUP (deletion initiated)"
    log "├── Container Apps Environment: $ACA_ENVIRONMENT"
    log "├── ML Inference App: $ACA_APP"
    log "├── Batch Account: $BATCH_ACCOUNT"
    log "├── GPU Pool: $BATCH_POOL"
    log "├── Key Vault: $KEY_VAULT (purged)"
    log "├── Storage Account: $STORAGE_ACCOUNT"
    log "├── Function App: $FUNCTION_APP"
    log "├── Log Analytics: $LOG_WORKSPACE"
    log "└── Monitoring Alerts: All deleted"
    echo ""
    
    log_success "Cost Impact:"
    log "✅ GPU compute charges stopped"
    log "✅ Storage charges stopped"
    log "✅ Function App charges stopped"
    log "✅ Monitoring charges stopped"
    echo ""
    
    log_warning "Important Notes:"
    log "- Resource group deletion may take 10-30 minutes to complete fully"
    log "- Key Vault is purged to prevent name conflicts in future deployments"
    log "- Billing charges should stop within a few minutes"
    log "- Check your Azure bill in 24-48 hours to verify charge cessation"
    echo ""
    
    log "Cleanup completed at: $(date)"
}

# Function to handle partial cleanup scenarios
handle_cleanup_errors() {
    local exit_code=$1
    
    if [ $exit_code -ne 0 ]; then
        log_error "Cleanup encountered errors. Some resources may not have been deleted."
        log_warning "Recommended actions:"
        log "1. Check Azure portal for remaining resources"
        log "2. Re-run this script with FORCE_DELETE=true"
        log "3. Manually delete remaining resources if needed"
        log "4. Contact Azure support if deletion issues persist"
        
        # List any remaining resources
        if az group exists --name "$RESOURCE_GROUP" 2>/dev/null; then
            log_warning "Resources still present in $RESOURCE_GROUP:"
            az resource list --resource-group "$RESOURCE_GROUP" \
                --query "[].{Name:name, Type:type}" --output table 2>/dev/null || true
        fi
    fi
    
    exit $exit_code
}

# Main cleanup function
main() {
    log "=== Starting Azure GPU Orchestration Cleanup ==="
    log "Timestamp: $(date)"
    
    # Set error handling
    trap 'handle_cleanup_errors $?' EXIT
    
    check_prerequisites
    load_deployment_info
    check_resource_group
    
    # Skip confirmation in non-interactive mode
    if [ -t 0 ]; then
        confirm_deletion
    else
        log_warning "Running in non-interactive mode, assuming confirmation"
    fi
    
    # Phase 1: Application Layer Cleanup
    log "=== Phase 1: Application Layer Cleanup ==="
    delete_container_apps
    delete_function_app
    
    # Phase 2: Compute Resources Cleanup
    log "=== Phase 2: Compute Resources Cleanup ==="
    delete_batch_resources
    
    # Phase 3: Storage and Security Cleanup
    log "=== Phase 3: Storage and Security Cleanup ==="
    delete_storage_account
    delete_key_vault
    
    # Phase 4: Monitoring Cleanup
    log "=== Phase 4: Monitoring Cleanup ==="
    delete_monitoring_resources
    
    # Phase 5: Infrastructure Cleanup
    log "=== Phase 5: Infrastructure Cleanup ==="
    delete_resource_group
    
    # Phase 6: Cleanup Verification
    log "=== Phase 6: Cleanup Verification ==="
    cleanup_temp_files
    verify_cleanup
    
    display_cleanup_summary
    
    # Reset error handling for successful completion
    trap - EXIT
    
    log_success "=== CLEANUP COMPLETED SUCCESSFULLY ==="
}

# Help function
show_help() {
    echo "Azure GPU Orchestration Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP      Resource group to delete (required if no deployment info file)"
    echo "  RANDOM_SUFFIX       Suffix used during deployment (required if no deployment info file)"
    echo "  FORCE_DELETE        Skip interactive confirmation (default: false)"
    echo "  SKIP_RG_DELETE      Keep resource group, only delete individual resources (default: false)"
    echo "  WAIT_FOR_COMPLETION Wait for resource group deletion to complete (default: false)"
    echo ""
    echo "Examples:"
    echo "  # Normal cleanup (interactive)"
    echo "  ./destroy.sh"
    echo ""
    echo "  # Force cleanup without confirmation"
    echo "  FORCE_DELETE=true ./destroy.sh"
    echo ""
    echo "  # Cleanup specific resource group"
    echo "  RESOURCE_GROUP=my-rg-name RANDOM_SUFFIX=abc123 ./destroy.sh"
    echo ""
    echo "  # Keep resource group, delete only resources"
    echo "  SKIP_RG_DELETE=true ./destroy.sh"
    echo ""
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac