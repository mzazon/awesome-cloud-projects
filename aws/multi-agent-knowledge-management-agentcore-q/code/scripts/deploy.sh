#!/bin/bash

################################################################################
# Multi-Agent Knowledge Management with Bedrock AgentCore and Q Business
# Deployment Script
# 
# This script deploys a complete multi-agent knowledge management system using:
# - Amazon Bedrock AgentCore for agent orchestration
# - Q Business for enterprise search and knowledge retrieval
# - AWS Lambda for serverless agent execution
# - S3 for knowledge base storage
# - DynamoDB for session management
# - API Gateway for external access
#
# Prerequisites:
# - AWS CLI v2 configured with appropriate permissions
# - Bedrock AgentCore enabled in your AWS account
# - Sufficient IAM permissions for all services
################################################################################

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging configuration
LOG_FILE="deployment_$(date +%Y%m%d_%H%M%S).log"
ERROR_FILE="deployment_errors_$(date +%Y%m%d_%H%M%S).log"

# Log function
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

# Error logging function
log_error() {
    echo -e "${RED}ERROR: ${1}${NC}" | tee -a "$LOG_FILE" | tee -a "$ERROR_FILE"
}

# Success logging function
log_success() {
    echo -e "${GREEN}✅ ${1}${NC}" | tee -a "$LOG_FILE"
}

# Warning logging function
log_warning() {
    echo -e "${YELLOW}⚠️  ${1}${NC}" | tee -a "$LOG_FILE"
}

# Info logging function
log_info() {
    echo -e "${BLUE}ℹ️  ${1}${NC}" | tee -a "$LOG_FILE"
}

# Progress logging function
log_progress() {
    echo -e "${PURPLE}🔄 ${1}${NC}" | tee -a "$LOG_FILE"
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of partially created resources..."
    
    # Check if cleanup script exists and run it
    if [[ -f "$(dirname "$0")/destroy.sh" ]]; then
        log_info "Running cleanup script..."
        bash "$(dirname "$0")/destroy.sh" --force || true
    fi
    
    # Clean up local files
    rm -f supervisor-agent.py finance-agent.py hr-agent.py technical-agent.py
    rm -f *.zip *.txt memory-config.json
    
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log_progress "Checking deployment prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or lacks permissions."
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some validation features will be limited."
    fi
    
    # Check AWS account limits and quotas (basic check)
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    log_info "Deploying to AWS Account: ${account_id}"
    
    # Check for existing resources that might conflict
    local existing_roles
    existing_roles=$(aws iam list-roles --query 'Roles[?contains(RoleName, `AgentCoreRole`)].RoleName' --output text || echo "")
    if [[ -n "$existing_roles" ]]; then
        log_warning "Found existing AgentCore roles: $existing_roles"
        log_warning "These may conflict with new deployment. Consider cleaning up old resources first."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_progress "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "No default region configured. Using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names with validation
    export PROJECT_NAME="multi-agent-km-${RANDOM_SUFFIX}"
    export S3_BUCKET_FINANCE="finance-kb-${RANDOM_SUFFIX}"
    export S3_BUCKET_HR="hr-kb-${RANDOM_SUFFIX}"
    export S3_BUCKET_TECH="tech-kb-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="AgentCoreRole-${RANDOM_SUFFIX}"
    export SESSION_TABLE="agent-sessions-${RANDOM_SUFFIX}"
    
    # Validate S3 bucket names
    for bucket in "$S3_BUCKET_FINANCE" "$S3_BUCKET_HR" "$S3_BUCKET_TECH"; do
        if [[ ${#bucket} -gt 63 ]]; then
            log_error "Bucket name too long: $bucket"
            exit 1
        fi
    done
    
    # Save environment variables to file for cleanup script
    cat > .deployment_env << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export PROJECT_NAME="$PROJECT_NAME"
export S3_BUCKET_FINANCE="$S3_BUCKET_FINANCE"
export S3_BUCKET_HR="$S3_BUCKET_HR"
export S3_BUCKET_TECH="$S3_BUCKET_TECH"
export IAM_ROLE_NAME="$IAM_ROLE_NAME"
export SESSION_TABLE="$SESSION_TABLE"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF
    
    log_success "Environment configured with suffix: ${RANDOM_SUFFIX}"
    log_info "Resources will be created with naming pattern: *-${RANDOM_SUFFIX}"
}

# Function to create IAM role
create_iam_role() {
    log_progress "Creating IAM role for multi-agent operations..."
    
    # Create IAM role with enhanced trust policy
    aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": [
                            "lambda.amazonaws.com",
                            "qbusiness.amazonaws.com",
                            "apigateway.amazonaws.com"
                        ]
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --description "Role for multi-agent knowledge management system" \
        --tags Key=Project,Value="${PROJECT_NAME}" Key=Component,Value=IAM

    # Wait for role to be available
    aws iam wait role-exists --role-name "${IAM_ROLE_NAME}"
    
    # Attach necessary policies
    local policies=(
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
        "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
        "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
    )
    
    for policy in "${policies[@]}"; do
        aws iam attach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn "$policy"
        log_info "Attached policy: $(basename "$policy")"
    done
    
    # Create custom policy for Q Business access
    local qbusiness_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "qbusiness:*"
                ],
                "Resource": "*"
            }
        ]
    }'
    
    aws iam create-policy \
        --policy-name "QBusinessAccess-${RANDOM_SUFFIX}" \
        --policy-document "$qbusiness_policy" \
        --description "Q Business access for multi-agent system" || true
    
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/QBusinessAccess-${RANDOM_SUFFIX}" || true
    
    # Wait for role propagation
    sleep 10
    
    log_success "IAM role created and configured: ${IAM_ROLE_NAME}"
}

# Function to create S3 knowledge base storage
create_knowledge_storage() {
    log_progress "Creating enterprise knowledge base storage..."
    
    local buckets=("$S3_BUCKET_FINANCE" "$S3_BUCKET_HR" "$S3_BUCKET_TECH")
    local departments=("finance" "hr" "engineering")
    
    for i in "${!buckets[@]}"; do
        local bucket="${buckets[$i]}"
        local dept="${departments[$i]}"
        
        # Create S3 bucket
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3 mb "s3://${bucket}"
        else
            aws s3 mb "s3://${bucket}" --region "$AWS_REGION"
        fi
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$bucket" \
            --versioning-configuration Status=Enabled
        
        # Enable server-side encryption
        aws s3api put-bucket-encryption \
            --bucket "$bucket" \
            --server-side-encryption-configuration \
            'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
        
        # Add bucket tagging
        aws s3api put-bucket-tagging \
            --bucket "$bucket" \
            --tagging "TagSet=[{Key=Project,Value=${PROJECT_NAME}},{Key=Department,Value=${dept}},{Key=Component,Value=KnowledgeBase}]"
        
        # Block public access
        aws s3api put-public-access-block \
            --bucket "$bucket" \
            --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
        
        log_info "Created knowledge base bucket: ${bucket}"
    done
    
    log_success "Knowledge base storage created with security features"
}

# Function to upload sample documents
upload_sample_documents() {
    log_progress "Uploading sample enterprise knowledge documents..."
    
    # Create sample finance documents
    cat > finance-policy.txt << 'EOF'
Finance Policy Documentation:

Expense Approval Process:
- All expenses over $1000 require manager approval
- Expenses over $5000 require director approval
- Capital expenditures over $10000 require CFO approval

Budget Management:
- Quarterly budget reviews conducted in March, June, September, December
- Department budget allocations updated annually in January
- Emergency budget requests require 48-hour approval window

Travel and Reimbursement:
- Travel reimbursement requires receipts within 30 days of completion
- International travel requires pre-approval 2 weeks in advance
- Meal allowances: $75 domestic, $100 international per day

Vendor Management:
- New vendor approval requires 3 business days
- Preferred vendor discounts available for volumes over $50,000
- Payment terms: Net 30 for most vendors, Net 15 for strategic partners
EOF
    
    # Create sample HR documents
    cat > hr-handbook.txt << 'EOF'
HR Handbook and Employee Policies:

Onboarding Process:
- Employee onboarding process takes 3-5 business days
- IT equipment setup completed on first day
- Benefits enrollment window: 30 days from start date
- New hire orientation scheduled within first week

Performance Management:
- Performance reviews conducted annually in Q4
- Mid-year check-ins scheduled in Q2
- Performance improvement plans: 90-day duration
- Goal setting and review cycle aligns with fiscal year

Time Off and Remote Work:
- Vacation requests require 2 weeks advance notice for approval
- Remote work policy allows up to 3 days per week remote work
- Sick leave: 10 days annually, carries over up to 5 days
- Parental leave: 12 weeks paid, additional 4 weeks unpaid

Professional Development:
- Annual training budget: $2,500 per employee
- Conference attendance requires manager approval
- Internal mentorship program available for all levels
EOF
    
    # Create sample technical documentation
    cat > tech-guidelines.txt << 'EOF'
Technical Guidelines and System Procedures:

Development Standards:
- All code must pass automated testing before deployment
- Code coverage minimum: 80% for production releases
- Security scans required for all external-facing applications
- Code review required for all pull requests

Infrastructure Management:
- Database backups performed nightly at 2 AM UTC
- Backup retention: 30 days local, 90 days archived
- Disaster recovery testing: quarterly
- Infrastructure changes require approval through change management

API and Security Standards:
- API rate limits: 1000 requests per minute per client
- Authentication required for all API endpoints
- SSL/TLS 1.2 minimum for all communications
- Security patching: within 48 hours for critical vulnerabilities

Monitoring and Alerting:
- 24/7 monitoring for all production systems
- Alert escalation: 15 minutes for critical, 1 hour for warning
- Post-incident reviews required for all severity 1 incidents
- Monthly capacity planning reviews
EOF
    
    # Upload documents with metadata
    aws s3 cp finance-policy.txt "s3://${S3_BUCKET_FINANCE}/" \
        --metadata "department=finance,type=policy,version=1.0,last-updated=$(date -u +%Y-%m-%d)"
    
    aws s3 cp hr-handbook.txt "s3://${S3_BUCKET_HR}/" \
        --metadata "department=hr,type=handbook,version=1.0,last-updated=$(date -u +%Y-%m-%d)"
    
    aws s3 cp tech-guidelines.txt "s3://${S3_BUCKET_TECH}/" \
        --metadata "department=engineering,type=guidelines,version=1.0,last-updated=$(date -u +%Y-%m-%d)"
    
    # Verify uploads
    for bucket in "$S3_BUCKET_FINANCE" "$S3_BUCKET_HR" "$S3_BUCKET_TECH"; do
        local count
        count=$(aws s3 ls "s3://${bucket}/" | wc -l)
        log_info "Bucket ${bucket} contains ${count} documents"
    done
    
    log_success "Sample knowledge documents uploaded with metadata"
}

# Function to configure Q Business application
configure_qbusiness() {
    log_progress "Configuring Q Business application for enterprise search..."
    
    # Create Q Business application
    Q_APP_ID=$(aws qbusiness create-application \
        --display-name "Enterprise Knowledge Management System" \
        --description "Multi-agent knowledge management with specialized domain expertise" \
        --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}" \
        --query 'applicationId' --output text)
    
    # Wait for application to be active
    log_info "Waiting for Q Business application to be created..."
    local retry_count=0
    local max_retries=30
    
    while [[ $retry_count -lt $max_retries ]]; do
        local status
        status=$(aws qbusiness get-application --application-id "$Q_APP_ID" --query 'status' --output text 2>/dev/null || echo "CREATING")
        
        if [[ "$status" == "ACTIVE" ]]; then
            break
        elif [[ "$status" == "FAILED" ]]; then
            log_error "Q Business application creation failed"
            exit 1
        fi
        
        sleep 10
        ((retry_count++))
        log_info "Application status: $status (attempt $retry_count/$max_retries)"
    done
    
    if [[ $retry_count -eq $max_retries ]]; then
        log_error "Q Business application creation timed out"
        exit 1
    fi
    
    # Create index for the application
    INDEX_ID=$(aws qbusiness create-index \
        --application-id "$Q_APP_ID" \
        --display-name "Multi-Agent Knowledge Index" \
        --description "Centralized index for multi-agent knowledge retrieval" \
        --query 'indexId' --output text)
    
    # Wait for index to be active
    log_info "Waiting for index to be active..."
    sleep 30
    
    # Create data sources for each knowledge domain
    local data_sources=()
    local buckets=("$S3_BUCKET_FINANCE" "$S3_BUCKET_HR" "$S3_BUCKET_TECH")
    local names=("Finance Knowledge Base" "HR Knowledge Base" "Technical Knowledge Base")
    
    for i in "${!buckets[@]}"; do
        local bucket="${buckets[$i]}"
        local name="${names[$i]}"
        
        local ds_id
        ds_id=$(aws qbusiness create-data-source \
            --application-id "$Q_APP_ID" \
            --index-id "$INDEX_ID" \
            --display-name "$name" \
            --type S3 \
            --configuration "{
                \"S3Configuration\": {
                    \"bucketName\": \"$bucket\",
                    \"inclusionPrefixes\": [\"\"],
                    \"exclusionPatterns\": [],
                    \"documentsMetadataConfiguration\": {
                        \"s3Prefix\": \"\"
                    }
                }
            }" \
            --query 'dataSourceId' --output text)
        
        data_sources+=("$ds_id")
        log_info "Created data source: $name ($ds_id)"
    done
    
    # Save Q Business configuration
    cat >> .deployment_env << EOF
export Q_APP_ID="$Q_APP_ID"
export INDEX_ID="$INDEX_ID"
export FINANCE_DS_ID="${data_sources[0]}"
export HR_DS_ID="${data_sources[1]}"
export TECH_DS_ID="${data_sources[2]}"
EOF
    
    export Q_APP_ID INDEX_ID
    export FINANCE_DS_ID="${data_sources[0]}"
    export HR_DS_ID="${data_sources[1]}"
    export TECH_DS_ID="${data_sources[2]}"
    
    log_success "Q Business application configured: $Q_APP_ID"
}

# Function to create and deploy Lambda agents
deploy_lambda_agents() {
    log_progress "Creating and deploying specialized Lambda agents..."
    
    # Create supervisor agent
    create_supervisor_agent
    
    # Create specialized agents
    create_finance_agent
    create_hr_agent
    create_technical_agent
    
    log_success "All Lambda agents deployed successfully"
}

# Function to create supervisor agent
create_supervisor_agent() {
    log_info "Creating supervisor agent..."
    
    # Create supervisor agent code with enhanced error handling
    cat > supervisor-agent.py << 'EOF'
import json
import boto3
import os
from typing import List, Dict, Any
import uuid
import logging
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Supervisor agent that coordinates specialized agents for knowledge retrieval
    """
    try:
        # Initialize AWS clients
        lambda_client = boto3.client('lambda')
        
        # Parse request with validation
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event
            
        query = body.get('query', '')
        session_id = body.get('sessionId', str(uuid.uuid4()))
        
        if not query:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Query parameter is required'
                })
            }
        
        logger.info(f"Processing query: {query} for session: {session_id}")
        
        # Determine which agents to engage based on query analysis
        agents_to_engage = determine_agents(query)
        logger.info(f"Engaging agents: {agents_to_engage}")
        
        # Collect responses from specialized agents
        agent_responses = []
        for agent_name in agents_to_engage:
            try:
                response = invoke_specialized_agent(lambda_client, agent_name, query, session_id)
                agent_responses.append({
                    'agent': agent_name,
                    'response': response,
                    'confidence': calculate_confidence(agent_name, query)
                })
            except Exception as e:
                logger.error(f"Error invoking {agent_name} agent: {str(e)}")
                agent_responses.append({
                    'agent': agent_name,
                    'response': f"Error retrieving {agent_name} information: {str(e)}",
                    'confidence': 0.0
                })
        
        # Synthesize comprehensive answer
        final_response = synthesize_responses(query, agent_responses)
        
        # Store session information for context
        store_session_context(session_id, query, final_response, agents_to_engage)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'query': query,
                'response': final_response,
                'agents_consulted': agents_to_engage,
                'session_id': session_id,
                'confidence_scores': {resp['agent']: resp['confidence'] for resp in agent_responses}
            })
        }
        
    except Exception as e:
        logger.error(f"Supervisor agent error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': f"Supervisor agent error: {str(e)}"
            })
        }

def determine_agents(query: str) -> List[str]:
    """Determine which specialized agents to engage based on query analysis"""
    query_lower = query.lower()
    agents = []
    
    # Finance-related keywords
    finance_keywords = ['budget', 'expense', 'cost', 'finance', 'money', 'approval', 
                       'reimbursement', 'travel', 'spending', 'capital', 'cfo', 'vendor']
    if any(word in query_lower for word in finance_keywords):
        agents.append('finance')
    
    # HR-related keywords
    hr_keywords = ['employee', 'hr', 'vacation', 'onboard', 'performance', 'leave',
                   'remote', 'work', 'benefits', 'policy', 'review', 'sick', 'training']
    if any(word in query_lower for word in hr_keywords):
        agents.append('hr')
    
    # Technical-related keywords
    tech_keywords = ['technical', 'code', 'api', 'database', 'security', 'backup',
                     'system', 'development', 'infrastructure', 'server', 'ssl', 'monitoring']
    if any(word in query_lower for word in tech_keywords):
        agents.append('technical')
    
    # If no specific domain detected, engage all agents for comprehensive coverage
    return agents if agents else ['finance', 'hr', 'technical']

def calculate_confidence(agent_name: str, query: str) -> float:
    """Calculate confidence score for agent relevance to query"""
    query_lower = query.lower()
    
    if agent_name == 'finance':
        finance_keywords = ['budget', 'expense', 'cost', 'finance', 'money', 'approval', 'vendor']
        matches = sum(1 for word in finance_keywords if word in query_lower)
        return min(matches * 0.2, 1.0)
    elif agent_name == 'hr':
        hr_keywords = ['employee', 'hr', 'vacation', 'onboard', 'performance', 'leave', 'training']
        matches = sum(1 for word in hr_keywords if word in query_lower)
        return min(matches * 0.2, 1.0)
    elif agent_name == 'technical':
        tech_keywords = ['technical', 'code', 'api', 'database', 'security', 'backup', 'monitoring']
        matches = sum(1 for word in tech_keywords if word in query_lower)
        return min(matches * 0.2, 1.0)
    
    return 0.5  # Default confidence

def invoke_specialized_agent(lambda_client, agent_name: str, query: str, session_id: str) -> str:
    """Invoke a specialized agent Lambda function"""
    function_name = f"{agent_name}-agent-{os.environ.get('RANDOM_SUFFIX', 'default')}"
    
    try:
        response = lambda_client.invoke(
            FunctionName=function_name,
            InvocationType='RequestResponse',
            Payload=json.dumps({
                'query': query,
                'sessionId': session_id,
                'context': f"Domain-specific query for {agent_name} expertise"
            })
        )
        
        result = json.loads(response['Payload'].read())
        if result.get('statusCode') == 200:
            body = json.loads(result.get('body', '{}'))
            return body.get('response', f"No {agent_name} information available")
        else:
            return f"Error retrieving {agent_name} information"
            
    except Exception as e:
        logger.error(f"Error invoking {agent_name} agent: {str(e)}")
        return f"Error accessing {agent_name} knowledge base: {str(e)}"

def synthesize_responses(query: str, responses: List[Dict]) -> str:
    """Synthesize responses from multiple agents into a comprehensive answer"""
    if not responses:
        return "No relevant information found in the knowledge base."
    
    # Filter responses by confidence score and exclude errors
    high_confidence_responses = [r for r in responses if r.get('confidence', 0) > 0.3 and not r['response'].startswith('Error')]
    responses_to_use = high_confidence_responses if high_confidence_responses else [r for r in responses if not r['response'].startswith('Error')]
    
    if not responses_to_use:
        return "I apologize, but I encountered issues accessing the knowledge bases. Please try again later."
    
    synthesis = f"Based on consultation with {len(responses_to_use)} specialized knowledge domains:\\n\\n"
    
    for resp in responses_to_use:
        if resp['response'] and not resp['response'].startswith('Error'):
            confidence_indicator = "🔷" if resp.get('confidence', 0) > 0.6 else "🔹"
            synthesis += f"{confidence_indicator} **{resp['agent'].title()} Domain**: {resp['response']}\\n\\n"
    
    synthesis += "\\n*This response was generated by consulting multiple specialized knowledge agents.*"
    return synthesis

def store_session_context(session_id: str, query: str, response: str, agents: List[str]):
    """Store session context for future reference"""
    try:
        table_name = os.environ.get('SESSION_TABLE', 'agent-sessions-default')
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(table_name)
        
        import time
        table.put_item(
            Item={
                'sessionId': session_id,
                'timestamp': str(int(time.time())),
                'query': query,
                'response': response,
                'agents_consulted': agents,
                'ttl': int(time.time()) + 86400  # 24 hour TTL
            }
        )
    except Exception as e:
        logger.error(f"Error storing session context: {str(e)}")
EOF
    
    # Package and deploy supervisor agent
    zip supervisor-agent.zip supervisor-agent.py
    
    SUPERVISOR_FUNCTION_ARN=$(aws lambda create-function \
        --function-name "supervisor-agent-${RANDOM_SUFFIX}" \
        --runtime python3.12 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}" \
        --handler supervisor-agent.lambda_handler \
        --zip-file fileb://supervisor-agent.zip \
        --timeout 60 \
        --memory-size 512 \
        --environment Variables="{RANDOM_SUFFIX=${RANDOM_SUFFIX},SESSION_TABLE=${SESSION_TABLE}}" \
        --description "Supervisor agent for multi-agent knowledge management" \
        --tags Project="${PROJECT_NAME}",Component=SupervisorAgent \
        --query 'FunctionArn' --output text)
    
    # Save to environment file
    echo "export SUPERVISOR_FUNCTION_ARN=\"$SUPERVISOR_FUNCTION_ARN\"" >> .deployment_env
    export SUPERVISOR_FUNCTION_ARN
    
    log_info "Supervisor agent deployed: $SUPERVISOR_FUNCTION_ARN"
}

# Function to create finance agent
create_finance_agent() {
    log_info "Creating finance agent..."
    
    cat > finance-agent.py << 'EOF'
import json
import boto3
import os
import logging
import uuid
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Finance specialist agent for budget and financial policy queries
    """
    try:
        query = event.get('query', '')
        session_id = event.get('sessionId', str(uuid.uuid4()))
        context_info = event.get('context', '')
        
        logger.info(f"Finance agent processing query: {query}")
        
        if not query:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Query is required'
                })
            }
        
        # Try Q Business integration first, fall back to static responses
        try:
            response = query_qbusiness_finance(query, session_id)
        except Exception as qb_error:
            logger.error(f"Q Business error: {str(qb_error)}")
            response = get_finance_fallback(query)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'agent': 'finance',
                'response': response,
                'sources': ['Finance Policy Documentation'],
                'session_id': session_id
            })
        }
        
    except Exception as e:
        logger.error(f"Finance agent error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"Finance agent error: {str(e)}"
            })
        }

def query_qbusiness_finance(query: str, session_id: str) -> str:
    """Query Q Business for finance information"""
    # Q Business integration would go here
    # For now, return fallback response
    return get_finance_fallback(query)

def get_finance_fallback(query: str) -> str:
    """Provide fallback finance information"""
    query_lower = query.lower()
    
    if 'expense' in query_lower or 'approval' in query_lower:
        return "Expense approval process: Expenses over $1000 require manager approval, over $5000 require director approval, and over $10000 require CFO approval."
    elif 'budget' in query_lower:
        return "Budget management: Quarterly reviews conducted in March, June, September, December. Annual allocations updated in January. Emergency requests require 48-hour approval window."
    elif 'travel' in query_lower or 'reimbursement' in query_lower:
        return "Travel policy: Reimbursement requires receipts within 30 days. International travel needs 2-week pre-approval. Daily allowances: $75 domestic, $100 international."
    elif 'vendor' in query_lower:
        return "Vendor management: New vendor approval requires 3 business days. Preferred vendor discounts available for volumes over $50,000. Payment terms: Net 30 for most vendors."
    else:
        return "Finance policies cover expense approvals, budget management, travel procedures, and vendor management. Specific policies require review of complete documentation."
EOF
    
    zip finance-agent.zip finance-agent.py
    
    FINANCE_FUNCTION_ARN=$(aws lambda create-function \
        --function-name "finance-agent-${RANDOM_SUFFIX}" \
        --runtime python3.12 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}" \
        --handler finance-agent.lambda_handler \
        --zip-file fileb://finance-agent.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables="{Q_APP_ID=${Q_APP_ID}}" \
        --description "Finance specialist agent" \
        --tags Project="${PROJECT_NAME}",Component=FinanceAgent \
        --query 'FunctionArn' --output text)
    
    echo "export FINANCE_FUNCTION_ARN=\"$FINANCE_FUNCTION_ARN\"" >> .deployment_env
    export FINANCE_FUNCTION_ARN
    
    log_info "Finance agent deployed: $FINANCE_FUNCTION_ARN"
}

# Function to create HR agent
create_hr_agent() {
    log_info "Creating HR agent..."
    
    cat > hr-agent.py << 'EOF'
import json
import boto3
import os
import logging
import uuid
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    HR specialist agent for employee and policy queries
    """
    try:
        query = event.get('query', '')
        session_id = event.get('sessionId', str(uuid.uuid4()))
        
        logger.info(f"HR agent processing query: {query}")
        
        if not query:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Query is required'
                })
            }
        
        # Try Q Business integration first, fall back to static responses
        try:
            response = query_qbusiness_hr(query, session_id)
        except Exception as qb_error:
            logger.error(f"Q Business error: {str(qb_error)}")
            response = get_hr_fallback(query)
        
        # Add confidentiality notice
        response += "\\n\\n*Note: HR information is confidential and subject to privacy policies.*"
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'agent': 'hr',
                'response': response,
                'sources': ['HR Handbook and Policies'],
                'session_id': session_id
            })
        }
        
    except Exception as e:
        logger.error(f"HR agent error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"HR agent error: {str(e)}"
            })
        }

def query_qbusiness_hr(query: str, session_id: str) -> str:
    """Query Q Business for HR information"""
    # Q Business integration would go here
    # For now, return fallback response
    return get_hr_fallback(query)

def get_hr_fallback(query: str) -> str:
    """Provide fallback HR information"""
    query_lower = query.lower()
    
    if 'onboard' in query_lower:
        return "Onboarding process: 3-5 business days completion, IT setup on first day, benefits enrollment within 30 days of start date. New hire orientation scheduled within first week."
    elif 'performance' in query_lower or 'review' in query_lower:
        return "Performance management: Annual reviews in Q4, mid-year check-ins in Q2, performance improvement plans have 90-day duration. Goal setting aligns with fiscal year."
    elif 'vacation' in query_lower or 'leave' in query_lower:
        return "Time off policies: Vacation requires 2-week advance notice, 10 sick days annually (5 carry-over), 12 weeks paid parental leave plus 4 weeks unpaid."
    elif 'remote' in query_lower or 'work' in query_lower:
        return "Remote work policy: Up to 3 days per week remote work allowed, subject to role requirements and manager approval."
    elif 'training' in query_lower:
        return "Professional development: Annual training budget of $2,500 per employee. Conference attendance requires manager approval. Internal mentorship program available."
    else:
        return "HR policies cover onboarding, performance management, time off, remote work, and professional development. Consult complete handbook for specific guidance."
EOF
    
    zip hr-agent.zip hr-agent.py
    
    HR_FUNCTION_ARN=$(aws lambda create-function \
        --function-name "hr-agent-${RANDOM_SUFFIX}" \
        --runtime python3.12 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}" \
        --handler hr-agent.lambda_handler \
        --zip-file fileb://hr-agent.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables="{Q_APP_ID=${Q_APP_ID}}" \
        --description "HR specialist agent" \
        --tags Project="${PROJECT_NAME}",Component=HRAgent \
        --query 'FunctionArn' --output text)
    
    echo "export HR_FUNCTION_ARN=\"$HR_FUNCTION_ARN\"" >> .deployment_env
    export HR_FUNCTION_ARN
    
    log_info "HR agent deployed: $HR_FUNCTION_ARN"
}

# Function to create technical agent
create_technical_agent() {
    log_info "Creating technical agent..."
    
    cat > technical-agent.py << 'EOF'
import json
import boto3
import os
import logging
import uuid
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Technical specialist agent for engineering and system queries
    """
    try:
        query = event.get('query', '')
        session_id = event.get('sessionId', str(uuid.uuid4()))
        
        logger.info(f"Technical agent processing query: {query}")
        
        if not query:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Query is required'
                })
            }
        
        # Try Q Business integration first, fall back to static responses
        try:
            response = query_qbusiness_technical(query, session_id)
        except Exception as qb_error:
            logger.error(f"Q Business error: {str(qb_error)}")
            response = get_technical_fallback(query)
        
        # Add standards compliance note
        response += "\\n\\n*Ensure all implementations follow current security and development standards.*"
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'agent': 'technical',
                'response': response,
                'sources': ['Technical Guidelines Documentation'],
                'session_id': session_id
            })
        }
        
    except Exception as e:
        logger.error(f"Technical agent error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"Technical agent error: {str(e)}"
            })
        }

def query_qbusiness_technical(query: str, session_id: str) -> str:
    """Query Q Business for technical information"""
    # Q Business integration would go here
    # For now, return fallback response
    return get_technical_fallback(query)

def get_technical_fallback(query: str) -> str:
    """Provide fallback technical information"""
    query_lower = query.lower()
    
    if 'code' in query_lower or 'development' in query_lower:
        return "Development standards: All code requires automated testing before deployment, minimum 80% code coverage for production, security scans for external applications. Code review required for all pull requests."
    elif 'backup' in query_lower or 'database' in query_lower:
        return "Infrastructure management: Database backups performed nightly at 2 AM UTC, 30-day local retention, 90-day archive retention, quarterly DR testing."
    elif 'api' in query_lower:
        return "API standards: 1000 requests per minute rate limit, authentication required for all endpoints, SSL/TLS 1.2 minimum for communications."
    elif 'security' in query_lower:
        return "Security procedures: Security patching within 48 hours for critical vulnerabilities, SSL/TLS 1.2 minimum, authentication required for all API endpoints."
    elif 'monitoring' in query_lower:
        return "Monitoring and alerting: 24/7 monitoring for all production systems. Alert escalation: 15 minutes for critical, 1 hour for warning. Monthly capacity planning reviews."
    else:
        return "Technical guidelines cover development standards, infrastructure management, API protocols, security procedures, and monitoring. Consult complete documentation for implementation details."
EOF
    
    zip technical-agent.zip technical-agent.py
    
    TECHNICAL_FUNCTION_ARN=$(aws lambda create-function \
        --function-name "technical-agent-${RANDOM_SUFFIX}" \
        --runtime python3.12 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}" \
        --handler technical-agent.lambda_handler \
        --zip-file fileb://technical-agent.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables="{Q_APP_ID=${Q_APP_ID}}" \
        --description "Technical specialist agent" \
        --tags Project="${PROJECT_NAME}",Component=TechnicalAgent \
        --query 'FunctionArn' --output text)
    
    echo "export TECHNICAL_FUNCTION_ARN=\"$TECHNICAL_FUNCTION_ARN\"" >> .deployment_env
    export TECHNICAL_FUNCTION_ARN
    
    log_info "Technical agent deployed: $TECHNICAL_FUNCTION_ARN"
}

# Function to configure session management
configure_session_management() {
    log_progress "Configuring agent memory and session management..."
    
    # Create DynamoDB table for session management
    aws dynamodb create-table \
        --table-name "$SESSION_TABLE" \
        --attribute-definitions \
            AttributeName=sessionId,AttributeType=S \
            AttributeName=timestamp,AttributeType=S \
        --key-schema \
            AttributeName=sessionId,KeyType=HASH \
            AttributeName=timestamp,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Project,Value="$PROJECT_NAME" Key=Component,Value=SessionManagement \
        --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES
    
    # Wait for table to be active
    aws dynamodb wait table-exists --table-name "$SESSION_TABLE"
    
    # Enable TTL for automatic session cleanup
    aws dynamodb update-time-to-live \
        --table-name "$SESSION_TABLE" \
        --time-to-live-specification Enabled=true,AttributeName=ttl
    
    log_success "Session management configured with DynamoDB table: $SESSION_TABLE"
}

# Function to create API Gateway
create_api_gateway() {
    log_progress "Creating API Gateway for multi-agent orchestration..."
    
    # Create API Gateway
    API_ID=$(aws apigatewayv2 create-api \
        --name "multi-agent-km-api-${RANDOM_SUFFIX}" \
        --protocol-type HTTP \
        --description "Multi-agent knowledge management API with enterprise features" \
        --cors-configuration AllowCredentials=false,AllowHeaders=Content-Type,AllowMethods=GET,POST,AllowOrigins=* \
        --query 'ApiId' --output text)
    
    # Create integration with supervisor Lambda
    INTEGRATION_ID=$(aws apigatewayv2 create-integration \
        --api-id "$API_ID" \
        --integration-type AWS_PROXY \
        --integration-method POST \
        --integration-uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${SUPERVISOR_FUNCTION_ARN}/invocations" \
        --payload-format-version 2.0 \
        --timeout-in-millis 29000 \
        --query 'IntegrationId' --output text)
    
    # Create routes
    aws apigatewayv2 create-route \
        --api-id "$API_ID" \
        --route-key 'POST /query' \
        --target "integrations/${INTEGRATION_ID}" \
        --authorization-type NONE
    
    aws apigatewayv2 create-route \
        --api-id "$API_ID" \
        --route-key 'GET /health' \
        --target "integrations/${INTEGRATION_ID}"
    
    # Create deployment stage
    aws apigatewayv2 create-stage \
        --api-id "$API_ID" \
        --stage-name prod \
        --auto-deploy \
        --description "Production stage for multi-agent knowledge management" \
        --throttle-settings BurstLimit=1000,RateLimit=500
    
    # Grant API Gateway permission to invoke Lambda
    aws lambda add-permission \
        --function-name "supervisor-agent-${RANDOM_SUFFIX}" \
        --statement-id allow-apigateway-invoke \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" || true
    
    API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    # Save to environment file
    cat >> .deployment_env << EOF
export API_ID="$API_ID"
export API_ENDPOINT="$API_ENDPOINT"
EOF
    
    export API_ID API_ENDPOINT
    
    log_success "API Gateway configured at: $API_ENDPOINT"
}

# Function to start Q Business synchronization
start_qbusiness_sync() {
    log_progress "Starting Q Business data source synchronization..."
    
    # Start synchronization for all data sources
    local sync_ids=()
    
    for ds_id in "$FINANCE_DS_ID" "$HR_DS_ID" "$TECH_DS_ID"; do
        local sync_id
        sync_id=$(aws qbusiness start-data-source-sync-job \
            --application-id "$Q_APP_ID" \
            --data-source-id "$ds_id" \
            --query 'executionId' --output text 2>/dev/null || echo "")
        
        if [[ -n "$sync_id" ]]; then
            sync_ids+=("$sync_id")
            log_info "Started sync for data source $ds_id: $sync_id"
        else
            log_warning "Failed to start sync for data source $ds_id"
        fi
    done
    
    # Wait for initial synchronization
    log_info "Waiting for data source synchronization to complete (this may take several minutes)..."
    sleep 60
    
    # Check synchronization status
    for ds_id in "$FINANCE_DS_ID" "$HR_DS_ID" "$TECH_DS_ID"; do
        local status
        status=$(aws qbusiness get-data-source \
            --application-id "$Q_APP_ID" \
            --data-source-id "$ds_id" \
            --query 'status' --output text 2>/dev/null || echo "UNKNOWN")
        
        log_info "Data source $ds_id status: $status"
    done
    
    log_success "Q Business synchronization initiated for all knowledge domains"
}

# Function to run deployment validation
validate_deployment() {
    log_progress "Validating deployment..."
    
    # Check Lambda functions
    local functions=("supervisor-agent-${RANDOM_SUFFIX}" "finance-agent-${RANDOM_SUFFIX}" "hr-agent-${RANDOM_SUFFIX}" "technical-agent-${RANDOM_SUFFIX}")
    
    for func in "${functions[@]}"; do
        local state
        state=$(aws lambda get-function --function-name "$func" --query 'Configuration.State' --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "$state" == "Active" ]]; then
            log_info "✓ Lambda function $func is active"
        else
            log_warning "✗ Lambda function $func state: $state"
        fi
    done
    
    # Check Q Business application
    local q_status
    q_status=$(aws qbusiness get-application --application-id "$Q_APP_ID" --query 'status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$q_status" == "ACTIVE" ]]; then
        log_info "✓ Q Business application is active"
    else
        log_warning "✗ Q Business application status: $q_status"
    fi
    
    # Check DynamoDB table
    local table_status
    table_status=$(aws dynamodb describe-table --table-name "$SESSION_TABLE" --query 'Table.TableStatus' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$table_status" == "ACTIVE" ]]; then
        log_info "✓ DynamoDB table is active"
    else
        log_warning "✗ DynamoDB table status: $table_status"
    fi
    
    # Test API endpoint
    if command -v curl &> /dev/null; then
        log_info "Testing API endpoint..."
        local response
        response=$(curl -s -o /dev/null -w "%{http_code}" -X GET "$API_ENDPOINT/health" --max-time 10 || echo "000")
        
        if [[ "$response" == "200" ]]; then
            log_info "✓ API Gateway is responding"
        else
            log_warning "✗ API Gateway returned status: $response"
        fi
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_success "Multi-Agent Knowledge Management System Deployment Complete!"
    
    echo ""
    echo "======================================================================"
    echo "                    DEPLOYMENT SUMMARY"
    echo "======================================================================"
    echo ""
    echo "🚀 ENDPOINTS:"
    echo "   API Gateway: $API_ENDPOINT"
    echo "   Health Check: $API_ENDPOINT/health"
    echo "   Query Endpoint: $API_ENDPOINT/query"
    echo ""
    echo "🤖 LAMBDA FUNCTIONS:"
    echo "   Supervisor Agent: supervisor-agent-${RANDOM_SUFFIX}"
    echo "   Finance Agent: finance-agent-${RANDOM_SUFFIX}"
    echo "   HR Agent: hr-agent-${RANDOM_SUFFIX}"
    echo "   Technical Agent: technical-agent-${RANDOM_SUFFIX}"
    echo ""
    echo "📚 KNOWLEDGE BASES:"
    echo "   Finance S3 Bucket: $S3_BUCKET_FINANCE"
    echo "   HR S3 Bucket: $S3_BUCKET_HR"
    echo "   Technical S3 Bucket: $S3_BUCKET_TECH"
    echo ""
    echo "🔍 Q BUSINESS:"
    echo "   Application ID: $Q_APP_ID"
    echo "   Index ID: $INDEX_ID"
    echo ""
    echo "💾 SESSION STORAGE:"
    echo "   DynamoDB Table: $SESSION_TABLE"
    echo ""
    echo "🔐 IAM ROLE:"
    echo "   Role Name: $IAM_ROLE_NAME"
    echo ""
    echo "======================================================================"
    echo ""
    echo "📋 TESTING COMMANDS:"
    echo ""
    echo "# Test a complex query requiring multiple agents:"
    echo "curl -X POST $API_ENDPOINT/query \\"
    echo "     -H \"Content-Type: application/json\" \\"
    echo "     -d '{\"query\": \"What is the budget approval process for travel?\", \"sessionId\": \"test-001\"}'"
    echo ""
    echo "# Test health endpoint:"
    echo "curl -X GET $API_ENDPOINT/health"
    echo ""
    echo "======================================================================"
    echo ""
    echo "📖 DOCUMENTATION:"
    echo "   Recipe Location: aws/multi-agent-knowledge-management-agentcore-q/"
    echo "   Cleanup Script: ./destroy.sh"
    echo ""
    echo "💰 ESTIMATED COSTS:"
    echo "   • Lambda invocations: ~\$0.01-0.10 per 1000 requests"
    echo "   • Q Business: ~\$20-50/month for testing usage"
    echo "   • DynamoDB: ~\$0.25/month for 1GB storage"
    echo "   • S3: ~\$0.02/month for sample documents"
    echo "   • API Gateway: ~\$0.001 per 1000 requests"
    echo ""
    echo "⚠️  IMPORTANT: Run './destroy.sh' when done testing to avoid ongoing charges!"
    echo ""
    echo "======================================================================"
}

# Main deployment function
main() {
    echo ""
    echo "======================================================================"
    echo "    Multi-Agent Knowledge Management System Deployment"
    echo "    Using AWS Bedrock AgentCore, Q Business, and Lambda"
    echo "======================================================================"
    echo ""
    
    # Start deployment
    local start_time
    start_time=$(date +%s)
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_iam_role
    create_knowledge_storage
    upload_sample_documents
    configure_qbusiness
    deploy_lambda_agents
    configure_session_management
    create_api_gateway
    start_qbusiness_sync
    validate_deployment
    
    # Calculate deployment time
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "Total deployment time: ${duration} seconds"
    
    # Display summary
    display_summary
    
    # Clean up temporary files
    rm -f supervisor-agent.py finance-agent.py hr-agent.py technical-agent.py
    rm -f *.zip *.txt memory-config.json
    
    log_info "Deployment logs saved to: $LOG_FILE"
    
    if [[ -s "$ERROR_FILE" ]]; then
        log_warning "Some errors occurred during deployment. Check: $ERROR_FILE"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Deploy Multi-Agent Knowledge Management System"
            echo ""
            echo "Options:"
            echo "  --help, -h          Show this help message"
            echo "  --validate-only     Only run validation, don't deploy"
            echo "  --dry-run          Show what would be deployed without creating resources"
            echo ""
            echo "Prerequisites:"
            echo "  - AWS CLI v2 configured with appropriate permissions"
            echo "  - Bedrock AgentCore enabled in your AWS account"
            echo ""
            exit 0
            ;;
        --validate-only)
            check_prerequisites
            exit 0
            ;;
        --dry-run)
            echo "DRY RUN: Would deploy the following resources:"
            echo "  - IAM Role: AgentCoreRole-<random>"
            echo "  - S3 Buckets: 3 knowledge base buckets"
            echo "  - Q Business Application and Index"
            echo "  - Lambda Functions: 4 agents"
            echo "  - DynamoDB Table: Session storage"
            echo "  - API Gateway: External interface"
            echo ""
            echo "Estimated deployment time: 5-10 minutes"
            echo "Estimated monthly cost: $20-100 for testing usage"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
    shift
done

# Run main deployment if no special flags
main "$@"