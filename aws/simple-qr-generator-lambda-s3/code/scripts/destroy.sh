#!/bin/bash

#================================================================
# AWS QR Code Generator Cleanup Script
# 
# This script safely removes all resources created by the
# QR code generator deployment, including:
# - API Gateway REST API
# - Lambda function
# - IAM role and policies
# - S3 bucket and all contents
# - Local temporary files
#
# Prerequisites:
# - AWS CLI installed and configured
# - Appropriate AWS permissions for resource deletion
# - State file from deployment (qr-generator-state.json)
#================================================================

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load state from file or environment
load_state() {
    log_info "Loading deployment state..."
    
    STATE_FILE="./qr-generator-state.json"
    
    # Try to load from state file first
    if [[ -f "$STATE_FILE" ]]; then
        log_info "Loading state from file: $STATE_FILE"
        
        if command -v jq &> /dev/null; then
            export BUCKET_NAME=$(jq -r '.bucket_name // empty' "$STATE_FILE")
            export FUNCTION_NAME=$(jq -r '.function_name // empty' "$STATE_FILE")
            export ROLE_NAME=$(jq -r '.role_name // empty' "$STATE_FILE")
            export API_NAME=$(jq -r '.api_name // empty' "$STATE_FILE")
            export API_ID=$(jq -r '.api_id // empty' "$STATE_FILE")
            export AWS_REGION=$(jq -r '.aws_region // empty' "$STATE_FILE")
            export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id // empty' "$STATE_FILE")
            export FUNCTION_ARN=$(jq -r '.function_arn // empty' "$STATE_FILE")
            export ROLE_ARN=$(jq -r '.role_arn // empty' "$STATE_FILE")
        else
            log_warning "jq not available. Please provide resource names manually or install jq."
            # Fallback parsing without jq (basic extraction)
            export BUCKET_NAME=$(grep -o '"bucket_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null | cut -d'"' -f4 || echo "")
            export FUNCTION_NAME=$(grep -o '"function_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null | cut -d'"' -f4 || echo "")
            export ROLE_NAME=$(grep -o '"role_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null | cut -d'"' -f4 || echo "")
            export API_NAME=$(grep -o '"api_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null | cut -d'"' -f4 || echo "")
        fi
    fi
    
    # Fallback to environment variables if state file is missing or incomplete
    export BUCKET_NAME="${BUCKET_NAME:-${QR_BUCKET_NAME:-}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-${QR_FUNCTION_NAME:-}}"
    export ROLE_NAME="${ROLE_NAME:-${QR_ROLE_NAME:-}}"
    export API_NAME="${API_NAME:-${QR_API_NAME:-}}"
    
    # Get current AWS region and account if not loaded from state
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
    fi
    
    if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    # Validate we have the minimum required information
    if [[ -z "${BUCKET_NAME:-}" ]] && [[ -z "${FUNCTION_NAME:-}" ]] && [[ -z "${ROLE_NAME:-}" ]] && [[ -z "${API_NAME:-}" ]]; then
        log_error "No resource names found in state file or environment variables."
        log_error "Please ensure you have the state file or set the following environment variables:"
        log_error "  QR_BUCKET_NAME, QR_FUNCTION_NAME, QR_ROLE_NAME, QR_API_NAME"
        exit 1
    fi
    
    log_success "State loaded successfully:"
    [[ -n "${BUCKET_NAME:-}" ]] && log_info "  Bucket Name: $BUCKET_NAME"
    [[ -n "${FUNCTION_NAME:-}" ]] && log_info "  Function Name: $FUNCTION_NAME"
    [[ -n "${ROLE_NAME:-}" ]] && log_info "  Role Name: $ROLE_NAME"
    [[ -n "${API_NAME:-}" ]] && log_info "  API Name: $API_NAME"
    [[ -n "${API_ID:-}" ]] && log_info "  API ID: $API_ID"
    log_info "  AWS Region: $AWS_REGION"
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        log_warning "FORCE_DESTROY flag set. Skipping confirmation."
        return 0
    fi
    
    echo
    log_warning "==============================================="
    log_warning "WARNING: This will permanently delete resources!"
    log_warning "==============================================="
    echo
    log_warning "The following resources will be deleted:"
    [[ -n "${API_NAME:-}" ]] && log_warning "  - API Gateway: $API_NAME"
    [[ -n "${FUNCTION_NAME:-}" ]] && log_warning "  - Lambda Function: $FUNCTION_NAME"
    [[ -n "${ROLE_NAME:-}" ]] && log_warning "  - IAM Role: $ROLE_NAME"
    [[ -n "${BUCKET_NAME:-}" ]] && log_warning "  - S3 Bucket and ALL contents: $BUCKET_NAME"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Do you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Function to delete API Gateway
delete_api_gateway() {
    if [[ -z "${API_NAME:-}" ]] && [[ -z "${API_ID:-}" ]]; then
        log_warning "No API Gateway information found. Skipping API Gateway deletion."
        return 0
    fi
    
    log_info "Deleting API Gateway..."
    
    # If we don't have API_ID, try to find it by name
    if [[ -z "${API_ID:-}" ]] && [[ -n "${API_NAME:-}" ]]; then
        API_ID=$(aws apigateway get-rest-apis \
            --query "items[?name=='$API_NAME'].id" \
            --output text 2>/dev/null | grep -v "None" | head -n1 || echo "")
    fi
    
    if [[ -n "${API_ID:-}" ]] && [[ "$API_ID" != "None" ]]; then
        aws apigateway delete-rest-api --rest-api-id "$API_ID" || {
            log_warning "Failed to delete API Gateway $API_ID. It may not exist."
        }
        log_success "API Gateway deleted: $API_ID"
    else
        log_warning "API Gateway not found or already deleted"
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        log_warning "No Lambda function name found. Skipping Lambda deletion."
        return 0
    fi
    
    log_info "Deleting Lambda function..."
    
    # Check if function exists
    if aws lambda get-function --function-name "$FUNCTION_NAME" &> /dev/null; then
        aws lambda delete-function --function-name "$FUNCTION_NAME" || {
            log_warning "Failed to delete Lambda function $FUNCTION_NAME"
        }
        log_success "Lambda function deleted: $FUNCTION_NAME"
    else
        log_warning "Lambda function $FUNCTION_NAME not found or already deleted"
    fi
}

# Function to delete IAM role and policies
delete_iam_role() {
    if [[ -z "${ROLE_NAME:-}" ]]; then
        log_warning "No IAM role name found. Skipping IAM role deletion."
        return 0
    fi
    
    log_info "Deleting IAM role and policies..."
    
    # Check if role exists
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        
        # Detach managed policies
        log_info "Detaching managed policies from role..."
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$ROLE_NAME" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$ATTACHED_POLICIES" ]]; then
            for policy_arn in $ATTACHED_POLICIES; do
                aws iam detach-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-arn "$policy_arn" || {
                    log_warning "Failed to detach policy $policy_arn"
                }
            done
        fi
        
        # Delete inline policies
        log_info "Deleting inline policies..."
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$ROLE_NAME" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$INLINE_POLICIES" ]] && [[ "$INLINE_POLICIES" != "None" ]]; then
            for policy_name in $INLINE_POLICIES; do
                aws iam delete-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-name "$policy_name" || {
                    log_warning "Failed to delete inline policy $policy_name"
                }
            done
        fi
        
        # Delete the role
        aws iam delete-role --role-name "$ROLE_NAME" || {
            log_warning "Failed to delete IAM role $ROLE_NAME"
        }
        
        log_success "IAM role deleted: $ROLE_NAME"
    else
        log_warning "IAM role $ROLE_NAME not found or already deleted"
    fi
}

# Function to delete S3 bucket and contents
delete_s3_bucket() {
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_warning "No S3 bucket name found. Skipping S3 bucket deletion."
        return 0
    fi
    
    log_info "Deleting S3 bucket and all contents..."
    
    # Check if bucket exists
    if aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        
        # Count objects for user information
        OBJECT_COUNT=$(aws s3 ls "s3://$BUCKET_NAME/" --recursive | wc -l || echo "0")
        if [[ "$OBJECT_COUNT" -gt 0 ]]; then
            log_info "Deleting $OBJECT_COUNT object(s) from bucket..."
            
            # Delete all objects and versions
            aws s3 rm "s3://$BUCKET_NAME" --recursive || {
                log_warning "Some objects may not have been deleted"
            }
            
            # Delete any versioned objects (if versioning was enabled)
            aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | while read -r key version_id; do
                if [[ -n "$key" ]] && [[ -n "$version_id" ]]; then
                    aws s3api delete-object \
                        --bucket "$BUCKET_NAME" \
                        --key "$key" \
                        --version-id "$version_id" 2>/dev/null || true
                fi
            done
            
            # Delete any delete markers
            aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | while read -r key version_id; do
                if [[ -n "$key" ]] && [[ -n "$version_id" ]]; then
                    aws s3api delete-object \
                        --bucket "$BUCKET_NAME" \
                        --key "$key" \
                        --version-id "$version_id" 2>/dev/null || true
                fi
            done
        fi
        
        # Delete the bucket
        aws s3 rb "s3://$BUCKET_NAME" --force || {
            log_warning "Failed to delete S3 bucket $BUCKET_NAME. It may contain objects or have other dependencies."
        }
        
        log_success "S3 bucket deleted: $BUCKET_NAME"
    else
        log_warning "S3 bucket $BUCKET_NAME not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove temporary files
    local files_to_remove=(
        "bucket-policy.json"
        "trust-policy.json" 
        "s3-policy.json"
        "qr-function.zip"
        "response.json"
        "./qr-generator-state.json"
    )
    
    # Remove directories
    local dirs_to_remove=(
        "qr-function"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file" && log_info "  Removed: $file"
        fi
    done
    
    for dir in "${dirs_to_remove[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir" && log_info "  Removed directory: $dir"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to verify resources are deleted
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local verification_failed=false
    
    # Check API Gateway
    if [[ -n "${API_ID:-}" ]]; then
        if aws apigateway get-rest-api --rest-api-id "$API_ID" &> /dev/null; then
            log_warning "API Gateway $API_ID still exists"
            verification_failed=true
        else
            log_success "✓ API Gateway confirmed deleted"
        fi
    fi
    
    # Check Lambda function
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "$FUNCTION_NAME" &> /dev/null; then
            log_warning "Lambda function $FUNCTION_NAME still exists"
            verification_failed=true
        else
            log_success "✓ Lambda function confirmed deleted"
        fi
    fi
    
    # Check IAM role
    if [[ -n "${ROLE_NAME:-}" ]]; then
        if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
            log_warning "IAM role $ROLE_NAME still exists"
            verification_failed=true
        else
            log_success "✓ IAM role confirmed deleted"
        fi
    fi
    
    # Check S3 bucket
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
            log_warning "S3 bucket $BUCKET_NAME still exists"
            verification_failed=true
        else
            log_success "✓ S3 bucket confirmed deleted"
        fi
    fi
    
    if [[ "$verification_failed" == "true" ]]; then
        log_warning "Some resources may still exist. Please check the AWS console."
        return 1
    else
        log_success "All resources confirmed deleted"
        return 0
    fi
}

# Function to display cleanup summary
display_summary() {
    echo
    log_success "=== QR Code Generator Cleanup Summary ==="
    echo
    log_info "Deleted Resources:"
    [[ -n "${API_NAME:-}" ]] && log_info "  ✓ API Gateway: $API_NAME"
    [[ -n "${FUNCTION_NAME:-}" ]] && log_info "  ✓ Lambda Function: $FUNCTION_NAME"
    [[ -n "${ROLE_NAME:-}" ]] && log_info "  ✓ IAM Role: $ROLE_NAME"
    [[ -n "${BUCKET_NAME:-}" ]] && log_info "  ✓ S3 Bucket: $BUCKET_NAME"
    log_info "  ✓ Local temporary files"
    echo
    log_success "Cleanup completed successfully!"
    echo
}

# Main cleanup function
main() {
    echo
    log_info "======================================="
    log_info "AWS QR Code Generator Cleanup Script"
    log_info "======================================="
    echo
    
    # Parse command line arguments
    FORCE_DESTROY=false
    DRY_RUN=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DESTROY=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift  
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --force     Skip confirmation prompt"
                echo "  --dry-run   Show what would be deleted without actually deleting"
                echo "  --help,-h   Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  QR_BUCKET_NAME      S3 bucket name to delete"
                echo "  QR_FUNCTION_NAME    Lambda function name to delete"
                echo "  QR_ROLE_NAME        IAM role name to delete"
                echo "  QR_API_NAME         API Gateway name to delete"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                log_error "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    export FORCE_DESTROY
    export DRY_RUN
    
    # Set up error handling
    trap 'log_error "Cleanup failed at line $LINENO. Some resources may not have been deleted."; exit 1' ERR
    
    # Execute cleanup steps
    check_prerequisites
    load_state
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - Showing what would be deleted:"
        [[ -n "${API_NAME:-}" ]] && log_info "  Would delete API Gateway: $API_NAME"
        [[ -n "${FUNCTION_NAME:-}" ]] && log_info "  Would delete Lambda Function: $FUNCTION_NAME"
        [[ -n "${ROLE_NAME:-}" ]] && log_info "  Would delete IAM Role: $ROLE_NAME"
        [[ -n "${BUCKET_NAME:-}" ]] && log_info "  Would delete S3 Bucket: $BUCKET_NAME"
        log_info "  Would delete local temporary files"
        exit 0
    fi
    
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_api_gateway
    delete_lambda_function
    delete_iam_role
    delete_s3_bucket
    cleanup_local_files
    
    # Verify deletion
    if verify_deletion; then
        display_summary
    else
        log_warning "Cleanup completed with warnings. Please check the AWS console for any remaining resources."
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"