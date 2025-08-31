#!/bin/bash

# Simple Todo API - Cleanup Script
# This script removes all resources created by the Bicep deployment

set -e  # Exit on any error

# Script configuration
RESOURCE_GROUP=""
SUBSCRIPTION=""
FORCE_DELETE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Simple Todo API Cleanup Script

Usage: $0 [OPTIONS]

Required Options:
  -g, --resource-group    Resource group name to delete

Optional Options:
  -s, --subscription     Azure subscription ID
  -f, --force           Skip confirmation prompts
  -h, --help            Show this help message

Examples:
  # Delete resource group with confirmation
  $0 -g "rg-todo-api"

  # Force delete without confirmation
  $0 -g "rg-todo-api" --force

  # Delete from specific subscription
  $0 -g "rg-todo-api" -s "subscription-id"

EOF
}

# Function to validate prerequisites
validate_prerequisites() {
    print_status "Validating prerequisites..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    print_success "Prerequisites validated"
}

# Function to validate parameters
validate_parameters() {
    print_status "Validating parameters..."

    # Validate required parameters
    if [[ -z "$RESOURCE_GROUP" ]]; then
        print_error "Resource group name is required. Use -g or --resource-group"
        exit 1
    fi

    print_success "Parameters validated"
}

# Function to set subscription
set_subscription() {
    if [[ -n "$SUBSCRIPTION" ]]; then
        print_status "Setting subscription to: $SUBSCRIPTION"
        az account set --subscription "$SUBSCRIPTION"
        print_success "Subscription set"
    fi
}

# Function to check if resource group exists
check_resource_group() {
    print_status "Checking if resource group exists: $RESOURCE_GROUP"
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_warning "Resource group does not exist: $RESOURCE_GROUP"
        print_status "Nothing to clean up."
        exit 0
    fi

    print_success "Resource group found: $RESOURCE_GROUP"
}

# Function to list resources in the group
list_resources() {
    print_status "Resources in resource group '$RESOURCE_GROUP':"
    echo
    
    az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --output table \
        --query "[].{Name:name, Type:type, Location:location}"
    
    echo
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        print_warning "Force delete enabled. Skipping confirmation."
        return 0
    fi

    print_warning "This will permanently delete the resource group and ALL resources within it."
    print_warning "This action cannot be undone."
    echo
    
    read -p "Are you sure you want to delete resource group '$RESOURCE_GROUP'? (yes/no): " -r
    echo
    
    if [[ ! "$REPLY" =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Deletion cancelled by user."
        exit 0
    fi
}

# Function to delete resource group
delete_resource_group() {
    print_status "Deleting resource group: $RESOURCE_GROUP"
    print_warning "This may take several minutes..."
    
    # Start deletion (async by default)
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    print_success "Resource group deletion initiated: $RESOURCE_GROUP"
    print_status "Deletion is running in the background. You can check status with:"
    echo "  az group show --name '$RESOURCE_GROUP'"
    echo
}

# Function to wait for deletion (optional)
wait_for_deletion() {
    print_status "Waiting for deletion to complete..."
    
    local timeout=1800  # 30 minutes timeout
    local elapsed=0
    local check_interval=30
    
    while [[ $elapsed -lt $timeout ]]; do
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            print_success "Resource group deleted successfully!"
            return 0
        fi
        
        print_status "Still deleting... (${elapsed}s elapsed)"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    print_warning "Deletion timeout reached. The resource group may still be deleting."
    print_status "Check deletion status with: az group show --name '$RESOURCE_GROUP'"
}

# Function to verify deletion
verify_deletion() {
    print_status "Verifying deletion..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_warning "Resource group still exists. Deletion may be in progress."
        print_status "Check deletion status with: az group show --name '$RESOURCE_GROUP'"
    else
        print_success "Resource group successfully deleted: $RESOURCE_GROUP"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--subscription)
            SUBSCRIPTION="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        --wait)
            WAIT_FOR_COMPLETION=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    echo "Simple Todo API - Cleanup Script"
    echo "================================"
    echo

    validate_prerequisites
    validate_parameters
    set_subscription
    check_resource_group

    # Show what will be deleted
    list_resources
    
    # Confirm deletion
    confirm_deletion
    
    # Delete resource group
    delete_resource_group
    
    # Wait for completion if requested
    if [[ "$WAIT_FOR_COMPLETION" == "true" ]]; then
        wait_for_deletion
    else
        # Just verify current status
        sleep 5  # Give a moment for the deletion to start
        verify_deletion
    fi
    
    echo
    print_success "Cleanup script completed."
    
    if [[ "$WAIT_FOR_COMPLETION" != "true" ]]; then
        print_status "Note: Deletion may still be in progress. Check Azure portal for final confirmation."
    fi
}

# Run main function
main "$@"