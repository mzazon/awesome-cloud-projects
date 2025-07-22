#!/bin/bash

# IoT Device Fleet Monitoring Deployment Script
# This script deploys AWS IoT Device Fleet Monitoring with CloudWatch and Device Defender
# Recipe: IoT Fleet Monitoring with Device Defender

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEPLOY_STATE_FILE="${SCRIPT_DIR}/.deploy_state"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "${RED}❌ Error: $1${NC}"
    exit 1
}

# Success message function
success() {
    log "${GREEN}✅ $1${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if jq is installed (for JSON parsing)
    if ! command_exists jq; then
        warning "jq is not installed. Some features may not work correctly."
    fi
    
    # Verify AWS permissions
    info "Verifying AWS permissions..."
    if ! aws iam get-user >/dev/null 2>&1 && ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_exit "Unable to verify AWS credentials. Please check your AWS configuration."
    fi
    
    success "Prerequisites check completed"
}

# Initialize environment variables
initialize_environment() {
    info "Initializing environment variables..."
    
    # Set basic AWS environment variables
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "${AWS_REGION}" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS_REGION not set, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export FLEET_NAME="iot-fleet-${RANDOM_SUFFIX}"
    export SECURITY_PROFILE_NAME="fleet-security-profile-${RANDOM_SUFFIX}"
    export DASHBOARD_NAME="IoT-Fleet-Dashboard-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="iot-fleet-alerts-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="iot-fleet-remediation-${RANDOM_SUFFIX}"
    export DEVICE_DEFENDER_ROLE_NAME="IoTDeviceDefenderRole-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="IoTFleetRemediationRole-${RANDOM_SUFFIX}"
    export CUSTOM_POLICY_NAME="IoTFleetRemediationPolicy-${RANDOM_SUFFIX}"
    export SCHEDULED_AUDIT_NAME="DailyFleetAudit-${RANDOM_SUFFIX}"
    export TEST_DEVICE_NAME="test-device-${RANDOM_SUFFIX}"
    
    # Save deployment state
    cat > "${DEPLOY_STATE_FILE}" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
FLEET_NAME=${FLEET_NAME}
SECURITY_PROFILE_NAME=${SECURITY_PROFILE_NAME}
DASHBOARD_NAME=${DASHBOARD_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
DEVICE_DEFENDER_ROLE_NAME=${DEVICE_DEFENDER_ROLE_NAME}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
CUSTOM_POLICY_NAME=${CUSTOM_POLICY_NAME}
SCHEDULED_AUDIT_NAME=${SCHEDULED_AUDIT_NAME}
TEST_DEVICE_NAME=${TEST_DEVICE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment initialized with Fleet: ${FLEET_NAME}"
}

# Create IAM roles and policies
create_iam_resources() {
    info "Creating IAM roles and policies..."
    
    # Create Device Defender role
    info "Creating Device Defender IAM role..."
    aws iam create-role \
        --role-name "${DEVICE_DEFENDER_ROLE_NAME}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "iot.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --description "IAM role for AWS IoT Device Defender" || {
            warning "Device Defender role may already exist"
        }
    
    # Attach required policies to Device Defender role
    aws iam attach-role-policy \
        --role-name "${DEVICE_DEFENDER_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSIoTDeviceDefenderAudit
    
    export DEVICE_DEFENDER_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${DEVICE_DEFENDER_ROLE_NAME}"
    
    # Create Lambda execution role
    info "Creating Lambda execution IAM role..."
    aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
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
        }' \
        --description "IAM role for IoT Fleet Remediation Lambda" || {
            warning "Lambda role may already exist"
        }
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for IoT and CloudWatch actions
    info "Creating custom IAM policy for Lambda..."
    aws iam create-policy \
        --policy-name "${CUSTOM_POLICY_NAME}" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "iot:UpdateCertificate",
                        "iot:DetachThingPrincipal",
                        "iot:ListThingPrincipals",
                        "iot:DescribeThing",
                        "cloudwatch:PutMetricData",
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents"
                    ],
                    "Resource": "*"
                }
            ]
        }' \
        --description "Custom policy for IoT Fleet Remediation Lambda" || {
            warning "Custom policy may already exist"
        }
    
    # Attach custom policy to Lambda role
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${CUSTOM_POLICY_NAME}"
    
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    
    # Wait for role propagation
    info "Waiting for IAM role propagation..."
    sleep 10
    
    success "IAM resources created successfully"
}

# Configure Device Defender
configure_device_defender() {
    info "Configuring AWS IoT Device Defender..."
    
    # Enable Device Defender audit configuration
    aws iot update-account-audit-configuration \
        --role-arn "${DEVICE_DEFENDER_ROLE_ARN}" \
        --audit-check-configurations '{
            "AUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK": {"enabled": true},
            "CA_CERTIFICATE_EXPIRING_CHECK": {"enabled": true},
            "CONFLICTING_CLIENT_IDS_CHECK": {"enabled": true},
            "DEVICE_CERTIFICATE_EXPIRING_CHECK": {"enabled": true},
            "DEVICE_CERTIFICATE_SHARED_CHECK": {"enabled": true},
            "IOT_POLICY_OVERLY_PERMISSIVE_CHECK": {"enabled": true},
            "LOGGING_DISABLED_CHECK": {"enabled": true},
            "REVOKED_CA_CERTIFICATE_STILL_ACTIVE_CHECK": {"enabled": true},
            "REVOKED_DEVICE_CERTIFICATE_STILL_ACTIVE_CHECK": {"enabled": true}
        }' || {
            warning "Device Defender audit configuration may already be enabled"
        }
    
    success "Device Defender audit configuration enabled"
}

# Create SNS topic and subscription
create_sns_resources() {
    info "Creating SNS topic for fleet alerts..."
    
    # Create SNS topic
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --query TopicArn --output text)
    
    export SNS_TOPIC_ARN
    
    # Create topic policy to allow Device Defender to publish
    aws sns set-topic-attributes \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --attribute-name Policy \
        --attribute-value '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "iot.amazonaws.com"
                    },
                    "Action": "SNS:Publish",
                    "Resource": "'${SNS_TOPIC_ARN}'"
                }
            ]
        }'
    
    info "SNS topic created: ${SNS_TOPIC_ARN}"
    info "To receive email notifications, subscribe to the topic:"
    info "aws sns subscribe --topic-arn ${SNS_TOPIC_ARN} --protocol email --notification-endpoint your-email@example.com"
    
    success "SNS topic configured successfully"
}

# Initialize CloudWatch metrics
initialize_cloudwatch_metrics() {
    info "Initializing custom CloudWatch metrics..."
    
    # Create custom metrics for device monitoring
    aws cloudwatch put-metric-data \
        --namespace "AWS/IoT/FleetMonitoring" \
        --metric-data MetricName=DeviceConnectionRate,Value=0,Unit=Count/Second,Dimensions=[{Name=FleetName,Value=${FLEET_NAME}}] || {
            warning "Failed to create DeviceConnectionRate metric"
        }
    
    aws cloudwatch put-metric-data \
        --namespace "AWS/IoT/FleetMonitoring" \
        --metric-data MetricName=MessageProcessingRate,Value=0,Unit=Count/Second,Dimensions=[{Name=FleetName,Value=${FLEET_NAME}}] || {
            warning "Failed to create MessageProcessingRate metric"
        }
    
    aws cloudwatch put-metric-data \
        --namespace "AWS/IoT/FleetMonitoring" \
        --metric-data MetricName=SecurityViolations,Value=0,Unit=Count,Dimensions=[{Name=FleetName,Value=${FLEET_NAME}}] || {
            warning "Failed to create SecurityViolations metric"
        }
    
    success "Custom CloudWatch metrics initialized"
}

# Create security profile
create_security_profile() {
    info "Creating IoT Device Defender security profile..."
    
    # Create comprehensive security profile
    aws iot create-security-profile \
        --security-profile-name "${SECURITY_PROFILE_NAME}" \
        --security-profile-description "Comprehensive security monitoring for IoT device fleet" \
        --behaviors '[
            {
                "name": "AuthorizationFailures",
                "metric": "aws:num-authorization-failures",
                "criteria": {
                    "comparisonOperator": "greater-than",
                    "value": {"count": 5},
                    "durationSeconds": 300,
                    "consecutiveDatapointsToAlarm": 2,
                    "consecutiveDatapointsToClear": 2
                }
            },
            {
                "name": "MessageByteSize",
                "metric": "aws:message-byte-size",
                "criteria": {
                    "comparisonOperator": "greater-than",
                    "value": {"count": 1024},
                    "consecutiveDatapointsToAlarm": 3,
                    "consecutiveDatapointsToClear": 1
                }
            },
            {
                "name": "MessagesReceived",
                "metric": "aws:num-messages-received",
                "criteria": {
                    "comparisonOperator": "greater-than",
                    "value": {"count": 100},
                    "durationSeconds": 300,
                    "consecutiveDatapointsToAlarm": 2,
                    "consecutiveDatapointsToClear": 2
                }
            },
            {
                "name": "MessagesSent",
                "metric": "aws:num-messages-sent",
                "criteria": {
                    "comparisonOperator": "greater-than",
                    "value": {"count": 100},
                    "durationSeconds": 300,
                    "consecutiveDatapointsToAlarm": 2,
                    "consecutiveDatapointsToClear": 2
                }
            },
            {
                "name": "ConnectionAttempts",
                "metric": "aws:num-connection-attempts",
                "criteria": {
                    "comparisonOperator": "greater-than",
                    "value": {"count": 10},
                    "durationSeconds": 300,
                    "consecutiveDatapointsToAlarm": 2,
                    "consecutiveDatapointsToClear": 2
                }
            }
        ]' \
        --alert-targets '{
            "SNS": {
                "alertTargetArn": "'${SNS_TOPIC_ARN}'",
                "roleArn": "'${DEVICE_DEFENDER_ROLE_ARN}'"
            }
        }' || {
            warning "Security profile may already exist"
        }
    
    export SECURITY_PROFILE_ARN="arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:securityprofile/${SECURITY_PROFILE_NAME}"
    
    success "Security profile created: ${SECURITY_PROFILE_NAME}"
}

# Create IoT things and thing group
create_iot_resources() {
    info "Creating IoT things and thing group..."
    
    # Create thing group for fleet management
    aws iot create-thing-group \
        --thing-group-name "${FLEET_NAME}" \
        --thing-group-properties \
            thingGroupDescription="IoT device fleet for monitoring demonstration" || {
            warning "Thing group may already exist"
        }
    
    # Create sample IoT things representing devices
    for i in {1..5}; do
        THING_NAME="device-${FLEET_NAME}-${i}"
        
        # Create IoT thing
        aws iot create-thing \
            --thing-name "${THING_NAME}" \
            --attribute-payload attributes='{
                "deviceType": "sensor",
                "location": "facility-'${i}'",
                "firmware": "v1.2.3"
            }' || {
            warning "Thing ${THING_NAME} may already exist"
        }
        
        # Add thing to fleet group
        aws iot add-thing-to-thing-group \
            --thing-group-name "${FLEET_NAME}" \
            --thing-name "${THING_NAME}" || {
            warning "Thing ${THING_NAME} may already be in group"
        }
    done
    
    # Attach security profile to thing group
    aws iot attach-security-profile \
        --security-profile-name "${SECURITY_PROFILE_NAME}" \
        --security-profile-target-arn "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thinggroup/${FLEET_NAME}" || {
        warning "Security profile may already be attached"
    }
    
    success "Created 5 test devices and attached security profile"
}

# Create Lambda function
create_lambda_function() {
    info "Creating Lambda function for automated remediation..."
    
    # Create Lambda function code
    cat > /tmp/lambda_function.py << 'EOF'
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iot_client = boto3.client('iot')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Parse SNS message
        if 'Records' in event:
            for record in event['Records']:
                if record['EventSource'] == 'aws:sns':
                    message = json.loads(record['Sns']['Message'])
                    process_security_violation(message)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed security violation')
        }
    
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def process_security_violation(message):
    """Process Device Defender security violation"""
    
    violation_type = message.get('violationEventType', 'unknown')
    thing_name = message.get('thingName', 'unknown')
    behavior_name = message.get('behavior', {}).get('name', 'unknown')
    
    logger.info(f"Processing violation: {violation_type} for {thing_name}, behavior: {behavior_name}")
    
    # Send custom metric to CloudWatch
    cloudwatch.put_metric_data(
        Namespace='AWS/IoT/FleetMonitoring',
        MetricData=[
            {
                'MetricName': 'SecurityViolations',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {
                        'Name': 'ViolationType',
                        'Value': violation_type
                    },
                    {
                        'Name': 'BehaviorName',
                        'Value': behavior_name
                    }
                ]
            }
        ]
    )
    
    # Implement remediation logic based on violation type
    if violation_type == 'in-alarm':
        handle_security_alarm(thing_name, behavior_name)
    elif violation_type == 'alarm-cleared':
        handle_alarm_cleared(thing_name, behavior_name)

def handle_security_alarm(thing_name, behavior_name):
    """Handle security alarm with appropriate remediation"""
    
    if behavior_name == 'AuthorizationFailures':
        # For repeated authorization failures, consider temporary device isolation
        logger.warning(f"Authorization failures detected for {thing_name}")
        # In production, you might disable the certificate temporarily
        
    elif behavior_name == 'MessageByteSize':
        # Large message size might indicate data exfiltration
        logger.warning(f"Unusual message size detected for {thing_name}")
        
    elif behavior_name in ['MessagesReceived', 'MessagesSent']:
        # Unusual message volume might indicate compromised device
        logger.warning(f"Unusual message volume detected for {thing_name}")
        
    elif behavior_name == 'ConnectionAttempts':
        # Multiple connection attempts might indicate brute force attack
        logger.warning(f"Multiple connection attempts detected for {thing_name}")

def handle_alarm_cleared(thing_name, behavior_name):
    """Handle alarm cleared event"""
    logger.info(f"Alarm cleared for {thing_name}, behavior: {behavior_name}")
    
    # Send metric indicating alarm cleared
    cloudwatch.put_metric_data(
        Namespace='AWS/IoT/FleetMonitoring',
        MetricData=[
            {
                'MetricName': 'SecurityAlarmsCleared',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {
                        'Name': 'BehaviorName',
                        'Value': behavior_name
                    }
                ]
            }
        ]
    )
EOF
    
    # Create deployment package
    cd /tmp && zip -q lambda_function.zip lambda_function.py
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda_function.zip \
        --description "Automated remediation for IoT fleet security violations" \
        --timeout 60 || {
        warning "Lambda function may already exist"
    }
    
    # Wait for function to be active
    info "Waiting for Lambda function to be active..."
    aws lambda wait function-active --function-name "${LAMBDA_FUNCTION_NAME}" || {
        warning "Lambda function may not be fully active yet"
    }
    
    success "Lambda remediation function created"
}

# Configure SNS to trigger Lambda
configure_sns_lambda_integration() {
    info "Configuring SNS to trigger Lambda function..."
    
    # Subscribe Lambda function to SNS topic
    LAMBDA_FUNCTION_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
    
    aws sns subscribe \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --protocol lambda \
        --notification-endpoint "${LAMBDA_FUNCTION_ARN}" || {
        warning "SNS subscription may already exist"
    }
    
    # Add permission for SNS to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id "sns-invoke-permission" \
        --action "lambda:InvokeFunction" \
        --principal sns.amazonaws.com \
        --source-arn "${SNS_TOPIC_ARN}" || {
        warning "Lambda permission may already exist"
    }
    
    success "SNS configured to trigger Lambda function"
}

# Create CloudWatch alarms
create_cloudwatch_alarms() {
    info "Creating CloudWatch alarms for fleet monitoring..."
    
    # Create alarm for high security violations
    aws cloudwatch put-metric-alarm \
        --alarm-name "IoT-Fleet-High-Security-Violations-${RANDOM_SUFFIX}" \
        --alarm-description "High number of security violations detected" \
        --metric-name SecurityViolations \
        --namespace AWS/IoT/FleetMonitoring \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=FleetName,Value="${FLEET_NAME}" || {
        warning "High security violations alarm may already exist"
    }
    
    # Create alarm for device connectivity issues
    aws cloudwatch put-metric-alarm \
        --alarm-name "IoT-Fleet-Low-Connectivity-${RANDOM_SUFFIX}" \
        --alarm-description "Low device connectivity detected" \
        --metric-name ConnectedDevices \
        --namespace AWS/IoT \
        --statistic Average \
        --period 300 \
        --threshold 3 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --treat-missing-data notBreaching || {
        warning "Low connectivity alarm may already exist"
    }
    
    # Create alarm for message processing errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "IoT-Fleet-Message-Processing-Errors-${RANDOM_SUFFIX}" \
        --alarm-description "High message processing error rate" \
        --metric-name RuleMessageProcessingErrors \
        --namespace AWS/IoT \
        --statistic Sum \
        --period 300 \
        --threshold 10 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}" || {
        warning "Message processing errors alarm may already exist"
    }
    
    success "CloudWatch alarms configured for fleet monitoring"
}

# Create CloudWatch dashboard
create_cloudwatch_dashboard() {
    info "Creating custom CloudWatch dashboard..."
    
    # Create comprehensive dashboard JSON
    cat > /tmp/dashboard.json << EOF
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
                    ["AWS/IoT", "ConnectedDevices", {"stat": "Average"}],
                    [".", "MessagesSent", {"stat": "Sum"}],
                    [".", "MessagesReceived", {"stat": "Sum"}]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "IoT Fleet Overview",
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
                    ["AWS/IoT/FleetMonitoring", "SecurityViolations", "FleetName", "${FLEET_NAME}"],
                    [".", "SecurityAlarmsCleared", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Security Violations",
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
                    ["AWS/IoT", "RuleMessageProcessingErrors", {"stat": "Sum"}],
                    [".", "RuleMessageProcessingSuccess", {"stat": "Sum"}]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Message Processing",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "log",
            "x": 12,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/lambda/${LAMBDA_FUNCTION_NAME}' | fields @timestamp, @message\\n| filter @message like /violation/\\n| sort @timestamp desc\\n| limit 20",
                "region": "${AWS_REGION}",
                "title": "Security Violation Logs",
                "view": "table"
            }
        }
    ]
}
EOF
    
    # Create the dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body file:///tmp/dashboard.json || {
        warning "Dashboard may already exist"
    }
    
    success "CloudWatch dashboard created: ${DASHBOARD_NAME}"
}

# Create scheduled audit
create_scheduled_audit() {
    info "Creating scheduled audit for compliance monitoring..."
    
    # Create daily scheduled audit
    aws iot create-scheduled-audit \
        --scheduled-audit-name "${SCHEDULED_AUDIT_NAME}" \
        --frequency DAILY \
        --target-check-names \
            CA_CERTIFICATE_EXPIRING_CHECK \
            DEVICE_CERTIFICATE_EXPIRING_CHECK \
            DEVICE_CERTIFICATE_SHARED_CHECK \
            IOT_POLICY_OVERLY_PERMISSIVE_CHECK \
            LOGGING_DISABLED_CHECK \
            REVOKED_CA_CERTIFICATE_STILL_ACTIVE_CHECK \
            REVOKED_DEVICE_CERTIFICATE_STILL_ACTIVE_CHECK || {
        warning "Scheduled audit may already exist"
    }
    
    # Configure audit notifications
    aws iot update-account-audit-configuration \
        --audit-notification-target-configurations \
            'SNS={targetArn="'${SNS_TOPIC_ARN}'",roleArn="'${DEVICE_DEFENDER_ROLE_ARN}'",enabled=true}' || {
        warning "Audit notification configuration may already be set"
    }
    
    success "Scheduled audit configured for daily compliance monitoring"
}

# Create IoT rules for advanced monitoring
create_iot_rules() {
    info "Creating IoT rules for advanced monitoring..."
    
    # Create log group for IoT events
    aws logs create-log-group \
        --log-group-name "/aws/iot/fleet-monitoring" || {
        warning "Log group may already exist"
    }
    
    # Create IoT rule for device connection monitoring
    aws iot create-topic-rule \
        --rule-name "DeviceConnectionMonitoring${RANDOM_SUFFIX}" \
        --topic-rule-payload '{
            "sql": "SELECT * FROM \"$aws/events/presence/connected/+\" WHERE eventType = \"connected\" OR eventType = \"disconnected\"",
            "description": "Monitor device connection events",
            "actions": [
                {
                    "cloudwatchMetric": {
                        "roleArn": "'${DEVICE_DEFENDER_ROLE_ARN}'",
                        "metricNamespace": "AWS/IoT/FleetMonitoring",
                        "metricName": "DeviceConnectionEvents",
                        "metricValue": "1",
                        "metricUnit": "Count",
                        "metricTimestamp": "${timestamp()}"
                    }
                },
                {
                    "cloudwatchLogs": {
                        "roleArn": "'${DEVICE_DEFENDER_ROLE_ARN}'",
                        "logGroupName": "/aws/iot/fleet-monitoring"
                    }
                }
            ]
        }' || {
        warning "Device connection monitoring rule may already exist"
    }
    
    # Create IoT rule for message volume monitoring
    aws iot create-topic-rule \
        --rule-name "MessageVolumeMonitoring${RANDOM_SUFFIX}" \
        --topic-rule-payload '{
            "sql": "SELECT clientId, timestamp, topic FROM \"device/+/data\"",
            "description": "Monitor message volume from devices",
            "actions": [
                {
                    "cloudwatchMetric": {
                        "roleArn": "'${DEVICE_DEFENDER_ROLE_ARN}'",
                        "metricNamespace": "AWS/IoT/FleetMonitoring",
                        "metricName": "MessageVolume",
                        "metricValue": "1",
                        "metricUnit": "Count",
                        "metricTimestamp": "${timestamp()}"
                    }
                }
            ]
        }' || {
        warning "Message volume monitoring rule may already exist"
    }
    
    success "IoT rules created for advanced monitoring"
}

# Create test device
create_test_device() {
    info "Creating test device for validation..."
    
    # Create test device
    aws iot create-thing \
        --thing-name "${TEST_DEVICE_NAME}" \
        --attribute-payload attributes='{"deviceType": "test", "location": "lab"}' || {
        warning "Test device may already exist"
    }
    
    # Add test device to fleet
    aws iot add-thing-to-thing-group \
        --thing-group-name "${FLEET_NAME}" \
        --thing-name "${TEST_DEVICE_NAME}" || {
        warning "Test device may already be in group"
    }
    
    success "Test device created: ${TEST_DEVICE_NAME}"
}

# Update deployment state with final values
update_deployment_state() {
    info "Updating deployment state..."
    
    # Update deployment state file with additional values
    cat >> "${DEPLOY_STATE_FILE}" << EOF
SNS_TOPIC_ARN=${SNS_TOPIC_ARN}
DEVICE_DEFENDER_ROLE_ARN=${DEVICE_DEFENDER_ROLE_ARN}
LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}
SECURITY_PROFILE_ARN=${SECURITY_PROFILE_ARN}
DEPLOYMENT_COMPLETE=true
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    success "Deployment state updated"
}

# Display deployment summary
display_deployment_summary() {
    info "Deployment Summary:"
    echo "===================="
    echo "Fleet Name: ${FLEET_NAME}"
    echo "Security Profile: ${SECURITY_PROFILE_NAME}"
    echo "Dashboard: ${DASHBOARD_NAME}"
    echo "SNS Topic: ${SNS_TOPIC_ARN}"
    echo "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "Test Device: ${TEST_DEVICE_NAME}"
    echo "AWS Region: ${AWS_REGION}"
    echo ""
    echo "Dashboard URL: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
    echo ""
    echo "To receive email notifications:"
    echo "aws sns subscribe --topic-arn ${SNS_TOPIC_ARN} --protocol email --notification-endpoint your-email@example.com"
    echo ""
    echo "Deployment state saved to: ${DEPLOY_STATE_FILE}"
    echo "Deployment logs saved to: ${LOG_FILE}"
}

# Main deployment function
main() {
    echo "Starting IoT Device Fleet Monitoring deployment..."
    echo "=================================================="
    
    # Initialize log file
    echo "Deployment started at $(date)" > "${LOG_FILE}"
    
    # Run deployment steps
    check_prerequisites
    initialize_environment
    create_iam_resources
    configure_device_defender
    create_sns_resources
    initialize_cloudwatch_metrics
    create_security_profile
    create_iot_resources
    create_lambda_function
    configure_sns_lambda_integration
    create_cloudwatch_alarms
    create_cloudwatch_dashboard
    create_scheduled_audit
    create_iot_rules
    create_test_device
    update_deployment_state
    
    # Clean up temporary files
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/dashboard.json
    
    success "Deployment completed successfully!"
    display_deployment_summary
}

# Run main function
main "$@"