#!/bin/bash

# AWS Webhook Processing Systems Deployment Script
# This script deploys API Gateway, SQS, Lambda, and DynamoDB resources for webhook processing

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

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: $description"
        log "Command: $cmd"
        return 0
    else
        log "$description"
        eval "$cmd"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it for JSON parsing."
        exit 1
    fi
    
    # Check AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        error "Unable to determine AWS Account ID"
        exit 1
    fi
    
    # Check AWS region
    AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region is not configured"
        exit 1
    fi
    
    success "Prerequisites check passed"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "AWS Region: $AWS_REGION"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Export all required environment variables
    export AWS_REGION
    export AWS_ACCOUNT_ID
    export WEBHOOK_QUEUE_NAME="webhook-processing-queue-${RANDOM_SUFFIX}"
    export WEBHOOK_DLQ_NAME="webhook-dlq-${RANDOM_SUFFIX}"
    export WEBHOOK_FUNCTION_NAME="webhook-processor-${RANDOM_SUFFIX}"
    export WEBHOOK_API_NAME="webhook-api-${RANDOM_SUFFIX}"
    export WEBHOOK_TABLE_NAME="webhook-history-${RANDOM_SUFFIX}"
    export RANDOM_SUFFIX
    
    # Create temporary directory for files
    export TEMP_DIR=$(mktemp -d)
    
    success "Environment variables configured"
    log "Queue Name: ${WEBHOOK_QUEUE_NAME}"
    log "Function Name: ${WEBHOOK_FUNCTION_NAME}"
    log "API Name: ${WEBHOOK_API_NAME}"
    log "Table Name: ${WEBHOOK_TABLE_NAME}"
    log "Temporary Directory: ${TEMP_DIR}"
}

# Function to create SQS dead letter queue
create_dead_letter_queue() {
    log "Creating SQS dead letter queue..."
    
    execute_command "aws sqs create-queue \
        --queue-name ${WEBHOOK_DLQ_NAME} \
        --attributes '{
            \"MessageRetentionPeriod\": \"1209600\",
            \"VisibilityTimeout\": \"60\"
        }'" "Creating dead letter queue"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Store DLQ URL and ARN
        export DLQ_URL=$(aws sqs get-queue-url \
            --queue-name ${WEBHOOK_DLQ_NAME} \
            --query QueueUrl --output text)
        
        export DLQ_ARN=$(aws sqs get-queue-attributes \
            --queue-url ${DLQ_URL} \
            --attribute-names QueueArn \
            --query 'Attributes.QueueArn' --output text)
        
        success "Dead letter queue created: ${DLQ_ARN}"
    fi
}

# Function to create primary SQS queue
create_primary_queue() {
    log "Creating primary SQS queue..."
    
    execute_command "aws sqs create-queue \
        --queue-name ${WEBHOOK_QUEUE_NAME} \
        --attributes '{
            \"MessageRetentionPeriod\": \"1209600\",
            \"VisibilityTimeout\": \"300\",
            \"RedrivePolicy\": \"{\\\"deadLetterTargetArn\\\":\\\"${DLQ_ARN}\\\",\\\"maxReceiveCount\\\":3}\"
        }'" "Creating primary queue with DLQ redrive policy"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Store primary queue URL and ARN
        export QUEUE_URL=$(aws sqs get-queue-url \
            --queue-name ${WEBHOOK_QUEUE_NAME} \
            --query QueueUrl --output text)
        
        export QUEUE_ARN=$(aws sqs get-queue-attributes \
            --queue-url ${QUEUE_URL} \
            --attribute-names QueueArn \
            --query 'Attributes.QueueArn' --output text)
        
        success "Primary webhook queue created: ${QUEUE_ARN}"
    fi
}

# Function to create DynamoDB table
create_dynamodb_table() {
    log "Creating DynamoDB table..."
    
    execute_command "aws dynamodb create-table \
        --table-name ${WEBHOOK_TABLE_NAME} \
        --attribute-definitions \
            AttributeName=webhook_id,AttributeType=S \
            AttributeName=timestamp,AttributeType=S \
        --key-schema \
            AttributeName=webhook_id,KeyType=HASH \
            AttributeName=timestamp,KeyType=RANGE \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --tags Key=Purpose,Value=WebhookProcessing" "Creating DynamoDB table"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for table to be active
        log "Waiting for DynamoDB table to become active..."
        aws dynamodb wait table-exists --table-name ${WEBHOOK_TABLE_NAME}
        success "DynamoDB table created: ${WEBHOOK_TABLE_NAME}"
    fi
}

# Function to create IAM role for API Gateway
create_api_gateway_role() {
    log "Creating IAM role for API Gateway..."
    
    # Create trust policy file
    cat > ${TEMP_DIR}/apigw-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "apigateway.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    execute_command "aws iam create-role \
        --role-name webhook-apigw-sqs-role-${RANDOM_SUFFIX} \
        --assume-role-policy-document file://${TEMP_DIR}/apigw-trust-policy.json" \
        "Creating API Gateway IAM role"
    
    # Create SQS access policy
    cat > ${TEMP_DIR}/apigw-sqs-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sqs:SendMessage",
                "sqs:GetQueueAttributes"
            ],
            "Resource": "${QUEUE_ARN}"
        }
    ]
}
EOF
    
    execute_command "aws iam put-role-policy \
        --role-name webhook-apigw-sqs-role-${RANDOM_SUFFIX} \
        --policy-name SQSAccessPolicy \
        --policy-document file://${TEMP_DIR}/apigw-sqs-policy.json" \
        "Attaching SQS access policy to API Gateway role"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export APIGW_ROLE_ARN=$(aws iam get-role \
            --role-name webhook-apigw-sqs-role-${RANDOM_SUFFIX} \
            --query Role.Arn --output text)
        
        success "API Gateway IAM role created: ${APIGW_ROLE_ARN}"
    fi
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function..."
    
    # Create Lambda function code
    cat > ${TEMP_DIR}/webhook-processor.py << 'EOF'
import json
import boto3
import uuid
import os
from datetime import datetime
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['WEBHOOK_TABLE_NAME'])

def lambda_handler(event, context):
    try:
        # Process each SQS record
        for record in event['Records']:
            # Parse the webhook payload
            webhook_body = json.loads(record['body'])
            
            # Generate unique webhook ID
            webhook_id = str(uuid.uuid4())
            timestamp = datetime.utcnow().isoformat()
            
            # Extract webhook metadata
            source_ip = webhook_body.get('source_ip', 'unknown')
            webhook_type = webhook_body.get('type', 'unknown')
            
            # Process the webhook (customize based on your needs)
            processed_data = process_webhook(webhook_body)
            
            # Store in DynamoDB
            table.put_item(
                Item={
                    'webhook_id': webhook_id,
                    'timestamp': timestamp,
                    'source_ip': source_ip,
                    'webhook_type': webhook_type,
                    'raw_payload': json.dumps(webhook_body),
                    'processed_data': json.dumps(processed_data),
                    'status': 'processed'
                }
            )
            
            logger.info(f"Processed webhook {webhook_id} of type {webhook_type}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Webhooks processed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing webhook: {str(e)}")
        raise

def process_webhook(payload):
    """
    Customize this function based on your webhook processing needs
    """
    # Example processing logic
    processed = {
        'processed_at': datetime.utcnow().isoformat(),
        'payload_size': len(json.dumps(payload)),
        'contains_sensitive_data': check_sensitive_data(payload)
    }
    
    # Add your specific processing logic here
    return processed

def check_sensitive_data(payload):
    """
    Example function to check for sensitive data
    """
    sensitive_keys = ['credit_card', 'ssn', 'password', 'secret']
    payload_str = json.dumps(payload).lower()
    
    return any(key in payload_str for key in sensitive_keys)
EOF
    
    # Create deployment package
    execute_command "cd ${TEMP_DIR} && zip webhook-processor.zip webhook-processor.py" \
        "Creating Lambda deployment package"
    
    # Create Lambda execution role trust policy
    cat > ${TEMP_DIR}/lambda-trust-policy.json << EOF
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
    
    execute_command "aws iam create-role \
        --role-name webhook-lambda-role-${RANDOM_SUFFIX} \
        --assume-role-policy-document file://${TEMP_DIR}/lambda-trust-policy.json" \
        "Creating Lambda execution role"
    
    # Attach basic Lambda execution policy
    execute_command "aws iam attach-role-policy \
        --role-name webhook-lambda-role-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "Attaching basic Lambda execution policy"
    
    # Create DynamoDB access policy
    cat > ${TEMP_DIR}/lambda-dynamodb-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${WEBHOOK_TABLE_NAME}"
        }
    ]
}
EOF
    
    execute_command "aws iam put-role-policy \
        --role-name webhook-lambda-role-${RANDOM_SUFFIX} \
        --policy-name DynamoDBAccessPolicy \
        --policy-document file://${TEMP_DIR}/lambda-dynamodb-policy.json" \
        "Attaching DynamoDB access policy to Lambda role"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export LAMBDA_ROLE_ARN=$(aws iam get-role \
            --role-name webhook-lambda-role-${RANDOM_SUFFIX} \
            --query Role.Arn --output text)
        
        # Wait for role propagation
        log "Waiting for IAM role propagation..."
        sleep 10
        
        # Create Lambda function
        execute_command "aws lambda create-function \
            --function-name ${WEBHOOK_FUNCTION_NAME} \
            --runtime python3.9 \
            --role ${LAMBDA_ROLE_ARN} \
            --handler webhook-processor.lambda_handler \
            --zip-file fileb://${TEMP_DIR}/webhook-processor.zip \
            --environment Variables=\"{WEBHOOK_TABLE_NAME=${WEBHOOK_TABLE_NAME}}\" \
            --timeout 30 \
            --memory-size 256" "Creating Lambda function"
        
        success "Lambda function created: ${WEBHOOK_FUNCTION_NAME}"
    fi
}

# Function to create SQS event source mapping
create_event_source_mapping() {
    log "Creating SQS event source mapping..."
    
    execute_command "aws lambda create-event-source-mapping \
        --function-name ${WEBHOOK_FUNCTION_NAME} \
        --event-source-arn ${QUEUE_ARN} \
        --batch-size 10 \
        --maximum-batching-window-in-seconds 5" \
        "Creating SQS to Lambda event source mapping"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        success "SQS event source mapping created"
    fi
}

# Function to create API Gateway
create_api_gateway() {
    log "Creating API Gateway..."
    
    execute_command "aws apigateway create-rest-api \
        --name ${WEBHOOK_API_NAME} \
        --description 'Webhook processing API' \
        --endpoint-configuration types=REGIONAL" \
        "Creating REST API"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export API_ID=$(aws apigateway create-rest-api \
            --name ${WEBHOOK_API_NAME} \
            --description "Webhook processing API" \
            --endpoint-configuration types=REGIONAL \
            --query id --output text)
        
        # Get root resource ID
        export ROOT_RESOURCE_ID=$(aws apigateway get-resources \
            --rest-api-id ${API_ID} \
            --query 'items[0].id' --output text)
        
        # Create /webhooks resource
        export WEBHOOK_RESOURCE_ID=$(aws apigateway create-resource \
            --rest-api-id ${API_ID} \
            --parent-id ${ROOT_RESOURCE_ID} \
            --path-part webhooks \
            --query id --output text)
        
        success "API Gateway REST API created: ${API_ID}"
        success "Webhook resource created: ${WEBHOOK_RESOURCE_ID}"
    fi
}

# Function to configure API Gateway method
configure_api_method() {
    log "Configuring API Gateway POST method..."
    
    # Create POST method
    execute_command "aws apigateway put-method \
        --rest-api-id ${API_ID} \
        --resource-id ${WEBHOOK_RESOURCE_ID} \
        --http-method POST \
        --authorization-type NONE" \
        "Creating POST method"
    
    # Set up SQS integration
    execute_command "aws apigateway put-integration \
        --rest-api-id ${API_ID} \
        --resource-id ${WEBHOOK_RESOURCE_ID} \
        --http-method POST \
        --type AWS \
        --integration-http-method POST \
        --uri 'arn:aws:apigateway:${AWS_REGION}:sqs:path/${AWS_ACCOUNT_ID}/${WEBHOOK_QUEUE_NAME}' \
        --credentials ${APIGW_ROLE_ARN} \
        --request-parameters 'integration.request.header.Content-Type=application/x-www-form-urlencoded' \
        --request-templates '{\"application/json\": \"Action=SendMessage&MessageBody=\$util.urlEncode(\\\"{\\\\\\\"source_ip\\\\\\\":\\\\\\\"\$context.identity.sourceIp\\\\\\\",\\\\\\\"timestamp\\\\\\\":\\\\\\\"\$context.requestTime\\\\\\\",\\\\\\\"body\\\\\\\":\$input.json('\\$')}\\\")\"}')" \
        "Setting up SQS integration"
    
    # Create method response
    execute_command "aws apigateway put-method-response \
        --rest-api-id ${API_ID} \
        --resource-id ${WEBHOOK_RESOURCE_ID} \
        --http-method POST \
        --status-code 200 \
        --response-models 'application/json=Empty'" \
        "Creating method response"
    
    # Create integration response
    execute_command "aws apigateway put-integration-response \
        --rest-api-id ${API_ID} \
        --resource-id ${WEBHOOK_RESOURCE_ID} \
        --http-method POST \
        --status-code 200 \
        --response-templates '{\"application/json\": \"{\\\"message\\\": \\\"Webhook received and queued for processing\\\", \\\"requestId\\\": \\\"\$context.requestId\\\"}\"}'" \
        "Creating integration response"
    
    success "POST method configured with SQS integration"
}

# Function to deploy API Gateway
deploy_api_gateway() {
    log "Deploying API Gateway..."
    
    execute_command "aws apigateway create-deployment \
        --rest-api-id ${API_ID} \
        --stage-name prod \
        --description 'Production deployment for webhook processing'" \
        "Creating API deployment"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod/webhooks"
        
        success "API deployed successfully"
        success "Webhook endpoint: ${API_ENDPOINT}"
    fi
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms..."
    
    # Create alarm for dead letter queue messages
    execute_command "aws cloudwatch put-metric-alarm \
        --alarm-name 'webhook-dlq-messages-${RANDOM_SUFFIX}' \
        --alarm-description 'Alert when messages appear in webhook DLQ' \
        --metric-name ApproximateNumberOfVisibleMessages \
        --namespace AWS/SQS \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --dimensions Name=QueueName,Value=${WEBHOOK_DLQ_NAME}" \
        "Creating dead letter queue alarm"
    
    # Create alarm for Lambda errors
    execute_command "aws cloudwatch put-metric-alarm \
        --alarm-name 'webhook-lambda-errors-${RANDOM_SUFFIX}' \
        --alarm-description 'Alert on Lambda function errors' \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --dimensions Name=FunctionName,Value=${WEBHOOK_FUNCTION_NAME}" \
        "Creating Lambda errors alarm"
    
    success "CloudWatch alarms configured"
}

# Function to save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    # Create deployment info file
    cat > webhook-deployment-info.json << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "random_suffix": "${RANDOM_SUFFIX}",
    "resources": {
        "sqs_queue_name": "${WEBHOOK_QUEUE_NAME}",
        "sqs_dlq_name": "${WEBHOOK_DLQ_NAME}",
        "lambda_function_name": "${WEBHOOK_FUNCTION_NAME}",
        "api_gateway_name": "${WEBHOOK_API_NAME}",
        "dynamodb_table_name": "${WEBHOOK_TABLE_NAME}",
        "api_gateway_id": "${API_ID:-}",
        "webhook_endpoint": "${API_ENDPOINT:-}",
        "queue_url": "${QUEUE_URL:-}",
        "dlq_url": "${DLQ_URL:-}"
    },
    "iam_roles": {
        "api_gateway_role": "webhook-apigw-sqs-role-${RANDOM_SUFFIX}",
        "lambda_role": "webhook-lambda-role-${RANDOM_SUFFIX}"
    },
    "cloudwatch_alarms": {
        "dlq_alarm": "webhook-dlq-messages-${RANDOM_SUFFIX}",
        "lambda_errors_alarm": "webhook-lambda-errors-${RANDOM_SUFFIX}"
    }
}
EOF
    
    success "Deployment information saved to webhook-deployment-info.json"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
        log "Temporary files cleaned up"
    fi
}

# Main deployment function
main() {
    log "Starting webhook processing system deployment..."
    
    # Set up cleanup trap
    trap cleanup_temp_files EXIT
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_dead_letter_queue
    create_primary_queue
    create_dynamodb_table
    create_api_gateway_role
    create_lambda_function
    create_event_source_mapping
    create_api_gateway
    configure_api_method
    deploy_api_gateway
    create_cloudwatch_alarms
    
    if [[ "$DRY_RUN" == "false" ]]; then
        save_deployment_info
    fi
    
    success "Webhook processing system deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        log "Deployment Summary:"
        log "==================="
        log "Webhook Endpoint: ${API_ENDPOINT}"
        log "SQS Queue: ${WEBHOOK_QUEUE_NAME}"
        log "Lambda Function: ${WEBHOOK_FUNCTION_NAME}"
        log "DynamoDB Table: ${WEBHOOK_TABLE_NAME}"
        echo ""
        log "Test your webhook endpoint with:"
        log "curl -X POST ${API_ENDPOINT} -H 'Content-Type: application/json' -d '{\"type\": \"test\", \"message\": \"Hello World\"}'"
        echo ""
        log "Monitor your system:"
        log "- CloudWatch Logs: /aws/lambda/${WEBHOOK_FUNCTION_NAME}"
        log "- CloudWatch Alarms: webhook-dlq-messages-${RANDOM_SUFFIX}, webhook-lambda-errors-${RANDOM_SUFFIX}"
        log "- DynamoDB Table: ${WEBHOOK_TABLE_NAME}"
    fi
}

# Run main function
main "$@"