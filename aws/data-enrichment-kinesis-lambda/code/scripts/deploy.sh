#!/bin/bash

# Deploy script for Streaming Data Enrichment with Kinesis
# This script creates all infrastructure components for real-time data enrichment pipeline

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

# Error handler
error_handler() {
    log_error "Script failed at line $1"
    log_error "Attempting cleanup of partially created resources..."
    cleanup_on_error
    exit 1
}

trap 'error_handler $LINENO' ERR

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Cleaning up partially created resources..."
    
    # Remove temporary files
    rm -f /tmp/trust-policy.json /tmp/lambda-policy.json 2>/dev/null || true
    rm -f /tmp/enrichment_function.py /tmp/enrichment_function.zip 2>/dev/null || true
    
    log_warning "Manual cleanup may be required for AWS resources"
    log_warning "Check AWS Console for: Lambda functions, Kinesis streams, DynamoDB tables, S3 buckets, IAM roles"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Verify required permissions
    log "Verifying AWS permissions..."
    
    # Test basic permissions
    if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity &> /dev/null; then
        log_error "Unable to verify AWS permissions. Ensure you have sufficient IAM permissions."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_warning "AWS region not set in configuration. Using us-east-1 as default."
        export AWS_REGION="us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export STREAM_NAME="data-enrichment-stream-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="data-enrichment-function-${RANDOM_SUFFIX}"
    export BUCKET_NAME="enriched-data-bucket-${RANDOM_SUFFIX}"
    export TABLE_NAME="enrichment-lookup-table-${RANDOM_SUFFIX}"
    export ROLE_NAME="data-enrichment-role-${RANDOM_SUFFIX}"
    
    # Save environment variables for cleanup script
    cat > /tmp/data-enrichment-env.sh << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export STREAM_NAME="$STREAM_NAME"
export FUNCTION_NAME="$FUNCTION_NAME"
export BUCKET_NAME="$BUCKET_NAME"
export TABLE_NAME="$TABLE_NAME"
export ROLE_NAME="$ROLE_NAME"
EOF
    
    log_success "Environment variables configured"
    log "Stream Name: ${STREAM_NAME}"
    log "Function Name: ${FUNCTION_NAME}"
    log "Bucket Name: ${BUCKET_NAME}"
    log "Table Name: ${TABLE_NAME}"
    log "Role Name: ${ROLE_NAME}"
}

# Function to create DynamoDB table
create_dynamodb_table() {
    log "Creating DynamoDB table for lookup data..."
    
    aws dynamodb create-table \
        --table-name ${TABLE_NAME} \
        --attribute-definitions \
            AttributeName=user_id,AttributeType=S \
        --key-schema \
            AttributeName=user_id,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Purpose,Value=DataEnrichment \
              Key=Environment,Value=Development \
              Key=DeployedBy,Value=bash-script
    
    # Wait for table to be active
    log "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name ${TABLE_NAME}
    
    log_success "DynamoDB table created: ${TABLE_NAME}"
}

# Function to populate lookup table with sample data
populate_lookup_table() {
    log "Populating lookup table with sample data..."
    
    # Add sample user profiles for enrichment
    aws dynamodb put-item \
        --table-name ${TABLE_NAME} \
        --item '{
            "user_id": {"S": "user123"},
            "name": {"S": "John Doe"},
            "email": {"S": "john@example.com"},
            "segment": {"S": "premium"},
            "location": {"S": "New York"}
        }'
    
    aws dynamodb put-item \
        --table-name ${TABLE_NAME} \
        --item '{
            "user_id": {"S": "user456"},
            "name": {"S": "Jane Smith"},
            "email": {"S": "jane@example.com"},
            "segment": {"S": "standard"},
            "location": {"S": "California"}
        }'
    
    # Add more sample data for testing
    aws dynamodb put-item \
        --table-name ${TABLE_NAME} \
        --item '{
            "user_id": {"S": "user789"},
            "name": {"S": "Bob Wilson"},
            "email": {"S": "bob@example.com"},
            "segment": {"S": "enterprise"},
            "location": {"S": "Texas"}
        }'
    
    log_success "Sample data populated in lookup table"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for enriched data output..."
    
    # Create S3 bucket with region-specific command
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb s3://${BUCKET_NAME}
    else
        aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
    fi
    
    # Enable versioning for data integrity
    aws s3api put-bucket-versioning \
        --bucket ${BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    # Add bucket tagging
    aws s3api put-bucket-tagging \
        --bucket ${BUCKET_NAME} \
        --tagging 'TagSet=[
            {Key=Purpose,Value=DataEnrichment},
            {Key=Environment,Value=Development},
            {Key=DeployedBy,Value=bash-script}
        ]'
    
    log_success "S3 bucket created: ${BUCKET_NAME}"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for Lambda function..."
    
    # Create trust policy for Lambda
    cat > /tmp/trust-policy.json << EOF
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
        --role-name ${ROLE_NAME} \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --tags Key=Purpose,Value=DataEnrichment \
               Key=Environment,Value=Development \
               Key=DeployedBy,Value=bash-script
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    log_success "IAM role created: ${ROLE_NAME}"
}

# Function to create custom IAM policy
create_custom_policy() {
    log "Creating custom policy for Lambda permissions..."
    
    # Create policy with necessary permissions
    cat > /tmp/lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kinesis:DescribeStream",
                "kinesis:DescribeStreamSummary",
                "kinesis:GetRecords",
                "kinesis:GetShardIterator",
                "kinesis:ListShards",
                "kinesis:SubscribeToShard"
            ],
            "Resource": "arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${STREAM_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${TABLE_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl"
            ],
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
        }
    ]
}
EOF
    
    # Create and attach custom policy
    aws iam create-policy \
        --policy-name ${ROLE_NAME}-policy \
        --policy-document file:///tmp/lambda-policy.json \
        --tags Key=Purpose,Value=DataEnrichment \
               Key=Environment,Value=Development \
               Key=DeployedBy,Value=bash-script
    
    aws iam attach-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-policy
    
    log_success "Custom policy created and attached"
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function for data enrichment..."
    
    # Create Lambda function code
    cat > /tmp/enrichment_function.py << 'EOF'
import json
import boto3
import base64
import datetime
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    # Get environment variables
    table_name = os.environ['TABLE_NAME']
    bucket_name = os.environ['BUCKET_NAME']
    
    table = dynamodb.Table(table_name)
    processed_records = 0
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data'])
            data = json.loads(payload)
            
            # Enrich data with user profile
            user_id = data.get('user_id')
            if user_id:
                try:
                    response = table.get_item(Key={'user_id': user_id})
                    if 'Item' in response:
                        # Add user profile data to event
                        user_profile = response['Item']
                        data['user_name'] = user_profile.get('name', 'Unknown')
                        data['user_email'] = user_profile.get('email', 'Unknown')
                        data['user_segment'] = user_profile.get('segment', 'Unknown')
                        data['user_location'] = user_profile.get('location', 'Unknown')
                    else:
                        data['user_name'] = 'Unknown'
                        data['user_segment'] = 'Unknown'
                        data['user_email'] = 'Unknown'
                        data['user_location'] = 'Unknown'
                except Exception as e:
                    print(f"Error enriching user data: {e}")
                    data['enrichment_error'] = str(e)
                    data['user_name'] = 'Error'
                    data['user_segment'] = 'Error'
            
            # Add processing timestamp
            data['processing_timestamp'] = datetime.datetime.utcnow().isoformat()
            data['enriched'] = True
            data['processor_version'] = '1.0'
            
            # Store enriched data in S3
            timestamp = datetime.datetime.utcnow().strftime('%Y/%m/%d/%H')
            key = f"enriched-data/{timestamp}/{record['kinesis']['sequenceNumber']}.json"
            
            try:
                s3.put_object(
                    Bucket=bucket_name,
                    Key=key,
                    Body=json.dumps(data, default=str),
                    ContentType='application/json'
                )
                print(f"Successfully processed record: {record['kinesis']['sequenceNumber']}")
                processed_records += 1
            except Exception as e:
                print(f"Error storing enriched data: {e}")
                raise
                
        except Exception as e:
            print(f"Error processing record: {e}")
            # Continue processing other records
            continue
    
    return {
        'statusCode': 200,
        'body': f"Successfully processed {processed_records} out of {len(event['Records'])} records"
    }
EOF
    
    # Create deployment package
    cd /tmp && zip enrichment_function.zip enrichment_function.py
    
    # Wait for IAM role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
    
    # Create Lambda function
    aws lambda create-function \
        --function-name ${FUNCTION_NAME} \
        --runtime python3.9 \
        --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME} \
        --handler enrichment_function.lambda_handler \
        --zip-file fileb://enrichment_function.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables="{TABLE_NAME=${TABLE_NAME},BUCKET_NAME=${BUCKET_NAME}}" \
        --tags Purpose=DataEnrichment,Environment=Development,DeployedBy=bash-script
    
    log_success "Lambda function created: ${FUNCTION_NAME}"
}

# Function to create Kinesis Data Stream
create_kinesis_stream() {
    log "Creating Kinesis Data Stream..."
    
    # Create Kinesis Data Stream with 2 shards
    aws kinesis create-stream \
        --stream-name ${STREAM_NAME} \
        --shard-count 2
    
    # Wait for stream to be active
    log "Waiting for Kinesis stream to become active..."
    aws kinesis wait stream-exists --stream-name ${STREAM_NAME}
    
    # Add tags to the stream
    aws kinesis add-tags-to-stream \
        --stream-name ${STREAM_NAME} \
        --tags Purpose=DataEnrichment,Environment=Development,DeployedBy=bash-script
    
    log_success "Kinesis Data Stream created: ${STREAM_NAME}"
}

# Function to create event source mapping
create_event_source_mapping() {
    log "Creating event source mapping to connect Kinesis to Lambda..."
    
    # Get stream ARN
    STREAM_ARN=$(aws kinesis describe-stream \
        --stream-name ${STREAM_NAME} \
        --query 'StreamDescription.StreamARN' \
        --output text)
    
    # Create event source mapping
    aws lambda create-event-source-mapping \
        --event-source-arn ${STREAM_ARN} \
        --function-name ${FUNCTION_NAME} \
        --starting-position LATEST \
        --batch-size 10 \
        --maximum-batching-window-in-seconds 5
    
    log_success "Event source mapping created"
    log "Stream ARN: ${STREAM_ARN}"
}

# Function to enable enhanced monitoring
enable_enhanced_monitoring() {
    log "Enabling enhanced monitoring on Kinesis stream..."
    
    # Enable enhanced monitoring for better observability
    aws kinesis enable-enhanced-monitoring \
        --stream-name ${STREAM_NAME} \
        --shard-level-metrics IncomingRecords,OutgoingRecords,IncomingBytes,OutgoingBytes
    
    log_success "Enhanced monitoring enabled"
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms for monitoring..."
    
    # Create alarm for Lambda function errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "${FUNCTION_NAME}-Errors" \
        --alarm-description "Lambda function errors for data enrichment" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --treat-missing-data notBreaching \
        --dimensions Name=FunctionName,Value=${FUNCTION_NAME}
    
    # Create alarm for Kinesis incoming records
    aws cloudwatch put-metric-alarm \
        --alarm-name "${STREAM_NAME}-IncomingRecords" \
        --alarm-description "Kinesis incoming records monitoring" \
        --metric-name IncomingRecords \
        --namespace AWS/Kinesis \
        --statistic Sum \
        --period 300 \
        --threshold 0 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 2 \
        --treat-missing-data notBreaching \
        --dimensions Name=StreamName,Value=${STREAM_NAME}
    
    # Create alarm for Lambda duration
    aws cloudwatch put-metric-alarm \
        --alarm-name "${FUNCTION_NAME}-Duration" \
        --alarm-description "Lambda function duration monitoring" \
        --metric-name Duration \
        --namespace AWS/Lambda \
        --statistic Average \
        --period 300 \
        --threshold 30000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --treat-missing-data notBreaching \
        --dimensions Name=FunctionName,Value=${FUNCTION_NAME}
    
    log_success "CloudWatch alarms created"
}

# Function to test the deployment
test_deployment() {
    log "Testing the deployment with sample data..."
    
    # Send sample clickstream event
    log "Sending test event for user123..."
    aws kinesis put-record \
        --stream-name ${STREAM_NAME} \
        --partition-key "user123" \
        --data '{
            "event_type": "page_view",
            "user_id": "user123",
            "page": "/product/abc123",
            "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
            "session_id": "session_xyz",
            "test_deployment": true
        }'
    
    # Send another event for different user
    log "Sending test event for user456..."
    aws kinesis put-record \
        --stream-name ${STREAM_NAME} \
        --partition-key "user456" \
        --data '{
            "event_type": "add_to_cart",
            "user_id": "user456",
            "product_id": "prod789",
            "quantity": 2,
            "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
            "session_id": "session_abc",
            "test_deployment": true
        }'
    
    log_success "Test events sent to Kinesis stream"
    log_warning "Wait 2-3 minutes for processing, then check S3 bucket ${BUCKET_NAME} for enriched data"
}

# Function to display deployment summary
display_summary() {
    log_success "=== Deployment Complete ==="
    echo ""
    echo "Resources Created:"
    echo "  • DynamoDB Table: ${TABLE_NAME}"
    echo "  • S3 Bucket: ${BUCKET_NAME}"
    echo "  • IAM Role: ${ROLE_NAME}"
    echo "  • Lambda Function: ${FUNCTION_NAME}"
    echo "  • Kinesis Stream: ${STREAM_NAME}"
    echo "  • CloudWatch Alarms: 3 alarms created"
    echo ""
    echo "Testing:"
    echo "  • Test events have been sent to the stream"
    echo "  • Check CloudWatch Logs for Lambda execution: /aws/lambda/${FUNCTION_NAME}"
    echo "  • Check S3 bucket for enriched data: s3://${BUCKET_NAME}/enriched-data/"
    echo ""
    echo "Monitoring:"
    echo "  • Lambda Function Errors: ${FUNCTION_NAME}-Errors"
    echo "  • Kinesis Incoming Records: ${STREAM_NAME}-IncomingRecords"
    echo "  • Lambda Duration: ${FUNCTION_NAME}-Duration"
    echo ""
    echo "Next Steps:"
    echo "  1. Monitor CloudWatch alarms for any issues"
    echo "  2. Send additional test data using:"
    echo "     aws kinesis put-record --stream-name ${STREAM_NAME} --partition-key <key> --data <json>"
    echo "  3. Use the destroy.sh script to clean up resources when finished"
    echo ""
    echo "Environment variables saved to: /tmp/data-enrichment-env.sh"
    echo "Run 'source /tmp/data-enrichment-env.sh' to reload environment for cleanup"
}

# Main deployment function
main() {
    log "=== Starting Data Enrichment Pipeline Deployment ==="
    
    check_prerequisites
    setup_environment
    create_dynamodb_table
    populate_lookup_table
    create_s3_bucket
    create_iam_role
    create_custom_policy
    create_lambda_function
    create_kinesis_stream
    create_event_source_mapping
    enable_enhanced_monitoring
    create_cloudwatch_alarms
    test_deployment
    
    # Clean up temporary files
    rm -f /tmp/trust-policy.json /tmp/lambda-policy.json
    rm -f /tmp/enrichment_function.py /tmp/enrichment_function.zip
    
    display_summary
}

# Run main function
main "$@"