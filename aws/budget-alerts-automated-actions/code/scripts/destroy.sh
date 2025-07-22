#!/bin/bash

# AWS Budget Alerts and Automated Actions - Cleanup Script
# This script removes all resources created by the budget deployment
# Version: 1.0
# Last Updated: 2025-07-12

set -e

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
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not authenticated. Please run 'aws configure' or set up credentials."
    fi
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. JSON processing will be limited."
    fi
    
    success "Prerequisites check completed"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    # Check if state file exists
    if [[ ! -f "./budget-deployment-state.json" ]]; then
        error "Deployment state file not found. Please ensure you're running this script from the same directory where you ran deploy.sh"
    fi
    
    # Load variables from state file
    export AWS_REGION=$(jq -r '.aws_region' ./budget-deployment-state.json)
    export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' ./budget-deployment-state.json)
    export BUDGET_EMAIL=$(jq -r '.budget_email' ./budget-deployment-state.json)
    export BUDGET_AMOUNT=$(jq -r '.budget_amount' ./budget-deployment-state.json)
    export BUDGET_NAME=$(jq -r '.budget_name' ./budget-deployment-state.json)
    export SNS_TOPIC_NAME=$(jq -r '.sns_topic_name' ./budget-deployment-state.json)
    export SNS_TOPIC_ARN=$(jq -r '.sns_topic_arn' ./budget-deployment-state.json)
    export LAMBDA_FUNCTION_NAME=$(jq -r '.lambda_function_name' ./budget-deployment-state.json)
    export LAMBDA_FUNCTION_ARN=$(jq -r '.lambda_function_arn' ./budget-deployment-state.json)
    export IAM_ROLE_NAME=$(jq -r '.iam_role_name' ./budget-deployment-state.json)
    export IAM_ROLE_ARN=$(jq -r '.iam_role_arn' ./budget-deployment-state.json)
    export IAM_POLICY_NAME=$(jq -r '.iam_policy_name' ./budget-deployment-state.json)
    export BUDGET_ACTION_POLICY_ARN=$(jq -r '.budget_action_policy_arn' ./budget-deployment-state.json)
    export BUDGET_ACTION_ROLE_ARN=$(jq -r '.budget_action_role_arn' ./budget-deployment-state.json)
    export RANDOM_SUFFIX=$(jq -r '.random_suffix' ./budget-deployment-state.json)
    
    # Validate critical variables
    if [[ -z "$BUDGET_NAME" || -z "$AWS_ACCOUNT_ID" || -z "$AWS_REGION" ]]; then
        error "Invalid deployment state file. Missing critical information."
    fi
    
    success "Deployment state loaded successfully"
    log "Budget Name: ${BUDGET_NAME}"
    log "AWS Region: ${AWS_REGION}"
    log "AWS Account ID: ${AWS_ACCOUNT_ID}"
}

# Function to prompt for confirmation
confirm_destruction() {
    echo ""
    echo "=========================================="
    echo "DESTRUCTIVE OPERATION WARNING"
    echo "=========================================="
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "- Budget: ${BUDGET_NAME}"
    echo "- SNS Topic: ${SNS_TOPIC_NAME}"
    echo "- Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "- IAM Role: ${IAM_ROLE_NAME}"
    echo "- IAM Policy: ${IAM_POLICY_NAME}"
    echo "- Budget Action Resources"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    # Check if running in non-interactive mode
    if [[ "$1" == "--force" || "$FORCE_DESTROY" == "true" ]]; then
        warning "Force mode enabled. Skipping confirmation."
        return 0
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        echo "Destruction cancelled."
        exit 0
    fi
    
    log "Confirmation received. Proceeding with resource destruction..."
}

# Function to delete budget
delete_budget() {
    log "Deleting budget: ${BUDGET_NAME}..."
    
    # Check if budget exists
    if aws budgets describe-budget \
        --account-id "${AWS_ACCOUNT_ID}" \
        --budget-name "${BUDGET_NAME}" &> /dev/null; then
        
        # Delete budget (this also removes all associated notifications)
        aws budgets delete-budget \
            --account-id "${AWS_ACCOUNT_ID}" \
            --budget-name "${BUDGET_NAME}"
        
        if [ $? -eq 0 ]; then
            success "Budget deleted successfully"
        else
            warning "Failed to delete budget, but continuing..."
        fi
    else
        warning "Budget not found or already deleted"
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function: ${LAMBDA_FUNCTION_NAME}..."
    
    # Check if Lambda function exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        
        # Delete Lambda function
        aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}"
        
        if [ $? -eq 0 ]; then
            success "Lambda function deleted successfully"
        else
            warning "Failed to delete Lambda function, but continuing..."
        fi
    else
        warning "Lambda function not found or already deleted"
    fi
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    # Detach and delete Lambda IAM policy
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}" &> /dev/null; then
        log "Detaching Lambda IAM policy from role..."
        aws iam detach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}" 2>/dev/null || true
        
        log "Deleting Lambda IAM policy..."
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}"
        
        if [ $? -eq 0 ]; then
            success "Lambda IAM policy deleted successfully"
        else
            warning "Failed to delete Lambda IAM policy, but continuing..."
        fi
    else
        warning "Lambda IAM policy not found or already deleted"
    fi
    
    # Delete Lambda IAM role
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        log "Deleting Lambda IAM role..."
        aws iam delete-role --role-name "${IAM_ROLE_NAME}"
        
        if [ $? -eq 0 ]; then
            success "Lambda IAM role deleted successfully"
        else
            warning "Failed to delete Lambda IAM role, but continuing..."
        fi
    else
        warning "Lambda IAM role not found or already deleted"
    fi
}

# Function to delete SNS topic
delete_sns_topic() {
    log "Deleting SNS topic: ${SNS_TOPIC_NAME}..."
    
    # Check if SNS topic exists
    if aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" &> /dev/null; then
        
        # Delete SNS topic (this also removes all subscriptions)
        aws sns delete-topic --topic-arn "${SNS_TOPIC_ARN}"
        
        if [ $? -eq 0 ]; then
            success "SNS topic deleted successfully"
        else
            warning "Failed to delete SNS topic, but continuing..."
        fi
    else
        warning "SNS topic not found or already deleted"
    fi
}

# Function to delete budget action resources
delete_budget_action_resources() {
    log "Deleting budget action resources..."
    
    # Delete budget action policy if it exists
    if [[ -n "$BUDGET_ACTION_POLICY_ARN" && "$BUDGET_ACTION_POLICY_ARN" != "null" ]]; then
        if aws iam get-policy --policy-arn "${BUDGET_ACTION_POLICY_ARN}" &> /dev/null; then
            log "Deleting budget action policy..."
            aws iam delete-policy --policy-arn "${BUDGET_ACTION_POLICY_ARN}"
            
            if [ $? -eq 0 ]; then
                success "Budget action policy deleted successfully"
            else
                warning "Failed to delete budget action policy, but continuing..."
            fi
        else
            warning "Budget action policy not found or already deleted"
        fi
    else
        warning "Budget action policy ARN not found in state"
    fi
    
    # Delete budget action role if it exists
    BUDGET_ACTION_ROLE_NAME="budget-action-role-${RANDOM_SUFFIX}"
    if aws iam get-role --role-name "${BUDGET_ACTION_ROLE_NAME}" &> /dev/null; then
        log "Detaching policy from budget action role..."
        aws iam detach-role-policy \
            --role-name "${BUDGET_ACTION_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/BudgetsActionsWithAWSResourceControlAccess" 2>/dev/null || true
        
        log "Deleting budget action role..."
        aws iam delete-role --role-name "${BUDGET_ACTION_ROLE_NAME}"
        
        if [ $? -eq 0 ]; then
            success "Budget action role deleted successfully"
        else
            warning "Failed to delete budget action role, but continuing..."
        fi
    else
        warning "Budget action role not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment state file
    if [[ -f "./budget-deployment-state.json" ]]; then
        rm -f ./budget-deployment-state.json
        success "Deployment state file removed"
    fi
    
    # Remove any temporary files that might be left
    rm -f /tmp/lambda-trust-policy.json 2>/dev/null || true
    rm -f /tmp/budget-action-policy.json 2>/dev/null || true
    rm -f /tmp/budget-config.json 2>/dev/null || true
    rm -f /tmp/budget-notifications.json 2>/dev/null || true
    rm -f /tmp/budget-restriction-policy.json 2>/dev/null || true
    rm -f /tmp/budget-service-trust-policy.json 2>/dev/null || true
    rm -f /tmp/budget-action-function.py 2>/dev/null || true
    rm -f /tmp/budget-action-function.zip 2>/dev/null || true
    rm -f /tmp/budget-deployment-state.json 2>/dev/null || true
    
    success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_errors=0
    
    # Check if budget still exists
    if aws budgets describe-budget \
        --account-id "${AWS_ACCOUNT_ID}" \
        --budget-name "${BUDGET_NAME}" &> /dev/null; then
        warning "Budget still exists: ${BUDGET_NAME}"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check if Lambda function still exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        warning "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check if IAM role still exists
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        warning "IAM role still exists: ${IAM_ROLE_NAME}"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check if SNS topic still exists
    if aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" &> /dev/null; then
        warning "SNS topic still exists: ${SNS_TOPIC_ARN}"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    if [ $cleanup_errors -eq 0 ]; then
        success "All resources verified as deleted"
    else
        warning "Some resources may still exist. Please check the AWS Console manually."
    fi
    
    return $cleanup_errors
}

# Function to display cleanup summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "CLEANUP COMPLETED"
    echo "=========================================="
    echo ""
    echo "Resources Removed:"
    echo "- Budget: ${BUDGET_NAME}"
    echo "- SNS Topic: ${SNS_TOPIC_NAME}"
    echo "- Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "- IAM Role: ${IAM_ROLE_NAME}"
    echo "- IAM Policy: ${IAM_POLICY_NAME}"
    echo "- Budget Action Resources"
    echo "- Local deployment state file"
    echo ""
    echo "Cost Impact:"
    echo "- Monthly budget charges stopped"
    echo "- SNS topic charges stopped"
    echo "- Lambda function charges stopped"
    echo "- No ongoing costs for destroyed resources"
    echo ""
    echo "Notes:"
    echo "- Email subscriptions may still exist in your email client"
    echo "- CloudWatch logs for the Lambda function may persist"
    echo "- Any existing EC2 instances with Environment tags remain unaffected"
    echo ""
    echo "=========================================="
}

# Function to handle cleanup errors gracefully
handle_errors() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        warning "Cleanup encountered some errors but completed as much as possible."
        warning "Please check the AWS Console to verify resource deletion."
        warning "You may need to manually delete some resources."
        exit $exit_code
    fi
}

# Set error handler
trap handle_errors EXIT

# Main execution
main() {
    echo "Starting AWS Budget Alerts and Automated Actions cleanup..."
    echo ""
    
    check_prerequisites
    load_deployment_state
    confirm_destruction "$@"
    
    # Perform cleanup in logical order
    delete_budget
    delete_lambda_function
    delete_iam_resources
    delete_sns_topic
    delete_budget_action_resources
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    display_summary
    
    success "Cleanup process completed successfully!"
}

# Execute main function with all arguments
main "$@"