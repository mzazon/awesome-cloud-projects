#!/bin/bash

# Deploy script for Interactive Business Process Automation with Bedrock Agents and EventBridge
# This script deploys the complete infrastructure for AI-driven business process automation

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
DRY_RUN=false
FORCE_DEPLOY=false

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Interactive Business Process Automation with Bedrock Agents and EventBridge

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without actually deploying
    -f, --force         Force deployment even if resources exist
    -r, --region REGION Specify AWS region (default: from AWS CLI config)

EXAMPLES:
    $0                  # Deploy with default settings
    $0 --dry-run        # Preview deployment
    $0 --force          # Force redeploy
    $0 --region us-east-1  # Deploy to specific region

PREREQUISITES:
    - AWS CLI installed and configured
    - Appropriate AWS permissions for Bedrock, EventBridge, Lambda, S3, IAM
    - Access to Anthropic Claude models in Amazon Bedrock

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE_DEPLOY=true
            shift
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

log "Starting deployment of Interactive Business Process Automation"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check Bedrock access
    if ! aws bedrock list-foundation-models --region ${AWS_REGION:-us-east-1} &> /dev/null; then
        warning "Cannot access Bedrock. Ensure you have Bedrock permissions and model access."
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "No region specified, using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export PROJECT_NAME="biz-automation-${RANDOM_SUFFIX}"
    export S3_BUCKET="${PROJECT_NAME}-documents"
    export AGENT_NAME="${PROJECT_NAME}-agent"
    export EVENT_BUS_NAME="${PROJECT_NAME}-events"
    
    # Store configuration for cleanup
    cat > "${SCRIPT_DIR}/.deploy-config" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
PROJECT_NAME=${PROJECT_NAME}
S3_BUCKET=${S3_BUCKET}
AGENT_NAME=${AGENT_NAME}
EVENT_BUS_NAME=${EVENT_BUS_NAME}
DEPLOYMENT_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    
    success "Environment configured: Project ${PROJECT_NAME} in ${AWS_REGION}"
}

# Create S3 bucket with security
create_s3_bucket() {
    log "Creating S3 bucket for document storage..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create S3 bucket: ${S3_BUCKET}"
        return 0
    fi
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "${S3_BUCKET}" 2>/dev/null; then
        if [[ "$FORCE_DEPLOY" == "false" ]]; then
            warning "S3 bucket ${S3_BUCKET} already exists. Use --force to recreate."
            return 0
        else
            log "Bucket exists, cleaning up for fresh deployment..."
            aws s3 rm "s3://${S3_BUCKET}" --recursive
        fi
    else
        # Create bucket
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3 mb "s3://${S3_BUCKET}"
        else
            aws s3 mb "s3://${S3_BUCKET}" --region "${AWS_REGION}"
        fi
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${S3_BUCKET}" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "${S3_BUCKET}" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "${S3_BUCKET}" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    success "S3 bucket created with security enabled: ${S3_BUCKET}"
}

# Create IAM roles and policies
create_iam_resources() {
    log "Creating IAM roles and policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create IAM roles for Bedrock Agent and Lambda functions"
        return 0
    fi
    
    # Create Bedrock Agent IAM trust policy
    cat > "${SCRIPT_DIR}/agent-trust-policy.json" << 'EOF'
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
    
    # Create IAM role for the agent
    if ! aws iam get-role --role-name "${PROJECT_NAME}-agent-role" &>/dev/null; then
        aws iam create-role \
            --role-name "${PROJECT_NAME}-agent-role" \
            --assume-role-policy-document "file://${SCRIPT_DIR}/agent-trust-policy.json" \
            --description "Role for Bedrock Agent business automation"
    fi
    
    # Create IAM policy for agent permissions
    cat > "${SCRIPT_DIR}/agent-permissions-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:Retrieve"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET}",
        "arn:aws:s3:::${S3_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "events:PutEvents"
      ],
      "Resource": "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:event-bus/${EVENT_BUS_NAME}"
    }
  ]
}
EOF
    
    # Create and attach policy
    if ! aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-agent-policy" &>/dev/null; then
        aws iam create-policy \
            --policy-name "${PROJECT_NAME}-agent-policy" \
            --policy-document "file://${SCRIPT_DIR}/agent-permissions-policy.json"
    fi
    
    aws iam attach-role-policy \
        --role-name "${PROJECT_NAME}-agent-role" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-agent-policy"
    
    # Create Lambda execution role
    cat > "${SCRIPT_DIR}/lambda-trust-policy.json" << 'EOF'
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
    
    if ! aws iam get-role --role-name "${PROJECT_NAME}-lambda-execution-role" &>/dev/null; then
        aws iam create-role \
            --role-name "${PROJECT_NAME}-lambda-execution-role" \
            --assume-role-policy-document "file://${SCRIPT_DIR}/lambda-trust-policy.json" \
            --description "Execution role for business process Lambda functions"
    fi
    
    aws iam attach-role-policy \
        --role-name "${PROJECT_NAME}-lambda-execution-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Store role ARNs
    export AGENT_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-agent-role"
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-execution-role"
    
    success "IAM roles and policies created successfully"
}

# Create EventBridge custom event bus
create_eventbridge_bus() {
    log "Creating EventBridge custom event bus..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create EventBridge event bus: ${EVENT_BUS_NAME}"
        return 0
    fi
    
    # Create custom EventBridge event bus
    if ! aws events describe-event-bus --name "${EVENT_BUS_NAME}" &>/dev/null; then
        aws events create-event-bus \
            --name "${EVENT_BUS_NAME}" \
            --tags "Key=Project,Value=${PROJECT_NAME}"
    fi
    
    success "EventBridge event bus created: ${EVENT_BUS_NAME}"
}

# Create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions for business process handlers..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Lambda functions for approval, processing, and notification handlers"
        return 0
    fi
    
    # Create temp directory for Lambda code
    TEMP_DIR=$(mktemp -d)
    
    # Create approval handler
    cat > "${TEMP_DIR}/approval-handler.py" << 'EOF'
import json
import boto3
import uuid
from datetime import datetime

def lambda_handler(event, context):
    print(f"Processing approval event: {json.dumps(event)}")
    
    # Extract document details from EventBridge event
    detail = event['detail']
    document_name = detail['document_name']
    confidence_score = detail['confidence_score']
    recommendation = detail['recommendation']
    
    # Simulate approval logic based on AI recommendation
    if confidence_score > 0.85 and recommendation == 'APPROVE':
        status = 'AUTO_APPROVED'
        action = 'Document automatically approved'
    else:
        status = 'PENDING_REVIEW'
        action = 'Document requires human review'
    
    # Log the decision
    result = {
        'process_id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'document_name': document_name,
        'status': status,
        'action': action,
        'confidence_score': confidence_score
    }
    
    print(f"Approval result: {json.dumps(result)}")
    return {'statusCode': 200, 'body': json.dumps(result)}
EOF
    
    # Create processing handler
    cat > "${TEMP_DIR}/processing-handler.py" << 'EOF'
import json
import boto3
import uuid
from datetime import datetime

def lambda_handler(event, context):
    print(f"Processing automation event: {json.dumps(event)}")
    
    detail = event['detail']
    document_name = detail['document_name']
    document_type = detail['document_type']
    extracted_data = detail.get('extracted_data', {})
    
    # Simulate different processing based on document type
    processing_actions = {
        'invoice': 'Initiated payment processing workflow',
        'contract': 'Routed to legal team for final review',
        'compliance': 'Submitted to regulatory reporting system',
        'default': 'Archived for future reference'
    }
    
    action = processing_actions.get(document_type, processing_actions['default'])
    
    result = {
        'process_id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'document_name': document_name,
        'document_type': document_type,
        'action': action,
        'data_extracted': len(extracted_data) > 0
    }
    
    print(f"Processing result: {json.dumps(result)}")
    return {'statusCode': 200, 'body': json.dumps(result)}
EOF
    
    # Create notification handler
    cat > "${TEMP_DIR}/notification-handler.py" << 'EOF'
import json
import boto3
import uuid
from datetime import datetime

def lambda_handler(event, context):
    print(f"Processing notification event: {json.dumps(event)}")
    
    detail = event['detail']
    document_name = detail['document_name']
    alert_type = detail['alert_type']
    message = detail['message']
    
    # Simulate notification routing
    notification_channels = {
        'high_priority': ['email', 'slack', 'sms'],
        'medium_priority': ['email', 'slack'],
        'low_priority': ['email']
    }
    
    channels = notification_channels.get(alert_type, ['email'])
    
    result = {
        'notification_id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'document_name': document_name,
        'alert_type': alert_type,
        'message': message,
        'channels': channels,
        'status': 'sent'
    }
    
    print(f"Notification result: {json.dumps(result)}")
    return {'statusCode': 200, 'body': json.dumps(result)}
EOF
    
    # Wait for IAM role propagation
    log "Waiting for IAM role propagation..."
    sleep 15
    
    # Deploy Lambda functions
    for handler in approval processing notification; do
        log "Creating ${handler} Lambda function..."
        
        cd "${TEMP_DIR}"
        zip "${handler}-function.zip" "${handler}-handler.py"
        
        if aws lambda get-function --function-name "${PROJECT_NAME}-${handler}" &>/dev/null; then
            if [[ "$FORCE_DEPLOY" == "true" ]]; then
                aws lambda update-function-code \
                    --function-name "${PROJECT_NAME}-${handler}" \
                    --zip-file "fileb://${handler}-function.zip"
            else
                warning "Function ${PROJECT_NAME}-${handler} already exists. Use --force to update."
                continue
            fi
        else
            aws lambda create-function \
                --function-name "${PROJECT_NAME}-${handler}" \
                --runtime python3.12 \
                --role "${LAMBDA_ROLE_ARN}" \
                --handler "${handler}-handler.lambda_handler" \
                --zip-file "fileb://${handler}-function.zip" \
                --timeout 30 \
                --memory-size 256 \
                --tags "Project=${PROJECT_NAME}"
        fi
    done
    
    # Clean up temp directory
    rm -rf "${TEMP_DIR}"
    
    success "Lambda functions created successfully"
}

# Create EventBridge rules
create_eventbridge_rules() {
    log "Creating EventBridge rules for event routing..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create EventBridge rules for approval, processing, and notifications"
        return 0
    fi
    
    # Create rule for high-confidence document approval
    aws events put-rule \
        --event-bus-name "${EVENT_BUS_NAME}" \
        --name "${PROJECT_NAME}-approval-rule" \
        --event-pattern '{
          "source": ["bedrock.agent"],
          "detail-type": ["Document Analysis Complete"],
          "detail": {
            "recommendation": ["APPROVE"],
            "confidence_score": [{"numeric": [">=", 0.8]}]
          }
        }' \
        --description "Route high-confidence approvals"
    
    # Grant EventBridge permission to invoke Lambda functions
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-approval" \
        --statement-id eventbridge-approval-invoke \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENT_BUS_NAME}/${PROJECT_NAME}-approval-rule" \
        2>/dev/null || true
    
    # Add Lambda target for approval rule
    aws events put-targets \
        --event-bus-name "${EVENT_BUS_NAME}" \
        --rule "${PROJECT_NAME}-approval-rule" \
        --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-approval"
    
    # Create similar rules for processing and notifications
    # Processing rule
    aws events put-rule \
        --event-bus-name "${EVENT_BUS_NAME}" \
        --name "${PROJECT_NAME}-processing-rule" \
        --event-pattern '{
          "source": ["bedrock.agent"],
          "detail-type": ["Document Analysis Complete"],
          "detail": {
            "document_type": ["invoice", "contract", "compliance"]
          }
        }' \
        --description "Route documents for automated processing"
    
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-processing" \
        --statement-id eventbridge-processing-invoke \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENT_BUS_NAME}/${PROJECT_NAME}-processing-rule" \
        2>/dev/null || true
    
    aws events put-targets \
        --event-bus-name "${EVENT_BUS_NAME}" \
        --rule "${PROJECT_NAME}-processing-rule" \
        --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-processing"
    
    # Alert rule
    aws events put-rule \
        --event-bus-name "${EVENT_BUS_NAME}" \
        --name "${PROJECT_NAME}-alert-rule" \
        --event-pattern '{
          "source": ["bedrock.agent"],
          "detail-type": ["Document Analysis Complete"],
          "detail": {
            "alert_type": ["high_priority", "compliance_issue", "error"]
          }
        }' \
        --description "Route alerts and notifications"
    
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-notification" \
        --statement-id eventbridge-notification-invoke \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENT_BUS_NAME}/${PROJECT_NAME}-alert-rule" \
        2>/dev/null || true
    
    aws events put-targets \
        --event-bus-name "${EVENT_BUS_NAME}" \
        --rule "${PROJECT_NAME}-alert-rule" \
        --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-notification"
    
    success "EventBridge rules created successfully"
}

# Create Bedrock Agent
create_bedrock_agent() {
    log "Creating Bedrock Agent with action groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Bedrock Agent: ${AGENT_NAME}"
        return 0
    fi
    
    # Create action group schema
    cat > "${SCRIPT_DIR}/action-schema.json" << 'EOF'
{
  "openAPIVersion": "3.0.0",
  "info": {
    "title": "Business Process Automation API",
    "version": "1.0.0",
    "description": "API for AI agent business process automation"
  },
  "paths": {
    "/analyze-document": {
      "post": {
        "description": "Analyze business document and trigger appropriate workflows",
        "parameters": [
          {
            "name": "document_path",
            "in": "query",
            "description": "S3 path to the document",
            "required": true,
            "schema": {"type": "string"}
          },
          {
            "name": "document_type",
            "in": "query",
            "description": "Type of document (invoice, contract, compliance)",
            "required": true,
            "schema": {"type": "string"}
          }
        ],
        "responses": {
          "200": {
            "description": "Document analysis completed",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "recommendation": {"type": "string"},
                    "confidence_score": {"type": "number"},
                    "extracted_data": {"type": "object"},
                    "next_actions": {"type": "array"}
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
EOF
    
    # Upload action schema to S3
    aws s3 cp "${SCRIPT_DIR}/action-schema.json" "s3://${S3_BUCKET}/schemas/"
    
    # Create agent action handler Lambda
    TEMP_DIR=$(mktemp -d)
    cat > "${TEMP_DIR}/agent-action-handler.py" << EOF
import json
import boto3
import re
from datetime import datetime

s3_client = boto3.client('s3')
events_client = boto3.client('events')

def lambda_handler(event, context):
    print(f"Agent action request: {json.dumps(event)}")
    
    # Parse agent request
    action_request = event['actionRequest']
    api_path = action_request['apiPath']
    parameters = action_request.get('parameters', [])
    
    # Extract parameters
    document_path = None
    document_type = None
    
    for param in parameters:
        if param['name'] == 'document_path':
            document_path = param['value']
        elif param['name'] == 'document_type':
            document_type = param['value']
    
    if api_path == '/analyze-document':
        result = analyze_document(document_path, document_type)
        
        # Publish event to EventBridge
        publish_event(result)
        
        return {
            'response': {
                'actionResponse': {
                    'responseBody': result
                }
            }
        }
    
    return {
        'response': {
            'actionResponse': {
                'responseBody': {'error': 'Unknown action'}
            }
        }
    }

def analyze_document(document_path, document_type):
    # Simulate document analysis
    analysis_results = {
        'invoice': {
            'recommendation': 'APPROVE',
            'confidence_score': 0.92,
            'extracted_data': {
                'amount': 1250.00,
                'vendor': 'TechSupplies Inc',
                'due_date': '2024-01-15'
            },
            'alert_type': 'medium_priority'
        },
        'contract': {
            'recommendation': 'REVIEW',
            'confidence_score': 0.75,
            'extracted_data': {
                'contract_value': 50000.00,
                'term_length': '12 months',
                'party': 'Global Services LLC'
            },
            'alert_type': 'high_priority'
        },
        'compliance': {
            'recommendation': 'APPROVE',
            'confidence_score': 0.88,
            'extracted_data': {
                'regulation': 'SOX',
                'compliance_score': 95,
                'review_date': '2024-01-01'
            },
            'alert_type': 'low_priority'
        }
    }
    
    return analysis_results.get(document_type, {
        'recommendation': 'REVIEW',
        'confidence_score': 0.5,
        'extracted_data': {},
        'alert_type': 'medium_priority'
    })

def publish_event(analysis_result):
    event_detail = {
        'document_name': 'sample-document.pdf',
        'document_type': 'invoice',
        'timestamp': datetime.utcnow().isoformat(),
        **analysis_result
    }
    
    events_client.put_events(
        Entries=[
            {
                'Source': 'bedrock.agent',
                'DetailType': 'Document Analysis Complete',
                'Detail': json.dumps(event_detail),
                'EventBusName': '${EVENT_BUS_NAME}'
            }
        ]
    )
EOF
    
    # Package and deploy agent action Lambda
    cd "${TEMP_DIR}"
    zip agent-action-function.zip agent-action-handler.py
    
    if aws lambda get-function --function-name "${PROJECT_NAME}-agent-action" &>/dev/null; then
        if [[ "$FORCE_DEPLOY" == "true" ]]; then
            aws lambda update-function-code \
                --function-name "${PROJECT_NAME}-agent-action" \
                --zip-file "fileb://agent-action-function.zip"
        fi
    else
        aws lambda create-function \
            --function-name "${PROJECT_NAME}-agent-action" \
            --runtime python3.12 \
            --role "${LAMBDA_ROLE_ARN}" \
            --handler agent-action-handler.lambda_handler \
            --zip-file "fileb://agent-action-function.zip" \
            --timeout 60 \
            --memory-size 512 \
            --environment "Variables={EVENT_BUS_NAME=${EVENT_BUS_NAME}}"
    fi
    
    rm -rf "${TEMP_DIR}"
    
    # Create the Bedrock Agent
    if ! aws bedrock-agent list-agents --query "agentSummaries[?agentName=='${AGENT_NAME}'].agentId" --output text | grep -q .; then
        aws bedrock-agent create-agent \
            --agent-name "${AGENT_NAME}" \
            --agent-resource-role-arn "${AGENT_ROLE_ARN}" \
            --foundation-model "anthropic.claude-3-sonnet-20240229-v1:0" \
            --instruction "You are a business process automation agent. Analyze documents uploaded to S3, extract key information, make recommendations for approval or processing, and trigger appropriate business workflows through EventBridge events. Focus on accuracy, compliance, and efficient processing." \
            --description "AI agent for intelligent business process automation"
    fi
    
    # Get agent ID
    export AGENT_ID=$(aws bedrock-agent list-agents \
        --query "agentSummaries[?agentName=='${AGENT_NAME}'].agentId" \
        --output text)
    
    # Wait for agent to be ready
    log "Waiting for agent to become available..."
    while [ "$(aws bedrock-agent get-agent --agent-id ${AGENT_ID} --query 'agent.agentStatus' --output text)" = "CREATING" ]; do
        sleep 5
    done
    
    success "Bedrock Agent created successfully: ${AGENT_ID}"
    
    # Save agent ID to config
    echo "AGENT_ID=${AGENT_ID}" >> "${SCRIPT_DIR}/.deploy-config"
}

# Deploy complete solution
deploy_solution() {
    log "Deploying complete business process automation solution..."
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_iam_resources
    create_eventbridge_bus
    create_lambda_functions
    create_eventbridge_rules
    create_bedrock_agent
    
    success "Deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Deployment Summary:"
        echo "  Project Name: ${PROJECT_NAME}"
        echo "  Region: ${AWS_REGION}"
        echo "  S3 Bucket: ${S3_BUCKET}"
        echo "  Event Bus: ${EVENT_BUS_NAME}"
        echo "  Agent Name: ${AGENT_NAME}"
        echo ""
        echo "Configuration saved to: ${SCRIPT_DIR}/.deploy-config"
        echo ""
        echo "Next steps:"
        echo "1. Upload test documents to S3 bucket"
        echo "2. Test agent invocation through AWS Console or CLI"
        echo "3. Monitor Lambda function logs for event processing"
        echo "4. Use destroy.sh script to clean up resources when done"
    fi
}

# Main execution
deploy_solution

exit 0