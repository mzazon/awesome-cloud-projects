#!/bin/bash
set -e

# Cleanup script for Cost-Optimized Batch Processing CDK Stack
# This script safely removes all resources created by the stack

echo "🧹 Cleaning up Cost-Optimized Batch Processing CDK Stack..."

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is required but not installed."
    exit 1
fi

# Check if CDK is available
if ! command -v cdk &> /dev/null; then
    echo "❌ AWS CDK CLI is required but not installed."
    echo "Install with: npm install -g aws-cdk"
    exit 1
fi

# Check if stack exists
STACK_NAME="CostOptimizedBatchProcessingStack"
if ! aws cloudformation describe-stacks --stack-name $STACK_NAME &> /dev/null; then
    echo "❌ Stack $STACK_NAME does not exist."
    exit 1
fi

# Get stack outputs
echo "📋 Retrieving stack information..."
JOB_QUEUE_NAME=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`JobQueueName`].OutputValue' \
    --output text 2>/dev/null || echo "")

ECR_REPO_URI=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
    --output text 2>/dev/null || echo "")

# Cancel any running jobs
if [ ! -z "$JOB_QUEUE_NAME" ]; then
    echo "🔄 Checking for running jobs..."
    RUNNING_JOBS=$(aws batch list-jobs \
        --job-queue $JOB_QUEUE_NAME \
        --job-status RUNNING \
        --query 'jobList[].jobId' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$RUNNING_JOBS" ]; then
        echo "🛑 Cancelling running jobs..."
        for job_id in $RUNNING_JOBS; do
            aws batch cancel-job \
                --job-id $job_id \
                --reason "Stack cleanup" \
                --no-cli-pager
            echo "   Cancelled job: $job_id"
        done
        
        echo "⏳ Waiting for jobs to terminate..."
        sleep 30
    fi
fi

# Empty ECR repository if it exists
if [ ! -z "$ECR_REPO_URI" ]; then
    ECR_REPO_NAME=$(echo $ECR_REPO_URI | cut -d'/' -f2)
    echo "🗑️  Removing ECR images from repository: $ECR_REPO_NAME"
    
    # Get image tags
    IMAGE_TAGS=$(aws ecr list-images \
        --repository-name $ECR_REPO_NAME \
        --query 'imageIds[].imageTag' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$IMAGE_TAGS" ]; then
        for tag in $IMAGE_TAGS; do
            aws ecr batch-delete-image \
                --repository-name $ECR_REPO_NAME \
                --image-ids imageTag=$tag \
                --no-cli-pager || true
        done
    fi
    
    # Delete untagged images
    UNTAGGED_IMAGES=$(aws ecr list-images \
        --repository-name $ECR_REPO_NAME \
        --filter tagStatus=UNTAGGED \
        --query 'imageIds[].imageDigest' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$UNTAGGED_IMAGES" ]; then
        for digest in $UNTAGGED_IMAGES; do
            aws ecr batch-delete-image \
                --repository-name $ECR_REPO_NAME \
                --image-ids imageDigest=$digest \
                --no-cli-pager || true
        done
    fi
fi

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    echo "🔧 Activating virtual environment..."
    source venv/bin/activate
fi

# Prompt for confirmation
echo ""
echo "⚠️  This will permanently delete all resources created by the stack."
echo "   - AWS Batch compute environment, job queue, and job definition"
echo "   - ECR repository and all container images"
echo "   - S3 bucket and all stored artifacts"
echo "   - CloudWatch log group and all logs"
echo "   - VPC, subnets, and networking resources"
echo "   - IAM roles and policies"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cleanup cancelled."
    exit 0
fi

# Destroy the stack
echo "🚮 Destroying CDK stack..."
cdk destroy --force

# Check if stack was successfully deleted
echo "⏳ Waiting for stack deletion to complete..."
sleep 10

if aws cloudformation describe-stacks --stack-name $STACK_NAME &> /dev/null; then
    echo "⚠️  Stack deletion may still be in progress. Check AWS Console for status."
else
    echo "✅ Stack successfully deleted!"
fi

# Clean up local files
echo "🧹 Cleaning up local files..."
if [ -d "venv" ]; then
    rm -rf venv
    echo "   Removed Python virtual environment"
fi

if [ -d "cdk.out" ]; then
    rm -rf cdk.out
    echo "   Removed CDK output directory"
fi

if [ -d ".pytest_cache" ]; then
    rm -rf .pytest_cache
    echo "   Removed pytest cache"
fi

if [ -d "__pycache__" ]; then
    rm -rf __pycache__
    echo "   Removed Python cache"
fi

echo ""
echo "✅ Cleanup completed successfully!"
echo "💰 All resources have been removed to prevent ongoing charges."