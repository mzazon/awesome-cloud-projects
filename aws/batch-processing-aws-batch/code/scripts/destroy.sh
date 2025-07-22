#!/bin/bash

# AWS Batch Processing Workloads Cleanup Script
# This script removes all AWS Batch infrastructure created by the deployment script
# Prerequisites: AWS CLI v2 and appropriate IAM permissions

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Parse command line options
DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run     Show what would be deleted without making changes"
            echo "  --force       Skip confirmation prompts (use with caution)"
            echo "  --help, -h    Show this help message"
            echo ""
            echo "This script removes all AWS Batch infrastructure including:"
            echo "  - Running jobs (cancelled)"
            echo "  - Job queues and compute environments"
            echo "  - Job definitions and ECR repository"
            echo "  - IAM roles and security groups"
            echo "  - CloudWatch resources"
            echo ""
            echo "WARNING: This action cannot be undone!"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid. Please configure AWS CLI."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load environment variables
load_environment() {
    log "Loading deployment environment variables..."
    
    if [ -f ".batch_deployment_vars" ]; then
        source .batch_deployment_vars
        success "Environment variables loaded from .batch_deployment_vars"
    else
        warning "Environment file .batch_deployment_vars not found."
        warning "You will need to provide resource names manually or check AWS console."
        
        # Try to get AWS region from CLI config
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            warning "No default region configured, using us-east-1"
        fi
        
        # Get AWS account ID
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        log "AWS Region: $AWS_REGION"
        log "AWS Account ID: $AWS_ACCOUNT_ID"
        
        warning "Some cleanup operations may fail without proper environment variables."
        echo "Continue with cleanup? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user."
            exit 0
        fi
    fi
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warning "This script will DELETE the following resources:"
    
    if [ -n "${BATCH_COMPUTE_ENV_NAME:-}" ]; then
        echo "- Batch Compute Environment: $BATCH_COMPUTE_ENV_NAME"
    fi
    if [ -n "${BATCH_JOB_QUEUE_NAME:-}" ]; then
        echo "- Batch Job Queue: $BATCH_JOB_QUEUE_NAME"
    fi
    if [ -n "${BATCH_JOB_DEFINITION_NAME:-}" ]; then
        echo "- Batch Job Definition: $BATCH_JOB_DEFINITION_NAME"
    fi
    if [ -n "${ECR_REPO_NAME:-}" ]; then
        echo "- ECR Repository: $ECR_REPO_NAME"
    fi
    if [ -n "${SECURITY_GROUP_ID:-}" ]; then
        echo "- Security Group: $SECURITY_GROUP_ID"
    fi
    if [ -n "${BATCH_SERVICE_ROLE_NAME:-}" ]; then
        echo "- IAM Service Role: $BATCH_SERVICE_ROLE_NAME"
    fi
    if [ -n "${BATCH_INSTANCE_ROLE_NAME:-}" ]; then
        echo "- IAM Instance Role: $BATCH_INSTANCE_ROLE_NAME"
    fi
    if [ -n "${BATCH_INSTANCE_PROFILE_NAME:-}" ]; then
        echo "- IAM Instance Profile: $BATCH_INSTANCE_PROFILE_NAME"
    fi
    echo "- CloudWatch Log Group: /aws/batch/job"
    echo "- CloudWatch Alarms (if created)"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN MODE - No resources would actually be deleted"
        return
    fi
    
    if [ "$FORCE" = true ]; then
        warning "Force mode enabled - skipping confirmation"
        return
    fi
    
    warning "This action cannot be undone!"
    echo "Are you sure you want to proceed? (yes/NO)"
    read -r response
    if [[ ! "$response" == "yes" ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
}

# Function to cancel running jobs
cancel_running_jobs() {
    if [ -z "${BATCH_JOB_QUEUE_NAME:-}" ]; then
        warning "Job queue name not available, skipping job cancellation"
        return
    fi
    
    log "Cancelling any running jobs in queue: $BATCH_JOB_QUEUE_NAME"
    
    # Get all active job statuses
    RUNNING_JOBS=$(aws batch list-jobs \
        --job-queue ${BATCH_JOB_QUEUE_NAME} \
        --job-status RUNNING \
        --query 'jobSummaryList[*].jobId' --output text 2>/dev/null || echo "")
    
    RUNNABLE_JOBS=$(aws batch list-jobs \
        --job-queue ${BATCH_JOB_QUEUE_NAME} \
        --job-status RUNNABLE \
        --query 'jobSummaryList[*].jobId' --output text 2>/dev/null || echo "")
    
    PENDING_JOBS=$(aws batch list-jobs \
        --job-queue ${BATCH_JOB_QUEUE_NAME} \
        --job-status PENDING \
        --query 'jobSummaryList[*].jobId' --output text 2>/dev/null || echo "")
    
    SUBMITTED_JOBS=$(aws batch list-jobs \
        --job-queue ${BATCH_JOB_QUEUE_NAME} \
        --job-status SUBMITTED \
        --query 'jobSummaryList[*].jobId' --output text 2>/dev/null || echo "")
    
    # Cancel specific test jobs if they exist
    if [ -n "${TEST_JOB_ID:-}" ]; then
        log "Cancelling test job: $TEST_JOB_ID"
        aws batch cancel-job \
            --job-id $TEST_JOB_ID \
            --reason "Cleanup - infrastructure deletion" 2>/dev/null || true
    fi
    
    if [ -n "${ARRAY_JOB_ID:-}" ]; then
        log "Cancelling array test job: $ARRAY_JOB_ID"
        aws batch cancel-job \
            --job-id $ARRAY_JOB_ID \
            --reason "Cleanup - infrastructure deletion" 2>/dev/null || true
    fi
    
    # Cancel running jobs
    if [ -n "$RUNNING_JOBS" ]; then
        for JOB_ID in $RUNNING_JOBS; do
            log "Cancelling running job: $JOB_ID"
            aws batch cancel-job \
                --job-id $JOB_ID \
                --reason "Cleanup - infrastructure deletion" 2>/dev/null || true
        done
        success "Running jobs cancelled"
    fi
    
    # Cancel runnable jobs
    if [ -n "$RUNNABLE_JOBS" ]; then
        for JOB_ID in $RUNNABLE_JOBS; do
            log "Cancelling runnable job: $JOB_ID"
            aws batch cancel-job \
                --job-id $JOB_ID \
                --reason "Cleanup - infrastructure deletion" 2>/dev/null || true
        done
        success "Runnable jobs cancelled"
    fi
    
    # Cancel pending jobs
    if [ -n "$PENDING_JOBS" ]; then
        for JOB_ID in $PENDING_JOBS; do
            log "Cancelling pending job: $JOB_ID"
            aws batch cancel-job \
                --job-id $JOB_ID \
                --reason "Cleanup - infrastructure deletion" 2>/dev/null || true
        done
        success "Pending jobs cancelled"
    fi
    
    # Cancel submitted jobs
    if [ -n "$SUBMITTED_JOBS" ]; then
        for JOB_ID in $SUBMITTED_JOBS; do
            log "Cancelling submitted job: $JOB_ID"
            aws batch cancel-job \
                --job-id $JOB_ID \
                --reason "Cleanup - infrastructure deletion" 2>/dev/null || true
        done
        success "Submitted jobs cancelled"
    fi
    
    if [ -z "$RUNNING_JOBS" ] && [ -z "$RUNNABLE_JOBS" ] && [ -z "$PENDING_JOBS" ] && [ -z "$SUBMITTED_JOBS" ]; then
        log "No active jobs found in queue"
    fi
    
    # Wait for jobs to be cancelled
    if [ -n "$RUNNING_JOBS" ] || [ -n "$RUNNABLE_JOBS" ] || [ -n "$PENDING_JOBS" ] || [ -n "$SUBMITTED_JOBS" ]; then
        log "Waiting for jobs to be cancelled..."
        sleep 30
    fi
}

# Function to delete job queue
delete_job_queue() {
    if [ -z "${BATCH_JOB_QUEUE_NAME:-}" ]; then
        warning "Job queue name not available, skipping"
        return
    fi
    
    log "Deleting job queue: $BATCH_JOB_QUEUE_NAME"
    
    # Disable job queue first
    log "Disabling job queue..."
    aws batch update-job-queue \
        --job-queue ${BATCH_JOB_QUEUE_NAME} \
        --state DISABLED 2>/dev/null || warning "Failed to disable job queue or queue doesn't exist"
    
    # Wait for queue to be disabled
    log "Waiting for job queue to be disabled..."
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        STATUS=$(aws batch describe-job-queues \
            --job-queues ${BATCH_JOB_QUEUE_NAME} \
            --query 'jobQueues[0].state' --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$STATUS" = "DISABLED" ] || [ "$STATUS" = "NOT_FOUND" ]; then
            break
        else
            log "Job queue state: $STATUS (attempt $attempt/$max_attempts)"
            sleep 15
            ((attempt++))
        fi
    done
    
    # Delete job queue
    log "Deleting job queue..."
    aws batch delete-job-queue \
        --job-queue ${BATCH_JOB_QUEUE_NAME} 2>/dev/null || warning "Failed to delete job queue or queue doesn't exist"
    
    success "Job queue deletion initiated"
}

# Function to delete compute environment
delete_compute_environment() {
    if [ -z "${BATCH_COMPUTE_ENV_NAME:-}" ]; then
        warning "Compute environment name not available, skipping"
        return
    fi
    
    log "Deleting compute environment: $BATCH_COMPUTE_ENV_NAME"
    
    # Disable compute environment first
    log "Disabling compute environment..."
    aws batch update-compute-environment \
        --compute-environment ${BATCH_COMPUTE_ENV_NAME} \
        --state DISABLED 2>/dev/null || warning "Failed to disable compute environment or environment doesn't exist"
    
    # Wait for compute environment to be disabled
    log "Waiting for compute environment to be disabled..."
    local max_attempts=15
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        STATUS=$(aws batch describe-compute-environments \
            --compute-environments ${BATCH_COMPUTE_ENV_NAME} \
            --query 'computeEnvironments[0].state' --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$STATUS" = "DISABLED" ] || [ "$STATUS" = "NOT_FOUND" ]; then
            break
        else
            log "Compute environment state: $STATUS (attempt $attempt/$max_attempts)"
            sleep 30
            ((attempt++))
        fi
    done
    
    # Delete compute environment
    log "Deleting compute environment..."
    aws batch delete-compute-environment \
        --compute-environment ${BATCH_COMPUTE_ENV_NAME} 2>/dev/null || warning "Failed to delete compute environment or environment doesn't exist"
    
    success "Compute environment deletion initiated"
}

# Function to delete job definitions
delete_job_definitions() {
    if [ -z "${BATCH_JOB_DEFINITION_NAME:-}" ]; then
        warning "Job definition name not available, skipping"
        return
    fi
    
    log "Deactivating job definitions: $BATCH_JOB_DEFINITION_NAME"
    
    # Get all revisions of the job definition
    JOB_DEF_ARNS=$(aws batch describe-job-definitions \
        --job-definition-name ${BATCH_JOB_DEFINITION_NAME} \
        --query 'jobDefinitions[*].jobDefinitionArn' --output text 2>/dev/null || echo "")
    
    if [ -n "$JOB_DEF_ARNS" ]; then
        for ARN in $JOB_DEF_ARNS; do
            log "Deactivating job definition: $ARN"
            aws batch deregister-job-definition \
                --job-definition $ARN 2>/dev/null || warning "Failed to deactivate job definition"
        done
        success "Job definitions deactivated"
    else
        log "No job definitions found to deactivate"
    fi
}

# Function to clean up IAM resources
cleanup_iam_resources() {
    log "Cleaning up IAM resources..."
    
    # Remove role from instance profile
    if [ -n "${BATCH_INSTANCE_PROFILE_NAME:-}" ] && [ -n "${BATCH_INSTANCE_ROLE_NAME:-}" ]; then
        log "Removing role from instance profile..."
        aws iam remove-role-from-instance-profile \
            --instance-profile-name ${BATCH_INSTANCE_PROFILE_NAME} \
            --role-name ${BATCH_INSTANCE_ROLE_NAME} 2>/dev/null || warning "Failed to remove role from instance profile"
    fi
    
    # Delete instance profile
    if [ -n "${BATCH_INSTANCE_PROFILE_NAME:-}" ]; then
        log "Deleting instance profile: $BATCH_INSTANCE_PROFILE_NAME"
        aws iam delete-instance-profile \
            --instance-profile-name ${BATCH_INSTANCE_PROFILE_NAME} 2>/dev/null || warning "Failed to delete instance profile"
    fi
    
    # Detach policies and delete service role
    if [ -n "${BATCH_SERVICE_ROLE_NAME:-}" ]; then
        log "Cleaning up Batch service role: $BATCH_SERVICE_ROLE_NAME"
        aws iam detach-role-policy \
            --role-name ${BATCH_SERVICE_ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole 2>/dev/null || warning "Failed to detach policy from service role"
        
        aws iam delete-role --role-name ${BATCH_SERVICE_ROLE_NAME} 2>/dev/null || warning "Failed to delete service role"
    fi
    
    # Detach policies and delete instance role
    if [ -n "${BATCH_INSTANCE_ROLE_NAME:-}" ]; then
        log "Cleaning up ECS instance role: $BATCH_INSTANCE_ROLE_NAME"
        aws iam detach-role-policy \
            --role-name ${BATCH_INSTANCE_ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role 2>/dev/null || warning "Failed to detach policy from instance role"
        
        aws iam delete-role --role-name ${BATCH_INSTANCE_ROLE_NAME} 2>/dev/null || warning "Failed to delete instance role"
    fi
    
    success "IAM resources cleanup completed"
}

# Function to delete security group
delete_security_group() {
    if [ -z "${SECURITY_GROUP_ID:-}" ]; then
        warning "Security group ID not available, skipping"
        return
    fi
    
    log "Deleting security group: $SECURITY_GROUP_ID"
    
    # Wait a bit for any ENIs to be released
    log "Waiting for network interfaces to be released..."
    sleep 30
    
    # Retry deletion a few times as ENIs might still be attached
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if aws ec2 delete-security-group --group-id ${SECURITY_GROUP_ID} 2>/dev/null; then
            success "Security group deleted"
            break
        else
            if [ $attempt -eq $max_attempts ]; then
                warning "Failed to delete security group after $max_attempts attempts"
                warning "It may have dependencies or network interfaces still attached"
                warning "You can manually delete it later from the AWS console"
            else
                log "Attempt $attempt failed, retrying in 30 seconds..."
                sleep 30
                ((attempt++))
            fi
        fi
    done
}

# Function to delete CloudWatch resources
cleanup_cloudwatch() {
    log "Cleaning up CloudWatch resources..."
    
    # Delete log group
    log "Deleting CloudWatch log group: /aws/batch/job"
    aws logs delete-log-group \
        --log-group-name /aws/batch/job 2>/dev/null || warning "Failed to delete log group or group doesn't exist"
    
    # Delete CloudWatch alarms
    if [ -n "${ALARM_FAILURES:-}" ]; then
        log "Deleting CloudWatch alarm: $ALARM_FAILURES"
        aws cloudwatch delete-alarms \
            --alarm-names "$ALARM_FAILURES" 2>/dev/null || warning "Failed to delete alarm or alarm doesn't exist"
    fi
    
    if [ -n "${ALARM_UTILIZATION:-}" ]; then
        log "Deleting CloudWatch alarm: $ALARM_UTILIZATION"
        aws cloudwatch delete-alarms \
            --alarm-names "$ALARM_UTILIZATION" 2>/dev/null || warning "Failed to delete alarm or alarm doesn't exist"
    fi
    
    success "CloudWatch resources cleanup completed"
}

# Function to delete ECR repository
delete_ecr_repository() {
    if [ -z "${ECR_REPO_NAME:-}" ]; then
        warning "ECR repository name not available, skipping"
        return
    fi
    
    log "Deleting ECR repository: $ECR_REPO_NAME"
    
    # Delete ECR repository (force delete to remove all images)
    aws ecr delete-repository \
        --repository-name ${ECR_REPO_NAME} \
        --force 2>/dev/null || warning "Failed to delete ECR repository or repository doesn't exist"
    
    success "ECR repository deleted"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    if [ -f ".batch_deployment_vars" ]; then
        rm -f .batch_deployment_vars
        log "Removed deployment variables file"
    fi
    
    success "Temporary files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_issues=0
    
    # Check if compute environment still exists
    if [ -n "${BATCH_COMPUTE_ENV_NAME:-}" ]; then
        if aws batch describe-compute-environments --compute-environments ${BATCH_COMPUTE_ENV_NAME} &>/dev/null; then
            warning "Compute environment still exists: $BATCH_COMPUTE_ENV_NAME"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if job queue still exists
    if [ -n "${BATCH_JOB_QUEUE_NAME:-}" ]; then
        if aws batch describe-job-queues --job-queues ${BATCH_JOB_QUEUE_NAME} &>/dev/null; then
            warning "Job queue still exists: $BATCH_JOB_QUEUE_NAME"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if ECR repository still exists
    if [ -n "${ECR_REPO_NAME:-}" ]; then
        if aws ecr describe-repositories --repository-names ${ECR_REPO_NAME} &>/dev/null; then
            warning "ECR repository still exists: $ECR_REPO_NAME"
            ((cleanup_issues++))
        fi
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        success "Cleanup verification passed"
    else
        warning "Found $cleanup_issues issues during cleanup verification"
        warning "Some resources may need manual cleanup"
        log "Check the AWS console to verify all resources are deleted"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "The following resources have been cleaned up:"
    echo "- AWS Batch compute environment and job queue"
    echo "- Job definitions (deactivated)"
    echo "- ECR repository and container images"
    echo "- IAM roles and instance profiles"
    echo "- Security groups"
    echo "- CloudWatch log groups and alarms"
    echo "- Temporary files"
    echo ""
    
    warning "Note: Some resources may take a few minutes to be fully deleted."
    warning "Verify in the AWS console that all resources are removed."
    echo ""
    success "Cleanup completed!"
}

# Function to handle script interruption
cleanup_on_interrupt() {
    error "Cleanup interrupted. Some resources may not be fully deleted."
    error "Please check the AWS console and manually delete any remaining resources."
    exit 1
}

# Trap interruption signals
trap cleanup_on_interrupt INT TERM

# Main cleanup function
main() {
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN MODE - Starting AWS Batch infrastructure cleanup simulation..."
    else
        log "Starting AWS Batch infrastructure cleanup..."
    fi
    
    check_prerequisites
    load_environment
    confirm_deletion
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN completed - no actual resources were modified"
        exit 0
    fi
    
    # Wait for any pending operations to complete
    log "Waiting 30 seconds for any pending operations to complete..."
    sleep 30
    
    cancel_running_jobs
    delete_job_queue
    delete_compute_environment
    delete_job_definitions
    cleanup_iam_resources
    delete_security_group
    cleanup_cloudwatch
    delete_ecr_repository
    cleanup_temp_files
    verify_cleanup
    display_cleanup_summary
}

# Run main function
main "$@"