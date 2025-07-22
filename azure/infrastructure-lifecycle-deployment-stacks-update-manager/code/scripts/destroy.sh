#!/bin/bash

# Azure Infrastructure Lifecycle Management with Deployment Stacks and Update Manager
# Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to load environment variables
load_environment_variables() {
    log "Loading environment variables..."
    
    # Try to load from environment first
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        info "Using environment variables from current session"
    else
        # If not set, try to discover from Azure resources
        warning "Environment variables not set. Attempting to discover resources..."
        
        # Get current subscription
        export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        
        # Try to find resource groups with our naming pattern
        local resource_groups=($(az group list --query "[?starts_with(name, 'rg-infra-lifecycle-')].name" --output tsv))
        
        if [[ ${#resource_groups[@]} -eq 0 ]]; then
            error "No resource groups found with pattern 'rg-infra-lifecycle-*'"
            echo "Please set the RESOURCE_GROUP environment variable manually."
            exit 1
        elif [[ ${#resource_groups[@]} -eq 1 ]]; then
            export RESOURCE_GROUP="${resource_groups[0]}"
            info "Found resource group: $RESOURCE_GROUP"
        else
            error "Multiple resource groups found with pattern 'rg-infra-lifecycle-*':"
            printf '%s\n' "${resource_groups[@]}"
            echo "Please set the RESOURCE_GROUP environment variable manually."
            exit 1
        fi
        
        # Extract suffix from resource group name
        local suffix_pattern="rg-infra-lifecycle-"
        export RANDOM_SUFFIX="${RESOURCE_GROUP#$suffix_pattern}"
        
        # Set derived variables
        export DEPLOYMENT_STACK_NAME="stack-web-tier-${RANDOM_SUFFIX}"
        export MAINTENANCE_CONFIG_NAME="mc-weekly-updates-${RANDOM_SUFFIX}"
        export LOG_ANALYTICS_WORKSPACE="law-monitoring-${RANDOM_SUFFIX}"
    fi
    
    # Display configuration
    info "Configuration:"
    info "  Resource Group: ${RESOURCE_GROUP:-Not set}"
    info "  Deployment Stack: ${DEPLOYMENT_STACK_NAME:-Not set}"
    info "  Maintenance Config: ${MAINTENANCE_CONFIG_NAME:-Not set}"
    info "  Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE:-Not set}"
    info "  Random Suffix: ${RANDOM_SUFFIX:-Not set}"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo "This script will permanently delete the following resources:"
    echo "- Resource Group: ${RESOURCE_GROUP:-Not set}"
    echo "- Deployment Stack: ${DEPLOYMENT_STACK_NAME:-Not set}"
    echo "- Maintenance Configuration: ${MAINTENANCE_CONFIG_NAME:-Not set}"
    echo "- Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE:-Not set}"
    echo "- All associated resources and data"
    echo ""
    
    # Check if running in interactive mode
    if [[ -t 0 ]]; then
        read -p "Are you sure you want to proceed? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    else
        warning "Running in non-interactive mode. Proceeding with deletion in 10 seconds..."
        sleep 10
    fi
    
    log "Proceeding with resource cleanup..."
}

# Function to remove deployment stack
remove_deployment_stack() {
    log "Removing deployment stack..."
    
    if [[ -z "${DEPLOYMENT_STACK_NAME:-}" ]] || [[ -z "${RESOURCE_GROUP:-}" ]]; then
        warning "Deployment stack name or resource group not set. Skipping deployment stack removal."
        return 0
    fi
    
    if az stack group show --name "$DEPLOYMENT_STACK_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        info "Found deployment stack: $DEPLOYMENT_STACK_NAME"
        
        # Remove deployment stack (this will delete all managed resources)
        az stack group delete \
            --name "$DEPLOYMENT_STACK_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --action-on-unmanage deleteAll \
            --yes
        
        log "✅ Deployment stack removed: $DEPLOYMENT_STACK_NAME"
        
        # Wait for stack deletion to complete
        local max_attempts=30
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            if ! az stack group show --name "$DEPLOYMENT_STACK_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                log "✅ Deployment stack deletion completed"
                break
            fi
            
            info "Waiting for deployment stack deletion to complete... (attempt $attempt/$max_attempts)"
            sleep 30
            ((attempt++))
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            warning "Deployment stack deletion may still be in progress. Please check the Azure portal."
        fi
    else
        warning "Deployment stack $DEPLOYMENT_STACK_NAME not found. Skipping removal."
    fi
}

# Function to remove maintenance configuration
remove_maintenance_configuration() {
    log "Removing maintenance configuration..."
    
    if [[ -z "${MAINTENANCE_CONFIG_NAME:-}" ]] || [[ -z "${RESOURCE_GROUP:-}" ]]; then
        warning "Maintenance configuration name or resource group not set. Skipping maintenance configuration removal."
        return 0
    fi
    
    if az maintenance configuration show --resource-group "$RESOURCE_GROUP" --resource-name "$MAINTENANCE_CONFIG_NAME" &> /dev/null; then
        info "Found maintenance configuration: $MAINTENANCE_CONFIG_NAME"
        
        # Remove maintenance assignments first
        local assignments=$(az maintenance assignment list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$assignments" ]]; then
            info "Removing maintenance assignments..."
            while IFS= read -r assignment; do
                if [[ -n "$assignment" ]]; then
                    az maintenance assignment delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --resource-name "$assignment" \
                        --yes &>/dev/null || warning "Failed to remove maintenance assignment: $assignment"
                fi
            done <<< "$assignments"
            log "✅ Maintenance assignments removed"
        fi
        
        # Remove maintenance configuration
        az maintenance configuration delete \
            --resource-group "$RESOURCE_GROUP" \
            --resource-name "$MAINTENANCE_CONFIG_NAME" \
            --yes
        
        log "✅ Maintenance configuration removed: $MAINTENANCE_CONFIG_NAME"
    else
        warning "Maintenance configuration $MAINTENANCE_CONFIG_NAME not found. Skipping removal."
    fi
}

# Function to remove Azure Policy
remove_azure_policy() {
    log "Removing Azure Policy assignments and definitions..."
    
    if [[ -z "${SUBSCRIPTION_ID:-}" ]] || [[ -z "${RESOURCE_GROUP:-}" ]]; then
        warning "Subscription ID or resource group not set. Skipping policy removal."
        return 0
    fi
    
    # Remove policy assignment
    local policy_scope="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
    
    if az policy assignment show --name "deployment-stack-governance" --scope "$policy_scope" &> /dev/null; then
        az policy assignment delete \
            --name "deployment-stack-governance" \
            --scope "$policy_scope"
        log "✅ Policy assignment removed: deployment-stack-governance"
    else
        warning "Policy assignment 'deployment-stack-governance' not found. Skipping removal."
    fi
    
    # Remove custom policy definition
    if az policy definition show --name "enforce-deployment-stack-deny-settings" &> /dev/null; then
        az policy definition delete \
            --name "enforce-deployment-stack-deny-settings"
        log "✅ Policy definition removed: enforce-deployment-stack-deny-settings"
    else
        warning "Policy definition 'enforce-deployment-stack-deny-settings' not found. Skipping removal."
    fi
}

# Function to remove monitoring resources
remove_monitoring_resources() {
    log "Removing monitoring resources..."
    
    if [[ -z "${LOG_ANALYTICS_WORKSPACE:-}" ]] || [[ -z "${RESOURCE_GROUP:-}" ]]; then
        warning "Log Analytics workspace name or resource group not set. Skipping monitoring resource removal."
        return 0
    fi
    
    # Remove workbook
    local workbook_name="infrastructure-lifecycle-dashboard"
    if az monitor workbook show --resource-group "$RESOURCE_GROUP" --name "$workbook_name" &> /dev/null; then
        az monitor workbook delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$workbook_name" \
            --yes
        log "✅ Monitoring workbook removed: $workbook_name"
    else
        warning "Monitoring workbook '$workbook_name' not found. Skipping removal."
    fi
    
    # Remove Log Analytics workspace
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE" &> /dev/null; then
        az monitor log-analytics workspace delete \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --force true \
            --yes
        log "✅ Log Analytics workspace removed: $LOG_ANALYTICS_WORKSPACE"
    else
        warning "Log Analytics workspace '$LOG_ANALYTICS_WORKSPACE' not found. Skipping removal."
    fi
}

# Function to remove resource group
remove_resource_group() {
    log "Removing resource group..."
    
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        warning "Resource group not set. Skipping resource group removal."
        return 0
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        info "Found resource group: $RESOURCE_GROUP"
        
        # Check if resource group is empty
        local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining_resources" -gt 0 ]]; then
            warning "Resource group contains $remaining_resources resources. Deleting anyway..."
        fi
        
        # Delete resource group
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        
        log "✅ Resource group deletion initiated: $RESOURCE_GROUP"
        info "Resource group deletion is running in the background. This may take several minutes."
    else
        warning "Resource group $RESOURCE_GROUP not found. May have been already deleted."
    fi
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    local temp_files=(
        "${SCRIPT_DIR}/policy-definition.json"
        "${SCRIPT_DIR}/compliance-workbook.json"
        "${SCRIPT_DIR}/../bicep/main.bicep"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            info "Removed temporary file: $file"
        fi
    done
    
    log "✅ Temporary files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_success=true
    
    # Check if deployment stack is gone
    if [[ -n "${DEPLOYMENT_STACK_NAME:-}" ]] && [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if az stack group show --name "$DEPLOYMENT_STACK_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            warning "⚠️ Deployment stack still exists: $DEPLOYMENT_STACK_NAME"
            cleanup_success=false
        else
            log "✅ Deployment stack successfully removed"
        fi
    fi
    
    # Check if maintenance configuration is gone
    if [[ -n "${MAINTENANCE_CONFIG_NAME:-}" ]] && [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if az maintenance configuration show --resource-group "$RESOURCE_GROUP" --resource-name "$MAINTENANCE_CONFIG_NAME" &> /dev/null; then
            warning "⚠️ Maintenance configuration still exists: $MAINTENANCE_CONFIG_NAME"
            cleanup_success=false
        else
            log "✅ Maintenance configuration successfully removed"
        fi
    fi
    
    # Check if resource group is gone (or being deleted)
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        local rg_status=$(az group show --name "$RESOURCE_GROUP" --query "properties.provisioningState" --output tsv 2>/dev/null || echo "NotFound")
        
        if [[ "$rg_status" == "NotFound" ]]; then
            log "✅ Resource group successfully removed"
        elif [[ "$rg_status" == "Deleting" ]]; then
            log "✅ Resource group deletion is in progress"
        else
            warning "⚠️ Resource group still exists with status: $rg_status"
            cleanup_success=false
        fi
    fi
    
    if [[ "$cleanup_success" == true ]]; then
        log "✅ Cleanup verification completed successfully"
    else
        warning "⚠️ Some resources may still exist. Please check the Azure portal."
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "===================="
    echo "Removed Resources:"
    echo "- Deployment Stack: ${DEPLOYMENT_STACK_NAME:-Not set}"
    echo "- Maintenance Configuration: ${MAINTENANCE_CONFIG_NAME:-Not set}"
    echo "- Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE:-Not set}"
    echo "- Resource Group: ${RESOURCE_GROUP:-Not set}"
    echo "- Azure Policy assignments and definitions"
    echo "- Monitoring workbooks and configurations"
    echo ""
    echo "Notes:"
    echo "- Resource group deletion may take several minutes to complete"
    echo "- Some resources may take additional time to fully remove"
    echo "- Check the Azure portal to verify complete removal"
    echo ""
    echo "Cleanup completed at: $(date)"
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    error "An error occurred during cleanup. Continuing with remaining resources..."
    return 0  # Continue with cleanup even if individual steps fail
}

# Main execution function
main() {
    log "Starting Azure Infrastructure Lifecycle Management cleanup..."
    
    # Initialize log file
    echo "Azure Infrastructure Lifecycle Management Cleanup Log" > "$LOG_FILE"
    echo "Started at: $(date)" >> "$LOG_FILE"
    echo "=========================================" >> "$LOG_FILE"
    
    # Execute cleanup steps with error handling
    check_prerequisites
    load_environment_variables
    confirm_deletion
    
    # Remove resources in reverse order of creation
    remove_deployment_stack || handle_cleanup_error
    remove_maintenance_configuration || handle_cleanup_error
    remove_azure_policy || handle_cleanup_error
    remove_monitoring_resources || handle_cleanup_error
    remove_resource_group || handle_cleanup_error
    cleanup_temp_files || handle_cleanup_error
    
    verify_cleanup
    display_summary
    
    log "Cleanup completed!"
    log "Log file available at: $LOG_FILE"
}

# Handle script interruption
trap 'error "Cleanup script interrupted. Some resources may still exist. Check the log file for details: $LOG_FILE"; exit 1' INT TERM

# Run main function
main "$@"