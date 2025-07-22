#!/bin/bash

# AWS Automated Security Incident Response with Security Hub - Cleanup Script
# This script removes all resources created by the deployment script
# as described in the recipe: Security Incident Response Automation

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAMBDA_DIR="${SCRIPT_DIR}/../lambda-functions"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
ENV_FILE="${SCRIPT_DIR}/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message function
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if environment file exists
    if [ ! -f "$ENV_FILE" ]; then
        warning "Environment file not found. Some resources may need manual cleanup."
        return 1
    fi
    
    success "Prerequisites check completed"
    return 0
}

# Load environment variables
load_environment() {
    info "Loading environment variables..."
    
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
        success "Environment variables loaded from $ENV_FILE"
    else
        warning "Environment file not found. Using manual cleanup approach."
        
        # Try to detect resources by pattern
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            warning "AWS region not configured, defaulting to us-east-1"
        fi
        
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Will need to search for resources by pattern
        return 1
    fi
}

# Confirmation prompt
confirm_cleanup() {
    echo ""
    echo -e "${YELLOW}⚠️  WARNING: This will delete ALL resources created by the deployment script!${NC}"
    echo ""
    echo "This includes:"
    echo "- Lambda Functions"
    echo "- IAM Roles and Policies"
    echo "- EventBridge Rules"
    echo "- SNS Topics"
    echo "- Security Hub Custom Actions and Insights"
    echo "- Test findings and local files"
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    info "Cleanup confirmed. Proceeding with resource deletion..."
}

# Delete EventBridge rules and targets
delete_eventbridge_rules() {
    info "Deleting EventBridge rules and targets..."
    
    if [ -n "$EVENTBRIDGE_RULE_NAME" ]; then
        # Remove targets from rules
        aws events remove-targets \
            --rule "${EVENTBRIDGE_RULE_NAME}-critical" \
            --ids "1" "2" "3" 2>/dev/null || warning "Failed to remove targets from critical rule"
        
        aws events remove-targets \
            --rule "${EVENTBRIDGE_RULE_NAME}-medium" \
            --ids "1" "2" 2>/dev/null || warning "Failed to remove targets from medium rule"
        
        aws events remove-targets \
            --rule "${EVENTBRIDGE_RULE_NAME}-manual-escalation" \
            --ids "1" 2>/dev/null || warning "Failed to remove targets from manual escalation rule"
        
        # Delete EventBridge rules
        aws events delete-rule --name "${EVENTBRIDGE_RULE_NAME}-critical" 2>/dev/null || warning "Failed to delete critical rule"
        aws events delete-rule --name "${EVENTBRIDGE_RULE_NAME}-medium" 2>/dev/null || warning "Failed to delete medium rule"
        aws events delete-rule --name "${EVENTBRIDGE_RULE_NAME}-manual-escalation" 2>/dev/null || warning "Failed to delete manual escalation rule"
        
        success "EventBridge rules deleted"
    else
        warning "EVENTBRIDGE_RULE_NAME not set, attempting pattern-based cleanup"
        
        # Search for rules by pattern
        local rules=$(aws events list-rules --query 'Rules[?contains(Name, `security-hub-findings`)].Name' --output text 2>/dev/null || echo "")
        
        if [ -n "$rules" ]; then
            for rule in $rules; do
                info "Deleting rule: $rule"
                aws events remove-targets --rule "$rule" --ids $(aws events list-targets-by-rule --rule "$rule" --query 'Targets[].Id' --output text) 2>/dev/null || true
                aws events delete-rule --name "$rule" 2>/dev/null || warning "Failed to delete rule: $rule"
            done
        fi
    fi
}

# Delete Lambda functions
delete_lambda_functions() {
    info "Deleting Lambda functions..."
    
    if [ -n "$CLASSIFICATION_FUNCTION_NAME" ] && [ -n "$REMEDIATION_FUNCTION_NAME" ] && [ -n "$NOTIFICATION_FUNCTION_NAME" ]; then
        # Delete Lambda functions
        aws lambda delete-function --function-name "$CLASSIFICATION_FUNCTION_NAME" 2>/dev/null || warning "Failed to delete classification function"
        aws lambda delete-function --function-name "$REMEDIATION_FUNCTION_NAME" 2>/dev/null || warning "Failed to delete remediation function"
        aws lambda delete-function --function-name "$NOTIFICATION_FUNCTION_NAME" 2>/dev/null || warning "Failed to delete notification function"
        
        success "Lambda functions deleted"
    else
        warning "Lambda function names not set, attempting pattern-based cleanup"
        
        # Search for functions by pattern
        local functions=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `security-`)].FunctionName' --output text 2>/dev/null || echo "")
        
        if [ -n "$functions" ]; then
            for func in $functions; do
                info "Deleting Lambda function: $func"
                aws lambda delete-function --function-name "$func" 2>/dev/null || warning "Failed to delete function: $func"
            done
        fi
    fi
}

# Delete Security Hub custom actions and insights
delete_security_hub_resources() {
    info "Deleting Security Hub custom actions and insights..."
    
    # Delete custom actions
    if [ -f "$LAMBDA_DIR/custom-action-arn.txt" ]; then
        local custom_action_arn=$(cat "$LAMBDA_DIR/custom-action-arn.txt" 2>/dev/null || echo "")
        if [ -n "$custom_action_arn" ]; then
            aws securityhub delete-action-target --action-target-arn "$custom_action_arn" 2>/dev/null || warning "Failed to delete custom action"
        fi
    else
        # Search for custom actions by pattern
        local actions=$(aws securityhub describe-action-targets --query 'ActionTargets[?contains(Name, `Escalate`)].ActionTargetArn' --output text 2>/dev/null || echo "")
        for action in $actions; do
            info "Deleting custom action: $action"
            aws securityhub delete-action-target --action-target-arn "$action" 2>/dev/null || warning "Failed to delete custom action: $action"
        done
    fi
    
    # Delete insights
    if [ -f "$LAMBDA_DIR/critical-insight-arn.txt" ]; then
        local critical_insight_arn=$(cat "$LAMBDA_DIR/critical-insight-arn.txt" 2>/dev/null || echo "")
        if [ -n "$critical_insight_arn" ]; then
            aws securityhub delete-insight --insight-arn "$critical_insight_arn" 2>/dev/null || warning "Failed to delete critical insight"
        fi
    fi
    
    if [ -f "$LAMBDA_DIR/unresolved-insight-arn.txt" ]; then
        local unresolved_insight_arn=$(cat "$LAMBDA_DIR/unresolved-insight-arn.txt" 2>/dev/null || echo "")
        if [ -n "$unresolved_insight_arn" ]; then
            aws securityhub delete-insight --insight-arn "$unresolved_insight_arn" 2>/dev/null || warning "Failed to delete unresolved insight"
        fi
    fi
    
    # Search for insights by pattern if files don't exist
    local insights=$(aws securityhub get-insights --query 'Insights[?contains(Name, `Critical`) || contains(Name, `Unresolved`)].InsightArn' --output text 2>/dev/null || echo "")
    for insight in $insights; do
        info "Deleting insight: $insight"
        aws securityhub delete-insight --insight-arn "$insight" 2>/dev/null || warning "Failed to delete insight: $insight"
    done
    
    success "Security Hub custom actions and insights deleted"
}

# Delete SNS topic and subscriptions
delete_sns_topic() {
    info "Deleting SNS topic and subscriptions..."
    
    if [ -n "$SNS_TOPIC_NAME" ]; then
        local sns_topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
        aws sns delete-topic --topic-arn "$sns_topic_arn" 2>/dev/null || warning "Failed to delete SNS topic"
        success "SNS topic deleted"
    elif [ -f "$LAMBDA_DIR/sns-topic-arn.txt" ]; then
        local sns_topic_arn=$(cat "$LAMBDA_DIR/sns-topic-arn.txt" 2>/dev/null || echo "")
        if [ -n "$sns_topic_arn" ]; then
            aws sns delete-topic --topic-arn "$sns_topic_arn" 2>/dev/null || warning "Failed to delete SNS topic"
        fi
    else
        warning "SNS topic name not set, attempting pattern-based cleanup"
        
        # Search for topics by pattern
        local topics=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `security-incidents`)].TopicArn' --output text 2>/dev/null || echo "")
        
        for topic in $topics; do
            info "Deleting SNS topic: $topic"
            aws sns delete-topic --topic-arn "$topic" 2>/dev/null || warning "Failed to delete topic: $topic"
        done
    fi
}

# Delete IAM roles and policies
delete_iam_roles() {
    info "Deleting IAM roles and policies..."
    
    if [ -n "$INCIDENT_RESPONSE_ROLE_NAME" ]; then
        # Delete IAM role policies
        aws iam delete-role-policy \
            --role-name "$INCIDENT_RESPONSE_ROLE_NAME" \
            --policy-name "IncidentResponsePolicy" 2>/dev/null || warning "Failed to delete role policy"
        
        # Delete IAM roles
        aws iam delete-role --role-name "$INCIDENT_RESPONSE_ROLE_NAME" 2>/dev/null || warning "Failed to delete IAM role"
        
        success "IAM roles deleted"
    else
        warning "IAM role name not set, attempting pattern-based cleanup"
        
        # Search for roles by pattern
        local roles=$(aws iam list-roles --query 'Roles[?contains(RoleName, `IncidentResponse`) || contains(RoleName, `SecurityHub`)].RoleName' --output text 2>/dev/null || echo "")
        
        for role in $roles; do
            info "Deleting IAM role: $role"
            
            # List and delete attached policies
            local policies=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames' --output text 2>/dev/null || echo "")
            for policy in $policies; do
                aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || warning "Failed to delete policy: $policy"
            done
            
            # Delete role
            aws iam delete-role --role-name "$role" 2>/dev/null || warning "Failed to delete role: $role"
        done
    fi
}

# Clean up test findings and local files
cleanup_local_files() {
    info "Cleaning up test findings and local files..."
    
    # Clean up lambda functions directory
    if [ -d "$LAMBDA_DIR" ]; then
        cd "$SCRIPT_DIR"
        rm -rf "$LAMBDA_DIR"
        success "Lambda functions directory cleaned up"
    fi
    
    # Clean up environment file
    if [ -f "$ENV_FILE" ]; then
        rm -f "$ENV_FILE"
        success "Environment file cleaned up"
    fi
    
    # Note: Security Hub findings will age out automatically
    info "Note: Test findings in Security Hub will age out automatically"
    info "You can manually archive test findings if needed"
    
    success "Local files cleaned up"
}

# Security Hub cleanup confirmation
security_hub_cleanup_prompt() {
    echo ""
    echo -e "${YELLOW}⚠️  Security Hub Status${NC}"
    echo ""
    echo "Security Hub has been left enabled as it may contain important security findings."
    echo "Test findings will age out automatically."
    echo ""
    echo -e "${BLUE}To completely disable Security Hub (this will remove ALL findings):${NC}"
    echo "aws securityhub disable-security-hub"
    echo ""
    
    read -p "Do you want to disable Security Hub now? (y/N): " disable_hub
    
    if [[ "$disable_hub" =~ ^[Yy]$ ]]; then
        info "Disabling Security Hub..."
        aws securityhub disable-security-hub 2>/dev/null || warning "Failed to disable Security Hub"
        success "Security Hub disabled"
    else
        info "Security Hub left enabled"
    fi
}

# Manual cleanup guidance
print_manual_cleanup_guidance() {
    echo ""
    echo "=== MANUAL CLEANUP GUIDANCE ==="
    echo ""
    echo "If some resources were not automatically deleted, you can clean them up manually:"
    echo ""
    echo "1. Lambda Functions:"
    echo "   aws lambda list-functions --query 'Functions[?contains(FunctionName, \`security-\`)].FunctionName'"
    echo "   aws lambda delete-function --function-name <function-name>"
    echo ""
    echo "2. EventBridge Rules:"
    echo "   aws events list-rules --query 'Rules[?contains(Name, \`security-hub-findings\`)].Name'"
    echo "   aws events delete-rule --name <rule-name>"
    echo ""
    echo "3. IAM Roles:"
    echo "   aws iam list-roles --query 'Roles[?contains(RoleName, \`IncidentResponse\`)].RoleName'"
    echo "   aws iam delete-role --role-name <role-name>"
    echo ""
    echo "4. SNS Topics:"
    echo "   aws sns list-topics --query 'Topics[?contains(TopicArn, \`security-incidents\`)].TopicArn'"
    echo "   aws sns delete-topic --topic-arn <topic-arn>"
    echo ""
    echo "5. Security Hub Resources:"
    echo "   aws securityhub describe-action-targets"
    echo "   aws securityhub get-insights"
    echo ""
}

# Main cleanup function
main() {
    info "Starting AWS Automated Security Incident Response cleanup..."
    
    # Create log file
    touch "$LOG_FILE"
    
    # Check prerequisites and load environment
    if ! check_prerequisites; then
        warning "Proceeding with limited cleanup capabilities"
    fi
    
    if ! load_environment; then
        warning "Environment not fully loaded, using pattern-based cleanup"
    fi
    
    # Confirm cleanup
    confirm_cleanup
    
    # Run cleanup steps in reverse order of creation
    delete_eventbridge_rules
    delete_lambda_functions
    delete_security_hub_resources
    delete_sns_topic
    delete_iam_roles
    cleanup_local_files
    
    success "🎉 AWS Automated Security Incident Response cleanup completed!"
    
    # Security Hub cleanup prompt
    security_hub_cleanup_prompt
    
    # Print manual cleanup guidance
    print_manual_cleanup_guidance
    
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    echo "✅ EventBridge rules and targets deleted"
    echo "✅ Lambda functions deleted"
    echo "✅ Security Hub custom actions and insights deleted"
    echo "✅ SNS topics deleted"
    echo "✅ IAM roles and policies deleted"
    echo "✅ Local files cleaned up"
    echo ""
    echo "=== NOTES ==="
    echo "- Security Hub may still be enabled"
    echo "- Test findings will age out automatically"
    echo "- Check the manual cleanup guidance above for any remaining resources"
    echo ""
    echo "Cleanup log saved to: $LOG_FILE"
    
    log "Cleanup completed successfully"
}

# Run main function
main "$@"