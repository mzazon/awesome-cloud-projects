#!/bin/bash

# Destroy script for Event-Driven Data Processing with S3 Event Notifications
# This script removes all resources created by the deploy.sh script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Global variables
FORCE_DELETE=false
DRY_RUN=false
RESOURCE_PREFIX=""

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --prefix)
                RESOURCE_PREFIX="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

# Show help message
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy all resources created by the Event-Driven Data Processing recipe.

OPTIONS:
    --force         Skip confirmation prompts and force deletion
    --dry-run       Show what would be deleted without actually deleting
    --prefix PREFIX Specify resource prefix to delete (e.g., data-processing-abc123)
    -h, --help      Show this help message

EXAMPLES:
    $0                           # Interactive deletion with confirmations
    $0 --force                   # Delete without confirmations
    $0 --dry-run                 # Show what would be deleted
    $0 --prefix data-processing-abc123  # Delete specific deployment

WARNING: This operation is destructive and cannot be undone!
EOF
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
    fi
    
    log "Prerequisites check completed successfully"
}

# Setup environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warn "No AWS region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log "Environment configured:"
    info "  AWS Region: $AWS_REGION"
    info "  AWS Account ID: $AWS_ACCOUNT_ID"
}

# Discover resources to delete
discover_resources() {
    log "Discovering resources to delete..."
    
    # If prefix is provided, use it directly
    if [[ -n "$RESOURCE_PREFIX" ]]; then
        BUCKET_PREFIX="$RESOURCE_PREFIX"
        LAMBDA_PREFIX="$RESOURCE_PREFIX"
        log "Using provided prefix: $RESOURCE_PREFIX"
    else
        # Auto-discover resources by common naming patterns
        BUCKET_PREFIX="data-processing-"
        LAMBDA_PREFIX="data-processor-"
        log "Auto-discovering resources with common prefixes"
    fi
    
    # Find S3 buckets
    BUCKETS=$(aws s3api list-buckets \
        --query "Buckets[?starts_with(Name, '$BUCKET_PREFIX')].Name" \
        --output text)
    
    # Find Lambda functions
    LAMBDA_FUNCTIONS=$(aws lambda list-functions \
        --query "Functions[?starts_with(FunctionName, '$LAMBDA_PREFIX')].FunctionName" \
        --output text)
    
    # Find error handler functions
    ERROR_HANDLERS=$(aws lambda list-functions \
        --query "Functions[?starts_with(FunctionName, 'error-handler-')].FunctionName" \
        --output text)
    
    # Find SQS queues
    DLQ_QUEUES=$(aws sqs list-queues \
        --queue-name-prefix "data-processing-dlq-" \
        --query "QueueUrls" \
        --output text 2>/dev/null || echo "")
    
    # Find SNS topics
    SNS_TOPICS=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, 'data-processing-alerts-')].TopicArn" \
        --output text)
    
    # Find IAM roles
    IAM_ROLES=$(aws iam list-roles \
        --query "Roles[?starts_with(RoleName, 'data-processing-lambda-role-')].RoleName" \
        --output text)
    
    # Find CloudWatch alarms
    CW_ALARMS=$(aws cloudwatch describe-alarms \
        --query "MetricAlarms[?contains(AlarmName, 'data-processing') || contains(AlarmName, 'data-processor')].AlarmName" \
        --output text)
    
    log "Resource discovery completed"
}

# Display resources to be deleted
display_resources() {
    echo ""
    echo "========================================="
    echo "RESOURCES TO BE DELETED"
    echo "========================================="
    
    if [[ -n "$BUCKETS" ]]; then
        echo "S3 Buckets:"
        for bucket in $BUCKETS; do
            echo "  - $bucket"
        done
    fi
    
    if [[ -n "$LAMBDA_FUNCTIONS" ]]; then
        echo "Lambda Functions:"
        for func in $LAMBDA_FUNCTIONS; do
            echo "  - $func"
        done
    fi
    
    if [[ -n "$ERROR_HANDLERS" ]]; then
        echo "Error Handler Functions:"
        for func in $ERROR_HANDLERS; do
            echo "  - $func"
        done
    fi
    
    if [[ -n "$DLQ_QUEUES" ]]; then
        echo "SQS Queues:"
        for queue in $DLQ_QUEUES; do
            queue_name=$(basename "$queue")
            echo "  - $queue_name"
        done
    fi
    
    if [[ -n "$SNS_TOPICS" ]]; then
        echo "SNS Topics:"
        for topic in $SNS_TOPICS; do
            topic_name=$(basename "$topic")
            echo "  - $topic_name"
        done
    fi
    
    if [[ -n "$IAM_ROLES" ]]; then
        echo "IAM Roles:"
        for role in $IAM_ROLES; do
            echo "  - $role"
        done
    fi
    
    if [[ -n "$CW_ALARMS" ]]; then
        echo "CloudWatch Alarms:"
        for alarm in $CW_ALARMS; do
            echo "  - $alarm"
        done
    fi
    
    echo "========================================="
    echo ""
    
    # Check if any resources were found
    if [[ -z "$BUCKETS" && -z "$LAMBDA_FUNCTIONS" && -z "$ERROR_HANDLERS" && -z "$DLQ_QUEUES" && -z "$SNS_TOPICS" && -z "$IAM_ROLES" && -z "$CW_ALARMS" ]]; then
        warn "No resources found to delete. They may have already been deleted or use different naming conventions."
        return 1
    fi
    
    return 0
}

# Confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        warn "Force deletion enabled - skipping confirmation"
        return 0
    fi
    
    echo -e "${RED}WARNING: This operation will permanently delete all listed resources!${NC}"
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed by user"
}

# Remove S3 event notifications
remove_s3_notifications() {
    log "Removing S3 event notifications..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would remove S3 event notifications"
        return 0
    fi
    
    for bucket in $BUCKETS; do
        if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            info "Removing event notifications from bucket: $bucket"
            aws s3api put-bucket-notification-configuration \
                --bucket "$bucket" \
                --notification-configuration '{}' 2>/dev/null || true
        fi
    done
    
    log "S3 event notifications removed"
}

# Delete S3 buckets
delete_s3_buckets() {
    log "Deleting S3 buckets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete S3 buckets"
        return 0
    fi
    
    for bucket in $BUCKETS; do
        if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            info "Deleting bucket: $bucket"
            
            # Delete all objects and versions
            aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
            
            # Delete all object versions
            aws s3api list-object-versions \
                --bucket "$bucket" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | \
            while read -r key version_id; do
                if [[ -n "$key" && -n "$version_id" ]]; then
                    aws s3api delete-object \
                        --bucket "$bucket" \
                        --key "$key" \
                        --version-id "$version_id" 2>/dev/null || true
                fi
            done
            
            # Delete all delete markers
            aws s3api list-object-versions \
                --bucket "$bucket" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | \
            while read -r key version_id; do
                if [[ -n "$key" && -n "$version_id" ]]; then
                    aws s3api delete-object \
                        --bucket "$bucket" \
                        --key "$key" \
                        --version-id "$version_id" 2>/dev/null || true
                fi
            done
            
            # Delete the bucket
            aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
            log "Bucket deleted: $bucket"
        fi
    done
    
    log "S3 buckets deleted"
}

# Delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete Lambda functions"
        return 0
    fi
    
    # Delete data processor functions
    for func in $LAMBDA_FUNCTIONS; do
        info "Deleting Lambda function: $func"
        
        # Remove event source mappings first
        aws lambda list-event-source-mappings \
            --function-name "$func" \
            --query 'EventSourceMappings[].UUID' \
            --output text 2>/dev/null | \
        while read -r uuid; do
            if [[ -n "$uuid" ]]; then
                aws lambda delete-event-source-mapping \
                    --uuid "$uuid" 2>/dev/null || true
            fi
        done
        
        # Delete the function
        aws lambda delete-function --function-name "$func" 2>/dev/null || true
        log "Lambda function deleted: $func"
    done
    
    # Delete error handler functions
    for func in $ERROR_HANDLERS; do
        info "Deleting error handler function: $func"
        
        # Remove event source mappings first
        aws lambda list-event-source-mappings \
            --function-name "$func" \
            --query 'EventSourceMappings[].UUID' \
            --output text 2>/dev/null | \
        while read -r uuid; do
            if [[ -n "$uuid" ]]; then
                aws lambda delete-event-source-mapping \
                    --uuid "$uuid" 2>/dev/null || true
            fi
        done
        
        # Delete the function
        aws lambda delete-function --function-name "$func" 2>/dev/null || true
        log "Error handler function deleted: $func"
    done
    
    log "Lambda functions deleted"
}

# Delete SQS queues
delete_sqs_queues() {
    log "Deleting SQS queues..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete SQS queues"
        return 0
    fi
    
    for queue_url in $DLQ_QUEUES; do
        if [[ -n "$queue_url" ]]; then
            info "Deleting SQS queue: $(basename "$queue_url")"
            aws sqs delete-queue --queue-url "$queue_url" 2>/dev/null || true
            log "SQS queue deleted: $(basename "$queue_url")"
        fi
    done
    
    log "SQS queues deleted"
}

# Delete SNS topics
delete_sns_topics() {
    log "Deleting SNS topics..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete SNS topics"
        return 0
    fi
    
    for topic_arn in $SNS_TOPICS; do
        if [[ -n "$topic_arn" ]]; then
            info "Deleting SNS topic: $(basename "$topic_arn")"
            aws sns delete-topic --topic-arn "$topic_arn" 2>/dev/null || true
            log "SNS topic deleted: $(basename "$topic_arn")"
        fi
    done
    
    log "SNS topics deleted"
}

# Delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete CloudWatch alarms"
        return 0
    fi
    
    if [[ -n "$CW_ALARMS" ]]; then
        info "Deleting CloudWatch alarms"
        # Convert space-separated string to array for aws command
        alarm_array=($CW_ALARMS)
        aws cloudwatch delete-alarms --alarm-names "${alarm_array[@]}" 2>/dev/null || true
        log "CloudWatch alarms deleted"
    fi
    
    log "CloudWatch alarms processing completed"
}

# Delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete IAM roles"
        return 0
    fi
    
    for role_name in $IAM_ROLES; do
        if [[ -n "$role_name" ]]; then
            info "Deleting IAM role: $role_name"
            
            # Detach managed policies
            aws iam list-attached-role-policies \
                --role-name "$role_name" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null | \
            while read -r policy_arn; do
                if [[ -n "$policy_arn" ]]; then
                    aws iam detach-role-policy \
                        --role-name "$role_name" \
                        --policy-arn "$policy_arn" 2>/dev/null || true
                fi
            done
            
            # Delete inline policies
            aws iam list-role-policies \
                --role-name "$role_name" \
                --query 'PolicyNames' \
                --output text 2>/dev/null | \
            while read -r policy_name; do
                if [[ -n "$policy_name" ]]; then
                    aws iam delete-role-policy \
                        --role-name "$role_name" \
                        --policy-name "$policy_name" 2>/dev/null || true
                fi
            done
            
            # Delete the role
            aws iam delete-role --role-name "$role_name" 2>/dev/null || true
            log "IAM role deleted: $role_name"
        fi
    done
    
    log "IAM roles deleted"
}

# Wait for resource cleanup
wait_for_cleanup() {
    log "Waiting for resource cleanup to complete..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would wait for cleanup to complete"
        return 0
    fi
    
    # Wait a bit for eventual consistency
    sleep 5
    
    log "Cleanup wait completed"
}

# Verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local remaining_resources=false
    
    # Check for remaining S3 buckets
    for bucket in $BUCKETS; do
        if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            warn "S3 bucket still exists: $bucket"
            remaining_resources=true
        fi
    done
    
    # Check for remaining Lambda functions
    for func in $LAMBDA_FUNCTIONS $ERROR_HANDLERS; do
        if aws lambda get-function --function-name "$func" 2>/dev/null >/dev/null; then
            warn "Lambda function still exists: $func"
            remaining_resources=true
        fi
    done
    
    # Check for remaining SQS queues
    for queue_url in $DLQ_QUEUES; do
        if aws sqs get-queue-attributes --queue-url "$queue_url" 2>/dev/null >/dev/null; then
            warn "SQS queue still exists: $(basename "$queue_url")"
            remaining_resources=true
        fi
    done
    
    # Check for remaining SNS topics
    for topic_arn in $SNS_TOPICS; do
        if aws sns get-topic-attributes --topic-arn "$topic_arn" 2>/dev/null >/dev/null; then
            warn "SNS topic still exists: $(basename "$topic_arn")"
            remaining_resources=true
        fi
    done
    
    # Check for remaining IAM roles
    for role_name in $IAM_ROLES; do
        if aws iam get-role --role-name "$role_name" 2>/dev/null >/dev/null; then
            warn "IAM role still exists: $role_name"
            remaining_resources=true
        fi
    done
    
    if [[ "$remaining_resources" == "true" ]]; then
        warn "Some resources may still exist. This could be due to:"
        warn "  - AWS eventual consistency delays"
        warn "  - Resources in use by other services"
        warn "  - Permission issues"
        warn "Please check the AWS console and retry if needed."
    else
        log "All resources appear to have been deleted successfully"
    fi
}

# Print destruction summary
print_summary() {
    echo ""
    echo "========================================="
    echo "DESTRUCTION SUMMARY"
    echo "========================================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN MODE: No resources were actually deleted"
    else
        echo "Resource deletion completed"
    fi
    
    echo "AWS Region: $AWS_REGION"
    echo "Timestamp: $(date)"
    echo "========================================="
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "All Event-Driven Data Processing resources have been removed."
        echo "Please verify in the AWS console that all resources are deleted."
        echo ""
        echo "Note: Some resources may take a few minutes to fully delete"
        echo "due to AWS eventual consistency."
    fi
}

# Main destruction function
main() {
    log "Starting destruction of Event-Driven Data Processing resources"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Setup and discovery
    check_prerequisites
    setup_environment
    discover_resources
    
    # Display resources and confirm
    if ! display_resources; then
        log "No resources found to delete. Exiting."
        exit 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY-RUN mode enabled - no resources will be deleted"
    else
        confirm_deletion
    fi
    
    # Perform deletion in reverse order of creation
    remove_s3_notifications
    delete_cloudwatch_alarms
    delete_lambda_functions
    delete_sqs_queues
    delete_sns_topics
    delete_iam_roles
    delete_s3_buckets
    wait_for_cleanup
    
    # Verify and summarize
    if [[ "$DRY_RUN" == "false" ]]; then
        verify_deletion
    fi
    
    print_summary
    
    log "Destruction process completed"
}

# Run main function with all arguments
main "$@"