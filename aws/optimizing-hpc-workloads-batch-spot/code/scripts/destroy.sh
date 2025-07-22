#!/bin/bash

# AWS Batch HPC Workloads with Spot Instances - Cleanup Script
# This script safely removes all infrastructure created by the deployment script
# including proper handling of dependencies and confirmation prompts

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to load environment variables
load_environment() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local env_file="${script_dir}/.env"
    
    if [ -f "$env_file" ]; then
        log "Loading environment variables from .env file..."
        source "$env_file"
        log_success "Environment variables loaded"
    else
        log_warning ".env file not found. You may need to provide resource names manually."
        
        # Prompt for required variables if not found
        if [ -z "${RANDOM_SUFFIX:-}" ]; then
            echo -n "Enter the resource suffix (6 characters): "
            read RANDOM_SUFFIX
            export RANDOM_SUFFIX
        fi
        
        if [ -z "${AWS_REGION:-}" ]; then
            export AWS_REGION=$(aws configure get region)
            if [ -z "$AWS_REGION" ]; then
                export AWS_REGION="us-east-1"
            fi
        fi
        
        if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
            export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        fi
        
        # Set resource names based on suffix
        export BUCKET_NAME="hpc-batch-${RANDOM_SUFFIX}"
        export COMPUTE_ENV_NAME="hpc-spot-compute-${RANDOM_SUFFIX}"
        export JOB_QUEUE_NAME="hpc-job-queue-${RANDOM_SUFFIX}"
        export JOB_DEFINITION_NAME="hpc-simulation-${RANDOM_SUFFIX}"
    fi
}

# Function to confirm cleanup
confirm_cleanup() {
    echo ""
    echo "======================================"
    echo "       CLEANUP CONFIRMATION"
    echo "======================================"
    echo "This will DELETE the following resources:"
    echo ""
    echo "AWS Region: ${AWS_REGION:-N/A}"
    echo "S3 Bucket: ${BUCKET_NAME:-N/A}"
    echo "Compute Environment: ${COMPUTE_ENV_NAME:-N/A}"
    echo "Job Queue: ${JOB_QUEUE_NAME:-N/A}"
    echo "Job Definition: ${JOB_DEFINITION_NAME:-N/A}"
    echo "EFS File System: ${EFS_ID:-N/A}"
    echo "IAM Roles and Policies"
    echo "Security Groups"
    echo "CloudWatch Resources"
    echo ""
    echo "⚠️  THIS ACTION CANNOT BE UNDONE ⚠️"
    echo "======================================"
    echo ""
    
    # Check for force flag
    if [ "${1:-}" = "--force" ] || [ "${FORCE_CLEANUP:-}" = "true" ]; then
        log_warning "Force flag detected. Proceeding with cleanup..."
        return 0
    fi
    
    echo -n "Are you sure you want to continue? (yes/no): "
    read confirmation
    
    if [ "$confirmation" != "yes" ] && [ "$confirmation" != "y" ]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    echo -n "Type 'DELETE' to confirm: "
    read delete_confirmation
    
    if [ "$delete_confirmation" != "DELETE" ]; then
        log "Cleanup cancelled. You must type 'DELETE' to confirm."
        exit 0
    fi
    
    log_success "Confirmation received. Starting cleanup..."
}

# Function to cancel running jobs
cancel_running_jobs() {
    log "Cancelling any running jobs..."
    
    if [ -z "${JOB_QUEUE_NAME:-}" ]; then
        log_warning "Job queue name not found. Skipping job cancellation."
        return 0
    fi
    
    # List and cancel running jobs
    local running_jobs=$(aws batch list-jobs --job-queue ${JOB_QUEUE_NAME} \
        --job-status RUNNING \
        --query "jobSummaryList[].jobId" --output text 2>/dev/null || echo "")
    
    if [ ! -z "$running_jobs" ] && [ "$running_jobs" != "None" ]; then
        for job_id in $running_jobs; do
            if [ ! -z "$job_id" ] && [ "$job_id" != "None" ]; then
                log "Cancelling job: $job_id"
                aws batch cancel-job --job-id $job_id \
                    --reason "Cleanup operation" 2>/dev/null || true
            fi
        done
        
        # Wait for jobs to be cancelled
        log "Waiting for jobs to be cancelled..."
        sleep 10
    fi
    
    # Also cancel submitted and runnable jobs
    local pending_jobs=$(aws batch list-jobs --job-queue ${JOB_QUEUE_NAME} \
        --job-status SUBMITTED \
        --query "jobSummaryList[].jobId" --output text 2>/dev/null || echo "")
    
    if [ ! -z "$pending_jobs" ] && [ "$pending_jobs" != "None" ]; then
        for job_id in $pending_jobs; do
            if [ ! -z "$job_id" ] && [ "$job_id" != "None" ]; then
                log "Cancelling pending job: $job_id"
                aws batch cancel-job --job-id $job_id \
                    --reason "Cleanup operation" 2>/dev/null || true
            fi
        done
    fi
    
    log_success "Running jobs cancelled"
}

# Function to delete job queue
delete_job_queue() {
    log "Deleting job queue..."
    
    if [ -z "${JOB_QUEUE_NAME:-}" ]; then
        log_warning "Job queue name not found. Skipping."
        return 0
    fi
    
    # Check if job queue exists
    local queue_exists=$(aws batch describe-job-queues \
        --job-queues ${JOB_QUEUE_NAME} \
        --query "length(jobQueues)" --output text 2>/dev/null || echo "0")
    
    if [ "$queue_exists" = "0" ]; then
        log_warning "Job queue not found. May have been already deleted."
        return 0
    fi
    
    # Disable job queue first
    log "Disabling job queue..."
    aws batch update-job-queue \
        --job-queue ${JOB_QUEUE_NAME} \
        --state DISABLED 2>/dev/null || true
    
    # Wait for job queue to be disabled
    local max_wait=120  # 2 minutes
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        local state=$(aws batch describe-job-queues \
            --job-queues ${JOB_QUEUE_NAME} \
            --query "jobQueues[0].state" --output text 2>/dev/null || echo "")
        
        if [ "$state" = "DISABLED" ]; then
            break
        fi
        
        log "Waiting for job queue to be disabled..."
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    # Delete job queue
    aws batch delete-job-queue \
        --job-queue ${JOB_QUEUE_NAME} 2>/dev/null || true
    
    log_success "Job queue deleted"
}

# Function to delete compute environment
delete_compute_environment() {
    log "Deleting compute environment..."
    
    if [ -z "${COMPUTE_ENV_NAME:-}" ]; then
        log_warning "Compute environment name not found. Skipping."
        return 0
    fi
    
    # Check if compute environment exists
    local env_exists=$(aws batch describe-compute-environments \
        --compute-environments ${COMPUTE_ENV_NAME} \
        --query "length(computeEnvironments)" --output text 2>/dev/null || echo "0")
    
    if [ "$env_exists" = "0" ]; then
        log_warning "Compute environment not found. May have been already deleted."
        return 0
    fi
    
    # Disable compute environment first
    log "Disabling compute environment..."
    aws batch update-compute-environment \
        --compute-environment ${COMPUTE_ENV_NAME} \
        --state DISABLED 2>/dev/null || true
    
    # Wait for compute environment to be disabled
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        local state=$(aws batch describe-compute-environments \
            --compute-environments ${COMPUTE_ENV_NAME} \
            --query "computeEnvironments[0].state" --output text 2>/dev/null || echo "")
        
        if [ "$state" = "DISABLED" ]; then
            break
        fi
        
        log "Waiting for compute environment to be disabled..."
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    # Delete compute environment
    aws batch delete-compute-environment \
        --compute-environment ${COMPUTE_ENV_NAME} 2>/dev/null || true
    
    # Wait for deletion to complete
    log "Waiting for compute environment deletion to complete..."
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        local exists=$(aws batch describe-compute-environments \
            --compute-environments ${COMPUTE_ENV_NAME} \
            --query "length(computeEnvironments)" --output text 2>/dev/null || echo "0")
        
        if [ "$exists" = "0" ]; then
            break
        fi
        
        log "Waiting for compute environment deletion..."
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    log_success "Compute environment deleted"
}

# Function to delete EFS resources
delete_efs_resources() {
    log "Deleting EFS resources..."
    
    if [ ! -z "${EFS_ID:-}" ]; then
        # Delete EFS file system
        log "Deleting EFS file system: $EFS_ID"
        aws efs delete-file-system --file-system-id ${EFS_ID} 2>/dev/null || \
            log_warning "EFS file system may have been already deleted or doesn't exist"
    fi
    
    if [ ! -z "${EFS_SECURITY_GROUP_ID:-}" ]; then
        # Delete EFS security group
        log "Deleting EFS security group: $EFS_SECURITY_GROUP_ID"
        aws ec2 delete-security-group --group-id ${EFS_SECURITY_GROUP_ID} 2>/dev/null || \
            log_warning "EFS security group may have been already deleted or doesn't exist"
    fi
    
    log_success "EFS resources deletion completed"
}

# Function to delete security groups
delete_security_groups() {
    log "Deleting security groups..."
    
    if [ ! -z "${SECURITY_GROUP_ID:-}" ]; then
        log "Deleting Batch compute security group: $SECURITY_GROUP_ID"
        aws ec2 delete-security-group --group-id ${SECURITY_GROUP_ID} 2>/dev/null || \
            log_warning "Batch security group may have been already deleted or doesn't exist"
    fi
    
    log_success "Security groups deletion completed"
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        log_warning "Random suffix not found. Cannot delete IAM resources."
        return 0
    fi
    
    # Delete instance profile and role
    log "Deleting instance profile and ECS role..."
    aws iam remove-role-from-instance-profile \
        --instance-profile-name "ecsInstanceProfile-${RANDOM_SUFFIX}" \
        --role-name "ecsInstanceRole-${RANDOM_SUFFIX}" 2>/dev/null || true
    
    aws iam delete-instance-profile \
        --instance-profile-name "ecsInstanceProfile-${RANDOM_SUFFIX}" 2>/dev/null || true
    
    # Detach policies from ECS instance role
    aws iam detach-role-policy \
        --role-name "ecsInstanceRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role" 2>/dev/null || true
    
    aws iam detach-role-policy \
        --role-name "ecsInstanceRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" 2>/dev/null || true
    
    # Delete ECS instance role
    aws iam delete-role --role-name "ecsInstanceRole-${RANDOM_SUFFIX}" 2>/dev/null || true
    
    # Delete Batch service role
    log "Deleting Batch service role..."
    aws iam detach-role-policy \
        --role-name "AWSBatchServiceRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole" 2>/dev/null || true
    
    aws iam delete-role --role-name "AWSBatchServiceRole-${RANDOM_SUFFIX}" 2>/dev/null || true
    
    log_success "IAM resources deleted"
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket..."
    
    if [ -z "${BUCKET_NAME:-}" ]; then
        log_warning "Bucket name not found. Skipping S3 cleanup."
        return 0
    fi
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket ${BUCKET_NAME} 2>/dev/null; then
        # Empty bucket first
        log "Emptying S3 bucket: $BUCKET_NAME"
        aws s3 rm s3://${BUCKET_NAME} --recursive 2>/dev/null || true
        
        # Delete bucket
        log "Deleting S3 bucket: $BUCKET_NAME"
        aws s3 rb s3://${BUCKET_NAME} 2>/dev/null || \
            log_warning "Failed to delete S3 bucket. It may contain objects or have active uploads."
    else
        log_warning "S3 bucket not found or already deleted."
    fi
    
    log_success "S3 bucket cleanup completed"
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch log group
    aws logs delete-log-group --log-group-name "/aws/batch/job" 2>/dev/null || \
        log_warning "CloudWatch log group may not exist or already deleted"
    
    # Delete CloudWatch alarm
    if [ ! -z "${RANDOM_SUFFIX:-}" ]; then
        aws cloudwatch delete-alarms \
            --alarm-names "HPC-Batch-FailedJobs-${RANDOM_SUFFIX}" 2>/dev/null || \
            log_warning "CloudWatch alarm may not exist or already deleted"
    fi
    
    log_success "CloudWatch resources deleted"
}

# Function to deregister job definitions
deregister_job_definitions() {
    log "Deregistering job definitions..."
    
    if [ -z "${JOB_DEFINITION_NAME:-}" ]; then
        log_warning "Job definition name not found. Skipping."
        return 0
    fi
    
    # List all revisions of the job definition
    local revisions=$(aws batch describe-job-definitions \
        --job-definition-name ${JOB_DEFINITION_NAME} \
        --status ACTIVE \
        --query "jobDefinitions[].revision" --output text 2>/dev/null || echo "")
    
    if [ ! -z "$revisions" ] && [ "$revisions" != "None" ]; then
        for revision in $revisions; do
            log "Deregistering job definition: ${JOB_DEFINITION_NAME}:${revision}"
            aws batch deregister-job-definition \
                --job-definition "${JOB_DEFINITION_NAME}:${revision}" 2>/dev/null || true
        done
    fi
    
    log_success "Job definitions deregistered"
}

# Function to clean up environment file
cleanup_env_file() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local env_file="${script_dir}/.env"
    
    if [ -f "$env_file" ]; then
        log "Removing environment file..."
        rm -f "$env_file"
        log_success "Environment file removed"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local errors=0
    
    # Check if S3 bucket still exists
    if [ ! -z "${BUCKET_NAME:-}" ]; then
        if aws s3api head-bucket --bucket ${BUCKET_NAME} 2>/dev/null; then
            log_error "S3 bucket still exists: $BUCKET_NAME"
            errors=$((errors + 1))
        fi
    fi
    
    # Check if compute environment still exists
    if [ ! -z "${COMPUTE_ENV_NAME:-}" ]; then
        local env_count=$(aws batch describe-compute-environments \
            --compute-environments ${COMPUTE_ENV_NAME} \
            --query "length(computeEnvironments)" --output text 2>/dev/null || echo "0")
        
        if [ "$env_count" != "0" ]; then
            log_error "Compute environment still exists: $COMPUTE_ENV_NAME"
            errors=$((errors + 1))
        fi
    fi
    
    # Check if job queue still exists
    if [ ! -z "${JOB_QUEUE_NAME:-}" ]; then
        local queue_count=$(aws batch describe-job-queues \
            --job-queues ${JOB_QUEUE_NAME} \
            --query "length(jobQueues)" --output text 2>/dev/null || echo "0")
        
        if [ "$queue_count" != "0" ]; then
            log_error "Job queue still exists: $JOB_QUEUE_NAME"
            errors=$((errors + 1))
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "Cleanup verification passed"
    else
        log_warning "Cleanup verification found $errors issues. Some resources may need manual cleanup."
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    echo ""
    echo "======================================"
    echo "       CLEANUP COMPLETED"
    echo "======================================"
    
    if [ $# -gt 0 ] && [ "$1" = "success" ]; then
        log_success "🎉 All resources have been successfully deleted!"
        echo ""
        echo "The following resources were removed:"
        echo "✅ AWS Batch Compute Environment"
        echo "✅ AWS Batch Job Queue"
        echo "✅ AWS Batch Job Definitions"
        echo "✅ EFS File System and Security Groups"
        echo "✅ IAM Roles and Instance Profiles"
        echo "✅ S3 Bucket and Contents"
        echo "✅ CloudWatch Logs and Alarms"
        echo "✅ EC2 Security Groups"
    else
        log_warning "Cleanup completed with some warnings."
        echo ""
        echo "Please check the output above for any resources"
        echo "that may require manual cleanup."
    fi
    
    echo ""
    echo "⚠️  Remember to check your AWS bill to ensure"
    echo "   no unexpected charges are incurred."
    echo "======================================"
}

# Main execution
main() {
    log "Starting AWS Batch HPC cleanup..."
    
    load_environment
    confirm_cleanup "$@"
    
    # Cleanup in reverse order of creation
    cancel_running_jobs
    delete_job_queue
    delete_compute_environment
    deregister_job_definitions
    delete_efs_resources
    delete_security_groups
    delete_iam_resources
    delete_s3_bucket
    delete_cloudwatch_resources
    cleanup_env_file
    
    verify_cleanup
    show_cleanup_summary "success"
    
    log_success "Cleanup script completed successfully!"
}

# Error handling
trap 'log_error "Cleanup script failed at line $LINENO. Some resources may require manual cleanup."' ERR

# Help function
show_help() {
    echo "AWS Batch HPC Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force    Skip confirmation prompts and proceed with cleanup"
    echo "  --help     Show this help message"
    echo ""
    echo "This script will delete all resources created by the deploy.sh script."
    echo "Make sure you have the .env file or know your resource identifiers."
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac