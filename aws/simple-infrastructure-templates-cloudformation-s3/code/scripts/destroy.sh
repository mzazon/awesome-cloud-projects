#!/bin/bash

#####################################################################
# Destroy Script for Simple Infrastructure Templates CloudFormation S3
# Recipe: Simple Infrastructure Templates with CloudFormation and S3
# Version: 1.1
# 
# This script safely destroys CloudFormation stack and all associated
# resources with proper error handling, logging, and safety checks.
#####################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Default values
DEFAULT_STACK_NAME="simple-s3-infrastructure"

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Display current AWS identity
    local account_id
    local aws_region
    account_id=$(aws sts get-caller-identity --query Account --output text)
    aws_region=$(aws configure get region || echo "us-east-1")
    
    log "INFO" "AWS Account ID: $account_id"
    log "INFO" "AWS Region: $aws_region"
    
    # Check CloudFormation permissions
    if ! aws cloudformation list-stacks --query 'StackSummaries[0].StackName' --output text &> /dev/null; then
        log "ERROR" "Insufficient CloudFormation permissions. Please check your IAM permissions."
        exit 1
    fi
    
    log "SUCCESS" "Prerequisites check completed"
}

# Function to check if stack exists
stack_exists() {
    local stack_name="$1"
    aws cloudformation describe-stacks --stack-name "$stack_name" &> /dev/null
}

# Function to get stack status
get_stack_status() {
    local stack_name="$1"
    aws cloudformation describe-stacks --stack-name "$stack_name" \
        --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND"
}

# Function to get stack resources
get_stack_resources() {
    local stack_name="$1"
    
    log "INFO" "Retrieving stack resources..."
    
    local resources
    resources=$(aws cloudformation list-stack-resources --stack-name "$stack_name" \
        --query 'StackResourceSummaries[*].[LogicalResourceId,ResourceType,PhysicalResourceId,ResourceStatus]' \
        --output table 2>/dev/null)
    
    if [[ -n "$resources" && "$resources" != "None" ]]; then
        log "INFO" "Stack resources:"
        echo "$resources"
        return 0
    else
        log "WARN" "No resources found for stack"
        return 1
    fi
}

# Function to get S3 bucket name from stack
get_s3_bucket_name() {
    local stack_name="$1"
    
    aws cloudformation describe-stacks --stack-name "$stack_name" \
        --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
        --output text 2>/dev/null || echo ""
}

# Function to empty S3 bucket
empty_s3_bucket() {
    local bucket_name="$1"
    
    if [[ -z "$bucket_name" ]]; then
        log "WARN" "No bucket name provided for emptying"
        return 0
    fi
    
    log "INFO" "Checking if S3 bucket exists: $bucket_name"
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log "WARN" "S3 bucket does not exist or is not accessible: $bucket_name"
        return 0
    fi
    
    log "INFO" "Emptying S3 bucket: $bucket_name"
    
    # Check if bucket has objects
    local object_count
    object_count=$(aws s3api list-objects-v2 --bucket "$bucket_name" \
        --query 'KeyCount' --output text 2>/dev/null || echo "0")
    
    if [[ "$object_count" -eq 0 ]]; then
        log "INFO" "S3 bucket is already empty"
        return 0
    fi
    
    log "INFO" "Found $object_count objects in bucket, deleting..."
    
    # Delete all object versions (for versioned buckets)
    local versions
    versions=$(aws s3api list-object-versions --bucket "$bucket_name" \
        --query 'Versions[*].[Key,VersionId]' --output text 2>/dev/null || echo "")
    
    if [[ -n "$versions" ]]; then
        log "INFO" "Deleting object versions..."
        echo "$versions" | while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object --bucket "$bucket_name" \
                    --key "$key" --version-id "$version_id" >/dev/null 2>&1 || true
            fi
        done
    fi
    
    # Delete delete markers (for versioned buckets)
    local delete_markers
    delete_markers=$(aws s3api list-object-versions --bucket "$bucket_name" \
        --query 'DeleteMarkers[*].[Key,VersionId]' --output text 2>/dev/null || echo "")
    
    if [[ -n "$delete_markers" ]]; then
        log "INFO" "Deleting delete markers..."
        echo "$delete_markers" | while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object --bucket "$bucket_name" \
                    --key "$key" --version-id "$version_id" >/dev/null 2>&1 || true
            fi
        done
    fi
    
    # Delete current objects (fallback for non-versioned objects)
    aws s3 rm "s3://$bucket_name/" --recursive >/dev/null 2>&1 || true
    
    # Verify bucket is empty
    local final_count
    final_count=$(aws s3api list-objects-v2 --bucket "$bucket_name" \
        --query 'KeyCount' --output text 2>/dev/null || echo "0")
    
    if [[ "$final_count" -eq 0 ]]; then
        log "SUCCESS" "S3 bucket emptied successfully"
    else
        log "WARN" "S3 bucket may still contain $final_count objects"
    fi
}

# Function to disable termination protection
disable_termination_protection() {
    local stack_name="$1"
    
    log "INFO" "Checking termination protection status..."
    
    local termination_protection
    termination_protection=$(aws cloudformation describe-stacks --stack-name "$stack_name" \
        --query 'Stacks[0].EnableTerminationProtection' --output text 2>/dev/null || echo "false")
    
    if [[ "$termination_protection" == "true" ]]; then
        log "INFO" "Disabling termination protection..."
        aws cloudformation update-termination-protection \
            --stack-name "$stack_name" \
            --no-enable-termination-protection
        log "SUCCESS" "Termination protection disabled"
    else
        log "INFO" "Termination protection is already disabled"
    fi
}

# Function to delete CloudFormation stack
delete_stack() {
    local stack_name="$1"
    
    log "INFO" "Initiating stack deletion: $stack_name"
    
    # Initiate stack deletion
    if aws cloudformation delete-stack --stack-name "$stack_name" 2>/dev/null; then
        log "SUCCESS" "Stack deletion initiated"
    else
        local exit_code=$?
        log "ERROR" "Failed to initiate stack deletion (exit code: $exit_code)"
        
        # Show recent stack events for debugging
        log "INFO" "Recent stack events:"
        aws cloudformation describe-stack-events --stack-name "$stack_name" \
            --query 'StackEvents[0:5].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason]' \
            --output table 2>/dev/null || true
        
        exit 1
    fi
}

# Function to wait for stack deletion
wait_for_stack_deletion() {
    local stack_name="$1"
    
    log "INFO" "Waiting for stack deletion to complete..."
    
    # Use AWS CLI wait with timeout (30 minutes)
    if timeout 1800 aws cloudformation wait stack-delete-complete --stack-name "$stack_name" 2>/dev/null; then
        log "SUCCESS" "Stack deletion completed successfully"
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log "ERROR" "Stack deletion timed out after 30 minutes"
        else
            # Check if stack still exists (it might have been deleted successfully)
            local current_status
            current_status=$(get_stack_status "$stack_name")
            
            if [[ "$current_status" == "NOT_FOUND" ]]; then
                log "SUCCESS" "Stack deletion completed successfully"
                return 0
            else
                log "ERROR" "Stack deletion failed with status: $current_status"
            fi
        fi
        
        # Show stack events for debugging
        log "INFO" "Recent stack events:"
        aws cloudformation describe-stack-events --stack-name "$stack_name" \
            --query 'StackEvents[0:10].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason]' \
            --output table 2>/dev/null || true
        
        exit 1
    fi
}

# Function to verify stack deletion
verify_stack_deletion() {
    local stack_name="$1"
    
    log "INFO" "Verifying stack deletion..."
    
    # Check if stack still exists
    if stack_exists "$stack_name"; then
        local current_status
        current_status=$(get_stack_status "$stack_name")
        log "ERROR" "Stack still exists with status: $current_status"
        exit 1
    else
        log "SUCCESS" "Stack successfully deleted and no longer exists"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    local files_to_clean=(
        "${SCRIPT_DIR}/stack-outputs.json"
        "${SCRIPT_DIR}/../s3-infrastructure-template.yaml"
        "${SCRIPT_DIR}/deploy.log"
    )
    
    for file in "${files_to_clean[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "INFO" "Removed: $file"
        fi
    done
    
    log "SUCCESS" "Local file cleanup completed"
}

# Function to confirm destructive action
confirm_deletion() {
    local stack_name="$1"
    local force="$2"
    
    if [[ "$force" == true ]]; then
        log "INFO" "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    echo
    log "WARN" "This will permanently delete the following:"
    log "WARN" "  - CloudFormation stack: $stack_name"
    log "WARN" "  - All S3 objects and versions in associated bucket"
    log "WARN" "  - The S3 bucket itself"
    log "WARN" "  - All stack-related resources"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "INFO" "Operation cancelled by user"
        exit 0
    fi
    
    log "INFO" "User confirmed deletion"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Simple Infrastructure Templates CloudFormation S3 Recipe

OPTIONS:
    -s, --stack-name NAME     CloudFormation stack name (default: $DEFAULT_STACK_NAME)
    -f, --force              Skip confirmation prompts
    -r, --region REGION      AWS region (default: current configured region)
    -c, --cleanup-only       Only clean up local files, don't delete AWS resources
    -v, --verbose            Enable verbose logging
    -h, --help               Show this help message

EXAMPLES:
    $0                           # Destroy with default stack name (with confirmation)
    $0 -s my-stack              # Destroy specific stack
    $0 -f                       # Force deletion without confirmation
    $0 -c                       # Clean up local files only
    $0 -v                       # Verbose logging

NOTES:
    - AWS credentials must be configured
    - This will permanently delete all resources created by the stack
    - S3 bucket contents will be deleted before bucket deletion
    - Termination protection will be disabled if enabled
    - Logs are written to: $LOG_FILE

WARNING:
    This operation is irreversible. All data in the S3 bucket will be permanently lost.

EOF
}

# Main destruction function
main() {
    local stack_name="$DEFAULT_STACK_NAME"
    local force=false
    local cleanup_only=false
    local verbose=false
    local aws_region=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--stack-name)
                stack_name="$2"
                shift 2
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -r|--region)
                aws_region="$2"
                shift 2
                ;;
            -c|--cleanup-only)
                cleanup_only=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set AWS region if provided
    if [[ -n "$aws_region" ]]; then
        export AWS_DEFAULT_REGION="$aws_region"
        log "INFO" "Using AWS region: $aws_region"
    fi
    
    # Enable verbose logging if requested
    if [[ "$verbose" == true ]]; then
        set -x
    fi
    
    # Initialize log file
    echo "Destruction started at $(date)" > "$LOG_FILE"
    
    log "INFO" "Starting destruction process..."
    log "INFO" "Stack name: $stack_name"
    log "INFO" "Force mode: $force"
    log "INFO" "Cleanup only: $cleanup_only"
    log "INFO" "Log file: $LOG_FILE"
    
    # If cleanup only, just clean local files and exit
    if [[ "$cleanup_only" == true ]]; then
        cleanup_local_files
        log "SUCCESS" "Local cleanup completed"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Check if stack exists
    if ! stack_exists "$stack_name"; then
        log "WARN" "Stack '$stack_name' does not exist or is not accessible"
        log "INFO" "Checking for local files to clean up..."
        cleanup_local_files
        exit 0
    fi
    
    # Get current stack status
    local current_status
    current_status=$(get_stack_status "$stack_name")
    log "INFO" "Current stack status: $current_status"
    
    # Check if stack is in a deletable state
    if [[ "$current_status" =~ ^(DELETE_IN_PROGRESS|DELETE_COMPLETE)$ ]]; then
        log "INFO" "Stack is already being deleted or has been deleted"
        wait_for_stack_deletion "$stack_name"
        verify_stack_deletion "$stack_name"
        cleanup_local_files
        exit 0
    fi
    
    if [[ "$current_status" =~ (FAILED|ROLLBACK) ]]; then
        log "WARN" "Stack is in a failed state: $current_status"
        log "WARN" "Attempting to delete anyway..."
    fi
    
    # Show stack resources before deletion
    get_stack_resources "$stack_name"
    
    # Get S3 bucket name for emptying
    local bucket_name
    bucket_name=$(get_s3_bucket_name "$stack_name")
    
    # Confirm deletion (unless forced)
    confirm_deletion "$stack_name" "$force"
    
    # Empty S3 bucket before stack deletion
    if [[ -n "$bucket_name" ]]; then
        empty_s3_bucket "$bucket_name"
    else
        log "WARN" "Could not determine S3 bucket name from stack outputs"
    fi
    
    # Disable termination protection if enabled
    disable_termination_protection "$stack_name"
    
    # Delete the stack
    delete_stack "$stack_name"
    
    # Wait for deletion to complete
    wait_for_stack_deletion "$stack_name"
    
    # Verify deletion
    verify_stack_deletion "$stack_name"
    
    # Clean up local files
    cleanup_local_files
    
    log "SUCCESS" "Destruction completed successfully!"
    log "INFO" "Stack '$stack_name' and all associated resources have been deleted"
}

# Trap for cleanup on script exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Destruction failed with exit code: $exit_code"
        log "INFO" "Check the log file for details: $LOG_FILE"
        log "WARN" "Some resources may still exist and require manual cleanup"
    fi
}

trap cleanup EXIT

# Run main function
main "$@"