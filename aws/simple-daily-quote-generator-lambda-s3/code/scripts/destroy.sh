#!/bin/bash

# destroy.sh - Simple Daily Quote Generator with Lambda and S3
# This script destroys all resources created by the quote generator deployment
# 
# Usage: ./destroy.sh [--force] [--verbose]
# 
# Prerequisites:
# - AWS CLI v2.0 or later installed and configured
# - IAM permissions for Lambda, S3, and IAM operations

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="/tmp/quote-generator-destroy-$(date +%Y%m%d_%H%M%S).log"

# Default values
FORCE=false
VERBOSE=false

# Resource configuration
FUNCTION_NAME="daily-quote-generator"

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Check log file: $LOG_FILE"
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [--force] [--verbose]"
                echo "  --force     Skip confirmation prompts (dangerous!)"
                echo "  --verbose   Enable verbose output"
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2.0 or later."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        error_exit "AWS credentials not configured. Run 'aws configure' to set up credentials."
    fi
    
    local caller_identity
    caller_identity=$(aws sts get-caller-identity 2>/dev/null) || error_exit "Failed to get AWS caller identity"
    log "AWS Account: $(echo "$caller_identity" | jq -r '.Account // "N/A"' 2>/dev/null || echo "N/A")"
    log "AWS User/Role: $(echo "$caller_identity" | jq -r '.Arn // "N/A"' 2>/dev/null || echo "N/A")"
    
    log_success "Prerequisites check passed"
}

# Discover existing resources
discover_resources() {
    log "Discovering existing resources..."
    
    # Initialize arrays to store discovered resources
    LAMBDA_FUNCTIONS=()
    S3_BUCKETS=()
    IAM_ROLES=()
    
    # Discover Lambda functions
    log "Searching for Lambda functions..."
    if aws lambda get-function --function-name "$FUNCTION_NAME" &>/dev/null; then
        LAMBDA_FUNCTIONS+=("$FUNCTION_NAME")
        log "Found Lambda function: $FUNCTION_NAME"
        
        # Get environment variables to find bucket name
        local env_vars
        env_vars=$(aws lambda get-function-configuration \
            --function-name "$FUNCTION_NAME" \
            --query 'Environment.Variables.BUCKET_NAME' \
            --output text 2>/dev/null)
        
        if [[ "$env_vars" != "None" && "$env_vars" != "null" && -n "$env_vars" ]]; then
            log "Found bucket name from Lambda environment: $env_vars"
            if aws s3api head-bucket --bucket "$env_vars" &>/dev/null; then
                S3_BUCKETS+=("$env_vars")
            fi
        fi
    fi
    
    # Discover S3 buckets (look for pattern if Lambda didn't provide bucket name)
    if [[ ${#S3_BUCKETS[@]} -eq 0 ]]; then
        log "Searching for S3 buckets with pattern 'daily-quotes-*'..."
        local buckets
        buckets=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `daily-quotes-`)].Name' --output text 2>/dev/null || echo "")
        
        if [[ -n "$buckets" ]]; then
            while read -r bucket; do
                if [[ -n "$bucket" ]]; then
                    S3_BUCKETS+=("$bucket")
                    log "Found S3 bucket: $bucket"
                fi
            done <<< "$buckets"
        fi
    fi
    
    # Discover IAM roles
    log "Searching for IAM roles with pattern 'lambda-s3-role-*'..."
    local roles
    roles=$(aws iam list-roles --query 'Roles[?starts_with(RoleName, `lambda-s3-role-`)].RoleName' --output text 2>/dev/null || echo "")
    
    if [[ -n "$roles" ]]; then
        while read -r role; do
            if [[ -n "$role" ]]; then
                IAM_ROLES+=("$role")
                log "Found IAM role: $role"
            fi
        done <<< "$roles"
    fi
    
    # Summary
    log "Resource discovery summary:"
    log "  Lambda functions: ${#LAMBDA_FUNCTIONS[@]}"
    log "  S3 buckets: ${#S3_BUCKETS[@]}"
    log "  IAM roles: ${#IAM_ROLES[@]}"
    
    # Check if any resources were found
    local total_resources=$((${#LAMBDA_FUNCTIONS[@]} + ${#S3_BUCKETS[@]} + ${#IAM_ROLES[@]}))
    if [[ $total_resources -eq 0 ]]; then
        log_warning "No resources found to delete"
        return 1
    fi
    
    return 0
}

# Show what will be deleted
show_deletion_plan() {
    echo
    echo "=========================================="
    echo "          DELETION PLAN"
    echo "=========================================="
    
    if [[ ${#LAMBDA_FUNCTIONS[@]} -gt 0 ]]; then
        echo "Lambda Functions to delete:"
        for func in "${LAMBDA_FUNCTIONS[@]}"; do
            echo "  - $func"
        done
        echo
    fi
    
    if [[ ${#S3_BUCKETS[@]} -gt 0 ]]; then
        echo "S3 Buckets to delete (including all contents):"
        for bucket in "${S3_BUCKETS[@]}"; do
            echo "  - $bucket"
            # Show bucket contents
            local objects
            objects=$(aws s3 ls "s3://$bucket" --recursive 2>/dev/null | wc -l || echo "0")
            echo "    └── Objects: $objects"
        done
        echo
    fi
    
    if [[ ${#IAM_ROLES[@]} -gt 0 ]]; then
        echo "IAM Roles to delete:"
        for role in "${IAM_ROLES[@]}"; do
            echo "  - $role"
        done
        echo
    fi
    
    echo "=========================================="
}

# Confirm deletion
confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    show_deletion_plan
    
    echo
    echo -e "${RED}WARNING: This action is irreversible!${NC}"
    echo -e "${RED}All data in S3 buckets will be permanently deleted!${NC}"
    echo
    
    read -p "Are you sure you want to delete all these resources? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "User confirmed deletion"
}

# Delete Lambda function and Function URL
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    for func in "${LAMBDA_FUNCTIONS[@]}"; do
        log "Deleting Lambda function: $func"
        
        # Delete function URL configuration first
        if aws lambda get-function-url-config --function-name "$func" &>/dev/null; then
            log "Deleting Function URL for: $func"
            aws lambda delete-function-url-config --function-name "$func" || \
                log_warning "Failed to delete Function URL for $func"
        fi
        
        # Delete the function
        if aws lambda delete-function --function-name "$func"; then
            log_success "Deleted Lambda function: $func"
        else
            log_error "Failed to delete Lambda function: $func"
        fi
    done
}

# Delete S3 buckets
delete_s3_buckets() {
    log "Deleting S3 buckets..."
    
    for bucket in "${S3_BUCKETS[@]}"; do
        log "Deleting S3 bucket: $bucket"
        
        # First, delete all objects in the bucket
        log "Deleting all objects in bucket: $bucket"
        if aws s3 rm "s3://$bucket" --recursive; then
            log "Deleted all objects in bucket: $bucket"
        else
            log_warning "Failed to delete some objects in bucket: $bucket"
        fi
        
        # Delete the bucket itself
        if aws s3 rb "s3://$bucket"; then
            log_success "Deleted S3 bucket: $bucket"
        else
            log_error "Failed to delete S3 bucket: $bucket"
        fi
    done
}

# Delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    for role in "${IAM_ROLES[@]}"; do
        log "Deleting IAM role: $role"
        
        # Detach managed policies
        log "Detaching managed policies from role: $role"
        local attached_policies
        attached_policies=$(aws iam list-attached-role-policies \
            --role-name "$role" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$attached_policies" ]]; then
            while read -r policy_arn; do
                if [[ -n "$policy_arn" ]]; then
                    log "Detaching policy: $policy_arn"
                    aws iam detach-role-policy \
                        --role-name "$role" \
                        --policy-arn "$policy_arn" || \
                        log_warning "Failed to detach policy: $policy_arn"
                fi
            done <<< "$attached_policies"
        fi
        
        # Delete inline policies
        log "Deleting inline policies from role: $role"
        local inline_policies
        inline_policies=$(aws iam list-role-policies \
            --role-name "$role" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$inline_policies" ]]; then
            while read -r policy_name; do
                if [[ -n "$policy_name" ]]; then
                    log "Deleting inline policy: $policy_name"
                    aws iam delete-role-policy \
                        --role-name "$role" \
                        --policy-name "$policy_name" || \
                        log_warning "Failed to delete inline policy: $policy_name"
                fi
            done <<< "$inline_policies"
        fi
        
        # Delete the role
        if aws iam delete-role --role-name "$role"; then
            log_success "Deleted IAM role: $role"
        else
            log_error "Failed to delete IAM role: $role"
        fi
    done
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_clean=(
        "$PROJECT_ROOT/.function_url"
        "$PROJECT_ROOT/quotes.json"
        "$PROJECT_ROOT/lambda_function.py"
        "$PROJECT_ROOT/function.zip"
        "$PROJECT_ROOT/trust-policy.json"
        "$PROJECT_ROOT/s3-policy.json"
        "$PROJECT_ROOT/test_response.json"
    )
    
    for file in "${files_to_clean[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file" && log "Removed local file: $(basename "$file")"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local errors=0
    
    # Check Lambda functions
    for func in "${LAMBDA_FUNCTIONS[@]}"; do
        if aws lambda get-function --function-name "$func" &>/dev/null; then
            log_error "Lambda function still exists: $func"
            ((errors++))
        else
            log "✓ Lambda function deleted: $func"
        fi
    done
    
    # Check S3 buckets
    for bucket in "${S3_BUCKETS[@]}"; do
        if aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
            log_error "S3 bucket still exists: $bucket"
            ((errors++))
        else
            log "✓ S3 bucket deleted: $bucket"
        fi
    done
    
    # Check IAM roles
    for role in "${IAM_ROLES[@]}"; do
        if aws iam get-role --role-name "$role" &>/dev/null; then
            log_error "IAM role still exists: $role"
            ((errors++))
        else
            log "✓ IAM role deleted: $role"
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_success "All resources successfully deleted"
    else
        log_error "Some resources failed to delete ($errors errors)"
        return 1
    fi
}

# Print cleanup summary
print_summary() {
    echo
    echo "=========================================="
    echo "          CLEANUP SUMMARY"
    echo "=========================================="
    echo "Lambda Functions: ${#LAMBDA_FUNCTIONS[@]} deleted"
    echo "S3 Buckets:       ${#S3_BUCKETS[@]} deleted"
    echo "IAM Roles:        ${#IAM_ROLES[@]} deleted"
    echo
    echo "Log file: $LOG_FILE"
    echo "=========================================="
}

# Main destruction function
main() {
    log "Starting cleanup of Simple Daily Quote Generator resources..."
    log "Log file: $LOG_FILE"
    
    parse_args "$@"
    check_prerequisites
    
    if ! discover_resources; then
        log "No resources found to delete. Exiting."
        exit 0
    fi
    
    confirm_deletion
    
    log "Starting resource deletion..."
    
    # Delete in reverse order of creation to handle dependencies
    delete_lambda_functions
    delete_iam_roles
    delete_s3_buckets
    cleanup_local_files
    
    if verify_deletion; then
        print_summary
        log_success "Cleanup completed successfully!"
    else
        log_error "Cleanup completed with errors. Some resources may need manual deletion."
        exit 1
    fi
}

# Run main function with all arguments
main "$@"