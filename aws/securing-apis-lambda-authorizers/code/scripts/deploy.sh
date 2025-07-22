#!/bin/bash

# Deployment script for Serverless API Patterns with Lambda Authorizers and API Gateway
# This script implements the complete infrastructure from the recipe with proper error handling

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
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        log_error "zip utility is not installed. Please install it first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region not configured. Please set it using 'aws configure'."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || openssl rand -hex 3)
    
    export API_NAME="secure-api-${RANDOM_SUFFIX}"
    export TOKEN_AUTH_FUNCTION="token-authorizer-${RANDOM_SUFFIX}"
    export REQUEST_AUTH_FUNCTION="request-authorizer-${RANDOM_SUFFIX}"
    export PROTECTED_FUNCTION="protected-api-${RANDOM_SUFFIX}"
    export PUBLIC_FUNCTION="public-api-${RANDOM_SUFFIX}"
    export ROLE_NAME="api-auth-role-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured"
    log_info "API Name: $API_NAME"
    log_info "AWS Region: $AWS_REGION"
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
}

# Function to create IAM role
create_iam_role() {
    log_info "Creating IAM role for Lambda functions..."
    
    # Create trust policy for Lambda service
    cat > lambda-trust-policy.json << EOF
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
    
    # Create the IAM role
    aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document file://lambda-trust-policy.json \
        --description "IAM role for serverless API Lambda functions and authorizers" \
        > /dev/null
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name $ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    export ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
    
    # Wait for role to be available
    log_info "Waiting for IAM role to be available..."
    sleep 10
    
    log_success "Created IAM role: $ROLE_ARN"
}

# Function to create Lambda authorizer functions
create_authorizer_functions() {
    log_info "Creating Lambda authorizer functions..."
    
    # Create token authorizer function code
    cat > token_authorizer.py << 'EOF'
import json
import re

def lambda_handler(event, context):
    """
    Token-based authorizer that validates Bearer tokens
    """
    print(f"Token Authorizer Event: {json.dumps(event)}")
    
    # Extract token from event
    token = event.get('authorizationToken', '')
    method_arn = event.get('methodArn', '')
    
    # Validate token format (Bearer <token>)
    if not token.startswith('Bearer '):
        raise Exception('Unauthorized')
    
    # Extract actual token
    actual_token = token.replace('Bearer ', '')
    
    # Validate token (simplified validation)
    # In production, validate JWT signature, expiration, etc.
    valid_tokens = {
        'admin-token': {
            'principalId': 'admin-user',
            'effect': 'Allow',
            'context': {
                'role': 'admin',
                'permissions': 'read,write,delete'
            }
        },
        'user-token': {
            'principalId': 'regular-user', 
            'effect': 'Allow',
            'context': {
                'role': 'user',
                'permissions': 'read'
            }
        }
    }
    
    # Check if token is valid
    if actual_token not in valid_tokens:
        raise Exception('Unauthorized')
    
    token_info = valid_tokens[actual_token]
    
    # Generate policy
    policy = generate_policy(
        token_info['principalId'],
        token_info['effect'],
        method_arn,
        token_info['context']
    )
    
    print(f"Generated Policy: {json.dumps(policy)}")
    return policy

def generate_policy(principal_id, effect, resource, context=None):
    """Generate IAM policy for API Gateway"""
    policy = {
        'principalId': principal_id,
        'policyDocument': {
            'Version': '2012-10-17',
            'Statement': [
                {
                    'Action': 'execute-api:Invoke',
                    'Effect': effect,
                    'Resource': resource
                }
            ]
        }
    }
    
    # Add context for passing additional information
    if context:
        policy['context'] = context
        
    return policy
EOF
    
    # Create request authorizer function code
    cat > request_authorizer.py << 'EOF'
import json
import base64
from urllib.parse import parse_qs

def lambda_handler(event, context):
    """
    Request-based authorizer that validates based on request context
    """
    print(f"Request Authorizer Event: {json.dumps(event)}")
    
    # Extract request details
    headers = event.get('headers', {})
    query_params = event.get('queryStringParameters', {}) or {}
    method_arn = event.get('methodArn', '')
    source_ip = event.get('requestContext', {}).get('identity', {}).get('sourceIp', '')
    
    # Check for API key in query parameters
    api_key = query_params.get('api_key', '')
    
    # Check for custom authentication header
    custom_auth = headers.get('X-Custom-Auth', '')
    
    # Validate based on multiple criteria
    principal_id = 'unknown'
    effect = 'Deny'
    context = {}
    
    # API Key validation
    if api_key == 'secret-api-key-123':
        principal_id = 'api-key-user'
        effect = 'Allow'
        context = {
            'authType': 'api-key',
            'sourceIp': source_ip,
            'permissions': 'read,write'
        }
    # Custom header validation
    elif custom_auth == 'custom-auth-value':
        principal_id = 'custom-user'
        effect = 'Allow'
        context = {
            'authType': 'custom-header',
            'sourceIp': source_ip,
            'permissions': 'read'
        }
    # IP-based validation (example)
    elif source_ip.startswith('10.') or source_ip.startswith('172.'):
        principal_id = 'internal-user'
        effect = 'Allow'
        context = {
            'authType': 'ip-whitelist',
            'sourceIp': source_ip,
            'permissions': 'read,write,delete'
        }
    
    # Generate policy
    policy = generate_policy(principal_id, effect, method_arn, context)
    
    print(f"Generated Policy: {json.dumps(policy)}")
    return policy

def generate_policy(principal_id, effect, resource, context=None):
    """Generate IAM policy for API Gateway"""
    policy = {
        'principalId': principal_id,
        'policyDocument': {
            'Version': '2012-10-17',
            'Statement': [
                {
                    'Action': 'execute-api:Invoke',
                    'Effect': effect,
                    'Resource': resource
                }
            ]
        }
    }
    
    if context:
        policy['context'] = context
        
    return policy
EOF
    
    # Package authorizer functions
    zip -q token-authorizer.zip token_authorizer.py
    zip -q request-authorizer.zip request_authorizer.py
    
    # Create token authorizer Lambda function
    aws lambda create-function \
        --function-name $TOKEN_AUTH_FUNCTION \
        --runtime python3.9 \
        --role $ROLE_ARN \
        --handler token_authorizer.lambda_handler \
        --zip-file fileb://token-authorizer.zip \
        --description "Token-based API Gateway authorizer" \
        --timeout 30 \
        > /dev/null
    
    # Create request authorizer Lambda function
    aws lambda create-function \
        --function-name $REQUEST_AUTH_FUNCTION \
        --runtime python3.9 \
        --role $ROLE_ARN \
        --handler request_authorizer.lambda_handler \
        --zip-file fileb://request-authorizer.zip \
        --description "Request-based API Gateway authorizer" \
        --timeout 30 \
        > /dev/null
    
    # Wait for functions to be ready
    log_info "Waiting for authorizer functions to be active..."
    aws lambda wait function-active --function-name $TOKEN_AUTH_FUNCTION
    aws lambda wait function-active --function-name $REQUEST_AUTH_FUNCTION
    
    export TOKEN_AUTH_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${TOKEN_AUTH_FUNCTION}"
    export REQUEST_AUTH_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${REQUEST_AUTH_FUNCTION}"
    
    log_success "Created authorizer functions"
}

# Function to create business logic Lambda functions
create_business_logic_functions() {
    log_info "Creating business logic Lambda functions..."
    
    # Create protected API function
    cat > protected_api.py << 'EOF'
import json

def lambda_handler(event, context):
    """Protected API that requires authorization"""
    
    # Extract authorization context
    auth_context = event.get('requestContext', {}).get('authorizer', {})
    principal_id = auth_context.get('principalId', 'unknown')
    
    # Get additional context passed from authorizer
    role = auth_context.get('role', 'unknown')
    permissions = auth_context.get('permissions', 'none')
    auth_type = auth_context.get('authType', 'token')
    source_ip = auth_context.get('sourceIp', 'unknown')
    
    response_data = {
        'message': 'Access granted to protected resource',
        'user': {
            'principalId': principal_id,
            'role': role,
            'permissions': permissions.split(',') if permissions != 'none' else [],
            'authType': auth_type,
            'sourceIp': source_ip
        },
        'timestamp': context.aws_request_id,
        'protected_data': {
            'secret_value': 'This is confidential information',
            'access_level': role
        }
    }
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(response_data, indent=2)
    }
EOF
    
    # Create public API function
    cat > public_api.py << 'EOF'
import json
import time

def lambda_handler(event, context):
    """Public API that doesn't require authorization"""
    
    response_data = {
        'message': 'Welcome to the public API',
        'status': 'operational',
        'timestamp': int(time.time()),
        'request_id': context.aws_request_id,
        'public_data': {
            'api_version': '1.0',
            'available_endpoints': [
                '/public/status',
                '/protected/data (requires auth)',
                '/protected/admin (requires admin auth)'
            ]
        }
    }
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(response_data, indent=2)
    }
EOF
    
    # Package and create functions
    zip -q protected-api.zip protected_api.py
    zip -q public-api.zip public_api.py
    
    aws lambda create-function \
        --function-name $PROTECTED_FUNCTION \
        --runtime python3.9 \
        --role $ROLE_ARN \
        --handler protected_api.lambda_handler \
        --zip-file fileb://protected-api.zip \
        --description "Protected API requiring authorization" \
        > /dev/null
    
    aws lambda create-function \
        --function-name $PUBLIC_FUNCTION \
        --runtime python3.9 \
        --role $ROLE_ARN \
        --handler public_api.lambda_handler \
        --zip-file fileb://public-api.zip \
        --description "Public API without authorization" \
        > /dev/null
    
    # Wait for functions to be ready
    log_info "Waiting for business logic functions to be active..."
    aws lambda wait function-active --function-name $PROTECTED_FUNCTION
    aws lambda wait function-active --function-name $PUBLIC_FUNCTION
    
    log_success "Created business logic functions"
}

# Function to create API Gateway
create_api_gateway() {
    log_info "Creating API Gateway REST API..."
    
    # Create REST API
    API_ID=$(aws apigateway create-rest-api \
        --name $API_NAME \
        --description "Serverless API with Lambda authorizers demo" \
        --query id --output text)
    
    # Get root resource ID
    ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id $API_ID \
        --query 'items[?path==`/`].id' --output text)
    
    # Create /public resource
    PUBLIC_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id $API_ID \
        --parent-id $ROOT_RESOURCE_ID \
        --path-part public \
        --query id --output text)
    
    # Create /protected resource
    PROTECTED_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id $API_ID \
        --parent-id $ROOT_RESOURCE_ID \
        --path-part protected \
        --query id --output text)
    
    # Create /protected/admin resource
    ADMIN_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id $API_ID \
        --parent-id $PROTECTED_RESOURCE_ID \
        --path-part admin \
        --query id --output text)
    
    export API_ID
    export ROOT_RESOURCE_ID
    export PUBLIC_RESOURCE_ID
    export PROTECTED_RESOURCE_ID
    export ADMIN_RESOURCE_ID
    
    log_success "Created API Gateway: $API_ID"
}

# Function to create API Gateway authorizers
create_api_authorizers() {
    log_info "Creating API Gateway authorizers..."
    
    # Create token-based authorizer
    TOKEN_AUTHORIZER_ID=$(aws apigateway create-authorizer \
        --rest-api-id $API_ID \
        --name "TokenAuthorizer" \
        --type TOKEN \
        --authorizer-uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${TOKEN_AUTH_ARN}/invocations" \
        --identity-source "method.request.header.Authorization" \
        --authorizer-result-ttl-in-seconds 300 \
        --query id --output text)
    
    # Create request-based authorizer
    REQUEST_AUTHORIZER_ID=$(aws apigateway create-authorizer \
        --rest-api-id $API_ID \
        --name "RequestAuthorizer" \
        --type REQUEST \
        --authorizer-uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${REQUEST_AUTH_ARN}/invocations" \
        --identity-source "method.request.header.X-Custom-Auth,method.request.querystring.api_key" \
        --authorizer-result-ttl-in-seconds 300 \
        --query id --output text)
    
    export TOKEN_AUTHORIZER_ID
    export REQUEST_AUTHORIZER_ID
    
    log_success "Created authorizers - Token: $TOKEN_AUTHORIZER_ID, Request: $REQUEST_AUTHORIZER_ID"
}

# Function to configure API methods and integrations
configure_api_methods() {
    log_info "Configuring API methods and integrations..."
    
    # Create public GET method (no authorization)
    aws apigateway put-method \
        --rest-api-id $API_ID \
        --resource-id $PUBLIC_RESOURCE_ID \
        --http-method GET \
        --authorization-type NONE \
        > /dev/null
    
    # Create protected GET method with token authorization
    aws apigateway put-method \
        --rest-api-id $API_ID \
        --resource-id $PROTECTED_RESOURCE_ID \
        --http-method GET \
        --authorization-type CUSTOM \
        --authorizer-id $TOKEN_AUTHORIZER_ID \
        > /dev/null
    
    # Create admin GET method with request authorization
    aws apigateway put-method \
        --rest-api-id $API_ID \
        --resource-id $ADMIN_RESOURCE_ID \
        --http-method GET \
        --authorization-type CUSTOM \
        --authorizer-id $REQUEST_AUTHORIZER_ID \
        > /dev/null
    
    # Configure public API integration
    aws apigateway put-integration \
        --rest-api-id $API_ID \
        --resource-id $PUBLIC_RESOURCE_ID \
        --http-method GET \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PUBLIC_FUNCTION}/invocations" \
        > /dev/null
    
    # Configure protected API integration  
    aws apigateway put-integration \
        --rest-api-id $API_ID \
        --resource-id $PROTECTED_RESOURCE_ID \
        --http-method GET \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROTECTED_FUNCTION}/invocations" \
        > /dev/null
    
    # Configure admin API integration
    aws apigateway put-integration \
        --rest-api-id $API_ID \
        --resource-id $ADMIN_RESOURCE_ID \
        --http-method GET \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROTECTED_FUNCTION}/invocations" \
        > /dev/null
    
    log_success "Configured API methods and integrations"
}

# Function to grant API Gateway permissions
grant_api_permissions() {
    log_info "Granting API Gateway permissions to invoke Lambda functions..."
    
    # Grant permission for public API function
    aws lambda add-permission \
        --function-name $PUBLIC_FUNCTION \
        --statement-id api-gateway-public \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" \
        > /dev/null
    
    # Grant permission for protected API function
    aws lambda add-permission \
        --function-name $PROTECTED_FUNCTION \
        --statement-id api-gateway-protected \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" \
        > /dev/null
    
    # Grant permission for token authorizer
    aws lambda add-permission \
        --function-name $TOKEN_AUTH_FUNCTION \
        --statement-id api-gateway-token-auth \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/authorizers/${TOKEN_AUTHORIZER_ID}" \
        > /dev/null
    
    # Grant permission for request authorizer
    aws lambda add-permission \
        --function-name $REQUEST_AUTH_FUNCTION \
        --statement-id api-gateway-request-auth \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/authorizers/${REQUEST_AUTHORIZER_ID}" \
        > /dev/null
    
    log_success "Granted API Gateway permissions"
}

# Function to deploy API and test
deploy_and_test_api() {
    log_info "Deploying API and running tests..."
    
    # Deploy API
    aws apigateway create-deployment \
        --rest-api-id $API_ID \
        --stage-name prod \
        --description "Production deployment with authorizers" \
        > /dev/null
    
    # Set API endpoint
    export API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    log_success "API deployed successfully!"
    log_info "API URL: $API_URL"
    
    # Wait a bit for deployment to propagate
    log_info "Waiting for API deployment to propagate..."
    sleep 15
    
    # Test endpoints
    log_info "Testing API endpoints..."
    
    echo -e "\n${BLUE}=== Testing Public Endpoint ===${NC}"
    if curl -s "$API_URL/public" | jq . 2>/dev/null; then
        log_success "Public endpoint test passed"
    else
        log_warning "Public endpoint test failed or jq not available"
    fi
    
    echo -e "\n${BLUE}=== Testing Protected Endpoint with Valid Token ===${NC}"
    if curl -s -H "Authorization: Bearer user-token" "$API_URL/protected" | jq . 2>/dev/null; then
        log_success "Protected endpoint with valid token test passed"
    else
        log_warning "Protected endpoint test failed or jq not available"
    fi
    
    echo -e "\n${BLUE}=== Testing Admin Endpoint with API Key ===${NC}"
    if curl -s "$API_URL/protected/admin?api_key=secret-api-key-123" | jq . 2>/dev/null; then
        log_success "Admin endpoint with API key test passed"
    else
        log_warning "Admin endpoint test failed or jq not available"
    fi
    
    echo -e "\n${BLUE}=== Testing Unauthorized Access ===${NC}"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/protected")
    if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        log_success "Unauthorized access properly denied (HTTP $HTTP_CODE)"
    else
        log_warning "Unauthorized access test returned unexpected code: $HTTP_CODE"
    fi
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > deployment-info.json << EOF
{
  "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "aws_region": "$AWS_REGION",
  "aws_account_id": "$AWS_ACCOUNT_ID",
  "api_gateway": {
    "api_id": "$API_ID",
    "api_url": "$API_URL",
    "stage": "prod"
  },
  "lambda_functions": {
    "token_authorizer": "$TOKEN_AUTH_FUNCTION",
    "request_authorizer": "$REQUEST_AUTH_FUNCTION",
    "protected_api": "$PROTECTED_FUNCTION",
    "public_api": "$PUBLIC_FUNCTION"
  },
  "iam_role": {
    "role_name": "$ROLE_NAME",
    "role_arn": "$ROLE_ARN"
  },
  "authorizers": {
    "token_authorizer_id": "$TOKEN_AUTHORIZER_ID",
    "request_authorizer_id": "$REQUEST_AUTHORIZER_ID"
  },
  "test_commands": {
    "public_endpoint": "curl -s '$API_URL/public'",
    "protected_with_user_token": "curl -s -H 'Authorization: Bearer user-token' '$API_URL/protected'",
    "protected_with_admin_token": "curl -s -H 'Authorization: Bearer admin-token' '$API_URL/protected'",
    "admin_with_api_key": "curl -s '$API_URL/protected/admin?api_key=secret-api-key-123'",
    "admin_with_custom_header": "curl -s -H 'X-Custom-Auth: custom-auth-value' '$API_URL/protected/admin'"
  }
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    rm -f lambda-trust-policy.json *.py *.zip
    log_success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log_info "Starting deployment of Serverless API Patterns with Lambda Authorizers"
    log_info "=================================================================="
    
    check_prerequisites
    setup_environment
    create_iam_role
    create_authorizer_functions
    create_business_logic_functions
    create_api_gateway
    create_api_authorizers
    configure_api_methods
    grant_api_permissions
    deploy_and_test_api
    save_deployment_info
    cleanup_temp_files
    
    echo -e "\n${GREEN}=================================================================="
    echo -e "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY! 🎉"
    echo -e "==================================================================${NC}"
    echo -e "\n${BLUE}API Endpoint:${NC} $API_URL"
    echo -e "\n${BLUE}Test Commands:${NC}"
    echo -e "  Public API:     curl -s '$API_URL/public'"
    echo -e "  Protected API:  curl -s -H 'Authorization: Bearer user-token' '$API_URL/protected'"
    echo -e "  Admin API:      curl -s '$API_URL/protected/admin?api_key=secret-api-key-123'"
    echo -e "\n${BLUE}Cleanup:${NC} Run './destroy.sh' to remove all resources"
    echo -e "\n${BLUE}Info:${NC} Deployment details saved in deployment-info.json"
}

# Run main function
main "$@"