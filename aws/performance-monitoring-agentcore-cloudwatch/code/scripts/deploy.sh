#!/bin/bash

#########################################################################
# Performance Monitoring AI Agents with AgentCore and CloudWatch
# Deployment Script
#
# This script deploys the complete monitoring infrastructure for AWS
# Bedrock AgentCore agents including CloudWatch dashboards, alarms,
# Lambda functions, and S3 storage for performance analytics.
#
# Author: Generated from recipe a9f7e2b4
# Version: 1.0
# Last Updated: 2025-01-15
#########################################################################

set -euo pipefail  # Exit on any error, undefined variables, or pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMP_DIR=$(mktemp -d)

# Global variables for cleanup
CREATED_RESOURCES=()

#########################################################################
# Utility Functions
#########################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "${RED}❌ $*${NC}"
}

cleanup_on_exit() {
    local exit_code=$?
    log_info "Cleaning up temporary files..."
    rm -rf "${TEMP_DIR}"
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed. Check the log file: ${LOG_FILE}"
        log_warning "Some resources may have been created. Run the destroy script to clean up."
    fi
    
    exit $exit_code
}

# Set trap for cleanup
trap cleanup_on_exit EXIT

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version (require v2)
    local aws_version=$(aws --version 2>&1 | head -n1 | awk '{print $1}' | cut -d/ -f2)
    if [[ $(echo "${aws_version}" | cut -d. -f1) -lt 2 ]]; then
        log_error "AWS CLI v2 is required. Current version: ${aws_version}"
        exit 1
    fi
    log_success "AWS CLI v${aws_version} detected"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some operations may be limited."
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        log_error "zip command is not available. Required for Lambda deployment."
        exit 1
    fi
    
    # Verify required AWS services access
    log_info "Verifying AWS service permissions..."
    
    # Test CloudWatch access
    if ! aws cloudwatch list-metrics --max-items 1 &> /dev/null; then
        log_error "No access to CloudWatch. Check IAM permissions."
        exit 1
    fi
    
    # Test Lambda access
    if ! aws lambda list-functions --max-items 1 &> /dev/null; then
        log_error "No access to Lambda. Check IAM permissions."
        exit 1
    fi
    
    # Test S3 access
    if ! aws s3 ls &> /dev/null; then
        log_error "No access to S3. Check IAM permissions."
        exit 1
    fi
    
    # Test IAM access
    if ! aws iam list-roles --max-items 1 &> /dev/null; then
        log_error "No access to IAM. Check IAM permissions."
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

setup_environment() {
    log_info "Setting up deployment environment..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        log_error "AWS region not configured. Run 'aws configure' first."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
        log_error "Unable to determine AWS account ID."
        exit 1
    fi
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export AGENT_NAME="ai-agent-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="agent-performance-optimizer-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="agent-monitoring-data-${RANDOM_SUFFIX}"
    export LOG_GROUP_NAME="/aws/bedrock/agentcore/${AGENT_NAME}"
    export DASHBOARD_NAME="AgentCore-Performance-${RANDOM_SUFFIX}"
    
    # Store configuration for cleanup script
    cat > "${SCRIPT_DIR}/deployment_config.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
AGENT_NAME=${AGENT_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
LOG_GROUP_NAME=${LOG_GROUP_NAME}
DASHBOARD_NAME=${DASHBOARD_NAME}
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    log_success "Environment configured"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
}

wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local check_command="$3"
    local max_attempts="${4:-30}"
    local sleep_interval="${5:-5}"
    
    log_info "Waiting for ${resource_type} '${resource_name}' to become available..."
    
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if eval "${check_command}" &> /dev/null; then
            log_success "${resource_type} '${resource_name}' is available"
            return 0
        fi
        
        ((attempt++))
        log_info "Attempt ${attempt}/${max_attempts}: Waiting ${sleep_interval}s..."
        sleep "${sleep_interval}"
    done
    
    log_error "Timeout waiting for ${resource_type} '${resource_name}'"
    return 1
}

#########################################################################
# Deployment Functions
#########################################################################

create_s3_bucket() {
    log_info "Creating S3 bucket for monitoring data storage..."
    
    # Check if bucket already exists
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        log_warning "S3 bucket s3://${S3_BUCKET_NAME} already exists"
        return 0
    fi
    
    # Create S3 bucket
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
        aws s3 mb "s3://${S3_BUCKET_NAME}"
    else
        aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}"
    fi
    
    CREATED_RESOURCES+=("s3:${S3_BUCKET_NAME}")
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${S3_BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "${S3_BUCKET_NAME}" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "${S3_BUCKET_NAME}" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    log_success "S3 bucket created: s3://${S3_BUCKET_NAME}"
}

create_agentcore_iam_role() {
    log_info "Creating IAM role for AgentCore with observability permissions..."
    
    # Create trust policy for AgentCore service
    cat > "${TEMP_DIR}/agentcore-trust-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "bedrock.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create IAM role for AgentCore
    local role_name="AgentCoreMonitoringRole-${RANDOM_SUFFIX}"
    
    if ! aws iam get-role --role-name "${role_name}" &> /dev/null; then
        aws iam create-role \
            --role-name "${role_name}" \
            --assume-role-policy-document "file://${TEMP_DIR}/agentcore-trust-policy.json" \
            --description "IAM role for AgentCore monitoring and observability"
        
        CREATED_RESOURCES+=("iam_role:${role_name}")
    else
        log_warning "IAM role ${role_name} already exists"
    fi
    
    # Create custom policy for AgentCore observability
    cat > "${TEMP_DIR}/agentcore-observability-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/bedrock/agentcore/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "cloudwatch:namespace": "AWS/BedrockAgentCore"
        }
      }
    }
  ]
}
EOF
    
    # Create the custom policy
    local policy_name="AgentCoreObservabilityPolicy-${RANDOM_SUFFIX}"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
    
    if ! aws iam get-policy --policy-arn "${policy_arn}" &> /dev/null; then
        aws iam create-policy \
            --policy-name "${policy_name}" \
            --policy-document "file://${TEMP_DIR}/agentcore-observability-policy.json" \
            --description "Policy for AgentCore observability permissions"
        
        CREATED_RESOURCES+=("iam_policy:${policy_arn}")
    else
        log_warning "IAM policy ${policy_name} already exists"
    fi
    
    # Attach the custom policy to the role
    aws iam attach-role-policy \
        --role-name "${role_name}" \
        --policy-arn "${policy_arn}"
    
    # Store role ARN for later use
    export AGENTCORE_ROLE_ARN=$(aws iam get-role \
        --role-name "${role_name}" \
        --query 'Role.Arn' --output text)
    
    log_success "AgentCore IAM role created: ${AGENTCORE_ROLE_ARN}"
}

create_cloudwatch_log_groups() {
    log_info "Creating CloudWatch log groups for comprehensive observability..."
    
    local log_groups=(
        "${LOG_GROUP_NAME}"
        "/aws/lambda/${LAMBDA_FUNCTION_NAME}"
        "/aws/bedrock/agentcore/memory/${AGENT_NAME}"
        "/aws/bedrock/agentcore/gateway/${AGENT_NAME}"
    )
    
    local retention_days=(30 7 30 30)
    
    for i in "${!log_groups[@]}"; do
        local log_group="${log_groups[i]}"
        local retention="${retention_days[i]}"
        
        if ! aws logs describe-log-groups --log-group-name-prefix "${log_group}" \
                --query "logGroups[?logGroupName=='${log_group}']" \
                --output text | grep -q "${log_group}"; then
            
            aws logs create-log-group \
                --log-group-name "${log_group}" \
                --retention-in-days "${retention}"
            
            CREATED_RESOURCES+=("log_group:${log_group}")
            log_success "Created log group: ${log_group}"
        else
            log_warning "Log group already exists: ${log_group}"
        fi
    done
}

create_lambda_function() {
    log_info "Creating performance monitoring Lambda function..."
    
    # Create Lambda function code
    cat > "${TEMP_DIR}/performance_monitor.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Monitor AgentCore performance metrics and trigger optimization actions
    """
    try:
        # Handle direct CloudWatch alarm format
        if 'Records' in event:
            # SNS message format
            message = json.loads(event['Records'][0]['Sns']['Message'])
            alarm_name = message.get('AlarmName', 'Unknown')
            alarm_description = message.get('AlarmDescription', '')
            new_state = message.get('NewStateValue', 'UNKNOWN')
        else:
            # Direct invocation format
            alarm_name = event.get('AlarmName', 'TestAlarm')
            alarm_description = event.get('AlarmDescription', 'Test alarm')
            new_state = event.get('NewStateValue', 'ALARM')
        
        # Get performance metrics for the last 5 minutes
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=5)
        
        # Query AgentCore metrics
        try:
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/BedrockAgentCore',
                MetricName='Latency',
                Dimensions=[
                    {'Name': 'AgentId', 'Value': os.environ['AGENT_NAME']}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=60,
                Statistics=['Average', 'Maximum']
            )
        except Exception as metric_error:
            print(f"Warning: Could not retrieve metrics - {str(metric_error)}")
            response = {'Datapoints': []}
        
        # Analyze performance and create report
        performance_report = {
            'timestamp': end_time.isoformat(),
            'alarm_triggered': alarm_name,
            'alarm_description': alarm_description,
            'new_state': new_state,
            'metrics': response['Datapoints'],
            'optimization_actions': []
        }
        
        # Add optimization recommendations based on metrics
        if response['Datapoints']:
            avg_latency = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
            max_latency = max((dp['Maximum'] for dp in response['Datapoints']), default=0)
            
            if avg_latency > 30000:  # 30 seconds
                performance_report['optimization_actions'].append({
                    'action': 'increase_memory_allocation',
                    'reason': f'High average latency detected: {avg_latency:.2f}ms'
                })
            
            if max_latency > 60000:  # 60 seconds
                performance_report['optimization_actions'].append({
                    'action': 'investigate_timeout_issues',
                    'reason': f'Maximum latency threshold exceeded: {max_latency:.2f}ms'
                })
        else:
            performance_report['optimization_actions'].append({
                'action': 'verify_agent_health',
                'reason': 'No metric data available for analysis'
            })
        
        # Store performance report in S3
        report_key = f"performance-reports/{datetime.now().strftime('%Y/%m/%d')}/{alarm_name}-{context.aws_request_id}.json"
        s3.put_object(
            Bucket=os.environ['S3_BUCKET_NAME'],
            Key=report_key,
            Body=json.dumps(performance_report, indent=2),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Performance analysis completed',
                'report_location': f"s3://{os.environ['S3_BUCKET_NAME']}/{report_key}",
                'optimization_actions': len(performance_report['optimization_actions'])
            })
        }
        
    except Exception as e:
        print(f"Error processing performance alert: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Package Lambda function
    cd "${TEMP_DIR}"
    zip performance_monitor.zip performance_monitor.py
    cd - > /dev/null
    
    # Create Lambda execution role
    cat > "${TEMP_DIR}/lambda-trust-policy.json" << EOF
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
    
    local lambda_role_name="LambdaPerformanceMonitorRole-${RANDOM_SUFFIX}"
    
    if ! aws iam get-role --role-name "${lambda_role_name}" &> /dev/null; then
        aws iam create-role \
            --role-name "${lambda_role_name}" \
            --assume-role-policy-document "file://${TEMP_DIR}/lambda-trust-policy.json" \
            --description "IAM role for Lambda performance monitoring function"
        
        CREATED_RESOURCES+=("iam_role:${lambda_role_name}")
    else
        log_warning "Lambda IAM role ${lambda_role_name} already exists"
    fi
    
    # Attach necessary policies
    local policies=(
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
        "arn:aws:iam::aws:policy/AmazonS3FullAccess"
    )
    
    for policy in "${policies[@]}"; do
        aws iam attach-role-policy \
            --role-name "${lambda_role_name}" \
            --policy-arn "${policy}"
    done
    
    # Get Lambda role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "${lambda_role_name}" \
        --query 'Role.Arn' --output text)
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 15
    
    # Create Lambda function
    if ! aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime python3.12 \
            --role "${LAMBDA_ROLE_ARN}" \
            --handler performance_monitor.lambda_handler \
            --zip-file "fileb://${TEMP_DIR}/performance_monitor.zip" \
            --timeout 60 \
            --memory-size 256 \
            --description "Performance monitoring function for AgentCore" \
            --environment "Variables={AGENT_NAME=${AGENT_NAME},S3_BUCKET_NAME=${S3_BUCKET_NAME}}"
        
        CREATED_RESOURCES+=("lambda:${LAMBDA_FUNCTION_NAME}")
    else
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} already exists"
    fi
    
    log_success "Performance monitoring Lambda function created"
}

create_cloudwatch_dashboard() {
    log_info "Creating CloudWatch dashboard for performance visualization..."
    
    # Create comprehensive CloudWatch dashboard configuration
    cat > "${TEMP_DIR}/dashboard-config.json" << EOF
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
          [ "AWS/BedrockAgentCore", "Latency", "AgentId", "${AGENT_NAME}" ],
          [ ".", "Invocations", ".", "." ],
          [ ".", "SessionCount", ".", "." ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Agent Performance Metrics",
        "period": 300,
        "stat": "Average"
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
          [ "AWS/BedrockAgentCore", "UserErrors", "AgentId", "${AGENT_NAME}" ],
          [ ".", "SystemErrors", ".", "." ],
          [ ".", "Throttles", ".", "." ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Error and Throttle Rates",
        "period": 300,
        "stat": "Sum",
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
        "query": "SOURCE '${LOG_GROUP_NAME}' | fields @timestamp, @message\\n| filter @message like /ERROR/\\n| sort @timestamp desc\\n| limit 20",
        "region": "${AWS_REGION}",
        "title": "Recent Agent Errors",
        "view": "table"
      }
    }
  ]
}
EOF
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body "file://${TEMP_DIR}/dashboard-config.json"
    
    CREATED_RESOURCES+=("dashboard:${DASHBOARD_NAME}")
    
    log_success "CloudWatch dashboard created: ${DASHBOARD_NAME}"
}

create_cloudwatch_alarms() {
    log_info "Creating CloudWatch alarms for performance monitoring..."
    
    local alarms=(
        "AgentCore-HighLatency-${RANDOM_SUFFIX}:Latency:30000:Average:Alert when agent latency exceeds 30 seconds"
        "AgentCore-HighSystemErrors-${RANDOM_SUFFIX}:SystemErrors:5:Sum:Alert when system errors exceed threshold"
        "AgentCore-HighThrottles-${RANDOM_SUFFIX}:Throttles:10:Sum:Alert when throttling occurs frequently"
    )
    
    for alarm_config in "${alarms[@]}"; do
        IFS=':' read -r alarm_name metric_name threshold statistic description <<< "${alarm_config}"
        
        if ! aws cloudwatch describe-alarms --alarm-names "${alarm_name}" \
                --query "MetricAlarms[?AlarmName=='${alarm_name}']" \
                --output text | grep -q "${alarm_name}"; then
            
            local evaluation_periods=2
            local period=300
            
            # Adjust evaluation periods for error-based alarms
            if [[ "${metric_name}" == "SystemErrors" ]]; then
                evaluation_periods=1
            fi
            
            aws cloudwatch put-metric-alarm \
                --alarm-name "${alarm_name}" \
                --alarm-description "${description}" \
                --metric-name "${metric_name}" \
                --namespace AWS/BedrockAgentCore \
                --statistic "${statistic}" \
                --period "${period}" \
                --threshold "${threshold}" \
                --comparison-operator GreaterThanThreshold \
                --evaluation-periods "${evaluation_periods}" \
                --alarm-actions "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}" \
                --dimensions Name=AgentId,Value="${AGENT_NAME}" \
                --treat-missing-data notBreaching
            
            CREATED_RESOURCES+=("alarm:${alarm_name}")
            log_success "Created alarm: ${alarm_name}"
        else
            log_warning "Alarm already exists: ${alarm_name}"
        fi
    done
    
    # Grant CloudWatch permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id allow-cloudwatch-alarms \
        --action lambda:InvokeFunction \
        --principal cloudwatch.amazonaws.com \
        --source-account "${AWS_ACCOUNT_ID}" 2>/dev/null || true
    
    log_success "CloudWatch alarms configured"
}

create_custom_metrics() {
    log_info "Setting up custom metrics collection for advanced analytics..."
    
    local metric_filters=(
        "AgentResponseTime:[timestamp, requestId, level=INFO, metric=\"response_time\", value]:metricName=AgentResponseTime,metricNamespace=CustomAgentMetrics,metricValue=\$value,defaultValue=0"
        "ConversationQualityScore:[timestamp, requestId, level=INFO, metric=\"quality_score\", score]:metricName=ConversationQuality,metricNamespace=CustomAgentMetrics,metricValue=\$score,defaultValue=0"
        "BusinessOutcomeSuccess:[timestamp, requestId, level=INFO, outcome=\"SUCCESS\"]:metricName=BusinessOutcomeSuccess,metricNamespace=CustomAgentMetrics,metricValue=1,defaultValue=0"
    )
    
    for filter_config in "${metric_filters[@]}"; do
        IFS=':' read -r filter_name filter_pattern metric_transformations <<< "${filter_config}"
        
        if ! aws logs describe-metric-filters \
                --log-group-name "${LOG_GROUP_NAME}" \
                --filter-name-prefix "${filter_name}" \
                --query "metricFilters[?filterName=='${filter_name}']" \
                --output text | grep -q "${filter_name}"; then
            
            aws logs put-metric-filter \
                --log-group-name "${LOG_GROUP_NAME}" \
                --filter-name "${filter_name}" \
                --filter-pattern "${filter_pattern}" \
                --metric-transformations "${metric_transformations}"
            
            CREATED_RESOURCES+=("metric_filter:${LOG_GROUP_NAME}:${filter_name}")
            log_success "Created metric filter: ${filter_name}"
        else
            log_warning "Metric filter already exists: ${filter_name}"
        fi
    done
}

#########################################################################
# Validation Functions
#########################################################################

validate_deployment() {
    log_info "Validating deployment..."
    
    local validation_errors=0
    
    # Check S3 bucket
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        log_success "S3 bucket is accessible"
    else
        log_error "S3 bucket validation failed"
        ((validation_errors++))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        log_success "Lambda function is available"
        
        # Test Lambda function
        local test_payload='{"AlarmName":"TestAlarm","AlarmDescription":"Test","NewStateValue":"ALARM"}'
        if aws lambda invoke \
                --function-name "${LAMBDA_FUNCTION_NAME}" \
                --payload "${test_payload}" \
                "${TEMP_DIR}/lambda_response.json" &> /dev/null; then
            log_success "Lambda function test passed"
        else
            log_error "Lambda function test failed"
            ((validation_errors++))
        fi
    else
        log_error "Lambda function validation failed"
        ((validation_errors++))
    fi
    
    # Check CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name "${DASHBOARD_NAME}" &> /dev/null; then
        log_success "CloudWatch dashboard is available"
    else
        log_error "CloudWatch dashboard validation failed"
        ((validation_errors++))
    fi
    
    # Check CloudWatch alarms
    local alarm_count=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "AgentCore-" \
        --query "length(MetricAlarms[?contains(AlarmName, '${RANDOM_SUFFIX}')])" \
        --output text)
    
    if [[ "${alarm_count}" -ge 3 ]]; then
        log_success "CloudWatch alarms are configured (${alarm_count} alarms)"
    else
        log_error "CloudWatch alarms validation failed (expected 3, found ${alarm_count})"
        ((validation_errors++))
    fi
    
    # Check log groups
    local log_group_count=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/bedrock/agentcore/" \
        --query "length(logGroups)" \
        --output text)
    
    if [[ "${log_group_count}" -ge 1 ]]; then
        log_success "Log groups are configured (${log_group_count} groups)"
    else
        log_error "Log groups validation failed"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log_success "All validation checks passed"
        return 0
    else
        log_error "Validation failed with ${validation_errors} errors"
        return 1
    fi
}

#########################################################################
# Main Deployment Function
#########################################################################

main() {
    log_info "Starting deployment of Performance Monitoring AI Agents infrastructure..."
    log_info "Script: $(basename "$0")"
    log_info "Version: 1.0"
    log_info "Log file: ${LOG_FILE}"
    
    # Check for dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log_info "DRY RUN MODE: No resources will be created"
        export DRY_RUN=true
    else
        export DRY_RUN=false
    fi
    
    # Deployment steps
    check_prerequisites
    setup_environment
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would create the following resources:"
        log_info "  - S3 bucket: ${S3_BUCKET_NAME}"
        log_info "  - Lambda function: ${LAMBDA_FUNCTION_NAME}"
        log_info "  - CloudWatch dashboard: ${DASHBOARD_NAME}"
        log_info "  - CloudWatch alarms: 3 alarms"
        log_info "  - CloudWatch log groups: 4 groups"
        log_info "  - IAM roles: 2 roles"
        log_success "DRY RUN completed successfully"
        return 0
    fi
    
    # Actual deployment
    create_s3_bucket
    create_agentcore_iam_role
    create_cloudwatch_log_groups
    create_lambda_function
    create_cloudwatch_dashboard
    create_cloudwatch_alarms
    create_custom_metrics
    
    # Validate deployment
    if ! validate_deployment; then
        log_error "Deployment validation failed"
        exit 1
    fi
    
    # Display deployment summary
    log_success "Deployment completed successfully!"
    echo
    log_info "=== DEPLOYMENT SUMMARY ==="
    log_info "AWS Region: ${AWS_REGION}"
    log_info "Agent Name: ${AGENT_NAME}"
    log_info "S3 Bucket: s3://${S3_BUCKET_NAME}"
    log_info "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log_info "CloudWatch Dashboard: ${DASHBOARD_NAME}"
    log_info "Configuration file: ${SCRIPT_DIR}/deployment_config.env"
    echo
    log_info "CloudWatch Dashboard URL:"
    log_info "https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
    echo
    log_info "S3 Bucket URL:"
    log_info "https://s3.console.aws.amazon.com/s3/buckets/${S3_BUCKET_NAME}?region=${AWS_REGION}"
    echo
    log_info "Next Steps:"
    log_info "1. Configure your AgentCore agent to use the monitoring role: ${AGENTCORE_ROLE_ARN}"
    log_info "2. View the CloudWatch dashboard for real-time monitoring"
    log_info "3. Check S3 bucket for performance reports generated by alarms"
    log_info "4. Use 'destroy.sh' to clean up resources when no longer needed"
    echo
    log_success "Performance monitoring infrastructure is ready!"
}

# Run main function with all arguments
main "$@"