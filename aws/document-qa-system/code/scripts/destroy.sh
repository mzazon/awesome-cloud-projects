#!/bin/bash

# =============================================================================
# Destroy Script for Intelligent Document QA System with AWS Bedrock and Kendra
# =============================================================================
# This script safely removes all resources created by the deployment script
# for the intelligent document question-answering system.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate AWS permissions for resource deletion
# - Environment file (.env) from deployment script
#
# Usage: ./destroy.sh [--force] [--verbose]
# =============================================================================

set -e
set -o pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/qa-system-destroy-$(date +%Y%m%d-%H%M%S).log"
FORCE=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--force] [--verbose]"
            echo "  --force     Skip confirmation prompts"
            echo "  --verbose   Enable verbose logging"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $1" | tee -a "$LOG_FILE"
    fi
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" | tee -a "$LOG_FILE"
}

# Cleanup function for script interruption
cleanup() {
    log "Destruction interrupted. Check $LOG_FILE for details."
    exit 1
}

trap cleanup INT TERM

# Load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
        log_error "Environment file not found: ${SCRIPT_DIR}/.env"
        log_error "This file should have been created by the deploy script."
        log_error "You may need to manually identify and delete resources."
        exit 1
    fi
    
    # Source the environment file
    source "${SCRIPT_DIR}/.env"
    
    # Validate required variables
    REQUIRED_VARS=(
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "KENDRA_INDEX_NAME"
        "S3_BUCKET_NAME"
        "LAMBDA_FUNCTION_NAME"
        "KENDRA_ROLE_NAME"
        "LAMBDA_ROLE_NAME"
        "RANDOM_SUFFIX"
    )
    
    for var in "${REQUIRED_VARS[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "Required environment variable $var is not set."
            exit 1
        fi
    done
    
    # Load additional variables if they exist
    if grep -q "KENDRA_INDEX_ID" "${SCRIPT_DIR}/.env"; then
        export KENDRA_INDEX_ID=$(grep "KENDRA_INDEX_ID" "${SCRIPT_DIR}/.env" | cut -d'=' -f2)
    fi
    
    if grep -q "DATA_SOURCE_ID" "${SCRIPT_DIR}/.env"; then
        export DATA_SOURCE_ID=$(grep "DATA_SOURCE_ID" "${SCRIPT_DIR}/.env" | cut -d'=' -f2)
    fi
    
    log_verbose "Environment variables loaded:"
    log_verbose "  AWS_REGION: ${AWS_REGION}"
    log_verbose "  S3_BUCKET_NAME: ${S3_BUCKET_NAME}"
    log_verbose "  LAMBDA_FUNCTION_NAME: ${LAMBDA_FUNCTION_NAME}"
    log_verbose "  KENDRA_INDEX_NAME: ${KENDRA_INDEX_NAME}"
    
    log "Environment loaded successfully."
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    # Verify we're in the correct AWS account
    CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    if [[ "$CURRENT_ACCOUNT" != "$AWS_ACCOUNT_ID" ]]; then
        log_error "Current AWS account ($CURRENT_ACCOUNT) doesn't match deployment account ($AWS_ACCOUNT_ID)."
        exit 1
    fi
    
    log "Prerequisites check completed successfully."
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" ]]; then
        log "Force mode enabled, skipping confirmation."
        return 0
    fi
    
    log ""
    log "WARNING: This will permanently delete the following resources:"
    log "  - S3 Bucket: ${S3_BUCKET_NAME} (and all contents)"
    log "  - Kendra Index: ${KENDRA_INDEX_NAME}"
    log "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log "  - IAM Roles: ${KENDRA_ROLE_NAME}, ${LAMBDA_ROLE_NAME}"
    log "  - All associated policies and configurations"
    log ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    log "Destruction confirmed. Proceeding..."
}

# Stop any running Kendra sync jobs
stop_kendra_sync_jobs() {
    log "Stopping any running Kendra sync jobs..."
    
    if [[ -z "$KENDRA_INDEX_ID" ]]; then
        log_verbose "No Kendra index ID found, skipping sync job cleanup."
        return 0
    fi
    
    if [[ -z "$DATA_SOURCE_ID" ]]; then
        log_verbose "No data source ID found, skipping sync job cleanup."
        return 0
    fi
    
    # Check for running sync jobs
    SYNC_JOBS=$(aws kendra list-data-source-sync-jobs \
        --index-id "$KENDRA_INDEX_ID" \
        --id "$DATA_SOURCE_ID" \
        --query 'History[?Status==`SYNCING`].ExecutionId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$SYNC_JOBS" ]]; then
        log "Found running sync jobs, stopping them..."
        for job_id in $SYNC_JOBS; do
            aws kendra stop-data-source-sync-job \
                --index-id "$KENDRA_INDEX_ID" \
                --id "$DATA_SOURCE_ID" || true
            log_verbose "Stopped sync job: $job_id"
        done
        
        # Wait for jobs to stop
        log "Waiting for sync jobs to stop..."
        sleep 30
    else
        log_verbose "No running sync jobs found."
    fi
}

# Delete Kendra data source
delete_kendra_data_source() {
    log "Deleting Kendra data source..."
    
    if [[ -z "$KENDRA_INDEX_ID" ]] || [[ -z "$DATA_SOURCE_ID" ]]; then
        log_verbose "Missing Kendra index or data source ID, skipping data source deletion."
        return 0
    fi
    
    # Check if data source exists
    if aws kendra describe-data-source \
        --index-id "$KENDRA_INDEX_ID" \
        --id "$DATA_SOURCE_ID" &> /dev/null; then
        
        aws kendra delete-data-source \
            --index-id "$KENDRA_INDEX_ID" \
            --id "$DATA_SOURCE_ID"
        
        log "Kendra data source deleted successfully."
    else
        log_verbose "Kendra data source not found or already deleted."
    fi
}

# Delete Kendra index
delete_kendra_index() {
    log "Deleting Kendra index..."
    
    if [[ -z "$KENDRA_INDEX_ID" ]]; then
        # Try to find index by name
        KENDRA_INDEX_ID=$(aws kendra list-indices \
            --query "IndexConfigurationSummaryItems[?Name=='${KENDRA_INDEX_NAME}'].Id" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -z "$KENDRA_INDEX_ID" ]]; then
        log_verbose "Kendra index not found, skipping deletion."
        return 0
    fi
    
    # Check if index exists
    if aws kendra describe-index --index-id "$KENDRA_INDEX_ID" &> /dev/null; then
        log "Deleting Kendra index: $KENDRA_INDEX_ID"
        aws kendra delete-index --id "$KENDRA_INDEX_ID"
        
        log "Kendra index deletion initiated. This may take several minutes..."
        log_verbose "Index deletion is asynchronous and will continue in the background."
    else
        log_verbose "Kendra index not found or already deleted."
    fi
}

# Delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    # Check if function exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
        log "Lambda function deleted successfully: $LAMBDA_FUNCTION_NAME"
    else
        log_verbose "Lambda function not found or already deleted."
    fi
}

# Delete S3 bucket and contents
delete_s3_bucket() {
    log "Deleting S3 bucket and all contents..."
    
    # Check if bucket exists
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        # Delete all objects and versions
        log_verbose "Deleting all objects from bucket..."
        aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive
        
        # Delete all object versions and delete markers
        log_verbose "Deleting all object versions..."
        aws s3api delete-objects \
            --bucket "$S3_BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$S3_BUCKET_NAME" \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                --output json)" 2>/dev/null || true
                
        aws s3api delete-objects \
            --bucket "$S3_BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$S3_BUCKET_NAME" \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                --output json)" 2>/dev/null || true
        
        # Delete the bucket
        aws s3 rb "s3://${S3_BUCKET_NAME}" --force
        log "S3 bucket deleted successfully: $S3_BUCKET_NAME"
    else
        log_verbose "S3 bucket not found or already deleted."
    fi
}

# Delete Lambda IAM role
delete_lambda_iam_role() {
    log "Deleting Lambda IAM role..."
    
    # Check if role exists
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        # Detach managed policies
        log_verbose "Detaching managed policies from Lambda role..."
        aws iam detach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
        
        # Delete inline policies
        log_verbose "Deleting inline policies from Lambda role..."
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$LAMBDA_ROLE_NAME" \
            --query 'PolicyNames' --output text 2>/dev/null || echo "")
        
        for policy in $INLINE_POLICIES; do
            aws iam delete-role-policy \
                --role-name "$LAMBDA_ROLE_NAME" \
                --policy-name "$policy" || true
        done
        
        # Delete the role
        aws iam delete-role --role-name "$LAMBDA_ROLE_NAME"
        log "Lambda IAM role deleted successfully: $LAMBDA_ROLE_NAME"
    else
        log_verbose "Lambda IAM role not found or already deleted."
    fi
}

# Delete Kendra IAM role
delete_kendra_iam_role() {
    log "Deleting Kendra IAM role..."
    
    # Check if role exists
    if aws iam get-role --role-name "$KENDRA_ROLE_NAME" &> /dev/null; then
        # Detach managed policies
        log_verbose "Detaching managed policies from Kendra role..."
        aws iam detach-role-policy \
            --role-name "$KENDRA_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess || true
        
        # Delete inline policies
        log_verbose "Deleting inline policies from Kendra role..."
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$KENDRA_ROLE_NAME" \
            --query 'PolicyNames' --output text 2>/dev/null || echo "")
        
        for policy in $INLINE_POLICIES; do
            aws iam delete-role-policy \
                --role-name "$KENDRA_ROLE_NAME" \
                --policy-name "$policy" || true
        done
        
        # Delete the role
        aws iam delete-role --role-name "$KENDRA_ROLE_NAME"
        log "Kendra IAM role deleted successfully: $KENDRA_ROLE_NAME"
    else
        log_verbose "Kendra IAM role not found or already deleted."
    fi
}

# Cleanup environment file
cleanup_environment_file() {
    log "Cleaning up environment file..."
    
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        rm -f "${SCRIPT_DIR}/.env"
        log "Environment file removed."
    fi
}

# Cleanup temporary files
cleanup_temp_files() {
    log_verbose "Cleaning up any remaining temporary files..."
    rm -f /tmp/test-response.json
    rm -rf /tmp/qa-lambda
}

# Verify resource deletion
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check S3 bucket
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        log_warning "S3 bucket still exists: $S3_BUCKET_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        log_warning "Lambda function still exists: $LAMBDA_FUNCTION_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        log_warning "Lambda IAM role still exists: $LAMBDA_ROLE_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if aws iam get-role --role-name "$KENDRA_ROLE_NAME" &> /dev/null; then
        log_warning "Kendra IAM role still exists: $KENDRA_ROLE_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Note: Kendra index deletion is asynchronous, so we don't check it here
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log "Resource cleanup verification completed successfully."
    else
        log_warning "Some resources may still exist. Check AWS console for manual cleanup if needed."
    fi
}

# Main destruction function
main() {
    log "Starting destruction of Intelligent Document QA System..."
    log "Log file: $LOG_FILE"
    
    load_environment
    check_prerequisites
    confirm_destruction
    
    # Stop any running processes first
    stop_kendra_sync_jobs
    
    # Delete resources in reverse dependency order
    delete_kendra_data_source
    delete_kendra_index
    delete_lambda_function
    delete_s3_bucket
    delete_lambda_iam_role
    delete_kendra_iam_role
    
    # Cleanup files
    cleanup_environment_file
    cleanup_temp_files
    
    # Verify cleanup
    verify_cleanup
    
    log ""
    log "Destruction completed successfully!"
    log ""
    log "Resources that have been deleted:"
    log "  ✓ S3 Bucket: $S3_BUCKET_NAME"
    log "  ✓ Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "  ✓ Lambda IAM Role: $LAMBDA_ROLE_NAME"
    log "  ✓ Kendra IAM Role: $KENDRA_ROLE_NAME"
    log "  ✓ Kendra Data Source"
    log "  ~ Kendra Index: $KENDRA_INDEX_NAME (deletion in progress)"
    log ""
    log "Note: Kendra index deletion is asynchronous and may take several minutes to complete."
    log "You can monitor the deletion progress in the AWS Console."
}

# Run main function
main "$@"