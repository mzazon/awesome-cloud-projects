#!/bin/bash

# AWS AppSync GraphQL API Deployment Script
# This script deploys a complete GraphQL API using AWS AppSync with DynamoDB and Cognito
# Based on the recipe: Real-Time GraphQL API with AppSync

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    log "Running in dry-run mode - no resources will be created"
fi

# Function to execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Would execute: $cmd${NC}"
        if [[ -n "$description" ]]; then
            echo -e "${YELLOW}[DRY-RUN] Description: $description${NC}"
        fi
        return 0
    else
        log "$description"
        eval "$cmd"
    fi
}

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
    
    # Check if required tools are available
    local required_tools=("jq" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warn "No region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique names to avoid conflicts
    local random_string
    if [[ "$DRY_RUN" == "true" ]]; then
        random_string="dryrun"
    else
        random_string=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    fi
    
    export API_NAME="blog-api-${random_string}"
    export TABLE_NAME="BlogPosts-${random_string}"
    export USER_POOL_NAME="BlogUserPool-${random_string}"
    export STACK_NAME="appsync-blog-${random_string}"
    
    # Create a deployment configuration file
    cat > .deployment-config << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
API_NAME=$API_NAME
TABLE_NAME=$TABLE_NAME
USER_POOL_NAME=$USER_POOL_NAME
STACK_NAME=$STACK_NAME
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    success "Environment variables configured"
    log "API Name: $API_NAME"
    log "Table Name: $TABLE_NAME"
    log "User Pool: $USER_POOL_NAME"
    log "Region: $AWS_REGION"
}

# Create Cognito User Pool
create_cognito_user_pool() {
    log "Creating Cognito User Pool..."
    
    local create_pool_cmd="aws cognito-idp create-user-pool \
        --pool-name $USER_POOL_NAME \
        --policies 'PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=false}' \
        --auto-verified-attributes email \
        --username-attributes email \
        --query 'UserPool.Id' --output text"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        execute_cmd "$create_pool_cmd" "Create Cognito User Pool"
        export USER_POOL_ID="us-east-1_DRYRUN123"
    else
        export USER_POOL_ID=$(eval "$create_pool_cmd")
        echo "USER_POOL_ID=$USER_POOL_ID" >> .deployment-config
    fi
    
    # Create User Pool Client
    local create_client_cmd="aws cognito-idp create-user-pool-client \
        --user-pool-id $USER_POOL_ID \
        --client-name '${API_NAME}-client' \
        --generate-secret \
        --explicit-auth-flows ADMIN_NO_SRP_AUTH \
        --query 'UserPoolClient.ClientId' --output text"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        execute_cmd "$create_client_cmd" "Create User Pool Client"
        export USER_POOL_CLIENT_ID="dryrun123456789"
    else
        export USER_POOL_CLIENT_ID=$(eval "$create_client_cmd")
        echo "USER_POOL_CLIENT_ID=$USER_POOL_CLIENT_ID" >> .deployment-config
    fi
    
    success "Cognito User Pool created: $USER_POOL_ID"
    success "User Pool Client created: $USER_POOL_CLIENT_ID"
}

# Create DynamoDB table
create_dynamodb_table() {
    log "Creating DynamoDB table..."
    
    local create_table_cmd="aws dynamodb create-table \
        --table-name $TABLE_NAME \
        --attribute-definitions \
            AttributeName=id,AttributeType=S \
            AttributeName=author,AttributeType=S \
            AttributeName=createdAt,AttributeType=S \
        --key-schema \
            AttributeName=id,KeyType=HASH \
        --global-secondary-indexes \
            'IndexName=AuthorIndex,KeySchema=[{AttributeName=author,KeyType=HASH},{AttributeName=createdAt,KeyType=RANGE}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5}' \
        --provisioned-throughput \
            ReadCapacityUnits=5,WriteCapacityUnits=5"
    
    execute_cmd "$create_table_cmd" "Create DynamoDB table with GSI"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for DynamoDB table to be active..."
        aws dynamodb wait table-exists --table-name $TABLE_NAME
        success "DynamoDB table is active: $TABLE_NAME"
    fi
}

# Create GraphQL schema file
create_graphql_schema() {
    log "Creating GraphQL schema..."
    
    cat > schema.graphql << 'EOF'
type BlogPost {
    id: ID!
    title: String!
    content: String!
    author: String!
    createdAt: AWSDateTime!
    updatedAt: AWSDateTime!
    tags: [String]
    published: Boolean!
}

input CreateBlogPostInput {
    title: String!
    content: String!
    tags: [String]
    published: Boolean = false
}

input UpdateBlogPostInput {
    id: ID!
    title: String
    content: String
    tags: [String]
    published: Boolean
}

type Query {
    getBlogPost(id: ID!): BlogPost
    listBlogPosts(limit: Int, nextToken: String): BlogPostConnection
    listBlogPostsByAuthor(author: String!, limit: Int, nextToken: String): BlogPostConnection
}

type Mutation {
    createBlogPost(input: CreateBlogPostInput!): BlogPost
    updateBlogPost(input: UpdateBlogPostInput!): BlogPost
    deleteBlogPost(id: ID!): BlogPost
}

type Subscription {
    onCreateBlogPost: BlogPost
        @aws_subscribe(mutations: ["createBlogPost"])
    onUpdateBlogPost: BlogPost
        @aws_subscribe(mutations: ["updateBlogPost"])
    onDeleteBlogPost: BlogPost
        @aws_subscribe(mutations: ["deleteBlogPost"])
}

type BlogPostConnection {
    items: [BlogPost]
    nextToken: String
}

schema {
    query: Query
    mutation: Mutation
    subscription: Subscription
}
EOF
    
    success "GraphQL schema created"
}

# Create AppSync GraphQL API
create_appsync_api() {
    log "Creating AppSync GraphQL API..."
    
    local create_api_cmd="aws appsync create-graphql-api \
        --name $API_NAME \
        --authentication-type AMAZON_COGNITO_USER_POOLS \
        --user-pool-config userPoolId=$USER_POOL_ID,awsRegion=$AWS_REGION,defaultAction=ALLOW \
        --query 'graphqlApi.apiId' --output text"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        execute_cmd "$create_api_cmd" "Create AppSync API"
        export API_ID="dryrun123456789012345678"
    else
        export API_ID=$(eval "$create_api_cmd")
        echo "API_ID=$API_ID" >> .deployment-config
    fi
    
    success "AppSync API created: $API_ID"
    
    # Get API endpoints
    if [[ "$DRY_RUN" == "false" ]]; then
        export API_ENDPOINT=$(aws appsync get-graphql-api --api-id $API_ID \
            --query 'graphqlApi.uris.GRAPHQL' --output text)
        export REALTIME_ENDPOINT=$(aws appsync get-graphql-api --api-id $API_ID \
            --query 'graphqlApi.uris.REALTIME' --output text)
        
        echo "API_ENDPOINT=$API_ENDPOINT" >> .deployment-config
        echo "REALTIME_ENDPOINT=$REALTIME_ENDPOINT" >> .deployment-config
        
        log "GraphQL Endpoint: $API_ENDPOINT"
        log "Real-time Endpoint: $REALTIME_ENDPOINT"
    fi
}

# Upload GraphQL schema
upload_graphql_schema() {
    log "Uploading GraphQL schema..."
    
    local upload_schema_cmd="aws appsync start-schema-creation \
        --api-id $API_ID \
        --definition fileb://schema.graphql"
    
    execute_cmd "$upload_schema_cmd" "Upload GraphQL schema"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for schema creation to complete..."
        local schema_status="PROCESSING"
        local timeout=120
        local elapsed=0
        
        while [ "$schema_status" = "PROCESSING" ] && [ $elapsed -lt $timeout ]; do
            sleep 5
            elapsed=$((elapsed + 5))
            schema_status=$(aws appsync get-schema-creation-status --api-id $API_ID \
                --query 'status' --output text 2>/dev/null || echo "PROCESSING")
            log "Schema creation status: $schema_status (${elapsed}s elapsed)"
        done
        
        if [ "$schema_status" = "SUCCESS" ]; then
            success "GraphQL schema uploaded successfully"
        else
            error "Schema creation failed or timed out. Status: $schema_status"
            exit 1
        fi
    fi
}

# Create IAM role for AppSync
create_iam_role() {
    log "Creating IAM role for AppSync..."
    
    # Create trust policy
    cat > appsync-service-role-trust-policy.json << EOF
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
    
    export ROLE_NAME="AppSyncDynamoDBRole-$(echo $API_NAME | sed 's/[^a-zA-Z0-9]//g')"
    
    local create_role_cmd="aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document file://appsync-service-role-trust-policy.json \
        --query 'Role.Arn' --output text"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        execute_cmd "$create_role_cmd" "Create IAM role"
        export SERVICE_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
    else
        export SERVICE_ROLE_ARN=$(eval "$create_role_cmd")
        echo "SERVICE_ROLE_ARN=$SERVICE_ROLE_ARN" >> .deployment-config
        echo "ROLE_NAME=$ROLE_NAME" >> .deployment-config
    fi
    
    # Create policy for DynamoDB access
    cat > appsync-dynamodb-policy.json << EOF
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
    
    local attach_policy_cmd="aws iam put-role-policy \
        --role-name $ROLE_NAME \
        --policy-name DynamoDBAccess \
        --policy-document file://appsync-dynamodb-policy.json"
    
    execute_cmd "$attach_policy_cmd" "Attach DynamoDB policy to role"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for role to be available..."
        sleep 10
    fi
    
    success "IAM role created: $SERVICE_ROLE_ARN"
}

# Create AppSync data source
create_data_source() {
    log "Creating AppSync data source..."
    
    export DATA_SOURCE_NAME="BlogPostsDataSource"
    
    local create_datasource_cmd="aws appsync create-data-source \
        --api-id $API_ID \
        --name $DATA_SOURCE_NAME \
        --type AMAZON_DYNAMODB \
        --dynamodb-config tableName=$TABLE_NAME,awsRegion=$AWS_REGION \
        --service-role-arn $SERVICE_ROLE_ARN"
    
    execute_cmd "$create_datasource_cmd" "Create DynamoDB data source"
    
    success "DynamoDB data source created: $DATA_SOURCE_NAME"
}

# Create VTL resolver templates
create_resolver_templates() {
    log "Creating VTL resolver templates..."
    
    # Get BlogPost resolver templates
    cat > get-blog-post-request.vtl << 'EOF'
{
    "version": "2017-02-28",
    "operation": "GetItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
    }
}
EOF

    cat > get-blog-post-response.vtl << 'EOF'
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOF

    # Create BlogPost resolver templates
    cat > create-blog-post-request.vtl << 'EOF'
#set($id = $util.autoId())
#set($createdAt = $util.time.nowISO8601())
{
    "version": "2017-02-28",
    "operation": "PutItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($id)
    },
    "attributeValues": {
        "title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
        "content": $util.dynamodb.toDynamoDBJson($ctx.args.input.content),
        "author": $util.dynamodb.toDynamoDBJson($ctx.identity.username),
        "createdAt": $util.dynamodb.toDynamoDBJson($createdAt),
        "updatedAt": $util.dynamodb.toDynamoDBJson($createdAt),
        "tags": $util.dynamodb.toDynamoDBJson($ctx.args.input.tags),
        "published": $util.dynamodb.toDynamoDBJson($ctx.args.input.published)
    }
}
EOF

    cat > create-blog-post-response.vtl << 'EOF'
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
EOF

    # List BlogPosts resolver templates
    cat > list-blog-posts-request.vtl << 'EOF'
{
    "version": "2017-02-28",
    "operation": "Scan",
    #if($ctx.args.limit)
    "limit": $ctx.args.limit,
    #end
    #if($ctx.args.nextToken)
    "nextToken": "$ctx.args.nextToken",
    #end
}
EOF

    cat > list-blog-posts-response.vtl << 'EOF'
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
{
    "items": $util.toJson($ctx.result.items),
    #if($ctx.result.nextToken)
    "nextToken": "$ctx.result.nextToken"
    #end
}
EOF

    # List BlogPosts by Author resolver templates
    cat > list-by-author-request.vtl << 'EOF'
{
    "version": "2017-02-28",
    "operation": "Query",
    "index": "AuthorIndex",
    "query": {
        "expression": "author = :author",
        "expressionValues": {
            ":author": $util.dynamodb.toDynamoDBJson($ctx.args.author)
        }
    },
    #if($ctx.args.limit)
    "limit": $ctx.args.limit,
    #end
    #if($ctx.args.nextToken)
    "nextToken": "$ctx.args.nextToken",
    #end
    "scanIndexForward": false
}
EOF
    
    success "VTL resolver templates created"
}

# Create AppSync resolvers
create_resolvers() {
    log "Creating AppSync resolvers..."
    
    # getBlogPost resolver
    local create_get_resolver_cmd="aws appsync create-resolver \
        --api-id $API_ID \
        --type-name Query \
        --field-name getBlogPost \
        --data-source-name $DATA_SOURCE_NAME \
        --request-mapping-template file://get-blog-post-request.vtl \
        --response-mapping-template file://get-blog-post-response.vtl"
    
    execute_cmd "$create_get_resolver_cmd" "Create getBlogPost resolver"
    
    # createBlogPost resolver
    local create_create_resolver_cmd="aws appsync create-resolver \
        --api-id $API_ID \
        --type-name Mutation \
        --field-name createBlogPost \
        --data-source-name $DATA_SOURCE_NAME \
        --request-mapping-template file://create-blog-post-request.vtl \
        --response-mapping-template file://create-blog-post-response.vtl"
    
    execute_cmd "$create_create_resolver_cmd" "Create createBlogPost resolver"
    
    # listBlogPosts resolver
    local create_list_resolver_cmd="aws appsync create-resolver \
        --api-id $API_ID \
        --type-name Query \
        --field-name listBlogPosts \
        --data-source-name $DATA_SOURCE_NAME \
        --request-mapping-template file://list-blog-posts-request.vtl \
        --response-mapping-template file://list-blog-posts-response.vtl"
    
    execute_cmd "$create_list_resolver_cmd" "Create listBlogPosts resolver"
    
    # listBlogPostsByAuthor resolver
    local create_list_by_author_resolver_cmd="aws appsync create-resolver \
        --api-id $API_ID \
        --type-name Query \
        --field-name listBlogPostsByAuthor \
        --data-source-name $DATA_SOURCE_NAME \
        --request-mapping-template file://list-by-author-request.vtl \
        --response-mapping-template file://list-blog-posts-response.vtl"
    
    execute_cmd "$create_list_by_author_resolver_cmd" "Create listBlogPostsByAuthor resolver"
    
    success "AppSync resolvers created"
}

# Create test user
create_test_user() {
    log "Creating test user..."
    
    export TEST_USERNAME="testuser@example.com"
    export TEMP_PASSWORD="TempPass123!"
    export NEW_PASSWORD="BlogUser123!"
    
    local create_user_cmd="aws cognito-idp admin-create-user \
        --user-pool-id $USER_POOL_ID \
        --username $TEST_USERNAME \
        --user-attributes Name=email,Value=$TEST_USERNAME Name=email_verified,Value=true \
        --temporary-password $TEMP_PASSWORD \
        --message-action SUPPRESS"
    
    execute_cmd "$create_user_cmd" "Create test user"
    
    # Set permanent password
    local set_password_cmd="aws cognito-idp admin-set-user-password \
        --user-pool-id $USER_POOL_ID \
        --username $TEST_USERNAME \
        --password $NEW_PASSWORD \
        --permanent"
    
    execute_cmd "$set_password_cmd" "Set permanent password"
    
    # Save credentials to config
    cat >> .deployment-config << EOF
TEST_USERNAME=$TEST_USERNAME
NEW_PASSWORD=$NEW_PASSWORD
EOF
    
    success "Test user created: $TEST_USERNAME"
}

# Add API key authentication
add_api_key_auth() {
    log "Adding API key authentication..."
    
    local update_api_cmd="aws appsync update-graphql-api \
        --api-id $API_ID \
        --name $API_NAME \
        --authentication-type AMAZON_COGNITO_USER_POOLS \
        --user-pool-config userPoolId=$USER_POOL_ID,awsRegion=$AWS_REGION,defaultAction=ALLOW \
        --additional-authentication-providers authenticationType=API_KEY"
    
    execute_cmd "$update_api_cmd" "Update API to add API key authentication"
    
    # Create API key
    local create_key_cmd="aws appsync create-api-key \
        --api-id $API_ID \
        --description 'Test API Key' \
        --expires \$(date -d '+30 days' +%s) \
        --query 'apiKey.id' --output text"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        execute_cmd "$create_key_cmd" "Create API key"
        export API_KEY="da2-dryrunkey123456789"
    else
        export API_KEY=$(aws appsync list-api-keys --api-id $API_ID \
            --query 'apiKeys[0].id' --output text 2>/dev/null || \
            eval "aws appsync create-api-key \
                --api-id $API_ID \
                --description 'Test API Key' \
                --expires $(date -d '+30 days' +%s) \
                --query 'apiKey.id' --output text")
        echo "API_KEY=$API_KEY" >> .deployment-config
    fi
    
    success "API key created: $API_KEY"
}

# Create test client
create_test_client() {
    log "Creating test client script..."
    
    cat > test_client.py << EOF
import json
import requests
import boto3
from botocore.exceptions import ClientError
import os

# Load configuration
config = {}
if os.path.exists('.deployment-config'):
    with open('.deployment-config', 'r') as f:
        for line in f:
            if '=' in line:
                key, value = line.strip().split('=', 1)
                config[key] = value

# Configuration
API_ENDPOINT = config.get('API_ENDPOINT', 'https://example.appsync-api.us-east-1.amazonaws.com/graphql')
API_KEY = config.get('API_KEY', 'your-api-key-here')
USER_POOL_ID = config.get('USER_POOL_ID', 'us-east-1_XXXXXXXX')
CLIENT_ID = config.get('USER_POOL_CLIENT_ID', 'your-client-id')
USERNAME = config.get('TEST_USERNAME', 'testuser@example.com')
PASSWORD = config.get('NEW_PASSWORD', 'BlogUser123!')

def get_auth_token():
    """Get Cognito ID token for authenticated requests"""
    try:
        client = boto3.client('cognito-idp')
        
        # Get client secret
        response = client.describe_user_pool_client(
            UserPoolId=USER_POOL_ID,
            ClientId=CLIENT_ID
        )
        client_secret = response['UserPoolClient']['ClientSecret']
        
        # Calculate secret hash
        import hmac
        import hashlib
        import base64
        
        message = USERNAME + CLIENT_ID
        dig = hmac.new(
            client_secret.encode('UTF-8'),
            message.encode('UTF-8'),
            hashlib.sha256
        ).digest()
        secret_hash = base64.b64encode(dig).decode()
        
        # Authenticate user
        auth_response = client.admin_initiate_auth(
            UserPoolId=USER_POOL_ID,
            ClientId=CLIENT_ID,
            AuthFlow='ADMIN_NO_SRP_AUTH',
            AuthParameters={
                'USERNAME': USERNAME,
                'PASSWORD': PASSWORD,
                'SECRET_HASH': secret_hash
            }
        )
        
        return auth_response['AuthenticationResult']['IdToken']
    except ClientError as e:
        print(f"Error getting auth token: {e}")
        return None

def graphql_request(query, variables=None, use_auth=False):
    """Make GraphQL request to AppSync API"""
    headers = {'Content-Type': 'application/json'}
    
    if use_auth:
        token = get_auth_token()
        if token:
            headers['Authorization'] = token
        else:
            print("Failed to get auth token, using API key")
            headers['x-api-key'] = API_KEY
    else:
        headers['x-api-key'] = API_KEY
    
    payload = {'query': query}
    if variables:
        payload['variables'] = variables
    
    try:
        response = requests.post(API_ENDPOINT, json=payload, headers=headers)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Request failed: {e}")
        return {"errors": [{"message": str(e)}]}

# Test queries
def test_api():
    print("Testing AppSync GraphQL API...")
    print(f"API Endpoint: {API_ENDPOINT}")
    print(f"API Key: {API_KEY}")
    
    # Test 1: Create a blog post (requires authentication)
    create_mutation = '''
    mutation CreatePost(\$input: CreateBlogPostInput!) {
        createBlogPost(input: \$input) {
            id
            title
            content
            author
            createdAt
            published
            tags
        }
    }
    '''
    
    variables = {
        "input": {
            "title": "My First Blog Post",
            "content": "This is the content of my first blog post created via GraphQL!",
            "tags": ["technology", "aws", "graphql"],
            "published": True
        }
    }
    
    print("\\n1. Creating blog post...")
    result = graphql_request(create_mutation, variables, use_auth=True)
    print(json.dumps(result, indent=2))
    
    # Test 2: List all blog posts
    list_query = '''
    query ListPosts {
        listBlogPosts(limit: 10) {
            items {
                id
                title
                author
                createdAt
                published
                tags
            }
            nextToken
        }
    }
    '''
    
    print("\\n2. Listing blog posts...")
    result = graphql_request(list_query)
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    test_api()
EOF
    
    success "Test client created: test_client.py"
}

# Display deployment summary
display_summary() {
    echo ""
    echo "=============================================="
    echo "          DEPLOYMENT SUMMARY"
    echo "=============================================="
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN COMPLETED - No resources were created"
        echo ""
        echo "The following resources would have been created:"
        echo "- Cognito User Pool: $USER_POOL_NAME"
        echo "- DynamoDB Table: $TABLE_NAME"
        echo "- AppSync GraphQL API: $API_NAME"
        echo "- IAM Role: $ROLE_NAME"
        echo ""
        echo "To deploy for real, run: $0"
        return 0
    fi
    
    if [[ -f ".deployment-config" ]]; then
        source .deployment-config
        
        echo "✅ Deployment completed successfully!"
        echo ""
        echo "🏗️  Infrastructure Created:"
        echo "   • Cognito User Pool: $USER_POOL_ID"
        echo "   • DynamoDB Table: $TABLE_NAME"
        echo "   • AppSync GraphQL API: $API_ID"
        echo "   • IAM Role: $ROLE_NAME"
        echo ""
        echo "🔗 API Endpoints:"
        echo "   • GraphQL: $API_ENDPOINT"
        echo "   • Real-time: $REALTIME_ENDPOINT"
        echo ""
        echo "🔐 Authentication:"
        echo "   • API Key: $API_KEY"
        echo "   • Test User: $TEST_USERNAME"
        echo "   • Password: $NEW_PASSWORD"
        echo ""
        echo "🧪 Testing:"
        echo "   • Test client: test_client.py"
        echo "   • To test: python3 test_client.py"
        echo ""
        echo "📊 Estimated Monthly Cost:"
        echo "   • AppSync: ~\$4.00 (1M requests)"
        echo "   • DynamoDB: ~\$1.25 (5 RCU/WCU)"
        echo "   • Cognito: Free tier (up to 50K MAU)"
        echo ""
        echo "🧹 Cleanup:"
        echo "   • Run: ./destroy.sh"
        echo ""
        echo "⚠️  Important Notes:"
        echo "   • Configuration saved to .deployment-config"
        echo "   • API key expires in 30 days"
        echo "   • Review security settings before production use"
        echo ""
        echo "=============================================="
    else
        warn "Configuration file not found. Some information may be missing."
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Cleaning up temporary files..."
        rm -f appsync-service-role-trust-policy.json
        rm -f appsync-dynamodb-policy.json
        rm -f *.vtl
        rm -f schema.graphql
        success "Temporary files cleaned up"
    fi
}

# Main execution
main() {
    log "Starting AppSync GraphQL API deployment..."
    
    check_prerequisites
    setup_environment
    create_cognito_user_pool
    create_dynamodb_table
    create_graphql_schema
    create_appsync_api
    upload_graphql_schema
    create_iam_role
    create_data_source
    create_resolver_templates
    create_resolvers
    create_test_user
    add_api_key_auth
    create_test_client
    cleanup_temp_files
    display_summary
    
    log "Deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "Next steps:"
        echo "1. Test the API: python3 test_client.py"
        echo "2. Open AppSync console to explore the API"
        echo "3. When done, run ./destroy.sh to clean up"
    fi
}

# Execute main function
main "$@"