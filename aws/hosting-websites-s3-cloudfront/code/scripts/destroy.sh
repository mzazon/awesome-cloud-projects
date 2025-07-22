#!/bin/bash

# Static Website Hosting Cleanup Script
# This script removes all resources created for the static website hosting solution
# Based on the recipe: Building Static Website Hosting with S3, CloudFront, and Route 53

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warn "Running in DRY RUN mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE=true
            info "Force mode enabled - skipping confirmation prompts"
            shift
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Function to execute commands with dry-run support
execute() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: $1"
    else
        eval "$1"
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or you don't have valid credentials."
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some features may not work properly."
    fi
    
    info "Prerequisites check passed"
}

# Function to load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [[ -f "deployment-info.json" ]]; then
        export DOMAIN_NAME=$(jq -r '.domain_name' deployment-info.json)
        export SUBDOMAIN=$(jq -r '.subdomain' deployment-info.json)
        export ROOT_BUCKET=$(jq -r '.root_bucket' deployment-info.json)
        export WWW_BUCKET=$(jq -r '.www_bucket' deployment-info.json)
        export CERT_ARN=$(jq -r '.certificate_arn' deployment-info.json)
        export CF_DISTRIBUTION_ID=$(jq -r '.cloudfront_distribution_id' deployment-info.json)
        export CF_DOMAIN_NAME=$(jq -r '.cloudfront_domain' deployment-info.json)
        export HOSTED_ZONE_ID=$(jq -r '.hosted_zone_id' deployment-info.json)
        export AWS_REGION=$(jq -r '.aws_region' deployment-info.json)
        export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' deployment-info.json)
        
        info "Loaded deployment information from deployment-info.json"
        info "Domain: $DOMAIN_NAME"
        info "CloudFront Distribution: $CF_DISTRIBUTION_ID"
        info "Certificate ARN: $CERT_ARN"
    else
        warn "deployment-info.json not found. Manual input required."
        get_manual_input
    fi
}

# Function to get manual input if deployment info file is missing
get_manual_input() {
    log "Getting manual input for cleanup..."
    
    if [[ -z "${DOMAIN_NAME:-}" ]]; then
        read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
    fi
    
    export SUBDOMAIN="www.${DOMAIN_NAME}"
    export ROOT_BUCKET="${DOMAIN_NAME}"
    export WWW_BUCKET="${SUBDOMAIN}"
    
    # Try to find resources automatically
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Try to find hosted zone
    export HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN_NAME" --query "HostedZones[0].Id" --output text 2>/dev/null | cut -d'/' -f3 || echo "")
    
    # Try to find certificate
    export CERT_ARN=$(aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn" --output text 2>/dev/null || echo "")
    
    # Try to find CloudFront distribution
    export CF_DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Aliases.Items[0]=='$SUBDOMAIN'].Id" --output text 2>/dev/null || echo "")
    
    if [[ -n "$CF_DISTRIBUTION_ID" ]]; then
        export CF_DOMAIN_NAME=$(aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" --query 'Distribution.DomainName' --output text 2>/dev/null || echo "")
    fi
    
    info "Manual input collected"
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    warn "This will permanently delete the following resources:"
    echo "  - S3 Buckets: $ROOT_BUCKET, $WWW_BUCKET"
    echo "  - CloudFront Distribution: $CF_DISTRIBUTION_ID"
    echo "  - SSL Certificate: $CERT_ARN"
    echo "  - DNS Records for: $DOMAIN_NAME, $SUBDOMAIN"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    warn "Starting cleanup in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
}

# Function to disable CloudFront distribution
disable_cloudfront_distribution() {
    log "Disabling CloudFront distribution..."
    
    if [[ -z "$CF_DISTRIBUTION_ID" ]]; then
        warn "No CloudFront distribution ID found, skipping..."
        return 0
    fi
    
    # Check if distribution exists
    if ! aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" >/dev/null 2>&1; then
        warn "CloudFront distribution $CF_DISTRIBUTION_ID not found, skipping..."
        return 0
    fi
    
    # Get current distribution configuration
    local etag=$(aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" --query 'ETag' --output text)
    
    # Get distribution config and disable it
    aws cloudfront get-distribution-config --id "$CF_DISTRIBUTION_ID" --query 'DistributionConfig' > /tmp/cf-config.json
    
    # Modify config to disable distribution
    jq '.Enabled = false' /tmp/cf-config.json > /tmp/cf-config-disabled.json
    
    # Update distribution to disable it
    execute "aws cloudfront update-distribution --id '$CF_DISTRIBUTION_ID' --distribution-config file:///tmp/cf-config-disabled.json --if-match '$etag'"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "Waiting for CloudFront distribution to be disabled..."
        aws cloudfront wait distribution-deployed --id "$CF_DISTRIBUTION_ID"
    fi
    
    info "CloudFront distribution disabled"
}

# Function to delete DNS records
delete_dns_records() {
    log "Deleting DNS records..."
    
    if [[ -z "$HOSTED_ZONE_ID" ]]; then
        warn "No hosted zone ID found, skipping DNS record deletion..."
        return 0
    fi
    
    # Delete WWW subdomain A record
    if [[ -n "$CF_DOMAIN_NAME" ]]; then
        cat > /tmp/delete-www-dns.json << EOF
{
    "Changes": [
        {
            "Action": "DELETE",
            "ResourceRecordSet": {
                "Name": "$SUBDOMAIN",
                "Type": "A",
                "AliasTarget": {
                    "DNSName": "$CF_DOMAIN_NAME",
                    "EvaluateTargetHealth": false,
                    "HostedZoneId": "Z2FDTNDATAQYW2"
                }
            }
        }
    ]
}
EOF
        
        execute "aws route53 change-resource-record-sets --hosted-zone-id '$HOSTED_ZONE_ID' --change-batch file:///tmp/delete-www-dns.json" || warn "Failed to delete WWW DNS record"
    fi
    
    # Delete root domain A record
    local s3_hosted_zone_id
    case "$AWS_REGION" in
        us-east-1) s3_hosted_zone_id="Z3AQBSTGFYJSTF" ;;
        us-west-1) s3_hosted_zone_id="Z2F56UZL2M1ACD" ;;
        us-west-2) s3_hosted_zone_id="Z3BJ6K6RIION7M" ;;
        eu-west-1) s3_hosted_zone_id="Z1BKCTXD74EZPE" ;;
        eu-central-1) s3_hosted_zone_id="Z21DNDUVLTQW6Q" ;;
        ap-southeast-1) s3_hosted_zone_id="Z3O0SRN1WG7CG" ;;
        ap-northeast-1) s3_hosted_zone_id="Z2M4EHUR26P7ZW" ;;
        *) s3_hosted_zone_id="Z3AQBSTGFYJSTF" ;;
    esac
    
    cat > /tmp/delete-root-dns.json << EOF
{
    "Changes": [
        {
            "Action": "DELETE",
            "ResourceRecordSet": {
                "Name": "$DOMAIN_NAME",
                "Type": "A",
                "AliasTarget": {
                    "DNSName": "$ROOT_BUCKET.s3-website-$AWS_REGION.amazonaws.com",
                    "EvaluateTargetHealth": false,
                    "HostedZoneId": "$s3_hosted_zone_id"
                }
            }
        }
    ]
}
EOF
    
    execute "aws route53 change-resource-record-sets --hosted-zone-id '$HOSTED_ZONE_ID' --change-batch file:///tmp/delete-root-dns.json" || warn "Failed to delete root DNS record"
    
    info "DNS records deleted"
}

# Function to delete CloudFront distribution
delete_cloudfront_distribution() {
    log "Deleting CloudFront distribution..."
    
    if [[ -z "$CF_DISTRIBUTION_ID" ]]; then
        warn "No CloudFront distribution ID found, skipping..."
        return 0
    fi
    
    # Check if distribution exists
    if ! aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" >/dev/null 2>&1; then
        warn "CloudFront distribution $CF_DISTRIBUTION_ID not found, skipping..."
        return 0
    fi
    
    # Get current etag
    local etag=$(aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" --query 'ETag' --output text)
    
    # Delete distribution
    execute "aws cloudfront delete-distribution --id '$CF_DISTRIBUTION_ID' --if-match '$etag'"
    
    info "CloudFront distribution deleted"
}

# Function to delete certificate validation records
delete_certificate_validation_records() {
    log "Deleting certificate validation records..."
    
    if [[ -z "$CERT_ARN" || -z "$HOSTED_ZONE_ID" ]]; then
        warn "Certificate ARN or hosted zone ID not found, skipping validation record deletion..."
        return 0
    fi
    
    # Get validation records
    local validation_records=$(aws acm describe-certificate \
        --certificate-arn "$CERT_ARN" \
        --region us-east-1 \
        --query 'Certificate.DomainValidationOptions[*].[DomainName,ResourceRecord.Name,ResourceRecord.Value]' \
        --output json 2>/dev/null || echo "[]")
    
    if [[ "$validation_records" == "[]" ]]; then
        info "No validation records found"
        return 0
    fi
    
    # Delete validation records
    echo "$validation_records" | jq -r '.[] | @base64' | while read -r record; do
        local domain=$(echo "$record" | base64 -d | jq -r '.[0]')
        local name=$(echo "$record" | base64 -d | jq -r '.[1]')
        local value=$(echo "$record" | base64 -d | jq -r '.[2]')
        
        info "Deleting validation record for domain: $domain"
        
        cat > /tmp/delete-validation-record.json << EOF
{
    "Changes": [
        {
            "Action": "DELETE",
            "ResourceRecordSet": {
                "Name": "$name",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [
                    {
                        "Value": "$value"
                    }
                ]
            }
        }
    ]
}
EOF
        
        execute "aws route53 change-resource-record-sets --hosted-zone-id '$HOSTED_ZONE_ID' --change-batch file:///tmp/delete-validation-record.json" || warn "Failed to delete validation record for $domain"
    done
    
    info "Certificate validation records deleted"
}

# Function to delete SSL certificate
delete_ssl_certificate() {
    log "Deleting SSL certificate..."
    
    if [[ -z "$CERT_ARN" ]]; then
        warn "No certificate ARN found, skipping..."
        return 0
    fi
    
    # Check if certificate exists
    if ! aws acm describe-certificate --certificate-arn "$CERT_ARN" --region us-east-1 >/dev/null 2>&1; then
        warn "Certificate $CERT_ARN not found, skipping..."
        return 0
    fi
    
    # Delete certificate
    execute "aws acm delete-certificate --certificate-arn '$CERT_ARN' --region us-east-1"
    
    info "SSL certificate deleted"
}

# Function to empty and delete S3 buckets
delete_s3_buckets() {
    log "Deleting S3 buckets..."
    
    # Delete WWW bucket
    if aws s3api head-bucket --bucket "$WWW_BUCKET" 2>/dev/null; then
        info "Emptying and deleting bucket: $WWW_BUCKET"
        execute "aws s3 rm 's3://$WWW_BUCKET' --recursive"
        execute "aws s3api delete-bucket --bucket '$WWW_BUCKET'"
    else
        warn "Bucket $WWW_BUCKET not found, skipping..."
    fi
    
    # Delete root bucket
    if aws s3api head-bucket --bucket "$ROOT_BUCKET" 2>/dev/null; then
        info "Emptying and deleting bucket: $ROOT_BUCKET"
        execute "aws s3 rm 's3://$ROOT_BUCKET' --recursive"
        execute "aws s3api delete-bucket --bucket '$ROOT_BUCKET'"
    else
        warn "Bucket $ROOT_BUCKET not found, skipping..."
    fi
    
    info "S3 buckets deleted"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f /tmp/cf-config.json /tmp/cf-config-disabled.json
    rm -f /tmp/delete-www-dns.json /tmp/delete-root-dns.json
    rm -f /tmp/delete-validation-record.json
    
    # Remove deployment info file if it exists
    if [[ -f "deployment-info.json" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            rm -f deployment-info.json
            info "Removed deployment-info.json"
        else
            info "DRY RUN: Would remove deployment-info.json"
        fi
    fi
    
    info "Temporary files cleaned up"
}

# Function to wait for resource cleanup
wait_for_cleanup() {
    log "Waiting for resource cleanup to complete..."
    
    # Wait for DNS propagation
    info "Waiting for DNS changes to propagate..."
    sleep 60
    
    info "Cleanup wait period completed"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local cleanup_success=true
    
    # Check if S3 buckets are deleted
    if aws s3api head-bucket --bucket "$WWW_BUCKET" 2>/dev/null; then
        warn "WWW bucket still exists: $WWW_BUCKET"
        cleanup_success=false
    else
        info "✅ WWW bucket deleted successfully"
    fi
    
    if aws s3api head-bucket --bucket "$ROOT_BUCKET" 2>/dev/null; then
        warn "Root bucket still exists: $ROOT_BUCKET"
        cleanup_success=false
    else
        info "✅ Root bucket deleted successfully"
    fi
    
    # Check if CloudFront distribution is deleted
    if [[ -n "$CF_DISTRIBUTION_ID" ]]; then
        if aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" >/dev/null 2>&1; then
            warn "CloudFront distribution still exists: $CF_DISTRIBUTION_ID"
            cleanup_success=false
        else
            info "✅ CloudFront distribution deleted successfully"
        fi
    fi
    
    # Check if certificate is deleted
    if [[ -n "$CERT_ARN" ]]; then
        if aws acm describe-certificate --certificate-arn "$CERT_ARN" --region us-east-1 >/dev/null 2>&1; then
            warn "SSL certificate still exists: $CERT_ARN"
            cleanup_success=false
        else
            info "✅ SSL certificate deleted successfully"
        fi
    fi
    
    # Test website accessibility (should return error)
    info "Testing website accessibility (should fail)..."
    local https_response=$(curl -s -o /dev/null -w "%{http_code}" "https://$SUBDOMAIN" 2>/dev/null || echo "000")
    if [[ "$https_response" == "000" || "$https_response" == "404" || "$https_response" == "403" ]]; then
        info "✅ Website is no longer accessible"
    else
        warn "Website still accessible (DNS may still be cached): $https_response"
    fi
    
    if [[ "$cleanup_success" == "true" ]]; then
        info "✅ Cleanup validation passed"
    else
        warn "Some resources may still exist. Please check manually."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "===================="
    echo "Domain Name: $DOMAIN_NAME"
    echo "Subdomain: $SUBDOMAIN"
    echo "Root Bucket: $ROOT_BUCKET (deleted)"
    echo "WWW Bucket: $WWW_BUCKET (deleted)"
    echo "CloudFront Distribution: $CF_DISTRIBUTION_ID (deleted)"
    echo "Certificate ARN: $CERT_ARN (deleted)"
    echo "===================="
    echo ""
    info "Static website resources have been cleaned up!"
    echo ""
    warn "Note: DNS changes may take up to 24 hours to propagate globally"
    warn "Some cached content may still be available temporarily"
    echo ""
}

# Main execution function
main() {
    log "Starting static website cleanup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment information
    load_deployment_info
    
    # Confirm destruction
    confirm_destruction
    
    # Disable CloudFront distribution first
    disable_cloudfront_distribution
    
    # Delete DNS records
    delete_dns_records
    
    # Delete CloudFront distribution
    delete_cloudfront_distribution
    
    # Delete certificate validation records
    delete_certificate_validation_records
    
    # Delete SSL certificate
    delete_ssl_certificate
    
    # Delete S3 buckets
    delete_s3_buckets
    
    # Wait for cleanup
    wait_for_cleanup
    
    # Validate cleanup
    validate_cleanup
    
    # Display summary
    display_cleanup_summary
    
    # Cleanup temporary files
    cleanup_temp_files
    
    log "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Script interrupted by user"' INT TERM

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --dry-run    Show what would be deleted without actually deleting"
    echo "  --force      Skip confirmation prompts"
    echo "  --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive cleanup with confirmations"
    echo "  $0 --dry-run          # Preview what would be deleted"
    echo "  $0 --force            # Skip confirmations"
    echo "  $0 --dry-run --force  # Preview without prompts"
}

# Check for help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_usage
    exit 0
fi

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi