#!/bin/bash

# =============================================================================
# FIFO Message Processing System Deployment Script
# Recipe: Processing Ordered Messages with SQS FIFO and Dead Letter Queues
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_FILE="deployment_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Global variables
DRY_RUN=false
FORCE_DEPLOY=false
SKIP_CLEANUP=false

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

cleanup_on_error() {
    error "Deployment failed. Cleaning up partially created resources..."
    if [[ "${SKIP_CLEANUP}" != "true" ]]; then
        ./destroy.sh --force --partial
    fi
    exit 1
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version | head -n1 | awk '{print $1}' | cut -d/ -f2)
    local required_version="2.0.0"
    if ! printf '%s\n%s\n' "${required_version}" "${aws_version}" | sort -V -C; then
        error "AWS CLI version ${aws_version} is too old. Minimum required: ${required_version}"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required tools
    local tools=("jq" "uuidgen" "zip")
    for tool in "${tools[@]}"; do
        if ! command -v ${tool} &> /dev/null; then
            error "${tool} is not installed. Please install it first."
            exit 1
        fi
    done
    
    info "✅ All prerequisites met"
}

check_existing_resources() {
    log "Checking for existing resources..."
    
    # Check if project already exists
    if aws sqs get-queue-url --queue-name "${MAIN_QUEUE_NAME}" &> /dev/null; then
        if [[ "${FORCE_DEPLOY}" != "true" ]]; then
            error "Resources with project name '${PROJECT_NAME}' already exist."
            error "Use --force to redeploy or choose a different project name."
            exit 1
        else
            warn "Existing resources found. Will attempt to update/recreate."
        fi
    fi
}

estimate_costs() {
    log "Estimating deployment costs..."
    
    cat << EOF
📊 ESTIMATED MONTHLY COSTS (US East 1):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• SQS FIFO Queue:           \$0.50 (1M requests)
• Lambda Functions:         \$1.00 (100K executions)
• DynamoDB Table:          \$2.50 (5 RCU/WCU)
• S3 Storage:              \$0.25 (10GB messages)
• CloudWatch:              \$1.00 (metrics/logs)
• SNS Topic:               \$0.50 (notifications)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TOTAL ESTIMATED:           ~\$5.75/month
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  Actual costs may vary based on usage patterns.
💡 Resources will be tagged for cost tracking.

EOF
}

setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        warn "No AWS region configured. Using default: ${AWS_REGION}"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            echo $(date +%s | tail -c 6))
    fi
    
    export PROJECT_NAME="fifo-processing-${RANDOM_SUFFIX}"
    export MAIN_QUEUE_NAME="${PROJECT_NAME}-main-queue.fifo"
    export DLQ_NAME="${PROJECT_NAME}-dlq.fifo"
    export ORDER_TABLE_NAME="${PROJECT_NAME}-orders"
    export ARCHIVE_BUCKET_NAME="${PROJECT_NAME}-message-archive"
    export SNS_TOPIC_NAME="${PROJECT_NAME}-alerts"
    
    # Save environment to file for cleanup script
    cat > .deployment_env << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export PROJECT_NAME="${PROJECT_NAME}"
export MAIN_QUEUE_NAME="${MAIN_QUEUE_NAME}"
export DLQ_NAME="${DLQ_NAME}"
export ORDER_TABLE_NAME="${ORDER_TABLE_NAME}"
export ARCHIVE_BUCKET_NAME="${ARCHIVE_BUCKET_NAME}"
export SNS_TOPIC_NAME="${SNS_TOPIC_NAME}"
EOF
    
    info "✅ Environment configured with project: ${PROJECT_NAME}"
    info "📝 Environment saved to .deployment_env"
}

# =============================================================================
# Resource Creation Functions
# =============================================================================

create_dynamodb_table() {
    log "Creating DynamoDB table for order state management..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "DRY RUN: Would create DynamoDB table ${ORDER_TABLE_NAME}"
        return 0
    fi
    
    aws dynamodb create-table \
        --table-name "${ORDER_TABLE_NAME}" \
        --attribute-definitions \
            AttributeName=OrderId,AttributeType=S \
            AttributeName=MessageGroupId,AttributeType=S \
            AttributeName=ProcessedAt,AttributeType=S \
        --key-schema \
            AttributeName=OrderId,KeyType=HASH \
        --global-secondary-indexes \
            IndexName=MessageGroup-ProcessedAt-index,KeySchema="[{AttributeName=MessageGroupId,KeyType=HASH},{AttributeName=ProcessedAt,KeyType=RANGE}]",Projection="{ProjectionType=ALL}",ProvisionedThroughput="{ReadCapacityUnits=5,WriteCapacityUnits=5}" \
        --provisioned-throughput \
            ReadCapacityUnits=10,WriteCapacityUnits=10 \
        --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
        --tags \
            Key=Project,Value="${PROJECT_NAME}" \
            Key=Recipe,Value="ordered-message-processing" \
            Key=Environment,Value="demo"
    
    # Wait for table to become active
    info "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name "${ORDER_TABLE_NAME}"
    
    info "✅ DynamoDB table created: ${ORDER_TABLE_NAME}"
}

create_s3_bucket() {
    log "Creating S3 bucket for message archiving..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "DRY RUN: Would create S3 bucket ${ARCHIVE_BUCKET_NAME}"
        return 0
    fi
    
    # Create bucket with proper region handling
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
        aws s3 mb "s3://${ARCHIVE_BUCKET_NAME}"
    else
        aws s3 mb "s3://${ARCHIVE_BUCKET_NAME}" --region "${AWS_REGION}"
    fi
    
    # Configure lifecycle policy for cost optimization
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "${ARCHIVE_BUCKET_NAME}" \
        --lifecycle-configuration '{
            "Rules": [{
                "ID": "ArchiveTransition",
                "Status": "Enabled",
                "Filter": {"Prefix": "poison-messages/"},
                "Transitions": [{
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                }, {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }]
            }]
        }'
    
    # Add bucket tagging
    aws s3api put-bucket-tagging \
        --bucket "${ARCHIVE_BUCKET_NAME}" \
        --tagging 'TagSet=[
            {Key=Project,Value='${PROJECT_NAME}'},
            {Key=Recipe,Value=ordered-message-processing},
            {Key=Environment,Value=demo}
        ]'
    
    info "✅ S3 bucket created: ${ARCHIVE_BUCKET_NAME}"
}

create_sns_topic() {
    log "Creating SNS topic for alerting..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "DRY RUN: Would create SNS topic ${SNS_TOPIC_NAME}"
        return 0
    fi
    
    aws sns create-topic --name "${SNS_TOPIC_NAME}" \
        --tags \
            Key=Project,Value="${PROJECT_NAME}" \
            Key=Recipe,Value="ordered-message-processing" \
            Key=Environment,Value="demo"
    
    export SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
        --query 'Attributes.TopicArn' --output text)
    
    info "✅ SNS topic created: ${SNS_TOPIC_ARN}"
}

create_sqs_queues() {
    log "Creating SQS FIFO queues..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "DRY RUN: Would create SQS queues ${MAIN_QUEUE_NAME} and ${DLQ_NAME}"
        return 0
    fi
    
    # Create dead letter queue first
    aws sqs create-queue \
        --queue-name "${DLQ_NAME}" \
        --attributes '{
            "FifoQueue": "true",
            "ContentBasedDeduplication": "true",
            "MessageRetentionPeriod": "1209600",
            "VisibilityTimeoutSeconds": "300"
        }' \
        --tags \
            Project="${PROJECT_NAME}",Recipe="ordered-message-processing",Environment="demo"
    
    export DLQ_URL=$(aws sqs get-queue-url \
        --queue-name "${DLQ_NAME}" \
        --query 'QueueUrl' --output text)
    
    export DLQ_ARN=$(aws sqs get-queue-attributes \
        --queue-url "${DLQ_URL}" \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)
    
    # Create main FIFO queue with DLQ configuration
    aws sqs create-queue \
        --queue-name "${MAIN_QUEUE_NAME}" \
        --attributes "{
            \"FifoQueue\": \"true\",
            \"ContentBasedDeduplication\": \"false\",
            \"DeduplicationScope\": \"messageGroup\",
            \"FifoThroughputLimit\": \"perMessageGroupId\",
            \"MessageRetentionPeriod\": \"1209600\",
            \"VisibilityTimeoutSeconds\": \"300\",
            \"RedrivePolicy\": \"{\\\"deadLetterTargetArn\\\":\\\"${DLQ_ARN}\\\",\\\"maxReceiveCount\\\":3}\"
        }" \
        --tags \
            Project="${PROJECT_NAME}",Recipe="ordered-message-processing",Environment="demo"
    
    export MAIN_QUEUE_URL=$(aws sqs get-queue-url \
        --queue-name "${MAIN_QUEUE_NAME}" \
        --query 'QueueUrl' --output text)
    
    export MAIN_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url "${MAIN_QUEUE_URL}" \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)
    
    info "✅ SQS queues created:"
    info "   Main Queue: ${MAIN_QUEUE_URL}"
    info "   DLQ: ${DLQ_URL}"
}

create_iam_roles() {
    log "Creating IAM roles for Lambda functions..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "DRY RUN: Would create IAM roles"
        return 0
    fi
    
    # Create trust policy document
    cat > trust_policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "lambda.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}
EOF
    
    # Create execution role for message processor
    aws iam create-role \
        --role-name "${PROJECT_NAME}-processor-role" \
        --assume-role-policy-document file://trust_policy.json \
        --tags \
            Key=Project,Value="${PROJECT_NAME}" \
            Key=Recipe,Value="ordered-message-processing" \
            Key=Environment,Value="demo"
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "${PROJECT_NAME}-processor-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Add SQS and DynamoDB permissions
    cat > processor_policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": [
            "sqs:ReceiveMessage",
            "sqs:DeleteMessage",
            "sqs:GetQueueAttributes",
            "sqs:SendMessage"
        ],
        "Resource": [
            "${MAIN_QUEUE_ARN}",
            "${DLQ_ARN}"
        ]
    }, {
        "Effect": "Allow",
        "Action": [
            "dynamodb:PutItem",
            "dynamodb:UpdateItem",
            "dynamodb:GetItem",
            "dynamodb:Query"
        ],
        "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${ORDER_TABLE_NAME}*"
    }, {
        "Effect": "Allow",
        "Action": [
            "cloudwatch:PutMetricData"
        ],
        "Resource": "*"
    }]
}
EOF
    
    aws iam put-role-policy \
        --role-name "${PROJECT_NAME}-processor-role" \
        --policy-name "MessageProcessingAccess" \
        --policy-document file://processor_policy.json
    
    # Create role for poison message handler
    aws iam create-role \
        --role-name "${PROJECT_NAME}-poison-handler-role" \
        --assume-role-policy-document file://trust_policy.json \
        --tags \
            Key=Project,Value="${PROJECT_NAME}" \
            Key=Recipe,Value="ordered-message-processing" \
            Key=Environment,Value="demo"
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "${PROJECT_NAME}-poison-handler-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Add permissions for poison message handling
    cat > poison_policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": [
            "sqs:ReceiveMessage",
            "sqs:DeleteMessage",
            "sqs:GetQueueAttributes",
            "sqs:SendMessage"
        ],
        "Resource": [
            "${DLQ_ARN}",
            "${MAIN_QUEUE_ARN}"
        ]
    }, {
        "Effect": "Allow",
        "Action": [
            "s3:PutObject",
            "s3:GetObject"
        ],
        "Resource": "arn:aws:s3:::${ARCHIVE_BUCKET_NAME}/*"
    }, {
        "Effect": "Allow",
        "Action": [
            "sns:Publish"
        ],
        "Resource": "${SNS_TOPIC_ARN}"
    }, {
        "Effect": "Allow",
        "Action": [
            "cloudwatch:PutMetricData"
        ],
        "Resource": "*"
    }]
}
EOF
    
    aws iam put-role-policy \
        --role-name "${PROJECT_NAME}-poison-handler-role" \
        --policy-name "PoisonMessageHandlingAccess" \
        --policy-document file://poison_policy.json
    
    # Wait for roles to be available
    sleep 10
    
    info "✅ IAM roles created"
}

create_lambda_functions() {
    log "Creating Lambda functions..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "DRY RUN: Would create Lambda functions"
        return 0
    fi
    
    # Create message processor function
    cat > message_processor.py << 'EOF'
import json
import boto3
import time
from datetime import datetime, timedelta
from decimal import Decimal
import hashlib
import random

dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')
sqs = boto3.client('sqs')

def lambda_handler(event, context):
    """
    Process messages from SQS FIFO queue with ordering guarantees
    """
    processed_count = 0
    failed_count = 0
    
    for record in event['Records']:
        try:
            # Extract message details
            message_body = json.loads(record['body'])
            message_group_id = record['attributes']['MessageGroupId']
            message_dedup_id = record['attributes']['MessageDeduplicationId']
            receipt_handle = record['receiptHandle']
            
            print(f"Processing message: {message_dedup_id} in group: {message_group_id}")
            
            # Simulate business logic processing
            result = process_order_message(message_body, message_group_id, message_dedup_id)
            
            if result['success']:
                processed_count += 1
                
                # Publish custom metrics
                publish_processing_metrics(message_group_id, 'SUCCESS', result['processing_time'])
                
            else:
                failed_count += 1
                # Don't delete message - let it go to DLQ after max retries
                publish_processing_metrics(message_group_id, 'FAILURE', result['processing_time'])
                
                # For demonstration: simulate different failure scenarios
                if should_simulate_failure():
                    raise Exception(f"Simulated processing failure for message {message_dedup_id}")
            
        except Exception as e:
            failed_count += 1
            print(f"Error processing message: {str(e)}")
            
            # Publish error metrics
            publish_processing_metrics(
                record['attributes'].get('MessageGroupId', 'unknown'), 
                'ERROR', 
                0
            )
            
            # Re-raise to trigger DLQ behavior
            raise
    
    # Publish batch metrics
    cloudwatch.put_metric_data(
        Namespace='FIFO/MessageProcessing',
        MetricData=[
            {
                'MetricName': 'ProcessedMessages',
                'Value': processed_count,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'Demo'}
                ]
            },
            {
                'MetricName': 'FailedMessages', 
                'Value': failed_count,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'Demo'}
                ]
            }
        ]
    )
    
    return {
        'statusCode': 200,
        'processedCount': processed_count,
        'failedCount': failed_count
    }

def process_order_message(message_body, message_group_id, message_dedup_id):
    """
    Process individual order message with idempotency
    """
    start_time = time.time()
    
    try:
        # Extract order information
        order_id = message_body.get('orderId')
        order_type = message_body.get('orderType')
        amount = message_body.get('amount')
        timestamp = message_body.get('timestamp')
        
        if not all([order_id, order_type, amount]):
            raise ValueError("Missing required order fields")
        
        table = dynamodb.Table(os.environ['ORDER_TABLE_NAME'])
        
        # Check for duplicate processing (idempotency)
        try:
            existing_item = table.get_item(
                Key={'OrderId': order_id}
            )
            
            if 'Item' in existing_item:
                if existing_item['Item'].get('MessageDeduplicationId') == message_dedup_id:
                    print(f"Message {message_dedup_id} already processed for order {order_id}")
                    return {
                        'success': True, 
                        'processing_time': time.time() - start_time,
                        'duplicate': True
                    }
        except Exception as e:
            print(f"Error checking for duplicates: {str(e)}")
        
        # Validate order amount (business rule)
        if Decimal(str(amount)) < 0:
            raise ValueError(f"Invalid order amount: {amount}")
        
        # Simulate complex business logic
        time.sleep(random.uniform(0.1, 0.5))  # Simulate processing time
        
        # Store order state with message tracking
        table.put_item(
            Item={
                'OrderId': order_id,
                'OrderType': order_type,
                'Amount': Decimal(str(amount)),
                'MessageGroupId': message_group_id,
                'MessageDeduplicationId': message_dedup_id,
                'Status': 'PROCESSED',
                'ProcessedAt': datetime.utcnow().isoformat(),
                'ProcessingTimeMs': int((time.time() - start_time) * 1000),
                'OriginalTimestamp': timestamp
            }
        )
        
        return {
            'success': True, 
            'processing_time': time.time() - start_time,
            'duplicate': False
        }
        
    except Exception as e:
        print(f"Error processing order {message_body.get('orderId', 'unknown')}: {str(e)}")
        return {
            'success': False, 
            'processing_time': time.time() - start_time,
            'error': str(e)
        }

def publish_processing_metrics(message_group_id, status, processing_time):
    """
    Publish detailed processing metrics to CloudWatch
    """
    try:
        cloudwatch.put_metric_data(
            Namespace='FIFO/MessageProcessing',
            MetricData=[
                {
                    'MetricName': 'ProcessingTime',
                    'Value': processing_time * 1000,  # Convert to milliseconds
                    'Unit': 'Milliseconds',
                    'Dimensions': [
                        {'Name': 'MessageGroup', 'Value': message_group_id},
                        {'Name': 'Status', 'Value': status}
                    ]
                },
                {
                    'MetricName': 'MessageStatus',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'MessageGroup', 'Value': message_group_id},
                        {'Name': 'Status', 'Value': status}
                    ]
                }
            ]
        )
    except Exception as e:
        print(f"Error publishing metrics: {str(e)}")

def should_simulate_failure():
    """
    Simulate occasional processing failures for testing
    """
    # 10% chance of failure for demonstration
    return random.random() < 0.1

import os
EOF
    
    # Package message processor
    zip message_processor.zip message_processor.py
    
    export PROCESSOR_ROLE_ARN=$(aws iam get-role \
        --role-name "${PROJECT_NAME}-processor-role" \
        --query 'Role.Arn' --output text)
    
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-message-processor" \
        --runtime python3.9 \
        --role "${PROCESSOR_ROLE_ARN}" \
        --handler message_processor.lambda_handler \
        --zip-file fileb://message_processor.zip \
        --environment "Variables={ORDER_TABLE_NAME=${ORDER_TABLE_NAME}}" \
        --timeout 300 \
        --reserved-concurrency 10 \
        --tags \
            Project="${PROJECT_NAME}",Recipe="ordered-message-processing",Environment="demo"
    
    # Create poison message handler
    cat > poison_message_handler.py << 'EOF'
import json
import boto3
import time
from datetime import datetime
import uuid

s3 = boto3.client('s3')
sns = boto3.client('sns')
sqs = boto3.client('sqs')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Handle poison messages from dead letter queue
    """
    processed_count = 0
    
    for record in event['Records']:
        try:
            # Extract message details
            message_body = json.loads(record['body'])
            message_group_id = record['attributes'].get('MessageGroupId', 'unknown')
            message_dedup_id = record['attributes'].get('MessageDeduplicationId', str(uuid.uuid4()))
            
            print(f"Processing poison message: {message_dedup_id} in group: {message_group_id}")
            
            # Analyze the poison message
            analysis_result = analyze_poison_message(message_body, record)
            
            # Archive the poison message to S3
            archive_key = archive_poison_message(message_body, record, analysis_result)
            
            # Send alert for critical poison messages
            if analysis_result['severity'] == 'CRITICAL':
                send_poison_message_alert(message_body, analysis_result, archive_key)
            
            # Attempt automated recovery if possible
            if analysis_result['recoverable']:
                recovery_result = attempt_message_recovery(message_body, message_group_id)
                if recovery_result['success']:
                    print(f"Successfully recovered message {message_dedup_id}")
            
            processed_count += 1
            
            # Publish metrics
            publish_poison_metrics(message_group_id, analysis_result)
            
        except Exception as e:
            print(f"Error handling poison message: {str(e)}")
            # Continue processing other messages
    
    return {
        'statusCode': 200,
        'processedCount': processed_count
    }

def analyze_poison_message(message_body, record):
    """
    Analyze poison message to determine cause and recovery options
    """
    analysis = {
        'severity': 'MEDIUM',
        'recoverable': False,
        'failure_reason': 'unknown',
        'analysis_timestamp': datetime.utcnow().isoformat()
    }
    
    try:
        # Check for common failure patterns
        
        # Missing required fields
        required_fields = ['orderId', 'orderType', 'amount']
        missing_fields = [field for field in required_fields if field not in message_body]
        
        if missing_fields:
            analysis['failure_reason'] = f"missing_fields: {', '.join(missing_fields)}"
            analysis['severity'] = 'HIGH'
            analysis['recoverable'] = False
        
        # Invalid data types or values
        elif 'amount' in message_body:
            try:
                amount = float(message_body['amount'])
                if amount < 0:
                    analysis['failure_reason'] = 'negative_amount'
                    analysis['severity'] = 'MEDIUM'
                    analysis['recoverable'] = True  # Could be corrected
            except (ValueError, TypeError):
                analysis['failure_reason'] = 'invalid_amount_format'
                analysis['severity'] = 'HIGH'
                analysis['recoverable'] = False
        
        # Check message attributes for processing history
        approximate_receive_count = int(record.get('attributes', {}).get('ApproximateReceiveCount', 0))
        if approximate_receive_count > 5:
            analysis['severity'] = 'CRITICAL'
            analysis['failure_reason'] = f'excessive_retries: {approximate_receive_count}'
        
        # Check for malformed JSON or encoding issues
        if not isinstance(message_body, dict):
            analysis['failure_reason'] = 'malformed_json'
            analysis['severity'] = 'HIGH'
            analysis['recoverable'] = False
        
    except Exception as e:
        analysis['failure_reason'] = f'analysis_error: {str(e)}'
        analysis['severity'] = 'CRITICAL'
    
    return analysis

def archive_poison_message(message_body, record, analysis):
    """
    Archive poison message to S3 for investigation
    """
    try:
        timestamp = datetime.utcnow()
        archive_key = f"poison-messages/{timestamp.strftime('%Y/%m/%d')}/{timestamp.strftime('%H%M%S')}-{uuid.uuid4()}.json"
        
        archive_data = {
            'originalMessage': message_body,
            'sqsRecord': {
                'messageId': record.get('messageId'),
                'receiptHandle': record.get('receiptHandle'),
                'messageAttributes': record.get('messageAttributes', {}),
                'attributes': record.get('attributes', {})
            },
            'analysis': analysis,
            'archivedAt': timestamp.isoformat()
        }
        
        s3.put_object(
            Bucket=os.environ['ARCHIVE_BUCKET_NAME'],
            Key=archive_key,
            Body=json.dumps(archive_data, indent=2),
            ContentType='application/json',
            Metadata={
                'severity': analysis['severity'],
                'failure-reason': analysis['failure_reason'][:256],  # Truncate if too long
                'message-group-id': record['attributes'].get('MessageGroupId', 'unknown')
            }
        )
        
        print(f"Archived poison message to: s3://{os.environ['ARCHIVE_BUCKET_NAME']}/{archive_key}")
        return archive_key
        
    except Exception as e:
        print(f"Error archiving poison message: {str(e)}")
        return None

def send_poison_message_alert(message_body, analysis, archive_key):
    """
    Send SNS alert for critical poison messages
    """
    try:
        alert_message = {
            'severity': analysis['severity'],
            'failure_reason': analysis['failure_reason'],
            'order_id': message_body.get('orderId', 'unknown'),
            'archive_location': f"s3://{os.environ['ARCHIVE_BUCKET_NAME']}/{archive_key}" if archive_key else 'failed_to_archive',
            'timestamp': datetime.utcnow().isoformat(),
            'requires_investigation': True
        }
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f"CRITICAL: Poison Message Detected - {analysis['failure_reason']}",
            Message=json.dumps(alert_message, indent=2)
        )
        
        print(f"Sent poison message alert for order {message_body.get('orderId', 'unknown')}")
        
    except Exception as e:
        print(f"Error sending poison message alert: {str(e)}")

def attempt_message_recovery(message_body, message_group_id):
    """
    Attempt automated recovery for recoverable poison messages
    """
    try:
        # Example recovery: fix negative amounts by taking absolute value
        if 'amount' in message_body and float(message_body['amount']) < 0:
            
            # Create corrected message
            corrected_message = message_body.copy()
            corrected_message['amount'] = abs(float(message_body['amount']))
            corrected_message['recovery_applied'] = 'negative_amount_correction'
            corrected_message['original_amount'] = message_body['amount']
            
            # Send corrected message back to main queue
            response = sqs.send_message(
                QueueUrl=os.environ['MAIN_QUEUE_URL'],
                MessageBody=json.dumps(corrected_message),
                MessageGroupId=message_group_id,
                MessageDeduplicationId=f"recovered-{uuid.uuid4()}"
            )
            
            return {
                'success': True,
                'recovery_type': 'negative_amount_correction',
                'new_message_id': response['MessageId']
            }
        
        return {'success': False, 'reason': 'no_recovery_strategy'}
        
    except Exception as e:
        print(f"Error attempting message recovery: {str(e)}")
        return {'success': False, 'reason': str(e)}

def publish_poison_metrics(message_group_id, analysis):
    """
    Publish poison message metrics to CloudWatch
    """
    try:
        cloudwatch.put_metric_data(
            Namespace='FIFO/PoisonMessages',
            MetricData=[
                {
                    'MetricName': 'PoisonMessageCount',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'MessageGroup', 'Value': message_group_id},
                        {'Name': 'Severity', 'Value': analysis['severity']},
                        {'Name': 'FailureReason', 'Value': analysis['failure_reason'][:255]}
                    ]
                },
                {
                    'MetricName': 'RecoverableMessages',
                    'Value': 1 if analysis['recoverable'] else 0,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'MessageGroup', 'Value': message_group_id}
                    ]
                }
            ]
        )
    except Exception as e:
        print(f"Error publishing poison metrics: {str(e)}")

import os
EOF
    
    # Package poison handler
    zip poison_message_handler.zip poison_message_handler.py
    
    export POISON_ROLE_ARN=$(aws iam get-role \
        --role-name "${PROJECT_NAME}-poison-handler-role" \
        --query 'Role.Arn' --output text)
    
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-poison-handler" \
        --runtime python3.9 \
        --role "${POISON_ROLE_ARN}" \
        --handler poison_message_handler.lambda_handler \
        --zip-file fileb://poison_message_handler.zip \
        --environment "Variables={ARCHIVE_BUCKET_NAME=${ARCHIVE_BUCKET_NAME},SNS_TOPIC_ARN=${SNS_TOPIC_ARN},MAIN_QUEUE_URL=${MAIN_QUEUE_URL}}" \
        --timeout 300 \
        --tags \
            Project="${PROJECT_NAME}",Recipe="ordered-message-processing",Environment="demo"
    
    # Create message replay function
    cat > message_replay.py << 'EOF'
import json
import boto3
from datetime import datetime, timedelta
import uuid

s3 = boto3.client('s3')
sqs = boto3.client('sqs')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Replay messages from S3 archive back to processing queue
    """
    try:
        # Parse replay request
        replay_request = event.get('replay_request', {})
        
        # Default parameters
        start_time = replay_request.get('start_time')
        end_time = replay_request.get('end_time', datetime.utcnow().isoformat())
        message_group_filter = replay_request.get('message_group_id')
        dry_run = replay_request.get('dry_run', True)
        
        if not start_time:
            # Default to last hour
            start_time = (datetime.utcnow() - timedelta(hours=1)).isoformat()
        
        print(f"Replaying messages from {start_time} to {end_time}")
        print(f"Message group filter: {message_group_filter}")
        print(f"Dry run mode: {dry_run}")
        
        # List archived messages in time range
        archived_messages = list_archived_messages(start_time, end_time, message_group_filter)
        
        replay_results = {
            'total_found': len(archived_messages),
            'replayed': 0,
            'skipped': 0,
            'errors': 0,
            'dry_run': dry_run
        }
        
        for message_info in archived_messages:
            try:
                if should_replay_message(message_info):
                    if not dry_run:
                        replay_result = replay_single_message(message_info)
                        if replay_result['success']:
                            replay_results['replayed'] += 1
                        else:
                            replay_results['errors'] += 1
                    else:
                        replay_results['replayed'] += 1
                        print(f"DRY RUN: Would replay message {message_info['key']}")
                else:
                    replay_results['skipped'] += 1
                    
            except Exception as e:
                print(f"Error processing archived message {message_info['key']}: {str(e)}")
                replay_results['errors'] += 1
        
        return {
            'statusCode': 200,
            'body': json.dumps(replay_results)
        }
        
    except Exception as e:
        print(f"Error in message replay: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def list_archived_messages(start_time, end_time, message_group_filter=None):
    """
    List archived messages within time range
    """
    archived_messages = []
    
    try:
        # Convert times to datetime objects for filtering
        start_dt = datetime.fromisoformat(start_time.replace('Z', '+00:00'))
        end_dt = datetime.fromisoformat(end_time.replace('Z', '+00:00'))
        
        # List objects in S3 bucket with poison-messages prefix
        paginator = s3.get_paginator('list_objects_v2')
        pages = paginator.paginate(
            Bucket=os.environ['ARCHIVE_BUCKET_NAME'],
            Prefix='poison-messages/'
        )
        
        for page in pages:
            for obj in page.get('Contents', []):
                # Extract timestamp from object key
                try:
                    # Parse key format: poison-messages/YYYY/MM/DD/HHMMSS-uuid.json
                    key_parts = obj['Key'].split('/')
                    if len(key_parts) >= 5:
                        date_part = '/'.join(key_parts[1:4])  # YYYY/MM/DD
                        filename = key_parts[4]
                        time_part = filename.split('-')[0]    # HHMMSS
                        
                        # Reconstruct timestamp
                        timestamp_str = f"{date_part.replace('/', '')}T{time_part[:2]}:{time_part[2:4]}:{time_part[4:6]}"
                        msg_dt = datetime.strptime(timestamp_str, '%Y%m%dT%H:%M:%S')
                        
                        if start_dt <= msg_dt <= end_dt:
                            message_info = {
                                'key': obj['Key'],
                                'timestamp': msg_dt,
                                'size': obj['Size'],
                                'metadata': obj.get('Metadata', {})
                            }
                            
                            # Apply message group filter if specified
                            if not message_group_filter or obj.get('Metadata', {}).get('message-group-id') == message_group_filter:
                                archived_messages.append(message_info)
                
                except Exception as e:
                    print(f"Error parsing object key {obj['Key']}: {str(e)}")
                    continue
        
        print(f"Found {len(archived_messages)} archived messages in time range")
        return archived_messages
        
    except Exception as e:
        print(f"Error listing archived messages: {str(e)}")
        return []

def should_replay_message(message_info):
    """
    Determine if a message should be replayed based on analysis
    """
    try:
        # Get message content from S3
        response = s3.get_object(
            Bucket=os.environ['ARCHIVE_BUCKET_NAME'],
            Key=message_info['key']
        )
        
        message_data = json.loads(response['Body'].read())
        analysis = message_data.get('analysis', {})
        
        # Only replay recoverable messages or those with medium/low severity
        if analysis.get('recoverable', False) or analysis.get('severity') in ['MEDIUM', 'LOW']:
            return True
        
        # Skip critical non-recoverable messages
        return False
        
    except Exception as e:
        print(f"Error analyzing message for replay: {str(e)}")
        return False

def replay_single_message(message_info):
    """
    Replay a single message back to the processing queue
    """
    try:
        # Get message content from S3
        response = s3.get_object(
            Bucket=os.environ['ARCHIVE_BUCKET_NAME'],
            Key=message_info['key']
        )
        
        message_data = json.loads(response['Body'].read())
        original_message = message_data['originalMessage']
        
        # Add replay metadata
        replay_message = original_message.copy()
        replay_message['replayed'] = True
        replay_message['replay_timestamp'] = datetime.utcnow().isoformat()
        replay_message['original_archive_key'] = message_info['key']
        
        # Determine message group ID
        message_group_id = message_info.get('metadata', {}).get('message-group-id', 'replay-group')
        
        # Send message back to main queue
        response = sqs.send_message(
            QueueUrl=os.environ['MAIN_QUEUE_URL'],
            MessageBody=json.dumps(replay_message),
            MessageGroupId=message_group_id,
            MessageDeduplicationId=f"replay-{uuid.uuid4()}"
        )
        
        print(f"Successfully replayed message {message_info['key']}: {response['MessageId']}")
        
        return {
            'success': True,
            'message_id': response['MessageId']
        }
        
    except Exception as e:
        print(f"Error replaying message {message_info['key']}: {str(e)}")
        return {
            'success': False,
            'error': str(e)
        }

import os
EOF
    
    # Package replay function
    zip message_replay.zip message_replay.py
    
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-message-replay" \
        --runtime python3.9 \
        --role "${POISON_ROLE_ARN}" \
        --handler message_replay.lambda_handler \
        --zip-file fileb://message_replay.zip \
        --environment "Variables={ARCHIVE_BUCKET_NAME=${ARCHIVE_BUCKET_NAME},MAIN_QUEUE_URL=${MAIN_QUEUE_URL}}" \
        --timeout 300 \
        --tags \
            Project="${PROJECT_NAME}",Recipe="ordered-message-processing",Environment="demo"
    
    info "✅ Lambda functions created"
}

configure_event_source_mappings() {
    log "Configuring event source mappings..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "DRY RUN: Would configure event source mappings"
        return 0
    fi
    
    # Configure event source mapping for main queue
    aws lambda create-event-source-mapping \
        --function-name "${PROJECT_NAME}-message-processor" \
        --event-source-arn "${MAIN_QUEUE_ARN}" \
        --batch-size 1 \
        --maximum-batching-window-in-seconds 5
    
    # Configure event source mapping for dead letter queue
    aws lambda create-event-source-mapping \
        --function-name "${PROJECT_NAME}-poison-handler" \
        --event-source-arn "${DLQ_ARN}" \
        --batch-size 5 \
        --maximum-batching-window-in-seconds 10
    
    info "✅ Event source mappings configured"
}

create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms for monitoring..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "DRY RUN: Would create CloudWatch alarms"
        return 0
    fi
    
    # Create alarm for high message processing failure rate
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-high-failure-rate" \
        --alarm-description "High message processing failure rate" \
        --metric-name FailedMessages \
        --namespace FIFO/MessageProcessing \
        --statistic Sum \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --tags \
            Key=Project,Value="${PROJECT_NAME}" \
            Key=Recipe,Value="ordered-message-processing" \
            Key=Environment,Value="demo"
    
    # Create alarm for poison messages
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-poison-messages-detected" \
        --alarm-description "Poison messages detected in DLQ" \
        --metric-name PoisonMessageCount \
        --namespace FIFO/PoisonMessages \
        --statistic Sum \
        --period 300 \
        --evaluation-periods 1 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --treat-missing-data notBreaching \
        --tags \
            Key=Project,Value="${PROJECT_NAME}" \
            Key=Recipe,Value="ordered-message-processing" \
            Key=Environment,Value="demo"
    
    # Create alarm for processing latency
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-high-processing-latency" \
        --alarm-description "High message processing latency" \
        --metric-name ProcessingTime \
        --namespace FIFO/MessageProcessing \
        --statistic Average \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 5000 \
        --comparison-operator GreaterThanThreshold \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --tags \
            Key=Project,Value="${PROJECT_NAME}" \
            Key=Recipe,Value="ordered-message-processing" \
            Key=Environment,Value="demo"
    
    info "✅ CloudWatch alarms created"
}

cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    local files=(
        "trust_policy.json"
        "processor_policy.json"
        "poison_policy.json"
        "message_processor.py"
        "poison_message_handler.py"
        "message_replay.py"
        "message_processor.zip"
        "poison_message_handler.zip"
        "message_replay.zip"
    )
    
    for file in "${files[@]}"; do
        [[ -f "${file}" ]] && rm -f "${file}"
    done
    
    info "✅ Temporary files cleaned up"
}

# =============================================================================
# Main Functions
# =============================================================================

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy FIFO Message Processing System with SQS FIFO and Dead Letter Queues

OPTIONS:
    --dry-run           Show what would be deployed without making changes
    --force             Force deployment even if resources exist
    --skip-cleanup      Skip automatic cleanup on deployment failure
    --project-name      Specify custom project name (default: auto-generated)
    --region           Specify AWS region (default: from AWS CLI config)
    --help             Show this help message

EXAMPLES:
    $0                          # Deploy with default settings
    $0 --dry-run               # Show what would be deployed
    $0 --force                 # Force redeploy existing resources
    $0 --project-name my-fifo  # Use custom project name

EOF
}

validate_deployment() {
    log "Validating deployment..."
    
    local validation_errors=0
    
    # Check if all resources were created
    local resources=(
        "DynamoDB table:aws dynamodb describe-table --table-name ${ORDER_TABLE_NAME}"
        "S3 bucket:aws s3 ls s3://${ARCHIVE_BUCKET_NAME}"
        "SNS topic:aws sns get-topic-attributes --topic-arn ${SNS_TOPIC_ARN}"
        "Main queue:aws sqs get-queue-url --queue-name ${MAIN_QUEUE_NAME}"
        "DLQ:aws sqs get-queue-url --queue-name ${DLQ_NAME}"
    )
    
    for resource in "${resources[@]}"; do
        local name=$(echo "${resource}" | cut -d: -f1)
        local command=$(echo "${resource}" | cut -d: -f2-)
        
        if ! eval "${command}" &> /dev/null; then
            error "❌ ${name} validation failed"
            ((validation_errors++))
        else
            info "✅ ${name} validated"
        fi
    done
    
    # Check Lambda functions
    local functions=(
        "${PROJECT_NAME}-message-processor"
        "${PROJECT_NAME}-poison-handler"
        "${PROJECT_NAME}-message-replay"
    )
    
    for function in "${functions[@]}"; do
        if ! aws lambda get-function --function-name "${function}" &> /dev/null; then
            error "❌ Lambda function ${function} validation failed"
            ((validation_errors++))
        else
            info "✅ Lambda function ${function} validated"
        fi
    done
    
    if [[ ${validation_errors} -eq 0 ]]; then
        log "🎉 All resources validated successfully!"
        return 0
    else
        error "❌ ${validation_errors} validation errors found"
        return 1
    fi
}

show_deployment_summary() {
    log "📋 DEPLOYMENT SUMMARY"
    cat << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Project Name:          ${PROJECT_NAME}
AWS Region:            ${AWS_REGION}
AWS Account:           ${AWS_ACCOUNT_ID}

📦 RESOURCES CREATED:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• DynamoDB Table:      ${ORDER_TABLE_NAME}
• S3 Bucket:           ${ARCHIVE_BUCKET_NAME}
• SNS Topic:           ${SNS_TOPIC_NAME}
• Main SQS Queue:      ${MAIN_QUEUE_NAME}
• Dead Letter Queue:   ${DLQ_NAME}
• Lambda Functions:    3 functions created
• IAM Roles:           2 roles created
• CloudWatch Alarms:   3 alarms created

🔗 IMPORTANT URLS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Main Queue URL:        ${MAIN_QUEUE_URL}
DLQ URL:              ${DLQ_URL}
S3 Bucket:            s3://${ARCHIVE_BUCKET_NAME}
SNS Topic ARN:        ${SNS_TOPIC_ARN}

📊 NEXT STEPS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Test the system by sending messages to the main queue
2. Monitor CloudWatch metrics in the FIFO/MessageProcessing namespace
3. Check poison message handling by sending invalid messages
4. Review CloudWatch logs for Lambda functions
5. Test message replay functionality if needed

💡 TESTING COMMANDS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Send test message:
aws sqs send-message \\
    --queue-url ${MAIN_QUEUE_URL} \\
    --message-body '{"orderId":"test-001","orderType":"BUY","amount":100,"timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \\
    --message-group-id "test-group" \\
    --message-deduplication-id \$(uuidgen)

# Check processed orders:
aws dynamodb scan --table-name ${ORDER_TABLE_NAME} --max-items 5

🧹 CLEANUP:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Run: ./destroy.sh

📋 ENVIRONMENT FILE:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Environment variables saved to: .deployment_env
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

main() {
    # Set error handler
    trap cleanup_on_error ERR
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_DEPLOY=true
                shift
                ;;
            --skip-cleanup)
                SKIP_CLEANUP=true
                shift
                ;;
            --project-name)
                PROJECT_NAME_OVERRIDE="$2"
                shift 2
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Header
    log "🚀 Starting FIFO Message Processing System Deployment"
    log "📅 $(date)"
    log "📍 Log file: ${LOG_FILE}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        warn "🔍 DRY RUN MODE - No resources will be created"
    fi
    
    # Main deployment flow
    check_prerequisites
    setup_environment
    
    # Override project name if provided
    if [[ -n "${PROJECT_NAME_OVERRIDE:-}" ]]; then
        export PROJECT_NAME="${PROJECT_NAME_OVERRIDE}"
        log "Using custom project name: ${PROJECT_NAME}"
    fi
    
    check_existing_resources
    estimate_costs
    
    # Deployment steps
    log "🏗️  Starting resource deployment..."
    
    create_dynamodb_table
    create_s3_bucket
    create_sns_topic
    create_sqs_queues
    create_iam_roles
    create_lambda_functions
    configure_event_source_mappings
    create_cloudwatch_alarms
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        cleanup_temp_files
        validate_deployment
        show_deployment_summary
        
        log "🎉 Deployment completed successfully!"
        log "📋 Review the summary above for next steps"
    else
        log "🔍 Dry run completed - no resources were created"
    fi
}

# Run main function
main "$@"