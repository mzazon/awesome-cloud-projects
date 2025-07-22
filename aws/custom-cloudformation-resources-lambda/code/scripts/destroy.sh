#!/bin/bash

# =============================================================================
# Custom CloudFormation Resources Lambda-Backed Destroy Script
# =============================================================================
# This script safely destroys all infrastructure created by the deployment
# script, including CloudFormation stacks, Lambda functions, IAM roles,
# and S3 buckets.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate AWS permissions for resource deletion
# - Deployment information from successful deployment
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly LOG_FILE="${PROJECT_ROOT}/destroy.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
DEPLOYMENT_ID=""
AWS_REGION=""
AWS_ACCOUNT_ID=""
VERBOSE=false
DRY_RUN=false
FORCE=false
INTERACTIVE=true

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to file
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
    
    # Log to console with colors
    case "${level}" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}" >&2
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}" >&2
            ;;
        "DEBUG")
            if [[ "${VERBOSE}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} ${message}" >&2
            fi
            ;;
    esac
}

error_exit() {
    log "ERROR" "$1"
    exit 1
}

confirm_action() {
    if [[ "${INTERACTIVE}" == "true" && "${FORCE}" == "false" ]]; then
        echo -e "${YELLOW}$1${NC}"
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "INFO" "Operation cancelled by user"
            exit 0
        fi
    fi
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured."
    fi
    
    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install jq for JSON processing."
    fi
    
    log "INFO" "Prerequisites check passed"
}

discover_deployments() {
    log "INFO" "Discovering existing deployments..."
    
    local deployment_dirs=()
    
    # Find deployment directories
    for dir in "${PROJECT_ROOT}"/deployment-*; do
        if [[ -d "$dir" && -f "$dir/deployment-info.json" ]]; then
            deployment_dirs+=("$dir")
        fi
    done
    
    if [[ ${#deployment_dirs[@]} -eq 0 ]]; then
        log "WARN" "No deployment directories found"
        return 1
    fi
    
    echo -e "${BLUE}Available deployments:${NC}"
    for i in "${!deployment_dirs[@]}"; do
        local dir="${deployment_dirs[$i]}"
        local info_file="$dir/deployment-info.json"
        local deployment_id=$(jq -r '.deployment_id' "$info_file")
        local timestamp=$(jq -r '.timestamp' "$info_file")
        local status=$(jq -r '.status' "$info_file")
        
        echo "  $((i+1)). Deployment ID: $deployment_id"
        echo "     Created: $timestamp"
        echo "     Status: $status"
        echo "     Path: $dir"
        echo
    done
    
    if [[ "${INTERACTIVE}" == "true" ]]; then
        read -p "Select deployment to destroy (1-${#deployment_dirs[@]}): " selection
        
        if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#deployment_dirs[@]} ]]; then
            error_exit "Invalid selection"
        fi
        
        local selected_dir="${deployment_dirs[$((selection-1))]}"
    else
        # In non-interactive mode, use the most recent deployment
        local selected_dir="${deployment_dirs[0]}"
    fi
    
    # Load deployment info
    local info_file="$selected_dir/deployment-info.json"
    DEPLOYMENT_ID=$(jq -r '.deployment_id' "$info_file")
    AWS_REGION=$(jq -r '.aws_region' "$info_file")
    AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$info_file")
    
    # Set resource names
    export STACK_NAME=$(jq -r '.resources.stack_name' "$info_file")
    export LAMBDA_FUNCTION_NAME=$(jq -r '.resources.lambda_function_name' "$info_file")
    export IAM_ROLE_NAME=$(jq -r '.resources.iam_role_name' "$info_file")
    export S3_BUCKET_NAME=$(jq -r '.resources.s3_bucket_name' "$info_file")
    export PROD_STACK_NAME="production-custom-resource-${DEPLOYMENT_ID}"
    
    log "INFO" "Selected deployment: $DEPLOYMENT_ID"
    log "DEBUG" "Stack: $STACK_NAME"
    log "DEBUG" "Lambda: $LAMBDA_FUNCTION_NAME"
    log "DEBUG" "IAM Role: $IAM_ROLE_NAME"
    log "DEBUG" "S3 Bucket: $S3_BUCKET_NAME"
}

wait_for_stack_deletion() {
    local stack_name="$1"
    local max_wait=1800  # 30 minutes
    local wait_time=0
    
    log "INFO" "Waiting for stack deletion to complete: $stack_name"
    
    while [[ $wait_time -lt $max_wait ]]; do
        local status=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --query 'Stacks[0].StackStatus' \
            --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "$status" == "NOT_FOUND" ]]; then
            log "INFO" "Stack deleted successfully: $stack_name"
            return 0
        elif [[ "$status" == "DELETE_FAILED" ]]; then
            log "ERROR" "Stack deletion failed: $stack_name"
            return 1
        fi
        
        sleep 30
        wait_time=$((wait_time + 30))
        log "DEBUG" "Stack status: $status (waited ${wait_time}s)"
    done
    
    log "ERROR" "Stack deletion timed out after ${max_wait}s"
    return 1
}

delete_cloudformation_stacks() {
    log "INFO" "Deleting CloudFormation stacks..."
    
    local stacks_to_delete=("$STACK_NAME")
    
    # Check if production stack exists
    if aws cloudformation describe-stacks --stack-name "$PROD_STACK_NAME" &>/dev/null; then
        stacks_to_delete+=("$PROD_STACK_NAME")
    fi
    
    for stack in "${stacks_to_delete[@]}"; do
        if aws cloudformation describe-stacks --stack-name "$stack" &>/dev/null; then
            log "INFO" "Deleting stack: $stack"
            
            if [[ "${DRY_RUN}" == "false" ]]; then
                aws cloudformation delete-stack --stack-name "$stack"
                
                if ! wait_for_stack_deletion "$stack"; then
                    log "WARN" "Stack deletion failed or timed out: $stack"
                    
                    # List stack resources for debugging
                    log "DEBUG" "Stack resources:"
                    aws cloudformation list-stack-resources \
                        --stack-name "$stack" \
                        --query 'StackResourceSummaries[*].{Type:ResourceType,Status:ResourceStatus,Reason:ResourceStatusReason}' \
                        --output table 2>/dev/null || true
                fi
            else
                log "INFO" "DRY RUN: Would delete stack $stack"
            fi
        else
            log "WARN" "Stack does not exist: $stack"
        fi
    done
}

delete_lambda_functions() {
    log "INFO" "Deleting Lambda functions..."
    
    local functions_to_delete=("$LAMBDA_FUNCTION_NAME")
    
    # Check if advanced lambda function exists
    local advanced_lambda="advanced-custom-resource-${DEPLOYMENT_ID}"
    if aws lambda get-function --function-name "$advanced_lambda" &>/dev/null; then
        functions_to_delete+=("$advanced_lambda")
    fi
    
    for func in "${functions_to_delete[@]}"; do
        if aws lambda get-function --function-name "$func" &>/dev/null; then
            log "INFO" "Deleting Lambda function: $func"
            
            if [[ "${DRY_RUN}" == "false" ]]; then
                aws lambda delete-function --function-name "$func"
                log "INFO" "Lambda function deleted: $func"
            else
                log "INFO" "DRY RUN: Would delete Lambda function $func"
            fi
        else
            log "WARN" "Lambda function does not exist: $func"
        fi
    done
}

delete_iam_resources() {
    log "INFO" "Deleting IAM resources..."
    
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        log "INFO" "Deleting IAM role: $IAM_ROLE_NAME"
        
        if [[ "${DRY_RUN}" == "false" ]]; then
            # Detach managed policies
            aws iam detach-role-policy \
                --role-name "$IAM_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
                2>/dev/null || true
            
            # Detach custom policy
            aws iam detach-role-policy \
                --role-name "$IAM_ROLE_NAME" \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CustomResourceS3Policy-${DEPLOYMENT_ID}" \
                2>/dev/null || true
            
            # Delete custom policy
            aws iam delete-policy \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CustomResourceS3Policy-${DEPLOYMENT_ID}" \
                2>/dev/null || true
            
            # Delete role
            aws iam delete-role --role-name "$IAM_ROLE_NAME"
            log "INFO" "IAM role deleted: $IAM_ROLE_NAME"
        else
            log "INFO" "DRY RUN: Would delete IAM role $IAM_ROLE_NAME and associated policies"
        fi
    else
        log "WARN" "IAM role does not exist: $IAM_ROLE_NAME"
    fi
}

delete_s3_resources() {
    log "INFO" "Deleting S3 resources..."
    
    local buckets_to_delete=("$S3_BUCKET_NAME" "${S3_BUCKET_NAME}-standard")
    
    for bucket in "${buckets_to_delete[@]}"; do
        if aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
            log "INFO" "Deleting S3 bucket: $bucket"
            
            if [[ "${DRY_RUN}" == "false" ]]; then
                # Delete all objects including versions
                aws s3api list-object-versions \
                    --bucket "$bucket" \
                    --output text \
                    --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                    | while read -r key version; do
                        if [[ -n "$key" && -n "$version" ]]; then
                            aws s3api delete-object \
                                --bucket "$bucket" \
                                --key "$key" \
                                --version-id "$version" \
                                2>/dev/null || true
                        fi
                    done
                
                # Delete delete markers
                aws s3api list-object-versions \
                    --bucket "$bucket" \
                    --output text \
                    --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                    | while read -r key version; do
                        if [[ -n "$key" && -n "$version" ]]; then
                            aws s3api delete-object \
                                --bucket "$bucket" \
                                --key "$key" \
                                --version-id "$version" \
                                2>/dev/null || true
                        fi
                    done
                
                # Delete remaining objects
                aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
                
                # Delete bucket
                aws s3 rb "s3://$bucket" 2>/dev/null || true
                
                log "INFO" "S3 bucket deleted: $bucket"
            else
                log "INFO" "DRY RUN: Would delete S3 bucket $bucket and all contents"
            fi
        else
            log "WARN" "S3 bucket does not exist: $bucket"
        fi
    done
}

delete_cloudwatch_logs() {
    log "INFO" "Deleting CloudWatch log groups..."
    
    local log_groups=(
        "/aws/lambda/$LAMBDA_FUNCTION_NAME"
        "/aws/lambda/advanced-custom-resource-${DEPLOYMENT_ID}"
    )
    
    for log_group in "${log_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
            log "INFO" "Deleting log group: $log_group"
            
            if [[ "${DRY_RUN}" == "false" ]]; then
                aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || true
                log "INFO" "Log group deleted: $log_group"
            else
                log "INFO" "DRY RUN: Would delete log group $log_group"
            fi
        else
            log "WARN" "Log group does not exist: $log_group"
        fi
    done
}

cleanup_deployment_files() {
    log "INFO" "Cleaning up deployment files..."
    
    local deployment_dir="${PROJECT_ROOT}/deployment-${DEPLOYMENT_ID}"
    
    if [[ -d "$deployment_dir" ]]; then
        if [[ "${DRY_RUN}" == "false" ]]; then
            rm -rf "$deployment_dir"
            log "INFO" "Deployment directory removed: $deployment_dir"
        else
            log "INFO" "DRY RUN: Would remove deployment directory $deployment_dir"
        fi
    else
        log "WARN" "Deployment directory does not exist: $deployment_dir"
    fi
}

verify_cleanup() {
    log "INFO" "Verifying cleanup..."
    
    local cleanup_errors=0
    
    # Check CloudFormation stacks
    for stack in "$STACK_NAME" "$PROD_STACK_NAME"; do
        if aws cloudformation describe-stacks --stack-name "$stack" &>/dev/null; then
            log "ERROR" "Stack still exists: $stack"
            cleanup_errors=$((cleanup_errors + 1))
        fi
    done
    
    # Check Lambda functions
    for func in "$LAMBDA_FUNCTION_NAME" "advanced-custom-resource-${DEPLOYMENT_ID}"; do
        if aws lambda get-function --function-name "$func" &>/dev/null; then
            log "ERROR" "Lambda function still exists: $func"
            cleanup_errors=$((cleanup_errors + 1))
        fi
    done
    
    # Check IAM role
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        log "ERROR" "IAM role still exists: $IAM_ROLE_NAME"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check S3 buckets
    for bucket in "$S3_BUCKET_NAME" "${S3_BUCKET_NAME}-standard"; do
        if aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
            log "ERROR" "S3 bucket still exists: $bucket"
            cleanup_errors=$((cleanup_errors + 1))
        fi
    done
    
    if [[ $cleanup_errors -eq 0 ]]; then
        log "INFO" "Cleanup verification passed"
    else
        log "WARN" "Cleanup verification found $cleanup_errors issues"
    fi
    
    return $cleanup_errors
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Custom CloudFormation Resources and all associated infrastructure

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose logging
    -d, --dry-run           Show what would be deleted without actually deleting
    -f, --force             Skip confirmation prompts
    -n, --non-interactive   Run without user interaction (use latest deployment)
    -i, --deployment-id ID  Target specific deployment ID
    -r, --region REGION     AWS region (default: from deployment info)

Examples:
    $0                      Interactively select and destroy deployment
    $0 --force              Destroy latest deployment without confirmation
    $0 --dry-run            Show what would be destroyed
    $0 -i 1234567890        Destroy specific deployment ID

EOF
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    local specific_deployment_id=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -n|--non-interactive)
                INTERACTIVE=false
                shift
                ;;
            -i|--deployment-id)
                specific_deployment_id="$2"
                shift 2
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
    
    # Initialize log file
    echo "=== Custom CloudFormation Resources Destroy Started ===" > "${LOG_FILE}"
    
    log "INFO" "Starting destruction of Custom CloudFormation Resources"
    log "INFO" "Destroy script version: 1.0"
    log "INFO" "Dry run mode: ${DRY_RUN}"
    log "INFO" "Verbose mode: ${VERBOSE}"
    log "INFO" "Force mode: ${FORCE}"
    log "INFO" "Interactive mode: ${INTERACTIVE}"
    
    # Execute destroy steps
    check_prerequisites
    
    if [[ -n "$specific_deployment_id" ]]; then
        # Load specific deployment
        local deployment_dir="${PROJECT_ROOT}/deployment-${specific_deployment_id}"
        if [[ ! -d "$deployment_dir" || ! -f "$deployment_dir/deployment-info.json" ]]; then
            error_exit "Deployment not found: $specific_deployment_id"
        fi
        
        DEPLOYMENT_ID="$specific_deployment_id"
        local info_file="$deployment_dir/deployment-info.json"
        AWS_REGION=$(jq -r '.aws_region' "$info_file")
        AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$info_file")
        
        # Set resource names
        export STACK_NAME=$(jq -r '.resources.stack_name' "$info_file")
        export LAMBDA_FUNCTION_NAME=$(jq -r '.resources.lambda_function_name' "$info_file")
        export IAM_ROLE_NAME=$(jq -r '.resources.iam_role_name' "$info_file")
        export S3_BUCKET_NAME=$(jq -r '.resources.s3_bucket_name' "$info_file")
        export PROD_STACK_NAME="production-custom-resource-${DEPLOYMENT_ID}"
        
        log "INFO" "Using specific deployment: $DEPLOYMENT_ID"
    else
        # Discover deployments
        if ! discover_deployments; then
            error_exit "No deployments found to destroy"
        fi
    fi
    
    # Confirm destruction
    confirm_action "This will permanently destroy all resources for deployment ${DEPLOYMENT_ID}."
    
    # Execute destruction in reverse order
    log "INFO" "Starting resource destruction..."
    
    delete_cloudformation_stacks
    delete_lambda_functions
    delete_iam_resources
    delete_s3_resources
    delete_cloudwatch_logs
    cleanup_deployment_files
    
    # Verify cleanup
    if [[ "${DRY_RUN}" == "false" ]]; then
        verify_cleanup
    fi
    
    log "INFO" "Destruction completed!"
    log "INFO" "Deployment ID: ${DEPLOYMENT_ID}"
    log "INFO" "Log file: ${LOG_FILE}"
    
    echo
    echo -e "${GREEN}✅ Destruction completed successfully!${NC}"
    echo -e "${BLUE}Deployment ID:${NC} ${DEPLOYMENT_ID}"
    echo -e "${BLUE}Region:${NC} ${AWS_REGION}"
    echo -e "${BLUE}Log file:${NC} ${LOG_FILE}"
    echo
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo -e "${YELLOW}This was a dry run. No resources were actually destroyed.${NC}"
    else
        echo -e "${GREEN}All resources have been successfully destroyed.${NC}"
    fi
    echo
}

# Execute main function
main "$@"