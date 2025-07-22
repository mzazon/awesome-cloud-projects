#!/bin/bash

# AWS Distributed Transaction Processing with SQS - Deployment Script
# This script deploys the complete distributed transaction processing solution
# including DynamoDB tables, SQS queues, Lambda functions, and API Gateway

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: $1"
    else
        log "Executing: $1"
        eval "$1"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required tools
    for tool in jq curl zip; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # AWS region and account setup
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, using default: $AWS_REGION"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    if [[ "$DRY_RUN" == "true" ]]; then
        RANDOM_SUFFIX="dry001"
    else
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "rnd$(date +%s | tail -c 4)")
    fi
    
    # Stack configuration
    export STACK_NAME="distributed-tx-${RANDOM_SUFFIX}"
    export SAGA_STATE_TABLE="${STACK_NAME}-saga-state"
    export ORDER_TABLE="${STACK_NAME}-orders"
    export PAYMENT_TABLE="${STACK_NAME}-payments"
    export INVENTORY_TABLE="${STACK_NAME}-inventory"
    
    # Create temporary directory for Lambda code
    export TEMP_DIR=$(mktemp -d)
    
    log "Stack name: $STACK_NAME"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "Temp directory: $TEMP_DIR"
    
    success "Environment setup completed"
}

# Function to create IAM role for Lambda functions
create_iam_role() {
    log "Creating IAM role for Lambda functions..."
    
    # Create IAM role
    execute_cmd "aws iam create-role \
        --role-name '${STACK_NAME}-lambda-role' \
        --assume-role-policy-document '{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Principal\": {
                        \"Service\": \"lambda.amazonaws.com\"
                    },
                    \"Action\": \"sts:AssumeRole\"
                }
            ]
        }'"
    
    # Attach necessary policies
    execute_cmd "aws iam attach-role-policy \
        --role-name '${STACK_NAME}-lambda-role' \
        --policy-arn 'arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole'"
    
    execute_cmd "aws iam attach-role-policy \
        --role-name '${STACK_NAME}-lambda-role' \
        --policy-arn 'arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess'"
    
    execute_cmd "aws iam attach-role-policy \
        --role-name '${STACK_NAME}-lambda-role' \
        --policy-arn 'arn:aws:iam::aws:policy/AmazonSQSFullAccess'"
    
    # Wait for role to be available
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep 10
    fi
    
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${STACK_NAME}-lambda-role"
    
    success "IAM role created: $LAMBDA_ROLE_ARN"
}

# Function to create DynamoDB tables
create_dynamodb_tables() {
    log "Creating DynamoDB tables..."
    
    # Create saga state table
    execute_cmd "aws dynamodb create-table \
        --table-name '${SAGA_STATE_TABLE}' \
        --attribute-definitions \
            AttributeName=TransactionId,AttributeType=S \
        --key-schema \
            AttributeName=TransactionId,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
        --tags Key=StackName,Value='${STACK_NAME}' Key=Purpose,Value='SagaState'"
    
    # Create orders table
    execute_cmd "aws dynamodb create-table \
        --table-name '${ORDER_TABLE}' \
        --attribute-definitions \
            AttributeName=OrderId,AttributeType=S \
        --key-schema \
            AttributeName=OrderId,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=StackName,Value='${STACK_NAME}' Key=Purpose,Value='Orders'"
    
    # Create payments table
    execute_cmd "aws dynamodb create-table \
        --table-name '${PAYMENT_TABLE}' \
        --attribute-definitions \
            AttributeName=PaymentId,AttributeType=S \
        --key-schema \
            AttributeName=PaymentId,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=StackName,Value='${STACK_NAME}' Key=Purpose,Value='Payments'"
    
    # Create inventory table
    execute_cmd "aws dynamodb create-table \
        --table-name '${INVENTORY_TABLE}' \
        --attribute-definitions \
            AttributeName=ProductId,AttributeType=S \
        --key-schema \
            AttributeName=ProductId,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=StackName,Value='${STACK_NAME}' Key=Purpose,Value='Inventory'"
    
    # Wait for tables to be created
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for DynamoDB tables to be created..."
        aws dynamodb wait table-exists --table-name "${SAGA_STATE_TABLE}"
        aws dynamodb wait table-exists --table-name "${ORDER_TABLE}"
        aws dynamodb wait table-exists --table-name "${PAYMENT_TABLE}"
        aws dynamodb wait table-exists --table-name "${INVENTORY_TABLE}"
    fi
    
    success "DynamoDB tables created successfully"
}

# Function to create SQS queues
create_sqs_queues() {
    log "Creating SQS FIFO queues..."
    
    # Create order processing queue
    execute_cmd "aws sqs create-queue \
        --queue-name '${STACK_NAME}-order-processing.fifo' \
        --attributes '{
            \"FifoQueue\": \"true\",
            \"ContentBasedDeduplication\": \"true\",
            \"MessageRetentionPeriod\": \"1209600\",
            \"VisibilityTimeoutSeconds\": \"300\"
        }' \
        --tags StackName='${STACK_NAME}',Purpose='OrderProcessing'"
    
    # Create payment processing queue
    execute_cmd "aws sqs create-queue \
        --queue-name '${STACK_NAME}-payment-processing.fifo' \
        --attributes '{
            \"FifoQueue\": \"true\",
            \"ContentBasedDeduplication\": \"true\",
            \"MessageRetentionPeriod\": \"1209600\",
            \"VisibilityTimeoutSeconds\": \"300\"
        }' \
        --tags StackName='${STACK_NAME}',Purpose='PaymentProcessing'"
    
    # Create inventory update queue
    execute_cmd "aws sqs create-queue \
        --queue-name '${STACK_NAME}-inventory-update.fifo' \
        --attributes '{
            \"FifoQueue\": \"true\",
            \"ContentBasedDeduplication\": \"true\",
            \"MessageRetentionPeriod\": \"1209600\",
            \"VisibilityTimeoutSeconds\": \"300\"
        }' \
        --tags StackName='${STACK_NAME}',Purpose='InventoryUpdate'"
    
    # Create compensation queue
    execute_cmd "aws sqs create-queue \
        --queue-name '${STACK_NAME}-compensation.fifo' \
        --attributes '{
            \"FifoQueue\": \"true\",
            \"ContentBasedDeduplication\": \"true\",
            \"MessageRetentionPeriod\": \"1209600\",
            \"VisibilityTimeoutSeconds\": \"300\"
        }' \
        --tags StackName='${STACK_NAME}',Purpose='Compensation'"
    
    # Create dead letter queue
    execute_cmd "aws sqs create-queue \
        --queue-name '${STACK_NAME}-dlq.fifo' \
        --attributes '{
            \"FifoQueue\": \"true\",
            \"ContentBasedDeduplication\": \"true\",
            \"MessageRetentionPeriod\": \"1209600\"
        }' \
        --tags StackName='${STACK_NAME}',Purpose='DeadLetter'"
    
    # Get queue URLs
    if [[ "$DRY_RUN" == "false" ]]; then
        export ORDER_QUEUE_URL=$(aws sqs get-queue-url \
            --queue-name "${STACK_NAME}-order-processing.fifo" \
            --query QueueUrl --output text)
        
        export PAYMENT_QUEUE_URL=$(aws sqs get-queue-url \
            --queue-name "${STACK_NAME}-payment-processing.fifo" \
            --query QueueUrl --output text)
        
        export INVENTORY_QUEUE_URL=$(aws sqs get-queue-url \
            --queue-name "${STACK_NAME}-inventory-update.fifo" \
            --query QueueUrl --output text)
        
        export COMPENSATION_QUEUE_URL=$(aws sqs get-queue-url \
            --queue-name "${STACK_NAME}-compensation.fifo" \
            --query QueueUrl --output text)
        
        export DLQ_URL=$(aws sqs get-queue-url \
            --queue-name "${STACK_NAME}-dlq.fifo" \
            --query QueueUrl --output text)
    else
        # Mock URLs for dry run
        export ORDER_QUEUE_URL="https://sqs.${AWS_REGION}.amazonaws.com/${AWS_ACCOUNT_ID}/${STACK_NAME}-order-processing.fifo"
        export PAYMENT_QUEUE_URL="https://sqs.${AWS_REGION}.amazonaws.com/${AWS_ACCOUNT_ID}/${STACK_NAME}-payment-processing.fifo"
        export INVENTORY_QUEUE_URL="https://sqs.${AWS_REGION}.amazonaws.com/${AWS_ACCOUNT_ID}/${STACK_NAME}-inventory-update.fifo"
        export COMPENSATION_QUEUE_URL="https://sqs.${AWS_REGION}.amazonaws.com/${AWS_ACCOUNT_ID}/${STACK_NAME}-compensation.fifo"
        export DLQ_URL="https://sqs.${AWS_REGION}.amazonaws.com/${AWS_ACCOUNT_ID}/${STACK_NAME}-dlq.fifo"
    fi
    
    success "SQS queues created successfully"
}

# Function to create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create orchestrator function
    create_orchestrator_function
    
    # Create compensation handler function
    create_compensation_handler_function
    
    # Create order service function
    create_order_service_function
    
    # Create payment service function
    create_payment_service_function
    
    # Create inventory service function
    create_inventory_service_function
    
    success "Lambda functions created successfully"
}

# Function to create orchestrator Lambda function
create_orchestrator_function() {
    log "Creating orchestrator Lambda function..."
    
    # Create orchestrator function code
    cat > "${TEMP_DIR}/orchestrator.py" << 'EOF'
import json
import boto3
import uuid
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
ORDER_QUEUE_URL = os.environ['ORDER_QUEUE_URL']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    try:
        # Initialize transaction
        transaction_id = str(uuid.uuid4())
        order_data = json.loads(event['body'])
        
        # Create saga state record
        saga_table = dynamodb.Table(SAGA_STATE_TABLE)
        saga_table.put_item(
            Item={
                'TransactionId': transaction_id,
                'Status': 'STARTED',
                'CurrentStep': 'ORDER_PROCESSING',
                'Steps': ['ORDER_PROCESSING', 'PAYMENT_PROCESSING', 'INVENTORY_UPDATE'],
                'CompletedSteps': [],
                'OrderData': order_data,
                'Timestamp': datetime.utcnow().isoformat(),
                'TTL': int(datetime.utcnow().timestamp()) + 86400  # 24 hours TTL
            }
        )
        
        # Start transaction by sending to order queue
        message_body = {
            'transactionId': transaction_id,
            'step': 'ORDER_PROCESSING',
            'data': order_data
        }
        
        sqs.send_message(
            QueueUrl=ORDER_QUEUE_URL,
            MessageBody=json.dumps(message_body),
            MessageGroupId=transaction_id
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'transactionId': transaction_id,
                'status': 'STARTED',
                'message': 'Transaction initiated successfully'
            })
        }
        
    except Exception as e:
        print(f"Error in orchestrator: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def handle_compensation(event, context):
    try:
        # Process compensation messages
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            failed_step = message_body['failedStep']
            
            # Update saga state to failed
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET #status = :status, FailedStep = :failed_step',
                ExpressionAttributeNames={'#status': 'Status'},
                ExpressionAttributeValues={
                    ':status': 'FAILED',
                    ':failed_step': failed_step
                }
            )
            
            print(f"Transaction {transaction_id} failed at step {failed_step}")
            
    except Exception as e:
        print(f"Error in compensation handler: {str(e)}")
        raise
EOF
    
    # Create deployment package
    if [[ "$DRY_RUN" == "false" ]]; then
        cd "${TEMP_DIR}"
        zip -r orchestrator.zip orchestrator.py
        cd - > /dev/null
    fi
    
    # Create Lambda function
    execute_cmd "aws lambda create-function \
        --function-name '${STACK_NAME}-orchestrator' \
        --runtime python3.9 \
        --role '${LAMBDA_ROLE_ARN}' \
        --handler orchestrator.lambda_handler \
        --zip-file fileb://${TEMP_DIR}/orchestrator.zip \
        --timeout 300 \
        --environment Variables='{
            \"SAGA_STATE_TABLE\":\"${SAGA_STATE_TABLE}\",
            \"ORDER_QUEUE_URL\":\"${ORDER_QUEUE_URL}\",
            \"COMPENSATION_QUEUE_URL\":\"${COMPENSATION_QUEUE_URL}\"
        }' \
        --tags StackName='${STACK_NAME}',Purpose='Orchestrator'"
    
    # Create compensation handler function
    execute_cmd "aws lambda create-function \
        --function-name '${STACK_NAME}-compensation-handler' \
        --runtime python3.9 \
        --role '${LAMBDA_ROLE_ARN}' \
        --handler orchestrator.handle_compensation \
        --zip-file fileb://${TEMP_DIR}/orchestrator.zip \
        --timeout 300 \
        --environment Variables='{
            \"SAGA_STATE_TABLE\":\"${SAGA_STATE_TABLE}\"
        }' \
        --tags StackName='${STACK_NAME}',Purpose='CompensationHandler'"
}

# Function to create compensation handler (placeholder since it's in orchestrator)
create_compensation_handler_function() {
    log "Compensation handler function created as part of orchestrator"
}

# Function to create order service Lambda function
create_order_service_function() {
    log "Creating order service Lambda function..."
    
    # Create order service function code
    cat > "${TEMP_DIR}/order_service.py" << 'EOF'
import json
import boto3
import uuid
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

ORDER_TABLE = os.environ['ORDER_TABLE']
SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
PAYMENT_QUEUE_URL = os.environ['PAYMENT_QUEUE_URL']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            order_data = message_body['data']
            
            # Generate order ID
            order_id = str(uuid.uuid4())
            
            # Create order record using DynamoDB transaction
            order_table = dynamodb.Table(ORDER_TABLE)
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            
            # Create order
            order_table.put_item(
                Item={
                    'OrderId': order_id,
                    'TransactionId': transaction_id,
                    'CustomerId': order_data['customerId'],
                    'ProductId': order_data['productId'],
                    'Quantity': order_data['quantity'],
                    'Amount': order_data['amount'],
                    'Status': 'PENDING',
                    'Timestamp': datetime.utcnow().isoformat()
                }
            )
            
            # Update saga state
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET CompletedSteps = list_append(CompletedSteps, :step), CurrentStep = :next_step',
                ExpressionAttributeValues={
                    ':step': ['ORDER_PROCESSING'],
                    ':next_step': 'PAYMENT_PROCESSING'
                }
            )
            
            # Send message to payment queue
            payment_message = {
                'transactionId': transaction_id,
                'step': 'PAYMENT_PROCESSING',
                'data': {
                    'orderId': order_id,
                    'customerId': order_data['customerId'],
                    'amount': order_data['amount']
                }
            }
            
            sqs.send_message(
                QueueUrl=PAYMENT_QUEUE_URL,
                MessageBody=json.dumps(payment_message),
                MessageGroupId=transaction_id
            )
            
            print(f"Order {order_id} created for transaction {transaction_id}")
            
    except Exception as e:
        print(f"Error in order service: {str(e)}")
        # Send compensation message
        compensation_message = {
            'transactionId': transaction_id,
            'failedStep': 'ORDER_PROCESSING',
            'error': str(e)
        }
        
        sqs.send_message(
            QueueUrl=COMPENSATION_QUEUE_URL,
            MessageBody=json.dumps(compensation_message),
            MessageGroupId=transaction_id
        )
        
        raise
EOF
    
    # Create deployment package
    if [[ "$DRY_RUN" == "false" ]]; then
        cd "${TEMP_DIR}"
        zip -r order_service.zip order_service.py
        cd - > /dev/null
    fi
    
    # Create Lambda function
    execute_cmd "aws lambda create-function \
        --function-name '${STACK_NAME}-order-service' \
        --runtime python3.9 \
        --role '${LAMBDA_ROLE_ARN}' \
        --handler order_service.lambda_handler \
        --zip-file fileb://${TEMP_DIR}/order_service.zip \
        --timeout 300 \
        --environment Variables='{
            \"ORDER_TABLE\":\"${ORDER_TABLE}\",
            \"SAGA_STATE_TABLE\":\"${SAGA_STATE_TABLE}\",
            \"PAYMENT_QUEUE_URL\":\"${PAYMENT_QUEUE_URL}\",
            \"COMPENSATION_QUEUE_URL\":\"${COMPENSATION_QUEUE_URL}\"
        }' \
        --tags StackName='${STACK_NAME}',Purpose='OrderService'"
}

# Function to create payment service Lambda function
create_payment_service_function() {
    log "Creating payment service Lambda function..."
    
    # Create payment service function code
    cat > "${TEMP_DIR}/payment_service.py" << 'EOF'
import json
import boto3
import uuid
import os
import random
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

PAYMENT_TABLE = os.environ['PAYMENT_TABLE']
SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
INVENTORY_QUEUE_URL = os.environ['INVENTORY_QUEUE_URL']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            payment_data = message_body['data']
            
            # Simulate payment processing (90% success rate)
            if random.random() < 0.1:
                raise Exception("Payment processing failed - insufficient funds")
            
            # Generate payment ID
            payment_id = str(uuid.uuid4())
            
            # Create payment record
            payment_table = dynamodb.Table(PAYMENT_TABLE)
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            
            payment_table.put_item(
                Item={
                    'PaymentId': payment_id,
                    'TransactionId': transaction_id,
                    'OrderId': payment_data['orderId'],
                    'CustomerId': payment_data['customerId'],
                    'Amount': payment_data['amount'],
                    'Status': 'PROCESSED',
                    'Timestamp': datetime.utcnow().isoformat()
                }
            )
            
            # Update saga state
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET CompletedSteps = list_append(CompletedSteps, :step), CurrentStep = :next_step',
                ExpressionAttributeValues={
                    ':step': ['PAYMENT_PROCESSING'],
                    ':next_step': 'INVENTORY_UPDATE'
                }
            )
            
            # Get original order data for inventory update
            saga_response = saga_table.get_item(
                Key={'TransactionId': transaction_id}
            )
            order_data = saga_response['Item']['OrderData']
            
            # Send message to inventory queue
            inventory_message = {
                'transactionId': transaction_id,
                'step': 'INVENTORY_UPDATE',
                'data': {
                    'orderId': payment_data['orderId'],
                    'paymentId': payment_id,
                    'productId': order_data['productId'],
                    'quantity': order_data['quantity']
                }
            }
            
            sqs.send_message(
                QueueUrl=INVENTORY_QUEUE_URL,
                MessageBody=json.dumps(inventory_message),
                MessageGroupId=transaction_id
            )
            
            print(f"Payment {payment_id} processed for transaction {transaction_id}")
            
    except Exception as e:
        print(f"Error in payment service: {str(e)}")
        # Send compensation message
        compensation_message = {
            'transactionId': transaction_id,
            'failedStep': 'PAYMENT_PROCESSING',
            'error': str(e)
        }
        
        sqs.send_message(
            QueueUrl=COMPENSATION_QUEUE_URL,
            MessageBody=json.dumps(compensation_message),
            MessageGroupId=transaction_id
        )
        
        raise
EOF
    
    # Create deployment package
    if [[ "$DRY_RUN" == "false" ]]; then
        cd "${TEMP_DIR}"
        zip -r payment_service.zip payment_service.py
        cd - > /dev/null
    fi
    
    # Create Lambda function
    execute_cmd "aws lambda create-function \
        --function-name '${STACK_NAME}-payment-service' \
        --runtime python3.9 \
        --role '${LAMBDA_ROLE_ARN}' \
        --handler payment_service.lambda_handler \
        --zip-file fileb://${TEMP_DIR}/payment_service.zip \
        --timeout 300 \
        --environment Variables='{
            \"PAYMENT_TABLE\":\"${PAYMENT_TABLE}\",
            \"SAGA_STATE_TABLE\":\"${SAGA_STATE_TABLE}\",
            \"INVENTORY_QUEUE_URL\":\"${INVENTORY_QUEUE_URL}\",
            \"COMPENSATION_QUEUE_URL\":\"${COMPENSATION_QUEUE_URL}\"
        }' \
        --tags StackName='${STACK_NAME}',Purpose='PaymentService'"
}

# Function to create inventory service Lambda function
create_inventory_service_function() {
    log "Creating inventory service Lambda function..."
    
    # Create inventory service function code
    cat > "${TEMP_DIR}/inventory_service.py" << 'EOF'
import json
import boto3
import os
import random
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

INVENTORY_TABLE = os.environ['INVENTORY_TABLE']
SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            inventory_data = message_body['data']
            
            # Simulate inventory check (85% success rate)
            if random.random() < 0.15:
                raise Exception("Insufficient inventory available")
            
            # Update inventory using DynamoDB transaction
            inventory_table = dynamodb.Table(INVENTORY_TABLE)
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            
            # Try to update inventory atomically
            try:
                inventory_table.update_item(
                    Key={'ProductId': inventory_data['productId']},
                    UpdateExpression='SET QuantityAvailable = QuantityAvailable - :quantity, LastUpdated = :timestamp',
                    ConditionExpression='QuantityAvailable >= :quantity',
                    ExpressionAttributeValues={
                        ':quantity': inventory_data['quantity'],
                        ':timestamp': datetime.utcnow().isoformat()
                    }
                )
            except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
                raise Exception("Insufficient inventory - conditional check failed")
            
            # Update saga state to completed
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET CompletedSteps = list_append(CompletedSteps, :step), CurrentStep = :next_step, #status = :status',
                ExpressionAttributeNames={'#status': 'Status'},
                ExpressionAttributeValues={
                    ':step': ['INVENTORY_UPDATE'],
                    ':next_step': 'COMPLETED',
                    ':status': 'COMPLETED'
                }
            )
            
            print(f"Inventory updated for transaction {transaction_id}, product {inventory_data['productId']}")
            
    except Exception as e:
        print(f"Error in inventory service: {str(e)}")
        # Send compensation message
        compensation_message = {
            'transactionId': transaction_id,
            'failedStep': 'INVENTORY_UPDATE',
            'error': str(e)
        }
        
        sqs.send_message(
            QueueUrl=COMPENSATION_QUEUE_URL,
            MessageBody=json.dumps(compensation_message),
            MessageGroupId=transaction_id
        )
        
        raise
EOF
    
    # Create deployment package
    if [[ "$DRY_RUN" == "false" ]]; then
        cd "${TEMP_DIR}"
        zip -r inventory_service.zip inventory_service.py
        cd - > /dev/null
    fi
    
    # Create Lambda function
    execute_cmd "aws lambda create-function \
        --function-name '${STACK_NAME}-inventory-service' \
        --runtime python3.9 \
        --role '${LAMBDA_ROLE_ARN}' \
        --handler inventory_service.lambda_handler \
        --zip-file fileb://${TEMP_DIR}/inventory_service.zip \
        --timeout 300 \
        --environment Variables='{
            \"INVENTORY_TABLE\":\"${INVENTORY_TABLE}\",
            \"SAGA_STATE_TABLE\":\"${SAGA_STATE_TABLE}\",
            \"COMPENSATION_QUEUE_URL\":\"${COMPENSATION_QUEUE_URL}\"
        }' \
        --tags StackName='${STACK_NAME}',Purpose='InventoryService'"
}

# Function to configure event source mappings
configure_event_sources() {
    log "Configuring SQS event source mappings..."
    
    # Create event source mapping for order processing
    execute_cmd "aws lambda create-event-source-mapping \
        --event-source-arn \$(aws sqs get-queue-attributes \
            --queue-url '${ORDER_QUEUE_URL}' \
            --attribute-names QueueArn \
            --query 'Attributes.QueueArn' --output text) \
        --function-name '${STACK_NAME}-order-service' \
        --batch-size 1 \
        --maximum-batching-window-in-seconds 5"
    
    # Create event source mapping for payment processing
    execute_cmd "aws lambda create-event-source-mapping \
        --event-source-arn \$(aws sqs get-queue-attributes \
            --queue-url '${PAYMENT_QUEUE_URL}' \
            --attribute-names QueueArn \
            --query 'Attributes.QueueArn' --output text) \
        --function-name '${STACK_NAME}-payment-service' \
        --batch-size 1 \
        --maximum-batching-window-in-seconds 5"
    
    # Create event source mapping for inventory update
    execute_cmd "aws lambda create-event-source-mapping \
        --event-source-arn \$(aws sqs get-queue-attributes \
            --queue-url '${INVENTORY_QUEUE_URL}' \
            --attribute-names QueueArn \
            --query 'Attributes.QueueArn' --output text) \
        --function-name '${STACK_NAME}-inventory-service' \
        --batch-size 1 \
        --maximum-batching-window-in-seconds 5"
    
    # Create event source mapping for compensation handling
    execute_cmd "aws lambda create-event-source-mapping \
        --event-source-arn \$(aws sqs get-queue-attributes \
            --queue-url '${COMPENSATION_QUEUE_URL}' \
            --attribute-names QueueArn \
            --query 'Attributes.QueueArn' --output text) \
        --function-name '${STACK_NAME}-compensation-handler' \
        --batch-size 1 \
        --maximum-batching-window-in-seconds 5"
    
    success "Event source mappings configured"
}

# Function to initialize sample data
initialize_sample_data() {
    log "Initializing sample inventory data..."
    
    # Add sample products to inventory
    execute_cmd "aws dynamodb put-item \
        --table-name '${INVENTORY_TABLE}' \
        --item '{
            \"ProductId\": {\"S\": \"PROD-001\"},
            \"ProductName\": {\"S\": \"Premium Laptop\"},
            \"QuantityAvailable\": {\"N\": \"50\"},
            \"Price\": {\"N\": \"1299.99\"},
            \"LastUpdated\": {\"S\": \"'$(date -u +%Y-%m-%dT%H:%M:%S)'\"}
        }'"
    
    execute_cmd "aws dynamodb put-item \
        --table-name '${INVENTORY_TABLE}' \
        --item '{
            \"ProductId\": {\"S\": \"PROD-002\"},
            \"ProductName\": {\"S\": \"Wireless Headphones\"},
            \"QuantityAvailable\": {\"N\": \"100\"},
            \"Price\": {\"N\": \"199.99\"},
            \"LastUpdated\": {\"S\": \"'$(date -u +%Y-%m-%dT%H:%M:%S)'\"}
        }'"
    
    execute_cmd "aws dynamodb put-item \
        --table-name '${INVENTORY_TABLE}' \
        --item '{
            \"ProductId\": {\"S\": \"PROD-003\"},
            \"ProductName\": {\"S\": \"Smartphone\"},
            \"QuantityAvailable\": {\"N\": \"25\"},
            \"Price\": {\"N\": \"799.99\"},
            \"LastUpdated\": {\"S\": \"'$(date -u +%Y-%m-%dT%H:%M:%S)'\"}
        }'"
    
    success "Sample inventory data initialized"
}

# Function to create API Gateway
create_api_gateway() {
    log "Creating API Gateway..."
    
    # Create API Gateway REST API
    if [[ "$DRY_RUN" == "false" ]]; then
        API_ID=$(aws apigateway create-rest-api \
            --name "${STACK_NAME}-transaction-api" \
            --description "Distributed Transaction Processing API" \
            --query 'id' --output text)
        
        # Get root resource ID
        ROOT_RESOURCE_ID=$(aws apigateway get-resources \
            --rest-api-id "${API_ID}" \
            --query 'items[?path==`/`].id' --output text)
        
        # Create transactions resource
        TRANSACTIONS_RESOURCE_ID=$(aws apigateway create-resource \
            --rest-api-id "${API_ID}" \
            --parent-id "${ROOT_RESOURCE_ID}" \
            --path-part "transactions" \
            --query 'id' --output text)
        
        # Create POST method
        aws apigateway put-method \
            --rest-api-id "${API_ID}" \
            --resource-id "${TRANSACTIONS_RESOURCE_ID}" \
            --http-method POST \
            --authorization-type "NONE"
        
        # Create Lambda integration
        aws apigateway put-integration \
            --rest-api-id "${API_ID}" \
            --resource-id "${TRANSACTIONS_RESOURCE_ID}" \
            --http-method POST \
            --type AWS_PROXY \
            --integration-http-method POST \
            --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${STACK_NAME}-orchestrator/invocations"
        
        # Grant API Gateway permission to invoke Lambda
        aws lambda add-permission \
            --function-name "${STACK_NAME}-orchestrator" \
            --statement-id "allow-api-gateway-invoke" \
            --action "lambda:InvokeFunction" \
            --principal "apigateway.amazonaws.com" \
            --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*"
        
        # Deploy API
        aws apigateway create-deployment \
            --rest-api-id "${API_ID}" \
            --stage-name "prod"
        
        export API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
        
        log "API Gateway created: ${API_ENDPOINT}"
    else
        API_ID="dry-run-api-id"
        export API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
        execute_cmd "# API Gateway would be created with endpoint: ${API_ENDPOINT}"
    fi
    
    success "API Gateway configuration completed"
}

# Function to create monitoring resources
create_monitoring() {
    log "Creating CloudWatch monitoring resources..."
    
    # Create CloudWatch alarm for failed transactions
    execute_cmd "aws cloudwatch put-metric-alarm \
        --alarm-name '${STACK_NAME}-failed-transactions' \
        --alarm-description 'Alert when transactions fail' \
        --metric-name 'Errors' \
        --namespace 'AWS/Lambda' \
        --statistic 'Sum' \
        --period 300 \
        --threshold 5 \
        --comparison-operator 'GreaterThanThreshold' \
        --evaluation-periods 2 \
        --dimensions Name=FunctionName,Value='${STACK_NAME}-orchestrator' \
        --tags Key=StackName,Value='${STACK_NAME}'"
    
    # Create CloudWatch alarm for SQS message age
    execute_cmd "aws cloudwatch put-metric-alarm \
        --alarm-name '${STACK_NAME}-message-age' \
        --alarm-description 'Alert when messages age in queue' \
        --metric-name 'ApproximateAgeOfOldestMessage' \
        --namespace 'AWS/SQS' \
        --statistic 'Maximum' \
        --period 300 \
        --threshold 600 \
        --comparison-operator 'GreaterThanThreshold' \
        --evaluation-periods 2 \
        --dimensions Name=QueueName,Value='${STACK_NAME}-order-processing.fifo' \
        --tags Key=StackName,Value='${STACK_NAME}'"
    
    # Create CloudWatch dashboard
    execute_cmd "aws cloudwatch put-dashboard \
        --dashboard-name '${STACK_NAME}-transactions' \
        --dashboard-body '{
            \"widgets\": [
                {
                    \"type\": \"metric\",
                    \"x\": 0,
                    \"y\": 0,
                    \"width\": 12,
                    \"height\": 6,
                    \"properties\": {
                        \"metrics\": [
                            [ \"AWS/Lambda\", \"Invocations\", \"FunctionName\", \"'${STACK_NAME}'-orchestrator\" ],
                            [ \".\", \"Errors\", \".\", \".\" ],
                            [ \".\", \"Duration\", \".\", \".\" ]
                        ],
                        \"period\": 300,
                        \"stat\": \"Sum\",
                        \"region\": \"'${AWS_REGION}'\",
                        \"title\": \"Transaction Orchestrator Metrics\"
                    }
                },
                {
                    \"type\": \"metric\",
                    \"x\": 12,
                    \"y\": 0,
                    \"width\": 12,
                    \"height\": 6,
                    \"properties\": {
                        \"metrics\": [
                            [ \"AWS/SQS\", \"NumberOfMessagesSent\", \"QueueName\", \"'${STACK_NAME}'-order-processing.fifo\" ],
                            [ \".\", \"NumberOfMessagesReceived\", \".\", \".\" ],
                            [ \".\", \"ApproximateNumberOfMessagesVisible\", \".\", \".\" ]
                        ],
                        \"period\": 300,
                        \"stat\": \"Sum\",
                        \"region\": \"'${AWS_REGION}'\",
                        \"title\": \"SQS Queue Metrics\"
                    }
                }
            ]
        }'"
    
    success "CloudWatch monitoring resources created"
}

# Function to save deployment state
save_deployment_state() {
    log "Saving deployment state..."
    
    # Create state file
    cat > "${TEMP_DIR}/deployment_state.json" << EOF
{
    "stackName": "${STACK_NAME}",
    "region": "${AWS_REGION}",
    "accountId": "${AWS_ACCOUNT_ID}",
    "deploymentTime": "$(date -u +%Y-%m-%dT%H:%M:%S)",
    "resources": {
        "dynamodbTables": [
            "${SAGA_STATE_TABLE}",
            "${ORDER_TABLE}",
            "${PAYMENT_TABLE}",
            "${INVENTORY_TABLE}"
        ],
        "sqsQueues": [
            "${STACK_NAME}-order-processing.fifo",
            "${STACK_NAME}-payment-processing.fifo",
            "${STACK_NAME}-inventory-update.fifo",
            "${STACK_NAME}-compensation.fifo",
            "${STACK_NAME}-dlq.fifo"
        ],
        "lambdaFunctions": [
            "${STACK_NAME}-orchestrator",
            "${STACK_NAME}-compensation-handler",
            "${STACK_NAME}-order-service",
            "${STACK_NAME}-payment-service",
            "${STACK_NAME}-inventory-service"
        ],
        "iamRole": "${STACK_NAME}-lambda-role",
        "apiGateway": {
            "apiId": "${API_ID}",
            "endpoint": "${API_ENDPOINT}"
        },
        "cloudwatchAlarms": [
            "${STACK_NAME}-failed-transactions",
            "${STACK_NAME}-message-age"
        ],
        "cloudwatchDashboard": "${STACK_NAME}-transactions"
    }
}
EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cp "${TEMP_DIR}/deployment_state.json" "./deployment_state_${STACK_NAME}.json"
        success "Deployment state saved to deployment_state_${STACK_NAME}.json"
    else
        success "Deployment state prepared (dry-run mode)"
    fi
}

# Function to cleanup temporary files
cleanup_temp_files() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log "Temporary files cleaned up"
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "================================================"
    echo "Stack Name: ${STACK_NAME}"
    echo "Region: ${AWS_REGION}"
    echo "Account ID: ${AWS_ACCOUNT_ID}"
    echo ""
    echo "API Endpoint: ${API_ENDPOINT}"
    echo ""
    echo "DynamoDB Tables:"
    echo "  - ${SAGA_STATE_TABLE}"
    echo "  - ${ORDER_TABLE}"
    echo "  - ${PAYMENT_TABLE}"
    echo "  - ${INVENTORY_TABLE}"
    echo ""
    echo "SQS Queues:"
    echo "  - ${STACK_NAME}-order-processing.fifo"
    echo "  - ${STACK_NAME}-payment-processing.fifo"
    echo "  - ${STACK_NAME}-inventory-update.fifo"
    echo "  - ${STACK_NAME}-compensation.fifo"
    echo "  - ${STACK_NAME}-dlq.fifo"
    echo ""
    echo "Lambda Functions:"
    echo "  - ${STACK_NAME}-orchestrator"
    echo "  - ${STACK_NAME}-compensation-handler"
    echo "  - ${STACK_NAME}-order-service"
    echo "  - ${STACK_NAME}-payment-service"
    echo "  - ${STACK_NAME}-inventory-service"
    echo ""
    echo "Test the API with:"
    echo "curl -X POST -H 'Content-Type: application/json' \\"
    echo "  -d '{\"customerId\":\"CUST-001\",\"productId\":\"PROD-001\",\"quantity\":2,\"amount\":2599.98}' \\"
    echo "  ${API_ENDPOINT}/transactions"
    echo ""
    echo "================================================"
}

# Function to handle script interruption
cleanup_on_interrupt() {
    error "Script interrupted. Cleaning up..."
    cleanup_temp_files
    exit 1
}

# Main deployment function
main() {
    # Set up interrupt handler
    trap cleanup_on_interrupt SIGINT SIGTERM
    
    log "Starting distributed transaction processing deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_iam_role
    create_dynamodb_tables
    create_sqs_queues
    create_lambda_functions
    configure_event_sources
    initialize_sample_data
    create_api_gateway
    create_monitoring
    save_deployment_state
    
    # Display summary
    display_summary
    
    # Cleanup
    cleanup_temp_files
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Dry-run completed successfully. No resources were created."
    else
        success "Deployment completed successfully!"
        warning "Remember to run ./destroy.sh when you're done testing to avoid ongoing charges."
    fi
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --dry-run    Run in dry-run mode (no resources created)"
    echo "  --help       Show this help message"
    echo ""
    echo "Example:"
    echo "  $0                # Deploy all resources"
    echo "  $0 --dry-run      # Preview deployment without creating resources"
}

# Parse command line arguments
case "$1" in
    --help)
        show_usage
        exit 0
        ;;
    --dry-run)
        # Dry run mode is handled in main execution
        ;;
    "")
        # No arguments is fine
        ;;
    *)
        error "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac

# Run main function
main