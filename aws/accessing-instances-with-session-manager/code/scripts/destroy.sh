#!/bin/bash

# Destroy script for AWS Session Manager Recipe
# This script removes all resources created by the Session Manager deployment

set -e  # Exit on any error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or you don't have valid credentials."
        exit 1
    fi
    
    # Check if environment file exists
    if [ ! -f ".env" ]; then
        error "Environment file (.env) not found. Cannot proceed with cleanup."
        error "This file should have been created during deployment."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Load environment variables
load_environment() {
    log "Loading environment variables from .env file..."
    
    # Source environment file
    source .env
    
    # Verify required variables are set
    required_vars=(
        "INSTANCE_ROLE_NAME"
        "INSTANCE_PROFILE_NAME"
        "USER_POLICY_NAME"
        "LOG_GROUP_NAME"
        "LOG_BUCKET_NAME"
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    log "Environment variables loaded:"
    log "  Region: ${AWS_REGION}"
    log "  Account ID: ${AWS_ACCOUNT_ID}"
    log "  Resources will be cleaned up with suffix: ${RANDOM_SUFFIX:-unknown}"
    
    success "Environment loaded successfully"
}

# Confirm destruction with user
confirm_destruction() {
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete the following AWS resources:"
    echo "  • IAM Role: ${INSTANCE_ROLE_NAME}"
    echo "  • IAM Instance Profile: ${INSTANCE_PROFILE_NAME}"
    echo "  • IAM User Policy: ${USER_POLICY_NAME}"
    echo "  • S3 Bucket: ${LOG_BUCKET_NAME} (including all objects)"
    echo "  • CloudWatch Log Group: ${LOG_GROUP_NAME}"
    echo "  • EC2 Instance: ${INSTANCE_ID:-Not found in environment}"
    echo "  • Session Manager logging preferences"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "User confirmed resource destruction"
}

# Terminate EC2 instance
terminate_ec2_instance() {
    log "Terminating EC2 instance..."
    
    if [ -z "${INSTANCE_ID:-}" ]; then
        warning "Instance ID not found in environment, skipping EC2 termination"
        return 0
    fi
    
    # Check if instance exists and get current state
    INSTANCE_STATE=$(aws ec2 describe-instances \
        --instance-ids ${INSTANCE_ID} \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "NotFound")
    
    if [ "$INSTANCE_STATE" = "NotFound" ]; then
        warning "EC2 instance ${INSTANCE_ID} not found, may have been deleted already"
        return 0
    fi
    
    if [ "$INSTANCE_STATE" = "terminated" ]; then
        success "EC2 instance ${INSTANCE_ID} is already terminated"
        return 0
    fi
    
    # Terminate the instance
    if aws ec2 terminate-instances --instance-ids ${INSTANCE_ID} > /dev/null; then
        log "EC2 instance termination initiated: ${INSTANCE_ID}"
        
        # Wait for termination to complete
        log "Waiting for instance termination to complete..."
        if aws ec2 wait instance-terminated --instance-ids ${INSTANCE_ID}; then
            success "EC2 instance terminated successfully"
        else
            warning "Timeout waiting for instance termination, but process initiated"
        fi
    else
        error "Failed to terminate EC2 instance"
        return 1
    fi
}

# Delete S3 bucket and all contents
delete_s3_bucket() {
    log "Deleting S3 bucket and contents..."
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket ${LOG_BUCKET_NAME} > /dev/null 2>&1; then
        warning "S3 bucket ${LOG_BUCKET_NAME} not found, may have been deleted already"
        return 0
    fi
    
    # Delete all object versions and delete markers (for versioned buckets)
    log "Deleting all object versions in bucket..."
    aws s3api list-object-versions \
        --bucket ${LOG_BUCKET_NAME} \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' \
        --output text 2>/dev/null | while read key version; do
        if [ -n "$key" ] && [ -n "$version" ]; then
            aws s3api delete-object --bucket ${LOG_BUCKET_NAME} --key "$key" --version-id "$version" > /dev/null
        fi
    done
    
    # Delete all delete markers
    aws s3api list-object-versions \
        --bucket ${LOG_BUCKET_NAME} \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
        --output text 2>/dev/null | while read key version; do
        if [ -n "$key" ] && [ -n "$version" ]; then
            aws s3api delete-object --bucket ${LOG_BUCKET_NAME} --key "$key" --version-id "$version" > /dev/null
        fi
    done
    
    # Delete all current objects (fallback for non-versioned buckets)
    if aws s3 rm s3://${LOG_BUCKET_NAME} --recursive > /dev/null 2>&1; then
        log "Deleted all objects from bucket"
    fi
    
    # Delete the bucket itself
    if aws s3api delete-bucket --bucket ${LOG_BUCKET_NAME} > /dev/null; then
        success "S3 bucket deleted: ${LOG_BUCKET_NAME}"
    else
        error "Failed to delete S3 bucket"
        return 1
    fi
}

# Delete IAM instance profile
delete_instance_profile() {
    log "Deleting IAM instance profile..."
    
    # Check if instance profile exists
    if ! aws iam get-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} > /dev/null 2>&1; then
        warning "Instance profile ${INSTANCE_PROFILE_NAME} not found, may have been deleted already"
        return 0
    fi
    
    # Remove role from instance profile first
    if aws iam remove-role-from-instance-profile \
        --instance-profile-name ${INSTANCE_PROFILE_NAME} \
        --role-name ${INSTANCE_ROLE_NAME} > /dev/null 2>&1; then
        log "Role removed from instance profile"
    else
        warning "Failed to remove role from instance profile, continuing..."
    fi
    
    # Delete instance profile
    if aws iam delete-instance-profile \
        --instance-profile-name ${INSTANCE_PROFILE_NAME} > /dev/null; then
        success "Instance profile deleted: ${INSTANCE_PROFILE_NAME}"
    else
        error "Failed to delete instance profile"
        return 1
    fi
}

# Delete IAM role
delete_iam_role() {
    log "Deleting IAM role..."
    
    # Check if role exists
    if ! aws iam get-role --role-name ${INSTANCE_ROLE_NAME} > /dev/null 2>&1; then
        warning "IAM role ${INSTANCE_ROLE_NAME} not found, may have been deleted already"
        return 0
    fi
    
    # Detach all managed policies from role
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
        --role-name ${INSTANCE_ROLE_NAME} \
        --query 'AttachedPolicies[].PolicyArn' \
        --output text)
    
    for policy_arn in $ATTACHED_POLICIES; do
        if [ -n "$policy_arn" ]; then
            if aws iam detach-role-policy \
                --role-name ${INSTANCE_ROLE_NAME} \
                --policy-arn "$policy_arn" > /dev/null; then
                log "Detached policy: $policy_arn"
            else
                warning "Failed to detach policy: $policy_arn"
            fi
        fi
    done
    
    # Delete any inline policies
    INLINE_POLICIES=$(aws iam list-role-policies \
        --role-name ${INSTANCE_ROLE_NAME} \
        --query 'PolicyNames' \
        --output text)
    
    for policy_name in $INLINE_POLICIES; do
        if [ -n "$policy_name" ]; then
            if aws iam delete-role-policy \
                --role-name ${INSTANCE_ROLE_NAME} \
                --policy-name "$policy_name" > /dev/null; then
                log "Deleted inline policy: $policy_name"
            else
                warning "Failed to delete inline policy: $policy_name"
            fi
        fi
    done
    
    # Delete the role
    if aws iam delete-role --role-name ${INSTANCE_ROLE_NAME} > /dev/null; then
        success "IAM role deleted: ${INSTANCE_ROLE_NAME}"
    else
        error "Failed to delete IAM role"
        return 1
    fi
}

# Delete user policy
delete_user_policy() {
    log "Deleting user policy..."
    
    # Check if policy ARN is available in environment
    if [ -z "${POLICY_ARN:-}" ]; then
        # Try to construct policy ARN
        POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${USER_POLICY_NAME}"
    fi
    
    # Check if policy exists
    if ! aws iam get-policy --policy-arn ${POLICY_ARN} > /dev/null 2>&1; then
        warning "User policy ${USER_POLICY_NAME} not found, may have been deleted already"
        return 0
    fi
    
    # List and detach the policy from all users/groups/roles first
    ENTITIES=$(aws iam list-entities-for-policy \
        --policy-arn ${POLICY_ARN} \
        --query 'PolicyUsers[].UserName + PolicyGroups[].GroupName + PolicyRoles[].RoleName' \
        --output text)
    
    for entity in $ENTITIES; do
        if [ -n "$entity" ]; then
            # Try to detach from user first
            aws iam detach-user-policy --user-name "$entity" --policy-arn ${POLICY_ARN} > /dev/null 2>&1 || true
            # Try to detach from group
            aws iam detach-group-policy --group-name "$entity" --policy-arn ${POLICY_ARN} > /dev/null 2>&1 || true
            # Try to detach from role
            aws iam detach-role-policy --role-name "$entity" --policy-arn ${POLICY_ARN} > /dev/null 2>&1 || true
            log "Detached policy from entity: $entity"
        fi
    done
    
    # Delete the policy
    if aws iam delete-policy --policy-arn ${POLICY_ARN} > /dev/null; then
        success "User policy deleted: ${USER_POLICY_NAME}"
    else
        error "Failed to delete user policy"
        return 1
    fi
}

# Delete Session Manager logging preferences
delete_logging_preferences() {
    log "Removing Session Manager logging preferences..."
    
    # Remove Session Manager logging preferences
    if aws ssm delete-preference \
        --name "SessionManagerLoggingPreferences" \
        --preference-type "Custom" > /dev/null 2>&1; then
        success "Session Manager logging preferences removed"
    else
        warning "Failed to remove Session Manager logging preferences, may not exist"
    fi
}

# Delete CloudWatch log group
delete_cloudwatch_logs() {
    log "Deleting CloudWatch log group..."
    
    # Check if log group exists
    if ! aws logs describe-log-groups \
        --log-group-name-prefix ${LOG_GROUP_NAME} \
        --query 'logGroups[0].logGroupName' \
        --output text > /dev/null 2>&1; then
        warning "CloudWatch log group ${LOG_GROUP_NAME} not found, may have been deleted already"
        return 0
    fi
    
    # Delete the log group
    if aws logs delete-log-group --log-group-name ${LOG_GROUP_NAME} > /dev/null; then
        success "CloudWatch log group deleted: ${LOG_GROUP_NAME}"
    else
        error "Failed to delete CloudWatch log group"
        return 1
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files that might have been created during deployment
    local files_to_remove=(
        "trust-policy.json"
        "user-policy.json" 
        "logging-config.json"
        "user-data.sh"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Removed: $file"
        fi
    done
    
    success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check IAM role
    if aws iam get-role --role-name ${INSTANCE_ROLE_NAME} > /dev/null 2>&1; then
        error "IAM role still exists: ${INSTANCE_ROLE_NAME}"
        ((cleanup_errors++))
    else
        success "IAM role cleanup verified"
    fi
    
    # Check instance profile
    if aws iam get-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} > /dev/null 2>&1; then
        error "Instance profile still exists: ${INSTANCE_PROFILE_NAME}"
        ((cleanup_errors++))
    else
        success "Instance profile cleanup verified"
    fi
    
    # Check user policy
    POLICY_ARN="${POLICY_ARN:-arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${USER_POLICY_NAME}}"
    if aws iam get-policy --policy-arn ${POLICY_ARN} > /dev/null 2>&1; then
        error "User policy still exists: ${USER_POLICY_NAME}"
        ((cleanup_errors++))
    else
        success "User policy cleanup verified"
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket ${LOG_BUCKET_NAME} > /dev/null 2>&1; then
        error "S3 bucket still exists: ${LOG_BUCKET_NAME}"
        ((cleanup_errors++))
    else
        success "S3 bucket cleanup verified"
    fi
    
    # Check CloudWatch log group
    if aws logs describe-log-groups --log-group-name-prefix ${LOG_GROUP_NAME} --query 'logGroups[0]' --output text 2>/dev/null | grep -q ${LOG_GROUP_NAME}; then
        error "CloudWatch log group still exists: ${LOG_GROUP_NAME}"
        ((cleanup_errors++))
    else
        success "CloudWatch log group cleanup verified"
    fi
    
    # Check EC2 instance (if ID available)
    if [ -n "${INSTANCE_ID:-}" ]; then
        INSTANCE_STATE=$(aws ec2 describe-instances \
            --instance-ids ${INSTANCE_ID} \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "NotFound")
        
        if [ "$INSTANCE_STATE" != "NotFound" ] && [ "$INSTANCE_STATE" != "terminated" ]; then
            error "EC2 instance still exists in state: ${INSTANCE_STATE}"
            ((cleanup_errors++))
        else
            success "EC2 instance cleanup verified"
        fi
    fi
    
    if [ $cleanup_errors -eq 0 ]; then
        success "All resources cleaned up successfully"
        return 0
    else
        error "Cleanup completed with $cleanup_errors errors"
        return 1
    fi
}

# Display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "================"
    
    echo "✅ EC2 Instance: ${INSTANCE_ID:-N/A} - Terminated"
    echo "✅ S3 Bucket: ${LOG_BUCKET_NAME} - Deleted"
    echo "✅ IAM Instance Profile: ${INSTANCE_PROFILE_NAME} - Deleted" 
    echo "✅ IAM Role: ${INSTANCE_ROLE_NAME} - Deleted"
    echo "✅ User Policy: ${USER_POLICY_NAME} - Deleted"
    echo "✅ CloudWatch Log Group: ${LOG_GROUP_NAME} - Deleted"
    echo "✅ Session Manager logging preferences - Removed"
    echo "✅ Local files - Cleaned up"
    echo ""
    
    # Ask if user wants to keep or remove environment file
    read -p "Do you want to remove the .env file? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        rm -f .env
        success "Environment file removed"
    else
        log "Environment file preserved for reference"
    fi
    
    success "Cleanup completed successfully!"
}

# Main cleanup function
main() {
    log "Starting AWS Session Manager resource cleanup..."
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    # Perform cleanup operations
    terminate_ec2_instance
    delete_s3_bucket
    delete_instance_profile
    delete_iam_role
    delete_user_policy
    delete_logging_preferences  
    delete_cloudwatch_logs
    cleanup_local_files
    
    # Verify and summarize
    if verify_cleanup; then
        display_summary
        exit 0
    else
        error "Cleanup completed with errors. Please check AWS console for any remaining resources."
        exit 1
    fi
}

# Trap to handle script interruption
trap 'error "Script interrupted during cleanup"; exit 1' INT TERM

# Run main function
main "$@"