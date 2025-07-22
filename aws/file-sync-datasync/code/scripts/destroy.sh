#!/bin/bash

# File System Synchronization with AWS DataSync and EFS - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please configure AWS CLI first."
        exit 1
    fi
    
    # Check if deployment state file exists
    if [ ! -f "deployment_state.json" ]; then
        error "deployment_state.json not found. Cannot proceed with cleanup."
        error "This file should have been created by deploy.sh"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to confirm destruction
confirm_destruction() {
    log "This will permanently delete the following resources:"
    echo "  - DataSync Task and Locations"
    echo "  - EFS File System and Mount Targets"
    echo "  - S3 Bucket and all contents"
    echo "  - VPC, Subnets, and Security Groups"
    echo "  - IAM Role and Policies"
    echo ""
    
    if [ -f "deployment_state.json" ]; then
        echo "Resources to be deleted:"
        echo "  VPC: $(jq -r '.vpc_id // "N/A"' deployment_state.json)"
        echo "  EFS: $(jq -r '.efs_id // "N/A"' deployment_state.json)"
        echo "  S3 Bucket: $(jq -r '.source_bucket // "N/A"' deployment_state.json)"
        echo "  DataSync Task: $(jq -r '.task_arn // "N/A"' deployment_state.json)"
        echo ""
    fi
    
    read -p "Are you sure you want to continue? (Type 'DELETE' to confirm): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log "Cleanup cancelled"
        exit 0
    fi
    
    log "Confirmation received. Proceeding with cleanup..."
}

# Function to safely delete resource with error handling
safe_delete() {
    local resource_type="$1"
    local resource_id="$2"
    local delete_command="$3"
    
    if [ -n "$resource_id" ] && [ "$resource_id" != "null" ] && [ "$resource_id" != "N/A" ]; then
        log "Deleting $resource_type: $resource_id"
        if eval "$delete_command"; then
            success "$resource_type deleted successfully"
        else
            warning "Failed to delete $resource_type: $resource_id"
            return 1
        fi
    else
        log "No $resource_type to delete"
    fi
    return 0
}

# Function to delete DataSync resources
delete_datasync_resources() {
    log "Cleaning up DataSync resources..."
    
    # Get resource IDs from state file
    TASK_ARN=$(jq -r '.task_arn // "null"' deployment_state.json)
    S3_LOCATION_ARN=$(jq -r '.s3_location_arn // "null"' deployment_state.json)
    EFS_LOCATION_ARN=$(jq -r '.efs_location_arn // "null"' deployment_state.json)
    
    # Delete DataSync task
    if [ "$TASK_ARN" != "null" ] && [ -n "$TASK_ARN" ]; then
        log "Deleting DataSync task..."
        
        # Check if there are any running executions
        RUNNING_EXECUTIONS=$(aws datasync list-task-executions \
            --task-arn "$TASK_ARN" \
            --query 'TaskExecutions[?Status==`RUNNING` || Status==`QUEUED` || Status==`LAUNCHING`].TaskExecutionArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$RUNNING_EXECUTIONS" ]; then
            warning "Found running task executions. Waiting for completion..."
            for execution in $RUNNING_EXECUTIONS; do
                log "Cancelling execution: $execution"
                aws datasync cancel-task-execution --task-execution-arn "$execution" || true
            done
            sleep 10
        fi
        
        safe_delete "DataSync Task" "$TASK_ARN" "aws datasync delete-task --task-arn '$TASK_ARN'"
    fi
    
    # Delete DataSync locations
    safe_delete "DataSync S3 Location" "$S3_LOCATION_ARN" "aws datasync delete-location --location-arn '$S3_LOCATION_ARN'"
    safe_delete "DataSync EFS Location" "$EFS_LOCATION_ARN" "aws datasync delete-location --location-arn '$EFS_LOCATION_ARN'"
}

# Function to delete EFS resources
delete_efs_resources() {
    log "Cleaning up EFS resources..."
    
    EFS_ID=$(jq -r '.efs_id // "null"' deployment_state.json)
    MOUNT_TARGET_ID=$(jq -r '.mount_target_id // "null"' deployment_state.json)
    
    # Delete mount target first
    if [ "$MOUNT_TARGET_ID" != "null" ] && [ -n "$MOUNT_TARGET_ID" ]; then
        log "Deleting EFS mount target..."
        if aws efs delete-mount-target --mount-target-id "$MOUNT_TARGET_ID"; then
            success "Mount target deletion initiated"
            log "Waiting for mount target to be deleted..."
            
            # Wait for mount target deletion with timeout
            local timeout=180  # 3 minutes
            local elapsed=0
            
            while [ $elapsed -lt $timeout ]; do
                if ! aws efs describe-mount-targets --mount-target-id "$MOUNT_TARGET_ID" &>/dev/null; then
                    success "Mount target deleted"
                    break
                fi
                sleep 10
                elapsed=$((elapsed + 10))
                log "Still waiting for mount target deletion... (${elapsed}s)"
            done
            
            if [ $elapsed -ge $timeout ]; then
                warning "Mount target deletion timed out"
            fi
        else
            warning "Failed to delete mount target: $MOUNT_TARGET_ID"
        fi
    fi
    
    # Delete EFS file system
    safe_delete "EFS File System" "$EFS_ID" "aws efs delete-file-system --file-system-id '$EFS_ID'"
}

# Function to delete S3 resources
delete_s3_resources() {
    log "Cleaning up S3 resources..."
    
    SOURCE_BUCKET=$(jq -r '.source_bucket // "null"' deployment_state.json)
    
    if [ "$SOURCE_BUCKET" != "null" ] && [ -n "$SOURCE_BUCKET" ]; then
        log "Deleting S3 bucket and all contents: $SOURCE_BUCKET"
        
        # Check if bucket exists
        if aws s3 ls "s3://$SOURCE_BUCKET" &>/dev/null; then
            # Delete all objects in bucket
            log "Removing all objects from bucket..."
            aws s3 rm "s3://$SOURCE_BUCKET" --recursive || warning "Failed to remove some objects"
            
            # Delete bucket
            if aws s3 rb "s3://$SOURCE_BUCKET"; then
                success "S3 bucket deleted successfully"
            else
                warning "Failed to delete S3 bucket: $SOURCE_BUCKET"
            fi
        else
            log "S3 bucket not found or already deleted"
        fi
    fi
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Cleaning up IAM resources..."
    
    DATASYNC_ROLE_NAME=$(jq -r '.datasync_role_name // "null"' deployment_state.json)
    
    if [ "$DATASYNC_ROLE_NAME" != "null" ] && [ -n "$DATASYNC_ROLE_NAME" ]; then
        log "Deleting IAM role: $DATASYNC_ROLE_NAME"
        
        # Detach managed policies
        log "Detaching policies from role..."
        aws iam detach-role-policy \
            --role-name "$DATASYNC_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" || warning "Failed to detach S3 policy"
        
        # Delete role
        safe_delete "IAM Role" "$DATASYNC_ROLE_NAME" "aws iam delete-role --role-name '$DATASYNC_ROLE_NAME'"
    fi
}

# Function to delete VPC and networking resources
delete_vpc_resources() {
    log "Cleaning up VPC and networking resources..."
    
    VPC_ID=$(jq -r '.vpc_id // "null"' deployment_state.json)
    SUBNET_ID=$(jq -r '.subnet_id // "null"' deployment_state.json)
    SG_ID=$(jq -r '.security_group_id // "null"' deployment_state.json)
    
    # Delete security group
    safe_delete "Security Group" "$SG_ID" "aws ec2 delete-security-group --group-id '$SG_ID'"
    
    # Delete subnet
    safe_delete "Subnet" "$SUBNET_ID" "aws ec2 delete-subnet --subnet-id '$SUBNET_ID'"
    
    # Delete VPC
    safe_delete "VPC" "$VPC_ID" "aws ec2 delete-vpc --vpc-id '$VPC_ID'"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files created during deployment
    local temp_files=(
        "/tmp/datasync-trust-policy.json"
        "/tmp/datasync-sample"
        "/tmp/sample1.txt"
        "/tmp/sample2.txt"
        "/tmp/test-folder"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -e "$file" ]; then
            rm -rf "$file"
            log "Removed temporary file/directory: $file"
        fi
    done
    
    # Ask user if they want to remove the deployment state file
    read -p "Do you want to remove the deployment state file (deployment_state.json)? [y/N]: " remove_state
    
    if [[ "$remove_state" =~ ^[Yy]$ ]]; then
        rm -f deployment_state.json
        success "Deployment state file removed"
    else
        log "Deployment state file preserved"
    fi
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local validation_errors=0
    
    # Check if resources still exist
    VPC_ID=$(jq -r '.vpc_id // "null"' deployment_state.json 2>/dev/null || echo "null")
    EFS_ID=$(jq -r '.efs_id // "null"' deployment_state.json 2>/dev/null || echo "null")
    SOURCE_BUCKET=$(jq -r '.source_bucket // "null"' deployment_state.json 2>/dev/null || echo "null")
    
    # Validate VPC deletion
    if [ "$VPC_ID" != "null" ] && [ -n "$VPC_ID" ]; then
        if aws ec2 describe-vpcs --vpc-ids "$VPC_ID" &>/dev/null; then
            warning "VPC still exists: $VPC_ID"
            validation_errors=$((validation_errors + 1))
        else
            success "VPC successfully deleted"
        fi
    fi
    
    # Validate EFS deletion
    if [ "$EFS_ID" != "null" ] && [ -n "$EFS_ID" ]; then
        if aws efs describe-file-systems --file-system-id "$EFS_ID" &>/dev/null; then
            warning "EFS file system still exists: $EFS_ID"
            validation_errors=$((validation_errors + 1))
        else
            success "EFS file system successfully deleted"
        fi
    fi
    
    # Validate S3 deletion
    if [ "$SOURCE_BUCKET" != "null" ] && [ -n "$SOURCE_BUCKET" ]; then
        if aws s3 ls "s3://$SOURCE_BUCKET" &>/dev/null; then
            warning "S3 bucket still exists: $SOURCE_BUCKET"
            validation_errors=$((validation_errors + 1))
        else
            success "S3 bucket successfully deleted"
        fi
    fi
    
    if [ $validation_errors -eq 0 ]; then
        success "All resources have been successfully cleaned up"
    else
        warning "$validation_errors resources may still exist. Check AWS console for manual cleanup."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "=================================="
    echo "The following resources have been removed:"
    echo "  ✓ DataSync Tasks and Locations"
    echo "  ✓ EFS File System and Mount Targets"
    echo "  ✓ S3 Bucket and Contents"
    echo "  ✓ VPC, Subnets, and Security Groups"
    echo "  ✓ IAM Roles and Policies"
    echo "  ✓ Temporary Files"
    echo ""
    echo "Cleanup completed successfully!"
    echo "=================================="
}

# Function to handle partial cleanup on error
handle_cleanup_error() {
    error "Cleanup encountered an error. Some resources may not have been deleted."
    warning "Please check the AWS console and manually remove any remaining resources:"
    
    if [ -f "deployment_state.json" ]; then
        echo "  - VPC: $(jq -r '.vpc_id // "N/A"' deployment_state.json)"
        echo "  - EFS: $(jq -r '.efs_id // "N/A"' deployment_state.json)"
        echo "  - S3 Bucket: $(jq -r '.source_bucket // "N/A"' deployment_state.json)"
        echo "  - DataSync Task: $(jq -r '.task_arn // "N/A"' deployment_state.json)"
    fi
    
    warning "You may incur charges for any remaining resources."
}

# Main cleanup function
main() {
    log "Starting cleanup of DataSync and EFS resources..."
    
    # Set trap for error handling
    trap handle_cleanup_error ERR
    
    check_prerequisites
    confirm_destruction
    
    # Continue cleanup even if individual steps fail
    set +e
    
    delete_datasync_resources
    delete_efs_resources
    delete_s3_resources
    delete_iam_resources
    delete_vpc_resources
    cleanup_temp_files
    
    # Re-enable exit on error for validation
    set -e
    
    validate_cleanup
    display_cleanup_summary
    
    success "Cleanup completed!"
}

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    error "jq is required but not installed. Please install jq to continue."
    exit 1
fi

# Run main function
main "$@"