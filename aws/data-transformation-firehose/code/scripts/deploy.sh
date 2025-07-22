#!/bin/bash
#
# Deploy script for Real-Time Data Transformation with Amazon Kinesis Data Firehose
# This script creates a fully managed real-time data processing pipeline
# with Lambda transformation and S3 delivery
#
# Usage: ./deploy.sh [--email EMAIL_ADDRESS]
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate AWS permissions for Kinesis, Lambda, S3, IAM, CloudWatch
# - Valid AWS credentials configured
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 is required but not installed"
        exit 1
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
}

# Function to generate random suffix
generate_random_suffix() {
    aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
    openssl rand -hex 3 2>/dev/null || \
    date +%s | tail -c 6
}

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    
    case $resource_type in
        "s3-bucket")
            aws s3 ls "s3://$resource_name" &>/dev/null
            ;;
        "lambda-function")
            aws lambda get-function --function-name "$resource_name" &>/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" &>/dev/null
            ;;
        "firehose-stream")
            aws firehose describe-delivery-stream --delivery-stream-name "$resource_name" &>/dev/null
            ;;
        "sns-topic")
            aws sns get-topic-attributes --topic-arn "$resource_name" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to wait for IAM role propagation
wait_for_iam_propagation() {
    local role_name=$1
    local max_attempts=30
    local attempt=1
    
    info "Waiting for IAM role propagation: $role_name"
    
    while [ $attempt -le $max_attempts ]; do
        if aws iam get-role --role-name "$role_name" &>/dev/null; then
            sleep 10  # Additional time for AWS-wide propagation
            return 0
        fi
        sleep 5
        ((attempt++))
    done
    
    error "IAM role propagation timeout: $role_name"
    return 1
}

# Function to cleanup on error
cleanup_on_error() {
    warn "Deployment failed. Cleaning up resources..."
    
    # Remove any partially created resources
    if [ -n "${LAMBDA_FUNCTION:-}" ]; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION" 2>/dev/null || true
    fi
    
    if [ -n "${LAMBDA_ROLE_NAME:-}" ]; then
        aws iam delete-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-name firehose-transform-policy 2>/dev/null || true
        aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" 2>/dev/null || true
    fi
    
    if [ -n "${FIREHOSE_ROLE_NAME:-}" ]; then
        aws iam delete-role-policy --role-name "$FIREHOSE_ROLE_NAME" --policy-name firehose-delivery-policy 2>/dev/null || true
        aws iam delete-role --role-name "$FIREHOSE_ROLE_NAME" 2>/dev/null || true
    fi
    
    # Clean up S3 buckets
    for bucket in "${RAW_BUCKET:-}" "${PROCESSED_BUCKET:-}" "${ERROR_BUCKET:-}"; do
        if [ -n "$bucket" ]; then
            aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
            aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
        fi
    done
    
    # Clean up local files
    rm -f lambda-trust-policy.json lambda-policy.json firehose-trust-policy.json firehose-policy.json
    rm -rf lambda_transform lambda_transform.zip
    
    exit 1
}

# Parse command line arguments
EMAIL_ADDRESS=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --email)
            EMAIL_ADDRESS="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--email EMAIL_ADDRESS]"
            echo "  --email EMAIL_ADDRESS  Email address for CloudWatch alarm notifications"
            echo "  -h, --help             Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Trap to cleanup on error
trap cleanup_on_error ERR

# Main deployment function
main() {
    log "Starting Kinesis Data Firehose real-time data transformation deployment"
    
    # Prerequisites check
    log "Checking prerequisites..."
    check_command "aws"
    check_command "zip"
    check_command "openssl"
    check_aws_credentials
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not configured"
        exit 1
    fi
    
    log "Using AWS region: $AWS_REGION"
    log "Using AWS account: $AWS_ACCOUNT_ID"
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(generate_random_suffix)
    
    export DELIVERY_STREAM_NAME="log-processing-stream-${RANDOM_SUFFIX}"
    export RAW_BUCKET="firehose-raw-data-${RANDOM_SUFFIX}"
    export PROCESSED_BUCKET="firehose-processed-data-${RANDOM_SUFFIX}"
    export ERROR_BUCKET="firehose-error-data-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION="firehose-transform-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="firehose-lambda-transform-role-${RANDOM_SUFFIX}"
    export FIREHOSE_ROLE_NAME="kinesis-firehose-role-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="firehose-alarms-${RANDOM_SUFFIX}"
    
    # Save configuration to file for cleanup script
    cat > .deployment_config << EOF
DELIVERY_STREAM_NAME=$DELIVERY_STREAM_NAME
RAW_BUCKET=$RAW_BUCKET
PROCESSED_BUCKET=$PROCESSED_BUCKET
ERROR_BUCKET=$ERROR_BUCKET
LAMBDA_FUNCTION=$LAMBDA_FUNCTION
LAMBDA_ROLE_NAME=$LAMBDA_ROLE_NAME
FIREHOSE_ROLE_NAME=$FIREHOSE_ROLE_NAME
SNS_TOPIC_NAME=$SNS_TOPIC_NAME
AWS_REGION=$AWS_REGION
EOF
    
    log "Configuration saved to .deployment_config"
    
    # Step 1: Create S3 buckets
    log "Creating S3 buckets..."
    
    for bucket in "$RAW_BUCKET" "$PROCESSED_BUCKET" "$ERROR_BUCKET"; do
        if resource_exists "s3-bucket" "$bucket"; then
            warn "S3 bucket $bucket already exists, skipping creation"
        else
            if [ "$AWS_REGION" = "us-east-1" ]; then
                aws s3api create-bucket --bucket "$bucket"
            else
                aws s3api create-bucket \
                    --bucket "$bucket" \
                    --region "$AWS_REGION" \
                    --create-bucket-configuration LocationConstraint="$AWS_REGION"
            fi
            log "Created S3 bucket: $bucket"
        fi
        
        # Enable bucket encryption
        aws s3api put-bucket-encryption \
            --bucket "$bucket" \
            --server-side-encryption-configuration '{
                "Rules": [
                    {
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        }
                    }
                ]
            }'
        log "Enabled encryption for bucket: $bucket"
    done
    
    # Step 2: Create Lambda function
    log "Creating Lambda function for data transformation..."
    
    # Create IAM role for Lambda
    if resource_exists "iam-role" "$LAMBDA_ROLE_NAME"; then
        warn "Lambda IAM role $LAMBDA_ROLE_NAME already exists, skipping creation"
        LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "$LAMBDA_ROLE_NAME" --query "Role.Arn" --output text)
    else
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
        
        LAMBDA_ROLE_ARN=$(aws iam create-role \
            --role-name "$LAMBDA_ROLE_NAME" \
            --assume-role-policy-document file://lambda-trust-policy.json \
            --query "Role.Arn" --output text)
        log "Created Lambda IAM role: $LAMBDA_ROLE_NAME"
        
        # Create and attach policy
        cat > lambda-policy.json << EOF
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
        "firehose:DescribeDeliveryStream",
        "firehose:ListDeliveryStreams",
        "firehose:ListTagsForDeliveryStream"
      ],
      "Resource": "*"
    },
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
        "arn:aws:s3:::$ERROR_BUCKET",
        "arn:aws:s3:::$ERROR_BUCKET/*",
        "arn:aws:s3:::$PROCESSED_BUCKET",
        "arn:aws:s3:::$PROCESSED_BUCKET/*"
      ]
    }
  ]
}
EOF
        
        aws iam put-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-name firehose-transform-policy \
            --policy-document file://lambda-policy.json
        log "Attached policy to Lambda role"
        
        wait_for_iam_propagation "$LAMBDA_ROLE_NAME"
    fi
    
    # Create Lambda function code
    if resource_exists "lambda-function" "$LAMBDA_FUNCTION"; then
        warn "Lambda function $LAMBDA_FUNCTION already exists, updating code"
        LAMBDA_ARN=$(aws lambda get-function --function-name "$LAMBDA_FUNCTION" --query "Configuration.FunctionArn" --output text)
    else
        log "Creating Lambda function code..."
        
        mkdir -p lambda_transform
        cat > lambda_transform/index.js << 'EOF'
/**
 * Kinesis Firehose Data Transformation Lambda
 * - Processes incoming log records
 * - Filters out records that don't match criteria
 * - Transforms and enriches valid records
 * - Returns both processed records and failed records
 */

// Configuration options
const config = {
    // Minimum log level to process (logs below this level will be filtered out)
    // Values: DEBUG, INFO, WARN, ERROR
    minLogLevel: 'INFO',
    
    // Whether to include timestamp in transformed data
    addProcessingTimestamp: true,
    
    // Fields to remove from logs for privacy/compliance (PII, etc.)
    fieldsToRedact: ['password', 'creditCard', 'ssn']
};

/**
 * Event structure expected in records:
 * {
 *   "timestamp": "2023-04-10T12:34:56Z",
 *   "level": "INFO|DEBUG|WARN|ERROR",
 *   "service": "service-name",
 *   "message": "Log message",
 *   // Additional fields...
 * }
 */
exports.handler = async (event, context) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    const output = {
        records: []
    };
    
    // Process each record in the batch
    for (const record of event.records) {
        console.log('Processing record:', record.recordId);
        
        try {
            // Decode and parse the record data
            const buffer = Buffer.from(record.data, 'base64');
            const decodedData = buffer.toString('utf8');
            
            // Try to parse as JSON, fail gracefully if not valid JSON
            let parsedData;
            try {
                parsedData = JSON.parse(decodedData);
            } catch (e) {
                console.error('Invalid JSON in record:', decodedData);
                
                // Mark record as processing failed
                output.records.push({
                    recordId: record.recordId,
                    result: 'ProcessingFailed',
                    data: record.data
                });
                continue;
            }
            
            // Apply filtering logic - skip records with log level below minimum
            if (parsedData.level && 
                ['DEBUG', 'INFO', 'WARN', 'ERROR'].indexOf(parsedData.level) < 
                ['DEBUG', 'INFO', 'WARN', 'ERROR'].indexOf(config.minLogLevel)) {
                
                console.log(`Filtering out record with level ${parsedData.level}`);
                
                // Mark record as dropped
                output.records.push({
                    recordId: record.recordId,
                    result: 'Dropped', 
                    data: record.data
                });
                continue;
            }
            
            // Apply transformations
            
            // Add processing metadata
            if (config.addProcessingTimestamp) {
                parsedData.processedAt = new Date().toISOString();
            }
            
            // Add AWS request ID for traceability
            parsedData.lambdaRequestId = context.awsRequestId;
            
            // Redact any sensitive fields
            for (const field of config.fieldsToRedact) {
                if (parsedData[field]) {
                    parsedData[field] = '********';
                }
            }
            
            // Convert transformed data back to string and encode as base64
            const transformedData = JSON.stringify(parsedData) + '\n';
            const encodedData = Buffer.from(transformedData).toString('base64');
            
            // Add transformed record to output
            output.records.push({
                recordId: record.recordId,
                result: 'Ok',
                data: encodedData
            });
            
        } catch (error) {
            console.error('Error processing record:', error);
            
            // Mark record as processing failed
            output.records.push({
                recordId: record.recordId,
                result: 'ProcessingFailed',
                data: record.data
            });
        }
    }
    
    console.log('Processing complete, returning', output.records.length, 'records');
    return output;
};
EOF
        
        # Package Lambda function
        cd lambda_transform
        zip -r ../lambda_transform.zip .
        cd ..
        
        # Create Lambda function
        LAMBDA_ARN=$(aws lambda create-function \
            --function-name "$LAMBDA_FUNCTION" \
            --runtime nodejs18.x \
            --handler index.handler \
            --role "$LAMBDA_ROLE_ARN" \
            --zip-file fileb://lambda_transform.zip \
            --description "Transform function for Kinesis Data Firehose" \
            --timeout 60 \
            --memory-size 256 \
            --query 'FunctionArn' --output text)
        
        log "Created Lambda function: $LAMBDA_FUNCTION"
    fi
    
    # Update Lambda function code if it already exists
    if [[ $LAMBDA_ARN == *"$LAMBDA_FUNCTION"* ]]; then
        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION" \
            --zip-file fileb://lambda_transform.zip >/dev/null
        log "Updated Lambda function code"
    fi
    
    # Step 3: Create IAM role for Firehose
    log "Creating Firehose IAM role..."
    
    if resource_exists "iam-role" "$FIREHOSE_ROLE_NAME"; then
        warn "Firehose IAM role $FIREHOSE_ROLE_NAME already exists, skipping creation"
        FIREHOSE_ROLE_ARN=$(aws iam get-role --role-name "$FIREHOSE_ROLE_NAME" --query "Role.Arn" --output text)
    else
        cat > firehose-trust-policy.json << EOF
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
        
        FIREHOSE_ROLE_ARN=$(aws iam create-role \
            --role-name "$FIREHOSE_ROLE_NAME" \
            --assume-role-policy-document file://firehose-trust-policy.json \
            --query "Role.Arn" --output text)
        log "Created Firehose IAM role: $FIREHOSE_ROLE_NAME"
        
        # Create and attach policy
        cat > firehose-policy.json << EOF
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
        "arn:aws:s3:::$RAW_BUCKET",
        "arn:aws:s3:::$RAW_BUCKET/*",
        "arn:aws:s3:::$PROCESSED_BUCKET",
        "arn:aws:s3:::$PROCESSED_BUCKET/*",
        "arn:aws:s3:::$ERROR_BUCKET",
        "arn:aws:s3:::$ERROR_BUCKET/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction",
        "lambda:GetFunctionConfiguration"
      ],
      "Resource": "$LAMBDA_ARN:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:PutLogEvents",
        "logs:CreateLogGroup",
        "logs:CreateLogStream"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kinesis:DescribeStream",
        "kinesis:GetShardIterator",
        "kinesis:GetRecords",
        "kinesis:ListShards"
      ],
      "Resource": "arn:aws:kinesis:*:*:stream/*"
    }
  ]
}
EOF
        
        aws iam put-role-policy \
            --role-name "$FIREHOSE_ROLE_NAME" \
            --policy-name firehose-delivery-policy \
            --policy-document file://firehose-policy.json
        log "Attached policy to Firehose role"
        
        wait_for_iam_propagation "$FIREHOSE_ROLE_NAME"
    fi
    
    # Step 4: Create Kinesis Data Firehose delivery stream
    log "Creating Kinesis Data Firehose delivery stream..."
    
    if resource_exists "firehose-stream" "$DELIVERY_STREAM_NAME"; then
        warn "Firehose delivery stream $DELIVERY_STREAM_NAME already exists, skipping creation"
    else
        aws firehose create-delivery-stream \
            --delivery-stream-name "$DELIVERY_STREAM_NAME" \
            --delivery-stream-type DirectPut \
            --extended-s3-destination-configuration '{
                "RoleARN": "'$FIREHOSE_ROLE_ARN'",
                "BucketARN": "arn:aws:s3:::'$PROCESSED_BUCKET'",
                "Prefix": "logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/",
                "ErrorOutputPrefix": "errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/",
                "BufferingHints": {
                    "SizeInMBs": 5,
                    "IntervalInSeconds": 60
                },
                "CompressionFormat": "GZIP",
                "S3BackupMode": "Enabled",
                "S3BackupConfiguration": {
                    "RoleARN": "'$FIREHOSE_ROLE_ARN'",
                    "BucketARN": "arn:aws:s3:::'$RAW_BUCKET'",
                    "Prefix": "raw/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/",
                    "BufferingHints": {
                        "SizeInMBs": 5,
                        "IntervalInSeconds": 60
                    },
                    "CompressionFormat": "GZIP"
                },
                "ProcessingConfiguration": {
                    "Enabled": true,
                    "Processors": [
                        {
                            "Type": "Lambda",
                            "Parameters": [
                                {
                                    "ParameterName": "LambdaArn",
                                    "ParameterValue": "'$LAMBDA_ARN':$LATEST"
                                },
                                {
                                    "ParameterName": "BufferSizeInMBs",
                                    "ParameterValue": "3"
                                },
                                {
                                    "ParameterName": "BufferIntervalInSeconds",
                                    "ParameterValue": "60"
                                }
                            ]
                        }
                    ]
                },
                "CloudWatchLoggingOptions": {
                    "Enabled": true,
                    "LogGroupName": "/aws/kinesisfirehose/'$DELIVERY_STREAM_NAME'",
                    "LogStreamName": "S3Delivery"
                }
            }'
        
        log "Created Firehose delivery stream: $DELIVERY_STREAM_NAME"
        
        # Wait for delivery stream to become active
        log "Waiting for delivery stream to become active..."
        aws firehose wait delivery-stream-active \
            --delivery-stream-name "$DELIVERY_STREAM_NAME"
        log "Delivery stream is now active"
    fi
    
    # Step 5: Create monitoring and alerting
    log "Creating monitoring and alerting..."
    
    # Create SNS topic for alarm notifications
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query 'TopicArn' --output text)
    log "Created SNS topic: $SNS_TOPIC_NAME"
    
    # Subscribe email to SNS topic if provided
    if [ -n "$EMAIL_ADDRESS" ]; then
        aws sns subscribe \
            --topic-arn "$SNS_TOPIC_ARN" \
            --protocol email \
            --notification-endpoint "$EMAIL_ADDRESS"
        log "Subscribed $EMAIL_ADDRESS to SNS topic (check email to confirm)"
    fi
    
    # Create CloudWatch alarm for delivery failures
    aws cloudwatch put-metric-alarm \
        --alarm-name "FirehoseDeliveryFailure-$DELIVERY_STREAM_NAME" \
        --metric-name "DeliveryToS3.DataFreshness" \
        --namespace "AWS/Kinesis/Firehose" \
        --statistic Maximum \
        --period 300 \
        --evaluation-periods 1 \
        --threshold 900 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=DeliveryStreamName,Value="$DELIVERY_STREAM_NAME" \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --ok-actions "$SNS_TOPIC_ARN" \
        --alarm-description "Alarm when Firehose records are not delivered to S3 within 15 minutes"
    
    log "Created CloudWatch alarm for delivery failures"
    
    # Update configuration file with SNS topic ARN
    echo "SNS_TOPIC_ARN=$SNS_TOPIC_ARN" >> .deployment_config
    
    # Clean up temporary files
    rm -f lambda-trust-policy.json lambda-policy.json firehose-trust-policy.json firehose-policy.json
    rm -rf lambda_transform lambda_transform.zip
    
    log "Deployment completed successfully!"
    echo ""
    echo "===== DEPLOYMENT SUMMARY ====="
    echo "Firehose Delivery Stream: $DELIVERY_STREAM_NAME"
    echo "Raw Data Bucket: $RAW_BUCKET"
    echo "Processed Data Bucket: $PROCESSED_BUCKET"
    echo "Error Data Bucket: $ERROR_BUCKET"
    echo "Lambda Function: $LAMBDA_FUNCTION"
    echo "SNS Topic: $SNS_TOPIC_NAME"
    echo ""
    echo "To test the pipeline, send data to the Firehose stream:"
    echo "aws firehose put-record --delivery-stream-name $DELIVERY_STREAM_NAME --record Data=\$(echo '{\"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"level\": \"INFO\", \"service\": \"test-service\", \"message\": \"Test message\"}' | base64)"
    echo ""
    echo "To clean up all resources, run: ./destroy.sh"
}

# Run main function
main "$@"