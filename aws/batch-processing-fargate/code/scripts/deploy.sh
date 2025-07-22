#!/bin/bash

# AWS Batch with Fargate Deployment Script
# This script deploys the complete AWS Batch infrastructure with Fargate compute environment

set -euo pipefail

# Color codes for output
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

# Script metadata
SCRIPT_NAME="AWS Batch Fargate Deployment"
SCRIPT_VERSION="1.0"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION at $TIMESTAMP"

# Configuration
DEPLOYMENT_TIMEOUT=1800  # 30 minutes
DOCKER_REQUIRED=true
ESTIMATED_COST="\$2.00"

# Prerequisites check function
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check Docker if required
    if [ "$DOCKER_REQUIRED" = true ]; then
        if ! command -v docker &> /dev/null; then
            log_error "Docker is not installed. Docker is required for building container images."
            exit 1
        fi
        
        if ! docker info &> /dev/null; then
            log_error "Docker daemon is not running. Please start Docker and try again."
            exit 1
        fi
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    log_success "Prerequisites check completed successfully"
}

# Environment setup function
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set basic AWS environment
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export BATCH_COMPUTE_ENV_NAME="batch-fargate-compute-${RANDOM_SUFFIX}"
    export BATCH_JOB_QUEUE_NAME="batch-fargate-queue-${RANDOM_SUFFIX}"
    export BATCH_JOB_DEFINITION_NAME="batch-fargate-job-${RANDOM_SUFFIX}"
    export BATCH_EXECUTION_ROLE_NAME="BatchFargateExecutionRole-${RANDOM_SUFFIX}"
    export ECR_REPOSITORY_NAME="batch-processing-demo-${RANDOM_SUFFIX}"
    
    # Get default VPC and subnet information
    export DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text)
    
    if [ "$DEFAULT_VPC_ID" = "None" ] || [ -z "$DEFAULT_VPC_ID" ]; then
        log_error "No default VPC found. Please create a VPC with public subnets first."
        exit 1
    fi
    
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${DEFAULT_VPC_ID}" \
        --query "Subnets[?MapPublicIpOnLaunch==\`true\`].SubnetId" \
        --output text | tr '\t' ',')
    
    if [ -z "$SUBNET_IDS" ]; then
        log_error "No public subnets found in default VPC. Please ensure you have public subnets available."
        exit 1
    fi
    
    export SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${DEFAULT_VPC_ID}" \
                 "Name=group-name,Values=default" \
        --query "SecurityGroups[0].GroupId" --output text)
    
    log_success "Environment configured for region: ${AWS_REGION}"
    log_info "Using VPC: ${DEFAULT_VPC_ID}"
    log_info "Using subnets: ${SUBNET_IDS}"
    log_info "Estimated cost: ${ESTIMATED_COST}"
}

# IAM role creation function
create_iam_roles() {
    log_info "Creating IAM execution role for Fargate tasks..."
    
    # Create trust policy for ECS tasks
    cat > /tmp/batch-execution-role-trust-policy.json << EOF
{
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
}
EOF
    
    # Create the execution role
    aws iam create-role \
        --role-name ${BATCH_EXECUTION_ROLE_NAME} \
        --assume-role-policy-document file:///tmp/batch-execution-role-trust-policy.json \
        --description "Execution role for AWS Batch Fargate tasks"
    
    # Attach AWS managed policy for ECS task execution
    aws iam attach-role-policy \
        --role-name ${BATCH_EXECUTION_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
    
    # Store the role ARN for later use
    export EXECUTION_ROLE_ARN=$(aws iam get-role \
        --role-name ${BATCH_EXECUTION_ROLE_NAME} \
        --query 'Role.Arn' --output text)
    
    log_success "Created execution role: ${EXECUTION_ROLE_ARN}"
    
    # Wait for role to be available
    log_info "Waiting for IAM role to be ready..."
    sleep 10
}

# ECR repository and container image creation
create_container_image() {
    log_info "Creating ECR repository and building container image..."
    
    # Create ECR repository
    aws ecr create-repository \
        --repository-name ${ECR_REPOSITORY_NAME} \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256
    
    # Get login token for ECR
    aws ecr get-login-password --region ${AWS_REGION} | \
        docker login --username AWS --password-stdin \
        ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
    
    # Create a simple batch processing script
    cat > /tmp/batch-process.py << 'EOF'
#!/usr/bin/env python3
import os
import sys
import time
import json
from datetime import datetime

def process_batch_job():
    """Simulate batch processing work"""
    job_id = os.environ.get('AWS_BATCH_JOB_ID', 'local-test')
    job_name = os.environ.get('AWS_BATCH_JOB_NAME', 'test-job')
    
    print(f"Starting batch job: {job_name} (ID: {job_id})")
    print(f"Timestamp: {datetime.now().isoformat()}")
    print(f"Environment: {os.environ.get('ENVIRONMENT', 'production')}")
    
    # Simulate processing work
    for i in range(10):
        print(f"Processing item {i+1}/10...")
        time.sleep(2)
    
    print("Batch processing completed successfully!")
    return {"status": "success", "processed_items": 10, "completion_time": datetime.now().isoformat()}

if __name__ == "__main__":
    try:
        result = process_batch_job()
        print(json.dumps(result))
        sys.exit(0)
    except Exception as e:
        print(f"Error: {str(e)}")
        sys.exit(1)
EOF
    
    # Create Dockerfile
    cat > /tmp/Dockerfile << 'EOF'
FROM python:3.9-alpine

# Set working directory
WORKDIR /app

# Install any additional packages if needed
RUN apk add --no-cache \
    bash \
    curl

# Copy the batch processing script
COPY batch-process.py .

# Make the script executable
RUN chmod +x batch-process.py

# Add a non-root user for security
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# Change ownership of the app directory
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Set environment variables
ENV ENVIRONMENT=production
ENV PYTHONUNBUFFERED=1

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python3 -c "import sys; sys.exit(0)"

# Set the default command
CMD ["python3", "batch-process.py"]
EOF
    
    # Build and push the container image
    cd /tmp
    docker build -t ${ECR_REPOSITORY_NAME} .
    docker tag ${ECR_REPOSITORY_NAME}:latest \
        ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY_NAME}:latest
    
    docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY_NAME}:latest
    
    # Store the image URI
    export CONTAINER_IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY_NAME}:latest"
    
    log_success "Container image built and pushed: ${CONTAINER_IMAGE_URI}"
}

# Create Batch compute environment
create_compute_environment() {
    log_info "Creating Fargate compute environment..."
    
    # Create compute environment configuration
    cat > /tmp/compute-environment.json << EOF
{
  "computeEnvironmentName": "${BATCH_COMPUTE_ENV_NAME}",
  "type": "MANAGED",
  "state": "ENABLED",
  "computeResources": {
    "type": "FARGATE",
    "maxvCpus": 256,
    "subnets": ["${SUBNET_IDS//,/\",\"}"],
    "securityGroupIds": ["${SECURITY_GROUP_ID}"],
    "tags": {
      "Environment": "demo",
      "Project": "batch-processing",
      "ManagedBy": "aws-batch-fargate-deployment"
    }
  },
  "serviceRole": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/aws-service-role/batch.amazonaws.com/AWSServiceRoleForBatch",
  "tags": {
    "Environment": "demo",
    "Project": "batch-processing",
    "ManagedBy": "aws-batch-fargate-deployment"
  }
}
EOF
    
    # Create the compute environment
    aws batch create-compute-environment \
        --cli-input-json file:///tmp/compute-environment.json
    
    # Wait for compute environment to be ready
    log_info "Waiting for compute environment to be ready (this may take several minutes)..."
    local timeout=600  # 10 minutes
    local elapsed=0
    local interval=30
    
    while [ $elapsed -lt $timeout ]; do
        local status=$(aws batch describe-compute-environments \
            --compute-environments ${BATCH_COMPUTE_ENV_NAME} \
            --query 'computeEnvironments[0].status' --output text)
        
        if [ "$status" = "VALID" ]; then
            log_success "Compute environment is ready"
            break
        elif [ "$status" = "INVALID" ]; then
            log_error "Compute environment creation failed"
            exit 1
        fi
        
        log_info "Compute environment status: $status (waiting...)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    if [ $elapsed -ge $timeout ]; then
        log_error "Timeout waiting for compute environment to be ready"
        exit 1
    fi
}

# Create job queue
create_job_queue() {
    log_info "Creating job queue..."
    
    # Create job queue
    aws batch create-job-queue \
        --job-queue-name ${BATCH_JOB_QUEUE_NAME} \
        --state ENABLED \
        --priority 1 \
        --compute-environment-order order=1,computeEnvironment=${BATCH_COMPUTE_ENV_NAME} \
        --tags Environment=demo,Project=batch-processing,ManagedBy=aws-batch-fargate-deployment
    
    # Wait for job queue to be ready
    log_info "Waiting for job queue to be ready..."
    local timeout=300  # 5 minutes
    local elapsed=0
    local interval=15
    
    while [ $elapsed -lt $timeout ]; do
        local status=$(aws batch describe-job-queues \
            --job-queues ${BATCH_JOB_QUEUE_NAME} \
            --query 'jobQueues[0].state' --output text)
        
        if [ "$status" = "ENABLED" ]; then
            log_success "Job queue is ready"
            break
        fi
        
        log_info "Job queue status: $status (waiting...)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    if [ $elapsed -ge $timeout ]; then
        log_error "Timeout waiting for job queue to be ready"
        exit 1
    fi
}

# Create CloudWatch log group
create_log_group() {
    log_info "Creating CloudWatch log group..."
    
    # Create log group for batch jobs
    aws logs create-log-group \
        --log-group-name "/aws/batch/job" \
        --retention-in-days 7 \
        --tags Environment=demo,Project=batch-processing,ManagedBy=aws-batch-fargate-deployment
    
    log_success "CloudWatch log group created: /aws/batch/job"
}

# Register job definition
register_job_definition() {
    log_info "Registering job definition for Fargate..."
    
    # Create job definition for Fargate
    cat > /tmp/job-definition.json << EOF
{
  "jobDefinitionName": "${BATCH_JOB_DEFINITION_NAME}",
  "type": "container",
  "platformCapabilities": ["FARGATE"],
  "containerProperties": {
    "image": "${CONTAINER_IMAGE_URI}",
    "resourceRequirements": [
      {
        "type": "VCPU",
        "value": "0.25"
      },
      {
        "type": "MEMORY",
        "value": "512"
      }
    ],
    "executionRoleArn": "${EXECUTION_ROLE_ARN}",
    "networkConfiguration": {
      "assignPublicIp": "ENABLED"
    },
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/aws/batch/job",
        "awslogs-region": "${AWS_REGION}",
        "awslogs-stream-prefix": "batch-fargate"
      }
    },
    "environment": [
      {
        "name": "ENVIRONMENT",
        "value": "demo"
      }
    ]
  },
  "retryStrategy": {
    "attempts": 1
  },
  "timeout": {
    "attemptDurationSeconds": 3600
  },
  "tags": {
    "Environment": "demo",
    "Project": "batch-processing",
    "ManagedBy": "aws-batch-fargate-deployment"
  }
}
EOF
    
    # Register the job definition
    aws batch register-job-definition \
        --cli-input-json file:///tmp/job-definition.json
    
    log_success "Job definition registered: ${BATCH_JOB_DEFINITION_NAME}"
}

# Submit test job
submit_test_job() {
    log_info "Submitting test batch job..."
    
    # Submit a test job
    JOB_RESPONSE=$(aws batch submit-job \
        --job-name "test-fargate-job-$(date +%s)" \
        --job-queue ${BATCH_JOB_QUEUE_NAME} \
        --job-definition ${BATCH_JOB_DEFINITION_NAME} \
        --timeout attemptDurationSeconds=3600)
    
    # Extract job ID
    export TEST_JOB_ID=$(echo ${JOB_RESPONSE} | jq -r '.jobId')
    
    log_success "Test job submitted successfully: ${TEST_JOB_ID}"
    log_info "Job Name: $(echo ${JOB_RESPONSE} | jq -r '.jobName')"
    
    # Monitor job briefly
    log_info "Monitoring job execution for 60 seconds..."
    local monitor_time=60
    local elapsed=0
    local interval=10
    
    while [ $elapsed -lt $monitor_time ]; do
        local status=$(aws batch describe-jobs --jobs ${TEST_JOB_ID} \
            --query 'jobs[0].status' --output text)
        
        log_info "Job Status: ${status}"
        
        if [ "${status}" = "SUCCEEDED" ]; then
            log_success "Test job completed successfully!"
            break
        elif [ "${status}" = "FAILED" ]; then
            log_warning "Test job failed - check CloudWatch logs for details"
            break
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > /tmp/aws-batch-deployment-info.json << EOF
{
  "deployment": {
    "timestamp": "${TIMESTAMP}",
    "region": "${AWS_REGION}",
    "account_id": "${AWS_ACCOUNT_ID}",
    "estimated_cost": "${ESTIMATED_COST}"
  },
  "resources": {
    "compute_environment": "${BATCH_COMPUTE_ENV_NAME}",
    "job_queue": "${BATCH_JOB_QUEUE_NAME}",
    "job_definition": "${BATCH_JOB_DEFINITION_NAME}",
    "execution_role": "${BATCH_EXECUTION_ROLE_NAME}",
    "ecr_repository": "${ECR_REPOSITORY_NAME}",
    "container_image": "${CONTAINER_IMAGE_URI}",
    "log_group": "/aws/batch/job",
    "test_job_id": "${TEST_JOB_ID:-not_submitted}"
  },
  "networking": {
    "vpc_id": "${DEFAULT_VPC_ID}",
    "subnet_ids": "${SUBNET_IDS}",
    "security_group_id": "${SECURITY_GROUP_ID}"
  }
}
EOF
    
    # Copy to current directory if different from /tmp
    if [ "$(pwd)" != "/tmp" ]; then
        cp /tmp/aws-batch-deployment-info.json ./aws-batch-deployment-info.json
        log_success "Deployment information saved to: $(pwd)/aws-batch-deployment-info.json"
    else
        log_success "Deployment information saved to: /tmp/aws-batch-deployment-info.json"
    fi
}

# Print usage instructions
print_usage_instructions() {
    log_success "AWS Batch with Fargate deployment completed successfully!"
    echo ""
    echo "=== Usage Instructions ==="
    echo ""
    echo "1. Submit a new job:"
    echo "   aws batch submit-job \\"
    echo "       --job-name \"my-batch-job-\$(date +%s)\" \\"
    echo "       --job-queue ${BATCH_JOB_QUEUE_NAME} \\"
    echo "       --job-definition ${BATCH_JOB_DEFINITION_NAME}"
    echo ""
    echo "2. Monitor jobs:"
    echo "   aws batch list-jobs --job-queue ${BATCH_JOB_QUEUE_NAME}"
    echo ""
    echo "3. View job logs:"
    echo "   aws logs describe-log-streams \\"
    echo "       --log-group-name \"/aws/batch/job\" \\"
    echo "       --order-by LastEventTime --descending"
    echo ""
    echo "4. Check resource status:"
    echo "   aws batch describe-compute-environments \\"
    echo "       --compute-environments ${BATCH_COMPUTE_ENV_NAME}"
    echo ""
    echo "=== Important Notes ==="
    echo "- Jobs run on Fargate with 0.25 vCPU and 512 MB memory"
    echo "- Logs are retained for 7 days in CloudWatch"
    echo "- ECR repository includes automatic vulnerability scanning"
    echo "- Container runs as non-root user for security"
    echo ""
    echo "=== Cost Information ==="
    echo "- Fargate pricing: ~\$0.04048 per vCPU hour + \$0.004445 per GB memory hour"
    echo "- CloudWatch Logs: \$0.50 per GB ingested"
    echo "- ECR storage: \$0.10 per GB per month"
    echo ""
    echo "=== Cleanup ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo ""
}

# Cleanup function for error handling
cleanup_on_error() {
    log_warning "Cleaning up temporary files due to error..."
    rm -f /tmp/batch-execution-role-trust-policy.json
    rm -f /tmp/compute-environment.json
    rm -f /tmp/job-definition.json
    rm -f /tmp/batch-process.py
    rm -f /tmp/Dockerfile
}

# Main deployment function
main() {
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_iam_roles
    create_container_image
    create_log_group
    create_compute_environment
    create_job_queue
    register_job_definition
    submit_test_job
    save_deployment_info
    
    # Cleanup temporary files
    rm -f /tmp/batch-execution-role-trust-policy.json
    rm -f /tmp/compute-environment.json
    rm -f /tmp/job-definition.json
    rm -f /tmp/batch-process.py
    rm -f /tmp/Dockerfile
    
    print_usage_instructions
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi