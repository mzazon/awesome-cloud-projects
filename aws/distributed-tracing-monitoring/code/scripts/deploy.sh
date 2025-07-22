#!/bin/bash

# AWS X-Ray Infrastructure Monitoring - Deployment Script
# This script deploys a complete X-Ray monitoring solution with Lambda, API Gateway, and DynamoDB

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
PROJECT_PREFIX="xray-monitoring"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure'."
    fi
    
    # Check required AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "${AWS_CLI_VERSION}" | cut -d. -f1) -lt 2 ]]; then
        error_exit "AWS CLI version 2.x is required. Current version: ${AWS_CLI_VERSION}"
    fi
    
    # Check if jq is available (optional but recommended)
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. JSON output may be less readable."
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        error_exit "curl is not installed. Required for API testing."
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        warning "No AWS region configured, using default: ${AWS_REGION}"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export PROJECT_NAME="${PROJECT_PREFIX}-${RANDOM_SUFFIX}"
    export ORDERS_TABLE_NAME="${PROJECT_NAME}-orders"
    export LAMBDA_ROLE_NAME="${PROJECT_NAME}-lambda-role"
    export API_GATEWAY_NAME="${PROJECT_NAME}-api"
    
    # Save environment variables for later use
    cat > "${SCRIPT_DIR}/.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
PROJECT_NAME=${PROJECT_NAME}
ORDERS_TABLE_NAME=${ORDERS_TABLE_NAME}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
API_GATEWAY_NAME=${API_GATEWAY_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables configured"
    info "Project Name: ${PROJECT_NAME}"
    info "AWS Region: ${AWS_REGION}"
    info "AWS Account: ${AWS_ACCOUNT_ID}"
}

# Create IAM role for Lambda functions
create_iam_role() {
    info "Creating IAM role for Lambda functions..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &>/dev/null; then
        warning "IAM role ${LAMBDA_ROLE_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create trust policy
    cat > /tmp/lambda-trust-policy.json << EOF
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
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
        --tags Key=Project,Value="${PROJECT_NAME}" Key=Purpose,Value="X-Ray Monitoring Demo" || error_exit "Failed to create IAM role"
    
    # Attach necessary policies
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || error_exit "Failed to attach Lambda execution policy"
    
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess || error_exit "Failed to attach X-Ray policy"
    
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess || error_exit "Failed to attach DynamoDB policy"
    
    # Wait for role to be available
    info "Waiting for IAM role to be available..."
    sleep 10
    
    success "IAM role created and configured"
}

# Create DynamoDB table
create_dynamodb_table() {
    info "Creating DynamoDB table..."
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name "${ORDERS_TABLE_NAME}" &>/dev/null; then
        warning "DynamoDB table ${ORDERS_TABLE_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create DynamoDB table
    aws dynamodb create-table \
        --table-name "${ORDERS_TABLE_NAME}" \
        --attribute-definitions \
            AttributeName=orderId,AttributeType=S \
        --key-schema \
            AttributeName=orderId,KeyType=HASH \
        --provisioned-throughput \
            ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --tags Key=Project,Value="${PROJECT_NAME}" Key=Purpose,Value="X-Ray Monitoring Demo" || error_exit "Failed to create DynamoDB table"
    
    # Wait for table to be active
    info "Waiting for DynamoDB table to be active..."
    aws dynamodb wait table-exists --table-name "${ORDERS_TABLE_NAME}" || error_exit "Timeout waiting for DynamoDB table"
    
    success "DynamoDB table created: ${ORDERS_TABLE_NAME}"
}

# Create Lambda functions
create_lambda_functions() {
    info "Creating Lambda functions..."
    
    # Create temporary directory for Lambda code
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Create order processor function
    create_order_processor_function
    
    # Create inventory manager function
    create_inventory_manager_function
    
    # Create trace analyzer function
    create_trace_analyzer_function
    
    # Cleanup temporary directory
    cd "${SCRIPT_DIR}"
    rm -rf "${TEMP_DIR}"
    
    success "All Lambda functions created"
}

# Create order processor Lambda function
create_order_processor_function() {
    info "Creating order processor Lambda function..."
    
    # Check if function already exists
    if aws lambda get-function --function-name "${PROJECT_NAME}-order-processor" &>/dev/null; then
        warning "Lambda function ${PROJECT_NAME}-order-processor already exists, skipping creation"
        return 0
    fi
    
    # Create function code
    cat > order-processor.py << 'EOF'
import json
import boto3
import uuid
from datetime import datetime
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all
import os

# Patch AWS SDK calls for X-Ray tracing
patch_all()

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['ORDERS_TABLE'])

@xray_recorder.capture('process_order')
def lambda_handler(event, context):
    try:
        # Add custom annotations for filtering
        xray_recorder.put_annotation('service', 'order-processor')
        xray_recorder.put_annotation('operation', 'create_order')
        
        # Extract order details
        body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        
        order_id = str(uuid.uuid4())
        order_data = {
            'orderId': order_id,
            'customerId': body.get('customerId'),
            'productId': body.get('productId'),
            'quantity': body.get('quantity', 1),
            'timestamp': datetime.utcnow().isoformat(),
            'status': 'pending'
        }
        
        # Add custom metadata
        xray_recorder.put_metadata('order_details', {
            'order_id': order_id,
            'customer_id': body.get('customerId'),
            'product_id': body.get('productId')
        })
        
        # Store order in DynamoDB
        with xray_recorder.in_subsegment('dynamodb_put_item'):
            table.put_item(Item=order_data)
        
        # Simulate calling inventory service
        inventory_response = check_inventory(body.get('productId'))
        
        # Simulate calling notification service
        notification_response = send_notification(order_id, body.get('customerId'))
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'orderId': order_id,
                'status': 'processed',
                'inventory': inventory_response,
                'notification': notification_response
            })
        }
        
    except Exception as e:
        xray_recorder.put_annotation('error', str(e))
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }

@xray_recorder.capture('check_inventory')
def check_inventory(product_id):
    # Simulate inventory check with artificial delay
    import time
    time.sleep(0.1)
    
    xray_recorder.put_annotation('inventory_check', 'completed')
    return {'status': 'available', 'quantity': 100}

@xray_recorder.capture('send_notification')
def send_notification(order_id, customer_id):
    # Simulate notification sending
    import time
    time.sleep(0.05)
    
    xray_recorder.put_annotation('notification_sent', 'true')
    return {'status': 'sent', 'channel': 'email'}
EOF
    
    # Install dependencies and create package
    pip install aws-xray-sdk -t . --quiet || error_exit "Failed to install X-Ray SDK"
    zip -r order-processor.zip . -x "*.pyc" "__pycache__/*" &>/dev/null || error_exit "Failed to create deployment package"
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-order-processor" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
        --handler order-processor.lambda_handler \
        --zip-file fileb://order-processor.zip \
        --environment Variables="{ORDERS_TABLE=${ORDERS_TABLE_NAME}}" \
        --tracing-config Mode=Active \
        --timeout 30 \
        --tags Project="${PROJECT_NAME}",Purpose="X-Ray Monitoring Demo" &>/dev/null || error_exit "Failed to create order processor function"
    
    success "Order processor Lambda function created"
}

# Create inventory manager Lambda function
create_inventory_manager_function() {
    info "Creating inventory manager Lambda function..."
    
    # Check if function already exists
    if aws lambda get-function --function-name "${PROJECT_NAME}-inventory-manager" &>/dev/null; then
        warning "Lambda function ${PROJECT_NAME}-inventory-manager already exists, skipping creation"
        return 0
    fi
    
    # Create function code
    cat > inventory-manager.py << 'EOF'
import json
import boto3
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all
import time

# Patch AWS SDK calls for X-Ray tracing
patch_all()

@xray_recorder.capture('inventory_manager')
def lambda_handler(event, context):
    try:
        xray_recorder.put_annotation('service', 'inventory-manager')
        xray_recorder.put_annotation('operation', 'update_inventory')
        
        # Simulate inventory processing
        with xray_recorder.in_subsegment('inventory_validation'):
            product_id = event.get('productId')
            quantity = event.get('quantity', 1)
            
            # Simulate database lookup
            time.sleep(0.1)
            
            xray_recorder.put_metadata('inventory_check', {
                'product_id': product_id,
                'requested_quantity': quantity,
                'available_quantity': 100
            })
        
        # Simulate inventory update
        with xray_recorder.in_subsegment('inventory_update'):
            time.sleep(0.05)
            xray_recorder.put_annotation('inventory_updated', 'true')
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'productId': product_id,
                'status': 'reserved',
                'availableQuantity': 100 - quantity
            })
        }
        
    except Exception as e:
        xray_recorder.put_annotation('error', str(e))
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Create deployment package (reuse existing aws-xray-sdk)
    zip -r inventory-manager.zip inventory-manager.py aws_xray_sdk/ &>/dev/null || error_exit "Failed to create deployment package"
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-inventory-manager" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
        --handler inventory-manager.lambda_handler \
        --zip-file fileb://inventory-manager.zip \
        --tracing-config Mode=Active \
        --timeout 30 \
        --tags Project="${PROJECT_NAME}",Purpose="X-Ray Monitoring Demo" &>/dev/null || error_exit "Failed to create inventory manager function"
    
    success "Inventory manager Lambda function created"
}

# Create trace analyzer Lambda function
create_trace_analyzer_function() {
    info "Creating trace analyzer Lambda function..."
    
    # Check if function already exists
    if aws lambda get-function --function-name "${PROJECT_NAME}-trace-analyzer" &>/dev/null; then
        warning "Lambda function ${PROJECT_NAME}-trace-analyzer already exists, skipping creation"
        return 0
    fi
    
    # Create function code
    cat > trace-analyzer.py << 'EOF'
import json
import boto3
from datetime import datetime, timedelta

xray_client = boto3.client('xray')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Get traces from last hour
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        # Get trace summaries
        response = xray_client.get_trace_summaries(
            TimeRangeType='TimeStamp',
            StartTime=start_time,
            EndTime=end_time,
            FilterExpression='service("order-processor")'
        )
        
        # Analyze traces
        total_traces = len(response['TraceSummaries'])
        error_traces = len([t for t in response['TraceSummaries'] if t.get('IsError')])
        high_latency_traces = len([t for t in response['TraceSummaries'] if t.get('ResponseTime', 0) > 2])
        
        # Send custom metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='XRay/Analysis',
            MetricData=[
                {
                    'MetricName': 'TotalTraces',
                    'Value': total_traces,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'ErrorTraces',
                    'Value': error_traces,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'HighLatencyTraces',
                    'Value': high_latency_traces,
                    'Unit': 'Count'
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'total_traces': total_traces,
                'error_traces': error_traces,
                'high_latency_traces': high_latency_traces
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Create deployment package
    zip -r trace-analyzer.zip trace-analyzer.py &>/dev/null || error_exit "Failed to create deployment package"
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-trace-analyzer" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
        --handler trace-analyzer.lambda_handler \
        --zip-file fileb://trace-analyzer.zip \
        --timeout 60 \
        --tags Project="${PROJECT_NAME}",Purpose="X-Ray Monitoring Demo" &>/dev/null || error_exit "Failed to create trace analyzer function"
    
    success "Trace analyzer Lambda function created"
}

# Create API Gateway
create_api_gateway() {
    info "Creating API Gateway..."
    
    # Check if API already exists
    EXISTING_API_ID=$(aws apigateway get-rest-apis --query "items[?name=='${API_GATEWAY_NAME}'].id" --output text)
    if [[ -n "${EXISTING_API_ID}" && "${EXISTING_API_ID}" != "None" ]]; then
        warning "API Gateway ${API_GATEWAY_NAME} already exists, using existing API: ${EXISTING_API_ID}"
        export API_ID="${EXISTING_API_ID}"
    else
        # Create REST API
        export API_ID=$(aws apigateway create-rest-api \
            --name "${API_GATEWAY_NAME}" \
            --description "API for X-Ray monitoring demo" \
            --query 'id' --output text) || error_exit "Failed to create API Gateway"
    fi
    
    # Get root resource ID
    ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query 'items[0].id' --output text) || error_exit "Failed to get root resource"
    
    # Create orders resource
    ORDERS_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "${API_ID}" \
        --parent-id "${ROOT_RESOURCE_ID}" \
        --path-part orders \
        --query 'id' --output text 2>/dev/null || \
        aws apigateway get-resources \
            --rest-api-id "${API_ID}" \
            --query "items[?pathPart=='orders'].id" --output text)
    
    # Create POST method for orders
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${ORDERS_RESOURCE_ID}" \
        --http-method POST \
        --authorization-type NONE &>/dev/null || warning "POST method already exists"
    
    # Configure method integration
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${ORDERS_RESOURCE_ID}" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-order-processor/invocations" &>/dev/null || warning "Integration already exists"
    
    # Grant API Gateway permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-order-processor" \
        --statement-id api-gateway-invoke \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*" &>/dev/null || warning "Permission already exists"
    
    # Deploy API Gateway
    aws apigateway create-deployment \
        --rest-api-id "${API_ID}" \
        --stage-name prod &>/dev/null || warning "Deployment already exists"
    
    # Enable X-Ray tracing on the stage
    aws apigateway update-stage \
        --rest-api-id "${API_ID}" \
        --stage-name prod \
        --patch-ops op=replace,path=/tracingEnabled,value=true || error_exit "Failed to enable X-Ray tracing"
    
    # Store API endpoint
    export API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    echo "API_ID=${API_ID}" >> "${SCRIPT_DIR}/.env"
    echo "API_ENDPOINT=${API_ENDPOINT}" >> "${SCRIPT_DIR}/.env"
    
    success "API Gateway created and deployed"
    info "API Endpoint: ${API_ENDPOINT}"
}

# Create X-Ray sampling rules
create_xray_sampling_rules() {
    info "Creating X-Ray sampling rules..."
    
    # Create high-priority sampling rule
    cat > /tmp/high-priority-sampling.json << EOF
{
    "SamplingRule": {
        "RuleName": "${PROJECT_NAME}-high-priority",
        "ResourceARN": "*",
        "Priority": 100,
        "FixedRate": 1.0,
        "ReservoirSize": 10,
        "ServiceName": "order-processor",
        "ServiceType": "*",
        "Host": "*",
        "HTTPMethod": "*",
        "URLPath": "*",
        "Version": 1
    }
}
EOF
    
    # Create error sampling rule
    cat > /tmp/error-sampling.json << EOF
{
    "SamplingRule": {
        "RuleName": "${PROJECT_NAME}-errors",
        "ResourceARN": "*",
        "Priority": 50,
        "FixedRate": 1.0,
        "ReservoirSize": 5,
        "ServiceName": "*",
        "ServiceType": "*",
        "Host": "*",
        "HTTPMethod": "*",
        "URLPath": "*",
        "Version": 1
    }
}
EOF
    
    # Create sampling rules
    aws xray create-sampling-rule \
        --cli-input-json file:///tmp/high-priority-sampling.json &>/dev/null || warning "High priority sampling rule already exists"
    
    aws xray create-sampling-rule \
        --cli-input-json file:///tmp/error-sampling.json &>/dev/null || warning "Error sampling rule already exists"
    
    success "X-Ray sampling rules created"
}

# Create X-Ray filter groups
create_xray_filter_groups() {
    info "Creating X-Ray filter groups..."
    
    # Create filter groups
    aws xray create-group \
        --group-name "${PROJECT_NAME}-high-latency" \
        --filter-expression "responsetime > 2" &>/dev/null || warning "High latency filter group already exists"
    
    aws xray create-group \
        --group-name "${PROJECT_NAME}-errors" \
        --filter-expression "error = true OR fault = true" &>/dev/null || warning "Error filter group already exists"
    
    aws xray create-group \
        --group-name "${PROJECT_NAME}-order-service" \
        --filter-expression "service(\"order-processor\")" &>/dev/null || warning "Order service filter group already exists"
    
    success "X-Ray filter groups created"
}

# Create EventBridge rule for trace analyzer
create_eventbridge_rule() {
    info "Creating EventBridge rule for automated trace analysis..."
    
    # Create EventBridge rule
    aws events put-rule \
        --name "${PROJECT_NAME}-trace-analysis" \
        --schedule-expression "rate(1 hour)" \
        --state ENABLED &>/dev/null || warning "EventBridge rule already exists"
    
    # Add Lambda as target
    aws events put-targets \
        --rule "${PROJECT_NAME}-trace-analysis" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-trace-analyzer" &>/dev/null || warning "EventBridge target already exists"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-trace-analyzer" \
        --statement-id eventbridge-invoke \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${PROJECT_NAME}-trace-analysis" &>/dev/null || warning "EventBridge permission already exists"
    
    success "EventBridge rule configured for automated trace analysis"
}

# Create CloudWatch dashboard and alarms
create_cloudwatch_resources() {
    info "Creating CloudWatch dashboard and alarms..."
    
    # Create CloudWatch dashboard
    cat > /tmp/xray-dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/X-Ray", "TracesReceived"],
                    ["AWS/X-Ray", "TracesScanned"],
                    ["AWS/X-Ray", "LatencyHigh"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "X-Ray Trace Metrics"
            }
        },
        {
            "type": "metric",
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Duration", "FunctionName", "${PROJECT_NAME}-order-processor"],
                    ["AWS/Lambda", "Errors", "FunctionName", "${PROJECT_NAME}-order-processor"],
                    ["AWS/Lambda", "Throttles", "FunctionName", "${PROJECT_NAME}-order-processor"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Lambda Function Metrics"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${PROJECT_NAME}-xray-monitoring" \
        --dashboard-body file:///tmp/xray-dashboard.json || warning "Failed to create CloudWatch dashboard"
    
    # Create CloudWatch alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-high-error-rate" \
        --alarm-description "High error rate detected in X-Ray traces" \
        --metric-name ErrorTraces \
        --namespace XRay/Analysis \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 &>/dev/null || warning "Error rate alarm already exists"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-high-latency" \
        --alarm-description "High latency detected in X-Ray traces" \
        --metric-name HighLatencyTraces \
        --namespace XRay/Analysis \
        --statistic Sum \
        --period 300 \
        --threshold 3 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 &>/dev/null || warning "Latency alarm already exists"
    
    success "CloudWatch dashboard and alarms created"
}

# Generate test traffic
generate_test_traffic() {
    info "Generating test traffic to populate X-Ray traces..."
    
    if [[ -z "${API_ENDPOINT:-}" ]]; then
        # Try to load from .env file
        if [[ -f "${SCRIPT_DIR}/.env" ]]; then
            source "${SCRIPT_DIR}/.env"
        else
            error_exit "API endpoint not found. Please ensure API Gateway was created successfully."
        fi
    fi
    
    # Generate successful requests
    info "Sending successful test requests..."
    for i in {1..5}; do
        curl -s -X POST "${API_ENDPOINT}/orders" \
            -H "Content-Type: application/json" \
            -d "{
                \"customerId\": \"customer-${i}\",
                \"productId\": \"product-${i}\",
                \"quantity\": ${i}
            }" > /dev/null
        sleep 1
    done
    
    # Generate some error requests
    info "Sending error test requests..."
    for i in {1..2}; do
        curl -s -X POST "${API_ENDPOINT}/orders" \
            -H "Content-Type: application/json" \
            -d "{
                \"invalid\": \"data\"
            }" > /dev/null
        sleep 1
    done
    
    success "Test traffic generated - traces should appear in X-Ray console within 2-3 minutes"
}

# Main deployment function
main() {
    echo "=========================================="
    echo "AWS X-Ray Infrastructure Monitoring"
    echo "Deployment Script"
    echo "=========================================="
    echo ""
    
    # Initialize log file
    echo "Deployment started at $(date)" > "${LOG_FILE}"
    
    # Check if running in dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        info "Running in dry-run mode - no resources will be created"
        DRY_RUN=true
    else
        DRY_RUN=false
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "Dry-run mode: would perform the following actions:"
        info "1. Check prerequisites"
        info "2. Set up environment variables"
        info "3. Create IAM role for Lambda functions"
        info "4. Create DynamoDB table"
        info "5. Create Lambda functions (order processor, inventory manager, trace analyzer)"
        info "6. Create and deploy API Gateway"
        info "7. Create X-Ray sampling rules and filter groups"
        info "8. Create EventBridge rule for automated analysis"
        info "9. Create CloudWatch dashboard and alarms"
        info "10. Generate test traffic"
        return 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_iam_role
    create_dynamodb_table
    create_lambda_functions
    create_api_gateway
    create_xray_sampling_rules
    create_xray_filter_groups
    create_eventbridge_rule
    create_cloudwatch_resources
    generate_test_traffic
    
    echo ""
    echo "=========================================="
    success "Deployment completed successfully!"
    echo "=========================================="
    echo ""
    info "Resources created:"
    info "• Project Name: ${PROJECT_NAME}"
    info "• DynamoDB Table: ${ORDERS_TABLE_NAME}"
    info "• Lambda Functions: ${PROJECT_NAME}-order-processor, ${PROJECT_NAME}-inventory-manager, ${PROJECT_NAME}-trace-analyzer"
    info "• API Gateway: ${API_ENDPOINT}"
    info "• CloudWatch Dashboard: ${PROJECT_NAME}-xray-monitoring"
    echo ""
    info "Next steps:"
    info "1. Visit the X-Ray console to view service maps and traces"
    info "2. Check CloudWatch dashboard for metrics"
    info "3. Test the API endpoint: ${API_ENDPOINT}/orders"
    echo ""
    warning "Remember to run the destroy script when done to avoid charges"
    echo ""
    
    # Save final configuration
    cat >> "${SCRIPT_DIR}/.env" << EOF
DEPLOYMENT_COMPLETE=true
DEPLOYMENT_TIME=$(date)
EOF
}

# Run main function
main "$@"