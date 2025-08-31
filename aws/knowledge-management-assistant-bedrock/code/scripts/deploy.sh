#!/bin/bash

# Knowledge Management Assistant with Bedrock Agents - Deployment Script
# This script deploys the complete infrastructure for an enterprise knowledge management assistant
# using Amazon Bedrock Agents, Knowledge Bases, S3, Lambda, and API Gateway.

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Run destroy.sh to clean up any partial deployment."
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Cleaning up partial deployment due to error..."
    # Source the destroy script to clean up any created resources
    if [[ -f "./destroy.sh" ]]; then
        bash ./destroy.sh --force
    fi
}

# Set error trap
trap cleanup_on_error ERR

# Prerequisites check function
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI version 2.x or later."
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$aws_version" | cut -d. -f1) -lt 2 ]]; then
        error_exit "AWS CLI version 2.x or later is required. Current version: $aws_version"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check required tools
    local required_tools=("jq" "curl" "zip")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error_exit "$tool is not installed. Please install $tool and try again."
        fi
    done
    
    # Check Bedrock model access
    log_info "Checking Bedrock model access..."
    if ! aws bedrock list-foundation-models --region us-east-1 &> /dev/null; then
        log_warning "Cannot verify Bedrock access. Ensure you have enabled access to Claude and Titan models."
    fi
    
    log_success "Prerequisites check completed successfully"
}

# Configuration function
configure_environment() {
    log_info "Configuring environment variables..."
    
    # Set environment variables
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error_exit "AWS region not set. Set AWS_REGION environment variable or configure default region."
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export BUCKET_NAME="knowledge-docs-${random_suffix}"
    export KB_NAME="enterprise-knowledge-base-${random_suffix}"
    export AGENT_NAME="knowledge-assistant-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="bedrock-agent-proxy-${random_suffix}"
    export API_NAME="knowledge-management-api-${random_suffix}"
    export COLLECTION_NAME="kb-collection-${random_suffix}"
    export RANDOM_SUFFIX="$random_suffix"
    
    # Create deployment state file
    cat > deployment_state.json << EOF
{
    "deployment_id": "$random_suffix",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "bucket_name": "$BUCKET_NAME",
    "kb_name": "$KB_NAME",
    "agent_name": "$AGENT_NAME",
    "lambda_function_name": "$LAMBDA_FUNCTION_NAME",
    "api_name": "$API_NAME",
    "collection_name": "$COLLECTION_NAME",
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
}
EOF
    
    log_success "Environment configured with suffix: $random_suffix"
}

# S3 bucket creation with security features
create_s3_bucket() {
    log_info "Creating S3 bucket with security features..."
    
    # Create S3 bucket
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://${BUCKET_NAME}" || error_exit "Failed to create S3 bucket"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION" || error_exit "Failed to create S3 bucket"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled || error_exit "Failed to enable S3 versioning"
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]' || error_exit "Failed to enable S3 encryption"
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" || error_exit "Failed to block public access"
    
    log_success "S3 bucket created with security features: $BUCKET_NAME"
}

# Upload sample documents
upload_sample_documents() {
    log_info "Creating and uploading sample enterprise documents..."
    
    # Create sample documents directory
    mkdir -p sample-docs
    
    # Create company policies document
    cat > sample-docs/company-policies.txt << 'EOF'
COMPANY POLICIES AND PROCEDURES

Remote Work Policy:
All employees are eligible for remote work arrangements with manager approval. Remote workers must maintain regular communication during business hours and attend quarterly in-person meetings.

Expense Reimbursement:
Business expenses must be submitted within 30 days with receipts. Meal expenses are capped at $75 per day for domestic travel and $100 for international travel.

Time Off Policy:
Employees accrue 2.5 days of PTO per month. Requests must be submitted 2 weeks in advance for planned time off.
EOF
    
    # Create technical guide document
    cat > sample-docs/technical-guide.txt << 'EOF'
TECHNICAL OPERATIONS GUIDE

Database Backup Procedures:
Daily automated backups run at 2 AM EST. Manual backups can be initiated through the admin console. Retention period is 30 days for automated backups.

Incident Response:
Priority 1: Response within 15 minutes
Priority 2: Response within 2 hours
Priority 3: Response within 24 hours

System Maintenance Windows:
Scheduled maintenance occurs first Sunday of each month from 2-6 AM EST.
EOF
    
    # Upload documents to S3
    aws s3 cp sample-docs/ "s3://${BUCKET_NAME}/documents/" --recursive || error_exit "Failed to upload sample documents"
    
    log_success "Sample enterprise documents uploaded to S3"
}

# Create IAM roles and policies
create_iam_resources() {
    log_info "Creating IAM roles and policies for Bedrock Agent..."
    
    # Create trust policy for Bedrock
    cat > bedrock-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "bedrock.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create IAM role for Bedrock Agent
    aws iam create-role \
        --role-name "BedrockAgentRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document file://bedrock-trust-policy.json || error_exit "Failed to create Bedrock IAM role"
    
    # Create S3 access policy
    cat > s3-access-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}/*",
        "arn:aws:s3:::${BUCKET_NAME}"
      ]
    }
  ]
}
EOF
    
    # Create and attach S3 access policy
    aws iam create-policy \
        --policy-name "BedrockS3Access-${RANDOM_SUFFIX}" \
        --policy-document file://s3-access-policy.json || error_exit "Failed to create S3 access policy"
    
    aws iam attach-role-policy \
        --role-name "BedrockAgentRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/BedrockS3Access-${RANDOM_SUFFIX}" || error_exit "Failed to attach S3 policy"
    
    # Create Bedrock access policy
    cat > bedrock-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:Retrieve",
        "bedrock:RetrieveAndGenerate"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    aws iam create-policy \
        --policy-name "BedrockMinimalAccess-${RANDOM_SUFFIX}" \
        --policy-document file://bedrock-policy.json || error_exit "Failed to create Bedrock policy"
    
    aws iam attach-role-policy \
        --role-name "BedrockAgentRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/BedrockMinimalAccess-${RANDOM_SUFFIX}" || error_exit "Failed to attach Bedrock policy"
    
    # Get role ARN
    export BEDROCK_ROLE_ARN=$(aws iam get-role \
        --role-name "BedrockAgentRole-${RANDOM_SUFFIX}" \
        --query Role.Arn --output text)
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
    
    log_success "IAM role created: $BEDROCK_ROLE_ARN"
}

# Create OpenSearch Serverless collection
create_opensearch_collection() {
    log_info "Creating OpenSearch Serverless collection for vector storage..."
    
    # Create collection
    aws opensearchserverless create-collection \
        --name "$COLLECTION_NAME" \
        --type VECTORSEARCH \
        --description "Vector collection for Bedrock Knowledge Base" || error_exit "Failed to create OpenSearch collection"
    
    # Wait for collection to be available
    log_info "Waiting for OpenSearch Serverless collection to be ready..."
    local max_attempts=12
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local status
        status=$(aws opensearchserverless list-collections \
            --query "collectionSummaries[?name=='$COLLECTION_NAME'].status" \
            --output text 2>/dev/null || echo "")
        
        if [[ "$status" == "ACTIVE" ]]; then
            break
        fi
        
        log_info "Collection status: $status (attempt $attempt/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        error_exit "OpenSearch collection failed to become active within expected time"
    fi
    
    # Get collection ARN
    export COLLECTION_ARN=$(aws opensearchserverless list-collections \
        --query "collectionSummaries[?name=='$COLLECTION_NAME'].arn" \
        --output text)
    
    log_success "OpenSearch Serverless collection created: $COLLECTION_ARN"
}

# Create Knowledge Base
create_knowledge_base() {
    log_info "Creating Bedrock Knowledge Base with enhanced configuration..."
    
    # Create knowledge base configuration
    cat > kb-config.json << EOF
{
  "name": "$KB_NAME",
  "description": "Enterprise knowledge base for company policies and procedures",
  "roleArn": "$BEDROCK_ROLE_ARN",
  "knowledgeBaseConfiguration": {
    "type": "VECTOR",
    "vectorKnowledgeBaseConfiguration": {
      "embeddingModelArn": "arn:aws:bedrock:${AWS_REGION}::foundation-model/amazon.titan-embed-text-v2:0"
    }
  },
  "storageConfiguration": {
    "type": "OPENSEARCH_SERVERLESS",
    "opensearchServerlessConfiguration": {
      "collectionArn": "$COLLECTION_ARN",
      "vectorIndexName": "knowledge-index",
      "fieldMapping": {
        "vectorField": "vector",
        "textField": "text",
        "metadataField": "metadata"
      }
    }
  }
}
EOF
    
    # Create knowledge base
    export KB_ID=$(aws bedrock-agent create-knowledge-base \
        --cli-input-json file://kb-config.json \
        --query knowledgeBase.knowledgeBaseId --output text) || error_exit "Failed to create knowledge base"
    
    log_success "Knowledge Base created with ID: $KB_ID"
}

# Configure S3 data source
configure_data_source() {
    log_info "Configuring S3 data source with advanced options..."
    
    # Create data source configuration
    cat > data-source-config.json << EOF
{
  "knowledgeBaseId": "$KB_ID",
  "name": "s3-document-source",
  "description": "S3 data source for enterprise documents",
  "dataSourceConfiguration": {
    "type": "S3",
    "s3Configuration": {
      "bucketArn": "arn:aws:s3:::${BUCKET_NAME}",
      "inclusionPrefixes": ["documents/"]
    }
  },
  "vectorIngestionConfiguration": {
    "chunkingConfiguration": {
      "chunkingStrategy": "FIXED_SIZE",
      "fixedSizeChunkingConfiguration": {
        "maxTokens": 300,
        "overlapPercentage": 20
      }
    }
  }
}
EOF
    
    # Create data source
    export DATA_SOURCE_ID=$(aws bedrock-agent create-data-source \
        --cli-input-json file://data-source-config.json \
        --query dataSource.dataSourceId --output text) || error_exit "Failed to create data source"
    
    # Start ingestion job
    aws bedrock-agent start-ingestion-job \
        --knowledge-base-id "$KB_ID" \
        --data-source-id "$DATA_SOURCE_ID" || error_exit "Failed to start ingestion job"
    
    log_success "Data source created and ingestion started: $DATA_SOURCE_ID"
}

# Create Bedrock Agent
create_bedrock_agent() {
    log_info "Creating Bedrock Agent with enhanced instructions..."
    
    # Create agent configuration
    cat > agent-config.json << EOF
{
  "agentName": "$AGENT_NAME",
  "description": "Enterprise knowledge management assistant powered by Claude 3.5 Sonnet",
  "instruction": "You are a helpful enterprise knowledge management assistant powered by Amazon Bedrock. Your role is to help employees find accurate information from company documents, policies, and procedures. Always provide specific, actionable answers and cite sources when possible. If you cannot find relevant information in the knowledge base, clearly state that and suggest alternative resources or contacts. Maintain a professional tone while being conversational and helpful. When providing policy information, always mention if employees should verify with HR for the most current version.",
  "foundationModel": "anthropic.claude-3-5-sonnet-20241022-v2:0",
  "agentResourceRoleArn": "$BEDROCK_ROLE_ARN",
  "idleSessionTTLInSeconds": 1800
}
EOF
    
    # Create agent
    export AGENT_ID=$(aws bedrock-agent create-agent \
        --cli-input-json file://agent-config.json \
        --query agent.agentId --output text) || error_exit "Failed to create Bedrock agent"
    
    # Associate knowledge base with agent
    aws bedrock-agent associate-agent-knowledge-base \
        --agent-id "$AGENT_ID" \
        --knowledge-base-id "$KB_ID" \
        --description "Enterprise knowledge base association" \
        --knowledge-base-state ENABLED || error_exit "Failed to associate knowledge base"
    
    # Prepare agent
    export AGENT_VERSION=$(aws bedrock-agent prepare-agent \
        --agent-id "$AGENT_ID" \
        --query agentVersion --output text) || error_exit "Failed to prepare agent"
    
    log_success "Bedrock Agent created and prepared: $AGENT_ID (Version: $AGENT_VERSION)"
}

# Create Lambda function
create_lambda_function() {
    log_info "Creating enhanced Lambda function for API integration..."
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import os
import logging
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Enhanced Lambda handler for Bedrock Agent integration
    with improved error handling and logging
    """
    # Initialize Bedrock Agent Runtime client
    bedrock_agent = boto3.client('bedrock-agent-runtime')
    
    try:
        # Parse request body with enhanced validation
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        else:
            body = event
        
        query = body.get('query', '').strip()
        session_id = body.get('sessionId', 'default-session')
        
        # Validate input
        if not query:
            logger.warning("Empty query received")
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS'
                },
                'body': json.dumps({
                    'error': 'Query parameter is required and cannot be empty'
                })
            }
        
        if len(query) > 1000:
            logger.warning(f"Query too long: {len(query)} characters")
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Query too long. Please limit to 1000 characters.'
                })
            }
        
        logger.info(f"Processing query for session: {session_id}")
        
        # Invoke Bedrock Agent with enhanced configuration
        response = bedrock_agent.invoke_agent(
            agentId=os.environ['AGENT_ID'],
            agentAliasId='TSTALIASID',
            sessionId=session_id,
            inputText=query,
            enableTrace=True
        )
        
        # Process response stream with better error handling
        response_text = ""
        trace_info = []
        
        for chunk in response['completion']:
            if 'chunk' in chunk:
                chunk_data = chunk['chunk']
                if 'bytes' in chunk_data:
                    response_text += chunk_data['bytes'].decode('utf-8')
            elif 'trace' in chunk:
                trace_info.append(chunk['trace'])
        
        logger.info(f"Successfully processed query, response length: {len(response_text)}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'POST, OPTIONS'
            },
            'body': json.dumps({
                'response': response_text,
                'sessionId': session_id,
                'timestamp': context.aws_request_id
            })
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        logger.error(f"AWS service error: {error_code} - {str(e)}")
        
        return {
            'statusCode': 503 if error_code in ['ThrottlingException', 'ServiceQuotaExceededException'] else 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': f'Service temporarily unavailable. Please try again later.',
                'requestId': context.aws_request_id
            })
        }
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Invalid JSON format in request body'
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'requestId': context.aws_request_id
            })
        }
EOF
    
    # Create deployment package
    zip lambda-deployment.zip lambda_function.py || error_exit "Failed to create Lambda deployment package"
    
    # Create Lambda execution role
    cat > lambda-trust-policy.json << 'EOF'
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
    
    aws iam create-role \
        --role-name "LambdaBedrockRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document file://lambda-trust-policy.json || error_exit "Failed to create Lambda IAM role"
    
    # Attach basic Lambda execution role
    aws iam attach-role-policy \
        --role-name "LambdaBedrockRole-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || error_exit "Failed to attach basic execution policy"
    
    # Create Lambda Bedrock policy
    cat > lambda-bedrock-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeAgent"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    aws iam create-policy \
        --policy-name "LambdaBedrockAccess-${RANDOM_SUFFIX}" \
        --policy-document file://lambda-bedrock-policy.json || error_exit "Failed to create Lambda Bedrock policy"
    
    aws iam attach-role-policy \
        --role-name "LambdaBedrockRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LambdaBedrockAccess-${RANDOM_SUFFIX}" || error_exit "Failed to attach Lambda Bedrock policy"
    
    # Get Lambda role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "LambdaBedrockRole-${RANDOM_SUFFIX}" \
        --query Role.Arn --output text)
    
    # Wait for role propagation
    log_info "Waiting for Lambda IAM role propagation..."
    sleep 10
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.12 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda-deployment.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment "Variables={AGENT_ID=${AGENT_ID}}" \
        --description "Knowledge Management Assistant API proxy" || error_exit "Failed to create Lambda function"
    
    log_success "Enhanced Lambda function created: $LAMBDA_FUNCTION_NAME"
}

# Create API Gateway
create_api_gateway() {
    log_info "Creating production-ready API Gateway..."
    
    # Create REST API
    export API_ID=$(aws apigateway create-rest-api \
        --name "$API_NAME" \
        --description "Knowledge Management Assistant API" \
        --endpoint-configuration types=REGIONAL \
        --query id --output text) || error_exit "Failed to create API Gateway"
    
    # Get root resource ID
    export ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "$API_ID" \
        --query 'items[?path==`/`].id' --output text)
    
    # Create query resource
    export QUERY_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "$API_ID" \
        --parent-id "$ROOT_RESOURCE_ID" \
        --path-part query \
        --query id --output text) || error_exit "Failed to create query resource"
    
    # Add OPTIONS method for CORS
    aws apigateway put-method \
        --rest-api-id "$API_ID" \
        --resource-id "$QUERY_RESOURCE_ID" \
        --http-method OPTIONS \
        --authorization-type NONE || error_exit "Failed to create OPTIONS method"
    
    aws apigateway put-integration \
        --rest-api-id "$API_ID" \
        --resource-id "$QUERY_RESOURCE_ID" \
        --http-method OPTIONS \
        --type MOCK \
        --request-templates '{"application/json":"{\"statusCode\": 200}"}' || error_exit "Failed to create OPTIONS integration"
    
    aws apigateway put-method-response \
        --rest-api-id "$API_ID" \
        --resource-id "$QUERY_RESOURCE_ID" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters 'method.response.header.Access-Control-Allow-Headers=false,method.response.header.Access-Control-Allow-Methods=false,method.response.header.Access-Control-Allow-Origin=false' || error_exit "Failed to create OPTIONS method response"
    
    aws apigateway put-integration-response \
        --rest-api-id "$API_ID" \
        --resource-id "$QUERY_RESOURCE_ID" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters 'method.response.header.Access-Control-Allow-Headers='"'"'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"'"',method.response.header.Access-Control-Allow-Methods='"'"'GET,POST,OPTIONS'"'"',method.response.header.Access-Control-Allow-Origin='"'"'*'"'"'' || error_exit "Failed to create OPTIONS integration response"
    
    # Create POST method
    aws apigateway put-method \
        --rest-api-id "$API_ID" \
        --resource-id "$QUERY_RESOURCE_ID" \
        --http-method POST \
        --authorization-type NONE \
        --request-models '{"application/json":"Empty"}' || error_exit "Failed to create POST method"
    
    # Get Lambda function ARN
    export LAMBDA_ARN=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query Configuration.FunctionArn --output text)
    
    # Create Lambda integration
    aws apigateway put-integration \
        --rest-api-id "$API_ID" \
        --resource-id "$QUERY_RESOURCE_ID" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" || error_exit "Failed to create Lambda integration"
    
    # Add Lambda permission
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id api-gateway-invoke \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" || error_exit "Failed to add Lambda permission"
    
    # Deploy API
    aws apigateway create-deployment \
        --rest-api-id "$API_ID" \
        --stage-name prod \
        --description "Production deployment of Knowledge Management API" || error_exit "Failed to deploy API"
    
    # Get API endpoint
    export API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    log_success "API Gateway created: $API_ENDPOINT"
}

# Wait for ingestion and test
wait_and_test() {
    log_info "Waiting for knowledge base ingestion to complete..."
    
    # Monitor ingestion job status
    local max_attempts=24  # 12 minutes total
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local status
        status=$(aws bedrock-agent list-ingestion-jobs \
            --knowledge-base-id "$KB_ID" \
            --data-source-id "$DATA_SOURCE_ID" \
            --max-results 1 \
            --query 'ingestionJobSummaries[0].status' \
            --output text 2>/dev/null || echo "")
        
        log_info "Ingestion status check $attempt/$max_attempts: $status"
        
        if [[ "$status" == "COMPLETE" ]]; then
            log_success "Ingestion completed successfully"
            break
        elif [[ "$status" == "FAILED" ]]; then
            error_exit "Ingestion failed. Check the AWS console for details."
        fi
        
        sleep 30
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_warning "Ingestion is taking longer than expected. Continuing with testing..."
    fi
    
    # Test the API
    log_info "Testing knowledge management assistant..."
    
    # Simple connectivity test
    local test_response
    test_response=$(curl -s -X POST "${API_ENDPOINT}/query" \
        -H "Content-Type: application/json" \
        -d '{
          "query": "What is our company remote work policy?",
          "sessionId": "deployment-test"
        }' || echo "curl_failed")
    
    if [[ "$test_response" == "curl_failed" ]]; then
        log_warning "API connectivity test failed. Check security groups and networking."
    else
        log_success "API connectivity test passed"
    fi
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    # Update deployment state with resource IDs
    jq ". += {
        \"kb_id\": \"$KB_ID\",
        \"agent_id\": \"$AGENT_ID\",
        \"agent_version\": \"$AGENT_VERSION\",
        \"data_source_id\": \"$DATA_SOURCE_ID\",
        \"api_id\": \"$API_ID\",
        \"api_endpoint\": \"$API_ENDPOINT\",
        \"lambda_arn\": \"$LAMBDA_ARN\",
        \"bedrock_role_arn\": \"$BEDROCK_ROLE_ARN\",
        \"lambda_role_arn\": \"$LAMBDA_ROLE_ARN\",
        \"collection_arn\": \"$COLLECTION_ARN\"
    }" deployment_state.json > deployment_state_tmp.json && mv deployment_state_tmp.json deployment_state.json
    
    # Create deployment summary
    cat > deployment_summary.txt << EOF
Knowledge Management Assistant Deployment Summary
================================================

Deployment ID: $RANDOM_SUFFIX
Region: $AWS_REGION
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)

Resources Created:
- S3 Bucket: $BUCKET_NAME
- Knowledge Base: $KB_ID
- Bedrock Agent: $AGENT_ID (Version: $AGENT_VERSION)
- Lambda Function: $LAMBDA_FUNCTION_NAME
- API Gateway: $API_ID
- OpenSearch Collection: $COLLECTION_NAME

API Endpoint: $API_ENDPOINT

Test your deployment:
curl -X POST $API_ENDPOINT/query \\
    -H "Content-Type: application/json" \\
    -d '{
      "query": "What is our company remote work policy?",
      "sessionId": "test-session"
    }'

To clean up all resources, run: ./destroy.sh
EOF
    
    log_success "Deployment information saved to deployment_summary.txt"
}

# Main deployment function
main() {
    log_info "Starting Knowledge Management Assistant deployment..."
    
    check_prerequisites
    configure_environment
    create_s3_bucket
    upload_sample_documents
    create_iam_resources
    create_opensearch_collection
    create_knowledge_base
    configure_data_source
    create_bedrock_agent
    create_lambda_function
    create_api_gateway
    wait_and_test
    save_deployment_info
    
    echo
    log_success "🎉 Knowledge Management Assistant deployment completed successfully!"
    echo
    echo -e "${GREEN}API Endpoint:${NC} $API_ENDPOINT"
    echo -e "${GREEN}Knowledge Base ID:${NC} $KB_ID"
    echo -e "${GREEN}Agent ID:${NC} $AGENT_ID"
    echo
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Review deployment_summary.txt for complete resource details"
    echo "2. Test the API using the provided curl command"
    echo "3. Upload additional documents to s3://$BUCKET_NAME/documents/"
    echo "4. Configure client applications to use the API endpoint"
    echo "5. Run ./destroy.sh when you're done to avoid ongoing charges"
    echo
}

# Run main function
main "$@"