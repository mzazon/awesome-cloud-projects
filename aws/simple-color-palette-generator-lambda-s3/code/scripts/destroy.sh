#!/bin/bash

#######################################################################
# AWS Simple Color Palette Generator - Cleanup Script
# 
# This script removes all resources created by the color palette
# generator deployment, including Lambda functions, S3 buckets,
# IAM roles, and policies.
#
# Prerequisites:
# - AWS CLI v2.0+ installed and configured
# - jq installed for JSON processing
# - Same AWS account and region as deployment
#
# Usage: ./destroy.sh [--force] [--dry-run]
#######################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FORCE_MODE="${1:-}"
readonly DRY_RUN="${2:-${1:-}}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check if running in dry-run mode
is_dry_run() {
    [[ "$DRY_RUN" == "--dry-run" ]]
}

# Check if running in force mode
is_force_mode() {
    [[ "$FORCE_MODE" == "--force" ]]
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="${2:-Executing command}"
    local ignore_error="${3:-false}"
    
    log_info "$description"
    if is_dry_run; then
        echo "DRY RUN: $cmd"
        return 0
    else
        if [[ "$ignore_error" == "true" ]]; then
            eval "$cmd" || log_warning "Command failed but continuing cleanup"
        else
            eval "$cmd"
        fi
    fi
}

# Confirmation prompt
confirm_destruction() {
    if is_force_mode || is_dry_run; then
        return 0
    fi
    
    echo ""
    log_warning "This will DELETE ALL resources created by the color palette generator!"
    log_warning "This action is IRREVERSIBLE and will remove:"
    log_warning "  - Lambda function and all its versions"
    log_warning "  - S3 bucket and ALL stored color palettes" 
    log_warning "  - IAM role and policies"
    log_warning "  - Function URL configuration"
    echo ""
    
    read -p "Are you sure you want to continue? Type 'yes' to proceed: " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

#######################################################################
# Prerequisites Check
#######################################################################

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed - some features may not work optimally"
    fi
    
    log_success "Prerequisites check completed"
}

#######################################################################
# Resource Discovery
#######################################################################

discover_resources() {
    log_info "Discovering resources to clean up..."
    
    export AWS_REGION
    AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Find Lambda functions with palette-generator prefix
    log_info "Discovering Lambda functions..."
    if command -v jq &> /dev/null; then
        LAMBDA_FUNCTIONS=($(aws lambda list-functions \
            --query 'Functions[?starts_with(FunctionName, `palette-generator-`)].FunctionName' \
            --output json | jq -r '.[]' 2>/dev/null || echo ""))
    else
        # Fallback without jq
        LAMBDA_FUNCTIONS=($(aws lambda list-functions \
            --query 'Functions[?starts_with(FunctionName, `palette-generator-`)].FunctionName' \
            --output text 2>/dev/null || echo ""))
    fi
    
    # Find S3 buckets with color-palettes prefix
    log_info "Discovering S3 buckets..."
    S3_BUCKETS=($(aws s3api list-buckets \
        --query 'Buckets[?starts_with(Name, `color-palettes-`)].Name' \
        --output text 2>/dev/null || echo ""))
    
    # Find IAM roles with palette-generator prefix
    log_info "Discovering IAM roles..."
    IAM_ROLES=($(aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `palette-generator-role-`)].RoleName' \
        --output text 2>/dev/null || echo ""))
    
    # Find IAM policies with palette-generator prefix
    log_info "Discovering IAM policies..."
    IAM_POLICIES=($(aws iam list-policies --scope Local \
        --query 'Policies[?starts_with(PolicyName, `palette-generator-role-`)].Arn' \
        --output text 2>/dev/null || echo ""))
    
    # Display discovered resources
    log_info "Resources discovered:"
    log_info "  Lambda Functions: ${#LAMBDA_FUNCTIONS[@]} (${LAMBDA_FUNCTIONS[*]})"
    log_info "  S3 Buckets: ${#S3_BUCKETS[@]} (${S3_BUCKETS[*]})"
    log_info "  IAM Roles: ${#IAM_ROLES[@]} (${IAM_ROLES[*]})"
    log_info "  IAM Policies: ${#IAM_POLICIES[@]} (${IAM_POLICIES[*]})"
    
    if [[ ${#LAMBDA_FUNCTIONS[@]} -eq 0 && ${#S3_BUCKETS[@]} -eq 0 && ${#IAM_ROLES[@]} -eq 0 ]]; then
        log_warning "No resources found to clean up"
        return 1
    fi
    
    return 0
}

#######################################################################
# Lambda Function Cleanup
#######################################################################

cleanup_lambda_functions() {
    log_info "Cleaning up Lambda functions..."
    
    for function_name in "${LAMBDA_FUNCTIONS[@]}"; do
        if [[ -z "$function_name" ]]; then
            continue
        fi
        
        log_info "Processing Lambda function: $function_name"
        
        # Delete function URL configuration (ignore errors if not exists)
        execute_cmd "aws lambda delete-function-url-config \
            --function-name $function_name" \
            "Deleting function URL for $function_name" \
            "true"
        
        # Delete Lambda function
        execute_cmd "aws lambda delete-function \
            --function-name $function_name" \
            "Deleting Lambda function $function_name" \
            "true"
        
        log_success "Lambda function $function_name cleanup completed"
    done
}

#######################################################################
# S3 Bucket Cleanup
#######################################################################

cleanup_s3_buckets() {
    log_info "Cleaning up S3 buckets..."
    
    for bucket_name in "${S3_BUCKETS[@]}"; do
        if [[ -z "$bucket_name" ]]; then
            continue
        fi
        
        log_info "Processing S3 bucket: $bucket_name"
        
        # Check if bucket exists before cleanup
        if ! is_dry_run && ! aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
            log_warning "Bucket $bucket_name not found, skipping"
            continue
        fi
        
        # Delete all objects and versions in bucket
        execute_cmd "aws s3 rm s3://$bucket_name --recursive" \
            "Deleting all objects in bucket $bucket_name" \
            "true"
        
        # Delete all object versions (if versioning enabled)
        if ! is_dry_run; then
            log_info "Deleting object versions and delete markers..."
            # Get all versions and delete markers
            aws s3api list-object-versions --bucket "$bucket_name" \
                --output json --query 'Versions[].{Key:Key,VersionId:VersionId}' | \
                jq -c '.[]?' 2>/dev/null | \
                while read -r version; do
                    if [[ -n "$version" ]]; then
                        key=$(echo "$version" | jq -r '.Key')
                        version_id=$(echo "$version" | jq -r '.VersionId')
                        aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" &>/dev/null || true
                    fi
                done
            
            # Delete delete markers
            aws s3api list-object-versions --bucket "$bucket_name" \
                --output json --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' | \
                jq -c '.[]?' 2>/dev/null | \
                while read -r marker; do
                    if [[ -n "$marker" ]]; then
                        key=$(echo "$marker" | jq -r '.Key')
                        version_id=$(echo "$marker" | jq -r '.VersionId')
                        aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" &>/dev/null || true
                    fi
                done
        fi
        
        # Delete the bucket
        execute_cmd "aws s3 rb s3://$bucket_name" \
            "Deleting S3 bucket $bucket_name" \
            "true"
        
        log_success "S3 bucket $bucket_name cleanup completed"
    done
}

#######################################################################
# IAM Resources Cleanup
#######################################################################

cleanup_iam_resources() {
    log_info "Cleaning up IAM resources..."
    
    # Clean up IAM roles
    for role_name in "${IAM_ROLES[@]}"; do
        if [[ -z "$role_name" ]]; then
            continue
        fi
        
        log_info "Processing IAM role: $role_name"
        
        # Detach all managed policies
        if ! is_dry_run; then
            aws iam list-attached-role-policies --role-name "$role_name" \
                --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null | \
                tr '\t' '\n' | \
                while read -r policy_arn; do
                    if [[ -n "$policy_arn" ]]; then
                        log_info "Detaching policy $policy_arn from role $role_name"
                        aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" || true
                    fi
                done
        else
            echo "DRY RUN: Detach all policies from role $role_name"
        fi
        
        # Delete inline policies
        if ! is_dry_run; then
            aws iam list-role-policies --role-name "$role_name" \
                --query 'PolicyNames' --output text 2>/dev/null | \
                tr '\t' '\n' | \
                while read -r policy_name; do
                    if [[ -n "$policy_name" ]]; then
                        log_info "Deleting inline policy $policy_name from role $role_name"
                        aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" || true
                    fi
                done
        else
            echo "DRY RUN: Delete all inline policies from role $role_name"
        fi
        
        # Delete the role
        execute_cmd "aws iam delete-role --role-name $role_name" \
            "Deleting IAM role $role_name" \
            "true"
        
        log_success "IAM role $role_name cleanup completed"
    done
    
    # Clean up custom IAM policies
    for policy_arn in "${IAM_POLICIES[@]}"; do
        if [[ -z "$policy_arn" ]]; then
            continue
        fi
        
        log_info "Processing IAM policy: $policy_arn"
        
        # Delete all policy versions except the default
        if ! is_dry_run; then
            aws iam list-policy-versions --policy-arn "$policy_arn" \
                --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null | \
                tr '\t' '\n' | \
                while read -r version_id; do
                    if [[ -n "$version_id" ]]; then
                        log_info "Deleting policy version $version_id"
                        aws iam delete-policy-version --policy-arn "$policy_arn" --version-id "$version_id" || true
                    fi
                done
        else
            echo "DRY RUN: Delete all non-default versions of policy $policy_arn"
        fi
        
        # Delete the policy
        execute_cmd "aws iam delete-policy --policy-arn $policy_arn" \
            "Deleting IAM policy $policy_arn" \
            "true"
        
        log_success "IAM policy $policy_arn cleanup completed"
    done
}

#######################################################################
# Cleanup Verification
#######################################################################

verify_cleanup() {
    if is_dry_run; then
        log_info "Skipping verification in dry-run mode"
        return 0
    fi
    
    log_info "Verifying cleanup completion..."
    
    # Check for remaining Lambda functions
    local remaining_functions
    remaining_functions=$(aws lambda list-functions \
        --query 'Functions[?starts_with(FunctionName, `palette-generator-`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_functions" ]]; then
        log_warning "Some Lambda functions may still exist: $remaining_functions"
    else
        log_success "All Lambda functions cleaned up"
    fi
    
    # Check for remaining S3 buckets
    local remaining_buckets
    remaining_buckets=$(aws s3api list-buckets \
        --query 'Buckets[?starts_with(Name, `color-palettes-`)].Name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_buckets" ]]; then
        log_warning "Some S3 buckets may still exist: $remaining_buckets"
    else
        log_success "All S3 buckets cleaned up"
    fi
    
    # Check for remaining IAM roles
    local remaining_roles
    remaining_roles=$(aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `palette-generator-role-`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_roles" ]]; then
        log_warning "Some IAM roles may still exist: $remaining_roles"
    else
        log_success "All IAM roles cleaned up"
    fi
}

#######################################################################
# Cleanup Summary
#######################################################################

cleanup_summary() {
    log_info "Cleanup Summary:"
    log_info "==============="
    log_info "AWS Region: $AWS_REGION"
    log_info "Lambda Functions Cleaned: ${#LAMBDA_FUNCTIONS[@]}"
    log_info "S3 Buckets Cleaned: ${#S3_BUCKETS[@]}"
    log_info "IAM Roles Cleaned: ${#IAM_ROLES[@]}"
    log_info "IAM Policies Cleaned: ${#IAM_POLICIES[@]}"
    log_info ""
    
    if is_dry_run; then
        log_info "This was a DRY RUN - no actual resources were deleted"
        log_info "Run without --dry-run to perform actual cleanup"
    else
        log_info "All color palette generator resources have been removed"
        log_info "You will no longer be charged for these resources"
    fi
}

#######################################################################
# Main Cleanup Process
#######################################################################

main() {
    log_info "Starting AWS Simple Color Palette Generator cleanup..."
    
    if is_dry_run; then
        log_info "Running in DRY RUN mode - no resources will be deleted"
    fi
    
    if is_force_mode; then
        log_info "Running in FORCE mode - skipping confirmation prompts"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Discover resources
    if ! discover_resources; then
        log_info "Cleanup completed - no resources found"
        exit 0
    fi
    
    # Confirm destruction
    confirm_destruction
    
    # Perform cleanup
    cleanup_lambda_functions
    cleanup_s3_buckets
    cleanup_iam_resources
    
    # Verify cleanup
    verify_cleanup
    
    # Show summary
    cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Handle script interruption
cleanup_script() {
    log_warning "Cleanup script interrupted"
    exit 1
}

trap cleanup_script INT TERM

# Display usage information
usage() {
    echo "Usage: $0 [--force] [--dry-run]"
    echo ""
    echo "Options:"
    echo "  --force    Skip confirmation prompts"
    echo "  --dry-run  Show what would be deleted without actually deleting"
    echo ""
    echo "Examples:"
    echo "  $0                # Interactive cleanup with confirmations"
    echo "  $0 --dry-run      # Preview what would be deleted"
    echo "  $0 --force        # Cleanup without confirmations"
    echo "  $0 --force --dry-run  # Force mode dry run"
}

# Check for help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

# Run main function
main "$@"