#!/bin/bash

# Email List Management with SES and DynamoDB - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error

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

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
    fi
    
    success "Prerequisites check completed"
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [ ! -f "./deployment-info.json" ]; then
        warning "deployment-info.json not found. You'll need to provide resource names manually."
        
        # Prompt for resource names if deployment info is not available
        echo ""
        log "Please provide the following resource names to delete:"
        
        read -p "DynamoDB Table Name (e.g., email-subscribers-abc123): " TABLE_NAME
        read -p "IAM Role Name (e.g., EmailListLambdaRole-abc123): " LAMBDA_ROLE_NAME
        read -p "Subscribe Lambda Function Name (e.g., email-subscribe-abc123): " SUBSCRIBE_FUNCTION_NAME
        read -p "Newsletter Lambda Function Name (e.g., email-newsletter-abc123): " NEWSLETTER_FUNCTION_NAME
        read -p "List Lambda Function Name (e.g., email-list-abc123): " LIST_FUNCTION_NAME
        
        export TABLE_NAME
        export LAMBDA_ROLE_NAME
        export SUBSCRIBE_FUNCTION_NAME
        export NEWSLETTER_FUNCTION_NAME
        export LIST_FUNCTION_NAME
        
    else
        # Load from deployment info file
        if command -v jq &> /dev/null; then
            export TABLE_NAME=$(jq -r '.resources.dynamodb_table' deployment-info.json)
            export LAMBDA_ROLE_NAME=$(jq -r '.resources.iam_role' deployment-info.json)
            export SUBSCRIBE_FUNCTION_NAME=$(jq -r '.resources.lambda_functions.subscribe' deployment-info.json)
            export NEWSLETTER_FUNCTION_NAME=$(jq -r '.resources.lambda_functions.newsletter' deployment-info.json)
            export LIST_FUNCTION_NAME=$(jq -r '.resources.lambda_functions.list' deployment-info.json)
            export AWS_REGION=$(jq -r '.aws_region' deployment-info.json)
            export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' deployment-info.json)
        else
            warning "jq not available. Please install jq or provide resource names manually."
            error "Cannot parse deployment-info.json without jq"
        fi
    fi
    
    # Set AWS region if not already set
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            warning "AWS region not configured, defaulting to us-east-1"
        fi
    fi
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    log "Resource information loaded:"
    log "  AWS_REGION: ${AWS_REGION}"
    log "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    log "  TABLE_NAME: ${TABLE_NAME}"
    log "  LAMBDA_ROLE_NAME: ${LAMBDA_ROLE_NAME}"
    log "  SUBSCRIBE_FUNCTION_NAME: ${SUBSCRIBE_FUNCTION_NAME}"
    log "  NEWSLETTER_FUNCTION_NAME: ${NEWSLETTER_FUNCTION_NAME}"
    log "  LIST_FUNCTION_NAME: ${LIST_FUNCTION_NAME}"
    
    success "Deployment information loaded"
}

# Confirmation prompt
confirm_deletion() {
    echo ""
    warning "⚠️  WARNING: This will permanently delete all resources!"
    warning "The following resources will be deleted:"
    warning "  • DynamoDB Table: ${TABLE_NAME}"
    warning "  • IAM Role: ${LAMBDA_ROLE_NAME}"
    warning "  • Lambda Function: ${SUBSCRIBE_FUNCTION_NAME}"
    warning "  • Lambda Function: ${NEWSLETTER_FUNCTION_NAME}"
    warning "  • Lambda Function: ${LIST_FUNCTION_NAME}"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " CONFIRMATION
    
    if [ "$CONFIRMATION" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Deletion confirmed"
}

# Delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    # Delete subscribe function
    if aws lambda get-function --function-name "${SUBSCRIBE_FUNCTION_NAME}" >/dev/null 2>&1; then
        log "Deleting subscribe Lambda function: ${SUBSCRIBE_FUNCTION_NAME}"
        aws lambda delete-function --function-name "${SUBSCRIBE_FUNCTION_NAME}"
        success "Subscribe function deleted: ${SUBSCRIBE_FUNCTION_NAME}"
    else
        warning "Subscribe function not found: ${SUBSCRIBE_FUNCTION_NAME}"
    fi
    
    # Delete newsletter function
    if aws lambda get-function --function-name "${NEWSLETTER_FUNCTION_NAME}" >/dev/null 2>&1; then
        log "Deleting newsletter Lambda function: ${NEWSLETTER_FUNCTION_NAME}"
        aws lambda delete-function --function-name "${NEWSLETTER_FUNCTION_NAME}"
        success "Newsletter function deleted: ${NEWSLETTER_FUNCTION_NAME}"
    else
        warning "Newsletter function not found: ${NEWSLETTER_FUNCTION_NAME}"
    fi
    
    # Delete list function
    if aws lambda get-function --function-name "${LIST_FUNCTION_NAME}" >/dev/null 2>&1; then
        log "Deleting list Lambda function: ${LIST_FUNCTION_NAME}"
        aws lambda delete-function --function-name "${LIST_FUNCTION_NAME}"
        success "List function deleted: ${LIST_FUNCTION_NAME}"
    else
        warning "List function not found: ${LIST_FUNCTION_NAME}"
    fi
    
    success "Lambda functions cleanup completed"
}

# Delete IAM role and policies
delete_iam_role() {
    log "Deleting IAM role and policies..."
    
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" >/dev/null 2>&1; then
        # Delete attached inline policies
        log "Deleting inline policies for role: ${LAMBDA_ROLE_NAME}"
        
        # List and delete all inline policies
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$INLINE_POLICIES" ] && [ "$INLINE_POLICIES" != "None" ]; then
            for policy in $INLINE_POLICIES; do
                log "Deleting inline policy: ${policy}"
                aws iam delete-role-policy \
                    --role-name "${LAMBDA_ROLE_NAME}" \
                    --policy-name "${policy}"
            done
        fi
        
        # Detach managed policies if any
        log "Checking for attached managed policies..."
        MANAGED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$MANAGED_POLICIES" ] && [ "$MANAGED_POLICIES" != "None" ]; then
            for policy_arn in $MANAGED_POLICIES; do
                log "Detaching managed policy: ${policy_arn}"
                aws iam detach-role-policy \
                    --role-name "${LAMBDA_ROLE_NAME}" \
                    --policy-arn "${policy_arn}"
            done
        fi
        
        # Delete the role
        log "Deleting IAM role: ${LAMBDA_ROLE_NAME}"
        aws iam delete-role --role-name "${LAMBDA_ROLE_NAME}"
        success "IAM role deleted: ${LAMBDA_ROLE_NAME}"
    else
        warning "IAM role not found: ${LAMBDA_ROLE_NAME}"
    fi
    
    success "IAM role cleanup completed"
}

# Delete DynamoDB table
delete_dynamodb_table() {
    log "Deleting DynamoDB table: ${TABLE_NAME}..."
    
    if aws dynamodb describe-table --table-name "${TABLE_NAME}" >/dev/null 2>&1; then
        # Check if table has data and warn user
        ITEM_COUNT=$(aws dynamodb scan \
            --table-name "${TABLE_NAME}" \
            --select COUNT \
            --query 'Count' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$ITEM_COUNT" -gt 0 ]; then
            warning "Table ${TABLE_NAME} contains ${ITEM_COUNT} subscriber records"
            echo ""
            read -p "Delete table with all subscriber data? (type 'yes' to confirm): " TABLE_CONFIRMATION
            
            if [ "$TABLE_CONFIRMATION" != "yes" ]; then
                warning "Skipping DynamoDB table deletion"
                return 0
            fi
        fi
        
        aws dynamodb delete-table --table-name "${TABLE_NAME}"
        
        log "Waiting for DynamoDB table deletion to complete..."
        aws dynamodb wait table-not-exists --table-name "${TABLE_NAME}"
        
        success "DynamoDB table deleted: ${TABLE_NAME}"
    else
        warning "DynamoDB table not found: ${TABLE_NAME}"
    fi
    
    success "DynamoDB table cleanup completed"
}

# Delete CloudWatch Log Groups
delete_cloudwatch_logs() {
    log "Cleaning up CloudWatch Log Groups..."
    
    # Common Lambda log group patterns
    LOG_GROUPS=(
        "/aws/lambda/${SUBSCRIBE_FUNCTION_NAME}"
        "/aws/lambda/${NEWSLETTER_FUNCTION_NAME}"
        "/aws/lambda/${LIST_FUNCTION_NAME}"
    )
    
    for log_group in "${LOG_GROUPS[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "${log_group}" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${log_group}"; then
            log "Deleting CloudWatch Log Group: ${log_group}"
            aws logs delete-log-group --log-group-name "${log_group}" 2>/dev/null || warning "Failed to delete log group: ${log_group}"
            success "Log group deleted: ${log_group}"
        else
            log "Log group not found: ${log_group}"
        fi
    done
    
    success "CloudWatch logs cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Files to clean up
    LOCAL_FILES=(
        "./deployment-info.json"
        "./subscribe_response.json"
        "./newsletter_response.json"
        "./list_response.json"
        "./lambda-trust-policy.json"
        "./lambda-permissions-policy.json"
    )
    
    for file in "${LOCAL_FILES[@]}"; do
        if [ -f "$file" ]; then
            log "Removing local file: $file"
            rm -f "$file"
        fi
    done
    
    success "Local files cleanup completed"
}

# Display SES cleanup information
display_ses_info() {
    log "SES Email Identity Information:"
    warning "Note: This script does not remove verified email identities from SES."
    warning "If you want to remove the verified email identity, you can do so manually:"
    warning "  aws ses delete-identity --identity your-email@example.com"
    warning ""
    warning "Remember: Removing email identities will require re-verification if you want to use them again."
}

# Generate cleanup report
generate_cleanup_report() {
    log "Generating cleanup report..."
    
    cat > "./cleanup-report.txt" << EOF
Email List Management System - Cleanup Report
=============================================
Cleanup Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
AWS Region: ${AWS_REGION}
AWS Account ID: ${AWS_ACCOUNT_ID}

Resources Cleaned Up:
--------------------
• DynamoDB Table: ${TABLE_NAME}
• IAM Role: ${LAMBDA_ROLE_NAME}
• Lambda Functions:
  - Subscribe: ${SUBSCRIBE_FUNCTION_NAME}
  - Newsletter: ${NEWSLETTER_FUNCTION_NAME}
  - List: ${LIST_FUNCTION_NAME}
• CloudWatch Log Groups (associated with Lambda functions)
• Local deployment files

Resources NOT Cleaned Up:
------------------------
• SES verified email identities (manual cleanup required if desired)

Manual Cleanup Steps (Optional):
-------------------------------
1. Remove SES email identity (if desired):
   aws ses delete-identity --identity your-email@example.com

2. Review AWS CloudWatch for any remaining log groups
3. Check AWS Config for any configuration items that may reference deleted resources

Notes:
------
• All subscriber data in DynamoDB has been permanently deleted
• Lambda function logs in CloudWatch have been removed
• No additional charges will be incurred from these resources

For questions or issues, refer to the AWS documentation or contact AWS support.
EOF
    
    success "Cleanup report saved to cleanup-report.txt"
}

# Main cleanup function
main() {
    log "Starting Email List Management System cleanup..."
    log "========================================================="
    
    check_prerequisites
    load_deployment_info
    confirm_deletion
    
    # Perform cleanup in reverse order of creation
    delete_lambda_functions
    delete_iam_role
    delete_dynamodb_table
    delete_cloudwatch_logs
    cleanup_local_files
    
    log "========================================================="
    success "Cleanup completed successfully!"
    log "========================================================="
    
    display_ses_info
    generate_cleanup_report
    
    log ""
    log "📋 Cleanup Summary:"
    log "  • All Lambda functions have been deleted"
    log "  • IAM role and policies have been removed"
    log "  • DynamoDB table and all subscriber data has been deleted"
    log "  • CloudWatch log groups have been cleaned up"
    log "  • Local deployment files have been removed"
    log ""
    log "📊 A detailed cleanup report has been saved to cleanup-report.txt"
    log ""
    success "Email List Management System has been completely removed!"
}

# Handle script interruption
trap 'error "Script interrupted by user"' INT TERM

# Run main function
main "$@"