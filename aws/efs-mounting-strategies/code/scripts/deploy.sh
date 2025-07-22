#!/bin/bash

# Deploy script for EFS Mounting Strategies Recipe
# This script creates EFS file system with mount targets, access points, and EC2 instances

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warn "Running in DRY-RUN mode - no resources will be created"
fi

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/deployment.state"
CONFIG_FILE="${SCRIPT_DIR}/deployment.config"

# Function to save state
save_state() {
    local key="$1"
    local value="$2"
    
    # Create state file if it doesn't exist
    touch "$STATE_FILE"
    
    # Remove existing key if present
    grep -v "^${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
    mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true
    
    # Add new key-value pair
    echo "${key}=${value}" >> "$STATE_FILE"
}

# Function to load state
load_state() {
    local key="$1"
    if [[ -f "$STATE_FILE" ]]; then
        grep "^${key}=" "$STATE_FILE" | cut -d'=' -f2- || true
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some operations may not work properly."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    # Check if user has necessary permissions
    log "Verifying AWS permissions..."
    local test_commands=(
        "aws efs describe-file-systems --max-items 1"
        "aws ec2 describe-vpcs --max-items 1"
        "aws iam get-user"
    )
    
    for cmd in "${test_commands[@]}"; do
        if ! eval "$cmd" &> /dev/null; then
            error "Insufficient permissions to run: $cmd"
        fi
    done
    
    log "Prerequisites check passed ✅"
}

# Function to initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Load existing configuration if available
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log "Loaded existing configuration from $CONFIG_FILE"
    fi
    
    # Set AWS region
    export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not configured. Please set AWS_REGION environment variable or run 'aws configure'."
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers if not already set
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            echo "$(date +%s | tail -c 6)")
    fi
    
    # Set resource names
    export EFS_NAME="${EFS_NAME:-efs-demo-${RANDOM_SUFFIX}}"
    export VPC_NAME="${VPC_NAME:-efs-vpc-${RANDOM_SUFFIX}}"
    export INSTANCE_NAME="${INSTANCE_NAME:-efs-instance-${RANDOM_SUFFIX}}"
    
    # Get or create VPC
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")
    
    if [[ "$VPC_ID" == "None" ]]; then
        warn "No default VPC found. You may need to create one."
    fi
    
    # Get subnets in different AZs
    local subnet_ids=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query "Subnets[*].SubnetId" --output text)
    
    export SUBNET_A=$(echo $subnet_ids | cut -d' ' -f1)
    export SUBNET_B=$(echo $subnet_ids | cut -d' ' -f2)
    export SUBNET_C=$(echo $subnet_ids | cut -d' ' -f3)
    
    if [[ -z "$SUBNET_A" || -z "$SUBNET_B" ]]; then
        error "At least two subnets required in different availability zones"
    fi
    
    # Get latest Amazon Linux 2 AMI
    export AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
        --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" \
        --output text)
    
    # Save configuration
    cat > "$CONFIG_FILE" << EOF
AWS_REGION="$AWS_REGION"
AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
EFS_NAME="$EFS_NAME"
VPC_NAME="$VPC_NAME"
INSTANCE_NAME="$INSTANCE_NAME"
VPC_ID="$VPC_ID"
SUBNET_A="$SUBNET_A"
SUBNET_B="$SUBNET_B"
SUBNET_C="$SUBNET_C"
AMI_ID="$AMI_ID"
EOF
    
    log "Environment initialized ✅"
    info "VPC ID: $VPC_ID"
    info "Subnets: $SUBNET_A, $SUBNET_B, $SUBNET_C"
    info "Random suffix: $RANDOM_SUFFIX"
}

# Function to create EFS file system
create_efs_filesystem() {
    log "Creating EFS file system..."
    
    # Check if EFS already exists
    local existing_efs=$(load_state "EFS_ID")
    if [[ -n "$existing_efs" ]]; then
        local efs_state=$(aws efs describe-file-systems \
            --file-system-id "$existing_efs" \
            --query "FileSystems[0].LifeCycleState" --output text 2>/dev/null || echo "not-found")
        
        if [[ "$efs_state" == "available" ]]; then
            export EFS_ID="$existing_efs"
            log "Using existing EFS file system: $EFS_ID"
            return 0
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create EFS file system with name: $EFS_NAME"
        export EFS_ID="fs-dryrun123456"
        return 0
    fi
    
    # Create EFS file system
    export EFS_ID=$(aws efs create-file-system \
        --performance-mode generalPurpose \
        --throughput-mode provisioned \
        --provisioned-throughput-in-mibps 100 \
        --encrypted \
        --tags Key=Name,Value="$EFS_NAME" \
        --query "FileSystemId" --output text)
    
    save_state "EFS_ID" "$EFS_ID"
    
    # Wait for file system to become available
    log "Waiting for EFS file system to become available..."
    aws efs wait file-system-available --file-system-id "$EFS_ID"
    
    log "EFS file system created successfully: $EFS_ID ✅"
}

# Function to create security group
create_security_group() {
    log "Creating security group for EFS..."
    
    # Check if security group already exists
    local existing_sg=$(load_state "SG_ID")
    if [[ -n "$existing_sg" ]]; then
        local sg_exists=$(aws ec2 describe-security-groups \
            --group-ids "$existing_sg" \
            --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "not-found")
        
        if [[ "$sg_exists" != "not-found" ]]; then
            export SG_ID="$existing_sg"
            log "Using existing security group: $SG_ID"
            return 0
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create security group: efs-mount-sg-${RANDOM_SUFFIX}"
        export SG_ID="sg-dryrun123456"
        return 0
    fi
    
    # Create security group
    export SG_ID=$(aws ec2 create-security-group \
        --group-name "efs-mount-sg-${RANDOM_SUFFIX}" \
        --description "Security group for EFS mount targets" \
        --vpc-id "$VPC_ID" \
        --query "GroupId" --output text)
    
    save_state "SG_ID" "$SG_ID"
    
    # Get VPC CIDR
    local vpc_cidr=$(aws ec2 describe-vpcs \
        --vpc-ids "$VPC_ID" \
        --query "Vpcs[0].CidrBlock" --output text)
    
    # Allow NFS traffic from VPC CIDR
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 2049 \
        --cidr "$vpc_cidr"
    
    log "Security group created successfully: $SG_ID ✅"
}

# Function to create mount targets
create_mount_targets() {
    log "Creating mount targets..."
    
    # Check if mount targets already exist
    local existing_mt_a=$(load_state "MT_A")
    local existing_mt_b=$(load_state "MT_B")
    
    if [[ -n "$existing_mt_a" && -n "$existing_mt_b" ]]; then
        local mt_a_state=$(aws efs describe-mount-targets \
            --mount-target-id "$existing_mt_a" \
            --query "MountTargets[0].LifeCycleState" --output text 2>/dev/null || echo "not-found")
        
        if [[ "$mt_a_state" == "available" ]]; then
            export MT_A="$existing_mt_a"
            export MT_B="$existing_mt_b"
            log "Using existing mount targets: $MT_A, $MT_B"
            return 0
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create mount targets in subnets: $SUBNET_A, $SUBNET_B"
        export MT_A="fsmt-dryrun123456"
        export MT_B="fsmt-dryrun789012"
        return 0
    fi
    
    # Create mount target in first AZ
    export MT_A=$(aws efs create-mount-target \
        --file-system-id "$EFS_ID" \
        --subnet-id "$SUBNET_A" \
        --security-groups "$SG_ID" \
        --query "MountTargetId" --output text)
    
    save_state "MT_A" "$MT_A"
    
    # Create mount target in second AZ
    export MT_B=$(aws efs create-mount-target \
        --file-system-id "$EFS_ID" \
        --subnet-id "$SUBNET_B" \
        --security-groups "$SG_ID" \
        --query "MountTargetId" --output text)
    
    save_state "MT_B" "$MT_B"
    
    # Create mount target in third AZ if available
    if [[ -n "$SUBNET_C" ]]; then
        export MT_C=$(aws efs create-mount-target \
            --file-system-id "$EFS_ID" \
            --subnet-id "$SUBNET_C" \
            --security-groups "$SG_ID" \
            --query "MountTargetId" --output text 2>/dev/null || echo "")
        
        if [[ -n "$MT_C" ]]; then
            save_state "MT_C" "$MT_C"
        fi
    fi
    
    # Wait for mount targets to become available
    log "Waiting for mount targets to become available..."
    aws efs wait mount-target-available --mount-target-id "$MT_A"
    aws efs wait mount-target-available --mount-target-id "$MT_B"
    
    if [[ -n "${MT_C:-}" ]]; then
        aws efs wait mount-target-available --mount-target-id "$MT_C"
        log "Mount targets created successfully: $MT_A, $MT_B, $MT_C ✅"
    else
        log "Mount targets created successfully: $MT_A, $MT_B ✅"
    fi
}

# Function to create access points
create_access_points() {
    log "Creating EFS access points..."
    
    # Check if access points already exist
    local existing_ap_app=$(load_state "AP_APP")
    if [[ -n "$existing_ap_app" ]]; then
        local ap_exists=$(aws efs describe-access-points \
            --access-point-id "$existing_ap_app" \
            --query "AccessPoints[0].AccessPointId" --output text 2>/dev/null || echo "not-found")
        
        if [[ "$ap_exists" != "not-found" ]]; then
            export AP_APP="$existing_ap_app"
            export AP_USER=$(load_state "AP_USER")
            export AP_LOGS=$(load_state "AP_LOGS")
            log "Using existing access points"
            return 0
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create access points for app-data, user-data, and logs"
        export AP_APP="fsap-dryrun123456"
        export AP_USER="fsap-dryrun789012"
        export AP_LOGS="fsap-dryrun345678"
        return 0
    fi
    
    # Create access point for application data
    export AP_APP=$(aws efs create-access-point \
        --file-system-id "$EFS_ID" \
        --posix-user Uid=1000,Gid=1000 \
        --root-directory 'Path="/app-data",CreationInfo={
            "OwnerUid": 1000,
            "OwnerGid": 1000,
            "Permissions": "0755"
        }' \
        --tags Key=Name,Value="app-data-access-point" \
        --query "AccessPointId" --output text)
    
    save_state "AP_APP" "$AP_APP"
    
    # Create access point for user data
    export AP_USER=$(aws efs create-access-point \
        --file-system-id "$EFS_ID" \
        --posix-user Uid=2000,Gid=2000 \
        --root-directory 'Path="/user-data",CreationInfo={
            "OwnerUid": 2000,
            "OwnerGid": 2000,
            "Permissions": "0750"
        }' \
        --tags Key=Name,Value="user-data-access-point" \
        --query "AccessPointId" --output text)
    
    save_state "AP_USER" "$AP_USER"
    
    # Create access point for logs
    export AP_LOGS=$(aws efs create-access-point \
        --file-system-id "$EFS_ID" \
        --posix-user Uid=3000,Gid=3000 \
        --root-directory 'Path="/logs",CreationInfo={
            "OwnerUid": 3000,
            "OwnerGid": 3000,
            "Permissions": "0755"
        }' \
        --tags Key=Name,Value="logs-access-point" \
        --query "AccessPointId" --output text)
    
    save_state "AP_LOGS" "$AP_LOGS"
    
    log "Access points created successfully: $AP_APP, $AP_USER, $AP_LOGS ✅"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for EC2 EFS access..."
    
    # Check if IAM role already exists
    local role_name="EFS-EC2-Role-${RANDOM_SUFFIX}"
    local existing_role=$(aws iam get-role --role-name "$role_name" --query "Role.RoleName" --output text 2>/dev/null || echo "not-found")
    
    if [[ "$existing_role" != "not-found" ]]; then
        log "Using existing IAM role: $role_name"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create IAM role: $role_name"
        return 0
    fi
    
    # Create IAM role
    aws iam create-role \
        --role-name "$role_name" \
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
        }' > /dev/null
    
    # Create and attach EFS policy
    aws iam put-role-policy \
        --role-name "$role_name" \
        --policy-name "EFS-Access-Policy" \
        --policy-document "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Action\": [
                        \"elasticfilesystem:ClientMount\",
                        \"elasticfilesystem:ClientWrite\",
                        \"elasticfilesystem:ClientRootAccess\"
                    ],
                    \"Resource\": \"arn:aws:elasticfilesystem:${AWS_REGION}:${AWS_ACCOUNT_ID}:file-system/${EFS_ID}\"
                }
            ]
        }" > /dev/null
    
    # Create instance profile
    local profile_name="EFS-EC2-Profile-${RANDOM_SUFFIX}"
    aws iam create-instance-profile \
        --instance-profile-name "$profile_name" > /dev/null
    
    aws iam add-role-to-instance-profile \
        --instance-profile-name "$profile_name" \
        --role-name "$role_name" > /dev/null
    
    # Wait for IAM role to propagate
    sleep 10
    
    save_state "IAM_ROLE" "$role_name"
    save_state "IAM_PROFILE" "$profile_name"
    
    log "IAM role and instance profile created successfully ✅"
}

# Function to launch EC2 instance
launch_ec2_instance() {
    log "Launching EC2 instance with EFS utils..."
    
    # Check if instance already exists
    local existing_instance=$(load_state "INSTANCE_ID")
    if [[ -n "$existing_instance" ]]; then
        local instance_state=$(aws ec2 describe-instances \
            --instance-ids "$existing_instance" \
            --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null || echo "not-found")
        
        if [[ "$instance_state" == "running" ]]; then
            export INSTANCE_ID="$existing_instance"
            log "Using existing EC2 instance: $INSTANCE_ID"
            return 0
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would launch EC2 instance: $INSTANCE_NAME"
        export INSTANCE_ID="i-dryrun123456"
        return 0
    fi
    
    # Create user data script
    local user_data_script=$(cat << 'EOF'
#!/bin/bash
yum update -y
yum install -y amazon-efs-utils
mkdir -p /mnt/efs
mkdir -p /mnt/efs-app
mkdir -p /mnt/efs-user
mkdir -p /mnt/efs-logs
EOF
)
    
    # Launch EC2 instance
    export INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type t3.micro \
        --subnet-id "$SUBNET_A" \
        --security-group-ids "$SG_ID" \
        --iam-instance-profile Name="EFS-EC2-Profile-${RANDOM_SUFFIX}" \
        --user-data "$user_data_script" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
        --query "Instances[0].InstanceId" --output text)
    
    save_state "INSTANCE_ID" "$INSTANCE_ID"
    
    # Wait for instance to be running
    log "Waiting for EC2 instance to be running..."
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
    
    log "EC2 instance launched successfully: $INSTANCE_ID ✅"
}

# Function to create mount scripts
create_mount_scripts() {
    log "Creating mount scripts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create mount scripts"
        return 0
    fi
    
    # Create scripts directory
    mkdir -p "${SCRIPT_DIR}/mount-scripts"
    
    # Create standard NFS mount script
    cat > "${SCRIPT_DIR}/mount-scripts/standard-nfs-mount.sh" << EOF
#!/bin/bash
# Standard NFS mount script

# Mount EFS using standard NFS
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600,retrans=2 \\
    ${EFS_ID}.efs.${AWS_REGION}.amazonaws.com:/ /mnt/efs

# Verify mount
df -h /mnt/efs
echo "✅ Standard NFS mount completed"
EOF
    
    # Create EFS utils mount script
    cat > "${SCRIPT_DIR}/mount-scripts/efs-utils-mount.sh" << EOF
#!/bin/bash
# EFS utils mount script

# Mount using EFS utils with TLS encryption
sudo mount -t efs -o tls ${EFS_ID}:/ /mnt/efs

# Mount using access points
sudo mount -t efs -o tls,accesspoint=${AP_APP} ${EFS_ID}:/ /mnt/efs-app
sudo mount -t efs -o tls,accesspoint=${AP_USER} ${EFS_ID}:/ /mnt/efs-user
sudo mount -t efs -o tls,accesspoint=${AP_LOGS} ${EFS_ID}:/ /mnt/efs-logs

# Verify all mounts
df -h | grep efs
echo "✅ EFS utils mounts completed"
EOF
    
    # Create fstab configuration script
    cat > "${SCRIPT_DIR}/mount-scripts/fstab-config.sh" << EOF
#!/bin/bash
# fstab configuration script

# Backup original fstab
sudo cp /etc/fstab /etc/fstab.backup

# Add EFS entries to fstab for automatic mounting
echo "${EFS_ID}.efs.${AWS_REGION}.amazonaws.com:/ /mnt/efs efs defaults,_netdev,tls" | sudo tee -a /etc/fstab
echo "${EFS_ID}.efs.${AWS_REGION}.amazonaws.com:/ /mnt/efs-app efs defaults,_netdev,tls,accesspoint=${AP_APP}" | sudo tee -a /etc/fstab
echo "${EFS_ID}.efs.${AWS_REGION}.amazonaws.com:/ /mnt/efs-user efs defaults,_netdev,tls,accesspoint=${AP_USER}" | sudo tee -a /etc/fstab
echo "${EFS_ID}.efs.${AWS_REGION}.amazonaws.com:/ /mnt/efs-logs efs defaults,_netdev,tls,accesspoint=${AP_LOGS}" | sudo tee -a /etc/fstab

# Mount all entries
sudo mount -a

echo "✅ Automatic mounting configured"
EOF
    
    # Make scripts executable
    chmod +x "${SCRIPT_DIR}/mount-scripts/"*.sh
    
    log "Mount scripts created successfully ✅"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "EFS File System ID: ${EFS_ID}"
    echo "Security Group ID: ${SG_ID}"
    echo "Mount Target A: ${MT_A}"
    echo "Mount Target B: ${MT_B}"
    [[ -n "${MT_C:-}" ]] && echo "Mount Target C: ${MT_C}"
    echo "Access Point (App): ${AP_APP}"
    echo "Access Point (User): ${AP_USER}"
    echo "Access Point (Logs): ${AP_LOGS}"
    echo "EC2 Instance ID: ${INSTANCE_ID}"
    echo "IAM Role: EFS-EC2-Role-${RANDOM_SUFFIX}"
    echo "IAM Instance Profile: EFS-EC2-Profile-${RANDOM_SUFFIX}"
    echo ""
    echo "Mount scripts created in: ${SCRIPT_DIR}/mount-scripts/"
    echo ""
    echo "To connect to the instance:"
    if [[ "$DRY_RUN" != "true" ]]; then
        local instance_ip=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --query "Reservations[0].Instances[0].PublicIpAddress" \
            --output text 2>/dev/null || echo "N/A")
        echo "ssh -i your-key.pem ec2-user@${instance_ip}"
    else
        echo "ssh -i your-key.pem ec2-user@<instance-public-ip>"
    fi
    echo ""
    echo "To run cleanup:"
    echo "./destroy.sh"
}

# Main execution
main() {
    log "Starting EFS Mounting Strategies deployment..."
    
    check_prerequisites
    initialize_environment
    create_efs_filesystem
    create_security_group
    create_mount_targets
    create_access_points
    create_iam_role
    launch_ec2_instance
    create_mount_scripts
    
    display_summary
    
    log "Deployment completed successfully! ✅"
}

# Trap errors and cleanup
trap 'error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"