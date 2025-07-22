#!/bin/bash

# AWS X-Ray Infrastructure Monitoring - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Confirmation prompt
confirm() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        info "Force mode enabled, proceeding with $message"
        return 0
    fi
    
    echo -e "${YELLOW}$message${NC}"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        info "Operation cancelled"
        return 1
    fi
}

# Load environment variables
load_environment() {
    info "Loading environment variables..."
    
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        # Source the environment file
        source "${SCRIPT_DIR}/.env"
        success "Environment variables loaded from .env file"
        info "Project Name: ${PROJECT_NAME:-Not set}"
        info "AWS Region: ${AWS_REGION:-Not set}"
        info "AWS Account: ${AWS_ACCOUNT_ID:-Not set}"
    else
        warning "No .env file found. You may need to provide environment variables manually."
        
        # Try to get from AWS CLI configuration
        export AWS_REGION=$(aws configure get region 2>/dev/null || echo "")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        
        if [[ -z "${PROJECT_NAME:-}" ]]; then
            warning "PROJECT_NAME not set. You may need to manually specify resource names."
            return 1
        fi
    fi
    
    # Validate essential variables
    if [[ -z "${AWS_REGION:-}" ]]; then
        error_exit "AWS_REGION not set. Please configure AWS CLI or set environment variables."
    fi
    
    if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
        error_exit "AWS_ACCOUNT_ID not set. Please configure AWS CLI or set environment variables."
    fi
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure'."
    fi
    
    success "Prerequisites check completed"
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    info "Deleting CloudWatch resources..."
    
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        warning "PROJECT_NAME not set, skipping CloudWatch resource deletion"
        return 0
    fi
    
    # Delete CloudWatch alarms
    info "Deleting CloudWatch alarms..."
    local alarms=(
        "${PROJECT_NAME}-high-error-rate"
        "${PROJECT_NAME}-high-latency"
    )
    
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "${alarm}" --query 'MetricAlarms[0]' --output text &>/dev/null; then
            aws cloudwatch delete-alarms --alarm-names "${alarm}" || warning "Failed to delete alarm: ${alarm}"
            success "Deleted CloudWatch alarm: ${alarm}"
        else
            info "CloudWatch alarm not found: ${alarm}"
        fi
    done
    
    # Delete CloudWatch dashboard
    info "Deleting CloudWatch dashboard..."
    local dashboard_name="${PROJECT_NAME}-xray-monitoring"
    if aws cloudwatch get-dashboard --dashboard-name "${dashboard_name}" &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "${dashboard_name}" || warning "Failed to delete dashboard: ${dashboard_name}"
        success "Deleted CloudWatch dashboard: ${dashboard_name}"
    else
        info "CloudWatch dashboard not found: ${dashboard_name}"
    fi
}

# Delete EventBridge resources
delete_eventbridge_resources() {
    info "Deleting EventBridge resources..."
    
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        warning "PROJECT_NAME not set, skipping EventBridge resource deletion"
        return 0
    fi
    
    local rule_name="${PROJECT_NAME}-trace-analysis"
    
    # Remove targets from EventBridge rule
    info "Removing EventBridge rule targets..."
    if aws events describe-rule --name "${rule_name}" &>/dev/null; then
        # Get target IDs
        local target_ids=$(aws events list-targets-by-rule --rule "${rule_name}" --query 'Targets[].Id' --output text)
        
        if [[ -n "${target_ids}" ]]; then
            aws events remove-targets --rule "${rule_name}" --ids ${target_ids} || warning "Failed to remove targets from rule: ${rule_name}"
            success "Removed targets from EventBridge rule: ${rule_name}"
        fi
        
        # Delete EventBridge rule
        aws events delete-rule --name "${rule_name}" || warning "Failed to delete rule: ${rule_name}"
        success "Deleted EventBridge rule: ${rule_name}"
    else
        info "EventBridge rule not found: ${rule_name}"
    fi
}

# Delete Lambda functions
delete_lambda_functions() {
    info "Deleting Lambda functions..."
    
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        warning "PROJECT_NAME not set, skipping Lambda function deletion"
        return 0
    fi
    
    local functions=(
        "${PROJECT_NAME}-order-processor"
        "${PROJECT_NAME}-inventory-manager"
        "${PROJECT_NAME}-trace-analyzer"
    )
    
    for function_name in "${functions[@]}"; do
        if aws lambda get-function --function-name "${function_name}" &>/dev/null; then
            aws lambda delete-function --function-name "${function_name}" || warning "Failed to delete function: ${function_name}"
            success "Deleted Lambda function: ${function_name}"
        else
            info "Lambda function not found: ${function_name}"
        fi
    done
}

# Delete API Gateway
delete_api_gateway() {
    info "Deleting API Gateway..."
    
    # Check if API_ID is available from environment
    if [[ -n "${API_ID:-}" ]]; then
        if aws apigateway get-rest-api --rest-api-id "${API_ID}" &>/dev/null; then
            aws apigateway delete-rest-api --rest-api-id "${API_ID}" || warning "Failed to delete API Gateway: ${API_ID}"
            success "Deleted API Gateway: ${API_ID}"
        else
            info "API Gateway not found: ${API_ID}"
        fi
    elif [[ -n "${API_GATEWAY_NAME:-}" ]]; then
        # Try to find API by name
        local api_id=$(aws apigateway get-rest-apis --query "items[?name=='${API_GATEWAY_NAME}'].id" --output text)
        if [[ -n "${api_id}" && "${api_id}" != "None" ]]; then
            aws apigateway delete-rest-api --rest-api-id "${api_id}" || warning "Failed to delete API Gateway: ${api_id}"
            success "Deleted API Gateway: ${api_id} (${API_GATEWAY_NAME})"
        else
            info "API Gateway not found: ${API_GATEWAY_NAME}"
        fi
    else
        warning "API Gateway ID or name not found, skipping deletion"
    fi
}

# Delete X-Ray resources
delete_xray_resources() {
    info "Deleting X-Ray resources..."
    
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        warning "PROJECT_NAME not set, skipping X-Ray resource deletion"
        return 0
    fi
    
    # Delete filter groups
    info "Deleting X-Ray filter groups..."
    local filter_groups=(
        "${PROJECT_NAME}-high-latency"
        "${PROJECT_NAME}-errors"
        "${PROJECT_NAME}-order-service"
    )
    
    for group_name in "${filter_groups[@]}"; do
        if aws xray get-group --group-name "${group_name}" &>/dev/null; then
            aws xray delete-group --group-name "${group_name}" || warning "Failed to delete filter group: ${group_name}"
            success "Deleted X-Ray filter group: ${group_name}"
        else
            info "X-Ray filter group not found: ${group_name}"
        fi
    done
    
    # Delete sampling rules
    info "Deleting X-Ray sampling rules..."
    local sampling_rules=(
        "${PROJECT_NAME}-high-priority"
        "${PROJECT_NAME}-errors"
    )
    
    for rule_name in "${sampling_rules[@]}"; do
        if aws xray get-sampling-rule --rule-name "${rule_name}" &>/dev/null; then
            aws xray delete-sampling-rule --rule-name "${rule_name}" || warning "Failed to delete sampling rule: ${rule_name}"
            success "Deleted X-Ray sampling rule: ${rule_name}"
        else
            info "X-Ray sampling rule not found: ${rule_name}"
        fi
    done
}

# Delete DynamoDB table
delete_dynamodb_table() {
    info "Deleting DynamoDB table..."
    
    if [[ -z "${ORDERS_TABLE_NAME:-}" ]]; then
        warning "ORDERS_TABLE_NAME not set, skipping DynamoDB table deletion"
        return 0
    fi
    
    if aws dynamodb describe-table --table-name "${ORDERS_TABLE_NAME}" &>/dev/null; then
        if confirm "Delete DynamoDB table '${ORDERS_TABLE_NAME}' and all its data?"; then
            aws dynamodb delete-table --table-name "${ORDERS_TABLE_NAME}" || warning "Failed to delete table: ${ORDERS_TABLE_NAME}"
            
            # Wait for table deletion
            info "Waiting for DynamoDB table deletion to complete..."
            aws dynamodb wait table-not-exists --table-name "${ORDERS_TABLE_NAME}" || warning "Timeout waiting for table deletion"
            
            success "Deleted DynamoDB table: ${ORDERS_TABLE_NAME}"
        else
            warning "Skipped DynamoDB table deletion"
        fi
    else
        info "DynamoDB table not found: ${ORDERS_TABLE_NAME}"
    fi
}

# Delete IAM role
delete_iam_role() {
    info "Deleting IAM role..."
    
    if [[ -z "${LAMBDA_ROLE_NAME:-}" ]]; then
        warning "LAMBDA_ROLE_NAME not set, skipping IAM role deletion"
        return 0
    fi
    
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &>/dev/null; then
        # Detach policies first
        info "Detaching policies from IAM role..."
        local policies=(
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
            "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
        )
        
        for policy_arn in "${policies[@]}"; do
            aws iam detach-role-policy --role-name "${LAMBDA_ROLE_NAME}" --policy-arn "${policy_arn}" &>/dev/null || info "Policy not attached: ${policy_arn}"
        done
        
        # Delete the role
        aws iam delete-role --role-name "${LAMBDA_ROLE_NAME}" || warning "Failed to delete role: ${LAMBDA_ROLE_NAME}"
        success "Deleted IAM role: ${LAMBDA_ROLE_NAME}"
    else
        info "IAM role not found: ${LAMBDA_ROLE_NAME}"
    fi
}

# List resources for manual verification
list_remaining_resources() {
    info "Checking for any remaining resources..."
    
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        warning "PROJECT_NAME not set, skipping resource verification"
        return 0
    fi
    
    local found_resources=false
    
    # Check Lambda functions
    local lambda_functions=$(aws lambda list-functions --query "Functions[?contains(FunctionName, '${PROJECT_NAME}')].FunctionName" --output text)
    if [[ -n "${lambda_functions}" ]]; then
        warning "Remaining Lambda functions found: ${lambda_functions}"
        found_resources=true
    fi
    
    # Check API Gateways
    local api_gateways=$(aws apigateway get-rest-apis --query "items[?contains(name, '${PROJECT_NAME}')].name" --output text)
    if [[ -n "${api_gateways}" ]]; then
        warning "Remaining API Gateways found: ${api_gateways}"
        found_resources=true
    fi
    
    # Check DynamoDB tables
    local dynamo_tables=$(aws dynamodb list-tables --query "TableNames[?contains(@, '${PROJECT_NAME}')]" --output text)
    if [[ -n "${dynamo_tables}" ]]; then
        warning "Remaining DynamoDB tables found: ${dynamo_tables}"
        found_resources=true
    fi
    
    # Check IAM roles
    local iam_roles=$(aws iam list-roles --query "Roles[?contains(RoleName, '${PROJECT_NAME}')].RoleName" --output text)
    if [[ -n "${iam_roles}" ]]; then
        warning "Remaining IAM roles found: ${iam_roles}"
        found_resources=true
    fi
    
    # Check CloudWatch alarms
    local cw_alarms=$(aws cloudwatch describe-alarms --query "MetricAlarms[?contains(AlarmName, '${PROJECT_NAME}')].AlarmName" --output text)
    if [[ -n "${cw_alarms}" ]]; then
        warning "Remaining CloudWatch alarms found: ${cw_alarms}"
        found_resources=true
    fi
    
    if [[ "${found_resources}" == "false" ]]; then
        success "No remaining resources found"
    else
        warning "Some resources may still exist. Please check the AWS console and delete them manually if needed."
    fi
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # List files to be removed
    local files_to_remove=(
        "${SCRIPT_DIR}/.env"
        "/tmp/lambda-trust-policy.json"
        "/tmp/high-priority-sampling.json"
        "/tmp/error-sampling.json"
        "/tmp/xray-dashboard.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}" || warning "Failed to remove file: ${file}"
            success "Removed file: ${file}"
        fi
    done
    
    success "Local cleanup completed"
}

# Main destroy function
main() {
    echo "=========================================="
    echo "AWS X-Ray Infrastructure Monitoring"
    echo "Cleanup Script"
    echo "=========================================="
    echo ""
    
    # Initialize log file
    echo "Cleanup started at $(date)" > "${LOG_FILE}"
    
    # Check for force mode
    if [[ "${1:-}" == "--force" ]]; then
        export FORCE_DESTROY=true
        warning "Force mode enabled - all confirmations will be skipped"
    fi
    
    # Check if running in dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        info "Running in dry-run mode - no resources will be deleted"
        DRY_RUN=true
    else
        DRY_RUN=false
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "Dry-run mode: would perform the following actions:"
        info "1. Load environment variables"
        info "2. Check prerequisites"
        info "3. Delete CloudWatch resources (dashboard and alarms)"
        info "4. Delete EventBridge rule and targets"
        info "5. Delete Lambda functions"
        info "6. Delete API Gateway"
        info "7. Delete X-Ray resources (filter groups and sampling rules)"
        info "8. Delete DynamoDB table"
        info "9. Delete IAM role"
        info "10. Verify cleanup and remove local files"
        return 0
    fi
    
    # Main confirmation
    if ! confirm "This will delete ALL resources created by the X-Ray monitoring deployment."; then
        info "Cleanup cancelled"
        exit 0
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_environment
    
    # Delete resources in reverse order of creation
    delete_cloudwatch_resources
    delete_eventbridge_resources
    delete_lambda_functions
    delete_api_gateway
    delete_xray_resources
    delete_dynamodb_table
    delete_iam_role
    
    # Verify cleanup
    list_remaining_resources
    cleanup_local_files
    
    echo ""
    echo "=========================================="
    success "Cleanup completed successfully!"
    echo "=========================================="
    echo ""
    info "All X-Ray monitoring resources have been removed."
    info "Please check your AWS bill to ensure no unexpected charges."
    echo ""
    warning "Note: X-Ray traces and CloudWatch logs may still exist and incur minimal charges."
    warning "These will automatically expire based on their retention policies."
    echo ""
}

# Handle script interruption
trap 'echo -e "\n${RED}Script interrupted. Some resources may not have been cleaned up.${NC}"; exit 1' INT TERM

# Run main function
main "$@"