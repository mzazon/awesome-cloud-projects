#!/bin/bash

# =============================================================================
# AWS Elemental MediaStore Video-on-Demand Platform Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deploy.sh script
# for the AWS Elemental MediaStore video-on-demand platform.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for MediaStore, CloudFront, S3, and IAM
# - Deployment state file (.deployment_state) from deploy.sh
# =============================================================================

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${BLUE}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check if state file exists
    if [ ! -f "$STATE_FILE" ]; then
        log "ERROR" "Deployment state file not found: $STATE_FILE"
        log "ERROR" "Cannot determine what resources to clean up."
        exit 1
    fi
    
    log "SUCCESS" "Prerequisites check completed."
}

load_deployment_state() {
    log "INFO" "Loading deployment state..."
    
    # Source the state file to load variables
    source "$STATE_FILE"
    
    # Verify required variables exist
    local required_vars=(
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "RANDOM_SUFFIX"
        "MEDIASTORE_CONTAINER_NAME"
        "S3_STAGING_BUCKET"
        "IAM_ROLE_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            log "ERROR" "Required variable $var not found in state file."
            exit 1
        fi
    done
    
    log "SUCCESS" "Deployment state loaded successfully."
    log "INFO" "Cleaning up resources with suffix: $RANDOM_SUFFIX"
}

wait_for_resource_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local max_wait="${3:-600}" # Default 10 minutes
    local wait_interval="${4:-30}" # Default 30 seconds
    
    log "INFO" "Waiting for $resource_type '$resource_name' to be deleted..."
    
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        case "$resource_type" in
            "cloudfront-distribution")
                if ! aws cloudfront get-distribution --id "$resource_name" &>/dev/null; then
                    log "SUCCESS" "$resource_type '$resource_name' has been deleted."
                    return 0
                fi
                ;;
            "mediastore-container")
                if ! aws mediastore describe-container --container-name "$resource_name" &>/dev/null; then
                    log "SUCCESS" "$resource_type '$resource_name' has been deleted."
                    return 0
                fi
                ;;
        esac
        
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
        log "INFO" "Still waiting for deletion... ($elapsed/${max_wait}s elapsed)"
    done
    
    log "WARN" "Timeout waiting for $resource_type '$resource_name' to be deleted."
    return 1
}

confirm_destruction() {
    local force="$1"
    
    if [ "$force" = true ]; then
        log "WARN" "Force flag detected. Skipping confirmation."
        return 0
    fi
    
    echo
    log "WARN" "This will permanently delete the following resources:"
    log "WARN" "  - MediaStore Container: ${MEDIASTORE_CONTAINER_NAME}"
    log "WARN" "  - CloudFront Distribution: ${DISTRIBUTION_ID:-'Not found'}"
    log "WARN" "  - S3 Staging Bucket: ${S3_STAGING_BUCKET}"
    log "WARN" "  - IAM Role: ${IAM_ROLE_NAME}"
    log "WARN" "  - CloudWatch Alarms and related resources"
    echo
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "INFO" "Cleanup cancelled by user."
        exit 0
    fi
    
    log "INFO" "User confirmed destruction. Proceeding..."
}

# =============================================================================
# Resource Cleanup Functions
# =============================================================================

disable_cloudfront_distribution() {
    if [ -z "${DISTRIBUTION_ID:-}" ]; then
        log "INFO" "No CloudFront distribution ID found. Skipping CloudFront cleanup."
        return 0
    fi
    
    log "INFO" "Disabling CloudFront distribution: $DISTRIBUTION_ID"
    
    # Get current distribution configuration
    local config_file="${SCRIPT_DIR}/current-distribution-config.json"
    if ! aws cloudfront get-distribution-config \
        --id "$DISTRIBUTION_ID" \
        --query 'DistributionConfig' \
        --output json > "$config_file" 2>/dev/null; then
        log "WARN" "Could not retrieve CloudFront distribution configuration."
        return 1
    fi
    
    # Get ETag for update
    local etag=$(aws cloudfront get-distribution-config \
        --id "$DISTRIBUTION_ID" \
        --query 'ETag' --output text 2>/dev/null)
    
    if [ -z "$etag" ]; then
        log "WARN" "Could not retrieve CloudFront ETag."
        return 1
    fi
    
    # Modify configuration to disable distribution
    if command -v jq &> /dev/null; then
        jq '.Enabled = false' "$config_file" > "${config_file}.tmp" && \
        mv "${config_file}.tmp" "$config_file"
    else
        # Fallback method without jq
        sed 's/"Enabled": true/"Enabled": false/g' "$config_file" > "${config_file}.tmp" && \
        mv "${config_file}.tmp" "$config_file"
    fi
    
    # Update distribution to disable it
    if aws cloudfront update-distribution \
        --id "$DISTRIBUTION_ID" \
        --distribution-config "file://$config_file" \
        --if-match "$etag" &>/dev/null; then
        log "SUCCESS" "CloudFront distribution disabled."
        
        # Wait for distribution to be deployed in disabled state
        log "INFO" "Waiting for CloudFront distribution to be disabled..."
        aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID" 2>/dev/null || \
        log "WARN" "Timeout waiting for distribution to be disabled."
    else
        log "WARN" "Failed to disable CloudFront distribution."
    fi
    
    # Clean up temporary file
    rm -f "$config_file"
}

delete_cloudfront_distribution() {
    if [ -z "${DISTRIBUTION_ID:-}" ]; then
        log "INFO" "No CloudFront distribution to delete."
        return 0
    fi
    
    log "INFO" "Deleting CloudFront distribution: $DISTRIBUTION_ID"
    
    # Get ETag for deletion
    local etag=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query 'ETag' --output text 2>/dev/null)
    
    if [ -z "$etag" ]; then
        log "WARN" "Could not retrieve CloudFront ETag for deletion."
        return 1
    fi
    
    # Delete the distribution
    if aws cloudfront delete-distribution \
        --id "$DISTRIBUTION_ID" \
        --if-match "$etag" &>/dev/null; then
        log "SUCCESS" "CloudFront distribution deletion initiated."
    else
        log "WARN" "Failed to delete CloudFront distribution."
        return 1
    fi
}

delete_mediastore_content() {
    if [ -z "${MEDIASTORE_ENDPOINT:-}" ]; then
        log "WARN" "MediaStore endpoint not found. Cannot delete content."
        return 1
    fi
    
    log "INFO" "Deleting all content from MediaStore container..."
    
    # List and delete all objects
    local objects=$(aws mediastore-data list-items \
        --endpoint-url "$MEDIASTORE_ENDPOINT" \
        --path "/" \
        --query 'Items[].Name' --output text 2>/dev/null)
    
    if [ -n "$objects" ]; then
        echo "$objects" | while read -r object; do
            if [ -n "$object" ]; then
                log "INFO" "Deleting object: /$object"
                aws mediastore-data delete-object \
                    --endpoint-url "$MEDIASTORE_ENDPOINT" \
                    --path "/$object" &>/dev/null || \
                log "WARN" "Failed to delete object: /$object"
            fi
        done
        log "SUCCESS" "MediaStore content deletion completed."
    else
        log "INFO" "No content found in MediaStore container."
    fi
}

delete_mediastore_container() {
    log "INFO" "Deleting MediaStore container: $MEDIASTORE_CONTAINER_NAME"
    
    # Delete container policies first
    aws mediastore delete-container-policy \
        --container-name "$MEDIASTORE_CONTAINER_NAME" &>/dev/null || \
    log "WARN" "Failed to delete container policy (may not exist)."
    
    aws mediastore delete-cors-policy \
        --container-name "$MEDIASTORE_CONTAINER_NAME" &>/dev/null || \
    log "WARN" "Failed to delete CORS policy (may not exist)."
    
    aws mediastore delete-lifecycle-policy \
        --container-name "$MEDIASTORE_CONTAINER_NAME" &>/dev/null || \
    log "WARN" "Failed to delete lifecycle policy (may not exist)."
    
    aws mediastore delete-metric-policy \
        --container-name "$MEDIASTORE_CONTAINER_NAME" &>/dev/null || \
    log "WARN" "Failed to delete metric policy (may not exist)."
    
    # Delete the container
    if aws mediastore delete-container \
        --container-name "$MEDIASTORE_CONTAINER_NAME" &>/dev/null; then
        log "SUCCESS" "MediaStore container deletion initiated."
        
        # Wait for container to be deleted
        if ! wait_for_resource_deletion "mediastore-container" "$MEDIASTORE_CONTAINER_NAME" 300 15; then
            log "WARN" "MediaStore container may still be deleting."
        fi
    else
        log "WARN" "Failed to delete MediaStore container."
    fi
}

delete_iam_resources() {
    log "INFO" "Deleting IAM resources..."
    
    # Delete role policy first
    if aws iam delete-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-name "MediaStoreAccessPolicy" &>/dev/null; then
        log "SUCCESS" "IAM role policy deleted."
    else
        log "WARN" "Failed to delete IAM role policy (may not exist)."
    fi
    
    # Delete the role
    if aws iam delete-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        log "SUCCESS" "IAM role deleted: $IAM_ROLE_NAME"
    else
        log "WARN" "Failed to delete IAM role."
    fi
}

delete_s3_staging_bucket() {
    log "INFO" "Deleting S3 staging bucket: $S3_STAGING_BUCKET"
    
    # Empty the bucket first
    if aws s3 rm "s3://$S3_STAGING_BUCKET" --recursive &>/dev/null; then
        log "INFO" "S3 bucket contents removed."
    else
        log "WARN" "Failed to empty S3 bucket (may already be empty)."
    fi
    
    # Delete the bucket
    if aws s3 rb "s3://$S3_STAGING_BUCKET" &>/dev/null; then
        log "SUCCESS" "S3 staging bucket deleted: $S3_STAGING_BUCKET"
    else
        log "WARN" "Failed to delete S3 staging bucket."
    fi
}

delete_cloudwatch_resources() {
    log "INFO" "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarm
    local alarm_name="MediaStore-HighRequestRate-${RANDOM_SUFFIX}"
    if aws cloudwatch delete-alarms --alarm-names "$alarm_name" &>/dev/null; then
        log "SUCCESS" "CloudWatch alarm deleted: $alarm_name"
    else
        log "WARN" "Failed to delete CloudWatch alarm (may not exist)."
    fi
}

cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    # List of files to clean up
    local files_to_cleanup=(
        "${SCRIPT_DIR}/mediastore-policy.json"
        "${SCRIPT_DIR}/cors-policy.json"
        "${SCRIPT_DIR}/trust-policy.json"
        "${SCRIPT_DIR}/mediastore-access-policy.json"
        "${SCRIPT_DIR}/cloudfront-config.json"
        "${SCRIPT_DIR}/lifecycle-policy.json"
        "${SCRIPT_DIR}/current-distribution-config.json"
        "${SCRIPT_DIR}/downloaded-video.mp4"
    )
    
    for file in "${files_to_cleanup[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "INFO" "Removed file: $(basename "$file")"
        fi
    done
    
    # Remove sample content directory
    if [ -d "${SCRIPT_DIR}/sample-content" ]; then
        rm -rf "${SCRIPT_DIR}/sample-content"
        log "INFO" "Removed sample-content directory."
    fi
    
    # Remove state file
    if [ -f "$STATE_FILE" ]; then
        rm -f "$STATE_FILE"
        log "INFO" "Removed deployment state file."
    fi
    
    log "SUCCESS" "Local file cleanup completed."
}

run_verification() {
    log "INFO" "Verifying resource deletion..."
    
    local all_deleted=true
    
    # Check MediaStore container
    if aws mediastore describe-container --container-name "$MEDIASTORE_CONTAINER_NAME" &>/dev/null; then
        log "WARN" "MediaStore container still exists: $MEDIASTORE_CONTAINER_NAME"
        all_deleted=false
    else
        log "SUCCESS" "MediaStore container successfully deleted."
    fi
    
    # Check CloudFront distribution
    if [ -n "${DISTRIBUTION_ID:-}" ]; then
        if aws cloudfront get-distribution --id "$DISTRIBUTION_ID" &>/dev/null; then
            log "WARN" "CloudFront distribution still exists: $DISTRIBUTION_ID"
            all_deleted=false
        else
            log "SUCCESS" "CloudFront distribution successfully deleted."
        fi
    fi
    
    # Check S3 bucket
    if aws s3 ls "s3://$S3_STAGING_BUCKET" &>/dev/null; then
        log "WARN" "S3 staging bucket still exists: $S3_STAGING_BUCKET"
        all_deleted=false
    else
        log "SUCCESS" "S3 staging bucket successfully deleted."
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        log "WARN" "IAM role still exists: $IAM_ROLE_NAME"
        all_deleted=false
    else
        log "SUCCESS" "IAM role successfully deleted."
    fi
    
    if [ "$all_deleted" = true ]; then
        log "SUCCESS" "All resources have been successfully deleted."
    else
        log "WARN" "Some resources may still exist. Check AWS console for manual cleanup."
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    local force=false
    local skip_confirmation=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=true
                skip_confirmation=true
                shift
                ;;
            --yes|-y)
                skip_confirmation=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--force] [--yes] [--help]"
                echo "  --force    Force deletion without confirmation and ignore errors"
                echo "  --yes      Skip confirmation prompt"
                echo "  --help     Show this help message"
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Initialize log file
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    log "INFO" "Starting AWS Elemental MediaStore VOD Platform cleanup..."
    
    check_prerequisites
    load_deployment_state
    
    if [ "$skip_confirmation" = false ]; then
        confirm_destruction "$force"
    fi
    
    # Execute cleanup steps in reverse order of creation
    log "INFO" "Beginning resource cleanup..."
    
    # Step 1: Disable and delete CloudFront distribution
    disable_cloudfront_distribution || [ "$force" = true ]
    delete_cloudfront_distribution || [ "$force" = true ]
    
    # Step 2: Delete MediaStore content and container
    delete_mediastore_content || [ "$force" = true ]
    delete_mediastore_container || [ "$force" = true ]
    
    # Step 3: Delete IAM resources
    delete_iam_resources || [ "$force" = true ]
    
    # Step 4: Delete S3 staging bucket
    delete_s3_staging_bucket || [ "$force" = true ]
    
    # Step 5: Delete CloudWatch resources
    delete_cloudwatch_resources || [ "$force" = true ]
    
    # Step 6: Clean up local files
    cleanup_local_files
    
    # Step 7: Verify deletion
    run_verification
    
    # Print cleanup summary
    echo
    log "SUCCESS" "========================================="
    log "SUCCESS" "VOD Platform Cleanup Complete!"
    log "SUCCESS" "========================================="
    log "INFO" "Log file: $LOG_FILE"
    echo
    log "INFO" "If any resources still exist, you may need to delete them manually"
    log "INFO" "through the AWS Console or wait for eventual consistency."
}

# Execute main function with all arguments
main "$@"