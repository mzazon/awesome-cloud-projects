#!/bin/bash

# =============================================================================
# AWS Hybrid Identity Management with Directory Service - Deployment Script
# =============================================================================
# This script deploys a complete hybrid identity management solution using:
# - AWS Managed Microsoft AD
# - Amazon WorkSpaces integration
# - RDS SQL Server with Windows Authentication
# - IAM roles and security groups
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION AND LOGGING
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging configuration
LOG_FILE="deployment-$(date +%Y%m%d-%H%M%S).log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
    log "INFO" "${message}"
}

print_error() {
    local message=$1
    echo -e "${RED}❌ ERROR: ${message}${NC}" >&2
    log "ERROR" "${message}"
}

print_warning() {
    local message=$1
    echo -e "${YELLOW}⚠️  WARNING: ${message}${NC}"
    log "WARN" "${message}"
}

print_info() {
    local message=$1
    echo -e "${BLUE}ℹ️  ${message}${NC}"
    log "INFO" "${message}"
}

print_success() {
    local message=$1
    echo -e "${GREEN}✅ ${message}${NC}"
    log "SUCCESS" "${message}"
}

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI version 2.0 or later."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    print_info "AWS CLI version: ${aws_version}"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        print_warning "jq is not installed. Some operations may be slower."
    fi
    
    # Display current AWS configuration
    local aws_account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "Unknown")
    local aws_region=$(aws configure get region 2>/dev/null || echo "Not set")
    local aws_user=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo "Unknown")
    
    print_info "AWS Account: ${aws_account}"
    print_info "AWS Region: ${aws_region}"
    print_info "AWS User/Role: ${aws_user}"
    
    # Validate region is set
    if [[ "${aws_region}" == "Not set" ]]; then
        print_error "AWS region is not configured. Please set a default region."
        exit 1
    fi
    
    print_success "Prerequisites check completed"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function to wait for resource to be in desired state
wait_for_resource() {
    local resource_type=$1
    local resource_id=$2
    local desired_state=$3
    local max_attempts=${4:-30}
    local sleep_interval=${5:-30}
    
    print_info "Waiting for ${resource_type} ${resource_id} to reach state: ${desired_state}"
    
    local attempts=0
    while [ ${attempts} -lt ${max_attempts} ]; do
        local current_state
        
        case ${resource_type} in
            "directory")
                current_state=$(aws ds describe-directories \
                    --directory-ids ${resource_id} \
                    --query 'DirectoryDescriptions[0].Stage' \
                    --output text 2>/dev/null || echo "Unknown")
                ;;
            "rds-instance")
                current_state=$(aws rds describe-db-instances \
                    --db-instance-identifier ${resource_id} \
                    --query 'DBInstances[0].DBInstanceStatus' \
                    --output text 2>/dev/null || echo "Unknown")
                ;;
            "ec2-instance")
                current_state=$(aws ec2 describe-instances \
                    --instance-ids ${resource_id} \
                    --query 'Reservations[0].Instances[0].State.Name' \
                    --output text 2>/dev/null || echo "Unknown")
                ;;
        esac
        
        if [[ "${current_state}" == "${desired_state}" ]]; then
            print_success "${resource_type} ${resource_id} is now ${desired_state}"
            return 0
        fi
        
        print_info "Current state: ${current_state}, waiting..."
        sleep ${sleep_interval}
        ((attempts++))
    done
    
    print_error "Timeout waiting for ${resource_type} ${resource_id} to reach ${desired_state}"
    return 1
}

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_identifier=$2
    
    case ${resource_type} in
        "vpc")
            aws ec2 describe-vpcs --vpc-ids ${resource_identifier} &>/dev/null
            ;;
        "directory")
            aws ds describe-directories --directory-ids ${resource_identifier} &>/dev/null
            ;;
        "rds-instance")
            aws rds describe-db-instances --db-instance-identifier ${resource_identifier} &>/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name ${resource_identifier} &>/dev/null
            ;;
        "security-group")
            aws ec2 describe-security-groups --group-ids ${resource_identifier} &>/dev/null
            ;;
    esac
}

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================

setup_environment() {
    print_info "Setting up environment variables..."
    
    # Set core environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 6))
    
    # Set resource names with unique suffix
    export DIRECTORY_NAME="corp-hybrid-ad-${random_suffix}"
    export VPC_NAME="hybrid-identity-vpc-${random_suffix}"
    export WORKSPACE_BUNDLE_ID="wsb-bh8rsxt14"  # Standard Windows 10 bundle
    export RDS_INSTANCE_ID="hybrid-sql-${random_suffix}"
    export IAM_ROLE_NAME="rds-directoryservice-role-${random_suffix}"
    export WORKSPACES_SG_NAME="workspaces-sg-${random_suffix}"
    export ADMIN_INSTANCE_NAME="domain-admin-instance-${random_suffix}"
    
    # Directory configuration
    export DIRECTORY_PASSWORD="TempPassword123!"
    export DIRECTORY_DOMAIN="${DIRECTORY_NAME}.corp.local"
    
    # Save environment to file for cleanup script
    cat > "${SCRIPT_DIR}/deployment.env" << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export DIRECTORY_NAME="${DIRECTORY_NAME}"
export VPC_NAME="${VPC_NAME}"
export WORKSPACE_BUNDLE_ID="${WORKSPACE_BUNDLE_ID}"
export RDS_INSTANCE_ID="${RDS_INSTANCE_ID}"
export IAM_ROLE_NAME="${IAM_ROLE_NAME}"
export WORKSPACES_SG_NAME="${WORKSPACES_SG_NAME}"
export ADMIN_INSTANCE_NAME="${ADMIN_INSTANCE_NAME}"
export DIRECTORY_PASSWORD="${DIRECTORY_PASSWORD}"
export DIRECTORY_DOMAIN="${DIRECTORY_DOMAIN}"
EOF
    
    print_success "Environment variables configured"
    print_info "Directory Name: ${DIRECTORY_NAME}"
    print_info "VPC Name: ${VPC_NAME}"
    print_info "RDS Instance ID: ${RDS_INSTANCE_ID}"
}

# =============================================================================
# VPC AND NETWORKING SETUP
# =============================================================================

create_vpc_infrastructure() {
    print_info "Creating VPC and networking infrastructure..."
    
    # Check if VPC already exists
    if aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${VPC_NAME}" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null | grep -q "vpc-"; then
        export VPC_ID=$(aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=${VPC_NAME}" \
            --query 'Vpcs[0].VpcId' --output text)
        print_info "VPC already exists: ${VPC_ID}"
    else
        # Create VPC
        print_info "Creating VPC with CIDR 10.0.0.0/16..."
        aws ec2 create-vpc \
            --cidr-block 10.0.0.0/16 \
            --tag-specifications \
            "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}},{Key=Purpose,Value=HybridIdentity}]"
        
        export VPC_ID=$(aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=${VPC_NAME}" \
            --query 'Vpcs[0].VpcId' --output text)
        
        # Enable DNS hostnames and resolution
        aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-hostnames
        aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-support
        
        print_success "VPC created: ${VPC_ID}"
    fi
    
    # Create subnets in different AZs (required for Directory Service)
    local az1="${AWS_REGION}a"
    local az2="${AWS_REGION}b"
    
    # Create first subnet
    if aws ec2 describe-subnets --filters "Name=tag:Name,Values=directory-subnet-1" \
        --query 'Subnets[0].SubnetId' --output text 2>/dev/null | grep -q "subnet-"; then
        export SUBNET_ID_1=$(aws ec2 describe-subnets \
            --filters "Name=tag:Name,Values=directory-subnet-1" \
            --query 'Subnets[0].SubnetId' --output text)
        print_info "Subnet 1 already exists: ${SUBNET_ID_1}"
    else
        print_info "Creating subnet 1 in AZ ${az1}..."
        aws ec2 create-subnet \
            --vpc-id ${VPC_ID} \
            --cidr-block 10.0.1.0/24 \
            --availability-zone ${az1} \
            --tag-specifications \
            "ResourceType=subnet,Tags=[{Key=Name,Value=directory-subnet-1},{Key=Purpose,Value=HybridIdentity}]"
        
        export SUBNET_ID_1=$(aws ec2 describe-subnets \
            --filters "Name=tag:Name,Values=directory-subnet-1" \
            --query 'Subnets[0].SubnetId' --output text)
        print_success "Subnet 1 created: ${SUBNET_ID_1}"
    fi
    
    # Create second subnet
    if aws ec2 describe-subnets --filters "Name=tag:Name,Values=directory-subnet-2" \
        --query 'Subnets[0].SubnetId' --output text 2>/dev/null | grep -q "subnet-"; then
        export SUBNET_ID_2=$(aws ec2 describe-subnets \
            --filters "Name=tag:Name,Values=directory-subnet-2" \
            --query 'Subnets[0].SubnetId' --output text)
        print_info "Subnet 2 already exists: ${SUBNET_ID_2}"
    else
        print_info "Creating subnet 2 in AZ ${az2}..."
        aws ec2 create-subnet \
            --vpc-id ${VPC_ID} \
            --cidr-block 10.0.2.0/24 \
            --availability-zone ${az2} \
            --tag-specifications \
            "ResourceType=subnet,Tags=[{Key=Name,Value=directory-subnet-2},{Key=Purpose,Value=HybridIdentity}]"
        
        export SUBNET_ID_2=$(aws ec2 describe-subnets \
            --filters "Name=tag:Name,Values=directory-subnet-2" \
            --query 'Subnets[0].SubnetId' --output text)
        print_success "Subnet 2 created: ${SUBNET_ID_2}"
    fi
    
    # Create Internet Gateway for WorkSpaces access
    if aws ec2 describe-internet-gateways \
        --filters "Name=tag:Name,Values=${VPC_NAME}-igw" \
        --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null | grep -q "igw-"; then
        export IGW_ID=$(aws ec2 describe-internet-gateways \
            --filters "Name=tag:Name,Values=${VPC_NAME}-igw" \
            --query 'InternetGateways[0].InternetGatewayId' --output text)
        print_info "Internet Gateway already exists: ${IGW_ID}"
    else
        print_info "Creating Internet Gateway..."
        aws ec2 create-internet-gateway \
            --tag-specifications \
            "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw}]"
        
        export IGW_ID=$(aws ec2 describe-internet-gateways \
            --filters "Name=tag:Name,Values=${VPC_NAME}-igw" \
            --query 'InternetGateways[0].InternetGatewayId' --output text)
        
        # Attach to VPC
        aws ec2 attach-internet-gateway \
            --internet-gateway-id ${IGW_ID} \
            --vpc-id ${VPC_ID}
        
        print_success "Internet Gateway created and attached: ${IGW_ID}"
    fi
    
    # Update route tables for internet access
    local route_table_id=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'RouteTables[0].RouteTableId' --output text)
    
    if ! aws ec2 describe-route-tables \
        --route-table-ids ${route_table_id} \
        --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`]' \
        --output text | grep -q "${IGW_ID}"; then
        
        print_info "Adding default route to Internet Gateway..."
        aws ec2 create-route \
            --route-table-id ${route_table_id} \
            --destination-cidr-block 0.0.0.0/0 \
            --gateway-id ${IGW_ID} || true
    fi
    
    # Save network configuration
    echo "export VPC_ID=\"${VPC_ID}\"" >> "${SCRIPT_DIR}/deployment.env"
    echo "export SUBNET_ID_1=\"${SUBNET_ID_1}\"" >> "${SCRIPT_DIR}/deployment.env"
    echo "export SUBNET_ID_2=\"${SUBNET_ID_2}\"" >> "${SCRIPT_DIR}/deployment.env"
    echo "export IGW_ID=\"${IGW_ID}\"" >> "${SCRIPT_DIR}/deployment.env"
    
    print_success "VPC infrastructure created successfully"
}

# =============================================================================
# DIRECTORY SERVICE SETUP
# =============================================================================

create_directory_service() {
    print_info "Creating AWS Managed Microsoft AD..."
    
    # Check if directory already exists
    if aws ds describe-directories \
        --query "DirectoryDescriptions[?Name=='${DIRECTORY_DOMAIN}'].DirectoryId" \
        --output text 2>/dev/null | grep -q "d-"; then
        
        export DIRECTORY_ID=$(aws ds describe-directories \
            --query "DirectoryDescriptions[?Name=='${DIRECTORY_DOMAIN}'].DirectoryId" \
            --output text)
        print_info "Directory already exists: ${DIRECTORY_ID}"
        
        # Wait for it to be active if not already
        local current_state=$(aws ds describe-directories \
            --directory-ids ${DIRECTORY_ID} \
            --query 'DirectoryDescriptions[0].Stage' \
            --output text)
        
        if [[ "${current_state}" != "Active" ]]; then
            wait_for_resource "directory" "${DIRECTORY_ID}" "Active" 20 60
        fi
    else
        # Create AWS Managed Microsoft AD
        print_info "Creating directory: ${DIRECTORY_DOMAIN}"
        aws ds create-microsoft-ad \
            --name ${DIRECTORY_DOMAIN} \
            --password "${DIRECTORY_PASSWORD}" \
            --description "Hybrid Identity Management Directory" \
            --vpc-settings "VpcId=${VPC_ID},SubnetIds=${SUBNET_ID_1},${SUBNET_ID_2}" \
            --edition Standard \
            --tags "Key=Purpose,Value=HybridIdentity"
        
        # Get directory ID
        export DIRECTORY_ID=$(aws ds describe-directories \
            --query "DirectoryDescriptions[?Name=='${DIRECTORY_DOMAIN}'].DirectoryId" \
            --output text)
        
        print_info "Directory created with ID: ${DIRECTORY_ID}"
        
        # Wait for directory to become active
        wait_for_resource "directory" "${DIRECTORY_ID}" "Active" 20 60
    fi
    
    # Get directory security group
    export DIRECTORY_SG_ID=$(aws ds describe-directories \
        --directory-ids ${DIRECTORY_ID} \
        --query 'DirectoryDescriptions[0].VpcSettings.SecurityGroupId' \
        --output text)
    
    print_info "Directory security group: ${DIRECTORY_SG_ID}"
    
    # Enable LDAPS and client authentication
    print_info "Enabling directory features..."
    
    # Check if LDAPS is already enabled
    local ldaps_status=$(aws ds describe-ldaps-settings \
        --directory-id ${DIRECTORY_ID} \
        --query 'LDAPSSettingsInfo[0].LDAPSStatus' \
        --output text 2>/dev/null || echo "Disabled")
    
    if [[ "${ldaps_status}" != "Enabled" ]]; then
        aws ds enable-ldaps \
            --directory-id ${DIRECTORY_ID} \
            --type Client || print_warning "LDAPS enablement may take time to complete"
    fi
    
    # Enable client authentication (smart card support)
    aws ds enable-client-authentication \
        --directory-id ${DIRECTORY_ID} \
        --type SmartCard || print_warning "Client authentication may already be enabled"
    
    # Save directory configuration
    echo "export DIRECTORY_ID=\"${DIRECTORY_ID}\"" >> "${SCRIPT_DIR}/deployment.env"
    echo "export DIRECTORY_SG_ID=\"${DIRECTORY_SG_ID}\"" >> "${SCRIPT_DIR}/deployment.env"
    
    print_success "AWS Managed Microsoft AD setup completed"
}

# =============================================================================
# SECURITY GROUPS SETUP
# =============================================================================

create_security_groups() {
    print_info "Creating security groups..."
    
    # Create security group for WorkSpaces
    if aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${WORKSPACES_SG_NAME}" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null | grep -q "sg-"; then
        
        export WORKSPACES_SG_ID=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=${WORKSPACES_SG_NAME}" \
            --query 'SecurityGroups[0].GroupId' --output text)
        print_info "WorkSpaces security group already exists: ${WORKSPACES_SG_ID}"
    else
        print_info "Creating WorkSpaces security group..."
        aws ec2 create-security-group \
            --group-name ${WORKSPACES_SG_NAME} \
            --description "Security group for WorkSpaces and RDS access" \
            --vpc-id ${VPC_ID} \
            --tag-specifications \
            "ResourceType=security-group,Tags=[{Key=Name,Value=${WORKSPACES_SG_NAME}},{Key=Purpose,Value=HybridIdentity}]"
        
        export WORKSPACES_SG_ID=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=${WORKSPACES_SG_NAME}" \
            --query 'SecurityGroups[0].GroupId' --output text)
        
        print_success "WorkSpaces security group created: ${WORKSPACES_SG_ID}"
    fi
    
    # Configure security group rules for directory communication
    print_info "Configuring security group rules..."
    
    # Allow SMB/CIFS from WorkSpaces to Directory
    aws ec2 authorize-security-group-ingress \
        --group-id ${DIRECTORY_SG_ID} \
        --protocol tcp \
        --port 445 \
        --source-group ${WORKSPACES_SG_ID} 2>/dev/null || \
        print_info "SMB rule already exists"
    
    # Allow RDP access to admin instance
    aws ec2 authorize-security-group-ingress \
        --group-id ${WORKSPACES_SG_ID} \
        --protocol tcp \
        --port 3389 \
        --cidr 0.0.0.0/0 2>/dev/null || \
        print_info "RDP rule already exists"
    
    # Allow HTTPS for management
    aws ec2 authorize-security-group-ingress \
        --group-id ${WORKSPACES_SG_ID} \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 2>/dev/null || \
        print_info "HTTPS rule already exists"
    
    # Allow SQL Server access (1433)
    aws ec2 authorize-security-group-ingress \
        --group-id ${WORKSPACES_SG_ID} \
        --protocol tcp \
        --port 1433 \
        --source-group ${WORKSPACES_SG_ID} 2>/dev/null || \
        print_info "SQL Server rule already exists"
    
    # Save security group configuration
    echo "export WORKSPACES_SG_ID=\"${WORKSPACES_SG_ID}\"" >> "${SCRIPT_DIR}/deployment.env"
    
    print_success "Security groups configured successfully"
}

# =============================================================================
# IAM ROLE SETUP
# =============================================================================

create_iam_role() {
    print_info "Creating IAM role for RDS Directory Service integration..."
    
    # Check if role already exists
    if resource_exists "iam-role" "${IAM_ROLE_NAME}"; then
        print_info "IAM role already exists: ${IAM_ROLE_NAME}"
    else
        print_info "Creating IAM role: ${IAM_ROLE_NAME}"
        
        # Create trust policy
        local trust_policy='{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "rds.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }'
        
        # Create IAM role
        aws iam create-role \
            --role-name ${IAM_ROLE_NAME} \
            --assume-role-policy-document "${trust_policy}" \
            --description "IAM role for RDS Directory Service integration"
        
        print_success "IAM role created: ${IAM_ROLE_NAME}"
    fi
    
    # Attach AWS managed policy
    print_info "Attaching Directory Service access policy..."
    aws iam attach-role-policy \
        --role-name ${IAM_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonRDSDirectoryServiceAccess
    
    print_success "IAM role configuration completed"
}

# =============================================================================
# WORKSPACES SETUP
# =============================================================================

setup_workspaces() {
    print_info "Setting up Amazon WorkSpaces..."
    
    # Check if directory is already registered with WorkSpaces
    local registration_status=$(aws workspaces describe-workspace-directories \
        --directory-ids ${DIRECTORY_ID} \
        --query 'Directories[0].State' \
        --output text 2>/dev/null || echo "NOT_REGISTERED")
    
    if [[ "${registration_status}" == "REGISTERED" ]]; then
        print_info "Directory already registered with WorkSpaces"
    else
        print_info "Registering directory with WorkSpaces..."
        
        # Register directory with WorkSpaces
        aws workspaces register-workspace-directory \
            --directory-id ${DIRECTORY_ID} \
            --subnet-ids ${SUBNET_ID_1} ${SUBNET_ID_2} \
            --enable-work-docs \
            --enable-self-service
        
        print_info "Waiting for directory registration to complete..."
        sleep 60
        
        # Verify registration
        local max_attempts=10
        local attempts=0
        while [ ${attempts} -lt ${max_attempts} ]; do
            registration_status=$(aws workspaces describe-workspace-directories \
                --directory-ids ${DIRECTORY_ID} \
                --query 'Directories[0].State' \
                --output text 2>/dev/null || echo "UNKNOWN")
            
            if [[ "${registration_status}" == "REGISTERED" ]]; then
                break
            fi
            
            print_info "Registration status: ${registration_status}, waiting..."
            sleep 30
            ((attempts++))
        done
        
        if [[ "${registration_status}" == "REGISTERED" ]]; then
            print_success "Directory successfully registered with WorkSpaces"
        else
            print_warning "Directory registration may still be in progress"
        fi
    fi
    
    print_info "WorkSpaces setup completed"
}

# =============================================================================
# RDS SETUP
# =============================================================================

create_rds_instance() {
    print_info "Creating RDS SQL Server instance with Directory Service integration..."
    
    # Check if RDS instance already exists
    if resource_exists "rds-instance" "${RDS_INSTANCE_ID}"; then
        print_info "RDS instance already exists: ${RDS_INSTANCE_ID}"
        
        # Wait for it to be available if not already
        local current_status=$(aws rds describe-db-instances \
            --db-instance-identifier ${RDS_INSTANCE_ID} \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text)
        
        if [[ "${current_status}" != "available" ]]; then
            wait_for_resource "rds-instance" "${RDS_INSTANCE_ID}" "available" 30 60
        fi
    else
        # Create DB subnet group first
        print_info "Creating DB subnet group..."
        
        local subnet_group_name="hybrid-db-subnet-group-${RANDOM_SUFFIX:-$(date +%s)}"
        
        aws rds create-db-subnet-group \
            --db-subnet-group-name ${subnet_group_name} \
            --db-subnet-group-description "Subnet group for hybrid RDS instance" \
            --subnet-ids ${SUBNET_ID_1} ${SUBNET_ID_2} \
            --tags "Key=Purpose,Value=HybridIdentity" 2>/dev/null || \
            print_info "DB subnet group may already exist"
        
        # Create RDS SQL Server instance
        print_info "Creating RDS SQL Server instance: ${RDS_INSTANCE_ID}"
        
        aws rds create-db-instance \
            --db-instance-identifier ${RDS_INSTANCE_ID} \
            --db-instance-class db.t3.medium \
            --engine sqlserver-se \
            --engine-version "15.00.4236.7.v1" \
            --master-username admin \
            --master-user-password "${DIRECTORY_PASSWORD}" \
            --allocated-storage 200 \
            --storage-type gp2 \
            --vpc-security-group-ids ${WORKSPACES_SG_ID} \
            --db-subnet-group-name ${subnet_group_name} \
            --domain ${DIRECTORY_ID} \
            --domain-iam-role-name ${IAM_ROLE_NAME} \
            --license-model license-included \
            --storage-encrypted \
            --tags "Key=Purpose,Value=HybridIdentity"
        
        print_info "RDS instance creation initiated. This may take 15-20 minutes..."
        
        # Wait for RDS instance to be available
        wait_for_resource "rds-instance" "${RDS_INSTANCE_ID}" "available" 40 60
    fi
    
    # Get RDS endpoint
    export RDS_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier ${RDS_INSTANCE_ID} \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    # Save RDS configuration
    echo "export RDS_ENDPOINT=\"${RDS_ENDPOINT}\"" >> "${SCRIPT_DIR}/deployment.env"
    
    print_success "RDS SQL Server instance is ready: ${RDS_ENDPOINT}"
}

# =============================================================================
# DOMAIN ADMIN INSTANCE SETUP
# =============================================================================

create_admin_instance() {
    print_info "Creating domain admin instance..."
    
    # Get the latest Windows Server 2019 AMI
    local ami_id=$(aws ec2 describe-images \
        --owners amazon \
        --filters \
            "Name=name,Values=Windows_Server-2019-English-Full-Base-*" \
            "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    print_info "Using AMI: ${ami_id}"
    
    # Check if instance already exists
    if aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=${ADMIN_INSTANCE_NAME}" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null | grep -q "i-"; then
        
        export ADMIN_INSTANCE_ID=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=${ADMIN_INSTANCE_NAME}" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
            --query 'Reservations[0].Instances[0].InstanceId' --output text)
        print_info "Admin instance already exists: ${ADMIN_INSTANCE_ID}"
        
        # Start if stopped
        local instance_state=$(aws ec2 describe-instances \
            --instance-ids ${ADMIN_INSTANCE_ID} \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text)
        
        if [[ "${instance_state}" == "stopped" ]]; then
            print_info "Starting stopped admin instance..."
            aws ec2 start-instances --instance-ids ${ADMIN_INSTANCE_ID}
            wait_for_resource "ec2-instance" "${ADMIN_INSTANCE_ID}" "running"
        fi
    else
        print_info "Launching new admin instance..."
        
        # Create user data script for domain join
        local user_data=$(base64 -w 0 << 'EOF'
<powershell>
# Enable PS Remoting
Enable-PSRemoting -Force
Set-NetFirewallRule -Name "WINRM-HTTP-In-TCP-PUBLIC" -RemoteAddress Any

# Install AD management tools
Install-WindowsFeature -Name RSAT-AD-Tools,RSAT-DNS-Server

# Configure PowerShell execution policy
Set-ExecutionPolicy RemoteSigned -Force

# Log completion
Add-Content -Path "C:\deployment.log" -Value "$(Get-Date): Domain admin instance configured"
</powershell>
EOF
)
        
        # Launch EC2 instance
        aws ec2 run-instances \
            --image-id ${ami_id} \
            --instance-type t3.medium \
            --subnet-id ${SUBNET_ID_1} \
            --security-group-ids ${WORKSPACES_SG_ID} \
            --user-data "${user_data}" \
            --tag-specifications \
            "ResourceType=instance,Tags=[{Key=Name,Value=${ADMIN_INSTANCE_NAME}},{Key=Purpose,Value=HybridIdentity}]" \
            --instance-initiated-shutdown-behavior stop
        
        export ADMIN_INSTANCE_ID=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=${ADMIN_INSTANCE_NAME}" \
            --query 'Reservations[0].Instances[0].InstanceId' \
            --output text)
        
        print_info "Admin instance launched: ${ADMIN_INSTANCE_ID}"
        
        # Wait for instance to be running
        wait_for_resource "ec2-instance" "${ADMIN_INSTANCE_ID}" "running"
    fi
    
    # Get instance public IP for RDP access
    export ADMIN_INSTANCE_IP=$(aws ec2 describe-instances \
        --instance-ids ${ADMIN_INSTANCE_ID} \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    # Save admin instance configuration
    echo "export ADMIN_INSTANCE_ID=\"${ADMIN_INSTANCE_ID}\"" >> "${SCRIPT_DIR}/deployment.env"
    echo "export ADMIN_INSTANCE_IP=\"${ADMIN_INSTANCE_IP}\"" >> "${SCRIPT_DIR}/deployment.env"
    
    print_success "Domain admin instance ready: ${ADMIN_INSTANCE_ID} (${ADMIN_INSTANCE_IP})"
}

# =============================================================================
# VALIDATION
# =============================================================================

validate_deployment() {
    print_info "Validating deployment..."
    
    # Validate Directory Service
    print_info "Validating Directory Service..."
    local dir_status=$(aws ds describe-directories \
        --directory-ids ${DIRECTORY_ID} \
        --query 'DirectoryDescriptions[0].Stage' \
        --output text)
    
    if [[ "${dir_status}" == "Active" ]]; then
        print_success "Directory Service is active"
    else
        print_error "Directory Service is not active: ${dir_status}"
        return 1
    fi
    
    # Validate WorkSpaces registration
    print_info "Validating WorkSpaces registration..."
    local ws_status=$(aws workspaces describe-workspace-directories \
        --directory-ids ${DIRECTORY_ID} \
        --query 'Directories[0].State' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "${ws_status}" == "REGISTERED" ]]; then
        print_success "WorkSpaces directory is registered"
    else
        print_warning "WorkSpaces registration status: ${ws_status}"
    fi
    
    # Validate RDS instance
    print_info "Validating RDS instance..."
    local rds_status=$(aws rds describe-db-instances \
        --db-instance-identifier ${RDS_INSTANCE_ID} \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "${rds_status}" == "available" ]]; then
        print_success "RDS instance is available"
    else
        print_warning "RDS instance status: ${rds_status}"
    fi
    
    # Validate admin instance
    print_info "Validating admin instance..."
    local instance_status=$(aws ec2 describe-instances \
        --instance-ids ${ADMIN_INSTANCE_ID} \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "${instance_status}" == "running" ]]; then
        print_success "Admin instance is running"
    else
        print_warning "Admin instance status: ${instance_status}"
    fi
    
    print_success "Deployment validation completed"
}

# =============================================================================
# MAIN DEPLOYMENT FUNCTION
# =============================================================================

deploy_hybrid_identity() {
    print_info "Starting AWS Hybrid Identity Management deployment..."
    print_info "Log file: ${LOG_FILE}"
    
    # Record start time
    local start_time=$(date)
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_vpc_infrastructure
    create_directory_service
    create_security_groups
    create_iam_role
    setup_workspaces
    create_rds_instance
    create_admin_instance
    validate_deployment
    
    # Record end time and duration
    local end_time=$(date)
    
    print_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    print_info "Started: ${start_time}"
    print_info "Completed: ${end_time}"
    print_info ""
    print_info "=== RESOURCE SUMMARY ==="
    print_info "Directory ID: ${DIRECTORY_ID}"
    print_info "Directory Domain: ${DIRECTORY_DOMAIN}"
    print_info "VPC ID: ${VPC_ID}"
    print_info "RDS Instance: ${RDS_INSTANCE_ID} (${RDS_ENDPOINT})"
    print_info "Admin Instance: ${ADMIN_INSTANCE_ID} (${ADMIN_INSTANCE_IP})"
    print_info ""
    print_info "=== NEXT STEPS ==="
    print_info "1. RDP to admin instance: ${ADMIN_INSTANCE_IP}"
    print_info "2. Join admin instance to domain: ${DIRECTORY_DOMAIN}"
    print_info "3. Create test users in Active Directory"
    print_info "4. Create WorkSpaces for users"
    print_info "5. Test SQL Server Windows Authentication"
    print_info ""
    print_info "Environment saved to: ${SCRIPT_DIR}/deployment.env"
    print_info "Use destroy.sh to clean up resources when done"
}

# =============================================================================
# ERROR HANDLING
# =============================================================================

# Trap errors and cleanup
trap 'print_error "Deployment failed on line $LINENO. Check ${LOG_FILE} for details."' ERR

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Check if running with bash
if [ "${BASH_VERSION}" = "" ]; then
    print_error "This script requires bash to run"
    exit 1
fi

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_hybrid_identity "$@"
fi