#!/bin/bash

# AWS FSx High-Performance File Systems Deployment Script
# This script deploys Amazon FSx file systems for Lustre, Windows, and NetApp ONTAP
# Recipe: High-Throughput Shared Storage System

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_NAME="FSx Deployment"
LOG_FILE="/tmp/fsx-deploy-$(date +%Y%m%d-%H%M%S).log"
DEPLOYMENT_START_TIME=$(date +%s)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    log ERROR "Script failed at line $line_number with exit code $exit_code"
    log ERROR "Check log file: $LOG_FILE"
    cleanup_on_failure
    exit $exit_code
}

# Trap errors
trap 'handle_error $LINENO' ERR

# Cleanup function for partial deployments
cleanup_on_failure() {
    log WARNING "Deployment failed. Cleaning up partial resources..."
    
    # Only cleanup resources that might exist
    if [[ -n "${LUSTRE_FS_ID:-}" ]]; then
        log INFO "Attempting to delete Lustre file system: $LUSTRE_FS_ID"
        aws fsx delete-file-system --file-system-id "$LUSTRE_FS_ID" 2>/dev/null || true
    fi
    
    if [[ -n "${WINDOWS_FS_ID:-}" ]]; then
        log INFO "Attempting to delete Windows file system: $WINDOWS_FS_ID"
        aws fsx delete-file-system --file-system-id "$WINDOWS_FS_ID" 2>/dev/null || true
    fi
    
    if [[ -n "${ONTAP_FS_ID:-}" ]]; then
        log INFO "Attempting to delete ONTAP file system: $ONTAP_FS_ID"
        aws fsx delete-file-system --file-system-id "$ONTAP_FS_ID" 2>/dev/null || true
    fi
    
    if [[ -n "${FSX_SG_ID:-}" ]]; then
        log INFO "Attempting to delete security group: $FSX_SG_ID"
        aws ec2 delete-security-group --group-id "$FSX_SG_ID" 2>/dev/null || true
    fi
    
    if [[ -n "${S3_BUCKET:-}" ]]; then
        log INFO "Attempting to delete S3 bucket: $S3_BUCKET"
        aws s3 rb "s3://$S3_BUCKET" --force 2>/dev/null || true
    fi
}

# Prerequisites check function
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log ERROR "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log ERROR "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check required permissions (basic check)
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$account_id" ]]; then
        log ERROR "Unable to retrieve AWS account ID"
        exit 1
    fi
    
    # Check AWS region
    local region
    region=$(aws configure get region)
    if [[ -z "$region" ]]; then
        log ERROR "AWS region not configured"
        exit 1
    fi
    
    # Check FSx service availability in region
    if ! aws fsx describe-file-systems --query 'FileSystems[0]' &> /dev/null; then
        if [[ $? -eq 255 ]]; then
            log ERROR "FSx service is not available in region: $region"
            exit 1
        fi
    fi
    
    log SUCCESS "Prerequisites check completed"
}

# Resource existence check
check_existing_resources() {
    log INFO "Checking for existing resources with prefix: $FSX_PREFIX"
    
    # Check for existing security groups
    local existing_sg
    existing_sg=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${FSX_PREFIX}-sg" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")
    
    if [[ "$existing_sg" != "None" && "$existing_sg" != "null" ]]; then
        log WARNING "Security group ${FSX_PREFIX}-sg already exists: $existing_sg"
        read -p "Continue with existing security group? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Deployment cancelled by user"
            exit 0
        fi
        FSX_SG_ID="$existing_sg"
        REUSE_SECURITY_GROUP=true
    fi
    
    # Check for existing S3 bucket
    if aws s3 ls "s3://$S3_BUCKET" &> /dev/null; then
        log WARNING "S3 bucket $S3_BUCKET already exists"
        read -p "Continue with existing S3 bucket? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Deployment cancelled by user"
            exit 0
        fi
        REUSE_S3_BUCKET=true
    fi
}

# Wait for resource function with timeout
wait_for_resource() {
    local resource_type=$1
    local resource_id=$2
    local timeout=${3:-1800}  # 30 minutes default
    local start_time=$(date +%s)
    
    log INFO "Waiting for $resource_type $resource_id to become available (timeout: ${timeout}s)..."
    
    case $resource_type in
        "file-system")
            if ! aws fsx wait file-system-available --file-system-ids "$resource_id" --cli-read-timeout "$timeout"; then
                log ERROR "Timeout waiting for file system $resource_id"
                return 1
            fi
            ;;
        "storage-virtual-machine")
            if ! aws fsx wait storage-virtual-machine-available --storage-virtual-machine-ids "$resource_id" --cli-read-timeout "$timeout"; then
                log ERROR "Timeout waiting for SVM $resource_id"
                return 1
            fi
            ;;
        "instance")
            if ! aws ec2 wait instance-running --instance-ids "$resource_id" --cli-read-timeout "$timeout"; then
                log ERROR "Timeout waiting for instance $resource_id"
                return 1
            fi
            ;;
    esac
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log SUCCESS "$resource_type $resource_id is now available (waited ${duration}s)"
}

# Display banner
echo "==========================================================="
echo "    AWS FSx High-Performance File Systems Deployment"
echo "==========================================================="
echo ""

log INFO "Starting $SCRIPT_NAME at $(date)"
log INFO "Log file: $LOG_FILE"

# Check prerequisites
check_prerequisites

log INFO "Setting up environment variables..."

# Set environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

export FSX_PREFIX="fsx-demo-${RANDOM_SUFFIX}"
export VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' --output text)

if [[ "$VPC_ID" == "None" || "$VPC_ID" == "null" ]]; then
    log ERROR "No default VPC found. Please create a VPC first."
    exit 1
fi

log INFO "Using VPC: $VPC_ID"
log INFO "Resource prefix: $FSX_PREFIX"

# Set S3 bucket name
S3_BUCKET="${FSX_PREFIX}-lustre-data"

# Check for existing resources
check_existing_resources

# Create security group if not reusing existing one
if [[ "${REUSE_SECURITY_GROUP:-}" != "true" ]]; then
    log INFO "Creating security group for FSx file systems..."
    FSX_SG_ID=$(aws ec2 create-security-group \
        --group-name "${FSX_PREFIX}-sg" \
        --description "Security group for FSx file systems" \
        --vpc-id "$VPC_ID" \
        --query 'GroupId' --output text)
    
    log SUCCESS "Security group created: $FSX_SG_ID"
    
    # Add inbound rules for FSx protocols
    log INFO "Configuring security group rules..."
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$FSX_SG_ID" \
        --protocol tcp --port 988 --cidr 10.0.0.0/8 \
        --description "FSx Lustre traffic" || log WARNING "Rule may already exist"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$FSX_SG_ID" \
        --protocol tcp --port 445 --cidr 10.0.0.0/8 \
        --description "SMB traffic for Windows File Server" || log WARNING "Rule may already exist"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$FSX_SG_ID" \
        --protocol tcp --port 111 --cidr 10.0.0.0/8 \
        --description "NFS traffic for ONTAP" || log WARNING "Rule may already exist"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$FSX_SG_ID" \
        --protocol tcp --port 2049 --cidr 10.0.0.0/8 \
        --description "NFS traffic for ONTAP" || log WARNING "Rule may already exist"
    
    log SUCCESS "Security group rules configured"
fi

# Get subnet IDs for deployment
log INFO "Getting subnet information..."
SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[?AvailabilityZone!=`us-east-1e`].SubnetId' \
    --output text)

if [[ -z "$SUBNET_IDS" ]]; then
    log ERROR "No suitable subnets found in VPC $VPC_ID"
    exit 1
fi

SUBNET_1=$(echo "$SUBNET_IDS" | cut -d' ' -f1)
SUBNET_2=$(echo "$SUBNET_IDS" | cut -d' ' -f2)

if [[ -z "$SUBNET_2" ]]; then
    SUBNET_2="$SUBNET_1"
    log WARNING "Only one subnet available, using $SUBNET_1 for all deployments"
fi

log INFO "Using subnets: $SUBNET_1, $SUBNET_2"

# Create S3 bucket if not reusing existing one
if [[ "${REUSE_S3_BUCKET:-}" != "true" ]]; then
    log INFO "Creating S3 bucket for FSx Lustre data repository..."
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://$S3_BUCKET"
    else
        aws s3 mb "s3://$S3_BUCKET" --region "$AWS_REGION"
    fi
    log SUCCESS "S3 bucket created: $S3_BUCKET"
fi

# Step 1: Create FSx for Lustre File System
log INFO "Creating FSx for Lustre file system..."
LUSTRE_FS_ID=$(aws fsx create-file-system \
    --file-system-type Lustre \
    --storage-capacity 1200 \
    --subnet-ids "$SUBNET_1" \
    --security-group-ids "$FSX_SG_ID" \
    --lustre-configuration \
    "DeploymentType=SCRATCH_2,DataRepositoryConfiguration={Bucket=$S3_BUCKET,ImportPath=s3://$S3_BUCKET/input/,ExportPath=s3://$S3_BUCKET/output/},PerUnitStorageThroughput=250" \
    --tags "Key=Name,Value=${FSX_PREFIX}-lustre" \
    --tags "Key=Purpose,Value=HPC-Workloads" \
    --query 'FileSystem.FileSystemId' --output text)

log SUCCESS "FSx for Lustre created: $LUSTRE_FS_ID"

# Wait for Lustre file system to become available
wait_for_resource "file-system" "$LUSTRE_FS_ID"

# Step 2: Create FSx for Windows File Server
log INFO "Creating FSx for Windows File Server..."
WINDOWS_FS_ID=$(aws fsx create-file-system \
    --file-system-type Windows \
    --storage-capacity 32 \
    --subnet-ids "$SUBNET_1" \
    --security-group-ids "$FSX_SG_ID" \
    --windows-configuration \
    "ThroughputCapacity=8,DeploymentType=SINGLE_AZ_1,PreferredSubnetId=$SUBNET_1" \
    --tags "Key=Name,Value=${FSX_PREFIX}-windows" \
    --tags "Key=Purpose,Value=Windows-Applications" \
    --query 'FileSystem.FileSystemId' --output text)

log SUCCESS "FSx for Windows created: $WINDOWS_FS_ID"

# Wait for Windows file system to become available
wait_for_resource "file-system" "$WINDOWS_FS_ID"

# Step 3: Create FSx for NetApp ONTAP File System
log INFO "Creating FSx for NetApp ONTAP file system..."
ONTAP_FS_ID=$(aws fsx create-file-system \
    --file-system-type ONTAP \
    --storage-capacity 1024 \
    --subnet-ids "$SUBNET_1" "$SUBNET_2" \
    --security-group-ids "$FSX_SG_ID" \
    --ontap-configuration \
    "DeploymentType=MULTI_AZ_1,ThroughputCapacity=256,PreferredSubnetId=$SUBNET_1,FsxAdminPassword=TempPassword123!" \
    --tags "Key=Name,Value=${FSX_PREFIX}-ontap" \
    --tags "Key=Purpose,Value=Multi-Protocol-Access" \
    --query 'FileSystem.FileSystemId' --output text)

log SUCCESS "FSx for NetApp ONTAP created: $ONTAP_FS_ID"

# Wait for ONTAP file system to become available
wait_for_resource "file-system" "$ONTAP_FS_ID"

# Step 4: Create Storage Virtual Machine (SVM) for ONTAP
log INFO "Creating Storage Virtual Machine for ONTAP..."
SVM_ID=$(aws fsx create-storage-virtual-machine \
    --file-system-id "$ONTAP_FS_ID" \
    --name "demo-svm" \
    --svm-admin-password "TempPassword123!" \
    --tags "Key=Name,Value=${FSX_PREFIX}-svm" \
    --query 'StorageVirtualMachine.StorageVirtualMachineId' \
    --output text)

log SUCCESS "Storage Virtual Machine created: $SVM_ID"

# Wait for SVM to become available
wait_for_resource "storage-virtual-machine" "$SVM_ID"

# Step 5: Create ONTAP Volumes
log INFO "Creating NFS volume for ONTAP..."
NFS_VOLUME_ID=$(aws fsx create-volume \
    --volume-type ONTAP \
    --name "nfs-volume" \
    --ontap-configuration \
    "StorageVirtualMachineId=$SVM_ID,JunctionPath=/nfs,SecurityStyle=UNIX,SizeInMegabytes=102400,StorageEfficiencyEnabled=true" \
    --tags "Key=Name,Value=${FSX_PREFIX}-nfs-volume" \
    --query 'Volume.VolumeId' --output text)

log SUCCESS "NFS volume created: $NFS_VOLUME_ID"

log INFO "Creating SMB volume for ONTAP..."
SMB_VOLUME_ID=$(aws fsx create-volume \
    --volume-type ONTAP \
    --name "smb-volume" \
    --ontap-configuration \
    "StorageVirtualMachineId=$SVM_ID,JunctionPath=/smb,SecurityStyle=NTFS,SizeInMegabytes=51200,StorageEfficiencyEnabled=true" \
    --tags "Key=Name,Value=${FSX_PREFIX}-smb-volume" \
    --query 'Volume.VolumeId' --output text)

log SUCCESS "SMB volume created: $SMB_VOLUME_ID"

# Step 6: Configure CloudWatch Monitoring and Alarms
log INFO "Setting up CloudWatch monitoring and alarms..."

aws cloudwatch put-metric-alarm \
    --alarm-name "${FSX_PREFIX}-lustre-throughput" \
    --alarm-description "Monitor Lustre throughput utilization" \
    --metric-name ThroughputUtilization \
    --namespace AWS/FSx \
    --statistic Average \
    --period 300 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --dimensions "Name=FileSystemId,Value=$LUSTRE_FS_ID"

aws cloudwatch put-metric-alarm \
    --alarm-name "${FSX_PREFIX}-windows-cpu" \
    --alarm-description "Monitor Windows file system CPU" \
    --metric-name CPUUtilization \
    --namespace AWS/FSx \
    --statistic Average \
    --period 300 \
    --threshold 85 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --dimensions "Name=FileSystemId,Value=$WINDOWS_FS_ID"

aws cloudwatch put-metric-alarm \
    --alarm-name "${FSX_PREFIX}-ontap-storage" \
    --alarm-description "Monitor ONTAP storage utilization" \
    --metric-name StorageUtilization \
    --namespace AWS/FSx \
    --statistic Average \
    --period 300 \
    --threshold 90 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1 \
    --dimensions "Name=FileSystemId,Value=$ONTAP_FS_ID"

log SUCCESS "CloudWatch monitoring configured"

# Step 7: Create IAM role for FSx service access
log INFO "Creating IAM role for FSx service access..."
FSX_ROLE_NAME="${FSX_PREFIX}-service-role"

aws iam create-role \
    --role-name "$FSX_ROLE_NAME" \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "fsx.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }' > /dev/null

# Attach necessary policies for S3 access
aws iam attach-role-policy \
    --role-name "$FSX_ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"

log SUCCESS "IAM role configured: $FSX_ROLE_NAME"

# Step 8: Configure automated backup policies
log INFO "Setting up automated backup policies..."

aws fsx put-backup-policy \
    --file-system-id "$WINDOWS_FS_ID" \
    --backup-policy \
    "Status=ENABLED,DailyBackupStartTime=01:00,RetentionDays=7,CopyTagsToBackups=true" || log WARNING "Backup policy configuration may have failed for Windows FS"

aws fsx put-backup-policy \
    --file-system-id "$ONTAP_FS_ID" \
    --backup-policy \
    "Status=ENABLED,DailyBackupStartTime=02:00,RetentionDays=14,CopyTagsToBackups=true" || log WARNING "Backup policy configuration may have failed for ONTAP FS"

log SUCCESS "Automated backup policies configured"

# Save deployment information
DEPLOYMENT_INFO_FILE="/tmp/fsx-deployment-${RANDOM_SUFFIX}.info"
cat > "$DEPLOYMENT_INFO_FILE" << EOF
# FSx Deployment Information
# Generated on: $(date)
# Deployment ID: $RANDOM_SUFFIX

export FSX_PREFIX="$FSX_PREFIX"
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export VPC_ID="$VPC_ID"
export SUBNET_1="$SUBNET_1"
export SUBNET_2="$SUBNET_2"
export FSX_SG_ID="$FSX_SG_ID"
export S3_BUCKET="$S3_BUCKET"
export LUSTRE_FS_ID="$LUSTRE_FS_ID"
export WINDOWS_FS_ID="$WINDOWS_FS_ID"
export ONTAP_FS_ID="$ONTAP_FS_ID"
export SVM_ID="$SVM_ID"
export NFS_VOLUME_ID="$NFS_VOLUME_ID"
export SMB_VOLUME_ID="$SMB_VOLUME_ID"
export FSX_ROLE_NAME="$FSX_ROLE_NAME"
EOF

log SUCCESS "Deployment information saved to: $DEPLOYMENT_INFO_FILE"

# Calculate deployment time
DEPLOYMENT_END_TIME=$(date +%s)
DEPLOYMENT_DURATION=$((DEPLOYMENT_END_TIME - DEPLOYMENT_START_TIME))

# Final verification
log INFO "Performing final verification..."

# Verify all file systems
FSX_STATUS=$(aws fsx describe-file-systems \
    --file-system-ids "$LUSTRE_FS_ID" "$WINDOWS_FS_ID" "$ONTAP_FS_ID" \
    --query 'FileSystems[*].{ID:FileSystemId,Type:FileSystemType,State:Lifecycle}' \
    --output table)

echo ""
echo "=== File System Status ==="
echo "$FSX_STATUS"
echo ""

# Display connection information
echo "=== Connection Information ==="
echo ""

LUSTRE_DNS=$(aws fsx describe-file-systems \
    --file-system-ids "$LUSTRE_FS_ID" \
    --query 'FileSystems[0].DNSName' --output text)

LUSTRE_MOUNT_NAME=$(aws fsx describe-file-systems \
    --file-system-ids "$LUSTRE_FS_ID" \
    --query 'FileSystems[0].LustreConfiguration.MountName' \
    --output text)

WINDOWS_DNS=$(aws fsx describe-file-systems \
    --file-system-ids "$WINDOWS_FS_ID" \
    --query 'FileSystems[0].DNSName' --output text)

echo "Lustre File System:"
echo "  DNS Name: $LUSTRE_DNS"
echo "  Mount Command: sudo mount -t lustre $LUSTRE_DNS@tcp:/$LUSTRE_MOUNT_NAME /mnt/fsx"
echo ""
echo "Windows File System:"
echo "  DNS Name: $WINDOWS_DNS"
echo "  UNC Path: \\\\$WINDOWS_DNS\\share"
echo ""

# Display cost estimation
echo "=== Cost Estimation (per hour) ==="
echo "  Lustre (1200 GB, SCRATCH_2): ~\$1.20"
echo "  Windows (32 GB, Single-AZ): ~\$0.16"
echo "  ONTAP (1024 GB, Multi-AZ): ~\$1.84"
echo "  Total estimated: ~\$3.20/hour"
echo ""

log SUCCESS "Deployment completed successfully!"
log INFO "Total deployment time: ${DEPLOYMENT_DURATION} seconds"
log INFO "Log file available at: $LOG_FILE"
log INFO "Deployment info file: $DEPLOYMENT_INFO_FILE"

echo ""
echo "==========================================================="
echo "   AWS FSx High-Performance File Systems Deployed!"
echo "==========================================================="
echo ""
echo "Next steps:"
echo "1. Review the connection information above"
echo "2. Create EC2 instances to test file system access"
echo "3. Configure your applications to use the file systems"
echo "4. Monitor performance through CloudWatch dashboards"
echo ""
echo "To clean up all resources, run: ./destroy.sh"
echo ""