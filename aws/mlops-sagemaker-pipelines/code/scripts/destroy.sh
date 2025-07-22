#!/bin/bash

# Destroy script for End-to-End MLOps with SageMaker Pipelines
# This script safely removes all resources created by the deploy script
# including SageMaker pipelines, S3 buckets, IAM roles, and CodeCommit repositories

set -e  # Exit on any error

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

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [ -f ".env" ]; then
        source .env
        log_success "Environment variables loaded from .env file"
    else
        log_warning ".env file not found. Please provide resource names manually."
        
        # Prompt for resource names if .env doesn't exist
        read -p "Enter S3 bucket name (sagemaker-mlops-*): " BUCKET_NAME
        read -p "Enter pipeline name (mlops-pipeline-*): " PIPELINE_NAME
        read -p "Enter IAM role name (SageMakerExecutionRole-*): " ROLE_NAME
        read -p "Enter CodeCommit repository name (mlops-*): " CODECOMMIT_REPO
        read -p "Enter AWS region: " AWS_REGION
        
        export BUCKET_NAME PIPELINE_NAME ROLE_NAME CODECOMMIT_REPO AWS_REGION
    fi
    
    # Verify required variables are set
    if [ -z "$BUCKET_NAME" ] || [ -z "$PIPELINE_NAME" ] || [ -z "$ROLE_NAME" ] || [ -z "$CODECOMMIT_REPO" ]; then
        log_error "Required environment variables are missing. Cannot proceed with cleanup."
        exit 1
    fi
    
    log_info "Target resources for cleanup:"
    log_info "  S3 Bucket: ${BUCKET_NAME}"
    log_info "  Pipeline: ${PIPELINE_NAME}"
    log_info "  IAM Role: ${ROLE_NAME}"
    log_info "  CodeCommit Repo: ${CODECOMMIT_REPO}"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "  • SageMaker Pipeline: ${PIPELINE_NAME}"
    echo "  • S3 Bucket: ${BUCKET_NAME} (and ALL contents)"
    echo "  • IAM Role: ${ROLE_NAME}"
    echo "  • CodeCommit Repository: ${CODECOMMIT_REPO}"
    echo ""
    echo "This action CANNOT be undone!"
    echo ""
    
    # Require explicit confirmation
    read -p "Type 'DELETE' to confirm resource destruction: " CONFIRMATION
    
    if [ "$CONFIRMATION" != "DELETE" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource cleanup..."
}

# Function to stop and delete SageMaker pipeline executions
cleanup_pipeline_executions() {
    log_info "Stopping active pipeline executions..."
    
    # List active executions
    ACTIVE_EXECUTIONS=$(aws sagemaker list-pipeline-executions \
        --pipeline-name "${PIPELINE_NAME}" \
        --query 'PipelineExecutionSummaries[?PipelineExecutionStatus==`Executing`].PipelineExecutionArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ACTIVE_EXECUTIONS" ]; then
        for execution_arn in $ACTIVE_EXECUTIONS; do
            log_info "Stopping execution: $(basename $execution_arn)"
            aws sagemaker stop-pipeline-execution \
                --pipeline-execution-arn "$execution_arn" || true
        done
        
        # Wait for executions to stop
        log_info "Waiting for executions to stop..."
        sleep 30
    else
        log_info "No active pipeline executions found"
    fi
}

# Function to delete SageMaker pipeline
delete_sagemaker_pipeline() {
    log_info "Deleting SageMaker pipeline..."
    
    # Check if pipeline exists
    if aws sagemaker describe-pipeline --pipeline-name "${PIPELINE_NAME}" &>/dev/null; then
        # Stop any running executions first
        cleanup_pipeline_executions
        
        # Delete the pipeline
        aws sagemaker delete-pipeline --pipeline-name "${PIPELINE_NAME}"
        log_success "SageMaker pipeline ${PIPELINE_NAME} deleted"
    else
        log_warning "SageMaker pipeline ${PIPELINE_NAME} not found"
    fi
}

# Function to delete SageMaker endpoints and models
cleanup_sagemaker_models() {
    log_info "Cleaning up SageMaker models and endpoints..."
    
    # List and delete endpoints that might be associated with this pipeline
    ENDPOINTS=$(aws sagemaker list-endpoints \
        --name-contains "${PIPELINE_NAME}" \
        --query 'Endpoints[].EndpointName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ENDPOINTS" ]; then
        for endpoint in $ENDPOINTS; do
            log_info "Deleting endpoint: $endpoint"
            aws sagemaker delete-endpoint --endpoint-name "$endpoint" || true
        done
    fi
    
    # List and delete models
    MODELS=$(aws sagemaker list-models \
        --name-contains "${PIPELINE_NAME}" \
        --query 'Models[].ModelName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$MODELS" ]; then
        for model in $MODELS; do
            log_info "Deleting model: $model"
            aws sagemaker delete-model --model-name "$model" || true
        done
    fi
    
    log_success "SageMaker models and endpoints cleanup completed"
}

# Function to delete S3 bucket and contents
delete_s3_bucket() {
    log_info "Deleting S3 bucket and all contents..."
    
    # Check if bucket exists
    if aws s3 ls "s3://${BUCKET_NAME}" &>/dev/null; then
        # Delete all objects including versions
        log_info "Removing all objects from bucket..."
        aws s3 rm "s3://${BUCKET_NAME}" --recursive || true
        
        # Remove any object versions (for versioned buckets)
        log_info "Removing object versions..."
        aws s3api delete-objects \
            --bucket "${BUCKET_NAME}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${BUCKET_NAME}" \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                --output json)" 2>/dev/null || true
        
        # Remove delete markers
        aws s3api delete-objects \
            --bucket "${BUCKET_NAME}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${BUCKET_NAME}" \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                --output json)" 2>/dev/null || true
        
        # Delete the bucket
        aws s3 rb "s3://${BUCKET_NAME}" --force
        log_success "S3 bucket ${BUCKET_NAME} deleted"
    else
        log_warning "S3 bucket ${BUCKET_NAME} not found"
    fi
}

# Function to delete CodeCommit repository
delete_codecommit_repo() {
    log_info "Deleting CodeCommit repository..."
    
    # Check if repository exists
    if aws codecommit get-repository --repository-name "${CODECOMMIT_REPO}" &>/dev/null; then
        aws codecommit delete-repository --repository-name "${CODECOMMIT_REPO}"
        log_success "CodeCommit repository ${CODECOMMIT_REPO} deleted"
    else
        log_warning "CodeCommit repository ${CODECOMMIT_REPO} not found"
    fi
}

# Function to delete IAM role and policies
delete_iam_role() {
    log_info "Deleting IAM role and attached policies..."
    
    # Check if role exists
    if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
        # Detach all managed policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "${ROLE_NAME}" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$ATTACHED_POLICIES" ]; then
            for policy_arn in $ATTACHED_POLICIES; do
                log_info "Detaching policy: $(basename $policy_arn)"
                aws iam detach-role-policy \
                    --role-name "${ROLE_NAME}" \
                    --policy-arn "$policy_arn" || true
            done
        fi
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "${ROLE_NAME}" \
            --query 'PolicyNames[]' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$INLINE_POLICIES" ]; then
            for policy_name in $INLINE_POLICIES; do
                log_info "Deleting inline policy: $policy_name"
                aws iam delete-role-policy \
                    --role-name "${ROLE_NAME}" \
                    --policy-name "$policy_name" || true
            done
        fi
        
        # Delete the role
        aws iam delete-role --role-name "${ROLE_NAME}"
        log_success "IAM role ${ROLE_NAME} deleted"
    else
        log_warning "IAM role ${ROLE_NAME} not found"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        ".env"
        "pipeline_definition.py"
        "train.py"
        "trust-policy.json"
        "sample-data"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -e "$file" ]; then
            rm -rf "$file"
            log_info "Removed: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_status=0
    
    # Check S3 bucket
    if aws s3 ls "s3://${BUCKET_NAME}" &>/dev/null; then
        log_error "✗ S3 bucket still exists"
        cleanup_status=1
    else
        log_success "✓ S3 bucket successfully deleted"
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
        log_error "✗ IAM role still exists"
        cleanup_status=1
    else
        log_success "✓ IAM role successfully deleted"
    fi
    
    # Check CodeCommit repository
    if aws codecommit get-repository --repository-name "${CODECOMMIT_REPO}" &>/dev/null; then
        log_error "✗ CodeCommit repository still exists"
        cleanup_status=1
    else
        log_success "✓ CodeCommit repository successfully deleted"
    fi
    
    # Check SageMaker pipeline
    if aws sagemaker describe-pipeline --pipeline-name "${PIPELINE_NAME}" &>/dev/null; then
        log_error "✗ SageMaker pipeline still exists"
        cleanup_status=1
    else
        log_success "✓ SageMaker pipeline successfully deleted"
    fi
    
    if [ $cleanup_status -eq 0 ]; then
        log_success "All resources successfully cleaned up!"
    else
        log_warning "Some resources may still exist. Please check AWS console."
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "============================================"
    echo "Cleanup Summary"
    echo "============================================"
    echo ""
    log_success "All MLOps pipeline resources have been removed:"
    echo "  ✓ SageMaker Pipeline deleted"
    echo "  ✓ S3 Bucket and contents deleted"
    echo "  ✓ IAM Role and policies deleted"
    echo "  ✓ CodeCommit Repository deleted"
    echo "  ✓ Local files cleaned up"
    echo ""
    log_info "Cleanup completed successfully!"
    echo ""
    echo "Note: It may take a few minutes for all AWS resources"
    echo "to be fully removed from your account."
}

# Function to handle cleanup errors
handle_cleanup_errors() {
    log_error "Cleanup encountered errors. Some resources may still exist."
    echo ""
    echo "Manual cleanup may be required for:"
    echo "  • SageMaker Pipeline: ${PIPELINE_NAME}"
    echo "  • S3 Bucket: ${BUCKET_NAME}"
    echo "  • IAM Role: ${ROLE_NAME}"
    echo "  • CodeCommit Repository: ${CODECOMMIT_REPO}"
    echo ""
    echo "Please check the AWS console and remove any remaining resources."
}

# Main cleanup function
main() {
    echo "=================================================="
    echo "SageMaker MLOps Pipeline Cleanup Script"
    echo "=================================================="
    echo ""
    
    # Load environment and confirm destruction
    load_environment
    confirm_destruction
    
    # Perform cleanup in order
    log_info "Starting resource cleanup..."
    
    # Clean up SageMaker resources first
    delete_sagemaker_pipeline
    cleanup_sagemaker_models
    
    # Clean up storage and repositories
    delete_s3_bucket
    delete_codecommit_repo
    
    # Clean up IAM resources
    delete_iam_role
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    if verify_cleanup; then
        display_cleanup_summary
    else
        handle_cleanup_errors
        exit 1
    fi
}

# Error handling
trap 'handle_cleanup_errors' ERR

# Run main function
main "$@"