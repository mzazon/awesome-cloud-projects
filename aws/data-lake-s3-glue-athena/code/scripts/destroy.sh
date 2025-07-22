#!/bin/bash

# AWS Data Lake Architecture Cleanup Script
# This script removes all resources created by deploy.sh
# Following the recipe: Building Data Lake Architectures with S3, Glue, and Athena

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
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
    
    log "Prerequisites check passed ✅"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to load from saved environment file
    if [ -f "/tmp/data-lake-env.sh" ]; then
        source /tmp/data-lake-env.sh
        log "Loaded environment from /tmp/data-lake-env.sh"
    else
        warn "Environment file not found. You may need to provide resource names manually."
        
        # Set basic environment variables
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            warn "AWS region not set, defaulting to us-east-1"
        fi
        
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Ask user for resource names if not found
        if [ -z "${DATA_LAKE_BUCKET:-}" ]; then
            read -p "Enter Data Lake bucket name: " DATA_LAKE_BUCKET
            export DATA_LAKE_BUCKET
        fi
        
        if [ -z "${ATHENA_RESULTS_BUCKET:-}" ]; then
            read -p "Enter Athena results bucket name: " ATHENA_RESULTS_BUCKET
            export ATHENA_RESULTS_BUCKET
        fi
        
        if [ -z "${GLUE_DATABASE_NAME:-}" ]; then
            read -p "Enter Glue database name: " GLUE_DATABASE_NAME
            export GLUE_DATABASE_NAME
        fi
        
        if [ -z "${GLUE_ROLE_NAME:-}" ]; then
            read -p "Enter Glue role name: " GLUE_ROLE_NAME
            export GLUE_ROLE_NAME
        fi
    fi
    
    log "Environment loaded ✅"
    info "AWS Region: $AWS_REGION"
    info "Data Lake Bucket: ${DATA_LAKE_BUCKET:-'Not specified'}"
    info "Athena Results Bucket: ${ATHENA_RESULTS_BUCKET:-'Not specified'}"
}

# Function to confirm cleanup
confirm_cleanup() {
    echo ""
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "This script will permanently delete the following resources:"
    echo "- S3 buckets and all their contents"
    echo "- Glue database, tables, crawlers, and ETL jobs"
    echo "- Athena workgroup and query history"
    echo "- IAM roles and policies"
    echo ""
    
    # Check if this is a force cleanup
    if [ "${1:-}" = "--force" ]; then
        warn "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Cleanup confirmed ✅"
}

# Function to delete Athena workgroup
delete_athena_workgroup() {
    log "Deleting Athena workgroup..."
    
    local workgroup_name="${ATHENA_WORKGROUP:-DataLakeWorkgroup-*}"
    
    # If we have the exact name, delete it
    if [ -n "${ATHENA_WORKGROUP:-}" ]; then
        if aws athena get-work-group --work-group "$ATHENA_WORKGROUP" &>/dev/null; then
            aws athena delete-work-group \
                --work-group "$ATHENA_WORKGROUP" \
                --recursive-delete-option || warn "Failed to delete workgroup $ATHENA_WORKGROUP"
            log "Deleted Athena workgroup: $ATHENA_WORKGROUP"
        else
            warn "Athena workgroup $ATHENA_WORKGROUP not found"
        fi
    else
        # Try to find and delete workgroups with pattern
        local workgroups=$(aws athena list-work-groups \
            --query "WorkGroups[?contains(Name, 'DataLakeWorkgroup-')].Name" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$workgroups" ]; then
            for workgroup in $workgroups; do
                aws athena delete-work-group \
                    --work-group "$workgroup" \
                    --recursive-delete-option || warn "Failed to delete workgroup $workgroup"
                log "Deleted Athena workgroup: $workgroup"
            done
        else
            warn "No Athena workgroups found matching pattern"
        fi
    fi
    
    log "Athena workgroup cleanup completed ✅"
}

# Function to delete Glue resources
delete_glue_resources() {
    log "Deleting Glue resources..."
    
    # Delete Glue crawlers
    if [ -n "${SALES_CRAWLER_NAME:-}" ]; then
        if aws glue get-crawler --name "$SALES_CRAWLER_NAME" &>/dev/null; then
            aws glue delete-crawler --name "$SALES_CRAWLER_NAME" || warn "Failed to delete crawler $SALES_CRAWLER_NAME"
            log "Deleted crawler: $SALES_CRAWLER_NAME"
        fi
    fi
    
    if [ -n "${LOGS_CRAWLER_NAME:-}" ]; then
        if aws glue get-crawler --name "$LOGS_CRAWLER_NAME" &>/dev/null; then
            aws glue delete-crawler --name "$LOGS_CRAWLER_NAME" || warn "Failed to delete crawler $LOGS_CRAWLER_NAME"
            log "Deleted crawler: $LOGS_CRAWLER_NAME"
        fi
    fi
    
    # Try to find and delete crawlers with pattern if specific names not available
    if [ -z "${SALES_CRAWLER_NAME:-}" ] || [ -z "${LOGS_CRAWLER_NAME:-}" ]; then
        local crawlers=$(aws glue list-crawlers \
            --query "CrawlerNames[?contains(@, 'crawler-')]" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$crawlers" ]; then
            for crawler in $crawlers; do
                aws glue delete-crawler --name "$crawler" || warn "Failed to delete crawler $crawler"
                log "Deleted crawler: $crawler"
            done
        fi
    fi
    
    # Delete Glue ETL job
    if [ -n "${ETL_JOB_NAME:-}" ]; then
        if aws glue get-job --job-name "$ETL_JOB_NAME" &>/dev/null; then
            aws glue delete-job --job-name "$ETL_JOB_NAME" || warn "Failed to delete ETL job $ETL_JOB_NAME"
            log "Deleted ETL job: $ETL_JOB_NAME"
        fi
    else
        # Try to find and delete ETL jobs with pattern
        local jobs=$(aws glue list-jobs \
            --query "JobNames[?contains(@, 'etl-')]" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$jobs" ]; then
            for job in $jobs; do
                aws glue delete-job --job-name "$job" || warn "Failed to delete ETL job $job"
                log "Deleted ETL job: $job"
            done
        fi
    fi
    
    # Delete Glue database and tables
    if [ -n "${GLUE_DATABASE_NAME:-}" ]; then
        if aws glue get-database --name "$GLUE_DATABASE_NAME" &>/dev/null; then
            aws glue delete-database --name "$GLUE_DATABASE_NAME" || warn "Failed to delete database $GLUE_DATABASE_NAME"
            log "Deleted Glue database: $GLUE_DATABASE_NAME"
        fi
    else
        # Try to find and delete databases with pattern
        local databases=$(aws glue get-databases \
            --query "DatabaseList[?contains(Name, 'datalake_db_')].Name" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$databases" ]; then
            for database in $databases; do
                aws glue delete-database --name "$database" || warn "Failed to delete database $database"
                log "Deleted Glue database: $database"
            done
        fi
    fi
    
    log "Glue resources cleanup completed ✅"
}

# Function to delete S3 buckets
delete_s3_buckets() {
    log "Deleting S3 buckets..."
    
    # Delete main data lake bucket
    if [ -n "${DATA_LAKE_BUCKET:-}" ]; then
        if aws s3api head-bucket --bucket "$DATA_LAKE_BUCKET" &>/dev/null; then
            log "Deleting all objects in bucket: $DATA_LAKE_BUCKET"
            aws s3 rm "s3://$DATA_LAKE_BUCKET" --recursive || warn "Failed to delete objects in $DATA_LAKE_BUCKET"
            
            # Delete all versions if versioning is enabled
            aws s3api delete-objects \
                --bucket "$DATA_LAKE_BUCKET" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$DATA_LAKE_BUCKET" \
                    --output json \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || warn "Failed to delete object versions"
            
            # Delete delete markers
            aws s3api delete-objects \
                --bucket "$DATA_LAKE_BUCKET" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$DATA_LAKE_BUCKET" \
                    --output json \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || warn "Failed to delete delete markers"
            
            aws s3 rb "s3://$DATA_LAKE_BUCKET" || warn "Failed to delete bucket $DATA_LAKE_BUCKET"
            log "Deleted bucket: $DATA_LAKE_BUCKET"
        else
            warn "Bucket $DATA_LAKE_BUCKET not found"
        fi
    fi
    
    # Delete Athena results bucket
    if [ -n "${ATHENA_RESULTS_BUCKET:-}" ]; then
        if aws s3api head-bucket --bucket "$ATHENA_RESULTS_BUCKET" &>/dev/null; then
            log "Deleting all objects in bucket: $ATHENA_RESULTS_BUCKET"
            aws s3 rm "s3://$ATHENA_RESULTS_BUCKET" --recursive || warn "Failed to delete objects in $ATHENA_RESULTS_BUCKET"
            aws s3 rb "s3://$ATHENA_RESULTS_BUCKET" || warn "Failed to delete bucket $ATHENA_RESULTS_BUCKET"
            log "Deleted bucket: $ATHENA_RESULTS_BUCKET"
        else
            warn "Bucket $ATHENA_RESULTS_BUCKET not found"
        fi
    fi
    
    # If bucket names not available, try to find them by pattern
    if [ -z "${DATA_LAKE_BUCKET:-}" ] || [ -z "${ATHENA_RESULTS_BUCKET:-}" ]; then
        warn "Searching for buckets with common patterns..."
        
        # Look for data lake buckets
        local data_lake_buckets=$(aws s3api list-buckets \
            --query "Buckets[?contains(Name, 'data-lake-')].Name" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$data_lake_buckets" ]; then
            for bucket in $data_lake_buckets; do
                log "Found potential data lake bucket: $bucket"
                read -p "Delete bucket $bucket? (y/n): " delete_bucket
                if [ "$delete_bucket" = "y" ]; then
                    aws s3 rm "s3://$bucket" --recursive || warn "Failed to delete objects in $bucket"
                    aws s3 rb "s3://$bucket" || warn "Failed to delete bucket $bucket"
                    log "Deleted bucket: $bucket"
                fi
            done
        fi
        
        # Look for Athena results buckets
        local athena_buckets=$(aws s3api list-buckets \
            --query "Buckets[?contains(Name, 'athena-results-')].Name" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$athena_buckets" ]; then
            for bucket in $athena_buckets; do
                log "Found potential Athena results bucket: $bucket"
                read -p "Delete bucket $bucket? (y/n): " delete_bucket
                if [ "$delete_bucket" = "y" ]; then
                    aws s3 rm "s3://$bucket" --recursive || warn "Failed to delete objects in $bucket"
                    aws s3 rb "s3://$bucket" || warn "Failed to delete bucket $bucket"
                    log "Deleted bucket: $bucket"
                fi
            done
        fi
    fi
    
    log "S3 buckets cleanup completed ✅"
}

# Function to delete IAM roles and policies
delete_iam_resources() {
    log "Deleting IAM roles and policies..."
    
    if [ -n "${GLUE_ROLE_NAME:-}" ]; then
        # Check if role exists
        if aws iam get-role --role-name "$GLUE_ROLE_NAME" &>/dev/null; then
            # Detach AWS managed policy
            aws iam detach-role-policy \
                --role-name "$GLUE_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole || warn "Failed to detach AWS managed policy"
            
            # Get and detach custom policies
            local attached_policies=$(aws iam list-attached-role-policies \
                --role-name "$GLUE_ROLE_NAME" \
                --query "AttachedPolicies[?contains(PolicyName, 'S3Policy')].PolicyArn" \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$attached_policies" ]; then
                for policy_arn in $attached_policies; do
                    aws iam detach-role-policy \
                        --role-name "$GLUE_ROLE_NAME" \
                        --policy-arn "$policy_arn" || warn "Failed to detach policy $policy_arn"
                    
                    # Delete custom policy if it's account-specific
                    if [[ "$policy_arn" == *"$AWS_ACCOUNT_ID"* ]]; then
                        aws iam delete-policy --policy-arn "$policy_arn" || warn "Failed to delete policy $policy_arn"
                        log "Deleted custom policy: $policy_arn"
                    fi
                done
            fi
            
            # Delete the role
            aws iam delete-role --role-name "$GLUE_ROLE_NAME" || warn "Failed to delete role $GLUE_ROLE_NAME"
            log "Deleted IAM role: $GLUE_ROLE_NAME"
        else
            warn "IAM role $GLUE_ROLE_NAME not found"
        fi
    else
        # Try to find and delete roles with pattern
        local roles=$(aws iam list-roles \
            --query "Roles[?contains(RoleName, 'GlueServiceRole-')].RoleName" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$roles" ]; then
            for role in $roles; do
                log "Found potential Glue role: $role"
                read -p "Delete role $role? (y/n): " delete_role
                if [ "$delete_role" = "y" ]; then
                    # Detach all policies
                    local policies=$(aws iam list-attached-role-policies \
                        --role-name "$role" \
                        --query "AttachedPolicies[].PolicyArn" \
                        --output text 2>/dev/null || echo "")
                    
                    if [ -n "$policies" ]; then
                        for policy_arn in $policies; do
                            aws iam detach-role-policy \
                                --role-name "$role" \
                                --policy-arn "$policy_arn" || warn "Failed to detach policy $policy_arn"
                            
                            # Delete custom policy if it's account-specific
                            if [[ "$policy_arn" == *"$AWS_ACCOUNT_ID"* ]]; then
                                aws iam delete-policy --policy-arn "$policy_arn" || warn "Failed to delete policy $policy_arn"
                                log "Deleted custom policy: $policy_arn"
                            fi
                        done
                    fi
                    
                    aws iam delete-role --role-name "$role" || warn "Failed to delete role $role"
                    log "Deleted IAM role: $role"
                fi
            done
        fi
    fi
    
    log "IAM resources cleanup completed ✅"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Clean up temporary files
    rm -f /tmp/data-lake-env.sh
    rm -f /tmp/lifecycle-policy.json
    rm -f /tmp/glue-trust-policy.json
    rm -f /tmp/glue-s3-policy.json
    rm -f /tmp/sample-sales-data.csv
    rm -f /tmp/sample-web-logs.json
    rm -f /tmp/glue-etl-script.py
    rm -f /tmp/sample-queries.sql
    
    log "Temporary files cleaned up ✅"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_issues=0
    
    # Check if buckets still exist
    if [ -n "${DATA_LAKE_BUCKET:-}" ]; then
        if aws s3api head-bucket --bucket "$DATA_LAKE_BUCKET" &>/dev/null; then
            warn "Bucket $DATA_LAKE_BUCKET still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [ -n "${ATHENA_RESULTS_BUCKET:-}" ]; then
        if aws s3api head-bucket --bucket "$ATHENA_RESULTS_BUCKET" &>/dev/null; then
            warn "Bucket $ATHENA_RESULTS_BUCKET still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check if Glue database still exists
    if [ -n "${GLUE_DATABASE_NAME:-}" ]; then
        if aws glue get-database --name "$GLUE_DATABASE_NAME" &>/dev/null; then
            warn "Glue database $GLUE_DATABASE_NAME still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check if IAM role still exists
    if [ -n "${GLUE_ROLE_NAME:-}" ]; then
        if aws iam get-role --role-name "$GLUE_ROLE_NAME" &>/dev/null; then
            warn "IAM role $GLUE_ROLE_NAME still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log "Cleanup verification passed ✅"
    else
        warn "Cleanup verification found $cleanup_issues issues"
        warn "You may need to manually delete remaining resources"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "================"
    echo "The following resources have been deleted:"
    echo "- Athena workgroup: ${ATHENA_WORKGROUP:-'Pattern matched'}"
    echo "- Glue crawlers: ${SALES_CRAWLER_NAME:-'Pattern matched'}, ${LOGS_CRAWLER_NAME:-'Pattern matched'}"
    echo "- Glue ETL job: ${ETL_JOB_NAME:-'Pattern matched'}"
    echo "- Glue database: ${GLUE_DATABASE_NAME:-'Pattern matched'}"
    echo "- S3 buckets: ${DATA_LAKE_BUCKET:-'Pattern matched'}, ${ATHENA_RESULTS_BUCKET:-'Pattern matched'}"
    echo "- IAM role: ${GLUE_ROLE_NAME:-'Pattern matched'}"
    echo "- Temporary files and configurations"
    echo "================"
    echo ""
    echo "AWS resources have been cleaned up to avoid ongoing charges."
    echo "Check your AWS console to verify all resources are deleted."
}

# Main cleanup function
main() {
    log "Starting AWS Data Lake Architecture cleanup..."
    
    # Check if this is a dry run
    if [ "${1:-}" = "--dry-run" ]; then
        log "DRY RUN MODE - No resources will be deleted"
        export DRY_RUN=true
    fi
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_cleanup "$@"
    delete_athena_workgroup
    delete_glue_resources
    delete_s3_buckets
    delete_iam_resources
    cleanup_temp_files
    verify_cleanup
    display_cleanup_summary
    
    log "Cleanup completed successfully! ✅"
}

# Handle script interruption
trap 'error "Cleanup interrupted"; exit 1' INT TERM

# Run main function
main "$@"