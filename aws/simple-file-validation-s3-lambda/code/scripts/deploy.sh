#!/bin/bash

# Simple File Validation with S3 and Lambda - Deployment Script
# This script deploys a serverless file validation system using AWS S3 and Lambda

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log_info "Checking AWS authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not authenticated. Please run 'aws configure' first."
        exit 1
    fi
    log_success "AWS authentication verified"
}

# Function to validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if zip is available
    if ! command_exists zip; then
        log_error "zip command is not available. Please install it first."
        exit 1
    fi
    
    # Check AWS authentication
    check_aws_auth
    
    # Check if jq is available for JSON parsing (optional but helpful)
    if ! command_exists jq; then
        log_warning "jq is not installed. Some output formatting may be limited."
    fi
    
    log_success "All prerequisites validated"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region not configured. Please set it with 'aws configure' or AWS_DEFAULT_REGION environment variable."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    # Set resource names
    export UPLOAD_BUCKET_NAME="file-upload-${RANDOM_SUFFIX}"
    export VALID_BUCKET_NAME="valid-files-${RANDOM_SUFFIX}"
    export QUARANTINE_BUCKET_NAME="quarantine-files-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="file-validator-${RANDOM_SUFFIX}"
    
    log_success "Environment configured:"
    log_info "  Region: ${AWS_REGION}"
    log_info "  Account ID: ${AWS_ACCOUNT_ID}"
    log_info "  Upload bucket: ${UPLOAD_BUCKET_NAME}"
    log_info "  Valid bucket: ${VALID_BUCKET_NAME}"
    log_info "  Quarantine bucket: ${QUARANTINE_BUCKET_NAME}"
    log_info "  Lambda function: ${LAMBDA_FUNCTION_NAME}"
    
    # Save environment variables for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
UPLOAD_BUCKET_NAME=${UPLOAD_BUCKET_NAME}
VALID_BUCKET_NAME=${VALID_BUCKET_NAME}
QUARANTINE_BUCKET_NAME=${QUARANTINE_BUCKET_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
EOF
    log_info "Environment variables saved to .env file"
}

# Function to create S3 buckets
create_s3_buckets() {
    log_info "Creating S3 buckets..."
    
    # Create upload bucket
    if aws s3api head-bucket --bucket "${UPLOAD_BUCKET_NAME}" 2>/dev/null; then
        log_warning "Upload bucket ${UPLOAD_BUCKET_NAME} already exists"
    else
        aws s3 mb "s3://${UPLOAD_BUCKET_NAME}" --region "${AWS_REGION}"
        log_success "Created upload bucket: ${UPLOAD_BUCKET_NAME}"
    fi
    
    # Create valid files bucket
    if aws s3api head-bucket --bucket "${VALID_BUCKET_NAME}" 2>/dev/null; then
        log_warning "Valid files bucket ${VALID_BUCKET_NAME} already exists"
    else
        aws s3 mb "s3://${VALID_BUCKET_NAME}" --region "${AWS_REGION}"
        log_success "Created valid files bucket: ${VALID_BUCKET_NAME}"
    fi
    
    # Create quarantine bucket
    if aws s3api head-bucket --bucket "${QUARANTINE_BUCKET_NAME}" 2>/dev/null; then
        log_warning "Quarantine bucket ${QUARANTINE_BUCKET_NAME} already exists"
    else
        aws s3 mb "s3://${QUARANTINE_BUCKET_NAME}" --region "${AWS_REGION}"
        log_success "Created quarantine bucket: ${QUARANTINE_BUCKET_NAME}"
    fi
    
    # Enable versioning for upload bucket
    aws s3api put-bucket-versioning \
        --bucket "${UPLOAD_BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    log_success "Enabled versioning for upload bucket"
    
    log_success "All S3 buckets created successfully"
}

# Function to create IAM role and policies
create_iam_resources() {
    log_info "Creating IAM resources..."
    
    # Create trust policy for Lambda
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
    
    # Check if role already exists
    if aws iam get-role --role-name "${LAMBDA_FUNCTION_NAME}-role" >/dev/null 2>&1; then
        log_warning "IAM role ${LAMBDA_FUNCTION_NAME}-role already exists"
    else
        # Create IAM role
        aws iam create-role \
            --role-name "${LAMBDA_FUNCTION_NAME}-role" \
            --assume-role-policy-document file://lambda-trust-policy.json \
            --description "IAM role for file validation Lambda function"
        log_success "Created IAM role: ${LAMBDA_FUNCTION_NAME}-role"
    fi
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create S3 access policy
    cat > s3-access-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::${UPLOAD_BUCKET_NAME}/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::${VALID_BUCKET_NAME}/*",
        "arn:aws:s3:::${QUARANTINE_BUCKET_NAME}/*"
      ]
    }
  ]
}
EOF
    
    # Check if policy already exists
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_FUNCTION_NAME}-s3-policy"
    if aws iam get-policy --policy-arn "${POLICY_ARN}" >/dev/null 2>&1; then
        log_warning "S3 access policy already exists"
    else
        # Create and attach the policy
        POLICY_ARN=$(aws iam create-policy \
            --policy-name "${LAMBDA_FUNCTION_NAME}-s3-policy" \
            --policy-document file://s3-access-policy.json \
            --description "S3 access policy for file validation Lambda" \
            --query 'Policy.Arn' --output text)
        log_success "Created S3 access policy: ${POLICY_ARN}"
    fi
    
    # Attach S3 policy to role
    aws iam attach-role-policy \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --policy-arn "${POLICY_ARN}"
    
    # Save policy ARN for cleanup
    echo "${POLICY_ARN}" > policy-arn.txt
    
    log_success "IAM resources created and configured"
}

# Function to create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function..."
    
    # Create Lambda function directory
    mkdir -p lambda-function
    
    # Create Lambda function code
    cat > lambda-function/index.py << 'EOF'
import json
import boto3
import urllib.parse
import os
from datetime import datetime

s3_client = boto3.client('s3')

# Configuration
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10 MB
ALLOWED_EXTENSIONS = ['.txt', '.pdf', '.jpg', '.jpeg', '.png', '.doc', '.docx']

def lambda_handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    
    valid_bucket = os.environ['VALID_BUCKET_NAME']
    quarantine_bucket = os.environ['QUARANTINE_BUCKET_NAME']
    
    for record in event['Records']:
        # Extract S3 information
        bucket_name = record['s3']['bucket']['name']
        object_key = urllib.parse.unquote_plus(record['s3']['object']['key'])
        object_size = record['s3']['object']['size']
        
        print(f"Processing file: {object_key}, Size: {object_size} bytes")
        
        # Validate file
        validation_result = validate_file(object_key, object_size)
        
        # Move file based on validation result
        if validation_result['valid']:
            destination_bucket = valid_bucket
            print(f"✅ File {object_key} is valid")
        else:
            destination_bucket = quarantine_bucket
            print(f"❌ File {object_key} is invalid: {validation_result['reason']}")
        
        # Copy file to appropriate bucket
        copy_source = {'Bucket': bucket_name, 'Key': object_key}
        destination_key = f"{datetime.now().strftime('%Y/%m/%d')}/{object_key}"
        
        s3_client.copy_object(
            CopySource=copy_source,
            Bucket=destination_bucket,
            Key=destination_key
        )
        
        # Delete original file from upload bucket
        s3_client.delete_object(
            Bucket=bucket_name,
            Key=object_key
        )
        
        print(f"Moved {object_key} to {destination_bucket} and deleted original")
    
    return {'statusCode': 200, 'body': json.dumps('File validation completed')}

def validate_file(filename, file_size):
    # Check file size
    if file_size > MAX_FILE_SIZE:
        return {'valid': False, 'reason': f'File size {file_size} exceeds maximum {MAX_FILE_SIZE}'}
    
    # Check file extension (more robust validation)
    if '.' not in filename:
        return {'valid': False, 'reason': 'File has no extension'}
        
    file_extension = '.' + filename.lower().split('.')[-1]
    if file_extension not in ALLOWED_EXTENSIONS:
        return {'valid': False, 'reason': f'File extension {file_extension} not allowed'}
    
    return {'valid': True, 'reason': 'File passed validation'}
EOF
    
    # Create deployment package
    cd lambda-function
    zip -r ../function.zip .
    cd ..
    
    # Get IAM role ARN
    ROLE_ARN=$(aws iam get-role \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --query 'Role.Arn' --output text)
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 15
    
    # Check if Lambda function already exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} already exists, updating..."
        # Update function code
        aws lambda update-function-code \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --zip-file fileb://function.zip
        
        # Update function configuration
        aws lambda update-function-configuration \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime python3.12 \
            --timeout 60 \
            --memory-size 256 \
            --environment Variables="{VALID_BUCKET_NAME=${VALID_BUCKET_NAME},QUARANTINE_BUCKET_NAME=${QUARANTINE_BUCKET_NAME}}"
    else
        # Create Lambda function
        aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime python3.12 \
            --role "${ROLE_ARN}" \
            --handler index.lambda_handler \
            --zip-file fileb://function.zip \
            --timeout 60 \
            --memory-size 256 \
            --description "File validation function for S3 uploads" \
            --environment Variables="{VALID_BUCKET_NAME=${VALID_BUCKET_NAME},QUARANTINE_BUCKET_NAME=${QUARANTINE_BUCKET_NAME}}"
    fi
    
    log_success "Lambda function deployed: ${LAMBDA_FUNCTION_NAME}"
}

# Function to configure S3 event notification
configure_s3_events() {
    log_info "Configuring S3 event notifications..."
    
    # Add permission for S3 to invoke Lambda (idempotent)
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --statement-id s3-trigger-permission \
        --source-arn "arn:aws:s3:::${UPLOAD_BUCKET_NAME}" 2>/dev/null || \
    log_warning "Lambda permission already exists or failed to add"
    
    # Create event notification configuration
    cat > event-notification.json << EOF
{
  "LambdaConfigurations": [
    {
      "Id": "file-validation-trigger",
      "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}",
      "Events": ["s3:ObjectCreated:*"]
    }
  ]
}
EOF
    
    # Apply notification configuration
    aws s3api put-bucket-notification-configuration \
        --bucket "${UPLOAD_BUCKET_NAME}" \
        --notification-configuration file://event-notification.json
    
    log_success "S3 event notification configured"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing deployment..."
    
    # Create test files
    echo "This is a valid text file for testing" > test-valid.txt
    echo "This content has invalid extension" > test-invalid.exe
    
    # Upload valid file
    aws s3 cp test-valid.txt "s3://${UPLOAD_BUCKET_NAME}/"
    log_info "Uploaded test valid file"
    
    # Wait for processing
    log_info "Waiting for Lambda processing..."
    sleep 20
    
    # Check if file was moved to valid bucket
    if aws s3 ls "s3://${VALID_BUCKET_NAME}/" --recursive | grep -q test-valid.txt; then
        log_success "Valid file processed correctly"
    else
        log_warning "Valid file may not have been processed yet"
    fi
    
    # Upload invalid file
    aws s3 cp test-invalid.exe "s3://${UPLOAD_BUCKET_NAME}/"
    log_info "Uploaded test invalid file"
    
    # Wait for processing
    sleep 20
    
    # Check if file was moved to quarantine bucket
    if aws s3 ls "s3://${QUARANTINE_BUCKET_NAME}/" --recursive | grep -q test-invalid.exe; then
        log_success "Invalid file quarantined correctly"
    else
        log_warning "Invalid file may not have been processed yet"
    fi
    
    # Clean up test files
    rm -f test-valid.txt test-invalid.exe
    
    log_success "Deployment test completed"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    log_info "Deployment Summary:"
    log_info "  Upload Bucket: ${UPLOAD_BUCKET_NAME}"
    log_info "  Valid Files Bucket: ${VALID_BUCKET_NAME}"
    log_info "  Quarantine Bucket: ${QUARANTINE_BUCKET_NAME}"
    log_info "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log_info "  AWS Region: ${AWS_REGION}"
    echo
    log_info "To test the system:"
    log_info "  aws s3 cp <your-file> s3://${UPLOAD_BUCKET_NAME}/"
    echo
    log_info "To view logs:"
    log_info "  aws logs tail /aws/lambda/${LAMBDA_FUNCTION_NAME} --follow"
    echo
    log_info "To clean up resources:"
    log_info "  ./destroy.sh"
    echo
}

# Function to handle cleanup on error
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    
    # Remove temporary files
    rm -f lambda-trust-policy.json s3-access-policy.json event-notification.json
    rm -f policy-arn.txt function.zip test-valid.txt test-invalid.exe
    rm -rf lambda-function
    
    log_info "Temporary files cleaned up. You may need to manually clean up AWS resources."
}

# Main deployment function
main() {
    log_info "Starting Simple File Validation with S3 and Lambda deployment..."
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_buckets
    create_iam_resources
    create_lambda_function
    configure_s3_events
    test_deployment
    display_summary
    
    # Clean up temporary files
    rm -f lambda-trust-policy.json s3-access-policy.json event-notification.json
    rm -f function.zip
    rm -rf lambda-function
    
    log_success "Deployment script completed successfully!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi