#!/bin/bash

# AWS ETL Pipelines with Glue and Data Catalog Management - Cleanup Script
# This script removes all resources created by the deployment script including
# S3 buckets, IAM roles, Glue database, crawlers, and ETL jobs

set -e  # Exit on any error

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Check if .env file exists
    if [ ! -f ".env" ]; then
        error "Environment file .env not found. Please run deploy.sh first or provide resource names manually."
        echo ""
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help                    Show this help message"
        echo "  --force                   Skip confirmation prompts"
        echo "  --glue-database NAME      Specify Glue database name"
        echo "  --s3-raw-bucket NAME      Specify raw S3 bucket name"
        echo "  --s3-processed-bucket NAME Specify processed S3 bucket name"
        echo "  --glue-role NAME          Specify Glue IAM role name"
        echo "  --crawler NAME            Specify raw data crawler name"
        echo "  --processed-crawler NAME  Specify processed data crawler name"
        echo "  --job NAME                Specify ETL job name"
        exit 1
    fi
    
    # Load environment variables from file
    source .env
    
    # Verify required variables are set
    if [ -z "$GLUE_DATABASE_NAME" ] || [ -z "$S3_RAW_BUCKET" ] || [ -z "$S3_PROCESSED_BUCKET" ] || \
       [ -z "$GLUE_ROLE_NAME" ] || [ -z "$CRAWLER_NAME" ] || [ -z "$JOB_NAME" ]; then
        error "Required environment variables not found in .env file"
        exit 1
    fi
    
    success "Environment variables loaded successfully"
    log "Database: ${GLUE_DATABASE_NAME}"
    log "Raw bucket: ${S3_RAW_BUCKET}"
    log "Processed bucket: ${S3_PROCESSED_BUCKET}"
    log "IAM role: ${GLUE_ROLE_NAME}"
    log "Crawler: ${CRAWLER_NAME}"
    log "ETL job: ${JOB_NAME}"
}

# Function to parse command line arguments
parse_arguments() {
    FORCE_MODE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                echo "AWS ETL Pipelines Cleanup Script"
                echo ""
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --help                    Show this help message"
                echo "  --force                   Skip confirmation prompts"
                echo "  --glue-database NAME      Specify Glue database name"
                echo "  --s3-raw-bucket NAME      Specify raw S3 bucket name"
                echo "  --s3-processed-bucket NAME Specify processed S3 bucket name"
                echo "  --glue-role NAME          Specify Glue IAM role name"
                echo "  --crawler NAME            Specify raw data crawler name"
                echo "  --processed-crawler NAME  Specify processed data crawler name"
                echo "  --job NAME                Specify ETL job name"
                exit 0
                ;;
            --force)
                FORCE_MODE=true
                shift
                ;;
            --glue-database)
                GLUE_DATABASE_NAME="$2"
                shift 2
                ;;
            --s3-raw-bucket)
                S3_RAW_BUCKET="$2"
                shift 2
                ;;
            --s3-processed-bucket)
                S3_PROCESSED_BUCKET="$2"
                shift 2
                ;;
            --glue-role)
                GLUE_ROLE_NAME="$2"
                shift 2
                ;;
            --crawler)
                CRAWLER_NAME="$2"
                shift 2
                ;;
            --processed-crawler)
                PROCESSED_CRAWLER_NAME="$2"
                shift 2
                ;;
            --job)
                JOB_NAME="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# Function to confirm cleanup
confirm_cleanup() {
    if [ "$FORCE_MODE" = false ]; then
        echo ""
        echo "=========================================="
        echo "         RESOURCE CLEANUP WARNING"
        echo "=========================================="
        echo ""
        echo "This script will DELETE the following resources:"
        echo ""
        echo "AWS Glue Resources:"
        echo "  • Database: ${GLUE_DATABASE_NAME}"
        echo "  • Crawler: ${CRAWLER_NAME}"
        echo "  • Processed Crawler: ${PROCESSED_CRAWLER_NAME}"
        echo "  • ETL Job: ${JOB_NAME}"
        echo ""
        echo "S3 Resources:"
        echo "  • Raw Data Bucket: ${S3_RAW_BUCKET} (and all contents)"
        echo "  • Processed Data Bucket: ${S3_PROCESSED_BUCKET} (and all contents)"
        echo ""
        echo "IAM Resources:"
        echo "  • Role: ${GLUE_ROLE_NAME}"
        echo ""
        echo "⚠️  WARNING: This action is IRREVERSIBLE!"
        echo "⚠️  All data in S3 buckets will be permanently deleted!"
        echo ""
        
        read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
        
        if [ "$confirmation" != "yes" ]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
        
        echo ""
        log "Proceeding with resource cleanup..."
    else
        log "Force mode enabled - skipping confirmation"
    fi
}

# Function to stop and delete crawlers
cleanup_crawlers() {
    log "Cleaning up Glue crawlers..."
    
    # Stop and delete raw data crawler
    if aws glue get-crawler --name "${CRAWLER_NAME}" &> /dev/null; then
        log "Stopping crawler: ${CRAWLER_NAME}"
        aws glue stop-crawler --name "${CRAWLER_NAME}" 2>/dev/null || true
        
        # Wait for crawler to stop
        log "Waiting for crawler to stop..."
        while true; do
            CRAWLER_STATE=$(aws glue get-crawler \
                --name "${CRAWLER_NAME}" \
                --query Crawler.State --output text 2>/dev/null || echo "NOT_FOUND")
            
            if [ "$CRAWLER_STATE" = "READY" ] || [ "$CRAWLER_STATE" = "NOT_FOUND" ]; then
                break
            else
                log "Crawler status: $CRAWLER_STATE - waiting..."
                sleep 10
            fi
        done
        
        # Delete crawler
        aws glue delete-crawler --name "${CRAWLER_NAME}"
        success "Raw data crawler deleted: ${CRAWLER_NAME}"
    else
        warning "Raw data crawler not found: ${CRAWLER_NAME}"
    fi
    
    # Stop and delete processed data crawler
    if [ -n "${PROCESSED_CRAWLER_NAME}" ] && aws glue get-crawler --name "${PROCESSED_CRAWLER_NAME}" &> /dev/null; then
        log "Stopping processed data crawler: ${PROCESSED_CRAWLER_NAME}"
        aws glue stop-crawler --name "${PROCESSED_CRAWLER_NAME}" 2>/dev/null || true
        
        # Wait for crawler to stop
        log "Waiting for processed data crawler to stop..."
        while true; do
            CRAWLER_STATE=$(aws glue get-crawler \
                --name "${PROCESSED_CRAWLER_NAME}" \
                --query Crawler.State --output text 2>/dev/null || echo "NOT_FOUND")
            
            if [ "$CRAWLER_STATE" = "READY" ] || [ "$CRAWLER_STATE" = "NOT_FOUND" ]; then
                break
            else
                log "Crawler status: $CRAWLER_STATE - waiting..."
                sleep 10
            fi
        done
        
        # Delete crawler
        aws glue delete-crawler --name "${PROCESSED_CRAWLER_NAME}"
        success "Processed data crawler deleted: ${PROCESSED_CRAWLER_NAME}"
    else
        warning "Processed data crawler not found: ${PROCESSED_CRAWLER_NAME}"
    fi
}

# Function to delete ETL job
cleanup_etl_job() {
    log "Cleaning up Glue ETL job..."
    
    if aws glue get-job --job-name "${JOB_NAME}" &> /dev/null; then
        # Stop any running job runs
        log "Checking for running job executions..."
        RUNNING_JOBS=$(aws glue get-job-runs \
            --job-name "${JOB_NAME}" \
            --query 'JobRuns[?JobRunState==`RUNNING`].Id' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$RUNNING_JOBS" ]; then
            log "Stopping running job executions..."
            for job_run_id in $RUNNING_JOBS; do
                aws glue batch-stop-job-run \
                    --job-name "${JOB_NAME}" \
                    --job-run-ids "$job_run_id" 2>/dev/null || true
            done
            
            # Wait for jobs to stop
            log "Waiting for job runs to stop..."
            sleep 30
        fi
        
        # Delete job
        aws glue delete-job --job-name "${JOB_NAME}"
        success "ETL job deleted: ${JOB_NAME}"
    else
        warning "ETL job not found: ${JOB_NAME}"
    fi
}

# Function to delete Glue database
cleanup_glue_database() {
    log "Cleaning up Glue database..."
    
    if aws glue get-database --name "${GLUE_DATABASE_NAME}" &> /dev/null; then
        # Delete database (this also removes all tables)
        aws glue delete-database --name "${GLUE_DATABASE_NAME}"
        success "Glue database deleted: ${GLUE_DATABASE_NAME}"
    else
        warning "Glue database not found: ${GLUE_DATABASE_NAME}"
    fi
}

# Function to delete IAM role
cleanup_iam_role() {
    log "Cleaning up IAM role..."
    
    if aws iam get-role --role-name "${GLUE_ROLE_NAME}" &> /dev/null; then
        # Detach managed policies
        log "Detaching managed policies..."
        aws iam detach-role-policy \
            --role-name "${GLUE_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || true
        
        # Delete inline policies
        log "Deleting inline policies..."
        aws iam delete-role-policy \
            --role-name "${GLUE_ROLE_NAME}" \
            --policy-name GlueS3Access 2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "${GLUE_ROLE_NAME}"
        success "IAM role deleted: ${GLUE_ROLE_NAME}"
    else
        warning "IAM role not found: ${GLUE_ROLE_NAME}"
    fi
}

# Function to delete S3 buckets
cleanup_s3_buckets() {
    log "Cleaning up S3 buckets..."
    
    # Empty and delete raw data bucket
    if aws s3 ls "s3://${S3_RAW_BUCKET}" &> /dev/null; then
        log "Emptying raw data bucket: ${S3_RAW_BUCKET}"
        aws s3 rm "s3://${S3_RAW_BUCKET}" --recursive 2>/dev/null || true
        
        log "Deleting raw data bucket: ${S3_RAW_BUCKET}"
        aws s3 rb "s3://${S3_RAW_BUCKET}" 2>/dev/null || true
        success "Raw data bucket deleted: ${S3_RAW_BUCKET}"
    else
        warning "Raw data bucket not found: ${S3_RAW_BUCKET}"
    fi
    
    # Empty and delete processed data bucket
    if aws s3 ls "s3://${S3_PROCESSED_BUCKET}" &> /dev/null; then
        log "Emptying processed data bucket: ${S3_PROCESSED_BUCKET}"
        aws s3 rm "s3://${S3_PROCESSED_BUCKET}" --recursive 2>/dev/null || true
        
        log "Deleting processed data bucket: ${S3_PROCESSED_BUCKET}"
        aws s3 rb "s3://${S3_PROCESSED_BUCKET}" 2>/dev/null || true
        success "Processed data bucket deleted: ${S3_PROCESSED_BUCKET}"
    else
        warning "Processed data bucket not found: ${S3_PROCESSED_BUCKET}"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files that might be left over
    rm -f glue-trust-policy.json glue-s3-policy.json etl-script.py sample-sales.csv sample-customers.json
    
    # Remove environment file
    if [ -f ".env" ]; then
        rm -f .env
        success "Environment file removed"
    fi
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local cleanup_successful=true
    
    # Check if resources still exist
    if aws glue get-database --name "${GLUE_DATABASE_NAME}" &> /dev/null; then
        warning "Glue database still exists: ${GLUE_DATABASE_NAME}"
        cleanup_successful=false
    fi
    
    if aws glue get-crawler --name "${CRAWLER_NAME}" &> /dev/null; then
        warning "Crawler still exists: ${CRAWLER_NAME}"
        cleanup_successful=false
    fi
    
    if aws glue get-job --job-name "${JOB_NAME}" &> /dev/null; then
        warning "ETL job still exists: ${JOB_NAME}"
        cleanup_successful=false
    fi
    
    if aws iam get-role --role-name "${GLUE_ROLE_NAME}" &> /dev/null; then
        warning "IAM role still exists: ${GLUE_ROLE_NAME}"
        cleanup_successful=false
    fi
    
    if aws s3 ls "s3://${S3_RAW_BUCKET}" &> /dev/null; then
        warning "Raw data bucket still exists: ${S3_RAW_BUCKET}"
        cleanup_successful=false
    fi
    
    if aws s3 ls "s3://${S3_PROCESSED_BUCKET}" &> /dev/null; then
        warning "Processed data bucket still exists: ${S3_PROCESSED_BUCKET}"
        cleanup_successful=false
    fi
    
    if [ "$cleanup_successful" = true ]; then
        success "All resources have been successfully removed"
    else
        warning "Some resources may still exist. Please check the AWS console for any remaining resources."
    fi
}

# Function to display cleanup summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "   CLEANUP COMPLETED"
    echo "=========================================="
    echo ""
    echo "Resources Removed:"
    echo "  • S3 Raw Data Bucket: ${S3_RAW_BUCKET}"
    echo "  • S3 Processed Data Bucket: ${S3_PROCESSED_BUCKET}"
    echo "  • IAM Role: ${GLUE_ROLE_NAME}"
    echo "  • Glue Database: ${GLUE_DATABASE_NAME}"
    echo "  • Raw Data Crawler: ${CRAWLER_NAME}"
    if [ -n "${PROCESSED_CRAWLER_NAME}" ]; then
        echo "  • Processed Data Crawler: ${PROCESSED_CRAWLER_NAME}"
    fi
    echo "  • ETL Job: ${JOB_NAME}"
    echo ""
    echo "Cost Impact:"
    echo "  • S3 storage charges have stopped"
    echo "  • Glue DPU charges have stopped"
    echo "  • No further infrastructure costs"
    echo ""
    echo "Note: It may take a few minutes for billing"
    echo "changes to reflect in your AWS account."
    echo "=========================================="
}

# Main execution
main() {
    echo "=========================================="
    echo "   AWS ETL Pipelines Cleanup Script"
    echo "=========================================="
    echo ""
    
    # Parse command line arguments first
    parse_arguments "$@"
    
    check_prerequisites
    
    # Load environment if not provided via command line
    if [ -z "$GLUE_DATABASE_NAME" ]; then
        load_environment
    fi
    
    confirm_cleanup
    
    # Execute cleanup in order (opposite of deployment)
    cleanup_crawlers
    cleanup_etl_job
    cleanup_glue_database
    cleanup_iam_role
    cleanup_s3_buckets
    cleanup_temp_files
    
    validate_cleanup
    display_summary
}

# Execute main function
main "$@"