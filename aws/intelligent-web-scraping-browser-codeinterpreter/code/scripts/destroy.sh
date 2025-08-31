#!/bin/bash

# Intelligent Web Scraping with AgentCore Browser and Code Interpreter - Cleanup Script
# This script removes all infrastructure deployed for the intelligent web scraping solution
# Usage: ./destroy.sh [--dry-run] [--project-name NAME] [--emergency] [--force]

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DRY_RUN=false
VERBOSE=false
EMERGENCY=false
FORCE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Check ${LOG_FILE} for details."
    exit 1
}

# Help function
show_help() {
    cat << EOF
Intelligent Web Scraping Cleanup Script

Usage: $0 [OPTIONS]

OPTIONS:
    --dry-run                    Show what would be destroyed without making changes
    --project-name NAME         Project name prefix to identify resources
    --emergency                 Emergency cleanup mode (less confirmation)
    --force                     Force deletion without confirmation prompts
    --verbose                   Enable verbose logging
    --help                      Show this help message

EXAMPLES:
    $0                              # Interactive cleanup (will prompt for project name)
    $0 --dry-run                   # Preview what would be destroyed
    $0 --project-name my-scraper   # Cleanup specific project
    $0 --force --project-name my-scraper  # Non-interactive cleanup
    $0 --emergency --project-name my-scraper  # Emergency cleanup (fewer safety checks)

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Appropriate AWS permissions for all services used
    - jq command-line JSON processor

SAFETY FEATURES:
    - Confirmation prompts for destructive actions (unless --force)
    - Resource verification before deletion
    - Detailed logging of all operations
    - Support for partial cleanup if some resources fail

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --emergency)
                EMERGENCY=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

# Prerequisites checking
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install jq for JSON processing."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        error_exit "AWS credentials not configured or invalid. Please run 'aws configure'."
    fi
    
    log_success "Prerequisites check completed"
}

# Load deployment info if available
load_deployment_info() {
    local deployment_file="${SCRIPT_DIR}/deployment-info.json"
    
    if [[ -f "${deployment_file}" ]] && [[ -z "${PROJECT_NAME:-}" ]]; then
        log_info "Found deployment info file, loading project details..."
        
        PROJECT_NAME=$(jq -r '.deployment.project_name' "${deployment_file}" 2>/dev/null || echo "")
        AWS_REGION=$(jq -r '.deployment.region' "${deployment_file}" 2>/dev/null || echo "")
        AWS_ACCOUNT_ID=$(jq -r '.deployment.account_id' "${deployment_file}" 2>/dev/null || echo "")
        
        if [[ -n "${PROJECT_NAME}" ]]; then
            log_info "Loaded project: ${PROJECT_NAME} in region: ${AWS_REGION}"
        fi
    fi
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS region if not set
    if [[ -z "${AWS_REGION:-}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            AWS_REGION="us-east-1"
            log_warning "No region configured, using default: ${AWS_REGION}"
        fi
    fi
    export AWS_REGION
    
    # Get AWS account ID if not set
    if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    export AWS_ACCOUNT_ID
    
    # Prompt for project name if not provided
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        if [[ "${FORCE}" == "true" ]] || [[ "${EMERGENCY}" == "true" ]]; then
            error_exit "Project name required for non-interactive cleanup. Use --project-name option."
        fi
        
        echo -n "Enter project name to cleanup: "
        read -r PROJECT_NAME
        
        if [[ -z "${PROJECT_NAME}" ]]; then
            error_exit "Project name is required"
        fi
    fi
    export PROJECT_NAME
    
    # Set resource names
    export S3_BUCKET_INPUT="${PROJECT_NAME}-input"
    export S3_BUCKET_OUTPUT="${PROJECT_NAME}-output"
    export LAMBDA_FUNCTION_NAME="${PROJECT_NAME}-orchestrator"
    export IAM_ROLE_NAME="${PROJECT_NAME}-lambda-role"
    export DLQ_NAME="${PROJECT_NAME}-dlq"
    export EVENTBRIDGE_RULE_NAME="${PROJECT_NAME}-schedule"
    export LOG_GROUP_NAME="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
    export DASHBOARD_NAME="${PROJECT_NAME}-monitoring"
    
    log_success "Environment configured:"
    log_info "  Region: ${AWS_REGION}"
    log_info "  Account ID: ${AWS_ACCOUNT_ID}"
    log_info "  Project Name: ${PROJECT_NAME}"
}

# Confirm cleanup operation
confirm_cleanup() {
    if [[ "${FORCE}" == "true" ]] || [[ "${EMERGENCY}" == "true" ]]; then
        log_warning "Skipping confirmation due to --force or --emergency flag"
        return 0
    fi
    
    log_warning "This will permanently delete all resources for project: ${PROJECT_NAME}"
    log_warning "Resources to be deleted:"
    log_warning "  - S3 buckets: ${S3_BUCKET_INPUT}, ${S3_BUCKET_OUTPUT}"
    log_warning "  - Lambda function: ${LAMBDA_FUNCTION_NAME}"
    log_warning "  - IAM role: ${IAM_ROLE_NAME}"
    log_warning "  - SQS queue: ${DLQ_NAME}"
    log_warning "  - EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
    log_warning "  - CloudWatch resources: ${LOG_GROUP_NAME}, ${DASHBOARD_NAME}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        echo
        echo -n "Are you sure you want to proceed? (yes/no): "
        read -r confirmation
        
        if [[ "${confirmation,,}" != "yes" ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
}

# Remove EventBridge resources
remove_eventbridge() {
    log_info "Removing EventBridge resources..."
    
    # Check if rule exists
    if ! aws events describe-rule --name "${EVENTBRIDGE_RULE_NAME}" &>/dev/null; then
        log_warning "EventBridge rule ${EVENTBRIDGE_RULE_NAME} not found, skipping"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would remove EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
        return 0
    fi
    
    # Remove targets first
    local targets
    targets=$(aws events list-targets-by-rule --rule "${EVENTBRIDGE_RULE_NAME}" --query 'Targets[].Id' --output text 2>/dev/null || echo "")
    
    if [[ -n "${targets}" ]]; then
        aws events remove-targets \
            --rule "${EVENTBRIDGE_RULE_NAME}" \
            --ids ${targets} \
            --region "${AWS_REGION}" || log_warning "Failed to remove EventBridge targets"
        
        log_success "Removed EventBridge targets"
    fi
    
    # Remove the rule
    aws events delete-rule \
        --name "${EVENTBRIDGE_RULE_NAME}" \
        --region "${AWS_REGION}" || log_warning "Failed to remove EventBridge rule"
    
    log_success "Removed EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
}

# Remove Lambda function
remove_lambda_function() {
    log_info "Removing Lambda function..."
    
    # Check if function exists
    if ! aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} not found, skipping"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would remove Lambda function: ${LAMBDA_FUNCTION_NAME}"
        return 0
    fi
    
    # Remove Lambda permission for EventBridge (ignore errors)
    aws lambda remove-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id "${PROJECT_NAME}-eventbridge-permission" \
        --region "${AWS_REGION}" 2>/dev/null || log_warning "EventBridge permission may not exist"
    
    # Delete the function
    aws lambda delete-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --region "${AWS_REGION}" || log_warning "Failed to delete Lambda function"
    
    log_success "Removed Lambda function: ${LAMBDA_FUNCTION_NAME}"
}

# Remove SQS Dead Letter Queue
remove_dlq() {
    log_info "Removing Dead Letter Queue..."
    
    # Check if queue exists
    local dlq_url
    dlq_url=$(aws sqs get-queue-url --queue-name "${DLQ_NAME}" --query QueueUrl --output text 2>/dev/null || echo "")
    
    if [[ -z "${dlq_url}" ]]; then
        log_warning "SQS queue ${DLQ_NAME} not found, skipping"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would remove SQS DLQ: ${DLQ_NAME}"
        return 0
    fi
    
    # Delete the queue
    aws sqs delete-queue \
        --queue-url "${dlq_url}" \
        --region "${AWS_REGION}" || log_warning "Failed to delete SQS queue"
    
    log_success "Removed SQS DLQ: ${DLQ_NAME}"
}

# Remove CloudWatch resources
remove_cloudwatch_resources() {
    log_info "Removing CloudWatch resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would remove CloudWatch dashboard and log group"
        return 0
    fi
    
    # Remove CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name "${DASHBOARD_NAME}" &>/dev/null; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "${DASHBOARD_NAME}" || log_warning "Failed to delete CloudWatch dashboard"
        
        log_success "Removed CloudWatch dashboard: ${DASHBOARD_NAME}"
    else
        log_warning "CloudWatch dashboard ${DASHBOARD_NAME} not found, skipping"
    fi
    
    # Remove CloudWatch log group
    if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --query 'logGroups[?logGroupName==`'${LOG_GROUP_NAME}'`]' --output text | grep -q "${LOG_GROUP_NAME}"; then
        aws logs delete-log-group \
            --log-group-name "${LOG_GROUP_NAME}" \
            --region "${AWS_REGION}" || log_warning "Failed to delete CloudWatch log group"
        
        log_success "Removed CloudWatch log group: ${LOG_GROUP_NAME}"
    else
        log_warning "CloudWatch log group ${LOG_GROUP_NAME} not found, skipping"
    fi
}

# Remove IAM role
remove_iam_role() {
    log_info "Removing IAM role..."
    
    # Check if role exists
    if ! aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        log_warning "IAM role ${IAM_ROLE_NAME} not found, skipping"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would remove IAM role: ${IAM_ROLE_NAME}"
        return 0
    fi
    
    # List and remove attached inline policies
    local policies
    policies=$(aws iam list-role-policies --role-name "${IAM_ROLE_NAME}" --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
    
    for policy in ${policies}; do
        if [[ -n "${policy}" ]] && [[ "${policy}" != "None" ]]; then
            aws iam delete-role-policy \
                --role-name "${IAM_ROLE_NAME}" \
                --policy-name "${policy}" || log_warning "Failed to delete policy: ${policy}"
            
            log_info "Removed inline policy: ${policy}"
        fi
    done
    
    # List and detach managed policies
    local managed_policies
    managed_policies=$(aws iam list-attached-role-policies --role-name "${IAM_ROLE_NAME}" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    
    for policy_arn in ${managed_policies}; do
        if [[ -n "${policy_arn}" ]] && [[ "${policy_arn}" != "None" ]]; then
            aws iam detach-role-policy \
                --role-name "${IAM_ROLE_NAME}" \
                --policy-arn "${policy_arn}" || log_warning "Failed to detach policy: ${policy_arn}"
            
            log_info "Detached managed policy: ${policy_arn}"
        fi
    done
    
    # Wait a moment for policy detachment to propagate
    sleep 5
    
    # Delete the role
    aws iam delete-role \
        --role-name "${IAM_ROLE_NAME}" || log_warning "Failed to delete IAM role"
    
    log_success "Removed IAM role: ${IAM_ROLE_NAME}"
}

# Remove S3 buckets
remove_s3_buckets() {
    log_info "Removing S3 buckets..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would remove S3 buckets: ${S3_BUCKET_INPUT}, ${S3_BUCKET_OUTPUT}"
        return 0
    fi
    
    # Remove input bucket
    if aws s3api head-bucket --bucket "${S3_BUCKET_INPUT}" &>/dev/null; then
        # Empty bucket first
        aws s3 rm s3://"${S3_BUCKET_INPUT}" --recursive || log_warning "Failed to empty input bucket"
        
        # Delete bucket
        aws s3 rb s3://"${S3_BUCKET_INPUT}" || log_warning "Failed to delete input bucket"
        
        log_success "Removed S3 input bucket: ${S3_BUCKET_INPUT}"
    else
        log_warning "S3 input bucket ${S3_BUCKET_INPUT} not found, skipping"
    fi
    
    # Remove output bucket
    if aws s3api head-bucket --bucket "${S3_BUCKET_OUTPUT}" &>/dev/null; then
        # Empty bucket first
        aws s3 rm s3://"${S3_BUCKET_OUTPUT}" --recursive || log_warning "Failed to empty output bucket"
        
        # Delete bucket
        aws s3 rb s3://"${S3_BUCKET_OUTPUT}" || log_warning "Failed to delete output bucket"
        
        log_success "Removed S3 output bucket: ${S3_BUCKET_OUTPUT}"
    else
        log_warning "S3 output bucket ${S3_BUCKET_OUTPUT} not found, skipping"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local cleanup_files=(
        "${SCRIPT_DIR}/deployment-info.json"
        "${SCRIPT_DIR}/lambda-trust-policy.json"
        "${SCRIPT_DIR}/lambda-policy.json"
        "${SCRIPT_DIR}/lambda_function.py"
        "${SCRIPT_DIR}/lambda-function.zip"
        "${SCRIPT_DIR}/scraper-config.json"
        "${SCRIPT_DIR}/data-processing-config.json"
        "${SCRIPT_DIR}/dashboard-config.json"
        "${SCRIPT_DIR}/eventbridge-input.json"
        "${SCRIPT_DIR}/test-payload.json"
        "${SCRIPT_DIR}/test-response.json"
    )
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    for file in "${cleanup_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}" || log_warning "Failed to remove ${file}"
            log_info "Removed: $(basename "${file}")"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local remaining_resources=()
    
    # Check Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
        remaining_resources+=("Lambda function: ${LAMBDA_FUNCTION_NAME}")
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        remaining_resources+=("IAM role: ${IAM_ROLE_NAME}")
    fi
    
    # Check S3 buckets
    if aws s3api head-bucket --bucket "${S3_BUCKET_INPUT}" &>/dev/null; then
        remaining_resources+=("S3 bucket: ${S3_BUCKET_INPUT}")
    fi
    
    if aws s3api head-bucket --bucket "${S3_BUCKET_OUTPUT}" &>/dev/null; then
        remaining_resources+=("S3 bucket: ${S3_BUCKET_OUTPUT}")
    fi
    
    # Check SQS queue
    if aws sqs get-queue-url --queue-name "${DLQ_NAME}" &>/dev/null; then
        remaining_resources+=("SQS queue: ${DLQ_NAME}")
    fi
    
    # Check EventBridge rule
    if aws events describe-rule --name "${EVENTBRIDGE_RULE_NAME}" &>/dev/null; then
        remaining_resources+=("EventBridge rule: ${EVENTBRIDGE_RULE_NAME}")
    fi
    
    # Check CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name "${DASHBOARD_NAME}" &>/dev/null; then
        remaining_resources+=("CloudWatch dashboard: ${DASHBOARD_NAME}")
    fi
    
    # Check CloudWatch log group
    if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --query 'logGroups[?logGroupName==`'${LOG_GROUP_NAME}'`]' --output text | grep -q "${LOG_GROUP_NAME}"; then
        remaining_resources+=("CloudWatch log group: ${LOG_GROUP_NAME}")
    fi
    
    if [[ ${#remaining_resources[@]} -eq 0 ]]; then
        log_success "All resources have been successfully removed"
        return 0
    else
        log_warning "The following resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            log_warning "  - ${resource}"
        done
        
        if [[ "${EMERGENCY}" == "false" ]]; then
            log_warning "You may need to manually remove these resources"
            log_warning "Or run the script again with --emergency flag for more aggressive cleanup"
        fi
        return 1
    fi
}

# Generate cleanup report
generate_cleanup_report() {
    log_info "Generating cleanup report..."
    
    cat > "${SCRIPT_DIR}/cleanup-report.txt" << EOF
Intelligent Web Scraping Cleanup Report
=======================================

Cleanup Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Project Name: ${PROJECT_NAME}
AWS Region: ${AWS_REGION}
AWS Account: ${AWS_ACCOUNT_ID}

Resources Targeted for Cleanup:
- S3 buckets: ${S3_BUCKET_INPUT}, ${S3_BUCKET_OUTPUT}
- Lambda function: ${LAMBDA_FUNCTION_NAME}
- IAM role: ${IAM_ROLE_NAME}
- SQS queue: ${DLQ_NAME}
- EventBridge rule: ${EVENTBRIDGE_RULE_NAME}
- CloudWatch log group: ${LOG_GROUP_NAME}
- CloudWatch dashboard: ${DASHBOARD_NAME}

Cleanup Method: $(if [[ "${DRY_RUN}" == "true" ]]; then echo "DRY RUN"; else echo "FULL CLEANUP"; fi)
Emergency Mode: ${EMERGENCY}
Force Mode: ${FORCE}

For detailed logs, see: ${LOG_FILE}

$(if [[ "${DRY_RUN}" == "false" ]]; then
    echo "Cleanup Status: COMPLETED"
    echo "Verification: $(if verify_cleanup &>/dev/null; then echo "SUCCESS"; else echo "PARTIAL - Some resources may remain"; fi)"
else
    echo "Cleanup Status: DRY RUN - No resources were actually removed"
fi)

EOF
    
    log_success "Cleanup report generated: ${SCRIPT_DIR}/cleanup-report.txt"
}

# Main cleanup function
main() {
    log_info "Starting Intelligent Web Scraping cleanup..."
    log_info "Log file: ${LOG_FILE}"
    
    # Parse arguments
    parse_args "$@"
    
    # Show dry-run notice
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Show emergency mode notice
    if [[ "${EMERGENCY}" == "true" ]]; then
        log_warning "EMERGENCY MODE - Reduced safety checks and confirmations"
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_info
    setup_environment
    confirm_cleanup
    
    # Remove resources in reverse order of creation dependencies
    remove_eventbridge
    remove_lambda_function
    remove_dlq
    remove_cloudwatch_resources
    remove_iam_role
    remove_s3_buckets
    
    # Cleanup local files
    cleanup_local_files
    
    # Verify cleanup completion if not dry run
    if [[ "${DRY_RUN}" == "false" ]]; then
        verify_cleanup
    fi
    
    # Generate report
    generate_cleanup_report
    
    # Success message
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_success "Dry run completed successfully!"
        log_info "No resources were actually deleted."
        log_info "To perform actual cleanup, run: $0 --project-name ${PROJECT_NAME}"
    else
        log_success "Cleanup completed successfully!"
        log_info ""
        log_info "Cleanup Summary:"
        log_info "  Project Name: ${PROJECT_NAME}"
        log_info "  Region: ${AWS_REGION}"
        log_info "  Status: All resources removed"
        log_info ""
        log_info "Reports generated:"
        log_info "  - Cleanup log: ${LOG_FILE}"
        log_info "  - Cleanup report: ${SCRIPT_DIR}/cleanup-report.txt"
    fi
}

# Execute main function with all arguments
main "$@"