#!/bin/bash

# API Gateway Custom Domain Names - Cleanup Script
# This script safely removes all resources created by the deployment script
# including custom domains, API Gateway, Lambda functions, and DNS records

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
DRY_RUN=false
FORCE=false
INTERACTIVE=true

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [ -f "${SCRIPT_DIR}/.env" ]; then
        source "${SCRIPT_DIR}/.env"
        log_success "Environment loaded from ${SCRIPT_DIR}/.env"
    else
        log_error "Environment file not found: ${SCRIPT_DIR}/.env"
        log_error "Cannot proceed without deployment environment information"
        exit 1
    fi
    
    # Load additional deployment artifacts
    if [ -f "${SCRIPT_DIR}/.certificate_arn" ]; then
        CERTIFICATE_ARN=$(cat "${SCRIPT_DIR}/.certificate_arn")
    fi
    
    if [ -f "${SCRIPT_DIR}/.lambda_function_arn" ]; then
        LAMBDA_FUNCTION_ARN=$(cat "${SCRIPT_DIR}/.lambda_function_arn")
    fi
    
    if [ -f "${SCRIPT_DIR}/.authorizer_function_arn" ]; then
        AUTHORIZER_FUNCTION_ARN=$(cat "${SCRIPT_DIR}/.authorizer_function_arn")
    fi
    
    if [ -f "${SCRIPT_DIR}/.regional_domain" ]; then
        REGIONAL_DOMAIN=$(cat "${SCRIPT_DIR}/.regional_domain")
    fi
    
    if [ -f "${SCRIPT_DIR}/.hosted_zone_id" ]; then
        HOSTED_ZONE_ID=$(cat "${SCRIPT_DIR}/.hosted_zone_id")
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Confirmation prompt
confirm_action() {
    local message="$1"
    local default="$2"
    
    if [ "$FORCE" = true ]; then
        return 0
    fi
    
    if [ "$INTERACTIVE" = false ]; then
        return 0
    fi
    
    while true; do
        if [ "$default" = "y" ]; then
            read -p "$message [Y/n]: " yn
            yn=${yn:-y}
        else
            read -p "$message [y/N]: " yn
            yn=${yn:-n}
        fi
        
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Remove custom domain and base path mappings
remove_custom_domain() {
    log_info "Removing custom domain and base path mappings..."
    
    if [ -z "${API_SUBDOMAIN:-}" ]; then
        log_warning "API_SUBDOMAIN not set, skipping custom domain cleanup"
        return 0
    fi
    
    # Check if domain exists
    if ! aws apigateway get-domain-name --domain-name "${API_SUBDOMAIN}" >/dev/null 2>&1; then
        log_info "Custom domain does not exist: ${API_SUBDOMAIN}"
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would remove custom domain: ${API_SUBDOMAIN}"
        return 0
    fi
    
    # Remove all base path mappings
    log_info "Removing base path mappings..."
    
    local mappings=$(aws apigateway get-base-path-mappings \
        --domain-name "${API_SUBDOMAIN}" \
        --query 'items[].basePath' --output text 2>/dev/null || echo "")
    
    if [ -n "$mappings" ]; then
        echo "$mappings" | while read -r base_path; do
            if [ "$base_path" = "None" ] || [ -z "$base_path" ]; then
                base_path=""
            fi
            
            log_info "Removing base path mapping: '${base_path}'"
            aws apigateway delete-base-path-mapping \
                --domain-name "${API_SUBDOMAIN}" \
                --base-path "${base_path}" 2>/dev/null || \
                log_warning "Failed to remove base path mapping: ${base_path}"
        done
    fi
    
    # Remove custom domain
    log_info "Removing custom domain: ${API_SUBDOMAIN}"
    if aws apigateway delete-domain-name --domain-name "${API_SUBDOMAIN}" 2>/dev/null; then
        log_success "Custom domain removed: ${API_SUBDOMAIN}"
    else
        log_warning "Failed to remove custom domain or it doesn't exist"
    fi
}

# Remove DNS records
remove_dns_records() {
    log_info "Removing DNS records..."
    
    if [ -z "${HOSTED_ZONE_ID:-}" ] || [ -z "${API_SUBDOMAIN:-}" ] || [ -z "${REGIONAL_DOMAIN:-}" ]; then
        log_warning "Missing DNS information, skipping DNS cleanup"
        return 0
    fi
    
    # Check if DNS record exists
    local existing_record=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "${HOSTED_ZONE_ID}" \
        --query "ResourceRecordSets[?Name=='${API_SUBDOMAIN}.'].Type" \
        --output text 2>/dev/null || true)
    
    if [ -z "$existing_record" ] || [ "$existing_record" = "None" ]; then
        log_info "DNS record does not exist for ${API_SUBDOMAIN}"
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would remove DNS record: ${API_SUBDOMAIN}"
        return 0
    fi
    
    # Create delete DNS record change batch
    cat > "${SCRIPT_DIR}/delete-dns-record.json" << EOF
{
    "Changes": [{
        "Action": "DELETE",
        "ResourceRecordSet": {
            "Name": "${API_SUBDOMAIN}",
            "Type": "CNAME",
            "TTL": 300,
            "ResourceRecords": [{"Value": "${REGIONAL_DOMAIN}"}]
        }
    }]
}
EOF
    
    log_info "Removing DNS record for ${API_SUBDOMAIN}"
    if aws route53 change-resource-record-sets \
        --hosted-zone-id "${HOSTED_ZONE_ID}" \
        --change-batch "file://${SCRIPT_DIR}/delete-dns-record.json" >/dev/null 2>&1; then
        log_success "DNS record removed"
    else
        log_warning "Failed to remove DNS record or it doesn't exist"
    fi
    
    # Clean up temporary file
    rm -f "${SCRIPT_DIR}/delete-dns-record.json"
}

# Remove API Gateway
remove_api_gateway() {
    log_info "Removing API Gateway..."
    
    if [ -z "${REST_API_ID:-}" ]; then
        log_warning "REST_API_ID not set, skipping API Gateway cleanup"
        return 0
    fi
    
    # Check if API exists
    if ! aws apigateway get-rest-api --rest-api-id "${REST_API_ID}" >/dev/null 2>&1; then
        log_info "REST API does not exist: ${REST_API_ID}"
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would remove REST API: ${REST_API_ID}"
        return 0
    fi
    
    log_info "Removing REST API: ${REST_API_ID}"
    if aws apigateway delete-rest-api --rest-api-id "${REST_API_ID}" 2>/dev/null; then
        log_success "REST API removed: ${REST_API_ID}"
    else
        log_warning "Failed to remove REST API or it doesn't exist"
    fi
}

# Remove Lambda functions
remove_lambda_functions() {
    log_info "Removing Lambda functions..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would remove Lambda functions"
        return 0
    fi
    
    # Remove main Lambda function
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        log_info "Removing Lambda function: ${LAMBDA_FUNCTION_NAME}"
        if aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}" 2>/dev/null; then
            log_success "Lambda function removed: ${LAMBDA_FUNCTION_NAME}"
        else
            log_warning "Failed to remove Lambda function or it doesn't exist: ${LAMBDA_FUNCTION_NAME}"
        fi
    fi
    
    # Remove custom authorizer function
    if [ -n "${AUTHORIZER_FUNCTION_NAME:-}" ]; then
        log_info "Removing authorizer function: ${AUTHORIZER_FUNCTION_NAME}"
        if aws lambda delete-function --function-name "${AUTHORIZER_FUNCTION_NAME}" 2>/dev/null; then
            log_success "Authorizer function removed: ${AUTHORIZER_FUNCTION_NAME}"
        else
            log_warning "Failed to remove authorizer function or it doesn't exist: ${AUTHORIZER_FUNCTION_NAME}"
        fi
    fi
}

# Remove IAM roles
remove_iam_roles() {
    log_info "Removing IAM roles..."
    
    if [ -z "${LAMBDA_FUNCTION_NAME:-}" ]; then
        log_warning "LAMBDA_FUNCTION_NAME not set, skipping IAM role cleanup"
        return 0
    fi
    
    local role_name="${LAMBDA_FUNCTION_NAME}-role"
    
    # Check if role exists
    if ! aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
        log_info "IAM role does not exist: $role_name"
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would remove IAM role: $role_name"
        return 0
    fi
    
    log_info "Removing IAM role: $role_name"
    
    # Detach policies first
    local policies=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    
    if [ -n "$policies" ] && [ "$policies" != "None" ]; then
        echo "$policies" | while read -r policy_arn; do
            if [ -n "$policy_arn" ]; then
                log_info "Detaching policy: $policy_arn"
                aws iam detach-role-policy \
                    --role-name "$role_name" \
                    --policy-arn "$policy_arn" 2>/dev/null || \
                    log_warning "Failed to detach policy: $policy_arn"
            fi
        done
    fi
    
    # Delete the role
    if aws iam delete-role --role-name "$role_name" 2>/dev/null; then
        log_success "IAM role removed: $role_name"
    else
        log_warning "Failed to remove IAM role or it doesn't exist: $role_name"
    fi
}

# Remove SSL certificate
remove_ssl_certificate() {
    log_info "Removing SSL certificate..."
    
    if [ -z "${CERTIFICATE_ARN:-}" ]; then
        log_warning "CERTIFICATE_ARN not set, skipping certificate cleanup"
        return 0
    fi
    
    # Check if certificate exists
    if ! aws acm describe-certificate --certificate-arn "${CERTIFICATE_ARN}" >/dev/null 2>&1; then
        log_info "SSL certificate does not exist: ${CERTIFICATE_ARN}"
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would remove SSL certificate: ${CERTIFICATE_ARN}"
        return 0
    fi
    
    # Check if certificate is in use
    local cert_status=$(aws acm describe-certificate \
        --certificate-arn "${CERTIFICATE_ARN}" \
        --query 'Certificate.Status' --output text 2>/dev/null || echo "UNKNOWN")
    
    if [ "$cert_status" = "ISSUED" ]; then
        # Check if certificate is associated with any resources
        local in_use_by=$(aws acm describe-certificate \
            --certificate-arn "${CERTIFICATE_ARN}" \
            --query 'Certificate.InUseBy' --output text 2>/dev/null || echo "")
        
        if [ -n "$in_use_by" ] && [ "$in_use_by" != "None" ]; then
            log_warning "Certificate is still in use by other resources: ${in_use_by}"
            log_warning "Skipping certificate deletion for safety"
            return 0
        fi
    fi
    
    if confirm_action "Remove SSL certificate ${CERTIFICATE_ARN}?" "n"; then
        log_info "Removing SSL certificate: ${CERTIFICATE_ARN}"
        if aws acm delete-certificate --certificate-arn "${CERTIFICATE_ARN}" 2>/dev/null; then
            log_success "SSL certificate removed: ${CERTIFICATE_ARN}"
        else
            log_warning "Failed to remove SSL certificate or it's in use"
        fi
    else
        log_info "Skipping SSL certificate removal"
    fi
}

# Remove S3 bucket
remove_s3_bucket() {
    log_info "Removing S3 deployment bucket..."
    
    if [ -z "${DEPLOYMENT_BUCKET:-}" ]; then
        log_warning "DEPLOYMENT_BUCKET not set, skipping S3 cleanup"
        return 0
    fi
    
    # Check if bucket exists
    if ! aws s3 ls "s3://${DEPLOYMENT_BUCKET}" >/dev/null 2>&1; then
        log_info "S3 bucket does not exist: ${DEPLOYMENT_BUCKET}"
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would remove S3 bucket: ${DEPLOYMENT_BUCKET}"
        return 0
    fi
    
    log_info "Removing S3 bucket: ${DEPLOYMENT_BUCKET}"
    if aws s3 rb "s3://${DEPLOYMENT_BUCKET}" --force 2>/dev/null; then
        log_success "S3 bucket removed: ${DEPLOYMENT_BUCKET}"
    else
        log_warning "Failed to remove S3 bucket or it doesn't exist: ${DEPLOYMENT_BUCKET}"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    local files_to_remove=(
        "${SCRIPT_DIR}/.env"
        "${SCRIPT_DIR}/.certificate_arn"
        "${SCRIPT_DIR}/.lambda_function_arn"
        "${SCRIPT_DIR}/.authorizer_function_arn"
        "${SCRIPT_DIR}/.regional_domain"
        "${SCRIPT_DIR}/.hosted_zone_id"
        "${SCRIPT_DIR}/.authorizer_id"
        "${SCRIPT_DIR}/.deployment_id"
        "${SCRIPT_DIR}/lambda-trust-policy.json"
        "${SCRIPT_DIR}/lambda-function.py"
        "${SCRIPT_DIR}/lambda-function.zip"
        "${SCRIPT_DIR}/authorizer-function.py"
        "${SCRIPT_DIR}/authorizer-function.zip"
        "${SCRIPT_DIR}/dns-record.json"
        "${SCRIPT_DIR}/delete-dns-record.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            log_info "Removing file: $(basename "$file")"
            rm -f "$file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local issues=0
    
    # Check custom domain
    if [ -n "${API_SUBDOMAIN:-}" ]; then
        if aws apigateway get-domain-name --domain-name "${API_SUBDOMAIN}" >/dev/null 2>&1; then
            log_warning "Custom domain still exists: ${API_SUBDOMAIN}"
            ((issues++))
        fi
    fi
    
    # Check API Gateway
    if [ -n "${REST_API_ID:-}" ]; then
        if aws apigateway get-rest-api --rest-api-id "${REST_API_ID}" >/dev/null 2>&1; then
            log_warning "REST API still exists: ${REST_API_ID}"
            ((issues++))
        fi
    fi
    
    # Check Lambda functions
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1; then
            log_warning "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
            ((issues++))
        fi
    fi
    
    if [ -n "${AUTHORIZER_FUNCTION_NAME:-}" ]; then
        if aws lambda get-function --function-name "${AUTHORIZER_FUNCTION_NAME}" >/dev/null 2>&1; then
            log_warning "Authorizer function still exists: ${AUTHORIZER_FUNCTION_NAME}"
            ((issues++))
        fi
    fi
    
    # Check IAM role
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        local role_name="${LAMBDA_FUNCTION_NAME}-role"
        if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
            log_warning "IAM role still exists: $role_name"
            ((issues++))
        fi
    fi
    
    # Check S3 bucket
    if [ -n "${DEPLOYMENT_BUCKET:-}" ]; then
        if aws s3 ls "s3://${DEPLOYMENT_BUCKET}" >/dev/null 2>&1; then
            log_warning "S3 bucket still exists: ${DEPLOYMENT_BUCKET}"
            ((issues++))
        fi
    fi
    
    if [ $issues -eq 0 ]; then
        log_success "Cleanup verification passed - all resources removed"
    else
        log_warning "Cleanup verification found $issues issues"
        log_warning "Some resources may still exist and require manual cleanup"
    fi
    
    return $issues
}

# Print cleanup summary
print_summary() {
    log_success "=== CLEANUP SUMMARY ==="
    log_info "Custom Domain: ${API_SUBDOMAIN:-N/A}"
    log_info "REST API ID: ${REST_API_ID:-N/A}"
    log_info "Lambda Function: ${LAMBDA_FUNCTION_NAME:-N/A}"
    log_info "Authorizer Function: ${AUTHORIZER_FUNCTION_NAME:-N/A}"
    log_info "Certificate ARN: ${CERTIFICATE_ARN:-N/A}"
    log_info "S3 Bucket: ${DEPLOYMENT_BUCKET:-N/A}"
    log_info ""
    
    if [ "$DRY_RUN" = true ]; then
        log_info "This was a dry run - no resources were actually removed"
        log_info "Run without --dry-run to perform actual cleanup"
    else
        log_success "Cleanup completed!"
        log_info "Log file: ${LOG_FILE}"
    fi
}

# Main cleanup function
main() {
    log_info "Starting API Gateway Custom Domain cleanup..."
    log_info "Log file: ${LOG_FILE}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN MODE - No resources will be removed"
    fi
    
    # Load environment and check prerequisites
    load_environment
    check_prerequisites
    
    # Show what will be removed
    log_info "Resources to be removed:"
    log_info "  - Custom Domain: ${API_SUBDOMAIN:-N/A}"
    log_info "  - REST API: ${REST_API_ID:-N/A}"
    log_info "  - Lambda Functions: ${LAMBDA_FUNCTION_NAME:-N/A}, ${AUTHORIZER_FUNCTION_NAME:-N/A}"
    log_info "  - IAM Role: ${LAMBDA_FUNCTION_NAME:-N/A}-role"
    log_info "  - SSL Certificate: ${CERTIFICATE_ARN:-N/A}"
    log_info "  - S3 Bucket: ${DEPLOYMENT_BUCKET:-N/A}"
    log_info ""
    
    # Confirm destruction
    if [ "$DRY_RUN" = false ]; then
        if ! confirm_action "Are you sure you want to remove all these resources?" "n"; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute cleanup steps in safe order
    remove_custom_domain
    remove_dns_records
    remove_api_gateway
    remove_lambda_functions
    remove_iam_roles
    remove_ssl_certificate
    remove_s3_bucket
    cleanup_local_files
    
    # Verify and summarize
    if [ "$DRY_RUN" = false ]; then
        verify_cleanup
    fi
    print_summary
}

# Show usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Remove all resources created by the API Gateway Custom Domain deployment"
    echo ""
    echo "Options:"
    echo "  -h, --help         Show this help message"
    echo "  -n, --dry-run      Show what would be removed without actually removing"
    echo "  -f, --force        Skip confirmation prompts"
    echo "  -y, --yes          Non-interactive mode (same as --force)"
    echo "  -v, --verbose      Enable verbose logging"
    echo ""
    echo "Examples:"
    echo "  $0                 Interactive cleanup with confirmations"
    echo "  $0 --dry-run       Preview what would be removed"
    echo "  $0 --force         Remove all resources without prompts"
    echo "  $0 -n -v          Dry run with verbose output"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force|-y|--yes)
            FORCE=true
            INTERACTIVE=false
            shift
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@"