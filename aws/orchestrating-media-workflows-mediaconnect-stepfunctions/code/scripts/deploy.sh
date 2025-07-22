#!/bin/bash

# Deploy script for Orchestrating Media Workflows with MediaConnect and Step Functions
# This script automates the deployment of a complete media monitoring workflow

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$aws_version" | cut -d. -f1) -lt 2 ]]; then
        error "AWS CLI v2 is required. Current version: $aws_version"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check required tools
    for tool in zip python3; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is not installed."
        fi
    done
    
    success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION="us-east-1"
        warning "Region not configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    export FLOW_NAME="live-stream-${RANDOM_SUFFIX}"
    export STATE_MACHINE_NAME="media-workflow-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="media-alerts-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="media-lambda-role-${RANDOM_SUFFIX}"
    export SF_ROLE_NAME="media-sf-role-${RANDOM_SUFFIX}"
    export EB_ROLE_NAME="eventbridge-sf-role-${RANDOM_SUFFIX}"
    export LAMBDA_BUCKET="lambda-code-${RANDOM_SUFFIX}"
    
    # Store variables for cleanup
    cat > .deployment_vars << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
FLOW_NAME=${FLOW_NAME}
STATE_MACHINE_NAME=${STATE_MACHINE_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
SF_ROLE_NAME=${SF_ROLE_NAME}
EB_ROLE_NAME=${EB_ROLE_NAME}
LAMBDA_BUCKET=${LAMBDA_BUCKET}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables configured"
}

# Create S3 bucket for Lambda code
create_lambda_bucket() {
    log "Creating S3 bucket for Lambda deployment packages..."
    
    if aws s3 ls "s3://${LAMBDA_BUCKET}" 2>/dev/null; then
        warning "S3 bucket ${LAMBDA_BUCKET} already exists"
    else
        if [[ "${AWS_REGION}" == "us-east-1" ]]; then
            aws s3 mb "s3://${LAMBDA_BUCKET}"
        else
            aws s3 mb "s3://${LAMBDA_BUCKET}" --region "${AWS_REGION}"
        fi
        success "S3 bucket created: ${LAMBDA_BUCKET}"
    fi
}

# Create SNS topic
create_sns_topic() {
    log "Creating SNS topic for media alerts..."
    
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --tags Key=Environment,Value=Production \
               Key=Purpose,Value=MediaAlerts \
               Key=Recipe,Value=media-workflow \
        --query TopicArn --output text)
    
    echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> .deployment_vars
    
    # Prompt for email subscription
    read -p "Enter email address for notifications (or press Enter to skip): " email
    if [[ -n "$email" ]]; then
        aws sns subscribe \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --protocol email \
            --notification-endpoint "$email"
        warning "Check your email to confirm the subscription"
    fi
    
    success "SNS topic created: ${SNS_TOPIC_ARN}"
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Lambda execution role
    log "Creating Lambda execution role..."
    aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document '{
          "Version": "2012-10-17",
          "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole"
          }]
        }' \
        --tags Key=Environment,Value=Production \
               Key=Purpose,Value=MediaWorkflow >/dev/null
    
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam put-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-name MediaConnectAccess \
        --policy-document '{
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Action": [
                "mediaconnect:DescribeFlow",
                "mediaconnect:ListFlows",
                "cloudwatch:GetMetricStatistics",
                "cloudwatch:GetMetricData",
                "sns:Publish"
              ],
              "Resource": "*"
            }
          ]
        }'
    
    LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --query Role.Arn --output text)
    
    echo "LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> .deployment_vars
    
    # Step Functions execution role
    log "Creating Step Functions execution role..."
    aws iam create-role \
        --role-name "${SF_ROLE_NAME}" \
        --assume-role-policy-document '{
          "Version": "2012-10-17",
          "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "states.amazonaws.com"},
            "Action": "sts:AssumeRole"
          }]
        }' \
        --tags Key=Environment,Value=Production \
               Key=Purpose,Value=MediaWorkflow >/dev/null
    
    aws iam put-role-policy \
        --role-name "${SF_ROLE_NAME}" \
        --policy-name StepFunctionsExecutionPolicy \
        --policy-document '{
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Action": [
                "lambda:InvokeFunction",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
              ],
              "Resource": "*"
            }
          ]
        }'
    
    SF_ROLE_ARN=$(aws iam get-role \
        --role-name "${SF_ROLE_NAME}" \
        --query Role.Arn --output text)
    
    echo "SF_ROLE_ARN=${SF_ROLE_ARN}" >> .deployment_vars
    
    # EventBridge role
    log "Creating EventBridge execution role..."
    aws iam create-role \
        --role-name "${EB_ROLE_NAME}" \
        --assume-role-policy-document '{
          "Version": "2012-10-17",
          "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "events.amazonaws.com"},
            "Action": "sts:AssumeRole"
          }]
        }' \
        --tags Key=Environment,Value=Production \
               Key=Purpose,Value=MediaWorkflow >/dev/null
    
    # Wait for role propagation
    sleep 10
    
    success "IAM roles created successfully"
}

# Create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create stream monitor function
    cat > stream-monitor.py << 'EOF'
import json
import boto3
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
mediaconnect = boto3.client('mediaconnect')

def lambda_handler(event, context):
    flow_arn = event['flow_arn']
    
    try:
        # Get flow details
        flow = mediaconnect.describe_flow(FlowArn=flow_arn)
        flow_name = flow['Flow']['Name']
        
        # Query CloudWatch metrics for the last 5 minutes
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=5)
        
        # Check source packet loss
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/MediaConnect',
            MetricName='SourcePacketLossPercent',
            Dimensions=[
                {'Name': 'FlowARN', 'Value': flow_arn}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        # Analyze metrics
        issues = []
        if response['Datapoints']:
            latest = sorted(response['Datapoints'], 
                           key=lambda x: x['Timestamp'])[-1]
            if latest['Maximum'] > 0.1:  # 0.1% packet loss threshold
                issues.append({
                    'metric': 'PacketLoss',
                    'value': latest['Maximum'],
                    'threshold': 0.1,
                    'severity': 'HIGH'
                })
        
        # Check source jitter
        jitter_response = cloudwatch.get_metric_statistics(
            Namespace='AWS/MediaConnect',
            MetricName='SourceJitter',
            Dimensions=[
                {'Name': 'FlowARN', 'Value': flow_arn}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        if jitter_response['Datapoints']:
            latest_jitter = sorted(jitter_response['Datapoints'], 
                                 key=lambda x: x['Timestamp'])[-1]
            if latest_jitter['Maximum'] > 50:  # 50ms jitter threshold
                issues.append({
                    'metric': 'Jitter',
                    'value': latest_jitter['Maximum'],
                    'threshold': 50,
                    'severity': 'MEDIUM'
                })
        
        return {
            'statusCode': 200,
            'flow_name': flow_name,
            'flow_arn': flow_arn,
            'timestamp': end_time.isoformat(),
            'issues': issues,
            'healthy': len(issues) == 0
        }
    
    except Exception as e:
        print(f"Error monitoring stream: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'healthy': False
        }
EOF
    
    # Create alert handler function
    cat > alert-handler.py << 'EOF'
import json
import boto3
import os

sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        # Extract monitoring results
        monitoring_result = event
        
        if not monitoring_result.get('healthy', True):
            # Get SNS topic ARN from environment
            sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
            if not sns_topic_arn:
                return {
                    'statusCode': 400,
                    'error': 'SNS_TOPIC_ARN environment variable not set'
                }
            
            # Construct alert message
            subject = f"MediaConnect Alert: {monitoring_result.get('flow_name', 'Unknown Flow')}"
            
            message_lines = [
                f"Flow: {monitoring_result.get('flow_name', 'Unknown')}",
                f"Time: {monitoring_result.get('timestamp', 'Unknown')}",
                f"Status: UNHEALTHY",
                "",
                "Issues Detected:"
            ]
            
            for issue in monitoring_result.get('issues', []):
                message_lines.append(
                    f"- {issue['metric']}: {issue['value']:.2f} "
                    f"(threshold: {issue['threshold']}) "
                    f"[{issue['severity']}]"
                )
            
            message_lines.extend([
                "",
                "Recommended Actions:",
                "1. Check source encoder stability",
                "2. Verify network connectivity",
                "3. Review CloudWatch dashboard for detailed metrics",
                f"4. Access flow in AWS Console"
            ])
            
            message = "\n".join(message_lines)
            
            # Send SNS notification
            response = sns.publish(
                TopicArn=sns_topic_arn,
                Subject=subject,
                Message=message
            )
            
            return {
                'statusCode': 200,
                'notification_sent': True,
                'message_id': response['MessageId']
            }
        
        return {
            'statusCode': 200,
            'notification_sent': False,
            'reason': 'Flow is healthy'
        }
    
    except Exception as e:
        print(f"Error sending alert: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }
EOF
    
    # Package Lambda functions
    zip stream-monitor.zip stream-monitor.py
    zip alert-handler.zip alert-handler.py
    
    # Upload to S3
    aws s3 cp stream-monitor.zip "s3://${LAMBDA_BUCKET}/"
    aws s3 cp alert-handler.zip "s3://${LAMBDA_BUCKET}/"
    
    # Create Lambda functions
    MONITOR_LAMBDA_ARN=$(aws lambda create-function \
        --function-name "stream-monitor-${RANDOM_SUFFIX}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler stream-monitor.lambda_handler \
        --code S3Bucket="${LAMBDA_BUCKET}",S3Key=stream-monitor.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables="{SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}" \
        --tags Environment=Production,Purpose=MediaWorkflow \
        --query FunctionArn --output text)
    
    ALERT_LAMBDA_ARN=$(aws lambda create-function \
        --function-name "alert-handler-${RANDOM_SUFFIX}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler alert-handler.lambda_handler \
        --code S3Bucket="${LAMBDA_BUCKET}",S3Key=alert-handler.zip \
        --timeout 30 \
        --memory-size 128 \
        --environment Variables="{SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}" \
        --tags Environment=Production,Purpose=MediaWorkflow \
        --query FunctionArn --output text)
    
    echo "MONITOR_LAMBDA_ARN=${MONITOR_LAMBDA_ARN}" >> .deployment_vars
    echo "ALERT_LAMBDA_ARN=${ALERT_LAMBDA_ARN}" >> .deployment_vars
    
    # Cleanup temporary files
    rm -f stream-monitor.py alert-handler.py stream-monitor.zip alert-handler.zip
    
    success "Lambda functions created and deployed"
}

# Create Step Functions state machine
create_step_functions() {
    log "Creating Step Functions state machine..."
    
    # Create state machine definition
    cat > state-machine.json << EOF
{
  "Comment": "Media workflow for monitoring MediaConnect flows",
  "StartAt": "MonitorStream",
  "States": {
    "MonitorStream": {
      "Type": "Task",
      "Resource": "${MONITOR_LAMBDA_ARN}",
      "Parameters": {
        "flow_arn.\$": "\$.flow_arn",
        "sns_topic_arn": "${SNS_TOPIC_ARN}"
      },
      "ResultPath": "\$.monitoring_result",
      "Next": "EvaluateHealth",
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ]
    },
    "EvaluateHealth": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "\$.monitoring_result.healthy",
          "BooleanEquals": false,
          "Next": "SendAlert"
        }
      ],
      "Default": "HealthyFlow"
    },
    "SendAlert": {
      "Type": "Task",
      "Resource": "${ALERT_LAMBDA_ARN}",
      "Parameters": {
        "flow_name.\$": "\$.monitoring_result.flow_name",
        "flow_arn.\$": "\$.monitoring_result.flow_arn",
        "timestamp.\$": "\$.monitoring_result.timestamp",
        "issues.\$": "\$.monitoring_result.issues",
        "healthy.\$": "\$.monitoring_result.healthy",
        "sns_topic_arn": "${SNS_TOPIC_ARN}"
      },
      "End": true,
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ]
    },
    "HealthyFlow": {
      "Type": "Pass",
      "Result": "Flow is healthy - no action required",
      "End": true
    }
  }
}
EOF
    
    # Add Step Functions invoke permission to EventBridge role
    aws iam put-role-policy \
        --role-name "${EB_ROLE_NAME}" \
        --policy-name InvokeStepFunctions \
        --policy-document "{
          \"Version\": \"2012-10-17\",
          \"Statement\": [{
            \"Effect\": \"Allow\",
            \"Action\": \"states:StartExecution\",
            \"Resource\": \"arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}\"
          }]
        }"
    
    EB_ROLE_ARN=$(aws iam get-role \
        --role-name "${EB_ROLE_NAME}" \
        --query Role.Arn --output text)
    
    echo "EB_ROLE_ARN=${EB_ROLE_ARN}" >> .deployment_vars
    
    # Wait for role propagation
    sleep 10
    
    # Create the state machine
    STATE_MACHINE_ARN=$(aws stepfunctions create-state-machine \
        --name "${STATE_MACHINE_NAME}" \
        --definition file://state-machine.json \
        --role-arn "${SF_ROLE_ARN}" \
        --type EXPRESS \
        --logging-configuration '{
          "level": "ERROR",
          "includeExecutionData": false
        }' \
        --tags Key=Environment,Value=Production \
               Key=Purpose,Value=MediaMonitoring \
        --query stateMachineArn --output text)
    
    echo "STATE_MACHINE_ARN=${STATE_MACHINE_ARN}" >> .deployment_vars
    
    # Cleanup temporary file
    rm -f state-machine.json
    
    success "Step Functions state machine created: ${STATE_MACHINE_ARN}"
}

# Create MediaConnect flow
create_mediaconnect_flow() {
    log "Creating MediaConnect flow..."
    
    warning "MediaConnect flow will use 0.0.0.0/0 for source whitelist. Update this in production!"
    
    # Create MediaConnect flow
    FLOW_ARN=$(aws mediaconnect create-flow \
        --name "${FLOW_NAME}" \
        --availability-zone "${AWS_REGION}a" \
        --source '{
          "Name": "PrimarySource",
          "Description": "Primary live stream source",
          "Protocol": "rtp",
          "WhitelistCidr": "0.0.0.0/0",
          "IngestPort": 5000
        }' \
        --outputs '[
          {
            "Name": "PrimaryOutput",
            "Description": "Primary stream output",
            "Protocol": "rtp",
            "Destination": "10.0.0.100",
            "Port": 5001
          },
          {
            "Name": "BackupOutput",
            "Description": "Backup stream output",
            "Protocol": "rtp",
            "Destination": "10.0.0.101",
            "Port": 5002
          }
        ]' \
        --query Flow.FlowArn --output text)
    
    echo "FLOW_ARN=${FLOW_ARN}" >> .deployment_vars
    
    # Get the ingest endpoint
    INGEST_IP=$(aws mediaconnect describe-flow \
        --flow-arn "${FLOW_ARN}" \
        --query Flow.Source.IngestIp --output text)
    
    echo "INGEST_IP=${INGEST_IP}" >> .deployment_vars
    
    # Start the flow
    aws mediaconnect start-flow --flow-arn "${FLOW_ARN}"
    
    success "MediaConnect flow created and started: ${FLOW_ARN}"
    echo "📡 Stream to: ${INGEST_IP}:5000 (RTP)"
}

# Configure CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms..."
    
    # Create alarm for packet loss
    aws cloudwatch put-metric-alarm \
        --alarm-name "${FLOW_NAME}-packet-loss" \
        --alarm-description "Triggers when packet loss exceeds threshold" \
        --metric-name SourcePacketLossPercent \
        --namespace AWS/MediaConnect \
        --statistic Maximum \
        --period 300 \
        --threshold 0.1 \
        --comparison-operator GreaterThanThreshold \
        --datapoints-to-alarm 1 \
        --evaluation-periods 1 \
        --dimensions Name=FlowARN,Value="${FLOW_ARN}" \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --tags Key=Environment,Value=Production \
               Key=Purpose,Value=MediaMonitoring
    
    # Create alarm for high jitter
    aws cloudwatch put-metric-alarm \
        --alarm-name "${FLOW_NAME}-jitter" \
        --alarm-description "Triggers when jitter exceeds threshold" \
        --metric-name SourceJitter \
        --namespace AWS/MediaConnect \
        --statistic Maximum \
        --period 300 \
        --threshold 50 \
        --comparison-operator GreaterThanThreshold \
        --datapoints-to-alarm 2 \
        --evaluation-periods 2 \
        --dimensions Name=FlowARN,Value="${FLOW_ARN}" \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --tags Key=Environment,Value=Production \
               Key=Purpose,Value=MediaMonitoring
    
    # Create alarm to trigger Step Functions
    aws cloudwatch put-metric-alarm \
        --alarm-name "${FLOW_NAME}-workflow-trigger" \
        --alarm-description "Triggers media monitoring workflow" \
        --metric-name SourcePacketLossPercent \
        --namespace AWS/MediaConnect \
        --statistic Average \
        --period 60 \
        --threshold 0.05 \
        --comparison-operator GreaterThanThreshold \
        --datapoints-to-alarm 1 \
        --evaluation-periods 1 \
        --dimensions Name=FlowARN,Value="${FLOW_ARN}" \
        --tags Key=Environment,Value=Production \
               Key=Purpose,Value=MediaMonitoring
    
    success "CloudWatch alarms configured"
}

# Create EventBridge rule
create_eventbridge_rule() {
    log "Creating EventBridge rule for automated workflow execution..."
    
    # Create EventBridge rule
    aws events put-rule \
        --name "${FLOW_NAME}-alarm-rule" \
        --description "Triggers workflow on MediaConnect alarm" \
        --event-pattern "{
          \"source\": [\"aws.cloudwatch\"],
          \"detail-type\": [\"CloudWatch Alarm State Change\"],
          \"detail\": {
            \"alarmName\": [\"${FLOW_NAME}-workflow-trigger\"],
            \"state\": {
              \"value\": [\"ALARM\"]
            }
          }
        }" \
        --state ENABLED \
        --tags Key=Environment,Value=Production \
               Key=Purpose,Value=MediaMonitoring
    
    # Add Step Functions as target
    aws events put-targets \
        --rule "${FLOW_NAME}-alarm-rule" \
        --targets "[{
          \"Id\": \"1\",
          \"Arn\": \"${STATE_MACHINE_ARN}\",
          \"RoleArn\": \"${EB_ROLE_ARN}\",
          \"Input\": \"{\\\"flow_arn\\\": \\\"${FLOW_ARN}\\\"}\"
        }]"
    
    success "EventBridge rule configured for automated workflow execution"
}

# Create CloudWatch dashboard
create_dashboard() {
    log "Creating CloudWatch dashboard..."
    
    cat > dashboard-body.json << EOF
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
          [ "AWS/MediaConnect", "SourcePacketLossPercent", "FlowARN", "${FLOW_ARN}", { "stat": "Maximum" } ],
          [ ".", "SourceJitter", ".", ".", { "stat": "Average", "yAxis": "right" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Stream Health Metrics",
        "period": 300
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
          [ "AWS/MediaConnect", "SourceBitrate", "FlowARN", "${FLOW_ARN}", { "stat": "Average" } ],
          [ ".", "SourceUptime", ".", ".", { "stat": "Maximum", "yAxis": "right" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Stream Performance",
        "period": 300
      }
    }
  ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "${FLOW_NAME}-monitoring" \
        --dashboard-body file://dashboard-body.json
    
    # Cleanup temporary file
    rm -f dashboard-body.json
    
    success "CloudWatch dashboard created"
    echo "📊 View at: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${FLOW_NAME}-monitoring"
}

# Display deployment summary
show_summary() {
    echo ""
    echo "=================================="
    echo "   DEPLOYMENT COMPLETE"
    echo "=================================="
    echo ""
    echo "Resources created:"
    echo "• MediaConnect Flow: ${FLOW_NAME}"
    echo "• Step Functions: ${STATE_MACHINE_NAME}"
    echo "• SNS Topic: ${SNS_TOPIC_NAME}"
    echo "• CloudWatch Dashboard: ${FLOW_NAME}-monitoring"
    echo ""
    echo "Stream Ingest Endpoint:"
    echo "• IP: ${INGEST_IP}"
    echo "• Port: 5000 (RTP)"
    echo ""
    echo "Monitoring URLs:"
    echo "• Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${FLOW_NAME}-monitoring"
    echo "• MediaConnect Console: https://console.aws.amazon.com/mediaconnect/home?region=${AWS_REGION}#/flows"
    echo "• Step Functions Console: https://console.aws.amazon.com/states/home?region=${AWS_REGION}#/statemachines"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo ""
    warning "Remember to update MediaConnect source whitelist for production use!"
}

# Main deployment function
main() {
    echo "🚀 Starting deployment of MediaConnect workflow..."
    echo ""
    
    check_prerequisites
    setup_environment
    create_lambda_bucket
    create_sns_topic
    create_iam_roles
    create_lambda_functions
    create_step_functions
    create_mediaconnect_flow
    create_cloudwatch_alarms
    create_eventbridge_rule
    create_dashboard
    
    show_summary
}

# Handle script interruption
cleanup_on_error() {
    error "Deployment interrupted. Run ./destroy.sh to clean up any created resources."
}

trap cleanup_on_error INT TERM

# Run main function
main "$@"