#!/bin/bash

# =================================================================
# Multi-Region Data Replication with S3 - Cleanup Script
# =================================================================
# This script safely removes all resources created by the 
# multi-region S3 replication deployment.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Administrative permissions for S3, KMS, IAM, CloudWatch
# - .env file from deployment script
#
# Usage: ./destroy.sh [--force] [--dry-run]
# =================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ENV_FILE="${SCRIPT_DIR}/.env"
DRY_RUN=false
FORCE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--force] [--dry-run]"
            echo "  --force    Skip confirmation prompts"
            echo "  --dry-run  Show what would be deleted without making changes"
            exit 0
            ;;
        *)
            echo "Unknown option $1"
            exit 1
            ;;
    esac
done

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️  $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $*" | tee -a "$LOG_FILE"
}

# Initialize log file
echo "==================================================================" > "$LOG_FILE"
echo "Multi-Region S3 Replication Cleanup - $(date)" >> "$LOG_FILE"
echo "==================================================================" >> "$LOG_FILE"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check for environment file
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "Environment file not found: $ENV_FILE"
        log_error "This file should have been created by the deploy.sh script."
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables from $ENV_FILE..."
    
    # Source the environment file
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    
    # Validate required variables
    local required_vars=(
        "PRIMARY_REGION" "SECONDARY_REGION" "TERTIARY_REGION"
        "AWS_ACCOUNT_ID" "SOURCE_BUCKET" "DEST_BUCKET_1" "DEST_BUCKET_2"
        "REPLICATION_ROLE" "SOURCE_KMS_ALIAS" "DEST_KMS_ALIAS_1" "DEST_KMS_ALIAS_2"
        "SNS_TOPIC"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    log_info "Environment loaded:"
    log_info "  Source Bucket: ${SOURCE_BUCKET}"
    log_info "  Destination Buckets: ${DEST_BUCKET_1}, ${DEST_BUCKET_2}"
    log_info "  Replication Role: ${REPLICATION_ROLE}"
    
    log_success "Environment variables loaded"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   - S3 Buckets: ${SOURCE_BUCKET}, ${DEST_BUCKET_1}, ${DEST_BUCKET_2}"
    echo "   - All objects and versions in these buckets"
    echo "   - KMS keys (scheduled for deletion after 7 days)"
    echo "   - IAM role: ${REPLICATION_ROLE}"
    echo "   - CloudWatch alarms and SNS topic"
    echo "   - All monitoring and operational scripts"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log "User confirmed deletion"
}

# Function to safely check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local region="${3:-}"
    
    case "$resource_type" in
        "s3-bucket")
            aws s3api head-bucket --bucket "$resource_name" ${region:+--region "$region"} &>/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" &>/dev/null
            ;;
        "kms-alias")
            aws kms describe-key --key-id "$resource_name" ${region:+--region "$region"} &>/dev/null
            ;;
        "sns-topic")
            aws sns get-topic-attributes --topic-arn "arn:aws:sns:${region}:${AWS_ACCOUNT_ID}:${resource_name}" ${region:+--region "$region"} &>/dev/null
            ;;
        "cloudwatch-alarm")
            aws cloudwatch describe-alarms --alarm-names "$resource_name" ${region:+--region "$region"} --query 'MetricAlarms[0]' --output text | grep -q "^${resource_name}" &>/dev/null
            ;;
        *)
            log_error "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

# Function to remove test objects and data
remove_test_objects() {
    log "Removing objects from S3 buckets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would delete all objects from S3 buckets"
        return 0
    fi
    
    # Remove objects from source bucket
    if resource_exists "s3-bucket" "$SOURCE_BUCKET"; then
        log "Deleting objects from source bucket: ${SOURCE_BUCKET}"
        aws s3 rm "s3://${SOURCE_BUCKET}" --recursive || log_warning "Failed to delete some objects from ${SOURCE_BUCKET}"
        
        # Delete all object versions (required for versioned buckets)
        log "Deleting object versions from source bucket..."
        aws s3api list-object-versions --bucket "${SOURCE_BUCKET}" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text | \
        while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object --bucket "${SOURCE_BUCKET}" --key "$key" --version-id "$version_id" || true
            fi
        done
        
        # Delete delete markers
        aws s3api list-object-versions --bucket "${SOURCE_BUCKET}" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text | \
        while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object --bucket "${SOURCE_BUCKET}" --key "$key" --version-id "$version_id" || true
            fi
        done
    fi
    
    # Remove objects from destination bucket 1
    if resource_exists "s3-bucket" "$DEST_BUCKET_1" "$SECONDARY_REGION"; then
        log "Deleting objects from destination bucket 1: ${DEST_BUCKET_1}"
        aws s3 rm "s3://${DEST_BUCKET_1}" --recursive --region "${SECONDARY_REGION}" || log_warning "Failed to delete some objects from ${DEST_BUCKET_1}"
        
        # Delete versions and delete markers
        aws s3api list-object-versions --bucket "${DEST_BUCKET_1}" --region "${SECONDARY_REGION}" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text | \
        while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object --bucket "${DEST_BUCKET_1}" --key "$key" --version-id "$version_id" --region "${SECONDARY_REGION}" || true
            fi
        done
        
        aws s3api list-object-versions --bucket "${DEST_BUCKET_1}" --region "${SECONDARY_REGION}" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text | \
        while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object --bucket "${DEST_BUCKET_1}" --key "$key" --version-id "$version_id" --region "${SECONDARY_REGION}" || true
            fi
        done
    fi
    
    # Remove objects from destination bucket 2
    if resource_exists "s3-bucket" "$DEST_BUCKET_2" "$TERTIARY_REGION"; then
        log "Deleting objects from destination bucket 2: ${DEST_BUCKET_2}"
        aws s3 rm "s3://${DEST_BUCKET_2}" --recursive --region "${TERTIARY_REGION}" || log_warning "Failed to delete some objects from ${DEST_BUCKET_2}"
        
        # Delete versions and delete markers
        aws s3api list-object-versions --bucket "${DEST_BUCKET_2}" --region "${TERTIARY_REGION}" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text | \
        while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object --bucket "${DEST_BUCKET_2}" --key "$key" --version-id "$version_id" --region "${TERTIARY_REGION}" || true
            fi
        done
        
        aws s3api list-object-versions --bucket "${DEST_BUCKET_2}" --region "${TERTIARY_REGION}" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text | \
        while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object --bucket "${DEST_BUCKET_2}" --key "$key" --version-id "$version_id" --region "${TERTIARY_REGION}" || true
            fi
        done
    fi
    
    log_success "Objects removed from all buckets"
}

# Function to remove replication configuration
remove_replication_configuration() {
    log "Removing replication configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would remove replication configuration from ${SOURCE_BUCKET}"
        return 0
    fi
    
    if resource_exists "s3-bucket" "$SOURCE_BUCKET"; then
        # Remove replication configuration
        aws s3api delete-bucket-replication --bucket "${SOURCE_BUCKET}" || log_warning "Failed to delete replication configuration"
        log_success "Replication configuration removed"
    else
        log_info "Source bucket ${SOURCE_BUCKET} does not exist, skipping replication configuration removal"
    fi
}

# Function to remove monitoring resources
remove_monitoring() {
    log "Removing monitoring and alerting resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would remove CloudWatch alarms and SNS topic"
        return 0
    fi
    
    # Delete CloudWatch alarms
    local alarm_names=(
        "S3-Replication-Failure-Rate-${SOURCE_BUCKET}"
        "S3-Replication-Latency-${SOURCE_BUCKET}"
    )
    
    for alarm_name in "${alarm_names[@]}"; do
        if resource_exists "cloudwatch-alarm" "$alarm_name" "$PRIMARY_REGION"; then
            log "Deleting CloudWatch alarm: $alarm_name"
            aws cloudwatch delete-alarms --alarm-names "$alarm_name" --region "${PRIMARY_REGION}" || log_warning "Failed to delete alarm $alarm_name"
        fi
    done
    
    # Delete CloudWatch dashboard
    local dashboard_name="S3-Multi-Region-Replication-Dashboard"
    aws cloudwatch delete-dashboards \
        --dashboard-names "$dashboard_name" \
        --region "${PRIMARY_REGION}" 2>/dev/null || log_info "Dashboard $dashboard_name does not exist or already deleted"
    
    # Delete SNS topic
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        log "Deleting SNS topic: ${SNS_TOPIC}"
        aws sns delete-topic \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --region "${PRIMARY_REGION}" || log_warning "Failed to delete SNS topic"
    elif resource_exists "sns-topic" "$SNS_TOPIC" "$PRIMARY_REGION"; then
        local topic_arn="arn:aws:sns:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC}"
        log "Deleting SNS topic: ${SNS_TOPIC}"
        aws sns delete-topic \
            --topic-arn "$topic_arn" \
            --region "${PRIMARY_REGION}" || log_warning "Failed to delete SNS topic"
    fi
    
    log_success "Monitoring resources removed"
}

# Function to remove IAM resources
remove_iam_resources() {
    log "Removing IAM role and policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would remove IAM role ${REPLICATION_ROLE}"
        return 0
    fi
    
    if resource_exists "iam-role" "$REPLICATION_ROLE"; then
        # Delete role policy
        log "Deleting IAM role policy: MultiRegionS3ReplicationPolicy"
        aws iam delete-role-policy \
            --role-name "${REPLICATION_ROLE}" \
            --policy-name MultiRegionS3ReplicationPolicy || log_warning "Failed to delete role policy"
        
        # Delete IAM role
        log "Deleting IAM role: ${REPLICATION_ROLE}"
        aws iam delete-role --role-name "${REPLICATION_ROLE}" || log_warning "Failed to delete IAM role"
        
        log_success "IAM resources removed"
    else
        log_info "IAM role ${REPLICATION_ROLE} does not exist, skipping"
    fi
}

# Function to remove KMS resources
remove_kms_resources() {
    log "Removing KMS keys and aliases..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would schedule KMS keys for deletion"
        return 0
    fi
    
    # Remove KMS aliases and schedule key deletion
    local kms_aliases=("$SOURCE_KMS_ALIAS" "$DEST_KMS_ALIAS_1" "$DEST_KMS_ALIAS_2")
    local kms_regions=("$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION")
    local kms_key_vars=("SOURCE_KMS_KEY_ID" "DEST_KMS_KEY_ID_1" "DEST_KMS_KEY_ID_2")
    
    for i in "${!kms_aliases[@]}"; do
        local alias="${kms_aliases[$i]}"
        local region="${kms_regions[$i]}"
        local key_var="${kms_key_vars[$i]}"
        local key_id="${!key_var:-}"
        
        if resource_exists "kms-alias" "$alias" "$region"; then
            log "Deleting KMS alias: $alias in $region"
            aws kms delete-alias --alias-name "$alias" --region "$region" || log_warning "Failed to delete KMS alias $alias"
            
            if [[ -n "$key_id" ]]; then
                log "Scheduling KMS key deletion: $key_id in $region (7 day waiting period)"
                aws kms schedule-key-deletion \
                    --key-id "$key_id" \
                    --pending-window-in-days 7 \
                    --region "$region" || log_warning "Failed to schedule key deletion for $key_id"
            fi
        else
            log_info "KMS alias $alias does not exist in $region, skipping"
        fi
    done
    
    log_success "KMS resources scheduled for deletion"
}

# Function to remove S3 buckets
remove_s3_buckets() {
    log "Removing S3 buckets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would delete S3 buckets: ${SOURCE_BUCKET}, ${DEST_BUCKET_1}, ${DEST_BUCKET_2}"
        return 0
    fi
    
    # Delete source bucket
    if resource_exists "s3-bucket" "$SOURCE_BUCKET"; then
        log "Deleting source bucket: ${SOURCE_BUCKET}"
        aws s3 rb "s3://${SOURCE_BUCKET}" --force || log_warning "Failed to delete source bucket"
    else
        log_info "Source bucket ${SOURCE_BUCKET} does not exist, skipping"
    fi
    
    # Delete destination bucket 1
    if resource_exists "s3-bucket" "$DEST_BUCKET_1" "$SECONDARY_REGION"; then
        log "Deleting destination bucket 1: ${DEST_BUCKET_1}"
        aws s3 rb "s3://${DEST_BUCKET_1}" --force --region "${SECONDARY_REGION}" || log_warning "Failed to delete destination bucket 1"
    else
        log_info "Destination bucket 1 ${DEST_BUCKET_1} does not exist, skipping"
    fi
    
    # Delete destination bucket 2
    if resource_exists "s3-bucket" "$DEST_BUCKET_2" "$TERTIARY_REGION"; then
        log "Deleting destination bucket 2: ${DEST_BUCKET_2}"
        aws s3 rb "s3://${DEST_BUCKET_2}" --force --region "${TERTIARY_REGION}" || log_warning "Failed to delete destination bucket 2"
    else
        log_info "Destination bucket 2 ${DEST_BUCKET_2} does not exist, skipping"
    fi
    
    log_success "S3 buckets removed"
}

# Function to remove CloudTrail
remove_cloudtrail() {
    log "Removing CloudTrail..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would remove CloudTrail ${CLOUDTRAIL_NAME:-}"
        return 0
    fi
    
    if [[ -n "${CLOUDTRAIL_NAME:-}" ]]; then
        log "Deleting CloudTrail: ${CLOUDTRAIL_NAME}"
        aws cloudtrail delete-trail \
            --name "${CLOUDTRAIL_NAME}" \
            --region "${PRIMARY_REGION}" || log_warning "Failed to delete CloudTrail"
    else
        log_info "CloudTrail name not found in environment, skipping"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would clean up local files and operational scripts"
        return 0
    fi
    
    # Remove operational scripts and files created during deployment
    local files_to_remove=(
        "${SCRIPT_DIR}/health-check.sh"
        "${SCRIPT_DIR}/test-data"
        "${SCRIPT_DIR}/.env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]] || [[ -d "$file" ]]; then
            log "Removing: $file"
            rm -rf "$file" || log_warning "Failed to remove $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to display cleanup summary
display_summary() {
    log "==================================================================="
    log "                    CLEANUP SUMMARY"
    log "==================================================================="
    log "The following resources have been removed:"
    log "  ✅ S3 Buckets and all objects/versions"
    log "  ✅ Multi-region replication configuration"
    log "  ✅ IAM role and policies"
    log "  ✅ CloudWatch alarms and SNS topic"
    log "  ✅ KMS aliases (keys scheduled for deletion in 7 days)"
    log "  ✅ CloudTrail (if configured)"
    log "  ✅ Local operational scripts and environment file"
    log ""
    log "Important Notes:"
    log "  • KMS keys are scheduled for deletion with a 7-day waiting period"
    log "  • You can cancel KMS key deletion during the waiting period if needed"
    log "  • All S3 object versions and delete markers have been removed"
    log "  • Replication metrics may continue to appear briefly in CloudWatch"
    log ""
    log "Cleanup completed successfully!"
    log "==================================================================="
}

# Function to handle partial cleanup on error
cleanup_on_error() {
    log_error "Cleanup failed at line $LINENO"
    log_error "Some resources may still exist. Check the log file for details: $LOG_FILE"
    log_error "You may need to manually remove remaining resources or re-run this script"
}

# Main execution function
main() {
    log "Starting multi-region S3 replication cleanup..."
    
    # Run cleanup steps in reverse order of creation
    check_prerequisites
    load_environment
    confirm_deletion
    
    # Clean up in reverse order
    remove_test_objects
    remove_replication_configuration
    remove_monitoring
    remove_iam_resources
    remove_s3_buckets
    remove_kms_resources
    remove_cloudtrail
    cleanup_local_files
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN completed successfully. No resources were deleted."
    else
        log_success "Multi-region S3 replication cleanup completed successfully!"
        display_summary
    fi
}

# Trap errors and provide cleanup guidance
trap cleanup_on_error ERR

# Run main function
main "$@"