#!/bin/bash

#########################################################################
# Performance Monitoring AI Agents with AgentCore and CloudWatch
# Destruction/Cleanup Script
#
# This script safely removes all AWS resources created by the deployment
# script, including CloudWatch dashboards, alarms, Lambda functions,
# S3 storage, IAM roles, and log groups.
#
# Author: Generated from recipe a9f7e2b4
# Version: 1.0
# Last Updated: 2025-01-15
#########################################################################

set -euo pipefail  # Exit on any error, undefined variables, or pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="destroy_$(date +%Y%m%d_%H%M%S).log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${SCRIPT_DIR}/deployment_config.env"

# Global variables
DELETION_ERRORS=0
FORCE_DELETE=false
DRY_RUN=false

#########################################################################
# Utility Functions
#########################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "${RED}❌ $*${NC}"
    ((DELETION_ERRORS++))
}

cleanup_on_exit() {
    local exit_code=$?
    
    if [[ $exit_code -eq 0 && $DELETION_ERRORS -eq 0 ]]; then
        log_success "Cleanup completed successfully"
        # Remove configuration file on successful cleanup
        if [[ -f "${CONFIG_FILE}" && "${DRY_RUN}" == "false" ]]; then
            rm -f "${CONFIG_FILE}"
            log_info "Removed configuration file: ${CONFIG_FILE}"
        fi
    else
        log_error "Cleanup completed with ${DELETION_ERRORS} errors"
        log_warning "Some resources may still exist. Check the log file: ${LOG_FILE}"
        
        if [[ -f "${CONFIG_FILE}" ]]; then
            log_info "Configuration file preserved for retry: ${CONFIG_FILE}"
        fi
    fi
    
    exit $exit_code
}

# Set trap for cleanup
trap cleanup_on_exit EXIT

load_configuration() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
        log_info "This file is created by the deploy.sh script."
        log_info "If you want to delete resources manually, set these environment variables:"
        log_info "  AWS_REGION, AWS_ACCOUNT_ID, RANDOM_SUFFIX"
        log_info "  AGENT_NAME, LAMBDA_FUNCTION_NAME, S3_BUCKET_NAME"
        log_info "  LOG_GROUP_NAME, DASHBOARD_NAME"
        exit 1
    fi
    
    log_info "Loading configuration from: ${CONFIG_FILE}"
    source "${CONFIG_FILE}"
    
    # Verify required variables are set
    local required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "RANDOM_SUFFIX"
        "AGENT_NAME" "LAMBDA_FUNCTION_NAME" "S3_BUCKET_NAME"
        "LOG_GROUP_NAME" "DASHBOARD_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable ${var} not found in configuration"
            exit 1
        fi
    done
    
    log_success "Configuration loaded successfully"
}

check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured"
        exit 1
    fi
    
    # Verify we're in the correct AWS account
    local current_account=$(aws sts get-caller-identity --query Account --output text)
    if [[ "${current_account}" != "${AWS_ACCOUNT_ID}" ]]; then
        log_error "AWS account mismatch!"
        log_error "Expected: ${AWS_ACCOUNT_ID}"
        log_error "Current:  ${current_account}"
        exit 1
    fi
    
    # Verify we're in the correct region
    local current_region=$(aws configure get region)
    if [[ "${current_region}" != "${AWS_REGION}" ]]; then
        log_warning "AWS region mismatch!"
        log_warning "Expected: ${AWS_REGION}"
        log_warning "Current:  ${current_region}"
        log_warning "Proceeding with configured region: ${AWS_REGION}"
    fi
    
    log_success "Prerequisites verified"
}

confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log_warning "Force deletion mode enabled - skipping confirmation"
        return 0
    fi
    
    echo
    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    log_warning "This will permanently delete the following AWS resources:"
    echo
    log_info "CloudWatch Resources:"
    log_info "  - Dashboard: ${DASHBOARD_NAME}"
    log_info "  - Alarms: AgentCore-*-${RANDOM_SUFFIX}"
    log_info "  - Log Groups: ${LOG_GROUP_NAME} and related groups"
    log_info "  - Metric Filters: Custom agent metrics"
    echo
    log_info "Compute Resources:"
    log_info "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo
    log_info "Storage Resources:"
    log_info "  - S3 Bucket: ${S3_BUCKET_NAME} (including all objects)"
    echo
    log_info "IAM Resources:"
    log_info "  - Role: AgentCoreMonitoringRole-${RANDOM_SUFFIX}"
    log_info "  - Role: LambdaPerformanceMonitorRole-${RANDOM_SUFFIX}"
    log_info "  - Policy: AgentCoreObservabilityPolicy-${RANDOM_SUFFIX}"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to delete these resources? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource deletion..."
}

wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local check_command="$3"
    local max_attempts="${4:-30}"
    local sleep_interval="${5:-2}"
    
    log_info "Waiting for ${resource_type} '${resource_name}' deletion..."
    
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if ! eval "${check_command}" &> /dev/null; then
            log_success "${resource_type} '${resource_name}' deleted successfully"
            return 0
        fi
        
        ((attempt++))
        if [[ $((attempt % 5)) -eq 0 ]]; then
            log_info "Still waiting for deletion... (${attempt}/${max_attempts})"
        fi
        sleep "${sleep_interval}"
    done
    
    log_error "Timeout waiting for ${resource_type} '${resource_name}' deletion"
    return 1
}

#########################################################################
# Deletion Functions
#########################################################################

delete_cloudwatch_alarms() {
    log_info "Deleting CloudWatch alarms..."
    
    # Get list of alarms created by our deployment
    local alarm_names=(
        "AgentCore-HighLatency-${RANDOM_SUFFIX}"
        "AgentCore-HighSystemErrors-${RANDOM_SUFFIX}"
        "AgentCore-HighThrottles-${RANDOM_SUFFIX}"
    )
    
    # First, check which alarms exist
    local existing_alarms=()
    for alarm_name in "${alarm_names[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "${alarm_name}" \
                --query "MetricAlarms[?AlarmName=='${alarm_name}'].AlarmName" \
                --output text 2>/dev/null | grep -q "${alarm_name}"; then
            existing_alarms+=("${alarm_name}")
        fi
    done
    
    if [[ ${#existing_alarms[@]} -eq 0 ]]; then
        log_info "No CloudWatch alarms found to delete"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would delete ${#existing_alarms[@]} CloudWatch alarms"
        return 0
    fi
    
    # Delete existing alarms
    if aws cloudwatch delete-alarms --alarm-names "${existing_alarms[@]}"; then
        log_success "Deleted ${#existing_alarms[@]} CloudWatch alarms"
    else
        log_error "Failed to delete CloudWatch alarms"
    fi
}

delete_cloudwatch_dashboard() {
    log_info "Deleting CloudWatch dashboard: ${DASHBOARD_NAME}"
    
    # Check if dashboard exists
    if ! aws cloudwatch get-dashboard --dashboard-name "${DASHBOARD_NAME}" &> /dev/null; then
        log_info "CloudWatch dashboard not found, skipping"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would delete CloudWatch dashboard: ${DASHBOARD_NAME}"
        return 0
    fi
    
    if aws cloudwatch delete-dashboards --dashboard-names "${DASHBOARD_NAME}"; then
        log_success "Deleted CloudWatch dashboard: ${DASHBOARD_NAME}"
    else
        log_error "Failed to delete CloudWatch dashboard: ${DASHBOARD_NAME}"
    fi
}

delete_lambda_function() {
    log_info "Deleting Lambda function: ${LAMBDA_FUNCTION_NAME}"
    
    # Check if Lambda function exists
    if ! aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        log_info "Lambda function not found, skipping"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would delete Lambda function: ${LAMBDA_FUNCTION_NAME}"
        return 0
    fi
    
    # Remove Lambda permission for CloudWatch
    aws lambda remove-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id allow-cloudwatch-alarms 2>/dev/null || true
    
    # Delete Lambda function
    if aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}"; then
        log_success "Deleted Lambda function: ${LAMBDA_FUNCTION_NAME}"
    else
        log_error "Failed to delete Lambda function: ${LAMBDA_FUNCTION_NAME}"
    fi
}

delete_metric_filters() {
    log_info "Deleting CloudWatch metric filters..."
    
    local metric_filter_names=(
        "AgentResponseTime"
        "ConversationQualityScore"
        "BusinessOutcomeSuccess"
    )
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would delete ${#metric_filter_names[@]} metric filters"
        return 0
    fi
    
    local deleted_count=0
    for filter_name in "${metric_filter_names[@]}"; do
        if aws logs describe-metric-filters \
                --log-group-name "${LOG_GROUP_NAME}" \
                --filter-name-prefix "${filter_name}" \
                --query "metricFilters[?filterName=='${filter_name}']" \
                --output text 2>/dev/null | grep -q "${filter_name}"; then
            
            if aws logs delete-metric-filter \
                    --log-group-name "${LOG_GROUP_NAME}" \
                    --filter-name "${filter_name}"; then
                ((deleted_count++))
                log_success "Deleted metric filter: ${filter_name}"
            else
                log_error "Failed to delete metric filter: ${filter_name}"
            fi
        fi
    done
    
    if [[ $deleted_count -gt 0 ]]; then
        log_success "Deleted ${deleted_count} metric filters"
    else
        log_info "No metric filters found to delete"
    fi
}

delete_log_groups() {
    log_info "Deleting CloudWatch log groups..."
    
    local log_groups=(
        "${LOG_GROUP_NAME}"
        "/aws/lambda/${LAMBDA_FUNCTION_NAME}"
        "/aws/bedrock/agentcore/memory/${AGENT_NAME}"
        "/aws/bedrock/agentcore/gateway/${AGENT_NAME}"
    )
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would delete ${#log_groups[@]} log groups"
        return 0
    fi
    
    local deleted_count=0
    for log_group in "${log_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "${log_group}" \
                --query "logGroups[?logGroupName=='${log_group}']" \
                --output text 2>/dev/null | grep -q "${log_group}"; then
            
            if aws logs delete-log-group --log-group-name "${log_group}"; then
                ((deleted_count++))
                log_success "Deleted log group: ${log_group}"
            else
                log_error "Failed to delete log group: ${log_group}"
            fi
        fi
    done
    
    if [[ $deleted_count -gt 0 ]]; then
        log_success "Deleted ${deleted_count} log groups"
    else
        log_info "No log groups found to delete"
    fi
}

delete_s3_bucket() {
    log_info "Deleting S3 bucket: ${S3_BUCKET_NAME}"
    
    # Check if bucket exists
    if ! aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        log_info "S3 bucket not found, skipping"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would delete S3 bucket: ${S3_BUCKET_NAME}"
        return 0
    fi
    
    # Check if bucket has objects
    local object_count=$(aws s3api list-objects-v2 \
        --bucket "${S3_BUCKET_NAME}" \
        --query 'length(Contents)' \
        --output text 2>/dev/null || echo "0")
    
    if [[ "${object_count}" != "0" && "${object_count}" != "null" ]]; then
        log_info "Bucket contains ${object_count} objects, removing them first..."
        
        # Remove all objects (including versions)
        if aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive; then
            log_success "Removed all objects from bucket"
        else
            log_error "Failed to remove objects from bucket"
            return 1
        fi
        
        # Remove delete markers and versions
        aws s3api list-object-versions \
            --bucket "${S3_BUCKET_NAME}" \
            --output json \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' 2>/dev/null | \
        jq -r '.[] | "--key \(.Key) --version-id \(.VersionId)"' | \
        while read -r args; do
            aws s3api delete-object --bucket "${S3_BUCKET_NAME}" $args &> /dev/null || true
        done
        
        # Remove delete markers
        aws s3api list-object-versions \
            --bucket "${S3_BUCKET_NAME}" \
            --output json \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' 2>/dev/null | \
        jq -r '.[] | "--key \(.Key) --version-id \(.VersionId)"' | \
        while read -r args; do
            aws s3api delete-object --bucket "${S3_BUCKET_NAME}" $args &> /dev/null || true
        done
    fi
    
    # Delete the bucket
    if aws s3 rb "s3://${S3_BUCKET_NAME}"; then
        log_success "Deleted S3 bucket: ${S3_BUCKET_NAME}"
    else
        log_error "Failed to delete S3 bucket: ${S3_BUCKET_NAME}"
    fi
}

delete_iam_resources() {
    log_info "Deleting IAM roles and policies..."
    
    local roles=(
        "AgentCoreMonitoringRole-${RANDOM_SUFFIX}"
        "LambdaPerformanceMonitorRole-${RANDOM_SUFFIX}"
    )
    
    local policies=(
        "AgentCoreObservabilityPolicy-${RANDOM_SUFFIX}"
    )
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would delete ${#roles[@]} IAM roles and ${#policies[@]} policies"
        return 0
    fi
    
    # Delete IAM roles
    for role_name in "${roles[@]}"; do
        if aws iam get-role --role-name "${role_name}" &> /dev/null; then
            log_info "Deleting IAM role: ${role_name}"
            
            # Detach all attached policies
            local attached_policies=$(aws iam list-attached-role-policies \
                --role-name "${role_name}" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null || echo "")
            
            for policy_arn in ${attached_policies}; do
                if [[ -n "${policy_arn}" ]]; then
                    aws iam detach-role-policy \
                        --role-name "${role_name}" \
                        --policy-arn "${policy_arn}" || true
                    log_info "Detached policy: ${policy_arn}"
                fi
            done
            
            # Delete the role
            if aws iam delete-role --role-name "${role_name}"; then
                log_success "Deleted IAM role: ${role_name}"
            else
                log_error "Failed to delete IAM role: ${role_name}"
            fi
        else
            log_info "IAM role not found: ${role_name}"
        fi
    done
    
    # Delete IAM policies
    for policy_name in "${policies[@]}"; do
        local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
        
        if aws iam get-policy --policy-arn "${policy_arn}" &> /dev/null; then
            log_info "Deleting IAM policy: ${policy_name}"
            
            if aws iam delete-policy --policy-arn "${policy_arn}"; then
                log_success "Deleted IAM policy: ${policy_name}"
            else
                log_error "Failed to delete IAM policy: ${policy_name}"
            fi
        else
            log_info "IAM policy not found: ${policy_name}"
        fi
    done
}

#########################################################################
# Main Destruction Function
#########################################################################

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Destroy Performance Monitoring AI Agents infrastructure"
    echo
    echo "OPTIONS:"
    echo "  --force        Skip confirmation prompt"
    echo "  --dry-run      Show what would be deleted without actually deleting"
    echo "  --help         Show this help message"
    echo
    echo "EXAMPLES:"
    echo "  $0                # Interactive deletion with confirmation"
    echo "  $0 --force        # Force deletion without confirmation"
    echo "  $0 --dry-run      # Preview what would be deleted"
    echo
}

main() {
    log_info "Starting destruction of Performance Monitoring AI Agents infrastructure..."
    log_info "Script: $(basename "$0")"
    log_info "Version: 1.0"
    log_info "Log file: ${LOG_FILE}"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Load configuration and check prerequisites
    load_configuration
    check_prerequisites
    
    # Show what will be deleted and confirm
    if [[ "${DRY_RUN}" == "false" ]]; then
        confirm_deletion
    fi
    
    log_info "Beginning resource deletion..."
    
    # Delete resources in reverse order of creation
    delete_cloudwatch_alarms
    delete_cloudwatch_dashboard
    delete_metric_filters
    delete_lambda_function
    delete_log_groups
    delete_s3_bucket
    delete_iam_resources
    
    # Summary
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_success "DRY RUN completed - no resources were actually deleted"
    elif [[ $DELETION_ERRORS -eq 0 ]]; then
        log_success "All resources deleted successfully!"
        echo
        log_info "=== CLEANUP SUMMARY ==="
        log_info "Deleted CloudWatch alarms, dashboard, and log groups"
        log_info "Deleted Lambda function and IAM roles"
        log_info "Deleted S3 bucket and all contents"
        log_info "Deleted custom metric filters"
        echo
        log_success "Infrastructure cleanup completed!"
    else
        log_error "Cleanup completed with ${DELETION_ERRORS} errors"
        log_warning "Some resources may still exist"
        log_info "Check the log file for details: ${LOG_FILE}"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"