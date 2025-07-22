#!/bin/bash

# Real-time Data Processing with Kinesis and Lambda - Deployment Script
# This script deploys the complete serverless data processing pipeline

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    log_info "Checking AWS CLI configuration..."
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or credentials are invalid"
        log_error "Please run 'aws configure' or set AWS environment variables"
        exit 1
    fi
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region || echo "us-east-1")
    
    log_success "AWS CLI configured for account: $AWS_ACCOUNT_ID in region: $AWS_REGION"
}

# Function to validate prerequisites
check_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check required commands
    local required_commands=("aws" "python3" "zip")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command '$cmd' is not installed"
            exit 1
        fi
    done
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | awk '{print $1}' | cut -d/ -f2)
    log_info "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check Python version
    PYTHON_VERSION=$(python3 --version | awk '{print $2}')
    log_info "Python version: $PYTHON_VERSION"
    
    # Check if boto3 is available
    if ! python3 -c "import boto3" 2>/dev/null; then
        log_warning "boto3 is not installed. Installing..."
        python3 -m pip install boto3 --user
    fi
    
    log_success "All prerequisites validated"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique identifiers with timestamp
    TIMESTAMP=$(date +%s)
    
    # Core environment variables
    export STREAM_NAME="${STREAM_NAME:-realtime-data-stream-$TIMESTAMP}"
    export LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:-kinesis-data-processor-$TIMESTAMP}"
    export S3_BUCKET_NAME="${S3_BUCKET_NAME:-processed-data-$TIMESTAMP}"
    export IAM_ROLE_NAME="${IAM_ROLE_NAME:-kinesis-lambda-execution-role-$TIMESTAMP}"
    
    # Save environment variables to file for cleanup script
    cat > .env_vars << EOF
STREAM_NAME=$STREAM_NAME
LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
S3_BUCKET_NAME=$S3_BUCKET_NAME
IAM_ROLE_NAME=$IAM_ROLE_NAME
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
TIMESTAMP=$TIMESTAMP
EOF
    
    log_success "Environment variables configured:"
    log_info "  Stream Name: $STREAM_NAME"
    log_info "  Lambda Function: $LAMBDA_FUNCTION_NAME"
    log_info "  S3 Bucket: $S3_BUCKET_NAME"
    log_info "  IAM Role: $IAM_ROLE_NAME"
}

# Function to create S3 bucket
create_s3_bucket() {
    log_info "Creating S3 bucket for processed data..."
    
    if aws s3 ls "s3://$S3_BUCKET_NAME" >/dev/null 2>&1; then
        log_warning "S3 bucket $S3_BUCKET_NAME already exists"
    else
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3 mb "s3://$S3_BUCKET_NAME"
        else
            aws s3 mb "s3://$S3_BUCKET_NAME" --region "$AWS_REGION"
        fi
        log_success "S3 bucket created: $S3_BUCKET_NAME"
    fi
}

# Function to create IAM role and policies
create_iam_role() {
    log_info "Creating IAM role for Lambda execution..."
    
    # Create trust policy
    cat > trust-policy.json << 'EOF'
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
            --assume-role-policy-document file://trust-policy.json \
            --description "Execution role for Kinesis Lambda data processing"
        
        log_success "IAM role created: $IAM_ROLE_NAME"
    fi
    
    # Attach managed policies
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AWSLambdaKinesisExecutionRole
    
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
    
    # Get role ARN
    ROLE_ARN=$(aws iam get-role --role-name "$IAM_ROLE_NAME" --query 'Role.Arn' --output text)
    export ROLE_ARN
    
    # Add role ARN to environment file
    echo "ROLE_ARN=$ROLE_ARN" >> .env_vars
    
    log_success "IAM policies attached to role"
    log_info "Role ARN: $ROLE_ARN"
}

# Function to create Kinesis stream
create_kinesis_stream() {
    log_info "Creating Kinesis Data Stream..."
    
    # Check if stream already exists
    if aws kinesis describe-stream --stream-name "$STREAM_NAME" >/dev/null 2>&1; then
        log_warning "Kinesis stream $STREAM_NAME already exists"
        STREAM_STATUS=$(aws kinesis describe-stream --stream-name "$STREAM_NAME" --query 'StreamDescription.StreamStatus' --output text)
        log_info "Current stream status: $STREAM_STATUS"
    else
        # Create stream with 3 shards for parallel processing
        aws kinesis create-stream \
            --stream-name "$STREAM_NAME" \
            --shard-count 3
        
        log_success "Kinesis stream creation initiated: $STREAM_NAME"
    fi
    
    # Wait for stream to become active
    log_info "Waiting for stream to become active (this may take a few minutes)..."
    aws kinesis wait stream-exists --stream-name "$STREAM_NAME"
    
    # Get stream ARN
    STREAM_ARN=$(aws kinesis describe-stream --stream-name "$STREAM_NAME" --query 'StreamDescription.StreamARN' --output text)
    export STREAM_ARN
    
    # Add stream ARN to environment file
    echo "STREAM_ARN=$STREAM_ARN" >> .env_vars
    
    log_success "Kinesis stream is active: $STREAM_NAME"
    log_info "Stream ARN: $STREAM_ARN"
}

# Function to create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function for data processing..."
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import base64
import boto3
import os
from datetime import datetime
from typing import Dict, Any, List

s3_client = boto3.client('s3')
BUCKET_NAME = os.environ['S3_BUCKET_NAME']

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process Kinesis records and store processed data in S3
    """
    processed_records = []
    
    for record in event['Records']:
        try:
            # Decode the Kinesis record data
            kinesis_data = record['kinesis']
            encoded_data = kinesis_data['data']
            decoded_data = base64.b64decode(encoded_data).decode('utf-8')
            
            # Parse the JSON data
            try:
                json_data = json.loads(decoded_data)
            except json.JSONDecodeError:
                # If not JSON, treat as plain text
                json_data = {"message": decoded_data}
                
            # Add processing metadata
            processed_record = {
                "original_data": json_data,
                "processing_timestamp": datetime.utcnow().isoformat(),
                "partition_key": kinesis_data['partitionKey'],
                "sequence_number": kinesis_data['sequenceNumber'],
                "event_id": record['eventID'],
                "processed": True
            }
            
            processed_records.append(processed_record)
            
            print(f"Processed record with EventID: {record['eventID']}")
            
        except Exception as e:
            print(f"Error processing record {record.get('eventID', 'unknown')}: {str(e)}")
            continue
    
    # Store processed records in S3
    if processed_records:
        try:
            s3_key = f"processed-data/{datetime.utcnow().strftime('%Y/%m/%d/%H')}/batch-{context.aws_request_id}.json"
            
            s3_client.put_object(
                Bucket=BUCKET_NAME,
                Key=s3_key,
                Body=json.dumps(processed_records, indent=2),
                ContentType='application/json'
            )
            
            print(f"Successfully stored {len(processed_records)} processed records to S3: {s3_key}")
            
        except Exception as e:
            print(f"Error storing data to S3: {str(e)}")
            raise
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed_count': len(processed_records),
            'message': 'Successfully processed Kinesis records'
        })
    }
EOF
    
    # Create deployment package
    zip lambda-function.zip lambda_function.py
    
    # Check if function already exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        log_warning "Lambda function $LAMBDA_FUNCTION_NAME already exists, updating code..."
        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --zip-file fileb://lambda-function.zip
    else
        # Wait a moment for IAM role to propagate
        log_info "Waiting for IAM role to propagate..."
        sleep 10
        
        # Create Lambda function
        aws lambda create-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --runtime python3.9 \
            --role "$ROLE_ARN" \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://lambda-function.zip \
            --timeout 60 \
            --memory-size 256 \
            --environment "Variables={S3_BUCKET_NAME=$S3_BUCKET_NAME}" \
            --description "Real-time data processor for Kinesis stream"
        
        log_success "Lambda function created: $LAMBDA_FUNCTION_NAME"
    fi
    
    # Update environment variables if needed
    aws lambda update-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --environment "Variables={S3_BUCKET_NAME=$S3_BUCKET_NAME}"
    
    log_success "Lambda function configured with S3 bucket: $S3_BUCKET_NAME"
}

# Function to create event source mapping
create_event_source_mapping() {
    log_info "Creating event source mapping between Kinesis and Lambda..."
    
    # Check if mapping already exists
    EXISTING_MAPPING=$(aws lambda list-event-source-mappings \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query "EventSourceMappings[?EventSourceArn=='$STREAM_ARN'].UUID" \
        --output text)
    
    if [ -n "$EXISTING_MAPPING" ] && [ "$EXISTING_MAPPING" != "None" ]; then
        log_warning "Event source mapping already exists: $EXISTING_MAPPING"
        EVENT_SOURCE_UUID="$EXISTING_MAPPING"
    else
        # Create event source mapping
        EVENT_SOURCE_UUID=$(aws lambda create-event-source-mapping \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --event-source-arn "$STREAM_ARN" \
            --starting-position LATEST \
            --batch-size 100 \
            --maximum-batching-window-in-seconds 5 \
            --query 'UUID' --output text)
        
        log_success "Event source mapping created: $EVENT_SOURCE_UUID"
    fi
    
    # Add mapping UUID to environment file
    echo "EVENT_SOURCE_UUID=$EVENT_SOURCE_UUID" >> .env_vars
    
    log_info "Event source mapping UUID: $EVENT_SOURCE_UUID"
}

# Function to create data generator
create_data_generator() {
    log_info "Creating data generator script..."
    
    cat > data_generator.py << EOF
import boto3
import json
import time
import random
from datetime import datetime

kinesis_client = boto3.client('kinesis')
STREAM_NAME = '$STREAM_NAME'

def generate_sample_data():
    """Generate sample IoT-like data"""
    return {
        "device_id": f"device_{random.randint(1, 100)}",
        "temperature": round(random.uniform(18.0, 35.0), 2),
        "humidity": round(random.uniform(30.0, 80.0), 2),
        "timestamp": datetime.utcnow().isoformat(),
        "location": {
            "lat": round(random.uniform(-90, 90), 6),
            "lon": round(random.uniform(-180, 180), 6)
        },
        "battery_level": random.randint(10, 100)
    }

def send_records_to_kinesis(num_records=50):
    """Send multiple records to Kinesis stream"""
    print(f"Sending {num_records} records to Kinesis stream: {STREAM_NAME}")
    
    for i in range(num_records):
        data = generate_sample_data()
        
        response = kinesis_client.put_record(
            StreamName=STREAM_NAME,
            Data=json.dumps(data),
            PartitionKey=data['device_id']
        )
        
        if i % 10 == 0:
            print(f"Sent {i+1} records...")
        
        # Small delay to simulate real-time data
        time.sleep(0.1)
    
    print(f"Successfully sent {num_records} records to Kinesis!")

if __name__ == "__main__":
    send_records_to_kinesis()
EOF
    
    chmod +x data_generator.py
    log_success "Data generator script created: data_generator.py"
}

# Function to test the pipeline
test_pipeline() {
    log_info "Testing the pipeline with sample data..."
    
    # Send test data
    python3 data_generator.py
    
    log_success "Test data sent to Kinesis stream"
    log_info "Lambda functions should be processing the data now"
    log_info "Check CloudWatch Logs for Lambda execution details"
    log_info "Processed data will appear in S3 bucket: $S3_BUCKET_NAME"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Kinesis Stream: $STREAM_NAME"
    echo "Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "S3 Bucket: $S3_BUCKET_NAME"
    echo "IAM Role: $IAM_ROLE_NAME"
    echo "AWS Region: $AWS_REGION"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Run the data generator: python3 data_generator.py"
    echo "2. Monitor Lambda logs: aws logs tail /aws/lambda/$LAMBDA_FUNCTION_NAME --follow"
    echo "3. Check processed data: aws s3 ls s3://$S3_BUCKET_NAME/processed-data/ --recursive"
    echo "4. Clean up resources: ./destroy.sh"
    echo
    echo "=== MONITORING ==="
    echo "CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#logsV2:log-groups/log-group/\$252Faws\$252Flambda\$252F$LAMBDA_FUNCTION_NAME"
    echo "Kinesis Console: https://console.aws.amazon.com/kinesis/home?region=$AWS_REGION#/streams/details/$STREAM_NAME"
    echo "S3 Console: https://s3.console.aws.amazon.com/s3/buckets/$S3_BUCKET_NAME"
}

# Function to cleanup on failure
cleanup_on_failure() {
    log_error "Deployment failed. Cleaning up partial resources..."
    
    # Source environment variables if they exist
    if [ -f .env_vars ]; then
        source .env_vars
    fi
    
    # Call cleanup script if it exists
    if [ -f destroy.sh ] && [ -x destroy.sh ]; then
        ./destroy.sh --force
    fi
}

# Main deployment function
main() {
    log_info "Starting deployment of Real-time Data Processing with Kinesis and Lambda"
    echo
    
    # Set trap for cleanup on failure
    trap cleanup_on_failure ERR
    
    # Run deployment steps
    check_prerequisites
    check_aws_config
    setup_environment
    create_s3_bucket
    create_iam_role
    create_kinesis_stream
    create_lambda_function
    create_event_source_mapping
    create_data_generator
    
    # Optional: Test the pipeline
    if [ "${SKIP_TEST:-false}" != "true" ]; then
        test_pipeline
    fi
    
    display_summary
    
    # Clear the error trap
    trap - ERR
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi