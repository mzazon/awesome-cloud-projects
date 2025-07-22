#!/bin/bash

# Deploy script for AI-Powered Infrastructure Code Generation with Amazon Q Developer
# This script deploys the complete infrastructure needed for the recipe solution

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly DRY_RUN=${DRY_RUN:-false}

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Function to log info messages
log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

# Function to log success messages
log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

# Function to log warning messages
log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

# Function to log error messages
log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: ${aws_version}"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check if jq is installed for JSON processing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some validation steps may be skipped."
    fi
    
    # Check required AWS permissions
    log_info "Validating AWS permissions..."
    local account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    local region=$(aws configure get region 2>/dev/null || echo "us-east-1")
    
    if [[ -z "${account_id}" ]]; then
        log_error "Unable to retrieve AWS account ID. Check your credentials."
        exit 1
    fi
    
    log_info "AWS Account ID: ${account_id}"
    log_info "AWS Region: ${region}"
    
    # Export global variables
    export AWS_ACCOUNT_ID="${account_id}"
    export AWS_REGION="${region}"
    
    log_success "Prerequisites check completed successfully"
}

# Function to generate unique resource names
generate_resource_names() {
    log_info "Generating unique resource names..."
    
    # Generate random suffix for unique naming
    local random_suffix
    if command -v aws &> /dev/null; then
        random_suffix=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    else
        random_suffix=$(date +%s | tail -c 6)
    fi
    
    # Export resource names
    export BUCKET_NAME="q-developer-templates-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="template-processor-${random_suffix}"
    export IAM_ROLE_NAME="q-developer-automation-role-${random_suffix}"
    export CUSTOM_POLICY_NAME="QDeveloperTemplateProcessorPolicy-${random_suffix}"
    
    log_info "Generated resource names:"
    log_info "  S3 Bucket: ${BUCKET_NAME}"
    log_info "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log_info "  IAM Role: ${IAM_ROLE_NAME}"
    log_info "  IAM Policy: ${CUSTOM_POLICY_NAME}"
}

# Function to create S3 bucket
create_s3_bucket() {
    log_info "Creating S3 bucket for template storage..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create S3 bucket: ${BUCKET_NAME}"
        return 0
    fi
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        log_warning "S3 bucket ${BUCKET_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create S3 bucket with region-specific configuration
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
        aws s3 mb "s3://${BUCKET_NAME}"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "${BUCKET_NAME}" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "${BUCKET_NAME}" \
        --public-access-block-configuration \
        'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
    
    log_success "S3 bucket created successfully: ${BUCKET_NAME}"
}

# Function to create IAM role and policies
create_iam_resources() {
    log_info "Creating IAM role and policies..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create IAM role: ${IAM_ROLE_NAME}"
        return 0
    fi
    
    # Check if role already exists
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        log_warning "IAM role ${IAM_ROLE_NAME} already exists, skipping creation"
        export LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "${IAM_ROLE_NAME}" --query 'Role.Arn' --output text)
        return 0
    fi
    
    # Create trust policy
    local trust_policy=$(cat << 'EOF'
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
)
    
    # Create IAM role
    aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document "${trust_policy}" \
        --description "Role for Q Developer template processing Lambda"
    
    # Get role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "${IAM_ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    
    # Attach basic execution role policy
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Create custom policy
    local custom_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:PutObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "cloudformation:ValidateTemplate",
                "cloudformation:CreateStack",
                "cloudformation:DescribeStacks",
                "cloudformation:DescribeStackEvents",
                "cloudformation:UpdateStack",
                "cloudformation:DeleteStack"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:PassRole",
                "iam:CreateRole",
                "iam:AttachRolePolicy",
                "iam:GetRole"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)
    
    # Create and attach custom policy
    aws iam create-policy \
        --policy-name "${CUSTOM_POLICY_NAME}" \
        --policy-document "${custom_policy}" \
        --description "Custom policy for Q Developer template processing"
    
    local custom_policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${CUSTOM_POLICY_NAME}"
    
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "${custom_policy_arn}"
    
    # Wait for role to be available
    log_info "Waiting for IAM role to be available..."
    sleep 10
    
    log_success "IAM resources created successfully"
}

# Function to create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function for template processing..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Lambda function: ${LAMBDA_FUNCTION_NAME}"
        return 0
    fi
    
    # Check if function already exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} already exists, updating code"
        
        # Create deployment package
        local temp_dir=$(mktemp -d)
        local lambda_code="${temp_dir}/index.py"
        
        # Create Lambda function code
        cat > "${lambda_code}" << 'EOF'
import json
import boto3
import logging
from urllib.parse import unquote_plus

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
cfn_client = boto3.client('cloudformation')

def lambda_handler(event, context):
    """
    Process CloudFormation templates uploaded to S3
    Validates templates and optionally deploys infrastructure
    """
    try:
        # Parse S3 event notification
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing template: {key} from bucket: {bucket}")
            
            # Download template from S3
            response = s3_client.get_object(Bucket=bucket, Key=key)
            template_body = response['Body'].read().decode('utf-8')
            
            # Validate CloudFormation template
            try:
                validation_response = cfn_client.validate_template(
                    TemplateBody=template_body
                )
                logger.info(f"Template validation successful: {validation_response.get('Description', 'No description')}")
                
                # Extract metadata from template
                template_data = json.loads(template_body) if template_body.strip().startswith('{') else {}
                stack_name = template_data.get('Metadata', {}).get('StackName', f"q-developer-stack-{key.replace('.json', '').replace('/', '-')}")
                
                # Create CloudFormation stack (optional - controlled by parameter)
                if key.startswith('auto-deploy/'):
                    logger.info(f"Auto-deploying stack: {stack_name}")
                    cfn_client.create_stack(
                        StackName=stack_name,
                        TemplateBody=template_body,
                        Capabilities=['CAPABILITY_IAM', 'CAPABILITY_NAMED_IAM'],
                        Tags=[
                            {'Key': 'Source', 'Value': 'QDeveloperAutomation'},
                            {'Key': 'TemplateFile', 'Value': key}
                        ]
                    )
                    
                # Store validation results
                validation_result = {
                    'template_file': key,
                    'validation_status': 'VALID',
                    'description': validation_response.get('Description', ''),
                    'parameters': validation_response.get('Parameters', []),
                    'capabilities': validation_response.get('Capabilities', [])
                }
                
                # Save validation results to S3
                result_key = f"validation-results/{key.replace('.json', '-validation.json')}"
                s3_client.put_object(
                    Bucket=bucket,
                    Key=result_key,
                    Body=json.dumps(validation_result, indent=2),
                    ContentType='application/json'
                )
                
            except Exception as validation_error:
                logger.error(f"Template validation failed: {str(validation_error)}")
                
                # Store validation error
                error_result = {
                    'template_file': key,
                    'validation_status': 'INVALID',
                    'error': str(validation_error)
                }
                
                result_key = f"validation-results/{key.replace('.json', '-error.json')}"
                s3_client.put_object(
                    Bucket=bucket,
                    Key=result_key,
                    Body=json.dumps(error_result, indent=2),
                    ContentType='application/json'
                )
        
        return {
            'statusCode': 200,
            'body': json.dumps('Template processing completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Lambda execution error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing template: {str(e)}')
        }
EOF
        
        # Create deployment package
        cd "${temp_dir}"
        zip -r lambda-function.zip index.py
        
        # Update function code
        aws lambda update-function-code \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --zip-file fileb://lambda-function.zip
        
        # Cleanup
        cd - > /dev/null
        rm -rf "${temp_dir}"
        
        log_success "Lambda function code updated"
        return 0
    fi
    
    # Create deployment package
    local temp_dir=$(mktemp -d)
    local lambda_code="${temp_dir}/index.py"
    
    # Create Lambda function code (same as above)
    cat > "${lambda_code}" << 'EOF'
import json
import boto3
import logging
from urllib.parse import unquote_plus

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
cfn_client = boto3.client('cloudformation')

def lambda_handler(event, context):
    """
    Process CloudFormation templates uploaded to S3
    Validates templates and optionally deploys infrastructure
    """
    try:
        # Parse S3 event notification
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing template: {key} from bucket: {bucket}")
            
            # Download template from S3
            response = s3_client.get_object(Bucket=bucket, Key=key)
            template_body = response['Body'].read().decode('utf-8')
            
            # Validate CloudFormation template
            try:
                validation_response = cfn_client.validate_template(
                    TemplateBody=template_body
                )
                logger.info(f"Template validation successful: {validation_response.get('Description', 'No description')}")
                
                # Extract metadata from template
                template_data = json.loads(template_body) if template_body.strip().startswith('{') else {}
                stack_name = template_data.get('Metadata', {}).get('StackName', f"q-developer-stack-{key.replace('.json', '').replace('/', '-')}")
                
                # Create CloudFormation stack (optional - controlled by parameter)
                if key.startswith('auto-deploy/'):
                    logger.info(f"Auto-deploying stack: {stack_name}")
                    cfn_client.create_stack(
                        StackName=stack_name,
                        TemplateBody=template_body,
                        Capabilities=['CAPABILITY_IAM', 'CAPABILITY_NAMED_IAM'],
                        Tags=[
                            {'Key': 'Source', 'Value': 'QDeveloperAutomation'},
                            {'Key': 'TemplateFile', 'Value': key}
                        ]
                    )
                    
                # Store validation results
                validation_result = {
                    'template_file': key,
                    'validation_status': 'VALID',
                    'description': validation_response.get('Description', ''),
                    'parameters': validation_response.get('Parameters', []),
                    'capabilities': validation_response.get('Capabilities', [])
                }
                
                # Save validation results to S3
                result_key = f"validation-results/{key.replace('.json', '-validation.json')}"
                s3_client.put_object(
                    Bucket=bucket,
                    Key=result_key,
                    Body=json.dumps(validation_result, indent=2),
                    ContentType='application/json'
                )
                
            except Exception as validation_error:
                logger.error(f"Template validation failed: {str(validation_error)}")
                
                # Store validation error
                error_result = {
                    'template_file': key,
                    'validation_status': 'INVALID',
                    'error': str(validation_error)
                }
                
                result_key = f"validation-results/{key.replace('.json', '-error.json')}"
                s3_client.put_object(
                    Bucket=bucket,
                    Key=result_key,
                    Body=json.dumps(error_result, indent=2),
                    ContentType='application/json'
                )
        
        return {
            'statusCode': 200,
            'body': json.dumps('Template processing completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Lambda execution error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing template: {str(e)}')
        }
EOF
    
    # Create deployment package
    cd "${temp_dir}"
    zip -r lambda-function.zip index.py
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.11 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler index.lambda_handler \
        --zip-file fileb://lambda-function.zip \
        --timeout 60 \
        --memory-size 256 \
        --description "Processes CloudFormation templates from Amazon Q Developer"
    
    # Cleanup
    cd - > /dev/null
    rm -rf "${temp_dir}"
    
    log_success "Lambda function created successfully: ${LAMBDA_FUNCTION_NAME}"
}

# Function to configure S3 event notification
configure_s3_events() {
    log_info "Configuring S3 event notifications..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would configure S3 event notifications"
        return 0
    fi
    
    # Get Lambda function ARN
    local lambda_function_arn=$(aws lambda get-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --query 'Configuration.FunctionArn' --output text)
    
    # Grant S3 permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --source-arn "arn:aws:s3:::${BUCKET_NAME}" \
        --statement-id "s3-trigger-permission-$(date +%s)" 2>/dev/null || true
    
    # Create S3 event notification configuration
    local notification_config=$(cat << EOF
{
    "LambdaConfigurations": [
        {
            "Id": "template-processing-trigger",
            "LambdaFunctionArn": "${lambda_function_arn}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".json"
                        },
                        {
                            "Name": "prefix",
                            "Value": "templates/"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
)
    
    # Apply notification configuration
    echo "${notification_config}" | aws s3api put-bucket-notification-configuration \
        --bucket "${BUCKET_NAME}" \
        --notification-configuration file:///dev/stdin
    
    log_success "S3 event notifications configured successfully"
}

# Function to create sample templates
create_sample_templates() {
    log_info "Creating sample templates and configuration files..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create sample templates"
        return 0
    fi
    
    # Create sample serverless template
    local sample_template=$(cat << 'EOF'
{
    "AWSTemplateFormatVersion": "2010-09-09",
    "Description": "Sample serverless web application generated with Amazon Q Developer assistance",
    "Metadata": {
        "StackName": "q-developer-serverless-app",
        "GeneratedBy": "Amazon Q Developer",
        "Architecture": "Serverless Web Application"
    },
    "Parameters": {
        "ApplicationName": {
            "Type": "String",
            "Default": "QDeveloperApp",
            "Description": "Name of the application"
        },
        "Environment": {
            "Type": "String",
            "Default": "dev",
            "AllowedValues": ["dev", "staging", "prod"],
            "Description": "Deployment environment"
        }
    },
    "Resources": {
        "S3Bucket": {
            "Type": "AWS::S3::Bucket",
            "Properties": {
                "BucketName": {
                    "Fn::Sub": "${ApplicationName}-${Environment}-static-content"
                },
                "PublicAccessBlockConfiguration": {
                    "BlockPublicAcls": true,
                    "BlockPublicPolicy": true,
                    "IgnorePublicAcls": true,
                    "RestrictPublicBuckets": true
                },
                "BucketEncryption": {
                    "ServerSideEncryptionConfiguration": [
                        {
                            "ServerSideEncryptionByDefault": {
                                "SSEAlgorithm": "AES256"
                            }
                        }
                    ]
                }
            }
        },
        "TestParameter": {
            "Type": "AWS::SSM::Parameter",
            "Properties": {
                "Name": "/test/q-developer-sample",
                "Type": "String",
                "Value": "Sample template deployed successfully"
            }
        }
    },
    "Outputs": {
        "S3BucketName": {
            "Description": "Name of the S3 bucket for static content",
            "Value": {
                "Ref": "S3Bucket"
            }
        }
    }
}
EOF
)
    
    # Upload sample template
    echo "${sample_template}" | aws s3 cp - "s3://${BUCKET_NAME}/templates/sample-serverless-app.json"
    
    # Create Infrastructure Composer project configuration
    local composer_config=$(cat << 'EOF'
{
    "version": "1.0",
    "projectName": "Q Developer Serverless Application",
    "description": "Sample project demonstrating Q Developer integration with Infrastructure Composer",
    "architecture": {
        "components": [
            {
                "type": "AWS::S3::Bucket",
                "name": "StaticContentBucket",
                "properties": {
                    "encryption": "enabled",
                    "versioning": "enabled",
                    "publicAccess": "blocked"
                }
            },
            {
                "type": "AWS::Lambda::Function",
                "name": "ApiFunction",
                "properties": {
                    "runtime": "python3.11",
                    "handler": "index.handler",
                    "timeout": 30
                }
            }
        ]
    }
}
EOF
)
    
    # Upload project configuration
    echo "${composer_config}" | aws s3 cp - "s3://${BUCKET_NAME}/projects/composer-project.json"
    
    log_success "Sample templates and configuration files created"
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" &>/dev/null; then
        log_success "✅ S3 bucket is accessible"
    else
        log_error "❌ S3 bucket is not accessible"
        return 1
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
        log_success "✅ Lambda function is deployed"
    else
        log_error "❌ Lambda function is not deployed"
        return 1
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        log_success "✅ IAM role is created"
    else
        log_error "❌ IAM role is not created"
        return 1
    fi
    
    # Wait for Lambda logs to be available
    log_info "Waiting for Lambda function to process sample template..."
    sleep 30
    
    # Check for validation results
    if aws s3 ls "s3://${BUCKET_NAME}/validation-results/" &>/dev/null; then
        log_success "✅ Template validation is working"
    else
        log_warning "⚠️ No validation results found yet (this is normal for new deployments)"
    fi
    
    log_success "Deployment verification completed"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo
    echo -e "${GREEN}Successfully deployed AI-Powered Infrastructure Code Generation pipeline!${NC}"
    echo
    echo "Resource Details:"
    echo "  S3 Bucket: ${BUCKET_NAME}"
    echo "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  IAM Role: ${IAM_ROLE_NAME}"
    echo "  AWS Region: ${AWS_REGION}"
    echo "  AWS Account: ${AWS_ACCOUNT_ID}"
    echo
    echo "Next Steps:"
    echo "  1. Install AWS Toolkit extension in VS Code"
    echo "  2. Configure Amazon Q Developer authentication"
    echo "  3. Upload CloudFormation templates to s3://${BUCKET_NAME}/templates/"
    echo "  4. Check validation results in s3://${BUCKET_NAME}/validation-results/"
    echo
    echo "For auto-deployment, upload templates to s3://${BUCKET_NAME}/auto-deploy/"
    echo
    echo "Monitor Lambda execution: aws logs tail /aws/lambda/${LAMBDA_FUNCTION_NAME} --follow"
    echo
}

# Function to handle cleanup on error
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup..."
    
    # Set environment variables if they weren't set
    export BUCKET_NAME="${BUCKET_NAME:-}"
    export LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:-}"
    export IAM_ROLE_NAME="${IAM_ROLE_NAME:-}"
    export CUSTOM_POLICY_NAME="${CUSTOM_POLICY_NAME:-}"
    
    # Call cleanup script
    if [[ -f "${SCRIPT_DIR}/destroy.sh" ]]; then
        bash "${SCRIPT_DIR}/destroy.sh" --auto-confirm
    fi
}

# Main execution function
main() {
    echo -e "${BLUE}Starting deployment of AI-Powered Infrastructure Code Generation pipeline...${NC}"
    echo "Log file: ${LOG_FILE}"
    echo
    
    # Set trap for cleanup on error
    trap cleanup_on_error ERR
    
    # Check if this is a dry run
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Running in DRY RUN mode - no resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    generate_resource_names
    create_s3_bucket
    create_iam_resources
    create_lambda_function
    configure_s3_events
    create_sample_templates
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        verify_deployment
        display_summary
    else
        log_info "DRY RUN completed successfully"
    fi
    
    log_success "Deployment completed successfully!"
}

# Script usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --dry-run           Run in dry-run mode (no resources created)"
    echo "  --help             Show this help message"
    echo
    echo "Environment Variables:"
    echo "  DRY_RUN=true       Enable dry-run mode"
    echo "  AWS_REGION         Override AWS region"
    echo
    echo "Examples:"
    echo "  $0                 Deploy infrastructure"
    echo "  $0 --dry-run       Preview deployment without creating resources"
    echo "  DRY_RUN=true $0    Same as --dry-run"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@"