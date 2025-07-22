#!/bin/bash

# Destroy script for ML Models with Amazon SageMaker Endpoints
# This script safely removes all resources created by the deploy script

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_FILE="${SCRIPT_DIR}/destroy_errors.log"
ENV_FILE="${SCRIPT_DIR}/.env"

# Logging functions
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $1" | tee -a "$ERROR_FILE" >&2
}

warning() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] WARNING: $1" | tee -a "$LOG_FILE"
}

# Cleanup function for script exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Cleanup failed with exit code $exit_code"
        log "Check $ERROR_FILE for detailed error information"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure'"
        exit 1
    fi
    
    log "Prerequisites satisfied"
}

# Load environment variables from deployment
load_environment() {
    log "Loading environment variables from deployment..."
    
    if [ ! -f "$ENV_FILE" ]; then
        error "Environment file not found: $ENV_FILE"
        error "Cannot proceed with cleanup without deployment information"
        exit 1
    fi
    
    # Source the environment file
    source "$ENV_FILE"
    
    # Validate required variables
    local required_vars=("REGION" "ACCOUNT_ID" "MODEL_NAME" "ENDPOINT_NAME" "ECR_REPOSITORY_NAME" "BUCKET_NAME" "ROLE_NAME")
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    log "Environment loaded successfully"
    log "Region: $REGION"
    log "Account: $ACCOUNT_ID"
    log "Endpoint: $ENDPOINT_NAME"
    log "Model: $MODEL_NAME"
}

# Confirmation prompt
confirm_deletion() {
    echo
    echo "==============================================="
    echo "WARNING: This will permanently delete:"
    echo "==============================================="
    echo "• SageMaker Endpoint: $ENDPOINT_NAME"
    echo "• SageMaker Model: $MODEL_NAME"
    echo "• ECR Repository: $ECR_REPOSITORY_NAME"
    echo "• S3 Bucket: $BUCKET_NAME"
    echo "• IAM Role: $ROLE_NAME"
    echo "• All associated data and configurations"
    echo "==============================================="
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "User confirmed deletion. Proceeding with cleanup..."
}

# Delete auto-scaling configuration
delete_autoscaling() {
    log "Removing auto-scaling configuration..."
    
    # Check if scalable target exists
    if aws application-autoscaling describe-scalable-targets \
        --service-namespace sagemaker \
        --resource-ids "endpoint/$ENDPOINT_NAME/variant/primary" \
        --region "$REGION" --query 'ScalableTargets[0]' --output text 2>/dev/null | grep -q "endpoint"; then
        
        # Delete scaling policy first
        log "Deleting scaling policy..."
        aws application-autoscaling delete-scaling-policy \
            --service-namespace sagemaker \
            --resource-id "endpoint/$ENDPOINT_NAME/variant/primary" \
            --scalable-dimension sagemaker:variant:DesiredInstanceCount \
            --policy-name iris-endpoint-scaling-policy \
            --region "$REGION" >> "$LOG_FILE" 2>> "$ERROR_FILE" || warning "Failed to delete scaling policy"
        
        # Deregister scalable target
        log "Deregistering scalable target..."
        aws application-autoscaling deregister-scalable-target \
            --service-namespace sagemaker \
            --resource-id "endpoint/$ENDPOINT_NAME/variant/primary" \
            --scalable-dimension sagemaker:variant:DesiredInstanceCount \
            --region "$REGION" >> "$LOG_FILE" 2>> "$ERROR_FILE" || warning "Failed to deregister scalable target"
        
        log "Auto-scaling configuration removed"
    else
        log "No auto-scaling configuration found"
    fi
}

# Delete SageMaker endpoint
delete_endpoint() {
    log "Deleting SageMaker endpoint: $ENDPOINT_NAME"
    
    # Check if endpoint exists
    if aws sagemaker describe-endpoint --endpoint-name "$ENDPOINT_NAME" --region "$REGION" &> /dev/null; then
        
        local status=$(aws sagemaker describe-endpoint --endpoint-name "$ENDPOINT_NAME" --region "$REGION" --query 'EndpointStatus' --output text)
        log "Current endpoint status: $status"
        
        # Delete the endpoint
        aws sagemaker delete-endpoint \
            --endpoint-name "$ENDPOINT_NAME" \
            --region "$REGION" >> "$LOG_FILE" 2>> "$ERROR_FILE"
        
        log "Waiting for endpoint deletion to complete..."
        
        # Wait for endpoint deletion with timeout
        local timeout=300  # 5 minutes
        local elapsed=0
        local interval=10
        
        while [ $elapsed -lt $timeout ]; do
            if ! aws sagemaker describe-endpoint --endpoint-name "$ENDPOINT_NAME" --region "$REGION" &> /dev/null; then
                log "Endpoint deleted successfully"
                return 0
            fi
            
            sleep $interval
            elapsed=$((elapsed + interval))
            log "Still waiting for endpoint deletion... (${elapsed}s elapsed)"
        done
        
        warning "Endpoint deletion timed out after ${timeout}s"
    else
        log "Endpoint not found or already deleted"
    fi
}

# Delete endpoint configuration
delete_endpoint_config() {
    log "Deleting endpoint configuration: ${ENDPOINT_CONFIG_NAME:-${MODEL_NAME}-config}"
    
    local config_name="${ENDPOINT_CONFIG_NAME:-${MODEL_NAME}-config}"
    
    if aws sagemaker describe-endpoint-config --endpoint-config-name "$config_name" --region "$REGION" &> /dev/null; then
        aws sagemaker delete-endpoint-config \
            --endpoint-config-name "$config_name" \
            --region "$REGION" >> "$LOG_FILE" 2>> "$ERROR_FILE"
        
        log "Endpoint configuration deleted: $config_name"
    else
        log "Endpoint configuration not found or already deleted"
    fi
}

# Delete SageMaker model
delete_sagemaker_model() {
    log "Deleting SageMaker model: $MODEL_NAME"
    
    if aws sagemaker describe-model --model-name "$MODEL_NAME" --region "$REGION" &> /dev/null; then
        aws sagemaker delete-model \
            --model-name "$MODEL_NAME" \
            --region "$REGION" >> "$LOG_FILE" 2>> "$ERROR_FILE"
        
        log "SageMaker model deleted: $MODEL_NAME"
    else
        log "SageMaker model not found or already deleted"
    fi
}

# Delete S3 bucket and contents
delete_s3_bucket() {
    log "Deleting S3 bucket and contents: $BUCKET_NAME"
    
    if aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        # Delete all objects first
        log "Removing all objects from bucket..."
        aws s3 rm "s3://$BUCKET_NAME" --recursive >> "$LOG_FILE" 2>> "$ERROR_FILE" || warning "Failed to delete some objects"
        
        # Delete the bucket
        log "Deleting bucket..."
        aws s3 rb "s3://$BUCKET_NAME" >> "$LOG_FILE" 2>> "$ERROR_FILE"
        
        log "S3 bucket deleted: $BUCKET_NAME"
    else
        log "S3 bucket not found or already deleted"
    fi
}

# Delete ECR repository
delete_ecr_repository() {
    log "Deleting ECR repository: $ECR_REPOSITORY_NAME"
    
    if aws ecr describe-repositories --repository-names "$ECR_REPOSITORY_NAME" --region "$REGION" &> /dev/null; then
        aws ecr delete-repository \
            --repository-name "$ECR_REPOSITORY_NAME" \
            --force \
            --region "$REGION" >> "$LOG_FILE" 2>> "$ERROR_FILE"
        
        log "ECR repository deleted: $ECR_REPOSITORY_NAME"
    else
        log "ECR repository not found or already deleted"
    fi
}

# Delete IAM role and policies
delete_iam_role() {
    log "Deleting IAM role: $ROLE_NAME"
    
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        # Detach policies first
        log "Detaching policies from role..."
        
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess \
            >> "$LOG_FILE" 2>> "$ERROR_FILE" || warning "Failed to detach SageMaker policy"
        
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
            >> "$LOG_FILE" 2>> "$ERROR_FILE" || warning "Failed to detach S3 policy"
        
        # Delete the role
        log "Deleting IAM role..."
        aws iam delete-role --role-name "$ROLE_NAME" >> "$LOG_FILE" 2>> "$ERROR_FILE"
        
        log "IAM role deleted: $ROLE_NAME"
    else
        log "IAM role not found or already deleted"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files and directories..."
    
    # Remove model training directory
    if [ -d "${SCRIPT_DIR}/../model-training" ]; then
        rm -rf "${SCRIPT_DIR}/../model-training"
        log "Removed model training directory"
    fi
    
    # Remove container directory
    if [ -d "${SCRIPT_DIR}/../container" ]; then
        rm -rf "${SCRIPT_DIR}/../container"
        log "Removed container directory"
    fi
    
    # Remove temporary files
    rm -f /tmp/sagemaker-trust-policy.json
    rm -f /tmp/test_payload.json
    rm -f /tmp/prediction_output.json
    
    # Remove environment file
    if [ -f "$ENV_FILE" ]; then
        rm -f "$ENV_FILE"
        log "Removed environment file"
    fi
    
    log "Local cleanup completed"
}

# Remove Docker images
cleanup_docker_images() {
    log "Cleaning up Docker images..."
    
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        # Remove local Docker images
        if docker images -q "$ECR_REPOSITORY_NAME" &> /dev/null; then
            docker rmi "$ECR_REPOSITORY_NAME" >> "$LOG_FILE" 2>> "$ERROR_FILE" || warning "Failed to remove Docker image: $ECR_REPOSITORY_NAME"
        fi
        
        if [ -n "${ECR_IMAGE_URI:-}" ] && docker images -q "$ECR_IMAGE_URI" &> /dev/null; then
            docker rmi "$ECR_IMAGE_URI" >> "$LOG_FILE" 2>> "$ERROR_FILE" || warning "Failed to remove Docker image: $ECR_IMAGE_URI"
        fi
        
        # Clean up unused Docker resources
        docker system prune -f >> "$LOG_FILE" 2>> "$ERROR_FILE" || warning "Failed to prune Docker system"
        
        log "Docker cleanup completed"
    else
        log "Docker not available, skipping Docker cleanup"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check endpoint
    if aws sagemaker describe-endpoint --endpoint-name "$ENDPOINT_NAME" --region "$REGION" &> /dev/null; then
        warning "Endpoint still exists: $ENDPOINT_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check model
    if aws sagemaker describe-model --model-name "$MODEL_NAME" --region "$REGION" &> /dev/null; then
        warning "Model still exists: $MODEL_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check S3 bucket
    if aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        warning "S3 bucket still exists: $BUCKET_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check ECR repository
    if aws ecr describe-repositories --repository-names "$ECR_REPOSITORY_NAME" --region "$REGION" &> /dev/null; then
        warning "ECR repository still exists: $ECR_REPOSITORY_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        warning "IAM role still exists: $ROLE_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log "All resources successfully cleaned up"
    else
        warning "$cleanup_issues resources may still exist and require manual cleanup"
    fi
}

# Main execution
main() {
    log "Starting SageMaker ML model cleanup..."
    log "Cleanup logs: $LOG_FILE"
    log "Error logs: $ERROR_FILE"
    
    check_prerequisites
    load_environment
    confirm_deletion
    
    log "Beginning resource deletion..."
    
    # Delete resources in proper order
    delete_autoscaling
    delete_endpoint
    delete_endpoint_config
    delete_sagemaker_model
    delete_s3_bucket
    delete_ecr_repository
    delete_iam_role
    cleanup_docker_images
    cleanup_local_files
    
    verify_cleanup
    
    log "===========================================" 
    log "Cleanup completed!"
    log "==========================================="
    log "All SageMaker ML model resources have been removed"
    log "Check the logs above for any warnings or issues"
    log "==========================================="
}

# Execute main function
main "$@"