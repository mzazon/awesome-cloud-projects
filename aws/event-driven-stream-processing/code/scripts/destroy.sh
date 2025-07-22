#!/bin/bash

# Destroy script for Real-Time Data Processing with Amazon Kinesis and Lambda
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script metadata
SCRIPT_NAME="destroy.sh"
SCRIPT_VERSION="1.0"
RECIPE_NAME="real-time-data-processing-with-kinesis-lambda"

# Color codes for output
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

# Error handler
error_handler() {
    local line_number=$1
    log_error "Script failed at line $line_number"
    log_error "Cleanup may be incomplete. Please check AWS console for remaining resources."
    exit 1
}

trap 'error_handler ${LINENO}' ERR

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Real-Time Data Processing Pipeline resources

OPTIONS:
    -h, --help              Show this help message
    -f, --force             Skip confirmation prompts
    -r, --region REGION     AWS region (default: current configured region)
    -s, --suffix SUFFIX     Resource suffix to identify specific deployment
    --dry-run              Show what would be deleted without actually deleting
    --partial RESOURCE      Delete only specific resource type (kinesis|lambda|dynamodb|sqs|iam|cloudwatch|sns)
    -v, --verbose          Enable verbose logging

EXAMPLES:
    $0                              # Interactive cleanup with confirmations
    $0 --force                      # Force cleanup without confirmations
    $0 --suffix abc123              # Cleanup specific deployment
    $0 --dry-run                    # Show what would be deleted
    $0 --partial lambda             # Delete only Lambda resources

RESOURCE TYPES:
    kinesis     - Kinesis Data Stream
    lambda      - Lambda function and event source mapping
    dynamodb    - DynamoDB table
    sqs         - SQS Dead Letter Queue
    iam         - IAM roles and policies
    cloudwatch  - CloudWatch alarms
    sns         - SNS topics and subscriptions

EOF
}

# Default values
FORCE=false
DRY_RUN=false
VERBOSE=false
RESOURCE_SUFFIX=""
PARTIAL_CLEANUP=""

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
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -s|--suffix)
            RESOURCE_SUFFIX="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --partial)
            PARTIAL_CLEANUP="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Enable verbose logging if requested
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

log_info "Starting cleanup of Real-Time Data Processing Pipeline"
log_info "Script: $SCRIPT_NAME v$SCRIPT_VERSION"

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Validate AWS region
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            log_error "AWS region not configured. Set it with 'aws configure' or use --region option."
            exit 1
        fi
    fi
    
    log_info "Using AWS region: $AWS_REGION"
    
    # Check if region is valid
    if ! aws ec2 describe-regions --region-names "$AWS_REGION" &> /dev/null; then
        log_error "Invalid AWS region: $AWS_REGION"
        exit 1
    fi
    
    # Check required permissions (basic check)
    local caller_arn=$(aws sts get-caller-identity --query 'Arn' --output text)
    log_info "Running as: $caller_arn"
    
    log_success "Prerequisites check completed"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Try to load from deployment-info.json first
    if [[ -f "deployment-info.json" && -z "$RESOURCE_SUFFIX" ]]; then
        log_info "Found deployment-info.json, loading resource information..."
        
        if command -v jq &> /dev/null; then
            RESOURCE_SUFFIX=$(jq -r '.deploymentInfo.suffix' deployment-info.json 2>/dev/null || echo "")
            export AWS_ACCOUNT_ID=$(jq -r '.deploymentInfo.accountId' deployment-info.json 2>/dev/null || echo "")
        else
            log_warning "jq not found. Please provide resource suffix manually with --suffix option."
        fi
    fi
    
    # If still no suffix, prompt user or try to discover
    if [[ -z "$RESOURCE_SUFFIX" ]]; then
        if [[ "$FORCE" == "false" ]]; then
            read -p "Enter resource suffix (found in resource names): " RESOURCE_SUFFIX
            if [[ -z "$RESOURCE_SUFFIX" ]]; then
                log_error "Resource suffix is required to identify resources to delete."
                exit 1
            fi
        else
            log_error "Resource suffix is required when using --force. Use --suffix option."
            exit 1
        fi
    fi
    
    # Set AWS account ID if not already set
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    # Set resource names
    export STREAM_NAME="retail-events-stream-${RESOURCE_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="retail-event-processor-${RESOURCE_SUFFIX}"
    export DYNAMODB_TABLE="retail-events-data-${RESOURCE_SUFFIX}"
    export DLQ_QUEUE_NAME="failed-events-dlq-${RESOURCE_SUFFIX}"
    export ALARM_NAME="stream-processing-errors-${RESOURCE_SUFFIX}"
    export LAMBDA_ROLE_NAME="retail-event-processor-role-${RESOURCE_SUFFIX}"
    export POLICY_NAME="retail-event-processor-policy-${RESOURCE_SUFFIX}"
    export ALERT_TOPIC_NAME="retail-event-alerts-${RESOURCE_SUFFIX}"
    
    log_info "Resource suffix: $RESOURCE_SUFFIX"
    log_success "Deployment information loaded"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will permanently delete the following resources:"
    echo "  - Kinesis Stream: $STREAM_NAME"
    echo "  - Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "  - DynamoDB Table: $DYNAMODB_TABLE"
    echo "  - SQS Queue: $DLQ_QUEUE_NAME"
    echo "  - CloudWatch Alarm: $ALARM_NAME"
    echo "  - IAM Role: $LAMBDA_ROLE_NAME"
    echo "  - IAM Policy: retail-event-processor-policy-$RESOURCE_SUFFIX"
    echo "  - SNS Topic: $ALERT_TOPIC_NAME (if exists)"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "$resource_type" in
        "kinesis")
            aws kinesis describe-stream --stream-name "$resource_name" --region "$AWS_REGION" &>/dev/null
            ;;
        "lambda")
            aws lambda get-function --function-name "$resource_name" --region "$AWS_REGION" &>/dev/null
            ;;
        "dynamodb")
            aws dynamodb describe-table --table-name "$resource_name" --region "$AWS_REGION" &>/dev/null
            ;;
        "sqs")
            aws sqs get-queue-url --queue-name "$resource_name" --region "$AWS_REGION" &>/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" &>/dev/null
            ;;
        "iam-policy")
            aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$resource_name" &>/dev/null
            ;;
        "cloudwatch-alarm")
            aws cloudwatch describe-alarms --alarm-names "$resource_name" --region "$AWS_REGION" | grep -q "MetricAlarms"
            ;;
        "sns-topic")
            aws sns get-topic-attributes --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:$resource_name" --region "$AWS_REGION" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Delete Lambda resources
delete_lambda_resources() {
    if [[ -n "$PARTIAL_CLEANUP" && "$PARTIAL_CLEANUP" != "lambda" ]]; then
        return 0
    fi
    
    log_info "Cleaning up Lambda resources..."
    
    # Get event source mapping UUID if exists
    if resource_exists "lambda" "$LAMBDA_FUNCTION_NAME"; then
        local event_source_uuid=$(aws lambda list-event-source-mappings \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --query 'EventSourceMappings[0].UUID' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "None")
        
        if [[ "$event_source_uuid" != "None" && "$event_source_uuid" != "null" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete event source mapping: $event_source_uuid"
            else
                log_info "Deleting event source mapping: $event_source_uuid"
                aws lambda delete-event-source-mapping \
                    --uuid "$event_source_uuid" \
                    --region "$AWS_REGION"
                log_success "Event source mapping deleted"
            fi
        fi
        
        # Delete Lambda function
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete Lambda function: $LAMBDA_FUNCTION_NAME"
        else
            log_info "Deleting Lambda function: $LAMBDA_FUNCTION_NAME"
            aws lambda delete-function \
                --function-name "$LAMBDA_FUNCTION_NAME" \
                --region "$AWS_REGION"
            log_success "Lambda function deleted: $LAMBDA_FUNCTION_NAME"
        fi
    else
        log_warning "Lambda function not found: $LAMBDA_FUNCTION_NAME"
    fi
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    if [[ -n "$PARTIAL_CLEANUP" && "$PARTIAL_CLEANUP" != "cloudwatch" ]]; then
        return 0
    fi
    
    log_info "Cleaning up CloudWatch resources..."
    
    # Delete CloudWatch alarm
    if resource_exists "cloudwatch-alarm" "$ALARM_NAME"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete CloudWatch alarm: $ALARM_NAME"
        else
            log_info "Deleting CloudWatch alarm: $ALARM_NAME"
            aws cloudwatch delete-alarms \
                --alarm-names "$ALARM_NAME" \
                --region "$AWS_REGION"
            log_success "CloudWatch alarm deleted: $ALARM_NAME"
        fi
    else
        log_warning "CloudWatch alarm not found: $ALARM_NAME"
    fi
}

# Delete SNS resources
delete_sns_resources() {
    if [[ -n "$PARTIAL_CLEANUP" && "$PARTIAL_CLEANUP" != "sns" ]]; then
        return 0
    fi
    
    log_info "Cleaning up SNS resources..."
    
    # Delete SNS topic if exists
    if resource_exists "sns-topic" "$ALERT_TOPIC_NAME"; then
        local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${ALERT_TOPIC_NAME}"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete SNS topic: $ALERT_TOPIC_NAME"
        else
            log_info "Deleting SNS topic: $ALERT_TOPIC_NAME"
            aws sns delete-topic \
                --topic-arn "$topic_arn" \
                --region "$AWS_REGION"
            log_success "SNS topic deleted: $ALERT_TOPIC_NAME"
        fi
    else
        log_info "SNS topic not found (this is normal if no email was configured): $ALERT_TOPIC_NAME"
    fi
}

# Delete IAM resources
delete_iam_resources() {
    if [[ -n "$PARTIAL_CLEANUP" && "$PARTIAL_CLEANUP" != "iam" ]]; then
        return 0
    fi
    
    log_info "Cleaning up IAM resources..."
    
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    # Detach and delete policy
    if resource_exists "iam-policy" "$POLICY_NAME"; then
        if resource_exists "iam-role" "$LAMBDA_ROLE_NAME"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would detach policy from role"
            else
                log_info "Detaching policy from role..."
                aws iam detach-role-policy \
                    --role-name "$LAMBDA_ROLE_NAME" \
                    --policy-arn "$policy_arn" 2>/dev/null || true
            fi
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete IAM policy: $POLICY_NAME"
        else
            log_info "Deleting IAM policy: $POLICY_NAME"
            aws iam delete-policy --policy-arn "$policy_arn"
            log_success "IAM policy deleted: $POLICY_NAME"
        fi
    else
        log_warning "IAM policy not found: $POLICY_NAME"
    fi
    
    # Delete IAM role
    if resource_exists "iam-role" "$LAMBDA_ROLE_NAME"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete IAM role: $LAMBDA_ROLE_NAME"
        else
            log_info "Deleting IAM role: $LAMBDA_ROLE_NAME"
            aws iam delete-role --role-name "$LAMBDA_ROLE_NAME"
            log_success "IAM role deleted: $LAMBDA_ROLE_NAME"
        fi
    else
        log_warning "IAM role not found: $LAMBDA_ROLE_NAME"
    fi
}

# Delete SQS resources
delete_sqs_resources() {
    if [[ -n "$PARTIAL_CLEANUP" && "$PARTIAL_CLEANUP" != "sqs" ]]; then
        return 0
    fi
    
    log_info "Cleaning up SQS resources..."
    
    # Get queue URL if exists
    if resource_exists "sqs" "$DLQ_QUEUE_NAME"; then
        local queue_url=$(aws sqs get-queue-url \
            --queue-name "$DLQ_QUEUE_NAME" \
            --query 'QueueUrl' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "")
        
        if [[ -n "$queue_url" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete SQS queue: $DLQ_QUEUE_NAME"
            else
                log_info "Deleting SQS queue: $DLQ_QUEUE_NAME"
                aws sqs delete-queue \
                    --queue-url "$queue_url" \
                    --region "$AWS_REGION"
                log_success "SQS queue deleted: $DLQ_QUEUE_NAME"
            fi
        fi
    else
        log_warning "SQS queue not found: $DLQ_QUEUE_NAME"
    fi
}

# Delete DynamoDB resources
delete_dynamodb_resources() {
    if [[ -n "$PARTIAL_CLEANUP" && "$PARTIAL_CLEANUP" != "dynamodb" ]]; then
        return 0
    fi
    
    log_info "Cleaning up DynamoDB resources..."
    
    # Delete DynamoDB table
    if resource_exists "dynamodb" "$DYNAMODB_TABLE"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete DynamoDB table: $DYNAMODB_TABLE"
        else
            log_info "Deleting DynamoDB table: $DYNAMODB_TABLE"
            aws dynamodb delete-table \
                --table-name "$DYNAMODB_TABLE" \
                --region "$AWS_REGION"
            log_success "DynamoDB table deletion initiated: $DYNAMODB_TABLE"
            log_info "Note: Table deletion may take a few minutes to complete"
        fi
    else
        log_warning "DynamoDB table not found: $DYNAMODB_TABLE"
    fi
}

# Delete Kinesis resources
delete_kinesis_resources() {
    if [[ -n "$PARTIAL_CLEANUP" && "$PARTIAL_CLEANUP" != "kinesis" ]]; then
        return 0
    fi
    
    log_info "Cleaning up Kinesis resources..."
    
    # Delete Kinesis stream
    if resource_exists "kinesis" "$STREAM_NAME"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete Kinesis stream: $STREAM_NAME"
        else
            log_info "Deleting Kinesis stream: $STREAM_NAME"
            aws kinesis delete-stream \
                --stream-name "$STREAM_NAME" \
                --region "$AWS_REGION"
            log_success "Kinesis stream deletion initiated: $STREAM_NAME"
            log_info "Note: Stream deletion may take a few minutes to complete"
        fi
    else
        log_warning "Kinesis stream not found: $STREAM_NAME"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "generate_test_data.py"
        "deployment-info.json"
        "/tmp/lambda-trust-policy.json"
        "/tmp/lambda-policy.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would remove local file: $file"
            else
                rm -f "$file"
                log_success "Removed local file: $file"
            fi
        fi
    done
}

# Validate partial cleanup option
validate_partial_cleanup() {
    if [[ -n "$PARTIAL_CLEANUP" ]]; then
        local valid_options=("kinesis" "lambda" "dynamodb" "sqs" "iam" "cloudwatch" "sns")
        local is_valid=false
        
        for option in "${valid_options[@]}"; do
            if [[ "$PARTIAL_CLEANUP" == "$option" ]]; then
                is_valid=true
                break
            fi
        done
        
        if [[ "$is_valid" == "false" ]]; then
            log_error "Invalid partial cleanup option: $PARTIAL_CLEANUP"
            log_error "Valid options: ${valid_options[*]}"
            exit 1
        fi
        
        log_info "Partial cleanup mode: $PARTIAL_CLEANUP"
    fi
}

# Main cleanup function
main() {
    log_info "=== Real-Time Data Processing Pipeline Cleanup ==="
    
    check_prerequisites
    validate_partial_cleanup
    load_deployment_info
    confirm_destruction
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "=== DRY RUN MODE - No resources will be deleted ==="
    fi
    
    # Delete resources in reverse order of creation
    # This ensures dependencies are handled correctly
    delete_lambda_resources
    delete_cloudwatch_resources
    delete_sns_resources
    delete_iam_resources
    delete_sqs_resources
    delete_dynamodb_resources
    delete_kinesis_resources
    cleanup_local_files
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "Dry run completed. No resources were actually deleted."
    else
        # Display cleanup summary
        cat << EOF

=== CLEANUP COMPLETED ===

Resources deleted:
- Kinesis Stream: $STREAM_NAME
- Lambda Function: $LAMBDA_FUNCTION_NAME
- DynamoDB Table: $DYNAMODB_TABLE
- SQS Dead Letter Queue: $DLQ_QUEUE_NAME
- CloudWatch Alarm: $ALARM_NAME
- IAM Role and Policy: $LAMBDA_ROLE_NAME

Note: Some resources (like DynamoDB tables and Kinesis streams) may take 
several minutes to be fully deleted from AWS.

Local files have been cleaned up.

EOF

        log_success "Cleanup completed successfully!"
    fi
}

# Run main function
main "$@"