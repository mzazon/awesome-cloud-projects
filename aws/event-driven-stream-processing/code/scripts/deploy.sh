#!/bin/bash

# Deploy script for Real-Time Data Processing with Amazon Kinesis and Lambda
# This script creates a complete serverless data processing pipeline

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script metadata
SCRIPT_NAME="deploy.sh"
SCRIPT_VERSION="1.0"
RECIPE_NAME="real-time-data-processing-with-kinesis-lambda"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handler
error_handler() {
    local line_number=$1
    log_error "Script failed at line $line_number"
    log_error "Deployment failed. Check the logs above for details."
    exit 1
}

trap 'error_handler ${LINENO}' ERR

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Real-Time Data Processing Pipeline with Kinesis and Lambda

OPTIONS:
    -h, --help              Show this help message
    -e, --email EMAIL       Email address for CloudWatch alarm notifications
    -r, --region REGION     AWS region (default: current configured region)
    -s, --suffix SUFFIX     Custom suffix for resource names (default: random)
    --dry-run              Validate prerequisites without deploying
    --skip-test-data       Skip generating test data after deployment
    -v, --verbose          Enable verbose logging

EXAMPLES:
    $0                                    # Deploy with default settings
    $0 -e admin@company.com              # Deploy with email notifications
    $0 --region us-west-2                # Deploy to specific region
    $0 --dry-run                         # Validate without deploying

EOF
}

# Default values
DRY_RUN=false
SKIP_TEST_DATA=false
VERBOSE=false
EMAIL_ADDRESS=""
CUSTOM_SUFFIX=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -e|--email)
            EMAIL_ADDRESS="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -s|--suffix)
            CUSTOM_SUFFIX="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-test-data)
            SKIP_TEST_DATA=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Enable verbose logging if requested
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

log_info "Starting deployment of Real-Time Data Processing Pipeline"
log_info "Script: $SCRIPT_NAME v$SCRIPT_VERSION"

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
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
    
    # Check if Python is available for test data generator
    if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
        log_warning "Python is not available. Test data generation will be skipped."
        SKIP_TEST_DATA=true
    fi
    
    # Check required permissions (basic check)
    local caller_arn=$(aws sts get-caller-identity --query 'Arn' --output text)
    log_info "Deploying as: $caller_arn"
    
    # Validate AWS region
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            log_error "AWS region not configured. Set it with 'aws configure' or use --region option."
            exit 1
        fi
    fi
    
    log_info "Using AWS region: $AWS_REGION"
    
    # Check if region is valid
    if ! aws ec2 describe-regions --region-names "$AWS_REGION" &> /dev/null; then
        log_error "Invalid AWS region: $AWS_REGION"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Initialize environment variables
initialize_environment() {
    log_info "Initializing environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    if [[ -n "$CUSTOM_SUFFIX" ]]; then
        RANDOM_SUFFIX="$CUSTOM_SUFFIX"
    else
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 8 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            openssl rand -hex 4)
    fi
    
    # Set resource names with random suffix to ensure uniqueness
    export STREAM_NAME="retail-events-stream-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="retail-event-processor-${RANDOM_SUFFIX}"
    export DYNAMODB_TABLE="retail-events-data-${RANDOM_SUFFIX}"
    export DLQ_QUEUE_NAME="failed-events-dlq-${RANDOM_SUFFIX}"
    export ALARM_NAME="stream-processing-errors-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="retail-event-processor-role-${RANDOM_SUFFIX}"
    export POLICY_NAME="retail-event-processor-policy-${RANDOM_SUFFIX}"
    
    log_info "Resource suffix: $RANDOM_SUFFIX"
    log_info "Stream name: $STREAM_NAME"
    log_info "Lambda function: $LAMBDA_FUNCTION_NAME"
    
    log_success "Environment variables initialized"
}

# Create Kinesis Data Stream
create_kinesis_stream() {
    log_info "Creating Kinesis Data Stream: $STREAM_NAME"
    
    aws kinesis create-stream \
        --stream-name "$STREAM_NAME" \
        --shard-count 1 \
        --region "$AWS_REGION"
    
    log_info "Waiting for stream to become active..."
    aws kinesis wait stream-exists \
        --stream-name "$STREAM_NAME" \
        --region "$AWS_REGION"
    
    # Retrieve and store the stream ARN
    export STREAM_ARN=$(aws kinesis describe-stream \
        --stream-name "$STREAM_NAME" \
        --query 'StreamDescription.StreamARN' \
        --output text \
        --region "$AWS_REGION")
    
    log_success "Kinesis Data Stream created: $STREAM_NAME"
}

# Create DynamoDB Table
create_dynamodb_table() {
    log_info "Creating DynamoDB table: $DYNAMODB_TABLE"
    
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --attribute-definitions \
            AttributeName=userId,AttributeType=S \
            AttributeName=eventTimestamp,AttributeType=N \
        --key-schema \
            AttributeName=userId,KeyType=HASH \
            AttributeName=eventTimestamp,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Project,Value=RetailAnalytics Key=Environment,Value=Development \
        --region "$AWS_REGION"
    
    log_info "Waiting for table to become active..."
    aws dynamodb wait table-exists \
        --table-name "$DYNAMODB_TABLE" \
        --region "$AWS_REGION"
    
    # Retrieve and store the table ARN
    export TABLE_ARN=$(aws dynamodb describe-table \
        --table-name "$DYNAMODB_TABLE" \
        --query 'Table.TableArn' \
        --output text \
        --region "$AWS_REGION")
    
    log_success "DynamoDB table created: $DYNAMODB_TABLE"
}

# Create SQS Dead Letter Queue
create_sqs_dlq() {
    log_info "Creating SQS Dead Letter Queue: $DLQ_QUEUE_NAME"
    
    export DLQ_URL=$(aws sqs create-queue \
        --queue-name "$DLQ_QUEUE_NAME" \
        --attributes '{
            "MessageRetentionPeriod": "1209600",
            "VisibilityTimeout": "30"
        }' \
        --query 'QueueUrl' \
        --output text \
        --region "$AWS_REGION")
    
    # Get the queue ARN
    export DLQ_ARN=$(aws sqs get-queue-attributes \
        --queue-url "$DLQ_URL" \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' \
        --output text \
        --region "$AWS_REGION")
    
    log_success "Dead Letter Queue created: $DLQ_QUEUE_NAME"
}

# Create IAM Role for Lambda
create_iam_role() {
    log_info "Creating IAM role for Lambda: $LAMBDA_ROLE_NAME"
    
    # Create the trust policy document for Lambda
    cat > /tmp/lambda-trust-policy.json << EOF
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
    
    # Create the IAM role
    export LAMBDA_ROLE_ARN=$(aws iam create-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
        --query 'Role.Arn' \
        --output text)
    
    # Create custom policy for Lambda
    cat > /tmp/lambda-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kinesis:DescribeStream",
        "kinesis:GetRecords",
        "kinesis:GetShardIterator",
        "kinesis:ListShards"
      ],
      "Resource": "$STREAM_ARN"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem"
      ],
      "Resource": "$TABLE_ARN"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage"
      ],
      "Resource": "$DLQ_ARN"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    # Attach custom policy to the role
    export POLICY_ARN=$(aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file:///tmp/lambda-policy.json \
        --query 'Policy.Arn' \
        --output text)
    
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn "$POLICY_ARN"
    
    log_info "Waiting for IAM role propagation..."
    sleep 15
    
    log_success "IAM role created: $LAMBDA_ROLE_NAME"
}

# Create Lambda Function
create_lambda_function() {
    log_info "Creating Lambda function: $LAMBDA_FUNCTION_NAME"
    
    # Create a temporary directory for Lambda code
    local lambda_dir="/tmp/lambda-function-$$"
    mkdir -p "$lambda_dir"
    
    # Create the Lambda function handler code
    cat > "$lambda_dir/lambda_function.py" << 'EOF'
import json
import base64
import boto3
import time
import os
import uuid
from datetime import datetime

# Initialize DynamoDB client
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

# Initialize CloudWatch client
cloudwatch = boto3.client('cloudwatch')

# Initialize SQS client for DLQ
sqs = boto3.client('sqs')

def process_event(event_data):
    """Process a single event and return results"""
    # Extract required fields
    user_id = event_data.get('userId')
    event_type = event_data.get('eventType')
    product_id = event_data.get('productId', 'unknown')
    timestamp = int(event_data.get('timestamp', int(time.time() * 1000)))
    
    # Simple logic based on event type
    if event_type == 'view':
        action = 'viewed'
        event_score = 1
    elif event_type == 'add_to_cart':
        action = 'added to cart'
        event_score = 5
    elif event_type == 'purchase':
        action = 'purchased'
        event_score = 10
    else:
        action = 'interacted with'
        event_score = 1
        
    # Generate a simple insight based on the event
    insight = f"User {user_id} {action} product {product_id}"
    
    # Data enrichment: add processing metadata
    processed_data = {
        'userId': user_id,
        'eventTimestamp': timestamp,
        'eventType': event_type,
        'productId': product_id,
        'eventScore': event_score,
        'insight': insight,
        'processedAt': int(time.time() * 1000),
        'recordId': str(uuid.uuid4())
    }
    
    return processed_data

def lambda_handler(event, context):
    """Process records from Kinesis stream"""
    processed_count = 0
    failed_count = 0
    
    # Process each record in the batch
    for record in event['Records']:
        # Decode and parse the record data
        try:
            # Kinesis data is base64 encoded
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            event_data = json.loads(payload)
            
            # Process the event
            processed_data = process_event(event_data)
            
            # Store result in DynamoDB
            table.put_item(Item=processed_data)
            
            processed_count += 1
            
        except Exception as e:
            failed_count += 1
            print(f"Error processing record: {str(e)}")
            
            # Send failed record to DLQ
            try:
                sqs.send_message(
                    QueueUrl=os.environ['DLQ_URL'],
                    MessageBody=json.dumps({
                        'error': str(e),
                        'record': record['kinesis']['data'],
                        'timestamp': datetime.utcnow().isoformat()
                    })
                )
            except Exception as dlq_error:
                print(f"Error sending to DLQ: {str(dlq_error)}")
    
    # Send custom metrics to CloudWatch
    try:
        cloudwatch.put_metric_data(
            Namespace='RetailEventProcessing',
            MetricData=[
                {
                    'MetricName': 'ProcessedEvents',
                    'Value': processed_count,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'FailedEvents',
                    'Value': failed_count,
                    'Unit': 'Count'
                }
            ]
        )
    except Exception as metric_error:
        print(f"Error publishing metrics: {str(metric_error)}")
    
    # Return summary
    return {
        'processed': processed_count,
        'failed': failed_count,
        'total': processed_count + failed_count
    }
EOF
    
    # Create a ZIP file for Lambda deployment
    cd "$lambda_dir"
    zip -r "/tmp/retail-event-processor-$$.zip" .
    cd - > /dev/null
    
    # Create the Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.8 \
        --handler lambda_function.lambda_handler \
        --role "$LAMBDA_ROLE_ARN" \
        --zip-file "fileb:///tmp/retail-event-processor-$$.zip" \
        --timeout 120 \
        --memory-size 256 \
        --environment "Variables={DYNAMODB_TABLE=$DYNAMODB_TABLE,DLQ_URL=$DLQ_URL}" \
        --tracing-config Mode=Active \
        --region "$AWS_REGION"
    
    # Clean up temporary files
    rm -rf "$lambda_dir"
    rm -f "/tmp/retail-event-processor-$$.zip"
    
    log_success "Lambda function created: $LAMBDA_FUNCTION_NAME"
}

# Configure Lambda Event Source Mapping
create_event_source_mapping() {
    log_info "Creating Lambda event source mapping"
    
    export EVENT_SOURCE_UUID=$(aws lambda create-event-source-mapping \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --event-source-arn "$STREAM_ARN" \
        --batch-size 100 \
        --maximum-batching-window-in-seconds 5 \
        --starting-position LATEST \
        --query 'UUID' \
        --output text \
        --region "$AWS_REGION")
    
    log_success "Lambda event source mapping created: $EVENT_SOURCE_UUID"
}

# Create CloudWatch Alarm
create_cloudwatch_alarm() {
    log_info "Creating CloudWatch alarm: $ALARM_NAME"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$ALARM_NAME" \
        --alarm-description "Alert when too many events fail processing" \
        --metric-name FailedEvents \
        --namespace RetailEventProcessing \
        --statistic Sum \
        --period 60 \
        --evaluation-periods 1 \
        --threshold 10 \
        --comparison-operator GreaterThanThreshold \
        --treat-missing-data notBreaching \
        --region "$AWS_REGION"
    
    # Set up SNS notifications if email provided
    if [[ -n "$EMAIL_ADDRESS" ]]; then
        log_info "Setting up SNS notifications for email: $EMAIL_ADDRESS"
        
        export ALERT_TOPIC_NAME="retail-event-alerts-${RANDOM_SUFFIX}"
        export ALERT_TOPIC_ARN=$(aws sns create-topic \
            --name "$ALERT_TOPIC_NAME" \
            --query 'TopicArn' \
            --output text \
            --region "$AWS_REGION")
        
        aws sns subscribe \
            --topic-arn "$ALERT_TOPIC_ARN" \
            --protocol email \
            --notification-endpoint "$EMAIL_ADDRESS" \
            --region "$AWS_REGION"
        
        aws cloudwatch put-metric-alarm \
            --alarm-name "$ALARM_NAME" \
            --alarm-description "Alert when too many events fail processing" \
            --metric-name FailedEvents \
            --namespace RetailEventProcessing \
            --statistic Sum \
            --period 60 \
            --evaluation-periods 1 \
            --threshold 10 \
            --comparison-operator GreaterThanThreshold \
            --treat-missing-data notBreaching \
            --alarm-actions "$ALERT_TOPIC_ARN" \
            --region "$AWS_REGION"
        
        log_warning "Please check your email to confirm the SNS subscription"
    fi
    
    log_success "CloudWatch alarm created: $ALARM_NAME"
}

# Create test data generator
create_test_data_generator() {
    if [[ "$SKIP_TEST_DATA" == "true" ]]; then
        log_info "Skipping test data generator creation"
        return
    fi
    
    log_info "Creating test data generator script"
    
    cat > generate_test_data.py << 'EOF'
import boto3
import json
import uuid
import time
import random
import sys

# Initialize Kinesis client
kinesis = boto3.client('kinesis')

# Event types and sample product IDs
EVENT_TYPES = ['view', 'add_to_cart', 'purchase']
PRODUCT_IDS = [f'P{i:04d}' for i in range(1, 101)]
USER_IDS = [f'user-{uuid.uuid4()}' for _ in range(20)]

def generate_event():
    """Generate a random retail event"""
    user_id = random.choice(USER_IDS)
    event_type = random.choice(EVENT_TYPES)
    product_id = random.choice(PRODUCT_IDS)
    
    return {
        'userId': user_id,
        'eventType': event_type,
        'productId': product_id,
        'timestamp': int(time.time() * 1000),
        'sessionId': str(uuid.uuid4()),
        'userAgent': 'Mozilla/5.0',
        'ipAddress': f'192.168.{random.randint(1, 255)}.{random.randint(1, 255)}'
    }

def put_record_to_stream(stream_name, record):
    """Put a single record to Kinesis stream"""
    result = kinesis.put_record(
        StreamName=stream_name,
        Data=json.dumps(record),
        PartitionKey=record['userId']
    )
    return result

def main(stream_name, count=100, delay=0.1):
    """Generate and send events to Kinesis"""
    print(f"Sending {count} events to stream {stream_name}")
    
    for i in range(count):
        event = generate_event()
        result = put_record_to_stream(stream_name, event)
        
        # Print progress every 10 events
        if (i + 1) % 10 == 0:
            print(f"Sent {i + 1}/{count} events")
        
        # Add small delay to prevent throttling
        time.sleep(delay)
    
    print("Done sending events")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python generate_test_data.py <stream_name> [event_count] [delay_seconds]")
        sys.exit(1)
        
    stream_name = sys.argv[1]
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    delay = float(sys.argv[3]) if len(sys.argv) > 3 else 0.1
    
    main(stream_name, count, delay)
EOF
    
    chmod +x generate_test_data.py
    
    log_success "Test data generator created: generate_test_data.py"
}

# Generate test data
generate_test_data() {
    if [[ "$SKIP_TEST_DATA" == "true" ]]; then
        log_info "Skipping test data generation"
        return
    fi
    
    log_info "Generating test data for the pipeline"
    
    # Determine Python command
    local python_cmd="python3"
    if ! command -v python3 &> /dev/null; then
        python_cmd="python"
    fi
    
    # Send test data to the Kinesis stream
    AWS_DEFAULT_REGION="$AWS_REGION" $python_cmd generate_test_data.py "$STREAM_NAME" 50 0.2
    
    log_info "Waiting 30 seconds for events to be processed..."
    sleep 30
    
    log_success "Test data sent to Kinesis stream"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information"
    
    cat > deployment-info.json << EOF
{
  "deploymentInfo": {
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "region": "$AWS_REGION",
    "accountId": "$AWS_ACCOUNT_ID",
    "suffix": "$RANDOM_SUFFIX"
  },
  "resources": {
    "kinesisStream": {
      "name": "$STREAM_NAME",
      "arn": "$STREAM_ARN"
    },
    "lambdaFunction": {
      "name": "$LAMBDA_FUNCTION_NAME",
      "roleArn": "$LAMBDA_ROLE_ARN"
    },
    "dynamodbTable": {
      "name": "$DYNAMODB_TABLE",
      "arn": "$TABLE_ARN"
    },
    "sqsQueue": {
      "name": "$DLQ_QUEUE_NAME",
      "url": "$DLQ_URL",
      "arn": "$DLQ_ARN"
    },
    "cloudwatchAlarm": {
      "name": "$ALARM_NAME"
    },
    "eventSourceMapping": {
      "uuid": "$EVENT_SOURCE_UUID"
    }
  }
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

# Clean up temporary files
cleanup_temp_files() {
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/lambda-policy.json
}

# Main deployment function
main() {
    log_info "=== Real-Time Data Processing Pipeline Deployment ==="
    
    check_prerequisites
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "Dry run completed successfully. Prerequisites check passed."
        exit 0
    fi
    
    initialize_environment
    
    # Deploy infrastructure components
    create_kinesis_stream
    create_dynamodb_table
    create_sqs_dlq
    create_iam_role
    create_lambda_function
    create_event_source_mapping
    create_cloudwatch_alarm
    create_test_data_generator
    generate_test_data
    save_deployment_info
    cleanup_temp_files
    
    # Display deployment summary
    cat << EOF

=== DEPLOYMENT COMPLETED SUCCESSFULLY ===

Resources created:
- Kinesis Stream: $STREAM_NAME
- Lambda Function: $LAMBDA_FUNCTION_NAME
- DynamoDB Table: $DYNAMODB_TABLE
- SQS Dead Letter Queue: $DLQ_QUEUE_NAME
- CloudWatch Alarm: $ALARM_NAME

Next steps:
1. Monitor the pipeline using CloudWatch dashboard
2. Generate additional test data: python generate_test_data.py $STREAM_NAME
3. Query processed data in DynamoDB table: $DYNAMODB_TABLE

To destroy all resources, run: ./destroy.sh

Deployment information saved to: deployment-info.json

EOF

    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"