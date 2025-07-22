#!/bin/bash

# =============================================================================
# Deploy Script for Intelligent Document QA System with AWS Bedrock and Kendra
# =============================================================================
# This script deploys the complete infrastructure for an intelligent document
# question-answering system using Amazon Kendra and AWS Bedrock.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate AWS permissions for Bedrock, Kendra, Lambda, S3, and IAM
# - Access to Amazon Bedrock Claude models
#
# Usage: ./deploy.sh [--dry-run] [--verbose]
# =============================================================================

set -e
set -o pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/qa-system-deploy-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--verbose]"
            echo "  --dry-run   Show what would be deployed without making changes"
            echo "  --verbose   Enable verbose logging"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $1" | tee -a "$LOG_FILE"
    fi
}

# Cleanup function for script interruption
cleanup() {
    log "Deployment interrupted. Check $LOG_FILE for details."
    exit 1
}

trap cleanup INT TERM

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ ! "$AWS_CLI_VERSION" =~ ^2\. ]]; then
        log_error "AWS CLI v2 is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    # Check required permissions (basic check)
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        log_error "Unable to retrieve AWS account ID. Check permissions."
        exit 1
    fi
    
    log "Prerequisites check completed successfully."
}

# Environment setup
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log "No region configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export KENDRA_INDEX_NAME="qa-system-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="documents-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="qa-processor-${RANDOM_SUFFIX}"
    export KENDRA_ROLE_NAME="KendraServiceRole-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="LambdaQARole-${RANDOM_SUFFIX}"
    
    # Save environment variables for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
KENDRA_INDEX_NAME=${KENDRA_INDEX_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
KENDRA_ROLE_NAME=${KENDRA_ROLE_NAME}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_verbose "Environment variables set:"
    log_verbose "  AWS_REGION: ${AWS_REGION}"
    log_verbose "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    log_verbose "  RANDOM_SUFFIX: ${RANDOM_SUFFIX}"
    
    log "Environment setup completed."
}

# Create S3 bucket for documents
create_s3_bucket() {
    log "Creating S3 bucket for documents..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create S3 bucket: ${S3_BUCKET_NAME}"
        return 0
    fi
    
    # Check if bucket already exists
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        log "S3 bucket ${S3_BUCKET_NAME} already exists, skipping creation."
        return 0
    fi
    
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://${S3_BUCKET_NAME}"
    else
        aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}"
    fi
    
    # Enable versioning for document management
    aws s3api put-bucket-versioning \
        --bucket "${S3_BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    log "S3 bucket created successfully: ${S3_BUCKET_NAME}"
}

# Create IAM role for Kendra
create_kendra_iam_role() {
    log "Creating IAM role for Kendra..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Kendra IAM role: ${KENDRA_ROLE_NAME}"
        return 0
    fi
    
    # Check if role already exists
    if aws iam get-role --role-name "${KENDRA_ROLE_NAME}" &> /dev/null; then
        log "Kendra IAM role ${KENDRA_ROLE_NAME} already exists, skipping creation."
        KENDRA_ROLE_ARN=$(aws iam get-role --role-name "${KENDRA_ROLE_NAME}" --query 'Role.Arn' --output text)
        echo "KENDRA_ROLE_ARN=${KENDRA_ROLE_ARN}" >> "${SCRIPT_DIR}/.env"
        return 0
    fi
    
    # Create trust policy
    cat > /tmp/kendra-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "kendra.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    KENDRA_ROLE_ARN=$(aws iam create-role \
        --role-name "${KENDRA_ROLE_NAME}" \
        --assume-role-policy-document file:///tmp/kendra-trust-policy.json \
        --query 'Role.Arn' --output text)

    # Attach required policies
    aws iam attach-role-policy \
        --role-name "${KENDRA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess

    # Create custom policy for S3 access
    cat > /tmp/kendra-s3-policy.json << EOF
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
        "arn:aws:s3:::${S3_BUCKET_NAME}",
        "arn:aws:s3:::${S3_BUCKET_NAME}/*"
      ]
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name "${KENDRA_ROLE_NAME}" \
        --policy-name "KendraS3Access" \
        --policy-document file:///tmp/kendra-s3-policy.json

    echo "KENDRA_ROLE_ARN=${KENDRA_ROLE_ARN}" >> "${SCRIPT_DIR}/.env"
    
    # Wait for role propagation
    sleep 10
    
    log "Kendra IAM role created successfully: ${KENDRA_ROLE_ARN}"
}

# Create Kendra index
create_kendra_index() {
    log "Creating Kendra index..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Kendra index: ${KENDRA_INDEX_NAME}"
        return 0
    fi
    
    # Check if index already exists
    EXISTING_INDEX=$(aws kendra list-indices --query "IndexConfigurationSummaryItems[?Name=='${KENDRA_INDEX_NAME}'].Id" --output text)
    if [[ -n "$EXISTING_INDEX" ]]; then
        log "Kendra index ${KENDRA_INDEX_NAME} already exists with ID: ${EXISTING_INDEX}"
        echo "KENDRA_INDEX_ID=${EXISTING_INDEX}" >> "${SCRIPT_DIR}/.env"
        return 0
    fi
    
    KENDRA_INDEX_ID=$(aws kendra create-index \
        --name "${KENDRA_INDEX_NAME}" \
        --description "Intelligent document QA system index" \
        --role-arn "${KENDRA_ROLE_ARN}" \
        --query 'Id' --output text)

    echo "KENDRA_INDEX_ID=${KENDRA_INDEX_ID}" >> "${SCRIPT_DIR}/.env"
    
    log "Kendra index created successfully: ${KENDRA_INDEX_ID}"
    log "Waiting for Kendra index to become active (this may take 30-45 minutes)..."
    
    # Wait for index to become active
    aws kendra wait index-active --index-id "${KENDRA_INDEX_ID}"
    
    log "Kendra index is now active."
}

# Create Kendra data source
create_kendra_data_source() {
    log "Creating Kendra data source..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Kendra data source for S3 bucket: ${S3_BUCKET_NAME}"
        return 0
    fi
    
    # Create data source configuration
    cat > /tmp/s3-data-source-config.json << EOF
{
  "S3Configuration": {
    "BucketName": "${S3_BUCKET_NAME}",
    "InclusionPrefixes": ["documents/"],
    "DocumentsMetadataConfiguration": {
      "S3Prefix": "metadata/"
    }
  }
}
EOF

    DATA_SOURCE_ID=$(aws kendra create-data-source \
        --index-id "${KENDRA_INDEX_ID}" \
        --name "S3DocumentSource" \
        --type "S3" \
        --description "S3 data source for document indexing" \
        --configuration file:///tmp/s3-data-source-config.json \
        --role-arn "${KENDRA_ROLE_ARN}" \
        --query 'Id' --output text)

    echo "DATA_SOURCE_ID=${DATA_SOURCE_ID}" >> "${SCRIPT_DIR}/.env"
    
    log "Kendra data source created successfully: ${DATA_SOURCE_ID}"
}

# Create IAM role for Lambda
create_lambda_iam_role() {
    log "Creating IAM role for Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Lambda IAM role: ${LAMBDA_ROLE_NAME}"
        return 0
    fi
    
    # Check if role already exists
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &> /dev/null; then
        log "Lambda IAM role ${LAMBDA_ROLE_NAME} already exists, skipping creation."
        LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" --query 'Role.Arn' --output text)
        echo "LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> "${SCRIPT_DIR}/.env"
        return 0
    fi
    
    # Create trust policy
    cat > /tmp/lambda-trust-policy.json << 'EOF'
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
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
        --query 'Role.Arn' --output text)

    # Create custom policy for Kendra and Bedrock access
    cat > /tmp/lambda-permissions-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kendra:Query",
        "kendra:DescribeIndex"
      ],
      "Resource": "arn:aws:kendra:${AWS_REGION}:${AWS_ACCOUNT_ID}:index/${KENDRA_INDEX_ID}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel"
      ],
      "Resource": "arn:aws:bedrock:${AWS_REGION}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-name "QAPermissions" \
        --policy-document file:///tmp/lambda-permissions-policy.json

    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    echo "LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> "${SCRIPT_DIR}/.env"
    
    # Wait for role propagation
    sleep 10
    
    log "Lambda IAM role created successfully: ${LAMBDA_ROLE_ARN}"
}

# Deploy Lambda function
deploy_lambda_function() {
    log "Deploying Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would deploy Lambda function: ${LAMBDA_FUNCTION_NAME}"
        return 0
    fi
    
    # Check if function already exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        log "Lambda function ${LAMBDA_FUNCTION_NAME} already exists, updating code..."
        # Update existing function
        (cd /tmp && rm -rf qa-lambda && mkdir qa-lambda && cd qa-lambda && \
         cat > index.py << 'EOF'
import json
import boto3
import os

kendra = boto3.client('kendra')
bedrock = boto3.client('bedrock-runtime')

def lambda_handler(event, context):
    try:
        question = event.get('question', '')
        if not question:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Question is required'})
            }
        
        index_id = os.environ['KENDRA_INDEX_ID']
        
        # Query Kendra for relevant documents
        kendra_response = kendra.query(
            IndexId=index_id,
            QueryText=question,
            PageSize=5
        )
        
        # Extract relevant passages
        passages = []
        for item in kendra_response.get('ResultItems', []):
            if item.get('Type') == 'DOCUMENT':
                passages.append({
                    'text': item.get('DocumentExcerpt', {}).get('Text', ''),
                    'title': item.get('DocumentTitle', {}).get('Text', ''),
                    'uri': item.get('DocumentURI', '')
                })
        
        if not passages:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'question': question,
                    'answer': 'No relevant documents found to answer your question.',
                    'sources': []
                })
            }
        
        # Generate answer using Bedrock Claude
        context_text = '\n\n'.join([f"Document: {p['title']}\n{p['text']}" for p in passages])
        
        prompt = f"""Based on the following document excerpts, please answer this question: {question}

Document excerpts:
{context_text}

Please provide a comprehensive answer based only on the information in the documents. If the documents don't contain enough information to answer the question, please say so. Include relevant citations.

Answer:"""
        
        bedrock_response = bedrock.invoke_model(
            modelId='anthropic.claude-3-sonnet-20240229-v1:0',
            body=json.dumps({
                'anthropic_version': 'bedrock-2023-05-31',
                'max_tokens': 1000,
                'messages': [{'role': 'user', 'content': prompt}]
            })
        )
        
        response_body = json.loads(bedrock_response['body'].read())
        answer = response_body['content'][0]['text']
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'question': question,
                'answer': answer,
                'sources': [{'title': p['title'], 'uri': p['uri']} for p in passages]
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
         zip -r qa-function.zip index.py)
        
        aws lambda update-function-code \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --zip-file fileb:///tmp/qa-lambda/qa-function.zip
            
        aws lambda update-function-configuration \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --environment Variables="{KENDRA_INDEX_ID=${KENDRA_INDEX_ID}}"
        
        return 0
    fi
    
    # Create new function
    (cd /tmp && rm -rf qa-lambda && mkdir qa-lambda && cd qa-lambda && \
     cat > index.py << 'EOF'
import json
import boto3
import os

kendra = boto3.client('kendra')
bedrock = boto3.client('bedrock-runtime')

def lambda_handler(event, context):
    try:
        question = event.get('question', '')
        if not question:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Question is required'})
            }
        
        index_id = os.environ['KENDRA_INDEX_ID']
        
        # Query Kendra for relevant documents
        kendra_response = kendra.query(
            IndexId=index_id,
            QueryText=question,
            PageSize=5
        )
        
        # Extract relevant passages
        passages = []
        for item in kendra_response.get('ResultItems', []):
            if item.get('Type') == 'DOCUMENT':
                passages.append({
                    'text': item.get('DocumentExcerpt', {}).get('Text', ''),
                    'title': item.get('DocumentTitle', {}).get('Text', ''),
                    'uri': item.get('DocumentURI', '')
                })
        
        if not passages:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'question': question,
                    'answer': 'No relevant documents found to answer your question.',
                    'sources': []
                })
            }
        
        # Generate answer using Bedrock Claude
        context_text = '\n\n'.join([f"Document: {p['title']}\n{p['text']}" for p in passages])
        
        prompt = f"""Based on the following document excerpts, please answer this question: {question}

Document excerpts:
{context_text}

Please provide a comprehensive answer based only on the information in the documents. If the documents don't contain enough information to answer the question, please say so. Include relevant citations.

Answer:"""
        
        bedrock_response = bedrock.invoke_model(
            modelId='anthropic.claude-3-sonnet-20240229-v1:0',
            body=json.dumps({
                'anthropic_version': 'bedrock-2023-05-31',
                'max_tokens': 1000,
                'messages': [{'role': 'user', 'content': prompt}]
            })
        )
        
        response_body = json.loads(bedrock_response['body'].read())
        answer = response_body['content'][0]['text']
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'question': question,
                'answer': answer,
                'sources': [{'title': p['title'], 'uri': p['uri']} for p in passages]
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
     zip -r qa-function.zip index.py)

    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler index.lambda_handler \
        --zip-file fileb:///tmp/qa-lambda/qa-function.zip \
        --environment Variables="{KENDRA_INDEX_ID=${KENDRA_INDEX_ID}}" \
        --timeout 60 \
        --description "QA processor for intelligent document system"

    log "Lambda function deployed successfully: ${LAMBDA_FUNCTION_NAME}"
}

# Upload sample documents
upload_sample_documents() {
    log "Uploading sample documents..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would upload sample documents to S3"
        return 0
    fi
    
    # Create sample document
    cat > /tmp/sample-technical-doc.txt << 'EOF'
Technical Documentation - Cloud Infrastructure Best Practices

Introduction
This document covers best practices for implementing cloud infrastructure solutions.

Security Guidelines
- Always use encryption for data at rest and in transit
- Implement least privilege access controls
- Enable audit logging for all critical resources
- Regular security assessments should be conducted

Performance Optimization
- Use content delivery networks for global applications
- Implement auto-scaling based on demand metrics
- Monitor application performance continuously
- Optimize database queries and indexing strategies

Cost Management
- Implement resource tagging for cost allocation
- Use reserved instances for predictable workloads
- Regular cost reviews and optimization recommendations
- Implement budget alerts and cost controls

Compliance Requirements
- Data residency requirements must be met
- Regular compliance audits are mandatory
- Document all configuration changes
- Maintain backup and disaster recovery procedures
EOF

    # Upload to S3
    aws s3 cp /tmp/sample-technical-doc.txt "s3://${S3_BUCKET_NAME}/documents/technical-best-practices.txt"
    
    # Trigger Kendra synchronization
    aws kendra start-data-source-sync-job \
        --index-id "${KENDRA_INDEX_ID}" \
        --id "${DATA_SOURCE_ID}"
    
    log "Sample documents uploaded and indexing started."
}

# Test the deployment
test_deployment() {
    log "Testing the QA system deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would test the deployment"
        return 0
    fi
    
    # Wait a moment for document indexing
    log "Waiting for document indexing to complete..."
    sleep 30
    
    # Test with a sample question
    RESPONSE=$(aws lambda invoke \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --payload '{"question": "What are the security best practices mentioned in the documentation?"}' \
        /tmp/test-response.json)
    
    if [[ $? -eq 0 ]]; then
        log "Test invocation successful. Response saved to /tmp/test-response.json"
        if [[ "$VERBOSE" == "true" ]]; then
            log_verbose "Response: $(cat /tmp/test-response.json)"
        fi
    else
        log_error "Test invocation failed."
        return 1
    fi
}

# Cleanup temporary files
cleanup_temp_files() {
    log_verbose "Cleaning up temporary files..."
    rm -f /tmp/kendra-trust-policy.json
    rm -f /tmp/kendra-s3-policy.json
    rm -f /tmp/s3-data-source-config.json
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/lambda-permissions-policy.json
    rm -f /tmp/sample-technical-doc.txt
    rm -f /tmp/test-response.json
    rm -rf /tmp/qa-lambda
}

# Main deployment function
main() {
    log "Starting deployment of Intelligent Document QA System..."
    log "Log file: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN MODE - No actual resources will be created"
    fi
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_kendra_iam_role
    create_kendra_index
    create_kendra_data_source
    create_lambda_iam_role
    deploy_lambda_function
    upload_sample_documents
    test_deployment
    cleanup_temp_files
    
    log "Deployment completed successfully!"
    log ""
    log "Resource Summary:"
    log "  S3 Bucket: ${S3_BUCKET_NAME}"
    log "  Kendra Index: ${KENDRA_INDEX_NAME} (${KENDRA_INDEX_ID:-N/A})"
    log "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log "  Region: ${AWS_REGION}"
    log ""
    log "Environment variables saved to: ${SCRIPT_DIR}/.env"
    log "To clean up resources, run: ./destroy.sh"
    log ""
    log "Test your QA system with:"
    log "  aws lambda invoke --function-name ${LAMBDA_FUNCTION_NAME} \\"
    log "    --payload '{\"question\": \"Your question here\"}' response.json"
}

# Run main function
main "$@"