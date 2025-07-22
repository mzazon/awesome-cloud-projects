#!/bin/bash

# Deploy script for Real-Time WebSocket APIs with Route Management and Connection Handling
# This script deploys a comprehensive WebSocket API using API Gateway, Lambda, and DynamoDB

set -e  # Exit on any error

# Colors for output
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

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    warn "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    info "$description"
    
    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY-RUN: $cmd"
        return 0
    else
        eval "$cmd"
        return $?
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if Python 3 is installed (for test client)
    if ! command -v python3 &> /dev/null; then
        warn "Python 3 is not installed. Test client will not be available."
    fi
    
    # Check if required Python packages are available
    if command -v python3 &> /dev/null; then
        if ! python3 -c "import websockets" &> /dev/null; then
            warn "Python websockets package not installed. Install with: pip install websockets"
        fi
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d. -f1)
    if [ "$aws_version" -lt 2 ]; then
        warn "AWS CLI version 2 is recommended. Current version: $(aws --version)"
    fi
    
    log "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "No AWS region configured, using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export RANDOM_SUFFIX="$random_suffix"
    export API_NAME="websocket-api-${RANDOM_SUFFIX}"
    export CONNECTIONS_TABLE="websocket-connections-${RANDOM_SUFFIX}"
    export ROOMS_TABLE="websocket-rooms-${RANDOM_SUFFIX}"
    export MESSAGES_TABLE="websocket-messages-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="websocket-lambda-role-${RANDOM_SUFFIX}"
    export POLICY_NAME="websocket-policy-${RANDOM_SUFFIX}"
    
    # Create deployment info file
    cat > deployment-info.txt << EOF
DEPLOYMENT_ID=${RANDOM_SUFFIX}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
API_NAME=${API_NAME}
CONNECTIONS_TABLE=${CONNECTIONS_TABLE}
ROOMS_TABLE=${ROOMS_TABLE}
MESSAGES_TABLE=${MESSAGES_TABLE}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
POLICY_NAME=${POLICY_NAME}
EOF
    
    log "Environment variables configured"
    info "Deployment ID: ${RANDOM_SUFFIX}"
    info "AWS Region: ${AWS_REGION}"
    info "AWS Account: ${AWS_ACCOUNT_ID}"
}

# Function to create DynamoDB tables
create_dynamodb_tables() {
    log "Creating DynamoDB tables..."
    
    # Create connections table
    execute_cmd "aws dynamodb create-table \
        --table-name ${CONNECTIONS_TABLE} \
        --attribute-definitions \
            AttributeName=connectionId,AttributeType=S \
            AttributeName=userId,AttributeType=S \
            AttributeName=roomId,AttributeType=S \
        --key-schema \
            AttributeName=connectionId,KeyType=HASH \
        --global-secondary-indexes \
            'IndexName=UserIndex,KeySchema=[{AttributeName=userId,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5}' \
            'IndexName=RoomIndex,KeySchema=[{AttributeName=roomId,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5}' \
        --provisioned-throughput \
            ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region ${AWS_REGION}" "Creating connections table"
    
    # Create rooms table
    execute_cmd "aws dynamodb create-table \
        --table-name ${ROOMS_TABLE} \
        --attribute-definitions \
            AttributeName=roomId,AttributeType=S \
            AttributeName=ownerId,AttributeType=S \
        --key-schema \
            AttributeName=roomId,KeyType=HASH \
        --global-secondary-indexes \
            'IndexName=OwnerIndex,KeySchema=[{AttributeName=ownerId,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5}' \
        --provisioned-throughput \
            ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region ${AWS_REGION}" "Creating rooms table"
    
    # Create messages table
    execute_cmd "aws dynamodb create-table \
        --table-name ${MESSAGES_TABLE} \
        --attribute-definitions \
            AttributeName=messageId,AttributeType=S \
            AttributeName=roomId,AttributeType=S \
            AttributeName=timestamp,AttributeType=N \
        --key-schema \
            AttributeName=messageId,KeyType=HASH \
        --global-secondary-indexes \
            'IndexName=RoomTimestampIndex,KeySchema=[{AttributeName=roomId,KeyType=HASH},{AttributeName=timestamp,KeyType=RANGE}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5}' \
        --provisioned-throughput \
            ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region ${AWS_REGION}" "Creating messages table"
    
    if [ "$DRY_RUN" != "true" ]; then
        # Wait for tables to be created
        info "Waiting for DynamoDB tables to be created..."
        aws dynamodb wait table-exists --table-name ${CONNECTIONS_TABLE} --region ${AWS_REGION}
        aws dynamodb wait table-exists --table-name ${ROOMS_TABLE} --region ${AWS_REGION}
        aws dynamodb wait table-exists --table-name ${MESSAGES_TABLE} --region ${AWS_REGION}
    fi
    
    log "DynamoDB tables created successfully"
}

# Function to create IAM roles and policies
create_iam_resources() {
    log "Creating IAM roles and policies..."
    
    # Create IAM role for Lambda functions
    execute_cmd "aws iam create-role \
        --role-name ${LAMBDA_ROLE_NAME} \
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
        }'" "Creating Lambda execution role"
    
    # Create custom policy for WebSocket operations
    execute_cmd "aws iam create-policy \
        --policy-name ${POLICY_NAME} \
        --policy-document '{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Action\": [
                        \"dynamodb:Query\",
                        \"dynamodb:Scan\",
                        \"dynamodb:GetItem\",
                        \"dynamodb:PutItem\",
                        \"dynamodb:UpdateItem\",
                        \"dynamodb:DeleteItem\"
                    ],
                    \"Resource\": [
                        \"arn:aws:dynamodb:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':table/'${CONNECTIONS_TABLE}'\",
                        \"arn:aws:dynamodb:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':table/'${CONNECTIONS_TABLE}'/index/*\",
                        \"arn:aws:dynamodb:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':table/'${ROOMS_TABLE}'\",
                        \"arn:aws:dynamodb:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':table/'${ROOMS_TABLE}'/index/*\",
                        \"arn:aws:dynamodb:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':table/'${MESSAGES_TABLE}'\",
                        \"arn:aws:dynamodb:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':table/'${MESSAGES_TABLE}'/index/*\"
                    ]
                },
                {
                    \"Effect\": \"Allow\",
                    \"Action\": [
                        \"execute-api:ManageConnections\"
                    ],
                    \"Resource\": \"arn:aws:execute-api:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':*/@connections/*\"
                }
            ]
        }'" "Creating WebSocket policy"
    
    # Attach policies to role
    execute_cmd "aws iam attach-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" "Attaching Lambda basic execution policy"
    
    execute_cmd "aws iam attach-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" "Attaching custom WebSocket policy"
    
    if [ "$DRY_RUN" != "true" ]; then
        # Wait for role propagation
        info "Waiting for IAM role propagation..."
        sleep 10
    fi
    
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    
    log "IAM resources created successfully"
}

# Function to create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create connection handler function
    cat > connect_handler.py << 'EOF'
import json
import boto3
import os
import time
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')
connections_table = dynamodb.Table(os.environ['CONNECTIONS_TABLE'])

def lambda_handler(event, context):
    connection_id = event['requestContext']['connectionId']
    domain_name = event['requestContext']['domainName']
    stage = event['requestContext']['stage']
    
    # Extract query parameters for authentication and room joining
    query_params = event.get('queryStringParameters') or {}
    user_id = query_params.get('userId', 'anonymous')
    room_id = query_params.get('roomId', 'general')
    auth_token = query_params.get('token')
    
    try:
        # Basic token validation (in production, integrate with Cognito)
        if auth_token:
            # Simulate token validation
            if not auth_token.startswith('valid_'):
                return {
                    'statusCode': 401,
                    'body': json.dumps({'error': 'Invalid authentication token'})
                }
        
        # Store connection information
        connection_data = {
            'connectionId': connection_id,
            'userId': user_id,
            'roomId': room_id,
            'connectedAt': int(time.time()),
            'domainName': domain_name,
            'stage': stage,
            'lastActivity': int(time.time()),
            'status': 'connected'
        }
        
        # Add optional user metadata
        if 'username' in query_params:
            connection_data['username'] = query_params['username']
        
        connections_table.put_item(Item=connection_data)
        
        # Send welcome message
        api_gateway = boto3.client('apigatewaymanagementapi',
            endpoint_url=f'https://{domain_name}/{stage}')
        
        welcome_message = {
            'type': 'welcome',
            'data': {
                'connectionId': connection_id,
                'userId': user_id,
                'roomId': room_id,
                'message': f'Welcome to room {room_id}!',
                'timestamp': int(time.time())
            }
        }
        
        api_gateway.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(welcome_message)
        )
        
        print(f"Connection established: {connection_id} for user {user_id} in room {room_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Connected successfully'})
        }
        
    except ClientError as e:
        print(f"DynamoDB error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Connection failed'})
        }
    except Exception as e:
        print(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }
EOF
    
    if [ "$DRY_RUN" != "true" ]; then
        zip connect_handler.zip connect_handler.py
    fi
    
    execute_cmd "aws lambda create-function \
        --function-name websocket-connect-${RANDOM_SUFFIX} \
        --runtime python3.9 \
        --role ${LAMBDA_ROLE_ARN} \
        --handler connect_handler.lambda_handler \
        --zip-file fileb://connect_handler.zip \
        --description 'WebSocket connection handler' \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables='{
            \"CONNECTIONS_TABLE\": \"'${CONNECTIONS_TABLE}'\"
        }' \
        --region ${AWS_REGION}" "Creating connection handler function"
    
    # Create disconnect handler function
    cat > disconnect_handler.py << 'EOF'
import json
import boto3
import os
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')
connections_table = dynamodb.Table(os.environ['CONNECTIONS_TABLE'])

def lambda_handler(event, context):
    connection_id = event['requestContext']['connectionId']
    
    try:
        # Get connection information before deletion
        response = connections_table.get_item(
            Key={'connectionId': connection_id}
        )
        
        if 'Item' in response:
            connection_data = response['Item']
            user_id = connection_data.get('userId', 'unknown')
            room_id = connection_data.get('roomId', 'unknown')
            
            print(f"Disconnecting user {user_id} from room {room_id}")
        
        # Remove connection from table
        connections_table.delete_item(
            Key={'connectionId': connection_id}
        )
        
        print(f"Connection removed: {connection_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Disconnected successfully'})
        }
        
    except ClientError as e:
        print(f"DynamoDB error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Disconnect failed'})
        }
    except Exception as e:
        print(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }
EOF
    
    if [ "$DRY_RUN" != "true" ]; then
        zip disconnect_handler.zip disconnect_handler.py
    fi
    
    execute_cmd "aws lambda create-function \
        --function-name websocket-disconnect-${RANDOM_SUFFIX} \
        --runtime python3.9 \
        --role ${LAMBDA_ROLE_ARN} \
        --handler disconnect_handler.lambda_handler \
        --zip-file fileb://disconnect_handler.zip \
        --description 'WebSocket disconnect handler' \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables='{
            \"CONNECTIONS_TABLE\": \"'${CONNECTIONS_TABLE}'\"
        }' \
        --region ${AWS_REGION}" "Creating disconnect handler function"
    
    # Create message handler function (truncated for brevity - full implementation would include the complete message_handler.py)
    cat > message_handler.py << 'EOF'
import json
import boto3
import os
import time
import uuid
from botocore.exceptions import ClientError
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')
connections_table = dynamodb.Table(os.environ['CONNECTIONS_TABLE'])
rooms_table = dynamodb.Table(os.environ['ROOMS_TABLE'])
messages_table = dynamodb.Table(os.environ['MESSAGES_TABLE'])

def lambda_handler(event, context):
    connection_id = event['requestContext']['connectionId']
    domain_name = event['requestContext']['domainName']
    stage = event['requestContext']['stage']
    
    # Parse message from client
    try:
        message_data = json.loads(event.get('body', '{}'))
    except json.JSONDecodeError:
        return send_error(connection_id, domain_name, stage, 'Invalid JSON format')
    
    # Get sender connection info
    try:
        sender_response = connections_table.get_item(
            Key={'connectionId': connection_id}
        )
        
        if 'Item' not in sender_response:
            return send_error(connection_id, domain_name, stage, 'Connection not found')
        
        sender_info = sender_response['Item']
        
    except ClientError as e:
        print(f"Error getting sender info: {e}")
        return {'statusCode': 500}
    
    # Route message based on type
    message_type = message_data.get('type', 'chat')
    
    if message_type == 'chat':
        return handle_chat_message(message_data, sender_info, domain_name, stage)
    else:
        return send_error(connection_id, domain_name, stage, f'Unknown message type: {message_type}')

def handle_chat_message(message_data, sender_info, domain_name, stage):
    room_id = message_data.get('roomId', sender_info['roomId'])
    message_content = message_data.get('message', '')
    
    if not message_content.strip():
        return send_error(sender_info['connectionId'], domain_name, stage, 'Message cannot be empty')
    
    # Store message in database
    message_id = str(uuid.uuid4())
    timestamp = int(time.time())
    
    message_record = {
        'messageId': message_id,
        'roomId': room_id,
        'senderId': sender_info['userId'],
        'senderName': sender_info.get('username', sender_info['userId']),
        'message': message_content,
        'timestamp': timestamp,
        'type': 'chat'
    }
    
    messages_table.put_item(Item=message_record)
    
    # Broadcast to all connections in the room
    broadcast_message = {
        'type': 'chat',
        'data': {
            'messageId': message_id,
            'roomId': room_id,
            'senderId': sender_info['userId'],
            'senderName': sender_info.get('username', sender_info['userId']),
            'message': message_content,
            'timestamp': timestamp
        }
    }
    
    broadcast_to_room(room_id, broadcast_message, domain_name, stage)
    
    return {'statusCode': 200}

def broadcast_to_room(room_id, message, domain_name, stage):
    # Get all connections in the room
    response = connections_table.query(
        IndexName='RoomIndex',
        KeyConditionExpression=Key('roomId').eq(room_id)
    )
    
    api_gateway = boto3.client('apigatewaymanagementapi',
        endpoint_url=f'https://{domain_name}/{stage}')
    
    message_data = json.dumps(message)
    stale_connections = []
    
    for connection in response['Items']:
        try:
            api_gateway.post_to_connection(
                ConnectionId=connection['connectionId'],
                Data=message_data
            )
        except ClientError as e:
            if e.response['Error']['Code'] == 'GoneException':
                stale_connections.append(connection['connectionId'])
    
    # Clean up stale connections
    for connection_id in stale_connections:
        connections_table.delete_item(Key={'connectionId': connection_id})

def send_error(connection_id, domain_name, stage, error_message):
    api_gateway = boto3.client('apigatewaymanagementapi',
        endpoint_url=f'https://{domain_name}/{stage}')
    
    error_response = {
        'type': 'error',
        'data': {
            'message': error_message,
            'timestamp': int(time.time())
        }
    }
    
    try:
        api_gateway.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(error_response)
        )
    except ClientError:
        pass  # Connection might be gone
    
    return {'statusCode': 400}
EOF
    
    if [ "$DRY_RUN" != "true" ]; then
        zip message_handler.zip message_handler.py
    fi
    
    execute_cmd "aws lambda create-function \
        --function-name websocket-message-${RANDOM_SUFFIX} \
        --runtime python3.9 \
        --role ${LAMBDA_ROLE_ARN} \
        --handler message_handler.lambda_handler \
        --zip-file fileb://message_handler.zip \
        --description 'WebSocket message handler' \
        --timeout 60 \
        --memory-size 512 \
        --environment Variables='{
            \"CONNECTIONS_TABLE\": \"'${CONNECTIONS_TABLE}'\",
            \"ROOMS_TABLE\": \"'${ROOMS_TABLE}'\",
            \"MESSAGES_TABLE\": \"'${MESSAGES_TABLE}'\"
        }' \
        --region ${AWS_REGION}" "Creating message handler function"
    
    # Store function ARNs for later use
    if [ "$DRY_RUN" != "true" ]; then
        export CONNECT_FUNCTION_ARN=$(aws lambda get-function \
            --function-name websocket-connect-${RANDOM_SUFFIX} \
            --query Configuration.FunctionArn --output text --region ${AWS_REGION})
        
        export DISCONNECT_FUNCTION_ARN=$(aws lambda get-function \
            --function-name websocket-disconnect-${RANDOM_SUFFIX} \
            --query Configuration.FunctionArn --output text --region ${AWS_REGION})
        
        export MESSAGE_FUNCTION_ARN=$(aws lambda get-function \
            --function-name websocket-message-${RANDOM_SUFFIX} \
            --query Configuration.FunctionArn --output text --region ${AWS_REGION})
        
        # Add to deployment info
        echo "CONNECT_FUNCTION_ARN=${CONNECT_FUNCTION_ARN}" >> deployment-info.txt
        echo "DISCONNECT_FUNCTION_ARN=${DISCONNECT_FUNCTION_ARN}" >> deployment-info.txt
        echo "MESSAGE_FUNCTION_ARN=${MESSAGE_FUNCTION_ARN}" >> deployment-info.txt
    fi
    
    log "Lambda functions created successfully"
}

# Function to create WebSocket API Gateway
create_websocket_api() {
    log "Creating WebSocket API Gateway..."
    
    # Create WebSocket API
    if [ "$DRY_RUN" != "true" ]; then
        export API_ID=$(aws apigatewayv2 create-api \
            --name ${API_NAME} \
            --protocol-type WEBSOCKET \
            --route-selection-expression '$request.body.type' \
            --description "Advanced WebSocket API with route management" \
            --query ApiId --output text --region ${AWS_REGION})
        
        echo "API_ID=${API_ID}" >> deployment-info.txt
    else
        export API_ID="dry-run-api-id"
    fi
    
    info "WebSocket API created with ID: ${API_ID}"
    
    # Create integrations
    if [ "$DRY_RUN" != "true" ]; then
        export CONNECT_INTEGRATION_ID=$(aws apigatewayv2 create-integration \
            --api-id ${API_ID} \
            --integration-type AWS_PROXY \
            --integration-uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${CONNECT_FUNCTION_ARN}/invocations" \
            --query IntegrationId --output text --region ${AWS_REGION})
        
        export DISCONNECT_INTEGRATION_ID=$(aws apigatewayv2 create-integration \
            --api-id ${API_ID} \
            --integration-type AWS_PROXY \
            --integration-uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${DISCONNECT_FUNCTION_ARN}/invocations" \
            --query IntegrationId --output text --region ${AWS_REGION})
        
        export MESSAGE_INTEGRATION_ID=$(aws apigatewayv2 create-integration \
            --api-id ${API_ID} \
            --integration-type AWS_PROXY \
            --integration-uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${MESSAGE_FUNCTION_ARN}/invocations" \
            --query IntegrationId --output text --region ${AWS_REGION})
    fi
    
    log "WebSocket API integrations created"
}

# Function to create routes
create_routes() {
    log "Creating WebSocket routes..."
    
    # Create $connect route
    execute_cmd "aws apigatewayv2 create-route \
        --api-id ${API_ID} \
        --route-key '\$connect' \
        --target 'integrations/${CONNECT_INTEGRATION_ID}' \
        --region ${AWS_REGION}" "Creating \$connect route"
    
    # Create $disconnect route
    execute_cmd "aws apigatewayv2 create-route \
        --api-id ${API_ID} \
        --route-key '\$disconnect' \
        --target 'integrations/${DISCONNECT_INTEGRATION_ID}' \
        --region ${AWS_REGION}" "Creating \$disconnect route"
    
    # Create $default route
    execute_cmd "aws apigatewayv2 create-route \
        --api-id ${API_ID} \
        --route-key '\$default' \
        --target 'integrations/${MESSAGE_INTEGRATION_ID}' \
        --region ${AWS_REGION}" "Creating \$default route"
    
    # Create custom routes
    execute_cmd "aws apigatewayv2 create-route \
        --api-id ${API_ID} \
        --route-key 'chat' \
        --target 'integrations/${MESSAGE_INTEGRATION_ID}' \
        --region ${AWS_REGION}" "Creating chat route"
    
    log "WebSocket routes created successfully"
}

# Function to grant permissions and deploy API
deploy_api() {
    log "Granting permissions and deploying API..."
    
    # Grant API Gateway permission to invoke Lambda functions
    execute_cmd "aws lambda add-permission \
        --function-name websocket-connect-${RANDOM_SUFFIX} \
        --statement-id websocket-connect-permission-${RANDOM_SUFFIX} \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn 'arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*' \
        --region ${AWS_REGION}" "Granting connect function permissions"
    
    execute_cmd "aws lambda add-permission \
        --function-name websocket-disconnect-${RANDOM_SUFFIX} \
        --statement-id websocket-disconnect-permission-${RANDOM_SUFFIX} \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn 'arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*' \
        --region ${AWS_REGION}" "Granting disconnect function permissions"
    
    execute_cmd "aws lambda add-permission \
        --function-name websocket-message-${RANDOM_SUFFIX} \
        --statement-id websocket-message-permission-${RANDOM_SUFFIX} \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn 'arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*' \
        --region ${AWS_REGION}" "Granting message function permissions"
    
    # Deploy API to staging stage
    if [ "$DRY_RUN" != "true" ]; then
        export DEPLOYMENT_ID=$(aws apigatewayv2 create-deployment \
            --api-id ${API_ID} \
            --stage-name staging \
            --description "Initial deployment of WebSocket API" \
            --query DeploymentId --output text --region ${AWS_REGION})
        
        # Create staging stage with logging enabled
        aws apigatewayv2 create-stage \
            --api-id ${API_ID} \
            --stage-name staging \
            --deployment-id ${DEPLOYMENT_ID} \
            --description "Staging environment for WebSocket API" \
            --default-route-settings '{
                "DetailedMetricsEnabled": true,
                "LoggingLevel": "INFO",
                "DataTraceEnabled": true,
                "ThrottlingBurstLimit": 500,
                "ThrottlingRateLimit": 1000
            }' \
            --region ${AWS_REGION}
        
        export WEBSOCKET_ENDPOINT="wss://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/staging"
        
        # Add to deployment info
        echo "DEPLOYMENT_ID=${DEPLOYMENT_ID}" >> deployment-info.txt
        echo "WEBSOCKET_ENDPOINT=${WEBSOCKET_ENDPOINT}" >> deployment-info.txt
    fi
    
    log "WebSocket API deployed successfully"
}

# Function to create test client
create_test_client() {
    log "Creating WebSocket test client..."
    
    cat > websocket_client.py << 'EOF'
import asyncio
import websockets
import json
import sys

class WebSocketClient:
    def __init__(self, uri, user_id, username, room_id="general"):
        self.uri = f"{uri}?userId={user_id}&username={username}&roomId={room_id}&token=valid_test_token"
        self.user_id = user_id
        self.username = username
        self.room_id = room_id
        self.websocket = None
    
    async def connect(self):
        try:
            self.websocket = await websockets.connect(self.uri)
            print(f"Connected as {self.username} ({self.user_id}) to room {self.room_id}")
            return True
        except Exception as e:
            print(f"Connection failed: {e}")
            return False
    
    async def listen(self):
        try:
            async for message in self.websocket:
                data = json.loads(message)
                await self.handle_message(data)
        except websockets.exceptions.ConnectionClosed:
            print("Connection closed")
        except Exception as e:
            print(f"Error listening: {e}")
    
    async def handle_message(self, data):
        message_type = data.get('type')
        payload = data.get('data', {})
        
        if message_type == 'welcome':
            print(f"✅ {payload.get('message')}")
        elif message_type == 'chat':
            sender = payload.get('senderName', payload.get('senderId'))
            message = payload.get('message')
            print(f"💬 {sender}: {message}")
        elif message_type == 'error':
            print(f"❌ Error: {payload.get('message')}")
        else:
            print(f"📨 {message_type}: {payload}")
    
    async def send_message(self, message_type, data):
        if self.websocket:
            message = json.dumps({
                'type': message_type,
                **data
            })
            await self.websocket.send(message)
    
    async def chat(self, message, room_id=None):
        await self.send_message('chat', {
            'message': message,
            'roomId': room_id or self.room_id
        })
    
    async def disconnect(self):
        if self.websocket:
            await self.websocket.close()

async def interactive_client(websocket_uri):
    user_id = input("Enter user ID: ") or "testuser"
    username = input("Enter username: ") or "TestUser"
    room_id = input("Enter room ID (default: general): ") or "general"
    
    client = WebSocketClient(websocket_uri, user_id, username, room_id)
    
    if not await client.connect():
        return
    
    # Start listening in background
    listen_task = asyncio.create_task(client.listen())
    
    print("\nCommands:")
    print("  /chat <message>    - Send chat message")
    print("  /quit             - Disconnect")
    print()
    
    try:
        while True:
            command = input("> ")
            
            if command.startswith('/chat '):
                message = command[6:]
                await client.chat(message)
            elif command == '/quit':
                break
            else:
                print("Unknown command")
    
    except KeyboardInterrupt:
        pass
    finally:
        listen_task.cancel()
        await client.disconnect()
        print("Disconnected")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python websocket_client.py <websocket_uri>")
        sys.exit(1)
    
    websocket_uri = sys.argv[1]
    asyncio.run(interactive_client(websocket_uri))
EOF
    
    log "WebSocket test client created"
}

# Function to display deployment summary
show_deployment_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Deployment ID: ${RANDOM_SUFFIX}"
    echo "AWS Region: ${AWS_REGION}"
    echo "AWS Account: ${AWS_ACCOUNT_ID}"
    echo ""
    echo "Resources Created:"
    echo "- DynamoDB Tables:"
    echo "  - ${CONNECTIONS_TABLE}"
    echo "  - ${ROOMS_TABLE}"
    echo "  - ${MESSAGES_TABLE}"
    echo "- Lambda Functions:"
    echo "  - websocket-connect-${RANDOM_SUFFIX}"
    echo "  - websocket-disconnect-${RANDOM_SUFFIX}"
    echo "  - websocket-message-${RANDOM_SUFFIX}"
    echo "- API Gateway:"
    echo "  - ${API_NAME}"
    echo "  - API ID: ${API_ID}"
    
    if [ "$DRY_RUN" != "true" ]; then
        echo "  - WebSocket Endpoint: ${WEBSOCKET_ENDPOINT}"
        echo ""
        echo "Next Steps:"
        echo "1. Test the WebSocket API:"
        echo "   python3 websocket_client.py ${WEBSOCKET_ENDPOINT}"
        echo ""
        echo "2. Monitor the deployment:"
        echo "   aws logs tail /aws/lambda/websocket-connect-${RANDOM_SUFFIX} --follow"
        echo ""
        echo "3. View API Gateway logs:"
        echo "   aws logs describe-log-groups --log-group-name-prefix /aws/apigateway/${API_ID}"
    fi
    
    echo ""
    echo "Deployment info saved to: deployment-info.txt"
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting WebSocket API deployment..."
    
    # Check if deployment info exists (prevent duplicate deployments)
    if [ -f "deployment-info.txt" ] && [ "$DRY_RUN" != "true" ]; then
        warn "Deployment info file exists. Resources may already be deployed."
        echo "To force redeploy, remove deployment-info.txt file."
        echo "To clean up existing resources, run: ./destroy.sh"
        exit 1
    fi
    
    check_prerequisites
    setup_environment
    create_dynamodb_tables
    create_iam_resources
    create_lambda_functions
    create_websocket_api
    create_routes
    deploy_api
    create_test_client
    show_deployment_summary
    
    log "WebSocket API deployment completed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted. Resources may be in inconsistent state. Run ./destroy.sh to clean up."; exit 1' INT

# Run main function
main "$@"