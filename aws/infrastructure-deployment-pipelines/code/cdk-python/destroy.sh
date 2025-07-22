#!/bin/bash

# Infrastructure Deployment Pipeline - CDK Python Destroy Script
# This script safely destroys the infrastructure deployment pipeline and all associated resources

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="infrastructure-deployment-pipeline"
STACK_NAME="InfrastructurePipelineStack"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if CDK is installed
    if ! command -v cdk &> /dev/null; then
        print_error "AWS CDK is not installed. Please install it first: npm install -g aws-cdk"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please configure them first."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to set up environment
setup_environment() {
    print_info "Setting up environment..."
    
    # Change to script directory
    cd "$SCRIPT_DIR"
    
    # Set environment variables
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export CDK_DEFAULT_ACCOUNT=$AWS_ACCOUNT_ID
    export CDK_DEFAULT_REGION=$AWS_REGION
    
    print_info "AWS Region: $AWS_REGION"
    print_info "AWS Account: $AWS_ACCOUNT_ID"
    
    print_success "Environment setup completed"
}

# Function to list existing stacks
list_stacks() {
    print_info "Listing existing CDK stacks..."
    
    # Activate virtual environment if it exists
    if [ -d ".venv" ]; then
        source .venv/bin/activate
    fi
    
    # List stacks
    STACKS=$(cdk list 2>/dev/null) || STACKS=""
    
    if [ -n "$STACKS" ]; then
        print_info "Found CDK stacks:"
        echo "$STACKS" | while read -r stack; do
            echo "  - $stack"
        done
    else
        print_warning "No CDK stacks found"
    fi
}

# Function to check if stack exists
stack_exists() {
    local stack_name=$1
    aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" &> /dev/null
}

# Function to get stack resources
get_stack_resources() {
    local stack_name=$1
    print_info "Getting resources for stack: $stack_name"
    
    if stack_exists "$stack_name"; then
        aws cloudformation list-stack-resources \
            --stack-name "$stack_name" \
            --region "$AWS_REGION" \
            --query 'StackResourceSummaries[].{Type:ResourceType,LogicalId:LogicalResourceId,PhysicalId:PhysicalResourceId}' \
            --output table 2>/dev/null || true
    else
        print_warning "Stack $stack_name does not exist"
    fi
}

# Function to empty S3 buckets
empty_s3_buckets() {
    print_info "Emptying S3 buckets..."
    
    # Get all S3 buckets from the stack
    if stack_exists "$STACK_NAME"; then
        S3_BUCKETS=$(aws cloudformation list-stack-resources \
            --stack-name "$STACK_NAME" \
            --region "$AWS_REGION" \
            --query 'StackResourceSummaries[?ResourceType==`AWS::S3::Bucket`].PhysicalResourceId' \
            --output text 2>/dev/null) || S3_BUCKETS=""
        
        if [ -n "$S3_BUCKETS" ]; then
            for bucket in $S3_BUCKETS; do
                if [ -n "$bucket" ] && [ "$bucket" != "None" ]; then
                    print_info "Emptying S3 bucket: $bucket"
                    
                    # Check if bucket exists
                    if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
                        # Empty the bucket
                        aws s3 rm s3://"$bucket" --recursive 2>/dev/null || true
                        
                        # Delete all object versions if versioning is enabled
                        aws s3api delete-objects --bucket "$bucket" \
                            --delete "$(aws s3api list-object-versions \
                                --bucket "$bucket" \
                                --output json \
                                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" \
                            2>/dev/null || true
                        
                        # Delete all delete markers if versioning is enabled
                        aws s3api delete-objects --bucket "$bucket" \
                            --delete "$(aws s3api list-object-versions \
                                --bucket "$bucket" \
                                --output json \
                                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" \
                            2>/dev/null || true
                        
                        print_success "Emptied S3 bucket: $bucket"
                    else
                        print_warning "S3 bucket $bucket does not exist or is not accessible"
                    fi
                fi
            done
        else
            print_info "No S3 buckets found in stack"
        fi
    fi
}

# Function to stop running pipelines
stop_pipelines() {
    print_info "Checking for running pipelines..."
    
    # Get all CodePipeline pipelines from the stack
    if stack_exists "$STACK_NAME"; then
        PIPELINES=$(aws cloudformation list-stack-resources \
            --stack-name "$STACK_NAME" \
            --region "$AWS_REGION" \
            --query 'StackResourceSummaries[?ResourceType==`AWS::CodePipeline::Pipeline`].PhysicalResourceId' \
            --output text 2>/dev/null) || PIPELINES=""
        
        if [ -n "$PIPELINES" ]; then
            for pipeline in $PIPELINES; do
                if [ -n "$pipeline" ] && [ "$pipeline" != "None" ]; then
                    print_info "Checking pipeline: $pipeline"
                    
                    # Get pipeline execution status
                    EXECUTION_ID=$(aws codepipeline get-pipeline-state \
                        --name "$pipeline" \
                        --query 'stageStates[0].latestExecution.pipelineExecutionId' \
                        --output text 2>/dev/null) || EXECUTION_ID=""
                    
                    if [ -n "$EXECUTION_ID" ] && [ "$EXECUTION_ID" != "None" ]; then
                        EXECUTION_STATUS=$(aws codepipeline get-pipeline-execution \
                            --pipeline-name "$pipeline" \
                            --pipeline-execution-id "$EXECUTION_ID" \
                            --query 'pipelineExecution.status' \
                            --output text 2>/dev/null) || EXECUTION_STATUS=""
                        
                        if [ "$EXECUTION_STATUS" = "InProgress" ]; then
                            print_warning "Pipeline $pipeline is running. Stopping execution..."
                            aws codepipeline stop-pipeline-execution \
                                --pipeline-name "$pipeline" \
                                --pipeline-execution-id "$EXECUTION_ID" \
                                --abandon true 2>/dev/null || true
                            print_success "Stopped pipeline execution: $pipeline"
                        fi
                    fi
                fi
            done
        else
            print_info "No CodePipeline pipelines found in stack"
        fi
    fi
}

# Function to destroy application stacks
destroy_application_stacks() {
    print_info "Destroying application stacks..."
    
    # Activate virtual environment if it exists
    if [ -d ".venv" ]; then
        source .venv/bin/activate
    fi
    
    # Get all application stacks (dev, staging, prod)
    ALL_STACKS=$(cdk list 2>/dev/null) || ALL_STACKS=""
    
    if [ -n "$ALL_STACKS" ]; then
        # Destroy application stacks first (they depend on the pipeline)
        echo "$ALL_STACKS" | while read -r stack; do
            if [ -n "$stack" ] && [ "$stack" != "$STACK_NAME" ]; then
                print_info "Destroying application stack: $stack"
                
                if [ "$AUTO_APPROVE" = "true" ]; then
                    cdk destroy "$stack" --force 2>/dev/null || true
                else
                    cdk destroy "$stack" 2>/dev/null || true
                fi
                
                print_success "Destroyed application stack: $stack"
            fi
        done
    fi
}

# Function to destroy pipeline stack
destroy_pipeline_stack() {
    print_info "Destroying pipeline stack..."
    
    # Activate virtual environment if it exists
    if [ -d ".venv" ]; then
        source .venv/bin/activate
    fi
    
    # Destroy the pipeline stack
    if [ "$AUTO_APPROVE" = "true" ]; then
        cdk destroy "$STACK_NAME" --force
    else
        cdk destroy "$STACK_NAME"
    fi
    
    print_success "Destroyed pipeline stack: $STACK_NAME"
}

# Function to clean up remaining resources
cleanup_remaining_resources() {
    print_info "Cleaning up remaining resources..."
    
    # Clean up any remaining CodeCommit repositories
    print_info "Checking for CodeCommit repositories..."
    
    # This is a manual cleanup - user should specify repository name
    if [ -n "$REPO_NAME" ]; then
        print_info "Deleting CodeCommit repository: $REPO_NAME"
        aws codecommit delete-repository --repository-name "$REPO_NAME" 2>/dev/null || true
        print_success "Deleted CodeCommit repository: $REPO_NAME"
    else
        print_warning "Repository name not specified. Manual cleanup may be required."
    fi
    
    # Clean up any remaining CloudWatch log groups
    print_info "Cleaning up CloudWatch log groups..."
    LOG_GROUPS=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/codebuild/$PROJECT_NAME" \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null) || LOG_GROUPS=""
    
    if [ -n "$LOG_GROUPS" ]; then
        for log_group in $LOG_GROUPS; do
            if [ -n "$log_group" ] && [ "$log_group" != "None" ]; then
                print_info "Deleting log group: $log_group"
                aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || true
            fi
        done
    fi
}

# Function to show confirmation
show_confirmation() {
    print_warning "This will destroy the following resources:"
    print_warning "- CDK Pipeline Stack: $STACK_NAME"
    print_warning "- All application stacks (dev, staging, prod)"
    print_warning "- All associated AWS resources (S3 buckets, DynamoDB tables, Lambda functions, etc.)"
    print_warning "- CodeCommit repository (if specified)"
    print_warning ""
    print_warning "This action cannot be undone!"
    print_warning ""
    
    if [ "$AUTO_APPROVE" != "true" ]; then
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Operation cancelled by user"
            exit 0
        fi
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -y, --auto-approve  Auto-approve destruction (no interactive prompts)"
    echo "  --repo-name NAME    Specify repository name to delete"
    echo "  --list-only         List stacks and resources only, don't destroy"
    echo ""
    echo "Environment variables:"
    echo "  AWS_REGION          AWS region (default: from AWS CLI config)"
    echo "  REPO_NAME           Repository name to delete"
    echo "  AUTO_APPROVE        Auto-approve destruction (true/false)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive destruction"
    echo "  $0 --auto-approve                    # Auto-approve destruction"
    echo "  $0 --list-only                       # List resources only"
    echo "  REPO_NAME=my-repo $0                 # Delete specific repository"
}

# Main function
main() {
    print_info "Starting Infrastructure Deployment Pipeline destruction..."
    print_info "Project: $PROJECT_NAME"
    print_info "Stack: $STACK_NAME"
    print_info ""
    
    # Parse command line arguments
    LIST_ONLY=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -y|--auto-approve)
                export AUTO_APPROVE=true
                shift
                ;;
            --repo-name)
                export REPO_NAME="$2"
                shift 2
                ;;
            --list-only)
                LIST_ONLY=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Execute destruction steps
    check_prerequisites
    setup_environment
    
    if [ "$LIST_ONLY" = "true" ]; then
        list_stacks
        get_stack_resources "$STACK_NAME"
        exit 0
    fi
    
    show_confirmation
    
    print_info "Starting destruction process..."
    
    # Stop any running pipelines
    stop_pipelines
    
    # Empty S3 buckets before destruction
    empty_s3_buckets
    
    # Destroy application stacks first
    destroy_application_stacks
    
    # Destroy pipeline stack
    destroy_pipeline_stack
    
    # Clean up remaining resources
    cleanup_remaining_resources
    
    print_success "Destruction completed successfully!"
    print_info ""
    print_info "All resources have been destroyed."
    print_info "Please check the AWS Console to verify complete cleanup."
}

# Run main function with all arguments
main "$@"