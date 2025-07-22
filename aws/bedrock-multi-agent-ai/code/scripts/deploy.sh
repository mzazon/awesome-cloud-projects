#!/bin/bash

# Multi-Agent AI Workflows with Amazon Bedrock AgentCore - Deployment Script
# This script deploys the complete multi-agent AI workflow infrastructure

set -e
set -o pipefail

# Color codes for output formatting
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

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command '$1' not found. Please install it and try again."
        exit 1
    fi
}

# Function to wait for resource creation
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local max_attempts="${3:-30}"
    local attempt=0
    
    log_info "Waiting for $resource_type: $resource_name to be ready..."
    
    while [ $attempt -lt $max_attempts ]; do
        case $resource_type in
            "dynamodb-table")
                if aws dynamodb describe-table --table-name "$resource_name" --query 'Table.TableStatus' --output text 2>/dev/null | grep -q "ACTIVE"; then
                    return 0
                fi
                ;;
            "bedrock-agent")
                if aws bedrock-agent get-agent --agent-id "$resource_name" --query 'agent.agentStatus' --output text 2>/dev/null | grep -q "PREPARED\|NOT_PREPARED"; then
                    return 0
                fi
                ;;
        esac
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 10
    done
    
    log_error "Timeout waiting for $resource_type: $resource_name"
    return 1
}

# Function to generate random suffix
generate_random_suffix() {
    if command -v aws &> /dev/null; then
        aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            openssl rand -hex 3 2>/dev/null || \
            date +%s | tail -c 6
    else
        openssl rand -hex 3 2>/dev/null || date +%s | tail -c 6
    fi
}

# Function to check AWS CLI configuration
check_aws_config() {
    log_info "Checking AWS CLI configuration..."
    
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        log_info "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
    
    local aws_region
    aws_region=$(aws configure get region)
    if [ -z "$aws_region" ]; then
        log_error "AWS region is not configured"
        log_info "Please run 'aws configure set region <your-region>' or set AWS_DEFAULT_REGION"
        exit 1
    fi
    
    log_success "AWS CLI configuration verified"
    log_info "Using AWS region: $aws_region"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required commands
    check_command "aws"
    check_command "jq"
    
    # Check AWS configuration
    check_aws_config
    
    # Check Bedrock model access
    log_info "Checking Amazon Bedrock model access..."
    if ! aws bedrock list-foundation-models --query 'modelSummaries[?contains(modelId, `anthropic.claude-3-sonnet`)]' --output text | grep -q claude; then
        log_warning "Claude 3 Sonnet model may not be available in your region or account"
        log_warning "Please ensure you have requested access to Claude models in Amazon Bedrock"
    fi
    
    log_success "Prerequisites check completed"
}

# Function to create IAM roles
create_iam_roles() {
    log_info "Creating IAM roles..."
    
    # Create Bedrock agent role
    log_info "Creating Bedrock agent execution role..."
    aws iam create-role \
        --role-name "BedrockAgentRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "bedrock.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        --tags Key=Project,Value=MultiAgentWorkflow Key=CreatedBy,Value=DeployScript >/dev/null 2>&1 || true
    
    # Attach policies to Bedrock role
    aws iam attach-role-policy \
        --role-name "BedrockAgentRole-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonBedrockFullAccess || true
    
    # Create Lambda coordinator role
    log_info "Creating Lambda coordinator execution role..."
    aws iam create-role \
        --role-name "LambdaCoordinatorRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "lambda.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        --tags Key=Project,Value=MultiAgentWorkflow Key=CreatedBy,Value=DeployScript >/dev/null 2>&1 || true
    
    # Attach policies to Lambda role
    local policies=(
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
        "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
        "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
    )
    
    for policy in "${policies[@]}"; do
        aws iam attach-role-policy \
            --role-name "LambdaCoordinatorRole-${RANDOM_SUFFIX}" \
            --policy-arn "$policy" || true
    done
    
    # Wait for roles to be available
    log_info "Waiting for IAM roles to propagate..."
    sleep 30
    
    log_success "IAM roles created successfully"
}

# Function to create DynamoDB memory table
create_dynamodb_table() {
    log_info "Creating DynamoDB table for agent memory..."
    
    aws dynamodb create-table \
        --table-name "${MEMORY_TABLE_NAME}" \
        --attribute-definitions \
            AttributeName=SessionId,AttributeType=S \
            AttributeName=Timestamp,AttributeType=N \
        --key-schema \
            AttributeName=SessionId,KeyType=HASH \
            AttributeName=Timestamp,KeyType=RANGE \
        --provisioned-throughput \
            ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
        --tags Key=Project,Value=MultiAgentWorkflow Key=CreatedBy,Value=DeployScript >/dev/null
    
    # Wait for table to be active
    wait_for_resource "dynamodb-table" "${MEMORY_TABLE_NAME}"
    
    export MEMORY_TABLE_ARN=$(aws dynamodb describe-table \
        --table-name "${MEMORY_TABLE_NAME}" \
        --query 'Table.TableArn' --output text)
    
    log_success "DynamoDB memory table created: ${MEMORY_TABLE_ARN}"
}

# Function to create EventBridge infrastructure
create_eventbridge_infrastructure() {
    log_info "Creating EventBridge infrastructure..."
    
    # Create custom event bus
    aws events create-event-bus \
        --name "${EVENT_BUS_NAME}" \
        --tags Key=Project,Value=MultiAgentWorkflow Key=CreatedBy,Value=DeployScript >/dev/null
    
    # Create event rule for agent task routing
    aws events put-rule \
        --name agent-task-router \
        --event-bus-name "${EVENT_BUS_NAME}" \
        --event-pattern '{
            "source": ["multi-agent.system"],
            "detail-type": ["Agent Task Request"]
        }' \
        --description "Routes tasks to specialized agents" >/dev/null
    
    export EVENT_BUS_ARN=$(aws events describe-event-bus \
        --name "${EVENT_BUS_NAME}" \
        --query 'Arn' --output text)
    
    # Create dead letter queue
    aws sqs create-queue \
        --queue-name "multi-agent-dlq-${RANDOM_SUFFIX}" \
        --attributes '{
            "MessageRetentionPeriod": "1209600",
            "VisibilityTimeoutSeconds": "60"
        }' \
        --tags Key=Project,Value=MultiAgentWorkflow Key=CreatedBy,Value=DeployScript >/dev/null
    
    export DLQ_URL=$(aws sqs get-queue-url \
        --queue-name "multi-agent-dlq-${RANDOM_SUFFIX}" \
        --query 'QueueUrl' --output text)
    
    log_success "EventBridge infrastructure created: ${EVENT_BUS_ARN}"
}

# Function to create Lambda coordinator
create_lambda_coordinator() {
    log_info "Creating Lambda coordinator function..."
    
    # Create coordinator Python code
    cat > /tmp/coordinator.py << 'EOF'
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

eventbridge = boto3.client('events')
bedrock_agent = boto3.client('bedrock-agent-runtime')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """Coordinate multi-agent workflows based on EventBridge events"""
    
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        task_type = detail.get('taskType')
        request_data = detail.get('requestData')
        correlation_id = detail.get('correlationId')
        session_id = detail.get('sessionId', correlation_id)
        
        logger.info(f"Processing task: {task_type} with correlation: {correlation_id}")
        
        # Store task in memory table
        memory_table_name = os.environ.get('MEMORY_TABLE_NAME')
        memory_table = dynamodb.Table(memory_table_name)
        
        memory_table.put_item(
            Item={
                'SessionId': session_id,
                'Timestamp': int(datetime.now().timestamp()),
                'TaskType': task_type,
                'RequestData': request_data,
                'Status': 'processing'
            }
        )
        
        # Route to appropriate agent based on task type
        agent_response = route_to_agent(task_type, request_data, session_id)
        
        # Update memory with result
        memory_table.put_item(
            Item={
                'SessionId': session_id,
                'Timestamp': int(datetime.now().timestamp()),
                'TaskType': task_type,
                'Response': agent_response,
                'Status': 'completed'
            }
        )
        
        # Publish completion event
        event_bus_name = os.environ.get('EVENT_BUS_NAME')
        eventbridge.put_events(
            Entries=[{
                'Source': 'multi-agent.coordinator',
                'DetailType': 'Agent Task Completed',
                'Detail': json.dumps({
                    'correlationId': correlation_id,
                    'taskType': task_type,
                    'result': agent_response,
                    'status': 'completed'
                }),
                'EventBusName': event_bus_name
            }]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Task coordinated successfully',
                'correlationId': correlation_id
            })
        }
        
    except Exception as e:
        logger.error(f"Coordination error: {str(e)}")
        
        # Publish error event
        eventbridge.put_events(
            Entries=[{
                'Source': 'multi-agent.coordinator',
                'DetailType': 'Agent Task Failed',
                'Detail': json.dumps({
                    'correlationId': correlation_id,
                    'error': str(e),
                    'status': 'failed'
                })
            }]
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def route_to_agent(task_type, request_data, session_id):
    """Route task to appropriate specialized agent"""
    
    # This is a simplified routing function
    # In production, this would invoke actual Bedrock agents
    agent_responses = {
        'financial_analysis': f"Financial analysis completed for: {request_data}",
        'customer_support': f"Customer support response for: {request_data}",
        'data_analytics': f"Analytics insights for: {request_data}"
    }
    
    return agent_responses.get(task_type, f"Processed by general agent: {request_data}")
EOF
    
    # Create deployment package
    cd /tmp
    zip coordinator.zip coordinator.py >/dev/null
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${COORDINATOR_FUNCTION_NAME}" \
        --runtime python3.11 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/LambdaCoordinatorRole-${RANDOM_SUFFIX}" \
        --handler coordinator.lambda_handler \
        --zip-file fileb://coordinator.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables='{
            "EVENT_BUS_NAME":"'${EVENT_BUS_NAME}'",
            "MEMORY_TABLE_NAME":"'${MEMORY_TABLE_NAME}'"
        }' \
        --tags Key=Project,Value=MultiAgentWorkflow,Key=CreatedBy,Value=DeployScript >/dev/null
    
    # Clean up temporary files
    rm -f /tmp/coordinator.py /tmp/coordinator.zip
    
    log_success "Lambda coordinator function created successfully"
}

# Function to create Bedrock agents
create_bedrock_agents() {
    log_info "Creating specialized Bedrock agents..."
    
    local bedrock_role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/BedrockAgentRole-${RANDOM_SUFFIX}"
    
    # Create Financial Analysis Agent
    log_info "Creating Financial Analysis Agent..."
    aws bedrock-agent create-agent \
        --agent-name "${FINANCE_AGENT_NAME}" \
        --agent-resource-role-arn "${bedrock_role_arn}" \
        --description "Specialized agent for financial analysis and reporting" \
        --foundation-model anthropic.claude-3-sonnet-20240229-v1:0 \
        --instruction "You are a financial analysis specialist. Your role is to analyze financial data, create reports, calculate metrics, and provide insights on financial performance. Always provide detailed explanations of your analysis methodology and cite relevant financial principles. Focus on accuracy and compliance with financial reporting standards." \
        --idle-session-ttl-in-seconds 1800 >/dev/null
    
    export FINANCE_AGENT_ID=$(aws bedrock-agent list-agents \
        --query "agentSummaries[?agentName=='${FINANCE_AGENT_NAME}'].agentId" \
        --output text)
    
    # Create Customer Support Agent
    log_info "Creating Customer Support Agent..."
    aws bedrock-agent create-agent \
        --agent-name "${SUPPORT_AGENT_NAME}" \
        --agent-resource-role-arn "${bedrock_role_arn}" \
        --description "Specialized agent for customer support and service" \
        --foundation-model anthropic.claude-3-sonnet-20240229-v1:0 \
        --instruction "You are a customer support specialist. Your role is to help customers resolve issues, answer questions, and provide excellent service experiences. Always maintain a helpful, empathetic tone and focus on resolving customer concerns efficiently. Escalate complex technical issues when appropriate and always follow company policies." \
        --idle-session-ttl-in-seconds 1800 >/dev/null
    
    export SUPPORT_AGENT_ID=$(aws bedrock-agent list-agents \
        --query "agentSummaries[?agentName=='${SUPPORT_AGENT_NAME}'].agentId" \
        --output text)
    
    # Create Data Analytics Agent
    log_info "Creating Data Analytics Agent..."
    aws bedrock-agent create-agent \
        --agent-name "${ANALYTICS_AGENT_NAME}" \
        --agent-resource-role-arn "${bedrock_role_arn}" \
        --description "Specialized agent for data analysis and insights" \
        --foundation-model anthropic.claude-3-sonnet-20240229-v1:0 \
        --instruction "You are a data analytics specialist. Your role is to analyze datasets, identify patterns, create visualizations, and provide actionable insights. Focus on statistical accuracy, clear data interpretation, and practical business recommendations. Always explain your analytical methodology and validate your findings." \
        --idle-session-ttl-in-seconds 1800 >/dev/null
    
    export ANALYTICS_AGENT_ID=$(aws bedrock-agent list-agents \
        --query "agentSummaries[?agentName=='${ANALYTICS_AGENT_NAME}'].agentId" \
        --output text)
    
    # Create Supervisor Agent
    log_info "Creating Supervisor Agent..."
    aws bedrock-agent create-agent \
        --agent-name "${SUPERVISOR_AGENT_NAME}" \
        --agent-resource-role-arn "${bedrock_role_arn}" \
        --description "Supervisor agent for multi-agent workflow coordination" \
        --foundation-model anthropic.claude-3-sonnet-20240229-v1:0 \
        --instruction "You are a supervisor agent responsible for coordinating complex business tasks across specialized agent teams. Your responsibilities include: 1. Analyzing incoming requests and breaking them into sub-tasks 2. Routing tasks to appropriate specialist agents: Financial Agent for financial analysis, Support Agent for customer service, Analytics Agent for data analysis 3. Coordinating parallel work streams and managing dependencies 4. Synthesizing results from multiple agents into cohesive responses 5. Ensuring quality control and consistency across agent outputs. Always provide clear task delegation and maintain oversight of the overall workflow progress." \
        --idle-session-ttl-in-seconds 3600 >/dev/null
    
    export SUPERVISOR_AGENT_ID=$(aws bedrock-agent list-agents \
        --query "agentSummaries[?agentName=='${SUPERVISOR_AGENT_NAME}'].agentId" \
        --output text)
    
    log_success "Specialized agents created successfully"
    log_info "Finance Agent ID: ${FINANCE_AGENT_ID}"
    log_info "Support Agent ID: ${SUPPORT_AGENT_ID}"
    log_info "Analytics Agent ID: ${ANALYTICS_AGENT_ID}"
    log_info "Supervisor Agent ID: ${SUPERVISOR_AGENT_ID}"
}

# Function to configure EventBridge integration
configure_eventbridge_integration() {
    log_info "Configuring EventBridge integration with Lambda coordinator..."
    
    # Add EventBridge permission to invoke Lambda function
    aws lambda add-permission \
        --function-name "${COORDINATOR_FUNCTION_NAME}" \
        --statement-id eventbridge-invoke \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENT_BUS_NAME}/agent-task-router" >/dev/null 2>&1 || true
    
    # Create EventBridge target for Lambda function
    aws events put-targets \
        --rule agent-task-router \
        --event-bus-name "${EVENT_BUS_NAME}" \
        --targets Id=1,Arn="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${COORDINATOR_FUNCTION_NAME}" >/dev/null
    
    log_success "EventBridge integration configured successfully"
}

# Function to prepare agents
prepare_agents() {
    log_info "Preparing agents for production use..."
    
    # Prepare all agents
    local agents=("${SUPERVISOR_AGENT_ID}" "${FINANCE_AGENT_ID}" "${SUPPORT_AGENT_ID}" "${ANALYTICS_AGENT_ID}")
    
    for agent_id in "${agents[@]}"; do
        if [ -n "$agent_id" ]; then
            aws bedrock-agent prepare-agent --agent-id "$agent_id" >/dev/null &
        fi
    done
    
    # Wait for all background jobs to complete
    wait
    
    log_info "Waiting for agents to be prepared..."
    sleep 60
    
    # Create production aliases
    for agent_id in "${agents[@]}"; do
        if [ -n "$agent_id" ]; then
            aws bedrock-agent create-agent-alias \
                --agent-id "$agent_id" \
                --agent-alias-name production \
                --description "Production alias for agent" >/dev/null 2>&1 || true
        fi
    done
    
    export SUPERVISOR_ALIAS_ID=$(aws bedrock-agent list-agent-aliases \
        --agent-id "${SUPERVISOR_AGENT_ID}" \
        --query "agentAliasSummaries[?agentAliasName=='production'].agentAliasId" \
        --output text 2>/dev/null || echo "")
    
    log_success "Agents prepared and production aliases created"
}

# Function to create monitoring infrastructure
create_monitoring_infrastructure() {
    log_info "Creating monitoring and observability infrastructure..."
    
    # Create CloudWatch Log Groups
    local log_groups=(
        "/aws/bedrock/agents/supervisor"
        "/aws/bedrock/agents/specialized"
        "/aws/lambda/${COORDINATOR_FUNCTION_NAME}"
    )
    
    for log_group in "${log_groups[@]}"; do
        aws logs create-log-group \
            --log-group-name "$log_group" \
            --retention-in-days 30 >/dev/null 2>&1 || true
    done
    
    # Create CloudWatch Dashboard
    cat > /tmp/dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/Bedrock", "InvocationLatency", "AgentId", "${SUPERVISOR_AGENT_ID}"],
                    ["AWS/Bedrock", "InvocationCount", "AgentId", "${SUPERVISOR_AGENT_ID}"],
                    ["AWS/Lambda", "Duration", "FunctionName", "${COORDINATOR_FUNCTION_NAME}"],
                    ["AWS/Events", "MatchedEvents", "EventBusName", "${EVENT_BUS_NAME}"],
                    ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", "${MEMORY_TABLE_NAME}"],
                    ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", "${MEMORY_TABLE_NAME}"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Multi-Agent Performance Metrics",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "MultiAgentWorkflow-${RANDOM_SUFFIX}" \
        --dashboard-body file:///tmp/dashboard-config.json >/dev/null
    
    # Enable X-Ray tracing for Lambda function
    aws lambda update-function-configuration \
        --function-name "${COORDINATOR_FUNCTION_NAME}" \
        --tracing-config Mode=Active >/dev/null 2>&1 || true
    
    # Clean up temporary file
    rm -f /tmp/dashboard-config.json
    
    log_success "Monitoring infrastructure created successfully"
}

# Function to save deployment configuration
save_deployment_config() {
    log_info "Saving deployment configuration..."
    
    cat > "/tmp/multi-agent-deployment-${RANDOM_SUFFIX}.env" << EOF
# Multi-Agent AI Workflow Deployment Configuration
# Generated: $(date)

export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"

# Resource Names
export SUPERVISOR_AGENT_NAME="${SUPERVISOR_AGENT_NAME}"
export FINANCE_AGENT_NAME="${FINANCE_AGENT_NAME}"
export SUPPORT_AGENT_NAME="${SUPPORT_AGENT_NAME}"
export ANALYTICS_AGENT_NAME="${ANALYTICS_AGENT_NAME}"
export EVENT_BUS_NAME="${EVENT_BUS_NAME}"
export COORDINATOR_FUNCTION_NAME="${COORDINATOR_FUNCTION_NAME}"
export MEMORY_TABLE_NAME="${MEMORY_TABLE_NAME}"

# Resource IDs
export SUPERVISOR_AGENT_ID="${SUPERVISOR_AGENT_ID}"
export FINANCE_AGENT_ID="${FINANCE_AGENT_ID}"
export SUPPORT_AGENT_ID="${SUPPORT_AGENT_ID}"
export ANALYTICS_AGENT_ID="${ANALYTICS_AGENT_ID}"
export SUPERVISOR_ALIAS_ID="${SUPERVISOR_ALIAS_ID}"

# Resource ARNs
export BEDROCK_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/BedrockAgentRole-${RANDOM_SUFFIX}"
export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/LambdaCoordinatorRole-${RANDOM_SUFFIX}"
export MEMORY_TABLE_ARN="${MEMORY_TABLE_ARN}"
export EVENT_BUS_ARN="${EVENT_BUS_ARN}"
export DLQ_URL="${DLQ_URL}"
EOF
    
    log_success "Deployment configuration saved to: /tmp/multi-agent-deployment-${RANDOM_SUFFIX}.env"
    log_info "Source this file to restore environment variables for cleanup: source /tmp/multi-agent-deployment-${RANDOM_SUFFIX}.env"
}

# Main deployment function
main() {
    log_info "Starting Multi-Agent AI Workflow deployment..."
    log_info "Deployment started at: $(date)"
    
    # Check prerequisites
    check_prerequisites
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export RANDOM_SUFFIX=$(generate_random_suffix)
    
    # Set resource names
    export SUPERVISOR_AGENT_NAME="supervisor-agent-${RANDOM_SUFFIX}"
    export FINANCE_AGENT_NAME="finance-agent-${RANDOM_SUFFIX}"
    export SUPPORT_AGENT_NAME="support-agent-${RANDOM_SUFFIX}"
    export ANALYTICS_AGENT_NAME="analytics-agent-${RANDOM_SUFFIX}"
    export EVENT_BUS_NAME="multi-agent-bus-${RANDOM_SUFFIX}"
    export COORDINATOR_FUNCTION_NAME="agent-coordinator-${RANDOM_SUFFIX}"
    export MEMORY_TABLE_NAME="agent-memory-${RANDOM_SUFFIX}"
    
    log_info "Using deployment suffix: ${RANDOM_SUFFIX}"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account: ${AWS_ACCOUNT_ID}"
    
    # Create infrastructure components
    create_iam_roles
    create_dynamodb_table
    create_eventbridge_infrastructure
    create_lambda_coordinator
    create_bedrock_agents
    configure_eventbridge_integration
    prepare_agents
    create_monitoring_infrastructure
    save_deployment_config
    
    log_success "🎉 Multi-Agent AI Workflow deployment completed successfully!"
    log_info "Deployment completed at: $(date)"
    
    # Display deployment summary
    echo ""
    log_info "=== DEPLOYMENT SUMMARY ==="
    echo "Deployment Suffix: ${RANDOM_SUFFIX}"
    echo "Supervisor Agent ID: ${SUPERVISOR_AGENT_ID}"
    echo "Finance Agent ID: ${FINANCE_AGENT_ID}"
    echo "Support Agent ID: ${SUPPORT_AGENT_ID}"
    echo "Analytics Agent ID: ${ANALYTICS_AGENT_ID}"
    echo "EventBridge Bus: ${EVENT_BUS_NAME}"
    echo "Lambda Function: ${COORDINATOR_FUNCTION_NAME}"
    echo "DynamoDB Table: ${MEMORY_TABLE_NAME}"
    echo "CloudWatch Dashboard: MultiAgentWorkflow-${RANDOM_SUFFIX}"
    echo ""
    echo "Configuration file: /tmp/multi-agent-deployment-${RANDOM_SUFFIX}.env"
    echo ""
    log_info "To test the deployment, use the AWS CLI to invoke the supervisor agent:"
    echo "aws bedrock-agent-runtime invoke-agent --agent-id ${SUPERVISOR_AGENT_ID} --agent-alias-id production --session-id test-session --input-text 'Analyze Q4 financial performance and customer satisfaction trends'"
    echo ""
    log_warning "Remember to run ./destroy.sh when you're done testing to avoid ongoing charges"
}

# Run main function
main "$@"