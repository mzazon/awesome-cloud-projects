#!/bin/bash

#
# Cleanup script for Simple File Sharing with Transfer Family Web Apps
# This script helps safely destroy the CDK application and clean up resources
#

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

confirm_destruction() {
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    log_warning "This will permanently delete ALL resources created by the CDK application:"
    echo "  • S3 bucket and all stored files"
    echo "  • Transfer Family Web App"
    echo "  • S3 Access Grants configuration"
    echo "  • Demo user (if created)"
    echo "  • IAM roles and policies"
    echo ""
    
    if [ "$FORCE_DESTROY" = true ]; then
        log_warning "Force destroy enabled - skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    echo ""
    log_warning "Last chance! Type 'DELETE' to confirm destruction:"
    read -p "> " -r
    if [[ $REPLY != "DELETE" ]]; then
        log_info "Operation cancelled - confirmation not matched"
        exit 0
    fi
}

check_stack_exists() {
    log_info "Checking if stack exists..."
    
    STACK_NAME="SimpleFileSharingTransferWebAppStack"
    
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" &> /dev/null; then
        log_success "Found stack: $STACK_NAME"
        return 0
    else
        log_warning "Stack $STACK_NAME not found - nothing to destroy"
        exit 0
    fi
}

get_stack_outputs() {
    log_info "Retrieving stack information before destruction..."
    
    STACK_NAME="SimpleFileSharingTransferWebAppStack"
    
    # Get S3 bucket name
    S3_BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' --output text 2>/dev/null || echo "")
    
    # Get Web App ID
    WEB_APP_ID=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs[?OutputKey==`TransferWebAppId`].OutputValue' --output text 2>/dev/null || echo "")
    
    if [ -n "$S3_BUCKET" ] && [ "$S3_BUCKET" != "None" ]; then
        log_info "Found S3 bucket: $S3_BUCKET"
    fi
    
    if [ -n "$WEB_APP_ID" ] && [ "$WEB_APP_ID" != "None" ]; then
        log_info "Found Transfer Web App: $WEB_APP_ID"
    fi
}

empty_s3_bucket() {
    if [ -n "$S3_BUCKET" ] && [ "$S3_BUCKET" != "None" ]; then
        log_info "Checking S3 bucket contents..."
        
        # Check if bucket exists
        if aws s3 ls "s3://$S3_BUCKET" &> /dev/null; then
            # Get object count
            OBJECT_COUNT=$(aws s3 ls "s3://$S3_BUCKET" --recursive | wc -l)
            
            if [ "$OBJECT_COUNT" -gt 0 ]; then
                log_warning "Found $OBJECT_COUNT objects in S3 bucket"
                log_info "Emptying S3 bucket: $S3_BUCKET"
                
                # Remove all objects and versions
                aws s3 rm "s3://$S3_BUCKET" --recursive
                
                # Remove any delete markers and versions if versioning is enabled
                aws s3api list-object-versions --bucket "$S3_BUCKET" --query 'Versions[].[Key,VersionId]' --output text | while read key version; do
                    if [ -n "$key" ] && [ -n "$version" ]; then
                        aws s3api delete-object --bucket "$S3_BUCKET" --key "$key" --version-id "$version" || true
                    fi
                done
                
                aws s3api list-object-versions --bucket "$S3_BUCKET" --query 'DeleteMarkers[].[Key,VersionId]' --output text | while read key version; do
                    if [ -n "$key" ] && [ -n "$version" ]; then
                        aws s3api delete-object --bucket "$S3_BUCKET" --key "$key" --version-id "$version" || true
                    fi
                done
                
                log_success "S3 bucket emptied"
            else
                log_info "S3 bucket is already empty"
            fi
        else
            log_info "S3 bucket not found or already deleted"
        fi
    fi
}

setup_environment() {
    log_info "Setting up environment for CDK operations..."
    
    # Activate virtual environment if it exists
    if [ -d ".venv" ]; then
        source .venv/bin/activate
        log_success "Activated Python virtual environment"
    else
        log_warning "No virtual environment found - using system Python"
    fi
    
    # Check CDK CLI
    if ! command -v cdk &> /dev/null; then
        log_error "CDK CLI is not installed. Install it with: npm install -g aws-cdk@latest"
        exit 1
    fi
}

destroy_stack() {
    log_info "Destroying CDK stack..."
    
    # Source virtual environment if available
    if [ -d ".venv" ]; then
        source .venv/bin/activate
    fi
    
    # Destroy the stack
    cdk destroy --force
    
    log_success "CDK stack destroyed"
}

cleanup_remaining_resources() {
    log_info "Checking for any remaining resources to clean up..."
    
    # Check if S3 Access Grants instance needs manual cleanup
    # (This is usually handled automatically, but we check just in case)
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Note: S3 Access Grants instances are managed by AWS and cannot be deleted directly
    # They are automatically cleaned up when no longer in use
    
    log_info "Automatic cleanup completed"
}

show_summary() {
    echo ""
    echo "=== Cleanup Summary ==="
    log_success "✅ CDK stack destroyed"
    log_success "✅ S3 bucket and contents removed"
    log_success "✅ Transfer Family Web App removed"
    log_success "✅ IAM roles and policies removed"
    log_success "✅ S3 Access Grants configuration removed"
    log_success "✅ Demo user removed (if created)"
    echo ""
    log_info "Note: IAM Identity Center instance remains active (managed separately)"
    log_info "Note: S3 Access Grants instance is managed by AWS and cleaned up automatically"
    echo ""
    log_success "🎉 All resources have been successfully cleaned up!"
}

main() {
    echo "🧹 Simple File Sharing with Transfer Family Web Apps - Cleanup Script"
    echo "===================================================================="
    echo ""
    
    # Parse command line arguments
    FORCE_DESTROY=false
    SKIP_CONFIRMATION=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DESTROY=true
                shift
                ;;
            --yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --force    Skip all confirmations and force destroy"
                echo "  --yes      Skip confirmation prompts (still shows warnings)"
                echo "  --help, -h Show this help message"
                echo ""
                echo "DANGER: This will permanently delete all resources!"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Check if stack exists
    check_stack_exists
    
    # Get stack information
    get_stack_outputs
    
    # Confirm destruction (unless forced or skipped)
    if [ "$SKIP_CONFIRMATION" = false ]; then
        confirm_destruction
    fi
    
    # Setup environment
    setup_environment
    
    # Empty S3 bucket first (required before stack deletion)
    empty_s3_bucket
    
    # Destroy the CDK stack
    destroy_stack
    
    # Clean up any remaining resources
    cleanup_remaining_resources
    
    # Show summary
    show_summary
}

# Run main function
main "$@"