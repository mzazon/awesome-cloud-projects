#!/bin/bash

# Deploy script for Lambda Function Deployment Patterns with Blue-Green and Canary Releases
# This script implements the complete deployment pipeline with proper error handling

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "Prerequisites check passed ✅"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "No region configured, using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    export FUNCTION_NAME="deploy-patterns-demo-${RANDOM_SUFFIX}"
    export API_NAME="deployment-api-${RANDOM_SUFFIX}"
    export ROLE_NAME="lambda-deploy-role-${RANDOM_SUFFIX}"
    
    # Store values for cleanup
    echo "FUNCTION_NAME=$FUNCTION_NAME" > .env
    echo "API_NAME=$API_NAME" >> .env
    echo "ROLE_NAME=$ROLE_NAME" >> .env
    echo "AWS_REGION=$AWS_REGION" >> .env
    echo "AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID" >> .env
    
    info "Function Name: $FUNCTION_NAME"
    info "API Name: $API_NAME"
    info "Role Name: $ROLE_NAME"
    info "AWS Region: $AWS_REGION"
    
    log "Environment setup complete ✅"
}

# Create IAM role for Lambda function
create_iam_role() {
    log "Creating IAM role for Lambda function..."
    
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
    
    # Create the IAM role
    aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document file://trust-policy.json \
        --description "Lambda execution role for deployment patterns demo"
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name $ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    export ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
    echo "ROLE_ARN=$ROLE_ARN" >> .env
    
    # Wait for role to be ready
    sleep 10
    
    log "IAM role created successfully ✅"
}

# Create Lambda function version 1
create_lambda_function() {
    log "Creating Lambda function (Version 1)..."
    
    # Create function code for version 1
    cat > lambda_function_v1.py << 'EOF'
import json
import os

def lambda_handler(event, context):
    version = "1.0.0"
    message = "Hello from Lambda Version 1 - Blue Environment"
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'version': version,
            'message': message,
            'timestamp': context.aws_request_id,
            'environment': 'blue'
        })
    }
EOF
    
    # Package the function
    zip function-v1.zip lambda_function_v1.py
    
    # Create the Lambda function
    aws lambda create-function \
        --function-name $FUNCTION_NAME \
        --runtime python3.9 \
        --role $ROLE_ARN \
        --handler lambda_function_v1.lambda_handler \
        --zip-file fileb://function-v1.zip \
        --description "Demo function for deployment patterns" \
        --timeout 30
    
    # Wait for function to be ready
    aws lambda wait function-active --function-name $FUNCTION_NAME
    
    log "Lambda function created successfully ✅"
}

# Publish version 1 and create production alias
create_version_and_alias() {
    log "Publishing Version 1 and creating production alias..."
    
    # Publish version 1
    VERSION_1=$(aws lambda publish-version \
        --function-name $FUNCTION_NAME \
        --description "Initial production version" \
        --query Version --output text)
    
    # Create production alias pointing to version 1
    aws lambda create-alias \
        --function-name $FUNCTION_NAME \
        --name production \
        --function-version $VERSION_1 \
        --description "Production alias for blue-green deployments"
    
    export PRODUCTION_ALIAS_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${FUNCTION_NAME}:production"
    echo "PRODUCTION_ALIAS_ARN=$PRODUCTION_ALIAS_ARN" >> .env
    echo "VERSION_1=$VERSION_1" >> .env
    
    log "Version 1 published and production alias created ✅"
}

# Create API Gateway
create_api_gateway() {
    log "Creating API Gateway..."
    
    # Create REST API
    API_ID=$(aws apigateway create-rest-api \
        --name $API_NAME \
        --description "API for Lambda deployment patterns demo" \
        --query id --output text)
    
    # Get root resource ID
    ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id $API_ID \
        --query 'items[?path==`/`].id' --output text)
    
    # Create resource for deployment demo
    RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id $API_ID \
        --parent-id $ROOT_RESOURCE_ID \
        --path-part demo \
        --query id --output text)
    
    # Create GET method
    aws apigateway put-method \
        --rest-api-id $API_ID \
        --resource-id $RESOURCE_ID \
        --http-method GET \
        --authorization-type NONE
    
    echo "API_ID=$API_ID" >> .env
    echo "ROOT_RESOURCE_ID=$ROOT_RESOURCE_ID" >> .env
    echo "RESOURCE_ID=$RESOURCE_ID" >> .env
    
    log "API Gateway created successfully ✅"
}

# Configure Lambda integration
configure_lambda_integration() {
    log "Configuring Lambda integration with API Gateway..."
    
    # Set up Lambda integration using the production alias
    aws apigateway put-integration \
        --rest-api-id $API_ID \
        --resource-id $RESOURCE_ID \
        --http-method GET \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${PRODUCTION_ALIAS_ARN}/invocations"
    
    # Configure method response
    aws apigateway put-method-response \
        --rest-api-id $API_ID \
        --resource-id $RESOURCE_ID \
        --http-method GET \
        --status-code 200
    
    # Grant API Gateway permission to invoke Lambda function
    aws lambda add-permission \
        --function-name $FUNCTION_NAME \
        --qualifier production \
        --statement-id api-gateway-invoke-permission \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*"
    
    log "Lambda integration configured successfully ✅"
}

# Deploy API Gateway
deploy_api() {
    log "Deploying API Gateway..."
    
    # Deploy API to prod stage
    aws apigateway create-deployment \
        --rest-api-id $API_ID \
        --stage-name prod \
        --description "Initial deployment with version 1"
    
    # Get API endpoint URL
    export API_URL="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod/demo"
    echo "API_URL=$API_URL" >> .env
    
    info "API URL: $API_URL"
    
    # Wait for deployment to be ready
    sleep 5
    
    # Test the deployment
    log "Testing Version 1 deployment..."
    response=$(curl -s $API_URL)
    if echo "$response" | jq -e '.body' > /dev/null 2>&1; then
        log "API deployment test passed ✅"
        info "Response: $(echo "$response" | jq -r '.body' | jq -c .)"
    else
        warn "API deployment test failed, but continuing..."
    fi
}

# Create version 2 for canary deployment
create_version_2() {
    log "Creating Version 2 for canary deployment..."
    
    # Create function code for version 2
    cat > lambda_function_v2.py << 'EOF'
import json
import os

def lambda_handler(event, context):
    version = "2.0.0"
    message = "Hello from Lambda Version 2 - Green Environment with NEW FEATURES!"
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'version': version,
            'message': message,
            'timestamp': context.aws_request_id,
            'environment': 'green',
            'features': ['enhanced_logging', 'improved_performance']
        })
    }
EOF
    
    # Package version 2
    zip function-v2.zip lambda_function_v2.py
    
    # Update function code
    aws lambda update-function-code \
        --function-name $FUNCTION_NAME \
        --zip-file fileb://function-v2.zip
    
    # Wait for update to complete
    aws lambda wait function-updated --function-name $FUNCTION_NAME
    
    # Publish version 2
    VERSION_2=$(aws lambda publish-version \
        --function-name $FUNCTION_NAME \
        --description "Version 2 with new features" \
        --query Version --output text)
    
    echo "VERSION_2=$VERSION_2" >> .env
    
    log "Version 2 created and published ✅"
}

# Implement canary deployment
implement_canary() {
    log "Implementing canary deployment (10% traffic to Version 2)..."
    
    # Update production alias with weighted routing
    # 90% traffic to version 1, 10% to version 2 (canary)
    aws lambda update-alias \
        --function-name $FUNCTION_NAME \
        --name production \
        --function-version $VERSION_2 \
        --routing-config "AdditionalVersionWeights={\"$VERSION_1\"=0.9}"
    
    log "Canary deployment configured: 90% v1, 10% v2 ✅"
    
    # Test canary deployment
    log "Testing canary deployment..."
    info "Testing canary deployment (should see ~10% version 2 responses):"
    for i in {1..10}; do
        response=$(curl -s $API_URL 2>/dev/null || echo '{"body": "{\"version\": \"error\", \"environment\": \"error\"}"}')
        version=$(echo "$response" | jq -r '.body' | jq -r '.version + " - " + .environment' 2>/dev/null || echo "error")
        info "Request $i: $version"
        sleep 1
    done
}

# Setup CloudWatch monitoring
setup_monitoring() {
    log "Setting up CloudWatch monitoring..."
    
    # Create CloudWatch alarm for error rate monitoring
    aws cloudwatch put-metric-alarm \
        --alarm-name "${FUNCTION_NAME}-error-rate" \
        --alarm-description "Monitor Lambda function error rate" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=FunctionName,Value=$FUNCTION_NAME
    
    echo "ALARM_NAME=${FUNCTION_NAME}-error-rate" >> .env
    
    log "CloudWatch monitoring configured ✅"
}

# Complete blue-green deployment
complete_blue_green() {
    log "Completing blue-green deployment (100% traffic to Version 2)..."
    
    # Promote version 2 to receive 100% of traffic
    aws lambda update-alias \
        --function-name $FUNCTION_NAME \
        --name production \
        --function-version $VERSION_2 \
        --routing-config '{}'
    
    log "Blue-green deployment completed: 100% traffic to v2 ✅"
    
    # Verify full deployment
    log "Testing full deployment to version 2..."
    for i in {1..5}; do
        response=$(curl -s $API_URL 2>/dev/null || echo '{"body": "{\"version\": \"error\", \"environment\": \"error\"}"}')
        version=$(echo "$response" | jq -r '.body' | jq -r '.version + " - " + .environment' 2>/dev/null || echo "error")
        info "Request $i: $version"
        sleep 1
    done
}

# Test rollback capability
test_rollback() {
    log "Testing rollback capability..."
    
    # Demonstrate instant rollback to version 1
    info "Simulating rollback to version 1..."
    aws lambda update-alias \
        --function-name $FUNCTION_NAME \
        --name production \
        --function-version $VERSION_1 \
        --routing-config '{}'
    
    log "Rollback completed ✅"
    
    # Test rollback
    info "Testing rollback:"
    response=$(curl -s $API_URL 2>/dev/null || echo '{"body": "{\"version\": \"error\", \"environment\": \"error\"}"}')
    version=$(echo "$response" | jq -r '.body' | jq -r '.version + " - " + .environment' 2>/dev/null || echo "error")
    info "Rollback test result: $version"
    
    # Restore to version 2 for final state
    aws lambda update-alias \
        --function-name $FUNCTION_NAME \
        --name production \
        --function-version $VERSION_2 \
        --routing-config '{}'
    
    log "Restored to version 2 ✅"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files but keep .env for cleanup script
    rm -f trust-policy.json lambda_function_v*.py function-v*.zip
    
    log "Temporary files cleaned up ✅"
}

# Main deployment function
main() {
    log "Starting Lambda Function Deployment Patterns Demo..."
    
    # Change to script directory
    cd "$(dirname "$0")"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_iam_role
    create_lambda_function
    create_version_and_alias
    create_api_gateway
    configure_lambda_integration
    deploy_api
    create_version_2
    implement_canary
    setup_monitoring
    complete_blue_green
    test_rollback
    cleanup_temp_files
    
    log "🎉 Deployment completed successfully!"
    info "API URL: $API_URL"
    info "You can now test the deployment patterns with:"
    info "curl -s $API_URL | jq ."
    info ""
    info "Environment details saved in .env file"
    info "Run ./destroy.sh to clean up resources"
}

# Handle script interruption
cleanup_on_exit() {
    error "Script interrupted. You may need to run ./destroy.sh to clean up resources."
    exit 1
}

trap cleanup_on_exit INT TERM

# Run main function
main "$@"