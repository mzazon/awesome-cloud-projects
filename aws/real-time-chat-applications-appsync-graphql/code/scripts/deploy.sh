#!/bin/bash

# Real-Time Chat Applications with AppSync and GraphQL - Deployment Script
# This script deploys the complete infrastructure for a serverless chat application
# using AWS AppSync, DynamoDB, Cognito, and Lambda

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
    
    # Check jq for JSON parsing (optional but helpful)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. JSON output will be less readable"
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "No region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
        --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        openssl rand -hex 4)
    
    export CHAT_APP_NAME="realtime-chat-${RANDOM_SUFFIX}"
    export APPSYNC_API_NAME="${CHAT_APP_NAME}-api"
    export COGNITO_USER_POOL_NAME="${CHAT_APP_NAME}-users"
    export DYNAMODB_MESSAGES_TABLE="${CHAT_APP_NAME}-messages"
    export DYNAMODB_CONVERSATIONS_TABLE="${CHAT_APP_NAME}-conversations"
    export DYNAMODB_USERS_TABLE="${CHAT_APP_NAME}-users"
    
    log_success "Environment prepared with suffix: ${RANDOM_SUFFIX}"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "App Name: $CHAT_APP_NAME"
}

# Create Cognito User Pool
create_cognito_user_pool() {
    log "Creating Cognito User Pool..."
    
    USER_POOL_ID=$(aws cognito-idp create-user-pool \
        --pool-name "${COGNITO_USER_POOL_NAME}" \
        --policies "PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=false}" \
        --auto-verified-attributes email \
        --username-attributes email \
        --schema "Name=email,AttributeDataType=String,Required=true,Mutable=true" \
        --query 'UserPool.Id' --output text)
    
    if [ $? -eq 0 ]; then
        log_success "Created Cognito User Pool: ${USER_POOL_ID}"
        echo "USER_POOL_ID=${USER_POOL_ID}" >> /tmp/chat-app-resources.env
    else
        log_error "Failed to create Cognito User Pool"
        exit 1
    fi
    
    # Create User Pool Client
    USER_POOL_CLIENT_ID=$(aws cognito-idp create-user-pool-client \
        --user-pool-id "${USER_POOL_ID}" \
        --client-name "${CHAT_APP_NAME}-client" \
        --explicit-auth-flows "ALLOW_USER_PASSWORD_AUTH" "ALLOW_REFRESH_TOKEN_AUTH" \
        --generate-secret \
        --query 'UserPoolClient.ClientId' --output text)
    
    if [ $? -eq 0 ]; then
        log_success "Created User Pool Client: ${USER_POOL_CLIENT_ID}"
        echo "USER_POOL_CLIENT_ID=${USER_POOL_CLIENT_ID}" >> /tmp/chat-app-resources.env
    else
        log_error "Failed to create User Pool Client"
        exit 1
    fi
}

# Create DynamoDB tables
create_dynamodb_tables() {
    log "Creating DynamoDB tables..."
    
    # Create Messages table
    log "Creating Messages table..."
    aws dynamodb create-table \
        --table-name "${DYNAMODB_MESSAGES_TABLE}" \
        --attribute-definitions \
            AttributeName=conversationId,AttributeType=S \
            AttributeName=messageId,AttributeType=S \
            AttributeName=createdAt,AttributeType=S \
        --key-schema \
            AttributeName=conversationId,KeyType=HASH \
            AttributeName=messageId,KeyType=RANGE \
        --global-secondary-indexes \
            IndexName=MessagesByTime,KeySchema=[{AttributeName=conversationId,KeyType=HASH},{AttributeName=createdAt,KeyType=RANGE}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5} \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
        > /dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Created Messages table: ${DYNAMODB_MESSAGES_TABLE}"
        echo "DYNAMODB_MESSAGES_TABLE=${DYNAMODB_MESSAGES_TABLE}" >> /tmp/chat-app-resources.env
    else
        log_error "Failed to create Messages table"
        exit 1
    fi
    
    # Create Conversations table
    log "Creating Conversations table..."
    aws dynamodb create-table \
        --table-name "${DYNAMODB_CONVERSATIONS_TABLE}" \
        --attribute-definitions \
            AttributeName=conversationId,AttributeType=S \
            AttributeName=userId,AttributeType=S \
        --key-schema \
            AttributeName=conversationId,KeyType=HASH \
        --global-secondary-indexes \
            IndexName=UserConversations,KeySchema=[{AttributeName=userId,KeyType=HASH},{AttributeName=conversationId,KeyType=RANGE}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5} \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        > /dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Created Conversations table: ${DYNAMODB_CONVERSATIONS_TABLE}"
        echo "DYNAMODB_CONVERSATIONS_TABLE=${DYNAMODB_CONVERSATIONS_TABLE}" >> /tmp/chat-app-resources.env
    else
        log_error "Failed to create Conversations table"
        exit 1
    fi
    
    # Create Users table
    log "Creating Users table..."
    aws dynamodb create-table \
        --table-name "${DYNAMODB_USERS_TABLE}" \
        --attribute-definitions \
            AttributeName=userId,AttributeType=S \
        --key-schema \
            AttributeName=userId,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        > /dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Created Users table: ${DYNAMODB_USERS_TABLE}"
        echo "DYNAMODB_USERS_TABLE=${DYNAMODB_USERS_TABLE}" >> /tmp/chat-app-resources.env
    else
        log_error "Failed to create Users table"
        exit 1
    fi
    
    # Wait for tables to become active
    log "Waiting for DynamoDB tables to become active..."
    aws dynamodb wait table-exists --table-name "${DYNAMODB_MESSAGES_TABLE}"
    aws dynamodb wait table-exists --table-name "${DYNAMODB_CONVERSATIONS_TABLE}"
    aws dynamodb wait table-exists --table-name "${DYNAMODB_USERS_TABLE}"
    
    log_success "All DynamoDB tables are now active"
}

# Create IAM role for AppSync
create_appsync_iam_role() {
    log "Creating IAM role for AppSync..."
    
    # Create trust policy for AppSync
    cat > /tmp/appsync-trust-policy.json << EOF
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
    
    # Create AppSync service role
    APPSYNC_ROLE_ARN=$(aws iam create-role \
        --role-name "${CHAT_APP_NAME}-appsync-role" \
        --assume-role-policy-document file:///tmp/appsync-trust-policy.json \
        --query 'Role.Arn' --output text)
    
    if [ $? -eq 0 ]; then
        log_success "Created AppSync IAM role: ${APPSYNC_ROLE_ARN}"
        echo "APPSYNC_ROLE_ARN=${APPSYNC_ROLE_ARN}" >> /tmp/chat-app-resources.env
    else
        log_error "Failed to create AppSync IAM role"
        exit 1
    fi
    
    # Create policy for DynamoDB access
    cat > /tmp/appsync-dynamodb-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:Query",
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:BatchGetItem",
                "dynamodb:Scan"
            ],
            "Resource": [
                "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DYNAMODB_MESSAGES_TABLE}*",
                "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DYNAMODB_CONVERSATIONS_TABLE}*",
                "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DYNAMODB_USERS_TABLE}*"
            ]
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "${CHAT_APP_NAME}-appsync-role" \
        --policy-name "DynamoDBAccess" \
        --policy-document file:///tmp/appsync-dynamodb-policy.json
    
    if [ $? -eq 0 ]; then
        log_success "Attached DynamoDB policy to AppSync role"
    else
        log_error "Failed to attach DynamoDB policy to AppSync role"
        exit 1
    fi
    
    # Wait a moment for IAM role propagation
    sleep 10
}

# Create GraphQL schema
create_graphql_schema() {
    log "Creating GraphQL schema..."
    
    cat > /tmp/chat-schema.graphql << 'EOF'
type Message {
    messageId: ID!
    conversationId: ID!
    userId: ID!
    content: String!
    messageType: MessageType!
    createdAt: AWSDateTime!
    updatedAt: AWSDateTime
    author: User
}

type Conversation {
    conversationId: ID!
    name: String
    participants: [ID!]!
    lastMessageAt: AWSDateTime
    lastMessage: String
    createdAt: AWSDateTime!
    updatedAt: AWSDateTime
    createdBy: ID!
    messageCount: Int
}

type User {
    userId: ID!
    username: String!
    email: AWSEmail!
    displayName: String
    avatarUrl: String
    lastSeen: AWSDateTime
    isOnline: Boolean
    createdAt: AWSDateTime!
    updatedAt: AWSDateTime
}

enum MessageType {
    TEXT
    IMAGE
    FILE
    SYSTEM
}

type Query {
    getMessage(conversationId: ID!, messageId: ID!): Message
    getConversation(conversationId: ID!): Conversation
    getUser(userId: ID!): User
    listMessages(conversationId: ID!, limit: Int, nextToken: String): MessageConnection
    listConversations(userId: ID!, limit: Int, nextToken: String): ConversationConnection
    searchMessages(conversationId: ID!, searchTerm: String!, limit: Int): [Message]
}

type Mutation {
    sendMessage(input: SendMessageInput!): Message
    createConversation(input: CreateConversationInput!): Conversation
    updateConversation(input: UpdateConversationInput!): Conversation
    deleteMessage(conversationId: ID!, messageId: ID!): Message
    updateUserPresence(userId: ID!, isOnline: Boolean!): User
    updateUserProfile(input: UpdateUserProfileInput!): User
}

type Subscription {
    onMessageSent(conversationId: ID!): Message
        @aws_subscribe(mutations: ["sendMessage"])
    onConversationUpdated(userId: ID!): Conversation
        @aws_subscribe(mutations: ["createConversation", "updateConversation"])
    onUserPresenceUpdated(conversationId: ID!): User
        @aws_subscribe(mutations: ["updateUserPresence"])
}

input SendMessageInput {
    conversationId: ID!
    content: String!
    messageType: MessageType = TEXT
}

input CreateConversationInput {
    name: String
    participants: [ID!]!
}

input UpdateConversationInput {
    conversationId: ID!
    name: String
}

input UpdateUserProfileInput {
    userId: ID!
    displayName: String
    avatarUrl: String
}

type MessageConnection {
    items: [Message]
    nextToken: String
}

type ConversationConnection {
    items: [Conversation]
    nextToken: String
}

schema {
    query: Query
    mutation: Mutation
    subscription: Subscription
}
EOF
    
    log_success "Created GraphQL schema file"
}

# Create AppSync API
create_appsync_api() {
    log "Creating AppSync API..."
    
    API_ID=$(aws appsync create-graphql-api \
        --name "${APPSYNC_API_NAME}" \
        --authentication-type AMAZON_COGNITO_USER_POOLS \
        --user-pool-config "userPoolId=${USER_POOL_ID},awsRegion=${AWS_REGION},defaultAction=ALLOW" \
        --query 'graphqlApi.apiId' --output text)
    
    if [ $? -eq 0 ]; then
        log_success "Created AppSync API: ${API_ID}"
        echo "API_ID=${API_ID}" >> /tmp/chat-app-resources.env
    else
        log_error "Failed to create AppSync API"
        exit 1
    fi
    
    # Get API details
    API_URL=$(aws appsync get-graphql-api \
        --api-id "${API_ID}" \
        --query 'graphqlApi.uris.GRAPHQL' --output text)
    
    REALTIME_URL=$(aws appsync get-graphql-api \
        --api-id "${API_ID}" \
        --query 'graphqlApi.uris.REALTIME' --output text)
    
    echo "API_URL=${API_URL}" >> /tmp/chat-app-resources.env
    echo "REALTIME_URL=${REALTIME_URL}" >> /tmp/chat-app-resources.env
    
    log "GraphQL URL: ${API_URL}"
    log "Real-time URL: ${REALTIME_URL}"
    
    # Upload schema
    aws appsync start-schema-creation \
        --api-id "${API_ID}" \
        --definition file:///tmp/chat-schema.graphql > /dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Uploaded GraphQL schema"
    else
        log_error "Failed to upload GraphQL schema"
        exit 1
    fi
    
    # Wait for schema creation to complete
    log "Waiting for schema creation to complete..."
    sleep 15
}

# Create DynamoDB data sources
create_data_sources() {
    log "Creating DynamoDB data sources..."
    
    # Create Messages table data source
    MESSAGES_DS_NAME=$(aws appsync create-data-source \
        --api-id "${API_ID}" \
        --name "MessagesTable" \
        --type "AMAZON_DYNAMODB" \
        --service-role-arn "${APPSYNC_ROLE_ARN}" \
        --dynamodb-config "tableName=${DYNAMODB_MESSAGES_TABLE},awsRegion=${AWS_REGION}" \
        --query 'dataSource.name' --output text)
    
    if [ $? -eq 0 ]; then
        log_success "Created Messages table data source: ${MESSAGES_DS_NAME}"
        echo "MESSAGES_DS_NAME=${MESSAGES_DS_NAME}" >> /tmp/chat-app-resources.env
    else
        log_error "Failed to create Messages table data source"
        exit 1
    fi
    
    # Create Conversations table data source
    CONVERSATIONS_DS_NAME=$(aws appsync create-data-source \
        --api-id "${API_ID}" \
        --name "ConversationsTable" \
        --type "AMAZON_DYNAMODB" \
        --service-role-arn "${APPSYNC_ROLE_ARN}" \
        --dynamodb-config "tableName=${DYNAMODB_CONVERSATIONS_TABLE},awsRegion=${AWS_REGION}" \
        --query 'dataSource.name' --output text)
    
    if [ $? -eq 0 ]; then
        log_success "Created Conversations table data source: ${CONVERSATIONS_DS_NAME}"
        echo "CONVERSATIONS_DS_NAME=${CONVERSATIONS_DS_NAME}" >> /tmp/chat-app-resources.env
    else
        log_error "Failed to create Conversations table data source"
        exit 1
    fi
    
    # Create Users table data source
    USERS_DS_NAME=$(aws appsync create-data-source \
        --api-id "${API_ID}" \
        --name "UsersTable" \
        --type "AMAZON_DYNAMODB" \
        --service-role-arn "${APPSYNC_ROLE_ARN}" \
        --dynamodb-config "tableName=${DYNAMODB_USERS_TABLE},awsRegion=${AWS_REGION}" \
        --query 'dataSource.name' --output text)
    
    if [ $? -eq 0 ]; then
        log_success "Created Users table data source: ${USERS_DS_NAME}"
        echo "USERS_DS_NAME=${USERS_DS_NAME}" >> /tmp/chat-app-resources.env
    else
        log_error "Failed to create Users table data source"
        exit 1
    fi
}

# Create VTL resolvers
create_resolvers() {
    log "Creating VTL resolvers..."
    
    # Create sendMessage mutation resolver
    cat > /tmp/send-message-request.vtl << 'EOF'
{
    "version": "2017-02-28",
    "operation": "PutItem",
    "key": {
        "conversationId": $util.dynamodb.toDynamoDBJson($ctx.args.input.conversationId),
        "messageId": $util.dynamodb.toDynamoDBJson($util.autoId())
    },
    "attributeValues": {
        "userId": $util.dynamodb.toDynamoDBJson($ctx.identity.sub),
        "content": $util.dynamodb.toDynamoDBJson($ctx.args.input.content),
        "messageType": $util.dynamodb.toDynamoDBJson($ctx.args.input.messageType),
        "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
        "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
    }
}
EOF
    
    cat > /tmp/send-message-response.vtl << 'EOF'
$util.toJson($ctx.result)
EOF
    
    # Create sendMessage resolver
    aws appsync create-resolver \
        --api-id "${API_ID}" \
        --type-name "Mutation" \
        --field-name "sendMessage" \
        --data-source-name "${MESSAGES_DS_NAME}" \
        --request-mapping-template file:///tmp/send-message-request.vtl \
        --response-mapping-template file:///tmp/send-message-response.vtl > /dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Created sendMessage resolver"
    else
        log_error "Failed to create sendMessage resolver"
        exit 1
    fi
    
    # Create listMessages query resolver
    cat > /tmp/list-messages-request.vtl << 'EOF'
{
    "version": "2017-02-28",
    "operation": "Query",
    "index": "MessagesByTime",
    "query": {
        "expression": "conversationId = :conversationId",
        "expressionValues": {
            ":conversationId": $util.dynamodb.toDynamoDBJson($ctx.args.conversationId)
        }
    },
    "scanIndexForward": false,
    "limit": #if($ctx.args.limit) $ctx.args.limit #else 50 #end
    #if($ctx.args.nextToken)
    ,"nextToken": "$ctx.args.nextToken"
    #end
}
EOF
    
    cat > /tmp/list-messages-response.vtl << 'EOF'
{
    "items": $util.toJson($ctx.result.items),
    "nextToken": #if($ctx.result.nextToken) "$ctx.result.nextToken" #else null #end
}
EOF
    
    # Create listMessages resolver
    aws appsync create-resolver \
        --api-id "${API_ID}" \
        --type-name "Query" \
        --field-name "listMessages" \
        --data-source-name "${MESSAGES_DS_NAME}" \
        --request-mapping-template file:///tmp/list-messages-request.vtl \
        --response-mapping-template file:///tmp/list-messages-response.vtl > /dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Created listMessages resolver"
    else
        log_error "Failed to create listMessages resolver"
        exit 1
    fi
    
    # Create createConversation mutation resolver
    cat > /tmp/create-conversation-request.vtl << 'EOF'
{
    "version": "2017-02-28",
    "operation": "PutItem",
    "key": {
        "conversationId": $util.dynamodb.toDynamoDBJson($util.autoId())
    },
    "attributeValues": {
        "name": $util.dynamodb.toDynamoDBJson($ctx.args.input.name),
        "participants": $util.dynamodb.toDynamoDBJson($ctx.args.input.participants),
        "createdBy": $util.dynamodb.toDynamoDBJson($ctx.identity.sub),
        "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
        "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
        "messageCount": $util.dynamodb.toDynamoDBJson(0)
    }
}
EOF
    
    cat > /tmp/create-conversation-response.vtl << 'EOF'
$util.toJson($ctx.result)
EOF
    
    # Create createConversation resolver
    aws appsync create-resolver \
        --api-id "${API_ID}" \
        --type-name "Mutation" \
        --field-name "createConversation" \
        --data-source-name "${CONVERSATIONS_DS_NAME}" \
        --request-mapping-template file:///tmp/create-conversation-request.vtl \
        --response-mapping-template file:///tmp/create-conversation-response.vtl > /dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Created createConversation resolver"
    else
        log_error "Failed to create createConversation resolver"
        exit 1
    fi
    
    # Create updateUserPresence mutation resolver
    cat > /tmp/update-user-presence-request.vtl << 'EOF'
{
    "version": "2017-02-28",
    "operation": "UpdateItem",
    "key": {
        "userId": $util.dynamodb.toDynamoDBJson($ctx.args.userId)
    },
    "update": {
        "expression": "SET isOnline = :isOnline, lastSeen = :lastSeen, updatedAt = :updatedAt",
        "expressionValues": {
            ":isOnline": $util.dynamodb.toDynamoDBJson($ctx.args.isOnline),
            ":lastSeen": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
            ":updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
        }
    }
}
EOF
    
    cat > /tmp/update-user-presence-response.vtl << 'EOF'
$util.toJson($ctx.result)
EOF
    
    # Create updateUserPresence resolver
    aws appsync create-resolver \
        --api-id "${API_ID}" \
        --type-name "Mutation" \
        --field-name "updateUserPresence" \
        --data-source-name "${USERS_DS_NAME}" \
        --request-mapping-template file:///tmp/update-user-presence-request.vtl \
        --response-mapping-template file:///tmp/update-user-presence-response.vtl > /dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Created updateUserPresence resolver"
    else
        log_error "Failed to create updateUserPresence resolver"
        exit 1
    fi
}

# Create test users
create_test_users() {
    log "Creating test users..."
    
    # Create test user 1
    aws cognito-idp admin-create-user \
        --user-pool-id "${USER_POOL_ID}" \
        --username "testuser1" \
        --user-attributes Name=email,Value=testuser1@example.com \
        --temporary-password "TempPassword123!" \
        --message-action SUPPRESS > /dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Created test user 1: testuser1@example.com"
    else
        log_warning "Failed to create test user 1 (may already exist)"
    fi
    
    # Create test user 2
    aws cognito-idp admin-create-user \
        --user-pool-id "${USER_POOL_ID}" \
        --username "testuser2" \
        --user-attributes Name=email,Value=testuser2@example.com \
        --temporary-password "TempPassword123!" \
        --message-action SUPPRESS > /dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Created test user 2: testuser2@example.com"
    else
        log_warning "Failed to create test user 2 (may already exist)"
    fi
    
    # Set permanent passwords
    aws cognito-idp admin-set-user-password \
        --user-pool-id "${USER_POOL_ID}" \
        --username "testuser1" \
        --password "TestPassword123!" \
        --permanent > /dev/null
    
    aws cognito-idp admin-set-user-password \
        --user-pool-id "${USER_POOL_ID}" \
        --username "testuser2" \
        --password "TestPassword123!" \
        --permanent > /dev/null
    
    log_success "Set permanent passwords for test users"
    log "Test user credentials:"
    log "  User 1: testuser1@example.com / TestPassword123!"
    log "  User 2: testuser2@example.com / TestPassword123!"
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f /tmp/chat-schema.graphql \
          /tmp/appsync-trust-policy.json \
          /tmp/appsync-dynamodb-policy.json \
          /tmp/send-message-*.vtl \
          /tmp/list-messages-*.vtl \
          /tmp/create-conversation-*.vtl \
          /tmp/update-user-presence-*.vtl
    
    log_success "Cleaned up temporary files"
}

# Display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "======================================"
    echo "REAL-TIME CHAT APPLICATION DEPLOYED"
    echo "======================================"
    echo ""
    echo "Resource Summary:"
    echo "  App Name: ${CHAT_APP_NAME}"
    echo "  AWS Region: ${AWS_REGION}"
    echo "  AppSync API ID: ${API_ID}"
    echo "  User Pool ID: ${USER_POOL_ID}"
    echo "  User Pool Client ID: ${USER_POOL_CLIENT_ID}"
    echo ""
    echo "API Endpoints:"
    echo "  GraphQL URL: ${API_URL}"
    echo "  Real-time URL: ${REALTIME_URL}"
    echo ""
    echo "DynamoDB Tables:"
    echo "  Messages: ${DYNAMODB_MESSAGES_TABLE}"
    echo "  Conversations: ${DYNAMODB_CONVERSATIONS_TABLE}"
    echo "  Users: ${DYNAMODB_USERS_TABLE}"
    echo ""
    echo "Test Users:"
    echo "  testuser1@example.com / TestPassword123!"
    echo "  testuser2@example.com / TestPassword123!"
    echo ""
    echo "Resource configuration saved to: /tmp/chat-app-resources.env"
    echo ""
    echo "Next Steps:"
    echo "1. Use the GraphQL endpoint to build your client application"
    echo "2. Authenticate users with Cognito credentials"
    echo "3. Test real-time subscriptions with the WebSocket endpoint"
    echo "4. Monitor usage and costs in the AWS Console"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo ""
}

# Main deployment function
main() {
    log "Starting Real-Time Chat Application deployment..."
    
    # Initialize resource tracking file
    echo "# Real-Time Chat Application Resources" > /tmp/chat-app-resources.env
    echo "# Generated on $(date)" >> /tmp/chat-app-resources.env
    echo "CHAT_APP_NAME=${CHAT_APP_NAME}" >> /tmp/chat-app-resources.env
    echo "AWS_REGION=${AWS_REGION}" >> /tmp/chat-app-resources.env
    echo "AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}" >> /tmp/chat-app-resources.env
    
    check_prerequisites
    setup_environment
    create_cognito_user_pool
    create_dynamodb_tables
    create_appsync_iam_role
    create_graphql_schema
    create_appsync_api
    create_data_sources
    create_resolvers
    create_test_users
    cleanup_temp_files
    display_summary
}

# Run main function
main "$@"