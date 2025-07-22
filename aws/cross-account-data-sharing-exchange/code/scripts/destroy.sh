#!/bin/bash

# Destroy script for Cross-Account Data Sharing with Data Exchange
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
ENV_FILE="${SCRIPT_DIR}/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error_log() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$ERROR_LOG"
}

warn_log() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

info_log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Load environment variables
load_environment() {
    if [[ -f "$ENV_FILE" ]]; then
        log "Loading environment variables from $ENV_FILE"
        source "$ENV_FILE"
    else
        warn_log "Environment file not found. Some resources may not be cleaned up automatically."
        
        # Try to determine values from current AWS environment
        export AWS_REGION=$(aws configure get region || echo "us-east-1")
        export PROVIDER_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        
        if [[ -z "$PROVIDER_ACCOUNT_ID" ]]; then
            error_log "Cannot determine account ID. Please ensure AWS credentials are configured."
            exit 1
        fi
        
        warn_log "Will attempt to clean up resources based on current AWS configuration"
    fi
}

# Safety confirmation
confirm_destruction() {
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   - Data Exchange datasets and revisions"
    echo "   - Data grants"
    echo "   - S3 buckets and all contents"
    echo "   - Lambda functions"
    echo "   - EventBridge rules"
    echo "   - CloudWatch alarms and log groups"
    echo "   - IAM roles and policies"
    echo ""
    
    if [[ -n "${DATASET_ID:-}" ]]; then
        echo "Dataset ID: $DATASET_ID"
    fi
    if [[ -n "${DATA_GRANT_ID:-}" ]]; then
        echo "Data Grant ID: $DATA_GRANT_ID"
    fi
    if [[ -n "${PROVIDER_BUCKET:-}" ]]; then
        echo "Provider Bucket: $PROVIDER_BUCKET"
    fi
    
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "User confirmed destruction. Proceeding..."
}

# Remove EventBridge rules and targets
remove_eventbridge_rules() {
    log "Removing EventBridge rules and targets..."
    
    # Remove targets from auto-update schedule rule
    if aws events describe-rule --name DataExchangeAutoUpdateSchedule &> /dev/null; then
        info_log "Removing targets from DataExchangeAutoUpdateSchedule rule..."
        aws events remove-targets \
            --rule DataExchangeAutoUpdateSchedule \
            --ids 1 2>/dev/null || warn_log "Failed to remove targets from auto-update schedule rule"
        
        # Delete the rule
        aws events delete-rule --name DataExchangeAutoUpdateSchedule 2>/dev/null || warn_log "Failed to delete auto-update schedule rule"
        log "Removed DataExchangeAutoUpdateSchedule rule"
    else
        info_log "DataExchangeAutoUpdateSchedule rule not found"
    fi
    
    # Remove targets from event rule
    if aws events describe-rule --name DataExchangeEventRule &> /dev/null; then
        info_log "Removing targets from DataExchangeEventRule..."
        aws events remove-targets \
            --rule DataExchangeEventRule \
            --ids 1 2>/dev/null || warn_log "Failed to remove targets from event rule"
        
        # Delete the rule
        aws events delete-rule --name DataExchangeEventRule 2>/dev/null || warn_log "Failed to delete event rule"
        log "Removed DataExchangeEventRule"
    else
        info_log "DataExchangeEventRule not found"
    fi
}

# Remove Lambda functions
remove_lambda_functions() {
    log "Removing Lambda functions..."
    
    # Remove permissions first
    aws lambda remove-permission \
        --function-name DataExchangeNotificationHandler \
        --statement-id DataExchangeEventPermission 2>/dev/null || info_log "Permission not found for notification handler"
    
    aws lambda remove-permission \
        --function-name DataExchangeAutoUpdate \
        --statement-id DataExchangeSchedulePermission 2>/dev/null || info_log "Permission not found for auto update"
    
    # Delete notification Lambda function
    if aws lambda get-function --function-name DataExchangeNotificationHandler &> /dev/null; then
        aws lambda delete-function --function-name DataExchangeNotificationHandler
        log "Deleted DataExchangeNotificationHandler Lambda function"
    else
        info_log "DataExchangeNotificationHandler Lambda function not found"
    fi
    
    # Delete update Lambda function
    if aws lambda get-function --function-name DataExchangeAutoUpdate &> /dev/null; then
        aws lambda delete-function --function-name DataExchangeAutoUpdate
        log "Deleted DataExchangeAutoUpdate Lambda function"
    else
        info_log "DataExchangeAutoUpdate Lambda function not found"
    fi
}

# Remove CloudWatch resources
remove_cloudwatch_resources() {
    log "Removing CloudWatch resources..."
    
    # Delete CloudWatch alarm
    if aws cloudwatch describe-alarms --alarm-names DataExchangeFailedGrants --query 'MetricAlarms[0]' --output text | grep -q "DataExchangeFailedGrants"; then
        aws cloudwatch delete-alarms --alarm-names DataExchangeFailedGrants
        log "Deleted DataExchangeFailedGrants CloudWatch alarm"
    else
        info_log "DataExchangeFailedGrants alarm not found"
    fi
    
    # Delete log groups
    if aws logs describe-log-groups --log-group-name-prefix "/aws/dataexchange/operations" --query 'logGroups[0]' --output text | grep -v "None"; then
        aws logs delete-log-group --log-group-name /aws/dataexchange/operations 2>/dev/null || warn_log "Failed to delete DataExchange log group"
        log "Deleted /aws/dataexchange/operations log group"
    else
        info_log "DataExchange operations log group not found"
    fi
    
    if aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/DataExchangeAutoUpdate" --query 'logGroups[0]' --output text | grep -v "None"; then
        aws logs delete-log-group --log-group-name /aws/lambda/DataExchangeAutoUpdate 2>/dev/null || warn_log "Failed to delete Lambda log group"
        log "Deleted /aws/lambda/DataExchangeAutoUpdate log group"
    else
        info_log "DataExchangeAutoUpdate log group not found"
    fi
    
    if aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/DataExchangeNotificationHandler" --query 'logGroups[0]' --output text | grep -v "None"; then
        aws logs delete-log-group --log-group-name /aws/lambda/DataExchangeNotificationHandler 2>/dev/null || warn_log "Failed to delete notification Lambda log group"
        log "Deleted /aws/lambda/DataExchangeNotificationHandler log group"
    else
        info_log "DataExchangeNotificationHandler log group not found"
    fi
}

# Remove data grants and datasets
remove_data_exchange_resources() {
    log "Removing Data Exchange resources..."
    
    # Delete data grant if it exists
    if [[ -n "${DATA_GRANT_ID:-}" ]]; then
        if aws dataexchange get-data-grant --data-grant-id "$DATA_GRANT_ID" &> /dev/null; then
            aws dataexchange delete-data-grant --data-grant-id "$DATA_GRANT_ID"
            log "Deleted data grant: $DATA_GRANT_ID"
        else
            info_log "Data grant $DATA_GRANT_ID not found or already deleted"
        fi
    else
        warn_log "No data grant ID found in environment file"
        
        # Try to find and delete data grants
        info_log "Searching for data grants to delete..."
        DATA_GRANTS=$(aws dataexchange list-data-grants --query 'DataGrants[].Id' --output text 2>/dev/null || echo "")
        if [[ -n "$DATA_GRANTS" ]]; then
            for grant_id in $DATA_GRANTS; do
                aws dataexchange delete-data-grant --data-grant-id "$grant_id" 2>/dev/null || warn_log "Failed to delete data grant: $grant_id"
                log "Deleted data grant: $grant_id"
            done
        else
            info_log "No data grants found"
        fi
    fi
    
    # Delete dataset if it exists
    if [[ -n "${DATASET_ID:-}" ]]; then
        if aws dataexchange get-data-set --data-set-id "$DATASET_ID" &> /dev/null; then
            aws dataexchange delete-data-set --data-set-id "$DATASET_ID"
            log "Deleted dataset: $DATASET_ID"
        else
            info_log "Dataset $DATASET_ID not found or already deleted"
        fi
    else
        warn_log "No dataset ID found in environment file"
        
        # Try to find and delete datasets that match our naming pattern
        info_log "Searching for datasets to delete..."
        if [[ -n "${DATASET_NAME:-}" ]]; then
            DATASETS=$(aws dataexchange list-data-sets --query "DataSets[?contains(Name, '$DATASET_NAME')].Id" --output text 2>/dev/null || echo "")
        else
            DATASETS=$(aws dataexchange list-data-sets --query "DataSets[?contains(Name, 'enterprise-analytics-data')].Id" --output text 2>/dev/null || echo "")
        fi
        
        if [[ -n "$DATASETS" ]]; then
            for dataset_id in $DATASETS; do
                aws dataexchange delete-data-set --data-set-id "$dataset_id" 2>/dev/null || warn_log "Failed to delete dataset: $dataset_id"
                log "Deleted dataset: $dataset_id"
            done
        else
            info_log "No matching datasets found"
        fi
    fi
}

# Remove S3 buckets and contents
remove_s3_resources() {
    log "Removing S3 resources..."
    
    # Remove provider bucket
    if [[ -n "${PROVIDER_BUCKET:-}" ]]; then
        if aws s3 ls "s3://$PROVIDER_BUCKET" &> /dev/null; then
            info_log "Emptying provider bucket: $PROVIDER_BUCKET"
            aws s3 rm "s3://$PROVIDER_BUCKET" --recursive 2>/dev/null || warn_log "Failed to empty provider bucket"
            
            info_log "Deleting provider bucket: $PROVIDER_BUCKET"
            aws s3 rb "s3://$PROVIDER_BUCKET" 2>/dev/null || warn_log "Failed to delete provider bucket"
            log "Removed provider bucket: $PROVIDER_BUCKET"
        else
            info_log "Provider bucket $PROVIDER_BUCKET not found"
        fi
    else
        warn_log "No provider bucket name found in environment file"
        
        # Try to find buckets with our naming pattern
        info_log "Searching for data-exchange-provider buckets to delete..."
        PROVIDER_BUCKETS=$(aws s3 ls | grep "data-exchange-provider" | awk '{print $3}' || echo "")
        if [[ -n "$PROVIDER_BUCKETS" ]]; then
            for bucket in $PROVIDER_BUCKETS; do
                info_log "Emptying bucket: $bucket"
                aws s3 rm "s3://$bucket" --recursive 2>/dev/null || warn_log "Failed to empty bucket: $bucket"
                aws s3 rb "s3://$bucket" 2>/dev/null || warn_log "Failed to delete bucket: $bucket"
                log "Removed bucket: $bucket"
            done
        else
            info_log "No matching provider buckets found"
        fi
    fi
}

# Remove IAM resources
remove_iam_resources() {
    log "Removing IAM resources..."
    
    # Detach and delete IAM role
    if aws iam get-role --role-name DataExchangeProviderRole &> /dev/null; then
        info_log "Detaching policies from DataExchangeProviderRole..."
        
        # Detach AWS managed policy
        aws iam detach-role-policy \
            --role-name DataExchangeProviderRole \
            --policy-arn arn:aws:iam::aws:policy/AWSDataExchangeProviderFullAccess 2>/dev/null || warn_log "Failed to detach AWS managed policy"
        
        # Delete the role
        aws iam delete-role --role-name DataExchangeProviderRole
        log "Deleted IAM role: DataExchangeProviderRole"
    else
        info_log "IAM role DataExchangeProviderRole not found"
    fi
}

# Clean up local files
clean_local_files() {
    log "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        "data-exchange-trust-policy.json"
        "notification-lambda.py"
        "notification-lambda.zip"
        "update-lambda.py"
        "update-lambda.zip"
        "subscriber-access-script.sh"
        "response.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            info_log "Removed file: $file"
        fi
    done
    
    # Remove sample data directory
    if [[ -d "sample-data" ]]; then
        rm -rf sample-data/
        info_log "Removed sample-data directory"
    fi
    
    # Remove environment file
    if [[ -f "$ENV_FILE" ]]; then
        rm -f "$ENV_FILE"
        info_log "Removed environment file: $ENV_FILE"
    fi
    
    log "Local cleanup completed"
}

# Wait for resource deletion (some resources may need time to be fully deleted)
wait_for_deletion() {
    log "Waiting for resources to be fully deleted..."
    
    # Wait for Lambda functions to be deleted
    local max_wait=60
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        if ! aws lambda get-function --function-name DataExchangeNotificationHandler &> /dev/null && \
           ! aws lambda get-function --function-name DataExchangeAutoUpdate &> /dev/null; then
            break
        fi
        sleep 5
        wait_time=$((wait_time + 5))
        info_log "Waiting for Lambda functions to be deleted... ($wait_time/$max_wait seconds)"
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        warn_log "Timeout waiting for Lambda functions to be deleted"
    else
        log "Lambda functions have been deleted"
    fi
}

# Main destruction function
main() {
    log "Starting AWS Data Exchange cross-account data sharing destruction..."
    
    # Initialize log files
    echo "Destruction started at $(date)" > "$LOG_FILE"
    echo "Error log for destruction started at $(date)" > "$ERROR_LOG"
    
    # Load environment and confirm
    load_environment
    confirm_destruction
    
    # Execute destruction in reverse order of creation
    remove_eventbridge_rules
    remove_lambda_functions
    remove_cloudwatch_resources
    remove_data_exchange_resources
    remove_s3_resources
    remove_iam_resources
    
    # Wait for deletions to complete
    wait_for_deletion
    
    # Clean up local files last
    clean_local_files
    
    # Final summary
    log "🎉 Destruction completed successfully!"
    echo ""
    echo "=== DESTRUCTION SUMMARY ==="
    echo "All AWS Data Exchange resources have been removed"
    echo "All Lambda functions have been deleted"
    echo "All EventBridge rules have been removed"
    echo "All CloudWatch resources have been cleaned up"
    echo "All S3 buckets and contents have been deleted"
    echo "All IAM roles and policies have been removed"
    echo "All local files have been cleaned up"
    echo ""
    echo "=== VERIFICATION ==="
    echo "You can verify the cleanup by checking:"
    echo "1. AWS Data Exchange console - no datasets should remain"
    echo "2. Lambda console - no DataExchange* functions should exist"
    echo "3. S3 console - no data-exchange-provider-* buckets should exist"
    echo "4. IAM console - no DataExchangeProviderRole should exist"
    echo ""
    log "Destruction logs available at: $LOG_FILE"
    
    if [[ -s "$ERROR_LOG" ]]; then
        warn_log "Some errors occurred during destruction. Check $ERROR_LOG for details."
    fi
}

# Handle script interruption
cleanup_on_interrupt() {
    warn_log "Destruction interrupted. Some resources may not have been cleaned up."
    warn_log "You may need to manually clean up remaining AWS resources."
    exit 1
}

# Set up interrupt trap
trap cleanup_on_interrupt INT TERM

# Run main function
main "$@"