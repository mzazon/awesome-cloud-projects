#!/bin/bash

# Advanced Cross-Account IAM Role Federation Cleanup Script
# This script safely removes all infrastructure created by the deployment script
# including IAM roles, CloudTrail, S3 buckets, Lambda functions, and related resources

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
CONFIG_FILE="${SCRIPT_DIR}/deployment-config.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Confirmation function
confirm_destruction() {
    echo "=========================================="
    echo "Advanced Cross-Account IAM Role Federation"
    echo "DESTRUCTION CONFIRMATION"
    echo "=========================================="
    echo
    warning "⚠️  This script will permanently delete the following resources:"
    echo "   • IAM Roles and Policies"
    echo "   • CloudTrail and S3 Audit Bucket"
    echo "   • Lambda Functions"
    echo "   • All associated configurations"
    echo
    warning "⚠️  This action cannot be undone!"
    echo
    
    if [ "${FORCE_DESTROY:-}" == "true" ]; then
        warning "FORCE_DESTROY is set. Proceeding without confirmation."
        return 0
    fi
    
    read -p "Are you sure you want to continue? Type 'DESTROY' to confirm: " confirmation
    
    if [ "$confirmation" != "DESTROY" ]; then
        info "Destruction cancelled by user."
        exit 0
    fi
    
    echo
    info "Proceeding with resource destruction..."
    echo
}

# Load configuration
load_configuration() {
    info "Loading deployment configuration..."
    
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Configuration file not found: $CONFIG_FILE"
        error "This suggests the deployment was not completed or the config file was deleted."
        error "You may need to manually clean up resources or set environment variables:"
        error "  export SECURITY_ACCOUNT_ID=111111111111"
        error "  export PROD_ACCOUNT_ID=222222222222"
        error "  export DEV_ACCOUNT_ID=333333333333"
        error "  export AWS_REGION=us-east-1"
        error "  export RANDOM_SUFFIX=abcd1234"
        exit 1
    fi
    
    # Load environment variables from config file
    source "$CONFIG_FILE"
    
    # Validate required variables
    if [ -z "${SECURITY_ACCOUNT_ID:-}" ] || [ -z "${PROD_ACCOUNT_ID:-}" ] || [ -z "${DEV_ACCOUNT_ID:-}" ] || [ -z "${AWS_REGION:-}" ] || [ -z "${RANDOM_SUFFIX:-}" ]; then
        error "Required configuration variables are missing from $CONFIG_FILE"
        exit 1
    fi
    
    info "Configuration loaded:"
    info "  Security Account: ${SECURITY_ACCOUNT_ID}"
    info "  Production Account: ${PROD_ACCOUNT_ID}"
    info "  Development Account: ${DEV_ACCOUNT_ID}"
    info "  Region: ${AWS_REGION}"
    info "  Random Suffix: ${RANDOM_SUFFIX}"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if jq is installed (for JSON processing)
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid. Please run 'aws configure'."
        exit 1
    fi
    
    # Verify we're in the correct account
    CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    if [ "$CURRENT_ACCOUNT" != "$SECURITY_ACCOUNT_ID" ]; then
        warning "Current AWS account ($CURRENT_ACCOUNT) doesn't match security account ($SECURITY_ACCOUNT_ID)"
        warning "Some resources may not be accessible for cleanup."
    fi
    
    success "Prerequisites check completed"
}

# Remove Lambda functions and roles
cleanup_lambda_resources() {
    info "Cleaning up Lambda functions and roles..."
    
    # Delete Lambda function
    if aws lambda get-function --function-name "CrossAccountRoleValidator-${RANDOM_SUFFIX}" &> /dev/null; then
        info "Deleting Lambda function..."
        aws lambda delete-function \
            --function-name "CrossAccountRoleValidator-${RANDOM_SUFFIX}"
        success "Lambda function deleted"
    else
        warning "Lambda function not found (may have been deleted already)"
    fi
    
    # Delete Lambda execution role policies
    if aws iam get-role --role-name "RoleValidatorLambdaRole-${RANDOM_SUFFIX}" &> /dev/null; then
        info "Deleting Lambda execution role policies..."
        
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "RoleValidatorLambdaRole-${RANDOM_SUFFIX}" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" || true
        
        aws iam detach-role-policy \
            --role-name "RoleValidatorLambdaRole-${RANDOM_SUFFIX}" \
            --policy-arn "arn:aws:iam::aws:policy/IAMReadOnlyAccess" || true
        
        # Delete the role
        aws iam delete-role \
            --role-name "RoleValidatorLambdaRole-${RANDOM_SUFFIX}"
        
        success "Lambda execution role deleted"
    else
        warning "Lambda execution role not found (may have been deleted already)"
    fi
}

# Remove CloudTrail and S3 bucket
cleanup_audit_trail() {
    info "Cleaning up CloudTrail and audit bucket..."
    
    # Stop and delete CloudTrail
    if aws cloudtrail describe-trails --trail-name-list "CrossAccountAuditTrail-${RANDOM_SUFFIX}" --query 'trailList[0].Name' --output text 2>/dev/null | grep -q "CrossAccountAuditTrail"; then
        info "Stopping and deleting CloudTrail..."
        
        # Stop logging
        aws cloudtrail stop-logging \
            --name "CrossAccountAuditTrail-${RANDOM_SUFFIX}" || true
        
        # Delete trail
        aws cloudtrail delete-trail \
            --name "CrossAccountAuditTrail-${RANDOM_SUFFIX}"
        
        success "CloudTrail deleted"
    else
        warning "CloudTrail not found (may have been deleted already)"
    fi
    
    # Empty and delete S3 bucket
    if aws s3api head-bucket --bucket "cross-account-audit-trail-${RANDOM_SUFFIX}" 2>/dev/null; then
        info "Emptying and deleting S3 audit bucket..."
        
        # Empty bucket first
        aws s3 rm "s3://cross-account-audit-trail-${RANDOM_SUFFIX}" \
            --recursive || true
        
        # Delete bucket
        aws s3 rb "s3://cross-account-audit-trail-${RANDOM_SUFFIX}" || true
        
        success "S3 audit bucket deleted"
    else
        warning "S3 audit bucket not found (may have been deleted already)"
    fi
}

# Remove cross-account roles
cleanup_cross_account_roles() {
    info "Cleaning up cross-account roles..."
    
    # Delete production account role
    if aws iam get-role --role-name "CrossAccount-ProductionAccess-${RANDOM_SUFFIX}" &> /dev/null; then
        info "Deleting production cross-account role..."
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "CrossAccount-ProductionAccess-${RANDOM_SUFFIX}" \
            --policy-name "ProductionResourceAccess" || true
        
        # Delete role
        aws iam delete-role \
            --role-name "CrossAccount-ProductionAccess-${RANDOM_SUFFIX}"
        
        success "Production cross-account role deleted"
    else
        warning "Production cross-account role not found (may have been deleted already)"
    fi
    
    # Delete development account role
    if aws iam get-role --role-name "CrossAccount-DevelopmentAccess-${RANDOM_SUFFIX}" &> /dev/null; then
        info "Deleting development cross-account role..."
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "CrossAccount-DevelopmentAccess-${RANDOM_SUFFIX}" \
            --policy-name "DevelopmentResourceAccess" || true
        
        # Delete role
        aws iam delete-role \
            --role-name "CrossAccount-DevelopmentAccess-${RANDOM_SUFFIX}"
        
        success "Development cross-account role deleted"
    else
        warning "Development cross-account role not found (may have been deleted already)"
    fi
}

# Remove master cross-account role
cleanup_master_role() {
    info "Cleaning up master cross-account role..."
    
    if aws iam get-role --role-name "MasterCrossAccountRole-${RANDOM_SUFFIX}" &> /dev/null; then
        info "Deleting master cross-account role..."
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "MasterCrossAccountRole-${RANDOM_SUFFIX}" \
            --policy-name "CrossAccountAssumePolicy" || true
        
        aws iam delete-role-policy \
            --role-name "MasterCrossAccountRole-${RANDOM_SUFFIX}" \
            --policy-name "EnhancedCrossAccountAccess" || true
        
        # Delete role
        aws iam delete-role \
            --role-name "MasterCrossAccountRole-${RANDOM_SUFFIX}"
        
        success "Master cross-account role deleted"
    else
        warning "Master cross-account role not found (may have been deleted already)"
    fi
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove generated scripts
    if [ -f "${SCRIPT_DIR}/assume-cross-account-role.sh" ]; then
        rm -f "${SCRIPT_DIR}/assume-cross-account-role.sh"
        success "Role assumption script removed"
    fi
    
    # Remove configuration file (with confirmation)
    if [ -f "$CONFIG_FILE" ]; then
        info "Removing deployment configuration file..."
        rm -f "$CONFIG_FILE"
        success "Configuration file removed"
    fi
    
    # Remove log files older than 30 days
    find "${SCRIPT_DIR}" -name "*.log" -type f -mtime +30 -delete 2>/dev/null || true
    
    success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    info "Verifying cleanup completion..."
    
    local cleanup_issues=()
    
    # Check for remaining IAM roles
    if aws iam get-role --role-name "MasterCrossAccountRole-${RANDOM_SUFFIX}" &> /dev/null; then
        cleanup_issues+=("Master cross-account role still exists")
    fi
    
    if aws iam get-role --role-name "CrossAccount-ProductionAccess-${RANDOM_SUFFIX}" &> /dev/null; then
        cleanup_issues+=("Production cross-account role still exists")
    fi
    
    if aws iam get-role --role-name "CrossAccount-DevelopmentAccess-${RANDOM_SUFFIX}" &> /dev/null; then
        cleanup_issues+=("Development cross-account role still exists")
    fi
    
    if aws iam get-role --role-name "RoleValidatorLambdaRole-${RANDOM_SUFFIX}" &> /dev/null; then
        cleanup_issues+=("Lambda execution role still exists")
    fi
    
    # Check for remaining Lambda functions
    if aws lambda get-function --function-name "CrossAccountRoleValidator-${RANDOM_SUFFIX}" &> /dev/null; then
        cleanup_issues+=("Lambda function still exists")
    fi
    
    # Check for remaining CloudTrail
    if aws cloudtrail describe-trails --trail-name-list "CrossAccountAuditTrail-${RANDOM_SUFFIX}" --query 'trailList[0].Name' --output text 2>/dev/null | grep -q "CrossAccountAuditTrail"; then
        cleanup_issues+=("CloudTrail still exists")
    fi
    
    # Check for remaining S3 bucket
    if aws s3api head-bucket --bucket "cross-account-audit-trail-${RANDOM_SUFFIX}" 2>/dev/null; then
        cleanup_issues+=("S3 audit bucket still exists")
    fi
    
    # Report results
    if [ ${#cleanup_issues[@]} -eq 0 ]; then
        success "✅ All resources have been successfully cleaned up"
        return 0
    else
        warning "⚠️  The following resources may still exist:"
        for issue in "${cleanup_issues[@]}"; do
            warning "   • $issue"
        done
        warning "You may need to manually remove these resources or wait for eventual consistency."
        return 1
    fi
}

# Error handling and cleanup
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Cleanup script encountered an error. Check $LOG_FILE for details."
        warning "Some resources may not have been removed. Please check manually."
    fi
    exit $exit_code
}

trap cleanup_on_error ERR

# Display help information
show_help() {
    echo "Advanced Cross-Account IAM Role Federation Cleanup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -f, --force     Skip confirmation prompt and proceed with destruction"
    echo "  -h, --help      Show this help message"
    echo "  --dry-run       Show what would be deleted without actually deleting anything"
    echo
    echo "Environment Variables:"
    echo "  FORCE_DESTROY   Set to 'true' to skip confirmation (equivalent to --force)"
    echo
    echo "Examples:"
    echo "  $0                    # Interactive cleanup with confirmation"
    echo "  $0 --force            # Force cleanup without confirmation"
    echo "  $0 --dry-run          # Show what would be deleted"
    echo
    echo "This script will remove all resources created by the deployment script,"
    echo "including IAM roles, CloudTrail, S3 buckets, and Lambda functions."
}

# Dry run mode
dry_run_mode() {
    info "DRY RUN MODE - No resources will be deleted"
    echo
    
    load_configuration
    
    info "The following resources would be deleted:"
    echo
    
    # Check what exists and would be deleted
    info "IAM Roles:"
    for role in "MasterCrossAccountRole-${RANDOM_SUFFIX}" "CrossAccount-ProductionAccess-${RANDOM_SUFFIX}" "CrossAccount-DevelopmentAccess-${RANDOM_SUFFIX}" "RoleValidatorLambdaRole-${RANDOM_SUFFIX}"; do
        if aws iam get-role --role-name "$role" &> /dev/null; then
            info "  ✓ $role (EXISTS - would be deleted)"
        else
            info "  ✗ $role (not found)"
        fi
    done
    
    echo
    info "Lambda Functions:"
    if aws lambda get-function --function-name "CrossAccountRoleValidator-${RANDOM_SUFFIX}" &> /dev/null; then
        info "  ✓ CrossAccountRoleValidator-${RANDOM_SUFFIX} (EXISTS - would be deleted)"
    else
        info "  ✗ CrossAccountRoleValidator-${RANDOM_SUFFIX} (not found)"
    fi
    
    echo
    info "CloudTrail:"
    if aws cloudtrail describe-trails --trail-name-list "CrossAccountAuditTrail-${RANDOM_SUFFIX}" --query 'trailList[0].Name' --output text 2>/dev/null | grep -q "CrossAccountAuditTrail"; then
        info "  ✓ CrossAccountAuditTrail-${RANDOM_SUFFIX} (EXISTS - would be deleted)"
    else
        info "  ✗ CrossAccountAuditTrail-${RANDOM_SUFFIX} (not found)"
    fi
    
    echo
    info "S3 Buckets:"
    if aws s3api head-bucket --bucket "cross-account-audit-trail-${RANDOM_SUFFIX}" 2>/dev/null; then
        info "  ✓ cross-account-audit-trail-${RANDOM_SUFFIX} (EXISTS - would be deleted)"
    else
        info "  ✗ cross-account-audit-trail-${RANDOM_SUFFIX} (not found)"
    fi
    
    echo
    info "Local Files:"
    if [ -f "${SCRIPT_DIR}/assume-cross-account-role.sh" ]; then
        info "  ✓ assume-cross-account-role.sh (EXISTS - would be deleted)"
    else
        info "  ✗ assume-cross-account-role.sh (not found)"
    fi
    
    if [ -f "$CONFIG_FILE" ]; then
        info "  ✓ deployment-config.env (EXISTS - would be deleted)"
    else
        info "  ✗ deployment-config.env (not found)"
    fi
    
    echo
    info "DRY RUN COMPLETE - Use '$0 --force' to actually delete these resources"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                export FORCE_DESTROY="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --dry-run)
                dry_run_mode
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main cleanup function
main() {
    echo "=========================================="
    echo "Advanced Cross-Account IAM Role Federation"
    echo "Cleanup Script"
    echo "=========================================="
    echo
    
    # Initialize log file
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    # Run cleanup steps
    confirm_destruction
    load_configuration
    check_prerequisites
    cleanup_lambda_resources
    cleanup_audit_trail
    cleanup_cross_account_roles
    cleanup_master_role
    cleanup_local_files
    
    # Verify cleanup
    if verify_cleanup; then
        echo
        success "=========================================="
        success "Cleanup completed successfully!"
        success "=========================================="
        echo
        info "All resources have been removed."
        info "The cross-account IAM role federation infrastructure has been completely cleaned up."
    else
        echo
        warning "=========================================="
        warning "Cleanup completed with warnings"
        warning "=========================================="
        echo
        warning "Some resources may still exist. Please check manually and remove if necessary."
    fi
    
    echo
    info "For detailed logs, check: $LOG_FILE"
}

# Parse command line arguments and run main function
parse_arguments "$@"
main