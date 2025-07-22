#!/bin/bash

# Deployment script for Serverless Real-Time Analytics Pipeline with Kinesis and Lambda
# This script deploys the complete infrastructure described in the recipe

set -euo pipefail

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if AWS CLI is configured
check_aws_config() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured or credentials are invalid"
        error "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $aws_version"
    
    # Check AWS configuration
    check_aws_config
    
    # Check required permissions
    log "Validating AWS permissions..."
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    log "AWS Account ID: $account_id"
    
    # Check if jq is available (optional but helpful)
    if command_exists jq; then
        log "jq is available for JSON parsing"
    else
        warning "jq is not installed. Some output may be less readable."
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(date +%s | tail -c 6)
    
    export KINESIS_STREAM_NAME="real-time-analytics-stream-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="kinesis-stream-processor-${RANDOM_SUFFIX}"
    export DYNAMODB_TABLE_NAME="analytics-results-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="kinesis-lambda-processor-role-${RANDOM_SUFFIX}"
    
    log "Resource names configured with suffix: ${RANDOM_SUFFIX}"
    log "Kinesis Stream: $KINESIS_STREAM_NAME"
    log "Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "DynamoDB Table: $DYNAMODB_TABLE_NAME"
    log "IAM Role: $IAM_ROLE_NAME"
    
    # Save environment variables for cleanup script
    cat > .env << EOF
KINESIS_STREAM_NAME=$KINESIS_STREAM_NAME
LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
DYNAMODB_TABLE_NAME=$DYNAMODB_TABLE_NAME
IAM_ROLE_NAME=$IAM_ROLE_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    success "Environment variables configured"
}

# Function to create DynamoDB table
create_dynamodb_table() {
    log "Creating DynamoDB table: $DYNAMODB_TABLE_NAME"
    
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE_NAME" \
        --attribute-definitions \
            AttributeName=eventId,AttributeType=S \
            AttributeName=timestamp,AttributeType=N \
        --key-schema \
            AttributeName=eventId,KeyType=HASH \
            AttributeName=timestamp,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --stream-specification StreamEnabled=false \
        --tags Key=Project,Value=RealTimeAnalytics Key=Environment,Value=Demo
    
    log "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE_NAME"
    
    success "DynamoDB table created successfully"
}

# Function to create IAM role and policies
create_iam_role() {
    log "Creating IAM role and policies..."
    
    # Create Lambda execution policy
    cat > lambda-kinesis-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "kinesis:DescribeStream",
                "kinesis:DescribeStreamSummary",
                "kinesis:GetRecords",
                "kinesis:GetShardIterator",
                "kinesis:ListShards",
                "kinesis:ListStreams",
                "kinesis:SubscribeToShard"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        }
    ]
}
EOF

    # Create Lambda trust policy
    cat > lambda-trust-policy.json << 'EOF'
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
        --assume-role-policy-document file://lambda-trust-policy.json \
        --tags Key=Project,Value=RealTimeAnalytics
    
    # Attach custom policy to role
    aws iam put-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-name KinesisLambdaProcessorPolicy \
        --policy-document file://lambda-kinesis-policy.json
    
    # Get role ARN
    LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "$IAM_ROLE_NAME" \
        --query 'Role.Arn' --output text)
    export LAMBDA_ROLE_ARN
    
    log "Lambda role ARN: $LAMBDA_ROLE_ARN"
    
    # Add role ARN to environment file
    echo "LAMBDA_ROLE_ARN=$LAMBDA_ROLE_ARN" >> .env
    
    success "IAM role and policies created successfully"
}

# Function to create Kinesis Data Stream
create_kinesis_stream() {
    log "Creating Kinesis Data Stream: $KINESIS_STREAM_NAME"
    
    aws kinesis create-stream \
        --stream-name "$KINESIS_STREAM_NAME" \
        --shard-count 2
    
    log "Waiting for Kinesis stream to become active..."
    aws kinesis wait stream-exists --stream-name "$KINESIS_STREAM_NAME"
    
    # Get stream ARN
    KINESIS_STREAM_ARN=$(aws kinesis describe-stream \
        --stream-name "$KINESIS_STREAM_NAME" \
        --query 'StreamDescription.StreamARN' --output text)
    export KINESIS_STREAM_ARN
    
    log "Kinesis Stream ARN: $KINESIS_STREAM_ARN"
    
    # Add stream ARN to environment file
    echo "KINESIS_STREAM_ARN=$KINESIS_STREAM_ARN" >> .env
    
    success "Kinesis Data Stream created successfully"
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function code..."
    
    # Create Lambda function directory
    mkdir -p lambda-processor
    cd lambda-processor

    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import base64
import time
from datetime import datetime
from decimal import Decimal

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')

# Get table reference
table = dynamodb.Table('analytics-results')

def lambda_handler(event, context):
    """
    Process Kinesis stream records and store analytics in DynamoDB
    """
    print(f"Received {len(event['Records'])} records from Kinesis")
    
    processed_records = 0
    failed_records = 0
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data'])
            data = json.loads(payload.decode('utf-8'))
            
            # Extract event information
            event_id = record['kinesis']['sequenceNumber']
            timestamp = int(record['kinesis']['approximateArrivalTimestamp'])
            
            # Process the data (example: calculate metrics)
            processed_data = process_analytics_data(data)
            
            # Store in DynamoDB
            store_analytics_result(event_id, timestamp, processed_data, data)
            
            # Send custom metrics to CloudWatch
            send_custom_metrics(processed_data)
            
            processed_records += 1
            
        except Exception as e:
            print(f"Error processing record: {str(e)}")
            failed_records += 1
            continue
    
    print(f"Successfully processed {processed_records} records, {failed_records} failed")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': processed_records,
            'failed': failed_records
        })
    }

def process_analytics_data(data):
    """
    Process incoming data and calculate analytics metrics
    """
    processed = {
        'event_type': data.get('eventType', 'unknown'),
        'user_id': data.get('userId', 'anonymous'),
        'session_id': data.get('sessionId', ''),
        'device_type': data.get('deviceType', 'unknown'),
        'location': data.get('location', {}),
        'metrics': {}
    }
    
    # Calculate custom metrics based on event type
    if data.get('eventType') == 'page_view':
        processed['metrics'] = {
            'page_url': data.get('pageUrl', ''),
            'load_time': data.get('loadTime', 0),
            'bounce_rate': calculate_bounce_rate(data)
        }
    elif data.get('eventType') == 'purchase':
        processed['metrics'] = {
            'amount': Decimal(str(data.get('amount', 0))),
            'currency': data.get('currency', 'USD'),
            'items_count': data.get('itemsCount', 0)
        }
    elif data.get('eventType') == 'user_signup':
        processed['metrics'] = {
            'signup_method': data.get('signupMethod', 'email'),
            'campaign_source': data.get('campaignSource', 'direct')
        }
    
    return processed

def calculate_bounce_rate(data):
    """
    Example calculation for bounce rate analytics
    """
    session_length = data.get('sessionLength', 0)
    pages_viewed = data.get('pagesViewed', 1)
    
    # Simple bounce rate calculation
    if session_length < 30 and pages_viewed == 1:
        return 1.0  # High bounce rate
    else:
        return 0.0  # Low bounce rate

def store_analytics_result(event_id, timestamp, processed_data, raw_data):
    """
    Store processed analytics in DynamoDB
    """
    try:
        table.put_item(
            Item={
                'eventId': event_id,
                'timestamp': timestamp,
                'processedAt': int(time.time()),
                'eventType': processed_data['event_type'],
                'userId': processed_data['user_id'],
                'sessionId': processed_data['session_id'],
                'deviceType': processed_data['device_type'],
                'location': processed_data['location'],
                'metrics': processed_data['metrics'],
                'rawData': raw_data
            }
        )
    except Exception as e:
        print(f"Error storing data in DynamoDB: {str(e)}")
        raise

def send_custom_metrics(processed_data):
    """
    Send custom metrics to CloudWatch
    """
    try:
        # Send event type metrics
        cloudwatch.put_metric_data(
            Namespace='RealTimeAnalytics',
            MetricData=[
                {
                    'MetricName': 'EventsProcessed',
                    'Dimensions': [
                        {
                            'Name': 'EventType',
                            'Value': processed_data['event_type']
                        },
                        {
                            'Name': 'DeviceType',
                            'Value': processed_data['device_type']
                        }
                    ],
                    'Value': 1,
                    'Unit': 'Count'
                }
            ]
        )
        
        # Send purchase metrics if applicable
        if processed_data['event_type'] == 'purchase':
            cloudwatch.put_metric_data(
                Namespace='RealTimeAnalytics',
                MetricData=[
                    {
                        'MetricName': 'PurchaseAmount',
                        'Value': float(processed_data['metrics']['amount']),
                        'Unit': 'None'
                    }
                ]
            )
            
    except Exception as e:
        print(f"Error sending CloudWatch metrics: {str(e)}")
        # Don't raise exception to avoid processing failure
EOF

    # Create deployment package
    zip -r ../lambda-processor.zip .
    cd ..
    
    log "Deploying Lambda function: $LAMBDA_FUNCTION_NAME"
    
    # Wait a bit for IAM role to propagate
    log "Waiting for IAM role to propagate..."
    sleep 10
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda-processor.zip \
        --timeout 300 \
        --memory-size 512 \
        --environment Variables="{DYNAMODB_TABLE=$DYNAMODB_TABLE_NAME}" \
        --tags Project=RealTimeAnalytics,Environment=Demo
    
    # Get Lambda function ARN
    LAMBDA_FUNCTION_ARN=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Configuration.FunctionArn' --output text)
    export LAMBDA_FUNCTION_ARN
    
    log "Lambda Function ARN: $LAMBDA_FUNCTION_ARN"
    
    # Add function ARN to environment file
    echo "LAMBDA_FUNCTION_ARN=$LAMBDA_FUNCTION_ARN" >> .env
    
    success "Lambda function created successfully"
}

# Function to create event source mapping
create_event_source_mapping() {
    log "Creating event source mapping between Kinesis and Lambda..."
    
    # Wait a bit for Kinesis stream to be fully available
    sleep 5
    
    EVENT_SOURCE_MAPPING_UUID=$(aws lambda create-event-source-mapping \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --event-source-arn "$KINESIS_STREAM_ARN" \
        --starting-position LATEST \
        --batch-size 100 \
        --maximum-batching-window-in-seconds 5 \
        --query 'UUID' --output text)
    
    export EVENT_SOURCE_MAPPING_UUID
    
    log "Event Source Mapping UUID: $EVENT_SOURCE_MAPPING_UUID"
    
    # Add mapping UUID to environment file
    echo "EVENT_SOURCE_MAPPING_UUID=$EVENT_SOURCE_MAPPING_UUID" >> .env
    
    success "Event source mapping created successfully"
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms for monitoring..."
    
    # Create CloudWatch alarm for Lambda errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "KinesisLambdaProcessorErrors-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor Lambda processing errors" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
        --tags Key=Project,Value=RealTimeAnalytics
    
    # Create CloudWatch alarm for DynamoDB throttling
    aws cloudwatch put-metric-alarm \
        --alarm-name "DynamoDBThrottling-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor DynamoDB throttling events" \
        --metric-name ThrottledRequests \
        --namespace AWS/DynamoDB \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --dimensions Name=TableName,Value="$DYNAMODB_TABLE_NAME" \
        --tags Key=Project,Value=RealTimeAnalytics
    
    # Add alarm names to environment file
    echo "LAMBDA_ERROR_ALARM=KinesisLambdaProcessorErrors-${RANDOM_SUFFIX}" >> .env
    echo "DYNAMODB_THROTTLING_ALARM=DynamoDBThrottling-${RANDOM_SUFFIX}" >> .env
    
    success "CloudWatch alarms created successfully"
}

# Function to create data producer script
create_data_producer() {
    log "Creating data producer script for testing..."
    
    cat > data_producer.py << 'EOF'
import boto3
import json
import time
import random
from datetime import datetime

# Initialize Kinesis client
kinesis = boto3.client('kinesis')

def generate_sample_events():
    """Generate sample events for testing"""
    event_types = ['page_view', 'purchase', 'user_signup', 'click']
    device_types = ['desktop', 'mobile', 'tablet']
    
    events = []
    
    for i in range(10):
        event = {
            'eventType': random.choice(event_types),
            'userId': f'user_{random.randint(1000, 9999)}',
            'sessionId': f'session_{random.randint(100000, 999999)}',
            'deviceType': random.choice(device_types),
            'timestamp': datetime.now().isoformat(),
            'location': {
                'country': random.choice(['US', 'UK', 'DE', 'FR', 'JP']),
                'city': random.choice(['New York', 'London', 'Berlin', 'Paris', 'Tokyo'])
            }
        }
        
        # Add event-specific data
        if event['eventType'] == 'page_view':
            event.update({
                'pageUrl': f'/page/{random.randint(1, 100)}',
                'loadTime': random.randint(500, 3000),
                'sessionLength': random.randint(10, 1800),
                'pagesViewed': random.randint(1, 10)
            })
        elif event['eventType'] == 'purchase':
            event.update({
                'amount': round(random.uniform(10.99, 299.99), 2),
                'currency': 'USD',
                'itemsCount': random.randint(1, 5)
            })
        elif event['eventType'] == 'user_signup':
            event.update({
                'signupMethod': random.choice(['email', 'social', 'phone']),
                'campaignSource': random.choice(['google', 'facebook', 'direct', 'email'])
            })
        
        events.append(event)
    
    return events

def send_events_to_kinesis(stream_name, events):
    """Send events to Kinesis Data Stream"""
    for event in events:
        try:
            response = kinesis.put_record(
                StreamName=stream_name,
                Data=json.dumps(event),
                PartitionKey=event['userId']
            )
            print(f"Sent event {event['eventType']} - Shard: {response['ShardId']}")
            time.sleep(0.1)  # Small delay between events
            
        except Exception as e:
            print(f"Error sending event: {str(e)}")

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python data_producer.py <stream_name>")
        sys.exit(1)
    
    stream_name = sys.argv[1]
    
    print(f"Generating and sending sample events to stream: {stream_name}")
    
    # Send multiple batches of events
    for batch in range(3):
        print(f"\nSending batch {batch + 1}...")
        events = generate_sample_events()
        send_events_to_kinesis(stream_name, events)
        time.sleep(2)  # Wait between batches
    
    print("\nCompleted sending test events!")
EOF

    success "Data producer script created"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "=================================="
    echo "Kinesis Stream: $KINESIS_STREAM_NAME"
    echo "Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "DynamoDB Table: $DYNAMODB_TABLE_NAME"
    echo "IAM Role: $IAM_ROLE_NAME"
    echo "=================================="
    echo ""
    echo "Testing the pipeline:"
    echo "1. Run the data producer: python3 data_producer.py $KINESIS_STREAM_NAME"
    echo "2. Check Lambda logs: aws logs filter-log-events --log-group-name /aws/lambda/$LAMBDA_FUNCTION_NAME"
    echo "3. Verify DynamoDB data: aws dynamodb scan --table-name $DYNAMODB_TABLE_NAME --max-items 5"
    echo ""
    echo "Cleanup:"
    echo "Run './destroy.sh' to remove all created resources"
    echo ""
    success "Deployment completed successfully!"
}

# Function to handle cleanup on error
cleanup_on_error() {
    error "Deployment failed. Cleaning up partial resources..."
    if [ -f .env ]; then
        source .env
        
        # Clean up resources that may have been created
        aws lambda delete-event-source-mapping --uuid "$EVENT_SOURCE_MAPPING_UUID" 2>/dev/null || true
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME" 2>/dev/null || true
        aws kinesis delete-stream --stream-name "$KINESIS_STREAM_NAME" 2>/dev/null || true
        aws dynamodb delete-table --table-name "$DYNAMODB_TABLE_NAME" 2>/dev/null || true
        aws iam delete-role-policy --role-name "$IAM_ROLE_NAME" --policy-name KinesisLambdaProcessorPolicy 2>/dev/null || true
        aws iam delete-role --role-name "$IAM_ROLE_NAME" 2>/dev/null || true
        aws cloudwatch delete-alarms --alarm-names "KinesisLambdaProcessorErrors-${RANDOM_SUFFIX}" "DynamoDBThrottling-${RANDOM_SUFFIX}" 2>/dev/null || true
        
        rm -f .env
    fi
    
    # Clean up temporary files
    rm -f lambda-kinesis-policy.json lambda-trust-policy.json
    rm -f lambda-processor.zip
    rm -rf lambda-processor/
    
    error "Cleanup completed"
    exit 1
}

# Main deployment function
main() {
    log "Starting deployment of Serverless Real-Time Analytics Pipeline"
    
    # Set trap for cleanup on error
    trap cleanup_on_error ERR
    
    # Check if deployment already exists
    if [ -f .env ]; then
        warning "Previous deployment detected. Please run destroy.sh first or remove .env file."
        exit 1
    fi
    
    check_prerequisites
    setup_environment
    create_dynamodb_table
    create_iam_role
    create_kinesis_stream
    create_lambda_function
    create_event_source_mapping
    create_cloudwatch_alarms
    create_data_producer
    
    # Clean up temporary files
    rm -f lambda-kinesis-policy.json lambda-trust-policy.json
    rm -f lambda-processor.zip
    rm -rf lambda-processor/
    
    display_summary
}

# Run main function
main "$@"