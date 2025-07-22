#!/bin/bash

# Business Process Automation with Step Functions - Deployment Script
# This script deploys all AWS resources needed for the business process automation workflow

set -e  # Exit on any error

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions
    log_info "Checking AWS permissions..."
    
    # Test basic permissions
    if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity &> /dev/null; then
        log_error "Insufficient AWS permissions. Please ensure you have the necessary IAM permissions."
        exit 1
    fi
    
    log_success "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "No region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    export BUSINESS_PROCESS_PREFIX="business-process-${RANDOM_SUFFIX}"
    export STATE_MACHINE_NAME="${BUSINESS_PROCESS_PREFIX}-workflow"
    export LAMBDA_FUNCTION_NAME="${BUSINESS_PROCESS_PREFIX}-processor"
    export SQS_QUEUE_NAME="${BUSINESS_PROCESS_PREFIX}-queue"
    export SNS_TOPIC_NAME="${BUSINESS_PROCESS_PREFIX}-notifications"
    export LAMBDA_ROLE_NAME="${BUSINESS_PROCESS_PREFIX}-lambda-role"
    export STEPFUNCTIONS_ROLE_NAME="${BUSINESS_PROCESS_PREFIX}-stepfunctions-role"
    export API_NAME="${BUSINESS_PROCESS_PREFIX}-approval-api"
    
    log_success "Environment variables configured"
    log_info "Resource prefix: ${BUSINESS_PROCESS_PREFIX}"
}

# Function to create IAM roles
create_iam_roles() {
    log_info "Creating IAM roles..."
    
    # Create trust policy for Lambda
    cat > /tmp/lambda-trust-policy.json << 'EOF'
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

    # Create Lambda execution role
    if ! aws iam get-role --role-name ${LAMBDA_ROLE_NAME} &> /dev/null; then
        aws iam create-role \
            --role-name ${LAMBDA_ROLE_NAME} \
            --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
            --description "Role for Lambda function in business process automation"
        
        # Attach basic Lambda execution policy
        aws iam attach-role-policy \
            --role-name ${LAMBDA_ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        log_success "Lambda IAM role created: ${LAMBDA_ROLE_NAME}"
    else
        log_warning "Lambda IAM role already exists: ${LAMBDA_ROLE_NAME}"
    fi
    
    # Create trust policy for Step Functions
    cat > /tmp/stepfunctions-trust-policy.json << 'EOF'
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

    # Create Step Functions execution role
    if ! aws iam get-role --role-name ${STEPFUNCTIONS_ROLE_NAME} &> /dev/null; then
        aws iam create-role \
            --role-name ${STEPFUNCTIONS_ROLE_NAME} \
            --assume-role-policy-document file:///tmp/stepfunctions-trust-policy.json \
            --description "Role for Step Functions state machine in business process automation"
        
        log_success "Step Functions IAM role created: ${STEPFUNCTIONS_ROLE_NAME}"
    else
        log_warning "Step Functions IAM role already exists: ${STEPFUNCTIONS_ROLE_NAME}"
    fi
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
}

# Function to create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function..."
    
    # Create Lambda function code
    cat > /tmp/business-processor.py << 'EOF'
import json
import boto3
import time
from datetime import datetime

def lambda_handler(event, context):
    # Extract business process data
    process_data = event.get('processData', {})
    process_type = process_data.get('type', 'unknown')
    
    # Simulate business logic processing
    processing_time = process_data.get('processingTime', 2)
    time.sleep(processing_time)
    
    # Generate processing result
    result = {
        'processId': process_data.get('processId', 'unknown'),
        'processType': process_type,
        'status': 'processed',
        'timestamp': datetime.utcnow().isoformat(),
        'result': f"Successfully processed {process_type} business process"
    }
    
    return {
        'statusCode': 200,
        'body': json.dumps(result),
        'processResult': result
    }
EOF

    # Create deployment package
    cd /tmp
    zip business-processor.zip business-processor.py
    cd - > /dev/null
    
    # Check if Lambda function already exists
    if aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME} &> /dev/null; then
        log_warning "Lambda function already exists, updating code..."
        aws lambda update-function-code \
            --function-name ${LAMBDA_FUNCTION_NAME} \
            --zip-file fileb:///tmp/business-processor.zip
    else
        # Create Lambda function
        aws lambda create-function \
            --function-name ${LAMBDA_FUNCTION_NAME} \
            --runtime python3.9 \
            --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME} \
            --handler business-processor.lambda_handler \
            --zip-file fileb:///tmp/business-processor.zip \
            --timeout 30 \
            --description "Business process automation Lambda function"
    fi
    
    export LAMBDA_FUNCTION_ARN=$(aws lambda get-function \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --query 'Configuration.FunctionArn' --output text)
    
    log_success "Lambda function created: ${LAMBDA_FUNCTION_NAME}"
}

# Function to create SQS queue
create_sqs_queue() {
    log_info "Creating SQS queue..."
    
    # Create SQS queue
    aws sqs create-queue \
        --queue-name ${SQS_QUEUE_NAME} \
        --attributes VisibilityTimeoutSeconds=300 &> /dev/null || true
    
    export SQS_QUEUE_URL=$(aws sqs get-queue-url \
        --queue-name ${SQS_QUEUE_NAME} \
        --query 'QueueUrl' --output text)
    
    export SQS_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url ${SQS_QUEUE_URL} \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)
    
    log_success "SQS queue created: ${SQS_QUEUE_NAME}"
}

# Function to create SNS topic
create_sns_topic() {
    log_info "Creating SNS topic..."
    
    # Create SNS topic
    aws sns create-topic --name ${SNS_TOPIC_NAME} > /dev/null
    
    export SNS_TOPIC_ARN=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
        --output text)
    
    log_success "SNS topic created: ${SNS_TOPIC_NAME}"
    log_info "SNS Topic ARN: ${SNS_TOPIC_ARN}"
    
    # Prompt for email subscription
    read -p "Enter email address for notifications (or press Enter to skip): " EMAIL_ADDRESS
    if [ ! -z "$EMAIL_ADDRESS" ]; then
        aws sns subscribe \
            --topic-arn ${SNS_TOPIC_ARN} \
            --protocol email \
            --notification-endpoint ${EMAIL_ADDRESS}
        log_info "Email subscription added. Please check your email and confirm the subscription."
    fi
}

# Function to create API Gateway
create_api_gateway() {
    log_info "Creating API Gateway..."
    
    # Create API Gateway
    aws apigateway create-rest-api \
        --name ${API_NAME} \
        --description "API for business process approvals" > /dev/null
    
    export API_ID=$(aws apigateway get-rest-apis \
        --query "items[?name=='${API_NAME}'].id" \
        --output text)
    
    # Get root resource ID
    export ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id ${API_ID} \
        --query 'items[?path==`/`].id' --output text)
    
    # Create approval resource
    aws apigateway create-resource \
        --rest-api-id ${API_ID} \
        --parent-id ${ROOT_RESOURCE_ID} \
        --path-part approval > /dev/null
    
    export APPROVAL_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id ${API_ID} \
        --query "items[?pathPart=='approval'].id" --output text)
    
    log_success "API Gateway created: ${API_NAME}"
}

# Function to configure Step Functions permissions
configure_stepfunctions_permissions() {
    log_info "Configuring Step Functions permissions..."
    
    # Create policy for Step Functions execution
    cat > /tmp/stepfunctions-execution-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction",
        "sns:Publish",
        "sqs:SendMessage"
      ],
      "Resource": [
        "${LAMBDA_FUNCTION_ARN}",
        "${SNS_TOPIC_ARN}",
        "${SQS_QUEUE_ARN}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF

    # Attach policy to Step Functions role
    aws iam put-role-policy \
        --role-name ${STEPFUNCTIONS_ROLE_NAME} \
        --policy-name StepFunctionsExecutionPolicy \
        --policy-document file:///tmp/stepfunctions-execution-policy.json
    
    export STEPFUNCTIONS_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${STEPFUNCTIONS_ROLE_NAME}"
    
    log_success "Step Functions permissions configured"
}

# Function to create Step Functions state machine
create_state_machine() {
    log_info "Creating Step Functions state machine..."
    
    # Create state machine definition
    cat > /tmp/business-process-state-machine.json << EOF
{
  "Comment": "Business Process Automation Workflow",
  "StartAt": "ValidateInput",
  "States": {
    "ValidateInput": {
      "Type": "Pass",
      "Parameters": {
        "processData.\$": "\$.processData",
        "validationResult": "Input validated successfully"
      },
      "Next": "ProcessBusinessLogic"
    },
    "ProcessBusinessLogic": {
      "Type": "Task",
      "Resource": "${LAMBDA_FUNCTION_ARN}",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 5,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ProcessingFailed"
        }
      ],
      "Next": "HumanApprovalRequired"
    },
    "HumanApprovalRequired": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish.waitForTaskToken",
      "Parameters": {
        "TopicArn": "${SNS_TOPIC_ARN}",
        "Message": {
          "processId.\$": "\$.processResult.processId",
          "processType.\$": "\$.processResult.processType",
          "approvalRequired": "Please approve this business process",
          "taskToken.\$": "\$\$.Task.Token"
        },
        "Subject": "Business Process Approval Required"
      },
      "HeartbeatSeconds": 3600,
      "TimeoutSeconds": 86400,
      "Next": "SendCompletionNotification"
    },
    "SendCompletionNotification": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "${SNS_TOPIC_ARN}",
        "Message": {
          "processId.\$": "\$.processResult.processId",
          "status": "completed",
          "message": "Business process completed successfully"
        },
        "Subject": "Business Process Completed"
      },
      "Next": "LogToQueue"
    },
    "LogToQueue": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sqs:sendMessage",
      "Parameters": {
        "QueueUrl": "${SQS_QUEUE_URL}",
        "MessageBody": {
          "processId.\$": "\$.processResult.processId",
          "completionTime.\$": "\$\$.State.EnteredTime",
          "status": "completed"
        }
      },
      "End": true
    },
    "ProcessingFailed": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "${SNS_TOPIC_ARN}",
        "Message": {
          "error": "Business process failed",
          "details.\$": "\$.Error"
        },
        "Subject": "Business Process Failed"
      },
      "End": true
    }
  }
}
EOF

    # Wait for permissions to propagate
    log_info "Waiting for permissions to propagate..."
    sleep 15
    
    # Create Step Functions state machine
    if aws stepfunctions describe-state-machine --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" &> /dev/null; then
        log_warning "State machine already exists, updating definition..."
        aws stepfunctions update-state-machine \
            --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
            --definition file:///tmp/business-process-state-machine.json
    else
        aws stepfunctions create-state-machine \
            --name ${STATE_MACHINE_NAME} \
            --definition file:///tmp/business-process-state-machine.json \
            --role-arn ${STEPFUNCTIONS_ROLE_ARN}
    fi
    
    export STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?name=='${STATE_MACHINE_NAME}'].stateMachineArn" \
        --output text)
    
    log_success "Step Functions state machine created: ${STATE_MACHINE_NAME}"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing the deployment..."
    
    # Create test input
    cat > /tmp/test-input.json << 'EOF'
{
  "processData": {
    "processId": "BP-001",
    "type": "expense-approval",
    "amount": 5000,
    "requestor": "john.doe@company.com",
    "description": "Software licensing renewal",
    "processingTime": 1
  }
}
EOF

    # Start test execution
    EXECUTION_ARN=$(aws stepfunctions start-execution \
        --state-machine-arn ${STATE_MACHINE_ARN} \
        --name "test-execution-$(date +%s)" \
        --input file:///tmp/test-input.json \
        --query 'executionArn' --output text)
    
    log_success "Test execution started: ${EXECUTION_ARN}"
    
    # Wait a moment and check status
    sleep 5
    EXECUTION_STATUS=$(aws stepfunctions describe-execution \
        --execution-arn ${EXECUTION_ARN} \
        --query 'status' --output text)
    
    log_info "Test execution status: ${EXECUTION_STATUS}"
    
    if [ "$EXECUTION_STATUS" = "RUNNING" ] || [ "$EXECUTION_STATUS" = "WAITING_FOR_CALLBACK" ]; then
        log_success "Test execution is running successfully"
    else
        log_warning "Test execution status: ${EXECUTION_STATUS}"
    fi
}

# Function to output deployment information
output_deployment_info() {
    log_info "Deployment completed successfully!"
    echo ""
    echo "=== Deployment Information ==="
    echo "AWS Region: ${AWS_REGION}"
    echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
    echo "Resource Prefix: ${BUSINESS_PROCESS_PREFIX}"
    echo ""
    echo "=== Created Resources ==="
    echo "State Machine Name: ${STATE_MACHINE_NAME}"
    echo "State Machine ARN: ${STATE_MACHINE_ARN}"
    echo "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "Lambda Function ARN: ${LAMBDA_FUNCTION_ARN}"
    echo "SQS Queue: ${SQS_QUEUE_NAME}"
    echo "SQS Queue URL: ${SQS_QUEUE_URL}"
    echo "SNS Topic: ${SNS_TOPIC_NAME}"
    echo "SNS Topic ARN: ${SNS_TOPIC_ARN}"
    echo "API Gateway: ${API_NAME}"
    echo "API Gateway ID: ${API_ID}"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Confirm your email subscription to the SNS topic if you provided one"
    echo "2. Test the workflow using the AWS Step Functions console"
    echo "3. Monitor executions and logs in CloudWatch"
    echo ""
    echo "=== Cleanup ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo ""
    
    # Save deployment info to file
    cat > deployment-info.txt << EOF
# Business Process Automation Deployment Information
# Generated on: $(date)

AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
BUSINESS_PROCESS_PREFIX=${BUSINESS_PROCESS_PREFIX}
STATE_MACHINE_NAME=${STATE_MACHINE_NAME}
STATE_MACHINE_ARN=${STATE_MACHINE_ARN}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
LAMBDA_FUNCTION_ARN=${LAMBDA_FUNCTION_ARN}
SQS_QUEUE_NAME=${SQS_QUEUE_NAME}
SQS_QUEUE_URL=${SQS_QUEUE_URL}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
SNS_TOPIC_ARN=${SNS_TOPIC_ARN}
API_NAME=${API_NAME}
API_ID=${API_ID}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
STEPFUNCTIONS_ROLE_NAME=${STEPFUNCTIONS_ROLE_NAME}
EOF
    
    log_success "Deployment information saved to deployment-info.txt"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/stepfunctions-trust-policy.json
    rm -f /tmp/business-processor.py
    rm -f /tmp/business-processor.zip
    rm -f /tmp/stepfunctions-execution-policy.json
    rm -f /tmp/business-process-state-machine.json
    rm -f /tmp/test-input.json
}

# Main deployment function
main() {
    echo "=== Business Process Automation with Step Functions - Deployment ==="
    echo ""
    
    # Set trap for cleanup on exit
    trap cleanup_temp_files EXIT
    
    check_prerequisites
    setup_environment
    create_iam_roles
    create_lambda_function
    create_sqs_queue
    create_sns_topic
    create_api_gateway
    configure_stepfunctions_permissions
    create_state_machine
    test_deployment
    output_deployment_info
    
    log_success "Deployment completed successfully!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi