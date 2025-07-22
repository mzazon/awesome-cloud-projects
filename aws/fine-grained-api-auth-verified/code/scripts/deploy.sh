#!/bin/bash

# Deploy script for Fine-Grained API Authorization with Verified Permissions
# This script creates a complete ABAC system with Cognito, Verified Permissions, API Gateway, and Lambda

set -e

# Color codes for output
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

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check if zip is installed
    if ! command -v zip &> /dev/null; then
        error "zip utility is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions
    log "Verifying AWS permissions..."
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    
    if [ -z "$region" ]; then
        error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export USER_POOL_NAME="DocManagement-UserPool-${RANDOM_SUFFIX}"
    export POLICY_STORE_NAME="DocManagement-PolicyStore-${RANDOM_SUFFIX}"
    export API_NAME="DocManagement-API-${RANDOM_SUFFIX}"
    export DOCUMENTS_TABLE="Documents-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="VerifiedPermissions-Lambda-Role-${RANDOM_SUFFIX}"
    export AUTHORIZER_FUNCTION_NAME="DocManagement-Authorizer-${RANDOM_SUFFIX}"
    export BUSINESS_FUNCTION_NAME="DocManagement-Business-${RANDOM_SUFFIX}"
    
    # Create state file to store resource IDs
    mkdir -p .deployment-state
    cat > .deployment-state/resources.env << EOF
RANDOM_SUFFIX=${RANDOM_SUFFIX}
USER_POOL_NAME=${USER_POOL_NAME}
POLICY_STORE_NAME=${POLICY_STORE_NAME}
API_NAME=${API_NAME}
DOCUMENTS_TABLE=${DOCUMENTS_TABLE}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
AUTHORIZER_FUNCTION_NAME=${AUTHORIZER_FUNCTION_NAME}
BUSINESS_FUNCTION_NAME=${BUSINESS_FUNCTION_NAME}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
EOF
    
    success "Environment variables configured"
}

# Create DynamoDB table
create_dynamodb_table() {
    log "Creating DynamoDB table for document storage..."
    
    if aws dynamodb describe-table --table-name "${DOCUMENTS_TABLE}" &> /dev/null; then
        warn "DynamoDB table ${DOCUMENTS_TABLE} already exists, skipping creation"
        return 0
    fi
    
    aws dynamodb create-table \
        --table-name "${DOCUMENTS_TABLE}" \
        --attribute-definitions \
            AttributeName=documentId,AttributeType=S \
        --key-schema \
            AttributeName=documentId,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Purpose,Value=VerifiedPermissionsDemo
    
    log "Waiting for DynamoDB table to be active..."
    aws dynamodb wait table-exists --table-name "${DOCUMENTS_TABLE}"
    
    success "DynamoDB table created successfully"
}

# Create Cognito User Pool
create_cognito_user_pool() {
    log "Creating Cognito User Pool..."
    
    USER_POOL_ID=$(aws cognito-idp create-user-pool \
        --pool-name "${USER_POOL_NAME}" \
        --policies "PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=false}" \
        --schema \
            Name=email,AttributeDataType=String,Required=true,Mutable=true \
            Name=department,AttributeDataType=String,DeveloperOnlyAttribute=false,Mutable=true \
            Name=role,AttributeDataType=String,DeveloperOnlyAttribute=false,Mutable=true \
        --auto-verified-attributes email \
        --query UserPool.Id --output text)
    
    if [ -z "$USER_POOL_ID" ]; then
        error "Failed to create Cognito User Pool"
        exit 1
    fi
    
    USER_POOL_CLIENT_ID=$(aws cognito-idp create-user-pool-client \
        --user-pool-id "${USER_POOL_ID}" \
        --client-name "DocManagement-Client" \
        --explicit-auth-flows ADMIN_NO_SRP_AUTH USER_PASSWORD_AUTH \
        --generate-secret \
        --query UserPoolClient.ClientId --output text)
    
    if [ -z "$USER_POOL_CLIENT_ID" ]; then
        error "Failed to create Cognito User Pool Client"
        exit 1
    fi
    
    # Store IDs in state file
    echo "USER_POOL_ID=${USER_POOL_ID}" >> .deployment-state/resources.env
    echo "USER_POOL_CLIENT_ID=${USER_POOL_CLIENT_ID}" >> .deployment-state/resources.env
    
    success "Cognito User Pool created: ${USER_POOL_ID}"
}

# Create Verified Permissions Policy Store
create_policy_store() {
    log "Creating Verified Permissions Policy Store..."
    
    POLICY_STORE_ID=$(aws verifiedpermissions create-policy-store \
        --description "Document Management Authorization Policies" \
        --validation-settings mode=STRICT \
        --query policyStoreId --output text)
    
    if [ -z "$POLICY_STORE_ID" ]; then
        error "Failed to create Policy Store"
        exit 1
    fi
    
    # Create identity source linking Cognito to Verified Permissions
    cat > cognito-config.json << EOF
{
    "cognitoUserPoolConfiguration": {
        "userPoolArn": "arn:aws:cognito-idp:${AWS_REGION}:${AWS_ACCOUNT_ID}:userpool/${USER_POOL_ID}",
        "clientIds": ["${USER_POOL_CLIENT_ID}"]
    }
}
EOF
    
    IDENTITY_SOURCE_ID=$(aws verifiedpermissions create-identity-source \
        --policy-store-id "${POLICY_STORE_ID}" \
        --configuration file://cognito-config.json \
        --principal-entity-type "User" \
        --query identitySourceId --output text)
    
    if [ -z "$IDENTITY_SOURCE_ID" ]; then
        error "Failed to create Identity Source"
        exit 1
    fi
    
    # Store IDs in state file
    echo "POLICY_STORE_ID=${POLICY_STORE_ID}" >> .deployment-state/resources.env
    echo "IDENTITY_SOURCE_ID=${IDENTITY_SOURCE_ID}" >> .deployment-state/resources.env
    
    success "Policy Store created: ${POLICY_STORE_ID}"
}

# Create Cedar authorization policies
create_cedar_policies() {
    log "Creating Cedar authorization policies..."
    
    # Create policy for document viewing
    cat > view-policy.cedar << 'EOF'
permit(
    principal,
    action == Action::"ViewDocument",
    resource
) when {
    principal.department == resource.department ||
    principal.role == "Manager" ||
    principal.role == "Admin"
};
EOF
    
    # Create policy for document editing
    cat > edit-policy.cedar << 'EOF'
permit(
    principal,
    action == Action::"EditDocument",
    resource
) when {
    (principal.sub == resource.owner) ||
    (principal.role == "Manager" && principal.department == resource.department) ||
    principal.role == "Admin"
};
EOF
    
    # Create policy for document deletion
    cat > delete-policy.cedar << 'EOF'
permit(
    principal,
    action == Action::"DeleteDocument",
    resource
) when {
    principal.role == "Admin"
};
EOF
    
    # Deploy policies to Verified Permissions
    VIEW_POLICY_ID=$(aws verifiedpermissions create-policy \
        --policy-store-id "${POLICY_STORE_ID}" \
        --definition "static={description=\"Allow document viewing based on department or management role\",statement=\"$(cat view-policy.cedar | tr '\n' ' ')\"}" \
        --query policyId --output text)
    
    EDIT_POLICY_ID=$(aws verifiedpermissions create-policy \
        --policy-store-id "${POLICY_STORE_ID}" \
        --definition "static={description=\"Allow document editing for owners, department managers, or admins\",statement=\"$(cat edit-policy.cedar | tr '\n' ' ')\"}" \
        --query policyId --output text)
    
    DELETE_POLICY_ID=$(aws verifiedpermissions create-policy \
        --policy-store-id "${POLICY_STORE_ID}" \
        --definition "static={description=\"Allow document deletion for admins only\",statement=\"$(cat delete-policy.cedar | tr '\n' ' ')\"}" \
        --query policyId --output text)
    
    # Store policy IDs in state file
    echo "VIEW_POLICY_ID=${VIEW_POLICY_ID}" >> .deployment-state/resources.env
    echo "EDIT_POLICY_ID=${EDIT_POLICY_ID}" >> .deployment-state/resources.env
    echo "DELETE_POLICY_ID=${DELETE_POLICY_ID}" >> .deployment-state/resources.env
    
    success "Cedar policies created successfully"
}

# Create IAM role for Lambda functions
create_lambda_role() {
    log "Creating IAM role for Lambda functions..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &> /dev/null; then
        warn "IAM role ${LAMBDA_ROLE_NAME} already exists, skipping creation"
        LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" --query Role.Arn --output text)
        echo "LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> .deployment-state/resources.env
        return 0
    fi
    
    cat > trust-policy.json << 'EOF'
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
    
    LAMBDA_ROLE_ARN=$(aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document file://trust-policy.json \
        --query Role.Arn --output text)
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for Verified Permissions and DynamoDB access
    cat > lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "verifiedpermissions:IsAuthorizedWithToken"
            ],
            "Resource": "arn:aws:verifiedpermissions::${AWS_ACCOUNT_ID}:policy-store/${POLICY_STORE_ID}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Scan",
                "dynamodb:Query"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DOCUMENTS_TABLE}"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-name "VerifiedPermissionsAndDynamoDBAccess" \
        --policy-document file://lambda-policy.json
    
    # Store role ARN in state file
    echo "LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> .deployment-state/resources.env
    
    success "IAM role created: ${LAMBDA_ROLE_ARN}"
}

# Create Lambda authorizer function
create_lambda_authorizer() {
    log "Creating Lambda authorizer function..."
    
    # Create Lambda function code
    mkdir -p lambda-authorizer
    cat > lambda-authorizer/index.py << 'EOF'
import json
import boto3
import jwt
from jwt import PyJWKSClient
import os
import urllib.request

verifiedpermissions = boto3.client('verifiedpermissions')
policy_store_id = os.environ['POLICY_STORE_ID']
user_pool_id = os.environ['USER_POOL_ID']
region = os.environ['AWS_REGION']

def lambda_handler(event, context):
    try:
        # Extract token from Authorization header
        token = event['authorizationToken'].replace('Bearer ', '')
        
        # Decode JWT token to get user attributes
        jwks_url = f'https://cognito-idp.{region}.amazonaws.com/{user_pool_id}/.well-known/jwks.json'
        jwks_client = PyJWKSClient(jwks_url)
        signing_key = jwks_client.get_signing_key_from_jwt(token)
        
        decoded_token = jwt.decode(
            token,
            signing_key.key,
            algorithms=['RS256'],
            audience=os.environ.get('USER_POOL_CLIENT_ID')
        )
        
        # Extract resource and action from method ARN
        method_arn = event['methodArn']
        resource_parts = method_arn.split(':')
        api_parts = resource_parts[5].split('/')
        
        http_method = api_parts[1]
        resource_path = '/'.join(api_parts[2:])
        
        # Map HTTP methods to actions
        action_map = {
            'GET': 'ViewDocument',
            'PUT': 'EditDocument',
            'POST': 'EditDocument',
            'DELETE': 'DeleteDocument'
        }
        
        action = action_map.get(http_method, 'ViewDocument')
        
        # Extract document ID from path
        document_id = resource_path.split('/')[-1] if resource_path else 'unknown'
        
        # Make authorization request to Verified Permissions
        response = verifiedpermissions.is_authorized_with_token(
            policyStoreId=policy_store_id,
            identityToken=token,
            action={
                'actionType': 'Action',
                'actionId': action
            },
            resource={
                'entityType': 'Document',
                'entityId': document_id
            }
        )
        
        # Generate policy based on decision
        effect = 'Allow' if response['decision'] == 'ALLOW' else 'Deny'
        
        return {
            'principalId': decoded_token['sub'],
            'policyDocument': {
                'Version': '2012-10-17',
                'Statement': [{
                    'Action': 'execute-api:Invoke',
                    'Effect': effect,
                    'Resource': event['methodArn']
                }]
            },
            'context': {
                'userId': decoded_token['sub'],
                'department': decoded_token.get('custom:department', ''),
                'role': decoded_token.get('custom:role', ''),
                'authDecision': response['decision']
            }
        }
        
    except Exception as e:
        print(f"Authorization error: {str(e)}")
        return {
            'principalId': 'unknown',
            'policyDocument': {
                'Version': '2012-10-17',
                'Statement': [{
                    'Action': 'execute-api:Invoke',
                    'Effect': 'Deny',
                    'Resource': event['methodArn']
                }]
            }
        }
EOF
    
    # Create requirements.txt
    cat > lambda-authorizer/requirements.txt << 'EOF'
PyJWT==2.8.0
cryptography==41.0.7
EOF
    
    # Package Lambda function
    cd lambda-authorizer
    if command -v pip3 &> /dev/null; then
        pip3 install -r requirements.txt -t .
    else
        pip install -r requirements.txt -t .
    fi
    zip -r ../authorizer-function.zip .
    cd ..
    
    # Wait for role propagation
    log "Waiting for IAM role propagation..."
    sleep 10
    
    # Create Lambda function
    AUTHORIZER_FUNCTION_ARN=$(aws lambda create-function \
        --function-name "${AUTHORIZER_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler index.lambda_handler \
        --zip-file fileb://authorizer-function.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables="{POLICY_STORE_ID=${POLICY_STORE_ID},USER_POOL_ID=${USER_POOL_ID},USER_POOL_CLIENT_ID=${USER_POOL_CLIENT_ID}}" \
        --query FunctionArn --output text)
    
    if [ -z "$AUTHORIZER_FUNCTION_ARN" ]; then
        error "Failed to create Lambda authorizer function"
        exit 1
    fi
    
    # Store function ARN in state file
    echo "AUTHORIZER_FUNCTION_ARN=${AUTHORIZER_FUNCTION_ARN}" >> .deployment-state/resources.env
    
    success "Lambda authorizer function created: ${AUTHORIZER_FUNCTION_ARN}"
}

# Create Lambda business logic function
create_lambda_business() {
    log "Creating Lambda business logic function..."
    
    # Create business logic Lambda function
    mkdir -p lambda-business
    cat > lambda-business/index.py << 'EOF'
import json
import boto3
import uuid
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DOCUMENTS_TABLE'])

def lambda_handler(event, context):
    try:
        # Extract user context from authorizer
        user_context = event['requestContext']['authorizer']
        user_id = user_context['userId']
        department = user_context['department']
        role = user_context['role']
        
        # Get HTTP method and document ID
        http_method = event['httpMethod']
        document_id = event['pathParameters'].get('documentId') if event.get('pathParameters') else None
        
        if http_method == 'GET' and document_id:
            # Retrieve specific document
            response = table.get_item(Key={'documentId': document_id})
            if 'Item' in response:
                return {
                    'statusCode': 200,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps(response['Item'])
                }
            else:
                return {
                    'statusCode': 404,
                    'body': json.dumps({'error': 'Document not found'})
                }
                
        elif http_method == 'GET':
            # List documents (simplified - in production, apply filtering)
            response = table.scan()
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(response['Items'])
            }
            
        elif http_method == 'POST':
            # Create new document
            body = json.loads(event['body'])
            document = {
                'documentId': str(uuid.uuid4()),
                'title': body['title'],
                'content': body['content'],
                'owner': user_id,
                'department': department,
                'createdAt': datetime.utcnow().isoformat(),
                'updatedAt': datetime.utcnow().isoformat()
            }
            
            table.put_item(Item=document)
            return {
                'statusCode': 201,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(document)
            }
            
        elif http_method == 'PUT' and document_id:
            # Update existing document
            body = json.loads(event['body'])
            response = table.update_item(
                Key={'documentId': document_id},
                UpdateExpression='SET title = :title, content = :content, updatedAt = :updated',
                ExpressionAttributeValues={
                    ':title': body['title'],
                    ':content': body['content'],
                    ':updated': datetime.utcnow().isoformat()
                },
                ReturnValues='ALL_NEW'
            )
            
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(response['Attributes'])
            }
            
        elif http_method == 'DELETE' and document_id:
            # Delete document
            table.delete_item(Key={'documentId': document_id})
            return {
                'statusCode': 204,
                'body': ''
            }
            
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Invalid request'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Package business logic Lambda
    cd lambda-business
    zip -r ../business-function.zip .
    cd ..
    
    # Create business logic Lambda function
    BUSINESS_FUNCTION_ARN=$(aws lambda create-function \
        --function-name "${BUSINESS_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler index.lambda_handler \
        --zip-file fileb://business-function.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables="{DOCUMENTS_TABLE=${DOCUMENTS_TABLE}}" \
        --query FunctionArn --output text)
    
    if [ -z "$BUSINESS_FUNCTION_ARN" ]; then
        error "Failed to create Lambda business function"
        exit 1
    fi
    
    # Store function ARN in state file
    echo "BUSINESS_FUNCTION_ARN=${BUSINESS_FUNCTION_ARN}" >> .deployment-state/resources.env
    
    success "Lambda business logic function created: ${BUSINESS_FUNCTION_ARN}"
}

# Create API Gateway
create_api_gateway() {
    log "Creating API Gateway..."
    
    # Create REST API
    API_ID=$(aws apigateway create-rest-api \
        --name "${API_NAME}" \
        --description "Document Management API with Verified Permissions" \
        --endpoint-configuration types=REGIONAL \
        --query id --output text)
    
    if [ -z "$API_ID" ]; then
        error "Failed to create API Gateway"
        exit 1
    fi
    
    # Get root resource ID
    ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query 'items[0].id' --output text)
    
    # Create documents resource
    DOCUMENTS_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "${API_ID}" \
        --parent-id "${ROOT_RESOURCE_ID}" \
        --path-part "documents" \
        --query id --output text)
    
    # Create document ID resource
    DOCUMENT_ID_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "${API_ID}" \
        --parent-id "${DOCUMENTS_RESOURCE_ID}" \
        --path-part "{documentId}" \
        --query id --output text)
    
    # Create custom authorizer
    AUTHORIZER_ID=$(aws apigateway create-authorizer \
        --rest-api-id "${API_ID}" \
        --name "VerifiedPermissionsAuthorizer" \
        --type TOKEN \
        --authorizer-uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${AUTHORIZER_FUNCTION_ARN}/invocations" \
        --authorizer-credentials "${LAMBDA_ROLE_ARN}" \
        --identity-source method.request.header.Authorization \
        --authorizer-result-ttl-in-seconds 300 \
        --query id --output text)
    
    # Grant API Gateway permission to invoke Lambda authorizer
    aws lambda add-permission \
        --function-name "${AUTHORIZER_FUNCTION_NAME}" \
        --statement-id "apigateway-invoke-authorizer" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/authorizers/${AUTHORIZER_ID}" || true
    
    # Store API Gateway IDs in state file
    echo "API_ID=${API_ID}" >> .deployment-state/resources.env
    echo "ROOT_RESOURCE_ID=${ROOT_RESOURCE_ID}" >> .deployment-state/resources.env
    echo "DOCUMENTS_RESOURCE_ID=${DOCUMENTS_RESOURCE_ID}" >> .deployment-state/resources.env
    echo "DOCUMENT_ID_RESOURCE_ID=${DOCUMENT_ID_RESOURCE_ID}" >> .deployment-state/resources.env
    echo "AUTHORIZER_ID=${AUTHORIZER_ID}" >> .deployment-state/resources.env
    
    success "API Gateway created: ${API_ID}"
}

# Configure API Gateway methods
configure_api_methods() {
    log "Configuring API Gateway methods..."
    
    # Create GET method for document retrieval
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${DOCUMENT_ID_RESOURCE_ID}" \
        --http-method GET \
        --authorization-type CUSTOM \
        --authorizer-id "${AUTHORIZER_ID}"
    
    # Create PUT method for document updates
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${DOCUMENT_ID_RESOURCE_ID}" \
        --http-method PUT \
        --authorization-type CUSTOM \
        --authorizer-id "${AUTHORIZER_ID}"
    
    # Create DELETE method for document deletion
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${DOCUMENT_ID_RESOURCE_ID}" \
        --http-method DELETE \
        --authorization-type CUSTOM \
        --authorizer-id "${AUTHORIZER_ID}"
    
    # Create POST method for document creation
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${DOCUMENTS_RESOURCE_ID}" \
        --http-method POST \
        --authorization-type CUSTOM \
        --authorizer-id "${AUTHORIZER_ID}"
    
    # Configure integrations for all methods
    for METHOD in GET PUT DELETE; do
        aws apigateway put-integration \
            --rest-api-id "${API_ID}" \
            --resource-id "${DOCUMENT_ID_RESOURCE_ID}" \
            --http-method "${METHOD}" \
            --type AWS_PROXY \
            --integration-http-method POST \
            --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${BUSINESS_FUNCTION_ARN}/invocations"
    done
    
    # Configure POST integration for document creation
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${DOCUMENTS_RESOURCE_ID}" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${BUSINESS_FUNCTION_ARN}/invocations"
    
    # Grant API Gateway permission to invoke business function
    aws lambda add-permission \
        --function-name "${BUSINESS_FUNCTION_NAME}" \
        --statement-id "apigateway-invoke-business" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" || true
    
    success "API Gateway methods configured"
}

# Deploy API Gateway
deploy_api_gateway() {
    log "Deploying API Gateway..."
    
    # Deploy API to production stage
    DEPLOYMENT_ID=$(aws apigateway create-deployment \
        --rest-api-id "${API_ID}" \
        --stage-name prod \
        --stage-description "Production deployment with Verified Permissions" \
        --query id --output text)
    
    API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    # Store deployment info in state file
    echo "DEPLOYMENT_ID=${DEPLOYMENT_ID}" >> .deployment-state/resources.env
    echo "API_ENDPOINT=${API_ENDPOINT}" >> .deployment-state/resources.env
    
    success "API Gateway deployed to production: ${API_ENDPOINT}"
}

# Create test users
create_test_users() {
    log "Creating test users..."
    
    # Create admin user
    aws cognito-idp admin-create-user \
        --user-pool-id "${USER_POOL_ID}" \
        --username "admin@company.com" \
        --temporary-password "TempPass123!" \
        --message-action SUPPRESS \
        --user-attributes \
            Name=email,Value="admin@company.com" \
            Name=custom:department,Value="IT" \
            Name=custom:role,Value="Admin" || true
    
    # Set permanent password for admin
    aws cognito-idp admin-set-user-password \
        --user-pool-id "${USER_POOL_ID}" \
        --username "admin@company.com" \
        --password "AdminPass123!" \
        --permanent || true
    
    # Create manager user
    aws cognito-idp admin-create-user \
        --user-pool-id "${USER_POOL_ID}" \
        --username "manager@company.com" \
        --temporary-password "TempPass123!" \
        --message-action SUPPRESS \
        --user-attributes \
            Name=email,Value="manager@company.com" \
            Name=custom:department,Value="Sales" \
            Name=custom:role,Value="Manager" || true
    
    aws cognito-idp admin-set-user-password \
        --user-pool-id "${USER_POOL_ID}" \
        --username "manager@company.com" \
        --password "ManagerPass123!" \
        --permanent || true
    
    # Create regular employee user
    aws cognito-idp admin-create-user \
        --user-pool-id "${USER_POOL_ID}" \
        --username "employee@company.com" \
        --temporary-password "TempPass123!" \
        --message-action SUPPRESS \
        --user-attributes \
            Name=email,Value="employee@company.com" \
            Name=custom:department,Value="Sales" \
            Name=custom:role,Value="Employee" || true
    
    aws cognito-idp admin-set-user-password \
        --user-pool-id "${USER_POOL_ID}" \
        --username "employee@company.com" \
        --password "EmployeePass123!" \
        --permanent || true
    
    success "Test users created successfully"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f cognito-config.json
    rm -f trust-policy.json
    rm -f lambda-policy.json
    rm -f *.cedar
    rm -f *.zip
    rm -rf lambda-authorizer
    rm -rf lambda-business
    
    success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting deployment of Fine-Grained API Authorization with Verified Permissions..."
    
    check_prerequisites
    setup_environment
    create_dynamodb_table
    create_cognito_user_pool
    create_policy_store
    create_cedar_policies
    create_lambda_role
    create_lambda_authorizer
    create_lambda_business
    create_api_gateway
    configure_api_methods
    deploy_api_gateway
    create_test_users
    cleanup_temp_files
    
    echo
    success "🎉 Deployment completed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "API Endpoint: ${API_ENDPOINT}"
    echo "User Pool ID: ${USER_POOL_ID}"
    echo "Policy Store ID: ${POLICY_STORE_ID}"
    echo
    echo "Test Users:"
    echo "- admin@company.com (Password: AdminPass123!)"
    echo "- manager@company.com (Password: ManagerPass123!)"
    echo "- employee@company.com (Password: EmployeePass123!)"
    echo
    echo "To test the API:"
    echo "1. Authenticate a user to get a token"
    echo "2. Use the token to make requests to ${API_ENDPOINT}"
    echo
    echo "Resource information saved to .deployment-state/resources.env"
    echo "Use ./destroy.sh to clean up all resources"
}

# Run main function
main "$@"