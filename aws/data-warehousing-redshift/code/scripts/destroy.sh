#!/bin/bash

# AWS Redshift Data Warehousing Solution - Cleanup Script
# This script safely removes all resources created by the deployment script
# including Redshift Serverless resources, IAM roles, and S3 buckets

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS credentials
validate_aws_credentials() {
    log "Validating AWS credentials..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid"
        log "Please run 'aws configure' or set AWS environment variables"
        exit 1
    fi
    log_success "AWS credentials validated"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Check if environment file exists
    if [[ -f ".redshift-env" ]]; then
        log "Loading environment from .redshift-env file..."
        source .redshift-env
        log_success "Environment variables loaded from file"
    else
        log_warn "Environment file .redshift-env not found"
        log "Please provide resource names manually or ensure deployment was successful"
        
        # Try to detect resources if possible
        read -p "Enter Namespace name: " NAMESPACE_NAME
        read -p "Enter Workgroup name: " WORKGROUP_NAME
        read -p "Enter S3 bucket name: " S3_BUCKET_NAME
        read -p "Enter IAM role name: " IAM_ROLE_NAME
        
        export NAMESPACE_NAME
        export WORKGROUP_NAME
        export S3_BUCKET_NAME
        export IAM_ROLE_NAME
        
        # Set other required variables
        export AWS_REGION=$(aws configure get region)
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        export IAM_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}"
    fi
    
    log "Current environment:"
    log "  AWS_REGION: ${AWS_REGION:-not set}"
    log "  NAMESPACE_NAME: ${NAMESPACE_NAME:-not set}"
    log "  WORKGROUP_NAME: ${WORKGROUP_NAME:-not set}"
    log "  S3_BUCKET_NAME: ${S3_BUCKET_NAME:-not set}"
    log "  IAM_ROLE_NAME: ${IAM_ROLE_NAME:-not set}"
}

# Function to confirm deletion
confirm_deletion() {
    echo
    log_warn "You are about to delete the following resources:"
    log "  - Redshift Serverless Workgroup: ${WORKGROUP_NAME:-not set}"
    log "  - Redshift Serverless Namespace: ${NAMESPACE_NAME:-not set}"
    log "  - S3 Bucket and all contents: ${S3_BUCKET_NAME:-not set}"
    log "  - IAM Role: ${IAM_ROLE_NAME:-not set}"
    echo
    log_warn "This action is IRREVERSIBLE and will DELETE ALL DATA!"
    echo
    
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        log_warn "Force delete mode enabled - skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource deletion..."
}

# Function to delete Redshift Serverless workgroup
delete_workgroup() {
    if [[ -z "${WORKGROUP_NAME:-}" ]]; then
        log_warn "Workgroup name not provided, skipping workgroup deletion"
        return 0
    fi
    
    log "Deleting Redshift Serverless workgroup: ${WORKGROUP_NAME}"
    
    # Check if workgroup exists
    if ! aws redshift-serverless get-workgroup --workgroup-name "$WORKGROUP_NAME" >/dev/null 2>&1; then
        log_warn "Workgroup ${WORKGROUP_NAME} does not exist or already deleted"
        return 0
    fi
    
    # Delete workgroup
    if aws redshift-serverless delete-workgroup --workgroup-name "$WORKGROUP_NAME" >/dev/null 2>&1; then
        log_success "Workgroup deletion initiated: ${WORKGROUP_NAME}"
        
        # Wait for workgroup to be deleted
        log "Waiting for workgroup to be deleted..."
        local timeout=300  # 5 minutes
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            if ! aws redshift-serverless get-workgroup --workgroup-name "$WORKGROUP_NAME" >/dev/null 2>&1; then
                log_success "Workgroup deleted successfully"
                return 0
            fi
            sleep 10
            elapsed=$((elapsed + 10))
            log "Waiting for deletion... (${elapsed}s/${timeout}s)"
        done
        
        log_warn "Timeout waiting for workgroup deletion, but deletion was initiated"
    else
        log_error "Failed to delete workgroup: ${WORKGROUP_NAME}"
    fi
}

# Function to delete Redshift Serverless namespace
delete_namespace() {
    if [[ -z "${NAMESPACE_NAME:-}" ]]; then
        log_warn "Namespace name not provided, skipping namespace deletion"
        return 0
    fi
    
    log "Deleting Redshift Serverless namespace: ${NAMESPACE_NAME}"
    
    # Check if namespace exists
    if ! aws redshift-serverless get-namespace --namespace-name "$NAMESPACE_NAME" >/dev/null 2>&1; then
        log_warn "Namespace ${NAMESPACE_NAME} does not exist or already deleted"
        return 0
    fi
    
    # Delete namespace
    if aws redshift-serverless delete-namespace --namespace-name "$NAMESPACE_NAME" >/dev/null 2>&1; then
        log_success "Namespace deletion initiated: ${NAMESPACE_NAME}"
        
        # Wait for namespace to be deleted
        log "Waiting for namespace to be deleted..."
        local timeout=300  # 5 minutes
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            if ! aws redshift-serverless get-namespace --namespace-name "$NAMESPACE_NAME" >/dev/null 2>&1; then
                log_success "Namespace deleted successfully"
                return 0
            fi
            sleep 10
            elapsed=$((elapsed + 10))
            log "Waiting for deletion... (${elapsed}s/${timeout}s)"
        done
        
        log_warn "Timeout waiting for namespace deletion, but deletion was initiated"
    else
        log_error "Failed to delete namespace: ${NAMESPACE_NAME}"
    fi
}

# Function to delete IAM role
delete_iam_role() {
    if [[ -z "${IAM_ROLE_NAME:-}" ]]; then
        log_warn "IAM role name not provided, skipping IAM role deletion"
        return 0
    fi
    
    log "Deleting IAM role: ${IAM_ROLE_NAME}"
    
    # Check if role exists
    if ! aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
        log_warn "IAM role ${IAM_ROLE_NAME} does not exist or already deleted"
        return 0
    fi
    
    # Detach all managed policies
    log "Detaching policies from IAM role..."
    local policies=$(aws iam list-attached-role-policies --role-name "$IAM_ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    
    if [[ -n "$policies" ]]; then
        for policy in $policies; do
            log "Detaching policy: $policy"
            aws iam detach-role-policy --role-name "$IAM_ROLE_NAME" --policy-arn "$policy" >/dev/null 2>&1 || true
        done
    fi
    
    # Delete inline policies if any
    local inline_policies=$(aws iam list-role-policies --role-name "$IAM_ROLE_NAME" --query 'PolicyNames' --output text 2>/dev/null || echo "")
    
    if [[ -n "$inline_policies" && "$inline_policies" != "None" ]]; then
        for policy in $inline_policies; do
            log "Deleting inline policy: $policy"
            aws iam delete-role-policy --role-name "$IAM_ROLE_NAME" --policy-name "$policy" >/dev/null 2>&1 || true
        done
    fi
    
    # Delete the role
    if aws iam delete-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
        log_success "IAM role deleted: ${IAM_ROLE_NAME}"
    else
        log_error "Failed to delete IAM role: ${IAM_ROLE_NAME}"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    if [[ -z "${S3_BUCKET_NAME:-}" ]]; then
        log_warn "S3 bucket name not provided, skipping S3 bucket deletion"
        return 0
    fi
    
    log "Deleting S3 bucket and all contents: ${S3_BUCKET_NAME}"
    
    # Check if bucket exists
    if ! aws s3 ls "s3://${S3_BUCKET_NAME}" >/dev/null 2>&1; then
        log_warn "S3 bucket ${S3_BUCKET_NAME} does not exist or already deleted"
        return 0
    fi
    
    # Delete all objects in bucket (including versions if versioning is enabled)
    log "Deleting all objects from S3 bucket..."
    aws s3api delete-objects \
        --bucket "$S3_BUCKET_NAME" \
        --delete "$(aws s3api list-object-versions \
            --bucket "$S3_BUCKET_NAME" \
            --output json \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" \
        >/dev/null 2>&1 || true
    
    # Delete all delete markers if versioning was enabled
    aws s3api delete-objects \
        --bucket "$S3_BUCKET_NAME" \
        --delete "$(aws s3api list-object-versions \
            --bucket "$S3_BUCKET_NAME" \
            --output json \
            --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" \
        >/dev/null 2>&1 || true
    
    # Force delete remaining objects
    aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive >/dev/null 2>&1 || true
    
    # Delete the bucket
    if aws s3 rb "s3://${S3_BUCKET_NAME}" --force >/dev/null 2>&1; then
        log_success "S3 bucket deleted: ${S3_BUCKET_NAME}"
    else
        log_error "Failed to delete S3 bucket: ${S3_BUCKET_NAME}"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        ".redshift-env"
        "create_tables.sql"
        "load_data.sql"
        "analytical_queries.sql"
        "redshift-trust-policy.json"
        "sales_data.csv"
        "customer_data.csv"
        "product_data.csv"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check workgroup
    if [[ -n "${WORKGROUP_NAME:-}" ]] && aws redshift-serverless get-workgroup --workgroup-name "$WORKGROUP_NAME" >/dev/null 2>&1; then
        log_warn "Workgroup still exists: ${WORKGROUP_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check namespace
    if [[ -n "${NAMESPACE_NAME:-}" ]] && aws redshift-serverless get-namespace --namespace-name "$NAMESPACE_NAME" >/dev/null 2>&1; then
        log_warn "Namespace still exists: ${NAMESPACE_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check IAM role
    if [[ -n "${IAM_ROLE_NAME:-}" ]] && aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
        log_warn "IAM role still exists: ${IAM_ROLE_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check S3 bucket
    if [[ -n "${S3_BUCKET_NAME:-}" ]] && aws s3 ls "s3://${S3_BUCKET_NAME}" >/dev/null 2>&1; then
        log_warn "S3 bucket still exists: ${S3_BUCKET_NAME}"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "All resources have been successfully cleaned up"
    else
        log_warn "Some resources may still exist. Please check manually in the AWS console"
        log "This might be due to deletion delays or permissions issues"
    fi
}

# Function to list resources for manual cleanup
list_remaining_resources() {
    log "Listing any remaining resources for manual cleanup..."
    echo
    
    # List Redshift Serverless resources
    log "Redshift Serverless Namespaces:"
    aws redshift-serverless list-namespaces --query 'namespaces[].namespaceName' --output table 2>/dev/null || log "Unable to list namespaces"
    
    log "Redshift Serverless Workgroups:"
    aws redshift-serverless list-workgroups --query 'workgroups[].workgroupName' --output table 2>/dev/null || log "Unable to list workgroups"
    
    # List S3 buckets with our prefix pattern
    log "S3 Buckets (with 'redshift-data' prefix):"
    aws s3 ls | grep "redshift-data" || log "No S3 buckets found with redshift-data prefix"
    
    # List IAM roles with our prefix pattern
    log "IAM Roles (with 'RedshiftServerlessRole' prefix):"
    aws iam list-roles --query 'Roles[?starts_with(RoleName, `RedshiftServerlessRole`)].RoleName' --output table 2>/dev/null || log "Unable to list IAM roles"
}

# Main cleanup function
main() {
    log "Starting AWS Redshift Data Warehousing Solution cleanup..."
    echo
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_DELETE=true
                log_warn "Force delete mode enabled"
                shift
                ;;
            --list-only)
                export LIST_ONLY=true
                log "List only mode enabled"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--force] [--list-only] [--help]"
                echo "  --force      Skip confirmation prompts"
                echo "  --list-only  Only list resources, don't delete"
                echo "  --help       Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Check prerequisites
    if ! command_exists aws; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    validate_aws_credentials
    load_environment
    
    # If list-only mode, just show resources and exit
    if [[ "${LIST_ONLY:-false}" == "true" ]]; then
        list_remaining_resources
        exit 0
    fi
    
    confirm_deletion
    
    # Execute cleanup steps in reverse order of creation
    delete_workgroup
    delete_namespace
    delete_iam_role
    delete_s3_bucket
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    echo
    log_success "Cleanup completed!"
    log "If any resources remain, they may take additional time to be fully deleted"
    log "You can run this script with --list-only to check for remaining resources"
}

# Error handling
trap 'log_error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"