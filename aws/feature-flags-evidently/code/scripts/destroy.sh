#!/bin/bash

# Feature Flags with CloudWatch Evidently - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_INFO="${SCRIPT_DIR}/deployment-info.txt"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

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
    echo -e "${TIMESTAMP} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Print banner
print_banner() {
    echo -e "${RED}"
    echo "=================================================="
    echo "  AWS CloudWatch Evidently - Resource Cleanup"
    echo "=================================================="
    echo -e "${NC}"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ -f "${DEPLOYMENT_INFO}" ]]; then
        # Source the deployment info file to load variables
        source "${DEPLOYMENT_INFO}"
        log_success "Deployment information loaded from ${DEPLOYMENT_INFO}"
        log_info "Resources to clean up:"
        log_info "  • Project: ${PROJECT_NAME:-not-found}"
        log_info "  • Lambda: ${LAMBDA_FUNCTION_NAME:-not-found}"
        log_info "  • IAM Role: ${IAM_ROLE_NAME:-not-found}"
    else
        log_warning "Deployment info file not found. Attempting manual cleanup..."
        # Try to get info from user or environment
        get_manual_cleanup_info
    fi
}

# Get cleanup information manually if deployment info is missing
get_manual_cleanup_info() {
    log_info "Please provide the resource names to clean up:"
    
    # Try to get info from environment variables first
    if [[ -n "${PROJECT_NAME:-}" ]]; then
        log_info "Using PROJECT_NAME from environment: ${PROJECT_NAME}"
    else
        echo -n "Enter Evidently Project Name (or press Enter to skip): "
        read -r PROJECT_NAME
    fi
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        log_info "Using LAMBDA_FUNCTION_NAME from environment: ${LAMBDA_FUNCTION_NAME}"
    else
        echo -n "Enter Lambda Function Name (or press Enter to skip): "
        read -r LAMBDA_FUNCTION_NAME
    fi
    
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        log_info "Using IAM_ROLE_NAME from environment: ${IAM_ROLE_NAME}"
    else
        echo -n "Enter IAM Role Name (or press Enter to skip): "
        read -r IAM_ROLE_NAME
    fi
    
    # Set defaults for AWS info
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
}

# Confirm cleanup operation
confirm_cleanup() {
    echo
    echo -e "${YELLOW}WARNING: This will permanently delete the following resources:${NC}"
    [[ -n "${PROJECT_NAME:-}" ]] && echo "  • Evidently Project: ${PROJECT_NAME}"
    [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]] && echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    [[ -n "${IAM_ROLE_NAME:-}" ]] && echo "  • IAM Role: ${IAM_ROLE_NAME}"
    echo
    echo -e "${RED}This operation cannot be undone!${NC}"
    echo
    
    # Check if running in non-interactive mode
    if [[ "${1:-}" == "--force" ]] || [[ "${FORCE_CLEANUP:-}" == "true" ]]; then
        log_warning "Force cleanup mode enabled. Proceeding without confirmation."
        return 0
    fi
    
    echo -n "Are you sure you want to proceed? (type 'yes' to confirm): "
    read -r confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "User confirmed cleanup. Proceeding..."
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Stop and delete launch
cleanup_launch() {
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        log_warning "Project name not provided. Skipping launch cleanup."
        return 0
    fi
    
    log_info "Cleaning up launch configuration..."
    
    # Check if launch exists and get its status
    local launch_status
    launch_status=$(aws evidently get-launch \
        --project "${PROJECT_NAME}" \
        --launch "checkout-gradual-rollout" \
        --query 'status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "${launch_status}" == "NOT_FOUND" ]]; then
        log_info "Launch not found or already deleted"
        return 0
    fi
    
    log_info "Launch status: ${launch_status}"
    
    # Stop the launch if it's running
    if [[ "${launch_status}" == "RUNNING" ]]; then
        log_info "Stopping launch..."
        if aws evidently stop-launch \
            --project "${PROJECT_NAME}" \
            --launch "checkout-gradual-rollout" \
            --output table > /dev/null 2>&1; then
            log_success "Launch stopped successfully"
            
            # Wait for launch to stop
            log_info "Waiting for launch to stop..."
            sleep 10
        else
            log_warning "Failed to stop launch, but continuing with deletion"
        fi
    fi
    
    # Delete the launch
    log_info "Deleting launch configuration..."
    if aws evidently delete-launch \
        --project "${PROJECT_NAME}" \
        --launch "checkout-gradual-rollout" \
        --output table > /dev/null 2>&1; then
        log_success "Launch deleted: checkout-gradual-rollout"
    else
        log_warning "Failed to delete launch (may not exist)"
    fi
}

# Delete feature flag
cleanup_feature_flag() {
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        log_warning "Project name not provided. Skipping feature flag cleanup."
        return 0
    fi
    
    log_info "Deleting feature flag..."
    
    # Check if feature exists
    if aws evidently get-feature \
        --project "${PROJECT_NAME}" \
        --feature "new-checkout-flow" \
        --query 'name' --output text > /dev/null 2>&1; then
        
        # Delete the feature flag
        if aws evidently delete-feature \
            --project "${PROJECT_NAME}" \
            --feature "new-checkout-flow" \
            --output table > /dev/null 2>&1; then
            log_success "Feature flag deleted: new-checkout-flow"
        else
            log_error "Failed to delete feature flag"
            return 1
        fi
    else
        log_info "Feature flag not found or already deleted"
    fi
}

# Delete Evidently project
cleanup_evidently_project() {
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        log_warning "Project name not provided. Skipping project cleanup."
        return 0
    fi
    
    log_info "Deleting Evidently project..."
    
    # Check if project exists
    if aws evidently get-project \
        --project "${PROJECT_NAME}" \
        --query 'name' --output text > /dev/null 2>&1; then
        
        # Delete the project
        if aws evidently delete-project \
            --project "${PROJECT_NAME}" \
            --output table > /dev/null 2>&1; then
            log_success "Evidently project deleted: ${PROJECT_NAME}"
        else
            log_error "Failed to delete Evidently project"
            return 1
        fi
    else
        log_info "Evidently project not found or already deleted"
    fi
}

# Delete Lambda function
cleanup_lambda_function() {
    if [[ -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        log_warning "Lambda function name not provided. Skipping Lambda cleanup."
        return 0
    fi
    
    log_info "Deleting Lambda function..."
    
    # Check if function exists
    if aws lambda get-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --query 'FunctionName' --output text > /dev/null 2>&1; then
        
        # Delete the function
        if aws lambda delete-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --output table > /dev/null 2>&1; then
            log_success "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}"
        else
            log_error "Failed to delete Lambda function"
            return 1
        fi
    else
        log_info "Lambda function not found or already deleted"
    fi
}

# Delete IAM role
cleanup_iam_role() {
    if [[ -z "${IAM_ROLE_NAME:-}" ]]; then
        log_warning "IAM role name not provided. Skipping IAM cleanup."
        return 0
    fi
    
    log_info "Cleaning up IAM role..."
    
    # Check if role exists
    if aws iam get-role \
        --role-name "${IAM_ROLE_NAME}" \
        --query 'Role.RoleName' --output text > /dev/null 2>&1; then
        
        # Detach policies first
        log_info "Detaching policies from IAM role..."
        
        # Detach AWSLambdaBasicExecutionRole
        if aws iam detach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
            --output table > /dev/null 2>&1; then
            log_success "Detached AWSLambdaBasicExecutionRole policy"
        else
            log_warning "Failed to detach AWSLambdaBasicExecutionRole (may not be attached)"
        fi
        
        # Detach CloudWatchEvidentlyFullAccess
        if aws iam detach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::aws:policy/CloudWatchEvidentlyFullAccess" \
            --output table > /dev/null 2>&1; then
            log_success "Detached CloudWatchEvidentlyFullAccess policy"
        else
            log_warning "Failed to detach CloudWatchEvidentlyFullAccess (may not be attached)"
        fi
        
        # Wait for policy detachments to propagate
        log_info "Waiting for policy detachments to propagate..."
        sleep 5
        
        # Delete the role
        if aws iam delete-role \
            --role-name "${IAM_ROLE_NAME}" \
            --output table > /dev/null 2>&1; then
            log_success "IAM role deleted: ${IAM_ROLE_NAME}"
        else
            log_error "Failed to delete IAM role"
            return 1
        fi
    else
        log_info "IAM role not found or already deleted"
    fi
}

# Clean up temporary files
cleanup_temporary_files() {
    log_info "Cleaning up temporary files..."
    
    # List of files to clean up
    local files_to_clean=(
        "${SCRIPT_DIR}/response.json"
        "${SCRIPT_DIR}/lambda_function.py"
        "${SCRIPT_DIR}/lambda-package.zip"
        "${SCRIPT_DIR}/deployment-info.txt"
    )
    
    local cleaned_count=0
    for file in "${files_to_clean[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_success "Removed: $(basename "${file}")"
            ((cleaned_count++))
        fi
    done
    
    if [[ ${cleaned_count} -eq 0 ]]; then
        log_info "No temporary files found to clean up"
    else
        log_success "Cleaned up ${cleaned_count} temporary file(s)"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local issues_found=0
    
    # Check if Evidently project still exists
    if [[ -n "${PROJECT_NAME:-}" ]]; then
        if aws evidently get-project \
            --project "${PROJECT_NAME}" \
            --query 'name' --output text > /dev/null 2>&1; then
            log_warning "Evidently project still exists: ${PROJECT_NAME}"
            ((issues_found++))
        else
            log_success "Evidently project cleanup verified"
        fi
    fi
    
    # Check if Lambda function still exists
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --query 'FunctionName' --output text > /dev/null 2>&1; then
            log_warning "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
            ((issues_found++))
        else
            log_success "Lambda function cleanup verified"
        fi
    fi
    
    # Check if IAM role still exists
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        if aws iam get-role \
            --role-name "${IAM_ROLE_NAME}" \
            --query 'Role.RoleName' --output text > /dev/null 2>&1; then
            log_warning "IAM role still exists: ${IAM_ROLE_NAME}"
            ((issues_found++))
        else
            log_success "IAM role cleanup verified"
        fi
    fi
    
    if [[ ${issues_found} -gt 0 ]]; then
        log_warning "Cleanup verification found ${issues_found} issue(s)"
        log_warning "Some resources may still exist. Please check the AWS Console."
        return 1
    else
        log_success "Cleanup verification completed successfully"
        return 0
    fi
}

# Print cleanup summary
print_summary() {
    echo
    echo -e "${GREEN}=================================================="
    echo "         CLEANUP COMPLETED"
    echo -e "==================================================${NC}"
    echo
    echo -e "${BLUE}Removed Resources:${NC}"
    [[ -n "${PROJECT_NAME:-}" ]] && echo "  • Evidently Project: ${PROJECT_NAME}"
    [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]] && echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    [[ -n "${IAM_ROLE_NAME:-}" ]] && echo "  • IAM Role: ${IAM_ROLE_NAME}"
    echo "  • Temporary files and deployment artifacts"
    echo
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  • Verify no unexpected charges in AWS Billing Console"
    echo "  • Check CloudWatch Logs for any remaining log groups if needed"
    echo "  • Review IAM policies if you have custom requirements"
    echo
    echo -e "${GREEN}All resources have been successfully cleaned up!${NC}"
    echo
}

# Error handling for partial cleanup
handle_partial_cleanup() {
    log_error "Cleanup encountered errors. Some resources may still exist."
    echo
    echo -e "${YELLOW}Manual cleanup may be required for:${NC}"
    
    # Check what still exists and provide manual commands
    if [[ -n "${PROJECT_NAME:-}" ]]; then
        if aws evidently get-project --project "${PROJECT_NAME}" > /dev/null 2>&1; then
            echo "  • Evidently Project: aws evidently delete-project --project ${PROJECT_NAME}"
        fi
    fi
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" > /dev/null 2>&1; then
            echo "  • Lambda Function: aws lambda delete-function --function-name ${LAMBDA_FUNCTION_NAME}"
        fi
    fi
    
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        if aws iam get-role --role-name "${IAM_ROLE_NAME}" > /dev/null 2>&1; then
            echo "  • IAM Role: aws iam delete-role --role-name ${IAM_ROLE_NAME}"
            echo "    (Note: Detach policies first)"
        fi
    fi
    
    echo
    echo "Please run these commands manually or check the AWS Console."
}

# Main cleanup function
main() {
    print_banner
    
    log_info "Starting CloudWatch Evidently resource cleanup..."
    log_info "Cleanup log: ${LOG_FILE}"
    
    # Load resource information
    load_deployment_info
    
    # Confirm cleanup
    confirm_cleanup "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Execute cleanup steps in reverse order of creation
    local cleanup_failed=false
    
    # Stop and delete launch first (dependencies)
    if ! cleanup_launch; then
        cleanup_failed=true
    fi
    
    # Delete feature flag
    if ! cleanup_feature_flag; then
        cleanup_failed=true
    fi
    
    # Delete Evidently project
    if ! cleanup_evidently_project; then
        cleanup_failed=true
    fi
    
    # Delete Lambda function
    if ! cleanup_lambda_function; then
        cleanup_failed=true
    fi
    
    # Delete IAM role
    if ! cleanup_iam_role; then
        cleanup_failed=true
    fi
    
    # Clean up temporary files
    cleanup_temporary_files
    
    # Verify cleanup
    if verify_cleanup && [[ "${cleanup_failed}" == "false" ]]; then
        print_summary
        log_success "Cleanup completed successfully!"
    else
        handle_partial_cleanup
        log_error "Cleanup completed with errors. Please review the log and AWS Console."
        exit 1
    fi
}

# Handle script arguments
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [--force]"
    echo
    echo "Options:"
    echo "  --force    Skip confirmation prompts (use with caution)"
    echo "  --help     Show this help message"
    echo
    echo "This script removes all AWS resources created by the deploy.sh script."
    echo "It will ask for confirmation before proceeding unless --force is used."
    exit 0
fi

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi