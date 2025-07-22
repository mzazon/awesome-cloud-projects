#!/bin/bash

# Deploy script for Monitoring Network Traffic with VPC Flow Logs
# This script creates a comprehensive network monitoring system using VPC Flow Logs,
# CloudWatch, S3, and Athena for real-time alerting and advanced analytics.

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_NAME="deploy.sh"
LOG_FILE="/tmp/vpc-flow-logs-deploy-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to handle errors
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Deployment failed. Check log file: $LOG_FILE"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "INFO" "AWS CLI version: $aws_version"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or use AWS IAM roles."
    fi
    
    local caller_identity=$(aws sts get-caller-identity 2>/dev/null)
    local account_id=$(echo "$caller_identity" | jq -r '.Account')
    local user_arn=$(echo "$caller_identity" | jq -r '.Arn')
    log "INFO" "AWS Account ID: $account_id"
    log "INFO" "AWS User/Role: $user_arn"
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install jq for JSON parsing."
    fi
    
    # Check required permissions (basic check)
    log "INFO" "Checking AWS permissions..."
    if ! aws ec2 describe-vpcs --max-items 1 &> /dev/null; then
        error_exit "Insufficient EC2 permissions. Ensure you have VPC, CloudWatch, S3, and Athena permissions."
    fi
    
    log "INFO" "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log "WARN" "AWS region not configured, defaulting to us-east-1"
    fi
    log "INFO" "AWS Region: $AWS_REGION"
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log "INFO" "AWS Account ID: $AWS_ACCOUNT_ID"
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export VPC_FLOW_LOGS_BUCKET="vpc-flow-logs-${AWS_ACCOUNT_ID}-${RANDOM_SUFFIX}"
    export FLOW_LOGS_GROUP="/aws/vpc/flowlogs"
    export FLOW_LOGS_ROLE_NAME="VPCFlowLogsRole-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="network-monitoring-alerts-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="network-anomaly-detector-${RANDOM_SUFFIX}"
    
    # Get default VPC ID
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
    
    if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
        log "WARN" "No default VPC found. Will use the first available VPC."
        export VPC_ID=$(aws ec2 describe-vpcs \
            --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
    fi
    
    if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
        error_exit "No VPC found in region $AWS_REGION. Please create a VPC first."
    fi
    
    log "INFO" "Environment configured successfully"
    log "INFO" "VPC ID: $VPC_ID"
    log "INFO" "S3 Bucket: $VPC_FLOW_LOGS_BUCKET"
    log "INFO" "Random Suffix: $RANDOM_SUFFIX"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "INFO" "Creating S3 bucket for VPC Flow Logs..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would create S3 bucket: $VPC_FLOW_LOGS_BUCKET"
        return
    fi
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$VPC_FLOW_LOGS_BUCKET" 2>/dev/null; then
        log "WARN" "S3 bucket $VPC_FLOW_LOGS_BUCKET already exists"
        return
    fi
    
    # Create S3 bucket with region-specific configuration
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$VPC_FLOW_LOGS_BUCKET" --region "$AWS_REGION"
    else
        aws s3api create-bucket \
            --bucket "$VPC_FLOW_LOGS_BUCKET" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$VPC_FLOW_LOGS_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Create lifecycle policy for cost optimization
    cat > /tmp/lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "FlowLogsLifecycle",
            "Status": "Enabled",
            "Filter": {"Prefix": "vpc-flow-logs/"},
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 365,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ]
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$VPC_FLOW_LOGS_BUCKET" \
        --lifecycle-configuration file:///tmp/lifecycle-policy.json
    
    log "INFO" "S3 bucket created and configured successfully"
}

# Function to create IAM role
create_iam_role() {
    log "INFO" "Creating IAM role for VPC Flow Logs..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would create IAM role: $FLOW_LOGS_ROLE_NAME"
        return
    fi
    
    # Check if role already exists
    if aws iam get-role --role-name "$FLOW_LOGS_ROLE_NAME" &>/dev/null; then
        log "WARN" "IAM role $FLOW_LOGS_ROLE_NAME already exists"
        export FLOW_LOGS_ROLE_ARN=$(aws iam get-role --role-name "$FLOW_LOGS_ROLE_NAME" --query 'Role.Arn' --output text)
        return
    fi
    
    # Create trust policy
    cat > /tmp/flow-logs-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "vpc-flow-logs.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "$FLOW_LOGS_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/flow-logs-trust-policy.json
    
    # Attach policy
    aws iam attach-role-policy \
        --role-name "$FLOW_LOGS_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/VPCFlowLogsDeliveryRolePolicy
    
    # Get role ARN
    export FLOW_LOGS_ROLE_ARN=$(aws iam get-role \
        --role-name "$FLOW_LOGS_ROLE_NAME" \
        --query 'Role.Arn' --output text)
    
    log "INFO" "IAM role created successfully: $FLOW_LOGS_ROLE_ARN"
    
    # Wait for role to propagate
    log "INFO" "Waiting for IAM role to propagate..."
    sleep 10
}

# Function to create CloudWatch Log Group
create_log_group() {
    log "INFO" "Creating CloudWatch Log Group..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would create CloudWatch Log Group: $FLOW_LOGS_GROUP"
        return
    fi
    
    # Check if log group already exists
    if aws logs describe-log-groups --log-group-name-prefix "$FLOW_LOGS_GROUP" \
        --query "logGroups[?logGroupName=='$FLOW_LOGS_GROUP']" --output text | grep -q "$FLOW_LOGS_GROUP"; then
        log "WARN" "CloudWatch Log Group $FLOW_LOGS_GROUP already exists"
        return
    fi
    
    # Create log group
    aws logs create-log-group --log-group-name "$FLOW_LOGS_GROUP"
    
    # Set retention period
    aws logs put-retention-policy \
        --log-group-name "$FLOW_LOGS_GROUP" \
        --retention-in-days 30
    
    # Add tags
    aws logs tag-log-group \
        --log-group-name "$FLOW_LOGS_GROUP" \
        --tags "Purpose=NetworkMonitoring,Environment=Production,CreatedBy=VPCFlowLogsRecipe"
    
    log "INFO" "CloudWatch Log Group created successfully"
}

# Function to create VPC Flow Logs
create_flow_logs() {
    log "INFO" "Creating VPC Flow Logs..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would create VPC Flow Logs for VPC: $VPC_ID"
        return
    fi
    
    # Create flow log for CloudWatch Logs
    export FLOW_LOG_CW_ID=$(aws ec2 create-flow-logs \
        --resource-type VPC \
        --resource-ids "$VPC_ID" \
        --traffic-type ALL \
        --log-destination-type cloud-watch-logs \
        --log-group-name "$FLOW_LOGS_GROUP" \
        --deliver-logs-permission-arn "$FLOW_LOGS_ROLE_ARN" \
        --max-aggregation-interval 60 \
        --query 'FlowLogIds[0]' --output text)
    
    # Create flow log for S3
    export FLOW_LOG_S3_ID=$(aws ec2 create-flow-logs \
        --resource-type VPC \
        --resource-ids "$VPC_ID" \
        --traffic-type ALL \
        --log-destination-type s3 \
        --log-destination "arn:aws:s3:::${VPC_FLOW_LOGS_BUCKET}/vpc-flow-logs/" \
        --log-format '${version} ${account-id} ${interface-id} ${srcaddr} ${dstaddr} ${srcport} ${dstport} ${protocol} ${packets} ${bytes} ${start} ${end} ${action} ${log-status} ${vpc-id} ${subnet-id} ${instance-id} ${tcp-flags} ${type} ${pkt-srcaddr} ${pkt-dstaddr}' \
        --max-aggregation-interval 60 \
        --query 'FlowLogIds[0]' --output text)
    
    log "INFO" "VPC Flow Logs created successfully"
    log "INFO" "CloudWatch Flow Log ID: $FLOW_LOG_CW_ID"
    log "INFO" "S3 Flow Log ID: $FLOW_LOG_S3_ID"
}

# Function to create SNS topic
create_sns_topic() {
    log "INFO" "Creating SNS topic for alerting..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would create SNS topic: $SNS_TOPIC_NAME"
        return
    fi
    
    # Create SNS topic
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query 'TopicArn' --output text)
    
    log "INFO" "SNS topic created successfully: $SNS_TOPIC_ARN"
    log "WARN" "Please manually subscribe your email address to the SNS topic for notifications"
    log "INFO" "Run: aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol email --notification-endpoint your-email@example.com"
}

# Function to create CloudWatch metrics and alarms
create_monitoring() {
    log "INFO" "Creating CloudWatch metric filters and alarms..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would create CloudWatch monitoring resources"
        return
    fi
    
    # Create metric filters
    aws logs put-metric-filter \
        --log-group-name "$FLOW_LOGS_GROUP" \
        --filter-name "RejectedConnections" \
        --filter-pattern '[version, account, eni, source, destination, srcport, destport, protocol, packets, bytes, windowstart, windowend, action="REJECT", flowlogstatus]' \
        --metric-transformations \
            metricName=RejectedConnections,metricNamespace=VPC/FlowLogs,metricValue=1
    
    aws logs put-metric-filter \
        --log-group-name "$FLOW_LOGS_GROUP" \
        --filter-name "HighDataTransfer" \
        --filter-pattern '[version, account, eni, source, destination, srcport, destport, protocol, packets, bytes>10000000, windowstart, windowend, action, flowlogstatus]' \
        --metric-transformations \
            metricName=HighDataTransfer,metricNamespace=VPC/FlowLogs,metricValue=1
    
    aws logs put-metric-filter \
        --log-group-name "$FLOW_LOGS_GROUP" \
        --filter-name "ExternalConnections" \
        --filter-pattern '[version, account, eni, source!="10.*" && source!="172.16.*" && source!="192.168.*", destination, srcport, destport, protocol, packets, bytes, windowstart, windowend, action, flowlogstatus]' \
        --metric-transformations \
            metricName=ExternalConnections,metricNamespace=VPC/FlowLogs,metricValue=1
    
    # Create CloudWatch alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "VPC-High-Rejected-Connections" \
        --alarm-description "Alert when rejected connections exceed threshold" \
        --metric-name RejectedConnections \
        --namespace VPC/FlowLogs \
        --statistic Sum \
        --period 300 \
        --threshold 50 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$SNS_TOPIC_ARN"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "VPC-High-Data-Transfer" \
        --alarm-description "Alert when high data transfer detected" \
        --metric-name HighDataTransfer \
        --namespace VPC/FlowLogs \
        --statistic Sum \
        --period 300 \
        --threshold 10 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$SNS_TOPIC_ARN"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "VPC-External-Connections" \
        --alarm-description "Alert when external connections exceed threshold" \
        --metric-name ExternalConnections \
        --namespace VPC/FlowLogs \
        --statistic Sum \
        --period 300 \
        --threshold 100 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$SNS_TOPIC_ARN"
    
    log "INFO" "CloudWatch monitoring resources created successfully"
}

# Function to create Lambda function
create_lambda_function() {
    log "INFO" "Creating Lambda function for anomaly detection..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would create Lambda function: $LAMBDA_FUNCTION_NAME"
        return
    fi
    
    # Create Lambda function code
    cat > /tmp/lambda-function.py << 'EOF'
import json
import boto3
import gzip
import base64
import os
from datetime import datetime

def lambda_handler(event, context):
    # Decode and decompress CloudWatch Logs data
    compressed_payload = base64.b64decode(event['awslogs']['data'])
    uncompressed_payload = gzip.decompress(compressed_payload)
    log_data = json.loads(uncompressed_payload)
    
    anomalies = []
    
    for log_event in log_data['logEvents']:
        message = log_event['message']
        fields = message.split(' ')
        
        if len(fields) >= 14:
            srcaddr = fields[3]
            dstaddr = fields[4]
            srcport = fields[5]
            dstport = fields[6]
            protocol = fields[7]
            bytes_transferred = int(fields[9]) if fields[9].isdigit() else 0
            action = fields[12]
            
            # Detect potential anomalies
            if bytes_transferred > 50000000:  # >50MB
                anomalies.append({
                    'type': 'high_data_transfer',
                    'source': srcaddr,
                    'destination': dstaddr,
                    'bytes': bytes_transferred
                })
            
            if action == 'REJECT' and protocol == '6':  # TCP rejects
                anomalies.append({
                    'type': 'rejected_tcp',
                    'source': srcaddr,
                    'destination': dstaddr,
                    'port': dstport
                })
    
    # Send notifications for anomalies
    if anomalies:
        sns = boto3.client('sns')
        message = f"Network anomalies detected: {json.dumps(anomalies, indent=2)}"
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=message,
            Subject='Network Anomaly Alert'
        )
    
    return {
        'statusCode': 200,
        'body': json.dumps('Analysis complete')
    }
EOF
    
    # Create deployment package
    cd /tmp
    zip lambda-function.zip lambda-function.py
    cd - > /dev/null
    
    # Create Lambda execution role policy
    cat > /tmp/lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "$SNS_TOPIC_ARN"
        }
    ]
}
EOF
    
    # Create Lambda execution role
    LAMBDA_ROLE_NAME="lambda-execution-role-${RANDOM_SUFFIX}"
    
    cat > /tmp/lambda-trust-policy.json << EOF
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
    
    aws iam create-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json
    
    aws iam put-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-name "LambdaExecutionPolicy" \
        --policy-document file:///tmp/lambda-policy.json
    
    LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "$LAMBDA_ROLE_NAME" --query 'Role.Arn' --output text)
    
    # Wait for role propagation
    sleep 10
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda-function.lambda_handler \
        --zip-file fileb:///tmp/lambda-function.zip \
        --environment "Variables={SNS_TOPIC_ARN=$SNS_TOPIC_ARN}" \
        --timeout 60
    
    log "INFO" "Lambda function created successfully"
}

# Function to create Athena workgroup
create_athena_workgroup() {
    log "INFO" "Creating Athena workgroup for analytics..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would create Athena workgroup"
        return
    fi
    
    # Create Athena workgroup
    aws athena create-work-group \
        --name "vpc-flow-logs-workgroup" \
        --description "Workgroup for VPC Flow Logs analysis" \
        --configuration "ResultConfiguration={OutputLocation=s3://${VPC_FLOW_LOGS_BUCKET}/athena-results/}"
    
    log "INFO" "Athena workgroup created successfully"
    log "INFO" "Note: Athena table creation will be available after flow logs data accumulates"
}

# Function to create CloudWatch dashboard
create_dashboard() {
    log "INFO" "Creating CloudWatch dashboard..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would create CloudWatch dashboard"
        return
    fi
    
    # Create dashboard configuration
    cat > /tmp/dashboard-config.json << EOF
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
                    ["VPC/FlowLogs", "RejectedConnections"],
                    [".", "HighDataTransfer"],
                    [".", "ExternalConnections"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "$AWS_REGION",
                "title": "Network Security Metrics",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '$FLOW_LOGS_GROUP' | fields @timestamp, @message\\n| filter @message like /REJECT/\\n| stats count() by bin(5m)",
                "region": "$AWS_REGION",
                "title": "Rejected Connections Over Time",
                "view": "table"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "VPC-Flow-Logs-Monitoring" \
        --dashboard-body file:///tmp/dashboard-config.json
    
    log "INFO" "CloudWatch dashboard created successfully"
}

# Function to save deployment state
save_deployment_state() {
    log "INFO" "Saving deployment state..."
    
    cat > /tmp/deployment-state.json << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "vpc_id": "$VPC_ID",
    "vpc_flow_logs_bucket": "$VPC_FLOW_LOGS_BUCKET",
    "flow_logs_group": "$FLOW_LOGS_GROUP",
    "flow_logs_role_name": "$FLOW_LOGS_ROLE_NAME",
    "flow_logs_role_arn": "$FLOW_LOGS_ROLE_ARN",
    "sns_topic_name": "$SNS_TOPIC_NAME",
    "sns_topic_arn": "$SNS_TOPIC_ARN",
    "lambda_function_name": "$LAMBDA_FUNCTION_NAME",
    "flow_log_cw_id": "$FLOW_LOG_CW_ID",
    "flow_log_s3_id": "$FLOW_LOG_S3_ID",
    "random_suffix": "$RANDOM_SUFFIX"
}
EOF
    
    cp /tmp/deployment-state.json ./vpc-flow-logs-deployment-state.json
    log "INFO" "Deployment state saved to: ./vpc-flow-logs-deployment-state.json"
}

# Function to print deployment summary
print_summary() {
    log "INFO" "Deployment completed successfully!"
    echo
    echo -e "${GREEN}=== VPC Flow Logs Network Monitoring Deployment Summary ===${NC}"
    echo -e "${BLUE}Region:${NC} $AWS_REGION"
    echo -e "${BLUE}VPC ID:${NC} $VPC_ID"
    echo -e "${BLUE}S3 Bucket:${NC} $VPC_FLOW_LOGS_BUCKET"
    echo -e "${BLUE}CloudWatch Log Group:${NC} $FLOW_LOGS_GROUP"
    echo -e "${BLUE}SNS Topic:${NC} $SNS_TOPIC_ARN"
    echo -e "${BLUE}Lambda Function:${NC} $LAMBDA_FUNCTION_NAME"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Subscribe to SNS topic for email notifications:"
    echo "   aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol email --notification-endpoint your-email@example.com"
    echo
    echo "2. View CloudWatch dashboard:"
    echo "   https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=VPC-Flow-Logs-Monitoring"
    echo
    echo "3. Monitor VPC Flow Logs in CloudWatch Logs:"
    echo "   https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#logsV2:log-groups/log-group/\$252Faws\$252Fvpc\$252Fflowlogs"
    echo
    echo "4. View flow logs data in S3:"
    echo "   aws s3 ls s3://$VPC_FLOW_LOGS_BUCKET/vpc-flow-logs/ --recursive"
    echo
    echo -e "${BLUE}Deployment log:${NC} $LOG_FILE"
    echo -e "${BLUE}Deployment state:${NC} ./vpc-flow-logs-deployment-state.json"
}

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Deploy VPC Flow Logs network monitoring infrastructure"
    echo
    echo "Options:"
    echo "  --dry-run    Show what would be deployed without making changes"
    echo "  --help       Show this help message"
    echo
    echo "Environment Variables (optional):"
    echo "  AWS_REGION   AWS region to deploy to (default: from AWS CLI config)"
    echo "  VPC_ID       Specific VPC ID to monitor (default: default VPC)"
    echo
}

# Main deployment function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    log "INFO" "Starting VPC Flow Logs network monitoring deployment"
    log "INFO" "Script: $SCRIPT_NAME"
    log "INFO" "Log file: $LOG_FILE"
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN MODE - No resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_iam_role
    create_log_group
    create_flow_logs
    create_sns_topic
    create_monitoring
    create_lambda_function
    create_athena_workgroup
    create_dashboard
    
    if [ "$DRY_RUN" = false ]; then
        save_deployment_state
        print_summary
    else
        log "INFO" "DRY RUN completed - no resources were created"
    fi
}

# Cleanup on script exit
cleanup() {
    log "DEBUG" "Cleaning up temporary files..."
    rm -f /tmp/lifecycle-policy.json
    rm -f /tmp/flow-logs-trust-policy.json
    rm -f /tmp/lambda-function.py
    rm -f /tmp/lambda-function.zip
    rm -f /tmp/lambda-policy.json
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/dashboard-config.json
    rm -f /tmp/deployment-state.json
}

# Set trap for cleanup
trap cleanup EXIT

# Run main function
main "$@"