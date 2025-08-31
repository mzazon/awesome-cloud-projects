#!/bin/bash

# Simple Random Data API Deployment Script
# This script deploys a serverless REST API using AWS Lambda and API Gateway
# that generates random data including quotes, numbers, and colors.

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
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of created resources..."
    
    # Clean up resources that might have been created
    if [[ -n "${API_ID:-}" ]]; then
        aws apigateway delete-rest-api --rest-api-id "${API_ID}" 2>/dev/null || true
        log_info "Cleaned up API Gateway: ${API_ID}"
    fi
    
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        aws lambda delete-function --function-name "${FUNCTION_NAME}" 2>/dev/null || true
        log_info "Cleaned up Lambda function: ${FUNCTION_NAME}"
    fi
    
    if [[ -n "${ROLE_NAME:-}" ]]; then
        aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        aws iam delete-role --role-name "${ROLE_NAME}" 2>/dev/null || true
        log_info "Cleaned up IAM role: ${ROLE_NAME}"
    fi
    
    # Clean up temporary files
    rm -f trust-policy.json function.zip 2>/dev/null || true
    rm -rf lambda-function/ 2>/dev/null || true
    
    exit 1
}

# Set up error trap
trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2 and configure credentials."
        exit 1
    fi
    
    # Check if jq is installed (for JSON parsing)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some output formatting may be limited."
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        log_error "zip command is not available. Please install zip utility."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$account_id" ]]; then
        log_error "Cannot retrieve AWS account ID. Check your credentials."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "No default region configured, using us-east-1"
    fi
    
    # Set AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names
    export FUNCTION_NAME="random-data-api-${RANDOM_SUFFIX}"
    export ROLE_NAME="lambda-random-api-role-${RANDOM_SUFFIX}"
    export API_NAME="random-data-api-${RANDOM_SUFFIX}"
    
    log_success "Environment configured"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "Function Name: ${FUNCTION_NAME}"
    log_info "Role Name: ${ROLE_NAME}"
    log_info "API Name: ${API_NAME}"
}

# Function to create IAM role
create_iam_role() {
    log_info "Creating IAM role for Lambda function..."
    
    # Create trust policy for Lambda service
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
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file://trust-policy.json \
        --description "IAM role for Random Data API Lambda function"
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Get role ARN for later use
    export ROLE_ARN=$(aws iam get-role \
        --role-name "${ROLE_NAME}" \
        --query Role.Arn --output text)
    
    # Wait for role to be available
    log_info "Waiting for IAM role to be available..."
    sleep 10
    
    log_success "IAM role created: ${ROLE_ARN}"
}

# Function to create Lambda function code
create_lambda_code() {
    log_info "Creating Lambda function code..."
    
    # Create function code directory
    mkdir -p lambda-function
    cd lambda-function
    
    # Create the main function file
    cat > lambda_function.py << 'EOF'
import json
import random
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    AWS Lambda handler for random data API
    Returns random quotes, numbers, or colors based on query parameter
    """
    
    try:
        # Log the incoming request
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Parse query parameters
        query_params = event.get('queryStringParameters') or {}
        data_type = query_params.get('type', 'quote').lower()
        
        # Random data collections
        quotes = [
            "The only way to do great work is to love what you do. - Steve Jobs",
            "Innovation distinguishes between a leader and a follower. - Steve Jobs",
            "Life is what happens to you while you're busy making other plans. - John Lennon",
            "The future belongs to those who believe in the beauty of their dreams. - Eleanor Roosevelt",
            "Success is not final, failure is not fatal: it is the courage to continue that counts. - Winston Churchill"
        ]
        
        colors = [
            {"name": "Ocean Blue", "hex": "#006994", "rgb": "rgb(0, 105, 148)"},
            {"name": "Sunset Orange", "hex": "#FF6B35", "rgb": "rgb(255, 107, 53)"},
            {"name": "Forest Green", "hex": "#2E8B57", "rgb": "rgb(46, 139, 87)"},
            {"name": "Purple Haze", "hex": "#9370DB", "rgb": "rgb(147, 112, 219)"},
            {"name": "Golden Yellow", "hex": "#FFD700", "rgb": "rgb(255, 215, 0)"}
        ]
        
        # Generate response based on type
        if data_type == 'quote':
            data = random.choice(quotes)
        elif data_type == 'number':
            data = random.randint(1, 1000)
        elif data_type == 'color':
            data = random.choice(colors)
        else:
            # Default to quote for unknown types
            data = random.choice(quotes)
            data_type = 'quote'
        
        # Create response
        response_body = {
            'type': data_type,
            'data': data,
            'timestamp': context.aws_request_id,
            'message': f'Random {data_type} generated successfully'
        }
        
        # Return successful response with CORS headers
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps(response_body)
        }
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        
        # Return error response
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': 'Failed to generate random data'
            })
        }
EOF
    
    cd ..
    log_success "Lambda function code created"
}

# Function to package and deploy Lambda function
deploy_lambda_function() {
    log_info "Packaging and deploying Lambda function..."
    
    cd lambda-function
    
    # Create deployment package
    zip -r ../function.zip lambda_function.py
    
    cd ..
    
    # Create Lambda function with latest Python runtime
    aws lambda create-function \
        --function-name "${FUNCTION_NAME}" \
        --runtime python3.12 \
        --role "${ROLE_ARN}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://function.zip \
        --timeout 30 \
        --memory-size 128 \
        --description "Random data API generator" \
        --tags Project=RandomDataAPI,Environment=dev
    
    # Wait for function to be active
    log_info "Waiting for Lambda function to be active..."
    aws lambda wait function-active --function-name "${FUNCTION_NAME}"
    
    log_success "Lambda function deployed: ${FUNCTION_NAME}"
}

# Function to create API Gateway
create_api_gateway() {
    log_info "Creating API Gateway REST API..."
    
    # Create REST API
    export API_ID=$(aws apigateway create-rest-api \
        --name "${API_NAME}" \
        --description "Random data API using Lambda" \
        --endpoint-configuration types=REGIONAL \
        --query id --output text)
    
    # Get root resource ID
    ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query 'items[?path==`/`].id' \
        --output text)
    
    log_success "API Gateway created: ${API_ID}"
    log_info "Root Resource ID: ${ROOT_RESOURCE_ID}"
    
    # Create /random resource
    RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "${API_ID}" \
        --parent-id "${ROOT_RESOURCE_ID}" \
        --path-part random \
        --query id --output text)
    
    # Create GET method
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${RESOURCE_ID}" \
        --http-method GET \
        --authorization-type NONE
    
    log_success "API resource and method created"
    log_info "Resource ID: ${RESOURCE_ID}"
    
    # Configure Lambda integration
    log_info "Configuring Lambda integration..."
    
    # Get Lambda function ARN
    FUNCTION_ARN=$(aws lambda get-function \
        --function-name "${FUNCTION_NAME}" \
        --query Configuration.FunctionArn --output text)
    
    # Configure Lambda proxy integration
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${RESOURCE_ID}" \
        --http-method GET \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${FUNCTION_ARN}/invocations"
    
    log_success "Lambda integration configured"
    
    # Grant API Gateway permission to invoke Lambda
    log_info "Granting API Gateway permission to invoke Lambda..."
    
    aws lambda add-permission \
        --function-name "${FUNCTION_NAME}" \
        --statement-id apigateway-invoke \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*"
    
    log_success "API Gateway permissions configured"
}

# Function to deploy API to stage
deploy_api_stage() {
    log_info "Deploying API to 'dev' stage..."
    
    # Deploy API to 'dev' stage
    aws apigateway create-deployment \
        --rest-api-id "${API_ID}" \
        --stage-name dev \
        --description "Initial deployment of random data API"
    
    # Get API endpoint URL
    export API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/dev/random"
    
    log_success "API deployed successfully"
    log_info "API Endpoint: ${API_URL}"
}

# Function to test the deployed API
test_api() {
    log_info "Testing the deployed API..."
    
    # Test basic functionality
    if command -v curl &> /dev/null; then
        log_info "Testing quote endpoint..."
        if curl -s -f "${API_URL}" > /dev/null; then
            log_success "Quote endpoint is working"
        else
            log_warning "Quote endpoint test failed"
        fi
        
        log_info "Testing number endpoint..."
        if curl -s -f "${API_URL}?type=number" > /dev/null; then
            log_success "Number endpoint is working"
        else
            log_warning "Number endpoint test failed"
        fi
        
        log_info "Testing color endpoint..."
        if curl -s -f "${API_URL}?type=color" > /dev/null; then
            log_success "Color endpoint is working"
        else
            log_warning "Color endpoint test failed"
        fi
    else
        log_warning "curl not available, skipping API tests"
    fi
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > deployment-info.json << EOF
{
  "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "aws_region": "${AWS_REGION}",
  "aws_account_id": "${AWS_ACCOUNT_ID}",
  "function_name": "${FUNCTION_NAME}",
  "role_name": "${ROLE_NAME}",
  "api_name": "${API_NAME}",
  "api_id": "${API_ID}",
  "api_url": "${API_URL}",
  "role_arn": "${ROLE_ARN}"
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    rm -f trust-policy.json function.zip
    rm -rf lambda-function/
    
    log_success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log_info "Starting Simple Random Data API deployment..."
    log_info "=========================================="
    
    check_prerequisites
    setup_environment
    create_iam_role
    create_lambda_code
    deploy_lambda_function
    create_api_gateway
    deploy_api_stage
    test_api
    save_deployment_info
    cleanup_temp_files
    
    log_success "=========================================="
    log_success "Deployment completed successfully!"
    log_success "=========================================="
    log_info "API Endpoint: ${API_URL}"
    log_info ""
    log_info "Test your API with these commands:"
    log_info "  curl '${API_URL}' | jq .                    # Get random quote"
    log_info "  curl '${API_URL}?type=number' | jq .        # Get random number"
    log_info "  curl '${API_URL}?type=color' | jq .         # Get random color"
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
    log_info "Deployment details saved in: deployment-info.json"
}

# Run main function
main "$@"