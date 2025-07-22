#!/bin/bash

#
# destroy.sh - S3 Inventory and Storage Analytics Cleanup Script
#
# This script safely removes all AWS resources created by the S3 Inventory 
# and Storage Analytics deployment, including S3 buckets, Lambda functions,
# IAM roles, EventBridge rules, and CloudWatch dashboards.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for resource deletion
# - deployment-summary.txt file from successful deployment
#
# Usage:
#   chmod +x destroy.sh
#   ./destroy.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if resource exists functions
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "${resource_type}" in
        "s3-bucket")
            aws s3 ls "s3://${resource_name}" &>/dev/null
            ;;
        "lambda-function")
            aws lambda get-function --function-name "${resource_name}" &>/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "${resource_name}" &>/dev/null
            ;;
        "eventbridge-rule")
            aws events describe-rule --name "${resource_name}" &>/dev/null
            ;;
        "cloudwatch-dashboard")
            aws cloudwatch get-dashboard --dashboard-name "${resource_name}" &>/dev/null
            ;;
        "athena-database")
            aws athena get-database --catalog-name AwsDataCatalog --database-name "${resource_name}" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Load deployment configuration
load_deployment_config() {
    log_info "Loading deployment configuration..."
    
    if [[ ! -f "deployment-summary.txt" ]]; then
        log_warning "deployment-summary.txt not found. Attempting to load from environment variables..."
        
        # Try to extract from environment or prompt user
        if [[ -z "${SOURCE_BUCKET:-}" ]]; then
            read -p "Enter source bucket name: " SOURCE_BUCKET
        fi
        if [[ -z "${DEST_BUCKET:-}" ]]; then
            read -p "Enter destination bucket name: " DEST_BUCKET
        fi
        if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
            # Extract suffix from bucket name if possible
            if [[ "${SOURCE_BUCKET}" =~ storage-analytics-source-(.+)$ ]]; then
                RANDOM_SUFFIX="${BASH_REMATCH[1]}"
            else
                read -p "Enter random suffix used in deployment: " RANDOM_SUFFIX
            fi
        fi
    else
        # Extract configuration from deployment summary
        SOURCE_BUCKET=$(grep "Source Bucket:" deployment-summary.txt | cut -d' ' -f3)
        DEST_BUCKET=$(grep "Destination Bucket:" deployment-summary.txt | cut -d' ' -f3)
        RANDOM_SUFFIX=$(echo "${SOURCE_BUCKET}" | sed 's/storage-analytics-source-//')
    fi
    
    # Set all resource names based on extracted configuration
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export INVENTORY_CONFIG_ID="daily-inventory-config"
    export ANALYTICS_CONFIG_ID="storage-class-analysis"
    export ATHENA_DATABASE="s3_inventory_db_${RANDOM_SUFFIX//-/_}"
    export LAMBDA_FUNCTION_NAME="StorageAnalyticsFunction-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="StorageAnalyticsLambdaRole-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_RULE_NAME="StorageAnalyticsSchedule-${RANDOM_SUFFIX}"
    export CLOUDWATCH_DASHBOARD_NAME="S3-Storage-Analytics-${RANDOM_SUFFIX}"
    
    log_success "Configuration loaded successfully"
    log_info "Source Bucket: ${SOURCE_BUCKET}"
    log_info "Destination Bucket: ${DEST_BUCKET}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
}

# Confirmation prompt
confirm_destruction() {
    log_warning "This script will permanently delete the following resources:"
    echo "  - S3 Buckets: ${SOURCE_BUCKET}, ${DEST_BUCKET}"
    echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  - IAM Role: ${IAM_ROLE_NAME}"
    echo "  - EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    echo "  - CloudWatch Dashboard: ${CLOUDWATCH_DASHBOARD_NAME}"
    echo "  - Athena Database: ${ATHENA_DATABASE}"
    echo ""
    log_warning "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [[ "${confirm}" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    # Double confirmation for production safety
    read -p "Type 'DELETE' to confirm resource deletion: " double_confirm
    
    if [[ "${double_confirm}" != "DELETE" ]]; then
        log_info "Destruction cancelled - confirmation text did not match"
        exit 0
    fi
    
    log_warning "Proceeding with resource destruction in 5 seconds..."
    sleep 5
}

# Remove EventBridge rule and Lambda permissions
remove_eventbridge_resources() {
    log_info "Removing EventBridge rule and Lambda permissions..."
    
    if resource_exists "eventbridge-rule" "${EVENTBRIDGE_RULE_NAME}"; then
        # Remove targets first
        aws events remove-targets \
            --rule "${EVENTBRIDGE_RULE_NAME}" \
            --ids "1" || log_warning "Failed to remove EventBridge targets"
        
        # Delete rule
        aws events delete-rule \
            --name "${EVENTBRIDGE_RULE_NAME}" || log_warning "Failed to delete EventBridge rule"
        
        log_success "Removed EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
    else
        log_info "EventBridge rule ${EVENTBRIDGE_RULE_NAME} not found (already deleted or never created)"
    fi
}

# Remove Lambda function
remove_lambda_function() {
    log_info "Removing Lambda function..."
    
    if resource_exists "lambda-function" "${LAMBDA_FUNCTION_NAME}"; then
        # Remove Lambda permission for EventBridge first
        aws lambda remove-permission \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --statement-id storage-analytics-schedule || log_warning "Failed to remove Lambda permission"
        
        # Delete Lambda function
        aws lambda delete-function \
            --function-name "${LAMBDA_FUNCTION_NAME}"
        
        log_success "Removed Lambda function: ${LAMBDA_FUNCTION_NAME}"
    else
        log_info "Lambda function ${LAMBDA_FUNCTION_NAME} not found (already deleted or never created)"
    fi
}

# Remove IAM role and policies
remove_iam_resources() {
    log_info "Removing IAM role and policies..."
    
    if resource_exists "iam-role" "${IAM_ROLE_NAME}"; then
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || \
            log_warning "Failed to detach basic execution policy"
        
        # Remove inline policies
        aws iam delete-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-name StorageAnalyticsPolicy || \
            log_warning "Failed to delete inline policy"
        
        # Delete role
        aws iam delete-role \
            --role-name "${IAM_ROLE_NAME}"
        
        log_success "Removed IAM role: ${IAM_ROLE_NAME}"
    else
        log_info "IAM role ${IAM_ROLE_NAME} not found (already deleted or never created)"
    fi
}

# Remove S3 configurations and buckets
remove_s3_resources() {
    log_info "Removing S3 configurations and buckets..."
    
    # Remove inventory configuration
    if resource_exists "s3-bucket" "${SOURCE_BUCKET}"; then
        aws s3api delete-bucket-inventory-configuration \
            --bucket "${SOURCE_BUCKET}" \
            --id "${INVENTORY_CONFIG_ID}" || \
            log_warning "Failed to delete inventory configuration"
        
        # Remove analytics configuration
        aws s3api delete-bucket-analytics-configuration \
            --bucket "${SOURCE_BUCKET}" \
            --id "${ANALYTICS_CONFIG_ID}" || \
            log_warning "Failed to delete analytics configuration"
        
        # Delete source bucket contents and bucket
        log_info "Deleting contents of source bucket..."
        aws s3 rm "s3://${SOURCE_BUCKET}" --recursive || \
            log_warning "Failed to delete some objects from source bucket"
        
        aws s3 rb "s3://${SOURCE_BUCKET}"
        log_success "Removed source bucket: ${SOURCE_BUCKET}"
    else
        log_info "Source bucket ${SOURCE_BUCKET} not found (already deleted or never created)"
    fi
    
    # Delete destination bucket contents and bucket
    if resource_exists "s3-bucket" "${DEST_BUCKET}"; then
        log_info "Deleting contents of destination bucket..."
        aws s3 rm "s3://${DEST_BUCKET}" --recursive || \
            log_warning "Failed to delete some objects from destination bucket"
        
        aws s3 rb "s3://${DEST_BUCKET}"
        log_success "Removed destination bucket: ${DEST_BUCKET}"
    else
        log_info "Destination bucket ${DEST_BUCKET} not found (already deleted or never created)"
    fi
}

# Remove CloudWatch dashboard
remove_cloudwatch_dashboard() {
    log_info "Removing CloudWatch dashboard..."
    
    if resource_exists "cloudwatch-dashboard" "${CLOUDWATCH_DASHBOARD_NAME}"; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "${CLOUDWATCH_DASHBOARD_NAME}"
        
        log_success "Removed CloudWatch dashboard: ${CLOUDWATCH_DASHBOARD_NAME}"
    else
        log_info "CloudWatch dashboard ${CLOUDWATCH_DASHBOARD_NAME} not found (already deleted or never created)"
    fi
}

# Remove Athena database
remove_athena_database() {
    log_info "Removing Athena database..."
    
    if resource_exists "athena-database" "${ATHENA_DATABASE}"; then
        # Drop Athena database
        local query_execution_id=$(aws athena start-query-execution \
            --query-string "DROP DATABASE IF EXISTS ${ATHENA_DATABASE} CASCADE" \
            --result-configuration "OutputLocation=s3://aws-athena-query-results-${AWS_ACCOUNT_ID}-${AWS_REGION}/" \
            --work-group primary \
            --query 'QueryExecutionId' --output text)
        
        # Wait for query to complete
        local status="RUNNING"
        local max_attempts=12
        local attempts=0
        
        while [[ "${status}" == "RUNNING" || "${status}" == "QUEUED" ]] && [[ ${attempts} -lt ${max_attempts} ]]; do
            sleep 5
            status=$(aws athena get-query-execution \
                --query-execution-id "${query_execution_id}" \
                --query 'QueryExecution.Status.State' --output text)
            ((attempts++))
        done
        
        if [[ "${status}" == "SUCCEEDED" ]]; then
            log_success "Removed Athena database: ${ATHENA_DATABASE}"
        else
            log_warning "Failed to remove Athena database or query timed out. Status: ${status}"
        fi
    else
        log_info "Athena database ${ATHENA_DATABASE} not found (already deleted or never created)"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove generated query files
    if [[ -d "athena-queries" ]]; then
        rm -rf athena-queries
        log_success "Removed athena-queries directory"
    fi
    
    # Remove deployment summary
    if [[ -f "deployment-summary.txt" ]]; then
        rm deployment-summary.txt
        log_success "Removed deployment-summary.txt"
    fi
    
    # Remove any temporary files that might exist
    rm -f inventory-config.json analytics-config.json dashboard-config.json \
          lambda-trust-policy.json lambda-custom-policy.json \
          lambda-function.py lambda-function.zip \
          inventory-bucket-policy.json
    
    log_success "Cleaned up local files"
}

# Create destruction summary
create_destruction_summary() {
    log_info "Creating destruction summary..."
    
    cat > destruction-summary.txt << EOF
S3 Inventory and Storage Analytics Destruction Summary
=====================================================

Destruction completed at: $(date)

Resources Removed:
- Source Bucket: ${SOURCE_BUCKET}
- Destination Bucket: ${DEST_BUCKET}
- S3 Inventory Configuration: ${INVENTORY_CONFIG_ID}
- Storage Analytics Configuration: ${ANALYTICS_CONFIG_ID}
- Athena Database: ${ATHENA_DATABASE}
- Lambda Function: ${LAMBDA_FUNCTION_NAME}
- IAM Role: ${IAM_ROLE_NAME}
- EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}
- CloudWatch Dashboard: ${CLOUDWATCH_DASHBOARD_NAME}

AWS Region: ${AWS_REGION}
AWS Account ID: ${AWS_ACCOUNT_ID}

Notes:
- All S3 objects and buckets have been permanently deleted
- All billing for these resources should stop within 24 hours
- Some CloudWatch metrics may remain visible for up to 15 months but will not incur charges
- IAM roles and policies have been completely removed

Verification:
Please check the AWS Console to ensure all resources have been removed:
1. S3 Console: https://console.aws.amazon.com/s3/
2. Lambda Console: https://console.aws.amazon.com/lambda/
3. IAM Console: https://console.aws.amazon.com/iam/
4. EventBridge Console: https://console.aws.amazon.com/events/
5. CloudWatch Console: https://console.aws.amazon.com/cloudwatch/
6. Athena Console: https://console.aws.amazon.com/athena/
EOF
    
    log_success "Destruction summary created: destruction-summary.txt"
}

# Check for remaining resources
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local remaining_resources=0
    
    # Check each resource type
    if resource_exists "s3-bucket" "${SOURCE_BUCKET}"; then
        log_warning "Source bucket still exists: ${SOURCE_BUCKET}"
        ((remaining_resources++))
    fi
    
    if resource_exists "s3-bucket" "${DEST_BUCKET}"; then
        log_warning "Destination bucket still exists: ${DEST_BUCKET}"
        ((remaining_resources++))
    fi
    
    if resource_exists "lambda-function" "${LAMBDA_FUNCTION_NAME}"; then
        log_warning "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
        ((remaining_resources++))
    fi
    
    if resource_exists "iam-role" "${IAM_ROLE_NAME}"; then
        log_warning "IAM role still exists: ${IAM_ROLE_NAME}"
        ((remaining_resources++))
    fi
    
    if resource_exists "eventbridge-rule" "${EVENTBRIDGE_RULE_NAME}"; then
        log_warning "EventBridge rule still exists: ${EVENTBRIDGE_RULE_NAME}"
        ((remaining_resources++))
    fi
    
    if resource_exists "cloudwatch-dashboard" "${CLOUDWATCH_DASHBOARD_NAME}"; then
        log_warning "CloudWatch dashboard still exists: ${CLOUDWATCH_DASHBOARD_NAME}"
        ((remaining_resources++))
    fi
    
    if [[ ${remaining_resources} -eq 0 ]]; then
        log_success "All resources have been successfully removed"
    else
        log_warning "Found ${remaining_resources} remaining resources. Please check manually."
    fi
}

# Main destruction function
main() {
    log_info "Starting S3 Inventory and Storage Analytics cleanup..."
    
    load_deployment_config
    confirm_destruction
    
    # Remove resources in reverse order of creation
    remove_eventbridge_resources
    remove_lambda_function
    remove_iam_resources
    remove_s3_resources
    remove_cloudwatch_dashboard
    remove_athena_database
    cleanup_local_files
    create_destruction_summary
    verify_cleanup
    
    log_success "🧹 S3 Inventory and Storage Analytics cleanup completed!"
    log_info "💰 All billing for removed resources should stop within 24 hours"
    log_info "📄 See destruction-summary.txt for detailed cleanup report"
    log_info ""
    log_warning "Please verify in AWS Console that all resources have been removed"
}

# Execute main function
main "$@"