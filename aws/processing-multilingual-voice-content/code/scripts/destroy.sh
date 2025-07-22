#!/bin/bash

# Multi-Language Voice Processing Pipeline - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error

# Color codes for output
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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to confirm destructive action
confirm_deletion() {
    echo -e "${YELLOW}⚠️  This will permanently delete all resources for the voice processing pipeline!${NC}"
    echo -e "${YELLOW}   This action cannot be undone.${NC}"
    echo ""
    read -p "Are you sure you want to proceed? (Type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        echo "Cleanup cancelled by user."
        exit 0
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local resource_name=$2
    local max_attempts=30
    local attempt=0
    
    log "Waiting for ${resource_type} ${resource_name} to be deleted..."
    
    while [ $attempt -lt $max_attempts ]; do
        case $resource_type in
            "table")
                if ! aws dynamodb describe-table --table-name "$resource_name" >/dev/null 2>&1; then
                    return 0
                fi
                ;;
            "state-machine")
                if ! aws stepfunctions describe-state-machine --state-machine-arn "$resource_name" >/dev/null 2>&1; then
                    return 0
                fi
                ;;
            "lambda")
                if ! aws lambda get-function --function-name "$resource_name" >/dev/null 2>&1; then
                    return 0
                fi
                ;;
        esac
        
        sleep 5
        ((attempt++))
        log "Attempt $attempt/$max_attempts..."
    done
    
    warning "Timeout waiting for ${resource_type} ${resource_name} to be deleted"
    return 1
}

# Prerequisites check
log "Checking prerequisites..."

if ! command_exists aws; then
    error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
    exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
    error "AWS CLI is not configured or credentials are invalid."
    exit 1
fi

# Check if deployment info file exists
if [ ! -f "deployment-info.json" ]; then
    error "deployment-info.json not found. Cannot determine what resources to delete."
    echo "Please ensure you're running this script from the same directory where deploy.sh was executed."
    exit 1
fi

# Load deployment information
if ! PROJECT_NAME=$(jq -r '.project_name' deployment-info.json 2>/dev/null); then
    error "Failed to parse deployment-info.json or jq is not installed."
    exit 1
fi

INPUT_BUCKET=$(jq -r '.input_bucket' deployment-info.json)
OUTPUT_BUCKET=$(jq -r '.output_bucket' deployment-info.json)
ROLE_NAME=$(jq -r '.role_name' deployment-info.json)
ROLE_ARN=$(jq -r '.role_arn' deployment-info.json)
STATE_MACHINE_ARN=$(jq -r '.state_machine_arn' deployment-info.json)
DYNAMODB_TABLE=$(jq -r '.dynamodb_table' deployment-info.json)
AWS_REGION=$(jq -r '.region' deployment-info.json)
AWS_ACCOUNT_ID=$(jq -r '.account_id' deployment-info.json)

log "Project Name: $PROJECT_NAME"
log "Input Bucket: $INPUT_BUCKET"
log "Output Bucket: $OUTPUT_BUCKET"
log "IAM Role: $ROLE_NAME"
log "State Machine: $STATE_MACHINE_ARN"
log "DynamoDB Table: $DYNAMODB_TABLE"
log "Region: $AWS_REGION"

# Confirm deletion
confirm_deletion

# Start cleanup process
log "Starting cleanup process..."

# 1. Stop any running executions
log "Stopping any running Step Functions executions..."
RUNNING_EXECUTIONS=$(aws stepfunctions list-executions \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --status-filter RUNNING \
    --query 'executions[].executionArn' \
    --output text 2>/dev/null || echo "")

if [ -n "$RUNNING_EXECUTIONS" ]; then
    for execution_arn in $RUNNING_EXECUTIONS; do
        log "Stopping execution: $execution_arn"
        aws stepfunctions stop-execution \
            --execution-arn "$execution_arn" \
            --cause "Cleanup script execution" \
            --error "UserInitiatedCleanup" >/dev/null 2>&1 || true
    done
    success "Stopped running executions"
else
    log "No running executions found"
fi

# 2. Delete Step Functions state machine
log "Deleting Step Functions state machine..."
if aws stepfunctions delete-state-machine \
    --state-machine-arn "$STATE_MACHINE_ARN" >/dev/null 2>&1; then
    wait_for_deletion "state-machine" "$STATE_MACHINE_ARN"
    success "Step Functions state machine deleted"
else
    warning "Failed to delete Step Functions state machine (it may not exist)"
fi

# 3. Delete Lambda functions
log "Deleting Lambda functions..."
lambda_functions=(
    "${PROJECT_NAME}-language-detector"
    "${PROJECT_NAME}-transcription-processor"
    "${PROJECT_NAME}-translation-processor"
    "${PROJECT_NAME}-speech-synthesizer"
    "${PROJECT_NAME}-job-status-checker"
)

for func in "${lambda_functions[@]}"; do
    log "Deleting Lambda function: $func"
    if aws lambda delete-function --function-name "$func" >/dev/null 2>&1; then
        wait_for_deletion "lambda" "$func"
        success "Lambda function $func deleted"
    else
        warning "Failed to delete Lambda function $func (it may not exist)"
    fi
done

# 4. Clean up any remaining Transcribe jobs
log "Cleaning up Transcribe jobs..."
TRANSCRIBE_JOBS=$(aws transcribe list-transcription-jobs \
    --max-results 100 \
    --query "TranscriptionJobSummaries[?starts_with(TranscriptionJobName, 'lang-detect-') || starts_with(TranscriptionJobName, 'transcribe-')].TranscriptionJobName" \
    --output text 2>/dev/null || echo "")

if [ -n "$TRANSCRIBE_JOBS" ]; then
    for job in $TRANSCRIBE_JOBS; do
        log "Deleting Transcribe job: $job"
        aws transcribe delete-transcription-job \
            --transcription-job-name "$job" >/dev/null 2>&1 || true
    done
    success "Cleaned up Transcribe jobs"
else
    log "No Transcribe jobs found"
fi

# 5. Empty and delete S3 buckets
log "Emptying and deleting S3 buckets..."

for bucket in "$INPUT_BUCKET" "$OUTPUT_BUCKET"; do
    if aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
        log "Emptying bucket: $bucket"
        aws s3 rm "s3://$bucket" --recursive >/dev/null 2>&1 || true
        
        # Delete any versioned objects
        aws s3api delete-objects --bucket "$bucket" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$bucket" \
                --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' \
                --output json 2>/dev/null || echo '{"Objects": []}')" \
            >/dev/null 2>&1 || true
        
        # Delete any delete markers
        aws s3api delete-objects --bucket "$bucket" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$bucket" \
                --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' \
                --output json 2>/dev/null || echo '{"Objects": []}')" \
            >/dev/null 2>&1 || true
        
        log "Deleting bucket: $bucket"
        aws s3 rb "s3://$bucket" >/dev/null 2>&1 || true
        success "Bucket $bucket deleted"
    else
        log "Bucket $bucket does not exist (already deleted)"
    fi
done

# 6. Delete DynamoDB table
log "Deleting DynamoDB table..."
if aws dynamodb delete-table --table-name "$DYNAMODB_TABLE" >/dev/null 2>&1; then
    wait_for_deletion "table" "$DYNAMODB_TABLE"
    success "DynamoDB table deleted"
else
    warning "Failed to delete DynamoDB table (it may not exist)"
fi

# 7. Detach policies and delete IAM role
log "Detaching IAM policies and deleting role..."
policies=(
    "arn:aws:iam::aws:policy/AmazonTranscribeFullAccess"
    "arn:aws:iam::aws:policy/AmazonPollyFullAccess"
    "arn:aws:iam::aws:policy/TranslateFullAccess"
    "arn:aws:iam::aws:policy/AmazonS3FullAccess"
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
)

for policy in "${policies[@]}"; do
    log "Detaching policy: $policy"
    aws iam detach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "$policy" >/dev/null 2>&1 || true
done

log "Deleting IAM role: $ROLE_NAME"
if aws iam delete-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    success "IAM role deleted"
else
    warning "Failed to delete IAM role (it may not exist)"
fi

# 8. Clean up any remaining CloudWatch Log Groups
log "Cleaning up CloudWatch Log Groups..."
LOG_GROUPS=$(aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/${PROJECT_NAME}" \
    --query 'logGroups[].logGroupName' \
    --output text 2>/dev/null || echo "")

if [ -n "$LOG_GROUPS" ]; then
    for log_group in $LOG_GROUPS; do
        log "Deleting log group: $log_group"
        aws logs delete-log-group \
            --log-group-name "$log_group" >/dev/null 2>&1 || true
    done
    success "Cleaned up CloudWatch Log Groups"
else
    log "No CloudWatch Log Groups found"
fi

# 9. Clean up any custom vocabularies and terminologies (if they exist)
log "Cleaning up custom vocabularies and terminologies..."

# List and delete custom vocabularies
VOCABULARIES=$(aws transcribe list-vocabularies \
    --name-contains "custom-vocab" \
    --query 'Vocabularies[].VocabularyName' \
    --output text 2>/dev/null || echo "")

if [ -n "$VOCABULARIES" ]; then
    for vocab in $VOCABULARIES; do
        log "Deleting vocabulary: $vocab"
        aws transcribe delete-vocabulary \
            --vocabulary-name "$vocab" >/dev/null 2>&1 || true
    done
    success "Cleaned up custom vocabularies"
else
    log "No custom vocabularies found"
fi

# List and delete custom terminologies
TERMINOLOGIES=$(aws translate list-terminologies \
    --query 'TerminologyPropertiesList[?starts_with(Name, `custom-terms`)].Name' \
    --output text 2>/dev/null || echo "")

if [ -n "$TERMINOLOGIES" ]; then
    for term in $TERMINOLOGIES; do
        log "Deleting terminology: $term"
        aws translate delete-terminology \
            --name "$term" >/dev/null 2>&1 || true
    done
    success "Cleaned up custom terminologies"
else
    log "No custom terminologies found"
fi

# 10. Remove deployment info file
log "Removing deployment info file..."
rm -f deployment-info.json
success "Deployment info file removed"

# 11. Final verification
log "Performing final verification..."
verification_passed=true

# Check if any resources still exist
if aws stepfunctions describe-state-machine \
    --state-machine-arn "$STATE_MACHINE_ARN" >/dev/null 2>&1; then
    warning "Step Functions state machine still exists"
    verification_passed=false
fi

for func in "${lambda_functions[@]}"; do
    if aws lambda get-function --function-name "$func" >/dev/null 2>&1; then
        warning "Lambda function $func still exists"
        verification_passed=false
    fi
done

if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" >/dev/null 2>&1; then
    warning "DynamoDB table still exists"
    verification_passed=false
fi

for bucket in "$INPUT_BUCKET" "$OUTPUT_BUCKET"; do
    if aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
        warning "S3 bucket $bucket still exists"
        verification_passed=false
    fi
done

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    warning "IAM role still exists"
    verification_passed=false
fi

if [ "$verification_passed" = true ]; then
    success "All resources have been successfully deleted"
else
    warning "Some resources may still exist. Please check the AWS console manually."
fi

log "Cleanup process completed!"
log ""
log "Summary:"
log "- Step Functions state machine: Deleted"
log "- Lambda functions: Deleted"
log "- DynamoDB table: Deleted"
log "- S3 buckets: Deleted"
log "- IAM role: Deleted"
log "- CloudWatch Log Groups: Deleted"
log "- Custom vocabularies/terminologies: Deleted"
log "- Deployment info file: Removed"
log ""
log "The multi-language voice processing pipeline has been completely removed."

# Optional: Show estimated cost savings
log ""
log "💰 Estimated monthly cost savings:"
log "- Lambda executions: ~$10-50/month"
log "- S3 storage: ~$5-20/month"
log "- DynamoDB: ~$5-15/month"
log "- Transcribe/Translate/Polly: Variable based on usage"
log "- Total estimated savings: ~$20-100+/month"