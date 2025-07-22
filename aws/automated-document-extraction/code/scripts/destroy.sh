#!/bin/bash

# =============================================================================
# AWS Textract Intelligent Document Processing - Cleanup Script
# =============================================================================
# This script removes all infrastructure components created by the deployment
# script, including S3 buckets, Lambda functions, and IAM roles.
#
# Resources removed:
# - S3 bucket and all contents
# - Lambda function and associated permissions
# - IAM roles and policies
# - S3 event notifications
# =============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# =============================================================================
# Configuration and Constants
# =============================================================================

# Script metadata
SCRIPT_NAME="destroy.sh"
SCRIPT_VERSION="1.0"
CLEANUP_START_TIME=$(date +%s)

# Logging configuration
LOG_FILE="/tmp/textract-cleanup-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up AWS Textract Intelligent Document Processing infrastructure.

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be destroyed without making changes
    -r, --region REGION    AWS region (default: current configured region)
    -p, --profile PROFILE  AWS CLI profile to use
    -s, --suffix SUFFIX    Resource suffix used during deployment
    -v, --verbose          Enable verbose logging
    --skip-confirmation    Skip confirmation prompts (dangerous!)
    --force                Force cleanup even if errors occur
    --preserve-logs        Keep CloudWatch logs after cleanup

EXAMPLES:
    $0                     # Interactive cleanup with confirmations
    $0 --dry-run           # Show what would be destroyed
    $0 --skip-confirmation # Non-interactive cleanup
    $0 -s abc123           # Cleanup resources with specific suffix

EOF
}

confirm_action() {
    local message="$1"
    if [ "$SKIP_CONFIRMATION" = "true" ]; then
        return 0
    fi
    
    echo -e "${YELLOW}[CONFIRM]${NC} $message"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
}

cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Cleanup failed with exit code: $exit_code"
        log_info "Log file: $LOG_FILE"
        log_info "Some resources may still exist. Review the log and run the script again."
    fi
}

# =============================================================================
# Resource Discovery
# =============================================================================

discover_resources() {
    log_info "Discovering Textract resources..."
    
    # Arrays to store discovered resources
    declare -g DISCOVERED_BUCKETS=()
    declare -g DISCOVERED_FUNCTIONS=()
    declare -g DISCOVERED_ROLES=()
    declare -g DISCOVERED_POLICIES=()
    
    # Discover S3 buckets
    log_info "Discovering S3 buckets..."
    while IFS= read -r bucket; do
        if [[ $bucket =~ ^textract-documents- ]]; then
            DISCOVERED_BUCKETS+=("$bucket")
            log_info "Found S3 bucket: $bucket"
        fi
    done < <(aws s3api list-buckets --query 'Buckets[].Name' --output text 2>/dev/null || echo "")
    
    # Discover Lambda functions
    log_info "Discovering Lambda functions..."
    while IFS= read -r function; do
        if [[ $function =~ ^textract-processor- ]]; then
            DISCOVERED_FUNCTIONS+=("$function")
            log_info "Found Lambda function: $function"
        fi
    done < <(aws lambda list-functions --query 'Functions[].FunctionName' --output text 2>/dev/null || echo "")
    
    # Discover IAM roles
    log_info "Discovering IAM roles..."
    while IFS= read -r role; do
        if [[ $role =~ ^TextractProcessorRole- ]]; then
            DISCOVERED_ROLES+=("$role")
            log_info "Found IAM role: $role"
        fi
    done < <(aws iam list-roles --query 'Roles[].RoleName' --output text 2>/dev/null || echo "")
    
    # Discover IAM policies
    log_info "Discovering IAM policies..."
    while IFS= read -r policy; do
        if [[ $policy =~ ^TextractProcessorPolicy- ]]; then
            DISCOVERED_POLICIES+=("$policy")
            log_info "Found IAM policy: $policy"
        fi
    done < <(aws iam list-policies --scope Local --query 'Policies[].PolicyName' --output text 2>/dev/null || echo "")
    
    # If suffix is provided, filter resources
    if [ -n "$RESOURCE_SUFFIX" ]; then
        log_info "Filtering resources by suffix: $RESOURCE_SUFFIX"
        
        # Set specific resource names
        BUCKET_NAME="textract-documents-${RESOURCE_SUFFIX}"
        LAMBDA_FUNCTION_NAME="textract-processor-${RESOURCE_SUFFIX}"
        ROLE_NAME="TextractProcessorRole-${RESOURCE_SUFFIX}"
        POLICY_NAME="TextractProcessorPolicy-${RESOURCE_SUFFIX}"
        
        # Filter discovered resources
        DISCOVERED_BUCKETS=("$BUCKET_NAME")
        DISCOVERED_FUNCTIONS=("$LAMBDA_FUNCTION_NAME")
        DISCOVERED_ROLES=("$ROLE_NAME")
        DISCOVERED_POLICIES=("$POLICY_NAME")
    fi
    
    # Summary
    log_info "Discovery complete:"
    log_info "  S3 Buckets: ${#DISCOVERED_BUCKETS[@]}"
    log_info "  Lambda Functions: ${#DISCOVERED_FUNCTIONS[@]}"
    log_info "  IAM Roles: ${#DISCOVERED_ROLES[@]}"
    log_info "  IAM Policies: ${#DISCOVERED_POLICIES[@]}"
}

# =============================================================================
# Cleanup Functions
# =============================================================================

cleanup_s3_buckets() {
    log_info "Cleaning up S3 buckets..."
    
    for bucket in "${DISCOVERED_BUCKETS[@]}"; do
        if [ -z "$bucket" ]; then
            continue
        fi
        
        log_info "Processing bucket: $bucket"
        
        # Check if bucket exists
        if ! aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
            log_warning "Bucket $bucket does not exist or is not accessible"
            continue
        fi
        
        # Remove all objects and versions
        log_info "Removing all objects from bucket: $bucket"
        
        # Remove all object versions
        aws s3api list-object-versions --bucket "$bucket" --output json | \
        jq -r '.Versions[]? | "\(.Key) \(.VersionId)"' | \
        while read -r key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" &>/dev/null || true
            fi
        done
        
        # Remove all delete markers
        aws s3api list-object-versions --bucket "$bucket" --output json | \
        jq -r '.DeleteMarkers[]? | "\(.Key) \(.VersionId)"' | \
        while read -r key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" &>/dev/null || true
            fi
        done
        
        # Remove any remaining objects (for non-versioned buckets)
        aws s3 rm "s3://$bucket" --recursive &>/dev/null || true
        
        # Remove bucket notification configuration
        aws s3api put-bucket-notification-configuration \
            --bucket "$bucket" \
            --notification-configuration '{}' &>/dev/null || true
        
        # Delete the bucket
        if aws s3api delete-bucket --bucket "$bucket" &>/dev/null; then
            log_success "Deleted S3 bucket: $bucket"
        else
            log_error "Failed to delete S3 bucket: $bucket"
            if [ "$FORCE_CLEANUP" != "true" ]; then
                continue
            fi
        fi
    done
}

cleanup_lambda_functions() {
    log_info "Cleaning up Lambda functions..."
    
    for function in "${DISCOVERED_FUNCTIONS[@]}"; do
        if [ -z "$function" ]; then
            continue
        fi
        
        log_info "Processing Lambda function: $function"
        
        # Check if function exists
        if ! aws lambda get-function --function-name "$function" &>/dev/null; then
            log_warning "Lambda function $function does not exist"
            continue
        fi
        
        # Remove event source mappings
        aws lambda list-event-source-mappings --function-name "$function" --query 'EventSourceMappings[].UUID' --output text | \
        while read -r uuid; do
            if [ -n "$uuid" ] && [ "$uuid" != "None" ]; then
                aws lambda delete-event-source-mapping --uuid "$uuid" &>/dev/null || true
                log_info "Removed event source mapping: $uuid"
            fi
        done
        
        # Remove function permissions
        aws lambda get-policy --function-name "$function" --query 'Policy' --output text 2>/dev/null | \
        jq -r '.Statement[]?.Sid' 2>/dev/null | \
        while read -r sid; do
            if [ -n "$sid" ] && [ "$sid" != "null" ]; then
                aws lambda remove-permission --function-name "$function" --statement-id "$sid" &>/dev/null || true
                log_info "Removed permission: $sid"
            fi
        done
        
        # Delete the function
        if aws lambda delete-function --function-name "$function" &>/dev/null; then
            log_success "Deleted Lambda function: $function"
        else
            log_error "Failed to delete Lambda function: $function"
            if [ "$FORCE_CLEANUP" != "true" ]; then
                continue
            fi
        fi
    done
}

cleanup_iam_resources() {
    log_info "Cleaning up IAM resources..."
    
    # Clean up IAM roles
    for role in "${DISCOVERED_ROLES[@]}"; do
        if [ -z "$role" ]; then
            continue
        fi
        
        log_info "Processing IAM role: $role"
        
        # Check if role exists
        if ! aws iam get-role --role-name "$role" &>/dev/null; then
            log_warning "IAM role $role does not exist"
            continue
        fi
        
        # Detach all policies
        aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text | \
        while read -r policy_arn; do
            if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
                aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" &>/dev/null || true
                log_info "Detached policy: $policy_arn"
            fi
        done
        
        # Remove inline policies
        aws iam list-role-policies --role-name "$role" --query 'PolicyNames' --output text | \
        while read -r policy_name; do
            if [ -n "$policy_name" ] && [ "$policy_name" != "None" ]; then
                aws iam delete-role-policy --role-name "$role" --policy-name "$policy_name" &>/dev/null || true
                log_info "Deleted inline policy: $policy_name"
            fi
        done
        
        # Delete the role
        if aws iam delete-role --role-name "$role" &>/dev/null; then
            log_success "Deleted IAM role: $role"
        else
            log_error "Failed to delete IAM role: $role"
            if [ "$FORCE_CLEANUP" != "true" ]; then
                continue
            fi
        fi
    done
    
    # Clean up IAM policies
    for policy in "${DISCOVERED_POLICIES[@]}"; do
        if [ -z "$policy" ]; then
            continue
        fi
        
        log_info "Processing IAM policy: $policy"
        
        # Get policy ARN
        local policy_arn=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='$policy'].Arn" --output text 2>/dev/null)
        
        if [ -z "$policy_arn" ] || [ "$policy_arn" = "None" ]; then
            log_warning "IAM policy $policy does not exist"
            continue
        fi
        
        # Delete all non-default versions
        aws iam list-policy-versions --policy-arn "$policy_arn" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text | \
        while read -r version_id; do
            if [ -n "$version_id" ] && [ "$version_id" != "None" ]; then
                aws iam delete-policy-version --policy-arn "$policy_arn" --version-id "$version_id" &>/dev/null || true
                log_info "Deleted policy version: $version_id"
            fi
        done
        
        # Delete the policy
        if aws iam delete-policy --policy-arn "$policy_arn" &>/dev/null; then
            log_success "Deleted IAM policy: $policy"
        else
            log_error "Failed to delete IAM policy: $policy"
            if [ "$FORCE_CLEANUP" != "true" ]; then
                continue
            fi
        fi
    done
}

cleanup_cloudwatch_logs() {
    if [ "$PRESERVE_LOGS" = "true" ]; then
        log_info "Preserving CloudWatch logs as requested"
        return 0
    fi
    
    log_info "Cleaning up CloudWatch logs..."
    
    for function in "${DISCOVERED_FUNCTIONS[@]}"; do
        if [ -z "$function" ]; then
            continue
        fi
        
        local log_group="/aws/lambda/$function"
        
        # Check if log group exists
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[].logGroupName' --output text | grep -q "$log_group"; then
            if aws logs delete-log-group --log-group-name "$log_group" &>/dev/null; then
                log_success "Deleted CloudWatch log group: $log_group"
            else
                log_warning "Failed to delete CloudWatch log group: $log_group"
            fi
        fi
    done
}

# =============================================================================
# Validation and Reporting
# =============================================================================

validate_cleanup() {
    log_info "Validating cleanup..."
    
    local cleanup_errors=0
    
    # Check S3 buckets
    for bucket in "${DISCOVERED_BUCKETS[@]}"; do
        if [ -z "$bucket" ]; then
            continue
        fi
        
        if aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
            log_warning "S3 bucket still exists: $bucket"
            ((cleanup_errors++))
        fi
    done
    
    # Check Lambda functions
    for function in "${DISCOVERED_FUNCTIONS[@]}"; do
        if [ -z "$function" ]; then
            continue
        fi
        
        if aws lambda get-function --function-name "$function" &>/dev/null; then
            log_warning "Lambda function still exists: $function"
            ((cleanup_errors++))
        fi
    done
    
    # Check IAM roles
    for role in "${DISCOVERED_ROLES[@]}"; do
        if [ -z "$role" ]; then
            continue
        fi
        
        if aws iam get-role --role-name "$role" &>/dev/null; then
            log_warning "IAM role still exists: $role"
            ((cleanup_errors++))
        fi
    done
    
    # Check IAM policies
    for policy in "${DISCOVERED_POLICIES[@]}"; do
        if [ -z "$policy" ]; then
            continue
        fi
        
        if aws iam list-policies --scope Local --query "Policies[?PolicyName=='$policy'].PolicyName" --output text | grep -q "$policy"; then
            log_warning "IAM policy still exists: $policy"
            ((cleanup_errors++))
        fi
    done
    
    if [ $cleanup_errors -eq 0 ]; then
        log_success "Cleanup validation passed - all resources removed"
    else
        log_warning "Cleanup validation found $cleanup_errors remaining resources"
    fi
    
    return $cleanup_errors
}

# =============================================================================
# Main Cleanup Logic
# =============================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -p|--profile)
                AWS_PROFILE="$2"
                export AWS_PROFILE
                shift 2
                ;;
            -s|--suffix)
                RESOURCE_SUFFIX="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --force)
                FORCE_CLEANUP=true
                shift
                ;;
            --preserve-logs)
                PRESERVE_LOGS=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Setup exit handler
    trap cleanup_on_exit EXIT
    
    # Script header
    echo "================================================================"
    echo "AWS Textract Document Processing Cleanup Script"
    echo "Version: $SCRIPT_VERSION"
    echo "Started: $(date)"
    echo "================================================================"
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Discover resources
    discover_resources
    
    # Check if any resources were found
    local total_resources=$((${#DISCOVERED_BUCKETS[@]} + ${#DISCOVERED_FUNCTIONS[@]} + ${#DISCOVERED_ROLES[@]} + ${#DISCOVERED_POLICIES[@]}))
    
    if [ $total_resources -eq 0 ]; then
        log_info "No Textract resources found to clean up"
        exit 0
    fi
    
    # Display what will be destroyed
    echo ""
    echo "The following resources will be PERMANENTLY DELETED:"
    echo ""
    
    if [ ${#DISCOVERED_BUCKETS[@]} -gt 0 ]; then
        echo "S3 Buckets:"
        for bucket in "${DISCOVERED_BUCKETS[@]}"; do
            [ -n "$bucket" ] && echo "  - $bucket (including all contents)"
        done
    fi
    
    if [ ${#DISCOVERED_FUNCTIONS[@]} -gt 0 ]; then
        echo "Lambda Functions:"
        for function in "${DISCOVERED_FUNCTIONS[@]}"; do
            [ -n "$function" ] && echo "  - $function"
        done
    fi
    
    if [ ${#DISCOVERED_ROLES[@]} -gt 0 ]; then
        echo "IAM Roles:"
        for role in "${DISCOVERED_ROLES[@]}"; do
            [ -n "$role" ] && echo "  - $role"
        done
    fi
    
    if [ ${#DISCOVERED_POLICIES[@]} -gt 0 ]; then
        echo "IAM Policies:"
        for policy in "${DISCOVERED_POLICIES[@]}"; do
            [ -n "$policy" ] && echo "  - $policy"
        done
    fi
    
    echo ""
    
    # Dry run mode
    if [ "$DRY_RUN" = "true" ]; then
        log_info "DRY RUN MODE - No resources will be destroyed"
        exit 0
    fi
    
    # Confirmation
    confirm_action "This action cannot be undone. All data will be permanently lost."
    
    # Perform cleanup
    cleanup_s3_buckets
    cleanup_lambda_functions
    cleanup_iam_resources
    cleanup_cloudwatch_logs
    
    # Validate cleanup
    if ! validate_cleanup; then
        if [ "$FORCE_CLEANUP" = "true" ]; then
            log_warning "Cleanup completed with warnings (--force mode)"
        else
            log_error "Cleanup completed with errors"
            exit 1
        fi
    fi
    
    # Display cleanup summary
    echo "================================================================"
    echo "CLEANUP COMPLETED SUCCESSFULLY"
    echo "================================================================"
    echo "Resources removed:"
    echo "  - S3 Buckets: ${#DISCOVERED_BUCKETS[@]}"
    echo "  - Lambda Functions: ${#DISCOVERED_FUNCTIONS[@]}"
    echo "  - IAM Roles: ${#DISCOVERED_ROLES[@]}"
    echo "  - IAM Policies: ${#DISCOVERED_POLICIES[@]}"
    echo ""
    echo "Log file: $LOG_FILE"
    echo "Cleanup time: $(($(date +%s) - CLEANUP_START_TIME)) seconds"
    echo "================================================================"
}

# Run main function
main "$@"