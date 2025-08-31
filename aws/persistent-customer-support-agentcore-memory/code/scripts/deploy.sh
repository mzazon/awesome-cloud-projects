#!/bin/bash

# Deployment script for Persistent Customer Support Agent with Bedrock AgentCore Memory
# This script deploys the complete infrastructure for an AI-powered customer support system
# with persistent memory capabilities using AWS services.

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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="persistent-customer-support"
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run    Show what would be deployed without actually deploying"
            echo "  --help, -h   Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1 | cut -d. -f1)
    if [ "$AWS_CLI_VERSION" -lt 2 ]; then
        log_error "AWS CLI v2 is required. Current version: $(aws --version)"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        log_info "Please run 'aws configure' or set up your AWS credentials."
        exit 1
    fi
    
    # Check if required AWS services are available in the region
    AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region is not configured. Please set a default region."
        exit 1
    fi
    
    # Verify Bedrock AgentCore availability (preview service)
    log_warning "Bedrock AgentCore is in preview. Ensure your account has access."
    
    log_success "Prerequisites check completed successfully"
}

# Function to validate region support
validate_region_support() {
    log_info "Validating region support for required services..."
    
    # Note: This is a basic check. In production, you'd want to check actual service availability
    case "$AWS_REGION" in
        us-east-1|us-west-2|eu-west-1|ap-southeast-1)
            log_success "Region $AWS_REGION supports required services"
            ;;
        *)
            log_warning "Region $AWS_REGION may not support all required services. Proceeding with caution."
            ;;
    esac
}

# Function to generate unique resource names
generate_resource_names() {
    log_info "Generating unique resource names..."
    
    # Generate random suffix for resource uniqueness
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set resource names with project prefix
    export MEMORY_NAME="${PROJECT_NAME}-memory-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="${PROJECT_NAME}-agent-${RANDOM_SUFFIX}"
    export DDB_TABLE_NAME="${PROJECT_NAME}-customer-data-${RANDOM_SUFFIX}"
    export API_NAME="${PROJECT_NAME}-api-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="${LAMBDA_FUNCTION_NAME}-role"
    
    log_success "Resource names generated with suffix: ${RANDOM_SUFFIX}"
}

# Function to set environment variables
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=$(aws configure get region)
    
    # Save configuration for cleanup script
    cat > "${SCRIPT_DIR}/.deployment_config" << EOF
MEMORY_NAME=${MEMORY_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
DDB_TABLE_NAME=${DDB_TABLE_NAME}
API_NAME=${API_NAME}
IAM_ROLE_NAME=${IAM_ROLE_NAME}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
DEPLOYMENT_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    
    log_success "Environment variables configured"
}

# Function to create DynamoDB table
create_dynamodb_table() {
    log_info "Creating DynamoDB table: ${DDB_TABLE_NAME}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create DynamoDB table: ${DDB_TABLE_NAME}"
        return 0
    fi
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name "${DDB_TABLE_NAME}" &> /dev/null; then
        log_warning "DynamoDB table ${DDB_TABLE_NAME} already exists"
        return 0
    fi
    
    aws dynamodb create-table \
        --table-name "${DDB_TABLE_NAME}" \
        --attribute-definitions \
            AttributeName=customerId,AttributeType=S \
        --key-schema \
            AttributeName=customerId,KeyType=HASH \
        --provisioned-throughput \
            ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --tags Key=Purpose,Value=CustomerSupport Key=Project,Value="${PROJECT_NAME}"
    
    # Wait for table to be active
    log_info "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name "${DDB_TABLE_NAME}"
    
    log_success "DynamoDB table created: ${DDB_TABLE_NAME}"
}

# Function to create AgentCore Memory
create_agentcore_memory() {
    log_info "Creating Bedrock AgentCore Memory: ${MEMORY_NAME}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create AgentCore Memory: ${MEMORY_NAME}"
        export MEMORY_ID="mock-memory-id-${RANDOM_SUFFIX}"
        return 0
    fi
    
    # Create AgentCore Memory with built-in strategies
    aws bedrock-agentcore-control create-memory \
        --name "${MEMORY_NAME}" \
        --description "Customer support agent memory for ${PROJECT_NAME}" \
        --event-expiry-duration "P30D" \
        --memory-strategies '[
            {
                "summarization": {
                    "enabled": true
                }
            },
            {
                "semantic_memory": {
                    "enabled": true
                }
            },
            {
                "user_preferences": {
                    "enabled": true
                }
            }
        ]'
    
    # Wait a moment for memory to be created
    sleep 5
    
    # Get memory ID
    export MEMORY_ID=$(aws bedrock-agentcore-control get-memory \
        --name "${MEMORY_NAME}" \
        --query 'memory.memoryId' \
        --output text)
    
    if [ -z "$MEMORY_ID" ] || [ "$MEMORY_ID" = "None" ]; then
        log_error "Failed to retrieve Memory ID"
        exit 1
    fi
    
    # Save memory ID to config
    echo "MEMORY_ID=${MEMORY_ID}" >> "${SCRIPT_DIR}/.deployment_config"
    
    log_success "AgentCore Memory created with ID: ${MEMORY_ID}"
}

# Function to create IAM role and policies
create_iam_role() {
    log_info "Creating IAM role: ${IAM_ROLE_NAME}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create IAM role: ${IAM_ROLE_NAME}"
        return 0
    fi
    
    # Check if role already exists
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        log_warning "IAM role ${IAM_ROLE_NAME} already exists"
        export LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "${IAM_ROLE_NAME}" --query 'Role.Arn' --output text)
        return 0
    fi
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/trust-policy.json" << 'EOF'
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
    
    # Create IAM role
    aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document file://"${SCRIPT_DIR}/trust-policy.json" \
        --tags Key=Purpose,Value=CustomerSupport Key=Project,Value="${PROJECT_NAME}"
    
    # Create permissions policy
    cat > "${SCRIPT_DIR}/permissions-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "bedrock-agentcore:CreateEvent",
                "bedrock-agentcore:ListSessions",
                "bedrock-agentcore:ListEvents",
                "bedrock-agentcore:GetEvent",
                "bedrock-agentcore:RetrieveMemoryRecords"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel"
            ],
            "Resource": "arn:aws:bedrock:${AWS_REGION}::foundation-model/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DDB_TABLE_NAME}"
        }
    ]
}
EOF
    
    # Attach policies to role
    aws iam put-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-name SupportAgentPolicy \
        --policy-document file://"${SCRIPT_DIR}/permissions-policy.json"
    
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Wait for role to be ready
    log_info "Waiting for IAM role to be ready..."
    sleep 15
    
    # Get role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "${IAM_ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    
    log_success "IAM role created: ${LAMBDA_ROLE_ARN}"
}

# Function to create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function: ${LAMBDA_FUNCTION_NAME}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create Lambda function: ${LAMBDA_FUNCTION_NAME}"
        return 0
    fi
    
    # Check if function already exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} already exists"
        return 0
    fi
    
    # Create Lambda function code
    cat > "${SCRIPT_DIR}/lambda_function.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime

bedrock_agentcore = boto3.client('bedrock-agentcore')
bedrock_runtime = boto3.client('bedrock-runtime')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        # Parse incoming request
        body = json.loads(event['body']) if 'body' in event else event
        customer_id = body.get('customerId')
        message = body.get('message')
        session_id = body.get('sessionId', f"session-{customer_id}-{int(datetime.now().timestamp())}")
        
        # Validate input
        if not customer_id or not message:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'customerId and message are required'})
            }
        
        # Retrieve customer context from DynamoDB
        table = dynamodb.Table(os.environ['DDB_TABLE_NAME'])
        customer_data = get_customer_data(table, customer_id)
        
        # Retrieve relevant memories from AgentCore
        memory_context = retrieve_memory_context(customer_id, message)
        
        # Generate AI response using Bedrock
        ai_response = generate_support_response(message, memory_context, customer_data)
        
        # Store interaction in AgentCore Memory
        store_interaction(customer_id, session_id, message, ai_response)
        
        # Update customer data if needed
        update_customer_data(table, customer_id, body.get('metadata', {}))
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'response': ai_response,
                'sessionId': session_id,
                'customerId': customer_id
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }

def get_customer_data(table, customer_id):
    try:
        response = table.get_item(Key={'customerId': customer_id})
        return response.get('Item', {})
    except Exception as e:
        print(f"Error retrieving customer data: {e}")
        return {}

def retrieve_memory_context(customer_id, query):
    try:
        response = bedrock_agentcore.retrieve_memory_records(
            memoryId=os.environ['MEMORY_ID'],
            query=query,
            filter={'customerId': customer_id},
            maxResults=5
        )
        return [record['content'] for record in response.get('memoryRecords', [])]
    except Exception as e:
        print(f"Error retrieving memory: {e}")
        return []

def generate_support_response(message, memory_context, customer_data):
    try:
        # Prepare context for AI model
        context = f"""
Customer Support Context:
- Previous interactions: {'; '.join(memory_context) if memory_context else 'No previous interactions'}
- Customer profile: {json.dumps(customer_data) if customer_data else 'No profile data'}
- Current query: {message}

Provide a helpful, personalized response based on the customer's history and current request.
Be empathetic, professional, and reference relevant past interactions when appropriate.
Keep responses concise but comprehensive.
"""
        
        # Invoke Bedrock model
        response = bedrock_runtime.invoke_model(
            modelId='anthropic.claude-3-haiku-20240307-v1:0',
            body=json.dumps({
                'anthropic_version': 'bedrock-2023-05-31',
                'max_tokens': 500,
                'messages': [
                    {
                        'role': 'user',
                        'content': context
                    }
                ]
            })
        )
        
        result = json.loads(response['body'].read())
        return result['content'][0]['text']
        
    except Exception as e:
        print(f"Error generating response: {e}")
        return "I apologize, but I'm experiencing technical difficulties. Please try again or contact support."

def store_interaction(customer_id, session_id, user_message, agent_response):
    try:
        # Store user message
        bedrock_agentcore.create_event(
            memoryId=os.environ['MEMORY_ID'],
            sessionId=session_id,
            eventData={
                'type': 'user_message',
                'customerId': customer_id,
                'content': user_message,
                'timestamp': datetime.now().isoformat()
            }
        )
        
        # Store agent response
        bedrock_agentcore.create_event(
            memoryId=os.environ['MEMORY_ID'],
            sessionId=session_id,
            eventData={
                'type': 'agent_response',
                'customerId': customer_id,
                'content': agent_response,
                'timestamp': datetime.now().isoformat()
            }
        )
    except Exception as e:
        print(f"Error storing interaction: {e}")

def update_customer_data(table, customer_id, metadata):
    try:
        if metadata:
            table.put_item(
                Item={
                    'customerId': customer_id,
                    'lastInteraction': datetime.now().isoformat(),
                    **metadata
                }
            )
    except Exception as e:
        print(f"Error updating customer data: {e}")
EOF
    
    # Create deployment package
    cd "${SCRIPT_DIR}"
    zip -r function.zip lambda_function.py
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.11 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://function.zip \
        --timeout 30 \
        --memory-size 512 \
        --environment Variables="{
            MEMORY_ID=${MEMORY_ID},
            DDB_TABLE_NAME=${DDB_TABLE_NAME}
        }" \
        --tags Purpose=CustomerSupport,Project="${PROJECT_NAME}"
    
    log_success "Lambda function created: ${LAMBDA_FUNCTION_NAME}"
}

# Function to create API Gateway
create_api_gateway() {
    log_info "Creating API Gateway: ${API_NAME}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create API Gateway: ${API_NAME}"
        return 0
    fi
    
    # Create REST API
    export API_ID=$(aws apigateway create-rest-api \
        --name "${API_NAME}" \
        --description "Customer Support Agent API for ${PROJECT_NAME}" \
        --query 'id' --output text)
    
    # Get root resource ID
    ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query 'items[0].id' --output text)
    
    # Create support resource
    SUPPORT_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "${API_ID}" \
        --parent-id "${ROOT_RESOURCE_ID}" \
        --path-part support \
        --query 'id' --output text)
    
    # Create POST method
    aws apigateway put-method \
        --rest-api-id "${API_ID}" \
        --resource-id "${SUPPORT_RESOURCE_ID}" \
        --http-method POST \
        --authorization-type NONE
    
    # Get Lambda function ARN for integration
    LAMBDA_ARN=$(aws lambda get-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --query 'Configuration.FunctionArn' --output text)
    
    # Configure Lambda integration
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${SUPPORT_RESOURCE_ID}" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"
    
    # Add Lambda permission for API Gateway
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id api-gateway-invoke \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*"
    
    # Deploy API
    aws apigateway create-deployment \
        --rest-api-id "${API_ID}" \
        --stage-name prod
    
    # Get API endpoint
    export API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    # Save API info to config
    echo "API_ID=${API_ID}" >> "${SCRIPT_DIR}/.deployment_config"
    echo "API_ENDPOINT=${API_ENDPOINT}" >> "${SCRIPT_DIR}/.deployment_config"
    
    log_success "API Gateway created: ${API_ENDPOINT}/support"
}

# Function to configure memory extraction strategies
configure_memory_strategies() {
    log_info "Configuring memory extraction strategies"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would configure memory extraction strategies"
        return 0
    fi
    
    # Create custom memory strategy configuration
    cat > "${SCRIPT_DIR}/memory-strategy.json" << 'EOF'
{
    "custom": {
        "enabled": true,
        "systemPrompt": "Extract the following from customer support conversations: 1) Customer preferences and requirements, 2) Technical issues and their resolutions, 3) Product interests and purchasing intent, 4) Satisfaction levels and feedback. Focus on actionable insights that improve future support interactions.",
        "modelId": "anthropic.claude-3-haiku-20240307-v1:0"
    }
}
EOF
    
    # Add custom strategy to memory
    aws bedrock-agentcore-control update-memory \
        --name "${MEMORY_NAME}" \
        --add-memory-strategies file://"${SCRIPT_DIR}/memory-strategy.json"
    
    log_success "Memory extraction strategies configured"
}

# Function to populate sample data
populate_sample_data() {
    log_info "Populating sample customer data"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would populate sample customer data"
        return 0
    fi
    
    # Add sample customer data to DynamoDB
    aws dynamodb put-item \
        --table-name "${DDB_TABLE_NAME}" \
        --item '{
            "customerId": {"S": "customer-001"},
            "name": {"S": "Sarah Johnson"},
            "email": {"S": "sarah.johnson@example.com"},
            "preferredChannel": {"S": "chat"},
            "productInterests": {"SS": ["enterprise-software", "analytics"]},
            "supportTier": {"S": "premium"},
            "lastInteraction": {"S": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}
        }'
    
    aws dynamodb put-item \
        --table-name "${DDB_TABLE_NAME}" \
        --item '{
            "customerId": {"S": "customer-002"},
            "name": {"S": "Michael Chen"},
            "email": {"S": "michael.chen@example.com"},
            "preferredChannel": {"S": "email"},
            "productInterests": {"SS": ["mobile-apps", "integration"]},
            "supportTier": {"S": "standard"},
            "lastInteraction": {"S": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}
        }'
    
    log_success "Sample customer data populated"
}

# Function to run deployment validation
validate_deployment() {
    log_info "Validating deployment..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    # Test DynamoDB table
    if aws dynamodb describe-table --table-name "${DDB_TABLE_NAME}" &> /dev/null; then
        log_success "✓ DynamoDB table is accessible"
    else
        log_error "✗ DynamoDB table validation failed"
        return 1
    fi
    
    # Test Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        log_success "✓ Lambda function is accessible"
    else
        log_error "✗ Lambda function validation failed"
        return 1
    fi
    
    # Test API Gateway
    if aws apigateway get-rest-api --rest-api-id "${API_ID}" &> /dev/null; then
        log_success "✓ API Gateway is accessible"
    else
        log_error "✗ API Gateway validation failed"
        return 1
    fi
    
    # Test AgentCore Memory
    if aws bedrock-agentcore-control get-memory --name "${MEMORY_NAME}" &> /dev/null; then
        log_success "✓ AgentCore Memory is accessible"
    else
        log_error "✗ AgentCore Memory validation failed"
        return 1
    fi
    
    log_success "All components validated successfully"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=================================================="
    echo "Project: ${PROJECT_NAME}"
    echo "Region: ${AWS_REGION}"
    echo "Account: ${AWS_ACCOUNT_ID}"
    echo ""
    echo "Resources Created:"
    echo "  - AgentCore Memory: ${MEMORY_NAME}"
    echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  - DynamoDB Table: ${DDB_TABLE_NAME}"
    echo "  - API Gateway: ${API_NAME}"
    echo "  - IAM Role: ${IAM_ROLE_NAME}"
    echo ""
    if [ "$DRY_RUN" = false ]; then
        echo "API Endpoint: ${API_ENDPOINT}/support"
        echo ""
        echo "Test the deployment with:"
        echo "curl -X POST ${API_ENDPOINT}/support \\"
        echo "  -H \"Content-Type: application/json\" \\"
        echo "  -d '{\"customerId\": \"customer-001\", \"message\": \"Hello, I need help with my account\"}'"
        echo ""
        echo "Configuration saved to: ${SCRIPT_DIR}/.deployment_config"
    fi
    echo "=================================================="
}

# Function to clean up temporary files
cleanup_temp_files() {
    if [ "$DRY_RUN" = false ]; then
        rm -f "${SCRIPT_DIR}/trust-policy.json"
        rm -f "${SCRIPT_DIR}/permissions-policy.json"
        rm -f "${SCRIPT_DIR}/memory-strategy.json"
        rm -f "${SCRIPT_DIR}/lambda_function.py"
        rm -f "${SCRIPT_DIR}/function.zip"
    fi
}

# Main execution
main() {
    log_info "Starting deployment of Persistent Customer Support Agent"
    
    # Run prerequisite checks
    check_prerequisites
    validate_region_support
    
    # Generate resource names and set environment
    generate_resource_names
    set_environment_variables
    
    # Deploy infrastructure components
    create_dynamodb_table
    create_agentcore_memory
    create_iam_role
    create_lambda_function
    create_api_gateway
    configure_memory_strategies
    populate_sample_data
    
    # Validate deployment
    validate_deployment
    
    # Display summary
    display_summary
    
    # Clean up temporary files
    cleanup_temp_files
    
    if [ "$DRY_RUN" = false ]; then
        log_success "Deployment completed successfully!"
        log_info "Use './destroy.sh' to clean up resources when done testing"
    else
        log_info "Dry run completed - no resources were created"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_temp_files EXIT

# Run main function
main "$@"