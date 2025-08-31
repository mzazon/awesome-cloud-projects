#!/bin/bash

# Simple Image Metadata Extractor with Lambda and S3 - Deployment Script
# This script deploys a serverless image metadata extraction system using AWS Lambda and S3

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
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if Python and pip are available
    if ! command -v python3 &> /dev/null; then
        log_error "Python3 is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        log_error "pip is not installed. Please install it first."
        exit 1
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        log_error "zip utility is not installed. Please install it first."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_warning "AWS region not set in configuration. Using us-east-1 as default."
        export AWS_REGION="us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export BUCKET_NAME="image-metadata-bucket-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="image-metadata-extractor-${RANDOM_SUFFIX}"
    export ROLE_NAME="lambda-s3-metadata-role-${RANDOM_SUFFIX}"
    export LAYER_NAME="pillow-image-processing-${RANDOM_SUFFIX}"
    
    log_success "Environment configured"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "Bucket Name: ${BUCKET_NAME}"
    log_info "Function Name: ${FUNCTION_NAME}"
    log_info "Role Name: ${ROLE_NAME}"
}

# Function to create S3 bucket
create_s3_bucket() {
    log_info "Creating S3 bucket: ${BUCKET_NAME}"
    
    # Create S3 bucket
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb s3://${BUCKET_NAME}
    else
        aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket ${BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket ${BUCKET_NAME} \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    log_success "S3 bucket created and configured: ${BUCKET_NAME}"
}

# Function to create IAM role
create_iam_role() {
    log_info "Creating IAM role: ${ROLE_NAME}"
    
    # Create trust policy for Lambda service
    cat > /tmp/lambda-trust-policy.json << 'EOF'
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
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json
    
    # Get role ARN
    export ROLE_ARN=$(aws iam get-role --role-name ${ROLE_NAME} \
        --query Role.Arn --output text)
    
    log_success "IAM role created: ${ROLE_NAME}"
    log_info "Role ARN: ${ROLE_ARN}"
}

# Function to attach policies to IAM role
attach_iam_policies() {
    log_info "Attaching IAM policies to role: ${ROLE_NAME}"
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for S3 read access
    cat > /tmp/s3-read-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-name S3ReadPolicy \
        --policy-document file:///tmp/s3-read-policy.json
    
    log_success "IAM policies attached"
}

# Function to create Lambda layer
create_lambda_layer() {
    log_info "Creating Lambda layer with Pillow library"
    
    # Create temporary directory for layer
    mkdir -p /tmp/lambda-layer/python
    cd /tmp/lambda-layer
    
    # Install Pillow library for the layer
    if command -v pip3 &> /dev/null; then
        pip3 install Pillow -t python/ --platform manylinux2014_x86_64 \
            --implementation cp --python-version 3.12 --only-binary=:all:
    else
        pip install Pillow -t python/ --platform manylinux2014_x86_64 \
            --implementation cp --python-version 3.12 --only-binary=:all:
    fi
    
    # Create layer zip file
    zip -r pillow-layer.zip python/
    
    # Create Lambda layer
    export LAYER_ARN=$(aws lambda publish-layer-version \
        --layer-name ${LAYER_NAME} \
        --description "PIL/Pillow library for image processing" \
        --zip-file fileb://pillow-layer.zip \
        --compatible-runtimes python3.12 python3.11 python3.10 \
        --query LayerVersionArn --output text)
    
    log_success "Lambda layer created: ${LAYER_ARN}"
}

# Function to create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function: ${FUNCTION_NAME}"
    
    # Create temporary directory for function
    mkdir -p /tmp/lambda-function
    cd /tmp/lambda-function
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import logging
from PIL import Image
from urllib.parse import unquote_plus
import io

# Initialize S3 client outside handler for reuse
s3_client = boto3.client('s3')

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Main Lambda handler for S3 image upload events
    Extracts metadata from uploaded images
    """
    try:
        # Process each S3 event record
        for record in event['Records']:
            # Get bucket and object key from S3 event
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing image: {key} from bucket: {bucket}")
            
            # Download image from S3
            response = s3_client.get_object(Bucket=bucket, Key=key)
            image_content = response['Body'].read()
            
            # Extract metadata
            metadata = extract_image_metadata(image_content, key)
            
            # Log extracted metadata
            logger.info(f"Extracted metadata for {key}: {json.dumps(metadata, indent=2)}")
            
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed images')
        }
        
    except Exception as e:
        logger.error(f"Error processing image: {str(e)}")
        raise

def extract_image_metadata(image_content, filename):
    """
    Extract comprehensive metadata from image content
    """
    try:
        # Open image with PIL
        with Image.open(io.BytesIO(image_content)) as img:
            metadata = {
                'filename': filename,
                'format': img.format,
                'mode': img.mode,
                'size': img.size,
                'width': img.width,
                'height': img.height,
                'file_size_bytes': len(image_content),
                'file_size_kb': round(len(image_content) / 1024, 2),
                'aspect_ratio': round(img.width / img.height, 2) if img.height > 0 else 0
            }
            
            # Extract EXIF data if available using getexif()
            try:
                exif_dict = img.getexif()
                if exif_dict:
                    metadata['has_exif'] = True
                    metadata['exif_tags_count'] = len(exif_dict)
                else:
                    metadata['has_exif'] = False
            except Exception:
                metadata['has_exif'] = False
                
            return metadata
            
    except Exception as e:
        logger.error(f"Error extracting metadata: {str(e)}")
        return {
            'filename': filename,
            'error': str(e),
            'file_size_bytes': len(image_content)
        }
EOF
    
    # Create deployment package
    zip -r function.zip lambda_function.py
    
    # Wait for IAM role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 15
    
    # Create Lambda function
    aws lambda create-function \
        --function-name ${FUNCTION_NAME} \
        --runtime python3.12 \
        --role ${ROLE_ARN} \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://function.zip \
        --description "Extract metadata from uploaded images" \
        --timeout 30 \
        --memory-size 256 \
        --layers ${LAYER_ARN}
    
    log_success "Lambda function created: ${FUNCTION_NAME}"
}

# Function to configure S3 event trigger
configure_s3_trigger() {
    log_info "Configuring S3 event trigger"
    
    # Add permission for S3 to invoke Lambda
    aws lambda add-permission \
        --function-name ${FUNCTION_NAME} \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --source-arn arn:aws:s3:::${BUCKET_NAME} \
        --statement-id s3-trigger-permission
    
    # Create notification configuration
    cat > /tmp/notification.json << EOF
{
    "LambdaConfigurations": [
        {
            "Id": "ImageUploadTriggerJPG",
            "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${FUNCTION_NAME}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".jpg"
                        }
                    ]
                }
            }
        },
        {
            "Id": "ImageUploadTriggerJPEG",
            "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${FUNCTION_NAME}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".jpeg"
                        }
                    ]
                }
            }
        },
        {
            "Id": "ImageUploadTriggerPNG",
            "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${FUNCTION_NAME}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".png"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
    
    # Configure S3 notification
    aws s3api put-bucket-notification-configuration \
        --bucket ${BUCKET_NAME} \
        --notification-configuration file:///tmp/notification.json
    
    log_success "S3 event trigger configured"
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information"
    
    cat > /tmp/deployment-info.json << EOF
{
    "deployment_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "bucket_name": "${BUCKET_NAME}",
    "function_name": "${FUNCTION_NAME}",
    "role_name": "${ROLE_NAME}",
    "role_arn": "${ROLE_ARN}",
    "layer_name": "${LAYER_NAME}",
    "layer_arn": "${LAYER_ARN}"
}
EOF
    
    # Copy deployment info to current directory if not in /tmp
    if [ "$PWD" != "/tmp" ]; then
        cp /tmp/deployment-info.json ./deployment-info.json
        log_success "Deployment information saved to ./deployment-info.json"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files"
    
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/s3-read-policy.json
    rm -f /tmp/notification.json
    rm -rf /tmp/lambda-layer
    rm -rf /tmp/lambda-function
    
    log_success "Temporary files cleaned up"
}

# Function to display deployment summary
display_summary() {
    log_success "===== DEPLOYMENT COMPLETE ====="
    log_info "Resources created:"
    log_info "  • S3 Bucket: ${BUCKET_NAME}"
    log_info "  • Lambda Function: ${FUNCTION_NAME}"
    log_info "  • IAM Role: ${ROLE_NAME}"
    log_info "  • Lambda Layer: ${LAYER_NAME}"
    log_info ""
    log_info "To test the deployment:"
    log_info "  1. Upload an image file (JPG, JPEG, or PNG) to the S3 bucket:"
    log_info "     aws s3 cp your-image.jpg s3://${BUCKET_NAME}/"
    log_info "  2. Check CloudWatch logs for the Lambda function:"
    log_info "     aws logs describe-log-groups --log-group-name-prefix '/aws/lambda/${FUNCTION_NAME}'"
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
    log_info "Deployment information saved to: deployment-info.json"
}

# Main deployment function
main() {
    log_info "Starting deployment of Simple Image Metadata Extractor"
    log_info "=============================================="
    
    # Check if deployment info already exists
    if [ -f "./deployment-info.json" ]; then
        log_warning "Found existing deployment-info.json"
        log_warning "This may indicate resources are already deployed."
        read -p "Continue with deployment? This may create duplicate resources. (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_iam_role
    attach_iam_policies
    create_lambda_layer
    create_lambda_function
    configure_s3_trigger
    save_deployment_info
    cleanup_temp_files
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Deployment interrupted. Some resources may have been created."; cleanup_temp_files; exit 1' INT TERM

# Run main function
main "$@"