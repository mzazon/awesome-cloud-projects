#!/bin/bash

# Destroy script for Machine Learning Model Deployment Pipelines with SageMaker and CodePipeline
# This script safely removes all resources created by the deploy.sh script

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
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    success "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ -f ".env" ]; then
        # Source the environment file
        set -a  # automatically export all variables
        source .env
        set +a  # stop automatically exporting
        
        success "Loaded environment variables from .env file"
        log "Project Name: ${PROJECT_NAME}"
        log "S3 Bucket: ${BUCKET_NAME}"
        log "Pipeline Name: ${PIPELINE_NAME}"
    else
        warning ".env file not found. Please provide environment variables manually."
        read -p "Enter PROJECT_NAME: " PROJECT_NAME
        read -p "Enter BUCKET_NAME: " BUCKET_NAME
        read -p "Enter PIPELINE_NAME: " PIPELINE_NAME
        read -p "Enter MODEL_PACKAGE_GROUP_NAME: " MODEL_PACKAGE_GROUP_NAME
        read -p "Enter RANDOM_SUFFIX: " RANDOM_SUFFIX
        
        export PROJECT_NAME BUCKET_NAME PIPELINE_NAME MODEL_PACKAGE_GROUP_NAME RANDOM_SUFFIX
    fi
}

# Function to confirm destruction
confirm_destruction() {
    log "This script will destroy the following resources:"
    echo "=============================================="
    echo "- CodePipeline: ${PIPELINE_NAME}"
    echo "- CodeBuild Projects: ${PROJECT_NAME}-train, ${PROJECT_NAME}-test"
    echo "- Lambda Function: ${PROJECT_NAME}-deploy"
    echo "- SageMaker Model Package Group: ${MODEL_PACKAGE_GROUP_NAME}"
    echo "- SageMaker Endpoints (if any)"
    echo "- S3 Bucket: ${BUCKET_NAME} (and all contents)"
    echo "- IAM Roles: SageMakerExecutionRole-${RANDOM_SUFFIX}, CodeBuildServiceRole-${RANDOM_SUFFIX}, etc."
    echo ""
    warning "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Proceeding with resource destruction..."
}

# Function to stop pipeline execution
stop_pipeline_execution() {
    log "Stopping any running pipeline executions..."
    
    # Get the latest execution ID
    EXECUTION_ID=$(aws codepipeline list-pipeline-executions \
        --pipeline-name "${PIPELINE_NAME}" \
        --query 'pipelineExecutionSummaries[0].pipelineExecutionId' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$EXECUTION_ID" != "None" ] && [ "$EXECUTION_ID" != "null" ]; then
        # Check if execution is still running
        EXECUTION_STATUS=$(aws codepipeline get-pipeline-execution \
            --pipeline-name "${PIPELINE_NAME}" \
            --pipeline-execution-id "${EXECUTION_ID}" \
            --query 'pipelineExecution.status' \
            --output text 2>/dev/null || echo "Unknown")
        
        if [ "$EXECUTION_STATUS" = "InProgress" ]; then
            log "Stopping pipeline execution: ${EXECUTION_ID}"
            aws codepipeline stop-pipeline-execution \
                --pipeline-name "${PIPELINE_NAME}" \
                --pipeline-execution-id "${EXECUTION_ID}" \
                --abandon true &>/dev/null || true
            success "Stopped pipeline execution"
        else
            log "No active pipeline execution to stop"
        fi
    else
        log "No pipeline executions found"
    fi
}

# Function to delete SageMaker resources
delete_sagemaker_resources() {
    log "Deleting SageMaker resources..."
    
    # Delete any endpoints that might have been created
    log "Checking for SageMaker endpoints to delete..."
    ENDPOINTS=$(aws sagemaker list-endpoints \
        --name-contains fraud-detection \
        --query 'Endpoints[].EndpointName' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$ENDPOINTS" ]; then
        for ENDPOINT in $ENDPOINTS; do
            log "Deleting endpoint: ${ENDPOINT}"
            aws sagemaker delete-endpoint \
                --endpoint-name "${ENDPOINT}" &>/dev/null || true
            success "Deleted endpoint: ${ENDPOINT}"
        done
    else
        log "No endpoints found to delete"
    fi
    
    # Delete endpoint configurations
    log "Checking for endpoint configurations to delete..."
    ENDPOINT_CONFIGS=$(aws sagemaker list-endpoint-configs \
        --name-contains fraud-detection \
        --query 'EndpointConfigs[].EndpointConfigName' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$ENDPOINT_CONFIGS" ]; then
        for CONFIG in $ENDPOINT_CONFIGS; do
            log "Deleting endpoint configuration: ${CONFIG}"
            aws sagemaker delete-endpoint-config \
                --endpoint-config-name "${CONFIG}" &>/dev/null || true
            success "Deleted endpoint configuration: ${CONFIG}"
        done
    else
        log "No endpoint configurations found to delete"
    fi
    
    # Delete models
    log "Checking for models to delete..."
    MODELS=$(aws sagemaker list-models \
        --name-contains fraud-detection \
        --query 'Models[].ModelName' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$MODELS" ]; then
        for MODEL in $MODELS; do
            log "Deleting model: ${MODEL}"
            aws sagemaker delete-model \
                --model-name "${MODEL}" &>/dev/null || true
            success "Deleted model: ${MODEL}"
        done
    else
        log "No models found to delete"
    fi
    
    # Note: Model Package Group deletion is handled separately
    # because it requires all model packages to be deleted first
    log "Model package group will be deleted later if empty"
}

# Function to delete CodePipeline
delete_codepipeline() {
    log "Deleting CodePipeline..."
    
    if aws codepipeline get-pipeline --name "${PIPELINE_NAME}" &>/dev/null; then
        aws codepipeline delete-pipeline \
            --name "${PIPELINE_NAME}"
        success "Deleted CodePipeline: ${PIPELINE_NAME}"
    else
        warning "CodePipeline ${PIPELINE_NAME} not found"
    fi
}

# Function to delete CodeBuild projects
delete_codebuild_projects() {
    log "Deleting CodeBuild projects..."
    
    # Delete training project
    if aws codebuild batch-get-projects --names "${PROJECT_NAME}-train" &>/dev/null; then
        aws codebuild delete-project \
            --name "${PROJECT_NAME}-train"
        success "Deleted CodeBuild project: ${PROJECT_NAME}-train"
    else
        warning "CodeBuild project ${PROJECT_NAME}-train not found"
    fi
    
    # Delete testing project
    if aws codebuild batch-get-projects --names "${PROJECT_NAME}-test" &>/dev/null; then
        aws codebuild delete-project \
            --name "${PROJECT_NAME}-test"
        success "Deleted CodeBuild project: ${PROJECT_NAME}-test"
    else
        warning "CodeBuild project ${PROJECT_NAME}-test not found"
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    if aws lambda get-function --function-name "${PROJECT_NAME}-deploy" &>/dev/null; then
        aws lambda delete-function \
            --function-name "${PROJECT_NAME}-deploy"
        success "Deleted Lambda function: ${PROJECT_NAME}-deploy"
    else
        warning "Lambda function ${PROJECT_NAME}-deploy not found"
    fi
}

# Function to delete model package group
delete_model_package_group() {
    log "Attempting to delete Model Package Group..."
    
    if aws sagemaker describe-model-package-group \
        --model-package-group-name "${MODEL_PACKAGE_GROUP_NAME}" &>/dev/null; then
        
        # First, list all model packages in the group
        MODEL_PACKAGES=$(aws sagemaker list-model-packages \
            --model-package-group-name "${MODEL_PACKAGE_GROUP_NAME}" \
            --query 'ModelPackageSummaryList[].ModelPackageArn' \
            --output text 2>/dev/null || echo "")
        
        if [ ! -z "$MODEL_PACKAGES" ]; then
            warning "Model Package Group contains model packages. Cannot delete automatically."
            warning "Please manually delete model packages first, then delete the group."
            log "Model packages to delete:"
            for PACKAGE in $MODEL_PACKAGES; do
                echo "  - $PACKAGE"
            done
        else
            # Try to delete the empty group
            aws sagemaker delete-model-package-group \
                --model-package-group-name "${MODEL_PACKAGE_GROUP_NAME}" &>/dev/null || \
                warning "Could not delete model package group (may contain packages)"
            success "Deleted Model Package Group: ${MODEL_PACKAGE_GROUP_NAME}"
        fi
    else
        warning "Model Package Group ${MODEL_PACKAGE_GROUP_NAME} not found"
    fi
}

# Function to delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    # Delete SageMaker execution role
    if aws iam get-role --role-name "SageMakerExecutionRole-${RANDOM_SUFFIX}" &>/dev/null; then
        # Detach policies first
        aws iam detach-role-policy \
            --role-name "SageMakerExecutionRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess &>/dev/null || true
        
        aws iam detach-role-policy \
            --role-name "SageMakerExecutionRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess &>/dev/null || true
        
        aws iam delete-role \
            --role-name "SageMakerExecutionRole-${RANDOM_SUFFIX}"
        success "Deleted SageMaker execution role"
    else
        warning "SageMaker execution role not found"
    fi
    
    # Delete CodeBuild service role
    if aws iam get-role --role-name "CodeBuildServiceRole-${RANDOM_SUFFIX}" &>/dev/null; then
        # Detach policies first
        aws iam detach-role-policy \
            --role-name "CodeBuildServiceRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess &>/dev/null || true
        
        aws iam detach-role-policy \
            --role-name "CodeBuildServiceRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess &>/dev/null || true
        
        aws iam detach-role-policy \
            --role-name "CodeBuildServiceRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess &>/dev/null || true
        
        aws iam delete-role \
            --role-name "CodeBuildServiceRole-${RANDOM_SUFFIX}"
        success "Deleted CodeBuild service role"
    else
        warning "CodeBuild service role not found"
    fi
    
    # Delete CodePipeline service role
    if aws iam get-role --role-name "CodePipelineServiceRole-${RANDOM_SUFFIX}" &>/dev/null; then
        # Delete inline policy first
        aws iam delete-role-policy \
            --role-name "CodePipelineServiceRole-${RANDOM_SUFFIX}" \
            --policy-name CodePipelineServicePolicy &>/dev/null || true
        
        aws iam delete-role \
            --role-name "CodePipelineServiceRole-${RANDOM_SUFFIX}"
        success "Deleted CodePipeline service role"
    else
        warning "CodePipeline service role not found"
    fi
    
    # Delete Lambda execution role
    if aws iam get-role --role-name "LambdaExecutionRole-${RANDOM_SUFFIX}" &>/dev/null; then
        # Detach policies first
        aws iam detach-role-policy \
            --role-name "LambdaExecutionRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole &>/dev/null || true
        
        aws iam detach-role-policy \
            --role-name "LambdaExecutionRole-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess &>/dev/null || true
        
        aws iam delete-role \
            --role-name "LambdaExecutionRole-${RANDOM_SUFFIX}"
        success "Deleted Lambda execution role"
    else
        warning "Lambda execution role not found"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket and all contents..."
    
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        # Delete all objects and versions first
        log "Emptying S3 bucket: ${BUCKET_NAME}"
        aws s3 rm "s3://${BUCKET_NAME}" --recursive &>/dev/null || true
        
        # Delete the bucket
        aws s3api delete-bucket --bucket "${BUCKET_NAME}"
        success "Deleted S3 bucket: ${BUCKET_NAME}"
    else
        warning "S3 bucket ${BUCKET_NAME} not found"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files that might have been created
    rm -f /tmp/buildspec-train.yml
    rm -f /tmp/buildspec-test.yml
    rm -f /tmp/train.py
    rm -f /tmp/deploy_function.py
    rm -f /tmp/deploy_function.zip
    rm -f /tmp/training_data.csv
    rm -f /tmp/pipeline.json
    rm -f /tmp/codepipeline-policy.json
    rm -rf /tmp/ml-source-code
    
    # Remove .env file if it exists
    if [ -f ".env" ]; then
        rm -f .env
        success "Removed .env file"
    fi
    
    success "Cleaned up local files"
}

# Function to wait for resource deletion
wait_for_deletion() {
    log "Waiting for resources to be fully deleted..."
    
    # Wait a bit for eventual consistency
    sleep 5
    
    success "Resource deletion wait completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "================"
    echo ""
    echo "The following resources have been removed:"
    echo "- CodePipeline: ${PIPELINE_NAME}"
    echo "- CodeBuild Projects: ${PROJECT_NAME}-train, ${PROJECT_NAME}-test"
    echo "- Lambda Function: ${PROJECT_NAME}-deploy"
    echo "- SageMaker Endpoints and Configurations"
    echo "- SageMaker Models"
    echo "- IAM Roles (SageMaker, CodeBuild, CodePipeline, Lambda)"
    echo "- S3 Bucket: ${BUCKET_NAME}"
    echo "- Local temporary files"
    echo ""
    
    if aws sagemaker describe-model-package-group \
        --model-package-group-name "${MODEL_PACKAGE_GROUP_NAME}" &>/dev/null; then
        warning "Model Package Group still exists (may contain model packages)"
        echo "If you want to delete the Model Package Group:"
        echo "1. Manually delete all model packages in the group"
        echo "2. Run: aws sagemaker delete-model-package-group --model-package-group-name ${MODEL_PACKAGE_GROUP_NAME}"
    else
        echo "- Model Package Group: ${MODEL_PACKAGE_GROUP_NAME}"
    fi
    
    echo ""
    success "Cleanup completed successfully!"
    echo ""
    log "Note: Some resources may take a few minutes to be fully removed from the AWS console."
}

# Function to handle cleanup errors gracefully
handle_cleanup_error() {
    local exit_code=$?
    error "Cleanup encountered an error (exit code: $exit_code)"
    warning "Some resources may not have been deleted completely."
    warning "Please check the AWS console and clean up any remaining resources manually."
    exit $exit_code
}

# Main execution
main() {
    log "Starting MLOps Pipeline Cleanup..."
    log "=================================="
    
    check_prerequisites
    load_environment
    confirm_destruction
    stop_pipeline_execution
    delete_sagemaker_resources
    delete_codepipeline
    delete_codebuild_projects
    delete_lambda_function
    delete_model_package_group
    delete_iam_roles
    delete_s3_bucket
    cleanup_local_files
    wait_for_deletion
    display_cleanup_summary
}

# Trap errors and provide helpful cleanup guidance
trap 'handle_cleanup_error' ERR

# Run main function
main "$@"