#!/bin/bash

# Destroy script for Automated Security Scanning with Inspector and Security Hub
# This script removes all resources created by the deploy.sh script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    success "Prerequisites check completed"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    if [[ ! -f .deployment_state ]]; then
        error "Deployment state file (.deployment_state) not found. Cannot proceed with cleanup."
    fi
    
    # Source the deployment state file
    source .deployment_state
    
    # Set AWS region if not already set
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Please set AWS_REGION environment variable."
    fi
    
    success "Deployment state loaded"
    log "Region: $AWS_REGION"
    log "Account ID: $AWS_ACCOUNT_ID"
    log "Resource suffix: $RANDOM_SUFFIX"
}

# Function to confirm deletion
confirm_deletion() {
    echo
    echo "=================================="
    echo "    RESOURCE CLEANUP WARNING"
    echo "=================================="
    echo "This will delete the following resources:"
    echo "- EventBridge Rules and Targets"
    echo "- Lambda Functions and Permissions"
    echo "- IAM Roles and Policies"
    echo "- SNS Topic and Subscriptions"
    echo "- Security Hub Custom Insights"
    echo "- Inspector Configuration (optional)"
    echo "- Security Hub (optional)"
    echo
    echo "Region: $AWS_REGION"
    echo "Account ID: $AWS_ACCOUNT_ID"
    echo "=================================="
    echo
    
    read -p "Are you sure you want to proceed with cleanup? (yes/no): " confirm
    if [[ $confirm != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    # Ask about Security Hub and Inspector
    echo
    read -p "Do you want to disable Inspector scanning? (yes/no): " disable_inspector
    read -p "Do you want to disable Security Hub? (This will remove all findings data) (yes/no): " disable_securityhub
    
    export DISABLE_INSPECTOR=$disable_inspector
    export DISABLE_SECURITYHUB=$disable_securityhub
}

# Function to remove EventBridge rules and targets
cleanup_eventbridge() {
    log "Cleaning up EventBridge rules and targets..."
    
    # Remove targets from EventBridge rules
    if aws events list-targets-by-rule --rule "$EVENTBRIDGE_RULE_NAME" >/dev/null 2>&1; then
        log "Removing targets from security findings rule..."
        aws events remove-targets \
            --rule "$EVENTBRIDGE_RULE_NAME" \
            --ids "1" || warning "Failed to remove targets from $EVENTBRIDGE_RULE_NAME"
    fi
    
    if aws events list-targets-by-rule --rule "$WEEKLY_REPORT_RULE" >/dev/null 2>&1; then
        log "Removing targets from weekly report rule..."
        aws events remove-targets \
            --rule "$WEEKLY_REPORT_RULE" \
            --ids "1" || warning "Failed to remove targets from $WEEKLY_REPORT_RULE"
    fi
    
    # Delete EventBridge rules
    if aws events describe-rule --name "$EVENTBRIDGE_RULE_NAME" >/dev/null 2>&1; then
        log "Deleting security findings EventBridge rule..."
        aws events delete-rule \
            --name "$EVENTBRIDGE_RULE_NAME" || warning "Failed to delete rule $EVENTBRIDGE_RULE_NAME"
    fi
    
    if aws events describe-rule --name "$WEEKLY_REPORT_RULE" >/dev/null 2>&1; then
        log "Deleting weekly report EventBridge rule..."
        aws events delete-rule \
            --name "$WEEKLY_REPORT_RULE" || warning "Failed to delete rule $WEEKLY_REPORT_RULE"
    fi
    
    success "EventBridge cleanup completed"
}

# Function to remove Lambda functions and permissions
cleanup_lambda() {
    log "Cleaning up Lambda functions..."
    
    # Remove Lambda permissions first
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        log "Removing Lambda permissions for security response handler..."
        aws lambda remove-permission \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --statement-id "AllowEventBridge" || warning "Failed to remove permission for $LAMBDA_FUNCTION_NAME"
        
        # Delete security response Lambda function
        log "Deleting security response Lambda function..."
        aws lambda delete-function \
            --function-name "$LAMBDA_FUNCTION_NAME" || warning "Failed to delete Lambda function $LAMBDA_FUNCTION_NAME"
    fi
    
    if aws lambda get-function --function-name "$COMPLIANCE_LAMBDA_NAME" >/dev/null 2>&1; then
        log "Removing Lambda permissions for compliance reporter..."
        aws lambda remove-permission \
            --function-name "$COMPLIANCE_LAMBDA_NAME" \
            --statement-id "AllowEventBridgeWeekly" || warning "Failed to remove permission for $COMPLIANCE_LAMBDA_NAME"
        
        # Delete compliance reporting Lambda function
        log "Deleting compliance reporting Lambda function..."
        aws lambda delete-function \
            --function-name "$COMPLIANCE_LAMBDA_NAME" || warning "Failed to delete Lambda function $COMPLIANCE_LAMBDA_NAME"
    fi
    
    success "Lambda functions cleanup completed"
}

# Function to remove IAM roles and policies
cleanup_iam() {
    log "Cleaning up IAM roles and policies..."
    
    # Get role name and policy ARN from state files if they exist
    if [[ -f .lambda_role_name ]]; then
        ROLE_NAME=$(cat .lambda_role_name)
        
        # Detach AWS managed policy
        log "Detaching AWS managed policy from role..."
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || warning "Failed to detach AWS managed policy"
        
        # Detach and delete custom policy
        if [[ -f .lambda_policy_arn ]]; then
            POLICY_ARN=$(cat .lambda_policy_arn)
            log "Detaching custom policy from role..."
            aws iam detach-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-arn "$POLICY_ARN" || warning "Failed to detach custom policy"
            
            log "Deleting custom IAM policy..."
            aws iam delete-policy \
                --policy-arn "$POLICY_ARN" || warning "Failed to delete custom policy"
        fi
        
        # Delete IAM role
        log "Deleting IAM role..."
        aws iam delete-role \
            --role-name "$ROLE_NAME" || warning "Failed to delete IAM role $ROLE_NAME"
    fi
    
    success "IAM cleanup completed"
}

# Function to remove SNS topic
cleanup_sns() {
    log "Cleaning up SNS topic..."
    
    if [[ -f .sns_topic_arn ]]; then
        SNS_TOPIC_ARN=$(cat .sns_topic_arn)
        
        # List and unsubscribe all subscriptions
        log "Removing SNS subscriptions..."
        SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$SNS_TOPIC_ARN" \
            --query 'Subscriptions[].SubscriptionArn' \
            --output text 2>/dev/null || echo "")
        
        for subscription in $SUBSCRIPTIONS; do
            if [[ "$subscription" != "None" && "$subscription" != "PendingConfirmation" ]]; then
                aws sns unsubscribe --subscription-arn "$subscription" || warning "Failed to unsubscribe $subscription"
            fi
        done
        
        # Delete SNS topic
        log "Deleting SNS topic..."
        aws sns delete-topic \
            --topic-arn "$SNS_TOPIC_ARN" || warning "Failed to delete SNS topic"
    fi
    
    success "SNS cleanup completed"
}

# Function to remove Security Hub custom insights
cleanup_security_hub_insights() {
    log "Cleaning up Security Hub custom insights..."
    
    # Get list of insights
    INSIGHTS=$(aws securityhub get-insights \
        --query 'Insights[?contains(Name, `Critical Vulnerabilities`) || contains(Name, `Unpatched EC2`)].InsightArn' \
        --output text 2>/dev/null || echo "")
    
    for insight_arn in $INSIGHTS; do
        if [[ -n "$insight_arn" && "$insight_arn" != "None" ]]; then
            log "Deleting Security Hub insight: $insight_arn"
            aws securityhub delete-insight \
                --insight-arn "$insight_arn" || warning "Failed to delete insight $insight_arn"
        fi
    done
    
    success "Security Hub insights cleanup completed"
}

# Function to disable Inspector (optional)
disable_inspector() {
    if [[ "$DISABLE_INSPECTOR" == "yes" ]]; then
        log "Disabling Inspector scanning..."
        
        aws inspector2 disable \
            --resource-types EC2 ECR LAMBDA \
            --region "$AWS_REGION" || warning "Failed to disable Inspector"
        
        success "Inspector disabled"
    else
        warning "Inspector scanning left enabled (as requested)"
    fi
}

# Function to disable Security Hub (optional)
disable_security_hub() {
    if [[ "$DISABLE_SECURITYHUB" == "yes" ]]; then
        log "Disabling Security Hub..."
        
        # Disable security standards first
        log "Disabling security standards..."
        STANDARDS=$(aws securityhub get-enabled-standards \
            --query 'StandardsSubscriptions[].StandardsSubscriptionArn' \
            --output text 2>/dev/null || echo "")
        
        for standard in $STANDARDS; do
            if [[ -n "$standard" && "$standard" != "None" ]]; then
                aws securityhub batch-disable-standards \
                    --standards-subscription-arns "$standard" || warning "Failed to disable standard $standard"
            fi
        done
        
        # Disable Security Hub
        aws securityhub disable-security-hub || warning "Failed to disable Security Hub"
        
        success "Security Hub disabled"
    else
        warning "Security Hub left enabled (as requested)"
    fi
}

# Function to clean up temporary files
cleanup_files() {
    log "Cleaning up temporary files..."
    
    # Remove policy documents
    rm -f security-hub-trust-policy.json
    rm -f lambda-trust-policy.json
    rm -f lambda-response-policy.json
    
    # Remove Lambda function code
    rm -f security-response-handler.py
    rm -f security-response-handler.zip
    rm -f compliance-report-generator.py
    rm -f compliance-report-generator.zip
    
    # Remove state tracking files
    rm -f .sns_topic_arn
    rm -f .lambda_function_arn
    rm -f .compliance_lambda_arn
    rm -f .lambda_role_name
    rm -f .lambda_policy_arn
    rm -f .eventbridge_rule_name
    rm -f .weekly_rule_name
    rm -f .deployment_state
    
    success "Temporary files cleaned up"
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup completed!"
    echo
    echo "=================================="
    echo "    CLEANUP SUMMARY"
    echo "=================================="
    echo "Removed Resources:"
    echo "✓ EventBridge Rules and Targets"
    echo "✓ Lambda Functions and Permissions"
    echo "✓ IAM Roles and Policies"
    echo "✓ SNS Topic and Subscriptions"
    echo "✓ Security Hub Custom Insights"
    echo "✓ Temporary Files"
    echo
    if [[ "$DISABLE_INSPECTOR" == "yes" ]]; then
        echo "✓ Inspector Scanning (disabled)"
    else
        echo "○ Inspector Scanning (left enabled)"
    fi
    
    if [[ "$DISABLE_SECURITYHUB" == "yes" ]]; then
        echo "✓ Security Hub (disabled)"
    else
        echo "○ Security Hub (left enabled)"
    fi
    echo
    echo "Region: $AWS_REGION"
    echo "Account ID: $AWS_ACCOUNT_ID"
    echo
    if [[ "$DISABLE_INSPECTOR" != "yes" || "$DISABLE_SECURITYHUB" != "yes" ]]; then
        echo "Note: Some AWS services were left enabled as requested."
        echo "You may continue to incur charges for these services."
        echo
        if [[ "$DISABLE_INSPECTOR" != "yes" ]]; then
            echo "To disable Inspector manually:"
            echo "aws inspector2 disable --resource-types EC2 ECR LAMBDA"
        fi
        if [[ "$DISABLE_SECURITYHUB" != "yes" ]]; then
            echo "To disable Security Hub manually:"
            echo "aws securityhub disable-security-hub"
        fi
    fi
    echo "=================================="
}

# Main cleanup function
main() {
    log "Starting cleanup of Automated Security Scanning infrastructure"
    
    check_prerequisites
    load_deployment_state
    confirm_deletion
    
    cleanup_eventbridge
    cleanup_lambda
    cleanup_iam
    cleanup_sns
    cleanup_security_hub_insights
    disable_inspector
    disable_security_hub
    cleanup_files
    
    display_summary
    success "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may not have been cleaned up."' INT TERM

# Run main function
main "$@"