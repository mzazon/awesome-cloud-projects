#!/bin/bash

# API Gateway Throttling and Rate Limiting - Deployment Script
# This script deploys a complete API Gateway solution with throttling controls,
# usage plans, and monitoring capabilities.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/../deploy.log"
TEMP_DIR="${SCRIPT_DIR}/../temp"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check $LOG_FILE for details."
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Cleaning up partial deployment..."
    
    # Remove local files
    [[ -f "${TEMP_DIR}/lambda_function.py" ]] && rm -f "${TEMP_DIR}/lambda_function.py"
    [[ -f "${TEMP_DIR}/lambda_function.zip" ]] && rm -f "${TEMP_DIR}/lambda_function.zip"
    
    # Note: AWS resources are left for manual cleanup to avoid data loss
    log_warning "AWS resources may need manual cleanup. Run destroy.sh for complete cleanup."
}

trap cleanup_on_error ERR

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check required tools
    local required_tools=("zip" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error_exit "$tool is not installed. Please install $tool."
        fi
    done
    
    # Check AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            error_exit "AWS region not set. Configure region with 'aws configure' or set AWS_REGION environment variable."
        fi
    fi
    
    log_success "Prerequisites check passed"
}

# Environment setup function
setup_environment() {
    log "Setting up environment variables..."
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    # Set environment variables
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export API_NAME="throttling-demo-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="api-backend-${RANDOM_SUFFIX}"
    export STAGE_NAME="prod"
    export IAM_ROLE_NAME="lambda-execution-role-${RANDOM_SUFFIX}"
    
    # Save variables for destroy script
    cat > "${SCRIPT_DIR}/../.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
API_NAME=${API_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
STAGE_NAME=${STAGE_NAME}
IAM_ROLE_NAME=${IAM_ROLE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment setup complete"
    log "API Name: ${API_NAME}"
    log "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log "Region: ${AWS_REGION}"
}

# Create Lambda function and IAM role
create_lambda_backend() {
    log "Creating Lambda backend function..."
    
    # Create Lambda function code
    cat > "${TEMP_DIR}/lambda_function.py" << 'EOF'
import json
import time
import os

def lambda_handler(event, context):
    # Simulate some processing time
    time.sleep(0.1)
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'message': 'Hello from throttled API!',
            'timestamp': int(time.time()),
            'requestId': context.aws_request_id,
            'region': os.environ.get('AWS_REGION', 'unknown')
        })
    }
EOF
    
    # Create deployment package
    cd "$TEMP_DIR"
    zip -q lambda_function.zip lambda_function.py || error_exit "Failed to create Lambda deployment package"
    cd - > /dev/null
    
    # Create IAM role for Lambda
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
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
        }' || error_exit "Failed to create IAM role"
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || error_exit "Failed to attach IAM policy"
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 15
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}" \
        --handler lambda_function.lambda_handler \
        --zip-file "fileb://${TEMP_DIR}/lambda_function.zip" \
        --timeout 30 \
        --memory-size 128 \
        --description "Backend function for API throttling demo" || error_exit "Failed to create Lambda function"
    
    # Get Lambda function ARN
    LAMBDA_ARN=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Configuration.FunctionArn' --output text) || error_exit "Failed to get Lambda ARN"
    
    echo "LAMBDA_ARN=${LAMBDA_ARN}" >> "${SCRIPT_DIR}/../.env"
    
    log_success "Lambda function created: ${LAMBDA_ARN}"
}

# Create API Gateway with throttling configuration
create_api_gateway() {
    log "Creating API Gateway with throttling configuration..."
    
    # Create REST API
    API_ID=$(aws apigateway create-rest-api \
        --name "$API_NAME" \
        --description "Demo API for throttling and rate limiting" \
        --query 'id' --output text) || error_exit "Failed to create REST API"
    
    echo "API_ID=${API_ID}" >> "${SCRIPT_DIR}/../.env"
    
    # Get root resource ID
    ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "$API_ID" \
        --query 'items[0].id' --output text) || error_exit "Failed to get root resource ID"
    
    # Create resource for our endpoint
    RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "$API_ID" \
        --parent-id "$ROOT_RESOURCE_ID" \
        --path-part "data" \
        --query 'id' --output text) || error_exit "Failed to create API resource"
    
    echo "RESOURCE_ID=${RESOURCE_ID}" >> "${SCRIPT_DIR}/../.env"
    
    # Create GET method
    aws apigateway put-method \
        --rest-api-id "$API_ID" \
        --resource-id "$RESOURCE_ID" \
        --http-method GET \
        --authorization-type NONE \
        --api-key-required || error_exit "Failed to create API method"
    
    # Create Lambda integration
    aws apigateway put-integration \
        --rest-api-id "$API_ID" \
        --resource-id "$RESOURCE_ID" \
        --http-method GET \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" || error_exit "Failed to create Lambda integration"
    
    # Add Lambda permission for API Gateway
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id "api-gateway-invoke-${RANDOM_SUFFIX}" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:apigateway:${AWS_REGION}::/restapis/${API_ID}/*/*" || error_exit "Failed to add Lambda permission"
    
    log_success "API Gateway created with ID: ${API_ID}"
}

# Deploy API and configure stage-level throttling
deploy_api_stage() {
    log "Deploying API to stage with throttling configuration..."
    
    # Create deployment
    DEPLOYMENT_ID=$(aws apigateway create-deployment \
        --rest-api-id "$API_ID" \
        --stage-name "$STAGE_NAME" \
        --stage-description "Production stage with throttling" \
        --description "Initial deployment" \
        --query 'id' --output text) || error_exit "Failed to create API deployment"
    
    echo "DEPLOYMENT_ID=${DEPLOYMENT_ID}" >> "${SCRIPT_DIR}/../.env"
    
    # Configure stage-level throttling (default limits)
    aws apigateway update-stage \
        --rest-api-id "$API_ID" \
        --stage-name "$STAGE_NAME" \
        --patch-operations \
            op=replace,path=/throttle/rateLimit,value=1000 \
            op=replace,path=/throttle/burstLimit,value=2000 || error_exit "Failed to configure stage throttling"
    
    # Get API endpoint URL
    API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/${STAGE_NAME}/data"
    echo "API_URL=${API_URL}" >> "${SCRIPT_DIR}/../.env"
    
    log_success "API deployed to stage: ${STAGE_NAME}"
    log "API URL: ${API_URL}"
}

# Create usage plans with different tiers
create_usage_plans() {
    log "Creating usage plans with different throttling tiers..."
    
    # Create Premium Usage Plan
    PREMIUM_PLAN_ID=$(aws apigateway create-usage-plan \
        --name "Premium-Plan-${RANDOM_SUFFIX}" \
        --description "Premium tier with high limits" \
        --throttle rateLimit=2000,burstLimit=5000 \
        --quota limit=1000000,offset=0,period=MONTH \
        --query 'id' --output text) || error_exit "Failed to create Premium usage plan"
    
    # Create Standard Usage Plan
    STANDARD_PLAN_ID=$(aws apigateway create-usage-plan \
        --name "Standard-Plan-${RANDOM_SUFFIX}" \
        --description "Standard tier with moderate limits" \
        --throttle rateLimit=500,burstLimit=1000 \
        --quota limit=100000,offset=0,period=MONTH \
        --query 'id' --output text) || error_exit "Failed to create Standard usage plan"
    
    # Create Basic Usage Plan
    BASIC_PLAN_ID=$(aws apigateway create-usage-plan \
        --name "Basic-Plan-${RANDOM_SUFFIX}" \
        --description "Basic tier with low limits" \
        --throttle rateLimit=100,burstLimit=200 \
        --quota limit=10000,offset=0,period=MONTH \
        --query 'id' --output text) || error_exit "Failed to create Basic usage plan"
    
    # Save usage plan IDs
    cat >> "${SCRIPT_DIR}/../.env" << EOF
PREMIUM_PLAN_ID=${PREMIUM_PLAN_ID}
STANDARD_PLAN_ID=${STANDARD_PLAN_ID}
BASIC_PLAN_ID=${BASIC_PLAN_ID}
EOF
    
    log_success "Usage plans created:"
    log "Premium: ${PREMIUM_PLAN_ID}"
    log "Standard: ${STANDARD_PLAN_ID}"
    log "Basic: ${BASIC_PLAN_ID}"
}

# Associate usage plans with API stages
associate_usage_plans() {
    log "Associating usage plans with API stages..."
    
    # Associate Premium plan with API stage
    aws apigateway create-usage-plan-key \
        --usage-plan-id "$PREMIUM_PLAN_ID" \
        --key-type API_STAGE \
        --key-value "${API_ID}:${STAGE_NAME}" || error_exit "Failed to associate Premium plan"
    
    # Associate Standard plan with API stage
    aws apigateway create-usage-plan-key \
        --usage-plan-id "$STANDARD_PLAN_ID" \
        --key-type API_STAGE \
        --key-value "${API_ID}:${STAGE_NAME}" || error_exit "Failed to associate Standard plan"
    
    # Associate Basic plan with API stage
    aws apigateway create-usage-plan-key \
        --usage-plan-id "$BASIC_PLAN_ID" \
        --key-type API_STAGE \
        --key-value "${API_ID}:${STAGE_NAME}" || error_exit "Failed to associate Basic plan"
    
    log_success "Usage plans associated with API stages"
}

# Create API keys for different customer tiers
create_api_keys() {
    log "Creating API keys for different customer tiers..."
    
    # Create Premium API Key
    PREMIUM_KEY_ID=$(aws apigateway create-api-key \
        --name "premium-customer-${RANDOM_SUFFIX}" \
        --description "Premium tier customer API key" \
        --enabled \
        --query 'id' --output text) || error_exit "Failed to create Premium API key"
    
    # Create Standard API Key
    STANDARD_KEY_ID=$(aws apigateway create-api-key \
        --name "standard-customer-${RANDOM_SUFFIX}" \
        --description "Standard tier customer API key" \
        --enabled \
        --query 'id' --output text) || error_exit "Failed to create Standard API key"
    
    # Create Basic API Key
    BASIC_KEY_ID=$(aws apigateway create-api-key \
        --name "basic-customer-${RANDOM_SUFFIX}" \
        --description "Basic tier customer API key" \
        --enabled \
        --query 'id' --output text) || error_exit "Failed to create Basic API key"
    
    # Save API key IDs
    cat >> "${SCRIPT_DIR}/../.env" << EOF
PREMIUM_KEY_ID=${PREMIUM_KEY_ID}
STANDARD_KEY_ID=${STANDARD_KEY_ID}
BASIC_KEY_ID=${BASIC_KEY_ID}
EOF
    
    log_success "API keys created:"
    log "Premium: ${PREMIUM_KEY_ID}"
    log "Standard: ${STANDARD_KEY_ID}"
    log "Basic: ${BASIC_KEY_ID}"
}

# Associate API keys with usage plans
associate_api_keys() {
    log "Associating API keys with usage plans..."
    
    # Associate Premium key with Premium plan
    aws apigateway create-usage-plan-key \
        --usage-plan-id "$PREMIUM_PLAN_ID" \
        --key-type API_KEY \
        --key-value "$PREMIUM_KEY_ID" || error_exit "Failed to associate Premium key"
    
    # Associate Standard key with Standard plan
    aws apigateway create-usage-plan-key \
        --usage-plan-id "$STANDARD_PLAN_ID" \
        --key-type API_KEY \
        --key-value "$STANDARD_KEY_ID" || error_exit "Failed to associate Standard key"
    
    # Associate Basic key with Basic plan
    aws apigateway create-usage-plan-key \
        --usage-plan-id "$BASIC_PLAN_ID" \
        --key-type API_KEY \
        --key-value "$BASIC_KEY_ID" || error_exit "Failed to associate Basic key"
    
    log_success "API keys associated with usage plans"
}

# Get API key values and save them
retrieve_api_key_values() {
    log "Retrieving API key values..."
    
    # Get actual API key values
    PREMIUM_KEY_VALUE=$(aws apigateway get-api-key \
        --api-key "$PREMIUM_KEY_ID" \
        --include-value \
        --query 'value' --output text) || error_exit "Failed to get Premium key value"
    
    STANDARD_KEY_VALUE=$(aws apigateway get-api-key \
        --api-key "$STANDARD_KEY_ID" \
        --include-value \
        --query 'value' --output text) || error_exit "Failed to get Standard key value"
    
    BASIC_KEY_VALUE=$(aws apigateway get-api-key \
        --api-key "$BASIC_KEY_ID" \
        --include-value \
        --query 'value' --output text) || error_exit "Failed to get Basic key value"
    
    # Save API key values
    cat >> "${SCRIPT_DIR}/../.env" << EOF
PREMIUM_KEY_VALUE=${PREMIUM_KEY_VALUE}
STANDARD_KEY_VALUE=${STANDARD_KEY_VALUE}
BASIC_KEY_VALUE=${BASIC_KEY_VALUE}
EOF
    
    log_success "API key values retrieved and saved"
}

# Configure CloudWatch monitoring and alarms
configure_monitoring() {
    log "Configuring CloudWatch monitoring and alarms..."
    
    # Create CloudWatch alarm for high throttling
    aws cloudwatch put-metric-alarm \
        --alarm-name "API-High-Throttling-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when API throttling exceeds threshold" \
        --metric-name Count \
        --namespace AWS/ApiGateway \
        --statistic Sum \
        --period 300 \
        --threshold 100 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=ApiName,Value="$API_NAME" Name=Stage,Value="$STAGE_NAME" || log_warning "Failed to create throttling alarm"
    
    # Create alarm for high error rate
    aws cloudwatch put-metric-alarm \
        --alarm-name "API-High-4xx-Errors-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when 4xx errors exceed threshold" \
        --metric-name 4XXError \
        --namespace AWS/ApiGateway \
        --statistic Sum \
        --period 300 \
        --threshold 50 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=ApiName,Value="$API_NAME" Name=Stage,Value="$STAGE_NAME" || log_warning "Failed to create error rate alarm"
    
    # Save alarm names
    cat >> "${SCRIPT_DIR}/../.env" << EOF
THROTTLING_ALARM_NAME=API-High-Throttling-${RANDOM_SUFFIX}
ERROR_ALARM_NAME=API-High-4xx-Errors-${RANDOM_SUFFIX}
EOF
    
    log_success "CloudWatch alarms configured"
}

# Test the deployed API
test_deployment() {
    log "Testing the deployed API..."
    
    # Test without API key (should fail)
    log "Testing API without key (expecting 403)..."
    if curl -s -o /dev/null -w "%{http_code}" "$API_URL" | grep -q "403"; then
        log_success "API correctly requires authentication"
    else
        log_warning "API may not be properly configured for key requirement"
    fi
    
    # Test with Basic API key
    log "Testing with Basic tier API key..."
    if curl -s -H "X-API-Key: $BASIC_KEY_VALUE" "$API_URL" | grep -q "Hello from throttled API"; then
        log_success "Basic tier API key works correctly"
    else
        log_warning "Basic tier API key may not be working properly"
    fi
    
    log_success "API deployment test completed"
}

# Generate deployment summary
generate_summary() {
    log "Generating deployment summary..."
    
    cat > "${SCRIPT_DIR}/../deployment-summary.txt" << EOF
API Gateway Throttling Demo - Deployment Summary
===============================================

Deployment completed: $(date)

API Information:
- API Name: ${API_NAME}
- API ID: ${API_ID}
- API URL: ${API_URL}
- Stage: ${STAGE_NAME}

Lambda Function:
- Function Name: ${LAMBDA_FUNCTION_NAME}
- IAM Role: ${IAM_ROLE_NAME}

Usage Plans:
- Premium Plan ID: ${PREMIUM_PLAN_ID}
  - Rate Limit: 2000 RPS
  - Burst Limit: 5000
  - Monthly Quota: 1,000,000 requests
  
- Standard Plan ID: ${STANDARD_PLAN_ID}
  - Rate Limit: 500 RPS
  - Burst Limit: 1000
  - Monthly Quota: 100,000 requests
  
- Basic Plan ID: ${BASIC_PLAN_ID}
  - Rate Limit: 100 RPS
  - Burst Limit: 200
  - Monthly Quota: 10,000 requests

API Keys:
- Premium Key: ${PREMIUM_KEY_VALUE}
- Standard Key: ${STANDARD_KEY_VALUE}
- Basic Key: ${BASIC_KEY_VALUE}

Testing Commands:
# Test with Premium key
curl -H "X-API-Key: ${PREMIUM_KEY_VALUE}" ${API_URL}

# Test with Standard key
curl -H "X-API-Key: ${STANDARD_KEY_VALUE}" ${API_URL}

# Test with Basic key
curl -H "X-API-Key: ${BASIC_KEY_VALUE}" ${API_URL}

Monitoring:
- Throttling Alarm: ${THROTTLING_ALARM_NAME:-Not created}
- Error Alarm: ${ERROR_ALARM_NAME:-Not created}

Cleanup:
To remove all resources, run: ./destroy.sh

Configuration saved to: ${SCRIPT_DIR}/../.env
EOF
    
    log_success "Deployment summary saved to: ${SCRIPT_DIR}/../deployment-summary.txt"
}

# Main deployment function
main() {
    log "Starting API Gateway throttling deployment..."
    log "Deployment log: $LOG_FILE"
    
    # Initialize log file
    echo "API Gateway Throttling Deployment - $(date)" > "$LOG_FILE"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_lambda_backend
    create_api_gateway
    deploy_api_stage
    create_usage_plans
    associate_usage_plans
    create_api_keys
    associate_api_keys
    retrieve_api_key_values
    configure_monitoring
    test_deployment
    generate_summary
    
    # Cleanup temporary files
    rm -rf "$TEMP_DIR"
    
    log_success "Deployment completed successfully!"
    log ""
    log "📋 Deployment Summary:"
    log "   API URL: ${API_URL}"
    log "   Premium API Key: ${PREMIUM_KEY_VALUE}"
    log "   Standard API Key: ${STANDARD_KEY_VALUE}"
    log "   Basic API Key: ${BASIC_KEY_VALUE}"
    log ""
    log "📖 View complete summary: ${SCRIPT_DIR}/../deployment-summary.txt"
    log "🧪 Test your API with the keys provided above"
    log "🗑️  To cleanup: ./destroy.sh"
}

# Run main function
main "$@"