#!/bin/bash

# AWS Batch with Spot Instances - Cleanup/Destroy Script
# This script safely removes all resources created by the deployment script

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI not configured or authentication failed"
        exit 1
    fi
}

# Function to prompt for confirmation
confirm() {
    local prompt="$1"
    local default="${2:-N}"
    
    if [ "${FORCE_DESTROY:-false}" = "true" ]; then
        log "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    while true; do
        echo -n "$prompt [y/N]: "
        read -r response
        response=${response:-$default}
        
        case "$response" in
            [yY]|[yY][eE][sS])
                return 0
                ;;
            [nN]|[nN][oO])
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local resource_name=$2
    local max_attempts=${3:-30}
    local attempt=1
    
    log "Waiting for $resource_type '$resource_name' to be deleted..."
    
    while [ $attempt -le $max_attempts ]; do
        case $resource_type in
            "compute-environment")
                if ! aws batch describe-compute-environments --compute-environments "$resource_name" >/dev/null 2>&1; then
                    success "$resource_type '$resource_name' deleted"
                    return 0
                fi
                ;;
            "job-queue")
                if ! aws batch describe-job-queues --job-queues "$resource_name" >/dev/null 2>&1; then
                    success "$resource_type '$resource_name' deleted"
                    return 0
                fi
                ;;
            "ecr-repository")
                if ! aws ecr describe-repositories --repository-names "$resource_name" >/dev/null 2>&1; then
                    success "$resource_type '$resource_name' deleted"
                    return 0
                fi
                ;;
        esac
        
        log "Attempt $attempt/$max_attempts: Waiting for $resource_type deletion..."
        sleep 10
        ((attempt++))
    done
    
    warn "$resource_type '$resource_name' deletion timed out"
    return 1
}

# Function to get resource info from deployment file
get_deployment_info() {
    if [ -f "deployment_info.txt" ]; then
        export ECR_REPO_NAME=$(grep "ECR Repository:" deployment_info.txt | cut -d' ' -f4)
        export COMPUTE_ENV_NAME=$(grep "Compute Environment:" deployment_info.txt | cut -d' ' -f4)
        export JOB_QUEUE_NAME=$(grep "Job Queue:" deployment_info.txt | cut -d' ' -f4)
        export JOB_DEFINITION_NAME=$(grep "Job Definition:" deployment_info.txt | cut -d' ' -f4)
        export SECURITY_GROUP_ID=$(grep "Security Group:" deployment_info.txt | cut -d' ' -f4)
        
        log "Loaded deployment information from deployment_info.txt"
    else
        warn "deployment_info.txt not found, attempting to discover resources..."
        
        # Try to discover resources using naming pattern
        local timestamp=$(date +%s)
        
        # Get current AWS account and region
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        export AWS_REGION=$(aws configure get region)
        
        # Try to find resources by pattern
        export ECR_REPO_NAME=$(aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName, `batch-demo-`)].repositoryName' --output text | head -1)
        export COMPUTE_ENV_NAME=$(aws batch describe-compute-environments --query 'computeEnvironments[?starts_with(computeEnvironmentName, `spot-compute-env-`)].computeEnvironmentName' --output text | head -1)
        export JOB_QUEUE_NAME=$(aws batch describe-job-queues --query 'jobQueues[?starts_with(jobQueueName, `spot-job-queue-`)].jobQueueName' --output text | head -1)
        export JOB_DEFINITION_NAME=$(aws batch describe-job-definitions --query 'jobDefinitions[?starts_with(jobDefinitionName, `batch-job-def-`)].jobDefinitionName' --output text | head -1)
        export SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --query 'SecurityGroups[?starts_with(GroupName, `batch-sg-`)].GroupId' --output text | head -1)
        
        if [ -z "$ECR_REPO_NAME" ] && [ -z "$COMPUTE_ENV_NAME" ] && [ -z "$JOB_QUEUE_NAME" ]; then
            warn "Could not discover resources automatically. Please provide resource names manually."
            return 1
        fi
    fi
}

# Function to list all jobs in a queue
list_jobs() {
    local queue_name=$1
    local job_status=${2:-"ALL"}
    
    if [ -z "$queue_name" ]; then
        return 0
    fi
    
    case $job_status in
        "ALL")
            aws batch list-jobs --job-queue "$queue_name" --job-status SUBMITTED --query 'jobList[].jobId' --output text 2>/dev/null || true
            aws batch list-jobs --job-queue "$queue_name" --job-status PENDING --query 'jobList[].jobId' --output text 2>/dev/null || true
            aws batch list-jobs --job-queue "$queue_name" --job-status RUNNABLE --query 'jobList[].jobId' --output text 2>/dev/null || true
            aws batch list-jobs --job-queue "$queue_name" --job-status RUNNING --query 'jobList[].jobId' --output text 2>/dev/null || true
            ;;
        *)
            aws batch list-jobs --job-queue "$queue_name" --job-status "$job_status" --query 'jobList[].jobId' --output text 2>/dev/null || true
            ;;
    esac
}

# Function to cancel jobs
cancel_jobs() {
    local queue_name=$1
    
    if [ -z "$queue_name" ]; then
        return 0
    fi
    
    log "Canceling jobs in queue: $queue_name"
    
    # Get all active jobs
    local active_jobs=$(list_jobs "$queue_name")
    
    if [ -n "$active_jobs" ]; then
        log "Found active jobs, canceling them..."
        for job_id in $active_jobs; do
            if [ -n "$job_id" ]; then
                aws batch cancel-job --job-id "$job_id" --reason "Cleanup script" 2>/dev/null || true
                log "Canceled job: $job_id"
            fi
        done
        
        # Wait for jobs to be canceled
        log "Waiting for jobs to be canceled..."
        sleep 30
    else
        log "No active jobs found in queue"
    fi
}

# Header
echo "=========================================="
echo "AWS Batch Spot Instance Cleanup Script"
echo "=========================================="

# Prerequisites check
log "Checking prerequisites..."

if ! command_exists aws; then
    error "AWS CLI is not installed"
    exit 1
fi

check_aws_auth

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY=true
            shift
            ;;
        --dry-run)
            export DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force     Skip confirmation prompts"
            echo "  --dry-run   Show what would be deleted without actually deleting"
            echo "  --help      Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Get deployment information
get_deployment_info

# Show what will be deleted
echo ""
echo "The following resources will be deleted:"
echo "----------------------------------------"
[ -n "${ECR_REPO_NAME:-}" ] && echo "📦 ECR Repository: $ECR_REPO_NAME"
[ -n "${COMPUTE_ENV_NAME:-}" ] && echo "💻 Compute Environment: $COMPUTE_ENV_NAME"
[ -n "${JOB_QUEUE_NAME:-}" ] && echo "📋 Job Queue: $JOB_QUEUE_NAME"
[ -n "${JOB_DEFINITION_NAME:-}" ] && echo "📄 Job Definition: $JOB_DEFINITION_NAME"
[ -n "${SECURITY_GROUP_ID:-}" ] && echo "🔒 Security Group: $SECURITY_GROUP_ID"
echo "👥 IAM Roles: AWSBatchServiceRole, ecsInstanceRole, BatchJobExecutionRole"
echo "🗂️  Local Files: deployment_info.txt"
echo ""

# Dry run mode
if [ "${DRY_RUN:-false}" = "true" ]; then
    log "DRY RUN MODE: No resources will be deleted"
    exit 0
fi

# Confirmation prompt
if ! confirm "Are you sure you want to delete these resources? This action cannot be undone."; then
    log "Cleanup canceled by user"
    exit 0
fi

log "Starting cleanup process..."

# Step 1: Cancel and wait for running jobs
if [ -n "${JOB_QUEUE_NAME:-}" ]; then
    cancel_jobs "$JOB_QUEUE_NAME"
fi

# Step 2: Disable and delete job queue
if [ -n "${JOB_QUEUE_NAME:-}" ]; then
    log "Disabling job queue: $JOB_QUEUE_NAME"
    aws batch update-job-queue --job-queue "$JOB_QUEUE_NAME" --state DISABLED 2>/dev/null || true
    
    log "Waiting for job queue to be disabled..."
    sleep 10
    
    log "Deleting job queue: $JOB_QUEUE_NAME"
    aws batch delete-job-queue --job-queue "$JOB_QUEUE_NAME" 2>/dev/null || true
    
    wait_for_deletion "job-queue" "$JOB_QUEUE_NAME" 20
fi

# Step 3: Disable and delete compute environment
if [ -n "${COMPUTE_ENV_NAME:-}" ]; then
    log "Disabling compute environment: $COMPUTE_ENV_NAME"
    aws batch update-compute-environment --compute-environment "$COMPUTE_ENV_NAME" --state DISABLED 2>/dev/null || true
    
    log "Waiting for compute environment to be disabled..."
    sleep 30
    
    log "Deleting compute environment: $COMPUTE_ENV_NAME"
    aws batch delete-compute-environment --compute-environment "$COMPUTE_ENV_NAME" 2>/dev/null || true
    
    wait_for_deletion "compute-environment" "$COMPUTE_ENV_NAME" 30
fi

# Step 4: Deregister job definition
if [ -n "${JOB_DEFINITION_NAME:-}" ]; then
    log "Deregistering job definition: $JOB_DEFINITION_NAME"
    aws batch deregister-job-definition --job-definition "$JOB_DEFINITION_NAME" 2>/dev/null || true
    success "Job definition deregistered"
fi

# Step 5: Delete ECR repository
if [ -n "${ECR_REPO_NAME:-}" ]; then
    log "Deleting ECR repository: $ECR_REPO_NAME"
    aws ecr delete-repository --repository-name "$ECR_REPO_NAME" --force 2>/dev/null || true
    
    wait_for_deletion "ecr-repository" "$ECR_REPO_NAME" 10
fi

# Step 6: Delete security group
if [ -n "${SECURITY_GROUP_ID:-}" ]; then
    log "Deleting security group: $SECURITY_GROUP_ID"
    aws ec2 delete-security-group --group-id "$SECURITY_GROUP_ID" 2>/dev/null || true
    success "Security group deleted"
fi

# Step 7: Clean up IAM resources
log "Cleaning up IAM resources..."

# Remove role from instance profile
aws iam remove-role-from-instance-profile \
    --instance-profile-name ecsInstanceRole \
    --role-name ecsInstanceRole 2>/dev/null || true

# Delete instance profile
aws iam delete-instance-profile \
    --instance-profile-name ecsInstanceRole 2>/dev/null || true

# Detach policies from roles
aws iam detach-role-policy \
    --role-name AWSBatchServiceRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole 2>/dev/null || true

aws iam detach-role-policy \
    --role-name ecsInstanceRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role 2>/dev/null || true

aws iam detach-role-policy \
    --role-name BatchJobExecutionRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || true

# Delete IAM roles
aws iam delete-role --role-name AWSBatchServiceRole 2>/dev/null || true
aws iam delete-role --role-name ecsInstanceRole 2>/dev/null || true
aws iam delete-role --role-name BatchJobExecutionRole 2>/dev/null || true

success "IAM resources cleaned up"

# Step 8: Clean up local files
log "Cleaning up local files..."
rm -f deployment_info.txt batch_app.py Dockerfile
success "Local files cleaned up"

# Step 9: Check for any remaining CloudWatch log groups
log "Checking for CloudWatch log groups..."
log_groups=$(aws logs describe-log-groups --log-group-name-prefix /aws/batch/job --query 'logGroups[].logGroupName' --output text 2>/dev/null || true)

if [ -n "$log_groups" ]; then
    warn "Found CloudWatch log groups that may contain job logs:"
    for log_group in $log_groups; do
        echo "  - $log_group"
    done
    echo ""
    if confirm "Delete these CloudWatch log groups?"; then
        for log_group in $log_groups; do
            aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || true
            log "Deleted log group: $log_group"
        done
    else
        warn "CloudWatch log groups preserved (may incur storage costs)"
    fi
fi

# Final summary
success "Cleanup completed successfully!"
echo ""
echo "=========================================="
echo "Cleanup Summary"
echo "=========================================="
echo "✅ Jobs canceled and queues deleted"
echo "✅ Compute environments deleted"
echo "✅ Job definitions deregistered"
echo "✅ ECR repositories deleted"
echo "✅ Security groups deleted"
echo "✅ IAM roles and policies cleaned up"
echo "✅ Local files removed"
echo ""
echo "🎉 All AWS Batch resources have been successfully removed!"
echo "💰 You should no longer incur costs for these resources."
echo ""
echo "⚠️  Note: Some CloudWatch logs may persist and incur minimal storage costs."
echo "   You can delete them manually if needed."
echo "=========================================="