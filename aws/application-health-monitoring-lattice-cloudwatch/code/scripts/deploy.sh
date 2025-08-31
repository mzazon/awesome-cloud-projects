#!/bin/bash

#####################################################################
# AWS Application Health Monitoring with VPC Lattice and CloudWatch
# Deployment Script
# 
# This script deploys a comprehensive health monitoring system using
# VPC Lattice service metrics, CloudWatch alarms, and Lambda functions
# to detect unhealthy services and trigger auto-remediation workflows.
#####################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly RESOURCE_FILE="${SCRIPT_DIR}/deployed_resources.env"

# Email configuration (optional)
EMAIL_ENDPOINT=""

#####################################################################
# Utility Functions
#####################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

cleanup_on_error() {
    log "ERROR" "Deployment failed. Starting cleanup..."
    if [[ -f "$RESOURCE_FILE" ]]; then
        source "$RESOURCE_FILE"
        cleanup_resources
    fi
    exit 1
}

wait_for_resource() {
    local resource_type="$1"
    local resource_id="$2"
    local max_attempts=30
    local attempt=1
    
    log "INFO" "Waiting for $resource_type $resource_id to be ready..."
    
    while [[ $attempt -le $max_attempts ]]; do
        case $resource_type in
            "service-network")
                local status=$(aws vpc-lattice get-service-network \
                    --service-network-identifier "$resource_id" \
                    --query "status" --output text 2>/dev/null || echo "UNKNOWN")
                ;;
            "service")
                local status=$(aws vpc-lattice get-service \
                    --service-identifier "$resource_id" \
                    --query "status" --output text 2>/dev/null || echo "UNKNOWN")
                ;;
            "lambda")
                local status=$(aws lambda get-function \
                    --function-name "$resource_id" \
                    --query "Configuration.State" --output text 2>/dev/null || echo "UNKNOWN")
                ;;
        esac
        
        if [[ "$status" == "ACTIVE" ]] || [[ "$status" == "Active" ]]; then
            log "INFO" "$resource_type $resource_id is ready"
            return 0
        fi
        
        log "DEBUG" "$resource_type status: $status (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    log "ERROR" "Timeout waiting for $resource_type $resource_id to be ready"
    return 1
}

#####################################################################
# Prerequisites Check
#####################################################################

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version | cut -d/ -f2 | cut -d' ' -f1)
    log "INFO" "AWS CLI version: $aws_version"
    
    # Test AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check for required utilities
    for util in zip jq; do
        if ! command -v "$util" &> /dev/null; then
            log "ERROR" "$util is not installed. Please install $util."
            exit 1
        fi
    done
    
    # Check VPC Lattice availability
    local region=$(aws configure get region)
    if ! aws vpc-lattice list-service-networks --max-results 1 &> /dev/null; then
        log "ERROR" "VPC Lattice is not available in region $region or insufficient permissions"
        exit 1
    fi
    
    log "INFO" "Prerequisites check completed successfully"
}

#####################################################################
# Environment Setup
#####################################################################

setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Export AWS environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set resource names
    export SERVICE_NETWORK_NAME="health-monitor-network-${random_suffix}"
    export SERVICE_NAME="demo-service-${random_suffix}"
    export TARGET_GROUP_NAME="demo-targets-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="health-remediation-${random_suffix}"
    export SNS_TOPIC_NAME="health-alerts-${random_suffix}"
    export IAM_ROLE_NAME="HealthRemediationRole-${random_suffix}"
    export IAM_POLICY_NAME="HealthRemediationPolicy-${random_suffix}"
    export DASHBOARD_NAME="VPCLattice-Health-${random_suffix}"
    export RANDOM_SUFFIX="$random_suffix"
    
    # Get VPC information (using default VPC for demo)
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text)
    
    if [[ "$VPC_ID" == "None" || "$VPC_ID" == "null" ]]; then
        log "ERROR" "No default VPC found. Please create a VPC or specify an existing VPC ID."
        exit 1
    fi
    
    # Get subnet IDs from default VPC
    local subnet_ids=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query "Subnets[0:2].SubnetId" --output text)
    export SUBNET_1=$(echo ${subnet_ids} | cut -d' ' -f1)
    export SUBNET_2=$(echo ${subnet_ids} | cut -d' ' -f2)
    
    # Save environment variables to file for cleanup script
    cat > "$RESOURCE_FILE" << EOF
# Deployed resources for VPC Lattice Health Monitoring
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export VPC_ID="$VPC_ID"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
export SERVICE_NETWORK_NAME="$SERVICE_NETWORK_NAME"
export SERVICE_NAME="$SERVICE_NAME"
export TARGET_GROUP_NAME="$TARGET_GROUP_NAME"
export LAMBDA_FUNCTION_NAME="$LAMBDA_FUNCTION_NAME"
export SNS_TOPIC_NAME="$SNS_TOPIC_NAME"
export IAM_ROLE_NAME="$IAM_ROLE_NAME"
export IAM_POLICY_NAME="$IAM_POLICY_NAME"
export DASHBOARD_NAME="$DASHBOARD_NAME"
EOF
    
    log "INFO" "Environment configured for VPC $VPC_ID in region $AWS_REGION"
    log "INFO" "Using subnets: $SUBNET_1, $SUBNET_2"
}

#####################################################################
# VPC Lattice Setup
#####################################################################

create_vpc_lattice_resources() {
    log "INFO" "Creating VPC Lattice resources..."
    
    # Create VPC Lattice service network
    log "INFO" "Creating VPC Lattice service network: $SERVICE_NETWORK_NAME"
    aws vpc-lattice create-service-network \
        --name "$SERVICE_NETWORK_NAME" \
        --auth-type "AWS_IAM" \
        --tags "Environment=demo,Purpose=health-monitoring,Project=vpc-lattice-monitoring"
    
    # Get service network ID
    export SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
        --query "items[?name=='${SERVICE_NETWORK_NAME}'].id" \
        --output text)
    
    if [[ -z "$SERVICE_NETWORK_ID" || "$SERVICE_NETWORK_ID" == "None" ]]; then
        log "ERROR" "Failed to create or retrieve service network ID"
        return 1
    fi
    
    echo "export SERVICE_NETWORK_ID=\"$SERVICE_NETWORK_ID\"" >> "$RESOURCE_FILE"
    wait_for_resource "service-network" "$SERVICE_NETWORK_ID"
    
    # Associate VPC with service network
    log "INFO" "Associating VPC $VPC_ID with service network"
    aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier "$SERVICE_NETWORK_ID" \
        --vpc-identifier "$VPC_ID" \
        --tags "Environment=demo,Project=vpc-lattice-monitoring"
    
    # Create target group with health check configuration
    log "INFO" "Creating target group: $TARGET_GROUP_NAME"
    aws vpc-lattice create-target-group \
        --name "$TARGET_GROUP_NAME" \
        --type "INSTANCE" \
        --protocol "HTTP" \
        --port 80 \
        --vpc-identifier "$VPC_ID" \
        --health-check-config '{
            "enabled": true,
            "protocol": "HTTP",
            "port": 80,
            "path": "/health",
            "healthCheckIntervalSeconds": 30,
            "healthCheckTimeoutSeconds": 5,
            "healthyThresholdCount": 2,
            "unhealthyThresholdCount": 2
        }' \
        --tags "Environment=demo,Purpose=health-monitoring,Project=vpc-lattice-monitoring"
    
    # Get target group ID
    export TARGET_GROUP_ID=$(aws vpc-lattice list-target-groups \
        --query "items[?name=='${TARGET_GROUP_NAME}'].id" \
        --output text)
    
    echo "export TARGET_GROUP_ID=\"$TARGET_GROUP_ID\"" >> "$RESOURCE_FILE"
    log "INFO" "Target group created with health checks: $TARGET_GROUP_ID"
    
    # Create VPC Lattice service
    log "INFO" "Creating VPC Lattice service: $SERVICE_NAME"
    aws vpc-lattice create-service \
        --name "$SERVICE_NAME" \
        --auth-type "AWS_IAM" \
        --tags "Environment=demo,Purpose=health-monitoring,Project=vpc-lattice-monitoring"
    
    # Get service ID
    export SERVICE_ID=$(aws vpc-lattice list-services \
        --query "items[?name=='${SERVICE_NAME}'].id" \
        --output text)
    
    echo "export SERVICE_ID=\"$SERVICE_ID\"" >> "$RESOURCE_FILE"
    wait_for_resource "service" "$SERVICE_ID"
    
    # Create service association with service network
    log "INFO" "Associating service with service network"
    aws vpc-lattice create-service-network-service-association \
        --service-network-identifier "$SERVICE_NETWORK_ID" \
        --service-identifier "$SERVICE_ID"
    
    # Create listener for HTTP traffic
    log "INFO" "Creating HTTP listener for service"
    aws vpc-lattice create-listener \
        --service-identifier "$SERVICE_ID" \
        --name "http-listener" \
        --protocol "HTTP" \
        --port 80 \
        --default-action "{
            \"type\": \"FORWARD\",
            \"forward\": {
                \"targetGroups\": [{
                    \"targetGroupIdentifier\": \"${TARGET_GROUP_ID}\",
                    \"weight\": 100
                }]
            }
        }"
    
    log "INFO" "VPC Lattice resources created successfully"
}

#####################################################################
# SNS Setup
#####################################################################

create_sns_topic() {
    log "INFO" "Creating SNS topic: $SNS_TOPIC_NAME"
    
    aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --attributes "DisplayName=Application Health Alerts"
    
    # Get topic ARN
    export SNS_TOPIC_ARN=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn,'${SNS_TOPIC_NAME}')].TopicArn" \
        --output text)
    
    echo "export SNS_TOPIC_ARN=\"$SNS_TOPIC_ARN\"" >> "$RESOURCE_FILE"
    log "INFO" "SNS topic created: $SNS_TOPIC_ARN"
    
    # Subscribe email if provided
    if [[ -n "$EMAIL_ENDPOINT" ]]; then
        log "INFO" "Subscribing email $EMAIL_ENDPOINT to SNS topic"
        aws sns subscribe \
            --topic-arn "$SNS_TOPIC_ARN" \
            --protocol "email" \
            --notification-endpoint "$EMAIL_ENDPOINT"
        log "INFO" "Email subscription created. Please check your email and confirm the subscription."
    else
        log "INFO" "To receive notifications, subscribe your email:"
        log "INFO" "aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol email --notification-endpoint your-email@example.com"
    fi
}

#####################################################################
# Lambda Function Setup
#####################################################################

create_lambda_function() {
    log "INFO" "Creating Lambda function for auto-remediation..."
    
    # Create Lambda execution role
    log "INFO" "Creating IAM role: $IAM_ROLE_NAME"
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "lambda.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        --tags "Key=Environment,Value=demo" "Key=Project,Value=vpc-lattice-monitoring"
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Create policy for VPC Lattice and SNS access
    local policy_document='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "vpc-lattice:*",
                    "sns:Publish",
                    "cloudwatch:GetMetricStatistics",
                    "ec2:DescribeInstances",
                    "ec2:RebootInstances"
                ],
                "Resource": "*"
            }
        ]
    }'
    
    export POLICY_ARN=$(aws iam create-policy \
        --policy-name "$IAM_POLICY_NAME" \
        --policy-document "$policy_document" \
        --query "Policy.Arn" --output text)
    
    echo "export POLICY_ARN=\"$POLICY_ARN\"" >> "$RESOURCE_FILE"
    
    # Attach custom policy to role
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "$POLICY_ARN"
    
    # Get role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "$IAM_ROLE_NAME" \
        --query "Role.Arn" --output text)
    
    echo "export LAMBDA_ROLE_ARN=\"$LAMBDA_ROLE_ARN\"" >> "$RESOURCE_FILE"
    log "INFO" "IAM role created: $LAMBDA_ROLE_ARN"
    
    # Wait for IAM role to propagate
    sleep 10
    
    # Create Lambda function code
    log "INFO" "Creating Lambda function code"
    cat > "${SCRIPT_DIR}/lambda_function.py" << 'EOF'
import json
import boto3
import os
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Auto-remediation function for VPC Lattice health issues
    """
    try:
        # Parse CloudWatch alarm data
        message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = message['AlarmName']
        alarm_state = message['NewStateValue']
        
        logger.info(f"Processing alarm: {alarm_name}, State: {alarm_state}")
        
        if alarm_state == 'ALARM':
            # Determine remediation action based on alarm type
            if '5XX' in alarm_name:
                remediate_error_rate(message)
            elif 'Timeout' in alarm_name:
                remediate_timeouts(message)
            elif 'ResponseTime' in alarm_name:
                remediate_performance(message)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Processed alarm: {alarm_name}')
        }
        
    except Exception as e:
        logger.error(f"Error processing alarm: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def remediate_error_rate(alarm_data):
    """Handle high error rate alarms"""
    logger.info("Implementing error rate remediation")
    
    # In a real implementation, you would:
    # 1. Identify unhealthy targets
    # 2. Remove them from the target group
    # 3. Trigger instance replacement
    # 4. Notify operations team
    
    send_notification(
        "🚨 High Error Rate Detected",
        f"Alarm: {alarm_data['AlarmName']}\n"
        f"Action: Investigating unhealthy targets\n"
        f"Time: {alarm_data['StateChangeTime']}"
    )

def remediate_timeouts(alarm_data):
    """Handle timeout alarms"""
    logger.info("Implementing timeout remediation")
    
    send_notification(
        "⏰ Request Timeouts Detected", 
        f"Alarm: {alarm_data['AlarmName']}\n"
        f"Action: Checking target capacity\n"
        f"Time: {alarm_data['StateChangeTime']}"
    )

def remediate_performance(alarm_data):
    """Handle performance degradation"""
    logger.info("Implementing performance remediation")
    
    send_notification(
        "📉 Performance Degradation Detected",
        f"Alarm: {alarm_data['AlarmName']}\n"
        f"Action: Analyzing response times\n"
        f"Time: {alarm_data['StateChangeTime']}"
    )

def send_notification(subject, message):
    """Send SNS notification"""
    try:
        sns = boto3.client('sns')
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=subject,
            Message=message
        )
        logger.info("Notification sent successfully")
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")
EOF
    
    # Create deployment package
    cd "$SCRIPT_DIR"
    zip lambda_function.zip lambda_function.py
    
    # Create Lambda function
    log "INFO" "Creating Lambda function: $LAMBDA_FUNCTION_NAME"
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime "python3.12" \
        --role "$LAMBDA_ROLE_ARN" \
        --handler "lambda_function.lambda_handler" \
        --zip-file "fileb://lambda_function.zip" \
        --timeout 60 \
        --memory-size 256 \
        --environment "Variables={SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}" \
        --description "Auto-remediation for VPC Lattice health monitoring" \
        --tags "Environment=demo,Project=vpc-lattice-monitoring"
    
    # Get Lambda function ARN
    export LAMBDA_ARN=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query "Configuration.FunctionArn" --output text)
    
    echo "export LAMBDA_ARN=\"$LAMBDA_ARN\"" >> "$RESOURCE_FILE"
    wait_for_resource "lambda" "$LAMBDA_FUNCTION_NAME"
    log "INFO" "Lambda function created: $LAMBDA_ARN"
    
    # Subscribe Lambda function to SNS topic
    log "INFO" "Subscribing Lambda function to SNS topic"
    aws sns subscribe \
        --topic-arn "$SNS_TOPIC_ARN" \
        --protocol "lambda" \
        --notification-endpoint "$LAMBDA_ARN"
    
    # Grant SNS permission to invoke Lambda function
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id "allow-sns-invoke-$(date +%s)" \
        --action "lambda:InvokeFunction" \
        --principal "sns.amazonaws.com" \
        --source-arn "$SNS_TOPIC_ARN"
    
    log "INFO" "Lambda function integration completed"
}

#####################################################################
# CloudWatch Setup
#####################################################################

create_cloudwatch_resources() {
    log "INFO" "Creating CloudWatch alarms and dashboard..."
    
    # Create alarm for high 5XX error rate
    log "INFO" "Creating CloudWatch alarm for 5XX errors"
    aws cloudwatch put-metric-alarm \
        --alarm-name "VPCLattice-${SERVICE_NAME}-High5XXRate" \
        --alarm-description "High 5XX error rate detected" \
        --metric-name "HTTPCode_5XX_Count" \
        --namespace "AWS/VpcLattice" \
        --statistic "Sum" \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 10 \
        --comparison-operator "GreaterThanThreshold" \
        --dimensions "Name=Service,Value=${SERVICE_ID}" \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --ok-actions "$SNS_TOPIC_ARN" \
        --treat-missing-data "notBreaching"
    
    # Create alarm for request timeouts
    log "INFO" "Creating CloudWatch alarm for timeouts"
    aws cloudwatch put-metric-alarm \
        --alarm-name "VPCLattice-${SERVICE_NAME}-RequestTimeouts" \
        --alarm-description "High request timeout rate detected" \
        --metric-name "RequestTimeoutCount" \
        --namespace "AWS/VpcLattice" \
        --statistic "Sum" \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 5 \
        --comparison-operator "GreaterThanThreshold" \
        --dimensions "Name=Service,Value=${SERVICE_ID}" \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --ok-actions "$SNS_TOPIC_ARN" \
        --treat-missing-data "notBreaching"
    
    # Create alarm for high response times
    log "INFO" "Creating CloudWatch alarm for response times"
    aws cloudwatch put-metric-alarm \
        --alarm-name "VPCLattice-${SERVICE_NAME}-HighResponseTime" \
        --alarm-description "High response time detected" \
        --metric-name "RequestTime" \
        --namespace "AWS/VpcLattice" \
        --statistic "Average" \
        --period 300 \
        --evaluation-periods 3 \
        --threshold 2000 \
        --comparison-operator "GreaterThanThreshold" \
        --dimensions "Name=Service,Value=${SERVICE_ID}" \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --treat-missing-data "notBreaching"
    
    # Create CloudWatch dashboard
    log "INFO" "Creating CloudWatch dashboard: $DASHBOARD_NAME"
    local dashboard_body="{
        \"widgets\": [
            {
                \"type\": \"metric\",
                \"x\": 0, \"y\": 0, \"width\": 12, \"height\": 6,
                \"properties\": {
                    \"metrics\": [
                        [\"AWS/VpcLattice\", \"HTTPCode_2XX_Count\", \"Service\", \"${SERVICE_ID}\"],
                        [\"AWS/VpcLattice\", \"HTTPCode_4XX_Count\", \"Service\", \"${SERVICE_ID}\"],
                        [\"AWS/VpcLattice\", \"HTTPCode_5XX_Count\", \"Service\", \"${SERVICE_ID}\"]
                    ],
                    \"period\": 300,
                    \"stat\": \"Sum\",
                    \"region\": \"${AWS_REGION}\",
                    \"title\": \"HTTP Response Codes\"
                }
            },
            {
                \"type\": \"metric\",
                \"x\": 12, \"y\": 0, \"width\": 12, \"height\": 6,
                \"properties\": {
                    \"metrics\": [
                        [\"AWS/VpcLattice\", \"RequestTime\", \"Service\", \"${SERVICE_ID}\"]
                    ],
                    \"period\": 300,
                    \"stat\": \"Average\",
                    \"region\": \"${AWS_REGION}\",
                    \"title\": \"Request Response Time\"
                }
            },
            {
                \"type\": \"metric\",
                \"x\": 0, \"y\": 6, \"width\": 12, \"height\": 6,
                \"properties\": {
                    \"metrics\": [
                        [\"AWS/VpcLattice\", \"TotalRequestCount\", \"Service\", \"${SERVICE_ID}\"],
                        [\"AWS/VpcLattice\", \"RequestTimeoutCount\", \"Service\", \"${SERVICE_ID}\"]
                    ],
                    \"period\": 300,
                    \"stat\": \"Sum\",
                    \"region\": \"${AWS_REGION}\",
                    \"title\": \"Request Volume and Timeouts\"
                }
            }
        ]
    }"
    
    aws cloudwatch put-dashboard \
        --dashboard-name "$DASHBOARD_NAME" \
        --dashboard-body "$dashboard_body"
    
    log "INFO" "CloudWatch resources created successfully"
    log "INFO" "Dashboard URL: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
}

#####################################################################
# Validation
#####################################################################

validate_deployment() {
    log "INFO" "Validating deployment..."
    
    # Check VPC Lattice service network
    local service_network_status=$(aws vpc-lattice get-service-network \
        --service-network-identifier "$SERVICE_NETWORK_ID" \
        --query "status" --output text)
    
    if [[ "$service_network_status" == "ACTIVE" ]]; then
        log "INFO" "✅ Service network is active"
    else
        log "WARN" "⚠️  Service network status: $service_network_status"
    fi
    
    # Check VPC Lattice service
    local service_status=$(aws vpc-lattice get-service \
        --service-identifier "$SERVICE_ID" \
        --query "status" --output text)
    
    if [[ "$service_status" == "ACTIVE" ]]; then
        log "INFO" "✅ VPC Lattice service is active"
    else
        log "WARN" "⚠️  Service status: $service_status"
    fi
    
    # Check Lambda function
    local lambda_state=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query "Configuration.State" --output text)
    
    if [[ "$lambda_state" == "Active" ]]; then
        log "INFO" "✅ Lambda function is active"
    else
        log "WARN" "⚠️  Lambda function state: $lambda_state"
    fi
    
    # Test SNS topic
    log "INFO" "Testing SNS notifications..."
    aws sns publish \
        --topic-arn "$SNS_TOPIC_ARN" \
        --subject "Health Monitoring Deployment Test" \
        --message "VPC Lattice health monitoring system deployed successfully at $(date)"
    
    log "INFO" "✅ SNS test notification sent"
    log "INFO" "Deployment validation completed"
}

#####################################################################
# Main Deployment Function
#####################################################################

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -e, --email EMAIL    Email address for SNS notifications"
    echo "  -h, --help          Show this help message"
    echo "  --dry-run           Show what would be done without executing"
    echo
    echo "Examples:"
    echo "  $0"
    echo "  $0 --email admin@example.com"
    echo "  $0 --dry-run"
}

main() {
    local dry_run=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--email)
                EMAIL_ENDPOINT="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    if [[ "$dry_run" == "true" ]]; then
        log "INFO" "DRY RUN MODE - No resources will be created"
        log "INFO" "Would deploy VPC Lattice health monitoring system"
        log "INFO" "Resources that would be created:"
        log "INFO" "  - VPC Lattice Service Network"
        log "INFO" "  - VPC Lattice Service and Target Group"
        log "INFO" "  - SNS Topic for notifications"
        log "INFO" "  - Lambda function for auto-remediation"
        log "INFO" "  - CloudWatch alarms and dashboard"
        exit 0
    fi
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Initialize log file
    echo "# VPC Lattice Health Monitoring Deployment Log" > "$LOG_FILE"
    echo "# Started at: $(date)" >> "$LOG_FILE"
    
    log "INFO" "Starting VPC Lattice Health Monitoring deployment..."
    log "INFO" "Log file: $LOG_FILE"
    log "INFO" "Resource file: $RESOURCE_FILE"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_vpc_lattice_resources
    create_sns_topic
    create_lambda_function
    create_cloudwatch_resources
    validate_deployment
    
    # Cleanup temporary files
    rm -f "${SCRIPT_DIR}/lambda_function.py"
    rm -f "${SCRIPT_DIR}/lambda_function.zip"
    
    log "INFO" "🎉 Deployment completed successfully!"
    log "INFO" ""
    log "INFO" "Resources created:"
    log "INFO" "  Service Network: $SERVICE_NETWORK_NAME ($SERVICE_NETWORK_ID)"
    log "INFO" "  Service: $SERVICE_NAME ($SERVICE_ID)"
    log "INFO" "  Target Group: $TARGET_GROUP_NAME ($TARGET_GROUP_ID)"
    log "INFO" "  Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "INFO" "  SNS Topic: $SNS_TOPIC_NAME"
    log "INFO" "  CloudWatch Dashboard: $DASHBOARD_NAME"
    log "INFO" ""
    log "INFO" "Next steps:"
    log "INFO" "  1. Add targets to the target group to start monitoring"
    log "INFO" "  2. Subscribe to SNS topic for notifications"
    log "INFO" "  3. View the CloudWatch dashboard for metrics"
    log "INFO" ""
    log "INFO" "Dashboard URL:"
    log "INFO" "  https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
    log "INFO" ""
    log "INFO" "To clean up all resources, run: ./destroy.sh"
}

# Execute main function with all arguments
main "$@"