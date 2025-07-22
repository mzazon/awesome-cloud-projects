#!/bin/bash

# Cleanup script for Automated Development Environment Provisioning with WorkSpaces Personal
# This script removes all infrastructure created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CLEANUP_LOG="$PROJECT_ROOT/cleanup.log"

# Initialize cleanup log
echo "=== Cleanup started at $(date) ===" > "$CLEANUP_LOG"

# Cleanup function for script interruption
cleanup_on_interrupt() {
    log_warning "Cleanup interrupted. Check $CLEANUP_LOG for details."
    exit 1
}

trap cleanup_on_interrupt SIGINT SIGTERM

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI to perform cleanup."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load environment variables
load_environment_variables() {
    log_info "Loading environment variables from deployment..."
    
    local env_file="$PROJECT_ROOT/deployment-vars.env"
    if [[ ! -f "$env_file" ]]; then
        log_error "Environment file not found: $env_file"
        log_error "This script requires variables from the deployment. Please run deploy.sh first or provide variables manually."
        exit 1
    fi
    
    # Source environment variables
    set -a  # Automatically export all variables
    source "$env_file"
    set +a  # Stop automatically exporting
    
    # Verify required variables are set
    local required_vars=("AWS_REGION" "AWS_ACCOUNT_ID" "PROJECT_NAME" "LAMBDA_FUNCTION_NAME" 
                         "IAM_ROLE_NAME" "SECRET_NAME" "SSM_DOCUMENT_NAME" "EVENTBRIDGE_RULE_NAME" "RANDOM_SUFFIX")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    log_success "Environment variables loaded successfully"
    log_info "Using region: $AWS_REGION"
    log_info "Using account: $AWS_ACCOUNT_ID"
    log_info "Using random suffix: $RANDOM_SUFFIX"
}

# Function to confirm cleanup action
confirm_cleanup() {
    log_warning "This will permanently delete the following resources:"
    echo "- EventBridge Rule: $EVENTBRIDGE_RULE_NAME"
    echo "- Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "- IAM Role: $IAM_ROLE_NAME"
    echo "- IAM Policy: ${PROJECT_NAME}-lambda-policy-${RANDOM_SUFFIX}"
    echo "- SSM Document: $SSM_DOCUMENT_NAME"
    echo "- Secrets Manager Secret: $SECRET_NAME"
    echo "- Local temporary files and directories"
    echo ""
    
    # Skip confirmation if --force flag is provided
    if [[ "${1:-}" == "--force" ]]; then
        log_warning "Force flag detected, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "User confirmed cleanup, proceeding..."
}

# Function to remove EventBridge rule and targets
remove_eventbridge_rule() {
    log_info "Removing EventBridge rule and targets..."
    
    # Check if rule exists
    if ! aws events describe-rule --name "$EVENTBRIDGE_RULE_NAME" &>/dev/null; then
        log_warning "EventBridge rule $EVENTBRIDGE_RULE_NAME does not exist, skipping"
        return 0
    fi
    
    # Remove targets from the rule
    log_info "Removing targets from EventBridge rule..."
    aws events remove-targets \
        --rule "$EVENTBRIDGE_RULE_NAME" \
        --ids "1" \
        --output table >> "$CLEANUP_LOG" 2>&1 || log_warning "No targets to remove or removal failed"
    
    # Delete the rule
    log_info "Deleting EventBridge rule..."
    aws events delete-rule \
        --name "$EVENTBRIDGE_RULE_NAME" \
        --output table >> "$CLEANUP_LOG" 2>&1
    
    log_success "EventBridge rule removed successfully"
}

# Function to remove Lambda function
remove_lambda_function() {
    log_info "Removing Lambda function..."
    
    # Check if function exists
    if ! aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log_warning "Lambda function $LAMBDA_FUNCTION_NAME does not exist, skipping"
        return 0
    fi
    
    # Remove Lambda permission for EventBridge (if it exists)
    log_info "Removing Lambda permission for EventBridge..."
    aws lambda remove-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id "allow-eventbridge-invocation" \
        --output table >> "$CLEANUP_LOG" 2>&1 || log_warning "Permission may not exist or removal failed"
    
    # Delete Lambda function
    log_info "Deleting Lambda function..."
    aws lambda delete-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --output table >> "$CLEANUP_LOG" 2>&1
    
    log_success "Lambda function removed successfully"
}

# Function to remove IAM role and policy
remove_iam_resources() {
    log_info "Removing IAM role and policy..."
    
    local policy_name="${PROJECT_NAME}-lambda-policy-${RANDOM_SUFFIX}"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy_name"
    
    # Check if role exists
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        # Detach all managed policies from role
        log_info "Detaching policies from IAM role..."
        local attached_policies
        attached_policies=$(aws iam list-attached-role-policies \
            --role-name "$IAM_ROLE_NAME" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text)
        
        if [[ -n "$attached_policies" ]]; then
            for policy in $attached_policies; do
                log_info "Detaching policy: $policy"
                aws iam detach-role-policy \
                    --role-name "$IAM_ROLE_NAME" \
                    --policy-arn "$policy" \
                    --output table >> "$CLEANUP_LOG" 2>&1
            done
        fi
        
        # Delete inline policies (if any)
        log_info "Checking for inline policies..."
        local inline_policies
        inline_policies=$(aws iam list-role-policies \
            --role-name "$IAM_ROLE_NAME" \
            --query 'PolicyNames' \
            --output text)
        
        if [[ -n "$inline_policies" && "$inline_policies" != "None" ]]; then
            for policy in $inline_policies; do
                log_info "Deleting inline policy: $policy"
                aws iam delete-role-policy \
                    --role-name "$IAM_ROLE_NAME" \
                    --policy-name "$policy" \
                    --output table >> "$CLEANUP_LOG" 2>&1
            done
        fi
        
        # Delete IAM role
        log_info "Deleting IAM role..."
        aws iam delete-role \
            --role-name "$IAM_ROLE_NAME" \
            --output table >> "$CLEANUP_LOG" 2>&1
        
        log_success "IAM role removed successfully"
    else
        log_warning "IAM role $IAM_ROLE_NAME does not exist, skipping"
    fi
    
    # Delete managed policy
    if aws iam get-policy --policy-arn "$policy_arn" &>/dev/null; then
        log_info "Deleting managed IAM policy..."
        
        # Delete all policy versions except the default
        local versions
        versions=$(aws iam list-policy-versions \
            --policy-arn "$policy_arn" \
            --query 'Versions[?!IsDefaultVersion].VersionId' \
            --output text)
        
        if [[ -n "$versions" && "$versions" != "None" ]]; then
            for version in $versions; do
                log_info "Deleting policy version: $version"
                aws iam delete-policy-version \
                    --policy-arn "$policy_arn" \
                    --version-id "$version" \
                    --output table >> "$CLEANUP_LOG" 2>&1
            done
        fi
        
        # Delete the policy
        aws iam delete-policy \
            --policy-arn "$policy_arn" \
            --output table >> "$CLEANUP_LOG" 2>&1
        
        log_success "IAM policy removed successfully"
    else
        log_warning "IAM policy $policy_name does not exist, skipping"
    fi
}

# Function to remove Systems Manager document
remove_ssm_document() {
    log_info "Removing Systems Manager document..."
    
    # Check if document exists
    if ! aws ssm describe-document --name "$SSM_DOCUMENT_NAME" &>/dev/null; then
        log_warning "SSM document $SSM_DOCUMENT_NAME does not exist, skipping"
        return 0
    fi
    
    # Delete SSM document
    aws ssm delete-document \
        --name "$SSM_DOCUMENT_NAME" \
        --output table >> "$CLEANUP_LOG" 2>&1
    
    log_success "Systems Manager document removed successfully"
}

# Function to remove Secrets Manager secret
remove_secrets_manager_secret() {
    log_info "Removing Secrets Manager secret..."
    
    # Check if secret exists
    if ! aws secretsmanager describe-secret --secret-id "$SECRET_NAME" &>/dev/null; then
        log_warning "Secret $SECRET_NAME does not exist, skipping"
        return 0
    fi
    
    # Delete secret with immediate deletion (no recovery period)
    log_warning "Deleting secret with immediate deletion (no recovery period)"
    aws secretsmanager delete-secret \
        --secret-id "$SECRET_NAME" \
        --force-delete-without-recovery \
        --output table >> "$CLEANUP_LOG" 2>&1
    
    log_success "Secrets Manager secret removed successfully"
}

# Function to clean up local files and directories
cleanup_local_files() {
    log_info "Cleaning up local files and directories..."
    
    local files_to_remove=(
        "$PROJECT_ROOT/lambda-package/"
        "$PROJECT_ROOT/lambda-deployment-package.zip"
        "$PROJECT_ROOT/lambda-trust-policy.json"
        "$PROJECT_ROOT/lambda-permissions-policy.json"
        "$PROJECT_ROOT/dev-environment-setup.json"
        "$PROJECT_ROOT/test-event.json"
        "$PROJECT_ROOT/response.json"
        "$PROJECT_ROOT/deployment-vars.env"
        "$PROJECT_ROOT/deployment.log"
    )
    
    for item in "${files_to_remove[@]}"; do
        if [[ -e "$item" ]]; then
            log_info "Removing: $item"
            rm -rf "$item"
        fi
    done
    
    log_success "Local files cleaned up successfully"
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check EventBridge rule
    if aws events describe-rule --name "$EVENTBRIDGE_RULE_NAME" &>/dev/null; then
        log_error "EventBridge rule $EVENTBRIDGE_RULE_NAME still exists"
        ((cleanup_errors++))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log_error "Lambda function $LAMBDA_FUNCTION_NAME still exists"
        ((cleanup_errors++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        log_error "IAM role $IAM_ROLE_NAME still exists"
        ((cleanup_errors++))
    fi
    
    # Check IAM policy
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-lambda-policy-${RANDOM_SUFFIX}"
    if aws iam get-policy --policy-arn "$policy_arn" &>/dev/null; then
        log_error "IAM policy still exists: $policy_arn"
        ((cleanup_errors++))
    fi
    
    # Check SSM document
    if aws ssm describe-document --name "$SSM_DOCUMENT_NAME" &>/dev/null; then
        log_error "SSM document $SSM_DOCUMENT_NAME still exists"
        ((cleanup_errors++))
    fi
    
    # Check Secrets Manager secret
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" &>/dev/null; then
        log_error "Secret $SECRET_NAME still exists"
        ((cleanup_errors++))
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        log_success "Cleanup verification passed - all resources removed successfully"
        return 0
    else
        log_error "Cleanup verification failed - $cleanup_errors resources still exist"
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "===================="
    echo "Region: $AWS_REGION"
    echo "Account ID: $AWS_ACCOUNT_ID"
    echo "Project: $PROJECT_NAME"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Removed Resources:"
    echo "- EventBridge Rule: $EVENTBRIDGE_RULE_NAME"
    echo "- Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "- IAM Role: $IAM_ROLE_NAME"
    echo "- IAM Policy: ${PROJECT_NAME}-lambda-policy-${RANDOM_SUFFIX}"
    echo "- SSM Document: $SSM_DOCUMENT_NAME"
    echo "- Secrets Manager Secret: $SECRET_NAME"
    echo "- Local files and directories"
    echo ""
    echo "Cleanup log: $CLEANUP_LOG"
    echo ""
    log_warning "Note: Any WorkSpaces created by this automation are NOT automatically removed."
    log_warning "Please review and manually terminate WorkSpaces if needed to avoid ongoing charges."
}

# Function to handle WorkSpaces cleanup warning
workspaces_cleanup_warning() {
    log_warning "IMPORTANT: WorkSpaces Cleanup Required"
    echo "=========================================="
    echo "This cleanup script removes the automation infrastructure but does NOT"
    echo "automatically terminate any WorkSpaces that may have been created."
    echo ""
    echo "To avoid ongoing charges, please:"
    echo "1. List WorkSpaces in your directory:"
    echo "   aws workspaces describe-workspaces --directory-id YOUR_DIRECTORY_ID"
    echo ""
    echo "2. Terminate WorkSpaces that are no longer needed:"
    echo "   aws workspaces terminate-workspaces --terminate-workspace-requests WorkspaceId=ws-xxxxxxxxx"
    echo ""
    echo "3. Review your WorkSpaces billing to ensure no unexpected charges"
    echo ""
    log_warning "WorkSpaces charges continue until explicitly terminated!"
}

# Main cleanup function
main() {
    log_info "Starting cleanup of WorkSpaces automation infrastructure..."
    
    check_prerequisites
    load_environment_variables
    confirm_cleanup "$@"
    workspaces_cleanup_warning
    
    # Perform cleanup in reverse order of creation
    remove_eventbridge_rule
    remove_lambda_function
    remove_iam_resources
    remove_ssm_document
    remove_secrets_manager_secret
    cleanup_local_files
    
    # Verify cleanup
    if verify_cleanup; then
        display_cleanup_summary
        log_success "Cleanup completed successfully!"
    else
        log_error "Cleanup completed with some resources still remaining"
        log_error "Please check the cleanup log and AWS console for remaining resources"
        exit 1
    fi
    
    echo "=== Cleanup completed at $(date) ===" >> "$CLEANUP_LOG"
}

# Show usage if help is requested
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script removes all infrastructure created by the WorkSpaces automation deployment."
    echo ""
    echo "OPTIONS:"
    echo "  --force    Skip confirmation prompt and proceed with cleanup"
    echo "  --help     Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                # Interactive cleanup with confirmation"
    echo "  $0 --force        # Automatic cleanup without confirmation"
    echo ""
    echo "REQUIREMENTS:"
    echo "  - AWS CLI installed and configured"
    echo "  - deployment-vars.env file from original deployment"
    echo "  - Appropriate AWS permissions for resource deletion"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        show_usage
        exit 0
        ;;
    --force|-f)
        main --force
        ;;
    "")
        main
        ;;
    *)
        echo "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac