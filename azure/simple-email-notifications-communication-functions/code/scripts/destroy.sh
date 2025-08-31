#!/bin/bash

# Azure Simple Email Notifications Cleanup Script
# This script safely removes all resources created for the email notifications recipe
# Author: Recipe Generator
# Version: 1.0

set -euo pipefail

# Colors for output formatting
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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error_exit "You are not logged into Azure. Please run 'az login' first."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to discover resources from deployment info
discover_resources() {
    log_info "Discovering deployed resources..."
    
    # Try to read from deployment-info.txt if it exists
    if [[ -f "deployment-info.txt" ]]; then
        log_info "Found deployment-info.txt, extracting resource information..."
        
        RESOURCE_GROUP=$(grep "Resource Group:" deployment-info.txt | cut -d' ' -f3 || echo "")
        COMMUNICATION_SERVICE=$(grep "Communication Service:" deployment-info.txt | cut -d' ' -f3 || echo "")
        EMAIL_SERVICE=$(grep "Email Service:" deployment-info.txt | cut -d' ' -f3 || echo "")
        FUNCTION_APP=$(grep "Function App:" deployment-info.txt | cut -d' ' -f3 || echo "")
        STORAGE_ACCOUNT=$(grep "Storage Account:" deployment-info.txt | cut -d' ' -f3 || echo "")
        
        if [[ -n "${RESOURCE_GROUP}" ]]; then
            log_success "Found resource group: ${RESOURCE_GROUP}"
            return 0
        fi
    fi
    
    # If no deployment info file or resource group not found, ask user
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_warning "Could not automatically discover resources"
        echo -n "Please enter the resource group name to delete: "
        read -r RESOURCE_GROUP
        
        if [[ -z "${RESOURCE_GROUP}" ]]; then
            error_exit "Resource group name is required"
        fi
    fi
}

# Function to list resources in the resource group
list_resources() {
    log_info "Listing resources in resource group: ${RESOURCE_GROUP}"
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} does not exist or has already been deleted"
        return 1
    fi
    
    echo ""
    echo "Resources to be deleted:"
    echo "======================="
    az resource list --resource-group "${RESOURCE_GROUP}" --output table
    echo ""
    
    return 0
}

# Function to confirm deletion
confirm_deletion() {
    echo -e "${YELLOW}WARNING: This will permanently delete all resources in the resource group: ${RESOURCE_GROUP}${NC}"
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    echo ""
    
    # Show estimated cost savings
    log_info "Deleting these resources will stop all ongoing charges"
    
    echo ""
    echo -n "Are you sure you want to proceed? (Type 'yes' to confirm): "
    read -r confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    echo -n "Are you absolutely certain? This will delete ALL resources! (Type 'DELETE' to confirm): "
    read -r final_confirmation
    
    if [[ "${final_confirmation}" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to delete individual resources (safer approach)
delete_resources_individually() {
    log_info "Attempting to delete resources individually for safer cleanup..."
    
    # Delete Function App first to stop any running functions
    if [[ -n "${FUNCTION_APP:-}" ]] && az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Deleting Function App: ${FUNCTION_APP}"
        az functionapp delete --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" --yes
        log_success "Function App deleted: ${FUNCTION_APP}"
    fi
    
    # Delete Communication Services email domain
    if [[ -n "${EMAIL_SERVICE:-}" ]] && az communication email show --name "${EMAIL_SERVICE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Deleting Email Communication Service: ${EMAIL_SERVICE}"
        
        # First delete the domain
        if az communication email domain show --domain-name AzureManagedDomain --email-service-name "${EMAIL_SERVICE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_info "Deleting managed domain from email service"
            az communication email domain delete \
                --domain-name AzureManagedDomain \
                --email-service-name "${EMAIL_SERVICE}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes
        fi
        
        # Then delete the email service
        az communication email delete --name "${EMAIL_SERVICE}" --resource-group "${RESOURCE_GROUP}" --yes
        log_success "Email Communication Service deleted: ${EMAIL_SERVICE}"
    fi
    
    # Delete Communication Services resource
    if [[ -n "${COMMUNICATION_SERVICE:-}" ]] && az communication show --name "${COMMUNICATION_SERVICE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Deleting Communication Services resource: ${COMMUNICATION_SERVICE}"
        az communication delete --name "${COMMUNICATION_SERVICE}" --resource-group "${RESOURCE_GROUP}" --yes
        log_success "Communication Services resource deleted: ${COMMUNICATION_SERVICE}"
    fi
    
    # Delete Storage Account
    if [[ -n "${STORAGE_ACCOUNT:-}" ]] && az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Deleting Storage Account: ${STORAGE_ACCOUNT}"
        az storage account delete --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --yes
        log_success "Storage Account deleted: ${STORAGE_ACCOUNT}"
    fi
    
    # Wait a bit for resources to be fully deleted
    log_info "Waiting for individual resource deletions to complete..."
    sleep 30
}

# Function to delete resource group
delete_resource_group() {
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} does not exist"
        return 0
    fi
    
    # Delete the resource group (this will delete all remaining resources)
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Note: Complete deletion may take several minutes"
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    # Wait a bit for deletion to process
    sleep 10
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group still exists (deletion in progress)"
        log_info "You can check deletion status with: az group show --name ${RESOURCE_GROUP}"
    else
        log_success "Resource group successfully deleted: ${RESOURCE_GROUP}"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment info file
    if [[ -f "deployment-info.txt" ]]; then
        rm -f deployment-info.txt
        log_success "Removed deployment-info.txt"
    fi
    
    # Remove any function deployment packages
    if [[ -f "function-deployment.zip" ]]; then
        rm -f function-deployment.zip
        log_success "Removed function-deployment.zip"
    fi
    
    # Remove any temporary directories that might have been left
    if [[ -d "email-function" ]]; then
        rm -rf email-function
        log_success "Removed email-function directory"
    fi
}

# Function to show cost impact
show_cost_impact() {
    log_info "Cost Impact Information:"
    echo "========================"
    echo "• Azure Functions (Consumption): Charges stopped immediately"
    echo "• Azure Communication Services: Charges for active email operations stopped"
    echo "• Storage Account: Minimal storage charges stopped"
    echo "• Resource Group: No direct charges (container for resources)"
    echo ""
    log_success "All ongoing charges have been stopped"
}

# Function to provide cleanup summary
show_cleanup_summary() {
    log_success "Cleanup Summary:"
    echo "================"
    echo "✅ All Azure resources deleted"
    echo "✅ Local deployment files removed"
    echo "✅ No ongoing charges"
    echo ""
    log_info "If you deployed using Infrastructure as Code (Terraform/Bicep),"
    log_info "make sure to also run the appropriate IaC cleanup commands."
}

# Function to handle different cleanup modes
handle_cleanup_mode() {
    local mode="${1:-interactive}"
    
    case "${mode}" in
        "--force"|"-f")
            log_warning "Force mode enabled - skipping confirmations"
            ;;
        "--dry-run"|"-d")
            log_info "Dry run mode - showing what would be deleted"
            list_resources
            log_info "Dry run completed. No resources were deleted."
            exit 0
            ;;
        "--help"|"-h")
            show_help
            exit 0
            ;;
        *)
            # Interactive mode (default)
            ;;
    esac
}

# Function to show help
show_help() {
    echo "Azure Simple Email Notifications Cleanup Script"
    echo "==============================================="
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force, -f      Skip confirmation prompts (use with caution)"
    echo "  --dry-run, -d    Show what would be deleted without actually deleting"
    echo "  --help, -h       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive cleanup with confirmations"
    echo "  $0 --dry-run          # Show resources that would be deleted"
    echo "  $0 --force            # Force cleanup without confirmations"
    echo ""
    echo "Note: This script will delete ALL resources in the specified resource group."
    echo "Make sure you have the correct resource group before proceeding."
}

# Main cleanup function
main() {
    local mode="${1:-}"
    
    log_info "Starting Azure Simple Email Notifications cleanup..."
    
    handle_cleanup_mode "${mode}"
    check_prerequisites
    discover_resources
    
    if ! list_resources; then
        log_info "No resources found to delete"
        exit 0
    fi
    
    # Skip confirmation in force mode
    if [[ "${mode}" != "--force" && "${mode}" != "-f" ]]; then
        confirm_deletion
    fi
    
    # Perform cleanup
    delete_resources_individually
    delete_resource_group
    verify_deletion
    cleanup_local_files
    show_cost_impact
    show_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Handle script interruption
trap 'log_warning "Cleanup interrupted by user"; exit 130' INT

# Run main function with all arguments
main "$@"