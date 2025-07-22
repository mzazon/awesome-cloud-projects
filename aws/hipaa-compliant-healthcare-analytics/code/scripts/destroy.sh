#!/bin/bash

# Healthcare Data Processing Pipelines with AWS HealthLake - Cleanup Script
# This script removes all resources created by the deployment script
# including HealthLake datastore, Lambda functions, EventBridge rules, and S3 buckets

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    echo -e "[${TIMESTAMP}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() { log "INFO" "${BLUE}$*${NC}"; }
log_warn() { log "WARN" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code ${exit_code}"
    log_error "Check ${LOG_FILE} for detailed error information"
    log_error "Some resources may still exist and incur charges"
    exit ${exit_code}
}

trap cleanup_on_error ERR

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -f, --force            Force deletion without confirmation prompts"
    echo "  -k, --keep-data        Keep S3 buckets and data (delete only compute resources)"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --force              # Delete all resources without prompts"
    echo "  $0 --keep-data          # Keep S3 buckets, delete other resources"
    exit 1
}

# Parse command line arguments
FORCE_DELETE=false
KEEP_DATA=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -k|--keep-data)
            KEEP_DATA=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        source "${SCRIPT_DIR}/.env"
        log_success "Environment variables loaded from .env file"
    else
        log_error "Environment file .env not found"
        log_error "Cannot proceed without resource information"
        log_info "If you know the resource names, you can manually create a .env file with:"
        log_info "AWS_REGION=your-region"
        log_info "DATASTORE_NAME=your-datastore-name"
        log_info "INPUT_BUCKET=your-input-bucket"
        log_info "OUTPUT_BUCKET=your-output-bucket"
        log_info "LAMBDA_PROCESSOR_NAME=your-processor-function"
        log_info "LAMBDA_ANALYTICS_NAME=your-analytics-function"
        log_info "IAM_ROLE_NAME=your-healthlake-role"
        log_info "LAMBDA_EXECUTION_ROLE=your-lambda-role"
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    log_info "Region: ${AWS_REGION:-unknown}"
    log_info "Account: ${AWS_ACCOUNT_ID:-unknown}"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warn "This will delete the following AWS resources:"
    log_warn "  - HealthLake Datastore: ${DATASTORE_NAME:-unknown}"
    
    if [[ "${KEEP_DATA}" == "false" ]]; then
        log_warn "  - S3 Buckets: ${INPUT_BUCKET:-unknown}, ${OUTPUT_BUCKET:-unknown}"
        log_warn "  - ALL DATA in these buckets will be permanently lost"
    fi
    
    log_warn "  - Lambda Functions: ${LAMBDA_PROCESSOR_NAME:-unknown}, ${LAMBDA_ANALYTICS_NAME:-unknown}"
    log_warn "  - EventBridge Rules and IAM Roles"
    log_warn ""
    log_warn "This action cannot be undone!"
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Stop active HealthLake jobs
stop_active_jobs() {
    log_info "Stopping active HealthLake jobs..."
    
    if [[ -z "${DATASTORE_ID:-}" ]]; then
        # Try to get datastore ID from name
        DATASTORE_ID=$(aws healthlake list-fhir-datastores \
            --query "DatastorePropertiesList[?DatastoreName=='${DATASTORE_NAME}'].DatastoreId" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -n "${DATASTORE_ID}" && "${DATASTORE_ID}" != "None" ]]; then
        # Cancel running import jobs
        IMPORT_JOBS=$(aws healthlake list-fhir-import-jobs \
            --datastore-id "${DATASTORE_ID}" \
            --query 'ImportJobPropertiesList[?JobStatus==`IN_PROGRESS`].JobId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${IMPORT_JOBS}" && "${IMPORT_JOBS}" != "None" ]]; then
            for job_id in ${IMPORT_JOBS}; do
                log_info "Cancelling import job: ${job_id}"
                aws healthlake cancel-fhir-import-job \
                    --datastore-id "${DATASTORE_ID}" \
                    --job-id "${job_id}" || true
            done
        fi
        
        # Cancel running export jobs
        EXPORT_JOBS=$(aws healthlake list-fhir-export-jobs \
            --datastore-id "${DATASTORE_ID}" \
            --query 'ExportJobPropertiesList[?JobStatus==`IN_PROGRESS`].JobId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${EXPORT_JOBS}" && "${EXPORT_JOBS}" != "None" ]]; then
            for job_id in ${EXPORT_JOBS}; do
                log_info "Cancelling export job: ${job_id}"
                aws healthlake cancel-fhir-export-job \
                    --datastore-id "${DATASTORE_ID}" \
                    --job-id "${job_id}" || true
            done
        fi
        
        log_success "Stopped active HealthLake jobs"
    else
        log_warn "Could not find HealthLake datastore to stop jobs"
    fi
}

# Remove EventBridge rules
remove_eventbridge_rules() {
    log_info "Removing EventBridge rules..."
    
    # Remove processor rule
    if aws events describe-rule --name "HealthLakeProcessorRule" &>/dev/null; then
        aws events remove-targets \
            --rule "HealthLakeProcessorRule" \
            --ids "1" 2>/dev/null || true
        
        aws events delete-rule \
            --name "HealthLakeProcessorRule" 2>/dev/null || true
        
        log_success "Removed HealthLakeProcessorRule"
    else
        log_warn "HealthLakeProcessorRule not found"
    fi
    
    # Remove analytics rule
    if aws events describe-rule --name "HealthLakeAnalyticsRule" &>/dev/null; then
        aws events remove-targets \
            --rule "HealthLakeAnalyticsRule" \
            --ids "1" 2>/dev/null || true
        
        aws events delete-rule \
            --name "HealthLakeAnalyticsRule" 2>/dev/null || true
        
        log_success "Removed HealthLakeAnalyticsRule"
    else
        log_warn "HealthLakeAnalyticsRule not found"
    fi
}

# Delete Lambda functions
delete_lambda_functions() {
    log_info "Deleting Lambda functions..."
    
    # Delete processor function
    if aws lambda get-function --function-name "${LAMBDA_PROCESSOR_NAME}" &>/dev/null; then
        aws lambda delete-function --function-name "${LAMBDA_PROCESSOR_NAME}"
        log_success "Deleted Lambda processor function: ${LAMBDA_PROCESSOR_NAME}"
    else
        log_warn "Lambda processor function not found: ${LAMBDA_PROCESSOR_NAME}"
    fi
    
    # Delete analytics function
    if aws lambda get-function --function-name "${LAMBDA_ANALYTICS_NAME}" &>/dev/null; then
        aws lambda delete-function --function-name "${LAMBDA_ANALYTICS_NAME}"
        log_success "Deleted Lambda analytics function: ${LAMBDA_ANALYTICS_NAME}"
    else
        log_warn "Lambda analytics function not found: ${LAMBDA_ANALYTICS_NAME}"
    fi
    
    # Delete Lambda execution role
    if aws iam get-role --role-name "${LAMBDA_EXECUTION_ROLE}" &>/dev/null; then
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "${LAMBDA_EXECUTION_ROLE}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
            2>/dev/null || true
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "${LAMBDA_EXECUTION_ROLE}" \
            --policy-name LambdaS3Access \
            2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "${LAMBDA_EXECUTION_ROLE}"
        log_success "Deleted Lambda execution role: ${LAMBDA_EXECUTION_ROLE}"
    else
        log_warn "Lambda execution role not found: ${LAMBDA_EXECUTION_ROLE}"
    fi
}

# Delete HealthLake datastore
delete_healthlake_datastore() {
    log_info "Deleting HealthLake datastore..."
    
    if [[ -z "${DATASTORE_ID:-}" ]]; then
        # Try to get datastore ID from name
        DATASTORE_ID=$(aws healthlake list-fhir-datastores \
            --query "DatastorePropertiesList[?DatastoreName=='${DATASTORE_NAME}'].DatastoreId" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -n "${DATASTORE_ID}" && "${DATASTORE_ID}" != "None" ]]; then
        # Check current status
        DATASTORE_STATUS=$(aws healthlake describe-fhir-datastore \
            --datastore-id "${DATASTORE_ID}" \
            --query 'DatastoreProperties.DatastoreStatus' \
            --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "${DATASTORE_STATUS}" != "NOT_FOUND" ]]; then
            log_info "Current datastore status: ${DATASTORE_STATUS}"
            
            if [[ "${DATASTORE_STATUS}" == "ACTIVE" ]]; then
                aws healthlake delete-fhir-datastore --datastore-id "${DATASTORE_ID}"
                log_info "HealthLake datastore deletion initiated: ${DATASTORE_ID}"
                
                # Wait for deletion to complete (with timeout)
                log_info "Waiting for datastore deletion (this may take several minutes)..."
                TIMEOUT=1800  # 30 minutes
                ELAPSED=0
                
                while [[ $ELAPSED -lt $TIMEOUT ]]; do
                    DATASTORE_STATUS=$(aws healthlake describe-fhir-datastore \
                        --datastore-id "${DATASTORE_ID}" \
                        --query 'DatastoreProperties.DatastoreStatus' \
                        --output text 2>/dev/null || echo "DELETED")
                    
                    if [[ "${DATASTORE_STATUS}" == "DELETED" ]] || [[ "${DATASTORE_STATUS}" == "NOT_FOUND" ]]; then
                        log_success "HealthLake datastore deleted successfully"
                        break
                    elif [[ "${DATASTORE_STATUS}" == "DELETING" ]]; then
                        log_info "Datastore deletion in progress..."
                        sleep 30
                        ELAPSED=$((ELAPSED + 30))
                    else
                        log_error "Unexpected datastore status during deletion: ${DATASTORE_STATUS}"
                        break
                    fi
                done
                
                if [[ $ELAPSED -ge $TIMEOUT ]]; then
                    log_warn "Datastore deletion timeout reached. Check AWS console for status."
                fi
            else
                log_warn "Datastore is not in ACTIVE state, skipping deletion"
            fi
        else
            log_warn "HealthLake datastore not found: ${DATASTORE_ID}"
        fi
    else
        log_warn "Could not find HealthLake datastore with name: ${DATASTORE_NAME}"
    fi
}

# Clean up S3 buckets
cleanup_s3_buckets() {
    if [[ "${KEEP_DATA}" == "true" ]]; then
        log_info "Skipping S3 bucket deletion (--keep-data flag specified)"
        return
    fi
    
    log_info "Cleaning up S3 buckets..."
    
    # Delete input bucket
    if aws s3api head-bucket --bucket "${INPUT_BUCKET}" 2>/dev/null; then
        log_info "Emptying input bucket: ${INPUT_BUCKET}"
        aws s3 rm "s3://${INPUT_BUCKET}" --recursive 2>/dev/null || true
        
        # Remove all versions and delete markers (for versioned bucket)
        aws s3api list-object-versions \
            --bucket "${INPUT_BUCKET}" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output text 2>/dev/null | while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object \
                    --bucket "${INPUT_BUCKET}" \
                    --key "$key" \
                    --version-id "$version_id" 2>/dev/null || true
            fi
        done
        
        # Remove delete markers
        aws s3api list-object-versions \
            --bucket "${INPUT_BUCKET}" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output text 2>/dev/null | while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object \
                    --bucket "${INPUT_BUCKET}" \
                    --key "$key" \
                    --version-id "$version_id" 2>/dev/null || true
            fi
        done
        
        aws s3 rb "s3://${INPUT_BUCKET}" 2>/dev/null || true
        log_success "Deleted input bucket: ${INPUT_BUCKET}"
    else
        log_warn "Input bucket not found: ${INPUT_BUCKET}"
    fi
    
    # Delete output bucket
    if aws s3api head-bucket --bucket "${OUTPUT_BUCKET}" 2>/dev/null; then
        log_info "Emptying output bucket: ${OUTPUT_BUCKET}"
        aws s3 rm "s3://${OUTPUT_BUCKET}" --recursive 2>/dev/null || true
        
        # Remove all versions and delete markers (for versioned bucket)
        aws s3api list-object-versions \
            --bucket "${OUTPUT_BUCKET}" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output text 2>/dev/null | while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object \
                    --bucket "${OUTPUT_BUCKET}" \
                    --key "$key" \
                    --version-id "$version_id" 2>/dev/null || true
            fi
        done
        
        # Remove delete markers
        aws s3api list-object-versions \
            --bucket "${OUTPUT_BUCKET}" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output text 2>/dev/null | while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object \
                    --bucket "${OUTPUT_BUCKET}" \
                    --key "$key" \
                    --version-id "$version_id" 2>/dev/null || true
            fi
        done
        
        aws s3 rb "s3://${OUTPUT_BUCKET}" 2>/dev/null || true
        log_success "Deleted output bucket: ${OUTPUT_BUCKET}"
    else
        log_warn "Output bucket not found: ${OUTPUT_BUCKET}"
    fi
}

# Remove HealthLake IAM role
remove_healthlake_iam_role() {
    log_info "Removing HealthLake IAM role..."
    
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-name HealthLakeS3Access \
            2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "${IAM_ROLE_NAME}"
        log_success "Deleted HealthLake IAM role: ${IAM_ROLE_NAME}"
    else
        log_warn "HealthLake IAM role not found: ${IAM_ROLE_NAME}"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove temporary files
    rm -f "${SCRIPT_DIR}"/healthlake-trust-policy.json
    rm -f "${SCRIPT_DIR}"/healthlake-s3-policy.json
    rm -f "${SCRIPT_DIR}"/lambda-trust-policy.json
    rm -f "${SCRIPT_DIR}"/lambda-s3-policy.json
    rm -f "${SCRIPT_DIR}"/lambda-processor.py
    rm -f "${SCRIPT_DIR}"/lambda-processor.zip
    rm -f "${SCRIPT_DIR}"/lambda-analytics.py
    rm -f "${SCRIPT_DIR}"/lambda-analytics.zip
    rm -f "${SCRIPT_DIR}"/patient-sample.json
    
    # Remove environment file (ask for confirmation if not forced)
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        if [[ "${FORCE_DELETE}" == "true" ]]; then
            rm -f "${SCRIPT_DIR}/.env"
            log_success "Removed environment file"
        else
            read -p "Remove environment file (.env)? This will make re-running destroy difficult. (y/N): " -r
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -f "${SCRIPT_DIR}/.env"
                log_success "Removed environment file"
            else
                log_info "Keeping environment file for future use"
            fi
        fi
    fi
    
    log_success "Local cleanup completed"
}

# Verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local issues_found=false
    
    # Check HealthLake datastore
    if [[ -n "${DATASTORE_ID:-}" ]]; then
        DATASTORE_STATUS=$(aws healthlake describe-fhir-datastore \
            --datastore-id "${DATASTORE_ID}" \
            --query 'DatastoreProperties.DatastoreStatus' \
            --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "${DATASTORE_STATUS}" != "NOT_FOUND" && "${DATASTORE_STATUS}" != "DELETED" ]]; then
            log_warn "HealthLake datastore still exists with status: ${DATASTORE_STATUS}"
            issues_found=true
        fi
    fi
    
    # Check Lambda functions
    if aws lambda get-function --function-name "${LAMBDA_PROCESSOR_NAME}" &>/dev/null; then
        log_warn "Lambda processor function still exists: ${LAMBDA_PROCESSOR_NAME}"
        issues_found=true
    fi
    
    if aws lambda get-function --function-name "${LAMBDA_ANALYTICS_NAME}" &>/dev/null; then
        log_warn "Lambda analytics function still exists: ${LAMBDA_ANALYTICS_NAME}"
        issues_found=true
    fi
    
    # Check S3 buckets (only if not keeping data)
    if [[ "${KEEP_DATA}" == "false" ]]; then
        if aws s3api head-bucket --bucket "${INPUT_BUCKET}" 2>/dev/null; then
            log_warn "Input S3 bucket still exists: ${INPUT_BUCKET}"
            issues_found=true
        fi
        
        if aws s3api head-bucket --bucket "${OUTPUT_BUCKET}" 2>/dev/null; then
            log_warn "Output S3 bucket still exists: ${OUTPUT_BUCKET}"
            issues_found=true
        fi
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        log_warn "HealthLake IAM role still exists: ${IAM_ROLE_NAME}"
        issues_found=true
    fi
    
    if aws iam get-role --role-name "${LAMBDA_EXECUTION_ROLE}" &>/dev/null; then
        log_warn "Lambda execution role still exists: ${LAMBDA_EXECUTION_ROLE}"
        issues_found=true
    fi
    
    if [[ "${issues_found}" == "true" ]]; then
        log_warn "Some resources may still exist. Check AWS console and billing."
        log_warn "You may need to manually delete remaining resources."
    else
        log_success "All resources appear to be successfully deleted"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Healthcare Data Processing Pipeline cleanup..."
    log_info "Cleanup log: ${LOG_FILE}"
    
    load_environment
    confirm_deletion
    stop_active_jobs
    remove_eventbridge_rules
    delete_lambda_functions
    delete_healthlake_datastore
    cleanup_s3_buckets
    remove_healthlake_iam_role
    cleanup_local_files
    verify_deletion
    
    log_success "Healthcare Data Processing Pipeline cleanup completed!"
    
    if [[ "${KEEP_DATA}" == "true" ]]; then
        log_info "S3 buckets were preserved as requested"
        log_info "Remember to manually delete them when no longer needed:"
        log_info "  aws s3 rb s3://${INPUT_BUCKET} --force"
        log_info "  aws s3 rb s3://${OUTPUT_BUCKET} --force"
    fi
    
    log_info "Cleanup completed. Check your AWS billing to ensure no unexpected charges."
}

# Run main function
main "$@"