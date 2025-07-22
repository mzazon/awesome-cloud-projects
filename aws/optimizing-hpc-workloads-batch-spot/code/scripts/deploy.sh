#!/bin/bash

# AWS Batch HPC Workloads with Spot Instances - Deployment Script
# This script deploys the complete infrastructure for optimizing HPC workloads
# using AWS Batch with Spot instances for cost-effective high-performance computing

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions (basic check)
    log "Verifying AWS credentials and basic permissions..."
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        log_error "Unable to retrieve AWS account ID. Please check your credentials."
        exit 1
    fi
    
    log_success "Prerequisites check completed. AWS Account ID: $AWS_ACCOUNT_ID"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_warning "AWS region not set. Using us-east-1 as default."
        export AWS_REGION="us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 7)")
    
    export BUCKET_NAME="hpc-batch-${RANDOM_SUFFIX}"
    export COMPUTE_ENV_NAME="hpc-spot-compute-${RANDOM_SUFFIX}"
    export JOB_QUEUE_NAME="hpc-job-queue-${RANDOM_SUFFIX}"
    export JOB_DEFINITION_NAME="hpc-simulation-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export BUCKET_NAME="${BUCKET_NAME}"
export COMPUTE_ENV_NAME="${COMPUTE_ENV_NAME}"
export JOB_QUEUE_NAME="${JOB_QUEUE_NAME}"
export JOB_DEFINITION_NAME="${JOB_DEFINITION_NAME}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF
    
    log_success "Environment variables set and saved to .env file"
    log "Region: $AWS_REGION"
    log "Account ID: $AWS_ACCOUNT_ID"
    log "Resource suffix: $RANDOM_SUFFIX"
}

# Function to create foundational resources
create_foundational_resources() {
    log "Creating foundational resources..."
    
    # Create S3 bucket for data storage
    log "Creating S3 bucket: $BUCKET_NAME"
    if aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION} 2>/dev/null; then
        log_success "S3 bucket created successfully"
    else
        log_warning "S3 bucket may already exist or creation failed"
    fi
    
    # Create IAM role for Batch service
    log "Creating IAM role for Batch service..."
    aws iam create-role \
        --role-name "AWSBatchServiceRole-${RANDOM_SUFFIX}" \
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
        }' > /dev/null 2>&1 || log_warning "Batch service role may already exist"
    
    # Attach AWS managed policy for Batch service
    aws iam attach-role-policy \
        --role-name "AWSBatchServiceRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole" 2>/dev/null || true
    
    export BATCH_SERVICE_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/AWSBatchServiceRole-${RANDOM_SUFFIX}"
    
    log_success "Foundational resources created"
}

# Function to create IAM roles and instance profiles
create_iam_resources() {
    log "Creating IAM roles and instance profiles..."
    
    # Create IAM role for EC2 instances
    aws iam create-role \
        --role-name "ecsInstanceRole-${RANDOM_SUFFIX}" \
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
        }' > /dev/null 2>&1 || log_warning "ECS instance role may already exist"
    
    # Attach required policies for ECS and Batch functionality
    aws iam attach-role-policy \
        --role-name "ecsInstanceRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role" 2>/dev/null || true
    
    aws iam attach-role-policy \
        --role-name "ecsInstanceRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" 2>/dev/null || true
    
    # Create instance profile
    aws iam create-instance-profile \
        --instance-profile-name "ecsInstanceProfile-${RANDOM_SUFFIX}" > /dev/null 2>&1 || log_warning "Instance profile may already exist"
    
    # Wait a moment for IAM eventual consistency
    sleep 5
    
    aws iam add-role-to-instance-profile \
        --instance-profile-name "ecsInstanceProfile-${RANDOM_SUFFIX}" \
        --role-name "ecsInstanceRole-${RANDOM_SUFFIX}" 2>/dev/null || true
    
    export INSTANCE_PROFILE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:instance-profile/ecsInstanceProfile-${RANDOM_SUFFIX}"
    
    log_success "IAM roles and instance profile created"
}

# Function to create EFS shared storage
create_efs_storage() {
    log "Creating EFS shared storage..."
    
    # Get default VPC information
    export DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text)
    
    if [ "$DEFAULT_VPC_ID" = "None" ] || [ -z "$DEFAULT_VPC_ID" ]; then
        log_error "No default VPC found. Please create a VPC first."
        exit 1
    fi
    
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${DEFAULT_VPC_ID}" \
        --query "Subnets[].SubnetId" --output text | tr '\t' ',')
    
    # Create EFS file system for shared storage
    log "Creating EFS file system..."
    export EFS_ID=$(aws efs create-file-system \
        --performance-mode generalPurpose \
        --throughput-mode provisioned \
        --provisioned-throughput-in-mibps 100 \
        --tags Key=Name,Value="hpc-shared-storage-${RANDOM_SUFFIX}" \
        --query "FileSystemId" --output text)
    
    # Create security group for EFS
    export EFS_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "efs-sg-${RANDOM_SUFFIX}" \
        --description "Security group for EFS file system" \
        --vpc-id ${DEFAULT_VPC_ID} \
        --query "GroupId" --output text)
    
    # Allow NFS traffic from Batch compute instances
    aws ec2 authorize-security-group-ingress \
        --group-id ${EFS_SECURITY_GROUP_ID} \
        --protocol tcp \
        --port 2049 \
        --source-group ${EFS_SECURITY_GROUP_ID} > /dev/null 2>&1 || true
    
    # Save EFS variables to env file
    echo "export EFS_ID=\"${EFS_ID}\"" >> "${SCRIPT_DIR}/.env"
    echo "export EFS_SECURITY_GROUP_ID=\"${EFS_SECURITY_GROUP_ID}\"" >> "${SCRIPT_DIR}/.env"
    echo "export DEFAULT_VPC_ID=\"${DEFAULT_VPC_ID}\"" >> "${SCRIPT_DIR}/.env"
    echo "export SUBNET_IDS=\"${SUBNET_IDS}\"" >> "${SCRIPT_DIR}/.env"
    
    log_success "EFS file system created: $EFS_ID"
}

# Function to create compute environment
create_compute_environment() {
    log "Creating Spot-optimized compute environment..."
    
    # Create security group for Batch compute instances
    export SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "batch-compute-sg-${RANDOM_SUFFIX}" \
        --description "Security group for AWS Batch compute environment" \
        --vpc-id ${DEFAULT_VPC_ID} \
        --query "GroupId" --output text)
    
    # Allow access to EFS from compute instances
    aws ec2 authorize-security-group-ingress \
        --group-id ${SECURITY_GROUP_ID} \
        --protocol tcp \
        --port 2049 \
        --source-group ${EFS_SECURITY_GROUP_ID} > /dev/null 2>&1 || true
    
    # Create compute environment with Spot instance configuration
    log "Creating compute environment with Spot instances..."
    aws batch create-compute-environment \
        --compute-environment-name ${COMPUTE_ENV_NAME} \
        --type MANAGED \
        --state ENABLED \
        --compute-resources '{
            "type": "EC2",
            "allocationStrategy": "SPOT_CAPACITY_OPTIMIZED",
            "minvCpus": 0,
            "maxvCpus": 1000,
            "desiredvCpus": 0,
            "instanceTypes": ["c5.large", "c5.xlarge", "c5.2xlarge", "c4.large", "c4.xlarge", "m5.large", "m5.xlarge"],
            "bidPercentage": 80,
            "ec2Configuration": [{
                "imageType": "ECS_AL2"
            }],
            "subnets": ["'${SUBNET_IDS//,/\",\"}'"],
            "securityGroupIds": ["'${SECURITY_GROUP_ID}'"],
            "instanceRole": "'${INSTANCE_PROFILE_ARN}'"
        }' \
        --service-role ${BATCH_SERVICE_ROLE_ARN} > /dev/null
    
    # Save security group to env file
    echo "export SECURITY_GROUP_ID=\"${SECURITY_GROUP_ID}\"" >> "${SCRIPT_DIR}/.env"
    
    log_success "Spot-optimized compute environment created"
}

# Function to create job queue
create_job_queue() {
    log "Creating job queue..."
    
    # Wait for compute environment to become VALID
    log "Waiting for compute environment to become valid..."
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        local status=$(aws batch describe-compute-environments \
            --compute-environments ${COMPUTE_ENV_NAME} \
            --query "computeEnvironments[0].status" --output text)
        
        if [ "$status" = "VALID" ]; then
            break
        fi
        
        log "Compute environment status: $status. Waiting..."
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    if [ $wait_time -ge $max_wait ]; then
        log_error "Timeout waiting for compute environment to become valid"
        exit 1
    fi
    
    # Create job queue linked to the compute environment
    aws batch create-job-queue \
        --job-queue-name ${JOB_QUEUE_NAME} \
        --state ENABLED \
        --priority 1 \
        --compute-environment-order '[{
            "order": 1,
            "computeEnvironment": "'${COMPUTE_ENV_NAME}'"
        }]' > /dev/null
    
    log_success "Job queue created and linked to compute environment"
}

# Function to register job definition
register_job_definition() {
    log "Registering HPC job definition..."
    
    # Create job definition for HPC simulation workload
    aws batch register-job-definition \
        --job-definition-name ${JOB_DEFINITION_NAME} \
        --type container \
        --container-properties '{
            "image": "busybox",
            "vcpus": 2,
            "memory": 4096,
            "jobRoleArn": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/ecsInstanceRole-'${RANDOM_SUFFIX}'",
            "command": [
                "sh", "-c",
                "echo Starting HPC simulation at $(date); sleep 300; echo Simulation completed at $(date)"
            ],
            "mountPoints": [{
                "sourceVolume": "efs-storage",
                "containerPath": "/shared",
                "readOnly": false
            }],
            "volumes": [{
                "name": "efs-storage",
                "efsVolumeConfiguration": {
                    "fileSystemId": "'${EFS_ID}'"
                }
            }],
            "environment": [
                {"name": "S3_BUCKET", "value": "'${BUCKET_NAME}'"},
                {"name": "AWS_DEFAULT_REGION", "value": "'${AWS_REGION}'"}
            ]
        }' \
        --retry-strategy '{
            "attempts": 3
        }' \
        --timeout '{"attemptDurationSeconds": 3600}' > /dev/null
    
    log_success "HPC job definition registered with fault tolerance"
}

# Function to setup CloudWatch monitoring
setup_monitoring() {
    log "Setting up CloudWatch monitoring..."
    
    # Create CloudWatch log group for Batch jobs
    aws logs create-log-group \
        --log-group-name "/aws/batch/job" \
        --retention-in-days 7 > /dev/null 2>&1 || log_warning "Log group may already exist"
    
    # Create custom metric filter for cost tracking
    aws logs put-metric-filter \
        --log-group-name "/aws/batch/job" \
        --filter-name "SpotInstanceSavings" \
        --filter-pattern "[timestamp, level=\"INFO\", message=\"*SPOT_SAVINGS*\"]" \
        --metric-transformations \
            metricName=SpotSavings,metricNamespace=HPC/Batch,metricValue=1 > /dev/null 2>&1 || true
    
    # Set up CloudWatch alarm for failed jobs
    aws cloudwatch put-metric-alarm \
        --alarm-name "HPC-Batch-FailedJobs-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when Batch jobs fail" \
        --metric-name FailedJobs \
        --namespace AWS/Batch \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --dimensions Name=JobQueue,Value=${JOB_QUEUE_NAME} > /dev/null 2>&1 || true
    
    log_success "CloudWatch monitoring configured"
}

# Function to run validation tests
run_validation() {
    log "Running validation tests..."
    
    # Test 1: Verify compute environment status
    local compute_status=$(aws batch describe-compute-environments \
        --compute-environments ${COMPUTE_ENV_NAME} \
        --query "computeEnvironments[0].status" --output text)
    
    if [ "$compute_status" = "VALID" ]; then
        log_success "Compute environment validation: PASSED"
    else
        log_error "Compute environment validation: FAILED (Status: $compute_status)"
    fi
    
    # Test 2: Verify job queue status
    local queue_status=$(aws batch describe-job-queues \
        --job-queues ${JOB_QUEUE_NAME} \
        --query "jobQueues[0].state" --output text)
    
    if [ "$queue_status" = "ENABLED" ]; then
        log_success "Job queue validation: PASSED"
    else
        log_error "Job queue validation: FAILED (Status: $queue_status)"
    fi
    
    # Test 3: Verify EFS status
    local efs_status=$(aws efs describe-file-systems \
        --file-system-id ${EFS_ID} \
        --query "FileSystems[0].LifeCycleState" --output text)
    
    if [ "$efs_status" = "available" ]; then
        log_success "EFS validation: PASSED"
    else
        log_error "EFS validation: FAILED (Status: $efs_status)"
    fi
    
    # Test 4: Submit test job
    log "Submitting test job..."
    local job_id=$(aws batch submit-job \
        --job-name "hpc-test-job-$(date +%s)" \
        --job-queue ${JOB_QUEUE_NAME} \
        --job-definition ${JOB_DEFINITION_NAME} \
        --query "jobId" --output text)
    
    if [ ! -z "$job_id" ]; then
        log_success "Test job submitted successfully: $job_id"
        echo "export TEST_JOB_ID=\"${job_id}\"" >> "${SCRIPT_DIR}/.env"
    else
        log_error "Failed to submit test job"
    fi
}

# Function to display deployment summary
show_deployment_summary() {
    log_success "🎉 Deployment completed successfully!"
    echo ""
    echo "======================================"
    echo "       DEPLOYMENT SUMMARY"
    echo "======================================"
    echo "AWS Region: $AWS_REGION"
    echo "S3 Bucket: $BUCKET_NAME"
    echo "Compute Environment: $COMPUTE_ENV_NAME"
    echo "Job Queue: $JOB_QUEUE_NAME"
    echo "Job Definition: $JOB_DEFINITION_NAME"
    echo "EFS File System: $EFS_ID"
    echo ""
    echo "Next Steps:"
    echo "1. Submit HPC jobs to the queue: $JOB_QUEUE_NAME"
    echo "2. Monitor costs and performance in CloudWatch"
    echo "3. Use shared storage at: /shared (in containers)"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo "======================================"
}

# Main execution
main() {
    # Get script directory for relative paths
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    log "Starting AWS Batch HPC deployment..."
    
    check_prerequisites
    setup_environment
    create_foundational_resources
    create_iam_resources
    create_efs_storage
    create_compute_environment
    create_job_queue
    register_job_definition
    setup_monitoring
    run_validation
    show_deployment_summary
    
    log_success "Deployment script completed successfully!"
}

# Error handling
trap 'log_error "Script failed at line $LINENO. Check the error above."' ERR

# Run main function
main "$@"