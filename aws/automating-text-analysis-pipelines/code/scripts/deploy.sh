#!/bin/bash

# =============================================================================
# AWS Comprehend NLP Pipeline Deployment Script
# =============================================================================
# This script deploys a complete Natural Language Processing pipeline using
# Amazon Comprehend for sentiment analysis, entity detection, and key phrase
# extraction with both real-time and batch processing capabilities.
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# Configuration and Variables
# =============================================================================

# Script metadata
SCRIPT_NAME="comprehend-nlp-deploy"
SCRIPT_VERSION="1.0"
LOG_FILE="/tmp/${SCRIPT_NAME}-$(date +%Y%m%d-%H%M%S).log"

# Default configuration
DEFAULT_REGION="us-east-1"
DEFAULT_MEMORY_SIZE=256
DEFAULT_TIMEOUT=60

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# =============================================================================
# Utility Functions
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or you don't have valid credentials."
        exit 1
    fi
    
    # Check if Python3 is available
    if ! command -v python3 &> /dev/null; then
        log_error "Python3 is required but not installed."
        exit 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some features may not work properly."
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        log_error "zip is required but not installed."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

check_permissions() {
    log_info "Checking AWS permissions..."
    
    local required_services=("comprehend" "s3" "lambda" "iam" "sts")
    local missing_permissions=()
    
    for service in "${required_services[@]}"; do
        case $service in
            "comprehend")
                if ! aws comprehend list-document-classifiers --max-results 1 &> /dev/null; then
                    missing_permissions+=("Amazon Comprehend")
                fi
                ;;
            "s3")
                if ! aws s3 ls &> /dev/null; then
                    missing_permissions+=("Amazon S3")
                fi
                ;;
            "lambda")
                if ! aws lambda list-functions --max-items 1 &> /dev/null; then
                    missing_permissions+=("AWS Lambda")
                fi
                ;;
            "iam")
                if ! aws iam list-roles --max-items 1 &> /dev/null; then
                    missing_permissions+=("AWS IAM")
                fi
                ;;
        esac
    done
    
    if [ ${#missing_permissions[@]} -ne 0 ]; then
        log_error "Missing permissions for: ${missing_permissions[*]}"
        exit 1
    fi
    
    log_success "Permissions check completed"
}

generate_random_suffix() {
    if command -v aws &> /dev/null; then
        aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)"
    else
        echo "$(date +%s | tail -c 6)"
    fi
}

wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local max_attempts=${3:-30}
    local sleep_time=${4:-10}
    
    log_info "Waiting for $resource_type '$resource_name' to be ready..."
    
    for ((i=1; i<=max_attempts; i++)); do
        case $resource_type in
            "iam-role")
                if aws iam get-role --role-name "$resource_name" &> /dev/null; then
                    log_success "$resource_type '$resource_name' is ready"
                    return 0
                fi
                ;;
            "lambda-function")
                local status=$(aws lambda get-function --function-name "$resource_name" --query 'Configuration.State' --output text 2>/dev/null || echo "UNKNOWN")
                if [ "$status" = "Active" ]; then
                    log_success "$resource_type '$resource_name' is ready"
                    return 0
                fi
                ;;
        esac
        
        if [ $i -eq $max_attempts ]; then
            log_error "Timeout waiting for $resource_type '$resource_name'"
            return 1
        fi
        
        log_info "Attempt $i/$max_attempts: $resource_type not ready yet, waiting ${sleep_time}s..."
        sleep $sleep_time
    done
}

# =============================================================================
# Resource Creation Functions
# =============================================================================

create_s3_buckets() {
    log_info "Creating S3 buckets..."
    
    # Create input bucket
    if aws s3 ls "s3://${COMPREHEND_BUCKET}" 2>/dev/null; then
        log_warning "S3 bucket ${COMPREHEND_BUCKET} already exists"
    else
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3 mb "s3://${COMPREHEND_BUCKET}"
        else
            aws s3 mb "s3://${COMPREHEND_BUCKET}" --region "$AWS_REGION"
        fi
        log_success "Created S3 bucket: ${COMPREHEND_BUCKET}"
    fi
    
    # Create output bucket
    if aws s3 ls "s3://${COMPREHEND_BUCKET}-output" 2>/dev/null; then
        log_warning "S3 bucket ${COMPREHEND_BUCKET}-output already exists"
    else
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3 mb "s3://${COMPREHEND_BUCKET}-output"
        else
            aws s3 mb "s3://${COMPREHEND_BUCKET}-output" --region "$AWS_REGION"
        fi
        log_success "Created S3 bucket: ${COMPREHEND_BUCKET}-output"
    fi
    
    # Upload sample data
    log_info "Creating and uploading sample data..."
    
    cat > sample-reviews.txt << 'EOF'
The customer service at this restaurant was absolutely terrible. The food was cold and the staff was rude.
I love this product! The quality is amazing and the delivery was super fast. Highly recommend!
The hotel room was okay, nothing special. The location was convenient but the amenities were lacking.
Outstanding experience! The team went above and beyond to help us. Five stars!
Very disappointed with the purchase. The item broke after just one week of use.
EOF
    
    aws s3 cp sample-reviews.txt "s3://${COMPREHEND_BUCKET}/input/"
    log_success "Uploaded sample data to S3"
}

create_iam_roles() {
    log_info "Creating IAM roles and policies..."
    
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
    
    # Check if role already exists
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        log_warning "IAM role ${IAM_ROLE_NAME} already exists"
    else
        aws iam create-role \
            --role-name "${IAM_ROLE_NAME}" \
            --assume-role-policy-document file://lambda-trust-policy.json
        log_success "Created IAM role: ${IAM_ROLE_NAME}"
    fi
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for Comprehend and S3 access
    cat > comprehend-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "comprehend:DetectSentiment",
        "comprehend:DetectEntities",
        "comprehend:DetectKeyPhrases",
        "comprehend:DetectLanguage",
        "comprehend:DetectSyntax",
        "comprehend:DetectTargetedSentiment",
        "comprehend:StartDocumentClassificationJob",
        "comprehend:StartEntitiesDetectionJob",
        "comprehend:StartKeyPhrasesDetectionJob",
        "comprehend:StartSentimentDetectionJob",
        "comprehend:DescribeDocumentClassificationJob",
        "comprehend:DescribeEntitiesDetectionJob",
        "comprehend:DescribeKeyPhrasesDetectionJob",
        "comprehend:DescribeSentimentDetectionJob"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${COMPREHEND_BUCKET}",
        "arn:aws:s3:::${COMPREHEND_BUCKET}/*",
        "arn:aws:s3:::${COMPREHEND_BUCKET}-output",
        "arn:aws:s3:::${COMPREHEND_BUCKET}-output/*"
      ]
    }
  ]
}
EOF
    
    # Create and attach custom policy
    local policy_name="ComprehendLambdaPolicy-${RANDOM_SUFFIX}"
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}" &> /dev/null; then
        log_warning "IAM policy ${policy_name} already exists"
    else
        aws iam create-policy \
            --policy-name "${policy_name}" \
            --policy-document file://comprehend-policy.json
        log_success "Created IAM policy: ${policy_name}"
    fi
    
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
    
    # Create Comprehend service role
    cat > comprehend-service-role-policy.json << 'EOF'
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
    
    local comprehend_role_name="ComprehendServiceRole-${RANDOM_SUFFIX}"
    if aws iam get-role --role-name "${comprehend_role_name}" &> /dev/null; then
        log_warning "IAM role ${comprehend_role_name} already exists"
    else
        aws iam create-role \
            --role-name "${comprehend_role_name}" \
            --assume-role-policy-document file://comprehend-service-role-policy.json
        log_success "Created Comprehend service role: ${comprehend_role_name}"
    fi
    
    # Create S3 access policy for Comprehend
    cat > comprehend-s3-policy.json << EOF
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
        "arn:aws:s3:::${COMPREHEND_BUCKET}",
        "arn:aws:s3:::${COMPREHEND_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::${COMPREHEND_BUCKET}-output",
        "arn:aws:s3:::${COMPREHEND_BUCKET}-output/*"
      ]
    }
  ]
}
EOF
    
    local comprehend_s3_policy_name="ComprehendS3Policy-${RANDOM_SUFFIX}"
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${comprehend_s3_policy_name}" &> /dev/null; then
        log_warning "IAM policy ${comprehend_s3_policy_name} already exists"
    else
        aws iam create-policy \
            --policy-name "${comprehend_s3_policy_name}" \
            --policy-document file://comprehend-s3-policy.json
        log_success "Created Comprehend S3 policy: ${comprehend_s3_policy_name}"
    fi
    
    aws iam attach-role-policy \
        --role-name "${comprehend_role_name}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${comprehend_s3_policy_name}"
    
    # Wait for IAM propagation
    wait_for_resource "iam-role" "${IAM_ROLE_NAME}" 30 5
}

create_lambda_function() {
    log_info "Creating Lambda function..."
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import uuid
from datetime import datetime

comprehend = boto3.client('comprehend')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Get text from S3 event or direct invocation
        if 'Records' in event:
            # S3 event trigger
            bucket = event['Records'][0]['s3']['bucket']['name']
            key = event['Records'][0]['s3']['object']['key']
            
            # Get text from S3
            response = s3.get_object(Bucket=bucket, Key=key)
            text = response['Body'].read().decode('utf-8')
        else:
            # Direct invocation
            text = event.get('text', '')
            bucket = event.get('output_bucket', '')
        
        if not text:
            return {'statusCode': 400, 'body': 'No text provided'}
        
        # Detect language first
        language_response = comprehend.detect_dominant_language(Text=text)
        language_code = language_response['Languages'][0]['LanguageCode']
        
        # Perform sentiment analysis
        sentiment_response = comprehend.detect_sentiment(
            Text=text,
            LanguageCode=language_code
        )
        
        # Extract entities
        entities_response = comprehend.detect_entities(
            Text=text,
            LanguageCode=language_code
        )
        
        # Extract key phrases
        keyphrases_response = comprehend.detect_key_phrases(
            Text=text,
            LanguageCode=language_code
        )
        
        # Compile results
        results = {
            'timestamp': datetime.now().isoformat(),
            'text': text,
            'language': language_code,
            'sentiment': {
                'sentiment': sentiment_response['Sentiment'],
                'scores': sentiment_response['SentimentScore']
            },
            'entities': entities_response['Entities'],
            'key_phrases': keyphrases_response['KeyPhrases']
        }
        
        # Save results to S3 if output bucket provided
        if bucket:
            output_key = f"processed/{uuid.uuid4()}.json"
            s3.put_object(
                Bucket=bucket + '-output',
                Key=output_key,
                Body=json.dumps(results, indent=2),
                ContentType='application/json'
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps(results)
        }
        
    except Exception as e:
        print(f"Error processing text: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Create deployment package
    zip -r lambda-function.zip lambda_function.py
    
    # Check if function already exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} already exists, updating code..."
        aws lambda update-function-code \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --zip-file fileb://lambda-function.zip
    else
        # Wait a bit more for IAM propagation
        log_info "Waiting for IAM role propagation..."
        sleep 10
        
        aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}" \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://lambda-function.zip \
            --timeout "${LAMBDA_TIMEOUT}" \
            --memory-size "${LAMBDA_MEMORY}"
        
        log_success "Created Lambda function: ${LAMBDA_FUNCTION_NAME}"
    fi
    
    # Wait for function to be active
    wait_for_resource "lambda-function" "${LAMBDA_FUNCTION_NAME}" 30 5
}

create_training_data() {
    log_info "Creating custom classification training data..."
    
    mkdir -p training-data
    
    # Create training manifest
    cat > training-manifest.csv << 'EOF'
complaints,The service was terrible and I want my money back.
complaints,This product broke after one day of use.
complaints,The staff was rude and unhelpful.
complaints,I am very disappointed with this purchase.
complaints,The quality is much worse than expected.
compliments,Excellent service and great product quality!
compliments,The staff was very helpful and professional.
compliments,I highly recommend this product to everyone.
compliments,Outstanding customer service experience.
compliments,The quality exceeded my expectations.
neutral,The product is okay for the price.
neutral,Average service, nothing special.
neutral,The item works as described.
neutral,Standard quality as expected.
neutral,Regular customer service interaction.
EOF
    
    # Upload training data
    aws s3 cp training-manifest.csv "s3://${COMPREHEND_BUCKET}/training/"
    log_success "Created and uploaded custom classification training data"
}

# =============================================================================
# Testing Functions
# =============================================================================

test_deployment() {
    log_info "Testing the deployment..."
    
    # Test Lambda function
    log_info "Testing Lambda function with sample text..."
    
    local test_payload='{
        "text": "I absolutely love this new product! The quality is exceptional and the customer service team was incredibly helpful.",
        "output_bucket": "'${COMPREHEND_BUCKET}'"
    }'
    
    if aws lambda invoke \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --payload "$test_payload" \
        --cli-binary-format raw-in-base64-out \
        response.json > /dev/null 2>&1; then
        
        if command -v jq &> /dev/null; then
            local sentiment=$(cat response.json | jq -r '.body | fromjson | .sentiment.sentiment' 2>/dev/null || echo "unknown")
            log_success "Lambda test completed - detected sentiment: ${sentiment}"
        else
            log_success "Lambda test completed successfully"
        fi
    else
        log_error "Lambda function test failed"
        return 1
    fi
    
    # Verify S3 buckets
    log_info "Verifying S3 bucket access..."
    if aws s3 ls "s3://${COMPREHEND_BUCKET}" > /dev/null 2>&1 && \
       aws s3 ls "s3://${COMPREHEND_BUCKET}-output" > /dev/null 2>&1; then
        log_success "S3 buckets are accessible"
    else
        log_error "S3 bucket verification failed"
        return 1
    fi
    
    log_success "All tests passed successfully!"
}

# =============================================================================
# Main Deployment Function
# =============================================================================

deploy_infrastructure() {
    log_info "Starting AWS Comprehend NLP Pipeline deployment..."
    
    # Set environment variables
    export AWS_REGION=${AWS_REGION:-$(aws configure get region || echo "$DEFAULT_REGION")}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(generate_random_suffix)
    export COMPREHEND_BUCKET="comprehend-nlp-pipeline-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="comprehend-processor-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="ComprehendLambdaRole-${RANDOM_SUFFIX}"
    export LAMBDA_MEMORY=${LAMBDA_MEMORY_SIZE:-$DEFAULT_MEMORY_SIZE}
    export LAMBDA_TIMEOUT=${LAMBDA_TIMEOUT_SECONDS:-$DEFAULT_TIMEOUT}
    
    log_info "Deployment configuration:"
    log_info "  AWS Region: ${AWS_REGION}"
    log_info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "  S3 Bucket: ${COMPREHEND_BUCKET}"
    log_info "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log_info "  IAM Role: ${IAM_ROLE_NAME}"
    log_info "  Random Suffix: ${RANDOM_SUFFIX}"
    
    # Save configuration for cleanup script
    cat > deployment-config.env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
COMPREHEND_BUCKET=${COMPREHEND_BUCKET}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
IAM_ROLE_NAME=${IAM_ROLE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')
EOF
    
    # Execute deployment steps
    create_s3_buckets
    create_iam_roles
    create_lambda_function
    create_training_data
    
    # Test the deployment
    test_deployment
    
    log_success "AWS Comprehend NLP Pipeline deployed successfully!"
    log_info "Configuration saved to: deployment-config.env"
    log_info "Log file available at: $LOG_FILE"
    
    # Display useful information
    echo ""
    echo "=== Deployment Summary ==="
    echo "S3 Input Bucket: ${COMPREHEND_BUCKET}"
    echo "S3 Output Bucket: ${COMPREHEND_BUCKET}-output"
    echo "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "IAM Role: ${IAM_ROLE_NAME}"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Test real-time processing:"
    echo "   aws lambda invoke --function-name ${LAMBDA_FUNCTION_NAME} --payload '{\"text\":\"Your text here\"}' response.json"
    echo ""
    echo "2. Upload documents for batch processing to:"
    echo "   s3://${COMPREHEND_BUCKET}/input/"
    echo ""
    echo "3. Check processed results in:"
    echo "   s3://${COMPREHEND_BUCKET}-output/"
    echo ""
    echo "4. To clean up resources, run:"
    echo "   ./destroy.sh"
}

# =============================================================================
# Help and Usage
# =============================================================================

show_help() {
    cat << EOF
AWS Comprehend NLP Pipeline Deployment Script

USAGE:
    $0 [OPTIONS]

DESCRIPTION:
    Deploys a complete Natural Language Processing pipeline using Amazon Comprehend
    for sentiment analysis, entity detection, and key phrase extraction.

OPTIONS:
    -r, --region REGION         AWS region (default: current AWS CLI region or us-east-1)
    -m, --memory SIZE          Lambda memory size in MB (default: 256)
    -t, --timeout SECONDS     Lambda timeout in seconds (default: 60)
    -h, --help                 Show this help message
    -v, --version              Show script version
    --dry-run                  Show what would be deployed without making changes
    --force                    Force deployment even if resources exist

EXAMPLES:
    $0                         # Deploy with default settings
    $0 --region us-west-2      # Deploy to specific region
    $0 --memory 512 --timeout 120  # Deploy with custom Lambda settings
    $0 --dry-run               # Preview deployment without changes

REQUIREMENTS:
    - AWS CLI v2 installed and configured
    - Python3 installed
    - zip utility available
    - Appropriate AWS permissions for Comprehend, S3, Lambda, and IAM

For more information, see the recipe documentation.
EOF
}

show_version() {
    echo "${SCRIPT_NAME} version ${SCRIPT_VERSION}"
}

# =============================================================================
# Argument Parsing
# =============================================================================

FORCE_DEPLOY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -m|--memory)
            LAMBDA_MEMORY_SIZE="$2"
            shift 2
            ;;
        -t|--timeout)
            LAMBDA_TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        --force)
            FORCE_DEPLOY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            show_version
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo "=== AWS Comprehend NLP Pipeline Deployment Script ==="
    echo "Version: ${SCRIPT_VERSION}"
    echo "Log file: ${LOG_FILE}"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN MODE - No resources will be created"
        log_info "This deployment would create:"
        log_info "  - 2 S3 buckets for input and output"
        log_info "  - 2 IAM roles for Lambda and Comprehend"
        log_info "  - 2 IAM policies for service permissions"
        log_info "  - 1 Lambda function for real-time processing"
        log_info "  - Sample training data for custom classification"
        exit 0
    fi
    
    # Run prerequisite checks
    check_prerequisites
    check_permissions
    
    # Start deployment
    deploy_infrastructure
    
    log_success "Deployment completed successfully!"
    echo "Check the log file for detailed information: $LOG_FILE"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi