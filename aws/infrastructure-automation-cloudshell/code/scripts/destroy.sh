#!/bin/bash

# Infrastructure Management with CloudShell PowerShell - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    log "Prerequisites check passed. Account ID: ${account_id}"
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [ -f "deployment-info.json" ]; then
        info "Found deployment-info.json, loading resource information..."
        
        export AWS_REGION=$(jq -r '.awsRegion' deployment-info.json)
        export AWS_ACCOUNT_ID=$(jq -r '.awsAccountId' deployment-info.json)
        export RANDOM_SUFFIX=$(jq -r '.randomSuffix' deployment-info.json)
        
        export ROLE_NAME=$(jq -r '.resources.iamRole.name' deployment-info.json)
        export DOCUMENT_NAME=$(jq -r '.resources.automationDocument.name' deployment-info.json)
        export LAMBDA_FUNCTION_NAME=$(jq -r '.resources.lambdaFunction.name' deployment-info.json)
        export SCHEDULE_RULE_NAME=$(jq -r '.resources.eventBridgeRule.name' deployment-info.json)
        export DASHBOARD_NAME=$(jq -r '.resources.cloudWatchDashboard.name' deployment-info.json)
        export ALARM_NAME=$(jq -r '.resources.cloudWatchAlarm.name' deployment-info.json)
        export SNS_TOPIC_ARN=$(jq -r '.resources.snsTopicArn' deployment-info.json)
        export LOG_GROUP_NAME=$(jq -r '.resources.logGroupName' deployment-info.json)
        
        # Extract SNS topic name from ARN
        export SNS_TOPIC_NAME=$(echo "$SNS_TOPIC_ARN" | cut -d':' -f6)
        
        log "Loaded deployment info for suffix: ${RANDOM_SUFFIX}"
    else
        warn "deployment-info.json not found. You'll need to provide resource names manually."
        prompt_for_resource_names
    fi
}

# Prompt for resource names if deployment info not found
prompt_for_resource_names() {
    echo
    warn "Deployment info file not found. Please provide the resource suffix used during deployment."
    read -p "Enter the random suffix (e.g., a1b2c3): " input_suffix
    
    if [ -z "$input_suffix" ]; then
        error "No suffix provided. Cannot proceed with cleanup."
        exit 1
    fi
    
    export RANDOM_SUFFIX="$input_suffix"
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Construct resource names
    export ROLE_NAME="InfraAutomationRole-${RANDOM_SUFFIX}"
    export DOCUMENT_NAME="InfrastructureHealthCheck-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="InfrastructureAutomation-${RANDOM_SUFFIX}"
    export SCHEDULE_RULE_NAME="InfrastructureHealthSchedule-${RANDOM_SUFFIX}"
    export DASHBOARD_NAME="InfrastructureAutomation-${RANDOM_SUFFIX}"
    export ALARM_NAME="InfrastructureAutomationErrors-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="automation-alerts-${RANDOM_SUFFIX}"
    export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    export LOG_GROUP_NAME="/aws/automation/infrastructure-health"
    
    info "Using suffix: ${RANDOM_SUFFIX} in region: ${AWS_REGION}"
}

# Confirmation prompt
confirm_destruction() {
    echo
    warn "This will DELETE the following resources:"
    echo "  • IAM Role: $ROLE_NAME"
    echo "  • Automation Document: $DOCUMENT_NAME"
    echo "  • Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "  • EventBridge Rule: $SCHEDULE_RULE_NAME"
    echo "  • CloudWatch Dashboard: $DASHBOARD_NAME"
    echo "  • CloudWatch Alarm: $ALARM_NAME"
    echo "  • SNS Topic: $SNS_TOPIC_NAME"
    echo "  • CloudWatch Log Group: $LOG_GROUP_NAME (optional)"
    echo
    
    if [ "${FORCE_DELETE:-false}" != "true" ]; then
        read -p "Are you sure you want to delete all these resources? (yes/no): " confirmation
        if [ "$confirmation" != "yes" ]; then
            info "Cleanup cancelled by user."
            exit 0
        fi
    else
        warn "Force delete mode enabled - skipping confirmation"
    fi
    
    log "Proceeding with resource cleanup..."
}

# Remove EventBridge scheduled rule
remove_eventbridge_rule() {
    log "Removing EventBridge scheduled rule..."
    
    if aws events describe-rule --name "$SCHEDULE_RULE_NAME" &> /dev/null 2>&1; then
        # Remove targets first
        info "Removing targets from EventBridge rule..."
        aws events remove-targets \
            --rule "$SCHEDULE_RULE_NAME" \
            --ids "1" || warn "Failed to remove targets (they may not exist)"
        
        # Delete the rule
        aws events delete-rule \
            --name "$SCHEDULE_RULE_NAME"
        
        log "✅ EventBridge rule deleted: $SCHEDULE_RULE_NAME"
    else
        info "EventBridge rule $SCHEDULE_RULE_NAME not found, skipping"
    fi
}

# Remove Lambda function
remove_lambda_function() {
    log "Removing Lambda function..."
    
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null 2>&1; then
        # Remove Lambda permissions first
        info "Removing Lambda permissions..."
        aws lambda remove-permission \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --statement-id "EventBridgeInvoke-${RANDOM_SUFFIX}" \
            2>/dev/null || warn "Permission removal failed (may not exist)"
        
        # Delete Lambda function
        aws lambda delete-function \
            --function-name "$LAMBDA_FUNCTION_NAME"
        
        log "✅ Lambda function deleted: $LAMBDA_FUNCTION_NAME"
    else
        info "Lambda function $LAMBDA_FUNCTION_NAME not found, skipping"
    fi
}

# Remove Systems Manager automation document
remove_automation_document() {
    log "Removing Systems Manager automation document..."
    
    if aws ssm describe-document --name "$DOCUMENT_NAME" &> /dev/null 2>&1; then
        # Check for running executions
        info "Checking for running automation executions..."
        local running_executions
        running_executions=$(aws ssm describe-automation-executions \
            --filters "Key=DocumentNamePrefix,Values=${DOCUMENT_NAME}" \
            --filters "Key=AutomationExecutionStatus,Values=InProgress" \
            --query "length(AutomationExecutions)" --output text 2>/dev/null || echo "0")
        
        if [ "$running_executions" -gt 0 ]; then
            warn "Found $running_executions running automation executions. Waiting for completion..."
            info "You can cancel them manually if needed using: aws ssm stop-automation-execution --automation-execution-id <id>"
            sleep 10
        fi
        
        # Delete automation document
        aws ssm delete-document \
            --name "$DOCUMENT_NAME"
        
        log "✅ Automation document deleted: $DOCUMENT_NAME"
    else
        info "Automation document $DOCUMENT_NAME not found, skipping"
    fi
}

# Remove CloudWatch resources
remove_cloudwatch_resources() {
    log "Removing CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" &> /dev/null 2>&1; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "$DASHBOARD_NAME"
        log "✅ CloudWatch dashboard deleted: $DASHBOARD_NAME"
    else
        info "CloudWatch dashboard $DASHBOARD_NAME not found, skipping"
    fi
    
    # Delete CloudWatch alarm
    if aws cloudwatch describe-alarms --alarm-names "$ALARM_NAME" --query 'MetricAlarms[0]' --output text &> /dev/null 2>&1; then
        aws cloudwatch delete-alarms \
            --alarm-names "$ALARM_NAME"
        log "✅ CloudWatch alarm deleted: $ALARM_NAME"
    else
        info "CloudWatch alarm $ALARM_NAME not found, skipping"
    fi
}

# Remove SNS topic
remove_sns_topic() {
    log "Removing SNS topic..."
    
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &> /dev/null 2>&1; then
        # List subscriptions
        local subscriptions
        subscriptions=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$SNS_TOPIC_ARN" \
            --query "Subscriptions[].SubscriptionArn" --output text 2>/dev/null || echo "")
        
        # Delete subscriptions
        if [ -n "$subscriptions" ] && [ "$subscriptions" != "None" ]; then
            info "Removing SNS subscriptions..."
            for subscription_arn in $subscriptions; do
                if [ "$subscription_arn" != "PendingConfirmation" ]; then
                    aws sns unsubscribe --subscription-arn "$subscription_arn" || \
                        warn "Failed to unsubscribe: $subscription_arn"
                fi
            done
        fi
        
        # Delete topic
        aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN"
        log "✅ SNS topic deleted: $SNS_TOPIC_NAME"
    else
        info "SNS topic $SNS_TOPIC_ARN not found, skipping"
    fi
}

# Remove CloudWatch log group (optional)
remove_log_group() {
    if [ "${DELETE_LOGS:-false}" = "true" ]; then
        log "Removing CloudWatch log group..."
        
        if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query "logGroups[?logGroupName=='$LOG_GROUP_NAME']" --output text | grep -q "$LOG_GROUP_NAME"; then
            aws logs delete-log-group \
                --log-group-name "$LOG_GROUP_NAME"
            log "✅ CloudWatch log group deleted: $LOG_GROUP_NAME"
        else
            info "CloudWatch log group $LOG_GROUP_NAME not found, skipping"
        fi
    else
        info "Skipping log group deletion (contains valuable historical data)"
        info "To delete manually: aws logs delete-log-group --log-group-name $LOG_GROUP_NAME"
    fi
}

# Remove IAM role and policies
remove_iam_role() {
    log "Removing IAM role and attached policies..."
    
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null 2>&1; then
        # List and detach all attached policies
        info "Detaching policies from IAM role..."
        local attached_policies
        attached_policies=$(aws iam list-attached-role-policies \
            --role-name "$ROLE_NAME" \
            --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || echo "")
        
        if [ -n "$attached_policies" ]; then
            for policy_arn in $attached_policies; do
                aws iam detach-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-arn "$policy_arn"
                info "Detached policy: $policy_arn"
            done
        fi
        
        # List and delete inline policies
        local inline_policies
        inline_policies=$(aws iam list-role-policies \
            --role-name "$ROLE_NAME" \
            --query "PolicyNames" --output text 2>/dev/null || echo "")
        
        if [ -n "$inline_policies" ] && [ "$inline_policies" != "None" ]; then
            for policy_name in $inline_policies; do
                aws iam delete-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-name "$policy_name"
                info "Deleted inline policy: $policy_name"
            done
        fi
        
        # Delete the role
        aws iam delete-role \
            --role-name "$ROLE_NAME"
        
        log "✅ IAM role deleted: $ROLE_NAME"
    else
        info "IAM role $ROLE_NAME not found, skipping"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-info.json"
        "/tmp/assume-role-policy.json"
        "/tmp/automation-document.json"
        "/tmp/infrastructure-health-check.ps1"
        "/tmp/lambda-automation.py"
        "/tmp/lambda-automation.zip"
        "/tmp/dashboard-config.json"
        "/tmp/lambda-response.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            info "Removed file: $file"
        fi
    done
    
    log "✅ Local cleanup completed"
}

# Verify resource deletion
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local errors=0
    
    # Check each resource type
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null 2>&1; then
        error "IAM role $ROLE_NAME still exists"
        ((errors++))
    fi
    
    if aws ssm describe-document --name "$DOCUMENT_NAME" &> /dev/null 2>&1; then
        error "Automation document $DOCUMENT_NAME still exists"
        ((errors++))
    fi
    
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null 2>&1; then
        error "Lambda function $LAMBDA_FUNCTION_NAME still exists"
        ((errors++))
    fi
    
    if aws events describe-rule --name "$SCHEDULE_RULE_NAME" &> /dev/null 2>&1; then
        error "EventBridge rule $SCHEDULE_RULE_NAME still exists"
        ((errors++))
    fi
    
    if aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" &> /dev/null 2>&1; then
        error "CloudWatch dashboard $DASHBOARD_NAME still exists"
        ((errors++))
    fi
    
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &> /dev/null 2>&1; then
        error "SNS topic $SNS_TOPIC_NAME still exists"
        ((errors++))
    fi
    
    if [ $errors -eq 0 ]; then
        log "✅ All resources successfully removed"
    else
        error "Found $errors resources that failed to delete"
        return 1
    fi
}

# Main cleanup function
main() {
    log "Starting Infrastructure Management with CloudShell PowerShell cleanup..."
    
    # Check for dry run mode
    if [ "${DRY_RUN:-false}" = "true" ]; then
        info "Running in dry-run mode - no resources will be deleted"
        return 0
    fi
    
    check_prerequisites
    load_deployment_info
    confirm_destruction
    
    # Remove resources in reverse order of creation
    remove_eventbridge_rule
    remove_lambda_function
    remove_automation_document
    remove_cloudwatch_resources
    remove_sns_topic
    remove_log_group
    remove_iam_role
    cleanup_local_files
    
    # Verify cleanup
    if verify_cleanup; then
        log "🎉 Cleanup completed successfully!"
        echo
        info "All infrastructure resources have been removed."
        info "If you enabled log deletion, historical data has also been removed."
        echo
    else
        error "Cleanup completed with errors. Please check the output above."
        echo
        info "You may need to manually remove any remaining resources."
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Infrastructure Management with CloudShell PowerShell - Cleanup Script"
        echo
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --force             Skip confirmation prompts"
        echo "  --delete-logs       Delete CloudWatch log group (contains historical data)"
        echo "  --dry-run           Show what would be deleted without actually deleting"
        echo
        echo "Environment Variables:"
        echo "  FORCE_DELETE=true   Skip confirmation prompts"
        echo "  DELETE_LOGS=true    Delete CloudWatch log group"
        echo "  DRY_RUN=true        Perform dry run"
        echo
        echo "Examples:"
        echo "  $0                  # Interactive cleanup"
        echo "  $0 --force          # Skip confirmations"
        echo "  $0 --delete-logs    # Include log group deletion"
        echo "  DRY_RUN=true $0     # Preview what would be deleted"
        exit 0
        ;;
    --force)
        export FORCE_DELETE=true
        ;;
    --delete-logs)
        export DELETE_LOGS=true
        ;;
    --dry-run)
        export DRY_RUN=true
        ;;
    "")
        # No arguments, proceed normally
        ;;
    *)
        error "Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main function
main "$@"