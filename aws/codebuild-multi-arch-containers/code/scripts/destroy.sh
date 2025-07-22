#!/bin/bash
# Cleanup script for Multi-Architecture Container Images with CodeBuild
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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI not configured or authentication failed"
        log_info "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS authentication
    check_aws_auth
    
    log_success "Prerequisites check passed"
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Check if .env file exists
    if [ ! -f ".env" ]; then
        log_error ".env file not found. Cannot determine resources to clean up."
        log_info "Please ensure you're running this script from the same directory as the deploy script."
        exit 1
    fi
    
    # Source the environment file
    source .env
    
    # Verify required variables are set
    if [ -z "${PROJECT_NAME:-}" ] || [ -z "${ECR_REPO_NAME:-}" ] || [ -z "${CODEBUILD_ROLE_NAME:-}" ]; then
        log_error "Required environment variables not found in .env file"
        exit 1
    fi
    
    log_success "Environment variables loaded"
    log_info "Project Name: ${PROJECT_NAME}"
    log_info "ECR Repository: ${ECR_REPO_NAME}"
    log_info "AWS Region: ${AWS_REGION}"
}

# Function to confirm deletion
confirm_deletion() {
    log_warning "This will permanently delete the following resources:"
    echo "  - ECR Repository: ${ECR_REPO_NAME}"
    echo "  - CodeBuild Project: ${PROJECT_NAME}"
    echo "  - IAM Role: ${CODEBUILD_ROLE_NAME}"
    echo "  - S3 Bucket: ${PROJECT_NAME}-source"
    echo "  - All container images in ECR"
    echo "  - All build logs in CloudWatch"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with cleanup..."
}

# Function to stop any running builds
stop_running_builds() {
    log_info "Checking for running builds..."
    
    # Get list of running builds for this project
    RUNNING_BUILDS=$(aws codebuild list-builds-for-project \
        --project-name "${PROJECT_NAME}" \
        --region "${AWS_REGION}" \
        --query 'ids' --output text 2>/dev/null || echo "")
    
    if [ -n "$RUNNING_BUILDS" ] && [ "$RUNNING_BUILDS" != "None" ]; then
        log_info "Found running builds. Stopping them..."
        
        for BUILD_ID in $RUNNING_BUILDS; do
            BUILD_STATUS=$(aws codebuild batch-get-builds \
                --ids "$BUILD_ID" \
                --region "${AWS_REGION}" \
                --query 'builds[0].buildStatus' --output text)
            
            if [ "$BUILD_STATUS" = "IN_PROGRESS" ]; then
                log_info "Stopping build: $BUILD_ID"
                aws codebuild stop-build \
                    --id "$BUILD_ID" \
                    --region "${AWS_REGION}" >/dev/null 2>&1 || true
            fi
        done
        
        log_success "Stopped running builds"
    else
        log_info "No running builds found"
    fi
}

# Function to delete CodeBuild project
delete_codebuild_project() {
    log_info "Deleting CodeBuild project..."
    
    # Check if project exists
    if aws codebuild batch-get-projects --names "${PROJECT_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        # Delete CodeBuild project
        aws codebuild delete-project \
            --name "${PROJECT_NAME}" \
            --region "${AWS_REGION}"
        
        log_success "Deleted CodeBuild project: ${PROJECT_NAME}"
    else
        log_warning "CodeBuild project ${PROJECT_NAME} not found"
    fi
}

# Function to delete ECR repository
delete_ecr_repository() {
    log_info "Deleting ECR repository..."
    
    # Check if repository exists
    if aws ecr describe-repositories --repository-names "${ECR_REPO_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        # Delete ECR repository and all images
        aws ecr delete-repository \
            --repository-name "${ECR_REPO_NAME}" \
            --region "${AWS_REGION}" \
            --force
        
        log_success "Deleted ECR repository: ${ECR_REPO_NAME}"
    else
        log_warning "ECR repository ${ECR_REPO_NAME} not found"
    fi
}

# Function to delete IAM role
delete_iam_role() {
    log_info "Deleting IAM role..."
    
    # Check if role exists
    if aws iam get-role --role-name "${CODEBUILD_ROLE_NAME}" >/dev/null 2>&1; then
        # Delete IAM role policy first
        aws iam delete-role-policy \
            --role-name "${CODEBUILD_ROLE_NAME}" \
            --policy-name "CodeBuildMultiArchPolicy" 2>/dev/null || true
        
        # Delete IAM role
        aws iam delete-role --role-name "${CODEBUILD_ROLE_NAME}"
        
        log_success "Deleted IAM role: ${CODEBUILD_ROLE_NAME}"
    else
        log_warning "IAM role ${CODEBUILD_ROLE_NAME} not found"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log_info "Deleting S3 bucket..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "${PROJECT_NAME}-source" --region "${AWS_REGION}" >/dev/null 2>&1; then
        # Delete S3 bucket and all contents
        aws s3 rm "s3://${PROJECT_NAME}-source" --recursive --region "${AWS_REGION}" 2>/dev/null || true
        aws s3 rb "s3://${PROJECT_NAME}-source" --region "${AWS_REGION}"
        
        log_success "Deleted S3 bucket: ${PROJECT_NAME}-source"
    else
        log_warning "S3 bucket ${PROJECT_NAME}-source not found"
    fi
}

# Function to delete CloudWatch log groups
delete_cloudwatch_logs() {
    log_info "Deleting CloudWatch log groups..."
    
    # Delete CodeBuild log group
    LOG_GROUP_NAME="/aws/codebuild/${PROJECT_NAME}"
    
    if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --region "${AWS_REGION}" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${LOG_GROUP_NAME}"; then
        aws logs delete-log-group \
            --log-group-name "${LOG_GROUP_NAME}" \
            --region "${AWS_REGION}" 2>/dev/null || true
        
        log_success "Deleted CloudWatch log group: ${LOG_GROUP_NAME}"
    else
        log_warning "CloudWatch log group ${LOG_GROUP_NAME} not found"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove sample application directory
    if [ -d "sample-app" ]; then
        rm -rf sample-app
        log_success "Removed sample-app directory"
    fi
    
    # Remove temporary files
    rm -f trust-policy.json codebuild-policy.json codebuild-project.json source.zip
    
    # Remove environment file
    if [ -f ".env" ]; then
        rm -f .env
        log_success "Removed .env file"
    fi
    
    # Remove any Docker images that might have been pulled
    if command_exists docker; then
        # Remove any locally pulled images (ignore errors)
        if [ -n "${ECR_REPO_URI:-}" ]; then
            docker rmi "${ECR_REPO_URI}:latest" 2>/dev/null || true
        fi
    fi
    
    log_success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local cleanup_errors=0
    
    # Check CodeBuild project
    if aws codebuild batch-get-projects --names "${PROJECT_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_error "CodeBuild project ${PROJECT_NAME} still exists"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check ECR repository
    if aws ecr describe-repositories --repository-names "${ECR_REPO_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_error "ECR repository ${ECR_REPO_NAME} still exists"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${CODEBUILD_ROLE_NAME}" >/dev/null 2>&1; then
        log_error "IAM role ${CODEBUILD_ROLE_NAME} still exists"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "${PROJECT_NAME}-source" --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_error "S3 bucket ${PROJECT_NAME}-source still exists"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    if [ $cleanup_errors -eq 0 ]; then
        log_success "All resources successfully cleaned up"
    else
        log_error "Some resources may not have been cleaned up completely"
        log_info "Please check the AWS console and manually delete any remaining resources"
        exit 1
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    log_success "=================================="
    log_success "CLEANUP COMPLETED SUCCESSFULLY"
    log_success "=================================="
    echo
    log_info "Deleted Resources:"
    echo "  - CodeBuild Project: ${PROJECT_NAME}"
    echo "  - ECR Repository: ${ECR_REPO_NAME}"
    echo "  - IAM Role: ${CODEBUILD_ROLE_NAME}"
    echo "  - S3 Bucket: ${PROJECT_NAME}-source"
    echo "  - CloudWatch Log Groups"
    echo "  - Local application files"
    echo
    log_info "All multi-architecture container build resources have been removed"
    log_info "No further AWS charges will be incurred for these resources"
}

# Function to handle cleanup errors
handle_cleanup_error() {
    local error_message="$1"
    log_error "Cleanup failed: $error_message"
    log_info "Some resources may still exist. Please check the AWS console."
    log_info "You may need to manually delete remaining resources to avoid charges."
    exit 1
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local check_command="$2"
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    log_info "Waiting for ${resource_type} deletion to complete..."
    
    while [ $wait_time -lt $max_wait ]; do
        if ! eval "$check_command" >/dev/null 2>&1; then
            log_success "${resource_type} deletion completed"
            return 0
        fi
        
        sleep 10
        wait_time=$((wait_time + 10))
        log_info "Still waiting for ${resource_type} deletion... (${wait_time}s)"
    done
    
    log_warning "${resource_type} deletion taking longer than expected"
    return 1
}

# Main cleanup function
main() {
    log_info "Starting multi-architecture container image cleanup..."
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_deletion
    stop_running_builds
    delete_codebuild_project
    delete_ecr_repository
    delete_iam_role
    delete_s3_bucket
    delete_cloudwatch_logs
    cleanup_local_files
    verify_cleanup
    show_cleanup_summary
}

# Trap errors and provide helpful information
trap 'handle_cleanup_error "An unexpected error occurred during cleanup"' ERR

# Run main function
main "$@"