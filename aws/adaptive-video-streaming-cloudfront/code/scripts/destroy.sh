#!/bin/bash

# Adaptive Bitrate Streaming with MediaConvert and CloudFront - Cleanup Script
# This script safely removes all infrastructure created for the ABR streaming solution

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.env"
FORCE=false
DRY_RUN=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
        *)     echo -e "$message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handler
error_exit() {
    log ERROR "$1"
    log ERROR "Cleanup failed. Check $LOG_FILE for details."
    exit 1
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy Adaptive Bitrate Streaming infrastructure

OPTIONS:
    -h, --help          Show this help message
    -f, --force         Skip confirmation prompts
    -d, --dry-run       Show what would be destroyed without making changes
    -v, --verbose       Enable verbose logging
    --delete-logs       Delete log files after successful cleanup

EXAMPLES:
    $0                              # Interactive cleanup with confirmations
    $0 --force                      # Automatic cleanup without prompts
    $0 --dry-run                    # Preview what would be destroyed
    $0 --force --delete-logs        # Complete cleanup including logs

SAFETY FEATURES:
    - Confirmation prompts for destructive actions
    - Dry-run mode to preview changes
    - Automatic detection of running MediaConvert jobs
    - Graceful handling of resource dependencies
    - Verification of resource deletion

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            --delete-logs)
                DELETE_LOGS=true
                shift
                ;;
            *)
                log ERROR "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Load deployment information
load_deployment_info() {
    log INFO "Loading deployment information..."
    
    if [ ! -f "$DEPLOYMENT_INFO_FILE" ]; then
        error_exit "Deployment info file not found: $DEPLOYMENT_INFO_FILE"
    fi
    
    # Source the deployment info
    source "$DEPLOYMENT_INFO_FILE"
    
    # Verify required variables are set
    local required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "SOURCE_BUCKET" "OUTPUT_BUCKET"
        "LAMBDA_FUNCTION" "MEDIACONVERT_ROLE" "JOB_TEMPLATE"
        "MEDIACONVERT_ENDPOINT" "DISTRIBUTION_ID"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            error_exit "Required variable $var not found in deployment info"
        fi
    done
    
    log INFO "Deployment information loaded successfully"
    log INFO "  Region: $AWS_REGION"
    log INFO "  Source Bucket: $SOURCE_BUCKET"
    log INFO "  Output Bucket: $OUTPUT_BUCKET"
    log INFO "  Lambda Function: $LAMBDA_FUNCTION"
    log INFO "  Distribution ID: $DISTRIBUTION_ID"
}

# Confirmation prompt
confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    if [ "$FORCE" = true ]; then
        log INFO "[FORCED] $message"
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would $message"
        return 0
    fi
    
    local prompt
    if [ "$default" = "y" ]; then
        prompt="$message [Y/n]: "
    else
        prompt="$message [y/N]: "
    fi
    
    while true; do
        read -p "$prompt" response
        case $response in
            [Yy]* ) return 0 ;;
            [Nn]* ) return 1 ;;
            "" ) 
                if [ "$default" = "y" ]; then
                    return 0
                else
                    return 1
                fi
                ;;
            * ) echo "Please answer yes or no." ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        error_exit "AWS CLI is not installed."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_exit "AWS credentials not configured."
    fi
    
    # Verify account ID matches
    local current_account=$(aws sts get-caller-identity --query Account --output text)
    if [ "$current_account" != "$AWS_ACCOUNT_ID" ]; then
        error_exit "Account ID mismatch. Expected: $AWS_ACCOUNT_ID, Current: $current_account"
    fi
    
    log INFO "Prerequisites check completed successfully"
}

# Stop running MediaConvert jobs
stop_mediaconvert_jobs() {
    log INFO "Checking for running MediaConvert jobs..."
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would check and stop MediaConvert jobs"
        return 0
    fi
    
    # List running jobs
    local running_jobs=$(aws mediaconvert list-jobs \
        --endpoint-url "$MEDIACONVERT_ENDPOINT" \
        --status PROGRESSING \
        --query 'Jobs[].Id' --output text 2>/dev/null || echo "")
    
    if [ -z "$running_jobs" ]; then
        log INFO "No running MediaConvert jobs found"
        return 0
    fi
    
    if confirm_action "Cancel running MediaConvert jobs?"; then
        for job_id in $running_jobs; do
            aws mediaconvert cancel-job \
                --endpoint-url "$MEDIACONVERT_ENDPOINT" \
                --id "$job_id" || log WARN "Failed to cancel job: $job_id"
            log INFO "Cancelled MediaConvert job: $job_id"
        done
        
        # Wait for jobs to stop
        log INFO "Waiting for jobs to stop..."
        sleep 30
    else
        log WARN "Skipping MediaConvert job cancellation"
    fi
}

# Remove S3 event notifications
remove_s3_notifications() {
    log INFO "Removing S3 event notifications..."
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would remove S3 event notifications from $SOURCE_BUCKET"
        return 0
    fi
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "$SOURCE_BUCKET" 2>/dev/null; then
        aws s3api put-bucket-notification-configuration \
            --bucket "$SOURCE_BUCKET" \
            --notification-configuration '{}' || log WARN "Failed to remove S3 notifications"
        log INFO "Removed S3 event notifications"
    else
        log INFO "Source bucket does not exist, skipping notification removal"
    fi
}

# Delete Lambda function
delete_lambda_function() {
    log INFO "Deleting Lambda function..."
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would delete Lambda function: $LAMBDA_FUNCTION"
        return 0
    fi
    
    # Remove Lambda permissions first
    aws lambda remove-permission \
        --function-name "$LAMBDA_FUNCTION" \
        --statement-id s3-video-trigger 2>/dev/null || log WARN "Failed to remove Lambda permission"
    
    # Delete Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION" >/dev/null 2>&1; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION"
        log INFO "Deleted Lambda function: $LAMBDA_FUNCTION"
    else
        log INFO "Lambda function does not exist: $LAMBDA_FUNCTION"
    fi
    
    # Delete Lambda execution role
    local lambda_role="${LAMBDA_FUNCTION}-role"
    if aws iam get-role --role-name "$lambda_role" >/dev/null 2>&1; then
        # Delete role policy
        aws iam delete-role-policy \
            --role-name "$lambda_role" \
            --policy-name MediaConvertAccessPolicy 2>/dev/null || log WARN "Failed to delete Lambda role policy"
        
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "$lambda_role" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || log WARN "Failed to detach Lambda policy"
        
        # Delete role
        aws iam delete-role --role-name "$lambda_role"
        log INFO "Deleted Lambda role: $lambda_role"
    else
        log INFO "Lambda role does not exist: $lambda_role"
    fi
}

# Delete MediaConvert resources
delete_mediaconvert_resources() {
    log INFO "Deleting MediaConvert resources..."
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would delete job template: $JOB_TEMPLATE"
        log INFO "[DRY RUN] Would delete MediaConvert role: $MEDIACONVERT_ROLE"
        return 0
    fi
    
    # Delete job template
    if aws mediaconvert get-job-template \
        --endpoint-url "$MEDIACONVERT_ENDPOINT" \
        --name "$JOB_TEMPLATE" >/dev/null 2>&1; then
        aws mediaconvert delete-job-template \
            --endpoint-url "$MEDIACONVERT_ENDPOINT" \
            --name "$JOB_TEMPLATE"
        log INFO "Deleted MediaConvert job template: $JOB_TEMPLATE"
    else
        log INFO "MediaConvert job template does not exist: $JOB_TEMPLATE"
    fi
    
    # Delete MediaConvert role
    if aws iam get-role --role-name "$MEDIACONVERT_ROLE" >/dev/null 2>&1; then
        # Delete role policy
        aws iam delete-role-policy \
            --role-name "$MEDIACONVERT_ROLE" \
            --policy-name S3AccessPolicy 2>/dev/null || log WARN "Failed to delete MediaConvert role policy"
        
        # Delete role
        aws iam delete-role --role-name "$MEDIACONVERT_ROLE"
        log INFO "Deleted MediaConvert role: $MEDIACONVERT_ROLE"
    else
        log INFO "MediaConvert role does not exist: $MEDIACONVERT_ROLE"
    fi
}

# Delete CloudFront distribution
delete_cloudfront_distribution() {
    log INFO "Deleting CloudFront distribution..."
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would delete CloudFront distribution: $DISTRIBUTION_ID"
        return 0
    fi
    
    # Check if distribution exists
    if ! aws cloudfront get-distribution --id "$DISTRIBUTION_ID" >/dev/null 2>&1; then
        log INFO "CloudFront distribution does not exist: $DISTRIBUTION_ID"
        return 0
    fi
    
    # Get current distribution configuration
    local config_file="/tmp/current-dist-config.json"
    local etag=$(aws cloudfront get-distribution-config \
        --id "$DISTRIBUTION_ID" \
        --query 'ETag' --output text)
    
    aws cloudfront get-distribution-config \
        --id "$DISTRIBUTION_ID" \
        --query 'DistributionConfig' > "$config_file"
    
    # Check if distribution is already disabled
    local enabled=$(jq -r '.Enabled' "$config_file")
    
    if [ "$enabled" = "true" ]; then
        if confirm_action "Disable CloudFront distribution before deletion?"; then
            # Disable distribution
            jq '.Enabled = false' "$config_file" > "/tmp/disabled-dist-config.json"
            
            aws cloudfront update-distribution \
                --id "$DISTRIBUTION_ID" \
                --distribution-config file:///tmp/disabled-dist-config.json \
                --if-match "$etag" >/dev/null
            
            log INFO "Disabled CloudFront distribution: $DISTRIBUTION_ID"
            log INFO "Distribution will be automatically deleted after it's fully disabled (may take 15-20 minutes)"
            log WARN "Manual deletion required: aws cloudfront delete-distribution --id $DISTRIBUTION_ID --if-match <new-etag>"
        else
            log WARN "Skipping CloudFront distribution deletion"
        fi
    else
        # Try to delete already disabled distribution
        etag=$(aws cloudfront get-distribution-config \
            --id "$DISTRIBUTION_ID" \
            --query 'ETag' --output text)
        
        aws cloudfront delete-distribution \
            --id "$DISTRIBUTION_ID" \
            --if-match "$etag" && \
        log INFO "Deleted CloudFront distribution: $DISTRIBUTION_ID" || \
        log WARN "Failed to delete CloudFront distribution (may still be propagating)"
    fi
    
    # Cleanup temp files
    rm -f /tmp/current-dist-config.json /tmp/disabled-dist-config.json
}

# Delete S3 buckets and contents
delete_s3_buckets() {
    log INFO "Deleting S3 buckets and contents..."
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would delete S3 buckets: $SOURCE_BUCKET, $OUTPUT_BUCKET"
        return 0
    fi
    
    # Function to delete bucket and contents
    delete_bucket() {
        local bucket=$1
        
        if aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
            # Check if bucket has contents
            local object_count=$(aws s3 ls "s3://$bucket" --recursive | wc -l)
            
            if [ "$object_count" -gt 0 ]; then
                if confirm_action "Delete all contents in bucket $bucket ($object_count objects)?"; then
                    aws s3 rm "s3://$bucket" --recursive
                    log INFO "Deleted all objects from bucket: $bucket"
                else
                    log WARN "Skipping bucket deletion due to contents: $bucket"
                    return 1
                fi
            fi
            
            # Delete bucket
            aws s3 rb "s3://$bucket"
            log INFO "Deleted bucket: $bucket"
        else
            log INFO "Bucket does not exist: $bucket"
        fi
    }
    
    # Delete output bucket first (may have more contents)
    delete_bucket "$OUTPUT_BUCKET"
    
    # Delete source bucket
    delete_bucket "$SOURCE_BUCKET"
}

# Verify resource deletion
verify_deletion() {
    log INFO "Verifying resource deletion..."
    
    local errors=0
    
    # Check S3 buckets
    if aws s3api head-bucket --bucket "$SOURCE_BUCKET" >/dev/null 2>&1; then
        log WARN "Source bucket still exists: $SOURCE_BUCKET"
        ((errors++))
    fi
    
    if aws s3api head-bucket --bucket "$OUTPUT_BUCKET" >/dev/null 2>&1; then
        log WARN "Output bucket still exists: $OUTPUT_BUCKET"
        ((errors++))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION" >/dev/null 2>&1; then
        log WARN "Lambda function still exists: $LAMBDA_FUNCTION"
        ((errors++))
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name "$MEDIACONVERT_ROLE" >/dev/null 2>&1; then
        log WARN "MediaConvert role still exists: $MEDIACONVERT_ROLE"
        ((errors++))
    fi
    
    if aws iam get-role --role-name "${LAMBDA_FUNCTION}-role" >/dev/null 2>&1; then
        log WARN "Lambda role still exists: ${LAMBDA_FUNCTION}-role"
        ((errors++))
    fi
    
    # Check MediaConvert job template
    if aws mediaconvert get-job-template \
        --endpoint-url "$MEDIACONVERT_ENDPOINT" \
        --name "$JOB_TEMPLATE" >/dev/null 2>&1; then
        log WARN "MediaConvert job template still exists: $JOB_TEMPLATE"
        ((errors++))
    fi
    
    # Check CloudFront distribution (may still be disabling)
    local dist_status=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query 'Distribution.Status' --output text 2>/dev/null || echo "NotFound")
    
    if [ "$dist_status" != "NotFound" ]; then
        log WARN "CloudFront distribution still exists: $DISTRIBUTION_ID (Status: $dist_status)"
        if [ "$dist_status" = "InProgress" ]; then
            log INFO "Distribution is still being disabled/deleted"
        fi
        ((errors++))
    fi
    
    if [ $errors -eq 0 ]; then
        log INFO "All resources successfully deleted"
    else
        log WARN "Some resources may still exist ($errors warnings)"
    fi
    
    return $errors
}

# Clean up deployment files
cleanup_deployment_files() {
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would clean up deployment files"
        return 0
    fi
    
    if [ "${DELETE_LOGS:-false}" = true ]; then
        if confirm_action "Delete deployment information and log files?"; then
            rm -f "$DEPLOYMENT_INFO_FILE"
            rm -f "$LOG_FILE"
            log INFO "Deleted deployment files"
        fi
    fi
}

# Display cleanup summary
display_summary() {
    log INFO "Cleanup completed!"
    
    cat << EOF

==================================================
ADAPTIVE BITRATE STREAMING CLEANUP COMPLETE
==================================================

✅ REMOVED RESOURCES:
- S3 Buckets: $SOURCE_BUCKET, $OUTPUT_BUCKET
- Lambda Function: $LAMBDA_FUNCTION
- MediaConvert Job Template: $JOB_TEMPLATE
- IAM Roles: $MEDIACONVERT_ROLE, ${LAMBDA_FUNCTION}-role
- CloudFront Distribution: $DISTRIBUTION_ID

📝 NOTES:
- CloudFront distributions may take 15-20 minutes to fully delete
- Check AWS Console to verify all resources are removed
- Monitor AWS billing for any remaining charges

💰 COST SAVINGS:
- All ongoing charges for this infrastructure have been stopped
- Any remaining S3 storage costs are eliminated
- CloudFront and Lambda execution costs are eliminated

==================================================

EOF
}

# Main cleanup function
main() {
    log INFO "Starting Adaptive Bitrate Streaming cleanup..."
    log INFO "Log file: $LOG_FILE"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Load deployment information
    load_deployment_info
    
    # Check prerequisites
    check_prerequisites
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "DRY RUN MODE - No resources will be deleted"
    elif [ "$FORCE" = false ]; then
        cat << EOF

⚠️  WARNING: This will permanently delete all Adaptive Bitrate Streaming infrastructure!

The following resources will be DESTROYED:
- S3 Buckets: $SOURCE_BUCKET, $OUTPUT_BUCKET (and ALL contents)
- Lambda Function: $LAMBDA_FUNCTION  
- MediaConvert Job Template: $JOB_TEMPLATE
- IAM Roles: $MEDIACONVERT_ROLE, ${LAMBDA_FUNCTION}-role
- CloudFront Distribution: $DISTRIBUTION_ID

This action CANNOT be undone!

EOF
        
        if ! confirm_action "Are you sure you want to proceed with the cleanup?"; then
            log INFO "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute cleanup steps
    stop_mediaconvert_jobs
    remove_s3_notifications
    delete_lambda_function
    delete_mediaconvert_resources
    delete_cloudfront_distribution
    delete_s3_buckets
    
    # Verify deletion
    if [ "$DRY_RUN" = false ]; then
        verify_deletion
        display_summary
        cleanup_deployment_files
    else
        log INFO "DRY RUN completed successfully"
    fi
    
    log INFO "Cleanup script completed"
}

# Execute main function with all arguments
main "$@"