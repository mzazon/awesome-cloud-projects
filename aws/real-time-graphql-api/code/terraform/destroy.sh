#!/bin/bash

# ==============================================================================
# AWS AppSync GraphQL API Destroy Script
# ==============================================================================
# This script destroys the AppSync GraphQL API infrastructure using Terraform.
# It includes safety checks and confirmation prompts to prevent accidental deletion.
# ==============================================================================

set -e  # Exit on any error

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

# Function to check if Terraform state exists
check_state() {
    if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
        print_warning "No Terraform state found. Nothing to destroy."
        exit 0
    fi
}

# Function to show what will be destroyed
show_plan() {
    print_status "Showing destruction plan..."
    echo ""
    
    if terraform plan -destroy; then
        print_success "Destruction plan completed!"
        echo ""
    else
        print_error "Failed to create destruction plan!"
        exit 1
    fi
}

# Function to list current resources
list_resources() {
    print_status "Current resources that will be destroyed:"
    echo ""
    
    # Try to get key resource information
    if terraform state list 2>/dev/null | grep -q "aws_appsync_graphql_api"; then
        echo "- AppSync GraphQL API: $(terraform output -raw appsync_api_name 2>/dev/null || echo 'Unknown')"
        echo "- GraphQL Endpoint: $(terraform output -raw graphql_endpoint 2>/dev/null || echo 'Unknown')"
    fi
    
    if terraform state list 2>/dev/null | grep -q "aws_dynamodb_table"; then
        echo "- DynamoDB Table: $(terraform output -raw dynamodb_table_name 2>/dev/null || echo 'Unknown')"
    fi
    
    if terraform state list 2>/dev/null | grep -q "aws_cognito_user_pool"; then
        echo "- Cognito User Pool: $(terraform output -raw cognito_user_pool_name 2>/dev/null || echo 'Unknown')"
    fi
    
    echo ""
    print_warning "ALL DATA IN DYNAMODB WILL BE PERMANENTLY LOST!"
    print_warning "THIS CANNOT BE UNDONE!"
    echo ""
}

# Function to confirm destruction
confirm_destruction() {
    print_warning "You are about to destroy all resources created by this Terraform configuration."
    print_warning "This action cannot be undone and will result in data loss."
    echo ""
    
    # First confirmation
    read -p "Are you sure you want to destroy all resources? (type 'yes' to confirm): " -r
    echo ""
    
    if [ "$REPLY" != "yes" ]; then
        print_status "Destruction cancelled."
        exit 0
    fi
    
    # Second confirmation for extra safety
    read -p "This will permanently delete all data. Type 'DESTROY' to confirm: " -r
    echo ""
    
    if [ "$REPLY" != "DESTROY" ]; then
        print_status "Destruction cancelled."
        exit 0
    fi
    
    print_status "Proceeding with destruction..."
}

# Function to destroy resources
destroy_resources() {
    print_status "Destroying resources..."
    echo ""
    
    if terraform destroy -auto-approve; then
        print_success "All resources have been successfully destroyed!"
    else
        print_error "Destruction failed! Some resources may still exist."
        print_status "Check the AWS console and clean up manually if needed."
        exit 1
    fi
}

# Function to clean up local files
cleanup_local() {
    print_status "Cleaning up local files..."
    
    # Remove plan files
    rm -f tfplan
    
    # Remove state backup files (optional)
    read -p "Do you want to remove Terraform state backup files? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f terraform.tfstate.backup
        rm -f .terraform.lock.hcl
        print_status "Local backup files removed."
    fi
    
    print_success "Local cleanup completed!"
}

# Function to show post-destruction information
show_post_destruction() {
    echo ""
    print_success "Destruction completed successfully!"
    echo ""
    print_status "Post-destruction checklist:"
    echo "  1. Verify all resources are removed in AWS console"
    echo "  2. Check for any remaining costs in AWS Cost Explorer"
    echo "  3. Remove any custom DNS records if you created them"
    echo "  4. Clean up any application code that references the destroyed resources"
    echo ""
    print_status "If you need to redeploy, you can run ./deploy.sh again."
}

# Main function
main() {
    echo "=== AWS AppSync GraphQL API Destruction ==="
    echo ""
    
    # Check if there's anything to destroy
    check_state
    
    # Show current resources
    list_resources
    
    # Show destruction plan
    show_plan
    
    # Get confirmation
    confirm_destruction
    
    # Destroy resources
    destroy_resources
    
    # Clean up local files
    cleanup_local
    
    # Show post-destruction information
    show_post_destruction
}

# Handle script arguments
case "${1:-}" in
    --force)
        print_warning "Force mode enabled. Skipping confirmations."
        print_status "Destroying resources in 5 seconds..."
        sleep 5
        
        check_state
        destroy_resources
        cleanup_local
        show_post_destruction
        ;;
    --help|-h)
        echo "Usage: $0 [--force] [--help]"
        echo ""
        echo "Options:"
        echo "  --force    Skip confirmation prompts (dangerous!)"
        echo "  --help     Show this help message"
        echo ""
        exit 0
        ;;
    "")
        main "$@"
        ;;
    *)
        print_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac