#!/bin/bash

# Deploy script for Streaming ETL with Kinesis Data Firehose Transformations
# This script creates a complete streaming ETL pipeline using Kinesis Data Firehose and Lambda

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

# Function to check AWS CLI authentication
check_aws_auth() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or not authenticated"
        log_info "Please run 'aws configure' or set appropriate environment variables"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check for required commands
    local required_commands=("aws" "jq" "zip")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command '$cmd' is not installed"
            exit 1
        fi
    done
    
    # Check AWS authentication
    check_aws_auth
    
    # Check for required AWS CLI version (v2 minimum)
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version
    major_version=$(echo "$aws_version" | cut -d. -f1)
    
    if [[ "$major_version" -lt 2 ]]; then
        log_error "AWS CLI version 2.x is required. Current version: $aws_version"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region is not configured"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export FIREHOSE_STREAM_NAME="streaming-etl-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="firehose-transform-${random_suffix}"
    export S3_BUCKET_NAME="streaming-etl-data-${random_suffix}"
    export IAM_ROLE_NAME="FirehoseDeliveryRole-${random_suffix}"
    export LAMBDA_ROLE_NAME="FirehoseLambdaRole-${random_suffix}"
    
    log_success "Environment variables configured"
    log_info "Region: $AWS_REGION"
    log_info "Account ID: $AWS_ACCOUNT_ID"
    log_info "S3 Bucket: $S3_BUCKET_NAME"
    log_info "Firehose Stream: $FIREHOSE_STREAM_NAME"
}

# Function to create S3 bucket
create_s3_bucket() {
    log_info "Creating S3 bucket..."
    
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
        log_warning "S3 bucket $S3_BUCKET_NAME already exists"
    else
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3 mb "s3://${S3_BUCKET_NAME}"
        else
            aws s3 mb "s3://${S3_BUCKET_NAME}" --region "$AWS_REGION"
        fi
        log_success "S3 bucket created: s3://${S3_BUCKET_NAME}"
    fi
}

# Function to create IAM roles and policies
create_iam_resources() {
    log_info "Creating IAM roles and policies..."
    
    # Create trust policy for Firehose
    cat > /tmp/firehose-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create Firehose IAM role
    if aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
        log_warning "Firehose IAM role $IAM_ROLE_NAME already exists"
    else
        aws iam create-role \
            --role-name "$IAM_ROLE_NAME" \
            --assume-role-policy-document file:///tmp/firehose-trust-policy.json
        log_success "Firehose IAM role created"
    fi
    
    export FIREHOSE_ROLE_ARN=$(aws iam get-role \
        --role-name "$IAM_ROLE_NAME" \
        --query 'Role.Arn' --output text)
    
    # Create S3 access policy for Firehose
    cat > /tmp/firehose-s3-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET_NAME}",
        "arn:aws:s3:::${S3_BUCKET_NAME}/*"
      ]
    }
  ]
}
EOF
    
    # Create and attach S3 policy
    local s3_policy_name="FirehoseS3DeliveryPolicy-${FIREHOSE_STREAM_NAME##*-}"
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${s3_policy_name}" >/dev/null 2>&1; then
        log_warning "S3 delivery policy already exists"
    else
        aws iam create-policy \
            --policy-name "$s3_policy_name" \
            --policy-document file:///tmp/firehose-s3-policy.json
        log_success "S3 delivery policy created"
    fi
    
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${s3_policy_name}" 2>/dev/null || true
    
    # Create Lambda execution role
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
    
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" >/dev/null 2>&1; then
        log_warning "Lambda IAM role $LAMBDA_ROLE_NAME already exists"
    else
        aws iam create-role \
            --role-name "$LAMBDA_ROLE_NAME" \
            --assume-role-policy-document file:///tmp/lambda-trust-policy.json
        
        aws iam attach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        log_success "Lambda IAM role created"
    fi
    
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --query 'Role.Arn' --output text)
    
    log_success "IAM resources configured"
}

# Function to create Lambda function
create_lambda_function() {
    log_info "Creating Lambda transformation function..."
    
    # Create Lambda function code
    cat > /tmp/lambda_function.py << 'EOF'
import json
import base64
import boto3
from datetime import datetime

def lambda_handler(event, context):
    output = []
    
    for record in event['records']:
        # Decode the data
        compressed_payload = base64.b64decode(record['data'])
        uncompressed_payload = compressed_payload.decode('utf-8')
        
        try:
            # Parse JSON data
            data = json.loads(uncompressed_payload)
            
            # Transform the data - add timestamp and enrich
            transformed_data = {
                'timestamp': datetime.utcnow().isoformat(),
                'event_type': data.get('event_type', 'unknown'),
                'user_id': data.get('user_id', 'anonymous'),
                'session_id': data.get('session_id', ''),
                'page_url': data.get('page_url', ''),
                'referrer': data.get('referrer', ''),
                'user_agent': data.get('user_agent', ''),
                'ip_address': data.get('ip_address', ''),
                'processed_by': 'lambda-firehose-transform'
            }
            
            # Convert back to JSON and encode
            output_record = {
                'recordId': record['recordId'],
                'result': 'Ok',
                'data': base64.b64encode(
                    json.dumps(transformed_data).encode('utf-8')
                ).decode('utf-8')
            }
            
        except Exception as e:
            print(f"Error processing record: {e}")
            # Mark as processing failed
            output_record = {
                'recordId': record['recordId'],
                'result': 'ProcessingFailed'
            }
        
        output.append(output_record)
    
    return {'records': output}
EOF
    
    # Create deployment package
    cd /tmp && zip -q lambda-function.zip lambda_function.py
    
    # Create or update Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        log_warning "Lambda function $LAMBDA_FUNCTION_NAME already exists, updating..."
        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --zip-file fileb:///tmp/lambda-function.zip
    else
        # Wait for IAM role propagation
        log_info "Waiting for IAM role propagation..."
        sleep 10
        
        aws lambda create-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --runtime python3.9 \
            --role "$LAMBDA_ROLE_ARN" \
            --handler lambda_function.lambda_handler \
            --zip-file fileb:///tmp/lambda-function.zip \
            --timeout 300 \
            --memory-size 128
        
        log_success "Lambda function created"
    fi
    
    export LAMBDA_FUNCTION_ARN=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Configuration.FunctionArn' --output text)
    
    # Grant Firehose permission to invoke Lambda
    local lambda_policy_name="FirehoseLambdaInvokePolicy-${FIREHOSE_STREAM_NAME##*-}"
    
    cat > /tmp/firehose-lambda-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction"
      ],
      "Resource": "${LAMBDA_FUNCTION_ARN}"
    }
  ]
}
EOF
    
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${lambda_policy_name}" >/dev/null 2>&1; then
        log_warning "Lambda invoke policy already exists"
    else
        aws iam create-policy \
            --policy-name "$lambda_policy_name" \
            --policy-document file:///tmp/firehose-lambda-policy.json
        log_success "Lambda invoke policy created"
    fi
    
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${lambda_policy_name}" 2>/dev/null || true
    
    log_success "Lambda function and permissions configured"
}

# Function to create Firehose delivery stream
create_firehose_stream() {
    log_info "Creating Kinesis Data Firehose delivery stream..."
    
    if aws firehose describe-delivery-stream --delivery-stream-name "$FIREHOSE_STREAM_NAME" >/dev/null 2>&1; then
        log_warning "Firehose delivery stream $FIREHOSE_STREAM_NAME already exists"
        return 0
    fi
    
    # Create Firehose delivery stream configuration
    cat > /tmp/firehose-config.json << EOF
{
  "DeliveryStreamName": "${FIREHOSE_STREAM_NAME}",
  "DeliveryStreamType": "DirectPut",
  "S3DestinationConfiguration": {
    "RoleARN": "${FIREHOSE_ROLE_ARN}",
    "BucketARN": "arn:aws:s3:::${S3_BUCKET_NAME}",
    "Prefix": "processed-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/",
    "ErrorOutputPrefix": "error-data/",
    "BufferingHints": {
      "SizeInMBs": 5,
      "IntervalInSeconds": 300
    },
    "CompressionFormat": "GZIP",
    "ProcessingConfiguration": {
      "Enabled": true,
      "Processors": [
        {
          "Type": "Lambda",
          "Parameters": [
            {
              "ParameterName": "LambdaArn",
              "ParameterValue": "${LAMBDA_FUNCTION_ARN}"
            },
            {
              "ParameterName": "BufferSizeInMBs",
              "ParameterValue": "1"
            },
            {
              "ParameterName": "BufferIntervalInSeconds",
              "ParameterValue": "60"
            }
          ]
        }
      ]
    },
    "DataFormatConversionConfiguration": {
      "Enabled": true,
      "OutputFormatConfiguration": {
        "Serializer": {
          "ParquetSerDe": {}
        }
      },
      "SchemaConfiguration": {
        "DatabaseName": "default",
        "TableName": "streaming_etl_data",
        "RoleARN": "${FIREHOSE_ROLE_ARN}"
      }
    }
  }
}
EOF
    
    # Create delivery stream
    aws firehose create-delivery-stream \
        --cli-input-json file:///tmp/firehose-config.json
    
    log_info "Waiting for Firehose stream to be active..."
    aws firehose wait delivery-stream-exists \
        --delivery-stream-name "$FIREHOSE_STREAM_NAME"
    
    log_success "Firehose delivery stream created and active"
}

# Function to configure monitoring
configure_monitoring() {
    log_info "Configuring CloudWatch monitoring..."
    
    # Attach CloudWatch policy to Firehose role
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSKinesisFirehoseServiceRolePolicy 2>/dev/null || true
    
    # Create CloudWatch log group for Lambda
    if aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/${LAMBDA_FUNCTION_NAME}" \
        --query 'logGroups[?logGroupName==`/aws/lambda/'${LAMBDA_FUNCTION_NAME}'`]' --output text | grep -q "/aws/lambda/${LAMBDA_FUNCTION_NAME}"; then
        log_warning "CloudWatch log group already exists"
    else
        aws logs create-log-group \
            --log-group-name "/aws/lambda/${LAMBDA_FUNCTION_NAME}"
        log_success "CloudWatch log group created"
    fi
    
    log_success "Monitoring configured"
}

# Function to test the pipeline
test_pipeline() {
    log_info "Testing the streaming ETL pipeline..."
    
    # Create sample test data
    cat > /tmp/test-data.json << 'EOF'
[
  {
    "event_type": "page_view",
    "user_id": "user123",
    "session_id": "session456",
    "page_url": "https://example.com/products",
    "referrer": "https://google.com",
    "user_agent": "Mozilla/5.0",
    "ip_address": "192.168.1.1"
  },
  {
    "event_type": "click",
    "user_id": "user456",
    "session_id": "session789",
    "page_url": "https://example.com/checkout",
    "referrer": "https://example.com/cart",
    "user_agent": "Mozilla/5.0",
    "ip_address": "192.168.1.2"
  },
  {
    "event_type": "purchase",
    "user_id": "user789",
    "session_id": "session101",
    "page_url": "https://example.com/success",
    "referrer": "https://example.com/checkout",
    "user_agent": "Mozilla/5.0",
    "ip_address": "192.168.1.3"
  }
]
EOF
    
    # Send test records to Firehose
    local record_count=0
    while IFS= read -r record; do
        if [[ -n "$record" ]]; then
            local encoded_record
            encoded_record=$(echo "$record" | base64 -w 0)
            aws firehose put-record \
                --delivery-stream-name "$FIREHOSE_STREAM_NAME" \
                --record "{\"Data\":\"${encoded_record}\"}" >/dev/null
            ((record_count++))
            log_info "Test record $record_count sent"
        fi
    done < <(jq -c '.[]' /tmp/test-data.json)
    
    log_success "Test data sent to Firehose stream ($record_count records)"
    log_info "Data will be processed and delivered to S3 within 5-10 minutes"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "AWS Region: $AWS_REGION"
    echo "S3 Bucket: $S3_BUCKET_NAME"
    echo "Firehose Stream: $FIREHOSE_STREAM_NAME"
    echo "Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "Firehose Role ARN: $FIREHOSE_ROLE_ARN"
    echo "Lambda Role ARN: $LAMBDA_ROLE_ARN"
    echo
    echo "=== Next Steps ==="
    echo "1. Monitor the pipeline in the AWS Console:"
    echo "   - Firehose: https://console.aws.amazon.com/firehose/home?region=${AWS_REGION}#/details/${FIREHOSE_STREAM_NAME}"
    echo "   - Lambda: https://console.aws.amazon.com/lambda/home?region=${AWS_REGION}#/functions/${LAMBDA_FUNCTION_NAME}"
    echo "   - S3: https://console.aws.amazon.com/s3/buckets/${S3_BUCKET_NAME}"
    echo
    echo "2. Send data to the Firehose stream:"
    echo "   aws firehose put-record --delivery-stream-name ${FIREHOSE_STREAM_NAME} --record '{\"Data\":\"<base64-encoded-json>\"}'"
    echo
    echo "3. Check processed data in S3 after 5-10 minutes:"
    echo "   aws s3 ls s3://${S3_BUCKET_NAME}/processed-data/ --recursive"
    echo
    echo "To clean up resources, run: ./destroy.sh"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    rm -f /tmp/firehose-trust-policy.json /tmp/lambda-trust-policy.json
    rm -f /tmp/firehose-s3-policy.json /tmp/firehose-lambda-policy.json
    rm -f /tmp/firehose-config.json /tmp/test-data.json
    rm -f /tmp/lambda_function.py /tmp/lambda-function.zip
}

# Main deployment function
main() {
    echo "========================================"
    echo "  Streaming ETL Pipeline Deployment"
    echo "========================================"
    echo
    
    # Trap to cleanup on exit
    trap cleanup_temp_files EXIT
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_iam_resources
    create_lambda_function
    create_firehose_stream
    configure_monitoring
    test_pipeline
    display_summary
    
    log_success "Deployment script completed successfully"
}

# Run main function
main "$@"