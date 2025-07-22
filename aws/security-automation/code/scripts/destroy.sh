#!/bin/bash

# Destroy script for Event-Driven Security Automation with EventBridge and Lambda
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if running with --help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [--dry-run] [--force] [--config-file CONFIG_FILE]"
    echo ""
    echo "Options:"
    echo "  --dry-run                Show what would be deleted without making changes"
    echo "  --force                  Skip confirmation prompts"
    echo "  --config-file FILE       Use specific configuration file (default: ~/.security-automation-deployment.env)"
    echo "  --help, -h               Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  AUTOMATION_PREFIX        Prefix for resource names (required if no config file)"
    echo "  AWS_REGION               AWS region for deployment (default: from AWS config)"
    echo ""
    echo "Note: This script will attempt to load configuration from ~/.security-automation-deployment.env"
    echo "      if it exists and no config file is specified."
    echo ""
    exit 0
fi

# Parse command line arguments
DRY_RUN=false
FORCE=false
CONFIG_FILE="$HOME/.security-automation-deployment.env"

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --config-file)
            CONFIG_FILE="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

log "Starting cleanup of Event-Driven Security Automation resources"

# Prerequisites check
info "Checking prerequisites..."

# Check if AWS CLI is installed and configured
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials are not configured. Please run 'aws configure' first."
fi

# Load configuration from file if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    info "Loading configuration from: $CONFIG_FILE"
    source "$CONFIG_FILE"
else
    warn "Configuration file not found: $CONFIG_FILE"
    info "Attempting to use environment variables..."
fi

# Set default values and validate required variables
export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}

if [[ -z "${AUTOMATION_PREFIX:-}" ]]; then
    error "AUTOMATION_PREFIX is not set. Please provide it via environment variable or configuration file."
fi

if [[ -z "$AWS_REGION" ]]; then
    error "AWS region not configured. Please set AWS_REGION environment variable or run 'aws configure'."
fi

# Set derived variables
export LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME:-"${AUTOMATION_PREFIX}-lambda-role"}
export EVENTBRIDGE_RULE_NAME=${EVENTBRIDGE_RULE_NAME:-"${AUTOMATION_PREFIX}-findings-rule"}
export SNS_TOPIC_NAME=${SNS_TOPIC_NAME:-"${AUTOMATION_PREFIX}-notifications"}
export SNS_TOPIC_ARN=${SNS_TOPIC_ARN:-"arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"}
export SQS_QUEUE_NAME=${SQS_QUEUE_NAME:-"${AUTOMATION_PREFIX}-dlq"}

log "Cleanup configuration:"
info "  AWS Region: $AWS_REGION"
info "  AWS Account ID: $AWS_ACCOUNT_ID"
info "  Resource Prefix: $AUTOMATION_PREFIX"
info "  Dry Run: $DRY_RUN"
info "  Force: $FORCE"

if [[ "$DRY_RUN" == "true" ]]; then
    warn "DRY RUN MODE - No resources will be deleted"
fi

# Confirmation prompt (unless force is used)
if [[ "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
    echo ""
    warn "This will DELETE all resources with prefix: $AUTOMATION_PREFIX"
    warn "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to proceed? (type 'yes' to continue): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        info "Cleanup cancelled by user."
        exit 0
    fi
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would execute: $description"
        info "[DRY RUN] Command: $cmd"
    else
        info "Executing: $description"
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || warn "Command failed but continuing: $description"
        else
            eval "$cmd"
        fi
    fi
}

# Function to check if resource exists
resource_exists() {
    local check_cmd="$1"
    local resource_name="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would check existence of: $resource_name"
        return 0
    fi
    
    if eval "$check_cmd" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Step 1: Remove EventBridge Rules and Targets
log "Step 1: Removing EventBridge rules and targets..."

# Remove targets first, then rules
EVENTBRIDGE_RULES=(
    "${EVENTBRIDGE_RULE_NAME}"
    "${AUTOMATION_PREFIX}-remediation-rule"
    "${AUTOMATION_PREFIX}-error-handling"
    "${AUTOMATION_PREFIX}-custom-actions"
)

for rule in "${EVENTBRIDGE_RULES[@]}"; do
    if resource_exists "aws events describe-rule --name $rule" "$rule"; then
        info "Removing targets and rule: $rule"
        
        # Get targets for the rule
        if [[ "$DRY_RUN" == "false" ]]; then
            TARGETS=$(aws events list-targets-by-rule --rule "$rule" --query 'Targets[].Id' --output text 2>/dev/null || echo "")
            if [[ -n "$TARGETS" ]]; then
                execute_command "aws events remove-targets --rule $rule --ids $TARGETS" \
                    "Remove targets from rule $rule" true
            fi
        else
            info "[DRY RUN] Would remove targets from rule: $rule"
        fi
        
        execute_command "aws events delete-rule --name $rule" \
            "Delete EventBridge rule $rule" true
    else
        info "Rule $rule does not exist, skipping..."
    fi
done

# Step 2: Remove Lambda Functions
log "Step 2: Removing Lambda functions..."

LAMBDA_FUNCTIONS=(
    "${AUTOMATION_PREFIX}-triage"
    "${AUTOMATION_PREFIX}-remediation"
    "${AUTOMATION_PREFIX}-notification"
    "${AUTOMATION_PREFIX}-error-handler"
)

for func in "${LAMBDA_FUNCTIONS[@]}"; do
    if resource_exists "aws lambda get-function --function-name $func" "$func"; then
        execute_command "aws lambda delete-function --function-name $func" \
            "Delete Lambda function $func" true
    else
        info "Lambda function $func does not exist, skipping..."
    fi
done

# Step 3: Remove SNS and SQS Resources
log "Step 3: Removing SNS and SQS resources..."

# Remove SNS topic
if resource_exists "aws sns get-topic-attributes --topic-arn $SNS_TOPIC_ARN" "SNS topic $SNS_TOPIC_NAME"; then
    execute_command "aws sns delete-topic --topic-arn $SNS_TOPIC_ARN" \
        "Delete SNS topic $SNS_TOPIC_NAME" true
else
    info "SNS topic $SNS_TOPIC_NAME does not exist, skipping..."
fi

# Remove SQS queue
if resource_exists "aws sqs get-queue-url --queue-name $SQS_QUEUE_NAME" "SQS queue $SQS_QUEUE_NAME"; then
    if [[ "$DRY_RUN" == "false" ]]; then
        DLQ_URL=$(aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" --query 'QueueUrl' --output text 2>/dev/null || echo "")
        if [[ -n "$DLQ_URL" ]]; then
            execute_command "aws sqs delete-queue --queue-url $DLQ_URL" \
                "Delete SQS queue $SQS_QUEUE_NAME" true
        fi
    else
        info "[DRY RUN] Would delete SQS queue: $SQS_QUEUE_NAME"
    fi
else
    info "SQS queue $SQS_QUEUE_NAME does not exist, skipping..."
fi

# Step 4: Remove Security Hub Resources
log "Step 4: Removing Security Hub resources..."

# Check if Security Hub is enabled
if [[ "$DRY_RUN" == "false" ]]; then
    if aws securityhub describe-hub &>/dev/null; then
        info "Security Hub is enabled, checking for automation rules and custom actions..."
        
        # Remove Security Hub automation rules
        AUTOMATION_RULE_NAMES=(
            "Auto-Process-High-Severity"
            "Auto-Process-Critical-Findings"
        )
        
        for rule_name in "${AUTOMATION_RULE_NAMES[@]}"; do
            # Get automation rule ARN
            RULE_ARN=$(aws securityhub list-automation-rules \
                --query "AutomationRulesMetadata[?RuleName=='$rule_name'].RuleArn" \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$RULE_ARN" && "$RULE_ARN" != "None" ]]; then
                execute_command "aws securityhub batch-delete-automation-rules --automation-rules-arns $RULE_ARN" \
                    "Delete Security Hub automation rule $rule_name" true
            else
                info "Security Hub automation rule $rule_name does not exist, skipping..."
            fi
        done
        
        # Remove custom actions
        CUSTOM_ACTIONS=(
            "trigger-remediation"
            "escalate-soc"
        )
        
        for action_id in "${CUSTOM_ACTIONS[@]}"; do
            ACTION_ARN="arn:aws:securityhub:${AWS_REGION}:${AWS_ACCOUNT_ID}:action/custom/$action_id"
            
            if resource_exists "aws securityhub describe-action-targets --action-target-arns $ACTION_ARN" "$action_id"; then
                execute_command "aws securityhub delete-action-target --action-target-arn $ACTION_ARN" \
                    "Delete custom Security Hub action $action_id" true
            else
                info "Custom Security Hub action $action_id does not exist, skipping..."
            fi
        done
    else
        info "Security Hub is not enabled, skipping Security Hub resource cleanup..."
    fi
else
    info "[DRY RUN] Would remove Security Hub automation rules and custom actions"
fi

# Step 5: Remove Systems Manager Documents
log "Step 5: Removing Systems Manager documents..."

SSM_DOCUMENTS=(
    "${AUTOMATION_PREFIX}-isolate-instance"
)

for doc in "${SSM_DOCUMENTS[@]}"; do
    if resource_exists "aws ssm describe-document --name $doc" "$doc"; then
        execute_command "aws ssm delete-document --name $doc" \
            "Delete Systems Manager document $doc" true
    else
        info "Systems Manager document $doc does not exist, skipping..."
    fi
done

# Step 6: Remove CloudWatch Resources
log "Step 6: Removing CloudWatch resources..."

# Remove CloudWatch alarms
CLOUDWATCH_ALARMS=(
    "${AUTOMATION_PREFIX}-lambda-errors"
    "${AUTOMATION_PREFIX}-eventbridge-failures"
)

for alarm in "${CLOUDWATCH_ALARMS[@]}"; do
    if resource_exists "aws cloudwatch describe-alarms --alarm-names $alarm" "$alarm"; then
        execute_command "aws cloudwatch delete-alarms --alarm-names $alarm" \
            "Delete CloudWatch alarm $alarm" true
    else
        info "CloudWatch alarm $alarm does not exist, skipping..."
    fi
done

# Remove CloudWatch dashboard
DASHBOARD_NAME="${AUTOMATION_PREFIX}-monitoring"
if resource_exists "aws cloudwatch get-dashboard --dashboard-name $DASHBOARD_NAME" "$DASHBOARD_NAME"; then
    execute_command "aws cloudwatch delete-dashboards --dashboard-names $DASHBOARD_NAME" \
        "Delete CloudWatch dashboard $DASHBOARD_NAME" true
else
    info "CloudWatch dashboard $DASHBOARD_NAME does not exist, skipping..."
fi

# Step 7: Remove IAM Resources
log "Step 7: Removing IAM resources..."

# Detach policies from role
if resource_exists "aws iam get-role --role-name $LAMBDA_ROLE_NAME" "$LAMBDA_ROLE_NAME"; then
    info "Detaching policies from IAM role: $LAMBDA_ROLE_NAME"
    
    # Detach managed policies
    execute_command "aws iam detach-role-policy \
        --role-name $LAMBDA_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "Detach AWSLambdaBasicExecutionRole from $LAMBDA_ROLE_NAME" true
    
    execute_command "aws iam detach-role-policy \
        --role-name $LAMBDA_ROLE_NAME \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${AUTOMATION_PREFIX}-policy" \
        "Detach custom policy from $LAMBDA_ROLE_NAME" true
    
    # Delete the role
    execute_command "aws iam delete-role --role-name $LAMBDA_ROLE_NAME" \
        "Delete IAM role $LAMBDA_ROLE_NAME" true
else
    info "IAM role $LAMBDA_ROLE_NAME does not exist, skipping..."
fi

# Delete custom policy
CUSTOM_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${AUTOMATION_PREFIX}-policy"
if resource_exists "aws iam get-policy --policy-arn $CUSTOM_POLICY_ARN" "${AUTOMATION_PREFIX}-policy"; then
    execute_command "aws iam delete-policy --policy-arn $CUSTOM_POLICY_ARN" \
        "Delete custom IAM policy ${AUTOMATION_PREFIX}-policy" true
else
    info "Custom IAM policy ${AUTOMATION_PREFIX}-policy does not exist, skipping..."
fi

# Step 8: Clean up CloudWatch Logs
log "Step 8: Cleaning up CloudWatch logs..."

# List and delete log groups for Lambda functions
if [[ "$DRY_RUN" == "false" ]]; then
    LOG_GROUPS=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/lambda/${AUTOMATION_PREFIX}" \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$LOG_GROUPS" ]]; then
        for log_group in $LOG_GROUPS; do
            execute_command "aws logs delete-log-group --log-group-name $log_group" \
                "Delete CloudWatch log group $log_group" true
        done
    else
        info "No CloudWatch log groups found for Lambda functions"
    fi
else
    info "[DRY RUN] Would delete CloudWatch log groups for Lambda functions"
fi

# Step 9: Verify cleanup
log "Step 9: Verifying cleanup..."

if [[ "$DRY_RUN" == "false" ]]; then
    info "Verification Summary:"
    echo "====================="
    
    # Check Lambda functions
    REMAINING_FUNCTIONS=$(aws lambda list-functions \
        --query "Functions[?starts_with(FunctionName, '$AUTOMATION_PREFIX')].FunctionName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$REMAINING_FUNCTIONS" ]]; then
        warn "Remaining Lambda functions: $REMAINING_FUNCTIONS"
    else
        info "✅ All Lambda functions removed"
    fi
    
    # Check EventBridge rules
    REMAINING_RULES=$(aws events list-rules \
        --name-prefix "$AUTOMATION_PREFIX" \
        --query 'Rules[].Name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$REMAINING_RULES" ]]; then
        warn "Remaining EventBridge rules: $REMAINING_RULES"
    else
        info "✅ All EventBridge rules removed"
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
        warn "IAM role still exists: $LAMBDA_ROLE_NAME"
    else
        info "✅ IAM role removed"
    fi
    
    # Check SNS topic
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
        warn "SNS topic still exists: $SNS_TOPIC_NAME"
    else
        info "✅ SNS topic removed"
    fi
    
    # Check CloudWatch alarms
    REMAINING_ALARMS=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "$AUTOMATION_PREFIX" \
        --query 'MetricAlarms[].AlarmName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$REMAINING_ALARMS" ]]; then
        warn "Remaining CloudWatch alarms: $REMAINING_ALARMS"
    else
        info "✅ All CloudWatch alarms removed"
    fi
    
else
    info "[DRY RUN] Verification skipped in dry run mode"
fi

# Step 10: Clean up configuration file
log "Step 10: Cleaning up configuration file..."

if [[ -f "$CONFIG_FILE" && "$DRY_RUN" == "false" ]]; then
    if [[ "$FORCE" == "true" ]]; then
        rm -f "$CONFIG_FILE"
        info "✅ Configuration file removed: $CONFIG_FILE"
    else
        read -p "Remove configuration file $CONFIG_FILE? (y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -f "$CONFIG_FILE"
            info "✅ Configuration file removed: $CONFIG_FILE"
        else
            info "Configuration file preserved: $CONFIG_FILE"
        fi
    fi
elif [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would ask about removing configuration file: $CONFIG_FILE"
fi

# Final summary
log "Cleanup completed!"

if [[ "$DRY_RUN" == "false" ]]; then
    info "Summary:"
    info "========"
    info "✅ EventBridge rules and targets removed"
    info "✅ Lambda functions removed"
    info "✅ SNS topic and SQS queue removed"
    info "✅ Security Hub automation rules and custom actions removed"
    info "✅ Systems Manager documents removed"
    info "✅ CloudWatch alarms and dashboards removed"
    info "✅ IAM roles and policies removed"
    info "✅ CloudWatch log groups removed"
    
    warn "Note: Some resources may take a few minutes to fully disappear from the AWS console."
    warn "CloudWatch logs are retained according to AWS retention policies."
    
    info "All resources with prefix '$AUTOMATION_PREFIX' have been removed."
    info "Your AWS bill should no longer include charges for these resources."
    
else
    info "This was a dry run. No resources were actually deleted."
    info "Run the script without --dry-run to perform the actual cleanup."
fi

log "Cleanup script completed successfully!"