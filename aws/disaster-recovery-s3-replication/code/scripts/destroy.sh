#!/bin/bash

# AWS S3 Cross-Region Replication Disaster Recovery Cleanup Script
# This script safely removes all resources created by the deploy.sh script
# with proper error handling, logging, and confirmation prompts

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
START_TIME=$(date +%s)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Info logging with blue color
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

# Success logging with green color
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

# Warning logging with yellow color
log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

# Error logging with red color
log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log_info "Checking AWS authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or authentication failed"
        log_error "Please run 'aws configure' or set up AWS credentials"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local user_arn=$(aws sts get-caller-identity --query Arn --output text)
    log_success "AWS authentication successful"
    log_info "Account ID: ${account_id}"
    log_info "User/Role ARN: ${user_arn}"
}

# Function to validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: ${aws_version}"
    
    check_aws_auth
    log_success "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Check if environment file exists
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        # Source the environment file
        source "${SCRIPT_DIR}/.env"
        log_info "Environment loaded from .env file"
    else
        log_warning "Environment file not found. Trying to load from current environment..."
        
        # Set default values if not set
        export PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
        export DR_REGION="${DR_REGION:-us-west-2}"
        export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
        
        # If resource names are not set, we cannot proceed with cleanup
        if [[ -z "${SOURCE_BUCKET:-}" || -z "${DEST_BUCKET:-}" ]]; then
            log_error "Required environment variables not found"
            log_error "Please ensure SOURCE_BUCKET and DEST_BUCKET are set"
            log_error "Or run this script from the same directory where deploy.sh was executed"
            exit 1
        fi
    fi
    
    log_info "Primary Region: ${PRIMARY_REGION}"
    log_info "DR Region: ${DR_REGION}"
    log_info "Source Bucket: ${SOURCE_BUCKET}"
    log_info "Destination Bucket: ${DEST_BUCKET}"
    
    # Set default values for optional variables
    export REPLICATION_ROLE_NAME="${REPLICATION_ROLE_NAME:-}"
    export CLOUDTRAIL_NAME="${CLOUDTRAIL_NAME:-}"
    export ALARM_NAME="${ALARM_NAME:-}"
}

# Function to confirm destruction
confirm_destruction() {
    echo
    echo "======================== DESTRUCTION WARNING ========================"
    echo "This script will PERMANENTLY DELETE the following resources:"
    echo "  - S3 Bucket: ${SOURCE_BUCKET} (including ALL objects and versions)"
    echo "  - S3 Bucket: ${DEST_BUCKET} (including ALL objects and versions)"
    echo "  - IAM Role: ${REPLICATION_ROLE_NAME}"
    echo "  - CloudTrail: ${CLOUDTRAIL_NAME}"
    echo "  - CloudWatch Alarm: ${ALARM_NAME}"
    echo "  - All associated policies and configurations"
    echo "=================================================================="
    echo
    
    # Skip confirmation if --force flag is provided
    if [[ "${1:-}" == "--force" ]]; then
        log_warning "Force flag detected. Skipping confirmation."
        return 0
    fi
    
    echo -n "Are you sure you want to proceed? Type 'yes' to continue: "
    read -r confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_info "User confirmed destruction. Proceeding..."
}

# Function to remove CloudWatch alarms
remove_cloudwatch_alarms() {
    if [[ -n "${ALARM_NAME}" ]]; then
        log_info "Removing CloudWatch alarms..."
        
        # Check if alarm exists before trying to delete
        if aws cloudwatch describe-alarms --alarm-names "${ALARM_NAME}" \
            --region "${PRIMARY_REGION}" --query 'MetricAlarms[0]' --output text 2>/dev/null | grep -q "${ALARM_NAME}"; then
            
            aws cloudwatch delete-alarms \
                --alarm-names "${ALARM_NAME}" \
                --region "${PRIMARY_REGION}"
            
            log_success "CloudWatch alarm ${ALARM_NAME} removed"
        else
            log_warning "CloudWatch alarm ${ALARM_NAME} not found"
        fi
    else
        log_warning "CloudWatch alarm name not set, skipping alarm cleanup"
    fi
}

# Function to stop and remove CloudTrail
remove_cloudtrail() {
    if [[ -n "${CLOUDTRAIL_NAME}" ]]; then
        log_info "Removing CloudTrail..."
        
        # Check if trail exists
        if aws cloudtrail describe-trails --trail-name-list "${CLOUDTRAIL_NAME}" \
            --region "${PRIMARY_REGION}" --query 'trailList[0]' --output text 2>/dev/null | grep -q "${CLOUDTRAIL_NAME}"; then
            
            # Stop logging
            aws cloudtrail stop-logging \
                --name "${CLOUDTRAIL_NAME}" \
                --region "${PRIMARY_REGION}" 2>/dev/null || true
            
            # Delete trail
            aws cloudtrail delete-trail \
                --name "${CLOUDTRAIL_NAME}" \
                --region "${PRIMARY_REGION}"
            
            log_success "CloudTrail ${CLOUDTRAIL_NAME} removed"
        else
            log_warning "CloudTrail ${CLOUDTRAIL_NAME} not found"
        fi
    else
        log_warning "CloudTrail name not set, skipping CloudTrail cleanup"
    fi
}

# Function to disable replication and delete S3 objects
remove_s3_objects_and_replication() {
    log_info "Removing S3 replication configuration and objects..."
    
    # Remove replication configuration from source bucket
    if aws s3api head-bucket --bucket "${SOURCE_BUCKET}" --region "${PRIMARY_REGION}" 2>/dev/null; then
        log_info "Disabling replication on source bucket..."
        
        # Check if replication configuration exists
        if aws s3api get-bucket-replication --bucket "${SOURCE_BUCKET}" --region "${PRIMARY_REGION}" >/dev/null 2>&1; then
            aws s3api delete-bucket-replication \
                --bucket "${SOURCE_BUCKET}" \
                --region "${PRIMARY_REGION}"
            log_success "Replication configuration removed from source bucket"
        else
            log_warning "No replication configuration found on source bucket"
        fi
        
        # Delete all objects and versions from source bucket
        log_info "Deleting all objects and versions from source bucket..."
        
        # Get all object versions
        local versions=$(aws s3api list-object-versions \
            --bucket "${SOURCE_BUCKET}" \
            --region "${PRIMARY_REGION}" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output json 2>/dev/null || echo '[]')
        
        # Get all delete markers
        local delete_markers=$(aws s3api list-object-versions \
            --bucket "${SOURCE_BUCKET}" \
            --region "${PRIMARY_REGION}" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output json 2>/dev/null || echo '[]')
        
        # Delete versions if they exist
        if [[ "${versions}" != "[]" && "${versions}" != "null" ]]; then
            aws s3api delete-objects \
                --bucket "${SOURCE_BUCKET}" \
                --delete "{\"Objects\":${versions}}" \
                --region "${PRIMARY_REGION}" >/dev/null
            log_success "Deleted object versions from source bucket"
        fi
        
        # Delete markers if they exist
        if [[ "${delete_markers}" != "[]" && "${delete_markers}" != "null" ]]; then
            aws s3api delete-objects \
                --bucket "${SOURCE_BUCKET}" \
                --delete "{\"Objects\":${delete_markers}}" \
                --region "${PRIMARY_REGION}" >/dev/null
            log_success "Deleted delete markers from source bucket"
        fi
    else
        log_warning "Source bucket ${SOURCE_BUCKET} not found"
    fi
    
    # Delete all objects from destination bucket
    if aws s3api head-bucket --bucket "${DEST_BUCKET}" --region "${DR_REGION}" 2>/dev/null; then
        log_info "Deleting all objects and versions from destination bucket..."
        
        # Get all object versions
        local dest_versions=$(aws s3api list-object-versions \
            --bucket "${DEST_BUCKET}" \
            --region "${DR_REGION}" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output json 2>/dev/null || echo '[]')
        
        # Get all delete markers
        local dest_delete_markers=$(aws s3api list-object-versions \
            --bucket "${DEST_BUCKET}" \
            --region "${DR_REGION}" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output json 2>/dev/null || echo '[]')
        
        # Delete versions if they exist
        if [[ "${dest_versions}" != "[]" && "${dest_versions}" != "null" ]]; then
            aws s3api delete-objects \
                --bucket "${DEST_BUCKET}" \
                --delete "{\"Objects\":${dest_versions}}" \
                --region "${DR_REGION}" >/dev/null
            log_success "Deleted object versions from destination bucket"
        fi
        
        # Delete markers if they exist
        if [[ "${dest_delete_markers}" != "[]" && "${dest_delete_markers}" != "null" ]]; then
            aws s3api delete-objects \
                --bucket "${DEST_BUCKET}" \
                --delete "{\"Objects\":${dest_delete_markers}}" \
                --region "${DR_REGION}" >/dev/null
            log_success "Deleted delete markers from destination bucket"
        fi
    else
        log_warning "Destination bucket ${DEST_BUCKET} not found"
    fi
}

# Function to delete S3 buckets
remove_s3_buckets() {
    log_info "Removing S3 buckets..."
    
    # Delete source bucket
    if aws s3api head-bucket --bucket "${SOURCE_BUCKET}" --region "${PRIMARY_REGION}" 2>/dev/null; then
        aws s3 rb "s3://${SOURCE_BUCKET}" --region "${PRIMARY_REGION}"
        log_success "Source bucket ${SOURCE_BUCKET} removed"
    else
        log_warning "Source bucket ${SOURCE_BUCKET} not found"
    fi
    
    # Delete destination bucket
    if aws s3api head-bucket --bucket "${DEST_BUCKET}" --region "${DR_REGION}" 2>/dev/null; then
        aws s3 rb "s3://${DEST_BUCKET}" --region "${DR_REGION}"
        log_success "Destination bucket ${DEST_BUCKET} removed"
    else
        log_warning "Destination bucket ${DEST_BUCKET} not found"
    fi
}

# Function to remove IAM role and policies
remove_iam_role() {
    if [[ -n "${REPLICATION_ROLE_NAME}" ]]; then
        log_info "Removing IAM role and policies..."
        
        # Check if role exists
        if aws iam get-role --role-name "${REPLICATION_ROLE_NAME}" >/dev/null 2>&1; then
            
            # List and delete all inline policies
            local policies=$(aws iam list-role-policies \
                --role-name "${REPLICATION_ROLE_NAME}" \
                --query 'PolicyNames[]' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "${policies}" ]]; then
                for policy in ${policies}; do
                    aws iam delete-role-policy \
                        --role-name "${REPLICATION_ROLE_NAME}" \
                        --policy-name "${policy}"
                    log_success "Deleted inline policy ${policy} from role"
                done
            fi
            
            # List and detach all attached managed policies
            local attached_policies=$(aws iam list-attached-role-policies \
                --role-name "${REPLICATION_ROLE_NAME}" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "${attached_policies}" ]]; then
                for policy_arn in ${attached_policies}; do
                    aws iam detach-role-policy \
                        --role-name "${REPLICATION_ROLE_NAME}" \
                        --policy-arn "${policy_arn}"
                    log_success "Detached managed policy ${policy_arn} from role"
                done
            fi
            
            # Delete the role
            aws iam delete-role --role-name "${REPLICATION_ROLE_NAME}"
            log_success "IAM role ${REPLICATION_ROLE_NAME} removed"
        else
            log_warning "IAM role ${REPLICATION_ROLE_NAME} not found"
        fi
    else
        log_warning "IAM role name not set, skipping IAM cleanup"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove JSON policy files
    local temp_files=(
        "${SCRIPT_DIR}/replication-trust-policy.json"
        "${SCRIPT_DIR}/replication-policy.json"
        "${SCRIPT_DIR}/replication-config.json"
        "${SCRIPT_DIR}/test-file.txt"
        "${SCRIPT_DIR}/.env"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_success "Removed temporary file: $(basename "${file}")"
        fi
    done
}

# Function to display destruction summary
display_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    log_success "Cleanup completed successfully!"
    echo
    echo "======================== CLEANUP SUMMARY ========================"
    echo "Removed Resources:"
    echo "  ✓ S3 Bucket: ${SOURCE_BUCKET}"
    echo "  ✓ S3 Bucket: ${DEST_BUCKET}"
    echo "  ✓ IAM Role: ${REPLICATION_ROLE_NAME}"
    echo "  ✓ CloudTrail: ${CLOUDTRAIL_NAME}"
    echo "  ✓ CloudWatch Alarm: ${ALARM_NAME}"
    echo "  ✓ All objects, versions, and configurations"
    echo "Cleanup Time:     ${duration} seconds"
    echo "=============================================================="
    echo
    echo "All disaster recovery resources have been successfully removed."
    echo "No ongoing charges will be incurred from these resources."
    echo
}

# Main destruction function
main() {
    log_info "Starting AWS S3 Cross-Region Replication cleanup..."
    log_info "Log file: ${LOG_FILE}"
    
    check_prerequisites
    load_environment
    confirm_destruction "$@"
    remove_cloudwatch_alarms
    remove_cloudtrail
    remove_s3_objects_and_replication
    remove_s3_buckets
    remove_iam_role
    cleanup_temp_files
    display_summary
    
    log_success "Cleanup script completed successfully"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi