#!/bin/bash

# Deploy script for Automated Application Performance Monitoring with CloudWatch Application Signals and EventBridge
# This script implements the infrastructure described in the recipe with proper error handling and logging

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI version 2.0 or higher."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI Version: $AWS_CLI_VERSION"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured or invalid. Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    
    # Check required permissions
    log "Checking AWS permissions..."
    CALLER_IDENTITY=$(aws sts get-caller-identity)
    log "Deploying as: $(echo $CALLER_IDENTITY | jq -r .Arn)"
    
    # Check if required services are available in region
    AWS_REGION_CHECK=$(aws configure get region)
    if [[ -z "$AWS_REGION_CHECK" ]]; then
        error "AWS region is not configured. Please set your default region."
        exit 1
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names
    export MONITORING_STACK_NAME="app-performance-monitoring-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="performance-alerts-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="performance-processor-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_RULE_NAME="performance-anomaly-rule-${RANDOM_SUFFIX}"
    
    # Create state file to track deployment
    STATE_FILE="./deployment-state-${RANDOM_SUFFIX}.json"
    cat > $STATE_FILE << EOF
{
    "deployment_id": "${RANDOM_SUFFIX}",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "monitoring_stack_name": "${MONITORING_STACK_NAME}",
    "sns_topic_name": "${SNS_TOPIC_NAME}",
    "lambda_function_name": "${LAMBDA_FUNCTION_NAME}",
    "eventbridge_rule_name": "${EVENTBRIDGE_RULE_NAME}",
    "created_resources": {},
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log "Environment configured:"
    log "  - AWS Region: ${AWS_REGION}"
    log "  - AWS Account: ${AWS_ACCOUNT_ID}"
    log "  - Deployment ID: ${RANDOM_SUFFIX}"
    log "  - State file: ${STATE_FILE}"
    
    success "Environment setup completed"
}

# Function to create IAM role for Lambda
create_iam_role() {
    log "Creating IAM role for Lambda execution..."
    
    # Create IAM role
    aws iam create-role \
        --role-name ${LAMBDA_FUNCTION_NAME}-role \
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
        }' || warn "IAM role may already exist"
    
    # Wait for role to be created
    sleep 5
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name ${LAMBDA_FUNCTION_NAME}-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Update state file
    jq '.created_resources.iam_role = "'${LAMBDA_FUNCTION_NAME}-role'"' $STATE_FILE > tmp.$$.json && mv tmp.$$.json $STATE_FILE
    
    success "IAM role created: ${LAMBDA_FUNCTION_NAME}-role"
}

# Function to enable Application Signals
enable_application_signals() {
    log "Enabling CloudWatch Application Signals..."
    
    # Create Application Signals log group
    aws logs create-log-group \
        --log-group-name /aws/application-signals/data \
        --retention-in-days 30 2>/dev/null || warn "Log group may already exist"
    
    # Enable Application Signals service
    aws application-signals put-service-level-objective \
        --service-level-objective-name "app-performance-slo-${RANDOM_SUFFIX}" \
        --service-level-objective-configuration '{
            "MetricType": "Latency",
            "ComparisonOperator": "LessThanThreshold",
            "Threshold": 2000,
            "EvaluationPeriods": 2,
            "DatapointsToAlarm": 1
        }' 2>/dev/null || warn "Application Signals may already be enabled"
    
    # Update state file
    jq '.created_resources.application_signals_slo = "app-performance-slo-'${RANDOM_SUFFIX}'"' $STATE_FILE > tmp.$$.json && mv tmp.$$.json $STATE_FILE
    
    success "CloudWatch Application Signals enabled and configured"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic for notifications..."
    
    # Create SNS topic
    aws sns create-topic \
        --name ${SNS_TOPIC_NAME} \
        --attributes '{
            "DisplayName": "Application Performance Alerts",
            "DeliveryPolicy": "{\"http\":{\"defaultHealthyRetryPolicy\":{\"minDelayTarget\":20,\"maxDelayTarget\":20,\"numRetries\":3,\"numMaxDelayRetries\":0,\"numMinDelayRetries\":0,\"numNoDelayRetries\":0,\"backoffFunction\":\"linear\"},\"disableSubscriptionOverrides\":false}}"
        }'
    
    # Get the topic ARN
    export SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME} \
        --query 'Attributes.TopicArn' --output text)
    
    # Update state file
    jq '.created_resources.sns_topic_arn = "'${SNS_TOPIC_ARN}'"' $STATE_FILE > tmp.$$.json && mv tmp.$$.json $STATE_FILE
    
    log "SNS topic created: ${SNS_TOPIC_ARN}"
    warn "Remember to manually subscribe email endpoints using: aws sns subscribe --topic-arn ${SNS_TOPIC_ARN} --protocol email --notification-endpoint your-email@example.com"
    
    success "SNS topic created successfully"
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function for event processing..."
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import logging
from datetime import datetime
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process CloudWatch alarm state changes and trigger appropriate actions
    """
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        alarm_name = detail.get('alarmName', '')
        new_state = detail.get('newState', {})
        state_value = new_state.get('value', '')
        state_reason = new_state.get('reason', '')
        
        logger.info(f"Processing alarm: {alarm_name}, State: {state_value}")
        
        # Initialize AWS clients
        sns_client = boto3.client('sns')
        cloudwatch_client = boto3.client('cloudwatch')
        
        # Get SNS topic ARN from environment
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        
        # Define response actions based on alarm state
        if state_value == 'ALARM':
            # Send immediate notification
            message = f"""
🚨 PERFORMANCE ALERT 🚨

Alarm: {alarm_name}
State: {state_value}
Reason: {state_reason}
Time: {datetime.now().isoformat()}

Automatic scaling has been triggered.
Monitor dashboard for real-time updates.
            """
            
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=message,
                Subject=f"Performance Alert: {alarm_name}"
            )
            
            logger.info("Sent alarm notification and triggered scaling response")
            
        elif state_value == 'OK':
            # Send resolution notification
            message = f"""
✅ ALERT RESOLVED ✅

Alarm: {alarm_name}
State: {state_value}
Time: {datetime.now().isoformat()}

Performance metrics have returned to normal.
            """
            
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=message,
                Subject=f"Alert Resolved: {alarm_name}"
            )
            
            logger.info("Sent resolution notification")
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Successfully processed alarm: {alarm_name}')
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        raise e
EOF
    
    # Create deployment package
    zip lambda_function.zip lambda_function.py
    
    # Create Lambda function
    aws lambda create-function \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --runtime python3.9 \
        --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_FUNCTION_NAME}-role \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda_function.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables='{
            "SNS_TOPIC_ARN": "'${SNS_TOPIC_ARN}'"
        }'
    
    # Clean up deployment package
    rm -f lambda_function.zip lambda_function.py
    
    # Update state file
    jq '.created_resources.lambda_function = "'${LAMBDA_FUNCTION_NAME}'"' $STATE_FILE > tmp.$$.json && mv tmp.$$.json $STATE_FILE
    
    success "Lambda function created: ${LAMBDA_FUNCTION_NAME}"
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms for Application Signals..."
    
    # Create alarm for application latency
    aws cloudwatch put-metric-alarm \
        --alarm-name "AppSignals-HighLatency-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor application latency from Application Signals" \
        --metric-name "Latency" \
        --namespace "AWS/ApplicationSignals" \
        --statistic Average \
        --period 300 \
        --threshold 2000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME} \
        --ok-actions arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME} \
        --dimensions Name=Service,Value=MyApplication
    
    # Create alarm for error rate
    aws cloudwatch put-metric-alarm \
        --alarm-name "AppSignals-HighErrorRate-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor application error rate from Application Signals" \
        --metric-name "ErrorRate" \
        --namespace "AWS/ApplicationSignals" \
        --statistic Average \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME} \
        --ok-actions arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME} \
        --dimensions Name=Service,Value=MyApplication
    
    # Create alarm for throughput anomaly
    aws cloudwatch put-metric-alarm \
        --alarm-name "AppSignals-LowThroughput-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor application throughput from Application Signals" \
        --metric-name "CallCount" \
        --namespace "AWS/ApplicationSignals" \
        --statistic Sum \
        --period 300 \
        --threshold 10 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 3 \
        --alarm-actions arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME} \
        --ok-actions arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME} \
        --dimensions Name=Service,Value=MyApplication
    
    # Update state file
    jq '.created_resources.cloudwatch_alarms = ["AppSignals-HighLatency-'${RANDOM_SUFFIX}'", "AppSignals-HighErrorRate-'${RANDOM_SUFFIX}'", "AppSignals-LowThroughput-'${RANDOM_SUFFIX}'"]' $STATE_FILE > tmp.$$.json && mv tmp.$$.json $STATE_FILE
    
    success "CloudWatch alarms created for Application Signals metrics"
}

# Function to create EventBridge rule
create_eventbridge_rule() {
    log "Creating EventBridge rule for alarm processing..."
    
    # Create EventBridge rule
    aws events put-rule \
        --name ${EVENTBRIDGE_RULE_NAME} \
        --description "Route CloudWatch alarm state changes to Lambda processor" \
        --event-pattern '{
            "source": ["aws.cloudwatch"],
            "detail-type": ["CloudWatch Alarm State Change"],
            "detail": {
                "state": {
                    "value": ["ALARM", "OK"]
                }
            }
        }' \
        --state ENABLED
    
    # Add Lambda function as target
    aws events put-targets \
        --rule ${EVENTBRIDGE_RULE_NAME} \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
    
    # Add permission for EventBridge to invoke Lambda
    aws lambda add-permission \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --statement-id allow-eventbridge-invoke \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}
    
    # Update state file
    jq '.created_resources.eventbridge_rule = "'${EVENTBRIDGE_RULE_NAME}'"' $STATE_FILE > tmp.$$.json && mv tmp.$$.json $STATE_FILE
    
    success "EventBridge rule created: ${EVENTBRIDGE_RULE_NAME}"
}

# Function to create CloudWatch dashboard
create_dashboard() {
    log "Creating CloudWatch dashboard for monitoring..."
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "ApplicationPerformanceMonitoring-${RANDOM_SUFFIX}" \
        --dashboard-body '{
            "widgets": [
                {
                    "type": "metric",
                    "x": 0,
                    "y": 0,
                    "width": 12,
                    "height": 6,
                    "properties": {
                        "metrics": [
                            ["AWS/ApplicationSignals", "Latency", "Service", "MyApplication"],
                            [".", "ErrorRate", ".", "."],
                            [".", "CallCount", ".", "."]
                        ],
                        "view": "timeSeries",
                        "stacked": false,
                        "region": "'${AWS_REGION}'",
                        "title": "Application Performance Metrics",
                        "period": 300,
                        "stat": "Average",
                        "yAxis": {
                            "left": {
                                "min": 0
                            }
                        }
                    }
                },
                {
                    "type": "metric",
                    "x": 12,
                    "y": 0,
                    "width": 12,
                    "height": 6,
                    "properties": {
                        "metrics": [
                            ["AWS/Events", "InvocationsCount", "RuleName", "'${EVENTBRIDGE_RULE_NAME}'"],
                            ["AWS/Lambda", "Invocations", "FunctionName", "'${LAMBDA_FUNCTION_NAME}'"]
                        ],
                        "view": "timeSeries",
                        "stacked": false,
                        "region": "'${AWS_REGION}'",
                        "title": "Event Processing Metrics",
                        "period": 300,
                        "stat": "Sum"
                    }
                }
            ]
        }'
    
    # Update state file
    jq '.created_resources.dashboard = "ApplicationPerformanceMonitoring-'${RANDOM_SUFFIX}'"' $STATE_FILE > tmp.$$.json && mv tmp.$$.json $STATE_FILE
    
    success "CloudWatch dashboard created for performance monitoring"
}

# Function to create additional IAM permissions
create_iam_permissions() {
    log "Configuring additional IAM permissions..."
    
    # Create additional IAM policy for Lambda function
    aws iam create-policy \
        --policy-name ${LAMBDA_FUNCTION_NAME}-policy \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "sns:Publish",
                        "cloudwatch:DescribeAlarms",
                        "cloudwatch:GetMetricStatistics",
                        "autoscaling:DescribeAutoScalingGroups",
                        "autoscaling:UpdateAutoScalingGroup"
                    ],
                    "Resource": "*"
                }
            ]
        }'
    
    # Attach policy to Lambda role
    aws iam attach-role-policy \
        --role-name ${LAMBDA_FUNCTION_NAME}-role \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_FUNCTION_NAME}-policy
    
    # Update state file
    jq '.created_resources.iam_policy = "'${LAMBDA_FUNCTION_NAME}-policy'"' $STATE_FILE > tmp.$$.json && mv tmp.$$.json $STATE_FILE
    
    success "IAM permissions configured for automated monitoring system"
}

# Function to test the monitoring system
test_monitoring_system() {
    log "Testing the monitoring system..."
    
    # Test alarm state by manually setting alarm state
    aws cloudwatch set-alarm-state \
        --alarm-name "AppSignals-HighLatency-${RANDOM_SUFFIX}" \
        --state-value ALARM \
        --state-reason "Manual test of monitoring system"
    
    log "Waiting for processing to complete..."
    sleep 15
    
    # Reset alarm state to OK
    aws cloudwatch set-alarm-state \
        --alarm-name "AppSignals-HighLatency-${RANDOM_SUFFIX}" \
        --state-value OK \
        --state-reason "Manual test completion"
    
    success "Monitoring system tested successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    log "==================="
    log "AWS Region: ${AWS_REGION}"
    log "AWS Account: ${AWS_ACCOUNT_ID}"
    log "Deployment ID: ${RANDOM_SUFFIX}"
    log ""
    log "Created Resources:"
    log "- IAM Role: ${LAMBDA_FUNCTION_NAME}-role"
    log "- SNS Topic: ${SNS_TOPIC_ARN}"
    log "- Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log "- EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    log "- CloudWatch Dashboard: ApplicationPerformanceMonitoring-${RANDOM_SUFFIX}"
    log "- CloudWatch Alarms: AppSignals-HighLatency-${RANDOM_SUFFIX}, AppSignals-HighErrorRate-${RANDOM_SUFFIX}, AppSignals-LowThroughput-${RANDOM_SUFFIX}"
    log ""
    log "Next Steps:"
    log "1. Subscribe to SNS notifications: aws sns subscribe --topic-arn ${SNS_TOPIC_ARN} --protocol email --notification-endpoint your-email@example.com"
    log "2. View dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=ApplicationPerformanceMonitoring-${RANDOM_SUFFIX}"
    log "3. Monitor Application Signals: https://${AWS_REGION}.console.aws.amazon.com/systems-manager/appinsights"
    log ""
    log "State file created: ${STATE_FILE}"
    log "Use this file with destroy.sh to clean up resources"
}

# Main deployment function
main() {
    log "Starting deployment of Automated Application Performance Monitoring"
    log "=================================================================="
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_iam_role
    enable_application_signals
    create_sns_topic
    create_lambda_function
    create_cloudwatch_alarms
    create_eventbridge_rule
    create_dashboard
    create_iam_permissions
    test_monitoring_system
    
    display_summary
    
    success "Deployment completed successfully! 🎉"
}

# Handle script interruption
cleanup_on_error() {
    error "Script interrupted. Some resources may have been created."
    if [[ -f "$STATE_FILE" ]]; then
        warn "Use the destroy.sh script with state file $STATE_FILE to clean up partial deployment"
    fi
    exit 1
}

trap cleanup_on_error INT

# Check if running in dry-run mode
if [[ "${1:-}" == "--dry-run" ]]; then
    log "DRY RUN MODE - No resources will be created"
    log "This would deploy the automated application performance monitoring solution"
    exit 0
fi

# Run main deployment
main "$@"