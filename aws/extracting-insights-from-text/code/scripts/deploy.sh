#!/bin/bash

# =============================================================================
# Amazon Comprehend NLP Solution - Deployment Script
# =============================================================================
# This script deploys a complete NLP solution using Amazon Comprehend
# including real-time processing, batch jobs, and event-driven automation.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for Comprehend, Lambda, S3, EventBridge
# - Estimated cost: $20-50 for running all examples
#
# Usage: ./deploy.sh [--dry-run]
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=${1:-""}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    if [[ -n "${COMPREHEND_BUCKET:-}" ]]; then
        aws s3 rm "s3://${COMPREHEND_BUCKET}" --recursive 2>/dev/null || true
        aws s3 rb "s3://${COMPREHEND_BUCKET}" 2>/dev/null || true
        aws s3 rm "s3://${COMPREHEND_BUCKET}-output" --recursive 2>/dev/null || true
        aws s3 rb "s3://${COMPREHEND_BUCKET}-output" 2>/dev/null || true
    fi
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ "${AWS_CLI_VERSION}" < "2.0" ]]; then
        log_error "AWS CLI version 2.0 or higher required. Current version: ${AWS_CLI_VERSION}"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required tools
    for tool in jq zip; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool not found. Please install $tool."
            exit 1
        fi
    done
    
    log "Prerequisites check passed."
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "No region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    export COMPREHEND_BUCKET="comprehend-nlp-${RANDOM_SUFFIX}"
    export COMPREHEND_ROLE="AmazonComprehendServiceRole-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE="ComprehendLambdaRole-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="comprehend-processor-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_RULE_NAME="comprehend-s3-processing-${RANDOM_SUFFIX}"
    
    # Create temporary directory for working files
    export TEMP_DIR="/tmp/comprehend-deploy-${RANDOM_SUFFIX}"
    mkdir -p "$TEMP_DIR"
    
    log "Environment variables configured:"
    log_info "  AWS_REGION: ${AWS_REGION}"
    log_info "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    log_info "  COMPREHEND_BUCKET: ${COMPREHEND_BUCKET}"
    log_info "  TEMP_DIR: ${TEMP_DIR}"
    
    # Save configuration for cleanup script
    cat > "${SCRIPT_DIR}/deploy-config.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
COMPREHEND_BUCKET=${COMPREHEND_BUCKET}
COMPREHEND_ROLE=${COMPREHEND_ROLE}
LAMBDA_ROLE=${LAMBDA_ROLE}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
EVENTBRIDGE_RULE_NAME=${EVENTBRIDGE_RULE_NAME}
TEMP_DIR=${TEMP_DIR}
EOF
}

# Create S3 buckets and sample data
create_s3_resources() {
    log "Creating S3 buckets and sample data..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log_info "DRY RUN: Would create S3 buckets and sample data"
        return 0
    fi
    
    # Create S3 buckets
    aws s3 mb "s3://${COMPREHEND_BUCKET}" --region "${AWS_REGION}"
    aws s3 mb "s3://${COMPREHEND_BUCKET}-output" --region "${AWS_REGION}"
    
    # Create sample text files
    mkdir -p "${TEMP_DIR}/nlp-samples"
    
    # Customer feedback samples
    cat > "${TEMP_DIR}/nlp-samples/review1.txt" << 'EOF'
This product is absolutely amazing! The quality exceeded my expectations and the customer service was outstanding. I would definitely recommend this to anyone looking for a reliable solution.
EOF
    
    cat > "${TEMP_DIR}/nlp-samples/review2.txt" << 'EOF'
The device stopped working after just two weeks. Very disappointed with the build quality. The support team was unhelpful and took forever to respond.
EOF
    
    cat > "${TEMP_DIR}/nlp-samples/review3.txt" << 'EOF'
The product is okay, nothing special. It works as described but doesn't stand out from similar products. Price is reasonable for what you get.
EOF
    
    # Support ticket samples
    cat > "${TEMP_DIR}/nlp-samples/support1.txt" << 'EOF'
Customer reporting login issues with mobile app. Error message: "Invalid credentials" appears even with correct password. Customer using iPhone 12, iOS 15.2.
EOF
    
    cat > "${TEMP_DIR}/nlp-samples/support2.txt" << 'EOF'
Billing inquiry - customer charged twice for premium subscription. Transaction dates: March 15th and March 16th. Customer account: premium-user@example.com
EOF
    
    # Topic modeling samples
    cat > "${TEMP_DIR}/nlp-samples/topic1.txt" << 'EOF'
Our cloud infrastructure migration was successful. The new serverless architecture improved scalability and reduced costs by 40%. DevOps team recommends similar approach for other applications.
EOF
    
    cat > "${TEMP_DIR}/nlp-samples/topic2.txt" << 'EOF'
The mobile application user interface needs improvement. Customer feedback indicates confusion with navigation menu. UX team should prioritize mobile design updates.
EOF
    
    cat > "${TEMP_DIR}/nlp-samples/topic3.txt" << 'EOF'
Security audit revealed several vulnerabilities in payment processing system. Encryption protocols need updating. Compliance team requires immediate action on PCI DSS requirements.
EOF
    
    # Upload sample files to S3
    aws s3 cp "${TEMP_DIR}/nlp-samples/" "s3://${COMPREHEND_BUCKET}/input/" --recursive
    aws s3 cp "${TEMP_DIR}/nlp-samples/topic1.txt" "s3://${COMPREHEND_BUCKET}/topics/"
    aws s3 cp "${TEMP_DIR}/nlp-samples/topic2.txt" "s3://${COMPREHEND_BUCKET}/topics/"
    aws s3 cp "${TEMP_DIR}/nlp-samples/topic3.txt" "s3://${COMPREHEND_BUCKET}/topics/"
    
    log "S3 resources created successfully"
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log_info "DRY RUN: Would create IAM roles"
        return 0
    fi
    
    # Create trust policy for Comprehend service
    cat > "${TEMP_DIR}/comprehend-trust-policy.json" << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "comprehend.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create Comprehend service role
    aws iam create-role \
        --role-name "${COMPREHEND_ROLE}" \
        --assume-role-policy-document "file://${TEMP_DIR}/comprehend-trust-policy.json" \
        --description "Service role for Amazon Comprehend batch processing jobs"
    
    # Attach policies to Comprehend role
    aws iam attach-role-policy \
        --role-name "${COMPREHEND_ROLE}" \
        --policy-arn "arn:aws:iam::aws:policy/ComprehendFullAccess"
    
    aws iam attach-role-policy \
        --role-name "${COMPREHEND_ROLE}" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess"
    
    export COMPREHEND_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${COMPREHEND_ROLE}"
    
    # Create Lambda trust policy
    cat > "${TEMP_DIR}/lambda-trust-policy.json" << 'EOF'
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
    
    # Create Lambda execution role
    aws iam create-role \
        --role-name "${LAMBDA_ROLE}" \
        --assume-role-policy-document "file://${TEMP_DIR}/lambda-trust-policy.json" \
        --description "Execution role for Comprehend Lambda function"
    
    # Attach policies to Lambda role
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE}" \
        --policy-arn "arn:aws:iam::aws:policy/ComprehendReadOnlyAccess"
    
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE}"
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 15
    
    log "IAM roles created successfully"
}

# Create Lambda function
create_lambda_function() {
    log "Creating Lambda function..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log_info "DRY RUN: Would create Lambda function"
        return 0
    fi
    
    # Create Lambda function code
    cat > "${TEMP_DIR}/comprehend-processor.py" << 'EOF'
import json
import boto3
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

comprehend = boto3.client('comprehend')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Handle different event types
        if 'Records' in event:
            # S3 event
            for record in event['Records']:
                bucket = record['s3']['bucket']['name']
                key = record['s3']['object']['key']
                
                # Get object from S3
                response = s3.get_object(Bucket=bucket, Key=key)
                text = response['Body'].read().decode('utf-8')
                
                # Process the text
                result = process_text(text)
                
                # Store result back to S3
                output_key = f"processed/{key}.json"
                s3.put_object(
                    Bucket=f"{bucket}-output",
                    Key=output_key,
                    Body=json.dumps(result),
                    ContentType='application/json'
                )
                
                logger.info(f"Processed {key} and stored result at {output_key}")
        
        else:
            # Direct invocation
            text = event.get('text', '')
            if not text:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'No text provided'})
                }
            
            result = process_text(text)
            
            return {
                'statusCode': 200,
                'body': json.dumps(result)
            }
            
    except Exception as e:
        logger.error(f"Error processing text: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def process_text(text):
    """Process text through multiple Comprehend APIs"""
    
    # Truncate text if too long for real-time processing
    if len(text) > 5000:
        text = text[:5000]
    
    result = {}
    
    try:
        # Sentiment analysis
        sentiment_response = comprehend.detect_sentiment(
            Text=text,
            LanguageCode='en'
        )
        result['sentiment'] = {
            'sentiment': sentiment_response['Sentiment'],
            'scores': sentiment_response['SentimentScore']
        }
        
        # Entity detection
        entities_response = comprehend.detect_entities(
            Text=text,
            LanguageCode='en'
        )
        result['entities'] = [
            {
                'text': entity['Text'],
                'type': entity['Type'],
                'score': entity['Score']
            }
            for entity in entities_response['Entities']
        ]
        
        # Key phrase extraction
        key_phrases_response = comprehend.detect_key_phrases(
            Text=text,
            LanguageCode='en'
        )
        result['key_phrases'] = [
            {
                'text': phrase['Text'],
                'score': phrase['Score']
            }
            for phrase in key_phrases_response['KeyPhrases']
        ]
        
        # Language detection
        language_response = comprehend.detect_dominant_language(Text=text)
        result['language'] = language_response['Languages'][0] if language_response['Languages'] else None
        
    except Exception as e:
        logger.error(f"Error in Comprehend processing: {str(e)}")
        result['error'] = str(e)
    
    return result
EOF
    
    # Create deployment package
    cd "${TEMP_DIR}"
    zip comprehend-processor.zip comprehend-processor.py
    
    # Create Lambda function
    export LAMBDA_ARN=$(aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler comprehend-processor.lambda_handler \
        --zip-file fileb://comprehend-processor.zip \
        --description "Real-time text processing with Amazon Comprehend" \
        --timeout 60 \
        --memory-size 256 \
        --query 'FunctionArn' --output text)
    
    log "Lambda function created: ${LAMBDA_ARN}"
}

# Create EventBridge rule for automation
create_eventbridge_rule() {
    log "Creating EventBridge rule for automated processing..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log_info "DRY RUN: Would create EventBridge rule"
        return 0
    fi
    
    # Create EventBridge rule for S3 events
    aws events put-rule \
        --name "${EVENTBRIDGE_RULE_NAME}" \
        --event-pattern "{
          \"source\": [\"aws.s3\"],
          \"detail-type\": [\"Object Created\"],
          \"detail\": {
            \"bucket\": {
              \"name\": [\"${COMPREHEND_BUCKET}\"]
            }
          }
        }" \
        --description "Trigger Comprehend processing when files are uploaded to S3"
    
    # Add Lambda target to EventBridge rule
    aws events put-targets \
        --rule "${EVENTBRIDGE_RULE_NAME}" \
        --targets "Id=1,Arn=${LAMBDA_ARN}"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id "eventbridge-invoke-${RANDOM_SUFFIX}" \
        --action "lambda:InvokeFunction" \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}"
    
    log "EventBridge rule created successfully"
}

# Start batch processing jobs
start_batch_jobs() {
    log "Starting batch processing jobs..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log_info "DRY RUN: Would start batch processing jobs"
        return 0
    fi
    
    # Start sentiment analysis job
    export SENTIMENT_JOB_ID=$(aws comprehend start-sentiment-detection-job \
        --job-name "sentiment-analysis-${RANDOM_SUFFIX}" \
        --language-code en \
        --input-data-config "S3Uri=s3://${COMPREHEND_BUCKET}/input/" \
        --output-data-config "S3Uri=s3://${COMPREHEND_BUCKET}-output/sentiment/" \
        --data-access-role-arn "${COMPREHEND_ROLE_ARN}" \
        --query 'JobId' --output text)
    
    log_info "Started sentiment analysis job: ${SENTIMENT_JOB_ID}"
    
    # Start entity detection job
    export ENTITIES_JOB_ID=$(aws comprehend start-entities-detection-job \
        --job-name "entities-detection-${RANDOM_SUFFIX}" \
        --language-code en \
        --input-data-config "S3Uri=s3://${COMPREHEND_BUCKET}/input/" \
        --output-data-config "S3Uri=s3://${COMPREHEND_BUCKET}-output/entities/" \
        --data-access-role-arn "${COMPREHEND_ROLE_ARN}" \
        --query 'JobId' --output text)
    
    log_info "Started entity detection job: ${ENTITIES_JOB_ID}"
    
    # Start topic modeling job
    export TOPICS_JOB_ID=$(aws comprehend start-topics-detection-job \
        --job-name "topics-detection-${RANDOM_SUFFIX}" \
        --input-data-config "S3Uri=s3://${COMPREHEND_BUCKET}/topics/" \
        --output-data-config "S3Uri=s3://${COMPREHEND_BUCKET}-output/topics/" \
        --data-access-role-arn "${COMPREHEND_ROLE_ARN}" \
        --number-of-topics 3 \
        --query 'JobId' --output text)
    
    log_info "Started topic modeling job: ${TOPICS_JOB_ID}"
    
    # Save job IDs for monitoring
    cat >> "${SCRIPT_DIR}/deploy-config.env" << EOF
SENTIMENT_JOB_ID=${SENTIMENT_JOB_ID}
ENTITIES_JOB_ID=${ENTITIES_JOB_ID}
TOPICS_JOB_ID=${TOPICS_JOB_ID}
LAMBDA_ARN=${LAMBDA_ARN}
EOF
    
    log "Batch processing jobs started successfully"
}

# Test the deployment
test_deployment() {
    log "Testing deployment..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log_info "DRY RUN: Would test deployment"
        return 0
    fi
    
    # Test Lambda function with sample text
    aws lambda invoke \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --payload '{"text": "I love this amazing product! The customer service at TechCorp was excellent and very responsive."}' \
        --output json \
        "${TEMP_DIR}/test-response.json"
    
    if [[ $? -eq 0 ]]; then
        log_info "Lambda function test successful"
        log_info "Response: $(cat ${TEMP_DIR}/test-response.json | jq -r '.body' | jq '.')"
    else
        log_error "Lambda function test failed"
    fi
    
    # Test real-time Comprehend APIs
    aws comprehend detect-sentiment \
        --language-code en \
        --text "This product is fantastic!" \
        --output json > "${TEMP_DIR}/sentiment-test.json"
    
    if [[ $? -eq 0 ]]; then
        log_info "Direct Comprehend sentiment test successful"
        log_info "Sentiment: $(cat ${TEMP_DIR}/sentiment-test.json | jq -r '.Sentiment')"
    else
        log_error "Direct Comprehend sentiment test failed"
    fi
    
    log "Deployment testing completed"
}

# Main deployment function
main() {
    log "Starting Amazon Comprehend NLP Solution deployment..."
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log_info "Running in DRY RUN mode - no resources will be created"
    fi
    
    check_prerequisites
    setup_environment
    create_s3_resources
    create_iam_roles
    create_lambda_function
    create_eventbridge_rule
    start_batch_jobs
    test_deployment
    
    log "Deployment completed successfully!"
    log ""
    log "===== DEPLOYMENT SUMMARY ====="
    log "AWS Region: ${AWS_REGION}"
    log "S3 Input Bucket: ${COMPREHEND_BUCKET}"
    log "S3 Output Bucket: ${COMPREHEND_BUCKET}-output"
    log "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log "EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    log "Comprehend Role: ${COMPREHEND_ROLE}"
    log "Lambda Role: ${LAMBDA_ROLE}"
    log ""
    log "Configuration saved to: ${SCRIPT_DIR}/deploy-config.env"
    log "Log file: ${LOG_FILE}"
    log ""
    log "Next steps:"
    log "1. Monitor batch jobs: aws comprehend list-sentiment-detection-jobs"
    log "2. Test Lambda function: aws lambda invoke --function-name ${LAMBDA_FUNCTION_NAME} --payload '{\"text\":\"Your text here\"}' response.json"
    log "3. Check S3 output bucket for results: aws s3 ls s3://${COMPREHEND_BUCKET}-output/"
    log "4. When finished, run: ./destroy.sh"
    log ""
    log "Estimated monthly cost: $20-50 (depends on usage)"
}

# Run main function
main "$@"