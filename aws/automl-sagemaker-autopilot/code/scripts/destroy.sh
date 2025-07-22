#!/bin/bash

# AWS AutoML Solutions with SageMaker Autopilot - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if deployment config exists
load_deployment_config() {
    if [[ ! -f "deployment_config.json" ]]; then
        error "No deployment configuration found. Nothing to clean up."
        info "Expected file: deployment_config.json"
        exit 1
    fi
    
    # Check if jq is available for parsing JSON
    if command -v jq &> /dev/null; then
        # Extract resource names from config file
        export AWS_REGION=$(cat deployment_config.json | jq -r '.aws_region')
        export AWS_ACCOUNT_ID=$(cat deployment_config.json | jq -r '.aws_account_id')
        export RANDOM_SUFFIX=$(cat deployment_config.json | jq -r '.random_suffix')
        export AUTOPILOT_JOB_NAME=$(cat deployment_config.json | jq -r '.resources.autopilot_job_name')
        export S3_BUCKET_NAME=$(cat deployment_config.json | jq -r '.resources.s3_bucket_name')
        export IAM_ROLE_NAME=$(cat deployment_config.json | jq -r '.resources.iam_role_name')
        export ROLE_ARN=$(cat deployment_config.json | jq -r '.resources.iam_role_arn')
        export MODEL_NAME=$(cat deployment_config.json | jq -r '.resources.model_name')
        export ENDPOINT_CONFIG_NAME=$(cat deployment_config.json | jq -r '.resources.endpoint_config_name')
        export ENDPOINT_NAME=$(cat deployment_config.json | jq -r '.resources.endpoint_name')
        export TRANSFORM_JOB_NAME=$(cat deployment_config.json | jq -r '.resources.transform_job_name')
    else
        # Fallback: extract values without jq (basic parsing)
        export AWS_REGION=$(grep -o '"aws_region": "[^"]*"' deployment_config.json | cut -d'"' -f4)
        export AWS_ACCOUNT_ID=$(grep -o '"aws_account_id": "[^"]*"' deployment_config.json | cut -d'"' -f4)
        export RANDOM_SUFFIX=$(grep -o '"random_suffix": "[^"]*"' deployment_config.json | cut -d'"' -f4)
        export AUTOPILOT_JOB_NAME=$(grep -o '"autopilot_job_name": "[^"]*"' deployment_config.json | cut -d'"' -f4)
        export S3_BUCKET_NAME=$(grep -o '"s3_bucket_name": "[^"]*"' deployment_config.json | cut -d'"' -f4)
        export IAM_ROLE_NAME=$(grep -o '"iam_role_name": "[^"]*"' deployment_config.json | cut -d'"' -f4)
        export ROLE_ARN=$(grep -o '"iam_role_arn": "[^"]*"' deployment_config.json | cut -d'"' -f4)
        export MODEL_NAME=$(grep -o '"model_name": "[^"]*"' deployment_config.json | cut -d'"' -f4)
        export ENDPOINT_CONFIG_NAME=$(grep -o '"endpoint_config_name": "[^"]*"' deployment_config.json | cut -d'"' -f4)
        export ENDPOINT_NAME=$(grep -o '"endpoint_name": "[^"]*"' deployment_config.json | cut -d'"' -f4)
        export TRANSFORM_JOB_NAME=$(grep -o '"transform_job_name": "[^"]*"' deployment_config.json | cut -d'"' -f4)
    fi
    
    # Validate required values
    if [[ -z "${S3_BUCKET_NAME}" || -z "${IAM_ROLE_NAME}" || -z "${ENDPOINT_NAME}" ]]; then
        error "Invalid deployment configuration. Required resource names not found."
        exit 1
    fi
    
    log "Loaded deployment configuration from deployment_config.json"
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
        error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Verify we're in the correct region
    local current_region
    current_region=$(aws configure get region)
    if [[ "${current_region}" != "${AWS_REGION}" ]]; then
        warn "Current AWS region (${current_region}) differs from deployment region (${AWS_REGION})"
        warn "Some resources may not be found. Continue anyway? (y/N)"
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log "Prerequisites check completed"
}

# Confirm destruction
confirm_destruction() {
    log "About to destroy the following resources:"
    log "  • S3 Bucket: ${S3_BUCKET_NAME}"
    log "  • IAM Role: ${IAM_ROLE_NAME}"
    log "  • AutoML Job: ${AUTOPILOT_JOB_NAME}"
    log "  • SageMaker Model: ${MODEL_NAME}"
    log "  • Endpoint: ${ENDPOINT_NAME}"
    log "  • Batch Transform Job: ${TRANSFORM_JOB_NAME}"
    log ""
    warn "This action cannot be undone!"
    warn "Are you sure you want to proceed? (y/N)"
    
    read -r response
    if [[ ! "${response}" =~ ^[Yy]$ ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
}

# Stop and delete SageMaker endpoint
delete_endpoint() {
    log "Deleting SageMaker endpoint..."
    
    # Check if endpoint exists
    if aws sagemaker describe-endpoint --endpoint-name "${ENDPOINT_NAME}" &> /dev/null; then
        local endpoint_status
        endpoint_status=$(aws sagemaker describe-endpoint \
            --endpoint-name "${ENDPOINT_NAME}" \
            --query 'EndpointStatus' \
            --output text)
        
        info "Endpoint status: ${endpoint_status}"
        
        # Delete endpoint
        aws sagemaker delete-endpoint \
            --endpoint-name "${ENDPOINT_NAME}"
        
        # Wait for deletion if endpoint was in service
        if [[ "${endpoint_status}" == "InService" ]]; then
            info "Waiting for endpoint deletion..."
            local max_wait=600  # 10 minutes
            local wait_time=0
            
            while [[ ${wait_time} -lt ${max_wait} ]]; do
                if ! aws sagemaker describe-endpoint --endpoint-name "${ENDPOINT_NAME}" &> /dev/null; then
                    break
                fi
                sleep 30
                wait_time=$((wait_time + 30))
                info "Still waiting for endpoint deletion... (${wait_time}s)"
            done
        fi
        
        log "Endpoint deleted successfully"
    else
        info "Endpoint not found or already deleted"
    fi
}

# Delete endpoint configuration
delete_endpoint_config() {
    log "Deleting endpoint configuration..."
    
    if aws sagemaker describe-endpoint-config --endpoint-config-name "${ENDPOINT_CONFIG_NAME}" &> /dev/null; then
        aws sagemaker delete-endpoint-config \
            --endpoint-config-name "${ENDPOINT_CONFIG_NAME}"
        log "Endpoint configuration deleted successfully"
    else
        info "Endpoint configuration not found or already deleted"
    fi
}

# Delete SageMaker model
delete_model() {
    log "Deleting SageMaker model..."
    
    if aws sagemaker describe-model --model-name "${MODEL_NAME}" &> /dev/null; then
        aws sagemaker delete-model \
            --model-name "${MODEL_NAME}"
        log "Model deleted successfully"
    else
        info "Model not found or already deleted"
    fi
}

# Stop batch transform job
stop_transform_job() {
    log "Stopping batch transform job..."
    
    if aws sagemaker describe-transform-job --transform-job-name "${TRANSFORM_JOB_NAME}" &> /dev/null; then
        local job_status
        job_status=$(aws sagemaker describe-transform-job \
            --transform-job-name "${TRANSFORM_JOB_NAME}" \
            --query 'TransformJobStatus' \
            --output text)
        
        info "Transform job status: ${job_status}"
        
        # Stop job if it's running
        if [[ "${job_status}" == "InProgress" ]]; then
            aws sagemaker stop-transform-job \
                --transform-job-name "${TRANSFORM_JOB_NAME}"
            log "Transform job stopped"
        else
            info "Transform job is not running (status: ${job_status})"
        fi
    else
        info "Transform job not found"
    fi
}

# Stop AutoML job if running
stop_autopilot_job() {
    log "Checking AutoML job status..."
    
    if aws sagemaker describe-auto-ml-job-v2 --auto-ml-job-name "${AUTOPILOT_JOB_NAME}" &> /dev/null; then
        local job_status
        job_status=$(aws sagemaker describe-auto-ml-job-v2 \
            --auto-ml-job-name "${AUTOPILOT_JOB_NAME}" \
            --query 'AutoMLJobStatus' \
            --output text)
        
        info "AutoML job status: ${job_status}"
        
        # Stop job if it's running
        if [[ "${job_status}" == "InProgress" ]]; then
            aws sagemaker stop-auto-ml-job \
                --auto-ml-job-name "${AUTOPILOT_JOB_NAME}"
            log "AutoML job stopped"
            
            # Wait for job to stop
            info "Waiting for AutoML job to stop..."
            local max_wait=300  # 5 minutes
            local wait_time=0
            
            while [[ ${wait_time} -lt ${max_wait} ]]; do
                local current_status
                current_status=$(aws sagemaker describe-auto-ml-job-v2 \
                    --auto-ml-job-name "${AUTOPILOT_JOB_NAME}" \
                    --query 'AutoMLJobStatus' \
                    --output text)
                
                if [[ "${current_status}" == "Stopped" ]]; then
                    break
                fi
                
                sleep 15
                wait_time=$((wait_time + 15))
                info "Still waiting for AutoML job to stop... (${wait_time}s)"
            done
        else
            info "AutoML job is not running (status: ${job_status})"
        fi
    else
        info "AutoML job not found"
    fi
}

# Delete S3 bucket and contents
delete_s3_bucket() {
    log "Deleting S3 bucket and contents..."
    
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        # Delete all objects including versions
        info "Removing all objects from bucket..."
        aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive
        
        # Delete all object versions if versioning is enabled
        local versions_output
        versions_output=$(aws s3api list-object-versions \
            --bucket "${S3_BUCKET_NAME}" \
            --output text \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' 2>/dev/null || true)
        
        if [[ -n "${versions_output}" ]]; then
            info "Removing object versions..."
            echo "${versions_output}" | while read -r key version_id; do
                if [[ -n "${key}" && -n "${version_id}" ]]; then
                    aws s3api delete-object \
                        --bucket "${S3_BUCKET_NAME}" \
                        --key "${key}" \
                        --version-id "${version_id}" &> /dev/null || true
                fi
            done
        fi
        
        # Delete delete markers
        local delete_markers
        delete_markers=$(aws s3api list-object-versions \
            --bucket "${S3_BUCKET_NAME}" \
            --output text \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' 2>/dev/null || true)
        
        if [[ -n "${delete_markers}" ]]; then
            info "Removing delete markers..."
            echo "${delete_markers}" | while read -r key version_id; do
                if [[ -n "${key}" && -n "${version_id}" ]]; then
                    aws s3api delete-object \
                        --bucket "${S3_BUCKET_NAME}" \
                        --key "${key}" \
                        --version-id "${version_id}" &> /dev/null || true
                fi
            done
        fi
        
        # Delete bucket
        aws s3 rb "s3://${S3_BUCKET_NAME}"
        log "S3 bucket deleted successfully"
    else
        info "S3 bucket not found or already deleted"
    fi
}

# Delete IAM role
delete_iam_role() {
    log "Deleting IAM role..."
    
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        # Detach policies
        info "Detaching policies from role..."
        aws iam detach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess 2>/dev/null || true
        
        aws iam detach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess 2>/dev/null || true
        
        # Delete role
        aws iam delete-role \
            --role-name "${IAM_ROLE_NAME}"
        
        log "IAM role deleted successfully"
    else
        info "IAM role not found or already deleted"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # List of files to remove
    local files_to_remove=(
        "churn_dataset.csv"
        "test_data.csv"
        "autopilot_job_config.json"
        "prediction_output.json"
        "endpoint_test.json"
        "deployment_config.json"
    )
    
    # Remove files if they exist
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            info "Removed: ${file}"
        fi
    done
    
    # Remove artifacts directory
    if [[ -d "./autopilot_artifacts" ]]; then
        rm -rf "./autopilot_artifacts"
        info "Removed: ./autopilot_artifacts/"
    fi
    
    log "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=()
    
    # Check S3 bucket
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        cleanup_issues+=("S3 bucket still exists")
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        cleanup_issues+=("IAM role still exists")
    fi
    
    # Check endpoint
    if aws sagemaker describe-endpoint --endpoint-name "${ENDPOINT_NAME}" &> /dev/null; then
        cleanup_issues+=("SageMaker endpoint still exists")
    fi
    
    # Check model
    if aws sagemaker describe-model --model-name "${MODEL_NAME}" &> /dev/null; then
        cleanup_issues+=("SageMaker model still exists")
    fi
    
    # Report results
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        log "Cleanup verification completed successfully"
        return 0
    else
        warn "Some resources may still exist:"
        for issue in "${cleanup_issues[@]}"; do
            warn "  • ${issue}"
        done
        warn "Manual cleanup may be required"
        return 1
    fi
}

# Main cleanup function
main() {
    log "Starting AWS AutoML Solutions cleanup..."
    
    # Load configuration and check prerequisites
    load_deployment_config
    check_prerequisites
    
    # Confirm destruction unless --force flag is provided
    if [[ "$*" != *"--force"* ]]; then
        confirm_destruction
    fi
    
    # Execute cleanup in correct order
    log "Beginning resource cleanup..."
    
    # Stop/delete compute resources first
    delete_endpoint
    delete_endpoint_config
    delete_model
    stop_transform_job
    stop_autopilot_job
    
    # Delete storage and IAM resources
    delete_s3_bucket
    delete_iam_role
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    if verify_cleanup; then
        log "Cleanup completed successfully!"
        log "═══════════════════════════════════════════════════════════════════════════════"
        log "AWS AutoML Solutions cleanup completed!"
        log ""
        log "All resources have been successfully removed:"
        log "  ✓ SageMaker endpoint and configuration"
        log "  ✓ SageMaker model"
        log "  ✓ AutoML and batch transform jobs"
        log "  ✓ S3 bucket and contents"
        log "  ✓ IAM role and policies"
        log "  ✓ Local files and artifacts"
        log ""
        log "No further charges will be incurred for these resources."
        log "═══════════════════════════════════════════════════════════════════════════════"
    else
        warn "Cleanup completed with some issues. Please check the AWS console for any remaining resources."
        exit 1
    fi
}

# Handle script arguments
if [[ "$*" == *"--help"* || "$*" == *"-h"* ]]; then
    echo "AWS AutoML Solutions Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force    Skip confirmation prompts"
    echo "  --help     Show this help message"
    echo ""
    echo "This script removes all resources created by the deploy.sh script."
    echo "It requires a deployment_config.json file to identify resources."
    exit 0
fi

# Execute main function
main "$@"