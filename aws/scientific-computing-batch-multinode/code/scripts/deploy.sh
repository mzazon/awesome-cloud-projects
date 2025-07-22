#!/bin/bash

#####################################################################
# AWS Batch Multi-Node Scientific Computing Deployment Script
#####################################################################
# This script deploys a complete AWS Batch environment for distributed
# scientific computing with multi-node parallel job support.
#
# Features:
# - MPI-enabled compute environment
# - EFS shared storage for data processing
# - ECR container registry with scientific computing image
# - Enhanced networking for low-latency MPI communication
# - Comprehensive monitoring and logging setup
#
# Prerequisites:
# - AWS CLI v2 configured with appropriate permissions
# - Docker installed for container image building
# - Permissions for Batch, EC2, ECR, EFS, VPC, and IAM
#
# Usage: ./deploy.sh [--region REGION] [--cluster-name NAME] [--node-count COUNT]
#####################################################################

set -euo pipefail

# Default configuration
DEFAULT_REGION="us-east-1"
DEFAULT_CLUSTER_NAME="sci-computing-$(date +%s | tail -c 7)"
DEFAULT_NODE_COUNT=2
DEFAULT_INSTANCE_TYPES="c5.large,c5.xlarge,c5.2xlarge"
DEFAULT_MAX_VCPUS=256

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
RESOURCES_FILE="${SCRIPT_DIR}/deployed-resources.txt"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#####################################################################
# Utility Functions
#####################################################################

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

cleanup_on_error() {
    error "Deployment failed. Starting cleanup of partially created resources..."
    if [[ -f "$RESOURCES_FILE" ]]; then
        source "$RESOURCES_FILE" 2>/dev/null || true
        "${SCRIPT_DIR}/destroy.sh" --force --resource-file "$RESOURCES_FILE" || true
    fi
    exit 1
}

save_resource() {
    echo "export $1=\"$2\"" >> "$RESOURCES_FILE"
}

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
        error "AWS CLI v2 or higher is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker to build container images."
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check required permissions (basic check)
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    if [[ -z "$ACCOUNT_ID" ]]; then
        error "Unable to retrieve AWS account ID. Check your credentials."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AWS Batch multi-node scientific computing environment.

OPTIONS:
    --region REGION          AWS region (default: $DEFAULT_REGION)
    --cluster-name NAME      Cluster name prefix (default: auto-generated)
    --node-count COUNT       Default node count for jobs (default: $DEFAULT_NODE_COUNT)
    --instance-types TYPES   Comma-separated instance types (default: $DEFAULT_INSTANCE_TYPES)
    --max-vcpus COUNT        Maximum vCPUs for compute environment (default: $DEFAULT_MAX_VCPUS)
    --skip-container-build   Skip building and pushing container image
    --dry-run               Show what would be created without actually creating
    --help                  Show this help message

EXAMPLES:
    $0
    $0 --region us-west-2 --cluster-name my-hpc-cluster
    $0 --node-count 4 --max-vcpus 512
    $0 --instance-types "c5.2xlarge,c5.4xlarge" --skip-container-build

EOF
}

#####################################################################
# Main Deployment Functions
#####################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --node-count)
                NODE_COUNT="$2"
                shift 2
                ;;
            --instance-types)
                INSTANCE_TYPES="$2"
                shift 2
                ;;
            --max-vcpus)
                MAX_VCPUS="$2"
                shift 2
                ;;
            --skip-container-build)
                SKIP_CONTAINER_BUILD="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Set defaults
    AWS_REGION="${AWS_REGION:-$DEFAULT_REGION}"
    CLUSTER_NAME="${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}"
    NODE_COUNT="${NODE_COUNT:-$DEFAULT_NODE_COUNT}"
    INSTANCE_TYPES="${INSTANCE_TYPES:-$DEFAULT_INSTANCE_TYPES}"
    MAX_VCPUS="${MAX_VCPUS:-$DEFAULT_MAX_VCPUS}"
    SKIP_CONTAINER_BUILD="${SKIP_CONTAINER_BUILD:-false}"
    DRY_RUN="${DRY_RUN:-false}"
}

initialize_environment() {
    log "Initializing deployment environment..."
    
    # Set AWS region
    export AWS_DEFAULT_REGION="$AWS_REGION"
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    save_resource "AWS_ACCOUNT_ID" "$AWS_ACCOUNT_ID"
    save_resource "AWS_REGION" "$AWS_REGION"
    save_resource "CLUSTER_NAME" "$CLUSTER_NAME"
    
    # Generate resource names
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    JOB_QUEUE_NAME="scientific-queue-${RANDOM_SUFFIX}"
    COMPUTE_ENV_NAME="sci-compute-env-${RANDOM_SUFFIX}"
    ECR_REPO_NAME="scientific-mpi-${RANDOM_SUFFIX}"
    EFS_NAME="sci-data-${RANDOM_SUFFIX}"
    VPC_NAME="sci-vpc-${RANDOM_SUFFIX}"
    
    # Save all resource names
    save_resource "JOB_QUEUE_NAME" "$JOB_QUEUE_NAME"
    save_resource "COMPUTE_ENV_NAME" "$COMPUTE_ENV_NAME"
    save_resource "ECR_REPO_NAME" "$ECR_REPO_NAME"
    save_resource "EFS_NAME" "$EFS_NAME"
    save_resource "VPC_NAME" "$VPC_NAME"
    save_resource "RANDOM_SUFFIX" "$RANDOM_SUFFIX"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN MODE - No resources will be created"
        info "Would create cluster: $CLUSTER_NAME"
        info "Would use region: $AWS_REGION"
        info "Would create resources with suffix: $RANDOM_SUFFIX"
        exit 0
    fi
    
    log "Environment initialized successfully"
}

create_networking() {
    log "Creating networking infrastructure..."
    
    # Create VPC
    info "Creating VPC: $VPC_NAME"
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}},{Key=Project,Value=scientific-computing}]" \
        --query 'Vpc.VpcId' --output text)
    save_resource "VPC_ID" "$VPC_ID"
    
    # Enable DNS hostnames
    aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
    aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support
    
    # Create subnet
    info "Creating subnet in VPC: $VPC_ID"
    SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-subnet},{Key=Project,Value=scientific-computing}]" \
        --query 'Subnet.SubnetId' --output text)
    save_resource "SUBNET_ID" "$SUBNET_ID"
    
    # Create internet gateway
    info "Creating internet gateway"
    IGW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw},{Key=Project,Value=scientific-computing}]" \
        --query 'InternetGateway.InternetGatewayId' --output text)
    save_resource "IGW_ID" "$IGW_ID"
    
    # Attach internet gateway to VPC
    aws ec2 attach-internet-gateway \
        --internet-gateway-id "$IGW_ID" \
        --vpc-id "$VPC_ID"
    
    # Configure route table
    info "Configuring routing"
    ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'RouteTables[0].RouteTableId' --output text)
    save_resource "ROUTE_TABLE_ID" "$ROUTE_TABLE_ID"
    
    aws ec2 create-route \
        --route-table-id "$ROUTE_TABLE_ID" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "$IGW_ID"
    
    # Enable auto-assign public IPs
    aws ec2 modify-subnet-attribute \
        --subnet-id "$SUBNET_ID" \
        --map-public-ip-on-launch
    
    # Create security group
    info "Creating security group for MPI communication"
    SG_ID=$(aws ec2 create-security-group \
        --group-name "${CLUSTER_NAME}-batch-sg" \
        --description "Security group for multi-node Batch jobs with MPI" \
        --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${CLUSTER_NAME}-batch-sg},{Key=Project,Value=scientific-computing}]" \
        --query 'GroupId' --output text)
    save_resource "SG_ID" "$SG_ID"
    
    # Configure security group rules
    info "Configuring security group rules"
    
    # Allow all traffic within security group for MPI communication
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol all \
        --source-group "$SG_ID" || warn "Self-referencing rule may already exist"
    
    # Allow SSH access for debugging
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 || warn "SSH rule may already exist"
    
    # Allow EFS NFS traffic
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 2049 \
        --source-group "$SG_ID" || warn "EFS rule may already exist"
    
    log "Networking infrastructure created successfully"
}

create_efs_storage() {
    log "Creating EFS shared storage..."
    
    # Create EFS filesystem
    info "Creating EFS filesystem: $EFS_NAME"
    EFS_ID=$(aws efs create-file-system \
        --creation-token "${EFS_NAME}-token" \
        --performance-mode generalPurpose \
        --throughput-mode provisioned \
        --provisioned-throughput-in-mibps 100 \
        --encrypted \
        --tags "Key=Name,Value=${EFS_NAME}" "Key=Project,Value=scientific-computing" \
        --query 'FileSystemId' --output text)
    save_resource "EFS_ID" "$EFS_ID"
    
    # Wait for filesystem to be available
    info "Waiting for EFS filesystem to become available..."
    aws efs wait file-system-available --file-system-id "$EFS_ID"
    
    # Create mount target
    info "Creating EFS mount target"
    MOUNT_TARGET_ID=$(aws efs create-mount-target \
        --file-system-id "$EFS_ID" \
        --subnet-id "$SUBNET_ID" \
        --security-groups "$SG_ID" \
        --query 'MountTargetId' --output text)
    save_resource "MOUNT_TARGET_ID" "$MOUNT_TARGET_ID"
    
    # Wait for mount target to be available
    info "Waiting for EFS mount target to become available..."
    aws efs wait mount-target-available --mount-target-id "$MOUNT_TARGET_ID"
    
    log "EFS shared storage created successfully: $EFS_ID"
}

create_container_image() {
    if [[ "$SKIP_CONTAINER_BUILD" == "true" ]]; then
        log "Skipping container image build as requested"
        return 0
    fi
    
    log "Creating ECR repository and building MPI container image..."
    
    # Create ECR repository
    info "Creating ECR repository: $ECR_REPO_NAME"
    ECR_URI=$(aws ecr create-repository \
        --repository-name "$ECR_REPO_NAME" \
        --image-scanning-configuration scanOnPush=true \
        --query 'repository.repositoryUri' --output text)
    save_resource "ECR_URI" "$ECR_URI"
    
    # Get ECR login token
    info "Authenticating with ECR"
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$ECR_URI"
    
    # Create temporary directory for container build
    CONTAINER_BUILD_DIR=$(mktemp -d)
    trap "rm -rf $CONTAINER_BUILD_DIR" EXIT
    
    info "Building MPI container image in: $CONTAINER_BUILD_DIR"
    
    # Create Dockerfile
    cat > "$CONTAINER_BUILD_DIR/Dockerfile" << 'EOF'
FROM ubuntu:20.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install essential packages and MPI
RUN apt-get update && apt-get install -y \
    build-essential \
    gfortran \
    openmpi-bin \
    openmpi-common \
    libopenmpi-dev \
    python3 \
    python3-pip \
    python3-numpy \
    python3-scipy \
    nfs-common \
    curl \
    wget \
    vim \
    htop \
    && rm -rf /var/lib/apt/lists/*

# Install additional scientific libraries
RUN pip3 install mpi4py matplotlib pandas seaborn

# Set up MPI environment
ENV OMPI_ALLOW_RUN_AS_ROOT=1
ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
ENV OMPI_MCA_btl_vader_single_copy_mechanism=none

# Create working directory
WORKDIR /app

# Copy MPI applications
COPY mpi_test.py /app/
COPY run_mpi_job.sh /app/
COPY advanced_mpi_test.py /app/

# Make scripts executable
RUN chmod +x /app/run_mpi_job.sh

# Default command
CMD ["/app/run_mpi_job.sh"]
EOF
    
    # Create MPI test application
    cat > "$CONTAINER_BUILD_DIR/mpi_test.py" << 'EOF'
#!/usr/bin/env python3
"""
Simple MPI test application for scientific computing validation
"""
import sys
import time
import numpy as np
from mpi4py import MPI

def main():
    # Initialize MPI
    comm = MPI.COMM_WORLD
    rank = comm.Get_rank()
    size = comm.Get_size()
    
    print(f"Process {rank} of {size} on node {MPI.Get_processor_name()}")
    
    # Simple computational workload
    if rank == 0:
        print("Starting distributed computation...")
        start_time = time.time()
    
    # Each process computes part of a larger matrix operation
    local_size = 1000
    local_matrix = np.random.rand(local_size, local_size)
    local_result = np.dot(local_matrix, local_matrix.T)
    
    # Gather results at root
    results = comm.gather(np.sum(local_result), root=0)
    
    if rank == 0:
        total_sum = sum(results)
        end_time = time.time()
        print(f"Computation completed in {end_time - start_time:.2f} seconds")
        print(f"Total sum across all processes: {total_sum:.2e}")
        print("✅ MPI job completed successfully")

if __name__ == "__main__":
    main()
EOF
    
    # Create advanced MPI test application
    cat > "$CONTAINER_BUILD_DIR/advanced_mpi_test.py" << 'EOF'
#!/usr/bin/env python3
"""
Advanced MPI test application demonstrating various parallel patterns
"""
import sys
import time
import numpy as np
from mpi4py import MPI

def parallel_matrix_multiply(comm, matrix_size):
    """Parallel matrix multiplication using MPI"""
    rank = comm.Get_rank()
    size = comm.Get_size()
    
    if rank == 0:
        # Create test matrices
        A = np.random.rand(matrix_size, matrix_size)
        B = np.random.rand(matrix_size, matrix_size)
    else:
        A = None
        B = None
    
    # Broadcast matrix B to all processes
    B = comm.bcast(B, root=0)
    
    # Scatter rows of matrix A
    rows_per_proc = matrix_size // size
    if rank == 0:
        A_scattered = [A[i*rows_per_proc:(i+1)*rows_per_proc] for i in range(size)]
    else:
        A_scattered = None
    
    local_A = comm.scatter(A_scattered, root=0)
    
    # Perform local matrix multiplication
    local_result = np.dot(local_A, B)
    
    # Gather results
    result = comm.gather(local_result, root=0)
    
    if rank == 0:
        final_result = np.vstack(result)
        return final_result
    return None

def main():
    comm = MPI.COMM_WORLD
    rank = comm.Get_rank()
    size = comm.Get_size()
    
    if rank == 0:
        print(f"Advanced MPI Test - Running on {size} processes")
        print("=" * 50)
    
    # Test 1: Parallel matrix multiplication
    matrix_size = 500
    start_time = time.time()
    result = parallel_matrix_multiply(comm, matrix_size)
    end_time = time.time()
    
    if rank == 0:
        print(f"Matrix multiplication ({matrix_size}x{matrix_size}): {end_time - start_time:.2f}s")
    
    # Test 2: Collective communication patterns
    data = rank * 10
    
    # All-reduce operation
    total = comm.allreduce(data, op=MPI.SUM)
    
    # All-gather operation
    all_data = comm.allgather(data)
    
    if rank == 0:
        print(f"All-reduce result: {total}")
        print(f"All-gather result: {all_data}")
        print("✅ Advanced MPI tests completed successfully")

if __name__ == "__main__":
    main()
EOF
    
    # Create job runner script
    cat > "$CONTAINER_BUILD_DIR/run_mpi_job.sh" << 'EOF'
#!/bin/bash
set -e

echo "=== MPI Multi-Node Job Starting ==="
echo "AWS Batch Job ID: ${AWS_BATCH_JOB_ID:-not-set}"
echo "Main node index: ${AWS_BATCH_JOB_MAIN_NODE_INDEX:-0}"
echo "Current node index: ${AWS_BATCH_JOB_NODE_INDEX:-0}"
echo "Number of nodes: ${AWS_BATCH_JOB_NUM_NODES:-1}"

# Mount EFS if available
if [ ! -z "${EFS_MOUNT_POINT:-}" ] && [ ! -z "${EFS_DNS_NAME:-}" ]; then
    echo "Mounting EFS filesystem..."
    mkdir -p "${EFS_MOUNT_POINT}"
    mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600 \
        "${EFS_DNS_NAME}":/ "${EFS_MOUNT_POINT}" || echo "EFS mount failed, continuing..."
    echo "EFS mounted at ${EFS_MOUNT_POINT}"
fi

# Only run on main node
if [ "${AWS_BATCH_JOB_NODE_INDEX:-0}" = "${AWS_BATCH_JOB_MAIN_NODE_INDEX:-0}" ]; then
    echo "Running MPI application from main node..."
    
    # Wait for all nodes to be ready
    sleep 30
    
    # Determine which test to run
    TEST_TYPE=${TEST_TYPE:-basic}
    
    if [ "$TEST_TYPE" = "advanced" ]; then
        echo "Running advanced MPI test..."
        mpirun --allow-run-as-root \
               --host "${AWS_BATCH_JOB_NODE_LIST:-localhost}" \
               -np "${AWS_BATCH_JOB_NUM_NODES:-1}" \
               python3 /app/advanced_mpi_test.py
    else
        echo "Running basic MPI test..."
        mpirun --allow-run-as-root \
               --host "${AWS_BATCH_JOB_NODE_LIST:-localhost}" \
               -np "${AWS_BATCH_JOB_NUM_NODES:-1}" \
               python3 /app/mpi_test.py
    fi
else
    echo "Child node waiting for MPI coordinator..."
    # Child nodes wait for main node to coordinate
    while true; do
        sleep 10
    done
fi
EOF
    
    # Build and push container image
    info "Building Docker image..."
    cd "$CONTAINER_BUILD_DIR"
    docker build -t "$ECR_REPO_NAME" .
    
    info "Tagging and pushing image to ECR..."
    docker tag "$ECR_REPO_NAME:latest" "$ECR_URI:latest"
    docker push "$ECR_URI:latest"
    
    log "Container image built and pushed successfully: $ECR_URI"
}

create_iam_roles() {
    log "Creating IAM roles for AWS Batch..."
    
    # Create temporary files for role policies
    BATCH_SERVICE_TRUST=$(mktemp)
    BATCH_INSTANCE_TRUST=$(mktemp)
    trap "rm -f $BATCH_SERVICE_TRUST $BATCH_INSTANCE_TRUST" EXIT
    
    # Create Batch service role trust policy
    cat > "$BATCH_SERVICE_TRUST" << EOF
{
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
}
EOF
    
    # Create Batch service role
    info "Creating Batch service role"
    aws iam create-role \
        --role-name "${CLUSTER_NAME}-batch-service-role" \
        --assume-role-policy-document "file://$BATCH_SERVICE_TRUST" \
        --tags "Key=Project,Value=scientific-computing" "Key=Component,Value=batch-service" || warn "Role may already exist"
    
    aws iam attach-role-policy \
        --role-name "${CLUSTER_NAME}-batch-service-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole || warn "Policy may already be attached"
    
    save_resource "BATCH_SERVICE_ROLE" "${CLUSTER_NAME}-batch-service-role"
    
    # Create instance role trust policy
    cat > "$BATCH_INSTANCE_TRUST" << EOF
{
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
}
EOF
    
    # Create instance role
    info "Creating Batch instance role"
    aws iam create-role \
        --role-name "${CLUSTER_NAME}-batch-instance-role" \
        --assume-role-policy-document "file://$BATCH_INSTANCE_TRUST" \
        --tags "Key=Project,Value=scientific-computing" "Key=Component,Value=batch-instance" || warn "Role may already exist"
    
    aws iam attach-role-policy \
        --role-name "${CLUSTER_NAME}-batch-instance-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role || warn "Policy may already be attached"
    
    save_resource "BATCH_INSTANCE_ROLE" "${CLUSTER_NAME}-batch-instance-role"
    
    # Create instance profile
    info "Creating instance profile"
    aws iam create-instance-profile \
        --instance-profile-name "${CLUSTER_NAME}-batch-instance-profile" \
        --tags "Key=Project,Value=scientific-computing" "Key=Component,Value=batch-instance" || warn "Instance profile may already exist"
    
    aws iam add-role-to-instance-profile \
        --instance-profile-name "${CLUSTER_NAME}-batch-instance-profile" \
        --role-name "${CLUSTER_NAME}-batch-instance-role" || warn "Role may already be added to instance profile"
    
    save_resource "BATCH_INSTANCE_PROFILE" "${CLUSTER_NAME}-batch-instance-profile"
    
    # Wait for role propagation
    info "Waiting for IAM role propagation..."
    sleep 10
    
    log "IAM roles created successfully"
}

create_batch_environment() {
    log "Creating AWS Batch compute environment..."
    
    # Create compute environment configuration
    COMPUTE_ENV_CONFIG=$(mktemp)
    trap "rm -f $COMPUTE_ENV_CONFIG" EXIT
    
    # Convert instance types string to JSON array
    IFS=',' read -ra INSTANCE_TYPE_ARRAY <<< "$INSTANCE_TYPES"
    INSTANCE_TYPE_JSON=$(printf '"%s",' "${INSTANCE_TYPE_ARRAY[@]}")
    INSTANCE_TYPE_JSON="[${INSTANCE_TYPE_JSON%,}]"
    
    cat > "$COMPUTE_ENV_CONFIG" << EOF
{
    "computeEnvironmentName": "${COMPUTE_ENV_NAME}",
    "type": "MANAGED",
    "state": "ENABLED",
    "computeResources": {
        "type": "EC2",
        "minvCpus": 0,
        "maxvCpus": ${MAX_VCPUS},
        "desiredvCpus": 0,
        "instanceTypes": ${INSTANCE_TYPE_JSON},
        "subnets": ["${SUBNET_ID}"],
        "securityGroupIds": ["${SG_ID}"],
        "instanceRole": "arn:aws:iam::${AWS_ACCOUNT_ID}:instance-profile/${CLUSTER_NAME}-batch-instance-profile",
        "tags": {
            "Environment": "scientific-computing",
            "Project": "${CLUSTER_NAME}",
            "ManagedBy": "aws-batch"
        }
    },
    "serviceRole": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-batch-service-role"
}
EOF
    
    # Create the compute environment
    info "Creating compute environment: $COMPUTE_ENV_NAME"
    aws batch create-compute-environment \
        --cli-input-json "file://$COMPUTE_ENV_CONFIG"
    
    # Wait for compute environment to be valid
    info "Waiting for compute environment to be ready..."
    aws batch wait compute-environment-in-service \
        --compute-environments "$COMPUTE_ENV_NAME"
    
    log "Batch compute environment created successfully"
}

create_job_queue_and_definitions() {
    log "Creating job queue and job definitions..."
    
    # Create job queue
    info "Creating job queue: $JOB_QUEUE_NAME"
    aws batch create-job-queue \
        --job-queue-name "$JOB_QUEUE_NAME" \
        --state ENABLED \
        --priority 1 \
        --compute-environment-order "order=1,computeEnvironment=${COMPUTE_ENV_NAME}" \
        --tags "Project=scientific-computing,Component=job-queue"
    
    # Wait for job queue to be valid
    info "Waiting for job queue to be ready..."
    aws batch wait job-queue-in-service --job-queues "$JOB_QUEUE_NAME"
    
    # Create multi-node parallel job definition
    JOB_DEF_CONFIG=$(mktemp)
    trap "rm -f $JOB_DEF_CONFIG" EXIT
    
    cat > "$JOB_DEF_CONFIG" << EOF
{
    "jobDefinitionName": "${CLUSTER_NAME}-mpi-job",
    "type": "multinode",
    "nodeProperties": {
        "mainNode": 0,
        "numNodes": ${NODE_COUNT},
        "nodeRangeProperties": [
            {
                "targetNodes": "0:",
                "container": {
                    "image": "${ECR_URI}:latest",
                    "vcpus": 2,
                    "memory": 4096,
                    "environment": [
                        {
                            "name": "EFS_DNS_NAME",
                            "value": "${EFS_ID}.efs.${AWS_REGION}.amazonaws.com"
                        },
                        {
                            "name": "EFS_MOUNT_POINT",
                            "value": "/mnt/efs"
                        }
                    ],
                    "mountPoints": [
                        {
                            "sourceVolume": "tmp",
                            "containerPath": "/tmp"
                        }
                    ],
                    "volumes": [
                        {
                            "name": "tmp",
                            "host": {
                                "sourcePath": "/tmp"
                            }
                        }
                    ],
                    "privileged": true
                }
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
        "Project": "scientific-computing",
        "JobType": "multi-node-mpi"
    }
}
EOF
    
    # Register the job definition
    info "Registering multi-node job definition"
    JOB_DEF_ARN=$(aws batch register-job-definition \
        --cli-input-json "file://$JOB_DEF_CONFIG" \
        --query 'jobDefinitionArn' --output text)
    save_resource "JOB_DEF_ARN" "$JOB_DEF_ARN"
    save_resource "JOB_DEF_NAME" "${CLUSTER_NAME}-mpi-job"
    
    # Create advanced parameterized job definition
    ADVANCED_JOB_DEF_CONFIG=$(mktemp)
    trap "rm -f $ADVANCED_JOB_DEF_CONFIG" EXIT
    
    cat > "$ADVANCED_JOB_DEF_CONFIG" << EOF
{
    "jobDefinitionName": "${CLUSTER_NAME}-parameterized-mpi",
    "type": "multinode",
    "parameters": {
        "inputDataPath": "/mnt/efs/input",
        "outputDataPath": "/mnt/efs/output",
        "testType": "basic"
    },
    "nodeProperties": {
        "mainNode": 0,
        "numNodes": 4,
        "nodeRangeProperties": [
            {
                "targetNodes": "0:",
                "container": {
                    "image": "${ECR_URI}:latest",
                    "vcpus": 4,
                    "memory": 8192,
                    "environment": [
                        {
                            "name": "EFS_DNS_NAME",
                            "value": "${EFS_ID}.efs.${AWS_REGION}.amazonaws.com"
                        },
                        {
                            "name": "EFS_MOUNT_POINT",
                            "value": "/mnt/efs"
                        },
                        {
                            "name": "INPUT_PATH",
                            "value": "Ref::inputDataPath"
                        },
                        {
                            "name": "OUTPUT_PATH",
                            "value": "Ref::outputDataPath"
                        },
                        {
                            "name": "TEST_TYPE",
                            "value": "Ref::testType"
                        }
                    ],
                    "mountPoints": [
                        {
                            "sourceVolume": "tmp",
                            "containerPath": "/tmp"
                        }
                    ],
                    "volumes": [
                        {
                            "name": "tmp",
                            "host": {
                                "sourcePath": "/tmp"
                            }
                        }
                    ],
                    "privileged": true
                }
            }
        ]
    },
    "retryStrategy": {
        "attempts": 2
    },
    "timeout": {
        "attemptDurationSeconds": 7200
    },
    "tags": {
        "Project": "scientific-computing",
        "JobType": "parameterized-multi-node-mpi"
    }
}
EOF
    
    # Register advanced job definition
    info "Registering parameterized job definition"
    ADVANCED_JOB_DEF_ARN=$(aws batch register-job-definition \
        --cli-input-json "file://$ADVANCED_JOB_DEF_CONFIG" \
        --query 'jobDefinitionArn' --output text)
    save_resource "ADVANCED_JOB_DEF_ARN" "$ADVANCED_JOB_DEF_ARN"
    save_resource "ADVANCED_JOB_DEF_NAME" "${CLUSTER_NAME}-parameterized-mpi"
    
    log "Job queue and definitions created successfully"
}

setup_monitoring() {
    log "Setting up monitoring and logging..."
    
    # Create CloudWatch dashboard
    DASHBOARD_CONFIG=$(mktemp)
    trap "rm -f $DASHBOARD_CONFIG" EXIT
    
    cat > "$DASHBOARD_CONFIG" << EOF
{
    "widgets": [
        {
            "type": "metric",
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Batch", "SubmittedJobs", "JobQueue", "${JOB_QUEUE_NAME}"],
                    [".", "RunnableJobs", ".", "."],
                    [".", "RunningJobs", ".", "."],
                    [".", "CompletedJobs", ".", "."],
                    [".", "FailedJobs", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Batch Job Status - ${JOB_QUEUE_NAME}",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "metric",
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/EFS", "ClientConnections", "FileSystemId", "${EFS_ID}"],
                    [".", "DataReadIOBytes", ".", "."],
                    [".", "DataWriteIOBytes", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "EFS Metrics - ${EFS_ID}"
            }
        }
    ]
}
EOF
    
    info "Creating CloudWatch dashboard"
    aws cloudwatch put-dashboard \
        --dashboard-name "${CLUSTER_NAME}-monitoring" \
        --dashboard-body "file://$DASHBOARD_CONFIG"
    save_resource "DASHBOARD_NAME" "${CLUSTER_NAME}-monitoring"
    
    # Create CloudWatch alarm for failed jobs
    info "Creating CloudWatch alarm for failed jobs"
    aws cloudwatch put-metric-alarm \
        --alarm-name "${CLUSTER_NAME}-failed-jobs" \
        --alarm-description "Alert when jobs fail in ${JOB_QUEUE_NAME}" \
        --metric-name FailedJobs \
        --namespace AWS/Batch \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --dimensions "Name=JobQueue,Value=${JOB_QUEUE_NAME}" \
        --evaluation-periods 1 \
        --tags "Key=Project,Value=scientific-computing"
    save_resource "ALARM_NAME" "${CLUSTER_NAME}-failed-jobs"
    
    log "Monitoring and alerting configured successfully"
}

create_job_submission_script() {
    log "Creating job submission helper script..."
    
    SUBMIT_SCRIPT="${SCRIPT_DIR}/submit-scientific-job.sh"
    
    cat > "$SUBMIT_SCRIPT" << EOF
#!/bin/bash

#####################################################################
# Scientific Job Submission Script
#####################################################################
# This script submits jobs to the AWS Batch scientific computing
# environment created by the deployment script.
#####################################################################

set -euo pipefail

# Default parameters
JOB_NAME="scientific-computation"
NODE_COUNT=2
VCPUS_PER_NODE=2
MEMORY_PER_NODE=4096
INPUT_PATH="/mnt/efs/input"
OUTPUT_PATH="/mnt/efs/output"
TEST_TYPE="basic"

# Configuration from deployment
JOB_QUEUE_NAME="${JOB_QUEUE_NAME}"
BASIC_JOB_DEFINITION="${CLUSTER_NAME}-mpi-job"
PARAMETERIZED_JOB_DEFINITION="${CLUSTER_NAME}-parameterized-mpi"

usage() {
    cat << USAGE
Usage: \$0 [OPTIONS]

Submit a scientific computing job to AWS Batch.

OPTIONS:
    --job-name NAME          Job name (default: \$JOB_NAME)
    --nodes COUNT            Number of nodes (default: \$NODE_COUNT)
    --vcpus COUNT            vCPUs per node (default: \$VCPUS_PER_NODE)
    --memory MB              Memory per node in MB (default: \$MEMORY_PER_NODE)
    --input-path PATH        Input data path (default: \$INPUT_PATH)
    --output-path PATH       Output data path (default: \$OUTPUT_PATH)
    --test-type TYPE         Test type: basic|advanced (default: \$TEST_TYPE)
    --use-parameterized      Use parameterized job definition
    --help                   Show this help message

EXAMPLES:
    \$0
    \$0 --job-name my-simulation --nodes 4 --vcpus 4
    \$0 --test-type advanced --use-parameterized
    \$0 --nodes 8 --memory 16384 --test-type advanced

USAGE
}

# Parse command line arguments
while [[ \$# -gt 0 ]]; do
    case \$1 in
        --job-name)
            JOB_NAME="\$2"
            shift 2
            ;;
        --nodes)
            NODE_COUNT="\$2"
            shift 2
            ;;
        --vcpus)
            VCPUS_PER_NODE="\$2"
            shift 2
            ;;
        --memory)
            MEMORY_PER_NODE="\$2"
            shift 2
            ;;
        --input-path)
            INPUT_PATH="\$2"
            shift 2
            ;;
        --output-path)
            OUTPUT_PATH="\$2"
            shift 2
            ;;
        --test-type)
            TEST_TYPE="\$2"
            shift 2
            ;;
        --use-parameterized)
            USE_PARAMETERIZED="true"
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown parameter: \$1"
            usage
            exit 1
            ;;
    esac
done

echo "Submitting scientific job with parameters:"
echo "  Job Name: \${JOB_NAME}"
echo "  Nodes: \${NODE_COUNT}"
echo "  vCPUs per node: \${VCPUS_PER_NODE}"
echo "  Memory per node: \${MEMORY_PER_NODE} MB"
echo "  Input path: \${INPUT_PATH}"
echo "  Output path: \${OUTPUT_PATH}"
echo "  Test type: \${TEST_TYPE}"

if [[ "\${USE_PARAMETERIZED:-false}" == "true" ]]; then
    echo "  Using parameterized job definition"
    
    # Submit job with parameters
    JOB_ID=\$(aws batch submit-job \\
        --job-name "\${JOB_NAME}" \\
        --job-queue "\${JOB_QUEUE_NAME}" \\
        --job-definition "\${PARAMETERIZED_JOB_DEFINITION}" \\
        --parameters "inputDataPath=\${INPUT_PATH},outputDataPath=\${OUTPUT_PATH},testType=\${TEST_TYPE}" \\
        --node-overrides "numNodes=\${NODE_COUNT},nodePropertyOverrides=[{targetNodes=\"0:\",container={vcpus=\${VCPUS_PER_NODE},memory=\${MEMORY_PER_NODE}}}]" \\
        --query 'jobId' --output text)
else
    echo "  Using basic job definition"
    
    # Submit job with node overrides
    JOB_ID=\$(aws batch submit-job \\
        --job-name "\${JOB_NAME}" \\
        --job-queue "\${JOB_QUEUE_NAME}" \\
        --job-definition "\${BASIC_JOB_DEFINITION}" \\
        --node-overrides "numNodes=\${NODE_COUNT},nodePropertyOverrides=[{targetNodes=\"0:\",container={vcpus=\${VCPUS_PER_NODE},memory=\${MEMORY_PER_NODE},environment=[{name=TEST_TYPE,value=\${TEST_TYPE}}]}}]" \\
        --query 'jobId' --output text)
fi

echo "Job submitted successfully!"
echo "Job ID: \${JOB_ID}"
echo ""
echo "Monitor with:"
echo "  aws batch describe-jobs --jobs \${JOB_ID}"
echo ""
echo "View logs:"
echo "  aws logs describe-log-groups --log-group-name-prefix '/aws/batch/job'"
echo ""
echo "Cancel job (if needed):"
echo "  aws batch terminate-job --job-id \${JOB_ID} --reason 'User requested termination'"
EOF
    
    chmod +x "$SUBMIT_SCRIPT"
    save_resource "SUBMIT_SCRIPT" "$SUBMIT_SCRIPT"
    
    log "Job submission script created: $SUBMIT_SCRIPT"
}

submit_test_job() {
    log "Submitting test multi-node job..."
    
    # Submit a test job to validate the environment
    info "Submitting test job with $NODE_COUNT nodes"
    TEST_JOB_ID=$(aws batch submit-job \
        --job-name "${CLUSTER_NAME}-test-job" \
        --job-queue "$JOB_QUEUE_NAME" \
        --job-definition "${CLUSTER_NAME}-mpi-job" \
        --query 'jobId' --output text)
    save_resource "TEST_JOB_ID" "$TEST_JOB_ID"
    
    log "Test job submitted successfully: $TEST_JOB_ID"
    
    info "Monitor job status with:"
    info "  aws batch describe-jobs --jobs $TEST_JOB_ID"
    info ""
    info "View job logs after completion:"
    info "  aws logs describe-log-groups --log-group-name-prefix '/aws/batch/job'"
}

print_deployment_summary() {
    log "Deployment completed successfully!"
    echo ""
    echo "==================================================================="
    echo "AWS Batch Multi-Node Scientific Computing Environment"
    echo "==================================================================="
    echo "Cluster Name:           $CLUSTER_NAME"
    echo "AWS Region:             $AWS_REGION"
    echo "Job Queue:              $JOB_QUEUE_NAME"
    echo "Compute Environment:    $COMPUTE_ENV_NAME"
    echo "ECR Repository:         $ECR_REPO_NAME"
    echo "EFS Filesystem:         $EFS_ID"
    echo "VPC:                    $VPC_ID"
    echo "Test Job ID:            ${TEST_JOB_ID:-not-submitted}"
    echo ""
    echo "Job Definitions:"
    echo "  Basic:                ${CLUSTER_NAME}-mpi-job"
    echo "  Parameterized:        ${CLUSTER_NAME}-parameterized-mpi"
    echo ""
    echo "Monitoring:"
    echo "  Dashboard:            ${CLUSTER_NAME}-monitoring"
    echo "  Failed Jobs Alarm:    ${CLUSTER_NAME}-failed-jobs"
    echo ""
    echo "Helper Scripts:"
    echo "  Submit Job:           ${SCRIPT_DIR}/submit-scientific-job.sh"
    echo "  Cleanup:              ${SCRIPT_DIR}/destroy.sh"
    echo ""
    echo "Useful Commands:"
    echo "  Submit job:           ${SCRIPT_DIR}/submit-scientific-job.sh --help"
    echo "  Monitor jobs:         aws batch list-jobs --job-queue $JOB_QUEUE_NAME"
    echo "  View dashboard:       https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${CLUSTER_NAME}-monitoring"
    echo "  Cleanup all:          ${SCRIPT_DIR}/destroy.sh"
    echo ""
    echo "==================================================================="
    echo ""
    warn "Remember to run the cleanup script when done to avoid ongoing charges!"
}

#####################################################################
# Main Execution
#####################################################################

main() {
    # Initialize log file
    echo "AWS Batch Multi-Node Scientific Computing Deployment" > "$LOG_FILE"
    echo "Started at: $(date)" >> "$LOG_FILE"
    echo "=========================================" >> "$LOG_FILE"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    initialize_environment
    create_networking
    create_efs_storage
    create_container_image
    create_iam_roles
    create_batch_environment
    create_job_queue_and_definitions
    setup_monitoring
    create_job_submission_script
    submit_test_job
    print_deployment_summary
    
    log "Deployment completed successfully at $(date)"
}

# Run main function with all arguments
main "$@"