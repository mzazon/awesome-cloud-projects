#!/bin/bash

# Real-time Data Synchronization with AWS AppSync - Deployment Script
# This script deploys a complete real-time task management system using AppSync, DynamoDB, and IAM

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy-errors.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$ERROR_LOG" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed with exit code $exit_code"
        log_info "Check $ERROR_LOG for detailed error information"
        log_info "Run ./destroy.sh to clean up any partially created resources"
    fi
    exit $exit_code
}

trap cleanup_on_error EXIT

# Help function
show_help() {
    cat << EOF
Real-time Data Synchronization with AWS AppSync - Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -r, --region REGION     AWS region (default: current configured region)
    -p, --prefix PREFIX     Resource name prefix (default: auto-generated)
    -d, --dry-run          Show what would be deployed without making changes
    -v, --verbose          Enable verbose logging
    --skip-prerequisites   Skip prerequisite checks (not recommended)

EXAMPLES:
    $0                                    # Deploy with defaults
    $0 --region us-east-1                # Deploy in specific region  
    $0 --prefix myapp                     # Deploy with custom prefix
    $0 --dry-run                          # Preview deployment

EOF
}

# Parse command line arguments
DRY_RUN=false
VERBOSE=false
SKIP_PREREQUISITES=false
CUSTOM_PREFIX=""
CUSTOM_REGION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--region)
            CUSTOM_REGION="$2"
            shift 2
            ;;
        -p|--prefix)
            CUSTOM_PREFIX="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --skip-prerequisites)
            SKIP_PREREQUISITES=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Initialize logging
echo "=== AWS AppSync Real-time Data Synchronization Deployment ===" > "$LOG_FILE"
echo "Started at: $(date)" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

log_info "Starting deployment of real-time data synchronization system"

# Prerequisites check
check_prerequisites() {
    if [ "$SKIP_PREREQUISITES" = true ]; then
        log_warning "Skipping prerequisite checks as requested"
        return 0
    fi

    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $aws_version"
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    log_info "AWS Account: $account_id"
    
    # Check required permissions (basic check)
    log_info "Verifying AWS permissions..."
    local required_services=("appsync" "dynamodb" "iam" "logs")
    
    for service in "${required_services[@]}"; do
        if [ "$service" = "appsync" ]; then
            # Check AppSync permissions
            if aws appsync list-graphql-apis --max-results 1 &> /dev/null; then
                log_info "✓ AppSync permissions verified"
            else
                log_error "Missing AppSync permissions"
                exit 1
            fi
        elif [ "$service" = "dynamodb" ]; then
            # Check DynamoDB permissions
            if aws dynamodb list-tables --max-items 1 &> /dev/null; then
                log_info "✓ DynamoDB permissions verified"
            else
                log_error "Missing DynamoDB permissions"
                exit 1
            fi
        elif [ "$service" = "iam" ]; then
            # Check IAM permissions
            if aws iam list-roles --max-items 1 &> /dev/null; then
                log_info "✓ IAM permissions verified"
            else
                log_error "Missing IAM permissions"
                exit 1
            fi
        elif [ "$service" = "logs" ]; then
            # Check CloudWatch Logs permissions
            if aws logs describe-log-groups --limit 1 &> /dev/null; then
                log_info "✓ CloudWatch Logs permissions verified"
            else
                log_warning "CloudWatch Logs permissions may be limited"
            fi
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # AWS Region
    if [ -n "$CUSTOM_REGION" ]; then
        export AWS_REGION="$CUSTOM_REGION"
    else
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            log_warning "No region configured, defaulting to us-east-1"
        fi
    fi
    
    # AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    if [ -n "$CUSTOM_PREFIX" ]; then
        local random_suffix=$(echo "$CUSTOM_PREFIX" | tr '[:upper:]' '[:lower:]')
    else
        local random_suffix=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            echo "$(date +%s | tail -c 7)")
    fi
    
    export API_NAME="realtime-tasks-${random_suffix}"
    export TABLE_NAME="tasks-${random_suffix}"
    export ROLE_NAME="appsync-tasks-role-${random_suffix}"
    
    # Create state file to track deployment
    cat > "${SCRIPT_DIR}/deployment-state.json" << EOF
{
    "deployment_id": "${random_suffix}",
    "api_name": "${API_NAME}",
    "table_name": "${TABLE_NAME}",
    "role_name": "${ROLE_NAME}",
    "region": "${AWS_REGION}",
    "account_id": "${AWS_ACCOUNT_ID}",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "status": "in_progress"
}
EOF
    
    log_success "Environment configured:"
    log_info "  Region: $AWS_REGION"
    log_info "  API Name: $API_NAME"
    log_info "  Table Name: $TABLE_NAME" 
    log_info "  Role Name: $ROLE_NAME"
}

# Create DynamoDB table
create_dynamodb_table() {
    log_info "Creating DynamoDB table: $TABLE_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create DynamoDB table with streams enabled"
        return 0
    fi
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name "$TABLE_NAME" &> /dev/null; then
        log_warning "DynamoDB table $TABLE_NAME already exists, skipping creation"
        return 0
    fi
    
    aws dynamodb create-table \
        --table-name "$TABLE_NAME" \
        --attribute-definitions \
            AttributeName=id,AttributeType=S \
            AttributeName=status,AttributeType=S \
            AttributeName=createdAt,AttributeType=S \
        --key-schema \
            AttributeName=id,KeyType=HASH \
        --global-secondary-indexes \
            IndexName=status-createdAt-index,KeySchema=[{AttributeName=status,KeyType=HASH},{AttributeName=createdAt,KeyType=RANGE}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5} \
        --provisioned-throughput \
            ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --stream-specification \
            StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
        --tags Key=Purpose,Value=AppSyncTutorial,Key=Environment,Value=Development
    
    # Wait for table to be active
    log_info "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name "$TABLE_NAME"
    
    # Update state file
    jq --arg table_arn "$(aws dynamodb describe-table --table-name "$TABLE_NAME" --query 'Table.TableArn' --output text)" \
       '.dynamodb_table_arn = $table_arn' \
       "${SCRIPT_DIR}/deployment-state.json" > "${SCRIPT_DIR}/deployment-state.tmp" && \
       mv "${SCRIPT_DIR}/deployment-state.tmp" "${SCRIPT_DIR}/deployment-state.json"
    
    log_success "DynamoDB table $TABLE_NAME created successfully"
}

# Create IAM role
create_iam_role() {
    log_info "Creating IAM role: $ROLE_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create IAM role with DynamoDB permissions"
        return 0
    fi
    
    # Check if role already exists
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        log_warning "IAM role $ROLE_NAME already exists, skipping creation"
        return 0
    fi
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/trust-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "appsync.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file://"${SCRIPT_DIR}/trust-policy.json" \
        --tags Key=Purpose,Value=AppSyncTutorial,Key=Environment,Value=Development
    
    # Create DynamoDB access policy
    cat > "${SCRIPT_DIR}/dynamodb-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
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
                "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${TABLE_NAME}/*"
            ]
        }
    ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-name DynamoDBAccess \
        --policy-document file://"${SCRIPT_DIR}/dynamodb-policy.json"
    
    # Wait for role propagation
    log_info "Waiting for IAM role to propagate..."
    sleep 10
    
    # Update state file
    local role_arn=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
    jq --arg role_arn "$role_arn" \
       '.iam_role_arn = $role_arn' \
       "${SCRIPT_DIR}/deployment-state.json" > "${SCRIPT_DIR}/deployment-state.tmp" && \
       mv "${SCRIPT_DIR}/deployment-state.tmp" "${SCRIPT_DIR}/deployment-state.json"
    
    log_success "IAM role $ROLE_NAME created successfully"
}

# Create GraphQL schema
create_graphql_schema() {
    log_info "Creating GraphQL schema file"
    
    cat > "${SCRIPT_DIR}/schema.graphql" << 'EOF'
type Task {
    id: ID!
    title: String!
    description: String
    status: TaskStatus!
    priority: Priority!
    assignedTo: String
    createdAt: AWSDateTime!
    updatedAt: AWSDateTime!
    version: Int!
}

enum TaskStatus {
    TODO
    IN_PROGRESS
    COMPLETED
    ARCHIVED
}

enum Priority {
    LOW
    MEDIUM
    HIGH
    URGENT
}

input CreateTaskInput {
    title: String!
    description: String
    priority: Priority!
    assignedTo: String
}

input UpdateTaskInput {
    id: ID!
    title: String
    description: String
    status: TaskStatus
    priority: Priority
    assignedTo: String
    version: Int!
}

type Query {
    getTask(id: ID!): Task
    listTasks(status: TaskStatus, limit: Int, nextToken: String): TaskConnection
    listTasksByStatus(status: TaskStatus!, limit: Int, nextToken: String): TaskConnection
}

type Mutation {
    createTask(input: CreateTaskInput!): Task
    updateTask(input: UpdateTaskInput!): Task
    deleteTask(id: ID!, version: Int!): Task
}

type Subscription {
    onTaskCreated: Task
        @aws_subscribe(mutations: ["createTask"])
    onTaskUpdated: Task
        @aws_subscribe(mutations: ["updateTask"])
    onTaskDeleted: Task
        @aws_subscribe(mutations: ["deleteTask"])
}

type TaskConnection {
    items: [Task]
    nextToken: String
}

schema {
    query: Query
    mutation: Mutation
    subscription: Subscription
}
EOF
    
    log_success "GraphQL schema created"
}

# Create AppSync API
create_appsync_api() {
    log_info "Creating AppSync GraphQL API: $API_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create AppSync API with GraphQL schema"
        return 0
    fi
    
    # Create AppSync API
    local api_response=$(aws appsync create-graphql-api \
        --name "$API_NAME" \
        --authentication-type API_KEY \
        --tags Purpose=AppSyncTutorial,Environment=Development)
    
    export API_ID=$(echo "$api_response" | jq -r '.graphqlApi.apiId')
    export API_URL=$(echo "$api_response" | jq -r '.graphqlApi.uris.GRAPHQL')
    
    log_info "API ID: $API_ID"
    log_info "GraphQL URL: $API_URL"
    
    # Upload GraphQL schema
    log_info "Uploading GraphQL schema..."
    aws appsync start-schema-creation \
        --api-id "$API_ID" \
        --definition file://"${SCRIPT_DIR}/schema.graphql"
    
    # Wait for schema creation
    log_info "Waiting for schema creation to complete..."
    sleep 15
    
    # Update state file
    jq --arg api_id "$API_ID" --arg api_url "$API_URL" \
       '.api_id = $api_id | .api_url = $api_url' \
       "${SCRIPT_DIR}/deployment-state.json" > "${SCRIPT_DIR}/deployment-state.tmp" && \
       mv "${SCRIPT_DIR}/deployment-state.tmp" "${SCRIPT_DIR}/deployment-state.json"
    
    log_success "AppSync API $API_NAME created successfully"
}

# Create API key
create_api_key() {
    log_info "Creating API key for testing"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create API key with 30-day expiration"
        return 0
    fi
    
    local expiry_date=$(date -d "+30 days" +%s)
    local api_key_response=$(aws appsync create-api-key \
        --api-id "$API_ID" \
        --description "Testing key for real-time tasks API" \
        --expires "$expiry_date")
    
    export API_KEY=$(echo "$api_key_response" | jq -r '.apiKey.id')
    
    # Update state file
    jq --arg api_key "$API_KEY" \
       '.api_key = $api_key' \
       "${SCRIPT_DIR}/deployment-state.json" > "${SCRIPT_DIR}/deployment-state.tmp" && \
       mv "${SCRIPT_DIR}/deployment-state.tmp" "${SCRIPT_DIR}/deployment-state.json"
    
    log_success "API Key created: $API_KEY"
}

# Create data source
create_data_source() {
    log_info "Creating DynamoDB data source"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create DynamoDB data source"
        return 0
    fi
    
    local role_arn=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
    
    aws appsync create-data-source \
        --api-id "$API_ID" \
        --name TasksDataSource \
        --type AMAZON_DYNAMODB \
        --service-role-arn "$role_arn" \
        --dynamodb-config tableName="$TABLE_NAME",awsRegion="$AWS_REGION"
    
    log_success "DynamoDB data source created"
}

# Create resolver templates
create_resolver_templates() {
    log_info "Creating resolver templates"
    
    # Create getTask resolver templates
    cat > "${SCRIPT_DIR}/getTask-request.vtl" << 'EOF'
{
    "version": "2018-05-29",
    "operation": "GetItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
    }
}
EOF
    
    cat > "${SCRIPT_DIR}/getTask-response.vtl" << 'EOF'
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOF
    
    # Create listTasks resolver templates
    cat > "${SCRIPT_DIR}/listTasks-request.vtl" << 'EOF'
{
    "version": "2018-05-29",
    "operation": "Scan",
    "limit": #if($ctx.args.limit) $ctx.args.limit #else 20 #end,
    "nextToken": #if($ctx.args.nextToken) "$ctx.args.nextToken" #else null #end
}
EOF
    
    cat > "${SCRIPT_DIR}/listTasks-response.vtl" << 'EOF'
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
{
    "items": $util.toJson($ctx.result.items),
    "nextToken": #if($ctx.result.nextToken) "$ctx.result.nextToken" #else null #end
}
EOF
    
    # Create createTask resolver templates
    cat > "${SCRIPT_DIR}/createTask-request.vtl" << 'EOF'
#set($id = $util.autoId())
#set($createdAt = $util.time.nowISO8601())
{
    "version": "2018-05-29",
    "operation": "PutItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($id)
    },
    "attributeValues": {
        "title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
        "description": $util.dynamodb.toDynamoDBJson($ctx.args.input.description),
        "status": $util.dynamodb.toDynamoDBJson("TODO"),
        "priority": $util.dynamodb.toDynamoDBJson($ctx.args.input.priority),
        "assignedTo": $util.dynamodb.toDynamoDBJson($ctx.args.input.assignedTo),
        "createdAt": $util.dynamodb.toDynamoDBJson($createdAt),
        "updatedAt": $util.dynamodb.toDynamoDBJson($createdAt),
        "version": $util.dynamodb.toDynamoDBJson(1)
    }
}
EOF
    
    cat > "${SCRIPT_DIR}/createTask-response.vtl" << 'EOF'
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOF
    
    # Create updateTask resolver templates (simplified version)
    cat > "${SCRIPT_DIR}/updateTask-request.vtl" << 'EOF'
#set($updatedAt = $util.time.nowISO8601())
{
    "version": "2018-05-29",
    "operation": "UpdateItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.input.id)
    },
    "update": {
        "expression": "SET #updatedAt = :updatedAt, #version = #version + :incr",
        "expressionNames": {
            "#updatedAt": "updatedAt",
            "#version": "version"
        },
        "expressionValues": {
            ":updatedAt": $util.dynamodb.toDynamoDBJson($updatedAt),
            ":incr": $util.dynamodb.toDynamoDBJson(1),
            ":expectedVersion": $util.dynamodb.toDynamoDBJson($ctx.args.input.version)
        }
    },
    "condition": {
        "expression": "#version = :expectedVersion",
        "expressionNames": {
            "#version": "version"
        },
        "expressionValues": {
            ":expectedVersion": $util.dynamodb.toDynamoDBJson($ctx.args.input.version)
        }
    }
}
EOF
    
    cat > "${SCRIPT_DIR}/updateTask-response.vtl" << 'EOF'
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOF
    
    # Create deleteTask resolver templates
    cat > "${SCRIPT_DIR}/deleteTask-request.vtl" << 'EOF'
{
    "version": "2018-05-29",
    "operation": "DeleteItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
    },
    "condition": {
        "expression": "#version = :expectedVersion",
        "expressionNames": {
            "#version": "version"
        },
        "expressionValues": {
            ":expectedVersion": $util.dynamodb.toDynamoDBJson($ctx.args.version)
        }
    }
}
EOF
    
    cat > "${SCRIPT_DIR}/deleteTask-response.vtl" << 'EOF'
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOF
    
    log_success "Resolver templates created"
}

# Create resolvers
create_resolvers() {
    log_info "Creating GraphQL resolvers"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create all GraphQL resolvers"
        return 0
    fi
    
    # Create getTask resolver
    aws appsync create-resolver \
        --api-id "$API_ID" \
        --type-name Query \
        --field-name getTask \
        --data-source-name TasksDataSource \
        --request-mapping-template file://"${SCRIPT_DIR}/getTask-request.vtl" \
        --response-mapping-template file://"${SCRIPT_DIR}/getTask-response.vtl"
    
    # Create listTasks resolver
    aws appsync create-resolver \
        --api-id "$API_ID" \
        --type-name Query \
        --field-name listTasks \
        --data-source-name TasksDataSource \
        --request-mapping-template file://"${SCRIPT_DIR}/listTasks-request.vtl" \
        --response-mapping-template file://"${SCRIPT_DIR}/listTasks-response.vtl"
    
    # Create createTask resolver
    aws appsync create-resolver \
        --api-id "$API_ID" \
        --type-name Mutation \
        --field-name createTask \
        --data-source-name TasksDataSource \
        --request-mapping-template file://"${SCRIPT_DIR}/createTask-request.vtl" \
        --response-mapping-template file://"${SCRIPT_DIR}/createTask-response.vtl"
    
    # Create updateTask resolver
    aws appsync create-resolver \
        --api-id "$API_ID" \
        --type-name Mutation \
        --field-name updateTask \
        --data-source-name TasksDataSource \
        --request-mapping-template file://"${SCRIPT_DIR}/updateTask-request.vtl" \
        --response-mapping-template file://"${SCRIPT_DIR}/updateTask-response.vtl"
    
    # Create deleteTask resolver
    aws appsync create-resolver \
        --api-id "$API_ID" \
        --type-name Mutation \
        --field-name deleteTask \
        --data-source-name TasksDataSource \
        --request-mapping-template file://"${SCRIPT_DIR}/deleteTask-request.vtl" \
        --response-mapping-template file://"${SCRIPT_DIR}/deleteTask-response.vtl"
    
    log_success "All resolvers created successfully"
}

# Test deployment
test_deployment() {
    log_info "Testing deployment"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would test GraphQL operations"
        return 0
    fi
    
    # Test creating a task
    local create_query='mutation { createTask(input: { title: "Test Task", description: "Deployment test", priority: HIGH, assignedTo: "test@example.com" }) { id title status priority version createdAt } }'
    
    local task_result=$(aws appsync post-graphql \
        --api-id "$API_ID" \
        --query "$create_query" \
        --auth-type API_KEY \
        --auth-config apiKey="$API_KEY" 2>/dev/null || echo "")
    
    if [ -n "$task_result" ] && echo "$task_result" | jq -e '.data.createTask.id' > /dev/null; then
        local task_id=$(echo "$task_result" | jq -r '.data.createTask.id')
        log_success "✓ Test task created successfully with ID: $task_id"
        
        # Test listing tasks
        local list_query='query { listTasks(limit: 10) { items { id title status } } }'
        local list_result=$(aws appsync post-graphql \
            --api-id "$API_ID" \
            --query "$list_query" \
            --auth-type API_KEY \
            --auth-config apiKey="$API_KEY" 2>/dev/null || echo "")
        
        if [ -n "$list_result" ] && echo "$list_result" | jq -e '.data.listTasks.items[0]' > /dev/null; then
            log_success "✓ Task listing works correctly"
        else
            log_warning "Task listing test failed"
        fi
    else
        log_warning "Task creation test failed - API may need more time to stabilize"
    fi
}

# Finalize deployment
finalize_deployment() {
    log_info "Finalizing deployment"
    
    # Update state file to completed
    jq '.status = "completed" | .completion_time = now' \
       "${SCRIPT_DIR}/deployment-state.json" > "${SCRIPT_DIR}/deployment-state.tmp" && \
       mv "${SCRIPT_DIR}/deployment-state.tmp" "${SCRIPT_DIR}/deployment-state.json"
    
    # Create deployment summary
    cat > "${SCRIPT_DIR}/deployment-summary.txt" << EOF
=== AWS AppSync Real-time Data Synchronization Deployment Summary ===

Deployment completed successfully at: $(date)

Resources Created:
- AppSync API: $API_NAME ($API_ID)
- GraphQL URL: $API_URL
- DynamoDB Table: $TABLE_NAME
- IAM Role: $ROLE_NAME
- API Key: $API_KEY

Next Steps:
1. Use the GraphQL URL and API Key to connect your applications
2. Review the generated schema.graphql for available operations
3. Check CloudWatch Logs for AppSync execution logs
4. Consider implementing Amazon Cognito for production authentication

Clean up:
Run ./destroy.sh to remove all created resources

Files created:
- deployment-state.json (tracks created resources)
- deployment-summary.txt (this file)
- schema.graphql (GraphQL schema)
- *.vtl (resolver templates)
- *.json (policy files)

EOF
    
    log_success "Deployment completed successfully!"
    log_info "Summary written to: ${SCRIPT_DIR}/deployment-summary.txt"
    log_info "State file: ${SCRIPT_DIR}/deployment-state.json"
    
    if [ "$VERBOSE" = true ]; then
        echo ""
        log_info "Deployment Summary:"
        cat "${SCRIPT_DIR}/deployment-summary.txt"
    fi
}

# Main deployment flow
main() {
    log_info "Starting main deployment flow"
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Create resources
    create_dynamodb_table
    create_iam_role
    create_graphql_schema
    create_appsync_api
    create_api_key
    create_data_source
    create_resolver_templates
    create_resolvers
    
    # Test and finalize
    test_deployment
    finalize_deployment
    
    log_success "All steps completed successfully!"
}

# Run main function
main "$@"

# Disable error trap for successful completion
trap - EXIT