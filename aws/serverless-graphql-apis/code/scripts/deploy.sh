#!/bin/bash

# Deploy script for Serverless GraphQL APIs with AWS AppSync and EventBridge Scheduler
# This script deploys the complete infrastructure for the task management system
# Author: AWS Recipe Generator v1.3
# Last Updated: 2025-07-12

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version=$(echo $aws_version | cut -d. -f1)
    if [ "$major_version" -lt 2 ]; then
        log_warning "AWS CLI v1 detected. AWS CLI v2 is recommended for best compatibility."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set up IAM roles."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$account_id" ]; then
        log_error "Unable to retrieve AWS account ID. Check your credentials."
        exit 1
    fi
    
    # Check for required tools
    if ! command -v zip &> /dev/null; then
        log_error "zip command not found. Please install zip utility."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region not set. Set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export API_NAME="TaskManagerAPI-${RANDOM_SUFFIX}"
    export TABLE_NAME="Tasks-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="TaskProcessor-${RANDOM_SUFFIX}"
    export SCHEDULER_ROLE="SchedulerRole-${RANDOM_SUFFIX}"
    export APPSYNC_ROLE="AppSyncRole-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE="LambdaRole-${RANDOM_SUFFIX}"
    
    # Create working directory
    export WORK_DIR="./task-manager-api-${RANDOM_SUFFIX}"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # Store deployment info for cleanup
    cat > deployment-info.env << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
API_NAME=$API_NAME
TABLE_NAME=$TABLE_NAME
FUNCTION_NAME=$FUNCTION_NAME
SCHEDULER_ROLE=$SCHEDULER_ROLE
APPSYNC_ROLE=$APPSYNC_ROLE
LAMBDA_ROLE=$LAMBDA_ROLE
WORK_DIR=$WORK_DIR
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    log_success "Environment setup completed with suffix: ${RANDOM_SUFFIX}"
}

# Function to create DynamoDB table
create_dynamodb_table() {
    log_info "Creating DynamoDB table: ${TABLE_NAME}..."
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name "${TABLE_NAME}" &>/dev/null; then
        log_warning "DynamoDB table ${TABLE_NAME} already exists, skipping creation"
        return 0
    fi
    
    aws dynamodb create-table \
        --table-name "${TABLE_NAME}" \
        --attribute-definitions \
            AttributeName=id,AttributeType=S \
            AttributeName=userId,AttributeType=S \
        --key-schema \
            AttributeName=id,KeyType=HASH \
        --global-secondary-indexes \
            "IndexName=UserIdIndex,KeySchema=[{AttributeName=userId,KeyType=HASH}],Projection={ProjectionType=ALL}" \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Project,Value=TaskManager,Key=DeployedBy,Value=RecipeScript
    
    # Wait for table to be active
    log_info "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name "${TABLE_NAME}"
    
    log_success "DynamoDB table ${TABLE_NAME} created successfully"
}

# Function to create IAM roles
create_iam_roles() {
    log_info "Creating IAM roles..."
    
    # AppSync role trust policy
    cat > appsync-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "appsync.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}
EOF
    
    # Create AppSync IAM role
    if ! aws iam get-role --role-name "${APPSYNC_ROLE}" &>/dev/null; then
        aws iam create-role \
            --role-name "${APPSYNC_ROLE}" \
            --assume-role-policy-document file://appsync-trust-policy.json \
            --tags Key=Project,Value=TaskManager,Key=DeployedBy,Value=RecipeScript
        
        # Attach DynamoDB policy
        cat > appsync-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ],
    "Resource": [
      "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${TABLE_NAME}",
      "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${TABLE_NAME}/index/*"
    ]
  }]
}
EOF
        
        aws iam put-role-policy \
            --role-name "${APPSYNC_ROLE}" \
            --policy-name DynamoDBAccess \
            --policy-document file://appsync-policy.json
    else
        log_warning "AppSync IAM role ${APPSYNC_ROLE} already exists"
    fi
    
    # Lambda role trust policy
    cat > lambda-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "lambda.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}
EOF
    
    # Create Lambda IAM role
    if ! aws iam get-role --role-name "${LAMBDA_ROLE}" &>/dev/null; then
        aws iam create-role \
            --role-name "${LAMBDA_ROLE}" \
            --assume-role-policy-document file://lambda-trust-policy.json \
            --tags Key=Project,Value=TaskManager,Key=DeployedBy,Value=RecipeScript
        
        # Attach basic execution policy
        aws iam attach-role-policy \
            --role-name "${LAMBDA_ROLE}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    else
        log_warning "Lambda IAM role ${LAMBDA_ROLE} already exists"
    fi
    
    # Scheduler role trust policy
    cat > scheduler-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "scheduler.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}
EOF
    
    # Create Scheduler IAM role
    if ! aws iam get-role --role-name "${SCHEDULER_ROLE}" &>/dev/null; then
        aws iam create-role \
            --role-name "${SCHEDULER_ROLE}" \
            --assume-role-policy-document file://scheduler-trust-policy.json \
            --tags Key=Project,Value=TaskManager,Key=DeployedBy,Value=RecipeScript
    else
        log_warning "Scheduler IAM role ${SCHEDULER_ROLE} already exists"
    fi
    
    # Wait for IAM role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
    
    log_success "IAM roles created successfully"
}

# Function to create GraphQL schema
create_graphql_schema() {
    log_info "Creating GraphQL schema..."
    
    cat > schema.graphql << 'EOF'
type Task {
  id: ID!
  userId: String!
  title: String!
  description: String
  dueDate: String!
  status: TaskStatus!
  reminderTime: String
  createdAt: String!
  updatedAt: String!
}

enum TaskStatus {
  PENDING
  IN_PROGRESS
  COMPLETED
  CANCELLED
}

input CreateTaskInput {
  title: String!
  description: String
  dueDate: String!
  reminderTime: String
}

input UpdateTaskInput {
  id: ID!
  title: String
  description: String
  status: TaskStatus
  dueDate: String
  reminderTime: String
}

type Query {
  getTask(id: ID!): Task
  listUserTasks(userId: String!): [Task]
}

type Mutation {
  createTask(input: CreateTaskInput!): Task
  updateTask(input: UpdateTaskInput!): Task
  deleteTask(id: ID!): Task
  sendReminder(taskId: ID!): Task
}

type Subscription {
  onTaskCreated(userId: String!): Task
    @aws_subscribe(mutations: ["createTask"])
  onTaskUpdated(userId: String!): Task
    @aws_subscribe(mutations: ["updateTask", "sendReminder"])
  onTaskDeleted(userId: String!): Task
    @aws_subscribe(mutations: ["deleteTask"])
}

schema {
  query: Query
  mutation: Mutation
  subscription: Subscription
}
EOF
    
    log_success "GraphQL schema created"
}

# Function to create AppSync API
create_appsync_api() {
    log_info "Creating AppSync GraphQL API..."
    
    # Create AppSync API
    API_ID=$(aws appsync create-graphql-api \
        --name "${API_NAME}" \
        --authentication-type AWS_IAM \
        --tags Project=TaskManager,DeployedBy=RecipeScript \
        --query graphqlApi.apiId \
        --output text)
    
    if [ -z "$API_ID" ]; then
        log_error "Failed to create AppSync API"
        exit 1
    fi
    
    # Store API ID for later use
    echo "API_ID=$API_ID" >> deployment-info.env
    export API_ID
    
    # Get API details
    API_URL=$(aws appsync get-graphql-api \
        --api-id "${API_ID}" \
        --query graphqlApi.uris.GRAPHQL \
        --output text)
    
    API_ARN=$(aws appsync get-graphql-api \
        --api-id "${API_ID}" \
        --query graphqlApi.arn \
        --output text)
    
    echo "API_URL=$API_URL" >> deployment-info.env
    echo "API_ARN=$API_ARN" >> deployment-info.env
    export API_URL API_ARN
    
    # Start schema creation
    aws appsync start-schema-creation \
        --api-id "${API_ID}" \
        --definition fileb://schema.graphql
    
    # Wait for schema creation
    log_info "Waiting for schema creation..."
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        STATUS=$(aws appsync get-schema-creation-status \
            --api-id "${API_ID}" \
            --query status --output text)
        
        if [ "$STATUS" = "SUCCESS" ]; then
            break
        elif [ "$STATUS" = "FAILED" ]; then
            log_error "Schema creation failed"
            exit 1
        fi
        
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log_error "Schema creation timeout"
        exit 1
    fi
    
    log_success "AppSync API created: ${API_URL}"
}

# Function to configure data source and resolvers
configure_appsync_resolvers() {
    log_info "Configuring AppSync data source and resolvers..."
    
    # Get AppSync role ARN
    APPSYNC_ROLE_ARN=$(aws iam get-role \
        --role-name "${APPSYNC_ROLE}" \
        --query Role.Arn --output text)
    
    # Create DynamoDB data source
    aws appsync create-data-source \
        --api-id "${API_ID}" \
        --name TasksDataSource \
        --type AMAZON_DYNAMODB \
        --dynamodb-config \
            "tableName=${TABLE_NAME},awsRegion=${AWS_REGION}" \
        --service-role-arn "${APPSYNC_ROLE_ARN}"
    
    # Create VTL templates for createTask resolver
    cat > create-task-request.vtl << 'EOF'
#set($id = $util.autoId())
{
  "version": "2017-02-28",
  "operation": "PutItem",
  "key": {
    "id": $util.dynamodb.toDynamoDBJson($id)
  },
  "attributeValues": {
    "userId": $util.dynamodb.toDynamoDBJson($ctx.identity.userArn),
    "title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
    "description": $util.dynamodb.toDynamoDBJson($ctx.args.input.description),
    "dueDate": $util.dynamodb.toDynamoDBJson($ctx.args.input.dueDate),
    "status": $util.dynamodb.toDynamoDBJson("PENDING"),
    "reminderTime": $util.dynamodb.toDynamoDBJson($ctx.args.input.reminderTime),
    "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
    "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
  }
}
EOF
    
    cat > response.vtl << 'EOF'
$util.toJson($ctx.result)
EOF
    
    # Create resolver
    aws appsync create-resolver \
        --api-id "${API_ID}" \
        --type-name Mutation \
        --field-name createTask \
        --data-source-name TasksDataSource \
        --request-mapping-template file://create-task-request.vtl \
        --response-mapping-template file://response.vtl
    
    log_success "Data source and resolvers configured"
}

# Function to create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function..."
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

appsync = boto3.client('appsync')

def lambda_handler(event, context):
    """Process scheduled task reminders from EventBridge"""
    print(f"Received event: {json.dumps(event)}")
    
    # Extract task ID from event
    task_id = event.get('taskId')
    if not task_id:
        raise ValueError("No taskId provided in event")
    
    # Prepare GraphQL mutation
    mutation = """
    mutation SendReminder($taskId: ID!) {
        sendReminder(taskId: $taskId) {
            id
            title
            status
        }
    }
    """
    
    # Execute mutation via AppSync
    try:
        response = appsync.graphql(
            apiId=os.environ['API_ID'],
            query=mutation,
            variables={'taskId': task_id}
        )
        
        print(f"Reminder sent successfully: {response}")
        return {
            'statusCode': 200,
            'body': json.dumps('Reminder sent successfully')
        }
    except Exception as e:
        print(f"Error sending reminder: {str(e)}")
        raise
EOF
    
    # Create deployment package
    zip -q function.zip lambda_function.py
    
    # Get Lambda role ARN
    LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "${LAMBDA_ROLE}" \
        --query Role.Arn --output text)
    
    # Create Lambda function
    LAMBDA_ARN=$(aws lambda create-function \
        --function-name "${FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://function.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables="{API_ID=${API_ID}}" \
        --tags Project=TaskManager,DeployedBy=RecipeScript \
        --query FunctionArn --output text)
    
    echo "LAMBDA_ARN=$LAMBDA_ARN" >> deployment-info.env
    export LAMBDA_ARN
    
    log_success "Lambda function created: ${FUNCTION_NAME}"
}

# Function to configure EventBridge Scheduler
configure_eventbridge_scheduler() {
    log_info "Configuring EventBridge Scheduler..."
    
    # Get Scheduler role ARN
    SCHEDULER_ROLE_ARN=$(aws iam get-role \
        --role-name "${SCHEDULER_ROLE}" \
        --query Role.Arn --output text)
    
    # Create policy for AppSync invocation
    cat > scheduler-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "appsync:GraphQL",
    "Resource": "${API_ARN}/*"
  }]
}
EOF
    
    aws iam put-role-policy \
        --role-name "${SCHEDULER_ROLE}" \
        --policy-name AppSyncAccess \
        --policy-document file://scheduler-policy.json
    
    echo "SCHEDULER_ROLE_ARN=$SCHEDULER_ROLE_ARN" >> deployment-info.env
    export SCHEDULER_ROLE_ARN
    
    log_success "EventBridge Scheduler configured"
}

# Function to run validation tests
run_validation() {
    log_info "Running validation tests..."
    
    # Test API endpoint connectivity
    local endpoint_status=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${API_URL}" \
        -H "Content-Type: application/json" \
        --data '{"query":"{ __typename }"}' \
        --aws-sigv4 "aws:amz:${AWS_REGION}:appsync" || echo "000")
    
    if [ "$endpoint_status" = "200" ] || [ "$endpoint_status" = "400" ]; then
        log_success "AppSync API endpoint is accessible"
    else
        log_warning "AppSync API endpoint test returned status: $endpoint_status"
    fi
    
    # Verify DynamoDB table
    local table_status=$(aws dynamodb describe-table \
        --table-name "${TABLE_NAME}" \
        --query Table.TableStatus --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$table_status" = "ACTIVE" ]; then
        log_success "DynamoDB table is active"
    else
        log_warning "DynamoDB table status: $table_status"
    fi
    
    # Verify Lambda function
    local function_status=$(aws lambda get-function \
        --function-name "${FUNCTION_NAME}" \
        --query Configuration.State --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$function_status" = "Active" ]; then
        log_success "Lambda function is active"
    else
        log_warning "Lambda function status: $function_status"
    fi
    
    log_success "Validation completed"
}

# Function to display deployment summary
show_deployment_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "API Name: ${API_NAME}"
    echo "API URL: ${API_URL}"
    echo "API ID: ${API_ID}"
    echo "DynamoDB Table: ${TABLE_NAME}"
    echo "Lambda Function: ${FUNCTION_NAME}"
    echo "Region: ${AWS_REGION}"
    echo "Working Directory: ${WORK_DIR}"
    echo
    echo "=== Next Steps ==="
    echo "1. Test your GraphQL API using the AWS AppSync console"
    echo "2. Create scheduled reminders using EventBridge Scheduler"
    echo "3. Implement client applications using the GraphQL endpoint"
    echo "4. Monitor your resources in the AWS console"
    echo
    echo "=== Cleanup ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo "Make sure to save the deployment-info.env file for cleanup"
    echo
}

# Main deployment function
main() {
    log_info "Starting deployment of Serverless GraphQL APIs with AppSync and EventBridge Scheduler"
    
    check_prerequisites
    setup_environment
    create_dynamodb_table
    create_iam_roles
    create_graphql_schema
    create_appsync_api
    configure_appsync_resolvers
    create_lambda_function
    configure_eventbridge_scheduler
    run_validation
    show_deployment_summary
    
    log_success "Deployment script completed successfully!"
}

# Handle script interruption
cleanup_on_error() {
    log_error "Deployment interrupted or failed"
    log_info "You may need to manually clean up partially created resources"
    log_info "Check the AWS console and use the destroy.sh script if needed"
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR INT TERM

# Run main function
main "$@"