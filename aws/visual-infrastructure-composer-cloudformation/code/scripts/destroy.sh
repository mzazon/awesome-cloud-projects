#!/bin/bash

# Visual Infrastructure Composer CloudFormation Cleanup Script
# This script removes all resources created by the deploy.sh script
# Generated for AWS recipe: visual-infrastructure-composer-cloudformation

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
FORCE_DELETE=false
SKIP_CONFIRMATION=false
STACK_NAME=""

# Function to display help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Clean up AWS resources created by the Visual Infrastructure Composer deployment."
    echo ""
    echo "Options:"
    echo "  --stack-name NAME    Specify the CloudFormation stack name to delete"
    echo "  --dry-run           Show what would be deleted without actually deleting"
    echo "  --force             Force deletion without confirmation prompts"
    echo "  --yes               Skip all confirmation prompts (same as --force)"
    echo "  --list-stacks       List all visual-website stacks in the account"
    echo "  --help, -h          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --stack-name visual-website-stack-abc123"
    echo "  $0 --list-stacks"
    echo "  $0 --dry-run --stack-name visual-website-stack-abc123"
    echo "  $0 --force --stack-name visual-website-stack-abc123"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force|--yes)
            FORCE_DELETE=true
            SKIP_CONFIRMATION=true
            shift
            ;;
        --list-stacks)
            LIST_STACKS=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        log "Run 'aws configure' to set up your credentials."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to list all visual-website stacks
list_stacks() {
    log "Listing all visual-website CloudFormation stacks..."
    
    STACKS=$(aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query 'StackSummaries[?contains(StackName, `visual-website-stack`)].{Name:StackName,Status:StackStatus,Created:CreationTime}' \
        --output table 2>/dev/null || echo "")
    
    if [[ -n "$STACKS" && "$STACKS" != "[]" ]]; then
        echo "$STACKS"
        echo ""
        log "To delete a specific stack, run:"
        log "$0 --stack-name <STACK_NAME>"
    else
        echo "No visual-website stacks found in the current region."
    fi
}

# Function to check if stack exists
check_stack_exists() {
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" &> /dev/null; then
        return 0  # Stack exists
    else
        return 1  # Stack doesn't exist
    fi
}

# Function to get bucket name from stack
get_bucket_name() {
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Parameters[?ParameterKey==`BucketName`].ParameterValue' \
        --output text 2>/dev/null || \
    aws cloudformation describe-stack-resources \
        --stack-name "$STACK_NAME" \
        --query 'StackResources[?ResourceType==`AWS::S3::Bucket`].PhysicalResourceId' \
        --output text 2>/dev/null || echo ""
}

# Function to empty S3 bucket
empty_s3_bucket() {
    local bucket_name="$1"
    
    if [[ -z "$bucket_name" ]]; then
        log_warning "Could not determine bucket name. Skipping S3 cleanup."
        return 0
    fi
    
    log "Checking if S3 bucket exists: $bucket_name"
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$bucket_name" &> /dev/null; then
        log_warning "S3 bucket '$bucket_name' does not exist or is not accessible. Skipping."
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would empty S3 bucket: $bucket_name"
        
        # Show what would be deleted
        OBJECTS=$(aws s3 ls "s3://$bucket_name" --recursive 2>/dev/null || echo "")
        if [[ -n "$OBJECTS" ]]; then
            echo "Objects that would be deleted:"
            echo "$OBJECTS"
        else
            echo "No objects found in bucket."
        fi
        return 0
    fi
    
    log "Emptying S3 bucket: $bucket_name"
    
    # List objects to be deleted
    OBJECTS=$(aws s3 ls "s3://$bucket_name" --recursive 2>/dev/null || echo "")
    if [[ -n "$OBJECTS" ]]; then
        log "Found objects in bucket:"
        echo "$OBJECTS"
        
        # Delete all objects and versions
        aws s3 rm "s3://$bucket_name" --recursive
        
        # Delete any versions and delete markers (for versioned buckets)
        aws s3api list-object-versions --bucket "$bucket_name" \
            --query 'Versions[].[Key,VersionId]' --output text 2>/dev/null | \
        while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" &> /dev/null || true
            fi
        done
        
        aws s3api list-object-versions --bucket "$bucket_name" \
            --query 'DeleteMarkers[].[Key,VersionId]' --output text 2>/dev/null | \
        while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" &> /dev/null || true
            fi
        done
        
        log_success "S3 bucket emptied successfully"
    else
        log "S3 bucket is already empty"
    fi
}

# Function to get stack information
get_stack_info() {
    log "Retrieving stack information..."
    
    STACK_INFO=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" 2>/dev/null)
    
    if [[ -z "$STACK_INFO" ]]; then
        log_error "Stack '$STACK_NAME' not found"
        return 1
    fi
    
    STACK_STATUS=$(echo "$STACK_INFO" | jq -r '.Stacks[0].StackStatus')
    CREATION_TIME=$(echo "$STACK_INFO" | jq -r '.Stacks[0].CreationTime')
    
    echo ""
    echo "========================================="
    echo "📋 STACK INFORMATION"
    echo "========================================="
    echo "Stack Name:    $STACK_NAME"
    echo "Stack Status:  $STACK_STATUS"
    echo "Created:       $CREATION_TIME"
    echo "========================================="
    echo ""
    
    # List stack resources
    log "Stack resources to be deleted:"
    aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" \
        --query 'StackResources[].[ResourceType,LogicalResourceId,PhysicalResourceId]' \
        --output table
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following:"
    echo "   • CloudFormation stack: $STACK_NAME"
    echo "   • All S3 bucket contents"
    echo "   • All associated AWS resources"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Type the stack name to confirm: " -r CONFIRM_NAME
    if [[ "$CONFIRM_NAME" != "$STACK_NAME" ]]; then
        log_error "Stack name confirmation failed. Deletion cancelled."
        exit 1
    fi
}

# Function to delete CloudFormation stack
delete_stack() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would delete CloudFormation stack: $STACK_NAME"
        return 0
    fi
    
    log "Initiating CloudFormation stack deletion..."
    
    aws cloudformation delete-stack --stack-name "$STACK_NAME"
    
    log "Waiting for stack deletion to complete..."
    log "This may take several minutes. You can monitor progress in the AWS Console."
    
    # Wait for deletion with timeout
    TIMEOUT=1800  # 30 minutes
    ELAPSED=0
    INTERVAL=30
    
    while [[ $ELAPSED -lt $TIMEOUT ]]; do
        if ! check_stack_exists; then
            log_success "CloudFormation stack deleted successfully"
            return 0
        fi
        
        STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
            --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DELETED")
        
        if [[ "$STACK_STATUS" == "DELETE_FAILED" ]]; then
            log_error "Stack deletion failed. Check the AWS Console for details."
            log "Stack Name: $STACK_NAME"
            return 1
        fi
        
        log "Stack status: $STACK_STATUS (elapsed: ${ELAPSED}s)"
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    done
    
    log_error "Stack deletion timed out after $TIMEOUT seconds"
    log "Check the AWS Console for current status: $STACK_NAME"
    return 1
}

# Function to clean up local environment
cleanup_local_environment() {
    log "Cleaning up local environment..."
    
    # Remove any temporary files created by the deployment
    if [[ -f "$HOME/.aws-visual-infrastructure-deployment" ]]; then
        rm -f "$HOME/.aws-visual-infrastructure-deployment"
        log "Removed deployment tracking file"
    fi
    
    log_success "Local environment cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log "Verifying cleanup completion..."
    
    # Check if stack still exists
    if check_stack_exists; then
        log_warning "Stack still exists. Cleanup may not be complete."
        return 1
    fi
    
    log_success "Cleanup verification completed - all resources removed"
}

# Function to handle script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        log_error "Cleanup script failed or was interrupted"
        log "Check AWS CloudFormation console for current stack status: ${STACK_NAME:-'unknown'}"
    fi
}

# Main execution function
main() {
    log "Starting Visual Infrastructure Composer CloudFormation cleanup..."
    
    # Set up error handling
    trap cleanup_on_exit EXIT
    
    # Handle special cases
    if [[ "${LIST_STACKS:-false}" == "true" ]]; then
        check_prerequisites
        list_stacks
        exit 0
    fi
    
    # Validate required parameters
    if [[ -z "$STACK_NAME" ]]; then
        log_error "Stack name is required. Use --stack-name option or --list-stacks to see available stacks."
        show_help
        exit 1
    fi
    
    # Execute cleanup steps
    check_prerequisites
    
    # Check if stack exists
    if ! check_stack_exists; then
        log_warning "Stack '$STACK_NAME' does not exist or is already deleted"
        log_success "Nothing to clean up"
        exit 0
    fi
    
    get_stack_info
    
    # Get bucket name before deletion
    BUCKET_NAME=$(get_bucket_name)
    
    if [[ ! "$DRY_RUN" == "true" ]]; then
        confirm_deletion
    fi
    
    # Perform cleanup
    if [[ -n "$BUCKET_NAME" ]]; then
        empty_s3_bucket "$BUCKET_NAME"
    fi
    
    delete_stack
    cleanup_local_environment
    verify_cleanup
    
    if [[ ! "$DRY_RUN" == "true" ]]; then
        echo ""
        echo "========================================="
        echo "🧹 CLEANUP COMPLETED"
        echo "========================================="
        echo "Stack Name:  $STACK_NAME"
        echo "Status:      DELETED"
        echo "Bucket:      ${BUCKET_NAME:-'N/A'} (emptied and deleted)"
        echo "========================================="
        echo ""
        log_success "All resources have been successfully removed!"
    fi
}

# Execute main function
main "$@"