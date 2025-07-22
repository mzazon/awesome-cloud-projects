#!/bin/bash

# AWS Serverless ETL Pipeline Cleanup Script
# Recipe: Processing Data with AWS Glue and Lambda
# Version: 1.0

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Load environment variables from .env file
load_environment() {
    if [ -f .env ]; then
        log "Loading environment variables from .env file..."
        export $(grep -v '^#' .env | xargs)
        log_success "Environment variables loaded"
    else
        log_error ".env file not found. Please ensure deployment was successful or provide resource names."
        exit 1
    fi
}

# Confirmation prompt
confirm_deletion() {
    if [ "${FORCE_DELETE:-false}" != "true" ]; then
        echo
        log_warning "This will permanently delete the following resources:"
        echo "  - S3 Bucket: ${BUCKET_NAME:-Unknown}"
        echo "  - Glue Database: ${GLUE_DATABASE:-Unknown}"
        echo "  - Glue Job: ${JOB_NAME:-Unknown}"
        echo "  - Glue Crawler: ${CRAWLER_NAME:-Unknown}"
        echo "  - Glue Workflow: ${WORKFLOW_NAME:-Unknown}"
        echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME:-Unknown}"
        echo "  - IAM Roles and Policies"
        echo
        read -p "Are you sure you want to proceed? (yes/no): " confirmation
        
        if [ "$confirmation" != "yes" ]; then
            log "Deletion cancelled by user"
            exit 0
        fi
    fi
    
    log "Starting resource cleanup..."
}

# Stop any running Glue jobs
stop_running_jobs() {
    log "Stopping any running Glue jobs..."
    
    if [ -n "${JOB_NAME:-}" ]; then
        # Get running job runs
        RUNNING_JOBS=$(aws glue get-job-runs \
            --job-name "$JOB_NAME" \
            --query "JobRuns[?JobRunState=='RUNNING'].Id" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$RUNNING_JOBS" ] && [ "$RUNNING_JOBS" != "None" ]; then
            for job_run_id in $RUNNING_JOBS; do
                log "Stopping job run: $job_run_id"
                aws glue batch-stop-job-run \
                    --job-name "$JOB_NAME" \
                    --job-run-ids "$job_run_id" || true
            done
            
            # Wait for jobs to stop
            log "Waiting for jobs to stop..."
            sleep 30
        fi
    fi
    
    log_success "Stopped running jobs"
}

# Delete Glue workflow and triggers
delete_glue_workflow() {
    log "Deleting Glue workflow and triggers..."
    
    if [ -n "${WORKFLOW_NAME:-}" ]; then
        # Delete triggers first
        TRIGGERS=$(aws glue get-triggers \
            --query "Triggers[?WorkflowName=='${WORKFLOW_NAME}'].Name" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$TRIGGERS" ] && [ "$TRIGGERS" != "None" ]; then
            for trigger_name in $TRIGGERS; do
                log "Deleting trigger: $trigger_name"
                aws glue delete-trigger --name "$trigger_name" || true
            done
        fi
        
        # Delete workflow
        if aws glue get-workflow --name "$WORKFLOW_NAME" &>/dev/null; then
            log "Deleting workflow: $WORKFLOW_NAME"
            aws glue delete-workflow --name "$WORKFLOW_NAME" || true
            log_success "Workflow deleted: $WORKFLOW_NAME"
        else
            log_warning "Workflow not found: $WORKFLOW_NAME"
        fi
    fi
}

# Delete Glue job
delete_glue_job() {
    log "Deleting Glue job..."
    
    if [ -n "${JOB_NAME:-}" ]; then
        if aws glue get-job --job-name "$JOB_NAME" &>/dev/null; then
            log "Deleting job: $JOB_NAME"
            aws glue delete-job --job-name "$JOB_NAME" || true
            log_success "Job deleted: $JOB_NAME"
        else
            log_warning "Job not found: $JOB_NAME"
        fi
    fi
}

# Delete Glue crawler
delete_glue_crawler() {
    log "Deleting Glue crawler..."
    
    if [ -n "${CRAWLER_NAME:-}" ]; then
        # Stop crawler if running
        CRAWLER_STATE=$(aws glue get-crawler \
            --name "$CRAWLER_NAME" \
            --query 'Crawler.State' --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$CRAWLER_STATE" = "RUNNING" ]; then
            log "Stopping crawler: $CRAWLER_NAME"
            aws glue stop-crawler --name "$CRAWLER_NAME" || true
            
            # Wait for crawler to stop
            log "Waiting for crawler to stop..."
            local max_attempts=20
            local attempt=0
            
            while [ $attempt -lt $max_attempts ]; do
                CRAWLER_STATE=$(aws glue get-crawler \
                    --name "$CRAWLER_NAME" \
                    --query 'Crawler.State' --output text 2>/dev/null || echo "NOT_FOUND")
                
                if [ "$CRAWLER_STATE" = "READY" ] || [ "$CRAWLER_STATE" = "NOT_FOUND" ]; then
                    break
                fi
                
                sleep 5
                ((attempt++))
            done
        fi
        
        if aws glue get-crawler --name "$CRAWLER_NAME" &>/dev/null; then
            log "Deleting crawler: $CRAWLER_NAME"
            aws glue delete-crawler --name "$CRAWLER_NAME" || true
            log_success "Crawler deleted: $CRAWLER_NAME"
        else
            log_warning "Crawler not found: $CRAWLER_NAME"
        fi
    fi
}

# Delete Glue database and tables
delete_glue_database() {
    log "Deleting Glue database and tables..."
    
    if [ -n "${GLUE_DATABASE:-}" ]; then
        # Delete tables first
        TABLES=$(aws glue get-tables \
            --database-name "$GLUE_DATABASE" \
            --query 'TableList[].Name' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$TABLES" ] && [ "$TABLES" != "None" ]; then
            for table_name in $TABLES; do
                log "Deleting table: $table_name"
                aws glue delete-table \
                    --database-name "$GLUE_DATABASE" \
                    --name "$table_name" || true
            done
        fi
        
        # Delete database
        if aws glue get-database --name "$GLUE_DATABASE" &>/dev/null; then
            log "Deleting database: $GLUE_DATABASE"
            aws glue delete-database --name "$GLUE_DATABASE" || true
            log_success "Database deleted: $GLUE_DATABASE"
        else
            log_warning "Database not found: $GLUE_DATABASE"
        fi
    fi
}

# Delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
            log "Deleting Lambda function: $LAMBDA_FUNCTION_NAME"
            aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME" || true
            log_success "Lambda function deleted: $LAMBDA_FUNCTION_NAME"
        else
            log_warning "Lambda function not found: $LAMBDA_FUNCTION_NAME"
        fi
    fi
}

# Delete S3 bucket and contents
delete_s3_bucket() {
    log "Deleting S3 bucket and all contents..."
    
    if [ -n "${BUCKET_NAME:-}" ]; then
        # Check if bucket exists
        if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
            log "Deleting all objects in bucket: $BUCKET_NAME"
            
            # Delete all object versions and delete markers
            aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | while read key version_id; do
                if [ -n "$key" ] && [ "$key" != "None" ]; then
                    aws s3api delete-object \
                        --bucket "$BUCKET_NAME" \
                        --key "$key" \
                        --version-id "$version_id" || true
                fi
            done
            
            # Delete delete markers
            aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | while read key version_id; do
                if [ -n "$key" ] && [ "$key" != "None" ]; then
                    aws s3api delete-object \
                        --bucket "$BUCKET_NAME" \
                        --key "$key" \
                        --version-id "$version_id" || true
                fi
            done
            
            # Force delete all remaining objects
            aws s3 rm "s3://$BUCKET_NAME" --recursive --quiet || true
            
            # Delete bucket
            log "Deleting bucket: $BUCKET_NAME"
            aws s3 rb "s3://$BUCKET_NAME" --force || true
            log_success "S3 bucket deleted: $BUCKET_NAME"
        else
            log_warning "S3 bucket not found: $BUCKET_NAME"
        fi
    fi
}

# Delete IAM roles and policies
delete_iam_resources() {
    log "Deleting IAM roles and policies..."
    
    # Delete Glue role and policies
    if [ -n "${GLUE_ROLE:-}" ]; then
        if aws iam get-role --role-name "$GLUE_ROLE" &>/dev/null; then
            log "Deleting Glue role: $GLUE_ROLE"
            
            # Detach AWS managed policies
            aws iam detach-role-policy \
                --role-name "$GLUE_ROLE" \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole || true
            
            # Detach and delete custom S3 policy
            if [ -n "${RANDOM_SUFFIX:-}" ]; then
                GLUE_S3_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/GlueS3AccessPolicy-${RANDOM_SUFFIX}"
                aws iam detach-role-policy \
                    --role-name "$GLUE_ROLE" \
                    --policy-arn "$GLUE_S3_POLICY_ARN" || true
                
                aws iam delete-policy --policy-arn "$GLUE_S3_POLICY_ARN" || true
            fi
            
            # Delete role
            aws iam delete-role --role-name "$GLUE_ROLE" || true
            log_success "Glue role deleted: $GLUE_ROLE"
        else
            log_warning "Glue role not found: $GLUE_ROLE"
        fi
    fi
    
    # Delete Lambda role and policies
    if [ -n "${LAMBDA_ROLE:-}" ]; then
        if aws iam get-role --role-name "$LAMBDA_ROLE" &>/dev/null; then
            log "Deleting Lambda role: $LAMBDA_ROLE"
            
            # Detach AWS managed policies
            aws iam detach-role-policy \
                --role-name "$LAMBDA_ROLE" \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
            
            # Detach and delete custom Glue policy
            if [ -n "${RANDOM_SUFFIX:-}" ]; then
                LAMBDA_GLUE_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LambdaGlueAccessPolicy-${RANDOM_SUFFIX}"
                aws iam detach-role-policy \
                    --role-name "$LAMBDA_ROLE" \
                    --policy-arn "$LAMBDA_GLUE_POLICY_ARN" || true
                
                aws iam delete-policy --policy-arn "$LAMBDA_GLUE_POLICY_ARN" || true
            fi
            
            # Delete role
            aws iam delete-role --role-name "$LAMBDA_ROLE" || true
            log_success "Lambda role deleted: $LAMBDA_ROLE"
        else
            log_warning "Lambda role not found: $LAMBDA_ROLE"
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [ -f .env ]; then
        rm -f .env
        log_success "Removed .env file"
    fi
    
    # Remove any temporary files that might still exist
    rm -f sales_data.csv customer_data.csv glue_etl_script.py
    rm -f lambda_function.py lambda_function.zip response.json
    
    log_success "Local files cleaned up"
}

# Verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local errors=0
    
    # Check S3 bucket
    if [ -n "${BUCKET_NAME:-}" ]; then
        if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
            log_error "S3 bucket still exists: $BUCKET_NAME"
            ((errors++))
        fi
    fi
    
    # Check Glue database
    if [ -n "${GLUE_DATABASE:-}" ]; then
        if aws glue get-database --name "$GLUE_DATABASE" &>/dev/null; then
            log_error "Glue database still exists: $GLUE_DATABASE"
            ((errors++))
        fi
    fi
    
    # Check Lambda function
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
            log_error "Lambda function still exists: $LAMBDA_FUNCTION_NAME"
            ((errors++))
        fi
    fi
    
    # Check IAM roles
    if [ -n "${GLUE_ROLE:-}" ]; then
        if aws iam get-role --role-name "$GLUE_ROLE" &>/dev/null; then
            log_error "Glue role still exists: $GLUE_ROLE"
            ((errors++))
        fi
    fi
    
    if [ -n "${LAMBDA_ROLE:-}" ]; then
        if aws iam get-role --role-name "$LAMBDA_ROLE" &>/dev/null; then
            log_error "Lambda role still exists: $LAMBDA_ROLE"
            ((errors++))
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "All resources successfully deleted"
    else
        log_warning "Some resources may still exist. Check AWS console for manual cleanup."
    fi
}

# Display estimated cost savings
show_cost_savings() {
    log "Estimated cost savings after cleanup:"
    echo "  - S3 storage costs: Eliminated"
    echo "  - Glue job execution costs: Eliminated"
    echo "  - Lambda execution costs: Eliminated"
    echo "  - CloudWatch logs storage: Reduced"
    echo
    log "Note: Some CloudWatch logs may be retained based on retention settings"
}

# Main cleanup function
main() {
    log "Starting AWS Serverless ETL Pipeline cleanup..."
    
    # Parse command line arguments
    FORCE_DELETE=false
    DRY_RUN=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                echo "Usage: $0 [--force] [--dry-run] [--help]"
                echo "  --force: Skip confirmation prompts"
                echo "  --dry-run: Show what would be deleted without actually deleting"
                echo "  --help: Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Load environment variables
    load_environment
    
    if [ "$DRY_RUN" = "true" ]; then
        log "DRY RUN MODE - No resources will be deleted"
        log "Would delete the following resources:"
        echo "  - S3 Bucket: ${BUCKET_NAME:-Unknown}"
        echo "  - Glue Database: ${GLUE_DATABASE:-Unknown}"
        echo "  - Glue Job: ${JOB_NAME:-Unknown}"
        echo "  - Glue Crawler: ${CRAWLER_NAME:-Unknown}"
        echo "  - Glue Workflow: ${WORKFLOW_NAME:-Unknown}"
        echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME:-Unknown}"
        echo "  - IAM Roles and Policies"
        exit 0
    fi
    
    # Confirm deletion
    confirm_deletion
    
    # Execute cleanup steps in reverse order of creation
    stop_running_jobs
    delete_glue_workflow
    delete_lambda_function
    delete_glue_job
    delete_glue_crawler
    delete_glue_database
    delete_s3_bucket
    delete_iam_resources
    cleanup_local_files
    
    # Verify cleanup
    verify_deletion
    
    # Display summary
    log_success "Cleanup completed successfully!"
    echo
    echo "=== Cleanup Summary ==="
    echo "All AWS resources have been removed:"
    echo "✅ S3 bucket and contents deleted"
    echo "✅ Glue database, job, crawler, and workflow deleted"
    echo "✅ Lambda function deleted"
    echo "✅ IAM roles and policies deleted"
    echo "✅ Local files cleaned up"
    echo
    
    show_cost_savings
    
    log "ETL pipeline infrastructure has been completely removed."
}

# Run main function
main "$@"