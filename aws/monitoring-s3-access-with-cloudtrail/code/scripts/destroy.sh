#!/bin/bash

# Destroy script for S3 Access Logging and Security Monitoring
# This script removes all resources created by the deployment script
# WARNING: This will permanently delete all monitoring data and configurations

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Function to handle command failures gracefully
safe_execute() {
    local cmd="$1"
    local description="$2"
    
    if eval "$cmd" 2>/dev/null; then
        success "$description"
    else
        warning "$description (may not exist or already deleted)"
    fi
}

# Function to ask for confirmation
confirm_deletion() {
    local resource="$1"
    
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        return 0
    fi
    
    echo -n "Are you sure you want to delete $resource? [y/N]: "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            echo "Skipping deletion of $resource"
            return 1
            ;;
    esac
}

# Check for force flag
if [[ "${1:-}" == "--force" ]]; then
    FORCE_DELETE=true
    warning "Force deletion mode enabled - no confirmation prompts"
fi

log "Starting S3 Access Logging and Security Monitoring cleanup..."

# Load configuration if available
if [[ -f "deployment-config.env" ]]; then
    log "Loading deployment configuration..."
    source deployment-config.env
    success "Loaded deployment configuration"
else
    warning "No deployment configuration found. Please provide resource names manually."
    echo -n "Enter Source Bucket name: "
    read -r SOURCE_BUCKET
    echo -n "Enter Logs Bucket name: "
    read -r LOGS_BUCKET
    echo -n "Enter CloudTrail Bucket name: "
    read -r CLOUDTRAIL_BUCKET
    echo -n "Enter CloudTrail Trail name: "
    read -r TRAIL_NAME
    echo -n "Enter CloudWatch Log Group name: "
    read -r LOG_GROUP_NAME
    echo -n "Enter SNS Topic ARN: "
    read -r SNS_TOPIC_ARN
    
    # Set defaults if not provided
    AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
    ROLE_ARN=${ROLE_ARN:-"arn:aws:iam::${AWS_ACCOUNT_ID}:role/CloudTrailLogsRole"}
fi

# Validate AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure' first."
fi

# Display what will be deleted
log "The following resources will be deleted:"
log "  🗂️  Source Bucket: ${SOURCE_BUCKET}"
log "  📝 Logs Bucket: ${LOGS_BUCKET}"
log "  🛤️  CloudTrail Bucket: ${CLOUDTRAIL_BUCKET}"
log "  📊 CloudTrail Trail: ${TRAIL_NAME}"
log "  📋 CloudWatch Log Group: ${LOG_GROUP_NAME}"
log "  🚨 SNS Topic: ${SNS_TOPIC_ARN}"
log "  🎯 EventBridge Rule: S3UnauthorizedAccess"
log "  📊 CloudWatch Dashboard: S3SecurityMonitoring"
log "  🔑 IAM Role: CloudTrailLogsRole"
log ""

# Final confirmation
if ! confirm_deletion "ALL RESOURCES listed above"; then
    log "Cleanup cancelled by user"
    exit 0
fi

log "Starting resource cleanup..."

# Step 1: Stop CloudTrail logging
log "Stopping CloudTrail logging..."
if [[ -n "${TRAIL_NAME:-}" ]]; then
    safe_execute "aws cloudtrail stop-logging --name ${TRAIL_NAME}" "Stopped CloudTrail logging"
else
    warning "Trail name not found, skipping CloudTrail stop"
fi

# Step 2: Remove EventBridge rule targets and rule
log "Removing EventBridge rules and targets..."
safe_execute "aws events remove-targets --rule S3UnauthorizedAccess --ids 1" "Removed EventBridge targets"
safe_execute "aws events delete-rule --name S3UnauthorizedAccess" "Deleted EventBridge rule"

# Step 3: Delete SNS topic
log "Deleting SNS topic..."
if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
    safe_execute "aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN}" "Deleted SNS topic"
else
    warning "SNS topic ARN not found, skipping SNS deletion"
fi

# Step 4: Delete CloudWatch Dashboard
log "Deleting CloudWatch Dashboard..."
safe_execute "aws cloudwatch delete-dashboards --dashboard-names S3SecurityMonitoring" "Deleted CloudWatch dashboard"

# Step 5: Delete CloudWatch Log Group
log "Deleting CloudWatch Log Group..."
if [[ -n "${LOG_GROUP_NAME:-}" ]]; then
    safe_execute "aws logs delete-log-group --log-group-name ${LOG_GROUP_NAME}" "Deleted CloudWatch log group"
else
    warning "Log group name not found, skipping log group deletion"
fi

# Step 6: Delete CloudTrail trail
log "Deleting CloudTrail trail..."
if [[ -n "${TRAIL_NAME:-}" ]]; then
    safe_execute "aws cloudtrail delete-trail --name ${TRAIL_NAME}" "Deleted CloudTrail trail"
else
    warning "Trail name not found, skipping CloudTrail deletion"
fi

# Step 7: Remove IAM role and policies
log "Removing IAM role and policies..."
safe_execute "aws iam delete-role-policy --role-name CloudTrailLogsRole --policy-name CloudTrailLogsPolicy" "Deleted IAM role policy"
safe_execute "aws iam delete-role --role-name CloudTrailLogsRole" "Deleted IAM role"

# Step 8: Empty and delete S3 buckets
log "Emptying and deleting S3 buckets..."

# Function to empty and delete S3 bucket
empty_and_delete_bucket() {
    local bucket_name="$1"
    
    if [[ -z "$bucket_name" ]]; then
        warning "Bucket name is empty, skipping"
        return
    fi
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log "Emptying bucket: $bucket_name"
        
        # Delete all objects including versions and delete markers
        aws s3api list-object-versions --bucket "$bucket_name" --output json | \
        jq -r '.Versions[]?, .DeleteMarkers[]? | "\(.Key) \(.VersionId)"' | \
        while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" 2>/dev/null || true
            fi
        done
        
        # Delete any remaining objects
        aws s3 rm "s3://$bucket_name" --recursive 2>/dev/null || true
        
        # Delete the bucket
        if aws s3api delete-bucket --bucket "$bucket_name" 2>/dev/null; then
            success "Deleted bucket: $bucket_name"
        else
            warning "Failed to delete bucket: $bucket_name (may not be empty or may not exist)"
        fi
    else
        warning "Bucket $bucket_name does not exist or is not accessible"
    fi
}

# Delete all buckets
empty_and_delete_bucket "${SOURCE_BUCKET}"
empty_and_delete_bucket "${LOGS_BUCKET}"
empty_and_delete_bucket "${CLOUDTRAIL_BUCKET}"

# Step 9: Clean up local files
log "Cleaning up local files..."
safe_execute "rm -f deployment-config.env" "Removed deployment configuration"
safe_execute "rm -f security-queries.txt" "Removed security queries file"
safe_execute "rm -f test-file.txt" "Removed test file"

# Step 10: Final verification
log "Performing final verification..."

# Check if buckets still exist
for bucket in "${SOURCE_BUCKET}" "${LOGS_BUCKET}" "${CLOUDTRAIL_BUCKET}"; do
    if [[ -n "$bucket" ]]; then
        if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            warning "Bucket $bucket still exists and may require manual deletion"
        else
            success "Bucket $bucket successfully deleted"
        fi
    fi
done

# Check if CloudTrail trail exists
if [[ -n "${TRAIL_NAME:-}" ]]; then
    if aws cloudtrail describe-trails --trail-name-list "${TRAIL_NAME}" --query 'trailList[0].Name' --output text 2>/dev/null | grep -q "${TRAIL_NAME}"; then
        warning "CloudTrail trail ${TRAIL_NAME} still exists"
    else
        success "CloudTrail trail ${TRAIL_NAME} successfully deleted"
    fi
fi

# Check if CloudWatch log group exists
if [[ -n "${LOG_GROUP_NAME:-}" ]]; then
    if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${LOG_GROUP_NAME}"; then
        warning "CloudWatch log group ${LOG_GROUP_NAME} still exists"
    else
        success "CloudWatch log group ${LOG_GROUP_NAME} successfully deleted"
    fi
fi

# Check if IAM role exists
if aws iam get-role --role-name CloudTrailLogsRole 2>/dev/null; then
    warning "IAM role CloudTrailLogsRole still exists"
else
    success "IAM role CloudTrailLogsRole successfully deleted"
fi

log "Cleanup completed!"
log ""
log "📋 Cleanup Summary:"
log "  ✅ Stopped CloudTrail logging"
log "  ✅ Removed EventBridge rules and targets"
log "  ✅ Deleted SNS topic"
log "  ✅ Deleted CloudWatch dashboard"
log "  ✅ Deleted CloudWatch log group"
log "  ✅ Deleted CloudTrail trail"
log "  ✅ Removed IAM role and policies"
log "  ✅ Emptied and deleted S3 buckets"
log "  ✅ Cleaned up local files"
log ""
log "⚠️  Important Notes:"
log "  1. If any resources still exist, you may need to delete them manually"
log "  2. Check AWS CloudTrail console for any remaining trails"
log "  3. Verify S3 console for any remaining buckets"
log "  4. Check CloudWatch console for any remaining log groups"
log "  5. Some resources may take a few minutes to fully delete"
log ""
log "💰 Cost Impact:"
log "  • S3 storage costs will stop accruing"
log "  • CloudTrail data event charges will stop"
log "  • CloudWatch Logs ingestion charges will stop"
log ""

success "S3 Access Logging and Security Monitoring cleanup completed successfully!"

# Show final resource count
log "Final resource verification:"
remaining_resources=0

# Count remaining buckets
for bucket in "${SOURCE_BUCKET}" "${LOGS_BUCKET}" "${CLOUDTRAIL_BUCKET}"; do
    if [[ -n "$bucket" ]] && aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
        ((remaining_resources++))
    fi
done

# Count remaining trails
if [[ -n "${TRAIL_NAME:-}" ]] && aws cloudtrail describe-trails --trail-name-list "${TRAIL_NAME}" --query 'trailList[0].Name' --output text 2>/dev/null | grep -q "${TRAIL_NAME}"; then
    ((remaining_resources++))
fi

# Count remaining log groups
if [[ -n "${LOG_GROUP_NAME:-}" ]] && aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${LOG_GROUP_NAME}"; then
    ((remaining_resources++))
fi

# Count remaining IAM roles
if aws iam get-role --role-name CloudTrailLogsRole 2>/dev/null; then
    ((remaining_resources++))
fi

if [[ $remaining_resources -eq 0 ]]; then
    success "All resources have been successfully deleted!"
else
    warning "$remaining_resources resources may still exist and require manual cleanup"
fi