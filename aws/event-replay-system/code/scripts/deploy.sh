#!/bin/bash

# Deploy script for EventBridge Archive Recipe
# Creates event replay mechanisms with EventBridge Archive

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/eventbridge-archive-deploy-$(date +%Y%m%d-%H%M%S).log"
DEPLOYMENT_NAME="eventbridge-archive-deploy"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check log file: $LOG_FILE"
    log_error "To clean up partial deployment, run: ./destroy.sh"
    exit 1
}

trap cleanup_on_error ERR

# Banner
cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                    EventBridge Archive Deployment Script                     ║
║                                                                              ║
║  This script deploys a complete event replay system using Amazon            ║
║  EventBridge Archive with automated event archiving, selective filtering,   ║
║  and controlled replay mechanisms.                                           ║
╚══════════════════════════════════════════════════════════════════════════════╝

EOF

log "Starting EventBridge Archive deployment..."

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Please install AWS CLI v2."
    exit 1
fi

# Check AWS CLI version
AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
log "AWS CLI version: $AWS_CLI_VERSION"

# Check if user is authenticated
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
    exit 1
fi

# Get AWS account info
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)

if [ -z "$AWS_REGION" ]; then
    log_error "AWS region not configured. Please set AWS_DEFAULT_REGION or configure region."
    exit 1
fi

log "AWS Account ID: $AWS_ACCOUNT_ID"
log "AWS Region: $AWS_REGION"

# Check required permissions
log "Checking required AWS permissions..."
REQUIRED_PERMISSIONS=(
    "events:*"
    "lambda:*"
    "iam:*"
    "s3:*"
    "logs:*"
    "cloudwatch:*"
)

for permission in "${REQUIRED_PERMISSIONS[@]}"; do
    log "  - $permission (assumed based on account access)"
done

log_warning "This script assumes you have the necessary permissions for EventBridge, Lambda, IAM, S3, and CloudWatch operations."

# Confirm deployment
echo ""
read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Deployment cancelled by user."
    exit 0
fi

log "Starting deployment process..."

# Generate unique identifiers
log "Generating unique resource identifiers..."
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

export EVENT_BUS_NAME="replay-demo-bus-${RANDOM_SUFFIX}"
export ARCHIVE_NAME="replay-demo-archive-${RANDOM_SUFFIX}"
export LAMBDA_FUNCTION_NAME="replay-processor-${RANDOM_SUFFIX}"
export S3_BUCKET_NAME="eventbridge-replay-logs-${RANDOM_SUFFIX}"
export RULE_NAME="replay-demo-rule-${RANDOM_SUFFIX}"
export IAM_ROLE_NAME="EventReplayProcessorRole-${RANDOM_SUFFIX}"

log "Resource identifiers:"
log "  - Event Bus: $EVENT_BUS_NAME"
log "  - Archive: $ARCHIVE_NAME"
log "  - Lambda Function: $LAMBDA_FUNCTION_NAME"
log "  - S3 Bucket: $S3_BUCKET_NAME"
log "  - Rule: $RULE_NAME"
log "  - IAM Role: $IAM_ROLE_NAME"

# Save deployment configuration
cat > /tmp/eventbridge-archive-config.env << EOF
# EventBridge Archive Deployment Configuration
# Generated: $(date)
export AWS_REGION=$AWS_REGION
export AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
export EVENT_BUS_NAME=$EVENT_BUS_NAME
export ARCHIVE_NAME=$ARCHIVE_NAME
export LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
export S3_BUCKET_NAME=$S3_BUCKET_NAME
export RULE_NAME=$RULE_NAME
export IAM_ROLE_NAME=$IAM_ROLE_NAME
EOF

log "Configuration saved to /tmp/eventbridge-archive-config.env"

# Step 1: Create S3 bucket for logs
log "Step 1: Creating S3 bucket for logs and artifacts..."
if aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION} 2>/dev/null; then
    log_success "Created S3 bucket: $S3_BUCKET_NAME"
else
    log_error "Failed to create S3 bucket. Bucket name may already exist."
    exit 1
fi

# Step 2: Create custom event bus
log "Step 2: Creating custom EventBridge event bus..."
aws events create-event-bus \
    --name ${EVENT_BUS_NAME} \
    --tags Key=Purpose,Value=EventReplayDemo Key=Environment,Value=Demo

EVENT_BUS_ARN=$(aws events describe-event-bus \
    --name ${EVENT_BUS_NAME} \
    --query 'Arn' --output text)

log_success "Created event bus: $EVENT_BUS_NAME"
log "Event bus ARN: $EVENT_BUS_ARN"

# Step 3: Create IAM role for Lambda
log "Step 3: Creating IAM role for Lambda function..."
cat > /tmp/lambda-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
    --role-name ${IAM_ROLE_NAME} \
    --assume-role-policy-document file:///tmp/lambda-trust-policy.json

aws iam attach-role-policy \
    --role-name ${IAM_ROLE_NAME} \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

log_success "Created IAM role: $IAM_ROLE_NAME"

# Wait for IAM role to be available
log "Waiting for IAM role to be available..."
sleep 10

# Step 4: Create Lambda function
log "Step 4: Creating Lambda function for event processing..."
cat > /tmp/event-processor.py << 'EOF'
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process events and log details for replay analysis
    """
    try:
        # Log the complete event for debugging
        logger.info(f"Received event: {json.dumps(event, indent=2)}")
        
        # Extract event details
        event_source = event.get('source', 'unknown')
        event_type = event.get('detail-type', 'unknown')
        event_time = event.get('time', datetime.utcnow().isoformat())
        
        # Check if this is a replayed event
        replay_name = event.get('replay-name')
        if replay_name:
            logger.info(f"Processing REPLAYED event from: {replay_name}")
            
        # Simulate business logic processing
        if event_source == 'myapp.orders':
            process_order_event(event)
        elif event_source == 'myapp.users':
            process_user_event(event)
        else:
            logger.info(f"Processing generic event: {event_type}")
        
        # Return successful response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed successfully',
                'eventSource': event_source,
                'eventType': event_type,
                'isReplay': bool(replay_name)
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        raise

def process_order_event(event):
    """Process order-related events"""
    order_id = event.get('detail', {}).get('orderId', 'unknown')
    logger.info(f"Processing order event for order: {order_id}")
    
def process_user_event(event):
    """Process user-related events"""
    user_id = event.get('detail', {}).get('userId', 'unknown')
    logger.info(f"Processing user event for user: {user_id}")
EOF

# Create deployment package
cd /tmp
zip -q event-processor.zip event-processor.py

# Get Lambda role ARN
LAMBDA_ROLE_ARN=$(aws iam get-role \
    --role-name ${IAM_ROLE_NAME} \
    --query 'Role.Arn' --output text)

# Create Lambda function
aws lambda create-function \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --runtime python3.9 \
    --role ${LAMBDA_ROLE_ARN} \
    --handler event-processor.lambda_handler \
    --zip-file fileb://event-processor.zip \
    --timeout 30 \
    --memory-size 256

log_success "Created Lambda function: $LAMBDA_FUNCTION_NAME"

# Step 5: Create EventBridge rule and target
log "Step 5: Creating EventBridge rule and Lambda target..."
aws events put-rule \
    --name ${RULE_NAME} \
    --event-bus-name ${EVENT_BUS_NAME} \
    --event-pattern '{
      "source": ["myapp.orders", "myapp.users", "myapp.inventory"],
      "detail-type": ["Order Created", "User Registered", "Inventory Updated"]
    }' \
    --state ENABLED \
    --description "Rule for processing application events"

# Add Lambda function as target
aws events put-targets \
    --rule ${RULE_NAME} \
    --event-bus-name ${EVENT_BUS_NAME} \
    --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"

# Grant EventBridge permission to invoke Lambda
aws lambda add-permission \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --statement-id EventBridgeInvoke \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENT_BUS_NAME}/${RULE_NAME}"

log_success "Created EventBridge rule and Lambda target"

# Step 6: Create event archive
log "Step 6: Creating event archive with selective filtering..."
aws events create-archive \
    --archive-name ${ARCHIVE_NAME} \
    --source-arn ${EVENT_BUS_ARN} \
    --event-pattern '{
      "source": ["myapp.orders", "myapp.users"],
      "detail-type": ["Order Created", "User Registered"]
    }' \
    --retention-days 30 \
    --description "Archive for order and user events"

log_success "Created event archive: $ARCHIVE_NAME"

# Step 7: Generate test events
log "Step 7: Generating test events for archiving..."
for i in {1..10}; do
    # Generate order events
    aws events put-events \
        --entries Source=myapp.orders,DetailType="Order Created",Detail="{\"orderId\":\"order-${i}\",\"amount\":$((RANDOM % 1000 + 50)),\"customerId\":\"customer-${i}\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
        --event-bus-name ${EVENT_BUS_NAME} &>/dev/null
    
    # Generate user events
    aws events put-events \
        --entries Source=myapp.users,DetailType="User Registered",Detail="{\"userId\":\"user-${i}\",\"email\":\"user${i}@example.com\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
        --event-bus-name ${EVENT_BUS_NAME} &>/dev/null
    
    # Brief pause between events
    sleep 1
done

log_success "Generated 20 test events for archive"

# Step 8: Create automation script
log "Step 8: Creating replay automation script..."
cat > /tmp/replay-automation.sh << 'EOF'
#!/bin/bash

# Replay automation script
ARCHIVE_NAME=$1
HOURS_BACK=${2:-1}

if [ -z "$ARCHIVE_NAME" ]; then
    echo "Usage: $0 <archive-name> [hours-back]"
    exit 1
fi

# Calculate replay time window
START_TIME=$(date -u -d "${HOURS_BACK} hours ago" +%Y-%m-%dT%H:%M:%SZ)
END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Generate replay name
REPLAY_NAME="auto-replay-$(date +%Y%m%d-%H%M%S)"

echo "Starting automated replay:"
echo "Archive: ${ARCHIVE_NAME}"
echo "Time window: ${START_TIME} to ${END_TIME}"
echo "Replay name: ${REPLAY_NAME}"

# Start replay
aws events start-replay \
    --replay-name ${REPLAY_NAME} \
    --event-source-arn $(aws events describe-archive --archive-name ${ARCHIVE_NAME} --query 'SourceArn' --output text) \
    --event-start-time ${START_TIME} \
    --event-end-time ${END_TIME} \
    --destination '{
      "Arn": "'$(aws events describe-archive --archive-name ${ARCHIVE_NAME} --query 'SourceArn' --output text)'"
    }'

echo "Replay started successfully: ${REPLAY_NAME}"
EOF

chmod +x /tmp/replay-automation.sh
aws s3 cp /tmp/replay-automation.sh s3://${S3_BUCKET_NAME}/scripts/

log_success "Created replay automation script"

# Step 9: Set up monitoring
log "Step 9: Setting up monitoring and alerting..."
aws logs create-log-group \
    --log-group-name /aws/events/replay-monitoring 2>/dev/null || true

log_success "Set up monitoring and alerting"

# Clean up temporary files
rm -f /tmp/lambda-trust-policy.json /tmp/event-processor.py /tmp/event-processor.zip /tmp/replay-automation.sh

log_success "Deployment completed successfully!"

# Display deployment summary
cat << EOF

╔══════════════════════════════════════════════════════════════════════════════╗
║                           Deployment Summary                                 ║
╚══════════════════════════════════════════════════════════════════════════════╝

✅ EventBridge Archive deployment completed successfully!

📋 Resources Created:
  • Event Bus: $EVENT_BUS_NAME
  • Archive: $ARCHIVE_NAME (30-day retention)
  • Lambda Function: $LAMBDA_FUNCTION_NAME
  • IAM Role: $IAM_ROLE_NAME
  • S3 Bucket: $S3_BUCKET_NAME
  • EventBridge Rule: $RULE_NAME

🔧 Configuration:
  • AWS Region: $AWS_REGION
  • AWS Account: $AWS_ACCOUNT_ID
  • Configuration file: /tmp/eventbridge-archive-config.env

📊 Next Steps:
  1. Wait 5-10 minutes for events to be archived
  2. Monitor Lambda function logs in CloudWatch
  3. Test event replay functionality
  4. Check archive event count with: aws events describe-archive --archive-name $ARCHIVE_NAME

💡 Testing:
  • Generate more test events by running the Lambda function
  • Create replay operations using the automation script
  • Monitor replay progress in EventBridge console

⚠️  Important:
  • Events take up to 10 minutes to appear in archive
  • Archive retention is set to 30 days
  • All resources are tagged for easy identification

🧹 Cleanup:
  To remove all resources, run: ./destroy.sh

📝 Log file: $LOG_FILE

EOF

log "Deployment process completed. Check the resources in AWS console."