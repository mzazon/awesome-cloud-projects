#!/bin/bash

# Azure Service Status Page Cleanup Script
# Recipe: Simple Service Status Page with Static Web Apps and Functions
# Version: 1.1
# Last Updated: 2025-07-12

set -euo pipefail
IFS=$'\n\t'

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show --output none 2>/dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites met"
}

# Load deployment information from file
load_deployment_info() {
    local deployment_info_file=""
    local search_paths=(
        "/tmp/status-page-*/deployment_info.txt"
        "./deployment_info.txt"
        "../deployment_info.txt"
        "../../deployment_info.txt"
    )
    
    # Try to find deployment info file
    for path in "${search_paths[@]}"; do
        # Use glob expansion to find files matching pattern
        for file in $path; do
            if [[ -f "$file" ]]; then
                deployment_info_file="$file"
                break 2
            fi
        done
    done
    
    if [[ -n "$deployment_info_file" ]]; then
        log_info "Loading deployment information from: $deployment_info_file"
        # shellcheck source=/dev/null
        source "$deployment_info_file"
        
        log_info "Loaded deployment information:"
        log_info "  Resource Group: ${RESOURCE_GROUP:-<not set>}"
        log_info "  Static Web App: ${STATIC_WEB_APP_NAME:-<not set>}"
        log_info "  Location: ${LOCATION:-<not set>}"
        log_info "  Deployment Date: ${DEPLOYMENT_DATE:-<not set>}"
        
        return 0
    else
        log_warning "No deployment info file found. Will proceed with manual input."
        return 1
    fi
}

# Manual input for resource information
get_manual_input() {
    log_info "Please provide the resource information manually:"
    
    # Get resource group name
    while [[ -z "${RESOURCE_GROUP:-}" ]]; do
        read -rp "Enter Resource Group name: " RESOURCE_GROUP
        if [[ -z "$RESOURCE_GROUP" ]]; then
            log_warning "Resource Group name cannot be empty"
        fi
    done
    
    # Get Static Web App name (optional - can delete entire resource group)
    read -rp "Enter Static Web App name (optional, leave empty to skip): " STATIC_WEB_APP_NAME
    
    export RESOURCE_GROUP
    export STATIC_WEB_APP_NAME
}

# List resources in resource group
list_resources() {
    log_info "Listing resources in resource group: ${RESOURCE_GROUP}"
    
    if ! az group show --name "${RESOURCE_GROUP}" --output none 2>/dev/null; then
        log_warning "Resource group '${RESOURCE_GROUP}' does not exist or is not accessible"
        return 1
    fi
    
    local resources
    resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null || true)
    
    if [[ -n "$resources" ]]; then
        echo
        log_info "Resources found in ${RESOURCE_GROUP}:"
        echo "$resources"
        echo
    else
        log_info "No resources found in resource group: ${RESOURCE_GROUP}"
    fi
}

# Confirmation prompt
confirm_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    
    echo
    log_warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    log_warning "This will permanently delete the following resources:"
    
    if [[ "$resource_type" == "resource-group" ]]; then
        log_warning "  🗂️  Resource Group: ${resource_name}"
        log_warning "  📦 ALL resources within the resource group"
        echo
        log_warning "This action cannot be undone and will delete:"
        log_warning "  - Static Web Apps"
        log_warning "  - Azure Functions"
        log_warning "  - All associated configurations"
        log_warning "  - Any other resources in this resource group"
    else
        log_warning "  🌐 Static Web App: ${resource_name}"
        log_warning "  ⚡ Associated Azure Functions"
    fi
    
    echo
    read -rp "Are you sure you want to continue? Type 'yes' to confirm: " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    log_info "Proceeding with cleanup..."
}

# Delete specific Static Web App
delete_static_web_app() {
    if [[ -z "${STATIC_WEB_APP_NAME:-}" ]]; then
        log_info "No Static Web App name provided, skipping individual app deletion"
        return 0
    fi
    
    log_info "Checking if Static Web App exists: ${STATIC_WEB_APP_NAME}"
    
    if ! az staticwebapp show --name "${STATIC_WEB_APP_NAME}" --resource-group "${RESOURCE_GROUP}" --output none 2>/dev/null; then
        log_warning "Static Web App '${STATIC_WEB_APP_NAME}' not found"
        return 0
    fi
    
    confirm_deletion "static-web-app" "${STATIC_WEB_APP_NAME}"
    
    log_info "Deleting Static Web App: ${STATIC_WEB_APP_NAME}"
    
    if az staticwebapp delete \
        --name "${STATIC_WEB_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes \
        --output none; then
        log_success "Static Web App deleted: ${STATIC_WEB_APP_NAME}"
    else
        log_error "Failed to delete Static Web App: ${STATIC_WEB_APP_NAME}"
        return 1
    fi
}

# Delete entire resource group
delete_resource_group() {
    log_info "Checking if resource group exists: ${RESOURCE_GROUP}"
    
    if ! az group show --name "${RESOURCE_GROUP}" --output none 2>/dev/null; then
        log_warning "Resource group '${RESOURCE_GROUP}' does not exist"
        return 0
    fi
    
    # List resources before deletion
    list_resources
    
    confirm_deletion "resource-group" "${RESOURCE_GROUP}"
    
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    log_warning "This operation may take several minutes..."
    
    # Start deletion in background
    if az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        --output none; then
        log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        log_info "Deletion is running in the background and may take several minutes to complete"
        
        # Optional: Wait for completion with timeout
        if [[ "${WAIT_FOR_COMPLETION:-}" == "true" ]]; then
            log_info "Waiting for deletion to complete (this may take up to 10 minutes)..."
            local wait_count=0
            local max_wait=60  # 10 minutes (60 * 10 seconds)
            
            while [[ $wait_count -lt $max_wait ]]; do
                if ! az group show --name "${RESOURCE_GROUP}" --output none 2>/dev/null; then
                    log_success "Resource group deletion completed"
                    break
                fi
                
                wait_count=$((wait_count + 1))
                echo -n "."
                sleep 10
            done
            
            if [[ $wait_count -eq $max_wait ]]; then
                log_warning "Deletion is still in progress. Check Azure portal for status."
            fi
        fi
    else
        log_error "Failed to initiate resource group deletion: ${RESOURCE_GROUP}"
        return 1
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Clean up project directories
    local cleanup_paths=(
        "/tmp/status-page-*"
        "${PROJECT_DIR:-}"
    )
    
    for path in "${cleanup_paths[@]}"; do
        if [[ -n "$path" ]] && [[ "$path" != "/" ]]; then
            # Use glob expansion for wildcard paths
            for dir in $path; do
                if [[ -d "$dir" ]]; then
                    log_info "Removing directory: $dir"
                    rm -rf "$dir" || log_warning "Failed to remove directory: $dir"
                fi
            done
        fi
    done
    
    # Optionally uninstall Static Web Apps CLI if it was installed by deploy script
    if command -v swa &> /dev/null && [[ "${UNINSTALL_SWA_CLI:-}" == "true" ]]; then
        log_info "Uninstalling Static Web Apps CLI..."
        npm uninstall -g @azure/static-web-apps-cli || log_warning "Failed to uninstall SWA CLI"
    fi
    
    log_success "Local cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" --output none 2>/dev/null; then
        log_warning "Resource group still exists (deletion may be in progress): ${RESOURCE_GROUP}"
        log_info "You can check deletion status with: az group show --name ${RESOURCE_GROUP}"
    else
        log_success "Resource group successfully deleted: ${RESOURCE_GROUP}"
    fi
    
    # Check if Static Web App still exists (if we tried to delete it individually)
    if [[ -n "${STATIC_WEB_APP_NAME:-}" ]]; then
        if az staticwebapp show --name "${STATIC_WEB_APP_NAME}" --resource-group "${RESOURCE_GROUP}" --output none 2>/dev/null; then
            log_warning "Static Web App still exists: ${STATIC_WEB_APP_NAME}"
        else
            log_success "Static Web App successfully deleted: ${STATIC_WEB_APP_NAME}"
        fi
    fi
}

# Main cleanup function
main() {
    local cleanup_mode="${1:-full}"
    
    echo
    log_info "🧹 Starting Azure Service Status Page cleanup..."
    echo
    
    check_prerequisites
    
    # Try to load deployment info, fallback to manual input
    if ! load_deployment_info; then
        get_manual_input
    fi
    
    case "$cleanup_mode" in
        "app-only")
            log_info "Cleanup mode: Static Web App only"
            delete_static_web_app
            ;;
        "full"|*)
            log_info "Cleanup mode: Full resource group deletion"
            delete_resource_group
            ;;
    esac
    
    cleanup_local_files
    verify_cleanup
    
    echo
    log_success "🎉 Cleanup completed!"
    echo
    log_info "💡 Summary:"
    log_info "  - Azure resources have been deleted or deletion initiated"
    log_info "  - Local temporary files have been cleaned up"
    log_info "  - Check Azure portal to verify complete deletion"
    echo
}

# Interactive mode
interactive_cleanup() {
    echo
    log_info "🧹 Interactive Azure Service Status Page cleanup..."
    echo
    
    check_prerequisites
    
    # Try to load deployment info
    if load_deployment_info; then
        echo
        log_info "Select cleanup option:"
        echo "  1) Delete entire resource group (recommended)"
        echo "  2) Delete Static Web App only"
        echo "  3) Cancel cleanup"
        echo
        
        local choice
        read -rp "Enter your choice (1-3): " choice
        
        case "$choice" in
            1)
                main "full"
                ;;
            2)
                main "app-only"
                ;;
            3)
                log_info "Cleanup cancelled"
                exit 0
                ;;
            *)
                log_error "Invalid choice. Please run the script again."
                exit 1
                ;;
        esac
    else
        # No deployment info found, get manual input
        get_manual_input
        main "full"
    fi
}

# Help function
show_help() {
    echo "Azure Service Status Page Cleanup Script"
    echo
    echo "Usage: $0 [OPTIONS] [MODE]"
    echo
    echo "Modes:"
    echo "  full         Delete entire resource group (default)"
    echo "  app-only     Delete only the Static Web App"
    echo
    echo "Options:"
    echo "  --interactive, -i    Run in interactive mode"
    echo "  --wait              Wait for deletion to complete"
    echo "  --uninstall-cli     Uninstall Static Web Apps CLI"
    echo "  --help, -h          Show this help message"
    echo
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP      Resource group name (overrides auto-detection)"
    echo "  STATIC_WEB_APP_NAME Static Web App name (overrides auto-detection)"
    echo "  WAIT_FOR_COMPLETION Set to 'true' to wait for deletion completion"
    echo "  UNINSTALL_SWA_CLI   Set to 'true' to uninstall SWA CLI"
    echo
    echo "Examples:"
    echo "  $0                          # Full cleanup with auto-detection"
    echo "  $0 app-only                 # Delete only Static Web App"
    echo "  $0 --interactive            # Interactive mode"
    echo "  $0 --wait full              # Full cleanup and wait for completion"
    echo "  RESOURCE_GROUP=my-rg $0     # Cleanup specific resource group"
    echo
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --interactive|-i)
            interactive_cleanup
            exit 0
            ;;
        --wait)
            export WAIT_FOR_COMPLETION="true"
            shift
            ;;
        --uninstall-cli)
            export UNINSTALL_SWA_CLI="true"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        full|app-only)
            CLEANUP_MODE="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Execute main function with specified mode
main "${CLEANUP_MODE:-full}"