#!/bin/bash

#================================================================
# AWS QR Code Generator Deployment Script
# 
# This script deploys a serverless QR code generator using:
# - AWS Lambda (Python 3.12) for QR code generation
# - Amazon S3 for storing generated QR code images  
# - API Gateway for REST API endpoint
# - IAM roles for secure service integration
#
# Prerequisites:
# - AWS CLI installed and configured
# - Appropriate AWS permissions
# - Python 3.x and pip installed locally
#================================================================

set -euo pipefail

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check Python and pip
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 not found. Please install Python 3 first."
        exit 1
    fi
    
    if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        log_error "pip not found. Please install pip first."
        exit 1
    fi
    
    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq not found. JSON output formatting will be limited."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 7)")
    
    # Set resource names with environment variable support
    export BUCKET_NAME="${QR_BUCKET_NAME:-qr-generator-bucket-${RANDOM_SUFFIX}}"
    export FUNCTION_NAME="${QR_FUNCTION_NAME:-qr-generator-function-${RANDOM_SUFFIX}}"
    export ROLE_NAME="${QR_ROLE_NAME:-qr-generator-role-${RANDOM_SUFFIX}}"
    export API_NAME="${QR_API_NAME:-qr-generator-api-${RANDOM_SUFFIX}}"
    
    # Create state file to track deployed resources
    STATE_FILE="./qr-generator-state.json"
    cat > "$STATE_FILE" << EOF
{
    "bucket_name": "$BUCKET_NAME",
    "function_name": "$FUNCTION_NAME",
    "role_name": "$ROLE_NAME",
    "api_name": "$API_NAME",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log_success "Environment configured:"
    log_info "  AWS Region: $AWS_REGION"
    log_info "  AWS Account: $AWS_ACCOUNT_ID"
    log_info "  Bucket Name: $BUCKET_NAME"
    log_info "  Function Name: $FUNCTION_NAME"
    log_info "  Role Name: $ROLE_NAME"
    log_info "  API Name: $API_NAME"
}

# Function to create S3 bucket
create_s3_bucket() {
    log_info "Creating S3 bucket for QR code storage..."
    
    # Check if bucket already exists
    if aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        log_warning "Bucket $BUCKET_NAME already exists. Skipping creation."
        return 0
    fi
    
    # Create bucket with region-specific handling
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://$BUCKET_NAME" || {
            log_error "Failed to create S3 bucket"
            exit 1
        }
    else
        aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION" || {
            log_error "Failed to create S3 bucket"
            exit 1
        }
    fi
    
    # Configure public access block
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" || {
        log_error "Failed to configure bucket public access"
        exit 1
    }
    
    # Create and apply bucket policy
    cat > bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
        }
    ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket "$BUCKET_NAME" \
        --policy file://bucket-policy.json || {
        log_error "Failed to apply bucket policy"
        exit 1
    }
    
    log_success "S3 bucket created: $BUCKET_NAME"
}

# Function to create IAM role
create_iam_role() {
    log_info "Creating IAM role for Lambda function..."
    
    # Check if role already exists
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        log_warning "IAM role $ROLE_NAME already exists. Skipping creation."
        export ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/$ROLE_NAME"
        return 0
    fi
    
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
        --assume-role-policy-document file://trust-policy.json || {
        log_error "Failed to create IAM role"
        exit 1
    }
    
    # Create S3 access policy
    cat > s3-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl"
            ],
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
        }
    ]
}
EOF
    
    # Attach basic execution role
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" || {
        log_error "Failed to attach basic execution policy"
        exit 1
    }
    
    # Attach S3 access policy
    aws iam put-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-name S3AccessPolicy \
        --policy-document file://s3-policy.json || {
        log_error "Failed to attach S3 access policy"
        exit 1
    }
    
    export ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/$ROLE_NAME"
    
    # Update state file with role ARN
    jq ".role_arn = \"$ROLE_ARN\"" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true
    
    log_success "IAM role created: $ROLE_ARN"
}

# Function to create Lambda function package
create_lambda_package() {
    log_info "Creating Lambda function package..."
    
    # Clean up any existing function directory
    rm -rf qr-function qr-function.zip
    
    # Create function directory and code
    mkdir -p qr-function
    cd qr-function
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import qrcode
import io
from datetime import datetime
import uuid
import os

# Initialize S3 client outside handler for connection reuse
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Parse request body
        if 'body' in event:
            body = json.loads(event['body'])
        else:
            body = event
        
        text = body.get('text', '').strip()
        if not text:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Text parameter is required'})
            }
        
        # Limit text length for security and performance
        if len(text) > 1000:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Text too long (max 1000 characters)'})
            }
        
        # Generate QR code
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(text)
        qr.make(fit=True)
        
        # Create QR code image
        img = qr.make_image(fill_color="black", back_color="white")
        
        # Convert to bytes
        img_buffer = io.BytesIO()
        img.save(img_buffer, format='PNG')
        img_buffer.seek(0)
        
        # Generate unique filename
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f"qr_{timestamp}_{str(uuid.uuid4())[:8]}.png"
        
        # Get bucket name from environment variable
        bucket_name = os.environ.get('BUCKET_NAME')
        if not bucket_name:
            # Fallback to context-based naming for backward compatibility
            bucket_name = context.function_name.replace(
                'qr-generator-function-', 'qr-generator-bucket-'
            )
        
        # Upload to S3
        s3_client.put_object(
            Bucket=bucket_name,
            Key=filename,
            Body=img_buffer.getvalue(),
            ContentType='image/png',
            CacheControl='max-age=31536000'  # Cache for 1 year
        )
        
        # Generate public URL
        region = boto3.Session().region_name
        url = f"https://{bucket_name}.s3.{region}.amazonaws.com/{filename}"
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'QR code generated successfully',
                'url': url,
                'filename': filename,
                'text_length': len(text)
            })
        }
        
    except Exception as e:
        # Log error for debugging
        print(f"Error generating QR code: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }
EOF
    
    # Install dependencies
    log_info "Installing Python dependencies..."
    if command -v pip3 &> /dev/null; then
        pip3 install "qrcode[pil]" -t . || {
            log_error "Failed to install Python dependencies"
            exit 1
        }
    else
        pip install "qrcode[pil]" -t . || {
            log_error "Failed to install Python dependencies"
            exit 1
        }
    fi
    
    # Create deployment package
    zip -r ../qr-function.zip . || {
        log_error "Failed to create deployment package"
        exit 1
    }
    
    cd ..
    
    log_success "Lambda function package created"
}

# Function to deploy Lambda function
deploy_lambda_function() {
    log_info "Deploying Lambda function..."
    
    # Check if function already exists
    if aws lambda get-function --function-name "$FUNCTION_NAME" &> /dev/null; then
        log_warning "Lambda function $FUNCTION_NAME already exists. Updating code..."
        
        # Update function code
        aws lambda update-function-code \
            --function-name "$FUNCTION_NAME" \
            --zip-file fileb://qr-function.zip || {
            log_error "Failed to update Lambda function code"
            exit 1
        }
        
        # Update environment variables
        aws lambda update-function-configuration \
            --function-name "$FUNCTION_NAME" \
            --environment Variables="{BUCKET_NAME=$BUCKET_NAME}" || {
            log_error "Failed to update Lambda function configuration"
            exit 1
        }
        
        log_success "Lambda function updated: $FUNCTION_NAME"
    else
        # Wait for IAM role to propagate
        log_info "Waiting for IAM role propagation..."
        sleep 15
        
        # Create new Lambda function
        aws lambda create-function \
            --function-name "$FUNCTION_NAME" \
            --runtime python3.12 \
            --role "$ROLE_ARN" \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://qr-function.zip \
            --timeout 30 \
            --memory-size 256 \
            --environment Variables="{BUCKET_NAME=$BUCKET_NAME}" || {
            log_error "Failed to create Lambda function"
            exit 1
        }
        
        log_success "Lambda function created: $FUNCTION_NAME"
    fi
    
    # Get function ARN
    export FUNCTION_ARN=$(aws lambda get-function \
        --function-name "$FUNCTION_NAME" \
        --query Configuration.FunctionArn --output text)
    
    # Update state file with function ARN
    jq ".function_arn = \"$FUNCTION_ARN\"" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true
    
    log_info "Function ARN: $FUNCTION_ARN"
}

# Function to create API Gateway
create_api_gateway() {
    log_info "Creating API Gateway REST API..."
    
    # Check if API already exists
    EXISTING_API_ID=$(aws apigateway get-rest-apis \
        --query "items[?name=='$API_NAME'].id" \
        --output text 2>/dev/null | grep -v "None" | head -n1)
    
    if [ -n "$EXISTING_API_ID" ] && [ "$EXISTING_API_ID" != "None" ]; then
        log_warning "API Gateway $API_NAME already exists. Using existing API: $EXISTING_API_ID"
        export API_ID="$EXISTING_API_ID"
    else
        # Create new REST API
        export API_ID=$(aws apigateway create-rest-api \
            --name "$API_NAME" \
            --description "QR Code Generator API" \
            --query id --output text) || {
            log_error "Failed to create API Gateway"
            exit 1
        }
        
        log_success "API Gateway created: $API_ID"
    fi
    
    # Get root resource ID
    export ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "$API_ID" \
        --query 'items[0].id' --output text)
    
    # Check if 'generate' resource exists
    EXISTING_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "$API_ID" \
        --query "items[?pathPart=='generate'].id" \
        --output text 2>/dev/null | grep -v "None" | head -n1)
    
    if [ -n "$EXISTING_RESOURCE_ID" ] && [ "$EXISTING_RESOURCE_ID" != "None" ]; then
        log_warning "Resource 'generate' already exists. Using existing resource: $EXISTING_RESOURCE_ID"
        export RESOURCE_ID="$EXISTING_RESOURCE_ID"
    else
        # Create 'generate' resource
        export RESOURCE_ID=$(aws apigateway create-resource \
            --rest-api-id "$API_ID" \
            --parent-id "$ROOT_RESOURCE_ID" \
            --path-part generate \
            --query id --output text) || {
            log_error "Failed to create API resource"
            exit 1
        }
        
        log_success "API resource 'generate' created: $RESOURCE_ID"
    fi
    
    # Create POST method if it doesn't exist
    if ! aws apigateway get-method \
        --rest-api-id "$API_ID" \
        --resource-id "$RESOURCE_ID" \
        --http-method POST &> /dev/null; then
        
        aws apigateway put-method \
            --rest-api-id "$API_ID" \
            --resource-id "$RESOURCE_ID" \
            --http-method POST \
            --authorization-type NONE || {
            log_error "Failed to create POST method"
            exit 1
        }
        
        log_success "POST method created"
    else
        log_warning "POST method already exists"
    fi
    
    # Update state file with API details
    jq ".api_id = \"$API_ID\" | .resource_id = \"$RESOURCE_ID\"" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true
}

# Function to configure Lambda integration
configure_lambda_integration() {
    log_info "Configuring Lambda integration..."
    
    # Configure Lambda integration
    aws apigateway put-integration \
        --rest-api-id "$API_ID" \
        --resource-id "$RESOURCE_ID" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:$AWS_REGION:lambda:path/2015-03-31/functions/$FUNCTION_ARN/invocations" || {
        log_error "Failed to configure Lambda integration"
        exit 1
    }
    
    # Grant API Gateway permission to invoke Lambda (idempotent)
    aws lambda add-permission \
        --function-name "$FUNCTION_NAME" \
        --statement-id allow-apigateway \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:$AWS_REGION:$AWS_ACCOUNT_ID:$API_ID/*/*" \
        2>/dev/null || {
        # Permission might already exist, check if it's the right one
        log_warning "Permission may already exist or failed to add. Continuing..."
    }
    
    log_success "Lambda integration configured"
}

# Function to deploy API Gateway
deploy_api_gateway() {
    log_info "Deploying API Gateway to production stage..."
    
    # Deploy API to 'prod' stage
    aws apigateway create-deployment \
        --rest-api-id "$API_ID" \
        --stage-name prod \
        --description "Production deployment - $(date)" || {
        log_error "Failed to deploy API Gateway"
        exit 1
    }
    
    # Generate API endpoint URL
    export API_URL="https://$API_ID.execute-api.$AWS_REGION.amazonaws.com/prod"
    
    # Update state file with API URL
    jq ".api_url = \"$API_URL\"" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true
    
    log_success "API deployed successfully"
    log_info "API Endpoint: $API_URL/generate"
}

# Function to test deployment
test_deployment() {
    log_info "Testing QR code generator deployment..."
    
    # Wait a moment for API to be ready
    sleep 5
    
    # Test API with sample text
    RESPONSE=$(curl -s -X POST "$API_URL/generate" \
        -H "Content-Type: application/json" \
        -d '{"text": "Hello, World! This is a test QR code."}' || echo "")
    
    if [ -n "$RESPONSE" ]; then
        if command -v jq &> /dev/null; then
            echo "$RESPONSE" | jq . || echo "$RESPONSE"
        else
            echo "$RESPONSE"
        fi
        
        # Check if response contains URL (simple validation)
        if echo "$RESPONSE" | grep -q "url"; then
            log_success "API test completed successfully!"
        else
            log_warning "API test completed but response may contain errors"
        fi
    else
        log_warning "API test failed - no response received"
    fi
    
    # Verify S3 bucket has objects
    OBJECT_COUNT=$(aws s3 ls "s3://$BUCKET_NAME/" | wc -l || echo "0")
    if [ "$OBJECT_COUNT" -gt 0 ]; then
        log_success "S3 bucket contains $OBJECT_COUNT QR code file(s)"
    fi
}

# Function to display deployment summary
display_summary() {
    log_success "=== QR Code Generator Deployment Summary ==="
    echo
    log_info "Resources Created:"
    log_info "  S3 Bucket: $BUCKET_NAME"
    log_info "  Lambda Function: $FUNCTION_NAME"
    log_info "  IAM Role: $ROLE_NAME"
    log_info "  API Gateway: $API_NAME ($API_ID)"
    echo
    log_info "API Endpoint:"
    log_info "  URL: $API_URL/generate"
    echo
    log_info "Example Usage:"
    echo "  curl -X POST $API_URL/generate \\"
    echo "    -H \"Content-Type: application/json\" \\"
    echo "    -d '{\"text\": \"Your text here\"}'"
    echo
    log_info "State file saved to: $STATE_FILE"
    log_warning "Use the destroy.sh script to clean up all resources"
    echo
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    rm -f bucket-policy.json trust-policy.json s3-policy.json
    rm -rf qr-function qr-function.zip
    log_success "Temporary files cleaned up"
}

# Main deployment function
main() {
    echo
    log_info "========================================"
    log_info "AWS QR Code Generator Deployment Script"
    log_info "========================================"
    echo
    
    # Check if this is a dry run
    if [[ "${1:-}" == "--dry-run" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        export DRY_RUN=true
    fi
    
    # Set up error handling
    trap 'log_error "Deployment failed at line $LINENO. Check the logs above."; cleanup_temp_files; exit 1' ERR
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "Dry run completed. No resources were created."
        exit 0
    fi
    
    create_s3_bucket
    create_iam_role
    create_lambda_package
    deploy_lambda_function
    create_api_gateway
    configure_lambda_integration
    deploy_api_gateway
    test_deployment
    display_summary
    cleanup_temp_files
    
    log_success "Deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"