#!/bin/bash

# Deployment script for Saga Patterns with Step Functions for Distributed Transactions
# This script deploys the complete infrastructure for the saga pattern implementation

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    warning "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    log "$description"
    
    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY-RUN: $cmd"
        return 0
    fi
    
    if ! eval "$cmd"; then
        error "Failed to execute: $cmd"
        return 1
    fi
}

# Function to wait for resource creation
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local max_attempts=30
    local attempt=0
    
    log "Waiting for $resource_type: $resource_name"
    
    while [ $attempt -lt $max_attempts ]; do
        case $resource_type in
            "dynamodb-table")
                if aws dynamodb describe-table --table-name "$resource_name" --query 'Table.TableStatus' --output text 2>/dev/null | grep -q "ACTIVE"; then
                    success "$resource_type $resource_name is ready"
                    return 0
                fi
                ;;
            "lambda-function")
                if aws lambda get-function --function-name "$resource_name" --query 'Configuration.State' --output text 2>/dev/null | grep -q "Active"; then
                    success "$resource_type $resource_name is ready"
                    return 0
                fi
                ;;
            "iam-role")
                if aws iam get-role --role-name "$resource_name" >/dev/null 2>&1; then
                    success "$resource_type $resource_name is ready"
                    return 0
                fi
                ;;
        esac
        
        attempt=$((attempt + 1))
        sleep 10
    done
    
    error "Timeout waiting for $resource_type: $resource_name"
    return 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if required tools are available
    local required_tools=("zip" "python3" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    # Check AWS permissions
    log "Validating AWS permissions..."
    local required_permissions=(
        "dynamodb:CreateTable"
        "lambda:CreateFunction"
        "iam:CreateRole"
        "states:CreateStateMachine"
        "apigateway:POST"
        "sns:CreateTopic"
    )
    
    # Note: In a production environment, you would implement more thorough permission checks
    # For now, we'll rely on the AWS CLI commands to fail if permissions are insufficient
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    if [ "$DRY_RUN" = "false" ]; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    else
        RANDOM_SUFFIX="dryrun"
    fi
    
    # Set resource names
    export SAGA_STATE_MACHINE_NAME="saga-orchestrator-${RANDOM_SUFFIX}"
    export ORDER_TABLE_NAME="saga-orders-${RANDOM_SUFFIX}"
    export INVENTORY_TABLE_NAME="saga-inventory-${RANDOM_SUFFIX}"
    export PAYMENT_TABLE_NAME="saga-payments-${RANDOM_SUFFIX}"
    export SAGA_TOPIC_NAME="saga-notifications-${RANDOM_SUFFIX}"
    
    # Save environment variables for cleanup script
    cat > "$SCRIPT_DIR/.env" << EOF
# Environment variables for Saga Pattern deployment
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
SAGA_STATE_MACHINE_NAME=${SAGA_STATE_MACHINE_NAME}
ORDER_TABLE_NAME=${ORDER_TABLE_NAME}
INVENTORY_TABLE_NAME=${INVENTORY_TABLE_NAME}
PAYMENT_TABLE_NAME=${PAYMENT_TABLE_NAME}
SAGA_TOPIC_NAME=${SAGA_TOPIC_NAME}
EOF
    
    success "Environment variables configured"
    log "Deployment suffix: $RANDOM_SUFFIX"
}

# Function to create DynamoDB tables
create_dynamodb_tables() {
    log "Creating DynamoDB tables..."
    
    # Create Orders table
    execute_cmd "aws dynamodb create-table \
        --table-name $ORDER_TABLE_NAME \
        --attribute-definitions AttributeName=orderId,AttributeType=S \
        --key-schema AttributeName=orderId,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Environment,Value=Demo Key=Component,Value=SagaPattern" \
        "Creating Orders table"
    
    # Create Inventory table
    execute_cmd "aws dynamodb create-table \
        --table-name $INVENTORY_TABLE_NAME \
        --attribute-definitions AttributeName=productId,AttributeType=S \
        --key-schema AttributeName=productId,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Environment,Value=Demo Key=Component,Value=SagaPattern" \
        "Creating Inventory table"
    
    # Create Payment table
    execute_cmd "aws dynamodb create-table \
        --table-name $PAYMENT_TABLE_NAME \
        --attribute-definitions AttributeName=paymentId,AttributeType=S \
        --key-schema AttributeName=paymentId,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Environment,Value=Demo Key=Component,Value=SagaPattern" \
        "Creating Payment table"
    
    if [ "$DRY_RUN" = "false" ]; then
        # Wait for tables to be created
        wait_for_resource "dynamodb-table" "$ORDER_TABLE_NAME"
        wait_for_resource "dynamodb-table" "$INVENTORY_TABLE_NAME"
        wait_for_resource "dynamodb-table" "$PAYMENT_TABLE_NAME"
    fi
    
    success "DynamoDB tables created"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic..."
    
    if [ "$DRY_RUN" = "false" ]; then
        SAGA_TOPIC_ARN=$(aws sns create-topic --name $SAGA_TOPIC_NAME --output text --query TopicArn)
        echo "SAGA_TOPIC_ARN=${SAGA_TOPIC_ARN}" >> "$SCRIPT_DIR/.env"
    else
        SAGA_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SAGA_TOPIC_NAME}"
    fi
    
    success "SNS topic created: $SAGA_TOPIC_ARN"
}

# Function to populate sample data
populate_sample_data() {
    log "Populating sample inventory data..."
    
    execute_cmd "aws dynamodb put-item \
        --table-name $INVENTORY_TABLE_NAME \
        --item '{
            \"productId\": {\"S\": \"laptop-001\"},
            \"quantity\": {\"N\": \"10\"},
            \"price\": {\"N\": \"999.99\"},
            \"reserved\": {\"N\": \"0\"}
        }'" \
        "Adding laptop inventory"
    
    execute_cmd "aws dynamodb put-item \
        --table-name $INVENTORY_TABLE_NAME \
        --item '{
            \"productId\": {\"S\": \"phone-002\"},
            \"quantity\": {\"N\": \"25\"},
            \"price\": {\"N\": \"599.99\"},
            \"reserved\": {\"N\": \"0\"}
        }'" \
        "Adding phone inventory"
    
    success "Sample data populated"
}

# Function to create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create trust policy for Step Functions
    cat > "$TEMP_DIR/saga-trust-policy.json" << 'EOF'
{
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
}
EOF
    
    # Create Step Functions IAM role
    if [ "$DRY_RUN" = "false" ]; then
        SAGA_ROLE_ARN=$(aws iam create-role \
            --role-name saga-orchestrator-role-${RANDOM_SUFFIX} \
            --assume-role-policy-document file://$TEMP_DIR/saga-trust-policy.json \
            --output text --query Role.Arn)
        echo "SAGA_ROLE_ARN=${SAGA_ROLE_ARN}" >> "$SCRIPT_DIR/.env"
    else
        SAGA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/saga-orchestrator-role-${RANDOM_SUFFIX}"
    fi
    
    # Attach Lambda execution policy
    execute_cmd "aws iam attach-role-policy \
        --role-name saga-orchestrator-role-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaRole" \
        "Attaching Lambda execution policy to Step Functions role"
    
    # Create custom policy for DynamoDB and SNS access
    cat > "$TEMP_DIR/saga-permissions-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:GetItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ],
      "Resource": [
        "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${ORDER_TABLE_NAME}",
        "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${INVENTORY_TABLE_NAME}",
        "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${PAYMENT_TABLE_NAME}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "${SAGA_TOPIC_ARN:-arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SAGA_TOPIC_NAME}}"
    }
  ]
}
EOF
    
    execute_cmd "aws iam put-role-policy \
        --role-name saga-orchestrator-role-${RANDOM_SUFFIX} \
        --policy-name saga-permissions \
        --policy-document file://$TEMP_DIR/saga-permissions-policy.json" \
        "Adding custom permissions to Step Functions role"
    
    # Create Lambda execution role
    cat > "$TEMP_DIR/lambda-trust-policy.json" << 'EOF'
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
    
    if [ "$DRY_RUN" = "false" ]; then
        LAMBDA_ROLE_ARN=$(aws iam create-role \
            --role-name saga-lambda-role-${RANDOM_SUFFIX} \
            --assume-role-policy-document file://$TEMP_DIR/lambda-trust-policy.json \
            --output text --query Role.Arn)
        echo "LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> "$SCRIPT_DIR/.env"
    else
        LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/saga-lambda-role-${RANDOM_SUFFIX}"
    fi
    
    # Attach basic Lambda execution policy
    execute_cmd "aws iam attach-role-policy \
        --role-name saga-lambda-role-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "Attaching basic execution policy to Lambda role"
    
    # Attach DynamoDB and SNS permissions to Lambda role
    execute_cmd "aws iam put-role-policy \
        --role-name saga-lambda-role-${RANDOM_SUFFIX} \
        --policy-name saga-lambda-permissions \
        --policy-document file://$TEMP_DIR/saga-permissions-policy.json" \
        "Adding custom permissions to Lambda role"
    
    if [ "$DRY_RUN" = "false" ]; then
        wait_for_resource "iam-role" "saga-orchestrator-role-${RANDOM_SUFFIX}"
        wait_for_resource "iam-role" "saga-lambda-role-${RANDOM_SUFFIX}"
    fi
    
    success "IAM roles created"
}

# Function to create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create Lambda function code files
    create_lambda_code_files
    
    # Package and deploy each function
    local functions=(
        "order-service:saga-order-service-${RANDOM_SUFFIX}"
        "inventory-service:saga-inventory-service-${RANDOM_SUFFIX}"
        "payment-service:saga-payment-service-${RANDOM_SUFFIX}"
        "notification-service:saga-notification-service-${RANDOM_SUFFIX}"
        "cancel-order:saga-cancel-order-${RANDOM_SUFFIX}"
        "revert-inventory:saga-revert-inventory-${RANDOM_SUFFIX}"
        "refund-payment:saga-refund-payment-${RANDOM_SUFFIX}"
    )
    
    for func in "${functions[@]}"; do
        IFS=":" read -r code_file function_name <<< "$func"
        
        # Package function
        cd "$TEMP_DIR"
        zip "${code_file}.zip" "${code_file}.py"
        
        # Deploy function
        if [ "$DRY_RUN" = "false" ]; then
            FUNCTION_ARN=$(aws lambda create-function \
                --function-name "$function_name" \
                --runtime python3.9 \
                --role "$LAMBDA_ROLE_ARN" \
                --handler "${code_file}.lambda_handler" \
                --zip-file "fileb://${code_file}.zip" \
                --timeout 30 \
                --tags Environment=Demo,Component=SagaPattern \
                --output text --query FunctionArn)
            
            echo "${function_name//-/_}_ARN=${FUNCTION_ARN}" >> "$SCRIPT_DIR/.env"
            
            wait_for_resource "lambda-function" "$function_name"
        else
            log "DRY-RUN: Would create Lambda function $function_name"
        fi
    done
    
    success "Lambda functions created"
}

# Function to create Lambda code files
create_lambda_code_files() {
    log "Creating Lambda function code files..."
    
    # Order Service
    cat > "$TEMP_DIR/order-service.py" << 'EOF'
import json
import boto3
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        order_id = str(uuid.uuid4())
        order_data = {
            'orderId': order_id,
            'customerId': event['customerId'],
            'productId': event['productId'],
            'quantity': event['quantity'],
            'status': 'PENDING',
            'timestamp': datetime.utcnow().isoformat()
        }
        
        table.put_item(Item=order_data)
        
        return {
            'statusCode': 200,
            'status': 'ORDER_PLACED',
            'orderId': order_id,
            'message': 'Order placed successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'ORDER_FAILED',
            'error': str(e)
        }
EOF

    # Inventory Service
    cat > "$TEMP_DIR/inventory-service.py" << 'EOF'
import json
import boto3
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        product_id = event['productId']
        quantity_needed = int(event['quantity'])
        
        # Get current inventory
        response = table.get_item(Key={'productId': product_id})
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'status': 'INVENTORY_NOT_FOUND',
                'message': 'Product not found in inventory'
            }
        
        item = response['Item']
        available_quantity = int(item['quantity']) - int(item.get('reserved', 0))
        
        if available_quantity < quantity_needed:
            return {
                'statusCode': 400,
                'status': 'INSUFFICIENT_INVENTORY',
                'message': f'Only {available_quantity} items available'
            }
        
        # Reserve inventory
        table.update_item(
            Key={'productId': product_id},
            UpdateExpression='SET reserved = reserved + :qty',
            ExpressionAttributeValues={':qty': quantity_needed}
        )
        
        return {
            'statusCode': 200,
            'status': 'INVENTORY_RESERVED',
            'productId': product_id,
            'quantity': quantity_needed,
            'message': 'Inventory reserved successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'INVENTORY_FAILED',
            'error': str(e)
        }
EOF

    # Payment Service
    cat > "$TEMP_DIR/payment-service.py" << 'EOF'
import json
import boto3
import uuid
import random
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        # Simulate payment processing with 20% failure rate
        if random.random() < 0.2:
            return {
                'statusCode': 400,
                'status': 'PAYMENT_FAILED',
                'message': 'Payment processing failed'
            }
        
        payment_id = str(uuid.uuid4())
        payment_data = {
            'paymentId': payment_id,
            'orderId': event['orderId'],
            'customerId': event['customerId'],
            'amount': event['amount'],
            'status': 'COMPLETED',
            'timestamp': datetime.utcnow().isoformat()
        }
        
        table.put_item(Item=payment_data)
        
        return {
            'statusCode': 200,
            'status': 'PAYMENT_COMPLETED',
            'paymentId': payment_id,
            'amount': event['amount'],
            'message': 'Payment processed successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'PAYMENT_FAILED',
            'error': str(e)
        }
EOF

    # Notification Service
    cat > "$TEMP_DIR/notification-service.py" << 'EOF'
import json
import boto3

sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        topic_arn = event['topicArn']
        message = event['message']
        subject = event.get('subject', 'Order Notification')
        
        response = sns.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=json.dumps(message, indent=2)
        )
        
        return {
            'statusCode': 200,
            'status': 'NOTIFICATION_SENT',
            'messageId': response['MessageId'],
            'message': 'Notification sent successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'NOTIFICATION_FAILED',
            'error': str(e)
        }
EOF

    # Cancel Order Compensation
    cat > "$TEMP_DIR/cancel-order.py" << 'EOF'
import json
import boto3

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        order_id = event['orderId']
        
        # Update order status to cancelled
        table.update_item(
            Key={'orderId': order_id},
            UpdateExpression='SET #status = :status',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={':status': 'CANCELLED'}
        )
        
        return {
            'statusCode': 200,
            'status': 'ORDER_CANCELLED',
            'orderId': order_id,
            'message': 'Order cancelled successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'CANCELLATION_FAILED',
            'error': str(e)
        }
EOF

    # Revert Inventory Compensation
    cat > "$TEMP_DIR/revert-inventory.py" << 'EOF'
import json
import boto3

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        product_id = event['productId']
        quantity = int(event['quantity'])
        
        # Release reserved inventory
        table.update_item(
            Key={'productId': product_id},
            UpdateExpression='SET reserved = reserved - :qty',
            ExpressionAttributeValues={':qty': quantity}
        )
        
        return {
            'statusCode': 200,
            'status': 'INVENTORY_REVERTED',
            'productId': product_id,
            'quantity': quantity,
            'message': 'Inventory reservation reverted'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'REVERT_FAILED',
            'error': str(e)
        }
EOF

    # Refund Payment Compensation
    cat > "$TEMP_DIR/refund-payment.py" << 'EOF'
import json
import boto3
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table_name = event['tableName']
        table = dynamodb.Table(table_name)
        
        # Create refund record
        refund_id = str(uuid.uuid4())
        refund_data = {
            'paymentId': refund_id,
            'originalPaymentId': event['paymentId'],
            'orderId': event['orderId'],
            'customerId': event['customerId'],
            'amount': event['amount'],
            'status': 'REFUNDED',
            'type': 'REFUND',
            'timestamp': datetime.utcnow().isoformat()
        }
        
        table.put_item(Item=refund_data)
        
        return {
            'statusCode': 200,
            'status': 'PAYMENT_REFUNDED',
            'refundId': refund_id,
            'amount': event['amount'],
            'message': 'Payment refunded successfully'
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'status': 'REFUND_FAILED',
            'error': str(e)
        }
EOF
}

# Function to create Step Functions state machine
create_step_functions() {
    log "Creating Step Functions state machine..."
    
    # Load environment variables for ARNs
    source "$SCRIPT_DIR/.env"
    
    # Create state machine definition
    cat > "$TEMP_DIR/saga-state-machine.json" << EOF
{
  "Comment": "Saga Pattern Orchestrator for E-commerce Transactions",
  "StartAt": "PlaceOrder",
  "States": {
    "PlaceOrder": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${saga_order_service_ARN:-arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:saga-order-service-${RANDOM_SUFFIX}}",
        "Payload": {
          "tableName": "${ORDER_TABLE_NAME}",
          "customerId.$": "$.customerId",
          "productId.$": "$.productId",
          "quantity.$": "$.quantity"
        }
      },
      "ResultPath": "$.orderResult",
      "Next": "CheckOrderStatus",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "OrderFailed",
          "ResultPath": "$.error"
        }
      ]
    },
    "CheckOrderStatus": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.orderResult.Payload.status",
          "StringEquals": "ORDER_PLACED",
          "Next": "ReserveInventory"
        }
      ],
      "Default": "OrderFailed"
    },
    "ReserveInventory": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${saga_inventory_service_ARN:-arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:saga-inventory-service-${RANDOM_SUFFIX}}",
        "Payload": {
          "tableName": "${INVENTORY_TABLE_NAME}",
          "productId.$": "$.productId",
          "quantity.$": "$.quantity"
        }
      },
      "ResultPath": "$.inventoryResult",
      "Next": "CheckInventoryStatus",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "CancelOrder",
          "ResultPath": "$.error"
        }
      ]
    },
    "CheckInventoryStatus": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.inventoryResult.Payload.status",
          "StringEquals": "INVENTORY_RESERVED",
          "Next": "ProcessPayment"
        }
      ],
      "Default": "CancelOrder"
    },
    "ProcessPayment": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${saga_payment_service_ARN:-arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:saga-payment-service-${RANDOM_SUFFIX}}",
        "Payload": {
          "tableName": "${PAYMENT_TABLE_NAME}",
          "orderId.$": "$.orderResult.Payload.orderId",
          "customerId.$": "$.customerId",
          "amount.$": "$.amount"
        }
      },
      "ResultPath": "$.paymentResult",
      "Next": "CheckPaymentStatus",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "RevertInventory",
          "ResultPath": "$.error"
        }
      ]
    },
    "CheckPaymentStatus": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.paymentResult.Payload.status",
          "StringEquals": "PAYMENT_COMPLETED",
          "Next": "SendSuccessNotification"
        }
      ],
      "Default": "RevertInventory"
    },
    "SendSuccessNotification": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${saga_notification_service_ARN:-arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:saga-notification-service-${RANDOM_SUFFIX}}",
        "Payload": {
          "topicArn": "${SAGA_TOPIC_ARN}",
          "subject": "Order Completed Successfully",
          "message": {
            "orderId.$": "$.orderResult.Payload.orderId",
            "customerId.$": "$.customerId",
            "status": "SUCCESS",
            "details": "Your order has been processed successfully"
          }
        }
      },
      "ResultPath": "$.notificationResult",
      "Next": "Success"
    },
    "Success": {
      "Type": "Pass",
      "Result": {
        "status": "SUCCESS",
        "message": "Transaction completed successfully"
      },
      "End": true
    },
    "RevertInventory": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${saga_revert_inventory_ARN:-arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:saga-revert-inventory-${RANDOM_SUFFIX}}",
        "Payload": {
          "tableName": "${INVENTORY_TABLE_NAME}",
          "productId.$": "$.productId",
          "quantity.$": "$.quantity"
        }
      },
      "ResultPath": "$.revertResult",
      "Next": "CancelOrder",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "CompensationFailed",
          "ResultPath": "$.compensationError"
        }
      ]
    },
    "CancelOrder": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${saga_cancel_order_ARN:-arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:saga-cancel-order-${RANDOM_SUFFIX}}",
        "Payload": {
          "tableName": "${ORDER_TABLE_NAME}",
          "orderId.$": "$.orderResult.Payload.orderId"
        }
      },
      "ResultPath": "$.cancelResult",
      "Next": "RefundPayment",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "CompensationFailed",
          "ResultPath": "$.compensationError"
        }
      ]
    },
    "RefundPayment": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${saga_refund_payment_ARN:-arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:saga-refund-payment-${RANDOM_SUFFIX}}",
        "Payload": {
          "tableName": "${PAYMENT_TABLE_NAME}",
          "paymentId.$": "$.paymentResult.Payload.paymentId",
          "orderId.$": "$.orderResult.Payload.orderId",
          "customerId.$": "$.customerId",
          "amount.$": "$.amount"
        }
      },
      "ResultPath": "$.refundResult",
      "Next": "SendFailureNotification",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "CompensationFailed",
          "ResultPath": "$.compensationError"
        }
      ]
    },
    "SendFailureNotification": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${saga_notification_service_ARN:-arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:saga-notification-service-${RANDOM_SUFFIX}}",
        "Payload": {
          "topicArn": "${SAGA_TOPIC_ARN}",
          "subject": "Order Processing Failed",
          "message": {
            "orderId.$": "$.orderResult.Payload.orderId",
            "customerId.$": "$.customerId",
            "status": "FAILED",
            "details": "Your order could not be processed and has been cancelled"
          }
        }
      },
      "ResultPath": "$.notificationResult",
      "Next": "TransactionFailed"
    },
    "OrderFailed": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${saga_notification_service_ARN:-arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:saga-notification-service-${RANDOM_SUFFIX}}",
        "Payload": {
          "topicArn": "${SAGA_TOPIC_ARN}",
          "subject": "Order Creation Failed",
          "message": {
            "customerId.$": "$.customerId",
            "status": "FAILED",
            "details": "Order creation failed"
          }
        }
      },
      "ResultPath": "$.notificationResult",
      "Next": "TransactionFailed"
    },
    "TransactionFailed": {
      "Type": "Pass",
      "Result": {
        "status": "FAILED",
        "message": "Transaction failed and compensations completed"
      },
      "End": true
    },
    "CompensationFailed": {
      "Type": "Pass",
      "Result": {
        "status": "COMPENSATION_FAILED",
        "message": "Transaction failed and compensation actions also failed"
      },
      "End": true
    }
  }
}
EOF
    
    # Create CloudWatch log group
    execute_cmd "aws logs create-log-group \
        --log-group-name /aws/stepfunctions/saga-logs-${RANDOM_SUFFIX} \
        --tags Environment=Demo,Component=SagaPattern" \
        "Creating CloudWatch log group"
    
    # Create the Step Functions state machine
    if [ "$DRY_RUN" = "false" ]; then
        sleep 30  # Wait for IAM roles to propagate
        
        SAGA_STATE_MACHINE_ARN=$(aws stepfunctions create-state-machine \
            --name "$SAGA_STATE_MACHINE_NAME" \
            --definition file://$TEMP_DIR/saga-state-machine.json \
            --role-arn "$SAGA_ROLE_ARN" \
            --type STANDARD \
            --logging-configuration "level=ALL,includeExecutionData=true,destinations=[{cloudWatchLogsLogGroup=/aws/stepfunctions/saga-logs-${RANDOM_SUFFIX}}]" \
            --tags Key=Environment,Value=Demo,Key=Component,Value=SagaPattern \
            --output text --query stateMachineArn)
        
        echo "SAGA_STATE_MACHINE_ARN=${SAGA_STATE_MACHINE_ARN}" >> "$SCRIPT_DIR/.env"
    else
        SAGA_STATE_MACHINE_ARN="arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${SAGA_STATE_MACHINE_NAME}"
    fi
    
    success "Step Functions state machine created: $SAGA_STATE_MACHINE_ARN"
}

# Function to create API Gateway
create_api_gateway() {
    log "Creating API Gateway..."
    
    # Create REST API
    if [ "$DRY_RUN" = "false" ]; then
        API_ID=$(aws apigateway create-rest-api \
            --name "saga-api-${RANDOM_SUFFIX}" \
            --description "API for initiating saga transactions" \
            --output text --query id)
        echo "API_ID=${API_ID}" >> "$SCRIPT_DIR/.env"
    else
        API_ID="dry-run-api-id"
    fi
    
    # Get root resource ID
    if [ "$DRY_RUN" = "false" ]; then
        ROOT_RESOURCE_ID=$(aws apigateway get-resources \
            --rest-api-id "$API_ID" \
            --query 'items[0].id' \
            --output text)
    else
        ROOT_RESOURCE_ID="dry-run-root-resource-id"
    fi
    
    # Create orders resource
    if [ "$DRY_RUN" = "false" ]; then
        ORDERS_RESOURCE_ID=$(aws apigateway create-resource \
            --rest-api-id "$API_ID" \
            --parent-id "$ROOT_RESOURCE_ID" \
            --path-part orders \
            --output text --query id)
    else
        ORDERS_RESOURCE_ID="dry-run-orders-resource-id"
    fi
    
    # Create IAM role for API Gateway
    cat > "$TEMP_DIR/api-gateway-trust-policy.json" << 'EOF'
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
    
    if [ "$DRY_RUN" = "false" ]; then
        source "$SCRIPT_DIR/.env"
        API_GATEWAY_ROLE_ARN=$(aws iam create-role \
            --role-name "saga-api-gateway-role-${RANDOM_SUFFIX}" \
            --assume-role-policy-document file://$TEMP_DIR/api-gateway-trust-policy.json \
            --output text --query Role.Arn)
        echo "API_GATEWAY_ROLE_ARN=${API_GATEWAY_ROLE_ARN}" >> "$SCRIPT_DIR/.env"
    else
        API_GATEWAY_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/saga-api-gateway-role-${RANDOM_SUFFIX}"
    fi
    
    # Create policy for Step Functions access
    cat > "$TEMP_DIR/api-gateway-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "states:StartExecution"
      ],
      "Resource": "${SAGA_STATE_MACHINE_ARN}"
    }
  ]
}
EOF
    
    execute_cmd "aws iam put-role-policy \
        --role-name saga-api-gateway-role-${RANDOM_SUFFIX} \
        --policy-name StepFunctionsAccess \
        --policy-document file://$TEMP_DIR/api-gateway-policy.json" \
        "Adding Step Functions permissions to API Gateway role"
    
    if [ "$DRY_RUN" = "false" ]; then
        sleep 30  # Wait for role propagation
        
        # Create POST method for orders
        aws apigateway put-method \
            --rest-api-id "$API_ID" \
            --resource-id "$ORDERS_RESOURCE_ID" \
            --http-method POST \
            --authorization-type NONE
        
        # Set up Step Functions integration
        aws apigateway put-integration \
            --rest-api-id "$API_ID" \
            --resource-id "$ORDERS_RESOURCE_ID" \
            --http-method POST \
            --type AWS \
            --integration-http-method POST \
            --uri "arn:aws:apigateway:${AWS_REGION}:states:action/StartExecution" \
            --credentials "$API_GATEWAY_ROLE_ARN" \
            --request-templates '{"application/json": "{\"stateMachineArn\": \"'${SAGA_STATE_MACHINE_ARN}'\", \"input\": \"$util.escapeJavaScript($input.body)\"}"}'
        
        # Configure method responses
        aws apigateway put-method-response \
            --rest-api-id "$API_ID" \
            --resource-id "$ORDERS_RESOURCE_ID" \
            --http-method POST \
            --status-code 200 \
            --response-models '{"application/json": "Empty"}'
        
        aws apigateway put-integration-response \
            --rest-api-id "$API_ID" \
            --resource-id "$ORDERS_RESOURCE_ID" \
            --http-method POST \
            --status-code 200 \
            --response-templates '{"application/json": "{\"executionArn\": \"$input.path(\"$.executionArn\")\", \"startDate\": \"$input.path(\"$.startDate\")\"}"}'
        
        # Deploy API
        aws apigateway create-deployment \
            --rest-api-id "$API_ID" \
            --stage-name prod
        
        API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
        echo "API_ENDPOINT=${API_ENDPOINT}" >> "$SCRIPT_DIR/.env"
    else
        API_ENDPOINT="https://dry-run-api-id.execute-api.${AWS_REGION}.amazonaws.com/prod"
    fi
    
    success "API Gateway created: $API_ENDPOINT"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Region: $AWS_REGION"
    echo "Account: $AWS_ACCOUNT_ID"
    echo "Deployment Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Created Resources:"
    echo "- DynamoDB Tables: $ORDER_TABLE_NAME, $INVENTORY_TABLE_NAME, $PAYMENT_TABLE_NAME"
    echo "- SNS Topic: $SAGA_TOPIC_NAME"
    echo "- Step Functions State Machine: $SAGA_STATE_MACHINE_NAME"
    echo "- Lambda Functions: 7 functions created"
    echo "- API Gateway: ${API_ENDPOINT:-Not created}"
    echo ""
    echo "Configuration saved to: $SCRIPT_DIR/.env"
    echo ""
    echo "Next Steps:"
    echo "1. Test the API endpoint:"
    echo "   curl -X POST ${API_ENDPOINT}/orders \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"customerId\": \"customer-123\", \"productId\": \"laptop-001\", \"quantity\": 2, \"amount\": 1999.98}'"
    echo ""
    echo "2. Monitor Step Functions execution in AWS Console"
    echo "3. Check DynamoDB tables for transaction data"
    echo "4. Run destroy.sh to clean up resources when done"
}

# Main deployment function
main() {
    log "Starting Saga Pattern deployment..."
    
    check_prerequisites
    setup_environment
    create_dynamodb_tables
    create_sns_topic
    populate_sample_data
    create_iam_roles
    create_lambda_functions
    create_step_functions
    create_api_gateway
    
    success "Deployment completed successfully!"
    display_summary
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run    Show what would be deployed without creating resources"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"