#!/bin/bash

# Azure IoT Digital Twins with Azure Data Explorer - Cleanup Script
# This script safely removes all resources created by the deployment script
# to avoid ongoing charges and clean up the Azure subscription.

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Error handler
error_exit() {
    log_error "Script failed at line $1"
    log_error "Command that failed: $2"
    log_warning "Some resources may not have been deleted. Please check Azure portal."
    exit 1
}

# Set up error handling (continue on error for cleanup)
# We don't want cleanup to stop if one resource fails to delete
set +e

# Script metadata
readonly SCRIPT_NAME="Azure IoT Digital Twins Cleanup"
readonly SCRIPT_VERSION="1.0"
readonly ESTIMATED_TIME="5-10 minutes"

# Print script header
print_header() {
    echo "=================================================="
    echo "   $SCRIPT_NAME"
    echo "   Version: $SCRIPT_VERSION"
    echo "   Estimated cleanup time: $ESTIMATED_TIME"
    echo "=================================================="
    echo
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Load environment variables
load_environment_variables() {
    log_info "Loading environment variables..."
    
    if [[ -f ".env.deploy" ]]; then
        log_info "Loading variables from .env.deploy file"
        source .env.deploy
        log_success "Environment variables loaded from deployment file"
    else
        log_warning ".env.deploy file not found"
        log_info "Please provide resource group name manually or ensure .env.deploy exists"
        
        # Prompt for resource group if not found
        if [[ -z "${RESOURCE_GROUP:-}" ]]; then
            echo
            read -p "Enter the resource group name to delete: " RESOURCE_GROUP
            if [[ -z "$RESOURCE_GROUP" ]]; then
                log_error "Resource group name is required"
                exit 1
            fi
        fi
    fi
    
    # Validate required variables
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_error "RESOURCE_GROUP variable is not set"
        exit 1
    fi
    
    log_info "Resource Group to delete: $RESOURCE_GROUP"
}

# Get user confirmation with safety checks
get_user_confirmation() {
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log_warning "This script will permanently delete the following:"
    echo "  • Resource Group: $RESOURCE_GROUP"
    echo "  • All contained resources including:"
    echo "    - Azure Digital Twins instance"
    echo "    - Azure Data Explorer cluster"
    echo "    - IoT Central application"
    echo "    - Function App and storage"
    echo "    - Event Hub namespace"
    echo "    - Time Series Insights environment"
    echo "    - All data and configurations"
    echo
    log_warning "This action CANNOT be undone!"
    echo
    
    # First confirmation
    read -p "Are you sure you want to delete these resources? (yes/no): " -r
    if [[ ! $REPLY =~ ^(yes|YES)$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    # Second confirmation for safety
    echo
    log_warning "Final confirmation required!"
    read -p "Type 'DELETE' to confirm permanent deletion: " -r
    if [[ ! $REPLY == "DELETE" ]]; then
        log_info "Cleanup cancelled - confirmation not received"
        exit 0
    fi
    
    echo
    log_info "Proceeding with resource deletion..."
}

# Check if resource group exists
check_resource_group_exists() {
    log_info "Checking if resource group exists..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Resource group '$RESOURCE_GROUP' found"
        return 0
    else
        log_warning "Resource group '$RESOURCE_GROUP' not found"
        return 1
    fi
}

# List resources before deletion
list_resources() {
    log_info "Listing resources in $RESOURCE_GROUP before deletion..."
    
    local resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query 'length(@)' --output tsv 2>/dev/null || echo "0")
    
    if [[ "$resource_count" -gt 0 ]]; then
        log_info "Found $resource_count resources:"
        az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query '[].{Name:name, Type:type, Location:location}' \
            --output table 2>/dev/null || log_warning "Could not list resources"
    else
        log_info "No resources found in resource group"
    fi
}

# Attempt graceful shutdown of specific services
graceful_shutdown() {
    log_info "Attempting graceful shutdown of key services..."
    
    # Stop Azure Data Explorer cluster if it exists
    if [[ -n "${ADX_CLUSTER:-}" ]]; then
        log_info "Stopping Azure Data Explorer cluster: $ADX_CLUSTER"
        az kusto cluster stop \
            --name "$ADX_CLUSTER" \
            --resource-group "$RESOURCE_GROUP" \
            --output none 2>/dev/null && \
            log_success "ADX cluster stop initiated" || \
            log_warning "Could not stop ADX cluster (may not exist)"
    fi
    
    # Stop Function App if it exists
    if [[ -n "${FUNC_APP:-}" ]]; then
        log_info "Stopping Function App: $FUNC_APP"
        az functionapp stop \
            --name "$FUNC_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --output none 2>/dev/null && \
            log_success "Function App stopped" || \
            log_warning "Could not stop Function App (may not exist)"
    fi
    
    log_info "Graceful shutdown completed"
}

# Delete individual resources with specific handling
delete_specific_resources() {
    log_info "Deleting specific resources individually for better control..."
    
    # Delete Time Series Insights environment (has dependencies)
    if [[ -n "${TSI_ENV:-}" ]]; then
        log_info "Deleting Time Series Insights environment: $TSI_ENV"
        az tsi environment delete \
            --name "$TSI_ENV" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none 2>/dev/null && \
            log_success "TSI environment deleted" || \
            log_warning "Could not delete TSI environment"
    fi
    
    # Delete Azure Digital Twins instance
    if [[ -n "${ADT_NAME:-}" ]]; then
        log_info "Deleting Azure Digital Twins instance: $ADT_NAME"
        az dt delete \
            --name "$ADT_NAME" \
            --yes \
            --output none 2>/dev/null && \
            log_success "Azure Digital Twins instance deleted" || \
            log_warning "Could not delete Azure Digital Twins instance"
    fi
    
    # Delete IoT Central application
    if [[ -n "${IOTC_APP:-}" ]]; then
        log_info "Deleting IoT Central application: $IOTC_APP"
        az iot central app delete \
            --name "$IOTC_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none 2>/dev/null && \
            log_success "IoT Central application deleted" || \
            log_warning "Could not delete IoT Central application"
    fi
    
    # Delete Azure Data Explorer cluster
    if [[ -n "${ADX_CLUSTER:-}" ]]; then
        log_info "Deleting Azure Data Explorer cluster: $ADX_CLUSTER (this may take several minutes)"
        az kusto cluster delete \
            --name "$ADX_CLUSTER" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none 2>/dev/null && \
            log_success "ADX cluster deletion initiated" || \
            log_warning "Could not delete ADX cluster"
    fi
    
    log_info "Individual resource deletion completed"
}

# Delete the entire resource group
delete_resource_group() {
    log_info "Deleting resource group and all remaining resources..."
    log_warning "This operation may take 10-15 minutes for complex resources like ADX cluster"
    
    # Delete resource group (this removes all resources)
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        log_info "Deletion is running in the background"
    else
        log_error "Failed to initiate resource group deletion"
        return 1
    fi
}

# Monitor deletion progress
monitor_deletion_progress() {
    log_info "Monitoring deletion progress..."
    
    local max_attempts=30
    local attempt=0
    local check_interval=30
    
    while [[ $attempt -lt $max_attempts ]]; do
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log_success "Resource group has been completely deleted"
            return 0
        fi
        
        attempt=$((attempt + 1))
        local remaining=$((max_attempts - attempt))
        log_info "Resource group still exists. Checking again in ${check_interval}s (${remaining} checks remaining)..."
        sleep $check_interval
    done
    
    log_warning "Resource group deletion is taking longer than expected"
    log_info "You can check the status in Azure Portal or run: az group show --name $RESOURCE_GROUP"
    return 1
}

# Verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' still exists"
        log_info "Checking remaining resources..."
        
        local remaining_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query 'length(@)' --output tsv 2>/dev/null || echo "unknown")
        
        if [[ "$remaining_count" == "0" ]]; then
            log_info "Resource group is empty but still exists (may be in deletion process)"
        else
            log_warning "$remaining_count resources still exist in the resource group"
            log_info "Listing remaining resources:"
            az resource list \
                --resource-group "$RESOURCE_GROUP" \
                --query '[].{Name:name, Type:type}' \
                --output table 2>/dev/null || log_warning "Could not list remaining resources"
        fi
        
        return 1
    else
        log_success "Resource group '$RESOURCE_GROUP' has been completely deleted"
        return 0
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f ".env.deploy" ]]; then
        rm -f .env.deploy
        log_success "Removed .env.deploy file"
    fi
    
    # Remove any temporary files that might have been created
    rm -f equipment-model.json 2>/dev/null
    
    log_success "Local cleanup completed"
}

# Print cleanup summary
print_cleanup_summary() {
    echo
    echo "=================================================="
    echo "   CLEANUP OPERATION SUMMARY"
    echo "=================================================="
    echo
    
    if verify_deletion; then
        log_success "🎉 All resources have been successfully deleted!"
        echo
        log_info "The following have been removed:"
        echo "  ✅ Resource Group: $RESOURCE_GROUP"
        echo "  ✅ Azure Digital Twins instance"
        echo "  ✅ Azure Data Explorer cluster"
        echo "  ✅ IoT Central application"
        echo "  ✅ Function App and storage"
        echo "  ✅ Event Hub namespace"
        echo "  ✅ Time Series Insights environment"
        echo "  ✅ All data and configurations"
        echo
        log_success "No further charges will be incurred for these resources."
    else
        log_warning "⚠️  Cleanup may be incomplete"
        echo
        log_info "Some resources may still exist. Please:"
        echo "  1. Check Azure Portal for remaining resources"
        echo "  2. Wait additional time for background deletion"
        echo "  3. Manually delete any remaining resources if needed"
        echo
        log_info "Command to check status:"
        echo "  az group show --name $RESOURCE_GROUP"
    fi
    
    echo "=================================================="
}

# Main cleanup function
main() {
    print_header
    check_prerequisites
    load_environment_variables
    
    if ! check_resource_group_exists; then
        log_info "Resource group does not exist - nothing to clean up"
        cleanup_local_files
        exit 0
    fi
    
    get_user_confirmation
    list_resources
    graceful_shutdown
    delete_specific_resources
    
    log_info "Waiting 30 seconds before resource group deletion..."
    sleep 30
    
    delete_resource_group
    monitor_deletion_progress
    cleanup_local_files
    print_cleanup_summary
    
    log_info "Cleanup script completed at $(date)"
}

# Run main function
main "$@"