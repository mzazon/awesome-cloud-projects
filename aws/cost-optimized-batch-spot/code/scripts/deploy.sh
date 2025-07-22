#!/bin/bash

# AWS Batch with Spot Instances - Deployment Script
# This script deploys a cost-optimized batch processing solution using AWS Batch and Spot Instances

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI not configured or authentication failed"
        exit 1
    fi
}

# Function to check Docker availability
check_docker() {
    if ! command_exists docker; then
        error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        error "Docker daemon is not running"
        exit 1
    fi
}

# Function to wait for resource to be ready
wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local max_attempts=${3:-30}
    local attempt=1
    
    log "Waiting for $resource_type '$resource_name' to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        case $resource_type in
            "compute-environment")
                status=$(aws batch describe-compute-environments \
                    --compute-environments "$resource_name" \
                    --query 'computeEnvironments[0].status' \
                    --output text 2>/dev/null || echo "NOT_FOUND")
                if [ "$status" = "VALID" ]; then
                    success "$resource_type '$resource_name' is ready"
                    return 0
                fi
                ;;
            "job-queue")
                status=$(aws batch describe-job-queues \
                    --job-queues "$resource_name" \
                    --query 'jobQueues[0].state' \
                    --output text 2>/dev/null || echo "NOT_FOUND")
                if [ "$status" = "ENABLED" ]; then
                    success "$resource_type '$resource_name' is ready"
                    return 0
                fi
                ;;
        esac
        
        log "Attempt $attempt/$max_attempts: $resource_type status is $status"
        sleep 10
        ((attempt++))
    done
    
    error "$resource_type '$resource_name' did not become ready within expected time"
    return 1
}

# Function to check if IAM role exists
role_exists() {
    aws iam get-role --role-name "$1" >/dev/null 2>&1
}

# Function to check if ECR repository exists
repo_exists() {
    aws ecr describe-repositories --repository-names "$1" >/dev/null 2>&1
}

# Function to cleanup on failure
cleanup_on_failure() {
    warn "Deployment failed. Cleaning up resources..."
    
    # Cancel any running jobs
    if [ -n "${JOB_QUEUE_NAME:-}" ]; then
        aws batch list-jobs --job-queue "$JOB_QUEUE_NAME" --job-status RUNNING \
            --query 'jobList[].jobId' --output text 2>/dev/null | \
            xargs -r -n1 aws batch cancel-job --job-id 2>/dev/null || true
    fi
    
    # Clean up resources in reverse order
    [ -n "${JOB_QUEUE_NAME:-}" ] && aws batch update-job-queue --job-queue "$JOB_QUEUE_NAME" --state DISABLED 2>/dev/null || true
    [ -n "${COMPUTE_ENV_NAME:-}" ] && aws batch update-compute-environment --compute-environment "$COMPUTE_ENV_NAME" --state DISABLED 2>/dev/null || true
    
    sleep 30  # Wait for resources to disable
    
    [ -n "${JOB_QUEUE_NAME:-}" ] && aws batch delete-job-queue --job-queue "$JOB_QUEUE_NAME" 2>/dev/null || true
    [ -n "${COMPUTE_ENV_NAME:-}" ] && aws batch delete-compute-environment --compute-environment "$COMPUTE_ENV_NAME" 2>/dev/null || true
    [ -n "${SECURITY_GROUP_ID:-}" ] && aws ec2 delete-security-group --group-id "$SECURITY_GROUP_ID" 2>/dev/null || true
    
    error "Deployment failed and cleanup completed"
    exit 1
}

# Trap to cleanup on failure
trap cleanup_on_failure ERR

# Header
echo "=========================================="
echo "AWS Batch Spot Instance Deployment Script"
echo "=========================================="

# Prerequisites check
log "Checking prerequisites..."

if ! command_exists aws; then
    error "AWS CLI is not installed"
    exit 1
fi

check_aws_auth
check_docker

# Get AWS account information
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=$(aws configure get region)

if [ -z "$AWS_REGION" ]; then
    error "AWS region not configured"
    exit 1
fi

log "AWS Account ID: $AWS_ACCOUNT_ID"
log "AWS Region: $AWS_REGION"

# Set up environment variables
export BATCH_SERVICE_ROLE_NAME=AWSBatchServiceRole
export INSTANCE_ROLE_NAME=ecsInstanceRole
export JOB_ROLE_NAME=BatchJobExecutionRole

# Generate unique identifiers
RANDOM_STRING=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

export ECR_REPO_NAME=batch-demo-$RANDOM_STRING
export COMPUTE_ENV_NAME=spot-compute-env-$RANDOM_STRING
export JOB_QUEUE_NAME=spot-job-queue-$RANDOM_STRING
export JOB_DEFINITION_NAME=batch-job-def-$RANDOM_STRING

log "Generated unique identifiers with suffix: $RANDOM_STRING"

# Check if dry-run mode
if [ "${1:-}" = "--dry-run" ]; then
    log "DRY RUN MODE: No resources will be created"
    log "Would create the following resources:"
    echo "  - ECR Repository: $ECR_REPO_NAME"
    echo "  - Compute Environment: $COMPUTE_ENV_NAME"
    echo "  - Job Queue: $JOB_QUEUE_NAME"
    echo "  - Job Definition: $JOB_DEFINITION_NAME"
    exit 0
fi

# Create IAM service role for AWS Batch
log "Creating IAM service role for AWS Batch..."
if ! role_exists "$BATCH_SERVICE_ROLE_NAME"; then
    aws iam create-role \
        --role-name $BATCH_SERVICE_ROLE_NAME \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "batch.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }'
    
    aws iam attach-role-policy \
        --role-name $BATCH_SERVICE_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole
    
    success "Created IAM service role: $BATCH_SERVICE_ROLE_NAME"
else
    log "IAM service role already exists: $BATCH_SERVICE_ROLE_NAME"
fi

# Create IAM instance role for EC2 instances
log "Creating IAM instance role for EC2 instances..."
if ! role_exists "$INSTANCE_ROLE_NAME"; then
    aws iam create-role \
        --role-name $INSTANCE_ROLE_NAME \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "ec2.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }'
    
    aws iam attach-role-policy \
        --role-name $INSTANCE_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role
    
    aws iam create-instance-profile \
        --instance-profile-name $INSTANCE_ROLE_NAME
    
    aws iam add-role-to-instance-profile \
        --instance-profile-name $INSTANCE_ROLE_NAME \
        --role-name $INSTANCE_ROLE_NAME
    
    success "Created IAM instance role: $INSTANCE_ROLE_NAME"
else
    log "IAM instance role already exists: $INSTANCE_ROLE_NAME"
fi

# Create IAM job execution role
log "Creating IAM job execution role..."
if ! role_exists "$JOB_ROLE_NAME"; then
    aws iam create-role \
        --role-name $JOB_ROLE_NAME \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "ecs-tasks.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }'
    
    aws iam attach-role-policy \
        --role-name $JOB_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    
    success "Created IAM job execution role: $JOB_ROLE_NAME"
else
    log "IAM job execution role already exists: $JOB_ROLE_NAME"
fi

# Create ECR repository
log "Creating ECR repository..."
if ! repo_exists "$ECR_REPO_NAME"; then
    aws ecr create-repository --repository-name $ECR_REPO_NAME
    success "Created ECR repository: $ECR_REPO_NAME"
else
    log "ECR repository already exists: $ECR_REPO_NAME"
fi

export ECR_URI=$(aws ecr describe-repositories \
    --repository-names $ECR_REPO_NAME \
    --query 'repositories[0].repositoryUri' --output text)

log "ECR URI: $ECR_URI"

# Create sample Python batch application
log "Creating sample batch application..."
cat > batch_app.py << 'EOF'
import os
import sys
import time
import random
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def simulate_batch_processing():
    """Simulate a batch processing job."""
    job_id = os.environ.get('AWS_BATCH_JOB_ID', 'local-test')
    logger.info(f"Starting batch job: {job_id}")
    
    # Simulate variable processing time (1-5 minutes)
    processing_time = random.randint(60, 300)
    logger.info(f"Processing will take {processing_time} seconds")
    
    # Process data in chunks to show progress
    chunks = 10
    chunk_time = processing_time / chunks
    
    for i in range(chunks):
        time.sleep(chunk_time)
        progress = ((i + 1) / chunks) * 100
        logger.info(f"Progress: {progress:.1f}%")
    
    logger.info(f"Batch job {job_id} completed successfully")
    return 0

if __name__ == "__main__":
    try:
        exit_code = simulate_batch_processing()
        sys.exit(exit_code)
    except Exception as e:
        logger.error(f"Batch job failed: {str(e)}")
        sys.exit(1)
EOF

# Create Dockerfile
log "Creating Dockerfile..."
cat > Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

COPY batch_app.py .

CMD ["python", "batch_app.py"]
EOF

# Build and push Docker image
log "Building and pushing Docker image..."
aws ecr get-login-password --region $AWS_REGION | \
    docker login --username AWS --password-stdin $ECR_URI

docker build -t $ECR_REPO_NAME .
docker tag $ECR_REPO_NAME:latest $ECR_URI:latest
docker push $ECR_URI:latest

success "Docker image pushed to ECR"

# Get VPC and subnet information
log "Getting VPC and subnet information..."
export VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' --output text)

export SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[].SubnetId' --output text | tr '\t' ',')

log "VPC ID: $VPC_ID"
log "Subnet IDs: $SUBNET_IDS"

# Create security group
log "Creating security group..."
export SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name batch-sg-$RANDOM_STRING \
    --description "Security group for AWS Batch instances" \
    --vpc-id $VPC_ID \
    --query 'GroupId' --output text)

success "Created security group: $SECURITY_GROUP_ID"

# Create compute environment
log "Creating AWS Batch compute environment..."
aws batch create-compute-environment \
    --compute-environment-name $COMPUTE_ENV_NAME \
    --type MANAGED \
    --state ENABLED \
    --compute-resources '{
        "type": "EC2",
        "minvCpus": 0,
        "maxvCpus": 100,
        "desiredvCpus": 0,
        "instanceTypes": ["c5.large", "c5.xlarge", "c5.2xlarge", "m5.large", "m5.xlarge", "m5.2xlarge"],
        "allocationStrategy": "SPOT_CAPACITY_OPTIMIZED",
        "bidPercentage": 80,
        "ec2Configuration": [{
            "imageType": "ECS_AL2"
        }],
        "subnets": ["'"$(echo $SUBNET_IDS | sed 's/,/", "/g')"'"],
        "securityGroupIds": ["'$SECURITY_GROUP_ID'"],
        "instanceRole": "arn:aws:iam::'$AWS_ACCOUNT_ID':instance-profile/'$INSTANCE_ROLE_NAME'",
        "tags": {
            "Environment": "batch-demo",
            "CostCenter": "batch-processing"
        }
    }' \
    --service-role arn:aws:iam::$AWS_ACCOUNT_ID:role/$BATCH_SERVICE_ROLE_NAME

success "Created compute environment: $COMPUTE_ENV_NAME"

# Wait for compute environment to be ready
wait_for_resource "compute-environment" "$COMPUTE_ENV_NAME"

# Create job queue
log "Creating job queue..."
aws batch create-job-queue \
    --job-queue-name $JOB_QUEUE_NAME \
    --state ENABLED \
    --priority 1 \
    --compute-environment-order '[{
        "order": 1,
        "computeEnvironment": "'$COMPUTE_ENV_NAME'"
    }]'

success "Created job queue: $JOB_QUEUE_NAME"

# Wait for job queue to be ready
wait_for_resource "job-queue" "$JOB_QUEUE_NAME"

# Create job definition
log "Creating job definition..."
aws batch register-job-definition \
    --job-definition-name $JOB_DEFINITION_NAME \
    --type container \
    --container-properties '{
        "image": "'$ECR_URI':latest",
        "vcpus": 1,
        "memory": 512,
        "jobRoleArn": "arn:aws:iam::'$AWS_ACCOUNT_ID':role/'$JOB_ROLE_NAME'"
    }' \
    --retry-strategy '{
        "attempts": 3,
        "evaluateOnExit": [{
            "onStatusReason": "Host EC2*",
            "action": "RETRY"
        }, {
            "onReason": "*",
            "action": "EXIT"
        }]
    }' \
    --timeout '{"attemptDurationSeconds": 3600}'

success "Created job definition: $JOB_DEFINITION_NAME"

# Submit a test job
log "Submitting test batch job..."
export JOB_ID=$(aws batch submit-job \
    --job-name test-batch-job-$(date +%s) \
    --job-queue $JOB_QUEUE_NAME \
    --job-definition $JOB_DEFINITION_NAME \
    --query 'jobId' --output text)

success "Submitted job with ID: $JOB_ID"

# Clean up local files
rm -f batch_app.py Dockerfile

# Save deployment info
cat > deployment_info.txt << EOF
AWS Batch Deployment Information
===============================
Deployment Date: $(date)
AWS Account ID: $AWS_ACCOUNT_ID
AWS Region: $AWS_REGION

Resources Created:
- ECR Repository: $ECR_REPO_NAME
- Compute Environment: $COMPUTE_ENV_NAME
- Job Queue: $JOB_QUEUE_NAME
- Job Definition: $JOB_DEFINITION_NAME
- Security Group: $SECURITY_GROUP_ID
- Test Job ID: $JOB_ID

ECR URI: $ECR_URI

To monitor your job:
aws batch describe-jobs --jobs $JOB_ID --query 'jobs[0].{Status:status,Queue:jobQueue}' --output table

To submit additional jobs:
aws batch submit-job --job-name my-job --job-queue $JOB_QUEUE_NAME --job-definition $JOB_DEFINITION_NAME

To clean up all resources:
./destroy.sh
EOF

success "Deployment completed successfully!"
echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo "✅ IAM roles created"
echo "✅ ECR repository created: $ECR_REPO_NAME"
echo "✅ Docker image built and pushed"
echo "✅ Security group created: $SECURITY_GROUP_ID"
echo "✅ Compute environment created: $COMPUTE_ENV_NAME"
echo "✅ Job queue created: $JOB_QUEUE_NAME"
echo "✅ Job definition created: $JOB_DEFINITION_NAME"
echo "✅ Test job submitted: $JOB_ID"
echo ""
echo "📋 Deployment information saved to: deployment_info.txt"
echo ""
echo "🔍 Monitor your job with:"
echo "aws batch describe-jobs --jobs $JOB_ID --query 'jobs[0].{Status:status,Queue:jobQueue}' --output table"
echo ""
echo "🧹 To clean up all resources, run:"
echo "./destroy.sh"
echo ""
echo "💰 This solution uses Spot Instances for up to 90% cost savings!"
echo "=========================================="