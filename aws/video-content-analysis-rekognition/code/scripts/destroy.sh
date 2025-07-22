#!/bin/bash

# Video Content Analysis with AWS Elemental MediaAnalyzer - Cleanup Script
# This script removes all resources created for the video content analysis infrastructure

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 is not installed or not in PATH"
        exit 1
    fi
}

# Function to validate AWS credentials
validate_aws_credentials() {
    info "Validating AWS credentials..."
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    
    if [ -z "$region" ]; then
        error "AWS region not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "AWS Account ID: $account_id"
    log "AWS Region: $region"
}

# Function to load resource names from environment file
load_resource_names() {
    info "Loading resource names..."
    
    # Check if environment file exists
    if [ -f "/tmp/video-analysis-resources.env" ]; then
        source /tmp/video-analysis-resources.env
        log "Loaded resource names from environment file"
    else
        warn "Environment file not found. Attempting to discover resources..."
        
        # Set basic environment variables
        export AWS_REGION=$(aws configure get region)
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Try to discover resources by common naming patterns
        discover_resources
    fi
    
    log "Resource names loaded:"
    log "  - AWS Region: $AWS_REGION"
    log "  - AWS Account: $AWS_ACCOUNT_ID"
    log "  - Source Bucket: $SOURCE_BUCKET"
    log "  - Results Bucket: $RESULTS_BUCKET"
    log "  - Temp Bucket: $TEMP_BUCKET"
    log "  - DynamoDB Table: $ANALYSIS_TABLE"
    log "  - SNS Topic: $SNS_TOPIC"
    log "  - SQS Queue: $SQS_QUEUE"
}

# Function to discover resources when environment file is not available
discover_resources() {
    info "Discovering resources..."
    
    # Discover S3 buckets
    local buckets=($(aws s3api list-buckets --query 'Buckets[?contains(Name, `video-source-`) || contains(Name, `video-results-`) || contains(Name, `video-temp-`)].Name' --output text))
    
    for bucket in "${buckets[@]}"; do
        if [[ $bucket == *"video-source-"* ]]; then
            export SOURCE_BUCKET="$bucket"
        elif [[ $bucket == *"video-results-"* ]]; then
            export RESULTS_BUCKET="$bucket"
        elif [[ $bucket == *"video-temp-"* ]]; then
            export TEMP_BUCKET="$bucket"
        fi
    done
    
    # Discover DynamoDB table
    export ANALYSIS_TABLE=$(aws dynamodb list-tables --query 'TableNames[?contains(@, `video-analysis-results-`)]' --output text)
    
    # Discover SNS topics
    export SNS_TOPIC=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `video-analysis-notifications-`)].TopicArn' --output text)
    
    # Discover SQS queues
    export SQS_QUEUE_URL=$(aws sqs list-queues --query 'QueueUrls[?contains(@, `video-analysis-queue-`)]' --output text)
    
    # Extract queue name from URL
    if [ -n "$SQS_QUEUE_URL" ]; then
        export SQS_QUEUE=$(basename "$SQS_QUEUE_URL")
    fi
    
    log "Resource discovery completed"
}

# Function to confirm destructive action
confirm_destruction() {
    warn "This will permanently delete all Video Content Analysis resources!"
    warn "The following resources will be removed:"
    warn "  - S3 Buckets and all contents"
    warn "  - DynamoDB Table and all data"
    warn "  - Lambda Functions"
    warn "  - Step Functions State Machine"
    warn "  - IAM Roles and Policies"
    warn "  - SNS Topics and SQS Queues"
    warn "  - CloudWatch Dashboards and Alarms"
    warn ""
    warn "This action cannot be undone!"
    warn ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    log "Proceeding with resource cleanup..."
}

# Function to delete Step Functions state machine
delete_state_machine() {
    info "Deleting Step Functions state machine..."
    
    # Find state machine ARN
    local state_machine_arn=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?name=='VideoAnalysisWorkflow'].stateMachineArn" \
        --output text)
    
    if [ -n "$state_machine_arn" ] && [ "$state_machine_arn" != "None" ]; then
        # Stop any running executions
        local running_executions=$(aws stepfunctions list-executions \
            --state-machine-arn "$state_machine_arn" \
            --status-filter RUNNING \
            --query 'executions[].executionArn' \
            --output text)
        
        if [ -n "$running_executions" ]; then
            warn "Stopping running executions..."
            for execution in $running_executions; do
                aws stepfunctions stop-execution --execution-arn "$execution" || true
            done
        fi
        
        # Delete state machine
        aws stepfunctions delete-state-machine --state-machine-arn "$state_machine_arn"
        log "Deleted Step Functions state machine"
    else
        warn "Step Functions state machine not found or already deleted"
    fi
}

# Function to delete Lambda functions
delete_lambda_functions() {
    info "Deleting Lambda functions..."
    
    local functions=(
        "VideoAnalysisInitFunction"
        "VideoAnalysisModerationFunction"
        "VideoAnalysisSegmentFunction"
        "VideoAnalysisAggregationFunction"
        "VideoAnalysisTriggerFunction"
    )
    
    for function in "${functions[@]}"; do
        if aws lambda get-function --function-name "$function" &>/dev/null; then
            # Remove S3 trigger permission if exists
            if [ "$function" == "VideoAnalysisTriggerFunction" ]; then
                aws lambda remove-permission \
                    --function-name "$function" \
                    --statement-id s3-trigger &>/dev/null || true
            fi
            
            # Delete function
            aws lambda delete-function --function-name "$function"
            log "Deleted Lambda function: $function"
        else
            warn "Lambda function $function not found or already deleted"
        fi
    done
    
    log "All Lambda functions deleted"
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    info "Deleting DynamoDB table..."
    
    if [ -n "$ANALYSIS_TABLE" ] && aws dynamodb describe-table --table-name "$ANALYSIS_TABLE" &>/dev/null; then
        aws dynamodb delete-table --table-name "$ANALYSIS_TABLE"
        
        # Wait for table deletion to complete
        log "Waiting for DynamoDB table deletion to complete..."
        aws dynamodb wait table-not-exists --table-name "$ANALYSIS_TABLE"
        
        log "Deleted DynamoDB table: $ANALYSIS_TABLE"
    else
        warn "DynamoDB table not found or already deleted"
    fi
}

# Function to delete S3 buckets
delete_s3_buckets() {
    info "Deleting S3 buckets and contents..."
    
    local buckets=("$SOURCE_BUCKET" "$RESULTS_BUCKET" "$TEMP_BUCKET")
    
    for bucket in "${buckets[@]}"; do
        if [ -n "$bucket" ] && aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
            # Remove bucket notification configuration
            aws s3api put-bucket-notification-configuration \
                --bucket "$bucket" \
                --notification-configuration '{}' &>/dev/null || true
            
            # Delete all objects and versions
            info "Emptying bucket: $bucket"
            aws s3 rm "s3://$bucket" --recursive &>/dev/null || true
            
            # Delete bucket
            aws s3 rb "s3://$bucket" &>/dev/null || true
            log "Deleted S3 bucket: $bucket"
        else
            warn "S3 bucket $bucket not found or already deleted"
        fi
    done
    
    log "All S3 buckets deleted"
}

# Function to delete SNS and SQS resources
delete_messaging_resources() {
    info "Deleting SNS and SQS resources..."
    
    # Delete SQS queue
    if [ -n "$SQS_QUEUE_URL" ]; then
        aws sqs delete-queue --queue-url "$SQS_QUEUE_URL" &>/dev/null || true
        log "Deleted SQS queue: $SQS_QUEUE"
    else
        warn "SQS queue not found or already deleted"
    fi
    
    # Delete SNS topic
    if [ -n "$SNS_TOPIC" ]; then
        aws sns delete-topic --topic-arn "$SNS_TOPIC" &>/dev/null || true
        log "Deleted SNS topic: $SNS_TOPIC"
    else
        warn "SNS topic not found or already deleted"
    fi
    
    log "Messaging resources deleted"
}

# Function to delete IAM roles and policies
delete_iam_resources() {
    info "Deleting IAM roles and policies..."
    
    # Delete Lambda role
    if aws iam get-role --role-name VideoAnalysisLambdaRole &>/dev/null; then
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name VideoAnalysisLambdaRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole &>/dev/null || true
        
        # Detach custom policy
        aws iam detach-role-policy \
            --role-name VideoAnalysisLambdaRole \
            --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/VideoAnalysisPolicy" &>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name VideoAnalysisLambdaRole
        log "Deleted Lambda IAM role"
    else
        warn "Lambda IAM role not found or already deleted"
    fi
    
    # Delete Step Functions role
    if aws iam get-role --role-name VideoAnalysisStepFunctionsRole &>/dev/null; then
        # Detach custom policy
        aws iam detach-role-policy \
            --role-name VideoAnalysisStepFunctionsRole \
            --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/VideoAnalysisStepFunctionsPolicy" &>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name VideoAnalysisStepFunctionsRole
        log "Deleted Step Functions IAM role"
    else
        warn "Step Functions IAM role not found or already deleted"
    fi
    
    # Delete custom policies
    local policies=(
        "VideoAnalysisPolicy"
        "VideoAnalysisStepFunctionsPolicy"
    )
    
    for policy in "${policies[@]}"; do
        if aws iam get-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$policy" &>/dev/null; then
            aws iam delete-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$policy"
            log "Deleted custom policy: $policy"
        else
            warn "Custom policy $policy not found or already deleted"
        fi
    done
    
    log "IAM resources deleted"
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    info "Deleting CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name VideoAnalysisDashboard &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names VideoAnalysisDashboard
        log "Deleted CloudWatch dashboard"
    else
        warn "CloudWatch dashboard not found or already deleted"
    fi
    
    # Delete CloudWatch alarm
    if aws cloudwatch describe-alarms --alarm-names VideoAnalysisFailedExecutions &>/dev/null; then
        aws cloudwatch delete-alarms --alarm-names VideoAnalysisFailedExecutions
        log "Deleted CloudWatch alarm"
    else
        warn "CloudWatch alarm not found or already deleted"
    fi
    
    # Delete log groups
    local log_groups=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/lambda/VideoAnalysis" \
        --query 'logGroups[].logGroupName' \
        --output text)
    
    if [ -n "$log_groups" ]; then
        for log_group in $log_groups; do
            aws logs delete-log-group --log-group-name "$log_group"
            log "Deleted log group: $log_group"
        done
    fi
    
    log "CloudWatch resources deleted"
}

# Function to clean up temporary files
cleanup_temp_files() {
    info "Cleaning up temporary files..."
    
    # Remove temporary Lambda packages
    rm -rf /tmp/lambda-packages &>/dev/null || true
    
    # Remove state machine definition
    rm -f /tmp/video-analysis-state-machine.json &>/dev/null || true
    
    # Remove environment file
    rm -f /tmp/video-analysis-resources.env &>/dev/null || true
    
    log "Temporary files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check S3 buckets
    local remaining_buckets=($(aws s3api list-buckets --query 'Buckets[?contains(Name, `video-source-`) || contains(Name, `video-results-`) || contains(Name, `video-temp-`)].Name' --output text))
    if [ ${#remaining_buckets[@]} -gt 0 ]; then
        warn "Some S3 buckets may still exist: ${remaining_buckets[*]}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check DynamoDB tables
    local remaining_tables=$(aws dynamodb list-tables --query 'TableNames[?contains(@, `video-analysis-results-`)]' --output text)
    if [ -n "$remaining_tables" ]; then
        warn "Some DynamoDB tables may still exist: $remaining_tables"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check Lambda functions
    local remaining_functions=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `VideoAnalysis`)].FunctionName' --output text)
    if [ -n "$remaining_functions" ]; then
        warn "Some Lambda functions may still exist: $remaining_functions"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check Step Functions state machines
    local remaining_state_machines=$(aws stepfunctions list-state-machines --query "stateMachines[?name=='VideoAnalysisWorkflow'].name" --output text)
    if [ -n "$remaining_state_machines" ]; then
        warn "Some Step Functions state machines may still exist: $remaining_state_machines"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log "Cleanup verification completed successfully"
    else
        warn "Cleanup verification found $cleanup_issues potential issues"
        warn "Some resources may take additional time to be fully removed"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "============================================="
    log "Video Content Analysis Cleanup Complete!"
    log "============================================="
    log ""
    log "Resources Removed:"
    log "  - S3 Buckets and contents"
    log "  - DynamoDB Table and data"
    log "  - Lambda Functions"
    log "  - Step Functions State Machine"
    log "  - IAM Roles and Policies"
    log "  - SNS Topics and SQS Queues"
    log "  - CloudWatch Dashboards and Alarms"
    log "  - CloudWatch Log Groups"
    log "  - Temporary files"
    log ""
    log "Note: Some resources may take a few minutes to be fully removed"
    log "from the AWS console due to eventual consistency."
    log ""
    log "If you encounter any issues or see remaining resources,"
    log "please check the AWS console and manually remove them if necessary."
}

# Main cleanup function
main() {
    log "Starting Video Content Analysis cleanup..."
    
    # Check prerequisites
    check_command "aws"
    check_command "jq"
    
    # Validate AWS setup
    validate_aws_credentials
    
    # Load resource names
    load_resource_names
    
    # Confirm destructive action
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_state_machine
    delete_lambda_functions
    delete_dynamodb_table
    delete_s3_buckets
    delete_messaging_resources
    delete_iam_resources
    delete_cloudwatch_resources
    
    # Clean up temporary files
    cleanup_temp_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display cleanup summary
    display_cleanup_summary
    
    log "Cleanup completed successfully!"
}

# Execute main function
main "$@"