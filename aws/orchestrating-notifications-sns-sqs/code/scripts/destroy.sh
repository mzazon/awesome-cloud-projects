#!/bin/bash

# Destroy script for Serverless Notification Systems with SNS, SQS, and Lambda
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error

# Script configuration
SCRIPT_NAME="destroy.sh"
LOG_FILE="/tmp/notification-system-destroy.log"
DEPLOYMENT_INFO_FILE="/tmp/deployment-info.json"
CLEANUP_START_TIME=$(date +%s)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code $exit_code"
    log_error "Check the log file at $LOG_FILE for details"
    log_error "Some resources may still exist and need manual cleanup"
    exit $exit_code
}

trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
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
    
    log_success "Prerequisites check completed"
}

# Function to prompt for confirmation
prompt_for_confirmation() {
    echo ""
    echo "⚠️  WARNING: This will DELETE all resources created by the deployment script!"
    echo ""
    echo "This action will remove:"
    echo "  • SNS Topics and subscriptions"
    echo "  • SQS Queues (including messages)"
    echo "  • Lambda Functions"
    echo "  • IAM Roles and Policies"
    echo "  • Event Source Mappings"
    echo ""
    
    # Check if running in non-interactive mode
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        log_warning "FORCE_DESTROY is set, skipping confirmation prompt"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "User confirmed resource deletion"
}

# Function to load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        log "Found deployment info file: $DEPLOYMENT_INFO_FILE"
        
        # Extract resource information from JSON file
        export AWS_REGION=$(jq -r '.aws_region' "$DEPLOYMENT_INFO_FILE")
        export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$DEPLOYMENT_INFO_FILE")
        export RANDOM_SUFFIX=$(jq -r '.random_suffix' "$DEPLOYMENT_INFO_FILE")
        
        # Extract resource names and ARNs
        export SNS_TOPIC_NAME=$(jq -r '.resources.sns_topic.name' "$DEPLOYMENT_INFO_FILE")
        export SNS_TOPIC_ARN=$(jq -r '.resources.sns_topic.arn' "$DEPLOYMENT_INFO_FILE")
        
        export EMAIL_QUEUE_NAME=$(jq -r '.resources.sqs_queues.email_queue.name' "$DEPLOYMENT_INFO_FILE")
        export EMAIL_QUEUE_URL=$(jq -r '.resources.sqs_queues.email_queue.url' "$DEPLOYMENT_INFO_FILE")
        export EMAIL_QUEUE_ARN=$(jq -r '.resources.sqs_queues.email_queue.arn' "$DEPLOYMENT_INFO_FILE")
        
        export SMS_QUEUE_NAME=$(jq -r '.resources.sqs_queues.sms_queue.name' "$DEPLOYMENT_INFO_FILE")
        export SMS_QUEUE_URL=$(jq -r '.resources.sqs_queues.sms_queue.url' "$DEPLOYMENT_INFO_FILE")
        export SMS_QUEUE_ARN=$(jq -r '.resources.sqs_queues.sms_queue.arn' "$DEPLOYMENT_INFO_FILE")
        
        export WEBHOOK_QUEUE_NAME=$(jq -r '.resources.sqs_queues.webhook_queue.name' "$DEPLOYMENT_INFO_FILE")
        export WEBHOOK_QUEUE_URL=$(jq -r '.resources.sqs_queues.webhook_queue.url' "$DEPLOYMENT_INFO_FILE")
        export WEBHOOK_QUEUE_ARN=$(jq -r '.resources.sqs_queues.webhook_queue.arn' "$DEPLOYMENT_INFO_FILE")
        
        export DLQ_NAME=$(jq -r '.resources.sqs_queues.dead_letter_queue.name' "$DEPLOYMENT_INFO_FILE")
        export DLQ_URL=$(jq -r '.resources.sqs_queues.dead_letter_queue.url' "$DEPLOYMENT_INFO_FILE")
        export DLQ_ARN=$(jq -r '.resources.sqs_queues.dead_letter_queue.arn' "$DEPLOYMENT_INFO_FILE")
        
        export EMAIL_LAMBDA_NAME=$(jq -r '.resources.lambda_functions.email_handler.name' "$DEPLOYMENT_INFO_FILE")
        export EMAIL_LAMBDA_ARN=$(jq -r '.resources.lambda_functions.email_handler.arn' "$DEPLOYMENT_INFO_FILE")
        
        export WEBHOOK_LAMBDA_NAME=$(jq -r '.resources.lambda_functions.webhook_handler.name' "$DEPLOYMENT_INFO_FILE")
        export WEBHOOK_LAMBDA_ARN=$(jq -r '.resources.lambda_functions.webhook_handler.arn' "$DEPLOYMENT_INFO_FILE")
        
        export IAM_ROLE_NAME=$(jq -r '.resources.iam_role.name' "$DEPLOYMENT_INFO_FILE")
        export LAMBDA_ROLE_ARN=$(jq -r '.resources.iam_role.arn' "$DEPLOYMENT_INFO_FILE")
        
        log_success "Loaded deployment information from JSON file"
    else
        log_warning "Deployment info file not found, attempting to discover resources..."
        discover_resources
    fi
}

# Function to discover resources by pattern matching
discover_resources() {
    log "Discovering resources by pattern matching..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "AWS region not configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Discover SNS topics
    SNS_TOPICS=$(aws sns list-topics --query 'Topics[].TopicArn' --output text | \
        grep -E "notification-system-[a-z0-9]{6}$" || echo "")
    
    # Discover SQS queues
    SQS_QUEUES=$(aws sqs list-queues --query 'QueueUrls[]' --output text | \
        grep -E "(email-notifications|sms-notifications|webhook-notifications|notification-dlq)-[a-z0-9]{6}$" || echo "")
    
    # Discover Lambda functions
    LAMBDA_FUNCTIONS=$(aws lambda list-functions --query 'Functions[].FunctionName' --output text | \
        grep -E "(EmailNotificationHandler|WebhookNotificationHandler)-[a-z0-9]{6}$" || echo "")
    
    # Discover IAM roles
    IAM_ROLES=$(aws iam list-roles --query 'Roles[].RoleName' --output text | \
        grep -E "NotificationLambdaRole-[a-z0-9]{6}$" || echo "")
    
    log_success "Resource discovery completed"
}

# Function to delete Lambda functions and event source mappings
delete_lambda_functions() {
    log "Deleting Lambda functions and event source mappings..."
    
    # Delete event source mappings for email Lambda
    if [[ -n "${EMAIL_LAMBDA_NAME:-}" ]]; then
        log "Deleting event source mappings for $EMAIL_LAMBDA_NAME..."
        aws lambda list-event-source-mappings \
            --function-name "$EMAIL_LAMBDA_NAME" \
            --query 'EventSourceMappings[].UUID' --output text | \
        while read -r uuid; do
            if [[ -n "$uuid" && "$uuid" != "None" ]]; then
                aws lambda delete-event-source-mapping --uuid "$uuid" || true
                log_success "Deleted event source mapping: $uuid"
            fi
        done
    fi
    
    # Delete event source mappings for webhook Lambda
    if [[ -n "${WEBHOOK_LAMBDA_NAME:-}" ]]; then
        log "Deleting event source mappings for $WEBHOOK_LAMBDA_NAME..."
        aws lambda list-event-source-mappings \
            --function-name "$WEBHOOK_LAMBDA_NAME" \
            --query 'EventSourceMappings[].UUID' --output text | \
        while read -r uuid; do
            if [[ -n "$uuid" && "$uuid" != "None" ]]; then
                aws lambda delete-event-source-mapping --uuid "$uuid" || true
                log_success "Deleted event source mapping: $uuid"
            fi
        done
    fi
    
    # Delete Lambda functions
    for function_name in "${EMAIL_LAMBDA_NAME:-}" "${WEBHOOK_LAMBDA_NAME:-}"; do
        if [[ -n "$function_name" ]]; then
            if aws lambda get-function --function-name "$function_name" &>/dev/null; then
                aws lambda delete-function --function-name "$function_name"
                log_success "Deleted Lambda function: $function_name"
            else
                log_warning "Lambda function not found: $function_name"
            fi
        fi
    done
    
    # Also discover and delete any remaining notification system Lambda functions
    if [[ -n "${LAMBDA_FUNCTIONS:-}" ]]; then
        for function_name in $LAMBDA_FUNCTIONS; do
            if aws lambda get-function --function-name "$function_name" &>/dev/null; then
                # Delete event source mappings first
                aws lambda list-event-source-mappings \
                    --function-name "$function_name" \
                    --query 'EventSourceMappings[].UUID' --output text | \
                while read -r uuid; do
                    if [[ -n "$uuid" && "$uuid" != "None" ]]; then
                        aws lambda delete-event-source-mapping --uuid "$uuid" || true
                    fi
                done
                
                # Delete the function
                aws lambda delete-function --function-name "$function_name"
                log_success "Deleted discovered Lambda function: $function_name"
            fi
        done
    fi
    
    log_success "Lambda functions and event source mappings cleanup completed"
}

# Function to delete SQS queues
delete_sqs_queues() {
    log "Deleting SQS queues..."
    
    # Delete queues using deployment info
    for queue_url in "${EMAIL_QUEUE_URL:-}" "${SMS_QUEUE_URL:-}" "${WEBHOOK_QUEUE_URL:-}" "${DLQ_URL:-}"; do
        if [[ -n "$queue_url" ]]; then
            if aws sqs get-queue-attributes --queue-url "$queue_url" --attribute-names QueueArn &>/dev/null; then
                aws sqs delete-queue --queue-url "$queue_url"
                queue_name=$(basename "$queue_url")
                log_success "Deleted SQS queue: $queue_name"
            else
                log_warning "SQS queue not found: $queue_url"
            fi
        fi
    done
    
    # Also discover and delete any remaining notification system queues
    if [[ -n "${SQS_QUEUES:-}" ]]; then
        for queue_url in $SQS_QUEUES; do
            if aws sqs get-queue-attributes --queue-url "$queue_url" --attribute-names QueueArn &>/dev/null; then
                aws sqs delete-queue --queue-url "$queue_url"
                queue_name=$(basename "$queue_url")
                log_success "Deleted discovered SQS queue: $queue_name"
            fi
        done
    fi
    
    log_success "SQS queues cleanup completed"
}

# Function to delete SNS topics
delete_sns_topics() {
    log "Deleting SNS topics and subscriptions..."
    
    # Delete topic using deployment info
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
            # List and delete subscriptions first
            aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" \
                --query 'Subscriptions[].SubscriptionArn' --output text | \
            while read -r subscription_arn; do
                if [[ -n "$subscription_arn" && "$subscription_arn" != "None" ]]; then
                    aws sns unsubscribe --subscription-arn "$subscription_arn" || true
                    log_success "Deleted subscription: $subscription_arn"
                fi
            done
            
            # Delete the topic
            aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN"
            log_success "Deleted SNS topic: $SNS_TOPIC_NAME"
        else
            log_warning "SNS topic not found: $SNS_TOPIC_ARN"
        fi
    fi
    
    # Also discover and delete any remaining notification system topics
    if [[ -n "${SNS_TOPICS:-}" ]]; then
        for topic_arn in $SNS_TOPICS; do
            if aws sns get-topic-attributes --topic-arn "$topic_arn" &>/dev/null; then
                # Delete subscriptions first
                aws sns list-subscriptions-by-topic --topic-arn "$topic_arn" \
                    --query 'Subscriptions[].SubscriptionArn' --output text | \
                while read -r subscription_arn; do
                    if [[ -n "$subscription_arn" && "$subscription_arn" != "None" ]]; then
                        aws sns unsubscribe --subscription-arn "$subscription_arn" || true
                    fi
                done
                
                # Delete the topic
                aws sns delete-topic --topic-arn "$topic_arn"
                topic_name=$(basename "$topic_arn")
                log_success "Deleted discovered SNS topic: $topic_name"
            fi
        done
    fi
    
    log_success "SNS topics cleanup completed"
}

# Function to delete IAM roles and policies
delete_iam_resources() {
    log "Deleting IAM roles and policies..."
    
    # Delete IAM role using deployment info
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
            # Detach managed policies
            aws iam list-attached-role-policies --role-name "$IAM_ROLE_NAME" \
                --query 'AttachedPolicies[].PolicyArn' --output text | \
            while read -r policy_arn; do
                if [[ -n "$policy_arn" && "$policy_arn" != "None" ]]; then
                    aws iam detach-role-policy --role-name "$IAM_ROLE_NAME" --policy-arn "$policy_arn"
                    log_success "Detached policy: $policy_arn"
                fi
            done
            
            # Delete inline policies
            aws iam list-role-policies --role-name "$IAM_ROLE_NAME" \
                --query 'PolicyNames[]' --output text | \
            while read -r policy_name; do
                if [[ -n "$policy_name" && "$policy_name" != "None" ]]; then
                    aws iam delete-role-policy --role-name "$IAM_ROLE_NAME" --policy-name "$policy_name"
                    log_success "Deleted inline policy: $policy_name"
                fi
            done
            
            # Delete the role
            aws iam delete-role --role-name "$IAM_ROLE_NAME"
            log_success "Deleted IAM role: $IAM_ROLE_NAME"
        else
            log_warning "IAM role not found: $IAM_ROLE_NAME"
        fi
    fi
    
    # Also discover and delete any remaining notification system IAM roles
    if [[ -n "${IAM_ROLES:-}" ]]; then
        for role_name in $IAM_ROLES; do
            if aws iam get-role --role-name "$role_name" &>/dev/null; then
                # Detach managed policies
                aws iam list-attached-role-policies --role-name "$role_name" \
                    --query 'AttachedPolicies[].PolicyArn' --output text | \
                while read -r policy_arn; do
                    if [[ -n "$policy_arn" && "$policy_arn" != "None" ]]; then
                        aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" || true
                    fi
                done
                
                # Delete inline policies
                aws iam list-role-policies --role-name "$role_name" \
                    --query 'PolicyNames[]' --output text | \
                while read -r policy_name; do
                    if [[ -n "$policy_name" && "$policy_name" != "None" ]]; then
                        aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" || true
                    fi
                done
                
                # Delete the role
                aws iam delete-role --role-name "$role_name"
                log_success "Deleted discovered IAM role: $role_name"
            fi
        done
    fi
    
    log_success "IAM resources cleanup completed"
}

# Function to clean up local files
clean_up_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files
    local temp_files=(
        "/tmp/lambda-trust-policy.json"
        "/tmp/sqs-access-policy.json"
        "/tmp/email_handler.py"
        "/tmp/email_handler.zip"
        "/tmp/webhook_handler.py"
        "/tmp/webhook_handler.zip"
        "/tmp/publish_notification.py"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Removed temporary file: $file"
        fi
    done
    
    # Clean up environment variables
    unset SNS_TOPIC_NAME EMAIL_QUEUE_NAME SMS_QUEUE_NAME
    unset WEBHOOK_QUEUE_NAME DLQ_NAME IAM_ROLE_NAME
    unset EMAIL_LAMBDA_NAME WEBHOOK_LAMBDA_NAME
    unset SNS_TOPIC_ARN EMAIL_QUEUE_URL SMS_QUEUE_URL
    unset WEBHOOK_QUEUE_URL DLQ_URL LAMBDA_ROLE_ARN
    unset EMAIL_LAMBDA_ARN WEBHOOK_LAMBDA_ARN
    unset EMAIL_QUEUE_ARN SMS_QUEUE_ARN WEBHOOK_QUEUE_ARN DLQ_ARN
    
    log_success "Local files cleanup completed"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local cleanup_issues=0
    
    # Check for remaining SNS topics
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
            log_warning "SNS topic still exists: $SNS_TOPIC_ARN"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check for remaining SQS queues
    for queue_url in "${EMAIL_QUEUE_URL:-}" "${SMS_QUEUE_URL:-}" "${WEBHOOK_QUEUE_URL:-}" "${DLQ_URL:-}"; do
        if [[ -n "$queue_url" ]]; then
            if aws sqs get-queue-attributes --queue-url "$queue_url" --attribute-names QueueArn &>/dev/null; then
                log_warning "SQS queue still exists: $queue_url"
                cleanup_issues=$((cleanup_issues + 1))
            fi
        fi
    done
    
    # Check for remaining Lambda functions
    for function_name in "${EMAIL_LAMBDA_NAME:-}" "${WEBHOOK_LAMBDA_NAME:-}"; do
        if [[ -n "$function_name" ]]; then
            if aws lambda get-function --function-name "$function_name" &>/dev/null; then
                log_warning "Lambda function still exists: $function_name"
                cleanup_issues=$((cleanup_issues + 1))
            fi
        fi
    done
    
    # Check for remaining IAM roles
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
            log_warning "IAM role still exists: $IAM_ROLE_NAME"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "Cleanup validation passed - no remaining resources found"
    else
        log_warning "Cleanup validation found $cleanup_issues remaining resources"
        log_warning "You may need to manually delete these resources"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    local cleanup_end_time=$(date +%s)
    local cleanup_duration=$((cleanup_end_time - CLEANUP_START_TIME))
    
    echo ""
    echo "=================================="
    echo "  CLEANUP COMPLETED SUCCESSFULLY"
    echo "=================================="
    echo ""
    echo "📋 Cleanup Summary:"
    echo "  • Region: ${AWS_REGION:-N/A}"
    echo "  • Account ID: ${AWS_ACCOUNT_ID:-N/A}"
    echo "  • Cleanup Duration: ${cleanup_duration}s"
    echo ""
    echo "🗑️  Removed Resources:"
    echo "  • SNS Topics and subscriptions"
    echo "  • SQS Queues (email, SMS, webhook, DLQ)"
    echo "  • Lambda Functions (email handler, webhook handler)"
    echo "  • IAM Roles and policies"
    echo "  • Event Source Mappings"
    echo "  • Local temporary files"
    echo ""
    echo "📝 Cleanup Log: $LOG_FILE"
    echo ""
    echo "💡 Note: If you encounter any issues, check the AWS console"
    echo "   to verify all resources have been removed."
    echo ""
}

# Function to remove deployment info file
remove_deployment_info() {
    log "Removing deployment info file..."
    
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        rm -f "$DEPLOYMENT_INFO_FILE"
        log_success "Removed deployment info file: $DEPLOYMENT_INFO_FILE"
    else
        log_warning "Deployment info file not found: $DEPLOYMENT_INFO_FILE"
    fi
}

# Main cleanup function
main() {
    log "Starting cleanup of Serverless Notification System..."
    log "Log file: $LOG_FILE"
    
    check_prerequisites
    prompt_for_confirmation
    load_deployment_info
    
    # Delete resources in reverse order of creation
    delete_lambda_functions
    delete_sqs_queues
    delete_sns_topics
    delete_iam_resources
    clean_up_local_files
    
    validate_cleanup
    remove_deployment_info
    display_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Run main function
main "$@"