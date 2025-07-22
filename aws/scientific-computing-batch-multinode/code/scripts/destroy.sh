#!/bin/bash

#####################################################################
# AWS Batch Multi-Node Scientific Computing Cleanup Script
#####################################################################
# This script safely removes all resources created by the deployment
# script, including Batch environments, networking, storage, and
# container images.
#
# Features:
# - Safe deletion with confirmation prompts
# - Handles resource dependencies properly
# - Comprehensive cleanup verification
# - Supports force mode for automation
# - Detailed logging of cleanup operations
#
# Usage: ./destroy.sh [--force] [--resource-file FILE]
#####################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
RESOURCES_FILE="${SCRIPT_DIR}/deployed-resources.txt"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Flags
FORCE_MODE=false
INTERACTIVE_MODE=true
VERIFY_DELETION=true

#####################################################################
# Utility Functions
#####################################################################

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

confirm_action() {
    if [[ "$FORCE_MODE" == "true" ]]; then
        return 0
    fi
    
    local message="$1"
    echo -e "${YELLOW}$message${NC}"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Operation cancelled by user"
        return 1
    fi
    return 0
}

check_aws_connectivity() {
    log "Checking AWS connectivity..."
    
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured or invalid"
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    if [[ -z "$ACCOUNT_ID" ]]; then
        error "Unable to retrieve AWS account ID"
        exit 1
    fi
    
    log "AWS connectivity verified (Account: $ACCOUNT_ID)"
}

load_resources() {
    if [[ ! -f "$RESOURCES_FILE" ]]; then
        error "Resource file not found: $RESOURCES_FILE"
        error "Unable to determine which resources to clean up"
        exit 1
    fi
    
    log "Loading resource information from: $RESOURCES_FILE"
    source "$RESOURCES_FILE"
    
    # Verify essential variables are loaded
    if [[ -z "${CLUSTER_NAME:-}" ]]; then
        error "CLUSTER_NAME not found in resource file"
        exit 1
    fi
    
    if [[ -z "${AWS_REGION:-}" ]]; then
        error "AWS_REGION not found in resource file"
        exit 1
    fi
    
    # Set AWS region
    export AWS_DEFAULT_REGION="$AWS_REGION"
    
    log "Resources loaded successfully for cluster: $CLUSTER_NAME"
    log "Region: $AWS_REGION"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely remove all AWS Batch scientific computing resources.

OPTIONS:
    --force                  Skip confirmation prompts (dangerous!)
    --resource-file FILE     Path to resource file (default: $RESOURCES_FILE)
    --no-verify             Skip deletion verification
    --help                  Show this help message

EXAMPLES:
    $0                      # Interactive cleanup with confirmations
    $0 --force              # Automated cleanup without prompts
    $0 --resource-file /path/to/resources.txt

WARNING: This script will permanently delete AWS resources and cannot be undone!

EOF
}

#####################################################################
# Resource Cleanup Functions
#####################################################################

cancel_running_jobs() {
    log "Checking for running jobs and cancelling them..."
    
    if [[ -z "${JOB_QUEUE_NAME:-}" ]]; then
        warn "JOB_QUEUE_NAME not set, skipping job cancellation"
        return 0
    fi
    
    # Get all running and submitted jobs
    local running_jobs submitted_jobs
    
    running_jobs=$(aws batch list-jobs \
        --job-queue "$JOB_QUEUE_NAME" \
        --job-status RUNNING \
        --query 'jobSummaryList[].jobId' \
        --output text 2>/dev/null || echo "")
    
    submitted_jobs=$(aws batch list-jobs \
        --job-queue "$JOB_QUEUE_NAME" \
        --job-status SUBMITTED \
        --query 'jobSummaryList[].jobId' \
        --output text 2>/dev/null || echo "")
    
    local all_jobs="$running_jobs $submitted_jobs"
    
    if [[ -n "$all_jobs" && "$all_jobs" != " " ]]; then
        info "Found active jobs to cancel: $all_jobs"
        
        if ! confirm_action "Cancel all running and submitted jobs?"; then
            warn "Skipping job cancellation - this may prevent proper cleanup"
            return 0
        fi
        
        for job_id in $all_jobs; do
            if [[ -n "$job_id" ]]; then
                info "Cancelling job: $job_id"
                aws batch terminate-job \
                    --job-id "$job_id" \
                    --reason "Resource cleanup - terminating for environment deletion" \
                    2>/dev/null || warn "Failed to cancel job: $job_id"
            fi
        done
        
        info "Waiting for jobs to terminate..."
        sleep 30
    else
        info "No active jobs found"
    fi
    
    success "Job cancellation completed"
}

disable_job_queue() {
    log "Disabling and deleting job queue..."
    
    if [[ -z "${JOB_QUEUE_NAME:-}" ]]; then
        warn "JOB_QUEUE_NAME not set, skipping job queue deletion"
        return 0
    fi
    
    # Check if job queue exists
    if ! aws batch describe-job-queues \
        --job-queues "$JOB_QUEUE_NAME" \
        --query 'jobQueues[0].jobQueueName' \
        --output text &>/dev/null; then
        info "Job queue $JOB_QUEUE_NAME does not exist or already deleted"
        return 0
    fi
    
    info "Disabling job queue: $JOB_QUEUE_NAME"
    aws batch update-job-queue \
        --job-queue "$JOB_QUEUE_NAME" \
        --state DISABLED \
        2>/dev/null || warn "Failed to disable job queue"
    
    info "Waiting for job queue to be disabled..."
    sleep 30
    
    info "Deleting job queue: $JOB_QUEUE_NAME"
    aws batch delete-job-queue \
        --job-queue "$JOB_QUEUE_NAME" \
        2>/dev/null || warn "Failed to delete job queue"
    
    success "Job queue deletion completed"
}

delete_compute_environment() {
    log "Disabling and deleting compute environment..."
    
    if [[ -z "${COMPUTE_ENV_NAME:-}" ]]; then
        warn "COMPUTE_ENV_NAME not set, skipping compute environment deletion"
        return 0
    fi
    
    # Check if compute environment exists
    if ! aws batch describe-compute-environments \
        --compute-environments "$COMPUTE_ENV_NAME" \
        --query 'computeEnvironments[0].computeEnvironmentName' \
        --output text &>/dev/null; then
        info "Compute environment $COMPUTE_ENV_NAME does not exist or already deleted"
        return 0
    fi
    
    info "Disabling compute environment: $COMPUTE_ENV_NAME"
    aws batch update-compute-environment \
        --compute-environment "$COMPUTE_ENV_NAME" \
        --state DISABLED \
        2>/dev/null || warn "Failed to disable compute environment"
    
    info "Waiting for compute environment to be disabled..."
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        local state=$(aws batch describe-compute-environments \
            --compute-environments "$COMPUTE_ENV_NAME" \
            --query 'computeEnvironments[0].state' \
            --output text 2>/dev/null || echo "")
        
        if [[ "$state" == "DISABLED" ]]; then
            break
        fi
        
        sleep 10
        wait_time=$((wait_time + 10))
        info "Still waiting for compute environment to disable... (${wait_time}s)"
    done
    
    info "Deleting compute environment: $COMPUTE_ENV_NAME"
    aws batch delete-compute-environment \
        --compute-environment "$COMPUTE_ENV_NAME" \
        2>/dev/null || warn "Failed to delete compute environment"
    
    success "Compute environment deletion completed"
}

delete_job_definitions() {
    log "Deregistering job definitions..."
    
    local job_def_names=(
        "${CLUSTER_NAME:-}-mpi-job"
        "${CLUSTER_NAME:-}-parameterized-mpi"
    )
    
    for job_def_name in "${job_def_names[@]}"; do
        if [[ -n "$job_def_name" && "$job_def_name" != "-mpi-job" && "$job_def_name" != "-parameterized-mpi" ]]; then
            info "Checking job definition: $job_def_name"
            
            # Get all revisions of the job definition
            local revisions
            revisions=$(aws batch describe-job-definitions \
                --job-definition-name "$job_def_name" \
                --status ACTIVE \
                --query 'jobDefinitions[].revision' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$revisions" ]]; then
                for revision in $revisions; do
                    info "Deregistering job definition: $job_def_name:$revision"
                    aws batch deregister-job-definition \
                        --job-definition "$job_def_name:$revision" \
                        2>/dev/null || warn "Failed to deregister $job_def_name:$revision"
                done
            else
                info "No active revisions found for: $job_def_name"
            fi
        fi
    done
    
    success "Job definition deregistration completed"
}

delete_ecr_repository() {
    log "Deleting ECR repository and images..."
    
    if [[ -z "${ECR_REPO_NAME:-}" ]]; then
        warn "ECR_REPO_NAME not set, skipping ECR repository deletion"
        return 0
    fi
    
    # Check if repository exists
    if ! aws ecr describe-repositories \
        --repository-names "$ECR_REPO_NAME" \
        --query 'repositories[0].repositoryName' \
        --output text &>/dev/null; then
        info "ECR repository $ECR_REPO_NAME does not exist or already deleted"
        return 0
    fi
    
    if confirm_action "Delete ECR repository '$ECR_REPO_NAME' and all container images?"; then
        info "Deleting ECR repository: $ECR_REPO_NAME"
        aws ecr delete-repository \
            --repository-name "$ECR_REPO_NAME" \
            --force \
            2>/dev/null || warn "Failed to delete ECR repository"
        
        success "ECR repository deletion completed"
    else
        warn "Skipping ECR repository deletion"
    fi
}

delete_efs_filesystem() {
    log "Deleting EFS filesystem and mount targets..."
    
    if [[ -z "${EFS_ID:-}" ]]; then
        warn "EFS_ID not set, skipping EFS deletion"
        return 0
    fi
    
    # Check if EFS exists
    if ! aws efs describe-file-systems \
        --file-system-id "$EFS_ID" \
        --query 'FileSystems[0].FileSystemId' \
        --output text &>/dev/null; then
        info "EFS filesystem $EFS_ID does not exist or already deleted"
        return 0
    fi
    
    if confirm_action "Delete EFS filesystem '$EFS_ID' and all data?"; then
        # Delete mount targets first
        info "Deleting EFS mount targets..."
        local mount_targets
        mount_targets=$(aws efs describe-mount-targets \
            --file-system-id "$EFS_ID" \
            --query 'MountTargets[].MountTargetId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$mount_targets" ]]; then
            for mt_id in $mount_targets; do
                if [[ -n "$mt_id" ]]; then
                    info "Deleting mount target: $mt_id"
                    aws efs delete-mount-target \
                        --mount-target-id "$mt_id" \
                        2>/dev/null || warn "Failed to delete mount target: $mt_id"
                fi
            done
            
            info "Waiting for mount targets to be deleted..."
            sleep 30
        fi
        
        # Delete the filesystem
        info "Deleting EFS filesystem: $EFS_ID"
        aws efs delete-file-system \
            --file-system-id "$EFS_ID" \
            2>/dev/null || warn "Failed to delete EFS filesystem"
        
        success "EFS filesystem deletion completed"
    else
        warn "Skipping EFS deletion"
    fi
}

delete_iam_resources() {
    log "Deleting IAM roles and policies..."
    
    local iam_resources=(
        "${CLUSTER_NAME:-}-batch-instance-profile"
        "${CLUSTER_NAME:-}-batch-instance-role"
        "${CLUSTER_NAME:-}-batch-service-role"
    )
    
    # Remove role from instance profile first
    if [[ -n "${CLUSTER_NAME:-}" ]]; then
        info "Removing role from instance profile"
        aws iam remove-role-from-instance-profile \
            --instance-profile-name "${CLUSTER_NAME}-batch-instance-profile" \
            --role-name "${CLUSTER_NAME}-batch-instance-role" \
            2>/dev/null || warn "Failed to remove role from instance profile"
        
        # Delete instance profile
        info "Deleting instance profile: ${CLUSTER_NAME}-batch-instance-profile"
        aws iam delete-instance-profile \
            --instance-profile-name "${CLUSTER_NAME}-batch-instance-profile" \
            2>/dev/null || warn "Failed to delete instance profile"
        
        # Detach policies and delete roles
        info "Detaching policies from instance role"
        aws iam detach-role-policy \
            --role-name "${CLUSTER_NAME}-batch-instance-role" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role \
            2>/dev/null || warn "Failed to detach instance role policy"
        
        info "Deleting instance role: ${CLUSTER_NAME}-batch-instance-role"
        aws iam delete-role \
            --role-name "${CLUSTER_NAME}-batch-instance-role" \
            2>/dev/null || warn "Failed to delete instance role"
        
        info "Detaching policies from service role"
        aws iam detach-role-policy \
            --role-name "${CLUSTER_NAME}-batch-service-role" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole \
            2>/dev/null || warn "Failed to detach service role policy"
        
        info "Deleting service role: ${CLUSTER_NAME}-batch-service-role"
        aws iam delete-role \
            --role-name "${CLUSTER_NAME}-batch-service-role" \
            2>/dev/null || warn "Failed to delete service role"
    fi
    
    success "IAM resources deletion completed"
}

delete_monitoring_resources() {
    log "Deleting monitoring and logging resources..."
    
    # Delete CloudWatch dashboard
    if [[ -n "${CLUSTER_NAME:-}" ]]; then
        info "Deleting CloudWatch dashboard: ${CLUSTER_NAME}-monitoring"
        aws cloudwatch delete-dashboards \
            --dashboard-names "${CLUSTER_NAME}-monitoring" \
            2>/dev/null || warn "Failed to delete CloudWatch dashboard"
        
        # Delete CloudWatch alarms
        info "Deleting CloudWatch alarm: ${CLUSTER_NAME}-failed-jobs"
        aws cloudwatch delete-alarms \
            --alarm-names "${CLUSTER_NAME}-failed-jobs" \
            2>/dev/null || warn "Failed to delete CloudWatch alarm"
    fi
    
    success "Monitoring resources deletion completed"
}

delete_networking_resources() {
    log "Deleting networking resources..."
    
    # Delete security group
    if [[ -n "${SG_ID:-}" ]]; then
        info "Deleting security group: $SG_ID"
        aws ec2 delete-security-group \
            --group-id "$SG_ID" \
            2>/dev/null || warn "Failed to delete security group"
    fi
    
    # Detach and delete internet gateway
    if [[ -n "${IGW_ID:-}" && -n "${VPC_ID:-}" ]]; then
        info "Detaching internet gateway: $IGW_ID"
        aws ec2 detach-internet-gateway \
            --internet-gateway-id "$IGW_ID" \
            --vpc-id "$VPC_ID" \
            2>/dev/null || warn "Failed to detach internet gateway"
        
        info "Deleting internet gateway: $IGW_ID"
        aws ec2 delete-internet-gateway \
            --internet-gateway-id "$IGW_ID" \
            2>/dev/null || warn "Failed to delete internet gateway"
    fi
    
    # Delete subnet
    if [[ -n "${SUBNET_ID:-}" ]]; then
        info "Deleting subnet: $SUBNET_ID"
        aws ec2 delete-subnet \
            --subnet-id "$SUBNET_ID" \
            2>/dev/null || warn "Failed to delete subnet"
    fi
    
    # Delete VPC
    if [[ -n "${VPC_ID:-}" ]]; then
        info "Deleting VPC: $VPC_ID"
        aws ec2 delete-vpc \
            --vpc-id "$VPC_ID" \
            2>/dev/null || warn "Failed to delete VPC"
    fi
    
    success "Networking resources deletion completed"
}

cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_clean=(
        "${SCRIPT_DIR}/submit-scientific-job.sh"
        "$RESOURCES_FILE"
    )
    
    for file in "${files_to_clean[@]}"; do
        if [[ -f "$file" ]]; then
            info "Removing file: $file"
            rm -f "$file" || warn "Failed to remove $file"
        fi
    done
    
    success "Local file cleanup completed"
}

verify_deletion() {
    if [[ "$VERIFY_DELETION" != "true" ]]; then
        return 0
    fi
    
    log "Verifying resource deletion..."
    
    local verification_failed=false
    
    # Check Batch resources
    if [[ -n "${JOB_QUEUE_NAME:-}" ]]; then
        if aws batch describe-job-queues --job-queues "$JOB_QUEUE_NAME" &>/dev/null; then
            warn "Job queue still exists: $JOB_QUEUE_NAME"
            verification_failed=true
        fi
    fi
    
    if [[ -n "${COMPUTE_ENV_NAME:-}" ]]; then
        if aws batch describe-compute-environments --compute-environments "$COMPUTE_ENV_NAME" &>/dev/null; then
            warn "Compute environment still exists: $COMPUTE_ENV_NAME"
            verification_failed=true
        fi
    fi
    
    # Check ECR repository
    if [[ -n "${ECR_REPO_NAME:-}" ]]; then
        if aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" &>/dev/null; then
            warn "ECR repository still exists: $ECR_REPO_NAME"
            verification_failed=true
        fi
    fi
    
    # Check EFS filesystem
    if [[ -n "${EFS_ID:-}" ]]; then
        if aws efs describe-file-systems --file-system-id "$EFS_ID" &>/dev/null; then
            warn "EFS filesystem still exists: $EFS_ID"
            verification_failed=true
        fi
    fi
    
    # Check VPC
    if [[ -n "${VPC_ID:-}" ]]; then
        if aws ec2 describe-vpcs --vpc-ids "$VPC_ID" &>/dev/null; then
            warn "VPC still exists: $VPC_ID"
            verification_failed=true
        fi
    fi
    
    if [[ "$verification_failed" == "true" ]]; then
        warn "Some resources may not have been deleted completely"
        warn "Please check the AWS console and delete any remaining resources manually"
    else
        success "All resources have been successfully deleted"
    fi
}

print_cleanup_summary() {
    log "Cleanup operation completed!"
    echo ""
    echo "==================================================================="
    echo "AWS Batch Scientific Computing Environment Cleanup Summary"
    echo "==================================================================="
    echo "Cluster Name:           ${CLUSTER_NAME:-unknown}"
    echo "AWS Region:             ${AWS_REGION:-unknown}"
    echo "Cleanup Started:        $(head -2 "$LOG_FILE" | tail -1 | cut -d' ' -f3-)"
    echo "Cleanup Completed:      $(date)"
    echo ""
    echo "Resources Cleaned Up:"
    echo "  ✓ Running and submitted jobs cancelled"
    echo "  ✓ Job queue disabled and deleted"
    echo "  ✓ Compute environment disabled and deleted"
    echo "  ✓ Job definitions deregistered"
    echo "  ✓ ECR repository and images deleted"
    echo "  ✓ EFS filesystem and mount targets deleted"
    echo "  ✓ IAM roles and instance profiles deleted"
    echo "  ✓ CloudWatch dashboard and alarms deleted"
    echo "  ✓ VPC, subnets, and security groups deleted"
    echo "  ✓ Local files cleaned up"
    echo ""
    echo "Log File:               $LOG_FILE"
    echo ""
    echo "==================================================================="
    echo ""
    success "All AWS Batch scientific computing resources have been removed!"
    
    if [[ -f "$RESOURCES_FILE" ]]; then
        info "Resource file has been removed: $RESOURCES_FILE"
    fi
}

#####################################################################
# Main Execution
#####################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_MODE=true
                INTERACTIVE_MODE=false
                shift
                ;;
            --resource-file)
                RESOURCES_FILE="$2"
                shift 2
                ;;
            --no-verify)
                VERIFY_DELETION=false
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

main() {
    # Initialize log file
    echo "AWS Batch Multi-Node Scientific Computing Cleanup" > "$LOG_FILE"
    echo "Started at: $(date)" >> "$LOG_FILE"
    echo "=========================================" >> "$LOG_FILE"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Initial safety check
    if [[ "$FORCE_MODE" != "true" ]]; then
        echo ""
        echo "==================================================================="
        echo "AWS Batch Scientific Computing Environment Cleanup"
        echo "==================================================================="
        echo ""
        warn "This script will permanently delete AWS resources!"
        warn "This action cannot be undone!"
        echo ""
        if ! confirm_action "Are you sure you want to continue?"; then
            info "Cleanup cancelled by user"
            exit 0
        fi
        echo ""
    fi
    
    # Run cleanup steps
    check_aws_connectivity
    load_resources
    
    log "Starting cleanup of AWS Batch scientific computing environment..."
    log "Cluster: ${CLUSTER_NAME:-unknown}"
    log "Region: ${AWS_REGION:-unknown}"
    
    # Execute cleanup in proper order
    cancel_running_jobs
    disable_job_queue
    delete_compute_environment
    delete_job_definitions
    delete_ecr_repository
    delete_efs_filesystem
    delete_iam_resources
    delete_monitoring_resources
    delete_networking_resources
    cleanup_local_files
    verify_deletion
    print_cleanup_summary
    
    log "Cleanup completed successfully at $(date)"
}

# Run main function with all arguments
main "$@"