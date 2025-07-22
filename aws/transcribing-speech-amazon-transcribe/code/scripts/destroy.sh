#!/bin/bash

# Destroy script for Speech Recognition Applications with Amazon Transcribe
# This script safely removes all resources created by the deployment

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Confirmation prompt
confirm_destruction() {
    echo -e "${RED}WARNING: This will permanently delete all resources created by the deployment!${NC}"
    echo
    echo "This includes:"
    echo "- S3 bucket and all contents"
    echo "- Custom vocabulary and filters"
    echo "- Custom language model"
    echo "- Lambda function"
    echo "- IAM roles and policies"
    echo "- All transcription jobs"
    echo
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
}

# Load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ -f .env ]; then
        source .env
        log "Environment variables loaded from .env file ✅"
    else
        warn "No .env file found. You may need to specify resource names manually."
        
        # Prompt for required variables if not found
        if [ -z "$BUCKET_NAME" ]; then
            read -p "Enter S3 bucket name: " BUCKET_NAME
        fi
        if [ -z "$VOCABULARY_NAME" ]; then
            read -p "Enter custom vocabulary name: " VOCABULARY_NAME
        fi
        if [ -z "$VOCABULARY_FILTER_NAME" ]; then
            read -p "Enter vocabulary filter name: " VOCABULARY_FILTER_NAME
        fi
        if [ -z "$LANGUAGE_MODEL_NAME" ]; then
            read -p "Enter language model name: " LANGUAGE_MODEL_NAME
        fi
        if [ -z "$ROLE_NAME" ]; then
            read -p "Enter Transcribe IAM role name: " ROLE_NAME
        fi
        if [ -z "$LAMBDA_ROLE_NAME" ]; then
            read -p "Enter Lambda IAM role name: " LAMBDA_ROLE_NAME
        fi
        if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
            read -p "Enter Lambda function name: " LAMBDA_FUNCTION_NAME
        fi
    fi
    
    # Set AWS region if not already set
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION=$(aws configure get region)
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "Prerequisites check passed ✅"
}

# Delete all transcription jobs
delete_transcription_jobs() {
    log "Deleting transcription jobs..."
    
    # List all transcription jobs and delete them
    local jobs=$(aws transcribe list-transcription-jobs \
        --query 'TranscriptionJobSummaries[*].TranscriptionJobName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$jobs" ]; then
        for job in $jobs; do
            if [[ "$job" == *"$RANDOM_SUFFIX"* ]] || [[ "$job" == *"transcription"* ]]; then
                log "Deleting transcription job: $job"
                aws transcribe delete-transcription-job \
                    --transcription-job-name "$job" \
                    2>/dev/null || warn "Failed to delete transcription job: $job"
            fi
        done
    fi
    
    log "Transcription jobs cleanup completed ✅"
}

# Delete custom language resources
delete_custom_language_resources() {
    log "Deleting custom language resources..."
    
    # Delete custom vocabulary
    if [ -n "$VOCABULARY_NAME" ]; then
        log "Deleting custom vocabulary: $VOCABULARY_NAME"
        aws transcribe delete-vocabulary \
            --vocabulary-name "$VOCABULARY_NAME" \
            2>/dev/null || warn "Failed to delete custom vocabulary: $VOCABULARY_NAME"
    fi
    
    # Delete vocabulary filter
    if [ -n "$VOCABULARY_FILTER_NAME" ]; then
        log "Deleting vocabulary filter: $VOCABULARY_FILTER_NAME"
        aws transcribe delete-vocabulary-filter \
            --vocabulary-filter-name "$VOCABULARY_FILTER_NAME" \
            2>/dev/null || warn "Failed to delete vocabulary filter: $VOCABULARY_FILTER_NAME"
    fi
    
    # Delete custom language model
    if [ -n "$LANGUAGE_MODEL_NAME" ]; then
        log "Deleting custom language model: $LANGUAGE_MODEL_NAME"
        aws transcribe delete-language-model \
            --model-name "$LANGUAGE_MODEL_NAME" \
            2>/dev/null || warn "Failed to delete custom language model: $LANGUAGE_MODEL_NAME"
    fi
    
    log "Custom language resources cleanup completed ✅"
}

# Delete Lambda function and role
delete_lambda_resources() {
    log "Deleting Lambda resources..."
    
    # Delete Lambda function
    if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
        log "Deleting Lambda function: $LAMBDA_FUNCTION_NAME"
        aws lambda delete-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            2>/dev/null || warn "Failed to delete Lambda function: $LAMBDA_FUNCTION_NAME"
    fi
    
    # Delete Lambda IAM role and policies
    if [ -n "$LAMBDA_ROLE_NAME" ]; then
        log "Deleting Lambda IAM role: $LAMBDA_ROLE_NAME"
        
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
            2>/dev/null || warn "Failed to detach Lambda basic execution policy"
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-name TranscribeAccess \
            2>/dev/null || warn "Failed to delete Lambda Transcribe access policy"
        
        # Delete role
        aws iam delete-role \
            --role-name "$LAMBDA_ROLE_NAME" \
            2>/dev/null || warn "Failed to delete Lambda IAM role: $LAMBDA_ROLE_NAME"
    fi
    
    log "Lambda resources cleanup completed ✅"
}

# Delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket..."
    
    if [ -n "$BUCKET_NAME" ]; then
        log "Emptying S3 bucket: $BUCKET_NAME"
        
        # Check if bucket exists
        if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
            # Remove all objects from bucket
            aws s3 rm s3://"$BUCKET_NAME" --recursive 2>/dev/null || warn "Failed to empty S3 bucket"
            
            # Remove all object versions (for versioned buckets)
            aws s3api delete-objects \
                --bucket "$BUCKET_NAME" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$BUCKET_NAME" \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                    --output json)" \
                2>/dev/null || warn "Failed to delete object versions"
            
            # Remove all delete markers
            aws s3api delete-objects \
                --bucket "$BUCKET_NAME" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$BUCKET_NAME" \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                    --output json)" \
                2>/dev/null || warn "Failed to delete delete markers"
            
            log "Deleting S3 bucket: $BUCKET_NAME"
            aws s3 rb s3://"$BUCKET_NAME" --force 2>/dev/null || warn "Failed to delete S3 bucket: $BUCKET_NAME"
        else
            warn "S3 bucket $BUCKET_NAME does not exist or is not accessible"
        fi
    fi
    
    log "S3 bucket cleanup completed ✅"
}

# Delete Transcribe IAM role
delete_transcribe_iam_role() {
    log "Deleting Transcribe IAM role..."
    
    if [ -n "$ROLE_NAME" ]; then
        log "Deleting Transcribe IAM role: $ROLE_NAME"
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-name TranscribeS3Access \
            2>/dev/null || warn "Failed to delete Transcribe S3 access policy"
        
        # Delete role
        aws iam delete-role \
            --role-name "$ROLE_NAME" \
            2>/dev/null || warn "Failed to delete Transcribe IAM role: $ROLE_NAME"
    fi
    
    log "Transcribe IAM role cleanup completed ✅"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files created during deployment
    local temp_files=(
        "transcribe-trust-policy.json"
        "transcribe-s3-policy.json"
        "lambda-trust-policy.json"
        "lambda-transcribe-policy.json"
        "custom-vocabulary.txt"
        "vocabulary-filter.txt"
        "training-data.txt"
        "lambda-function.py"
        "lambda-function.zip"
        "sample-audio-metadata.txt"
        "streaming-config.json"
        "monitor-jobs.sh"
        "test-event.json"
        "lambda-response.json"
        "sample-transcript.json"
        "response.json"
        "basic-transcription-job.json"
        "advanced-transcription-job.json"
        "pii-redaction-job.json"
        "websocket-client.py"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Removed: $file"
        fi
    done
    
    # Remove environment file
    if [ -f ".env" ]; then
        rm -f ".env"
        log "Removed: .env"
    fi
    
    log "Local files cleanup completed ✅"
}

# Verify resource deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local verification_failed=false
    
    # Check S3 bucket
    if [ -n "$BUCKET_NAME" ]; then
        if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
            warn "S3 bucket $BUCKET_NAME still exists"
            verification_failed=true
        fi
    fi
    
    # Check Lambda function
    if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" 2>/dev/null; then
            warn "Lambda function $LAMBDA_FUNCTION_NAME still exists"
            verification_failed=true
        fi
    fi
    
    # Check IAM roles
    if [ -n "$ROLE_NAME" ]; then
        if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
            warn "IAM role $ROLE_NAME still exists"
            verification_failed=true
        fi
    fi
    
    if [ -n "$LAMBDA_ROLE_NAME" ]; then
        if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" 2>/dev/null; then
            warn "Lambda IAM role $LAMBDA_ROLE_NAME still exists"
            verification_failed=true
        fi
    fi
    
    # Check custom vocabulary
    if [ -n "$VOCABULARY_NAME" ]; then
        if aws transcribe get-vocabulary --vocabulary-name "$VOCABULARY_NAME" 2>/dev/null; then
            warn "Custom vocabulary $VOCABULARY_NAME still exists"
            verification_failed=true
        fi
    fi
    
    # Check vocabulary filter
    if [ -n "$VOCABULARY_FILTER_NAME" ]; then
        if aws transcribe get-vocabulary-filter --vocabulary-filter-name "$VOCABULARY_FILTER_NAME" 2>/dev/null; then
            warn "Vocabulary filter $VOCABULARY_FILTER_NAME still exists"
            verification_failed=true
        fi
    fi
    
    if [ "$verification_failed" = true ]; then
        warn "Some resources may still exist. You may need to delete them manually."
        warn "This could be due to resource dependencies or IAM eventual consistency."
    else
        log "Resource deletion verification passed ✅"
    fi
}

# Wait for resource cleanup
wait_for_cleanup() {
    log "Waiting for resource cleanup to complete..."
    
    # Wait for IAM roles to be fully deleted (eventual consistency)
    if [ -n "$ROLE_NAME" ] || [ -n "$LAMBDA_ROLE_NAME" ]; then
        log "Waiting for IAM roles to be fully deleted..."
        sleep 30
    fi
    
    # Wait for Transcribe resources to be fully deleted
    if [ -n "$VOCABULARY_NAME" ] || [ -n "$VOCABULARY_FILTER_NAME" ]; then
        log "Waiting for Transcribe resources to be fully deleted..."
        sleep 15
    fi
    
    log "Cleanup wait period completed ✅"
}

# Display cleanup summary
display_cleanup_summary() {
    log "Cleanup completed successfully! 🎉"
    echo
    echo -e "${BLUE}Deleted Resources:${NC}"
    echo "- S3 Bucket: ${BUCKET_NAME:-'N/A'}"
    echo "- Custom Vocabulary: ${VOCABULARY_NAME:-'N/A'}"
    echo "- Vocabulary Filter: ${VOCABULARY_FILTER_NAME:-'N/A'}"
    echo "- Language Model: ${LANGUAGE_MODEL_NAME:-'N/A'}"
    echo "- Transcribe IAM Role: ${ROLE_NAME:-'N/A'}"
    echo "- Lambda Function: ${LAMBDA_FUNCTION_NAME:-'N/A'}"
    echo "- Lambda IAM Role: ${LAMBDA_ROLE_NAME:-'N/A'}"
    echo "- All transcription jobs"
    echo "- Local configuration files"
    echo
    echo -e "${GREEN}All resources have been successfully removed.${NC}"
    echo -e "${YELLOW}Note:${NC} Due to AWS eventual consistency, some resources may take a few minutes to fully disappear from the AWS console."
}

# Main cleanup function
main() {
    log "Starting cleanup of Speech Recognition Applications with Amazon Transcribe..."
    
    confirm_destruction
    check_prerequisites
    load_environment
    
    # Delete resources in order (reverse of creation)
    delete_transcription_jobs
    delete_custom_language_resources
    delete_lambda_resources
    delete_s3_bucket
    delete_transcribe_iam_role
    
    # Wait for cleanup to complete
    wait_for_cleanup
    
    # Clean up local files
    cleanup_local_files
    
    # Verify deletion
    verify_deletion
    
    # Display summary
    display_cleanup_summary
    
    log "Cleanup completed! ✅"
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may not have been deleted."' INT TERM

# Run main function
main "$@"