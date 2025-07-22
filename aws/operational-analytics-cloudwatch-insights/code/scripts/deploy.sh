#!/bin/bash

# =============================================================================
# AWS Operational Analytics with CloudWatch Insights - Deployment Script
# =============================================================================
# This script deploys a comprehensive operational analytics solution using 
# CloudWatch Logs Insights for log pattern analysis, custom queries, 
# and automated alerting on operational anomalies.
# =============================================================================

set -euo pipefail

# Configuration variables
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly DRY_RUN="${DRY_RUN:-false}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warn() {
    log "WARN" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command '$1' not found. Please install it and try again."
        exit 1
    fi
}

check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid. Please run 'aws configure' first."
        exit 1
    fi
}

validate_region() {
    local region="$1"
    if ! aws ec2 describe-regions --region-names "$region" &> /dev/null; then
        log_error "Invalid AWS region: $region"
        exit 1
    fi
}

cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code $exit_code"
        log_warn "Check $LOG_FILE for details"
        log_warn "To cleanup resources, run the destroy.sh script"
    fi
}

wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local max_attempts="${3:-30}"
    local check_interval="${4:-10}"
    
    log_info "Waiting for $resource_type '$resource_name' to be ready..."
    
    for ((i=1; i<=max_attempts; i++)); do
        case "$resource_type" in
            "lambda")
                if aws lambda get-function --function-name "$resource_name" &> /dev/null; then
                    log_success "$resource_type '$resource_name' is ready"
                    return 0
                fi
                ;;
            "log-group")
                if aws logs describe-log-groups --log-group-name-prefix "$resource_name" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$resource_name"; then
                    log_success "$resource_type '$resource_name' is ready"
                    return 0
                fi
                ;;
            *)
                log_error "Unknown resource type: $resource_type"
                return 1
                ;;
        esac
        
        if [[ $i -eq $max_attempts ]]; then
            log_error "Timeout waiting for $resource_type '$resource_name'"
            return 1
        fi
        
        log_info "Attempt $i/$max_attempts failed, waiting ${check_interval}s..."
        sleep "$check_interval"
    done
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check required commands
    local required_commands=("aws" "zip" "jq")
    for cmd in "${required_commands[@]}"; do
        check_command "$cmd"
    done
    
    # Check AWS credentials
    check_aws_credentials
    
    # Validate AWS region
    validate_region "$AWS_REGION"
    
    # Check if we can list S3 buckets (basic permission check)
    if ! aws s3 ls &> /dev/null; then
        log_error "AWS credentials don't have sufficient permissions. S3 list access is required."
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

check_existing_resources() {
    log_info "Checking for existing resources..."
    
    local conflicts=0
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        log_warn "Lambda function '$LAMBDA_FUNCTION_NAME' already exists"
        ((conflicts++))
    fi
    
    # Check Log Group
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
        log_warn "Log group '$LOG_GROUP_NAME' already exists"
        ((conflicts++))
    fi
    
    # Check SNS Topic
    if aws sns get-topic-attributes --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" &> /dev/null; then
        log_warn "SNS topic '$SNS_TOPIC_NAME' already exists"
        ((conflicts++))
    fi
    
    # Check Dashboard
    if aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" &> /dev/null; then
        log_warn "CloudWatch dashboard '$DASHBOARD_NAME' already exists"
        ((conflicts++))
    fi
    
    if [[ $conflicts -gt 0 ]]; then
        log_warn "Found $conflicts existing resources. Deployment will update/overwrite them."
        if [[ "${FORCE_DEPLOY:-false}" != "true" ]]; then
            read -p "Continue with deployment? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Deployment cancelled by user"
                exit 0
            fi
        fi
    fi
}

# =============================================================================
# Resource Creation Functions
# =============================================================================

set_environment_variables() {
    log_info "Setting environment variables..."
    
    # Export required environment variables
    export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
    export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
    
    # Generate unique suffix for resources
    local random_suffix
    if command -v openssl &> /dev/null; then
        random_suffix=$(openssl rand -hex 3)
    else
        random_suffix=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    fi
    
    # Set resource names with validation
    export LOG_GROUP_NAME="${LOG_GROUP_NAME:-/aws/lambda/operational-analytics-demo-${random_suffix}}"
    export DASHBOARD_NAME="${DASHBOARD_NAME:-OperationalAnalytics-${random_suffix}}"
    export SNS_TOPIC_NAME="${SNS_TOPIC_NAME:-operational-alerts-${random_suffix}}"
    export LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:-log-generator-${random_suffix}}"
    export IAM_ROLE_NAME="${IAM_ROLE_NAME:-LogGeneratorRole-${random_suffix}}"
    
    # Validate resource names
    if [[ ${#LAMBDA_FUNCTION_NAME} -gt 64 ]]; then
        log_error "Lambda function name too long: $LAMBDA_FUNCTION_NAME"
        exit 1
    fi
    
    log_info "Environment variables set:"
    log_info "  AWS_REGION: $AWS_REGION"
    log_info "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    log_info "  LOG_GROUP_NAME: $LOG_GROUP_NAME"
    log_info "  LAMBDA_FUNCTION_NAME: $LAMBDA_FUNCTION_NAME"
    log_info "  SNS_TOPIC_NAME: $SNS_TOPIC_NAME"
    log_info "  DASHBOARD_NAME: $DASHBOARD_NAME"
}

create_log_group() {
    log_info "Creating CloudWatch Log Group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create log group: $LOG_GROUP_NAME"
        return 0
    fi
    
    # Create log group if it doesn't exist
    if ! aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
        aws logs create-log-group \
            --log-group-name "$LOG_GROUP_NAME" \
            --log-group-class "STANDARD" \
            --tags "Project=OperationalAnalytics,CreatedBy=DeployScript"
        
        log_success "Created log group: $LOG_GROUP_NAME"
    else
        log_info "Log group already exists: $LOG_GROUP_NAME"
    fi
    
    # Set retention policy for cost optimization
    aws logs put-retention-policy \
        --log-group-name "$LOG_GROUP_NAME" \
        --retention-in-days 7
    
    log_success "Set 7-day retention policy for log group"
}

create_iam_role() {
    log_info "Creating IAM role for Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create IAM role: $IAM_ROLE_NAME"
        return 0
    fi
    
    # Create trust policy
    local trust_policy_file="${SCRIPT_DIR}/trust-policy.json"
    cat > "$trust_policy_file" << 'EOF'
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
    
    # Create IAM role if it doesn't exist
    if ! aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        aws iam create-role \
            --role-name "$IAM_ROLE_NAME" \
            --assume-role-policy-document "file://$trust_policy_file" \
            --tags "Key=Project,Value=OperationalAnalytics" "Key=CreatedBy,Value=DeployScript"
        
        log_success "Created IAM role: $IAM_ROLE_NAME"
    else
        log_info "IAM role already exists: $IAM_ROLE_NAME"
    fi
    
    # Attach CloudWatch Logs permissions
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    log_success "Attached CloudWatch Logs permissions to IAM role"
    
    # Wait for role to be available
    sleep 10
    
    # Cleanup temporary file
    rm -f "$trust_policy_file"
}

create_lambda_function() {
    log_info "Creating Lambda function for log generation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Lambda function: $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    # Create Lambda function code
    local lambda_code_file="${SCRIPT_DIR}/log-generator.py"
    cat > "$lambda_code_file" << 'EOF'
import json
import random
import time
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    # Generate various log patterns for analytics
    log_patterns = [
        {"level": "INFO", "message": "User authentication successful", "user_id": f"user_{random.randint(1000, 9999)}", "response_time": random.randint(100, 500)},
        {"level": "ERROR", "message": "Database connection failed", "error_code": "DB_CONN_ERR", "retry_count": random.randint(1, 3)},
        {"level": "WARN", "message": "High memory usage detected", "memory_usage": random.randint(70, 95), "threshold": 80},
        {"level": "INFO", "message": "API request processed", "endpoint": f"/api/v1/users/{random.randint(1, 100)}", "method": random.choice(["GET", "POST", "PUT"])},
        {"level": "ERROR", "message": "Payment processing failed", "transaction_id": f"txn_{random.randint(100000, 999999)}", "amount": random.randint(10, 1000)},
        {"level": "INFO", "message": "Cache hit", "cache_key": f"user_profile_{random.randint(1, 1000)}", "hit_rate": random.uniform(0.7, 0.95)},
        {"level": "DEBUG", "message": "SQL query executed", "query_time": random.randint(50, 2000), "table": random.choice(["users", "orders", "products"])},
        {"level": "WARN", "message": "Rate limit approaching", "current_rate": random.randint(80, 99), "limit": 100}
    ]
    
    # Generate 5-10 random log entries
    for i in range(random.randint(5, 10)):
        log_entry = random.choice(log_patterns)
        log_entry["timestamp"] = datetime.utcnow().isoformat()
        log_entry["request_id"] = f"req_{random.randint(1000000, 9999999)}"
        
        # Log with different levels
        if log_entry["level"] == "ERROR":
            logger.error(json.dumps(log_entry))
        elif log_entry["level"] == "WARN":
            logger.warning(json.dumps(log_entry))
        elif log_entry["level"] == "DEBUG":
            logger.debug(json.dumps(log_entry))
        else:
            logger.info(json.dumps(log_entry))
        
        # Small delay to spread timestamps
        time.sleep(0.1)
    
    return {
        'statusCode': 200,
        'body': json.dumps('Log generation completed')
    }
EOF
    
    # Create deployment package
    local zip_file="${SCRIPT_DIR}/log-generator.zip"
    (cd "$SCRIPT_DIR" && zip -q "$zip_file" "$(basename "$lambda_code_file")")
    
    # Create or update Lambda function
    local role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/$IAM_ROLE_NAME"
    
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        # Update existing function
        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --zip-file "fileb://$zip_file"
        
        log_success "Updated Lambda function: $LAMBDA_FUNCTION_NAME"
    else
        # Create new function
        aws lambda create-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --runtime python3.9 \
            --role "$role_arn" \
            --handler "$(basename "$lambda_code_file" .py).lambda_handler" \
            --zip-file "fileb://$zip_file" \
            --timeout 30 \
            --tags "Project=OperationalAnalytics,CreatedBy=DeployScript"
        
        log_success "Created Lambda function: $LAMBDA_FUNCTION_NAME"
    fi
    
    # Wait for function to be active
    wait_for_resource "lambda" "$LAMBDA_FUNCTION_NAME"
    
    # Cleanup temporary files
    rm -f "$lambda_code_file" "$zip_file"
}

generate_sample_data() {
    log_info "Generating sample log data..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would generate sample log data"
        return 0
    fi
    
    # Invoke Lambda function multiple times to generate log data
    for i in {1..10}; do
        local output_file="${SCRIPT_DIR}/output-${i}.txt"
        if aws lambda invoke \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --payload '{}' \
            "$output_file" &> /dev/null; then
            log_info "Generated log batch $i/10"
            rm -f "$output_file"
        else
            log_error "Failed to generate log batch $i"
        fi
        sleep 2
    done
    
    # Wait for logs to be available
    log_info "Waiting for logs to be available in CloudWatch..."
    sleep 30
    
    log_success "Sample log data generated successfully"
}

create_sns_topic() {
    log_info "Creating SNS topic for alerts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create SNS topic: $SNS_TOPIC_NAME"
        return 0
    fi
    
    # Create SNS topic
    local topic_arn
    topic_arn=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --tags "Key=Project,Value=OperationalAnalytics,Key=CreatedBy,Value=DeployScript" \
        --query 'TopicArn' --output text)
    
    export SNS_TOPIC_ARN="$topic_arn"
    log_success "Created SNS topic: $SNS_TOPIC_NAME"
    log_info "Topic ARN: $SNS_TOPIC_ARN"
    
    # Subscribe to email notifications if email provided
    if [[ -n "${EMAIL_ADDRESS:-}" ]]; then
        aws sns subscribe \
            --topic-arn "$SNS_TOPIC_ARN" \
            --protocol email \
            --notification-endpoint "$EMAIL_ADDRESS"
        
        log_success "Subscribed email '$EMAIL_ADDRESS' to SNS topic"
        log_warn "Please check your email and confirm the subscription"
    else
        log_warn "No EMAIL_ADDRESS provided. You can subscribe to the topic later:"
        log_warn "aws sns subscribe --topic-arn '$SNS_TOPIC_ARN' --protocol email --notification-endpoint 'your-email@example.com'"
    fi
}

create_cloudwatch_dashboard() {
    log_info "Creating CloudWatch dashboard..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create CloudWatch dashboard: $DASHBOARD_NAME"
        return 0
    fi
    
    # Create dashboard configuration
    local dashboard_config_file="${SCRIPT_DIR}/dashboard-config.json"
    cat > "$dashboard_config_file" << EOF
{
  "widgets": [
    {
      "type": "log",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "Error Analysis",
        "query": "SOURCE '$LOG_GROUP_NAME' | fields @timestamp, @message\\n| filter @message like /ERROR/\\n| stats count() as error_count by bin(5m)\\n| sort @timestamp desc\\n| limit 50",
        "region": "$AWS_REGION",
        "view": "table",
        "stacked": false
      }
    },
    {
      "type": "log",
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "title": "Performance Metrics",
        "query": "SOURCE '$LOG_GROUP_NAME' | fields @timestamp, @message\\n| filter @message like /response_time/\\n| parse @message '\"response_time\": *' as response_time\\n| stats avg(response_time) as avg_response_time, max(response_time) as max_response_time by bin(1m)\\n| sort @timestamp desc",
        "region": "$AWS_REGION",
        "view": "table",
        "stacked": false
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 6,
      "width": 24,
      "height": 6,
      "properties": {
        "title": "Top Active Users",
        "query": "SOURCE '$LOG_GROUP_NAME' | fields @timestamp, @message\\n| filter @message like /user_id/\\n| parse @message '\"user_id\": \"*\"' as user_id\\n| stats count() as activity_count by user_id\\n| sort activity_count desc\\n| limit 20",
        "region": "$AWS_REGION",
        "view": "table",
        "stacked": false
      }
    }
  ]
}
EOF
    
    # Create the dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "$DASHBOARD_NAME" \
        --dashboard-body "file://$dashboard_config_file"
    
    log_success "Created CloudWatch dashboard: $DASHBOARD_NAME"
    log_info "Dashboard URL: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=$DASHBOARD_NAME"
    
    # Cleanup temporary file
    rm -f "$dashboard_config_file"
}

create_metric_filters_and_alarms() {
    log_info "Creating CloudWatch metric filters and alarms..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create metric filters and alarms"
        return 0
    fi
    
    # Create custom metric filter for error rate
    aws logs put-metric-filter \
        --log-group-name "$LOG_GROUP_NAME" \
        --filter-name "ErrorRateFilter" \
        --filter-pattern '[timestamp, requestId, level="ERROR", ...]' \
        --metric-transformations \
            metricName="ErrorRate" \
            metricNamespace="OperationalAnalytics" \
            metricValue="1" \
            defaultValue="0"
    
    log_success "Created error rate metric filter"
    
    # Create alarm for high error rate
    aws cloudwatch put-metric-alarm \
        --alarm-name "HighErrorRate-${RANDOM_SUFFIX:-$(date +%s | tail -c 6)}" \
        --alarm-description "Alert when error rate exceeds threshold" \
        --metric-name "ErrorRate" \
        --namespace "OperationalAnalytics" \
        --statistic "Sum" \
        --period 300 \
        --threshold 5 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --tags "Key=Project,Value=OperationalAnalytics,Key=CreatedBy,Value=DeployScript"
    
    log_success "Created high error rate alarm"
    
    # Create metric filter for log volume monitoring
    aws logs put-metric-filter \
        --log-group-name "$LOG_GROUP_NAME" \
        --filter-name "LogVolumeFilter" \
        --filter-pattern "" \
        --metric-transformations \
            metricName="LogVolume" \
            metricNamespace="OperationalAnalytics" \
            metricValue="1" \
            defaultValue="0"
    
    log_success "Created log volume metric filter"
    
    # Create alarm for excessive log volume
    aws cloudwatch put-metric-alarm \
        --alarm-name "HighLogVolume-${RANDOM_SUFFIX:-$(date +%s | tail -c 6)}" \
        --alarm-description "Alert when log volume exceeds budget threshold" \
        --metric-name "LogVolume" \
        --namespace "OperationalAnalytics" \
        --statistic "Sum" \
        --period 3600 \
        --threshold 10000 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 1 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --tags "Key=Project,Value=OperationalAnalytics,Key=CreatedBy,Value=DeployScript"
    
    log_success "Created high log volume alarm"
}

create_anomaly_detection() {
    log_info "Creating CloudWatch anomaly detection..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create anomaly detection"
        return 0
    fi
    
    # Create anomaly detector for log ingestion
    if aws cloudwatch put-anomaly-detector \
        --namespace "AWS/Logs" \
        --metric-name "IncomingBytes" \
        --dimensions Name=LogGroupName,Value="$LOG_GROUP_NAME" \
        --stat "Average" &> /dev/null; then
        
        log_success "Created anomaly detector for log ingestion"
        
        # Create anomaly alarm (simplified version to avoid complex JSON in bash)
        aws cloudwatch put-metric-alarm \
            --alarm-name "LogIngestionAnomaly-${RANDOM_SUFFIX:-$(date +%s | tail -c 6)}" \
            --alarm-description "Detect anomalies in log ingestion patterns" \
            --metric-name "IncomingBytes" \
            --namespace "AWS/Logs" \
            --statistic "Average" \
            --period 300 \
            --threshold 2 \
            --comparison-operator "LessThanThreshold" \
            --evaluation-periods 2 \
            --alarm-actions "$SNS_TOPIC_ARN" \
            --tags "Key=Project,Value=OperationalAnalytics,Key=CreatedBy,Value=DeployScript"
        
        log_success "Created log ingestion anomaly alarm"
    else
        log_warn "Failed to create anomaly detector. This may require historical data."
    fi
}

# =============================================================================
# Main Deployment Function
# =============================================================================

deploy_operational_analytics() {
    log_info "Starting deployment of AWS Operational Analytics solution..."
    
    # Set trap for cleanup on error
    trap cleanup_on_error EXIT
    
    # Phase 1: Validation and Setup
    validate_prerequisites
    set_environment_variables
    check_existing_resources
    
    # Phase 2: Core Infrastructure
    create_log_group
    create_iam_role
    create_lambda_function
    
    # Phase 3: Data Generation
    generate_sample_data
    
    # Phase 4: Analytics and Monitoring
    create_sns_topic
    create_cloudwatch_dashboard
    create_metric_filters_and_alarms
    create_anomaly_detection
    
    # Phase 5: Completion
    log_success "✅ AWS Operational Analytics deployment completed successfully!"
    
    echo
    log_info "=== Deployment Summary ==="
    log_info "Log Group: $LOG_GROUP_NAME"
    log_info "Lambda Function: $LAMBDA_FUNCTION_NAME"
    log_info "SNS Topic: $SNS_TOPIC_NAME"
    log_info "Dashboard: $DASHBOARD_NAME"
    log_info "Dashboard URL: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=$DASHBOARD_NAME"
    
    if [[ -n "${EMAIL_ADDRESS:-}" ]]; then
        echo
        log_warn "📧 Please check your email and confirm the SNS subscription to receive alerts"
    fi
    
    echo
    log_info "=== Next Steps ==="
    log_info "1. Review the CloudWatch dashboard for operational insights"
    log_info "2. Customize CloudWatch Insights queries based on your needs"
    log_info "3. Set up additional metric filters and alarms as required"
    log_info "4. Consider implementing automated remediation actions"
    
    # Remove error trap on successful completion
    trap - EXIT
}

# =============================================================================
# Script Entry Point
# =============================================================================

show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Deploy AWS Operational Analytics with CloudWatch Insights

OPTIONS:
    -h, --help              Show this help message
    -r, --region REGION     AWS region (default: current AWS CLI region)
    -e, --email EMAIL       Email address for SNS notifications
    -f, --force             Force deployment without confirmation
    -d, --dry-run           Show what would be deployed without making changes
    -v, --verbose           Enable verbose logging

ENVIRONMENT VARIABLES:
    AWS_REGION              AWS region to deploy resources
    EMAIL_ADDRESS           Email address for SNS notifications
    FORCE_DEPLOY            Set to 'true' to skip confirmation prompts
    DRY_RUN                 Set to 'true' to enable dry-run mode

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME --region us-west-2 --email admin@example.com
    $SCRIPT_NAME --dry-run --verbose
    DRY_RUN=true $SCRIPT_NAME

EOF
}

main() {
    # Initialize log file
    : > "$LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -r|--region)
                export AWS_REGION="$2"
                shift 2
                ;;
            -e|--email)
                export EMAIL_ADDRESS="$2"
                shift 2
                ;;
            -f|--force)
                export FORCE_DEPLOY="true"
                shift
                ;;
            -d|--dry-run)
                export DRY_RUN="true"
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Start deployment
    deploy_operational_analytics
}

# Execute main function with all arguments
main "$@"