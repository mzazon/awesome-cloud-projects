#!/bin/bash

# AWS Markdown to HTML Converter - Deployment Script
# This script deploys a serverless markdown to HTML converter using AWS Lambda and S3
# 
# Prerequisites:
# - AWS CLI installed and configured
# - Python 3.12 or later for Lambda runtime
# - pip for installing Python dependencies
# - Appropriate AWS permissions for Lambda, S3, and IAM

set -e  # Exit on error
set -u  # Exit on undefined variable

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

# Check if script is run from correct directory
check_directory() {
    if [[ ! -f "../../markdown-html-converter-lambda-s3.md" ]]; then
        log_error "Please run this script from the aws/markdown-html-converter-lambda-s3/code/scripts/ directory"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install Python 3.12 or later."
        exit 1
    fi
    
    # Check pip
    if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        log_error "pip is not installed. Please install pip for Python package management."
        exit 1
    fi
    
    # Check zip utility
    if ! command -v zip &> /dev/null; then
        log_error "zip utility is not installed. Please install it for Lambda packaging."
        exit 1
    fi
    
    log_success "All prerequisites are met"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "No default region found, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    if command -v aws &> /dev/null && aws secretsmanager get-random-password &> /dev/null; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    else
        RANDOM_SUFFIX=$(date +%s | tail -c 7)
    fi
    
    # Set resource names
    export INPUT_BUCKET_NAME="markdown-input-${RANDOM_SUFFIX}"
    export OUTPUT_BUCKET_NAME="markdown-output-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="markdown-to-html-converter"
    export ROLE_NAME="lambda-markdown-converter-role"
    
    # Save configuration for cleanup script
    cat > .deployment-config << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
INPUT_BUCKET_NAME=$INPUT_BUCKET_NAME
OUTPUT_BUCKET_NAME=$OUTPUT_BUCKET_NAME
FUNCTION_NAME=$FUNCTION_NAME
ROLE_NAME=$ROLE_NAME
EOF
    
    log_success "Environment configured - Region: $AWS_REGION, Account: $AWS_ACCOUNT_ID"
    log_info "Input bucket: $INPUT_BUCKET_NAME"
    log_info "Output bucket: $OUTPUT_BUCKET_NAME"
}

# Create S3 buckets
create_s3_buckets() {
    log_info "Creating S3 buckets..."
    
    # Create input bucket
    if aws s3api head-bucket --bucket "$INPUT_BUCKET_NAME" 2>/dev/null; then
        log_warning "Input bucket $INPUT_BUCKET_NAME already exists"
    else
        aws s3 mb "s3://$INPUT_BUCKET_NAME" --region "$AWS_REGION"
        
        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "$INPUT_BUCKET_NAME" \
            --server-side-encryption-configuration \
            'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$INPUT_BUCKET_NAME" \
            --versioning-configuration Status=Enabled
        
        log_success "Input bucket $INPUT_BUCKET_NAME created with encryption and versioning"
    fi
    
    # Create output bucket
    if aws s3api head-bucket --bucket "$OUTPUT_BUCKET_NAME" 2>/dev/null; then
        log_warning "Output bucket $OUTPUT_BUCKET_NAME already exists"
    else
        aws s3 mb "s3://$OUTPUT_BUCKET_NAME" --region "$AWS_REGION"
        
        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "$OUTPUT_BUCKET_NAME" \
            --server-side-encryption-configuration \
            'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$OUTPUT_BUCKET_NAME" \
            --versioning-configuration Status=Enabled
        
        log_success "Output bucket $OUTPUT_BUCKET_NAME created with encryption and versioning"
    fi
}

# Create IAM role and policies
create_iam_resources() {
    log_info "Creating IAM role and policies..."
    
    # Check if role already exists
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        log_warning "IAM role $ROLE_NAME already exists"
        ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
    else
        # Create trust policy
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
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document file://trust-policy.json
        
        ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
        log_success "IAM role $ROLE_NAME created: $ROLE_ARN"
        
        # Wait for role to be available
        sleep 10
    fi
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        2>/dev/null || log_warning "Basic execution policy already attached"
    
    # Create and attach S3 access policy
    POLICY_NAME="lambda-s3-access-policy"
    POLICY_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME"
    
    if ! aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
        cat > s3-access-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::$INPUT_BUCKET_NAME/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::$OUTPUT_BUCKET_NAME/*"
    }
  ]
}
EOF
        
        aws iam create-policy \
            --policy-name "$POLICY_NAME" \
            --policy-document file://s3-access-policy.json
        
        log_success "S3 access policy created"
    else
        log_warning "S3 access policy already exists"
    fi
    
    # Attach S3 policy to role
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "$POLICY_ARN" \
        2>/dev/null || log_warning "S3 access policy already attached"
    
    # Clean up temporary files
    rm -f trust-policy.json s3-access-policy.json
}

# Create and package Lambda function
create_lambda_function() {
    log_info "Creating Lambda function..."
    
    # Create temporary directory for Lambda code
    LAMBDA_DIR="lambda-function-temp"
    mkdir -p "$LAMBDA_DIR"
    cd "$LAMBDA_DIR"
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import urllib.parse
import os
from datetime import datetime

# Initialize S3 client
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    AWS Lambda handler for converting Markdown files to HTML
    Triggered by S3 PUT events on markdown files
    """
    try:
        # Parse S3 event
        for record in event['Records']:
            # Extract bucket and object information
            input_bucket = record['s3']['bucket']['name']
            input_key = urllib.parse.unquote_plus(
                record['s3']['object']['key'], encoding='utf-8'
            )
            
            print(f"Processing file: {input_key} from bucket: {input_bucket}")
            
            # Verify file is a markdown file
            if not input_key.lower().endswith(('.md', '.markdown')):
                print(f"Skipping non-markdown file: {input_key}")
                continue
            
            # Download markdown content from S3
            response = s3.get_object(Bucket=input_bucket, Key=input_key)
            markdown_content = response['Body'].read().decode('utf-8')
            
            # Convert markdown to HTML using markdown2
            html_content = convert_markdown_to_html(markdown_content)
            
            # Generate output filename (replace .md with .html)
            output_key = input_key.rsplit('.', 1)[0] + '.html'
            output_bucket = os.environ['OUTPUT_BUCKET_NAME']
            
            # Upload HTML content to output bucket
            s3.put_object(
                Bucket=output_bucket,
                Key=output_key,
                Body=html_content,
                ContentType='text/html',
                Metadata={
                    'source-file': input_key,
                    'conversion-timestamp': datetime.utcnow().isoformat(),
                    'converter': 'lambda-markdown2'
                }
            )
            
            print(f"Successfully converted {input_key} to {output_key}")
            
    except Exception as e:
        print(f"Error processing file: {str(e)}")
        raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Markdown conversion completed successfully'
        })
    }

def convert_markdown_to_html(markdown_text):
    """
    Convert markdown text to HTML using markdown2 library
    Includes basic extensions for enhanced formatting
    """
    try:
        import markdown2
        
        # Configure markdown2 with useful extras
        html = markdown2.markdown(
            markdown_text,
            extras=[
                'code-friendly',      # Better code block handling
                'fenced-code-blocks', # Support for ``` code blocks
                'tables',            # Support for markdown tables
                'strike',            # Support for ~~strikethrough~~
                'task-list'          # Support for task lists
            ]
        )
        
        # Wrap in basic HTML structure
        full_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Converted Document</title>
    <style>
        body {{ font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }}
        code {{ background-color: #f4f4f4; padding: 2px 4px; border-radius: 3px; }}
        pre {{ background-color: #f4f4f4; padding: 10px; border-radius: 5px; overflow-x: auto; }}
        table {{ border-collapse: collapse; width: 100%; }}
        th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
        th {{ background-color: #f2f2f2; }}
    </style>
</head>
<body>
{html}
</body>
</html>"""
        
        return full_html
        
    except ImportError:
        # Fallback if markdown2 is not available
        return f"<html><body><pre>{markdown_text}</pre></body></html>"
EOF
    
    # Create requirements file
    cat > requirements.txt << EOF
markdown2==2.5.3
EOF
    
    # Install dependencies
    log_info "Installing Python dependencies..."
    if command -v pip3 &> /dev/null; then
        pip3 install -r requirements.txt -t .
    else
        pip install -r requirements.txt -t .
    fi
    
    # Create deployment package
    log_info "Creating deployment package..."
    zip -r ../lambda-function.zip . -x "*.pyc" "__pycache__/*" > /dev/null
    
    cd ..
    
    # Deploy or update Lambda function
    if aws lambda get-function --function-name "$FUNCTION_NAME" &>/dev/null; then
        log_warning "Lambda function $FUNCTION_NAME already exists, updating..."
        aws lambda update-function-code \
            --function-name "$FUNCTION_NAME" \
            --zip-file fileb://lambda-function.zip
        
        aws lambda update-function-configuration \
            --function-name "$FUNCTION_NAME" \
            --environment Variables="{OUTPUT_BUCKET_NAME=$OUTPUT_BUCKET_NAME}"
    else
        log_info "Creating new Lambda function..."
        aws lambda create-function \
            --function-name "$FUNCTION_NAME" \
            --runtime python3.12 \
            --role "$ROLE_ARN" \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://lambda-function.zip \
            --timeout 60 \
            --memory-size 256 \
            --environment Variables="{OUTPUT_BUCKET_NAME=$OUTPUT_BUCKET_NAME}" \
            --description "Converts Markdown files to HTML using markdown2"
    fi
    
    # Wait for function to be active
    log_info "Waiting for Lambda function to be active..."
    aws lambda wait function-active --function-name "$FUNCTION_NAME"
    
    FUNCTION_ARN=$(aws lambda get-function \
        --function-name "$FUNCTION_NAME" \
        --query 'Configuration.FunctionArn' --output text)
    
    log_success "Lambda function deployed: $FUNCTION_ARN"
    
    # Clean up temporary files
    rm -rf "$LAMBDA_DIR" lambda-function.zip
}

# Configure S3 event trigger
configure_s3_trigger() {
    log_info "Configuring S3 event trigger..."
    
    # Grant S3 permission to invoke Lambda function
    aws lambda add-permission \
        --function-name "$FUNCTION_NAME" \
        --principal s3.amazonaws.com \
        --statement-id s3-trigger-permission \
        --action lambda:InvokeFunction \
        --source-arn "arn:aws:s3:::$INPUT_BUCKET_NAME" \
        2>/dev/null || log_warning "Permission already exists"
    
    # Get function ARN for notification configuration
    FUNCTION_ARN=$(aws lambda get-function \
        --function-name "$FUNCTION_NAME" \
        --query 'Configuration.FunctionArn' --output text)
    
    # Create notification configuration
    cat > notification-config.json << EOF
{
  "LambdaConfigurations": [
    {
      "Id": "markdown-processor-trigger",
      "LambdaFunctionArn": "$FUNCTION_ARN",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "suffix",
              "Value": ".md"
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
        --bucket "$INPUT_BUCKET_NAME" \
        --notification-configuration file://notification-config.json
    
    log_success "S3 event trigger configured for .md files"
    
    # Clean up temporary file
    rm -f notification-config.json
}

# Test deployment with sample file
test_deployment() {
    log_info "Testing deployment with sample file..."
    
    # Create sample markdown file
    cat > sample-test.md << 'EOF'
# Deployment Test

This is a **test document** to verify the markdown converter deployment.

## Features Tested

- **Bold text** and *italic text*
- `inline code` snippets
- [Links](https://aws.amazon.com)

### Code Block Example

```bash
echo "Hello from AWS Lambda!"
```

### Table Example

| Service | Status |
|---------|--------|
| Lambda | ✅ Active |
| S3 | ✅ Active |

> **Note**: This document was created by the deployment test.
EOF
    
    # Upload test file
    log_info "Uploading test file to input bucket..."
    aws s3 cp sample-test.md "s3://$INPUT_BUCKET_NAME/"
    
    # Wait for processing
    log_info "Waiting for processing (15 seconds)..."
    sleep 15
    
    # Check if HTML file was created
    if aws s3api head-object --bucket "$OUTPUT_BUCKET_NAME" --key "sample-test.html" &>/dev/null; then
        log_success "✅ Test successful! HTML file created in output bucket"
        
        # Download and show first few lines
        aws s3 cp "s3://$OUTPUT_BUCKET_NAME/sample-test.html" ./test-output.html
        log_info "First few lines of converted HTML:"
        head -n 10 test-output.html
        
        # Clean up test files
        rm -f sample-test.md test-output.html
        aws s3 rm "s3://$INPUT_BUCKET_NAME/sample-test.md"
        aws s3 rm "s3://$OUTPUT_BUCKET_NAME/sample-test.html"
    else
        log_error "❌ Test failed! HTML file not found in output bucket"
        log_info "Check CloudWatch logs for Lambda function errors:"
        log_info "aws logs tail /aws/lambda/$FUNCTION_NAME --follow"
    fi
}

# Main deployment function
main() {
    log_info "Starting AWS Markdown to HTML Converter deployment..."
    
    check_directory
    check_prerequisites
    setup_environment
    create_s3_buckets
    create_iam_resources
    create_lambda_function
    configure_s3_trigger
    test_deployment
    
    log_success "🎉 Deployment completed successfully!"
    echo
    log_info "Resources created:"
    log_info "  • Input S3 Bucket: $INPUT_BUCKET_NAME"
    log_info "  • Output S3 Bucket: $OUTPUT_BUCKET_NAME"
    log_info "  • Lambda Function: $FUNCTION_NAME"
    log_info "  • IAM Role: $ROLE_NAME"
    echo
    log_info "To test the converter:"
    log_info "  1. Upload a .md file to: s3://$INPUT_BUCKET_NAME/"
    log_info "  2. Check the converted HTML file in: s3://$OUTPUT_BUCKET_NAME/"
    echo
    log_info "To clean up resources, run: ./destroy.sh"
    echo
    log_info "Configuration saved to .deployment-config for cleanup script"
}

# Run main function
main "$@"