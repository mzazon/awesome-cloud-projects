#!/bin/bash

# =============================================================================
# Custom CloudFormation Resources Lambda-Backed Deployment Script
# =============================================================================
# This script deploys the complete infrastructure for the custom CloudFormation
# resources recipe, including IAM roles, Lambda functions, and CloudFormation
# stacks with custom resources.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate AWS permissions for CloudFormation, Lambda, IAM, and S3
# - Python 3.9+ for Lambda function runtime
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly LOG_FILE="${PROJECT_ROOT}/deployment.log"
readonly STACK_PREFIX="custom-resource-demo"
readonly LAMBDA_RUNTIME="python3.9"
readonly LAMBDA_TIMEOUT=300
readonly LAMBDA_MEMORY=256

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
DEPLOYMENT_ID=""
AWS_REGION=""
AWS_ACCOUNT_ID=""
CLEANUP_ON_FAILURE=true
VERBOSE=false
DRY_RUN=false

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to file
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
    
    # Log to console with colors
    case "${level}" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}" >&2
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}" >&2
            ;;
        "DEBUG")
            if [[ "${VERBOSE}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} ${message}" >&2
            fi
            ;;
    esac
}

error_exit() {
    log "ERROR" "$1"
    if [[ "${CLEANUP_ON_FAILURE}" == "true" ]]; then
        log "INFO" "Cleaning up resources due to failure..."
        cleanup_resources
    fi
    exit 1
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | head -n1 | awk '{print $1}' | cut -d/ -f2)
    if [[ ! "${aws_version}" =~ ^2\. ]]; then
        error_exit "AWS CLI v2 is required. Current version: ${aws_version}"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set appropriate environment variables."
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        error_exit "Python 3 is not installed. Please install Python 3.9 or later."
    fi
    
    # Check zip utility
    if ! command -v zip &> /dev/null; then
        error_exit "zip utility is not installed. Please install zip."
    fi
    
    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install jq for JSON processing."
    fi
    
    log "INFO" "Prerequisites check passed"
}

initialize_deployment() {
    log "INFO" "Initializing deployment..."
    
    # Generate unique deployment ID
    DEPLOYMENT_ID=$(date +%s)
    
    # Get AWS account and region
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    if [[ -z "${AWS_REGION}" ]]; then
        AWS_REGION="us-east-1"
        log "WARN" "No default region configured, using us-east-1"
    fi
    
    # Create deployment directory
    mkdir -p "${PROJECT_ROOT}/deployment-${DEPLOYMENT_ID}"
    
    log "INFO" "Deployment ID: ${DEPLOYMENT_ID}"
    log "INFO" "AWS Account: ${AWS_ACCOUNT_ID}"
    log "INFO" "AWS Region: ${AWS_REGION}"
    
    # Set resource names
    export STACK_NAME="${STACK_PREFIX}-${DEPLOYMENT_ID}"
    export LAMBDA_FUNCTION_NAME="custom-resource-handler-${DEPLOYMENT_ID}"
    export ADVANCED_LAMBDA_NAME="advanced-custom-resource-${DEPLOYMENT_ID}"
    export IAM_ROLE_NAME="CustomResourceLambdaRole-${DEPLOYMENT_ID}"
    export S3_BUCKET_NAME="custom-resource-data-${AWS_ACCOUNT_ID}-${DEPLOYMENT_ID}"
    export PROD_STACK_NAME="production-custom-resource-${DEPLOYMENT_ID}"
    
    log "DEBUG" "Resource names initialized"
}

create_lambda_code() {
    log "INFO" "Creating Lambda function code..."
    
    local deployment_dir="${PROJECT_ROOT}/deployment-${DEPLOYMENT_ID}"
    
    # Create basic Lambda function code
    cat > "${deployment_dir}/lambda_function.py" << 'EOF'
import json
import boto3
import cfnresponse
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda function to handle custom resource operations
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Extract event properties
        request_type = event['RequestType']
        resource_properties = event.get('ResourceProperties', {})
        physical_resource_id = event.get('PhysicalResourceId', 'CustomResource')
        
        # Initialize response data
        response_data = {}
        
        if request_type == 'Create':
            logger.info("Processing CREATE request")
            response_data = handle_create(resource_properties, physical_resource_id)
            
        elif request_type == 'Update':
            logger.info("Processing UPDATE request")
            response_data = handle_update(resource_properties, physical_resource_id)
            
        elif request_type == 'Delete':
            logger.info("Processing DELETE request")
            response_data = handle_delete(resource_properties, physical_resource_id)
            
        else:
            logger.error(f"Unknown request type: {request_type}")
            cfnresponse.send(event, context, cfnresponse.FAILED, {}, physical_resource_id)
            return
        
        # Send success response
        cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data, physical_resource_id)
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {}, physical_resource_id)

def handle_create(properties, physical_resource_id):
    """
    Handle resource creation
    """
    try:
        # Get configuration from properties
        bucket_name = properties.get('BucketName')
        file_name = properties.get('FileName', 'custom-resource-data.json')
        data_content = properties.get('DataContent', {})
        
        # Create data object
        data_object = {
            'created_at': datetime.utcnow().isoformat(),
            'resource_id': physical_resource_id,
            'configuration': data_content,
            'operation': 'CREATE'
        }
        
        # Upload to S3
        s3.put_object(
            Bucket=bucket_name,
            Key=file_name,
            Body=json.dumps(data_object, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f"Created object {file_name} in bucket {bucket_name}")
        
        # Return response data
        return {
            'BucketName': bucket_name,
            'FileName': file_name,
            'DataUrl': f"https://{bucket_name}.s3.amazonaws.com/{file_name}",
            'CreatedAt': data_object['created_at']
        }
        
    except Exception as e:
        logger.error(f"Error in handle_create: {str(e)}")
        raise

def handle_update(properties, physical_resource_id):
    """
    Handle resource updates
    """
    try:
        # Get configuration from properties
        bucket_name = properties.get('BucketName')
        file_name = properties.get('FileName', 'custom-resource-data.json')
        data_content = properties.get('DataContent', {})
        
        # Try to get existing object
        try:
            response = s3.get_object(Bucket=bucket_name, Key=file_name)
            existing_data = json.loads(response['Body'].read())
        except s3.exceptions.NoSuchKey:
            existing_data = {}
        
        # Update data object
        data_object = {
            'created_at': existing_data.get('created_at', datetime.utcnow().isoformat()),
            'updated_at': datetime.utcnow().isoformat(),
            'resource_id': physical_resource_id,
            'configuration': data_content,
            'operation': 'UPDATE'
        }
        
        # Upload updated object to S3
        s3.put_object(
            Bucket=bucket_name,
            Key=file_name,
            Body=json.dumps(data_object, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f"Updated object {file_name} in bucket {bucket_name}")
        
        # Return response data
        return {
            'BucketName': bucket_name,
            'FileName': file_name,
            'DataUrl': f"https://{bucket_name}.s3.amazonaws.com/{file_name}",
            'UpdatedAt': data_object['updated_at']
        }
        
    except Exception as e:
        logger.error(f"Error in handle_update: {str(e)}")
        raise

def handle_delete(properties, physical_resource_id):
    """
    Handle resource deletion
    """
    try:
        # Get configuration from properties
        bucket_name = properties.get('BucketName')
        file_name = properties.get('FileName', 'custom-resource-data.json')
        
        # Delete object from S3
        try:
            s3.delete_object(Bucket=bucket_name, Key=file_name)
            logger.info(f"Deleted object {file_name} from bucket {bucket_name}")
        except Exception as e:
            logger.warning(f"Could not delete object: {str(e)}")
        
        # Return response data
        return {
            'BucketName': bucket_name,
            'FileName': file_name,
            'DeletedAt': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error in handle_delete: {str(e)}")
        raise
EOF
    
    # Create deployment package
    cd "${deployment_dir}"
    zip -q lambda-function.zip lambda_function.py
    
    log "INFO" "Lambda function code created and packaged"
}

create_iam_role() {
    log "INFO" "Creating IAM role for Lambda function..."
    
    local deployment_dir="${PROJECT_ROOT}/deployment-${DEPLOYMENT_ID}"
    
    # Create trust policy
    cat > "${deployment_dir}/trust-policy.json" << EOF
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
    if [[ "${DRY_RUN}" == "false" ]]; then
        aws iam create-role \
            --role-name "${IAM_ROLE_NAME}" \
            --assume-role-policy-document file://"${deployment_dir}/trust-policy.json" \
            --tags Key=Project,Value=CustomResourceDemo Key=DeploymentId,Value="${DEPLOYMENT_ID}" \
            >> "${LOG_FILE}" 2>&1
        
        # Attach basic Lambda execution policy
        aws iam attach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        # Create custom policy for S3 access
        cat > "${deployment_dir}/s3-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
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
        
        # Create and attach S3 policy
        aws iam create-policy \
            --policy-name "CustomResourceS3Policy-${DEPLOYMENT_ID}" \
            --policy-document file://"${deployment_dir}/s3-policy.json" \
            >> "${LOG_FILE}" 2>&1
        
        aws iam attach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CustomResourceS3Policy-${DEPLOYMENT_ID}"
        
        # Wait for role to be available
        sleep 10
        
        # Get role ARN
        export ROLE_ARN=$(aws iam get-role \
            --role-name "${IAM_ROLE_NAME}" \
            --query Role.Arn --output text)
        
        log "INFO" "IAM role created: ${ROLE_ARN}"
    else
        log "INFO" "DRY RUN: Would create IAM role ${IAM_ROLE_NAME}"
    fi
}

create_s3_bucket() {
    log "INFO" "Creating S3 bucket for demonstration data..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create bucket with region-specific configuration
        if [[ "${AWS_REGION}" == "us-east-1" ]]; then
            aws s3 mb "s3://${S3_BUCKET_NAME}" >> "${LOG_FILE}" 2>&1
        else
            aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1
        fi
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "${S3_BUCKET_NAME}" \
            --versioning-configuration Status=Enabled
        
        # Add tags
        aws s3api put-bucket-tagging \
            --bucket "${S3_BUCKET_NAME}" \
            --tagging 'TagSet=[{Key=Project,Value=CustomResourceDemo},{Key=DeploymentId,Value='${DEPLOYMENT_ID}'}]'
        
        log "INFO" "S3 bucket created: ${S3_BUCKET_NAME}"
    else
        log "INFO" "DRY RUN: Would create S3 bucket ${S3_BUCKET_NAME}"
    fi
}

create_lambda_function() {
    log "INFO" "Creating Lambda function..."
    
    local deployment_dir="${PROJECT_ROOT}/deployment-${DEPLOYMENT_ID}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create Lambda function
        aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime "${LAMBDA_RUNTIME}" \
            --role "${ROLE_ARN}" \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://"${deployment_dir}/lambda-function.zip" \
            --timeout "${LAMBDA_TIMEOUT}" \
            --memory-size "${LAMBDA_MEMORY}" \
            --description "Custom resource handler for CloudFormation - Deployment ${DEPLOYMENT_ID}" \
            --tags Project=CustomResourceDemo,DeploymentId="${DEPLOYMENT_ID}" \
            >> "${LOG_FILE}" 2>&1
        
        # Get Lambda function ARN
        export LAMBDA_ARN=$(aws lambda get-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --query Configuration.FunctionArn --output text)
        
        log "INFO" "Lambda function created: ${LAMBDA_ARN}"
    else
        log "INFO" "DRY RUN: Would create Lambda function ${LAMBDA_FUNCTION_NAME}"
    fi
}

create_cloudformation_template() {
    log "INFO" "Creating CloudFormation template..."
    
    local deployment_dir="${PROJECT_ROOT}/deployment-${DEPLOYMENT_ID}"
    
    cat > "${deployment_dir}/custom-resource-template.yaml" << EOF
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Demo stack with Lambda-backed custom resource - Deployment ${DEPLOYMENT_ID}'

Parameters:
  LambdaFunctionArn:
    Type: String
    Description: ARN of the Lambda function for custom resource
  S3BucketName:
    Type: String
    Description: S3 bucket name for data storage
  DataFileName:
    Type: String
    Default: 'demo-data.json'
    Description: Name of the data file to create
  CustomDataContent:
    Type: String
    Default: '{"environment": "demo", "version": "1.0"}'
    Description: JSON content for the custom data

Resources:
  # Custom Resource that uses Lambda function
  CustomDataResource:
    Type: AWS::CloudFormation::CustomResource
    Properties:
      ServiceToken: !Ref LambdaFunctionArn
      BucketName: !Ref S3BucketName
      FileName: !Ref DataFileName
      DataContent: !Ref CustomDataContent
      Version: '1.0'  # Change this to trigger updates

  # Standard S3 bucket for comparison
  DemoS3Bucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub '\${S3BucketName}-standard'
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      VersioningConfiguration:
        Status: Enabled
      Tags:
        - Key: Project
          Value: CustomResourceDemo
        - Key: DeploymentId
          Value: '${DEPLOYMENT_ID}'

  # CloudWatch Log Group for monitoring
  CustomResourceLogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      LogGroupName: !Sub '/aws/lambda/\${LambdaFunctionArn}'
      RetentionInDays: 7

Outputs:
  CustomResourceDataUrl:
    Description: URL of the data file created by custom resource
    Value: !GetAtt CustomDataResource.DataUrl
    Export:
      Name: !Sub '\${AWS::StackName}-DataUrl'
  
  CustomResourceFileName:
    Description: Name of the file created by custom resource
    Value: !GetAtt CustomDataResource.FileName
    Export:
      Name: !Sub '\${AWS::StackName}-FileName'
  
  CustomResourceBucketName:
    Description: Bucket name used by custom resource
    Value: !GetAtt CustomDataResource.BucketName
    Export:
      Name: !Sub '\${AWS::StackName}-BucketName'
  
  CreatedAt:
    Description: Timestamp when resource was created
    Value: !GetAtt CustomDataResource.CreatedAt
    Export:
      Name: !Sub '\${AWS::StackName}-CreatedAt'
EOF
    
    log "INFO" "CloudFormation template created"
}

deploy_cloudformation_stack() {
    log "INFO" "Deploying CloudFormation stack..."
    
    local deployment_dir="${PROJECT_ROOT}/deployment-${DEPLOYMENT_ID}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create CloudFormation stack
        aws cloudformation create-stack \
            --stack-name "${STACK_NAME}" \
            --template-body file://"${deployment_dir}/custom-resource-template.yaml" \
            --parameters ParameterKey=LambdaFunctionArn,ParameterValue="${LAMBDA_ARN}" \
                        ParameterKey=S3BucketName,ParameterValue="${S3_BUCKET_NAME}" \
                        ParameterKey=DataFileName,ParameterValue=demo-data.json \
                        ParameterKey=CustomDataContent,ParameterValue='{"environment":"production","version":"1.0","features":["logging","monitoring"]}' \
            --capabilities CAPABILITY_IAM \
            --tags Key=Project,Value=CustomResourceDemo Key=DeploymentId,Value="${DEPLOYMENT_ID}" \
            >> "${LOG_FILE}" 2>&1
        
        # Wait for stack creation to complete
        log "INFO" "Waiting for stack creation to complete..."
        aws cloudformation wait stack-create-complete --stack-name "${STACK_NAME}"
        
        # Check stack status
        local stack_status=$(aws cloudformation describe-stacks \
            --stack-name "${STACK_NAME}" \
            --query 'Stacks[0].StackStatus' --output text)
        
        if [[ "${stack_status}" == "CREATE_COMPLETE" ]]; then
            log "INFO" "Stack created successfully: ${stack_status}"
        else
            error_exit "Stack creation failed: ${stack_status}"
        fi
    else
        log "INFO" "DRY RUN: Would deploy CloudFormation stack ${STACK_NAME}"
    fi
}

test_deployment() {
    log "INFO" "Testing deployment..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Get stack outputs
        log "INFO" "Stack outputs:"
        aws cloudformation describe-stacks \
            --stack-name "${STACK_NAME}" \
            --query 'Stacks[0].Outputs[*].{Key:OutputKey,Value:OutputValue}' \
            --output table
        
        # Verify S3 object was created
        log "INFO" "Checking S3 objects created by custom resource:"
        aws s3 ls "s3://${S3_BUCKET_NAME}/" --recursive
        
        # Test Lambda function directly
        log "INFO" "Testing Lambda function invocation..."
        local test_payload='{"RequestType":"Create","ResponseURL":"https://example.com/test","StackId":"test","RequestId":"test","ResourceType":"Custom::TestResource","LogicalResourceId":"TestResource","ResourceProperties":{"BucketName":"'${S3_BUCKET_NAME}'","FileName":"test-direct.json","DataContent":"{\"test\":\"direct-invocation\"}"}}'
        
        aws lambda invoke \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --payload "${test_payload}" \
            --cli-binary-format raw-in-base64-out \
            "${PROJECT_ROOT}/deployment-${DEPLOYMENT_ID}/test-response.json" \
            >> "${LOG_FILE}" 2>&1
        
        log "INFO" "Lambda function test response:"
        cat "${PROJECT_ROOT}/deployment-${DEPLOYMENT_ID}/test-response.json"
        
        log "INFO" "Deployment test completed successfully"
    else
        log "INFO" "DRY RUN: Would test deployment"
    fi
}

save_deployment_info() {
    log "INFO" "Saving deployment information..."
    
    local deployment_dir="${PROJECT_ROOT}/deployment-${DEPLOYMENT_ID}"
    
    cat > "${deployment_dir}/deployment-info.json" << EOF
{
  "deployment_id": "${DEPLOYMENT_ID}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "aws_region": "${AWS_REGION}",
  "aws_account_id": "${AWS_ACCOUNT_ID}",
  "resources": {
    "stack_name": "${STACK_NAME}",
    "lambda_function_name": "${LAMBDA_FUNCTION_NAME}",
    "iam_role_name": "${IAM_ROLE_NAME}",
    "s3_bucket_name": "${S3_BUCKET_NAME}",
    "lambda_arn": "${LAMBDA_ARN:-}",
    "role_arn": "${ROLE_ARN:-}"
  },
  "status": "deployed"
}
EOF
    
    log "INFO" "Deployment information saved to ${deployment_dir}/deployment-info.json"
}

cleanup_resources() {
    log "INFO" "Cleaning up resources..."
    
    # This function is called on failure - implement basic cleanup
    if [[ -n "${STACK_NAME:-}" ]]; then
        aws cloudformation delete-stack --stack-name "${STACK_NAME}" 2>/dev/null || true
    fi
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}" 2>/dev/null || true
    fi
    
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        aws iam detach-role-policy --role-name "${IAM_ROLE_NAME}" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        aws iam detach-role-policy --role-name "${IAM_ROLE_NAME}" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CustomResourceS3Policy-${DEPLOYMENT_ID}" 2>/dev/null || true
        aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CustomResourceS3Policy-${DEPLOYMENT_ID}" 2>/dev/null || true
        aws iam delete-role --role-name "${IAM_ROLE_NAME}" 2>/dev/null || true
    fi
    
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive 2>/dev/null || true
        aws s3 rb "s3://${S3_BUCKET_NAME}" 2>/dev/null || true
    fi
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Custom CloudFormation Resources with Lambda-backed Custom Resources

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose logging
    -d, --dry-run           Show what would be done without actually doing it
    -n, --no-cleanup        Don't cleanup resources on failure
    -r, --region REGION     AWS region (default: from AWS config)

Examples:
    $0                      Deploy with default settings
    $0 --verbose            Deploy with verbose logging
    $0 --dry-run            Show what would be deployed
    $0 --region us-west-2   Deploy to specific region

EOF
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -n|--no-cleanup)
                CLEANUP_ON_FAILURE=false
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
    
    # Initialize log file
    echo "=== Custom CloudFormation Resources Deployment Started ===" > "${LOG_FILE}"
    
    log "INFO" "Starting deployment of Custom CloudFormation Resources"
    log "INFO" "Deployment script version: 1.0"
    log "INFO" "Dry run mode: ${DRY_RUN}"
    log "INFO" "Verbose mode: ${VERBOSE}"
    
    # Execute deployment steps
    check_prerequisites
    initialize_deployment
    create_lambda_code
    create_s3_bucket
    create_iam_role
    create_lambda_function
    create_cloudformation_template
    deploy_cloudformation_stack
    test_deployment
    save_deployment_info
    
    log "INFO" "Deployment completed successfully!"
    log "INFO" "Deployment ID: ${DEPLOYMENT_ID}"
    log "INFO" "Stack Name: ${STACK_NAME}"
    log "INFO" "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log "INFO" "S3 Bucket: ${S3_BUCKET_NAME}"
    log "INFO" "Log file: ${LOG_FILE}"
    
    echo
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
    echo -e "${BLUE}Deployment ID:${NC} ${DEPLOYMENT_ID}"
    echo -e "${BLUE}Stack Name:${NC} ${STACK_NAME}"
    echo -e "${BLUE}Region:${NC} ${AWS_REGION}"
    echo -e "${BLUE}Log file:${NC} ${LOG_FILE}"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Review the CloudFormation stack in the AWS Console"
    echo "2. Check the S3 bucket for custom resource data"
    echo "3. View Lambda function logs in CloudWatch"
    echo "4. Use the destroy script to clean up resources when done"
    echo
}

# Execute main function
main "$@"