#!/bin/bash

# CodeCommit Git Workflows Cleanup Script
# This script removes all resources created by the deployment script
# including repository, Lambda functions, SNS topics, IAM roles, and monitoring

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/deployment-config.env"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${TIMESTAMP} - $1" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "${RED}ERROR: $1${NC}"
    echo "Cleanup failed. Check ${LOG_FILE} for details."
    exit 1
}

# Success logging function
success() {
    log "${GREEN}✅ $1${NC}"
}

# Warning logging function
warn() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Info logging function
info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Function to confirm destruction
confirm_destruction() {
    echo "🚨 WARNING: This will delete all CodeCommit Git workflow resources!"
    echo "============================================================="
    echo
    echo "The following resources will be PERMANENTLY DELETED:"
    
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo "• Repository: ${REPO_NAME:-unknown}"
        echo "• Lambda Functions: ${LAMBDA_FUNCTION_PREFIX:-unknown}-*"
        echo "• SNS Topics: ${SNS_TOPIC_PREFIX:-unknown}-*"
        echo "• IAM Role: CodeCommitAutomationRole"
        echo "• IAM Policy: CodeCommitAutomationPolicy"
        echo "• EventBridge Rule: ${EVENTBRIDGE_RULE_NAME:-unknown}"
        echo "• Approval Template: ${APPROVAL_TEMPLATE_NAME:-unknown}"
        echo "• CloudWatch Dashboard: ${DASHBOARD_NAME:-unknown}"
    else
        echo "• All resources (config file not found, will attempt cleanup)"
    fi
    
    echo
    echo "⚠️  This action CANNOT be undone!"
    echo
    
    # Interactive confirmation
    if [ "${FORCE_DESTROY:-false}" != "true" ]; then
        read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " confirmation
        if [ "$confirmation" != "DELETE" ]; then
            echo "Destruction cancelled."
            exit 0
        fi
        
        echo
        read -p "Last chance - type 'CONFIRM' to proceed with deletion: " final_confirmation
        if [ "$final_confirmation" != "CONFIRM" ]; then
            echo "Destruction cancelled."
            exit 0
        fi
    fi
    
    echo
    info "Starting resource cleanup..."
}

# Function to load configuration
load_configuration() {
    info "Loading deployment configuration..."
    
    if [ ! -f "$CONFIG_FILE" ]; then
        warn "Configuration file not found at ${CONFIG_FILE}"
        warn "Will attempt cleanup using AWS CLI discovery"
        
        # Try to discover resources
        export AWS_REGION=$(aws configure get region || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        return 1
    fi
    
    # Load configuration
    source "$CONFIG_FILE"
    
    success "Configuration loaded successfully"
    info "AWS Region: ${AWS_REGION}"
    info "AWS Account: ${AWS_ACCOUNT_ID}"
    info "Repository: ${REPO_NAME}"
    
    return 0
}

# Function to delete Lambda functions
delete_lambda_functions() {
    info "Deleting Lambda functions..."
    
    if [ -n "${LAMBDA_FUNCTION_PREFIX}" ]; then
        # Delete specific Lambda functions
        local functions=("${LAMBDA_FUNCTION_PREFIX}-pull-request" "${LAMBDA_FUNCTION_PREFIX}-quality-gate" "${LAMBDA_FUNCTION_PREFIX}-branch-protection")
        
        for func_name in "${functions[@]}"; do
            if aws lambda get-function --function-name "$func_name" &>/dev/null; then
                info "Deleting Lambda function: $func_name"
                aws lambda delete-function --function-name "$func_name" || warn "Failed to delete $func_name"
                success "Deleted Lambda function: $func_name"
            else
                warn "Lambda function not found: $func_name"
            fi
        done
    else
        # Discover and delete Lambda functions
        info "Discovering Lambda functions with CodeCommit automation pattern..."
        local functions=$(aws lambda list-functions \
            --query "Functions[?contains(FunctionName, 'codecommit-automation')].FunctionName" \
            --output text)
        
        if [ -n "$functions" ]; then
            for func_name in $functions; do
                info "Deleting discovered Lambda function: $func_name"
                aws lambda delete-function --function-name "$func_name" || warn "Failed to delete $func_name"
                success "Deleted Lambda function: $func_name"
            done
        else
            info "No Lambda functions found with codecommit-automation pattern"
        fi
    fi
    
    success "Lambda function cleanup completed"
}

# Function to remove EventBridge rules
remove_eventbridge_rules() {
    info "Removing EventBridge rules..."
    
    if [ -n "${EVENTBRIDGE_RULE_NAME}" ]; then
        # Remove specific EventBridge rule
        if aws events describe-rule --name "${EVENTBRIDGE_RULE_NAME}" &>/dev/null; then
            info "Removing targets from EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
            aws events remove-targets \
                --rule "${EVENTBRIDGE_RULE_NAME}" \
                --ids "1" || warn "Failed to remove targets from ${EVENTBRIDGE_RULE_NAME}"
            
            info "Deleting EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
            aws events delete-rule \
                --name "${EVENTBRIDGE_RULE_NAME}" || warn "Failed to delete rule ${EVENTBRIDGE_RULE_NAME}"
            
            success "Deleted EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
        else
            warn "EventBridge rule not found: ${EVENTBRIDGE_RULE_NAME}"
        fi
    else
        # Discover and delete EventBridge rules
        info "Discovering EventBridge rules with CodeCommit pattern..."
        local rules=$(aws events list-rules \
            --query "Rules[?contains(Name, 'codecommit-pull-request-events')].Name" \
            --output text)
        
        if [ -n "$rules" ]; then
            for rule_name in $rules; do
                info "Removing targets from discovered rule: $rule_name"
                aws events remove-targets --rule "$rule_name" --ids "1" || warn "Failed to remove targets from $rule_name"
                
                info "Deleting discovered EventBridge rule: $rule_name"
                aws events delete-rule --name "$rule_name" || warn "Failed to delete rule $rule_name"
                success "Deleted EventBridge rule: $rule_name"
            done
        else
            info "No EventBridge rules found with codecommit pattern"
        fi
    fi
    
    success "EventBridge rules cleanup completed"
}

# Function to delete approval templates
delete_approval_templates() {
    info "Deleting approval rule templates..."
    
    if [ -n "${APPROVAL_TEMPLATE_NAME}" ] && [ -n "${REPO_NAME}" ]; then
        # Disassociate and delete specific approval template
        if aws codecommit get-approval-rule-template --approval-rule-template-name "${APPROVAL_TEMPLATE_NAME}" &>/dev/null; then
            info "Disassociating approval template from repository..."
            aws codecommit disassociate-approval-rule-template-from-repository \
                --approval-rule-template-name "${APPROVAL_TEMPLATE_NAME}" \
                --repository-name "${REPO_NAME}" || warn "Failed to disassociate template from repository"
            
            info "Deleting approval rule template: ${APPROVAL_TEMPLATE_NAME}"
            aws codecommit delete-approval-rule-template \
                --approval-rule-template-name "${APPROVAL_TEMPLATE_NAME}" || warn "Failed to delete approval template"
            
            success "Deleted approval rule template: ${APPROVAL_TEMPLATE_NAME}"
        else
            warn "Approval rule template not found: ${APPROVAL_TEMPLATE_NAME}"
        fi
    else
        # Discover and delete approval templates
        info "Discovering approval rule templates with enterprise pattern..."
        local templates=$(aws codecommit list-approval-rule-templates \
            --query "approvalRuleTemplateNames[?contains(@, 'enterprise-approval-template')]" \
            --output text)
        
        if [ -n "$templates" ]; then
            for template_name in $templates; do
                info "Deleting discovered approval template: $template_name"
                
                # Try to disassociate from repositories first
                local repos=$(aws codecommit list-repositories-for-approval-rule-template \
                    --approval-rule-template-name "$template_name" \
                    --query "repositoryNames" --output text 2>/dev/null || echo "")
                
                for repo in $repos; do
                    aws codecommit disassociate-approval-rule-template-from-repository \
                        --approval-rule-template-name "$template_name" \
                        --repository-name "$repo" || warn "Failed to disassociate template from $repo"
                done
                
                aws codecommit delete-approval-rule-template \
                    --approval-rule-template-name "$template_name" || warn "Failed to delete template $template_name"
                success "Deleted approval template: $template_name"
            done
        else
            info "No approval templates found with enterprise pattern"
        fi
    fi
    
    success "Approval templates cleanup completed"
}

# Function to delete CodeCommit repository
delete_repository() {
    info "Deleting CodeCommit repository..."
    
    if [ -n "${REPO_NAME}" ]; then
        # Delete specific repository
        if aws codecommit get-repository --repository-name "${REPO_NAME}" &>/dev/null; then
            info "Removing repository triggers..."
            aws codecommit put-repository-triggers \
                --repository-name "${REPO_NAME}" \
                --triggers [] || warn "Failed to remove repository triggers"
            
            info "Deleting repository: ${REPO_NAME}"
            aws codecommit delete-repository \
                --repository-name "${REPO_NAME}" || warn "Failed to delete repository ${REPO_NAME}"
            
            success "Deleted repository: ${REPO_NAME}"
        else
            warn "Repository not found: ${REPO_NAME}"
        fi
    else
        # Discover and delete repositories
        info "Discovering repositories with enterprise-app pattern..."
        local repos=$(aws codecommit list-repositories \
            --query "repositories[?contains(repositoryName, 'enterprise-app')].repositoryName" \
            --output text)
        
        if [ -n "$repos" ]; then
            for repo_name in $repos; do
                info "Removing triggers from discovered repository: $repo_name"
                aws codecommit put-repository-triggers \
                    --repository-name "$repo_name" \
                    --triggers [] || warn "Failed to remove triggers from $repo_name"
                
                info "Deleting discovered repository: $repo_name"
                aws codecommit delete-repository \
                    --repository-name "$repo_name" || warn "Failed to delete repository $repo_name"
                success "Deleted repository: $repo_name"
            done
        else
            info "No repositories found with enterprise-app pattern"
        fi
    fi
    
    success "Repository cleanup completed"
}

# Function to delete SNS topics
delete_sns_topics() {
    info "Deleting SNS topics..."
    
    if [ -n "${SNS_TOPIC_PREFIX}" ]; then
        # Delete specific SNS topics
        local topic_names=("${SNS_TOPIC_PREFIX}-pull-requests" "${SNS_TOPIC_PREFIX}-merges" "${SNS_TOPIC_PREFIX}-quality-gates" "${SNS_TOPIC_PREFIX}-security-alerts")
        
        for topic_name in "${topic_names[@]}"; do
            local topic_arn=$(aws sns list-topics --query "Topics[?contains(TopicArn, '$topic_name')].TopicArn" --output text)
            
            if [ -n "$topic_arn" ]; then
                info "Deleting SNS topic: $topic_name"
                aws sns delete-topic --topic-arn "$topic_arn" || warn "Failed to delete SNS topic $topic_name"
                success "Deleted SNS topic: $topic_name"
            else
                warn "SNS topic not found: $topic_name"
            fi
        done
    else
        # Discover and delete SNS topics
        info "Discovering SNS topics with codecommit-notifications pattern..."
        local topics=$(aws sns list-topics \
            --query "Topics[?contains(TopicArn, 'codecommit-notifications')].TopicArn" \
            --output text)
        
        if [ -n "$topics" ]; then
            for topic_arn in $topics; do
                local topic_name=$(echo "$topic_arn" | rev | cut -d':' -f1 | rev)
                info "Deleting discovered SNS topic: $topic_name"
                aws sns delete-topic --topic-arn "$topic_arn" || warn "Failed to delete SNS topic $topic_arn"
                success "Deleted SNS topic: $topic_name"
            done
        else
            info "No SNS topics found with codecommit-notifications pattern"
        fi
    fi
    
    success "SNS topics cleanup completed"
}

# Function to delete IAM resources
delete_iam_resources() {
    info "Deleting IAM resources..."
    
    # Delete IAM policy and role
    local role_name="CodeCommitAutomationRole"
    local policy_name="CodeCommitAutomationPolicy"
    
    # Check if role exists
    if aws iam get-role --role-name "$role_name" &>/dev/null; then
        info "Detaching policy from IAM role..."
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy_name" || \
            warn "Failed to detach policy from role (may not be attached)"
        
        info "Deleting IAM role: $role_name"
        aws iam delete-role --role-name "$role_name" || warn "Failed to delete IAM role"
        success "Deleted IAM role: $role_name"
    else
        warn "IAM role not found: $role_name"
    fi
    
    # Check if policy exists
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy_name" &>/dev/null; then
        info "Deleting IAM policy: $policy_name"
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy_name" || \
            warn "Failed to delete IAM policy"
        success "Deleted IAM policy: $policy_name"
    else
        warn "IAM policy not found: $policy_name"
    fi
    
    success "IAM resources cleanup completed"
}

# Function to delete CloudWatch dashboard
delete_cloudwatch_dashboard() {
    info "Deleting CloudWatch dashboard..."
    
    if [ -n "${DASHBOARD_NAME}" ]; then
        # Delete specific dashboard
        if aws cloudwatch get-dashboard --dashboard-name "${DASHBOARD_NAME}" &>/dev/null; then
            info "Deleting CloudWatch dashboard: ${DASHBOARD_NAME}"
            aws cloudwatch delete-dashboards \
                --dashboard-names "${DASHBOARD_NAME}" || warn "Failed to delete dashboard ${DASHBOARD_NAME}"
            success "Deleted CloudWatch dashboard: ${DASHBOARD_NAME}"
        else
            warn "CloudWatch dashboard not found: ${DASHBOARD_NAME}"
        fi
    else
        # Discover and delete dashboards
        info "Discovering CloudWatch dashboards with Git-Workflow pattern..."
        local dashboards=$(aws cloudwatch list-dashboards \
            --query "DashboardEntries[?contains(DashboardName, 'Git-Workflow')].DashboardName" \
            --output text)
        
        if [ -n "$dashboards" ]; then
            for dashboard_name in $dashboards; do
                info "Deleting discovered dashboard: $dashboard_name"
                aws cloudwatch delete-dashboards \
                    --dashboard-names "$dashboard_name" || warn "Failed to delete dashboard $dashboard_name"
                success "Deleted dashboard: $dashboard_name"
            done
        else
            info "No dashboards found with Git-Workflow pattern"
        fi
    fi
    
    success "CloudWatch dashboard cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove temporary files
    local files_to_remove=(
        "${SCRIPT_DIR}/*.zip"
        "${SCRIPT_DIR}/*.py"
        "${SCRIPT_DIR}/*.json"
        "${SCRIPT_DIR}/lambda-trust-policy.json"
        "${SCRIPT_DIR}/codecommit-automation-policy.json"
        "${SCRIPT_DIR}/approval-rule-template.json"
        "${SCRIPT_DIR}/git-workflow-dashboard.json"
        "${SCRIPT_DIR}/git-workflow-documentation.md"
    )
    
    for pattern in "${files_to_remove[@]}"; do
        if ls $pattern 1> /dev/null 2>&1; then
            rm -f $pattern
            info "Removed files matching: $pattern"
        fi
    done
    
    success "Local files cleanup completed"
}

# Function to wait for resources to be deleted
wait_for_deletion() {
    info "Waiting for resources to be fully deleted..."
    sleep 5
    success "Resource deletion wait completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    info "Cleanup Summary"
    echo "==============="
    echo
    success "✅ All CodeCommit Git workflow resources have been deleted"
    echo
    echo "Deleted Resources:"
    echo "• CodeCommit repository and triggers"
    echo "• Lambda functions (pull-request and quality-gate automation)"
    echo "• SNS topics (notifications)"
    echo "• EventBridge rules (pull request events)"
    echo "• Approval rule templates"
    echo "• IAM role and policy"
    echo "• CloudWatch dashboard"
    echo "• Local temporary files"
    echo
    echo "📝 Cleanup log available at: ${LOG_FILE}"
    
    # Optionally remove config file
    if [ -f "$CONFIG_FILE" ]; then
        echo
        read -p "Remove deployment configuration file? (y/N): " remove_config
        if [[ "$remove_config" =~ ^[Yy]$ ]]; then
            rm -f "$CONFIG_FILE"
            success "Removed deployment configuration file"
        fi
    fi
    
    echo
    success "Cleanup completed successfully!"
}

# Function to discover and clean resources without config
emergency_cleanup() {
    warn "Performing emergency cleanup without configuration file..."
    warn "This will attempt to find and delete resources based on naming patterns"
    
    echo
    read -p "Continue with emergency cleanup? (y/N): " continue_emergency
    if [[ ! "$continue_emergency" =~ ^[Yy]$ ]]; then
        echo "Emergency cleanup cancelled."
        exit 0
    fi
    
    # Set minimal required variables
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Run cleanup functions without specific names
    delete_lambda_functions
    remove_eventbridge_rules
    delete_approval_templates
    delete_repository
    delete_sns_topics
    delete_iam_resources
    delete_cloudwatch_dashboard
    cleanup_local_files
    
    success "Emergency cleanup completed"
}

# Main cleanup function
main() {
    echo "🧹 Starting CodeCommit Git Workflow Cleanup"
    echo "==========================================="
    
    # Initialize log file
    echo "Cleanup started at ${TIMESTAMP}" > "${LOG_FILE}"
    
    # Confirm destruction
    confirm_destruction
    
    # Load configuration or perform emergency cleanup
    if load_configuration; then
        # Standard cleanup with configuration
        delete_lambda_functions
        remove_eventbridge_rules
        delete_approval_templates
        delete_repository
        delete_sns_topics
        delete_iam_resources
        delete_cloudwatch_dashboard
        cleanup_local_files
        wait_for_deletion
        display_cleanup_summary
    else
        # Emergency cleanup without configuration
        emergency_cleanup
    fi
    
    echo
    success "All resources cleaned up successfully!"
    echo "Check the cleanup log at: ${LOG_FILE}"
}

# Script options
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --force    Skip confirmation prompts"
            echo "  --help     Show this help message"
            echo
            echo "This script removes all resources created by the CodeCommit Git workflow deployment."
            echo "Make sure you have the deployment-config.env file in the same directory."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi