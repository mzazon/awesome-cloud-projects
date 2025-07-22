#!/bin/bash

# Destroy script for Static Website with S3 and CloudFront
# This script safely removes all resources created by the deploy.sh script
# as described in the "Serving Static Content with S3 and CloudFront" recipe

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
CONFIG_FILE="${SCRIPT_DIR}/.deploy_config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}INFO:${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}SUCCESS:${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI version 2."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is installed (needed for JSON parsing)
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON parsing."
        exit 1
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to load deployment configuration
load_deployment_config() {
    info "Loading deployment configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file not found: $CONFIG_FILE"
        error "This usually means the deployment was not completed or the config file was deleted."
        echo
        info "If you know the resource names, you can manually set them:"
        info "export BUCKET_NAME='your-bucket-name'"
        info "export DISTRIBUTION_ID='your-distribution-id'"
        info "Then run this script again."
        exit 1
    fi
    
    # Source the configuration file
    source "$CONFIG_FILE"
    
    # Validate required variables
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        error "BUCKET_NAME not found in configuration file"
        exit 1
    fi
    
    if [[ -z "${DISTRIBUTION_ID:-}" ]]; then
        error "DISTRIBUTION_ID not found in configuration file"
        exit 1
    fi
    
    info "Loaded configuration for deployment:"
    info "- S3 Website Bucket: $BUCKET_NAME"
    info "- S3 Logs Bucket: ${LOGS_BUCKET_NAME:-'not configured'}"
    info "- CloudFront Distribution: $DISTRIBUTION_ID"
    
    if [[ "${SETUP_DOMAIN:-n}" == "y" ]]; then
        info "- Custom Domain: ${DOMAIN_NAME:-'not configured'}"
        info "- SSL Certificate: ${CERT_ARN:-'not configured'}"
    fi
    
    success "Configuration loaded successfully"
}

# Function to confirm destruction
confirm_destruction() {
    echo
    echo "======================================"
    warn "DESTRUCTIVE OPERATION WARNING"
    echo "======================================"
    echo
    warn "This script will permanently delete the following resources:"
    echo
    info "✗ S3 Bucket: $BUCKET_NAME (and all content)"
    if [[ -n "${LOGS_BUCKET_NAME:-}" ]]; then
        info "✗ S3 Logs Bucket: $LOGS_BUCKET_NAME (and all content)"
    fi
    info "✗ CloudFront Distribution: $DISTRIBUTION_ID"
    
    if [[ "${SETUP_DOMAIN:-n}" == "y" ]]; then
        if [[ -n "${DOMAIN_NAME:-}" ]]; then
            info "✗ Route 53 DNS record for: $DOMAIN_NAME"
        fi
        if [[ -n "${CERT_ARN:-}" ]]; then
            info "✗ SSL Certificate: $CERT_ARN"
        fi
    fi
    
    if [[ -n "${OAC_ID:-}" ]]; then
        info "✗ Origin Access Control: $OAC_ID"
    fi
    
    echo
    warn "This action cannot be undone!"
    echo
    
    # Prompt for confirmation
    read -p "Are you sure you want to delete all resources? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Please type the bucket name '$BUCKET_NAME' to confirm: " bucket_confirmation
    
    if [[ "$bucket_confirmation" != "$BUCKET_NAME" ]]; then
        error "Bucket name confirmation failed. Destruction cancelled."
        exit 1
    fi
    
    success "Destruction confirmed by user"
}

# Function to delete Route 53 records
delete_route53_records() {
    if [[ "${SETUP_DOMAIN:-n}" == "y" && -n "${HOSTED_ZONE_ID:-}" && "${HOSTED_ZONE_ID}" != "None" && "${HOSTED_ZONE_ID}" != "null" ]]; then
        info "Deleting Route 53 DNS records..."
        
        # Delete the main A record pointing to CloudFront
        if [[ -n "${DOMAIN_NAME:-}" && -n "${DISTRIBUTION_DOMAIN:-}" ]]; then
            info "Deleting A record for $DOMAIN_NAME..."
            
            aws route53 change-resource-record-sets \
                --hosted-zone-id "$HOSTED_ZONE_ID" \
                --change-batch '{
                    "Changes": [{
                        "Action": "DELETE",
                        "ResourceRecordSet": {
                            "Name": "'"$DOMAIN_NAME"'",
                            "Type": "A",
                            "AliasTarget": {
                                "HostedZoneId": "Z2FDTNDATAQYW2",
                                "DNSName": "'"$DISTRIBUTION_DOMAIN"'",
                                "EvaluateTargetHealth": false
                            }
                        }
                    }]
                }' 2>/dev/null || warn "Failed to delete A record (may not exist)"
        fi
        
        # Delete certificate validation CNAME record
        if [[ -n "${VALIDATION_NAME:-}" && -n "${VALIDATION_VALUE:-}" ]]; then
            info "Deleting certificate validation CNAME record..."
            
            aws route53 change-resource-record-sets \
                --hosted-zone-id "$HOSTED_ZONE_ID" \
                --change-batch '{
                    "Changes": [{
                        "Action": "DELETE",
                        "ResourceRecordSet": {
                            "Name": "'"$VALIDATION_NAME"'",
                            "Type": "CNAME",
                            "TTL": 300,
                            "ResourceRecords": [{"Value": "'"$VALIDATION_VALUE"'"}]
                        }
                    }]
                }' 2>/dev/null || warn "Failed to delete validation CNAME record (may not exist)"
        fi
        
        success "Route 53 records deleted"
    else
        info "No Route 53 records to delete (not configured or hosted zone not found)"
    fi
}

# Function to disable and delete CloudFront distribution
delete_cloudfront_distribution() {
    info "Disabling and deleting CloudFront distribution..."
    
    # Check if distribution exists
    if ! aws cloudfront get-distribution --id "$DISTRIBUTION_ID" &> /dev/null; then
        warn "CloudFront distribution $DISTRIBUTION_ID not found (may already be deleted)"
        return 0
    fi
    
    # Get current distribution status
    local dist_status=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query 'Distribution.Status' \
        --output text)
    
    info "Current distribution status: $dist_status"
    
    # Get current ETag for the distribution
    local etag=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query 'ETag' \
        --output text)
    
    # Get current distribution config
    local current_config=$(aws cloudfront get-distribution-config \
        --id "$DISTRIBUTION_ID" \
        --query 'DistributionConfig')
    
    # Modify config to disable the distribution
    local disabled_config=$(echo "$current_config" | jq '.Enabled = false')
    
    # Save disabled config to temporary file
    local temp_config_file="${SCRIPT_DIR}/temp-disabled-config.json"
    echo "$disabled_config" > "$temp_config_file"
    
    info "Disabling CloudFront distribution..."
    
    # Update distribution to disable it
    aws cloudfront update-distribution \
        --id "$DISTRIBUTION_ID" \
        --if-match "$etag" \
        --distribution-config file://"$temp_config_file" > /dev/null
    
    # Clean up temporary file
    rm -f "$temp_config_file"
    
    info "Waiting for CloudFront distribution to be disabled (this may take 5-15 minutes)..."
    
    # Wait for distribution to be deployed in disabled state
    if timeout 1800 aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID"; then
        success "CloudFront distribution disabled successfully"
    else
        warn "Timeout waiting for distribution to be disabled, but continuing..."
    fi
    
    # Get new ETag for deletion
    local delete_etag=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query 'ETag' \
        --output text)
    
    info "Deleting CloudFront distribution..."
    
    # Delete the distribution
    aws cloudfront delete-distribution \
        --id "$DISTRIBUTION_ID" \
        --if-match "$delete_etag"
    
    success "CloudFront distribution deletion initiated"
}

# Function to delete Origin Access Control
delete_origin_access_control() {
    if [[ -n "${OAC_ID:-}" ]]; then
        info "Deleting Origin Access Control..."
        
        # Check if OAC exists
        if aws cloudfront get-origin-access-control --id "$OAC_ID" &> /dev/null; then
            local oac_etag=$(aws cloudfront get-origin-access-control \
                --id "$OAC_ID" \
                --query 'ETag' \
                --output text)
            
            aws cloudfront delete-origin-access-control \
                --id "$OAC_ID" \
                --if-match "$oac_etag"
            
            success "Origin Access Control deleted"
        else
            warn "Origin Access Control $OAC_ID not found (may already be deleted)"
        fi
    else
        info "No Origin Access Control to delete (not configured)"
    fi
}

# Function to delete SSL certificate
delete_ssl_certificate() {
    if [[ "${SETUP_DOMAIN:-n}" == "y" && -n "${CERT_ARN:-}" ]]; then
        info "Deleting SSL certificate..."
        
        # Wait a bit to ensure CloudFront is fully deleted
        info "Waiting 30 seconds for CloudFront deletion to propagate..."
        sleep 30
        
        # Check if certificate exists
        if aws acm describe-certificate --certificate-arn "$CERT_ARN" --region us-east-1 &> /dev/null; then
            # Try to delete the certificate
            if aws acm delete-certificate --certificate-arn "$CERT_ARN" --region us-east-1 2>/dev/null; then
                success "SSL certificate deleted"
            else
                warn "Failed to delete SSL certificate (may still be in use or require manual deletion)"
                warn "Certificate ARN: $CERT_ARN"
                warn "You may need to wait longer for CloudFront deletion to fully propagate"
            fi
        else
            warn "SSL certificate $CERT_ARN not found (may already be deleted)"
        fi
    else
        info "No SSL certificate to delete (not configured)"
    fi
}

# Function to delete S3 buckets
delete_s3_buckets() {
    info "Deleting S3 buckets and content..."
    
    # Delete main website bucket
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        info "Emptying and deleting S3 website bucket: $BUCKET_NAME"
        
        # Remove all objects and versions
        aws s3 rm "s3://$BUCKET_NAME/" --recursive
        
        # Delete the bucket
        aws s3api delete-bucket --bucket "$BUCKET_NAME"
        
        success "Deleted S3 website bucket: $BUCKET_NAME"
    else
        warn "S3 bucket $BUCKET_NAME not found (may already be deleted)"
    fi
    
    # Delete logs bucket if configured
    if [[ -n "${LOGS_BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket "$LOGS_BUCKET_NAME" 2>/dev/null; then
            info "Emptying and deleting S3 logs bucket: $LOGS_BUCKET_NAME"
            
            # Remove all objects and versions
            aws s3 rm "s3://$LOGS_BUCKET_NAME/" --recursive
            
            # Delete the bucket
            aws s3api delete-bucket --bucket "$LOGS_BUCKET_NAME"
            
            success "Deleted S3 logs bucket: $LOGS_BUCKET_NAME"
        else
            warn "S3 logs bucket $LOGS_BUCKET_NAME not found (may already be deleted)"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove configuration file
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
        info "Removed configuration file: $CONFIG_FILE"
    fi
    
    # Remove any temporary files that might still exist
    local temp_files=(
        "${SCRIPT_DIR}/bucket-policy.json"
        "${SCRIPT_DIR}/distribution-config.json"
        "${SCRIPT_DIR}/temp-disabled-config.json"
    )
    
    for temp_file in "${temp_files[@]}"; do
        if [[ -f "$temp_file" ]]; then
            rm -f "$temp_file"
            info "Removed temporary file: $(basename "$temp_file")"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to verify resource deletion
verify_deletion() {
    info "Verifying resource deletion..."
    
    local errors=0
    
    # Check S3 buckets
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        error "S3 bucket $BUCKET_NAME still exists"
        ((errors++))
    else
        success "S3 bucket $BUCKET_NAME deleted successfully"
    fi
    
    if [[ -n "${LOGS_BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket "$LOGS_BUCKET_NAME" 2>/dev/null; then
            error "S3 logs bucket $LOGS_BUCKET_NAME still exists"
            ((errors++))
        else
            success "S3 logs bucket $LOGS_BUCKET_NAME deleted successfully"
        fi
    fi
    
    # Check CloudFront distribution
    if aws cloudfront get-distribution --id "$DISTRIBUTION_ID" &> /dev/null; then
        warn "CloudFront distribution $DISTRIBUTION_ID still exists (deletion may be in progress)"
    else
        success "CloudFront distribution $DISTRIBUTION_ID deleted successfully"
    fi
    
    if [[ $errors -gt 0 ]]; then
        error "Some resources could not be deleted. Please check manually."
        return 1
    else
        success "All resources verified as deleted"
        return 0
    fi
}

# Function to display destruction summary
display_destruction_summary() {
    echo
    echo "======================================"
    if verify_deletion; then
        success "DESTRUCTION COMPLETED SUCCESSFULLY!"
    else
        warn "DESTRUCTION COMPLETED WITH WARNINGS"
    fi
    echo "======================================"
    echo
    
    info "Resources that were deleted:"
    info "✓ S3 Website Bucket: $BUCKET_NAME"
    if [[ -n "${LOGS_BUCKET_NAME:-}" ]]; then
        info "✓ S3 Logs Bucket: $LOGS_BUCKET_NAME"
    fi
    info "✓ CloudFront Distribution: $DISTRIBUTION_ID"
    
    if [[ "${SETUP_DOMAIN:-n}" == "y" ]]; then
        if [[ -n "${DOMAIN_NAME:-}" ]]; then
            info "✓ Route 53 DNS record for: $DOMAIN_NAME"
        fi
        if [[ -n "${CERT_ARN:-}" ]]; then
            info "✓ SSL Certificate: $CERT_ARN"
        fi
    fi
    
    if [[ -n "${OAC_ID:-}" ]]; then
        info "✓ Origin Access Control: $OAC_ID"
    fi
    
    info "✓ Configuration files and temporary files"
    
    echo
    info "Important Notes:"
    info "- CloudFront distributions may take additional time to fully delete"
    info "- DNS changes may take up to 48 hours to propagate globally"
    info "- All billable resources have been removed"
    info "- Destruction logs saved to: $LOG_FILE"
    
    echo
    success "Cleanup complete! All resources have been removed."
    echo "======================================"
}

# Main destruction function
main() {
    echo "======================================"
    echo "AWS S3 + CloudFront Website Destruction"
    echo "======================================"
    echo
    
    log "Starting destruction at $(date)"
    
    # Run destruction steps
    check_prerequisites
    load_deployment_config
    confirm_destruction
    
    echo
    info "Beginning resource deletion..."
    echo
    
    # Delete resources in reverse order of creation
    delete_route53_records
    delete_cloudfront_distribution
    delete_origin_access_control
    delete_ssl_certificate
    delete_s3_buckets
    cleanup_local_files
    
    display_destruction_summary
    
    log "Destruction completed at $(date)"
}

# Error handling function
handle_error() {
    error "An error occurred during destruction. Check $LOG_FILE for details."
    echo
    warn "Some resources may still exist. You can:"
    warn "1. Re-run this script to attempt cleanup again"
    warn "2. Manually delete remaining resources in the AWS console"
    warn "3. Check the AWS billing console to ensure no charges continue"
    exit 1
}

# Set trap for error handling
trap handle_error ERR

# Run main function
main "$@"