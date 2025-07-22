#!/bin/bash

# Document Processing Pipeline Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log "Running in dry-run mode"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            log "Force delete mode enabled"
            shift
            ;;
        --help)
            echo "Usage: $0 [--dry-run] [--force] [--help]"
            echo "  --dry-run: Show what would be deleted without actually deleting"
            echo "  --force: Skip confirmation prompts"
            echo "  --help: Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to execute commands with dry-run support
execute() {
    local cmd="$1"
    local description="${2:-}"
    
    if [[ -n "$description" ]]; then
        log "$description"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
        return 0
    else
        eval "$cmd" 2>/dev/null || true
    fi
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case $resource_type in
        "s3-bucket")
            aws s3api head-bucket --bucket "$resource_name" 2>/dev/null
            ;;
        "dynamodb-table")
            aws dynamodb describe-table --table-name "$resource_name" 2>/dev/null >/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" 2>/dev/null >/dev/null
            ;;
        "lambda-function")
            aws lambda get-function --function-name "$resource_name" 2>/dev/null >/dev/null
            ;;
        "stepfunctions-statemachine")
            aws stepfunctions describe-state-machine --state-machine-arn "$resource_name" 2>/dev/null >/dev/null
            ;;
        "sns-topic")
            aws sns get-topic-attributes --topic-arn "$resource_name" 2>/dev/null >/dev/null
            ;;
    esac
}

# Load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        warning "Environment file not found: $ENV_FILE"
        warning "Attempting to discover resources..."
        
        # Try to discover resources
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        
        if [[ -z "$AWS_ACCOUNT_ID" ]]; then
            error "Unable to determine AWS account ID. Please ensure AWS CLI is configured."
            exit 1
        fi
        
        # Try to find existing resources
        local buckets
        buckets=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `document-processing-`) || contains(Name, `processing-results-`)].Name' --output text 2>/dev/null || echo "")
        
        if [[ -n "$buckets" ]]; then
            for bucket in $buckets; do
                if [[ "$bucket" == document-processing-* ]]; then
                    export DOCUMENT_BUCKET="$bucket"
                    BUCKET_SUFFIX="${bucket#document-processing-}"
                elif [[ "$bucket" == processing-results-* ]]; then
                    export RESULTS_BUCKET="$bucket"
                fi
            done
        fi
        
        # Try to find Step Functions state machine
        local state_machines
        state_machines=$(aws stepfunctions list-state-machines --query 'stateMachines[?contains(name, `DocumentProcessingPipeline`)].stateMachineArn' --output text 2>/dev/null || echo "")
        if [[ -n "$state_machines" ]]; then
            export STATE_MACHINE_ARN="$state_machines"
        fi
        
        # Try to find SNS topic
        local topics
        topics=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `DocumentProcessingNotifications`)].TopicArn' --output text 2>/dev/null || echo "")
        if [[ -n "$topics" ]]; then
            export NOTIFICATION_TOPIC_ARN="$topics"
        fi
        
        log "Discovery complete. Found resources may be incomplete."
    else
        # Source the environment file
        source "$ENV_FILE"
        success "Environment variables loaded from $ENV_FILE"
    fi
    
    # Validate required variables
    if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
        error "AWS_ACCOUNT_ID not set"
        exit 1
    fi
    
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION="us-east-1"
        warning "AWS_REGION not set, using default: us-east-1"
    fi
    
    log "Using AWS Account ID: $AWS_ACCOUNT_ID"
    log "Using AWS Region: $AWS_REGION"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo
    warning "This will delete the following resources:"
    echo "  - S3 Buckets: ${DOCUMENT_BUCKET:-document-processing-*}, ${RESULTS_BUCKET:-processing-results-*}"
    echo "  - DynamoDB Table: DocumentProcessingJobs"
    echo "  - Lambda Function: DocumentProcessingTrigger"
    echo "  - Step Functions State Machine: DocumentProcessingPipeline"
    echo "  - SNS Topic: ${NOTIFICATION_TOPIC_ARN:-DocumentProcessingNotifications}"
    echo "  - IAM Role: DocumentProcessingStepFunctionsRole"
    echo
    warning "This action cannot be undone!"
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Deletion cancelled."
        exit 0
    fi
}

# Delete Step Functions state machine
delete_step_functions() {
    log "Deleting Step Functions state machine..."
    
    if [[ -n "${STATE_MACHINE_ARN:-}" ]]; then
        if resource_exists "stepfunctions-statemachine" "$STATE_MACHINE_ARN"; then
            execute "aws stepfunctions delete-state-machine --state-machine-arn '$STATE_MACHINE_ARN'" \
                "Deleting state machine: $STATE_MACHINE_ARN"
            success "Step Functions state machine deleted"
        else
            warning "Step Functions state machine not found or already deleted"
        fi
    else
        # Try to find and delete by name
        local state_machines
        state_machines=$(aws stepfunctions list-state-machines --query 'stateMachines[?name==`DocumentProcessingPipeline`].stateMachineArn' --output text 2>/dev/null || echo "")
        if [[ -n "$state_machines" ]]; then
            execute "aws stepfunctions delete-state-machine --state-machine-arn '$state_machines'" \
                "Deleting state machine: DocumentProcessingPipeline"
            success "Step Functions state machine deleted"
        else
            warning "Step Functions state machine not found"
        fi
    fi
}

# Delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    if resource_exists "lambda-function" "DocumentProcessingTrigger"; then
        execute "aws lambda delete-function --function-name DocumentProcessingTrigger" \
            "Deleting Lambda function: DocumentProcessingTrigger"
        success "Lambda function deleted"
    else
        warning "Lambda function not found or already deleted"
    fi
}

# Delete S3 buckets
delete_s3_buckets() {
    log "Deleting S3 buckets..."
    
    # Delete document bucket
    if [[ -n "${DOCUMENT_BUCKET:-}" ]]; then
        if resource_exists "s3-bucket" "$DOCUMENT_BUCKET"; then
            execute "aws s3 rm s3://$DOCUMENT_BUCKET --recursive" \
                "Emptying document bucket: $DOCUMENT_BUCKET"
            execute "aws s3api delete-bucket --bucket $DOCUMENT_BUCKET" \
                "Deleting document bucket: $DOCUMENT_BUCKET"
            success "Document bucket deleted: $DOCUMENT_BUCKET"
        else
            warning "Document bucket not found: $DOCUMENT_BUCKET"
        fi
    else
        # Try to find and delete buckets by pattern
        local buckets
        buckets=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `document-processing-`)].Name' --output text 2>/dev/null || echo "")
        for bucket in $buckets; do
            if [[ -n "$bucket" ]]; then
                execute "aws s3 rm s3://$bucket --recursive" \
                    "Emptying document bucket: $bucket"
                execute "aws s3api delete-bucket --bucket $bucket" \
                    "Deleting document bucket: $bucket"
                success "Document bucket deleted: $bucket"
            fi
        done
    fi
    
    # Delete results bucket
    if [[ -n "${RESULTS_BUCKET:-}" ]]; then
        if resource_exists "s3-bucket" "$RESULTS_BUCKET"; then
            execute "aws s3 rm s3://$RESULTS_BUCKET --recursive" \
                "Emptying results bucket: $RESULTS_BUCKET"
            execute "aws s3api delete-bucket --bucket $RESULTS_BUCKET" \
                "Deleting results bucket: $RESULTS_BUCKET"
            success "Results bucket deleted: $RESULTS_BUCKET"
        else
            warning "Results bucket not found: $RESULTS_BUCKET"
        fi
    else
        # Try to find and delete buckets by pattern
        local buckets
        buckets=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `processing-results-`)].Name' --output text 2>/dev/null || echo "")
        for bucket in $buckets; do
            if [[ -n "$bucket" ]]; then
                execute "aws s3 rm s3://$bucket --recursive" \
                    "Emptying results bucket: $bucket"
                execute "aws s3api delete-bucket --bucket $bucket" \
                    "Deleting results bucket: $bucket"
                success "Results bucket deleted: $bucket"
            fi
        done
    fi
}

# Delete DynamoDB table
delete_dynamodb_table() {
    log "Deleting DynamoDB table..."
    
    if resource_exists "dynamodb-table" "DocumentProcessingJobs"; then
        execute "aws dynamodb delete-table --table-name DocumentProcessingJobs" \
            "Deleting DynamoDB table: DocumentProcessingJobs"
        
        # Wait for table deletion to complete
        if [[ "$DRY_RUN" == "false" ]]; then
            log "Waiting for DynamoDB table deletion to complete..."
            aws dynamodb wait table-not-exists --table-name DocumentProcessingJobs 2>/dev/null || true
        fi
        
        success "DynamoDB table deleted"
    else
        warning "DynamoDB table not found or already deleted"
    fi
}

# Delete SNS topic
delete_sns_topic() {
    log "Deleting SNS topic..."
    
    if [[ -n "${NOTIFICATION_TOPIC_ARN:-}" ]]; then
        if resource_exists "sns-topic" "$NOTIFICATION_TOPIC_ARN"; then
            execute "aws sns delete-topic --topic-arn '$NOTIFICATION_TOPIC_ARN'" \
                "Deleting SNS topic: $NOTIFICATION_TOPIC_ARN"
            success "SNS topic deleted"
        else
            warning "SNS topic not found or already deleted"
        fi
    else
        # Try to find and delete by name pattern
        local topics
        topics=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `DocumentProcessingNotifications`)].TopicArn' --output text 2>/dev/null || echo "")
        for topic in $topics; do
            if [[ -n "$topic" ]]; then
                execute "aws sns delete-topic --topic-arn '$topic'" \
                    "Deleting SNS topic: $topic"
                success "SNS topic deleted: $topic"
            fi
        done
    fi
}

# Delete IAM role and policies
delete_iam_role() {
    log "Deleting IAM role and policies..."
    
    if resource_exists "iam-role" "DocumentProcessingStepFunctionsRole"; then
        # Delete attached policies first
        execute "aws iam delete-role-policy \
            --role-name DocumentProcessingStepFunctionsRole \
            --policy-name DocumentProcessingPolicy" \
            "Deleting IAM policy: DocumentProcessingPolicy"
        
        # Delete the role
        execute "aws iam delete-role --role-name DocumentProcessingStepFunctionsRole" \
            "Deleting IAM role: DocumentProcessingStepFunctionsRole"
        
        success "IAM role and policies deleted"
    else
        warning "IAM role not found or already deleted"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ -f "$ENV_FILE" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "DRY-RUN: rm $ENV_FILE"
        else
            rm "$ENV_FILE"
        fi
        success "Environment file removed"
    fi
    
    # Clean up any temporary files that might have been left behind
    local temp_files=(
        "$SCRIPT_DIR/step-functions-trust-policy.json"
        "$SCRIPT_DIR/step-functions-policy.json"
        "$SCRIPT_DIR/document-processing-workflow.json"
        "$SCRIPT_DIR/document-processing-workflow-final.json"
        "$SCRIPT_DIR/lambda-trigger.py"
        "$SCRIPT_DIR/lambda-trigger.zip"
        "$SCRIPT_DIR/s3-notification.json"
        "$SCRIPT_DIR/s3-notification-final.json"
        "$SCRIPT_DIR/sample-invoice.pdf"
        "$SCRIPT_DIR/test-document.txt"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "DRY-RUN: rm $file"
            else
                rm "$file"
            fi
        fi
    done
    
    success "Local cleanup completed"
}

# Verify deletion
verify_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log "Verifying resource deletion..."
    
    local remaining_resources=()
    
    # Check S3 buckets
    if [[ -n "${DOCUMENT_BUCKET:-}" ]] && resource_exists "s3-bucket" "$DOCUMENT_BUCKET"; then
        remaining_resources+=("S3 Bucket: $DOCUMENT_BUCKET")
    fi
    
    if [[ -n "${RESULTS_BUCKET:-}" ]] && resource_exists "s3-bucket" "$RESULTS_BUCKET"; then
        remaining_resources+=("S3 Bucket: $RESULTS_BUCKET")
    fi
    
    # Check DynamoDB table
    if resource_exists "dynamodb-table" "DocumentProcessingJobs"; then
        remaining_resources+=("DynamoDB Table: DocumentProcessingJobs")
    fi
    
    # Check Lambda function
    if resource_exists "lambda-function" "DocumentProcessingTrigger"; then
        remaining_resources+=("Lambda Function: DocumentProcessingTrigger")
    fi
    
    # Check IAM role
    if resource_exists "iam-role" "DocumentProcessingStepFunctionsRole"; then
        remaining_resources+=("IAM Role: DocumentProcessingStepFunctionsRole")
    fi
    
    if [[ ${#remaining_resources[@]} -eq 0 ]]; then
        success "All resources have been successfully deleted"
    else
        warning "Some resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            warning "  - $resource"
        done
        warning "These resources may take time to delete or may need manual cleanup"
    fi
}

# Main cleanup function
main() {
    log "Starting document processing pipeline cleanup..."
    
    load_environment
    
    if [[ "$DRY_RUN" == "false" ]]; then
        confirm_deletion
    fi
    
    # Delete resources in reverse order of creation
    delete_step_functions
    delete_lambda_function
    delete_s3_buckets
    delete_dynamodb_table
    delete_sns_topic
    delete_iam_role
    cleanup_local_files
    
    verify_deletion
    
    echo
    success "Document processing pipeline cleanup completed!"
    echo
    log "All resources have been removed from your AWS account."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Note: Some resources may take a few minutes to fully delete."
        log "You may want to verify deletion in the AWS Console."
    fi
}

# Run main function
main "$@"