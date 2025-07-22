#!/bin/bash

# Automated Video Workflow Orchestration with Step Functions - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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

# Error handling function
handle_error() {
    log_error "Cleanup failed at line $1"
    log_error "Command that failed: $2"
    log_warning "Some resources may not have been cleaned up. Please check manually."
    exit 1
}

trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# Function to load configuration
load_configuration() {
    log_info "Loading deployment configuration..."
    
    if [[ -f "deployment-config.env" ]]; then
        source deployment-config.env
        log_success "Configuration loaded from deployment-config.env"
    else
        log_error "deployment-config.env not found!"
        log_error "This file is required for cleanup. Please ensure you're running this script"
        log_error "from the same directory where deploy.sh was executed."
        exit 1
    fi
    
    # Verify required variables
    required_vars=(
        "AWS_REGION"
        "RANDOM_SUFFIX"
        "SOURCE_BUCKET"
        "OUTPUT_BUCKET"
        "ARCHIVE_BUCKET"
        "JOBS_TABLE"
        "SNS_TOPIC"
        "WORKFLOW_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var is not set in configuration"
            exit 1
        fi
    done
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo "================================================================"
    log_warning "WARNING: DESTRUCTIVE OPERATION"
    echo "================================================================"
    echo ""
    echo "This will permanently delete the following resources:"
    echo ""
    echo "🗂️  S3 Buckets:"
    echo "   - ${SOURCE_BUCKET} (and all contents)"
    echo "   - ${OUTPUT_BUCKET} (and all contents)"
    echo "   - ${ARCHIVE_BUCKET} (and all contents)"
    echo ""
    echo "🗃️  DynamoDB Table:"
    echo "   - ${JOBS_TABLE} (and all data)"
    echo ""
    echo "⚡ Lambda Functions:"
    echo "   - video-metadata-extractor-${RANDOM_SUFFIX}"
    echo "   - video-quality-control-${RANDOM_SUFFIX}"
    echo "   - video-publisher-${RANDOM_SUFFIX}"
    echo "   - video-workflow-trigger-${RANDOM_SUFFIX}"
    echo ""
    echo "🔄 Step Functions:"
    echo "   - ${WORKFLOW_NAME}"
    echo ""
    echo "🔐 IAM Roles and Policies"
    echo "🌐 API Gateway"
    echo "📊 CloudWatch Dashboard"
    echo "📢 SNS Topic"
    echo ""
    echo "================================================================"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log_warning "Starting cleanup in 5 seconds... Press Ctrl+C to cancel"
    sleep 5
}

# Function to remove S3 event notifications first
remove_s3_notifications() {
    log_info "Removing S3 event notifications..."
    
    # Clear S3 bucket notifications
    aws s3api put-bucket-notification-configuration \
        --bucket "${SOURCE_BUCKET}" \
        --notification-configuration '{}' \
        --region "${AWS_REGION}" || log_warning "Failed to clear S3 notifications"
    
    log_success "S3 event notifications removed"
}

# Function to delete Step Functions state machine
delete_step_functions() {
    log_info "Deleting Step Functions state machine..."
    
    if [[ -n "${STATE_MACHINE_ARN:-}" ]]; then
        # Stop any running executions first
        log_info "Checking for running executions..."
        running_executions=$(aws stepfunctions list-executions \
            --state-machine-arn "${STATE_MACHINE_ARN}" \
            --status-filter RUNNING \
            --query 'executions[].executionArn' \
            --output text \
            --region "${AWS_REGION}" 2>/dev/null || echo "")
        
        if [[ -n "$running_executions" ]]; then
            log_warning "Found running executions. Stopping them..."
            for execution in $running_executions; do
                aws stepfunctions stop-execution \
                    --execution-arn "$execution" \
                    --region "${AWS_REGION}" || log_warning "Failed to stop execution: $execution"
            done
            sleep 5
        fi
        
        # Delete the state machine
        aws stepfunctions delete-state-machine \
            --state-machine-arn "${STATE_MACHINE_ARN}" \
            --region "${AWS_REGION}" || log_warning "Failed to delete state machine"
        
        log_success "Step Functions state machine deleted"
    else
        log_warning "STATE_MACHINE_ARN not found in configuration"
    fi
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log_info "Deleting Lambda functions..."
    
    lambda_functions=(
        "video-metadata-extractor-${RANDOM_SUFFIX}"
        "video-quality-control-${RANDOM_SUFFIX}"
        "video-publisher-${RANDOM_SUFFIX}"
        "video-workflow-trigger-${RANDOM_SUFFIX}"
    )
    
    for function_name in "${lambda_functions[@]}"; do
        log_info "Deleting Lambda function: $function_name"
        aws lambda delete-function \
            --function-name "$function_name" \
            --region "${AWS_REGION}" || log_warning "Failed to delete function: $function_name"
    done
    
    log_success "Lambda functions deleted"
}

# Function to delete API Gateway
delete_api_gateway() {
    log_info "Deleting API Gateway..."
    
    if [[ -n "${API_ID:-}" ]]; then
        aws apigatewayv2 delete-api \
            --api-id "${API_ID}" \
            --region "${AWS_REGION}" || log_warning "Failed to delete API Gateway"
        
        log_success "API Gateway deleted"
    else
        log_warning "API_ID not found in configuration"
    fi
}

# Function to delete IAM roles and policies
delete_iam_roles() {
    log_info "Deleting IAM roles and policies..."
    
    # Delete Step Functions role
    if [[ -n "${STEPFUNCTIONS_ROLE_NAME:-}" ]]; then
        log_info "Deleting Step Functions role: ${STEPFUNCTIONS_ROLE_NAME}"
        
        # Delete inline policies first
        aws iam delete-role-policy \
            --role-name "${STEPFUNCTIONS_ROLE_NAME}" \
            --policy-name VideoWorkflowStepFunctionsPolicy \
            --region "${AWS_REGION}" || log_warning "Failed to delete Step Functions policy"
        
        # Delete the role
        aws iam delete-role \
            --role-name "${STEPFUNCTIONS_ROLE_NAME}" \
            --region "${AWS_REGION}" || log_warning "Failed to delete Step Functions role"
    fi
    
    # Delete Lambda role
    if [[ -n "${LAMBDA_ROLE_NAME:-}" ]]; then
        log_info "Deleting Lambda role: ${LAMBDA_ROLE_NAME}"
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-name VideoWorkflowPolicy \
            --region "${AWS_REGION}" || log_warning "Failed to delete Lambda policy"
        
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
            --region "${AWS_REGION}" || log_warning "Failed to detach Lambda basic execution policy"
        
        # Delete the role
        aws iam delete-role \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --region "${AWS_REGION}" || log_warning "Failed to delete Lambda role"
    fi
    
    # Delete MediaConvert role
    if [[ -n "${MEDIACONVERT_ROLE:-}" ]]; then
        log_info "Deleting MediaConvert role: ${MEDIACONVERT_ROLE}"
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "${MEDIACONVERT_ROLE}" \
            --policy-name MediaConvertWorkflowPolicy \
            --region "${AWS_REGION}" || log_warning "Failed to delete MediaConvert policy"
        
        # Delete the role
        aws iam delete-role \
            --role-name "${MEDIACONVERT_ROLE}" \
            --region "${AWS_REGION}" || log_warning "Failed to delete MediaConvert role"
    fi
    
    log_success "IAM roles and policies deleted"
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log_info "Deleting CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    if [[ -n "${DASHBOARD_NAME:-}" ]]; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "${DASHBOARD_NAME}" \
            --region "${AWS_REGION}" || log_warning "Failed to delete CloudWatch dashboard"
    fi
    
    # Delete CloudWatch log group
    aws logs delete-log-group \
        --log-group-name "/aws/stepfunctions/${WORKFLOW_NAME}" \
        --region "${AWS_REGION}" || log_warning "Failed to delete CloudWatch log group"
    
    log_success "CloudWatch resources deleted"
}

# Function to delete SNS topic
delete_sns_topic() {
    log_info "Deleting SNS topic..."
    
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        aws sns delete-topic \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --region "${AWS_REGION}" || log_warning "Failed to delete SNS topic"
        
        log_success "SNS topic deleted"
    else
        log_warning "SNS_TOPIC_ARN not found in configuration"
    fi
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    log_info "Deleting DynamoDB table..."
    
    aws dynamodb delete-table \
        --table-name "${JOBS_TABLE}" \
        --region "${AWS_REGION}" || log_warning "Failed to delete DynamoDB table"
    
    # Wait for table deletion
    log_info "Waiting for DynamoDB table deletion to complete..."
    aws dynamodb wait table-not-exists \
        --table-name "${JOBS_TABLE}" \
        --region "${AWS_REGION}" || log_warning "Table deletion wait timed out"
    
    log_success "DynamoDB table deleted"
}

# Function to empty and delete S3 buckets
delete_s3_buckets() {
    log_info "Deleting S3 buckets and contents..."
    
    buckets=("${SOURCE_BUCKET}" "${OUTPUT_BUCKET}" "${ARCHIVE_BUCKET}")
    
    for bucket in "${buckets[@]}"; do
        log_info "Processing bucket: $bucket"
        
        # Check if bucket exists
        if aws s3api head-bucket --bucket "$bucket" --region "${AWS_REGION}" 2>/dev/null; then
            # Remove all objects including versions
            log_info "Emptying bucket: $bucket"
            aws s3 rm "s3://$bucket" --recursive \
                --region "${AWS_REGION}" || log_warning "Failed to empty bucket: $bucket"
            
            # Remove versioned objects if versioning is enabled
            log_info "Removing versioned objects from: $bucket"
            aws s3api delete-objects \
                --bucket "$bucket" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$bucket" \
                    --output json \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                    --region "${AWS_REGION}" 2>/dev/null || echo '{}')" \
                --region "${AWS_REGION}" 2>/dev/null || true
            
            # Remove delete markers
            aws s3api delete-objects \
                --bucket "$bucket" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$bucket" \
                    --output json \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                    --region "${AWS_REGION}" 2>/dev/null || echo '{}')" \
                --region "${AWS_REGION}" 2>/dev/null || true
            
            # Delete the bucket
            log_info "Deleting bucket: $bucket"
            aws s3 rb "s3://$bucket" --region "${AWS_REGION}" || log_warning "Failed to delete bucket: $bucket"
        else
            log_warning "Bucket $bucket does not exist or is not accessible"
        fi
    done
    
    log_success "S3 buckets deleted"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local cleanup_issues=0
    
    # Check S3 buckets
    for bucket in "${SOURCE_BUCKET}" "${OUTPUT_BUCKET}" "${ARCHIVE_BUCKET}"; do
        if aws s3api head-bucket --bucket "$bucket" --region "${AWS_REGION}" 2>/dev/null; then
            log_warning "Bucket $bucket still exists"
            ((cleanup_issues++))
        fi
    done
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "${JOBS_TABLE}" --region "${AWS_REGION}" 2>/dev/null; then
        log_warning "DynamoDB table ${JOBS_TABLE} still exists"
        ((cleanup_issues++))
    fi
    
    # Check Lambda functions
    lambda_functions=(
        "video-metadata-extractor-${RANDOM_SUFFIX}"
        "video-quality-control-${RANDOM_SUFFIX}"
        "video-publisher-${RANDOM_SUFFIX}"
        "video-workflow-trigger-${RANDOM_SUFFIX}"
    )
    
    for function_name in "${lambda_functions[@]}"; do
        if aws lambda get-function --function-name "$function_name" --region "${AWS_REGION}" 2>/dev/null; then
            log_warning "Lambda function $function_name still exists"
            ((cleanup_issues++))
        fi
    done
    
    # Check Step Functions
    if [[ -n "${STATE_MACHINE_ARN:-}" ]]; then
        if aws stepfunctions describe-state-machine --state-machine-arn "${STATE_MACHINE_ARN}" --region "${AWS_REGION}" 2>/dev/null; then
            log_warning "Step Functions state machine still exists"
            ((cleanup_issues++))
        fi
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "Cleanup verification completed successfully"
        return 0
    else
        log_warning "Found $cleanup_issues cleanup issues that may require manual intervention"
        return 1
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # List of files to clean up
    local_files=(
        "deployment-config.env"
        "*.json"
        "*.py"
        "*.zip"
    )
    
    for pattern in "${local_files[@]}"; do
        if ls $pattern 1> /dev/null 2>&1; then
            log_info "Removing local files matching: $pattern"
            rm -f $pattern
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "================================================================"
    log_success "VIDEO WORKFLOW ORCHESTRATION CLEANUP COMPLETED"
    echo "================================================================"
    echo ""
    echo "The following resources have been deleted:"
    echo ""
    echo "✅ S3 Buckets and contents"
    echo "✅ DynamoDB table and data"
    echo "✅ Lambda functions"
    echo "✅ Step Functions state machine"
    echo "✅ IAM roles and policies"
    echo "✅ API Gateway"
    echo "✅ SNS topic"
    echo "✅ CloudWatch dashboard and logs"
    echo "✅ Local configuration files"
    echo ""
    echo "📋 IMPORTANT NOTES:"
    echo "• All video processing data has been permanently deleted"
    echo "• IAM roles and policies have been removed"
    echo "• No ongoing charges should occur from these resources"
    echo "• If you encounter any remaining resources, check the AWS console"
    echo ""
    echo "================================================================"
}

# Function to handle partial cleanup
handle_partial_cleanup() {
    log_warning "Some resources may not have been fully cleaned up."
    echo ""
    echo "Manual cleanup may be required for:"
    echo "• Resources that failed to delete due to dependencies"
    echo "• Resources created outside of this script"
    echo "• Resources in different regions"
    echo ""
    echo "Please check the AWS console for any remaining resources with suffix: ${RANDOM_SUFFIX}"
}

# Main cleanup function
main() {
    log_info "Starting video workflow orchestration cleanup..."
    
    # Load configuration
    load_configuration
    
    # Confirm destruction
    confirm_destruction
    
    # Perform cleanup in reverse order of creation
    log_info "Beginning cleanup process..."
    
    # Remove dependencies first
    remove_s3_notifications
    
    # Delete core services
    delete_step_functions
    delete_lambda_functions
    delete_api_gateway
    
    # Delete storage and data
    delete_cloudwatch_resources
    delete_sns_topic
    delete_dynamodb_table
    delete_s3_buckets
    
    # Delete access controls last
    delete_iam_roles
    
    # Verify cleanup
    if verify_cleanup; then
        cleanup_local_files
        display_cleanup_summary
        log_success "Cleanup completed successfully!"
    else
        handle_partial_cleanup
        log_warning "Cleanup completed with some issues. Please review the warnings above."
        exit 1
    fi
}

# Help function
show_help() {
    echo "Video Workflow Orchestration Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -f, --force    Skip confirmation prompt (use with caution)"
    echo ""
    echo "This script will delete all resources created by deploy.sh"
    echo "Make sure deployment-config.env exists in the current directory"
}

# Parse command line arguments
FORCE_CLEANUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE_CLEANUP=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Override confirmation if force flag is set
if [[ "$FORCE_CLEANUP" == "true" ]]; then
    confirm_destruction() {
        log_warning "Force cleanup enabled - skipping confirmation"
    }
fi

# Check if script is being run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi