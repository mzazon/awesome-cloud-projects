#!/bin/bash

# Destroy Azure Confidential Ledger and Logic Apps Audit Trail Solution
# This script safely removes all resources created by the deployment script
# with proper confirmation prompts and error handling.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="destroy_$(date +%Y%m%d_%H%M%S).log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly DELETION_TIMEOUT=1800  # 30 minutes

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}" | tee -a "${LOG_FILE}"
}

print_info() { print_status "${BLUE}" "INFO: $1"; }
print_success() { print_status "${GREEN}" "SUCCESS: $1"; }
print_warning() { print_status "${YELLOW}" "WARNING: $1"; }
print_error() { print_status "${RED}" "ERROR: $1"; }

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to cleanup on script exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_error "Script failed with exit code $exit_code"
        print_info "Check the log file for details: ${LOG_FILE}"
        print_info "Some resources may still exist and require manual cleanup"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        print_error "Azure CLI is not installed"
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show >/dev/null 2>&1; then
        print_error "Not logged into Azure. Please run 'az login' first"
        exit 1
    fi
    
    print_success "Prerequisites check completed"
}

# Function to prompt for confirmation
confirm_destruction() {
    print_warning "This script will permanently delete the following resources:"
    print_warning "- Resource Group and ALL contained resources"
    print_warning "- Azure Confidential Ledger (immutable audit data will be lost)"
    print_warning "- Key Vault (secrets will be soft-deleted)"
    print_warning "- Logic App workflows"
    print_warning "- Event Hub namespace and events"
    print_warning "- Storage Account and all data"
    print_warning ""
    print_warning "This action cannot be undone!"
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Destruction cancelled by user"
        exit 0
    fi
    
    print_warning "Final confirmation required!"
    read -p "Type 'DELETE' to confirm resource destruction: " -r
    if [[ $REPLY != "DELETE" ]]; then
        print_info "Destruction cancelled by user"
        exit 0
    fi
}

# Function to discover resources
discover_resources() {
    print_info "Discovering deployed resources..."
    
    # Check if we can find resource groups matching the pattern
    local resource_groups
    resource_groups=$(az group list --query "[?starts_with(name, 'rg-audit-trail-')].name" --output tsv)
    
    if [[ -z "$resource_groups" ]]; then
        print_warning "No resource groups found matching pattern 'rg-audit-trail-*'"
        
        # Prompt user to specify resource group
        print_info "Available resource groups:"
        az group list --query "[].name" --output table
        
        read -p "Enter the resource group name to delete (or 'cancel' to exit): " -r
        if [[ $REPLY == "cancel" ]]; then
            print_info "Destruction cancelled by user"
            exit 0
        fi
        
        export RESOURCE_GROUP="$REPLY"
    else
        print_info "Found resource groups matching pattern:"
        echo "$resource_groups"
        
        if [[ $(echo "$resource_groups" | wc -l) -eq 1 ]]; then
            export RESOURCE_GROUP="$resource_groups"
            print_info "Using resource group: $RESOURCE_GROUP"
        else
            print_info "Multiple resource groups found. Please select one:"
            select rg in $resource_groups; do
                if [[ -n "$rg" ]]; then
                    export RESOURCE_GROUP="$rg"
                    print_info "Selected resource group: $RESOURCE_GROUP"
                    break
                fi
            done
        fi
    fi
    
    # Verify resource group exists
    if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_error "Resource group '$RESOURCE_GROUP' does not exist"
        exit 1
    fi
    
    print_success "Resource discovery completed"
}

# Function to list resources in the resource group
list_resources() {
    print_info "Listing resources in resource group: $RESOURCE_GROUP"
    
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table)
    
    if [[ -z "$resources" ]]; then
        print_warning "No resources found in resource group: $RESOURCE_GROUP"
        return 1
    fi
    
    echo "$resources"
    print_info "Total resources found: $(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv)"
    
    return 0
}

# Function to handle Key Vault deletion
handle_keyvault_deletion() {
    print_info "Handling Key Vault deletion..."
    
    # Find Key Vaults in the resource group
    local keyvaults
    keyvaults=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    if [[ -z "$keyvaults" ]]; then
        print_info "No Key Vaults found in resource group"
        return 0
    fi
    
    for keyvault in $keyvaults; do
        print_info "Processing Key Vault: $keyvault"
        
        # Check if Key Vault has purge protection enabled
        local purge_protection
        purge_protection=$(az keyvault show --name "$keyvault" --resource-group "$RESOURCE_GROUP" --query properties.enablePurgeProtection --output tsv)
        
        if [[ "$purge_protection" == "true" ]]; then
            print_warning "Key Vault '$keyvault' has purge protection enabled"
            print_warning "After deletion, it will be soft-deleted and cannot be purged for 90 days"
            print_warning "The Key Vault name will be reserved during this period"
        fi
        
        # Delete the Key Vault (this will soft-delete it)
        print_info "Deleting Key Vault: $keyvault"
        az keyvault delete --name "$keyvault" --resource-group "$RESOURCE_GROUP" --output none
        
        print_success "Key Vault '$keyvault' deleted (soft-deleted)"
    done
}

# Function to handle Confidential Ledger deletion
handle_confidential_ledger_deletion() {
    print_info "Handling Confidential Ledger deletion..."
    
    # Find Confidential Ledgers in the resource group
    local ledgers
    ledgers=$(az confidentialledger list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    if [[ -z "$ledgers" ]]; then
        print_info "No Confidential Ledgers found in resource group"
        return 0
    fi
    
    for ledger in $ledgers; do
        print_warning "Deleting Confidential Ledger: $ledger"
        print_warning "All immutable audit data will be permanently lost!"
        
        # Delete the Confidential Ledger
        az confidentialledger delete --name "$ledger" --resource-group "$RESOURCE_GROUP" --yes --output none
        
        print_success "Confidential Ledger '$ledger' deletion initiated"
    done
}

# Function to handle Storage Account deletion
handle_storage_deletion() {
    print_info "Handling Storage Account deletion..."
    
    # Find Storage Accounts in the resource group
    local storage_accounts
    storage_accounts=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    if [[ -z "$storage_accounts" ]]; then
        print_info "No Storage Accounts found in resource group"
        return 0
    fi
    
    for storage_account in $storage_accounts; do
        print_warning "Deleting Storage Account: $storage_account"
        print_warning "All stored data including audit archives will be permanently lost!"
        
        # Delete the Storage Account
        az storage account delete --name "$storage_account" --resource-group "$RESOURCE_GROUP" --yes --output none
        
        print_success "Storage Account '$storage_account' deleted"
    done
}

# Function to delete resource group
delete_resource_group() {
    print_info "Deleting resource group: $RESOURCE_GROUP"
    
    # Double-check that resource group exists
    if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_warning "Resource group '$RESOURCE_GROUP' does not exist"
        return 0
    fi
    
    print_info "Initiating resource group deletion (this may take several minutes)..."
    
    # Delete the resource group and all its resources
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none
    
    print_success "Resource group deletion initiated: $RESOURCE_GROUP"
    
    # Optionally wait for completion
    read -p "Wait for deletion to complete? (y/n): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Waiting for resource group deletion to complete..."
        
        local timeout_counter=0
        while az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; do
            if [[ $timeout_counter -ge $DELETION_TIMEOUT ]]; then
                print_warning "Deletion timeout reached. Resource group may still be deleting."
                break
            fi
            
            sleep 30
            timeout_counter=$((timeout_counter + 30))
            print_info "Still deleting... ($timeout_counter/$DELETION_TIMEOUT seconds)"
        done
        
        if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
            print_success "Resource group deletion completed"
        else
            print_warning "Resource group deletion is still in progress"
        fi
    else
        print_info "Resource group deletion is running in the background"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    print_info "Cleaning up local files..."
    
    # Clean up any temporary files that might have been created
    local temp_files=("test-audit.json" "*.tmp" "*.temp")
    
    for pattern in "${temp_files[@]}"; do
        if compgen -G "$pattern" > /dev/null; then
            rm -f $pattern
            print_info "Removed temporary files: $pattern"
        fi
    done
    
    print_success "Local cleanup completed"
}

# Function to verify deletion
verify_deletion() {
    print_info "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_warning "Resource group '$RESOURCE_GROUP' still exists"
        print_info "This is normal if deletion is still in progress"
        print_info "You can check status with: az group show --name '$RESOURCE_GROUP'"
    else
        print_success "Resource group '$RESOURCE_GROUP' has been deleted"
    fi
    
    # Check for any remaining resources (in case of partial deletion)
    local remaining_resources
    remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
    
    if [[ "$remaining_resources" -gt 0 ]]; then
        print_warning "Some resources may still exist during deletion process"
        print_info "Remaining resources: $remaining_resources"
    fi
}

# Function to print deletion summary
print_deletion_summary() {
    print_info "=== DELETION SUMMARY ==="
    print_info "Resource Group: $RESOURCE_GROUP"
    print_info "Status: Deletion initiated"
    print_info "Log file: $LOG_FILE"
    print_info "========================"
    print_success "Destruction process completed!"
    print_info "Note: Some resources may take additional time to be fully removed"
    print_info "Azure may retain some data for compliance and billing purposes"
}

# Main destruction function
main() {
    local start_time
    start_time=$(date +%s)
    
    print_info "Starting destruction of Azure Confidential Ledger Audit Trail Solution"
    print_info "Script: $SCRIPT_NAME"
    print_info "Log file: $LOG_FILE"
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Execute destruction steps
    check_prerequisites
    discover_resources
    
    # List resources before deletion
    if ! list_resources; then
        print_info "No resources to delete"
        exit 0
    fi
    
    # Confirm destruction
    confirm_destruction
    
    # Handle special resources that need specific deletion procedures
    handle_keyvault_deletion
    handle_confidential_ledger_deletion
    handle_storage_deletion
    
    # Delete the entire resource group
    delete_resource_group
    
    # Clean up local files
    cleanup_local_files
    
    # Verify deletion
    verify_deletion
    
    # Print summary
    print_deletion_summary
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_success "Total destruction time: $duration seconds"
}

# Execute main function
main "$@"