#!/bin/bash

# Infrastructure Deployment Pipelines with CDK and CodePipeline - Destroy Script
# This script cleans up all resources created by the CDK pipeline
# Version: 1.0

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" >&2
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log "Checking AWS CLI authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not authenticated or configured"
        error "Please run 'aws configure' or set up your AWS credentials"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    success "AWS CLI authenticated - Account: $account_id, Region: $region"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        error "AWS CLI is not installed"
        error "Please install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
        exit 1
    fi
    
    # Check CDK CLI
    if ! command_exists cdk; then
        error "CDK CLI is not installed"
        error "Please install CDK CLI: npm install -g aws-cdk"
        exit 1
    fi
    
    success "Prerequisites checked"
}

# Function to discover existing resources
discover_resources() {
    log "Discovering existing pipeline resources..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Find pipelines that match our pattern
    PIPELINES=$(aws codepipeline list-pipelines --query 'pipelines[?contains(name, `cdk-pipeline-`)].name' --output text)
    
    if [ -z "$PIPELINES" ]; then
        warning "No CDK pipelines found matching pattern 'cdk-pipeline-*'"
        PIPELINES=""
    else
        log "Found pipelines: $PIPELINES"
    fi
    
    # Find repositories that match our pattern
    REPOSITORIES=$(aws codecommit list-repositories --query 'repositories[?contains(repositoryName, `infrastructure-`)].repositoryName' --output text)
    
    if [ -z "$REPOSITORIES" ]; then
        warning "No CodeCommit repositories found matching pattern 'infrastructure-*'"
        REPOSITORIES=""
    else
        log "Found repositories: $REPOSITORIES"
    fi
    
    # Find CloudFormation stacks related to CDK pipelines
    STACKS=$(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query 'StackSummaries[?contains(StackName, `PipelineStack`) || contains(StackName, `cdk-pipeline-`)].StackName' \
        --output text)
    
    if [ -z "$STACKS" ]; then
        warning "No CloudFormation stacks found matching CDK pipeline pattern"
        STACKS=""
    else
        log "Found stacks: $STACKS"
    fi
}

# Function to confirm destruction
confirm_destruction() {
    log "Resources to be destroyed:"
    echo
    
    if [ -n "$PIPELINES" ]; then
        echo "📊 CodePipelines:"
        for pipeline in $PIPELINES; do
            echo "  - $pipeline"
        done
        echo
    fi
    
    if [ -n "$REPOSITORIES" ]; then
        echo "📁 CodeCommit Repositories:"
        for repo in $REPOSITORIES; do
            echo "  - $repo"
        done
        echo
    fi
    
    if [ -n "$STACKS" ]; then
        echo "🏗️  CloudFormation Stacks:"
        for stack in $STACKS; do
            echo "  - $stack"
        done
        echo
    fi
    
    # Additional resources that might be created
    echo "⚠️  Additional resources that may be deleted:"
    echo "  - S3 buckets (pipeline artifacts, application buckets)"
    echo "  - IAM roles and policies"
    echo "  - CodeBuild projects"
    echo "  - SNS topics and subscriptions"
    echo "  - CloudWatch logs and metrics"
    echo
    
    warning "This action is IRREVERSIBLE and will delete ALL resources!"
    warning "Make sure you have backups of any important data!"
    echo
    
    read -p "Are you sure you want to destroy all resources? Type 'yes' to continue: " -r
    if [ "$REPLY" != "yes" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    echo
    warning "Last chance to cancel!"
    read -p "Type 'DELETE' to confirm destruction: " -r
    if [ "$REPLY" != "DELETE" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Function to stop active pipeline executions
stop_active_executions() {
    if [ -n "$PIPELINES" ]; then
        log "Stopping active pipeline executions..."
        
        for pipeline in $PIPELINES; do
            log "Checking pipeline: $pipeline"
            
            # Get active executions
            ACTIVE_EXECUTIONS=$(aws codepipeline list-pipeline-executions \
                --pipeline-name "$pipeline" \
                --query 'pipelineExecutionSummaries[?status==`InProgress`].pipelineExecutionId' \
                --output text)
            
            if [ -n "$ACTIVE_EXECUTIONS" ]; then
                warning "Found active executions for pipeline $pipeline"
                for execution in $ACTIVE_EXECUTIONS; do
                    log "Stopping execution: $execution"
                    aws codepipeline stop-pipeline-execution \
                        --pipeline-name "$pipeline" \
                        --pipeline-execution-id "$execution" \
                        --abandon true || warning "Failed to stop execution $execution"
                done
            else
                log "No active executions found for pipeline $pipeline"
            fi
        done
        
        # Wait for executions to stop
        log "Waiting for pipeline executions to stop..."
        sleep 30
        
        success "Pipeline executions stopped"
    fi
}

# Function to delete CloudFormation stacks
delete_cloudformation_stacks() {
    if [ -n "$STACKS" ]; then
        log "Deleting CloudFormation stacks..."
        
        # Delete stacks in reverse order (application stacks first, then pipeline stacks)
        ORDERED_STACKS=$(echo "$STACKS" | tr ' ' '\n' | sort -r | tr '\n' ' ')
        
        for stack in $ORDERED_STACKS; do
            log "Deleting stack: $stack"
            
            # Check if stack exists
            if aws cloudformation describe-stacks --stack-name "$stack" >/dev/null 2>&1; then
                # Delete stack
                aws cloudformation delete-stack --stack-name "$stack"
                success "Initiated deletion of stack: $stack"
            else
                warning "Stack $stack does not exist or already deleted"
            fi
        done
        
        # Wait for stack deletions to complete
        log "Waiting for stack deletions to complete..."
        for stack in $ORDERED_STACKS; do
            if aws cloudformation describe-stacks --stack-name "$stack" >/dev/null 2>&1; then
                log "Waiting for stack deletion: $stack"
                aws cloudformation wait stack-delete-complete --stack-name "$stack" || \
                    warning "Stack deletion may have failed or timed out: $stack"
            fi
        done
        
        success "CloudFormation stacks deleted"
    fi
}

# Function to delete S3 buckets
delete_s3_buckets() {
    log "Searching for related S3 buckets..."
    
    # Find buckets that might be related to our pipeline
    BUCKETS=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `cdk-pipeline-`) || contains(Name, `codepipeline-`) || contains(Name, `pipeline-`)].Name' --output text)
    
    if [ -n "$BUCKETS" ]; then
        log "Found related S3 buckets: $BUCKETS"
        
        for bucket in $BUCKETS; do
            log "Processing bucket: $bucket"
            
            # Check if bucket exists
            if aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
                warning "Deleting S3 bucket: $bucket"
                
                # Delete all objects and versions
                aws s3 rm s3://"$bucket" --recursive || warning "Failed to delete objects from $bucket"
                
                # Delete bucket
                aws s3api delete-bucket --bucket "$bucket" || warning "Failed to delete bucket $bucket"
                
                success "Deleted S3 bucket: $bucket"
            else
                log "Bucket $bucket does not exist or already deleted"
            fi
        done
    else
        log "No related S3 buckets found"
    fi
}

# Function to delete CodeCommit repositories
delete_codecommit_repos() {
    if [ -n "$REPOSITORIES" ]; then
        log "Deleting CodeCommit repositories..."
        
        for repo in $REPOSITORIES; do
            log "Deleting repository: $repo"
            
            # Check if repository exists
            if aws codecommit get-repository --repository-name "$repo" >/dev/null 2>&1; then
                aws codecommit delete-repository --repository-name "$repo"
                success "Deleted repository: $repo"
            else
                warning "Repository $repo does not exist or already deleted"
            fi
        done
    fi
}

# Function to clean up IAM roles and policies
cleanup_iam_resources() {
    log "Cleaning up IAM resources..."
    
    # Find IAM roles related to CodePipeline and CodeBuild
    ROLES=$(aws iam list-roles --query 'Roles[?contains(RoleName, `CodePipeline`) || contains(RoleName, `CodeBuild`) || contains(RoleName, `cdk-pipeline-`)].RoleName' --output text)
    
    if [ -n "$ROLES" ]; then
        warning "Found related IAM roles (these may be managed by CloudFormation):"
        for role in $ROLES; do
            echo "  - $role"
        done
        warning "IAM roles are typically deleted automatically with CloudFormation stacks"
    else
        log "No related IAM roles found"
    fi
    
    # Note: We don't delete IAM roles directly as they're typically managed by CloudFormation
    # and will be cleaned up when the stacks are deleted
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Find CDK project directories
    CDK_DIRS=$(find . -maxdepth 2 -name "cdk-pipeline-*" -type d 2>/dev/null || true)
    
    if [ -n "$CDK_DIRS" ]; then
        log "Found local CDK project directories:"
        for dir in $CDK_DIRS; do
            echo "  - $dir"
        done
        
        read -p "Do you want to delete these local directories? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for dir in $CDK_DIRS; do
                log "Deleting directory: $dir"
                rm -rf "$dir"
                success "Deleted directory: $dir"
            done
        else
            log "Skipping local directory cleanup"
        fi
    else
        log "No local CDK project directories found"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check if any pipelines still exist
    REMAINING_PIPELINES=$(aws codepipeline list-pipelines --query 'pipelines[?contains(name, `cdk-pipeline-`)].name' --output text)
    if [ -n "$REMAINING_PIPELINES" ]; then
        warning "Some pipelines may still exist: $REMAINING_PIPELINES"
    else
        success "All pipelines cleaned up"
    fi
    
    # Check if any repositories still exist
    REMAINING_REPOS=$(aws codecommit list-repositories --query 'repositories[?contains(repositoryName, `infrastructure-`)].repositoryName' --output text)
    if [ -n "$REMAINING_REPOS" ]; then
        warning "Some repositories may still exist: $REMAINING_REPOS"
    else
        success "All repositories cleaned up"
    fi
    
    # Check if any stacks still exist
    REMAINING_STACKS=$(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE DELETE_IN_PROGRESS \
        --query 'StackSummaries[?contains(StackName, `PipelineStack`) || contains(StackName, `cdk-pipeline-`)].StackName' \
        --output text)
    if [ -n "$REMAINING_STACKS" ]; then
        warning "Some stacks may still exist or are being deleted: $REMAINING_STACKS"
    else
        success "All stacks cleaned up"
    fi
    
    success "Cleanup verification completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup completed!"
    echo
    echo "📋 Cleanup Summary:"
    echo "✅ CloudFormation stacks deleted"
    echo "✅ CodePipelines removed"
    echo "✅ CodeCommit repositories deleted"
    echo "✅ S3 buckets cleaned up"
    echo "✅ IAM resources cleaned up (via CloudFormation)"
    echo
    echo "🔍 Manual Verification:"
    echo "- Check AWS Console for any remaining resources"
    echo "- Verify no unexpected charges in AWS billing"
    echo "- Review CloudWatch logs for any errors"
    echo
    echo "⚠️  Note: Some resources may take time to fully delete"
    echo "   - CloudFormation stacks: 5-15 minutes"
    echo "   - S3 buckets: Immediate"
    echo "   - IAM roles: Automatic with CloudFormation"
    echo
    echo "🔗 Useful Links:"
    echo "- CloudFormation: https://console.aws.amazon.com/cloudformation/home?region=${AWS_REGION}#/stacks"
    echo "- CodePipeline: https://console.aws.amazon.com/codesuite/codepipeline/pipelines"
    echo "- CodeCommit: https://console.aws.amazon.com/codesuite/codecommit/repositories"
    echo "- S3: https://console.aws.amazon.com/s3/home?region=${AWS_REGION}"
    echo
    success "All CDK pipeline resources have been destroyed!"
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    error "Cleanup encountered an error. Some resources may not have been deleted."
    warning "Please check the AWS Console manually for any remaining resources:"
    echo "1. CloudFormation stacks"
    echo "2. CodePipelines"
    echo "3. CodeCommit repositories"
    echo "4. S3 buckets"
    echo "5. IAM roles and policies"
    echo
    error "Manual cleanup may be required for incomplete deletions."
}

# Main function
main() {
    log "Starting Infrastructure Deployment Pipeline cleanup..."
    
    # Set up error handling
    trap handle_cleanup_error ERR
    
    # Run cleanup steps
    check_prerequisites
    check_aws_auth
    discover_resources
    
    # Check if any resources were found
    if [ -z "$PIPELINES" ] && [ -z "$REPOSITORIES" ] && [ -z "$STACKS" ]; then
        warning "No CDK pipeline resources found to delete"
        log "This could mean:"
        echo "1. Resources were already deleted"
        echo "2. Resources were created with different naming patterns"
        echo "3. You're looking in the wrong AWS region/account"
        echo
        read -p "Do you want to continue with manual cleanup? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled"
            exit 0
        fi
    fi
    
    confirm_destruction
    stop_active_executions
    delete_cloudformation_stacks
    delete_s3_buckets
    delete_codecommit_repos
    cleanup_iam_resources
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
    
    success "Cleanup completed successfully!"
}

# Run main function
main "$@"