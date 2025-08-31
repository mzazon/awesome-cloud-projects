#!/bin/bash

# Automated Data Analysis with Bedrock AgentCore Runtime - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ -f ".env.deployment" ]; then
        source .env.deployment
        success "Environment variables loaded from .env.deployment"
        log "Found deployment with suffix: ${RANDOM_SUFFIX}"
    else
        error "No .env.deployment file found. Cannot determine resources to clean up."
        echo ""
        echo "If you know the resource names, you can clean up manually:"
        echo "1. Find S3 buckets: aws s3 ls | grep data-analysis"
        echo "2. Find Lambda functions: aws lambda list-functions | grep data-analysis"
        echo "3. Find IAM roles: aws iam list-roles | grep DataAnalysis"
        echo "4. Find CloudWatch dashboards: aws cloudwatch list-dashboards | grep DataAnalysis"
        exit 1
    fi
}

# Function to confirm cleanup
confirm_cleanup() {
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This will permanently delete the following resources:"
    echo "  • S3 Bucket: ${DATA_BUCKET_NAME} (and ALL contents)"
    echo "  • S3 Bucket: ${RESULTS_BUCKET_NAME} (and ALL contents)"
    echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  • IAM Role: ${IAM_ROLE_NAME}"
    echo "  • IAM Policy: ${POLICY_NAME}"
    echo "  • CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Cleanup confirmed, proceeding..."
}

# Function to remove S3 event notification
remove_s3_notifications() {
    log "Removing S3 event notifications..."
    
    if aws s3api head-bucket --bucket "$DATA_BUCKET_NAME" 2>/dev/null; then
        # Remove S3 bucket notification configuration
        aws s3api put-bucket-notification-configuration \
            --bucket "${DATA_BUCKET_NAME}" \
            --notification-configuration '{}' 2>/dev/null || true
        success "S3 event notifications removed"
    else
        warning "Data bucket ${DATA_BUCKET_NAME} not found, skipping notification removal"
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        # Remove Lambda permission for S3 (if exists)
        aws lambda remove-permission \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --statement-id s3-trigger-permission 2>/dev/null || true
        
        # Delete Lambda function
        aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}"
        
        # Wait for function deletion to complete
        log "Waiting for Lambda function deletion to complete..."
        sleep 10
        
        success "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}"
    else
        warning "Lambda function ${LAMBDA_FUNCTION_NAME} not found, skipping deletion"
    fi
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    # Check if role exists
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        # Detach policies from role
        log "Detaching policies from IAM role..."
        aws iam detach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        aws iam detach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn "${POLICY_ARN}" 2>/dev/null || true
        
        # Delete IAM role
        aws iam delete-role --role-name "${IAM_ROLE_NAME}"
        success "IAM role deleted: ${IAM_ROLE_NAME}"
    else
        warning "IAM role ${IAM_ROLE_NAME} not found, skipping deletion"
    fi
    
    # Check if custom policy exists
    if aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
        # Wait a moment for policy detachment to complete
        sleep 5
        
        # Delete custom policy
        aws iam delete-policy --policy-arn "${POLICY_ARN}"
        success "IAM policy deleted: ${POLICY_NAME}"
    else
        warning "IAM policy ${POLICY_NAME} not found, skipping deletion"
    fi
}

# Function to delete S3 buckets and contents
delete_s3_buckets() {
    log "Deleting S3 buckets and contents..."
    
    # Delete data bucket
    if aws s3api head-bucket --bucket "$DATA_BUCKET_NAME" 2>/dev/null; then
        log "Emptying data bucket: ${DATA_BUCKET_NAME}"
        aws s3 rm "s3://${DATA_BUCKET_NAME}" --recursive 2>/dev/null || true
        
        # Delete all object versions (if versioning is enabled)
        log "Removing all object versions from data bucket..."
        aws s3api list-object-versions \
            --bucket "${DATA_BUCKET_NAME}" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output text 2>/dev/null | while read key version; do
            if [ -n "$key" ] && [ -n "$version" ]; then
                aws s3api delete-object \
                    --bucket "${DATA_BUCKET_NAME}" \
                    --key "$key" \
                    --version-id "$version" 2>/dev/null || true
            fi
        done
        
        # Delete delete markers
        aws s3api list-object-versions \
            --bucket "${DATA_BUCKET_NAME}" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output text 2>/dev/null | while read key version; do
            if [ -n "$key" ] && [ -n "$version" ]; then
                aws s3api delete-object \
                    --bucket "${DATA_BUCKET_NAME}" \
                    --key "$key" \
                    --version-id "$version" 2>/dev/null || true
            fi
        done
        
        aws s3 rb "s3://${DATA_BUCKET_NAME}" --force
        success "Data bucket deleted: ${DATA_BUCKET_NAME}"
    else
        warning "Data bucket ${DATA_BUCKET_NAME} not found, skipping deletion"
    fi
    
    # Delete results bucket
    if aws s3api head-bucket --bucket "$RESULTS_BUCKET_NAME" 2>/dev/null; then
        log "Emptying results bucket: ${RESULTS_BUCKET_NAME}"
        aws s3 rm "s3://${RESULTS_BUCKET_NAME}" --recursive 2>/dev/null || true
        
        # Delete all object versions (if versioning is enabled)
        log "Removing all object versions from results bucket..."
        aws s3api list-object-versions \
            --bucket "${RESULTS_BUCKET_NAME}" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output text 2>/dev/null | while read key version; do
            if [ -n "$key" ] && [ -n "$version" ]; then
                aws s3api delete-object \
                    --bucket "${RESULTS_BUCKET_NAME}" \
                    --key "$key" \
                    --version-id "$version" 2>/dev/null || true
            fi
        done
        
        # Delete delete markers
        aws s3api list-object-versions \
            --bucket "${RESULTS_BUCKET_NAME}" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output text 2>/dev/null | while read key version; do
            if [ -n "$key" ] && [ -n "$version" ]; then
                aws s3api delete-object \
                    --bucket "${RESULTS_BUCKET_NAME}" \
                    --key "$key" \
                    --version-id "$version" 2>/dev/null || true
            fi
        done
        
        aws s3 rb "s3://${RESULTS_BUCKET_NAME}" --force
        success "Results bucket deleted: ${RESULTS_BUCKET_NAME}"
    else
        warning "Results bucket ${RESULTS_BUCKET_NAME} not found, skipping deletion"
    fi
}

# Function to delete CloudWatch dashboard
delete_cloudwatch_dashboard() {
    log "Deleting CloudWatch dashboard..."
    
    if aws cloudwatch describe-dashboards --dashboard-names "$DASHBOARD_NAME" &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "${DASHBOARD_NAME}"
        success "CloudWatch dashboard deleted: ${DASHBOARD_NAME}"
    else
        warning "CloudWatch dashboard ${DASHBOARD_NAME} not found, skipping deletion"
    fi
}

# Function to delete CloudWatch log groups
delete_cloudwatch_logs() {
    log "Deleting CloudWatch log groups..."
    
    LOG_GROUP_NAME="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
        aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME"
        success "CloudWatch log group deleted: ${LOG_GROUP_NAME}"
    else
        warning "CloudWatch log group ${LOG_GROUP_NAME} not found, skipping deletion"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment environment file
    if [ -f ".env.deployment" ]; then
        rm -f .env.deployment
        success "Removed .env.deployment file"
    fi
    
    # Remove any temporary files that might be left over
    rm -f lambda-trust-policy.json
    rm -f custom-permissions-policy.json
    rm -f s3-notification-config.json
    rm -f dashboard-config.json
    rm -f data_analysis_orchestrator.py
    rm -f lambda-function.zip
    rm -f sample-dataset.csv
    
    success "Local temporary files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check S3 buckets
    if aws s3api head-bucket --bucket "$DATA_BUCKET_NAME" 2>/dev/null; then
        error "Data bucket still exists: ${DATA_BUCKET_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if aws s3api head-bucket --bucket "$RESULTS_BUCKET_NAME" 2>/dev/null; then
        error "Results bucket still exists: ${RESULTS_BUCKET_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        error "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        error "IAM role still exists: ${IAM_ROLE_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        success "All resources successfully cleaned up!"
        return 0
    else
        error "Some resources may not have been fully cleaned up. Please check manually."
        return 1
    fi
}

# Function to display cleanup summary
display_summary() {
    echo ""
    echo "🧹 Cleanup Summary:"
    echo ""
    if verify_cleanup; then
        echo "✅ All resources from the Automated Data Analysis deployment have been removed"
        echo ""
        echo "📋 Resources Deleted:"
        echo "  • S3 Data Bucket: ${DATA_BUCKET_NAME}"
        echo "  • S3 Results Bucket: ${RESULTS_BUCKET_NAME}"
        echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
        echo "  • IAM Role: ${IAM_ROLE_NAME}"
        echo "  • IAM Policy: ${POLICY_NAME}"
        echo "  • CloudWatch Dashboard: ${DASHBOARD_NAME}"
        echo "  • CloudWatch Log Groups"
        echo ""
        echo "💰 Cost Impact:"
        echo "  • No ongoing charges from these resources"
        echo "  • Any remaining CloudWatch log retention charges will expire based on retention settings"
    else
        echo "⚠️  Some resources may still exist. Please check the AWS console or run:"
        echo ""
        echo "Manual cleanup commands:"
        echo "  aws s3 ls | grep data-analysis"
        echo "  aws lambda list-functions | grep data-analysis"
        echo "  aws iam list-roles | grep DataAnalysis"
        echo "  aws cloudwatch list-dashboards | grep DataAnalysis"
    fi
    echo ""
}

# Main cleanup function
main() {
    log "Starting cleanup of Automated Data Analysis with Bedrock AgentCore..."
    
    load_environment
    confirm_cleanup
    
    # Cleanup in reverse order of creation
    remove_s3_notifications
    delete_lambda_function
    delete_iam_resources
    delete_s3_buckets
    delete_cloudwatch_dashboard
    delete_cloudwatch_logs
    cleanup_local_files
    
    display_summary
    
    success "Cleanup completed!"
}

# Error handling for script interruption
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        echo ""
        error "Cleanup was interrupted. Some resources may still exist."
        echo "You can re-run this script to continue cleanup, or clean up manually."
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"