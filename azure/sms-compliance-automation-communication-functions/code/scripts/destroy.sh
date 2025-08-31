#!/bin/bash

# SMS Compliance Automation with Communication Services - Cleanup Script
# This script safely removes all Azure resources created for the SMS compliance solution
# including Communication Services, Azure Functions, Storage Account, and Resource Group.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is logged into Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed successfully"
}

# Function to discover resources by tags or naming patterns
discover_resources() {
    log_info "Discovering SMS compliance resources..."
    
    # Find resource groups with SMS compliance pattern
    RESOURCE_GROUPS=$(az group list --query "[?starts_with(name, 'rg-sms-compliance-')].name" --output tsv 2>/dev/null || echo "")
    
    if [ -z "${RESOURCE_GROUPS}" ]; then
        # Also check for tagged resources if no naming pattern matches
        TAGGED_GROUPS=$(az group list --tag purpose=sms-compliance --query "[].name" --output tsv 2>/dev/null || echo "")
        RESOURCE_GROUPS="${TAGGED_GROUPS}"
    fi
    
    if [ -z "${RESOURCE_GROUPS}" ]; then
        log_warning "No SMS compliance resource groups found using standard naming patterns or tags"
        return 1
    fi
    
    log_info "Found resource groups: ${RESOURCE_GROUPS}"
    return 0
}

# Function to prompt for resource group selection if multiple found
select_resource_group() {
    local groups=($RESOURCE_GROUPS)
    
    if [ ${#groups[@]} -eq 1 ]; then
        SELECTED_RESOURCE_GROUP="${groups[0]}"
        log_info "Using resource group: ${SELECTED_RESOURCE_GROUP}"
        return 0
    fi
    
    echo ""
    log_info "Multiple SMS compliance resource groups found:"
    for i in "${!groups[@]}"; do
        echo "$((i+1)). ${groups[i]}"
    done
    echo ""
    
    while true; do
        read -p "Select resource group to delete (1-${#groups[@]}), or 'all' to delete all, or 'q' to quit: " choice
        
        if [ "${choice}" = "q" ] || [ "${choice}" = "Q" ]; then
            log_info "Cleanup cancelled by user"
            exit 0
        elif [ "${choice}" = "all" ] || [ "${choice}" = "ALL" ]; then
            SELECTED_RESOURCE_GROUP="ALL"
            return 0
        elif [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le ${#groups[@]} ]; then
            SELECTED_RESOURCE_GROUP="${groups[$((choice-1))]}"
            log_info "Selected resource group: ${SELECTED_RESOURCE_GROUP}"
            return 0
        else
            log_warning "Invalid selection. Please try again."
        fi
    done
}

# Function to list resources in a resource group
list_resources_in_group() {
    local resource_group="$1"
    
    log_info "Resources in ${resource_group}:"
    az resource list --resource-group "${resource_group}" \
        --query "[].{Name:name, Type:type, Location:location}" \
        --output table 2>/dev/null || {
        log_warning "Could not list resources in ${resource_group}"
        return 1
    }
    
    return 0
}

# Function to confirm deletion
confirm_deletion() {
    local resource_group="$1"
    
    echo ""
    log_warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo "=================================================="
    echo "This will permanently delete ALL resources in:"
    echo "Resource Group: ${resource_group}"
    echo ""
    
    # List resources to be deleted
    list_resources_in_group "${resource_group}"
    
    echo ""
    echo "=================================================="
    log_warning "This action cannot be undone!"
    echo ""
    
    # Require explicit confirmation
    while true; do
        read -p "Are you absolutely sure you want to delete these resources? (yes/no): " confirm
        case $confirm in
            [Yy][Ee][Ss])
                return 0
                ;;
            [Nn][Oo])
                log_info "Deletion cancelled by user"
                return 1
                ;;
            *)
                log_warning "Please answer 'yes' or 'no'"
                ;;
        esac
    done
}

# Function to delete Function App and Storage Account first
delete_function_resources() {
    local resource_group="$1"
    
    log_info "Identifying Function Apps and Storage Accounts in ${resource_group}..."
    
    # Find Function Apps
    local function_apps=$(az functionapp list --resource-group "${resource_group}" \
        --query "[].name" --output tsv 2>/dev/null || echo "")
    
    # Find Storage Accounts
    local storage_accounts=$(az storage account list --resource-group "${resource_group}" \
        --query "[].name" --output tsv 2>/dev/null || echo "")
    
    # Delete Function Apps first
    if [ -n "${function_apps}" ]; then
        for app in ${function_apps}; do
            log_info "Deleting Function App: ${app}"
            az functionapp delete \
                --name "${app}" \
                --resource-group "${resource_group}" \
                --yes \
                --output none 2>/dev/null || {
                log_warning "Failed to delete Function App: ${app}"
            }
            
            if [ $? -eq 0 ]; then
                log_success "Function App deleted: ${app}"
            fi
        done
    fi
    
    # Delete Storage Accounts
    if [ -n "${storage_accounts}" ]; then
        for account in ${storage_accounts}; do
            log_info "Deleting Storage Account: ${account}"
            az storage account delete \
                --name "${account}" \
                --resource-group "${resource_group}" \
                --yes \
                --output none 2>/dev/null || {
                log_warning "Failed to delete Storage Account: ${account}"
            }
            
            if [ $? -eq 0 ]; then
                log_success "Storage Account deleted: ${account}"
            fi
        done
    fi
}

# Function to delete Communication Services resources
delete_communication_services() {
    local resource_group="$1"
    
    log_info "Identifying Communication Services resources in ${resource_group}..."
    
    # Find Communication Services resources
    local comm_services=$(az communication list --resource-group "${resource_group}" \
        --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [ -n "${comm_services}" ]; then
        for service in ${comm_services}; do
            log_info "Deleting Communication Services resource: ${service}"
            az communication delete \
                --name "${service}" \
                --resource-group "${resource_group}" \
                --yes \
                --output none 2>/dev/null || {
                log_warning "Failed to delete Communication Services resource: ${service}"
            }
            
            if [ $? -eq 0 ]; then
                log_success "Communication Services resource deleted: ${service}"
            fi
        done
    fi
}

# Function to delete a single resource group
delete_resource_group() {
    local resource_group="$1"
    
    log_info "Starting cleanup of resource group: ${resource_group}"
    
    # Check if resource group exists
    if ! az group exists --name "${resource_group}" --output tsv 2>/dev/null; then
        log_warning "Resource group ${resource_group} does not exist"
        return 0
    fi
    
    # Confirm deletion
    if ! confirm_deletion "${resource_group}"; then
        log_info "Deletion cancelled for ${resource_group}"
        return 0
    fi
    
    # Delete Function Apps and Storage Accounts first (order matters for dependencies)
    delete_function_resources "${resource_group}"
    
    # Wait a moment for propagation
    sleep 5
    
    # Delete Communication Services resources
    delete_communication_services "${resource_group}"
    
    # Wait a moment for propagation
    sleep 5
    
    # Delete the entire resource group and all remaining resources
    log_info "Deleting resource group and all remaining resources: ${resource_group}"
    az group delete \
        --name "${resource_group}" \
        --yes \
        --no-wait \
        --output none
    
    if [ $? -eq 0 ]; then
        log_success "Resource group deletion initiated: ${resource_group}"
        log_info "Note: Complete deletion may take several minutes"
        
        # Optionally wait for deletion to complete
        if [ "${WAIT_FOR_COMPLETION:-false}" = "true" ]; then
            log_info "Waiting for deletion to complete..."
            while az group exists --name "${resource_group}" --output tsv 2>/dev/null; do
                echo -n "."
                sleep 10
            done
            echo ""
            log_success "Resource group ${resource_group} deleted completely"
        fi
    else
        log_error "Failed to initiate deletion of resource group: ${resource_group}"
        return 1
    fi
}

# Function to clean up local temporary files
cleanup_local_files() {
    log_info "Cleaning up local temporary files..."
    
    # Remove any temporary function directories that might exist
    if [ -d "./sms-compliance-functions" ]; then
        rm -rf "./sms-compliance-functions"
        log_success "Temporary function directory cleaned up"
    fi
    
    # Clean up environment variables
    unset RESOURCE_GROUP 2>/dev/null || true
    unset COMMUNICATION_SERVICE 2>/dev/null || true
    unset FUNCTION_APP 2>/dev/null || true
    unset STORAGE_ACCOUNT 2>/dev/null || true
    unset COMM_CONNECTION_STRING 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

# Function to display cleanup summary
display_summary() {
    echo ""
    log_info "Cleanup Summary:"
    echo "=================================================="
    
    if [ "${SELECTED_RESOURCE_GROUP}" = "ALL" ]; then
        echo "Action: Deleted all SMS compliance resource groups"
        for group in ${RESOURCE_GROUPS}; do
            echo "  - ${group}"
        done
    else
        echo "Action: Deleted resource group ${SELECTED_RESOURCE_GROUP}"
    fi
    
    echo "Status: Deletion initiated successfully"
    echo "Note: Complete deletion may take several minutes"
    echo "=================================================="
    echo ""
    log_success "SMS Compliance Automation resources cleanup completed!"
    echo ""
    log_info "You can verify deletion by checking the Azure Portal or running:"
    echo "az group list --query \"[?starts_with(name, 'rg-sms-compliance-')].name\" --output table"
}

# Main cleanup function
main() {
    log_info "Starting SMS Compliance Automation cleanup..."
    echo "=================================================="
    
    # Check prerequisites
    check_prerequisites
    
    # Discover resources
    if ! discover_resources; then
        log_info "No resources found to clean up. Exiting gracefully."
        exit 0
    fi
    
    # Select resource group(s) to delete
    select_resource_group
    
    # Delete selected resource group(s)
    if [ "${SELECTED_RESOURCE_GROUP}" = "ALL" ]; then
        for group in ${RESOURCE_GROUPS}; do
            delete_resource_group "${group}"
        done
    else
        delete_resource_group "${SELECTED_RESOURCE_GROUP}"
    fi
    
    # Clean up local files
    cleanup_local_files
    
    # Display summary
    display_summary
    
    log_success "SMS Compliance Automation cleanup completed successfully!"
}

# Function to handle manual resource group specification
handle_manual_resource_group() {
    local manual_rg="$1"
    
    log_info "Using manually specified resource group: ${manual_rg}"
    
    # Check if the resource group exists
    if ! az group exists --name "${manual_rg}" --output tsv 2>/dev/null; then
        log_error "Resource group '${manual_rg}' does not exist"
        exit 1
    fi
    
    SELECTED_RESOURCE_GROUP="${manual_rg}"
    delete_resource_group "${manual_rg}"
    cleanup_local_files
    
    log_success "Manual cleanup completed for resource group: ${manual_rg}"
}

# Handle script interruption
trap 'log_error "Script interrupted. Some resources may still exist."; exit 1' INT TERM

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        echo "SMS Compliance Automation Cleanup Script"
        echo "Usage: $0 [OPTIONS] [RESOURCE_GROUP]"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --wait              Wait for deletion to complete before exiting"
        echo "  --dry-run           Show what would be deleted without actually deleting"
        echo ""
        echo "Arguments:"
        echo "  RESOURCE_GROUP      Specific resource group name to delete"
        echo ""
        echo "Examples:"
        echo "  $0                           # Interactive mode - discover and select resources"
        echo "  $0 rg-sms-compliance-abc123  # Delete specific resource group"
        echo "  $0 --wait                    # Wait for deletion to complete"
        echo "  $0 --dry-run                 # Preview what would be deleted"
        exit 0
        ;;
    --wait)
        export WAIT_FOR_COMPLETION=true
        main
        ;;
    --dry-run)
        log_info "DRY RUN MODE - No resources will be deleted"
        check_prerequisites
        if discover_resources; then
            for group in ${RESOURCE_GROUPS}; do
                echo ""
                log_info "Would delete resource group: ${group}"
                list_resources_in_group "${group}"
            done
        fi
        log_info "Dry run completed. No resources were deleted."
        exit 0
        ;;
    rg-*)
        handle_manual_resource_group "$1"
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac