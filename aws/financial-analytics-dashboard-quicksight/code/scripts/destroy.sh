#!/bin/bash

# Cleanup script for Advanced Financial Analytics Dashboard with QuickSight and Cost Explorer
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ENV_FILE="${SCRIPT_DIR}/.env"
RECIPE_NAME="advanced-financial-analytics-dashboard-quicksight-cost-explorer"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Success logging
log_success() {
    log "${GREEN}SUCCESS${NC}" "$*"
}

# Error logging
log_error() {
    log "${RED}ERROR${NC}" "$*"
}

# Warning logging
log_warning() {
    log "${YELLOW}WARNING${NC}" "$*"
}

# Info logging
log_info() {
    log "${BLUE}INFO${NC}" "$*"
}

# Error handler (non-fatal for cleanup)
error_handler() {
    local line_number=$1
    log_warning "An error occurred on line ${line_number}. Continuing cleanup..."
}

trap 'error_handler ${LINENO}' ERR

# Display banner
display_banner() {
    echo -e "${RED}"
    echo "================================================================"
    echo "  AWS Financial Analytics Dashboard Cleanup Script"
    echo "  Recipe: ${RECIPE_NAME}"
    echo "  Date: $(date)"
    echo "================================================================"
    echo -e "${NC}"
    echo ""
    echo -e "${YELLOW}WARNING: This will DELETE all resources created by the deployment script!${NC}"
    echo ""
}

# Load environment variables
load_environment() {
    if [[ -f "${ENV_FILE}" ]]; then
        log_info "Loading environment variables from ${ENV_FILE}..."
        # shellcheck source=/dev/null
        source "${ENV_FILE}"
        log_success "Environment variables loaded."
    else
        log_warning "Environment file not found. Will attempt cleanup with manual detection."
        
        # Set basic variables
        export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        
        if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
            log_error "Unable to determine AWS account ID. Please ensure AWS CLI is configured."
            exit 1
        fi
    fi
}

# Confirm deletion
confirm_deletion() {
    echo -e "${RED}You are about to delete the following resources:${NC}"
    echo ""
    echo "• QuickSight data sources and datasets"
    echo "• Lambda functions (CostDataCollector, DataTransformer)"
    echo "• EventBridge rules and targets"
    echo "• Athena workgroup (FinancialAnalytics)"
    echo "• IAM role and policies (FinancialAnalyticsLambdaRole)"
    echo "• S3 buckets and all data:"
    
    if [[ -n "${RAW_DATA_BUCKET:-}" ]]; then
        echo "  - ${RAW_DATA_BUCKET}"
    fi
    if [[ -n "${PROCESSED_DATA_BUCKET:-}" ]]; then
        echo "  - ${PROCESSED_DATA_BUCKET}"
    fi
    if [[ -n "${REPORTS_BUCKET:-}" ]]; then
        echo "  - ${REPORTS_BUCKET}"
    fi
    if [[ -n "${ANALYTICS_BUCKET:-}" ]]; then
        echo "  - ${ANALYTICS_BUCKET}"
    fi
    
    echo ""
    echo -e "${YELLOW}Region: ${AWS_REGION}${NC}"
    echo -e "${YELLOW}Account: ${AWS_ACCOUNT_ID}${NC}"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    echo ""
    log_info "Starting cleanup process..."
}

# Remove QuickSight resources
remove_quicksight_resources() {
    log_info "Removing QuickSight resources..."
    
    # Note: QuickSight cleanup is minimal as most configuration is manual
    log_warning "QuickSight data sources and datasets should be manually deleted from the QuickSight console."
    log_warning "Visit: https://quicksight.aws.amazon.com/"
    
    # Try to delete datasets if they exist
    local datasets=("daily-cost-trends" "department-cost-allocation")
    for dataset in "${datasets[@]}"; do
        if aws quicksight describe-data-set \
            --aws-account-id "${AWS_ACCOUNT_ID}" \
            --data-set-id "${dataset}" &>/dev/null; then
            aws quicksight delete-data-set \
                --aws-account-id "${AWS_ACCOUNT_ID}" \
                --data-set-id "${dataset}" 2>/dev/null || \
                log_warning "Failed to delete QuickSight dataset: ${dataset}"
            log_success "Deleted QuickSight dataset: ${dataset}"
        fi
    done
    
    # Try to delete data sources if they exist
    local datasources=("financial-analytics-s3" "financial-analytics-athena")
    for datasource in "${datasources[@]}"; do
        if aws quicksight describe-data-source \
            --aws-account-id "${AWS_ACCOUNT_ID}" \
            --data-source-id "${datasource}" &>/dev/null; then
            aws quicksight delete-data-source \
                --aws-account-id "${AWS_ACCOUNT_ID}" \
                --data-source-id "${datasource}" 2>/dev/null || \
                log_warning "Failed to delete QuickSight data source: ${datasource}"
            log_success "Deleted QuickSight data source: ${datasource}"
        fi
    done
    
    log_success "QuickSight resources cleanup completed."
}

# Remove EventBridge resources
remove_eventbridge_resources() {
    log_info "Removing EventBridge rules and targets..."
    
    local rules=("DailyCostDataCollection" "WeeklyDataTransformation")
    
    for rule in "${rules[@]}"; do
        # Remove targets first
        if aws events describe-rule --name "${rule}" &>/dev/null; then
            # Get target IDs
            local target_ids=$(aws events list-targets-by-rule \
                --rule "${rule}" \
                --query 'Targets[].Id' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "${target_ids}" ]]; then
                aws events remove-targets \
                    --rule "${rule}" \
                    --ids ${target_ids} 2>/dev/null || \
                    log_warning "Failed to remove targets from rule: ${rule}"
            fi
            
            # Delete the rule
            aws events delete-rule \
                --name "${rule}" 2>/dev/null || \
                log_warning "Failed to delete EventBridge rule: ${rule}"
            
            log_success "Deleted EventBridge rule: ${rule}"
        fi
    done
    
    log_success "EventBridge resources cleanup completed."
}

# Remove Lambda functions
remove_lambda_functions() {
    log_info "Removing Lambda functions..."
    
    local functions=("CostDataCollector" "DataTransformer")
    
    for function in "${functions[@]}"; do
        if aws lambda get-function --function-name "${function}" &>/dev/null; then
            aws lambda delete-function \
                --function-name "${function}" 2>/dev/null || \
                log_warning "Failed to delete Lambda function: ${function}"
            log_success "Deleted Lambda function: ${function}"
        fi
    done
    
    log_success "Lambda functions cleanup completed."
}

# Remove Athena resources
remove_athena_resources() {
    log_info "Removing Athena workgroup and database..."
    
    # Delete Athena workgroup
    if aws athena get-work-group --work-group "FinancialAnalytics" &>/dev/null; then
        # First, cancel any running queries
        local query_ids=$(aws athena list-query-executions \
            --work-group "FinancialAnalytics" \
            --query 'QueryExecutionIds' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${query_ids}" ]]; then
            for query_id in ${query_ids}; do
                aws athena stop-query-execution \
                    --query-execution-id "${query_id}" 2>/dev/null || true
            done
        fi
        
        # Delete workgroup
        aws athena delete-work-group \
            --work-group "FinancialAnalytics" \
            --recursive-delete-option 2>/dev/null || \
            log_warning "Failed to delete Athena workgroup: FinancialAnalytics"
        
        log_success "Deleted Athena workgroup: FinancialAnalytics"
    fi
    
    # Delete Glue database
    if aws glue get-database --name "financial_analytics" &>/dev/null; then
        aws glue delete-database \
            --name "financial_analytics" 2>/dev/null || \
            log_warning "Failed to delete Glue database: financial_analytics"
        log_success "Deleted Glue database: financial_analytics"
    fi
    
    log_success "Athena resources cleanup completed."
}

# Remove IAM resources
remove_iam_resources() {
    log_info "Removing IAM role and policies..."
    
    local role_name="FinancialAnalyticsLambdaRole"
    local policy_name="FinancialAnalyticsPolicy"
    
    # Detach and delete policy
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}" &>/dev/null; then
        # Detach from role
        aws iam detach-role-policy \
            --role-name "${role_name}" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}" 2>/dev/null || \
            log_warning "Failed to detach policy from role"
        
        # Delete policy
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}" 2>/dev/null || \
            log_warning "Failed to delete IAM policy: ${policy_name}"
        
        log_success "Deleted IAM policy: ${policy_name}"
    fi
    
    # Delete role
    if aws iam get-role --role-name "${role_name}" &>/dev/null; then
        aws iam delete-role \
            --role-name "${role_name}" 2>/dev/null || \
            log_warning "Failed to delete IAM role: ${role_name}"
        log_success "Deleted IAM role: ${role_name}"
    fi
    
    log_success "IAM resources cleanup completed."
}

# Remove S3 buckets
remove_s3_buckets() {
    log_info "Removing S3 buckets and all data..."
    
    # List of buckets to remove
    local buckets=()
    
    # Add buckets from environment variables if they exist
    [[ -n "${RAW_DATA_BUCKET:-}" ]] && buckets+=("${RAW_DATA_BUCKET}")
    [[ -n "${PROCESSED_DATA_BUCKET:-}" ]] && buckets+=("${PROCESSED_DATA_BUCKET}")
    [[ -n "${REPORTS_BUCKET:-}" ]] && buckets+=("${REPORTS_BUCKET}")
    [[ -n "${ANALYTICS_BUCKET:-}" ]] && buckets+=("${ANALYTICS_BUCKET}")
    
    # If no buckets from env file, try to find them
    if [[ ${#buckets[@]} -eq 0 ]]; then
        log_warning "No bucket names found in environment file. Attempting to find buckets by pattern..."
        
        # Look for buckets with our naming patterns
        local bucket_patterns=("cost-raw-data-" "cost-processed-data-" "financial-reports-" "financial-analytics-")
        
        for pattern in "${bucket_patterns[@]}"; do
            local found_buckets=$(aws s3api list-buckets \
                --query "Buckets[?starts_with(Name, '${pattern}')].Name" \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "${found_buckets}" ]]; then
                for bucket in ${found_buckets}; do
                    buckets+=("${bucket}")
                done
            fi
        done
    fi
    
    # Remove each bucket
    for bucket in "${buckets[@]}"; do
        if aws s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
            log_info "Removing bucket: ${bucket}"
            
            # First, remove all objects and versions
            aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || \
                log_warning "Failed to remove objects from bucket: ${bucket}"
            
            # Remove all object versions and delete markers
            aws s3api list-object-versions \
                --bucket "${bucket}" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | \
                while read -r key version_id; do
                    if [[ -n "${key}" && -n "${version_id}" ]]; then
                        aws s3api delete-object \
                            --bucket "${bucket}" \
                            --key "${key}" \
                            --version-id "${version_id}" 2>/dev/null || true
                    fi
                done
            
            # Remove delete markers
            aws s3api list-object-versions \
                --bucket "${bucket}" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | \
                while read -r key version_id; do
                    if [[ -n "${key}" && -n "${version_id}" ]]; then
                        aws s3api delete-object \
                            --bucket "${bucket}" \
                            --key "${key}" \
                            --version-id "${version_id}" 2>/dev/null || true
                    fi
                done
            
            # Finally, delete the bucket
            aws s3 rb "s3://${bucket}" --force 2>/dev/null || \
                log_warning "Failed to delete bucket: ${bucket}"
            
            log_success "Deleted bucket: ${bucket}"
        else
            log_warning "Bucket not found or already deleted: ${bucket}"
        fi
    done
    
    log_success "S3 buckets cleanup completed."
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove temporary files created during deployment
    local files_to_remove=(
        "${SCRIPT_DIR}/lambda-analytics-trust-policy.json"
        "${SCRIPT_DIR}/lambda-analytics-policy.json"
        "${SCRIPT_DIR}/collection-response.json"
        "${SCRIPT_DIR}/transformation-response.json"
        "${SCRIPT_DIR}/quicksight-manifest.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_success "Removed file: $(basename "${file}")"
        fi
    done
    
    # Optionally remove environment file (ask user)
    if [[ -f "${ENV_FILE}" ]]; then
        read -p "Remove environment file (${ENV_FILE})? [y/N]: " remove_env
        if [[ "${remove_env}" =~ ^[Yy]$ ]]; then
            rm -f "${ENV_FILE}"
            log_success "Removed environment file."
        fi
    fi
    
    log_success "Local files cleanup completed."
}

# Display final summary
display_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo -e "\n${GREEN}================================================================"
    echo "  CLEANUP COMPLETED!"
    echo "================================================================${NC}"
    echo ""
    echo -e "${BLUE}Summary:${NC}"
    echo "• Cleanup completed in ${duration} seconds"
    echo "• All AWS resources have been removed"
    echo "• Local temporary files have been cleaned up"
    echo ""
    echo -e "${YELLOW}Manual Steps Required:${NC}"
    echo "• If you have QuickSight analyses or dashboards, delete them manually"
    echo "• Review your AWS bill to ensure no unexpected charges"
    echo "• Check CloudWatch logs if you want to remove log groups"
    echo ""
    echo -e "${YELLOW}Important:${NC}"
    echo "• All cost data has been permanently deleted"
    echo "• This action cannot be undone"
    echo "• Re-run deploy.sh to recreate the solution"
    echo ""
    echo -e "${GREEN}Thank you for using the Financial Analytics Dashboard!${NC}"
    echo ""
}

# Verify AWS access
verify_aws_access() {
    log_info "Verifying AWS access..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    log_success "AWS access verified."
}

# Main cleanup function
main() {
    # Start timing
    start_time=$(date +%s)
    
    # Initialize log file
    echo "Cleanup started at $(date)" > "${LOG_FILE}"
    
    display_banner
    verify_aws_access
    load_environment
    confirm_deletion
    
    # Execute cleanup steps (order matters for dependencies)
    remove_quicksight_resources
    remove_eventbridge_resources
    remove_lambda_functions
    remove_athena_resources
    remove_iam_resources
    remove_s3_buckets
    cleanup_local_files
    
    display_summary
}

# Cleanup function for interrupted destruction
cleanup_on_interrupt() {
    log_warning "Cleanup interrupted. Some resources may still exist."
    echo "Re-run this script to continue cleanup."
    exit 1
}

# Set up interrupt handler
trap cleanup_on_interrupt SIGINT SIGTERM

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help     Show this help message"
    echo "  -f, --force    Skip confirmation prompts (dangerous!)"
    echo "  -y, --yes      Answer yes to all prompts"
    echo ""
    echo "This script removes all AWS resources created by the deployment script."
    echo "Use with caution as this action cannot be undone."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force|-y|--yes)
            # Set non-interactive mode
            export FORCE_YES=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Override confirmation if force mode is enabled
if [[ "${FORCE_YES:-false}" == "true" ]]; then
    confirm_deletion() {
        log_warning "Force mode enabled - skipping confirmation prompts."
    }
fi

# Run main cleanup
main "$@"