#!/bin/bash

# Deploy script for Microservices Orchestration with AWS Step Functions
# This script deploys Lambda functions, Step Functions state machine, and EventBridge integration

set -e  # Exit on any error

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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    # Check required permissions
    log "Validating AWS permissions..."
    aws iam get-user &> /dev/null || aws sts get-caller-identity &> /dev/null || error "Unable to verify AWS credentials"
    
    success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No default region set. Using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 6))
    
    export PROJECT_NAME="microservices-stepfn-${RANDOM_SUFFIX}"
    export ROLE_NAME="${PROJECT_NAME}-execution-role"
    export LAMBDA_ROLE_NAME="${PROJECT_NAME}-lambda-role"
    
    log "Project Name: $PROJECT_NAME"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    
    success "Environment setup complete"
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create Step Functions execution role
    log "Creating Step Functions execution role..."
    aws iam create-role \
        --role-name $ROLE_NAME \
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
        }' || warning "Step Functions role may already exist"
    
    # Attach policy for Lambda invocation
    aws iam attach-role-policy \
        --role-name $ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaRole || true
    
    # Create Lambda execution role
    log "Creating Lambda execution role..."
    aws iam create-role \
        --role-name $LAMBDA_ROLE_NAME \
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
        }' || warning "Lambda role may already exist"
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name $LAMBDA_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
    
    # Wait for role propagation
    log "Waiting for IAM role propagation..."
    sleep 10
    
    success "IAM roles created successfully"
}

# Create Lambda function
create_lambda_function() {
    local function_name=$1
    local handler=$2
    local code_file=$3
    
    log "Creating Lambda function: $function_name"
    
    # Package function
    zip ${function_name}.zip ${code_file} || error "Failed to package $function_name"
    
    # Create function
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-${function_name}" \
        --runtime python3.9 \
        --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME} \
        --handler ${handler} \
        --zip-file fileb://${function_name}.zip \
        --timeout 30 \
        --description "Microservices ${function_name} for Step Functions orchestration" || {
        warning "Function ${function_name} may already exist, updating code..."
        aws lambda update-function-code \
            --function-name "${PROJECT_NAME}-${function_name}" \
            --zip-file fileb://${function_name}.zip || error "Failed to update $function_name"
    }
    
    success "Lambda function $function_name deployed"
}

# Create all Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create user service function
    cat > user-service.py << 'EOF'
import json
import boto3
import random

def lambda_handler(event, context):
    user_id = event.get('userId')
    
    # Simulate user validation
    if not user_id:
        raise Exception("User ID is required")
    
    # Mock user data
    user_data = {
        'userId': user_id,
        'email': f'user{user_id}@example.com',
        'status': 'active',
        'creditScore': random.randint(600, 850)
    }
    
    return {
        'statusCode': 200,
        'body': json.dumps(user_data)
    }
EOF
    
    create_lambda_function "user-service" "user-service.lambda_handler" "user-service.py"
    
    # Create order service function
    cat > order-service.py << 'EOF'
import json
import uuid
import datetime

def lambda_handler(event, context):
    order_data = event.get('orderData', {})
    user_data = event.get('userData', {})
    
    # Validate order requirements
    if not order_data.get('items'):
        raise Exception("Order items are required")
    
    # Create order
    order = {
        'orderId': str(uuid.uuid4()),
        'userId': user_data.get('userId'),
        'items': order_data.get('items'),
        'total': sum(item.get('price', 0) for item in order_data.get('items', [])),
        'status': 'pending',
        'created': datetime.datetime.utcnow().isoformat()
    }
    
    return {
        'statusCode': 200,
        'body': json.dumps(order)
    }
EOF
    
    create_lambda_function "order-service" "order-service.lambda_handler" "order-service.py"
    
    # Create payment service function
    cat > payment-service.py << 'EOF'
import json
import random

def lambda_handler(event, context):
    order_data = event.get('orderData', {})
    user_data = event.get('userData', {})
    
    order_total = order_data.get('total', 0)
    credit_score = user_data.get('creditScore', 600)
    
    # Simulate payment processing
    if order_total > 1000 and credit_score < 650:
        raise Exception("Payment declined: Insufficient credit rating")
    
    # Simulate random payment failures
    if random.random() < 0.1:  # 10% failure rate
        raise Exception("Payment gateway timeout")
    
    payment_result = {
        'transactionId': f"txn_{random.randint(100000, 999999)}",
        'amount': order_total,
        'status': 'authorized',
        'method': 'credit_card'
    }
    
    return {
        'statusCode': 200,
        'body': json.dumps(payment_result)
    }
EOF
    
    create_lambda_function "payment-service" "payment-service.lambda_handler" "payment-service.py"
    
    # Create inventory service function
    cat > inventory-service.py << 'EOF'
import json
import random

def lambda_handler(event, context):
    order_data = event.get('orderData', {})
    
    items = order_data.get('items', [])
    inventory_results = []
    
    for item in items:
        # Simulate inventory check
        available_qty = random.randint(0, 100)
        requested_qty = item.get('quantity', 1)
        
        if available_qty >= requested_qty:
            inventory_results.append({
                'productId': item.get('productId'),
                'status': 'reserved',
                'quantity': requested_qty
            })
        else:
            raise Exception(f"Insufficient inventory for product {item.get('productId')}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'reservations': inventory_results,
            'status': 'confirmed'
        })
    }
EOF
    
    create_lambda_function "inventory-service" "inventory-service.lambda_handler" "inventory-service.py"
    
    # Create notification service function
    cat > notification-service.py << 'EOF'
import json

def lambda_handler(event, context):
    user_data = event.get('userData', {})
    order_data = event.get('orderData', {})
    payment_data = event.get('paymentData', {})
    
    # Create notification message
    notification = {
        'to': user_data.get('email'),
        'subject': f"Order Confirmation #{order_data.get('orderId')}",
        'message': f"Your order for ${order_data.get('total')} has been confirmed. Transaction ID: {payment_data.get('transactionId')}",
        'status': 'sent'
    }
    
    # In a real implementation, this would send actual notifications
    print(f"Notification sent: {json.dumps(notification)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(notification)
    }
EOF
    
    create_lambda_function "notification-service" "notification-service.lambda_handler" "notification-service.py"
    
    success "All Lambda functions created successfully"
}

# Create Step Functions state machine
create_step_functions() {
    log "Creating Step Functions state machine..."
    
    # Create state machine definition
    cat > stepfunctions-definition.json << EOF
{
  "Comment": "Microservices orchestration workflow",
  "StartAt": "ValidateInput",
  "States": {
    "ValidateInput": {
      "Type": "Pass",
      "Next": "GetUserData"
    },
    "GetUserData": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PROJECT_NAME}-user-service",
        "Payload.$": "$"
      },
      "ResultPath": "$.userResult",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Next": "ProcessOrderAndPayment"
    },
    "ProcessOrderAndPayment": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "CreateOrder",
          "States": {
            "CreateOrder": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "${PROJECT_NAME}-order-service",
                "Payload": {
                  "orderData.$": "$.orderData",
                  "userData.$": "$.userResult.Payload"
                }
              },
              "End": true
            }
          }
        },
        {
          "StartAt": "ProcessPayment",
          "States": {
            "ProcessPayment": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "${PROJECT_NAME}-payment-service",
                "Payload": {
                  "orderData.$": "$.orderData",
                  "userData.$": "$.userResult.Payload"
                }
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 1,
                  "MaxAttempts": 2
                }
              ],
              "End": true
            }
          }
        },
        {
          "StartAt": "CheckInventory",
          "States": {
            "CheckInventory": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "${PROJECT_NAME}-inventory-service",
                "Payload": {
                  "orderData.$": "$.orderData"
                }
              },
              "End": true
            }
          }
        }
      ],
      "Next": "SendNotification"
    },
    "SendNotification": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PROJECT_NAME}-notification-service",
        "Payload": {
          "userData.$": "$.userResult.Payload",
          "orderData.$": "$[0].Payload",
          "paymentData.$": "$[1].Payload"
        }
      },
      "End": true
    }
  }
}
EOF
    
    # Create Step Functions state machine
    aws stepfunctions create-state-machine \
        --name "${PROJECT_NAME}-workflow" \
        --definition file://stepfunctions-definition.json \
        --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME} || {
        warning "State machine may already exist, updating definition..."
        export STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
            --query "stateMachines[?name=='${PROJECT_NAME}-workflow'].stateMachineArn" \
            --output text)
        
        if [ ! -z "$STATE_MACHINE_ARN" ]; then
            aws stepfunctions update-state-machine \
                --state-machine-arn $STATE_MACHINE_ARN \
                --definition file://stepfunctions-definition.json \
                --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME} || error "Failed to update state machine"
        else
            error "Failed to create or find state machine"
        fi
    }
    
    # Get state machine ARN
    export STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?name=='${PROJECT_NAME}-workflow'].stateMachineArn" \
        --output text)
    
    success "Step Functions state machine deployed: $STATE_MACHINE_ARN"
}

# Create EventBridge integration
create_eventbridge() {
    log "Creating EventBridge integration..."
    
    # Create EventBridge rule
    aws events put-rule \
        --name "${PROJECT_NAME}-trigger" \
        --event-pattern '{
          "source": ["microservices.orders"],
          "detail-type": ["Order Submitted"]
        }' \
        --state ENABLED || warning "EventBridge rule may already exist"
    
    # Add Step Functions as target
    aws events put-targets \
        --rule "${PROJECT_NAME}-trigger" \
        --targets Id=1,Arn=${STATE_MACHINE_ARN},RoleArn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME} || \
        warning "EventBridge target may already exist"
    
    success "EventBridge integration configured"
}

# Test deployment
test_deployment() {
    log "Testing deployment..."
    
    # Test individual Lambda function
    log "Testing user service..."
    aws lambda invoke \
        --function-name "${PROJECT_NAME}-user-service" \
        --payload '{"userId": "12345"}' \
        user-response.json &> /dev/null || error "User service test failed"
    
    if grep -q "statusCode.*200" user-response.json; then
        success "User service test passed"
    else
        error "User service test failed - invalid response"
    fi
    
    # Test Step Functions workflow
    log "Testing Step Functions workflow..."
    EXECUTION_ARN=$(aws stepfunctions start-execution \
        --state-machine-arn $STATE_MACHINE_ARN \
        --input '{
          "userId": "12345",
          "orderData": {
            "items": [
              {"productId": "PROD001", "quantity": 2, "price": 29.99},
              {"productId": "PROD002", "quantity": 1, "price": 49.99}
            ]
          }
        }' \
        --query 'executionArn' \
        --output text) || error "Failed to start Step Functions execution"
    
    success "Step Functions execution started: $EXECUTION_ARN"
    
    # Test EventBridge trigger
    log "Testing EventBridge integration..."
    aws events put-events \
        --entries Source=microservices.orders,DetailType="Order Submitted",Detail='{"userId":"12345","orderData":{"items":[{"productId":"PROD001","quantity":1,"price":99.99}]}}' \
        &> /dev/null || warning "EventBridge test may have failed"
    
    success "EventBridge test event sent"
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f *.py *.zip *.json
    success "Temporary files cleaned up"
}

# Display deployment information
display_info() {
    echo ""
    echo "=============================================="
    success "🎉 Deployment completed successfully!"
    echo "=============================================="
    echo ""
    echo "📋 Deployment Summary:"
    echo "   Project Name: $PROJECT_NAME"
    echo "   AWS Region: $AWS_REGION"
    echo "   State Machine ARN: $STATE_MACHINE_ARN"
    echo ""
    echo "🔧 Resources Created:"
    echo "   • IAM Roles: $ROLE_NAME, $LAMBDA_ROLE_NAME"
    echo "   • Lambda Functions: 5 microservices"
    echo "   • Step Functions State Machine: ${PROJECT_NAME}-workflow"
    echo "   • EventBridge Rule: ${PROJECT_NAME}-trigger"
    echo ""
    echo "🧪 To test the workflow manually:"
    echo "   aws stepfunctions start-execution \\"
    echo "       --state-machine-arn $STATE_MACHINE_ARN \\"
    echo "       --input '{\"userId\":\"12345\",\"orderData\":{\"items\":[{\"productId\":\"PROD001\",\"quantity\":1,\"price\":99.99}]}}'"
    echo ""
    echo "📊 Monitor executions in AWS Console:"
    echo "   https://${AWS_REGION}.console.aws.amazon.com/states/home?region=${AWS_REGION}#/statemachines/view/${STATE_MACHINE_ARN}"
    echo ""
    warning "💰 Remember to run destroy.sh when finished to avoid ongoing charges!"
    echo ""
}

# Main execution
main() {
    log "🚀 Starting microservices Step Functions deployment..."
    
    check_prerequisites
    setup_environment
    create_iam_roles
    create_lambda_functions
    create_step_functions
    create_eventbridge
    test_deployment
    cleanup_temp_files
    display_info
}

# Handle script interruption
trap 'error "❌ Deployment interrupted! Some resources may have been created. Run destroy.sh to clean up."' INT TERM

# Run main function
main "$@"