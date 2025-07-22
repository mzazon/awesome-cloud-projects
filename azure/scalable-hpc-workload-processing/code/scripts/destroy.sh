#!/bin/bash

# Azure Scalable HPC Workload Processing - Cleanup Script
# This script removes all Azure resources created by the deployment script
# for the HPC workload processing solution

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be deleted"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $cmd"
        echo "[DRY-RUN] Description: $description"
        return 0
    fi
    
    log "$description"
    if eval "$cmd"; then
        success "$description completed"
        return 0
    else
        if [[ "$ignore_errors" == "true" ]]; then
            warning "$description failed (ignored)"
            return 0
        else
            error "$description failed"
            return 1
        fi
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
    fi
    
    success "Prerequisites check completed"
}

# Function to load environment variables
load_environment_variables() {
    log "Loading environment variables..."
    
    # Try to load from .env file first
    if [[ -f ".env" ]]; then
        log "Loading environment variables from .env file..."
        source .env
        success "Environment variables loaded from .env file"
    else
        warning ".env file not found. Please provide resource names manually or ensure deploy.sh was run successfully."
        
        # Prompt for required variables if not found
        if [[ -z "${RESOURCE_GROUP:-}" ]]; then
            read -p "Enter Resource Group name: " RESOURCE_GROUP
        fi
        
        if [[ -z "${LOCATION:-}" ]]; then
            read -p "Enter Location (e.g., eastus): " LOCATION
        fi
        
        if [[ -z "${SUBSCRIPTION_ID:-}" ]]; then
            SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        fi
        
        # Set default values for other variables if not provided
        ESAN_NAME="${ESAN_NAME:-esan-hpc}"
        BATCH_ACCOUNT="${BATCH_ACCOUNT:-batch-hpc}"
        STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-sthpc}"
        VNET_NAME="${VNET_NAME:-vnet-hpc}"
        SUBNET_NAME="${SUBNET_NAME:-subnet-batch}"
        NSG_NAME="${NSG_NAME:-nsg-hpc}"
        WORKSPACE_NAME="${WORKSPACE_NAME:-law-hpc}"
    fi
    
    log "Environment variables configured:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Location: ${LOCATION}"
    log "  Subscription ID: ${SUBSCRIPTION_ID}"
    
    success "Environment variables loaded"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warning "This will permanently delete the following resources:"
    echo "  - Resource Group: ${RESOURCE_GROUP}"
    echo "  - All contained resources (Elastic SAN, Batch, Storage, Network, etc.)"
    echo ""
    warning "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    success "Deletion confirmed"
}

# Function to stop and delete Batch resources
cleanup_batch_resources() {
    log "Cleaning up Azure Batch resources..."
    
    # Check if Batch account exists
    if az batch account show --resource-group ${RESOURCE_GROUP} --name ${BATCH_ACCOUNT} &> /dev/null; then
        
        # Login to Batch account
        execute_command \
            "az batch account login --resource-group ${RESOURCE_GROUP} --name ${BATCH_ACCOUNT}" \
            "Logging in to Batch account" \
            "true"
        
        # Delete running jobs
        JOBS=$(az batch job list --query "[].id" --output tsv 2>/dev/null || echo "")
        if [[ -n "$JOBS" ]]; then
            for job in $JOBS; do
                execute_command \
                    "az batch job delete --job-id $job --yes" \
                    "Deleting Batch job: $job" \
                    "true"
            done
        fi
        
        # Delete pools
        POOLS=$(az batch pool list --query "[].id" --output tsv 2>/dev/null || echo "")
        if [[ -n "$POOLS" ]]; then
            for pool in $POOLS; do
                execute_command \
                    "az batch pool delete --pool-id $pool --yes" \
                    "Deleting Batch pool: $pool" \
                    "true"
            done
        fi
        
        # Wait for pools to be deleted
        log "Waiting for pools to be fully deleted..."
        while true; do
            ACTIVE_POOLS=$(az batch pool list --query "length([?state=='active'])" --output tsv 2>/dev/null || echo "0")
            if [[ "$ACTIVE_POOLS" == "0" ]]; then
                break
            fi
            log "Waiting for $ACTIVE_POOLS pools to be deleted..."
            sleep 30
        done
        
        success "Batch resources cleaned up"
    else
        warning "Batch account not found, skipping Batch cleanup"
    fi
}

# Function to delete Elastic SAN volumes and storage
cleanup_elastic_san() {
    log "Cleaning up Azure Elastic SAN..."
    
    # Check if Elastic SAN exists
    if az elastic-san show --resource-group ${RESOURCE_GROUP} --name ${ESAN_NAME} &> /dev/null; then
        
        # Delete volumes
        VOLUMES=("data-input" "results-output" "shared-libraries")
        for volume in "${VOLUMES[@]}"; do
            execute_command \
                "az elastic-san volume delete --resource-group ${RESOURCE_GROUP} --elastic-san-name ${ESAN_NAME} --volume-group-name hpc-volumes --name $volume --yes" \
                "Deleting Elastic SAN volume: $volume" \
                "true"
        done
        
        # Delete volume group
        execute_command \
            "az elastic-san volume-group delete --resource-group ${RESOURCE_GROUP} --elastic-san-name ${ESAN_NAME} --name hpc-volumes --yes" \
            "Deleting Elastic SAN volume group" \
            "true"
        
        # Delete Elastic SAN
        execute_command \
            "az elastic-san delete --resource-group ${RESOURCE_GROUP} --name ${ESAN_NAME} --yes" \
            "Deleting Elastic SAN" \
            "true"
        
        success "Elastic SAN cleaned up"
    else
        warning "Elastic SAN not found, skipping Elastic SAN cleanup"
    fi
}

# Function to delete monitoring resources
cleanup_monitoring() {
    log "Cleaning up monitoring resources..."
    
    # Delete Log Analytics workspace
    execute_command \
        "az monitor log-analytics workspace delete --resource-group ${RESOURCE_GROUP} --workspace-name ${WORKSPACE_NAME} --yes" \
        "Deleting Log Analytics workspace" \
        "true"
    
    success "Monitoring resources cleaned up"
}

# Function to delete storage account
cleanup_storage() {
    log "Cleaning up storage account..."
    
    # Check if storage account exists
    if az storage account show --resource-group ${RESOURCE_GROUP} --name ${STORAGE_ACCOUNT} &> /dev/null; then
        execute_command \
            "az storage account delete --resource-group ${RESOURCE_GROUP} --name ${STORAGE_ACCOUNT} --yes" \
            "Deleting storage account" \
            "true"
    else
        warning "Storage account not found, skipping storage cleanup"
    fi
    
    success "Storage account cleaned up"
}

# Function to delete Batch account
cleanup_batch_account() {
    log "Cleaning up Batch account..."
    
    # Check if Batch account exists
    if az batch account show --resource-group ${RESOURCE_GROUP} --name ${BATCH_ACCOUNT} &> /dev/null; then
        execute_command \
            "az batch account delete --resource-group ${RESOURCE_GROUP} --name ${BATCH_ACCOUNT} --yes" \
            "Deleting Batch account" \
            "true"
    else
        warning "Batch account not found, skipping Batch account cleanup"
    fi
    
    success "Batch account cleaned up"
}

# Function to delete network resources
cleanup_network() {
    log "Cleaning up network resources..."
    
    # Delete network security group
    execute_command \
        "az network nsg delete --resource-group ${RESOURCE_GROUP} --name ${NSG_NAME}" \
        "Deleting network security group" \
        "true"
    
    # Delete virtual network (this will also delete subnets)
    execute_command \
        "az network vnet delete --resource-group ${RESOURCE_GROUP} --name ${VNET_NAME}" \
        "Deleting virtual network" \
        "true"
    
    success "Network resources cleaned up"
}

# Function to delete resource group
cleanup_resource_group() {
    log "Cleaning up resource group..."
    
    # Check if resource group exists
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        execute_command \
            "az group delete --name ${RESOURCE_GROUP} --yes --no-wait" \
            "Deleting resource group (async)" \
            "false"
        
        log "Resource group deletion initiated. This may take several minutes to complete."
        log "You can monitor the deletion progress in the Azure portal."
    else
        warning "Resource group not found, skipping resource group cleanup"
    fi
    
    success "Resource group cleanup initiated"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files created during deployment
    local files_to_remove=(
        "batch-pool-config.json"
        "mount-elastic-san.sh"
        "hpc-workload.py"
        "autoscale-formula.txt"
        ".env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            execute_command \
                "rm -f $file" \
                "Removing local file: $file" \
                "true"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        warning "Resource group still exists. Deletion may be in progress."
        log "You can check the deletion status with: az group show --name ${RESOURCE_GROUP}"
    else
        success "Resource group successfully deleted"
    fi
    
    success "Deletion verification completed"
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo ""
    echo "Cleanup Actions Performed:"
    echo "✅ Batch jobs and pools deleted"
    echo "✅ Elastic SAN volumes and storage deleted"
    echo "✅ Monitoring resources deleted"
    echo "✅ Storage account deleted"
    echo "✅ Batch account deleted"
    echo "✅ Network resources deleted"
    echo "✅ Resource group deletion initiated"
    echo "✅ Local files cleaned up"
    echo ""
    echo "Note: Resource group deletion is asynchronous and may take several minutes."
    echo "You can monitor the progress in the Azure portal."
    echo ""
    success "Cleanup completed successfully!"
}

# Main execution
main() {
    log "Starting Azure HPC Workload Processing cleanup..."
    
    check_prerequisites
    load_environment_variables
    confirm_deletion
    
    # Clean up resources in reverse order of creation
    cleanup_batch_resources
    cleanup_elastic_san
    cleanup_monitoring
    cleanup_storage
    cleanup_batch_account
    cleanup_network
    cleanup_resource_group
    cleanup_local_files
    
    verify_deletion
    display_summary
    
    success "Cleanup script completed successfully!"
}

# Trap to handle script interruption
trap 'error "Script interrupted. Some resources may not have been deleted. Check Azure portal for remaining resources."' INT TERM

# Execute main function
main "$@"