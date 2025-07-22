#!/bin/bash

# Destroy script for Fine-Grained Access Control with IAM Policies and Conditions
# This script safely removes all resources created by the deploy.sh script

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

# Check for force flag
FORCE_DELETE=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE_DELETE=true
    log "Force delete mode enabled - skipping confirmations"
fi

# Check if required tools are installed
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid. Please run 'aws configure'."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [[ -f "deployment-info.json" ]]; then
        export PROJECT_NAME=$(jq -r '.project_name' deployment-info.json)
        export AWS_REGION=$(jq -r '.aws_region' deployment-info.json)
        export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' deployment-info.json)
        export BUCKET_NAME=$(jq -r '.resources.s3_bucket' deployment-info.json)
        export LOG_GROUP_NAME=$(jq -r '.resources.log_group' deployment-info.json)
        
        log_success "Loaded deployment information from deployment-info.json"
        log "  PROJECT_NAME: ${PROJECT_NAME}"
        log "  AWS_REGION: ${AWS_REGION}"
        log "  BUCKET_NAME: ${BUCKET_NAME}"
    else
        log_warning "deployment-info.json not found. Attempting manual discovery..."
        
        # Try to get environment variables or use defaults
        export AWS_REGION=$(aws configure get region || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Ask user for project name if not provided
        if [[ "$FORCE_DELETE" == "false" ]]; then
            read -p "Enter the project name to delete (e.g., finegrained-access-12345678): " PROJECT_NAME
            if [[ -z "$PROJECT_NAME" ]]; then
                log_error "Project name is required"
                exit 1
            fi
        else
            log_error "Project name required. deployment-info.json not found and force mode enabled."
            exit 1
        fi
        
        export BUCKET_NAME="${PROJECT_NAME}-test-bucket"
        export LOG_GROUP_NAME="/aws/lambda/${PROJECT_NAME}"
    fi
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "false" ]]; then
        log ""
        log "⚠️  WARNING: This will DELETE the following resources:"
        log "  • S3 Bucket: ${BUCKET_NAME} (and all contents)"
        log "  • CloudWatch Log Group: ${LOG_GROUP_NAME}"
        log "  • IAM User: ${PROJECT_NAME}-test-user"
        log "  • IAM Role: ${PROJECT_NAME}-test-role"
        log "  • IAM Policies: All policies with prefix ${PROJECT_NAME}-"
        log ""
        read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRMATION
        
        if [[ "$CONFIRMATION" != "yes" ]]; then
            log "Deletion cancelled by user"
            exit 0
        fi
        log_success "Deletion confirmed by user"
    fi
}

# Detach and delete IAM policies
cleanup_iam_policies() {
    log "Cleaning up IAM policies and attachments..."
    
    # List of policies to clean up
    POLICY_NAMES=(
        "business-hours-policy"
        "ip-restriction-policy"
        "tag-based-policy"
        "mfa-required-policy"
        "session-policy"
    )
    
    # Detach policies from user
    USER_NAME="${PROJECT_NAME}-test-user"
    if aws iam get-user --user-name "$USER_NAME" &>/dev/null; then
        log "Detaching policies from user: $USER_NAME"
        
        for policy_name in "${POLICY_NAMES[@]}"; do
            POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-${policy_name}"
            
            if aws iam detach-user-policy \
                --user-name "$USER_NAME" \
                --policy-arn "$POLICY_ARN" 2>/dev/null; then
                log_success "Detached policy: ${policy_name} from user"
            fi
        done
    else
        log_warning "User $USER_NAME not found"
    fi
    
    # Detach policies from role
    ROLE_NAME="${PROJECT_NAME}-test-role"
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        log "Detaching policies from role: $ROLE_NAME"
        
        for policy_name in "${POLICY_NAMES[@]}"; do
            POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-${policy_name}"
            
            if aws iam detach-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-arn "$POLICY_ARN" 2>/dev/null; then
                log_success "Detached policy: ${policy_name} from role"
            fi
        done
    else
        log_warning "Role $ROLE_NAME not found"
    fi
    
    # Wait for policy detachment to propagate
    log "Waiting for policy detachment to propagate..."
    sleep 5
    
    # Delete IAM policies
    log "Deleting IAM policies..."
    for policy_name in "${POLICY_NAMES[@]}"; do
        POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-${policy_name}"
        
        if aws iam delete-policy --policy-arn "$POLICY_ARN" 2>/dev/null; then
            log_success "Deleted policy: ${policy_name}"
        else
            log_warning "Policy ${policy_name} not found or already deleted"
        fi
    done
}

# Delete IAM principals
cleanup_iam_principals() {
    log "Cleaning up IAM users and roles..."
    
    # Delete test user
    USER_NAME="${PROJECT_NAME}-test-user"
    if aws iam get-user --user-name "$USER_NAME" &>/dev/null; then
        # Remove any remaining attached policies (managed and inline)
        ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
            --user-name "$USER_NAME" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        for policy_arn in $ATTACHED_POLICIES; do
            aws iam detach-user-policy \
                --user-name "$USER_NAME" \
                --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Delete any inline policies
        INLINE_POLICIES=$(aws iam list-user-policies \
            --user-name "$USER_NAME" \
            --query 'PolicyNames[]' \
            --output text 2>/dev/null || echo "")
        
        for policy_name in $INLINE_POLICIES; do
            aws iam delete-user-policy \
                --user-name "$USER_NAME" \
                --policy-name "$policy_name" 2>/dev/null || true
        done
        
        # Delete access keys if any
        ACCESS_KEYS=$(aws iam list-access-keys \
            --user-name "$USER_NAME" \
            --query 'AccessKeyMetadata[].AccessKeyId' \
            --output text 2>/dev/null || echo "")
        
        for access_key in $ACCESS_KEYS; do
            aws iam delete-access-key \
                --user-name "$USER_NAME" \
                --access-key-id "$access_key" 2>/dev/null || true
        done
        
        # Delete user
        aws iam delete-user --user-name "$USER_NAME"
        log_success "Deleted IAM user: $USER_NAME"
    else
        log_warning "User $USER_NAME not found"
    fi
    
    # Delete test role
    ROLE_NAME="${PROJECT_NAME}-test-role"
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        # Remove any remaining attached policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$ROLE_NAME" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        for policy_arn in $ATTACHED_POLICIES; do
            aws iam detach-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Delete any inline policies
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$ROLE_NAME" \
            --query 'PolicyNames[]' \
            --output text 2>/dev/null || echo "")
        
        for policy_name in $INLINE_POLICIES; do
            aws iam delete-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-name "$policy_name" 2>/dev/null || true
        done
        
        # Delete role
        aws iam delete-role --role-name "$ROLE_NAME"
        log_success "Deleted IAM role: $ROLE_NAME"
    else
        log_warning "Role $ROLE_NAME not found"
    fi
}

# Clean up S3 resources
cleanup_s3_resources() {
    log "Cleaning up S3 resources..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        # Remove bucket policy first
        if aws s3api delete-bucket-policy --bucket "$BUCKET_NAME" 2>/dev/null; then
            log_success "Removed S3 bucket policy"
        fi
        
        # Delete all objects in bucket (including versions and delete markers)
        log "Deleting all objects in bucket $BUCKET_NAME..."
        
        # Delete current versions
        aws s3 rm "s3://${BUCKET_NAME}" --recursive --quiet 2>/dev/null || true
        
        # Check if versioning is enabled and clean up versions
        VERSIONING_STATUS=$(aws s3api get-bucket-versioning \
            --bucket "$BUCKET_NAME" \
            --query 'Status' \
            --output text 2>/dev/null || echo "None")
        
        if [[ "$VERSIONING_STATUS" == "Enabled" ]]; then
            log "Cleaning up object versions..."
            
            # Get all versions and delete markers
            aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --output json 2>/dev/null | \
            jq -r '.Versions[]?, .DeleteMarkers[]? | select(.Key != null) | "\(.Key)\t\(.VersionId)"' | \
            while IFS=$'\t' read -r key version_id; do
                if [[ -n "$key" && -n "$version_id" ]]; then
                    aws s3api delete-object \
                        --bucket "$BUCKET_NAME" \
                        --key "$key" \
                        --version-id "$version_id" \
                        --quiet 2>/dev/null || true
                fi
            done
        fi
        
        # Delete the bucket
        aws s3 rb "s3://${BUCKET_NAME}" --force
        log_success "Deleted S3 bucket: $BUCKET_NAME"
    else
        log_warning "S3 bucket $BUCKET_NAME not found"
    fi
}

# Clean up CloudWatch resources
cleanup_cloudwatch_resources() {
    log "Cleaning up CloudWatch resources..."
    
    # Delete log group
    if aws logs describe-log-groups \
        --log-group-name-prefix "$LOG_GROUP_NAME" \
        --query 'logGroups[?logGroupName==`'"$LOG_GROUP_NAME"'`]' \
        --output text | grep -q "$LOG_GROUP_NAME"; then
        
        aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME"
        log_success "Deleted CloudWatch log group: $LOG_GROUP_NAME"
    else
        log_warning "CloudWatch log group $LOG_GROUP_NAME not found"
    fi
}

# Clean up any remaining resources by searching for project prefix
cleanup_remaining_resources() {
    log "Searching for any remaining resources with project prefix..."
    
    # Check for any IAM policies with the project prefix
    REMAINING_POLICIES=$(aws iam list-policies \
        --scope Local \
        --query "Policies[?starts_with(PolicyName, \`${PROJECT_NAME}\`)].PolicyName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$REMAINING_POLICIES" ]]; then
        log_warning "Found remaining IAM policies: $REMAINING_POLICIES"
        for policy_name in $REMAINING_POLICIES; do
            POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
            aws iam delete-policy --policy-arn "$POLICY_ARN" 2>/dev/null || true
            log_success "Deleted remaining policy: $policy_name"
        done
    fi
    
    # Check for any IAM users with the project prefix
    REMAINING_USERS=$(aws iam list-users \
        --query "Users[?starts_with(UserName, \`${PROJECT_NAME}\`)].UserName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$REMAINING_USERS" ]]; then
        log_warning "Found remaining IAM users: $REMAINING_USERS"
        for user_name in $REMAINING_USERS; do
            # Force cleanup of any attached policies and access keys
            aws iam list-attached-user-policies --user-name "$user_name" --query 'AttachedPolicies[].PolicyArn' --output text | \
            while read -r policy_arn; do
                [[ -n "$policy_arn" ]] && aws iam detach-user-policy --user-name "$user_name" --policy-arn "$policy_arn" 2>/dev/null || true
            done
            
            aws iam list-access-keys --user-name "$user_name" --query 'AccessKeyMetadata[].AccessKeyId' --output text | \
            while read -r access_key; do
                [[ -n "$access_key" ]] && aws iam delete-access-key --user-name "$user_name" --access-key-id "$access_key" 2>/dev/null || true
            done
            
            aws iam delete-user --user-name "$user_name" 2>/dev/null || true
            log_success "Deleted remaining user: $user_name"
        done
    fi
    
    # Check for any IAM roles with the project prefix
    REMAINING_ROLES=$(aws iam list-roles \
        --query "Roles[?starts_with(RoleName, \`${PROJECT_NAME}\`)].RoleName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$REMAINING_ROLES" ]]; then
        log_warning "Found remaining IAM roles: $REMAINING_ROLES"
        for role_name in $REMAINING_ROLES; do
            # Force cleanup of any attached policies
            aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text | \
            while read -r policy_arn; do
                [[ -n "$policy_arn" ]] && aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null || true
            done
            
            aws iam delete-role --role-name "$role_name" 2>/dev/null || true
            log_success "Deleted remaining role: $role_name"
        done
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove policy files
    rm -f business-hours-policy.json
    rm -f ip-restriction-policy.json
    rm -f tag-based-policy.json
    rm -f mfa-required-policy.json
    rm -f session-policy.json
    rm -f trust-policy.json
    rm -f bucket-policy.json
    rm -f test-file.txt
    rm -f shared-file.txt
    
    # Remove deployment info
    if [[ "$FORCE_DELETE" == "false" ]]; then
        read -p "Remove deployment-info.json? (y/n): " REMOVE_INFO
        if [[ "$REMOVE_INFO" =~ ^[Yy]$ ]]; then
            rm -f deployment-info.json
            log_success "Removed deployment-info.json"
        fi
    else
        rm -f deployment-info.json
        log_success "Removed deployment-info.json"
    fi
    
    log_success "Cleaned up local files"
}

# Main cleanup function
main() {
    log "Starting Fine-Grained Access Control IAM cleanup..."
    log "=================================================="
    
    check_prerequisites
    load_deployment_info
    confirm_deletion
    
    # Clean up resources in reverse order of creation
    cleanup_iam_policies
    cleanup_iam_principals
    cleanup_s3_resources
    cleanup_cloudwatch_resources
    cleanup_remaining_resources
    cleanup_local_files
    
    log "=================================================="
    log_success "Cleanup completed successfully!"
    log ""
    log "All resources have been removed:"
    log "  ✅ IAM Policies deleted"
    log "  ✅ IAM Users and Roles deleted"
    log "  ✅ S3 Bucket and contents deleted"
    log "  ✅ CloudWatch Log Group deleted"
    log "  ✅ Local files cleaned up"
    log ""
    log "Your AWS account has been restored to its previous state."
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warning "Script interrupted. Some resources may remain."
    log "You can run this script again to complete the cleanup."
    exit 1
}

# Set trap for interruption
trap cleanup_on_interrupt INT TERM

# Run main function
main "$@"