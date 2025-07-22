#!/bin/bash

# CQRS and Event Sourcing with EventBridge and DynamoDB - Deployment Script
# This script deploys a complete CQRS (Command Query Responsibility Segregation) 
# and Event Sourcing architecture using AWS services

set -euo pipefail

# =============================================================================
# Configuration and Constants
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/cqrs-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly REQUIRED_AWS_CLI_VERSION="2.0.0"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default values
DEFAULT_PROJECT_NAME="cqrs-demo"
DEFAULT_REGION=""

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

# =============================================================================
# Utility Functions
# =============================================================================

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy CQRS and Event Sourcing architecture with EventBridge and DynamoDB

OPTIONS:
    -n, --project-name NAME    Project name prefix (default: ${DEFAULT_PROJECT_NAME})
    -r, --region REGION        AWS region (uses current default if not specified)
    -d, --dry-run             Show what would be deployed without creating resources
    -v, --verbose             Enable verbose logging
    -h, --help                Show this help message

EXAMPLES:
    $0                                    # Deploy with defaults
    $0 --project-name my-cqrs-app        # Deploy with custom project name
    $0 --region us-west-2 --verbose      # Deploy in specific region with verbose output
    $0 --dry-run                         # Preview deployment without creating resources

EOF
}

cleanup_on_error() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Deployment failed with exit code ${exit_code}"
        log_error "Check log file: ${LOG_FILE}"
        log_warning "You may need to manually clean up any partially created resources"
        log_info "Use the destroy.sh script to remove any created resources"
    fi
    exit ${exit_code}
}

version_compare() {
    local version1=$1
    local version2=$2
    
    if [[ "$(printf '%s\n' "$version1" "$version2" | sort -V | head -n1)" == "$version1" ]]; then
        return 0  # version1 <= version2
    else
        return 1  # version1 > version2
    fi
}

wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local max_attempts=${3:-30}
    local attempt=1
    
    log_info "Waiting for ${resource_type} '${resource_name}' to become available..."
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        case ${resource_type} in
            "dynamodb-table")
                if aws dynamodb describe-table --table-name "${resource_name}" >/dev/null 2>&1; then
                    log_success "${resource_type} '${resource_name}' is ready"
                    return 0
                fi
                ;;
            "iam-role")
                if aws iam get-role --role-name "${resource_name}" >/dev/null 2>&1; then
                    log_success "${resource_type} '${resource_name}' is ready"
                    return 0
                fi
                ;;
            "lambda-function")
                if aws lambda get-function --function-name "${resource_name}" >/dev/null 2>&1; then
                    log_success "${resource_type} '${resource_name}' is ready"
                    return 0
                fi
                ;;
        esac
        
        log_info "Attempt ${attempt}/${max_attempts}: ${resource_type} not ready yet, waiting..."
        sleep 10
        ((attempt++))
    done
    
    log_error "Timeout waiting for ${resource_type} '${resource_name}'"
    return 1
}

# =============================================================================
# Prerequisites Checking
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2 or higher."
        log_error "Visit: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        return 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if ! version_compare "${REQUIRED_AWS_CLI_VERSION}" "${aws_version}"; then
        log_error "AWS CLI version ${aws_version} is too old. Required: ${REQUIRED_AWS_CLI_VERSION}+"
        return 1
    fi
    log_success "AWS CLI version ${aws_version} meets requirements"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid"
        log_error "Run 'aws configure' to set up your credentials"
        return 1
    fi
    
    local caller_identity
    caller_identity=$(aws sts get-caller-identity)
    local account_id
    account_id=$(echo "${caller_identity}" | jq -r '.Account')
    local user_arn
    user_arn=$(echo "${caller_identity}" | jq -r '.Arn')
    
    log_success "AWS credentials configured"
    log_info "Account ID: ${account_id}"
    log_info "User/Role: ${user_arn}"
    
    # Check required permissions (basic check)
    log_info "Checking AWS permissions..."
    local permissions_ok=true
    
    # Test DynamoDB permissions
    if ! aws dynamodb list-tables >/dev/null 2>&1; then
        log_error "Missing DynamoDB permissions"
        permissions_ok=false
    fi
    
    # Test Lambda permissions
    if ! aws lambda list-functions >/dev/null 2>&1; then
        log_error "Missing Lambda permissions"
        permissions_ok=false
    fi
    
    # Test IAM permissions
    if ! aws iam list-roles >/dev/null 2>&1; then
        log_error "Missing IAM permissions"
        permissions_ok=false
    fi
    
    # Test EventBridge permissions
    if ! aws events list-event-buses >/dev/null 2>&1; then
        log_error "Missing EventBridge permissions"
        permissions_ok=false
    fi
    
    if [[ "${permissions_ok}" != "true" ]]; then
        log_error "Insufficient AWS permissions. Please ensure your user/role has appropriate policies."
        return 1
    fi
    
    log_success "AWS permissions check passed"
    
    # Check for required tools
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is not installed. Please install jq for JSON processing."
        return 1
    fi
    
    if ! command -v zip >/dev/null 2>&1; then
        log_error "zip is not installed. Please install zip utility."
        return 1
    fi
    
    log_success "All prerequisites check passed"
    return 0
}

# =============================================================================
# Resource Management Functions
# =============================================================================

generate_unique_suffix() {
    aws secretsmanager get-random-password \
        --exclude-punctuation \
        --exclude-uppercase \
        --password-length 6 \
        --require-each-included-type \
        --output text \
        --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)"
}

setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix if not in dry-run mode
    local suffix
    if [[ "${DRY_RUN}" == "true" ]]; then
        suffix="abc123"
    else
        suffix=$(generate_unique_suffix)
    fi
    
    # Export environment variables
    export AWS_REGION="${REGION:-$(aws configure get region)}"
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export PROJECT_NAME="${PROJECT_NAME_PREFIX}-${suffix}"
    export EVENT_BUS_NAME="${PROJECT_NAME}-events"
    export EVENT_STORE_TABLE="${PROJECT_NAME}-event-store"
    export USER_READ_MODEL_TABLE="${PROJECT_NAME}-user-profiles"
    export ORDER_READ_MODEL_TABLE="${PROJECT_NAME}-order-summaries"
    
    log_success "Environment configured:"
    log_info "  AWS Region: ${AWS_REGION}"
    log_info "  AWS Account: ${AWS_ACCOUNT_ID}"
    log_info "  Project Name: ${PROJECT_NAME}"
    log_info "  Event Bus: ${EVENT_BUS_NAME}"
    log_info "  Event Store Table: ${EVENT_STORE_TABLE}"
    log_info "  User Read Model: ${USER_READ_MODEL_TABLE}"
    log_info "  Order Read Model: ${ORDER_READ_MODEL_TABLE}"
}

create_event_store_table() {
    log_info "Creating Event Store DynamoDB table..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create DynamoDB table: ${EVENT_STORE_TABLE}"
        return 0
    fi
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name "${EVENT_STORE_TABLE}" >/dev/null 2>&1; then
        log_warning "Table ${EVENT_STORE_TABLE} already exists, skipping creation"
        return 0
    fi
    
    aws dynamodb create-table \
        --table-name "${EVENT_STORE_TABLE}" \
        --attribute-definitions \
            AttributeName=AggregateId,AttributeType=S \
            AttributeName=Version,AttributeType=N \
            AttributeName=EventType,AttributeType=S \
            AttributeName=Timestamp,AttributeType=S \
        --key-schema \
            AttributeName=AggregateId,KeyType=HASH \
            AttributeName=Version,KeyType=RANGE \
        --global-secondary-indexes \
            "IndexName=EventType-Timestamp-index,KeySchema=[{AttributeName=EventType,KeyType=HASH},{AttributeName=Timestamp,KeyType=RANGE}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5}" \
        --provisioned-throughput \
            ReadCapacityUnits=10,WriteCapacityUnits=10 \
        --stream-specification \
            StreamEnabled=true,StreamViewType=NEW_IMAGE
    
    aws dynamodb wait table-exists --table-name "${EVENT_STORE_TABLE}"
    log_success "Event Store table created: ${EVENT_STORE_TABLE}"
}

create_read_model_tables() {
    log_info "Creating Read Model DynamoDB tables..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create read model tables"
        return 0
    fi
    
    # Create user profiles table
    if ! aws dynamodb describe-table --table-name "${USER_READ_MODEL_TABLE}" >/dev/null 2>&1; then
        aws dynamodb create-table \
            --table-name "${USER_READ_MODEL_TABLE}" \
            --attribute-definitions \
                AttributeName=UserId,AttributeType=S \
                AttributeName=Email,AttributeType=S \
            --key-schema \
                AttributeName=UserId,KeyType=HASH \
            --global-secondary-indexes \
                "IndexName=Email-index,KeySchema=[{AttributeName=Email,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5}" \
            --provisioned-throughput \
                ReadCapacityUnits=5,WriteCapacityUnits=5
    else
        log_warning "Table ${USER_READ_MODEL_TABLE} already exists, skipping creation"
    fi
    
    # Create order summaries table
    if ! aws dynamodb describe-table --table-name "${ORDER_READ_MODEL_TABLE}" >/dev/null 2>&1; then
        aws dynamodb create-table \
            --table-name "${ORDER_READ_MODEL_TABLE}" \
            --attribute-definitions \
                AttributeName=OrderId,AttributeType=S \
                AttributeName=UserId,AttributeType=S \
                AttributeName=Status,AttributeType=S \
            --key-schema \
                AttributeName=OrderId,KeyType=HASH \
            --global-secondary-indexes \
                "IndexName=UserId-index,KeySchema=[{AttributeName=UserId,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5}" \
                "IndexName=Status-index,KeySchema=[{AttributeName=Status,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5}" \
            --provisioned-throughput \
                ReadCapacityUnits=5,WriteCapacityUnits=5
    else
        log_warning "Table ${ORDER_READ_MODEL_TABLE} already exists, skipping creation"
    fi
    
    # Wait for tables to become active
    aws dynamodb wait table-exists --table-name "${USER_READ_MODEL_TABLE}"
    aws dynamodb wait table-exists --table-name "${ORDER_READ_MODEL_TABLE}"
    
    log_success "Read model tables created successfully"
}

create_eventbridge_bus() {
    log_info "Creating EventBridge custom bus..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create EventBridge bus: ${EVENT_BUS_NAME}"
        return 0
    fi
    
    # Create custom event bus
    if ! aws events describe-event-bus --name "${EVENT_BUS_NAME}" >/dev/null 2>&1; then
        aws events create-event-bus --name "${EVENT_BUS_NAME}"
    else
        log_warning "Event bus ${EVENT_BUS_NAME} already exists, skipping creation"
    fi
    
    # Create event archive
    local archive_name="${EVENT_BUS_NAME}-archive"
    if ! aws events describe-archive --archive-name "${archive_name}" >/dev/null 2>&1; then
        aws events create-archive \
            --archive-name "${archive_name}" \
            --event-source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:event-bus/${EVENT_BUS_NAME}" \
            --retention-days 30 \
            --description "Archive for CQRS event sourcing demo"
    else
        log_warning "Archive ${archive_name} already exists, skipping creation"
    fi
    
    log_success "EventBridge bus and archive created: ${EVENT_BUS_NAME}"
}

create_iam_roles() {
    log_info "Creating IAM roles for Lambda functions..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create IAM roles"
        return 0
    fi
    
    local command_role="${PROJECT_NAME}-command-role"
    local projection_role="${PROJECT_NAME}-projection-role"
    
    # Create command handler role
    if ! aws iam get-role --role-name "${command_role}" >/dev/null 2>&1; then
        aws iam create-role \
            --role-name "${command_role}" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Principal": {"Service": "lambda.amazonaws.com"},
                    "Action": "sts:AssumeRole"
                }]
            }'
        
        # Wait for role to be created
        sleep 10
        
        # Attach basic execution policy
        aws iam attach-role-policy \
            --role-name "${command_role}" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        
        # Add DynamoDB event store access
        aws iam put-role-policy \
            --role-name "${command_role}" \
            --policy-name "DynamoDBEventStoreAccess" \
            --policy-document "{
                \"Version\": \"2012-10-17\",
                \"Statement\": [{
                    \"Effect\": \"Allow\",
                    \"Action\": [
                        \"dynamodb:PutItem\",
                        \"dynamodb:Query\",
                        \"dynamodb:GetItem\"
                    ],
                    \"Resource\": \"arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${EVENT_STORE_TABLE}*\"
                }]
            }"
        
        # Add EventBridge permissions
        aws iam put-role-policy \
            --role-name "${command_role}" \
            --policy-name "EventBridgePublish" \
            --policy-document "{
                \"Version\": \"2012-10-17\",
                \"Statement\": [{
                    \"Effect\": \"Allow\",
                    \"Action\": \"events:PutEvents\",
                    \"Resource\": \"arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:event-bus/${EVENT_BUS_NAME}\"
                }]
            }"
        
        # Add DynamoDB Streams permissions
        aws iam put-role-policy \
            --role-name "${command_role}" \
            --policy-name "DynamoDBStreamsAccess" \
            --policy-document "{
                \"Version\": \"2012-10-17\",
                \"Statement\": [{
                    \"Effect\": \"Allow\",
                    \"Action\": [
                        \"dynamodb:DescribeStream\",
                        \"dynamodb:GetRecords\",
                        \"dynamodb:GetShardIterator\",
                        \"dynamodb:ListStreams\"
                    ],
                    \"Resource\": \"arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${EVENT_STORE_TABLE}/stream/*\"
                }]
            }"
    else
        log_warning "Role ${command_role} already exists, skipping creation"
    fi
    
    # Create projection handler role
    if ! aws iam get-role --role-name "${projection_role}" >/dev/null 2>&1; then
        aws iam create-role \
            --role-name "${projection_role}" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Principal": {"Service": "lambda.amazonaws.com"},
                    "Action": "sts:AssumeRole"
                }]
            }'
        
        # Wait for role to be created
        sleep 10
        
        # Attach basic execution policy
        aws iam attach-role-policy \
            --role-name "${projection_role}" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        
        # Add read model access
        aws iam put-role-policy \
            --role-name "${projection_role}" \
            --policy-name "ReadModelAccess" \
            --policy-document "{
                \"Version\": \"2012-10-17\",
                \"Statement\": [{
                    \"Effect\": \"Allow\",
                    \"Action\": [
                        \"dynamodb:PutItem\",
                        \"dynamodb:UpdateItem\",
                        \"dynamodb:DeleteItem\",
                        \"dynamodb:GetItem\",
                        \"dynamodb:Query\"
                    ],
                    \"Resource\": [
                        \"arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${USER_READ_MODEL_TABLE}*\",
                        \"arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${ORDER_READ_MODEL_TABLE}*\"
                    ]
                }]
            }"
    else
        log_warning "Role ${projection_role} already exists, skipping creation"
    fi
    
    log_success "IAM roles created with appropriate permissions"
}

create_lambda_functions() {
    log_info "Creating Lambda functions..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create Lambda functions"
        return 0
    fi
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Function to create a Lambda function with retries
    create_lambda_with_retry() {
        local function_name=$1
        local handler=$2
        local role_arn=$3
        local env_vars=$4
        local source_file=$5
        
        log_info "Creating Lambda function: ${function_name}"
        
        # Package the function
        local zip_file="${temp_dir}/${function_name}.zip"
        (cd "${temp_dir}" && zip "${zip_file}" "${source_file}")
        
        # Create function with retry logic
        local attempt=1
        local max_attempts=3
        
        while [[ ${attempt} -le ${max_attempts} ]]; do
            if aws lambda create-function \
                --function-name "${function_name}" \
                --runtime python3.9 \
                --role "${role_arn}" \
                --handler "${handler}" \
                --zip-file "fileb://${zip_file}" \
                --environment "Variables=${env_vars}" \
                --timeout 30 >/dev/null 2>&1; then
                log_success "Lambda function created: ${function_name}"
                return 0
            fi
            
            log_warning "Attempt ${attempt}/${max_attempts} failed for ${function_name}, retrying..."
            sleep 5
            ((attempt++))
        done
        
        log_error "Failed to create Lambda function: ${function_name}"
        return 1
    }
    
    # Get role ARNs
    local command_role_arn
    command_role_arn=$(aws iam get-role --role-name "${PROJECT_NAME}-command-role" --query 'Role.Arn' --output text)
    local projection_role_arn
    projection_role_arn=$(aws iam get-role --role-name "${PROJECT_NAME}-projection-role" --query 'Role.Arn' --output text)
    
    # Create command handler source
    cat > "${temp_dir}/command_handler.py" << 'EOF'
import json
import boto3
import uuid
import os
from datetime import datetime
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        # Parse command from API Gateway or direct invocation
        if 'body' in event and event['body']:
            command = json.loads(event['body'])
        else:
            command = event
        
        # Command validation
        command_type = command.get('commandType')
        aggregate_id = command.get('aggregateId', str(uuid.uuid4()))
        
        if not command_type:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'commandType is required'})
            }
        
        # Get current version for optimistic concurrency
        table = dynamodb.Table(os.environ['EVENT_STORE_TABLE'])
        
        # Query existing events for this aggregate
        response = table.query(
            KeyConditionExpression='AggregateId = :id',
            ExpressionAttributeValues={':id': aggregate_id},
            ScanIndexForward=False,
            Limit=1
        )
        
        current_version = 0
        if response['Items']:
            current_version = int(response['Items'][0]['Version'])
        
        # Create domain event
        event_id = str(uuid.uuid4())
        new_version = current_version + 1
        timestamp = datetime.utcnow().isoformat()
        
        # Event payload based on command type
        event_data = create_event_from_command(command_type, command, aggregate_id)
        
        # Store event in event store
        table.put_item(
            Item={
                'AggregateId': aggregate_id,
                'Version': new_version,
                'EventId': event_id,
                'EventType': event_data['eventType'],
                'Timestamp': timestamp,
                'EventData': event_data['data'],
                'CommandId': command.get('commandId', str(uuid.uuid4())),
                'CorrelationId': command.get('correlationId', str(uuid.uuid4()))
            },
            ConditionExpression='attribute_not_exists(#aid) OR #v < :new_version',
            ExpressionAttributeNames={'#aid': 'AggregateId', '#v': 'Version'},
            ExpressionAttributeValues={':new_version': new_version}
        )
        
        return {
            'statusCode': 201,
            'body': json.dumps({
                'aggregateId': aggregate_id,
                'version': new_version,
                'eventId': event_id
            })
        }
        
    except Exception as e:
        print(f"Error processing command: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def create_event_from_command(command_type, command, aggregate_id):
    """Transform commands into domain events"""
    
    if command_type == 'CreateUser':
        return {
            'eventType': 'UserCreated',
            'data': {
                'userId': aggregate_id,
                'email': command['email'],
                'name': command['name'],
                'createdAt': datetime.utcnow().isoformat()
            }
        }
    
    elif command_type == 'UpdateUserProfile':
        return {
            'eventType': 'UserProfileUpdated',
            'data': {
                'userId': aggregate_id,
                'changes': command['changes'],
                'updatedAt': datetime.utcnow().isoformat()
            }
        }
    
    elif command_type == 'CreateOrder':
        return {
            'eventType': 'OrderCreated',
            'data': {
                'orderId': aggregate_id,
                'userId': command['userId'],
                'items': command['items'],
                'totalAmount': command['totalAmount'],
                'createdAt': datetime.utcnow().isoformat()
            }
        }
    
    elif command_type == 'UpdateOrderStatus':
        return {
            'eventType': 'OrderStatusUpdated',
            'data': {
                'orderId': aggregate_id,
                'status': command['status'],
                'updatedAt': datetime.utcnow().isoformat()
            }
        }
    
    else:
        raise ValueError(f"Unknown command type: {command_type}")
EOF
    
    # Create stream processor source
    cat > "${temp_dir}/stream_processor.py" << 'EOF'
import json
import boto3
import os
from decimal import Decimal

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            if record['eventName'] in ['INSERT']:
                # Extract event from DynamoDB stream
                dynamodb_event = record['dynamodb']['NewImage']
                
                # Convert DynamoDB format to normal format
                domain_event = {
                    'EventId': dynamodb_event['EventId']['S'],
                    'AggregateId': dynamodb_event['AggregateId']['S'],
                    'EventType': dynamodb_event['EventType']['S'],
                    'Version': int(dynamodb_event['Version']['N']),
                    'Timestamp': dynamodb_event['Timestamp']['S'],
                    'EventData': deserialize_dynamodb_item(dynamodb_event['EventData']['M']),
                    'CommandId': dynamodb_event.get('CommandId', {}).get('S'),
                    'CorrelationId': dynamodb_event.get('CorrelationId', {}).get('S')
                }
                
                # Publish to EventBridge
                eventbridge.put_events(
                    Entries=[{
                        'Source': 'cqrs.demo',
                        'DetailType': domain_event['EventType'],
                        'Detail': json.dumps(domain_event, default=str),
                        'EventBusName': os.environ['EVENT_BUS_NAME']
                    }]
                )
                
                print(f"Published event {domain_event['EventId']} to EventBridge")
        
        return {'statusCode': 200}
        
    except Exception as e:
        print(f"Error processing stream: {str(e)}")
        raise

def deserialize_dynamodb_item(item):
    """Convert DynamoDB item format to regular Python objects"""
    if isinstance(item, dict):
        if len(item) == 1:
            key, value = next(iter(item.items()))
            if key == 'S':
                return value
            elif key == 'N':
                return Decimal(value)
            elif key == 'B':
                return value
            elif key == 'SS':
                return set(value)
            elif key == 'NS':
                return set(Decimal(v) for v in value)
            elif key == 'BS':
                return set(value)
            elif key == 'M':
                return {k: deserialize_dynamodb_item(v) for k, v in value.items()}
            elif key == 'L':
                return [deserialize_dynamodb_item(v) for v in value]
            elif key == 'NULL':
                return None
            elif key == 'BOOL':
                return value
        else:
            return {k: deserialize_dynamodb_item(v) for k, v in item.items()}
    return item
EOF
    
    # Create user projection source
    cat > "${temp_dir}/user_projection.py" << 'EOF'
import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        detail = event['detail']
        event_type = detail['EventType']
        event_data = detail['EventData']
        
        table = dynamodb.Table(os.environ['USER_READ_MODEL_TABLE'])
        
        if event_type == 'UserCreated':
            # Create user profile projection
            table.put_item(
                Item={
                    'UserId': event_data['userId'],
                    'Email': event_data['email'],
                    'Name': event_data['name'],
                    'CreatedAt': event_data['createdAt'],
                    'UpdatedAt': event_data['createdAt'],
                    'Version': detail['Version']
                }
            )
            print(f"Created user profile for {event_data['userId']}")
            
        elif event_type == 'UserProfileUpdated':
            # Update user profile projection
            update_expression = "SET UpdatedAt = :updated, Version = :version"
            expression_values = {
                ':updated': event_data['updatedAt'],
                ':version': detail['Version']
            }
            
            # Build update expression for changes
            for field, value in event_data['changes'].items():
                if field in ['Name', 'Email']:  # Allow only certain fields
                    update_expression += f", {field} = :{field.lower()}"
                    expression_values[f":{field.lower()}"] = value
            
            table.update_item(
                Key={'UserId': event_data['userId']},
                UpdateExpression=update_expression,
                ExpressionAttributeValues=expression_values
            )
            print(f"Updated user profile for {event_data['userId']}")
        
        return {'statusCode': 200}
        
    except Exception as e:
        print(f"Error in user projection: {str(e)}")
        raise
EOF
    
    # Create order projection source
    cat > "${temp_dir}/order_projection.py" << 'EOF'
import json
import boto3
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        detail = event['detail']
        event_type = detail['EventType']
        event_data = detail['EventData']
        
        table = dynamodb.Table(os.environ['ORDER_READ_MODEL_TABLE'])
        
        if event_type == 'OrderCreated':
            # Create order summary projection
            table.put_item(
                Item={
                    'OrderId': event_data['orderId'],
                    'UserId': event_data['userId'],
                    'Items': event_data['items'],
                    'TotalAmount': Decimal(str(event_data['totalAmount'])),
                    'Status': 'Created',
                    'CreatedAt': event_data['createdAt'],
                    'UpdatedAt': event_data['createdAt'],
                    'Version': detail['Version']
                }
            )
            print(f"Created order summary for {event_data['orderId']}")
            
        elif event_type == 'OrderStatusUpdated':
            # Update order status in projection
            table.update_item(
                Key={'OrderId': event_data['orderId']},
                UpdateExpression="SET #status = :status, UpdatedAt = :updated, Version = :version",
                ExpressionAttributeNames={'#status': 'Status'},
                ExpressionAttributeValues={
                    ':status': event_data['status'],
                    ':updated': event_data['updatedAt'],
                    ':version': detail['Version']
                }
            )
            print(f"Updated order status for {event_data['orderId']}")
        
        return {'statusCode': 200}
        
    except Exception as e:
        print(f"Error in order projection: {str(e)}")
        raise
EOF
    
    # Create query handler source
    cat > "${temp_dir}/query_handler.py" << 'EOF'
import json
import boto3
import os
from boto3.dynamodb.conditions import Key
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        # Parse query from API Gateway or direct invocation
        if 'body' in event and event['body']:
            query = json.loads(event['body'])
        else:
            query = event
            
        query_type = query.get('queryType')
        
        if query_type == 'GetUserProfile':
            result = get_user_profile(query['userId'])
        elif query_type == 'GetUserByEmail':
            result = get_user_by_email(query['email'])
        elif query_type == 'GetOrdersByUser':
            result = get_orders_by_user(query['userId'])
        elif query_type == 'GetOrdersByStatus':
            result = get_orders_by_status(query['status'])
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Unknown query type: {query_type}'})
            }
        
        return {
            'statusCode': 200,
            'body': json.dumps(result, default=decimal_encoder)
        }
        
    except Exception as e:
        print(f"Error processing query: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_user_profile(user_id):
    table = dynamodb.Table(os.environ['USER_READ_MODEL_TABLE'])
    response = table.get_item(Key={'UserId': user_id})
    return response.get('Item')

def get_user_by_email(email):
    table = dynamodb.Table(os.environ['USER_READ_MODEL_TABLE'])
    response = table.query(
        IndexName='Email-index',
        KeyConditionExpression=Key('Email').eq(email)
    )
    return response['Items'][0] if response['Items'] else None

def get_orders_by_user(user_id):
    table = dynamodb.Table(os.environ['ORDER_READ_MODEL_TABLE'])
    response = table.query(
        IndexName='UserId-index',
        KeyConditionExpression=Key('UserId').eq(user_id)
    )
    return response['Items']

def get_orders_by_status(status):
    table = dynamodb.Table(os.environ['ORDER_READ_MODEL_TABLE'])
    response = table.query(
        IndexName='Status-index',
        KeyConditionExpression=Key('Status').eq(status)
    )
    return response['Items']

def decimal_encoder(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError
EOF
    
    # Create Lambda functions
    create_lambda_with_retry \
        "${PROJECT_NAME}-command-handler" \
        "command_handler.lambda_handler" \
        "${command_role_arn}" \
        "{EVENT_STORE_TABLE=${EVENT_STORE_TABLE}}" \
        "command_handler.py"
    
    create_lambda_with_retry \
        "${PROJECT_NAME}-stream-processor" \
        "stream_processor.lambda_handler" \
        "${command_role_arn}" \
        "{EVENT_BUS_NAME=${EVENT_BUS_NAME}}" \
        "stream_processor.py"
    
    create_lambda_with_retry \
        "${PROJECT_NAME}-user-projection" \
        "user_projection.lambda_handler" \
        "${projection_role_arn}" \
        "{USER_READ_MODEL_TABLE=${USER_READ_MODEL_TABLE}}" \
        "user_projection.py"
    
    create_lambda_with_retry \
        "${PROJECT_NAME}-order-projection" \
        "order_projection.lambda_handler" \
        "${projection_role_arn}" \
        "{ORDER_READ_MODEL_TABLE=${ORDER_READ_MODEL_TABLE}}" \
        "order_projection.py"
    
    create_lambda_with_retry \
        "${PROJECT_NAME}-query-handler" \
        "query_handler.lambda_handler" \
        "${projection_role_arn}" \
        "{USER_READ_MODEL_TABLE=${USER_READ_MODEL_TABLE},ORDER_READ_MODEL_TABLE=${ORDER_READ_MODEL_TABLE}}" \
        "query_handler.py"
    
    # Cleanup temp directory
    rm -rf "${temp_dir}"
    
    log_success "All Lambda functions created successfully"
}

connect_dynamodb_stream() {
    log_info "Connecting DynamoDB Stream to Lambda..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would connect DynamoDB stream to Lambda"
        return 0
    fi
    
    # Get DynamoDB stream ARN
    local stream_arn
    stream_arn=$(aws dynamodb describe-table \
        --table-name "${EVENT_STORE_TABLE}" \
        --query 'Table.LatestStreamArn' \
        --output text)
    
    if [[ "${stream_arn}" == "None" || -z "${stream_arn}" ]]; then
        log_error "No stream ARN found for table ${EVENT_STORE_TABLE}"
        return 1
    fi
    
    # Create event source mapping
    aws lambda create-event-source-mapping \
        --function-name "${PROJECT_NAME}-stream-processor" \
        --event-source-arn "${stream_arn}" \
        --starting-position LATEST \
        --batch-size 10 >/dev/null
    
    log_success "DynamoDB stream connected to Lambda processor"
}

create_eventbridge_rules() {
    log_info "Creating EventBridge rules and targets..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create EventBridge rules"
        return 0
    fi
    
    # Create rule for user events
    aws events put-rule \
        --name "${PROJECT_NAME}-user-events" \
        --event-pattern '{
            "source": ["cqrs.demo"],
            "detail-type": ["UserCreated", "UserProfileUpdated"]
        }' \
        --event-bus-name "${EVENT_BUS_NAME}" >/dev/null
    
    # Create rule for order events  
    aws events put-rule \
        --name "${PROJECT_NAME}-order-events" \
        --event-pattern '{
            "source": ["cqrs.demo"],
            "detail-type": ["OrderCreated", "OrderStatusUpdated"]
        }' \
        --event-bus-name "${EVENT_BUS_NAME}" >/dev/null
    
    # Add Lambda permissions for EventBridge
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-user-projection" \
        --statement-id "EventBridgeInvoke" \
        --action "lambda:InvokeFunction" \
        --principal "events.amazonaws.com" \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENT_BUS_NAME}/${PROJECT_NAME}-user-events" >/dev/null 2>&1 || true
    
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-order-projection" \
        --statement-id "EventBridgeInvoke" \
        --action "lambda:InvokeFunction" \
        --principal "events.amazonaws.com" \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENT_BUS_NAME}/${PROJECT_NAME}-order-events" >/dev/null 2>&1 || true
    
    # Add targets to rules
    aws events put-targets \
        --rule "${PROJECT_NAME}-user-events" \
        --event-bus-name "${EVENT_BUS_NAME}" \
        --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-user-projection" >/dev/null
    
    aws events put-targets \
        --rule "${PROJECT_NAME}-order-events" \
        --event-bus-name "${EVENT_BUS_NAME}" \
        --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-order-projection" >/dev/null
    
    log_success "EventBridge rules and targets configured"
}

# =============================================================================
# Main Deployment Function
# =============================================================================

deploy_infrastructure() {
    log_info "Starting CQRS and Event Sourcing infrastructure deployment..."
    
    setup_environment
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "=== DRY RUN MODE - NO RESOURCES WILL BE CREATED ==="
    fi
    
    # Deploy infrastructure components
    create_event_store_table
    create_read_model_tables
    create_eventbridge_bus
    create_iam_roles
    create_lambda_functions
    connect_dynamodb_stream
    create_eventbridge_rules
    
    log_success "CQRS and Event Sourcing infrastructure deployed successfully!"
    
    # Output deployment summary
    cat << EOF

=============================================================================
                        DEPLOYMENT SUMMARY
=============================================================================
Project Name:           ${PROJECT_NAME}
AWS Region:             ${AWS_REGION}
AWS Account:            ${AWS_ACCOUNT_ID}

EVENT STORE:
- DynamoDB Table:       ${EVENT_STORE_TABLE}

READ MODELS:
- User Profiles:        ${USER_READ_MODEL_TABLE}
- Order Summaries:      ${ORDER_READ_MODEL_TABLE}

EVENT PROCESSING:
- EventBridge Bus:      ${EVENT_BUS_NAME}
- Archive:              ${EVENT_BUS_NAME}-archive

LAMBDA FUNCTIONS:
- Command Handler:      ${PROJECT_NAME}-command-handler
- Stream Processor:     ${PROJECT_NAME}-stream-processor
- User Projection:      ${PROJECT_NAME}-user-projection
- Order Projection:     ${PROJECT_NAME}-order-projection
- Query Handler:        ${PROJECT_NAME}-query-handler

IAM ROLES:
- Command Role:         ${PROJECT_NAME}-command-role
- Projection Role:      ${PROJECT_NAME}-projection-role

LOG FILE:               ${LOG_FILE}

NEXT STEPS:
1. Test the deployment by invoking the command handler with sample commands
2. Verify read models are updated correctly
3. Monitor CloudWatch logs for any issues
4. Use the destroy.sh script to clean up resources when done

=============================================================================
EOF
}

# =============================================================================
# Main Script Execution
# =============================================================================

main() {
    # Parse command line arguments
    local project_name="${DEFAULT_PROJECT_NAME}"
    local region="${DEFAULT_REGION}"
    local dry_run=false
    local verbose=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--project-name)
                project_name="$2"
                shift 2
                ;;
            -r|--region)
                region="$2"
                shift 2
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Set global variables
    PROJECT_NAME_PREFIX="${project_name}"
    REGION="${region}"
    DRY_RUN="${dry_run}"
    VERBOSE="${verbose}"
    
    # Enable verbose logging if requested
    if [[ "${verbose}" == "true" ]]; then
        set -x
    fi
    
    # Set up error handling
    trap cleanup_on_error EXIT
    
    log_info "Starting CQRS and Event Sourcing deployment script"
    log_info "Log file: ${LOG_FILE}"
    
    # Check prerequisites
    if ! check_prerequisites; then
        log_error "Prerequisites check failed. Please resolve the issues and try again."
        exit 1
    fi
    
    # Deploy infrastructure
    deploy_infrastructure
    
    # Clear error trap on successful completion
    trap - EXIT
    
    log_success "Deployment completed successfully!"
    exit 0
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi