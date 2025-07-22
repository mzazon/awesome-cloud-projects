#!/bin/bash

# =============================================================================
# AWS S3 Cross-Region Replication Disaster Recovery Solution - Destroy Script
# =============================================================================
# This script safely removes all resources created by the deployment script,
# including S3 buckets, IAM roles, CloudWatch resources, and CloudTrail.
#
# Features:
# - Safe resource deletion with confirmation prompts
# - Idempotent operations (safe to run multiple times)
# - Comprehensive logging and error handling
# - Resource dependency handling
# - Verification of resource deletion
# - Cleanup of local files and configurations
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - deployment-vars.env file from deployment
# - Appropriate IAM permissions for resource deletion
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration and Constants
# =============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly DEPLOYMENT_VARS_FILE="${SCRIPT_DIR}/deployment-vars.env"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Global Variables
# =============================================================================
CONFIRMATION_REQUIRED=true
FORCE_DELETE=false
DRY_RUN=false

# =============================================================================
# Logging Functions
# =============================================================================
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] ${RED}$*${NC}" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] ${GREEN}$*${NC}" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] ${YELLOW}$*${NC}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [INFO] ${BLUE}$*${NC}" | tee -a "${LOG_FILE}"
}

# =============================================================================
# Command Line Options
# =============================================================================
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -f, --force         Skip confirmation prompts (dangerous)
    -d, --dry-run       Show what would be deleted without actually deleting
    -y, --yes           Automatically answer yes to all prompts
    -h, --help          Show this help message

Examples:
    $0                  # Interactive mode with confirmations
    $0 --dry-run        # Show what would be deleted
    $0 --force          # Delete everything without prompts (dangerous)
    $0 --yes            # Auto-confirm all prompts

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_DELETE=true
                CONFIRMATION_REQUIRED=false
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                CONFIRMATION_REQUIRED=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# Confirmation Functions
# =============================================================================
confirm_action() {
    local message="$1"
    local default_response="${2:-n}"
    
    if [[ "${CONFIRMATION_REQUIRED}" == "false" ]]; then
        return 0
    fi
    
    while true; do
        if [[ "${default_response}" == "y" ]]; then
            read -p "${message} (Y/n): " -r response
            response=${response:-Y}
        else
            read -p "${message} (y/N): " -r response
            response=${response:-N}
        fi
        
        case ${response} in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# =============================================================================
# Environment Setup
# =============================================================================
load_deployment_variables() {
    log_info "Loading deployment variables..."
    
    if [[ ! -f "${DEPLOYMENT_VARS_FILE}" ]]; then
        log_error "Deployment variables file not found: ${DEPLOYMENT_VARS_FILE}"
        log_error "This file is created during deployment and contains resource identifiers."
        log_error "If you don't have this file, you'll need to manually identify and delete resources."
        exit 1
    fi
    
    # Source the deployment variables
    # shellcheck source=/dev/null
    source "${DEPLOYMENT_VARS_FILE}"
    
    # Validate required variables
    local required_vars=(
        "AWS_ACCOUNT_ID"
        "PRIMARY_REGION"
        "SECONDARY_REGION"
        "SOURCE_BUCKET"
        "REPLICA_BUCKET"
        "REPLICATION_ROLE"
        "SNS_TOPIC"
        "CLOUDTRAIL_NAME"
        "DEPLOYMENT_ID"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required variables: ${missing_vars[*]}"
        exit 1
    fi
    
    log_success "Deployment variables loaded successfully"
    log_info "  Deployment ID: ${DEPLOYMENT_ID}"
    log_info "  Source Bucket: ${SOURCE_BUCKET}"
    log_info "  Replica Bucket: ${REPLICA_BUCKET}"
    log_info "  Replication Role: ${REPLICATION_ROLE}"
}

# =============================================================================
# Prerequisite Validation
# =============================================================================
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Verify we can access the deployment regions
    if ! aws ec2 describe-regions --region-names "${PRIMARY_REGION}" --query 'Regions[0].RegionName' --output text &> /dev/null; then
        log_error "Cannot access primary region ${PRIMARY_REGION}"
        exit 1
    fi
    
    if ! aws ec2 describe-regions --region-names "${SECONDARY_REGION}" --query 'Regions[0].RegionName' --output text &> /dev/null; then
        log_error "Cannot access secondary region ${SECONDARY_REGION}"
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# =============================================================================
# Resource Discovery
# =============================================================================
discover_resources() {
    log_info "Discovering resources to be deleted..."
    
    local resources_found=()
    
    # Check if source bucket exists
    if aws s3 ls "s3://${SOURCE_BUCKET}" &> /dev/null; then
        resources_found+=("S3 Source Bucket: ${SOURCE_BUCKET}")
    fi
    
    # Check if replica bucket exists
    if aws s3 ls "s3://${REPLICA_BUCKET}" --region "${SECONDARY_REGION}" &> /dev/null; then
        resources_found+=("S3 Replica Bucket: ${REPLICA_BUCKET}")
    fi
    
    # Check if IAM role exists
    if aws iam get-role --role-name "${REPLICATION_ROLE}" &> /dev/null; then
        resources_found+=("IAM Role: ${REPLICATION_ROLE}")
    fi
    
    # Check if SNS topic exists
    local sns_topic_arn="arn:aws:sns:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC}"
    if aws sns get-topic-attributes --topic-arn "${sns_topic_arn}" --region "${PRIMARY_REGION}" &> /dev/null; then
        resources_found+=("SNS Topic: ${SNS_TOPIC}")
    fi
    
    # Check if CloudTrail exists
    if aws cloudtrail describe-trails --trail-name-list "${CLOUDTRAIL_NAME}" --region "${PRIMARY_REGION}" --query 'trailList[0].Name' --output text 2>/dev/null | grep -q "${CLOUDTRAIL_NAME}"; then
        resources_found+=("CloudTrail: ${CLOUDTRAIL_NAME}")
    fi
    
    # Check for CloudWatch resources
    if aws cloudwatch describe-alarms --alarm-names "S3-Replication-Failure-${SOURCE_BUCKET}" --region "${PRIMARY_REGION}" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "S3-Replication-Failure"; then
        resources_found+=("CloudWatch Alarm: S3-Replication-Failure-${SOURCE_BUCKET}")
    fi
    
    if aws cloudwatch get-dashboard --dashboard-name "S3-DR-Dashboard-${DEPLOYMENT_ID}" --region "${PRIMARY_REGION}" &> /dev/null; then
        resources_found+=("CloudWatch Dashboard: S3-DR-Dashboard-${DEPLOYMENT_ID}")
    fi
    
    if [[ ${#resources_found[@]} -eq 0 ]]; then
        log_warning "No resources found for deletion. They may have been already deleted."
        return 1
    fi
    
    log_info "Found ${#resources_found[@]} resources to delete:"
    for resource in "${resources_found[@]}"; do
        log_info "  - ${resource}"
    done
    
    return 0
}

# =============================================================================
# Safety Functions
# =============================================================================
execute_command() {
    local description="$1"
    local command="$2"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] ${description}"
        log_info "[DRY RUN] Command: ${command}"
        return 0
    fi
    
    log_info "Executing: ${description}"
    if eval "${command}"; then
        log_success "${description} completed successfully"
        return 0
    else
        log_error "${description} failed"
        return 1
    fi
}

# =============================================================================
# Resource Deletion Functions
# =============================================================================
delete_s3_buckets() {
    log_info "Deleting S3 buckets..."
    
    # Delete source bucket
    if aws s3 ls "s3://${SOURCE_BUCKET}" &> /dev/null; then
        log_info "Deleting source bucket: ${SOURCE_BUCKET}"
        
        # Remove replication configuration first
        execute_command \
            "Remove replication configuration from ${SOURCE_BUCKET}" \
            "aws s3api delete-bucket-replication --bucket '${SOURCE_BUCKET}' 2>/dev/null || true"
        
        # Remove lifecycle configuration
        execute_command \
            "Remove lifecycle configuration from ${SOURCE_BUCKET}" \
            "aws s3api delete-bucket-lifecycle --bucket '${SOURCE_BUCKET}' 2>/dev/null || true"
        
        # Empty bucket
        execute_command \
            "Empty source bucket ${SOURCE_BUCKET}" \
            "aws s3 rm 's3://${SOURCE_BUCKET}' --recursive --quiet"
        
        # Delete bucket
        execute_command \
            "Delete source bucket ${SOURCE_BUCKET}" \
            "aws s3 rb 's3://${SOURCE_BUCKET}' --force"
    else
        log_warning "Source bucket ${SOURCE_BUCKET} not found or already deleted"
    fi
    
    # Delete replica bucket
    if aws s3 ls "s3://${REPLICA_BUCKET}" --region "${SECONDARY_REGION}" &> /dev/null; then
        log_info "Deleting replica bucket: ${REPLICA_BUCKET}"
        
        # Remove lifecycle configuration
        execute_command \
            "Remove lifecycle configuration from ${REPLICA_BUCKET}" \
            "aws s3api delete-bucket-lifecycle --bucket '${REPLICA_BUCKET}' --region '${SECONDARY_REGION}' 2>/dev/null || true"
        
        # Empty bucket
        execute_command \
            "Empty replica bucket ${REPLICA_BUCKET}" \
            "aws s3 rm 's3://${REPLICA_BUCKET}' --recursive --quiet --region '${SECONDARY_REGION}'"
        
        # Delete bucket
        execute_command \
            "Delete replica bucket ${REPLICA_BUCKET}" \
            "aws s3 rb 's3://${REPLICA_BUCKET}' --force --region '${SECONDARY_REGION}'"
    else
        log_warning "Replica bucket ${REPLICA_BUCKET} not found or already deleted"
    fi
    
    # Delete CloudTrail bucket if it exists
    if [[ -n "${CLOUDTRAIL_BUCKET:-}" ]]; then
        if aws s3 ls "s3://${CLOUDTRAIL_BUCKET}" &> /dev/null; then
            log_info "Deleting CloudTrail bucket: ${CLOUDTRAIL_BUCKET}"
            
            execute_command \
                "Empty CloudTrail bucket ${CLOUDTRAIL_BUCKET}" \
                "aws s3 rm 's3://${CLOUDTRAIL_BUCKET}' --recursive --quiet"
            
            execute_command \
                "Delete CloudTrail bucket ${CLOUDTRAIL_BUCKET}" \
                "aws s3 rb 's3://${CLOUDTRAIL_BUCKET}' --force"
        fi
    fi
    
    log_success "S3 buckets deletion completed"
}

delete_iam_resources() {
    log_info "Deleting IAM resources..."
    
    if aws iam get-role --role-name "${REPLICATION_ROLE}" &> /dev/null; then
        log_info "Deleting IAM role: ${REPLICATION_ROLE}"
        
        # Delete role policy
        execute_command \
            "Delete IAM role policy S3ReplicationPolicy" \
            "aws iam delete-role-policy --role-name '${REPLICATION_ROLE}' --policy-name S3ReplicationPolicy 2>/dev/null || true"
        
        # Delete IAM role
        execute_command \
            "Delete IAM role ${REPLICATION_ROLE}" \
            "aws iam delete-role --role-name '${REPLICATION_ROLE}'"
    else
        log_warning "IAM role ${REPLICATION_ROLE} not found or already deleted"
    fi
    
    log_success "IAM resources deletion completed"
}

delete_cloudwatch_resources() {
    log_info "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarm
    local alarm_name="S3-Replication-Failure-${SOURCE_BUCKET}"
    if aws cloudwatch describe-alarms --alarm-names "${alarm_name}" --region "${PRIMARY_REGION}" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "S3-Replication-Failure"; then
        execute_command \
            "Delete CloudWatch alarm ${alarm_name}" \
            "aws cloudwatch delete-alarms --alarm-names '${alarm_name}' --region '${PRIMARY_REGION}'"
    else
        log_warning "CloudWatch alarm ${alarm_name} not found or already deleted"
    fi
    
    # Delete CloudWatch dashboard
    local dashboard_name="S3-DR-Dashboard-${DEPLOYMENT_ID}"
    if aws cloudwatch get-dashboard --dashboard-name "${dashboard_name}" --region "${PRIMARY_REGION}" &> /dev/null; then
        execute_command \
            "Delete CloudWatch dashboard ${dashboard_name}" \
            "aws cloudwatch delete-dashboards --dashboard-names '${dashboard_name}' --region '${PRIMARY_REGION}'"
    else
        log_warning "CloudWatch dashboard ${dashboard_name} not found or already deleted"
    fi
    
    log_success "CloudWatch resources deletion completed"
}

delete_sns_resources() {
    log_info "Deleting SNS resources..."
    
    local sns_topic_arn="arn:aws:sns:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC}"
    if aws sns get-topic-attributes --topic-arn "${sns_topic_arn}" --region "${PRIMARY_REGION}" &> /dev/null; then
        execute_command \
            "Delete SNS topic ${SNS_TOPIC}" \
            "aws sns delete-topic --topic-arn '${sns_topic_arn}' --region '${PRIMARY_REGION}'"
    else
        log_warning "SNS topic ${SNS_TOPIC} not found or already deleted"
    fi
    
    log_success "SNS resources deletion completed"
}

delete_cloudtrail_resources() {
    log_info "Deleting CloudTrail resources..."
    
    if aws cloudtrail describe-trails --trail-name-list "${CLOUDTRAIL_NAME}" --region "${PRIMARY_REGION}" --query 'trailList[0].Name' --output text 2>/dev/null | grep -q "${CLOUDTRAIL_NAME}"; then
        # Stop logging first
        execute_command \
            "Stop CloudTrail logging for ${CLOUDTRAIL_NAME}" \
            "aws cloudtrail stop-logging --name '${CLOUDTRAIL_NAME}' --region '${PRIMARY_REGION}' 2>/dev/null || true"
        
        # Delete CloudTrail
        execute_command \
            "Delete CloudTrail ${CLOUDTRAIL_NAME}" \
            "aws cloudtrail delete-trail --name '${CLOUDTRAIL_NAME}' --region '${PRIMARY_REGION}'"
    else
        log_warning "CloudTrail ${CLOUDTRAIL_NAME} not found or already deleted"
    fi
    
    log_success "CloudTrail resources deletion completed"
}

# =============================================================================
# Local Cleanup
# =============================================================================
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/deployment-vars.env"
        "${SCRIPT_DIR}/dr-failover.sh"
        "${SCRIPT_DIR}/dr-failback.sh"
        "${SCRIPT_DIR}/replication-trust-policy.json"
        "${SCRIPT_DIR}/replication-permissions-policy.json"
        "${SCRIPT_DIR}/replication-config.json"
        "${SCRIPT_DIR}/lifecycle-policy.json"
        "${SCRIPT_DIR}/dashboard-config.json"
        "${SCRIPT_DIR}/cloudtrail-bucket-policy.json"
        "${SCRIPT_DIR}/deploy.log"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY RUN] Would remove file: ${file}"
            else
                rm -f "${file}"
                log_info "Removed file: ${file}"
            fi
        fi
    done
    
    # Remove test data directory if it exists
    if [[ -d "${SCRIPT_DIR}/test-data" ]]; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would remove directory: ${SCRIPT_DIR}/test-data"
        else
            rm -rf "${SCRIPT_DIR}/test-data"
            log_info "Removed directory: ${SCRIPT_DIR}/test-data"
        fi
    fi
    
    log_success "Local files cleanup completed"
}

# =============================================================================
# Verification
# =============================================================================
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local remaining_resources=()
    
    # Check S3 buckets
    if aws s3 ls "s3://${SOURCE_BUCKET}" &> /dev/null; then
        remaining_resources+=("S3 Source Bucket: ${SOURCE_BUCKET}")
    fi
    
    if aws s3 ls "s3://${REPLICA_BUCKET}" --region "${SECONDARY_REGION}" &> /dev/null; then
        remaining_resources+=("S3 Replica Bucket: ${REPLICA_BUCKET}")
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${REPLICATION_ROLE}" &> /dev/null; then
        remaining_resources+=("IAM Role: ${REPLICATION_ROLE}")
    fi
    
    # Check SNS topic
    local sns_topic_arn="arn:aws:sns:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC}"
    if aws sns get-topic-attributes --topic-arn "${sns_topic_arn}" --region "${PRIMARY_REGION}" &> /dev/null; then
        remaining_resources+=("SNS Topic: ${SNS_TOPIC}")
    fi
    
    # Check CloudTrail
    if aws cloudtrail describe-trails --trail-name-list "${CLOUDTRAIL_NAME}" --region "${PRIMARY_REGION}" --query 'trailList[0].Name' --output text 2>/dev/null | grep -q "${CLOUDTRAIL_NAME}"; then
        remaining_resources+=("CloudTrail: ${CLOUDTRAIL_NAME}")
    fi
    
    if [[ ${#remaining_resources[@]} -eq 0 ]]; then
        log_success "All resources have been successfully deleted"
        return 0
    else
        log_warning "Some resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            log_warning "  - ${resource}"
        done
        return 1
    fi
}

# =============================================================================
# Main Destroy Function
# =============================================================================
main() {
    log_info "Starting AWS S3 Cross-Region Replication Disaster Recovery cleanup..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be actually deleted"
    fi
    
    # Load deployment variables and validate prerequisites
    load_deployment_variables
    validate_prerequisites
    
    # Discover resources to be deleted
    if ! discover_resources; then
        log_info "No resources found to delete. Exiting."
        exit 0
    fi
    
    # Final confirmation
    if [[ "${FORCE_DELETE}" == "false" ]]; then
        echo ""
        log_warning "WARNING: This will permanently delete ALL resources created by the deployment!"
        log_warning "This includes S3 buckets and all their contents, IAM roles, and monitoring resources."
        echo ""
        
        if ! confirm_action "Are you sure you want to proceed with deletion?"; then
            log_info "Deletion cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deletion in dependency order
    log_info "Starting resource deletion..."
    
    # Delete CloudWatch resources first (they reference other resources)
    delete_cloudwatch_resources
    
    # Delete CloudTrail (depends on S3 bucket)
    delete_cloudtrail_resources
    
    # Delete SNS resources
    delete_sns_resources
    
    # Delete S3 buckets (remove replication configuration first)
    delete_s3_buckets
    
    # Delete IAM resources (no dependencies)
    delete_iam_resources
    
    # Clean up local files
    if [[ "${DRY_RUN}" == "false" ]]; then
        cleanup_local_files
    fi
    
    # Verify deletion
    if [[ "${DRY_RUN}" == "false" ]]; then
        verify_deletion
    fi
    
    # Display completion message
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_success "============================================="
        log_success "DRY RUN COMPLETED"
        log_success "============================================="
        log_info "No resources were actually deleted."
        log_info "Run without --dry-run to perform actual deletion."
    else
        log_success "============================================="
        log_success "CLEANUP COMPLETED SUCCESSFULLY"
        log_success "============================================="
        log_success "All disaster recovery resources have been deleted."
        log_success "Deployment ID: ${DEPLOYMENT_ID}"
        log_info ""
        log_info "The following resources were removed:"
        log_info "  - S3 source and replica buckets"
        log_info "  - IAM replication role and policies"
        log_info "  - CloudWatch alarms and dashboards"
        log_info "  - SNS topics and subscriptions"
        log_info "  - CloudTrail and associated resources"
        log_info "  - Local configuration files"
        log_info ""
        log_info "Cleanup log saved to: ${LOG_FILE}"
    fi
}

# =============================================================================
# Script Entry Point
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi