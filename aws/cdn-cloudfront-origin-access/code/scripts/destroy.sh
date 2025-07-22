#!/bin/bash

# =============================================================================
# AWS CloudFront CDN Cleanup Script
# CDN with CloudFront Origin Access Controls
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Cleanup configuration
readonly MAX_RETRIES=3
readonly WAIT_TIMEOUT=1800  # 30 minutes for CloudFront deletion

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

get_state() {
    local key="$1"
    if [[ -f "$STATE_FILE" ]]; then
        grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2- | tail -1
    fi
}

wait_for_resource_deletion() {
    local check_command="$1"
    local description="$2"
    local timeout="${3:-300}"
    
    log_info "Waiting for ${description} to be deleted..."
    local elapsed=0
    local interval=10
    
    while eval "$check_command" &>/dev/null; do
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timeout waiting for ${description} deletion"
            return 1
        fi
        
        printf "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo ""
    log_success "${description} has been deleted"
}

confirm_destruction() {
    local force="$1"
    
    if [[ "$force" == true ]]; then
        return 0
    fi
    
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    log_warning "This will permanently delete the following AWS resources:"
    
    # Show resources that will be deleted
    local distribution_id
    distribution_id=$(get_state "DISTRIBUTION_ID")
    local bucket_name
    bucket_name=$(get_state "BUCKET_NAME")
    local logs_bucket_name
    logs_bucket_name=$(get_state "LOGS_BUCKET_NAME")
    local oac_id
    oac_id=$(get_state "OAC_ID")
    local waf_arn
    waf_arn=$(get_state "WAF_ARN")
    
    echo ""
    if [[ -n "$distribution_id" ]]; then
        log_warning "  📦 CloudFront Distribution: ${distribution_id}"
    fi
    if [[ -n "$bucket_name" ]]; then
        log_warning "  🪣 S3 Content Bucket: ${bucket_name} (and all contents)"
    fi
    if [[ -n "$logs_bucket_name" ]]; then
        log_warning "  🪣 S3 Logs Bucket: ${logs_bucket_name} (and all contents)"
    fi
    if [[ -n "$oac_id" ]]; then
        log_warning "  🔐 Origin Access Control: ${oac_id}"
    fi
    if [[ -n "$waf_arn" ]]; then
        log_warning "  🛡️  WAF Web ACL: ${waf_arn}"
    fi
    log_warning "  📊 CloudWatch Alarms"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log_info "Proceeding with resource cleanup..."
}

# =============================================================================
# CloudFront Distribution Cleanup
# =============================================================================

disable_cloudfront_distribution() {
    log_info "Disabling CloudFront distribution..."
    
    local distribution_id
    distribution_id=$(get_state "DISTRIBUTION_ID")
    
    if [[ -z "$distribution_id" ]]; then
        log_warning "No CloudFront distribution ID found in state"
        return 0
    fi
    
    # Check if distribution exists
    if ! aws cloudfront get-distribution --id "$distribution_id" &>/dev/null; then
        log_warning "CloudFront distribution ${distribution_id} not found (may already be deleted)"
        return 0
    fi
    
    # Get current distribution config and check if already disabled
    local current_config
    current_config=$(aws cloudfront get-distribution-config --id "$distribution_id" 2>/dev/null || echo "{}")
    
    if [[ $(echo "$current_config" | jq -r '.DistributionConfig.Enabled // false') == "false" ]]; then
        log_info "Distribution is already disabled"
        return 0
    fi
    
    # Get ETag and disable distribution
    local etag
    etag=$(echo "$current_config" | jq -r '.ETag // ""')
    
    if [[ -z "$etag" ]]; then
        log_error "Could not get ETag for distribution"
        return 1
    fi
    
    # Create disabled config
    local disabled_config
    disabled_config=$(echo "$current_config" | jq '.DistributionConfig.Enabled = false | .DistributionConfig')
    
    # Update distribution to disable it
    echo "$disabled_config" | aws cloudfront update-distribution \
        --id "$distribution_id" \
        --if-match "$etag" \
        --distribution-config file:///dev/stdin >/dev/null
    
    log_success "Distribution disabled, waiting for deployment..."
    
    # Wait for distribution to be disabled and deployed
    wait_for_resource_deletion \
        "aws cloudfront get-distribution --id ${distribution_id} --query 'Distribution.Status' --output text | grep -v 'Deployed'" \
        "CloudFront distribution disable deployment" \
        "$WAIT_TIMEOUT"
    
    log_success "CloudFront distribution disabled"
}

delete_cloudfront_distribution() {
    log_info "Deleting CloudFront distribution..."
    
    local distribution_id
    distribution_id=$(get_state "DISTRIBUTION_ID")
    
    if [[ -z "$distribution_id" ]]; then
        log_warning "No CloudFront distribution ID found in state"
        return 0
    fi
    
    # Check if distribution exists
    if ! aws cloudfront get-distribution --id "$distribution_id" &>/dev/null; then
        log_warning "CloudFront distribution ${distribution_id} not found (may already be deleted)"
        return 0
    fi
    
    # Get new ETag after disable
    local etag
    etag=$(aws cloudfront get-distribution-config --id "$distribution_id" \
        --query 'ETag' --output text 2>/dev/null || echo "")
    
    if [[ -z "$etag" ]]; then
        log_error "Could not get ETag for distribution deletion"
        return 1
    fi
    
    # Delete the distribution
    aws cloudfront delete-distribution \
        --id "$distribution_id" \
        --if-match "$etag"
    
    log_success "CloudFront distribution deletion initiated"
}

# =============================================================================
# Origin Access Control Cleanup
# =============================================================================

delete_origin_access_control() {
    log_info "Deleting Origin Access Control..."
    
    local oac_id
    oac_id=$(get_state "OAC_ID")
    
    if [[ -z "$oac_id" ]]; then
        log_warning "No Origin Access Control ID found in state"
        return 0
    fi
    
    # Check if OAC exists
    if ! aws cloudfront get-origin-access-control --id "$oac_id" &>/dev/null; then
        log_warning "Origin Access Control ${oac_id} not found (may already be deleted)"
        return 0
    fi
    
    # Get OAC ETag
    local oac_etag
    oac_etag=$(aws cloudfront get-origin-access-control --id "$oac_id" \
        --query 'ETag' --output text 2>/dev/null || echo "")
    
    if [[ -z "$oac_etag" ]]; then
        log_error "Could not get ETag for Origin Access Control"
        return 1
    fi
    
    # Delete OAC
    aws cloudfront delete-origin-access-control \
        --id "$oac_id" \
        --if-match "$oac_etag"
    
    log_success "Origin Access Control deleted: ${oac_id}"
}

# =============================================================================
# WAF Web ACL Cleanup
# =============================================================================

delete_waf_web_acl() {
    log_info "Deleting WAF Web ACL..."
    
    local waf_name
    waf_name=$(get_state "WAF_NAME")
    
    if [[ -z "$waf_name" ]]; then
        log_warning "No WAF name found in state"
        return 0
    fi
    
    # Get WAF Web ACL ID
    local waf_id
    waf_id=$(aws wafv2 list-web-acls --scope CLOUDFRONT \
        --query "WebACLs[?Name=='${waf_name}'].Id" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$waf_id" ]] || [[ "$waf_id" == "None" ]]; then
        log_warning "WAF Web ACL '${waf_name}' not found (may already be deleted)"
        return 0
    fi
    
    # Get lock token
    local lock_token
    lock_token=$(aws wafv2 get-web-acl --scope CLOUDFRONT --id "$waf_id" \
        --query 'LockToken' --output text 2>/dev/null || echo "")
    
    if [[ -z "$lock_token" ]]; then
        log_error "Could not get lock token for WAF Web ACL"
        return 1
    fi
    
    # Delete WAF Web ACL
    aws wafv2 delete-web-acl \
        --scope CLOUDFRONT \
        --id "$waf_id" \
        --lock-token "$lock_token"
    
    log_success "WAF Web ACL deleted: ${waf_id}"
}

# =============================================================================
# S3 Buckets Cleanup
# =============================================================================

empty_and_delete_s3_bucket() {
    local bucket_name="$1"
    local bucket_description="$2"
    
    if [[ -z "$bucket_name" ]]; then
        log_warning "No ${bucket_description} bucket name provided"
        return 0
    fi
    
    log_info "Cleaning up ${bucket_description} bucket: ${bucket_name}"
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log_warning "Bucket ${bucket_name} not found (may already be deleted)"
        return 0
    fi
    
    # Remove all objects (including versions and delete markers for versioned buckets)
    log_info "Emptying bucket contents..."
    
    # Remove current objects
    aws s3 rm "s3://${bucket_name}" --recursive 2>/dev/null || true
    
    # Remove versions and delete markers if versioning is enabled
    local versions
    versions=$(aws s3api list-object-versions --bucket "$bucket_name" \
        --query '{Objects: [Versions[].{Key:Key,VersionId:VersionId}, DeleteMarkers[].{Key:Key,VersionId:VersionId}]}' \
        2>/dev/null || echo '{"Objects": []}')
    
    if [[ $(echo "$versions" | jq '.Objects | length') -gt 0 ]]; then
        log_info "Removing object versions and delete markers..."
        echo "$versions" | aws s3api delete-objects \
            --bucket "$bucket_name" \
            --delete file:///dev/stdin >/dev/null 2>&1 || true
    fi
    
    # Remove any incomplete multipart uploads
    aws s3api list-multipart-uploads --bucket "$bucket_name" \
        --query 'Uploads[].{Key:Key,UploadId:UploadId}' 2>/dev/null | \
        jq -r '.[]? | "--key \(.Key) --upload-id \(.UploadId)"' | \
        while read -r args; do
            if [[ -n "$args" ]]; then
                # shellcheck disable=SC2086
                aws s3api abort-multipart-upload --bucket "$bucket_name" $args 2>/dev/null || true
            fi
        done
    
    # Delete the bucket
    log_info "Deleting bucket ${bucket_name}..."
    aws s3 rb "s3://${bucket_name}" 2>/dev/null || \
        aws s3api delete-bucket --bucket "$bucket_name" 2>/dev/null || true
    
    log_success "${bucket_description} bucket deleted: ${bucket_name}"
}

delete_s3_buckets() {
    log_info "Deleting S3 buckets..."
    
    local bucket_name
    bucket_name=$(get_state "BUCKET_NAME")
    local logs_bucket_name
    logs_bucket_name=$(get_state "LOGS_BUCKET_NAME")
    
    # Delete content bucket
    empty_and_delete_s3_bucket "$bucket_name" "content"
    
    # Delete logs bucket
    empty_and_delete_s3_bucket "$logs_bucket_name" "logs"
}

# =============================================================================
# CloudWatch Alarms Cleanup
# =============================================================================

delete_cloudwatch_alarms() {
    log_info "Deleting CloudWatch alarms..."
    
    local distribution_id
    distribution_id=$(get_state "DISTRIBUTION_ID")
    
    if [[ -z "$distribution_id" ]]; then
        log_warning "No distribution ID found for alarm cleanup"
        return 0
    fi
    
    # Define alarm names
    local alarm_names=(
        "CloudFront-4xx-Errors-${distribution_id}"
        "CloudFront-Low-Cache-Hit-Rate-${distribution_id}"
    )
    
    # Delete alarms if they exist
    for alarm_name in "${alarm_names[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm_name" \
            --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm_name"; then
            
            aws cloudwatch delete-alarms --alarm-names "$alarm_name"
            log_success "Deleted CloudWatch alarm: ${alarm_name}"
        else
            log_warning "CloudWatch alarm not found: ${alarm_name}"
        fi
    done
}

# =============================================================================
# Local Files Cleanup
# =============================================================================

cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local content_dir
    content_dir=$(get_state "CONTENT_DIR")
    
    # Remove sample content directory
    if [[ -n "$content_dir" ]] && [[ -d "$content_dir" ]]; then
        rm -rf "$content_dir"
        log_success "Removed sample content directory: ${content_dir}"
    fi
    
    # Remove temporary configuration files
    local temp_files=(
        "${SCRIPT_DIR}/distribution-config.json"
        "${SCRIPT_DIR}/oac-config.json"
        "${SCRIPT_DIR}/bucket-policy.json"
        "${SCRIPT_DIR}/waf-config.json"
        "${SCRIPT_DIR}/current-config.json"
        "${SCRIPT_DIR}/disable-config.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed temporary file: $(basename "$file")"
        fi
    done
}

# =============================================================================
# State File Management
# =============================================================================

backup_state_file() {
    if [[ -f "$STATE_FILE" ]]; then
        local backup_file="${STATE_FILE}.destroyed.$(date +%s)"
        cp "$STATE_FILE" "$backup_file"
        log_info "State file backed up to: ${backup_file}"
    fi
}

remove_state_file() {
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        log_success "Removed deployment state file"
    fi
}

# =============================================================================
# Resource Discovery (for cleanup without state file)
# =============================================================================

discover_resources() {
    log_info "Discovering resources to clean up..."
    
    # Try to find resources with common naming patterns
    local random_suffix
    random_suffix="${1:-}"
    
    if [[ -z "$random_suffix" ]]; then
        log_warning "No random suffix provided for resource discovery"
        return 1
    fi
    
    # Discover S3 buckets
    local buckets
    buckets=$(aws s3 ls | grep -E "cdn-(content|logs)-${random_suffix}" | awk '{print $3}' || true)
    
    if [[ -n "$buckets" ]]; then
        log_info "Found S3 buckets to clean up:"
        echo "$buckets" | while read -r bucket; do
            log_info "  ${bucket}"
            if [[ "$bucket" == *"content"* ]]; then
                echo "BUCKET_NAME=${bucket}" >> "$STATE_FILE"
            elif [[ "$bucket" == *"logs"* ]]; then
                echo "LOGS_BUCKET_NAME=${bucket}" >> "$STATE_FILE"
            fi
        done
    fi
    
    # Discover CloudFront distributions
    local distributions
    distributions=$(aws cloudfront list-distributions \
        --query "DistributionList.Items[?Comment=='CDN Distribution ${random_suffix}'].Id" \
        --output text 2>/dev/null || true)
    
    if [[ -n "$distributions" ]]; then
        echo "DISTRIBUTION_ID=${distributions}" >> "$STATE_FILE"
        log_info "Found CloudFront distribution: ${distributions}"
    fi
    
    # Discover WAF Web ACLs
    local waf_id
    waf_id=$(aws wafv2 list-web-acls --scope CLOUDFRONT \
        --query "WebACLs[?Name=='cdn-waf-${random_suffix}'].Id" \
        --output text 2>/dev/null || true)
    
    if [[ -n "$waf_id" ]] && [[ "$waf_id" != "None" ]]; then
        echo "WAF_NAME=cdn-waf-${random_suffix}" >> "$STATE_FILE"
        log_info "Found WAF Web ACL: cdn-waf-${random_suffix}"
    fi
}

# =============================================================================
# Main Cleanup Function
# =============================================================================

main() {
    log_info "Starting AWS CloudFront CDN cleanup..."
    log_info "Script: $0"
    log_info "Working directory: $(pwd)"
    log_info "Timestamp: $(date)"
    
    # Parse command line arguments
    local force=false
    local dry_run=false
    local random_suffix=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --suffix)
                random_suffix="$2"
                shift 2
                ;;
            --help)
                cat << EOF
AWS CloudFront CDN Cleanup Script

Usage: $0 [OPTIONS]

Options:
    --force      Skip confirmation prompts
    --dry-run    Show what would be deleted without actually deleting
    --suffix ID  Attempt to discover and clean resources with specific suffix
    --help       Show this help message

This script removes all resources created by the deployment script:
- CloudFront distribution
- S3 buckets and contents
- Origin Access Control
- WAF Web ACL
- CloudWatch alarms
- Local files and state
EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Initialize log file
    echo "AWS CloudFront CDN Cleanup Log" > "$LOG_FILE"
    echo "Started: $(date)" >> "$LOG_FILE"
    echo "==========================================" >> "$LOG_FILE"
    
    # Check if state file exists or try resource discovery
    if [[ ! -f "$STATE_FILE" ]]; then
        if [[ -n "$random_suffix" ]]; then
            log_info "State file not found, attempting resource discovery..."
            discover_resources "$random_suffix"
        else
            log_error "No deployment state file found: ${STATE_FILE}"
            log_error "Use --suffix <random_suffix> to attempt resource discovery"
            log_error "or check if deployment was completed successfully"
            exit 1
        fi
    fi
    
    # Show what will be destroyed
    if [[ "$dry_run" == true ]]; then
        log_info "DRY RUN - The following resources would be deleted:"
        
        # List resources from state file
        if [[ -f "$STATE_FILE" ]]; then
            while IFS='=' read -r key value; do
                case "$key" in
                    DISTRIBUTION_ID)
                        log_info "  CloudFront Distribution: ${value}"
                        ;;
                    BUCKET_NAME)
                        log_info "  S3 Content Bucket: ${value}"
                        ;;
                    LOGS_BUCKET_NAME)
                        log_info "  S3 Logs Bucket: ${value}"
                        ;;
                    OAC_ID)
                        log_info "  Origin Access Control: ${value}"
                        ;;
                    WAF_NAME)
                        log_info "  WAF Web ACL: ${value}"
                        ;;
                esac
            done < "$STATE_FILE"
        fi
        
        log_info "  CloudWatch Alarms"
        log_info "  Local files and state"
        exit 0
    fi
    
    # Confirm destruction
    confirm_destruction "$force"
    
    # Backup state file before cleanup
    backup_state_file
    
    # Main cleanup steps (order is important!)
    log_info "Starting resource cleanup..."
    
    # 1. Disable CloudFront distribution first (required before deletion)
    disable_cloudfront_distribution
    
    # 2. Delete CloudWatch alarms (no dependencies)
    delete_cloudwatch_alarms
    
    # 3. Delete CloudFront distribution (takes longest)
    delete_cloudfront_distribution
    
    # 4. Delete Origin Access Control (after distribution is gone)
    delete_origin_access_control
    
    # 5. Delete WAF Web ACL (after distribution is gone)
    delete_waf_web_acl
    
    # 6. Delete S3 buckets (after distribution is gone)
    delete_s3_buckets
    
    # 7. Clean up local files
    cleanup_local_files
    
    # 8. Remove state file
    remove_state_file
    
    # Summary
    echo ""
    log_success "🧹 Cleanup completed successfully!"
    echo ""
    log_info "All AWS resources have been removed:"
    log_info "  ✓ CloudFront distribution disabled and deleted"
    log_info "  ✓ S3 buckets and contents removed"
    log_info "  ✓ Origin Access Control deleted"
    log_info "  ✓ WAF Web ACL deleted"
    log_info "  ✓ CloudWatch alarms removed"
    log_info "  ✓ Local files and state cleaned up"
    echo ""
    log_info "💰 This will stop all recurring charges for this deployment."
    log_info "📋 Cleanup log saved to: ${LOG_FILE}"
    echo ""
    log_info "Total cleanup time: $SECONDS seconds"
}

# =============================================================================
# Script Execution
# =============================================================================

# Ensure script is executable
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi