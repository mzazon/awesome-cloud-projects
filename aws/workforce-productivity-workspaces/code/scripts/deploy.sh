#!/bin/bash

# =============================================================================
# AWS WorkSpaces Deployment Script
# =============================================================================
# This script deploys a complete AWS WorkSpaces environment including:
# - VPC with public and private subnets
# - Internet Gateway and NAT Gateway
# - Simple AD directory service
# - WorkSpaces virtual desktop environment
# - CloudWatch monitoring and security controls
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log_info "Checking AWS CLI authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or authentication failed"
        log_error "Please run 'aws configure' or set appropriate environment variables"
        exit 1
    fi
    log_success "AWS CLI authentication verified"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version (require v2)
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ "${AWS_CLI_VERSION}" < "2.0.0" ]]; then
        log_warning "AWS CLI v2 is recommended. Current version: ${AWS_CLI_VERSION}"
    fi
    
    # Check if jq is available (optional but helpful)
    if ! command_exists jq; then
        log_warning "jq is not installed. JSON output will be less readable."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to check if WorkSpaces is available in the region
check_workspaces_availability() {
    log_info "Checking WorkSpaces availability in region ${AWS_REGION}..."
    
    if ! aws workspaces describe-workspace-directories --region "$AWS_REGION" >/dev/null 2>&1; then
        log_error "WorkSpaces is not available in region ${AWS_REGION}"
        log_error "Please choose a different region or check service availability"
        exit 1
    fi
    
    log_success "WorkSpaces is available in region ${AWS_REGION}"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        log_error "AWS region is not configured"
        exit 1
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export VPC_NAME="workspaces-vpc-${RANDOM_SUFFIX}"
    export DIRECTORY_NAME="workspaces-dir-${RANDOM_SUFFIX}"
    export WORKSPACE_USERNAME="testuser${RANDOM_SUFFIX}"
    
    # Create deployment log file
    export DEPLOYMENT_LOG="/tmp/workspaces-deployment-$(date +%Y%m%d-%H%M%S).log"
    
    log_success "Environment variables configured"
    log_info "Deployment log: ${DEPLOYMENT_LOG}"
    echo "# WorkSpaces Deployment Log - $(date)" > "$DEPLOYMENT_LOG"
}

# Function to create VPC
create_vpc() {
    log_info "Creating VPC..."
    
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}},{Key=Purpose,Value=WorkSpaces}]" \
        --query 'Vpc.VpcId' --output text)
    
    if [[ -z "${VPC_ID}" ]]; then
        log_error "Failed to create VPC"
        exit 1
    fi
    
    # Enable DNS hostnames and resolution
    aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
    aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support
    
    echo "VPC_ID=${VPC_ID}" >> "$DEPLOYMENT_LOG"
    log_success "Created VPC: ${VPC_ID}"
}

# Function to create subnets
create_subnets() {
    log_info "Creating subnets..."
    
    # Get available Availability Zones
    AZ_1=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneName' --output text)
    AZ_2=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[1].ZoneName' --output text)
    
    # Create public subnet for NAT Gateway
    PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone "$AZ_1" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-public},{Key=Purpose,Value=WorkSpaces}]" \
        --query 'Subnet.SubnetId' --output text)
    
    # Create private subnets for WorkSpaces
    PRIVATE_SUBNET_1_ID=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block 10.0.2.0/24 \
        --availability-zone "$AZ_1" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-private-1},{Key=Purpose,Value=WorkSpaces}]" \
        --query 'Subnet.SubnetId' --output text)
    
    PRIVATE_SUBNET_2_ID=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block 10.0.3.0/24 \
        --availability-zone "$AZ_2" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-private-2},{Key=Purpose,Value=WorkSpaces}]" \
        --query 'Subnet.SubnetId' --output text)
    
    echo "PUBLIC_SUBNET_ID=${PUBLIC_SUBNET_ID}" >> "$DEPLOYMENT_LOG"
    echo "PRIVATE_SUBNET_1_ID=${PRIVATE_SUBNET_1_ID}" >> "$DEPLOYMENT_LOG"
    echo "PRIVATE_SUBNET_2_ID=${PRIVATE_SUBNET_2_ID}" >> "$DEPLOYMENT_LOG"
    
    log_success "Created subnets: Public=${PUBLIC_SUBNET_ID}, Private1=${PRIVATE_SUBNET_1_ID}, Private2=${PRIVATE_SUBNET_2_ID}"
}

# Function to set up internet connectivity
setup_internet_connectivity() {
    log_info "Setting up internet connectivity..."
    
    # Create and attach Internet Gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw},{Key=Purpose,Value=WorkSpaces}]" \
        --query 'InternetGateway.InternetGatewayId' --output text)
    
    aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
    
    # Allocate Elastic IP for NAT Gateway
    EIP_ALLOCATION_ID=$(aws ec2 allocate-address \
        --domain vpc \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${VPC_NAME}-nat-eip},{Key=Purpose,Value=WorkSpaces}]" \
        --query 'AllocationId' --output text)
    
    # Create NAT Gateway
    NAT_GW_ID=$(aws ec2 create-nat-gateway \
        --subnet-id "$PUBLIC_SUBNET_ID" \
        --allocation-id "$EIP_ALLOCATION_ID" \
        --tag-specifications "ResourceType=nat-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-nat},{Key=Purpose,Value=WorkSpaces}]" \
        --query 'NatGateway.NatGatewayId' --output text)
    
    # Wait for NAT Gateway to be available
    log_info "Waiting for NAT Gateway to become available..."
    aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_GW_ID"
    
    echo "IGW_ID=${IGW_ID}" >> "$DEPLOYMENT_LOG"
    echo "EIP_ALLOCATION_ID=${EIP_ALLOCATION_ID}" >> "$DEPLOYMENT_LOG"
    echo "NAT_GW_ID=${NAT_GW_ID}" >> "$DEPLOYMENT_LOG"
    
    log_success "Created networking components: IGW=${IGW_ID}, NAT=${NAT_GW_ID}"
}

# Function to configure route tables
configure_routing() {
    log_info "Configuring route tables..."
    
    # Create route table for public subnet
    PUBLIC_RT_ID=$(aws ec2 create-route-table \
        --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-public-rt},{Key=Purpose,Value=WorkSpaces}]" \
        --query 'RouteTable.RouteTableId' --output text)
    
    # Create route table for private subnets
    PRIVATE_RT_ID=$(aws ec2 create-route-table \
        --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-private-rt},{Key=Purpose,Value=WorkSpaces}]" \
        --query 'RouteTable.RouteTableId' --output text)
    
    # Add routes
    aws ec2 create-route --route-table-id "$PUBLIC_RT_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID"
    aws ec2 create-route --route-table-id "$PRIVATE_RT_ID" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_GW_ID"
    
    # Associate subnets with route tables
    aws ec2 associate-route-table --subnet-id "$PUBLIC_SUBNET_ID" --route-table-id "$PUBLIC_RT_ID"
    aws ec2 associate-route-table --subnet-id "$PRIVATE_SUBNET_1_ID" --route-table-id "$PRIVATE_RT_ID"
    aws ec2 associate-route-table --subnet-id "$PRIVATE_SUBNET_2_ID" --route-table-id "$PRIVATE_RT_ID"
    
    echo "PUBLIC_RT_ID=${PUBLIC_RT_ID}" >> "$DEPLOYMENT_LOG"
    echo "PRIVATE_RT_ID=${PRIVATE_RT_ID}" >> "$DEPLOYMENT_LOG"
    
    log_success "Configured routing for VPC"
}

# Function to create Simple AD directory
create_directory() {
    log_info "Creating Simple AD directory..."
    log_warning "This may take 10-15 minutes..."
    
    DIRECTORY_ID=$(aws ds create-directory \
        --name "${DIRECTORY_NAME}.local" \
        --password "TempPassword123!" \
        --description "WorkSpaces Simple AD Directory" \
        --size Small \
        --vpc-settings "VpcId=${VPC_ID},SubnetIds=${PRIVATE_SUBNET_1_ID},${PRIVATE_SUBNET_2_ID}" \
        --query 'DirectoryId' --output text)
    
    if [[ -z "${DIRECTORY_ID}" ]]; then
        log_error "Failed to create directory"
        exit 1
    fi
    
    # Wait for directory to be created
    log_info "Waiting for directory to become available..."
    aws ds wait directory-available --directory-ids "$DIRECTORY_ID"
    
    echo "DIRECTORY_ID=${DIRECTORY_ID}" >> "$DEPLOYMENT_LOG"
    log_success "Created Simple AD directory: ${DIRECTORY_ID}"
}

# Function to register directory with WorkSpaces
register_directory() {
    log_info "Registering directory with WorkSpaces..."
    
    aws workspaces register-workspace-directory \
        --directory-id "$DIRECTORY_ID" \
        --subnet-ids "$PRIVATE_SUBNET_1_ID" "$PRIVATE_SUBNET_2_ID" \
        --enable-work-docs \
        --enable-self-service
    
    # Wait for registration to complete
    sleep 30
    
    # Verify registration
    DIRECTORY_STATE=$(aws workspaces describe-workspace-directories \
        --directory-ids "$DIRECTORY_ID" \
        --query 'Directories[0].State' --output text)
    
    log_success "Registered directory with WorkSpaces (State: ${DIRECTORY_STATE})"
}

# Function to create WorkSpace
create_workspace() {
    log_info "Creating WorkSpace..."
    log_warning "This may take 20-30 minutes..."
    
    # Get available WorkSpace bundles
    BUNDLE_ID=$(aws workspaces describe-workspace-bundles \
        --query 'Bundles[?contains(Name, `Standard`) && contains(Name, `Windows`)].BundleId | [0]' \
        --output text)
    
    if [[ "${BUNDLE_ID}" == "null" || -z "${BUNDLE_ID}" ]]; then
        log_error "No suitable WorkSpace bundle found"
        exit 1
    fi
    
    # Create WorkSpace
    aws workspaces create-workspaces \
        --workspaces "DirectoryId=${DIRECTORY_ID},UserName=${WORKSPACE_USERNAME},BundleId=${BUNDLE_ID},UserVolumeEncryptionEnabled=true,RootVolumeEncryptionEnabled=true,WorkspaceProperties={RunningMode=AUTO_STOP,RunningModeAutoStopTimeoutInMinutes=60,RootVolumeSizeGib=80,UserVolumeSizeGib=50,ComputeTypeName=STANDARD}"
    
    # Wait for WorkSpace to be available
    log_info "Waiting for WorkSpace to become available..."
    sleep 60  # Initial wait before checking
    
    WORKSPACE_ID=""
    for i in {1..30}; do
        WORKSPACE_ID=$(aws workspaces describe-workspaces \
            --directory-id "$DIRECTORY_ID" \
            --query 'Workspaces[0].WorkspaceId' --output text 2>/dev/null || echo "")
        
        if [[ -n "${WORKSPACE_ID}" && "${WORKSPACE_ID}" != "null" ]]; then
            break
        fi
        
        log_info "WorkSpace creation in progress... (attempt $i/30)"
        sleep 60
    done
    
    if [[ -z "${WORKSPACE_ID}" || "${WORKSPACE_ID}" == "null" ]]; then
        log_error "Failed to get WorkSpace ID"
        exit 1
    fi
    
    echo "WORKSPACE_ID=${WORKSPACE_ID}" >> "$DEPLOYMENT_LOG"
    echo "BUNDLE_ID=${BUNDLE_ID}" >> "$DEPLOYMENT_LOG"
    log_success "Created WorkSpace: ${WORKSPACE_ID}"
}

# Function to configure WorkSpace security
configure_security() {
    log_info "Configuring WorkSpace security..."
    
    # Create IP access control group
    IP_GROUP_ID=$(aws workspaces create-ip-group \
        --group-name "${VPC_NAME}-ip-group" \
        --group-desc "IP access control for WorkSpaces" \
        --user-rules "ipRule=0.0.0.0/0,ruleDesc=Allow all IPs" \
        --query 'GroupId' --output text)
    
    # Associate IP group with directory
    aws workspaces associate-ip-groups \
        --directory-id "$DIRECTORY_ID" \
        --group-ids "$IP_GROUP_ID"
    
    echo "IP_GROUP_ID=${IP_GROUP_ID}" >> "$DEPLOYMENT_LOG"
    log_success "Configured WorkSpace security and properties"
    log_warning "IP group is configured to allow all IPs. Consider restricting in production."
}

# Function to set up CloudWatch monitoring
setup_monitoring() {
    log_info "Setting up CloudWatch monitoring..."
    
    # Create CloudWatch log group
    aws logs create-log-group \
        --log-group-name "/aws/workspaces/${DIRECTORY_ID}" 2>/dev/null || true
    
    # Create CloudWatch alarm for WorkSpace connection failures
    # Note: SNS topic creation is optional for this demo
    log_info "Setting up CloudWatch alarm..."
    aws cloudwatch put-metric-alarm \
        --alarm-name "WorkSpaces-Connection-Failures-${DIRECTORY_ID}" \
        --alarm-description "Monitor WorkSpace connection failures" \
        --metric-name "ConnectionAttempt" \
        --namespace "AWS/WorkSpaces" \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 2>/dev/null || true
    
    log_success "Configured CloudWatch monitoring"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check WorkSpace status
    WORKSPACE_STATE=$(aws workspaces describe-workspaces \
        --directory-id "$DIRECTORY_ID" \
        --query 'Workspaces[0].State' --output text 2>/dev/null || echo "NOT_FOUND")
    
    log_info "WorkSpace State: ${WORKSPACE_STATE}"
    
    # Check directory status
    DIRECTORY_STATE=$(aws ds describe-directories \
        --directory-ids "$DIRECTORY_ID" \
        --query 'DirectoryDescriptions[0].Stage' --output text 2>/dev/null || echo "NOT_FOUND")
    
    log_info "Directory State: ${DIRECTORY_STATE}"
    
    # Check VPC status
    VPC_STATE=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" \
        --query 'Vpcs[0].State' --output text 2>/dev/null || echo "NOT_FOUND")
    
    log_info "VPC State: ${VPC_STATE}"
    
    if [[ "${WORKSPACE_STATE}" == "AVAILABLE" && "${DIRECTORY_STATE}" == "Active" && "${VPC_STATE}" == "available" ]]; then
        log_success "Deployment validation successful"
        return 0
    else
        log_warning "Some resources may not be fully ready yet"
        return 1
    fi
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "===================="
    echo "VPC ID: ${VPC_ID}"
    echo "Directory ID: ${DIRECTORY_ID}"
    echo "WorkSpace ID: ${WORKSPACE_ID}"
    echo "WorkSpace Username: ${WORKSPACE_USERNAME}"
    echo "Directory Password: TempPassword123! (CHANGE THIS)"
    echo "Region: ${AWS_REGION}"
    echo "Deployment Log: ${DEPLOYMENT_LOG}"
    echo "===================="
    
    log_warning "IMPORTANT: Change the directory password immediately in production"
    log_info "Use 'aws workspaces describe-workspaces --directory-id ${DIRECTORY_ID}' to check WorkSpace status"
    log_info "Access your WorkSpace using the WorkSpaces client application"
}

# Function to handle script cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code $exit_code"
        log_info "Check the deployment log: ${DEPLOYMENT_LOG}"
        log_info "Use destroy.sh to clean up any partially created resources"
    fi
}

# Main deployment function
main() {
    echo "======================================="
    echo "AWS WorkSpaces Deployment Script"
    echo "======================================="
    
    # Set trap for cleanup on exit
    trap cleanup_on_exit EXIT
    
    check_prerequisites
    check_aws_auth
    setup_environment
    check_workspaces_availability
    
    create_vpc
    create_subnets
    setup_internet_connectivity
    configure_routing
    create_directory
    register_directory
    create_workspace
    configure_security
    setup_monitoring
    
    # Final validation
    if validate_deployment; then
        display_summary
        log_success "WorkSpaces deployment completed successfully!"
    else
        log_warning "Deployment completed but some resources may still be initializing"
        log_info "Run the validation again in a few minutes"
    fi
}

# Script execution check
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi