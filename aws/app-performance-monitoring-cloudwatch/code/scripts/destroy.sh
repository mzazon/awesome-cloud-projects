#!/bin/bash

# Destroy script for Automated Application Performance Monitoring with CloudWatch Application Signals and EventBridge
# This script safely removes all infrastructure created by the deployment script

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI version 2.0 or higher."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured or invalid. Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. State file parsing will be limited."
    fi
    
    success "Prerequisites check completed"
}

# Function to find and load state file
load_state_file() {
    local state_file="$1"
    
    if [[ ! -f "$state_file" ]]; then
        error "State file not found: $state_file"
        log "Available state files:"
        ls -la deployment-state-*.json 2>/dev/null || log "No state files found in current directory"
        exit 1
    fi
    
    log "Loading deployment state from: $state_file"
    
    # Extract variables from state file
    if command -v jq &> /dev/null; then
        export DEPLOYMENT_ID=$(jq -r '.deployment_id' "$state_file")
        export AWS_REGION=$(jq -r '.aws_region' "$state_file")
        export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$state_file")
        export MONITORING_STACK_NAME=$(jq -r '.monitoring_stack_name' "$state_file")
        export SNS_TOPIC_NAME=$(jq -r '.sns_topic_name' "$state_file")
        export LAMBDA_FUNCTION_NAME=$(jq -r '.lambda_function_name' "$state_file")
        export EVENTBRIDGE_RULE_NAME=$(jq -r '.eventbridge_rule_name' "$state_file")
        
        # Extract created resources
        SNS_TOPIC_ARN=$(jq -r '.created_resources.sns_topic_arn // empty' "$state_file")
        DASHBOARD_NAME=$(jq -r '.created_resources.dashboard // empty' "$state_file")
        IAM_ROLE_NAME=$(jq -r '.created_resources.iam_role // empty' "$state_file")
        IAM_POLICY_NAME=$(jq -r '.created_resources.iam_policy // empty' "$state_file")
        
        # Extract alarm names
        ALARM_NAMES=$(jq -r '.created_resources.cloudwatch_alarms[]? // empty' "$state_file")
    else
        # Fallback parsing without jq
        warn "Using fallback parsing method without jq"
        export DEPLOYMENT_ID=$(grep -o '"deployment_id": *"[^"]*"' "$state_file" | cut -d'"' -f4)
        export AWS_REGION=$(grep -o '"aws_region": *"[^"]*"' "$state_file" | cut -d'"' -f4)
        export LAMBDA_FUNCTION_NAME=$(grep -o '"lambda_function_name": *"[^"]*"' "$state_file" | cut -d'"' -f4)
        export EVENTBRIDGE_RULE_NAME=$(grep -o '"eventbridge_rule_name": *"[^"]*"' "$state_file" | cut -d'"' -f4)
        export SNS_TOPIC_NAME=$(grep -o '"sns_topic_name": *"[^"]*"' "$state_file" | cut -d'"' -f4)
    fi
    
    if [[ -z "$DEPLOYMENT_ID" ]]; then
        error "Could not parse deployment ID from state file"
        exit 1
    fi
    
    log "Loaded deployment configuration:"
    log "  - Deployment ID: ${DEPLOYMENT_ID}"
    log "  - AWS Region: ${AWS_REGION}"
    log "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log "  - EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    log "  - SNS Topic: ${SNS_TOPIC_NAME}"
    
    success "State file loaded successfully"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    warn "This will permanently delete all resources created by the monitoring deployment:"
    warn "- CloudWatch Dashboard"
    warn "- CloudWatch Alarms" 
    warn "- EventBridge Rule and Targets"
    warn "- Lambda Function"
    warn "- SNS Topic and Subscriptions"
    warn "- IAM Roles and Policies"
    warn "- Application Signals Configuration"
    echo ""
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        warn "Force destroy mode enabled - skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Function to delete CloudWatch dashboard
delete_dashboard() {
    log "Deleting CloudWatch dashboard..."
    
    local dashboard_name="${DASHBOARD_NAME:-ApplicationPerformanceMonitoring-${DEPLOYMENT_ID}}"
    
    aws cloudwatch delete-dashboards \
        --dashboard-names "$dashboard_name" 2>/dev/null || warn "Dashboard may not exist or already deleted"
    
    success "CloudWatch dashboard deletion completed"
}

# Function to remove EventBridge rule and targets
remove_eventbridge_rule() {
    log "Removing EventBridge rule and targets..."
    
    # Remove targets from EventBridge rule
    aws events remove-targets \
        --rule ${EVENTBRIDGE_RULE_NAME} \
        --ids "1" 2>/dev/null || warn "EventBridge targets may not exist or already removed"
    
    # Delete EventBridge rule
    aws events delete-rule \
        --name ${EVENTBRIDGE_RULE_NAME} 2>/dev/null || warn "EventBridge rule may not exist or already deleted"
    
    success "EventBridge rule and targets removed"
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    # Define alarm names based on deployment pattern
    local alarm_names=(
        "AppSignals-HighLatency-${DEPLOYMENT_ID}"
        "AppSignals-HighErrorRate-${DEPLOYMENT_ID}"
        "AppSignals-LowThroughput-${DEPLOYMENT_ID}"
    )
    
    # Delete alarms if they exist
    for alarm_name in "${alarm_names[@]}"; do
        aws cloudwatch delete-alarms \
            --alarm-names "$alarm_name" 2>/dev/null || warn "Alarm $alarm_name may not exist or already deleted"
    done
    
    success "CloudWatch alarms deletion completed"
}

# Function to delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    # Remove EventBridge permission first
    aws lambda remove-permission \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --statement-id allow-eventbridge-invoke 2>/dev/null || warn "Lambda permission may not exist"
    
    # Delete Lambda function
    aws lambda delete-function \
        --function-name ${LAMBDA_FUNCTION_NAME} 2>/dev/null || warn "Lambda function may not exist or already deleted"
    
    success "Lambda function deleted"
}

# Function to delete SNS topic
delete_sns_topic() {
    log "Deleting SNS topic and subscriptions..."
    
    local sns_topic_arn="${SNS_TOPIC_ARN:-arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}}"
    
    # List and delete all subscriptions first
    local subscriptions=$(aws sns list-subscriptions-by-topic \
        --topic-arn "$sns_topic_arn" \
        --query 'Subscriptions[].SubscriptionArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$subscriptions" ]]; then
        for subscription_arn in $subscriptions; do
            if [[ "$subscription_arn" != "PendingConfirmation" ]]; then
                aws sns unsubscribe --subscription-arn "$subscription_arn" 2>/dev/null || warn "Could not unsubscribe: $subscription_arn"
            fi
        done
    fi
    
    # Delete SNS topic
    aws sns delete-topic \
        --topic-arn "$sns_topic_arn" 2>/dev/null || warn "SNS topic may not exist or already deleted"
    
    success "SNS topic and subscriptions deleted"
}

# Function to remove IAM roles and policies
remove_iam_resources() {
    log "Removing IAM roles and policies..."
    
    local role_name="${IAM_ROLE_NAME:-${LAMBDA_FUNCTION_NAME}-role}"
    local policy_name="${IAM_POLICY_NAME:-${LAMBDA_FUNCTION_NAME}-policy}"
    
    # Detach policies from IAM role
    aws iam detach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || warn "Basic execution policy may not be attached"
    
    aws iam detach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name} 2>/dev/null || warn "Custom policy may not be attached"
    
    # Delete custom IAM policy
    aws iam delete-policy \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name} 2>/dev/null || warn "Custom policy may not exist or already deleted"
    
    # Delete IAM role
    aws iam delete-role \
        --role-name "$role_name" 2>/dev/null || warn "IAM role may not exist or already deleted"
    
    success "IAM roles and policies removed"
}

# Function to clean up Application Signals resources
cleanup_application_signals() {
    log "Cleaning up Application Signals resources..."
    
    # Delete Service Level Objectives
    local slo_name="app-performance-slo-${DEPLOYMENT_ID}"
    aws application-signals delete-service-level-objective \
        --service-level-objective-name "$slo_name" 2>/dev/null || warn "Application Signals SLO may not exist or already deleted"
    
    # Clean up log groups (be careful not to delete other application logs)
    aws logs delete-log-group \
        --log-group-name /aws/application-signals/data 2>/dev/null || warn "Application Signals log group may not exist or already deleted"
    
    success "Application Signals resources cleanup completed"
}

# Function to verify resource deletion
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check Lambda function
    if aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME} &>/dev/null; then
        warn "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check EventBridge rule
    if aws events describe-rule --name ${EVENTBRIDGE_RULE_NAME} &>/dev/null; then
        warn "EventBridge rule still exists: ${EVENTBRIDGE_RULE_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check SNS topic
    local sns_topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    if aws sns get-topic-attributes --topic-arn "$sns_topic_arn" &>/dev/null; then
        warn "SNS topic still exists: ${SNS_TOPIC_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check IAM role
    local role_name="${LAMBDA_FUNCTION_NAME}-role"
    if aws iam get-role --role-name "$role_name" &>/dev/null; then
        warn "IAM role still exists: $role_name"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        success "All resources have been successfully deleted"
    else
        warn "Some resources may still exist ($cleanup_issues issues found)"
        warn "You may need to manually delete remaining resources or wait for eventual consistency"
    fi
}

# Function to remove state file
cleanup_state_file() {
    local state_file="$1"
    
    log "Cleaning up state file..."
    
    if [[ -f "$state_file" ]]; then
        rm -f "$state_file"
        success "State file deleted: $state_file"
    else
        warn "State file not found: $state_file"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    log "================"
    log "Deployment ID: ${DEPLOYMENT_ID}"
    log "AWS Region: ${AWS_REGION}"
    log ""
    log "Deleted Resources:"
    log "- CloudWatch Dashboard: ApplicationPerformanceMonitoring-${DEPLOYMENT_ID}"
    log "- EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    log "- CloudWatch Alarms: AppSignals-HighLatency-${DEPLOYMENT_ID}, AppSignals-HighErrorRate-${DEPLOYMENT_ID}, AppSignals-LowThroughput-${DEPLOYMENT_ID}"
    log "- Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log "- SNS Topic: ${SNS_TOPIC_NAME}"
    log "- IAM Role: ${LAMBDA_FUNCTION_NAME}-role"
    log "- IAM Policy: ${LAMBDA_FUNCTION_NAME}-policy"
    log "- Application Signals SLO: app-performance-slo-${DEPLOYMENT_ID}"
    log ""
    log "Note: Some resources may take a few minutes to be fully deleted due to AWS eventual consistency."
}

# Main cleanup function
main() {
    local state_file="${1:-}"
    
    log "Starting cleanup of Automated Application Performance Monitoring resources"
    log "======================================================================="
    
    check_prerequisites
    
    # If no state file specified, try to find one
    if [[ -z "$state_file" ]]; then
        # Look for state files in current directory
        local state_files=(deployment-state-*.json)
        if [[ ${#state_files[@]} -eq 1 && -f "${state_files[0]}" ]]; then
            state_file="${state_files[0]}"
            log "Found state file: $state_file"
        else
            error "No state file specified and could not auto-detect one."
            log "Usage: $0 <path-to-state-file>"
            log "Or: $0 (if deployment-state-*.json exists in current directory)"
            exit 1
        fi
    fi
    
    load_state_file "$state_file"
    confirm_destruction
    
    # Run cleanup steps in reverse order of creation
    delete_dashboard
    remove_eventbridge_rule
    delete_cloudwatch_alarms
    delete_lambda_function
    delete_sns_topic
    remove_iam_resources
    cleanup_application_signals
    
    verify_cleanup
    display_cleanup_summary
    cleanup_state_file "$state_file"
    
    success "Cleanup completed successfully! 🎉"
    log "All monitoring infrastructure has been removed."
}

# Handle script interruption
cleanup_on_interrupt() {
    error "Script interrupted during cleanup."
    warn "Some resources may be in an inconsistent state."
    warn "You may need to manually verify and clean up remaining resources."
    exit 1
}

trap cleanup_on_interrupt INT

# Show usage if help requested
show_usage() {
    echo "Usage: $0 [OPTIONS] [STATE_FILE]"
    echo ""
    echo "Options:"
    echo "  --force          Skip confirmation prompts"
    echo "  --dry-run        Show what would be deleted without actually deleting"
    echo "  --help           Show this help message"
    echo ""
    echo "Arguments:"
    echo "  STATE_FILE       Path to the deployment state file (optional if auto-detectable)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Auto-detect state file"
    echo "  $0 deployment-state-abc123.json      # Use specific state file"
    echo "  $0 --force                           # Skip confirmations"
    echo "  $0 --dry-run                         # Preview destruction"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY="true"
            shift
            ;;
        --dry-run)
            log "DRY RUN MODE - No resources will be deleted"
            log "This would destroy all monitoring infrastructure"
            exit 0
            ;;
        --help)
            show_usage
            exit 0
            ;;
        -*)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            STATE_FILE_ARG="$1"
            shift
            ;;
    esac
done

# Run main cleanup
main "${STATE_FILE_ARG:-}"