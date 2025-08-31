#!/bin/bash

# AWS Chat Notifications with SNS and Chatbot - Deployment Script
# This script deploys the complete infrastructure for team chat notifications

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Script header
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         AWS Chat Notifications Deployment Script            ║${NC}"
echo -e "${BLUE}║                SNS + Chatbot Integration                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
    echo "Visit: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS CLI is not configured or credentials are invalid."
    echo "Run: aws configure"
    exit 1
fi

# Check for jq (optional but helpful for JSON parsing)
if ! command -v jq &> /dev/null; then
    warning "jq not found. JSON output will be raw format."
    JQ_AVAILABLE=false
else
    JQ_AVAILABLE=true
fi

success "Prerequisites check completed"

# Set up environment variables
log "Setting up environment variables..."

export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
if [[ -z "$AWS_REGION" ]]; then
    error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
    exit 1
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    error "Unable to get AWS Account ID. Check your credentials."
    exit 1
fi

# Generate unique identifiers for resources
log "Generating unique resource identifiers..."
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

# Set resource names
export SNS_TOPIC_NAME="team-notifications-${RANDOM_SUFFIX}"
export ALARM_NAME="demo-cpu-alarm-${RANDOM_SUFFIX}"
export CHATBOT_CONFIG_NAME="team-alerts-${RANDOM_SUFFIX}"

success "Environment configured for region: ${AWS_REGION}"
success "Account ID: ${AWS_ACCOUNT_ID}"
success "Resource suffix: ${RANDOM_SUFFIX}"

# Create deployment state file for cleanup tracking
DEPLOYMENT_STATE_FILE="/tmp/chat-notifications-deployment-${RANDOM_SUFFIX}.state"
cat > "$DEPLOYMENT_STATE_FILE" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
ALARM_NAME=${ALARM_NAME}
CHATBOT_CONFIG_NAME=${CHATBOT_CONFIG_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

log "Deployment state saved to: ${DEPLOYMENT_STATE_FILE}"

# Function to check if SNS topic exists
check_sns_topic_exists() {
    local topic_name=$1
    aws sns list-topics --query "Topics[?contains(TopicArn, ':${topic_name}')]" --output text | grep -q "${topic_name}" 2>/dev/null
}

# Function to check if CloudWatch alarm exists
check_alarm_exists() {
    local alarm_name=$1
    aws cloudwatch describe-alarms --alarm-names "${alarm_name}" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "${alarm_name}"
}

# Step 1: Create SNS Topic
log "Step 1: Creating SNS Topic for team notifications..."

if check_sns_topic_exists "$SNS_TOPIC_NAME"; then
    warning "SNS topic ${SNS_TOPIC_NAME} already exists. Skipping creation."
    export SNS_TOPIC_ARN=$(aws sns list-topics --query "Topics[?contains(TopicArn, ':${SNS_TOPIC_NAME}')].TopicArn" --output text)
else
    log "Creating SNS topic with encryption enabled..."
    
    # Create SNS topic with KMS encryption
    aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --attributes '{
            "KmsMasterKeyId": "alias/aws/sns",
            "DisplayName": "Team Notifications Topic"
        }' > /dev/null
    
    # Get the topic ARN
    export SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
        --query 'Attributes.TopicArn' --output text)
    
    success "SNS topic created: ${SNS_TOPIC_ARN}"
fi

# Add SNS_TOPIC_ARN to state file
echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> "$DEPLOYMENT_STATE_FILE"

# Step 2: Display Chatbot Configuration Instructions
log "Step 2: AWS Chatbot Configuration (Manual Setup Required)..."

echo ""
echo -e "${YELLOW}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│                 MANUAL SETUP REQUIRED                      │${NC}"
echo -e "${YELLOW}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""
echo "AWS Chatbot requires initial setup through the AWS Console:"
echo ""
echo "🔗 Open AWS Chatbot Console: https://console.aws.amazon.com/chatbot/"
echo ""
echo "Complete these manual steps:"
echo "1. Choose 'Slack' as chat client"
echo "2. Click 'Configure' and authorize AWS Chatbot in your Slack workspace"
echo "3. Select your Slack workspace from dropdown"
echo "4. Click 'Allow' to grant permissions"
echo ""
echo "Then create a channel configuration:"
echo "1. Click 'Configure new channel'"
echo "2. Configuration name: ${CHATBOT_CONFIG_NAME}"
echo "3. Slack channel: Choose your target channel"
echo "4. IAM role: Create new role or use existing (ReadOnlyAccess recommended)"
echo "5. Channel guardrail policies: Add ReadOnlyAccess for security"
echo "6. SNS topics: Add ${SNS_TOPIC_ARN}"
echo "7. Save the configuration"
echo ""

read -p "Press Enter after completing the manual Chatbot setup..."

success "Manual Chatbot configuration completed"

# Step 3: Create CloudWatch Alarm for Testing
log "Step 3: Creating CloudWatch alarm for testing notifications..."

if check_alarm_exists "$ALARM_NAME"; then
    warning "CloudWatch alarm ${ALARM_NAME} already exists. Skipping creation."
else
    log "Creating test alarm with low CPU threshold..."
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "${ALARM_NAME}" \
        --alarm-description "Demo CPU alarm for testing chat notifications" \
        --metric-name CPUUtilization \
        --namespace AWS/EC2 \
        --statistic Average \
        --period 300 \
        --threshold 1.0 \
        --comparison-operator LessThanThreshold \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --evaluation-periods 1 \
        --treat-missing-data notBreaching
    
    success "CloudWatch alarm created: ${ALARM_NAME}"
    success "Alarm will trigger when CPU utilization < 1% (for testing)"
fi

# Step 4: Test Notification Flow
log "Step 4: Testing notification delivery..."

log "Sending test notification to SNS topic..."

TEST_MESSAGE=$(cat << EOF
{
    "AlarmName": "Manual Test Alert",
    "AlarmDescription": "Testing chat notification system deployment",
    "NewStateValue": "ALARM",
    "NewStateReason": "Testing notification delivery to Slack channel via deployment script",
    "StateChangeTime": "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")",
    "Region": "${AWS_REGION}",
    "AccountId": "${AWS_ACCOUNT_ID}"
}
EOF
)

aws sns publish \
    --topic-arn "${SNS_TOPIC_ARN}" \
    --subject "🚨 Test Alert: Infrastructure Notification" \
    --message "$TEST_MESSAGE" > /dev/null

success "Test notification sent to SNS topic"
echo "📱 Check your Slack channel for the notification message"

# Step 5: Validation
log "Step 5: Validating deployment..."

# Validate SNS topic
log "Validating SNS topic configuration..."
if $JQ_AVAILABLE; then
    aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" \
        --query 'Attributes.{DisplayName:DisplayName,KmsMasterKeyId:KmsMasterKeyId}' \
        --output json | jq '.'
else
    aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" \
        --query 'Attributes.{DisplayName:DisplayName,KmsMasterKeyId:KmsMasterKeyId}'
fi

# Validate CloudWatch alarm
log "Validating CloudWatch alarm status..."
if $JQ_AVAILABLE; then
    aws cloudwatch describe-alarms --alarm-names "${ALARM_NAME}" \
        --query 'MetricAlarms[0].{Name:AlarmName,State:StateValue,Actions:AlarmActions}' \
        --output json | jq '.'
else
    aws cloudwatch describe-alarms --alarm-names "${ALARM_NAME}" \
        --query 'MetricAlarms[0].{Name:AlarmName,State:StateValue,Actions:AlarmActions}'
fi

# Check SNS subscriptions
log "Checking SNS topic subscriptions..."
SUBSCRIPTION_COUNT=$(aws sns list-subscriptions-by-topic \
    --topic-arn "${SNS_TOPIC_ARN}" \
    --query 'length(Subscriptions)' --output text)

if [[ "$SUBSCRIPTION_COUNT" -gt 0 ]]; then
    success "Found ${SUBSCRIPTION_COUNT} subscription(s) to SNS topic"
    if $JQ_AVAILABLE; then
        aws sns list-subscriptions-by-topic --topic-arn "${SNS_TOPIC_ARN}" \
            --query 'Subscriptions[*].{Protocol:Protocol,Endpoint:Endpoint}' \
            --output json | jq '.'
    else
        aws sns list-subscriptions-by-topic --topic-arn "${SNS_TOPIC_ARN}" \
            --query 'Subscriptions[*].{Protocol:Protocol,Endpoint:Endpoint}'
    fi
else
    warning "No subscriptions found. Ensure Chatbot configuration is complete."
fi

# Final deployment summary
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  DEPLOYMENT COMPLETED                        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "📋 Deployment Summary:"
echo "   • SNS Topic: ${SNS_TOPIC_NAME}"
echo "   • CloudWatch Alarm: ${ALARM_NAME}"
echo "   • Chatbot Configuration: ${CHATBOT_CONFIG_NAME}"
echo "   • Region: ${AWS_REGION}"
echo "   • Account ID: ${AWS_ACCOUNT_ID}"
echo ""
echo "🗂️  State File: ${DEPLOYMENT_STATE_FILE}"
echo "   (Save this path for cleanup: ./destroy.sh ${DEPLOYMENT_STATE_FILE})"
echo ""
echo "🧪 Next Steps:"
echo "   1. Confirm test notification was received in Slack"
echo "   2. Create additional CloudWatch alarms as needed"
echo "   3. Configure environment-specific SNS topics"
echo "   4. Set up escalation workflows"
echo ""
echo "🔧 Cleanup:"
echo "   Run ./destroy.sh ${DEPLOYMENT_STATE_FILE} to remove all resources"
echo ""

success "Chat notifications infrastructure deployed successfully!"

# Export state file location for other scripts
echo "DEPLOYMENT_STATE_FILE=${DEPLOYMENT_STATE_FILE}" > "/tmp/last-chat-notifications-deployment.env"

exit 0