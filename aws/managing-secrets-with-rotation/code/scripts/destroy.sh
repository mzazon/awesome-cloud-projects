#!/bin/bash

# Destroy script for AWS Secrets Manager Recipe
# This script safely removes all resources created by the deployment

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured or you don't have access. Please run 'aws configure' first."
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS authentication
    check_aws_auth
    
    log "Prerequisites check completed successfully"
}

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local check_command=$3
    
    if eval "$check_command" >/dev/null 2>&1; then
        return 0  # Resource exists
    else
        return 1  # Resource does not exist
    fi
}

# Function to safely delete a resource
safe_delete() {
    local resource_type=$1
    local resource_name=$2
    local delete_command=$3
    local check_command=$4
    
    info "Checking if $resource_type '$resource_name' exists..."
    
    if resource_exists "$resource_type" "$resource_name" "$check_command"; then
        info "Deleting $resource_type: $resource_name"
        
        # Execute the delete command
        if eval "$delete_command" >/dev/null 2>&1; then
            log "Successfully deleted $resource_type: $resource_name"
            return 0
        else
            error "Failed to delete $resource_type: $resource_name"
            return 1
        fi
    else
        warn "$resource_type '$resource_name' does not exist, skipping deletion"
        return 0
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local resource_name=$2
    local check_command=$3
    local max_attempts=30
    local attempt=1
    
    info "Waiting for $resource_type deletion to complete..."
    
    while [ $attempt -le $max_attempts ]; do
        if ! resource_exists "$resource_type" "$resource_name" "$check_command"; then
            log "$resource_type deletion completed"
            return 0
        fi
        
        info "Attempt $attempt/$max_attempts: $resource_type still exists, waiting..."
        sleep 10
        ((attempt++))
    done
    
    error "$resource_type deletion did not complete within expected time"
    return 1
}

# Function to confirm destructive action
confirm_destruction() {
    local resource_count=$1
    
    echo
    warn "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo
    info "This script will permanently delete the following resources:"
    info "- AWS Secrets Manager secret and all versions"
    info "- Lambda function for secret rotation"
    info "- IAM role and custom policies"
    info "- KMS key and alias (7-day deletion window)"
    info "- CloudWatch dashboard and alarms"
    info "- All temporary files and deployment state"
    echo
    warn "This action cannot be undone!"
    echo
    
    if [ "$FORCE_DELETE" = true ]; then
        info "Force delete enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed, proceeding..."
}

# Function to load deployment state
load_deployment_state() {
    if [ ! -f ".deployment_state" ]; then
        error "Deployment state file not found. Cannot determine resources to delete."
        error "Please ensure you're running this script from the same directory where you ran deploy.sh"
        exit 1
    fi
    
    info "Loading deployment state..."
    source .deployment_state
    
    # Verify required variables are set
    if [ -z "${SECRET_NAME:-}" ] || [ -z "${LAMBDA_FUNCTION_NAME:-}" ] || [ -z "${IAM_ROLE_NAME:-}" ] || [ -z "${KMS_KEY_ID:-}" ]; then
        error "Deployment state file is incomplete or corrupted"
        exit 1
    fi
    
    log "Deployment state loaded successfully"
    log "Secret Name: $SECRET_NAME"
    log "Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "IAM Role: $IAM_ROLE_NAME"
    log "KMS Key: $KMS_KEY_ID"
    log "Random Suffix: $RANDOM_SUFFIX"
}

# Function to cancel secret rotation
cancel_rotation() {
    info "Canceling secret rotation..."
    
    # Check if rotation is in progress
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --query 'RotationEnabled' --output text 2>/dev/null | grep -q "True"; then
        info "Secret rotation is enabled, attempting to cancel..."
        
        # Try to cancel rotation (this may fail if no rotation is in progress)
        if aws secretsmanager cancel-rotate-secret --secret-id "$SECRET_NAME" 2>/dev/null; then
            log "Secret rotation cancelled successfully"
        else
            warn "No rotation in progress or rotation already completed"
        fi
    else
        info "Secret rotation is not enabled, no need to cancel"
    fi
}

# Function to delete secrets manager resources
delete_secrets_manager_resources() {
    info "Deleting Secrets Manager resources..."
    
    # Cancel any ongoing rotation first
    cancel_rotation
    
    # Delete the secret with force (bypasses 7-day recovery window)
    safe_delete "Secret" "$SECRET_NAME" \
        "aws secretsmanager delete-secret --secret-id '$SECRET_NAME' --force-delete-without-recovery" \
        "aws secretsmanager describe-secret --secret-id '$SECRET_NAME'"
}

# Function to delete Lambda resources
delete_lambda_resources() {
    info "Deleting Lambda resources..."
    
    # Remove Lambda permission for Secrets Manager
    info "Removing Lambda permission for Secrets Manager..."
    if aws lambda get-policy --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        aws lambda remove-permission \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --statement-id SecretsManagerInvoke 2>/dev/null || true
    fi
    
    # Delete Lambda function
    safe_delete "Lambda Function" "$LAMBDA_FUNCTION_NAME" \
        "aws lambda delete-function --function-name '$LAMBDA_FUNCTION_NAME'" \
        "aws lambda get-function --function-name '$LAMBDA_FUNCTION_NAME'"
}

# Function to delete IAM resources
delete_iam_resources() {
    info "Deleting IAM resources..."
    
    # Detach managed policies
    info "Detaching managed policies from IAM role..."
    aws iam detach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
    
    aws iam detach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SecretsManagerRotationPolicy-${RANDOM_SUFFIX}" 2>/dev/null || true
    
    # Delete custom policy
    safe_delete "IAM Policy" "SecretsManagerRotationPolicy-${RANDOM_SUFFIX}" \
        "aws iam delete-policy --policy-arn 'arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SecretsManagerRotationPolicy-${RANDOM_SUFFIX}'" \
        "aws iam get-policy --policy-arn 'arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SecretsManagerRotationPolicy-${RANDOM_SUFFIX}'"
    
    # Delete IAM role
    safe_delete "IAM Role" "$IAM_ROLE_NAME" \
        "aws iam delete-role --role-name '$IAM_ROLE_NAME'" \
        "aws iam get-role --role-name '$IAM_ROLE_NAME'"
}

# Function to delete KMS resources
delete_kms_resources() {
    info "Deleting KMS resources..."
    
    # Delete KMS key alias
    safe_delete "KMS Alias" "$KMS_KEY_ALIAS" \
        "aws kms delete-alias --alias-name '$KMS_KEY_ALIAS'" \
        "aws kms describe-key --key-id '$KMS_KEY_ALIAS'"
    
    # Schedule KMS key deletion
    info "Scheduling KMS key deletion..."
    if aws kms describe-key --key-id "$KMS_KEY_ID" >/dev/null 2>&1; then
        # Check if key is already scheduled for deletion
        KEY_STATE=$(aws kms describe-key --key-id "$KMS_KEY_ID" --query 'KeyMetadata.KeyState' --output text 2>/dev/null)
        
        if [ "$KEY_STATE" = "PendingDeletion" ]; then
            warn "KMS key is already scheduled for deletion"
        else
            aws kms schedule-key-deletion \
                --key-id "$KMS_KEY_ID" \
                --pending-window-in-days 7
            log "KMS key scheduled for deletion in 7 days: $KMS_KEY_ID"
        fi
    else
        warn "KMS key $KMS_KEY_ID does not exist, skipping deletion"
    fi
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    info "Deleting CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    safe_delete "CloudWatch Dashboard" "SecretsManager-${RANDOM_SUFFIX}" \
        "aws cloudwatch delete-dashboards --dashboard-names 'SecretsManager-${RANDOM_SUFFIX}'" \
        "aws cloudwatch get-dashboard --dashboard-name 'SecretsManager-${RANDOM_SUFFIX}'"
    
    # Delete CloudWatch alarm
    safe_delete "CloudWatch Alarm" "SecretsManager-RotationFailure-${RANDOM_SUFFIX}" \
        "aws cloudwatch delete-alarms --alarm-names 'SecretsManager-RotationFailure-${RANDOM_SUFFIX}'" \
        "aws cloudwatch describe-alarms --alarm-names 'SecretsManager-RotationFailure-${RANDOM_SUFFIX}'"
}

# Function to cleanup local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove temporary files
    local temp_files=(
        "/tmp/kms-key-id.txt"
        "/tmp/lambda-trust-policy.json"
        "/tmp/secrets-manager-policy.json"
        "/tmp/db-credentials.json"
        "/tmp/rotation_lambda.py"
        "/tmp/rotation_lambda.zip"
        "/tmp/cross-account-policy.json"
        "/tmp/app_integration.py"
        "/tmp/dashboard.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Removed temporary file: $file"
        fi
    done
    
    # Remove deployment state file
    if [ -f ".deployment_state" ]; then
        rm -f ".deployment_state"
        log "Removed deployment state file"
    fi
    
    log "Local cleanup completed"
}

# Function to verify complete deletion
verify_deletion() {
    info "Verifying resource deletion..."
    
    local failed_deletions=0
    
    # Check if secret still exists
    if resource_exists "Secret" "$SECRET_NAME" "aws secretsmanager describe-secret --secret-id '$SECRET_NAME'"; then
        error "Secret still exists: $SECRET_NAME"
        ((failed_deletions++))
    fi
    
    # Check if Lambda function still exists
    if resource_exists "Lambda Function" "$LAMBDA_FUNCTION_NAME" "aws lambda get-function --function-name '$LAMBDA_FUNCTION_NAME'"; then
        error "Lambda function still exists: $LAMBDA_FUNCTION_NAME"
        ((failed_deletions++))
    fi
    
    # Check if IAM role still exists
    if resource_exists "IAM Role" "$IAM_ROLE_NAME" "aws iam get-role --role-name '$IAM_ROLE_NAME'"; then
        error "IAM role still exists: $IAM_ROLE_NAME"
        ((failed_deletions++))
    fi
    
    # Check if custom policy still exists
    if resource_exists "IAM Policy" "SecretsManagerRotationPolicy-${RANDOM_SUFFIX}" "aws iam get-policy --policy-arn 'arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SecretsManagerRotationPolicy-${RANDOM_SUFFIX}'"; then
        error "Custom IAM policy still exists: SecretsManagerRotationPolicy-${RANDOM_SUFFIX}"
        ((failed_deletions++))
    fi
    
    if [ $failed_deletions -eq 0 ]; then
        log "✅ All resources successfully deleted"
        return 0
    else
        error "❌ $failed_deletions resource(s) failed to delete"
        return 1
    fi
}

# Main destroy function
destroy() {
    info "Starting AWS Secrets Manager resource destruction..."
    
    # Load deployment state
    load_deployment_state
    
    # Confirm destruction
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_cloudwatch_resources
    delete_secrets_manager_resources
    delete_lambda_resources
    delete_iam_resources
    delete_kms_resources
    cleanup_local_files
    
    # Verify deletion
    if verify_deletion; then
        echo
        log "🎉 Resource destruction completed successfully!"
        echo
        info "Destruction Summary:"
        info "==================="
        info "✅ Secret deleted: $SECRET_NAME"
        info "✅ Lambda function deleted: $LAMBDA_FUNCTION_NAME"
        info "✅ IAM role deleted: $IAM_ROLE_NAME"
        info "✅ KMS key scheduled for deletion: $KMS_KEY_ID"
        info "✅ CloudWatch resources deleted"
        info "✅ Local files cleaned up"
        echo
        info "Note: KMS key will be permanently deleted in 7 days"
        info "All other resources have been immediately removed"
        echo
    else
        error "Some resources may still exist. Please check the AWS console and manual cleanup if necessary."
        exit 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -v, --verbose        Enable verbose logging"
    echo "  -f, --force          Skip confirmation prompts"
    echo "  --dry-run           Show what would be deleted without actually deleting"
    echo "  --region REGION     Override AWS region (default: from deployment state)"
    echo ""
    echo "Examples:"
    echo "  $0                   Destroy with confirmation prompts"
    echo "  $0 --force           Destroy without confirmation"
    echo "  $0 --verbose         Destroy with verbose logging"
    echo "  $0 --dry-run         Show destruction plan without executing"
}

# Function to show dry run information
show_dry_run() {
    info "DRY RUN MODE - No resources will be deleted"
    echo
    info "This would delete the following resources:"
    
    if [ -f ".deployment_state" ]; then
        source .deployment_state
        echo
        info "Secrets Manager Resources:"
        info "- Secret: $SECRET_NAME"
        echo
        info "Lambda Resources:"
        info "- Function: $LAMBDA_FUNCTION_NAME"
        echo
        info "IAM Resources:"
        info "- Role: $IAM_ROLE_NAME"
        info "- Policy: SecretsManagerRotationPolicy-${RANDOM_SUFFIX}"
        echo
        info "KMS Resources:"
        info "- Key: $KMS_KEY_ID"
        info "- Alias: $KMS_KEY_ALIAS"
        echo
        info "CloudWatch Resources:"
        info "- Dashboard: SecretsManager-${RANDOM_SUFFIX}"
        info "- Alarm: SecretsManager-RotationFailure-${RANDOM_SUFFIX}"
        echo
        info "Local Files:"
        info "- Deployment state file"
        info "- Temporary files in /tmp/"
    else
        warn "No deployment state file found. No resources to delete."
    fi
}

# Parse command line arguments
FORCE_DELETE=false
VERBOSE=false
DRY_RUN=false
CUSTOM_REGION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --region)
            CUSTOM_REGION="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Enable verbose logging if requested
if [ "$VERBOSE" = true ]; then
    set -x
fi

# Override region if specified
if [ -n "$CUSTOM_REGION" ]; then
    export AWS_DEFAULT_REGION="$CUSTOM_REGION"
fi

# Main execution
main() {
    if [ "$DRY_RUN" = true ]; then
        show_dry_run
        exit 0
    fi
    
    log "Starting AWS Secrets Manager destruction script"
    check_prerequisites
    destroy
    log "Destruction script completed successfully"
}

# Run main function
main "$@"