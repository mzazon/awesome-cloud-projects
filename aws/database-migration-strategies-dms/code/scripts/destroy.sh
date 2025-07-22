#!/bin/bash

# Cleanup script for AWS DMS Database Migration Recipe
# This script removes all DMS migration infrastructure

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ -f ".env_vars" ]]; then
        source .env_vars
        success "Environment variables loaded from .env_vars file"
    else
        warning ".env_vars file not found. You will need to provide resource identifiers manually."
        
        # Prompt for required variables if not found
        if [[ -z "$DMS_REPLICATION_INSTANCE_ID" ]]; then
            read -p "Enter DMS Replication Instance ID: " DMS_REPLICATION_INSTANCE_ID
        fi
        if [[ -z "$DMS_SUBNET_GROUP_ID" ]]; then
            read -p "Enter DMS Subnet Group ID: " DMS_SUBNET_GROUP_ID
        fi
        if [[ -z "$SOURCE_ENDPOINT_ID" ]]; then
            read -p "Enter Source Endpoint ID: " SOURCE_ENDPOINT_ID
        fi
        if [[ -z "$TARGET_ENDPOINT_ID" ]]; then
            read -p "Enter Target Endpoint ID: " TARGET_ENDPOINT_ID
        fi
        if [[ -z "$MIGRATION_TASK_ID" ]]; then
            read -p "Enter Migration Task ID: " MIGRATION_TASK_ID
        fi
        if [[ -z "$CDC_TASK_ID" ]]; then
            read -p "Enter CDC Task ID: " CDC_TASK_ID
        fi
        if [[ -z "$S3_BUCKET_NAME" ]]; then
            read -p "Enter S3 Bucket Name: " S3_BUCKET_NAME
        fi
        
        # Set defaults for optional variables
        AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
    fi
    
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Please set AWS_REGION environment variable or configure default region."
        exit 1
    fi
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
        error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to confirm destruction
confirm_destruction() {
    warning "This will permanently delete all DMS migration resources!"
    echo "Resources to be deleted:"
    echo "- DMS Replication Instance: ${DMS_REPLICATION_INSTANCE_ID}"
    echo "- DMS Subnet Group: ${DMS_SUBNET_GROUP_ID}"
    echo "- Source Endpoint: ${SOURCE_ENDPOINT_ID}"
    echo "- Target Endpoint: ${TARGET_ENDPOINT_ID}"
    echo "- Migration Task: ${MIGRATION_TASK_ID}"
    echo "- CDC Task: ${CDC_TASK_ID}"
    echo "- S3 Bucket: ${S3_BUCKET_NAME}"
    echo "- CloudWatch Log Group: dms-tasks-${DMS_REPLICATION_INSTANCE_ID}"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed, proceeding..."
}

# Function to stop and delete migration tasks
delete_migration_tasks() {
    log "Stopping and deleting migration tasks..."
    
    # Function to stop and delete a task
    stop_and_delete_task() {
        local task_id=$1
        local task_name=$2
        
        log "Processing ${task_name}: ${task_id}"
        
        # Check if task exists
        if aws dms describe-replication-tasks \
            --replication-task-identifier ${task_id} &> /dev/null; then
            
            # Get task ARN
            local task_arn=$(aws dms describe-replication-tasks \
                --replication-task-identifier ${task_id} \
                --query 'ReplicationTasks[0].ReplicationTaskArn' --output text 2>/dev/null || echo "")
            
            if [[ -n "$task_arn" && "$task_arn" != "None" ]]; then
                # Check task status
                local task_status=$(aws dms describe-replication-tasks \
                    --replication-task-identifier ${task_id} \
                    --query 'ReplicationTasks[0].Status' --output text 2>/dev/null || echo "")
                
                # Stop task if running
                if [[ "$task_status" == "running" || "$task_status" == "starting" ]]; then
                    log "Stopping ${task_name}..."
                    aws dms stop-replication-task \
                        --replication-task-arn ${task_arn} || true
                    
                    # Wait for task to stop
                    log "Waiting for ${task_name} to stop..."
                    local max_attempts=30
                    local attempt=0
                    while [[ $attempt -lt $max_attempts ]]; do
                        local current_status=$(aws dms describe-replication-tasks \
                            --replication-task-identifier ${task_id} \
                            --query 'ReplicationTasks[0].Status' --output text 2>/dev/null || echo "stopped")
                        
                        if [[ "$current_status" == "stopped" || "$current_status" == "failed" ]]; then
                            break
                        fi
                        
                        sleep 10
                        ((attempt++))
                    done
                fi
                
                # Delete task
                log "Deleting ${task_name}..."
                aws dms delete-replication-task \
                    --replication-task-arn ${task_arn} || true
                
                success "${task_name} deleted"
            else
                warning "${task_name} ARN not found or invalid"
            fi
        else
            warning "${task_name} not found: ${task_id}"
        fi
    }
    
    # Stop and delete migration tasks
    stop_and_delete_task "${MIGRATION_TASK_ID}" "Migration task"
    stop_and_delete_task "${CDC_TASK_ID}" "CDC task"
    
    success "Migration tasks processed"
}

# Function to delete endpoints
delete_endpoints() {
    log "Deleting endpoints..."
    
    # Function to delete an endpoint
    delete_endpoint() {
        local endpoint_id=$1
        local endpoint_name=$2
        
        log "Deleting ${endpoint_name}: ${endpoint_id}"
        
        # Check if endpoint exists
        if aws dms describe-endpoints \
            --endpoint-identifier ${endpoint_id} &> /dev/null; then
            
            # Get endpoint ARN
            local endpoint_arn=$(aws dms describe-endpoints \
                --endpoint-identifier ${endpoint_id} \
                --query 'Endpoints[0].EndpointArn' --output text 2>/dev/null || echo "")
            
            if [[ -n "$endpoint_arn" && "$endpoint_arn" != "None" ]]; then
                # Delete endpoint
                aws dms delete-endpoint \
                    --endpoint-arn ${endpoint_arn} || true
                
                success "${endpoint_name} deleted"
            else
                warning "${endpoint_name} ARN not found or invalid"
            fi
        else
            warning "${endpoint_name} not found: ${endpoint_id}"
        fi
    }
    
    # Delete endpoints
    delete_endpoint "${SOURCE_ENDPOINT_ID}" "Source endpoint"
    delete_endpoint "${TARGET_ENDPOINT_ID}" "Target endpoint"
    
    success "Endpoints processed"
}

# Function to delete replication instance
delete_replication_instance() {
    log "Deleting DMS replication instance..."
    
    # Check if replication instance exists
    if aws dms describe-replication-instances \
        --replication-instance-identifier ${DMS_REPLICATION_INSTANCE_ID} &> /dev/null; then
        
        log "Deleting replication instance: ${DMS_REPLICATION_INSTANCE_ID}"
        
        # Delete replication instance
        aws dms delete-replication-instance \
            --replication-instance-identifier ${DMS_REPLICATION_INSTANCE_ID} || true
        
        # Wait for deletion to complete
        log "Waiting for replication instance deletion to complete..."
        local max_attempts=60  # 10 minutes
        local attempt=0
        while [[ $attempt -lt $max_attempts ]]; do
            if ! aws dms describe-replication-instances \
                --replication-instance-identifier ${DMS_REPLICATION_INSTANCE_ID} &> /dev/null; then
                break
            fi
            
            sleep 10
            ((attempt++))
            
            if [[ $((attempt % 6)) -eq 0 ]]; then
                log "Still waiting for replication instance deletion... (${attempt}0 seconds)"
            fi
        done
        
        success "DMS replication instance deleted"
    else
        warning "DMS replication instance not found: ${DMS_REPLICATION_INSTANCE_ID}"
    fi
}

# Function to delete subnet group
delete_subnet_group() {
    log "Deleting DMS subnet group..."
    
    # Check if subnet group exists
    if aws dms describe-replication-subnet-groups \
        --replication-subnet-group-identifier ${DMS_SUBNET_GROUP_ID} &> /dev/null; then
        
        log "Deleting subnet group: ${DMS_SUBNET_GROUP_ID}"
        
        # Delete subnet group
        aws dms delete-replication-subnet-group \
            --replication-subnet-group-identifier ${DMS_SUBNET_GROUP_ID} || true
        
        success "DMS subnet group deleted"
    else
        warning "DMS subnet group not found: ${DMS_SUBNET_GROUP_ID}"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket ${S3_BUCKET_NAME} 2>/dev/null; then
        log "Deleting S3 bucket: ${S3_BUCKET_NAME}"
        
        # Empty bucket first
        log "Emptying S3 bucket..."
        aws s3 rm s3://${S3_BUCKET_NAME} --recursive || true
        
        # Remove all versions and delete markers (if versioning was enabled)
        aws s3api list-object-versions \
            --bucket ${S3_BUCKET_NAME} \
            --query 'Versions[].{Key: Key, VersionId: VersionId}' \
            --output text 2>/dev/null | while read key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object \
                    --bucket ${S3_BUCKET_NAME} \
                    --key "$key" \
                    --version-id "$version_id" || true
            fi
        done
        
        aws s3api list-object-versions \
            --bucket ${S3_BUCKET_NAME} \
            --query 'DeleteMarkers[].{Key: Key, VersionId: VersionId}' \
            --output text 2>/dev/null | while read key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object \
                    --bucket ${S3_BUCKET_NAME} \
                    --key "$key" \
                    --version-id "$version_id" || true
            fi
        done
        
        # Delete bucket
        aws s3 rb s3://${S3_BUCKET_NAME} --force || true
        
        success "S3 bucket deleted"
    else
        warning "S3 bucket not found: ${S3_BUCKET_NAME}"
    fi
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch log group
    local log_group_name="dms-tasks-${DMS_REPLICATION_INSTANCE_ID}"
    
    if aws logs describe-log-groups \
        --log-group-name-prefix ${log_group_name} \
        --query "logGroups[?logGroupName=='${log_group_name}']" \
        --output text | grep -q "${log_group_name}"; then
        
        log "Deleting CloudWatch log group: ${log_group_name}"
        aws logs delete-log-group \
            --log-group-name ${log_group_name} || true
        
        success "CloudWatch log group deleted"
    else
        warning "CloudWatch log group not found: ${log_group_name}"
    fi
    
    # Delete CloudWatch alarms (if any exist)
    local alarm_name="DMS-Task-Failure-${MIGRATION_TASK_ID}"
    
    if aws cloudwatch describe-alarms \
        --alarm-names ${alarm_name} \
        --query "MetricAlarms[?AlarmName=='${alarm_name}']" \
        --output text | grep -q "${alarm_name}"; then
        
        log "Deleting CloudWatch alarm: ${alarm_name}"
        aws cloudwatch delete-alarms \
            --alarm-names ${alarm_name} || true
        
        success "CloudWatch alarm deleted"
    else
        warning "CloudWatch alarm not found: ${alarm_name}"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        ".env_vars"
        "table-mapping.json"
        "task-settings.json"
        "validation-settings.json"
        "endpoint-config.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed: $file"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to display cleanup summary
show_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "The following resources have been processed for deletion:"
    echo "- DMS Replication Instance: ${DMS_REPLICATION_INSTANCE_ID}"
    echo "- DMS Subnet Group: ${DMS_SUBNET_GROUP_ID}"
    echo "- Source Endpoint: ${SOURCE_ENDPOINT_ID}"
    echo "- Target Endpoint: ${TARGET_ENDPOINT_ID}"
    echo "- Migration Task: ${MIGRATION_TASK_ID}"
    echo "- CDC Task: ${CDC_TASK_ID}"
    echo "- S3 Bucket: ${S3_BUCKET_NAME}"
    echo "- CloudWatch Log Group: dms-tasks-${DMS_REPLICATION_INSTANCE_ID}"
    echo ""
    echo "Note: Some resources may take additional time to be fully deleted."
    echo "Check the AWS Console to verify complete removal of all resources."
}

# Function to handle script interruption
cleanup_on_interrupt() {
    echo ""
    warning "Script interrupted. Some resources may not have been deleted."
    echo "You may need to run this script again or manually delete remaining resources."
    exit 1
}

# Set trap to handle script interruption
trap cleanup_on_interrupt INT TERM

# Main cleanup function
main() {
    log "Starting DMS Database Migration cleanup..."
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_migration_tasks
    delete_endpoints
    delete_replication_instance
    delete_subnet_group
    delete_s3_bucket
    delete_cloudwatch_resources
    cleanup_local_files
    
    success "DMS Database Migration infrastructure cleanup completed!"
    show_cleanup_summary
}

# Run main function
main "$@"