#!/bin/bash

# Simple Password Generator with Lambda and S3 - Deployment Script
# This script deploys a serverless password generator using AWS Lambda and S3
# Author: AWS Recipe Generator
# Version: 1.1

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI and configure it."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid. Please run 'aws configure'."
        exit 1
    fi
    
    # Check if python3 is available
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install Python 3."
        exit 1
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        log_error "zip utility is not installed. Please install zip."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to setup environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        log_error "AWS region not configured. Please set your default region with 'aws configure'."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
        log_error "Unable to determine AWS Account ID. Please check your AWS credentials."
        exit 1
    fi
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names with validation
    export BUCKET_NAME="password-generator-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="password-generator-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="lambda-password-generator-role-${RANDOM_SUFFIX}"
    
    # Validate resource names
    if [[ ${#BUCKET_NAME} -gt 63 ]]; then
        log_error "Bucket name too long: ${BUCKET_NAME}"
        exit 1
    fi
    
    log_success "Environment configured with region: ${AWS_REGION}"
    log_success "Resources will use suffix: ${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > "${PWD}/.deploy_env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
BUCKET_NAME=${BUCKET_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
IAM_ROLE_NAME=${IAM_ROLE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
}

# Function to create S3 bucket
create_s3_bucket() {
    log_info "Creating S3 bucket for password storage..."
    
    # Check if bucket already exists
    if aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
        log_warning "S3 bucket ${BUCKET_NAME} already exists. Skipping creation."
        return 0
    fi
    
    # Create S3 bucket with encryption enabled
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
        aws s3 mb "s3://${BUCKET_NAME}"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
    fi
    
    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "${BUCKET_NAME}" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    # Enable versioning for password history
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    # Block public access for security
    aws s3api put-public-access-block \
        --bucket "${BUCKET_NAME}" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    
    log_success "S3 bucket created: ${BUCKET_NAME}"
}

# Function to create IAM role
create_iam_role() {
    log_info "Creating IAM role for Lambda function..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        log_warning "IAM role ${IAM_ROLE_NAME} already exists. Skipping creation."
        return 0
    fi
    
    # Create trust policy for Lambda
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
    
    # Create IAM role
    aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document file://trust-policy.json \
        --description "IAM role for password generator Lambda function"
    
    # Create custom policy for S3 access
    cat > lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
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
    
    # Attach custom policy to role
    aws iam put-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-name LambdaPasswordGeneratorPolicy \
        --policy-document file://lambda-policy.json
    
    log_success "IAM role created: ${IAM_ROLE_NAME}"
}

# Function to create Lambda function code
create_lambda_code() {
    log_info "Creating Lambda function code..."
    
    # Create the Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import secrets
import string
from datetime import datetime
import logging
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize S3 client
s3_client = boto3.client('s3')
BUCKET_NAME = os.environ['BUCKET_NAME']

def lambda_handler(event, context):
    try:
        # Parse request parameters
        body = json.loads(event.get('body', '{}')) if event.get('body') else event
        
        # Default password parameters
        length = body.get('length', 16)
        include_uppercase = body.get('include_uppercase', True)
        include_lowercase = body.get('include_lowercase', True)
        include_numbers = body.get('include_numbers', True)
        include_symbols = body.get('include_symbols', True)
        password_name = body.get('name', f'password_{datetime.now().strftime("%Y%m%d_%H%M%S")}')
        
        # Validate parameters
        if length < 8 or length > 128:
            raise ValueError("Password length must be between 8 and 128 characters")
        
        # Build character set
        charset = ""
        if include_lowercase:
            charset += string.ascii_lowercase
        if include_uppercase:
            charset += string.ascii_uppercase
        if include_numbers:
            charset += string.digits
        if include_symbols:
            charset += "!@#$%^&*()_+-=[]{}|;:,.<>?"
        
        if not charset:
            raise ValueError("At least one character type must be selected")
        
        # Generate secure password
        password = ''.join(secrets.choice(charset) for _ in range(length))
        
        # Create password metadata
        password_data = {
            'password': password,
            'length': length,
            'created_at': datetime.now().isoformat(),
            'parameters': {
                'include_uppercase': include_uppercase,
                'include_lowercase': include_lowercase,
                'include_numbers': include_numbers,
                'include_symbols': include_symbols
            }
        }
        
        # Store password in S3
        s3_key = f'passwords/{password_name}.json'
        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=s3_key,
            Body=json.dumps(password_data, indent=2),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        
        logger.info(f"Password generated and stored: {s3_key}")
        
        # Return response (without actual password for security)
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Password generated successfully',
                'password_name': password_name,
                's3_key': s3_key,
                'length': length,
                'created_at': password_data['created_at']
            })
        }
        
    except Exception as e:
        logger.error(f"Error generating password: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Failed to generate password',
                'message': str(e)
            })
        }
EOF
    
    log_success "Lambda function code created"
}

# Function to deploy Lambda function
deploy_lambda_function() {
    log_info "Packaging and deploying Lambda function..."
    
    # Check if function already exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} already exists. Updating code..."
        
        # Create deployment package
        zip -q lambda-function.zip lambda_function.py
        
        # Update function code
        aws lambda update-function-code \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --zip-file fileb://lambda-function.zip
        
        # Update environment variables
        aws lambda update-function-configuration \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --environment "Variables={BUCKET_NAME=${BUCKET_NAME}}"
        
        log_success "Lambda function updated: ${LAMBDA_FUNCTION_NAME}"
        return 0
    fi
    
    # Create deployment package
    zip -q lambda-function.zip lambda_function.py
    
    # Get IAM role ARN
    ROLE_ARN=$(aws iam get-role \
        --role-name "${IAM_ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    
    # Wait for role to be ready
    log_info "Waiting for IAM role to be ready..."
    sleep 15
    
    # Create Lambda function with retry logic
    local max_retries=3
    local retry_count=0
    
    while [[ ${retry_count} -lt ${max_retries} ]]; do
        if aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime python3.12 \
            --role "${ROLE_ARN}" \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://lambda-function.zip \
            --timeout 30 \
            --memory-size 128 \
            --environment "Variables={BUCKET_NAME=${BUCKET_NAME}}" \
            --description "Secure password generator with S3 storage" &> /dev/null; then
            break
        else
            retry_count=$((retry_count + 1))
            if [[ ${retry_count} -eq ${max_retries} ]]; then
                log_error "Failed to create Lambda function after ${max_retries} attempts"
                exit 1
            fi
            log_warning "Lambda creation failed, retrying in 10 seconds... (${retry_count}/${max_retries})"
            sleep 10
        fi
    done
    
    log_success "Lambda function deployed: ${LAMBDA_FUNCTION_NAME}"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing password generation..."
    
    # Test with default parameters
    if aws lambda invoke \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --payload '{"length": 20, "name": "test-password-1"}' \
        response.json &> /dev/null; then
        
        # Display the response
        if [[ -f response.json ]]; then
            log_info "Test response:"
            cat response.json | python3 -m json.tool 2>/dev/null || cat response.json
        fi
        
        log_success "Password generation test completed successfully"
    else
        log_error "Password generation test failed"
        return 1
    fi
    
    # Test S3 bucket content
    log_info "Verifying S3 storage..."
    if aws s3 ls "s3://${BUCKET_NAME}/passwords/" &> /dev/null; then
        log_success "Passwords successfully stored in S3"
    else
        log_warning "No passwords found in S3 bucket"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    rm -f trust-policy.json lambda-policy.json lambda_function.py lambda-function.zip response.json
    log_success "Temporary files cleaned up"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "AWS Region: ${AWS_REGION}"
    echo "S3 Bucket: ${BUCKET_NAME}"
    echo "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "IAM Role: ${IAM_ROLE_NAME}"
    echo
    echo "=== USAGE EXAMPLES ==="
    echo "1. Generate a simple password:"
    echo "   aws lambda invoke --function-name ${LAMBDA_FUNCTION_NAME} --payload '{\"length\": 16}' response.json"
    echo
    echo "2. Generate a complex password:"
    echo "   aws lambda invoke --function-name ${LAMBDA_FUNCTION_NAME} --payload '{\"length\": 24, \"name\": \"my-secure-password\"}' response.json"
    echo
    echo "3. List generated passwords:"
    echo "   aws s3 ls s3://${BUCKET_NAME}/passwords/"
    echo
    echo "4. Retrieve a password:"
    echo "   aws s3 cp s3://${BUCKET_NAME}/passwords/test-password-1.json ./"
    echo
    echo "=== CLEANUP ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo
}

# Main execution
main() {
    log_info "Starting deployment of Simple Password Generator with Lambda and S3"
    echo
    
    # Check if dry run is requested
    if [[ "${1:-}" == "--dry-run" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        return 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_iam_role
    create_lambda_code
    deploy_lambda_function
    test_deployment
    cleanup_temp_files
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Deployment interrupted. Run destroy.sh to clean up any partially created resources."; exit 1' INT TERM

# Run main function with all arguments
main "$@"