#!/bin/bash

# Deploy script for CloudWatch Log Analytics with Insights
# This script automates the deployment of log analytics infrastructure

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    log "Running in dry-run mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would execute: $cmd"
        log "[DRY-RUN] Description: $description"
        return 0
    else
        log "Executing: $description"
        eval "$cmd"
        return $?
    fi
}

# Banner
echo "=============================================="
echo "  Log Analytics Solutions Deployment Script"
echo "=============================================="
echo

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS CLI is not configured. Please run 'aws configure' first."
fi

# Check if jq is installed (for JSON parsing)
if ! command -v jq &> /dev/null; then
    warning "jq is not installed. Some output formatting may be limited."
fi

# Check AWS permissions
log "Verifying AWS permissions..."
if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity &> /dev/null; then
    error "Unable to verify AWS credentials. Please check your AWS configuration."
fi

success "Prerequisites check completed"

# Environment setup
log "Setting up environment variables..."

# Set AWS region
AWS_REGION=$(aws configure get region)
if [[ -z "$AWS_REGION" ]]; then
    AWS_REGION="us-east-1"
    warning "AWS region not configured, using default: $AWS_REGION"
fi
export AWS_REGION

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    error "Unable to determine AWS account ID"
fi
export AWS_ACCOUNT_ID

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

export LOG_GROUP_NAME="/aws/lambda/log-analytics-${RANDOM_SUFFIX}"
export SNS_TOPIC_NAME="log-analytics-alerts-${RANDOM_SUFFIX}"
export LAMBDA_FUNCTION_NAME="log-analytics-processor-${RANDOM_SUFFIX}"

# Prompt for notification email if not set
if [[ -z "$NOTIFICATION_EMAIL" ]]; then
    read -p "Enter your email address for notifications: " NOTIFICATION_EMAIL
    if [[ -z "$NOTIFICATION_EMAIL" ]]; then
        error "Notification email is required"
    fi
fi
export NOTIFICATION_EMAIL

# Validate email format
if [[ ! "$NOTIFICATION_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    error "Invalid email format: $NOTIFICATION_EMAIL"
fi

log "Environment configuration:"
log "  AWS Region: $AWS_REGION"
log "  AWS Account ID: $AWS_ACCOUNT_ID"
log "  Log Group: $LOG_GROUP_NAME"
log "  SNS Topic: $SNS_TOPIC_NAME"
log "  Lambda Function: $LAMBDA_FUNCTION_NAME"
log "  Notification Email: $NOTIFICATION_EMAIL"

# Create temporary directory for files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Step 1: Create CloudWatch Log Group
log "Step 1: Creating CloudWatch Log Group..."

# Check if log group already exists
if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query "logGroups[?logGroupName=='$LOG_GROUP_NAME']" --output text | grep -q "$LOG_GROUP_NAME"; then
    warning "Log group $LOG_GROUP_NAME already exists, skipping creation"
else
    execute_command "aws logs create-log-group --log-group-name '$LOG_GROUP_NAME' --region '$AWS_REGION'" "Creating log group"
    success "Log group created: $LOG_GROUP_NAME"
fi

# Set retention policy
execute_command "aws logs put-retention-policy --log-group-name '$LOG_GROUP_NAME' --retention-in-days 30" "Setting retention policy"
success "Retention policy set to 30 days"

# Step 2: Generate sample log data
log "Step 2: Generating sample log data..."

# Create sample log entries
TIMESTAMP=$(date +%s000)
execute_command "aws logs put-log-events \
    --log-group-name '$LOG_GROUP_NAME' \
    --log-stream-name 'api-server-001' \
    --log-events \
    timestamp=$TIMESTAMP,message='[INFO] API Request: GET /users/123 - 200 - 45ms' \
    timestamp=$((TIMESTAMP + 1000)),message='[ERROR] Database connection failed - Connection timeout' \
    timestamp=$((TIMESTAMP + 2000)),message='[INFO] API Request: POST /orders - 201 - 120ms' \
    timestamp=$((TIMESTAMP + 3000)),message='[WARN] High memory usage detected: 85%' \
    timestamp=$((TIMESTAMP + 4000)),message='[INFO] API Request: GET /products - 200 - 32ms'" "Generating sample log data"

success "Sample log data generated"

# Step 3: Create SNS topic
log "Step 3: Creating SNS topic for alerts..."

# Check if SNS topic already exists
if aws sns list-topics --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')]" --output text | grep -q "$SNS_TOPIC_NAME"; then
    warning "SNS topic $SNS_TOPIC_NAME already exists, getting ARN"
    SNS_TOPIC_ARN=$(aws sns list-topics --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text)
else
    SNS_TOPIC_ARN=$(execute_command "aws sns create-topic --name '$SNS_TOPIC_NAME' --query 'TopicArn' --output text" "Creating SNS topic")
    success "SNS topic created: $SNS_TOPIC_ARN"
fi

# Subscribe email to SNS topic
execute_command "aws sns subscribe --topic-arn '$SNS_TOPIC_ARN' --protocol email --notification-endpoint '$NOTIFICATION_EMAIL'" "Subscribing email to SNS topic"
success "Email subscription created. Please check your email and confirm the subscription."

# Step 4: Create IAM role for Lambda
log "Step 4: Creating IAM role for Lambda function..."

# Create trust policy
cat > "$TEMP_DIR/trust-policy.json" << EOF
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

# Check if IAM role already exists
if aws iam get-role --role-name "${LAMBDA_FUNCTION_NAME}-role" &> /dev/null; then
    warning "IAM role ${LAMBDA_FUNCTION_NAME}-role already exists, skipping creation"
    LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "${LAMBDA_FUNCTION_NAME}-role" --query 'Role.Arn' --output text)
else
    LAMBDA_ROLE_ARN=$(execute_command "aws iam create-role \
        --role-name '${LAMBDA_FUNCTION_NAME}-role' \
        --assume-role-policy-document file://$TEMP_DIR/trust-policy.json \
        --query 'Role.Arn' --output text" "Creating IAM role")
    success "IAM role created: $LAMBDA_ROLE_ARN"
fi

# Step 5: Attach IAM policies
log "Step 5: Attaching IAM policies..."

# Attach basic Lambda execution role
execute_command "aws iam attach-role-policy \
    --role-name '${LAMBDA_FUNCTION_NAME}-role' \
    --policy-arn 'arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole'" "Attaching Lambda basic execution policy"

# Attach SNS publishing permissions
execute_command "aws iam attach-role-policy \
    --role-name '${LAMBDA_FUNCTION_NAME}-role' \
    --policy-arn 'arn:aws:iam::aws:policy/AmazonSNSFullAccess'" "Attaching SNS publishing policy"

# Create custom policy for CloudWatch Logs Insights
cat > "$TEMP_DIR/logs-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:StartQuery",
                "logs:GetQueryResults",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Check if custom policy already exists
if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_FUNCTION_NAME}-logs-policy" &> /dev/null; then
    warning "Custom logs policy already exists, skipping creation"
else
    execute_command "aws iam create-policy \
        --policy-name '${LAMBDA_FUNCTION_NAME}-logs-policy' \
        --policy-document file://$TEMP_DIR/logs-policy.json" "Creating custom logs policy"
    success "Custom logs policy created"
fi

# Attach custom policy
execute_command "aws iam attach-role-policy \
    --role-name '${LAMBDA_FUNCTION_NAME}-role' \
    --policy-arn 'arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_FUNCTION_NAME}-logs-policy'" "Attaching custom logs policy"

success "All IAM policies attached"

# Wait for IAM role to be available
log "Waiting for IAM role to be available..."
sleep 10

# Step 6: Create Lambda function
log "Step 6: Creating Lambda function..."

# Create Lambda function code
cat > "$TEMP_DIR/lambda_function.py" << EOF
import json
import boto3
import time
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    logs_client = boto3.client('logs')
    sns_client = boto3.client('sns')
    
    # Get configuration from environment variables
    log_group_name = os.environ.get('LOG_GROUP_NAME', '${LOG_GROUP_NAME}')
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN', '${SNS_TOPIC_ARN}')
    
    # Query for errors in the last hour
    end_time = int(time.time())
    start_time = end_time - 3600  # 1 hour ago
    
    query = '''
    fields @timestamp, @message
    | filter @message like /ERROR/
    | stats count() as error_count
    '''
    
    try:
        print(f"Starting query for log group: {log_group_name}")
        
        # Start CloudWatch Logs Insights query
        response = logs_client.start_query(
            logGroupName=log_group_name,
            startTime=start_time,
            endTime=end_time,
            queryString=query
        )
        
        query_id = response['queryId']
        print(f"Query started with ID: {query_id}")
        
        # Wait for query completion
        max_attempts = 30
        attempts = 0
        while attempts < max_attempts:
            result = logs_client.get_query_results(queryId=query_id)
            if result['status'] == 'Complete':
                break
            elif result['status'] == 'Failed':
                raise Exception(f"Query failed: {result.get('statistics', {}).get('recordsMatched', 'Unknown error')}")
            time.sleep(1)
            attempts += 1
        
        if attempts >= max_attempts:
            raise Exception("Query timed out after 30 seconds")
        
        print(f"Query completed successfully. Results: {result['results']}")
        
        # Check results and send alert if errors found
        error_count = 0
        if result['results']:
            for row in result['results']:
                if row and len(row) > 0:
                    error_count = int(row[0]['value'])
                    break
        
        if error_count > 0:
            message = f"Alert: {error_count} errors detected in the last hour in log group {log_group_name}"
            print(f"Sending alert: {message}")
            
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=message,
                Subject='Log Analytics Alert - Errors Detected'
            )
            print("Alert sent successfully")
        else:
            print("No errors detected in the last hour")
                
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Log analysis completed successfully',
                'error_count': error_count,
                'query_id': query_id
            })
        }
        
    except Exception as e:
        error_message = f"Error during log analysis: {str(e)}"
        print(error_message)
        
        # Send error notification
        try:
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=f"Log analytics function failed: {error_message}",
                Subject='Log Analytics Alert - Function Error'
            )
        except Exception as sns_error:
            print(f"Failed to send error notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message
            })
        }
EOF

# Package Lambda function
cd "$TEMP_DIR"
zip -r lambda-function.zip lambda_function.py

# Check if Lambda function already exists
if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
    warning "Lambda function $LAMBDA_FUNCTION_NAME already exists, updating code"
    execute_command "aws lambda update-function-code \
        --function-name '$LAMBDA_FUNCTION_NAME' \
        --zip-file fileb://lambda-function.zip" "Updating Lambda function code"
else
    execute_command "aws lambda create-function \
        --function-name '$LAMBDA_FUNCTION_NAME' \
        --runtime python3.9 \
        --role '$LAMBDA_ROLE_ARN' \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda-function.zip \
        --timeout 60 \
        --environment Variables='{LOG_GROUP_NAME=$LOG_GROUP_NAME,SNS_TOPIC_ARN=$SNS_TOPIC_ARN}'" "Creating Lambda function"
    success "Lambda function created: $LAMBDA_FUNCTION_NAME"
fi

cd - > /dev/null

# Step 7: Create CloudWatch Events rule
log "Step 7: Creating CloudWatch Events rule for scheduled analysis..."

# Check if rule already exists
if aws events describe-rule --name "${LAMBDA_FUNCTION_NAME}-schedule" &> /dev/null; then
    warning "CloudWatch Events rule already exists, skipping creation"
else
    execute_command "aws events put-rule \
        --name '${LAMBDA_FUNCTION_NAME}-schedule' \
        --schedule-expression 'rate(5 minutes)' \
        --description 'Automated log analysis every 5 minutes'" "Creating CloudWatch Events rule"
    success "CloudWatch Events rule created"
fi

# Add Lambda function as target
execute_command "aws events put-targets \
    --rule '${LAMBDA_FUNCTION_NAME}-schedule' \
    --targets 'Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}'" "Adding Lambda function as target"

# Grant permission for Events to invoke Lambda
execute_command "aws lambda add-permission \
    --function-name '$LAMBDA_FUNCTION_NAME' \
    --statement-id allow-eventbridge \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn 'arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${LAMBDA_FUNCTION_NAME}-schedule'" "Granting EventBridge permission"

success "Automated log analysis scheduled every 5 minutes"

# Step 8: Test the deployment
log "Step 8: Testing the deployment..."

# Test Lambda function
log "Testing Lambda function execution..."
execute_command "aws lambda invoke \
    --function-name '$LAMBDA_FUNCTION_NAME' \
    --payload '{}' \
    '$TEMP_DIR/response.json'" "Testing Lambda function"

if [[ "$DRY_RUN" == "false" ]]; then
    if [[ -f "$TEMP_DIR/response.json" ]]; then
        log "Lambda function response:"
        cat "$TEMP_DIR/response.json"
        echo
    fi
fi

# Verification steps
log "Performing verification checks..."

# Check log group
execute_command "aws logs describe-log-groups --log-group-name-prefix '$LOG_GROUP_NAME'" "Verifying log group"

# Check SNS topic
execute_command "aws sns list-subscriptions-by-topic --topic-arn '$SNS_TOPIC_ARN'" "Verifying SNS subscriptions"

# Check CloudWatch Events rule
execute_command "aws events describe-rule --name '${LAMBDA_FUNCTION_NAME}-schedule'" "Verifying CloudWatch Events rule"

# Save deployment information
cat > "$TEMP_DIR/deployment-info.json" << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "resources": {
        "log_group_name": "$LOG_GROUP_NAME",
        "sns_topic_name": "$SNS_TOPIC_NAME",
        "sns_topic_arn": "$SNS_TOPIC_ARN",
        "lambda_function_name": "$LAMBDA_FUNCTION_NAME",
        "lambda_role_arn": "$LAMBDA_ROLE_ARN",
        "notification_email": "$NOTIFICATION_EMAIL"
    }
}
EOF

if [[ "$DRY_RUN" == "false" ]]; then
    cp "$TEMP_DIR/deployment-info.json" "./deployment-info.json"
    success "Deployment information saved to deployment-info.json"
fi

echo
echo "=============================================="
echo "         DEPLOYMENT COMPLETED SUCCESSFULLY"
echo "=============================================="
echo
success "Log Analytics Solution has been deployed successfully!"
echo
echo "Resource Summary:"
echo "  📊 Log Group: $LOG_GROUP_NAME"
echo "  📧 SNS Topic: $SNS_TOPIC_NAME"
echo "  ⚡ Lambda Function: $LAMBDA_FUNCTION_NAME"
echo "  📅 Schedule: Every 5 minutes"
echo "  💌 Notifications: $NOTIFICATION_EMAIL"
echo
echo "Next Steps:"
echo "  1. Check your email and confirm the SNS subscription"
echo "  2. Monitor the Lambda function logs for automated analysis"
echo "  3. Use CloudWatch Logs Insights for manual queries"
echo "  4. View the deployment-info.json file for resource details"
echo
echo "To clean up resources, run: ./destroy.sh"
echo
warning "Remember to confirm your email subscription to receive alerts!"