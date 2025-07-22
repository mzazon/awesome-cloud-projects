#!/bin/bash

# Deploy script for Intelligent Document Summarization with Amazon Bedrock and Lambda
# This script creates all necessary AWS resources for automated document processing

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check required permissions by testing access
    log "Verifying AWS permissions..."
    if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity &> /dev/null; then
        error "Unable to verify AWS credentials."
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some features may be limited."
    fi
    
    # Check Python and pip for Lambda packaging
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed. Required for Lambda function packaging."
        exit 1
    fi
    
    if ! command -v pip &> /dev/null; then
        error "pip is not installed. Required for Lambda dependencies."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    # Set resource names
    export INPUT_BUCKET="documents-input-${RANDOM_SUFFIX}"
    export OUTPUT_BUCKET="summaries-output-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="doc-summarizer-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="DocumentSummarizerRole-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
INPUT_BUCKET=${INPUT_BUCKET}
OUTPUT_BUCKET=${OUTPUT_BUCKET}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
IAM_ROLE_NAME=${IAM_ROLE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log "Environment variables configured:"
    log "  AWS Region: ${AWS_REGION}"
    log "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "  Input Bucket: ${INPUT_BUCKET}"
    log "  Output Bucket: ${OUTPUT_BUCKET}"
    log "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    
    success "Environment setup completed"
}

# Function to create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets..."
    
    # Create input bucket
    if aws s3api head-bucket --bucket "${INPUT_BUCKET}" 2>/dev/null; then
        warning "Input bucket ${INPUT_BUCKET} already exists"
    else
        aws s3 mb "s3://${INPUT_BUCKET}" --region "${AWS_REGION}"
        success "Created input bucket: ${INPUT_BUCKET}"
    fi
    
    # Create output bucket
    if aws s3api head-bucket --bucket "${OUTPUT_BUCKET}" 2>/dev/null; then
        warning "Output bucket ${OUTPUT_BUCKET} already exists"
    else
        aws s3 mb "s3://${OUTPUT_BUCKET}" --region "${AWS_REGION}"
        success "Created output bucket: ${OUTPUT_BUCKET}"
    fi
    
    # Enable versioning on buckets for better data protection
    aws s3api put-bucket-versioning \
        --bucket "${INPUT_BUCKET}" \
        --versioning-configuration Status=Enabled
    
    aws s3api put-bucket-versioning \
        --bucket "${OUTPUT_BUCKET}" \
        --versioning-configuration Status=Enabled
    
    success "S3 buckets created and configured"
}

# Function to check Bedrock access
check_bedrock_access() {
    log "Checking Amazon Bedrock access..."
    
    # Check if Claude model is available
    if aws bedrock list-foundation-models --region "${AWS_REGION}" \
        --query 'modelSummaries[?modelId==`anthropic.claude-3-sonnet-20240229-v1:0`]' \
        --output text | grep -q "anthropic.claude-3-sonnet"; then
        success "Bedrock Claude model access verified"
    else
        warning "Claude model may not be available in region ${AWS_REGION}"
        warning "Please ensure you have access to Bedrock and the Claude model"
    fi
}

# Function to create Lambda deployment package
create_lambda_package() {
    log "Creating Lambda deployment package..."
    
    # Create temporary directory for Lambda function
    LAMBDA_DIR="doc-summarizer-$(date +%s)"
    mkdir -p "${LAMBDA_DIR}"
    cd "${LAMBDA_DIR}"
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import os
from urllib.parse import unquote_plus
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
textract = boto3.client('textract')
bedrock = boto3.client('bedrock-runtime')

def lambda_handler(event, context):
    try:
        # Parse S3 event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        logger.info(f"Processing document: {key} from bucket: {bucket}")
        
        # Extract text from document
        text_content = extract_text(bucket, key)
        
        # Generate summary using Bedrock
        summary = generate_summary(text_content)
        
        # Store summary
        store_summary(key, summary, text_content)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Document processed successfully',
                'document': key,
                'summary_length': len(summary)
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing document: {str(e)}")
        raise

def extract_text(bucket, key):
    """Extract text from document using Textract"""
    try:
        response = textract.detect_document_text(
            Document={'S3Object': {'Bucket': bucket, 'Name': key}}
        )
        
        text_blocks = []
        for block in response['Blocks']:
            if block['BlockType'] == 'LINE':
                text_blocks.append(block['Text'])
        
        return '\n'.join(text_blocks)
        
    except Exception as e:
        logger.error(f"Text extraction failed: {str(e)}")
        raise

def generate_summary(text_content):
    """Generate summary using Bedrock Claude"""
    try:
        # Truncate text if too long
        max_length = 10000
        if len(text_content) > max_length:
            text_content = text_content[:max_length] + "..."
        
        prompt = f"""Please provide a comprehensive summary of the following document. Include:
        
1. Main topics and key points
2. Important facts, figures, and conclusions
3. Actionable insights or recommendations
4. Any critical deadlines or dates mentioned

Document content:
{text_content}

Summary:"""
        
        response = bedrock.invoke_model(
            modelId='anthropic.claude-3-sonnet-20240229-v1:0',
            body=json.dumps({
                'anthropic_version': 'bedrock-2023-05-31',
                'max_tokens': 1000,
                'messages': [{'role': 'user', 'content': prompt}]
            })
        )
        
        response_body = json.loads(response['body'].read())
        return response_body['content'][0]['text']
        
    except Exception as e:
        logger.error(f"Summary generation failed: {str(e)}")
        raise

def store_summary(original_key, summary, full_text):
    """Store summary and metadata in S3"""
    try:
        output_bucket = os.environ['OUTPUT_BUCKET']
        summary_key = f"summaries/{original_key}.summary.txt"
        
        # Store summary
        s3.put_object(
            Bucket=output_bucket,
            Key=summary_key,
            Body=summary,
            ContentType='text/plain',
            Metadata={
                'original-document': original_key,
                'summary-generated': 'true',
                'text-length': str(len(full_text)),
                'summary-length': str(len(summary))
            }
        )
        
        logger.info(f"Summary stored: {summary_key}")
        
    except Exception as e:
        logger.error(f"Failed to store summary: {str(e)}")
        raise
EOF

    # Create requirements file
    cat > requirements.txt << 'EOF'
boto3>=1.26.0
EOF
    
    # Install dependencies
    pip install -r requirements.txt -t . --quiet
    
    # Create deployment package
    zip -r "../${LAMBDA_FUNCTION_NAME}.zip" . -q
    
    cd ..
    success "Lambda deployment package created"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for Lambda function..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        warning "IAM role ${IAM_ROLE_NAME} already exists"
        LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "${IAM_ROLE_NAME}" --query 'Role.Arn' --output text)
    else
        # Create trust policy
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

        # Create role
        LAMBDA_ROLE_ARN=$(aws iam create-role \
            --role-name "${IAM_ROLE_NAME}" \
            --assume-role-policy-document file://lambda-trust-policy.json \
            --query 'Role.Arn' --output text)
        
        success "Created IAM role: ${IAM_ROLE_NAME}"
    fi
    
    # Create permissions policy
    cat > lambda-permissions-policy.json << EOF
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
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::${INPUT_BUCKET}/*",
                "arn:aws:s3:::${OUTPUT_BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "textract:DetectDocumentText"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel"
            ],
            "Resource": "arn:aws:bedrock:${AWS_REGION}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
        }
    ]
}
EOF

    # Attach policy to role
    aws iam put-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-name DocumentSummarizerPolicy \
        --policy-document file://lambda-permissions-policy.json
    
    success "IAM role configured with necessary permissions"
    
    # Wait for role propagation
    log "Waiting for IAM role propagation..."
    sleep 10
}

# Function to deploy Lambda function
deploy_lambda_function() {
    log "Deploying Lambda function..."
    
    # Check if function already exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
        warning "Lambda function ${LAMBDA_FUNCTION_NAME} already exists, updating..."
        
        # Update function code
        aws lambda update-function-code \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --zip-file "fileb://${LAMBDA_FUNCTION_NAME}.zip"
        
        # Update function configuration
        aws lambda update-function-configuration \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --environment "Variables={OUTPUT_BUCKET=${OUTPUT_BUCKET}}" \
            --timeout 300 \
            --memory-size 512
        
        success "Lambda function updated"
    else
        # Create new function
        aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime python3.9 \
            --role "${LAMBDA_ROLE_ARN}" \
            --handler lambda_function.lambda_handler \
            --zip-file "fileb://${LAMBDA_FUNCTION_NAME}.zip" \
            --environment "Variables={OUTPUT_BUCKET=${OUTPUT_BUCKET}}" \
            --timeout 300 \
            --memory-size 512 \
            --description "Intelligent document summarization using Bedrock and Textract"
        
        success "Lambda function created"
    fi
    
    # Wait for function to be ready
    log "Waiting for Lambda function to be ready..."
    aws lambda wait function-active --function-name "${LAMBDA_FUNCTION_NAME}"
}

# Function to configure S3 trigger
configure_s3_trigger() {
    log "Configuring S3 event trigger..."
    
    # Add Lambda permission for S3
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --statement-id s3-trigger \
        --source-arn "arn:aws:s3:::${INPUT_BUCKET}" \
        2>/dev/null || warning "Lambda permission may already exist"
    
    # Create S3 notification configuration
    cat > s3-notification-config.json << EOF
{
    "LambdaConfiguration": {
        "Id": "DocumentUploadTrigger",
        "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}",
        "Events": ["s3:ObjectCreated:*"],
        "Filter": {
            "Key": {
                "FilterRules": [
                    {
                        "Name": "prefix",
                        "Value": "documents/"
                    }
                ]
            }
        }
    }
}
EOF

    # Configure bucket notification
    aws s3api put-bucket-notification-configuration \
        --bucket "${INPUT_BUCKET}" \
        --notification-configuration file://s3-notification-config.json
    
    success "S3 event trigger configured"
}

# Function to create test document
create_test_document() {
    log "Creating test document..."
    
    cat > test-document.txt << 'EOF'
EXECUTIVE SUMMARY

This quarterly report presents the financial performance and strategic initiatives of XYZ Corporation for Q3 2024. 

KEY FINDINGS:
- Revenue increased 15% year-over-year to $2.3M
- Customer acquisition cost reduced by 8%
- New product line launched successfully in European markets
- Digital transformation initiative completed ahead of schedule

RECOMMENDATIONS:
- Expand marketing budget for Q4 holiday season
- Invest in additional customer service capacity
- Explore partnership opportunities in Asian markets
- Continue focus on operational efficiency improvements

The outlook for Q4 remains positive with projected growth of 12-18%.
EOF

    success "Test document created"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check S3 buckets
    if aws s3api head-bucket --bucket "${INPUT_BUCKET}" &>/dev/null && \
       aws s3api head-bucket --bucket "${OUTPUT_BUCKET}" &>/dev/null; then
        success "S3 buckets are accessible"
    else
        error "S3 buckets are not accessible"
        return 1
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
        success "Lambda function is deployed"
    else
        error "Lambda function is not accessible"
        return 1
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        success "IAM role exists"
    else
        error "IAM role is not accessible"
        return 1
    fi
    
    success "Deployment verification completed"
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "=================================================================="
    echo "                   DEPLOYMENT COMPLETED                          "
    echo "=================================================================="
    echo ""
    echo "Resources created:"
    echo "  • Input Bucket: ${INPUT_BUCKET}"
    echo "  • Output Bucket: ${OUTPUT_BUCKET}"
    echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  • IAM Role: ${IAM_ROLE_NAME}"
    echo ""
    echo "Testing the solution:"
    echo "  1. Upload a document to test the system:"
    echo "     aws s3 cp test-document.txt s3://${INPUT_BUCKET}/documents/"
    echo ""
    echo "  2. Check processing logs:"
    echo "     aws logs tail /aws/lambda/${LAMBDA_FUNCTION_NAME} --follow"
    echo ""
    echo "  3. Download generated summary:"
    echo "     aws s3 cp s3://${OUTPUT_BUCKET}/summaries/documents/test-document.txt.summary.txt summary.txt"
    echo ""
    echo "Environment file saved as: .env"
    echo "Use ./destroy.sh to clean up all resources"
    echo ""
    echo "=================================================================="
}

# Cleanup function for errors
cleanup_on_error() {
    error "Deployment failed. Cleaning up partial resources..."
    
    # Remove temporary files
    rm -f lambda-trust-policy.json lambda-permissions-policy.json s3-notification-config.json
    rm -f "${LAMBDA_FUNCTION_NAME}.zip"
    rm -rf "doc-summarizer-"*
    
    warning "Please run ./destroy.sh to clean up any created resources"
}

# Main deployment function
main() {
    log "Starting deployment of Intelligent Document Summarization system..."
    
    # Set trap for cleanup on error
    trap cleanup_on_error ERR
    
    check_prerequisites
    setup_environment
    check_bedrock_access
    create_s3_buckets
    create_lambda_package
    create_iam_role
    deploy_lambda_function
    configure_s3_trigger
    create_test_document
    verify_deployment
    
    # Cleanup temporary files
    rm -f lambda-trust-policy.json lambda-permissions-policy.json s3-notification-config.json
    rm -f "${LAMBDA_FUNCTION_NAME}.zip"
    rm -rf "doc-summarizer-"*
    
    display_summary
    success "Deployment completed successfully!"
}

# Run main function
main "$@"