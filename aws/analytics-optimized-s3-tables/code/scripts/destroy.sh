#!/bin/bash

# AWS S3 Tables Analytics Solution Cleanup Script
# This script safely removes all resources created by the deployment script
# including S3 Tables, Athena workgroups, Glue databases, and supporting resources

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
    log "Loading deployment environment..."
    
    if [ -f .env_deploy ]; then
        source .env_deploy
        success "Environment loaded from .env_deploy"
        log "Deployment timestamp: ${DEPLOYMENT_TIMESTAMP:-unknown}"
    else
        warning "Environment file .env_deploy not found"
        
        # Try to prompt for manual input of critical variables
        echo "Please provide the following information to proceed with cleanup:"
        
        read -p "AWS Region [us-east-1]: " AWS_REGION
        AWS_REGION=${AWS_REGION:-us-east-1}
        
        read -p "Table Bucket Name: " TABLE_BUCKET_NAME
        if [ -z "$TABLE_BUCKET_NAME" ]; then
            error "Table bucket name is required for cleanup"
            exit 1
        fi
        
        read -p "Namespace Name [sales_analytics]: " NAMESPACE_NAME
        NAMESPACE_NAME=${NAMESPACE_NAME:-sales_analytics}
        
        read -p "Table Name [transaction_data]: " TABLE_NAME
        TABLE_NAME=${TABLE_NAME:-transaction_data}
        
        read -p "Glue Database Name [s3_tables_analytics]: " GLUE_DATABASE_NAME
        GLUE_DATABASE_NAME=${GLUE_DATABASE_NAME:-s3_tables_analytics}
        
        read -p "Athena Workgroup Name [s3-tables-workgroup]: " WORKGROUP_NAME
        WORKGROUP_NAME=${WORKGROUP_NAME:-s3-tables-workgroup}
        
        # Set derived variables
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        export ATHENA_RESULTS_BUCKET="aws-athena-query-results-${AWS_ACCOUNT_ID}-${AWS_REGION}"
        
        # Try to find ETL bucket by pattern
        ETL_BUCKET_NAME=$(aws s3 ls | grep "glue-etl-data-" | head -1 | awk '{print $3}' || echo "")
        
        warning "Manual environment setup completed"
    fi
    
    # Validate critical variables
    if [ -z "${TABLE_BUCKET_NAME:-}" ]; then
        error "TABLE_BUCKET_NAME is required for cleanup"
        exit 1
    fi
    
    export AWS_REGION=${AWS_REGION:-us-east-1}
    export NAMESPACE_NAME=${NAMESPACE_NAME:-sales_analytics}
    export TABLE_NAME=${TABLE_NAME:-transaction_data}
    export GLUE_DATABASE_NAME=${GLUE_DATABASE_NAME:-s3_tables_analytics}
    export WORKGROUP_NAME=${WORKGROUP_NAME:-s3-tables-workgroup}
}

# Function to confirm destruction
confirm_destruction() {
    log "Resources to be deleted:"
    echo "======================="
    echo "S3 Tables Resources:"
    echo "  - Table Bucket: ${TABLE_BUCKET_NAME}"
    echo "  - Namespace: ${NAMESPACE_NAME}"
    echo "  - Table: ${TABLE_NAME}"
    echo ""
    echo "Analytics Services:"
    echo "  - Glue Database: ${GLUE_DATABASE_NAME}"
    echo "  - Athena Workgroup: ${WORKGROUP_NAME}"
    echo "  - Athena Results Bucket: ${ATHENA_RESULTS_BUCKET:-unknown}"
    echo ""
    echo "Supporting Resources:"
    echo "  - ETL Bucket: ${ETL_BUCKET_NAME:-unknown}"
    echo ""
    
    # Check if running in non-interactive mode
    if [ "${FORCE_DELETE:-false}" = "true" ]; then
        warning "Force delete mode enabled - proceeding without confirmation"
        return 0
    fi
    
    warning "This action will permanently delete all resources listed above."
    warning "This action cannot be undone."
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Cleanup confirmed - proceeding with resource deletion"
}

# Function to delete S3 Tables resources
delete_s3_tables() {
    log "Deleting S3 Tables resources..."
    
    # Get table bucket ARN if not already set
    if [ -z "${TABLE_BUCKET_ARN:-}" ]; then
        TABLE_BUCKET_ARN=$(aws s3tables list-table-buckets \
            --query "tableBuckets[?name=='${TABLE_BUCKET_NAME}'].arn" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [ -n "$TABLE_BUCKET_ARN" ]; then
        log "Table bucket ARN: $TABLE_BUCKET_ARN"
        
        # Step 1: Delete table
        log "Deleting table: ${TABLE_NAME}"
        if aws s3tables delete-table \
            --table-bucket-arn ${TABLE_BUCKET_ARN} \
            --namespace ${NAMESPACE_NAME} \
            --name ${TABLE_NAME} 2>/dev/null; then
            success "Table deleted: ${TABLE_NAME}"
        else
            warning "Table deletion failed or table doesn't exist: ${TABLE_NAME}"
        fi
        
        # Wait a moment for table deletion to propagate
        sleep 5
        
        # Step 2: Delete namespace
        log "Deleting namespace: ${NAMESPACE_NAME}"
        if aws s3tables delete-namespace \
            --table-bucket-arn ${TABLE_BUCKET_ARN} \
            --namespace ${NAMESPACE_NAME} 2>/dev/null; then
            success "Namespace deleted: ${NAMESPACE_NAME}"
        else
            warning "Namespace deletion failed or namespace doesn't exist: ${NAMESPACE_NAME}"
        fi
        
        # Wait a moment for namespace deletion to propagate
        sleep 10
        
        # Step 3: Delete table bucket
        log "Deleting table bucket: ${TABLE_BUCKET_NAME}"
        if aws s3tables delete-table-bucket \
            --name ${TABLE_BUCKET_NAME} 2>/dev/null; then
            success "Table bucket deleted: ${TABLE_BUCKET_NAME}"
        else
            warning "Table bucket deletion failed or bucket doesn't exist: ${TABLE_BUCKET_NAME}"
        fi
        
    else
        warning "Could not find table bucket: ${TABLE_BUCKET_NAME}"
        warning "It may have already been deleted or never existed"
    fi
}

# Function to delete Glue resources
delete_glue_resources() {
    log "Deleting AWS Glue resources..."
    
    # Delete Glue database
    log "Deleting Glue database: ${GLUE_DATABASE_NAME}"
    if aws glue delete-database --name ${GLUE_DATABASE_NAME} 2>/dev/null; then
        success "Glue database deleted: ${GLUE_DATABASE_NAME}"
    else
        warning "Glue database deletion failed or database doesn't exist: ${GLUE_DATABASE_NAME}"
    fi
}

# Function to delete Athena resources
delete_athena_resources() {
    log "Deleting Amazon Athena resources..."
    
    # Delete Athena workgroup
    log "Deleting Athena workgroup: ${WORKGROUP_NAME}"
    
    # First, try to cancel any running queries
    log "Checking for running queries in workgroup..."
    RUNNING_QUERIES=$(aws athena list-query-executions \
        --work-group ${WORKGROUP_NAME} \
        --query "QueryExecutionIds" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$RUNNING_QUERIES" ] && [ "$RUNNING_QUERIES" != "None" ]; then
        warning "Found running queries - attempting to stop them"
        for query_id in $RUNNING_QUERIES; do
            aws athena stop-query-execution --query-execution-id $query_id 2>/dev/null || true
        done
        sleep 5
    fi
    
    # Delete the workgroup
    if aws athena delete-work-group \
        --work-group ${WORKGROUP_NAME} \
        --recursive-delete-option 2>/dev/null; then
        success "Athena workgroup deleted: ${WORKGROUP_NAME}"
    else
        warning "Athena workgroup deletion failed or workgroup doesn't exist: ${WORKGROUP_NAME}"
    fi
}

# Function to delete S3 buckets and data
delete_s3_buckets() {
    log "Deleting S3 buckets and data..."
    
    # Delete ETL bucket if it exists
    if [ -n "${ETL_BUCKET_NAME:-}" ]; then
        log "Deleting ETL bucket: ${ETL_BUCKET_NAME}"
        
        # Check if bucket exists
        if aws s3 ls s3://${ETL_BUCKET_NAME} &> /dev/null; then
            # Remove all objects first
            log "Removing all objects from ETL bucket..."
            if aws s3 rm s3://${ETL_BUCKET_NAME} --recursive 2>/dev/null; then
                log "Objects removed from ETL bucket"
            else
                warning "Failed to remove some objects from ETL bucket"
            fi
            
            # Delete the bucket
            if aws s3 rb s3://${ETL_BUCKET_NAME} 2>/dev/null; then
                success "ETL bucket deleted: ${ETL_BUCKET_NAME}"
            else
                warning "ETL bucket deletion failed: ${ETL_BUCKET_NAME}"
            fi
        else
            warning "ETL bucket not found or already deleted: ${ETL_BUCKET_NAME}"
        fi
    fi
    
    # Delete Athena results bucket
    if [ -n "${ATHENA_RESULTS_BUCKET:-}" ]; then
        log "Deleting Athena results bucket: ${ATHENA_RESULTS_BUCKET}"
        
        # Check if bucket exists
        if aws s3 ls s3://${ATHENA_RESULTS_BUCKET} &> /dev/null; then
            # Remove all objects first
            log "Removing all objects from Athena results bucket..."
            if aws s3 rm s3://${ATHENA_RESULTS_BUCKET} --recursive 2>/dev/null; then
                log "Objects removed from Athena results bucket"
            else
                warning "Failed to remove some objects from Athena results bucket"
            fi
            
            # Delete the bucket
            if aws s3 rb s3://${ATHENA_RESULTS_BUCKET} 2>/dev/null; then
                success "Athena results bucket deleted: ${ATHENA_RESULTS_BUCKET}"
            else
                warning "Athena results bucket deletion failed: ${ATHENA_RESULTS_BUCKET}"
                warning "You may need to manually delete this bucket if it contains objects"
            fi
        else
            warning "Athena results bucket not found or already deleted: ${ATHENA_RESULTS_BUCKET}"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [ -f .env_deploy ]; then
        rm -f .env_deploy
        success "Environment file removed: .env_deploy"
    fi
    
    # Remove any temporary files that might exist
    rm -f /tmp/table_bucket_policy.json 2>/dev/null || true
    rm -f /tmp/workgroup_config.json 2>/dev/null || true
    rm -f /tmp/sample_transactions.csv 2>/dev/null || true
    
    success "Local cleanup completed"
}

# Function to run verification
verify_deletion() {
    log "Verifying resource deletion..."
    
    local verification_errors=0
    
    # Check table bucket
    if aws s3tables get-table-bucket --name ${TABLE_BUCKET_NAME} &> /dev/null; then
        error "Table bucket still exists: ${TABLE_BUCKET_NAME}"
        verification_errors=$((verification_errors + 1))
    else
        success "Table bucket deletion verified: ${TABLE_BUCKET_NAME}"
    fi
    
    # Check Glue database
    if aws glue get-database --name ${GLUE_DATABASE_NAME} &> /dev/null; then
        error "Glue database still exists: ${GLUE_DATABASE_NAME}"
        verification_errors=$((verification_errors + 1))
    else
        success "Glue database deletion verified: ${GLUE_DATABASE_NAME}"
    fi
    
    # Check Athena workgroup
    if aws athena get-work-group --work-group ${WORKGROUP_NAME} &> /dev/null; then
        error "Athena workgroup still exists: ${WORKGROUP_NAME}"
        verification_errors=$((verification_errors + 1))
    else
        success "Athena workgroup deletion verified: ${WORKGROUP_NAME}"
    fi
    
    # Check ETL bucket
    if [ -n "${ETL_BUCKET_NAME:-}" ] && aws s3 ls s3://${ETL_BUCKET_NAME} &> /dev/null; then
        error "ETL bucket still exists: ${ETL_BUCKET_NAME}"
        verification_errors=$((verification_errors + 1))
    else
        success "ETL bucket deletion verified: ${ETL_BUCKET_NAME:-not specified}"
    fi
    
    if [ $verification_errors -eq 0 ]; then
        success "All resources successfully deleted"
    else
        warning "$verification_errors resources may still exist - manual cleanup may be required"
        log "Please check the AWS Console to verify complete cleanup"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "Cleanup completed at: $(date)"
    echo ""
    echo "Resources processed for deletion:"
    echo "  - S3 Table Bucket: ${TABLE_BUCKET_NAME}"
    echo "  - Namespace: ${NAMESPACE_NAME}"
    echo "  - Table: ${TABLE_NAME}"
    echo "  - Glue Database: ${GLUE_DATABASE_NAME}"
    echo "  - Athena Workgroup: ${WORKGROUP_NAME}"
    echo "  - ETL Bucket: ${ETL_BUCKET_NAME:-not specified}"
    echo "  - Athena Results Bucket: ${ATHENA_RESULTS_BUCKET:-not specified}"
    echo ""
    echo "Next Steps:"
    echo "  - Verify in AWS Console that all resources are deleted"
    echo "  - Check for any remaining costs in your AWS billing dashboard"
    echo "  - Review CloudTrail logs if audit trail is required"
    echo ""
    success "Cleanup process completed!"
}

# Function to handle cleanup errors
handle_cleanup_error() {
    error "Cleanup encountered an error"
    warning "Some resources may not have been deleted completely"
    warning "Please check the AWS Console and manually delete any remaining resources"
    warning "Pay special attention to:"
    warning "  - S3 buckets that may still contain objects"
    warning "  - S3 Tables resources in the S3 Tables console"
    warning "  - Athena workgroups and query results"
    warning "  - Glue catalog databases and tables"
    
    exit 1
}

# Main cleanup function
main() {
    log "Starting AWS S3 Tables Analytics Solution cleanup..."
    log "This script will safely remove all deployed resources"
    
    # Check if running in dry-run mode
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log "Running in DRY-RUN mode - no resources will be deleted"
        warning "Set DRY_RUN=false to perform actual cleanup"
        exit 0
    fi
    
    # Execute cleanup steps
    load_environment
    confirm_destruction
    
    log "Beginning resource deletion process..."
    
    # Delete resources in reverse order of creation
    delete_s3_tables          # Delete S3 Tables first (highest level)
    delete_glue_resources     # Delete Glue resources
    delete_athena_resources   # Delete Athena resources
    delete_s3_buckets        # Delete supporting S3 buckets
    cleanup_local_files      # Clean up local files
    
    # Verify deletion
    verify_deletion
    display_cleanup_summary
    
    log "Cleanup completed at $(date)"
}

# Set error trap
trap handle_cleanup_error ERR

# Execute main function
main "$@"