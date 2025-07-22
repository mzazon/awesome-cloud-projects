#!/bin/bash

# Destroy script for Automated Testing Strategies for Infrastructure as Code
# This script removes all AWS resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/iac-testing-destroy-$(date +%Y%m%d-%H%M%S).log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "$LOG_FILE"
}

# Cleanup function for error handling
cleanup_on_error() {
    print_error "Cleanup failed. Check log file: $LOG_FILE"
    print_warning "Some resources may not have been deleted. Please check AWS Console."
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Banner
echo -e "${RED}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              IaC Testing Pipeline Cleanup                     ║"
echo "║        Removing All Infrastructure Testing Resources           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

log "Starting IaC testing pipeline cleanup"

# Load environment variables
if [ -f "$SCRIPT_DIR/.env" ]; then
    print_info "Loading environment from .env file..."
    source "$SCRIPT_DIR/.env"
    log "Loaded environment variables from .env"
else
    print_warning "No .env file found. Using current AWS configuration."
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed and no .env file found"
        exit 1
    fi
    
    # Try to get current configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured and no .env file found"
        exit 1
    fi
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Prompt for project details if not available
    if [ -z "$PROJECT_NAME" ]; then
        echo -e "${YELLOW}Enter the project name (e.g., iac-testing-abc12345):${NC}"
        read -r PROJECT_NAME
        export PROJECT_NAME
    fi
    
    if [ -z "$BUCKET_NAME" ]; then
        echo -e "${YELLOW}Enter the S3 bucket name (e.g., iac-testing-artifacts-abc12345):${NC}"
        read -r BUCKET_NAME
        export BUCKET_NAME
    fi
    
    if [ -z "$REPOSITORY_NAME" ]; then
        echo -e "${YELLOW}Enter the CodeCommit repository name (e.g., iac-testing-repo-abc12345):${NC}"
        read -r REPOSITORY_NAME
        export REPOSITORY_NAME
    fi
fi

# Validate required variables
if [ -z "$PROJECT_NAME" ] || [ -z "$BUCKET_NAME" ] || [ -z "$REPOSITORY_NAME" ] || [ -z "$AWS_REGION" ] || [ -z "$AWS_ACCOUNT_ID" ]; then
    print_error "Missing required environment variables"
    echo "Required: PROJECT_NAME, BUCKET_NAME, REPOSITORY_NAME, AWS_REGION, AWS_ACCOUNT_ID"
    exit 1
fi

log "Project Name: $PROJECT_NAME"
log "S3 Bucket: $BUCKET_NAME"
log "Repository: $REPOSITORY_NAME"
log "AWS Region: $AWS_REGION"
log "AWS Account: $AWS_ACCOUNT_ID"

# Confirmation prompt
echo -e "\n${YELLOW}⚠️  WARNING: This will permanently delete the following resources:${NC}"
echo "   • CodePipeline: ${PROJECT_NAME}-pipeline"
echo "   • CodeBuild Project: $PROJECT_NAME"
echo "   • S3 Bucket: $BUCKET_NAME (and all contents)"
echo "   • CodeCommit Repository: $REPOSITORY_NAME (and all code)"
echo "   • IAM Roles: ${PROJECT_NAME}-codebuild-role, ${PROJECT_NAME}-pipeline-role"
echo ""

# Interactive confirmation
read -p "Are you sure you want to delete these resources? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    print_info "Cleanup cancelled by user"
    exit 0
fi

# Additional confirmation for production-like environments
if [[ "$PROJECT_NAME" =~ (prod|production) ]]; then
    echo -e "\n${RED}⚠️  PRODUCTION WARNING: This appears to be a production environment!${NC}"
    read -p "Type 'DELETE PRODUCTION' to confirm: " -r
    if [[ "$REPLY" != "DELETE PRODUCTION" ]]; then
        print_info "Production cleanup cancelled"
        exit 0
    fi
fi

print_info "Beginning resource cleanup..."

# Function to safely run AWS commands with error handling
safe_aws_command() {
    local description="$1"
    shift
    local aws_command=("$@")
    
    print_info "Attempting: $description"
    
    if "${aws_command[@]}" &>> "$LOG_FILE"; then
        print_status "$description completed successfully"
        return 0
    else
        print_warning "$description failed or resource not found"
        return 1
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local check_command="$1"
    local resource_name="$2"
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ! eval "$check_command" &>/dev/null; then
            print_status "$resource_name deletion confirmed"
            return 0
        fi
        
        print_info "Waiting for $resource_name deletion... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    print_warning "$resource_name deletion timeout - may still be in progress"
    return 1
}

# 1. Stop any running pipeline executions
print_info "Stopping any running pipeline executions..."

PIPELINE_NAME="${PROJECT_NAME}-pipeline"
if aws codepipeline get-pipeline --name "$PIPELINE_NAME" &>/dev/null; then
    # Get running executions
    EXECUTIONS=$(aws codepipeline list-pipeline-executions \
        --pipeline-name "$PIPELINE_NAME" \
        --query 'pipelineExecutionSummaries[?status==`InProgress`].pipelineExecutionId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$EXECUTIONS" ]; then
        for execution in $EXECUTIONS; do
            print_info "Stopping pipeline execution: $execution"
            aws codepipeline stop-pipeline-execution \
                --pipeline-name "$PIPELINE_NAME" \
                --pipeline-execution-id "$execution" \
                --abandon true &>/dev/null || true
        done
        print_status "Stopped running pipeline executions"
    else
        print_info "No running pipeline executions found"
    fi
else
    print_info "Pipeline not found or already deleted"
fi

# 2. Stop any running CodeBuild builds
print_info "Stopping any running CodeBuild builds..."

if aws codebuild batch-get-projects --names "$PROJECT_NAME" &>/dev/null; then
    # Get running builds
    BUILDS=$(aws codebuild list-builds-for-project \
        --project-name "$PROJECT_NAME" \
        --query 'ids[0:10]' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$BUILDS" ] && [ "$BUILDS" != "None" ]; then
        for build in $BUILDS; do
            BUILD_STATUS=$(aws codebuild batch-get-builds \
                --ids "$build" \
                --query 'builds[0].buildStatus' \
                --output text 2>/dev/null || echo "")
            
            if [ "$BUILD_STATUS" = "IN_PROGRESS" ]; then
                print_info "Stopping build: $build"
                aws codebuild stop-build --id "$build" &>/dev/null || true
            fi
        done
        print_status "Stopped running builds"
    else
        print_info "No running builds found"
    fi
else
    print_info "CodeBuild project not found or already deleted"
fi

# 3. Delete CodePipeline
print_info "Deleting CodePipeline..."

safe_aws_command \
    "Delete CodePipeline" \
    aws codepipeline delete-pipeline --name "$PIPELINE_NAME"

# 4. Delete CodeBuild project
print_info "Deleting CodeBuild project..."

safe_aws_command \
    "Delete CodeBuild project" \
    aws codebuild delete-project --name "$PROJECT_NAME"

# 5. Clean up S3 bucket (empty and delete)
print_info "Cleaning up S3 bucket..."

if aws s3api head-bucket --bucket "$BUCKET_NAME" &>/dev/null; then
    print_info "Emptying S3 bucket: $BUCKET_NAME"
    
    # Delete all objects including versions
    aws s3api list-object-versions \
        --bucket "$BUCKET_NAME" \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' \
        --output text 2>/dev/null | \
    while read -r key version_id; do
        if [ -n "$key" ] && [ "$key" != "None" ]; then
            aws s3api delete-object \
                --bucket "$BUCKET_NAME" \
                --key "$key" \
                --version-id "$version_id" &>/dev/null || true
        fi
    done
    
    # Delete all delete markers
    aws s3api list-object-versions \
        --bucket "$BUCKET_NAME" \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
        --output text 2>/dev/null | \
    while read -r key version_id; do
        if [ -n "$key" ] && [ "$key" != "None" ]; then
            aws s3api delete-object \
                --bucket "$BUCKET_NAME" \
                --key "$key" \
                --version-id "$version_id" &>/dev/null || true
        fi
    done
    
    # Remove any remaining objects with simplified approach
    aws s3 rm s3://"$BUCKET_NAME" --recursive &>/dev/null || true
    
    print_status "S3 bucket emptied"
    
    # Delete the bucket
    safe_aws_command \
        "Delete S3 bucket" \
        aws s3 rb s3://"$BUCKET_NAME" --force
else
    print_info "S3 bucket not found or already deleted"
fi

# 6. Delete CodeCommit repository
print_info "Deleting CodeCommit repository..."

safe_aws_command \
    "Delete CodeCommit repository" \
    aws codecommit delete-repository --repository-name "$REPOSITORY_NAME"

# 7. Delete IAM policies and roles
print_info "Deleting IAM roles and policies..."

# Delete CodeBuild role
CODEBUILD_ROLE="${PROJECT_NAME}-codebuild-role"
if aws iam get-role --role-name "$CODEBUILD_ROLE" &>/dev/null; then
    # Delete attached policies
    safe_aws_command \
        "Delete CodeBuild role policy" \
        aws iam delete-role-policy \
            --role-name "$CODEBUILD_ROLE" \
            --policy-name "${PROJECT_NAME}-codebuild-policy"
    
    # Detach managed policies if any
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
        --role-name "$CODEBUILD_ROLE" \
        --query 'AttachedPolicies[].PolicyArn' \
        --output text 2>/dev/null || echo "")
    
    for policy_arn in $ATTACHED_POLICIES; do
        if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
            safe_aws_command \
                "Detach managed policy from CodeBuild role" \
                aws iam detach-role-policy \
                    --role-name "$CODEBUILD_ROLE" \
                    --policy-arn "$policy_arn"
        fi
    done
    
    # Delete the role
    safe_aws_command \
        "Delete CodeBuild role" \
        aws iam delete-role --role-name "$CODEBUILD_ROLE"
else
    print_info "CodeBuild role not found or already deleted"
fi

# Delete CodePipeline role
PIPELINE_ROLE="${PROJECT_NAME}-pipeline-role"
if aws iam get-role --role-name "$PIPELINE_ROLE" &>/dev/null; then
    # Delete attached policies
    safe_aws_command \
        "Delete CodePipeline role policy" \
        aws iam delete-role-policy \
            --role-name "$PIPELINE_ROLE" \
            --policy-name "${PROJECT_NAME}-pipeline-policy"
    
    # Detach managed policies if any
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
        --role-name "$PIPELINE_ROLE" \
        --query 'AttachedPolicies[].PolicyArn' \
        --output text 2>/dev/null || echo "")
    
    for policy_arn in $ATTACHED_POLICIES; do
        if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
            safe_aws_command \
                "Detach managed policy from CodePipeline role" \
                aws iam detach-role-policy \
                    --role-name "$PIPELINE_ROLE" \
                    --policy-arn "$policy_arn"
        fi
    done
    
    # Delete the role
    safe_aws_command \
        "Delete CodePipeline role" \
        aws iam delete-role --role-name "$PIPELINE_ROLE"
else
    print_info "CodePipeline role not found or already deleted"
fi

# 8. Clean up CloudWatch logs (optional)
print_info "Cleaning up CloudWatch logs..."

LOG_GROUP="/aws/codebuild/$PROJECT_NAME"
if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --query 'logGroups[0]' &>/dev/null; then
    safe_aws_command \
        "Delete CloudWatch log group" \
        aws logs delete-log-group --log-group-name "$LOG_GROUP"
else
    print_info "CloudWatch log group not found or already deleted"
fi

# 9. Clean up any orphaned stacks from integration tests
print_info "Checking for orphaned CloudFormation stacks..."

INTEGRATION_STACKS=$(aws cloudformation list-stacks \
    --query 'StackSummaries[?contains(StackName, `integration-test`) && StackStatus != `DELETE_COMPLETE`].StackName' \
    --output text 2>/dev/null || echo "")

if [ -n "$INTEGRATION_STACKS" ] && [ "$INTEGRATION_STACKS" != "None" ]; then
    for stack in $INTEGRATION_STACKS; do
        print_info "Deleting orphaned stack: $stack"
        aws cloudformation delete-stack --stack-name "$stack" &>/dev/null || true
    done
    print_status "Initiated cleanup of orphaned stacks"
else
    print_info "No orphaned integration test stacks found"
fi

# 10. Clean up local files
print_info "Cleaning up local files..."

if [ -f "$SCRIPT_DIR/.env" ]; then
    rm -f "$SCRIPT_DIR/.env"
    print_status "Removed environment file"
fi

# Clean up any temporary project directory
PROJECT_DIR="/tmp/$PROJECT_NAME"
if [ -d "$PROJECT_DIR" ]; then
    rm -rf "$PROJECT_DIR"
    print_status "Removed temporary project directory"
fi

# Wait for critical resources to be fully deleted
print_info "Waiting for resource deletion to complete..."

# Wait for IAM roles (they can take time to propagate)
wait_for_deletion \
    "aws iam get-role --role-name $CODEBUILD_ROLE" \
    "CodeBuild IAM role" || true

wait_for_deletion \
    "aws iam get-role --role-name $PIPELINE_ROLE" \
    "CodePipeline IAM role" || true

# Verify major resources are deleted
print_info "Verifying resource deletion..."

VERIFICATION_FAILED=false

# Check CodePipeline
if aws codepipeline get-pipeline --name "$PIPELINE_NAME" &>/dev/null; then
    print_warning "CodePipeline still exists: $PIPELINE_NAME"
    VERIFICATION_FAILED=true
fi

# Check CodeBuild
if aws codebuild batch-get-projects --names "$PROJECT_NAME" &>/dev/null; then
    print_warning "CodeBuild project still exists: $PROJECT_NAME"
    VERIFICATION_FAILED=true
fi

# Check S3 bucket
if aws s3api head-bucket --bucket "$BUCKET_NAME" &>/dev/null; then
    print_warning "S3 bucket still exists: $BUCKET_NAME"
    VERIFICATION_FAILED=true
fi

# Check CodeCommit repository
if aws codecommit get-repository --repository-name "$REPOSITORY_NAME" &>/dev/null; then
    print_warning "CodeCommit repository still exists: $REPOSITORY_NAME"
    VERIFICATION_FAILED=true
fi

# Display cleanup summary
echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════════╗"
echo "║                    Cleanup Summary                             ║"
echo "╚════════════════════════════════════════════════════════════════╝${NC}"

if [ "$VERIFICATION_FAILED" = true ]; then
    echo -e "\n${YELLOW}⚠️  Some resources may still exist:${NC}"
    echo "   • This can be normal due to AWS eventual consistency"
    echo "   • Some resources may take additional time to fully delete"
    echo "   • Check the AWS Console to verify complete deletion"
    echo "   • Re-run this script if resources still exist after 15 minutes"
else
    echo -e "\n${GREEN}✅ All resources successfully deleted:${NC}"
    echo "   • CodePipeline: ${PROJECT_NAME}-pipeline"
    echo "   • CodeBuild Project: $PROJECT_NAME"
    echo "   • S3 Bucket: $BUCKET_NAME"
    echo "   • CodeCommit Repository: $REPOSITORY_NAME"
    echo "   • IAM Roles and Policies"
    echo "   • CloudWatch Log Groups"
fi

echo -e "\n📊 ${BLUE}Cost Savings:${NC}"
echo "   • No more CodeBuild compute charges"
echo "   • No more CodePipeline monthly charges"
echo "   • No more S3 storage charges"
echo "   • No more CodeCommit charges"

echo -e "\n📋 ${BLUE}Next Steps:${NC}"
echo "   • Verify deletion in AWS Console if needed"
echo "   • Check CloudTrail for any remaining resource references"
echo "   • Review AWS billing for any lingering charges"

if [ "$VERIFICATION_FAILED" = true ]; then
    echo -e "\n${YELLOW}📝 Troubleshooting:${NC}"
    echo "   • Some AWS services have eventual consistency delays"
    echo "   • IAM resources can take up to 30 minutes to fully propagate"
    echo "   • Run: aws sts get-caller-identity to verify AWS access"
    echo "   • Check AWS Console for any resources in 'Deleting' state"
fi

echo -e "\n🔒 ${BLUE}Security Note:${NC}"
echo "   • All IAM roles and policies have been removed"
echo "   • All data in S3 has been permanently deleted"
echo "   • All source code in CodeCommit has been permanently deleted"

log "Cleanup process completed"

if [ "$VERIFICATION_FAILED" = true ]; then
    print_warning "Cleanup completed with warnings - check log file: $LOG_FILE"
    exit 1
else
    print_status "All resources successfully cleaned up!"
    echo -e "📝 Log file: $LOG_FILE"
fi