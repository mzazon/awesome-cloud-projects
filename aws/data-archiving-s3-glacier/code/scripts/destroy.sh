#!/bin/bash

# Destroy script for Automated Data Archiving with S3 Glacier Recipe
# This script safely removes all resources created by the deployment script

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running in script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Starting cleanup of Automated Data Archiving with S3 Glacier solution..."

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS CLI is not configured. Please run 'aws configure' first."
    exit 1
fi

success "Prerequisites check completed"

# Load deployment information if available
if [ -f "deployment-info.json" ]; then
    log "Loading deployment information from deployment-info.json..."
    
    if command -v jq &> /dev/null; then
        export AWS_REGION=$(jq -r '.awsRegion' deployment-info.json)
        export AWS_ACCOUNT_ID=$(jq -r '.awsAccountId' deployment-info.json)
        export BUCKET_NAME=$(jq -r '.bucketName' deployment-info.json)
        export SNS_TOPIC_ARN=$(jq -r '.snsTopicArn' deployment-info.json)
        export NOTIFICATION_EMAIL=$(jq -r '.notificationEmail' deployment-info.json)
        success "Loaded deployment information from file"
    else
        warning "jq not available, using environment variables or defaults"
    fi
else
    warning "deployment-info.json not found, using environment variables or defaults"
fi

# Set environment variables if not already set
if [ -z "${AWS_REGION:-}" ]; then
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No region information available, using us-east-1"
    fi
fi

if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        error "Unable to get AWS Account ID"
        exit 1
    fi
fi

if [ -z "${BUCKET_NAME:-}" ]; then
    export BUCKET_NAME="awscookbook-archive-${AWS_ACCOUNT_ID:0:8}"
fi

log "Cleanup configuration:"
log "  Region: $AWS_REGION"
log "  Account ID: $AWS_ACCOUNT_ID"
log "  Bucket Name: $BUCKET_NAME"
if [ -n "${SNS_TOPIC_ARN:-}" ]; then
    log "  SNS Topic ARN: $SNS_TOPIC_ARN"
fi

# Confirmation prompt
warning "This will permanently delete all resources created by the deployment script."
warning "This action cannot be undone."
echo
read -p "Are you sure you want to proceed? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log "Cleanup cancelled by user"
    exit 0
fi

# Step 1: Remove bucket notification configuration
log "Step 1: Removing S3 bucket notification configuration..."

if aws s3api get-bucket-notification-configuration --bucket "$BUCKET_NAME" > /dev/null 2>&1; then
    aws s3api put-bucket-notification-configuration \
        --bucket "$BUCKET_NAME" \
        --notification-configuration '{}'
    success "Removed bucket notification configuration"
else
    warning "Bucket notification configuration not found or already removed"
fi

# Step 2: Remove lifecycle configuration
log "Step 2: Removing S3 lifecycle configuration..."

if aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET_NAME" > /dev/null 2>&1; then
    aws s3api delete-bucket-lifecycle --bucket "$BUCKET_NAME"
    success "Removed lifecycle configuration from bucket"
else
    warning "Lifecycle configuration not found or already removed"
fi

# Step 3: Delete all objects in the bucket (including all versions)
log "Step 3: Deleting all objects and versions from S3 bucket..."

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    # Delete all current objects
    log "Deleting current objects..."
    aws s3 rm s3://"$BUCKET_NAME" --recursive --quiet || true
    
    # Delete all object versions and delete markers
    log "Deleting object versions and delete markers..."
    aws s3api list-object-versions --bucket "$BUCKET_NAME" \
        --output json --query 'Versions[].{Key:Key,VersionId:VersionId}' \
        | jq -r '.[] | select(.Key != null and .VersionId != null) | "\(.Key) \(.VersionId)"' \
        | while read -r key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id" --quiet || true
            fi
        done 2>/dev/null || true
    
    # Delete all delete markers
    aws s3api list-object-versions --bucket "$BUCKET_NAME" \
        --output json --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
        | jq -r '.[] | select(.Key != null and .VersionId != null) | "\(.Key) \(.VersionId)"' \
        | while read -r key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id" --quiet || true
            fi
        done 2>/dev/null || true
    
    success "Deleted all objects and versions from bucket"
else
    warning "Bucket $BUCKET_NAME not found or already deleted"
fi

# Step 4: Delete the S3 bucket
log "Step 4: Deleting S3 bucket..."

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    # Wait a moment for eventual consistency
    sleep 5
    
    # Try to delete the bucket
    if aws s3api delete-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        success "Deleted S3 bucket: $BUCKET_NAME"
    else
        warning "Failed to delete bucket immediately, it may still contain objects or have eventual consistency issues"
        log "Retrying bucket deletion in 10 seconds..."
        sleep 10
        
        if aws s3api delete-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
            success "Deleted S3 bucket: $BUCKET_NAME (retry successful)"
        else
            error "Failed to delete bucket after retry. Manual cleanup may be required."
        fi
    fi
else
    warning "Bucket $BUCKET_NAME not found or already deleted"
fi

# Step 5: Delete SNS topic and subscriptions
log "Step 5: Deleting SNS topic and subscriptions..."

if [ -n "${SNS_TOPIC_ARN:-}" ]; then
    # List and delete all subscriptions first
    log "Deleting SNS subscriptions..."
    aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" \
        --query 'Subscriptions[].SubscriptionArn' --output text \
        | tr '\t' '\n' | while read -r subscription_arn; do
            if [ -n "$subscription_arn" ] && [ "$subscription_arn" != "None" ]; then
                aws sns unsubscribe --subscription-arn "$subscription_arn" || true
                log "Deleted subscription: $subscription_arn"
            fi
        done 2>/dev/null || true
    
    # Delete the topic
    if aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" 2>/dev/null; then
        success "Deleted SNS topic: $SNS_TOPIC_ARN"
    else
        warning "Failed to delete SNS topic or topic not found"
    fi
else
    # Try to find and delete any archive notification topics
    log "Searching for archive notification topics..."
    aws sns list-topics --query 'Topics[?contains(TopicArn, `archive-notification`)].TopicArn' \
        --output text | tr '\t' '\n' | while read -r topic_arn; do
            if [ -n "$topic_arn" ] && [ "$topic_arn" != "None" ]; then
                # Delete subscriptions first
                aws sns list-subscriptions-by-topic --topic-arn "$topic_arn" \
                    --query 'Subscriptions[].SubscriptionArn' --output text \
                    | tr '\t' '\n' | while read -r subscription_arn; do
                        if [ -n "$subscription_arn" ] && [ "$subscription_arn" != "None" ]; then
                            aws sns unsubscribe --subscription-arn "$subscription_arn" || true
                        fi
                    done 2>/dev/null || true
                
                # Delete the topic
                aws sns delete-topic --topic-arn "$topic_arn" || true
                success "Deleted SNS topic: $topic_arn"
            fi
        done 2>/dev/null || true
fi

# Step 6: Clean up local files
log "Step 6: Cleaning up local files..."

local_files=(
    "lifecycle-policy.json"
    "restore-request.json"
    "notification-config.json"
    "deployment-info.json"
    "sample-data"
)

for file in "${local_files[@]}"; do
    if [ -e "$file" ]; then
        rm -rf "$file"
        success "Deleted local file/directory: $file"
    fi
done

# Step 7: Final validation
log "Step 7: Running final validation..."

# Check if bucket still exists
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    warning "Bucket $BUCKET_NAME still exists - manual cleanup may be required"
else
    success "Bucket successfully deleted"
fi

# Check if SNS topic still exists
if [ -n "${SNS_TOPIC_ARN:-}" ]; then
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" > /dev/null 2>&1; then
        warning "SNS topic $SNS_TOPIC_ARN still exists - manual cleanup may be required"
    else
        success "SNS topic successfully deleted"
    fi
fi

success "✅ Cleanup completed!"

log "Summary of cleanup actions:"
log "  - Removed S3 bucket notification configuration"
log "  - Removed S3 lifecycle configuration"
log "  - Deleted all objects and versions from S3 bucket"
log "  - Deleted S3 bucket: $BUCKET_NAME"
if [ -n "${SNS_TOPIC_ARN:-}" ]; then
    log "  - Deleted SNS topic and subscriptions: $SNS_TOPIC_ARN"
fi
log "  - Cleaned up local configuration files"

log "Cleanup script completed at $(date)"

# Final notes
echo
warning "Important notes:"
warning "1. If you had objects in Glacier or Deep Archive, they may still incur storage costs"
warning "2. Any ongoing restore operations will be cancelled"
warning "3. All lifecycle policies and notifications have been removed"
warning "4. Make sure to check AWS Cost Explorer for any remaining charges"
echo
success "All resources have been successfully removed!"