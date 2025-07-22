#!/bin/bash

# AWS API Composition with Step Functions and API Gateway - Deployment Script
# This script deploys the complete infrastructure for API composition using Step Functions and API Gateway

set -euo pipefail

# Script metadata
SCRIPT_NAME="deploy.sh"
SCRIPT_VERSION="1.0"
RECIPE_NAME="api-composition-step-functions-api-gateway"

# Color codes for output
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

log_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Cleanup function for script exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code $exit_code"
        log_warning "Some resources may have been created. Run destroy.sh to clean up."
    fi
    
    # Clean up temporary files
    rm -f trust-policy.json composition-policy.json apigw-trust-policy.json
    rm -f state-machine-definition.json enhanced-state-machine.json
    rm -f user-service.py inventory-service.py
    rm -f user-service.zip inventory-service.zip
    
    exit $exit_code
}

trap cleanup EXIT

# Validation functions
check_prerequisites() {
    log_header "Checking Prerequisites"
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $aws_version"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check required permissions
    log_info "Validating AWS permissions..."
    local account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [[ -z "$account_id" ]]; then
        log_error "Cannot retrieve AWS account ID. Check your credentials."
        exit 1
    fi
    
    # Check if required utilities are available
    for cmd in zip curl jq; do
        if ! command -v $cmd &> /dev/null; then
            log_warning "$cmd is not installed. Some features may not work."
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Environment setup
setup_environment() {
    log_header "Setting Up Environment"
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    if command -v aws &> /dev/null; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    else
        RANDOM_SUFFIX=$(date +%s | tail -c 6)
    fi
    
    export PROJECT_NAME="api-composition-${RANDOM_SUFFIX}"
    export ROLE_NAME="StepFunctionsCompositionRole-${RANDOM_SUFFIX}"
    export STATE_MACHINE_NAME="OrderProcessingWorkflow-${RANDOM_SUFFIX}"
    export API_NAME="CompositionAPI-${RANDOM_SUFFIX}"
    
    log_info "AWS Region: $AWS_REGION"
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    log_info "Project Name: $PROJECT_NAME"
    log_info "Random Suffix: $RANDOM_SUFFIX"
    
    # Save environment variables for destroy script
    cat > .deployment_env << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
PROJECT_NAME=$PROJECT_NAME
ROLE_NAME=$ROLE_NAME
STATE_MACHINE_NAME=$STATE_MACHINE_NAME
API_NAME=$API_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    log_success "Environment setup completed"
}

# Create DynamoDB tables
create_dynamodb_tables() {
    log_header "Creating DynamoDB Tables"
    
    # Create orders table
    log_info "Creating orders table..."
    if aws dynamodb create-table \
        --table-name "${PROJECT_NAME}-orders" \
        --attribute-definitions AttributeName=orderId,AttributeType=S \
        --key-schema AttributeName=orderId,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "Orders table creation initiated"
    else
        log_warning "Orders table may already exist or creation failed"
    fi
    
    # Create audit table
    log_info "Creating audit table..."
    if aws dynamodb create-table \
        --table-name "${PROJECT_NAME}-audit" \
        --attribute-definitions AttributeName=auditId,AttributeType=S \
        --key-schema AttributeName=auditId,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "Audit table creation initiated"
    else
        log_warning "Audit table may already exist or creation failed"
    fi
    
    # Wait for tables to be created
    log_info "Waiting for tables to become active..."
    aws dynamodb wait table-exists --table-name "${PROJECT_NAME}-orders" --region "$AWS_REGION"
    aws dynamodb wait table-exists --table-name "${PROJECT_NAME}-audit" --region "$AWS_REGION"
    
    log_success "DynamoDB tables created successfully"
}

# Create IAM role for Step Functions
create_iam_role() {
    log_header "Creating IAM Role for Step Functions"
    
    # Create trust policy for Step Functions
    cat > trust-policy.json << EOF
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
    
    # Create the IAM role
    log_info "Creating IAM role: $ROLE_NAME"
    if aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file://trust-policy.json \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "IAM role created"
    else
        log_warning "IAM role may already exist"
    fi
    
    # Attach necessary policies
    log_info "Attaching AWS Lambda execution policy..."
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaRole" \
        --region "$AWS_REGION" > /dev/null 2>&1 || log_warning "Policy attachment may have failed"
    
    # Create custom policy for DynamoDB and API Gateway access
    cat > composition-policy.json << EOF
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
      "Resource": [
        "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${PROJECT_NAME}-*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "execute-api:Invoke"
      ],
      "Resource": "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:*/*/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:*"
    }
  ]
}
EOF
    
    log_info "Creating custom composition policy..."
    aws iam put-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-name "CompositionPolicy" \
        --policy-document file://composition-policy.json \
        --region "$AWS_REGION"
    
    # Get the role ARN
    ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" \
        --query Role.Arn --output text --region "$AWS_REGION")
    
    log_success "IAM role created with ARN: $ROLE_ARN"
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
}

# Create Lambda functions for microservices
create_lambda_functions() {
    log_header "Creating Lambda Functions for Microservices"
    
    # Check if lambda execution role exists, if not create a basic one
    if ! aws iam get-role --role-name lambda-execution-role &> /dev/null; then
        log_info "Creating basic Lambda execution role..."
        
        cat > lambda-trust-policy.json << EOF
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
            --role-name lambda-execution-role \
            --assume-role-policy-document file://lambda-trust-policy.json \
            --region "$AWS_REGION" > /dev/null 2>&1
        
        aws iam attach-role-policy \
            --role-name lambda-execution-role \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
            --region "$AWS_REGION" > /dev/null 2>&1
        
        sleep 5  # Wait for role propagation
        rm -f lambda-trust-policy.json
    fi
    
    # Create Lambda function for user validation
    cat > user-service.py << 'EOF'
import json
import random

def lambda_handler(event, context):
    user_id = event.get('userId', '')
    
    # Mock user validation
    if not user_id or len(user_id) < 3:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'valid': False,
                'error': 'Invalid user ID'
            })
        }
    
    # Simulate user data retrieval
    user_data = {
        'valid': True,
        'userId': user_id,
        'name': f'User {user_id}',
        'email': f'{user_id}@example.com',
        'creditLimit': random.randint(1000, 5000)
    }
    
    return {
        'statusCode': 200,
        'body': json.dumps(user_data)
    }
EOF
    
    # Create deployment package
    zip -q user-service.zip user-service.py
    
    # Create Lambda function
    log_info "Creating user service Lambda function..."
    if aws lambda create-function \
        --function-name "${PROJECT_NAME}-user-service" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda-execution-role" \
        --handler user-service.lambda_handler \
        --zip-file fileb://user-service.zip \
        --timeout 30 \
        --memory-size 128 \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "User service Lambda function created"
    else
        log_warning "User service Lambda function may already exist"
    fi
    
    # Create inventory service
    cat > inventory-service.py << 'EOF'
import json
import random

def lambda_handler(event, context):
    items = event.get('items', [])
    
    inventory_status = []
    for item in items:
        available = random.randint(0, 100)
        requested = item.get('quantity', 0)
        
        inventory_status.append({
            'productId': item.get('productId'),
            'requested': requested,
            'available': available,
            'sufficient': available >= requested,
            'price': random.randint(10, 500)
        })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'inventoryStatus': inventory_status,
            'allItemsAvailable': all(item['sufficient'] for item in inventory_status)
        })
    }
EOF
    
    zip -q inventory-service.zip inventory-service.py
    
    log_info "Creating inventory service Lambda function..."
    if aws lambda create-function \
        --function-name "${PROJECT_NAME}-inventory-service" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda-execution-role" \
        --handler inventory-service.lambda_handler \
        --zip-file fileb://inventory-service.zip \
        --timeout 30 \
        --memory-size 128 \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "Inventory service Lambda function created"
    else
        log_warning "Inventory service Lambda function may already exist"
    fi
    
    log_success "Mock microservices created successfully"
}

# Create Step Functions State Machine
create_state_machine() {
    log_header "Creating Step Functions State Machine"
    
    # Create the state machine definition
    cat > state-machine-definition.json << EOF
{
  "Comment": "Order Processing Workflow with API Composition",
  "StartAt": "ValidateOrder",
  "States": {
    "ValidateOrder": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PROJECT_NAME}-user-service",
        "Payload": {
          "userId.\$": "\$.userId"
        }
      },
      "ResultPath": "\$.userValidation",
      "Next": "CheckUserValid",
      "Catch": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "Next": "ValidationFailed",
          "ResultPath": "\$.error"
        }
      ]
    },
    "CheckUserValid": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "\$.userValidation.Payload.body",
          "StringMatches": "*\"valid\":true*",
          "Next": "CheckInventory"
        }
      ],
      "Default": "ValidationFailed"
    },
    "CheckInventory": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PROJECT_NAME}-inventory-service",
        "Payload": {
          "items.\$": "\$.items"
        }
      },
      "ResultPath": "\$.inventoryCheck",
      "Next": "ProcessInventoryResult",
      "Catch": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "Next": "InventoryCheckFailed",
          "ResultPath": "\$.error"
        }
      ]
    },
    "ProcessInventoryResult": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "\$.inventoryCheck.Payload.body",
          "StringMatches": "*\"allItemsAvailable\":true*",
          "Next": "CalculateOrderTotal"
        }
      ],
      "Default": "InsufficientInventory"
    },
    "CalculateOrderTotal": {
      "Type": "Pass",
      "Parameters": {
        "orderId.\$": "\$.orderId",
        "userId.\$": "\$.userId",
        "items.\$": "\$.items",
        "userInfo.\$": "\$.userValidation.Payload.body",
        "inventoryInfo.\$": "\$.inventoryCheck.Payload.body",
        "orderTotal": 250.00,
        "status": "processing"
      },
      "Next": "ParallelProcessing"
    },
    "ParallelProcessing": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "SaveOrder",
          "States": {
            "SaveOrder": {
              "Type": "Task",
              "Resource": "arn:aws:states:::dynamodb:putItem",
              "Parameters": {
                "TableName": "${PROJECT_NAME}-orders",
                "Item": {
                  "orderId": {
                    "S.\$": "\$.orderId"
                  },
                  "userId": {
                    "S.\$": "\$.userId"
                  },
                  "status": {
                    "S": "processing"
                  },
                  "orderTotal": {
                    "N": "250.00"
                  },
                  "timestamp": {
                    "S.\$": "\$\$.State.EnteredTime"
                  }
                }
              },
              "End": true
            }
          }
        },
        {
          "StartAt": "LogAudit",
          "States": {
            "LogAudit": {
              "Type": "Task",
              "Resource": "arn:aws:states:::dynamodb:putItem",
              "Parameters": {
                "TableName": "${PROJECT_NAME}-audit",
                "Item": {
                  "auditId": {
                    "S.\$": "\$\$.Execution.Name"
                  },
                  "orderId": {
                    "S.\$": "\$.orderId"
                  },
                  "action": {
                    "S": "order_created"
                  },
                  "timestamp": {
                    "S.\$": "\$\$.State.EnteredTime"
                  }
                }
              },
              "End": true
            }
          }
        }
      ],
      "Next": "OrderProcessed"
    },
    "OrderProcessed": {
      "Type": "Pass",
      "Parameters": {
        "orderId.\$": "\$.orderId",
        "status": "completed",
        "message": "Order processed successfully",
        "orderTotal": 250.00
      },
      "End": true
    },
    "ValidationFailed": {
      "Type": "Pass",
      "Parameters": {
        "error": "User validation failed",
        "orderId.\$": "\$.orderId"
      },
      "End": true
    },
    "InventoryCheckFailed": {
      "Type": "Pass",
      "Parameters": {
        "error": "Inventory check failed",
        "orderId.\$": "\$.orderId"
      },
      "End": true
    },
    "InsufficientInventory": {
      "Type": "Pass",
      "Parameters": {
        "error": "Insufficient inventory",
        "orderId.\$": "\$.orderId"
      },
      "End": true
    }
  }
}
EOF
    
    # Create the state machine
    log_info "Creating Step Functions state machine..."
    if aws stepfunctions create-state-machine \
        --name "${STATE_MACHINE_NAME}" \
        --definition file://state-machine-definition.json \
        --role-arn "${ROLE_ARN}" \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "Step Functions state machine created"
    else
        log_warning "Step Functions state machine may already exist"
    fi
    
    # Get the state machine ARN
    STATE_MACHINE_ARN=$(aws stepfunctions describe-state-machine \
        --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
        --query stateMachineArn --output text --region "$AWS_REGION")
    
    log_success "State machine created with ARN: $STATE_MACHINE_ARN"
    
    # Save state machine ARN for API Gateway
    echo "STATE_MACHINE_ARN=$STATE_MACHINE_ARN" >> .deployment_env
}

# Create API Gateway
create_api_gateway() {
    log_header "Creating API Gateway"
    
    # Create API Gateway
    log_info "Creating REST API..."
    API_ID=$(aws apigateway create-rest-api \
        --name "${API_NAME}" \
        --description "API Composition with Step Functions" \
        --query id --output text --region "$AWS_REGION")
    
    log_success "API Gateway created with ID: $API_ID"
    
    # Get root resource ID
    ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query 'items[0].id' --output text --region "$AWS_REGION")
    
    # Create orders resource
    log_info "Creating orders resource..."
    ORDERS_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "${API_ID}" \
        --parent-id "${ROOT_RESOURCE_ID}" \
        --path-part "orders" \
        --query id --output text --region "$AWS_REGION")
    
    # Create IAM role for API Gateway to invoke Step Functions
    cat > apigw-trust-policy.json << EOF
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
    
    log_info "Creating API Gateway IAM role..."
    if aws iam create-role \
        --role-name "APIGatewayStepFunctionsRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document file://apigw-trust-policy.json \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "API Gateway IAM role created"
    else
        log_warning "API Gateway IAM role may already exist"
    fi
    
    # Attach Step Functions execution policy
    aws iam attach-role-policy \
        --role-name "APIGatewayStepFunctionsRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess" \
        --region "$AWS_REGION" > /dev/null 2>&1
    
    APIGW_ROLE_ARN=$(aws iam get-role \
        --role-name "APIGatewayStepFunctionsRole-${RANDOM_SUFFIX}" \
        --query Role.Arn --output text --region "$AWS_REGION")
    
    log_success "API Gateway IAM role created: $APIGW_ROLE_ARN"
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
    
    # Save API details for cleanup
    echo "API_ID=$API_ID" >> .deployment_env
    echo "APIGW_ROLE_ARN=$APIGW_ROLE_ARN" >> .deployment_env
    echo "ORDERS_RESOURCE_ID=$ORDERS_RESOURCE_ID" >> .deployment_env
}

# Configure API Gateway methods
configure_api_methods() {
    log_header "Configuring API Gateway Methods"
    
    # Create POST method
    log_info "Creating POST method for orders..."
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${ORDERS_RESOURCE_ID}" \
        --http-method POST \
        --authorization-type NONE \
        --request-parameters method.request.header.Content-Type=false \
        --region "$AWS_REGION" > /dev/null 2>&1
    
    # Create integration with Step Functions
    log_info "Setting up Step Functions integration..."
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${ORDERS_RESOURCE_ID}" \
        --http-method POST \
        --type AWS \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:states:action/StartExecution" \
        --credentials "${APIGW_ROLE_ARN}" \
        --request-templates "{\"application/json\": \"{\\\"input\\\": \\\"\\$util.escapeJavaScript(\\$input.json('\\$'))\\\", \\\"stateMachineArn\\\": \\\"${STATE_MACHINE_ARN}\\\"}\"}" \
        --region "$AWS_REGION" > /dev/null 2>&1
    
    # Configure method response
    aws apigateway put-method-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${ORDERS_RESOURCE_ID}" \
        --http-method POST \
        --status-code 200 \
        --response-models application/json=Empty \
        --region "$AWS_REGION" > /dev/null 2>&1
    
    # Configure integration response
    aws apigateway put-integration-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${ORDERS_RESOURCE_ID}" \
        --http-method POST \
        --status-code 200 \
        --response-templates "{\"application/json\": \"{\\\"executionArn\\\": \\\"\\$input.json('\\$.executionArn')\\\"}\"}" \
        --region "$AWS_REGION" > /dev/null 2>&1
    
    log_success "API Gateway method configured successfully"
}

# Deploy API Gateway
deploy_api() {
    log_header "Deploying API Gateway"
    
    # Deploy API
    log_info "Creating API deployment..."
    aws apigateway create-deployment \
        --rest-api-id "${API_ID}" \
        --stage-name "prod" \
        --region "$AWS_REGION" > /dev/null 2>&1
    
    # Get API endpoint
    API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    log_success "API deployed successfully"
    log_success "API Endpoint: $API_ENDPOINT"
    
    # Save API endpoint
    echo "API_ENDPOINT=$API_ENDPOINT" >> .deployment_env
}

# Test the deployment
test_deployment() {
    log_header "Testing Deployment"
    
    if command -v curl &> /dev/null; then
        log_info "Testing API composition endpoint..."
        
        # Test the API composition
        RESPONSE=$(curl -s -X POST "${API_ENDPOINT}/orders" \
            -H "Content-Type: application/json" \
            -d '{
              "orderId": "test-order-123",
              "userId": "testuser456",
              "items": [
                {
                  "productId": "prod-1",
                  "quantity": 2
                },
                {
                  "productId": "prod-2",
                  "quantity": 1
                }
              ]
            }' || echo "Test failed")
        
        if [[ "$RESPONSE" == *"executionArn"* ]]; then
            log_success "API composition test completed successfully"
            log_info "Response: $RESPONSE"
        else
            log_warning "API test may have failed. Response: $RESPONSE"
        fi
    else
        log_warning "curl not available. Skipping API test."
    fi
}

# Display deployment summary
show_deployment_summary() {
    log_header "Deployment Summary"
    
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
    echo
    echo "Resources created:"
    echo "  • DynamoDB Tables:"
    echo "    - ${PROJECT_NAME}-orders"
    echo "    - ${PROJECT_NAME}-audit"
    echo "  • Lambda Functions:"
    echo "    - ${PROJECT_NAME}-user-service"
    echo "    - ${PROJECT_NAME}-inventory-service"
    echo "  • Step Functions State Machine:"
    echo "    - ${STATE_MACHINE_NAME}"
    echo "  • API Gateway:"
    echo "    - ${API_NAME}"
    echo
    echo "API Endpoint: ${API_ENDPOINT}"
    echo
    echo "Test your API:"
    echo "curl -X POST ${API_ENDPOINT}/orders \\"
    echo "  -H \"Content-Type: application/json\" \\"
    echo "  -d '{\"orderId\": \"order-123\", \"userId\": \"user456\", \"items\": [{\"productId\": \"prod-1\", \"quantity\": 2}]}'"
    echo
    echo "Environment details saved to .deployment_env"
    echo "Run ./destroy.sh to clean up all resources."
}

# Main deployment function
main() {
    log_header "AWS API Composition Deployment - $SCRIPT_VERSION"
    
    echo "Starting deployment of API Composition with Step Functions and API Gateway..."
    echo "This will create AWS resources that may incur charges."
    echo
    
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_dynamodb_tables
    create_iam_role
    create_lambda_functions
    create_state_machine
    create_api_gateway
    configure_api_methods
    deploy_api
    test_deployment
    show_deployment_summary
    
    log_success "Deployment completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi