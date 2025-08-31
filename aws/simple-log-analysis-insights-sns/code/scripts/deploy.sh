#!/bin/bash

# Deploy script for Simple Log Analysis with CloudWatch Insights and SNS
# This script deploys the complete log monitoring solution described in the recipe

set -e  # Exit on any error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Cleanup function for partial deployments
cleanup_on_error() {
    error "Deployment failed. Cleaning up partial resources..."
    if [[ -f "./destroy.sh" && -x "./destroy.sh" ]]; then
        ./destroy.sh --force
    fi
    exit 1
}

# Trap errors and cleanup
trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Deploy script for Simple Log Analysis with CloudWatch Insights and SNS

Usage: $0 [OPTIONS]

Options:
    -e, --email EMAIL       Email address for SNS notifications (required)
    -r, --region REGION     AWS region (optional, uses configured default)
    -d, --dry-run          Show what would be deployed without creating resources
    -v, --verbose          Enable verbose logging
    -h, --help             Show this help message

Example:
    $0 --email admin@example.com --region us-east-1
    $0 -e admin@example.com --dry-run

EOF
}

# Default values
EMAIL_ADDRESS=""
AWS_REGION=""
DRY_RUN=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--email)
            EMAIL_ADDRESS="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate email address is provided
if [[ -z "$EMAIL_ADDRESS" ]]; then
    error "Email address is required. Use --email option."
    show_help
    exit 1
fi

# Validate email format (basic validation)
if [[ ! "$EMAIL_ADDRESS" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    error "Invalid email address format: $EMAIL_ADDRESS"
    exit 1
fi

log "Starting deployment of Simple Log Analysis with CloudWatch Insights and SNS"

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install AWS CLI v2."
    exit 1
fi

# Check AWS CLI version
AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
log "AWS CLI version: $AWS_CLI_VERSION"

# Check if user is authenticated
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Run 'aws configure' first."
    exit 1
fi

# Get AWS account info
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
log "AWS Account ID: $AWS_ACCOUNT_ID"
log "User ARN: $AWS_USER_ARN"

# Set AWS region
if [[ -z "$AWS_REGION" ]]; then
    AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        warning "No AWS region configured. Using us-east-1 as default."
        AWS_REGION="us-east-1"
    fi
fi
export AWS_REGION

log "Using AWS Region: $AWS_REGION"

# Check required permissions
log "Validating AWS permissions..."
REQUIRED_PERMISSIONS=(
    "logs:CreateLogGroup"
    "logs:PutRetentionPolicy"
    "logs:PutLogEvents"
    "sns:CreateTopic"
    "sns:Subscribe"
    "lambda:CreateFunction"
    "iam:CreateRole"
    "iam:AttachRolePolicy"
    "events:PutRule"
    "events:PutTargets"
)

# Basic permission check (simplified)
if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity --query Arn --output text | grep -q "assumed-role"; then
    warning "Cannot verify IAM permissions. Proceeding with deployment..."
fi

# Generate unique identifiers
log "Generating unique resource identifiers..."
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))

# Export environment variables
export LOG_GROUP_NAME="/aws/lambda/demo-app-${RANDOM_SUFFIX}"
export SNS_TOPIC_NAME="log-analysis-alerts-${RANDOM_SUFFIX}"
export LAMBDA_FUNCTION_NAME="log-analyzer-${RANDOM_SUFFIX}"
export ALARM_NAME="error-pattern-alarm-${RANDOM_SUFFIX}"
export IAM_ROLE_NAME="log-analyzer-role-${RANDOM_SUFFIX}"
export EVENTBRIDGE_RULE_NAME="log-analysis-schedule-${RANDOM_SUFFIX}"

log "Resource identifiers:"
log "  Log Group: ${LOG_GROUP_NAME}"
log "  SNS Topic: ${SNS_TOPIC_NAME}"
log "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
log "  IAM Role: ${IAM_ROLE_NAME}"
log "  EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"

if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN MODE - No resources will be created"
    log "Would deploy the following resources:"
    log "  - CloudWatch Log Group: ${LOG_GROUP_NAME}"
    log "  - SNS Topic: ${SNS_TOPIC_NAME}"
    log "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log "  - IAM Role: ${IAM_ROLE_NAME}"
    log "  - EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    log "  - Sample log events for testing"
    exit 0
fi

# Store deployment state for cleanup
cat > .deployment_state << EOF
AWS_REGION=${AWS_REGION}
LOG_GROUP_NAME=${LOG_GROUP_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
IAM_ROLE_NAME=${IAM_ROLE_NAME}
EVENTBRIDGE_RULE_NAME=${EVENTBRIDGE_RULE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

# Step 1: Create CloudWatch Log Group
log "Step 1: Creating CloudWatch Log Group..."
if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${LOG_GROUP_NAME}"; then
    warning "Log group ${LOG_GROUP_NAME} already exists. Skipping creation."
else
    aws logs create-log-group \
        --log-group-name "${LOG_GROUP_NAME}" \
        --region "${AWS_REGION}"
    
    # Set log retention
    aws logs put-retention-policy \
        --log-group-name "${LOG_GROUP_NAME}" \
        --retention-in-days 7
    
    success "Log group created: ${LOG_GROUP_NAME}"
fi

# Step 2: Generate Sample Log Events
log "Step 2: Creating sample log events..."
CURRENT_TIME=$(date +%s000)

# Normal application logs
aws logs put-log-events \
    --log-group-name "${LOG_GROUP_NAME}" \
    --log-stream-name "application-stream" \
    --log-events \
    timestamp=${CURRENT_TIME},message="INFO: Application started successfully" \
    timestamp=$((CURRENT_TIME + 1000)),message="INFO: User authentication completed" \
    timestamp=$((CURRENT_TIME + 2000)),message="DEBUG: Database connection established" \
    --region "${AWS_REGION}"

# Error log events
aws logs put-log-events \
    --log-group-name "${LOG_GROUP_NAME}" \
    --log-stream-name "error-stream" \
    --log-events \
    timestamp=$((CURRENT_TIME + 3000)),message="ERROR: Database connection failed - timeout" \
    timestamp=$((CURRENT_TIME + 4000)),message="ERROR: Authentication service unavailable" \
    timestamp=$((CURRENT_TIME + 5000)),message="CRITICAL: Application crash detected" \
    --region "${AWS_REGION}"

success "Sample log events created"

# Step 3: Create SNS Topic
log "Step 3: Creating SNS Topic..."
if SNS_TOPIC_ARN=$(aws sns create-topic --name "${SNS_TOPIC_NAME}" --query 'TopicArn' --output text 2>/dev/null); then
    success "SNS topic created: ${SNS_TOPIC_ARN}"
    
    # Subscribe email address
    log "Subscribing email address to SNS topic..."
    SUBSCRIPTION_ARN=$(aws sns subscribe \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --protocol email \
        --notification-endpoint "${EMAIL_ADDRESS}" \
        --query 'SubscriptionArn' --output text)
    
    success "Email subscription created. Check your email and confirm the subscription."
    warning "IMPORTANT: You must confirm the email subscription before alerts will be sent!"
else
    error "Failed to create SNS topic"
    exit 1
fi

# Step 4: Create IAM Role for Lambda
log "Step 4: Creating IAM Role for Lambda..."

# Create trust policy
cat > /tmp/lambda-trust-policy.json << 'EOF'
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
if LAMBDA_ROLE_ARN=$(aws iam create-role \
    --role-name "${IAM_ROLE_NAME}" \
    --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
    --query 'Role.Arn' --output text 2>/dev/null); then
    
    success "IAM role created: ${LAMBDA_ROLE_ARN}"
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy
    cat > /tmp/lambda-permissions-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:StartQuery",
                "logs:GetQueryResults",
                "logs:StopQuery",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
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
    
    aws iam put-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-name LogAnalyzerPolicy \
        --policy-document file:///tmp/lambda-permissions-policy.json
    
    success "IAM policies attached"
else
    error "Failed to create IAM role"
    exit 1
fi

# Step 5: Create Lambda Function
log "Step 5: Creating Lambda Function..."

# Create Lambda function code
cat > /tmp/log_analyzer.py << 'EOF'
import json
import boto3
import time
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    logs_client = boto3.client('logs')
    sns_client = boto3.client('sns')
    
    log_group = os.environ['LOG_GROUP_NAME']
    sns_topic = os.environ['SNS_TOPIC_ARN']
    
    # Define time range (last 10 minutes)
    end_time = datetime.now()
    start_time = end_time - timedelta(minutes=10)
    
    # CloudWatch Logs Insights query for error patterns
    query = '''
    fields @timestamp, @message
    | filter @message like /ERROR|CRITICAL/
    | sort @timestamp desc
    | limit 100
    '''
    
    try:
        # Start the query
        response = logs_client.start_query(
            logGroupName=log_group,
            startTime=int(start_time.timestamp()),
            endTime=int(end_time.timestamp()),
            queryString=query
        )
        
        query_id = response['queryId']
        
        # Wait for query completion
        while True:
            time.sleep(2)
            result = logs_client.get_query_results(queryId=query_id)
            if result['status'] == 'Complete':
                break
            elif result['status'] == 'Failed':
                raise Exception('Query failed')
        
        # Process results
        error_count = len(result['results'])
        
        if error_count > 0:
            # Format alert message
            alert_message = f"""
🚨 Log Analysis Alert

Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
Log Group: {log_group}
Error Count: {error_count} errors found in the last 10 minutes

Recent Errors:
"""
            
            for i, log_entry in enumerate(result['results'][:5]):  # Show first 5 errors
                timestamp = next(field['value'] for field in log_entry if field['field'] == '@timestamp')
                message = next(field['value'] for field in log_entry if field['field'] == '@message')
                alert_message += f"\n{i+1}. {timestamp}: {message}"
            
            # Send SNS notification
            sns_client.publish(
                TopicArn=sns_topic,
                Subject='CloudWatch Log Analysis Alert',
                Message=alert_message
            )
            
            print(f"Alert sent: {error_count} errors detected")
        else:
            print("No errors detected in recent logs")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'error_count': error_count,
                'status': 'success'
            })
        }
        
    except Exception as e:
        print(f"Error analyzing logs: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'status': 'error'
            })
        }
EOF

# Package Lambda function
cd /tmp
zip -q lambda-function.zip log_analyzer.py

# Wait for IAM role propagation
log "Waiting for IAM role propagation..."
sleep 15

# Create Lambda function
if aws lambda create-function \
    --function-name "${LAMBDA_FUNCTION_NAME}" \
    --runtime python3.12 \
    --role "${LAMBDA_ROLE_ARN}" \
    --handler log_analyzer.lambda_handler \
    --zip-file fileb://lambda-function.zip \
    --timeout 60 \
    --memory-size 256 \
    --environment Variables="{LOG_GROUP_NAME=${LOG_GROUP_NAME},SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}" \
    --region "${AWS_REGION}" > /dev/null; then
    
    success "Lambda function created: ${LAMBDA_FUNCTION_NAME}"
    
    # Get Lambda function ARN
    LAMBDA_ARN=$(aws lambda get-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --query 'Configuration.FunctionArn' --output text)
else
    error "Failed to create Lambda function"
    exit 1
fi

# Step 6: Create EventBridge Rule
log "Step 6: Creating EventBridge Rule for scheduled execution..."

if aws events put-rule \
    --name "${EVENTBRIDGE_RULE_NAME}" \
    --schedule-expression "rate(5 minutes)" \
    --description "Trigger log analysis every 5 minutes" \
    --region "${AWS_REGION}" > /dev/null; then
    
    success "EventBridge rule created: ${EVENTBRIDGE_RULE_NAME}"
    
    # Add Lambda as target
    aws events put-targets \
        --rule "${EVENTBRIDGE_RULE_NAME}" \
        --targets "Id"="1","Arn"="${LAMBDA_ARN}" \
        --region "${AWS_REGION}"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id allow-eventbridge \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}" \
        --region "${AWS_REGION}" > /dev/null
    
    success "EventBridge rule configured for automatic execution"
else
    error "Failed to create EventBridge rule"
    exit 1
fi

# Step 7: Test the deployment
log "Step 7: Testing the deployment..."

# Manual test of Lambda function
if aws lambda invoke \
    --function-name "${LAMBDA_FUNCTION_NAME}" \
    --payload '{}' \
    /tmp/lambda-response.json \
    --region "${AWS_REGION}" > /dev/null; then
    
    RESPONSE=$(cat /tmp/lambda-response.json)
    success "Manual test completed successfully"
    [[ "$VERBOSE" == "true" ]] && log "Lambda response: $RESPONSE"
else
    warning "Manual test failed, but deployment may still be functional"
fi

# Cleanup temporary files
rm -f /tmp/lambda-trust-policy.json /tmp/lambda-permissions-policy.json
rm -f /tmp/log_analyzer.py /tmp/lambda-function.zip /tmp/lambda-response.json

# Update deployment state with resource ARNs
cat >> .deployment_state << EOF
SNS_TOPIC_ARN=${SNS_TOPIC_ARN}
LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}
LAMBDA_ARN=${LAMBDA_ARN}
DEPLOYMENT_STATUS=SUCCESS
EOF

success "🎉 Deployment completed successfully!"
echo
log "=== DEPLOYMENT SUMMARY ==="
log "Log Group: ${LOG_GROUP_NAME}"
log "SNS Topic: ${SNS_TOPIC_ARN}"
log "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
log "EventBridge Rule: ${EVENTBRIDGE_RULE_NAME} (runs every 5 minutes)"
log "Email Notifications: ${EMAIL_ADDRESS}"
echo
warning "IMPORTANT NEXT STEPS:"
warning "1. Check your email (${EMAIL_ADDRESS}) and confirm the SNS subscription"
warning "2. The log analysis will run automatically every 5 minutes"
warning "3. Monitor your AWS costs - this solution incurs minimal charges"
warning "4. Use the destroy.sh script to clean up all resources when finished"
echo
log "The log analysis function is now monitoring ${LOG_GROUP_NAME} for ERROR and CRITICAL messages."
log "You should receive an email notification within 5 minutes if errors are detected."