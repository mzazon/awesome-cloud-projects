#!/bin/bash

# Advanced Request Routing with VPC Lattice and ALB - Destruction Script
# This script safely destroys the CDK TypeScript stack with confirmation

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS credentials
validate_aws_credentials() {
    print_status "Validating AWS credentials..."
    
    if ! command_exists aws; then
        print_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Get account and region info
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    print_success "AWS credentials validated for account $AWS_ACCOUNT_ID in region $AWS_REGION"
}

# Function to list existing stacks
list_stacks() {
    print_status "Checking for deployed stacks..."
    
    # Look for stacks with common prefixes
    STACKS=$(aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query 'StackSummaries[?contains(StackName, `AdvancedRouting`)].StackName' \
        --output text)
    
    if [ -z "$STACKS" ]; then
        print_warning "No Advanced Request Routing stacks found in the current region."
        echo ""
        print_status "Available stacks in region $AWS_REGION:"
        aws cloudformation list-stacks \
            --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
            --query 'StackSummaries[*].StackName' \
            --output table
        exit 0
    else
        print_success "Found the following Advanced Request Routing stacks:"
        for stack in $STACKS; do
            echo "  - $stack"
        done
    fi
}

# Function to show stack resources
show_stack_resources() {
    local stack_name=$1
    
    print_status "Resources that will be deleted in stack '$stack_name':"
    
    aws cloudformation list-stack-resources \
        --stack-name "$stack_name" \
        --query 'StackResourceSummaries[*].[ResourceType,LogicalResourceId,ResourceStatus]' \
        --output table
}

# Function to get confirmation
get_confirmation() {
    local stack_name=$1
    
    echo ""
    print_warning "⚠️  WARNING: This will permanently delete all resources in the stack '$stack_name'"
    print_warning "⚠️  This action cannot be undone!"
    echo ""
    
    # Show estimated savings
    print_status "💰 Estimated hourly cost savings after deletion:"
    echo "  - EC2 instances (2x t3.micro): ~\$0.021/hour"
    echo "  - Application Load Balancer: ~\$0.023/hour"
    echo "  - VPC Lattice: \$0.025 per million requests"
    echo "  - Total estimated savings: ~\$0.05+/hour"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        print_status "Destruction cancelled by user."
        exit 0
    fi
    
    # Double confirmation for production-like environments
    if [[ "$stack_name" =~ [Pp]rod ]]; then
        print_warning "🚨 This appears to be a production stack!"
        read -p "Please type 'DELETE PRODUCTION' to confirm: " prod_confirmation
        if [ "$prod_confirmation" != "DELETE PRODUCTION" ]; then
            print_status "Production stack destruction cancelled."
            exit 0
        fi
    fi
}

# Function to destroy the stack
destroy_stack() {
    local stack_name=$1
    
    print_status "Starting destruction of stack '$stack_name'..."
    
    # Use CDK destroy if cdk.json exists, otherwise use CloudFormation
    if [ -f "cdk.json" ] && command_exists cdk; then
        print_status "Using CDK to destroy the stack..."
        
        # Extract context from stack name if possible
        if [[ "$stack_name" =~ ^(.+)-([^-]+)$ ]]; then
            STACK_PREFIX="${BASH_REMATCH[1]}"
            ENVIRONMENT="${BASH_REMATCH[2]}"
            
            cdk destroy \
                --context stackPrefix="$STACK_PREFIX" \
                --context environment="$ENVIRONMENT" \
                --force
        else
            # Fallback to direct stack name
            cdk destroy "$stack_name" --force
        fi
    else
        print_status "Using CloudFormation to destroy the stack..."
        aws cloudformation delete-stack --stack-name "$stack_name"
        
        print_status "Waiting for stack deletion to complete..."
        aws cloudformation wait stack-delete-complete --stack-name "$stack_name"
    fi
    
    print_success "Stack '$stack_name' has been successfully destroyed!"
}

# Function to verify destruction
verify_destruction() {
    local stack_name=$1
    
    print_status "Verifying stack destruction..."
    
    # Check if stack still exists
    if aws cloudformation describe-stacks --stack-name "$stack_name" >/dev/null 2>&1; then
        STACK_STATUS=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --query 'Stacks[0].StackStatus' \
            --output text)
        
        if [ "$STACK_STATUS" = "DELETE_COMPLETE" ]; then
            print_success "Stack destruction verified - all resources have been removed."
        else
            print_warning "Stack status: $STACK_STATUS"
            print_status "Stack deletion may still be in progress. Check the AWS Console for details."
        fi
    else
        print_success "Stack has been completely removed from CloudFormation."
    fi
}

# Function to clean up local files
cleanup_local_files() {
    print_status "Cleaning up local build artifacts..."
    
    # Remove CDK output
    if [ -d "cdk.out" ]; then
        rm -rf cdk.out
        print_status "Removed cdk.out directory"
    fi
    
    # Remove compiled TypeScript files
    if [ -d "dist" ]; then
        rm -rf dist
        print_status "Removed dist directory"
    fi
    
    # Remove node_modules if requested
    read -p "Remove node_modules directory? (y/N): " remove_node_modules
    if [[ "$remove_node_modules" =~ ^[Yy]$ ]]; then
        if [ -d "node_modules" ]; then
            rm -rf node_modules
            print_status "Removed node_modules directory"
        fi
    fi
    
    print_success "Local cleanup completed"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [STACK_NAME]"
    echo ""
    echo "Examples:"
    echo "  $0                           # Interactive mode - shows available stacks"
    echo "  $0 AdvancedRouting-dev       # Destroy specific stack"
    echo "  $0 --list                    # List available stacks"
    echo ""
    echo "Options:"
    echo "  -h, --help                   # Show this help"
    echo "  --list                       # List available stacks and exit"
    echo "  --force                      # Skip confirmation (use with caution!)"
}

# Main destruction function
main() {
    echo "=========================================="
    echo "Advanced Request Routing Stack Destroyer"
    echo "=========================================="
    echo ""
    
    # Parse command line arguments
    FORCE_MODE=false
    STACK_NAME=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            --list)
                validate_aws_credentials
                list_stacks
                exit 0
                ;;
            --force)
                FORCE_MODE=true
                shift
                ;;
            *)
                STACK_NAME="$1"
                shift
                ;;
        esac
    done
    
    # Validation
    validate_aws_credentials
    
    # If no stack name provided, list stacks and prompt
    if [ -z "$STACK_NAME" ]; then
        list_stacks
        echo ""
        read -p "Enter the name of the stack to destroy: " STACK_NAME
        
        if [ -z "$STACK_NAME" ]; then
            print_error "No stack name provided."
            exit 1
        fi
    fi
    
    # Verify stack exists
    if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" >/dev/null 2>&1; then
        print_error "Stack '$STACK_NAME' does not exist or is not accessible."
        exit 1
    fi
    
    # Show what will be deleted
    show_stack_resources "$STACK_NAME"
    
    # Get confirmation unless in force mode
    if [ "$FORCE_MODE" = false ]; then
        get_confirmation "$STACK_NAME"
    else
        print_warning "Running in force mode - skipping confirmation!"
    fi
    
    echo ""
    print_status "🗑️  Starting stack destruction process..."
    echo ""
    
    # Destroy the stack
    destroy_stack "$STACK_NAME"
    
    # Verify destruction
    verify_destruction "$STACK_NAME"
    
    # Clean up local files
    cleanup_local_files
    
    echo ""
    print_success "🎉 Stack destruction completed successfully!"
    print_success "💰 You are no longer incurring charges for these resources."
    echo ""
    print_status "If you want to redeploy later, run './deploy.sh'"
}

# Error handling
trap 'print_error "Destruction failed! Check the error messages above."' ERR

# Run main function
main "$@"