#!/bin/bash

#########################################
# Deploy Simple Timezone Converter
# with Lambda and API Gateway
#
# This script deploys a serverless timezone
# conversion API using AWS Lambda and 
# API Gateway with proper error handling
# and logging.
#########################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS credentials
validate_aws_credentials() {
    log "Validating AWS credentials..."
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    success "AWS credentials validated"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        error "Visit: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    
    # Check if zip is available
    if ! command_exists zip; then
        error "zip command not found. Please install zip utility."
        exit 1
    fi
    
    # Check if python is available for JSON formatting
    if ! command_exists python; then
        warn "Python not found. JSON output formatting may not work."
    fi
    
    # Check if curl is available for testing
    if ! command_exists curl; then
        warn "curl not found. API testing will be skipped."
    fi
    
    success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "No default region set, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names with unique suffixes
    export FUNCTION_NAME="timezone-converter-${RANDOM_SUFFIX}"
    export ROLE_NAME="timezone-converter-role-${RANDOM_SUFFIX}"
    export API_NAME="timezone-converter-api-${RANDOM_SUFFIX}"
    
    # Store values for cleanup script
    echo "FUNCTION_NAME=${FUNCTION_NAME}" > .deployment-vars
    echo "ROLE_NAME=${ROLE_NAME}" >> .deployment-vars
    echo "API_NAME=${API_NAME}" >> .deployment-vars
    echo "AWS_REGION=${AWS_REGION}" >> .deployment-vars
    echo "AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}" >> .deployment-vars
    
    success "Environment configured for region: ${AWS_REGION}"
    success "Account ID: ${AWS_ACCOUNT_ID}"
    success "Function name: ${FUNCTION_NAME}"
}

# Function to create IAM role for Lambda execution
create_iam_role() {
    log "Creating IAM role for Lambda execution..."
    
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
    
    # Check if role already exists
    if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
        warn "IAM role ${ROLE_NAME} already exists, skipping creation"
    else
        # Create the IAM role
        aws iam create-role \
            --role-name "${ROLE_NAME}" \
            --assume-role-policy-document file://trust-policy.json \
            --description "Execution role for timezone converter Lambda function"
        
        success "IAM role created: ${ROLE_NAME}"
    fi
    
    # Attach basic execution policy for CloudWatch Logs
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Store role ARN for later use
    ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    
    echo "ROLE_ARN=${ROLE_ARN}" >> .deployment-vars
    
    success "IAM role configured: ${ROLE_ARN}"
}

# Function to create Lambda function code
create_lambda_code() {
    log "Creating Lambda function code..."
    
    # Create the Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import logging
from datetime import datetime
from zoneinfo import ZoneInfo

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Convert timestamp between timezones
    
    Expected event format:
    {
      "timestamp": "2025-07-12T15:30:00",
      "from_timezone": "UTC",
      "to_timezone": "America/New_York"
    }
    """
    try:
        # Parse the request body
        if 'body' in event:
            body = json.loads(event['body'])
        else:
            body = event
        
        # Extract required parameters
        timestamp_str = body.get('timestamp')
        from_tz = body.get('from_timezone', 'UTC')
        to_tz = body.get('to_timezone')
        
        # Validate required parameters
        if not timestamp_str or not to_tz:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Missing required parameters: timestamp and to_timezone'
                })
            }
        
        # Parse the timestamp
        try:
            # Try parsing with timezone info first
            if 'T' in timestamp_str and ('+' in timestamp_str or 'Z' in timestamp_str):
                dt = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
            else:
                # Parse as naive datetime and assign source timezone
                dt_naive = datetime.fromisoformat(timestamp_str)
                dt = dt_naive.replace(tzinfo=ZoneInfo(from_tz))
        except ValueError as e:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': f'Invalid timestamp format: {str(e)}'
                })
            }
        
        # Convert to target timezone
        try:
            target_tz = ZoneInfo(to_tz)
            converted_dt = dt.astimezone(target_tz)
        except Exception as e:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': f'Invalid timezone: {str(e)}'
                })
            }
        
        # Format response
        response_data = {
            'original_timestamp': timestamp_str,
            'original_timezone': from_tz,
            'converted_timestamp': converted_dt.isoformat(),
            'target_timezone': to_tz,
            'timezone_offset': converted_dt.strftime('%z'),
            'timezone_name': converted_dt.tzname()
        }
        
        logger.info(f"Converted {timestamp_str} from {from_tz} to {to_tz}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(response_data)
        }
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error'
            })
        }
EOF
    
    success "Lambda function code created"
}

# Function to package and deploy Lambda function
deploy_lambda_function() {
    log "Packaging and deploying Lambda function..."
    
    # Create deployment package
    zip -q lambda-deployment.zip lambda_function.py
    
    # Wait for IAM role to propagate (required for new roles)
    log "Waiting for IAM role propagation..."
    sleep 10
    
    # Check if function already exists
    if aws lambda get-function --function-name "${FUNCTION_NAME}" >/dev/null 2>&1; then
        warn "Lambda function ${FUNCTION_NAME} already exists, updating code..."
        
        # Update existing function
        aws lambda update-function-code \
            --function-name "${FUNCTION_NAME}" \
            --zip-file fileb://lambda-deployment.zip
        
        # Update configuration if needed
        aws lambda update-function-configuration \
            --function-name "${FUNCTION_NAME}" \
            --runtime python3.12 \
            --timeout 30 \
            --memory-size 128 \
            --description "Simple timezone converter API"
    else
        # Create the Lambda function with Python 3.12 runtime
        aws lambda create-function \
            --function-name "${FUNCTION_NAME}" \
            --runtime python3.12 \
            --role "${ROLE_ARN}" \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://lambda-deployment.zip \
            --timeout 30 \
            --memory-size 128 \
            --description "Simple timezone converter API"
    fi
    
    # Store function ARN for later use
    FUNCTION_ARN=$(aws lambda get-function --function-name "${FUNCTION_NAME}" \
        --query 'Configuration.FunctionArn' --output text)
    
    echo "FUNCTION_ARN=${FUNCTION_ARN}" >> .deployment-vars
    
    success "Lambda function deployed: ${FUNCTION_ARN}"
}

# Function to create API Gateway REST API
create_api_gateway() {
    log "Creating API Gateway REST API..."
    
    # Check if API already exists
    EXISTING_API_ID=$(aws apigateway get-rest-apis \
        --query "items[?name=='${API_NAME}'].id" --output text 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_API_ID" ] && [ "$EXISTING_API_ID" != "None" ]; then
        warn "API Gateway ${API_NAME} already exists, using existing API"
        API_ID="$EXISTING_API_ID"
    else
        # Create the REST API
        API_ID=$(aws apigateway create-rest-api \
            --name "${API_NAME}" \
            --description "Timezone converter REST API" \
            --endpoint-configuration types=REGIONAL \
            --query 'id' --output text)
        
        success "API Gateway created: ${API_ID}"
    fi
    
    # Get the root resource ID
    ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query 'items[0].id' --output text)
    
    echo "API_ID=${API_ID}" >> .deployment-vars
    echo "ROOT_RESOURCE_ID=${ROOT_RESOURCE_ID}" >> .deployment-vars
    
    success "Root resource ID: ${ROOT_RESOURCE_ID}"
}

# Function to create API resource and method
create_api_resource_method() {
    log "Creating API resource and method..."
    
    # Check if /convert resource already exists
    EXISTING_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query "items[?pathPart=='convert'].id" --output text 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_RESOURCE_ID" ] && [ "$EXISTING_RESOURCE_ID" != "None" ]; then
        warn "/convert resource already exists, using existing resource"
        RESOURCE_ID="$EXISTING_RESOURCE_ID"
    else
        # Create the /convert resource
        RESOURCE_ID=$(aws apigateway create-resource \
            --rest-api-id "${API_ID}" \
            --parent-id "${ROOT_RESOURCE_ID}" \
            --path-part convert \
            --query 'id' --output text)
        
        success "/convert resource created: ${RESOURCE_ID}"
    fi
    
    # Create POST method on /convert resource (if it doesn't exist)
    if ! aws apigateway get-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${RESOURCE_ID}" \
        --http-method POST >/dev/null 2>&1; then
        
        aws apigateway put-method \
            --rest-api-id "${API_ID}" \
            --resource-id "${RESOURCE_ID}" \
            --http-method POST \
            --authorization-type NONE
        
        success "POST method created on /convert resource"
    else
        warn "POST method already exists on /convert resource"
    fi
    
    # Configure method integration with Lambda
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${RESOURCE_ID}" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${FUNCTION_ARN}/invocations"
    
    echo "RESOURCE_ID=${RESOURCE_ID}" >> .deployment-vars
    
    success "API resource and method configured"
}

# Function to grant API Gateway permission to invoke Lambda
grant_api_gateway_permission() {
    log "Granting API Gateway permission to invoke Lambda..."
    
    # Remove existing permission if it exists
    aws lambda remove-permission \
        --function-name "${FUNCTION_NAME}" \
        --statement-id apigateway-invoke-permission >/dev/null 2>&1 || true
    
    # Grant API Gateway permission to invoke Lambda function
    aws lambda add-permission \
        --function-name "${FUNCTION_NAME}" \
        --statement-id apigateway-invoke-permission \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*"
    
    success "API Gateway invoke permission granted"
}

# Function to deploy API to stage
deploy_api_stage() {
    log "Deploying API to production stage..."
    
    # Deploy API to production stage
    aws apigateway create-deployment \
        --rest-api-id "${API_ID}" \
        --stage-name prod \
        --description "Production deployment of timezone converter API"
    
    # Store the API endpoint URL
    API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    echo "API_ENDPOINT=${API_ENDPOINT}" >> .deployment-vars
    
    success "API deployed to production stage"
    success "API endpoint: ${API_ENDPOINT}/convert"
}

# Function to test the deployment
test_deployment() {
    log "Testing the deployment..."
    
    # Wait a moment for deployment to be ready
    sleep 5
    
    # Test Lambda function directly
    log "Testing Lambda function directly..."
    aws lambda invoke \
        --function-name "${FUNCTION_NAME}" \
        --payload '{"timestamp":"2025-07-12T15:30:00","from_timezone":"UTC","to_timezone":"America/New_York"}' \
        response.json >/dev/null
    
    if [ -f response.json ]; then
        success "Lambda function test completed"
        if command_exists python; then
            log "Lambda response:"
            cat response.json | python -m json.tool 2>/dev/null || cat response.json
        fi
    fi
    
    # Test API Gateway endpoint if curl is available
    if command_exists curl; then
        log "Testing API Gateway endpoint..."
        
        HTTP_STATUS=$(curl -s -o api_response.json -w "%{http_code}" \
            -X POST "${API_ENDPOINT}/convert" \
            -H "Content-Type: application/json" \
            -d '{
              "timestamp": "2025-07-12T15:30:00",
              "from_timezone": "UTC", 
              "to_timezone": "America/Los_Angeles"
            }')
        
        if [ "$HTTP_STATUS" = "200" ]; then
            success "API Gateway test completed successfully"
            if command_exists python && [ -f api_response.json ]; then
                log "API response:"
                cat api_response.json | python -m json.tool 2>/dev/null || cat api_response.json
            fi
        else
            warn "API Gateway test returned HTTP status: $HTTP_STATUS"
            if [ -f api_response.json ]; then
                cat api_response.json
            fi
        fi
    else
        warn "curl not available, skipping API Gateway test"
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo ""
    echo "🚀 Timezone Converter API deployed successfully!"
    echo ""
    echo "📋 Resource Details:"
    echo "   • Lambda Function: ${FUNCTION_NAME}"
    echo "   • IAM Role: ${ROLE_NAME}"
    echo "   • API Gateway: ${API_NAME}"
    echo "   • API Endpoint: ${API_ENDPOINT}/convert"
    echo ""
    echo "🧪 Test your API:"
    echo "   curl -X POST ${API_ENDPOINT}/convert \\"
    echo "        -H \"Content-Type: application/json\" \\"
    echo "        -d '{\"timestamp\":\"2025-07-12T15:30:00\",\"to_timezone\":\"America/New_York\"}'"
    echo ""
    echo "🗑️  To clean up resources, run: ./destroy.sh"
    echo ""
    success "Deployment completed successfully!"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f trust-policy.json lambda_function.py lambda-deployment.zip response.json api_response.json
    success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting deployment of Simple Timezone Converter..."
    
    # Run all deployment steps
    check_prerequisites
    validate_aws_credentials
    setup_environment
    create_iam_role
    create_lambda_code
    deploy_lambda_function
    create_api_gateway
    create_api_resource_method
    grant_api_gateway_permission
    deploy_api_stage
    test_deployment
    display_summary
    cleanup_temp_files
    
    success "Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted. Run ./destroy.sh to clean up any created resources."; exit 1' INT TERM

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi