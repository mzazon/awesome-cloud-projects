#!/bin/bash

# Deploy script for Request/Response Transformation with VTL Templates and Custom Models
# This script automates the deployment of API Gateway with advanced transformations

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEPLOYMENT_CONFIG="${SCRIPT_DIR}/deployment.config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Colored output functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Cleanup function for script interruption
cleanup() {
    if [ $? -ne 0 ]; then
        error "Deployment failed. Check ${LOG_FILE} for details."
        error "Run ./destroy.sh to clean up any partially created resources."
    fi
}

trap cleanup EXIT

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it and try again."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if jq is installed (for JSON processing)
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it for JSON processing."
        exit 1
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        error "zip is not installed. Please install it for Lambda packaging."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export API_NAME="transformation-api-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="data-processor-${RANDOM_SUFFIX}"
    export BUCKET_NAME="api-data-store-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="transformation-lambda-role-${RANDOM_SUFFIX}"
    
    # Save configuration for cleanup
    cat > "${DEPLOYMENT_CONFIG}" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
API_NAME=${API_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
BUCKET_NAME=${BUCKET_NAME}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables configured"
    info "Region: ${AWS_REGION}"
    info "Account ID: ${AWS_ACCOUNT_ID}"
    info "Random suffix: ${RANDOM_SUFFIX}"
}

# Function to create S3 bucket
create_s3_bucket() {
    info "Creating S3 bucket..."
    
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        warning "S3 bucket ${BUCKET_NAME} already exists"
    else
        if [ "${AWS_REGION}" = "us-east-1" ]; then
            aws s3api create-bucket --bucket "${BUCKET_NAME}"
        else
            aws s3api create-bucket --bucket "${BUCKET_NAME}" \
                --create-bucket-configuration LocationConstraint="${AWS_REGION}"
        fi
        success "Created S3 bucket: ${BUCKET_NAME}"
    fi
    
    # Enable versioning for better data management
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    success "S3 bucket created and configured"
}

# Function to create IAM role for Lambda
create_lambda_role() {
    info "Creating IAM role for Lambda..."
    
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &>/dev/null; then
        warning "IAM role ${LAMBDA_ROLE_NAME} already exists"
    else
        aws iam create-role \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --assume-role-policy-document '{
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
            }'
        success "Created IAM role: ${LAMBDA_ROLE_NAME}"
    fi
    
    # Attach policies
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
    
    # Wait for role propagation
    info "Waiting for IAM role propagation..."
    sleep 15
    
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    
    success "IAM role created and configured"
}

# Function to create and deploy Lambda function
create_lambda_function() {
    info "Creating Lambda function..."
    
    # Create Lambda function code
    cat > "${SCRIPT_DIR}/data-processor.py" << 'EOF'
import json
import boto3
import uuid
from datetime import datetime

s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Log the transformed request for debugging
        print(f"Received event: {json.dumps(event)}")
        
        # Simulate processing based on event structure
        if 'user_data' in event:
            # Process user data from transformed request
            response_data = {
                'id': str(uuid.uuid4()),
                'processed_at': datetime.utcnow().isoformat(),
                'user_id': event['user_data'].get('id'),
                'full_name': f"{event['user_data'].get('first_name', '')} {event['user_data'].get('last_name', '')}".strip(),
                'profile': {
                    'email': event['user_data'].get('email'),
                    'phone': event['user_data'].get('phone'),
                    'preferences': event['user_data'].get('preferences', {})
                },
                'status': 'processed',
                'metadata': {
                    'source': 'api_gateway_transformation',
                    'version': '2.0'
                }
            }
        else:
            # Handle generic data processing
            response_data = {
                'id': str(uuid.uuid4()),
                'processed_at': datetime.utcnow().isoformat(),
                'input_data': event,
                'status': 'processed',
                'transformation_applied': True
            }
        
        return {
            'statusCode': 200,
            'body': response_data
        }
        
    except Exception as e:
        print(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': 'Internal processing error',
                'message': str(e),
                'request_id': context.aws_request_id
            }
        }
EOF
    
    # Package Lambda function
    cd "${SCRIPT_DIR}"
    zip -q data-processor.zip data-processor.py
    
    # Create or update Lambda function
    if aws lambda get-function --function-name "${FUNCTION_NAME}" &>/dev/null; then
        warning "Lambda function ${FUNCTION_NAME} already exists, updating..."
        aws lambda update-function-code \
            --function-name "${FUNCTION_NAME}" \
            --zip-file fileb://data-processor.zip
    else
        aws lambda create-function \
            --function-name "${FUNCTION_NAME}" \
            --runtime python3.9 \
            --role "${LAMBDA_ROLE_ARN}" \
            --handler data-processor.lambda_handler \
            --zip-file fileb://data-processor.zip \
            --description "Data processor with transformation support" \
            --timeout 30 \
            --memory-size 256
    fi
    
    export LAMBDA_ARN=$(aws lambda get-function \
        --function-name "${FUNCTION_NAME}" \
        --query Configuration.FunctionArn --output text)
    
    success "Lambda function created: ${FUNCTION_NAME}"
    
    # Update deployment config
    echo "LAMBDA_ARN=${LAMBDA_ARN}" >> "${DEPLOYMENT_CONFIG}"
}

# Function to create API Gateway with models
create_api_gateway() {
    info "Creating API Gateway with custom models..."
    
    # Create REST API
    export API_ID=$(aws apigateway create-rest-api \
        --name "${API_NAME}" \
        --description "API with advanced request/response transformation" \
        --endpoint-configuration types=REGIONAL \
        --query id --output text)
    
    success "Created API Gateway: ${API_ID}"
    
    # Create request model
    aws apigateway create-model \
        --rest-api-id "${API_ID}" \
        --name UserCreateRequest \
        --content-type application/json \
        --schema '{
            "$schema": "http://json-schema.org/draft-04/schema#",
            "title": "User Creation Request",
            "type": "object",
            "required": ["firstName", "lastName", "email"],
            "properties": {
                "firstName": {
                    "type": "string",
                    "minLength": 1,
                    "maxLength": 50,
                    "pattern": "^[a-zA-Z\\s]+$"
                },
                "lastName": {
                    "type": "string",
                    "minLength": 1,
                    "maxLength": 50,
                    "pattern": "^[a-zA-Z\\s]+$"
                },
                "email": {
                    "type": "string",
                    "format": "email",
                    "maxLength": 100
                },
                "phoneNumber": {
                    "type": "string",
                    "pattern": "^\\+?[1-9]\\d{1,14}$"
                },
                "preferences": {
                    "type": "object",
                    "properties": {
                        "notifications": {"type": "boolean"},
                        "theme": {"type": "string", "enum": ["light", "dark"]},
                        "language": {"type": "string", "pattern": "^[a-z]{2}$"}
                    }
                },
                "metadata": {
                    "type": "object",
                    "additionalProperties": true
                }
            },
            "additionalProperties": false
        }'
    
    # Create response model
    aws apigateway create-model \
        --rest-api-id "${API_ID}" \
        --name UserResponse \
        --content-type application/json \
        --schema '{
            "$schema": "http://json-schema.org/draft-04/schema#",
            "title": "User Response",
            "type": "object",
            "properties": {
                "success": {"type": "boolean"},
                "data": {
                    "type": "object",
                    "properties": {
                        "userId": {"type": "string"},
                        "displayName": {"type": "string"},
                        "contactInfo": {
                            "type": "object",
                            "properties": {
                                "email": {"type": "string"},
                                "phone": {"type": "string"}
                            }
                        },
                        "createdAt": {"type": "string"},
                        "profileComplete": {"type": "boolean"}
                    }
                },
                "links": {
                    "type": "object",
                    "properties": {
                        "self": {"type": "string"},
                        "profile": {"type": "string"}
                    }
                }
            }
        }'
    
    # Create error response model
    aws apigateway create-model \
        --rest-api-id "${API_ID}" \
        --name ErrorResponse \
        --content-type application/json \
        --schema '{
            "$schema": "http://json-schema.org/draft-04/schema#",
            "title": "Error Response",
            "type": "object",
            "required": ["error", "message"],
            "properties": {
                "error": {"type": "string"},
                "message": {"type": "string"},
                "details": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "field": {"type": "string"},
                            "code": {"type": "string"},
                            "message": {"type": "string"}
                        }
                    }
                },
                "timestamp": {"type": "string"},
                "path": {"type": "string"}
            }
        }'
    
    success "Created API Gateway models"
    
    # Update deployment config
    echo "API_ID=${API_ID}" >> "${DEPLOYMENT_CONFIG}"
}

# Function to create resources and methods
create_api_resources() {
    info "Creating API resources and methods..."
    
    # Get root resource ID
    export ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query 'items[?path==`/`].id' --output text)
    
    # Create /users resource
    export USERS_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "${API_ID}" \
        --parent-id "${ROOT_RESOURCE_ID}" \
        --path-part users \
        --query id --output text)
    
    # Create request validator
    export VALIDATOR_ID=$(aws apigateway create-request-validator \
        --rest-api-id "${API_ID}" \
        --name comprehensive-validator \
        --validate-request-body true \
        --validate-request-parameters true \
        --query id --output text)
    
    success "Created API resources and validator"
    
    # Update deployment config
    echo "USERS_RESOURCE_ID=${USERS_RESOURCE_ID}" >> "${DEPLOYMENT_CONFIG}"
    echo "VALIDATOR_ID=${VALIDATOR_ID}" >> "${DEPLOYMENT_CONFIG}"
}

# Function to create VTL mapping templates
create_vtl_templates() {
    info "Creating VTL mapping templates..."
    
    # Create request mapping template
    cat > "${SCRIPT_DIR}/request_template.vtl" << 'EOF'
#set($inputRoot = $input.path('$'))
#set($context = $context)
#set($util = $util)

## Transform incoming request to backend format
{
    "user_data": {
        "id": "$util.escapeJavaScript($context.requestId)",
        "first_name": "$util.escapeJavaScript($inputRoot.firstName)",
        "last_name": "$util.escapeJavaScript($inputRoot.lastName)",
        "email": "$util.escapeJavaScript($inputRoot.email.toLowerCase())",
        #if($inputRoot.phoneNumber && $inputRoot.phoneNumber != "")
        "phone": "$util.escapeJavaScript($inputRoot.phoneNumber)",
        #end
        #if($inputRoot.preferences)
        "preferences": {
            #if($inputRoot.preferences.notifications)
            "email_notifications": $inputRoot.preferences.notifications,
            #end
            #if($inputRoot.preferences.theme)
            "ui_theme": "$util.escapeJavaScript($inputRoot.preferences.theme)",
            #end
            #if($inputRoot.preferences.language)
            "locale": "$util.escapeJavaScript($inputRoot.preferences.language)",
            #end
            "auto_save": true
        },
        #end
        "source": "api_gateway",
        "created_via": "rest_api"
    },
    "request_context": {
        "request_id": "$context.requestId",
        "api_id": "$context.apiId",
        "stage": "$context.stage",
        "resource_path": "$context.resourcePath",
        "http_method": "$context.httpMethod",
        "source_ip": "$context.identity.sourceIp",
        "user_agent": "$util.escapeJavaScript($context.identity.userAgent)",
        "request_time": "$context.requestTime",
        "request_time_epoch": $context.requestTimeEpoch
    },
    #if($inputRoot.metadata)
    "additional_metadata": $input.json('$.metadata'),
    #end
    "processing_flags": {
        "validate_email": true,
        "send_welcome": true,
        "create_profile": true
    }
}
EOF
    
    # Create response mapping template
    cat > "${SCRIPT_DIR}/response_template.vtl" << 'EOF'
#set($inputRoot = $input.path('$'))
#set($context = $context)

## Transform backend response to standardized API format
{
    "success": true,
    "data": {
        "userId": "$util.escapeJavaScript($inputRoot.id)",
        "displayName": "$util.escapeJavaScript($inputRoot.full_name)",
        "contactInfo": {
            #if($inputRoot.profile.email)
            "email": "$util.escapeJavaScript($inputRoot.profile.email)",
            #end
            #if($inputRoot.profile.phone)
            "phone": "$util.escapeJavaScript($inputRoot.profile.phone)"
            #end
        },
        "createdAt": "$util.escapeJavaScript($inputRoot.processed_at)",
        "profileComplete": #if($inputRoot.profile.email && $inputRoot.full_name != "")true#{else}false#end,
        "preferences": #if($inputRoot.profile.preferences)$input.json('$.profile.preferences')#{else}{}#end
    },
    "metadata": {
        "processingId": "$util.escapeJavaScript($inputRoot.id)",
        "version": #if($inputRoot.metadata.version)"$util.escapeJavaScript($inputRoot.metadata.version)"#{else}"1.0"#end,
        "processedAt": "$util.escapeJavaScript($inputRoot.processed_at)"
    },
    "links": {
        "self": "https://$context.domainName/$context.stage/users/$util.escapeJavaScript($inputRoot.id)",
        "profile": "https://$context.domainName/$context.stage/users/$util.escapeJavaScript($inputRoot.id)/profile"
    }
}
EOF
    
    # Create error response template
    cat > "${SCRIPT_DIR}/error_template.vtl" << 'EOF'
#set($inputRoot = $input.path('$.errorMessage'))
#set($context = $context)

{
    "error": "PROCESSING_ERROR",
    "message": #if($inputRoot)"$util.escapeJavaScript($inputRoot)"#{else}"An error occurred while processing your request"#end,
    "details": [
        {
            "field": "request",
            "code": "LAMBDA_EXECUTION_ERROR",
            "message": "Backend service encountered an error"
        }
    ],
    "timestamp": "$context.requestTime",
    "path": "$context.resourcePath",
    "requestId": "$context.requestId"
}
EOF
    
    success "Created VTL mapping templates"
}

# Function to configure API methods
configure_api_methods() {
    info "Configuring API methods..."
    
    # Create POST method with validation
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${USERS_RESOURCE_ID}" \
        --http-method POST \
        --authorization-type NONE \
        --request-validator-id "${VALIDATOR_ID}" \
        --request-models application/json=UserCreateRequest
    
    # Create Lambda integration with request transformation
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${USERS_RESOURCE_ID}" \
        --http-method POST \
        --type AWS \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
        --passthrough-behavior NEVER \
        --request-templates "application/json=$(cat "${SCRIPT_DIR}/request_template.vtl")"
    
    # Configure method responses
    aws apigateway put-method-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${USERS_RESOURCE_ID}" \
        --http-method POST \
        --status-code 200 \
        --response-models application/json=UserResponse
    
    aws apigateway put-method-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${USERS_RESOURCE_ID}" \
        --http-method POST \
        --status-code 400 \
        --response-models application/json=ErrorResponse
    
    aws apigateway put-method-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${USERS_RESOURCE_ID}" \
        --http-method POST \
        --status-code 500 \
        --response-models application/json=ErrorResponse
    
    # Configure integration responses
    aws apigateway put-integration-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${USERS_RESOURCE_ID}" \
        --http-method POST \
        --status-code 200 \
        --response-templates "application/json=$(cat "${SCRIPT_DIR}/response_template.vtl")"
    
    aws apigateway put-integration-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${USERS_RESOURCE_ID}" \
        --http-method POST \
        --status-code 500 \
        --selection-pattern '.*"statusCode": 500.*' \
        --response-templates "application/json=$(cat "${SCRIPT_DIR}/error_template.vtl")"
    
    success "Configured API methods with transformations"
}

# Function to create GET method with query parameters
create_get_method() {
    info "Creating GET method with query parameter transformation..."
    
    # Create GET method for data retrieval
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${USERS_RESOURCE_ID}" \
        --http-method GET \
        --authorization-type NONE \
        --request-parameters \
            method.request.querystring.limit=false \
            method.request.querystring.offset=false \
            method.request.querystring.filter=false \
            method.request.querystring.sort=false
    
    # Create query parameter transformation template
    cat > "${SCRIPT_DIR}/get_request_template.vtl" << 'EOF'
{
    "operation": "list_users",
    "pagination": {
        "limit": #if($input.params('limit'))$input.params('limit')#{else}10#end,
        "offset": #if($input.params('offset'))$input.params('offset')#{else}0#end
    },
    #if($input.params('filter'))
    "filters": {
        #set($filterParam = $input.params('filter'))
        #if($filterParam.contains(':'))
            #set($filterParts = $filterParam.split(':'))
            "$util.escapeJavaScript($filterParts[0])": "$util.escapeJavaScript($filterParts[1])"
        #else
            "search": "$util.escapeJavaScript($filterParam)"
        #end
    },
    #end
    #if($input.params('sort'))
    "sorting": {
        #set($sortParam = $input.params('sort'))
        #if($sortParam.startsWith('-'))
            "field": "$util.escapeJavaScript($sortParam.substring(1))",
            "direction": "desc"
        #else
            "field": "$util.escapeJavaScript($sortParam)",
            "direction": "asc"
        #end
    },
    #end
    "request_context": {
        "request_id": "$context.requestId",
        "source_ip": "$context.identity.sourceIp",
        "user_agent": "$util.escapeJavaScript($context.identity.userAgent)"
    }
}
EOF
    
    # Create integration for GET method
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${USERS_RESOURCE_ID}" \
        --http-method GET \
        --type AWS \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
        --request-templates "application/json=$(cat "${SCRIPT_DIR}/get_request_template.vtl")"
    
    # Configure GET method responses
    aws apigateway put-method-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${USERS_RESOURCE_ID}" \
        --http-method GET \
        --status-code 200
    
    aws apigateway put-integration-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${USERS_RESOURCE_ID}" \
        --http-method GET \
        --status-code 200
    
    success "Created GET method with query parameter transformation"
}

# Function to configure gateway responses
configure_gateway_responses() {
    info "Configuring custom gateway responses..."
    
    # Create validation error template
    cat > "${SCRIPT_DIR}/validation_error_template.vtl" << 'EOF'
{
    "error": "VALIDATION_ERROR",
    "message": "Request validation failed",
    "details": [
        #foreach($error in $context.error.validationErrorString.split(','))
        {
            "field": #if($error.contains('Invalid request body'))"body"#{elseif($error.contains('required'))$error.split("'")[1]#{else}"unknown"#end,
            "code": "VALIDATION_FAILED",
            "message": "$util.escapeJavaScript($error.trim())"
        }#if($foreach.hasNext),#end
        #end
    ],
    "timestamp": "$context.requestTime",
    "path": "$context.resourcePath",
    "requestId": "$context.requestId"
}
EOF
    
    # Configure gateway responses
    aws apigateway put-gateway-response \
        --rest-api-id "${API_ID}" \
        --response-type BAD_REQUEST_BODY \
        --status-code 400 \
        --response-templates "application/json=$(cat "${SCRIPT_DIR}/validation_error_template.vtl")"
    
    aws apigateway put-gateway-response \
        --rest-api-id "${API_ID}" \
        --response-type UNAUTHORIZED \
        --status-code 401 \
        --response-templates 'application/json={
            "error": "UNAUTHORIZED",
            "message": "Authentication required",
            "timestamp": "$context.requestTime",
            "path": "$context.resourcePath"
        }'
    
    success "Configured custom gateway responses"
}

# Function to grant permissions and deploy API
deploy_api() {
    info "Granting permissions and deploying API..."
    
    # Grant API Gateway permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${FUNCTION_NAME}" \
        --statement-id "api-gateway-transform-${RANDOM_SUFFIX}" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" \
        --output table || warning "Permission may already exist"
    
    # Deploy API to staging
    export DEPLOYMENT_ID=$(aws apigateway create-deployment \
        --rest-api-id "${API_ID}" \
        --stage-name staging \
        --stage-description "Staging environment for transformation testing" \
        --description "Initial deployment with VTL transformations" \
        --query id --output text)
    
    # Enable detailed CloudWatch logging
    aws apigateway update-stage \
        --rest-api-id "${API_ID}" \
        --stage-name staging \
        --patch-operations \
            'op=replace,path=/*/*/logging/loglevel,value=INFO' \
            'op=replace,path=/*/*/logging/dataTrace,value=true' \
            'op=replace,path=/*/*/metricsEnabled,value=true' \
        --output table || warning "Logging configuration may have failed"
    
    export API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/staging"
    
    success "API deployed successfully"
    
    # Update deployment config
    echo "DEPLOYMENT_ID=${DEPLOYMENT_ID}" >> "${DEPLOYMENT_CONFIG}"
    echo "API_ENDPOINT=${API_ENDPOINT}" >> "${DEPLOYMENT_CONFIG}"
}

# Function to display deployment summary
display_summary() {
    info "Deployment Summary:"
    echo "=========================================="
    echo "API Gateway ID: ${API_ID}"
    echo "API Endpoint: ${API_ENDPOINT}"
    echo "Lambda Function: ${FUNCTION_NAME}"
    echo "S3 Bucket: ${BUCKET_NAME}"
    echo "IAM Role: ${LAMBDA_ROLE_NAME}"
    echo "Region: ${AWS_REGION}"
    echo "=========================================="
    echo ""
    echo "Test the API with:"
    echo "curl -X POST '${API_ENDPOINT}/users' \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -d '{\"firstName\":\"John\",\"lastName\":\"Doe\",\"email\":\"john@example.com\"}'"
    echo ""
    echo "Configuration saved to: ${DEPLOYMENT_CONFIG}"
    echo "Deployment log saved to: ${LOG_FILE}"
}

# Main deployment function
main() {
    info "Starting deployment of Request/Response Transformation API..."
    
    # Initialize log file
    echo "Deployment started at $(date)" > "${LOG_FILE}"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_lambda_role
    create_lambda_function
    create_api_gateway
    create_api_resources
    create_vtl_templates
    configure_api_methods
    create_get_method
    configure_gateway_responses
    deploy_api
    
    success "Deployment completed successfully!"
    display_summary
}

# Run main function
main "$@"