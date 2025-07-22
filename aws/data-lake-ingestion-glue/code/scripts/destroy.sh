#!/bin/bash

# =============================================================================
# AWS Data Lake Ingestion Pipeline Cleanup Script
# =============================================================================
# This script safely removes all resources created by the data lake pipeline:
# - AWS Glue workflows, jobs, crawlers, and databases
# - S3 bucket and all stored data
# - IAM roles and policies
# - CloudWatch alarms and SNS topics
# - Athena workgroups
# =============================================================================

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=false
VERBOSE=false
FORCE=false
SKIP_CONFIRMATION=false

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() {
    log "INFO" "${BLUE}$*${NC}"
}

success() {
    log "SUCCESS" "${GREEN}✅ $*${NC}"
}

warning() {
    log "WARNING" "${YELLOW}⚠️  $*${NC}"
}

error() {
    log "ERROR" "${RED}❌ $*${NC}"
}

fatal() {
    error "$*"
    exit 1
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy AWS Data Lake Ingestion Pipeline resources

OPTIONS:
    -d, --dry-run       Show what would be destroyed without making changes
    -v, --verbose       Enable verbose output
    -h, --help          Show this help message
    -f, --force         Force deletion without confirmation prompts
    -y, --yes           Skip confirmation prompts (same as --force)
    -r, --region        Specify AWS region (default: from AWS CLI config)
    -p, --prefix        Resource name prefix to identify resources to delete

EXAMPLES:
    $0 --dry-run
    $0 --verbose --force
    $0 --region us-west-2 --prefix mycompany

WARNING: This script will permanently delete all pipeline resources and data!

EOF
}

confirm_action() {
    if [[ "${SKIP_CONFIRMATION}" == "true" ]]; then
        return 0
    fi

    local message="$1"
    local default="${2:-n}"
    
    echo -e "${YELLOW}${message}${NC}"
    if [[ "${default}" == "y" ]]; then
        read -p "Continue? [Y/n]: " -n 1 -r
    else
        read -p "Continue? [y/N]: " -n 1 -r
    fi
    echo
    
    if [[ "${default}" == "y" ]]; then
        [[ $REPLY =~ ^[Nn]$ ]] && return 1 || return 0
    else
        [[ $REPLY =~ ^[Yy]$ ]] && return 0 || return 1
    fi
}

# =============================================================================
# Prerequisites Checking
# =============================================================================

check_prerequisites() {
    info "Checking prerequisites..."

    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        fatal "AWS CLI is not installed. Please install it first."
    fi

    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: ${aws_version}"

    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        fatal "AWS credentials not configured. Please run 'aws configure' first."
    fi

    # Get current user info
    local caller_identity=$(aws sts get-caller-identity)
    local account_id=$(echo "${caller_identity}" | jq -r '.Account')
    local user_arn=$(echo "${caller_identity}" | jq -r '.Arn')
    
    info "AWS Account ID: ${account_id}"
    info "User ARN: ${user_arn}"

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        fatal "jq is not installed. Please install it for JSON processing."
    fi

    success "Prerequisites check completed"
}

# =============================================================================
# Environment Discovery
# =============================================================================

discover_resources() {
    info "Discovering AWS Data Lake Pipeline resources..."

    # Set AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            export AWS_REGION="us-east-1"
            warning "No region configured, defaulting to us-east-1"
        fi
    fi

    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    # If prefix not provided, attempt to discover from existing resources
    if [[ -z "${RESOURCE_PREFIX:-}" ]]; then
        discover_resource_prefix
    fi

    # Set resource names based on prefix
    if [[ -n "${RESOURCE_PREFIX:-}" ]]; then
        export GLUE_DATABASE_NAME="${RESOURCE_PREFIX}-catalog"
        export S3_BUCKET_NAME="${RESOURCE_PREFIX}-pipeline"
        export GLUE_ROLE_NAME="GlueDataLakeRole-${RESOURCE_PREFIX}"
        export CRAWLER_NAME="${RESOURCE_PREFIX}-crawler"
        export ETL_JOB_NAME="${RESOURCE_PREFIX}-etl-job"
        export WORKFLOW_NAME="${RESOURCE_PREFIX}-workflow"
        export SNS_TOPIC_NAME="DataLakeAlerts-${RESOURCE_PREFIX}"
        export ATHENA_WORKGROUP="DataLakeWorkgroup-${RESOURCE_PREFIX}"

        info "Using resource prefix: ${RESOURCE_PREFIX}"
    else
        fatal "Could not discover resource prefix. Please specify with --prefix option."
    fi

    # Validate resources exist
    validate_resources_exist

    success "Resource discovery completed"
}

discover_resource_prefix() {
    info "Attempting to discover resource prefix from existing resources..."

    # Look for Glue databases that might belong to our pipeline
    local databases=$(aws glue get-databases --query 'DatabaseList[?contains(Name, `catalog`)].Name' --output text)
    
    for db in ${databases}; do
        if [[ "${db}" =~ (.+)-catalog$ ]]; then
            local potential_prefix="${BASH_REMATCH[1]}"
            
            # Check if corresponding S3 bucket exists
            if aws s3 ls "s3://${potential_prefix}-pipeline" &> /dev/null; then
                export RESOURCE_PREFIX="${potential_prefix}"
                info "Discovered resource prefix: ${RESOURCE_PREFIX}"
                return 0
            fi
        fi
    done

    # Look for S3 buckets that might belong to our pipeline
    local buckets=$(aws s3 ls | grep -o '[^ ]*-pipeline$' | sed 's/-pipeline$//' || true)
    
    for bucket_prefix in ${buckets}; do
        # Check if corresponding Glue database exists
        if aws glue get-database --name "${bucket_prefix}-catalog" &> /dev/null; then
            export RESOURCE_PREFIX="${bucket_prefix}"
            info "Discovered resource prefix: ${RESOURCE_PREFIX}"
            return 0
        fi
    done

    warning "Could not automatically discover resource prefix"
}

validate_resources_exist() {
    info "Validating that pipeline resources exist..."

    local found_resources=()
    local missing_resources=()

    # Check S3 bucket
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        found_resources+=("S3 Bucket: ${S3_BUCKET_NAME}")
    else
        missing_resources+=("S3 Bucket: ${S3_BUCKET_NAME}")
    fi

    # Check Glue database
    if aws glue get-database --name "${GLUE_DATABASE_NAME}" &> /dev/null; then
        found_resources+=("Glue Database: ${GLUE_DATABASE_NAME}")
    else
        missing_resources+=("Glue Database: ${GLUE_DATABASE_NAME}")
    fi

    # Check Glue crawler
    if aws glue get-crawler --name "${CRAWLER_NAME}" &> /dev/null; then
        found_resources+=("Glue Crawler: ${CRAWLER_NAME}")
    else
        missing_resources+=("Glue Crawler: ${CRAWLER_NAME}")
    fi

    # Check Glue job
    if aws glue get-job --job-name "${ETL_JOB_NAME}" &> /dev/null; then
        found_resources+=("Glue ETL Job: ${ETL_JOB_NAME}")
    else
        missing_resources+=("Glue ETL Job: ${ETL_JOB_NAME}")
    fi

    # Check IAM role
    if aws iam get-role --role-name "${GLUE_ROLE_NAME}" &> /dev/null; then
        found_resources+=("IAM Role: ${GLUE_ROLE_NAME}")
    else
        missing_resources+=("IAM Role: ${GLUE_ROLE_NAME}")
    fi

    # Display findings
    if [[ ${#found_resources[@]} -gt 0 ]]; then
        info "Found pipeline resources:"
        for resource in "${found_resources[@]}"; do
            info "  - ${resource}"
        done
    fi

    if [[ ${#missing_resources[@]} -gt 0 ]]; then
        warning "Missing pipeline resources (will be skipped):"
        for resource in "${missing_resources[@]}"; do
            warning "  - ${resource}"
        done
    fi

    if [[ ${#found_resources[@]} -eq 0 ]]; then
        fatal "No pipeline resources found. Check the prefix or resource names."
    fi

    success "Resource validation completed"
}

# =============================================================================
# Resource Deletion Functions
# =============================================================================

stop_active_operations() {
    info "Stopping active Glue operations..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would stop active Glue operations"
        return 0
    fi

    # Stop workflow runs
    if aws glue get-workflow --name "${WORKFLOW_NAME}" &> /dev/null; then
        local workflow_runs=$(aws glue get-workflow-runs --name "${WORKFLOW_NAME}" \
            --query 'Runs[?WorkflowRunProperties.Status==`RUNNING`].WorkflowRunId' --output text)
        
        for run_id in ${workflow_runs}; do
            info "Stopping workflow run: ${run_id}"
            aws glue stop-workflow-run --name "${WORKFLOW_NAME}" --run-id "${run_id}" || true
        done
    fi

    # Stop running ETL jobs
    if aws glue get-job --job-name "${ETL_JOB_NAME}" &> /dev/null; then
        local job_runs=$(aws glue get-job-runs --job-name "${ETL_JOB_NAME}" \
            --query 'JobRuns[?JobRunState==`RUNNING`].Id' --output text)
        
        for run_id in ${job_runs}; do
            info "Stopping job run: ${run_id}"
            aws glue batch-stop-job-run --job-name "${ETL_JOB_NAME}" --job-run-ids "${run_id}" || true
        done
    fi

    # Stop running crawlers
    if aws glue get-crawler --name "${CRAWLER_NAME}" &> /dev/null; then
        local crawler_state=$(aws glue get-crawler --name "${CRAWLER_NAME}" \
            --query 'Crawler.State' --output text)
        
        if [[ "${crawler_state}" == "RUNNING" ]]; then
            info "Stopping crawler: ${CRAWLER_NAME}"
            aws glue stop-crawler --name "${CRAWLER_NAME}" || true
            
            # Wait for crawler to stop
            local max_wait=300  # 5 minutes
            local wait_time=0
            
            while [[ ${wait_time} -lt ${max_wait} ]]; do
                local state=$(aws glue get-crawler --name "${CRAWLER_NAME}" \
                    --query 'Crawler.State' --output text)
                
                if [[ "${state}" != "STOPPING" ]]; then
                    break
                fi
                
                sleep 10
                wait_time=$((wait_time + 10))
            done
        fi
    fi

    success "Active operations stopped"
}

delete_glue_workflow() {
    info "Deleting Glue workflow and triggers..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would delete Glue workflow: ${WORKFLOW_NAME}"
        return 0
    fi

    if ! aws glue get-workflow --name "${WORKFLOW_NAME}" &> /dev/null; then
        warning "Workflow ${WORKFLOW_NAME} does not exist"
        return 0
    fi

    # Delete triggers first
    local triggers=$(aws glue get-triggers --workflow-name "${WORKFLOW_NAME}" \
        --query 'Triggers[].Name' --output text)
    
    for trigger in ${triggers}; do
        info "Deleting trigger: ${trigger}"
        aws glue delete-trigger --name "${trigger}" || warning "Failed to delete trigger: ${trigger}"
    done

    # Delete workflow
    aws glue delete-workflow --name "${WORKFLOW_NAME}"

    success "Glue workflow deleted: ${WORKFLOW_NAME}"
}

delete_glue_job() {
    info "Deleting Glue ETL job..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would delete Glue job: ${ETL_JOB_NAME}"
        return 0
    fi

    if ! aws glue get-job --job-name "${ETL_JOB_NAME}" &> /dev/null; then
        warning "ETL job ${ETL_JOB_NAME} does not exist"
        return 0
    fi

    aws glue delete-job --job-name "${ETL_JOB_NAME}"

    success "Glue ETL job deleted: ${ETL_JOB_NAME}"
}

delete_glue_crawler() {
    info "Deleting Glue crawler..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would delete Glue crawler: ${CRAWLER_NAME}"
        return 0
    fi

    if ! aws glue get-crawler --name "${CRAWLER_NAME}" &> /dev/null; then
        warning "Crawler ${CRAWLER_NAME} does not exist"
        return 0
    fi

    aws glue delete-crawler --name "${CRAWLER_NAME}"

    success "Glue crawler deleted: ${CRAWLER_NAME}"
}

delete_glue_database() {
    info "Deleting Glue database and tables..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would delete Glue database: ${GLUE_DATABASE_NAME}"
        return 0
    fi

    if ! aws glue get-database --name "${GLUE_DATABASE_NAME}" &> /dev/null; then
        warning "Database ${GLUE_DATABASE_NAME} does not exist"
        return 0
    fi

    # Delete all tables first
    local tables=$(aws glue get-tables --database-name "${GLUE_DATABASE_NAME}" \
        --query 'TableList[].Name' --output text)
    
    for table in ${tables}; do
        info "Deleting table: ${table}"
        aws glue delete-table --database-name "${GLUE_DATABASE_NAME}" --name "${table}" || \
            warning "Failed to delete table: ${table}"
    done

    # Delete database
    aws glue delete-database --name "${GLUE_DATABASE_NAME}"

    success "Glue database deleted: ${GLUE_DATABASE_NAME}"
}

delete_s3_bucket() {
    info "Deleting S3 bucket and all contents..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would delete S3 bucket: ${S3_BUCKET_NAME}"
        return 0
    fi

    if ! aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        warning "S3 bucket ${S3_BUCKET_NAME} does not exist"
        return 0
    fi

    # Show bucket contents before deletion
    info "S3 bucket contents:"
    aws s3 ls "s3://${S3_BUCKET_NAME}" --recursive --human-readable --summarize || true

    if ! confirm_action "⚠️  This will permanently delete ALL data in S3 bucket: ${S3_BUCKET_NAME}"; then
        warning "Skipping S3 bucket deletion"
        return 0
    fi

    # Delete all objects and versions
    info "Deleting all objects in bucket..."
    aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive

    # Delete incomplete multipart uploads
    aws s3api list-multipart-uploads --bucket "${S3_BUCKET_NAME}" \
        --query 'Uploads[].{Key:Key,UploadId:UploadId}' --output text | \
    while read -r key upload_id; do
        if [[ -n "${key}" && -n "${upload_id}" ]]; then
            aws s3api abort-multipart-upload --bucket "${S3_BUCKET_NAME}" \
                --key "${key}" --upload-id "${upload_id}" || true
        fi
    done

    # Delete bucket
    aws s3 rb "s3://${S3_BUCKET_NAME}"

    success "S3 bucket deleted: ${S3_BUCKET_NAME}"
}

delete_iam_role() {
    info "Deleting IAM role and policies..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would delete IAM role: ${GLUE_ROLE_NAME}"
        return 0
    fi

    if ! aws iam get-role --role-name "${GLUE_ROLE_NAME}" &> /dev/null; then
        warning "IAM role ${GLUE_ROLE_NAME} does not exist"
        return 0
    fi

    # Detach managed policies
    local attached_policies=$(aws iam list-attached-role-policies --role-name "${GLUE_ROLE_NAME}" \
        --query 'AttachedPolicies[].PolicyArn' --output text)
    
    for policy_arn in ${attached_policies}; do
        info "Detaching policy: ${policy_arn}"
        aws iam detach-role-policy --role-name "${GLUE_ROLE_NAME}" --policy-arn "${policy_arn}" || \
            warning "Failed to detach policy: ${policy_arn}"
    done

    # Delete inline policies
    local inline_policies=$(aws iam list-role-policies --role-name "${GLUE_ROLE_NAME}" \
        --query 'PolicyNames' --output text)
    
    for policy_name in ${inline_policies}; do
        info "Deleting inline policy: ${policy_name}"
        aws iam delete-role-policy --role-name "${GLUE_ROLE_NAME}" --policy-name "${policy_name}" || \
            warning "Failed to delete inline policy: ${policy_name}"
    done

    # Delete role
    aws iam delete-role --role-name "${GLUE_ROLE_NAME}"

    success "IAM role deleted: ${GLUE_ROLE_NAME}"
}

delete_cloudwatch_alarms() {
    info "Deleting CloudWatch alarms..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would delete CloudWatch alarms"
        return 0
    fi

    local alarm_names=(
        "GlueJobFailure-${ETL_JOB_NAME}"
        "GlueCrawlerFailure-${CRAWLER_NAME}"
    )

    for alarm_name in "${alarm_names[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "${alarm_name}" --query 'MetricAlarms[0]' --output text &> /dev/null; then
            info "Deleting alarm: ${alarm_name}"
            aws cloudwatch delete-alarms --alarm-names "${alarm_name}" || \
                warning "Failed to delete alarm: ${alarm_name}"
        else
            warning "Alarm ${alarm_name} does not exist"
        fi
    done

    success "CloudWatch alarms deleted"
}

delete_sns_topic() {
    info "Deleting SNS topic..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would delete SNS topic: ${SNS_TOPIC_NAME}"
        return 0
    fi

    # Find topic ARN
    local topic_arn=$(aws sns list-topics --query "Topics[?ends_with(TopicArn, ':${SNS_TOPIC_NAME}')].TopicArn" --output text)
    
    if [[ -n "${topic_arn}" ]]; then
        info "Deleting SNS topic: ${topic_arn}"
        aws sns delete-topic --topic-arn "${topic_arn}"
        success "SNS topic deleted: ${SNS_TOPIC_NAME}"
    else
        warning "SNS topic ${SNS_TOPIC_NAME} does not exist"
    fi
}

delete_athena_workgroup() {
    info "Deleting Athena workgroup..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would delete Athena workgroup: ${ATHENA_WORKGROUP}"
        return 0
    fi

    if aws athena get-work-group --work-group "${ATHENA_WORKGROUP}" &> /dev/null; then
        # Cancel any running queries first
        local query_executions=$(aws athena list-query-executions --work-group "${ATHENA_WORKGROUP}" \
            --query 'QueryExecutionIds[0:10]' --output text)
        
        for query_id in ${query_executions}; do
            local status=$(aws athena get-query-execution --query-execution-id "${query_id}" \
                --query 'QueryExecution.Status.State' --output text 2>/dev/null || echo "UNKNOWN")
            
            if [[ "${status}" == "RUNNING" || "${status}" == "QUEUED" ]]; then
                info "Cancelling query: ${query_id}"
                aws athena stop-query-execution --query-execution-id "${query_id}" || true
            fi
        done

        aws athena delete-work-group --work-group "${ATHENA_WORKGROUP}" --recursive-delete-option
        success "Athena workgroup deleted: ${ATHENA_WORKGROUP}"
    else
        warning "Athena workgroup ${ATHENA_WORKGROUP} does not exist"
    fi
}

delete_data_quality_rules() {
    info "Deleting data quality rules..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY-RUN] Would delete data quality rules"
        return 0
    fi

    # List and delete data quality rulesets
    local rulesets=$(aws glue list-data-quality-rulesets \
        --query 'Rulesets[?contains(Name, `DataLakeQualityRules`)].Name' --output text 2>/dev/null || true)
    
    for ruleset in ${rulesets}; do
        info "Deleting data quality ruleset: ${ruleset}"
        aws glue delete-data-quality-ruleset --name "${ruleset}" || \
            warning "Failed to delete ruleset: ${ruleset}"
    done

    if [[ -z "${rulesets}" ]]; then
        warning "No data quality rules found"
    else
        success "Data quality rules deleted"
    fi
}

# =============================================================================
# Main Cleanup Function
# =============================================================================

cleanup_pipeline() {
    info "Starting AWS Data Lake Ingestion Pipeline cleanup..."

    # Show final warning
    if ! confirm_action "⚠️  WARNING: This will permanently delete ALL pipeline resources and data!"; then
        info "Cleanup cancelled by user"
        exit 0
    fi

    # Cleanup resources in reverse dependency order
    stop_active_operations
    delete_glue_workflow
    delete_glue_job
    delete_glue_crawler
    delete_data_quality_rules
    delete_glue_database
    delete_cloudwatch_alarms
    delete_sns_topic
    delete_athena_workgroup
    delete_iam_role
    delete_s3_bucket

    success "Pipeline cleanup completed successfully!"
    
    # Display summary
    cat << EOF

=============================================================================
AWS Data Lake Ingestion Pipeline - Cleanup Summary
=============================================================================

Deleted Resources:
- S3 Bucket: ${S3_BUCKET_NAME}
- Glue Database: ${GLUE_DATABASE_NAME}
- Glue Crawler: ${CRAWLER_NAME}
- Glue ETL Job: ${ETL_JOB_NAME}
- Glue Workflow: ${WORKFLOW_NAME}
- IAM Role: ${GLUE_ROLE_NAME}
- SNS Topic: ${SNS_TOPIC_NAME}
- Athena Workgroup: ${ATHENA_WORKGROUP}
- CloudWatch Alarms and Data Quality Rules

All pipeline resources have been successfully removed.
Log file: ${LOG_FILE}
=============================================================================

EOF
}

# =============================================================================
# Command Line Argument Parsing
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -f|--force|-y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -r|--region)
                export AWS_REGION="$2"
                shift 2
                ;;
            -p|--prefix)
                export RESOURCE_PREFIX="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    info "AWS Data Lake Ingestion Pipeline Cleanup Script"
    info "==============================================="
    
    parse_arguments "$@"
    
    if [[ "${VERBOSE}" == "true" ]]; then
        set -x
    fi
    
    check_prerequisites
    discover_resources
    cleanup_pipeline
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "Dry-run completed. No resources were deleted."
    fi
}

# Execute main function with all arguments
main "$@"