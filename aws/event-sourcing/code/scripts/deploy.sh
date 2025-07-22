#!/bin/bash

# Event Sourcing Architecture Deployment Script
# This script deploys the complete event sourcing architecture with EventBridge and DynamoDB

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Deploy Event Sourcing Architecture with EventBridge and DynamoDB"
    echo ""
    echo "Options:"
    echo "  -r, --region REGION          AWS region (default: from AWS CLI config)"
    echo "  -s, --suffix SUFFIX          Resource suffix (default: auto-generated)"
    echo "  -d, --dry-run               Perform a dry run without creating resources"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_REGION                  AWS region override"
    echo "  RESOURCE_SUFFIX            Resource suffix override"
    echo ""
    exit 1
}

# Parse command line arguments
DRY_RUN=false
CUSTOM_SUFFIX=""
CUSTOM_REGION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            CUSTOM_REGION="$2"
            shift 2
            ;;
        -s|--suffix)
            CUSTOM_SUFFIX="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            usage
            ;;
    esac
done

# Cleanup function for error handling
cleanup() {
    if [ $? -ne 0 ]; then
        error "Deployment failed. Check the logs above for details."
        warn "You may need to manually clean up partially created resources."
    fi
}

trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [ -z "$account_id" ]; then
        error "Unable to get AWS account ID. Check your AWS credentials."
        exit 1
    fi
    
    # Check if Python is available for Lambda packaging
    if ! command -v python3 &> /dev/null; then
        error "Python3 is not installed. Required for Lambda function packaging."
        exit 1
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        error "zip command is not installed. Required for Lambda function packaging."
        exit 1
    fi
    
    log "Prerequisites check passed ✅"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    if [ -n "$CUSTOM_REGION" ]; then
        export AWS_REGION="$CUSTOM_REGION"
    else
        export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate or use custom suffix
    if [ -n "$CUSTOM_SUFFIX" ]; then
        RANDOM_SUFFIX="$CUSTOM_SUFFIX"
    else
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    fi
    
    # Set resource names
    export EVENT_BUS_NAME="event-sourcing-bus-${RANDOM_SUFFIX}"
    export EVENT_STORE_TABLE="event-store-${RANDOM_SUFFIX}"
    export READ_MODEL_TABLE="read-model-${RANDOM_SUFFIX}"
    export COMMAND_FUNCTION="command-handler-${RANDOM_SUFFIX}"
    export PROJECTION_FUNCTION="projection-handler-${RANDOM_SUFFIX}"
    export QUERY_FUNCTION="query-handler-${RANDOM_SUFFIX}"
    export DLQ_NAME="event-sourcing-dlq-${RANDOM_SUFFIX}"
    
    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "Resource Suffix: $RANDOM_SUFFIX"
    
    # Store configuration for cleanup
    cat > .deployment_config << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
RANDOM_SUFFIX=$RANDOM_SUFFIX
EVENT_BUS_NAME=$EVENT_BUS_NAME
EVENT_STORE_TABLE=$EVENT_STORE_TABLE
READ_MODEL_TABLE=$READ_MODEL_TABLE
COMMAND_FUNCTION=$COMMAND_FUNCTION
PROJECTION_FUNCTION=$PROJECTION_FUNCTION
QUERY_FUNCTION=$QUERY_FUNCTION
DLQ_NAME=$DLQ_NAME
DEPLOYMENT_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    
    log "Environment setup complete ✅"
}

# Check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    
    case $resource_type in
        "iam-role")
            aws iam get-role --role-name "$resource_name" &>/dev/null
            ;;
        "iam-policy")
            aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$resource_name" &>/dev/null
            ;;
        "eventbridge-bus")
            aws events describe-event-bus --name "$resource_name" &>/dev/null
            ;;
        "dynamodb-table")
            aws dynamodb describe-table --table-name "$resource_name" &>/dev/null
            ;;
        "lambda-function")
            aws lambda get-function --function-name "$resource_name" &>/dev/null
            ;;
        "sqs-queue")
            aws sqs get-queue-url --queue-name "$resource_name" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Create IAM resources
create_iam_resources() {
    log "Creating IAM resources..."
    
    local role_name="event-sourcing-lambda-role"
    local policy_name="EventSourcingPolicy"
    
    # Create Lambda execution role if it doesn't exist
    if ! resource_exists "iam-role" "$role_name"; then
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would create IAM role: $role_name"
        else
            aws iam create-role \
                --role-name "$role_name" \
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
                }' \
                --description "Execution role for Event Sourcing Lambda functions"
            
            # Wait for role to be available
            aws iam wait role-exists --role-name "$role_name"
            log "Created IAM role: $role_name ✅"
        fi
    else
        warn "IAM role $role_name already exists, skipping creation"
    fi
    
    # Attach basic execution policy
    if [ "$DRY_RUN" = false ]; then
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    fi
    
    # Create custom policy if it doesn't exist
    if ! resource_exists "iam-policy" "$policy_name"; then
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would create IAM policy: $policy_name"
        else
            aws iam create-policy \
                --policy-name "$policy_name" \
                --policy-document '{
                    "Version": "2012-10-17",
                    "Statement": [
                        {
                            "Effect": "Allow",
                            "Action": [
                                "events:PutEvents",
                                "events:List*",
                                "events:Describe*"
                            ],
                            "Resource": "*"
                        },
                        {
                            "Effect": "Allow",
                            "Action": [
                                "dynamodb:PutItem",
                                "dynamodb:GetItem",
                                "dynamodb:Query",
                                "dynamodb:Scan",
                                "dynamodb:UpdateItem",
                                "dynamodb:DeleteItem",
                                "dynamodb:BatchGetItem",
                                "dynamodb:BatchWriteItem"
                            ],
                            "Resource": "*"
                        },
                        {
                            "Effect": "Allow",
                            "Action": [
                                "sqs:SendMessage",
                                "sqs:ReceiveMessage",
                                "sqs:DeleteMessage",
                                "sqs:GetQueueAttributes"
                            ],
                            "Resource": "*"
                        }
                    ]
                }' \
                --description "Policy for Event Sourcing Lambda functions"
            
            log "Created IAM policy: $policy_name ✅"
        fi
    else
        warn "IAM policy $policy_name already exists, skipping creation"
    fi
    
    # Attach custom policy
    if [ "$DRY_RUN" = false ]; then
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy_name"
        
        log "Attached policies to role ✅"
    fi
}

# Create EventBridge resources
create_eventbridge_resources() {
    log "Creating EventBridge resources..."
    
    # Create custom event bus
    if ! resource_exists "eventbridge-bus" "$EVENT_BUS_NAME"; then
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would create EventBridge bus: $EVENT_BUS_NAME"
        else
            aws events create-event-bus \
                --name "$EVENT_BUS_NAME" \
                --description "Event sourcing bus for financial transactions"
            
            log "Created EventBridge bus: $EVENT_BUS_NAME ✅"
        fi
    else
        warn "EventBridge bus $EVENT_BUS_NAME already exists, skipping creation"
    fi
    
    # Create event archive
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would create EventBridge archive: ${EVENT_BUS_NAME}-archive"
    else
        aws events create-archive \
            --archive-name "${EVENT_BUS_NAME}-archive" \
            --event-source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:event-bus/${EVENT_BUS_NAME}" \
            --retention-days 365 \
            --description "Archive for event replay and audit" || warn "Archive creation failed or already exists"
        
        log "Created EventBridge archive ✅"
    fi
}

# Create DynamoDB tables
create_dynamodb_tables() {
    log "Creating DynamoDB tables..."
    
    # Create event store table
    if ! resource_exists "dynamodb-table" "$EVENT_STORE_TABLE"; then
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would create DynamoDB table: $EVENT_STORE_TABLE"
        else
            aws dynamodb create-table \
                --table-name "$EVENT_STORE_TABLE" \
                --attribute-definitions \
                    AttributeName=AggregateId,AttributeType=S \
                    AttributeName=EventSequence,AttributeType=N \
                    AttributeName=EventType,AttributeType=S \
                    AttributeName=Timestamp,AttributeType=S \
                --key-schema \
                    AttributeName=AggregateId,KeyType=HASH \
                    AttributeName=EventSequence,KeyType=RANGE \
                --global-secondary-indexes \
                    IndexName=EventType-Timestamp-index,KeySchema=[{AttributeName=EventType,KeyType=HASH},{AttributeName=Timestamp,KeyType=RANGE}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5} \
                --provisioned-throughput ReadCapacityUnits=10,WriteCapacityUnits=10 \
                --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
                --tags Key=Purpose,Value=EventSourcing Key=Environment,Value=Development
            
            # Wait for table to be active
            info "Waiting for event store table to be active..."
            aws dynamodb wait table-exists --table-name "$EVENT_STORE_TABLE"
            log "Created event store table: $EVENT_STORE_TABLE ✅"
        fi
    else
        warn "DynamoDB table $EVENT_STORE_TABLE already exists, skipping creation"
    fi
    
    # Create read model table
    if ! resource_exists "dynamodb-table" "$READ_MODEL_TABLE"; then
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would create DynamoDB table: $READ_MODEL_TABLE"
        else
            aws dynamodb create-table \
                --table-name "$READ_MODEL_TABLE" \
                --attribute-definitions \
                    AttributeName=AccountId,AttributeType=S \
                    AttributeName=ProjectionType,AttributeType=S \
                --key-schema \
                    AttributeName=AccountId,KeyType=HASH \
                    AttributeName=ProjectionType,KeyType=RANGE \
                --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
                --tags Key=Purpose,Value=EventSourcing Key=Environment,Value=Development
            
            # Wait for table to be active
            info "Waiting for read model table to be active..."
            aws dynamodb wait table-exists --table-name "$READ_MODEL_TABLE"
            log "Created read model table: $READ_MODEL_TABLE ✅"
        fi
    else
        warn "DynamoDB table $READ_MODEL_TABLE already exists, skipping creation"
    fi
}

# Create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create command handler function
    if ! resource_exists "lambda-function" "$COMMAND_FUNCTION"; then
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would create Lambda function: $COMMAND_FUNCTION"
        else
            # Create function code
            cat > command-handler.py << 'EOF'
import json
import boto3
import uuid
from datetime import datetime
import os

events_client = boto3.client('events')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['EVENT_STORE_TABLE'])

def lambda_handler(event, context):
    try:
        # Parse command from event
        command = json.loads(event['body']) if 'body' in event else event
        
        # Generate event from command
        event_id = str(uuid.uuid4())
        aggregate_id = command['aggregateId']
        event_type = command['eventType']
        event_data = command['eventData']
        
        # Get next sequence number
        response = table.query(
            KeyConditionExpression='AggregateId = :aid',
            ExpressionAttributeValues={':aid': aggregate_id},
            ScanIndexForward=False,
            Limit=1
        )
        
        next_sequence = 1
        if response['Items']:
            next_sequence = response['Items'][0]['EventSequence'] + 1
        
        # Create event record
        timestamp = datetime.utcnow().isoformat()
        event_record = {
            'EventId': event_id,
            'AggregateId': aggregate_id,
            'EventSequence': next_sequence,
            'EventType': event_type,
            'EventData': event_data,
            'Timestamp': timestamp,
            'Version': '1.0'
        }
        
        # Store event in DynamoDB
        table.put_item(Item=event_record)
        
        # Publish event to EventBridge
        events_client.put_events(
            Entries=[
                {
                    'Source': 'event-sourcing.financial',
                    'DetailType': event_type,
                    'Detail': json.dumps(event_record),
                    'EventBusName': os.environ['EVENT_BUS_NAME']
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'eventId': event_id,
                'aggregateId': aggregate_id,
                'sequence': next_sequence
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
            
            # Package function
            zip -q command-handler.zip command-handler.py
            
            # Create function
            aws lambda create-function \
                --function-name "$COMMAND_FUNCTION" \
                --runtime python3.9 \
                --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/event-sourcing-lambda-role" \
                --handler command-handler.lambda_handler \
                --zip-file fileb://command-handler.zip \
                --environment Variables="{EVENT_STORE_TABLE=${EVENT_STORE_TABLE},EVENT_BUS_NAME=${EVENT_BUS_NAME}}" \
                --timeout 30 \
                --description "Command handler for event sourcing architecture" \
                --tags Purpose=EventSourcing,Environment=Development
            
            log "Created command handler function: $COMMAND_FUNCTION ✅"
        fi
    else
        warn "Lambda function $COMMAND_FUNCTION already exists, skipping creation"
    fi
    
    # Create projection handler function
    if ! resource_exists "lambda-function" "$PROJECTION_FUNCTION"; then
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would create Lambda function: $PROJECTION_FUNCTION"
        else
            # Create function code
            cat > projection-handler.py << 'EOF'
import json
import boto3
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
read_model_table = dynamodb.Table(os.environ['READ_MODEL_TABLE'])

def lambda_handler(event, context):
    try:
        # Process EventBridge events
        for record in event['Records']:
            detail = json.loads(record['body']) if 'body' in record else record['detail']
            
            event_type = detail['EventType']
            aggregate_id = detail['AggregateId']
            event_data = detail['EventData']
            
            # Handle different event types
            if event_type == 'AccountCreated':
                handle_account_created(aggregate_id, event_data)
            elif event_type == 'TransactionProcessed':
                handle_transaction_processed(aggregate_id, event_data)
            elif event_type == 'AccountClosed':
                handle_account_closed(aggregate_id, event_data)
                
        return {'statusCode': 200}
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def handle_account_created(aggregate_id, event_data):
    read_model_table.put_item(
        Item={
            'AccountId': aggregate_id,
            'ProjectionType': 'AccountSummary',
            'Balance': Decimal('0.00'),
            'Status': 'Active',
            'CreatedAt': event_data['createdAt'],
            'TransactionCount': 0
        }
    )

def handle_transaction_processed(aggregate_id, event_data):
    # Update account balance
    response = read_model_table.get_item(
        Key={'AccountId': aggregate_id, 'ProjectionType': 'AccountSummary'}
    )
    
    if 'Item' in response:
        current_balance = response['Item']['Balance']
        transaction_count = response['Item']['TransactionCount']
        
        new_balance = current_balance + Decimal(str(event_data['amount']))
        
        read_model_table.update_item(
            Key={'AccountId': aggregate_id, 'ProjectionType': 'AccountSummary'},
            UpdateExpression='SET Balance = :balance, TransactionCount = :count, LastTransactionAt = :timestamp',
            ExpressionAttributeValues={
                ':balance': new_balance,
                ':count': transaction_count + 1,
                ':timestamp': event_data['timestamp']
            }
        )

def handle_account_closed(aggregate_id, event_data):
    read_model_table.update_item(
        Key={'AccountId': aggregate_id, 'ProjectionType': 'AccountSummary'},
        UpdateExpression='SET #status = :status, ClosedAt = :timestamp',
        ExpressionAttributeNames={'#status': 'Status'},
        ExpressionAttributeValues={
            ':status': 'Closed',
            ':timestamp': event_data['closedAt']
        }
    )
EOF
            
            # Package function
            zip -q projection-handler.zip projection-handler.py
            
            # Create function
            aws lambda create-function \
                --function-name "$PROJECTION_FUNCTION" \
                --runtime python3.9 \
                --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/event-sourcing-lambda-role" \
                --handler projection-handler.lambda_handler \
                --zip-file fileb://projection-handler.zip \
                --environment Variables="{READ_MODEL_TABLE=${READ_MODEL_TABLE}}" \
                --timeout 30 \
                --description "Projection handler for event sourcing architecture" \
                --tags Purpose=EventSourcing,Environment=Development
            
            log "Created projection handler function: $PROJECTION_FUNCTION ✅"
        fi
    else
        warn "Lambda function $PROJECTION_FUNCTION already exists, skipping creation"
    fi
    
    # Create query handler function
    if ! resource_exists "lambda-function" "$QUERY_FUNCTION"; then
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would create Lambda function: $QUERY_FUNCTION"
        else
            # Create function code
            cat > query-handler.py << 'EOF'
import json
import boto3
import os
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')
event_store_table = dynamodb.Table(os.environ['EVENT_STORE_TABLE'])
read_model_table = dynamodb.Table(os.environ['READ_MODEL_TABLE'])

def lambda_handler(event, context):
    try:
        query_type = event['queryType']
        
        if query_type == 'getAggregateEvents':
            return get_aggregate_events(event['aggregateId'])
        elif query_type == 'getAccountSummary':
            return get_account_summary(event['accountId'])
        elif query_type == 'reconstructState':
            return reconstruct_state(event['aggregateId'], event.get('upToSequence'))
        else:
            return {'statusCode': 400, 'body': json.dumps({'error': 'Unknown query type'})}
            
    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def get_aggregate_events(aggregate_id):
    response = event_store_table.query(
        KeyConditionExpression=Key('AggregateId').eq(aggregate_id),
        ScanIndexForward=True
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'aggregateId': aggregate_id,
            'events': response['Items']
        }, default=str)
    }

def get_account_summary(account_id):
    response = read_model_table.get_item(
        Key={'AccountId': account_id, 'ProjectionType': 'AccountSummary'}
    )
    
    if 'Item' in response:
        return {
            'statusCode': 200,
            'body': json.dumps(response['Item'], default=str)
        }
    else:
        return {'statusCode': 404, 'body': json.dumps({'error': 'Account not found'})}

def reconstruct_state(aggregate_id, up_to_sequence=None):
    # Reconstruct state by replaying events
    key_condition = Key('AggregateId').eq(aggregate_id)
    
    if up_to_sequence:
        key_condition = key_condition & Key('EventSequence').lte(up_to_sequence)
    
    response = event_store_table.query(
        KeyConditionExpression=key_condition,
        ScanIndexForward=True
    )
    
    # Replay events to reconstruct state
    state = {'balance': 0, 'status': 'Unknown', 'transactionCount': 0}
    
    for event in response['Items']:
        event_type = event['EventType']
        event_data = event['EventData']
        
        if event_type == 'AccountCreated':
            state['status'] = 'Active'
            state['createdAt'] = event_data['createdAt']
        elif event_type == 'TransactionProcessed':
            state['balance'] += float(event_data['amount'])
            state['transactionCount'] += 1
        elif event_type == 'AccountClosed':
            state['status'] = 'Closed'
            state['closedAt'] = event_data['closedAt']
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'aggregateId': aggregate_id,
            'reconstructedState': state,
            'eventsProcessed': len(response['Items'])
        }, default=str)
    }
EOF
            
            # Package function
            zip -q query-handler.zip query-handler.py
            
            # Create function
            aws lambda create-function \
                --function-name "$QUERY_FUNCTION" \
                --runtime python3.9 \
                --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/event-sourcing-lambda-role" \
                --handler query-handler.lambda_handler \
                --zip-file fileb://query-handler.zip \
                --environment Variables="{EVENT_STORE_TABLE=${EVENT_STORE_TABLE},READ_MODEL_TABLE=${READ_MODEL_TABLE}}" \
                --timeout 30 \
                --description "Query handler for event sourcing architecture" \
                --tags Purpose=EventSourcing,Environment=Development
            
            log "Created query handler function: $QUERY_FUNCTION ✅"
        fi
    else
        warn "Lambda function $QUERY_FUNCTION already exists, skipping creation"
    fi
}

# Create SQS Dead Letter Queue
create_sqs_resources() {
    log "Creating SQS resources..."
    
    if ! resource_exists "sqs-queue" "$DLQ_NAME"; then
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would create SQS queue: $DLQ_NAME"
        else
            aws sqs create-queue \
                --queue-name "$DLQ_NAME" \
                --attributes '{
                    "MessageRetentionPeriod": "1209600",
                    "VisibilityTimeoutSeconds": "300"
                }' \
                --tags Purpose=EventSourcing,Environment=Development
            
            log "Created SQS dead letter queue: $DLQ_NAME ✅"
        fi
    else
        warn "SQS queue $DLQ_NAME already exists, skipping creation"
    fi
}

# Create EventBridge rules and targets
create_eventbridge_rules() {
    log "Creating EventBridge rules and targets..."
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would create EventBridge rules and targets"
        return
    fi
    
    # Create rule for financial events
    aws events put-rule \
        --name "financial-events-rule" \
        --event-pattern '{
            "source": ["event-sourcing.financial"],
            "detail-type": ["AccountCreated", "TransactionProcessed", "AccountClosed"]
        }' \
        --state ENABLED \
        --description "Route financial events to projection handler" \
        --event-bus-name "$EVENT_BUS_NAME"
    
    # Add Lambda target to the rule
    aws events put-targets \
        --rule "financial-events-rule" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECTION_FUNCTION}"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "$PROJECTION_FUNCTION" \
        --statement-id "allow-eventbridge-invoke" \
        --action "lambda:InvokeFunction" \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENT_BUS_NAME}/financial-events-rule" || warn "Permission already exists"
    
    # Create rule for failed events
    aws events put-rule \
        --name "failed-events-rule" \
        --event-pattern '{
            "source": ["aws.events"],
            "detail-type": ["Event Processing Failed"]
        }' \
        --state ENABLED \
        --event-bus-name "$EVENT_BUS_NAME"
    
    # Get DLQ ARN
    local dlq_url=$(aws sqs get-queue-url --queue-name "$DLQ_NAME" --query 'QueueUrl' --output text)
    local dlq_arn="arn:aws:sqs:${AWS_REGION}:${AWS_ACCOUNT_ID}:${DLQ_NAME}"
    
    # Add SQS target for failed events
    aws events put-targets \
        --rule "failed-events-rule" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --targets "Id"="1","Arn"="$dlq_arn"
    
    log "Created EventBridge rules and targets ✅"
}

# Create CloudWatch monitoring
create_cloudwatch_monitoring() {
    log "Creating CloudWatch monitoring..."
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would create CloudWatch alarms"
        return
    fi
    
    # Create alarm for DynamoDB write throttles
    aws cloudwatch put-metric-alarm \
        --alarm-name "EventStore-WriteThrottles-${RANDOM_SUFFIX}" \
        --alarm-description "DynamoDB write throttles on event store" \
        --metric-name WriteThrottleEvents \
        --namespace AWS/DynamoDB \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=TableName,Value="$EVENT_STORE_TABLE"
    
    # Create alarm for Lambda errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "CommandHandler-Errors-${RANDOM_SUFFIX}" \
        --alarm-description "High error rate in command handler" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 10 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=FunctionName,Value="$COMMAND_FUNCTION"
    
    # Create alarm for EventBridge failed invocations
    aws cloudwatch put-metric-alarm \
        --alarm-name "EventBridge-FailedInvocations-${RANDOM_SUFFIX}" \
        --alarm-description "High number of failed event invocations" \
        --metric-name FailedInvocations \
        --namespace AWS/Events \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=EventBusName,Value="$EVENT_BUS_NAME"
    
    log "Created CloudWatch monitoring alarms ✅"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would validate deployment"
        return
    fi
    
    local validation_errors=0
    
    # Check EventBridge bus
    if ! aws events describe-event-bus --name "$EVENT_BUS_NAME" &>/dev/null; then
        error "EventBridge bus $EVENT_BUS_NAME not found"
        ((validation_errors++))
    fi
    
    # Check DynamoDB tables
    if ! aws dynamodb describe-table --table-name "$EVENT_STORE_TABLE" &>/dev/null; then
        error "DynamoDB table $EVENT_STORE_TABLE not found"
        ((validation_errors++))
    fi
    
    if ! aws dynamodb describe-table --table-name "$READ_MODEL_TABLE" &>/dev/null; then
        error "DynamoDB table $READ_MODEL_TABLE not found"
        ((validation_errors++))
    fi
    
    # Check Lambda functions
    if ! aws lambda get-function --function-name "$COMMAND_FUNCTION" &>/dev/null; then
        error "Lambda function $COMMAND_FUNCTION not found"
        ((validation_errors++))
    fi
    
    if ! aws lambda get-function --function-name "$PROJECTION_FUNCTION" &>/dev/null; then
        error "Lambda function $PROJECTION_FUNCTION not found"
        ((validation_errors++))
    fi
    
    if ! aws lambda get-function --function-name "$QUERY_FUNCTION" &>/dev/null; then
        error "Lambda function $QUERY_FUNCTION not found"
        ((validation_errors++))
    fi
    
    # Check SQS queue
    if ! aws sqs get-queue-url --queue-name "$DLQ_NAME" &>/dev/null; then
        error "SQS queue $DLQ_NAME not found"
        ((validation_errors++))
    fi
    
    if [ $validation_errors -eq 0 ]; then
        log "Deployment validation passed ✅"
    else
        error "Deployment validation failed with $validation_errors errors"
        return 1
    fi
}

# Print deployment summary
print_summary() {
    log "Deployment Summary"
    echo "==================="
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account ID: $AWS_ACCOUNT_ID"
    echo "Resource Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Created Resources:"
    echo "- EventBridge Bus: $EVENT_BUS_NAME"
    echo "- Event Store Table: $EVENT_STORE_TABLE"
    echo "- Read Model Table: $READ_MODEL_TABLE"
    echo "- Command Function: $COMMAND_FUNCTION"
    echo "- Projection Function: $PROJECTION_FUNCTION"
    echo "- Query Function: $QUERY_FUNCTION"
    echo "- Dead Letter Queue: $DLQ_NAME"
    echo ""
    echo "Configuration saved to: .deployment_config"
    echo ""
    echo "Next Steps:"
    echo "1. Test the deployment using the command handler function"
    echo "2. Monitor CloudWatch alarms for any issues"
    echo "3. Use the query handler to retrieve event data"
    echo "4. Run ./destroy.sh to clean up resources when done"
}

# Main deployment function
main() {
    log "Starting Event Sourcing Architecture deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    if [ "$DRY_RUN" = true ]; then
        warn "DRY RUN MODE - No resources will be created"
    fi
    
    # Create resources
    create_iam_resources
    create_eventbridge_resources
    create_dynamodb_tables
    create_lambda_functions
    create_sqs_resources
    create_eventbridge_rules
    create_cloudwatch_monitoring
    
    # Validate deployment
    validate_deployment
    
    # Clean up temporary files
    if [ "$DRY_RUN" = false ]; then
        rm -f command-handler.py command-handler.zip
        rm -f projection-handler.py projection-handler.zip
        rm -f query-handler.py query-handler.zip
    fi
    
    # Print summary
    print_summary
    
    log "Deployment completed successfully! 🎉"
}

# Run main function
main "$@"