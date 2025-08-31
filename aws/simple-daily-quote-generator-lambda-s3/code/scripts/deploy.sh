#!/bin/bash

# deploy.sh - Simple Daily Quote Generator with Lambda and S3
# This script deploys a serverless quote API using AWS Lambda and S3
# 
# Usage: ./deploy.sh [--dry-run] [--verbose]
# 
# Prerequisites:
# - AWS CLI v2.0 or later installed and configured
# - IAM permissions for Lambda, S3, and IAM operations
# - jq installed for JSON processing (optional but recommended)

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="/tmp/quote-generator-deploy-$(date +%Y%m%d_%H%M%S).log"

# Default values
DRY_RUN=false
VERBOSE=false

# Resource configuration
FUNCTION_NAME="daily-quote-generator"
BUCKET_PREFIX="daily-quotes"
ROLE_PREFIX="lambda-s3-role"

# Logging functions
log() {
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

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check log file: $LOG_FILE"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partially created resources..."
    
    # Attempt to delete resources that might have been created
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        aws s3 rm "s3://$BUCKET_NAME" --recursive 2>/dev/null || true
        aws s3 rb "s3://$BUCKET_NAME" 2>/dev/null || true
    fi
    
    if [[ -n "${ROLE_NAME:-}" ]]; then
        aws iam detach-role-policy --role-name "$ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
        aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "S3ReadPolicy" 2>/dev/null || true
        aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || true
    fi
    
    if aws lambda get-function --function-name "$FUNCTION_NAME" &>/dev/null; then
        aws lambda delete-function-url-config --function-name "$FUNCTION_NAME" 2>/dev/null || true
        aws lambda delete-function --function-name "$FUNCTION_NAME" 2>/dev/null || true
    fi
}

trap cleanup_on_error ERR

# Parse command line arguments
parse_args() {
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
                echo "  --verbose   Enable verbose output"
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2.0 or later."
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$aws_version" | cut -d. -f1) -lt 2 ]]; then
        error_exit "AWS CLI version 2.0 or later is required. Current version: $aws_version"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        error_exit "AWS credentials not configured. Run 'aws configure' to set up credentials."
    fi
    
    # Check required permissions (basic test)
    local caller_identity
    caller_identity=$(aws sts get-caller-identity 2>/dev/null) || error_exit "Failed to get AWS caller identity"
    log "AWS Account: $(echo "$caller_identity" | jq -r '.Account // "N/A"')"
    log "AWS User/Role: $(echo "$caller_identity" | jq -r '.Arn // "N/A"')"
    
    # Optional: Check for jq
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. JSON output will be less readable."
    fi
    
    log_success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION
    AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION="us-east-1"
        log_warning "No default region configured. Using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export BUCKET_NAME="${BUCKET_PREFIX}-${random_suffix}"
    export ROLE_NAME="${ROLE_PREFIX}-${random_suffix}"
    
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "S3 Bucket: $BUCKET_NAME"
    log "Lambda Function: $FUNCTION_NAME"
    log "IAM Role: $ROLE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN MODE: No resources will be created"
    fi
}

# Create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for quote storage..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create S3 bucket: $BUCKET_NAME"
        return 0
    fi
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        log_warning "S3 bucket $BUCKET_NAME already exists"
    else
        # Create bucket (handle region-specific creation)
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3 mb "s3://$BUCKET_NAME" || error_exit "Failed to create S3 bucket"
        else
            aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION" || error_exit "Failed to create S3 bucket"
        fi
        
        # Enable server-side encryption
        aws s3api put-bucket-encryption \
            --bucket "$BUCKET_NAME" \
            --server-side-encryption-configuration \
            'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]' || \
            error_exit "Failed to enable bucket encryption"
        
        log_success "S3 bucket created: $BUCKET_NAME"
    fi
}

# Upload quote data to S3
upload_quote_data() {
    log "Uploading quote data to S3..."
    
    local quotes_file="$PROJECT_ROOT/quotes.json"
    
    # Create quotes JSON file
    cat > "$quotes_file" << 'EOF'
{
  "quotes": [
    {
      "text": "The only way to do great work is to love what you do.",
      "author": "Steve Jobs"
    },
    {
      "text": "Innovation distinguishes between a leader and a follower.",
      "author": "Steve Jobs"
    },
    {
      "text": "Life is what happens to you while you're busy making other plans.",
      "author": "John Lennon"
    },
    {
      "text": "The future belongs to those who believe in the beauty of their dreams.",
      "author": "Eleanor Roosevelt"
    },
    {
      "text": "It is during our darkest moments that we must focus to see the light.",
      "author": "Aristotle"
    },
    {
      "text": "Success is not final, failure is not fatal: it is the courage to continue that counts.",
      "author": "Winston Churchill"
    }
  ]
}
EOF
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would upload quotes.json to s3://$BUCKET_NAME/"
    else
        # Upload quotes to S3
        aws s3 cp "$quotes_file" "s3://$BUCKET_NAME/quotes.json" || \
            error_exit "Failed to upload quotes to S3"
        
        log_success "Quote data uploaded to S3"
    fi
    
    # Clean up temporary file
    rm -f "$quotes_file"
}

# Create IAM role for Lambda
create_iam_role() {
    log "Creating IAM role for Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create IAM role: $ROLE_NAME"
        return 0
    fi
    
    # Check if role already exists
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        log_warning "IAM role $ROLE_NAME already exists"
        return 0
    fi
    
    local trust_policy="$PROJECT_ROOT/trust-policy.json"
    local s3_policy="$PROJECT_ROOT/s3-policy.json"
    
    # Create trust policy for Lambda
    cat > "$trust_policy" << 'EOF'
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
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "file://$trust_policy" || \
        error_exit "Failed to create IAM role"
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" || \
        error_exit "Failed to attach Lambda execution policy"
    
    # Create S3 read policy
    cat > "$s3_policy" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    }
  ]
}
EOF
    
    # Create and attach S3 policy
    aws iam put-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-name "S3ReadPolicy" \
        --policy-document "file://$s3_policy" || \
        error_exit "Failed to create S3 read policy"
    
    # Clean up temporary files
    rm -f "$trust_policy" "$s3_policy"
    
    log_success "IAM role created with S3 read permissions"
}

# Create Lambda function
create_lambda_function() {
    log "Creating Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Lambda function: $FUNCTION_NAME"
        return 0
    fi
    
    # Check if function already exists
    if aws lambda get-function --function-name "$FUNCTION_NAME" &>/dev/null; then
        log_warning "Lambda function $FUNCTION_NAME already exists. Updating..."
        update_lambda_function
        return 0
    fi
    
    local function_code="$PROJECT_ROOT/lambda_function.py"
    local function_zip="$PROJECT_ROOT/function.zip"
    
    # Create Lambda function code
    cat > "$function_code" << 'EOF'
import json
import boto3
import random
import os

def lambda_handler(event, context):
    # Initialize S3 client
    s3 = boto3.client('s3')
    bucket_name = os.environ['BUCKET_NAME']
    
    try:
        # Get quotes from S3
        response = s3.get_object(Bucket=bucket_name, Key='quotes.json')
        quotes_data = json.loads(response['Body'].read().decode('utf-8'))
        
        # Select random quote
        random_quote = random.choice(quotes_data['quotes'])
        
        # Return response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'quote': random_quote['text'],
                'author': random_quote['author'],
                'timestamp': context.aws_request_id
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'error': 'Failed to retrieve quote',
                'message': str(e)
            })
        }
EOF
    
    # Create deployment package
    (cd "$PROJECT_ROOT" && zip -q "$function_zip" lambda_function.py) || \
        error_exit "Failed to create deployment package"
    
    # Wait for role propagation
    log "Waiting for IAM role propagation..."
    sleep 10
    
    # Get IAM role ARN
    local role_arn
    role_arn=$(aws iam get-role --role-name "$ROLE_NAME" \
        --query 'Role.Arn' --output text) || \
        error_exit "Failed to get IAM role ARN"
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$FUNCTION_NAME" \
        --runtime python3.12 \
        --role "$role_arn" \
        --handler lambda_function.lambda_handler \
        --zip-file "fileb://$function_zip" \
        --timeout 30 \
        --memory-size 128 \
        --environment "Variables={BUCKET_NAME=$BUCKET_NAME}" || \
        error_exit "Failed to create Lambda function"
    
    # Clean up temporary files
    rm -f "$function_code" "$function_zip"
    
    log_success "Lambda function deployed: $FUNCTION_NAME"
}

# Update existing Lambda function
update_lambda_function() {
    log "Updating existing Lambda function..."
    
    local function_code="$PROJECT_ROOT/lambda_function.py"
    local function_zip="$PROJECT_ROOT/function.zip"
    
    # Create Lambda function code (same as create)
    cat > "$function_code" << 'EOF'
import json
import boto3
import random
import os

def lambda_handler(event, context):
    # Initialize S3 client
    s3 = boto3.client('s3')
    bucket_name = os.environ['BUCKET_NAME']
    
    try:
        # Get quotes from S3
        response = s3.get_object(Bucket=bucket_name, Key='quotes.json')
        quotes_data = json.loads(response['Body'].read().decode('utf-8'))
        
        # Select random quote
        random_quote = random.choice(quotes_data['quotes'])
        
        # Return response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'quote': random_quote['text'],
                'author': random_quote['author'],
                'timestamp': context.aws_request_id
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'error': 'Failed to retrieve quote',
                'message': str(e)
            })
        }
EOF
    
    # Create deployment package
    (cd "$PROJECT_ROOT" && zip -q "$function_zip" lambda_function.py) || \
        error_exit "Failed to create deployment package"
    
    # Update function code
    aws lambda update-function-code \
        --function-name "$FUNCTION_NAME" \
        --zip-file "fileb://$function_zip" || \
        error_exit "Failed to update Lambda function code"
    
    # Update environment variables
    aws lambda update-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --environment "Variables={BUCKET_NAME=$BUCKET_NAME}" || \
        error_exit "Failed to update Lambda function configuration"
    
    # Clean up temporary files
    rm -f "$function_code" "$function_zip"
    
    log_success "Lambda function updated: $FUNCTION_NAME"
}

# Create Function URL
create_function_url() {
    log "Creating Function URL for direct access..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Function URL for: $FUNCTION_NAME"
        return 0
    fi
    
    # Check if Function URL already exists
    if aws lambda get-function-url-config --function-name "$FUNCTION_NAME" &>/dev/null; then
        log_warning "Function URL already exists for $FUNCTION_NAME"
    else
        # Create function URL
        aws lambda create-function-url-config \
            --function-name "$FUNCTION_NAME" \
            --auth-type NONE \
            --cors 'AllowCredentials=false,AllowHeaders=["*"],AllowMethods=["GET"],AllowOrigins=["*"],MaxAge=86400' || \
            error_exit "Failed to create Function URL"
    fi
    
    # Get the function URL
    local function_url
    function_url=$(aws lambda get-function-url-config \
        --function-name "$FUNCTION_NAME" \
        --query 'FunctionUrl' --output text) || \
        error_exit "Failed to get Function URL"
    
    log_success "Function URL created: $function_url"
    
    # Store URL for testing
    echo "$function_url" > "$PROJECT_ROOT/.function_url"
}

# Test deployment
test_deployment() {
    log "Testing deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would test deployment"
        return 0
    fi
    
    # Test Lambda function directly
    log "Testing Lambda function invocation..."
    local response_file="$PROJECT_ROOT/test_response.json"
    
    aws lambda invoke \
        --function-name "$FUNCTION_NAME" \
        --payload '{}' \
        "$response_file" || \
        error_exit "Failed to invoke Lambda function"
    
    if [[ -f "$response_file" ]]; then
        log "Lambda response:"
        if command -v jq &> /dev/null; then
            cat "$response_file" | jq '.'
        else
            cat "$response_file"
        fi
        rm -f "$response_file"
    fi
    
    # Test Function URL if available
    if [[ -f "$PROJECT_ROOT/.function_url" ]]; then
        local function_url
        function_url=$(cat "$PROJECT_ROOT/.function_url")
        
        log "Testing Function URL..."
        if command -v curl &> /dev/null; then
            curl -s "$function_url" | if command -v jq &> /dev/null; then jq '.'; else cat; fi
        else
            log_warning "curl not available. Function URL: $function_url"
        fi
    fi
    
    log_success "Deployment test completed"
}

# Print deployment summary
print_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=========================================="
    echo "          DEPLOYMENT SUMMARY"
    echo "=========================================="
    echo "AWS Region:       $AWS_REGION"
    echo "S3 Bucket:        $BUCKET_NAME"
    echo "Lambda Function:  $FUNCTION_NAME"
    echo "IAM Role:         $ROLE_NAME"
    
    if [[ -f "$PROJECT_ROOT/.function_url" ]]; then
        local function_url
        function_url=$(cat "$PROJECT_ROOT/.function_url")
        echo "Function URL:     $function_url"
    fi
    
    echo
    echo "Test your API:"
    if [[ -f "$PROJECT_ROOT/.function_url" ]]; then
        local function_url
        function_url=$(cat "$PROJECT_ROOT/.function_url")
        echo "  curl $function_url"
    fi
    echo "  aws lambda invoke --function-name $FUNCTION_NAME --payload '{}' response.json"
    echo
    echo "Log file: $LOG_FILE"
    echo "=========================================="
}

# Main deployment function
main() {
    log "Starting deployment of Simple Daily Quote Generator..."
    log "Log file: $LOG_FILE"
    
    parse_args "$@"
    check_prerequisites
    setup_environment
    create_s3_bucket
    upload_quote_data
    create_iam_role
    create_lambda_function
    create_function_url
    test_deployment
    print_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function with all arguments
main "$@"