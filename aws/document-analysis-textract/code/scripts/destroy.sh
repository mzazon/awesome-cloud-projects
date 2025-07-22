#!/bin/bash

# Destroy script for Document Analysis with Amazon Textract
# This script safely removes all infrastructure created by the deploy script
# Recipe: Implementing Document Analysis with Amazon Textract

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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

# Check if running in AWS CloudShell or with AWS CLI configured
check_aws_config() {
    log "Checking AWS configuration..."
    
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        error "Please run 'aws configure' or ensure you're in AWS CloudShell."
        exit 1
    fi
    
    AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        error "AWS region is not configured."
        error "Please set a default region with 'aws configure set region <region>'"
        exit 1
    fi
    
    success "AWS CLI configured for region: $AWS_REGION"
}

# Function to get user confirmation
confirm_destruction() {
    echo ""
    echo "========================================="
    echo "           DANGER ZONE"
    echo "========================================="
    echo ""
    warning "This script will PERMANENTLY DELETE all resources created by the Textract deployment!"
    echo ""
    echo "Resources that will be destroyed:"
    echo "• All Lambda functions"
    echo "• Step Functions state machine"
    echo "• S3 buckets and ALL their contents"
    echo "• DynamoDB table and ALL data"
    echo "• SNS topic and subscriptions"
    echo "• IAM roles and policies"
    echo ""
    echo "This action CANNOT be undone!"
    echo ""
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        warning "FORCE_DESTROY is set - skipping confirmation"
        return 0
    fi
    
    read -p "Type 'destroy' to confirm deletion: " confirm
    if [[ "$confirm" != "destroy" ]]; then
        echo "Destruction cancelled."
        exit 0
    fi
    
    echo ""
    warning "Starting destruction in 5 seconds..."
    sleep 5
}

# Discover existing deployments
discover_deployments() {
    log "Discovering existing Textract deployments..."
    
    # Try to load from deployment config if available
    if [[ -n "${PROJECT_NAME:-}" ]]; then
        log "Using provided PROJECT_NAME: $PROJECT_NAME"
        return 0
    fi
    
    # Look for textract-analysis prefixed resources
    local buckets=$(aws s3 ls | grep -o 'textract-analysis-[a-z0-9]\{6\}' | head -1 || true)
    if [[ -n "$buckets" ]]; then
        PROJECT_NAME="$buckets"
        log "Discovered deployment: $PROJECT_NAME"
        return 0
    fi
    
    # Look for Lambda functions with textract-analysis prefix
    local functions=$(aws lambda list-functions \
        --query 'Functions[?starts_with(FunctionName, `textract-analysis-`)].FunctionName' \
        --output text | head -1 || true)
    if [[ -n "$functions" ]]; then
        PROJECT_NAME=$(echo "$functions" | cut -d'-' -f1-3)
        log "Discovered deployment from Lambda: $PROJECT_NAME"
        return 0
    fi
    
    # Interactive discovery
    echo ""
    echo "No automatic discovery possible. Available options:"
    echo "1. Provide PROJECT_NAME as environment variable"
    echo "2. Look for deployment config in S3"
    echo ""
    
    read -p "Enter the PROJECT_NAME (textract-analysis-XXXXXX): " input_project_name
    if [[ -z "$input_project_name" ]]; then
        error "PROJECT_NAME is required for destruction."
        exit 1
    fi
    
    PROJECT_NAME="$input_project_name"
    log "Using provided PROJECT_NAME: $PROJECT_NAME"
}

# Set resource names based on project name
set_resource_names() {
    log "Setting resource names for project: $PROJECT_NAME"
    
    export INPUT_BUCKET="${PROJECT_NAME}-input"
    export OUTPUT_BUCKET="${PROJECT_NAME}-output"
    export METADATA_TABLE="${PROJECT_NAME}-metadata"
    export SNS_TOPIC="${PROJECT_NAME}-notifications"
    export EXECUTION_ROLE_NAME="${PROJECT_NAME}-execution-role"
    
    log "Input bucket: $INPUT_BUCKET"
    log "Output bucket: $OUTPUT_BUCKET"
    log "DynamoDB table: $METADATA_TABLE"
    log "SNS topic: $SNS_TOPIC"
    log "IAM role: $EXECUTION_ROLE_NAME"
}

# Stop any running Textract jobs
stop_textract_jobs() {
    log "Checking for running Textract jobs..."
    
    # Note: This is a safety measure to prevent orphaned jobs
    # In practice, jobs should complete or fail naturally
    warning "If you have running Textract jobs, they may continue to incur charges."
    warning "Monitor the AWS Console to ensure all jobs complete."
}

# Remove Lambda functions
remove_lambda_functions() {
    log "Removing Lambda functions..."
    
    local functions=(
        "${PROJECT_NAME}-document-classifier"
        "${PROJECT_NAME}-textract-processor"
        "${PROJECT_NAME}-async-results-processor"
        "${PROJECT_NAME}-document-query"
    )
    
    for function_name in "${functions[@]}"; do
        if aws lambda get-function --function-name "$function_name" &> /dev/null; then
            log "Deleting Lambda function: $function_name"
            
            # Remove any event source mappings
            local mappings=$(aws lambda list-event-source-mappings \
                --function-name "$function_name" \
                --query 'EventSourceMappings[].UUID' \
                --output text 2>/dev/null || true)
            
            for mapping_uuid in $mappings; do
                if [[ -n "$mapping_uuid" && "$mapping_uuid" != "None" ]]; then
                    aws lambda delete-event-source-mapping --uuid "$mapping_uuid" || true
                fi
            done
            
            # Delete the function
            aws lambda delete-function --function-name "$function_name"
            success "Deleted Lambda function: $function_name"
        else
            warning "Lambda function not found: $function_name"
        fi
    done
}

# Remove Step Functions state machine
remove_step_functions() {
    log "Removing Step Functions state machine..."
    
    local state_machine_name="${PROJECT_NAME}-workflow"
    
    # Get state machine ARN
    local state_machine_arn=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?name=='$state_machine_name'].stateMachineArn" \
        --output text 2>/dev/null || true)
    
    if [[ -n "$state_machine_arn" && "$state_machine_arn" != "None" ]]; then
        log "Stopping any running executions..."
        
        # Stop running executions
        local running_executions=$(aws stepfunctions list-executions \
            --state-machine-arn "$state_machine_arn" \
            --status-filter RUNNING \
            --query 'executions[].executionArn' \
            --output text 2>/dev/null || true)
        
        for execution_arn in $running_executions; do
            if [[ -n "$execution_arn" && "$execution_arn" != "None" ]]; then
                aws stepfunctions stop-execution --execution-arn "$execution_arn" || true
                log "Stopped execution: $execution_arn"
            fi
        done
        
        # Wait a moment for executions to stop
        sleep 5
        
        # Delete state machine
        aws stepfunctions delete-state-machine --state-machine-arn "$state_machine_arn"
        success "Deleted Step Functions state machine: $state_machine_name"
    else
        warning "Step Functions state machine not found: $state_machine_name"
    fi
}

# Remove S3 buckets and contents
remove_s3_buckets() {
    log "Removing S3 buckets and contents..."
    
    local buckets=("$INPUT_BUCKET" "$OUTPUT_BUCKET")
    
    for bucket in "${buckets[@]}"; do
        if aws s3 ls "s3://$bucket" &> /dev/null; then
            log "Emptying S3 bucket: $bucket"
            
            # Delete all object versions (including delete markers)
            aws s3api list-object-versions \
                --bucket "$bucket" \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                --output json | \
                jq '.Objects // []' | \
                aws s3api delete-objects \
                    --bucket "$bucket" \
                    --delete file:///dev/stdin 2>/dev/null || true
            
            # Delete delete markers
            aws s3api list-object-versions \
                --bucket "$bucket" \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                --output json | \
                jq '.Objects // []' | \
                aws s3api delete-objects \
                    --bucket "$bucket" \
                    --delete file:///dev/stdin 2>/dev/null || true
            
            # Remove bucket notification configuration
            aws s3api put-bucket-notification-configuration \
                --bucket "$bucket" \
                --notification-configuration '{}' 2>/dev/null || true
            
            # Delete the bucket
            aws s3 rb "s3://$bucket" --force
            success "Deleted S3 bucket: $bucket"
        else
            warning "S3 bucket not found: $bucket"
        fi
    done
}

# Remove DynamoDB table
remove_dynamodb_table() {
    log "Removing DynamoDB table..."
    
    if aws dynamodb describe-table --table-name "$METADATA_TABLE" &> /dev/null; then
        log "Deleting DynamoDB table: $METADATA_TABLE"
        
        aws dynamodb delete-table --table-name "$METADATA_TABLE"
        
        log "Waiting for table deletion to complete..."
        aws dynamodb wait table-not-exists --table-name "$METADATA_TABLE"
        
        success "Deleted DynamoDB table: $METADATA_TABLE"
    else
        warning "DynamoDB table not found: $METADATA_TABLE"
    fi
}

# Remove SNS topic and subscriptions
remove_sns_resources() {
    log "Removing SNS resources..."
    
    # Find SNS topic ARN
    local topic_arn=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, '$SNS_TOPIC')].TopicArn" \
        --output text 2>/dev/null || true)
    
    if [[ -n "$topic_arn" && "$topic_arn" != "None" ]]; then
        log "Removing SNS subscriptions for topic: $SNS_TOPIC"
        
        # List and delete subscriptions
        local subscriptions=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$topic_arn" \
            --query 'Subscriptions[].SubscriptionArn' \
            --output text 2>/dev/null || true)
        
        for subscription_arn in $subscriptions; do
            if [[ -n "$subscription_arn" && "$subscription_arn" != "None" && "$subscription_arn" != "PendingConfirmation" ]]; then
                aws sns unsubscribe --subscription-arn "$subscription_arn" || true
                log "Deleted subscription: $subscription_arn"
            fi
        done
        
        # Delete the topic
        aws sns delete-topic --topic-arn "$topic_arn"
        success "Deleted SNS topic: $SNS_TOPIC"
    else
        warning "SNS topic not found: $SNS_TOPIC"
    fi
}

# Remove IAM role and policies
remove_iam_resources() {
    log "Removing IAM resources..."
    
    if aws iam get-role --role-name "$EXECUTION_ROLE_NAME" &> /dev/null; then
        log "Removing policies from IAM role: $EXECUTION_ROLE_NAME"
        
        # List and detach managed policies
        local attached_policies=$(aws iam list-attached-role-policies \
            --role-name "$EXECUTION_ROLE_NAME" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || true)
        
        for policy_arn in $attached_policies; do
            if [[ -n "$policy_arn" && "$policy_arn" != "None" ]]; then
                aws iam detach-role-policy \
                    --role-name "$EXECUTION_ROLE_NAME" \
                    --policy-arn "$policy_arn"
                log "Detached policy: $policy_arn"
            fi
        done
        
        # List and delete inline policies
        local inline_policies=$(aws iam list-role-policies \
            --role-name "$EXECUTION_ROLE_NAME" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || true)
        
        for policy_name in $inline_policies; do
            if [[ -n "$policy_name" && "$policy_name" != "None" ]]; then
                aws iam delete-role-policy \
                    --role-name "$EXECUTION_ROLE_NAME" \
                    --policy-name "$policy_name"
                log "Deleted inline policy: $policy_name"
            fi
        done
        
        # Wait for policies to detach
        sleep 5
        
        # Delete the role
        aws iam delete-role --role-name "$EXECUTION_ROLE_NAME"
        success "Deleted IAM role: $EXECUTION_ROLE_NAME"
    else
        warning "IAM role not found: $EXECUTION_ROLE_NAME"
    fi
}

# Remove Lambda permissions
remove_lambda_permissions() {
    log "Cleaning up Lambda permissions..."
    
    # This is handled during Lambda function deletion
    # But we can attempt to clean up any orphaned permissions
    
    local functions=(
        "${PROJECT_NAME}-document-classifier"
        "${PROJECT_NAME}-async-results-processor"
    )
    
    for function_name in "${functions[@]}"; do
        # Try to remove S3 and SNS permissions (will fail if function doesn't exist, which is OK)
        aws lambda remove-permission \
            --function-name "$function_name" \
            --statement-id "s3-trigger-permission" 2>/dev/null || true
        aws lambda remove-permission \
            --function-name "$function_name" \
            --statement-id "sns-trigger-permission" 2>/dev/null || true
    done
}

# Clean up local temporary files
cleanup_local_files() {
    log "Cleaning up local temporary files..."
    
    # Remove any temporary files that might have been created
    rm -f /tmp/textract-*.json
    rm -f /tmp/s3-notification.json
    rm -rf /tmp/lambda-packages
    rm -rf /tmp/sample-documents
    
    success "Local cleanup completed"
}

# Verify destruction completion
verify_destruction() {
    log "Verifying destruction completion..."
    
    local resources_remaining=0
    
    # Check Lambda functions
    for function_name in "${PROJECT_NAME}-document-classifier" "${PROJECT_NAME}-textract-processor" "${PROJECT_NAME}-async-results-processor" "${PROJECT_NAME}-document-query"; do
        if aws lambda get-function --function-name "$function_name" &> /dev/null; then
            warning "Lambda function still exists: $function_name"
            ((resources_remaining++))
        fi
    done
    
    # Check S3 buckets
    for bucket in "$INPUT_BUCKET" "$OUTPUT_BUCKET"; do
        if aws s3 ls "s3://$bucket" &> /dev/null; then
            warning "S3 bucket still exists: $bucket"
            ((resources_remaining++))
        fi
    done
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "$METADATA_TABLE" &> /dev/null; then
        warning "DynamoDB table still exists: $METADATA_TABLE"
        ((resources_remaining++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$EXECUTION_ROLE_NAME" &> /dev/null; then
        warning "IAM role still exists: $EXECUTION_ROLE_NAME"
        ((resources_remaining++))
    fi
    
    if [[ $resources_remaining -eq 0 ]]; then
        success "All resources have been successfully destroyed"
    else
        warning "$resources_remaining resources may still exist. Please check the AWS console."
    fi
}

# Display destruction summary
display_summary() {
    echo ""
    echo "========================================="
    echo "   DESTRUCTION COMPLETED"
    echo "========================================="
    echo ""
    echo "Project: $PROJECT_NAME"
    echo "Region: $AWS_REGION"
    echo ""
    echo "Resources Destroyed:"
    echo "• Lambda Functions: 4 functions"
    echo "• Step Functions state machine"
    echo "• S3 Buckets: $INPUT_BUCKET, $OUTPUT_BUCKET"
    echo "• DynamoDB Table: $METADATA_TABLE"
    echo "• SNS Topic: $SNS_TOPIC"
    echo "• IAM Role: $EXECUTION_ROLE_NAME"
    echo ""
    warning "Please verify in the AWS Console that no unexpected charges are occurring."
    warning "Check for any orphaned resources that may have been missed."
    echo ""
    success "Textract document analysis infrastructure has been destroyed."
    echo "========================================="
}

# Main execution
main() {
    echo "======================================"
    echo "  Document Analysis Textract Destroy"
    echo "======================================"
    echo ""
    
    check_aws_config
    confirm_destruction
    discover_deployments
    set_resource_names
    
    echo ""
    log "Beginning destruction of: $PROJECT_NAME"
    echo ""
    
    stop_textract_jobs
    remove_lambda_permissions
    remove_lambda_functions
    remove_step_functions
    remove_s3_buckets
    remove_dynamodb_table
    remove_sns_resources
    remove_iam_resources
    cleanup_local_files
    verify_destruction
    display_summary
}

# Error handling
trap 'error "Destruction encountered an error. Some resources may still exist."; exit 1' ERR

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --force)
            FORCE_DESTROY="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [--project-name PROJECT_NAME] [--force] [--help]"
            echo ""
            echo "Options:"
            echo "  --project-name   Specify the project name to destroy"
            echo "  --force          Skip confirmation prompt"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"