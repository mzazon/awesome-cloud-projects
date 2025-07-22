#!/bin/bash

# AWS Resource Groups Automated Resource Management - Deploy Script
# This script deploys a complete resource group management solution with monitoring and automation

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="./deploy-$(date +%Y%m%d-%H%M%S).log"
readonly DRY_RUN=${DRY_RUN:-false}

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"
}

# Usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Deploy AWS Resource Groups automated resource management solution.

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Perform a dry run without creating resources
    -r, --region        AWS region (default: from AWS CLI config)
    -e, --email         Email address for notifications (required)
    -p, --prefix        Resource name prefix (default: auto-generated)
    --skip-confirm      Skip confirmation prompts

EXAMPLES:
    $SCRIPT_NAME --email admin@company.com
    $SCRIPT_NAME --email admin@company.com --region us-east-1 --prefix mycompany
    $SCRIPT_NAME --dry-run --email admin@company.com

ENVIRONMENT VARIABLES:
    DRY_RUN            Set to 'true' for dry run mode
    AWS_REGION         Override AWS region
    EMAIL_ADDRESS      Email for notifications
    RESOURCE_PREFIX    Prefix for resource names

EOF
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: $aws_version"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid. Run 'aws configure' first."
    fi
    
    # Get account info
    local account_id
    local user_arn
    account_id=$(aws sts get-caller-identity --query Account --output text)
    user_arn=$(aws sts get-caller-identity --query Arn --output text)
    
    info "AWS Account ID: $account_id"
    info "User ARN: $user_arn"
    
    # Check required permissions (basic check)
    log "Checking basic IAM permissions..."
    local required_services=("resource-groups" "sns" "cloudwatch" "iam" "ssm" "events" "budgets" "ce")
    
    for service in "${required_services[@]}"; do
        case $service in
            "resource-groups")
                if ! aws resource-groups list-groups --max-items 1 &> /dev/null; then
                    warn "May not have sufficient Resource Groups permissions"
                fi
                ;;
            "sns")
                if ! aws sns list-topics --max-items 1 &> /dev/null; then
                    warn "May not have sufficient SNS permissions"
                fi
                ;;
            "cloudwatch")
                if ! aws cloudwatch list-dashboards --max-items 1 &> /dev/null; then
                    warn "May not have sufficient CloudWatch permissions"
                fi
                ;;
        esac
    done
    
    log "Prerequisites check completed"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -e|--email)
                EMAIL_ADDRESS="$2"
                shift 2
                ;;
            -p|--prefix)
                RESOURCE_PREFIX="$2"
                shift 2
                ;;
            --skip-confirm)
                SKIP_CONFIRM=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# Set environment variables
set_environment() {
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Use --region option or configure AWS CLI."
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix
    local timestamp=$(date +%s)
    local random=$(openssl rand -hex 3 2>/dev/null || echo "$(shuf -i 100-999 -n1)")
    readonly UNIQUE_SUFFIX="${timestamp:(-6)}${random}"
    
    # Set resource names with prefix
    local prefix=${RESOURCE_PREFIX:-"rg-mgmt"}
    export RESOURCE_GROUP_NAME="${prefix}-${UNIQUE_SUFFIX}"
    export SNS_TOPIC_NAME="${prefix}-alerts-${UNIQUE_SUFFIX}"
    export CLOUDWATCH_DASHBOARD_NAME="${prefix}-dashboard-${UNIQUE_SUFFIX}"
    export IAM_ROLE_NAME="ResourceGroupAutomationRole-${UNIQUE_SUFFIX}"
    export BUDGET_NAME="ResourceGroup-Budget-${UNIQUE_SUFFIX}"
    export DETECTOR_NAME="ResourceGroupAnomalyDetector-${UNIQUE_SUFFIX}"
    
    log "Environment configured:"
    info "  AWS Region: $AWS_REGION"
    info "  AWS Account: $AWS_ACCOUNT_ID"
    info "  Resource Group: $RESOURCE_GROUP_NAME"
    info "  SNS Topic: $SNS_TOPIC_NAME"
    info "  Dashboard: $CLOUDWATCH_DASHBOARD_NAME"
}

# Validate email address
validate_email() {
    if [[ -z "${EMAIL_ADDRESS:-}" ]]; then
        error "Email address is required. Use --email option or set EMAIL_ADDRESS environment variable."
    fi
    
    # Basic email validation
    if [[ ! "$EMAIL_ADDRESS" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        error "Invalid email address format: $EMAIL_ADDRESS"
    fi
    
    info "Email address: $EMAIL_ADDRESS"
}

# Confirmation prompt
confirm_deployment() {
    if [[ "${SKIP_CONFIRM:-false}" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    warn "This will create the following AWS resources:"
    echo "  • Resource Group: $RESOURCE_GROUP_NAME"
    echo "  • SNS Topic: $SNS_TOPIC_NAME"
    echo "  • CloudWatch Dashboard: $CLOUDWATCH_DASHBOARD_NAME"
    echo "  • IAM Role: $IAM_ROLE_NAME"
    echo "  • AWS Budget: $BUDGET_NAME"
    echo "  • Cost Anomaly Detector: $DETECTOR_NAME"
    echo "  • CloudWatch Alarms and Automation Documents"
    echo
    warn "Estimated monthly cost: \$15-25 for monitoring and notifications"
    echo
    
    read -p "Do you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
}

# Execute command with dry run support
execute() {
    local description="$1"
    shift
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] $description"
        info "[DRY RUN] Command: $*"
        return 0
    fi
    
    info "$description"
    if ! "$@"; then
        error "Failed to execute: $*"
    fi
}

# Create SNS topic and subscription
create_sns_resources() {
    log "Creating SNS notification system..."
    
    # Create SNS topic
    execute "Creating SNS topic" \
        aws sns create-topic \
            --name "$SNS_TOPIC_NAME" \
            --region "$AWS_REGION" \
            --tags Key=Purpose,Value=resource-management Key=CreatedBy,Value=deploy-script
    
    # Get SNS topic ARN
    export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    
    # Subscribe email to topic
    execute "Subscribing email to SNS topic" \
        aws sns subscribe \
            --topic-arn "$SNS_TOPIC_ARN" \
            --protocol email \
            --notification-endpoint "$EMAIL_ADDRESS"
    
    # Test notification
    execute "Sending test notification" \
        aws sns publish \
            --topic-arn "$SNS_TOPIC_ARN" \
            --message "AWS Resource Management System deployment started" \
            --subject "Resource Group Management - Deployment Started"
    
    log "✅ SNS resources created successfully"
}

# Create IAM role for automation
create_iam_role() {
    log "Creating IAM role for Systems Manager automation..."
    
    # Create trust policy document
    local trust_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": [
                    "ssm.amazonaws.com",
                    "events.amazonaws.com"
                ]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)
    
    # Create IAM role
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "$trust_policy" > /tmp/trust-policy.json
    fi
    
    execute "Creating IAM role" \
        aws iam create-role \
            --role-name "$IAM_ROLE_NAME" \
            --assume-role-policy-document "file:///tmp/trust-policy.json" \
            --tags Key=Purpose,Value=resource-management Key=CreatedBy,Value=deploy-script
    
    # Attach necessary policies
    execute "Attaching SSM automation policy" \
        aws iam attach-role-policy \
            --role-name "$IAM_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonSSMAutomationRole"
    
    execute "Attaching resource groups tagging policy" \
        aws iam attach-role-policy \
            --role-name "$IAM_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/ResourceGroupsandTagEditorFullAccess"
    
    # Wait for role to be ready
    if [[ "$DRY_RUN" != "true" ]]; then
        info "Waiting for IAM role to be ready..."
        sleep 10
    fi
    
    # Clean up temp file
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -f /tmp/trust-policy.json
    fi
    
    log "✅ IAM role created successfully"
}

# Create resource group
create_resource_group() {
    log "Creating tag-based resource group..."
    
    # Create resource group with tag-based query
    local resource_query=$(cat << EOF
{
    "Type": "TAG_FILTERS_1_0",
    "Query": "{\"ResourceTypeFilters\":[\"AWS::AllSupported\"],\"TagFilters\":[{\"Key\":\"Environment\",\"Values\":[\"production\"]},{\"Key\":\"Application\",\"Values\":[\"web-app\"]}]}"
}
EOF
)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "$resource_query" > /tmp/resource-query.json
    fi
    
    execute "Creating resource group" \
        aws resource-groups create-group \
            --name "$RESOURCE_GROUP_NAME" \
            --description "Automated resource management for production web application" \
            --resource-query "file:///tmp/resource-query.json" \
            --tags Environment=production,Application=web-app,Purpose=resource-management,CreatedBy=deploy-script
    
    # Clean up temp file
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -f /tmp/resource-query.json
    fi
    
    log "✅ Resource group created successfully"
}

# Create Systems Manager automation documents
create_ssm_documents() {
    log "Creating Systems Manager automation documents..."
    
    # Create resource group maintenance document
    local maintenance_doc=$(cat << 'EOF'
{
    "schemaVersion": "0.3",
    "description": "Automated maintenance for resource group",
    "assumeRole": "{{ AutomationAssumeRole }}",
    "parameters": {
        "ResourceGroupName": {
            "type": "String",
            "description": "Name of the resource group to process"
        },
        "AutomationAssumeRole": {
            "type": "String",
            "description": "IAM role for automation execution"
        }
    },
    "mainSteps": [
        {
            "name": "GetResourceGroupResources",
            "action": "aws:executeAwsApi",
            "inputs": {
                "Service": "resource-groups",
                "Api": "ListGroupResources",
                "GroupName": "{{ ResourceGroupName }}"
            },
            "outputs": [
                {
                    "Name": "ResourceCount",
                    "Selector": "$.length(ResourceIdentifiers)",
                    "Type": "Integer"
                }
            ]
        },
        {
            "name": "LogResourceCount",
            "action": "aws:executeAwsApi",
            "inputs": {
                "Service": "logs",
                "Api": "CreateLogGroup",
                "logGroupName": "/aws/ssm/resource-group-maintenance"
            },
            "onFailure": "Continue"
        }
    ]
}
EOF
)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "$maintenance_doc" > /tmp/maintenance-doc.json
    fi
    
    execute "Creating resource group maintenance document" \
        aws ssm create-document \
            --name "ResourceGroupMaintenance-${UNIQUE_SUFFIX}" \
            --document-type "Automation" \
            --document-format "JSON" \
            --content "file:///tmp/maintenance-doc.json" \
            --tags Key=Purpose,Value=resource-management Key=CreatedBy,Value=deploy-script
    
    # Create automated tagging document
    local tagging_doc=$(cat << 'EOF'
{
    "schemaVersion": "0.3",
    "description": "Automated resource tagging for resource groups",
    "assumeRole": "{{ AutomationAssumeRole }}",
    "parameters": {
        "ResourceArn": {
            "type": "String",
            "description": "ARN of the resource to tag"
        },
        "TagKey": {
            "type": "String",
            "description": "Tag key to apply"
        },
        "TagValue": {
            "type": "String",
            "description": "Tag value to apply"
        },
        "AutomationAssumeRole": {
            "type": "String",
            "description": "IAM role for automation execution"
        }
    },
    "mainSteps": [
        {
            "name": "TagResource",
            "action": "aws:executeAwsApi",
            "inputs": {
                "Service": "resourcegroupstaggingapi",
                "Api": "TagResources",
                "ResourceARNList": ["{{ ResourceArn }}"],
                "Tags": {
                    "{{ TagKey }}": "{{ TagValue }}"
                }
            }
        }
    ]
}
EOF
)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "$tagging_doc" > /tmp/tagging-doc.json
    fi
    
    execute "Creating automated tagging document" \
        aws ssm create-document \
            --name "AutomatedResourceTagging-${UNIQUE_SUFFIX}" \
            --document-type "Automation" \
            --document-format "JSON" \
            --content "file:///tmp/tagging-doc.json" \
            --tags Key=Purpose,Value=resource-management Key=CreatedBy,Value=deploy-script
    
    # Clean up temp files
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -f /tmp/maintenance-doc.json /tmp/tagging-doc.json
    fi
    
    log "✅ Systems Manager documents created successfully"
}

# Create CloudWatch resources
create_cloudwatch_resources() {
    log "Creating CloudWatch monitoring resources..."
    
    # Create CloudWatch dashboard
    local dashboard_body=$(cat << EOF
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
                    [ "AWS/EC2", "CPUUtilization", { "stat": "Average" } ],
                    [ "AWS/RDS", "CPUUtilization", { "stat": "Average" } ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Resource Group CPU Utilization"
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
                    [ "AWS/Billing", "EstimatedCharges", "Currency", "USD" ]
                ],
                "period": 86400,
                "stat": "Maximum",
                "region": "us-east-1",
                "title": "Estimated Monthly Charges"
            }
        }
    ]
}
EOF
)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "$dashboard_body" > /tmp/dashboard.json
    fi
    
    execute "Creating CloudWatch dashboard" \
        aws cloudwatch put-dashboard \
            --dashboard-name "$CLOUDWATCH_DASHBOARD_NAME" \
            --dashboard-body "file:///tmp/dashboard.json"
    
    # Create CloudWatch alarms
    execute "Creating high CPU alarm" \
        aws cloudwatch put-metric-alarm \
            --alarm-name "ResourceGroup-HighCPU-${UNIQUE_SUFFIX}" \
            --alarm-description "High CPU usage across resource group" \
            --metric-name CPUUtilization \
            --namespace AWS/EC2 \
            --statistic Average \
            --period 300 \
            --threshold 80 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --alarm-actions "$SNS_TOPIC_ARN" \
            --tags Key=Environment,Value=production Key=Application,Value=web-app Key=CreatedBy,Value=deploy-script
    
    execute "Creating health check alarm" \
        aws cloudwatch put-metric-alarm \
            --alarm-name "ResourceGroup-HealthCheck-${UNIQUE_SUFFIX}" \
            --alarm-description "Overall health monitoring for resource group" \
            --metric-name StatusCheckFailed \
            --namespace AWS/EC2 \
            --statistic Maximum \
            --period 300 \
            --threshold 0 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 1 \
            --alarm-actions "$SNS_TOPIC_ARN" \
            --treat-missing-data notBreaching \
            --tags Key=Environment,Value=production Key=Application,Value=web-app Key=CreatedBy,Value=deploy-script
    
    # Clean up temp file
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -f /tmp/dashboard.json
    fi
    
    log "✅ CloudWatch resources created successfully"
}

# Create EventBridge rule for automated tagging
create_eventbridge_rule() {
    log "Creating EventBridge rule for automated tagging..."
    
    # Create EventBridge rule
    local event_pattern=$(cat << EOF
{
    "source": ["aws.ec2", "aws.s3", "aws.rds"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {
        "eventSource": ["ec2.amazonaws.com", "s3.amazonaws.com", "rds.amazonaws.com"],
        "eventName": ["RunInstances", "CreateBucket", "CreateDBInstance"]
    }
}
EOF
)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "$event_pattern" > /tmp/event-pattern.json
    fi
    
    execute "Creating EventBridge rule" \
        aws events put-rule \
            --name "AutoTagNewResources-${UNIQUE_SUFFIX}" \
            --event-pattern "file:///tmp/event-pattern.json" \
            --state ENABLED \
            --description "Automatically tag new resources for resource group inclusion"
    
    # Clean up temp file
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -f /tmp/event-pattern.json
    fi
    
    log "✅ EventBridge rule created successfully"
}

# Create budget and cost monitoring
create_budget_monitoring() {
    log "Creating budget and cost monitoring..."
    
    # Create budget
    local budget_config=$(cat << EOF
{
    "BudgetName": "$BUDGET_NAME",
    "BudgetLimit": {
        "Amount": "100",
        "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST",
    "CostFilters": {
        "TagKey": ["Environment", "Application"],
        "TagValue": ["production", "web-app"]
    }
}
EOF
)
    
    local notifications_config=$(cat << EOF
[
    {
        "Notification": {
            "NotificationType": "ACTUAL",
            "ComparisonOperator": "GREATER_THAN",
            "Threshold": 80,
            "ThresholdType": "PERCENTAGE"
        },
        "Subscribers": [
            {
                "SubscriptionType": "SNS",
                "Address": "$SNS_TOPIC_ARN"
            }
        ]
    }
]
EOF
)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "$budget_config" > /tmp/budget.json
        echo "$notifications_config" > /tmp/notifications.json
    fi
    
    execute "Creating budget for resource group" \
        aws budgets create-budget \
            --account-id "$AWS_ACCOUNT_ID" \
            --budget "file:///tmp/budget.json" \
            --notifications-with-subscribers "file:///tmp/notifications.json"
    
    # Create cost anomaly detector
    local detector_config=$(cat << EOF
{
    "DetectorName": "$DETECTOR_NAME",
    "MonitorType": "DIMENSIONAL",
    "DimensionKey": "SERVICE",
    "MatchOptions": ["EQUALS"],
    "MonitorSpecification": "{\"TagKey\":\"Environment\",\"TagValues\":[\"production\"]}"
}
EOF
)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "$detector_config" > /tmp/detector.json
    fi
    
    execute "Creating cost anomaly detector" \
        aws ce create-anomaly-detector \
            --anomaly-detector "file:///tmp/detector.json"
    
    # Clean up temp files
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -f /tmp/budget.json /tmp/notifications.json /tmp/detector.json
    fi
    
    log "✅ Budget and cost monitoring created successfully"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Skipping validation in dry-run mode"
        return 0
    fi
    
    # Check resource group
    if aws resource-groups get-group --group-name "$RESOURCE_GROUP_NAME" &> /dev/null; then
        log "✅ Resource group validation passed"
    else
        error "Resource group validation failed"
    fi
    
    # Check SNS topic
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &> /dev/null; then
        log "✅ SNS topic validation passed"
    else
        error "SNS topic validation failed"
    fi
    
    # Check CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name "$CLOUDWATCH_DASHBOARD_NAME" &> /dev/null; then
        log "✅ CloudWatch dashboard validation passed"
    else
        error "CloudWatch dashboard validation failed"
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        log "✅ IAM role validation passed"
    else
        error "IAM role validation failed"
    fi
    
    log "✅ All validations passed"
}

# Send completion notification
send_completion_notification() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Dry-run completed successfully"
        return 0
    fi
    
    local message=$(cat << EOF
AWS Resource Groups automated resource management solution has been successfully deployed!

Resources created:
• Resource Group: $RESOURCE_GROUP_NAME
• SNS Topic: $SNS_TOPIC_NAME  
• CloudWatch Dashboard: $CLOUDWATCH_DASHBOARD_NAME
• IAM Role: $IAM_ROLE_NAME
• Budget: $BUDGET_NAME
• Cost Anomaly Detector: $DETECTOR_NAME
• CloudWatch Alarms and Systems Manager documents

Next steps:
1. Check your email and confirm the SNS subscription
2. Review the CloudWatch dashboard at: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${CLOUDWATCH_DASHBOARD_NAME}
3. Tag your existing resources with Environment=production and Application=web-app to include them in the resource group
4. Test the automation by running the Systems Manager document

For cleanup, run the destroy.sh script.
EOF
)
    
    execute "Sending completion notification" \
        aws sns publish \
            --topic-arn "$SNS_TOPIC_ARN" \
            --message "$message" \
            --subject "AWS Resource Management System - Deployment Complete"
    
    log "✅ Deployment completed successfully!"
    echo
    echo "📋 DEPLOYMENT SUMMARY"
    echo "===================="
    echo "Resource Group: $RESOURCE_GROUP_NAME"
    echo "SNS Topic: $SNS_TOPIC_NAME"
    echo "Dashboard: $CLOUDWATCH_DASHBOARD_NAME"
    echo "Region: $AWS_REGION"
    echo "Log file: $LOG_FILE"
    echo
    echo "🔗 CloudWatch Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${CLOUDWATCH_DASHBOARD_NAME}"
    echo
    warn "Don't forget to confirm your SNS subscription via email!"
}

# Error handling
trap 'error "Script failed at line $LINENO"' ERR

# Main execution
main() {
    log "Starting AWS Resource Groups automated resource management deployment"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Set environment
    set_environment
    
    # Validate email
    validate_email
    
    # Confirm deployment
    confirm_deployment
    
    # Execute deployment steps
    create_sns_resources
    create_iam_role
    create_resource_group
    create_ssm_documents
    create_cloudwatch_resources
    create_eventbridge_rule
    create_budget_monitoring
    
    # Validate deployment
    validate_deployment
    
    # Send completion notification
    send_completion_notification
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi