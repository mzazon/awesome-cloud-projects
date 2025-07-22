#!/bin/bash

# =============================================================================
# AWS Cost Anomaly Detection Deployment Script
# =============================================================================
# This script deploys the complete cost anomaly detection infrastructure
# including Lambda functions, SNS topics, IAM roles, and Cost Anomaly Detection
# monitors and detectors.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for all services
# - At least 24 hours of AWS usage history
#
# Usage: ./deploy.sh [options]
# Options:
#   --email EMAIL     Email address for cost anomaly notifications
#   --dry-run         Show what would be deployed without making changes
#   --debug           Enable debug logging
#   --help            Show this help message
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false
DEBUG=false
EMAIL_ADDRESS=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

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

log_debug() {
    if [[ "${DEBUG}" == "true" ]]; then
        log "${BLUE}[DEBUG]${NC} $1"
    fi
}

show_help() {
    cat << EOF
AWS Cost Anomaly Detection Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --email EMAIL     Email address for cost anomaly notifications (required)
    --dry-run         Show what would be deployed without making changes
    --debug           Enable debug logging
    --help            Show this help message

EXAMPLES:
    $0 --email admin@company.com
    $0 --email admin@company.com --dry-run
    $0 --email admin@company.com --debug

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Appropriate IAM permissions for Cost Explorer, Lambda, SNS, EventBridge
    - At least 24 hours of AWS usage history for anomaly detection training

EOF
}

cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of partially created resources..."
    
    # Store current set options and disable exit on error for cleanup
    set +e
    
    # Clean up resources in reverse order
    if [[ -n "${DETECTOR_ARN:-}" ]]; then
        log_info "Cleaning up anomaly detector..."
        aws ce delete-anomaly-detector --detector-arn "${DETECTOR_ARN}" 2>/dev/null || true
    fi
    
    if [[ -n "${MONITOR_ARN:-}" ]]; then
        log_info "Cleaning up anomaly monitor..."
        aws ce delete-anomaly-monitor --monitor-arn "${MONITOR_ARN}" 2>/dev/null || true
    fi
    
    if [[ -n "${RULE_NAME:-}" ]]; then
        log_info "Cleaning up EventBridge rule..."
        aws events remove-targets --rule "${RULE_NAME}" --ids "1" 2>/dev/null || true
        aws events delete-rule --name "${RULE_NAME}" 2>/dev/null || true
    fi
    
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log_info "Cleaning up Lambda function..."
        aws lambda delete-function --function-name "${FUNCTION_NAME}" 2>/dev/null || true
    fi
    
    if [[ -n "${ROLE_NAME:-}" ]]; then
        log_info "Cleaning up IAM role and policies..."
        aws iam detach-role-policy --role-name "${ROLE_NAME}" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
        aws iam detach-role-policy --role-name "${ROLE_NAME}" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CostAnomalyPolicy-${RANDOM_SUFFIX}" 2>/dev/null || true
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CostAnomalyPolicy-${RANDOM_SUFFIX}" 2>/dev/null || true
        aws iam delete-role --role-name "${ROLE_NAME}" 2>/dev/null || true
    fi
    
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        log_info "Cleaning up SNS topic..."
        aws sns delete-topic --topic-arn "${SNS_TOPIC_ARN}" 2>/dev/null || true
    fi
    
    if [[ -n "${DASHBOARD_NAME:-}" ]]; then
        log_info "Cleaning up CloudWatch dashboard..."
        aws cloudwatch delete-dashboards --dashboard-names "${DASHBOARD_NAME}" 2>/dev/null || true
    fi
    
    # Clean up temporary files
    rm -f "${SCRIPT_DIR}/lambda-trust-policy.json" \
          "${SCRIPT_DIR}/cost-anomaly-policy.json" \
          "${SCRIPT_DIR}/lambda_function.py" \
          "${SCRIPT_DIR}/lambda-deployment.zip" \
          "${SCRIPT_DIR}/dashboard-config.json" 2>/dev/null || true
    
    log_error "Cleanup completed. Please check AWS console for any remaining resources."
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_debug "AWS CLI version: ${aws_version}"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions
    log_info "Verifying AWS permissions..."
    
    # Test Cost Explorer access
    if ! aws ce get-rightsizing-recommendation \
        --service "AmazonEC2" \
        --configuration "CrossInstanceFamily=INCLUDE,BuyingOption=ON_DEMAND" \
        --page-size 1 &> /dev/null; then
        log_warning "Cost Explorer access verification failed. This is normal for new accounts."
    fi
    
    # Test IAM permissions
    if ! aws iam get-user &> /dev/null && ! aws iam get-role --role-name NonExistentRole &> /dev/null; then
        log_error "Insufficient IAM permissions. Please ensure you have administrative access."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# =============================================================================
# Environment Setup
# =============================================================================

setup_environment() {
    log_info "Setting up environment..."
    
    # Initialize log file
    echo "=== AWS Cost Anomaly Detection Deployment Log ===" > "${LOG_FILE}"
    echo "Started at: $(date)" >> "${LOG_FILE}"
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    if [[ -z "${AWS_REGION}" ]]; then
        log_error "AWS region not configured. Please run 'aws configure' to set your default region."
        exit 1
    fi
    
    log_debug "AWS Region: ${AWS_REGION}"
    log_debug "AWS Account ID: ${AWS_ACCOUNT_ID}"
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    log_debug "Random suffix: ${RANDOM_SUFFIX}"
    
    # Set resource names
    export MONITOR_NAME="cost-anomaly-monitor-${RANDOM_SUFFIX}"
    export DETECTOR_NAME="cost-anomaly-detector-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="cost-anomaly-processor-${RANDOM_SUFFIX}"
    export SNS_TOPIC="cost-anomaly-alerts-${RANDOM_SUFFIX}"
    export ROLE_NAME="CostAnomalyLambdaRole-${RANDOM_SUFFIX}"
    export RULE_NAME="cost-anomaly-rule-${RANDOM_SUFFIX}"
    export DASHBOARD_NAME="CostAnomalyDetection-${RANDOM_SUFFIX}"
    
    log_success "Environment setup completed"
}

# =============================================================================
# Resource Creation Functions
# =============================================================================

create_sns_topic() {
    log_info "Creating SNS topic for cost anomaly notifications..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create SNS topic: ${SNS_TOPIC}"
        export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC}"
        return 0
    fi
    
    # Create SNS topic
    aws sns create-topic \
        --name "${SNS_TOPIC}" \
        --attributes "DisplayName=Cost Anomaly Alerts" \
        --tags "Key=Purpose,Value=CostAnomalyDetection" \
              "Key=CreatedBy,Value=CostAnomalyScript"
    
    # Store SNS topic ARN
    export SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC}" \
        --query "Attributes.TopicArn" --output text)
    
    log_success "SNS topic created: ${SNS_TOPIC_ARN}"
}

subscribe_email_to_sns() {
    log_info "Subscribing email address to SNS topic..."
    
    if [[ -z "${EMAIL_ADDRESS}" ]]; then
        log_error "Email address is required. Use --email option."
        exit 1
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would subscribe ${EMAIL_ADDRESS} to SNS topic"
        return 0
    fi
    
    # Subscribe email to SNS topic
    aws sns subscribe \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --protocol email \
        --notification-endpoint "${EMAIL_ADDRESS}"
    
    log_success "Email subscription created for: ${EMAIL_ADDRESS}"
    log_warning "Please check your email and confirm the subscription before proceeding"
    
    if [[ "${DEBUG}" != "true" ]]; then
        read -p "Press Enter after confirming email subscription..." -r
    fi
}

create_iam_role() {
    log_info "Creating IAM role for Lambda function..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create IAM role: ${ROLE_NAME}"
        export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
        return 0
    fi
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/lambda-trust-policy.json" << EOF
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
        --assume-role-policy-document "file://${SCRIPT_DIR}/lambda-trust-policy.json" \
        --description "Role for Cost Anomaly Lambda Function" \
        --tags "Key=Purpose,Value=CostAnomalyDetection" \
              "Key=CreatedBy,Value=CostAnomalyScript"
    
    # Store role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "${ROLE_NAME}" \
        --query "Role.Arn" --output text)
    
    log_success "IAM role created: ${LAMBDA_ROLE_ARN}"
}

attach_iam_policies() {
    log_info "Attaching policies to Lambda role..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would attach policies to IAM role"
        return 0
    fi
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Create custom policy for cost operations
    cat > "${SCRIPT_DIR}/cost-anomaly-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ce:GetCostAndUsage",
                "ce:GetUsageReport",
                "ce:GetDimensionValues",
                "ce:GetReservationCoverage",
                "ce:GetReservationPurchaseRecommendation",
                "ce:GetReservationUtilization"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData",
                "cloudwatch:GetMetricStatistics"
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
    
    # Create and attach custom policy
    aws iam create-policy \
        --policy-name "CostAnomalyPolicy-${RANDOM_SUFFIX}" \
        --policy-document "file://${SCRIPT_DIR}/cost-anomaly-policy.json" \
        --description "Policy for Cost Anomaly Detection Lambda function" \
        --tags "Key=Purpose,Value=CostAnomalyDetection" \
              "Key=CreatedBy,Value=CostAnomalyScript"
    
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CostAnomalyPolicy-${RANDOM_SUFFIX}"
    
    log_success "Policies attached to Lambda role"
    
    # Wait for IAM consistency
    log_info "Waiting for IAM role propagation..."
    sleep 10
}

create_lambda_function() {
    log_info "Creating Lambda function for cost anomaly processing..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Lambda function: ${FUNCTION_NAME}"
        return 0
    fi
    
    # Create Lambda function code
    cat > "${SCRIPT_DIR}/lambda_function.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal

def lambda_handler(event, context):
    """
    Process Cost Anomaly Detection events with enhanced analysis
    """
    print(f"Received event: {json.dumps(event, indent=2)}")
    
    # Initialize AWS clients
    ce_client = boto3.client('ce')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    try:
        # Extract anomaly details from EventBridge event
        detail = event['detail']
        anomaly_id = detail['anomalyId']
        total_impact = detail['impact']['totalImpact']
        account_name = detail['accountName']
        dimension_value = detail.get('dimensionValue', 'N/A')
        
        # Calculate percentage impact
        total_actual = detail['impact']['totalActualSpend']
        total_expected = detail['impact']['totalExpectedSpend']
        impact_percentage = detail['impact']['totalImpactPercentage']
        
        # Get additional cost breakdown
        cost_breakdown = get_cost_breakdown(ce_client, detail)
        
        # Publish custom CloudWatch metrics
        publish_metrics(cloudwatch, anomaly_id, total_impact, impact_percentage)
        
        # Send enhanced notification
        send_enhanced_notification(sns, detail, cost_breakdown)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed anomaly {anomaly_id}',
                'total_impact': float(total_impact),
                'impact_percentage': float(impact_percentage)
            })
        }
        
    except Exception as e:
        print(f"Error processing anomaly: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_cost_breakdown(ce_client, detail):
    """Get detailed cost breakdown for the anomaly period"""
    try:
        end_date = detail['anomalyEndDate'][:10]  # YYYY-MM-DD
        start_date = detail['anomalyStartDate'][:10]
        
        # Get cost and usage data
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date,
                'End': end_date
            },
            Granularity='DAILY',
            Metrics=['BlendedCost', 'UsageQuantity'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'}
            ]
        )
        
        return response.get('ResultsByTime', [])
        
    except Exception as e:
        print(f"Error getting cost breakdown: {str(e)}")
        return []

def publish_metrics(cloudwatch, anomaly_id, total_impact, impact_percentage):
    """Publish custom CloudWatch metrics for anomaly tracking"""
    try:
        cloudwatch.put_metric_data(
            Namespace='AWS/CostAnomaly',
            MetricData=[
                {
                    'MetricName': 'AnomalyImpact',
                    'Value': float(total_impact),
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'AnomalyId',
                            'Value': anomaly_id
                        }
                    ]
                },
                {
                    'MetricName': 'AnomalyPercentage',
                    'Value': float(impact_percentage),
                    'Unit': 'Percent',
                    'Dimensions': [
                        {
                            'Name': 'AnomalyId',
                            'Value': anomaly_id
                        }
                    ]
                }
            ]
        )
        print("✅ Custom metrics published to CloudWatch")
        
    except Exception as e:
        print(f"Error publishing metrics: {str(e)}")

def send_enhanced_notification(sns, detail, cost_breakdown):
    """Send enhanced notification with detailed analysis"""
    try:
        # Format the notification message
        message = format_notification_message(detail, cost_breakdown)
        
        # Publish to SNS
        response = sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f"🚨 AWS Cost Anomaly Detected - ${detail['impact']['totalImpact']:.2f}",
            Message=message
        )
        
        print(f"✅ Notification sent: {response['MessageId']}")
        
    except Exception as e:
        print(f"Error sending notification: {str(e)}")

def format_notification_message(detail, cost_breakdown):
    """Format detailed notification message"""
    impact = detail['impact']
    
    message = f"""
AWS Cost Anomaly Detection Alert
================================

Anomaly ID: {detail['anomalyId']}
Account: {detail['accountName']}
Service: {detail.get('dimensionValue', 'Multiple Services')}

Cost Impact:
- Total Impact: ${impact['totalImpact']:.2f}
- Actual Spend: ${impact['totalActualSpend']:.2f}
- Expected Spend: ${impact['totalExpectedSpend']:.2f}
- Percentage Increase: {impact['totalImpactPercentage']:.1f}%

Period:
- Start: {detail['anomalyStartDate']}
- End: {detail['anomalyEndDate']}

Anomaly Score:
- Current: {detail['anomalyScore']['currentScore']:.3f}
- Maximum: {detail['anomalyScore']['maxScore']:.3f}

Root Causes:
"""
    
    # Add root cause analysis
    for cause in detail.get('rootCauses', []):
        message += f"""
- Account: {cause.get('linkedAccountName', 'N/A')}
  Service: {cause.get('service', 'N/A')}
  Region: {cause.get('region', 'N/A')}
  Usage Type: {cause.get('usageType', 'N/A')}
  Contribution: ${cause.get('impact', {}).get('contribution', 0):.2f}
"""
    
    message += f"""

Next Steps:
1. Review the affected services and usage patterns
2. Check for any unauthorized usage or misconfigurations
3. Consider implementing cost controls if needed
4. Monitor for additional anomalies

AWS Console Links:
- Cost Explorer: https://console.aws.amazon.com/billing/home#/costexplorer
- Cost Anomaly Detection: https://console.aws.amazon.com/billing/home#/anomaly-detection

Generated by: AWS Cost Anomaly Detection Lambda
Timestamp: {datetime.now().isoformat()}
    """
    
    return message
EOF
    
    # Create deployment package
    cd "${SCRIPT_DIR}"
    zip lambda-deployment.zip lambda_function.py
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda-deployment.zip \
        --timeout 300 \
        --memory-size 256 \
        --environment "Variables={SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}" \
        --description "Enhanced Cost Anomaly Detection processor" \
        --tags "Purpose=CostAnomalyDetection,CreatedBy=CostAnomalyScript"
    
    # Wait for function to be ready
    log_info "Waiting for Lambda function to be active..."
    aws lambda wait function-active --function-name "${FUNCTION_NAME}"
    
    log_success "Lambda function created: ${FUNCTION_NAME}"
}

create_cost_anomaly_monitor() {
    log_info "Creating Cost Anomaly Detection monitor..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Cost Anomaly Monitor: ${MONITOR_NAME}"
        export MONITOR_ARN="arn:aws:ce::${AWS_ACCOUNT_ID}:anomalymonitor/${MONITOR_NAME}"
        return 0
    fi
    
    # Create Cost Anomaly Detection monitor
    aws ce create-anomaly-monitor \
        --anomaly-monitor '{
            "MonitorName": "'${MONITOR_NAME}'",
            "MonitorType": "DIMENSIONAL",
            "MonitorSpecification": {
                "Dimension": "SERVICE",
                "MatchOptions": ["EQUALS"],
                "Values": ["Amazon Elastic Compute Cloud - Compute"]
            },
            "MonitorDimension": "SERVICE"
        }'
    
    # Get monitor ARN
    export MONITOR_ARN=$(aws ce get-anomaly-monitors \
        --query "AnomalyMonitors[?MonitorName=='${MONITOR_NAME}'].MonitorArn" \
        --output text)
    
    log_success "Cost Anomaly Monitor created: ${MONITOR_ARN}"
}

create_eventbridge_rule() {
    log_info "Creating EventBridge rule for cost anomalies..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create EventBridge rule: ${RULE_NAME}"
        return 0
    fi
    
    # Create EventBridge rule
    aws events put-rule \
        --name "${RULE_NAME}" \
        --event-pattern '{
            "source": ["aws.ce"],
            "detail-type": ["Anomaly Detected"]
        }' \
        --description "Rule to capture Cost Anomaly Detection events" \
        --tags "Key=Purpose,Value=CostAnomalyDetection" \
              "Key=CreatedBy,Value=CostAnomalyScript"
    
    # Add Lambda function as target
    aws events put-targets \
        --rule "${RULE_NAME}" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${FUNCTION_NAME}"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${FUNCTION_NAME}" \
        --statement-id "cost-anomaly-eventbridge" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${RULE_NAME}"
    
    log_success "EventBridge rule configured: ${RULE_NAME}"
}

create_cost_anomaly_detector() {
    log_info "Creating Cost Anomaly Detector..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Cost Anomaly Detector: ${DETECTOR_NAME}"
        export DETECTOR_ARN="arn:aws:ce::${AWS_ACCOUNT_ID}:anomalydetector/${DETECTOR_NAME}"
        return 0
    fi
    
    # Create Cost Anomaly Detector
    aws ce create-anomaly-detector \
        --anomaly-detector '{
            "DetectorName": "'${DETECTOR_NAME}'",
            "MonitorArnList": ["'${MONITOR_ARN}'"],
            "Subscribers": [
                {
                    "Address": "'${SNS_TOPIC_ARN}'",
                    "Type": "SNS",
                    "Status": "CONFIRMED"
                }
            ],
            "Threshold": 10.0,
            "Frequency": "IMMEDIATE"
        }'
    
    # Store detector ARN
    export DETECTOR_ARN=$(aws ce get-anomaly-detectors \
        --query "AnomalyDetectors[?DetectorName=='${DETECTOR_NAME}'].DetectorArn" \
        --output text)
    
    log_success "Cost Anomaly Detector created: ${DETECTOR_ARN}"
}

create_cloudwatch_dashboard() {
    log_info "Creating CloudWatch dashboard..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create CloudWatch dashboard: ${DASHBOARD_NAME}"
        return 0
    fi
    
    # Create dashboard configuration
    cat > "${SCRIPT_DIR}/dashboard-config.json" << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/CostAnomaly", "AnomalyImpact" ],
                    [ ".", "AnomalyPercentage" ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Cost Anomaly Metrics",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/Lambda", "Invocations", "FunctionName", "${FUNCTION_NAME}" ],
                    [ ".", "Duration", ".", "." ],
                    [ ".", "Errors", ".", "." ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Lambda Function Metrics"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body "file://${SCRIPT_DIR}/dashboard-config.json"
    
    log_success "CloudWatch dashboard created: ${DASHBOARD_NAME}"
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    local errors=0
    
    # Check SNS topic
    if aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" &> /dev/null; then
        log_success "✅ SNS topic validation passed"
    else
        log_error "❌ SNS topic validation failed"
        ((errors++))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "${FUNCTION_NAME}" &> /dev/null; then
        log_success "✅ Lambda function validation passed"
    else
        log_error "❌ Lambda function validation failed"
        ((errors++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
        log_success "✅ IAM role validation passed"
    else
        log_error "❌ IAM role validation failed"
        ((errors++))
    fi
    
    # Check Cost Anomaly Monitor
    if aws ce get-anomaly-monitors --monitor-arn-list "${MONITOR_ARN}" &> /dev/null; then
        log_success "✅ Cost Anomaly Monitor validation passed"
    else
        log_error "❌ Cost Anomaly Monitor validation failed"
        ((errors++))
    fi
    
    # Check Cost Anomaly Detector
    if aws ce get-anomaly-detectors --detector-arn-list "${DETECTOR_ARN}" &> /dev/null; then
        log_success "✅ Cost Anomaly Detector validation passed"
    else
        log_error "❌ Cost Anomaly Detector validation failed"
        ((errors++))
    fi
    
    # Check EventBridge rule
    if aws events describe-rule --name "${RULE_NAME}" &> /dev/null; then
        log_success "✅ EventBridge rule validation passed"
    else
        log_error "❌ EventBridge rule validation failed"
        ((errors++))
    fi
    
    if [[ ${errors} -eq 0 ]]; then
        log_success "All validation checks passed!"
        return 0
    else
        log_error "Validation failed with ${errors} errors"
        return 1
    fi
}

# =============================================================================
# Main Deployment Logic
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --email)
                EMAIL_ADDRESS="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    if [[ -z "${EMAIL_ADDRESS}" ]]; then
        log_error "Email address is required. Use --email option."
        show_help
        exit 1
    fi
}

deploy_infrastructure() {
    log_info "Starting AWS Cost Anomaly Detection deployment..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
    
    # Step-by-step deployment
    setup_environment
    check_prerequisites
    create_sns_topic
    subscribe_email_to_sns
    create_iam_role
    attach_iam_policies
    create_lambda_function
    create_cost_anomaly_monitor
    create_eventbridge_rule
    create_cost_anomaly_detector
    create_cloudwatch_dashboard
    
    # Validate deployment
    validate_deployment
    
    # Clean up temporary files
    rm -f "${SCRIPT_DIR}/lambda-trust-policy.json" \
          "${SCRIPT_DIR}/cost-anomaly-policy.json" \
          "${SCRIPT_DIR}/lambda_function.py" \
          "${SCRIPT_DIR}/lambda-deployment.zip" \
          "${SCRIPT_DIR}/dashboard-config.json"
    
    log_success "Deployment completed successfully!"
    
    # Display summary
    cat << EOF

=============================================================================
DEPLOYMENT SUMMARY
=============================================================================
SNS Topic:              ${SNS_TOPIC_ARN}
Lambda Function:        ${FUNCTION_NAME}
IAM Role:              ${LAMBDA_ROLE_ARN}
Cost Anomaly Monitor:   ${MONITOR_ARN}
Cost Anomaly Detector:  ${DETECTOR_ARN}
EventBridge Rule:       ${RULE_NAME}
CloudWatch Dashboard:   ${DASHBOARD_NAME}

Email Notifications:    ${EMAIL_ADDRESS}
AWS Region:            ${AWS_REGION}
AWS Account:           ${AWS_ACCOUNT_ID}

NEXT STEPS:
1. Confirm email subscription if not done already
2. Wait 24-48 hours for anomaly detection to learn spending patterns
3. Monitor CloudWatch dashboard for cost anomaly metrics
4. Review AWS Cost Explorer for baseline understanding

AWS Console Links:
- Cost Anomaly Detection: https://console.aws.amazon.com/billing/home#/anomaly-detection
- CloudWatch Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}
- Lambda Function: https://${AWS_REGION}.console.aws.amazon.com/lambda/home?region=${AWS_REGION}#/functions/${FUNCTION_NAME}

Log file: ${LOG_FILE}
=============================================================================

EOF
}

# =============================================================================
# Script Execution
# =============================================================================

main() {
    parse_arguments "$@"
    deploy_infrastructure
}

# Execute main function with all arguments
main "$@"