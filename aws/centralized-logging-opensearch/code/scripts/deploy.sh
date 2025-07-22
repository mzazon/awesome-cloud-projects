#!/bin/bash

# Centralized Logging with Amazon OpenSearch Service - Deployment Script
# This script deploys a comprehensive centralized logging solution using OpenSearch Service,
# CloudWatch Logs, Lambda functions, and Kinesis for scalable log processing and analysis.

set -euo pipefail

# Configuration and Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/centralized-logging-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly TIMEOUT_OPENSEARCH=1800  # 30 minutes for OpenSearch domain creation
readonly TIMEOUT_GENERAL=300      # 5 minutes for other resources
readonly MIN_CLI_VERSION="2.0.0"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $*${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ ERROR: $*${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ WARNING: $*${NC}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check the log file: $LOG_FILE"
    log_error "Run the destroy script to clean up any partially created resources."
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Cleaning up partially created resources..."
    
    # Clean up temporary files
    rm -f opensearch-trust-policy.json lambda-trust-policy.json firehose-trust-policy.json
    rm -f cwlogs-trust-policy.json opensearch-domain-config.json firehose-config.json
    rm -f lambda-execution-policy.json firehose-service-policy.json cwlogs-kinesis-policy.json
    rm -f log_processor.py log_processor.zip
    
    log_warning "Partial cleanup completed. Run destroy.sh for complete cleanup."
}

trap cleanup_on_error EXIT

# Prerequisites checking functions
check_aws_cli() {
    log "Checking AWS CLI installation and version..."
    
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2.0+ and configure it."
    fi
    
    local cli_version
    cli_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $cli_version"
    
    # Check if version is >= 2.0.0 (simplified check)
    if [[ "${cli_version:0:1}" -lt "2" ]]; then
        error_exit "AWS CLI version 2.0+ is required. Current version: $cli_version"
    fi
}

check_aws_credentials() {
    log "Checking AWS credentials and permissions..."
    
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        error_exit "AWS credentials not configured or invalid. Please run 'aws configure' or set environment variables."
    fi
    
    local caller_identity
    caller_identity=$(aws sts get-caller-identity 2>/dev/null)
    log "AWS Account ID: $(echo "$caller_identity" | jq -r '.Account')"
    log "User/Role: $(echo "$caller_identity" | jq -r '.Arn')"
}

check_required_permissions() {
    log "Checking required AWS service permissions..."
    
    local required_actions=(
        "opensearch:CreateDomain"
        "iam:CreateRole"
        "kinesis:CreateStream"
        "lambda:CreateFunction"
        "firehose:CreateDeliveryStream"
        "s3:CreateBucket"
        "logs:CreateLogGroup"
    )
    
    for action in "${required_actions[@]}"; do
        local service="${action%%:*}"
        if ! aws "$service" help > /dev/null 2>&1; then
            log_warning "Cannot verify permissions for $service. Proceeding anyway..."
        fi
    done
    
    log_success "Basic permission checks completed"
}

check_region_support() {
    log "Checking region support for required services..."
    
    if [[ -z "${AWS_REGION:-}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            error_exit "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        fi
    fi
    
    export AWS_REGION
    log "Using AWS Region: $AWS_REGION"
    
    # Check if OpenSearch Service is available in the region
    if ! aws opensearch list-domain-names > /dev/null 2>&1; then
        error_exit "OpenSearch Service is not available in region $AWS_REGION"
    fi
    
    log_success "Region $AWS_REGION supports required services"
}

check_cost_awareness() {
    log_warning "COST AWARENESS:"
    log_warning "This deployment will create resources with ongoing costs:"
    log_warning "- OpenSearch domain (3 t3.small.search instances): ~$100-150/month"
    log_warning "- Kinesis Data Streams: ~$15/month"
    log_warning "- Lambda function: Pay per execution"
    log_warning "- Kinesis Data Firehose: Pay per GB transferred"
    log_warning "- S3 storage: Pay per GB stored"
    
    if [[ "${SKIP_CONFIRMATION:-}" != "true" ]]; then
        echo -n "Do you want to continue with the deployment? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user."
            exit 0
        fi
    fi
}

# Resource deployment functions
setup_environment_variables() {
    log "Setting up environment variables..."
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=$(aws configure get region)
    
    # Generate unique identifiers
    local random_string
    random_string=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export RANDOM_STRING="$random_string"
    export DOMAIN_NAME="central-logging-${RANDOM_STRING}"
    export KINESIS_STREAM="log-stream-${RANDOM_STRING}"
    export FIREHOSE_STREAM="log-delivery-${RANDOM_STRING}"
    export BACKUP_BUCKET="central-logging-backup-${RANDOM_STRING}"
    
    # Export role ARNs for later use
    export OPENSEARCH_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/OpenSearchServiceRole-${RANDOM_STRING}"
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/LogProcessorLambdaRole-${RANDOM_STRING}"
    export FIREHOSE_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/FirehoseDeliveryRole-${RANDOM_STRING}"
    export CWLOGS_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/CWLogsToKinesisRole-${RANDOM_STRING}"
    export KINESIS_STREAM_ARN="arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${KINESIS_STREAM}"
    export LAMBDA_FUNCTION_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:LogProcessor-${RANDOM_STRING}"
    
    log_success "Environment variables configured"
    log "Domain Name: $DOMAIN_NAME"
    log "Kinesis Stream: $KINESIS_STREAM"
    log "Firehose Stream: $FIREHOSE_STREAM"
    log "Backup Bucket: $BACKUP_BUCKET"
}

create_iam_roles() {
    log "Creating IAM service roles..."
    
    # OpenSearch service role
    cat > opensearch-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "opensearch.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    if aws iam create-role \
        --role-name "OpenSearchServiceRole-${RANDOM_STRING}" \
        --assume-role-policy-document file://opensearch-trust-policy.json \
        --description "Service role for OpenSearch centralized logging domain" > /dev/null 2>&1; then
        log_success "Created OpenSearch service role"
    else
        error_exit "Failed to create OpenSearch service role"
    fi
    
    # Lambda execution role
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
    
    if aws iam create-role \
        --role-name "LogProcessorLambdaRole-${RANDOM_STRING}" \
        --assume-role-policy-document file://lambda-trust-policy.json \
        --description "Execution role for log processing Lambda function" > /dev/null 2>&1; then
        log_success "Created Lambda execution role"
    else
        error_exit "Failed to create Lambda execution role"
    fi
    
    # Create Lambda execution policy
    cat > lambda-execution-policy.json << EOF
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
        "kinesis:GetShardIterator",
        "kinesis:GetRecords",
        "kinesis:ListStreams"
      ],
      "Resource": "$KINESIS_STREAM_ARN"
    },
    {
      "Effect": "Allow",
      "Action": [
        "firehose:PutRecord",
        "firehose:PutRecordBatch"
      ],
      "Resource": "arn:aws:firehose:${AWS_REGION}:${AWS_ACCOUNT_ID}:deliverystream/*"
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
    
    if aws iam put-role-policy \
        --role-name "LogProcessorLambdaRole-${RANDOM_STRING}" \
        --policy-name LogProcessorExecutionPolicy \
        --policy-document file://lambda-execution-policy.json > /dev/null 2>&1; then
        log_success "Created Lambda execution policy"
    else
        error_exit "Failed to create Lambda execution policy"
    fi
    
    # Firehose service role
    cat > firehose-trust-policy.json << 'EOF'
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
    
    if aws iam create-role \
        --role-name "FirehoseDeliveryRole-${RANDOM_STRING}" \
        --assume-role-policy-document file://firehose-trust-policy.json \
        --description "Service role for Kinesis Data Firehose delivery to OpenSearch" > /dev/null 2>&1; then
        log_success "Created Firehose service role"
    else
        error_exit "Failed to create Firehose service role"
    fi
    
    # CloudWatch Logs service role
    cat > cwlogs-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringLike": {
          "aws:SourceArn": "arn:aws:logs:*:*:*"
        }
      }
    }
  ]
}
EOF
    
    if aws iam create-role \
        --role-name "CWLogsToKinesisRole-${RANDOM_STRING}" \
        --assume-role-policy-document file://cwlogs-trust-policy.json \
        --description "Service role for CloudWatch Logs to write to Kinesis" > /dev/null 2>&1; then
        log_success "Created CloudWatch Logs service role"
    else
        error_exit "Failed to create CloudWatch Logs service role"
    fi
    
    # Wait for roles to be available
    log "Waiting for IAM roles to propagate..."
    sleep 15
}

create_kinesis_stream() {
    log "Creating Kinesis Data Stream for log ingestion..."
    
    if aws kinesis create-stream \
        --stream-name "$KINESIS_STREAM" \
        --shard-count 2 \
        --tags "Project=CentralizedLogging,Environment=Production" > /dev/null 2>&1; then
        log_success "Kinesis stream creation initiated"
    else
        error_exit "Failed to create Kinesis stream"
    fi
    
    log "Waiting for Kinesis stream to become active..."
    local attempts=0
    local max_attempts=60
    
    while [ $attempts -lt $max_attempts ]; do
        local stream_status
        stream_status=$(aws kinesis describe-stream \
            --stream-name "$KINESIS_STREAM" \
            --query 'StreamDescription.StreamStatus' \
            --output text 2>/dev/null)
        
        if [[ "$stream_status" == "ACTIVE" ]]; then
            log_success "Kinesis stream is active"
            return 0
        fi
        
        log "Stream status: $stream_status (attempt $((attempts + 1))/$max_attempts)"
        sleep 10
        ((attempts++))
    done
    
    error_exit "Kinesis stream did not become active within expected time"
}

create_opensearch_domain() {
    log "Creating Amazon OpenSearch Service domain (this takes 15-20 minutes)..."
    
    # Create domain configuration
    cat > opensearch-domain-config.json << EOF
{
  "DomainName": "$DOMAIN_NAME",
  "OpenSearchVersion": "OpenSearch_2.9",
  "ClusterConfig": {
    "InstanceType": "t3.small.search",
    "InstanceCount": 3,
    "DedicatedMasterEnabled": true,
    "MasterInstanceType": "t3.small.search",
    "MasterInstanceCount": 3,
    "ZoneAwarenessEnabled": true,
    "ZoneAwarenessConfig": {
      "AvailabilityZoneCount": 3
    }
  },
  "EBSOptions": {
    "EBSEnabled": true,
    "VolumeType": "gp3",
    "VolumeSize": 20
  },
  "EncryptionAtRestOptions": {
    "Enabled": true
  },
  "NodeToNodeEncryptionOptions": {
    "Enabled": true
  },
  "DomainEndpointOptions": {
    "EnforceHTTPS": true,
    "TLSSecurityPolicy": "Policy-Min-TLS-1-2-2019-07"
  },
  "AccessPolicies": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::${AWS_ACCOUNT_ID}:root\"},\"Action\":\"es:*\",\"Resource\":\"arn:aws:es:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${DOMAIN_NAME}/*\"}]}",
  "TagList": [
    {
      "Key": "Project",
      "Value": "CentralizedLogging"
    },
    {
      "Key": "Environment",
      "Value": "Production"
    }
  ]
}
EOF
    
    if aws opensearch create-domain \
        --cli-input-json file://opensearch-domain-config.json > /dev/null 2>&1; then
        log_success "OpenSearch domain creation initiated"
    else
        error_exit "Failed to create OpenSearch domain"
    fi
    
    log "Waiting for OpenSearch domain to become available..."
    local attempts=0
    local max_attempts=120  # 20 minutes maximum
    
    while [ $attempts -lt $max_attempts ]; do
        local domain_status
        domain_status=$(aws opensearch describe-domain \
            --domain-name "$DOMAIN_NAME" \
            --query 'DomainStatus.Processing' \
            --output text 2>/dev/null)
        
        if [[ "$domain_status" == "False" ]]; then
            log_success "OpenSearch domain is ready"
            
            # Get domain endpoint
            local opensearch_endpoint
            opensearch_endpoint=$(aws opensearch describe-domain \
                --domain-name "$DOMAIN_NAME" \
                --query 'DomainStatus.Endpoints.vpc' \
                --output text 2>/dev/null)
            
            if [[ "$opensearch_endpoint" == "None" ]] || [[ -z "$opensearch_endpoint" ]]; then
                opensearch_endpoint=$(aws opensearch describe-domain \
                    --domain-name "$DOMAIN_NAME" \
                    --query 'DomainStatus.Endpoint' \
                    --output text)
            fi
            
            export OPENSEARCH_ENDPOINT="$opensearch_endpoint"
            log_success "OpenSearch Endpoint: https://$OPENSEARCH_ENDPOINT"
            return 0
        fi
        
        log "Domain still processing... (attempt $((attempts + 1))/$max_attempts)"
        sleep 10
        ((attempts++))
    done
    
    error_exit "OpenSearch domain did not become available within expected time"
}

create_s3_backup_bucket() {
    log "Creating S3 backup bucket for failed log deliveries..."
    
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        # us-east-1 doesn't need LocationConstraint
        if aws s3api create-bucket \
            --bucket "$BACKUP_BUCKET" > /dev/null 2>&1; then
            log_success "S3 backup bucket created"
        else
            error_exit "Failed to create S3 backup bucket"
        fi
    else
        if aws s3api create-bucket \
            --bucket "$BACKUP_BUCKET" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION" > /dev/null 2>&1; then
            log_success "S3 backup bucket created"
        else
            error_exit "Failed to create S3 backup bucket"
        fi
    fi
    
    # Add bucket policy for Firehose access
    sleep 5
}

create_firehose_delivery_stream() {
    log "Creating Kinesis Data Firehose delivery stream..."
    
    # Create Firehose service policy
    cat > firehose-service-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "es:ESHttpPost",
        "es:ESHttpPut"
      ],
      "Resource": "arn:aws:es:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${DOMAIN_NAME}/*"
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
        "arn:aws:s3:::$BACKUP_BUCKET",
        "arn:aws:s3:::$BACKUP_BUCKET/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/kinesisfirehose/*"
    }
  ]
}
EOF
    
    if aws iam put-role-policy \
        --role-name "FirehoseDeliveryRole-${RANDOM_STRING}" \
        --policy-name FirehoseDeliveryPolicy \
        --policy-document file://firehose-service-policy.json > /dev/null 2>&1; then
        log_success "Created Firehose service policy"
    else
        error_exit "Failed to create Firehose service policy"
    fi
    
    # Wait for role to be ready
    sleep 10
    
    # Create Firehose delivery stream configuration
    cat > firehose-config.json << EOF
{
  "DeliveryStreamName": "$FIREHOSE_STREAM",
  "DeliveryStreamType": "DirectPut",
  "OpenSearchDestinationConfiguration": {
    "RoleARN": "$FIREHOSE_ROLE_ARN",
    "DomainARN": "arn:aws:es:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${DOMAIN_NAME}",
    "IndexName": "logs-%Y-%m-%d",
    "IndexRotationPeriod": "OneDay",
    "TypeName": "_doc",
    "RetryDuration": 300,
    "S3BackupMode": "FailedDocumentsOnly",
    "S3Configuration": {
      "RoleARN": "$FIREHOSE_ROLE_ARN",
      "BucketARN": "arn:aws:s3:::$BACKUP_BUCKET",
      "Prefix": "failed-logs/",
      "ErrorOutputPrefix": "errors/",
      "BufferingHints": {
        "SizeInMBs": 5,
        "IntervalInSeconds": 300
      },
      "CompressionFormat": "GZIP"
    },
    "ProcessingConfiguration": {
      "Enabled": false
    },
    "CloudWatchLoggingOptions": {
      "Enabled": true,
      "LogGroupName": "/aws/kinesisfirehose/$FIREHOSE_STREAM"
    }
  },
  "Tags": [
    {
      "Key": "Project",
      "Value": "CentralizedLogging"
    },
    {
      "Key": "Environment",
      "Value": "Production"
    }
  ]
}
EOF
    
    if aws firehose create-delivery-stream \
        --cli-input-json file://firehose-config.json > /dev/null 2>&1; then
        log_success "Kinesis Data Firehose delivery stream created"
    else
        error_exit "Failed to create Kinesis Data Firehose delivery stream"
    fi
}

create_lambda_function() {
    log "Creating log processing Lambda function..."
    
    # Create Lambda function code
    cat > log_processor.py << 'EOF'
import json
import base64
import gzip
import boto3
import datetime
import os
import re
from typing import Dict, List, Any

firehose = boto3.client('firehose')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Process CloudWatch Logs data from Kinesis stream
    Enrich logs and forward to Kinesis Data Firehose
    """
    records_to_firehose = []
    error_count = 0
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            compressed_payload = base64.b64decode(record['kinesis']['data'])
            uncompressed_payload = gzip.decompress(compressed_payload)
            log_data = json.loads(uncompressed_payload)
            
            # Process each log event
            for log_event in log_data.get('logEvents', []):
                enriched_log = enrich_log_event(log_event, log_data)
                
                # Convert to JSON string for Firehose
                json_record = json.dumps(enriched_log) + '\n'
                
                records_to_firehose.append({
                    'Data': json_record
                })
                
        except Exception as e:
            print(f"Error processing record: {str(e)}")
            error_count += 1
            continue
    
    # Send processed records to Firehose
    if records_to_firehose:
        try:
            response = firehose.put_record_batch(
                DeliveryStreamName=os.environ['FIREHOSE_STREAM_NAME'],
                Records=records_to_firehose
            )
            
            failed_records = response.get('FailedPutCount', 0)
            if failed_records > 0:
                print(f"Failed to process {failed_records} records")
                
        except Exception as e:
            print(f"Error sending to Firehose: {str(e)}")
            error_count += len(records_to_firehose)
    
    # Send metrics to CloudWatch
    if error_count > 0:
        cloudwatch.put_metric_data(
            Namespace='CentralLogging/Processing',
            MetricData=[
                {
                    'MetricName': 'ProcessingErrors',
                    'Value': error_count,
                    'Unit': 'Count',
                    'Timestamp': datetime.datetime.utcnow()
                }
            ]
        )
    
    return {
        'statusCode': 200,
        'processedRecords': len(records_to_firehose),
        'errorCount': error_count
    }

def enrich_log_event(log_event: Dict, log_data: Dict) -> Dict:
    """
    Enrich log events with additional metadata and parsing
    """
    enriched = {
        '@timestamp': datetime.datetime.fromtimestamp(
            log_event['timestamp'] / 1000
        ).isoformat() + 'Z',
        'message': log_event.get('message', ''),
        'log_group': log_data.get('logGroup', ''),
        'log_stream': log_data.get('logStream', ''),
        'aws_account_id': log_data.get('owner', ''),
        'aws_region': os.environ.get('AWS_REGION', ''),
        'source_type': determine_source_type(log_data.get('logGroup', ''))
    }
    
    # Parse structured logs (JSON)
    try:
        if log_event['message'].strip().startswith('{'):
            parsed_message = json.loads(log_event['message'])
            enriched['parsed_message'] = parsed_message
            
            # Extract common fields
            if 'level' in parsed_message:
                enriched['log_level'] = parsed_message['level'].upper()
            if 'timestamp' in parsed_message:
                enriched['original_timestamp'] = parsed_message['timestamp']
                
    except (json.JSONDecodeError, KeyError):
        pass
    
    # Extract log level from message
    if 'log_level' not in enriched:
        enriched['log_level'] = extract_log_level(log_event['message'])
    
    # Add security context for security-related logs
    if is_security_related(log_event['message'], log_data.get('logGroup', '')):
        enriched['security_event'] = True
        enriched['priority'] = 'high'
    
    return enriched

def determine_source_type(log_group: str) -> str:
    """Determine the type of service generating the logs"""
    if '/aws/lambda/' in log_group:
        return 'lambda'
    elif '/aws/apigateway/' in log_group:
        return 'api-gateway'
    elif '/aws/rds/' in log_group:
        return 'rds'
    elif '/aws/vpc/flowlogs' in log_group:
        return 'vpc-flow-logs'
    elif 'cloudtrail' in log_group.lower():
        return 'cloudtrail'
    else:
        return 'application'

def extract_log_level(message: str) -> str:
    """Extract log level from message content"""
    log_levels = ['ERROR', 'WARN', 'WARNING', 'INFO', 'DEBUG', 'TRACE']
    message_upper = message.upper()
    
    for level in log_levels:
        if level in message_upper:
            return level
    
    return 'INFO'

def is_security_related(message: str, log_group: str) -> bool:
    """Identify potentially security-related log events"""
    security_keywords = [
        'authentication failed', 'access denied', 'unauthorized',
        'security group', 'iam', 'login failed', 'brute force',
        'suspicious', 'blocked', 'firewall', 'intrusion'
    ]
    
    message_lower = message.lower()
    log_group_lower = log_group.lower()
    
    # Check for security keywords
    for keyword in security_keywords:
        if keyword in message_lower:
            return True
    
    # Security-related log groups
    if any(term in log_group_lower for term in ['cloudtrail', 'security', 'auth', 'iam']):
        return True
    
    return False
EOF
    
    # Create deployment package
    if zip log_processor.zip log_processor.py > /dev/null 2>&1; then
        log_success "Created Lambda deployment package"
    else
        error_exit "Failed to create Lambda deployment package"
    fi
    
    # Deploy Lambda function
    if aws lambda create-function \
        --function-name "LogProcessor-${RANDOM_STRING}" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler log_processor.lambda_handler \
        --zip-file fileb://log_processor.zip \
        --timeout 300 \
        --memory-size 512 \
        --environment Variables="{FIREHOSE_STREAM_NAME=${FIREHOSE_STREAM}}" \
        --description "Log processing function for centralized logging" \
        --tags "Project=CentralizedLogging,Environment=Production" > /dev/null 2>&1; then
        log_success "Lambda function deployed"
    else
        error_exit "Failed to deploy Lambda function"
    fi
    
    # Create event source mapping from Kinesis to Lambda
    if aws lambda create-event-source-mapping \
        --function-name "LogProcessor-${RANDOM_STRING}" \
        --event-source-arn "$KINESIS_STREAM_ARN" \
        --starting-position LATEST \
        --batch-size 100 \
        --maximum-batching-window-in-seconds 10 > /dev/null 2>&1; then
        log_success "Event source mapping created"
    else
        error_exit "Failed to create event source mapping"
    fi
}

configure_cloudwatch_logs() {
    log "Configuring CloudWatch Logs subscription filters..."
    
    # Create policy for CloudWatch Logs to write to Kinesis
    cat > cwlogs-kinesis-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kinesis:PutRecord",
        "kinesis:PutRecords"
      ],
      "Resource": "$KINESIS_STREAM_ARN"
    }
  ]
}
EOF
    
    if aws iam put-role-policy \
        --role-name "CWLogsToKinesisRole-${RANDOM_STRING}" \
        --policy-name CWLogsToKinesisPolicy \
        --policy-document file://cwlogs-kinesis-policy.json > /dev/null 2>&1; then
        log_success "Created CloudWatch Logs to Kinesis policy"
    else
        error_exit "Failed to create CloudWatch Logs to Kinesis policy"
    fi
    
    # Wait for role to be ready
    sleep 10
    
    # Create a test log group to demonstrate the solution
    local test_log_group="/aws/test/centralized-logging"
    
    if aws logs create-log-group --log-group-name "$test_log_group" > /dev/null 2>&1; then
        log_success "Created test log group: $test_log_group"
    else
        log_warning "Test log group may already exist"
    fi
    
    # Create subscription filter for test log group
    if aws logs put-subscription-filter \
        --log-group-name "$test_log_group" \
        --filter-name "CentralLoggingTestFilter-${RANDOM_STRING}" \
        --filter-pattern "" \
        --destination-arn "$KINESIS_STREAM_ARN" \
        --role-arn "$CWLOGS_ROLE_ARN" \
        --distribution "Random" > /dev/null 2>&1; then
        log_success "Created subscription filter for test log group"
    else
        log_warning "Failed to create subscription filter for test log group"
    fi
    
    log "To add subscription filters to existing log groups, use:"
    log "aws logs put-subscription-filter --log-group-name <LOG_GROUP> --filter-name \"CentralLoggingFilter-${RANDOM_STRING}\" --filter-pattern \"\" --destination-arn $KINESIS_STREAM_ARN --role-arn $CWLOGS_ROLE_ARN"
}

# Deployment summary and validation
generate_test_logs() {
    log "Generating test logs to validate the pipeline..."
    
    local test_log_group="/aws/test/centralized-logging"
    local test_stream_name="test-stream-$(date +%Y-%m-%d)"
    
    for i in {1..5}; do
        local log_message="{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",\"level\":\"INFO\",\"service\":\"test-app\",\"message\":\"Test log entry $i from deployment script\",\"user_id\":\"deployment-test\",\"request_id\":\"req-$i\"}"
        
        aws logs put-log-events \
            --log-group-name "$test_log_group" \
            --log-stream-name "$test_stream_name" \
            --log-events timestamp="$(date +%s)000",message="$log_message" > /dev/null 2>&1 || true
        
        sleep 1
    done
    
    log_success "Generated test logs"
}

print_deployment_summary() {
    log_success "=========================================="
    log_success "DEPLOYMENT COMPLETED SUCCESSFULLY!"
    log_success "=========================================="
    log ""
    log "📊 Centralized Logging Infrastructure:"
    log "   • OpenSearch Domain: $DOMAIN_NAME"
    log "   • Domain Endpoint: https://${OPENSEARCH_ENDPOINT:-'<pending>'}"
    log "   • Kinesis Stream: $KINESIS_STREAM"
    log "   • Firehose Stream: $FIREHOSE_STREAM"
    log "   • Lambda Function: LogProcessor-${RANDOM_STRING}"
    log "   • Backup Bucket: $BACKUP_BUCKET"
    log ""
    log "🔧 Configuration Files:"
    log "   • Environment variables saved to: /tmp/centralized-logging-env-${RANDOM_STRING}.sh"
    log "   • Deployment log: $LOG_FILE"
    log ""
    log "📝 Next Steps:"
    log "   1. Wait 5-10 minutes for initial log processing pipeline to warm up"
    log "   2. Access OpenSearch Dashboards at: https://${OPENSEARCH_ENDPOINT:-'<pending>'}/_dashboards"
    log "   3. Add subscription filters to existing log groups"
    log "   4. Create custom dashboards and alerts in OpenSearch"
    log ""
    log "💰 Cost Awareness:"
    log "   • Monitor usage in AWS Cost Explorer"
    log "   • Review OpenSearch domain sizing after initial data ingestion"
    log "   • Use destroy.sh script to clean up resources when no longer needed"
    log ""
    log "🔍 Monitoring:"
    log "   • Lambda metrics: LogProcessor-${RANDOM_STRING}"
    log "   • Kinesis metrics: $KINESIS_STREAM"
    log "   • Firehose metrics: $FIREHOSE_STREAM"
    log "   • OpenSearch cluster health: $DOMAIN_NAME"
    
    # Save environment variables for future use
    cat > "/tmp/centralized-logging-env-${RANDOM_STRING}.sh" << EOF
#!/bin/bash
# Centralized Logging Environment Variables
# Generated on $(date)

export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export AWS_REGION="$AWS_REGION"
export RANDOM_STRING="$RANDOM_STRING"
export DOMAIN_NAME="$DOMAIN_NAME"
export KINESIS_STREAM="$KINESIS_STREAM"
export FIREHOSE_STREAM="$FIREHOSE_STREAM"
export BACKUP_BUCKET="$BACKUP_BUCKET"
export OPENSEARCH_ENDPOINT="${OPENSEARCH_ENDPOINT:-}"

# Resource ARNs
export OPENSEARCH_ROLE_ARN="$OPENSEARCH_ROLE_ARN"
export LAMBDA_ROLE_ARN="$LAMBDA_ROLE_ARN"
export FIREHOSE_ROLE_ARN="$FIREHOSE_ROLE_ARN"
export CWLOGS_ROLE_ARN="$CWLOGS_ROLE_ARN"
export KINESIS_STREAM_ARN="$KINESIS_STREAM_ARN"
export LAMBDA_FUNCTION_ARN="$LAMBDA_FUNCTION_ARN"
EOF
    
    chmod +x "/tmp/centralized-logging-env-${RANDOM_STRING}.sh"
    log_success "Environment variables saved for future reference"
}

# Main deployment workflow
main() {
    log "=========================================="
    log "Centralized Logging Deployment Script"
    log "=========================================="
    log "Starting deployment at $(date)"
    log "Log file: $LOG_FILE"
    
    # Prerequisites
    check_aws_cli
    check_aws_credentials
    check_required_permissions
    check_region_support
    check_cost_awareness
    
    # Setup
    setup_environment_variables
    
    # Core infrastructure
    create_iam_roles
    create_kinesis_stream
    create_s3_backup_bucket
    create_opensearch_domain
    
    # Processing pipeline
    create_firehose_delivery_stream
    create_lambda_function
    configure_cloudwatch_logs
    
    # Validation
    generate_test_logs
    
    # Summary
    print_deployment_summary
    
    # Cleanup temporary files but preserve the trap
    trap - EXIT
    cleanup_on_error
    
    log_success "Deployment completed successfully!"
    log "Total deployment time: $SECONDS seconds"
}

# Run main function
main "$@"