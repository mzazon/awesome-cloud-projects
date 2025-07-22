#!/bin/bash

# AWS Chaos Engineering Testing with FIS and EventBridge - Deployment Script
# This script deploys the complete chaos engineering infrastructure including
# FIS experiment templates, EventBridge rules, CloudWatch alarms, and SNS notifications

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Some resources may have been created."
    log_info "Run ./destroy.sh to clean up any partial deployment."
    exit 1
}

trap cleanup_on_error ERR

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
EMAIL_ADDRESS="${EMAIL_ADDRESS:-}"
DRY_RUN="${DRY_RUN:-false}"

# Start logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

log_info "Starting AWS Chaos Engineering deployment..."
log_info "Deployment log: $LOG_FILE"

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$account_id" ]]; then
        log_error "Unable to retrieve AWS account ID. Check your credentials."
        exit 1
    fi
    
    # Validate email address for SNS
    if [[ -z "$EMAIL_ADDRESS" ]]; then
        read -p "Enter email address for SNS notifications: " EMAIL_ADDRESS
        if [[ ! "$EMAIL_ADDRESS" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            log_error "Invalid email address format."
            exit 1
        fi
    fi
    
    log_success "Prerequisites validated successfully"
}

# Initialize environment variables
initialize_environment() {
    log_info "Initializing environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        log_warning "No default region configured. Using us-east-1"
        export AWS_REGION="us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export EXPERIMENT_NAME="chaos-experiment-${random_suffix}"
    export SNS_TOPIC_NAME="fis-alerts-${random_suffix}"
    export DASHBOARD_NAME="chaos-monitoring-${random_suffix}"
    export RANDOM_SUFFIX="$random_suffix"
    
    # Save environment variables for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
EXPERIMENT_NAME=${EXPERIMENT_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
DASHBOARD_NAME=${DASHBOARD_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EMAIL_ADDRESS=${EMAIL_ADDRESS}
EOF
    
    log_success "Environment initialized with region: $AWS_REGION"
    log_info "Resource suffix: $RANDOM_SUFFIX"
}

# Create SNS topic and subscription
create_sns_resources() {
    log_info "Creating SNS topic and subscription..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would create SNS topic $SNS_TOPIC_NAME"
        export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
        return 0
    fi
    
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --query TopicArn --output text)
    
    if [[ -z "$SNS_TOPIC_ARN" ]]; then
        log_error "Failed to create SNS topic"
        return 1
    fi
    
    # Subscribe email to SNS topic
    aws sns subscribe \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --protocol email \
        --notification-endpoint "${EMAIL_ADDRESS}" >/dev/null
    
    # Save SNS ARN for cleanup
    echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> "${SCRIPT_DIR}/.env"
    
    log_success "SNS topic created: $SNS_TOPIC_ARN"
    log_warning "Please check your email ($EMAIL_ADDRESS) to confirm SNS subscription"
}

# Create IAM role for FIS experiments
create_fis_iam_role() {
    log_info "Creating IAM role for FIS experiments..."
    
    # Create trust policy file
    cat > "${SCRIPT_DIR}/fis-trust-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "fis.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would create IAM role FISExperimentRole-${RANDOM_SUFFIX}"
        export FIS_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/FISExperimentRole-${RANDOM_SUFFIX}"
        return 0
    fi
    
    # Create the IAM role
    export FIS_ROLE_ARN=$(aws iam create-role \
        --role-name "FISExperimentRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document "file://${SCRIPT_DIR}/fis-trust-policy.json" \
        --query Role.Arn --output text)
    
    # Attach AWS managed policy
    aws iam attach-role-policy \
        --role-name "FISExperimentRole-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
    
    # Save role ARN for cleanup
    echo "FIS_ROLE_ARN=${FIS_ROLE_ARN}" >> "${SCRIPT_DIR}/.env"
    echo "FIS_ROLE_NAME=FISExperimentRole-${RANDOM_SUFFIX}" >> "${SCRIPT_DIR}/.env"
    
    log_success "FIS IAM role created: $FIS_ROLE_ARN"
}

# Create CloudWatch alarms for stop conditions
create_cloudwatch_alarms() {
    log_info "Creating CloudWatch alarms for stop conditions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would create CloudWatch alarms"
        export ERROR_ALARM_ARN="arn:aws:cloudwatch:${AWS_REGION}:${AWS_ACCOUNT_ID}:alarm:FIS-HighErrorRate-${RANDOM_SUFFIX}"
        export CPU_ALARM_ARN="arn:aws:cloudwatch:${AWS_REGION}:${AWS_ACCOUNT_ID}:alarm:FIS-HighCPU-${RANDOM_SUFFIX}"
        return 0
    fi
    
    # Create alarm for high error rate
    export ERROR_ALARM_ARN=$(aws cloudwatch put-metric-alarm \
        --alarm-name "FIS-HighErrorRate-${RANDOM_SUFFIX}" \
        --alarm-description "Stop FIS experiment on high errors" \
        --metric-name 4XXError \
        --namespace AWS/ApplicationELB \
        --statistic Sum \
        --period 60 \
        --evaluation-periods 2 \
        --threshold 50 \
        --comparison-operator GreaterThanThreshold \
        --treat-missing-data notBreaching \
        --query AlarmArn --output text)
    
    # Create alarm for high CPU utilization
    export CPU_ALARM_ARN=$(aws cloudwatch put-metric-alarm \
        --alarm-name "FIS-HighCPU-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor CPU during experiments" \
        --metric-name CPUUtilization \
        --namespace AWS/EC2 \
        --statistic Average \
        --period 300 \
        --evaluation-periods 1 \
        --threshold 90 \
        --comparison-operator GreaterThanThreshold \
        --query AlarmArn --output text)
    
    # Save alarm ARNs for cleanup
    echo "ERROR_ALARM_ARN=${ERROR_ALARM_ARN}" >> "${SCRIPT_DIR}/.env"
    echo "CPU_ALARM_ARN=${CPU_ALARM_ARN}" >> "${SCRIPT_DIR}/.env"
    
    log_success "CloudWatch alarms created successfully"
}

# Create FIS experiment template
create_experiment_template() {
    log_info "Creating FIS experiment template..."
    
    # Create experiment template configuration
    cat > "${SCRIPT_DIR}/experiment-template.json" << EOF
{
    "description": "Multi-action chaos experiment for resilience testing",
    "stopConditions": [
        {
            "source": "aws:cloudwatch:alarm",
            "value": "${ERROR_ALARM_ARN}"
        }
    ],
    "targets": {
        "ec2-instances": {
            "resourceType": "aws:ec2:instance",
            "selectionMode": "COUNT(1)",
            "resourceTags": {
                "ChaosReady": "true"
            }
        }
    },
    "actions": {
        "cpu-stress": {
            "actionId": "aws:ssm:send-command",
            "description": "Inject CPU stress on EC2 instances",
            "parameters": {
                "documentArn": "arn:aws:ssm:${AWS_REGION}::document/AWSFIS-Run-CPU-Stress",
                "documentParameters": "{\"DurationSeconds\": \"120\", \"CPU\": \"0\", \"LoadPercent\": \"80\"}",
                "duration": "PT3M"
            },
            "targets": {
                "Instances": "ec2-instances"
            }
        },
        "terminate-instance": {
            "actionId": "aws:ec2:terminate-instances",
            "description": "Terminate EC2 instance to test recovery",
            "targets": {
                "Instances": "ec2-instances"
            },
            "startAfter": ["cpu-stress"]
        }
    },
    "roleArn": "${FIS_ROLE_ARN}",
    "tags": {
        "Environment": "Testing",
        "Purpose": "ChaosEngineering",
        "DeployedBy": "chaos-engineering-recipe"
    }
}
EOF
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would create FIS experiment template"
        export TEMPLATE_ID="EXT0123456789abcdef"
        return 0
    fi
    
    # Create the experiment template
    export TEMPLATE_ID=$(aws fis create-experiment-template \
        --cli-input-json "file://${SCRIPT_DIR}/experiment-template.json" \
        --query experimentTemplate.id --output text)
    
    if [[ -z "$TEMPLATE_ID" ]]; then
        log_error "Failed to create FIS experiment template"
        return 1
    fi
    
    # Save template ID for cleanup
    echo "TEMPLATE_ID=${TEMPLATE_ID}" >> "${SCRIPT_DIR}/.env"
    
    log_success "FIS experiment template created: $TEMPLATE_ID"
}

# Create EventBridge resources
create_eventbridge_resources() {
    log_info "Creating EventBridge rules for experiment notifications..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would create EventBridge resources"
        export EB_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/EventBridgeFISRole-${RANDOM_SUFFIX}"
        return 0
    fi
    
    # Create EventBridge rule for FIS state changes
    aws events put-rule \
        --name "FIS-ExperimentStateChanges-${RANDOM_SUFFIX}" \
        --description "Capture all FIS experiment state changes" \
        --event-pattern '{
            "source": ["aws.fis"],
            "detail-type": ["FIS Experiment State Change"]
        }' \
        --state ENABLED >/dev/null
    
    # Create EventBridge trust policy
    cat > "${SCRIPT_DIR}/eventbridge-trust-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "events.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role for EventBridge
    export EB_ROLE_ARN=$(aws iam create-role \
        --role-name "EventBridgeFISRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document "file://${SCRIPT_DIR}/eventbridge-trust-policy.json" \
        --query Role.Arn --output text)
    
    # Attach SNS publish policy
    aws iam put-role-policy \
        --role-name "EventBridgeFISRole-${RANDOM_SUFFIX}" \
        --policy-name SNSPublishPolicy \
        --policy-document "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Action\": \"sns:Publish\",
                    \"Resource\": \"${SNS_TOPIC_ARN}\"
                }
            ]
        }" >/dev/null
    
    # Add SNS target to EventBridge rule
    aws events put-targets \
        --rule "FIS-ExperimentStateChanges-${RANDOM_SUFFIX}" \
        --targets "Id"="1","Arn"="${SNS_TOPIC_ARN}","RoleArn"="${EB_ROLE_ARN}" >/dev/null
    
    # Save EventBridge resources for cleanup
    echo "EB_ROLE_ARN=${EB_ROLE_ARN}" >> "${SCRIPT_DIR}/.env"
    echo "EB_ROLE_NAME=EventBridgeFISRole-${RANDOM_SUFFIX}" >> "${SCRIPT_DIR}/.env"
    echo "EB_RULE_NAME=FIS-ExperimentStateChanges-${RANDOM_SUFFIX}" >> "${SCRIPT_DIR}/.env"
    
    log_success "EventBridge rules configured successfully"
}

# Create scheduled EventBridge rule
create_scheduled_experiments() {
    log_info "Creating scheduled EventBridge rule for automated testing..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would create scheduled EventBridge rule"
        return 0
    fi
    
    # Create scheduler trust policy
    cat > "${SCRIPT_DIR}/scheduler-trust-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "scheduler.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role for EventBridge Scheduler
    export SCHEDULER_ROLE_ARN=$(aws iam create-role \
        --role-name "SchedulerFISRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document "file://${SCRIPT_DIR}/scheduler-trust-policy.json" \
        --query Role.Arn --output text)
    
    # Attach FIS start experiment policy
    aws iam put-role-policy \
        --role-name "SchedulerFISRole-${RANDOM_SUFFIX}" \
        --policy-name FISStartExperimentPolicy \
        --policy-document "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Action\": \"fis:StartExperiment\",
                    \"Resource\": [
                        \"arn:aws:fis:*:*:experiment-template/${TEMPLATE_ID}\",
                        \"arn:aws:fis:*:*:experiment/*\"
                    ]
                }
            ]
        }" >/dev/null
    
    # Create EventBridge schedule (runs daily at 2 AM)
    aws scheduler create-schedule \
        --name "FIS-DailyChaosTest-${RANDOM_SUFFIX}" \
        --schedule-expression "cron(0 2 * * ? *)" \
        --target "{
            \"Arn\": \"arn:aws:scheduler:::aws-sdk:fis:startExperiment\",
            \"RoleArn\": \"${SCHEDULER_ROLE_ARN}\",
            \"Input\": \"{\\\"experimentTemplateId\\\": \\\"${TEMPLATE_ID}\\\"}\"
        }" \
        --flexible-time-window '{"Mode": "OFF"}' >/dev/null
    
    # Save scheduler resources for cleanup
    echo "SCHEDULER_ROLE_ARN=${SCHEDULER_ROLE_ARN}" >> "${SCRIPT_DIR}/.env"
    echo "SCHEDULER_ROLE_NAME=SchedulerFISRole-${RANDOM_SUFFIX}" >> "${SCRIPT_DIR}/.env"
    echo "SCHEDULER_NAME=FIS-DailyChaosTest-${RANDOM_SUFFIX}" >> "${SCRIPT_DIR}/.env"
    
    log_success "Scheduled chaos experiments configured (daily at 2 AM)"
}

# Create CloudWatch dashboard
create_cloudwatch_dashboard() {
    log_info "Creating CloudWatch dashboard for experiment monitoring..."
    
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
                    ["AWS/FIS", "ExperimentsStarted", {"stat": "Sum"}],
                    [".", "ExperimentsStopped", {"stat": "Sum"}],
                    [".", "ExperimentsFailed", {"stat": "Sum"}]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "${AWS_REGION}",
                "title": "FIS Experiment Status",
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
                    ["AWS/EC2", "CPUUtilization", {"stat": "Average"}],
                    ["AWS/ApplicationELB", "TargetResponseTime", {"stat": "Average"}],
                    [".", "HTTPCode_Target_4XX_Count", {"stat": "Sum"}]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "${AWS_REGION}",
                "title": "Application Health During Experiments",
                "period": 60
            }
        }
    ]
}
EOF
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would create CloudWatch dashboard"
        return 0
    fi
    
    # Create the dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body "file://${SCRIPT_DIR}/dashboard-config.json" >/dev/null
    
    log_success "CloudWatch dashboard created: $DASHBOARD_NAME"
}

# Cleanup temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    rm -f "${SCRIPT_DIR}/fis-trust-policy.json"
    rm -f "${SCRIPT_DIR}/eventbridge-trust-policy.json"
    rm -f "${SCRIPT_DIR}/scheduler-trust-policy.json"
    rm -f "${SCRIPT_DIR}/experiment-template.json"
    rm -f "${SCRIPT_DIR}/dashboard-config.json"
    
    log_success "Temporary files cleaned up"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Skipping validation"
        return 0
    fi
    
    # Check if experiment template exists
    if aws fis get-experiment-template --id "$TEMPLATE_ID" >/dev/null 2>&1; then
        log_success "FIS experiment template validated"
    else
        log_error "FIS experiment template validation failed"
        return 1
    fi
    
    # Check if EventBridge rule exists
    if aws events describe-rule --name "FIS-ExperimentStateChanges-${RANDOM_SUFFIX}" >/dev/null 2>&1; then
        log_success "EventBridge rule validated"
    else
        log_error "EventBridge rule validation failed"
        return 1
    fi
    
    # Check if SNS topic exists
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" >/dev/null 2>&1; then
        log_success "SNS topic validated"
    else
        log_error "SNS topic validation failed"
        return 1
    fi
    
    log_success "Deployment validation completed successfully"
}

# Print deployment summary
print_summary() {
    log_info "Deployment Summary:"
    echo "===================="
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account ID: $AWS_ACCOUNT_ID"
    echo "Resource Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Created Resources:"
    echo "- SNS Topic: $SNS_TOPIC_ARN"
    echo "- FIS Experiment Template: $TEMPLATE_ID"
    echo "- CloudWatch Dashboard: $DASHBOARD_NAME"
    echo "- EventBridge Rules: FIS-ExperimentStateChanges-${RANDOM_SUFFIX}"
    echo "- Scheduled Experiment: FIS-DailyChaosTest-${RANDOM_SUFFIX}"
    echo ""
    echo "Next Steps:"
    echo "1. Confirm your email subscription for SNS notifications"
    echo "2. Tag your EC2 instances with 'ChaosReady=true' to include them in experiments"
    echo "3. Run a manual test: aws fis start-experiment --experiment-template-id $TEMPLATE_ID"
    echo "4. Monitor experiments via CloudWatch dashboard: $DASHBOARD_NAME"
    echo ""
    echo "To clean up all resources, run: ./destroy.sh"
    echo "===================="
}

# Main execution
main() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE: No resources will be created"
    fi
    
    validate_prerequisites
    initialize_environment
    create_sns_resources
    create_fis_iam_role
    create_cloudwatch_alarms
    create_experiment_template
    create_eventbridge_resources
    create_scheduled_experiments
    create_cloudwatch_dashboard
    cleanup_temp_files
    validate_deployment
    print_summary
    
    log_success "AWS Chaos Engineering deployment completed successfully!"
}

# Run main function
main "$@"