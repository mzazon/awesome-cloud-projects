#!/bin/bash

# destroy.sh - Cleanup script for Automated Email Notification Systems
# Recipe: Email Notification Automation with SES
# 
# This script removes all resources created by the deployment script:
# - Amazon SES templates and configurations
# - AWS Lambda functions and IAM resources
# - Amazon EventBridge buses and rules
# - CloudWatch alarms and log groups
# - S3 buckets and objects

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Remove all resources created by the automated email notification system deployment.

OPTIONS:
    -p, --project-name NAME      Project name prefix (required)
    -R, --region REGION          AWS region (optional, uses current region)
    --force                      Skip confirmation prompts
    --dry-run                    Show what would be destroyed without making changes
    --keep-emails                Keep verified email addresses in SES
    -h, --help                   Show this help message

EXAMPLES:
    $0 --project-name email-automation-abc123
    $0 -p email-automation-abc123 --force
    $0 --project-name email-automation-abc123 --dry-run
    $0 -p email-automation-abc123 --keep-emails

WARNING:
    This script will permanently delete all resources. Make sure you have
    backed up any important data before running this script.

EOF
}

# Default values
DRY_RUN=false
FORCE=false
KEEP_EMAILS=false
PROJECT_NAME=""
AWS_REGION=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -R|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --keep-emails)
            KEEP_EMAILS=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$PROJECT_NAME" ]]; then
    log_error "Project name is required. Use --project-name option."
    
    # Try to find deployment info file
    local info_files=(deployment-info-*.txt)
    if [[ -e "${info_files[0]}" ]]; then
        log_info "Found deployment info files:"
        for file in "${info_files[@]}"; do
            if [[ -f "$file" ]]; then
                local project=$(grep "^PROJECT_NAME=" "$file" | cut -d= -f2)
                log_info "  - $file (project: $project)"
            fi
        done
        log_info "You can use one of these project names with --project-name option."
    fi
    
    usage
    exit 1
fi

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Setup environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            AWS_REGION="us-east-1"
            log_warning "No region configured, using default: $AWS_REGION"
        fi
    fi
    export AWS_REGION
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Set project-specific variables
    export PROJECT_NAME
    export S3_BUCKET="lambda-deployment-${PROJECT_NAME}"
    
    # Try to load deployment info if available
    local info_file="deployment-info-${PROJECT_NAME}.txt"
    if [[ -f "$info_file" ]]; then
        log_info "Loading deployment information from: $info_file"
        # Source the file safely
        while IFS='=' read -r key value; do
            if [[ "$key" =~ ^[A-Z_]+$ ]] && [[ ! "$key" =~ ^# ]]; then
                export "$key"="$value"
            fi
        done < <(grep -E '^[A-Z_]+=' "$info_file")
    fi
    
    log_info "Environment configuration:"
    log_info "  AWS Region: $AWS_REGION"
    log_info "  AWS Account ID: $AWS_ACCOUNT_ID"
    log_info "  Project Name: $PROJECT_NAME"
    log_info "  S3 Bucket: $S3_BUCKET"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_warning "This will permanently delete the following resources:"
    log_warning "  - Lambda function: ${PROJECT_NAME}-email-processor"
    log_warning "  - IAM role: ${PROJECT_NAME}-lambda-role"
    log_warning "  - IAM policy: ${PROJECT_NAME}-ses-policy"
    log_warning "  - EventBridge bus: ${PROJECT_NAME}-event-bus"
    log_warning "  - EventBridge rules and targets"
    log_warning "  - SES email template: NotificationTemplate"
    log_warning "  - S3 bucket: ${S3_BUCKET}"
    log_warning "  - CloudWatch alarms and log groups"
    
    if [[ "$KEEP_EMAILS" == "false" ]]; then
        log_warning "  - SES verified email addresses (unless --keep-emails is specified)"
    fi
    
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
}

# Execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] $description"
        log_info "[DRY-RUN] Command: $cmd"
    else
        log_info "$description"
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || log_warning "Command failed, continuing..."
        else
            eval "$cmd"
        fi
    fi
}

# Check if resource exists
resource_exists() {
    local check_cmd="$1"
    local resource_name="$2"
    
    if eval "$check_cmd" &> /dev/null; then
        log_info "Found $resource_name"
        return 0
    else
        log_warning "$resource_name not found, skipping"
        return 1
    fi
}

# Remove Lambda function and related resources
remove_lambda_resources() {
    log_info "Removing Lambda function and related resources..."
    
    local function_name="${PROJECT_NAME}-email-processor"
    
    if resource_exists "aws lambda get-function --function-name $function_name" "Lambda function: $function_name"; then
        # Remove Lambda permissions first
        local permissions=(
            "eventbridge-invoke-${PROJECT_NAME}"
            "priority-invoke-${PROJECT_NAME}"
            "scheduled-invoke-${PROJECT_NAME}"
        )
        
        for permission in "${permissions[@]}"; do
            local remove_permission_cmd="aws lambda remove-permission --function-name $function_name --statement-id $permission"
            execute_command "$remove_permission_cmd" "Removing Lambda permission: $permission" true
        done
        
        # Delete Lambda function
        local delete_function_cmd="aws lambda delete-function --function-name $function_name"
        execute_command "$delete_function_cmd" "Deleting Lambda function: $function_name"
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "Lambda resources removed"
    fi
}

# Remove IAM resources
remove_iam_resources() {
    log_info "Removing IAM role and policies..."
    
    local role_name="${PROJECT_NAME}-lambda-role"
    local policy_name="${PROJECT_NAME}-ses-policy"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
    
    if resource_exists "aws iam get-role --role-name $role_name" "IAM role: $role_name"; then
        # Detach policies from role
        local basic_policy_arn="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        
        local detach_basic_cmd="aws iam detach-role-policy --role-name $role_name --policy-arn $basic_policy_arn"
        execute_command "$detach_basic_cmd" "Detaching basic execution policy from role" true
        
        local detach_ses_cmd="aws iam detach-role-policy --role-name $role_name --policy-arn $policy_arn"
        execute_command "$detach_ses_cmd" "Detaching SES policy from role" true
        
        # Delete IAM role
        local delete_role_cmd="aws iam delete-role --role-name $role_name"
        execute_command "$delete_role_cmd" "Deleting IAM role: $role_name"
    fi
    
    if resource_exists "aws iam get-policy --policy-arn $policy_arn" "IAM policy: $policy_name"; then
        # Delete IAM policy
        local delete_policy_cmd="aws iam delete-policy --policy-arn $policy_arn"
        execute_command "$delete_policy_cmd" "Deleting IAM policy: $policy_name"
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "IAM resources removed"
    fi
}

# Remove EventBridge resources
remove_eventbridge_resources() {
    log_info "Removing EventBridge resources..."
    
    local event_bus_name="${PROJECT_NAME}-event-bus"
    local rules=("${PROJECT_NAME}-email-rule" "${PROJECT_NAME}-priority-rule")
    local scheduled_rule="${PROJECT_NAME}-daily-report"
    
    # Remove targets and rules from custom event bus
    for rule in "${rules[@]}"; do
        if resource_exists "aws events describe-rule --event-bus-name $event_bus_name --name $rule" "EventBridge rule: $rule"; then
            local remove_targets_cmd="aws events remove-targets --event-bus-name $event_bus_name --rule $rule --ids 1"
            execute_command "$remove_targets_cmd" "Removing targets from rule: $rule" true
            
            local delete_rule_cmd="aws events delete-rule --event-bus-name $event_bus_name --name $rule"
            execute_command "$delete_rule_cmd" "Deleting rule: $rule"
        fi
    done
    
    # Remove scheduled rule (on default bus)
    if resource_exists "aws events describe-rule --name $scheduled_rule" "Scheduled rule: $scheduled_rule"; then
        local remove_scheduled_targets_cmd="aws events remove-targets --rule $scheduled_rule --ids 1"
        execute_command "$remove_scheduled_targets_cmd" "Removing targets from scheduled rule" true
        
        local delete_scheduled_rule_cmd="aws events delete-rule --name $scheduled_rule"
        execute_command "$delete_scheduled_rule_cmd" "Deleting scheduled rule: $scheduled_rule"
    fi
    
    # Delete custom event bus
    if resource_exists "aws events describe-event-bus --name $event_bus_name" "EventBridge bus: $event_bus_name"; then
        local delete_bus_cmd="aws events delete-event-bus --name $event_bus_name"
        execute_command "$delete_bus_cmd" "Deleting EventBridge bus: $event_bus_name"
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "EventBridge resources removed"
    fi
}

# Remove SES resources
remove_ses_resources() {
    log_info "Removing SES resources..."
    
    local template_name="NotificationTemplate"
    
    if resource_exists "aws ses get-template --template-name $template_name --region $AWS_REGION" "SES template: $template_name"; then
        local delete_template_cmd="aws ses delete-template --template-name $template_name --region $AWS_REGION"
        execute_command "$delete_template_cmd" "Deleting SES template: $template_name"
    fi
    
    if [[ "$KEEP_EMAILS" == "false" ]]; then
        if [[ -n "${EMAIL_SENDER:-}" ]]; then
            log_info "Removing verified sender email: $EMAIL_SENDER"
            local delete_sender_cmd="aws ses delete-identity --identity $EMAIL_SENDER --region $AWS_REGION"
            execute_command "$delete_sender_cmd" "Removing sender email verification" true
        fi
        
        if [[ -n "${EMAIL_RECIPIENT:-}" ]]; then
            log_info "Removing verified recipient email: $EMAIL_RECIPIENT"
            local delete_recipient_cmd="aws ses delete-identity --identity $EMAIL_RECIPIENT --region $AWS_REGION"
            execute_command "$delete_recipient_cmd" "Removing recipient email verification" true
        fi
    else
        log_info "Keeping verified email addresses (--keep-emails specified)"
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "SES resources removed"
    fi
}

# Remove CloudWatch resources
remove_cloudwatch_resources() {
    log_info "Removing CloudWatch resources..."
    
    local alarms=("${PROJECT_NAME}-lambda-errors" "${PROJECT_NAME}-ses-bounces")
    local log_group="/aws/lambda/${PROJECT_NAME}-email-processor"
    
    # Delete CloudWatch alarms
    for alarm in "${alarms[@]}"; do
        if resource_exists "aws cloudwatch describe-alarms --alarm-names $alarm" "CloudWatch alarm: $alarm"; then
            local delete_alarm_cmd="aws cloudwatch delete-alarms --alarm-names $alarm"
            execute_command "$delete_alarm_cmd" "Deleting CloudWatch alarm: $alarm"
        fi
    done
    
    # Delete CloudWatch log group
    if resource_exists "aws logs describe-log-groups --log-group-name-prefix $log_group" "CloudWatch log group: $log_group"; then
        local delete_log_group_cmd="aws logs delete-log-group --log-group-name $log_group"
        execute_command "$delete_log_group_cmd" "Deleting CloudWatch log group: $log_group"
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "CloudWatch resources removed"
    fi
}

# Remove S3 resources
remove_s3_resources() {
    log_info "Removing S3 resources..."
    
    if resource_exists "aws s3 ls s3://$S3_BUCKET" "S3 bucket: $S3_BUCKET"; then
        # Empty bucket first
        local empty_bucket_cmd="aws s3 rm s3://$S3_BUCKET --recursive"
        execute_command "$empty_bucket_cmd" "Emptying S3 bucket: $S3_BUCKET" true
        
        # Delete bucket
        local delete_bucket_cmd="aws s3 rb s3://$S3_BUCKET"
        execute_command "$delete_bucket_cmd" "Deleting S3 bucket: $S3_BUCKET"
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "S3 resources removed"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-info-${PROJECT_NAME}.txt"
        "/tmp/lambda-trust-policy-${PROJECT_NAME}.json"
        "/tmp/ses-permissions-policy-${PROJECT_NAME}.json"
        "/tmp/email-template-${PROJECT_NAME}.json"
        "/tmp/email_processor-${PROJECT_NAME}.py"
        "/tmp/function-${PROJECT_NAME}.zip"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "false" ]]; then
                rm -f "$file"
                log_info "Removed local file: $file"
            else
                log_info "[DRY-RUN] Would remove local file: $file"
            fi
        fi
    done
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "Local files cleaned up"
    fi
}

# Verify resources are deleted
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_info "Verifying resource cleanup..."
    
    local verification_failed=false
    
    # Check Lambda function
    if aws lambda get-function --function-name "${PROJECT_NAME}-email-processor" &> /dev/null; then
        log_warning "Lambda function still exists"
        verification_failed=true
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${PROJECT_NAME}-lambda-role" &> /dev/null; then
        log_warning "IAM role still exists"
        verification_failed=true
    fi
    
    # Check EventBridge bus
    if aws events describe-event-bus --name "${PROJECT_NAME}-event-bus" &> /dev/null; then
        log_warning "EventBridge bus still exists"
        verification_failed=true
    fi
    
    # Check S3 bucket
    if aws s3 ls "s3://${S3_BUCKET}" &> /dev/null; then
        log_warning "S3 bucket still exists"
        verification_failed=true
    fi
    
    if [[ "$verification_failed" == "true" ]]; then
        log_warning "Some resources may not have been completely removed"
        log_info "You may need to check and remove them manually"
    else
        log_success "All resources successfully removed"
    fi
}

# Main cleanup function
main() {
    log_info "Starting cleanup of automated email notification system..."
    log_info "================================================"
    
    check_prerequisites
    setup_environment
    confirm_destruction
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY-RUN mode enabled. No resources will be deleted."
    fi
    
    # Remove resources in reverse order of creation
    remove_lambda_resources
    remove_eventbridge_resources
    remove_cloudwatch_resources
    remove_ses_resources
    remove_iam_resources
    remove_s3_resources
    cleanup_local_files
    verify_cleanup
    
    log_success "================================================"
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "Cleanup completed successfully!"
        log_success "All resources for project '$PROJECT_NAME' have been removed."
    else
        log_info "DRY-RUN completed. No resources were actually deleted."
    fi
}

# Handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Cleanup failed with exit code: $exit_code"
        log_info "Check the error messages above for details."
        log_info "Some resources may still exist and need manual cleanup."
    fi
    exit $exit_code
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"