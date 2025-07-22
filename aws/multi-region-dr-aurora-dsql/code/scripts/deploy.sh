#!/bin/bash

#==============================================================================
# Aurora DSQL Multi-Region Disaster Recovery Deployment Script
# This script deploys a comprehensive disaster recovery solution with Aurora DSQL,
# EventBridge, Lambda, and CloudWatch across multiple AWS regions.
#==============================================================================

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
readonly LOG_FILE="/tmp/aurora-dsql-dr-deploy-${TIMESTAMP}.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Default configuration
DEFAULT_PRIMARY_REGION="us-east-1"
DEFAULT_SECONDARY_REGION="us-west-2"
DEFAULT_WITNESS_REGION="us-west-1"
DEFAULT_EMAIL="ops-team@company.com"

#==============================================================================
# Utility Functions
#==============================================================================

log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

print_colored() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

error_exit() {
    print_colored "$RED" "❌ Error: $*" >&2
    log_error "$*"
    exit 1
}

success_msg() {
    print_colored "$GREEN" "✅ $*"
    log_success "$*"
}

info_msg() {
    print_colored "$BLUE" "ℹ️ $*"
    log_info "$*"
}

warn_msg() {
    print_colored "$YELLOW" "⚠️ $*"
    log_warn "$*"
}

#==============================================================================
# Validation Functions
#==============================================================================

check_prerequisites() {
    info_msg "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI not found. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$aws_version" | cut -d. -f1) -lt 2 ]]; then
        error_exit "AWS CLI v2 is required. Found version: $aws_version"
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error_exit "jq not found. Please install jq for JSON processing."
    fi
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured or invalid. Run 'aws configure' first."
    fi
    
    success_msg "Prerequisites check passed"
}

validate_regions() {
    info_msg "Validating region availability for Aurora DSQL..."
    
    # Note: Aurora DSQL availability should be checked here
    # For this example, we'll validate the regions are accessible
    local regions=("$PRIMARY_REGION" "$SECONDARY_REGION" "$WITNESS_REGION")
    
    for region in "${regions[@]}"; do
        if ! aws ec2 describe-regions --region-names "$region" &> /dev/null; then
            error_exit "Region $region is not valid or accessible"
        fi
    done
    
    # Check for Aurora DSQL availability (simulated - replace with actual check)
    warn_msg "Please verify Aurora DSQL is available in your selected regions:"
    warn_msg "Primary: $PRIMARY_REGION, Secondary: $SECONDARY_REGION, Witness: $WITNESS_REGION"
    
    success_msg "Region validation completed"
}

validate_permissions() {
    info_msg "Validating required AWS permissions..."
    
    local required_services=("dsql" "lambda" "events" "sns" "iam" "cloudwatch")
    local errors=0
    
    for service in "${required_services[@]}"; do
        case $service in
            "dsql")
                if ! aws dsql list-clusters --region "$PRIMARY_REGION" &> /dev/null; then
                    log_error "Missing permissions for Aurora DSQL in $PRIMARY_REGION"
                    ((errors++))
                fi
                ;;
            "lambda")
                if ! aws lambda list-functions --region "$PRIMARY_REGION" &> /dev/null; then
                    log_error "Missing permissions for Lambda in $PRIMARY_REGION"
                    ((errors++))
                fi
                ;;
            "events")
                if ! aws events list-rules --region "$PRIMARY_REGION" &> /dev/null; then
                    log_error "Missing permissions for EventBridge in $PRIMARY_REGION"
                    ((errors++))
                fi
                ;;
            "sns")
                if ! aws sns list-topics --region "$PRIMARY_REGION" &> /dev/null; then
                    log_error "Missing permissions for SNS in $PRIMARY_REGION"
                    ((errors++))
                fi
                ;;
            "iam")
                if ! aws iam list-roles &> /dev/null; then
                    log_error "Missing permissions for IAM"
                    ((errors++))
                fi
                ;;
            "cloudwatch")
                if ! aws cloudwatch list-dashboards --region "$PRIMARY_REGION" &> /dev/null; then
                    log_error "Missing permissions for CloudWatch in $PRIMARY_REGION"
                    ((errors++))
                fi
                ;;
        esac
    done
    
    if [[ $errors -gt 0 ]]; then
        error_exit "Permission validation failed. Check logs for details."
    fi
    
    success_msg "Permission validation completed"
}

#==============================================================================
# Resource Creation Functions
#==============================================================================

setup_environment() {
    info_msg "Setting up environment variables..."
    
    # Export environment variables for use in other functions
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 8)")
    
    export CLUSTER_PREFIX="dr-dsql-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="dr-monitor-${random_suffix}"
    export EVENTBRIDGE_RULE_NAME="dr-health-monitor-${random_suffix}"
    export SNS_TOPIC_NAME="dr-alerts-${random_suffix}"
    
    # Store configuration for cleanup script
    cat > "/tmp/aurora-dsql-dr-config-${random_suffix}.env" << EOF
PRIMARY_REGION=$PRIMARY_REGION
SECONDARY_REGION=$SECONDARY_REGION
WITNESS_REGION=$WITNESS_REGION
CLUSTER_PREFIX=$CLUSTER_PREFIX
LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
EVENTBRIDGE_RULE_NAME=$EVENTBRIDGE_RULE_NAME
SNS_TOPIC_NAME=$SNS_TOPIC_NAME
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
EMAIL_ADDRESS=$EMAIL_ADDRESS
DEPLOYMENT_ID=$random_suffix
EOF
    
    success_msg "Environment setup completed"
    info_msg "Configuration saved to: /tmp/aurora-dsql-dr-config-${random_suffix}.env"
    info_msg "Primary Region: $PRIMARY_REGION"
    info_msg "Secondary Region: $SECONDARY_REGION"
    info_msg "Witness Region: $WITNESS_REGION"
    info_msg "Deployment ID: $random_suffix"
}

create_aurora_dsql_clusters() {
    info_msg "Creating Aurora DSQL clusters..."
    
    # Create primary cluster
    info_msg "Creating primary Aurora DSQL cluster in $PRIMARY_REGION..."
    aws dsql create-cluster \
        --region "$PRIMARY_REGION" \
        --cluster-identifier "${CLUSTER_PREFIX}-primary" \
        --multi-region-properties "{\"witnessRegion\":\"$WITNESS_REGION\"}" \
        --tags Key=Project,Value=DisasterRecovery \
               Key=Environment,Value=Production \
               Key=CostCenter,Value=Infrastructure \
               Key=DeployedBy,Value="$SCRIPT_NAME" || error_exit "Failed to create primary cluster"
    
    # Wait for primary cluster to become available
    info_msg "Waiting for primary cluster to become available..."
    local retries=0
    while [[ $retries -lt 30 ]]; do
        local status
        status=$(aws dsql describe-cluster \
            --region "$PRIMARY_REGION" \
            --identifier "${CLUSTER_PREFIX}-primary" \
            --query 'status' --output text 2>/dev/null || echo "CREATING")
        
        if [[ "$status" == "ACTIVE" ]]; then
            break
        elif [[ "$status" == "FAILED" ]]; then
            error_exit "Primary cluster creation failed"
        fi
        
        info_msg "Primary cluster status: $status (attempt $((retries + 1))/30)"
        sleep 30
        ((retries++))
    done
    
    if [[ $retries -eq 30 ]]; then
        error_exit "Timeout waiting for primary cluster to become active"
    fi
    
    success_msg "Primary Aurora DSQL cluster created: ${CLUSTER_PREFIX}-primary"
    
    # Create secondary cluster
    info_msg "Creating secondary Aurora DSQL cluster in $SECONDARY_REGION..."
    aws dsql create-cluster \
        --region "$SECONDARY_REGION" \
        --cluster-identifier "${CLUSTER_PREFIX}-secondary" \
        --multi-region-properties "{\"witnessRegion\":\"$WITNESS_REGION\"}" \
        --tags Key=Project,Value=DisasterRecovery \
               Key=Environment,Value=Production \
               Key=CostCenter,Value=Infrastructure \
               Key=DeployedBy,Value="$SCRIPT_NAME" || error_exit "Failed to create secondary cluster"
    
    # Wait for secondary cluster to become available
    info_msg "Waiting for secondary cluster to become available..."
    retries=0
    while [[ $retries -lt 30 ]]; do
        local status
        status=$(aws dsql describe-cluster \
            --region "$SECONDARY_REGION" \
            --identifier "${CLUSTER_PREFIX}-secondary" \
            --query 'status' --output text 2>/dev/null || echo "CREATING")
        
        if [[ "$status" == "ACTIVE" ]]; then
            break
        elif [[ "$status" == "FAILED" ]]; then
            error_exit "Secondary cluster creation failed"
        fi
        
        info_msg "Secondary cluster status: $status (attempt $((retries + 1))/30)"
        sleep 30
        ((retries++))
    done
    
    if [[ $retries -eq 30 ]]; then
        error_exit "Timeout waiting for secondary cluster to become active"
    fi
    
    success_msg "Secondary Aurora DSQL cluster created: ${CLUSTER_PREFIX}-secondary"
}

establish_cluster_peering() {
    info_msg "Establishing multi-region cluster peering..."
    
    # Get cluster ARNs
    local primary_arn secondary_arn
    primary_arn=$(aws dsql describe-cluster \
        --region "$PRIMARY_REGION" \
        --identifier "${CLUSTER_PREFIX}-primary" \
        --query 'arn' --output text) || error_exit "Failed to get primary cluster ARN"
    
    secondary_arn=$(aws dsql describe-cluster \
        --region "$SECONDARY_REGION" \
        --identifier "${CLUSTER_PREFIX}-secondary" \
        --query 'arn' --output text) || error_exit "Failed to get secondary cluster ARN"
    
    # Peer primary cluster with secondary
    info_msg "Peering primary cluster with secondary..."
    aws dsql update-cluster \
        --region "$PRIMARY_REGION" \
        --identifier "${CLUSTER_PREFIX}-primary" \
        --multi-region-properties "{\"witnessRegion\":\"$WITNESS_REGION\",\"clusters\":[\"$secondary_arn\"]}" \
        || error_exit "Failed to peer primary cluster"
    
    # Peer secondary cluster with primary
    info_msg "Completing peering from secondary cluster..."
    aws dsql update-cluster \
        --region "$SECONDARY_REGION" \
        --identifier "${CLUSTER_PREFIX}-secondary" \
        --multi-region-properties "{\"witnessRegion\":\"$WITNESS_REGION\",\"clusters\":[\"$primary_arn\"]}" \
        || error_exit "Failed to peer secondary cluster"
    
    # Wait for peering to complete
    info_msg "Waiting for cluster peering to complete..."
    sleep 60
    
    success_msg "Multi-region cluster peering established successfully"
}

create_sns_topics() {
    info_msg "Creating SNS topics for multi-region alerting..."
    
    # Create primary SNS topic
    local primary_sns_arn
    primary_sns_arn=$(aws sns create-topic \
        --region "$PRIMARY_REGION" \
        --name "${SNS_TOPIC_NAME}-primary" \
        --attributes DisplayName="DR Alerts Primary" \
        --tags Key=Project,Value=DisasterRecovery \
               Key=Region,Value=Primary \
               Key=DeployedBy,Value="$SCRIPT_NAME" \
        --query 'TopicArn' --output text) || error_exit "Failed to create primary SNS topic"
    
    # Create secondary SNS topic
    local secondary_sns_arn
    secondary_sns_arn=$(aws sns create-topic \
        --region "$SECONDARY_REGION" \
        --name "${SNS_TOPIC_NAME}-secondary" \
        --attributes DisplayName="DR Alerts Secondary" \
        --tags Key=Project,Value=DisasterRecovery \
               Key=Region,Value=Secondary \
               Key=DeployedBy,Value="$SCRIPT_NAME" \
        --query 'TopicArn' --output text) || error_exit "Failed to create secondary SNS topic"
    
    # Subscribe email endpoints
    if [[ "$EMAIL_ADDRESS" != "ops-team@company.com" ]]; then
        info_msg "Subscribing email address to SNS topics..."
        aws sns subscribe \
            --region "$PRIMARY_REGION" \
            --topic-arn "$primary_sns_arn" \
            --protocol email \
            --notification-endpoint "$EMAIL_ADDRESS" || warn_msg "Failed to subscribe to primary SNS topic"
        
        aws sns subscribe \
            --region "$SECONDARY_REGION" \
            --topic-arn "$secondary_sns_arn" \
            --protocol email \
            --notification-endpoint "$EMAIL_ADDRESS" || warn_msg "Failed to subscribe to secondary SNS topic"
    else
        warn_msg "Using default email address. Please update with a real email address."
    fi
    
    # Enable encryption
    aws sns set-topic-attributes \
        --region "$PRIMARY_REGION" \
        --topic-arn "$primary_sns_arn" \
        --attribute-name KmsMasterKeyId \
        --attribute-value alias/aws/sns || warn_msg "Failed to enable encryption for primary SNS"
    
    aws sns set-topic-attributes \
        --region "$SECONDARY_REGION" \
        --topic-arn "$secondary_sns_arn" \
        --attribute-name KmsMasterKeyId \
        --attribute-value alias/aws/sns || warn_msg "Failed to enable encryption for secondary SNS"
    
    # Export for other functions
    export PRIMARY_SNS_ARN="$primary_sns_arn"
    export SECONDARY_SNS_ARN="$secondary_sns_arn"
    
    success_msg "SNS topics created and configured"
    info_msg "Primary SNS: $primary_sns_arn"
    info_msg "Secondary SNS: $secondary_sns_arn"
}

create_iam_role() {
    info_msg "Creating IAM role for Lambda functions..."
    
    # Create trust policy
    cat > "/tmp/trust-policy.json" << EOF
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
    local lambda_role_arn
    lambda_role_arn=$(aws iam create-role \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --tags Key=Project,Value=DisasterRecovery \
               Key=DeployedBy,Value="$SCRIPT_NAME" \
        --query 'Role.Arn' --output text) || error_exit "Failed to create IAM role"
    
    # Wait for role propagation
    info_msg "Waiting for IAM role propagation..."
    sleep 15
    
    # Attach necessary policies
    local policies=(
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        "arn:aws:iam::aws:policy/AmazonDSQLFullAccess"
        "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
        "arn:aws:iam::aws:policy/CloudWatchFullAccess"
    )
    
    for policy in "${policies[@]}"; do
        aws iam attach-role-policy \
            --role-name "${LAMBDA_FUNCTION_NAME}-role" \
            --policy-arn "$policy" || error_exit "Failed to attach policy: $policy"
    done
    
    export LAMBDA_ROLE_ARN="$lambda_role_arn"
    
    # Cleanup temporary file
    rm -f "/tmp/trust-policy.json"
    
    success_msg "IAM role created: $lambda_role_arn"
}

create_lambda_function() {
    info_msg "Creating Lambda function code..."
    
    # Create Lambda function code
    cat > "/tmp/lambda_function.py" << 'EOF'
import json
import boto3
import os
import time
from datetime import datetime
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    """
    Monitor Aurora DSQL cluster health and send alerts
    """
    dsql_client = boto3.client('dsql')
    sns_client = boto3.client('sns')
    cloudwatch_client = boto3.client('cloudwatch')
    
    cluster_id = os.environ['CLUSTER_ID']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    region = os.environ['AWS_REGION']
    
    try:
        # Check cluster status with retry logic
        max_retries = 3
        for attempt in range(max_retries):
            try:
                response = dsql_client.describe_cluster(identifier=cluster_id)
                break
            except ClientError as e:
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)  # Exponential backoff
                    continue
                raise e
        
        cluster_status = response['status']
        cluster_arn = response['arn']
        
        # Create comprehensive health report
        health_report = {
            'timestamp': datetime.now().isoformat(),
            'region': region,
            'cluster_id': cluster_id,
            'cluster_arn': cluster_arn,
            'status': cluster_status,
            'healthy': cluster_status == 'ACTIVE',
            'function_name': context.function_name,
            'request_id': context.aws_request_id
        }
        
        # Publish custom CloudWatch metric
        cloudwatch_client.put_metric_data(
            Namespace='Aurora/DSQL/DisasterRecovery',
            MetricData=[
                {
                    'MetricName': 'ClusterHealth',
                    'Value': 1.0 if cluster_status == 'ACTIVE' else 0.0,
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'ClusterID',
                            'Value': cluster_id
                        },
                        {
                            'Name': 'Region',
                            'Value': region
                        }
                    ]
                }
            ]
        )
        
        # Send alert if cluster is not healthy
        if cluster_status != 'ACTIVE':
            alert_message = f"""
ALERT: Aurora DSQL Cluster Health Issue

Region: {region}
Cluster ID: {cluster_id}
Cluster ARN: {cluster_arn}
Status: {cluster_status}
Timestamp: {health_report['timestamp']}
Function: {context.function_name}
Request ID: {context.aws_request_id}

Immediate investigation required.
Check Aurora DSQL console for detailed status information.
            """
            
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Subject=f'Aurora DSQL Alert - {region}',
                Message=alert_message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps(health_report),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        error_message = f"""
ERROR: Aurora DSQL Health Check Failed

Region: {region}
Cluster ID: {cluster_id}
Error: {str(e)}
Error Type: {type(e).__name__}
Timestamp: {datetime.now().isoformat()}
Function: {context.function_name}
Request ID: {context.aws_request_id}

This error indicates a potential issue with the monitoring infrastructure.
Verify Lambda function permissions and Aurora DSQL cluster accessibility.
        """
        
        try:
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Subject=f'Aurora DSQL Health Check Error - {region}',
                Message=error_message
            )
        except Exception as sns_error:
            print(f"Failed to send SNS alert: {sns_error}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'error_type': type(e).__name__,
                'timestamp': datetime.now().isoformat()
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
EOF
    
    # Package Lambda function
    (cd /tmp && zip lambda_function.zip lambda_function.py) || error_exit "Failed to package Lambda function"
    
    success_msg "Lambda function code created and packaged"
}

deploy_lambda_functions() {
    info_msg "Deploying Lambda functions to both regions..."
    
    # Deploy to primary region
    local primary_lambda_arn
    primary_lambda_arn=$(aws lambda create-function \
        --region "$PRIMARY_REGION" \
        --function-name "${LAMBDA_FUNCTION_NAME}-primary" \
        --runtime python3.12 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb:///tmp/lambda_function.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment "Variables={CLUSTER_ID=${CLUSTER_PREFIX}-primary,SNS_TOPIC_ARN=$PRIMARY_SNS_ARN}" \
        --tags Key=Project,Value=DisasterRecovery,Key=Region,Value=Primary,Key=DeployedBy,Value="$SCRIPT_NAME" \
        --query 'FunctionArn' --output text) || error_exit "Failed to create primary Lambda function"
    
    # Deploy to secondary region
    local secondary_lambda_arn
    secondary_lambda_arn=$(aws lambda create-function \
        --region "$SECONDARY_REGION" \
        --function-name "${LAMBDA_FUNCTION_NAME}-secondary" \
        --runtime python3.12 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb:///tmp/lambda_function.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment "Variables={CLUSTER_ID=${CLUSTER_PREFIX}-secondary,SNS_TOPIC_ARN=$SECONDARY_SNS_ARN}" \
        --tags Key=Project,Value=DisasterRecovery,Key=Region,Value=Secondary,Key=DeployedBy,Value="$SCRIPT_NAME" \
        --query 'FunctionArn' --output text) || error_exit "Failed to create secondary Lambda function"
    
    # Configure reserved concurrency
    aws lambda put-reserved-concurrency-configuration \
        --region "$PRIMARY_REGION" \
        --function-name "${LAMBDA_FUNCTION_NAME}-primary" \
        --reserved-concurrent-executions 10 || warn_msg "Failed to set concurrency for primary Lambda"
    
    aws lambda put-reserved-concurrency-configuration \
        --region "$SECONDARY_REGION" \
        --function-name "${LAMBDA_FUNCTION_NAME}-secondary" \
        --reserved-concurrent-executions 10 || warn_msg "Failed to set concurrency for secondary Lambda"
    
    export PRIMARY_LAMBDA_ARN="$primary_lambda_arn"
    export SECONDARY_LAMBDA_ARN="$secondary_lambda_arn"
    
    # Cleanup temporary files
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip
    
    success_msg "Lambda functions deployed successfully"
    info_msg "Primary Lambda: $primary_lambda_arn"
    info_msg "Secondary Lambda: $secondary_lambda_arn"
}

configure_eventbridge() {
    info_msg "Configuring EventBridge rules for automated monitoring..."
    
    # Create EventBridge rule for primary region
    aws events put-rule \
        --region "$PRIMARY_REGION" \
        --name "${EVENTBRIDGE_RULE_NAME}-primary" \
        --schedule-expression "rate(2 minutes)" \
        --description "Aurora DSQL health monitoring for primary region" \
        --state ENABLED \
        --tags Key=Project,Value=DisasterRecovery,Key=DeployedBy,Value="$SCRIPT_NAME" \
        || error_exit "Failed to create primary EventBridge rule"
    
    # Add Lambda target for primary region
    aws events put-targets \
        --region "$PRIMARY_REGION" \
        --rule "${EVENTBRIDGE_RULE_NAME}-primary" \
        --targets "Id=1,Arn=$PRIMARY_LAMBDA_ARN,RetryPolicy={MaximumRetryAttempts=3,MaximumEventAge=3600}" \
        || error_exit "Failed to add target to primary EventBridge rule"
    
    # Grant EventBridge permission to invoke Lambda (primary)
    aws lambda add-permission \
        --region "$PRIMARY_REGION" \
        --function-name "${LAMBDA_FUNCTION_NAME}-primary" \
        --statement-id "allow-eventbridge-primary" \
        --action "lambda:InvokeFunction" \
        --principal "events.amazonaws.com" \
        --source-arn "arn:aws:events:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}-primary" \
        || error_exit "Failed to grant EventBridge permission for primary Lambda"
    
    # Create EventBridge rule for secondary region
    aws events put-rule \
        --region "$SECONDARY_REGION" \
        --name "${EVENTBRIDGE_RULE_NAME}-secondary" \
        --schedule-expression "rate(2 minutes)" \
        --description "Aurora DSQL health monitoring for secondary region" \
        --state ENABLED \
        --tags Key=Project,Value=DisasterRecovery,Key=DeployedBy,Value="$SCRIPT_NAME" \
        || error_exit "Failed to create secondary EventBridge rule"
    
    # Add Lambda target for secondary region
    aws events put-targets \
        --region "$SECONDARY_REGION" \
        --rule "${EVENTBRIDGE_RULE_NAME}-secondary" \
        --targets "Id=1,Arn=$SECONDARY_LAMBDA_ARN,RetryPolicy={MaximumRetryAttempts=3,MaximumEventAge=3600}" \
        || error_exit "Failed to add target to secondary EventBridge rule"
    
    # Grant EventBridge permission to invoke Lambda (secondary)
    aws lambda add-permission \
        --region "$SECONDARY_REGION" \
        --function-name "${LAMBDA_FUNCTION_NAME}-secondary" \
        --statement-id "allow-eventbridge-secondary" \
        --action "lambda:InvokeFunction" \
        --principal "events.amazonaws.com" \
        --source-arn "arn:aws:events:${SECONDARY_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}-secondary" \
        || error_exit "Failed to grant EventBridge permission for secondary Lambda"
    
    success_msg "EventBridge rules configured successfully"
}

create_cloudwatch_resources() {
    info_msg "Creating CloudWatch dashboard and alarms..."
    
    # Create CloudWatch dashboard
    cat > "/tmp/dashboard_body.json" << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0, "y": 0, "width": 12, "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Invocations", "FunctionName", "${LAMBDA_FUNCTION_NAME}-primary"],
                    ["AWS/Lambda", "Invocations", "FunctionName", "${LAMBDA_FUNCTION_NAME}-secondary"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${PRIMARY_REGION}",
                "title": "Lambda Function Invocations",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 12, "y": 0, "width": 12, "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Errors", "FunctionName", "${LAMBDA_FUNCTION_NAME}-primary"],
                    ["AWS/Lambda", "Errors", "FunctionName", "${LAMBDA_FUNCTION_NAME}-secondary"],
                    ["AWS/Lambda", "Duration", "FunctionName", "${LAMBDA_FUNCTION_NAME}-primary"],
                    ["AWS/Lambda", "Duration", "FunctionName", "${LAMBDA_FUNCTION_NAME}-secondary"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${PRIMARY_REGION}",
                "title": "Lambda Function Errors and Duration"
            }
        },
        {
            "type": "metric",
            "x": 0, "y": 6, "width": 24, "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Events", "MatchedEvents", "RuleName", "${EVENTBRIDGE_RULE_NAME}-primary"],
                    ["AWS/Events", "MatchedEvents", "RuleName", "${EVENTBRIDGE_RULE_NAME}-secondary"],
                    ["AWS/Events", "SuccessfulInvocations", "RuleName", "${EVENTBRIDGE_RULE_NAME}-primary"],
                    ["AWS/Events", "SuccessfulInvocations", "RuleName", "${EVENTBRIDGE_RULE_NAME}-secondary"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${PRIMARY_REGION}",
                "title": "EventBridge Rule Executions and Success Rate"
            }
        },
        {
            "type": "metric",
            "x": 0, "y": 12, "width": 24, "height": 6,
            "properties": {
                "metrics": [
                    ["Aurora/DSQL/DisasterRecovery", "ClusterHealth", "ClusterID", "${CLUSTER_PREFIX}-primary", "Region", "${PRIMARY_REGION}"],
                    ["Aurora/DSQL/DisasterRecovery", "ClusterHealth", "ClusterID", "${CLUSTER_PREFIX}-secondary", "Region", "${SECONDARY_REGION}"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${PRIMARY_REGION}",
                "title": "Aurora DSQL Cluster Health Status",
                "yAxis": {
                    "left": {
                        "min": 0,
                        "max": 1
                    }
                }
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --region "$PRIMARY_REGION" \
        --dashboard-name "Aurora-DSQL-DR-Dashboard-${CLUSTER_PREFIX##*-}" \
        --dashboard-body file:///tmp/dashboard_body.json \
        || error_exit "Failed to create CloudWatch dashboard"
    
    # Create CloudWatch alarms
    local alarm_suffix="${CLUSTER_PREFIX##*-}"
    
    # Lambda errors alarm - primary
    aws cloudwatch put-metric-alarm \
        --region "$PRIMARY_REGION" \
        --alarm-name "Aurora-DSQL-Lambda-Errors-Primary-${alarm_suffix}" \
        --alarm-description "Alert when Lambda function errors occur in primary region" \
        --metric-name "Errors" \
        --namespace "AWS/Lambda" \
        --statistic "Sum" \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 1 \
        --comparison-operator "GreaterThanOrEqualToThreshold" \
        --dimensions "Name=FunctionName,Value=${LAMBDA_FUNCTION_NAME}-primary" \
        --alarm-actions "$PRIMARY_SNS_ARN" \
        --treat-missing-data "notBreaching" \
        --tags Key=Project,Value=DisasterRecovery,Key=DeployedBy,Value="$SCRIPT_NAME" \
        || warn_msg "Failed to create primary Lambda errors alarm"
    
    # Lambda errors alarm - secondary
    aws cloudwatch put-metric-alarm \
        --region "$SECONDARY_REGION" \
        --alarm-name "Aurora-DSQL-Lambda-Errors-Secondary-${alarm_suffix}" \
        --alarm-description "Alert when Lambda function errors occur in secondary region" \
        --metric-name "Errors" \
        --namespace "AWS/Lambda" \
        --statistic "Sum" \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 1 \
        --comparison-operator "GreaterThanOrEqualToThreshold" \
        --dimensions "Name=FunctionName,Value=${LAMBDA_FUNCTION_NAME}-secondary" \
        --alarm-actions "$SECONDARY_SNS_ARN" \
        --treat-missing-data "notBreaching" \
        --tags Key=Project,Value=DisasterRecovery,Key=DeployedBy,Value="$SCRIPT_NAME" \
        || warn_msg "Failed to create secondary Lambda errors alarm"
    
    # Cluster health alarm
    aws cloudwatch put-metric-alarm \
        --region "$PRIMARY_REGION" \
        --alarm-name "Aurora-DSQL-Cluster-Health-${alarm_suffix}" \
        --alarm-description "Alert when Aurora DSQL cluster health degrades" \
        --metric-name "ClusterHealth" \
        --namespace "Aurora/DSQL/DisasterRecovery" \
        --statistic "Average" \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 0.5 \
        --comparison-operator "LessThanThreshold" \
        --alarm-actions "$PRIMARY_SNS_ARN" \
        --treat-missing-data "breaching" \
        --tags Key=Project,Value=DisasterRecovery,Key=DeployedBy,Value="$SCRIPT_NAME" \
        || warn_msg "Failed to create cluster health alarm"
    
    # Cleanup temporary file
    rm -f /tmp/dashboard_body.json
    
    success_msg "CloudWatch dashboard and alarms created successfully"
}

#==============================================================================
# Validation and Testing Functions
#==============================================================================

test_deployment() {
    info_msg "Testing deployment functionality..."
    
    # Test Lambda function invocation
    info_msg "Testing Lambda function execution..."
    local test_result
    test_result=$(aws lambda invoke \
        --region "$PRIMARY_REGION" \
        --function-name "${LAMBDA_FUNCTION_NAME}-primary" \
        --payload '{}' \
        /tmp/primary_response.json \
        --query 'StatusCode' --output text 2>/dev/null)
    
    if [[ "$test_result" == "200" ]]; then
        success_msg "Primary Lambda function test successful"
    else
        warn_msg "Primary Lambda function test failed"
    fi
    
    # Test SNS notification
    info_msg "Testing SNS notification system..."
    aws sns publish \
        --region "$PRIMARY_REGION" \
        --topic-arn "$PRIMARY_SNS_ARN" \
        --subject "Test: Aurora DSQL DR System Deployment" \
        --message "This is a test message confirming successful deployment of the Aurora DSQL disaster recovery system. All components are operational." \
        &> /dev/null && success_msg "SNS test notification sent successfully" || warn_msg "SNS test notification failed"
    
    # Cleanup test files
    rm -f /tmp/primary_response.json
    
    success_msg "Deployment testing completed"
}

#==============================================================================
# Main Functions
#==============================================================================

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Deploy Aurora DSQL Multi-Region Disaster Recovery Infrastructure

OPTIONS:
    -p, --primary-region REGION     Primary AWS region (default: $DEFAULT_PRIMARY_REGION)
    -s, --secondary-region REGION   Secondary AWS region (default: $DEFAULT_SECONDARY_REGION)
    -w, --witness-region REGION     Witness AWS region (default: $DEFAULT_WITNESS_REGION)
    -e, --email EMAIL               Email address for alerts (default: $DEFAULT_EMAIL)
    -d, --dry-run                   Validate configuration without deploying
    -v, --verbose                   Enable verbose logging
    -h, --help                      Show this help message

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME --primary-region us-east-1 --secondary-region us-west-2
    $SCRIPT_NAME --email admin@company.com --verbose
    $SCRIPT_NAME --dry-run

EOF
}

parse_arguments() {
    # Set defaults
    PRIMARY_REGION="$DEFAULT_PRIMARY_REGION"
    SECONDARY_REGION="$DEFAULT_SECONDARY_REGION"
    WITNESS_REGION="$DEFAULT_WITNESS_REGION"
    EMAIL_ADDRESS="$DEFAULT_EMAIL"
    DRY_RUN=false
    VERBOSE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--primary-region)
                PRIMARY_REGION="$2"
                shift 2
                ;;
            -s|--secondary-region)
                SECONDARY_REGION="$2"
                shift 2
                ;;
            -w|--witness-region)
                WITNESS_REGION="$2"
                shift 2
                ;;
            -e|--email)
                EMAIL_ADDRESS="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
    
    # Validate regions are different
    if [[ "$PRIMARY_REGION" == "$SECONDARY_REGION" ]]; then
        error_exit "Primary and secondary regions must be different"
    fi
    
    # Export for global use
    export PRIMARY_REGION SECONDARY_REGION WITNESS_REGION EMAIL_ADDRESS DRY_RUN VERBOSE
}

main() {
    print_colored "$CYAN" "================================================================"
    print_colored "$CYAN" "Aurora DSQL Multi-Region Disaster Recovery Deployment"
    print_colored "$CYAN" "================================================================"
    echo
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Enable verbose logging if requested
    if [[ "$VERBOSE" == "true" ]]; then
        set -x
    fi
    
    info_msg "Starting deployment process..."
    info_msg "Log file: $LOG_FILE"
    
    # Validation phase
    check_prerequisites
    validate_regions
    validate_permissions
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success_msg "Dry run completed successfully. Configuration is valid."
        exit 0
    fi
    
    # Deployment phase
    info_msg "Beginning resource deployment..."
    
    setup_environment
    create_aurora_dsql_clusters
    establish_cluster_peering
    create_sns_topics
    create_iam_role
    create_lambda_function
    deploy_lambda_functions
    configure_eventbridge
    create_cloudwatch_resources
    
    # Testing phase
    test_deployment
    
    # Success summary
    echo
    print_colored "$GREEN" "================================================================"
    print_colored "$GREEN" "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!"
    print_colored "$GREEN" "================================================================"
    echo
    success_msg "Aurora DSQL Multi-Region Disaster Recovery system deployed successfully"
    info_msg "Deployment summary:"
    info_msg "  • Primary cluster: ${CLUSTER_PREFIX}-primary (${PRIMARY_REGION})"
    info_msg "  • Secondary cluster: ${CLUSTER_PREFIX}-secondary (${SECONDARY_REGION})"
    info_msg "  • Witness region: ${WITNESS_REGION}"
    info_msg "  • Monitoring frequency: Every 2 minutes"
    info_msg "  • Dashboard: Aurora-DSQL-DR-Dashboard-${CLUSTER_PREFIX##*-}"
    echo
    info_msg "Next steps:"
    info_msg "  1. Check your email for SNS subscription confirmations"
    info_msg "  2. Review the CloudWatch dashboard for system health"
    info_msg "  3. Test application connectivity to both regions"
    info_msg "  4. Configure application-level failover logic"
    echo
    info_msg "To clean up resources, use the destroy.sh script with the same parameters"
    info_msg "Configuration saved to: /tmp/aurora-dsql-dr-config-${CLUSTER_PREFIX##*-}.env"
    echo
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi