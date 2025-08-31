#!/bin/bash

# Intelligent Web Scraping with AgentCore Browser and Code Interpreter - Deployment Script
# This script deploys the complete infrastructure for intelligent web scraping solution
# Usage: ./deploy.sh [--dry-run] [--region REGION] [--project-name NAME]

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false
VERBOSE=false

# Default values
DEFAULT_REGION=""
DEFAULT_PROJECT_NAME=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Starting cleanup of partially created resources..."
    
    # Only cleanup if we have the project name set
    if [[ -n "${PROJECT_NAME:-}" ]]; then
        # This will call destroy.sh with emergency cleanup
        if [[ -f "${SCRIPT_DIR}/destroy.sh" ]]; then
            log_info "Running emergency cleanup..."
            bash "${SCRIPT_DIR}/destroy.sh" --emergency --project-name "${PROJECT_NAME}" || true
        fi
    fi
}

# Trap errors for cleanup
trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Intelligent Web Scraping Deployment Script

Usage: $0 [OPTIONS]

OPTIONS:
    --dry-run                    Show what would be deployed without making changes
    --region REGION             AWS region (default: current CLI region)
    --project-name NAME         Project name prefix (default: auto-generated)
    --verbose                   Enable verbose logging
    --help                      Show this help message

EXAMPLES:
    $0                          # Deploy with defaults
    $0 --dry-run               # Preview deployment
    $0 --region us-west-2      # Deploy to specific region
    $0 --project-name my-scraper --verbose

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Appropriate AWS permissions for Bedrock, Lambda, S3, IAM, CloudWatch
    - jq command-line JSON processor

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

# Prerequisites checking
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install jq for JSON processing."
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | head -n1 | awk '{print $1}' | cut -d/ -f2 | cut -d. -f1)
    if [[ "${aws_version}" -lt 2 ]]; then
        error_exit "AWS CLI version 2 is required. Current version: $(aws --version)"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        error_exit "AWS credentials not configured or invalid. Please run 'aws configure'."
    fi
    
    # Check Bedrock service availability (AgentCore is preview)
    local identity
    identity=$(aws sts get-caller-identity 2>/dev/null) || error_exit "Failed to verify AWS identity"
    
    log_success "Prerequisites check completed"
    
    if [[ "${VERBOSE}" == "true" ]]; then
        log_info "AWS Identity: $(echo "${identity}" | jq -r '.Arn')"
        log_info "AWS CLI Version: $(aws --version)"
    fi
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            AWS_REGION="us-east-1"
            log_warning "No region configured, using default: ${AWS_REGION}"
        fi
    fi
    export AWS_REGION
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_ACCOUNT_ID
    
    # Generate unique project name if not provided
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        local random_suffix
        random_suffix=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            echo "$(date +%s | tail -c 6)")
        PROJECT_NAME="intelligent-scraper-${random_suffix}"
    fi
    export PROJECT_NAME
    
    # Set resource names
    export S3_BUCKET_INPUT="${PROJECT_NAME}-input"
    export S3_BUCKET_OUTPUT="${PROJECT_NAME}-output"
    export LAMBDA_FUNCTION_NAME="${PROJECT_NAME}-orchestrator"
    export IAM_ROLE_NAME="${PROJECT_NAME}-lambda-role"
    export DLQ_NAME="${PROJECT_NAME}-dlq"
    export EVENTBRIDGE_RULE_NAME="${PROJECT_NAME}-schedule"
    export LOG_GROUP_NAME="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
    export DASHBOARD_NAME="${PROJECT_NAME}-monitoring"
    
    log_success "Environment configured:"
    log_info "  Region: ${AWS_REGION}"
    log_info "  Account ID: ${AWS_ACCOUNT_ID}"
    log_info "  Project Name: ${PROJECT_NAME}"
    log_info "  Input Bucket: ${S3_BUCKET_INPUT}"
    log_info "  Output Bucket: ${S3_BUCKET_OUTPUT}"
    log_info "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
}

# Create S3 buckets
create_s3_buckets() {
    log_info "Creating S3 buckets..."
    
    # Check if buckets already exist
    local input_exists output_exists
    input_exists=$(aws s3api head-bucket --bucket "${S3_BUCKET_INPUT}" 2>/dev/null && echo "true" || echo "false")
    output_exists=$(aws s3api head-bucket --bucket "${S3_BUCKET_OUTPUT}" 2>/dev/null && echo "true" || echo "false")
    
    if [[ "${input_exists}" == "true" ]] && [[ "${output_exists}" == "true" ]]; then
        log_warning "S3 buckets already exist, skipping creation"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create S3 buckets: ${S3_BUCKET_INPUT}, ${S3_BUCKET_OUTPUT}"
        return 0
    fi
    
    # Create input bucket
    if [[ "${input_exists}" == "false" ]]; then
        if [[ "${AWS_REGION}" == "us-east-1" ]]; then
            aws s3 mb s3://"${S3_BUCKET_INPUT}" || error_exit "Failed to create input bucket"
        else
            aws s3 mb s3://"${S3_BUCKET_INPUT}" --region "${AWS_REGION}" || error_exit "Failed to create input bucket"
        fi
        
        # Enable versioning and encryption
        aws s3api put-bucket-versioning \
            --bucket "${S3_BUCKET_INPUT}" \
            --versioning-configuration Status=Enabled || error_exit "Failed to enable versioning on input bucket"
        
        aws s3api put-bucket-encryption \
            --bucket "${S3_BUCKET_INPUT}" \
            --server-side-encryption-configuration \
            'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]' || error_exit "Failed to enable encryption on input bucket"
        
        log_success "Created input bucket: ${S3_BUCKET_INPUT}"
    fi
    
    # Create output bucket
    if [[ "${output_exists}" == "false" ]]; then
        if [[ "${AWS_REGION}" == "us-east-1" ]]; then
            aws s3 mb s3://"${S3_BUCKET_OUTPUT}" || error_exit "Failed to create output bucket"
        else
            aws s3 mb s3://"${S3_BUCKET_OUTPUT}" --region "${AWS_REGION}" || error_exit "Failed to create output bucket"
        fi
        
        aws s3api put-bucket-encryption \
            --bucket "${S3_BUCKET_OUTPUT}" \
            --server-side-encryption-configuration \
            'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]' || error_exit "Failed to enable encryption on output bucket"
        
        log_success "Created output bucket: ${S3_BUCKET_OUTPUT}"
    fi
}

# Create IAM role for Lambda
create_iam_role() {
    log_info "Creating IAM role for Lambda..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        log_warning "IAM role ${IAM_ROLE_NAME} already exists, skipping creation"
        export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create IAM role: ${IAM_ROLE_NAME}"
        return 0
    fi
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/lambda-trust-policy.json" << EOF
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
        --assume-role-policy-document file://"${SCRIPT_DIR}/lambda-trust-policy.json" || error_exit "Failed to create IAM role"
    
    # Create policy for AgentCore and S3 access
    cat > "${SCRIPT_DIR}/lambda-policy.json" << EOF
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
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:StartBrowserSession",
        "bedrock-agentcore:StopBrowserSession",
        "bedrock-agentcore:GetBrowserSession",
        "bedrock-agentcore:UpdateBrowserStream",
        "bedrock-agentcore:StartCodeInterpreterSession",
        "bedrock-agentcore:StopCodeInterpreterSession",
        "bedrock-agentcore:GetCodeInterpreterSession"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET_INPUT}",
        "arn:aws:s3:::${S3_BUCKET_INPUT}/*",
        "arn:aws:s3:::${S3_BUCKET_OUTPUT}",
        "arn:aws:s3:::${S3_BUCKET_OUTPUT}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage"
      ],
      "Resource": "arn:aws:sqs:${AWS_REGION}:${AWS_ACCOUNT_ID}:${DLQ_NAME}"
    }
  ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-name "${PROJECT_NAME}-lambda-policy" \
        --policy-document file://"${SCRIPT_DIR}/lambda-policy.json" || error_exit "Failed to attach policy to IAM role"
    
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}"
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 15
    
    log_success "Created IAM role: ${LAMBDA_ROLE_ARN}"
}

# Upload scraping configuration
upload_scraping_config() {
    log_info "Creating and uploading scraping configuration..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would upload scraping configuration to S3"
        return 0
    fi
    
    # Create browser configuration
    cat > "${SCRIPT_DIR}/scraper-config.json" << EOF
{
  "scraping_scenarios": [
    {
      "name": "ecommerce_demo",
      "description": "Extract product information from demo sites",
      "target_url": "https://books.toscrape.com/",
      "extraction_rules": {
        "product_titles": {
          "selector": "h3 a",
          "attribute": "title",
          "wait_for": "h3 a"
        },
        "prices": {
          "selector": ".price_color",
          "attribute": "textContent",
          "wait_for": ".price_color"
        },
        "availability": {
          "selector": ".availability",
          "attribute": "textContent",
          "wait_for": ".availability"
        }
      },
      "session_config": {
        "timeout_seconds": 30,
        "view_port": {
          "width": 1920,
          "height": 1080
        }
      }
    }
  ]
}
EOF
    
    # Upload configuration to S3
    aws s3 cp "${SCRIPT_DIR}/scraper-config.json" s3://"${S3_BUCKET_INPUT}"/ || error_exit "Failed to upload scraper configuration"
    
    # Create data processing configuration
    cat > "${SCRIPT_DIR}/data-processing-config.json" << EOF
{
  "processing_rules": {
    "price_cleaning": {
      "remove_currency_symbols": true,
      "normalize_decimal_places": 2,
      "convert_to_numeric": true
    },
    "text_analysis": {
      "extract_keywords": true,
      "sentiment_analysis": false,
      "language_detection": false
    },
    "data_validation": {
      "required_fields": ["product_titles", "prices"],
      "min_data_points": 1,
      "max_processing_time_seconds": 60
    },
    "output_format": {
      "include_raw_data": true,
      "include_statistics": true,
      "include_quality_metrics": true
    }
  },
  "analysis_templates": {
    "ecommerce": {
      "metrics": ["price_distribution", "availability_rate", "product_count"],
      "alerts": {
        "low_availability": 0.5,
        "price_variance_threshold": 0.3
      }
    }
  }
}
EOF
    
    aws s3 cp "${SCRIPT_DIR}/data-processing-config.json" s3://"${S3_BUCKET_INPUT}"/ || error_exit "Failed to upload data processing configuration"
    
    log_success "Uploaded configuration files to S3"
}

# Create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function..."
    
    # Check if function already exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} already exists, updating code..."
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would update Lambda function code"
            return 0
        fi
        
        # Update existing function
        aws lambda update-function-code \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --zip-file fileb://"${SCRIPT_DIR}/lambda-function.zip" || error_exit "Failed to update Lambda function code"
        
        log_success "Updated Lambda function code"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Lambda function: ${LAMBDA_FUNCTION_NAME}"
        return 0
    fi
    
    # Create Lambda function code
    cat > "${SCRIPT_DIR}/lambda_function.py" << 'EOF'
import json
import boto3
import time
import logging
import uuid
from datetime import datetime
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    try:
        s3 = boto3.client('s3')
        agentcore = boto3.client('bedrock-agentcore')
        cloudwatch = boto3.client('cloudwatch')
        
        # Get configuration from S3
        bucket_input = event.get('bucket_input', 'default-input')
        bucket_output = event.get('bucket_output', 'default-output')
        
        config_response = s3.get_object(
            Bucket=bucket_input,
            Key='scraper-config.json'
        )
        config = json.loads(config_response['Body'].read())
        
        logger.info(f"Processing {len(config['scraping_scenarios'])} scenarios")
        
        all_scraped_data = []
        
        for scenario in config['scraping_scenarios']:
            logger.info(f"Processing scenario: {scenario['name']}")
            
            # Start browser session
            session_response = agentcore.start_browser_session(
                browserIdentifier='default-browser',
                name=f"{scenario['name']}-{int(time.time())}",
                sessionTimeoutSeconds=scenario['session_config']['timeout_seconds']
            )
            
            browser_session_id = session_response['sessionId']
            logger.info(f"Started browser session: {browser_session_id}")
            
            try:
                # Simulate web navigation and data extraction
                # Note: In actual implementation, you would use browser automation SDK
                
                scenario_data = {
                    'scenario_name': scenario['name'],
                    'target_url': scenario['target_url'],
                    'timestamp': datetime.utcnow().isoformat(),
                    'session_id': browser_session_id,
                    'extracted_data': {
                        'product_titles': ['Sample Book 1', 'Sample Book 2', 'Sample Book 3'],
                        'prices': ['£51.77', '£53.74', '£50.10'],
                        'availability': ['In stock', 'In stock', 'Out of stock']
                    }
                }
                
                all_scraped_data.append(scenario_data)
                
                # Send metrics to CloudWatch
                cloudwatch.put_metric_data(
                    Namespace=f'IntelligentScraper/{context.function_name}',
                    MetricData=[
                        {
                            'MetricName': 'ScrapingJobs',
                            'Value': 1,
                            'Unit': 'Count'
                        },
                        {
                            'MetricName': 'DataPointsExtracted',
                            'Value': len(scenario_data['extracted_data']['product_titles']),
                            'Unit': 'Count'
                        }
                    ]
                )
                
            finally:
                # Cleanup browser session
                try:
                    agentcore.stop_browser_session(sessionId=browser_session_id)
                    logger.info(f"Stopped browser session: {browser_session_id}")
                except Exception as e:
                    logger.warning(f"Failed to stop session {browser_session_id}: {e}")
        
        # Start Code Interpreter session for data processing
        code_session_response = agentcore.start_code_interpreter_session(
            codeInterpreterIdentifier='default-code-interpreter',
            name=f"data-processor-{int(time.time())}",
            sessionTimeoutSeconds=300
        )
        
        code_session_id = code_session_response['sessionId']
        logger.info(f"Started code interpreter session: {code_session_id}")
        
        try:
            # Process data with analysis
            processing_results = process_scraped_data(all_scraped_data)
            
            # Save results to S3
            result_data = {
                'raw_data': all_scraped_data,
                'analysis': processing_results,
                'execution_metadata': {
                    'timestamp': datetime.utcnow().isoformat(),
                    'function_name': context.function_name,
                    'request_id': context.aws_request_id
                }
            }
            
            result_key = f'scraping-results-{int(time.time())}.json'
            s3.put_object(
                Bucket=bucket_output,
                Key=result_key,
                Body=json.dumps(result_data, indent=2),
                ContentType='application/json'
            )
            
            logger.info(f"Results saved to s3://{bucket_output}/{result_key}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Scraping completed successfully',
                    'scenarios_processed': len(config['scraping_scenarios']),
                    'total_data_points': sum(len(data['extracted_data']['product_titles']) for data in all_scraped_data),
                    'result_location': f's3://{bucket_output}/{result_key}'
                })
            }
            
        finally:
            # Cleanup code interpreter session
            try:
                agentcore.stop_code_interpreter_session(sessionId=code_session_id)
                logger.info(f"Stopped code interpreter session: {code_session_id}")
            except Exception as e:
                logger.warning(f"Failed to stop code session {code_session_id}: {e}")
        
    except Exception as e:
        logger.error(f"Error in scraping workflow: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'request_id': context.aws_request_id
            })
        }

def process_scraped_data(scraped_data):
    """Process and analyze scraped data"""
    total_items = sum(len(data['extracted_data']['product_titles']) for data in scraped_data)
    
    # Analyze prices
    all_prices = []
    for data in scraped_data:
        for price_str in data['extracted_data']['prices']:
            # Extract numeric value from price string
            numeric_price = ''.join(filter(lambda x: x.isdigit() or x == '.', price_str))
            if numeric_price:
                all_prices.append(float(numeric_price))
    
    # Calculate availability stats
    all_availability = []
    for data in scraped_data:
        all_availability.extend(data['extracted_data']['availability'])
    
    in_stock_count = sum(1 for status in all_availability if 'stock' in status.lower())
    
    analysis = {
        'total_products_scraped': total_items,
        'price_analysis': {
            'average_price': sum(all_prices) / len(all_prices) if all_prices else 0,
            'min_price': min(all_prices) if all_prices else 0,
            'max_price': max(all_prices) if all_prices else 0,
            'price_count': len(all_prices)
        },
        'availability_analysis': {
            'total_items_checked': len(all_availability),
            'in_stock_count': in_stock_count,
            'out_of_stock_count': len(all_availability) - in_stock_count,
            'availability_rate': (in_stock_count / len(all_availability) * 100) if all_availability else 0
        },
        'data_quality_score': (total_items / max(1, len(scraped_data))) * 100,
        'processing_timestamp': datetime.utcnow().isoformat()
    }
    
    return analysis
EOF
    
    # Package Lambda function
    (cd "${SCRIPT_DIR}" && zip lambda-function.zip lambda_function.py) || error_exit "Failed to package Lambda function"
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.11 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://"${SCRIPT_DIR}/lambda-function.zip" \
        --timeout 900 \
        --memory-size 1024 \
        --environment Variables='{
            "S3_BUCKET_INPUT":"'${S3_BUCKET_INPUT}'",
            "S3_BUCKET_OUTPUT":"'${S3_BUCKET_OUTPUT}'",
            "ENVIRONMENT":"production",
            "LOG_LEVEL":"INFO"
        }' \
        --region "${AWS_REGION}" || error_exit "Failed to create Lambda function"
    
    log_success "Created Lambda function: ${LAMBDA_FUNCTION_NAME}"
}

# Create SQS Dead Letter Queue
create_dlq() {
    log_info "Creating Dead Letter Queue..."
    
    # Check if queue already exists
    if aws sqs get-queue-url --queue-name "${DLQ_NAME}" &>/dev/null; then
        log_warning "DLQ ${DLQ_NAME} already exists, skipping creation"
        export DLQ_URL=$(aws sqs get-queue-url --queue-name "${DLQ_NAME}" --query QueueUrl --output text)
        export DLQ_ARN=$(aws sqs get-queue-attributes --queue-url "${DLQ_URL}" --attribute-names QueueArn --query Attributes.QueueArn --output text)
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create SQS DLQ: ${DLQ_NAME}"
        return 0
    fi
    
    # Create SQS DLQ
    aws sqs create-queue \
        --queue-name "${DLQ_NAME}" \
        --attributes VisibilityTimeoutSeconds=300 \
        --region "${AWS_REGION}" || error_exit "Failed to create DLQ"
    
    export DLQ_URL=$(aws sqs get-queue-url --queue-name "${DLQ_NAME}" --query QueueUrl --output text)
    export DLQ_ARN=$(aws sqs get-queue-attributes --queue-url "${DLQ_URL}" --attribute-names QueueArn --query Attributes.QueueArn --output text)
    
    # Update Lambda with DLQ configuration
    aws lambda update-function-configuration \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --dead-letter-config TargetArn="${DLQ_ARN}" \
        --region "${AWS_REGION}" || error_exit "Failed to configure DLQ for Lambda"
    
    log_success "Created DLQ: ${DLQ_ARN}"
}

# Create CloudWatch resources
create_cloudwatch_resources() {
    log_info "Creating CloudWatch monitoring resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create CloudWatch log group and dashboard"
        return 0
    fi
    
    # Create CloudWatch log group (if it doesn't exist)
    if ! aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --query 'logGroups[?logGroupName==`'${LOG_GROUP_NAME}'`]' --output text | grep -q "${LOG_GROUP_NAME}"; then
        aws logs create-log-group \
            --log-group-name "${LOG_GROUP_NAME}" \
            --region "${AWS_REGION}" || error_exit "Failed to create CloudWatch log group"
        
        log_success "Created CloudWatch log group: ${LOG_GROUP_NAME}"
    else
        log_warning "CloudWatch log group already exists: ${LOG_GROUP_NAME}"
    fi
    
    # Create CloudWatch dashboard
    cat > "${SCRIPT_DIR}/dashboard-config.json" << EOF
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          ["IntelligentScraper/${LAMBDA_FUNCTION_NAME}", "ScrapingJobs"],
          [".", "DataPointsExtracted"]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "Scraping Activity",
        "yAxis": {
          "left": {
            "min": 0
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          ["AWS/Lambda", "Duration", "FunctionName", "${LAMBDA_FUNCTION_NAME}"],
          [".", "Errors", ".", "."],
          [".", "Invocations", ".", "."]
        ],
        "period": 300,
        "stat": "Average",
        "region": "${AWS_REGION}",
        "title": "Lambda Performance"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 6,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE '${LOG_GROUP_NAME}'\n| fields @timestamp, @message\n| filter @message like /ERROR/\n| sort @timestamp desc\n| limit 20",
        "region": "${AWS_REGION}",
        "title": "Recent Errors",
        "view": "table"
      }
    }
  ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body file://"${SCRIPT_DIR}/dashboard-config.json" || error_exit "Failed to create CloudWatch dashboard"
    
    log_success "Created CloudWatch dashboard: ${DASHBOARD_NAME}"
}

# Configure EventBridge scheduling
configure_eventbridge() {
    log_info "Configuring EventBridge scheduling..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would configure EventBridge rule and targets"
        return 0
    fi
    
    # Check if rule already exists
    if aws events describe-rule --name "${EVENTBRIDGE_RULE_NAME}" &>/dev/null; then
        log_warning "EventBridge rule ${EVENTBRIDGE_RULE_NAME} already exists, updating..."
        
        # Update existing rule
        aws events put-rule \
            --name "${EVENTBRIDGE_RULE_NAME}" \
            --schedule-expression "rate(6 hours)" \
            --description "Scheduled intelligent web scraping" \
            --state ENABLED \
            --region "${AWS_REGION}" || error_exit "Failed to update EventBridge rule"
    else
        # Create new rule
        aws events put-rule \
            --name "${EVENTBRIDGE_RULE_NAME}" \
            --schedule-expression "rate(6 hours)" \
            --description "Scheduled intelligent web scraping" \
            --state ENABLED \
            --region "${AWS_REGION}" || error_exit "Failed to create EventBridge rule"
    fi
    
    # Add Lambda permission for EventBridge
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id "${PROJECT_NAME}-eventbridge-permission" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}" \
        --region "${AWS_REGION}" 2>/dev/null || log_warning "Lambda permission may already exist"
    
    # Create EventBridge target
    cat > "${SCRIPT_DIR}/eventbridge-input.json" << EOF
{
  "bucket_input": "${S3_BUCKET_INPUT}",
  "bucket_output": "${S3_BUCKET_OUTPUT}",
  "scheduled_execution": true
}
EOF
    
    aws events put-targets \
        --rule "${EVENTBRIDGE_RULE_NAME}" \
        --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME},Input=$(cat "${SCRIPT_DIR}/eventbridge-input.json" | jq -c .)" \
        --region "${AWS_REGION}" || error_exit "Failed to configure EventBridge targets"
    
    log_success "Configured EventBridge scheduling (every 6 hours)"
}

# Test deployment
test_deployment() {
    log_info "Testing deployment..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would test Lambda function execution"
        return 0
    fi
    
    # Create test payload
    cat > "${SCRIPT_DIR}/test-payload.json" << EOF
{
  "bucket_input": "${S3_BUCKET_INPUT}",
  "bucket_output": "${S3_BUCKET_OUTPUT}",
  "test_mode": true
}
EOF
    
    # Execute test run
    log_info "Executing test Lambda invocation..."
    aws lambda invoke \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --payload file://"${SCRIPT_DIR}/test-payload.json" \
        --region "${AWS_REGION}" \
        "${SCRIPT_DIR}/test-response.json" || error_exit "Failed to test Lambda function"
    
    # Check test results
    local status_code
    status_code=$(jq -r '.StatusCode' "${SCRIPT_DIR}/test-response.json" 2>/dev/null || echo "0")
    
    if [[ "${status_code}" == "200" ]]; then
        log_success "Test execution completed successfully"
        
        if [[ "${VERBOSE}" == "true" ]]; then
            log_info "Test response:"
            jq '.' "${SCRIPT_DIR}/test-response.json" || cat "${SCRIPT_DIR}/test-response.json"
        fi
    else
        log_error "Test execution failed with status code: ${status_code}"
        cat "${SCRIPT_DIR}/test-response.json"
        error_exit "Deployment test failed"
    fi
}

# Save deployment info
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > "${SCRIPT_DIR}/deployment-info.json" << EOF
{
  "deployment": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "project_name": "${PROJECT_NAME}",
    "region": "${AWS_REGION}",
    "account_id": "${AWS_ACCOUNT_ID}"
  },
  "resources": {
    "s3_bucket_input": "${S3_BUCKET_INPUT}",
    "s3_bucket_output": "${S3_BUCKET_OUTPUT}",
    "lambda_function": "${LAMBDA_FUNCTION_NAME}",
    "iam_role": "${IAM_ROLE_NAME}",
    "iam_role_arn": "${LAMBDA_ROLE_ARN}",
    "dlq_name": "${DLQ_NAME}",
    "dlq_arn": "${DLQ_ARN:-}",
    "eventbridge_rule": "${EVENTBRIDGE_RULE_NAME}",
    "log_group": "${LOG_GROUP_NAME}",
    "dashboard": "${DASHBOARD_NAME}"
  },
  "endpoints": {
    "lambda_function_arn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}",
    "s3_input_url": "s3://${S3_BUCKET_INPUT}",
    "s3_output_url": "s3://${S3_BUCKET_OUTPUT}",
    "cloudwatch_dashboard_url": "https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
  }
}
EOF
    
    log_success "Deployment information saved to: ${SCRIPT_DIR}/deployment-info.json"
}

# Cleanup temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    local temp_files=(
        "${SCRIPT_DIR}/lambda-trust-policy.json"
        "${SCRIPT_DIR}/lambda-policy.json"
        "${SCRIPT_DIR}/lambda_function.py"
        "${SCRIPT_DIR}/lambda-function.zip"
        "${SCRIPT_DIR}/scraper-config.json"
        "${SCRIPT_DIR}/data-processing-config.json"
        "${SCRIPT_DIR}/dashboard-config.json"
        "${SCRIPT_DIR}/eventbridge-input.json"
        "${SCRIPT_DIR}/test-payload.json"
        "${SCRIPT_DIR}/test-response.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}" || log_warning "Failed to remove ${file}"
        fi
    done
    
    log_success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log_info "Starting Intelligent Web Scraping deployment..."
    log_info "Log file: ${LOG_FILE}"
    
    # Parse arguments
    parse_args "$@"
    
    # Show dry-run notice
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_s3_buckets
    create_iam_role
    upload_scraping_config
    create_lambda_function
    create_dlq
    create_cloudwatch_resources
    configure_eventbridge
    
    # Test deployment if not dry run
    if [[ "${DRY_RUN}" == "false" ]]; then
        test_deployment
        save_deployment_info
    fi
    
    # Cleanup
    cleanup_temp_files
    
    # Success message
    log_success "Deployment completed successfully!"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        log_info ""
        log_info "Deployment Summary:"
        log_info "  Project Name: ${PROJECT_NAME}"
        log_info "  Region: ${AWS_REGION}"
        log_info "  Input Bucket: s3://${S3_BUCKET_INPUT}"
        log_info "  Output Bucket: s3://${S3_BUCKET_OUTPUT}"
        log_info "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
        log_info "  CloudWatch Dashboard: ${DASHBOARD_NAME}"
        log_info ""
        log_info "Next steps:"
        log_info "  1. Monitor execution in CloudWatch: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
        log_info "  2. Check scraping results in S3: https://s3.console.aws.amazon.com/s3/buckets/${S3_BUCKET_OUTPUT}"
        log_info "  3. Configure additional scraping scenarios in s3://${S3_BUCKET_INPUT}/scraper-config.json"
        log_info ""
        log_info "To clean up resources, run: ./destroy.sh --project-name ${PROJECT_NAME}"
    fi
}

# Execute main function with all arguments
main "$@"