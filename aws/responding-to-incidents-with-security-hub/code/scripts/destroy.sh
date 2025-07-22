#!/bin/bash

# Security Incident Response with AWS Security Hub - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    # Check if state file exists
    if [[ ! -f "/tmp/security-hub-deployment-state.env" ]]; then
        error "Deployment state file not found at /tmp/security-hub-deployment-state.env"
        error "Unable to determine which resources to clean up"
        error "Please provide the following environment variables manually:"
        error "  - AWS_REGION"
        error "  - AWS_ACCOUNT_ID"
        error "  - SECURITY_HUB_ROLE_NAME"
        error "  - LAMBDA_ROLE_NAME"
        error "  - SNS_TOPIC_NAME"
        error "  - LAMBDA_FUNCTION_NAME"
        error "  - CUSTOM_ACTION_NAME"
        error "  - THREAT_INTEL_FUNCTION_NAME"
        error "  - SQS_QUEUE_NAME"
        exit 1
    fi
    
    # Source the deployment state
    source /tmp/security-hub-deployment-state.env
    
    success "Deployment state loaded successfully"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "Security Hub Role: $SECURITY_HUB_ROLE_NAME"
    log "Lambda Role: $LAMBDA_ROLE_NAME"
    log "SNS Topic: $SNS_TOPIC_NAME"
    log "Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "Threat Intel Function: $THREAT_INTEL_FUNCTION_NAME"
    log "SQS Queue: $SQS_QUEUE_NAME"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will PERMANENTLY DELETE the following AWS resources:"
    echo "- CloudWatch Dashboard: SecurityHubIncidentResponse"
    echo "- CloudWatch Alarm: SecurityHubIncidentProcessingFailures"
    echo "- Security Hub Automation Rules (2 rules)"
    echo "- Security Hub Custom Action: Escalate to SOC"
    echo "- EventBridge Rules: security-hub-high-severity, security-hub-custom-escalation"
    echo "- Lambda Functions: $LAMBDA_FUNCTION_NAME, $THREAT_INTEL_FUNCTION_NAME"
    echo "- SNS Topic: $SNS_TOPIC_NAME"
    echo "- SQS Queue: $SQS_QUEUE_NAME"
    echo "- IAM Roles: $SECURITY_HUB_ROLE_NAME, $LAMBDA_ROLE_NAME"
    echo "- IAM Policy: SecurityHubLambdaPolicy-*"
    echo ""
    warning "Security Hub itself will NOT be disabled, only the custom configurations will be removed."
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Cleanup confirmed. Proceeding with resource deletion..."
}

# Function to remove CloudWatch resources
remove_monitoring() {
    log "Removing CloudWatch monitoring resources..."
    
    # Delete CloudWatch alarm
    if aws cloudwatch describe-alarms --alarm-names SecurityHubIncidentProcessingFailures &> /dev/null; then
        aws cloudwatch delete-alarms \
            --alarm-names SecurityHubIncidentProcessingFailures
        success "CloudWatch alarm deleted"
    else
        warning "CloudWatch alarm not found or already deleted"
    fi
    
    # Delete CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name SecurityHubIncidentResponse &> /dev/null; then
        aws cloudwatch delete-dashboards \
            --dashboard-names SecurityHubIncidentResponse
        success "CloudWatch dashboard deleted"
    else
        warning "CloudWatch dashboard not found or already deleted"
    fi
}

# Function to remove Security Hub automation
remove_security_hub_automation() {
    log "Removing Security Hub automation rules and custom actions..."
    
    # Get automation rules
    local automation_rules=$(aws securityhub list-automation-rules \
        --query 'AutomationRules[?contains(RuleName, `Suppress Low Priority Findings`) || contains(RuleName, `Escalate Critical Findings`)].RuleArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$automation_rules" ]]; then
        # Convert space-separated ARNs to JSON array format
        local rule_arns_json=$(echo "$automation_rules" | tr ' ' '\n' | jq -R . | jq -s .)
        
        aws securityhub batch-delete-automation-rules \
            --automation-rules-arns "$rule_arns_json" \
            --output table > /dev/null
        success "Security Hub automation rules deleted"
    else
        warning "No automation rules found to delete"
    fi
    
    # Delete custom action
    if [[ -n "$CUSTOM_ACTION_ARN" ]]; then
        aws securityhub delete-action-target \
            --action-target-arn "$CUSTOM_ACTION_ARN" \
            --output table > /dev/null 2>/dev/null || warning "Custom action not found or already deleted"
        success "Security Hub custom action deleted"
    else
        warning "Custom action ARN not found in state"
    fi
}

# Function to remove EventBridge rules
remove_eventbridge_rules() {
    log "Removing EventBridge rules and targets..."
    
    # Remove targets first, then delete rules
    local rules=("security-hub-high-severity" "security-hub-custom-escalation")
    
    for rule in "${rules[@]}"; do
        # Remove targets from rule
        if aws events describe-rule --name "$rule" &> /dev/null; then
            # Get target IDs
            local target_ids=$(aws events list-targets-by-rule --rule "$rule" \
                --query 'Targets[].Id' --output text 2>/dev/null || echo "")
            
            if [[ -n "$target_ids" ]]; then
                aws events remove-targets \
                    --rule "$rule" \
                    --ids $target_ids \
                    --output table > /dev/null
                log "Removed targets from EventBridge rule: $rule"
            fi
            
            # Delete the rule
            aws events delete-rule --name "$rule" --output table > /dev/null
            success "EventBridge rule deleted: $rule"
        else
            warning "EventBridge rule not found: $rule"
        fi
    done
}

# Function to remove Lambda functions
remove_lambda_functions() {
    log "Removing Lambda functions..."
    
    # Delete main incident processor function
    if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
            aws lambda delete-function \
                --function-name "$LAMBDA_FUNCTION_NAME" \
                --output table > /dev/null
            success "Lambda function deleted: $LAMBDA_FUNCTION_NAME"
        else
            warning "Lambda function not found: $LAMBDA_FUNCTION_NAME"
        fi
    fi
    
    # Delete threat intelligence function
    if [[ -n "$THREAT_INTEL_FUNCTION_NAME" ]]; then
        if aws lambda get-function --function-name "$THREAT_INTEL_FUNCTION_NAME" &> /dev/null; then
            aws lambda delete-function \
                --function-name "$THREAT_INTEL_FUNCTION_NAME" \
                --output table > /dev/null
            success "Lambda function deleted: $THREAT_INTEL_FUNCTION_NAME"
        else
            warning "Lambda function not found: $THREAT_INTEL_FUNCTION_NAME"
        fi
    fi
    
    # Wait for Lambda functions to be fully deleted
    sleep 5
}

# Function to remove messaging infrastructure
remove_messaging_infrastructure() {
    log "Removing SNS and SQS resources..."
    
    # Delete SQS queue
    if [[ -n "$QUEUE_URL" ]]; then
        if aws sqs get-queue-attributes --queue-url "$QUEUE_URL" &> /dev/null; then
            aws sqs delete-queue --queue-url "$QUEUE_URL" --output table > /dev/null
            success "SQS queue deleted: $SQS_QUEUE_NAME"
        else
            warning "SQS queue not found: $SQS_QUEUE_NAME"
        fi
    elif [[ -n "$SQS_QUEUE_NAME" ]]; then
        # Try to find queue by name if URL not available
        local queue_url=$(aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" \
            --query QueueUrl --output text 2>/dev/null || echo "")
        if [[ -n "$queue_url" ]]; then
            aws sqs delete-queue --queue-url "$queue_url" --output table > /dev/null
            success "SQS queue deleted: $SQS_QUEUE_NAME"
        else
            warning "SQS queue not found: $SQS_QUEUE_NAME"
        fi
    fi
    
    # Delete SNS topic
    if [[ -n "$SNS_TOPIC_ARN" ]]; then
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &> /dev/null; then
            aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" --output table > /dev/null
            success "SNS topic deleted: $SNS_TOPIC_NAME"
        else
            warning "SNS topic not found: $SNS_TOPIC_NAME"
        fi
    elif [[ -n "$SNS_TOPIC_NAME" ]]; then
        # Try to find topic by name if ARN not available
        local topic_arn=$(aws sns list-topics --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" \
            --output text 2>/dev/null || echo "")
        if [[ -n "$topic_arn" ]]; then
            aws sns delete-topic --topic-arn "$topic_arn" --output table > /dev/null
            success "SNS topic deleted: $SNS_TOPIC_NAME"
        else
            warning "SNS topic not found: $SNS_TOPIC_NAME"
        fi
    fi
}

# Function to remove IAM resources
remove_iam_resources() {
    log "Removing IAM roles and policies..."
    
    # Remove Lambda role
    if [[ -n "$LAMBDA_ROLE_NAME" ]]; then
        if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
            # Detach managed policies
            aws iam detach-role-policy \
                --role-name "$LAMBDA_ROLE_NAME" \
                --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
                2>/dev/null || warning "Basic execution policy already detached"
            
            # Detach custom policy
            local custom_policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SecurityHubLambdaPolicy-${LAMBDA_ROLE_NAME##*-}"
            aws iam detach-role-policy \
                --role-name "$LAMBDA_ROLE_NAME" \
                --policy-arn "$custom_policy_arn" \
                2>/dev/null || warning "Custom policy already detached"
            
            # Delete the role
            aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" --output table > /dev/null
            success "IAM role deleted: $LAMBDA_ROLE_NAME"
            
            # Delete custom policy
            aws iam delete-policy --policy-arn "$custom_policy_arn" \
                --output table > /dev/null 2>/dev/null || warning "Custom policy already deleted"
            success "IAM policy deleted: SecurityHubLambdaPolicy-${LAMBDA_ROLE_NAME##*-}"
        else
            warning "Lambda IAM role not found: $LAMBDA_ROLE_NAME"
        fi
    fi
    
    # Remove Security Hub role
    if [[ -n "$SECURITY_HUB_ROLE_NAME" ]]; then
        if aws iam get-role --role-name "$SECURITY_HUB_ROLE_NAME" &> /dev/null; then
            aws iam delete-role --role-name "$SECURITY_HUB_ROLE_NAME" --output table > /dev/null
            success "IAM role deleted: $SECURITY_HUB_ROLE_NAME"
        else
            warning "Security Hub IAM role not found: $SECURITY_HUB_ROLE_NAME"
        fi
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove Lambda function zip files
    rm -f /tmp/incident_processor.py /tmp/incident_processor.zip
    rm -f /tmp/threat_intelligence.py /tmp/threat_intelligence.zip
    
    # Keep the deployment state file for potential future reference
    if [[ -f "/tmp/security-hub-deployment-state.env" ]]; then
        warning "Deployment state file preserved at: /tmp/security-hub-deployment-state.env"
        warning "You may delete this file manually if no longer needed"
    fi
    
    success "Temporary files cleaned up"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating resource cleanup..."
    
    local cleanup_errors=0
    
    # Check Lambda functions
    if [[ -n "$LAMBDA_FUNCTION_NAME" ]] && aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        error "Lambda function still exists: $LAMBDA_FUNCTION_NAME"
        ((cleanup_errors++))
    fi
    
    if [[ -n "$THREAT_INTEL_FUNCTION_NAME" ]] && aws lambda get-function --function-name "$THREAT_INTEL_FUNCTION_NAME" &> /dev/null; then
        error "Threat intelligence function still exists: $THREAT_INTEL_FUNCTION_NAME"
        ((cleanup_errors++))
    fi
    
    # Check SNS topic
    if [[ -n "$SNS_TOPIC_ARN" ]] && aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &> /dev/null; then
        error "SNS topic still exists: $SNS_TOPIC_ARN"
        ((cleanup_errors++))
    fi
    
    # Check SQS queue
    if [[ -n "$QUEUE_URL" ]] && aws sqs get-queue-attributes --queue-url "$QUEUE_URL" &> /dev/null; then
        error "SQS queue still exists: $QUEUE_URL"
        ((cleanup_errors++))
    fi
    
    # Check IAM roles
    if [[ -n "$LAMBDA_ROLE_NAME" ]] && aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        error "Lambda IAM role still exists: $LAMBDA_ROLE_NAME"
        ((cleanup_errors++))
    fi
    
    if [[ -n "$SECURITY_HUB_ROLE_NAME" ]] && aws iam get-role --role-name "$SECURITY_HUB_ROLE_NAME" &> /dev/null; then
        error "Security Hub IAM role still exists: $SECURITY_HUB_ROLE_NAME"
        ((cleanup_errors++))
    fi
    
    # Check EventBridge rules
    if aws events describe-rule --name security-hub-high-severity &> /dev/null; then
        error "EventBridge rule still exists: security-hub-high-severity"
        ((cleanup_errors++))
    fi
    
    if aws events describe-rule --name security-hub-custom-escalation &> /dev/null; then
        error "EventBridge rule still exists: security-hub-custom-escalation"
        ((cleanup_errors++))
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        success "All resources cleaned up successfully"
        return 0
    else
        error "Cleanup validation failed with $cleanup_errors errors"
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo ""
    echo "The following resources have been removed:"
    echo "✅ CloudWatch Dashboard: SecurityHubIncidentResponse"
    echo "✅ CloudWatch Alarm: SecurityHubIncidentProcessingFailures"
    echo "✅ Security Hub Automation Rules"
    echo "✅ Security Hub Custom Action: Escalate to SOC"
    echo "✅ EventBridge Rules: security-hub-high-severity, security-hub-custom-escalation"
    echo "✅ Lambda Functions: $LAMBDA_FUNCTION_NAME, $THREAT_INTEL_FUNCTION_NAME"
    echo "✅ SNS Topic: $SNS_TOPIC_NAME"
    echo "✅ SQS Queue: $SQS_QUEUE_NAME"
    echo "✅ IAM Roles: $SECURITY_HUB_ROLE_NAME, $LAMBDA_ROLE_NAME"
    echo "✅ IAM Policy: SecurityHubLambdaPolicy-*"
    echo ""
    warning "Note: AWS Security Hub itself remains enabled with default standards"
    warning "If you want to disable Security Hub completely, run:"
    echo "  aws securityhub disable-security-hub"
    echo ""
    success "Security incident response system cleanup completed!"
}

# Function to handle script interruption
cleanup_on_interrupt() {
    echo ""
    warning "Script interrupted by user"
    warning "Partial cleanup may have occurred"
    warning "Please review AWS resources manually"
    exit 130
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq not found. Some operations may be limited."
        warning "Install jq for better JSON processing: https://stedolan.github.io/jq/"
    fi
    
    success "Prerequisites check completed"
}

# Main cleanup function
main() {
    log "Starting Security Hub Incident Response cleanup..."
    
    # Set up interrupt handler
    trap cleanup_on_interrupt SIGINT SIGTERM
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_state
    confirm_destruction
    remove_monitoring
    remove_security_hub_automation
    remove_eventbridge_rules
    remove_lambda_functions
    remove_messaging_infrastructure
    remove_iam_resources
    cleanup_temp_files
    
    # Validate cleanup
    if validate_cleanup; then
        display_cleanup_summary
        success "Cleanup completed successfully!"
    else
        error "Cleanup completed with some errors"
        error "Please review the output above and clean up remaining resources manually"
        exit 1
    fi
}

# Execute main function
main "$@"