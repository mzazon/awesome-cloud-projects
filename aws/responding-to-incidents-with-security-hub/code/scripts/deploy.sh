#!/bin/bash

# Security Incident Response with AWS Security Hub - Deployment Script
# This script deploys the complete security incident response infrastructure

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if required AWS services are available in region
    local region=$(aws configure get region)
    if [[ -z "$region" ]]; then
        error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    # Verify Security Hub is available in the region
    if ! aws securityhub describe-hub --region "$region" &> /dev/null; then
        warning "Security Hub may not be enabled in region $region"
    fi
    
    success "Prerequisites check completed"
}

# Function to initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set core environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export SECURITY_HUB_ROLE_NAME="SecurityHubIncidentResponseRole-${random_suffix}"
    export LAMBDA_ROLE_NAME="SecurityHubLambdaRole-${random_suffix}"
    export SNS_TOPIC_NAME="security-incident-alerts-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="security-incident-processor-${random_suffix}"
    export CUSTOM_ACTION_NAME="escalate-to-soc-${random_suffix}"
    export THREAT_INTEL_FUNCTION_NAME="threat-intelligence-lookup-${random_suffix}"
    export SQS_QUEUE_NAME="security-incident-queue-${random_suffix}"
    
    # Create deployment state file
    cat > /tmp/security-hub-deployment-state.env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
SECURITY_HUB_ROLE_NAME=${SECURITY_HUB_ROLE_NAME}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
CUSTOM_ACTION_NAME=${CUSTOM_ACTION_NAME}
THREAT_INTEL_FUNCTION_NAME=${THREAT_INTEL_FUNCTION_NAME}
SQS_QUEUE_NAME=${SQS_QUEUE_NAME}
EOF
    
    success "Environment variables initialized"
    log "Deployment state saved to /tmp/security-hub-deployment-state.env"
}

# Function to create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create IAM role for Security Hub
    aws iam create-role \
        --role-name "${SECURITY_HUB_ROLE_NAME}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "securityhub.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --tags Key=Project,Value=SecurityIncidentResponse Key=Environment,Value=Production \
        --output table > /dev/null
    
    # Create IAM role for Lambda
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
        --tags Key=Project,Value=SecurityIncidentResponse Key=Environment,Value=Production \
        --output table > /dev/null
    
    # Attach basic execution role for Lambda
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for Security Hub and SNS access
    local policy_doc='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "securityhub:BatchUpdateFindings",
                    "securityhub:GetFindings",
                    "sns:Publish"
                ],
                "Resource": "*"
            }
        ]
    }'
    
    aws iam create-policy \
        --policy-name "SecurityHubLambdaPolicy-${LAMBDA_ROLE_NAME##*-}" \
        --policy-document "$policy_doc" \
        --description "Policy for Security Hub Lambda incident processor" \
        --output table > /dev/null
    
    # Attach custom policy to Lambda role
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SecurityHubLambdaPolicy-${LAMBDA_ROLE_NAME##*-}"
    
    # Wait for IAM role propagation
    sleep 15
    
    success "IAM roles created and configured"
}

# Function to enable Security Hub
enable_security_hub() {
    log "Enabling AWS Security Hub..."
    
    # Check if Security Hub is already enabled
    if aws securityhub describe-hub --region "$AWS_REGION" &> /dev/null; then
        warning "Security Hub is already enabled in region $AWS_REGION"
    else
        # Enable Security Hub with default standards
        aws securityhub enable-security-hub \
            --enable-default-standards \
            --tags Project=SecurityIncidentResponse,Environment=Production \
            --output table > /dev/null
        
        # Wait for Security Hub to be fully enabled
        sleep 10
        
        # Enable additional security standards
        aws securityhub batch-enable-standards \
            --standards-subscription-requests '[
                {
                    "StandardsArn": "arn:aws:securityhub:'${AWS_REGION}'::standards/cis-aws-foundations-benchmark/v/1.4.0"
                }
            ]' --output table > /dev/null 2>/dev/null || warning "CIS standard may already be enabled"
    fi
    
    success "Security Hub enabled and configured"
}

# Function to create SNS topic and SQS queue
create_messaging_infrastructure() {
    log "Creating SNS topic and SQS queue..."
    
    # Create SNS topic
    local sns_topic_arn=$(aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --attributes '{
            "DisplayName": "Security Incident Alerts",
            "DeliveryPolicy": "{\"http\":{\"defaultHealthyRetryPolicy\":{\"numRetries\":3,\"minDelayTarget\":20,\"maxDelayTarget\":20,\"numMinDelayRetries\":0,\"numMaxDelayRetries\":0,\"numNoDelayRetries\":0,\"backoffFunction\":\"linear\"},\"disableSubscriptionOverrides\":false}}",
            "Policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"},\"Action\":\"SNS:Publish\",\"Resource\":\"*\"}]}"
        }' \
        --query TopicArn --output text)
    
    export SNS_TOPIC_ARN="$sns_topic_arn"
    
    # Add SNS topic ARN to state file
    echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> /tmp/security-hub-deployment-state.env
    
    # Create SQS queue for buffering notifications
    local queue_url=$(aws sqs create-queue \
        --queue-name "${SQS_QUEUE_NAME}" \
        --attributes '{
            "MessageRetentionPeriod": "1209600",
            "ReceiveMessageWaitTimeSeconds": "20",
            "VisibilityTimeoutSeconds": "300"
        }' \
        --query QueueUrl --output text)
    
    export QUEUE_URL="$queue_url"
    
    # Get queue ARN
    local queue_arn=$(aws sqs get-queue-attributes \
        --queue-url "${QUEUE_URL}" \
        --attribute-names QueueArn \
        --query Attributes.QueueArn --output text)
    
    export QUEUE_ARN="$queue_arn"
    
    # Add queue details to state file
    echo "QUEUE_URL=${QUEUE_URL}" >> /tmp/security-hub-deployment-state.env
    echo "QUEUE_ARN=${QUEUE_ARN}" >> /tmp/security-hub-deployment-state.env
    
    # Subscribe SQS queue to SNS topic
    aws sns subscribe \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --protocol sqs \
        --notification-endpoint "${QUEUE_ARN}" \
        --output table > /dev/null
    
    # Grant SNS permission to send messages to SQS
    local policy_doc='{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "sns.amazonaws.com"},
            "Action": "sqs:SendMessage",
            "Resource": "'${QUEUE_ARN}'",
            "Condition": {
                "ArnEquals": {
                    "aws:SourceArn": "'${SNS_TOPIC_ARN}'"
                }
            }
        }]
    }'
    
    aws sqs set-queue-attributes \
        --queue-url "${QUEUE_URL}" \
        --attributes "Policy=${policy_doc}"
    
    success "Messaging infrastructure created"
}

# Function to create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create incident processor Lambda function code
    cat > /tmp/incident_processor.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    # Initialize AWS clients
    sns = boto3.client('sns')
    securityhub = boto3.client('securityhub')
    
    try:
        # Process Security Hub finding
        finding = event['detail']['findings'][0]
        
        # Extract key information
        severity = finding.get('Severity', {}).get('Label', 'UNKNOWN')
        title = finding.get('Title', 'Unknown Security Finding')
        description = finding.get('Description', 'No description available')
        account_id = finding.get('AwsAccountId', 'Unknown')
        region = finding.get('Region', 'Unknown')
        finding_id = finding.get('Id', 'Unknown')
        
        # Determine response based on severity
        response_action = determine_response_action(severity)
        
        # Create incident ticket payload
        incident_payload = {
            'finding_id': finding_id,
            'severity': severity,
            'title': title,
            'description': description,
            'account_id': account_id,
            'region': region,
            'timestamp': datetime.utcnow().isoformat(),
            'response_action': response_action,
            'source': 'AWS Security Hub'
        }
        
        # Send notification to SNS
        message = create_incident_message(incident_payload)
        
        response = sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=json.dumps(message, indent=2),
            Subject=f"Security Incident: {severity} - {title[:50]}",
            MessageAttributes={
                'severity': {
                    'DataType': 'String',
                    'StringValue': severity
                },
                'account_id': {
                    'DataType': 'String',
                    'StringValue': account_id
                }
            }
        )
        
        # Update finding with response action
        update_finding_workflow(securityhub, finding_id, response_action)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Incident processed successfully',
                'finding_id': finding_id,
                'severity': severity,
                'response_action': response_action
            })
        }
        
    except Exception as e:
        print(f"Error processing incident: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'finding_id': finding.get('Id', 'Unknown') if 'finding' in locals() else 'Unknown'
            })
        }

def determine_response_action(severity):
    """Determine appropriate response action based on severity"""
    if severity == 'CRITICAL':
        return 'immediate_response'
    elif severity == 'HIGH':
        return 'escalated_response'
    elif severity == 'MEDIUM':
        return 'standard_response'
    else:
        return 'low_priority_response'

def create_incident_message(payload):
    """Create formatted incident message"""
    return {
        'incident_details': {
            'id': payload['finding_id'],
            'severity': payload['severity'],
            'title': payload['title'],
            'description': payload['description'],
            'account': payload['account_id'],
            'region': payload['region'],
            'timestamp': payload['timestamp']
        },
        'response_plan': {
            'action': payload['response_action'],
            'priority': get_priority_level(payload['severity']),
            'sla': get_sla_minutes(payload['severity'])
        },
        'integration': {
            'jira_project': 'SEC',
            'slack_channel': '#security-incidents',
            'pagerduty_service': 'security-team'
        }
    }

def get_priority_level(severity):
    """Map severity to priority level"""
    priority_map = {
        'CRITICAL': 'P1',
        'HIGH': 'P2',
        'MEDIUM': 'P3',
        'LOW': 'P4',
        'INFORMATIONAL': 'P5'
    }
    return priority_map.get(severity, 'P4')

def get_sla_minutes(severity):
    """Get SLA response time in minutes"""
    sla_map = {
        'CRITICAL': 15,
        'HIGH': 60,
        'MEDIUM': 240,
        'LOW': 1440,
        'INFORMATIONAL': 2880
    }
    return sla_map.get(severity, 1440)

def update_finding_workflow(securityhub, finding_id, response_action):
    """Update finding workflow status"""
    try:
        securityhub.batch_update_findings(
            FindingIdentifiers=[{
                'Id': finding_id,
                'ProductArn': f'arn:aws:securityhub:{os.environ["AWS_REGION"]}::product/aws/securityhub'
            }],
            Note={
                'Text': f'Automated incident response initiated: {response_action}',
                'UpdatedBy': 'SecurityHubAutomation'
            },
            Workflow={
                'Status': 'NOTIFIED'
            }
        )
    except Exception as e:
        print(f"Error updating finding workflow: {str(e)}")
EOF
    
    # Create threat intelligence Lambda function code
    cat > /tmp/threat_intelligence.py << 'EOF'
import json
import boto3
import os
import re

def lambda_handler(event, context):
    try:
        finding = event['detail']['findings'][0]
        
        # Extract IP addresses, domains, hashes from finding
        resources = finding.get('Resources', [])
        threat_indicators = extract_threat_indicators(resources)
        
        # Simulate threat intelligence lookup
        threat_score = calculate_threat_score(threat_indicators)
        
        # Update finding with threat intelligence
        securityhub = boto3.client('securityhub')
        
        securityhub.batch_update_findings(
            FindingIdentifiers=[{
                'Id': finding['Id'],
                'ProductArn': finding['ProductArn']
            }],
            Note={
                'Text': f'Threat Intelligence Score: {threat_score}/100. Indicators: {len(threat_indicators)}',
                'UpdatedBy': 'ThreatIntelligence'
            },
            UserDefinedFields={
                'ThreatScore': str(threat_score),
                'ThreatIndicators': str(len(threat_indicators))
            }
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'threat_score': threat_score,
                'indicators_found': len(threat_indicators)
            })
        }
        
    except Exception as e:
        print(f"Error updating finding with threat intelligence: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def extract_threat_indicators(resources):
    """Extract potential threat indicators from resources"""
    indicators = []
    
    for resource in resources:
        resource_id = resource.get('Id', '')
        
        # Look for IP addresses (simplified regex)
        ip_pattern = r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b'
        ips = re.findall(ip_pattern, resource_id)
        indicators.extend(ips)
        
        # Look for domains (simplified)
        domain_pattern = r'\b[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b'
        domains = re.findall(domain_pattern, resource_id)
        indicators.extend(domains)
    
    return indicators

def calculate_threat_score(indicators):
    """Calculate threat score based on indicators"""
    # This would normally query actual threat intelligence feeds
    # For demo, we'll use a simple scoring system
    base_score = 10
    indicator_bonus = len(indicators) * 5
    
    return min(base_score + indicator_bonus, 100)
EOF
    
    # Zip the Lambda functions
    cd /tmp
    zip incident_processor.zip incident_processor.py
    zip threat_intelligence.zip threat_intelligence.py
    
    # Deploy incident processor Lambda function
    local lambda_arn=$(aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
        --handler incident_processor.lambda_handler \
        --zip-file fileb://incident_processor.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment "Variables={SNS_TOPIC_ARN=${SNS_TOPIC_ARN},AWS_REGION=${AWS_REGION}}" \
        --tags Project=SecurityIncidentResponse,Environment=Production \
        --query FunctionArn --output text)
    
    export LAMBDA_ARN="$lambda_arn"
    
    # Deploy threat intelligence Lambda function
    local threat_intel_arn=$(aws lambda create-function \
        --function-name "${THREAT_INTEL_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
        --handler threat_intelligence.lambda_handler \
        --zip-file fileb://threat_intelligence.zip \
        --timeout 60 \
        --memory-size 256 \
        --tags Project=SecurityIncidentResponse,Environment=Production \
        --query FunctionArn --output text)
    
    export THREAT_INTEL_ARN="$threat_intel_arn"
    
    # Add Lambda ARNs to state file
    echo "LAMBDA_ARN=${LAMBDA_ARN}" >> /tmp/security-hub-deployment-state.env
    echo "THREAT_INTEL_ARN=${THREAT_INTEL_ARN}" >> /tmp/security-hub-deployment-state.env
    
    success "Lambda functions created and deployed"
}

# Function to create EventBridge rules
create_eventbridge_rules() {
    log "Creating EventBridge rules..."
    
    # Create EventBridge rule for high severity findings
    aws events put-rule \
        --name security-hub-high-severity \
        --event-pattern '{
            "source": ["aws.securityhub"],
            "detail-type": ["Security Hub Findings - Imported"],
            "detail": {
                "findings": {
                    "Severity": {
                        "Label": ["HIGH", "CRITICAL"]
                    },
                    "Workflow": {
                        "Status": ["NEW"]
                    }
                }
            }
        }' \
        --state ENABLED \
        --description "Process high and critical severity Security Hub findings" \
        --output table > /dev/null
    
    # Add Lambda as target for high severity rule
    aws events put-targets \
        --rule security-hub-high-severity \
        --targets Id=1,Arn="${LAMBDA_ARN}" \
        --output table > /dev/null
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id security-hub-high-severity \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/security-hub-high-severity" \
        --output table > /dev/null
    
    success "EventBridge rules created"
}

# Function to create custom actions and automation rules
create_security_hub_automation() {
    log "Creating Security Hub custom actions and automation rules..."
    
    # Create custom action in Security Hub
    local custom_action_arn=$(aws securityhub create-action-target \
        --name "Escalate to SOC" \
        --description "Escalate this finding to the Security Operations Center" \
        --id "${CUSTOM_ACTION_NAME}" \
        --query ActionTargetArn --output text)
    
    export CUSTOM_ACTION_ARN="$custom_action_arn"
    
    # Add custom action ARN to state file
    echo "CUSTOM_ACTION_ARN=${CUSTOM_ACTION_ARN}" >> /tmp/security-hub-deployment-state.env
    
    # Create EventBridge rule for custom action
    aws events put-rule \
        --name security-hub-custom-escalation \
        --event-pattern '{
            "source": ["aws.securityhub"],
            "detail-type": ["Security Hub Findings - Custom Action"],
            "detail": {
                "actionName": ["Escalate to SOC"],
                "actionDescription": ["Escalate this finding to the Security Operations Center"]
            }
        }' \
        --state ENABLED \
        --description "Process manual escalation from Security Hub" \
        --output table > /dev/null
    
    # Add Lambda as target for custom action rule
    aws events put-targets \
        --rule security-hub-custom-escalation \
        --targets Id=1,Arn="${LAMBDA_ARN}" \
        --output table > /dev/null
    
    # Grant EventBridge permission to invoke Lambda for custom action
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id security-hub-custom-escalation \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/security-hub-custom-escalation" \
        --output table > /dev/null
    
    # Create automation rules for intelligent triage
    aws securityhub create-automation-rule \
        --rule-name "Suppress Low Priority Findings" \
        --description "Automatically suppress informational findings from specific controls" \
        --rule-order 1 \
        --rule-status ENABLED \
        --criteria '{
            "SeverityLabel": [{"Value": "INFORMATIONAL", "Comparison": "EQUALS"}],
            "GeneratorId": [{"Value": "aws-foundational-security-best-practices", "Comparison": "PREFIX"}]
        }' \
        --actions '[{
            "Type": "FINDING_FIELDS_UPDATE",
            "FindingFieldsUpdate": {
                "Note": {
                    "Text": "Low priority finding automatically suppressed by automation rule",
                    "UpdatedBy": "SecurityHubAutomation"
                },
                "Workflow": {
                    "Status": "SUPPRESSED"
                }
            }
        }]' \
        --output table > /dev/null
    
    aws securityhub create-automation-rule \
        --rule-name "Escalate Critical Findings" \
        --description "Automatically escalate critical findings and add priority notes" \
        --rule-order 2 \
        --rule-status ENABLED \
        --criteria '{
            "SeverityLabel": [{"Value": "CRITICAL", "Comparison": "EQUALS"}],
            "Workflow": {
                "Status": [{"Value": "NEW", "Comparison": "EQUALS"}]
            }
        }' \
        --actions '[{
            "Type": "FINDING_FIELDS_UPDATE",
            "FindingFieldsUpdate": {
                "Note": {
                    "Text": "CRITICAL: Immediate attention required. Escalated to SOC automatically.",
                    "UpdatedBy": "SecurityHubAutomation"
                },
                "Workflow": {
                    "Status": "NOTIFIED"
                }
            }
        }]' \
        --output table > /dev/null
    
    success "Security Hub automation configured"
}

# Function to create monitoring and alerting
create_monitoring() {
    log "Creating CloudWatch monitoring and alerting..."
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name SecurityHubIncidentResponse \
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
                            ["AWS/Lambda", "Invocations", "FunctionName", "'${LAMBDA_FUNCTION_NAME}'"],
                            ["AWS/Lambda", "Errors", "FunctionName", "'${LAMBDA_FUNCTION_NAME}'"],
                            ["AWS/Lambda", "Duration", "FunctionName", "'${LAMBDA_FUNCTION_NAME}'"]
                        ],
                        "period": 300,
                        "stat": "Sum",
                        "region": "'${AWS_REGION}'",
                        "title": "Security Incident Processing Metrics"
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
                            ["AWS/SNS", "NumberOfMessagesPublished", "TopicName", "'${SNS_TOPIC_NAME}'"],
                            ["AWS/SNS", "NumberOfNotificationsFailed", "TopicName", "'${SNS_TOPIC_NAME}'"]
                        ],
                        "period": 300,
                        "stat": "Sum",
                        "region": "'${AWS_REGION}'",
                        "title": "Notification Delivery Metrics"
                    }
                }
            ]
        }' \
        --output table > /dev/null
    
    # Create CloudWatch alarm for failed incident processing
    aws cloudwatch put-metric-alarm \
        --alarm-name SecurityHubIncidentProcessingFailures \
        --alarm-description "Alert when Security Hub incident processing fails" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=FunctionName,Value="${LAMBDA_FUNCTION_NAME}" \
        --output table > /dev/null
    
    success "Monitoring and alerting configured"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check Security Hub status
    if aws securityhub describe-hub --region "$AWS_REGION" &> /dev/null; then
        success "Security Hub is enabled and accessible"
    else
        error "Security Hub validation failed"
        return 1
    fi
    
    # Check Lambda functions
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        success "Main Lambda function deployed successfully"
    else
        error "Main Lambda function validation failed"
        return 1
    fi
    
    if aws lambda get-function --function-name "$THREAT_INTEL_FUNCTION_NAME" &> /dev/null; then
        success "Threat intelligence Lambda function deployed successfully"
    else
        error "Threat intelligence Lambda function validation failed"
        return 1
    fi
    
    # Check SNS topic
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &> /dev/null; then
        success "SNS topic created successfully"
    else
        error "SNS topic validation failed"
        return 1
    fi
    
    # Check SQS queue
    if aws sqs get-queue-attributes --queue-url "$QUEUE_URL" &> /dev/null; then
        success "SQS queue created successfully"
    else
        error "SQS queue validation failed"
        return 1
    fi
    
    # Check EventBridge rules
    if aws events describe-rule --name security-hub-high-severity &> /dev/null; then
        success "EventBridge rules created successfully"
    else
        error "EventBridge rules validation failed"
        return 1
    fi
    
    success "All components validated successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo ""
    echo "Security Hub Status: Enabled"
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account ID: $AWS_ACCOUNT_ID"
    echo ""
    echo "Created Resources:"
    echo "- IAM Roles:"
    echo "  - Security Hub Role: $SECURITY_HUB_ROLE_NAME"
    echo "  - Lambda Role: $LAMBDA_ROLE_NAME"
    echo "- Lambda Functions:"
    echo "  - Incident Processor: $LAMBDA_FUNCTION_NAME"
    echo "  - Threat Intelligence: $THREAT_INTEL_FUNCTION_NAME"
    echo "- Messaging:"
    echo "  - SNS Topic: $SNS_TOPIC_NAME"
    echo "  - SNS Topic ARN: $SNS_TOPIC_ARN"
    echo "  - SQS Queue: $SQS_QUEUE_NAME"
    echo "- Security Hub:"
    echo "  - Custom Action: Escalate to SOC"
    echo "  - Automation Rules: 2 rules created"
    echo "- EventBridge Rules:"
    echo "  - High Severity Processing: security-hub-high-severity"
    echo "  - Custom Action Processing: security-hub-custom-escalation"
    echo "- Monitoring:"
    echo "  - CloudWatch Dashboard: SecurityHubIncidentResponse"
    echo "  - CloudWatch Alarm: SecurityHubIncidentProcessingFailures"
    echo ""
    echo "Deployment state saved to: /tmp/security-hub-deployment-state.env"
    echo ""
    success "Security incident response system deployed successfully!"
    echo ""
    echo "Next Steps:"
    echo "1. Subscribe to SNS notifications for alerts"
    echo "2. Test the system with sample findings"
    echo "3. Configure external integrations (JIRA, Slack, etc.)"
    echo "4. Review and customize automation rules as needed"
}

# Main deployment function
main() {
    log "Starting Security Hub Incident Response deployment..."
    
    # Run deployment steps
    check_prerequisites
    initialize_environment
    create_iam_roles
    enable_security_hub
    create_messaging_infrastructure
    create_lambda_functions
    create_eventbridge_rules
    create_security_hub_automation
    create_monitoring
    validate_deployment
    display_summary
    
    success "Deployment completed successfully!"
}

# Execute main function
main "$@"