#!/bin/bash

# Azure Resource Tagging and Compliance Enforcement Cleanup Script
# This script safely removes all resources created by the deployment script
# including policies, assignments, monitoring configurations, and resource groups.

set -e  # Exit on any error

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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
    fi
    
    log "Prerequisites check passed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        error "Unable to get subscription ID"
    fi
    
    # Set default values (can be overridden by environment variables)
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-governance-demo}"
    export LOCATION="${LOCATION:-eastus}"
    
    # Try to detect existing resources if specific names aren't provided
    if [[ -z "$POLICY_INITIATIVE_NAME" ]]; then
        POLICY_INITIATIVE_NAME=$(az policy set-definition list --query "[?contains(name, 'mandatory-tagging-initiative')].name" -o tsv | head -1)
    fi
    
    if [[ -z "$POLICY_ASSIGNMENT_NAME" ]]; then
        POLICY_ASSIGNMENT_NAME=$(az policy assignment list --scope "/subscriptions/$SUBSCRIPTION_ID" --query "[?contains(name, 'enforce-mandatory-tags')].name" -o tsv | head -1)
    fi
    
    if [[ -z "$LOG_ANALYTICS_WORKSPACE" ]]; then
        LOG_ANALYTICS_WORKSPACE=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'law-governance')].name" -o tsv | head -1)
    fi
    
    if [[ -z "$AUTOMATION_ACCOUNT_NAME" ]]; then
        AUTOMATION_ACCOUNT_NAME=$(az automation account list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'aa-governance')].name" -o tsv | head -1)
    fi
    
    info "Using subscription: $SUBSCRIPTION_ID"
    info "Using resource group: $RESOURCE_GROUP"
    info "Policy initiative: ${POLICY_INITIATIVE_NAME:-'Not found'}"
    info "Policy assignment: ${POLICY_ASSIGNMENT_NAME:-'Not found'}"
    info "Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE:-'Not found'}"
    info "Automation account: ${AUTOMATION_ACCOUNT_NAME:-'Not found'}"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warn "This script will permanently delete the following resources:"
    echo "- Policy assignments and remediation tasks"
    echo "- Policy initiative and custom policy definitions"
    echo "- Resource group: $RESOURCE_GROUP (and all contained resources)"
    echo "- Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE:-'Not found'}"
    echo "- Automation account: ${AUTOMATION_ACCOUNT_NAME:-'Not found'}"
    echo "- Diagnostic settings"
    echo "- Resource Graph shared queries"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    warn "Final confirmation required. This action cannot be undone."
    read -p "Type 'DELETE' to confirm: " -r
    if [[ $REPLY != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource cleanup..."
}

# Function to remove policy assignments and remediation tasks
remove_policy_assignments() {
    log "Removing policy assignments and remediation tasks..."
    
    # Get all remediation tasks for the policy assignment
    if [[ -n "$POLICY_ASSIGNMENT_NAME" ]]; then
        local remediation_tasks=$(az policy remediation list --query "[?policyAssignmentId==\`/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Authorization/policyAssignments/$POLICY_ASSIGNMENT_NAME\`].name" -o tsv)
        
        if [[ -n "$remediation_tasks" ]]; then
            while IFS= read -r task_name; do
                if [[ -n "$task_name" ]]; then
                    log "Deleting remediation task: $task_name"
                    az policy remediation delete --name "$task_name" || warn "Failed to delete remediation task: $task_name"
                fi
            done <<< "$remediation_tasks"
        else
            info "No remediation tasks found"
        fi
        
        # Delete policy assignment
        if az policy assignment show --name "$POLICY_ASSIGNMENT_NAME" --scope "/subscriptions/$SUBSCRIPTION_ID" &> /dev/null; then
            log "Deleting policy assignment: $POLICY_ASSIGNMENT_NAME"
            az policy assignment delete \
                --name "$POLICY_ASSIGNMENT_NAME" \
                --scope "/subscriptions/$SUBSCRIPTION_ID"
            log "Policy assignment deleted: $POLICY_ASSIGNMENT_NAME"
        else
            warn "Policy assignment not found: $POLICY_ASSIGNMENT_NAME"
        fi
    else
        warn "No policy assignment name provided or found"
    fi
    
    # Wait for policy assignment deletion to propagate
    sleep 30
    
    log "Policy assignments and remediation tasks cleanup completed"
}

# Function to remove policy initiative and definitions
remove_policy_initiative() {
    log "Removing policy initiative and custom policy definitions..."
    
    # Delete policy initiative
    if [[ -n "$POLICY_INITIATIVE_NAME" ]]; then
        if az policy set-definition show --name "$POLICY_INITIATIVE_NAME" &> /dev/null; then
            log "Deleting policy initiative: $POLICY_INITIATIVE_NAME"
            az policy set-definition delete --name "$POLICY_INITIATIVE_NAME"
            log "Policy initiative deleted: $POLICY_INITIATIVE_NAME"
        else
            warn "Policy initiative not found: $POLICY_INITIATIVE_NAME"
        fi
    else
        warn "No policy initiative name provided or found"
    fi
    
    # Delete custom policy definitions
    local policy_definitions=("require-department-tag" "require-environment-tag" "inherit-costcenter-tag")
    
    for policy_def in "${policy_definitions[@]}"; do
        if az policy definition show --name "$policy_def" &> /dev/null; then
            log "Deleting policy definition: $policy_def"
            az policy definition delete --name "$policy_def"
            log "Policy definition deleted: $policy_def"
        else
            warn "Policy definition not found: $policy_def"
        fi
    done
    
    log "Policy initiative and definitions cleanup completed"
}

# Function to remove diagnostic settings
remove_diagnostic_settings() {
    log "Removing diagnostic settings..."
    
    # Delete diagnostic settings for policy evaluation logs
    if az monitor diagnostic-settings show --name "policy-compliance-logs" --resource "/subscriptions/$SUBSCRIPTION_ID" &> /dev/null; then
        log "Deleting diagnostic settings: policy-compliance-logs"
        az monitor diagnostic-settings delete \
            --name "policy-compliance-logs" \
            --resource "/subscriptions/$SUBSCRIPTION_ID"
        log "Diagnostic settings deleted: policy-compliance-logs"
    else
        warn "Diagnostic settings not found: policy-compliance-logs"
    fi
    
    log "Diagnostic settings cleanup completed"
}

# Function to remove Resource Graph shared queries
remove_resource_graph_queries() {
    log "Removing Resource Graph shared queries..."
    
    # Check if resource group exists before trying to delete queries
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        # Delete shared query for compliance monitoring
        if az graph shared-query show --name "tag-compliance-dashboard" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log "Deleting shared query: tag-compliance-dashboard"
            az graph shared-query delete \
                --name "tag-compliance-dashboard" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            log "Shared query deleted: tag-compliance-dashboard"
        else
            warn "Shared query not found: tag-compliance-dashboard"
        fi
    else
        warn "Resource group $RESOURCE_GROUP not found - skipping shared query deletion"
    fi
    
    log "Resource Graph queries cleanup completed"
}

# Function to remove automation account
remove_automation_account() {
    log "Removing automation account..."
    
    if [[ -n "$AUTOMATION_ACCOUNT_NAME" ]] && az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        if az automation account show --name "$AUTOMATION_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log "Deleting automation account: $AUTOMATION_ACCOUNT_NAME"
            az automation account delete \
                --name "$AUTOMATION_ACCOUNT_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            log "Automation account deleted: $AUTOMATION_ACCOUNT_NAME"
        else
            warn "Automation account not found: $AUTOMATION_ACCOUNT_NAME"
        fi
    else
        warn "No automation account name provided or resource group not found"
    fi
    
    log "Automation account cleanup completed"
}

# Function to remove resource group and all resources
remove_resource_group() {
    log "Removing resource group and all contained resources..."
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting resource group: $RESOURCE_GROUP"
        info "This may take several minutes to complete..."
        
        # Delete resource group and all contained resources
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
            
        log "Resource group deletion initiated: $RESOURCE_GROUP"
        log "Note: Deletion may take several minutes to complete in the background"
        
        # Optionally wait for completion
        read -p "Do you want to wait for resource group deletion to complete? (yes/no): " -r
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Waiting for resource group deletion to complete..."
            local max_attempts=60
            local attempt=1
            
            while [[ $attempt -le $max_attempts ]]; do
                if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
                    log "Resource group deletion completed successfully"
                    break
                fi
                info "Waiting for resource group deletion... (attempt $attempt/$max_attempts)"
                sleep 30
                ((attempt++))
            done
            
            if [[ $attempt -gt $max_attempts ]]; then
                warn "Resource group deletion is taking longer than expected. Check Azure portal for status."
            fi
        fi
    else
        warn "Resource group $RESOURCE_GROUP not found - may have already been deleted"
    fi
    
    log "Resource group cleanup completed"
}

# Function to clean up environment variables
cleanup_environment() {
    log "Cleaning up environment variables..."
    
    # Unset environment variables
    unset SUBSCRIPTION_ID RESOURCE_GROUP LOCATION LOG_ANALYTICS_WORKSPACE
    unset POLICY_INITIATIVE_NAME POLICY_ASSIGNMENT_NAME AUTOMATION_ACCOUNT_NAME
    
    # Remove temporary files
    rm -f /tmp/remediation-runbook.ps1 2>/dev/null || true
    rm -f dashboard-config.json 2>/dev/null || true
    
    log "Environment cleanup completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "===================="
    echo "The following resources have been removed:"
    echo "- Policy assignments and remediation tasks"
    echo "- Policy initiative and custom policy definitions"
    echo "- Resource group: $RESOURCE_GROUP (and all contained resources)"
    echo "- Log Analytics workspace"
    echo "- Automation account"
    echo "- Diagnostic settings"
    echo "- Resource Graph shared queries"
    echo "- Temporary files and environment variables"
    echo "===================="
    echo ""
    echo "Cleanup completed successfully!"
    echo ""
    echo "Notes:"
    echo "- Resource group deletion may continue in the background"
    echo "- Policy assignments may take up to 30 minutes to fully propagate"
    echo "- Check Azure portal to verify all resources have been removed"
    echo ""
    echo "If you encounter any issues, you can:"
    echo "1. Check the Azure portal for remaining resources"
    echo "2. Manually remove any remaining resources"
    echo "3. Run this script again to clean up any missed resources"
}

# Function to handle errors gracefully
handle_errors() {
    local exit_code=$1
    local line_number=$2
    
    error "Script failed at line $line_number with exit code $exit_code"
    warn "Cleanup may be incomplete. Please check the Azure portal and manually remove any remaining resources."
    
    # Attempt to provide helpful troubleshooting information
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check if you have sufficient permissions to delete resources"
    echo "2. Verify that no resources are locked or have dependencies"
    echo "3. Check the Azure portal for any remaining resources"
    echo "4. Try running specific deletion commands manually"
    echo ""
    
    exit $exit_code
}

# Set up error handling
trap 'handle_errors $? $LINENO' ERR

# Main execution
main() {
    log "Starting Azure Resource Tagging and Compliance Enforcement cleanup..."
    
    check_prerequisites
    set_environment_variables
    confirm_deletion
    
    # Remove resources in reverse order of creation
    remove_policy_assignments
    remove_policy_initiative
    remove_diagnostic_settings
    remove_resource_graph_queries
    remove_automation_account
    remove_resource_group
    cleanup_environment
    
    display_cleanup_summary
    
    log "Cleanup completed successfully!"
}

# Handle script interruption
trap 'log "Script interrupted by user"; exit 1' INT TERM

# Run main function
main "$@"