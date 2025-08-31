#!/bin/bash

# Deploy Script for Simple Log Retention Management with CloudWatch and Lambda
# This script automates the deployment of the log retention management solution

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TEMP_DIR="${SCRIPT_DIR}/temp"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message"
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        BLUE)
            echo -e "${BLUE}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
    esac
}

# Cleanup function for script termination
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log ERROR "Deployment failed with exit code $exit_code"
        log INFO "Check the log file at $LOG_FILE for details"
        log INFO "Run ./destroy.sh to clean up any partially created resources"
    fi
    
    # Clean up temporary files
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    
    exit $exit_code
}

# Set up trap for cleanup
trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log ERROR "AWS CLI is not installed. Please install AWS CLI version 2.0 or later."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log INFO "AWS CLI version: $aws_version"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log ERROR "AWS credentials are not configured. Please run 'aws configure' or set up credentials."
        exit 1
    fi
    
    # Check if Python 3 is available for JSON processing
    if ! command -v python3 &> /dev/null; then
        log ERROR "Python 3 is required for JSON processing. Please install Python 3."
        exit 1
    fi
    
    # Check required AWS permissions
    log INFO "Checking AWS permissions..."
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    
    if [ -z "$region" ]; then
        log ERROR "AWS region is not configured. Please set a default region."
        exit 1
    fi
    
    log INFO "AWS Account ID: $account_id"
    log INFO "AWS Region: $region"
    
    # Test basic permissions
    if ! aws iam list-roles --max-items 1 &> /dev/null; then
        log WARN "Limited IAM permissions detected. Some operations may fail."
    fi
    
    log INFO "Prerequisites check completed ✅"
}

# Initialize environment
initialize_environment() {
    log INFO "Initializing environment..."
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    export FUNCTION_NAME="log-retention-manager-${RANDOM_SUFFIX}"
    export ROLE_NAME="LogRetentionManagerRole-${RANDOM_SUFFIX}"
    export TEST_LOG_GROUP="/aws/test-logs-${RANDOM_SUFFIX}"
    export RULE_NAME="log-retention-schedule-${RANDOM_SUFFIX}"
    
    # Save environment variables for destroy script
    cat > "${SCRIPT_DIR}/.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
FUNCTION_NAME=${FUNCTION_NAME}
ROLE_NAME=${ROLE_NAME}
TEST_LOG_GROUP=${TEST_LOG_GROUP}
RULE_NAME=${RULE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log INFO "Environment initialized with unique suffix: $RANDOM_SUFFIX"
    log INFO "Function name: $FUNCTION_NAME"
    log INFO "IAM role name: $ROLE_NAME"
}

# Create IAM role and policies
create_iam_role() {
    log INFO "Creating IAM role for Lambda function..."
    
    # Create trust policy for Lambda service
    cat > "${TEMP_DIR}/trust-policy.json" << EOF
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
    if aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
        log WARN "IAM role ${ROLE_NAME} already exists, skipping creation"
    else
        # Create IAM role
        aws iam create-role \
            --role-name "${ROLE_NAME}" \
            --assume-role-policy-document "file://${TEMP_DIR}/trust-policy.json" \
            --description "Role for Log Retention Manager Lambda function" \
            --tags Key=Project,Value=LogRetentionManager Key=ManagedBy,Value=DeployScript
        
        log INFO "IAM role created: ${ROLE_NAME}"
    fi
    
    # Create custom policy for CloudWatch Logs management
    cat > "${TEMP_DIR}/logs-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/lambda/*"
    }
  ]
}
EOF
    
    # Attach custom policy to role
    aws iam put-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-name LogRetentionPolicy \
        --policy-document "file://${TEMP_DIR}/logs-policy.json"
    
    log INFO "IAM role configured with CloudWatch Logs permissions ✅"
}

# Create Lambda function
create_lambda_function() {
    log INFO "Creating Lambda function..."
    
    # Create Lambda function code
    cat > "${TEMP_DIR}/lambda_function.py" << 'EOF'
import json
import boto3
import logging
import os
from botocore.exceptions import ClientError

# Initialize CloudWatch Logs client
logs_client = boto3.client('logs')

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def apply_retention_policy(log_group_name, retention_days):
    """Apply retention policy to a specific log group"""
    try:
        logs_client.put_retention_policy(
            logGroupName=log_group_name,
            retentionInDays=retention_days
        )
        logger.info(f"Applied {retention_days} day retention to {log_group_name}")
        return True
    except ClientError as e:
        logger.error(f"Failed to set retention for {log_group_name}: {e}")
        return False

def get_retention_days(log_group_name):
    """Determine appropriate retention period based on log group name patterns"""
    # Define retention rules based on log group naming patterns
    retention_rules = {
        '/aws/lambda/': 30,       # Lambda logs: 30 days
        '/aws/apigateway/': 90,   # API Gateway logs: 90 days  
        '/aws/codebuild/': 14,    # CodeBuild logs: 14 days
        '/aws/ecs/': 60,          # ECS logs: 60 days
        '/aws/stepfunctions/': 90, # Step Functions: 90 days
        '/application/': 180,     # Application logs: 180 days
        '/system/': 365,          # System logs: 1 year
    }
    
    # Check log group name against patterns
    for pattern, days in retention_rules.items():
        if pattern in log_group_name:
            return days
    
    # Default retention for unmatched patterns
    return int(os.environ.get('DEFAULT_RETENTION_DAYS', '30'))

def lambda_handler(event, context):
    """Main Lambda handler for log retention management"""
    try:
        processed_groups = 0
        updated_groups = 0
        errors = []
        
        # Get all log groups (paginated)
        paginator = logs_client.get_paginator('describe_log_groups')
        
        for page in paginator.paginate():
            for log_group in page['logGroups']:
                log_group_name = log_group['logGroupName']
                current_retention = log_group.get('retentionInDays')
                
                # Determine appropriate retention period
                target_retention = get_retention_days(log_group_name)
                
                processed_groups += 1
                
                # Apply retention policy if needed
                if current_retention != target_retention:
                    if apply_retention_policy(log_group_name, target_retention):
                        updated_groups += 1
                    else:
                        errors.append(log_group_name)
                else:
                    logger.info(f"Log group {log_group_name} already has correct retention: {current_retention} days")
        
        # Return summary
        result = {
            'statusCode': 200,
            'message': f'Processed {processed_groups} log groups, updated {updated_groups} retention policies',
            'processedGroups': processed_groups,
            'updatedGroups': updated_groups,
            'errors': errors
        }
        
        logger.info(json.dumps(result))
        return result
        
    except Exception as e:
        logger.error(f"Error in log retention management: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }
EOF
    
    # Create deployment package
    cd "$TEMP_DIR"
    zip lambda-function.zip lambda_function.py
    cd - > /dev/null
    
    # Wait for IAM role to be available
    log INFO "Waiting for IAM role to be available..."
    sleep 10
    
    # Get IAM role ARN
    ROLE_ARN=$(aws iam get-role \
        --role-name "${ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    
    # Check if Lambda function already exists
    if aws lambda get-function --function-name "${FUNCTION_NAME}" &> /dev/null; then
        log WARN "Lambda function ${FUNCTION_NAME} already exists, updating code..."
        aws lambda update-function-code \
            --function-name "${FUNCTION_NAME}" \
            --zip-file "fileb://${TEMP_DIR}/lambda-function.zip"
    else
        # Create Lambda function
        aws lambda create-function \
            --function-name "${FUNCTION_NAME}" \
            --runtime python3.12 \
            --role "${ROLE_ARN}" \
            --handler lambda_function.lambda_handler \
            --zip-file "fileb://${TEMP_DIR}/lambda-function.zip" \
            --timeout 300 \
            --memory-size 256 \
            --environment Variables="{DEFAULT_RETENTION_DAYS=30}" \
            --description "Automated CloudWatch Logs retention management" \
            --tags Project=LogRetentionManager,ManagedBy=DeployScript
        
        log INFO "Lambda function created: ${FUNCTION_NAME}"
    fi
    
    log INFO "Lambda function deployed successfully ✅"
}

# Create test log groups
create_test_log_groups() {
    log INFO "Creating test log groups..."
    
    local test_groups=(
        "/aws/lambda/test-function-${RANDOM_SUFFIX}"
        "/aws/apigateway/test-api-${RANDOM_SUFFIX}"
        "/application/web-app-${RANDOM_SUFFIX}"
        "${TEST_LOG_GROUP}"
    )
    
    for log_group in "${test_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
            log WARN "Log group $log_group already exists, skipping creation"
        else
            aws logs create-log-group --log-group-name "$log_group"
            log INFO "Created test log group: $log_group"
        fi
    done
    
    log INFO "Test log groups created ✅"
}

# Execute Lambda function
execute_lambda_function() {
    log INFO "Executing Lambda function to apply retention policies..."
    
    # Invoke Lambda function
    aws lambda invoke \
        --function-name "${FUNCTION_NAME}" \
        --payload '{}' \
        --cli-binary-format raw-in-base64-out \
        "${TEMP_DIR}/response.json"
    
    # Display execution results
    log INFO "Lambda function execution results:"
    cat "${TEMP_DIR}/response.json" | python3 -m json.tool
    
    # Check for errors in response
    if grep -q '"statusCode": 500' "${TEMP_DIR}/response.json"; then
        log ERROR "Lambda function execution failed"
        return 1
    fi
    
    log INFO "Lambda function executed successfully ✅"
}

# Configure automated execution schedule
configure_schedule() {
    log INFO "Configuring automated execution schedule..."
    
    # Check if EventBridge rule already exists
    if aws events describe-rule --name "${RULE_NAME}" &> /dev/null; then
        log WARN "EventBridge rule ${RULE_NAME} already exists, skipping creation"
    else
        # Create EventBridge rule for weekly execution
        aws events put-rule \
            --name "${RULE_NAME}" \
            --schedule-expression "rate(7 days)" \
            --description "Weekly log retention policy management" \
            --state ENABLED \
            --tags Key=Project,Value=LogRetentionManager Key=ManagedBy,Value=DeployScript
        
        log INFO "EventBridge rule created: ${RULE_NAME}"
    fi
    
    # Create targets configuration
    cat > "${TEMP_DIR}/targets.json" << EOF
[
  {
    "Id": "1",
    "Arn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${FUNCTION_NAME}"
  }
]
EOF
    
    # Add Lambda function as target
    aws events put-targets \
        --rule "${RULE_NAME}" \
        --targets "file://${TEMP_DIR}/targets.json"
    
    # Grant EventBridge permission to invoke Lambda
    local statement_id="allow-eventbridge-${RANDOM_SUFFIX}"
    
    # Remove existing permission if it exists
    aws lambda remove-permission \
        --function-name "${FUNCTION_NAME}" \
        --statement-id "$statement_id" &> /dev/null || true
    
    # Add new permission
    aws lambda add-permission \
        --function-name "${FUNCTION_NAME}" \
        --statement-id "$statement_id" \
        --action "lambda:InvokeFunction" \
        --principal "events.amazonaws.com" \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${RULE_NAME}"
    
    log INFO "Automated weekly execution schedule configured ✅"
}

# Validate deployment
validate_deployment() {
    log INFO "Validating deployment..."
    
    # Check Lambda function exists and is active
    local function_state=$(aws lambda get-function \
        --function-name "${FUNCTION_NAME}" \
        --query 'Configuration.State' --output text)
    
    if [ "$function_state" != "Active" ]; then
        log ERROR "Lambda function is not in Active state: $function_state"
        return 1
    fi
    
    # Check IAM role exists
    if ! aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
        log ERROR "IAM role ${ROLE_NAME} not found"
        return 1
    fi
    
    # Check EventBridge rule exists and is enabled
    local rule_state=$(aws events describe-rule \
        --name "${RULE_NAME}" \
        --query 'State' --output text)
    
    if [ "$rule_state" != "ENABLED" ]; then
        log ERROR "EventBridge rule is not enabled: $rule_state"
        return 1
    fi
    
    # Test Lambda function execution
    log INFO "Testing Lambda function execution..."
    aws lambda invoke \
        --function-name "${FUNCTION_NAME}" \
        --payload '{}' \
        --cli-binary-format raw-in-base64-out \
        "${TEMP_DIR}/test-response.json" > /dev/null
    
    if ! grep -q '"statusCode": 200' "${TEMP_DIR}/test-response.json"; then
        log ERROR "Lambda function test execution failed"
        return 1
    fi
    
    log INFO "Deployment validation completed successfully ✅"
}

# Display deployment summary
display_summary() {
    log INFO "=== Deployment Summary ==="
    echo
    log BLUE "Resources Created:"
    log INFO "• IAM Role: ${ROLE_NAME}"
    log INFO "• Lambda Function: ${FUNCTION_NAME}"
    log INFO "• EventBridge Rule: ${RULE_NAME}"
    log INFO "• Test Log Groups: 4 groups created"
    echo
    log BLUE "Configuration:"
    log INFO "• AWS Region: ${AWS_REGION}"
    log INFO "• Schedule: Weekly (every 7 days)"
    log INFO "• Default Retention: 30 days"
    echo
    log BLUE "Next Steps:"
    log INFO "• Monitor function execution in CloudWatch Logs"
    log INFO "• Review log group retention policies"
    log INFO "• Customize retention rules as needed"
    echo
    log BLUE "Cleanup:"
    log INFO "• Run ./destroy.sh to remove all resources"
    echo
    log GREEN "Deployment completed successfully! 🎉"
}

# Main deployment function
main() {
    log INFO "Starting deployment of Simple Log Retention Management solution..."
    log INFO "Log file: $LOG_FILE"
    echo
    
    # Execute deployment steps
    check_prerequisites
    initialize_environment
    create_iam_role
    create_lambda_function
    create_test_log_groups
    execute_lambda_function
    configure_schedule
    validate_deployment
    display_summary
    
    log INFO "Deployment completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help]"
        echo
        echo "Deploy Simple Log Retention Management with CloudWatch and Lambda"
        echo
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo
        echo "This script will create:"
        echo "  • IAM role for Lambda execution"
        echo "  • Lambda function for log retention management"
        echo "  • EventBridge schedule for weekly execution"
        echo "  • Test log groups for validation"
        echo
        echo "Prerequisites:"
        echo "  • AWS CLI installed and configured"
        echo "  • Appropriate AWS permissions"
        echo "  • Python 3 for JSON processing"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        log ERROR "Unknown option: $1"
        log INFO "Use --help for usage information"
        exit 1
        ;;
esac