#!/bin/bash

# Deploy script for Asynchronous API Patterns with API Gateway and SQS
# This script creates all infrastructure components for the async API solution

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
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

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command '$1' not found. Please install it and try again."
        exit 1
    fi
}

# Function to check AWS CLI configuration
check_aws_config() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI not configured or credentials invalid. Please run 'aws configure' first."
        exit 1
    fi
}

# Function to wait for resource availability
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local max_attempts="${3:-30}"
    local attempt=1
    
    log_info "Waiting for $resource_type '$resource_name' to be available..."
    
    while [ $attempt -le $max_attempts ]; do
        case $resource_type in
            "table")
                if aws dynamodb describe-table --table-name "$resource_name" --query 'Table.TableStatus' --output text 2>/dev/null | grep -q "ACTIVE"; then
                    log_success "$resource_type '$resource_name' is now active"
                    return 0
                fi
                ;;
            "role")
                if aws iam get-role --role-name "$resource_name" &>/dev/null; then
                    # Wait additional time for role propagation
                    sleep 10
                    log_success "$resource_type '$resource_name' is now available"
                    return 0
                fi
                ;;
        esac
        
        echo -n "."
        sleep 10
        ((attempt++))
    done
    
    log_error "Timeout waiting for $resource_type '$resource_name'"
    return 1
}

# Function to create temporary files
create_temp_files() {
    export TEMP_DIR=$(mktemp -d)
    log_info "Created temporary directory: $TEMP_DIR"
    
    # Cleanup function
    cleanup_temp() {
        if [ -d "$TEMP_DIR" ]; then
            rm -rf "$TEMP_DIR"
            log_info "Cleaned up temporary directory"
        fi
    }
    
    # Register cleanup function
    trap cleanup_temp EXIT
}

# Function to generate random suffix
generate_random_suffix() {
    if command -v aws &> /dev/null; then
        aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)"
    else
        echo "$(date +%s | tail -c 6)"
    fi
}

# Main deployment function
main() {
    log_info "Starting deployment of Asynchronous API Patterns with API Gateway and SQS"
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    check_command "aws"
    check_command "curl"
    check_command "python3"
    check_aws_config
    
    # Create temporary directory
    create_temp_files
    
    # Set environment variables
    log_info "Setting up environment variables..."
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "AWS region not configured, using default: $AWS_REGION"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(generate_random_suffix)
    export PROJECT_NAME="async-api-${RANDOM_SUFFIX}"
    export MAIN_QUEUE_NAME="${PROJECT_NAME}-main-queue"
    export DLQ_NAME="${PROJECT_NAME}-dlq"
    export JOBS_TABLE_NAME="${PROJECT_NAME}-jobs"
    export RESULTS_BUCKET_NAME="${PROJECT_NAME}-results"
    export API_NAME="${PROJECT_NAME}-api"
    
    log_info "Project Name: $PROJECT_NAME"
    log_info "AWS Region: $AWS_REGION"
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    
    # Create S3 bucket for storing results
    log_info "Creating S3 bucket for results..."
    if aws s3 mb "s3://${RESULTS_BUCKET_NAME}" --region "${AWS_REGION}"; then
        log_success "Created S3 bucket: ${RESULTS_BUCKET_NAME}"
    else
        log_error "Failed to create S3 bucket"
        exit 1
    fi
    
    # Step 1: Create Dead Letter Queue
    log_info "Creating Dead Letter Queue..."
    aws sqs create-queue \
        --queue-name "${DLQ_NAME}" \
        --attributes '{
            "MessageRetentionPeriod": "1209600",
            "VisibilityTimeoutSeconds": "300"
        }' > /dev/null
    
    export DLQ_URL=$(aws sqs get-queue-url --queue-name "${DLQ_NAME}" --query QueueUrl --output text)
    export DLQ_ARN=$(aws sqs get-queue-attributes --queue-url "${DLQ_URL}" --attribute-names QueueArn --query Attributes.QueueArn --output text)
    log_success "Created Dead Letter Queue: ${DLQ_NAME}"
    
    # Step 2: Create Main Processing Queue
    log_info "Creating Main Processing Queue..."
    aws sqs create-queue \
        --queue-name "${MAIN_QUEUE_NAME}" \
        --attributes '{
            "MessageRetentionPeriod": "1209600",
            "VisibilityTimeoutSeconds": "300",
            "RedrivePolicy": "{\"deadLetterTargetArn\":\"'${DLQ_ARN}'\",\"maxReceiveCount\":3}"
        }' > /dev/null
    
    export MAIN_QUEUE_URL=$(aws sqs get-queue-url --queue-name "${MAIN_QUEUE_NAME}" --query QueueUrl --output text)
    export MAIN_QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url "${MAIN_QUEUE_URL}" --attribute-names QueueArn --query Attributes.QueueArn --output text)
    log_success "Created Main Queue: ${MAIN_QUEUE_NAME}"
    
    # Step 3: Create DynamoDB Table
    log_info "Creating DynamoDB table for job tracking..."
    aws dynamodb create-table \
        --table-name "${JOBS_TABLE_NAME}" \
        --attribute-definitions AttributeName=jobId,AttributeType=S \
        --key-schema AttributeName=jobId,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --stream-specification StreamEnabled=false > /dev/null
    
    wait_for_resource "table" "${JOBS_TABLE_NAME}"
    log_success "Created DynamoDB table: ${JOBS_TABLE_NAME}"
    
    # Step 4: Create IAM Role for API Gateway
    log_info "Creating IAM role for API Gateway..."
    
    cat > "${TEMP_DIR}/api-gateway-trust-policy.json" << EOF
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
    
    aws iam create-role \
        --role-name "${PROJECT_NAME}-api-gateway-role" \
        --assume-role-policy-document "file://${TEMP_DIR}/api-gateway-trust-policy.json" > /dev/null
    
    cat > "${TEMP_DIR}/sqs-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sqs:SendMessage",
                "sqs:GetQueueAttributes"
            ],
            "Resource": "${MAIN_QUEUE_ARN}"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "${PROJECT_NAME}-api-gateway-role" \
        --policy-name SQSAccessPolicy \
        --policy-document "file://${TEMP_DIR}/sqs-policy.json"
    
    export API_GATEWAY_ROLE_ARN=$(aws iam get-role --role-name "${PROJECT_NAME}-api-gateway-role" --query Role.Arn --output text)
    wait_for_resource "role" "${PROJECT_NAME}-api-gateway-role"
    log_success "Created API Gateway IAM role"
    
    # Step 5: Create Lambda Execution Role
    log_info "Creating IAM role for Lambda functions..."
    
    cat > "${TEMP_DIR}/lambda-trust-policy.json" << EOF
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
    
    aws iam create-role \
        --role-name "${PROJECT_NAME}-lambda-role" \
        --assume-role-policy-document "file://${TEMP_DIR}/lambda-trust-policy.json" > /dev/null
    
    aws iam attach-role-policy \
        --role-name "${PROJECT_NAME}-lambda-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    cat > "${TEMP_DIR}/lambda-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${JOBS_TABLE_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject"
            ],
            "Resource": "arn:aws:s3:::${RESULTS_BUCKET_NAME}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sqs:ReceiveMessage",
                "sqs:DeleteMessage",
                "sqs:GetQueueAttributes"
            ],
            "Resource": "${MAIN_QUEUE_ARN}"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "${PROJECT_NAME}-lambda-role" \
        --policy-name LambdaAccessPolicy \
        --policy-document "file://${TEMP_DIR}/lambda-policy.json"
    
    export LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "${PROJECT_NAME}-lambda-role" --query Role.Arn --output text)
    wait_for_resource "role" "${PROJECT_NAME}-lambda-role"
    log_success "Created Lambda IAM role"
    
    # Step 6: Create Job Processor Lambda Function
    log_info "Creating Job Processor Lambda function..."
    
    cat > "${TEMP_DIR}/job-processor.py" << 'EOF'
import json
import boto3
import uuid
import time
import os
from datetime import datetime, timezone

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    table_name = os.environ['JOBS_TABLE_NAME']
    results_bucket = os.environ['RESULTS_BUCKET_NAME']
    
    table = dynamodb.Table(table_name)
    
    for record in event['Records']:
        try:
            # Parse message from SQS
            message_body = json.loads(record['body'])
            job_id = message_body['jobId']
            job_data = message_body['data']
            
            # Update job status to processing
            table.update_item(
                Key={'jobId': job_id},
                UpdateExpression='SET #status = :status, #updatedAt = :timestamp',
                ExpressionAttributeNames={
                    '#status': 'status',
                    '#updatedAt': 'updatedAt'
                },
                ExpressionAttributeValues={
                    ':status': 'processing',
                    ':timestamp': datetime.now(timezone.utc).isoformat()
                }
            )
            
            # Simulate processing work (replace with actual processing logic)
            time.sleep(10)  # Simulate work
            
            # Generate result
            result = {
                'jobId': job_id,
                'result': f'Processed data: {job_data}',
                'processedAt': datetime.now(timezone.utc).isoformat()
            }
            
            # Store result in S3
            s3.put_object(
                Bucket=results_bucket,
                Key=f'results/{job_id}.json',
                Body=json.dumps(result),
                ContentType='application/json'
            )
            
            # Update job status to completed
            table.update_item(
                Key={'jobId': job_id},
                UpdateExpression='SET #status = :status, #result = :result, #updatedAt = :timestamp',
                ExpressionAttributeNames={
                    '#status': 'status',
                    '#result': 'result',
                    '#updatedAt': 'updatedAt'
                },
                ExpressionAttributeValues={
                    ':status': 'completed',
                    ':result': f's3://{results_bucket}/results/{job_id}.json',
                    ':timestamp': datetime.now(timezone.utc).isoformat()
                }
            )
            
            print(f"Successfully processed job {job_id}")
            
        except Exception as e:
            print(f"Error processing job: {str(e)}")
            # Update job status to failed
            table.update_item(
                Key={'jobId': job_id},
                UpdateExpression='SET #status = :status, #error = :error, #updatedAt = :timestamp',
                ExpressionAttributeNames={
                    '#status': 'status',
                    '#error': 'error',
                    '#updatedAt': 'updatedAt'
                },
                ExpressionAttributeValues={
                    ':status': 'failed',
                    ':error': str(e),
                    ':timestamp': datetime.now(timezone.utc).isoformat()
                }
            )
            raise

    return {'statusCode': 200, 'body': 'Processing complete'}
EOF
    
    cd "${TEMP_DIR}" && zip job-processor.zip job-processor.py
    
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-job-processor" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler job-processor.lambda_handler \
        --zip-file fileb://job-processor.zip \
        --timeout 300 \
        --memory-size 512 \
        --environment Variables='{
            "JOBS_TABLE_NAME": "'${JOBS_TABLE_NAME}'",
            "RESULTS_BUCKET_NAME": "'${RESULTS_BUCKET_NAME}'"
        }' > /dev/null
    
    log_success "Created Job Processor Lambda function"
    
    # Step 7: Create Status Check Lambda Function
    log_info "Creating Status Check Lambda function..."
    
    cat > "${TEMP_DIR}/status-checker.py" << 'EOF'
import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    table_name = os.environ['JOBS_TABLE_NAME']
    table = dynamodb.Table(table_name)
    
    job_id = event['pathParameters']['jobId']
    
    try:
        response = table.get_item(Key={'jobId': job_id})
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Job not found'})
            }
        
        job = response['Item']
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'jobId': job['jobId'],
                'status': job['status'],
                'createdAt': job['createdAt'],
                'updatedAt': job.get('updatedAt', job['createdAt']),
                'result': job.get('result'),
                'error': job.get('error')
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    cd "${TEMP_DIR}" && zip status-checker.zip status-checker.py
    
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-status-checker" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler status-checker.lambda_handler \
        --zip-file fileb://status-checker.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables='{
            "JOBS_TABLE_NAME": "'${JOBS_TABLE_NAME}'"
        }' > /dev/null
    
    log_success "Created Status Check Lambda function"
    
    # Step 8: Create API Gateway REST API
    log_info "Creating API Gateway REST API..."
    export API_ID=$(aws apigateway create-rest-api \
        --name "${API_NAME}" \
        --description "Asynchronous API with SQS integration" \
        --endpoint-configuration types=REGIONAL \
        --query id --output text)
    
    export ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query 'items[0].id' --output text)
    
    log_success "Created API Gateway: ${API_ID}"
    
    # Step 9: Create Submit Job Endpoint
    log_info "Creating /submit endpoint..."
    export SUBMIT_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "${API_ID}" \
        --parent-id "${ROOT_RESOURCE_ID}" \
        --path-part submit \
        --query id --output text)
    
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${SUBMIT_RESOURCE_ID}" \
        --http-method POST \
        --authorization-type NONE \
        --request-parameters '{}' > /dev/null
    
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${SUBMIT_RESOURCE_ID}" \
        --http-method POST \
        --type AWS \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:sqs:path/${AWS_ACCOUNT_ID}/${MAIN_QUEUE_NAME}" \
        --credentials "${API_GATEWAY_ROLE_ARN}" \
        --request-parameters '{
            "integration.request.header.Content-Type": "'"'"'application/x-amz-json-1.0'"'"'",
            "integration.request.querystring.Action": "'"'"'SendMessage'"'"'",
            "integration.request.querystring.MessageBody": "method.request.body"
        }' \
        --request-templates '{
            "application/json": "{\"jobId\": \"$context.requestId\", \"data\": $input.json(\"$\"), \"timestamp\": \"$context.requestTime\"}"
        }' > /dev/null
    
    aws apigateway put-method-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${SUBMIT_RESOURCE_ID}" \
        --http-method POST \
        --status-code 200 \
        --response-models '{"application/json": "Empty"}' > /dev/null
    
    aws apigateway put-integration-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${SUBMIT_RESOURCE_ID}" \
        --http-method POST \
        --status-code 200 \
        --response-templates '{
            "application/json": "{\"jobId\": \"$context.requestId\", \"status\": \"queued\", \"message\": \"Job submitted successfully\"}"
        }' > /dev/null
    
    log_success "Created /submit endpoint"
    
    # Step 10: Create Status Check Endpoint
    log_info "Creating /status/{jobId} endpoint..."
    export STATUS_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "${API_ID}" \
        --parent-id "${ROOT_RESOURCE_ID}" \
        --path-part status \
        --query id --output text)
    
    export STATUS_JOB_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "${API_ID}" \
        --parent-id "${STATUS_RESOURCE_ID}" \
        --path-part '{jobId}' \
        --query id --output text)
    
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${STATUS_JOB_RESOURCE_ID}" \
        --http-method GET \
        --authorization-type NONE \
        --request-parameters '{"method.request.path.jobId": true}' > /dev/null
    
    export STATUS_LAMBDA_ARN=$(aws lambda get-function \
        --function-name "${PROJECT_NAME}-status-checker" \
        --query Configuration.FunctionArn --output text)
    
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${STATUS_JOB_RESOURCE_ID}" \
        --http-method GET \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${STATUS_LAMBDA_ARN}/invocations" > /dev/null
    
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-status-checker" \
        --statement-id apigateway-invoke \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" > /dev/null
    
    log_success "Created /status/{jobId} endpoint"
    
    # Step 11: Configure SQS Lambda Trigger
    log_info "Configuring SQS Lambda trigger..."
    aws lambda create-event-source-mapping \
        --event-source-arn "${MAIN_QUEUE_ARN}" \
        --function-name "${PROJECT_NAME}-job-processor" \
        --batch-size 10 \
        --maximum-batching-window-in-seconds 5 > /dev/null
    
    log_success "Configured SQS Lambda trigger"
    
    # Step 12: Deploy API Gateway
    log_info "Deploying API Gateway..."
    aws apigateway create-deployment \
        --rest-api-id "${API_ID}" \
        --stage-name prod \
        --stage-description "Production stage" \
        --description "Initial deployment" > /dev/null
    
    export API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    log_success "API deployed at: ${API_ENDPOINT}"
    
    # Save deployment information
    cat > deployment-info.txt << EOF
# Asynchronous API Patterns Deployment Information
# Generated on: $(date)

PROJECT_NAME=${PROJECT_NAME}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}

# API Gateway
API_ID=${API_ID}
API_ENDPOINT=${API_ENDPOINT}

# SQS Queues
MAIN_QUEUE_NAME=${MAIN_QUEUE_NAME}
MAIN_QUEUE_URL=${MAIN_QUEUE_URL}
DLQ_NAME=${DLQ_NAME}
DLQ_URL=${DLQ_URL}

# DynamoDB
JOBS_TABLE_NAME=${JOBS_TABLE_NAME}

# S3
RESULTS_BUCKET_NAME=${RESULTS_BUCKET_NAME}

# Lambda Functions
JOB_PROCESSOR_FUNCTION=${PROJECT_NAME}-job-processor
STATUS_CHECKER_FUNCTION=${PROJECT_NAME}-status-checker

# IAM Roles
API_GATEWAY_ROLE=${PROJECT_NAME}-api-gateway-role
LAMBDA_ROLE=${PROJECT_NAME}-lambda-role

# Test Commands
# Submit a job:
curl -X POST -H "Content-Type: application/json" -d '{"task": "process_data", "data": {"input": "test data"}}' ${API_ENDPOINT}/submit

# Check job status (replace JOB_ID with actual job ID from submit response):
curl ${API_ENDPOINT}/status/JOB_ID
EOF
    
    log_success "Deployment information saved to deployment-info.txt"
    
    # Final status
    echo
    log_success "🎉 Deployment completed successfully!"
    echo
    log_info "API Endpoint: ${API_ENDPOINT}"
    log_info "Submit jobs to: ${API_ENDPOINT}/submit"
    log_info "Check status at: ${API_ENDPOINT}/status/{jobId}"
    echo
    log_info "Test your deployment with:"
    echo "  curl -X POST -H \"Content-Type: application/json\" \\"
    echo "    -d '{\"task\": \"process_data\", \"data\": {\"input\": \"test data\"}}' \\"
    echo "    ${API_ENDPOINT}/submit"
    echo
    log_warning "Remember to run the destroy script when you're done to avoid ongoing charges."
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi