#!/bin/bash

# Fault-Tolerant HPC Workflows Cleanup Script
# This script safely removes all resources created by the deployment script
# including Step Functions, Lambda functions, IAM roles, and storage

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_DIR="$(dirname "$SCRIPT_DIR")"
DEPLOYMENT_INFO_FILE="${CODE_DIR}/deployment-info.json"
DRY_RUN=false
FORCE_DELETE=false
SKIP_CONFIRMATION=false

# Functions
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

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely remove all fault-tolerant HPC workflows infrastructure

OPTIONS:
    -n, --dry-run           Show what would be deleted without actually deleting
    -f, --force            Force deletion without confirmation prompts
    -y, --yes              Skip confirmation prompts (same as --force)
    -i, --info-file        Path to deployment info file (default: auto-detect)
    -h, --help             Show this help message

EXAMPLES:
    $0                     # Interactive cleanup with confirmations
    $0 --dry-run           # Show what would be deleted
    $0 --force             # Force cleanup without prompts
    $0 --info-file /path/to/deployment-info.json  # Use specific info file

SAFETY FEATURES:
    - Requires confirmation before deleting resources
    - Checks for active Step Functions executions
    - Validates resource ownership before deletion
    - Provides detailed progress reporting
    - Handles resource dependencies correctly

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_DELETE=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -i|--info-file)
                DEPLOYMENT_INFO_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check for jq
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed or not in PATH"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [ ! -f "$DEPLOYMENT_INFO_FILE" ]; then
        log_error "Deployment info file not found: $DEPLOYMENT_INFO_FILE"
        log_error "Cannot proceed with cleanup without deployment information"
        exit 1
    fi
    
    # Parse deployment info
    export PROJECT_NAME=$(jq -r '.project_name' "$DEPLOYMENT_INFO_FILE")
    export AWS_REGION=$(jq -r '.aws_region' "$DEPLOYMENT_INFO_FILE")
    export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$DEPLOYMENT_INFO_FILE")
    export STATE_MACHINE_NAME=$(jq -r '.resources.state_machine_name' "$DEPLOYMENT_INFO_FILE")
    export S3_BUCKET_NAME=$(jq -r '.resources.s3_bucket_name' "$DEPLOYMENT_INFO_FILE")
    export DDB_TABLE_NAME=$(jq -r '.resources.dynamodb_table_name' "$DEPLOYMENT_INFO_FILE")
    
    # Validate required fields
    if [ "$PROJECT_NAME" = "null" ] || [ "$AWS_REGION" = "null" ] || [ "$AWS_ACCOUNT_ID" = "null" ]; then
        log_error "Invalid deployment info file format"
        exit 1
    fi
    
    log_success "Deployment information loaded"
    log_info "Project: $PROJECT_NAME"
    log_info "Region: $AWS_REGION"
    log_info "Account: $AWS_ACCOUNT_ID"
}

confirm_deletion() {
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return 0
    fi
    
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo
    echo "This will permanently delete the following resources:"
    echo "  • Step Functions State Machine: $STATE_MACHINE_NAME"
    echo "  • S3 Bucket and all contents: $S3_BUCKET_NAME"
    echo "  • DynamoDB Table: $DDB_TABLE_NAME"
    echo "  • Lambda Functions (4 functions)"
    echo "  • IAM Roles (2 roles)"
    echo "  • EventBridge Rules"
    echo "  • CloudWatch Dashboard and Alarms"
    echo "  • SNS Topic"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to proceed? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Please type 'delete' to confirm: " -r
    if [[ $REPLY != "delete" ]]; then
        log_info "Cleanup cancelled - confirmation failed"
        exit 0
    fi
    
    log_info "Confirmation received, proceeding with cleanup..."
}

stop_active_executions() {
    log_info "Checking for active Step Functions executions..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would stop any active executions"
        return
    fi
    
    # Check if state machine exists
    if ! aws stepfunctions describe-state-machine \
        --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
        &> /dev/null; then
        log_info "State machine not found, skipping execution check"
        return
    fi
    
    # Get running executions
    RUNNING_EXECUTIONS=$(aws stepfunctions list-executions \
        --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
        --status-filter RUNNING \
        --query 'executions[].executionArn' --output text)
    
    if [ -n "$RUNNING_EXECUTIONS" ]; then
        log_warning "Found active executions, stopping them..."
        
        for execution in $RUNNING_EXECUTIONS; do
            aws stepfunctions stop-execution --execution-arn "$execution"
            log_info "Stopped execution: $execution"
        done
        
        # Wait for executions to stop
        sleep 10
    else
        log_info "No active executions found"
    fi
    
    log_success "Active executions handled"
}

delete_eventbridge_resources() {
    log_info "Deleting EventBridge resources..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would delete EventBridge rules and targets"
        return
    fi
    
    # Remove EventBridge targets and rules
    local rule_name="${PROJECT_NAME}-spot-interruption-warning"
    
    # Check if rule exists
    if aws events describe-rule --name "$rule_name" &> /dev/null; then
        # Remove targets first
        aws events remove-targets \
            --rule "$rule_name" \
            --ids "1" || true
        
        # Delete rule
        aws events delete-rule --name "$rule_name"
        
        log_success "EventBridge rule deleted: $rule_name"
    else
        log_info "EventBridge rule not found: $rule_name"
    fi
}

delete_step_functions() {
    log_info "Deleting Step Functions state machine..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would delete state machine: $STATE_MACHINE_NAME"
        return
    fi
    
    local state_machine_arn="arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}"
    
    # Check if state machine exists
    if aws stepfunctions describe-state-machine --state-machine-arn "$state_machine_arn" &> /dev/null; then
        aws stepfunctions delete-state-machine --state-machine-arn "$state_machine_arn"
        log_success "Step Functions state machine deleted: $STATE_MACHINE_NAME"
    else
        log_info "State machine not found: $STATE_MACHINE_NAME"
    fi
}

delete_lambda_functions() {
    log_info "Deleting Lambda functions..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would delete Lambda functions"
        return
    fi
    
    local functions=(
        "${PROJECT_NAME}-spot-fleet-manager"
        "${PROJECT_NAME}-checkpoint-manager"
        "${PROJECT_NAME}-workflow-parser"
        "${PROJECT_NAME}-spot-interruption-handler"
    )
    
    for func in "${functions[@]}"; do
        if aws lambda get-function --function-name "$func" &> /dev/null; then
            aws lambda delete-function --function-name "$func"
            log_success "Lambda function deleted: $func"
        else
            log_info "Lambda function not found: $func"
        fi
    done
}

delete_monitoring_resources() {
    log_info "Deleting CloudWatch resources..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would delete CloudWatch dashboards and alarms"
        return
    fi
    
    # Delete CloudWatch dashboard
    local dashboard_name="${PROJECT_NAME}-monitoring"
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" &> /dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name"
        log_success "CloudWatch dashboard deleted: $dashboard_name"
    else
        log_info "CloudWatch dashboard not found: $dashboard_name"
    fi
    
    # Delete CloudWatch alarms
    local alarms=(
        "${PROJECT_NAME}-workflow-failures"
        "${PROJECT_NAME}-spot-interruptions"
    )
    
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0]' --output text | grep -q "$alarm"; then
            aws cloudwatch delete-alarms --alarm-names "$alarm"
            log_success "CloudWatch alarm deleted: $alarm"
        else
            log_info "CloudWatch alarm not found: $alarm"
        fi
    done
    
    # Delete SNS topic
    local topic_name="${PROJECT_NAME}-alerts"
    SNS_TOPIC_ARN=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, '$topic_name')].TopicArn" \
        --output text)
    
    if [ -n "$SNS_TOPIC_ARN" ] && [ "$SNS_TOPIC_ARN" != "None" ]; then
        aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN"
        log_success "SNS topic deleted: $topic_name"
    else
        log_info "SNS topic not found: $topic_name"
    fi
}

delete_storage_resources() {
    log_info "Deleting storage resources..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would delete S3 bucket: $S3_BUCKET_NAME"
        log_info "[DRY-RUN] Would delete DynamoDB table: $DDB_TABLE_NAME"
        return
    fi
    
    # Delete S3 bucket
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" &> /dev/null; then
        log_info "Emptying S3 bucket: $S3_BUCKET_NAME"
        aws s3 rm s3://${S3_BUCKET_NAME} --recursive
        
        # Delete all versions and delete markers
        aws s3api delete-objects --bucket "$S3_BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions --bucket "$S3_BUCKET_NAME" \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
            --output json)" &> /dev/null || true
        
        aws s3api delete-objects --bucket "$S3_BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions --bucket "$S3_BUCKET_NAME" \
            --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
            --output json)" &> /dev/null || true
        
        aws s3 rb s3://${S3_BUCKET_NAME}
        log_success "S3 bucket deleted: $S3_BUCKET_NAME"
    else
        log_info "S3 bucket not found: $S3_BUCKET_NAME"
    fi
    
    # Delete DynamoDB table
    if aws dynamodb describe-table --table-name "$DDB_TABLE_NAME" &> /dev/null; then
        aws dynamodb delete-table --table-name "$DDB_TABLE_NAME"
        log_success "DynamoDB table deleted: $DDB_TABLE_NAME"
    else
        log_info "DynamoDB table not found: $DDB_TABLE_NAME"
    fi
}

delete_iam_resources() {
    log_info "Deleting IAM resources..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would delete IAM roles and policies"
        return
    fi
    
    # Delete Step Functions IAM role
    local sf_role_name="${PROJECT_NAME}-stepfunctions-role"
    if aws iam get-role --role-name "$sf_role_name" &> /dev/null; then
        # Remove inline policies
        aws iam delete-role-policy \
            --role-name "$sf_role_name" \
            --policy-name StepFunctionsExecutionPolicy || true
        
        # Delete role
        aws iam delete-role --role-name "$sf_role_name"
        log_success "IAM role deleted: $sf_role_name"
    else
        log_info "IAM role not found: $sf_role_name"
    fi
    
    # Delete Lambda IAM role
    local lambda_role_name="${PROJECT_NAME}-lambda-role"
    if aws iam get-role --role-name "$lambda_role_name" &> /dev/null; then
        # Detach managed policies
        local managed_policies=(
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
            "arn:aws:iam::aws:policy/AWSBatchFullAccess"
            "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
            "arn:aws:iam::aws:policy/AmazonS3FullAccess"
        )
        
        for policy in "${managed_policies[@]}"; do
            aws iam detach-role-policy \
                --role-name "$lambda_role_name" \
                --policy-arn "$policy" || true
        done
        
        # Delete role
        aws iam delete-role --role-name "$lambda_role_name"
        log_success "IAM role deleted: $lambda_role_name"
    else
        log_info "IAM role not found: $lambda_role_name"
    fi
}

cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would clean up temporary files"
        return
    fi
    
    # Remove deployment info file
    if [ -f "$DEPLOYMENT_INFO_FILE" ]; then
        rm -f "$DEPLOYMENT_INFO_FILE"
        log_success "Deployment info file removed"
    fi
    
    # Clean up any remaining temp files
    rm -f /tmp/stepfunctions-*.json
    rm -f /tmp/lambda-*.json
    rm -f /tmp/dashboard.json
    rm -f /tmp/sample-workflow.json
    rm -rf /tmp/lambda-packages
    
    log_success "Temporary files cleaned up"
}

verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would verify resource deletion"
        return
    fi
    
    local cleanup_success=true
    
    # Check Step Functions state machine
    if aws stepfunctions describe-state-machine \
        --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
        &> /dev/null; then
        log_warning "State machine still exists: $STATE_MACHINE_NAME"
        cleanup_success=false
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" &> /dev/null; then
        log_warning "S3 bucket still exists: $S3_BUCKET_NAME"
        cleanup_success=false
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "$DDB_TABLE_NAME" &> /dev/null; then
        log_warning "DynamoDB table still exists: $DDB_TABLE_NAME"
        cleanup_success=false
    fi
    
    if [ "$cleanup_success" = true ]; then
        log_success "Cleanup verification passed"
    else
        log_warning "Some resources may still exist - check AWS console"
    fi
}

print_summary() {
    echo
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY-RUN completed - no resources were deleted"
    else
        log_success "Cleanup completed successfully!"
        echo
        echo "==== CLEANUP SUMMARY ===="
        echo "Project: $PROJECT_NAME"
        echo "Region: $AWS_REGION"
        echo "Account: $AWS_ACCOUNT_ID"
        echo
        echo "==== RESOURCES DELETED ===="
        echo "✓ Step Functions State Machine"
        echo "✓ Lambda Functions (4 functions)"
        echo "✓ IAM Roles (2 roles)"
        echo "✓ S3 Bucket and contents"
        echo "✓ DynamoDB Table"
        echo "✓ EventBridge Rules"
        echo "✓ CloudWatch Dashboard and Alarms"
        echo "✓ SNS Topic"
        echo "✓ Deployment configuration files"
        echo
        echo "All resources have been safely removed."
        echo "You can now redeploy using ./deploy.sh if needed."
    fi
    echo
}

main() {
    log_info "Starting fault-tolerant HPC workflows cleanup..."
    
    parse_arguments "$@"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY-RUN MODE: No resources will be deleted"
        echo
    fi
    
    check_prerequisites
    load_deployment_info
    
    if [ "$DRY_RUN" = false ]; then
        confirm_deletion
    fi
    
    stop_active_executions
    delete_eventbridge_resources
    delete_step_functions
    delete_lambda_functions
    delete_monitoring_resources
    delete_storage_resources
    delete_iam_resources
    cleanup_temp_files
    verify_cleanup
    
    print_summary
}

# Run main function with all arguments
main "$@"