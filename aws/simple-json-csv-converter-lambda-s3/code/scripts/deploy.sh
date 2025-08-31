#!/bin/bash

# Simple JSON to CSV Converter with Lambda and S3 - Deployment Script
# This script deploys a serverless JSON-to-CSV conversion pipeline using AWS Lambda and S3

set -euo pipefail  # Exit on error, undefined variables, or pipe failures

# Color codes for output
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

# Script metadata
SCRIPT_NAME="JSON to CSV Converter Deployment"
SCRIPT_VERSION="1.0"
DEPLOYMENT_START_TIME=$(date)

log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
log_info "Deployment started at: $DEPLOYMENT_START_TIME"

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    if [[ -n "${INPUT_BUCKET_NAME:-}" ]]; then
        aws s3 rm s3://${INPUT_BUCKET_NAME} --recursive 2>/dev/null || true
        aws s3 rb s3://${INPUT_BUCKET_NAME} 2>/dev/null || true
    fi
    if [[ -n "${OUTPUT_BUCKET_NAME:-}" ]]; then
        aws s3 rm s3://${OUTPUT_BUCKET_NAME} --recursive 2>/dev/null || true
        aws s3 rb s3://${OUTPUT_BUCKET_NAME} 2>/dev/null || true
    fi
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        aws lambda delete-function --function-name ${LAMBDA_FUNCTION_NAME} 2>/dev/null || true
    fi
    if [[ -n "${LAMBDA_ROLE_NAME:-}" ]]; then
        aws iam detach-role-policy --role-name ${LAMBDA_ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        aws iam delete-role-policy --role-name ${LAMBDA_ROLE_NAME} --policy-name S3AccessPolicy 2>/dev/null || true
        aws iam delete-role --role-name ${LAMBDA_ROLE_NAME} 2>/dev/null || true
    fi
    # Clean up temporary files
    rm -f trust-policy.json s3-policy.json lambda_function.py lambda-deployment.zip notification-config.json
    exit 1
}

trap cleanup_on_error ERR

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if required commands exist
    local required_commands=("zip" "cat" "grep" "sed")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command '$cmd' is not available."
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region not configured. Please set it with 'aws configure set region <region>'"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set resource names
    export INPUT_BUCKET_NAME="json-input-${RANDOM_SUFFIX}"
    export OUTPUT_BUCKET_NAME="csv-output-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="json-csv-converter-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="json-csv-converter-role-${RANDOM_SUFFIX}"
    
    log_success "Environment configured - AWS Region: $AWS_REGION, Account: $AWS_ACCOUNT_ID"
    log_info "Resource names generated with suffix: $RANDOM_SUFFIX"
}

# Function to create S3 buckets
create_s3_buckets() {
    log_info "Creating S3 buckets..."
    
    # Create input bucket for JSON files
    if ! aws s3api head-bucket --bucket ${INPUT_BUCKET_NAME} 2>/dev/null; then
        aws s3 mb s3://${INPUT_BUCKET_NAME} --region ${AWS_REGION}
        log_success "Created input bucket: ${INPUT_BUCKET_NAME}"
    else
        log_warning "Input bucket ${INPUT_BUCKET_NAME} already exists"
    fi
    
    # Create output bucket for CSV files
    if ! aws s3api head-bucket --bucket ${OUTPUT_BUCKET_NAME} 2>/dev/null; then
        aws s3 mb s3://${OUTPUT_BUCKET_NAME} --region ${AWS_REGION}
        log_success "Created output bucket: ${OUTPUT_BUCKET_NAME}"
    else
        log_warning "Output bucket ${OUTPUT_BUCKET_NAME} already exists"
    fi
    
    # Enable versioning for data protection
    aws s3api put-bucket-versioning \
        --bucket ${INPUT_BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    aws s3api put-bucket-versioning \
        --bucket ${OUTPUT_BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    log_success "S3 buckets created with versioning enabled"
}

# Function to create IAM role
create_iam_role() {
    log_info "Creating IAM role for Lambda function..."
    
    # Create trust policy for Lambda service
    cat > trust-policy.json << 'EOF'
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
    if aws iam get-role --role-name ${LAMBDA_ROLE_NAME} >/dev/null 2>&1; then
        log_warning "IAM role ${LAMBDA_ROLE_NAME} already exists"
    else
        # Create IAM role
        aws iam create-role \
            --role-name ${LAMBDA_ROLE_NAME} \
            --assume-role-policy-document file://trust-policy.json
        log_success "Created IAM role: ${LAMBDA_ROLE_NAME}"
    fi
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    log_success "IAM role created and configured"
}

# Function to create S3 access policy
create_s3_policy() {
    log_info "Creating S3 access policy for Lambda..."
    
    # Create S3 access policy
    cat > s3-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::${INPUT_BUCKET_NAME}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::${OUTPUT_BUCKET_NAME}/*"
        }
    ]
}
EOF
    
    # Create and attach the policy
    aws iam put-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-name S3AccessPolicy \
        --policy-document file://s3-policy.json
    
    log_success "S3 access policy attached to Lambda role"
}

# Function to create Lambda function code
create_lambda_code() {
    log_info "Creating Lambda function code..."
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import csv
import boto3
import urllib.parse
import os
from io import StringIO

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Get bucket and object key from S3 event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(
            event['Records'][0]['s3']['object']['key'], 
            encoding='utf-8'
        )
        
        print(f"Processing file: {key} from bucket: {bucket}")
        
        # Read JSON file from S3
        response = s3_client.get_object(Bucket=bucket, Key=key)
        json_content = response['Body'].read().decode('utf-8')
        data = json.loads(json_content)
        
        # Convert JSON to CSV
        if isinstance(data, list) and len(data) > 0:
            # Handle array of objects
            csv_buffer = StringIO()
            if isinstance(data[0], dict):
                fieldnames = data[0].keys()
                writer = csv.DictWriter(csv_buffer, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(data)
            else:
                # Handle array of simple values
                writer = csv.writer(csv_buffer)
                writer.writerow(['value'])  # Add header for simple values
                for item in data:
                    writer.writerow([item])
        elif isinstance(data, dict):
            # Handle single object
            csv_buffer = StringIO()
            writer = csv.DictWriter(csv_buffer, fieldnames=data.keys())
            writer.writeheader()
            writer.writerow(data)
        else:
            raise ValueError("Unsupported JSON structure")
        
        # Generate output file name
        output_key = key.replace('.json', '.csv')
        
        # Upload CSV to output bucket
        s3_client.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=output_key,
            Body=csv_buffer.getvalue(),
            ContentType='text/csv'
        )
        
        print(f"Successfully converted {key} to {output_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Successfully converted {key} to CSV')
        }
        
    except Exception as e:
        print(f"Error processing file {key}: {str(e)}")
        raise e
EOF
    
    # Create deployment package
    zip lambda-deployment.zip lambda_function.py
    
    log_success "Lambda function code created and packaged"
}

# Function to deploy Lambda function
deploy_lambda_function() {
    log_info "Deploying Lambda function..."
    
    # Get IAM role ARN
    ROLE_ARN=$(aws iam get-role \
        --role-name ${LAMBDA_ROLE_NAME} \
        --query 'Role.Arn' --output text)
    
    # Wait for role to be available (eventual consistency)
    log_info "Waiting for IAM role to be available..."
    sleep 10
    
    # Check if function already exists
    if aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME} >/dev/null 2>&1; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} already exists, updating..."
        aws lambda update-function-code \
            --function-name ${LAMBDA_FUNCTION_NAME} \
            --zip-file fileb://lambda-deployment.zip
        
        aws lambda update-function-configuration \
            --function-name ${LAMBDA_FUNCTION_NAME} \
            --environment Variables="{OUTPUT_BUCKET=${OUTPUT_BUCKET_NAME}}"
    else
        # Create Lambda function
        aws lambda create-function \
            --function-name ${LAMBDA_FUNCTION_NAME} \
            --runtime python3.12 \
            --role ${ROLE_ARN} \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://lambda-deployment.zip \
            --timeout 60 \
            --memory-size 256 \
            --environment Variables="{OUTPUT_BUCKET=${OUTPUT_BUCKET_NAME}}"
    fi
    
    # Wait for function to be active
    log_info "Waiting for Lambda function to be active..."
    aws lambda wait function-active --function-name ${LAMBDA_FUNCTION_NAME}
    
    log_success "Lambda function deployed successfully"
}

# Function to configure S3 event trigger
configure_s3_trigger() {
    log_info "Configuring S3 event trigger..."
    
    # Add permission for S3 to invoke Lambda (idempotent)
    aws lambda add-permission \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --statement-id s3-trigger-permission \
        --source-arn arn:aws:s3:::${INPUT_BUCKET_NAME} 2>/dev/null || true
    
    # Get Lambda function ARN
    LAMBDA_ARN=$(aws lambda get-function \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --query 'Configuration.FunctionArn' --output text)
    
    # Create notification configuration
    cat > notification-config.json << EOF
{
    "LambdaConfigurations": [
        {
            "Id": "json-csv-converter-trigger",
            "LambdaFunctionArn": "${LAMBDA_ARN}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".json"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
    
    # Configure S3 bucket notification
    aws s3api put-bucket-notification-configuration \
        --bucket ${INPUT_BUCKET_NAME} \
        --notification-configuration file://notification-config.json
    
    log_success "S3 event trigger configured for JSON files"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing the deployment..."
    
    # Create sample JSON data for testing
    cat > sample-data.json << 'EOF'
[
    {
        "id": 1,
        "name": "John Doe",
        "email": "john@example.com",
        "department": "Engineering"
    },
    {
        "id": 2,
        "name": "Jane Smith",
        "email": "jane@example.com",
        "department": "Marketing"
    },
    {
        "id": 3,
        "name": "Bob Wilson",
        "email": "bob@example.com",
        "department": "Sales"
    }
]
EOF
    
    # Upload test file to input bucket
    aws s3 cp sample-data.json s3://${INPUT_BUCKET_NAME}/
    log_success "Test JSON file uploaded to input bucket"
    
    # Wait for processing
    log_info "Waiting for Lambda function to process the file..."
    sleep 15
    
    # Check if CSV file was created
    if aws s3 ls s3://${OUTPUT_BUCKET_NAME}/sample-data.csv >/dev/null 2>&1; then
        log_success "CSV file successfully created in output bucket"
        # Download and display the converted CSV file
        aws s3 cp s3://${OUTPUT_BUCKET_NAME}/sample-data.csv ./
        log_info "Sample CSV content:"
        cat sample-data.csv
    else
        log_warning "CSV file not found. Check Lambda logs for potential issues."
    fi
    
    # Clean up test files
    rm -f sample-data.json sample-data.csv
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > deployment-info.json << EOF
{
    "deployment_timestamp": "$(date -Iseconds)",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "input_bucket_name": "${INPUT_BUCKET_NAME}",
    "output_bucket_name": "${OUTPUT_BUCKET_NAME}",
    "lambda_function_name": "${LAMBDA_FUNCTION_NAME}",
    "lambda_role_name": "${LAMBDA_ROLE_NAME}",
    "random_suffix": "${RANDOM_SUFFIX}"
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    rm -f trust-policy.json s3-policy.json lambda_function.py lambda-deployment.zip notification-config.json
    log_success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log_info "========================================="
    log_info "JSON to CSV Converter Deployment Script"
    log_info "========================================="
    
    check_prerequisites
    setup_environment
    create_s3_buckets
    create_iam_role
    create_s3_policy
    create_lambda_code
    deploy_lambda_function
    configure_s3_trigger
    test_deployment
    save_deployment_info
    cleanup_temp_files
    
    DEPLOYMENT_END_TIME=$(date)
    log_success "========================================="
    log_success "Deployment completed successfully!"
    log_success "Started:  $DEPLOYMENT_START_TIME"
    log_success "Finished: $DEPLOYMENT_END_TIME"
    log_success "========================================="
    log_info ""
    log_info "Resources created:"
    log_info "  - Input S3 Bucket: ${INPUT_BUCKET_NAME}"
    log_info "  - Output S3 Bucket: ${OUTPUT_BUCKET_NAME}"
    log_info "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log_info "  - IAM Role: ${LAMBDA_ROLE_NAME}"
    log_info ""
    log_info "To test the solution:"
    log_info "  1. Upload a JSON file to: s3://${INPUT_BUCKET_NAME}/"
    log_info "  2. Check for converted CSV in: s3://${OUTPUT_BUCKET_NAME}/"
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi