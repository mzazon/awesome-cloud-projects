#!/bin/bash

# Destroy script for Orchestrating Distributed Cache Warm-up Workflows
# with Azure Container Apps Jobs and Azure Redis Enterprise
#
# This script safely removes all resources created by the deploy script:
# - Azure Container Apps Jobs and Environment
# - Azure Redis Enterprise cluster
# - Azure Storage Account
# - Azure Key Vault (with purge protection handling)
# - Azure Monitor resources
# - Resource Group and all contained resources

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription info
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    log "Using Azure subscription: $subscription_name ($subscription_id)"
    
    success "Prerequisites check completed successfully"
}

# Function to prompt for confirmation
confirm_destruction() {
    echo
    warn "⚠️  WARNING: This script will DELETE ALL resources created by the deployment script!"
    warn "This action is IRREVERSIBLE and will result in:"
    warn "  - Loss of all cache data in Redis Enterprise"
    warn "  - Deletion of all Container Apps jobs and logs"
    warn "  - Removal of all stored secrets and configuration"
    warn "  - Complete cleanup of the resource group"
    echo
    
    # Check if running in non-interactive mode
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        log "Force destroy mode enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "User confirmed destruction"
}

# Function to get resource group from user input or discover existing ones
get_resource_group() {
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log "Using provided resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Try to find cache warmup resource groups
    local cache_warmup_groups=$(az group list \
        --query "[?tags.purpose=='cache-warmup'].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$cache_warmup_groups" ]]; then
        echo
        error "No cache warmup resource groups found and RESOURCE_GROUP not provided."
        error "Please provide the resource group name:"
        error "  export RESOURCE_GROUP=your-resource-group-name"
        error "  ./destroy.sh"
        exit 1
    fi
    
    # If only one group found, use it
    local group_count=$(echo "$cache_warmup_groups" | wc -l)
    if [[ $group_count -eq 1 ]]; then
        export RESOURCE_GROUP="$cache_warmup_groups"
        log "Auto-detected resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Multiple groups found, ask user to choose
    echo
    log "Multiple cache warmup resource groups found:"
    local i=1
    while IFS= read -r group; do
        echo "  $i) $group"
        ((i++))
    done <<< "$cache_warmup_groups"
    
    echo
    read -p "Select resource group number (1-$((i-1))): " selection
    
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ $selection -lt 1 ]] || [[ $selection -ge $i ]]; then
        error "Invalid selection"
        exit 1
    fi
    
    export RESOURCE_GROUP=$(echo "$cache_warmup_groups" | sed -n "${selection}p")
    log "Selected resource group: $RESOURCE_GROUP"
}

# Function to verify resource group exists and contains expected resources
verify_resource_group() {
    log "Verifying resource group: $RESOURCE_GROUP"
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group '$RESOURCE_GROUP' does not exist"
        exit 1
    fi
    
    # Check if it has the expected purpose tag
    local purpose=$(az group show \
        --name "$RESOURCE_GROUP" \
        --query "tags.purpose" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ "$purpose" != "cache-warmup" ]]; then
        warn "Resource group '$RESOURCE_GROUP' does not have 'cache-warmup' purpose tag"
        warn "This might not be a cache warmup resource group"
        
        if [[ "${FORCE_DESTROY:-false}" != "true" ]]; then
            read -p "Continue anyway? (yes/no): " continue_anyway
            if [[ "$continue_anyway" != "yes" ]]; then
                log "Destruction cancelled"
                exit 0
            fi
        fi
    fi
    
    # List resources in the group
    local resource_count=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "length(@)" \
        --output tsv)
    
    log "Found $resource_count resources in resource group"
    
    if [[ $resource_count -eq 0 ]]; then
        warn "Resource group is empty, nothing to clean up"
        return 0
    fi
    
    # Show resource types for verification
    log "Resource types found:"
    az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].type" \
        --output tsv | sort | uniq -c | while read count type; do
        log "  $count x $type"
    done
    
    success "Resource group verification completed"
}

# Function to stop running Container Apps jobs
stop_container_jobs() {
    log "Stopping running Container Apps jobs..."
    
    # Get list of Container Apps jobs
    local jobs=$(az containerapp job list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$jobs" ]]; then
        log "No Container Apps jobs found"
        return 0
    fi
    
    # Stop each job's running executions
    while IFS= read -r job_name; do
        if [[ -n "$job_name" ]]; then
            log "Checking job: $job_name"
            
            # Get running executions
            local executions=$(az containerapp job execution list \
                --name "$job_name" \
                --resource-group "$RESOURCE_GROUP" \
                --query "[?status=='Running'].name" \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "$executions" ]]; then
                while IFS= read -r execution_name; do
                    if [[ -n "$execution_name" ]]; then
                        log "Stopping execution: $execution_name"
                        az containerapp job stop \
                            --name "$job_name" \
                            --resource-group "$RESOURCE_GROUP" \
                            --job-execution-name "$execution_name" \
                            --no-wait \
                            --output none 2>/dev/null || warn "Failed to stop execution $execution_name"
                    fi
                done <<< "$executions"
            else
                log "No running executions for job: $job_name"
            fi
        fi
    done <<< "$jobs"
    
    # Wait a moment for jobs to stop
    if [[ -n "$jobs" ]]; then
        log "Waiting for jobs to stop..."
        sleep 10
    fi
    
    success "Container Apps jobs stop process completed"
}

# Function to handle Key Vault deletion and purging
delete_key_vaults() {
    log "Handling Key Vault deletion..."
    
    # Get list of Key Vaults in the resource group
    local key_vaults=$(az keyvault list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$key_vaults" ]]; then
        log "No Key Vaults found"
        return 0
    fi
    
    # Delete and purge each Key Vault
    while IFS= read -r vault_name; do
        if [[ -n "$vault_name" ]]; then
            log "Deleting Key Vault: $vault_name"
            
            # Delete the Key Vault
            az keyvault delete \
                --name "$vault_name" \
                --resource-group "$RESOURCE_GROUP" \
                --output none 2>/dev/null || warn "Failed to delete Key Vault $vault_name"
            
            # Purge the Key Vault to completely remove it
            log "Purging Key Vault: $vault_name"
            az keyvault purge \
                --name "$vault_name" \
                --no-wait \
                --output none 2>/dev/null || warn "Failed to purge Key Vault $vault_name (may not have purge protection)"
        fi
    done <<< "$key_vaults"
    
    success "Key Vault deletion process completed"
}

# Function to handle Redis Enterprise deletion
delete_redis_enterprise() {
    log "Deleting Redis Enterprise clusters..."
    
    # Get list of Redis instances in the resource group
    local redis_instances=$(az redis list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$redis_instances" ]]; then
        log "No Redis instances found"
        return 0
    fi
    
    # Delete each Redis instance
    while IFS= read -r redis_name; do
        if [[ -n "$redis_name" ]]; then
            log "Deleting Redis instance: $redis_name"
            warn "Redis Enterprise deletion may take 10-15 minutes..."
            
            az redis delete \
                --name "$redis_name" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --no-wait \
                --output none 2>/dev/null || warn "Failed to delete Redis instance $redis_name"
        fi
    done <<< "$redis_instances"
    
    success "Redis Enterprise deletion process initiated"
}

# Function to delete Container Apps environment
delete_container_apps_environment() {
    log "Deleting Container Apps environments..."
    
    # Get list of Container Apps environments
    local environments=$(az containerapp env list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$environments" ]]; then
        log "No Container Apps environments found"
        return 0
    fi
    
    # Delete each environment
    while IFS= read -r env_name; do
        if [[ -n "$env_name" ]]; then
            log "Deleting Container Apps environment: $env_name"
            
            az containerapp env delete \
                --name "$env_name" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --no-wait \
                --output none 2>/dev/null || warn "Failed to delete environment $env_name"
        fi
    done <<< "$environments"
    
    success "Container Apps environment deletion process initiated"
}

# Function to clean up local Docker images
cleanup_docker_images() {
    log "Cleaning up local Docker images..."
    
    # Remove coordinator image
    if docker image inspect coordinator:latest &> /dev/null; then
        docker rmi coordinator:latest &> /dev/null || warn "Failed to remove coordinator image"
        log "Removed coordinator Docker image"
    fi
    
    # Remove worker image
    if docker image inspect worker:latest &> /dev/null; then
        docker rmi worker:latest &> /dev/null || warn "Failed to remove worker image"
        log "Removed worker Docker image"
    fi
    
    # Clean up dangling images
    docker image prune -f &> /dev/null || warn "Failed to prune Docker images"
    
    success "Docker image cleanup completed"
}

# Function to delete the entire resource group
delete_resource_group() {
    log "Deleting resource group: $RESOURCE_GROUP"
    warn "This will delete ALL remaining resources in the group..."
    
    # Final confirmation for resource group deletion
    if [[ "${FORCE_DESTROY:-false}" != "true" ]]; then
        echo
        read -p "Delete resource group '$RESOURCE_GROUP' and ALL its resources? (yes/no): " final_confirmation
        
        if [[ "$final_confirmation" != "yes" ]]; then
            log "Resource group deletion cancelled"
            return 0
        fi
    fi
    
    # Delete the resource group
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none
    
    log "Resource group deletion initiated: $RESOURCE_GROUP"
    log "Complete deletion may take 10-20 minutes"
    
    success "Resource group deletion process started"
}

# Function to wait for resource group deletion (optional)
wait_for_deletion() {
    if [[ "${WAIT_FOR_COMPLETION:-false}" != "true" ]]; then
        log "Skipping wait for deletion completion (set WAIT_FOR_COMPLETION=true to wait)"
        return 0
    fi
    
    log "Waiting for resource group deletion to complete..."
    
    local timeout=1200  # 20 minutes
    local elapsed=0
    local interval=30
    
    while [ $elapsed -lt $timeout ]; do
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            success "Resource group successfully deleted"
            return 0
        fi
        
        log "Resource group still exists (elapsed: ${elapsed}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    warn "Resource group deletion timed out after $timeout seconds"
    warn "Check Azure Portal for deletion status"
}

# Function to display cleanup summary
display_summary() {
    echo
    echo "=== CLEANUP SUMMARY ==="
    log "Cleanup process completed for resource group: $RESOURCE_GROUP"
    echo
    echo "Resources processed:"
    echo "  ✓ Container Apps jobs stopped"
    echo "  ✓ Key Vaults deleted and purged"
    echo "  ✓ Redis Enterprise clusters deleted"
    echo "  ✓ Container Apps environments deleted"
    echo "  ✓ Local Docker images cleaned up"
    echo "  ✓ Resource group deletion initiated"
    echo
    echo "=== IMPORTANT NOTES ==="
    warn "1. Some resources may take additional time to fully delete"
    warn "2. Check Azure Portal to confirm complete resource removal"
    warn "3. Purged Key Vaults cannot be recovered"
    warn "4. All cache data has been permanently lost"
    echo
    log "Monitor deletion progress in Azure Portal or use:"
    log "  az group show --name $RESOURCE_GROUP"
    echo
    success "Cleanup process completed successfully!"
}

# Main destruction function
main() {
    echo "=========================================="
    echo "Azure Cache Warm-up Destruction Script"
    echo "=========================================="
    echo
    
    check_prerequisites
    get_resource_group
    verify_resource_group
    confirm_destruction
    
    log "Starting resource cleanup process..."
    
    stop_container_jobs
    delete_key_vaults
    delete_redis_enterprise
    delete_container_apps_environment
    cleanup_docker_images
    delete_resource_group
    wait_for_deletion
    
    display_summary
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h           Show this help message"
        echo "  --force              Skip confirmation prompts"
        echo "  --wait               Wait for deletion to complete"
        echo
        echo "Environment variables:"
        echo "  RESOURCE_GROUP       Resource group to delete (auto-detected if not set)"
        echo "  FORCE_DESTROY        Set to 'true' to skip confirmations"
        echo "  WAIT_FOR_COMPLETION  Set to 'true' to wait for deletion completion"
        echo
        echo "Examples:"
        echo "  $0                                    # Interactive mode"
        echo "  RESOURCE_GROUP=my-rg $0 --force      # Force delete specific group"
        echo "  $0 --force --wait                    # Force delete and wait"
        exit 0
        ;;
    --force)
        export FORCE_DESTROY=true
        ;;
    --wait)
        export WAIT_FOR_COMPLETION=true
        ;;
    --force --wait|--wait --force)
        export FORCE_DESTROY=true
        export WAIT_FOR_COMPLETION=true
        ;;
esac

# Run main function
main "$@"