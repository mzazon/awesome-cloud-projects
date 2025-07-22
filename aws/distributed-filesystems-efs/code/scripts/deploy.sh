#!/bin/bash

# Deploy script for Building Distributed File Systems with Amazon EFS
# This script creates a complete EFS setup with multi-AZ mount targets,
# access points, EC2 instances, and monitoring

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
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

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    log "Running in dry-run mode - no resources will be created"
fi

# Function to execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        log "$description"
        eval "$cmd"
        return $?
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if we have necessary permissions
    if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity --query 'Arn' --output text | grep -q 'assumed-role'; then
        error "Unable to verify AWS credentials. Please check your configuration."
        exit 1
    fi
    
    # Check if ssh command is available
    if ! command -v ssh &> /dev/null; then
        error "SSH client is not installed. Please install it first."
        exit 1
    fi
    
    # Check if fio is available on the system (for performance testing)
    if ! command -v fio &> /dev/null; then
        warning "fio (Flexible I/O Tester) is not installed locally. It will be installed on EC2 instances."
    fi
    
    success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No region configured, using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export EFS_NAME="distributed-efs-${RANDOM_SUFFIX}"
    export KEY_PAIR_NAME="efs-demo-${RANDOM_SUFFIX}"
    
    # Get VPC information
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
        error "No default VPC found. Please create a VPC first."
        exit 1
    fi
    
    # Get subnets from different AZs
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[].SubnetId' --output text)
    
    if [ -z "$SUBNET_IDS" ]; then
        error "No subnets found in VPC $VPC_ID"
        exit 1
    fi
    
    export SUBNET_1=$(echo $SUBNET_IDS | cut -d' ' -f1)
    export SUBNET_2=$(echo $SUBNET_IDS | cut -d' ' -f2)
    export SUBNET_3=$(echo $SUBNET_IDS | cut -d' ' -f3)
    
    # Ensure we have at least 2 subnets in different AZs
    if [ -z "$SUBNET_2" ]; then
        error "At least 2 subnets in different AZs are required"
        exit 1
    fi
    
    # Use first subnet for third if not available
    if [ -z "$SUBNET_3" ]; then
        export SUBNET_3=$SUBNET_1
        warning "Only 2 subnets available, using subnet 1 for third mount target"
    fi
    
    success "Environment variables configured"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "EFS Name: $EFS_NAME"
    log "VPC ID: $VPC_ID"
    log "Subnets: $SUBNET_1, $SUBNET_2, $SUBNET_3"
}

# Function to create key pair
create_key_pair() {
    log "Creating key pair for EC2 instances..."
    
    # Create .ssh directory if it doesn't exist
    mkdir -p ~/.ssh
    
    # Create key pair
    execute_cmd "aws ec2 create-key-pair \
        --key-name $KEY_PAIR_NAME \
        --query 'KeyMaterial' --output text > ~/.ssh/${KEY_PAIR_NAME}.pem" \
        "Creating key pair"
    
    if [ "$DRY_RUN" = false ]; then
        chmod 600 ~/.ssh/${KEY_PAIR_NAME}.pem
        success "Key pair created: $KEY_PAIR_NAME"
    fi
}

# Function to create security groups
create_security_groups() {
    log "Creating security groups..."
    
    # Create security group for EFS
    export EFS_SG_ID=$(execute_cmd "aws ec2 create-security-group \
        --group-name \"efs-sg-${RANDOM_SUFFIX}\" \
        --description \"Security group for EFS mount targets\" \
        --vpc-id $VPC_ID \
        --query 'GroupId' --output text" \
        "Creating EFS security group")
    
    # Create security group for EC2 instances
    export EC2_SG_ID=$(execute_cmd "aws ec2 create-security-group \
        --group-name \"efs-client-sg-${RANDOM_SUFFIX}\" \
        --description \"Security group for EFS client instances\" \
        --vpc-id $VPC_ID \
        --query 'GroupId' --output text" \
        "Creating EC2 security group")
    
    if [ "$DRY_RUN" = false ]; then
        # Configure EFS security group rules
        execute_cmd "aws ec2 authorize-security-group-ingress \
            --group-id $EFS_SG_ID \
            --protocol tcp \
            --port 2049 \
            --source-group $EC2_SG_ID" \
            "Configuring EFS security group ingress"
        
        # Configure EC2 security group rules
        execute_cmd "aws ec2 authorize-security-group-ingress \
            --group-id $EC2_SG_ID \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0" \
            "Configuring EC2 security group SSH access"
        
        execute_cmd "aws ec2 authorize-security-group-ingress \
            --group-id $EC2_SG_ID \
            --protocol tcp \
            --port 80 \
            --cidr 0.0.0.0/0" \
            "Configuring EC2 security group HTTP access"
        
        success "Security groups created - EFS: $EFS_SG_ID, EC2: $EC2_SG_ID"
    fi
}

# Function to create EFS file system
create_efs_filesystem() {
    log "Creating EFS file system..."
    
    export EFS_ID=$(execute_cmd "aws efs create-file-system \
        --creation-token \"${EFS_NAME}-token\" \
        --performance-mode generalPurpose \
        --throughput-mode elastic \
        --encrypted \
        --tags Key=Name,Value=$EFS_NAME \
        --query 'FileSystemId' --output text" \
        "Creating EFS file system")
    
    if [ "$DRY_RUN" = false ]; then
        # Wait for EFS to become available
        log "Waiting for EFS file system to become available..."
        aws efs wait file-system-available --file-system-id $EFS_ID
        success "EFS file system created: $EFS_ID"
    fi
}

# Function to create mount targets
create_mount_targets() {
    log "Creating mount targets in multiple AZs..."
    
    # Create mount target in first AZ
    export MT1_ID=$(execute_cmd "aws efs create-mount-target \
        --file-system-id $EFS_ID \
        --subnet-id $SUBNET_1 \
        --security-groups $EFS_SG_ID \
        --query 'MountTargetId' --output text" \
        "Creating mount target in first AZ")
    
    # Create mount target in second AZ
    export MT2_ID=$(execute_cmd "aws efs create-mount-target \
        --file-system-id $EFS_ID \
        --subnet-id $SUBNET_2 \
        --security-groups $EFS_SG_ID \
        --query 'MountTargetId' --output text" \
        "Creating mount target in second AZ")
    
    # Create mount target in third AZ (if different subnet)
    if [ "$SUBNET_3" != "$SUBNET_1" ]; then
        export MT3_ID=$(execute_cmd "aws efs create-mount-target \
            --file-system-id $EFS_ID \
            --subnet-id $SUBNET_3 \
            --security-groups $EFS_SG_ID \
            --query 'MountTargetId' --output text" \
            "Creating mount target in third AZ")
    fi
    
    if [ "$DRY_RUN" = false ]; then
        # Wait for mount targets to become available
        log "Waiting for mount targets to become available..."
        aws efs wait mount-target-available --mount-target-id $MT1_ID
        aws efs wait mount-target-available --mount-target-id $MT2_ID
        if [ -n "$MT3_ID" ]; then
            aws efs wait mount-target-available --mount-target-id $MT3_ID
        fi
        success "Mount targets created in all AZs"
    fi
}

# Function to create access points
create_access_points() {
    log "Creating EFS access points..."
    
    # Create access point for web application content
    export AP1_ID=$(execute_cmd "aws efs create-access-point \
        --file-system-id $EFS_ID \
        --posix-user Uid=1000,Gid=1000 \
        --root-directory Path=/web-content,CreationInfo='{OwnerUid=1000,OwnerGid=1000,Permissions=755}' \
        --tags Key=Name,Value=\"${EFS_NAME}-web-content\" \
        --query 'AccessPointId' --output text" \
        "Creating access point for web content")
    
    # Create access point for shared data
    export AP2_ID=$(execute_cmd "aws efs create-access-point \
        --file-system-id $EFS_ID \
        --posix-user Uid=1001,Gid=1001 \
        --root-directory Path=/shared-data,CreationInfo='{OwnerUid=1001,OwnerGid=1001,Permissions=750}' \
        --tags Key=Name,Value=\"${EFS_NAME}-shared-data\" \
        --query 'AccessPointId' --output text" \
        "Creating access point for shared data")
    
    if [ "$DRY_RUN" = false ]; then
        success "Access points created - Web: $AP1_ID, Data: $AP2_ID"
    fi
}

# Function to launch EC2 instances
launch_ec2_instances() {
    log "Launching EC2 instances..."
    
    # Get Amazon Linux 2 AMI ID
    export AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    if [ -z "$AMI_ID" ]; then
        error "Unable to find Amazon Linux 2 AMI"
        exit 1
    fi
    
    # Create user data script
    cat > /tmp/user-data.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y amazon-efs-utils
mkdir -p /mnt/efs
mkdir -p /mnt/web-content
mkdir -p /mnt/shared-data

# Install CloudWatch agent
yum install -y amazon-cloudwatch-agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CW_EOF'
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/messages",
                        "log_group_name": "/aws/ec2/efs-demo",
                        "log_stream_name": "{instance_id}/var/log/messages"
                    }
                ]
            }
        }
    }
}
CW_EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Install performance testing tools
yum install -y fio
EOF
    
    # Launch instance in first AZ
    export INSTANCE1_ID=$(execute_cmd "aws ec2 run-instances \
        --image-id $AMI_ID \
        --instance-type t3.micro \
        --key-name $KEY_PAIR_NAME \
        --security-group-ids $EC2_SG_ID \
        --subnet-id $SUBNET_1 \
        --user-data file:///tmp/user-data.sh \
        --tag-specifications \"ResourceType=instance,Tags=[{Key=Name,Value=${EFS_NAME}-instance-1}]\" \
        --query 'Instances[0].InstanceId' --output text" \
        "Launching instance in first AZ")
    
    # Launch instance in second AZ
    export INSTANCE2_ID=$(execute_cmd "aws ec2 run-instances \
        --image-id $AMI_ID \
        --instance-type t3.micro \
        --key-name $KEY_PAIR_NAME \
        --security-group-ids $EC2_SG_ID \
        --subnet-id $SUBNET_2 \
        --user-data file:///tmp/user-data.sh \
        --tag-specifications \"ResourceType=instance,Tags=[{Key=Name,Value=${EFS_NAME}-instance-2}]\" \
        --query 'Instances[0].InstanceId' --output text" \
        "Launching instance in second AZ")
    
    if [ "$DRY_RUN" = false ]; then
        # Wait for instances to be running
        log "Waiting for instances to be running..."
        aws ec2 wait instance-running --instance-ids $INSTANCE1_ID $INSTANCE2_ID
        
        # Get public IP addresses
        export IP1=$(aws ec2 describe-instances \
            --instance-ids $INSTANCE1_ID \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            --output text)
        
        export IP2=$(aws ec2 describe-instances \
            --instance-ids $INSTANCE2_ID \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            --output text)
        
        success "EC2 instances launched: $INSTANCE1_ID ($IP1), $INSTANCE2_ID ($IP2)"
        
        # Wait for instances to be ready for SSH
        log "Waiting for instances to be ready for SSH connection..."
        sleep 60
    fi
}

# Function to configure EFS mounting
configure_efs_mounting() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Would configure EFS mounting on instances"
        return 0
    fi
    
    log "Configuring EFS mounting on instances..."
    
    # Configure mounting on first instance
    ssh -i ~/.ssh/${KEY_PAIR_NAME}.pem \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=30 \
        ec2-user@$IP1 << EOF
    # Mount EFS file system
    sudo mount -t efs -o tls,iam ${EFS_ID}:/ /mnt/efs
    
    # Mount access points
    sudo mount -t efs -o tls,iam,accesspoint=${AP1_ID} ${EFS_ID}:/ /mnt/web-content
    sudo mount -t efs -o tls,iam,accesspoint=${AP2_ID} ${EFS_ID}:/ /mnt/shared-data
    
    # Add to fstab for persistent mounting
    echo "${EFS_ID}:/ /mnt/efs efs defaults,_netdev,tls,iam" | sudo tee -a /etc/fstab
    echo "${EFS_ID}:/ /mnt/web-content efs defaults,_netdev,tls,iam,accesspoint=${AP1_ID}" | sudo tee -a /etc/fstab
    echo "${EFS_ID}:/ /mnt/shared-data efs defaults,_netdev,tls,iam,accesspoint=${AP2_ID}" | sudo tee -a /etc/fstab
    
    # Create test files
    echo "Hello from instance 1" | sudo tee /mnt/efs/test1.txt
    echo "Web content from instance 1" | sudo tee /mnt/web-content/web1.txt
    echo "Shared data from instance 1" | sudo tee /mnt/shared-data/data1.txt
EOF
    
    # Configure mounting on second instance
    ssh -i ~/.ssh/${KEY_PAIR_NAME}.pem \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=30 \
        ec2-user@$IP2 << EOF
    # Mount EFS file system
    sudo mount -t efs -o tls,iam ${EFS_ID}:/ /mnt/efs
    
    # Mount access points
    sudo mount -t efs -o tls,iam,accesspoint=${AP1_ID} ${EFS_ID}:/ /mnt/web-content
    sudo mount -t efs -o tls,iam,accesspoint=${AP2_ID} ${EFS_ID}:/ /mnt/shared-data
    
    # Add to fstab for persistent mounting
    echo "${EFS_ID}:/ /mnt/efs efs defaults,_netdev,tls,iam" | sudo tee -a /etc/fstab
    echo "${EFS_ID}:/ /mnt/web-content efs defaults,_netdev,tls,iam,accesspoint=${AP1_ID}" | sudo tee -a /etc/fstab
    echo "${EFS_ID}:/ /mnt/shared-data efs defaults,_netdev,tls,iam,accesspoint=${AP2_ID}" | sudo tee -a /etc/fstab
    
    # Create test files
    echo "Hello from instance 2" | sudo tee /mnt/efs/test2.txt
    echo "Web content from instance 2" | sudo tee /mnt/web-content/web2.txt
    echo "Shared data from instance 2" | sudo tee /mnt/shared-data/data2.txt
EOF
    
    success "EFS mounting configured on both instances"
}

# Function to set up monitoring
setup_monitoring() {
    log "Setting up CloudWatch monitoring..."
    
    # Create CloudWatch log group
    execute_cmd "aws logs create-log-group \
        --log-group-name \"/aws/efs/${EFS_NAME}\" \
        --retention-in-days 7" \
        "Creating CloudWatch log group"
    
    # Create CloudWatch dashboard
    cat > /tmp/dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/EFS", "TotalIOBytes", "FileSystemId", "${EFS_ID}"],
                    [".", "DataReadIOBytes", ".", "."],
                    [".", "DataWriteIOBytes", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "EFS Data Transfer"
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/EFS", "ClientConnections", "FileSystemId", "${EFS_ID}"],
                    [".", "TotalIOTime", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "EFS Performance"
            }
        }
    ]
}
EOF
    
    execute_cmd "aws cloudwatch put-dashboard \
        --dashboard-name \"EFS-${EFS_NAME}\" \
        --dashboard-body file:///tmp/dashboard.json" \
        "Creating CloudWatch dashboard"
    
    if [ "$DRY_RUN" = false ]; then
        success "CloudWatch monitoring configured"
    fi
}

# Function to configure automated backups
configure_automated_backups() {
    log "Configuring automated backups..."
    
    # Create backup vault
    export BACKUP_VAULT_NAME="efs-backup-${RANDOM_SUFFIX}"
    
    execute_cmd "aws backup create-backup-vault \
        --backup-vault-name $BACKUP_VAULT_NAME \
        --backup-vault-kms-key-id alias/aws/backup" \
        "Creating backup vault"
    
    # Create backup plan
    cat > /tmp/backup-plan.json << EOF
{
    "BackupPlanName": "EFS-Daily-Backup-${RANDOM_SUFFIX}",
    "Rules": [
        {
            "RuleName": "Daily-Backup",
            "TargetBackupVaultName": "${BACKUP_VAULT_NAME}",
            "ScheduleExpression": "cron(0 2 ? * * *)",
            "StartWindowMinutes": 60,
            "Lifecycle": {
                "DeleteAfterDays": 30
            },
            "RecoveryPointTags": {
                "EFS": "${EFS_NAME}"
            }
        }
    ]
}
EOF
    
    export BACKUP_PLAN_ID=$(execute_cmd "aws backup create-backup-plan \
        --backup-plan file:///tmp/backup-plan.json \
        --query 'BackupPlanId' --output text" \
        "Creating backup plan")
    
    # Create backup selection
    cat > /tmp/backup-selection.json << EOF
{
    "SelectionName": "EFS-Selection-${RANDOM_SUFFIX}",
    "IamRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/service-role/AWSBackupDefaultServiceRole",
    "Resources": [
        "arn:aws:elasticfilesystem:${AWS_REGION}:${AWS_ACCOUNT_ID}:file-system/${EFS_ID}"
    ]
}
EOF
    
    execute_cmd "aws backup create-backup-selection \
        --backup-plan-id $BACKUP_PLAN_ID \
        --backup-selection file:///tmp/backup-selection.json" \
        "Creating backup selection"
    
    if [ "$DRY_RUN" = false ]; then
        success "Automated backups configured"
    fi
}

# Function to configure lifecycle policies
configure_lifecycle_policies() {
    log "Configuring lifecycle policies..."
    
    # Create lifecycle policy for cost optimization
    execute_cmd "aws efs create-lifecycle-policy \
        --file-system-id $EFS_ID \
        --lifecycle-policy TransitionToIA=AFTER_30_DAYS,TransitionToPrimaryStorageClass=AFTER_1_ACCESS" \
        "Creating lifecycle policy"
    
    # Create file system policy
    cat > /tmp/file-system-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
            },
            "Action": [
                "elasticfilesystem:ClientMount",
                "elasticfilesystem:ClientWrite",
                "elasticfilesystem:ClientRootAccess"
            ],
            "Resource": "arn:aws:elasticfilesystem:${AWS_REGION}:${AWS_ACCOUNT_ID}:file-system/${EFS_ID}",
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "true"
                }
            }
        }
    ]
}
EOF
    
    execute_cmd "aws efs create-file-system-policy \
        --file-system-id $EFS_ID \
        --policy file:///tmp/file-system-policy.json" \
        "Creating file system policy"
    
    if [ "$DRY_RUN" = false ]; then
        success "Lifecycle policies configured"
    fi
}

# Function to validate deployment
validate_deployment() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Would validate deployment"
        return 0
    fi
    
    log "Validating deployment..."
    
    # Check EFS file system status
    EFS_STATUS=$(aws efs describe-file-systems \
        --file-system-id $EFS_ID \
        --query 'FileSystems[0].LifeCycleState' --output text)
    
    if [ "$EFS_STATUS" = "available" ]; then
        success "EFS file system is available"
    else
        error "EFS file system is not available: $EFS_STATUS"
        exit 1
    fi
    
    # Test file sharing between instances
    log "Testing file sharing between instances..."
    
    FILES1=$(ssh -i ~/.ssh/${KEY_PAIR_NAME}.pem \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=30 \
        ec2-user@$IP1 "ls -la /mnt/efs/" 2>/dev/null || echo "ERROR")
    
    FILES2=$(ssh -i ~/.ssh/${KEY_PAIR_NAME}.pem \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=30 \
        ec2-user@$IP2 "ls -la /mnt/efs/" 2>/dev/null || echo "ERROR")
    
    if [ "$FILES1" != "ERROR" ] && [ "$FILES2" != "ERROR" ]; then
        success "File sharing is working between instances"
    else
        warning "Unable to verify file sharing (instances may still be initializing)"
    fi
    
    success "Deployment validation completed"
}

# Function to save deployment info
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > /tmp/efs-deployment-info.txt << EOF
EFS Deployment Information
==========================
Deployment Date: $(date)
AWS Region: $AWS_REGION
AWS Account ID: $AWS_ACCOUNT_ID

Resources Created:
- EFS File System ID: $EFS_ID
- EFS Name: $EFS_NAME
- Key Pair: $KEY_PAIR_NAME
- EFS Security Group: $EFS_SG_ID
- EC2 Security Group: $EC2_SG_ID
- Access Point 1 (Web Content): $AP1_ID
- Access Point 2 (Shared Data): $AP2_ID
- Mount Target 1: $MT1_ID
- Mount Target 2: $MT2_ID
- Mount Target 3: $MT3_ID
- EC2 Instance 1: $INSTANCE1_ID ($IP1)
- EC2 Instance 2: $INSTANCE2_ID ($IP2)
- Backup Vault: $BACKUP_VAULT_NAME
- Backup Plan: $BACKUP_PLAN_ID

Connection Information:
- SSH to Instance 1: ssh -i ~/.ssh/${KEY_PAIR_NAME}.pem ec2-user@$IP1
- SSH to Instance 2: ssh -i ~/.ssh/${KEY_PAIR_NAME}.pem ec2-user@$IP2

CloudWatch Dashboard:
- Dashboard Name: EFS-${EFS_NAME}

Cleanup Command:
- Run: ./destroy.sh

EOF
    
    cp /tmp/efs-deployment-info.txt ./efs-deployment-info.txt
    success "Deployment information saved to efs-deployment-info.txt"
}

# Function to display cost estimate
display_cost_estimate() {
    log "Estimated monthly costs (may vary by region and usage):"
    echo "  - EFS Storage (1 GB): ~\$0.30/month"
    echo "  - EFS Request charges: ~\$0.01-0.10/month"
    echo "  - EC2 t3.micro instances (2x): ~\$16/month"
    echo "  - EBS storage (default): ~\$2/month"
    echo "  - Data transfer: Variable"
    echo "  - Total estimated: ~\$18-20/month"
    echo ""
    warning "Remember to run ./destroy.sh to clean up resources and avoid ongoing charges"
}

# Main execution
main() {
    log "Starting EFS deployment..."
    
    check_prerequisites
    setup_environment
    create_key_pair
    create_security_groups
    create_efs_filesystem
    create_mount_targets
    create_access_points
    launch_ec2_instances
    configure_efs_mounting
    setup_monitoring
    configure_automated_backups
    configure_lifecycle_policies
    validate_deployment
    save_deployment_info
    display_cost_estimate
    
    success "EFS deployment completed successfully!"
    log "Check efs-deployment-info.txt for connection details and resource information"
}

# Run main function
main "$@"