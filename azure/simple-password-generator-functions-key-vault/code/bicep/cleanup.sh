#!/bin/bash

# ============================================================================
# Azure Bicep Cleanup Script: Simple Password Generator
# ============================================================================
# This script safely removes all resources created by the password generator
# deployment with proper confirmation and logging.

set -e  # Exit on any error

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_RESOURCE_GROUP="rg-password-generator"

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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        print_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    print_success "Prerequisites check completed"
}

# Function to get resource group name
get_resource_group() {
    echo
    read -p "Resource Group Name to delete [$DEFAULT_RESOURCE_GROUP]: " RESOURCE_GROUP
    RESOURCE_GROUP=${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}
    
    # Verify resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_error "Resource group '$RESOURCE_GROUP' does not exist."
        exit 1
    fi
    
    print_success "Found resource group: $RESOURCE_GROUP"
}

# Function to display resources to be deleted
show_resources() {
    print_status "Resources in resource group '$RESOURCE_GROUP':"
    echo
    
    # Get resource list
    RESOURCES=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].{Name:name, Type:type, Location:location}' \
        --output table)
    
    if [[ -z "$RESOURCES" || "$RESOURCES" == "[]" ]]; then
        print_warning "No resources found in resource group."
        return
    fi
    
    echo "$RESOURCES"
    echo
    
    # Count resources
    RESOURCE_COUNT=$(az resource list --resource-group "$RESOURCE_GROUP" --query 'length(@)')
    print_status "Total resources to be deleted: $RESOURCE_COUNT"
}

# Function to check for Key Vault with purge protection
check_key_vault_protection() {
    print_status "Checking for Key Vaults with purge protection..."
    
    KEY_VAULTS=$(az keyvault list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[?properties.enablePurgeProtection].{Name:name, PurgeProtection:properties.enablePurgeProtection}' \
        --output table)
    
    if [[ -n "$KEY_VAULTS" && "$KEY_VAULTS" != "[]" ]]; then
        print_warning "Found Key Vaults with purge protection enabled:"
        echo "$KEY_VAULTS"
        echo
        print_warning "These Key Vaults cannot be permanently deleted and will remain in a 'deleted' state."
        print_warning "They can be recovered or purged after the retention period expires."
        echo
    fi
}

# Function to estimate cost savings
estimate_cost_savings() {
    print_status "Estimating monthly cost savings after deletion..."
    
    # This is a rough estimation based on common resource types
    echo "Estimated monthly cost savings:"
    echo "  • Function App (Consumption): ~$0-10/month"
    echo "  • Key Vault: ~$0.03/10k transactions + $3/month for HSM operations"
    echo "  • Storage Account: ~$0.02-0.05/GB"
    echo "  • Application Insights: ~$2.30/GB"
    echo "  • Log Analytics: ~$2.30/GB"
    echo
    print_status "Total estimated savings: $5-50/month (varies by usage)"
}

# Function to perform cleanup
perform_cleanup() {
    print_status "Starting resource group deletion..."
    
    # Delete the resource group (this deletes all contained resources)
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    print_success "Resource group deletion initiated"
    print_status "Note: Deletion will continue in the background and may take several minutes to complete"
}

# Function to verify deletion
verify_deletion() {
    print_status "Waiting for deletion to complete..."
    
    # Wait for resource group to be deleted (with timeout)
    TIMEOUT=300  # 5 minutes
    ELAPSED=0
    INTERVAL=10
    
    while [[ $ELAPSED -lt $TIMEOUT ]]; do
        if ! az group exists --name "$RESOURCE_GROUP" 2>/dev/null; then
            print_success "Resource group has been successfully deleted"
            return 0
        fi
        
        print_status "Still deleting... (${ELAPSED}s elapsed)"
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    done
    
    print_warning "Deletion is taking longer than expected but will continue in the background"
    print_status "You can check status with: az group exists --name $RESOURCE_GROUP"
}

# Function to clean up soft-deleted Key Vaults (optional)
cleanup_soft_deleted_vaults() {
    echo
    read -p "Do you want to check for soft-deleted Key Vaults that can be purged? (y/N): " PURGE_VAULTS
    
    if [[ "$PURGE_VAULTS" =~ ^[Yy]$ ]]; then
        print_status "Checking for soft-deleted Key Vaults..."
        
        DELETED_VAULTS=$(az keyvault list-deleted \
            --resource-type vault \
            --query '[?properties.purgeProtectionEnabled==`false`].{Name:name, Location:properties.location, DeletionDate:properties.deletionDate}' \
            --output table 2>/dev/null || true)
        
        if [[ -n "$DELETED_VAULTS" && "$DELETED_VAULTS" != "[]" ]]; then
            echo
            print_status "Soft-deleted Key Vaults (without purge protection):"
            echo "$DELETED_VAULTS"
            echo
            read -p "Do you want to permanently purge these Key Vaults? This cannot be undone! (y/N): " CONFIRM_PURGE
            
            if [[ "$CONFIRM_PURGE" =~ ^[Yy]$ ]]; then
                # Get vault names
                VAULT_NAMES=$(az keyvault list-deleted \
                    --resource-type vault \
                    --query '[?properties.purgeProtectionEnabled==`false`].name' \
                    --output tsv 2>/dev/null || true)
                
                for vault_name in $VAULT_NAMES; do
                    print_status "Purging Key Vault: $vault_name"
                    az keyvault purge --name "$vault_name" --no-wait 2>/dev/null || true
                done
                
                print_success "Purge operations initiated for soft-deleted Key Vaults"
            fi
        else
            print_status "No soft-deleted Key Vaults found that can be purged"
        fi
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    echo
    print_success "Cleanup Summary:"
    echo "✅ Resource group deletion initiated: $RESOURCE_GROUP"
    echo "✅ All contained resources will be removed"
    echo "✅ Billing will stop once deletion completes"
    echo
    print_status "What happens next:"
    echo "• Resource deletion continues in the background"
    echo "• You will stop incurring charges once resources are deleted"
    echo "• Soft-deleted resources may have retention periods"
    echo "• Activity logs will show the deletion events"
    echo
    print_status "To verify complete deletion:"
    echo "  az group exists --name $RESOURCE_GROUP"
    echo "  (should return 'false' when deletion is complete)"
}

# Main execution
main() {
    echo "============================================================================"
    echo "Azure Password Generator - Cleanup Script"
    echo "============================================================================"
    echo
    print_warning "⚠️  WARNING: This script will DELETE all resources in the specified resource group!"
    print_warning "⚠️  This action cannot be undone and will permanently remove all data!"
    echo
    
    check_prerequisites
    get_resource_group
    show_resources
    check_key_vault_protection
    estimate_cost_savings
    
    echo
    print_error "🚨 FINAL CONFIRMATION REQUIRED 🚨"
    echo "You are about to permanently delete:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  All contained resources and data"
    echo
    read -p "Type 'DELETE' in all caps to confirm: " FINAL_CONFIRM
    
    if [[ "$FINAL_CONFIRM" != "DELETE" ]]; then
        print_status "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    print_status "Proceeding with resource deletion..."
    perform_cleanup
    
    # Ask if user wants to wait for completion
    read -p "Wait for deletion to complete? (y/N): " WAIT_FOR_COMPLETION
    if [[ "$WAIT_FOR_COMPLETION" =~ ^[Yy]$ ]]; then
        verify_deletion
    fi
    
    cleanup_soft_deleted_vaults
    show_cleanup_summary
    
    print_success "Cleanup process completed! 🧹"
}

# Handle script interruption
trap 'print_error "Cleanup interrupted by user"; exit 1' INT

# Execute main function
main "$@"