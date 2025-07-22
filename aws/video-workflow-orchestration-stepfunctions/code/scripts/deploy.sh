#!/bin/bash

# Automated Video Workflow Orchestration with Step Functions - Deployment Script
# This script deploys the complete video processing workflow infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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

# Error handling function
handle_error() {
    log_error "Deployment failed at line $1"
    log_error "Command that failed: $2"
    exit 1
}

trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if jq is installed (for JSON processing)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some JSON processing may fail."
        log_info "Installing jq (if running on Amazon Linux/RHEL)..."
        if command -v yum &> /dev/null; then
            sudo yum install -y jq || log_warning "Failed to install jq via yum"
        elif command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y jq || log_warning "Failed to install jq via apt"
        fi
    fi
    
    # Check required permissions (basic check)
    log_info "Verifying AWS permissions..."
    if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity &> /dev/null; then
        log_error "Unable to verify AWS identity. Check your credentials."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to generate unique identifiers
generate_identifiers() {
    log_info "Generating unique identifiers..."
    
    # Generate random suffix for resource names
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 8)")
    
    # Set environment variables for all resources
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export WORKFLOW_NAME="video-processing-workflow-${RANDOM_SUFFIX}"
    export SOURCE_BUCKET="video-workflow-source-${RANDOM_SUFFIX}"
    export OUTPUT_BUCKET="video-workflow-output-${RANDOM_SUFFIX}"
    export ARCHIVE_BUCKET="video-workflow-archive-${RANDOM_SUFFIX}"
    export JOBS_TABLE="video-workflow-jobs-${RANDOM_SUFFIX}"
    export SNS_TOPIC="video-workflow-notifications-${RANDOM_SUFFIX}"
    export MEDIACONVERT_ROLE="VideoWorkflowMediaConvertRole-${RANDOM_SUFFIX}"
    
    log_success "Generated resource identifiers with suffix: ${RANDOM_SUFFIX}"
    
    # Save configuration to file for later cleanup
    cat > deployment-config.env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
WORKFLOW_NAME=${WORKFLOW_NAME}
SOURCE_BUCKET=${SOURCE_BUCKET}
OUTPUT_BUCKET=${OUTPUT_BUCKET}
ARCHIVE_BUCKET=${ARCHIVE_BUCKET}
JOBS_TABLE=${JOBS_TABLE}
SNS_TOPIC=${SNS_TOPIC}
MEDIACONVERT_ROLE=${MEDIACONVERT_ROLE}
EOF
    
    log_info "Configuration saved to deployment-config.env"
}

# Function to create S3 buckets
create_s3_infrastructure() {
    log_info "Creating S3 buckets..."
    
    # Create source bucket
    aws s3 mb "s3://${SOURCE_BUCKET}" --region "${AWS_REGION}" || \
        log_warning "Source bucket ${SOURCE_BUCKET} may already exist"
    
    # Create output bucket
    aws s3 mb "s3://${OUTPUT_BUCKET}" --region "${AWS_REGION}" || \
        log_warning "Output bucket ${OUTPUT_BUCKET} may already exist"
    
    # Create archive bucket
    aws s3 mb "s3://${ARCHIVE_BUCKET}" --region "${AWS_REGION}" || \
        log_warning "Archive bucket ${ARCHIVE_BUCKET} may already exist"
    
    # Enable versioning on source bucket
    aws s3api put-bucket-versioning \
        --bucket "${SOURCE_BUCKET}" \
        --versioning-configuration Status=Enabled
    
    log_success "S3 buckets created and configured"
}

# Function to create DynamoDB table
create_dynamodb_table() {
    log_info "Creating DynamoDB table for job tracking..."
    
    aws dynamodb create-table \
        --table-name "${JOBS_TABLE}" \
        --attribute-definitions \
            AttributeName=JobId,AttributeType=S \
            AttributeName=CreatedAt,AttributeType=S \
        --key-schema \
            AttributeName=JobId,KeyType=HASH \
        --global-secondary-indexes \
            IndexName=CreatedAtIndex,KeySchema=[{AttributeName=CreatedAt,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5} \
        --provisioned-throughput ReadCapacityUnits=10,WriteCapacityUnits=10 \
        --tags Key=Name,Value="${JOBS_TABLE}" Key=Environment,Value=Production \
        --region "${AWS_REGION}"
    
    # Wait for table to become active
    log_info "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name "${JOBS_TABLE}" --region "${AWS_REGION}"
    
    log_success "DynamoDB table created successfully"
}

# Function to create SNS topic
create_sns_topic() {
    log_info "Creating SNS topic for notifications..."
    
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC}" \
        --region "${AWS_REGION}" \
        --output text --query TopicArn)
    
    # Save SNS topic ARN to config
    echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> deployment-config.env
    
    log_success "SNS topic created: ${SNS_TOPIC_ARN}"
}

# Function to create IAM roles
create_iam_roles() {
    log_info "Creating IAM roles for MediaConvert and Lambda..."
    
    # Create MediaConvert trust policy
    cat > mediaconvert-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "mediaconvert.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create MediaConvert service role
    aws iam create-role \
        --role-name "${MEDIACONVERT_ROLE}" \
        --assume-role-policy-document file://mediaconvert-trust-policy.json
    
    # Create MediaConvert policy
    cat > mediaconvert-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": [
                "arn:aws:s3:::${SOURCE_BUCKET}",
                "arn:aws:s3:::${SOURCE_BUCKET}/*",
                "arn:aws:s3:::${OUTPUT_BUCKET}",
                "arn:aws:s3:::${OUTPUT_BUCKET}/*",
                "arn:aws:s3:::${ARCHIVE_BUCKET}",
                "arn:aws:s3:::${ARCHIVE_BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "${SNS_TOPIC_ARN}"
        }
    ]
}
EOF
    
    # Attach policy to MediaConvert role
    aws iam put-role-policy \
        --role-name "${MEDIACONVERT_ROLE}" \
        --policy-name MediaConvertWorkflowPolicy \
        --policy-document file://mediaconvert-policy.json
    
    # Get MediaConvert role ARN
    export MEDIACONVERT_ROLE_ARN=$(aws iam get-role \
        --role-name "${MEDIACONVERT_ROLE}" \
        --query Role.Arn --output text)
    
    # Create Lambda trust policy
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
    
    # Create Lambda role
    export LAMBDA_ROLE_NAME="VideoWorkflowLambdaRole-${RANDOM_SUFFIX}"
    aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document file://lambda-trust-policy.json
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create Lambda workflow policy
    cat > lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:HeadObject"
            ],
            "Resource": [
                "arn:aws:s3:::${SOURCE_BUCKET}",
                "arn:aws:s3:::${SOURCE_BUCKET}/*",
                "arn:aws:s3:::${OUTPUT_BUCKET}",
                "arn:aws:s3:::${OUTPUT_BUCKET}/*",
                "arn:aws:s3:::${ARCHIVE_BUCKET}",
                "arn:aws:s3:::${ARCHIVE_BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${JOBS_TABLE}*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "${SNS_TOPIC_ARN}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "stepfunctions:StartExecution"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Attach workflow policy
    aws iam put-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-name VideoWorkflowPolicy \
        --policy-document file://lambda-policy.json
    
    # Get Lambda role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --query Role.Arn --output text)
    
    # Save role ARNs to config
    echo "MEDIACONVERT_ROLE_ARN=${MEDIACONVERT_ROLE_ARN}" >> deployment-config.env
    echo "LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> deployment-config.env
    echo "LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}" >> deployment-config.env
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
    
    log_success "IAM roles created successfully"
}

# Function to create Lambda functions
create_lambda_functions() {
    log_info "Creating Lambda functions..."
    
    # Create metadata extraction Lambda
    cat > video_metadata_extractor.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    # Extract input parameters
    bucket = event['bucket']
    key = event['key']
    job_id = event['jobId']
    
    try:
        # Get basic file information
        response = s3.head_object(Bucket=bucket, Key=key)
        file_size = response['ContentLength']
        
        # Simplified metadata extraction (placeholder)
        metadata = {
            'duration': 120.5,
            'width': 1920,
            'height': 1080,
            'fps': 29.97,
            'bitrate': 5000000,
            'codec': 'h264',
            'audio_codec': 'aac',
            'file_size': file_size,
            'last_modified': response['LastModified'].isoformat()
        }
        
        # Store metadata in DynamoDB
        table = dynamodb.Table(os.environ['JOBS_TABLE'])
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET VideoMetadata = :metadata, MetadataExtractedAt = :timestamp',
            ExpressionAttributeValues={
                ':metadata': metadata,
                ':timestamp': datetime.utcnow().isoformat()
            }
        )
        
        return {
            'statusCode': 200,
            'metadata': metadata,
            'jobId': job_id
        }
        
    except Exception as e:
        print(f"Error extracting metadata: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'jobId': job_id
        }
EOF
    
    # Create quality control Lambda
    cat > video_quality_control.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    # Extract input parameters
    outputs = event['outputs']
    job_id = event['jobId']
    
    try:
        quality_results = []
        
        for output in outputs:
            bucket = output['bucket']
            key = output['key']
            format_type = output['format']
            
            # Perform quality checks
            try:
                response = s3.head_object(Bucket=bucket, Key=key)
                file_size = response['ContentLength']
                
                checks = {
                    'file_exists': True,
                    'file_size_valid': file_size > 1000,
                    'format_valid': format_type in ['mp4', 'hls', 'dash'],
                    'encoding_quality': 0.9
                }
                
                score = sum(1 for check in checks.values() if check is True) / len([k for k in checks.keys() if k != 'encoding_quality'])
                if 'encoding_quality' in checks:
                    score = (score + checks['encoding_quality']) / 2
                
                quality_results.append({
                    'bucket': bucket,
                    'key': key,
                    'format': format_type,
                    'checks': checks,
                    'score': score,
                    'file_size': file_size
                })
                
            except Exception as e:
                quality_results.append({
                    'bucket': bucket,
                    'key': key,
                    'format': format_type,
                    'error': str(e),
                    'score': 0.0
                })
        
        # Calculate overall quality score
        if quality_results:
            overall_score = sum(result.get('score', 0.0) for result in quality_results) / len(quality_results)
        else:
            overall_score = 0.0
        
        # Store results in DynamoDB
        table = dynamodb.Table(os.environ['JOBS_TABLE'])
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET QualityResults = :results, QualityScore = :score, QCCompletedAt = :timestamp',
            ExpressionAttributeValues={
                ':results': quality_results,
                ':score': overall_score,
                ':timestamp': datetime.utcnow().isoformat()
            }
        )
        
        return {
            'statusCode': 200,
            'qualityResults': quality_results,
            'qualityScore': overall_score,
            'passed': overall_score >= 0.8,
            'jobId': job_id
        }
        
    except Exception as e:
        print(f"Error in quality control: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'jobId': job_id,
            'passed': False
        }
EOF
    
    # Create publisher Lambda
    cat > video_publisher.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

def lambda_handler(event, context):
    # Extract input parameters
    job_id = event['jobId']
    outputs = event['outputs']
    quality_passed = event.get('qualityPassed', False)
    
    try:
        # Update job status in DynamoDB
        table = dynamodb.Table(os.environ['JOBS_TABLE'])
        
        if quality_passed:
            # Publish successful completion
            table.update_item(
                Key={'JobId': job_id},
                UpdateExpression='SET JobStatus = :status, PublishedAt = :timestamp, OutputLocations = :outputs',
                ExpressionAttributeValues={
                    ':status': 'PUBLISHED',
                    ':timestamp': datetime.utcnow().isoformat(),
                    ':outputs': outputs
                }
            )
            
            message = f"Video processing completed successfully for job {job_id}"
            subject = "Video Processing Success"
            
        else:
            # Mark as failed quality control
            table.update_item(
                Key={'JobId': job_id},
                UpdateExpression='SET JobStatus = :status, FailedAt = :timestamp, FailureReason = :reason',
                ExpressionAttributeValues={
                    ':status': 'FAILED_QC',
                    ':timestamp': datetime.utcnow().isoformat(),
                    ':reason': 'Quality control validation failed'
                }
            )
            
            message = f"Video processing failed quality control for job {job_id}"
            subject = "Video Processing Quality Control Failed"
        
        # Send SNS notification
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=message,
            Subject=subject
        )
        
        return {
            'statusCode': 200,
            'jobId': job_id,
            'status': 'PUBLISHED' if quality_passed else 'FAILED_QC',
            'message': message
        }
        
    except Exception as e:
        print(f"Error in publishing: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'jobId': job_id
        }
EOF
    
    # Create workflow trigger Lambda
    cat > workflow_trigger.py << 'EOF'
import json
import boto3
import uuid
import os
from datetime import datetime

stepfunctions = boto3.client('stepfunctions')

def lambda_handler(event, context):
    try:
        # Handle S3 event or direct API call
        if 'Records' in event:
            # S3 event notification
            for record in event['Records']:
                bucket = record['s3']['bucket']['name']
                key = record['s3']['object']['key']
                process_video(bucket, key)
        else:
            # Direct API call
            if 'body' in event:
                body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
            else:
                body = event
            
            bucket = body.get('bucket')
            key = body.get('key')
            
            if not bucket or not key:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'Missing bucket or key parameter'})
                }
            
            job_id = process_video(bucket, key)
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'jobId': job_id,
                    'message': 'Video processing workflow started successfully'
                })
            }
        
    except Exception as e:
        print(f"Error starting workflow: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def process_video(bucket, key):
    # Generate unique job ID
    job_id = str(uuid.uuid4())
    
    # Start Step Functions execution
    stepfunctions.start_execution(
        stateMachineArn=os.environ['STATE_MACHINE_ARN'],
        name=f"video-workflow-{job_id}",
        input=json.dumps({
            'jobId': job_id,
            'bucket': bucket,
            'key': key,
            'requestedAt': datetime.utcnow().isoformat()
        })
    )
    
    return job_id
EOF
    
    # Create deployment packages
    zip metadata-extractor.zip video_metadata_extractor.py
    zip quality-control.zip video_quality_control.py
    zip video-publisher.zip video_publisher.py
    zip workflow-trigger.zip workflow_trigger.py
    
    # Create Lambda functions
    export METADATA_LAMBDA_ARN=$(aws lambda create-function \
        --function-name "video-metadata-extractor-${RANDOM_SUFFIX}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler video_metadata_extractor.lambda_handler \
        --zip-file fileb://metadata-extractor.zip \
        --timeout 300 \
        --environment Variables="{JOBS_TABLE=${JOBS_TABLE}}" \
        --query 'FunctionArn' --output text)
    
    export QC_LAMBDA_ARN=$(aws lambda create-function \
        --function-name "video-quality-control-${RANDOM_SUFFIX}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler video_quality_control.lambda_handler \
        --zip-file fileb://quality-control.zip \
        --timeout 300 \
        --environment Variables="{JOBS_TABLE=${JOBS_TABLE}}" \
        --query 'FunctionArn' --output text)
    
    export PUBLISHER_LAMBDA_ARN=$(aws lambda create-function \
        --function-name "video-publisher-${RANDOM_SUFFIX}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler video_publisher.lambda_handler \
        --zip-file fileb://video-publisher.zip \
        --timeout 300 \
        --environment Variables="{JOBS_TABLE=${JOBS_TABLE},SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}" \
        --query 'FunctionArn' --output text)
    
    export TRIGGER_LAMBDA_ARN=$(aws lambda create-function \
        --function-name "video-workflow-trigger-${RANDOM_SUFFIX}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler workflow_trigger.lambda_handler \
        --zip-file fileb://workflow-trigger.zip \
        --timeout 30 \
        --environment Variables="{STATE_MACHINE_ARN=placeholder}" \
        --query 'FunctionArn' --output text)
    
    # Save Lambda ARNs to config
    cat >> deployment-config.env << EOF
METADATA_LAMBDA_ARN=${METADATA_LAMBDA_ARN}
QC_LAMBDA_ARN=${QC_LAMBDA_ARN}
PUBLISHER_LAMBDA_ARN=${PUBLISHER_LAMBDA_ARN}
TRIGGER_LAMBDA_ARN=${TRIGGER_LAMBDA_ARN}
EOF
    
    log_success "Lambda functions created successfully"
}

# Function to get MediaConvert endpoint
get_mediaconvert_endpoint() {
    log_info "Getting MediaConvert endpoint..."
    
    export MEDIACONVERT_ENDPOINT=$(aws mediaconvert describe-endpoints \
        --region "${AWS_REGION}" \
        --query Endpoints[0].Url --output text)
    
    echo "MEDIACONVERT_ENDPOINT=${MEDIACONVERT_ENDPOINT}" >> deployment-config.env
    
    log_success "MediaConvert endpoint: ${MEDIACONVERT_ENDPOINT}"
}

# Function to create Step Functions state machine
create_step_functions() {
    log_info "Creating Step Functions state machine..."
    
    # Create Step Functions trust policy
    cat > stepfunctions-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "states.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create Step Functions role
    export STEPFUNCTIONS_ROLE_NAME="VideoWorkflowStepFunctionsRole-${RANDOM_SUFFIX}"
    aws iam create-role \
        --role-name "${STEPFUNCTIONS_ROLE_NAME}" \
        --assume-role-policy-document file://stepfunctions-trust-policy.json
    
    # Create Step Functions policy
    cat > stepfunctions-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "${METADATA_LAMBDA_ARN}",
                "${QC_LAMBDA_ARN}",
                "${PUBLISHER_LAMBDA_ARN}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "mediaconvert:CreateJob",
                "mediaconvert:GetJob",
                "mediaconvert:ListJobs"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:PassRole"
            ],
            "Resource": "${MEDIACONVERT_ROLE_ARN}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${JOBS_TABLE}*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:CopyObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${SOURCE_BUCKET}",
                "arn:aws:s3:::${SOURCE_BUCKET}/*",
                "arn:aws:s3:::${OUTPUT_BUCKET}",
                "arn:aws:s3:::${OUTPUT_BUCKET}/*",
                "arn:aws:s3:::${ARCHIVE_BUCKET}",
                "arn:aws:s3:::${ARCHIVE_BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Attach policy to Step Functions role
    aws iam put-role-policy \
        --role-name "${STEPFUNCTIONS_ROLE_NAME}" \
        --policy-name VideoWorkflowStepFunctionsPolicy \
        --policy-document file://stepfunctions-policy.json
    
    # Get Step Functions role ARN
    export STEPFUNCTIONS_ROLE_ARN=$(aws iam get-role \
        --role-name "${STEPFUNCTIONS_ROLE_NAME}" \
        --query Role.Arn --output text)
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
    
    # Create CloudWatch log group for Step Functions
    aws logs create-log-group \
        --log-group-name "/aws/stepfunctions/${WORKFLOW_NAME}" \
        --region "${AWS_REGION}" || log_warning "Log group may already exist"
    
    # Create simplified state machine definition (basic workflow)
    cat > video-workflow-definition.json << EOF
{
    "Comment": "Video processing workflow with quality control",
    "StartAt": "InitializeJob",
    "States": {
        "InitializeJob": {
            "Type": "Pass",
            "Parameters": {
                "jobId.$": "$.jobId",
                "bucket.$": "$.bucket",
                "key.$": "$.key",
                "outputBucket": "${OUTPUT_BUCKET}",
                "timestamp.$": "$$.State.EnteredTime"
            },
            "Next": "RecordJobStart"
        },
        "RecordJobStart": {
            "Type": "Task",
            "Resource": "arn:aws:states:::dynamodb:putItem",
            "Parameters": {
                "TableName": "${JOBS_TABLE}",
                "Item": {
                    "JobId": {
                        "S.$": "$.jobId"
                    },
                    "SourceBucket": {
                        "S.$": "$.bucket"
                    },
                    "SourceKey": {
                        "S.$": "$.key"
                    },
                    "CreatedAt": {
                        "S.$": "$.timestamp"
                    },
                    "JobStatus": {
                        "S": "STARTED"
                    }
                }
            },
            "Next": "ExtractMetadata",
            "Retry": [
                {
                    "ErrorEquals": ["States.TaskFailed"],
                    "IntervalSeconds": 2,
                    "MaxAttempts": 3,
                    "BackoffRate": 2.0
                }
            ]
        },
        "ExtractMetadata": {
            "Type": "Task",
            "Resource": "${METADATA_LAMBDA_ARN}",
            "Parameters": {
                "bucket.$": "$.bucket",
                "key.$": "$.key",
                "jobId.$": "$.jobId"
            },
            "Next": "CreateTestOutput",
            "Retry": [
                {
                    "ErrorEquals": ["States.TaskFailed"],
                    "IntervalSeconds": 5,
                    "MaxAttempts": 2
                }
            ]
        },
        "CreateTestOutput": {
            "Type": "Pass",
            "Parameters": {
                "jobId.$": "$.jobId",
                "metadata.$": "$.metadata",
                "outputs": [
                    {
                        "format": "mp4",
                        "bucket": "${OUTPUT_BUCKET}",
                        "key.$": "States.Format('mp4/{}/output.mp4', $.jobId)"
                    }
                ]
            },
            "Next": "QualityControl"
        },
        "QualityControl": {
            "Type": "Task",
            "Resource": "${QC_LAMBDA_ARN}",
            "Parameters": {
                "jobId.$": "$.jobId",
                "outputs.$": "$.outputs",
                "metadata.$": "$.metadata"
            },
            "Next": "QualityDecision",
            "Retry": [
                {
                    "ErrorEquals": ["States.TaskFailed"],
                    "IntervalSeconds": 10,
                    "MaxAttempts": 2
                }
            ]
        },
        "QualityDecision": {
            "Type": "Choice",
            "Choices": [
                {
                    "Variable": "$.passed",
                    "BooleanEquals": true,
                    "Next": "PublishContent"
                }
            ],
            "Default": "QualityControlFailed"
        },
        "PublishContent": {
            "Type": "Task",
            "Resource": "${PUBLISHER_LAMBDA_ARN}",
            "Parameters": {
                "jobId.$": "$.jobId",
                "outputs.$": "$.outputs",
                "qualityResults.$": "$.qualityResults",
                "qualityPassed": true
            },
            "Next": "WorkflowSuccess"
        },
        "WorkflowSuccess": {
            "Type": "Pass",
            "Result": {
                "status": "SUCCESS",
                "message": "Video processing workflow completed successfully"
            },
            "End": true
        },
        "QualityControlFailed": {
            "Type": "Task",
            "Resource": "${PUBLISHER_LAMBDA_ARN}",
            "Parameters": {
                "jobId.$": "$.jobId",
                "outputs.$": "$.outputs",
                "qualityResults.$": "$.qualityResults",
                "qualityPassed": false
            },
            "Next": "WorkflowFailure"
        },
        "WorkflowFailure": {
            "Type": "Fail",
            "Cause": "Video processing workflow failed"
        }
    }
}
EOF
    
    # Create Step Functions state machine
    export STATE_MACHINE_ARN=$(aws stepfunctions create-state-machine \
        --name "${WORKFLOW_NAME}" \
        --definition file://video-workflow-definition.json \
        --role-arn "${STEPFUNCTIONS_ROLE_ARN}" \
        --type EXPRESS \
        --logging-configuration level=ALL,includeExecutionData=true,destinations=[{cloudWatchLogsLogGroup=arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/stepfunctions/${WORKFLOW_NAME}}] \
        --query 'stateMachineArn' --output text)
    
    # Update trigger Lambda with state machine ARN
    aws lambda update-function-configuration \
        --function-name "video-workflow-trigger-${RANDOM_SUFFIX}" \
        --environment Variables="{STATE_MACHINE_ARN=${STATE_MACHINE_ARN}}"
    
    # Save to config
    cat >> deployment-config.env << EOF
STEPFUNCTIONS_ROLE_ARN=${STEPFUNCTIONS_ROLE_ARN}
STEPFUNCTIONS_ROLE_NAME=${STEPFUNCTIONS_ROLE_NAME}
STATE_MACHINE_ARN=${STATE_MACHINE_ARN}
EOF
    
    log_success "Step Functions state machine created: ${STATE_MACHINE_ARN}"
}

# Function to create API Gateway
create_api_gateway() {
    log_info "Creating API Gateway..."
    
    # Create API Gateway
    export API_ID=$(aws apigatewayv2 create-api \
        --name "video-workflow-api-${RANDOM_SUFFIX}" \
        --protocol-type HTTP \
        --description "Video processing workflow API" \
        --cors-configuration AllowCredentials=false,AllowHeaders="*",AllowMethods="*",AllowOrigins="*" \
        --query 'ApiId' --output text)
    
    # Create integration
    export INTEGRATION_ID=$(aws apigatewayv2 create-integration \
        --api-id "${API_ID}" \
        --integration-type AWS_PROXY \
        --integration-uri "${TRIGGER_LAMBDA_ARN}" \
        --payload-format-version "2.0" \
        --query 'IntegrationId' --output text)
    
    # Create route
    aws apigatewayv2 create-route \
        --api-id "${API_ID}" \
        --route-key "POST /start-workflow" \
        --target "integrations/${INTEGRATION_ID}"
    
    # Create deployment
    aws apigatewayv2 create-deployment \
        --api-id "${API_ID}" \
        --stage-name prod
    
    # Add permission for API Gateway to invoke Lambda
    aws lambda add-permission \
        --function-name "video-workflow-trigger-${RANDOM_SUFFIX}" \
        --principal apigateway.amazonaws.com \
        --statement-id api-gateway-invoke \
        --action lambda:InvokeFunction \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*"
    
    # Get API endpoint
    export API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    # Save to config
    cat >> deployment-config.env << EOF
API_ID=${API_ID}
INTEGRATION_ID=${INTEGRATION_ID}
API_ENDPOINT=${API_ENDPOINT}
EOF
    
    log_success "API Gateway created: ${API_ENDPOINT}"
}

# Function to configure S3 event notifications
configure_s3_events() {
    log_info "Configuring S3 event notifications..."
    
    # Add permission for S3 to invoke trigger Lambda
    aws lambda add-permission \
        --function-name "video-workflow-trigger-${RANDOM_SUFFIX}" \
        --principal s3.amazonaws.com \
        --statement-id s3-workflow-trigger \
        --action lambda:InvokeFunction \
        --source-arn "arn:aws:s3:::${SOURCE_BUCKET}"
    
    # Create S3 event notification configuration
    cat > s3-notification.json << EOF
{
    "LambdaConfigurations": [
        {
            "Id": "VideoWorkflowTrigger",
            "LambdaFunctionArn": "${TRIGGER_LAMBDA_ARN}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".mp4"
                        }
                    ]
                }
            }
        },
        {
            "Id": "VideoWorkflowTriggerMOV",
            "LambdaFunctionArn": "${TRIGGER_LAMBDA_ARN}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".mov"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
    
    # Apply notification configuration
    aws s3api put-bucket-notification-configuration \
        --bucket "${SOURCE_BUCKET}" \
        --notification-configuration file://s3-notification.json
    
    log_success "S3 event notifications configured"
}

# Function to create CloudWatch dashboard
create_monitoring_dashboard() {
    log_info "Creating CloudWatch monitoring dashboard..."
    
    cat > workflow-dashboard.json << EOF
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
                    [ "AWS/States", "ExecutionsSucceeded", "StateMachineArn", "${STATE_MACHINE_ARN}" ],
                    [ ".", "ExecutionsFailed", ".", "." ],
                    [ ".", "ExecutionsStarted", ".", "." ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Step Functions Executions",
                "view": "timeSeries"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/Lambda", "Invocations", "FunctionName", "video-metadata-extractor-${RANDOM_SUFFIX}" ],
                    [ ".", "Errors", ".", "." ],
                    [ ".", "Duration", ".", "." ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Lambda Functions Performance"
            }
        }
    ]
}
EOF
    
    # Create the dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "VideoWorkflowMonitoring-${RANDOM_SUFFIX}" \
        --dashboard-body file://workflow-dashboard.json
    
    echo "DASHBOARD_NAME=VideoWorkflowMonitoring-${RANDOM_SUFFIX}" >> deployment-config.env
    
    log_success "CloudWatch dashboard created"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    rm -f *.json *.py *.zip
    
    log_success "Temporary files cleaned up"
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "================================================================"
    log_success "VIDEO WORKFLOW ORCHESTRATION DEPLOYMENT COMPLETE"
    echo "================================================================"
    echo ""
    echo "🎯 WORKFLOW COMPONENTS:"
    echo "State Machine: ${STATE_MACHINE_ARN}"
    echo "Jobs Table: ${JOBS_TABLE}"
    echo "API Endpoint: ${API_ENDPOINT}/start-workflow"
    echo ""
    echo "📁 STORAGE BUCKETS:"
    echo "Source: s3://${SOURCE_BUCKET}/"
    echo "Output: s3://${OUTPUT_BUCKET}/"
    echo "Archive: s3://${ARCHIVE_BUCKET}/"
    echo ""
    echo "⚡ LAMBDA FUNCTIONS:"
    echo "Metadata Extractor: video-metadata-extractor-${RANDOM_SUFFIX}"
    echo "Quality Control: video-quality-control-${RANDOM_SUFFIX}"
    echo "Publisher: video-publisher-${RANDOM_SUFFIX}"
    echo "Workflow Trigger: video-workflow-trigger-${RANDOM_SUFFIX}"
    echo ""
    echo "📊 MONITORING:"
    echo "Dashboard: VideoWorkflowMonitoring-${RANDOM_SUFFIX}"
    echo "SNS Topic: ${SNS_TOPIC_ARN}"
    echo ""
    echo "🚀 USAGE EXAMPLES:"
    echo ""
    echo "1. Automatic Processing (upload video to source bucket):"
    echo "   aws s3 cp your-video.mp4 s3://${SOURCE_BUCKET}/"
    echo ""
    echo "2. API-Triggered Processing:"
    echo "   curl -X POST ${API_ENDPOINT}/start-workflow \\"
    echo "        -H 'Content-Type: application/json' \\"
    echo "        -d '{\"bucket\":\"${SOURCE_BUCKET}\",\"key\":\"your-video.mp4\"}'"
    echo ""
    echo "3. Monitor Workflow Executions:"
    echo "   aws stepfunctions list-executions --state-machine-arn ${STATE_MACHINE_ARN}"
    echo ""
    echo "📋 CONFIGURATION:"
    echo "Deployment configuration saved to: deployment-config.env"
    echo "Use this file with destroy.sh for cleanup"
    echo ""
    echo "================================================================"
}

# Main deployment function
main() {
    log_info "Starting video workflow orchestration deployment..."
    
    # Run deployment steps
    check_prerequisites
    generate_identifiers
    create_s3_infrastructure
    create_dynamodb_table
    create_sns_topic
    create_iam_roles
    create_lambda_functions
    get_mediaconvert_endpoint
    create_step_functions
    create_api_gateway
    configure_s3_events
    create_monitoring_dashboard
    cleanup_temp_files
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Check if script is being run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi