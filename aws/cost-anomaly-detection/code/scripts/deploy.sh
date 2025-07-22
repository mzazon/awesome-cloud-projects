#!/bin/bash

# AWS Cost Anomaly Detection Deployment Script
# This script deploys cost anomaly detection infrastructure using AWS CLI
# Based on the recipe: Cost Anomaly Detection with Machine Learning

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
RESOURCES_FILE="${SCRIPT_DIR}/deployed_resources.txt"

# Default values - can be overridden by environment variables
DEFAULT_EMAIL="${COST_ANOMALY_EMAIL:-}"
DEFAULT_REGION="${AWS_REGION:-us-east-1}"
DRY_RUN="${DRY_RUN:-false}"

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ✅ SUCCESS: $1" | tee -a "$LOG_FILE"
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        log_error "Deployment failed. Check $LOG_FILE for details."
        log "Consider running the destroy script to clean up any partially created resources."
    fi
}

trap cleanup_on_exit EXIT

validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log_error "Invalid email format: $email"
        return 1
    fi
}

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        return 1
    fi
    
    local version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $version"
}

check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured or invalid."
        log "Please run 'aws configure' to set up your credentials."
        return 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region || echo "us-east-1")
    log "AWS Account ID: $account_id"
    log "AWS Region: $region"
}

check_cost_explorer_access() {
    log "Verifying Cost Explorer access..."
    
    # Try to make a simple Cost Explorer API call
    if aws ce get-cost-and-usage \
        --time-period Start=2024-01-01,End=2024-01-02 \
        --granularity MONTHLY \
        --metrics BlendedCost \
        --group-by Type=DIMENSION,Key=SERVICE \
        --query 'ResultsByTime[0].Total' &> /dev/null; then
        log_success "Cost Explorer access verified"
    else
        log_error "Cost Explorer access failed. Please ensure:"
        log "  1. Cost Explorer is enabled in your AWS account"
        log "  2. You have appropriate permissions for Cost Explorer"
        log "  3. Your account has billing data available"
        return 1
    fi
}

check_iam_permissions() {
    log "Checking IAM permissions..."
    
    local required_actions=(
        "ce:*"
        "sns:CreateTopic"
        "sns:Subscribe"
        "events:PutRule"
        "events:PutTargets"
        "lambda:CreateFunction"
        "lambda:AddPermission"
        "cloudwatch:PutDashboard"
        "logs:CreateLogGroup"
    )
    
    # Note: This is a basic check. In practice, you might want to use
    # aws iam simulate-principal-policy for more thorough testing
    log "Required permissions: ${required_actions[*]}"
    log "⚠️  Please ensure you have the necessary IAM permissions"
}

resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "$resource_type" in
        "sns-topic")
            aws sns list-topics --query "Topics[?contains(TopicArn, '$resource_name')]" --output text | grep -q "$resource_name"
            ;;
        "anomaly-monitor")
            aws ce get-anomaly-monitors --query "AnomalyMonitors[?MonitorName=='$resource_name']" --output text | grep -q "$resource_name"
            ;;
        "anomaly-subscription")
            aws ce get-anomaly-subscriptions --query "AnomalySubscriptions[?SubscriptionName=='$resource_name']" --output text | grep -q "$resource_name"
            ;;
        "lambda-function")
            aws lambda get-function --function-name "$resource_name" &> /dev/null
            ;;
        "eventbridge-rule")
            aws events describe-rule --name "$resource_name" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

save_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_arn="$3"
    
    echo "${resource_type}|${resource_name}|${resource_arn}" >> "$RESOURCES_FILE"
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================

deploy_sns_topic() {
    local topic_name="$1"
    local email="$2"
    
    log "Creating SNS topic: $topic_name"
    
    if resource_exists "sns-topic" "$topic_name"; then
        log "SNS topic $topic_name already exists, skipping creation"
        local topic_arn=$(aws sns list-topics --query "Topics[?contains(TopicArn, '$topic_name')].TopicArn" --output text)
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would create SNS topic: $topic_name"
            return 0
        fi
        
        local topic_arn=$(aws sns create-topic \
            --name "$topic_name" \
            --query 'TopicArn' --output text)
        
        save_resource "sns-topic" "$topic_name" "$topic_arn"
        log_success "Created SNS topic: $topic_arn"
    fi
    
    # Subscribe email to topic
    log "Subscribing email to SNS topic: $email"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would subscribe email: $email"
        return 0
    fi
    
    aws sns subscribe \
        --topic-arn "$topic_arn" \
        --protocol email \
        --notification-endpoint "$email"
    
    log_success "Email subscription created. Please check $email to confirm subscription."
    
    echo "$topic_arn"
}

deploy_anomaly_monitors() {
    log "Creating Cost Anomaly Detection monitors..."
    
    local monitors=()
    
    # AWS Services Monitor
    local services_monitor_name="AWS-Services-Monitor"
    if resource_exists "anomaly-monitor" "$services_monitor_name"; then
        log "Monitor $services_monitor_name already exists, skipping creation"
        local services_monitor_arn=$(aws ce get-anomaly-monitors --query "AnomalyMonitors[?MonitorName=='$services_monitor_name'].MonitorArn" --output text)
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would create AWS Services monitor"
        else
            local services_monitor_arn=$(aws ce create-anomaly-monitor \
                --anomaly-monitor '{
                    "MonitorName": "'$services_monitor_name'",
                    "MonitorType": "DIMENSIONAL",
                    "MonitorDimension": "SERVICE"
                }' \
                --query 'MonitorArn' --output text)
            
            save_resource "anomaly-monitor" "$services_monitor_name" "$services_monitor_arn"
            log_success "Created AWS Services monitor: $services_monitor_arn"
        fi
    fi
    monitors+=("$services_monitor_arn")
    
    # Account-Based Monitor
    local account_monitor_name="Account-Based-Monitor"
    if resource_exists "anomaly-monitor" "$account_monitor_name"; then
        log "Monitor $account_monitor_name already exists, skipping creation"
        local account_monitor_arn=$(aws ce get-anomaly-monitors --query "AnomalyMonitors[?MonitorName=='$account_monitor_name'].MonitorArn" --output text)
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would create Account-Based monitor"
        else
            local account_monitor_arn=$(aws ce create-anomaly-monitor \
                --anomaly-monitor '{
                    "MonitorName": "'$account_monitor_name'",
                    "MonitorType": "DIMENSIONAL",
                    "MonitorDimension": "LINKED_ACCOUNT"
                }' \
                --query 'MonitorArn' --output text)
            
            save_resource "anomaly-monitor" "$account_monitor_name" "$account_monitor_arn"
            log_success "Created Account-Based monitor: $account_monitor_arn"
        fi
    fi
    monitors+=("$account_monitor_arn")
    
    # Tag-Based Monitor
    local tag_monitor_name="Environment-Tag-Monitor"
    if resource_exists "anomaly-monitor" "$tag_monitor_name"; then
        log "Monitor $tag_monitor_name already exists, skipping creation"
        local tag_monitor_arn=$(aws ce get-anomaly-monitors --query "AnomalyMonitors[?MonitorName=='$tag_monitor_name'].MonitorArn" --output text)
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would create Tag-Based monitor"
        else
            local tag_monitor_arn=$(aws ce create-anomaly-monitor \
                --anomaly-monitor '{
                    "MonitorName": "'$tag_monitor_name'",
                    "MonitorType": "CUSTOM",
                    "MonitorSpecification": {
                        "Tags": {
                            "Key": "Environment",
                            "Values": ["Production", "Staging"],
                            "MatchOptions": ["EQUALS"]
                        }
                    }
                }' \
                --query 'MonitorArn' --output text)
            
            save_resource "anomaly-monitor" "$tag_monitor_name" "$tag_monitor_arn"
            log_success "Created Tag-Based monitor: $tag_monitor_arn"
        fi
    fi
    monitors+=("$tag_monitor_arn")
    
    echo "${monitors[@]}"
}

deploy_anomaly_subscriptions() {
    local email="$1"
    local topic_arn="$2"
    shift 2
    local monitors=("$@")
    
    log "Creating anomaly subscriptions..."
    
    # Daily Summary Subscription
    local daily_subscription_name="Daily-Cost-Summary"
    if resource_exists "anomaly-subscription" "$daily_subscription_name"; then
        log "Subscription $daily_subscription_name already exists, skipping creation"
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would create daily summary subscription"
        else
            local daily_subscription_arn=$(aws ce create-anomaly-subscription \
                --anomaly-subscription '{
                    "SubscriptionName": "'$daily_subscription_name'",
                    "Frequency": "DAILY",
                    "MonitorArnList": [
                        "'${monitors[0]}'",
                        "'${monitors[1]}'"
                    ],
                    "Subscribers": [
                        {
                            "Address": "'$email'",
                            "Type": "EMAIL"
                        }
                    ],
                    "ThresholdExpression": {
                        "And": [
                            {
                                "Dimensions": {
                                    "Key": "ANOMALY_TOTAL_IMPACT_ABSOLUTE",
                                    "Values": ["100"]
                                }
                            }
                        ]
                    }
                }' \
                --query 'SubscriptionArn' --output text)
            
            save_resource "anomaly-subscription" "$daily_subscription_name" "$daily_subscription_arn"
            log_success "Created Daily Summary subscription: $daily_subscription_arn"
        fi
    fi
    
    # Individual Alert Subscription
    local individual_subscription_name="Individual-Cost-Alerts"
    if resource_exists "anomaly-subscription" "$individual_subscription_name"; then
        log "Subscription $individual_subscription_name already exists, skipping creation"
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would create individual alerts subscription"
        else
            local individual_subscription_arn=$(aws ce create-anomaly-subscription \
                --anomaly-subscription '{
                    "SubscriptionName": "'$individual_subscription_name'",
                    "Frequency": "IMMEDIATE",
                    "MonitorArnList": [
                        "'${monitors[2]}'"
                    ],
                    "Subscribers": [
                        {
                            "Address": "'$topic_arn'",
                            "Type": "SNS"
                        }
                    ],
                    "ThresholdExpression": {
                        "And": [
                            {
                                "Dimensions": {
                                    "Key": "ANOMALY_TOTAL_IMPACT_ABSOLUTE",
                                    "Values": ["50"]
                                }
                            }
                        ]
                    }
                }' \
                --query 'SubscriptionArn' --output text)
            
            save_resource "anomaly-subscription" "$individual_subscription_name" "$individual_subscription_arn"
            log_success "Created Individual Alerts subscription: $individual_subscription_arn"
        fi
    fi
}

deploy_eventbridge_integration() {
    local lambda_arn="$1"
    
    log "Creating EventBridge rule for cost anomaly events..."
    
    local rule_name="cost-anomaly-detection-rule"
    if resource_exists "eventbridge-rule" "$rule_name"; then
        log "EventBridge rule $rule_name already exists, skipping creation"
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would create EventBridge rule: $rule_name"
        else
            aws events put-rule \
                --name "$rule_name" \
                --event-pattern '{
                    "source": ["aws.ce"],
                    "detail-type": ["Cost Anomaly Detection"]
                }' \
                --description "Capture AWS Cost Anomaly Detection events"
            
            save_resource "eventbridge-rule" "$rule_name" "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/$rule_name"
            log_success "Created EventBridge rule: $rule_name"
        fi
    fi
    
    # Add Lambda as target
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would add Lambda function as EventBridge target"
        log "[DRY RUN] Would grant EventBridge permission to invoke Lambda"
    else
        aws events put-targets \
            --rule "$rule_name" \
            --targets "Id"="1","Arn"="$lambda_arn"
        
        # Grant EventBridge permission to invoke Lambda
        aws lambda add-permission \
            --function-name "cost-anomaly-processor" \
            --statement-id "allow-eventbridge-invoke" \
            --action "lambda:InvokeFunction" \
            --principal events.amazonaws.com \
            --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/$rule_name" \
            2>/dev/null || log "Lambda permission may already exist"
        
        log_success "Configured EventBridge to invoke Lambda function"
    fi
}

deploy_lambda_function() {
    local function_name="cost-anomaly-processor"
    
    log "Creating Lambda function: $function_name"
    
    if resource_exists "lambda-function" "$function_name"; then
        log "Lambda function $function_name already exists, skipping creation"
        local lambda_arn=$(aws lambda get-function --function-name "$function_name" --query 'Configuration.FunctionArn' --output text)
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would create Lambda function: $function_name"
            echo "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:$function_name"
            return 0
        fi
        
        # Create Lambda function code
        local temp_dir=$(mktemp -d)
        cat > "$temp_dir/anomaly-processor.py" << 'EOF'
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Process cost anomaly detection events and take automated actions"""
    
    try:
        # Log the incoming event
        logger.info(f"Received cost anomaly event: {json.dumps(event)}")
        
        # Extract anomaly details
        detail = event.get('detail', {})
        anomaly_score = detail.get('anomalyScore', 0)
        impact = detail.get('impact', {})
        total_impact = impact.get('totalImpact', 0)
        
        # Determine severity level
        if total_impact > 500:
            severity = "HIGH"
        elif total_impact > 100:
            severity = "MEDIUM"
        else:
            severity = "LOW"
        
        # Log anomaly details
        logger.info(f"Anomaly detected - Score: {anomaly_score}, Impact: ${total_impact}, Severity: {severity}")
        
        # Send to CloudWatch Logs for further analysis
        cloudwatch = boto3.client('logs')
        log_group = '/aws/lambda/cost-anomaly-processor'
        log_stream = f"anomaly-{datetime.now().strftime('%Y-%m-%d')}"
        
        try:
            cloudwatch.create_log_group(logGroupName=log_group)
        except cloudwatch.exceptions.ResourceAlreadyExistsException:
            pass
        
        try:
            cloudwatch.create_log_stream(
                logGroupName=log_group,
                logStreamName=log_stream
            )
        except cloudwatch.exceptions.ResourceAlreadyExistsException:
            pass
        
        # Log structured anomaly data
        structured_log = {
            "timestamp": datetime.now().isoformat(),
            "anomaly_score": anomaly_score,
            "total_impact": total_impact,
            "severity": severity,
            "event_detail": detail
        }
        
        cloudwatch.put_log_events(
            logGroupName=log_group,
            logStreamName=log_stream,
            logEvents=[
                {
                    'timestamp': int(datetime.now().timestamp() * 1000),
                    'message': json.dumps(structured_log)
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost anomaly processed successfully',
                'severity': severity,
                'impact': total_impact
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing cost anomaly: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error processing cost anomaly',
                'error': str(e)
            })
        }
EOF
        
        # Create deployment package
        cd "$temp_dir" && zip anomaly-processor.zip anomaly-processor.py
        
        # Create IAM role for Lambda (basic execution role)
        local role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda-execution-role"
        
        # Check if role exists, create if not
        if ! aws iam get-role --role-name lambda-execution-role &> /dev/null; then
            log "Creating IAM role for Lambda function..."
            
            cat > "$temp_dir/trust-policy.json" << 'EOF'
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
                --role-name lambda-execution-role \
                --assume-role-policy-document file://"$temp_dir/trust-policy.json"
            
            aws iam attach-role-policy \
                --role-name lambda-execution-role \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
            
            aws iam attach-role-policy \
                --role-name lambda-execution-role \
                --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
            
            log "Waiting for role to be available..."
            sleep 10
        fi
        
        # Create Lambda function
        local lambda_arn=$(aws lambda create-function \
            --function-name "$function_name" \
            --runtime python3.9 \
            --role "$role_arn" \
            --handler anomaly-processor.lambda_handler \
            --zip-file fileb://anomaly-processor.zip \
            --description "Process cost anomaly detection events" \
            --timeout 60 \
            --query 'FunctionArn' --output text)
        
        save_resource "lambda-function" "$function_name" "$lambda_arn"
        log_success "Created Lambda function: $lambda_arn"
        
        # Cleanup
        rm -rf "$temp_dir"
    fi
    
    echo "$lambda_arn"
}

deploy_cloudwatch_dashboard() {
    log "Creating CloudWatch dashboard for cost anomaly monitoring..."
    
    local dashboard_name="Cost-Anomaly-Detection-Dashboard"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create CloudWatch dashboard: $dashboard_name"
        return 0
    fi
    
    aws cloudwatch put-dashboard \
        --dashboard-name "$dashboard_name" \
        --dashboard-body '{
            "widgets": [
                {
                    "type": "log",
                    "x": 0,
                    "y": 0,
                    "width": 12,
                    "height": 6,
                    "properties": {
                        "query": "SOURCE \"/aws/lambda/cost-anomaly-processor\"\n| fields @timestamp, severity, total_impact, anomaly_score\n| filter severity = \"HIGH\"\n| sort @timestamp desc\n| limit 20",
                        "region": "'$AWS_REGION'",
                        "title": "High Impact Cost Anomalies",
                        "view": "table"
                    }
                },
                {
                    "type": "log",
                    "x": 0,
                    "y": 6,
                    "width": 12,
                    "height": 6,
                    "properties": {
                        "query": "SOURCE \"/aws/lambda/cost-anomaly-processor\"\n| fields @timestamp, severity, total_impact\n| stats count() by severity\n| sort severity desc",
                        "region": "'$AWS_REGION'",
                        "title": "Anomaly Count by Severity",
                        "view": "table"
                    }
                }
            ]
        }'
    
    save_resource "cloudwatch-dashboard" "$dashboard_name" "https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${dashboard_name}"
    log_success "Created CloudWatch dashboard: $dashboard_name"
}

# =============================================================================
# MAIN DEPLOYMENT FUNCTION
# =============================================================================

main() {
    log "Starting AWS Cost Anomaly Detection deployment..."
    log "Script directory: $SCRIPT_DIR"
    log "Log file: $LOG_FILE"
    log "Resources file: $RESOURCES_FILE"
    
    # Initialize resources file
    echo "# Deployed resources - $(date)" > "$RESOURCES_FILE"
    echo "# Format: type|name|arn" >> "$RESOURCES_FILE"
    
    # Get email for notifications
    if [[ -z "$DEFAULT_EMAIL" ]]; then
        read -p "Enter email address for cost anomaly notifications: " email
    else
        email="$DEFAULT_EMAIL"
    fi
    
    # Validate email
    validate_email "$email"
    
    # Set environment variables
    export AWS_REGION="$DEFAULT_REGION"
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    local topic_name="cost-anomaly-alerts-${random_suffix}"
    
    log "Configuration:"
    log "  Email: $email"
    log "  Region: $AWS_REGION"
    log "  Account ID: $AWS_ACCOUNT_ID"
    log "  SNS Topic: $topic_name"
    log "  Dry Run: $DRY_RUN"
    
    # Prerequisites check
    log "Checking prerequisites..."
    check_aws_cli
    check_aws_credentials
    check_cost_explorer_access
    check_iam_permissions
    
    # Deploy infrastructure
    log "Deploying infrastructure components..."
    
    # 1. Deploy SNS topic
    local topic_arn=$(deploy_sns_topic "$topic_name" "$email")
    
    # 2. Deploy anomaly monitors
    local monitors=($(deploy_anomaly_monitors))
    
    # 3. Deploy anomaly subscriptions
    deploy_anomaly_subscriptions "$email" "$topic_arn" "${monitors[@]}"
    
    # 4. Deploy Lambda function
    local lambda_arn=$(deploy_lambda_function)
    
    # 5. Deploy EventBridge integration
    deploy_eventbridge_integration "$lambda_arn"
    
    # 6. Deploy CloudWatch dashboard
    deploy_cloudwatch_dashboard
    
    # Summary
    log_success "Deployment completed successfully!"
    log ""
    log "=== DEPLOYMENT SUMMARY ==="
    log "SNS Topic ARN: $topic_arn"
    log "Anomaly Monitors: ${#monitors[@]} created"
    log "Lambda Function ARN: $lambda_arn"
    log "CloudWatch Dashboard: Cost-Anomaly-Detection-Dashboard"
    log ""
    log "=== NEXT STEPS ==="
    log "1. Confirm your email subscription to receive notifications"
    log "2. Wait 10+ days for Cost Anomaly Detection to learn your spending patterns"
    log "3. Monitor the CloudWatch dashboard for anomaly insights"
    log "4. Review and customize anomaly thresholds as needed"
    log ""
    log "All deployed resources are tracked in: $RESOURCES_FILE"
    log "To clean up resources, run the destroy script: $SCRIPT_DIR/destroy.sh"
}

# =============================================================================
# HELP FUNCTION
# =============================================================================

show_help() {
    cat << EOF
AWS Cost Anomaly Detection Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -e, --email EMAIL       Email address for notifications (can also set COST_ANOMALY_EMAIL env var)
    -r, --region REGION     AWS region (default: us-east-1, can also set AWS_REGION env var)
    -d, --dry-run          Show what would be deployed without making changes
    -h, --help             Show this help message

ENVIRONMENT VARIABLES:
    COST_ANOMALY_EMAIL     Email address for notifications
    AWS_REGION             AWS region to deploy resources
    DRY_RUN               Set to 'true' for dry run mode

EXAMPLES:
    # Interactive deployment
    $0

    # Deployment with email specified
    $0 --email user@example.com

    # Dry run to see what would be deployed
    $0 --dry-run

    # Deployment in specific region
    $0 --region us-west-2 --email user@example.com

EOF
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--email)
            DEFAULT_EMAIL="$2"
            shift 2
            ;;
        -r|--region)
            DEFAULT_REGION="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
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

# =============================================================================
# MAIN EXECUTION
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi