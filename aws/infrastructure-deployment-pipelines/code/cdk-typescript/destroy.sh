#!/bin/bash

# Infrastructure Deployment Pipeline Cleanup Script
# This script removes the CDK infrastructure deployment pipeline

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Parse command line arguments
STACK_TYPE="basic"
FORCE_DESTROY=false
KEEP_ARTIFACTS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --type|-t)
            STACK_TYPE="$2"
            shift 2
            ;;
        --force|-f)
            FORCE_DESTROY=true
            shift
            ;;
        --keep-artifacts)
            KEEP_ARTIFACTS=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --type, -t TYPE       Stack type: basic or advanced (default: basic)"
            echo "  --force, -f           Force destruction without confirmation"
            echo "  --keep-artifacts      Keep S3 artifacts bucket"
            echo "  --help, -h            Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate stack type
if [[ "$STACK_TYPE" != "basic" && "$STACK_TYPE" != "advanced" ]]; then
    log_error "Invalid stack type: $STACK_TYPE. Must be 'basic' or 'advanced'."
    exit 1
fi

# Determine stack name
if [[ "$STACK_TYPE" == "basic" ]]; then
    STACK_NAME="InfrastructureDeploymentPipeline"
else
    STACK_NAME="AdvancedPipelineStack"
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if CDK is installed
if ! command -v cdk &> /dev/null; then
    log_error "AWS CDK CLI is not installed. Please install it first."
    exit 1
fi

# Get AWS account and region
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)

if [[ -z "$AWS_ACCOUNT" || -z "$AWS_REGION" ]]; then
    log_error "Unable to determine AWS account or region. Please check your AWS configuration."
    exit 1
fi

log_info "Starting cleanup..."
log_info "AWS Account: $AWS_ACCOUNT"
log_info "AWS Region: $AWS_REGION"
log_info "Stack Type: $STACK_TYPE"
log_info "Stack Name: $STACK_NAME"

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" &> /dev/null; then
    log_error "Stack $STACK_NAME does not exist in region $AWS_REGION"
    exit 1
fi

# Get stack outputs before deletion
log_info "Retrieving stack information..."
OUTPUTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs' \
    --output json)

BUCKET_NAME=""
REPO_NAME=""
PIPELINE_NAME=""

if [[ "$OUTPUTS" != "null" && "$OUTPUTS" != "[]" ]]; then
    BUCKET_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="ArtifactBucketName") | .OutputValue // empty')
    REPO_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="RepositoryCloneUrl") | .OutputValue // empty' | sed 's/.*\/\([^\/]*\)\.git/\1/')
    PIPELINE_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="PipelineName") | .OutputValue // empty')
fi

# Warning about destructive action
if [[ "$FORCE_DESTROY" != true ]]; then
    echo
    log_warning "This will permanently delete the following resources:"
    echo "  - CloudFormation Stack: $STACK_NAME"
    echo "  - CodePipeline: $PIPELINE_NAME"
    echo "  - CodeCommit Repository: $REPO_NAME"
    if [[ "$KEEP_ARTIFACTS" != true && "$BUCKET_NAME" != "" ]]; then
        echo "  - S3 Artifacts Bucket: $BUCKET_NAME (and all contents)"
    fi
    echo
    log_warning "This action cannot be undone!"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
fi

# Stop any running pipeline executions
if [[ "$PIPELINE_NAME" != "" ]]; then
    log_info "Checking for running pipeline executions..."
    RUNNING_EXECUTIONS=$(aws codepipeline list-pipeline-executions \
        --pipeline-name "$PIPELINE_NAME" \
        --query 'pipelineExecutionSummaries[?status==`InProgress`].pipelineExecutionId' \
        --output text)
    
    if [[ "$RUNNING_EXECUTIONS" != "" ]]; then
        log_warning "Found running pipeline executions. Stopping them..."
        for execution_id in $RUNNING_EXECUTIONS; do
            aws codepipeline stop-pipeline-execution \
                --pipeline-name "$PIPELINE_NAME" \
                --pipeline-execution-id "$execution_id" \
                --abandon
            log_info "Stopped execution: $execution_id"
        done
    fi
fi

# Empty S3 bucket if it exists and we're not keeping artifacts
if [[ "$BUCKET_NAME" != "" && "$KEEP_ARTIFACTS" != true ]]; then
    log_info "Emptying S3 bucket: $BUCKET_NAME"
    if aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        # Delete all objects including versions
        aws s3api delete-objects \
            --bucket "$BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' \
                --output json)" &> /dev/null || true
        
        # Delete delete markers
        aws s3api delete-objects \
            --bucket "$BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' \
                --output json)" &> /dev/null || true
        
        log_success "S3 bucket emptied"
    else
        log_warning "S3 bucket not found or already empty"
    fi
fi

# Delete the CloudFormation stack
log_info "Deleting CloudFormation stack: $STACK_NAME"
if cdk destroy "$STACK_NAME" --force; then
    log_success "Stack deleted successfully"
else
    log_error "Failed to delete stack"
    exit 1
fi

# Wait for stack deletion to complete
log_info "Waiting for stack deletion to complete..."
aws cloudformation wait stack-delete-complete \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION"

log_success "Stack deletion completed"

# Manual cleanup instructions
if [[ "$KEEP_ARTIFACTS" == true && "$BUCKET_NAME" != "" ]]; then
    log_info "Manual cleanup required:"
    echo "  - S3 Bucket: $BUCKET_NAME (preserved as requested)"
    echo "  - To delete later: aws s3 rb s3://$BUCKET_NAME --force"
fi

# Check for any remaining resources
log_info "Checking for any remaining resources..."
REMAINING_STACKS=$(aws cloudformation list-stacks \
    --query "StackSummaries[?StackName==\`$STACK_NAME\` && StackStatus!=\`DELETE_COMPLETE\`].StackName" \
    --output text)

if [[ "$REMAINING_STACKS" != "" ]]; then
    log_warning "Some resources may still be cleaning up. Check the AWS Console for details."
else
    log_success "All resources have been cleaned up successfully!"
fi

echo
log_info "Cleanup completed!"
log_info "You can verify the cleanup in the AWS Console:"
echo "https://console.aws.amazon.com/cloudformation/home?region=$AWS_REGION"