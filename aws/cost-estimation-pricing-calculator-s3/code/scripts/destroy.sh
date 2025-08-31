#!/bin/bash

# Cost Estimation Planning with Pricing Calculator and S3 - Cleanup Script
# This script removes all infrastructure created for cost estimation storage
# Version: 1.0
# Last Updated: 2025-01-16

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy-$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=false
FORCE=false
KEEP_LOGS=false

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to print colored output
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}" | tee -a "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_status "$RED" "❌ AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        print_status "$RED" "❌ AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    print_status "$GREEN" "✅ Prerequisites check completed"
}

# Function to discover existing resources
discover_resources() {
    log "INFO" "Discovering existing resources..."
    
    # Get AWS configuration
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        print_status "$RED" "❌ Failed to get AWS Account ID"
        exit 1
    fi
    
    # Try to find deployment summary from previous deployment
    if [ -f "${SCRIPT_DIR}/deployment-summary.txt" ]; then
        log "INFO" "Found deployment summary, extracting resource information..."
        
        export BUCKET_NAME=$(grep "S3 Bucket:" "${SCRIPT_DIR}/deployment-summary.txt" | cut -d: -f2 | xargs)
        export PROJECT_NAME=$(grep "AWS Budget:" "${SCRIPT_DIR}/deployment-summary.txt" | cut -d: -f2 | sed 's/-budget//' | xargs)
        export SNS_TOPIC_NAME="${PROJECT_NAME}-budget-alerts"
        export TOPIC_ARN=$(grep "ARN:" "${SCRIPT_DIR}/deployment-summary.txt" | cut -d: -f2- | xargs)
        
        log "INFO" "Resources discovered from deployment summary"
    else
        # If no deployment summary, try to discover resources
        log "INFO" "No deployment summary found, attempting resource discovery..."
        
        # Set default project name
        export PROJECT_NAME="web-app-migration"
        export SNS_TOPIC_NAME="${PROJECT_NAME}-budget-alerts"
        
        # Try to find cost estimation buckets
        local buckets=($(aws s3api list-buckets --query 'Buckets[?contains(Name, `cost-estimates`)].Name' --output text 2>/dev/null || echo ""))
        
        if [ ${#buckets[@]} -eq 1 ]; then
            export BUCKET_NAME="${buckets[0]}"
            log "INFO" "Found S3 bucket: ${BUCKET_NAME}"
        elif [ ${#buckets[@]} -gt 1 ]; then
            print_status "$YELLOW" "⚠️  Multiple cost estimation buckets found:"
            printf '%s\n' "${buckets[@]}"
            if [ "$FORCE" = false ]; then
                echo -n "Enter bucket name to delete: "
                read -r BUCKET_NAME
                export BUCKET_NAME
            else
                print_status "$RED" "❌ Multiple buckets found but --force specified. Cannot proceed safely."
                exit 1
            fi
        else
            print_status "$YELLOW" "⚠️  No cost estimation S3 buckets found"
            export BUCKET_NAME=""
        fi
        
        # Try to get SNS topic ARN
        if aws sns get-topic-attributes --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" &>/dev/null; then
            export TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
            log "INFO" "Found SNS topic: ${TOPIC_ARN}"
        else
            export TOPIC_ARN=""
            print_status "$YELLOW" "⚠️  SNS topic not found: ${SNS_TOPIC_NAME}"
        fi
    fi
    
    log "INFO" "Resource discovery completed"
    log "INFO" "AWS Region: ${AWS_REGION}"
    log "INFO" "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "INFO" "Bucket Name: ${BUCKET_NAME:-'Not found'}"
    log "INFO" "Project Name: ${PROJECT_NAME}"
    log "INFO" "SNS Topic: ${SNS_TOPIC_NAME}"
}

# Function to confirm destruction
confirm_destruction() {
    if [ "$FORCE" = true ]; then
        print_status "$YELLOW" "⚠️  FORCE mode enabled - skipping confirmation"
        return
    fi
    
    print_status "$YELLOW" "⚠️  DESTRUCTIVE OPERATION WARNING"
    echo ""
    echo "This will permanently delete the following resources:"
    
    if [ -n "${BUCKET_NAME:-}" ]; then
        echo "  - S3 Bucket: ${BUCKET_NAME} (including ALL contents and versions)"
    fi
    
    if [ -n "${TOPIC_ARN:-}" ]; then
        echo "  - SNS Topic: ${SNS_TOPIC_NAME}"
    fi
    
    echo "  - AWS Budget: ${PROJECT_NAME}-budget"
    echo ""
    
    if [ "$DRY_RUN" = false ]; then
        echo -n "Are you sure you want to continue? [y/N]: "
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                print_status "$YELLOW" "⚠️  Proceeding with resource deletion..."
                ;;
            *)
                print_status "$BLUE" "🚫 Operation cancelled by user"
                exit 0
                ;;
        esac
    fi
}

# Function to delete AWS Budget
delete_budget() {
    log "INFO" "Deleting AWS Budget..."
    
    if [ "$DRY_RUN" = true ]; then
        print_status "$BLUE" "🔍 DRY RUN: Would delete budget: ${PROJECT_NAME}-budget"
        return
    fi
    
    # Check if budget exists
    if aws budgets describe-budget --account-id "${AWS_ACCOUNT_ID}" --budget-name "${PROJECT_NAME}-budget" &>/dev/null; then
        aws budgets delete-budget \
            --account-id "${AWS_ACCOUNT_ID}" \
            --budget-name "${PROJECT_NAME}-budget" 2>&1 | tee -a "$LOG_FILE"
        
        print_status "$GREEN" "✅ Budget deleted: ${PROJECT_NAME}-budget"
    else
        print_status "$YELLOW" "⚠️  Budget not found: ${PROJECT_NAME}-budget"
    fi
}

# Function to delete SNS topic
delete_sns_topic() {
    log "INFO" "Deleting SNS topic..."
    
    if [ "$DRY_RUN" = true ]; then
        print_status "$BLUE" "🔍 DRY RUN: Would delete SNS topic: ${SNS_TOPIC_NAME}"
        return
    fi
    
    if [ -n "${TOPIC_ARN:-}" ]; then
        # Check if topic exists
        if aws sns get-topic-attributes --topic-arn "${TOPIC_ARN}" &>/dev/null; then
            aws sns delete-topic --topic-arn "${TOPIC_ARN}" 2>&1 | tee -a "$LOG_FILE"
            print_status "$GREEN" "✅ SNS topic deleted: ${SNS_TOPIC_NAME}"
        else
            print_status "$YELLOW" "⚠️  SNS topic not found: ${SNS_TOPIC_NAME}"
        fi
    else
        print_status "$YELLOW" "⚠️  No SNS topic ARN available for deletion"
    fi
}

# Function to empty and delete S3 bucket
delete_s3_bucket() {
    log "INFO" "Deleting S3 bucket and all contents..."
    
    if [ -z "${BUCKET_NAME:-}" ]; then
        print_status "$YELLOW" "⚠️  No S3 bucket to delete"
        return
    fi
    
    if [ "$DRY_RUN" = true ]; then
        print_status "$BLUE" "🔍 DRY RUN: Would delete S3 bucket: ${BUCKET_NAME}"
        
        # Show what would be deleted (in dry-run mode)
        if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
            echo "Contents that would be deleted:"
            aws s3 ls "s3://${BUCKET_NAME}" --recursive 2>/dev/null || echo "  (bucket is empty)"
        fi
        return
    fi
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        print_status "$YELLOW" "⚠️  S3 bucket not found: ${BUCKET_NAME}"
        return
    fi
    
    log "INFO" "Emptying S3 bucket contents..."
    
    # Delete all objects (current versions)
    aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>&1 | tee -a "$LOG_FILE" || true
    
    # Delete all object versions and delete markers (for versioned bucket)
    local versions_json=$(aws s3api list-object-versions --bucket "${BUCKET_NAME}" 2>/dev/null || echo '{}')
    
    if echo "$versions_json" | grep -q '"Versions"'; then
        echo "$versions_json" | jq -r '.Versions[]? | "\(.Key) \(.VersionId)"' | while read -r key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object --bucket "${BUCKET_NAME}" --key "$key" --version-id "$version_id" 2>&1 | tee -a "$LOG_FILE" || true
            fi
        done
    fi
    
    if echo "$versions_json" | grep -q '"DeleteMarkers"'; then
        echo "$versions_json" | jq -r '.DeleteMarkers[]? | "\(.Key) \(.VersionId)"' | while read -r key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object --bucket "${BUCKET_NAME}" --key "$key" --version-id "$version_id" 2>&1 | tee -a "$LOG_FILE" || true
            fi
        done
    fi
    
    # Wait a moment for deletions to propagate
    sleep 2
    
    # Delete the bucket
    log "INFO" "Deleting S3 bucket..."
    aws s3api delete-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}" 2>&1 | tee -a "$LOG_FILE"
    
    print_status "$GREEN" "✅ S3 bucket deleted: ${BUCKET_NAME}"
}

# Function to cleanup local temporary files
cleanup_local_files() {
    log "INFO" "Cleaning up local temporary files..."
    
    if [ "$DRY_RUN" = true ]; then
        print_status "$BLUE" "🔍 DRY RUN: Would clean up local files"
        return
    fi
    
    local files_to_remove=(
        "${SCRIPT_DIR}/lifecycle-policy.json"
        "${SCRIPT_DIR}/budget-policy.json"
        "${SCRIPT_DIR}/sample-estimate.csv"
        "${SCRIPT_DIR}/estimate-summary.txt"
    )
    
    if [ "$KEEP_LOGS" = false ]; then
        files_to_remove+=("${SCRIPT_DIR}/deployment-summary.txt")
    fi
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "INFO" "Removed file: $(basename "$file")"
        fi
    done
    
    print_status "$GREEN" "✅ Local temporary files cleaned up"
}

# Function to validate cleanup
validate_cleanup() {
    log "INFO" "Validating resource cleanup..."
    
    local remaining_resources=0
    
    # Check S3 bucket
    if [ -n "${BUCKET_NAME:-}" ] && aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        print_status "$RED" "❌ S3 bucket still exists: ${BUCKET_NAME}"
        ((remaining_resources++))
    else
        print_status "$GREEN" "✅ S3 bucket successfully deleted"
    fi
    
    # Check SNS topic
    if [ -n "${TOPIC_ARN:-}" ] && aws sns get-topic-attributes --topic-arn "${TOPIC_ARN}" &>/dev/null; then
        print_status "$RED" "❌ SNS topic still exists: ${SNS_TOPIC_NAME}"
        ((remaining_resources++))
    else
        print_status "$GREEN" "✅ SNS topic successfully deleted"
    fi
    
    # Check budget
    if aws budgets describe-budget --account-id "${AWS_ACCOUNT_ID}" --budget-name "${PROJECT_NAME}-budget" &>/dev/null; then
        print_status "$RED" "❌ Budget still exists: ${PROJECT_NAME}-budget"
        ((remaining_resources++))
    else
        print_status "$GREEN" "✅ Budget successfully deleted"
    fi
    
    if [ $remaining_resources -eq 0 ]; then
        print_status "$GREEN" "✅ All resources cleaned up successfully"
        return 0
    else
        print_status "$YELLOW" "⚠️  $remaining_resources resources may still exist"
        return 1
    fi
}

# Function to create cleanup summary
create_cleanup_summary() {
    log "INFO" "Creating cleanup summary..."
    
    cat > "${SCRIPT_DIR}/cleanup-summary.txt" << EOF
=== Cost Estimation Infrastructure Cleanup Summary ===
Cleanup Date: $(date)
AWS Region: ${AWS_REGION}
AWS Account ID: ${AWS_ACCOUNT_ID}

Resources Deleted:
- S3 Bucket: ${BUCKET_NAME:-'Not found'}
- SNS Topic: ${SNS_TOPIC_NAME}
- AWS Budget: ${PROJECT_NAME}-budget

Cleanup Method: $([ "$DRY_RUN" = true ] && echo "DRY RUN" || echo "ACTUAL")
Force Mode: $([ "$FORCE" = true ] && echo "Enabled" || echo "Disabled")

Status: $([ "$DRY_RUN" = true ] && echo "Simulated" || echo "Completed")

Log File: $LOG_FILE
EOF
    
    print_status "$GREEN" "✅ Cleanup summary created: ${SCRIPT_DIR}/cleanup-summary.txt"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Cost Estimation Planning infrastructure from AWS

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deleted without making changes
    -f, --force         Skip confirmation prompts (dangerous!)
    -k, --keep-logs     Keep deployment logs and summary files
    -v, --verbose       Enable verbose logging
    
ENVIRONMENT VARIABLES:
    AWS_REGION          Override AWS region (default: from AWS CLI config)
    PROJECT_NAME        Override project name (default: web-app-migration)

EXAMPLES:
    $0                  Interactive cleanup with confirmation
    $0 --dry-run        Preview what would be deleted
    $0 --force          Delete without confirmation (use with caution!)
    $0 --keep-logs      Delete resources but keep log files

WARNING:
    This script will permanently delete AWS resources and data.
    Use --dry-run first to preview what will be deleted.

EOF
}

# Main cleanup function
main() {
    print_status "$BLUE" "🧹 Starting Cost Estimation Infrastructure Cleanup"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
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
            -k|--keep-logs)
                KEEP_LOGS=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                print_status "$RED" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    if [ "$DRY_RUN" = true ]; then
        print_status "$YELLOW" "🔍 DRY RUN MODE: No resources will be deleted"
    fi
    
    if [ "$FORCE" = true ] && [ "$DRY_RUN" = false ]; then
        print_status "$RED" "⚠️  FORCE MODE ENABLED: Resources will be deleted without confirmation!"
    fi
    
    # Execute cleanup steps with error handling
    trap 'log "ERROR" "Cleanup failed at line $LINENO"; exit 1' ERR
    
    check_prerequisites
    discover_resources
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_budget
    delete_sns_topic
    delete_s3_bucket
    cleanup_local_files
    
    if [ "$DRY_RUN" = false ]; then
        validate_cleanup
    fi
    
    create_cleanup_summary
    
    print_status "$GREEN" "🎉 Cleanup completed successfully!"
    
    if [ "$DRY_RUN" = false ]; then
        echo ""
        print_status "$BLUE" "📋 Cleanup Summary:"
        cat "${SCRIPT_DIR}/cleanup-summary.txt"
        echo ""
        print_status "$GREEN" "💰 All AWS resources have been removed to prevent ongoing charges"
        echo ""
        print_status "$BLUE" "📝 Log file: $LOG_FILE"
    else
        echo ""
        print_status "$YELLOW" "💡 This was a dry run. To actually delete resources, run without --dry-run"
    fi
}

# Run main function
main "$@"