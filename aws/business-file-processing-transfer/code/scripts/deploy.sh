#!/bin/bash

# AWS Transfer Family and Step Functions File Processing Pipeline Deployment Script
# This script deploys the complete infrastructure for automated business file processing
# Author: Recipe Generator
# Version: 1.0

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
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

# Function to check if AWS CLI is installed and configured
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI installation
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: ${AWS_CLI_VERSION}"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check required permissions (basic check)
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not configured. Please set AWS_DEFAULT_REGION or run 'aws configure'."
        exit 1
    fi
    
    log "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "AWS Region: ${AWS_REGION}"
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resource naming
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    # Set project-specific variables
    export PROJECT_NAME="file-processing-${RANDOM_SUFFIX}"
    export LANDING_BUCKET="${PROJECT_NAME}-landing"
    export PROCESSED_BUCKET="${PROJECT_NAME}-processed"
    export ARCHIVE_BUCKET="${PROJECT_NAME}-archive"
    
    log "Project Name: ${PROJECT_NAME}"
    log "Landing Bucket: ${LANDING_BUCKET}"
    log "Processed Bucket: ${PROCESSED_BUCKET}"
    log "Archive Bucket: ${ARCHIVE_BUCKET}"
    
    success "Environment variables configured"
}

# Function to create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets..."
    
    # Create S3 buckets for file storage tiers
    aws s3 mb s3://${LANDING_BUCKET} --region ${AWS_REGION}
    aws s3 mb s3://${PROCESSED_BUCKET} --region ${AWS_REGION}
    aws s3 mb s3://${ARCHIVE_BUCKET} --region ${AWS_REGION}
    
    # Enable S3 bucket versioning for data protection
    aws s3api put-bucket-versioning \
        --bucket ${LANDING_BUCKET} \
        --versioning-configuration Status=Enabled
    
    aws s3api put-bucket-versioning \
        --bucket ${PROCESSED_BUCKET} \
        --versioning-configuration Status=Enabled
    
    # Enable S3 bucket encryption
    aws s3api put-bucket-encryption \
        --bucket ${LANDING_BUCKET} \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    aws s3api put-bucket-encryption \
        --bucket ${PROCESSED_BUCKET} \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    aws s3api put-bucket-encryption \
        --bucket ${ARCHIVE_BUCKET} \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    success "S3 buckets created with versioning and encryption enabled"
}

# Function to create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create Lambda execution role
    aws iam create-role \
        --role-name ${PROJECT_NAME}-lambda-role \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "lambda.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' || warning "Lambda role may already exist"
    
    # Attach AWS managed policies for Lambda
    aws iam attach-role-policy \
        --role-name ${PROJECT_NAME}-lambda-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for S3 and SNS access
    aws iam create-policy \
        --policy-name ${PROJECT_NAME}-lambda-policy \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:CopyObject",
                        "s3:DeleteObject"
                    ],
                    "Resource": [
                        "arn:aws:s3:::'${LANDING_BUCKET}'/*",
                        "arn:aws:s3:::'${PROCESSED_BUCKET}'/*",
                        "arn:aws:s3:::'${ARCHIVE_BUCKET}'/*"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action": ["sns:Publish"],
                    "Resource": "*"
                },
                {
                    "Effect": "Allow",
                    "Action": ["sts:GetCallerIdentity"],
                    "Resource": "*"
                }
            ]
        }' || warning "Lambda policy may already exist"
    
    aws iam attach-role-policy \
        --role-name ${PROJECT_NAME}-lambda-role \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-lambda-policy
    
    # Create Transfer Family service role
    aws iam create-role \
        --role-name ${PROJECT_NAME}-transfer-role \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "transfer.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' || warning "Transfer role may already exist"
    
    # Create custom policy for Transfer Family S3 access
    aws iam create-policy \
        --policy-name ${PROJECT_NAME}-transfer-policy \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Action": [
                    "s3:PutObject",
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:DeleteObject",
                    "s3:DeleteObjectVersion"
                ],
                "Resource": "arn:aws:s3:::'${LANDING_BUCKET}'/*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:ListBucket",
                    "s3:GetBucketLocation"
                ],
                "Resource": "arn:aws:s3:::'${LANDING_BUCKET}'"
            }]
        }' || warning "Transfer policy may already exist"
    
    aws iam attach-role-policy \
        --role-name ${PROJECT_NAME}-transfer-role \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-transfer-policy
    
    # Create Step Functions execution role
    aws iam create-role \
        --role-name ${PROJECT_NAME}-stepfunctions-role \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "states.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' || warning "Step Functions role may already exist"
    
    # Create EventBridge role for Step Functions integration
    aws iam create-role \
        --role-name ${PROJECT_NAME}-events-role \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "events.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' || warning "EventBridge role may already exist"
    
    # Wait for roles to propagate
    log "Waiting for IAM roles to propagate..."
    sleep 10
    
    success "IAM roles created successfully"
}

# Function to create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create temporary directory for Lambda code
    TEMP_DIR=$(mktemp -d)
    cd $TEMP_DIR
    
    # Create file validator Lambda function
    cat > validator-function.py << 'EOF'
import json
import boto3
import csv
from io import StringIO

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    
    # Extract S3 information from EventBridge or direct input
    if 'detail' in event:
        bucket = event['detail']['bucket']['name']
        key = event['detail']['object']['key']
    else:
        bucket = event['bucket']
        key = event['key']
    
    try:
        # Download and validate file format
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Validate CSV format
        csv_reader = csv.reader(StringIO(content))
        rows = list(csv_reader)
        
        if len(rows) < 2:  # Header + at least one data row
            raise ValueError("File must contain header and data rows")
        
        return {
            'statusCode': 200,
            'isValid': True,
            'rowCount': len(rows) - 1,
            'bucket': bucket,
            'key': key
        }
    except Exception as e:
        return {
            'statusCode': 400,
            'isValid': False,
            'error': str(e),
            'bucket': bucket,
            'key': key
        }
EOF
    
    # Package and deploy validator function
    zip validator-function.zip validator-function.py
    
    aws lambda create-function \
        --function-name ${PROJECT_NAME}-validator \
        --runtime python3.9 \
        --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role \
        --handler validator-function.lambda_handler \
        --zip-file fileb://validator-function.zip \
        --timeout 60 \
        --memory-size 256
    
    # Create data processor Lambda function
    cat > processor-function.py << 'EOF'
import json
import boto3
import csv
import io
from datetime import datetime

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    bucket = event['bucket']
    key = event['key']
    
    try:
        # Download original file
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Process CSV data
        csv_reader = csv.DictReader(io.StringIO(content))
        processed_rows = []
        
        for row in csv_reader:
            # Add processing timestamp
            row['processed_timestamp'] = datetime.utcnow().isoformat()
            # Add business logic transformations here
            processed_rows.append(row)
        
        # Convert back to CSV
        output = io.StringIO()
        if processed_rows:
            writer = csv.DictWriter(output, fieldnames=processed_rows[0].keys())
            writer.writeheader()
            writer.writerows(processed_rows)
        
        # Upload processed file
        processed_key = f"processed/{key}"
        s3.put_object(
            Bucket=bucket.replace('landing', 'processed'),
            Key=processed_key,
            Body=output.getvalue(),
            ContentType='text/csv'
        )
        
        return {
            'statusCode': 200,
            'processedKey': processed_key,
            'recordCount': len(processed_rows),
            'bucket': bucket,
            'originalKey': key
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'error': str(e),
            'bucket': bucket,
            'key': key
        }
EOF
    
    # Create routing Lambda function
    cat > router-function.py << 'EOF'
import json
import boto3
import csv
import io

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    
    bucket = event['bucket']
    key = event['processedKey']
    record_count = event['recordCount']
    
    try:
        # Determine routing destination based on file content
        if 'financial' in key.lower():
            destination = 'financial-data/'
        elif 'inventory' in key.lower():
            destination = 'inventory-data/'
        else:
            destination = 'general-data/'
        
        # Copy to appropriate destination
        processed_bucket = bucket.replace('landing', 'processed')
        archive_bucket = bucket.replace('landing', 'archive')
        
        # Copy to archive with organized structure
        archive_key = f"{destination}{key}"
        s3.copy_object(
            CopySource={'Bucket': processed_bucket, 'Key': key},
            Bucket=archive_bucket,
            Key=archive_key
        )
        
        return {
            'statusCode': 200,
            'destination': destination,
            'archiveKey': archive_key,
            'recordCount': record_count
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'error': str(e)
        }
EOF
    
    # Deploy processor function
    zip processor-function.zip processor-function.py
    
    aws lambda create-function \
        --function-name ${PROJECT_NAME}-processor \
        --runtime python3.9 \
        --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role \
        --handler processor-function.lambda_handler \
        --zip-file fileb://processor-function.zip \
        --timeout 300 \
        --memory-size 512
    
    # Deploy router function
    zip router-function.zip router-function.py
    
    aws lambda create-function \
        --function-name ${PROJECT_NAME}-router \
        --runtime python3.9 \
        --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role \
        --handler router-function.lambda_handler \
        --zip-file fileb://router-function.zip \
        --timeout 180 \
        --memory-size 256
    
    # Clean up temporary files
    cd - > /dev/null
    rm -rf $TEMP_DIR
    
    success "Lambda functions created successfully"
}

# Function to configure IAM policies for Step Functions
configure_stepfunctions_policies() {
    log "Configuring Step Functions and EventBridge policies..."
    
    # Create Step Functions policy for Lambda invocation
    aws iam create-policy \
        --policy-name ${PROJECT_NAME}-stepfunctions-policy \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Action": "lambda:InvokeFunction",
                "Resource": [
                    "arn:aws:lambda:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':function:'${PROJECT_NAME}'-validator",
                    "arn:aws:lambda:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':function:'${PROJECT_NAME}'-processor",
                    "arn:aws:lambda:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':function:'${PROJECT_NAME}'-router"
                ]
            }]
        }' || warning "Step Functions policy may already exist"
    
    aws iam attach-role-policy \
        --role-name ${PROJECT_NAME}-stepfunctions-role \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-stepfunctions-policy
    
    # Create EventBridge policy for Step Functions invocation
    aws iam create-policy \
        --policy-name ${PROJECT_NAME}-events-policy \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Action": "states:StartExecution",
                "Resource": "*"
            }]
        }' || warning "EventBridge policy may already exist"
    
    aws iam attach-role-policy \
        --role-name ${PROJECT_NAME}-events-role \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-events-policy
    
    success "IAM policies configured for Step Functions and EventBridge"
}

# Function to create Step Functions state machine
create_step_functions() {
    log "Creating Step Functions state machine..."
    
    # Create temporary file for workflow definition
    TEMP_WORKFLOW=$(mktemp)
    
    cat > $TEMP_WORKFLOW << EOF
{
  "Comment": "Automated file processing workflow",
  "StartAt": "ValidateFile",
  "States": {
    "ValidateFile": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-validator",
      "Next": "CheckValidation",
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException", "Lambda.AWSLambdaException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ValidationFailed"
        }
      ]
    },
    "CheckValidation": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.isValid",
          "BooleanEquals": true,
          "Next": "ProcessFile"
        }
      ],
      "Default": "ValidationFailed"
    },
    "ProcessFile": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-processor",
      "Next": "RouteFile",
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3
        }
      ]
    },
    "RouteFile": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-router",
      "Next": "ProcessingComplete"
    },
    "ProcessingComplete": {
      "Type": "Succeed"
    },
    "ValidationFailed": {
      "Type": "Fail",
      "Cause": "File validation failed"
    }
  }
}
EOF
    
    # Create Step Functions state machine
    aws stepfunctions create-state-machine \
        --name ${PROJECT_NAME}-workflow \
        --definition file://$TEMP_WORKFLOW \
        --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-stepfunctions-role
    
    # Clean up temporary file
    rm $TEMP_WORKFLOW
    
    success "Step Functions workflow created with error handling"
}

# Function to create Transfer Family SFTP server
create_transfer_family() {
    log "Creating AWS Transfer Family SFTP server..."
    
    # Create Transfer Family SFTP server
    aws transfer create-server \
        --identity-provider-type SERVICE_MANAGED \
        --protocols SFTP \
        --endpoint-type PUBLIC \
        --tags Key=Project,Value=${PROJECT_NAME}
    
    # Wait for server to be online
    log "Waiting for Transfer Family server to be online..."
    sleep 30
    
    # Get server ID
    TRANSFER_SERVER_ID=$(aws transfer list-servers \
        --query 'Servers[0].ServerId' --output text)
    
    if [ "$TRANSFER_SERVER_ID" == "None" ] || [ -z "$TRANSFER_SERVER_ID" ]; then
        error "Failed to retrieve Transfer Family server ID"
        exit 1
    fi
    
    # Wait for server to be fully online before creating user
    aws transfer wait server-online --server-id $TRANSFER_SERVER_ID
    
    # Create SFTP user with S3 access
    aws transfer create-user \
        --server-id ${TRANSFER_SERVER_ID} \
        --user-name businesspartner \
        --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-transfer-role \
        --home-directory /${LANDING_BUCKET} \
        --home-directory-type PATH \
        --tags Key=UserType,Value=BusinessPartner
    
    # Get SFTP endpoint
    SFTP_ENDPOINT=$(aws transfer describe-server \
        --server-id ${TRANSFER_SERVER_ID} \
        --query 'Server.EndpointDetails.Address' \
        --output text)
    
    log "Transfer Family SFTP server created: ${TRANSFER_SERVER_ID}"
    log "SFTP Endpoint: ${SFTP_ENDPOINT}"
    
    # Store server info for cleanup
    echo "TRANSFER_SERVER_ID=${TRANSFER_SERVER_ID}" >> /tmp/${PROJECT_NAME}-resources.env
    
    success "Transfer Family SFTP server created successfully"
}

# Function to configure S3 event integration
configure_s3_events() {
    log "Configuring S3 event integration with Step Functions..."
    
    # Enable EventBridge for S3 bucket
    aws s3api put-bucket-notification-configuration \
        --bucket ${LANDING_BUCKET} \
        --notification-configuration '{
            "EventBridgeConfiguration": {}
        }'
    
    # Create EventBridge rule for S3 events
    aws events put-rule \
        --name ${PROJECT_NAME}-file-processing \
        --event-pattern '{
            "source": ["aws.s3"],
            "detail-type": ["Object Created"],
            "detail": {
                "bucket": {"name": ["'${LANDING_BUCKET}'"]}
            }
        }' \
        --state ENABLED
    
    # Get State Machine ARN
    STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?name=='${PROJECT_NAME}-workflow'].stateMachineArn" \
        --output text)
    
    if [ -z "$STATE_MACHINE_ARN" ]; then
        error "Failed to retrieve Step Functions state machine ARN"
        exit 1
    fi
    
    # Add Step Functions as target
    aws events put-targets \
        --rule ${PROJECT_NAME}-file-processing \
        --targets "Id"="1","Arn"="${STATE_MACHINE_ARN}","RoleArn"="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-events-role"
    
    success "S3 event integration configured with Step Functions"
}

# Function to set up monitoring
setup_monitoring() {
    log "Setting up monitoring and alerting..."
    
    # Create SNS topic for alerts
    aws sns create-topic --name ${PROJECT_NAME}-alerts
    
    TOPIC_ARN=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, '${PROJECT_NAME}-alerts')].TopicArn" \
        --output text)
    
    # Get State Machine ARN
    STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?name=='${PROJECT_NAME}-workflow'].stateMachineArn" \
        --output text)
    
    # Create CloudWatch alarm for failed executions
    aws cloudwatch put-metric-alarm \
        --alarm-name ${PROJECT_NAME}-failed-executions \
        --alarm-description "Alert on Step Functions execution failures" \
        --metric-name ExecutionsFailed \
        --namespace AWS/States \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions ${TOPIC_ARN} \
        --dimensions Name=StateMachineArn,Value=${STATE_MACHINE_ARN}
    
    success "Monitoring and alerting configured"
}

# Function to create test file and validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Create test CSV file
    cat > test-financial-data.csv << 'EOF'
transaction_id,amount,currency,date
TX001,1500.00,USD,2025-07-12
TX002,2750.50,USD,2025-07-12
TX003,890.25,EUR,2025-07-12
EOF
    
    # Upload test file to trigger workflow
    aws s3 cp test-financial-data.csv s3://${LANDING_BUCKET}/
    
    log "Test file uploaded. Waiting for processing..."
    sleep 30
    
    # Check Step Functions execution
    STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?name=='${PROJECT_NAME}-workflow'].stateMachineArn" \
        --output text)
    
    EXECUTION_STATUS=$(aws stepfunctions list-executions \
        --state-machine-arn ${STATE_MACHINE_ARN} \
        --max-items 1 \
        --query 'executions[0].status' \
        --output text 2>/dev/null || echo "UNKNOWN")
    
    if [ "$EXECUTION_STATUS" == "SUCCEEDED" ]; then
        success "Step Functions execution completed successfully"
    else
        warning "Step Functions execution status: ${EXECUTION_STATUS}"
    fi
    
    # Check for processed files
    PROCESSED_FILES=$(aws s3 ls s3://${PROCESSED_BUCKET}/ --recursive | wc -l)
    ARCHIVE_FILES=$(aws s3 ls s3://${ARCHIVE_BUCKET}/ --recursive | wc -l)
    
    log "Processed files: ${PROCESSED_FILES}"
    log "Archive files: ${ARCHIVE_FILES}"
    
    # Clean up test file
    rm -f test-financial-data.csv
    
    success "Deployment validation completed"
}

# Function to save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    # Create deployment info file
    cat > /tmp/${PROJECT_NAME}-deployment-info.txt << EOF
===========================================
AWS Transfer Family File Processing Pipeline
===========================================

Deployment completed: $(date)
Project Name: ${PROJECT_NAME}
AWS Region: ${AWS_REGION}
AWS Account ID: ${AWS_ACCOUNT_ID}

Resources Created:
- S3 Buckets:
  * Landing: ${LANDING_BUCKET}
  * Processed: ${PROCESSED_BUCKET}
  * Archive: ${ARCHIVE_BUCKET}

- Lambda Functions:
  * ${PROJECT_NAME}-validator
  * ${PROJECT_NAME}-processor
  * ${PROJECT_NAME}-router

- Step Functions:
  * ${PROJECT_NAME}-workflow

- Transfer Family:
  * Server ID: $(cat /tmp/${PROJECT_NAME}-resources.env 2>/dev/null | grep TRANSFER_SERVER_ID | cut -d= -f2 || echo "Unknown")

- IAM Roles:
  * ${PROJECT_NAME}-lambda-role
  * ${PROJECT_NAME}-transfer-role
  * ${PROJECT_NAME}-stepfunctions-role
  * ${PROJECT_NAME}-events-role

- Monitoring:
  * SNS Topic: ${PROJECT_NAME}-alerts
  * CloudWatch Alarm: ${PROJECT_NAME}-failed-executions

Next Steps:
1. Configure SFTP client to connect to the Transfer Family endpoint
2. Upload test files to validate the processing pipeline
3. Monitor CloudWatch logs and Step Functions executions
4. Set up email notifications for the SNS topic

To clean up all resources, run: ./destroy.sh
EOF
    
    log "Deployment information saved to: /tmp/${PROJECT_NAME}-deployment-info.txt"
    cat /tmp/${PROJECT_NAME}-deployment-info.txt
}

# Main deployment function
main() {
    log "Starting AWS Transfer Family and Step Functions deployment..."
    
    check_prerequisites
    setup_environment
    create_s3_buckets
    create_iam_roles
    create_lambda_functions
    configure_stepfunctions_policies
    create_step_functions
    create_transfer_family
    configure_s3_events
    setup_monitoring
    validate_deployment
    save_deployment_info
    
    success "Deployment completed successfully!"
    success "Project Name: ${PROJECT_NAME}"
    success "Check deployment info at: /tmp/${PROJECT_NAME}-deployment-info.txt"
}

# Handle script interruption
trap 'error "Deployment interrupted. You may need to manually clean up partial resources."; exit 1' INT TERM

# Run main function
main "$@"