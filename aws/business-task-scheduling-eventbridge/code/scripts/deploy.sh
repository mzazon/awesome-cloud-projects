#!/bin/bash
set -euo pipefail

# AWS EventBridge Scheduler and Lambda Business Automation Deployment Script
# This script automates the deployment of business task scheduling infrastructure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script metadata
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEPLOYMENT_STATE="${SCRIPT_DIR}/.deployment_state"

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    if [[ -f "${DEPLOYMENT_STATE}" ]]; then
        source "${DEPLOYMENT_STATE}"
        
        # Clean up resources in reverse order
        [[ -n "${SCHEDULE_NAMES:-}" ]] && {
            for schedule in ${SCHEDULE_NAMES}; do
                aws scheduler delete-schedule --name "${schedule}" 2>/dev/null || true
            done
        }
        
        [[ -n "${SCHEDULE_GROUP_NAME:-}" ]] && {
            aws scheduler delete-schedule-group --name "${SCHEDULE_GROUP_NAME}" 2>/dev/null || true
        }
        
        [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]] && {
            aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}" 2>/dev/null || true
        }
        
        [[ -n "${LAMBDA_ROLE_NAME:-}" ]] && {
            aws iam detach-role-policy --role-name "${LAMBDA_ROLE_NAME}" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
            aws iam detach-role-policy --role-name "${LAMBDA_ROLE_NAME}" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_ROLE_NAME}-policy" 2>/dev/null || true
            aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_ROLE_NAME}-policy" 2>/dev/null || true
            aws iam delete-role --role-name "${LAMBDA_ROLE_NAME}" 2>/dev/null || true
        }
        
        [[ -n "${SCHEDULER_ROLE_NAME:-}" ]] && {
            aws iam detach-role-policy --role-name "${SCHEDULER_ROLE_NAME}" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${SCHEDULER_ROLE_NAME}-policy" 2>/dev/null || true
            aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${SCHEDULER_ROLE_NAME}-policy" 2>/dev/null || true
            aws iam delete-role --role-name "${SCHEDULER_ROLE_NAME}" 2>/dev/null || true
        }
        
        [[ -n "${TOPIC_ARN:-}" ]] && {
            aws sns delete-topic --topic-arn "${TOPIC_ARN}" 2>/dev/null || true
        }
        
        [[ -n "${BUCKET_NAME:-}" ]] && {
            aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>/dev/null || true
            aws s3 rb "s3://${BUCKET_NAME}" 2>/dev/null || true
        }
        
        rm -f "${DEPLOYMENT_STATE}"
    fi
    exit 1
}

# Set error trap
trap cleanup_on_error ERR

print_banner() {
    log_info "=============================================================="
    log_info "AWS Business Task Scheduling Automation Deployment"
    log_info "Recipe: EventBridge Scheduler + Lambda + SNS + S3"
    log_info "=============================================================="
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: ${AWS_CLI_VERSION}"
    
    # Check AWS authentication
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS authentication failed. Please configure AWS CLI credentials."
        exit 1
    fi
    
    # Check required tools
    for tool in zip jq; do
        if ! command -v "${tool}" &> /dev/null; then
            log_error "${tool} is not installed. Please install ${tool}."
            exit 1
        fi
    done
    
    log_success "Prerequisites check completed"
}

setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS account information
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 7)")
    
    # Set resource names
    export BUCKET_NAME="business-automation-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="business-notifications-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="business-task-processor-${RANDOM_SUFFIX}"
    export SCHEDULER_ROLE_NAME="eventbridge-scheduler-role-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="lambda-execution-role-${RANDOM_SUFFIX}"
    export SCHEDULE_GROUP_NAME="business-automation-group"
    export NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-admin@example.com}"
    
    # Save deployment state
    cat > "${DEPLOYMENT_STATE}" << EOF
AWS_REGION="${AWS_REGION}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
BUCKET_NAME="${BUCKET_NAME}"
SNS_TOPIC_NAME="${SNS_TOPIC_NAME}"
LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME}"
SCHEDULER_ROLE_NAME="${SCHEDULER_ROLE_NAME}"
LAMBDA_ROLE_NAME="${LAMBDA_ROLE_NAME}"
SCHEDULE_GROUP_NAME="${SCHEDULE_GROUP_NAME}"
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL}"
RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF
    
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "Resource Suffix: ${RANDOM_SUFFIX}"
    log_success "Environment setup completed"
}

create_s3_bucket() {
    log_info "Creating S3 bucket for report storage..."
    
    # Create S3 bucket
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
        aws s3 mb "s3://${BUCKET_NAME}"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
    fi
    
    # Wait for bucket to be available
    aws s3api wait bucket-exists --bucket "${BUCKET_NAME}"
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "${BUCKET_NAME}" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    # Add lifecycle policy for cost optimization
    cat > bucket-lifecycle.json << 'EOF'
{
    "Rules": [
        {
            "ID": "BusinessAutomationLifecycle",
            "Status": "Enabled",
            "Filter": {"Prefix": "reports/"},
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }
            ]
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "${BUCKET_NAME}" \
        --lifecycle-configuration file://bucket-lifecycle.json
    
    rm -f bucket-lifecycle.json
    
    echo "BUCKET_NAME=\"${BUCKET_NAME}\"" >> "${DEPLOYMENT_STATE}"
    log_success "S3 bucket created: ${BUCKET_NAME}"
}

create_sns_topic() {
    log_info "Creating SNS topic for notifications..."
    
    # Create SNS topic
    aws sns create-topic --name "${SNS_TOPIC_NAME}"
    
    # Get topic ARN
    TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
        --query 'Attributes.TopicArn' --output text)
    
    # Subscribe email endpoint
    if [[ "${NOTIFICATION_EMAIL}" != "admin@example.com" ]]; then
        aws sns subscribe \
            --topic-arn "${TOPIC_ARN}" \
            --protocol email \
            --notification-endpoint "${NOTIFICATION_EMAIL}"
        log_info "Email subscription created. Please check your email and confirm the subscription."
    else
        log_warning "Using default email address. Set NOTIFICATION_EMAIL environment variable for actual notifications."
    fi
    
    echo "TOPIC_ARN=\"${TOPIC_ARN}\"" >> "${DEPLOYMENT_STATE}"
    log_success "SNS topic created: ${SNS_TOPIC_NAME}"
}

create_lambda_role() {
    log_info "Creating IAM role for Lambda execution..."
    
    # Create trust policy
    cat > lambda-trust-policy.json << 'EOF'
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
    
    # Create Lambda execution role
    aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document file://lambda-trust-policy.json \
        --description "Execution role for business task automation Lambda function"
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for S3 and SNS access
    cat > lambda-permissions-policy.json << EOF
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
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "${TOPIC_ARN}"
        }
    ]
}
EOF
    
    # Create and attach the custom policy
    aws iam create-policy \
        --policy-name "${LAMBDA_ROLE_NAME}-policy" \
        --policy-document file://lambda-permissions-policy.json \
        --description "Custom permissions for business automation Lambda function"
    
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_ROLE_NAME}-policy"
    
    # Wait for role to be available
    sleep 10
    
    rm -f lambda-trust-policy.json lambda-permissions-policy.json
    
    echo "LAMBDA_ROLE_NAME=\"${LAMBDA_ROLE_NAME}\"" >> "${DEPLOYMENT_STATE}"
    log_success "Lambda execution role created: ${LAMBDA_ROLE_NAME}"
}

create_lambda_function() {
    log_info "Creating Lambda function for business task processing..."
    
    # Create Lambda function code
    cat > business_task_processor.py << 'EOF'
import json
import boto3
import datetime
from io import StringIO
import csv
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Main Lambda handler for business task automation
    Supports multiple task types: report, data_processing, notification
    """
    try:
        # Get task type from event
        task_type = event.get('task_type', 'report')
        bucket_name = os.environ['BUCKET_NAME']
        topic_arn = os.environ['TOPIC_ARN']
        
        logger.info(f"Processing task type: {task_type}")
        
        if task_type == 'report':
            result = generate_daily_report(bucket_name)
        elif task_type == 'data_processing':
            result = process_business_data(bucket_name)
        elif task_type == 'notification':
            result = send_business_notification(topic_arn)
        else:
            raise ValueError(f"Unknown task type: {task_type}")
        
        # Send success notification
        sns.publish(
            TopicArn=topic_arn,
            Message=f"Business task completed successfully: {result}",
            Subject=f"✅ Task Completion - {task_type.replace('_', ' ').title()}"
        )
        
        logger.info(f"Task completed successfully: {result}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Task completed successfully',
                'result': result,
                'task_type': task_type,
                'timestamp': datetime.datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Task failed: {error_msg}")
        
        # Send failure notification
        try:
            sns.publish(
                TopicArn=topic_arn,
                Message=f"Business task failed: {error_msg}",
                Subject=f"❌ Task Failure - {task_type.replace('_', ' ').title()}"
            )
        except Exception as sns_error:
            logger.error(f"Failed to send error notification: {sns_error}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_msg,
                'task_type': task_type,
                'timestamp': datetime.datetime.now().isoformat()
            })
        }

def generate_daily_report(bucket_name):
    """Generate sample business report and upload to S3"""
    now = datetime.datetime.now()
    
    # Generate sample business data
    report_data = [
        ['Date', 'Revenue', 'Orders', 'Customers', 'Conversion Rate'],
        [now.strftime('%Y-%m-%d'), '12500.00', '45', '38', '84.4%'],
        [(now - datetime.timedelta(days=1)).strftime('%Y-%m-%d'), '15800.00', '52', '41', '78.8%'],
        [(now - datetime.timedelta(days=2)).strftime('%Y-%m-%d'), '11200.00', '38', '35', '92.1%']
    ]
    
    # Convert to CSV
    csv_buffer = StringIO()
    writer = csv.writer(csv_buffer)
    writer.writerows(report_data)
    
    # Upload to S3 with proper metadata
    report_key = f"reports/daily-report-{now.strftime('%Y%m%d-%H%M%S')}.csv"
    s3.put_object(
        Bucket=bucket_name,
        Key=report_key,
        Body=csv_buffer.getvalue(),
        ContentType='text/csv',
        Metadata={
            'generated_by': 'business-automation-system',
            'report_type': 'daily_summary',
            'generation_timestamp': now.isoformat()
        }
    )
    
    return f"Daily report generated: s3://{bucket_name}/{report_key}"

def process_business_data(bucket_name):
    """Simulate data processing and store results"""
    now = datetime.datetime.now()
    
    # Simulate business data processing
    processed_data = {
        'processing_job_id': f"job-{now.strftime('%Y%m%d-%H%M%S')}",
        'processed_at': now.isoformat(),
        'input_records': 150,
        'processed_records': 148,
        'error_records': 2,
        'success_rate': 98.67,
        'processing_time_seconds': 12.5,
        'data_quality_score': 95.2,
        'categories_processed': ['sales', 'inventory', 'customer_data'],
        'anomalies_detected': 1
    }
    
    # Save processed data to S3
    data_key = f"processed-data/batch-{now.strftime('%Y%m%d-%H%M%S')}.json"
    s3.put_object(
        Bucket=bucket_name,
        Key=data_key,
        Body=json.dumps(processed_data, indent=2),
        ContentType='application/json',
        Metadata={
            'job_type': 'business_data_processing',
            'completion_timestamp': now.isoformat()
        }
    )
    
    return f"Data processing completed: {processed_data['processed_records']} records processed with {processed_data['success_rate']}% success rate"

def send_business_notification(topic_arn):
    """Send business status notification"""
    now = datetime.datetime.now()
    
    # Create comprehensive status message
    status_message = f"""
Business Automation System Status Update

Timestamp: {now.strftime('%Y-%m-%d %H:%M:%S UTC')}
System Status: ✅ Operational
Last Health Check: {now.isoformat()}

Recent Activity Summary:
- Automated tasks are running on schedule
- All system components are healthy
- No critical issues detected

Next Scheduled Tasks:
- Daily report generation
- Hourly data processing
- Weekly business reviews

For detailed information, check the CloudWatch logs and S3 storage buckets.
    """.strip()
    
    # Send detailed notification
    sns.publish(
        TopicArn=topic_arn,
        Message=status_message,
        Subject="📊 Business Automation System - Status Update"
    )
    
    return f"Business status notification sent at {now.isoformat()}"
EOF
    
    # Create deployment package
    zip -r business-task-processor.zip business_task_processor.py
    
    # Get Lambda role ARN
    LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler business_task_processor.lambda_handler \
        --zip-file fileb://business-task-processor.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables="{BUCKET_NAME=${BUCKET_NAME},TOPIC_ARN=${TOPIC_ARN}}" \
        --description "Business task automation processor for EventBridge Scheduler"
    
    # Wait for function to be active
    aws lambda wait function-active --function-name "${LAMBDA_FUNCTION_NAME}"
    
    rm -f business_task_processor.py business-task-processor.zip
    
    echo "LAMBDA_FUNCTION_NAME=\"${LAMBDA_FUNCTION_NAME}\"" >> "${DEPLOYMENT_STATE}"
    log_success "Lambda function created: ${LAMBDA_FUNCTION_NAME}"
}

create_scheduler_role() {
    log_info "Creating IAM role for EventBridge Scheduler..."
    
    # Create trust policy
    cat > scheduler-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "scheduler.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create EventBridge Scheduler role
    aws iam create-role \
        --role-name "${SCHEDULER_ROLE_NAME}" \
        --assume-role-policy-document file://scheduler-trust-policy.json \
        --description "Execution role for EventBridge Scheduler to invoke Lambda functions"
    
    # Create policy for Lambda invocation
    cat > scheduler-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
        }
    ]
}
EOF
    
    # Create and attach the policy
    aws iam create-policy \
        --policy-name "${SCHEDULER_ROLE_NAME}-policy" \
        --policy-document file://scheduler-policy.json \
        --description "Policy for EventBridge Scheduler to invoke business automation Lambda"
    
    aws iam attach-role-policy \
        --role-name "${SCHEDULER_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${SCHEDULER_ROLE_NAME}-policy"
    
    # Wait for role to be available
    sleep 10
    
    rm -f scheduler-trust-policy.json scheduler-policy.json
    
    echo "SCHEDULER_ROLE_NAME=\"${SCHEDULER_ROLE_NAME}\"" >> "${DEPLOYMENT_STATE}"
    log_success "EventBridge Scheduler role created: ${SCHEDULER_ROLE_NAME}"
}

create_eventbridge_schedules() {
    log_info "Creating EventBridge schedules for business automation..."
    
    # Get role ARN for scheduler
    SCHEDULER_ROLE_ARN=$(aws iam get-role \
        --role-name "${SCHEDULER_ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    
    # Create schedule group
    aws scheduler create-schedule-group \
        --name "${SCHEDULE_GROUP_NAME}" \
        --description "Business automation schedules for automated task processing" \
        --tags Key=Environment,Value=Production \
               Key=Department,Value=Operations \
               Key=Application,Value=BusinessAutomation \
               Key=ManagedBy,Value=EventBridgeScheduler
    
    # Define schedule configurations
    declare -A SCHEDULES=(
        ["daily-report-schedule"]="cron(0 9 * * ? *)|report|Daily business report generation at 9 AM"
        ["hourly-data-processing"]="rate(1 hour)|data_processing|Hourly business data processing"
        ["weekly-notification-schedule"]="cron(0 10 ? * MON *)|notification|Weekly business status notifications on Mondays"
    )
    
    SCHEDULE_NAMES=""
    
    # Create each schedule
    for schedule_name in "${!SCHEDULES[@]}"; do
        IFS='|' read -r expression task_type description <<< "${SCHEDULES[$schedule_name]}"
        
        log_info "Creating schedule: ${schedule_name}"
        
        # Determine if timezone is needed (for cron expressions)
        if [[ ${expression} == cron* ]]; then
            timezone_param='--schedule-expression-timezone "America/New_York"'
        else
            timezone_param=""
        fi
        
        # Create the schedule
        eval aws scheduler create-schedule \
            --name "${schedule_name}" \
            --group-name "${SCHEDULE_GROUP_NAME}" \
            --schedule-expression "\"${expression}\"" \
            ${timezone_param} \
            --flexible-time-window Mode=OFF \
            --target "'{
                \"Arn\": \"arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}\",
                \"RoleArn\": \"${SCHEDULER_ROLE_ARN}\",
                \"Input\": \"{\\\"task_type\\\":\\\"${task_type}\\\"}\"
            }'" \
            --description "\"${description}\"" \
            --state ENABLED
        
        SCHEDULE_NAMES="${SCHEDULE_NAMES} ${schedule_name}"
        log_success "Schedule created: ${schedule_name}"
    done
    
    echo "SCHEDULE_NAMES=\"${SCHEDULE_NAMES}\"" >> "${DEPLOYMENT_STATE}"
    echo "SCHEDULE_GROUP_NAME=\"${SCHEDULE_GROUP_NAME}\"" >> "${DEPLOYMENT_STATE}"
    log_success "EventBridge schedules created successfully"
}

test_deployment() {
    log_info "Testing deployment..."
    
    # Test Lambda function with sample events
    log_info "Testing Lambda function with sample events..."
    
    for task_type in "report" "data_processing" "notification"; do
        log_info "Testing ${task_type} task..."
        
        aws lambda invoke \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --payload "{\"task_type\":\"${task_type}\"}" \
            --cli-binary-format raw-in-base64-out \
            "test-response-${task_type}.json"
        
        if jq -e '.statusCode == 200' "test-response-${task_type}.json" > /dev/null; then
            log_success "✅ ${task_type} task test passed"
        else
            log_warning "⚠️  ${task_type} task test had issues - check logs"
        fi
        
        rm -f "test-response-${task_type}.json"
    done
    
    # Verify S3 bucket contents
    log_info "Checking S3 bucket contents..."
    BUCKET_OBJECTS=$(aws s3 ls "s3://${BUCKET_NAME}" --recursive | wc -l)
    log_info "S3 bucket contains ${BUCKET_OBJECTS} objects"
    
    # Verify schedules
    log_info "Verifying EventBridge schedules..."
    SCHEDULE_COUNT=$(aws scheduler list-schedules --group-name "${SCHEDULE_GROUP_NAME}" --query 'length(Schedules)' --output text)
    log_info "Created ${SCHEDULE_COUNT} EventBridge schedules"
    
    log_success "Deployment testing completed"
}

print_deployment_summary() {
    source "${DEPLOYMENT_STATE}"
    
    log_info "=============================================================="
    log_success "🎉 Business Automation System Deployed Successfully!"
    log_info "=============================================================="
    log_info ""
    log_info "📋 Deployment Summary:"
    log_info "  • AWS Region: ${AWS_REGION}"
    log_info "  • S3 Bucket: ${BUCKET_NAME}"
    log_info "  • SNS Topic: ${SNS_TOPIC_NAME}"
    log_info "  • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log_info "  • Schedule Group: ${SCHEDULE_GROUP_NAME}"
    log_info "  • Notification Email: ${NOTIFICATION_EMAIL}"
    log_info ""
    log_info "📅 Active Schedules:"
    log_info "  • Daily Report: Every day at 9:00 AM EST"
    log_info "  • Data Processing: Every hour"
    log_info "  • Status Notifications: Every Monday at 10:00 AM EST"
    log_info ""
    log_info "🔗 Useful Commands:"
    log_info "  • View schedules: aws scheduler list-schedules --group-name ${SCHEDULE_GROUP_NAME}"
    log_info "  • Check Lambda logs: aws logs tail /aws/lambda/${LAMBDA_FUNCTION_NAME} --follow"
    log_info "  • View S3 contents: aws s3 ls s3://${BUCKET_NAME} --recursive"
    log_info "  • Test Lambda: aws lambda invoke --function-name ${LAMBDA_FUNCTION_NAME} --payload '{\"task_type\":\"report\"}' response.json"
    log_info ""
    log_info "💰 Estimated Monthly Cost: \$5-15 (based on typical usage)"
    log_info ""
    log_info "⚠️  Important Notes:"
    log_info "  • Confirm your email subscription to receive notifications"
    log_info "  • Monitor CloudWatch logs for task execution details"
    log_info "  • Use the destroy.sh script to clean up resources when done"
    log_info ""
    log_info "📖 For more information, see the recipe documentation"
    log_info "=============================================================="
}

# Main execution
main() {
    print_banner
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_sns_topic
    create_lambda_role
    create_lambda_function
    create_scheduler_role
    create_eventbridge_schedules
    test_deployment
    print_deployment_summary
    
    log_success "🚀 Deployment completed successfully!"
    log_info "Check your email for SNS subscription confirmation if you provided a valid email address."
}

# Execute main function
main "$@"