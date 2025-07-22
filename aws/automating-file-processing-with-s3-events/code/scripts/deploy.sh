#!/bin/bash

# S3 Event Notifications Automated Processing - Deployment Script
# This script deploys the complete event-driven architecture for S3 file processing

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log "Checking AWS CLI authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured or credentials are invalid"
        error "Please run 'aws configure' or set up your credentials"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    
    if [ -z "$region" ]; then
        error "AWS region is not configured"
        error "Please run 'aws configure set region <your-region>'"
        exit 1
    fi
    
    success "AWS authentication verified (Account: $account_id, Region: $region)"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed"
        error "Please install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $aws_version"
    
    # Check if jq is available (optional but helpful)
    if ! command_exists jq; then
        warning "jq is not installed. JSON output will be less readable"
        warning "Consider installing jq for better output formatting"
    fi
    
    # Check if zip is available
    if ! command_exists zip; then
        error "zip command is not available"
        error "Please install zip utility"
        exit 1
    fi
    
    # Check AWS authentication
    check_aws_auth
    
    success "All prerequisites checked successfully"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Export AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    export BUCKET_NAME="file-processing-demo-${random_suffix}"
    export SNS_TOPIC_NAME="file-processing-notifications-${random_suffix}"
    export SQS_QUEUE_NAME="file-processing-queue-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="file-processor-${random_suffix}"
    
    # Create temporary directory for files
    export TEMP_DIR=$(mktemp -d)
    
    log "Environment variables set:"
    log "  AWS_REGION: $AWS_REGION"
    log "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    log "  BUCKET_NAME: $BUCKET_NAME"
    log "  SNS_TOPIC_NAME: $SNS_TOPIC_NAME"
    log "  SQS_QUEUE_NAME: $SQS_QUEUE_NAME"
    log "  LAMBDA_FUNCTION_NAME: $LAMBDA_FUNCTION_NAME"
    log "  TEMP_DIR: $TEMP_DIR"
    
    # Save environment variables to file for cleanup script
    cat > "${TEMP_DIR}/deploy_vars.env" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
BUCKET_NAME=$BUCKET_NAME
SNS_TOPIC_NAME=$SNS_TOPIC_NAME
SQS_QUEUE_NAME=$SQS_QUEUE_NAME
LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
EOF
    
    success "Environment setup completed"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket: $BUCKET_NAME..."
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        warning "S3 bucket $BUCKET_NAME already exists, skipping creation"
        return 0
    fi
    
    # Create bucket with region-specific configuration
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://${BUCKET_NAME}"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"
    fi
    
    # Wait for bucket to be available
    log "Waiting for bucket to be available..."
    aws s3api wait bucket-exists --bucket "$BUCKET_NAME"
    
    success "S3 bucket created: $BUCKET_NAME"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic: $SNS_TOPIC_NAME..."
    
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query TopicArn --output text)
    
    log "SNS Topic ARN: $SNS_TOPIC_ARN"
    
    # Add topic ARN to environment file
    echo "SNS_TOPIC_ARN=$SNS_TOPIC_ARN" >> "${TEMP_DIR}/deploy_vars.env"
    
    success "SNS topic created: $SNS_TOPIC_ARN"
}

# Function to create SQS queue
create_sqs_queue() {
    log "Creating SQS queue: $SQS_QUEUE_NAME..."
    
    export SQS_QUEUE_URL=$(aws sqs create-queue \
        --queue-name "$SQS_QUEUE_NAME" \
        --query QueueUrl --output text)
    
    # Get queue ARN
    export SQS_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url "$SQS_QUEUE_URL" \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)
    
    log "SQS Queue URL: $SQS_QUEUE_URL"
    log "SQS Queue ARN: $SQS_QUEUE_ARN"
    
    # Add queue details to environment file
    echo "SQS_QUEUE_URL=$SQS_QUEUE_URL" >> "${TEMP_DIR}/deploy_vars.env"
    echo "SQS_QUEUE_ARN=$SQS_QUEUE_ARN" >> "${TEMP_DIR}/deploy_vars.env"
    
    success "SQS queue created: $SQS_QUEUE_ARN"
}

# Function to create IAM role for Lambda
create_lambda_iam_role() {
    log "Creating IAM role for Lambda function..."
    
    local role_name="${LAMBDA_FUNCTION_NAME}-role"
    
    # Check if role already exists
    if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
        warning "IAM role $role_name already exists, skipping creation"
        export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_name}"
        echo "LAMBDA_ROLE_ARN=$LAMBDA_ROLE_ARN" >> "${TEMP_DIR}/deploy_vars.env"
        return 0
    fi
    
    # Create trust policy for Lambda
    cat > "${TEMP_DIR}/lambda-trust-policy.json" << EOF
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
        --role-name "$role_name" \
        --assume-role-policy-document "file://${TEMP_DIR}/lambda-trust-policy.json" \
        --description "Execution role for S3 event processing Lambda function"
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_name}"
    
    # Add role ARN to environment file
    echo "LAMBDA_ROLE_ARN=$LAMBDA_ROLE_ARN" >> "${TEMP_DIR}/deploy_vars.env"
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
    
    success "Lambda IAM role created: $LAMBDA_ROLE_ARN"
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function: $LAMBDA_FUNCTION_NAME..."
    
    # Check if function already exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        warning "Lambda function $LAMBDA_FUNCTION_NAME already exists, updating code..."
        
        # Create the updated function code
        create_lambda_code
        
        # Update the function code
        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --zip-file "fileb://${TEMP_DIR}/function.zip"
        
        success "Lambda function code updated"
        return 0
    fi
    
    # Create Lambda function code
    create_lambda_code
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler file-processor.lambda_handler \
        --zip-file "fileb://${TEMP_DIR}/function.zip" \
        --timeout 30 \
        --memory-size 128 \
        --description "S3 event processing function for automated file workflows"
    
    # Wait for function to be available
    log "Waiting for Lambda function to be available..."
    aws lambda wait function-active --function-name "$LAMBDA_FUNCTION_NAME"
    
    success "Lambda function created: $LAMBDA_FUNCTION_NAME"
}

# Function to create Lambda function code
create_lambda_code() {
    log "Creating Lambda function code..."
    
    # Create Lambda function code
    cat > "${TEMP_DIR}/file-processor.py" << 'EOF'
import json
import boto3
import urllib.parse
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process S3 events for automated file workflows.
    Supports image, video, and document processing scenarios.
    """
    logger.info(f"Received event: {json.dumps(event, indent=2)}")
    
    processed_files = []
    
    try:
        for record in event['Records']:
            # Parse S3 event details
            bucket = record['s3']['bucket']['name']
            key = urllib.parse.unquote_plus(record['s3']['object']['key'])
            size = record['s3']['object']['size']
            event_name = record['eventName']
            event_time = record['eventTime']
            
            logger.info(f"Processing {event_name} for {key} in bucket {bucket}")
            logger.info(f"File size: {size} bytes, Event time: {event_time}")
            
            # Process based on file type
            processing_result = process_file_by_type(key, size, bucket)
            
            processed_files.append({
                'bucket': bucket,
                'key': key,
                'size': size,
                'event_name': event_name,
                'processing_result': processing_result,
                'processed_at': datetime.now().isoformat()
            })
            
            logger.info(f"Successfully processed {key}")
    
    except Exception as e:
        logger.error(f"Error processing S3 event: {str(e)}")
        raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'File processing completed successfully',
            'processed_files': processed_files
        }, indent=2)
    }

def process_file_by_type(file_key, file_size, bucket_name):
    """
    Determine processing workflow based on file type.
    This is a simulation - replace with actual processing logic.
    """
    file_key_lower = file_key.lower()
    
    if file_key_lower.endswith(('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff')):
        return process_image_file(file_key, file_size, bucket_name)
    elif file_key_lower.endswith(('.mp4', '.mov', '.avi', '.mkv', '.wmv', '.flv')):
        return process_video_file(file_key, file_size, bucket_name)
    elif file_key_lower.endswith(('.pdf', '.doc', '.docx', '.txt', '.csv', '.xlsx')):
        return process_document_file(file_key, file_size, bucket_name)
    elif file_key_lower.endswith(('.zip', '.tar', '.gz', '.rar')):
        return process_archive_file(file_key, file_size, bucket_name)
    else:
        return process_generic_file(file_key, file_size, bucket_name)

def process_image_file(file_key, file_size, bucket_name):
    """Simulate image processing workflow."""
    logger.info(f"Image processing workflow for {file_key}")
    
    # Simulate processing tasks
    tasks = [
        "Generate thumbnail",
        "Extract EXIF metadata",
        "Perform image optimization",
        "Run content moderation scan"
    ]
    
    return {
        'file_type': 'image',
        'processing_tasks': tasks,
        'estimated_processing_time': '2-5 seconds',
        'output_formats': ['thumbnail.jpg', 'metadata.json', 'optimized.jpg']
    }

def process_video_file(file_key, file_size, bucket_name):
    """Simulate video processing workflow."""
    logger.info(f"Video processing workflow for {file_key}")
    
    # Simulate processing tasks
    tasks = [
        "Extract video metadata",
        "Generate video thumbnails",
        "Create preview clips",
        "Initiate transcoding pipeline"
    ]
    
    return {
        'file_type': 'video',
        'processing_tasks': tasks,
        'estimated_processing_time': f'{file_size // 1000000} minutes',
        'output_formats': ['thumbnail.jpg', 'preview.mp4', 'metadata.json']
    }

def process_document_file(file_key, file_size, bucket_name):
    """Simulate document processing workflow."""
    logger.info(f"Document processing workflow for {file_key}")
    
    # Simulate processing tasks
    tasks = [
        "Extract text content",
        "Generate document preview",
        "Perform OCR if needed",
        "Index for search"
    ]
    
    return {
        'file_type': 'document',
        'processing_tasks': tasks,
        'estimated_processing_time': '5-10 seconds',
        'output_formats': ['text.txt', 'preview.pdf', 'search_index.json']
    }

def process_archive_file(file_key, file_size, bucket_name):
    """Simulate archive processing workflow."""
    logger.info(f"Archive processing workflow for {file_key}")
    
    # Simulate processing tasks
    tasks = [
        "List archive contents",
        "Scan for malware",
        "Extract metadata",
        "Queue individual files for processing"
    ]
    
    return {
        'file_type': 'archive',
        'processing_tasks': tasks,
        'estimated_processing_time': f'{file_size // 100000} seconds',
        'output_formats': ['contents.json', 'scan_results.json']
    }

def process_generic_file(file_key, file_size, bucket_name):
    """Simulate generic file processing workflow."""
    logger.info(f"Generic file processing workflow for {file_key}")
    
    # Simulate processing tasks
    tasks = [
        "Analyze file type",
        "Extract basic metadata",
        "Perform virus scan",
        "Log for manual review"
    ]
    
    return {
        'file_type': 'unknown',
        'processing_tasks': tasks,
        'estimated_processing_time': '1-2 seconds',
        'output_formats': ['metadata.json', 'analysis.json']
    }
EOF
    
    # Create deployment package
    cd "$TEMP_DIR" && zip function.zip file-processor.py
    
    success "Lambda function code created"
}

# Function to configure service permissions
configure_service_permissions() {
    log "Configuring service permissions..."
    
    # Configure SNS topic policy for S3
    log "Setting SNS topic policy..."
    cat > "${TEMP_DIR}/sns-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "s3.amazonaws.com"
            },
            "Action": "SNS:Publish",
            "Resource": "${SNS_TOPIC_ARN}",
            "Condition": {
                "ArnEquals": {
                    "aws:SourceArn": "arn:aws:s3:::${BUCKET_NAME}"
                }
            }
        }
    ]
}
EOF
    
    aws sns set-topic-attributes \
        --topic-arn "$SNS_TOPIC_ARN" \
        --attribute-name Policy \
        --attribute-value "file://${TEMP_DIR}/sns-policy.json"
    
    # Configure SQS queue policy for S3
    log "Setting SQS queue policy..."
    cat > "${TEMP_DIR}/sqs-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "s3.amazonaws.com"
            },
            "Action": "SQS:SendMessage",
            "Resource": "${SQS_QUEUE_ARN}",
            "Condition": {
                "ArnEquals": {
                    "aws:SourceArn": "arn:aws:s3:::${BUCKET_NAME}"
                }
            }
        }
    ]
}
EOF
    
    aws sqs set-queue-attributes \
        --queue-url "$SQS_QUEUE_URL" \
        --attributes "file://${TEMP_DIR}/sqs-policy.json"
    
    # Grant S3 permission to invoke Lambda
    log "Granting S3 permission to invoke Lambda..."
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --statement-id s3-trigger-permission \
        --source-arn "arn:aws:s3:::${BUCKET_NAME}" \
        --output text || warning "Permission may already exist"
    
    success "Service permissions configured"
}

# Function to configure S3 event notifications
configure_s3_notifications() {
    log "Configuring S3 event notifications..."
    
    # Create notification configuration
    cat > "${TEMP_DIR}/notification-config.json" << EOF
{
    "TopicConfigurations": [
        {
            "Id": "file-upload-notification",
            "TopicArn": "${SNS_TOPIC_ARN}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "uploads/"
                        }
                    ]
                }
            }
        }
    ],
    "QueueConfigurations": [
        {
            "Id": "batch-processing-queue",
            "QueueArn": "${SQS_QUEUE_ARN}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "batch/"
                        }
                    ]
                }
            }
        }
    ],
    "LambdaConfigurations": [
        {
            "Id": "immediate-processing",
            "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "immediate/"
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
        --bucket "$BUCKET_NAME" \
        --notification-configuration "file://${TEMP_DIR}/notification-config.json"
    
    success "S3 event notifications configured"
}

# Function to create directory structure
create_directory_structure() {
    log "Creating S3 directory structure..."
    
    # Create test directories in S3
    aws s3api put-object --bucket "$BUCKET_NAME" --key uploads/ --content-length 0
    aws s3api put-object --bucket "$BUCKET_NAME" --key batch/ --content-length 0
    aws s3api put-object --bucket "$BUCKET_NAME" --key immediate/ --content-length 0
    
    success "Directory structure created"
}

# Function to create CloudWatch log group
create_cloudwatch_logs() {
    log "Creating CloudWatch log group..."
    
    local log_group_name="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
    
    # Check if log group already exists
    if aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --query 'logGroups[?logGroupName==`'$log_group_name'`]' --output text | grep -q "$log_group_name"; then
        warning "CloudWatch log group already exists"
        return 0
    fi
    
    aws logs create-log-group --log-group-name "$log_group_name"
    
    # Set retention policy (optional)
    aws logs put-retention-policy \
        --log-group-name "$log_group_name" \
        --retention-in-days 14
    
    success "CloudWatch log group created with 14-day retention"
}

# Function to run deployment tests
run_deployment_tests() {
    log "Running deployment validation tests..."
    
    # Test 1: Verify S3 bucket exists and is accessible
    log "Testing S3 bucket accessibility..."
    if aws s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
        success "✓ S3 bucket is accessible"
    else
        error "✗ S3 bucket is not accessible"
        return 1
    fi
    
    # Test 2: Verify SNS topic exists
    log "Testing SNS topic..."
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" >/dev/null 2>&1; then
        success "✓ SNS topic is accessible"
    else
        error "✗ SNS topic is not accessible"
        return 1
    fi
    
    # Test 3: Verify SQS queue exists
    log "Testing SQS queue..."
    if aws sqs get-queue-attributes --queue-url "$SQS_QUEUE_URL" >/dev/null 2>&1; then
        success "✓ SQS queue is accessible"
    else
        error "✗ SQS queue is not accessible"
        return 1
    fi
    
    # Test 4: Verify Lambda function exists
    log "Testing Lambda function..."
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        success "✓ Lambda function is accessible"
    else
        error "✗ Lambda function is not accessible"
        return 1
    fi
    
    # Test 5: Check S3 notification configuration
    log "Testing S3 notification configuration..."
    local config_output=$(aws s3api get-bucket-notification-configuration --bucket "$BUCKET_NAME" 2>/dev/null)
    if echo "$config_output" | grep -q "LambdaConfigurations\|TopicConfigurations\|QueueConfigurations"; then
        success "✓ S3 event notifications are configured"
    else
        error "✗ S3 event notifications are not properly configured"
        return 1
    fi
    
    success "All deployment tests passed!"
}

# Function to display deployment summary
display_deployment_summary() {
    log "Deployment Summary"
    echo "===================="
    echo
    echo "🎉 S3 Event Notifications Architecture Deployed Successfully!"
    echo
    echo "📋 Resources Created:"
    echo "  • S3 Bucket: $BUCKET_NAME"
    echo "  • SNS Topic: $SNS_TOPIC_ARN"
    echo "  • SQS Queue: $SQS_QUEUE_ARN"
    echo "  • Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "  • IAM Role: ${LAMBDA_FUNCTION_NAME}-role"
    echo "  • CloudWatch Log Group: /aws/lambda/${LAMBDA_FUNCTION_NAME}"
    echo
    echo "🔄 Event Routing Configuration:"
    echo "  • uploads/    → SNS Topic (notifications)"
    echo "  • batch/      → SQS Queue (batch processing)"
    echo "  • immediate/  → Lambda Function (real-time processing)"
    echo
    echo "🧪 Test Your Deployment:"
    echo "  # Test SNS notifications"
    echo "  aws s3 cp test-file.txt s3://${BUCKET_NAME}/uploads/"
    echo
    echo "  # Test SQS batch processing"
    echo "  aws s3 cp test-file.txt s3://${BUCKET_NAME}/batch/"
    echo
    echo "  # Test Lambda immediate processing"
    echo "  aws s3 cp test-file.txt s3://${BUCKET_NAME}/immediate/"
    echo
    echo "📊 Monitor Your Architecture:"
    echo "  • CloudWatch Logs: /aws/lambda/${LAMBDA_FUNCTION_NAME}"
    echo "  • SQS Queue Messages: ${SQS_QUEUE_URL}"
    echo "  • SNS Topic Metrics: ${SNS_TOPIC_ARN}"
    echo
    echo "🧹 Cleanup:"
    echo "  Run ./destroy.sh to remove all resources"
    echo
    echo "Environment variables saved to: ${TEMP_DIR}/deploy_vars.env"
    echo "Keep this file for cleanup operations."
    echo
}

# Function to save deployment state
save_deployment_state() {
    local state_file="$(dirname "$0")/deployment_state.env"
    
    log "Saving deployment state to $state_file..."
    
    cp "${TEMP_DIR}/deploy_vars.env" "$state_file"
    echo "DEPLOYMENT_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$state_file"
    echo "TEMP_DIR=$TEMP_DIR" >> "$state_file"
    
    success "Deployment state saved to $state_file"
}

# Function to handle cleanup on error
cleanup_on_error() {
    error "Deployment failed. Starting cleanup..."
    
    # Source the environment variables if they exist
    if [ -f "${TEMP_DIR}/deploy_vars.env" ]; then
        source "${TEMP_DIR}/deploy_vars.env"
        
        # Run cleanup (this script should handle partial deployments)
        if [ -f "$(dirname "$0")/destroy.sh" ]; then
            bash "$(dirname "$0")/destroy.sh" --force
        fi
    fi
    
    # Clean up temporary directory
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    
    error "Cleanup completed after deployment failure"
    exit 1
}

# Main deployment function
main() {
    echo "🚀 Starting S3 Event Notifications Deployment"
    echo "=============================================="
    echo
    
    # Set trap for error handling
    trap cleanup_on_error ERR
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Deploy infrastructure components
    create_s3_bucket
    create_sns_topic
    create_sqs_queue
    create_lambda_iam_role
    create_lambda_function
    configure_service_permissions
    configure_s3_notifications
    create_directory_structure
    create_cloudwatch_logs
    
    # Validate deployment
    run_deployment_tests
    
    # Save deployment state
    save_deployment_state
    
    # Display summary
    display_deployment_summary
    
    success "🎉 Deployment completed successfully!"
}

# Run main function
main "$@"