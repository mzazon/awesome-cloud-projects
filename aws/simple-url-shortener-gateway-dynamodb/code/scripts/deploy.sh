#!/bin/bash

# AWS Simple URL Shortener Deployment Script
# Creates API Gateway, Lambda functions, and DynamoDB table for URL shortening service

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging configuration
LOG_FILE="deployment_$(date +%Y%m%d_%H%M%S).log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partially created resources..."
    if [[ -n "${TABLE_NAME:-}" ]]; then
        aws dynamodb delete-table --table-name "${TABLE_NAME}" 2>/dev/null || true
    fi
    if [[ -n "${ROLE_NAME:-}" ]]; then
        aws iam detach-role-policy --role-name "${ROLE_NAME}" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
        aws iam detach-role-policy --role-name "${ROLE_NAME}" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-dynamodb-policy" 2>/dev/null || true
        aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-dynamodb-policy" 2>/dev/null || true
        aws iam delete-role --role-name "${ROLE_NAME}" 2>/dev/null || true
    fi
    if [[ -n "${CREATE_FUNCTION_NAME:-}" ]]; then
        aws lambda delete-function --function-name "${CREATE_FUNCTION_NAME}" 2>/dev/null || true
    fi
    if [[ -n "${REDIRECT_FUNCTION_NAME:-}" ]]; then
        aws lambda delete-function --function-name "${REDIRECT_FUNCTION_NAME}" 2>/dev/null || true
    fi
    if [[ -n "${API_ID:-}" ]]; then
        aws apigateway delete-rest-api --rest-api-id "${API_ID}" 2>/dev/null || true
    fi
    # Clean up temporary files
    rm -f trust-policy.json dynamodb-policy.json
    rm -f create-function.py redirect-function.py
    rm -f create-function.zip redirect-function.zip
    exit 1
}

trap cleanup_on_error ERR

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Command '$1' is required but not installed."
        exit 1
    fi
}

# Function to validate AWS credentials
validate_aws_credentials() {
    log_info "Validating AWS credentials..."
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    log_success "AWS credentials validated"
}

# Function to check if resource already exists
check_existing_resources() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "$resource_type" in
        "table")
            if aws dynamodb describe-table --table-name "$resource_name" &>/dev/null; then
                return 0
            fi
            ;;
        "role")
            if aws iam get-role --role-name "$resource_name" &>/dev/null; then
                return 0
            fi
            ;;
        "function")
            if aws lambda get-function --function-name "$resource_name" &>/dev/null; then
                return 0
            fi
            ;;
        "api")
            if aws apigateway get-rest-apis --query "items[?name=='$resource_name'].id" --output text | grep -q .; then
                return 0
            fi
            ;;
    esac
    return 1
}

# Function to wait for resource readiness
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for $resource_type '$resource_name' to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        case "$resource_type" in
            "table")
                if [ "$(aws dynamodb describe-table --table-name "$resource_name" --query 'Table.TableStatus' --output text 2>/dev/null)" = "ACTIVE" ]; then
                    log_success "$resource_type '$resource_name' is ready"
                    return 0
                fi
                ;;
            "function")
                local state=$(aws lambda get-function --function-name "$resource_name" --query 'Configuration.State' --output text 2>/dev/null)
                if [ "$state" = "Active" ]; then
                    log_success "$resource_type '$resource_name' is ready"
                    return 0
                fi
                ;;
        esac
        
        log_info "Attempt $attempt/$max_attempts: $resource_type not ready yet, waiting..."
        sleep 10
        ((attempt++))
    done
    
    log_error "$resource_type '$resource_name' did not become ready within expected time"
    return 1
}

# Main deployment function
main() {
    log_info "Starting AWS Simple URL Shortener deployment..."
    log_info "Deployment log: ${LOG_FILE}"
    
    # Prerequisites check
    log_info "Checking prerequisites..."
    check_command "aws"
    check_command "zip"
    check_command "curl"
    validate_aws_credentials
    
    # Set environment variables for AWS configuration
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        log_error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set resource names with unique suffix
    export TABLE_NAME="url-shortener-${RANDOM_SUFFIX}"
    export ROLE_NAME="url-shortener-lambda-role-${RANDOM_SUFFIX}"
    export CREATE_FUNCTION_NAME="url-shortener-create-${RANDOM_SUFFIX}"
    export REDIRECT_FUNCTION_NAME="url-shortener-redirect-${RANDOM_SUFFIX}"
    export API_NAME="url-shortener-api-${RANDOM_SUFFIX}"
    
    log_info "Using AWS Region: ${AWS_REGION}"
    log_info "Using AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "Generated resource suffix: ${RANDOM_SUFFIX}"
    
    # Check for existing resources
    if check_existing_resources "table" "${TABLE_NAME}"; then
        log_warning "DynamoDB table ${TABLE_NAME} already exists, skipping creation"
    else
        # Step 1: Create DynamoDB Table
        log_info "Step 1: Creating DynamoDB table..."
        aws dynamodb create-table \
            --table-name "${TABLE_NAME}" \
            --attribute-definitions \
                AttributeName=shortCode,AttributeType=S \
            --key-schema \
                AttributeName=shortCode,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --tags Key=Project,Value=URLShortener,Key=Environment,Value=Development
        
        wait_for_resource "table" "${TABLE_NAME}"
        log_success "DynamoDB table ${TABLE_NAME} created successfully"
    fi
    
    # Step 2: Create IAM Role
    if check_existing_resources "role" "${ROLE_NAME}"; then
        log_warning "IAM role ${ROLE_NAME} already exists, skipping creation"
    else
        log_info "Step 2: Creating IAM role for Lambda functions..."
        
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
        
        # Create IAM role for Lambda functions
        aws iam create-role \
            --role-name "${ROLE_NAME}" \
            --assume-role-policy-document file://trust-policy.json \
            --tags Key=Project,Value=URLShortener
        
        # Attach basic Lambda execution policy
        aws iam attach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        log_success "IAM role ${ROLE_NAME} created with basic permissions"
    fi
    
    # Step 3: Create DynamoDB Access Policy
    log_info "Step 3: Creating DynamoDB access policy..."
    
    # Create policy for DynamoDB access
    cat > dynamodb-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${TABLE_NAME}"
        }
    ]
}
EOF
    
    # Create and attach DynamoDB policy (check if it already exists)
    if ! aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-dynamodb-policy" &>/dev/null; then
        aws iam create-policy \
            --policy-name "${ROLE_NAME}-dynamodb-policy" \
            --policy-document file://dynamodb-policy.json \
            --tags Key=Project,Value=URLShortener
    fi
    
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-dynamodb-policy"
    
    log_success "DynamoDB access policy attached to Lambda role"
    
    # Wait a moment for IAM propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
    
    # Step 4: Create Lambda Function for URL Creation
    if check_existing_resources "function" "${CREATE_FUNCTION_NAME}"; then
        log_warning "Lambda function ${CREATE_FUNCTION_NAME} already exists, skipping creation"
    else
        log_info "Step 4: Creating Lambda function for URL creation..."
        
        # Create Lambda function code for URL creation
        cat > create-function.py << 'EOF'
import json
import boto3
import string
import random
import os
import logging
from urllib.parse import urlparse

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Parse request body
        if not event.get('body'):
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS'
                },
                'body': json.dumps({'error': 'Request body is required'})
            }
        
        body = json.loads(event['body'])
        original_url = body.get('url')
        
        # Validate URL presence
        if not original_url:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS'
                },
                'body': json.dumps({'error': 'URL is required'})
            }
        
        # Validate URL format
        try:
            parsed_url = urlparse(original_url)
            if not all([parsed_url.scheme, parsed_url.netloc]):
                return {
                    'statusCode': 400,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*',
                        'Access-Control-Allow-Headers': 'Content-Type',
                        'Access-Control-Allow-Methods': 'POST, OPTIONS'
                    },
                    'body': json.dumps({'error': 'Invalid URL format'})
                }
        except Exception:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS'
                },
                'body': json.dumps({'error': 'Invalid URL format'})
            }
        
        # Generate short code (retry if collision occurs)
        max_retries = 5
        for attempt in range(max_retries):
            short_code = ''.join(random.choices(string.ascii_letters + string.digits, k=6))
            
            try:
                # Use conditional write to prevent overwriting existing codes
                table.put_item(
                    Item={
                        'shortCode': short_code,
                        'originalUrl': original_url
                    },
                    ConditionExpression='attribute_not_exists(shortCode)'
                )
                break
            except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
                if attempt == max_retries - 1:
                    raise Exception("Unable to generate unique short code after multiple attempts")
                continue
        
        logger.info(f"Created short URL: {short_code} -> {original_url}")
        
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'POST, OPTIONS'
            },
            'body': json.dumps({
                'shortCode': short_code,
                'shortUrl': f"https://your-api-gateway-url/{short_code}",
                'originalUrl': original_url
            })
        }
        
    except Exception as e:
        logger.error(f"Error creating short URL: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'POST, OPTIONS'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }
EOF
        
        # Package and create Lambda function
        zip -q create-function.zip create-function.py
        
        aws lambda create-function \
            --function-name "${CREATE_FUNCTION_NAME}" \
            --runtime python3.12 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}" \
            --handler create-function.lambda_handler \
            --zip-file fileb://create-function.zip \
            --environment Variables="{TABLE_NAME=${TABLE_NAME}}" \
            --timeout 10 \
            --tags Project=URLShortener,Environment=Development
        
        wait_for_resource "function" "${CREATE_FUNCTION_NAME}"
        log_success "Lambda function ${CREATE_FUNCTION_NAME} created for URL creation"
    fi
    
    # Step 5: Create Lambda Function for URL Redirection
    if check_existing_resources "function" "${REDIRECT_FUNCTION_NAME}"; then
        log_warning "Lambda function ${REDIRECT_FUNCTION_NAME} already exists, skipping creation"
    else
        log_info "Step 5: Creating Lambda function for URL redirection..."
        
        # Create Lambda function code for URL redirection
        cat > redirect-function.py << 'EOF'
import json
import boto3
import os
import logging
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Get short code from path parameters
        if not event.get('pathParameters') or not event['pathParameters'].get('shortCode'):
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'text/html'},
                'body': '<h1>400 - Bad Request</h1><p>Short code parameter is required</p>'
            }
        
        short_code = event['pathParameters']['shortCode']
        
        # Validate short code format (basic validation)
        if not short_code or len(short_code) != 6 or not short_code.isalnum():
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'text/html'},
                'body': '<h1>400 - Bad Request</h1><p>Invalid short code format</p>'
            }
        
        # Lookup original URL in DynamoDB
        response = table.get_item(
            Key={'shortCode': short_code}
        )
        
        if 'Item' in response:
            original_url = response['Item']['originalUrl']
            logger.info(f"Redirecting {short_code} to {original_url}")
            return {
                'statusCode': 302,
                'headers': {
                    'Location': original_url,
                    'Cache-Control': 'no-cache, no-store, must-revalidate'
                }
            }
        else:
            logger.warning(f"Short code not found: {short_code}")
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'text/html'},
                'body': '<h1>404 - Short URL not found</h1><p>The requested short URL does not exist or has expired.</p>'
            }
            
    except ClientError as e:
        logger.error(f"DynamoDB error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'text/html'},
            'body': '<h1>500 - Internal Server Error</h1><p>Database error occurred</p>'
        }
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'text/html'},
            'body': '<h1>500 - Internal Server Error</h1><p>An unexpected error occurred</p>'
        }
EOF
        
        # Package and create Lambda function
        zip -q redirect-function.zip redirect-function.py
        
        aws lambda create-function \
            --function-name "${REDIRECT_FUNCTION_NAME}" \
            --runtime python3.12 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}" \
            --handler redirect-function.lambda_handler \
            --zip-file fileb://redirect-function.zip \
            --environment Variables="{TABLE_NAME=${TABLE_NAME}}" \
            --timeout 10 \
            --tags Project=URLShortener,Environment=Development
        
        wait_for_resource "function" "${REDIRECT_FUNCTION_NAME}"
        log_success "Lambda function ${REDIRECT_FUNCTION_NAME} created for URL redirection"
    fi
    
    # Step 6: Create API Gateway REST API
    if check_existing_resources "api" "${API_NAME}"; then
        log_warning "API Gateway ${API_NAME} already exists, retrieving existing API ID"
        API_ID=$(aws apigateway get-rest-apis --query "items[?name=='${API_NAME}'].id" --output text)
    else
        log_info "Step 6: Creating API Gateway REST API..."
        
        # Create REST API
        API_ID=$(aws apigateway create-rest-api \
            --name "${API_NAME}" \
            --description "Serverless URL Shortener API" \
            --query 'id' --output text)
        
        log_success "API Gateway REST API ${API_NAME} created with ID: ${API_ID}"
    fi
    
    # Step 7: Configure API Gateway Resources and Methods
    log_info "Step 7: Configuring API Gateway resources and methods..."
    
    # Get root resource ID
    ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query 'items[0].id' --output text)
    
    # Create /shorten resource for URL creation (check if exists first)
    SHORTEN_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query "items[?pathPart=='shorten'].id" --output text)
    
    if [[ -z "${SHORTEN_RESOURCE_ID}" ]]; then
        SHORTEN_RESOURCE_ID=$(aws apigateway create-resource \
            --rest-api-id "${API_ID}" \
            --parent-id "${ROOT_RESOURCE_ID}" \
            --path-part shorten \
            --query 'id' --output text)
    fi
    
    # Create POST method for /shorten (idempotent)
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${SHORTEN_RESOURCE_ID}" \
        --http-method POST \
        --authorization-type NONE || true
    
    # Add OPTIONS method for CORS support (idempotent)
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${SHORTEN_RESOURCE_ID}" \
        --http-method OPTIONS \
        --authorization-type NONE || true
    
    # Create /{shortCode} resource for redirects (check if exists first)
    SHORTCODE_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query "items[?pathPart=='{shortCode}'].id" --output text)
    
    if [[ -z "${SHORTCODE_RESOURCE_ID}" ]]; then
        SHORTCODE_RESOURCE_ID=$(aws apigateway create-resource \
            --rest-api-id "${API_ID}" \
            --parent-id "${ROOT_RESOURCE_ID}" \
            --path-part '{shortCode}' \
            --query 'id' --output text)
    fi
    
    # Create GET method for /{shortCode} (idempotent)
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${SHORTCODE_RESOURCE_ID}" \
        --http-method GET \
        --authorization-type NONE \
        --request-parameters method.request.path.shortCode=true || true
    
    log_success "API Gateway resources and methods configured"
    
    # Step 8: Connect Lambda Functions to API Gateway
    log_info "Step 8: Connecting Lambda functions to API Gateway..."
    
    # Integrate POST /shorten with create Lambda function
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${SHORTEN_RESOURCE_ID}" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${CREATE_FUNCTION_NAME}/invocations" || true
    
    # Add CORS integration for OPTIONS method
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${SHORTEN_RESOURCE_ID}" \
        --http-method OPTIONS \
        --type MOCK \
        --request-templates '{"application/json":"{\"statusCode\": 200}"}' \
        --passthrough-behavior WHEN_NO_MATCH || true
    
    # Configure OPTIONS method response
    aws apigateway put-method-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${SHORTEN_RESOURCE_ID}" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters method.response.header.Access-Control-Allow-Headers=false,method.response.header.Access-Control-Allow-Methods=false,method.response.header.Access-Control-Allow-Origin=false || true
    
    aws apigateway put-integration-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${SHORTEN_RESOURCE_ID}" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters method.response.header.Access-Control-Allow-Headers="'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",method.response.header.Access-Control-Allow-Methods="'POST,OPTIONS'",method.response.header.Access-Control-Allow-Origin="'*'" || true
    
    # Integrate GET /{shortCode} with redirect Lambda function
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${SHORTCODE_RESOURCE_ID}" \
        --http-method GET \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${REDIRECT_FUNCTION_NAME}/invocations" || true
    
    # Grant API Gateway permission to invoke Lambda functions (idempotent)
    aws lambda add-permission \
        --function-name "${CREATE_FUNCTION_NAME}" \
        --statement-id api-gateway-invoke-create \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" 2>/dev/null || true
    
    aws lambda add-permission \
        --function-name "${REDIRECT_FUNCTION_NAME}" \
        --statement-id api-gateway-invoke-redirect \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" 2>/dev/null || true
    
    # Deploy API to stage
    log_info "Deploying API to production stage..."
    aws apigateway create-deployment \
        --rest-api-id "${API_ID}" \
        --stage-name prod \
        --description "Production deployment of URL Shortener API"
    
    # Get API endpoint URL
    API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    log_success "Lambda functions connected to API Gateway"
    
    # Clean up temporary files
    rm -f trust-policy.json dynamodb-policy.json
    rm -f create-function.py redirect-function.py
    rm -f create-function.zip redirect-function.zip
    
    # Save deployment information
    cat > deployment-info.json << EOF
{
    "deploymentTimestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "region": "${AWS_REGION}",
    "accountId": "${AWS_ACCOUNT_ID}",
    "resources": {
        "tableName": "${TABLE_NAME}",
        "roleName": "${ROLE_NAME}",
        "createFunctionName": "${CREATE_FUNCTION_NAME}",
        "redirectFunctionName": "${REDIRECT_FUNCTION_NAME}",
        "apiName": "${API_NAME}",
        "apiId": "${API_ID}",
        "apiUrl": "${API_URL}"
    }
}
EOF
    
    # Display deployment summary
    log_success "============================================"
    log_success "AWS Simple URL Shortener Deployment Complete!"
    log_success "============================================"
    log_success "API Endpoint: ${API_URL}"
    log_success "DynamoDB Table: ${TABLE_NAME}"
    log_success "Create Function: ${CREATE_FUNCTION_NAME}"
    log_success "Redirect Function: ${REDIRECT_FUNCTION_NAME}"
    log_success "IAM Role: ${ROLE_NAME}"
    log_success ""
    log_success "Test the deployment:"
    log_success "1. Create a short URL:"
    log_success "   curl -X POST ${API_URL}/shorten \\"
    log_success "        -H \"Content-Type: application/json\" \\"
    log_success "        -d '{\"url\": \"https://aws.amazon.com/lambda/\"}'"
    log_success ""
    log_success "2. Use the returned shortCode to test redirection:"
    log_success "   curl -I ${API_URL}/[shortCode]"
    log_success ""
    log_success "Deployment information saved to: deployment-info.json"
    log_success "Deployment log saved to: ${LOG_FILE}"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi