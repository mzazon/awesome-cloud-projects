#!/bin/bash

#===============================================================================
# Simple Web Application Deployment with Elastic Beanstalk and CloudWatch
# Destroy Script
#
# This script safely removes all resources created by the deploy.sh script,
# including Elastic Beanstalk environments, applications, CloudWatch alarms,
# and S3 buckets.
#
# Prerequisites:
# - AWS CLI installed and configured
# - Appropriate AWS permissions for resource deletion
# - deployment-info.env file from successful deployment
#
# Usage: ./destroy.sh [--force] [--keep-logs]
#===============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
FORCE_DELETE=false
KEEP_LOGS=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            echo "⚠️  Force delete mode enabled - skipping confirmation prompts"
            shift
            ;;
        --keep-logs)
            KEEP_LOGS=true
            echo "📝 Keep logs mode enabled - CloudWatch logs will be preserved"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--force] [--keep-logs]"
            echo "  --force      Skip confirmation prompts and force deletion"
            echo "  --keep-logs  Preserve CloudWatch logs after cleanup"
            echo "  -h, --help   Show this help message"
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️  $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1" | tee -a "$LOG_FILE"
}

# Load deployment information
load_deployment_info() {
    local info_file="${SCRIPT_DIR}/deployment-info.env"
    
    if [[ ! -f "$info_file" ]]; then
        log_error "Deployment info file not found: $info_file"
        log_error "This file should be created by the deploy.sh script."
        log_info "You can still manually specify resource names to clean up."
        
        read -p "Do you want to manually specify resource names? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        
        manual_resource_input
        return
    fi
    
    # Source the deployment info
    # shellcheck source=/dev/null
    source "$info_file"
    
    log_info "Loaded deployment information:"
    log_info "  Application Name: ${APP_NAME:-not set}"
    log_info "  Environment Name: ${ENV_NAME:-not set}"
    log_info "  S3 Bucket: ${S3_BUCKET:-not set}"
    log_info "  AWS Region: ${AWS_REGION:-not set}"
    log_info "  Work Directory: ${WORK_DIR:-not set}"
}

# Manual resource input for cases where deployment-info.env is missing
manual_resource_input() {
    log_info "Please provide the resource names to clean up:"
    
    read -p "Application Name: " APP_NAME
    read -p "Environment Name: " ENV_NAME
    read -p "S3 Bucket Name: " S3_BUCKET
    
    # Set defaults for optional variables
    export AWS_REGION
    AWS_REGION=$(aws configure get region)
    export WORK_DIR=""
    export VERSION_LABEL=""
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    echo "=================================="
    echo "⚠️  RESOURCE DELETION CONFIRMATION"
    echo "=================================="
    echo "The following resources will be PERMANENTLY DELETED:"
    echo ""
    echo "• Elastic Beanstalk Environment: $ENV_NAME"
    echo "• Elastic Beanstalk Application: $APP_NAME"
    echo "• CloudWatch Alarms: ${ENV_NAME}-health-alarm, ${ENV_NAME}-4xx-errors"
    echo "• S3 Bucket and Contents: $S3_BUCKET"
    if [[ "$KEEP_LOGS" == "false" ]]; then
        echo "• CloudWatch Log Groups: /aws/elasticbeanstalk/$ENV_NAME/*"
    fi
    if [[ -n "$WORK_DIR" ]]; then
        echo "• Local Working Directory: $WORK_DIR"
    fi
    echo ""
    echo "This action CANNOT be undone!"
    echo "=================================="
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_warning "User confirmed deletion. Proceeding with resource cleanup..."
}

# Check if resources exist before attempting deletion
check_resource_existence() {
    log "🔍 Checking resource existence..."
    
    # Check if environment exists
    local env_status
    env_status=$(aws elasticbeanstalk describe-environments \
        --environment-names "$ENV_NAME" \
        --query 'Environments[0].Status' \
        --output text 2>/dev/null || echo "NotFound")
    
    if [[ "$env_status" == "NotFound" || "$env_status" == "None" ]]; then
        log_warning "Environment $ENV_NAME not found - it may have already been deleted"
        ENV_EXISTS=false
    else
        log_info "Environment $ENV_NAME found with status: $env_status"
        ENV_EXISTS=true
    fi
    
    # Check if application exists
    local app_status
    app_status=$(aws elasticbeanstalk describe-applications \
        --application-names "$APP_NAME" \
        --query 'Applications[0].ApplicationName' \
        --output text 2>/dev/null || echo "NotFound")
    
    if [[ "$app_status" == "NotFound" || "$app_status" == "None" ]]; then
        log_warning "Application $APP_NAME not found - it may have already been deleted"
        APP_EXISTS=false
    else
        log_info "Application $APP_NAME found"
        APP_EXISTS=true
    fi
    
    # Check if S3 bucket exists
    if aws s3 ls "s3://$S3_BUCKET" &>/dev/null; then
        log_info "S3 bucket $S3_BUCKET found"
        S3_EXISTS=true
    else
        log_warning "S3 bucket $S3_BUCKET not found - it may have already been deleted"
        S3_EXISTS=false
    fi
}

# Terminate Elastic Beanstalk environment
terminate_environment() {
    if [[ "$ENV_EXISTS" == "false" ]]; then
        log_info "Skipping environment termination - environment not found"
        return 0
    fi
    
    log "🔄 Terminating Elastic Beanstalk environment..."
    
    # Terminate the environment
    aws elasticbeanstalk terminate-environment --environment-name "$ENV_NAME"
    
    log_info "Environment termination initiated - this may take 5-10 minutes..."
    
    # Wait for environment termination with timeout
    local timeout=900  # 15 minutes
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            log_error "Environment termination timed out after 15 minutes"
            log_error "You may need to manually check the environment status in the AWS console"
            break
        fi
        
        local env_status
        env_status=$(aws elasticbeanstalk describe-environments \
            --environment-names "$ENV_NAME" \
            --query 'Environments[0].Status' \
            --output text 2>/dev/null || echo "NotFound")
        
        if [[ "$env_status" == "NotFound" || "$env_status" == "None" ]]; then
            log_success "Environment $ENV_NAME terminated successfully"
            break
        elif [[ "$env_status" == "Terminated" ]]; then
            log_success "Environment $ENV_NAME terminated successfully"
            break
        fi
        
        log_info "Environment status: $env_status (elapsed: ${elapsed}s)"
        sleep 30
    done
}

# Delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "📊 Deleting CloudWatch alarms..."
    
    local alarms=("${ENV_NAME}-health-alarm" "${ENV_NAME}-4xx-errors")
    local existing_alarms=()
    
    # Check which alarms actually exist
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm"; then
            existing_alarms+=("$alarm")
        else
            log_warning "CloudWatch alarm $alarm not found - it may have already been deleted"
        fi
    done
    
    if [[ ${#existing_alarms[@]} -eq 0 ]]; then
        log_info "No CloudWatch alarms found to delete"
        return 0
    fi
    
    # Delete existing alarms
    aws cloudwatch delete-alarms --alarm-names "${existing_alarms[@]}"
    log_success "CloudWatch alarms deleted: ${existing_alarms[*]}"
}

# Delete CloudWatch log groups
delete_cloudwatch_logs() {
    if [[ "$KEEP_LOGS" == "true" ]]; then
        log_info "Keeping CloudWatch logs as requested"
        return 0
    fi
    
    log "📝 Deleting CloudWatch log groups..."
    
    # Get log groups for the environment
    local log_groups
    log_groups=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/elasticbeanstalk/$ENV_NAME" \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$log_groups" ]]; then
        log_info "No CloudWatch log groups found for environment $ENV_NAME"
        return 0
    fi
    
    # Delete each log group
    for log_group in $log_groups; do
        log_info "Deleting log group: $log_group"
        aws logs delete-log-group --log-group-name "$log_group" || {
            log_warning "Failed to delete log group: $log_group"
        }
    done
    
    log_success "CloudWatch log groups cleanup completed"
}

# Delete Elastic Beanstalk application
delete_application() {
    if [[ "$APP_EXISTS" == "false" ]]; then
        log_info "Skipping application deletion - application not found"
        return 0
    fi
    
    log "🗑️  Deleting Elastic Beanstalk application..."
    
    # Delete the application (this will also delete any remaining environments)
    aws elasticbeanstalk delete-application \
        --application-name "$APP_NAME" \
        --terminate-env-by-force
    
    log_success "Elastic Beanstalk application $APP_NAME deleted"
}

# Delete S3 bucket and contents
delete_s3_bucket() {
    if [[ "$S3_EXISTS" == "false" ]]; then
        log_info "Skipping S3 bucket deletion - bucket not found"
        return 0
    fi
    
    log "🪣 Deleting S3 bucket and contents..."
    
    # Delete all objects in the bucket first
    local object_count
    object_count=$(aws s3 ls "s3://$S3_BUCKET" --recursive | wc -l)
    
    if [[ $object_count -gt 0 ]]; then
        log_info "Deleting $object_count objects from S3 bucket $S3_BUCKET"
        aws s3 rm "s3://$S3_BUCKET" --recursive
    fi
    
    # Delete the bucket
    aws s3 rb "s3://$S3_BUCKET"
    log_success "S3 bucket $S3_BUCKET deleted"
}

# Clean up local files
cleanup_local_files() {
    if [[ -z "$WORK_DIR" ]] || [[ ! -d "$WORK_DIR" ]]; then
        log_info "No local working directory to clean up"
        return 0
    fi
    
    log "📁 Cleaning up local files..."
    
    if [[ "$FORCE_DELETE" == "false" ]]; then
        read -p "Delete local working directory $WORK_DIR? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Keeping local working directory: $WORK_DIR"
            return 0
        fi
    fi
    
    rm -rf "$WORK_DIR"
    log_success "Local working directory deleted: $WORK_DIR"
}

# Clean up deployment info file
cleanup_deployment_info() {
    local info_file="${SCRIPT_DIR}/deployment-info.env"
    
    if [[ -f "$info_file" ]]; then
        rm -f "$info_file"
        log_success "Deployment info file cleaned up"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log "🔍 Verifying cleanup completion..."
    
    local issues_found=false
    
    # Check if environment still exists
    local env_status
    env_status=$(aws elasticbeanstalk describe-environments \
        --environment-names "$ENV_NAME" \
        --query 'Environments[0].Status' \
        --output text 2>/dev/null || echo "NotFound")
    
    if [[ "$env_status" != "NotFound" && "$env_status" != "None" ]]; then
        log_warning "Environment $ENV_NAME still exists with status: $env_status"
        issues_found=true
    fi
    
    # Check if application still exists
    local app_status
    app_status=$(aws elasticbeanstalk describe-applications \
        --application-names "$APP_NAME" \
        --query 'Applications[0].ApplicationName' \
        --output text 2>/dev/null || echo "NotFound")
    
    if [[ "$app_status" != "NotFound" && "$app_status" != "None" ]]; then
        log_warning "Application $APP_NAME still exists"
        issues_found=true
    fi
    
    # Check if S3 bucket still exists
    if aws s3 ls "s3://$S3_BUCKET" &>/dev/null; then
        log_warning "S3 bucket $S3_BUCKET still exists"
        issues_found=true
    fi
    
    # Check CloudWatch alarms
    local remaining_alarms
    remaining_alarms=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "$ENV_NAME" \
        --query 'MetricAlarms[].AlarmName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_alarms" ]]; then
        log_warning "Some CloudWatch alarms still exist: $remaining_alarms"
        issues_found=true
    fi
    
    if [[ "$issues_found" == "true" ]]; then
        log_warning "Some resources may not have been fully cleaned up"
        log_info "You may need to check the AWS console and manually remove any remaining resources"
    else
        log_success "All resources have been successfully cleaned up"
    fi
}

# Main cleanup function
main() {
    log "🧹 Starting cleanup of Simple Web Application deployment"
    log "Cleanup log: $LOG_FILE"
    
    load_deployment_info
    confirm_deletion
    check_resource_existence
    
    # Perform cleanup in reverse order of creation
    terminate_environment
    delete_cloudwatch_alarms
    delete_cloudwatch_logs
    delete_application
    delete_s3_bucket
    cleanup_local_files
    cleanup_deployment_info
    
    verify_cleanup
    
    echo ""
    echo "=================================="
    echo "🎉 CLEANUP COMPLETED"
    echo "=================================="
    echo "All resources have been removed from AWS."
    echo "Check the log file for detailed information: $LOG_FILE"
    echo "=================================="
    
    log_success "Cleanup completed successfully! 🎉"
}

# Execute main function
main "$@"