#!/bin/bash

#################################################################################
# Real-Time Stream Enrichment with Kinesis Data Firehose and EventBridge Pipes
# Deployment Script
#################################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_ROOT/deployment.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Cleanup function for failed deployments
cleanup_on_error() {
    print_error "Deployment failed. Cleaning up resources..."
    
    # Call cleanup script if it exists
    if [ -f "$SCRIPT_DIR/destroy.sh" ]; then
        bash "$SCRIPT_DIR/destroy.sh" --force
    fi
    
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

#################################################################################
# Prerequisites Check
#################################################################################

check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version | cut -d/ -f2 | cut -d' ' -f1)
    print_status "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions (basic test)
    CALLER_IDENTITY=$(aws sts get-caller-identity)
    ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
    USER_ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn')
    
    print_status "Deploying as: $USER_ARN"
    print_status "Account ID: $ACCOUNT_ID"
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install jq for JSON parsing."
        exit 1
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        print_error "zip command not found. Please install zip utility."
        exit 1
    fi
    
    print_success "Prerequisites check completed successfully"
}

#################################################################################
# Environment Setup
#################################################################################

setup_environment() {
    print_status "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        print_warning "No default region set. Using us-east-1"
        export AWS_REGION="us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    # Export resource names
    export BUCKET_NAME="stream-enrichment-${RANDOM_SUFFIX}"
    export STREAM_NAME="raw-events-${RANDOM_SUFFIX}"
    export FIREHOSE_NAME="event-ingestion-${RANDOM_SUFFIX}"
    export TABLE_NAME="reference-data-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="enrich-events-${RANDOM_SUFFIX}"
    export PIPE_NAME="enrichment-pipe-${RANDOM_SUFFIX}"
    
    # Save configuration for cleanup
    cat > "$PROJECT_ROOT/.deployment-config" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
RANDOM_SUFFIX=$RANDOM_SUFFIX
BUCKET_NAME=$BUCKET_NAME
STREAM_NAME=$STREAM_NAME
FIREHOSE_NAME=$FIREHOSE_NAME
TABLE_NAME=$TABLE_NAME
FUNCTION_NAME=$FUNCTION_NAME
PIPE_NAME=$PIPE_NAME
EOF
    
    print_success "Environment prepared with suffix: $RANDOM_SUFFIX"
    log "Configuration saved to $PROJECT_ROOT/.deployment-config"
}

#################################################################################
# S3 Bucket Creation
#################################################################################

create_s3_bucket() {
    print_status "Creating S3 bucket for data storage..."
    
    # Create S3 bucket with proper region handling
    if [ "$AWS_REGION" == "us-east-1" ]; then
        aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"
    fi
    
    # Enable versioning for data protection
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Apply bucket encryption
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    print_success "S3 bucket created: s3://${BUCKET_NAME}"
}

#################################################################################
# DynamoDB Table Creation
#################################################################################

create_dynamodb_table() {
    print_status "Creating DynamoDB table for reference data..."
    
    # Create DynamoDB table
    aws dynamodb create-table \
        --table-name "$TABLE_NAME" \
        --attribute-definitions \
            AttributeName=productId,AttributeType=S \
        --key-schema \
            AttributeName=productId,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION" \
        --tags '[
            {
                "Key": "Project",
                "Value": "StreamEnrichment"
            },
            {
                "Key": "Environment",
                "Value": "Demo"
            }
        ]'
    
    # Wait for table to be active
    print_status "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists \
        --table-name "$TABLE_NAME" \
        --region "$AWS_REGION"
    
    # Add sample reference data
    print_status "Adding sample reference data..."
    
    aws dynamodb put-item \
        --table-name "$TABLE_NAME" \
        --item '{
            "productId": {"S": "PROD-001"},
            "productName": {"S": "Smart Sensor"},
            "category": {"S": "IoT Devices"},
            "price": {"N": "49.99"}
        }' \
        --region "$AWS_REGION"
    
    aws dynamodb put-item \
        --table-name "$TABLE_NAME" \
        --item '{
            "productId": {"S": "PROD-002"},
            "productName": {"S": "Temperature Monitor"},
            "category": {"S": "IoT Devices"},
            "price": {"N": "79.99"}
        }' \
        --region "$AWS_REGION"
    
    aws dynamodb put-item \
        --table-name "$TABLE_NAME" \
        --item '{
            "productId": {"S": "PROD-003"},
            "productName": {"S": "Humidity Sensor"},
            "category": {"S": "IoT Devices"},
            "price": {"N": "65.50"}
        }' \
        --region "$AWS_REGION"
    
    print_success "DynamoDB table created with reference data: $TABLE_NAME"
}

#################################################################################
# Kinesis Data Stream Creation
#################################################################################

create_kinesis_stream() {
    print_status "Creating Kinesis Data Stream..."
    
    # Create Kinesis Data Stream with on-demand mode
    aws kinesis create-stream \
        --stream-name "$STREAM_NAME" \
        --stream-mode-details StreamMode=ON_DEMAND \
        --region "$AWS_REGION" \
        --tags Project=StreamEnrichment,Environment=Demo
    
    # Wait for stream to be active
    print_status "Waiting for Kinesis Data Stream to become active..."
    aws kinesis wait stream-exists \
        --stream-name "$STREAM_NAME" \
        --region "$AWS_REGION"
    
    # Get stream ARN for later use
    STREAM_ARN=$(aws kinesis describe-stream \
        --stream-name "$STREAM_NAME" \
        --query 'StreamDescription.StreamARN' \
        --output text)
    
    # Save stream ARN to config
    echo "STREAM_ARN=$STREAM_ARN" >> "$PROJECT_ROOT/.deployment-config"
    
    print_success "Kinesis Data Stream created: $STREAM_ARN"
}

#################################################################################
# Lambda Function Creation
#################################################################################

create_lambda_function() {
    print_status "Creating Lambda function for event enrichment..."
    
    # Create Lambda execution role
    LAMBDA_ROLE_NAME="lambda-enrichment-role-${RANDOM_SUFFIX}"
    
    LAMBDA_ROLE_ARN=$(aws iam create-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "lambda.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        --tags '[
            {
                "Key": "Project",
                "Value": "StreamEnrichment"
            },
            {
                "Key": "Environment",
                "Value": "Demo"
            }
        ]' \
        --query 'Role.Arn' --output text)
    
    # Attach basic execution role policy
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create and attach DynamoDB read policy
    aws iam put-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-name DynamoDBReadPolicy \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Action": [
                    "dynamodb:GetItem",
                    "dynamodb:Query",
                    "dynamodb:BatchGetItem"
                ],
                "Resource": "arn:aws:dynamodb:'"$AWS_REGION"':'"$AWS_ACCOUNT_ID"':table/'"$TABLE_NAME"'"
            }]
        }'
    
    # Create Lambda function code
    print_status "Creating Lambda function code..."
    
    cat > "$PROJECT_ROOT/lambda_function.py" << 'EOF'
import json
import base64
import boto3
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    """
    Lambda function to enrich streaming events with reference data from DynamoDB.
    
    Args:
        event: List of records from EventBridge Pipes
        context: Lambda context object
        
    Returns:
        List of enriched records
    """
    enriched_records = []
    
    logger.info(f"Processing {len(event)} records")
    
    for record in event:
        try:
            # Decode Kinesis data
            if 'data' in record:
                # Data from Kinesis is base64 encoded
                payload = json.loads(
                    base64.b64decode(record['data']).decode('utf-8')
                )
            else:
                # Direct payload
                payload = record
            
            logger.info(f"Processing record: {payload.get('eventId', 'unknown')}")
            
            # Lookup product details if productId is present
            product_id = payload.get('productId')
            if product_id:
                try:
                    response = table.get_item(
                        Key={'productId': product_id}
                    )
                    
                    if 'Item' in response:
                        # Enrich the payload with product information
                        item = response['Item']
                        payload['productName'] = item['productName']
                        payload['category'] = item['category']
                        payload['price'] = float(item['price'])
                        payload['enrichmentTimestamp'] = datetime.utcnow().isoformat()
                        payload['enrichmentStatus'] = 'success'
                        
                        logger.info(f"Successfully enriched record for product {product_id}")
                    else:
                        payload['enrichmentStatus'] = 'product_not_found'
                        payload['enrichmentTimestamp'] = datetime.utcnow().isoformat()
                        
                        logger.warning(f"Product not found: {product_id}")
                        
                except Exception as e:
                    payload['enrichmentStatus'] = 'error'
                    payload['enrichmentError'] = str(e)
                    payload['enrichmentTimestamp'] = datetime.utcnow().isoformat()
                    
                    logger.error(f"Error enriching record: {str(e)}")
            else:
                payload['enrichmentStatus'] = 'no_product_id'
                payload['enrichmentTimestamp'] = datetime.utcnow().isoformat()
                
                logger.warning("No productId found in record")
            
            # Add processing metadata
            payload['processingTimestamp'] = datetime.utcnow().isoformat()
            payload['processedBy'] = context.function_name
            
            enriched_records.append(payload)
            
        except Exception as e:
            logger.error(f"Error processing record: {str(e)}")
            # Add error record for debugging
            error_record = {
                'error': str(e),
                'originalRecord': record,
                'enrichmentStatus': 'processing_error',
                'enrichmentTimestamp': datetime.utcnow().isoformat()
            }
            enriched_records.append(error_record)
    
    logger.info(f"Successfully processed {len(enriched_records)} records")
    return enriched_records
EOF
    
    # Package Lambda function
    cd "$PROJECT_ROOT"
    zip -q function.zip lambda_function.py
    
    # Wait for IAM role propagation
    print_status "Waiting for IAM role propagation..."
    sleep 15
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$FUNCTION_NAME" \
        --runtime python3.11 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://function.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables="{TABLE_NAME=$TABLE_NAME}" \
        --description "Event enrichment function for real-time streaming pipeline" \
        --tags Project=StreamEnrichment,Environment=Demo \
        --region "$AWS_REGION"
    
    # Wait for function to be active
    print_status "Waiting for Lambda function to become active..."
    aws lambda wait function-active \
        --function-name "$FUNCTION_NAME" \
        --region "$AWS_REGION"
    
    # Get Lambda function ARN
    LAMBDA_ARN=$(aws lambda get-function \
        --function-name "$FUNCTION_NAME" \
        --query 'Configuration.FunctionArn' \
        --output text)
    
    # Save Lambda ARN to config
    echo "LAMBDA_ARN=$LAMBDA_ARN" >> "$PROJECT_ROOT/.deployment-config"
    echo "LAMBDA_ROLE_NAME=$LAMBDA_ROLE_NAME" >> "$PROJECT_ROOT/.deployment-config"
    
    print_success "Lambda function created: $LAMBDA_ARN"
}

#################################################################################
# IAM Role for EventBridge Pipes
#################################################################################

create_pipes_role() {
    print_status "Creating IAM role for EventBridge Pipes..."
    
    PIPES_ROLE_NAME="pipes-execution-role-${RANDOM_SUFFIX}"
    
    # Create EventBridge Pipes execution role
    PIPES_ROLE_ARN=$(aws iam create-role \
        --role-name "$PIPES_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "pipes.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        --tags '[
            {
                "Key": "Project",
                "Value": "StreamEnrichment"
            },
            {
                "Key": "Environment",
                "Value": "Demo"
            }
        ]' \
        --query 'Role.Arn' --output text)
    
    # Create comprehensive policy for Pipes
    aws iam put-role-policy \
        --role-name "$PIPES_ROLE_NAME" \
        --policy-name PipesExecutionPolicy \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "kinesis:DescribeStream",
                        "kinesis:GetRecords",
                        "kinesis:GetShardIterator",
                        "kinesis:ListStreams",
                        "kinesis:SubscribeToShard"
                    ],
                    "Resource": "arn:aws:kinesis:'"$AWS_REGION"':'"$AWS_ACCOUNT_ID"':stream/'"$STREAM_NAME"'"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "lambda:InvokeFunction"
                    ],
                    "Resource": "'"$LAMBDA_ARN"'"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents"
                    ],
                    "Resource": "arn:aws:logs:'"$AWS_REGION"':'"$AWS_ACCOUNT_ID"':*"
                }
            ]
        }'
    
    # Save Pipes role info to config
    echo "PIPES_ROLE_NAME=$PIPES_ROLE_NAME" >> "$PROJECT_ROOT/.deployment-config"
    echo "PIPES_ROLE_ARN=$PIPES_ROLE_ARN" >> "$PROJECT_ROOT/.deployment-config"
    
    print_success "EventBridge Pipes IAM role created: $PIPES_ROLE_ARN"
}

#################################################################################
# Kinesis Data Firehose Creation
#################################################################################

create_firehose_stream() {
    print_status "Creating Kinesis Data Firehose delivery stream..."
    
    FIREHOSE_ROLE_NAME="firehose-delivery-role-${RANDOM_SUFFIX}"
    
    # Create IAM role for Firehose
    FIREHOSE_ROLE_ARN=$(aws iam create-role \
        --role-name "$FIREHOSE_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "firehose.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        --tags '[
            {
                "Key": "Project",
                "Value": "StreamEnrichment"
            },
            {
                "Key": "Environment",
                "Value": "Demo"
            }
        ]' \
        --query 'Role.Arn' --output text)
    
    # Attach S3 permissions to Firehose role
    aws iam put-role-policy \
        --role-name "$FIREHOSE_ROLE_NAME" \
        --policy-name FirehoseDeliveryPolicy \
        --policy-document '{
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
                        "arn:aws:s3:::'"$BUCKET_NAME"'",
                        "arn:aws:s3:::'"$BUCKET_NAME"'/*"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents"
                    ],
                    "Resource": "arn:aws:logs:'"$AWS_REGION"':'"$AWS_ACCOUNT_ID"':*"
                }
            ]
        }'
    
    # Wait for IAM role propagation
    print_status "Waiting for IAM role propagation..."
    sleep 15
    
    # Create Kinesis Data Firehose delivery stream
    aws firehose create-delivery-stream \
        --delivery-stream-name "$FIREHOSE_NAME" \
        --delivery-stream-type DirectPut \
        --extended-s3-destination-configuration '{
            "RoleARN": "'"$FIREHOSE_ROLE_ARN"'",
            "BucketARN": "arn:aws:s3:::'"$BUCKET_NAME"'",
            "Prefix": "enriched-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/",
            "ErrorOutputPrefix": "error-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/",
            "CompressionFormat": "GZIP",
            "BufferingHints": {
                "SizeInMBs": 5,
                "IntervalInSeconds": 300
            },
            "DataFormatConversionConfiguration": {
                "Enabled": false
            },
            "CloudWatchLoggingOptions": {
                "Enabled": true,
                "LogGroupName": "/aws/kinesisfirehose/'"$FIREHOSE_NAME"'"
            }
        }' \
        --tags '[
            {
                "Key": "Project",
                "Value": "StreamEnrichment"
            },
            {
                "Key": "Environment",
                "Value": "Demo"
            }
        ]' \
        --region "$AWS_REGION"
    
    # Wait for Firehose to be active
    print_status "Waiting for Kinesis Data Firehose to become active..."
    sleep 30
    
    # Get Firehose ARN
    FIREHOSE_ARN=$(aws firehose describe-delivery-stream \
        --delivery-stream-name "$FIREHOSE_NAME" \
        --query 'DeliveryStreamDescription.DeliveryStreamARN' \
        --output text)
    
    # Update Pipes role to include Firehose permissions
    aws iam put-role-policy \
        --role-name "$PIPES_ROLE_NAME" \
        --policy-name FirehoseTargetPolicy \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Action": [
                    "firehose:PutRecord",
                    "firehose:PutRecordBatch"
                ],
                "Resource": "'"$FIREHOSE_ARN"'"
            }]
        }'
    
    # Save Firehose info to config
    echo "FIREHOSE_ROLE_NAME=$FIREHOSE_ROLE_NAME" >> "$PROJECT_ROOT/.deployment-config"
    echo "FIREHOSE_ARN=$FIREHOSE_ARN" >> "$PROJECT_ROOT/.deployment-config"
    
    print_success "Kinesis Data Firehose created: $FIREHOSE_ARN"
}

#################################################################################
# EventBridge Pipe Creation (Note: May require manual setup)
#################################################################################

create_eventbridge_pipe() {
    print_status "Creating EventBridge Pipe for stream enrichment..."
    
    print_warning "EventBridge Pipes CLI support may be limited in some regions."
    print_warning "If this step fails, you can create the pipe manually in the AWS Console."
    
    # Attempt to create EventBridge Pipe
    # Note: This API might not be available in all regions or CLI versions
    cat > "$PROJECT_ROOT/pipe-config.json" << EOF
{
    "Name": "$PIPE_NAME",
    "RoleArn": "$PIPES_ROLE_ARN",
    "Source": "$STREAM_ARN",
    "SourceParameters": {
        "KinesisStreamParameters": {
            "StartingPosition": "LATEST",
            "BatchSize": 10,
            "MaximumBatchingWindowInSeconds": 5
        }
    },
    "Enrichment": "$LAMBDA_ARN",
    "Target": "$FIREHOSE_ARN",
    "TargetParameters": {
        "KinesisFirehoseParameters": {
            "PartitionKey": "$.productId"
        }
    },
    "Tags": {
        "Project": "StreamEnrichment",
        "Environment": "Demo"
    }
}
EOF
    
    # Try to create the pipe
    if aws pipes create-pipe \
        --cli-input-json file://"$PROJECT_ROOT/pipe-config.json" \
        --region "$AWS_REGION" 2>/dev/null; then
        print_success "EventBridge Pipe created successfully: $PIPE_NAME"
    else
        print_warning "Failed to create EventBridge Pipe via CLI."
        print_warning "Please create the pipe manually using the AWS Console with the following configuration:"
        echo "Pipe Name: $PIPE_NAME"
        echo "Source: $STREAM_ARN"
        echo "Enrichment: $LAMBDA_ARN"
        echo "Target: $FIREHOSE_ARN"
        echo "Role: $PIPES_ROLE_ARN"
        echo ""
        print_warning "Pipe configuration saved to: $PROJECT_ROOT/pipe-config.json"
    fi
}

#################################################################################
# Test Data Generation
#################################################################################

generate_test_data() {
    print_status "Sending test events to the pipeline..."
    
    # Wait for all services to be ready
    sleep 10
    
    # Send test events to Kinesis Data Stream
    for i in {1..5}; do
        PRODUCT_ID="PROD-00$((RANDOM % 3 + 1))"
        EVENT_ID="evt-$(date +%s)-$i"
        QUANTITY=$((RANDOM % 10 + 1))
        TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        
        TEST_EVENT="{\"eventId\":\"$EVENT_ID\",\"productId\":\"$PRODUCT_ID\",\"quantity\":$QUANTITY,\"timestamp\":\"$TIMESTAMP\",\"source\":\"test-generator\"}"
        
        aws kinesis put-record \
            --stream-name "$STREAM_NAME" \
            --data "$(echo "$TEST_EVENT" | base64)" \
            --partition-key "$PRODUCT_ID" \
            --region "$AWS_REGION" >/dev/null
        
        print_status "Sent test event $i: $EVENT_ID"
        sleep 1
    done
    
    # Send one event with an unknown product ID for error testing
    UNKNOWN_EVENT="{\"eventId\":\"evt-unknown-$(date +%s)\",\"productId\":\"PROD-999\",\"quantity\":1,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"source\":\"error-test\"}"
    
    aws kinesis put-record \
        --stream-name "$STREAM_NAME" \
        --data "$(echo "$UNKNOWN_EVENT" | base64)" \
        --partition-key "PROD-999" \
        --region "$AWS_REGION" >/dev/null
    
    print_success "Test events sent to the pipeline"
    print_status "Events will be processed and delivered to S3 within a few minutes"
}

#################################################################################
# Deployment Validation
#################################################################################

validate_deployment() {
    print_status "Validating deployment..."
    
    # Check Lambda function
    if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        print_success "Lambda function is accessible"
    else
        print_error "Lambda function validation failed"
        return 1
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        print_success "DynamoDB table is accessible"
    else
        print_error "DynamoDB table validation failed"
        return 1
    fi
    
    # Check Kinesis stream
    if aws kinesis describe-stream --stream-name "$STREAM_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        print_success "Kinesis Data Stream is accessible"
    else
        print_error "Kinesis Data Stream validation failed"
        return 1
    fi
    
    # Check Firehose delivery stream
    if aws firehose describe-delivery-stream --delivery-stream-name "$FIREHOSE_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        print_success "Kinesis Data Firehose is accessible"
    else
        print_error "Kinesis Data Firehose validation failed"
        return 1
    fi
    
    # Check S3 bucket
    if aws s3 ls "s3://$BUCKET_NAME" >/dev/null 2>&1; then
        print_success "S3 bucket is accessible"
    else
        print_error "S3 bucket validation failed"
        return 1
    fi
    
    print_success "All resources validated successfully"
}

#################################################################################
# Main Deployment Function
#################################################################################

main() {
    echo "=========================================="
    echo "Real-Time Stream Enrichment Deployment"
    echo "=========================================="
    echo
    
    # Initialize log file
    log "Starting deployment at $(date)"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_dynamodb_table
    create_kinesis_stream
    create_lambda_function
    create_pipes_role
    create_firehose_stream
    create_eventbridge_pipe
    generate_test_data
    validate_deployment
    
    # Cleanup temporary files
    rm -f "$PROJECT_ROOT/function.zip" "$PROJECT_ROOT/lambda_function.py" "$PROJECT_ROOT/pipe-config.json"
    
    echo
    echo "=========================================="
    echo "Deployment Completed Successfully!"
    echo "=========================================="
    echo
    print_success "Resources created:"
    echo "  - S3 Bucket: s3://$BUCKET_NAME"
    echo "  - DynamoDB Table: $TABLE_NAME"
    echo "  - Kinesis Stream: $STREAM_NAME"
    echo "  - Lambda Function: $FUNCTION_NAME"
    echo "  - Firehose Stream: $FIREHOSE_NAME"
    echo "  - EventBridge Pipe: $PIPE_NAME (may require manual setup)"
    echo
    print_status "Configuration saved to: $PROJECT_ROOT/.deployment-config"
    print_status "Logs saved to: $LOG_FILE"
    echo
    print_status "Monitor the pipeline:"
    echo "  - Check Lambda logs: aws logs tail /aws/lambda/$FUNCTION_NAME --follow"
    echo "  - Check S3 for enriched data: aws s3 ls s3://$BUCKET_NAME/enriched-data/ --recursive"
    echo "  - CloudWatch metrics for monitoring performance"
    echo
    print_warning "Remember to run destroy.sh when done to avoid ongoing charges!"
    
    log "Deployment completed successfully at $(date)"
}

# Run main function
main "$@"