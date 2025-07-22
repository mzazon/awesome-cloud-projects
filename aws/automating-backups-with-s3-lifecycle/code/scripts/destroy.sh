#!/bin/bash

# =============================================================================
# AWS S3 Scheduled Backups - Cleanup Script
# =============================================================================
# This script removes all AWS resources created by the deployment script:
# - EventBridge rule and targets
# - Lambda function
# - IAM role and policies
# - S3 buckets and all their contents (including versions)
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI not configured or not authenticated"
        error "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
}

# Function to check if bucket exists
bucket_exists() {
    aws s3api head-bucket --bucket "$1" >/dev/null 2>&1
}

# Function to check if IAM role exists
role_exists() {
    aws iam get-role --role-name "$1" >/dev/null 2>&1
}

# Function to check if Lambda function exists
lambda_exists() {
    aws lambda get-function --function-name "$1" >/dev/null 2>&1
}

# Function to check if EventBridge rule exists
rule_exists() {
    aws events describe-rule --name "$1" >/dev/null 2>&1
}

# Function to get user confirmation
confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    if [ "$default" = "y" ] || [ "$default" = "Y" ]; then
        prompt="$message [Y/n]: "
    else
        prompt="$message [y/N]: "
    fi
    
    read -p "$prompt" -r response
    
    if [ -z "$response" ]; then
        response="$default"
    fi
    
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to load deployment information
load_deployment_info() {
    if [ -f "deployment-info.txt" ]; then
        log "Loading deployment information from deployment-info.txt..."
        source deployment-info.txt
        success "Loaded deployment information"
    else
        warning "deployment-info.txt not found"
        log "Please provide the resource names manually or run from the deployment directory"
        
        # Try to get values from environment or prompt user
        if [ -z "${AWS_REGION:-}" ]; then
            export AWS_REGION=$(aws configure get region)
        fi
        
        if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
            export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        fi
        
        if [ -z "${PRIMARY_BUCKET:-}" ]; then
            read -p "Enter primary bucket name: " PRIMARY_BUCKET
            export PRIMARY_BUCKET
        fi
        
        if [ -z "${BACKUP_BUCKET:-}" ]; then
            read -p "Enter backup bucket name: " BACKUP_BUCKET
            export BACKUP_BUCKET
        fi
        
        if [ -z "${LAMBDA_FUNCTION_NAME:-}" ]; then
            read -p "Enter Lambda function name: " LAMBDA_FUNCTION_NAME
            export LAMBDA_FUNCTION_NAME
        fi
        
        if [ -z "${LAMBDA_ROLE_NAME:-}" ]; then
            read -p "Enter Lambda role name: " LAMBDA_ROLE_NAME
            export LAMBDA_ROLE_NAME
        fi
        
        if [ -z "${EVENTBRIDGE_RULE_NAME:-}" ]; then
            read -p "Enter EventBridge rule name: " EVENTBRIDGE_RULE_NAME
            export EVENTBRIDGE_RULE_NAME
        fi
        
        if [ -z "${RANDOM_SUFFIX:-}" ]; then
            read -p "Enter random suffix used: " RANDOM_SUFFIX
            export RANDOM_SUFFIX
        fi
    fi
}

# Function to delete all versions of objects in a bucket
delete_bucket_versions() {
    local bucket_name="$1"
    
    if ! bucket_exists "$bucket_name"; then
        warning "Bucket $bucket_name does not exist, skipping version deletion"
        return 0
    fi
    
    log "Deleting all versions of objects in bucket: $bucket_name"
    
    # Get all object versions
    local versions_json=$(mktemp)
    local delete_markers_json=$(mktemp)
    
    # List object versions
    aws s3api list-object-versions \
        --bucket "$bucket_name" \
        --output json \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' > "$versions_json"
    
    # List delete markers
    aws s3api list-object-versions \
        --bucket "$bucket_name" \
        --output json \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' > "$delete_markers_json"
    
    # Delete all versions if they exist
    if [ -s "$versions_json" ] && [ "$(cat "$versions_json")" != "[]" ]; then
        log "Deleting object versions..."
        
        # Format for delete-objects command
        echo "{\"Objects\": $(cat "$versions_json"), \"Quiet\": true}" > delete-versions.json
        
        aws s3api delete-objects \
            --bucket "$bucket_name" \
            --delete file://delete-versions.json >/dev/null
        
        success "Deleted all object versions from $bucket_name"
    else
        log "No object versions to delete in $bucket_name"
    fi
    
    # Delete all delete markers if they exist
    if [ -s "$delete_markers_json" ] && [ "$(cat "$delete_markers_json")" != "[]" ]; then
        log "Deleting delete markers..."
        
        # Format for delete-objects command
        echo "{\"Objects\": $(cat "$delete_markers_json"), \"Quiet\": true}" > delete-markers.json
        
        aws s3api delete-objects \
            --bucket "$bucket_name" \
            --delete file://delete-markers.json >/dev/null
        
        success "Deleted all delete markers from $bucket_name"
    else
        log "No delete markers to delete in $bucket_name"
    fi
    
    # Clean up temporary files
    rm -f "$versions_json" "$delete_markers_json" delete-versions.json delete-markers.json
}

# Function to wait for bucket to be empty
wait_for_empty_bucket() {
    local bucket_name="$1"
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local object_count=$(aws s3api list-objects-v2 \
            --bucket "$bucket_name" \
            --query 'KeyCount' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$object_count" -eq 0 ]; then
            success "Bucket $bucket_name is empty"
            return 0
        fi
        
        log "Attempt $attempt/$max_attempts: Waiting for bucket to be empty (found $object_count objects)..."
        sleep 2
        ((attempt++))
    done
    
    warning "Timeout waiting for bucket $bucket_name to be empty"
    return 1
}

# =============================================================================
# MAIN CLEANUP SCRIPT
# =============================================================================

log "Starting AWS S3 Scheduled Backups cleanup..."

# Check prerequisites
log "Checking prerequisites..."

if ! command_exists aws; then
    error "AWS CLI is not installed"
    error "Please install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

check_aws_auth

# Load deployment information
load_deployment_info

# Display what will be deleted
echo ""
echo "============================================================================="
echo "RESOURCES TO BE DELETED"
echo "============================================================================="
echo "🗑️  Primary S3 Bucket: ${PRIMARY_BUCKET:-'Not specified'}"
echo "🗑️  Backup S3 Bucket: ${BACKUP_BUCKET:-'Not specified'}"
echo "🗑️  Lambda Function: ${LAMBDA_FUNCTION_NAME:-'Not specified'}"
echo "🗑️  IAM Role: ${LAMBDA_ROLE_NAME:-'Not specified'}"
echo "🗑️  EventBridge Rule: ${EVENTBRIDGE_RULE_NAME:-'Not specified'}"
echo "============================================================================="
echo ""

# Get user confirmation
warning "This action will permanently delete all resources and data!"
warning "This includes all files in the S3 buckets and their versions!"

if ! confirm_action "Are you sure you want to proceed with the cleanup?"; then
    log "Cleanup cancelled by user"
    exit 0
fi

echo ""
log "Starting cleanup process..."

# =============================================================================
# STEP 1: Remove EventBridge Rule and Targets
# =============================================================================

if [ -n "${EVENTBRIDGE_RULE_NAME:-}" ]; then
    log "Removing EventBridge rule and targets..."
    
    if rule_exists "$EVENTBRIDGE_RULE_NAME"; then
        # Remove targets first
        log "Removing targets from EventBridge rule..."
        aws events remove-targets \
            --rule "$EVENTBRIDGE_RULE_NAME" \
            --ids "1" 2>/dev/null || warning "Could not remove targets (may not exist)"
        
        # Delete the rule
        log "Deleting EventBridge rule..."
        aws events delete-rule --name "$EVENTBRIDGE_RULE_NAME"
        success "Deleted EventBridge rule: $EVENTBRIDGE_RULE_NAME"
    else
        warning "EventBridge rule $EVENTBRIDGE_RULE_NAME not found, skipping"
    fi
else
    warning "EventBridge rule name not specified, skipping"
fi

# =============================================================================
# STEP 2: Remove Lambda Function
# =============================================================================

if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
    log "Removing Lambda function..."
    
    if lambda_exists "$LAMBDA_FUNCTION_NAME"; then
        # Remove Lambda permission first
        if [ -n "${RANDOM_SUFFIX:-}" ]; then
            log "Removing Lambda permission..."
            aws lambda remove-permission \
                --function-name "$LAMBDA_FUNCTION_NAME" \
                --statement-id "EventBridgeInvoke-${RANDOM_SUFFIX}" \
                2>/dev/null || warning "Could not remove Lambda permission (may not exist)"
        fi
        
        # Delete the function
        log "Deleting Lambda function..."
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
        success "Deleted Lambda function: $LAMBDA_FUNCTION_NAME"
    else
        warning "Lambda function $LAMBDA_FUNCTION_NAME not found, skipping"
    fi
else
    warning "Lambda function name not specified, skipping"
fi

# =============================================================================
# STEP 3: Remove IAM Role and Policies
# =============================================================================

if [ -n "${LAMBDA_ROLE_NAME:-}" ]; then
    log "Removing IAM role and policies..."
    
    if role_exists "$LAMBDA_ROLE_NAME"; then
        # Delete attached policies first
        log "Deleting role policies..."
        aws iam delete-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-name S3BackupPermissions \
            2>/dev/null || warning "Could not delete role policy (may not exist)"
        
        # Delete the role
        log "Deleting IAM role..."
        aws iam delete-role --role-name "$LAMBDA_ROLE_NAME"
        success "Deleted IAM role: $LAMBDA_ROLE_NAME"
    else
        warning "IAM role $LAMBDA_ROLE_NAME not found, skipping"
    fi
else
    warning "IAM role name not specified, skipping"
fi

# =============================================================================
# STEP 4: Delete S3 Buckets and Contents
# =============================================================================

# Delete primary bucket
if [ -n "${PRIMARY_BUCKET:-}" ]; then
    log "Deleting primary S3 bucket and contents..."
    
    if bucket_exists "$PRIMARY_BUCKET"; then
        # Delete all objects and versions
        delete_bucket_versions "$PRIMARY_BUCKET"
        
        # Wait for bucket to be empty
        wait_for_empty_bucket "$PRIMARY_BUCKET"
        
        # Delete the bucket
        log "Deleting primary bucket..."
        aws s3api delete-bucket --bucket "$PRIMARY_BUCKET"
        success "Deleted primary bucket: $PRIMARY_BUCKET"
    else
        warning "Primary bucket $PRIMARY_BUCKET not found, skipping"
    fi
else
    warning "Primary bucket name not specified, skipping"
fi

# Delete backup bucket
if [ -n "${BACKUP_BUCKET:-}" ]; then
    log "Deleting backup S3 bucket and contents..."
    
    if bucket_exists "$BACKUP_BUCKET"; then
        # Delete all objects and versions
        delete_bucket_versions "$BACKUP_BUCKET"
        
        # Wait for bucket to be empty
        wait_for_empty_bucket "$BACKUP_BUCKET"
        
        # Delete the bucket
        log "Deleting backup bucket..."
        aws s3api delete-bucket --bucket "$BACKUP_BUCKET"
        success "Deleted backup bucket: $BACKUP_BUCKET"
    else
        warning "Backup bucket $BACKUP_BUCKET not found, skipping"
    fi
else
    warning "Backup bucket name not specified, skipping"
fi

# =============================================================================
# STEP 5: Clean up local files
# =============================================================================

log "Cleaning up local files..."

# Remove deployment info file if it exists
if [ -f "deployment-info.txt" ]; then
    rm -f deployment-info.txt
    success "Removed deployment-info.txt"
fi

# Remove any temporary files that might be left
rm -f lifecycle-policy.json trust-policy.json s3-permissions.json
rm -f lambda_function.py lambda_function.zip response.json
rm -f sample-file-*.txt delete-versions.json delete-markers.json

success "Cleaned up local files"

# =============================================================================
# CLEANUP COMPLETE
# =============================================================================

success "AWS S3 Scheduled Backups cleanup completed successfully!"

echo ""
echo "============================================================================="
echo "CLEANUP SUMMARY"
echo "============================================================================="
echo "✅ EventBridge rule and targets removed"
echo "✅ Lambda function deleted"
echo "✅ IAM role and policies removed"
echo "✅ Primary S3 bucket and contents deleted"
echo "✅ Backup S3 bucket and contents deleted"
echo "✅ Local files cleaned up"
echo ""
echo "All resources have been successfully removed."
echo "Your AWS account will no longer incur charges for these resources."
echo "============================================================================="

log "Cleanup completed at $(date)"