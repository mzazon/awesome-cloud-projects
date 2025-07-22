#!/bin/bash

# Enterprise KMS Envelope Encryption with Key Rotation - Destruction Script
# Recipe: enterprise-kms-envelope-encryption-key-rotation
# Version: 1.0
# Description: Safely removes all infrastructure created by the deployment script

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destruction.log"
readonly ENV_FILE="${SCRIPT_DIR}/.deployment_env"

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Load environment variables from deployment
load_environment() {
    print_status "$BLUE" "[INFO] Loading deployment environment..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        print_status "$RED" "[ERROR] Deployment environment file not found: $ENV_FILE"
        print_status "$YELLOW" "[HINT] This might indicate the infrastructure was not deployed using deploy.sh"
        print_status "$YELLOW" "[HINT] Or the environment file has been deleted"
        exit 1
    fi
    
    # Source environment variables
    source "$ENV_FILE"
    
    # Validate required variables
    local required_vars=(
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "KMS_KEY_ALIAS"
        "S3_BUCKET_NAME"
        "LAMBDA_FUNCTION_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            print_status "$RED" "[ERROR] Required environment variable $var is not set"
            exit 1
        fi
    done
    
    log "INFO" "Environment variables loaded:"
    log "INFO" "  AWS_REGION: $AWS_REGION"
    log "INFO" "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    log "INFO" "  KMS_KEY_ALIAS: $KMS_KEY_ALIAS"
    log "INFO" "  S3_BUCKET_NAME: $S3_BUCKET_NAME"
    log "INFO" "  LAMBDA_FUNCTION_NAME: $LAMBDA_FUNCTION_NAME"
    
    print_status "$GREEN" "✅ Environment variables loaded successfully"
}

# Validate AWS CLI and authentication
validate_aws_prerequisites() {
    print_status "$BLUE" "[INFO] Validating AWS prerequisites..."
    
    if ! command_exists aws; then
        print_status "$RED" "[ERROR] AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Test AWS authentication
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_status "$RED" "[ERROR] AWS CLI is not configured or lacks permissions"
        print_status "$YELLOW" "[HINT] Run 'aws configure' to set up your credentials"
        exit 1
    fi
    
    local current_account
    current_account=$(aws sts get-caller-identity --query Account --output text)
    
    if [[ "$current_account" != "$AWS_ACCOUNT_ID" ]]; then
        print_status "$RED" "[ERROR] Current AWS account ($current_account) does not match deployment account ($AWS_ACCOUNT_ID)"
        print_status "$YELLOW" "[HINT] Ensure you're using the correct AWS credentials"
        exit 1
    fi
    
    print_status "$GREEN" "✅ AWS prerequisites validated"
}

# Confirmation prompt
confirm_destruction() {
    print_status "$YELLOW" "\n⚠️  WARNING: This will permanently delete the following resources:"
    cat << EOF

🔐 KMS Resources:
   • Customer Master Key: alias/$KMS_KEY_ALIAS
   • Key will be scheduled for deletion (7-day waiting period)

📦 S3 Resources:
   • Bucket: $S3_BUCKET_NAME
   • All objects and versions will be permanently deleted

⚡ Lambda Resources:
   • Function: $LAMBDA_FUNCTION_NAME
   • CloudWatch logs and metrics

🔧 IAM Resources:
   • Role: ${LAMBDA_FUNCTION_NAME}-role
   • Policy: ${LAMBDA_FUNCTION_NAME}-kms-policy

📊 CloudWatch Resources:
   • Events rule: ${LAMBDA_FUNCTION_NAME}-schedule
   • Log group: /aws/lambda/${LAMBDA_FUNCTION_NAME}

EOF
    
    print_status "$RED" "This action cannot be undone!"
    
    read -p "Do you want to continue? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        print_status "$YELLOW" "[INFO] Destruction cancelled by user"
        exit 0
    fi
    
    log "INFO" "User confirmed destruction of infrastructure"
}

# Remove CloudWatch Events rule
remove_cloudwatch_events() {
    print_status "$BLUE" "[INFO] Removing CloudWatch Events rule..."
    
    # Check if rule exists
    if aws events describe-rule --name "${LAMBDA_FUNCTION_NAME}-schedule" >/dev/null 2>&1; then
        # Remove Lambda permission for CloudWatch Events
        aws lambda remove-permission \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --statement-id allow-cloudwatch-events 2>/dev/null || {
            log "WARN" "Failed to remove Lambda permission for CloudWatch Events (may not exist)"
        }
        
        # Remove targets from rule
        aws events remove-targets \
            --rule "${LAMBDA_FUNCTION_NAME}-schedule" \
            --ids "1" 2>/dev/null || {
            log "WARN" "Failed to remove targets from CloudWatch Events rule"
        }
        
        # Delete the rule
        aws events delete-rule \
            --name "${LAMBDA_FUNCTION_NAME}-schedule"
        
        log "INFO" "CloudWatch Events rule removed: ${LAMBDA_FUNCTION_NAME}-schedule"
        print_status "$GREEN" "✅ CloudWatch Events rule removed"
    else
        log "WARN" "CloudWatch Events rule not found: ${LAMBDA_FUNCTION_NAME}-schedule"
        print_status "$YELLOW" "[WARN] CloudWatch Events rule not found (may have been deleted already)"
    fi
}

# Remove Lambda function
remove_lambda_function() {
    print_status "$BLUE" "[INFO] Removing Lambda function..."
    
    # Check if function exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        # Delete Lambda function
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
        
        log "INFO" "Lambda function deleted: $LAMBDA_FUNCTION_NAME"
        print_status "$GREEN" "✅ Lambda function removed"
    else
        log "WARN" "Lambda function not found: $LAMBDA_FUNCTION_NAME"
        print_status "$YELLOW" "[WARN] Lambda function not found (may have been deleted already)"
    fi
    
    # Remove CloudWatch log group
    if aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1; then
        aws logs delete-log-group \
            --log-group-name "/aws/lambda/${LAMBDA_FUNCTION_NAME}" || {
            log "WARN" "Failed to delete CloudWatch log group (may not exist)"
        }
        log "INFO" "CloudWatch log group deleted: /aws/lambda/${LAMBDA_FUNCTION_NAME}"
    fi
}

# Remove IAM resources
remove_iam_resources() {
    print_status "$BLUE" "[INFO] Removing IAM resources..."
    
    local role_name="${LAMBDA_FUNCTION_NAME}-role"
    local policy_name="${LAMBDA_FUNCTION_NAME}-kms-policy"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
    
    # Check if role exists
    if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy_arn" 2>/dev/null || {
            log "WARN" "Failed to detach custom policy from role (may not be attached)"
        }
        
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || {
            log "WARN" "Failed to detach basic execution policy from role (may not be attached)"
        }
        
        # Delete the role
        aws iam delete-role --role-name "$role_name"
        log "INFO" "IAM role deleted: $role_name"
    else
        log "WARN" "IAM role not found: $role_name"
    fi
    
    # Delete custom policy
    if aws iam get-policy --policy-arn "$policy_arn" >/dev/null 2>&1; then
        aws iam delete-policy --policy-arn "$policy_arn"
        log "INFO" "IAM policy deleted: $policy_name"
    else
        log "WARN" "IAM policy not found: $policy_name"
    fi
    
    print_status "$GREEN" "✅ IAM resources removed"
}

# Remove S3 bucket and contents
remove_s3_bucket() {
    print_status "$BLUE" "[INFO] Removing S3 bucket and contents..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
        # Delete all object versions and delete markers
        aws s3api list-object-versions --bucket "$S3_BUCKET_NAME" --output json | \
        jq -r '.Versions[]?, .DeleteMarkers[]? | "\(.Key)\t\(.VersionId)"' | \
        while IFS=$'\t' read -r key version; do
            if [[ -n "$key" && -n "$version" ]]; then
                aws s3api delete-object \
                    --bucket "$S3_BUCKET_NAME" \
                    --key "$key" \
                    --version-id "$version" >/dev/null 2>&1 || true
            fi
        done
        
        # Delete any remaining objects
        aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive 2>/dev/null || true
        
        # Delete the bucket
        aws s3 rb "s3://${S3_BUCKET_NAME}" --force
        
        log "INFO" "S3 bucket deleted: $S3_BUCKET_NAME"
        print_status "$GREEN" "✅ S3 bucket and contents removed"
    else
        log "WARN" "S3 bucket not found: $S3_BUCKET_NAME"
        print_status "$YELLOW" "[WARN] S3 bucket not found (may have been deleted already)"
    fi
}

# Schedule KMS key deletion
remove_kms_key() {
    print_status "$BLUE" "[INFO] Scheduling KMS key deletion..."
    
    # Check if key alias exists
    if aws kms describe-key --key-id "alias/${KMS_KEY_ALIAS}" >/dev/null 2>&1; then
        # Get the actual key ID
        local key_id
        key_id=$(aws kms describe-key \
            --key-id "alias/${KMS_KEY_ALIAS}" \
            --query KeyMetadata.KeyId --output text)
        
        # Schedule key deletion (7-day waiting period)
        aws kms schedule-key-deletion \
            --key-id "$key_id" \
            --pending-window-in-days 7
        
        # Delete key alias
        aws kms delete-alias --alias-name "alias/${KMS_KEY_ALIAS}"
        
        log "INFO" "KMS key scheduled for deletion: $key_id"
        log "INFO" "KMS key alias deleted: alias/$KMS_KEY_ALIAS"
        
        print_status "$GREEN" "✅ KMS key scheduled for deletion (7-day waiting period)"
        print_status "$YELLOW" "[INFO] Key will be permanently deleted after 7 days"
    else
        log "WARN" "KMS key not found: alias/$KMS_KEY_ALIAS"
        print_status "$YELLOW" "[WARN] KMS key not found (may have been deleted already)"
    fi
}

# Clean up local files
cleanup_local_files() {
    print_status "$BLUE" "[INFO] Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/.deployment_env"
        "${SCRIPT_DIR}/.cmk_id"
        "${SCRIPT_DIR}/.lambda_arn"
        "${SCRIPT_DIR}/deployment.log"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "INFO" "Removed file: $file"
        fi
    done
    
    print_status "$GREEN" "✅ Local files cleaned up"
}

# Verify destruction
verify_destruction() {
    print_status "$BLUE" "[INFO] Verifying resource removal..."
    
    local issues_found=0
    
    # Check CloudWatch Events rule
    if aws events describe-rule --name "${LAMBDA_FUNCTION_NAME}-schedule" >/dev/null 2>&1; then
        print_status "$RED" "[ERROR] CloudWatch Events rule still exists"
        ((issues_found++))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        print_status "$RED" "[ERROR] Lambda function still exists"
        ((issues_found++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${LAMBDA_FUNCTION_NAME}-role" >/dev/null 2>&1; then
        print_status "$RED" "[ERROR] IAM role still exists"
        ((issues_found++))
    fi
    
    # Check IAM policy
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_FUNCTION_NAME}-kms-policy" >/dev/null 2>&1; then
        print_status "$RED" "[ERROR] IAM policy still exists"
        ((issues_found++))
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
        print_status "$RED" "[ERROR] S3 bucket still exists"
        ((issues_found++))
    fi
    
    # Check KMS key (should be in PendingDeletion state)
    local key_state
    key_state=$(aws kms describe-key --key-id "alias/${KMS_KEY_ALIAS}" --query KeyMetadata.KeyState --output text 2>/dev/null || echo "NotFound")
    
    if [[ "$key_state" != "NotFound" && "$key_state" != "PendingDeletion" ]]; then
        print_status "$RED" "[ERROR] KMS key is not scheduled for deletion (state: $key_state)"
        ((issues_found++))
    fi
    
    if [[ $issues_found -eq 0 ]]; then
        print_status "$GREEN" "✅ All resources removed successfully"
    else
        print_status "$RED" "[ERROR] $issues_found issues found during verification"
        print_status "$YELLOW" "[HINT] You may need to manually remove remaining resources"
        exit 1
    fi
}

# Print destruction summary
print_summary() {
    print_status "$GREEN" "\n🗑️  Destruction completed successfully!"
    
    cat << EOF

📋 DESTRUCTION SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Resources Removed:
   • CloudWatch Events rule: ${LAMBDA_FUNCTION_NAME}-schedule
   • Lambda function: $LAMBDA_FUNCTION_NAME
   • IAM role: ${LAMBDA_FUNCTION_NAME}-role
   • IAM policy: ${LAMBDA_FUNCTION_NAME}-kms-policy
   • S3 bucket: $S3_BUCKET_NAME (all contents deleted)
   • KMS key alias: alias/$KMS_KEY_ALIAS

⏰ Scheduled for Deletion:
   • KMS Customer Master Key (7-day waiting period)
   
🧹 Cleaned Up:
   • Local configuration files
   • Deployment environment file
   • Temporary resources

📊 Final Status:
   • All AWS resources successfully removed or scheduled for deletion
   • No ongoing charges (except potential S3 storage costs until final deletion)
   • Infrastructure completely dismantled

⚠️  Important Notes:
   • KMS key will be permanently deleted after 7 days
   • During the waiting period, you can cancel deletion if needed
   • All encrypted data will remain accessible until key deletion
   • After key deletion, encrypted data will be permanently unrecoverable

For more information about KMS key deletion, see:
https://docs.aws.amazon.com/kms/latest/developerguide/deleting-keys.html

EOF
}

# Main execution
main() {
    print_status "$BLUE" "🗑️  Starting Enterprise KMS Infrastructure Destruction"
    print_status "$BLUE" "=========================================================="
    
    log "INFO" "Destruction started at $(date)"
    
    load_environment
    validate_aws_prerequisites
    confirm_destruction
    
    remove_cloudwatch_events
    remove_lambda_function
    remove_iam_resources
    remove_s3_bucket
    remove_kms_key
    cleanup_local_files
    verify_destruction
    print_summary
    
    log "INFO" "Destruction completed successfully at $(date)"
}

# Handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_status "$RED" "\n[ERROR] Destruction process interrupted or failed"
        print_status "$YELLOW" "[HINT] Check ${LOG_FILE} for details"
        print_status "$YELLOW" "[HINT] Some resources may need manual cleanup"
    fi
}

trap cleanup_on_exit EXIT

# Execute main function
main "$@"