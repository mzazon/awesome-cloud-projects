#!/bin/bash

# AWS Batch Processing Workloads Deployment Script
# This script deploys the AWS Batch infrastructure for batch processing workloads
# Prerequisites: AWS CLI v2, Docker, and appropriate IAM permissions

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Parse command line options
DRY_RUN=false
SKIP_DOCKER_BUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-docker-build)
            SKIP_DOCKER_BUILD=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run            Show what would be deployed without making changes"
            echo "  --skip-docker-build  Skip Docker image build (use existing image)"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "This script creates a complete AWS Batch infrastructure including:"
            echo "  - IAM roles and instance profiles"
            echo "  - ECR repository and container image"
            echo "  - Compute environment and job queue"
            echo "  - Job definitions and monitoring"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION" | cut -d. -f1) -lt 2 ]]; then
        error "AWS CLI version 2.x is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker to build container images."
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid. Please configure AWS CLI."
        exit 1
    fi
    
    success "All prerequisites met"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No default region configured, using us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export BATCH_COMPUTE_ENV_NAME="batch-compute-env-${RANDOM_SUFFIX}"
    export BATCH_JOB_QUEUE_NAME="batch-job-queue-${RANDOM_SUFFIX}"
    export BATCH_JOB_DEFINITION_NAME="batch-job-def-${RANDOM_SUFFIX}"
    export ECR_REPO_NAME="batch-processing-${RANDOM_SUFFIX}"
    export BATCH_SERVICE_ROLE_NAME="AWSBatchServiceRole-${RANDOM_SUFFIX}"
    export BATCH_INSTANCE_PROFILE_NAME="ecsInstanceProfile-${RANDOM_SUFFIX}"
    export BATCH_INSTANCE_ROLE_NAME="ecsInstanceRole-${RANDOM_SUFFIX}"
    export SECURITY_GROUP_NAME="batch-sg-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > .batch_deployment_vars << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export BATCH_COMPUTE_ENV_NAME="${BATCH_COMPUTE_ENV_NAME}"
export BATCH_JOB_QUEUE_NAME="${BATCH_JOB_QUEUE_NAME}"
export BATCH_JOB_DEFINITION_NAME="${BATCH_JOB_DEFINITION_NAME}"
export ECR_REPO_NAME="${ECR_REPO_NAME}"
export BATCH_SERVICE_ROLE_NAME="${BATCH_SERVICE_ROLE_NAME}"
export BATCH_INSTANCE_PROFILE_NAME="${BATCH_INSTANCE_PROFILE_NAME}"
export BATCH_INSTANCE_ROLE_NAME="${BATCH_INSTANCE_ROLE_NAME}"
export SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME}"
EOF
    
    success "Environment variables configured"
    log "Using AWS Region: $AWS_REGION"
    log "Using AWS Account ID: $AWS_ACCOUNT_ID"
}

# Function to create IAM roles
create_iam_roles() {
    log "Creating IAM roles for AWS Batch..."
    
    # Create IAM service role for AWS Batch
    log "Creating Batch service role: $BATCH_SERVICE_ROLE_NAME"
    aws iam create-role \
        --role-name ${BATCH_SERVICE_ROLE_NAME} \
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
        }' 2>/dev/null || warning "Batch service role may already exist"
    
    # Attach the AWS managed policy for Batch service
    aws iam attach-role-policy \
        --role-name ${BATCH_SERVICE_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole
    
    # Create IAM role for ECS instance profile
    log "Creating ECS instance role: $BATCH_INSTANCE_ROLE_NAME"
    aws iam create-role \
        --role-name ${BATCH_INSTANCE_ROLE_NAME} \
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
        }' 2>/dev/null || warning "ECS instance role may already exist"
    
    # Attach the AWS managed policy for ECS instance
    aws iam attach-role-policy \
        --role-name ${BATCH_INSTANCE_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role
    
    # Create instance profile and add role
    log "Creating instance profile: $BATCH_INSTANCE_PROFILE_NAME"
    aws iam create-instance-profile \
        --instance-profile-name ${BATCH_INSTANCE_PROFILE_NAME} 2>/dev/null || warning "Instance profile may already exist"
    
    aws iam add-role-to-instance-profile \
        --instance-profile-name ${BATCH_INSTANCE_PROFILE_NAME} \
        --role-name ${BATCH_INSTANCE_ROLE_NAME} 2>/dev/null || true
    
    success "IAM roles created successfully"
}

# Function to setup networking
setup_networking() {
    log "Setting up networking components..."
    
    # Get default VPC and subnet information
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [ "$VPC_ID" = "None" ] || [ "$VPC_ID" = "null" ]; then
        error "No default VPC found. Please create a VPC first."
        exit 1
    fi
    
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')
    
    # Create security group for Batch compute environment
    log "Creating security group: $SECURITY_GROUP_NAME"
    export SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name ${SECURITY_GROUP_NAME} \
        --description "Security group for AWS Batch compute environment" \
        --vpc-id ${VPC_ID} \
        --query 'GroupId' --output text 2>/dev/null || \
        aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=${SECURITY_GROUP_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
            --query 'SecurityGroups[0].GroupId' --output text)
    
    # Update environment file with networking info
    cat >> .batch_deployment_vars << EOF
export VPC_ID="${VPC_ID}"
export SUBNET_IDS="${SUBNET_IDS}"
export SECURITY_GROUP_ID="${SECURITY_GROUP_ID}"
EOF
    
    success "Networking setup complete"
    log "Using VPC: $VPC_ID"
    log "Using Security Group: $SECURITY_GROUP_ID"
}

# Function to create ECR repository and build container image
create_container_image() {
    log "Setting up ECR repository and building container image..."
    
    # Create ECR repository
    log "Creating ECR repository: $ECR_REPO_NAME"
    aws ecr create-repository \
        --repository-name ${ECR_REPO_NAME} \
        --image-scanning-configuration scanOnPush=true 2>/dev/null || warning "ECR repository may already exist"
    
    # Get ECR login token
    log "Logging into ECR..."
    aws ecr get-login-password --region ${AWS_REGION} | \
        docker login --username AWS \
        --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
    
    # Create temporary directory for Docker build
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Create Dockerfile
    log "Creating Dockerfile..."
    cat > Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Install required packages
RUN pip install numpy pandas boto3

# Copy processing script
COPY batch_processor.py .

# Run the batch processing script
CMD ["python", "batch_processor.py"]
EOF

    # Create sample batch processing script
    log "Creating batch processing application..."
    cat > batch_processor.py << 'EOF'
#!/usr/bin/env python3
import os
import time
import random
import numpy as np
import pandas as pd
from datetime import datetime

def main():
    # Get job parameters from environment variables
    job_id = os.environ.get('AWS_BATCH_JOB_ID', 'local-test')
    job_name = os.environ.get('AWS_BATCH_JOB_NAME', 'batch-job')
    
    print(f"Starting batch job: {job_name} (ID: {job_id})")
    print(f"Timestamp: {datetime.now()}")
    
    # Simulate data processing workload
    print("Generating sample data...")
    data_size = int(os.environ.get('DATA_SIZE', '1000'))
    data = np.random.randn(data_size, 5)
    df = pd.DataFrame(data, columns=['A', 'B', 'C', 'D', 'E'])
    
    # Simulate processing time
    processing_time = int(os.environ.get('PROCESSING_TIME', '60'))
    print(f"Processing {data_size} records for {processing_time} seconds...")
    
    # Perform some calculations
    results = []
    for i in range(processing_time):
        # Simulate complex calculations
        result = df.mean().sum() + random.random()
        results.append(result)
        time.sleep(1)
        
        if i % 10 == 0:
            print(f"Progress: {i+1}/{processing_time} seconds")
    
    # Output results
    final_result = sum(results) / len(results)
    print(f"Processing complete! Final result: {final_result:.6f}")
    print(f"Job {job_name} finished successfully at {datetime.now()}")

if __name__ == "__main__":
    main()
EOF

    # Build and tag the Docker image
    log "Building Docker image..."
    docker build -t ${ECR_REPO_NAME} .
    
    # Tag image for ECR
    docker tag ${ECR_REPO_NAME}:latest \
        ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:latest
    
    # Push image to ECR
    log "Pushing image to ECR..."
    docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:latest
    
    export CONTAINER_IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:latest"
    
    # Update environment file with container image URI
    echo "export CONTAINER_IMAGE_URI=\"${CONTAINER_IMAGE_URI}\"" >> .batch_deployment_vars
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    
    success "Container image created and pushed to ECR"
    log "Container image URI: $CONTAINER_IMAGE_URI"
}

# Function to create AWS Batch compute environment
create_compute_environment() {
    log "Creating AWS Batch compute environment..."
    
    # Wait for instance profile to be available
    log "Waiting for instance profile to be available..."
    sleep 30
    
    # Create managed compute environment
    log "Creating compute environment: $BATCH_COMPUTE_ENV_NAME"
    aws batch create-compute-environment \
        --compute-environment-name ${BATCH_COMPUTE_ENV_NAME} \
        --type MANAGED \
        --state ENABLED \
        --service-role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${BATCH_SERVICE_ROLE_NAME} \
        --compute-resources "type=EC2,minvCpus=0,maxvCpus=100,desiredvCpus=0,instanceTypes=optimal,subnets=${SUBNET_IDS},securityGroupIds=${SECURITY_GROUP_ID},instanceRole=arn:aws:iam::${AWS_ACCOUNT_ID}:instance-profile/${BATCH_INSTANCE_PROFILE_NAME},bidPercentage=50,ec2Configuration=[{imageType=ECS_AL2}]" \
        2>/dev/null || warning "Compute environment may already exist"
    
    # Wait for compute environment to be ready
    log "Waiting for compute environment to be ready..."
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        STATUS=$(aws batch describe-compute-environments \
            --compute-environments ${BATCH_COMPUTE_ENV_NAME} \
            --query 'computeEnvironments[0].status' --output text)
        
        if [ "$STATUS" = "VALID" ]; then
            success "Compute environment is ready: $BATCH_COMPUTE_ENV_NAME"
            break
        elif [ "$STATUS" = "INVALID" ]; then
            error "Compute environment creation failed"
            exit 1
        else
            log "Compute environment status: $STATUS (attempt $attempt/$max_attempts)"
            sleep 30
            ((attempt++))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "Timeout waiting for compute environment to be ready"
        exit 1
    fi
}

# Function to create job queue
create_job_queue() {
    log "Creating AWS Batch job queue..."
    
    # Create job queue
    log "Creating job queue: $BATCH_JOB_QUEUE_NAME"
    aws batch create-job-queue \
        --job-queue-name ${BATCH_JOB_QUEUE_NAME} \
        --state ENABLED \
        --priority 1 \
        --compute-environment-order "order=1,computeEnvironment=${BATCH_COMPUTE_ENV_NAME}" \
        2>/dev/null || warning "Job queue may already exist"
    
    # Wait for job queue to be ready
    log "Waiting for job queue to be ready..."
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        STATUS=$(aws batch describe-job-queues \
            --job-queues ${BATCH_JOB_QUEUE_NAME} \
            --query 'jobQueues[0].status' --output text)
        
        if [ "$STATUS" = "VALID" ]; then
            success "Job queue is ready: $BATCH_JOB_QUEUE_NAME"
            break
        elif [ "$STATUS" = "INVALID" ]; then
            error "Job queue creation failed"
            exit 1
        else
            log "Job queue status: $STATUS (attempt $attempt/$max_attempts)"
            sleep 15
            ((attempt++))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "Timeout waiting for job queue to be ready"
        exit 1
    fi
}

# Function to create job definition
create_job_definition() {
    log "Creating AWS Batch job definition..."
    
    # Create CloudWatch log group first
    log "Creating CloudWatch log group..."
    aws logs create-log-group \
        --log-group-name /aws/batch/job \
        --retention-in-days 30 2>/dev/null || warning "Log group may already exist"
    
    # Create job definition
    log "Creating job definition: $BATCH_JOB_DEFINITION_NAME"
    aws batch register-job-definition \
        --job-definition-name ${BATCH_JOB_DEFINITION_NAME} \
        --type container \
        --container-properties "{
            \"image\": \"${CONTAINER_IMAGE_URI}\",
            \"vcpus\": 1,
            \"memory\": 512,
            \"environment\": [
                {\"name\": \"DATA_SIZE\", \"value\": \"5000\"},
                {\"name\": \"PROCESSING_TIME\", \"value\": \"120\"}
            ],
            \"logConfiguration\": {
                \"logDriver\": \"awslogs\",
                \"options\": {
                    \"awslogs-group\": \"/aws/batch/job\",
                    \"awslogs-region\": \"${AWS_REGION}\"
                }
            }
        }" \
        --timeout "attemptDurationSeconds=3600" > /dev/null
    
    # Get job definition ARN
    export JOB_DEFINITION_ARN=$(aws batch describe-job-definitions \
        --job-definition-name ${BATCH_JOB_DEFINITION_NAME} \
        --status ACTIVE \
        --query 'jobDefinitions[0].jobDefinitionArn' --output text)
    
    # Update environment file with job definition ARN
    echo "export JOB_DEFINITION_ARN=\"${JOB_DEFINITION_ARN}\"" >> .batch_deployment_vars
    
    success "Job definition created: $JOB_DEFINITION_ARN"
}

# Function to create monitoring alarms
create_monitoring() {
    log "Setting up monitoring and alerts..."
    
    # Create CloudWatch alarm for failed jobs
    aws cloudwatch put-metric-alarm \
        --alarm-name "BatchJobFailures-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when batch jobs fail" \
        --metric-name FailedJobs \
        --namespace AWS/Batch \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --dimensions "Name=JobQueue,Value=${BATCH_JOB_QUEUE_NAME}" 2>/dev/null || warning "Alarm may already exist"
    
    # Create alarm for high job queue utilization
    aws cloudwatch put-metric-alarm \
        --alarm-name "BatchQueueUtilization-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when job queue has high utilization" \
        --metric-name QueueUtilization \
        --namespace AWS/Batch \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions "Name=JobQueue,Value=${BATCH_JOB_QUEUE_NAME}" 2>/dev/null || warning "Alarm may already exist"
    
    # Update environment file with alarm names
    cat >> .batch_deployment_vars << EOF
export ALARM_FAILURES="BatchJobFailures-${RANDOM_SUFFIX}"
export ALARM_UTILIZATION="BatchQueueUtilization-${RANDOM_SUFFIX}"
EOF
    
    success "Monitoring and alerts configured"
}

# Function to test the deployment
test_deployment() {
    log "Testing the deployment..."
    
    # Verify compute environment status
    log "Verifying compute environment status..."
    COMPUTE_STATUS=$(aws batch describe-compute-environments \
        --compute-environments ${BATCH_COMPUTE_ENV_NAME} \
        --query 'computeEnvironments[0].status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$COMPUTE_STATUS" = "VALID" ]; then
        success "Compute environment is valid: $BATCH_COMPUTE_ENV_NAME"
    else
        error "Compute environment validation failed. Status: $COMPUTE_STATUS"
        exit 1
    fi
    
    # Verify job queue status
    log "Verifying job queue status..."
    QUEUE_STATUS=$(aws batch describe-job-queues \
        --job-queues ${BATCH_JOB_QUEUE_NAME} \
        --query 'jobQueues[0].status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$QUEUE_STATUS" = "VALID" ]; then
        success "Job queue is valid: $BATCH_JOB_QUEUE_NAME"
    else
        error "Job queue validation failed. Status: $QUEUE_STATUS"
        exit 1
    fi
    
    # Submit a test job
    log "Submitting test job..."
    TEST_JOB_ID=$(aws batch submit-job \
        --job-name "deployment-test-job" \
        --job-queue ${BATCH_JOB_QUEUE_NAME} \
        --job-definition ${BATCH_JOB_DEFINITION_NAME} \
        --parameters "DATA_SIZE=100,PROCESSING_TIME=10" \
        --query 'jobId' --output text)
    
    if [ -n "$TEST_JOB_ID" ]; then
        success "Test job submitted successfully: $TEST_JOB_ID"
        echo "export TEST_JOB_ID=\"${TEST_JOB_ID}\"" >> .batch_deployment_vars
        log "Monitor job status with: aws batch describe-jobs --jobs $TEST_JOB_ID"
        
        # Wait a moment and check initial job status
        log "Checking initial job status..."
        sleep 10
        JOB_STATUS=$(aws batch describe-jobs --jobs ${TEST_JOB_ID} \
            --query 'jobs[0].status' --output text 2>/dev/null || echo "UNKNOWN")
        log "Current job status: $JOB_STATUS"
        
        # Test array job submission
        log "Submitting test array job..."
        ARRAY_JOB_ID=$(aws batch submit-job \
            --job-name "deployment-array-test-job" \
            --job-queue ${BATCH_JOB_QUEUE_NAME} \
            --job-definition ${BATCH_JOB_DEFINITION_NAME} \
            --array-properties "size=3" \
            --parameters "DATA_SIZE=50,PROCESSING_TIME=5" \
            --query 'jobId' --output text)
        
        if [ -n "$ARRAY_JOB_ID" ]; then
            success "Test array job submitted successfully: $ARRAY_JOB_ID"
            echo "export ARRAY_JOB_ID=\"${ARRAY_JOB_ID}\"" >> .batch_deployment_vars
            log "Array job will create 3 parallel executions"
        else
            warning "Failed to submit test array job"
        fi
        
    else
        error "Failed to submit test job"
        exit 1
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account ID: $AWS_ACCOUNT_ID"
    echo ""
    echo "Created Resources:"
    echo "- Compute Environment: $BATCH_COMPUTE_ENV_NAME"
    echo "- Job Queue: $BATCH_JOB_QUEUE_NAME"
    echo "- Job Definition: $BATCH_JOB_DEFINITION_NAME"
    echo "- ECR Repository: $ECR_REPO_NAME"
    echo "- Container Image: $CONTAINER_IMAGE_URI"
    echo "- Security Group: $SECURITY_GROUP_ID"
    echo ""
    echo "IAM Resources:"
    echo "- Batch Service Role: $BATCH_SERVICE_ROLE_NAME"
    echo "- Instance Profile: $BATCH_INSTANCE_PROFILE_NAME"
    echo "- Instance Role: $BATCH_INSTANCE_ROLE_NAME"
    echo ""
    echo "Monitoring:"
    echo "- CloudWatch Log Group: /aws/batch/job"
    echo "- Job Failures Alarm: BatchJobFailures-${RANDOM_SUFFIX}"
    echo "- Queue Utilization Alarm: BatchQueueUtilization-${RANDOM_SUFFIX}"
    echo ""
    echo "Next Steps:"
    echo "1. Submit batch jobs using the job queue: $BATCH_JOB_QUEUE_NAME"
    echo "2. Monitor jobs in the AWS Batch console"
    echo "3. View logs in CloudWatch Logs: /aws/batch/job"
    if [ -n "${TEST_JOB_ID:-}" ]; then
        echo "4. Monitor test job: aws batch describe-jobs --jobs $TEST_JOB_ID"
        echo "5. View test job logs: aws logs get-log-events --log-group-name /aws/batch/job --log-stream-name \$(aws batch describe-jobs --jobs $TEST_JOB_ID --query 'jobs[0].container.logStreamName' --output text)"
    fi
    echo "6. Clean up resources when finished using: ./destroy.sh"
    echo ""
    echo "Example Commands:"
    echo "# Submit a custom job"
    echo "aws batch submit-job \\"
    echo "  --job-name my-batch-job \\"
    echo "  --job-queue $BATCH_JOB_QUEUE_NAME \\"
    echo "  --job-definition $BATCH_JOB_DEFINITION_NAME \\"
    echo "  --parameters DATA_SIZE=2000,PROCESSING_TIME=60"
    echo ""
    echo "# Submit an array job for parallel processing"
    echo "aws batch submit-job \\"
    echo "  --job-name my-array-job \\"
    echo "  --job-queue $BATCH_JOB_QUEUE_NAME \\"
    echo "  --job-definition $BATCH_JOB_DEFINITION_NAME \\"
    echo "  --array-properties size=5 \\"
    echo "  --parameters DATA_SIZE=1000,PROCESSING_TIME=30"
    echo ""
    success "Deployment completed successfully!"
}

# Function to handle script interruption
cleanup_on_error() {
    error "Deployment interrupted. You may need to manually clean up partial resources."
    error "Use the destroy.sh script to clean up any created resources."
    exit 1
}

# Trap interruption signals
trap cleanup_on_error INT TERM

# Main deployment function
main() {
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN MODE - No resources will be created"
        echo "Would deploy AWS Batch infrastructure with the following components:"
        echo "- IAM service role and instance profile for AWS Batch"
        echo "- Security group for compute environment" 
        echo "- ECR repository and container image (unless --skip-docker-build)"
        echo "- Managed compute environment with EC2 instances"
        echo "- Job queue with priority 1"
        echo "- Container job definition with CloudWatch logging"
        echo "- CloudWatch alarms for monitoring"
        echo "- Test job submission for validation"
        echo ""
        echo "To proceed with actual deployment, run without --dry-run flag"
        exit 0
    fi
    
    log "Starting AWS Batch deployment..."
    
    check_prerequisites
    setup_environment
    create_iam_roles
    setup_networking
    
    if [ "$SKIP_DOCKER_BUILD" = false ]; then
        create_container_image
    else
        log "Skipping Docker image build as requested"
        # Assume existing image URI from environment or use a default
        if [ -z "${CONTAINER_IMAGE_URI:-}" ]; then
            export CONTAINER_IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:latest"
            warning "Using assumed container image URI: $CONTAINER_IMAGE_URI"
            warning "Make sure this image exists in ECR"
        fi
    fi
    
    create_compute_environment
    create_job_queue
    create_job_definition
    create_monitoring
    test_deployment
    display_summary
}

# Run main function
main "$@"