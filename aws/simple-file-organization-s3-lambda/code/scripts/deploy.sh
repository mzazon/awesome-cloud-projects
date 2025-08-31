#!/bin/bash

# Simple File Organization with S3 and Lambda - Deployment Script
# This script deploys the infrastructure for automated file organization using S3 and Lambda

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed (for JSON parsing)
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it for JSON parsing."
        exit 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        log_error "zip command is not available. Please install zip utility."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_warning "AWS region not set in config, defaulting to us-east-1"
        export AWS_REGION="us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names
    export BUCKET_NAME="file-organizer-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="file-organizer-function-${RANDOM_SUFFIX}"
    export ROLE_NAME="file-organizer-lambda-role-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
BUCKET_NAME=${BUCKET_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
ROLE_NAME=${ROLE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment configured"
    log "AWS Region: ${AWS_REGION}"
    log "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "Bucket Name: ${BUCKET_NAME}"
    log "Function Name: ${FUNCTION_NAME}"
    log "Role Name: ${ROLE_NAME}"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for file organization..."
    
    # Create S3 bucket with region-specific configuration
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
    else
        aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
    fi
    
    # Enable versioning for file safety
    aws s3api put-bucket-versioning \
        --bucket ${BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket ${BUCKET_NAME} \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    log_success "S3 bucket created and configured: ${BUCKET_NAME}"
}

# Function to create IAM role and policies
create_iam_resources() {
    log "Creating IAM execution role for Lambda..."
    
    # Create trust policy for Lambda service
    cat > trust-policy.json << EOF
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
        --role-name ${ROLE_NAME} \
        --assume-role-policy-document file://trust-policy.json
    
    # Get role ARN for later use
    ROLE_ARN=$(aws iam get-role --role-name ${ROLE_NAME} \
        --query 'Role.Arn' --output text)
    
    log_success "IAM role created: ${ROLE_NAME}"
    
    # Attach basic Lambda execution policy for CloudWatch logs
    aws iam attach-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for S3 operations
    cat > s3-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    }
  ]
}
EOF
    
    # Create and attach custom S3 policy
    aws iam create-policy \
        --policy-name ${ROLE_NAME}-s3-policy \
        --policy-document file://s3-policy.json
    
    aws iam attach-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-s3-policy
    
    # Save role ARN to environment
    echo "ROLE_ARN=${ROLE_ARN}" >> .env
    
    log_success "IAM policies attached to role"
}

# Function to create and deploy Lambda function
create_lambda_function() {
    log "Creating Lambda function code..."
    
    # Create Python code for file organization
    cat > lambda_function.py << 'EOF'
import json
import boto3
import os
from urllib.parse import unquote_plus

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    # Process each S3 event record
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        
        # Skip if file is already in an organized folder
        if '/' in key and key.split('/')[0] in ['images', 'documents', 'videos', 'other']:
            print(f"File {key} is already organized, skipping")
            continue
        
        # Skip .gitkeep files used for folder structure
        if key.endswith('/.gitkeep'):
            print(f"Skipping folder placeholder file: {key}")
            continue
        
        # Determine file type based on extension
        file_extension = key.lower().split('.')[-1] if '.' in key else ''
        folder = get_folder_for_extension(file_extension)
        
        # Create new key with folder structure
        new_key = f"{folder}/{key}"
        
        try:
            # Copy object to new location
            s3_client.copy_object(
                Bucket=bucket,
                CopySource={'Bucket': bucket, 'Key': key},
                Key=new_key
            )
            
            # Delete original object
            s3_client.delete_object(Bucket=bucket, Key=key)
            
            print(f"Moved {key} to {new_key}")
            
        except Exception as e:
            print(f"Error moving {key}: {str(e)}")
            # Return error to trigger retry mechanism
            raise e

def get_folder_for_extension(extension):
    """Determine folder based on file extension"""
    image_extensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'tiff', 'svg', 'webp']
    document_extensions = ['pdf', 'doc', 'docx', 'txt', 'rtf', 'odt', 'xls', 'xlsx', 'ppt', 'pptx', 'csv']
    video_extensions = ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'mkv', 'm4v']
    
    if extension in image_extensions:
        return 'images'
    elif extension in document_extensions:
        return 'documents'
    elif extension in video_extensions:
        return 'videos'
    else:
        return 'other'
EOF
    
    # Create deployment package
    zip function.zip lambda_function.py
    
    log_success "Lambda function code created and packaged"
    
    # Wait for IAM role to propagate (important for new roles)
    log "Waiting for IAM role to propagate..."
    sleep 15
    
    # Create Lambda function with updated Python runtime
    aws lambda create-function \
        --function-name ${FUNCTION_NAME} \
        --runtime python3.12 \
        --role ${ROLE_ARN} \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://function.zip \
        --timeout 60 \
        --memory-size 256 \
        --description "Automatically organizes uploaded files by type"
    
    # Get function ARN for S3 trigger configuration
    FUNCTION_ARN=$(aws lambda get-function --function-name ${FUNCTION_NAME} \
        --query 'Configuration.FunctionArn' --output text)
    
    # Save function ARN to environment
    echo "FUNCTION_ARN=${FUNCTION_ARN}" >> .env
    
    log_success "Lambda function deployed: ${FUNCTION_NAME}"
    log "Function ARN: ${FUNCTION_ARN}"
}

# Function to configure S3 event notification
configure_s3_notification() {
    log "Configuring S3 event notification..."
    
    # Add permission for S3 to invoke Lambda function
    aws lambda add-permission \
        --function-name ${FUNCTION_NAME} \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --statement-id s3-trigger-${RANDOM_SUFFIX} \
        --source-arn arn:aws:s3:::${BUCKET_NAME}
    
    # Create notification configuration
    cat > notification.json << EOF
{
  "LambdaConfigurations": [
    {
      "Id": "ObjectCreatedEvents",
      "LambdaFunctionArn": "${FUNCTION_ARN}",
      "Events": ["s3:ObjectCreated:*"]
    }
  ]
}
EOF
    
    # Configure S3 bucket notification
    aws s3api put-bucket-notification-configuration \
        --bucket ${BUCKET_NAME} \
        --notification-configuration file://notification.json
    
    log_success "S3 event notification configured"
}

# Function to create folder structure
create_folder_structure() {
    log "Creating folder structure in S3 bucket..."
    
    # Create folder structure by uploading placeholder files
    echo "Images will be stored here" | \
        aws s3 cp - s3://${BUCKET_NAME}/images/.gitkeep
    echo "Documents will be stored here" | \
        aws s3 cp - s3://${BUCKET_NAME}/documents/.gitkeep
    echo "Videos will be stored here" | \
        aws s3 cp - s3://${BUCKET_NAME}/videos/.gitkeep
    echo "Other files will be stored here" | \
        aws s3 cp - s3://${BUCKET_NAME}/other/.gitkeep
    
    log_success "Folder structure created in S3 bucket"
    
    # List bucket contents to verify structure
    log "Current bucket structure:"
    aws s3 ls s3://${BUCKET_NAME}/ --recursive
}

# Function to test the deployment
test_deployment() {
    log "Testing the deployment with sample files..."
    
    # Create test files with different extensions
    echo "Sample image content" > test-image.jpg
    echo "Sample document content" > test-document.pdf
    echo "Sample video metadata" > test-video.mp4
    echo "Sample unknown file" > test-file.unknown
    
    # Upload test files to trigger organization
    aws s3 cp test-image.jpg s3://${BUCKET_NAME}/
    aws s3 cp test-document.pdf s3://${BUCKET_NAME}/
    aws s3 cp test-video.mp4 s3://${BUCKET_NAME}/
    aws s3 cp test-file.unknown s3://${BUCKET_NAME}/
    
    # Wait for Lambda processing
    log "Waiting for Lambda processing..."
    sleep 10
    
    # Verify files were organized correctly
    log "Files organized in bucket:"
    aws s3 ls s3://${BUCKET_NAME}/ --recursive
    
    # Clean up test files
    rm -f test-image.jpg test-document.pdf test-video.mp4 test-file.unknown
    
    log_success "Deployment test completed"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f trust-policy.json s3-policy.json notification.json
    rm -f lambda_function.py function.zip
    log_success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting deployment of Simple File Organization with S3 and Lambda..."
    
    # Change to script directory to handle relative paths
    cd "$(dirname "$0")"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_iam_resources
    create_lambda_function
    configure_s3_notification
    create_folder_structure
    test_deployment
    cleanup_temp_files
    
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    log ""
    log "🎉 Your file organization system is now ready!"
    log ""
    log "📁 S3 Bucket: ${BUCKET_NAME}"
    log "⚡ Lambda Function: ${FUNCTION_NAME}"
    log "🔐 IAM Role: ${ROLE_NAME}"
    log ""
    log "💡 Try uploading files to your S3 bucket - they will be automatically organized!"
    log ""
    log "🧹 To clean up resources, run: ./destroy.sh"
    log ""
    log "📊 Monitor Lambda function logs:"
    log "   aws logs tail /aws/lambda/${FUNCTION_NAME} --follow"
    log ""
}

# Error handling
trap 'log_error "Deployment failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"