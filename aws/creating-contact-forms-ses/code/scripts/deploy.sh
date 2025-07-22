#!/bin/bash

# AWS Simple Contact Form Backend Deployment Script
# This script deploys a serverless contact form backend using AWS Lambda, API Gateway, and SES
# Recipe: Creating Contact Forms with SES and Lambda

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
TEMP_DIR="${SCRIPT_DIR}/temp"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    cleanup_temp_files
    exit 1
}

# Success handler
success_handler() {
    log "✅ Deployment completed successfully!"
    log "📍 API Endpoint: ${API_ENDPOINT}"
    log "📧 Verified email: ${SENDER_EMAIL}"
    log "📝 Check deployment.log for detailed information"
    cleanup_temp_files
}

# Cleanup temporary files
cleanup_temp_files() {
    if [ -d "${TEMP_DIR}" ]; then
        rm -rf "${TEMP_DIR}"
        log "🧹 Temporary files cleaned up"
    fi
}

# Prerequisites check
check_prerequisites() {
    log "🔍 Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "📦 AWS CLI version: ${AWS_CLI_VERSION}"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check if required commands are available
    for cmd in zip python3 curl; do
        if ! command -v "$cmd" &> /dev/null; then
            error_exit "Required command '$cmd' is not available"
        fi
    done
    
    log "✅ Prerequisites check passed"
}

# Environment setup
setup_environment() {
    log "🔧 Setting up environment..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [ -z "${AWS_REGION}" ]; then
        export AWS_REGION="us-east-1"
        log "⚠️  No default region set, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export LAMBDA_FUNCTION_NAME="contact-form-processor-${RANDOM_SUFFIX}"
    export API_GATEWAY_NAME="contact-form-api-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="contact-form-lambda-role-${RANDOM_SUFFIX}"
    export POLICY_NAME="contact-form-ses-policy-${RANDOM_SUFFIX}"
    
    # Create temporary directory
    mkdir -p "${TEMP_DIR}"
    
    # Save environment variables for cleanup script
    cat > "${SCRIPT_DIR}/deployment_vars.env" << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME}"
export API_GATEWAY_NAME="${API_GATEWAY_NAME}"
export IAM_ROLE_NAME="${IAM_ROLE_NAME}"
export POLICY_NAME="${POLICY_NAME}"
EOF
    
    log "✅ Environment configured for region: ${AWS_REGION}"
    log "✅ Account ID: ${AWS_ACCOUNT_ID}"
    log "✅ Resource suffix: ${RANDOM_SUFFIX}"
}

# SES verification
verify_email() {
    log "📧 Setting up email verification..."
    
    # Prompt for email address if not provided
    if [ -z "${SENDER_EMAIL:-}" ]; then
        read -p "Enter your email address for SES verification: " SENDER_EMAIL
        export SENDER_EMAIL
    fi
    
    # Save email to environment file
    echo "export SENDER_EMAIL=\"${SENDER_EMAIL}\"" >> "${SCRIPT_DIR}/deployment_vars.env"
    
    # Verify email address identity
    aws ses verify-email-identity --email-address "${SENDER_EMAIL}" || \
        error_exit "Failed to initiate email verification"
    
    log "✅ Email verification initiated for ${SENDER_EMAIL}"
    log "📧 Check your inbox and click the verification link"
    log "⏳ Waiting for email verification..."
    
    # Wait for verification with timeout
    local timeout=600  # 10 minutes
    local elapsed=0
    local interval=30
    
    while [ $elapsed -lt $timeout ]; do
        VERIFICATION_STATUS=$(aws ses get-identity-verification-attributes \
            --identities "${SENDER_EMAIL}" \
            --query "VerificationAttributes.\"${SENDER_EMAIL}\".VerificationStatus" \
            --output text 2>/dev/null || echo "Pending")
        
        if [ "$VERIFICATION_STATUS" = "Success" ]; then
            log "✅ Email address verified successfully"
            return 0
        elif [ "$VERIFICATION_STATUS" = "Failed" ]; then
            error_exit "Email verification failed"
        else
            log "⏳ Verification status: ${VERIFICATION_STATUS}. Waiting... (${elapsed}s elapsed)"
            sleep $interval
            elapsed=$((elapsed + interval))
        fi
    done
    
    error_exit "Email verification timed out after ${timeout} seconds"
}

# Create IAM role
create_iam_role() {
    log "🔐 Creating IAM role..."
    
    # Create trust policy
    cat > "${TEMP_DIR}/trust-policy.json" << 'EOF'
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
        --assume-role-policy-document "file://${TEMP_DIR}/trust-policy.json" \
        --tags Key=Project,Value=ContactForm Key=Environment,Value=Production || \
        error_exit "Failed to create IAM role"
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" || \
        error_exit "Failed to attach basic execution policy"
    
    # Create custom SES policy
    cat > "${TEMP_DIR}/ses-policy.json" << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ses:SendEmail",
        "ses:SendRawEmail"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    # Create and attach SES policy
    aws iam create-policy \
        --policy-name "${POLICY_NAME}" \
        --policy-document "file://${TEMP_DIR}/ses-policy.json" \
        --description "Policy for contact form to send emails via SES" || \
        error_exit "Failed to create SES policy"
    
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" || \
        error_exit "Failed to attach SES policy"
    
    # Wait for role to be available
    log "⏳ Waiting for IAM role to be available..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
            sleep 10  # Additional wait for role propagation
            break
        fi
        log "⏳ Attempt ${attempt}/${max_attempts}: Waiting for role..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error_exit "IAM role creation timed out"
    fi
    
    log "✅ IAM role created with SES permissions"
}

# Create Lambda function
create_lambda_function() {
    log "⚡ Creating Lambda function..."
    
    # Create Lambda function code
    cat > "${TEMP_DIR}/lambda_function.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    # Initialize SES client
    ses_client = boto3.client('ses')
    
    try:
        # Parse the incoming request
        body = json.loads(event['body'])
        
        # Extract form data
        name = body.get('name', '')
        email = body.get('email', '')
        subject = body.get('subject', 'Contact Form Submission')
        message = body.get('message', '')
        
        # Validate required fields
        if not name or not email or not message:
            return {
                'statusCode': 400,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'POST',
                    'Access-Control-Allow-Headers': 'Content-Type'
                },
                'body': json.dumps({
                    'error': 'Name, email, and message are required fields'
                })
            }
        
        # Prepare email content
        sender_email = os.environ['SENDER_EMAIL']
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')
        
        email_body = f"""
New Contact Form Submission

Time: {timestamp}
Name: {name}
Email: {email}
Subject: {subject}

Message:
{message}
        """
        
        # Send email using SES
        response = ses_client.send_email(
            Source=sender_email,
            Destination={
                'ToAddresses': [sender_email]
            },
            Message={
                'Subject': {
                    'Data': f'Contact Form: {subject}'
                },
                'Body': {
                    'Text': {
                        'Data': email_body
                    }
                }
            }
        )
        
        # Return success response
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps({
                'message': 'Email sent successfully',
                'messageId': response['MessageId']
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps({
                'error': 'Internal server error'
            })
        }
EOF
    
    # Create deployment package
    cd "${TEMP_DIR}"
    zip lambda-function.zip lambda_function.py || error_exit "Failed to create Lambda deployment package"
    cd "${SCRIPT_DIR}"
    
    # Get IAM role ARN
    ROLE_ARN=$(aws iam get-role --role-name "${IAM_ROLE_NAME}" --query Role.Arn --output text) || \
        error_exit "Failed to get IAM role ARN"
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${ROLE_ARN}" \
        --handler lambda_function.lambda_handler \
        --zip-file "fileb://${TEMP_DIR}/lambda-function.zip" \
        --timeout 30 \
        --memory-size 128 \
        --environment "Variables={SENDER_EMAIL=${SENDER_EMAIL}}" \
        --description "Contact form processor for serverless backend" \
        --tags Project=ContactForm,Environment=Production || \
        error_exit "Failed to create Lambda function"
    
    # Wait for function to be ready
    log "⏳ Waiting for Lambda function to be active..."
    aws lambda wait function-active --function-name "${LAMBDA_FUNCTION_NAME}" || \
        error_exit "Lambda function failed to become active"
    
    log "✅ Lambda function deployed successfully"
}

# Create API Gateway
create_api_gateway() {
    log "🌐 Creating API Gateway..."
    
    # Create REST API
    API_ID=$(aws apigateway create-rest-api \
        --name "${API_GATEWAY_NAME}" \
        --description "Contact form API for serverless backend" \
        --endpoint-configuration types=REGIONAL \
        --query id --output text) || \
        error_exit "Failed to create API Gateway"
    
    # Save API ID to environment file
    echo "export API_ID=\"${API_ID}\"" >> "${SCRIPT_DIR}/deployment_vars.env"
    
    # Get root resource ID
    ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query 'items[0].id' --output text) || \
        error_exit "Failed to get root resource ID"
    
    # Create 'contact' resource
    CONTACT_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "${API_ID}" \
        --parent-id "${ROOT_RESOURCE_ID}" \
        --path-part contact \
        --query id --output text) || \
        error_exit "Failed to create contact resource"
    
    # Save resource ID to environment file
    echo "export CONTACT_RESOURCE_ID=\"${CONTACT_RESOURCE_ID}\"" >> "${SCRIPT_DIR}/deployment_vars.env"
    
    log "✅ API Gateway REST API created (ID: ${API_ID})"
}

# Configure API methods
configure_api_methods() {
    log "🔧 Configuring API methods..."
    
    # Create POST method
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${CONTACT_RESOURCE_ID}" \
        --http-method POST \
        --authorization-type NONE || \
        error_exit "Failed to create POST method"
    
    # Create Lambda integration
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${CONTACT_RESOURCE_ID}" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}/invocations" || \
        error_exit "Failed to create Lambda integration"
    
    # Grant API Gateway permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id api-gateway-invoke \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*/*" || \
        error_exit "Failed to grant API Gateway permission"
    
    log "✅ POST method configured with Lambda integration"
}

# Configure CORS
configure_cors() {
    log "🌍 Configuring CORS..."
    
    # Create OPTIONS method for CORS preflight
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${CONTACT_RESOURCE_ID}" \
        --http-method OPTIONS \
        --authorization-type NONE || \
        error_exit "Failed to create OPTIONS method"
    
    # Create mock integration for OPTIONS
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${CONTACT_RESOURCE_ID}" \
        --http-method OPTIONS \
        --type MOCK \
        --request-templates '{"application/json": "{\"statusCode\": 200}"}' || \
        error_exit "Failed to create OPTIONS integration"
    
    # Configure OPTIONS method response
    aws apigateway put-method-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${CONTACT_RESOURCE_ID}" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters \
        method.response.header.Access-Control-Allow-Headers=false,method.response.header.Access-Control-Allow-Methods=false,method.response.header.Access-Control-Allow-Origin=false || \
        error_exit "Failed to create OPTIONS method response"
    
    # Configure OPTIONS integration response with CORS headers
    aws apigateway put-integration-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${CONTACT_RESOURCE_ID}" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters '{
            "method.response.header.Access-Control-Allow-Headers": "\"Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token\"",
            "method.response.header.Access-Control-Allow-Methods": "\"POST,OPTIONS\"",
            "method.response.header.Access-Control-Allow-Origin": "\"*\""
        }' || \
        error_exit "Failed to create OPTIONS integration response"
    
    log "✅ CORS configuration completed"
}

# Deploy API
deploy_api() {
    log "🚀 Deploying API Gateway stage..."
    
    # Create deployment
    aws apigateway create-deployment \
        --rest-api-id "${API_ID}" \
        --stage-name prod \
        --stage-description "Production stage for contact form API" || \
        error_exit "Failed to create API deployment"
    
    # Set API endpoint
    API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod/contact"
    echo "export API_ENDPOINT=\"${API_ENDPOINT}\"" >> "${SCRIPT_DIR}/deployment_vars.env"
    
    log "✅ API Gateway deployed to production stage"
    log "🌐 API Endpoint: ${API_ENDPOINT}"
}

# Test deployment
test_deployment() {
    log "🧪 Testing deployment..."
    
    # Create test event
    cat > "${TEMP_DIR}/test-event.json" << 'EOF'
{
  "body": "{\"name\": \"Test User\", \"email\": \"test@example.com\", \"subject\": \"Deployment Test\", \"message\": \"This is a test message from the deployment script.\"}"
}
EOF
    
    # Test Lambda function directly
    log "Testing Lambda function directly..."
    aws lambda invoke \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --payload "file://${TEMP_DIR}/test-event.json" \
        --cli-binary-format raw-in-base64-out \
        "${TEMP_DIR}/response.json" > /dev/null || \
        log "⚠️  Direct Lambda test failed (this may be expected if SES is in sandbox mode)"
    
    # Test API endpoint
    log "Testing API Gateway endpoint..."
    if command -v curl &> /dev/null; then
        CURL_RESPONSE=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d '{"name": "API Test", "email": "apitest@example.com", "subject": "API Test", "message": "Testing the API Gateway endpoint"}' \
            "${API_ENDPOINT}" || echo "API test failed")
        
        if [[ "$CURL_RESPONSE" == *"Email sent successfully"* ]]; then
            log "✅ API endpoint test successful"
        else
            log "⚠️  API endpoint test returned: ${CURL_RESPONSE}"
            log "⚠️  This may be expected if SES is in sandbox mode and test email is not verified"
        fi
    else
        log "⚠️  curl not available, skipping API endpoint test"
    fi
    
    log "✅ Deployment testing completed"
}

# Main deployment function
main() {
    log "🚀 Starting AWS Contact Form Backend deployment..."
    
    # Set trap for cleanup on exit
    trap cleanup_temp_files EXIT
    
    check_prerequisites
    setup_environment
    verify_email
    create_iam_role
    create_lambda_function
    create_api_gateway
    configure_api_methods
    configure_cors
    deploy_api
    test_deployment
    
    success_handler
}

# Run main function
main "$@"