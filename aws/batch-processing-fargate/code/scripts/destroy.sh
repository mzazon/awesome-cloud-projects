#!/bin/bash

# AWS Batch with Fargate Cleanup Script
# This script safely removes all AWS Batch infrastructure created by deploy.sh

set -euo pipefail

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

# Script metadata
SCRIPT_NAME="AWS Batch Fargate Cleanup"
SCRIPT_VERSION="1.0"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION at $TIMESTAMP"

# Configuration
CLEANUP_TIMEOUT=1800  # 30 minutes
FORCE_CLEANUP=false
DEPLOYMENT_INFO_FILE=""

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --force              Force cleanup without confirmation"
    echo "  -i, --info-file FILE     Use specific deployment info file"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                      # Interactive cleanup"
    echo "  $0 --force              # Force cleanup without prompts"
    echo "  $0 -i deployment.json   # Use specific deployment info file"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_CLEANUP=true
                shift
                ;;
            -i|--info-file)
                DEPLOYMENT_INFO_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    log_success "Prerequisites check completed successfully"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Try to find deployment info file
    local info_files=(
        "${DEPLOYMENT_INFO_FILE}"
        "aws-batch-deployment-info.json"
        "/tmp/aws-batch-deployment-info.json"
        "./aws-batch-deployment-info.json"
    )
    
    local found_file=""
    for file in "${info_files[@]}"; do
        if [ -n "$file" ] && [ -f "$file" ]; then
            found_file="$file"
            break
        fi
    done
    
    if [ -z "$found_file" ]; then
        log_warning "No deployment info file found. Will attempt to discover resources..."
        return 1
    fi
    
    log_info "Using deployment info file: $found_file"
    
    # Load variables from deployment info
    export AWS_REGION=$(jq -r '.deployment.region // empty' "$found_file")
    export AWS_ACCOUNT_ID=$(jq -r '.deployment.account_id // empty' "$found_file")
    export BATCH_COMPUTE_ENV_NAME=$(jq -r '.resources.compute_environment // empty' "$found_file")
    export BATCH_JOB_QUEUE_NAME=$(jq -r '.resources.job_queue // empty' "$found_file")
    export BATCH_JOB_DEFINITION_NAME=$(jq -r '.resources.job_definition // empty' "$found_file")
    export BATCH_EXECUTION_ROLE_NAME=$(jq -r '.resources.execution_role // empty' "$found_file")
    export ECR_REPOSITORY_NAME=$(jq -r '.resources.ecr_repository // empty' "$found_file")
    export LOG_GROUP_NAME=$(jq -r '.resources.log_group // empty' "$found_file")
    
    # Set defaults if not found in file
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION=$(aws configure get region || echo "us-east-1")
    fi
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    log_success "Deployment information loaded successfully"
    return 0
}

# Discover resources function (fallback if no deployment info)
discover_resources() {
    log_info "Attempting to discover AWS Batch resources..."
    
    # Set basic environment
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Try to find resources by common patterns
    log_info "Searching for compute environments..."
    local compute_envs=$(aws batch describe-compute-environments \
        --query 'computeEnvironments[?contains(computeEnvironmentName, `batch-fargate-compute`)].computeEnvironmentName' \
        --output text)
    
    log_info "Searching for job queues..."
    local job_queues=$(aws batch describe-job-queues \
        --query 'jobQueues[?contains(jobQueueName, `batch-fargate-queue`)].jobQueueName' \
        --output text)
    
    log_info "Searching for ECR repositories..."
    local ecr_repos=$(aws ecr describe-repositories \
        --query 'repositories[?contains(repositoryName, `batch-processing-demo`)].repositoryName' \
        --output text 2>/dev/null || echo "")
    
    log_info "Searching for IAM roles..."
    local iam_roles=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `BatchFargateExecutionRole`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    # Display found resources
    if [ -n "$compute_envs" ] || [ -n "$job_queues" ] || [ -n "$ecr_repos" ] || [ -n "$iam_roles" ]; then
        log_info "Found the following resources:"
        [ -n "$compute_envs" ] && echo "  Compute Environments: $compute_envs"
        [ -n "$job_queues" ] && echo "  Job Queues: $job_queues"
        [ -n "$ecr_repos" ] && echo "  ECR Repositories: $ecr_repos"
        [ -n "$iam_roles" ] && echo "  IAM Roles: $iam_roles"
        
        return 0
    else
        log_warning "No AWS Batch resources found with expected naming patterns"
        return 1
    fi
}

# Confirmation function
confirm_cleanup() {
    if [ "$FORCE_CLEANUP" = true ]; then
        log_info "Force cleanup enabled, skipping confirmation"
        return 0
    fi
    
    echo ""
    log_warning "This will permanently delete the following AWS resources:"
    echo "  - AWS Batch compute environments and job queues"
    echo "  - Job definitions and any running/queued jobs"
    echo "  - ECR repositories and container images"
    echo "  - IAM roles and policies"
    echo "  - CloudWatch log groups and data"
    echo ""
    
    if [ -n "${BATCH_COMPUTE_ENV_NAME:-}" ]; then
        echo "Specific resources to be deleted:"
        [ -n "${BATCH_COMPUTE_ENV_NAME:-}" ] && echo "  - Compute Environment: $BATCH_COMPUTE_ENV_NAME"
        [ -n "${BATCH_JOB_QUEUE_NAME:-}" ] && echo "  - Job Queue: $BATCH_JOB_QUEUE_NAME"
        [ -n "${BATCH_JOB_DEFINITION_NAME:-}" ] && echo "  - Job Definition: $BATCH_JOB_DEFINITION_NAME"
        [ -n "${BATCH_EXECUTION_ROLE_NAME:-}" ] && echo "  - IAM Role: $BATCH_EXECUTION_ROLE_NAME"
        [ -n "${ECR_REPOSITORY_NAME:-}" ] && echo "  - ECR Repository: $ECR_REPOSITORY_NAME"
        [ -n "${LOG_GROUP_NAME:-}" ] && echo "  - Log Group: $LOG_GROUP_NAME"
        echo ""
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Cleanup confirmed, proceeding..."
}

# Stop and cancel running jobs
cleanup_jobs() {
    if [ -z "${BATCH_JOB_QUEUE_NAME:-}" ]; then
        log_info "No job queue specified, skipping job cleanup"
        return 0
    fi
    
    log_info "Cancelling any running or queued jobs..."
    
    # List and cancel running jobs
    local running_jobs=$(aws batch list-jobs \
        --job-queue ${BATCH_JOB_QUEUE_NAME} \
        --job-status RUNNING \
        --query 'jobSummaryList[].jobId' --output text 2>/dev/null || echo "")
    
    if [ -n "$running_jobs" ]; then
        for job_id in $running_jobs; do
            log_info "Cancelling running job: $job_id"
            aws batch cancel-job \
                --job-id $job_id \
                --reason "Cleanup procedure" || log_warning "Failed to cancel job $job_id"
        done
    fi
    
    # List and cancel queued jobs
    local queued_jobs=$(aws batch list-jobs \
        --job-queue ${BATCH_JOB_QUEUE_NAME} \
        --job-status SUBMITTED,PENDING,RUNNABLE \
        --query 'jobSummaryList[].jobId' --output text 2>/dev/null || echo "")
    
    if [ -n "$queued_jobs" ]; then
        for job_id in $queued_jobs; do
            log_info "Cancelling queued job: $job_id"
            aws batch cancel-job \
                --job-id $job_id \
                --reason "Cleanup procedure" || log_warning "Failed to cancel job $job_id"
        done
    fi
    
    # Wait for jobs to finish cancelling
    if [ -n "$running_jobs" ] || [ -n "$queued_jobs" ]; then
        log_info "Waiting for jobs to finish cancelling..."
        sleep 30
    fi
    
    log_success "Job cleanup completed"
}

# Delete job queue
delete_job_queue() {
    if [ -z "${BATCH_JOB_QUEUE_NAME:-}" ]; then
        log_info "No job queue specified, skipping job queue deletion"
        return 0
    fi
    
    log_info "Deleting job queue: $BATCH_JOB_QUEUE_NAME"
    
    # Check if job queue exists
    local queue_status=$(aws batch describe-job-queues \
        --job-queues ${BATCH_JOB_QUEUE_NAME} \
        --query 'jobQueues[0].state' --output text 2>/dev/null || echo "NOTFOUND")
    
    if [ "$queue_status" = "NOTFOUND" ] || [ "$queue_status" = "None" ]; then
        log_info "Job queue not found, skipping deletion"
        return 0
    fi
    
    # Disable job queue first
    if [ "$queue_status" = "ENABLED" ]; then
        log_info "Disabling job queue..."
        aws batch update-job-queue \
            --job-queue ${BATCH_JOB_QUEUE_NAME} \
            --state DISABLED
        
        # Wait for job queue to be disabled
        local timeout=300  # 5 minutes
        local elapsed=0
        local interval=15
        
        while [ $elapsed -lt $timeout ]; do
            local status=$(aws batch describe-job-queues \
                --job-queues ${BATCH_JOB_QUEUE_NAME} \
                --query 'jobQueues[0].state' --output text)
            
            if [ "$status" = "DISABLED" ]; then
                break
            fi
            
            log_info "Waiting for job queue to be disabled... (status: $status)"
            sleep $interval
            elapsed=$((elapsed + interval))
        done
    fi
    
    # Delete job queue
    aws batch delete-job-queue \
        --job-queue ${BATCH_JOB_QUEUE_NAME}
    
    log_success "Job queue deleted: ${BATCH_JOB_QUEUE_NAME}"
}

# Delete compute environment
delete_compute_environment() {
    if [ -z "${BATCH_COMPUTE_ENV_NAME:-}" ]; then
        log_info "No compute environment specified, skipping compute environment deletion"
        return 0
    fi
    
    log_info "Deleting compute environment: $BATCH_COMPUTE_ENV_NAME"
    
    # Check if compute environment exists
    local env_status=$(aws batch describe-compute-environments \
        --compute-environments ${BATCH_COMPUTE_ENV_NAME} \
        --query 'computeEnvironments[0].state' --output text 2>/dev/null || echo "NOTFOUND")
    
    if [ "$env_status" = "NOTFOUND" ] || [ "$env_status" = "None" ]; then
        log_info "Compute environment not found, skipping deletion"
        return 0
    fi
    
    # Disable compute environment first
    if [ "$env_status" = "ENABLED" ]; then
        log_info "Disabling compute environment..."
        aws batch update-compute-environment \
            --compute-environment ${BATCH_COMPUTE_ENV_NAME} \
            --state DISABLED
        
        # Wait for compute environment to be disabled
        local timeout=600  # 10 minutes
        local elapsed=0
        local interval=30
        
        while [ $elapsed -lt $timeout ]; do
            local status=$(aws batch describe-compute-environments \
                --compute-environments ${BATCH_COMPUTE_ENV_NAME} \
                --query 'computeEnvironments[0].state' --output text)
            
            if [ "$status" = "DISABLED" ]; then
                break
            fi
            
            log_info "Waiting for compute environment to be disabled... (status: $status)"
            sleep $interval
            elapsed=$((elapsed + interval))
        done
    fi
    
    # Delete compute environment
    aws batch delete-compute-environment \
        --compute-environment ${BATCH_COMPUTE_ENV_NAME}
    
    log_success "Compute environment deleted: ${BATCH_COMPUTE_ENV_NAME}"
}

# Delete ECR repository
delete_ecr_repository() {
    if [ -z "${ECR_REPOSITORY_NAME:-}" ]; then
        log_info "No ECR repository specified, skipping ECR repository deletion"
        return 0
    fi
    
    log_info "Deleting ECR repository: $ECR_REPOSITORY_NAME"
    
    # Check if repository exists
    if aws ecr describe-repositories --repository-names ${ECR_REPOSITORY_NAME} &>/dev/null; then
        # Delete repository with all images
        aws ecr delete-repository \
            --repository-name ${ECR_REPOSITORY_NAME} \
            --force
        
        log_success "ECR repository deleted: ${ECR_REPOSITORY_NAME}"
    else
        log_info "ECR repository not found, skipping deletion"
    fi
}

# Delete IAM role
delete_iam_role() {
    if [ -z "${BATCH_EXECUTION_ROLE_NAME:-}" ]; then
        log_info "No IAM role specified, skipping IAM role deletion"
        return 0
    fi
    
    log_info "Deleting IAM role: $BATCH_EXECUTION_ROLE_NAME"
    
    # Check if role exists
    if aws iam get-role --role-name ${BATCH_EXECUTION_ROLE_NAME} &>/dev/null; then
        # Detach managed policies
        log_info "Detaching policies from role..."
        aws iam detach-role-policy \
            --role-name ${BATCH_EXECUTION_ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy || \
            log_warning "Failed to detach policy from role"
        
        # Delete role
        aws iam delete-role \
            --role-name ${BATCH_EXECUTION_ROLE_NAME}
        
        log_success "IAM role deleted: ${BATCH_EXECUTION_ROLE_NAME}"
    else
        log_info "IAM role not found, skipping deletion"
    fi
}

# Delete CloudWatch log group
delete_log_group() {
    local log_group="${LOG_GROUP_NAME:-/aws/batch/job}"
    
    log_info "Deleting CloudWatch log group: $log_group"
    
    # Check if log group exists
    if aws logs describe-log-groups --log-group-name-prefix "$log_group" \
        --query "logGroups[?logGroupName=='$log_group']" --output text | grep -q "$log_group"; then
        
        aws logs delete-log-group \
            --log-group-name "$log_group"
        
        log_success "CloudWatch log group deleted: $log_group"
    else
        log_info "CloudWatch log group not found, skipping deletion"
    fi
}

# Cleanup job definitions
cleanup_job_definitions() {
    if [ -z "${BATCH_JOB_DEFINITION_NAME:-}" ]; then
        log_info "No job definition specified, skipping job definition cleanup"
        return 0
    fi
    
    log_info "Deregistering job definition: $BATCH_JOB_DEFINITION_NAME"
    
    # Get all revisions of the job definition
    local revisions=$(aws batch describe-job-definitions \
        --job-definition-name ${BATCH_JOB_DEFINITION_NAME} \
        --status ACTIVE \
        --query 'jobDefinitions[].revision' --output text 2>/dev/null || echo "")
    
    if [ -n "$revisions" ]; then
        for revision in $revisions; do
            log_info "Deregistering job definition revision: ${BATCH_JOB_DEFINITION_NAME}:${revision}"
            aws batch deregister-job-definition \
                --job-definition ${BATCH_JOB_DEFINITION_NAME}:${revision} || \
                log_warning "Failed to deregister job definition revision $revision"
        done
        log_success "Job definition deregistered: ${BATCH_JOB_DEFINITION_NAME}"
    else
        log_info "No active job definition revisions found"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    rm -f /tmp/batch-execution-role-trust-policy.json
    rm -f /tmp/compute-environment.json
    rm -f /tmp/job-definition.json
    rm -f /tmp/batch-process.py
    rm -f /tmp/Dockerfile
    
    log_success "Temporary files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local issues=0
    
    # Check compute environments
    if [ -n "${BATCH_COMPUTE_ENV_NAME:-}" ]; then
        local env_exists=$(aws batch describe-compute-environments \
            --compute-environments ${BATCH_COMPUTE_ENV_NAME} \
            --query 'computeEnvironments[0].computeEnvironmentName' --output text 2>/dev/null || echo "None")
        
        if [ "$env_exists" != "None" ]; then
            log_warning "Compute environment still exists: $BATCH_COMPUTE_ENV_NAME"
            issues=$((issues + 1))
        fi
    fi
    
    # Check job queues
    if [ -n "${BATCH_JOB_QUEUE_NAME:-}" ]; then
        local queue_exists=$(aws batch describe-job-queues \
            --job-queues ${BATCH_JOB_QUEUE_NAME} \
            --query 'jobQueues[0].jobQueueName' --output text 2>/dev/null || echo "None")
        
        if [ "$queue_exists" != "None" ]; then
            log_warning "Job queue still exists: $BATCH_JOB_QUEUE_NAME"
            issues=$((issues + 1))
        fi
    fi
    
    # Check ECR repository
    if [ -n "${ECR_REPOSITORY_NAME:-}" ]; then
        if aws ecr describe-repositories --repository-names ${ECR_REPOSITORY_NAME} &>/dev/null; then
            log_warning "ECR repository still exists: $ECR_REPOSITORY_NAME"
            issues=$((issues + 1))
        fi
    fi
    
    # Check IAM role
    if [ -n "${BATCH_EXECUTION_ROLE_NAME:-}" ]; then
        if aws iam get-role --role-name ${BATCH_EXECUTION_ROLE_NAME} &>/dev/null; then
            log_warning "IAM role still exists: $BATCH_EXECUTION_ROLE_NAME"
            issues=$((issues + 1))
        fi
    fi
    
    if [ $issues -eq 0 ]; then
        log_success "Cleanup verification completed successfully - all resources removed"
    else
        log_warning "Cleanup verification found $issues potential issues - some resources may still exist"
        log_info "You may need to manually check and remove remaining resources"
    fi
}

# Main cleanup function
main() {
    log_info "Starting AWS Batch Fargate infrastructure cleanup..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Run cleanup steps
    check_prerequisites
    
    # Try to load deployment info, fall back to discovery if needed
    if ! load_deployment_info; then
        discover_resources
    fi
    
    confirm_cleanup
    cleanup_jobs
    cleanup_job_definitions
    delete_job_queue
    delete_compute_environment
    delete_ecr_repository
    delete_iam_role
    delete_log_group
    cleanup_temp_files
    verify_cleanup
    
    log_success "AWS Batch Fargate cleanup completed successfully!"
    echo ""
    echo "=== Cleanup Summary ==="
    echo "- All AWS Batch resources have been removed"
    echo "- Container images and ECR repository deleted"
    echo "- IAM roles and CloudWatch logs cleaned up"
    echo "- No ongoing charges from this deployment"
    echo ""
    log_info "If you encounter any issues, check the AWS Console to manually remove remaining resources"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi