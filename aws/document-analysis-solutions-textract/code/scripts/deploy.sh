#!/bin/bash

# AWS Textract Document Analysis Solution - Deployment Script
# This script deploys the complete document analysis pipeline with error handling and logging

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
DEPLOYMENT_NAME="textract-document-analysis"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Status output functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Cleanup function for errors
cleanup_on_error() {
    error "Deployment failed. Starting cleanup..."
    
    # Clean up any partially created resources
    if [[ -n "${BUCKET_INPUT:-}" ]]; then
        aws s3 rm s3://${BUCKET_INPUT} --recursive 2>/dev/null || true
        aws s3 rb s3://${BUCKET_INPUT} 2>/dev/null || true
    fi
    
    if [[ -n "${BUCKET_OUTPUT:-}" ]]; then
        aws s3 rm s3://${BUCKET_OUTPUT} --recursive 2>/dev/null || true
        aws s3 rb s3://${BUCKET_OUTPUT} 2>/dev/null || true
    fi
    
    # Remove temp files
    rm -f trust-policy.json lambda-policy.json notification-config.json
    rm -f textract_processor.py textract_processor.zip
    
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
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
    
    # Check required permissions
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$account_id" ]]; then
        error "Unable to determine AWS account ID"
        exit 1
    fi
    
    # Check region
    local region=$(aws configure get region)
    if [[ -z "$region" ]]; then
        error "AWS region not configured. Please set it with 'aws configure set region <region>'"
        exit 1
    fi
    
    # Check Textract service availability
    if ! aws textract describe-document-text-detection-job --job-id "test" 2>&1 | grep -q "InvalidJobIdException\|InvalidParameterException"; then
        warning "Textract service may not be available in region $region"
    fi
    
    success "Prerequisites check completed"
}

# Generate unique identifiers
generate_identifiers() {
    info "Generating unique resource identifiers..."
    
    # Generate random suffix for unique naming
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    # Export environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export BUCKET_INPUT="textract-input-${RANDOM_SUFFIX}"
    export BUCKET_OUTPUT="textract-output-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION="textract-processor-${RANDOM_SUFFIX}"
    export SNS_TOPIC="textract-notifications-${RANDOM_SUFFIX}"
    export IAM_ROLE="textract-lambda-role-${RANDOM_SUFFIX}"
    
    info "Generated identifiers:"
    info "  - Input Bucket: ${BUCKET_INPUT}"
    info "  - Output Bucket: ${BUCKET_OUTPUT}"
    info "  - Lambda Function: ${LAMBDA_FUNCTION}"
    info "  - SNS Topic: ${SNS_TOPIC}"
    info "  - IAM Role: ${IAM_ROLE}"
    
    # Save identifiers to file for cleanup script
    cat > "${SCRIPT_DIR}/deployment-vars.env" << EOF
export AWS_REGION=${AWS_REGION}
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
export BUCKET_INPUT=${BUCKET_INPUT}
export BUCKET_OUTPUT=${BUCKET_OUTPUT}
export LAMBDA_FUNCTION=${LAMBDA_FUNCTION}
export SNS_TOPIC=${SNS_TOPIC}
export IAM_ROLE=${IAM_ROLE}
export RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Resource identifiers generated and saved"
}

# Create S3 buckets
create_s3_buckets() {
    info "Creating S3 buckets..."
    
    # Create input bucket
    if aws s3api head-bucket --bucket "${BUCKET_INPUT}" 2>/dev/null; then
        warning "Input bucket ${BUCKET_INPUT} already exists"
    else
        aws s3 mb s3://${BUCKET_INPUT} --region ${AWS_REGION}
        success "Created input bucket: ${BUCKET_INPUT}"
    fi
    
    # Create output bucket
    if aws s3api head-bucket --bucket "${BUCKET_OUTPUT}" 2>/dev/null; then
        warning "Output bucket ${BUCKET_OUTPUT} already exists"
    else
        aws s3 mb s3://${BUCKET_OUTPUT} --region ${AWS_REGION}
        success "Created output bucket: ${BUCKET_OUTPUT}"
    fi
    
    # Enable versioning on buckets
    aws s3api put-bucket-versioning --bucket ${BUCKET_INPUT} --versioning-configuration Status=Enabled
    aws s3api put-bucket-versioning --bucket ${BUCKET_OUTPUT} --versioning-configuration Status=Enabled
    
    success "S3 buckets created and configured"
}

# Create IAM role and policies
create_iam_role() {
    info "Creating IAM role and policies..."
    
    # Create trust policy
    cat > trust-policy.json << EOF
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
    
    # Check if role exists
    if aws iam get-role --role-name ${IAM_ROLE} &>/dev/null; then
        warning "IAM role ${IAM_ROLE} already exists"
    else
        # Create IAM role
        aws iam create-role \
            --role-name ${IAM_ROLE} \
            --assume-role-policy-document file://trust-policy.json
        success "Created IAM role: ${IAM_ROLE}"
    fi
    
    # Attach managed policies
    aws iam attach-role-policy \
        --role-name ${IAM_ROLE} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name ${IAM_ROLE} \
        --policy-arn arn:aws:iam::aws:policy/AmazonTextractFullAccess
    
    # Create custom policy for S3 and SNS access
    cat > lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_INPUT}/*",
                "arn:aws:s3:::${BUCKET_OUTPUT}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC}"
        }
    ]
}
EOF
    
    # Apply custom policy
    aws iam put-role-policy \
        --role-name ${IAM_ROLE} \
        --policy-name CustomTextractPolicy \
        --policy-document file://lambda-policy.json
    
    success "IAM role and policies configured"
}

# Create SNS topic
create_sns_topic() {
    info "Creating SNS topic..."
    
    # Check if topic exists
    if aws sns get-topic-attributes --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC}" &>/dev/null; then
        warning "SNS topic ${SNS_TOPIC} already exists"
    else
        aws sns create-topic --name ${SNS_TOPIC}
        success "Created SNS topic: ${SNS_TOPIC}"
    fi
    
    # Get topic ARN
    export SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC} \
        --query 'Attributes.TopicArn' --output text)
    
    info "SNS Topic ARN: ${SNS_TOPIC_ARN}"
}

# Create Lambda function
create_lambda_function() {
    info "Creating Lambda function..."
    
    # Create Lambda function code
    cat > textract_processor.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

textract = boto3.client('textract')
s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        # Parse S3 event
        s3_event = event['Records'][0]['s3']
        bucket_name = s3_event['bucket']['name']
        object_key = s3_event['object']['key']
        
        print(f"Processing document: {object_key} from bucket: {bucket_name}")
        
        # Analyze document with Textract
        response = textract.analyze_document(
            Document={
                'S3Object': {
                    'Bucket': bucket_name,
                    'Name': object_key
                }
            },
            FeatureTypes=['TABLES', 'FORMS', 'QUERIES'],
            QueriesConfig={
                'Queries': [
                    {'Text': 'What is the document type?'},
                    {'Text': 'What is the total amount?'},
                    {'Text': 'What is the date?'}
                ]
            }
        )
        
        # Extract structured data
        extracted_data = {
            'document_name': object_key,
            'processed_at': datetime.now().isoformat(),
            'blocks': response['Blocks'],
            'document_metadata': response['DocumentMetadata']
        }
        
        # Save results to output bucket
        output_key = f"processed/{object_key.split('/')[-1]}.json"
        s3.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=output_key,
            Body=json.dumps(extracted_data, indent=2),
            ContentType='application/json'
        )
        
        # Send notification
        message = f"Document processed successfully: {object_key}"
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=message,
            Subject='Textract Processing Complete'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Document processed successfully',
                'output_location': f"s3://{os.environ['OUTPUT_BUCKET']}/{output_key}"
            })
        }
        
    except Exception as e:
        print(f"Error processing document: {str(e)}")
        
        # Send error notification
        error_message = f"Error processing {object_key}: {str(e)}"
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=error_message,
            Subject='Textract Processing Error'
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
EOF
    
    # Create deployment package
    zip -q textract_processor.zip textract_processor.py
    
    # Wait for IAM role to propagate
    info "Waiting for IAM role propagation..."
    sleep 30
    
    # Check if Lambda function exists
    if aws lambda get-function --function-name ${LAMBDA_FUNCTION} &>/dev/null; then
        warning "Lambda function ${LAMBDA_FUNCTION} already exists, updating..."
        aws lambda update-function-code \
            --function-name ${LAMBDA_FUNCTION} \
            --zip-file fileb://textract_processor.zip
        
        aws lambda update-function-configuration \
            --function-name ${LAMBDA_FUNCTION} \
            --environment Variables="{OUTPUT_BUCKET=${BUCKET_OUTPUT},SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}"
    else
        # Create Lambda function
        aws lambda create-function \
            --function-name ${LAMBDA_FUNCTION} \
            --runtime python3.9 \
            --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE} \
            --handler textract_processor.lambda_handler \
            --zip-file fileb://textract_processor.zip \
            --timeout 300 \
            --memory-size 512 \
            --environment Variables="{OUTPUT_BUCKET=${BUCKET_OUTPUT},SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}"
    fi
    
    success "Lambda function created/updated: ${LAMBDA_FUNCTION}"
}

# Configure S3 event notification
configure_s3_events() {
    info "Configuring S3 event notifications..."
    
    # Get Lambda function ARN
    export LAMBDA_ARN=$(aws lambda get-function \
        --function-name ${LAMBDA_FUNCTION} \
        --query 'Configuration.FunctionArn' --output text)
    
    # Add permission for S3 to invoke Lambda
    aws lambda add-permission \
        --function-name ${LAMBDA_FUNCTION} \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --source-arn arn:aws:s3:::${BUCKET_INPUT} \
        --statement-id s3-invoke-permission-${RANDOM_SUFFIX} 2>/dev/null || true
    
    # Create S3 notification configuration
    cat > notification-config.json << EOF
{
    "LambdaConfigurations": [
        {
            "Id": "textract-processor-trigger",
            "LambdaFunctionArn": "${LAMBDA_ARN}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".pdf"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
    
    # Configure S3 event notification
    aws s3api put-bucket-notification-configuration \
        --bucket ${BUCKET_INPUT} \
        --notification-configuration file://notification-config.json
    
    success "S3 event notification configured"
}

# Create test document
create_test_document() {
    info "Creating test document..."
    
    # Create a simple test document
    cat > test-document.txt << 'EOF'
SAMPLE INVOICE

Invoice Number: INV-2024-001
Date: 2024-01-15
Due Date: 2024-02-15

Bill To:
John Doe
123 Main Street
Anytown, ST 12345

Description          Quantity    Unit Price    Total
Consulting Services      10        $150.00    $1,500.00
Software License          1        $500.00      $500.00

Subtotal:                                    $2,000.00
Tax (8%):                                      $160.00
Total:                                       $2,160.00

Terms: Net 30 days
EOF
    
    # Upload test document
    aws s3 cp test-document.txt s3://${BUCKET_INPUT}/test-documents/sample-invoice.pdf
    
    success "Test document uploaded to input bucket"
}

# Validate deployment
validate_deployment() {
    info "Validating deployment..."
    
    # Check S3 buckets
    if aws s3api head-bucket --bucket ${BUCKET_INPUT} &>/dev/null; then
        success "Input bucket is accessible"
    else
        error "Input bucket is not accessible"
        return 1
    fi
    
    if aws s3api head-bucket --bucket ${BUCKET_OUTPUT} &>/dev/null; then
        success "Output bucket is accessible"
    else
        error "Output bucket is not accessible"
        return 1
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name ${LAMBDA_FUNCTION} &>/dev/null; then
        success "Lambda function is accessible"
    else
        error "Lambda function is not accessible"
        return 1
    fi
    
    # Check SNS topic
    if aws sns get-topic-attributes --topic-arn ${SNS_TOPIC_ARN} &>/dev/null; then
        success "SNS topic is accessible"
    else
        error "SNS topic is not accessible"
        return 1
    fi
    
    # Wait for processing and check results
    info "Waiting for test document processing..."
    sleep 60
    
    # Check if test document was processed
    if aws s3 ls s3://${BUCKET_OUTPUT}/processed/ | grep -q "sample-invoice.pdf.json"; then
        success "Test document processed successfully"
    else
        warning "Test document processing may still be in progress"
    fi
    
    success "Deployment validation completed"
}

# Cleanup temporary files
cleanup_temp_files() {
    info "Cleaning up temporary files..."
    
    rm -f trust-policy.json lambda-policy.json notification-config.json
    rm -f textract_processor.py textract_processor.zip
    rm -f test-document.txt
    
    success "Temporary files cleaned up"
}

# Display deployment summary
display_summary() {
    info "Deployment Summary:"
    info "==================="
    info "AWS Region: ${AWS_REGION}"
    info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    info "Input Bucket: s3://${BUCKET_INPUT}"
    info "Output Bucket: s3://${BUCKET_OUTPUT}"
    info "Lambda Function: ${LAMBDA_FUNCTION}"
    info "SNS Topic: ${SNS_TOPIC}"
    info "IAM Role: ${IAM_ROLE}"
    info ""
    info "To test the solution:"
    info "1. Upload a PDF document to: s3://${BUCKET_INPUT}/test-documents/"
    info "2. Check processed results in: s3://${BUCKET_OUTPUT}/processed/"
    info "3. Monitor Lambda logs: aws logs tail /aws/lambda/${LAMBDA_FUNCTION}"
    info ""
    info "To clean up resources, run: ./destroy.sh"
    info ""
    success "Deployment completed successfully!"
}

# Main execution
main() {
    log "Starting AWS Textract Document Analysis Solution deployment..."
    
    check_prerequisites
    generate_identifiers
    create_s3_buckets
    create_iam_role
    create_sns_topic
    create_lambda_function
    configure_s3_events
    create_test_document
    validate_deployment
    cleanup_temp_files
    display_summary
    
    log "Deployment completed successfully at $(date)"
}

# Run main function
main "$@"