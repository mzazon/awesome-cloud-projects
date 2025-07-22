#!/bin/bash

# Dead Letter Queue Processing with SQS - Deployment Script
# This script deploys the complete DLQ processing infrastructure
# Based on recipe: dead-letter-queue-processing-sqs-lambda

set -e

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Script information
log "Starting deployment of Dead Letter Queue Processing infrastructure"
log "This script will create: SQS queues, Lambda functions, IAM roles, and CloudWatch alarms"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    # Check required tools
    if ! command -v zip &> /dev/null; then
        error "zip command is not available. Please install zip utility."
    fi
    
    success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not set, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    export QUEUE_NAME="order-processing-${RANDOM_SUFFIX}"
    export DLQ_NAME="order-processing-dlq-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="dlq-processing-role-${RANDOM_SUFFIX}"
    export MAIN_PROCESSOR_NAME="order-processor-${RANDOM_SUFFIX}"
    export DLQ_MONITOR_NAME="dlq-monitor-${RANDOM_SUFFIX}"
    
    log "Environment variables set:"
    log "  AWS_REGION: ${AWS_REGION}"
    log "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    log "  QUEUE_NAME: ${QUEUE_NAME}"
    log "  DLQ_NAME: ${DLQ_NAME}"
    log "  LAMBDA_ROLE_NAME: ${LAMBDA_ROLE_NAME}"
    
    # Create temp directory for Lambda packages
    export TEMP_DIR=$(mktemp -d)
    log "Created temporary directory: ${TEMP_DIR}"
}

# Create IAM role for Lambda functions
create_iam_role() {
    log "Creating IAM role for Lambda functions..."
    
    local assume_role_policy='{
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
    }'
    
    if aws iam get-role --role-name ${LAMBDA_ROLE_NAME} &> /dev/null; then
        warning "IAM role ${LAMBDA_ROLE_NAME} already exists, skipping creation"
    else
        aws iam create-role \
            --role-name ${LAMBDA_ROLE_NAME} \
            --assume-role-policy-document "${assume_role_policy}" > /dev/null
        
        success "IAM role created: ${LAMBDA_ROLE_NAME}"
    fi
    
    # Attach necessary policies
    log "Attaching policies to IAM role..."
    
    aws iam attach-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess
    
    aws iam attach-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess
    
    # Wait for role to be available
    log "Waiting for IAM role to be ready..."
    sleep 10
    
    success "IAM role configuration completed"
}

# Create SQS queues
create_sqs_queues() {
    log "Creating SQS queues..."
    
    # Create dead letter queue first
    log "Creating dead letter queue..."
    DLQ_URL=$(aws sqs create-queue \
        --queue-name ${DLQ_NAME} \
        --attributes '{
            "MessageRetentionPeriod": "1209600",
            "VisibilityTimeoutSeconds": "300"
        }' \
        --query 'QueueUrl' --output text)
    
    if [ $? -eq 0 ]; then
        success "Dead Letter Queue created: ${DLQ_URL}"
    else
        error "Failed to create dead letter queue"
    fi
    
    # Get DLQ ARN
    DLQ_ARN=$(aws sqs get-queue-attributes \
        --queue-url ${DLQ_URL} \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)
    
    log "DLQ ARN: ${DLQ_ARN}"
    
    # Create main processing queue with DLQ configuration
    log "Creating main processing queue..."
    MAIN_QUEUE_URL=$(aws sqs create-queue \
        --queue-name ${QUEUE_NAME} \
        --attributes '{
            "VisibilityTimeoutSeconds": "300",
            "MessageRetentionPeriod": "1209600",
            "RedrivePolicy": "{\"deadLetterTargetArn\":\"'${DLQ_ARN}'\",\"maxReceiveCount\":3}"
        }' \
        --query 'QueueUrl' --output text)
    
    if [ $? -eq 0 ]; then
        success "Main processing queue created: ${MAIN_QUEUE_URL}"
    else
        error "Failed to create main processing queue"
    fi
    
    # Get main queue ARN
    MAIN_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url ${MAIN_QUEUE_URL} \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)
    
    log "Main queue ARN: ${MAIN_QUEUE_ARN}"
    
    # Export variables for later use
    export DLQ_URL DLQ_ARN MAIN_QUEUE_URL MAIN_QUEUE_ARN
}

# Create Lambda function packages
create_lambda_packages() {
    log "Creating Lambda function packages..."
    
    # Create main processor function
    log "Creating main processor Lambda package..."
    cat > ${TEMP_DIR}/main_processor.py << 'EOF'
import json
import logging
import random
import boto3
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Main order processing function that simulates processing failures
    """
    for record in event['Records']:
        try:
            # Parse the message
            message_body = json.loads(record['body'])
            order_id = message_body.get('orderId')
            
            logger.info(f"Processing order: {order_id}")
            
            # Simulate processing logic with intentional failures
            # In real scenarios, this would be actual business logic
            if random.random() < 0.3:  # 30% failure rate for demo
                raise Exception(f"Processing failed for order {order_id}")
            
            # Simulate successful processing
            logger.info(f"Successfully processed order: {order_id}")
            
            # In real scenarios, you would:
            # - Validate order data
            # - Update inventory
            # - Process payment
            # - Send confirmation email
            
        except Exception as e:
            logger.error(f"Error processing message: {str(e)}")
            # Let SQS handle the retry mechanism
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps('Processing completed')
    }
EOF
    
    cd ${TEMP_DIR}
    zip main_processor.zip main_processor.py
    
    # Create DLQ monitor function
    log "Creating DLQ monitor Lambda package..."
    cat > ${TEMP_DIR}/dlq_monitor.py << 'EOF'
import json
import logging
import boto3
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs = boto3.client('sqs')

def lambda_handler(event, context):
    """
    Monitor and analyze messages in the dead letter queue
    """
    for record in event['Records']:
        try:
            # Parse the failed message
            message_body = json.loads(record['body'])
            receipt_handle = record['receiptHandle']
            
            # Extract error information
            order_id = message_body.get('orderId')
            error_count = int(record.get('attributes', {}).get('ApproximateReceiveCount', '1'))
            
            logger.info(f"Analyzing failed message for order: {order_id}")
            logger.info(f"Error count: {error_count}")
            
            # Categorize error types
            error_category = categorize_error(message_body)
            
            # Log detailed error information
            logger.info(f"Error category: {error_category}")
            logger.info(f"Message attributes: {record.get('messageAttributes', {})}")
            
            # Create error metrics
            cloudwatch = boto3.client('cloudwatch')
            cloudwatch.put_metric_data(
                Namespace='DLQ/Processing',
                MetricData=[
                    {
                        'MetricName': 'FailedMessages',
                        'Value': 1,
                        'Unit': 'Count',
                        'Dimensions': [
                            {
                                'Name': 'ErrorCategory',
                                'Value': error_category
                            }
                        ]
                    }
                ]
            )
            
            # Determine if message should be retried
            if should_retry(message_body, error_count):
                logger.info(f"Message will be retried for order: {order_id}")
                send_to_retry_queue(message_body)
            else:
                logger.warning(f"Message permanently failed for order: {order_id}")
                # In production, you might send to a manual review queue
                # or trigger an alert for manual investigation
                
        except Exception as e:
            logger.error(f"Error processing DLQ message: {str(e)}")
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps('DLQ monitoring completed')
    }

def categorize_error(message_body):
    """Categorize the type of error for better analysis"""
    # In real scenarios, this would analyze the actual error
    # For demo purposes, we'll categorize based on order value
    order_value = message_body.get('orderValue', 0)
    
    if order_value > 1000:
        return 'HighValueOrder'
    elif order_value > 100:
        return 'MediumValueOrder'
    else:
        return 'LowValueOrder'

def should_retry(message_body, error_count):
    """Determine if a message should be retried"""
    # Retry logic based on error count and order characteristics
    max_retries = 2
    order_value = message_body.get('orderValue', 0)
    
    # High-value orders get more retry attempts
    if order_value > 1000:
        max_retries = 5
    
    return error_count < max_retries

def send_to_retry_queue(message_body):
    """Send message back to main queue for retry"""
    import os
    main_queue_url = os.environ.get('MAIN_QUEUE_URL')
    
    if main_queue_url:
        try:
            sqs.send_message(
                QueueUrl=main_queue_url,
                MessageBody=json.dumps(message_body),
                MessageAttributes={
                    'RetryAttempt': {
                        'StringValue': 'true',
                        'DataType': 'String'
                    }
                }
            )
            logger.info("Message sent to retry queue")
        except Exception as e:
            logger.error(f"Failed to send message to retry queue: {str(e)}")
EOF
    
    zip dlq_monitor.zip dlq_monitor.py
    
    success "Lambda packages created successfully"
}

# Create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create main processing Lambda
    log "Creating main processing Lambda function..."
    LAMBDA_ARN=$(aws lambda create-function \
        --function-name ${MAIN_PROCESSOR_NAME} \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
        --handler main_processor.lambda_handler \
        --zip-file fileb://${TEMP_DIR}/main_processor.zip \
        --timeout 30 \
        --memory-size 128 \
        --description "Main order processing function for DLQ recipe" \
        --query 'FunctionArn' --output text)
    
    if [ $? -eq 0 ]; then
        success "Main processing Lambda created: ${LAMBDA_ARN}"
    else
        error "Failed to create main processing Lambda function"
    fi
    
    # Create DLQ monitor Lambda
    log "Creating DLQ monitor Lambda function..."
    DLQ_MONITOR_ARN=$(aws lambda create-function \
        --function-name ${DLQ_MONITOR_NAME} \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
        --handler dlq_monitor.lambda_handler \
        --zip-file fileb://${TEMP_DIR}/dlq_monitor.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables="{MAIN_QUEUE_URL=${MAIN_QUEUE_URL}}" \
        --description "DLQ monitoring and analysis function" \
        --query 'FunctionArn' --output text)
    
    if [ $? -eq 0 ]; then
        success "DLQ monitor Lambda created: ${DLQ_MONITOR_ARN}"
    else
        error "Failed to create DLQ monitor Lambda function"
    fi
    
    export LAMBDA_ARN DLQ_MONITOR_ARN
}

# Configure event source mappings
configure_event_sources() {
    log "Configuring SQS event source mappings..."
    
    # Wait a moment for Lambda functions to be ready
    sleep 5
    
    # Create event source mapping for main queue
    log "Creating event source mapping for main queue..."
    MAIN_ESM_UUID=$(aws lambda create-event-source-mapping \
        --event-source-arn ${MAIN_QUEUE_ARN} \
        --function-name ${MAIN_PROCESSOR_NAME} \
        --batch-size 10 \
        --maximum-batching-window-in-seconds 5 \
        --query 'UUID' --output text)
    
    if [ $? -eq 0 ]; then
        success "Main queue event source mapping created: ${MAIN_ESM_UUID}"
    else
        error "Failed to create main queue event source mapping"
    fi
    
    # Create event source mapping for DLQ
    log "Creating event source mapping for DLQ..."
    DLQ_ESM_UUID=$(aws lambda create-event-source-mapping \
        --event-source-arn ${DLQ_ARN} \
        --function-name ${DLQ_MONITOR_NAME} \
        --batch-size 5 \
        --maximum-batching-window-in-seconds 10 \
        --query 'UUID' --output text)
    
    if [ $? -eq 0 ]; then
        success "DLQ event source mapping created: ${DLQ_ESM_UUID}"
    else
        error "Failed to create DLQ event source mapping"
    fi
    
    export MAIN_ESM_UUID DLQ_ESM_UUID
}

# Create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms..."
    
    # Create alarm for DLQ message count
    log "Creating DLQ message count alarm..."
    aws cloudwatch put-metric-alarm \
        --alarm-name "DLQ-Messages-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when messages appear in DLQ" \
        --metric-name ApproximateNumberOfVisibleMessages \
        --namespace AWS/SQS \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --dimensions Name=QueueName,Value=${DLQ_NAME}
    
    if [ $? -eq 0 ]; then
        success "DLQ message count alarm created"
    else
        warning "Failed to create DLQ message count alarm"
    fi
    
    # Create alarm for high error rate
    log "Creating high error rate alarm..."
    aws cloudwatch put-metric-alarm \
        --alarm-name "DLQ-ErrorRate-${RANDOM_SUFFIX}" \
        --alarm-description "Alert on high error rate" \
        --metric-name FailedMessages \
        --namespace DLQ/Processing \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2
    
    if [ $? -eq 0 ]; then
        success "High error rate alarm created"
    else
        warning "Failed to create high error rate alarm"
    fi
}

# Send test messages
send_test_messages() {
    log "Sending test messages to demonstrate the system..."
    
    for i in {1..10}; do
        ORDER_VALUE=$((RANDOM % 2000 + 50))
        aws sqs send-message \
            --queue-url ${MAIN_QUEUE_URL} \
            --message-body '{
                "orderId": "ORD-'$(date +%s)'-'${i}'",
                "orderValue": '${ORDER_VALUE}',
                "customerId": "CUST-'${i}'",
                "items": [
                    {
                        "productId": "PROD-'${i}'",
                        "quantity": 2,
                        "price": '${ORDER_VALUE}'
                    }
                ],
                "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
            }' > /dev/null
    done
    
    success "Test messages sent to main queue"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > deployment-info.json << EOF
{
    "deploymentTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "randomSuffix": "${RANDOM_SUFFIX}",
    "region": "${AWS_REGION}",
    "accountId": "${AWS_ACCOUNT_ID}",
    "resources": {
        "iamRole": "${LAMBDA_ROLE_NAME}",
        "mainQueue": {
            "name": "${QUEUE_NAME}",
            "url": "${MAIN_QUEUE_URL}",
            "arn": "${MAIN_QUEUE_ARN}"
        },
        "deadLetterQueue": {
            "name": "${DLQ_NAME}",
            "url": "${DLQ_URL}",
            "arn": "${DLQ_ARN}"
        },
        "lambdaFunctions": {
            "mainProcessor": {
                "name": "${MAIN_PROCESSOR_NAME}",
                "arn": "${LAMBDA_ARN}"
            },
            "dlqMonitor": {
                "name": "${DLQ_MONITOR_NAME}",
                "arn": "${DLQ_MONITOR_ARN}"
            }
        },
        "eventSourceMappings": {
            "mainQueue": "${MAIN_ESM_UUID}",
            "dlq": "${DLQ_ESM_UUID}"
        },
        "alarms": [
            "DLQ-Messages-${RANDOM_SUFFIX}",
            "DLQ-ErrorRate-${RANDOM_SUFFIX}"
        ]
    }
}
EOF
    
    success "Deployment information saved to deployment-info.json"
}

# Cleanup temporary files
cleanup_temp() {
    log "Cleaning up temporary files..."
    rm -rf ${TEMP_DIR}
    success "Temporary files cleaned up"
}

# Display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    echo ""
    echo "🎉 Dead Letter Queue Processing Infrastructure Deployed"
    echo ""
    echo "📋 Resources Created:"
    echo "  • IAM Role: ${LAMBDA_ROLE_NAME}"
    echo "  • Main Queue: ${QUEUE_NAME}"
    echo "  • Dead Letter Queue: ${DLQ_NAME}"
    echo "  • Main Processor Lambda: ${MAIN_PROCESSOR_NAME}"
    echo "  • DLQ Monitor Lambda: ${DLQ_MONITOR_NAME}"
    echo "  • CloudWatch Alarms: 2 alarms created"
    echo ""
    echo "🔗 Useful Commands:"
    echo "  # Check queue depths"
    echo "  aws sqs get-queue-attributes --queue-url ${MAIN_QUEUE_URL} --attribute-names ApproximateNumberOfMessages"
    echo "  aws sqs get-queue-attributes --queue-url ${DLQ_URL} --attribute-names ApproximateNumberOfMessages"
    echo ""
    echo "  # View Lambda logs"
    echo "  aws logs filter-log-events --log-group-name /aws/lambda/${MAIN_PROCESSOR_NAME}"
    echo "  aws logs filter-log-events --log-group-name /aws/lambda/${DLQ_MONITOR_NAME}"
    echo ""
    echo "💡 Next Steps:"
    echo "  1. Monitor CloudWatch logs for processing activity"
    echo "  2. Check DLQ for failed messages after a few minutes"
    echo "  3. Review CloudWatch metrics for error patterns"
    echo "  4. Use destroy.sh to clean up resources when done"
    echo ""
    echo "💰 Cost Monitoring:"
    echo "  Monitor your AWS billing dashboard for Lambda invocations and SQS requests"
    echo ""
}

# Main execution
main() {
    check_prerequisites
    setup_environment
    create_iam_role
    create_sqs_queues
    create_lambda_packages
    create_lambda_functions
    configure_event_sources
    create_cloudwatch_alarms
    send_test_messages
    save_deployment_info
    cleanup_temp
    display_summary
}

# Execute main function
main "$@"