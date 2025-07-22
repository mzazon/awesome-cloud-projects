#!/bin/bash

# Deploy script for Automated Data Archiving with S3 Glacier Recipe
# This script implements the complete solution from the recipe with proper error handling

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

log "Starting deployment of Automated Data Archiving with S3 Glacier solution..."

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

# Check if jq is installed for JSON parsing
if ! command -v jq &> /dev/null; then
    warning "jq is not installed. Some JSON parsing may not work optimally."
fi

success "Prerequisites check completed"

# Set environment variables
log "Setting up environment variables..."

export AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    export AWS_REGION="us-east-1"
    warning "No default region configured, using us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "$AWS_ACCOUNT_ID" ]; then
    error "Unable to get AWS Account ID"
    exit 1
fi

# Generate unique bucket name
export BUCKET_NAME="awscookbook-archive-${AWS_ACCOUNT_ID:0:8}"

# Email for notifications (can be overridden by environment variable)
if [ -z "${NOTIFICATION_EMAIL:-}" ]; then
    export NOTIFICATION_EMAIL="your-email@example.com"
    warning "Using default email address. Set NOTIFICATION_EMAIL environment variable for actual notifications."
fi

log "Environment variables configured:"
log "  Region: $AWS_REGION"
log "  Account ID: $AWS_ACCOUNT_ID"
log "  Bucket Name: $BUCKET_NAME"
log "  Notification Email: $NOTIFICATION_EMAIL"

# Step 1: Create S3 bucket
log "Step 1: Creating S3 bucket for data archiving..."

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    warning "Bucket $BUCKET_NAME already exists, skipping creation"
else
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
    else
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    success "Created S3 bucket: $BUCKET_NAME"
fi

# Enable versioning for better data protection
log "Enabling versioning on S3 bucket..."
aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled
success "Enabled versioning on bucket"

# Step 2: Upload sample data
log "Step 2: Uploading sample data to demonstrate archiving..."

# Create sample files directory if it doesn't exist
mkdir -p sample-data

# Create sample files
echo "This is a sample file for S3 Glacier archiving demonstration created on $(date)" > sample-data/sample-data.txt

# Create additional test files
for i in {1..5}; do
    echo "Test file $i created on $(date)" > sample-data/test-file-$i.txt
done

# Upload sample data
aws s3 cp sample-data/sample-data.txt s3://"$BUCKET_NAME"/data/
for i in {1..5}; do
    aws s3 cp sample-data/test-file-$i.txt s3://"$BUCKET_NAME"/data/
done

success "Uploaded sample data files to s3://$BUCKET_NAME/data/"

# Step 3: Create lifecycle policy
log "Step 3: Creating lifecycle policy for automated archiving..."

cat > lifecycle-policy.json << 'EOF'
{
    "Rules": [
        {
            "ID": "ArchiveRule",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "data/"
            },
            "Transitions": [
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 365,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ]
        }
    ]
}
EOF

success "Created lifecycle policy configuration"

# Step 4: Apply lifecycle policy
log "Step 4: Applying lifecycle policy to S3 bucket..."

aws s3api put-bucket-lifecycle-configuration \
    --bucket "$BUCKET_NAME" \
    --lifecycle-configuration file://lifecycle-policy.json

success "Applied lifecycle policy to bucket $BUCKET_NAME"

# Step 5: Create restore request configuration
log "Step 5: Creating restore request configuration..."

cat > restore-request.json << 'EOF'
{
    "Days": 7,
    "GlacierJobParameters": {
        "Tier": "Standard"
    }
}
EOF

success "Created restore request configuration"

# Step 6: Create SNS topic for notifications
log "Step 6: Creating SNS topic for archiving notifications..."

export SNS_TOPIC_ARN=$(aws sns create-topic --name archive-notification-$(date +%s) \
    --output text --query 'TopicArn')

if [ -z "$SNS_TOPIC_ARN" ]; then
    error "Failed to create SNS topic"
    exit 1
fi

success "Created SNS topic: $SNS_TOPIC_ARN"

# Step 7: Subscribe to notifications
log "Step 7: Setting up email notifications..."

if [ "$NOTIFICATION_EMAIL" != "your-email@example.com" ]; then
    aws sns subscribe \
        --topic-arn "$SNS_TOPIC_ARN" \
        --protocol email \
        --notification-endpoint "$NOTIFICATION_EMAIL"
    success "Subscribed $NOTIFICATION_EMAIL to archive notifications"
    warning "Please check your email and confirm the subscription"
else
    warning "Skipping email subscription as no valid email was provided"
fi

# Step 8: Configure S3 event notifications
log "Step 8: Configuring S3 event notifications..."

# First, we need to add permission for S3 to publish to SNS
aws sns set-topic-attributes \
    --topic-arn "$SNS_TOPIC_ARN" \
    --attribute-name Policy \
    --attribute-value "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [
            {
                \"Effect\": \"Allow\",
                \"Principal\": {
                    \"Service\": \"s3.amazonaws.com\"
                },
                \"Action\": \"SNS:Publish\",
                \"Resource\": \"$SNS_TOPIC_ARN\",
                \"Condition\": {
                    \"StringEquals\": {
                        \"aws:SourceAccount\": \"$AWS_ACCOUNT_ID\"
                    }
                }
            }
        ]
    }"

# Create notification configuration
cat > notification-config.json << EOF
{
    "TopicConfigurations": [
        {
            "TopicArn": "$SNS_TOPIC_ARN",
            "Events": ["s3:ObjectRestore:Completed", "s3:ObjectRestore:Post"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "data/"
                        }
                    ]
                }
            }
        }
    ]
}
EOF

aws s3api put-bucket-notification-configuration \
    --bucket "$BUCKET_NAME" \
    --notification-configuration file://notification-config.json

success "Configured S3 event notifications"

# Save deployment information
log "Saving deployment information..."

cat > deployment-info.json << EOF
{
    "deploymentTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "awsRegion": "$AWS_REGION",
    "awsAccountId": "$AWS_ACCOUNT_ID",
    "bucketName": "$BUCKET_NAME",
    "snsTopicArn": "$SNS_TOPIC_ARN",
    "notificationEmail": "$NOTIFICATION_EMAIL"
}
EOF

success "Saved deployment information to deployment-info.json"

# Final validation
log "Running final validation..."

# Check if bucket exists and has lifecycle policy
if aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET_NAME" > /dev/null 2>&1; then
    success "Lifecycle policy successfully applied"
else
    error "Lifecycle policy validation failed"
    exit 1
fi

# Check if SNS topic exists
if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" > /dev/null 2>&1; then
    success "SNS topic successfully created"
else
    error "SNS topic validation failed"
    exit 1
fi

# Check if notification configuration exists
if aws s3api get-bucket-notification-configuration --bucket "$BUCKET_NAME" > /dev/null 2>&1; then
    success "Bucket notification configuration successfully applied"
else
    error "Bucket notification configuration validation failed"
    exit 1
fi

success "✅ Deployment completed successfully!"

log "Summary of deployed resources:"
log "  - S3 Bucket: $BUCKET_NAME"
log "  - SNS Topic: $SNS_TOPIC_ARN"
log "  - Lifecycle Policy: Applied with 90-day Glacier and 365-day Deep Archive transitions"
log "  - Event Notifications: Configured for restore operations"
log "  - Sample Data: Uploaded to data/ prefix"

log "Next steps:"
log "  1. Objects will automatically transition to Glacier after 90 days"
log "  2. Objects will transition to Deep Archive after 365 days"
log "  3. Use the restore-request.json file to restore archived objects when needed"
log "  4. Monitor notifications for restore operation completions"

if [ "$NOTIFICATION_EMAIL" != "your-email@example.com" ]; then
    log "  5. Confirm your email subscription to receive notifications"
fi

log "Deployment script completed at $(date)"