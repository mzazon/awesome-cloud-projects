#!/bin/bash

# Deploy script for GuardDuty Threat Detection Recipe
# This script implements the complete GuardDuty threat detection solution
# with automated alerts and monitoring capabilities

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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

# Banner
echo -e "${BLUE}"
echo "=============================================="
echo "   GuardDuty Threat Detection Deployment"
echo "=============================================="
echo -e "${NC}"

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
fi

# Check if user is authenticated
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS CLI is not configured or you don't have proper credentials."
fi

# Check if user has required permissions (basic check)
log "Validating AWS permissions..."
if ! aws guardduty list-detectors &> /dev/null; then
    error "Insufficient permissions. You need GuardDuty, CloudWatch, SNS, and EventBridge permissions."
fi

success "Prerequisites check passed"

# Set environment variables
log "Configuring environment variables..."

export AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    export AWS_REGION="us-east-1"
    warning "No default region found, using us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Prompt for notification email if not set
if [ -z "${NOTIFICATION_EMAIL:-}" ]; then
    echo -n "Enter your email address for GuardDuty notifications: "
    read NOTIFICATION_EMAIL
    export NOTIFICATION_EMAIL
fi

# Validate email format (basic check)
if [[ ! "$NOTIFICATION_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    error "Invalid email format: $NOTIFICATION_EMAIL"
fi

# Generate unique identifier for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))

export SNS_TOPIC_NAME="guardduty-alerts-${RANDOM_SUFFIX}"
export S3_BUCKET_NAME="guardduty-findings-${AWS_ACCOUNT_ID}-${RANDOM_SUFFIX}"

success "Environment configured for region: ${AWS_REGION}"
log "Account ID: ${AWS_ACCOUNT_ID}"
log "Notification email: ${NOTIFICATION_EMAIL}"

# Step 1: Enable Amazon GuardDuty
log "Step 1: Enabling Amazon GuardDuty..."

# Check if GuardDuty is already enabled
EXISTING_DETECTORS=$(aws guardduty list-detectors --query 'DetectorIds' --output text)

if [ -n "$EXISTING_DETECTORS" ] && [ "$EXISTING_DETECTORS" != "None" ]; then
    DETECTOR_ID=$EXISTING_DETECTORS
    warning "GuardDuty already enabled with detector ID: ${DETECTOR_ID}"
else
    DETECTOR_ID=$(aws guardduty create-detector \
        --enable \
        --finding-publishing-frequency FIFTEEN_MINUTES \
        --query DetectorId --output text)
    success "GuardDuty enabled with detector ID: ${DETECTOR_ID}"
fi

export DETECTOR_ID

# Step 2: Create SNS Topic for Alert Notifications
log "Step 2: Creating SNS topic for alert notifications..."

SNS_TOPIC_ARN=$(aws sns create-topic \
    --name ${SNS_TOPIC_NAME} \
    --query TopicArn --output text)

export SNS_TOPIC_ARN
success "SNS topic created: ${SNS_TOPIC_ARN}"

# Step 3: Subscribe Email to SNS Topic
log "Step 3: Subscribing email to SNS topic..."

SUBSCRIPTION_ARN=$(aws sns subscribe \
    --topic-arn ${SNS_TOPIC_ARN} \
    --protocol email \
    --notification-endpoint ${NOTIFICATION_EMAIL} \
    --query SubscriptionArn --output text)

success "Email subscription created for ${NOTIFICATION_EMAIL}"
warning "Please check your email and confirm the subscription!"

# Step 4: Create EventBridge Rule for GuardDuty Findings
log "Step 4: Creating EventBridge rule for GuardDuty findings..."

aws events put-rule \
    --name guardduty-finding-events \
    --event-pattern '{
      "source": ["aws.guardduty"],
      "detail-type": ["GuardDuty Finding"]
    }' \
    --description "Route GuardDuty findings to SNS" \
    --state ENABLED

success "EventBridge rule created for GuardDuty findings"

# Step 5: Add SNS Topic as EventBridge Target
log "Step 5: Adding SNS topic as EventBridge target..."

aws events put-targets \
    --rule guardduty-finding-events \
    --targets "Id"="1","Arn"="${SNS_TOPIC_ARN}"

success "SNS topic added as EventBridge target"

# Step 6: Grant EventBridge Permission to Publish to SNS
log "Step 6: Configuring EventBridge permissions for SNS..."

POLICY_DOCUMENT='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "sns:Publish",
      "Resource": "'${SNS_TOPIC_ARN}'"
    }
  ]
}'

aws sns set-topic-attributes \
    --topic-arn ${SNS_TOPIC_ARN} \
    --attribute-name Policy \
    --attribute-value "${POLICY_DOCUMENT}"

success "EventBridge permissions configured for SNS topic"

# Step 7: Create CloudWatch Dashboard for Threat Monitoring
log "Step 7: Creating CloudWatch dashboard for security monitoring..."

aws cloudwatch put-dashboard \
    --dashboard-name "GuardDuty-Security-Monitoring" \
    --dashboard-body '{
      "widgets": [
        {
          "type": "metric",
          "x": 0,
          "y": 0,
          "width": 12,
          "height": 6,
          "properties": {
            "metrics": [
              [ "AWS/GuardDuty", "FindingCount" ]
            ],
            "period": 300,
            "stat": "Sum",
            "region": "'${AWS_REGION}'",
            "title": "GuardDuty Findings Count",
            "yAxis": {
              "left": {
                "min": 0
              }
            }
          }
        },
        {
          "type": "log",
          "x": 0,
          "y": 6,
          "width": 24,
          "height": 6,
          "properties": {
            "query": "SOURCE \"/aws/events/rule/guardduty-finding-events\" | fields @timestamp, @message\n| sort @timestamp desc\n| limit 20",
            "region": "'${AWS_REGION}'",
            "title": "Recent GuardDuty Events",
            "view": "table"
          }
        }
      ]
    }'

success "CloudWatch dashboard created for security monitoring"

# Step 8: Configure GuardDuty Finding Export to S3
log "Step 8: Configuring GuardDuty findings export to S3..."

# Create S3 bucket for GuardDuty findings export
if aws s3 ls "s3://${S3_BUCKET_NAME}" 2>&1 | grep -q 'NoSuchBucket'; then
    aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}
    success "S3 bucket created: ${S3_BUCKET_NAME}"
else
    warning "S3 bucket already exists: ${S3_BUCKET_NAME}"
fi

# Configure bucket policy for GuardDuty
BUCKET_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowGuardDutyGetBucketLocation",
      "Effect": "Allow",
      "Principal": {
        "Service": "guardduty.amazonaws.com"
      },
      "Action": "s3:GetBucketLocation",
      "Resource": "arn:aws:s3:::'${S3_BUCKET_NAME}'"
    },
    {
      "Sid": "AllowGuardDutyPutObject",
      "Effect": "Allow",
      "Principal": {
        "Service": "guardduty.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::'${S3_BUCKET_NAME}'/*"
    }
  ]
}'

aws s3api put-bucket-policy \
    --bucket ${S3_BUCKET_NAME} \
    --policy "${BUCKET_POLICY}"

# Configure GuardDuty to export findings to S3
DESTINATION_ID=$(aws guardduty create-publishing-destination \
    --detector-id ${DETECTOR_ID} \
    --destination-type S3 \
    --destination-properties DestinationArn=arn:aws:s3:::${S3_BUCKET_NAME},KmsKeyArn="" \
    --query DestinationId --output text)

success "GuardDuty findings export configured to S3: ${S3_BUCKET_NAME}"

# Save deployment configuration
log "Saving deployment configuration..."

cat > guardduty-deployment.env << EOF
# GuardDuty Threat Detection Deployment Configuration
# Generated on: $(date)
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export DETECTOR_ID="${DETECTOR_ID}"
export SNS_TOPIC_ARN="${SNS_TOPIC_ARN}"
export SNS_TOPIC_NAME="${SNS_TOPIC_NAME}"
export S3_BUCKET_NAME="${S3_BUCKET_NAME}"
export NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL}"
export DESTINATION_ID="${DESTINATION_ID}"
EOF

success "Deployment configuration saved to guardduty-deployment.env"

# Final validation
log "Performing final validation..."

# Check GuardDuty status
DETECTOR_STATUS=$(aws guardduty get-detector --detector-id ${DETECTOR_ID} --query Status --output text)
if [ "$DETECTOR_STATUS" != "ENABLED" ]; then
    error "GuardDuty detector is not enabled. Status: $DETECTOR_STATUS"
fi

# Check SNS topic exists
if ! aws sns get-topic-attributes --topic-arn ${SNS_TOPIC_ARN} &> /dev/null; then
    error "SNS topic validation failed"
fi

# Check EventBridge rule exists
if ! aws events describe-rule --name guardduty-finding-events &> /dev/null; then
    error "EventBridge rule validation failed"
fi

success "All validations passed"

# Display deployment summary
echo -e "\n${GREEN}=========================================="
echo "   Deployment Completed Successfully!"
echo "==========================================${NC}"
echo
echo "📊 Dashboard URL: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=GuardDuty-Security-Monitoring"
echo "🔒 GuardDuty Console: https://${AWS_REGION}.console.aws.amazon.com/guardduty/home?region=${AWS_REGION}#/findings"
echo "📧 Notification Email: ${NOTIFICATION_EMAIL}"
echo "🪣 S3 Findings Bucket: ${S3_BUCKET_NAME}"
echo
warning "Don't forget to confirm your email subscription to receive alerts!"
echo
log "To generate test findings, use the GuardDuty console 'Generate sample findings' feature"
log "To clean up resources, run: ./destroy.sh"
echo
echo -e "${BLUE}Happy threat hunting! 🕵️‍♂️${NC}"