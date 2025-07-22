#!/bin/bash

# =============================================================================
# Destroy Script for Intelligent Document Processing with Azure AI Document Intelligence and Logic Apps
# =============================================================================
#
# This script safely removes all resources created by the deployment script
# for the intelligent document processing solution.
#
# Prerequisites:
# - Azure CLI installed and configured
# - Appropriate Azure subscription permissions
# - bash shell environment
#
# Usage:
#   chmod +x destroy.sh
#   ./destroy.sh
#
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# Configuration and Variables
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Cleanup configuration
CLEANUP_NAME="docprocessing-cleanup-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="destroy-$(date +%Y%m%d-%H%M%S).log"

# =============================================================================
# Helper Functions
# =============================================================================

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

# Error logging function
error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Success logging function
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

# Warning logging function
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate Azure CLI is logged in
validate_azure_cli() {
    log "Validating Azure CLI authentication..."
    
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    if ! az account show >/dev/null 2>&1; then
        error "Azure CLI is not logged in. Please run 'az login' first."
        exit 1
    fi
    
    # Get account info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    ACCOUNT_NAME=$(az account show --query name --output tsv)
    
    log "Using Azure subscription: $ACCOUNT_NAME ($SUBSCRIPTION_ID)"
}

# Function to list resource groups with document processing pattern
list_resource_groups() {
    log "Scanning for document processing resource groups..."
    
    # Find resource groups that match our naming pattern
    RESOURCE_GROUPS=$(az group list --query "[?contains(name, 'rg-docprocessing-')].name" --output tsv)
    
    if [ -z "$RESOURCE_GROUPS" ]; then
        warning "No document processing resource groups found matching pattern 'rg-docprocessing-*'"
        return 1
    fi
    
    log "Found the following resource groups:"
    echo "$RESOURCE_GROUPS" | while read -r rg; do
        log "  - $rg"
    done
    
    return 0
}

# Function to display resource group details
display_resource_group_details() {
    local rg_name=$1
    
    log "Resource Group: $rg_name"
    log "Resources in this group:"
    
    # List resources in the group
    az resource list --resource-group "$rg_name" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null || {
        warning "Could not list resources in $rg_name"
        return 1
    }
    
    # Get resource group tags
    local tags=$(az group show --name "$rg_name" --query "tags" --output json 2>/dev/null)
    if [ "$tags" != "null" ] && [ -n "$tags" ]; then
        log "Resource Group Tags: $tags"
    fi
}

# Function to prompt for confirmation
prompt_confirmation() {
    local rg_name=$1
    
    echo
    warning "⚠️  WARNING: This will permanently delete all resources in resource group: $rg_name"
    warning "⚠️  This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log "Cleanup cancelled by user."
        return 1
    fi
    
    return 0
}

# Function to delete resource group with safety checks
delete_resource_group() {
    local rg_name=$1
    
    log "Initiating deletion of resource group: $rg_name"
    
    # Check if resource group exists
    if ! az group show --name "$rg_name" >/dev/null 2>&1; then
        warning "Resource group $rg_name does not exist or is already deleted."
        return 0
    fi
    
    # Display resource group details
    display_resource_group_details "$rg_name"
    
    # Prompt for confirmation
    if ! prompt_confirmation "$rg_name"; then
        return 1
    fi
    
    # Delete resource group
    log "Deleting resource group: $rg_name (this may take several minutes)..."
    
    az group delete \
        --name "$rg_name" \
        --yes \
        --no-wait
    
    success "Resource group deletion initiated: $rg_name"
    
    return 0
}

# Function to wait for deletion completion
wait_for_deletion() {
    local rg_name=$1
    
    log "Waiting for resource group deletion to complete: $rg_name"
    
    local max_attempts=60  # 30 minutes maximum wait time
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if ! az group show --name "$rg_name" >/dev/null 2>&1; then
            success "Resource group $rg_name has been successfully deleted."
            return 0
        fi
        
        log "Deletion in progress... (attempt $((attempt + 1))/$max_attempts)"
        sleep 30
        attempt=$((attempt + 1))
    done
    
    warning "Deletion is taking longer than expected. Check Azure Portal for status."
    return 1
}

# Function to verify cleanup
verify_cleanup() {
    local rg_name=$1
    
    log "Verifying cleanup for resource group: $rg_name"
    
    if az group show --name "$rg_name" >/dev/null 2>&1; then
        warning "Resource group $rg_name still exists. Deletion may be in progress."
        log "Check Azure Portal for current status: https://portal.azure.com"
        return 1
    else
        success "Resource group $rg_name has been completely removed."
        return 0
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove any temporary files that might have been created
    local temp_files=("sample-invoice.txt" "workflow-definition.json")
    
    for file in "${temp_files[@]}"; do
        if [ -f "$file" ]; then
            rm "$file"
            log "Removed local file: $file"
        fi
    done
    
    success "Local file cleanup completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    log "================"
    log "Cleanup operation: $CLEANUP_NAME"
    log "Log file: $LOG_FILE"
    log ""
    log "What was cleaned up:"
    log "- Resource groups matching 'rg-docprocessing-*' pattern"
    log "- All resources within those groups including:"
    log "  • Storage accounts and containers"
    log "  • Key Vault and secrets"
    log "  • Document Intelligence services"
    log "  • Logic Apps and API connections"
    log "  • Service Bus namespaces and queues"
    log "- Local temporary files"
    log ""
    log "Note: It may take up to 30 minutes for all resources to be fully removed."
    log "You can monitor the deletion progress in the Azure Portal."
}

# Function to handle interactive mode
interactive_mode() {
    log "Starting interactive cleanup mode..."
    
    if ! list_resource_groups; then
        log "No resource groups found. Exiting."
        exit 0
    fi
    
    echo
    log "Select resource groups to delete:"
    
    # Convert to array for easier handling
    local rg_array=()
    while IFS= read -r line; do
        rg_array+=("$line")
    done < <(az group list --query "[?contains(name, 'rg-docprocessing-')].name" --output tsv)
    
    # Display numbered list
    for i in "${!rg_array[@]}"; do
        printf "%d) %s\n" $((i + 1)) "${rg_array[$i]}"
    done
    printf "%d) Delete all resource groups\n" $((${#rg_array[@]} + 1))
    printf "%d) Cancel\n" $((${#rg_array[@]} + 2))
    
    echo
    read -p "Enter your choice (1-$((${#rg_array[@]} + 2))): " choice
    
    case $choice in
        $((${#rg_array[@]} + 1)))
            # Delete all
            for rg in "${rg_array[@]}"; do
                delete_resource_group "$rg"
            done
            ;;
        $((${#rg_array[@]} + 2)))
            # Cancel
            log "Cleanup cancelled by user."
            exit 0
            ;;
        *)
            # Delete specific resource group
            if [[ "$choice" -ge 1 && "$choice" -le ${#rg_array[@]} ]]; then
                local selected_rg="${rg_array[$((choice - 1))]}"
                delete_resource_group "$selected_rg"
            else
                error "Invalid choice. Please run the script again."
                exit 1
            fi
            ;;
    esac
}

# Function to handle resource group parameter
handle_resource_group_parameter() {
    local rg_name=$1
    
    log "Attempting to delete specific resource group: $rg_name"
    
    # Validate resource group name pattern
    if [[ ! "$rg_name" =~ ^rg-docprocessing- ]]; then
        warning "Resource group name '$rg_name' does not match expected pattern 'rg-docprocessing-*'"
        read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
        if [ "$confirm" != "yes" ]; then
            log "Cleanup cancelled by user."
            exit 0
        fi
    fi
    
    delete_resource_group "$rg_name"
}

# Function to display usage information
display_usage() {
    echo "Usage: $0 [OPTIONS] [RESOURCE_GROUP]"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -i, --interactive  Run in interactive mode (default)"
    echo "  -f, --force    Skip confirmation prompts (use with caution)"
    echo "  -w, --wait     Wait for deletion to complete"
    echo "  -q, --quiet    Suppress non-essential output"
    echo
    echo "Arguments:"
    echo "  RESOURCE_GROUP  Specific resource group to delete (optional)"
    echo
    echo "Examples:"
    echo "  $0                              # Interactive mode"
    echo "  $0 rg-docprocessing-abc123      # Delete specific resource group"
    echo "  $0 -f -w rg-docprocessing-abc123 # Force delete and wait"
}

# =============================================================================
# Main Cleanup Function
# =============================================================================

main() {
    log "Starting cleanup of Intelligent Document Processing solution..."
    log "Cleanup name: $CLEANUP_NAME"
    log "Log file: $LOG_FILE"
    
    # Parse command line arguments
    local resource_group=""
    local interactive=true
    local force=false
    local wait=false
    local quiet=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                display_usage
                exit 0
                ;;
            -i|--interactive)
                interactive=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -w|--wait)
                wait=true
                shift
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            -*)
                error "Unknown option: $1"
                display_usage
                exit 1
                ;;
            *)
                resource_group="$1"
                interactive=false
                shift
                ;;
        esac
    done
    
    # Validate Azure CLI
    validate_azure_cli
    
    # Execute cleanup based on parameters
    if [ -n "$resource_group" ]; then
        handle_resource_group_parameter "$resource_group"
    else
        interactive_mode
    fi
    
    # Wait for deletion if requested
    if [ "$wait" = true ]; then
        if [ -n "$resource_group" ]; then
            wait_for_deletion "$resource_group"
        else
            # In interactive mode, wait for all deleted resource groups
            for rg in $(az group list --query "[?contains(name, 'rg-docprocessing-')].name" --output tsv 2>/dev/null || echo ""); do
                wait_for_deletion "$rg"
            done
        fi
    fi
    
    # Clean up local files
    cleanup_local_files
    
    success "Cleanup completed successfully!"
    display_cleanup_summary
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi