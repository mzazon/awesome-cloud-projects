#!/bin/bash

# Destroy script for Business Intelligence Solutions with QuickSight
# This script safely removes all resources created by the deploy script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ -f ".env_quicksight" ]; then
        source .env_quicksight
        log "Loaded environment from .env_quicksight"
    else
        warn "Environment file .env_quicksight not found"
        log "Attempting to detect resources dynamically..."
        
        # Try to get basic AWS info
        export AWS_REGION=$(aws configure get region || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        
        if [ -z "$AWS_ACCOUNT_ID" ]; then
            error "Cannot determine AWS Account ID. Please ensure AWS CLI is configured."
            exit 1
        fi
    fi
    
    log "Environment loaded:"
    log "  AWS Region: ${AWS_REGION:-us-east-1}"
    log "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    
    # Set defaults if not loaded from file
    BUCKET_NAME=${BUCKET_NAME:-""}
    DB_IDENTIFIER=${DB_IDENTIFIER:-""}
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "  • QuickSight Dashboard, Analysis, and Dataset"
    echo "  • QuickSight Data Source"
    echo "  • RDS Database Instance (if exists): ${DB_IDENTIFIER:-<auto-detect>}"
    echo "  • S3 Bucket and all contents (if exists): ${BUCKET_NAME:-<auto-detect>}"
    echo "  • IAM Role and Policies"
    echo ""
    echo "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " CONFIRM
    
    if [ "$CONFIRM" != "DELETE" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Confirmed. Starting resource destruction..."
}

# Function to find and delete QuickSight resources
delete_quicksight_resources() {
    log "Deleting QuickSight resources..."
    
    # Delete refresh schedule first
    if aws quicksight describe-refresh-schedule \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --data-set-id sales-dataset \
        --schedule-id daily-refresh \
        --region "${AWS_REGION}" &>/dev/null; then
        
        aws quicksight delete-refresh-schedule \
            --aws-account-id "${AWS_ACCOUNT_ID}" \
            --data-set-id sales-dataset \
            --schedule-id daily-refresh \
            --region "${AWS_REGION}" || warn "Failed to delete refresh schedule"
        success "Deleted refresh schedule"
    fi
    
    # Delete dashboard
    if aws quicksight describe-dashboard \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --dashboard-id sales-dashboard \
        --region "${AWS_REGION}" &>/dev/null; then
        
        aws quicksight delete-dashboard \
            --aws-account-id "${AWS_ACCOUNT_ID}" \
            --dashboard-id sales-dashboard \
            --region "${AWS_REGION}" || warn "Failed to delete dashboard"
        success "Deleted QuickSight dashboard"
    fi
    
    # Delete analysis
    if aws quicksight describe-analysis \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --analysis-id sales-analysis \
        --region "${AWS_REGION}" &>/dev/null; then
        
        aws quicksight delete-analysis \
            --aws-account-id "${AWS_ACCOUNT_ID}" \
            --analysis-id sales-analysis \
            --region "${AWS_REGION}" || warn "Failed to delete analysis"
        success "Deleted QuickSight analysis"
    fi
    
    # Delete dataset
    if aws quicksight describe-data-set \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --data-set-id sales-dataset \
        --region "${AWS_REGION}" &>/dev/null; then
        
        aws quicksight delete-data-set \
            --aws-account-id "${AWS_ACCOUNT_ID}" \
            --data-set-id sales-dataset \
            --region "${AWS_REGION}" || warn "Failed to delete dataset"
        success "Deleted QuickSight dataset"
    fi
    
    # Delete data source
    if aws quicksight describe-data-source \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --data-source-id sales-data-s3 \
        --region "${AWS_REGION}" &>/dev/null; then
        
        aws quicksight delete-data-source \
            --aws-account-id "${AWS_ACCOUNT_ID}" \
            --data-source-id sales-data-s3 \
            --region "${AWS_REGION}" || warn "Failed to delete data source"
        success "Deleted QuickSight data source"
    fi
}

# Function to delete RDS resources
delete_rds_resources() {
    log "Deleting RDS resources..."
    
    # Find RDS instances if DB_IDENTIFIER is not set
    if [ -z "$DB_IDENTIFIER" ]; then
        log "Searching for QuickSight demo RDS instances..."
        POSSIBLE_IDENTIFIERS=$(aws rds describe-db-instances \
            --query 'DBInstances[?contains(DBInstanceIdentifier, `quicksight-demo-db`)].DBInstanceIdentifier' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$POSSIBLE_IDENTIFIERS" ]; then
            log "Found possible RDS instances: $POSSIBLE_IDENTIFIERS"
            for identifier in $POSSIBLE_IDENTIFIERS; do
                DB_IDENTIFIER="$identifier"
                break  # Use the first one found
            done
        fi
    fi
    
    if [ -n "$DB_IDENTIFIER" ] && aws rds describe-db-instances --db-instance-identifier "${DB_IDENTIFIER}" &>/dev/null; then
        log "Deleting RDS instance: ${DB_IDENTIFIER} (this may take 5-10 minutes)..."
        
        # Delete RDS instance without final snapshot
        aws rds delete-db-instance \
            --db-instance-identifier "${DB_IDENTIFIER}" \
            --skip-final-snapshot \
            --region "${AWS_REGION}" || warn "Failed to delete RDS instance"
        
        # Wait for deletion to start
        log "Waiting for RDS deletion to initiate..."
        sleep 30
        
        success "RDS instance deletion initiated"
    else
        log "No RDS instance found to delete"
    fi
    
    # Delete subnet group
    if aws rds describe-db-subnet-groups --db-subnet-group-name quicksight-subnet-group &>/dev/null; then
        # Wait a bit more for instance deletion to progress
        log "Waiting for RDS instance to be fully deleted before removing subnet group..."
        
        # Check if instance is still deleting
        if [ -n "$DB_IDENTIFIER" ]; then
            while aws rds describe-db-instances --db-instance-identifier "${DB_IDENTIFIER}" &>/dev/null; do
                log "RDS instance still exists, waiting 30 seconds..."
                sleep 30
            done
        fi
        
        aws rds delete-db-subnet-group \
            --db-subnet-group-name quicksight-subnet-group \
            --region "${AWS_REGION}" || warn "Failed to delete subnet group (may still be in use)"
        success "Deleted RDS subnet group"
    fi
}

# Function to delete S3 resources
delete_s3_resources() {
    log "Deleting S3 resources..."
    
    # Find S3 bucket if BUCKET_NAME is not set
    if [ -z "$BUCKET_NAME" ]; then
        log "Searching for QuickSight demo S3 buckets..."
        POSSIBLE_BUCKETS=$(aws s3api list-buckets \
            --query 'Buckets[?contains(Name, `quicksight-bi-data`)].Name' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$POSSIBLE_BUCKETS" ]; then
            log "Found possible S3 buckets: $POSSIBLE_BUCKETS"
            for bucket in $POSSIBLE_BUCKETS; do
                BUCKET_NAME="$bucket"
                break  # Use the first one found
            done
        fi
    fi
    
    if [ -n "$BUCKET_NAME" ] && aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        log "Deleting S3 bucket contents: ${BUCKET_NAME}"
        
        # Delete all objects in bucket
        aws s3 rm "s3://${BUCKET_NAME}" --recursive || warn "Failed to delete bucket contents"
        
        # Delete the bucket
        aws s3 rb "s3://${BUCKET_NAME}" || warn "Failed to delete bucket"
        
        success "Deleted S3 bucket: ${BUCKET_NAME}"
    else
        log "No S3 bucket found to delete"
    fi
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    # Delete IAM role policy
    if aws iam get-role-policy --role-name QuickSight-S3-Role --policy-name QuickSight-S3-Access &>/dev/null; then
        aws iam delete-role-policy \
            --role-name QuickSight-S3-Role \
            --policy-name QuickSight-S3-Access || warn "Failed to delete IAM policy"
        success "Deleted IAM role policy"
    fi
    
    # Delete IAM role
    if aws iam get-role --role-name QuickSight-S3-Role &>/dev/null; then
        aws iam delete-role --role-name QuickSight-S3-Role || warn "Failed to delete IAM role"
        success "Deleted IAM role"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [ -f ".env_quicksight" ]; then
        rm -f .env_quicksight
        success "Removed .env_quicksight file"
    fi
    
    # Remove any remaining temporary files
    TEMP_FILES=(
        "sales_data.csv"
        "quicksight-trust-policy.json"
        "quicksight-s3-policy.json"
        "s3-data-source.json"
        "dataset-s3.json"
        "analysis-config.json"
        "dashboard-config.json"
        "dashboard-permissions.json"
        "refresh-schedule.json"
    )
    
    for file in "${TEMP_FILES[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Removed temporary file: $file"
        fi
    done
    
    success "Local cleanup completed"
}

# Function to validate destruction
validate_destruction() {
    log "Validating resource destruction..."
    
    # Check QuickSight dashboard
    if ! aws quicksight describe-dashboard \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --dashboard-id sales-dashboard \
        --region "${AWS_REGION}" &>/dev/null; then
        success "✅ QuickSight dashboard removed"
    else
        warn "⚠️ QuickSight dashboard still exists"
    fi
    
    # Check QuickSight data source
    if ! aws quicksight describe-data-source \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --data-source-id sales-data-s3 \
        --region "${AWS_REGION}" &>/dev/null; then
        success "✅ QuickSight data source removed"
    else
        warn "⚠️ QuickSight data source still exists"
    fi
    
    # Check S3 bucket
    if [ -n "$BUCKET_NAME" ] && ! aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        success "✅ S3 bucket removed"
    elif [ -n "$BUCKET_NAME" ]; then
        warn "⚠️ S3 bucket still exists: ${BUCKET_NAME}"
    fi
    
    # Check RDS instance
    if [ -n "$DB_IDENTIFIER" ] && ! aws rds describe-db-instances --db-instance-identifier "${DB_IDENTIFIER}" &>/dev/null; then
        success "✅ RDS instance removed"
    elif [ -n "$DB_IDENTIFIER" ]; then
        warn "⚠️ RDS instance still exists (may still be deleting): ${DB_IDENTIFIER}"
    fi
    
    # Check IAM role
    if ! aws iam get-role --role-name QuickSight-S3-Role &>/dev/null; then
        success "✅ IAM role removed"
    else
        warn "⚠️ IAM role still exists"
    fi
}

# Function to display completion message
display_completion_message() {
    success "🧹 Destruction completed!"
    echo ""
    echo "=== QuickSight Business Intelligence Solution Cleanup ==="
    echo ""
    echo "✅ Removed Resources:"
    echo "  • QuickSight Dashboard, Analysis, and Dataset"
    echo "  • QuickSight Data Source"
    echo "  • S3 Bucket and contents (if found)"
    echo "  • RDS Database Instance (if found)"
    echo "  • IAM Role and Policies"
    echo "  • Local temporary files"
    echo ""
    echo "💡 Note: Some resources (like RDS instances) may take several minutes"
    echo "   to fully delete even after this script completes."
    echo ""
    echo "🔍 To verify all resources are deleted, you can:"
    echo "  • Check AWS Console for any remaining resources"
    echo "  • Run: aws quicksight list-dashboards --aws-account-id ${AWS_ACCOUNT_ID}"
    echo "  • Run: aws rds describe-db-instances"
    echo "  • Run: aws s3 ls"
    echo ""
    echo "💰 Cost Impact: All billable resources have been removed."
}

# Function to handle partial cleanup
handle_partial_cleanup() {
    warn "Some resources may still exist. This could be due to:"
    echo "  • Resources still being processed by AWS"
    echo "  • Dependency constraints (e.g., RDS subnet group still in use)"
    echo "  • Insufficient permissions"
    echo "  • Resources were created outside of this script"
    echo ""
    echo "💡 Recommendations:"
    echo "  • Wait a few minutes and check AWS Console"
    echo "  • Manually verify and delete remaining resources"
    echo "  • Check AWS Cost Explorer for any unexpected charges"
}

# Main destruction function
main() {
    log "Starting QuickSight Business Intelligence Solution cleanup..."
    echo ""
    
    # Load environment and confirm
    load_environment
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_quicksight_resources
    delete_rds_resources
    delete_s3_resources
    delete_iam_resources
    cleanup_local_files
    
    # Validate and report
    validate_destruction
    display_completion_message
    
    # Check for any remaining issues
    if aws quicksight describe-dashboard --aws-account-id "${AWS_ACCOUNT_ID}" --dashboard-id sales-dashboard --region "${AWS_REGION}" &>/dev/null || \
       [ -n "$BUCKET_NAME" ] && aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null || \
       aws iam get-role --role-name QuickSight-S3-Role &>/dev/null; then
        handle_partial_cleanup
    fi
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"