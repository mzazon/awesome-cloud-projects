#!/bin/bash

# Deploy script for Real-time Database Change Streams with DynamoDB Streams
# This script implements the complete infrastructure from the recipe with proper error handling

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set up IAM roles."
        exit 1
    fi
    
    # Check required tools
    for tool in jq zip; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is not installed. Please install $tool."
            exit 1
        fi
    done
    
    success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        warning "No region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    export TABLE_NAME="UserActivities-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="stream-processor-${RANDOM_SUFFIX}"
    export ROLE_NAME="dynamodb-stream-role-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="activity-notifications-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="activity-audit-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
TABLE_NAME=${TABLE_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
ROLE_NAME=${ROLE_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
EOF
    
    log "Environment variables configured:"
    log "  AWS Region: ${AWS_REGION}"
    log "  AWS Account: ${AWS_ACCOUNT_ID}"
    log "  Table Name: ${TABLE_NAME}"
    log "  Function Name: ${FUNCTION_NAME}"
    
    success "Environment setup complete"
}

# Function to create foundational resources
create_foundational_resources() {
    log "Creating foundational resources..."
    
    # Create S3 bucket for audit logs
    if aws s3 ls "s3://${S3_BUCKET_NAME}" 2>/dev/null; then
        warning "S3 bucket ${S3_BUCKET_NAME} already exists, skipping creation"
    else
        if [[ "${AWS_REGION}" == "us-east-1" ]]; then
            aws s3 mb "s3://${S3_BUCKET_NAME}"
        else
            aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}"
        fi
        success "S3 bucket created: ${S3_BUCKET_NAME}"
    fi
    
    # Create SNS topic for notifications
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --query TopicArn --output text)
    export SNS_TOPIC_ARN
    
    # Update .env file with SNS topic ARN
    echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> .env
    
    success "Foundational resources created"
}

# Function to create DynamoDB table with streams
create_dynamodb_table() {
    log "Creating DynamoDB table with streams..."
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name "${TABLE_NAME}" &>/dev/null; then
        warning "DynamoDB table ${TABLE_NAME} already exists, skipping creation"
        STREAM_ARN=$(aws dynamodb describe-table \
            --table-name "${TABLE_NAME}" \
            --query Table.LatestStreamArn --output text)
    else
        # Create table with NEW_AND_OLD_IMAGES stream view
        aws dynamodb create-table \
            --table-name "${TABLE_NAME}" \
            --attribute-definitions \
                AttributeName=UserId,AttributeType=S \
                AttributeName=ActivityId,AttributeType=S \
            --key-schema \
                AttributeName=UserId,KeyType=HASH \
                AttributeName=ActivityId,KeyType=RANGE \
            --provisioned-throughput \
                ReadCapacityUnits=5,WriteCapacityUnits=5 \
            --stream-specification \
                StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
            --tags Key=Environment,Value=Production \
                 Key=Project,Value=StreamProcessing
        
        # Wait for table to be active
        log "Waiting for DynamoDB table to become active..."
        aws dynamodb wait table-exists --table-name "${TABLE_NAME}"
        
        # Get stream ARN
        STREAM_ARN=$(aws dynamodb describe-table \
            --table-name "${TABLE_NAME}" \
            --query Table.LatestStreamArn --output text)
        
        success "DynamoDB table created with stream: ${STREAM_ARN}"
    fi
    
    export STREAM_ARN
    echo "STREAM_ARN=${STREAM_ARN}" >> .env
}

# Function to create IAM role and policies
create_iam_resources() {
    log "Creating IAM role and policies..."
    
    # Create trust policy for Lambda
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
    
    # Check if role already exists
    if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
        warning "IAM role ${ROLE_NAME} already exists, skipping creation"
    else
        # Create IAM role
        aws iam create-role \
            --role-name "${ROLE_NAME}" \
            --assume-role-policy-document file://lambda-trust-policy.json
        
        # Attach AWS managed policy for DynamoDB stream execution
        aws iam attach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole
        
        success "IAM role created: ${ROLE_NAME}"
    fi
    
    # Create custom policy for SNS and S3 access
    cat > custom-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "${SNS_TOPIC_ARN}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl"
            ],
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*"
        }
    ]
}
EOF
    
    # Check if custom policy already exists
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-custom-policy" &>/dev/null; then
        warning "Custom policy ${ROLE_NAME}-custom-policy already exists, skipping creation"
    else
        # Create and attach custom policy
        aws iam create-policy \
            --policy-name "${ROLE_NAME}-custom-policy" \
            --policy-document file://custom-policy.json
        
        aws iam attach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-custom-policy"
        
        success "Custom policy attached to role"
    fi
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function..."
    
    # Create Lambda function code
    cat > stream-processor.py << 'EOF'
import json
import boto3
import logging
from datetime import datetime
from decimal import Decimal

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
sns = boto3.client('sns')
s3 = boto3.client('s3')

# Environment variables
import os
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
S3_BUCKET_NAME = os.environ['S3_BUCKET_NAME']

def decimal_default(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def lambda_handler(event, context):
    logger.info(f"Processing {len(event['Records'])} stream records")
    
    for record in event['Records']:
        try:
            # Process each stream record
            process_stream_record(record)
        except Exception as e:
            logger.error(f"Error processing record: {str(e)}")
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Successfully processed {len(event["Records"])} records')
    }

def process_stream_record(record):
    event_name = record['eventName']
    user_id = record['dynamodb']['Keys']['UserId']['S']
    activity_id = record['dynamodb']['Keys']['ActivityId']['S']
    
    logger.info(f"Processing {event_name} event for user {user_id}, activity {activity_id}")
    
    # Create audit record
    audit_record = {
        'timestamp': datetime.utcnow().isoformat(),
        'eventName': event_name,
        'userId': user_id,
        'activityId': activity_id,
        'awsRegion': record['awsRegion'],
        'eventSource': record['eventSource']
    }
    
    # Add old and new images if available
    if 'OldImage' in record['dynamodb']:
        audit_record['oldImage'] = record['dynamodb']['OldImage']
    if 'NewImage' in record['dynamodb']:
        audit_record['newImage'] = record['dynamodb']['NewImage']
    
    # Store audit record in S3
    store_audit_record(audit_record)
    
    # Send notification based on event type
    if event_name == 'INSERT':
        send_notification(f"New activity created for user {user_id}", audit_record)
    elif event_name == 'MODIFY':
        send_notification(f"Activity updated for user {user_id}", audit_record)
    elif event_name == 'REMOVE':
        send_notification(f"Activity deleted for user {user_id}", audit_record)

def store_audit_record(audit_record):
    try:
        # Generate S3 key with timestamp and user ID
        timestamp = datetime.utcnow().strftime('%Y/%m/%d/%H')
        s3_key = f"audit-logs/{timestamp}/{audit_record['userId']}-{audit_record['activityId']}.json"
        
        # Store in S3
        s3.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=s3_key,
            Body=json.dumps(audit_record, default=decimal_default),
            ContentType='application/json'
        )
        
        logger.info(f"Audit record stored: s3://{S3_BUCKET_NAME}/{s3_key}")
    except Exception as e:
        logger.error(f"Failed to store audit record: {str(e)}")
        raise e

def send_notification(message, audit_record):
    try:
        # Send SNS notification
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=json.dumps({
                'message': message,
                'details': audit_record
            }, default=decimal_default),
            Subject=f"DynamoDB Activity: {audit_record['eventName']}"
        )
        
        logger.info(f"Notification sent: {message}")
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")
        raise e
EOF
    
    # Create deployment package
    zip lambda-function.zip stream-processor.py
    
    # Wait for IAM role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
    
    # Get role ARN
    ROLE_ARN=$(aws iam get-role \
        --role-name "${ROLE_NAME}" \
        --query Role.Arn --output text)
    
    # Check if Lambda function already exists
    if aws lambda get-function --function-name "${FUNCTION_NAME}" &>/dev/null; then
        warning "Lambda function ${FUNCTION_NAME} already exists, updating code..."
        aws lambda update-function-code \
            --function-name "${FUNCTION_NAME}" \
            --zip-file fileb://lambda-function.zip
        
        aws lambda update-function-configuration \
            --function-name "${FUNCTION_NAME}" \
            --environment Variables="{ \
                SNS_TOPIC_ARN=${SNS_TOPIC_ARN}, \
                S3_BUCKET_NAME=${S3_BUCKET_NAME} \
            }"
    else
        # Create Lambda function
        aws lambda create-function \
            --function-name "${FUNCTION_NAME}" \
            --runtime python3.9 \
            --role "${ROLE_ARN}" \
            --handler stream-processor.lambda_handler \
            --zip-file fileb://lambda-function.zip \
            --environment Variables="{ \
                SNS_TOPIC_ARN=${SNS_TOPIC_ARN}, \
                S3_BUCKET_NAME=${S3_BUCKET_NAME} \
            }" \
            --timeout 60 \
            --memory-size 256 \
            --description "Processes DynamoDB stream records"
        
        success "Lambda function created: ${FUNCTION_NAME}"
    fi
    
    # Wait for function to be active
    aws lambda wait function-active --function-name "${FUNCTION_NAME}"
}

# Function to create event source mapping
create_event_source_mapping() {
    log "Creating DynamoDB stream event source mapping..."
    
    # Check if event source mapping already exists
    EXISTING_MAPPING=$(aws lambda list-event-source-mappings \
        --function-name "${FUNCTION_NAME}" \
        --query 'EventSourceMappings[?EventSourceArn==`'${STREAM_ARN}'`].UUID' \
        --output text)
    
    if [[ -n "${EXISTING_MAPPING}" && "${EXISTING_MAPPING}" != "None" ]]; then
        warning "Event source mapping already exists: ${EXISTING_MAPPING}"
        MAPPING_UUID="${EXISTING_MAPPING}"
    else
        # Create event source mapping
        aws lambda create-event-source-mapping \
            --event-source-arn "${STREAM_ARN}" \
            --function-name "${FUNCTION_NAME}" \
            --starting-position LATEST \
            --batch-size 10 \
            --maximum-batching-window-in-seconds 5 \
            --maximum-record-age-in-seconds 3600 \
            --bisect-batch-on-function-error \
            --maximum-retry-attempts 3 \
            --parallelization-factor 2
        
        # Get event source mapping UUID
        MAPPING_UUID=$(aws lambda list-event-source-mappings \
            --function-name "${FUNCTION_NAME}" \
            --query EventSourceMappings[0].UUID --output text)
        
        success "Event source mapping created: ${MAPPING_UUID}"
    fi
    
    export MAPPING_UUID
    echo "MAPPING_UUID=${MAPPING_UUID}" >> .env
}

# Function to create dead letter queue
create_dead_letter_queue() {
    log "Creating dead letter queue..."
    
    # Check if DLQ already exists
    DLQ_URL=$(aws sqs get-queue-url --queue-name "${FUNCTION_NAME}-dlq" --output text 2>/dev/null || echo "")
    
    if [[ -n "${DLQ_URL}" ]]; then
        warning "Dead letter queue already exists: ${DLQ_URL}"
    else
        # Create SQS dead letter queue
        DLQ_URL=$(aws sqs create-queue \
            --queue-name "${FUNCTION_NAME}-dlq" \
            --attributes MessageRetentionPeriod=1209600 \
            --query QueueUrl --output text)
        
        success "Dead letter queue created: ${DLQ_URL}"
    fi
    
    # Get DLQ ARN
    DLQ_ARN=$(aws sqs get-queue-attributes \
        --queue-url "${DLQ_URL}" \
        --attribute-names QueueArn \
        --query Attributes.QueueArn --output text)
    
    # Update Lambda function with DLQ configuration
    aws lambda update-function-configuration \
        --function-name "${FUNCTION_NAME}" \
        --dead-letter-config TargetArn="${DLQ_ARN}"
    
    export DLQ_URL DLQ_ARN
    echo "DLQ_URL=${DLQ_URL}" >> .env
    echo "DLQ_ARN=${DLQ_ARN}" >> .env
    
    success "Dead letter queue configured: ${DLQ_ARN}"
}

# Function to configure CloudWatch monitoring
configure_cloudwatch() {
    log "Configuring CloudWatch monitoring..."
    
    # Create CloudWatch alarm for Lambda errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "${FUNCTION_NAME}-errors" \
        --alarm-description "Lambda function errors" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=FunctionName,Value="${FUNCTION_NAME}"
    
    # Create alarm for DLQ message count
    aws cloudwatch put-metric-alarm \
        --alarm-name "${FUNCTION_NAME}-dlq-messages" \
        --alarm-description "Dead letter queue messages" \
        --metric-name ApproximateNumberOfVisibleMessages \
        --namespace AWS/SQS \
        --statistic Average \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=QueueName,Value="${FUNCTION_NAME}-dlq"
    
    success "CloudWatch alarms configured"
}

# Function to create test data
create_test_data() {
    log "Creating test data to validate stream processing..."
    
    # Insert test data to trigger stream processing
    aws dynamodb put-item \
        --table-name "${TABLE_NAME}" \
        --item '{
            "UserId": {"S": "user123"},
            "ActivityId": {"S": "activity001"},
            "ActivityType": {"S": "LOGIN"},
            "Timestamp": {"N": "'$(date +%s)'"},
            "IPAddress": {"S": "192.168.1.100"},
            "UserAgent": {"S": "Mozilla/5.0"}
        }'
    
    # Update the item to trigger MODIFY event
    aws dynamodb update-item \
        --table-name "${TABLE_NAME}" \
        --key '{
            "UserId": {"S": "user123"},
            "ActivityId": {"S": "activity001"}
        }' \
        --update-expression "SET ActivityType = :type, #ts = :ts" \
        --expression-attribute-names '{"#ts": "Timestamp"}' \
        --expression-attribute-values '{
            ":type": {"S": "LOGOUT"},
            ":ts": {"N": "'$(date +%s)'"}
        }'
    
    # Insert another item
    aws dynamodb put-item \
        --table-name "${TABLE_NAME}" \
        --item '{
            "UserId": {"S": "user456"},
            "ActivityId": {"S": "activity002"},
            "ActivityType": {"S": "PURCHASE"},
            "Timestamp": {"N": "'$(date +%s)'"},
            "Amount": {"N": "99.99"},
            "Currency": {"S": "USD"}
        }'
    
    success "Test data created. Stream processing should trigger automatically."
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f lambda-trust-policy.json custom-policy.json \
          stream-processor.py lambda-function.zip
    
    success "Temporary files cleaned up"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "DynamoDB Table: ${TABLE_NAME}"
    echo "Lambda Function: ${FUNCTION_NAME}"
    echo "SNS Topic: ${SNS_TOPIC_ARN}"
    echo "S3 Bucket: ${S3_BUCKET_NAME}"
    echo "Dead Letter Queue: ${DLQ_ARN}"
    echo "Event Source Mapping: ${MAPPING_UUID}"
    echo ""
    echo "Environment variables saved to .env file"
    echo ""
    echo "To subscribe to SNS notifications:"
    echo "aws sns subscribe --topic-arn ${SNS_TOPIC_ARN} --protocol email --notification-endpoint your-email@example.com"
    echo ""
    echo "To monitor Lambda function logs:"
    echo "aws logs tail /aws/lambda/${FUNCTION_NAME} --follow"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main execution
main() {
    log "Starting DynamoDB Streams deployment..."
    
    check_prerequisites
    setup_environment
    create_foundational_resources
    create_dynamodb_table
    create_iam_resources
    create_lambda_function
    create_event_source_mapping
    create_dead_letter_queue
    configure_cloudwatch
    create_test_data
    cleanup_temp_files
    
    success "Deployment completed successfully!"
    display_summary
}

# Run main function
main "$@"