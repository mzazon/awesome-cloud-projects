#!/bin/bash

# Event-Driven Microservices with EventBridge and Step Functions - Deployment Script
# This script deploys the complete event-driven microservices architecture

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# ANSI color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling function
handle_error() {
    log_error "An error occurred on line $1. Exiting..."
    exit 1
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# Parse command line arguments
DRY_RUN=false
FORCE=false
SKIP_TESTS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Deploy event-driven microservices architecture"
            echo ""
            echo "OPTIONS:"
            echo "  --dry-run     Show what would be deployed without making changes"
            echo "  --force       Force deployment even if resources exist"
            echo "  --skip-tests  Skip post-deployment validation tests"
            echo "  -h, --help    Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN MODE - No actual changes will be made"
fi

log "Starting deployment of Event-Driven Microservices architecture..."

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS CLI is not configured or credentials are invalid."
    exit 1
fi

# Check if jq is available for JSON parsing
if ! command -v jq &> /dev/null; then
    log_warning "jq is not installed. Some features may not work properly."
fi

log_success "Prerequisites check completed"

# Set environment variables
log "Setting up environment variables..."

export AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    export AWS_REGION="us-east-1"
    log_warning "No default region set, using us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))

export PROJECT_NAME="microservices-demo"
export EVENTBUS_NAME="${PROJECT_NAME}-eventbus-${RANDOM_SUFFIX}"
export LAMBDA_ROLE_NAME="${PROJECT_NAME}-lambda-role-${RANDOM_SUFFIX}"
export STEPFUNCTIONS_ROLE_NAME="${PROJECT_NAME}-stepfunctions-role-${RANDOM_SUFFIX}"
export DYNAMODB_TABLE_NAME="${PROJECT_NAME}-orders-${RANDOM_SUFFIX}"

log_success "Environment variables configured:"
log "  AWS Region: ${AWS_REGION}"
log "  AWS Account ID: ${AWS_ACCOUNT_ID}"
log "  EventBus Name: ${EVENTBUS_NAME}"
log "  DynamoDB Table: ${DYNAMODB_TABLE_NAME}"

# Save environment variables to file for cleanup script
cat > .deployment_env << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export PROJECT_NAME="${PROJECT_NAME}"
export EVENTBUS_NAME="${EVENTBUS_NAME}"
export LAMBDA_ROLE_NAME="${LAMBDA_ROLE_NAME}"
export STEPFUNCTIONS_ROLE_NAME="${STEPFUNCTIONS_ROLE_NAME}"
export DYNAMODB_TABLE_NAME="${DYNAMODB_TABLE_NAME}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF

if [ "$DRY_RUN" = true ]; then
    log "DRY RUN: Would create IAM roles, DynamoDB table, EventBridge bus, Lambda functions, and Step Functions state machine"
    exit 0
fi

# Step 1: Create IAM roles
log "Creating IAM roles..."

# Create Lambda execution role
log "Creating Lambda execution role..."
aws iam create-role \
    --role-name ${LAMBDA_ROLE_NAME} \
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
    }' > /dev/null

# Attach policies to Lambda role
aws iam attach-role-policy \
    --role-name ${LAMBDA_ROLE_NAME} \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam attach-role-policy \
    --role-name ${LAMBDA_ROLE_NAME} \
    --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

aws iam attach-role-policy \
    --role-name ${LAMBDA_ROLE_NAME} \
    --policy-arn arn:aws:iam::aws:policy/Amazon-EventBridge-FullAccess

# Create Step Functions execution role
log "Creating Step Functions execution role..."
aws iam create-role \
    --role-name ${STEPFUNCTIONS_ROLE_NAME} \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "states.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }' > /dev/null

aws iam attach-role-policy \
    --role-name ${STEPFUNCTIONS_ROLE_NAME} \
    --policy-arn arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess

aws iam attach-role-policy \
    --role-name ${STEPFUNCTIONS_ROLE_NAME} \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaRole

log_success "IAM roles created successfully"

# Wait for role propagation
log "Waiting for IAM role propagation..."
sleep 10

# Step 2: Create DynamoDB table
log "Creating DynamoDB table..."
aws dynamodb create-table \
    --table-name ${DYNAMODB_TABLE_NAME} \
    --attribute-definitions \
        AttributeName=orderId,AttributeType=S \
        AttributeName=customerId,AttributeType=S \
    --key-schema \
        AttributeName=orderId,KeyType=HASH \
        AttributeName=customerId,KeyType=RANGE \
    --provisioned-throughput \
        ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --global-secondary-indexes \
        IndexName=CustomerId-Index,KeySchema=["{AttributeName=customerId,KeyType=HASH}"],Projection="{ProjectionType=ALL}",ProvisionedThroughput="{ReadCapacityUnits=5,WriteCapacityUnits=5}" > /dev/null

# Wait for table to be created
log "Waiting for DynamoDB table to become active..."
aws dynamodb wait table-exists --table-name ${DYNAMODB_TABLE_NAME}
log_success "DynamoDB table created and active"

# Step 3: Create EventBridge custom event bus
log "Creating EventBridge custom event bus..."
aws events create-event-bus \
    --name ${EVENTBUS_NAME} \
    --tags Key=Project,Value=${PROJECT_NAME} \
        Key=Environment,Value=development > /dev/null

export EVENTBUS_ARN=$(aws events describe-event-bus \
    --name ${EVENTBUS_NAME} \
    --query 'Arn' --output text)

log_success "Custom EventBridge bus created"
log "EventBus ARN: ${EVENTBUS_ARN}"

# Step 4: Create Lambda functions
log "Creating Lambda functions..."

# Create temporary directory for Lambda code
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Create Order Service Lambda function
log "Creating Order Service Lambda function..."
cat > order-service.py << EOF
import json
import boto3
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        # Parse order data
        order_data = json.loads(event['body']) if 'body' in event else event
        
        # Create order record
        order_id = str(uuid.uuid4())
        order_item = {
            'orderId': order_id,
            'customerId': order_data['customerId'],
            'items': order_data['items'],
            'totalAmount': order_data['totalAmount'],
            'status': 'PENDING',
            'createdAt': datetime.utcnow().isoformat()
        }
        
        # Store in DynamoDB
        table = dynamodb.Table('${DYNAMODB_TABLE_NAME}')
        table.put_item(Item=order_item)
        
        # Publish event to EventBridge
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'order.service',
                    'DetailType': 'Order Created',
                    'Detail': json.dumps(order_item),
                    'EventBusName': '${EVENTBUS_NAME}'
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'orderId': order_id,
                'status': 'PENDING'
            })
        }
        
    except Exception as e:
        print(f"Error processing order: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF

# Replace environment variables in the function code
sed -i "s/\${DYNAMODB_TABLE_NAME}/${DYNAMODB_TABLE_NAME}/g" order-service.py
sed -i "s/\${EVENTBUS_NAME}/${EVENTBUS_NAME}/g" order-service.py

# Create deployment package
zip order-service.zip order-service.py

# Create Lambda function
export ORDER_SERVICE_ARN=$(aws lambda create-function \
    --function-name ${PROJECT_NAME}-order-service-${RANDOM_SUFFIX} \
    --runtime python3.9 \
    --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME} \
    --handler order-service.lambda_handler \
    --zip-file fileb://order-service.zip \
    --timeout 30 \
    --memory-size 256 \
    --environment Variables="{EVENTBUS_NAME=${EVENTBUS_NAME},DYNAMODB_TABLE_NAME=${DYNAMODB_TABLE_NAME}}" \
    --query 'FunctionArn' --output text)

log_success "Order Service Lambda function created"

# Create Payment Service Lambda function
log "Creating Payment Service Lambda function..."
cat > payment-service.py << EOF
import json
import boto3
import random
import time
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        # Parse payment data
        payment_data = event['detail'] if 'detail' in event else event
        order_id = payment_data['orderId']
        amount = payment_data['totalAmount']
        
        # Simulate payment processing delay
        time.sleep(2)
        
        # Simulate payment success/failure (90% success rate)
        payment_successful = random.random() < 0.9
        
        # Update order status
        table = dynamodb.Table('${DYNAMODB_TABLE_NAME}')
        
        if payment_successful:
            table.update_item(
                Key={'orderId': order_id, 'customerId': payment_data['customerId']},
                UpdateExpression='SET #status = :status, paymentId = :paymentId, updatedAt = :updatedAt',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': 'PAID',
                    ':paymentId': f'pay_{order_id[:8]}',
                    ':updatedAt': datetime.utcnow().isoformat()
                }
            )
            
            # Publish payment success event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'payment.service',
                        'DetailType': 'Payment Processed',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'paymentId': f'pay_{order_id[:8]}',
                            'amount': amount,
                            'status': 'SUCCESS'
                        }),
                        'EventBusName': '${EVENTBUS_NAME}'
                    }
                ]
            )
        else:
            table.update_item(
                Key={'orderId': order_id, 'customerId': payment_data['customerId']},
                UpdateExpression='SET #status = :status, updatedAt = :updatedAt',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': 'PAYMENT_FAILED',
                    ':updatedAt': datetime.utcnow().isoformat()
                }
            )
            
            # Publish payment failure event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'payment.service',
                        'DetailType': 'Payment Failed',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'amount': amount,
                            'status': 'FAILED'
                        }),
                        'EventBusName': '${EVENTBUS_NAME}'
                    }
                ]
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'orderId': order_id,
                'paymentStatus': 'SUCCESS' if payment_successful else 'FAILED'
            })
        }
        
    except Exception as e:
        print(f"Error processing payment: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF

# Replace environment variables
sed -i "s/\${DYNAMODB_TABLE_NAME}/${DYNAMODB_TABLE_NAME}/g" payment-service.py
sed -i "s/\${EVENTBUS_NAME}/${EVENTBUS_NAME}/g" payment-service.py

zip payment-service.zip payment-service.py

export PAYMENT_SERVICE_ARN=$(aws lambda create-function \
    --function-name ${PROJECT_NAME}-payment-service-${RANDOM_SUFFIX} \
    --runtime python3.9 \
    --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME} \
    --handler payment-service.lambda_handler \
    --zip-file fileb://payment-service.zip \
    --timeout 30 \
    --memory-size 256 \
    --environment Variables="{EVENTBUS_NAME=${EVENTBUS_NAME},DYNAMODB_TABLE_NAME=${DYNAMODB_TABLE_NAME}}" \
    --query 'FunctionArn' --output text)

log_success "Payment Service Lambda function created"

# Create Inventory Service Lambda function
log "Creating Inventory Service Lambda function..."
cat > inventory-service.py << EOF
import json
import boto3
import random
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        # Parse inventory data
        inventory_data = event['detail'] if 'detail' in event else event
        order_id = inventory_data['orderId']
        items = inventory_data['items']
        
        # Simulate inventory check (95% success rate)
        inventory_available = random.random() < 0.95
        
        # Update order status
        table = dynamodb.Table('${DYNAMODB_TABLE_NAME}')
        
        if inventory_available:
            table.update_item(
                Key={'orderId': order_id, 'customerId': inventory_data['customerId']},
                UpdateExpression='SET #status = :status, updatedAt = :updatedAt',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': 'INVENTORY_RESERVED',
                    ':updatedAt': datetime.utcnow().isoformat()
                }
            )
            
            # Publish inventory reserved event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'inventory.service',
                        'DetailType': 'Inventory Reserved',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'items': items,
                            'status': 'RESERVED'
                        }),
                        'EventBusName': '${EVENTBUS_NAME}'
                    }
                ]
            )
        else:
            table.update_item(
                Key={'orderId': order_id, 'customerId': inventory_data['customerId']},
                UpdateExpression='SET #status = :status, updatedAt = :updatedAt',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': 'INVENTORY_UNAVAILABLE',
                    ':updatedAt': datetime.utcnow().isoformat()
                }
            )
            
            # Publish inventory unavailable event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'inventory.service',
                        'DetailType': 'Inventory Unavailable',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'items': items,
                            'status': 'UNAVAILABLE'
                        }),
                        'EventBusName': '${EVENTBUS_NAME}'
                    }
                ]
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'orderId': order_id,
                'inventoryStatus': 'RESERVED' if inventory_available else 'UNAVAILABLE'
            })
        }
        
    except Exception as e:
        print(f"Error processing inventory: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF

sed -i "s/\${DYNAMODB_TABLE_NAME}/${DYNAMODB_TABLE_NAME}/g" inventory-service.py
sed -i "s/\${EVENTBUS_NAME}/${EVENTBUS_NAME}/g" inventory-service.py

zip inventory-service.zip inventory-service.py

export INVENTORY_SERVICE_ARN=$(aws lambda create-function \
    --function-name ${PROJECT_NAME}-inventory-service-${RANDOM_SUFFIX} \
    --runtime python3.9 \
    --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME} \
    --handler inventory-service.lambda_handler \
    --zip-file fileb://inventory-service.zip \
    --timeout 30 \
    --memory-size 256 \
    --environment Variables="{EVENTBUS_NAME=${EVENTBUS_NAME},DYNAMODB_TABLE_NAME=${DYNAMODB_TABLE_NAME}}" \
    --query 'FunctionArn' --output text)

log_success "Inventory Service Lambda function created"

# Create Notification Service Lambda function
log "Creating Notification Service Lambda function..."
cat > notification-service.py << EOF
import json
import boto3
from datetime import datetime

def lambda_handler(event, context):
    try:
        # Parse notification data
        notification_data = event['detail'] if 'detail' in event else event
        
        # Log notification (in real scenario, send email/SMS)
        print(f"NOTIFICATION: {json.dumps(notification_data, indent=2)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Notification sent successfully',
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error sending notification: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF

zip notification-service.zip notification-service.py

export NOTIFICATION_SERVICE_ARN=$(aws lambda create-function \
    --function-name ${PROJECT_NAME}-notification-service-${RANDOM_SUFFIX} \
    --runtime python3.9 \
    --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME} \
    --handler notification-service.lambda_handler \
    --zip-file fileb://notification-service.zip \
    --timeout 30 \
    --memory-size 256 \
    --query 'FunctionArn' --output text)

log_success "Notification Service Lambda function created"

# Step 5: Create CloudWatch Log Group for Step Functions
log "Creating CloudWatch Log Group for Step Functions..."
aws logs create-log-group \
    --log-group-name /aws/stepfunctions/${PROJECT_NAME}-order-processing-${RANDOM_SUFFIX} 2>/dev/null || true

aws logs put-retention-policy \
    --log-group-name /aws/stepfunctions/${PROJECT_NAME}-order-processing-${RANDOM_SUFFIX} \
    --retention-in-days 14

log_success "CloudWatch Log Group created for Step Functions"

# Step 6: Create Step Functions state machine
log "Creating Step Functions state machine..."
cat > order-processing-workflow.json << EOF
{
  "Comment": "Order Processing Workflow",
  "StartAt": "ProcessPayment",
  "States": {
    "ProcessPayment": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PAYMENT_SERVICE_ARN}",
        "Payload.$": "$"
      },
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 6,
          "BackoffRate": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "PaymentFailed",
          "ResultPath": "$.error"
        }
      ],
      "Next": "CheckPaymentStatus"
    },
    "CheckPaymentStatus": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.Payload.body",
          "StringMatches": "*SUCCESS*",
          "Next": "ReserveInventory"
        }
      ],
      "Default": "PaymentFailed"
    },
    "ReserveInventory": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${INVENTORY_SERVICE_ARN}",
        "Payload.$": "$"
      },
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "InventoryFailed",
          "ResultPath": "$.error"
        }
      ],
      "Next": "CheckInventoryStatus"
    },
    "CheckInventoryStatus": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.Payload.body",
          "StringMatches": "*RESERVED*",
          "Next": "SendSuccessNotification"
        }
      ],
      "Default": "InventoryFailed"
    },
    "SendSuccessNotification": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${NOTIFICATION_SERVICE_ARN}",
        "Payload": {
          "message": "Order processed successfully",
          "orderId.$": "$.detail.orderId",
          "status": "COMPLETED"
        }
      },
      "End": true
    },
    "PaymentFailed": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${NOTIFICATION_SERVICE_ARN}",
        "Payload": {
          "message": "Payment failed",
          "orderId.$": "$.detail.orderId",
          "status": "PAYMENT_FAILED"
        }
      },
      "End": true
    },
    "InventoryFailed": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${NOTIFICATION_SERVICE_ARN}",
        "Payload": {
          "message": "Inventory unavailable",
          "orderId.$": "$.detail.orderId",
          "status": "INVENTORY_FAILED"
        }
      },
      "End": true
    }
  }
}
EOF

export STATE_MACHINE_ARN=$(aws stepfunctions create-state-machine \
    --name ${PROJECT_NAME}-order-processing-${RANDOM_SUFFIX} \
    --definition file://order-processing-workflow.json \
    --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/${STEPFUNCTIONS_ROLE_NAME} \
    --type STANDARD \
    --logging-configuration level=ALL,includeExecutionData=true,destinations=[{cloudWatchLogsLogGroup=arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/stepfunctions/${PROJECT_NAME}-order-processing-${RANDOM_SUFFIX}}] \
    --query 'stateMachineArn' --output text)

log_success "Step Functions state machine created"

# Step 7: Create EventBridge rules
log "Creating EventBridge rules..."

# Create EventBridge rule for order created events
aws events put-rule \
    --name ${PROJECT_NAME}-order-created-rule-${RANDOM_SUFFIX} \
    --event-pattern '{
        "source": ["order.service"],
        "detail-type": ["Order Created"]
    }' \
    --state ENABLED \
    --event-bus-name ${EVENTBUS_NAME} > /dev/null

# Add Step Functions as target for the rule
aws events put-targets \
    --rule ${PROJECT_NAME}-order-created-rule-${RANDOM_SUFFIX} \
    --event-bus-name ${EVENTBUS_NAME} \
    --targets "Id"="1","Arn"="${STATE_MACHINE_ARN}","RoleArn"="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${STEPFUNCTIONS_ROLE_NAME}" > /dev/null

# Create EventBridge rule for payment events
aws events put-rule \
    --name ${PROJECT_NAME}-payment-events-rule-${RANDOM_SUFFIX} \
    --event-pattern '{
        "source": ["payment.service"],
        "detail-type": ["Payment Processed", "Payment Failed"]
    }' \
    --state ENABLED \
    --event-bus-name ${EVENTBUS_NAME} > /dev/null

# Add Lambda as target for payment events
aws events put-targets \
    --rule ${PROJECT_NAME}-payment-events-rule-${RANDOM_SUFFIX} \
    --event-bus-name ${EVENTBUS_NAME} \
    --targets "Id"="1","Arn"="${NOTIFICATION_SERVICE_ARN}" > /dev/null

# Grant EventBridge permission to invoke Lambda
aws lambda add-permission \
    --function-name ${NOTIFICATION_SERVICE_ARN} \
    --statement-id ${PROJECT_NAME}-eventbridge-permission \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBUS_NAME}/${PROJECT_NAME}-payment-events-rule-${RANDOM_SUFFIX} > /dev/null

log_success "EventBridge rules and targets configured"

# Step 8: Create CloudWatch dashboard
log "Creating CloudWatch dashboard..."
cat > dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Invocations", "FunctionName", "${PROJECT_NAME}-order-service-${RANDOM_SUFFIX}"],
                    ["AWS/Lambda", "Invocations", "FunctionName", "${PROJECT_NAME}-payment-service-${RANDOM_SUFFIX}"],
                    ["AWS/Lambda", "Invocations", "FunctionName", "${PROJECT_NAME}-inventory-service-${RANDOM_SUFFIX}"],
                    ["AWS/Lambda", "Invocations", "FunctionName", "${PROJECT_NAME}-notification-service-${RANDOM_SUFFIX}"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Lambda Invocations"
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", "${STATE_MACHINE_ARN}"],
                    ["AWS/States", "ExecutionsFailed", "StateMachineArn", "${STATE_MACHINE_ARN}"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Step Functions Executions"
            }
        }
    ]
}
EOF

aws cloudwatch put-dashboard \
    --dashboard-name ${PROJECT_NAME}-microservices-dashboard-${RANDOM_SUFFIX} \
    --dashboard-body file://dashboard-config.json > /dev/null

log_success "CloudWatch dashboard created"

# Update environment file with all ARNs
cat >> .deployment_env << EOF
export ORDER_SERVICE_ARN="${ORDER_SERVICE_ARN}"
export PAYMENT_SERVICE_ARN="${PAYMENT_SERVICE_ARN}"
export INVENTORY_SERVICE_ARN="${INVENTORY_SERVICE_ARN}"
export NOTIFICATION_SERVICE_ARN="${NOTIFICATION_SERVICE_ARN}"
export STATE_MACHINE_ARN="${STATE_MACHINE_ARN}"
export EVENTBUS_ARN="${EVENTBUS_ARN}"
EOF

# Cleanup temporary directory
cd - > /dev/null
rm -rf "$TEMP_DIR"

# Post-deployment validation
if [ "$SKIP_TESTS" = false ]; then
    log "Running post-deployment validation tests..."
    
    # Test the order processing workflow
    TEST_ORDER=$(cat << EOF
{
    "customerId": "customer-123",
    "items": [
        {"productId": "prod-001", "quantity": 2, "price": 29.99},
        {"productId": "prod-002", "quantity": 1, "price": 49.99}
    ],
    "totalAmount": 109.97
}
EOF
)
    
    # Invoke the Order Service directly
    log "Testing Order Service..."
    aws lambda invoke \
        --function-name ${PROJECT_NAME}-order-service-${RANDOM_SUFFIX} \
        --payload "${TEST_ORDER}" \
        test-response.json > /dev/null
    
    if [ -f test-response.json ]; then
        if grep -q "PENDING" test-response.json; then
            log_success "Order Service test passed"
        else
            log_warning "Order Service test may have failed - check test-response.json"
        fi
        rm -f test-response.json
    fi
    
    # Verify resources exist
    log "Verifying deployed resources..."
    
    # Check EventBridge bus
    if aws events describe-event-bus --name ${EVENTBUS_NAME} > /dev/null 2>&1; then
        log_success "EventBridge bus verified"
    else
        log_warning "EventBridge bus verification failed"
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name ${DYNAMODB_TABLE_NAME} > /dev/null 2>&1; then
        log_success "DynamoDB table verified"
    else
        log_warning "DynamoDB table verification failed"
    fi
    
    # Check Step Functions state machine
    if aws stepfunctions describe-state-machine --state-machine-arn ${STATE_MACHINE_ARN} > /dev/null 2>&1; then
        log_success "Step Functions state machine verified"
    else
        log_warning "Step Functions state machine verification failed"
    fi
fi

log_success "Deployment completed successfully!"
echo ""
echo "=============================================="
echo "DEPLOYMENT SUMMARY"
echo "=============================================="
echo "AWS Region: ${AWS_REGION}"
echo "Project Name: ${PROJECT_NAME}"
echo "Random Suffix: ${RANDOM_SUFFIX}"
echo ""
echo "Created Resources:"
echo "  • EventBridge Bus: ${EVENTBUS_NAME}"
echo "  • DynamoDB Table: ${DYNAMODB_TABLE_NAME}"
echo "  • Lambda Functions: 4 microservices"
echo "  • Step Functions State Machine: ${PROJECT_NAME}-order-processing-${RANDOM_SUFFIX}"
echo "  • IAM Roles: 2 execution roles"
echo "  • EventBridge Rules: 2 routing rules"
echo "  • CloudWatch Dashboard: ${PROJECT_NAME}-microservices-dashboard-${RANDOM_SUFFIX}"
echo ""
echo "Console URLs:"
echo "  • Step Functions: https://${AWS_REGION}.console.aws.amazon.com/states/home?region=${AWS_REGION}#/statemachines/view/${STATE_MACHINE_ARN}"
echo "  • EventBridge: https://${AWS_REGION}.console.aws.amazon.com/events/home?region=${AWS_REGION}#/eventbus/${EVENTBUS_NAME}"
echo "  • DynamoDB: https://${AWS_REGION}.console.aws.amazon.com/dynamodb/home?region=${AWS_REGION}#tables:selected=${DYNAMODB_TABLE_NAME}"
echo "  • CloudWatch Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${PROJECT_NAME}-microservices-dashboard-${RANDOM_SUFFIX}"
echo ""
echo "Environment variables saved to: .deployment_env"
echo "Use 'source .deployment_env' to load these variables"
echo ""
echo "To clean up resources, run: ./destroy.sh"
echo "=============================================="