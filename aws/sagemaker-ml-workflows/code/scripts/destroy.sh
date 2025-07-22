#!/bin/bash

# ML Pipeline Cleanup Script
# This script removes all resources created by the ML pipeline deployment

set -e  # Exit on any error

# Colors for output
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

# Check if running in confirmation mode
SKIP_CONFIRMATION=false
if [[ "$1" == "--yes" || "$1" == "-y" ]]; then
    SKIP_CONFIRMATION=true
fi

# Prerequisites check
log "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    error "AWS CLI not found. Please install AWS CLI v2"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure'"
    exit 1
fi

# Get AWS account information
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
if [[ -z "$AWS_REGION" ]]; then
    AWS_REGION="us-east-1"
fi

# Function to prompt for confirmation
confirm_action() {
    local message="$1"
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    while true; do
        echo -e "${YELLOW}$message (y/n): ${NC}"
        read -r response
        case $response in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer y or n.";;
        esac
    done
}

# Function to find ML pipeline resources
find_ml_resources() {
    log "Scanning for ML pipeline resources..."
    
    # Look for S3 buckets with ml-pipeline prefix
    ML_BUCKETS=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `ml-pipeline-bucket-`)].Name' --output text)
    
    # Look for Step Functions state machines
    STATE_MACHINES=$(aws stepfunctions list-state-machines --query 'stateMachines[?starts_with(name, `ml-pipeline-`)].{Name:name,Arn:stateMachineArn}' --output json)
    
    # Look for Lambda functions
    LAMBDA_FUNCTIONS=$(aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `EvaluateModel-`)].FunctionName' --output text)
    
    # Look for IAM roles
    SAGEMAKER_ROLES=$(aws iam list-roles --query 'Roles[?starts_with(RoleName, `SageMakerMLPipelineRole-`)].RoleName' --output text)
    STEP_FUNCTIONS_ROLES=$(aws iam list-roles --query 'Roles[?starts_with(RoleName, `StepFunctionsMLRole-`)].RoleName' --output text)
    LAMBDA_ROLES=$(aws iam list-roles --query 'Roles[?starts_with(RoleName, `LambdaEvaluateModelRole-`)].RoleName' --output text)
    
    # Look for custom policies
    CUSTOM_POLICIES=$(aws iam list-policies --scope Local --query 'Policies[?starts_with(PolicyName, `StepFunctionsSageMakerPolicy-`)].{Name:PolicyName,Arn:Arn}' --output json)
    
    # Look for SageMaker resources
    SAGEMAKER_ENDPOINTS=$(aws sagemaker list-endpoints --query 'Endpoints[?starts_with(EndpointName, `endpoint-`)].EndpointName' --output text)
    SAGEMAKER_MODELS=$(aws sagemaker list-models --query 'Models[?starts_with(ModelName, `model-`)].ModelName' --output text)
    SAGEMAKER_CONFIGS=$(aws sagemaker list-endpoint-configs --query 'EndpointConfigs[?starts_with(EndpointConfigName, `endpoint-config-`)].EndpointConfigName' --output text)
    
    # Display found resources
    info "Found the following ML pipeline resources:"
    info ""
    
    if [[ -n "$ML_BUCKETS" ]]; then
        info "S3 Buckets:"
        for bucket in $ML_BUCKETS; do
            info "  - $bucket"
        done
    fi
    
    if [[ "$STATE_MACHINES" != "[]" ]]; then
        info "Step Functions State Machines:"
        echo "$STATE_MACHINES" | jq -r '.[] | "  - " + .Name + " (" + .Arn + ")"'
    fi
    
    if [[ -n "$LAMBDA_FUNCTIONS" ]]; then
        info "Lambda Functions:"
        for func in $LAMBDA_FUNCTIONS; do
            info "  - $func"
        done
    fi
    
    if [[ -n "$SAGEMAKER_ENDPOINTS" ]]; then
        info "SageMaker Endpoints:"
        for endpoint in $SAGEMAKER_ENDPOINTS; do
            info "  - $endpoint"
        done
    fi
    
    if [[ -n "$SAGEMAKER_MODELS" ]]; then
        info "SageMaker Models:"
        for model in $SAGEMAKER_MODELS; do
            info "  - $model"
        done
    fi
    
    if [[ -n "$SAGEMAKER_CONFIGS" ]]; then
        info "SageMaker Endpoint Configs:"
        for config in $SAGEMAKER_CONFIGS; do
            info "  - $config"
        done
    fi
    
    if [[ -n "$SAGEMAKER_ROLES" ]]; then
        info "SageMaker IAM Roles:"
        for role in $SAGEMAKER_ROLES; do
            info "  - $role"
        done
    fi
    
    if [[ -n "$STEP_FUNCTIONS_ROLES" ]]; then
        info "Step Functions IAM Roles:"
        for role in $STEP_FUNCTIONS_ROLES; do
            info "  - $role"
        done
    fi
    
    if [[ -n "$LAMBDA_ROLES" ]]; then
        info "Lambda IAM Roles:"
        for role in $LAMBDA_ROLES; do
            info "  - $role"
        done
    fi
    
    if [[ "$CUSTOM_POLICIES" != "[]" ]]; then
        info "Custom IAM Policies:"
        echo "$CUSTOM_POLICIES" | jq -r '.[] | "  - " + .Name + " (" + .Arn + ")"'
    fi
    
    info ""
}

# Function to load deployment info from S3
load_deployment_info() {
    local bucket="$1"
    local temp_dir=$(mktemp -d)
    
    if aws s3 cp "s3://${bucket}/deployment-info/ml-pipeline-info.json" "${temp_dir}/ml-pipeline-info.json" &>/dev/null; then
        # Load variables from deployment info
        export RANDOM_SUFFIX=$(jq -r '.random_suffix' "${temp_dir}/ml-pipeline-info.json")
        export S3_BUCKET_NAME=$(jq -r '.s3_bucket_name' "${temp_dir}/ml-pipeline-info.json")
        export SAGEMAKER_ROLE_NAME=$(jq -r '.sagemaker_role_name' "${temp_dir}/ml-pipeline-info.json")
        export STEP_FUNCTIONS_ROLE_NAME=$(jq -r '.step_functions_role_name' "${temp_dir}/ml-pipeline-info.json")
        export LAMBDA_FUNCTION_NAME=$(jq -r '.lambda_function_name' "${temp_dir}/ml-pipeline-info.json")
        export LAMBDA_ROLE_NAME=$(jq -r '.lambda_role_name' "${temp_dir}/ml-pipeline-info.json")
        export ML_PIPELINE_NAME=$(jq -r '.ml_pipeline_name' "${temp_dir}/ml-pipeline-info.json")
        export STATE_MACHINE_ARN=$(jq -r '.state_machine_arn' "${temp_dir}/ml-pipeline-info.json")
        export STEP_FUNCTIONS_POLICY_NAME=$(jq -r '.step_functions_policy_name' "${temp_dir}/ml-pipeline-info.json")
        
        info "Loaded deployment information from S3"
        rm -rf "$temp_dir"
        return 0
    else
        rm -rf "$temp_dir"
        return 1
    fi
}

# Function to cleanup SageMaker resources
cleanup_sagemaker_resources() {
    log "Cleaning up SageMaker resources..."
    
    # Stop any running endpoints
    if [[ -n "$SAGEMAKER_ENDPOINTS" ]]; then
        for endpoint in $SAGEMAKER_ENDPOINTS; do
            info "Checking endpoint: $endpoint"
            ENDPOINT_STATUS=$(aws sagemaker describe-endpoint --endpoint-name "$endpoint" --query 'EndpointStatus' --output text 2>/dev/null || echo "NotFound")
            
            if [[ "$ENDPOINT_STATUS" == "InService" || "$ENDPOINT_STATUS" == "Creating" || "$ENDPOINT_STATUS" == "Updating" ]]; then
                if confirm_action "Delete SageMaker endpoint: $endpoint?"; then
                    aws sagemaker delete-endpoint --endpoint-name "$endpoint"
                    log "Deleted SageMaker endpoint: $endpoint"
                fi
            fi
        done
    fi
    
    # Delete endpoint configurations
    if [[ -n "$SAGEMAKER_CONFIGS" ]]; then
        for config in $SAGEMAKER_CONFIGS; do
            if confirm_action "Delete SageMaker endpoint config: $config?"; then
                aws sagemaker delete-endpoint-config --endpoint-config-name "$config" 2>/dev/null || warn "Failed to delete endpoint config: $config"
                log "Deleted SageMaker endpoint config: $config"
            fi
        done
    fi
    
    # Delete models
    if [[ -n "$SAGEMAKER_MODELS" ]]; then
        for model in $SAGEMAKER_MODELS; do
            if confirm_action "Delete SageMaker model: $model?"; then
                aws sagemaker delete-model --model-name "$model" 2>/dev/null || warn "Failed to delete model: $model"
                log "Deleted SageMaker model: $model"
            fi
        done
    fi
}

# Function to cleanup Step Functions resources
cleanup_step_functions_resources() {
    log "Cleaning up Step Functions resources..."
    
    if [[ "$STATE_MACHINES" != "[]" ]]; then
        echo "$STATE_MACHINES" | jq -r '.[] | .Arn' | while read -r state_machine_arn; do
            state_machine_name=$(echo "$state_machine_arn" | awk -F: '{print $NF}')
            if confirm_action "Delete Step Functions state machine: $state_machine_name?"; then
                # Stop any running executions first
                RUNNING_EXECUTIONS=$(aws stepfunctions list-executions --state-machine-arn "$state_machine_arn" --status-filter RUNNING --query 'executions[].executionArn' --output text)
                
                if [[ -n "$RUNNING_EXECUTIONS" ]]; then
                    for execution_arn in $RUNNING_EXECUTIONS; do
                        warn "Stopping running execution: $execution_arn"
                        aws stepfunctions stop-execution --execution-arn "$execution_arn" || warn "Failed to stop execution"
                    done
                    
                    # Wait a bit for executions to stop
                    sleep 10
                fi
                
                aws stepfunctions delete-state-machine --state-machine-arn "$state_machine_arn"
                log "Deleted Step Functions state machine: $state_machine_name"
            fi
        done
    fi
}

# Function to cleanup Lambda resources
cleanup_lambda_resources() {
    log "Cleaning up Lambda resources..."
    
    if [[ -n "$LAMBDA_FUNCTIONS" ]]; then
        for func in $LAMBDA_FUNCTIONS; do
            if confirm_action "Delete Lambda function: $func?"; then
                aws lambda delete-function --function-name "$func"
                log "Deleted Lambda function: $func"
            fi
        done
    fi
}

# Function to cleanup IAM resources
cleanup_iam_resources() {
    log "Cleaning up IAM resources..."
    
    # Cleanup custom policies first
    if [[ "$CUSTOM_POLICIES" != "[]" ]]; then
        echo "$CUSTOM_POLICIES" | jq -r '.[] | .Name + " " + .Arn' | while read -r policy_name policy_arn; do
            if confirm_action "Delete IAM policy: $policy_name?"; then
                # Detach policy from all roles first
                ATTACHED_ROLES=$(aws iam list-entities-for-policy --policy-arn "$policy_arn" --query 'PolicyRoles[].RoleName' --output text)
                
                if [[ -n "$ATTACHED_ROLES" ]]; then
                    for role in $ATTACHED_ROLES; do
                        aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn"
                        log "Detached policy $policy_name from role $role"
                    done
                fi
                
                aws iam delete-policy --policy-arn "$policy_arn"
                log "Deleted IAM policy: $policy_name"
            fi
        done
    fi
    
    # Cleanup SageMaker roles
    if [[ -n "$SAGEMAKER_ROLES" ]]; then
        for role in $SAGEMAKER_ROLES; do
            if confirm_action "Delete SageMaker IAM role: $role?"; then
                # Detach all policies
                ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text)
                
                if [[ -n "$ATTACHED_POLICIES" ]]; then
                    for policy_arn in $ATTACHED_POLICIES; do
                        aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn"
                    done
                fi
                
                aws iam delete-role --role-name "$role"
                log "Deleted SageMaker IAM role: $role"
            fi
        done
    fi
    
    # Cleanup Step Functions roles
    if [[ -n "$STEP_FUNCTIONS_ROLES" ]]; then
        for role in $STEP_FUNCTIONS_ROLES; do
            if confirm_action "Delete Step Functions IAM role: $role?"; then
                # Detach all policies
                ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text)
                
                if [[ -n "$ATTACHED_POLICIES" ]]; then
                    for policy_arn in $ATTACHED_POLICIES; do
                        aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn"
                    done
                fi
                
                aws iam delete-role --role-name "$role"
                log "Deleted Step Functions IAM role: $role"
            fi
        done
    fi
    
    # Cleanup Lambda roles
    if [[ -n "$LAMBDA_ROLES" ]]; then
        for role in $LAMBDA_ROLES; do
            if confirm_action "Delete Lambda IAM role: $role?"; then
                # Detach all policies
                ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text)
                
                if [[ -n "$ATTACHED_POLICIES" ]]; then
                    for policy_arn in $ATTACHED_POLICIES; do
                        aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn"
                    done
                fi
                
                aws iam delete-role --role-name "$role"
                log "Deleted Lambda IAM role: $role"
            fi
        done
    fi
}

# Function to cleanup S3 resources
cleanup_s3_resources() {
    log "Cleaning up S3 resources..."
    
    if [[ -n "$ML_BUCKETS" ]]; then
        for bucket in $ML_BUCKETS; do
            if confirm_action "Delete S3 bucket and all contents: $bucket?"; then
                # Delete all objects in bucket
                aws s3 rm "s3://$bucket" --recursive 2>/dev/null || warn "Failed to delete some objects in bucket: $bucket"
                
                # Delete all object versions and delete markers (for versioned buckets)
                aws s3api delete-objects --bucket "$bucket" --delete "$(aws s3api list-object-versions --bucket "$bucket" --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)" 2>/dev/null || true
                aws s3api delete-objects --bucket "$bucket" --delete "$(aws s3api list-object-versions --bucket "$bucket" --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json)" 2>/dev/null || true
                
                # Delete bucket
                aws s3 rb "s3://$bucket" --force
                log "Deleted S3 bucket: $bucket"
            fi
        done
    fi
}

# Function to cleanup training/processing jobs
cleanup_sagemaker_jobs() {
    log "Checking for running SageMaker jobs..."
    
    # List processing jobs
    PROCESSING_JOBS=$(aws sagemaker list-processing-jobs --status-equals InProgress --query 'ProcessingJobSummaries[?starts_with(ProcessingJobName, `preprocessing-`)].ProcessingJobName' --output text)
    
    if [[ -n "$PROCESSING_JOBS" ]]; then
        for job in $PROCESSING_JOBS; do
            if confirm_action "Stop processing job: $job?"; then
                aws sagemaker stop-processing-job --processing-job-name "$job"
                log "Stopped processing job: $job"
            fi
        done
    fi
    
    # List training jobs
    TRAINING_JOBS=$(aws sagemaker list-training-jobs --status-equals InProgress --query 'TrainingJobSummaries[?starts_with(TrainingJobName, `training-`)].TrainingJobName' --output text)
    
    if [[ -n "$TRAINING_JOBS" ]]; then
        for job in $TRAINING_JOBS; do
            if confirm_action "Stop training job: $job?"; then
                aws sagemaker stop-training-job --training-job-name "$job"
                log "Stopped training job: $job"
            fi
        done
    fi
}

# Main cleanup function
main() {
    log "Starting ML Pipeline cleanup..."
    
    # Find all ML pipeline resources
    find_ml_resources
    
    # Check if any resources were found
    if [[ -z "$ML_BUCKETS" && "$STATE_MACHINES" == "[]" && -z "$LAMBDA_FUNCTIONS" && -z "$SAGEMAKER_ROLES" && -z "$STEP_FUNCTIONS_ROLES" && -z "$LAMBDA_ROLES" && "$CUSTOM_POLICIES" == "[]" && -z "$SAGEMAKER_ENDPOINTS" && -z "$SAGEMAKER_MODELS" && -z "$SAGEMAKER_CONFIGS" ]]; then
        info "No ML pipeline resources found to cleanup."
        exit 0
    fi
    
    # Try to load deployment info from the first bucket found
    if [[ -n "$ML_BUCKETS" ]]; then
        FIRST_BUCKET=$(echo "$ML_BUCKETS" | head -n1)
        load_deployment_info "$FIRST_BUCKET" || warn "Could not load deployment info from S3"
    fi
    
    # Confirm cleanup
    if ! confirm_action "Are you sure you want to delete all these resources? This action cannot be undone."; then
        info "Cleanup cancelled."
        exit 0
    fi
    
    # Stop any running jobs first
    cleanup_sagemaker_jobs
    
    # Cleanup in reverse order of creation
    cleanup_sagemaker_resources
    cleanup_step_functions_resources
    cleanup_lambda_resources
    cleanup_iam_resources
    cleanup_s3_resources
    
    log "✅ ML Pipeline cleanup completed successfully!"
    info ""
    info "All ML pipeline resources have been removed."
    info "Please verify in the AWS Console that all resources are deleted."
    info ""
    warn "Note: Some resources may take a few minutes to fully delete."
    warn "Check CloudFormation stacks if you used infrastructure as code deployment."
}

# Show usage if help requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "ML Pipeline Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -y, --yes    Skip confirmation prompts"
    echo "  -h, --help   Show this help message"
    echo ""
    echo "This script will:"
    echo "  1. Find all ML pipeline resources in your AWS account"
    echo "  2. Stop any running SageMaker jobs"
    echo "  3. Delete SageMaker endpoints, models, and configurations"
    echo "  4. Delete Step Functions state machines"
    echo "  5. Delete Lambda functions"
    echo "  6. Delete IAM roles and policies"
    echo "  7. Delete S3 buckets and all contents"
    echo ""
    echo "CAUTION: This is a destructive operation that cannot be undone."
    echo "Make sure you have backups of any important data before running."
    exit 0
fi

# Run main function
main