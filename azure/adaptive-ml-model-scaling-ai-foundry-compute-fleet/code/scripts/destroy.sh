#!/bin/bash

# Adaptive ML Model Scaling with Azure AI Foundry and Compute Fleet
# Cleanup/Destroy Script
# 
# This script removes all resources created by the deployment script
# for the Azure AI Foundry and Compute Fleet adaptive ML scaling solution.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Default values
DRY_RUN=false
FORCE=false
NO_CONFIRM=false
PARALLEL=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --no-confirm)
            NO_CONFIRM=true
            shift
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run        Show what would be deleted without making changes"
            echo "  --force          Skip confirmation prompts and force deletion"
            echo "  --no-confirm     Skip confirmation prompts (same as --force)"
            echo "  --parallel       Delete resources in parallel (faster but less safe)"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  RESOURCE_GROUP   Azure resource group name (default: rg-ml-adaptive-scaling)"
            echo "  RANDOM_SUFFIX    Custom suffix for resource names"
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Set force flag if no-confirm is specified
if [ "$NO_CONFIRM" = true ]; then
    FORCE=true
fi

# Banner
echo "=================================================="
echo "Azure AI Foundry Adaptive ML Scaling Cleanup"
echo "=================================================="
echo ""

if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN MODE - No resources will be deleted"
    echo ""
fi

# Set environment variables with defaults
export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-ml-adaptive-scaling}"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv 2>/dev/null || echo "")

# Try to determine random suffix from existing resources if not provided
if [ -z "${RANDOM_SUFFIX:-}" ]; then
    log_info "Attempting to auto-detect random suffix from existing resources..."
    
    # Try to find the suffix from storage account name
    RANDOM_SUFFIX=$(az storage account list --resource-group "${RESOURCE_GROUP}" --query "[?starts_with(name, 'stmlscaling')].name" -o tsv 2>/dev/null | head -1 | sed 's/stmlscaling//' || echo "")
    
    if [ -z "$RANDOM_SUFFIX" ]; then
        # Try to find suffix from AI Foundry hub name
        RANDOM_SUFFIX=$(az ml workspace list --resource-group "${RESOURCE_GROUP}" --query "[?starts_with(name, 'aif-adaptive-')].name" -o tsv 2>/dev/null | head -1 | sed 's/aif-adaptive-//' || echo "")
    fi
    
    if [ -z "$RANDOM_SUFFIX" ]; then
        log_warning "Could not auto-detect random suffix. Please set RANDOM_SUFFIX environment variable."
    else
        log_info "Auto-detected random suffix: ${RANDOM_SUFFIX}"
    fi
fi

# Set resource names
export AI_FOUNDRY_NAME="aif-adaptive-${RANDOM_SUFFIX}"
export COMPUTE_FLEET_NAME="cf-ml-scaling-${RANDOM_SUFFIX}"
export ML_WORKSPACE_NAME="mlw-scaling-${RANDOM_SUFFIX}"
export STORAGE_ACCOUNT_NAME="stmlscaling${RANDOM_SUFFIX}"
export KEY_VAULT_NAME="kv-ml-${RANDOM_SUFFIX}"
export LOG_ANALYTICS_NAME="law-ml-${RANDOM_SUFFIX}"

log_info "Cleanup Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Random Suffix: ${RANDOM_SUFFIX}"
log_info "  Subscription ID: ${SUBSCRIPTION_ID}"

# Check if resource group exists
check_resource_group() {
    log_info "Checking if resource group exists..."
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group '${RESOURCE_GROUP}' does not exist. Nothing to clean up."
        exit 0
    fi
    
    log_info "Resource group found: ${RESOURCE_GROUP}"
}

# List resources to be deleted
list_resources() {
    log_info "Listing resources to be deleted..."
    
    if [ "$DRY_RUN" = true ] || [ "$FORCE" = false ]; then
        echo ""
        echo "Resources in resource group '${RESOURCE_GROUP}':"
        az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null || log_warning "Failed to list resources"
        echo ""
    fi
}

# Confirmation prompt
confirm_deletion() {
    if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
        echo ""
        read -p "Are you sure you want to delete all resources in '${RESOURCE_GROUP}'? This action cannot be undone. (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user."
            exit 0
        fi
        echo ""
    fi
}

# Stop automated workflows
stop_workflows() {
    log_info "Stopping automated workflows..."
    
    if [ "$DRY_RUN" = false ]; then
        # Disable scaling workflow if it exists
        az ml workflow disable \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${AI_FOUNDRY_NAME}" \
            --name adaptive-ml-scaling 2>/dev/null || log_warning "Failed to disable scaling workflow (may not exist)"
    fi
    
    log_success "Automated workflows stopped"
}

# Remove AI agents and connections
remove_ai_agents() {
    log_info "Removing AI agents and connections..."
    
    if [ "$DRY_RUN" = false ]; then
        # List and delete agent connections
        log_info "Removing agent connections..."
        az ml agent connection delete \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${AI_FOUNDRY_NAME}" \
            --source-agent ml-scaling-agent \
            --target-agent cost-optimizer 2>/dev/null || log_warning "Failed to delete agent connection (may not exist)"
        
        az ml agent connection delete \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${AI_FOUNDRY_NAME}" \
            --source-agent ml-scaling-agent \
            --target-agent performance-monitor 2>/dev/null || log_warning "Failed to delete agent connection (may not exist)"
        
        # Delete individual agents
        log_info "Removing individual agents..."
        az ml agent delete \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${AI_FOUNDRY_NAME}" \
            --name ml-scaling-agent \
            --yes 2>/dev/null || log_warning "Failed to delete main scaling agent (may not exist)"
        
        az ml agent delete \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${AI_FOUNDRY_NAME}" \
            --name cost-optimizer \
            --yes 2>/dev/null || log_warning "Failed to delete cost optimizer agent (may not exist)"
        
        az ml agent delete \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${AI_FOUNDRY_NAME}" \
            --name performance-monitor \
            --yes 2>/dev/null || log_warning "Failed to delete performance monitor agent (may not exist)"
    fi
    
    log_success "AI agents and connections removed"
}

# Remove compute resources
remove_compute_resources() {
    log_info "Removing compute resources..."
    
    if [ "$DRY_RUN" = false ]; then
        # Delete compute fleet
        log_info "Deleting Compute Fleet: ${COMPUTE_FLEET_NAME}"
        az vm fleet delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${COMPUTE_FLEET_NAME}" \
            --yes \
            --no-wait 2>/dev/null || log_warning "Failed to delete Compute Fleet (may not exist)"
        
        # Delete ML compute clusters if they exist
        log_info "Checking for ML compute clusters..."
        local compute_clusters=$(az ml compute list --resource-group "${RESOURCE_GROUP}" --workspace-name "${ML_WORKSPACE_NAME}" --query "[].name" -o tsv 2>/dev/null || echo "")
        
        if [ -n "$compute_clusters" ]; then
            for cluster in $compute_clusters; do
                log_info "Deleting ML compute cluster: ${cluster}"
                az ml compute delete \
                    --resource-group "${RESOURCE_GROUP}" \
                    --workspace-name "${ML_WORKSPACE_NAME}" \
                    --name "$cluster" \
                    --yes \
                    --no-wait 2>/dev/null || log_warning "Failed to delete compute cluster: ${cluster}"
            done
        fi
    fi
    
    log_success "Compute resources removal initiated"
}

# Remove ML and AI workspaces
remove_workspaces() {
    log_info "Removing ML and AI workspaces..."
    
    if [ "$DRY_RUN" = false ]; then
        # Delete ML endpoints first
        log_info "Cleaning up ML endpoints..."
        local endpoints=$(az ml online-endpoint list --resource-group "${RESOURCE_GROUP}" --workspace-name "${ML_WORKSPACE_NAME}" --query "[].name" -o tsv 2>/dev/null || echo "")
        
        if [ -n "$endpoints" ]; then
            for endpoint in $endpoints; do
                log_info "Deleting ML endpoint: ${endpoint}"
                az ml online-endpoint delete \
                    --resource-group "${RESOURCE_GROUP}" \
                    --workspace-name "${ML_WORKSPACE_NAME}" \
                    --name "$endpoint" \
                    --yes \
                    --no-wait 2>/dev/null || log_warning "Failed to delete endpoint: ${endpoint}"
            done
        fi
        
        # Delete ML workspace
        log_info "Deleting ML workspace: ${ML_WORKSPACE_NAME}"
        az ml workspace delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${ML_WORKSPACE_NAME}" \
            --yes \
            --no-wait 2>/dev/null || log_warning "Failed to delete ML workspace (may not exist)"
        
        # Delete AI Foundry project
        log_info "Deleting AI Foundry project: project-${AI_FOUNDRY_NAME}"
        az ml workspace delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "project-${AI_FOUNDRY_NAME}" \
            --yes \
            --no-wait 2>/dev/null || log_warning "Failed to delete AI Foundry project (may not exist)"
        
        # Delete AI Foundry hub
        log_info "Deleting AI Foundry hub: ${AI_FOUNDRY_NAME}"
        az ml workspace delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${AI_FOUNDRY_NAME}" \
            --yes \
            --no-wait 2>/dev/null || log_warning "Failed to delete AI Foundry hub (may not exist)"
    fi
    
    log_success "Workspace removal initiated"
}

# Remove monitoring resources
remove_monitoring() {
    log_info "Removing monitoring resources..."
    
    if [ "$DRY_RUN" = false ]; then
        # Delete monitoring workbook
        az monitor workbook delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "ML-Scaling-Dashboard" \
            --yes 2>/dev/null || log_warning "Failed to delete monitoring workbook (may not exist)"
        
        # Delete alert rules
        local alerts=$(az monitor metrics alert list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv 2>/dev/null || echo "")
        
        if [ -n "$alerts" ]; then
            for alert in $alerts; do
                log_info "Deleting alert rule: ${alert}"
                az monitor metrics alert delete \
                    --resource-group "${RESOURCE_GROUP}" \
                    --name "$alert" \
                    --yes 2>/dev/null || log_warning "Failed to delete alert rule: ${alert}"
            done
        fi
        
        # Delete Log Analytics workspace
        log_info "Deleting Log Analytics workspace: ${LOG_ANALYTICS_NAME}"
        az monitor log-analytics workspace delete \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_ANALYTICS_NAME}" \
            --yes \
            --no-wait 2>/dev/null || log_warning "Failed to delete Log Analytics workspace (may not exist)"
    fi
    
    log_success "Monitoring resources removed"
}

# Remove storage and security resources
remove_storage_security() {
    log_info "Removing storage and security resources..."
    
    if [ "$DRY_RUN" = false ]; then
        # Delete Key Vault (with purge protection disabled)
        log_info "Deleting Key Vault: ${KEY_VAULT_NAME}"
        az keyvault delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${KEY_VAULT_NAME}" \
            --no-wait 2>/dev/null || log_warning "Failed to delete Key Vault (may not exist)"
        
        # Purge Key Vault to completely remove it
        log_info "Purging Key Vault: ${KEY_VAULT_NAME}"
        az keyvault purge \
            --name "${KEY_VAULT_NAME}" \
            --no-wait 2>/dev/null || log_warning "Failed to purge Key Vault (may not exist or may be protected)"
        
        # Delete storage account
        log_info "Deleting storage account: ${STORAGE_ACCOUNT_NAME}"
        az storage account delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --yes 2>/dev/null || log_warning "Failed to delete storage account (may not exist)"
    fi
    
    log_success "Storage and security resources removed"
}

# Wait for resource deletion completion
wait_for_deletion() {
    log_info "Waiting for resource deletion to complete..."
    
    if [ "$DRY_RUN" = false ]; then
        local max_wait=600  # 10 minutes
        local wait_time=0
        
        while [ $wait_time -lt $max_wait ]; do
            local resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length([])" -o tsv 2>/dev/null || echo "0")
            
            if [ "$resource_count" -eq 0 ]; then
                log_success "All resources have been deleted"
                break
            fi
            
            log_info "Waiting for deletion... (${resource_count} resources remaining)"
            sleep 30
            wait_time=$((wait_time + 30))
        done
        
        if [ $wait_time -ge $max_wait ]; then
            log_warning "Timeout waiting for resource deletion. Some resources may still be deleting."
        fi
    fi
}

# Delete resource group
delete_resource_group() {
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    
    if [ "$DRY_RUN" = false ]; then
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait || error_exit "Failed to delete resource group"
        
        log_info "Resource group deletion initiated. This may take several minutes to complete."
    fi
    
    log_success "Resource group deletion started"
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove any temporary configuration files that might have been created
    rm -f agent-config.json cost-optimizer-agent.json performance-monitor-agent.json
    rm -f scaling-workbook.json vm-sizes-profile.json
    rm -f train_model.py scaling-policy.json scaling-workflow.json
    
    log_success "Temporary files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    if [ "$DRY_RUN" = false ]; then
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            log_warning "Resource group still exists. Cleanup may still be in progress."
        else
            log_success "Resource group has been completely removed"
        fi
    fi
}

# Main cleanup function
main() {
    log_info "Starting Azure AI Foundry Adaptive ML Scaling cleanup..."
    
    # Check if resource group exists
    check_resource_group
    
    # List resources
    list_resources
    
    # Get confirmation
    confirm_deletion
    
    if [ "$PARALLEL" = true ]; then
        log_info "Running parallel cleanup (faster but less safe)..."
        
        # Run cleanup operations in parallel
        (
            stop_workflows
            remove_ai_agents
        ) &
        
        (
            remove_compute_resources
        ) &
        
        (
            remove_monitoring
        ) &
        
        (
            remove_storage_security
        ) &
        
        # Wait for all background jobs
        wait
        
        # Remove workspaces after other resources
        remove_workspaces
        
    else
        log_info "Running sequential cleanup (safer but slower)..."
        
        # Sequential cleanup
        stop_workflows
        remove_ai_agents
        remove_compute_resources
        remove_workspaces
        remove_monitoring
        remove_storage_security
    fi
    
    # Wait for deletion completion
    wait_for_deletion
    
    # Delete resource group
    delete_resource_group
    
    # Clean up temporary files
    cleanup_temp_files
    
    # Verify cleanup
    verify_cleanup
    
    # Cleanup summary
    echo ""
    echo "=================================================="
    log_success "Cleanup completed successfully!"
    echo "=================================================="
    echo ""
    log_info "Cleanup Summary:"
    log_info "  Resource Group: ${RESOURCE_GROUP} (deletion initiated)"
    log_info "  AI Foundry Hub: ${AI_FOUNDRY_NAME} (removed)"
    log_info "  ML Workspace: ${ML_WORKSPACE_NAME} (removed)"
    log_info "  Compute Fleet: ${COMPUTE_FLEET_NAME} (removed)"
    log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME} (removed)"
    log_info "  Key Vault: ${KEY_VAULT_NAME} (removed and purged)"
    log_info "  Log Analytics: ${LOG_ANALYTICS_NAME} (removed)"
    echo ""
    log_info "Note: Some Azure resources may take additional time to fully delete."
    log_info "You can verify complete deletion in the Azure Portal."
    echo ""
    log_success "All resources have been cleaned up to avoid ongoing charges!"
}

# Run main function
main "$@"