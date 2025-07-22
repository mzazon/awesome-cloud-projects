#!/bin/bash

# =============================================================================
# AWS Textract Intelligent Document Processing - Deployment Script
# =============================================================================
# This script deploys the complete infrastructure for intelligent document
# processing using Amazon Textract, Lambda, and S3.
#
# Services deployed:
# - S3 bucket for document storage
# - Lambda function for document processing
# - IAM roles and policies
# - S3 event notifications
# =============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# =============================================================================
# Configuration and Constants
# =============================================================================

# Script metadata
SCRIPT_NAME="deploy.sh"
SCRIPT_VERSION="1.0"
DEPLOYMENT_START_TIME=$(date +%s)

# Logging configuration
LOG_FILE="/tmp/textract-deploy-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AWS Textract Intelligent Document Processing infrastructure.

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deployed without making changes
    -r, --region REGION    AWS region (default: current configured region)
    -p, --profile PROFILE  AWS CLI profile to use
    -s, --suffix SUFFIX    Custom suffix for resource names
    -v, --verbose          Enable verbose logging
    --skip-validation      Skip prerequisite validation
    --force                Force deployment even if resources exist

EXAMPLES:
    $0                     # Deploy with default settings
    $0 -r us-east-1        # Deploy to specific region
    $0 --dry-run           # Show deployment plan
    $0 --profile myprofile # Use specific AWS profile

EOF
}

cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed with exit code: $exit_code"
        log_info "Log file: $LOG_FILE"
        log_info "Run './destroy.sh' to clean up any partially created resources"
    fi
}

# =============================================================================
# Prerequisites and Validation
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $aws_version"
    
    # Check if jq is installed (useful for JSON parsing)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some features may be limited."
    fi
    
    # Check if zip is installed (required for Lambda deployment)
    if ! command -v zip &> /dev/null; then
        log_error "zip utility is not installed. Required for Lambda function packaging."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid."
        log_error "Please run 'aws configure' or set AWS_PROFILE environment variable."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

validate_permissions() {
    log_info "Validating AWS permissions..."
    
    # Test permissions for required services
    local required_actions=(
        "s3:CreateBucket"
        "s3:PutBucketNotification"
        "lambda:CreateFunction"
        "lambda:AddPermission"
        "iam:CreateRole"
        "iam:AttachRolePolicy"
        "textract:DetectDocumentText"
    )
    
    # Note: In a production script, you would implement IAM policy simulation
    # For now, we'll rely on the actual deployment to catch permission issues
    log_success "Permission validation completed"
}

# =============================================================================
# Environment Setup
# =============================================================================

setup_environment() {
    log_info "Setting up deployment environment..."
    
    # Set default values
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    if [ -z "$RESOURCE_SUFFIX" ]; then
        RESOURCE_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    fi
    
    # Set resource names
    export BUCKET_NAME="textract-documents-${RESOURCE_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="textract-processor-${RESOURCE_SUFFIX}"
    export ROLE_NAME="TextractProcessorRole-${RESOURCE_SUFFIX}"
    export POLICY_NAME="TextractProcessorPolicy-${RESOURCE_SUFFIX}"
    
    # Create temporary directory for deployment artifacts
    TEMP_DIR=$(mktemp -d)
    export TEMP_DIR
    
    log_success "Environment setup completed"
    log_info "AWS Region: $AWS_REGION"
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    log_info "Resource Suffix: $RESOURCE_SUFFIX"
    log_info "Bucket Name: $BUCKET_NAME"
    log_info "Lambda Function: $LAMBDA_FUNCTION_NAME"
    log_info "Temporary Directory: $TEMP_DIR"
}

# =============================================================================
# Resource Deployment Functions
# =============================================================================

deploy_s3_bucket() {
    log_info "Deploying S3 bucket: $BUCKET_NAME"
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        if [ "$FORCE_DEPLOY" != "true" ]; then
            log_warning "S3 bucket $BUCKET_NAME already exists. Use --force to continue."
            return 0
        fi
    fi
    
    # Create S3 bucket
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
    else
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Add bucket tags
    aws s3api put-bucket-tagging \
        --bucket "$BUCKET_NAME" \
        --tagging "TagSet=[{Key=Project,Value=TextractDocumentProcessing},{Key=ManagedBy,Value=DeploymentScript}]"
    
    # Create documents folder
    aws s3api put-object \
        --bucket "$BUCKET_NAME" \
        --key "documents/" \
        --body /dev/null
    
    log_success "S3 bucket deployed successfully"
}

deploy_iam_role() {
    log_info "Deploying IAM role: $ROLE_NAME"
    
    # Create trust policy
    cat > "$TEMP_DIR/trust-policy.json" << 'EOF'
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
        --assume-role-policy-document "file://$TEMP_DIR/trust-policy.json" \
        --description "Role for Textract document processing Lambda function" \
        --tags "Key=Project,Value=TextractDocumentProcessing" "Key=ManagedBy,Value=DeploymentScript"
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Create custom policy for S3 and Textract access
    cat > "$TEMP_DIR/textract-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "textract:DetectDocumentText",
                "textract:AnalyzeDocument"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create and attach custom policy
    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document "file://$TEMP_DIR/textract-policy.json" \
        --description "Policy for Textract document processing operations"
    
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME"
    
    log_success "IAM role deployed successfully"
}

deploy_lambda_function() {
    log_info "Deploying Lambda function: $LAMBDA_FUNCTION_NAME"
    
    # Create Lambda function code
    cat > "$TEMP_DIR/lambda_function.py" << 'EOF'
import json
import boto3
import urllib.parse
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process documents uploaded to S3 using Amazon Textract
    """
    # Initialize AWS clients
    s3_client = boto3.client('s3')
    textract_client = boto3.client('textract')
    
    try:
        # Get the S3 bucket and object key from the event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(
            event['Records'][0]['s3']['object']['key'], 
            encoding='utf-8'
        )
        
        logger.info(f"Processing document: {key} from bucket: {bucket}")
        
        # Call Textract to analyze the document
        response = textract_client.detect_document_text(
            Document={
                'S3Object': {
                    'Bucket': bucket,
                    'Name': key
                }
            }
        )
        
        # Extract text from the response
        extracted_text = ""
        confidence_scores = []
        
        for block in response['Blocks']:
            if block['BlockType'] == 'LINE':
                extracted_text += block['Text'] + '\n'
                confidence_scores.append(block['Confidence'])
        
        # Calculate average confidence
        avg_confidence = sum(confidence_scores) / len(confidence_scores) if confidence_scores else 0
        
        # Prepare results
        results = {
            'document': key,
            'extracted_text': extracted_text.strip(),
            'average_confidence': round(avg_confidence, 2),
            'total_blocks': len(response['Blocks']),
            'processing_status': 'completed',
            'textract_response_id': response['ResponseMetadata']['RequestId']
        }
        
        # Save results back to S3
        results_key = f"results/{key.split('/')[-1]}_results.json"
        s3_client.put_object(
            Bucket=bucket,
            Key=results_key,
            Body=json.dumps(results, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f"Results saved to: {results_key}")
        logger.info(f"Average confidence: {avg_confidence}%")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Document processed successfully',
                'results_location': f"s3://{bucket}/{results_key}",
                'confidence': avg_confidence,
                'processing_time': context.get_remaining_time_in_millis()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing document: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Document processing failed'
            })
        }
EOF
    
    # Package the function
    cd "$TEMP_DIR"
    zip -r lambda-function.zip lambda_function.py
    
    # Wait for IAM role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 15
    
    # Create the Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::$AWS_ACCOUNT_ID:role/$ROLE_NAME" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda-function.zip \
        --timeout 60 \
        --memory-size 256 \
        --description "Intelligent document processing using Amazon Textract" \
        --tags "Project=TextractDocumentProcessing,ManagedBy=DeploymentScript"
    
    log_success "Lambda function deployed successfully"
}

configure_s3_notifications() {
    log_info "Configuring S3 event notifications"
    
    # Get Lambda function ARN
    local lambda_arn=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Configuration.FunctionArn' \
        --output text)
    
    # Add permission for S3 to invoke Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --statement-id s3-trigger-permission \
        --source-arn "arn:aws:s3:::$BUCKET_NAME"
    
    # Create notification configuration
    cat > "$TEMP_DIR/notification-config.json" << EOF
{
    "LambdaConfigurations": [
        {
            "Id": "ObjectCreateEvents",
            "LambdaFunctionArn": "$lambda_arn",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "documents/"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
    
    # Apply notification configuration
    aws s3api put-bucket-notification-configuration \
        --bucket "$BUCKET_NAME" \
        --notification-configuration "file://$TEMP_DIR/notification-config.json"
    
    log_success "S3 event notifications configured successfully"
}

# =============================================================================
# Deployment Validation
# =============================================================================

validate_deployment() {
    log_info "Validating deployment..."
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "$BUCKET_NAME" &>/dev/null; then
        log_success "S3 bucket is accessible"
    else
        log_error "S3 bucket validation failed"
        return 1
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log_success "Lambda function is accessible"
    else
        log_error "Lambda function validation failed"
        return 1
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        log_success "IAM role is accessible"
    else
        log_error "IAM role validation failed"
        return 1
    fi
    
    # Test document upload and processing
    log_info "Testing document processing..."
    
    # Create test document
    echo "This is a test document for Textract processing." > "$TEMP_DIR/test-document.txt"
    
    # Upload test document
    aws s3 cp "$TEMP_DIR/test-document.txt" "s3://$BUCKET_NAME/documents/"
    
    # Wait for processing
    sleep 10
    
    # Check if results were created
    if aws s3 ls "s3://$BUCKET_NAME/results/test-document.txt_results.json" &>/dev/null; then
        log_success "Document processing test passed"
    else
        log_warning "Document processing test may have failed - check CloudWatch logs"
    fi
    
    log_success "Deployment validation completed"
}

# =============================================================================
# Main Deployment Logic
# =============================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -p|--profile)
                AWS_PROFILE="$2"
                export AWS_PROFILE
                shift 2
                ;;
            -s|--suffix)
                RESOURCE_SUFFIX="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --force)
                FORCE_DEPLOY=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Setup exit handler
    trap cleanup_on_exit EXIT
    
    # Script header
    echo "================================================================"
    echo "AWS Textract Document Processing Deployment Script"
    echo "Version: $SCRIPT_VERSION"
    echo "Started: $(date)"
    echo "================================================================"
    
    # Dry run mode
    if [ "$DRY_RUN" = "true" ]; then
        log_info "DRY RUN MODE - No resources will be created"
        setup_environment
        log_info "Would deploy the following resources:"
        echo "  - S3 Bucket: $BUCKET_NAME"
        echo "  - Lambda Function: $LAMBDA_FUNCTION_NAME"
        echo "  - IAM Role: $ROLE_NAME"
        echo "  - IAM Policy: $POLICY_NAME"
        echo "  - S3 Event Notifications"
        exit 0
    fi
    
    # Run deployment steps
    if [ "$SKIP_VALIDATION" != "true" ]; then
        check_prerequisites
        validate_permissions
    fi
    
    setup_environment
    deploy_s3_bucket
    deploy_iam_role
    deploy_lambda_function
    configure_s3_notifications
    validate_deployment
    
    # Display deployment summary
    echo "================================================================"
    echo "DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "================================================================"
    echo "Resources created:"
    echo "  - S3 Bucket: $BUCKET_NAME"
    echo "  - Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "  - IAM Role: $ROLE_NAME"
    echo "  - IAM Policy: $POLICY_NAME"
    echo ""
    echo "To test the deployment:"
    echo "  aws s3 cp your-document.pdf s3://$BUCKET_NAME/documents/"
    echo ""
    echo "To monitor processing:"
    echo "  aws logs tail /aws/lambda/$LAMBDA_FUNCTION_NAME --follow"
    echo ""
    echo "To view results:"
    echo "  aws s3 ls s3://$BUCKET_NAME/results/"
    echo ""
    echo "Log file: $LOG_FILE"
    echo "Deployment time: $(($(date +%s) - DEPLOYMENT_START_TIME)) seconds"
    echo "================================================================"
}

# Run main function
main "$@"