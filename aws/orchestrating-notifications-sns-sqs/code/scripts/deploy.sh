#!/bin/bash

# Deploy script for Serverless Notification Systems with SNS, SQS, and Lambda
# This script creates a scalable notification system using AWS managed services

set -e  # Exit on any error

# Script configuration
SCRIPT_NAME="deploy.sh"
LOG_FILE="/tmp/notification-system-deploy.log"
DEPLOYMENT_START_TIME=$(date +%s)

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
    local exit_code=$?
    log_error "Deployment failed with exit code $exit_code"
    log_error "Check the log file at $LOG_FILE for details"
    log_error "You may need to run the cleanup script to remove partial resources"
    exit $exit_code
}

trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if Python 3 is available
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not available. Please install Python 3."
        exit 1
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        log_error "zip command is not available. Please install zip utility."
        exit 1
    fi
    
    # Check required environment variables
    if [[ -z "${TEST_EMAIL:-}" ]]; then
        log_warning "TEST_EMAIL environment variable not set. Using default: test@example.com"
        export TEST_EMAIL="test@example.com"
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "AWS region not configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers to avoid conflicts
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    # Export resource names
    export SNS_TOPIC_NAME="notification-system-${RANDOM_SUFFIX}"
    export EMAIL_QUEUE_NAME="email-notifications-${RANDOM_SUFFIX}"
    export SMS_QUEUE_NAME="sms-notifications-${RANDOM_SUFFIX}"
    export WEBHOOK_QUEUE_NAME="webhook-notifications-${RANDOM_SUFFIX}"
    export DLQ_NAME="notification-dlq-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="NotificationLambdaRole-${RANDOM_SUFFIX}"
    export EMAIL_LAMBDA_NAME="EmailNotificationHandler-${RANDOM_SUFFIX}"
    export WEBHOOK_LAMBDA_NAME="WebhookNotificationHandler-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured"
    log "  AWS Region: $AWS_REGION"
    log "  AWS Account ID: $AWS_ACCOUNT_ID"
    log "  Random Suffix: $RANDOM_SUFFIX"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic..."
    
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query 'TopicArn' --output text)
    
    if [[ -z "$SNS_TOPIC_ARN" ]]; then
        log_error "Failed to create SNS topic"
        exit 1
    fi
    
    # Add topic policy for cross-service access
    aws sns set-topic-attributes \
        --topic-arn "$SNS_TOPIC_ARN" \
        --attribute-name Policy \
        --attribute-value '{
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Principal": {"AWS": "*"},
              "Action": "SNS:Publish",
              "Resource": "'$SNS_TOPIC_ARN'",
              "Condition": {
                "StringEquals": {
                  "aws:SourceAccount": "'$AWS_ACCOUNT_ID'"
                }
              }
            }
          ]
        }'
    
    export SNS_TOPIC_ARN
    log_success "Created SNS topic: $SNS_TOPIC_ARN"
}

# Function to create SQS queues
create_sqs_queues() {
    log "Creating SQS queues..."
    
    # Create dead letter queue first
    DLQ_URL=$(aws sqs create-queue \
        --queue-name "$DLQ_NAME" \
        --query 'QueueUrl' --output text)
    
    DLQ_ARN=$(aws sqs get-queue-attributes \
        --queue-url "$DLQ_URL" \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)
    
    # Create email processing queue
    EMAIL_QUEUE_URL=$(aws sqs create-queue \
        --queue-name "$EMAIL_QUEUE_NAME" \
        --attributes '{
          "VisibilityTimeoutSeconds": "300",
          "MessageRetentionPeriod": "1209600",
          "RedrivePolicy": "{\"deadLetterTargetArn\":\"'$DLQ_ARN'\",\"maxReceiveCount\":3}"
        }' \
        --query 'QueueUrl' --output text)
    
    # Create SMS processing queue
    SMS_QUEUE_URL=$(aws sqs create-queue \
        --queue-name "$SMS_QUEUE_NAME" \
        --attributes '{
          "VisibilityTimeoutSeconds": "300",
          "MessageRetentionPeriod": "1209600",
          "RedrivePolicy": "{\"deadLetterTargetArn\":\"'$DLQ_ARN'\",\"maxReceiveCount\":3}"
        }' \
        --query 'QueueUrl' --output text)
    
    # Create webhook processing queue
    WEBHOOK_QUEUE_URL=$(aws sqs create-queue \
        --queue-name "$WEBHOOK_QUEUE_NAME" \
        --attributes '{
          "VisibilityTimeoutSeconds": "300",
          "MessageRetentionPeriod": "1209600",
          "RedrivePolicy": "{\"deadLetterTargetArn\":\"'$DLQ_ARN'\",\"maxReceiveCount\":3}"
        }' \
        --query 'QueueUrl' --output text)
    
    # Get queue ARNs
    EMAIL_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url "$EMAIL_QUEUE_URL" \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)
    
    SMS_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url "$SMS_QUEUE_URL" \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)
    
    WEBHOOK_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url "$WEBHOOK_QUEUE_URL" \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)
    
    # Export variables for later use
    export DLQ_URL DLQ_ARN
    export EMAIL_QUEUE_URL EMAIL_QUEUE_ARN
    export SMS_QUEUE_URL SMS_QUEUE_ARN
    export WEBHOOK_QUEUE_URL WEBHOOK_QUEUE_ARN
    
    log_success "Created SQS queues with dead letter queue configuration"
}

# Function to subscribe queues to SNS topic
subscribe_queues_to_sns() {
    log "Subscribing SQS queues to SNS topic..."
    
    # Subscribe email queue with filter
    aws sns subscribe \
        --topic-arn "$SNS_TOPIC_ARN" \
        --protocol sqs \
        --notification-endpoint "$EMAIL_QUEUE_ARN" \
        --attributes '{
          "FilterPolicy": "{\"notification_type\":[\"email\",\"all\"]}",
          "RawMessageDelivery": "true"
        }'
    
    # Subscribe SMS queue with filter
    aws sns subscribe \
        --topic-arn "$SNS_TOPIC_ARN" \
        --protocol sqs \
        --notification-endpoint "$SMS_QUEUE_ARN" \
        --attributes '{
          "FilterPolicy": "{\"notification_type\":[\"sms\",\"all\"]}",
          "RawMessageDelivery": "true"
        }'
    
    # Subscribe webhook queue with filter
    aws sns subscribe \
        --topic-arn "$SNS_TOPIC_ARN" \
        --protocol sqs \
        --notification-endpoint "$WEBHOOK_QUEUE_ARN" \
        --attributes '{
          "FilterPolicy": "{\"notification_type\":[\"webhook\",\"all\"]}",
          "RawMessageDelivery": "true"
        }'
    
    log_success "Subscribed queues to SNS topic with message filtering"
}

# Function to create IAM role for Lambda
create_iam_role() {
    log "Creating IAM role for Lambda functions..."
    
    # Create trust policy document
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
    
    # Create IAM role
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
        --description "IAM role for serverless notification system Lambda functions"
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create and attach SQS access policy
    cat > /tmp/sqs-access-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:SendMessage"
      ],
      "Resource": [
        "$EMAIL_QUEUE_ARN",
        "$SMS_QUEUE_ARN",
        "$WEBHOOK_QUEUE_ARN",
        "$DLQ_ARN"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-name SQSAccessPolicy \
        --policy-document file:///tmp/sqs-access-policy.json
    
    # Get role ARN
    LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "$IAM_ROLE_NAME" \
        --query 'Role.Arn' --output text)
    
    export LAMBDA_ROLE_ARN
    log_success "Created IAM role: $LAMBDA_ROLE_ARN"
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
}

# Function to create Lambda function code
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create email handler function
    cat > /tmp/email_handler.py << 'EOF'
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Process email notification messages from SQS"""
    
    processed_messages = []
    
    for record in event['Records']:
        try:
            # Parse message body
            message_body = json.loads(record['body'])
            
            # Extract notification details
            subject = message_body.get('subject', 'Notification')
            message = message_body.get('message', '')
            recipient = message_body.get('recipient', 'default@example.com')
            priority = message_body.get('priority', 'normal')
            
            # Simulate email sending (replace with actual email service)
            logger.info(f"Sending email to {recipient}")
            logger.info(f"Subject: {subject}")
            logger.info(f"Message: {message}")
            logger.info(f"Priority: {priority}")
            
            # Here you would integrate with SES, SendGrid, or other email service
            # For demo purposes, we'll just log the email details
            
            processed_messages.append({
                'messageId': record['messageId'],
                'status': 'success',
                'recipient': recipient,
                'subject': subject
            })
            
        except Exception as e:
            logger.error(f"Error processing message {record['messageId']}: {str(e)}")
            # Message will be retried or sent to DLQ based on SQS configuration
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': len(processed_messages),
            'messages': processed_messages
        })
    }
EOF
    
    # Create webhook handler function
    cat > /tmp/webhook_handler.py << 'EOF'
import json
import logging
import urllib3
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)

http = urllib3.PoolManager()

def lambda_handler(event, context):
    """Process webhook notification messages from SQS"""
    
    processed_messages = []
    
    for record in event['Records']:
        try:
            # Parse message body
            message_body = json.loads(record['body'])
            
            # Extract webhook details
            webhook_url = message_body.get('webhook_url', '')
            payload = message_body.get('payload', {})
            headers = message_body.get('headers', {'Content-Type': 'application/json'})
            retry_count = message_body.get('retry_count', 0)
            
            if not webhook_url:
                logger.error("No webhook URL provided")
                continue
            
            # Send webhook request
            logger.info(f"Sending webhook to {webhook_url}")
            
            try:
                response = http.request(
                    'POST',
                    webhook_url,
                    body=json.dumps(payload),
                    headers=headers,
                    timeout=30
                )
                
                if response.status == 200:
                    logger.info(f"Webhook sent successfully to {webhook_url}")
                    status = 'success'
                else:
                    logger.warning(f"Webhook returned status {response.status}")
                    status = 'retry'
                    
            except Exception as webhook_error:
                logger.error(f"Webhook request failed: {str(webhook_error)}")
                status = 'failed'
                if retry_count < 3:
                    raise webhook_error  # Will trigger SQS retry
            
            processed_messages.append({
                'messageId': record['messageId'],
                'status': status,
                'webhook_url': webhook_url,
                'retry_count': retry_count
            })
            
        except Exception as e:
            logger.error(f"Error processing message {record['messageId']}: {str(e)}")
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': len(processed_messages),
            'messages': processed_messages
        })
    }
EOF
    
    # Create deployment packages
    cd /tmp
    zip -q email_handler.zip email_handler.py
    zip -q webhook_handler.zip webhook_handler.py
    cd - > /dev/null
    
    # Create email Lambda function
    EMAIL_LAMBDA_ARN=$(aws lambda create-function \
        --function-name "$EMAIL_LAMBDA_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler email_handler.lambda_handler \
        --zip-file fileb:///tmp/email_handler.zip \
        --timeout 300 \
        --description "Email notification handler for serverless notification system" \
        --query 'FunctionArn' --output text)
    
    # Create webhook Lambda function
    WEBHOOK_LAMBDA_ARN=$(aws lambda create-function \
        --function-name "$WEBHOOK_LAMBDA_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler webhook_handler.lambda_handler \
        --zip-file fileb:///tmp/webhook_handler.zip \
        --timeout 300 \
        --description "Webhook notification handler for serverless notification system" \
        --query 'FunctionArn' --output text)
    
    export EMAIL_LAMBDA_ARN WEBHOOK_LAMBDA_ARN
    log_success "Created Lambda functions"
}

# Function to create event source mappings
create_event_source_mappings() {
    log "Creating event source mappings..."
    
    # Connect email queue to email Lambda function
    aws lambda create-event-source-mapping \
        --event-source-arn "$EMAIL_QUEUE_ARN" \
        --function-name "$EMAIL_LAMBDA_NAME" \
        --batch-size 10 \
        --maximum-batching-window-in-seconds 5 \
        --starting-position LATEST
    
    # Connect webhook queue to webhook Lambda function
    aws lambda create-event-source-mapping \
        --event-source-arn "$WEBHOOK_QUEUE_ARN" \
        --function-name "$WEBHOOK_LAMBDA_NAME" \
        --batch-size 10 \
        --maximum-batching-window-in-seconds 5 \
        --starting-position LATEST
    
    log_success "Created event source mappings"
}

# Function to create test publisher
create_test_publisher() {
    log "Creating test notification publisher..."
    
    cat > /tmp/publish_notification.py << EOF
#!/usr/bin/env python3
import boto3
import json
import sys
from datetime import datetime

def publish_notification(topic_arn, notification_type, subject, message, **kwargs):
    """Publish a notification to SNS topic"""
    
    sns = boto3.client('sns')
    
    # Prepare message attributes for filtering
    message_attributes = {
        'notification_type': {
            'DataType': 'String',
            'StringValue': notification_type
        },
        'timestamp': {
            'DataType': 'String',
            'StringValue': datetime.utcnow().isoformat()
        }
    }
    
    # Prepare message body
    message_body = {
        'subject': subject,
        'message': message,
        'timestamp': datetime.utcnow().isoformat(),
        **kwargs
    }
    
    try:
        response = sns.publish(
            TopicArn=topic_arn,
            Message=json.dumps(message_body),
            Subject=subject,
            MessageAttributes=message_attributes
        )
        
        print(f"Published {notification_type} notification:")
        print(f"  Message ID: {response['MessageId']}")
        print(f"  Subject: {subject}")
        print(f"  Type: {notification_type}")
        return response['MessageId']
        
    except Exception as e:
        print(f"Error publishing notification: {e}")
        return None

if __name__ == "__main__":
    topic_arn = "$SNS_TOPIC_ARN"
    
    # Test different notification types
    notifications = [
        {
            'type': 'email',
            'subject': 'Test Email Notification',
            'message': 'This is a test email notification from the serverless notification system.',
            'recipient': '$TEST_EMAIL',
            'priority': 'high'
        },
        {
            'type': 'webhook',
            'subject': 'Test Webhook Notification',
            'message': 'This is a test webhook notification.',
            'webhook_url': 'https://httpbin.org/post',
            'payload': {
                'event': 'test_notification',
                'data': {'test': True, 'timestamp': datetime.utcnow().isoformat()}
            }
        },
        {
            'type': 'all',
            'subject': 'Broadcast Notification',
            'message': 'This notification will be sent to all channels.',
            'recipient': '$TEST_EMAIL',
            'webhook_url': 'https://httpbin.org/post',
            'payload': {'broadcast': True}
        }
    ]
    
    for notification in notifications:
        notification_type = notification.pop('type')
        subject = notification.pop('subject')
        message = notification.pop('message')
        
        message_id = publish_notification(
            topic_arn, notification_type, subject, message, **notification
        )
        
        if message_id:
            print(f"✅ Published {notification_type} notification")
        else:
            print(f"❌ Failed to publish {notification_type} notification")
        print()
EOF
    
    chmod +x /tmp/publish_notification.py
    log_success "Created test notification publisher"
}

# Function to save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > /tmp/deployment-info.json << EOF
{
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "aws_region": "$AWS_REGION",
  "aws_account_id": "$AWS_ACCOUNT_ID",
  "random_suffix": "$RANDOM_SUFFIX",
  "resources": {
    "sns_topic": {
      "name": "$SNS_TOPIC_NAME",
      "arn": "$SNS_TOPIC_ARN"
    },
    "sqs_queues": {
      "email_queue": {
        "name": "$EMAIL_QUEUE_NAME",
        "url": "$EMAIL_QUEUE_URL",
        "arn": "$EMAIL_QUEUE_ARN"
      },
      "sms_queue": {
        "name": "$SMS_QUEUE_NAME",
        "url": "$SMS_QUEUE_URL",
        "arn": "$SMS_QUEUE_ARN"
      },
      "webhook_queue": {
        "name": "$WEBHOOK_QUEUE_NAME",
        "url": "$WEBHOOK_QUEUE_URL",
        "arn": "$WEBHOOK_QUEUE_ARN"
      },
      "dead_letter_queue": {
        "name": "$DLQ_NAME",
        "url": "$DLQ_URL",
        "arn": "$DLQ_ARN"
      }
    },
    "lambda_functions": {
      "email_handler": {
        "name": "$EMAIL_LAMBDA_NAME",
        "arn": "$EMAIL_LAMBDA_ARN"
      },
      "webhook_handler": {
        "name": "$WEBHOOK_LAMBDA_NAME",
        "arn": "$WEBHOOK_LAMBDA_ARN"
      }
    },
    "iam_role": {
      "name": "$IAM_ROLE_NAME",
      "arn": "$LAMBDA_ROLE_ARN"
    }
  }
}
EOF
    
    log_success "Deployment information saved to /tmp/deployment-info.json"
}

# Function to run deployment validation
validate_deployment() {
    log "Validating deployment..."
    
    # Check SNS topic exists
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
        log_success "SNS topic validation passed"
    else
        log_error "SNS topic validation failed"
        return 1
    fi
    
    # Check SQS queues exist
    for queue_url in "$EMAIL_QUEUE_URL" "$SMS_QUEUE_URL" "$WEBHOOK_QUEUE_URL" "$DLQ_URL"; do
        if aws sqs get-queue-attributes --queue-url "$queue_url" --attribute-names QueueArn &>/dev/null; then
            queue_name=$(basename "$queue_url")
            log_success "SQS queue validation passed: $queue_name"
        else
            log_error "SQS queue validation failed: $queue_url"
            return 1
        fi
    done
    
    # Check Lambda functions exist
    for function_name in "$EMAIL_LAMBDA_NAME" "$WEBHOOK_LAMBDA_NAME"; do
        if aws lambda get-function --function-name "$function_name" &>/dev/null; then
            log_success "Lambda function validation passed: $function_name"
        else
            log_error "Lambda function validation failed: $function_name"
            return 1
        fi
    done
    
    log_success "Deployment validation completed successfully"
}

# Function to display deployment summary
display_deployment_summary() {
    local deployment_end_time=$(date +%s)
    local deployment_duration=$((deployment_end_time - DEPLOYMENT_START_TIME))
    
    echo ""
    echo "=================================="
    echo "  DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=================================="
    echo ""
    echo "📋 Deployment Summary:"
    echo "  • Region: $AWS_REGION"
    echo "  • Account ID: $AWS_ACCOUNT_ID"
    echo "  • Deployment Duration: ${deployment_duration}s"
    echo "  • Random Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "📡 Created Resources:"
    echo "  • SNS Topic: $SNS_TOPIC_NAME"
    echo "  • Email Queue: $EMAIL_QUEUE_NAME"
    echo "  • SMS Queue: $SMS_QUEUE_NAME"
    echo "  • Webhook Queue: $WEBHOOK_QUEUE_NAME"
    echo "  • Dead Letter Queue: $DLQ_NAME"
    echo "  • Email Lambda: $EMAIL_LAMBDA_NAME"
    echo "  • Webhook Lambda: $WEBHOOK_LAMBDA_NAME"
    echo "  • IAM Role: $IAM_ROLE_NAME"
    echo ""
    echo "🧪 Testing:"
    echo "  • Test publisher: /tmp/publish_notification.py"
    echo "  • Run: python3 /tmp/publish_notification.py"
    echo ""
    echo "📊 Monitoring:"
    echo "  • CloudWatch Logs: /aws/lambda/$EMAIL_LAMBDA_NAME"
    echo "  • CloudWatch Logs: /aws/lambda/$WEBHOOK_LAMBDA_NAME"
    echo ""
    echo "🔧 Cleanup:"
    echo "  • Run: ./destroy.sh"
    echo ""
    echo "📝 Deployment Info: /tmp/deployment-info.json"
    echo "📝 Deployment Log: $LOG_FILE"
    echo ""
}

# Main deployment function
main() {
    log "Starting deployment of Serverless Notification System..."
    log "Log file: $LOG_FILE"
    
    check_prerequisites
    setup_environment
    create_sns_topic
    create_sqs_queues
    subscribe_queues_to_sns
    create_iam_role
    create_lambda_functions
    create_event_source_mappings
    create_test_publisher
    save_deployment_info
    validate_deployment
    display_deployment_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"