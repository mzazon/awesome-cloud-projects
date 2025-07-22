#!/bin/bash

# Destroy script for Multi-Branch CI/CD Pipelines with CodePipeline
# This script safely removes all resources created by the deploy script

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log "Running in dry-run mode - no resources will be deleted"
fi

# Check if force mode is enabled
FORCE=false
if [[ "${1:-}" == "--force" ]] || [[ "${2:-}" == "--force" ]]; then
    FORCE=true
    log "Force mode enabled - will skip confirmation prompts"
fi

# Function to execute command with dry-run support
execute_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $*"
    else
        "$@"
    fi
}

# Load configuration from deployment
load_configuration() {
    if [[ ! -f .deployment-config ]]; then
        error "Configuration file .deployment-config not found!"
        error "Please run this script from the same directory where deploy.sh was executed."
        exit 1
    fi
    
    log "Loading deployment configuration..."
    source .deployment-config
    
    # Validate required variables
    if [[ -z "${REPO_NAME:-}" ]] || [[ -z "${AWS_REGION:-}" ]]; then
        error "Invalid configuration file. Missing required variables."
        exit 1
    fi
    
    success "Configuration loaded successfully"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" ]]; then
        log "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo
    echo -e "${YELLOW}WARNING: This will permanently delete the following resources:${NC}"
    echo "  - CodeCommit Repository: ${REPO_NAME}"
    echo "  - All CodePipeline pipelines for repository: ${REPO_NAME}"
    echo "  - CodeBuild Project: ${CODEBUILD_PROJECT_NAME}"
    echo "  - Lambda Function: ${PIPELINE_MANAGER_FUNCTION}"
    echo "  - EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    echo "  - IAM Roles: ${PIPELINE_ROLE_NAME}, ${CODEBUILD_ROLE_NAME}, ${LAMBDA_ROLE_NAME}"
    echo "  - S3 Bucket: ${ARTIFACT_BUCKET} (and all contents)"
    echo "  - CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "  - SNS Topic: ${SNS_TOPIC_NAME}"
    echo "  - CloudWatch Alarms"
    echo
    echo -e "${RED}This action cannot be undone!${NC}"
    echo
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed by user"
}

# Delete all pipelines for the repository
delete_pipelines() {
    log "Deleting all pipelines for repository: ${REPO_NAME}..."
    
    # Get all pipelines that match the repository name
    PIPELINE_NAMES=$(aws codepipeline list-pipelines \
        --query "pipelines[?contains(name, '${REPO_NAME}')].name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$PIPELINE_NAMES" ]]; then
        for pipeline in $PIPELINE_NAMES; do
            log "Deleting pipeline: $pipeline"
            execute_cmd aws codepipeline delete-pipeline --name "$pipeline"
            success "Deleted pipeline: $pipeline"
        done
    else
        warning "No pipelines found for repository: ${REPO_NAME}"
    fi
}

# Delete EventBridge rules and targets
delete_eventbridge_rules() {
    log "Deleting EventBridge rules..."
    
    # Remove targets first
    if aws events list-targets-by-rule --rule "${EVENTBRIDGE_RULE_NAME}" &>/dev/null; then
        execute_cmd aws events remove-targets \
            --rule "${EVENTBRIDGE_RULE_NAME}" \
            --ids "1"
        success "Removed EventBridge targets"
    fi
    
    # Delete the rule
    if aws events describe-rule --name "${EVENTBRIDGE_RULE_NAME}" &>/dev/null; then
        execute_cmd aws events delete-rule --name "${EVENTBRIDGE_RULE_NAME}"
        success "Deleted EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
    else
        warning "EventBridge rule not found: ${EVENTBRIDGE_RULE_NAME}"
    fi
}

# Delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    if aws lambda get-function --function-name "${PIPELINE_MANAGER_FUNCTION}" &>/dev/null; then
        execute_cmd aws lambda delete-function --function-name "${PIPELINE_MANAGER_FUNCTION}"
        success "Deleted Lambda function: ${PIPELINE_MANAGER_FUNCTION}"
    else
        warning "Lambda function not found: ${PIPELINE_MANAGER_FUNCTION}"
    fi
}

# Delete CodeBuild project
delete_codebuild_project() {
    log "Deleting CodeBuild project..."
    
    if aws codebuild batch-get-projects --names "${CODEBUILD_PROJECT_NAME}" 2>/dev/null | grep -q "${CODEBUILD_PROJECT_NAME}"; then
        execute_cmd aws codebuild delete-project --name "${CODEBUILD_PROJECT_NAME}"
        success "Deleted CodeBuild project: ${CODEBUILD_PROJECT_NAME}"
    else
        warning "CodeBuild project not found: ${CODEBUILD_PROJECT_NAME}"
    fi
}

# Delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    # Delete CodePipeline role
    if aws iam get-role --role-name "${PIPELINE_ROLE_NAME}" &>/dev/null; then
        log "Deleting CodePipeline role policies..."
        execute_cmd aws iam detach-role-policy \
            --role-name "${PIPELINE_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AWSCodePipelineFullAccess
        
        execute_cmd aws iam detach-role-policy \
            --role-name "${PIPELINE_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AWSCodeCommitFullAccess
        
        execute_cmd aws iam detach-role-policy \
            --role-name "${PIPELINE_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess
        
        execute_cmd aws iam delete-role --role-name "${PIPELINE_ROLE_NAME}"
        success "Deleted CodePipeline role: ${PIPELINE_ROLE_NAME}"
    else
        warning "CodePipeline role not found: ${PIPELINE_ROLE_NAME}"
    fi
    
    # Delete CodeBuild role
    if aws iam get-role --role-name "${CODEBUILD_ROLE_NAME}" &>/dev/null; then
        log "Deleting CodeBuild role policies..."
        execute_cmd aws iam detach-role-policy \
            --role-name "${CODEBUILD_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
        
        execute_cmd aws iam detach-role-policy \
            --role-name "${CODEBUILD_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
        
        execute_cmd aws iam delete-role --role-name "${CODEBUILD_ROLE_NAME}"
        success "Deleted CodeBuild role: ${CODEBUILD_ROLE_NAME}"
    else
        warning "CodeBuild role not found: ${CODEBUILD_ROLE_NAME}"
    fi
    
    # Delete Lambda role
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &>/dev/null; then
        log "Deleting Lambda role policies..."
        execute_cmd aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        execute_cmd aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AWSCodePipelineFullAccess
        
        execute_cmd aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AWSCodeBuildAdminAccess
        
        execute_cmd aws iam delete-role --role-name "${LAMBDA_ROLE_NAME}"
        success "Deleted Lambda role: ${LAMBDA_ROLE_NAME}"
    else
        warning "Lambda role not found: ${LAMBDA_ROLE_NAME}"
    fi
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name "${DASHBOARD_NAME}" &>/dev/null; then
        execute_cmd aws cloudwatch delete-dashboards --dashboard-names "${DASHBOARD_NAME}"
        success "Deleted CloudWatch dashboard: ${DASHBOARD_NAME}"
    else
        warning "CloudWatch dashboard not found: ${DASHBOARD_NAME}"
    fi
    
    # Delete CloudWatch alarms
    ALARM_NAME="PipelineFailure-${REPO_NAME}"
    if aws cloudwatch describe-alarms --alarm-names "${ALARM_NAME}" &>/dev/null; then
        execute_cmd aws cloudwatch delete-alarms --alarm-names "${ALARM_NAME}"
        success "Deleted CloudWatch alarm: ${ALARM_NAME}"
    else
        warning "CloudWatch alarm not found: ${ALARM_NAME}"
    fi
    
    # Delete SNS topic
    if [[ -n "${ALERT_TOPIC_ARN:-}" ]]; then
        if aws sns get-topic-attributes --topic-arn "${ALERT_TOPIC_ARN}" &>/dev/null; then
            execute_cmd aws sns delete-topic --topic-arn "${ALERT_TOPIC_ARN}"
            success "Deleted SNS topic: ${ALERT_TOPIC_ARN}"
        else
            warning "SNS topic not found: ${ALERT_TOPIC_ARN}"
        fi
    else
        warning "SNS topic ARN not found in configuration"
    fi
}

# Delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket and all contents..."
    
    if aws s3api head-bucket --bucket "${ARTIFACT_BUCKET}" &>/dev/null; then
        log "Emptying S3 bucket: ${ARTIFACT_BUCKET}"
        execute_cmd aws s3 rm "s3://${ARTIFACT_BUCKET}" --recursive
        
        log "Deleting S3 bucket: ${ARTIFACT_BUCKET}"
        execute_cmd aws s3 rb "s3://${ARTIFACT_BUCKET}"
        success "Deleted S3 bucket: ${ARTIFACT_BUCKET}"
    else
        warning "S3 bucket not found: ${ARTIFACT_BUCKET}"
    fi
}

# Delete CodeCommit repository
delete_codecommit_repo() {
    log "Deleting CodeCommit repository..."
    
    if aws codecommit get-repository --repository-name "${REPO_NAME}" &>/dev/null; then
        echo
        echo -e "${YELLOW}WARNING: This will permanently delete the CodeCommit repository and all its contents!${NC}"
        echo "Repository: ${REPO_NAME}"
        echo "This includes all branches, commits, and history."
        echo
        
        if [[ "$FORCE" == "false" ]]; then
            read -p "Are you sure you want to delete the repository? (type 'DELETE' to confirm): " repo_confirmation
            
            if [[ "$repo_confirmation" != "DELETE" ]]; then
                log "Repository deletion cancelled by user"
                return 0
            fi
        fi
        
        execute_cmd aws codecommit delete-repository --repository-name "${REPO_NAME}"
        success "Deleted CodeCommit repository: ${REPO_NAME}"
    else
        warning "CodeCommit repository not found: ${REPO_NAME}"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove deployment configuration
    if [[ -f .deployment-config ]]; then
        rm -f .deployment-config
        success "Removed deployment configuration file"
    fi
    
    # Remove any leftover Lambda function files
    if [[ -f pipeline-manager.py ]]; then
        rm -f pipeline-manager.py
        success "Removed pipeline-manager.py"
    fi
    
    if [[ -f pipeline-manager.zip ]]; then
        rm -f pipeline-manager.zip
        success "Removed pipeline-manager.zip"
    fi
}

# Verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local errors=0
    
    # Check CodeCommit repository
    if aws codecommit get-repository --repository-name "${REPO_NAME}" &>/dev/null; then
        error "CodeCommit repository still exists: ${REPO_NAME}"
        ((errors++))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "${PIPELINE_MANAGER_FUNCTION}" &>/dev/null; then
        error "Lambda function still exists: ${PIPELINE_MANAGER_FUNCTION}"
        ((errors++))
    fi
    
    # Check CodeBuild project
    if aws codebuild batch-get-projects --names "${CODEBUILD_PROJECT_NAME}" 2>/dev/null | grep -q "${CODEBUILD_PROJECT_NAME}"; then
        error "CodeBuild project still exists: ${CODEBUILD_PROJECT_NAME}"
        ((errors++))
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "${ARTIFACT_BUCKET}" &>/dev/null; then
        error "S3 bucket still exists: ${ARTIFACT_BUCKET}"
        ((errors++))
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name "${PIPELINE_ROLE_NAME}" &>/dev/null; then
        error "IAM role still exists: ${PIPELINE_ROLE_NAME}"
        ((errors++))
    fi
    
    if aws iam get-role --role-name "${CODEBUILD_ROLE_NAME}" &>/dev/null; then
        error "IAM role still exists: ${CODEBUILD_ROLE_NAME}"
        ((errors++))
    fi
    
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &>/dev/null; then
        error "IAM role still exists: ${LAMBDA_ROLE_NAME}"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        success "All resources have been successfully deleted"
    else
        error "Some resources may still exist. Please check the AWS console and delete manually if needed."
        return 1
    fi
}

# Main destruction function
main() {
    log "Starting multi-branch CI/CD pipeline destruction..."
    
    # Prerequisites check
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    load_configuration
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_pipelines
    delete_eventbridge_rules
    delete_lambda_function
    delete_codebuild_project
    delete_cloudwatch_resources
    delete_iam_roles
    delete_s3_bucket
    delete_codecommit_repo
    cleanup_temp_files
    
    # Verify deletion
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for AWS eventual consistency..."
        sleep 10
        verify_deletion
    fi
    
    success "Multi-branch CI/CD pipeline destruction completed!"
    
    echo
    echo "=== Destruction Summary ==="
    echo "All resources related to repository '${REPO_NAME}' have been removed."
    echo "Region: ${AWS_REGION}"
    echo
    echo "The following resources were deleted:"
    echo "  ✓ CodeCommit Repository: ${REPO_NAME}"
    echo "  ✓ All CodePipeline pipelines"
    echo "  ✓ CodeBuild Project: ${CODEBUILD_PROJECT_NAME}"
    echo "  ✓ Lambda Function: ${PIPELINE_MANAGER_FUNCTION}"
    echo "  ✓ EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    echo "  ✓ IAM Roles (3 roles)"
    echo "  ✓ S3 Bucket: ${ARTIFACT_BUCKET}"
    echo "  ✓ CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "  ✓ CloudWatch Alarms"
    echo "  ✓ SNS Topic for alerts"
    echo "  ✓ Configuration files"
    echo
    echo "Thank you for using the multi-branch CI/CD pipeline solution!"
}

# Execute main function
main "$@"