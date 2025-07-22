#!/bin/bash

# Deploy script for Real-Time Data Processing with Kinesis Data Firehose
# This script deploys the complete infrastructure for streaming data processing

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
    fi
    
    # Check if zip is installed
    if ! command -v zip &> /dev/null; then
        error "zip is not installed. Please install it first."
    fi
    
    # Check required permissions
    info "Checking AWS permissions..."
    
    # Test basic permissions
    if ! aws iam get-user &> /dev/null && ! aws iam get-role --role-name "$(aws sts get-caller-identity --query Arn --output text | cut -d/ -f2)" &> /dev/null; then
        warn "Unable to verify IAM permissions. Proceeding with deployment..."
    fi
    
    log "Prerequisites check completed successfully"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "No region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Export resource names
    export FIREHOSE_STREAM_NAME="realtime-data-stream-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="firehose-data-bucket-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="firehose-transform-${RANDOM_SUFFIX}"
    export OPENSEARCH_DOMAIN="firehose-search-${RANDOM_SUFFIX}"
    export REDSHIFT_CLUSTER="firehose-warehouse-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="FirehoseDeliveryRole-${RANDOM_SUFFIX}"
    
    log "Environment variables initialized"
    info "S3 Bucket: ${S3_BUCKET_NAME}"
    info "Firehose Stream: ${FIREHOSE_STREAM_NAME}"
    info "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    info "OpenSearch Domain: ${OPENSEARCH_DOMAIN}"
    info "IAM Role: ${IAM_ROLE_NAME}"
}

# Create S3 bucket and directory structure
create_s3_bucket() {
    log "Creating S3 bucket and directory structure..."
    
    # Create S3 bucket
    if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
        warn "S3 bucket ${S3_BUCKET_NAME} already exists"
    else
        aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}"
        log "Created S3 bucket: ${S3_BUCKET_NAME}"
    fi
    
    # Create directory structure
    aws s3api put-object --bucket "${S3_BUCKET_NAME}" --key "raw-data/" --body /dev/null
    aws s3api put-object --bucket "${S3_BUCKET_NAME}" --key "transformed-data/" --body /dev/null
    aws s3api put-object --bucket "${S3_BUCKET_NAME}" --key "error-data/" --body /dev/null
    aws s3api put-object --bucket "${S3_BUCKET_NAME}" --key "opensearch-backup/" --body /dev/null
    
    log "S3 directory structure created"
}

# Create IAM role for Kinesis Data Firehose
create_iam_role() {
    log "Creating IAM role for Kinesis Data Firehose..."
    
    # Create trust policy
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
    
    # Create the IAM role
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        warn "IAM role ${IAM_ROLE_NAME} already exists"
    else
        aws iam create-role \
            --role-name "${IAM_ROLE_NAME}" \
            --assume-role-policy-document file:///tmp/firehose-trust-policy.json
        log "Created IAM role: ${IAM_ROLE_NAME}"
    fi
    
    # Create permissions policy
    cat > /tmp/firehose-permissions-policy.json << EOF
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
        },
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction",
                "lambda:GetFunctionConfiguration"
            ],
            "Resource": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "es:DescribeElasticsearchDomain",
                "es:DescribeElasticsearchDomains",
                "es:DescribeElasticsearchDomainConfig",
                "es:ESHttpPost",
                "es:ESHttpPut"
            ],
            "Resource": "arn:aws:es:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${OPENSEARCH_DOMAIN}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:*"
        }
    ]
}
EOF
    
    # Attach permissions policy to the role
    aws iam put-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-name "FirehoseDeliveryPolicy" \
        --policy-document file:///tmp/firehose-permissions-policy.json
    
    # Get the role ARN
    export FIREHOSE_ROLE_ARN=$(aws iam get-role \
        --role-name "${IAM_ROLE_NAME}" \
        --query Role.Arn --output text)
    
    log "IAM role configured with ARN: ${FIREHOSE_ROLE_ARN}"
}

# Create Lambda function for data transformation
create_lambda_function() {
    log "Creating Lambda function for data transformation..."
    
    # Create Lambda function code
    cat > /tmp/transform_function.py << 'EOF'
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
            
            # Add timestamp and processing metadata
            data['processed_timestamp'] = datetime.utcnow().isoformat()
            data['processing_status'] = 'SUCCESS'
            
            # Enrich data with additional fields
            if 'user_id' in data:
                data['user_category'] = 'registered' if data['user_id'] else 'guest'
            
            if 'amount' in data:
                data['amount_category'] = 'high' if float(data['amount']) > 100 else 'low'
            
            # Convert back to JSON
            transformed_data = json.dumps(data) + '\n'
            
            output_record = {
                'recordId': record['recordId'],
                'result': 'Ok',
                'data': base64.b64encode(transformed_data.encode('utf-8')).decode('utf-8')
            }
            
        except Exception as e:
            # Handle transformation errors
            error_data = {
                'recordId': record['recordId'],
                'error': str(e),
                'original_data': uncompressed_payload,
                'timestamp': datetime.utcnow().isoformat()
            }
            
            output_record = {
                'recordId': record['recordId'],
                'result': 'ProcessingFailed',
                'data': base64.b64encode(json.dumps(error_data).encode('utf-8')).decode('utf-8')
            }
        
        output.append(output_record)
    
    return {'records': output}
EOF
    
    # Create deployment package
    cd /tmp
    zip transform_function.zip transform_function.py
    
    # Create Lambda execution role if it doesn't exist
    if ! aws iam get-role --role-name "lambda-execution-role-${RANDOM_SUFFIX}" &>/dev/null; then
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
        
        aws iam create-role \
            --role-name "lambda-execution-role-${RANDOM_SUFFIX}" \
            --assume-role-policy-document file:///tmp/lambda-trust-policy.json
        
        aws iam attach-role-policy \
            --role-name "lambda-execution-role-${RANDOM_SUFFIX}" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        
        # Wait for role to be available
        sleep 10
    fi
    
    # Create Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
        warn "Lambda function ${LAMBDA_FUNCTION_NAME} already exists"
    else
        aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda-execution-role-${RANDOM_SUFFIX}" \
            --handler transform_function.lambda_handler \
            --zip-file fileb://transform_function.zip \
            --timeout 300 \
            --memory-size 128
        
        log "Created Lambda function: ${LAMBDA_FUNCTION_NAME}"
    fi
    
    # Get Lambda function ARN
    export LAMBDA_FUNCTION_ARN=$(aws lambda get-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --query Configuration.FunctionArn --output text)
    
    log "Lambda function ARN: ${LAMBDA_FUNCTION_ARN}"
}

# Create OpenSearch domain
create_opensearch_domain() {
    log "Creating OpenSearch domain..."
    
    # Check if domain already exists
    if aws opensearch describe-domain --domain-name "${OPENSEARCH_DOMAIN}" &>/dev/null; then
        warn "OpenSearch domain ${OPENSEARCH_DOMAIN} already exists"
    else
        aws opensearch create-domain \
            --domain-name "${OPENSEARCH_DOMAIN}" \
            --engine-version OpenSearch_1.3 \
            --cluster-config InstanceType=t3.small.search,InstanceCount=1 \
            --ebs-options EBSEnabled=true,VolumeType=gp2,VolumeSize=20 \
            --access-policies '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "AWS": "arn:aws:iam::'${AWS_ACCOUNT_ID}':root"
                        },
                        "Action": "es:*",
                        "Resource": "arn:aws:es:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':domain/'${OPENSEARCH_DOMAIN}'/*"
                    }
                ]
            }' \
            --domain-endpoint-options EnforceHTTPS=true
        
        log "Created OpenSearch domain: ${OPENSEARCH_DOMAIN}"
    fi
    
    # Wait for domain to be active
    log "Waiting for OpenSearch domain to be active..."
    aws opensearch wait domain-available --domain-name "${OPENSEARCH_DOMAIN}"
    
    # Get domain endpoint
    export OPENSEARCH_ENDPOINT=$(aws opensearch describe-domain \
        --domain-name "${OPENSEARCH_DOMAIN}" \
        --query DomainStatus.Endpoint --output text)
    
    log "OpenSearch domain endpoint: ${OPENSEARCH_ENDPOINT}"
}

# Create Kinesis Data Firehose delivery streams
create_firehose_streams() {
    log "Creating Kinesis Data Firehose delivery streams..."
    
    # Create S3 delivery stream configuration
    cat > /tmp/firehose-s3-config.json << EOF
{
    "DeliveryStreamName": "${FIREHOSE_STREAM_NAME}",
    "DeliveryStreamType": "DirectPut",
    "S3DestinationConfiguration": {
        "RoleARN": "${FIREHOSE_ROLE_ARN}",
        "BucketARN": "arn:aws:s3:::${S3_BUCKET_NAME}",
        "Prefix": "transformed-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/",
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
        "DataFormatConversionConfiguration": {
            "Enabled": true,
            "OutputFormatConfiguration": {
                "Serializer": {
                    "ParquetSerDe": {}
                }
            }
        },
        "CloudWatchLoggingOptions": {
            "Enabled": true,
            "LogGroupName": "/aws/kinesisfirehose/${FIREHOSE_STREAM_NAME}",
            "LogStreamName": "S3Delivery"
        }
    }
}
EOF
    
    # Create S3 delivery stream
    if aws firehose describe-delivery-stream --delivery-stream-name "${FIREHOSE_STREAM_NAME}" &>/dev/null; then
        warn "Firehose delivery stream ${FIREHOSE_STREAM_NAME} already exists"
    else
        aws firehose create-delivery-stream --cli-input-json file:///tmp/firehose-s3-config.json
        log "Created S3 delivery stream: ${FIREHOSE_STREAM_NAME}"
    fi
    
    # Wait for S3 stream to be active
    log "Waiting for S3 delivery stream to be active..."
    aws firehose wait delivery-stream-ready --delivery-stream-name "${FIREHOSE_STREAM_NAME}"
    
    # Create OpenSearch delivery stream configuration
    cat > /tmp/firehose-opensearch-config.json << EOF
{
    "DeliveryStreamName": "${FIREHOSE_STREAM_NAME}-opensearch",
    "DeliveryStreamType": "DirectPut",
    "OpenSearchDestinationConfiguration": {
        "RoleARN": "${FIREHOSE_ROLE_ARN}",
        "DomainARN": "arn:aws:es:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${OPENSEARCH_DOMAIN}",
        "IndexName": "realtime-events",
        "TypeName": "_doc",
        "IndexRotationPeriod": "OneDay",
        "BufferingHints": {
            "SizeInMBs": 1,
            "IntervalInSeconds": 60
        },
        "RetryOptions": {
            "DurationInSeconds": 3600
        },
        "S3BackupMode": "AllDocuments",
        "S3Configuration": {
            "RoleARN": "${FIREHOSE_ROLE_ARN}",
            "BucketARN": "arn:aws:s3:::${S3_BUCKET_NAME}",
            "Prefix": "opensearch-backup/",
            "BufferingHints": {
                "SizeInMBs": 5,
                "IntervalInSeconds": 300
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
                            "ParameterValue": "${LAMBDA_FUNCTION_ARN}"
                        }
                    ]
                }
            ]
        },
        "CloudWatchLoggingOptions": {
            "Enabled": true,
            "LogGroupName": "/aws/kinesisfirehose/${FIREHOSE_STREAM_NAME}-opensearch",
            "LogStreamName": "OpenSearchDelivery"
        }
    }
}
EOF
    
    # Create OpenSearch delivery stream
    if aws firehose describe-delivery-stream --delivery-stream-name "${FIREHOSE_STREAM_NAME}-opensearch" &>/dev/null; then
        warn "OpenSearch delivery stream ${FIREHOSE_STREAM_NAME}-opensearch already exists"
    else
        aws firehose create-delivery-stream --cli-input-json file:///tmp/firehose-opensearch-config.json
        log "Created OpenSearch delivery stream: ${FIREHOSE_STREAM_NAME}-opensearch"
    fi
    
    # Wait for OpenSearch stream to be active
    log "Waiting for OpenSearch delivery stream to be active..."
    aws firehose wait delivery-stream-ready --delivery-stream-name "${FIREHOSE_STREAM_NAME}-opensearch"
    
    log "Both Firehose delivery streams are active"
}

# Create CloudWatch monitoring and alarms
create_monitoring() {
    log "Creating CloudWatch monitoring and alarms..."
    
    # Create CloudWatch alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "${FIREHOSE_STREAM_NAME}-DeliveryErrors" \
        --alarm-description "Monitor Firehose delivery errors" \
        --metric-name "DeliveryToS3.Records" \
        --namespace "AWS/KinesisFirehose" \
        --statistic Sum \
        --period 300 \
        --threshold 0 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=DeliveryStreamName,Value="${FIREHOSE_STREAM_NAME}" \
        --evaluation-periods 2 \
        --treat-missing-data notBreaching
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "${LAMBDA_FUNCTION_NAME}-Errors" \
        --alarm-description "Monitor Lambda transformation errors" \
        --metric-name "Errors" \
        --namespace "AWS/Lambda" \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=FunctionName,Value="${LAMBDA_FUNCTION_NAME}" \
        --evaluation-periods 2 \
        --treat-missing-data notBreaching
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "${FIREHOSE_STREAM_NAME}-OpenSearchErrors" \
        --alarm-description "Monitor OpenSearch delivery errors" \
        --metric-name "DeliveryToOpenSearch.Records" \
        --namespace "AWS/KinesisFirehose" \
        --statistic Sum \
        --period 300 \
        --threshold 0 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=DeliveryStreamName,Value="${FIREHOSE_STREAM_NAME}-opensearch" \
        --evaluation-periods 2 \
        --treat-missing-data notBreaching
    
    log "Created CloudWatch monitoring alarms"
}

# Create error handling infrastructure
create_error_handling() {
    log "Creating error handling infrastructure..."
    
    # Create SQS queue for failed records
    aws sqs create-queue \
        --queue-name "${FIREHOSE_STREAM_NAME}-dlq" \
        --attributes VisibilityTimeoutSeconds=300,MessageRetentionPeriod=1209600
    
    # Get SQS queue URL
    export DLQ_URL=$(aws sqs get-queue-url \
        --queue-name "${FIREHOSE_STREAM_NAME}-dlq" \
        --query QueueUrl --output text)
    
    log "Created dead letter queue: ${DLQ_URL}"
}

# Test the deployment
test_deployment() {
    log "Testing deployment with sample data..."
    
    # Create sample data
    cat > /tmp/sample-events.json << 'EOF'
[
    {
        "event_id": "evt001",
        "user_id": "user123",
        "event_type": "purchase",
        "amount": 150.50,
        "product_id": "prod456",
        "timestamp": "2024-01-15T10:30:00Z"
    },
    {
        "event_id": "evt002",
        "user_id": "user456",
        "event_type": "view",
        "product_id": "prod789",
        "timestamp": "2024-01-15T10:31:00Z"
    }
]
EOF
    
    # Send test data to Firehose
    for event in $(jq -c '.[]' /tmp/sample-events.json); do
        aws firehose put-record \
            --delivery-stream-name "${FIREHOSE_STREAM_NAME}" \
            --record Data="$(echo $event | base64)" > /dev/null
    done
    
    for event in $(jq -c '.[]' /tmp/sample-events.json); do
        aws firehose put-record \
            --delivery-stream-name "${FIREHOSE_STREAM_NAME}-opensearch" \
            --record Data="$(echo $event | base64)" > /dev/null
    done
    
    log "Sent test data to Firehose streams"
    info "Test data will be processed and delivered to S3 and OpenSearch"
    info "Check S3 bucket in 5-10 minutes: s3://${S3_BUCKET_NAME}/transformed-data/"
    info "Check OpenSearch endpoint: https://${OPENSEARCH_ENDPOINT}/_cat/indices"
}

# Save deployment configuration
save_deployment_config() {
    log "Saving deployment configuration..."
    
    cat > /tmp/deployment-config.json << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "firehose_stream_name": "${FIREHOSE_STREAM_NAME}",
    "s3_bucket_name": "${S3_BUCKET_NAME}",
    "lambda_function_name": "${LAMBDA_FUNCTION_NAME}",
    "opensearch_domain": "${OPENSEARCH_DOMAIN}",
    "iam_role_name": "${IAM_ROLE_NAME}",
    "opensearch_endpoint": "${OPENSEARCH_ENDPOINT}",
    "firehose_role_arn": "${FIREHOSE_ROLE_ARN}",
    "lambda_function_arn": "${LAMBDA_FUNCTION_ARN}",
    "dlq_url": "${DLQ_URL}"
}
EOF
    
    # Copy config to current directory
    cp /tmp/deployment-config.json ./firehose-deployment-config.json
    
    log "Deployment configuration saved to: firehose-deployment-config.json"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f /tmp/firehose-trust-policy.json
    rm -f /tmp/firehose-permissions-policy.json
    rm -f /tmp/firehose-s3-config.json
    rm -f /tmp/firehose-opensearch-config.json
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/transform_function.py
    rm -f /tmp/transform_function.zip
    rm -f /tmp/sample-events.json
    rm -f /tmp/deployment-config.json
    
    log "Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting deployment of Real-Time Data Processing with Kinesis Data Firehose"
    
    # Check if this is a retry or fresh deployment
    if [ -f "./firehose-deployment-config.json" ]; then
        warn "Found existing deployment configuration."
        echo "This may be a retry or update. Proceeding with deployment..."
    fi
    
    # Run deployment steps
    check_prerequisites
    initialize_environment
    create_s3_bucket
    create_iam_role
    create_lambda_function
    create_opensearch_domain
    create_firehose_streams
    create_monitoring
    create_error_handling
    test_deployment
    save_deployment_config
    cleanup_temp_files
    
    log "Deployment completed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "S3 Bucket: ${S3_BUCKET_NAME}"
    echo "Firehose Stream (S3): ${FIREHOSE_STREAM_NAME}"
    echo "Firehose Stream (OpenSearch): ${FIREHOSE_STREAM_NAME}-opensearch"
    echo "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "OpenSearch Domain: ${OPENSEARCH_DOMAIN}"
    echo "OpenSearch Endpoint: https://${OPENSEARCH_ENDPOINT}"
    echo "IAM Role: ${IAM_ROLE_NAME}"
    echo "Dead Letter Queue: ${DLQ_URL}"
    echo ""
    echo "Configuration saved to: firehose-deployment-config.json"
    echo ""
    echo "Next steps:"
    echo "1. Monitor CloudWatch logs for data processing"
    echo "2. Check S3 bucket for transformed data files"
    echo "3. Verify OpenSearch indices are created"
    echo "4. Set up additional monitoring and alerting as needed"
    echo ""
    warn "Remember to run destroy.sh to clean up resources when done testing"
}

# Run main function
main "$@"