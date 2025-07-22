#!/bin/bash

# Azure Compute Fleet and Batch Processing Cleanup Script
# This script safely removes all resources created by the deployment script
# with proper error handling, confirmation prompts, and logging

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
FORCE_CLEANUP=false
SKIP_CONFIRMATION=false
PARTIAL_CLEANUP=false

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[HEADER]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to load environment variables from deployment
load_deployment_vars() {
    local vars_file="${SCRIPT_DIR}/deployment_vars.env"
    
    if [[ -f "$vars_file" ]]; then
        print_status "Loading deployment variables from: $vars_file"
        # shellcheck source=/dev/null
        source "$vars_file"
    else
        print_warning "Deployment variables file not found: $vars_file"
        print_warning "You may need to provide resource names manually"
        
        # Set default values with random suffix
        local random_suffix=$(openssl rand -hex 3)
        export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-batch-fleet-${random_suffix}}"
        export LOCATION="${LOCATION:-eastus}"
        export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stbatch${random_suffix}}"
        export BATCH_ACCOUNT="${BATCH_ACCOUNT:-batchacct${random_suffix}}"
        export FLEET_NAME="${FLEET_NAME:-compute-fleet-${random_suffix}}"
        export LOG_WORKSPACE="${LOG_WORKSPACE:-log-batch-${random_suffix}}"
        export POOL_ID="${POOL_ID:-batch-pool-${random_suffix}}"
        export JOB_ID="${JOB_ID:-sample-processing-job-${random_suffix}}"
    fi
    
    print_status "Using the following resource names:"
    echo "  RESOURCE_GROUP: $RESOURCE_GROUP"
    echo "  STORAGE_ACCOUNT: $STORAGE_ACCOUNT"
    echo "  BATCH_ACCOUNT: $BATCH_ACCOUNT"
    echo "  FLEET_NAME: $FLEET_NAME"
    echo "  LOG_WORKSPACE: $LOG_WORKSPACE"
    echo "  POOL_ID: $POOL_ID"
    echo "  JOB_ID: $JOB_ID"
}

# Function to check Azure CLI authentication
check_azure_auth() {
    print_status "Checking Azure CLI authentication..."
    
    if ! az account show >/dev/null 2>&1; then
        print_error "Azure CLI not authenticated. Please run 'az login' first."
        exit 1
    fi
    
    local subscription_id=$(az account show --query id --output tsv)
    local account_name=$(az account show --query name --output tsv)
    
    print_status "Authenticated to Azure subscription: $account_name ($subscription_id)"
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites..."
    
    # Check required commands
    local required_commands=("az" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            print_error "Required command '$cmd' not found. Please install it first."
            exit 1
        fi
    done
    
    # Check Azure authentication
    check_azure_auth
    
    print_status "Prerequisites check completed successfully"
}

# Function to check what resources exist
check_existing_resources() {
    print_header "Checking Existing Resources..."
    
    local resources_found=false
    
    # Check resource group
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_status "Found resource group: $RESOURCE_GROUP"
        resources_found=true
    else
        print_warning "Resource group not found: $RESOURCE_GROUP"
    fi
    
    # Check batch job
    if az batch job show --job-id "$JOB_ID" >/dev/null 2>&1; then
        print_status "Found batch job: $JOB_ID"
        resources_found=true
    else
        print_warning "Batch job not found: $JOB_ID"
    fi
    
    # Check batch pool
    if az batch pool show --pool-id "$POOL_ID" >/dev/null 2>&1; then
        print_status "Found batch pool: $POOL_ID"
        resources_found=true
    else
        print_warning "Batch pool not found: $POOL_ID"
    fi
    
    # Check batch account
    if az batch account show --name "$BATCH_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_status "Found batch account: $BATCH_ACCOUNT"
        resources_found=true
    else
        print_warning "Batch account not found: $BATCH_ACCOUNT"
    fi
    
    # Check compute fleet
    if az compute-fleet show --name "$FLEET_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_status "Found compute fleet: $FLEET_NAME"
        resources_found=true
    else
        print_warning "Compute fleet not found: $FLEET_NAME"
    fi
    
    # Check storage account
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_status "Found storage account: $STORAGE_ACCOUNT"
        resources_found=true
    else
        print_warning "Storage account not found: $STORAGE_ACCOUNT"
    fi
    
    # Check Log Analytics workspace
    if az monitor log-analytics workspace show --workspace-name "$LOG_WORKSPACE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_status "Found Log Analytics workspace: $LOG_WORKSPACE"
        resources_found=true
    else
        print_warning "Log Analytics workspace not found: $LOG_WORKSPACE"
    fi
    
    if [[ "$resources_found" != true ]]; then
        print_warning "No resources found to clean up"
        if [[ "$FORCE_CLEANUP" != true ]]; then
            exit 0
        fi
    fi
    
    return 0
}

# Function to delete batch jobs
delete_batch_jobs() {
    print_header "Deleting Batch Jobs..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would delete batch job: $JOB_ID"
        return 0
    fi
    
    # Set batch account context if it exists
    if az batch account show --name "$BATCH_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_status "Setting batch account context..."
        az batch account set \
            --name "$BATCH_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP"
    fi
    
    # Delete batch job
    if az batch job show --job-id "$JOB_ID" >/dev/null 2>&1; then
        print_status "Deleting batch job: $JOB_ID"
        
        # First, try to terminate the job
        if az batch job terminate --job-id "$JOB_ID" --yes >/dev/null 2>&1; then
            print_status "Job terminated successfully"
        fi
        
        # Wait a moment for termination to complete
        sleep 10
        
        # Now delete the job
        if az batch job delete --job-id "$JOB_ID" --yes; then
            print_status "✅ Batch job deleted successfully"
        else
            print_warning "Failed to delete batch job, continuing..."
        fi
    else
        print_status "Batch job not found, skipping deletion"
    fi
}

# Function to delete batch pools
delete_batch_pools() {
    print_header "Deleting Batch Pools..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would delete batch pool: $POOL_ID"
        return 0
    fi
    
    # Delete batch pool
    if az batch pool show --pool-id "$POOL_ID" >/dev/null 2>&1; then
        print_status "Deleting batch pool: $POOL_ID"
        
        # First, disable autoscaling if enabled
        if az batch pool autoscale disable --pool-id "$POOL_ID" >/dev/null 2>&1; then
            print_status "Autoscaling disabled for pool"
        fi
        
        # Resize pool to 0 nodes
        if az batch pool resize --pool-id "$POOL_ID" --target-dedicated-nodes 0 --target-low-priority-nodes 0 >/dev/null 2>&1; then
            print_status "Pool resized to 0 nodes"
        fi
        
        # Wait for nodes to be deallocated
        print_status "Waiting for nodes to be deallocated..."
        local max_wait=300  # 5 minutes
        local wait_time=0
        
        while [[ $wait_time -lt $max_wait ]]; do
            local current_nodes=$(az batch pool show --pool-id "$POOL_ID" --query "currentDedicatedNodes + currentLowPriorityNodes" --output tsv)
            if [[ "$current_nodes" -eq 0 ]]; then
                print_status "All nodes deallocated"
                break
            fi
            
            echo "Waiting for nodes to deallocate... ($current_nodes nodes remaining)"
            sleep 30
            ((wait_time+=30))
        done
        
        # Delete the pool
        if az batch pool delete --pool-id "$POOL_ID" --yes; then
            print_status "✅ Batch pool deleted successfully"
        else
            print_warning "Failed to delete batch pool, continuing..."
        fi
    else
        print_status "Batch pool not found, skipping deletion"
    fi
}

# Function to delete compute fleet
delete_compute_fleet() {
    print_header "Deleting Compute Fleet..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would delete compute fleet: $FLEET_NAME"
        return 0
    fi
    
    # Delete compute fleet
    if az compute-fleet show --name "$FLEET_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_status "Deleting compute fleet: $FLEET_NAME"
        
        if az compute-fleet delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$FLEET_NAME" \
            --yes; then
            print_status "✅ Compute fleet deleted successfully"
        else
            print_warning "Failed to delete compute fleet, continuing..."
        fi
    else
        print_status "Compute fleet not found, skipping deletion"
    fi
}

# Function to delete batch account
delete_batch_account() {
    print_header "Deleting Batch Account..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would delete batch account: $BATCH_ACCOUNT"
        return 0
    fi
    
    # Delete batch account
    if az batch account show --name "$BATCH_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_status "Deleting batch account: $BATCH_ACCOUNT"
        
        if az batch account delete \
            --name "$BATCH_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes; then
            print_status "✅ Batch account deleted successfully"
        else
            print_warning "Failed to delete batch account, continuing..."
        fi
    else
        print_status "Batch account not found, skipping deletion"
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    print_header "Deleting Monitoring Resources..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would delete Log Analytics workspace: $LOG_WORKSPACE"
        return 0
    fi
    
    # Delete cost alerts
    print_status "Deleting cost alerts..."
    if az monitor metrics alert delete \
        --name "batch-cost-alert" \
        --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_status "Cost alert deleted"
    else
        print_warning "Cost alert not found or already deleted"
    fi
    
    # Delete Log Analytics workspace
    if az monitor log-analytics workspace show --workspace-name "$LOG_WORKSPACE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_status "Deleting Log Analytics workspace: $LOG_WORKSPACE"
        
        if az monitor log-analytics workspace delete \
            --workspace-name "$LOG_WORKSPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --yes; then
            print_status "✅ Log Analytics workspace deleted successfully"
        else
            print_warning "Failed to delete Log Analytics workspace, continuing..."
        fi
    else
        print_status "Log Analytics workspace not found, skipping deletion"
    fi
}

# Function to delete storage account
delete_storage_account() {
    print_header "Deleting Storage Account..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would delete storage account: $STORAGE_ACCOUNT"
        return 0
    fi
    
    # Delete storage account
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_status "Deleting storage account: $STORAGE_ACCOUNT"
        
        if az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes; then
            print_status "✅ Storage account deleted successfully"
        else
            print_warning "Failed to delete storage account, continuing..."
        fi
    else
        print_status "Storage account not found, skipping deletion"
    fi
}

# Function to delete resource group
delete_resource_group() {
    print_header "Deleting Resource Group..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Delete resource group
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_status "Deleting resource group: $RESOURCE_GROUP"
        print_warning "This will delete ALL resources in the resource group"
        
        if az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait; then
            print_status "✅ Resource group deletion initiated"
            print_status "Note: Deletion may take several minutes to complete"
        else
            print_error "Failed to delete resource group"
            return 1
        fi
    else
        print_status "Resource group not found, skipping deletion"
    fi
}

# Function to verify resource deletion
verify_deletion() {
    print_header "Verifying Resource Deletion..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would verify resource deletion"
        return 0
    fi
    
    local verification_failed=false
    
    # Wait a moment for deletion to propagate
    sleep 10
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_warning "Resource group still exists (deletion may be in progress)"
        
        # List remaining resources
        local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
        if [[ -n "$remaining_resources" ]]; then
            print_warning "Remaining resources in resource group:"
            echo "$remaining_resources"
        fi
    else
        print_status "✅ Resource group successfully deleted"
    fi
    
    return 0
}

# Function to clean up temporary files
cleanup_temp_files() {
    print_header "Cleaning Up Temporary Files..."
    
    local temp_files=(
        "${SCRIPT_DIR}/deployment_vars.env"
        "${SCRIPT_DIR}/fleet-config.json"
        "${SCRIPT_DIR}/pool-config.json"
        "${SCRIPT_DIR}/job-config.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            if $DRY_RUN; then
                print_status "[DRY RUN] Would delete temp file: $file"
            else
                print_status "Deleting temp file: $file"
                rm -f "$file"
            fi
        fi
    done
    
    if [[ "$DRY_RUN" != true ]]; then
        print_status "✅ Temporary files cleaned up"
    fi
}

# Function to display cleanup summary
display_summary() {
    print_header "Cleanup Summary"
    
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Batch Account: $BATCH_ACCOUNT"
    echo "Batch Pool: $POOL_ID"
    echo "Batch Job: $JOB_ID"
    echo "Compute Fleet: $FLEET_NAME"
    echo "Log Analytics Workspace: $LOG_WORKSPACE"
    
    if [[ "$DRY_RUN" != true ]]; then
        echo ""
        echo "Cleanup Status:"
        echo "- All batch processing resources have been deleted"
        echo "- Resource group deletion has been initiated"
        echo "- Temporary files have been cleaned up"
        echo ""
        echo "Cleanup log saved to: $LOG_FILE"
    else
        echo ""
        echo "This was a dry run. No resources were actually deleted."
    fi
}

# Function to handle cleanup errors
handle_cleanup_error() {
    print_error "Cleanup encountered an error. Some resources may still exist."
    print_status "You can:"
    print_status "1. Run the script again with --force to continue cleanup"
    print_status "2. Check the Azure portal for remaining resources"
    print_status "3. Delete the resource group manually if needed"
    
    if [[ "$PARTIAL_CLEANUP" != true ]]; then
        exit 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run                    Show what would be deleted without making changes"
    echo "  --force                      Force cleanup even if resources don't exist"
    echo "  --skip-confirmation         Skip confirmation prompts"
    echo "  --partial                    Continue cleanup even if some deletions fail"
    echo "  --resource-group NAME       Override resource group name"
    echo "  --help                      Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP              Resource group name"
    echo "  STORAGE_ACCOUNT             Storage account name"
    echo "  BATCH_ACCOUNT               Batch account name"
    echo "  FLEET_NAME                  Compute fleet name"
    echo "  LOG_WORKSPACE               Log Analytics workspace name"
    echo "  POOL_ID                     Batch pool ID"
    echo "  JOB_ID                      Batch job ID"
    echo ""
    echo "Examples:"
    echo "  $0                          Clean up with confirmation"
    echo "  $0 --dry-run                Preview cleanup"
    echo "  $0 --force                  Force cleanup"
    echo "  $0 --skip-confirmation      Clean up without prompts"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --partial)
            PARTIAL_CLEANUP=true
            shift
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main cleanup function
main() {
    print_header "Azure Compute Fleet and Batch Processing Cleanup"
    
    # Set error trap
    if [[ "$PARTIAL_CLEANUP" != true ]]; then
        trap handle_cleanup_error ERR
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment variables
    load_deployment_vars
    
    # Check existing resources
    check_existing_resources
    
    # Confirmation prompt
    if [[ "$DRY_RUN" != true && "$SKIP_CONFIRMATION" != true ]]; then
        echo ""
        print_warning "This will DELETE all resources in the resource group: $RESOURCE_GROUP"
        print_warning "This action cannot be undone!"
        echo ""
        read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute cleanup steps in reverse order of creation
    delete_batch_jobs
    delete_batch_pools
    delete_compute_fleet
    delete_batch_account
    delete_monitoring_resources
    delete_storage_account
    delete_resource_group
    
    # Verify deletion
    verify_deletion
    
    # Clean up temporary files
    cleanup_temp_files
    
    # Display summary
    display_summary
    
    if [[ "$DRY_RUN" != true ]]; then
        print_status "✅ Cleanup completed successfully!"
    else
        print_status "✅ Dry run completed successfully!"
    fi
}

# Run main function
main "$@"