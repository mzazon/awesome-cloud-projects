#!/bin/bash

# Destroy script for Analytics-Ready Data Storage with S3 Tables
# This script safely removes all resources created by the deploy script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to load environment variables
load_environment() {
    if [ -f ".env" ]; then
        log "Loading environment variables from .env file..."
        source .env
        success "Environment variables loaded"
    else
        error "Environment file .env not found. Please ensure deploy.sh was run successfully."
        echo "You can manually set the following variables and re-run this script:"
        echo "export AWS_REGION=<your-region>"
        echo "export TABLE_BUCKET_NAME=<your-table-bucket-name>"
        echo "export NAMESPACE_NAME=<your-namespace>"
        echo "export SAMPLE_TABLE_NAME=<your-table-name>"
        echo "export ATHENA_RESULTS_BUCKET=<your-athena-bucket>"
        exit 1
    fi
}

# Function to confirm destructive actions
confirm_destruction() {
    echo ""
    warning "This script will destroy the following resources:"
    echo "  - S3 Table Bucket: ${TABLE_BUCKET_NAME}"
    echo "  - Namespace: ${NAMESPACE_NAME}"
    echo "  - Sample Table: ${SAMPLE_TABLE_NAME}"
    echo "  - Athena Results Bucket: ${ATHENA_RESULTS_BUCKET}"
    echo "  - Athena Workgroup: ${ATHENA_WORKGROUP:-s3-tables-workgroup}"
    echo "  - SQL files: customer_events_ddl.sql, insert_sample_data.sql"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    warning "Starting resource destruction in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure'"
        exit 1
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to delete Athena workgroup
delete_athena_workgroup() {
    log "Deleting Athena workgroup..."
    
    local WORKGROUP_NAME="${ATHENA_WORKGROUP:-s3-tables-workgroup}"
    
    # Check if workgroup exists
    if ! aws athena get-work-group --work-group "${WORKGROUP_NAME}" &> /dev/null; then
        warning "Athena workgroup ${WORKGROUP_NAME} does not exist or already deleted"
        return 0
    fi
    
    # Delete the workgroup with recursive delete to remove all query executions
    aws athena delete-work-group \
        --work-group "${WORKGROUP_NAME}" \
        --recursive-delete-option
    
    success "Athena workgroup deleted"
}

# Function to delete sample table
delete_sample_table() {
    log "Deleting sample table..."
    
    # Check if we have the table bucket ARN
    if [ -z "${TABLE_BUCKET_ARN:-}" ]; then
        # Try to get the ARN from the bucket name
        if aws s3tables get-table-bucket --name "${TABLE_BUCKET_NAME}" &> /dev/null; then
            export TABLE_BUCKET_ARN=$(aws s3tables get-table-bucket \
                --name "${TABLE_BUCKET_NAME}" \
                --query 'arn' --output text)
        else
            warning "Table bucket ${TABLE_BUCKET_NAME} does not exist or already deleted"
            return 0
        fi
    fi
    
    # Check if table exists
    if ! aws s3tables get-table \
        --table-bucket-arn "${TABLE_BUCKET_ARN}" \
        --namespace "${NAMESPACE_NAME}" \
        --name "${SAMPLE_TABLE_NAME}" &> /dev/null; then
        warning "Table ${SAMPLE_TABLE_NAME} does not exist or already deleted"
        return 0
    fi
    
    # Delete the table
    aws s3tables delete-table \
        --table-bucket-arn "${TABLE_BUCKET_ARN}" \
        --namespace "${NAMESPACE_NAME}" \
        --name "${SAMPLE_TABLE_NAME}"
    
    success "Sample table deleted"
}

# Function to delete namespace
delete_namespace() {
    log "Deleting namespace..."
    
    # Check if namespace exists
    if ! aws s3tables list-namespaces \
        --table-bucket-arn "${TABLE_BUCKET_ARN}" \
        --query "namespaces[?namespace=='${NAMESPACE_NAME}']" \
        --output text | grep -q "${NAMESPACE_NAME}"; then
        warning "Namespace ${NAMESPACE_NAME} does not exist or already deleted"
        return 0
    fi
    
    # Delete the namespace
    aws s3tables delete-namespace \
        --table-bucket-arn "${TABLE_BUCKET_ARN}" \
        --namespace "${NAMESPACE_NAME}"
    
    success "Namespace deleted"
}

# Function to delete table bucket
delete_table_bucket() {
    log "Deleting S3 Table bucket..."
    
    # Check if table bucket exists
    if ! aws s3tables get-table-bucket --name "${TABLE_BUCKET_NAME}" &> /dev/null; then
        warning "Table bucket ${TABLE_BUCKET_NAME} does not exist or already deleted"
        return 0
    fi
    
    # Delete the table bucket
    aws s3tables delete-table-bucket \
        --name "${TABLE_BUCKET_NAME}"
    
    success "Table bucket deleted"
}

# Function to delete Athena results bucket
delete_athena_results_bucket() {
    log "Deleting Athena results bucket..."
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "${ATHENA_RESULTS_BUCKET}" &> /dev/null; then
        warning "Athena results bucket ${ATHENA_RESULTS_BUCKET} does not exist or already deleted"
        return 0
    fi
    
    # Delete all objects in the bucket first
    log "Removing all objects from Athena results bucket..."
    aws s3 rm "s3://${ATHENA_RESULTS_BUCKET}" --recursive --quiet
    
    # Delete the bucket
    aws s3 rb "s3://${ATHENA_RESULTS_BUCKET}"
    
    success "Athena results bucket deleted"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local FILES_TO_DELETE=(
        "customer_events_ddl.sql"
        "insert_sample_data.sql"
        ".env"
    )
    
    for file in "${FILES_TO_DELETE[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            success "Deleted local file: $file"
        else
            warning "Local file not found: $file"
        fi
    done
    
    success "Local files cleanup completed"
}

# Function to verify resource deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local VERIFICATION_FAILED=false
    
    # Check table bucket
    if aws s3tables get-table-bucket --name "${TABLE_BUCKET_NAME}" &> /dev/null; then
        error "Table bucket ${TABLE_BUCKET_NAME} still exists"
        VERIFICATION_FAILED=true
    else
        success "Table bucket deletion verified"
    fi
    
    # Check Athena results bucket
    if aws s3api head-bucket --bucket "${ATHENA_RESULTS_BUCKET}" &> /dev/null; then
        error "Athena results bucket ${ATHENA_RESULTS_BUCKET} still exists"
        VERIFICATION_FAILED=true
    else
        success "Athena results bucket deletion verified"
    fi
    
    # Check Athena workgroup
    local WORKGROUP_NAME="${ATHENA_WORKGROUP:-s3-tables-workgroup}"
    if aws athena get-work-group --work-group "${WORKGROUP_NAME}" &> /dev/null; then
        error "Athena workgroup ${WORKGROUP_NAME} still exists"
        VERIFICATION_FAILED=true
    else
        success "Athena workgroup deletion verified"
    fi
    
    if [ "$VERIFICATION_FAILED" = true ]; then
        error "Some resources were not deleted successfully. Please check manually."
        exit 1
    else
        success "All resources deleted successfully"
    fi
}

# Function to handle cleanup errors gracefully
handle_cleanup_error() {
    local FUNCTION_NAME="$1"
    local ERROR_MESSAGE="$2"
    
    error "Error in ${FUNCTION_NAME}: ${ERROR_MESSAGE}"
    warning "Continuing with remaining cleanup operations..."
    
    # Add to failed operations list for summary
    if [ -z "${FAILED_OPERATIONS:-}" ]; then
        FAILED_OPERATIONS="$FUNCTION_NAME"
    else
        FAILED_OPERATIONS="$FAILED_OPERATIONS, $FUNCTION_NAME"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary:"
    echo "================"
    
    if [ -n "${FAILED_OPERATIONS:-}" ]; then
        warning "Some operations failed: ${FAILED_OPERATIONS}"
        echo "Please manually verify and clean up any remaining resources:"
        echo "  - Table bucket: ${TABLE_BUCKET_NAME}"
        echo "  - Athena results bucket: ${ATHENA_RESULTS_BUCKET}"
        echo "  - Athena workgroup: ${ATHENA_WORKGROUP:-s3-tables-workgroup}"
    else
        success "All S3 Tables analytics infrastructure has been destroyed!"
    fi
    
    echo ""
    log "Resources that were deleted:"
    echo "  ✓ S3 Table bucket and all tables"
    echo "  ✓ Namespace and table metadata"
    echo "  ✓ Athena workgroup and queries"
    echo "  ✓ Athena results bucket and contents"
    echo "  ✓ Local SQL and environment files"
    echo ""
    
    if [ -n "${FAILED_OPERATIONS:-}" ]; then
        warning "Please verify charges have stopped in your AWS billing console"
    else
        success "No ongoing charges should remain from this deployment"
    fi
}

# Main destruction function with error handling
main() {
    log "Starting S3 Tables Analytics Infrastructure Destruction"
    echo "======================================================="
    
    # Initialize failed operations tracking
    FAILED_OPERATIONS=""
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    # Execute deletion operations with error handling
    delete_athena_workgroup || handle_cleanup_error "delete_athena_workgroup" "$?"
    delete_sample_table || handle_cleanup_error "delete_sample_table" "$?"
    delete_namespace || handle_cleanup_error "delete_namespace" "$?"
    delete_table_bucket || handle_cleanup_error "delete_table_bucket" "$?"
    delete_athena_results_bucket || handle_cleanup_error "delete_athena_results_bucket" "$?"
    cleanup_local_files || handle_cleanup_error "cleanup_local_files" "$?"
    
    # Only run verification if no critical failures occurred
    if [ -z "${FAILED_OPERATIONS:-}" ]; then
        verify_deletion
    else
        warning "Skipping verification due to previous failures"
    fi
    
    display_summary
    
    if [ -z "${FAILED_OPERATIONS:-}" ]; then
        success "Destruction completed successfully!"
    else
        warning "Destruction completed with some failures. Please review manually."
        exit 1
    fi
}

# Handle script interruption gracefully
trap 'echo ""; warning "Script interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"