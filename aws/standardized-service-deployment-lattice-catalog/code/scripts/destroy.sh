#!/bin/bash

# Standardized Service Deployment with VPC Lattice and Service Catalog - Destroy Script
# This script safely removes all resources created by the deployment script

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.json"
readonly DRY_RUN=${DRY_RUN:-false}
readonly FORCE=${FORCE:-false}

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

# Error handler
error_handler() {
    local line_no=$1
    log_error "Script failed at line ${line_no}"
    exit 1
}

# Set error trap
trap 'error_handler ${LINENO}' ERR

# Help function
show_help() {
    cat << EOF
Standardized Service Deployment with VPC Lattice and Service Catalog - Destroy Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be destroyed without making changes
    -f, --force            Skip confirmation prompts (use with caution)
    -k, --keep-s3          Keep S3 bucket and templates
    -i, --info-file FILE   Path to deployment info file (default: ./deployment-info.json)
    -v, --verbose          Enable verbose logging

ENVIRONMENT VARIABLES:
    DRY_RUN                Set to 'true' to enable dry-run mode
    FORCE                  Set to 'true' to skip confirmation prompts
    AWS_REGION             AWS region override

EXAMPLES:
    $0                                    # Interactive destroy with confirmations
    $0 --dry-run                         # Preview what would be destroyed
    $0 --force                           # Destroy without prompts (dangerous!)
    $0 --keep-s3                         # Destroy but keep S3 bucket
    DRY_RUN=true $0                      # Dry run using environment variable

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -k|--keep-s3)
                KEEP_S3=true
                shift
                ;;
            -i|--info-file)
                DEPLOYMENT_INFO_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check if jq is available (for parsing deployment info)
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for parsing deployment info. Please install it."
        exit 1
    fi
    
    # Check if deployment info file exists
    if [[ ! -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        log_error "Deployment info file not found: ${DEPLOYMENT_INFO_FILE}"
        log_error "This file is created during deployment and contains resource IDs"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Validate JSON format
    if ! jq empty "${DEPLOYMENT_INFO_FILE}" 2>/dev/null; then
        log_error "Invalid JSON in deployment info file: ${DEPLOYMENT_INFO_FILE}"
        exit 1
    fi
    
    # Load variables from deployment info
    export PORTFOLIO_ID=$(jq -r '.portfolioId // empty' "${DEPLOYMENT_INFO_FILE}")
    export NETWORK_PRODUCT_ID=$(jq -r '.networkProductId // empty' "${DEPLOYMENT_INFO_FILE}")
    export SERVICE_PRODUCT_ID=$(jq -r '.serviceProductId // empty' "${DEPLOYMENT_INFO_FILE}")
    export LAUNCH_ROLE_ARN=$(jq -r '.launchRoleArn // empty' "${DEPLOYMENT_INFO_FILE}")
    export BUCKET_NAME=$(jq -r '.bucketName // empty' "${DEPLOYMENT_INFO_FILE}")
    export RESOURCE_PREFIX=$(jq -r '.resourcePrefix // empty' "${DEPLOYMENT_INFO_FILE}")
    export TEST_NETWORK_ID=$(jq -r '.testNetworkId // empty' "${DEPLOYMENT_INFO_FILE}")
    export TEST_NETWORK_NAME=$(jq -r '.testNetworkName // empty' "${DEPLOYMENT_INFO_FILE}")
    
    # Extract role name from ARN
    if [[ -n "${LAUNCH_ROLE_ARN}" ]]; then
        export LAUNCH_ROLE_NAME=$(echo "${LAUNCH_ROLE_ARN}" | cut -d'/' -f2)
    fi
    
    # Set AWS region from deployment info or AWS config
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    
    log_info "Deployment information loaded:"
    log_info "  Portfolio ID: ${PORTFOLIO_ID:-'Not found'}"
    log_info "  Network Product ID: ${NETWORK_PRODUCT_ID:-'Not found'}"
    log_info "  Service Product ID: ${SERVICE_PRODUCT_ID:-'Not found'}"
    log_info "  IAM Role: ${LAUNCH_ROLE_NAME:-'Not found'}"
    log_info "  S3 Bucket: ${BUCKET_NAME:-'Not found'}"
    log_info "  Resource Prefix: ${RESOURCE_PREFIX:-'Not found'}"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "${FORCE}" == "true" || "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will destroy the following resources:"
    echo "  • Service Catalog Portfolio: ${PORTFOLIO_ID}"
    echo "  • Service Catalog Products: ${NETWORK_PRODUCT_ID}, ${SERVICE_PRODUCT_ID}"
    echo "  • IAM Role: ${LAUNCH_ROLE_NAME}"
    if [[ "${KEEP_S3:-false}" != "true" ]]; then
        echo "  • S3 Bucket: ${BUCKET_NAME}"
    fi
    if [[ -n "${TEST_NETWORK_ID}" ]]; then
        echo "  • Test Service Network: ${TEST_NETWORK_NAME}"
    fi
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
}

# Wait for provisioned product termination
wait_for_termination() {
    local provisioned_product_id="$1"
    local product_name="$2"
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for ${product_name} termination to complete..."
    
    while [[ $attempt -le $max_attempts ]]; do
        local status
        status=$(aws servicecatalog describe-provisioned-product \
            --id "${provisioned_product_id}" \
            --query 'ProvisionedProductDetail.Status' \
            --output text 2>/dev/null || echo "TERMINATED")
        
        if [[ "${status}" == "TERMINATED" ]]; then
            log_success "${product_name} termination completed"
            return 0
        elif [[ "${status}" == "ERROR" ]]; then
            log_warning "${product_name} termination failed"
            return 1
        fi
        
        log_info "  Status: ${status} (attempt ${attempt}/${max_attempts})"
        sleep 30
        ((attempt++))
    done
    
    log_warning "${product_name} termination timed out after $((max_attempts * 30)) seconds"
    return 1
}

# Remove test provisioned products
remove_test_resources() {
    if [[ -z "${TEST_NETWORK_ID}" ]]; then
        log_info "No test resources to remove"
        return 0
    fi
    
    log_info "Removing test provisioned products..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would terminate test network: ${TEST_NETWORK_ID}"
        return 0
    fi
    
    # Check if test network still exists
    if aws servicecatalog describe-provisioned-product --id "${TEST_NETWORK_ID}" &>/dev/null; then
        # Terminate test network
        aws servicecatalog terminate-provisioned-product \
            --provisioned-product-id "${TEST_NETWORK_ID}" \
            --ignore-errors || true
        
        # Wait for termination
        wait_for_termination "${TEST_NETWORK_ID}" "test network"
    else
        log_info "Test network already terminated or not found"
    fi
    
    log_success "Test resources removal completed"
}

# Remove Service Catalog resources
remove_service_catalog() {
    log_info "Removing Service Catalog resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would remove Service Catalog portfolio and products"
        return 0
    fi
    
    # Remove portfolio access
    local current_user_arn
    current_user_arn=$(aws sts get-caller-identity --query 'Arn' --output text)
    
    aws servicecatalog disassociate-principal-from-portfolio \
        --portfolio-id "${PORTFOLIO_ID}" \
        --principal-arn "${current_user_arn}" 2>/dev/null || true
    
    # Remove constraints
    local constraints
    constraints=$(aws servicecatalog list-constraints-for-portfolio \
        --portfolio-id "${PORTFOLIO_ID}" \
        --query 'ConstraintDetails[].ConstraintId' \
        --output text 2>/dev/null || echo "")
    
    for constraint_id in ${constraints}; do
        if [[ -n "${constraint_id}" && "${constraint_id}" != "None" ]]; then
            aws servicecatalog delete-constraint \
                --id "${constraint_id}" 2>/dev/null || true
        fi
    done
    
    # Disassociate products from portfolio
    if [[ -n "${NETWORK_PRODUCT_ID}" ]]; then
        aws servicecatalog disassociate-product-from-portfolio \
            --product-id "${NETWORK_PRODUCT_ID}" \
            --portfolio-id "${PORTFOLIO_ID}" 2>/dev/null || true
    fi
    
    if [[ -n "${SERVICE_PRODUCT_ID}" ]]; then
        aws servicecatalog disassociate-product-from-portfolio \
            --product-id "${SERVICE_PRODUCT_ID}" \
            --portfolio-id "${PORTFOLIO_ID}" 2>/dev/null || true
    fi
    
    # Delete products
    if [[ -n "${NETWORK_PRODUCT_ID}" ]]; then
        aws servicecatalog delete-product \
            --id "${NETWORK_PRODUCT_ID}" 2>/dev/null || true
    fi
    
    if [[ -n "${SERVICE_PRODUCT_ID}" ]]; then
        aws servicecatalog delete-product \
            --id "${SERVICE_PRODUCT_ID}" 2>/dev/null || true
    fi
    
    # Delete portfolio
    if [[ -n "${PORTFOLIO_ID}" ]]; then
        aws servicecatalog delete-portfolio \
            --id "${PORTFOLIO_ID}" 2>/dev/null || true
    fi
    
    log_success "Service Catalog resources removed"
}

# Remove IAM role
remove_iam_role() {
    if [[ -z "${LAUNCH_ROLE_NAME}" ]]; then
        log_info "No IAM role to remove"
        return 0
    fi
    
    log_info "Removing IAM role: ${LAUNCH_ROLE_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would remove IAM role: ${LAUNCH_ROLE_NAME}"
        return 0
    fi
    
    # Check if role exists
    if ! aws iam get-role --role-name "${LAUNCH_ROLE_NAME}" &>/dev/null; then
        log_info "IAM role ${LAUNCH_ROLE_NAME} does not exist"
        return 0
    fi
    
    # Remove inline policies
    local policies
    policies=$(aws iam list-role-policies \
        --role-name "${LAUNCH_ROLE_NAME}" \
        --query 'PolicyNames' \
        --output text 2>/dev/null || echo "")
    
    for policy_name in ${policies}; do
        if [[ -n "${policy_name}" && "${policy_name}" != "None" ]]; then
            aws iam delete-role-policy \
                --role-name "${LAUNCH_ROLE_NAME}" \
                --policy-name "${policy_name}" 2>/dev/null || true
        fi
    done
    
    # Remove attached managed policies
    local attached_policies
    attached_policies=$(aws iam list-attached-role-policies \
        --role-name "${LAUNCH_ROLE_NAME}" \
        --query 'AttachedPolicies[].PolicyArn' \
        --output text 2>/dev/null || echo "")
    
    for policy_arn in ${attached_policies}; do
        if [[ -n "${policy_arn}" && "${policy_arn}" != "None" ]]; then
            aws iam detach-role-policy \
                --role-name "${LAUNCH_ROLE_NAME}" \
                --policy-arn "${policy_arn}" 2>/dev/null || true
        fi
    done
    
    # Delete role
    aws iam delete-role --role-name "${LAUNCH_ROLE_NAME}"
    
    log_success "IAM role removed: ${LAUNCH_ROLE_NAME}"
}

# Remove S3 bucket and contents
remove_s3_bucket() {
    if [[ "${KEEP_S3:-false}" == "true" ]]; then
        log_info "Keeping S3 bucket as requested: ${BUCKET_NAME}"
        return 0
    fi
    
    if [[ -z "${BUCKET_NAME}" ]]; then
        log_info "No S3 bucket to remove"
        return 0
    fi
    
    log_info "Removing S3 bucket: ${BUCKET_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would remove S3 bucket: ${BUCKET_NAME}"
        return 0
    fi
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        log_info "S3 bucket ${BUCKET_NAME} does not exist"
        return 0
    fi
    
    # Remove all objects and versions
    aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>/dev/null || true
    
    # Remove all object versions (if versioning is enabled)
    aws s3api list-object-versions \
        --bucket "${BUCKET_NAME}" \
        --output json \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' 2>/dev/null | \
    jq -r '.[] | "--key \(.Key) --version-id \(.VersionId)"' | \
    while read -r args; do
        if [[ -n "${args}" ]]; then
            aws s3api delete-object --bucket "${BUCKET_NAME}" ${args} 2>/dev/null || true
        fi
    done
    
    # Remove delete markers
    aws s3api list-object-versions \
        --bucket "${BUCKET_NAME}" \
        --output json \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' 2>/dev/null | \
    jq -r '.[] | "--key \(.Key) --version-id \(.VersionId)"' | \
    while read -r args; do
        if [[ -n "${args}" ]]; then
            aws s3api delete-object --bucket "${BUCKET_NAME}" ${args} 2>/dev/null || true
        fi
    done
    
    # Delete bucket
    aws s3api delete-bucket --bucket "${BUCKET_NAME}"
    
    log_success "S3 bucket removed: ${BUCKET_NAME}"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would remove local deployment files"
        return 0
    fi
    
    # Remove deployment info file
    if [[ -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        rm -f "${DEPLOYMENT_INFO_FILE}"
        log_success "Removed deployment info file"
    fi
    
    # Remove any temporary CloudFormation templates in the current directory
    local template_files=("service-network-template.yaml" "lattice-service-template.yaml" 
                         "service-catalog-role-policy.json" "vpc-lattice-permissions.json"
                         "trust-policy.json" "permissions-policy.json")
    
    for file in "${template_files[@]}"; do
        if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
            rm -f "${SCRIPT_DIR}/${file}"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Display destruction summary
show_summary() {
    log_info "Destruction Summary"
    echo "=================================="
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "DRY RUN - No resources were actually destroyed"
    else
        echo "Successfully destroyed resources:"
        echo "✓ Service Catalog Portfolio: ${PORTFOLIO_ID}"
        echo "✓ Service Catalog Products"
        echo "✓ IAM Role: ${LAUNCH_ROLE_NAME}"
        if [[ "${KEEP_S3:-false}" != "true" ]]; then
            echo "✓ S3 Bucket: ${BUCKET_NAME}"
        else
            echo "○ S3 Bucket: ${BUCKET_NAME} (kept as requested)"
        fi
        if [[ -n "${TEST_NETWORK_ID}" ]]; then
            echo "✓ Test Resources"
        fi
        echo "✓ Local Files"
    fi
    echo ""
    echo "Log file: ${LOG_FILE}"
    echo "=================================="
}

# Main execution
main() {
    log_info "Starting destruction of Standardized Service Deployment with VPC Lattice and Service Catalog"
    
    # Parse arguments
    parse_args "$@"
    
    # Run destruction steps
    check_prerequisites
    load_deployment_info
    confirm_destruction
    remove_test_resources
    remove_service_catalog
    remove_iam_role
    remove_s3_bucket
    cleanup_local_files
    
    log_success "Destruction completed successfully!"
    show_summary
}

# Execute main function with all arguments
main "$@"