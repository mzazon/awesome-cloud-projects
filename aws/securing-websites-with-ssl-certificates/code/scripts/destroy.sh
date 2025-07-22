#!/bin/bash

# Destroy script for Securing Websites with SSL Certificates
# This script safely removes all resources created by the deploy script

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ENV_FILE="${SCRIPT_DIR}/.env"

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  WARNING: $*" | tee -a "${LOG_FILE}"
}

# Cleanup function for temporary files
cleanup() {
    log "Cleaning up temporary files..."
    rm -f bucket-policy.json dns-records.json dns-delete.json disabled-config.json
}

# Trap for cleanup on exit
trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON processing"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load environment variables from deployment
load_environment() {
    log "Loading environment variables from deployment..."
    
    if [[ ! -f "${ENV_FILE}" ]]; then
        log_error "Environment file not found: ${ENV_FILE}"
        log_error "This script requires variables from a previous deployment"
        log_error "Please ensure you run this script from the same location as deploy.sh"
        exit 1
    fi
    
    # Source environment variables
    source "${ENV_FILE}"
    
    # Verify required variables are loaded
    local required_vars=("CERTIFICATE_ARN" "DISTRIBUTION_ID" "BUCKET_NAME")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("${var}")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Please check your .env file or re-run the deployment"
        exit 1
    fi
    
    # Set AWS configuration
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log_success "Environment variables loaded successfully"
    log "Certificate ARN: ${CERTIFICATE_ARN}"
    log "Distribution ID: ${DISTRIBUTION_ID}"
    log "Bucket Name: ${BUCKET_NAME}"
}

# Confirmation prompt
confirm_destruction() {
    log "⚠️  WARNING: This will permanently delete the following resources:"
    log "   - CloudFront Distribution: ${DISTRIBUTION_ID}"
    log "   - SSL Certificate: ${CERTIFICATE_ARN}"
    log "   - S3 Bucket and all contents: ${BUCKET_NAME}"
    if [[ -n "${HOSTED_ZONE_ID:-}" ]]; then
        log "   - DNS Records in hosted zone: ${HOSTED_ZONE_ID}"
    fi
    log ""
    log "This action cannot be undone!"
    log ""
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log "Force destroy mode enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    if [[ "${confirmation}" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed, proceeding..."
}

# Delete CloudFront distribution
delete_cloudfront_distribution() {
    log "Deleting CloudFront distribution..."
    
    # Check if distribution exists
    if ! aws cloudfront get-distribution --id "${DISTRIBUTION_ID}" &> /dev/null; then
        log_warning "CloudFront distribution ${DISTRIBUTION_ID} not found, skipping"
        return 0
    fi
    
    # Get current distribution configuration and ETag
    local config_output
    config_output=$(aws cloudfront get-distribution-config --id "${DISTRIBUTION_ID}")
    
    local distribution_config
    distribution_config=$(echo "${config_output}" | jq -c '.DistributionConfig')
    
    local etag
    etag=$(echo "${config_output}" | jq -r '.ETag')
    
    # Disable distribution first
    log "Disabling CloudFront distribution..."
    local disabled_config
    disabled_config=$(echo "${distribution_config}" | jq '.Enabled = false')
    
    aws cloudfront update-distribution \
        --id "${DISTRIBUTION_ID}" \
        --distribution-config "${disabled_config}" \
        --if-match "${etag}" > /dev/null
    
    # Wait for distribution to be disabled
    log "Waiting for distribution to be disabled (this may take several minutes)..."
    aws cloudfront wait distribution-deployed --id "${DISTRIBUTION_ID}"
    
    # Get new ETag after update
    local new_etag
    new_etag=$(aws cloudfront get-distribution-config \
        --id "${DISTRIBUTION_ID}" \
        --query 'ETag' \
        --output text)
    
    # Delete distribution
    log "Deleting CloudFront distribution..."
    aws cloudfront delete-distribution \
        --id "${DISTRIBUTION_ID}" \
        --if-match "${new_etag}"
    
    log_success "CloudFront distribution deletion initiated"
}

# Delete SSL certificate
delete_ssl_certificate() {
    log "Deleting SSL certificate..."
    
    # Check if certificate exists
    if ! aws acm describe-certificate --certificate-arn "${CERTIFICATE_ARN}" --region us-east-1 &> /dev/null; then
        log_warning "SSL certificate ${CERTIFICATE_ARN} not found, skipping"
        return 0
    fi
    
    # Check if certificate is in use
    local cert_status
    cert_status=$(aws acm describe-certificate \
        --certificate-arn "${CERTIFICATE_ARN}" \
        --region us-east-1 \
        --query 'Certificate.Status' \
        --output text)
    
    if [[ "${cert_status}" == "ISSUED" ]]; then
        # Check if certificate is still in use by CloudFront
        local in_use
        in_use=$(aws acm describe-certificate \
            --certificate-arn "${CERTIFICATE_ARN}" \
            --region us-east-1 \
            --query 'Certificate.InUseBy' \
            --output text)
        
        if [[ "${in_use}" != "None" && "${in_use}" != "" ]]; then
            log_warning "Certificate is still in use by CloudFront. Waiting for CloudFront deletion to complete..."
            sleep 30
        fi
    fi
    
    # Delete certificate
    if aws acm delete-certificate --certificate-arn "${CERTIFICATE_ARN}" --region us-east-1; then
        log_success "SSL certificate deleted"
    else
        log_warning "Failed to delete SSL certificate (may still be in use)"
    fi
}

# Remove DNS records
remove_dns_records() {
    log "Removing DNS records..."
    
    # Check if hosted zone ID is available
    if [[ -z "${HOSTED_ZONE_ID:-}" ]]; then
        log "No hosted zone ID found, skipping DNS record removal"
        return 0
    fi
    
    # Check if hosted zone exists
    if ! aws route53 get-hosted-zone --id "${HOSTED_ZONE_ID}" &> /dev/null; then
        log_warning "Hosted zone ${HOSTED_ZONE_ID} not found, skipping DNS record removal"
        return 0
    fi
    
    # Get CloudFront domain name for deletion
    local cloudfront_domain="${CLOUDFRONT_DOMAIN:-}"
    if [[ -z "${cloudfront_domain}" ]]; then
        log_warning "CloudFront domain not found in environment, skipping DNS record removal"
        return 0
    fi
    
    # Create DNS deletion records
    cat > dns-delete.json << EOF
{
    "Changes": [
        {
            "Action": "DELETE",
            "ResourceRecordSet": {
                "Name": "${DOMAIN_NAME:-example.com}",
                "Type": "A",
                "AliasTarget": {
                    "DNSName": "${cloudfront_domain}",
                    "EvaluateTargetHealth": false,
                    "HostedZoneId": "Z2FDTNDATAQYW2"
                }
            }
        },
        {
            "Action": "DELETE",
            "ResourceRecordSet": {
                "Name": "${SUBDOMAIN:-www.example.com}",
                "Type": "A",
                "AliasTarget": {
                    "DNSName": "${cloudfront_domain}",
                    "EvaluateTargetHealth": false,
                    "HostedZoneId": "Z2FDTNDATAQYW2"
                }
            }
        }
    ]
}
EOF
    
    # Remove DNS records
    if aws route53 change-resource-record-sets \
        --hosted-zone-id "${HOSTED_ZONE_ID}" \
        --change-batch file://dns-delete.json &> /dev/null; then
        log_success "DNS records removed"
    else
        log_warning "Failed to remove DNS records (may not exist)"
    fi
}

# Delete S3 bucket and contents
delete_s3_bucket() {
    log "Deleting S3 bucket and contents..."
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        log_warning "S3 bucket ${BUCKET_NAME} not found, skipping"
        return 0
    fi
    
    # Remove all objects from bucket (including versions)
    log "Removing all objects from S3 bucket..."
    aws s3 rm s3://${BUCKET_NAME} --recursive
    
    # Remove all object versions and delete markers
    log "Removing object versions and delete markers..."
    aws s3api list-object-versions --bucket "${BUCKET_NAME}" \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' \
        --output text | while read key version_id; do
        if [[ -n "${key}" && -n "${version_id}" ]]; then
            aws s3api delete-object --bucket "${BUCKET_NAME}" --key "${key}" --version-id "${version_id}" > /dev/null
        fi
    done
    
    # Remove delete markers
    aws s3api list-object-versions --bucket "${BUCKET_NAME}" \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
        --output text | while read key version_id; do
        if [[ -n "${key}" && -n "${version_id}" ]]; then
            aws s3api delete-object --bucket "${BUCKET_NAME}" --key "${key}" --version-id "${version_id}" > /dev/null
        fi
    done
    
    # Delete bucket
    aws s3 rb s3://${BUCKET_NAME}
    
    log_success "S3 bucket and contents deleted"
}

# Clean up Origin Access Control
delete_origin_access_control() {
    log "Deleting Origin Access Control..."
    
    if [[ -z "${OAC_ID:-}" ]]; then
        log "No Origin Access Control ID found, skipping"
        return 0
    fi
    
    # Check if OAC exists
    if ! aws cloudfront get-origin-access-control --id "${OAC_ID}" &> /dev/null; then
        log_warning "Origin Access Control ${OAC_ID} not found, skipping"
        return 0
    fi
    
    # Get ETag for deletion
    local etag
    etag=$(aws cloudfront get-origin-access-control \
        --id "${OAC_ID}" \
        --query 'ETag' \
        --output text)
    
    # Delete OAC
    if aws cloudfront delete-origin-access-control \
        --id "${OAC_ID}" \
        --if-match "${etag}"; then
        log_success "Origin Access Control deleted"
    else
        log_warning "Failed to delete Origin Access Control (may still be in use)"
    fi
}

# Clean up local files
clean_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f "${ENV_FILE}" ]]; then
        rm -f "${ENV_FILE}"
        log_success "Environment file removed"
    fi
    
    # Remove any temporary files that might exist
    rm -f "${SCRIPT_DIR}/index.html" "${SCRIPT_DIR}/error.html"
    
    log_success "Local files cleaned up"
}

# Verify destruction
verify_destruction() {
    log "Verifying resource destruction..."
    
    local verification_errors=0
    
    # Check CloudFront distribution
    if aws cloudfront get-distribution --id "${DISTRIBUTION_ID}" &> /dev/null; then
        log_warning "CloudFront distribution still exists (deletion may be in progress)"
        verification_errors=$((verification_errors + 1))
    fi
    
    # Check SSL certificate
    if aws acm describe-certificate --certificate-arn "${CERTIFICATE_ARN}" --region us-east-1 &> /dev/null; then
        log_warning "SSL certificate still exists"
        verification_errors=$((verification_errors + 1))
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        log_warning "S3 bucket still exists"
        verification_errors=$((verification_errors + 1))
    fi
    
    if [[ ${verification_errors} -eq 0 ]]; then
        log_success "All resources successfully destroyed"
    else
        log_warning "${verification_errors} resources may still exist or be in deletion process"
    fi
}

# Print destruction summary
print_summary() {
    log "============================================"
    log "           DESTRUCTION SUMMARY"
    log "============================================"
    log "Resources removed:"
    log "✅ CloudFront Distribution: ${DISTRIBUTION_ID}"
    log "✅ SSL Certificate: ${CERTIFICATE_ARN}"
    log "✅ S3 Bucket: ${BUCKET_NAME}"
    if [[ -n "${HOSTED_ZONE_ID:-}" ]]; then
        log "✅ DNS Records in hosted zone: ${HOSTED_ZONE_ID}"
    fi
    if [[ -n "${OAC_ID:-}" ]]; then
        log "✅ Origin Access Control: ${OAC_ID}"
    fi
    log "✅ Local environment files"
    log "============================================"
    log ""
    log "🎉 Destruction completed successfully!"
    log ""
    log "Note: CloudFront distributions may take up to 15 minutes to fully delete."
    log "Certificate deletion may be delayed if still referenced by CloudFront."
    log ""
    log "Destruction logs saved to: ${LOG_FILE}"
}

# Main destruction function
main() {
    log "Starting destruction of secure static website resources"
    log "======================================================"
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    # Delete resources in reverse order of creation
    remove_dns_records
    delete_cloudfront_distribution
    delete_origin_access_control
    delete_ssl_certificate
    delete_s3_bucket
    clean_local_files
    
    verify_destruction
    print_summary
    
    log "Destruction completed successfully! 🎉"
}

# Script usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy resources created by the secure static website deployment.

Options:
    -f, --force     Force destruction without confirmation prompt
    -h, --help      Show this help message

Environment:
    FORCE_DESTROY=true    Force destruction without confirmation (alternative to -f)

This script will remove:
- CloudFront Distribution
- SSL Certificate (ACM)
- S3 Bucket and all contents
- DNS Records (if Route 53 hosted zone was used)
- Origin Access Control
- Local environment files

Prerequisites:
- AWS CLI installed and configured
- jq installed for JSON processing
- Must be run from the same location as deploy.sh
- .env file from previous deployment must exist

Example:
    $0                    # Interactive destruction with confirmation
    $0 --force           # Force destruction without confirmation
    FORCE_DESTROY=true $0 # Alternative force method

For more information, see the recipe documentation.
EOF
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            export FORCE_DESTROY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
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