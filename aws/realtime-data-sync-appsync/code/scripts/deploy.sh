#!/bin/bash

# =============================================================================
# Deploy Script for AWS AppSync and DynamoDB Streams Real-Time Data Synchronization
# =============================================================================
# This script deploys the complete infrastructure for real-time data synchronization
# using AWS AppSync, DynamoDB Streams, and Lambda functions.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Proper IAM permissions for AppSync, DynamoDB, Lambda, and IAM
# - Active AWS account with appropriate service limits
#
# Usage:
# ./deploy.sh [OPTIONS]
#
# Options:
# -h, --help          Show this help message
# -v, --verbose       Enable verbose logging
# -d, --dry-run       Show what would be deployed without making changes
# -r, --region        AWS region (defaults to current CLI region)
# -s, --suffix        Custom suffix for resource names (optional)
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
VERBOSE=false
DRY_RUN=false
CUSTOM_SUFFIX=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}"
            ;;
        "DEBUG")
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} ${message}"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log "ERROR" "Script failed on line $line_number with exit code $exit_code"
    log "ERROR" "Check $LOG_FILE for detailed error information"
    exit $exit_code
}

# Set error trap
trap 'handle_error $LINENO' ERR

# Help function
show_help() {
    cat << EOF
Deploy Script for AWS AppSync and DynamoDB Streams Real-Time Data Synchronization

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -d, --dry-run       Show what would be deployed without making changes
    -r, --region        AWS region (defaults to current CLI region)
    -s, --suffix        Custom suffix for resource names (optional)

EXAMPLES:
    $0                           # Deploy with default settings
    $0 -v                        # Deploy with verbose logging
    $0 -d                        # Show what would be deployed
    $0 -r us-west-2              # Deploy to specific region
    $0 -s mytest                 # Use custom suffix 'mytest'

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - IAM permissions for AppSync, DynamoDB, Lambda, and IAM
    - Active AWS account with appropriate service limits

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -s|--suffix)
            CUSTOM_SUFFIX="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Initialize log file
echo "=== AWS AppSync and DynamoDB Streams Deployment Log ===" > "$LOG_FILE"
echo "Started at: $(date)" >> "$LOG_FILE"

log "INFO" "Starting AWS AppSync and DynamoDB Streams deployment"

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI not found. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version=$(echo $aws_version | cut -d. -f1)
    if [[ "$major_version" -lt 2 ]]; then
        log "WARN" "AWS CLI version $aws_version detected. AWS CLI v2 is recommended."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required tools
    local required_tools=("zip" "curl" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log "ERROR" "Required tool '$tool' not found. Please install it."
            exit 1
        fi
    done
    
    log "INFO" "Prerequisites check completed successfully"
}

# Set environment variables
setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Set AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            log "ERROR" "AWS region not configured. Please set region using -r option or configure AWS CLI."
            exit 1
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate or use custom suffix
    if [[ -n "$CUSTOM_SUFFIX" ]]; then
        RANDOM_SUFFIX="$CUSTOM_SUFFIX"
    else
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    fi
    
    # Export resource names
    export TABLE_NAME="RealTimeData-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="AppSyncNotifier-${RANDOM_SUFFIX}"
    export APPSYNC_API_NAME="RealTimeSyncAPI-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="${LAMBDA_FUNCTION_NAME}-Role"
    export APPSYNC_ROLE_NAME="AppSyncDynamoDBRole-${RANDOM_SUFFIX}"
    
    # Create environment file for cleanup
    cat > "${SCRIPT_DIR}/.env" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
TABLE_NAME=$TABLE_NAME
LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
APPSYNC_API_NAME=$APPSYNC_API_NAME
LAMBDA_ROLE_NAME=$LAMBDA_ROLE_NAME
APPSYNC_ROLE_NAME=$APPSYNC_ROLE_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    log "INFO" "Environment configured:"
    log "INFO" "  AWS Region: $AWS_REGION"
    log "INFO" "  AWS Account ID: $AWS_ACCOUNT_ID"
    log "INFO" "  Resource Suffix: $RANDOM_SUFFIX"
    log "INFO" "  DynamoDB Table: $TABLE_NAME"
    log "INFO" "  Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "INFO" "  AppSync API: $APPSYNC_API_NAME"
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    log "DEBUG" "Executing: $cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would execute: $description"
        return 0
    else
        log "INFO" "$description"
        eval "$cmd"
        return $?
    fi
}

# Deploy DynamoDB table with streams
deploy_dynamodb_table() {
    log "INFO" "Deploying DynamoDB table with streams..."
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name "$TABLE_NAME" &>/dev/null; then
        log "WARN" "DynamoDB table '$TABLE_NAME' already exists. Skipping creation."
        export STREAM_ARN=$(aws dynamodb describe-table \
            --table-name "$TABLE_NAME" \
            --query 'Table.LatestStreamArn' --output text)
        return 0
    fi
    
    local cmd="aws dynamodb create-table \
        --table-name '$TABLE_NAME' \
        --attribute-definitions AttributeName=id,AttributeType=S \
        --key-schema AttributeName=id,KeyType=HASH \
        --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Project,Value=AppSyncRealTimeSync \
        --tags Key=DeployedBy,Value=DeployScript"
    
    execute_cmd "$cmd" "Creating DynamoDB table with streams enabled"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "Waiting for table to become active..."
        aws dynamodb wait table-exists --table-name "$TABLE_NAME"
        
        # Get stream ARN
        export STREAM_ARN=$(aws dynamodb describe-table \
            --table-name "$TABLE_NAME" \
            --query 'Table.LatestStreamArn' --output text)
        
        log "INFO" "DynamoDB table created successfully"
        log "INFO" "Stream ARN: $STREAM_ARN"
        
        # Save to environment file
        echo "STREAM_ARN=$STREAM_ARN" >> "${SCRIPT_DIR}/.env"
    fi
}

# Deploy Lambda IAM role
deploy_lambda_role() {
    log "INFO" "Deploying Lambda IAM role..."
    
    # Check if role already exists
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
        log "WARN" "Lambda role '$LAMBDA_ROLE_NAME' already exists. Skipping creation."
        export LAMBDA_ROLE_ARN=$(aws iam get-role \
            --role-name "$LAMBDA_ROLE_NAME" \
            --query 'Role.Arn' --output text)
        return 0
    fi
    
    local assume_role_policy='{
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
    }'
    
    local cmd="aws iam create-role \
        --role-name '$LAMBDA_ROLE_NAME' \
        --assume-role-policy-document '$assume_role_policy' \
        --tags Key=Project,Value=AppSyncRealTimeSync"
    
    execute_cmd "$cmd" "Creating Lambda execution role"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Attach policies
        aws iam attach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        
        aws iam attach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole"
        
        # Get role ARN
        export LAMBDA_ROLE_ARN=$(aws iam get-role \
            --role-name "$LAMBDA_ROLE_NAME" \
            --query 'Role.Arn' --output text)
        
        log "INFO" "Lambda role created successfully"
        log "INFO" "Role ARN: $LAMBDA_ROLE_ARN"
        
        # Save to environment file
        echo "LAMBDA_ROLE_ARN=$LAMBDA_ROLE_ARN" >> "${SCRIPT_DIR}/.env"
        
        # Wait for role to be ready
        log "INFO" "Waiting for IAM role to propagate..."
        sleep 10
    fi
}

# Deploy Lambda function
deploy_lambda_function() {
    log "INFO" "Deploying Lambda function for stream processing..."
    
    # Check if function already exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log "WARN" "Lambda function '$LAMBDA_FUNCTION_NAME' already exists. Updating code..."
        
        # Create function code
        create_lambda_code
        
        # Update function code
        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --zip-file "fileb://${SCRIPT_DIR}/lambda_function.zip"
        
        return 0
    fi
    
    # Create function code
    create_lambda_code
    
    local cmd="aws lambda create-function \
        --function-name '$LAMBDA_FUNCTION_NAME' \
        --runtime python3.9 \
        --role '$LAMBDA_ROLE_ARN' \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://${SCRIPT_DIR}/lambda_function.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables='{\"TABLE_NAME\":\"$TABLE_NAME\"}' \
        --tags Project=AppSyncRealTimeSync"
    
    execute_cmd "$cmd" "Creating Lambda function"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "Waiting for Lambda function to be ready..."
        aws lambda wait function-active --function-name "$LAMBDA_FUNCTION_NAME"
        
        log "INFO" "Lambda function created successfully"
    fi
}

# Create Lambda function code
create_lambda_code() {
    cat > "${SCRIPT_DIR}/lambda_function.py" << 'EOF'
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process DynamoDB stream events and trigger AppSync mutations
    for real-time data synchronization
    """
    
    logger.info(f"Processing {len(event['Records'])} stream records")
    
    for record in event['Records']:
        event_name = record['eventName']
        
        if event_name in ['INSERT', 'MODIFY', 'REMOVE']:
            # Extract item data from stream record
            if 'NewImage' in record['dynamodb']:
                item_data = record['dynamodb']['NewImage']
                item_id = item_data.get('id', {}).get('S', 'unknown')
                
                logger.info(f"Processing {event_name} for item {item_id}")
                
                # In production, this would trigger AppSync mutations
                # For now, we'll log the change for validation
                change_event = {
                    'eventType': event_name,
                    'itemId': item_id,
                    'timestamp': datetime.utcnow().isoformat(),
                    'newImage': item_data if 'NewImage' in record['dynamodb'] else None,
                    'oldImage': record['dynamodb'].get('OldImage')
                }
                
                logger.info(f"Change event: {json.dumps(change_event, default=str)}")
        
    return {
        'statusCode': 200,
        'processedRecords': len(event['Records'])
    }
EOF
    
    # Package Lambda function
    cd "${SCRIPT_DIR}"
    zip -r lambda_function.zip lambda_function.py
    cd - > /dev/null
}

# Deploy event source mapping
deploy_event_source_mapping() {
    log "INFO" "Deploying event source mapping..."
    
    # Check if mapping already exists
    local existing_mapping=$(aws lambda list-event-source-mappings \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'EventSourceMappings[0].UUID' --output text 2>/dev/null || echo "None")
    
    if [[ "$existing_mapping" != "None" ]]; then
        log "WARN" "Event source mapping already exists. Skipping creation."
        export EVENT_MAPPING_UUID="$existing_mapping"
        return 0
    fi
    
    local cmd="aws lambda create-event-source-mapping \
        --function-name '$LAMBDA_FUNCTION_NAME' \
        --event-source-arn '$STREAM_ARN' \
        --starting-position LATEST \
        --batch-size 10 \
        --maximum-batching-window-in-seconds 5 \
        --parallelization-factor 1"
    
    execute_cmd "$cmd" "Creating event source mapping"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export EVENT_MAPPING_UUID=$(aws lambda list-event-source-mappings \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --query 'EventSourceMappings[0].UUID' --output text)
        
        log "INFO" "Event source mapping created successfully"
        log "INFO" "Mapping UUID: $EVENT_MAPPING_UUID"
        
        # Save to environment file
        echo "EVENT_MAPPING_UUID=$EVENT_MAPPING_UUID" >> "${SCRIPT_DIR}/.env"
    fi
}

# Deploy AppSync API
deploy_appsync_api() {
    log "INFO" "Deploying AppSync GraphQL API..."
    
    # Check if API already exists
    local existing_api=$(aws appsync list-graphql-apis \
        --query "graphqlApis[?name=='$APPSYNC_API_NAME'].apiId" --output text 2>/dev/null || echo "")
    
    if [[ -n "$existing_api" ]]; then
        log "WARN" "AppSync API '$APPSYNC_API_NAME' already exists. Skipping creation."
        export APPSYNC_API_ID="$existing_api"
        export APPSYNC_API_URL=$(aws appsync get-graphql-api \
            --api-id "$APPSYNC_API_ID" \
            --query 'graphqlApi.uris.GRAPHQL' --output text)
        return 0
    fi
    
    local cmd="aws appsync create-graphql-api \
        --name '$APPSYNC_API_NAME' \
        --authentication-type API_KEY \
        --tags Project=AppSyncRealTimeSync"
    
    execute_cmd "$cmd" "Creating AppSync GraphQL API"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export APPSYNC_API_ID=$(aws appsync list-graphql-apis \
            --query "graphqlApis[?name=='$APPSYNC_API_NAME'].apiId" --output text)
        
        export APPSYNC_API_URL=$(aws appsync get-graphql-api \
            --api-id "$APPSYNC_API_ID" \
            --query 'graphqlApi.uris.GRAPHQL' --output text)
        
        # Create API key
        aws appsync create-api-key \
            --api-id "$APPSYNC_API_ID" \
            --description "Development API key for real-time sync"
        
        export APPSYNC_API_KEY=$(aws appsync list-api-keys \
            --api-id "$APPSYNC_API_ID" \
            --query 'apiKeys[0].id' --output text)
        
        log "INFO" "AppSync API created successfully"
        log "INFO" "API ID: $APPSYNC_API_ID"
        log "INFO" "API URL: $APPSYNC_API_URL"
        log "INFO" "API Key: $APPSYNC_API_KEY"
        
        # Save to environment file
        cat >> "${SCRIPT_DIR}/.env" << EOF
APPSYNC_API_ID=$APPSYNC_API_ID
APPSYNC_API_URL=$APPSYNC_API_URL
APPSYNC_API_KEY=$APPSYNC_API_KEY
EOF
    fi
}

# Deploy GraphQL schema
deploy_graphql_schema() {
    log "INFO" "Deploying GraphQL schema..."
    
    # Create schema file
    cat > "${SCRIPT_DIR}/schema.graphql" << 'EOF'
type DataItem {
    id: ID!
    title: String!
    content: String!
    timestamp: String!
    version: Int!
}

type Query {
    getDataItem(id: ID!): DataItem
    listDataItems: [DataItem]
}

type Mutation {
    createDataItem(input: CreateDataItemInput!): DataItem
    updateDataItem(input: UpdateDataItemInput!): DataItem
    deleteDataItem(id: ID!): DataItem
}

type Subscription {
    onDataItemCreated: DataItem
        @aws_subscribe(mutations: ["createDataItem"])
    onDataItemUpdated: DataItem
        @aws_subscribe(mutations: ["updateDataItem"])
    onDataItemDeleted: DataItem
        @aws_subscribe(mutations: ["deleteDataItem"])
}

input CreateDataItemInput {
    title: String!
    content: String!
}

input UpdateDataItemInput {
    id: ID!
    title: String
    content: String
}
EOF
    
    local cmd="aws appsync start-schema-creation \
        --api-id '$APPSYNC_API_ID' \
        --definition fileb://${SCRIPT_DIR}/schema.graphql"
    
    execute_cmd "$cmd" "Deploying GraphQL schema"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "Waiting for schema creation to complete..."
        
        while true; do
            local status=$(aws appsync get-schema-creation-status \
                --api-id "$APPSYNC_API_ID" \
                --query 'status' --output text)
            
            if [[ "$status" == "SUCCESS" ]]; then
                log "INFO" "GraphQL schema deployed successfully"
                break
            elif [[ "$status" == "FAILED" ]]; then
                log "ERROR" "Schema creation failed"
                return 1
            else
                log "DEBUG" "Schema creation in progress: $status"
                sleep 5
            fi
        done
    fi
}

# Deploy AppSync service role
deploy_appsync_role() {
    log "INFO" "Deploying AppSync service role..."
    
    # Check if role already exists
    if aws iam get-role --role-name "$APPSYNC_ROLE_NAME" &>/dev/null; then
        log "WARN" "AppSync role '$APPSYNC_ROLE_NAME' already exists. Skipping creation."
        export APPSYNC_ROLE_ARN=$(aws iam get-role \
            --role-name "$APPSYNC_ROLE_NAME" \
            --query 'Role.Arn' --output text)
        return 0
    fi
    
    local assume_role_policy='{
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
    }'
    
    local cmd="aws iam create-role \
        --role-name '$APPSYNC_ROLE_NAME' \
        --assume-role-policy-document '$assume_role_policy' \
        --tags Key=Project,Value=AppSyncRealTimeSync"
    
    execute_cmd "$cmd" "Creating AppSync service role"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create and attach DynamoDB policy
        local policy_document='{
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
                    "Resource": "arn:aws:dynamodb:'$AWS_REGION':'$AWS_ACCOUNT_ID':table/'$TABLE_NAME'"
                }
            ]
        }'
        
        aws iam put-role-policy \
            --role-name "$APPSYNC_ROLE_NAME" \
            --policy-name DynamoDBAccess \
            --policy-document "$policy_document"
        
        export APPSYNC_ROLE_ARN=$(aws iam get-role \
            --role-name "$APPSYNC_ROLE_NAME" \
            --query 'Role.Arn' --output text)
        
        log "INFO" "AppSync service role created successfully"
        log "INFO" "Role ARN: $APPSYNC_ROLE_ARN"
        
        # Save to environment file
        echo "APPSYNC_ROLE_ARN=$APPSYNC_ROLE_ARN" >> "${SCRIPT_DIR}/.env"
        
        # Wait for role to be ready
        log "INFO" "Waiting for IAM role to propagate..."
        sleep 10
    fi
}

# Deploy DynamoDB data source
deploy_dynamodb_datasource() {
    log "INFO" "Deploying DynamoDB data source..."
    
    local cmd="aws appsync create-data-source \
        --api-id '$APPSYNC_API_ID' \
        --name DynamoDBDataSource \
        --type AMAZON_DYNAMODB \
        --service-role-arn '$APPSYNC_ROLE_ARN' \
        --dynamodb-config tableName='$TABLE_NAME',awsRegion='$AWS_REGION'"
    
    execute_cmd "$cmd" "Creating DynamoDB data source"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "DynamoDB data source created successfully"
    fi
}

# Deploy GraphQL resolvers
deploy_graphql_resolvers() {
    log "INFO" "Deploying GraphQL resolvers..."
    
    # Create resolver templates
    cat > "${SCRIPT_DIR}/create-resolver-request.vtl" << 'EOF'
{
    "version": "2017-02-28",
    "operation": "PutItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($util.autoId())
    },
    "attributeValues": {
        "title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
        "content": $util.dynamodb.toDynamoDBJson($ctx.args.input.content),
        "timestamp": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
        "version": $util.dynamodb.toDynamoDBJson(1)
    }
}
EOF
    
    cat > "${SCRIPT_DIR}/create-resolver-response.vtl" << 'EOF'
$util.toJson($ctx.result)
EOF
    
    cat > "${SCRIPT_DIR}/get-resolver-request.vtl" << 'EOF'
{
    "version": "2017-02-28",
    "operation": "GetItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
    }
}
EOF
    
    cat > "${SCRIPT_DIR}/get-resolver-response.vtl" << 'EOF'
$util.toJson($ctx.result)
EOF
    
    # Deploy create mutation resolver
    local cmd1="aws appsync create-resolver \
        --api-id '$APPSYNC_API_ID' \
        --type-name Mutation \
        --field-name createDataItem \
        --data-source-name DynamoDBDataSource \
        --request-mapping-template file://${SCRIPT_DIR}/create-resolver-request.vtl \
        --response-mapping-template file://${SCRIPT_DIR}/create-resolver-response.vtl"
    
    execute_cmd "$cmd1" "Creating createDataItem resolver"
    
    # Deploy get query resolver
    local cmd2="aws appsync create-resolver \
        --api-id '$APPSYNC_API_ID' \
        --type-name Query \
        --field-name getDataItem \
        --data-source-name DynamoDBDataSource \
        --request-mapping-template file://${SCRIPT_DIR}/get-resolver-request.vtl \
        --response-mapping-template file://${SCRIPT_DIR}/get-resolver-response.vtl"
    
    execute_cmd "$cmd2" "Creating getDataItem resolver"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "GraphQL resolvers created successfully"
    fi
}

# Run deployment validation
run_deployment_validation() {
    log "INFO" "Running deployment validation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "Skipping validation in dry-run mode"
        return 0
    fi
    
    # Validate DynamoDB table
    local table_status=$(aws dynamodb describe-table --table-name "$TABLE_NAME" \
        --query 'Table.TableStatus' --output text)
    
    if [[ "$table_status" != "ACTIVE" ]]; then
        log "ERROR" "DynamoDB table is not active: $table_status"
        return 1
    fi
    
    # Validate Lambda function
    local function_status=$(aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Configuration.State' --output text)
    
    if [[ "$function_status" != "Active" ]]; then
        log "ERROR" "Lambda function is not active: $function_status"
        return 1
    fi
    
    # Validate AppSync API
    local api_status=$(aws appsync get-graphql-api --api-id "$APPSYNC_API_ID" \
        --query 'graphqlApi.apiStatus' --output text)
    
    if [[ "$api_status" != "AVAILABLE" ]]; then
        log "ERROR" "AppSync API is not available: $api_status"
        return 1
    fi
    
    log "INFO" "Deployment validation completed successfully"
}

# Print deployment summary
print_deployment_summary() {
    log "INFO" "Deployment Summary:"
    log "INFO" "=================="
    log "INFO" "AWS Region: $AWS_REGION"
    log "INFO" "DynamoDB Table: $TABLE_NAME"
    log "INFO" "Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "INFO" "AppSync API: $APPSYNC_API_NAME"
    log "INFO" "AppSync API ID: ${APPSYNC_API_ID:-'[DRY-RUN]'}"
    log "INFO" "AppSync API URL: ${APPSYNC_API_URL:-'[DRY-RUN]'}"
    log "INFO" "AppSync API Key: ${APPSYNC_API_KEY:-'[DRY-RUN]'}"
    log "INFO" ""
    log "INFO" "Next Steps:"
    log "INFO" "1. Test the GraphQL API using the provided URL and API key"
    log "INFO" "2. Monitor CloudWatch logs for Lambda function execution"
    log "INFO" "3. Use the destroy.sh script to clean up resources when done"
    log "INFO" ""
    log "INFO" "Environment variables saved to: ${SCRIPT_DIR}/.env"
    log "INFO" "Deployment log saved to: $LOG_FILE"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "DEBUG" "Cleaning up temporary files..."
    
    local temp_files=(
        "${SCRIPT_DIR}/lambda_function.py"
        "${SCRIPT_DIR}/lambda_function.zip"
        "${SCRIPT_DIR}/schema.graphql"
        "${SCRIPT_DIR}/create-resolver-request.vtl"
        "${SCRIPT_DIR}/create-resolver-response.vtl"
        "${SCRIPT_DIR}/get-resolver-request.vtl"
        "${SCRIPT_DIR}/get-resolver-response.vtl"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "DEBUG" "Removed temporary file: $file"
        fi
    done
}

# Main deployment function
main() {
    log "INFO" "Starting deployment process..."
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Deploy infrastructure components
    deploy_dynamodb_table
    deploy_lambda_role
    deploy_lambda_function
    deploy_event_source_mapping
    deploy_appsync_api
    deploy_graphql_schema
    deploy_appsync_role
    deploy_dynamodb_datasource
    deploy_graphql_resolvers
    
    # Run validation
    run_deployment_validation
    
    # Print summary
    print_deployment_summary
    
    # Cleanup
    cleanup_temp_files
    
    log "INFO" "Deployment completed successfully!"
}

# Run main function
main "$@"