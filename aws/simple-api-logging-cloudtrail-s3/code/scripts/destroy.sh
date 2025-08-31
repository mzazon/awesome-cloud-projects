#!/bin/bash

#===============================================================================
# AWS CloudTrail API Logging Cleanup Script
#
# This script safely removes all resources created by the deploy.sh script:
# - Stops and deletes CloudTrail trail
# - Removes CloudWatch alarms, metric filters, and log groups
# - Deletes SNS topics and subscriptions
# - Removes S3 bucket and all contents (including versions)
# - Cleans up IAM roles and policies
#
# Usage: ./destroy.sh [--force] [--preserve-logs]
#
# Requirements:
# - AWS CLI v2.0 or later configured with appropriate permissions
# - .deployment-config file from successful deployment
#===============================================================================

set -euo pipefail

# Colors for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/cloudtrail-destroy-$(date +%Y%m%d-%H%M%S).log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment-config"

# Command line options
FORCE_DELETE=false
PRESERVE_LOGS=false
VERBOSE=false

#===============================================================================
# Utility Functions
#===============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC}  $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC}  $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") [[ "$VERBOSE" == true ]] && echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

load_deployment_config() {
    log "INFO" "Loading deployment configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "ERROR" "Deployment configuration file not found: $CONFIG_FILE"
        log "ERROR" "This file should have been created during deployment."
        log "ERROR" "Cannot proceed without knowing which resources to delete."
        exit 1
    fi
    
    # Source the configuration file
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    
    # Validate required variables
    local missing_vars=()
    [[ -z "${AWS_REGION:-}" ]] && missing_vars+=("AWS_REGION")
    [[ -z "${AWS_ACCOUNT_ID:-}" ]] && missing_vars+=("AWS_ACCOUNT_ID")
    [[ -z "${BUCKET_NAME:-}" ]] && missing_vars+=("BUCKET_NAME")
    [[ -z "${TRAIL_NAME:-}" ]] && missing_vars+=("TRAIL_NAME")
    [[ -z "${LOG_GROUP_NAME:-}" ]] && missing_vars+=("LOG_GROUP_NAME")
    [[ -z "${ROLE_NAME:-}" ]] && missing_vars+=("ROLE_NAME")
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log "ERROR" "Missing required configuration variables: ${missing_vars[*]}"
        log "ERROR" "Configuration file may be corrupted: $CONFIG_FILE"
        exit 1
    fi
    
    log "INFO" "✅ Configuration loaded successfully"
    log "INFO" "  Deployment Date: ${DEPLOYMENT_DATE:-Unknown}"
    log "INFO" "  Region: $AWS_REGION"
    log "INFO" "  Account: $AWS_ACCOUNT_ID"
    log "DEBUG" "  Resources to delete:"
    log "DEBUG" "    S3 Bucket: $BUCKET_NAME"
    log "DEBUG" "    CloudTrail: $TRAIL_NAME"
    log "DEBUG" "    Log Group: $LOG_GROUP_NAME"
    log "DEBUG" "    IAM Role: $ROLE_NAME"
    log "DEBUG" "    Alarm: ${ALARM_NAME:-Not set}"
    log "DEBUG" "    Topic: ${TOPIC_NAME:-Not set}"
}

check_aws_access() {
    log "INFO" "Verifying AWS access..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured or invalid."
        exit 1
    fi
    
    # Verify we're in the correct account
    local current_account
    current_account=$(aws sts get-caller-identity --query Account --output text)
    if [[ "$current_account" != "$AWS_ACCOUNT_ID" ]]; then
        log "ERROR" "Account mismatch! Expected: $AWS_ACCOUNT_ID, Current: $current_account"
        log "ERROR" "Please ensure you're authenticated to the correct AWS account."
        exit 1
    fi
    
    log "INFO" "✅ AWS access verified"
}

confirm_deletion() {
    if [[ "$FORCE_DELETE" == true ]]; then
        log "INFO" "Force deletion enabled, skipping confirmation"
        return 0
    fi
    
    echo ""
    log "WARN" "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log "WARN" ""
    log "WARN" "This will permanently delete the following AWS resources:"
    log "WARN" "  • CloudTrail: $TRAIL_NAME"
    log "WARN" "  • S3 Bucket: $BUCKET_NAME (and ALL contents)"
    log "WARN" "  • CloudWatch Log Group: $LOG_GROUP_NAME"
    log "WARN" "  • IAM Role: $ROLE_NAME"
    [[ -n "${ALARM_NAME:-}" ]] && log "WARN" "  • CloudWatch Alarm: $ALARM_NAME"
    [[ -n "${TOPIC_NAME:-}" ]] && log "WARN" "  • SNS Topic: $TOPIC_NAME"
    log "WARN" ""
    
    if [[ "$PRESERVE_LOGS" == true ]]; then
        log "INFO" "Log preservation is enabled - S3 logs will be downloaded before deletion"
    else
        log "WARN" "⚠️  ALL CLOUDTRAIL LOGS WILL BE PERMANENTLY LOST ⚠️"
    fi
    
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "INFO" "Operation cancelled by user"
        exit 0
    fi
    
    log "INFO" "Deletion confirmed. Proceeding with cleanup..."
}

resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "$resource_type" in
        "cloudtrail")
            aws cloudtrail describe-trails --trail-name-list "$resource_name" &>/dev/null
            ;;
        "s3-bucket")
            aws s3api head-bucket --bucket "$resource_name" &>/dev/null
            ;;
        "log-group")
            aws logs describe-log-groups --log-group-name-prefix "$resource_name" \
                --query 'logGroups[?logGroupName==`'$resource_name'`]' --output text | grep -q "$resource_name"
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" &>/dev/null
            ;;
        "sns-topic")
            # For SNS, we need the full ARN, so we'll construct it
            local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${resource_name}"
            aws sns get-topic-attributes --topic-arn "$topic_arn" &>/dev/null
            ;;
        "cloudwatch-alarm")
            aws cloudwatch describe-alarms --alarm-names "$resource_name" \
                --query 'MetricAlarms[?AlarmName==`'$resource_name'`]' --output text | grep -q "$resource_name"
            ;;
        *)
            log "ERROR" "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

preserve_cloudtrail_logs() {
    if [[ "$PRESERVE_LOGS" != true ]]; then
        return 0
    fi
    
    log "INFO" "Preserving CloudTrail logs before deletion..."
    
    # Create local backup directory
    local backup_dir="${SCRIPT_DIR}/cloudtrail-logs-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Download logs from S3
    log "INFO" "Downloading logs to: $backup_dir"
    if aws s3 sync "s3://$BUCKET_NAME" "$backup_dir" --quiet; then
        log "INFO" "✅ CloudTrail logs backed up to: $backup_dir"
        
        # Create a summary file
        cat > "${backup_dir}/backup-info.txt" << EOF
CloudTrail Log Backup
===================
Backup Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Original Deployment: ${DEPLOYMENT_DATE:-Unknown}
AWS Account: $AWS_ACCOUNT_ID
AWS Region: $AWS_REGION
S3 Bucket: $BUCKET_NAME
CloudTrail: $TRAIL_NAME

Files in this backup:
$(find "$backup_dir" -type f -name "*.json.gz" | wc -l) CloudTrail log files
$(du -sh "$backup_dir" | cut -f1) total size
EOF
        
    else
        log "WARN" "Failed to backup CloudTrail logs. Continuing with deletion."
    fi
}

#===============================================================================
# Resource Deletion Functions
#===============================================================================

stop_and_delete_cloudtrail() {
    log "INFO" "Stopping and deleting CloudTrail..."
    
    if ! resource_exists "cloudtrail" "$TRAIL_NAME"; then
        log "WARN" "CloudTrail '$TRAIL_NAME' not found, skipping"
        return 0
    fi
    
    # Stop logging first
    log "DEBUG" "Stopping CloudTrail logging..."
    if aws cloudtrail stop-logging --name "$TRAIL_NAME" &>/dev/null; then
        log "INFO" "CloudTrail logging stopped"
    else
        log "WARN" "Failed to stop CloudTrail logging (may already be stopped)"
    fi
    
    # Delete the trail
    log "DEBUG" "Deleting CloudTrail..."
    if aws cloudtrail delete-trail --name "$TRAIL_NAME"; then
        log "INFO" "✅ CloudTrail deleted: $TRAIL_NAME"
    else
        log "ERROR" "Failed to delete CloudTrail: $TRAIL_NAME"
        return 1
    fi
}

delete_cloudwatch_resources() {
    log "INFO" "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarm if it exists
    if [[ -n "${ALARM_NAME:-}" ]] && resource_exists "cloudwatch-alarm" "$ALARM_NAME"; then
        log "DEBUG" "Deleting CloudWatch alarm: $ALARM_NAME"
        if aws cloudwatch delete-alarms --alarm-names "$ALARM_NAME"; then
            log "INFO" "CloudWatch alarm deleted: $ALARM_NAME"
        else
            log "WARN" "Failed to delete CloudWatch alarm: $ALARM_NAME"
        fi
    fi
    
    # Delete metric filter
    log "DEBUG" "Deleting metric filter..."
    if aws logs delete-metric-filter \
        --log-group-name "$LOG_GROUP_NAME" \
        --filter-name RootAccountUsage &>/dev/null; then
        log "INFO" "Metric filter deleted"
    else
        log "WARN" "Failed to delete metric filter (may not exist)"
    fi
    
    # Delete log group
    if resource_exists "log-group" "$LOG_GROUP_NAME"; then
        log "DEBUG" "Deleting CloudWatch log group: $LOG_GROUP_NAME"
        if aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME"; then
            log "INFO" "✅ CloudWatch log group deleted: $LOG_GROUP_NAME"
        else
            log "ERROR" "Failed to delete CloudWatch log group: $LOG_GROUP_NAME"
        fi
    else
        log "WARN" "CloudWatch log group '$LOG_GROUP_NAME' not found, skipping"
    fi
}

delete_sns_topic() {
    if [[ -z "${TOPIC_NAME:-}" ]]; then
        log "DEBUG" "No SNS topic name configured, skipping"
        return 0
    fi
    
    log "INFO" "Deleting SNS topic..."
    
    local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${TOPIC_NAME}"
    
    if resource_exists "sns-topic" "$TOPIC_NAME"; then
        log "DEBUG" "Deleting SNS topic: $topic_arn"
        if aws sns delete-topic --topic-arn "$topic_arn"; then
            log "INFO" "✅ SNS topic deleted: $TOPIC_NAME"
        else
            log "ERROR" "Failed to delete SNS topic: $TOPIC_NAME"
        fi
    else
        log "WARN" "SNS topic '$TOPIC_NAME' not found, skipping"
    fi
}

delete_s3_bucket() {
    log "INFO" "Deleting S3 bucket and all contents..."
    
    if ! resource_exists "s3-bucket" "$BUCKET_NAME"; then
        log "WARN" "S3 bucket '$BUCKET_NAME' not found, skipping"
        return 0
    fi
    
    # First, preserve logs if requested
    preserve_cloudtrail_logs
    
    log "DEBUG" "Deleting all objects in bucket..."
    # Delete all current objects
    if aws s3 rm "s3://$BUCKET_NAME" --recursive --quiet; then
        log "INFO" "Current objects deleted from bucket"
    else
        log "WARN" "Some objects may not have been deleted"
    fi
    
    # Delete all object versions (since versioning is enabled)
    log "DEBUG" "Deleting all object versions..."
    local versions_json
    versions_json=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" \
        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)
    
    if [[ "$versions_json" != '{"Objects": null}' ]] && [[ "$versions_json" != '{"Objects": []}' ]]; then
        if aws s3api delete-objects --bucket "$BUCKET_NAME" --delete "$versions_json" --quiet; then
            log "INFO" "Object versions deleted from bucket"
        else
            log "WARN" "Some object versions may not have been deleted"
        fi
    fi
    
    # Delete delete markers
    log "DEBUG" "Deleting delete markers..."
    local markers_json
    markers_json=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" \
        --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)
    
    if [[ "$markers_json" != '{"Objects": null}' ]] && [[ "$markers_json" != '{"Objects": []}' ]]; then
        if aws s3api delete-objects --bucket "$BUCKET_NAME" --delete "$markers_json" --quiet; then
            log "INFO" "Delete markers removed from bucket"
        else
            log "WARN" "Some delete markers may not have been removed"
        fi
    fi
    
    # Finally, delete the bucket
    log "DEBUG" "Deleting S3 bucket..."
    if aws s3 rb "s3://$BUCKET_NAME"; then
        log "INFO" "✅ S3 bucket deleted: $BUCKET_NAME"
    else
        log "ERROR" "Failed to delete S3 bucket: $BUCKET_NAME"
        log "ERROR" "You may need to manually remove remaining objects and delete the bucket"
        return 1
    fi
}

delete_iam_role() {
    log "INFO" "Deleting IAM role and policies..."
    
    if ! resource_exists "iam-role" "$ROLE_NAME"; then
        log "WARN" "IAM role '$ROLE_NAME' not found, skipping"
        return 0
    fi
    
    # Delete inline role policy first
    log "DEBUG" "Deleting inline role policy..."
    if aws iam delete-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-name CloudTrailLogsPolicy &>/dev/null; then
        log "INFO" "Inline role policy deleted"
    else
        log "WARN" "Failed to delete inline role policy (may not exist)"
    fi
    
    # Delete the role
    log "DEBUG" "Deleting IAM role: $ROLE_NAME"
    if aws iam delete-role --role-name "$ROLE_NAME"; then
        log "INFO" "✅ IAM role deleted: $ROLE_NAME"
    else
        log "ERROR" "Failed to delete IAM role: $ROLE_NAME"
        return 1
    fi
}

cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    # Remove temporary policy files (if they exist)
    local temp_files=(
        "cloudtrail-trust-policy.json"
        "cloudtrail-logs-policy.json"
        "s3-bucket-policy.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "DEBUG" "Removed temporary file: $file"
        fi
    done
    
    # Remove deployment configuration
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
        log "INFO" "Removed deployment configuration: $CONFIG_FILE"
    fi
    
    log "INFO" "✅ Local cleanup completed"
}

verify_cleanup() {
    log "INFO" "Verifying resource cleanup..."
    
    local remaining_resources=()
    
    # Check each resource type
    if resource_exists "cloudtrail" "$TRAIL_NAME"; then
        remaining_resources+=("CloudTrail: $TRAIL_NAME")
    fi
    
    if resource_exists "s3-bucket" "$BUCKET_NAME"; then
        remaining_resources+=("S3 Bucket: $BUCKET_NAME")
    fi
    
    if resource_exists "log-group" "$LOG_GROUP_NAME"; then
        remaining_resources+=("CloudWatch Log Group: $LOG_GROUP_NAME")
    fi
    
    if resource_exists "iam-role" "$ROLE_NAME"; then
        remaining_resources+=("IAM Role: $ROLE_NAME")
    fi
    
    if [[ -n "${ALARM_NAME:-}" ]] && resource_exists "cloudwatch-alarm" "$ALARM_NAME"; then
        remaining_resources+=("CloudWatch Alarm: $ALARM_NAME")
    fi
    
    if [[ -n "${TOPIC_NAME:-}" ]] && resource_exists "sns-topic" "$TOPIC_NAME"; then
        remaining_resources+=("SNS Topic: $TOPIC_NAME")
    fi
    
    if [[ ${#remaining_resources[@]} -eq 0 ]]; then
        log "INFO" "✅ All resources successfully cleaned up"
        return 0
    else
        log "WARN" "Some resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            log "WARN" "  • $resource"
        done
        log "WARN" "You may need to manually clean up these resources"
        return 1
    fi
}

#===============================================================================
# Main Destruction Logic
#===============================================================================

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy AWS CloudTrail API logging infrastructure.

OPTIONS:
    --force             Skip confirmation prompts
    --preserve-logs     Download CloudTrail logs before deleting S3 bucket
    --verbose           Enable verbose debugging output
    --help              Show this help message

EXAMPLES:
    $0                          # Interactive cleanup with confirmations
    $0 --force                  # Automated cleanup without prompts
    $0 --preserve-logs          # Download logs before deletion
    $0 --force --preserve-logs  # Automated cleanup with log preservation

REQUIREMENTS:
    - AWS CLI v2.0+ configured with appropriate permissions
    - .deployment-config file from successful deployment
    - Permissions for all services used in the original deployment

SAFETY FEATURES:
    - Requires explicit confirmation before deletion (unless --force used)
    - Verifies AWS account matches deployment configuration
    - Can preserve CloudTrail logs before S3 bucket deletion
    - Validates cleanup completion after resource deletion

For more information, see the recipe documentation.
EOF
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --preserve-logs)
                PRESERVE_LOGS=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log "INFO" "Starting CloudTrail API Logging cleanup..."
    log "INFO" "Log file: $LOG_FILE"
    
    # Execute cleanup steps
    load_deployment_config
    check_aws_access
    confirm_deletion
    
    log "INFO" "Beginning resource deletion..."
    
    # Delete resources in reverse order of creation
    stop_and_delete_cloudtrail
    delete_cloudwatch_resources
    delete_sns_topic
    delete_s3_bucket
    delete_iam_role
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    log "INFO" "🎉 CLEANUP COMPLETED!"
    log "INFO" ""
    log "INFO" "All CloudTrail API logging resources have been removed."
    
    if [[ "$PRESERVE_LOGS" == true ]]; then
        log "INFO" "CloudTrail logs have been preserved locally."
        log "INFO" "Check the 'cloudtrail-logs-backup-*' directory for saved logs."
    fi
    
    log "INFO" ""
    log "INFO" "Cleanup log saved to: $LOG_FILE"
}

# Execute main function with all arguments
main "$@"