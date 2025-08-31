#!/bin/bash

# deploy.sh - Deploy AWS Resource Cleanup Automation with Lambda and Tags
# This script creates the complete infrastructure for automated resource cleanup

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TEMP_DIR=$(mktemp -d)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" | tee -a "$LOG_FILE"
    cleanup_temp_files
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

# Info message function
info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "$LOG_FILE"
}

# Cleanup temporary files
cleanup_temp_files() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Trap for cleanup on script exit
trap cleanup_temp_files EXIT

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI version 2.0 or later."
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version=$(echo "$aws_version" | cut -d. -f1)
    if [[ "$major_version" -lt 2 ]]; then
        error_exit "AWS CLI version 2.0 or later is required. Current version: $aws_version"
    fi
    
    # Check if jq is installed for JSON processing
    if ! command -v jq &> /dev/null; then
        error_exit "jq is required for JSON processing. Please install jq."
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        error_exit "zip command is required. Please install zip utility."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials are not configured or invalid. Please run 'aws configure' or set appropriate environment variables."
    fi
    
    # Check required permissions (basic check)
    local caller_identity=$(aws sts get-caller-identity)
    local account_id=$(echo "$caller_identity" | jq -r '.Account')
    if [[ -z "$account_id" || "$account_id" == "null" ]]; then
        error_exit "Unable to determine AWS account ID. Please check your credentials."
    fi
    
    success "Prerequisites check completed"
}

# Initialize environment variables
initialize_environment() {
    info "Initializing environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export FUNCTION_NAME="resource-cleanup-${random_suffix}"
    export ROLE_NAME="resource-cleanup-role-${random_suffix}"
    export SNS_TOPIC_NAME="resource-cleanup-alerts-${random_suffix}"
    export TEST_INSTANCE_NAME="test-cleanup-instance-${random_suffix}"
    
    # Get latest Amazon Linux 2023 AMI ID
    export LATEST_AMI_ID=$(aws ssm get-parameter \
        --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
        --query 'Parameter.Value' --output text 2>/dev/null || echo "ami-0abcdef1234567890")
    
    # Save environment variables to file for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
FUNCTION_NAME=${FUNCTION_NAME}
ROLE_NAME=${ROLE_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
TEST_INSTANCE_NAME=${TEST_INSTANCE_NAME}
LATEST_AMI_ID=${LATEST_AMI_ID}
EOF
    
    success "Environment variables configured"
    info "Function Name: ${FUNCTION_NAME}"
    info "SNS Topic: ${SNS_TOPIC_NAME}"
    info "Latest AMI ID: ${LATEST_AMI_ID}"
}

# Create SNS topic and subscription
create_sns_topic() {
    info "Creating SNS topic for cleanup notifications..."
    
    # Create SNS topic
    aws sns create-topic --name "${SNS_TOPIC_NAME}" --region "${AWS_REGION}" || error_exit "Failed to create SNS topic"
    
    # Get topic ARN
    export SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
        --query 'Attributes.TopicArn' --output text)
    
    # Add SNS_TOPIC_ARN to environment file
    echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> "${SCRIPT_DIR}/.env"
    
    success "SNS topic created: ${SNS_TOPIC_ARN}"
    
    # Prompt for email subscription
    if [[ -z "${EMAIL_ADDRESS:-}" ]]; then
        echo -n "Enter your email address for cleanup notifications (press Enter to skip): "
        read -r EMAIL_ADDRESS
    fi
    
    if [[ -n "${EMAIL_ADDRESS:-}" ]]; then
        aws sns subscribe \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --protocol email \
            --notification-endpoint "${EMAIL_ADDRESS}" \
            --region "${AWS_REGION}" || warning "Failed to create email subscription"
        
        echo "EMAIL_ADDRESS=${EMAIL_ADDRESS}" >> "${SCRIPT_DIR}/.env"
        success "Email subscription created - check your inbox to confirm"
    else
        warning "Email subscription skipped"
    fi
}

# Create IAM role for Lambda
create_iam_role() {
    info "Creating IAM role for Lambda function..."
    
    # Create trust policy file
    cat > "${TEMP_DIR}/trust-policy.json" << 'EOF'
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
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document "file://${TEMP_DIR}/trust-policy.json" \
        --description "Role for automated resource cleanup Lambda function" || error_exit "Failed to create IAM role"
    
    success "IAM role created: ${ROLE_NAME}"
    
    # Wait for role to be available
    info "Waiting for IAM role to be available..."
    aws iam wait role-exists --role-name "${ROLE_NAME}" || error_exit "IAM role creation failed"
    
    # Get role ARN
    export ROLE_ARN=$(aws iam get-role \
        --role-name "${ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    
    echo "ROLE_ARN=${ROLE_ARN}" >> "${SCRIPT_DIR}/.env"
    success "IAM role ARN: ${ROLE_ARN}"
}

# Attach permissions to Lambda role
attach_iam_permissions() {
    info "Attaching permissions to Lambda role..."
    
    # Create custom policy for resource cleanup permissions
    cat > "${TEMP_DIR}/cleanup-policy.json" << EOF
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
                "ec2:DescribeInstances",
                "ec2:TerminateInstances",
                "ec2:DescribeTags"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "${SNS_TOPIC_ARN}"
        }
    ]
}
EOF
    
    # Create and attach policy
    aws iam put-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-name ResourceCleanupPolicy \
        --policy-document "file://${TEMP_DIR}/cleanup-policy.json" || error_exit "Failed to attach IAM policy"
    
    # Wait for policy to be attached
    sleep 10
    
    success "Permissions attached to role"
}

# Create Lambda function code and package
create_lambda_function() {
    info "Creating Lambda function code..."
    
    # Create Lambda function code
    cat > "${TEMP_DIR}/cleanup_function.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime, timezone

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    sns = boto3.client('sns')
    
    # Get environment variables
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    try:
        # Query instances with cleanup tag
        response = ec2.describe_instances(
            Filters=[
                {
                    'Name': 'tag:AutoCleanup',
                    'Values': ['true', 'True', 'TRUE']
                },
                {
                    'Name': 'instance-state-name',
                    'Values': ['running', 'stopped']
                }
            ]
        )
        
        instances_to_cleanup = []
        
        # Extract instance information
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                instance_name = 'Unnamed'
                instance_type = instance.get('InstanceType', 'Unknown')
                
                # Get instance name from tags
                for tag in instance.get('Tags', []):
                    if tag['Key'] == 'Name':
                        instance_name = tag['Value']
                        break
                
                instances_to_cleanup.append({
                    'InstanceId': instance_id,
                    'Name': instance_name,
                    'State': instance['State']['Name'],
                    'Type': instance_type
                })
        
        if not instances_to_cleanup:
            print("No instances found with AutoCleanup tag")
            return {
                'statusCode': 200,
                'body': json.dumps('No instances to cleanup')
            }
        
        # Terminate instances
        instance_ids = [inst['InstanceId'] for inst in instances_to_cleanup]
        ec2.terminate_instances(InstanceIds=instance_ids)
        
        # Send SNS notification
        message = f"""
AWS Resource Cleanup Report
Time: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC
Region: {os.environ.get('AWS_REGION', 'Unknown')}

The following EC2 instances were terminated:

"""
        
        for instance in instances_to_cleanup:
            message += f"- {instance['Name']} ({instance['InstanceId']}) - Type: {instance['Type']}, State: {instance['State']}\n"
        
        message += f"\nTotal instances cleaned up: {len(instances_to_cleanup)}"
        message += f"\nEstimated monthly savings: Varies by instance type and usage"
        
        # Publish to SNS
        sns.publish(
            TopicArn=sns_topic_arn,
            Subject='AWS Resource Cleanup Completed',
            Message=message
        )
        
        print(f"Successfully terminated {len(instances_to_cleanup)} instances")
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Cleaned up {len(instances_to_cleanup)} instances')
        }
        
    except Exception as e:
        error_message = f"Error during cleanup: {str(e)}"
        print(error_message)
        
        # Send error notification
        try:
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject='AWS Resource Cleanup Error',
                Message=f"Error occurred during resource cleanup:\n\n{error_message}"
            )
        except Exception as sns_error:
            print(f"Failed to send error notification: {sns_error}")
        
        return {
            'statusCode': 500,
            'body': json.dumps(error_message)
        }
EOF
    
    # Create deployment package
    cd "${TEMP_DIR}"
    zip -q function.zip cleanup_function.py || error_exit "Failed to create deployment package"
    cd - > /dev/null
    
    success "Lambda function code created and packaged"
}

# Deploy Lambda function
deploy_lambda_function() {
    info "Deploying Lambda function..."
    
    # Create Lambda function with latest Python runtime
    aws lambda create-function \
        --function-name "${FUNCTION_NAME}" \
        --runtime python3.12 \
        --role "${ROLE_ARN}" \
        --handler cleanup_function.lambda_handler \
        --zip-file "fileb://${TEMP_DIR}/function.zip" \
        --timeout 300 \
        --memory-size 256 \
        --environment "Variables={SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}" \
        --description "Automated cleanup of tagged EC2 instances" \
        --region "${AWS_REGION}" || error_exit "Failed to deploy Lambda function"
    
    success "Lambda function deployed: ${FUNCTION_NAME}"
}

# Create test instance (optional)
create_test_instance() {
    if [[ "${SKIP_TEST_INSTANCE:-false}" == "true" ]]; then
        warning "Skipping test instance creation"
        return
    fi
    
    echo -n "Create a test EC2 instance for validation? (y/n): "
    read -r create_test
    
    if [[ "$create_test" =~ ^[Yy]$ ]]; then
        info "Creating test EC2 instance with cleanup tag..."
        
        # Launch test instance with cleanup tag
        local instance_id=$(aws ec2 run-instances \
            --image-id "${LATEST_AMI_ID}" \
            --instance-type t2.micro \
            --tag-specifications \
            "ResourceType=instance,Tags=[{Key=Name,Value=${TEST_INSTANCE_NAME}},{Key=AutoCleanup,Value=true},{Key=Environment,Value=test},{Key=Purpose,Value=cleanup-testing}]" \
            --region "${AWS_REGION}" \
            --query 'Instances[0].InstanceId' \
            --output text) || error_exit "Failed to create test instance"
        
        export TEST_INSTANCE_ID="${instance_id}"
        echo "TEST_INSTANCE_ID=${TEST_INSTANCE_ID}" >> "${SCRIPT_DIR}/.env"
        
        # Wait for instance to be in running state
        info "Waiting for test instance to be running..."
        aws ec2 wait instance-running --instance-ids "${TEST_INSTANCE_ID}" --region "${AWS_REGION}" || warning "Test instance may not be fully ready"
        
        success "Test instance created: ${TEST_INSTANCE_ID}"
        warning "Test instance will be terminated when cleanup function runs"
    else
        info "Skipping test instance creation"
    fi
}

# Test Lambda function
test_lambda_function() {
    if [[ "${SKIP_LAMBDA_TEST:-false}" == "true" ]]; then
        warning "Skipping Lambda function test"
        return
    fi
    
    echo -n "Test the Lambda function now? (y/n): "
    read -r test_function
    
    if [[ "$test_function" =~ ^[Yy]$ ]]; then
        info "Testing Lambda function..."
        
        # Invoke Lambda function to test cleanup
        aws lambda invoke \
            --function-name "${FUNCTION_NAME}" \
            --payload '{}' \
            --region "${AWS_REGION}" \
            "${TEMP_DIR}/response.json" || error_exit "Failed to invoke Lambda function"
        
        # Display function response
        info "Lambda function response:"
        cat "${TEMP_DIR}/response.json"
        echo ""
        
        success "Lambda function tested successfully"
    else
        info "Skipping Lambda function test"
    fi
}

# Display deployment summary
display_summary() {
    info "Deployment completed successfully!"
    echo ""
    echo "=== Deployment Summary ==="
    echo "AWS Region: ${AWS_REGION}"
    echo "Lambda Function: ${FUNCTION_NAME}"
    echo "IAM Role: ${ROLE_NAME}"
    echo "SNS Topic: ${SNS_TOPIC_NAME}"
    echo "SNS Topic ARN: ${SNS_TOPIC_ARN}"
    if [[ -n "${EMAIL_ADDRESS:-}" ]]; then
        echo "Email Subscription: ${EMAIL_ADDRESS} (confirm via email)"
    fi
    if [[ -n "${TEST_INSTANCE_ID:-}" ]]; then
        echo "Test Instance: ${TEST_INSTANCE_ID}"
    fi
    echo ""
    echo "=== Next Steps ==="
    echo "1. Confirm email subscription if you provided an email address"
    echo "2. Tag EC2 instances with 'AutoCleanup=true' to enable automatic cleanup"
    echo "3. Schedule the Lambda function with CloudWatch Events for regular execution"
    echo "4. Monitor CloudWatch Logs for function execution details"
    echo ""
    echo "=== Important Notes ==="
    echo "- Only instances tagged with 'AutoCleanup=true' will be terminated"
    echo "- The function logs all actions to CloudWatch Logs"
    echo "- Run './destroy.sh' to remove all created resources"
    echo ""
    success "Resource cleanup automation is now ready!"
}

# Main execution
main() {
    echo "=== AWS Resource Cleanup Automation Deployment ==="
    echo "This script will deploy the complete infrastructure for automated resource cleanup"
    echo ""
    
    log "Starting deployment process..."
    
    check_prerequisites
    initialize_environment
    create_sns_topic
    create_iam_role
    attach_iam_permissions
    create_lambda_function
    deploy_lambda_function
    create_test_instance
    test_lambda_function
    display_summary
    
    log "Deployment process completed successfully"
}

# Run main function
main "$@"