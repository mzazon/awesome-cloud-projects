#!/bin/bash

# AWS Glue Workflows Data Pipeline Orchestration - Cleanup Script
# This script destroys all AWS resources created by the deployment script
# Use with caution - this will permanently delete all resources

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Cleanup function for script interruption
cleanup() {
    log_warning "Cleanup script interrupted. Some resources may remain."
    exit 1
}

# Trap cleanup function
trap cleanup SIGINT SIGTERM

# Function to check if a command exists
check_command() {
    local command="$1"
    if ! command -v "$command" &> /dev/null; then
        log_error "Command '$command' not found. Please install it and try again."
        exit 1
    fi
}

# Function to check AWS CLI configuration
check_aws_cli() {
    log_info "Checking AWS CLI configuration..."
    
    # Check if AWS CLI is installed
    check_command "aws"
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        log_error "Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    
    # Get account and region information
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=$(aws configure get region)
    
    if [[ -z "${AWS_REGION}" ]]; then
        log_error "AWS region is not configured. Please set a default region."
        exit 1
    fi
    
    log_success "AWS CLI configured - Account: ${AWS_ACCOUNT_ID}, Region: ${AWS_REGION}"
}

# Function to load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ ! -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        log_error "Deployment state file not found: ${DEPLOYMENT_STATE_FILE}"
        log_error "Cannot proceed without deployment state information."
        log_error "If you know the resource names, you can manually set them or run cleanup manually."
        exit 1
    fi
    
    # Source the deployment state file
    source "${DEPLOYMENT_STATE_FILE}"
    
    # Verify required variables are set
    local required_vars=(
        "AWS_ACCOUNT_ID"
        "AWS_REGION"
        "RANDOM_SUFFIX"
        "WORKFLOW_NAME"
        "S3_BUCKET_RAW"
        "S3_BUCKET_PROCESSED"
        "GLUE_ROLE_NAME"
        "DATABASE_NAME"
        "SOURCE_CRAWLER_NAME"
        "TARGET_CRAWLER_NAME"
        "ETL_JOB_NAME"
        "SCHEDULE_TRIGGER_NAME"
        "CRAWLER_SUCCESS_TRIGGER_NAME"
        "JOB_SUCCESS_TRIGGER_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var is not set in deployment state file."
            exit 1
        fi
    done
    
    log_success "Deployment state loaded successfully"
    log_info "Resources to be destroyed:"
    log_info "  • Workflow: ${WORKFLOW_NAME}"
    log_info "  • S3 Buckets: ${S3_BUCKET_RAW}, ${S3_BUCKET_PROCESSED}"
    log_info "  • IAM Role: ${GLUE_ROLE_NAME}"
    log_info "  • Database: ${DATABASE_NAME}"
    log_info "  • Crawlers: ${SOURCE_CRAWLER_NAME}, ${TARGET_CRAWLER_NAME}"
    log_info "  • ETL Job: ${ETL_JOB_NAME}"
    log_info "  • Triggers: ${SCHEDULE_TRIGGER_NAME}, ${CRAWLER_SUCCESS_TRIGGER_NAME}, ${JOB_SUCCESS_TRIGGER_NAME}"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo -e "${RED}WARNING: This will permanently delete all AWS resources created by the deployment script.${NC}"
    echo -e "${RED}This action cannot be undone.${NC}"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
    
    echo ""
    read -p "Please type 'DELETE' to confirm: " -r
    if [[ $REPLY != "DELETE" ]]; then
        log_info "Destruction cancelled - confirmation not matched."
        exit 0
    fi
    
    log_warning "Proceeding with resource destruction..."
}

# Function to stop running workflows
stop_workflows() {
    log_info "Stopping any running workflows..."
    
    # Get all running workflow runs
    local running_runs=$(aws glue get-workflow-runs \
        --name "${WORKFLOW_NAME}" \
        --query 'Runs[?Status==`RUNNING`].WorkflowRunId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${running_runs}" ]]; then
        for run_id in ${running_runs}; do
            log_info "Stopping workflow run: ${run_id}"
            aws glue stop-workflow-run \
                --name "${WORKFLOW_NAME}" \
                --run-id "${run_id}" 2>/dev/null || log_warning "Failed to stop workflow run: ${run_id}"
        done
        
        # Wait for workflows to stop
        log_info "Waiting for workflows to stop..."
        sleep 15
    else
        log_info "No running workflows found"
    fi
}

# Function to delete Glue triggers
delete_glue_triggers() {
    log_info "Deleting Glue triggers..."
    
    local triggers=(
        "${SCHEDULE_TRIGGER_NAME}"
        "${CRAWLER_SUCCESS_TRIGGER_NAME}"
        "${JOB_SUCCESS_TRIGGER_NAME}"
    )
    
    for trigger in "${triggers[@]}"; do
        if aws glue get-trigger --name "${trigger}" 2>/dev/null; then
            log_info "Deleting trigger: ${trigger}"
            aws glue delete-trigger --name "${trigger}" 2>/dev/null || log_warning "Failed to delete trigger: ${trigger}"
            log_success "Deleted trigger: ${trigger}"
        else
            log_info "Trigger not found: ${trigger}"
        fi
    done
}

# Function to delete Glue workflow
delete_glue_workflow() {
    log_info "Deleting Glue workflow..."
    
    if aws glue get-workflow --name "${WORKFLOW_NAME}" 2>/dev/null; then
        log_info "Deleting workflow: ${WORKFLOW_NAME}"
        aws glue delete-workflow --name "${WORKFLOW_NAME}" 2>/dev/null || log_warning "Failed to delete workflow: ${WORKFLOW_NAME}"
        log_success "Deleted workflow: ${WORKFLOW_NAME}"
    else
        log_info "Workflow not found: ${WORKFLOW_NAME}"
    fi
}

# Function to delete Glue job
delete_glue_job() {
    log_info "Deleting Glue job..."
    
    if aws glue get-job --job-name "${ETL_JOB_NAME}" 2>/dev/null; then
        log_info "Deleting job: ${ETL_JOB_NAME}"
        aws glue delete-job --job-name "${ETL_JOB_NAME}" 2>/dev/null || log_warning "Failed to delete job: ${ETL_JOB_NAME}"
        log_success "Deleted job: ${ETL_JOB_NAME}"
    else
        log_info "Job not found: ${ETL_JOB_NAME}"
    fi
}

# Function to delete Glue crawlers
delete_glue_crawlers() {
    log_info "Deleting Glue crawlers..."
    
    local crawlers=(
        "${SOURCE_CRAWLER_NAME}"
        "${TARGET_CRAWLER_NAME}"
    )
    
    for crawler in "${crawlers[@]}"; do
        if aws glue get-crawler --name "${crawler}" 2>/dev/null; then
            # Stop crawler if running
            local crawler_state=$(aws glue get-crawler --name "${crawler}" --query 'Crawler.State' --output text 2>/dev/null || echo "")
            if [[ "${crawler_state}" == "RUNNING" ]]; then
                log_info "Stopping crawler: ${crawler}"
                aws glue stop-crawler --name "${crawler}" 2>/dev/null || log_warning "Failed to stop crawler: ${crawler}"
                sleep 5
            fi
            
            log_info "Deleting crawler: ${crawler}"
            aws glue delete-crawler --name "${crawler}" 2>/dev/null || log_warning "Failed to delete crawler: ${crawler}"
            log_success "Deleted crawler: ${crawler}"
        else
            log_info "Crawler not found: ${crawler}"
        fi
    done
}

# Function to delete Glue database and tables
delete_glue_database() {
    log_info "Deleting Glue database and tables..."
    
    if aws glue get-database --name "${DATABASE_NAME}" 2>/dev/null; then
        # Delete tables first
        local tables=$(aws glue get-tables --database-name "${DATABASE_NAME}" --query 'TableList[].Name' --output text 2>/dev/null || echo "")
        
        if [[ -n "${tables}" ]]; then
            for table in ${tables}; do
                log_info "Deleting table: ${table}"
                aws glue delete-table --database-name "${DATABASE_NAME}" --name "${table}" 2>/dev/null || log_warning "Failed to delete table: ${table}"
                log_success "Deleted table: ${table}"
            done
        fi
        
        # Delete database
        log_info "Deleting database: ${DATABASE_NAME}"
        aws glue delete-database --name "${DATABASE_NAME}" 2>/dev/null || log_warning "Failed to delete database: ${DATABASE_NAME}"
        log_success "Deleted database: ${DATABASE_NAME}"
    else
        log_info "Database not found: ${DATABASE_NAME}"
    fi
}

# Function to delete IAM role
delete_iam_role() {
    log_info "Deleting IAM role..."
    
    if aws iam get-role --role-name "${GLUE_ROLE_NAME}" 2>/dev/null; then
        # Detach managed policies
        log_info "Detaching managed policies from role: ${GLUE_ROLE_NAME}"
        aws iam detach-role-policy \
            --role-name "${GLUE_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || log_warning "Failed to detach AWSGlueServiceRole policy"
        
        # Delete inline policies
        local inline_policies=$(aws iam list-role-policies --role-name "${GLUE_ROLE_NAME}" --query 'PolicyNames' --output text 2>/dev/null || echo "")
        if [[ -n "${inline_policies}" ]]; then
            for policy in ${inline_policies}; do
                log_info "Deleting inline policy: ${policy}"
                aws iam delete-role-policy --role-name "${GLUE_ROLE_NAME}" --policy-name "${policy}" 2>/dev/null || log_warning "Failed to delete inline policy: ${policy}"
            done
        fi
        
        # Delete role
        log_info "Deleting role: ${GLUE_ROLE_NAME}"
        aws iam delete-role --role-name "${GLUE_ROLE_NAME}" 2>/dev/null || log_warning "Failed to delete role: ${GLUE_ROLE_NAME}"
        log_success "Deleted role: ${GLUE_ROLE_NAME}"
    else
        log_info "Role not found: ${GLUE_ROLE_NAME}"
    fi
}

# Function to delete S3 buckets
delete_s3_buckets() {
    log_info "Deleting S3 buckets and their contents..."
    
    local buckets=(
        "${S3_BUCKET_RAW}"
        "${S3_BUCKET_PROCESSED}"
    )
    
    for bucket in "${buckets[@]}"; do
        if aws s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
            log_info "Deleting S3 bucket and contents: ${bucket}"
            
            # Delete all objects and versions
            aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || log_warning "Failed to delete some objects in bucket: ${bucket}"
            
            # Delete bucket
            aws s3 rb "s3://${bucket}" --force 2>/dev/null || log_warning "Failed to delete bucket: ${bucket}"
            log_success "Deleted S3 bucket: ${bucket}"
        else
            log_info "S3 bucket not found: ${bucket}"
        fi
    done
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/sample-data.csv"
        "${SCRIPT_DIR}/etl-script.py"
        "${SCRIPT_DIR}/glue-trust-policy.json"
        "${SCRIPT_DIR}/s3-access-policy.json"
        "${DEPLOYMENT_STATE_FILE}"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_success "Removed local file: ${file}"
        fi
    done
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local cleanup_successful=true
    
    # Check workflow
    if aws glue get-workflow --name "${WORKFLOW_NAME}" 2>/dev/null; then
        log_error "Workflow still exists: ${WORKFLOW_NAME}"
        cleanup_successful=false
    fi
    
    # Check S3 buckets
    if aws s3api head-bucket --bucket "${S3_BUCKET_RAW}" 2>/dev/null; then
        log_error "S3 bucket still exists: ${S3_BUCKET_RAW}"
        cleanup_successful=false
    fi
    
    if aws s3api head-bucket --bucket "${S3_BUCKET_PROCESSED}" 2>/dev/null; then
        log_error "S3 bucket still exists: ${S3_BUCKET_PROCESSED}"
        cleanup_successful=false
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${GLUE_ROLE_NAME}" 2>/dev/null; then
        log_error "IAM role still exists: ${GLUE_ROLE_NAME}"
        cleanup_successful=false
    fi
    
    # Check database
    if aws glue get-database --name "${DATABASE_NAME}" 2>/dev/null; then
        log_error "Glue database still exists: ${DATABASE_NAME}"
        cleanup_successful=false
    fi
    
    if [[ "${cleanup_successful}" == "true" ]]; then
        log_success "All resources have been successfully cleaned up"
    else
        log_warning "Some resources may still exist. Please check the AWS console and clean up manually if needed."
    fi
}

# Function to display cleanup summary
display_summary() {
    log_success "=== CLEANUP COMPLETED ==="
    echo ""
    echo "Cleaned up resources:"
    echo "  • Workflow: ${WORKFLOW_NAME}"
    echo "  • S3 Buckets: ${S3_BUCKET_RAW}, ${S3_BUCKET_PROCESSED}"
    echo "  • IAM Role: ${GLUE_ROLE_NAME}"
    echo "  • Glue Database: ${DATABASE_NAME}"
    echo "  • Crawlers: ${SOURCE_CRAWLER_NAME}, ${TARGET_CRAWLER_NAME}"
    echo "  • ETL Job: ${ETL_JOB_NAME}"
    echo "  • Triggers: ${SCHEDULE_TRIGGER_NAME}, ${CRAWLER_SUCCESS_TRIGGER_NAME}, ${JOB_SUCCESS_TRIGGER_NAME}"
    echo ""
    echo "Local files cleaned up:"
    echo "  • Deployment state file"
    echo "  • Temporary policy files"
    echo "  • ETL script file"
    echo ""
    echo "Log file available at: ${LOG_FILE}"
    echo ""
    echo "Please verify in the AWS console that all resources have been removed."
}

# Function to handle manual cleanup mode
manual_cleanup() {
    log_warning "Manual cleanup mode - you will need to provide resource names"
    echo ""
    echo "Please provide the resource names (press Enter to skip):"
    
    read -p "Workflow name: " WORKFLOW_NAME
    read -p "Raw data S3 bucket: " S3_BUCKET_RAW
    read -p "Processed data S3 bucket: " S3_BUCKET_PROCESSED
    read -p "IAM role name: " GLUE_ROLE_NAME
    read -p "Database name: " DATABASE_NAME
    read -p "Source crawler name: " SOURCE_CRAWLER_NAME
    read -p "Target crawler name: " TARGET_CRAWLER_NAME
    read -p "ETL job name: " ETL_JOB_NAME
    read -p "Schedule trigger name: " SCHEDULE_TRIGGER_NAME
    read -p "Crawler success trigger name: " CRAWLER_SUCCESS_TRIGGER_NAME
    read -p "Job success trigger name: " JOB_SUCCESS_TRIGGER_NAME
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log_info "Manual cleanup mode configured"
}

# Main cleanup function
main() {
    log_info "Starting AWS Glue Workflows cleanup..."
    log_info "Script directory: ${SCRIPT_DIR}"
    log_info "Log file: ${LOG_FILE}"
    
    # Check prerequisites
    check_aws_cli
    
    # Check if manual mode is requested
    if [[ "${1:-}" == "--manual" ]]; then
        manual_cleanup
    else
        # Load deployment state
        load_deployment_state
    fi
    
    # Confirm destruction
    confirm_destruction
    
    # Stop any running workflows
    stop_workflows
    
    # Delete resources in reverse order of creation
    delete_glue_triggers
    delete_glue_workflow
    delete_glue_job
    delete_glue_crawlers
    delete_glue_database
    delete_iam_role
    delete_s3_buckets
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_summary
    
    log_success "Cleanup completed successfully!"
}

# Check command line arguments
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [--manual]"
    echo ""
    echo "Options:"
    echo "  --manual    Run in manual mode (enter resource names manually)"
    echo "  --help      Show this help message"
    echo ""
    echo "This script will delete all AWS resources created by the deployment script."
    echo "Use with caution - this action cannot be undone."
    exit 0
fi

# Run main function
main "$@"