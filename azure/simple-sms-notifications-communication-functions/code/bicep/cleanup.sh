#!/bin/bash

# Cleanup script for Simple SMS Notifications resources
# This script safely removes all resources created by the Bicep template

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if deployment info exists
check_deployment_info() {
    if [ -f "deployment-info.json" ]; then
        print_info "Found deployment info file"
        RESOURCE_GROUP=$(jq -r '.resourceGroup' deployment-info.json)
        COMMUNICATION_SERVICE_NAME=$(jq -r '.communicationServiceName' deployment-info.json)
        FUNCTION_APP_NAME=$(jq -r '.functionAppName' deployment-info.json)
        print_info "Using resources from deployment-info.json"
    else
        print_warning "No deployment-info.json found. Manual input required."
        get_manual_input
    fi
}

# Get manual input if deployment info not available
get_manual_input() {
    read -p "Resource Group name: " RESOURCE_GROUP
    read -p "Communication Service name (optional): " COMMUNICATION_SERVICE_NAME
    read -p "Function App name (optional): " FUNCTION_APP_NAME
    
    if [ -z "$RESOURCE_GROUP" ]; then
        print_error "Resource Group name is required"
        exit 1
    fi
}

# Show resources to be deleted
show_resources() {
    print_info "Checking resources in resource group: $RESOURCE_GROUP"
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_warning "Resource group '$RESOURCE_GROUP' not found"
        exit 0
    fi
    
    # List resources
    echo
    print_info "Resources to be deleted:"
    az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output table
    echo
    
    # Show estimated monthly savings
    print_info "Monthly cost savings after cleanup:"
    echo "  • Function App: \$0 (was pay-per-execution)"
    echo "  • Storage Account: \$1-2"
    echo "  • Phone Number: \$2 (toll-free lease)"
    echo "  • SMS Messages: \$0.0075-0.01 per message"
    echo "  • Application Insights: \$1-5 (if enabled)"
    echo "  • Total savings: ~\$3-7/month + SMS usage"
}

# Release phone number before resource group deletion
release_phone_number() {
    if [ ! -z "$COMMUNICATION_SERVICE_NAME" ]; then
        print_info "Checking for phone numbers to release..."
        
        # List phone numbers
        PHONE_NUMBERS=$(az communication phonenumber list \
            --resource-group "$RESOURCE_GROUP" \
            --communication-service "$COMMUNICATION_SERVICE_NAME" \
            --query "[].phoneNumber" \
            --output tsv 2>/dev/null || echo "")
        
        if [ ! -z "$PHONE_NUMBERS" ]; then
            print_warning "Found phone numbers that will be released:"
            echo "$PHONE_NUMBERS"
            echo
            
            read -p "Release phone numbers to stop monthly charges? (Y/n): " RELEASE_NUMBERS
            if [[ ! $RELEASE_NUMBERS =~ ^[Nn]$ ]]; then
                for number in $PHONE_NUMBERS; do
                    print_info "Releasing phone number: $number"
                    az communication phonenumber release \
                        --resource-group "$RESOURCE_GROUP" \
                        --communication-service "$COMMUNICATION_SERVICE_NAME" \
                        --phone-number "$number" || print_warning "Failed to release $number"
                done
                print_success "Phone numbers released"
            else
                print_warning "Phone numbers not released. Monthly charges will continue."
            fi
        else
            print_info "No phone numbers found to release"
        fi
    else
        print_warning "Communication Service name not provided. Skipping phone number release."
        print_warning "You may need to manually release phone numbers to stop monthly charges."
    fi
}

# Delete resource group
delete_resource_group() {
    print_warning "This will permanently delete all resources in the resource group!"
    print_warning "This action cannot be undone."
    echo
    
    read -p "Type 'DELETE' to confirm resource group deletion: " CONFIRMATION
    if [ "$CONFIRMATION" != "DELETE" ]; then
        print_info "Cleanup cancelled"
        exit 0
    fi
    
    print_info "Deleting resource group: $RESOURCE_GROUP"
    print_info "This may take several minutes..."
    
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    
    print_success "Resource group deletion initiated"
    print_info "Deletion is running in the background and may take 5-10 minutes to complete"
    
    # Offer to wait for completion
    read -p "Wait for deletion to complete? (y/N): " WAIT_FOR_COMPLETION
    if [[ $WAIT_FOR_COMPLETION =~ ^[Yy]$ ]]; then
        print_info "Waiting for deletion to complete..."
        
        # Poll for resource group existence
        while az group show --name "$RESOURCE_GROUP" &> /dev/null; do
            echo -n "."
            sleep 10
        done
        echo
        print_success "Resource group deletion completed"
    fi
}

# Clean up local files
cleanup_local_files() {
    read -p "Remove local deployment files? (deployment-info.json) (y/N): " REMOVE_LOCAL
    if [[ $REMOVE_LOCAL =~ ^[Yy]$ ]]; then
        if [ -f "deployment-info.json" ]; then
            rm deployment-info.json
            print_success "Removed deployment-info.json"
        fi
    fi
}

# Show verification commands
show_verification() {
    print_info "Verification commands:"
    echo
    echo "Check if resource group still exists:"
    echo "  az group show --name $RESOURCE_GROUP"
    echo
    echo "List remaining Communication Services resources:"
    echo "  az communication list --query \"[?contains(name, 'sms')]\""
    echo
    echo "Check for remaining Function Apps:"
    echo "  az functionapp list --query \"[?contains(name, 'sms')]\""
}

# Main execution
main() {
    echo
    echo "🧹 Azure SMS Notifications Cleanup Script"
    echo "=========================================="
    echo
    
    print_warning "This script will delete ALL resources created by the SMS notifications template"
    print_warning "Make sure you have backed up any important data before proceeding"
    echo
    
    check_deployment_info
    echo
    
    show_resources
    echo
    
    release_phone_number
    echo
    
    delete_resource_group
    echo
    
    cleanup_local_files
    echo
    
    show_verification
    echo
    
    print_success "Cleanup script completed! 🎉"
    print_info "All resources should be deleted within 10 minutes"
}

# Handle script interruption
trap 'print_error "Cleanup interrupted"; exit 1' INT TERM

# Run main function
main "$@"