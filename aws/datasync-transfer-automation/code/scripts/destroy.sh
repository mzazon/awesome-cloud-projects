#!/bin/bash

# AWS DataSync Data Transfer Automation - Cleanup Script
# This script removes all resources created by the DataSync deployment

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.json"
FORCE="${FORCE:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
trap 'log "ERROR" "Script failed at line $LINENO"' ERR

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy AWS DataSync Data Transfer Automation resources

OPTIONS:
    -h, --help          Show this help message
    -f, --force         Skip confirmation prompts
    -d, --dry-run       Show what would be destroyed without making changes
    -r, --region        AWS region (default: from deployment info or AWS CLI config)
    -v, --verbose       Enable verbose logging
    --keep-buckets      Keep S3 buckets (only delete DataSync resources)
    --keep-data         Keep data in S3 buckets but delete other resources

EXAMPLES:
    $0                          # Interactive cleanup with confirmations
    $0 --force                  # Force cleanup without prompts
    $0 --dry-run                # Show cleanup plan
    $0 --keep-buckets           # Keep S3 buckets
    $0 --keep-data              # Keep S3 data but delete other resources

EOF
}

# Parse command line arguments
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
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --keep-buckets)
            KEEP_BUCKETS=true
            shift
            ;;
        --keep-data)
            KEEP_DATA=true
            shift
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Initialize logging
log "INFO" "Starting DataSync cleanup script"
log "INFO" "Log file: $LOG_FILE"

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
    
    # Check required tools
    local required_tools=("jq" "cut" "grep" "sed")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log "ERROR" "Required tool '$tool' is not installed"
            exit 1
        fi
    done
    
    log "INFO" "Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    log "INFO" "Loading deployment information..."
    
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        # Load from deployment info file
        AWS_REGION=$(jq -r '.aws_region' "$DEPLOYMENT_INFO_FILE")
        AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$DEPLOYMENT_INFO_FILE")
        SOURCE_BUCKET_NAME=$(jq -r '.source_bucket' "$DEPLOYMENT_INFO_FILE")
        DEST_BUCKET_NAME=$(jq -r '.destination_bucket' "$DEPLOYMENT_INFO_FILE")
        DATASYNC_ROLE_NAME=$(jq -r '.datasync_role_name' "$DEPLOYMENT_INFO_FILE")
        DATASYNC_TASK_NAME=$(jq -r '.datasync_task_name' "$DEPLOYMENT_INFO_FILE")
        EVENTBRIDGE_ROLE_NAME=$(jq -r '.eventbridge_role_name' "$DEPLOYMENT_INFO_FILE")
        LOG_GROUP_NAME=$(jq -r '.log_group_name' "$DEPLOYMENT_INFO_FILE")
        DATASYNC_ROLE_ARN=$(jq -r '.datasync_role_arn' "$DEPLOYMENT_INFO_FILE")
        SOURCE_LOCATION_ARN=$(jq -r '.source_location_arn' "$DEPLOYMENT_INFO_FILE")
        DEST_LOCATION_ARN=$(jq -r '.destination_location_arn' "$DEPLOYMENT_INFO_FILE")
        TASK_ARN=$(jq -r '.task_arn' "$DEPLOYMENT_INFO_FILE")
        
        log "INFO" "Loaded deployment information from: $DEPLOYMENT_INFO_FILE"
    else
        log "WARN" "Deployment info file not found. Using fallback discovery..."
        
        # Fallback: try to discover resources
        if [[ -z "${AWS_REGION:-}" ]]; then
            AWS_REGION=$(aws configure get region)
            if [[ -z "$AWS_REGION" ]]; then
                log "ERROR" "AWS region not configured. Use --region or configure AWS CLI"
                exit 1
            fi
        fi
        
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Try to discover resources by naming patterns
        log "INFO" "Attempting to discover DataSync resources..."
        
        # Find DataSync tasks
        local tasks=$(aws datasync list-tasks --query 'Tasks[?contains(Name, `DataSyncTask-`)].{Name:Name,TaskArn:TaskArn}' --output json)
        if [[ $(echo "$tasks" | jq length) -gt 0 ]]; then
            DATASYNC_TASK_NAME=$(echo "$tasks" | jq -r '.[0].Name')
            TASK_ARN=$(echo "$tasks" | jq -r '.[0].TaskArn')
            log "INFO" "Found DataSync task: $DATASYNC_TASK_NAME"
        else
            log "WARN" "No DataSync tasks found with expected naming pattern"
        fi
    fi
    
    # Export variables
    export AWS_REGION AWS_ACCOUNT_ID SOURCE_BUCKET_NAME DEST_BUCKET_NAME
    export DATASYNC_ROLE_NAME DATASYNC_TASK_NAME EVENTBRIDGE_ROLE_NAME LOG_GROUP_NAME
    export DATASYNC_ROLE_ARN SOURCE_LOCATION_ARN DEST_LOCATION_ARN TASK_ARN
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log "WARN" "This will destroy the following resources:"
    log "WARN" "  - DataSync task: ${DATASYNC_TASK_NAME:-'Not found'}"
    log "WARN" "  - DataSync locations: ${SOURCE_LOCATION_ARN:-'Not found'}, ${DEST_LOCATION_ARN:-'Not found'}"
    log "WARN" "  - IAM roles: ${DATASYNC_ROLE_NAME:-'Not found'}, ${EVENTBRIDGE_ROLE_NAME:-'Not found'}"
    log "WARN" "  - CloudWatch log group: ${LOG_GROUP_NAME:-'Not found'}"
    log "WARN" "  - EventBridge rule: DataSyncScheduledExecution"
    log "WARN" "  - CloudWatch dashboard: DataSyncMonitoring"
    
    if [[ "${KEEP_BUCKETS:-false}" != "true" ]]; then
        log "WARN" "  - S3 buckets: ${SOURCE_BUCKET_NAME:-'Not found'}, ${DEST_BUCKET_NAME:-'Not found'}"
    fi
    
    echo
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log "INFO" "Cleanup cancelled by user"
        exit 0
    fi
}

# Stop any running DataSync executions
stop_datasync_executions() {
    log "INFO" "Stopping any running DataSync executions..."
    
    if [[ -n "${TASK_ARN:-}" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would stop running executions for task: $TASK_ARN"
        else
            # List and cancel running executions
            local executions=$(aws datasync list-task-executions \
                --task-arn "$TASK_ARN" \
                --query 'TaskExecutions[?Status==`RUNNING`].TaskExecutionArn' \
                --output text)
            
            if [[ -n "$executions" ]]; then
                for execution in $executions; do
                    aws datasync cancel-task-execution --task-execution-arn "$execution" || true
                    log "INFO" "Cancelled running execution: $execution"
                done
                
                # Wait for executions to stop
                log "INFO" "Waiting for executions to stop..."
                sleep 30
            else
                log "INFO" "No running executions found"
            fi
        fi
    else
        log "INFO" "No task ARN available, skipping execution stop"
    fi
}

# Remove EventBridge scheduling
remove_eventbridge_scheduling() {
    log "INFO" "Removing EventBridge scheduling..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would remove EventBridge rule: DataSyncScheduledExecution"
    else
        # Remove targets from rule
        if aws events list-targets-by-rule --rule DataSyncScheduledExecution &>/dev/null; then
            aws events remove-targets --rule DataSyncScheduledExecution --ids 1 || true
            log "INFO" "Removed targets from EventBridge rule"
        fi
        
        # Delete rule
        if aws events describe-rule --name DataSyncScheduledExecution &>/dev/null; then
            aws events delete-rule --name DataSyncScheduledExecution || true
            log "INFO" "Deleted EventBridge rule: DataSyncScheduledExecution"
        else
            log "INFO" "EventBridge rule not found, skipping"
        fi
    fi
}

# Remove CloudWatch resources
remove_cloudwatch_resources() {
    log "INFO" "Removing CloudWatch resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would remove CloudWatch dashboard: DataSyncMonitoring"
        log "INFO" "[DRY RUN] Would remove CloudWatch log group: ${LOG_GROUP_NAME:-'Not found'}"
    else
        # Delete dashboard
        if aws cloudwatch get-dashboard --dashboard-name DataSyncMonitoring &>/dev/null; then
            aws cloudwatch delete-dashboards --dashboard-names DataSyncMonitoring || true
            log "INFO" "Deleted CloudWatch dashboard: DataSyncMonitoring"
        else
            log "INFO" "CloudWatch dashboard not found, skipping"
        fi
        
        # Delete log group
        if [[ -n "${LOG_GROUP_NAME:-}" ]]; then
            if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
                aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME" || true
                log "INFO" "Deleted CloudWatch log group: $LOG_GROUP_NAME"
            else
                log "INFO" "CloudWatch log group not found, skipping"
            fi
        fi
    fi
}

# Remove DataSync resources
remove_datasync_resources() {
    log "INFO" "Removing DataSync resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would remove DataSync task: ${TASK_ARN:-'Not found'}"
        log "INFO" "[DRY RUN] Would remove DataSync locations: ${SOURCE_LOCATION_ARN:-'Not found'}, ${DEST_LOCATION_ARN:-'Not found'}"
    else
        # Delete task
        if [[ -n "${TASK_ARN:-}" ]]; then
            if aws datasync describe-task --task-arn "$TASK_ARN" &>/dev/null; then
                aws datasync delete-task --task-arn "$TASK_ARN" || true
                log "INFO" "Deleted DataSync task: $TASK_ARN"
            else
                log "INFO" "DataSync task not found, skipping"
            fi
        fi
        
        # Delete source location
        if [[ -n "${SOURCE_LOCATION_ARN:-}" ]]; then
            if aws datasync describe-location-s3 --location-arn "$SOURCE_LOCATION_ARN" &>/dev/null; then
                aws datasync delete-location --location-arn "$SOURCE_LOCATION_ARN" || true
                log "INFO" "Deleted source location: $SOURCE_LOCATION_ARN"
            else
                log "INFO" "Source location not found, skipping"
            fi
        fi
        
        # Delete destination location
        if [[ -n "${DEST_LOCATION_ARN:-}" ]]; then
            if aws datasync describe-location-s3 --location-arn "$DEST_LOCATION_ARN" &>/dev/null; then
                aws datasync delete-location --location-arn "$DEST_LOCATION_ARN" || true
                log "INFO" "Deleted destination location: $DEST_LOCATION_ARN"
            else
                log "INFO" "Destination location not found, skipping"
            fi
        fi
    fi
}

# Remove IAM resources
remove_iam_resources() {
    log "INFO" "Removing IAM resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would remove IAM role: ${DATASYNC_ROLE_NAME:-'Not found'}"
        log "INFO" "[DRY RUN] Would remove IAM role: ${EVENTBRIDGE_ROLE_NAME:-'Not found'}"
    else
        # Delete DataSync role policies and role
        if [[ -n "${DATASYNC_ROLE_NAME:-}" ]]; then
            if aws iam get-role --role-name "$DATASYNC_ROLE_NAME" &>/dev/null; then
                # Delete role policies
                aws iam delete-role-policy --role-name "$DATASYNC_ROLE_NAME" --policy-name DataSyncS3Policy || true
                
                # Delete role
                aws iam delete-role --role-name "$DATASYNC_ROLE_NAME" || true
                log "INFO" "Deleted DataSync IAM role: $DATASYNC_ROLE_NAME"
            else
                log "INFO" "DataSync IAM role not found, skipping"
            fi
        fi
        
        # Delete EventBridge role policies and role
        if [[ -n "${EVENTBRIDGE_ROLE_NAME:-}" ]]; then
            if aws iam get-role --role-name "$EVENTBRIDGE_ROLE_NAME" &>/dev/null; then
                # Delete role policies
                aws iam delete-role-policy --role-name "$EVENTBRIDGE_ROLE_NAME" --policy-name DataSyncExecutionPolicy || true
                
                # Delete role
                aws iam delete-role --role-name "$EVENTBRIDGE_ROLE_NAME" || true
                log "INFO" "Deleted EventBridge IAM role: $EVENTBRIDGE_ROLE_NAME"
            else
                log "INFO" "EventBridge IAM role not found, skipping"
            fi
        fi
    fi
}

# Remove S3 resources
remove_s3_resources() {
    if [[ "${KEEP_BUCKETS:-false}" == "true" ]]; then
        log "INFO" "Keeping S3 buckets as requested"
        return 0
    fi
    
    log "INFO" "Removing S3 resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would remove S3 bucket: ${SOURCE_BUCKET_NAME:-'Not found'}"
        log "INFO" "[DRY RUN] Would remove S3 bucket: ${DEST_BUCKET_NAME:-'Not found'}"
    else
        # Delete source bucket
        if [[ -n "${SOURCE_BUCKET_NAME:-}" ]]; then
            if aws s3api head-bucket --bucket "$SOURCE_BUCKET_NAME" &>/dev/null; then
                if [[ "${KEEP_DATA:-false}" != "true" ]]; then
                    aws s3 rm "s3://$SOURCE_BUCKET_NAME" --recursive || true
                fi
                aws s3api delete-bucket --bucket "$SOURCE_BUCKET_NAME" || true
                log "INFO" "Deleted source bucket: $SOURCE_BUCKET_NAME"
            else
                log "INFO" "Source bucket not found, skipping"
            fi
        fi
        
        # Delete destination bucket
        if [[ -n "${DEST_BUCKET_NAME:-}" ]]; then
            if aws s3api head-bucket --bucket "$DEST_BUCKET_NAME" &>/dev/null; then
                if [[ "${KEEP_DATA:-false}" != "true" ]]; then
                    aws s3 rm "s3://$DEST_BUCKET_NAME" --recursive || true
                fi
                aws s3api delete-bucket --bucket "$DEST_BUCKET_NAME" || true
                log "INFO" "Deleted destination bucket: $DEST_BUCKET_NAME"
            else
                log "INFO" "Destination bucket not found, skipping"
            fi
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would remove local files"
    else
        # Remove temporary files
        rm -f /tmp/datasync-*.json /tmp/eventbridge-*.json /tmp/sample-file.txt
        
        # Remove deployment info file
        if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
            rm -f "$DEPLOYMENT_INFO_FILE"
            log "INFO" "Removed deployment info file"
        fi
        
        log "INFO" "Cleaned up local files"
    fi
}

# Wait for resource cleanup
wait_for_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log "INFO" "Waiting for resource cleanup to complete..."
    sleep 10
    
    # Verify critical resources are deleted
    local cleanup_success=true
    
    # Check DataSync task
    if [[ -n "${TASK_ARN:-}" ]]; then
        if aws datasync describe-task --task-arn "$TASK_ARN" &>/dev/null; then
            log "WARN" "DataSync task still exists: $TASK_ARN"
            cleanup_success=false
        fi
    fi
    
    # Check S3 buckets (if not keeping them)
    if [[ "${KEEP_BUCKETS:-false}" != "true" ]]; then
        if [[ -n "${SOURCE_BUCKET_NAME:-}" ]] && aws s3api head-bucket --bucket "$SOURCE_BUCKET_NAME" &>/dev/null; then
            log "WARN" "Source bucket still exists: $SOURCE_BUCKET_NAME"
            cleanup_success=false
        fi
        
        if [[ -n "${DEST_BUCKET_NAME:-}" ]] && aws s3api head-bucket --bucket "$DEST_BUCKET_NAME" &>/dev/null; then
            log "WARN" "Destination bucket still exists: $DEST_BUCKET_NAME"
            cleanup_success=false
        fi
    fi
    
    if [[ "$cleanup_success" == "true" ]]; then
        log "INFO" "Resource cleanup verification passed"
    else
        log "WARN" "Some resources may not have been fully cleaned up"
    fi
}

# Main cleanup function
main() {
    log "INFO" "Starting DataSync cleanup..."
    
    check_prerequisites
    load_deployment_info
    confirm_destruction
    stop_datasync_executions
    remove_eventbridge_scheduling
    remove_cloudwatch_resources
    remove_datasync_resources
    remove_iam_resources
    remove_s3_resources
    cleanup_local_files
    wait_for_cleanup
    
    log "INFO" "DataSync cleanup completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "All resources have been removed"
        log "INFO" "You may want to verify in the AWS console that all resources are deleted"
        log "INFO" "Check AWS Cost Explorer for any remaining charges"
    fi
}

# Run main function
main "$@"