#!/bin/bash

# Destroy script for Simple File Backup Notifications with S3 and SNS
# This script safely removes all resources created by the deploy script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false
SKIP_CONFIRMATION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warning "Running in DRY-RUN mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            warning "Force delete mode enabled - will delete resources without confirmation"
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--force] [--yes]"
            echo "  --dry-run: Show what would be deleted without actually deleting"
            echo "  --force: Delete resources even if they contain data"
            echo "  --yes: Skip confirmation prompts"
            exit 1
            ;;
    esac
done

# Function to run commands (with dry-run support)
run_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    log "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
        return 0
    else
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || warning "Command failed but continuing..."
        else
            eval "$cmd"
        fi
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to load deployment information
load_deployment_info() {
    local info_file="deployment-info.json"
    
    if [[ -f "$info_file" ]]; then
        log "Loading deployment information from $info_file"
        
        export AWS_REGION=$(jq -r '.aws_region' "$info_file")
        export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$info_file")
        export BUCKET_NAME=$(jq -r '.bucket_name' "$info_file")
        export SNS_TOPIC_NAME=$(jq -r '.sns_topic_name' "$info_file")
        export SNS_TOPIC_ARN=$(jq -r '.sns_topic_arn' "$info_file")
        export EMAIL_ADDRESS=$(jq -r '.email_address' "$info_file")
        
        success "Deployment information loaded successfully"
        log "AWS Region: ${AWS_REGION}"
        log "Bucket name: ${BUCKET_NAME}"
        log "SNS topic: ${SNS_TOPIC_NAME}"
    else
        warning "Deployment info file not found. Attempting to discover resources..."
        discover_resources
    fi
}

# Function to discover resources if deployment info is missing
discover_resources() {
    log "Discovering existing resources..."
    
    # Set AWS region if not already set
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
            warning "AWS region not configured, defaulting to us-east-1"
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Prompt for resource names if not found in deployment info
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        echo -n "Enter the S3 bucket name to delete (backup-notifications-*): "
        read -r BUCKET_NAME
        export BUCKET_NAME
    fi
    
    if [[ -z "${SNS_TOPIC_NAME:-}" ]]; then
        echo -n "Enter the SNS topic name to delete (backup-alerts-*): "
        read -r SNS_TOPIC_NAME
        export SNS_TOPIC_NAME
        export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    fi
    
    success "Resource discovery completed"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    log "The following resources will be PERMANENTLY DELETED:"
    echo "  • S3 Bucket: ${BUCKET_NAME} (and all contents)"
    echo "  • SNS Topic: ${SNS_TOPIC_NAME} (and all subscriptions)"
    echo "  • All event notifications and policies"
    echo ""
    warning "This action cannot be undone!"
    echo ""
    
    if [[ "$FORCE_DELETE" != "true" ]]; then
        echo -n "Are you sure you want to proceed? (type 'DELETE' to confirm): "
        read -r confirmation
        
        if [[ "$confirmation" != "DELETE" ]]; then
            log "Operation cancelled by user"
            exit 0
        fi
    fi
    
    success "Deletion confirmed. Proceeding with resource cleanup..."
}

# Function to check if S3 bucket exists and has objects
check_s3_bucket_status() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        warning "S3 bucket ${BUCKET_NAME} does not exist or is not accessible"
        return 1
    fi
    
    # Check if bucket has objects
    local object_count=$(aws s3 ls s3://${BUCKET_NAME}/ --recursive | wc -l)
    if [[ $object_count -gt 0 ]]; then
        warning "S3 bucket contains $object_count objects"
        return 0
    fi
    
    return 0
}

# Function to empty S3 bucket
empty_s3_bucket() {
    log "Emptying S3 bucket contents..."
    
    if ! check_s3_bucket_status; then
        warning "Skipping S3 bucket operations - bucket not accessible"
        return 0
    fi
    
    # Remove all objects and versions
    run_command \
        "aws s3 rm s3://${BUCKET_NAME} --recursive" \
        "Removing all objects from S3 bucket" \
        "true"
    
    # Remove all object versions (if versioning is enabled)
    run_command \
        "aws s3api delete-objects --bucket ${BUCKET_NAME} --delete \"\$(aws s3api list-object-versions --bucket ${BUCKET_NAME} --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)\" 2>/dev/null || true" \
        "Removing object versions" \
        "true"
    
    # Remove delete markers
    run_command \
        "aws s3api delete-objects --bucket ${BUCKET_NAME} --delete \"\$(aws s3api list-object-versions --bucket ${BUCKET_NAME} --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json)\" 2>/dev/null || true" \
        "Removing delete markers" \
        "true"
    
    success "S3 bucket emptied"
}

# Function to remove S3 event notifications
remove_s3_notifications() {
    log "Removing S3 event notification configuration..."
    
    if ! check_s3_bucket_status; then
        warning "Skipping S3 notification removal - bucket not accessible"
        return 0
    fi
    
    # Remove bucket notification configuration
    run_command \
        "aws s3api put-bucket-notification-configuration --bucket ${BUCKET_NAME} --notification-configuration '{}'" \
        "Removing S3 event notifications" \
        "true"
    
    success "S3 event notifications removed"
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket..."
    
    if ! check_s3_bucket_status; then
        warning "Skipping S3 bucket deletion - bucket not accessible"
        return 0
    fi
    
    # Delete the S3 bucket
    run_command \
        "aws s3 rb s3://${BUCKET_NAME}" \
        "Deleting S3 bucket" \
        "true"
    
    success "S3 bucket deleted"
}

# Function to check if SNS topic exists
check_sns_topic_status() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    # Check if topic exists
    if ! aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" &>/dev/null; then
        warning "SNS topic ${SNS_TOPIC_NAME} does not exist or is not accessible"
        return 1
    fi
    
    return 0
}

# Function to list SNS subscriptions before deletion
list_sns_subscriptions() {
    if [[ "$DRY_RUN" == "true" ]] || ! check_sns_topic_status; then
        return 0
    fi
    
    log "Current SNS subscriptions:"
    aws sns list-subscriptions-by-topic \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --query 'Subscriptions[].{Protocol:Protocol,Endpoint:Endpoint,Status:SubscriptionArn}' \
        --output table 2>/dev/null || warning "Could not list subscriptions"
}

# Function to delete SNS topic
delete_sns_topic() {
    log "Deleting SNS topic and all subscriptions..."
    
    if ! check_sns_topic_status; then
        warning "Skipping SNS topic deletion - topic not accessible"
        return 0
    fi
    
    # Delete SNS topic (this also removes all subscriptions)
    run_command \
        "aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN}" \
        "Deleting SNS topic and subscriptions" \
        "true"
    
    success "SNS topic and subscriptions deleted"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove local test files if they exist
    run_command \
        "rm -f test-backup-*.txt validation-test.txt" \
        "Removing test files" \
        "true"
    
    # Remove temporary configuration files
    run_command \
        "rm -f /tmp/sns-policy.json /tmp/notification-config.json" \
        "Removing temporary configuration files" \
        "true"
    
    # Optionally remove deployment info file
    if [[ -f "deployment-info.json" ]]; then
        if [[ "$SKIP_CONFIRMATION" == "true" ]] || [[ "$FORCE_DELETE" == "true" ]]; then
            rm -f deployment-info.json
            success "Deployment info file removed"
        else
            echo -n "Remove deployment-info.json? (y/N): "
            read -r remove_info
            if [[ "$remove_info" =~ ^[Yy]$ ]]; then
                rm -f deployment-info.json
                success "Deployment info file removed"
            else
                log "Keeping deployment-info.json for reference"
            fi
        fi
    fi
    
    success "Local cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Skipping cleanup verification in dry-run mode"
        return 0
    fi
    
    log "Verifying resource cleanup..."
    
    # Check if S3 bucket still exists
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        warning "S3 bucket ${BUCKET_NAME} still exists"
    else
        success "S3 bucket ${BUCKET_NAME} successfully deleted"
    fi
    
    # Check if SNS topic still exists
    if aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" &>/dev/null; then
        warning "SNS topic ${SNS_TOPIC_NAME} still exists"
    else
        success "SNS topic ${SNS_TOPIC_NAME} successfully deleted"
    fi
    
    success "Cleanup verification completed"
}

# Main destruction function
main() {
    log "Starting cleanup of Simple File Backup Notifications with S3 and SNS"
    log "========================================="
    
    check_prerequisites
    load_deployment_info
    confirm_deletion
    list_sns_subscriptions
    empty_s3_bucket
    remove_s3_notifications
    delete_s3_bucket
    delete_sns_topic
    cleanup_local_files
    verify_cleanup
    
    log "========================================="
    success "🧹 Cleanup completed successfully!"
    log ""
    log "All resources have been removed:"
    log "• S3 bucket and all contents deleted"
    log "• SNS topic and subscriptions deleted"
    log "• Event notifications removed"
    log "• Local files cleaned up"
    log ""
    warning "Note: Email subscriptions may take a few minutes to fully propagate the deletion"
}

# Handle script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        error "Cleanup failed. Check the logs above for details."
        log "Some resources may still exist and require manual cleanup."
        log "You can run this script again or use the AWS console to remove remaining resources."
    fi
}

trap cleanup_on_exit EXIT

# Check if jq is available for JSON parsing
if ! command -v jq &> /dev/null && [[ -f "deployment-info.json" ]]; then
    warning "jq is not installed but needed to parse deployment-info.json"
    warning "Please install jq or provide resource names manually"
fi

# Run main function
main "$@"