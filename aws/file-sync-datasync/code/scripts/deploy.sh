#!/bin/bash

# File System Synchronization with AWS DataSync and EFS - Deployment Script
# This script deploys the complete infrastructure for DataSync and EFS file synchronization

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
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions
    log "Checking AWS permissions..."
    aws iam get-user &> /dev/null || {
        error "Unable to retrieve user information. Please check your AWS credentials."
        exit 1
    }
    
    success "Prerequisites check passed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No region configured, defaulting to us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
        --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export EFS_NAME="datasync-efs-${RANDOM_SUFFIX}"
    export VPC_NAME="datasync-vpc-${RANDOM_SUFFIX}"
    export DATASYNC_TASK_NAME="file-sync-task-${RANDOM_SUFFIX}"
    export SOURCE_BUCKET="datasync-source-${RANDOM_SUFFIX}"
    export DATASYNC_ROLE_NAME="DataSyncServiceRole-${RANDOM_SUFFIX}"
    
    # Create deployment state file
    cat > deployment_state.json << EOF
{
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "efs_name": "$EFS_NAME",
    "vpc_name": "$VPC_NAME",
    "datasync_task_name": "$DATASYNC_TASK_NAME",
    "source_bucket": "$SOURCE_BUCKET",
    "datasync_role_name": "$DATASYNC_ROLE_NAME",
    "random_suffix": "$RANDOM_SUFFIX"
}
EOF
    
    success "Environment variables configured"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "Random Suffix: $RANDOM_SUFFIX"
}

# Function to create VPC and networking components
create_vpc_networking() {
    log "Creating VPC and networking components..."
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}},{Key=Project,Value=DataSyncEFS}]" \
        --query 'Vpc.VpcId' --output text)
    
    if [ -z "$VPC_ID" ]; then
        error "Failed to create VPC"
        exit 1
    fi
    
    success "VPC created: ${VPC_ID}"
    
    # Create private subnet
    SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id ${VPC_ID} \
        --cidr-block 10.0.1.0/24 \
        --availability-zone ${AWS_REGION}a \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-private},{Key=Project,Value=DataSyncEFS}]" \
        --query 'Subnet.SubnetId' --output text)
    
    if [ -z "$SUBNET_ID" ]; then
        error "Failed to create subnet"
        exit 1
    fi
    
    success "Private subnet created: ${SUBNET_ID}"
    
    # Create security group
    SG_ID=$(aws ec2 create-security-group \
        --group-name ${VPC_NAME}-efs-sg \
        --description "Security group for EFS access from DataSync" \
        --vpc-id ${VPC_ID} \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${VPC_NAME}-efs-sg},{Key=Project,Value=DataSyncEFS}]" \
        --query 'GroupId' --output text)
    
    if [ -z "$SG_ID" ]; then
        error "Failed to create security group"
        exit 1
    fi
    
    # Allow NFS traffic (port 2049) within VPC
    aws ec2 authorize-security-group-ingress \
        --group-id ${SG_ID} \
        --protocol tcp \
        --port 2049 \
        --cidr 10.0.0.0/16
    
    success "Security group configured: ${SG_ID}"
    
    # Update deployment state
    jq --arg vpc_id "$VPC_ID" \
       --arg subnet_id "$SUBNET_ID" \
       --arg sg_id "$SG_ID" \
       '. + {vpc_id: $vpc_id, subnet_id: $subnet_id, security_group_id: $sg_id}' \
       deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
}

# Function to create EFS file system
create_efs_filesystem() {
    log "Creating EFS file system..."
    
    # Create EFS file system with encryption at rest
    EFS_ID=$(aws efs create-file-system \
        --creation-token ${EFS_NAME} \
        --performance-mode generalPurpose \
        --throughput-mode provisioned \
        --provisioned-throughput-in-mibps 100 \
        --encrypted \
        --tags Key=Name,Value=${EFS_NAME},Key=Project,Value=DataSyncEFS \
        --query 'FileSystemId' --output text)
    
    if [ -z "$EFS_ID" ]; then
        error "Failed to create EFS file system"
        exit 1
    fi
    
    success "EFS file system created: ${EFS_ID}"
    
    # Wait for EFS to be available
    log "Waiting for EFS file system to become available..."
    aws efs wait file-system-available --file-system-id ${EFS_ID}
    
    # Create mount target
    MOUNT_TARGET_ID=$(aws efs create-mount-target \
        --file-system-id ${EFS_ID} \
        --subnet-id $(jq -r '.subnet_id' deployment_state.json) \
        --security-groups $(jq -r '.security_group_id' deployment_state.json) \
        --query 'MountTargetId' --output text)
    
    if [ -z "$MOUNT_TARGET_ID" ]; then
        error "Failed to create EFS mount target"
        exit 1
    fi
    
    # Wait for mount target to become available
    log "Waiting for EFS mount target to become available..."
    aws efs wait mount-target-available --mount-target-id ${MOUNT_TARGET_ID}
    
    success "EFS mount target created and available: ${MOUNT_TARGET_ID}"
    
    # Update deployment state
    jq --arg efs_id "$EFS_ID" \
       --arg mount_target_id "$MOUNT_TARGET_ID" \
       '. + {efs_id: $efs_id, mount_target_id: $mount_target_id}' \
       deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
}

# Function to create S3 bucket with sample data
create_s3_source() {
    log "Creating S3 bucket with sample data..."
    
    # Create S3 bucket
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket ${SOURCE_BUCKET}
    else
        aws s3api create-bucket \
            --bucket ${SOURCE_BUCKET} \
            --create-bucket-configuration LocationConstraint=${AWS_REGION}
    fi
    
    # Add bucket tagging
    aws s3api put-bucket-tagging \
        --bucket ${SOURCE_BUCKET} \
        --tagging 'TagSet=[{Key=Name,Value='${SOURCE_BUCKET}'},{Key=Project,Value=DataSyncEFS}]'
    
    success "S3 bucket created: ${SOURCE_BUCKET}"
    
    # Create sample files for testing
    mkdir -p /tmp/datasync-sample
    echo "Sample file 1 content - $(date)" > /tmp/datasync-sample/sample1.txt
    echo "Sample file 2 content - $(date)" > /tmp/datasync-sample/sample2.txt
    mkdir -p /tmp/datasync-sample/test-folder
    echo "Nested file content - $(date)" > /tmp/datasync-sample/test-folder/nested.txt
    echo "Configuration file content - $(date)" > /tmp/datasync-sample/config.json
    
    # Upload sample files to S3
    aws s3 sync /tmp/datasync-sample/ s3://${SOURCE_BUCKET}/
    
    success "Sample data uploaded to S3 bucket"
    
    # Update deployment state
    jq --arg source_bucket "$SOURCE_BUCKET" \
       '. + {source_bucket: $source_bucket}' \
       deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
}

# Function to create IAM role for DataSync
create_iam_role() {
    log "Creating IAM role for DataSync..."
    
    # Create trust policy
    cat > /tmp/datasync-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "datasync.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name ${DATASYNC_ROLE_NAME} \
        --assume-role-policy-document file:///tmp/datasync-trust-policy.json \
        --description "Service role for DataSync operations" \
        --tags Key=Project,Value=DataSyncEFS
    
    # Attach managed policy for S3 access
    aws iam attach-role-policy \
        --role-name ${DATASYNC_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
    
    success "DataSync IAM role created: ${DATASYNC_ROLE_NAME}"
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
    
    # Update deployment state
    jq --arg role_name "$DATASYNC_ROLE_NAME" \
       '. + {datasync_role_name: $role_name}' \
       deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
}

# Function to create DataSync locations
create_datasync_locations() {
    log "Creating DataSync locations..."
    
    # Get the DataSync role ARN
    DATASYNC_ROLE_ARN=$(aws iam get-role \
        --role-name ${DATASYNC_ROLE_NAME} \
        --query 'Role.Arn' --output text)
    
    if [ -z "$DATASYNC_ROLE_ARN" ]; then
        error "Failed to get DataSync role ARN"
        exit 1
    fi
    
    # Create S3 location
    S3_LOCATION_ARN=$(aws datasync create-location-s3 \
        --s3-bucket-arn arn:aws:s3:::${SOURCE_BUCKET} \
        --s3-config "{
            \"BucketAccessRoleArn\": \"${DATASYNC_ROLE_ARN}\"
        }" \
        --tags Key=Project,Value=DataSyncEFS \
        --query 'LocationArn' --output text)
    
    if [ -z "$S3_LOCATION_ARN" ]; then
        error "Failed to create S3 location"
        exit 1
    fi
    
    success "DataSync S3 location created: ${S3_LOCATION_ARN}"
    
    # Get values from deployment state
    EFS_ID=$(jq -r '.efs_id' deployment_state.json)
    SUBNET_ID=$(jq -r '.subnet_id' deployment_state.json)
    SG_ID=$(jq -r '.security_group_id' deployment_state.json)
    
    # Create EFS location
    EFS_LOCATION_ARN=$(aws datasync create-location-efs \
        --efs-file-system-arn arn:aws:elasticfilesystem:${AWS_REGION}:${AWS_ACCOUNT_ID}:file-system/${EFS_ID} \
        --ec2-config "{
            \"SubnetArn\": \"arn:aws:ec2:${AWS_REGION}:${AWS_ACCOUNT_ID}:subnet/${SUBNET_ID}\",
            \"SecurityGroupArns\": [\"arn:aws:ec2:${AWS_REGION}:${AWS_ACCOUNT_ID}:security-group/${SG_ID}\"]
        }" \
        --tags Key=Project,Value=DataSyncEFS \
        --query 'LocationArn' --output text)
    
    if [ -z "$EFS_LOCATION_ARN" ]; then
        error "Failed to create EFS location"
        exit 1
    fi
    
    success "DataSync EFS location created: ${EFS_LOCATION_ARN}"
    
    # Update deployment state
    jq --arg s3_location "$S3_LOCATION_ARN" \
       --arg efs_location "$EFS_LOCATION_ARN" \
       --arg role_arn "$DATASYNC_ROLE_ARN" \
       '. + {s3_location_arn: $s3_location, efs_location_arn: $efs_location, datasync_role_arn: $role_arn}' \
       deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
}

# Function to create and execute DataSync task
create_datasync_task() {
    log "Creating DataSync task..."
    
    # Get location ARNs from deployment state
    S3_LOCATION_ARN=$(jq -r '.s3_location_arn' deployment_state.json)
    EFS_LOCATION_ARN=$(jq -r '.efs_location_arn' deployment_state.json)
    
    # Create DataSync task
    TASK_ARN=$(aws datasync create-task \
        --source-location-arn ${S3_LOCATION_ARN} \
        --destination-location-arn ${EFS_LOCATION_ARN} \
        --name ${DATASYNC_TASK_NAME} \
        --options '{
            "VerifyMode": "POINT_IN_TIME_CONSISTENT",
            "OverwriteMode": "ALWAYS",
            "Atime": "BEST_EFFORT",
            "Mtime": "PRESERVE",
            "Uid": "INT_VALUE",
            "Gid": "INT_VALUE",
            "PreserveDeletedFiles": "PRESERVE",
            "PreserveDevices": "NONE",
            "PosixPermissions": "PRESERVE",
            "BytesPerSecond": -1,
            "TaskQueueing": "ENABLED",
            "LogLevel": "TRANSFER"
        }' \
        --tags Key=Project,Value=DataSyncEFS \
        --query 'TaskArn' --output text)
    
    if [ -z "$TASK_ARN" ]; then
        error "Failed to create DataSync task"
        exit 1
    fi
    
    success "DataSync task created: ${TASK_ARN}"
    
    # Update deployment state
    jq --arg task_arn "$TASK_ARN" \
       '. + {task_arn: $task_arn}' \
       deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
}

# Function to execute DataSync task
execute_datasync_task() {
    log "Executing DataSync task..."
    
    TASK_ARN=$(jq -r '.task_arn' deployment_state.json)
    
    # Start task execution
    EXECUTION_ARN=$(aws datasync start-task-execution \
        --task-arn ${TASK_ARN} \
        --query 'TaskExecutionArn' --output text)
    
    if [ -z "$EXECUTION_ARN" ]; then
        error "Failed to start DataSync task execution"
        exit 1
    fi
    
    success "DataSync task execution started: ${EXECUTION_ARN}"
    
    # Monitor task execution
    log "Monitoring task execution progress..."
    local timeout=300  # 5 minutes timeout
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        STATUS=$(aws datasync describe-task-execution \
            --task-execution-arn ${EXECUTION_ARN} \
            --query 'Status' --output text)
        
        case $STATUS in
            "SUCCESS")
                success "Task execution completed successfully"
                break
                ;;
            "ERROR")
                error "Task execution failed"
                aws datasync describe-task-execution \
                    --task-execution-arn ${EXECUTION_ARN} \
                    --query 'Result' --output text
                exit 1
                ;;
            "QUEUED"|"LAUNCHING"|"PREPARING"|"TRANSFERRING"|"VERIFYING")
                log "Task status: ${STATUS} - waiting..."
                sleep 10
                elapsed=$((elapsed + 10))
                ;;
            *)
                warning "Unknown status: ${STATUS}"
                sleep 10
                elapsed=$((elapsed + 10))
                ;;
        esac
    done
    
    if [ $elapsed -ge $timeout ]; then
        warning "Task execution timed out after 5 minutes. Check AWS console for status."
    fi
    
    # Update deployment state
    jq --arg execution_arn "$EXECUTION_ARN" \
       '. + {execution_arn: $execution_arn}' \
       deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Verify EFS file system
    EFS_ID=$(jq -r '.efs_id' deployment_state.json)
    EFS_STATUS=$(aws efs describe-file-systems \
        --file-system-id ${EFS_ID} \
        --query 'FileSystems[0].LifeCycleState' --output text)
    
    if [ "$EFS_STATUS" = "available" ]; then
        success "EFS file system is available"
    else
        warning "EFS file system status: $EFS_STATUS"
    fi
    
    # Verify S3 bucket
    SOURCE_BUCKET=$(jq -r '.source_bucket' deployment_state.json)
    if aws s3 ls s3://${SOURCE_BUCKET} > /dev/null 2>&1; then
        success "S3 bucket is accessible"
    else
        warning "S3 bucket may not be accessible"
    fi
    
    # Verify DataSync task
    TASK_ARN=$(jq -r '.task_arn' deployment_state.json)
    TASK_STATUS=$(aws datasync describe-task \
        --task-arn ${TASK_ARN} \
        --query 'Status' --output text)
    
    if [ "$TASK_STATUS" = "AVAILABLE" ]; then
        success "DataSync task is available"
    else
        warning "DataSync task status: $TASK_STATUS"
    fi
    
    # Display task execution results if available
    if [ -n "$(jq -r '.execution_arn' deployment_state.json)" ] && [ "$(jq -r '.execution_arn' deployment_state.json)" != "null" ]; then
        EXECUTION_ARN=$(jq -r '.execution_arn' deployment_state.json)
        log "DataSync execution results:"
        aws datasync describe-task-execution \
            --task-execution-arn ${EXECUTION_ARN} \
            --query '{
                Status: Status,
                BytesTransferred: BytesTransferred,
                FilesTransferred: FilesTransferred,
                StartTime: StartTime
            }' --output table
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "=================================="
    
    if [ -f deployment_state.json ]; then
        echo "AWS Region: $(jq -r '.aws_region' deployment_state.json)"
        echo "VPC ID: $(jq -r '.vpc_id' deployment_state.json)"
        echo "EFS ID: $(jq -r '.efs_id' deployment_state.json)"
        echo "S3 Bucket: $(jq -r '.source_bucket' deployment_state.json)"
        echo "DataSync Task: $(jq -r '.task_arn' deployment_state.json)"
        echo ""
        echo "State file: deployment_state.json"
        echo "Use this file with destroy.sh to clean up resources"
    else
        warning "Deployment state file not found"
    fi
    
    echo "=================================="
}

# Function to cleanup on error
cleanup_on_error() {
    error "Deployment failed. Cleaning up partial resources..."
    if [ -f deployment_state.json ]; then
        warning "Running cleanup script..."
        # Don't exit on cleanup errors
        set +e
        ./destroy.sh || true
        set -e
    fi
}

# Main deployment function
main() {
    log "Starting DataSync and EFS deployment..."
    
    # Set trap for cleanup on error
    trap cleanup_on_error ERR
    
    check_prerequisites
    set_environment_variables
    create_vpc_networking
    create_efs_filesystem
    create_s3_source
    create_iam_role
    create_datasync_locations
    create_datasync_task
    execute_datasync_task
    validate_deployment
    display_summary
    
    success "Deployment completed successfully!"
    log "You can now test file synchronization between S3 and EFS"
    log "Run './destroy.sh' to clean up all resources when done"
}

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    error "jq is required but not installed. Please install jq to continue."
    exit 1
fi

# Run main function
main "$@"