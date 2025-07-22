#!/bin/bash

# Destroy script for AI-Powered Infrastructure Code Generation with Amazon Q Developer
# This script safely removes all infrastructure created by the deploy script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup.log"
readonly AUTO_CONFIRM=${AUTO_CONFIRM:-false}
readonly DRY_RUN=${DRY_RUN:-false}

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Function to log info messages
log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

# Function to log success messages
log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

# Function to log warning messages
log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

# Function to log error messages
log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Function to confirm destructive actions
confirm_action() {
    local message="$1"
    local default_response="${2:-n}"
    
    if [[ "${AUTO_CONFIRM}" == "true" ]]; then
        log_info "Auto-confirm enabled: ${message} - YES"
        return 0
    fi
    
    echo -e "${YELLOW}${message} (y/N): ${NC}"
    read -r response
    response=${response:-${default_response}}
    
    if [[ "${response,,}" =~ ^(yes|y)$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Get account and region information
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    
    log_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "AWS Region: ${AWS_REGION}"
    
    log_success "Prerequisites check completed"
}

# Function to discover resources to clean up
discover_resources() {
    log_info "Discovering resources to clean up..."
    
    # Try to get resource names from environment variables first
    if [[ -n "${BUCKET_NAME:-}" && -n "${LAMBDA_FUNCTION_NAME:-}" && -n "${IAM_ROLE_NAME:-}" ]]; then
        log_info "Using provided resource names from environment variables"
        return 0
    fi
    
    # Discover S3 buckets matching our naming pattern
    log_info "Discovering S3 buckets with q-developer-templates prefix..."
    local buckets
    buckets=$(aws s3api list-buckets \
        --query 'Buckets[?starts_with(Name, `q-developer-templates-`)].Name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${buckets}" ]]; then
        echo "Found S3 buckets:"
        for bucket in ${buckets}; do
            echo "  - ${bucket}"
        done
        echo
        
        if [[ -z "${BUCKET_NAME:-}" ]]; then
            # If multiple buckets found, ask user to specify
            local bucket_count=$(echo "${buckets}" | wc -w)
            if [[ ${bucket_count} -eq 1 ]]; then
                export BUCKET_NAME="${buckets}"
                log_info "Using bucket: ${BUCKET_NAME}"
            else
                log_warning "Multiple buckets found. Please set BUCKET_NAME environment variable."
                echo "Example: export BUCKET_NAME=q-developer-templates-abc123"
                exit 1
            fi
        fi
    fi
    
    # Discover Lambda functions
    log_info "Discovering Lambda functions with template-processor prefix..."
    local functions
    functions=$(aws lambda list-functions \
        --query 'Functions[?starts_with(FunctionName, `template-processor-`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${functions}" ]]; then
        echo "Found Lambda functions:"
        for func in ${functions}; do
            echo "  - ${func}"
        done
        echo
        
        if [[ -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
            local func_count=$(echo "${functions}" | wc -w)
            if [[ ${func_count} -eq 1 ]]; then
                export LAMBDA_FUNCTION_NAME="${functions}"
                log_info "Using Lambda function: ${LAMBDA_FUNCTION_NAME}"
            else
                log_warning "Multiple Lambda functions found. Please set LAMBDA_FUNCTION_NAME environment variable."
                exit 1
            fi
        fi
    fi
    
    # Discover IAM roles
    log_info "Discovering IAM roles with q-developer-automation-role prefix..."
    local roles
    roles=$(aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `q-developer-automation-role-`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${roles}" ]]; then
        echo "Found IAM roles:"
        for role in ${roles}; do
            echo "  - ${role}"
        done
        echo
        
        if [[ -z "${IAM_ROLE_NAME:-}" ]]; then
            local role_count=$(echo "${roles}" | wc -w)
            if [[ ${role_count} -eq 1 ]]; then
                export IAM_ROLE_NAME="${roles}"
                log_info "Using IAM role: ${IAM_ROLE_NAME}"
            else
                log_warning "Multiple IAM roles found. Please set IAM_ROLE_NAME environment variable."
                exit 1
            fi
        fi
    fi
    
    # Discover custom policies
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        log_info "Discovering custom policies attached to role..."
        local policies
        policies=$(aws iam list-attached-role-policies \
            --role-name "${IAM_ROLE_NAME}" \
            --query 'AttachedPolicies[?starts_with(PolicyArn, `arn:aws:iam::'${AWS_ACCOUNT_ID}':policy/QDeveloperTemplateProcessorPolicy-`)].PolicyName' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${policies}" ]]; then
            export CUSTOM_POLICY_NAME="${policies}"
            log_info "Found custom policy: ${CUSTOM_POLICY_NAME}"
        fi
    fi
    
    # Check if any resources were found
    if [[ -z "${BUCKET_NAME:-}" && -z "${LAMBDA_FUNCTION_NAME:-}" && -z "${IAM_ROLE_NAME:-}" ]]; then
        log_warning "No Q Developer infrastructure resources found to clean up."
        log_info "This could mean:"
        log_info "  1. Resources have already been cleaned up"
        log_info "  2. Resources were created with different names"
        log_info "  3. You're running cleanup in a different region/account"
        return 1
    fi
    
    log_success "Resource discovery completed"
}

# Function to delete CloudFormation stacks created by the automation
delete_cloudformation_stacks() {
    log_info "Checking for CloudFormation stacks created by Q Developer automation..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would check and delete CloudFormation stacks"
        return 0
    fi
    
    # Find stacks with our tags
    local stacks
    stacks=$(aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query 'StackSummaries[?contains(StackName, `q-developer`)].StackName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${stacks}" ]]; then
        echo "Found CloudFormation stacks to delete:"
        for stack in ${stacks}; do
            echo "  - ${stack}"
        done
        echo
        
        if confirm_action "Delete these CloudFormation stacks?"; then
            for stack in ${stacks}; do
                log_info "Deleting stack: ${stack}"
                aws cloudformation delete-stack --stack-name "${stack}" || true
                
                # Wait for stack deletion to complete
                log_info "Waiting for stack deletion to complete..."
                aws cloudformation wait stack-delete-complete \
                    --stack-name "${stack}" \
                    --region "${AWS_REGION}" 2>/dev/null || true
                
                log_success "Stack ${stack} deleted successfully"
            done
        else
            log_warning "Skipping CloudFormation stack deletion"
        fi
    else
        log_info "No CloudFormation stacks found to delete"
    fi
}

# Function to remove S3 bucket and contents
delete_s3_bucket() {
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_info "No S3 bucket specified for deletion"
        return 0
    fi
    
    log_info "Preparing to delete S3 bucket: ${BUCKET_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete S3 bucket: ${BUCKET_NAME}"
        return 0
    fi
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" &>/dev/null; then
        log_warning "S3 bucket ${BUCKET_NAME} does not exist or is not accessible"
        return 0
    fi
    
    # Show bucket contents
    log_info "Checking bucket contents..."
    local object_count
    object_count=$(aws s3 ls "s3://${BUCKET_NAME}" --recursive | wc -l)
    
    if [[ ${object_count} -gt 0 ]]; then
        log_warning "Bucket contains ${object_count} objects"
        if confirm_action "Delete all objects in bucket ${BUCKET_NAME}?"; then
            log_info "Deleting all objects from bucket..."
            aws s3 rm "s3://${BUCKET_NAME}" --recursive || true
            log_success "All objects deleted from bucket"
        else
            log_error "Cannot delete bucket with objects. Please empty the bucket first."
            return 1
        fi
    fi
    
    # Delete bucket versions if versioning is enabled
    log_info "Checking for object versions..."
    local versions
    versions=$(aws s3api list-object-versions \
        --bucket "${BUCKET_NAME}" \
        --query 'Versions[].Key' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${versions}" ]]; then
        log_info "Deleting object versions..."
        aws s3api delete-objects \
            --bucket "${BUCKET_NAME}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${BUCKET_NAME}" \
                --output json \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" \
            2>/dev/null || true
    fi
    
    # Delete delete markers
    local delete_markers
    delete_markers=$(aws s3api list-object-versions \
        --bucket "${BUCKET_NAME}" \
        --query 'DeleteMarkers[].Key' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${delete_markers}" ]]; then
        log_info "Deleting delete markers..."
        aws s3api delete-objects \
            --bucket "${BUCKET_NAME}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${BUCKET_NAME}" \
                --output json \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" \
            2>/dev/null || true
    fi
    
    # Finally delete the bucket
    if confirm_action "Delete S3 bucket ${BUCKET_NAME}?"; then
        log_info "Deleting S3 bucket..."
        aws s3 rb "s3://${BUCKET_NAME}" --force || true
        log_success "S3 bucket deleted successfully"
    else
        log_warning "Skipping S3 bucket deletion"
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    if [[ -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        log_info "No Lambda function specified for deletion"
        return 0
    fi
    
    log_info "Preparing to delete Lambda function: ${LAMBDA_FUNCTION_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Lambda function: ${LAMBDA_FUNCTION_NAME}"
        return 0
    fi
    
    # Check if function exists
    if ! aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} does not exist"
        return 0
    fi
    
    if confirm_action "Delete Lambda function ${LAMBDA_FUNCTION_NAME}?"; then
        # Remove S3 trigger permissions first
        log_info "Removing S3 trigger permissions..."
        local statement_ids
        statement_ids=$(aws lambda get-policy \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --output json 2>/dev/null | \
            jq -r '.Policy | fromjson | .Statement[] | select(.Principal.Service == "s3.amazonaws.com") | .Sid' 2>/dev/null || echo "")
        
        for sid in ${statement_ids}; do
            if [[ -n "${sid}" && "${sid}" != "null" ]]; then
                log_info "Removing permission: ${sid}"
                aws lambda remove-permission \
                    --function-name "${LAMBDA_FUNCTION_NAME}" \
                    --statement-id "${sid}" 2>/dev/null || true
            fi
        done
        
        # Delete the function
        log_info "Deleting Lambda function..."
        aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}" || true
        log_success "Lambda function deleted successfully"
    else
        log_warning "Skipping Lambda function deletion"
    fi
}

# Function to delete IAM resources
delete_iam_resources() {
    if [[ -z "${IAM_ROLE_NAME:-}" ]]; then
        log_info "No IAM role specified for deletion"
        return 0
    fi
    
    log_info "Preparing to delete IAM resources for role: ${IAM_ROLE_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete IAM role: ${IAM_ROLE_NAME}"
        return 0
    fi
    
    # Check if role exists
    if ! aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        log_warning "IAM role ${IAM_ROLE_NAME} does not exist"
        return 0
    fi
    
    if confirm_action "Delete IAM role ${IAM_ROLE_NAME} and associated policies?"; then
        # Detach managed policies
        log_info "Detaching managed policies..."
        local managed_policies
        managed_policies=$(aws iam list-attached-role-policies \
            --role-name "${IAM_ROLE_NAME}" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        for policy_arn in ${managed_policies}; do
            if [[ -n "${policy_arn}" ]]; then
                log_info "Detaching policy: ${policy_arn}"
                aws iam detach-role-policy \
                    --role-name "${IAM_ROLE_NAME}" \
                    --policy-arn "${policy_arn}" || true
            fi
        done
        
        # Delete inline policies
        log_info "Deleting inline policies..."
        local inline_policies
        inline_policies=$(aws iam list-role-policies \
            --role-name "${IAM_ROLE_NAME}" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        for policy_name in ${inline_policies}; do
            if [[ -n "${policy_name}" ]]; then
                log_info "Deleting inline policy: ${policy_name}"
                aws iam delete-role-policy \
                    --role-name "${IAM_ROLE_NAME}" \
                    --policy-name "${policy_name}" || true
            fi
        done
        
        # Delete custom managed policy if it exists
        if [[ -n "${CUSTOM_POLICY_NAME:-}" ]]; then
            local custom_policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${CUSTOM_POLICY_NAME}"
            log_info "Deleting custom policy: ${CUSTOM_POLICY_NAME}"
            aws iam delete-policy --policy-arn "${custom_policy_arn}" 2>/dev/null || true
        fi
        
        # Delete the role
        log_info "Deleting IAM role..."
        aws iam delete-role --role-name "${IAM_ROLE_NAME}" || true
        log_success "IAM resources deleted successfully"
    else
        log_warning "Skipping IAM resource deletion"
    fi
}

# Function to clean up CloudWatch Log Groups
delete_cloudwatch_logs() {
    if [[ -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        log_info "No Lambda function name available for log group cleanup"
        return 0
    fi
    
    local log_group_name="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
    
    log_info "Checking for CloudWatch Log Group: ${log_group_name}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete CloudWatch Log Group: ${log_group_name}"
        return 0
    fi
    
    # Check if log group exists
    if aws logs describe-log-groups --log-group-name-prefix "${log_group_name}" --query 'logGroups[0].logGroupName' --output text | grep -q "${log_group_name}"; then
        if confirm_action "Delete CloudWatch Log Group ${log_group_name}?"; then
            log_info "Deleting CloudWatch Log Group..."
            aws logs delete-log-group --log-group-name "${log_group_name}" || true
            log_success "CloudWatch Log Group deleted successfully"
        else
            log_warning "Skipping CloudWatch Log Group deletion"
        fi
    else
        log_info "CloudWatch Log Group does not exist"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_complete=true
    
    # Check S3 bucket
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket "${BUCKET_NAME}" &>/dev/null; then
            log_warning "❌ S3 bucket ${BUCKET_NAME} still exists"
            cleanup_complete=false
        else
            log_success "✅ S3 bucket successfully removed"
        fi
    fi
    
    # Check Lambda function
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
            log_warning "❌ Lambda function ${LAMBDA_FUNCTION_NAME} still exists"
            cleanup_complete=false
        else
            log_success "✅ Lambda function successfully removed"
        fi
    fi
    
    # Check IAM role
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
            log_warning "❌ IAM role ${IAM_ROLE_NAME} still exists"
            cleanup_complete=false
        else
            log_success "✅ IAM role successfully removed"
        fi
    fi
    
    if [[ "${cleanup_complete}" == "true" ]]; then
        log_success "Cleanup verification completed successfully"
    else
        log_warning "Some resources may still exist. Manual cleanup may be required."
        return 1
    fi
}

# Function to display cleanup summary
display_summary() {
    log_info "Cleanup Summary:"
    echo
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo -e "${BLUE}DRY RUN: No resources were actually deleted${NC}"
    else
        echo -e "${GREEN}AI-Powered Infrastructure Code Generation pipeline cleanup completed${NC}"
    fi
    echo
    echo "Resources processed:"
    [[ -n "${BUCKET_NAME:-}" ]] && echo "  S3 Bucket: ${BUCKET_NAME}"
    [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]] && echo "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    [[ -n "${IAM_ROLE_NAME:-}" ]] && echo "  IAM Role: ${IAM_ROLE_NAME}"
    [[ -n "${CUSTOM_POLICY_NAME:-}" ]] && echo "  Custom Policy: ${CUSTOM_POLICY_NAME}"
    echo "  AWS Region: ${AWS_REGION}"
    echo "  AWS Account: ${AWS_ACCOUNT_ID}"
    echo
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        echo "All Q Developer infrastructure resources have been removed."
        echo "You may want to check the AWS Console to verify cleanup completion."
    fi
    echo
}

# Main execution function
main() {
    echo -e "${BLUE}Starting cleanup of AI-Powered Infrastructure Code Generation pipeline...${NC}"
    echo "Log file: ${LOG_FILE}"
    echo
    
    # Check if this is a dry run
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Running in DRY RUN mode - no resources will be deleted"
    fi
    
    # Display warning for destructive action
    if [[ "${AUTO_CONFIRM}" != "true" && "${DRY_RUN}" != "true" ]]; then
        echo -e "${RED}WARNING: This script will delete AWS resources and cannot be undone!${NC}"
        echo -e "${RED}Make sure you want to completely remove the Q Developer infrastructure.${NC}"
        echo
        if ! confirm_action "Continue with cleanup?"; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
        echo
    fi
    
    # Execute cleanup steps
    check_prerequisites
    
    if ! discover_resources; then
        log_info "No resources found to clean up. Exiting."
        exit 0
    fi
    
    delete_cloudformation_stacks
    delete_lambda_function
    delete_s3_bucket
    delete_iam_resources
    delete_cloudwatch_logs
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        verify_cleanup
    fi
    
    display_summary
    log_success "Cleanup completed successfully!"
}

# Script usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --auto-confirm      Skip confirmation prompts (dangerous!)"
    echo "  --dry-run          Show what would be deleted without actually deleting"
    echo "  --help             Show this help message"
    echo
    echo "Environment Variables:"
    echo "  BUCKET_NAME              S3 bucket name to delete"
    echo "  LAMBDA_FUNCTION_NAME     Lambda function name to delete"
    echo "  IAM_ROLE_NAME           IAM role name to delete"
    echo "  CUSTOM_POLICY_NAME      Custom policy name to delete"
    echo "  AUTO_CONFIRM=true       Skip all confirmation prompts"
    echo "  DRY_RUN=true           Enable dry-run mode"
    echo "  AWS_REGION             Override AWS region"
    echo
    echo "Examples:"
    echo "  $0                     Interactive cleanup with confirmations"
    echo "  $0 --auto-confirm     Delete all resources without prompts"
    echo "  $0 --dry-run          Preview what would be deleted"
    echo "  BUCKET_NAME=my-bucket $0  Cleanup specific bucket"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-confirm)
            AUTO_CONFIRM=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
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

# Run main function
main "$@"