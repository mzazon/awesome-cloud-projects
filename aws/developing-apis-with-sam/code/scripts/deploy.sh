#!/bin/bash

# deploy.sh - Serverless API Development with SAM and API Gateway
# This script deploys a complete serverless API using AWS SAM
# with Lambda functions, API Gateway, and DynamoDB

set -e

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be created"
fi

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check SAM CLI
    if ! command -v sam &> /dev/null; then
        error "SAM CLI is not installed. Please install SAM CLI."
        exit 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed. Please install Python 3.9+."
        exit 1
    fi
    
    # Check Docker (required for SAM local testing)
    if ! command -v docker &> /dev/null; then
        warning "Docker is not installed. SAM local testing will not be available."
    else
        # Check if Docker is running
        if ! docker info &> /dev/null; then
            warning "Docker is not running. SAM local testing will not be available."
        fi
    fi
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured or invalid."
        error "Please run 'aws configure' or set AWS_PROFILE environment variable."
        exit 1
    fi
    
    # Check AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            error "AWS region is not set. Please set AWS_REGION environment variable or configure default region."
            exit 1
        fi
    fi
    
    success "Prerequisites check completed"
}

# Function to generate unique resource names
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique identifier using account ID and timestamp
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    TIMESTAMP=$(date +%s)
    RANDOM_SUFFIX=$(echo "${ACCOUNT_ID}${TIMESTAMP}" | sha256sum | head -c 6)
    
    # Set environment variables
    export PROJECT_NAME="sam-api-${RANDOM_SUFFIX}"
    export STACK_NAME="${PROJECT_NAME}"
    export DYNAMO_TABLE_NAME="users-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="${PROJECT_NAME}-artifacts-${ACCOUNT_ID}"
    
    # Store variables for cleanup script
    cat > deployment_vars.env << EOF
PROJECT_NAME=${PROJECT_NAME}
STACK_NAME=${STACK_NAME}
DYNAMO_TABLE_NAME=${DYNAMO_TABLE_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
AWS_REGION=${AWS_REGION}
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF
    
    log "Environment configured:"
    log "  Project Name: ${PROJECT_NAME}"
    log "  Stack Name: ${STACK_NAME}"
    log "  AWS Region: ${AWS_REGION}"
    log "  S3 Bucket: ${S3_BUCKET_NAME}"
    
    success "Environment setup completed"
}

# Function to create S3 bucket for SAM artifacts
create_s3_bucket() {
    log "Creating S3 bucket for SAM artifacts..."
    
    if $DRY_RUN; then
        log "DRY RUN: Would create S3 bucket: ${S3_BUCKET_NAME}"
        return 0
    fi
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
        warning "S3 bucket ${S3_BUCKET_NAME} already exists"
    else
        # Create bucket with appropriate location constraint
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3api create-bucket --bucket "${S3_BUCKET_NAME}"
        else
            aws s3api create-bucket \
                --bucket "${S3_BUCKET_NAME}" \
                --create-bucket-configuration LocationConstraint="${AWS_REGION}"
        fi
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "${S3_BUCKET_NAME}" \
            --versioning-configuration Status=Enabled
        
        # Block public access
        aws s3api put-public-access-block \
            --bucket "${S3_BUCKET_NAME}" \
            --public-access-block-configuration \
            BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
        
        success "S3 bucket ${S3_BUCKET_NAME} created successfully"
    fi
}

# Function to create SAM project structure
create_sam_project() {
    log "Creating SAM project structure..."
    
    if $DRY_RUN; then
        log "DRY RUN: Would create SAM project structure"
        return 0
    fi
    
    # Create project directory
    mkdir -p "${PROJECT_NAME}"
    cd "${PROJECT_NAME}"
    
    # Initialize SAM application
    sam init \
        --runtime python3.9 \
        --name "${PROJECT_NAME}" \
        --app-template "hello-world" \
        --no-interactive
    
    cd "${PROJECT_NAME}"
    
    success "SAM project structure created"
}

# Function to generate SAM template
generate_sam_template() {
    log "Generating SAM template..."
    
    if $DRY_RUN; then
        log "DRY RUN: Would generate SAM template"
        return 0
    fi
    
    # Backup original template
    if [[ -f template.yaml ]]; then
        cp template.yaml template.yaml.backup
    fi
    
    # Create comprehensive SAM template
    cat > template.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: Serverless API Development with SAM and API Gateway

Globals:
  Function:
    Timeout: 30
    MemorySize: 128
    Runtime: python3.9
    Environment:
      Variables:
        DYNAMODB_TABLE: !Ref UsersTable
        CORS_ALLOW_ORIGIN: '*'

Resources:
  UsersApi:
    Type: AWS::Serverless::Api
    Properties:
      StageName: dev
      Cors:
        AllowMethods: "'GET,POST,PUT,DELETE,OPTIONS'"
        AllowHeaders: "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
        AllowOrigin: "'*'"

  # GET /users - List all users
  ListUsersFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: src/list_users/
      Handler: app.lambda_handler
      Events:
        Api:
          Type: Api
          Properties:
            RestApiId: !Ref UsersApi
            Path: /users
            Method: GET
      Policies:
        - DynamoDBReadPolicy:
            TableName: !Ref UsersTable

  # POST /users - Create new user
  CreateUserFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: src/create_user/
      Handler: app.lambda_handler
      Events:
        Api:
          Type: Api
          Properties:
            RestApiId: !Ref UsersApi
            Path: /users
            Method: POST
      Policies:
        - DynamoDBWritePolicy:
            TableName: !Ref UsersTable

  # GET /users/{id} - Get specific user
  GetUserFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: src/get_user/
      Handler: app.lambda_handler
      Events:
        Api:
          Type: Api
          Properties:
            RestApiId: !Ref UsersApi
            Path: /users/{id}
            Method: GET
      Policies:
        - DynamoDBReadPolicy:
            TableName: !Ref UsersTable

  # PUT /users/{id} - Update user
  UpdateUserFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: src/update_user/
      Handler: app.lambda_handler
      Events:
        Api:
          Type: Api
          Properties:
            RestApiId: !Ref UsersApi
            Path: /users/{id}
            Method: PUT
      Policies:
        - DynamoDBWritePolicy:
            TableName: !Ref UsersTable

  # DELETE /users/{id} - Delete user
  DeleteUserFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: src/delete_user/
      Handler: app.lambda_handler
      Events:
        Api:
          Type: Api
          Properties:
            RestApiId: !Ref UsersApi
            Path: /users/{id}
            Method: DELETE
      Policies:
        - DynamoDBWritePolicy:
            TableName: !Ref UsersTable

  # DynamoDB Table
  UsersTable:
    Type: AWS::DynamoDB::Table
    Properties:
      TableName: !Sub "${AWS::StackName}-users"
      AttributeDefinitions:
        - AttributeName: id
          AttributeType: S
      KeySchema:
        - AttributeName: id
          KeyType: HASH
      BillingMode: PAY_PER_REQUEST

Outputs:
  ApiGatewayUrl:
    Description: API Gateway endpoint URL
    Value: !Sub "https://${UsersApi}.execute-api.${AWS::Region}.amazonaws.com/dev/"
    Export:
      Name: !Sub "${AWS::StackName}-ApiUrl"
  
  UsersTableName:
    Description: DynamoDB table name
    Value: !Ref UsersTable
    Export:
      Name: !Sub "${AWS::StackName}-TableName"
EOF
    
    success "SAM template generated"
}

# Function to create Lambda function source code
create_lambda_functions() {
    log "Creating Lambda function source code..."
    
    if $DRY_RUN; then
        log "DRY RUN: Would create Lambda function source code"
        return 0
    fi
    
    # Remove default hello_world directory
    rm -rf hello_world/
    
    # Create function directories
    mkdir -p src/{list_users,create_user,get_user,update_user,delete_user}
    mkdir -p src/shared
    
    # Create shared utilities
    cat > src/shared/dynamodb_utils.py << 'EOF'
import json
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')

def get_table():
    import os
    table_name = os.environ.get('DYNAMODB_TABLE')
    return dynamodb.Table(table_name)

def create_response(status_code, body, headers=None):
    default_headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    }
    
    if headers:
        default_headers.update(headers)
    
    return {
        'statusCode': status_code,
        'headers': default_headers,
        'body': json.dumps(body) if isinstance(body, (dict, list)) else body
    }

def handle_dynamodb_error(error):
    if error.response['Error']['Code'] == 'ResourceNotFoundException':
        return create_response(404, {'error': 'Resource not found'})
    else:
        return create_response(500, {'error': 'Internal server error'})
EOF

    # Create Lambda functions
    create_list_users_function
    create_create_user_function
    create_get_user_function
    create_update_user_function
    create_delete_user_function
    
    # Create requirements.txt for each function
    for func in list_users create_user get_user update_user delete_user; do
        cat > "src/${func}/requirements.txt" << 'EOF'
boto3==1.26.137
botocore==1.29.137
EOF
    done
    
    success "Lambda function source code created"
}

# Individual function creation functions
create_list_users_function() {
    cat > src/list_users/app.py << 'EOF'
import json
import sys
import os

# Add shared directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))

from dynamodb_utils import get_table, create_response, handle_dynamodb_error
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    try:
        table = get_table()
        
        # Scan table for all users
        response = table.scan()
        users = response.get('Items', [])
        
        # Handle pagination if needed
        while 'LastEvaluatedKey' in response:
            response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
            users.extend(response.get('Items', []))
        
        return create_response(200, users)
        
    except ClientError as e:
        return handle_dynamodb_error(e)
    except Exception as e:
        return create_response(500, {'error': str(e)})
EOF
}

create_create_user_function() {
    cat > src/create_user/app.py << 'EOF'
import json
import sys
import os
import uuid
from datetime import datetime

# Add shared directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))

from dynamodb_utils import get_table, create_response, handle_dynamodb_error
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        # Validate required fields
        if not body.get('name') or not body.get('email'):
            return create_response(400, {'error': 'Name and email are required'})
        
        # Generate user ID and timestamp
        user_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat()
        
        # Create user item
        user_item = {
            'id': user_id,
            'name': body['name'],
            'email': body['email'],
            'created_at': timestamp,
            'updated_at': timestamp
        }
        
        # Optional fields
        if body.get('age'):
            user_item['age'] = int(body['age'])
        
        # Put item in DynamoDB
        table = get_table()
        table.put_item(Item=user_item)
        
        return create_response(201, user_item)
        
    except ClientError as e:
        return handle_dynamodb_error(e)
    except ValueError as e:
        return create_response(400, {'error': 'Invalid JSON in request body'})
    except Exception as e:
        return create_response(500, {'error': str(e)})
EOF
}

create_get_user_function() {
    cat > src/get_user/app.py << 'EOF'
import json
import sys
import os

# Add shared directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))

from dynamodb_utils import get_table, create_response, handle_dynamodb_error
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    try:
        # Get user ID from path parameters
        user_id = event['pathParameters']['id']
        
        # Get item from DynamoDB
        table = get_table()
        response = table.get_item(Key={'id': user_id})
        
        if 'Item' not in response:
            return create_response(404, {'error': 'User not found'})
        
        return create_response(200, response['Item'])
        
    except ClientError as e:
        return handle_dynamodb_error(e)
    except Exception as e:
        return create_response(500, {'error': str(e)})
EOF
}

create_update_user_function() {
    cat > src/update_user/app.py << 'EOF'
import json
import sys
import os
from datetime import datetime

# Add shared directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))

from dynamodb_utils import get_table, create_response, handle_dynamodb_error
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    try:
        # Get user ID from path parameters
        user_id = event['pathParameters']['id']
        
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        # Check if user exists
        table = get_table()
        response = table.get_item(Key={'id': user_id})
        
        if 'Item' not in response:
            return create_response(404, {'error': 'User not found'})
        
        # Build update expression
        update_expression = "SET updated_at = :timestamp"
        expression_values = {':timestamp': datetime.utcnow().isoformat()}
        
        if body.get('name'):
            update_expression += ", #name = :name"
            expression_values[':name'] = body['name']
        
        if body.get('email'):
            update_expression += ", email = :email"
            expression_values[':email'] = body['email']
        
        if body.get('age'):
            update_expression += ", age = :age"
            expression_values[':age'] = int(body['age'])
        
        # Update item
        response = table.update_item(
            Key={'id': user_id},
            UpdateExpression=update_expression,
            ExpressionAttributeNames={'#name': 'name'} if body.get('name') else {},
            ExpressionAttributeValues=expression_values,
            ReturnValues='ALL_NEW'
        )
        
        return create_response(200, response['Attributes'])
        
    except ClientError as e:
        return handle_dynamodb_error(e)
    except ValueError as e:
        return create_response(400, {'error': 'Invalid JSON in request body'})
    except Exception as e:
        return create_response(500, {'error': str(e)})
EOF
}

create_delete_user_function() {
    cat > src/delete_user/app.py << 'EOF'
import json
import sys
import os

# Add shared directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'shared'))

from dynamodb_utils import get_table, create_response, handle_dynamodb_error
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    try:
        # Get user ID from path parameters
        user_id = event['pathParameters']['id']
        
        # Check if user exists
        table = get_table()
        response = table.get_item(Key={'id': user_id})
        
        if 'Item' not in response:
            return create_response(404, {'error': 'User not found'})
        
        # Delete item
        table.delete_item(Key={'id': user_id})
        
        return create_response(204, '')
        
    except ClientError as e:
        return handle_dynamodb_error(e)
    except Exception as e:
        return create_response(500, {'error': str(e)})
EOF
}

# Function to build and deploy SAM application
build_and_deploy() {
    log "Building and deploying SAM application..."
    
    if $DRY_RUN; then
        log "DRY RUN: Would build and deploy SAM application"
        return 0
    fi
    
    # Build the SAM application
    log "Building SAM application..."
    sam build
    
    # Deploy with guided deployment
    log "Deploying SAM application..."
    sam deploy \
        --stack-name "${STACK_NAME}" \
        --s3-bucket "${S3_BUCKET_NAME}" \
        --capabilities CAPABILITY_IAM \
        --no-confirm-changeset \
        --no-fail-on-empty-changeset
    
    success "SAM application deployed successfully"
}

# Function to get deployment outputs
get_deployment_outputs() {
    log "Retrieving deployment outputs..."
    
    if $DRY_RUN; then
        log "DRY RUN: Would retrieve deployment outputs"
        return 0
    fi
    
    # Get API Gateway URL
    API_URL=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
        --output text)
    
    # Get DynamoDB table name
    TABLE_NAME=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --query 'Stacks[0].Outputs[?OutputKey==`UsersTableName`].OutputValue' \
        --output text)
    
    # Save outputs to file
    cat >> deployment_vars.env << EOF
API_URL=${API_URL}
TABLE_NAME=${TABLE_NAME}
EOF
    
    success "Deployment completed successfully!"
    echo ""
    echo "🎉 Your serverless API is now live!"
    echo ""
    echo "📊 Deployment Summary:"
    echo "  Stack Name: ${STACK_NAME}"
    echo "  API Gateway URL: ${API_URL}"
    echo "  DynamoDB Table: ${TABLE_NAME}"
    echo "  S3 Bucket: ${S3_BUCKET_NAME}"
    echo ""
    echo "🔗 Quick Test Commands:"
    echo "  List users: curl ${API_URL}users"
    echo "  Create user: curl -X POST ${API_URL}users -H 'Content-Type: application/json' -d '{\"name\":\"John Doe\",\"email\":\"john@example.com\"}'"
    echo ""
    echo "📁 Configuration saved to: deployment_vars.env"
    echo "🗑️  To cleanup: ./destroy.sh"
}

# Function to create test data
create_test_data() {
    log "Creating test data..."
    
    if $DRY_RUN; then
        log "DRY RUN: Would create test data"
        return 0
    fi
    
    # Wait a moment for API Gateway to be fully ready
    sleep 10
    
    # Create test users
    log "Creating test user 1..."
    USER1_RESPONSE=$(curl -s -X POST "${API_URL}users" \
        -H "Content-Type: application/json" \
        -d '{"name": "John Doe", "email": "john@example.com", "age": 30}' || echo '{}')
    
    log "Creating test user 2..."
    USER2_RESPONSE=$(curl -s -X POST "${API_URL}users" \
        -H "Content-Type: application/json" \
        -d '{"name": "Jane Smith", "email": "jane@example.com", "age": 25}' || echo '{}')
    
    if [[ "$USER1_RESPONSE" != '{}' ]] && [[ "$USER2_RESPONSE" != '{}' ]]; then
        success "Test data created successfully"
    else
        warning "Test data creation may have failed - API might need more time to initialize"
    fi
}

# Function to create CloudWatch dashboard
create_monitoring_dashboard() {
    log "Creating CloudWatch monitoring dashboard..."
    
    if $DRY_RUN; then
        log "DRY RUN: Would create monitoring dashboard"
        return 0
    fi
    
    # Create dashboard JSON
    cat > dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/ApiGateway", "Count", "ApiName", "${STACK_NAME}"],
                    ["AWS/ApiGateway", "Latency", "ApiName", "${STACK_NAME}"],
                    ["AWS/ApiGateway", "4XXError", "ApiName", "${STACK_NAME}"],
                    ["AWS/ApiGateway", "5XXError", "ApiName", "${STACK_NAME}"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "API Gateway Metrics"
            }
        },
        {
            "type": "metric",
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", "${TABLE_NAME}"],
                    ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", "${TABLE_NAME}"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "DynamoDB Metrics"
            }
        }
    ]
}
EOF
    
    # Create the dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${STACK_NAME}-monitoring" \
        --dashboard-body file://dashboard.json
    
    # Clean up temporary file
    rm dashboard.json
    
    success "CloudWatch dashboard created: ${STACK_NAME}-monitoring"
}

# Main execution flow
main() {
    echo "🚀 Starting Serverless API Deployment with SAM and API Gateway"
    echo "=============================================================="
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_sam_project
    generate_sam_template
    create_lambda_functions
    build_and_deploy
    get_deployment_outputs
    create_test_data
    create_monitoring_dashboard
    
    echo ""
    echo "=============================================================="
    success "🎉 Deployment completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Test your API endpoints using the URLs above"
    echo "2. Monitor your API in the CloudWatch dashboard"
    echo "3. Explore the SAM template and Lambda functions"
    echo "4. Run './destroy.sh' when you're done to clean up resources"
    echo ""
    echo "For troubleshooting, check the CloudFormation stack events in the AWS Console."
}

# Handle script termination
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        error "Deployment failed!"
        echo "Check the error messages above for details."
        echo "You may need to run './destroy.sh' to clean up any partially created resources."
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"