#!/bin/bash

# ==============================================================================
# AWS Real-Time Analytics with Kinesis Data Streams - Deployment Script
# ==============================================================================
# This script deploys a complete real-time analytics pipeline using:
# - Amazon Kinesis Data Streams for streaming data ingestion
# - AWS Lambda for real-time stream processing
# - Amazon S3 for analytics data storage
# - Amazon CloudWatch for monitoring and alerting
# ==============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Cleanup function for rollback on failure
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code $exit_code. Starting cleanup..."
    
    # Source the destroy script for cleanup
    if [[ -f "./destroy.sh" ]]; then
        log_info "Running cleanup using destroy script..."
        bash ./destroy.sh --force 2>/dev/null || true
    fi
    
    exit $exit_code
}

# Set up error handling
trap cleanup_on_error ERR

# ==============================================================================
# PREREQUISITES CHECK
# ==============================================================================

log_info "Checking prerequisites..."

# Check AWS CLI
if ! command_exists aws; then
    log_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check AWS CLI version
AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
log_info "AWS CLI version: $AWS_CLI_VERSION"

# Check AWS credentials
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log_error "AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

# Check Python
if ! command_exists python3; then
    log_error "Python 3 is not installed. Please install it first."
    exit 1
fi

# Check zip command
if ! command_exists zip; then
    log_error "zip command is not available. Please install it first."
    exit 1
fi

log_success "Prerequisites check completed"

# ==============================================================================
# ENVIRONMENT SETUP
# ==============================================================================

log_info "Setting up environment variables..."

# Get AWS region and account ID
export AWS_REGION=$(aws configure get region)
if [[ -z "$AWS_REGION" ]]; then
    export AWS_REGION="us-east-1"
    log_warning "No default region found, using us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))

export STREAM_NAME="analytics-stream-${RANDOM_SUFFIX}"
export LAMBDA_FUNCTION_NAME="stream-processor-${RANDOM_SUFFIX}"
export S3_BUCKET_NAME="kinesis-analytics-${RANDOM_SUFFIX}"
export IAM_ROLE_NAME="KinesisAnalyticsRole-${RANDOM_SUFFIX}"

log_info "AWS Region: $AWS_REGION"
log_info "AWS Account ID: $AWS_ACCOUNT_ID"
log_info "Stream Name: $STREAM_NAME"
log_info "Lambda Function: $LAMBDA_FUNCTION_NAME"
log_info "S3 Bucket: $S3_BUCKET_NAME"
log_info "IAM Role: $IAM_ROLE_NAME"

# Save environment variables for cleanup script
cat > .env_vars << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export STREAM_NAME="$STREAM_NAME"
export LAMBDA_FUNCTION_NAME="$LAMBDA_FUNCTION_NAME"
export S3_BUCKET_NAME="$S3_BUCKET_NAME"
export IAM_ROLE_NAME="$IAM_ROLE_NAME"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF

log_success "Environment setup completed"

# ==============================================================================
# S3 BUCKET CREATION
# ==============================================================================

log_info "Creating S3 bucket for analytics data storage..."

# Check if bucket already exists
if aws s3 ls "s3://${S3_BUCKET_NAME}" >/dev/null 2>&1; then
    log_warning "S3 bucket ${S3_BUCKET_NAME} already exists"
else
    # Create bucket with appropriate region configuration
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://${S3_BUCKET_NAME}"
    else
        aws s3 mb "s3://${S3_BUCKET_NAME}" --region "$AWS_REGION"
    fi
    
    # Enable versioning for data protection
    aws s3api put-bucket-versioning \
        --bucket "$S3_BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Apply lifecycle policy for cost optimization
    cat > lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "AnalyticsDataLifecycle",
            "Status": "Enabled",
            "Filter": {"Prefix": "analytics-data/"},
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }
            ]
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$S3_BUCKET_NAME" \
        --lifecycle-configuration file://lifecycle-policy.json
    
    log_success "S3 bucket created and configured: $S3_BUCKET_NAME"
fi

# ==============================================================================
# IAM ROLE CREATION
# ==============================================================================

log_info "Creating IAM role for Lambda stream processing..."

# Create trust policy for Lambda
cat > lambda-trust-policy.json << EOF
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
if aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
    log_warning "IAM role $IAM_ROLE_NAME already exists"
else
    # Create IAM role
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document file://lambda-trust-policy.json \
        --description "IAM role for Kinesis analytics Lambda function"
    
    log_success "IAM role created: $IAM_ROLE_NAME"
fi

# Create permissions policy for stream processing
cat > stream-processor-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kinesis:DescribeStream",
                "kinesis:GetShardIterator",
                "kinesis:GetRecords",
                "kinesis:ListStreams"
            ],
            "Resource": "arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${STREAM_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:*"
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

# Attach policies to role
aws iam attach-role-policy \
    --role-name "$IAM_ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam put-role-policy \
    --role-name "$IAM_ROLE_NAME" \
    --policy-name StreamProcessorPolicy \
    --policy-document file://stream-processor-policy.json

# Get role ARN
export LAMBDA_ROLE_ARN=$(aws iam get-role \
    --role-name "$IAM_ROLE_NAME" \
    --query 'Role.Arn' --output text)

log_success "IAM role configured with appropriate permissions"

# ==============================================================================
# KINESIS DATA STREAM CREATION
# ==============================================================================

log_info "Creating Kinesis Data Stream..."

# Check if stream already exists
if aws kinesis describe-stream --stream-name "$STREAM_NAME" >/dev/null 2>&1; then
    log_warning "Kinesis stream $STREAM_NAME already exists"
else
    # Create stream with 3 shards for parallel processing
    aws kinesis create-stream \
        --stream-name "$STREAM_NAME" \
        --shard-count 3
    
    log_info "Waiting for stream to become active..."
    aws kinesis wait stream-exists --stream-name "$STREAM_NAME"
    
    log_success "Kinesis stream created: $STREAM_NAME"
fi

# Verify stream creation and get details
STREAM_INFO=$(aws kinesis describe-stream \
    --stream-name "$STREAM_NAME" \
    --query 'StreamDescription.{Name:StreamName,Status:StreamStatus,Shards:length(Shards)}')

log_info "Stream details: $STREAM_INFO"

# ==============================================================================
# LAMBDA FUNCTION CREATION
# ==============================================================================

log_info "Creating Lambda function for real-time processing..."

# Create Lambda function code
cat > stream_processor.py << 'EOF'
import json
import boto3
import base64
import datetime
import os
from decimal import Decimal

s3_client = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    processed_records = 0
    total_amount = 0
    
    try:
        for record in event['Records']:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            data = json.loads(payload)
            
            # Process analytics data
            processed_records += 1
            
            # Example: Extract transaction amount for financial data
            if 'amount' in data:
                total_amount += float(data['amount'])
            
            # Store processed record to S3
            timestamp = datetime.datetime.now().isoformat()
            s3_key = f"analytics-data/{timestamp[:10]}/{record['kinesis']['sequenceNumber']}.json"
            
            # Add processing metadata
            enhanced_data = {
                'original_data': data,
                'processed_at': timestamp,
                'shard_id': record['kinesis']['partitionKey'],
                'sequence_number': record['kinesis']['sequenceNumber']
            }
            
            s3_client.put_object(
                Bucket=os.environ['S3_BUCKET'],
                Key=s3_key,
                Body=json.dumps(enhanced_data),
                ContentType='application/json'
            )
        
        # Send custom metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='KinesisAnalytics',
            MetricData=[
                {
                    'MetricName': 'ProcessedRecords',
                    'Value': processed_records,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'TotalAmount',
                    'Value': total_amount,
                    'Unit': 'None'
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'processed_records': processed_records,
                'total_amount': total_amount
            })
        }
        
    except Exception as e:
        print(f"Error processing records: {str(e)}")
        # Send error metric
        cloudwatch.put_metric_data(
            Namespace='KinesisAnalytics',
            MetricData=[
                {
                    'MetricName': 'ProcessingErrors',
                    'Value': 1,
                    'Unit': 'Count'
                }
            ]
        )
        raise
EOF

# Create deployment package
zip function.zip stream_processor.py

# Wait for IAM role to propagate
log_info "Waiting for IAM role to propagate..."
sleep 10

# Check if Lambda function already exists
if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
    log_warning "Lambda function $LAMBDA_FUNCTION_NAME already exists, updating code..."
    aws lambda update-function-code \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --zip-file fileb://function.zip
else
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler stream_processor.lambda_handler \
        --zip-file fileb://function.zip \
        --environment Variables="{S3_BUCKET=${S3_BUCKET_NAME}}" \
        --timeout 60 \
        --description "Real-time stream processor for Kinesis analytics"
    
    log_success "Lambda function created: $LAMBDA_FUNCTION_NAME"
fi

# ==============================================================================
# EVENT SOURCE MAPPING
# ==============================================================================

log_info "Configuring Lambda event source mapping..."

# Check if event source mapping already exists
EXISTING_MAPPING=$(aws lambda list-event-source-mappings \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --query 'EventSourceMappings[?contains(EventSourceArn, `'$STREAM_NAME'`)].UUID' \
    --output text)

if [[ -n "$EXISTING_MAPPING" && "$EXISTING_MAPPING" != "None" ]]; then
    log_warning "Event source mapping already exists: $EXISTING_MAPPING"
    export EVENT_SOURCE_UUID="$EXISTING_MAPPING"
else
    # Create event source mapping to trigger Lambda from Kinesis
    export EVENT_SOURCE_UUID=$(aws lambda create-event-source-mapping \
        --event-source-arn "arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${STREAM_NAME}" \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --starting-position LATEST \
        --batch-size 10 \
        --maximum-batching-window-in-seconds 5 \
        --query 'UUID' --output text)
    
    log_success "Event source mapping created: $EVENT_SOURCE_UUID"
fi

# Update environment variables file
echo "export EVENT_SOURCE_UUID=\"$EVENT_SOURCE_UUID\"" >> .env_vars

# ==============================================================================
# ENHANCED MONITORING AND ALERTING
# ==============================================================================

log_info "Enabling enhanced monitoring and alerting..."

# Enable enhanced monitoring for detailed metrics
aws kinesis enable-enhanced-monitoring \
    --stream-name "$STREAM_NAME" \
    --shard-level-metrics ALL

# Create CloudWatch alarm for high incoming records
aws cloudwatch put-metric-alarm \
    --alarm-name "KinesisHighIncomingRecords-${RANDOM_SUFFIX}" \
    --alarm-description "Alert when incoming records exceed threshold" \
    --metric-name IncomingRecords \
    --namespace AWS/Kinesis \
    --statistic Sum \
    --period 300 \
    --evaluation-periods 2 \
    --threshold 1000 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=StreamName,Value="$STREAM_NAME"

# Create alarm for Lambda function errors
aws cloudwatch put-metric-alarm \
    --alarm-name "LambdaProcessingErrors-${RANDOM_SUFFIX}" \
    --alarm-description "Alert on Lambda processing errors" \
    --metric-name Errors \
    --namespace AWS/Lambda \
    --statistic Sum \
    --period 300 \
    --evaluation-periods 1 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME"

log_success "Enhanced monitoring and alerting configured"

# ==============================================================================
# STREAM CONFIGURATION
# ==============================================================================

log_info "Configuring stream retention and scaling..."

# Increase retention period to 7 days for replay capability
aws kinesis increase-stream-retention-period \
    --stream-name "$STREAM_NAME" \
    --retention-period-hours 168

# Configure automatic scaling by updating shard count
aws kinesis update-shard-count \
    --stream-name "$STREAM_NAME" \
    --scaling-type UNIFORM_SCALING \
    --target-shard-count 5

# Wait for scaling to complete
log_info "Waiting for shard scaling to complete..."
sleep 30  # Give some time for the operation to start
aws kinesis wait stream-exists --stream-name "$STREAM_NAME"

log_success "Stream retention and scaling configured"

# ==============================================================================
# ANALYTICS DASHBOARD
# ==============================================================================

log_info "Creating analytics dashboard..."

# Create custom dashboard for monitoring
cat > dashboard_config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Kinesis", "IncomingRecords", "StreamName", "${STREAM_NAME}"],
                    [".", "OutgoingRecords", ".", "."],
                    ["AWS/Lambda", "Invocations", "FunctionName", "${LAMBDA_FUNCTION_NAME}"],
                    [".", "Errors", ".", "."],
                    ["KinesisAnalytics", "ProcessedRecords"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Real-Time Analytics Metrics"
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Duration", "FunctionName", "${LAMBDA_FUNCTION_NAME}"],
                    ["KinesisAnalytics", "TotalAmount"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Performance and Business Metrics"
            }
        }
    ]
}
EOF

# Create CloudWatch dashboard
aws cloudwatch put-dashboard \
    --dashboard-name "KinesisAnalytics-${RANDOM_SUFFIX}" \
    --dashboard-body file://dashboard_config.json

log_success "Analytics dashboard created: KinesisAnalytics-${RANDOM_SUFFIX}"

# ==============================================================================
# CREATE UTILITY SCRIPTS
# ==============================================================================

log_info "Creating utility scripts for testing..."

# Create sample data producer
cat > data_producer.py << 'EOF'
import boto3
import json
import random
import time
import sys
from datetime import datetime

# Initialize Kinesis client
kinesis_client = boto3.client('kinesis')

def generate_sample_data():
    """Generate sample analytics data"""
    return {
        'timestamp': datetime.now().isoformat(),
        'user_id': f"user_{random.randint(1000, 9999)}",
        'event_type': random.choice(['page_view', 'purchase', 'click', 'login']),
        'amount': round(random.uniform(10.0, 500.0), 2),
        'product_id': f"product_{random.randint(100, 999)}",
        'session_id': f"session_{random.randint(10000, 99999)}",
        'location': random.choice(['US', 'UK', 'CA', 'DE', 'FR']),
        'device_type': random.choice(['mobile', 'desktop', 'tablet'])
    }

def send_to_kinesis(stream_name, data, partition_key):
    """Send data to Kinesis stream"""
    try:
        response = kinesis_client.put_record(
            StreamName=stream_name,
            Data=json.dumps(data),
            PartitionKey=partition_key
        )
        return response
    except Exception as e:
        print(f"Error sending data: {e}")
        return None

def main():
    stream_name = sys.argv[1] if len(sys.argv) > 1 else 'analytics-stream'
    records_to_send = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    
    print(f"Sending {records_to_send} records to stream: {stream_name}")
    
    for i in range(records_to_send):
        data = generate_sample_data()
        partition_key = data['user_id']
        
        response = send_to_kinesis(stream_name, data, partition_key)
        if response:
            print(f"Record {i+1} sent - Shard: {response['ShardId']}")
        
        # Add small delay to simulate real-time streaming
        time.sleep(0.1)
    
    print(f"✅ Completed sending {records_to_send} records")

if __name__ == "__main__":
    main()
EOF

# Create stream monitoring script
cat > stream_monitor.py << 'EOF'
import boto3
import json
import time
import sys
from datetime import datetime

kinesis_client = boto3.client('kinesis')

def get_shard_iterator(stream_name, shard_id):
    """Get shard iterator for reading from stream"""
    response = kinesis_client.get_shard_iterator(
        StreamName=stream_name,
        ShardId=shard_id,
        ShardIteratorType='LATEST'
    )
    return response['ShardIterator']

def read_from_stream(stream_name, duration_seconds=60):
    """Read records from stream for specified duration"""
    # Get stream description
    stream_desc = kinesis_client.describe_stream(StreamName=stream_name)
    shards = stream_desc['StreamDescription']['Shards']
    
    print(f"Monitoring stream: {stream_name}")
    print(f"Shards: {len(shards)}")
    print(f"Duration: {duration_seconds} seconds")
    print("-" * 50)
    
    # Create shard iterators
    shard_iterators = {}
    for shard in shards:
        shard_id = shard['ShardId']
        shard_iterators[shard_id] = get_shard_iterator(stream_name, shard_id)
    
    start_time = time.time()
    total_records = 0
    
    while (time.time() - start_time) < duration_seconds:
        for shard_id, iterator in shard_iterators.items():
            if iterator:
                try:
                    response = kinesis_client.get_records(
                        ShardIterator=iterator,
                        Limit=25
                    )
                    
                    records = response['Records']
                    if records:
                        total_records += len(records)
                        print(f"[{datetime.now().strftime('%H:%M:%S')}] "
                              f"Shard {shard_id}: {len(records)} records")
                        
                        # Process records
                        for record in records:
                            data = json.loads(record['Data'])
                            print(f"  └─ {data.get('event_type', 'unknown')} "
                                  f"by {data.get('user_id', 'unknown')}")
                    
                    # Update iterator
                    shard_iterators[shard_id] = response.get('NextShardIterator')
                    
                except Exception as e:
                    print(f"Error reading from shard {shard_id}: {e}")
                    shard_iterators[shard_id] = None
        
        time.sleep(1)
    
    print(f"\n✅ Monitoring complete. Total records processed: {total_records}")

def main():
    stream_name = sys.argv[1] if len(sys.argv) > 1 else 'analytics-stream'
    duration = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    
    read_from_stream(stream_name, duration)

if __name__ == "__main__":
    main()
EOF

# Make scripts executable
chmod +x data_producer.py stream_monitor.py

log_success "Utility scripts created"

# ==============================================================================
# VALIDATION
# ==============================================================================

log_info "Validating deployment..."

# Verify stream status
STREAM_STATUS=$(aws kinesis describe-stream \
    --stream-name "$STREAM_NAME" \
    --query 'StreamDescription.StreamStatus' --output text)

if [[ "$STREAM_STATUS" == "ACTIVE" ]]; then
    log_success "Kinesis stream is active"
else
    log_error "Kinesis stream is not active: $STREAM_STATUS"
    exit 1
fi

# Verify Lambda function
LAMBDA_STATE=$(aws lambda get-function \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --query 'Configuration.State' --output text)

if [[ "$LAMBDA_STATE" == "Active" ]]; then
    log_success "Lambda function is active"
else
    log_error "Lambda function is not active: $LAMBDA_STATE"
    exit 1
fi

# Verify S3 bucket
if aws s3 ls "s3://${S3_BUCKET_NAME}" >/dev/null 2>&1; then
    log_success "S3 bucket is accessible"
else
    log_error "S3 bucket is not accessible"
    exit 1
fi

# ==============================================================================
# CLEANUP TEMPORARY FILES
# ==============================================================================

log_info "Cleaning up temporary files..."

rm -f lambda-trust-policy.json stream-processor-policy.json
rm -f function.zip stream_processor.py
rm -f dashboard_config.json lifecycle-policy.json

log_success "Temporary files cleaned up"

# ==============================================================================
# DEPLOYMENT SUMMARY
# ==============================================================================

echo ""
echo "===================================================================================="
echo "                         DEPLOYMENT COMPLETED SUCCESSFULLY"
echo "===================================================================================="
echo ""
echo "📊 Real-Time Analytics Pipeline deployed with the following resources:"
echo ""
echo "🔄 Kinesis Data Stream:"
echo "   • Name: $STREAM_NAME"
echo "   • Shards: 5"
echo "   • Retention: 7 days"
echo "   • Enhanced monitoring: Enabled"
echo ""
echo "⚡ Lambda Function:"
echo "   • Name: $LAMBDA_FUNCTION_NAME"
echo "   • Runtime: Python 3.9"
echo "   • Event source mapping: Configured"
echo ""
echo "🗄️  S3 Bucket:"
echo "   • Name: $S3_BUCKET_NAME"
echo "   • Versioning: Enabled"
echo "   • Lifecycle policy: Applied"
echo ""
echo "📈 CloudWatch Dashboard:"
echo "   • Name: KinesisAnalytics-${RANDOM_SUFFIX}"
echo "   • URL: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=KinesisAnalytics-${RANDOM_SUFFIX}"
echo ""
echo "🚨 CloudWatch Alarms:"
echo "   • KinesisHighIncomingRecords-${RANDOM_SUFFIX}"
echo "   • LambdaProcessingErrors-${RANDOM_SUFFIX}"
echo ""
echo "🧪 Testing Scripts Available:"
echo "   • data_producer.py - Generate sample data"
echo "   • stream_monitor.py - Monitor stream in real-time"
echo ""
echo "📝 Example Usage:"
echo "   # Send test data:"
echo "   python3 data_producer.py $STREAM_NAME 100"
echo ""
echo "   # Monitor stream:"
echo "   python3 stream_monitor.py $STREAM_NAME 60"
echo ""
echo "💡 Next Steps:"
echo "   1. Test the pipeline using the provided scripts"
echo "   2. Monitor metrics in the CloudWatch dashboard"
echo "   3. Check S3 bucket for processed data"
echo "   4. Review Lambda function logs for processing details"
echo ""
echo "💰 Estimated Monthly Cost: $50-100 (varies by usage)"
echo ""
echo "🧹 To clean up resources, run: ./destroy.sh"
echo "===================================================================================="
echo ""

log_success "Real-time analytics pipeline deployment completed successfully! 🎉"