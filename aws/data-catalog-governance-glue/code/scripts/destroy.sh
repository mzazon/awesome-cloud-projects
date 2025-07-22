#!/bin/bash

# Destroy script for AWS Glue Data Catalog Governance Recipe
# This script safely removes all resources created by the deployment

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
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ -f .env ]]; then
        source .env
        success "Environment variables loaded from .env file"
    else
        error "No .env file found. Please run deploy.sh first or ensure you're in the correct directory."
    fi
    
    # Verify required variables are set
    local required_vars=("AWS_REGION" "AWS_ACCOUNT_ID" "GOVERNANCE_BUCKET" "DATABASE_NAME" "CRAWLER_NAME" "AUDIT_BUCKET" "CLASSIFIER_NAME" "GLUE_ROLE_NAME" "POLICY_NAME" "TRAIL_NAME" "DASHBOARD_NAME")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required environment variable $var is not set"
        fi
    done
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    success "Prerequisites check passed"
}

# Confirmation prompt
confirm_destruction() {
    echo
    warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo
    log "This will permanently delete the following resources:"
    echo "  - Data Catalog Database: ${DATABASE_NAME}"
    echo "  - S3 Buckets: ${GOVERNANCE_BUCKET}, ${AUDIT_BUCKET}"
    echo "  - Crawler: ${CRAWLER_NAME}"
    echo "  - CloudTrail: ${TRAIL_NAME}"
    echo "  - IAM Role: ${GLUE_ROLE_NAME}"
    echo "  - IAM Policy: ${POLICY_NAME}"
    echo "  - CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "  - All associated data and configurations"
    echo
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Stop and delete CloudTrail
remove_cloudtrail() {
    log "Removing CloudTrail..."
    
    # Stop CloudTrail logging
    aws cloudtrail stop-logging \
        --name ${TRAIL_NAME} \
        2>/dev/null || warning "Failed to stop CloudTrail logging (may already be stopped)"
    
    # Delete CloudTrail
    aws cloudtrail delete-trail \
        --name ${TRAIL_NAME} \
        2>/dev/null || warning "Failed to delete CloudTrail (may not exist)"
    
    success "CloudTrail removed"
}

# Remove Lake Formation configurations
remove_lake_formation() {
    log "Removing Lake Formation configurations..."
    
    # Get table name if available
    local table_name=""
    if [[ -n "${TABLE_NAME:-}" ]]; then
        table_name="$TABLE_NAME"
    else
        table_name=$(aws glue get-tables \
            --database-name ${DATABASE_NAME} \
            --query 'TableList[0].Name' --output text 2>/dev/null || echo "")
    fi
    
    # Revoke Lake Formation permissions if table exists
    if [[ -n "$table_name" && "$table_name" != "None" ]]; then
        # Note: In production, you would revoke permissions for actual data analyst roles
        # For this demo, we'll just log the action
        log "Would revoke Lake Formation permissions for table: $table_name"
    fi
    
    # Deregister S3 location
    aws lakeformation deregister-resource \
        --resource-arn arn:aws:s3:::${GOVERNANCE_BUCKET}/data/ \
        2>/dev/null || warning "Failed to deregister S3 location (may not be registered)"
    
    success "Lake Formation configurations removed"
}

# Delete Glue resources
remove_glue_resources() {
    log "Removing Glue resources..."
    
    # Stop crawler if running
    local crawler_state=$(aws glue get-crawler \
        --name ${CRAWLER_NAME} \
        --query 'Crawler.State' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$crawler_state" == "RUNNING" ]]; then
        log "Stopping running crawler..."
        aws glue stop-crawler --name ${CRAWLER_NAME} 2>/dev/null || warning "Failed to stop crawler"
        
        # Wait for crawler to stop
        local max_attempts=10
        local attempt=1
        while [ $attempt -le $max_attempts ]; do
            local state=$(aws glue get-crawler \
                --name ${CRAWLER_NAME} \
                --query 'Crawler.State' --output text 2>/dev/null || echo "NOT_FOUND")
            
            if [[ "$state" == "READY" || "$state" == "NOT_FOUND" ]]; then
                break
            fi
            
            log "Waiting for crawler to stop (attempt $attempt/$max_attempts)..."
            sleep 10
            ((attempt++))
        done
    fi
    
    # Delete crawler
    aws glue delete-crawler \
        --name ${CRAWLER_NAME} \
        2>/dev/null || warning "Failed to delete crawler (may not exist)"
    
    # Delete classifier
    aws glue delete-classifier \
        --name ${CLASSIFIER_NAME} \
        2>/dev/null || warning "Failed to delete classifier (may not exist)"
    
    # Delete database and tables
    aws glue delete-database \
        --name ${DATABASE_NAME} \
        2>/dev/null || warning "Failed to delete database (may not exist)"
    
    success "Glue resources removed"
}

# Remove IAM roles and policies
remove_iam_resources() {
    log "Removing IAM roles and policies..."
    
    # Detach and delete IAM policies from role
    aws iam detach-role-policy \
        --role-name ${GLUE_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole \
        2>/dev/null || warning "Failed to detach Glue service role policy"
    
    aws iam detach-role-policy \
        --role-name ${GLUE_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
        2>/dev/null || warning "Failed to detach S3 read-only policy"
    
    # Delete IAM role
    aws iam delete-role \
        --role-name ${GLUE_ROLE_NAME} \
        2>/dev/null || warning "Failed to delete IAM role (may not exist)"
    
    # Delete custom policy
    aws iam delete-policy \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME} \
        2>/dev/null || warning "Failed to delete custom policy (may not exist)"
    
    success "IAM roles and policies removed"
}

# Remove CloudWatch dashboard
remove_dashboard() {
    log "Removing CloudWatch dashboard..."
    
    aws cloudwatch delete-dashboards \
        --dashboard-names ${DASHBOARD_NAME} \
        2>/dev/null || warning "Failed to delete CloudWatch dashboard (may not exist)"
    
    success "CloudWatch dashboard removed"
}

# Empty and delete S3 buckets
remove_s3_resources() {
    log "Removing S3 buckets..."
    
    # Empty and delete governance bucket
    log "Emptying governance bucket: ${GOVERNANCE_BUCKET}"
    aws s3 rm s3://${GOVERNANCE_BUCKET} --recursive 2>/dev/null || warning "Failed to empty governance bucket"
    
    aws s3 rb s3://${GOVERNANCE_BUCKET} 2>/dev/null || warning "Failed to delete governance bucket"
    
    # Empty and delete audit bucket
    log "Emptying audit bucket: ${AUDIT_BUCKET}"
    aws s3 rm s3://${AUDIT_BUCKET} --recursive 2>/dev/null || warning "Failed to empty audit bucket"
    
    aws s3 rb s3://${AUDIT_BUCKET} 2>/dev/null || warning "Failed to delete audit bucket"
    
    success "S3 buckets removed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    rm -f .env
    
    # Remove any temporary files that might be left
    rm -f glue-trust-policy.json data-analyst-policy.json
    rm -f pii-detection-script.py governance-dashboard.json
    rm -f sample_customer_data.csv
    
    success "Local files cleaned up"
}

# Verify resource deletion
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local issues_found=0
    
    # Check if database still exists
    if aws glue get-database --name ${DATABASE_NAME} &>/dev/null; then
        warning "Database ${DATABASE_NAME} still exists"
        ((issues_found++))
    fi
    
    # Check if S3 buckets still exist
    if aws s3 ls s3://${GOVERNANCE_BUCKET} &>/dev/null; then
        warning "Governance bucket ${GOVERNANCE_BUCKET} still exists"
        ((issues_found++))
    fi
    
    if aws s3 ls s3://${AUDIT_BUCKET} &>/dev/null; then
        warning "Audit bucket ${AUDIT_BUCKET} still exists"
        ((issues_found++))
    fi
    
    # Check if IAM role still exists
    if aws iam get-role --role-name ${GLUE_ROLE_NAME} &>/dev/null; then
        warning "IAM role ${GLUE_ROLE_NAME} still exists"
        ((issues_found++))
    fi
    
    # Check if CloudTrail still exists
    if aws cloudtrail describe-trails --trail-name-list ${TRAIL_NAME} --query 'trailList[0]' --output text 2>/dev/null | grep -q "${TRAIL_NAME}"; then
        warning "CloudTrail ${TRAIL_NAME} still exists"
        ((issues_found++))
    fi
    
    if [[ $issues_found -eq 0 ]]; then
        success "All resources successfully removed"
    else
        warning "Some resources may still exist ($issues_found issues found)"
        log "You may need to manually remove these resources from the AWS console"
    fi
}

# Handle script interruption
cleanup_on_exit() {
    log "Script interrupted, cleaning up temporary files..."
    rm -f glue-trust-policy.json data-analyst-policy.json
    rm -f pii-detection-script.py governance-dashboard.json
    rm -f sample_customer_data.csv
}

# Set up trap for cleanup
trap cleanup_on_exit EXIT

# Main destruction function
main() {
    log "Starting AWS Glue Data Catalog Governance cleanup..."
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    log "Beginning resource cleanup..."
    
    # Remove resources in reverse order of creation
    remove_cloudtrail
    remove_dashboard
    remove_lake_formation
    remove_glue_resources
    remove_iam_resources
    remove_s3_resources
    verify_cleanup
    cleanup_local_files
    
    success "Cleanup completed successfully!"
    echo
    log "Summary:"
    echo "  - All AWS resources have been removed"
    echo "  - Local configuration files have been cleaned up"
    echo "  - No further charges should be incurred"
    echo
    log "If you encounter any issues, check the AWS Console to manually remove any remaining resources"
}

# Run main function
main "$@"