#!/bin/bash

# AWS Basic Log Monitoring with CloudWatch Logs and SNS - Deployment Script
# This script deploys a complete log monitoring solution with error detection and alerting

set -euo pipefail

# Configuration and Constants
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/tmp/basic-log-monitoring-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly LAMBDA_CODE_FILE="/tmp/log-processor.py"
readonly LAMBDA_ZIP_FILE="/tmp/log-processor.zip"

# Default values
LOG_GROUP_NAME="/aws/application/monitoring-demo"
METRIC_FILTER_NAME="error-count-filter"
ALARM_NAME="application-errors-alarm"
LAMBDA_FUNCTION_NAME=""
SNS_TOPIC_NAME=""
NOTIFICATION_EMAIL=""
ERROR_THRESHOLD=2
ALARM_PERIOD=300
LOG_RETENTION_DAYS=7

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR] $*${NC}" | tee -a "$LOG_FILE" >&2
}

warn() {
    echo -e "${YELLOW}[WARN] $*${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO] $*${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS] $*${NC}" | tee -a "$LOG_FILE"
}

# Usage function
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Deploy AWS Basic Log Monitoring with CloudWatch Logs and SNS

OPTIONS:
    -e, --email EMAIL           Email address for notifications (required)
    -g, --log-group NAME        CloudWatch log group name (default: $LOG_GROUP_NAME)
    -f, --filter-name NAME      Metric filter name (default: $METRIC_FILTER_NAME)
    -a, --alarm-name NAME       CloudWatch alarm name (default: $ALARM_NAME)
    -t, --threshold NUM         Error threshold for alarm (default: $ERROR_THRESHOLD)
    -p, --period SECONDS        Alarm evaluation period (default: $ALARM_PERIOD)
    -r, --retention DAYS        Log retention in days (default: $LOG_RETENTION_DAYS)
    -h, --help                  Show this help message
    -v, --verbose               Enable verbose logging
    --dry-run                   Show what would be deployed without making changes

EXAMPLES:
    $SCRIPT_NAME --email user@example.com
    $SCRIPT_NAME --email user@example.com --threshold 5 --period 600
    $SCRIPT_NAME --dry-run --email user@example.com

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--email)
                NOTIFICATION_EMAIL="$2"
                shift 2
                ;;
            -g|--log-group)
                LOG_GROUP_NAME="$2"
                shift 2
                ;;
            -f|--filter-name)
                METRIC_FILTER_NAME="$2"
                shift 2
                ;;
            -a|--alarm-name)
                ALARM_NAME="$2"
                shift 2
                ;;
            -t|--threshold)
                ERROR_THRESHOLD="$2"
                shift 2
                ;;
            -p|--period)
                ALARM_PERIOD="$2"
                shift 2
                ;;
            -r|--retention)
                LOG_RETENTION_DAYS="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$NOTIFICATION_EMAIL" ]]; then
        error "Email address is required. Use --email or -e option."
        usage
        exit 1
    fi

    # Validate email format
    if [[ ! "$NOTIFICATION_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        error "Invalid email format: $NOTIFICATION_EMAIL"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."

    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi

    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' or set up credentials."
        exit 1
    fi

    # Check required permissions (basic check)
    local test_commands=(
        "aws logs describe-log-groups --limit 1"
        "aws sns list-topics --max-items 1"
        "aws cloudwatch describe-alarms --max-records 1"
        "aws lambda list-functions --max-items 1"
        "aws iam list-roles --max-items 1"
    )

    for cmd in "${test_commands[@]}"; do
        if ! eval "$cmd" &> /dev/null; then
            error "Insufficient permissions to run: $cmd"
            exit 1
        fi
    done

    success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    info "Setting up environment variables..."

    # Get AWS region and account ID
    export AWS_REGION
    AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION="us-east-1"
        warn "No default region configured, using us-east-1"
    fi

    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")

    SNS_TOPIC_NAME="log-monitoring-alerts-${random_suffix}"
    LAMBDA_FUNCTION_NAME="log-processor-${random_suffix}"

    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "SNS Topic: $SNS_TOPIC_NAME"
    info "Lambda Function: $LAMBDA_FUNCTION_NAME"
}

# Create Lambda function code
create_lambda_code() {
    info "Creating Lambda function code..."

    cat > "$LAMBDA_CODE_FILE" << 'EOF'
import json
import boto3
import logging
from datetime import datetime
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process CloudWatch alarm notifications and enrich alert data
    """
    
    try:
        # Parse SNS message
        for record in event['Records']:
            sns_message = json.loads(record['Sns']['Message'])
            
            # Extract alarm details
            alarm_name = sns_message.get('AlarmName', 'Unknown')
            alarm_reason = sns_message.get('NewStateReason', 'No reason provided')
            alarm_state = sns_message.get('NewStateValue', 'Unknown')
            timestamp = sns_message.get('StateChangeTime', datetime.now().isoformat())
            region = sns_message.get('Region', 'Unknown')
            
            # Log processing details
            logger.info(f"Processing alarm: {alarm_name}")
            logger.info(f"State: {alarm_state}")
            logger.info(f"Reason: {alarm_reason}")
            logger.info(f"Timestamp: {timestamp}")
            logger.info(f"Region: {region}")
            
            # Additional context logging
            if alarm_state == 'ALARM':
                logger.warning(f"CRITICAL: Alarm {alarm_name} is in ALARM state")
                # Here you could add additional logic:
                # - Query CloudWatch Logs for error context
                # - Send notifications to external systems
                # - Trigger automated remediation
                # - Create support tickets
                
            elif alarm_state == 'OK':
                logger.info(f"RESOLVED: Alarm {alarm_name} returned to OK state")
                
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Log processing completed successfully',
                'processedRecords': len(event['Records'])
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing log event: {str(e)}")
        logger.error(f"Event: {json.dumps(event)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process log event'
            })
        }
EOF

    # Create deployment package
    cd /tmp
    if [[ -f "$LAMBDA_ZIP_FILE" ]]; then
        rm "$LAMBDA_ZIP_FILE"
    fi
    zip -q "$LAMBDA_ZIP_FILE" "$(basename "$LAMBDA_CODE_FILE")"
    cd - > /dev/null

    success "Lambda function code created"
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "$resource_type" in
        "log-group")
            aws logs describe-log-groups --log-group-name-prefix "$resource_name" \
                --query 'logGroups[?logGroupName==`'"$resource_name"'`]' --output text | grep -q .
            ;;
        "sns-topic")
            aws sns get-topic-attributes --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${resource_name}" &> /dev/null
            ;;
        "lambda-function")
            aws lambda get-function --function-name "$resource_name" &> /dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" &> /dev/null
            ;;
        "metric-filter")
            aws logs describe-metric-filters --log-group-name "$LOG_GROUP_NAME" \
                --filter-name-prefix "$resource_name" --query 'metricFilters[0]' --output text | grep -q .
            ;;
        "alarm")
            aws cloudwatch describe-alarms --alarm-names "$resource_name" \
                --query 'MetricAlarms[0]' --output text | grep -q .
            ;;
        *)
            return 1
            ;;
    esac
}

# Deploy CloudWatch Log Group
deploy_log_group() {
    info "Deploying CloudWatch Log Group: $LOG_GROUP_NAME"

    if resource_exists "log-group" "$LOG_GROUP_NAME"; then
        warn "Log group $LOG_GROUP_NAME already exists, skipping creation"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would create log group: $LOG_GROUP_NAME"
        return 0
    fi

    aws logs create-log-group \
        --log-group-name "$LOG_GROUP_NAME" \
        --retention-in-days "$LOG_RETENTION_DAYS"

    # Verify creation
    if resource_exists "log-group" "$LOG_GROUP_NAME"; then
        success "Log group created: $LOG_GROUP_NAME"
    else
        error "Failed to create log group: $LOG_GROUP_NAME"
        return 1
    fi
}

# Deploy SNS Topic
deploy_sns_topic() {
    info "Deploying SNS Topic: $SNS_TOPIC_NAME"

    if resource_exists "sns-topic" "$SNS_TOPIC_NAME"; then
        warn "SNS topic $SNS_TOPIC_NAME already exists, skipping creation"
        export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would create SNS topic: $SNS_TOPIC_NAME"
        return 0
    fi

    aws sns create-topic --name "$SNS_TOPIC_NAME" > /dev/null

    # Get topic ARN
    export SNS_TOPIC_ARN
    SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
        --query 'Attributes.TopicArn' --output text)

    # Subscribe email to topic
    aws sns subscribe \
        --topic-arn "$SNS_TOPIC_ARN" \
        --protocol email \
        --notification-endpoint "$NOTIFICATION_EMAIL" > /dev/null

    success "SNS topic created: $SNS_TOPIC_NAME"
    success "Email subscription added for: $NOTIFICATION_EMAIL"
    warn "Please check your email and confirm the subscription"
}

# Deploy Lambda IAM Role
deploy_lambda_role() {
    local role_name="lambda-log-processor-role"
    
    info "Deploying Lambda IAM Role: $role_name"

    if resource_exists "iam-role" "$role_name"; then
        warn "IAM role $role_name already exists, skipping creation"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would create IAM role: $role_name"
        return 0
    fi

    # Create IAM role for Lambda function
    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document '{
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
        }' > /dev/null

    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    # Wait for role to be available
    info "Waiting for IAM role to be available..."
    sleep 15

    success "Lambda IAM role created: $role_name"
}

# Deploy Lambda Function
deploy_lambda_function() {
    info "Deploying Lambda Function: $LAMBDA_FUNCTION_NAME"

    if resource_exists "lambda-function" "$LAMBDA_FUNCTION_NAME"; then
        warn "Lambda function $LAMBDA_FUNCTION_NAME already exists, updating code"
        
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            info "[DRY RUN] Would update Lambda function: $LAMBDA_FUNCTION_NAME"
            return 0
        fi

        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --zip-file fileb://"$LAMBDA_ZIP_FILE" > /dev/null
        
        success "Lambda function code updated: $LAMBDA_FUNCTION_NAME"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would create Lambda function: $LAMBDA_FUNCTION_NAME"
        return 0
    fi

    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda-log-processor-role" \
        --handler log-processor.lambda_handler \
        --zip-file fileb://"$LAMBDA_ZIP_FILE" \
        --timeout 60 \
        --memory-size 256 \
        --description "Process CloudWatch alarm notifications for log monitoring" > /dev/null

    success "Lambda function created: $LAMBDA_FUNCTION_NAME"
}

# Deploy Metric Filter
deploy_metric_filter() {
    info "Deploying Metric Filter: $METRIC_FILTER_NAME"

    if resource_exists "metric-filter" "$METRIC_FILTER_NAME"; then
        warn "Metric filter $METRIC_FILTER_NAME already exists, skipping creation"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would create metric filter: $METRIC_FILTER_NAME"
        return 0
    fi

    # Create metric filter for error detection
    aws logs put-metric-filter \
        --log-group-name "$LOG_GROUP_NAME" \
        --filter-name "$METRIC_FILTER_NAME" \
        --filter-pattern '{ ($.level = "ERROR") || ($.message = "*ERROR*") || ($.message = "*FAILED*") || ($.message = "*EXCEPTION*") || ($.message = "*TIMEOUT*") }' \
        --metric-transformations \
            metricName=ApplicationErrors,\
            metricNamespace=CustomApp/Monitoring,\
            metricValue=1,\
            defaultValue=0

    success "Metric filter created: $METRIC_FILTER_NAME"
}

# Deploy CloudWatch Alarm
deploy_alarm() {
    info "Deploying CloudWatch Alarm: $ALARM_NAME"

    if resource_exists "alarm" "$ALARM_NAME"; then
        warn "CloudWatch alarm $ALARM_NAME already exists, skipping creation"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would create CloudWatch alarm: $ALARM_NAME"
        return 0
    fi

    # Create CloudWatch alarm for error threshold
    aws cloudwatch put-metric-alarm \
        --alarm-name "$ALARM_NAME" \
        --alarm-description "Alert when application errors exceed threshold of $ERROR_THRESHOLD" \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --ok-actions "$SNS_TOPIC_ARN" \
        --metric-name ApplicationErrors \
        --namespace CustomApp/Monitoring \
        --statistic Sum \
        --period "$ALARM_PERIOD" \
        --threshold "$ERROR_THRESHOLD" \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --datapoints-to-alarm 1 \
        --treat-missing-data notBreaching

    success "CloudWatch alarm created: $ALARM_NAME"
}

# Configure SNS Lambda Subscription
configure_sns_lambda_subscription() {
    info "Configuring SNS Lambda subscription"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would configure SNS Lambda subscription"
        return 0
    fi

    # Subscribe Lambda function to SNS topic
    aws sns subscribe \
        --topic-arn "$SNS_TOPIC_ARN" \
        --protocol lambda \
        --notification-endpoint "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}" > /dev/null

    # Grant SNS permission to invoke Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id sns-trigger \
        --action lambda:InvokeFunction \
        --principal sns.amazonaws.com \
        --source-arn "$SNS_TOPIC_ARN" 2>/dev/null || true

    success "Lambda function subscribed to SNS topic"
}

# Generate test log events
generate_test_events() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would generate test log events"
        return 0
    fi

    info "Generating test log events..."

    # Create log stream
    local log_stream_name="test-stream-$(date +%Y%m%d%H%M%S)"
    
    aws logs create-log-stream \
        --log-group-name "$LOG_GROUP_NAME" \
        --log-stream-name "$log_stream_name"

    # Send test error events
    for i in {1..3}; do
        aws logs put-log-events \
            --log-group-name "$LOG_GROUP_NAME" \
            --log-stream-name "$log_stream_name" \
            --log-events \
                timestamp="$(date +%s)000",message="ERROR: Database connection failed - test event $i"
        
        info "Sent test error event $i"
        sleep 2
    done

    success "Test log events sent. Monitor should trigger within 5-10 minutes."
}

# Cleanup temporary files
cleanup_temp_files() {
    info "Cleaning up temporary files..."
    
    [[ -f "$LAMBDA_CODE_FILE" ]] && rm -f "$LAMBDA_CODE_FILE"
    [[ -f "$LAMBDA_ZIP_FILE" ]] && rm -f "$LAMBDA_ZIP_FILE"
    
    success "Temporary files cleaned up"
}

# Print deployment summary
print_summary() {
    echo
    success "=== DEPLOYMENT SUMMARY ==="
    echo "Log Group: $LOG_GROUP_NAME"
    echo "SNS Topic: $SNS_TOPIC_NAME"
    echo "Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "Metric Filter: $METRIC_FILTER_NAME"
    echo "CloudWatch Alarm: $ALARM_NAME"
    echo "Notification Email: $NOTIFICATION_EMAIL"
    echo "Error Threshold: $ERROR_THRESHOLD errors in ${ALARM_PERIOD}s"
    echo "Log File: $LOG_FILE"
    echo
    info "Next Steps:"
    echo "1. Confirm your email subscription in your inbox"
    echo "2. Test the monitoring by sending error logs to: $LOG_GROUP_NAME"
    echo "3. Monitor CloudWatch metrics in namespace: CustomApp/Monitoring"
    echo "4. Check Lambda function logs in: /aws/lambda/$LAMBDA_FUNCTION_NAME"
    echo
}

# Main deployment function
main() {
    log "Starting AWS Basic Log Monitoring deployment"
    
    parse_args "$@"
    check_prerequisites
    setup_environment
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY RUN MODE - No resources will be created"
    fi
    
    create_lambda_code
    deploy_log_group
    deploy_sns_topic
    deploy_lambda_role
    deploy_lambda_function
    deploy_metric_filter
    deploy_alarm
    configure_sns_lambda_subscription
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        generate_test_events
    fi
    
    cleanup_temp_files
    print_summary
    
    success "Deployment completed successfully!"
}

# Error handler
error_handler() {
    local line_number=$1
    error "Script failed at line $line_number"
    cleanup_temp_files
    exit 1
}

# Set up error handling
trap 'error_handler ${LINENO}' ERR

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi