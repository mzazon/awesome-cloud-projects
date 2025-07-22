#!/bin/bash

# AWS Business Continuity Testing Framework Cleanup Script
# This script removes all resources created by the BC testing framework

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure'."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load configuration
load_configuration() {
    log "Loading deployment configuration..."
    
    if [ -f ".bc-deployment-config" ]; then
        source .bc-deployment-config
        log "Configuration loaded from .bc-deployment-config"
        log "Project ID: ${BC_PROJECT_ID}"
        log "AWS Region: ${AWS_REGION}"
        log "Account ID: ${AWS_ACCOUNT_ID}"
    else
        warning "Configuration file .bc-deployment-config not found"
        log "Attempting to discover resources..."
        
        # Try to detect region and account
        export AWS_REGION=$(aws configure get region || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Try to find project ID from existing resources
        BC_PROJECT_ID=$(aws lambda list-functions \
            --query 'Functions[?starts_with(FunctionName, `bc-test-orchestrator-`)].FunctionName' \
            --output text | sed 's/bc-test-orchestrator-//' | head -n1)
        
        if [ -z "$BC_PROJECT_ID" ]; then
            error "Unable to determine project ID. Manual cleanup may be required."
            exit 1
        fi
        
        export BC_PROJECT_ID
        export BC_FRAMEWORK_NAME="business-continuity-${BC_PROJECT_ID}"
        export AUTOMATION_ROLE_NAME="BCTestingRole-${BC_PROJECT_ID}"
        export TEST_RESULTS_BUCKET="bc-testing-results-${BC_PROJECT_ID}"
        
        log "Discovered Project ID: ${BC_PROJECT_ID}"
    fi
}

# Function to confirm cleanup
confirm_cleanup() {
    echo ""
    warning "This will permanently delete all Business Continuity Testing resources."
    echo "Resources to be deleted:"
    echo "- IAM Role: ${AUTOMATION_ROLE_NAME}"
    echo "- S3 Bucket: ${TEST_RESULTS_BUCKET} (and all contents)"
    echo "- Lambda Function: bc-test-orchestrator-${BC_PROJECT_ID}"
    echo "- SNS Topic: bc-alerts-${BC_PROJECT_ID}"
    echo "- Systems Manager Documents: BC-*-${BC_PROJECT_ID}"
    echo "- EventBridge Rules: bc-*-${BC_PROJECT_ID}"
    echo "- CloudWatch Dashboard: BC-Testing-${BC_PROJECT_ID}"
    echo ""
    
    # Check for --force flag
    if [[ "$1" == "--force" ]]; then
        log "Force flag detected, proceeding with cleanup..."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
}

# Function to delete EventBridge rules and targets
delete_eventbridge_schedules() {
    log "Deleting EventBridge schedules..."
    
    local rules=(
        "bc-daily-tests-${BC_PROJECT_ID}"
        "bc-weekly-tests-${BC_PROJECT_ID}" 
        "bc-monthly-tests-${BC_PROJECT_ID}"
        "bc-compliance-reporting-${BC_PROJECT_ID}"
    )
    
    for rule in "${rules[@]}"; do
        if aws events describe-rule --name "$rule" &> /dev/null; then
            log "Deleting EventBridge rule: $rule"
            
            # Remove targets first
            aws events remove-targets --rule "$rule" --ids 1 2>/dev/null || true
            
            # Delete the rule
            aws events delete-rule --name "$rule" 2>/dev/null || true
            
            success "Deleted EventBridge rule: $rule"
        else
            warning "EventBridge rule not found: $rule"
        fi
    done
    
    success "EventBridge schedules cleanup completed"
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    local functions=(
        "bc-test-orchestrator-${BC_PROJECT_ID}"
        "bc-compliance-reporter-${BC_PROJECT_ID}"
        "bc-manual-test-executor-${BC_PROJECT_ID}"
    )
    
    for function in "${functions[@]}"; do
        if aws lambda get-function --function-name "$function" &> /dev/null; then
            log "Deleting Lambda function: $function"
            aws lambda delete-function --function-name "$function"
            success "Deleted Lambda function: $function"
        else
            warning "Lambda function not found: $function"
        fi
    done
    
    success "Lambda functions cleanup completed"
}

# Function to delete Systems Manager automation documents
delete_ssm_documents() {
    log "Deleting Systems Manager automation documents..."
    
    local documents=(
        "BC-BackupValidation-${BC_PROJECT_ID}"
        "BC-DatabaseRecovery-${BC_PROJECT_ID}"
        "BC-ApplicationFailover-${BC_PROJECT_ID}"
    )
    
    for doc in "${documents[@]}"; do
        if aws ssm describe-document --name "$doc" &> /dev/null; then
            log "Deleting SSM document: $doc"
            aws ssm delete-document --name "$doc" --force
            success "Deleted SSM document: $doc"
        else
            warning "SSM document not found: $doc"
        fi
    done
    
    success "Systems Manager documents cleanup completed"
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket and contents..."
    
    if aws s3api head-bucket --bucket "${TEST_RESULTS_BUCKET}" 2>/dev/null; then
        log "Emptying S3 bucket: ${TEST_RESULTS_BUCKET}"
        
        # Delete all objects and versions
        aws s3 rm "s3://${TEST_RESULTS_BUCKET}" --recursive 2>/dev/null || true
        
        # Delete all object versions (if versioning was enabled)
        aws s3api delete-objects \
            --bucket "${TEST_RESULTS_BUCKET}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${TEST_RESULTS_BUCKET}" \
                --output json \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" \
            2>/dev/null || true
        
        # Delete all delete markers
        aws s3api delete-objects \
            --bucket "${TEST_RESULTS_BUCKET}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${TEST_RESULTS_BUCKET}" \
                --output json \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" \
            2>/dev/null || true
        
        # Delete the bucket
        log "Deleting S3 bucket: ${TEST_RESULTS_BUCKET}"
        aws s3api delete-bucket --bucket "${TEST_RESULTS_BUCKET}"
        
        success "Deleted S3 bucket: ${TEST_RESULTS_BUCKET}"
    else
        warning "S3 bucket not found: ${TEST_RESULTS_BUCKET}"
    fi
    
    success "S3 bucket cleanup completed"
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete dashboard
    local dashboard_name="BC-Testing-${BC_PROJECT_ID}"
    if aws cloudwatch list-dashboards --dashboard-name-prefix "$dashboard_name" --query 'DashboardEntries[0].DashboardName' --output text | grep -q "$dashboard_name"; then
        log "Deleting CloudWatch dashboard: $dashboard_name"
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name"
        success "Deleted CloudWatch dashboard: $dashboard_name"
    else
        warning "CloudWatch dashboard not found: $dashboard_name"
    fi
    
    # Delete log groups
    local log_groups=(
        "/aws/lambda/bc-test-orchestrator-${BC_PROJECT_ID}"
        "/aws/lambda/bc-compliance-reporter-${BC_PROJECT_ID}"
        "/aws/lambda/bc-manual-test-executor-${BC_PROJECT_ID}"
    )
    
    for log_group in "${log_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text | grep -q "$log_group"; then
            log "Deleting CloudWatch log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group"
            success "Deleted CloudWatch log group: $log_group"
        else
            warning "CloudWatch log group not found: $log_group"
        fi
    done
    
    success "CloudWatch resources cleanup completed"
}

# Function to delete SNS topic
delete_sns_topic() {
    log "Deleting SNS topic..."
    
    local topic_name="bc-alerts-${BC_PROJECT_ID}"
    local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${topic_name}"
    
    if aws sns get-topic-attributes --topic-arn "$topic_arn" &> /dev/null; then
        log "Deleting SNS topic: $topic_name"
        aws sns delete-topic --topic-arn "$topic_arn"
        success "Deleted SNS topic: $topic_name"
    else
        warning "SNS topic not found: $topic_name"
    fi
    
    success "SNS topic cleanup completed"
}

# Function to delete IAM role and policies
delete_iam_role() {
    log "Deleting IAM role and policies..."
    
    if aws iam get-role --role-name "${AUTOMATION_ROLE_NAME}" &> /dev/null; then
        log "Deleting IAM role: ${AUTOMATION_ROLE_NAME}"
        
        # Delete inline policies
        local policies=$(aws iam list-role-policies --role-name "${AUTOMATION_ROLE_NAME}" --query 'PolicyNames[]' --output text)
        for policy in $policies; do
            log "Deleting inline policy: $policy"
            aws iam delete-role-policy --role-name "${AUTOMATION_ROLE_NAME}" --policy-name "$policy"
        done
        
        # Detach managed policies
        local attached_policies=$(aws iam list-attached-role-policies --role-name "${AUTOMATION_ROLE_NAME}" --query 'AttachedPolicies[].PolicyArn' --output text)
        for policy_arn in $attached_policies; do
            log "Detaching managed policy: $policy_arn"
            aws iam detach-role-policy --role-name "${AUTOMATION_ROLE_NAME}" --policy-arn "$policy_arn"
        done
        
        # Delete the role
        aws iam delete-role --role-name "${AUTOMATION_ROLE_NAME}"
        success "Deleted IAM role: ${AUTOMATION_ROLE_NAME}"
    else
        warning "IAM role not found: ${AUTOMATION_ROLE_NAME}"
    fi
    
    success "IAM role cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local configuration files..."
    
    local files=(
        ".bc-deployment-config"
        "manual-test-result.json"
        "response.json"
    )
    
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            log "Removing local file: $file"
            rm -f "$file"
        fi
    done
    
    success "Local files cleanup completed"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup completion..."
    
    local cleanup_issues=0
    
    # Check Lambda functions
    local lambda_count=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `'${BC_PROJECT_ID}'`)].FunctionName' \
        --output text | wc -w)
    if [ "$lambda_count" -gt 0 ]; then
        warning "Found $lambda_count remaining Lambda functions with project ID"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check SSM documents
    local ssm_count=$(aws ssm list-documents \
        --filters Key=Name,Values=BC-*-${BC_PROJECT_ID} \
        --query 'length(DocumentIdentifiers)')
    if [ "$ssm_count" -gt 0 ]; then
        warning "Found $ssm_count remaining SSM documents"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "${TEST_RESULTS_BUCKET}" 2>/dev/null; then
        warning "S3 bucket still exists: ${TEST_RESULTS_BUCKET}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check EventBridge rules
    local eventbridge_count=$(aws events list-rules \
        --name-prefix "bc-" \
        --query 'Rules[?contains(Name, `'${BC_PROJECT_ID}'`)].Name' \
        --output text | wc -w)
    if [ "$eventbridge_count" -gt 0 ]; then
        warning "Found $eventbridge_count remaining EventBridge rules"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${AUTOMATION_ROLE_NAME}" &> /dev/null; then
        warning "IAM role still exists: ${AUTOMATION_ROLE_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ "$cleanup_issues" -eq 0 ]; then
        success "Cleanup validation completed successfully - no remaining resources found"
    else
        warning "Cleanup validation found $cleanup_issues potential issues"
        warning "Some resources may require manual cleanup"
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "Project ID: ${BC_PROJECT_ID}"
    echo "AWS Region: ${AWS_REGION}"
    echo "Account ID: ${AWS_ACCOUNT_ID}"
    echo ""
    echo "Resources Deleted:"
    echo "- IAM Role: ${AUTOMATION_ROLE_NAME}"
    echo "- S3 Bucket: ${TEST_RESULTS_BUCKET}"
    echo "- Lambda Functions: bc-*-${BC_PROJECT_ID}"
    echo "- SNS Topic: bc-alerts-${BC_PROJECT_ID}"
    echo "- Systems Manager Documents: BC-*-${BC_PROJECT_ID}"
    echo "- EventBridge Rules: bc-*-${BC_PROJECT_ID}"
    echo "- CloudWatch Dashboard: BC-Testing-${BC_PROJECT_ID}"
    echo "- CloudWatch Log Groups"
    echo "- Local configuration files"
    echo ""
    echo "Manual Cleanup (if needed):"
    echo "- Review AWS Console for any remaining resources"
    echo "- Check CloudWatch Logs for any orphaned log groups"
    echo "- Verify SNS subscriptions have been removed"
}

# Function to handle errors during cleanup
cleanup_error_handler() {
    error "Cleanup failed on line $LINENO. Exit code: $?"
    warning "Partial cleanup may have occurred. Please review AWS Console for remaining resources."
    warning "You may need to manually delete some resources."
    exit 1
}

# Main cleanup function
main() {
    log "Starting AWS Business Continuity Testing Framework cleanup..."
    
    # Check for help
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "Usage: $0 [--force]"
        echo ""
        echo "Options:"
        echo "  --force    Skip confirmation prompt"
        echo "  --help     Show this help message"
        exit 0
    fi
    
    # Run cleanup steps
    check_prerequisites
    load_configuration
    confirm_cleanup "$1"
    
    log "Starting resource cleanup..."
    delete_eventbridge_schedules
    delete_lambda_functions
    delete_ssm_documents
    delete_cloudwatch_resources
    delete_sns_topic
    delete_s3_bucket
    delete_iam_role
    cleanup_local_files
    
    # Validate cleanup
    if validate_cleanup; then
        display_cleanup_summary
        success "AWS Business Continuity Testing Framework cleanup completed successfully!"
    else
        warning "Cleanup completed with some issues. Manual review recommended."
    fi
    
    success "Total cleanup time: $SECONDS seconds"
}

# Trap errors
trap cleanup_error_handler ERR

# Run main function
main "$@"