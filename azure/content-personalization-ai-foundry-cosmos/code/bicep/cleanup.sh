#!/bin/bash

# Cleanup script for Content Personalization Engine with AI Foundry and Cosmos
# This script safely removes all deployed resources

set -e  # Exit on any error

# Color codes for output
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

# Function to confirm deletion
confirm_deletion() {
    local resource_group=$1
    
    echo ""
    print_warning "This will permanently delete the following resources:"
    echo "  • Resource Group: $resource_group"
    echo "  • All resources within the resource group including:"
    echo "    - Azure Cosmos DB account and data"
    echo "    - Azure OpenAI service and model deployments"
    echo "    - Azure Functions app and code"
    echo "    - AI Foundry workspace and configurations"
    echo "    - Storage accounts and all stored data"
    echo "    - Application Insights and logged data"
    echo "    - Key Vault and stored secrets"
    echo ""
    print_error "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        print_status "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Please type the resource group name '$resource_group' to confirm: " rg_confirmation
    
    if [[ "$rg_confirmation" != "$resource_group" ]]; then
        print_error "Resource group name doesn't match. Cleanup cancelled for safety."
        exit 1
    fi
}

# Function to list resources before deletion
list_resources() {
    local resource_group=$1
    
    print_status "Resources to be deleted:"
    echo ""
    
    if az resource list --resource-group "$resource_group" --output table --query "[].{Name:name, Type:type, Location:location}" 2>/dev/null; then
        echo ""
    else
        print_warning "Could not list resources or resource group does not exist"
    fi
}

# Function to check for important data
check_important_data() {
    local resource_group=$1
    
    print_status "Checking for important data that will be lost..."
    
    # Check for Cosmos DB data
    local cosmos_accounts=$(az cosmosdb list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "$cosmos_accounts" ]]; then
        print_warning "Cosmos DB accounts found with potentially important data:"
        echo "$cosmos_accounts" | while read -r account; do
            echo "  • $account"
        done
        echo ""
    fi
    
    # Check for Function Apps
    local function_apps=$(az functionapp list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "$function_apps" ]]; then
        print_warning "Function Apps found with potentially important code/configurations:"
        echo "$function_apps" | while read -r app; do
            echo "  • $app"
        done
        echo ""
    fi
    
    # Check for Key Vaults
    local key_vaults=$(az keyvault list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "$key_vaults" ]]; then
        print_warning "Key Vaults found with potentially important secrets:"
        echo "$key_vaults" | while read -r vault; do
            echo "  • $vault"
        done
        echo ""
    fi
}

# Function to perform cleanup
perform_cleanup() {
    local resource_group=$1
    local force_delete=$2
    
    print_status "Starting cleanup process..."
    
    if [[ "$force_delete" == true ]]; then
        print_status "Force delete enabled - skipping individual resource cleanup"
    else
        # Optional: Clean up specific resources first to ensure proper deletion order
        print_status "Cleaning up resources in proper order..."
        
        # Clean up Function Apps first (to avoid dependency issues)
        local function_apps=$(az functionapp list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || echo "")
        if [[ -n "$function_apps" ]]; then
            echo "$function_apps" | while read -r app; do
                if [[ -n "$app" ]]; then
                    print_status "Deleting Function App: $app"
                    az functionapp delete --name "$app" --resource-group "$resource_group" --output none 2>/dev/null || true
                fi
            done
        fi
        
        # Clean up Key Vaults (to avoid soft-delete retention issues)
        local key_vaults=$(az keyvault list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || echo "")
        if [[ -n "$key_vaults" ]]; then
            echo "$key_vaults" | while read -r vault; do
                if [[ -n "$vault" ]]; then
                    print_status "Deleting Key Vault: $vault"
                    az keyvault delete --name "$vault" --resource-group "$resource_group" --output none 2>/dev/null || true
                    # Purge the key vault to avoid retention issues
                    az keyvault purge --name "$vault" --output none 2>/dev/null || true
                fi
            done
        fi
        
        print_status "Individual resource cleanup completed"
    fi
    
    # Delete the entire resource group
    print_status "Deleting resource group: $resource_group"
    print_status "This may take several minutes..."
    
    if az group delete --name "$resource_group" --yes --no-wait --output none; then
        print_success "Resource group deletion initiated"
        print_status "Resources are being deleted in the background"
        print_status "You can check the status in the Azure portal or run:"
        echo "  az group show --name $resource_group"
    else
        print_error "Failed to initiate resource group deletion"
        exit 1
    fi
}

# Function to wait for deletion completion
wait_for_deletion() {
    local resource_group=$1
    local max_wait_minutes=${2:-30}
    local wait_interval=30
    local elapsed_time=0
    
    print_status "Waiting for deletion to complete (max $max_wait_minutes minutes)..."
    
    while [[ $elapsed_time -lt $((max_wait_minutes * 60)) ]]; do
        if ! az group show --name "$resource_group" --output none &> /dev/null; then
            print_success "Resource group '$resource_group' has been successfully deleted"
            return 0
        fi
        
        print_status "Still deleting... ($(($elapsed_time / 60)) minutes elapsed)"
        sleep $wait_interval
        elapsed_time=$((elapsed_time + wait_interval))
    done
    
    print_warning "Deletion is still in progress after $max_wait_minutes minutes"
    print_status "Check Azure portal for current status"
    return 1
}

# Main cleanup function
main() {
    # Default values
    RESOURCE_GROUP=""
    FORCE_DELETE=false
    SKIP_CONFIRMATION=false
    WAIT_FOR_COMPLETION=false
    MAX_WAIT_MINUTES=30
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --wait)
                WAIT_FOR_COMPLETION=true
                shift
                ;;
            --max-wait)
                MAX_WAIT_MINUTES="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  -g, --resource-group    Resource group name to delete (required)"
                echo "  --force                 Skip individual resource cleanup"
                echo "  --yes                   Skip confirmation prompts"
                echo "  --wait                  Wait for deletion to complete"
                echo "  --max-wait              Maximum minutes to wait (default: 30)"
                echo "  -h, --help              Show this help message"
                echo ""
                echo "Example:"
                echo "  $0 -g rg-personalization-demo"
                echo "  $0 -g rg-personalization-demo --yes --wait"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$RESOURCE_GROUP" ]]; then
        print_error "Resource group name is required. Use -g or --resource-group"
        exit 1
    fi
    
    # Check if Azure CLI is available and user is logged in
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed"
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        print_error "You are not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" --output none &> /dev/null; then
        print_error "Resource group '$RESOURCE_GROUP' does not exist"
        exit 1
    fi
    
    # Start cleanup process
    echo "============================================"
    echo "Content Personalization Engine Cleanup"
    echo "============================================"
    echo ""
    
    # List resources
    list_resources "$RESOURCE_GROUP"
    
    # Check for important data
    check_important_data "$RESOURCE_GROUP"
    
    # Confirm deletion unless skipped
    if [[ "$SKIP_CONFIRMATION" != true ]]; then
        confirm_deletion "$RESOURCE_GROUP"
    fi
    
    # Perform cleanup
    perform_cleanup "$RESOURCE_GROUP" "$FORCE_DELETE"
    
    # Wait for completion if requested
    if [[ "$WAIT_FOR_COMPLETION" == true ]]; then
        wait_for_deletion "$RESOURCE_GROUP" "$MAX_WAIT_MINUTES"
    fi
    
    # Final message
    echo ""
    print_success "Cleanup process completed successfully!"
    
    if [[ "$WAIT_FOR_COMPLETION" != true ]]; then
        print_status "Resources are being deleted in the background"
        print_status "Monitor progress in the Azure portal or check with:"
        echo "  az group show --name $RESOURCE_GROUP"
    fi
    
    echo ""
    echo "Thank you for using the Content Personalization Engine!"
}

# Run main function with all arguments
main "$@"