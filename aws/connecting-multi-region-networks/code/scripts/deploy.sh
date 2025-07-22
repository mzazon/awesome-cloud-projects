#!/bin/bash

# Multi-Region VPC Connectivity with Transit Gateway - Deployment Script
# This script deploys a complete multi-region Transit Gateway architecture
# with VPCs, cross-region peering, and monitoring capabilities

set -e
set -o pipefail

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

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/deployment-state.env"
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            cat << EOF
Usage: $0 [OPTIONS]

Deploy multi-region VPC connectivity with Transit Gateway

OPTIONS:
    --dry-run    Show what would be deployed without making changes
    --help       Show this help message

ENVIRONMENT VARIABLES:
    PRIMARY_REGION      Primary AWS region (default: us-east-1)
    SECONDARY_REGION    Secondary AWS region (default: us-west-2)
    PROJECT_NAME        Project name prefix (auto-generated if not set)
    ENABLE_MONITORING   Enable CloudWatch monitoring (default: true)

EXAMPLES:
    $0                                    # Deploy with defaults
    $0 --dry-run                         # Preview deployment
    PRIMARY_REGION=us-west-1 $0          # Deploy to different primary region
EOF
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

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
    
    # Check if jq is installed for JSON processing
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it for JSON processing."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Set default regions
    export PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
    export SECONDARY_REGION="${SECONDARY_REGION:-us-west-2}"
    
    # Validate regions are different
    if [[ "$PRIMARY_REGION" == "$SECONDARY_REGION" ]]; then
        error "Primary and secondary regions must be different"
        exit 1
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique project name if not provided
    if [[ -z "$PROJECT_NAME" ]]; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
        export PROJECT_NAME="multi-region-tgw-${RANDOM_SUFFIX}"
    fi
    
    # Set resource names
    export PRIMARY_TGW_NAME="${PROJECT_NAME}-primary"
    export SECONDARY_TGW_NAME="${PROJECT_NAME}-secondary"
    
    # Define CIDR blocks (ensure non-overlapping)
    export PRIMARY_VPC_A_CIDR="10.1.0.0/16"
    export PRIMARY_VPC_B_CIDR="10.2.0.0/16"
    export SECONDARY_VPC_A_CIDR="10.3.0.0/16"
    export SECONDARY_VPC_B_CIDR="10.4.0.0/16"
    
    # Enable monitoring by default
    export ENABLE_MONITORING="${ENABLE_MONITORING:-true}"
    
    success "Environment variables configured"
    log "Primary Region: ${PRIMARY_REGION}"
    log "Secondary Region: ${SECONDARY_REGION}"
    log "Project Name: ${PROJECT_NAME}"
    log "AWS Account ID: ${AWS_ACCOUNT_ID}"
}

# Function to save state
save_state() {
    log "Saving deployment state..."
    cat > "$STATE_FILE" << EOF
# Multi-Region Transit Gateway Deployment State
# Generated on $(date)

# Project Configuration
PROJECT_NAME="${PROJECT_NAME}"
PRIMARY_REGION="${PRIMARY_REGION}"
SECONDARY_REGION="${SECONDARY_REGION}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"

# Resource Names
PRIMARY_TGW_NAME="${PRIMARY_TGW_NAME}"
SECONDARY_TGW_NAME="${SECONDARY_TGW_NAME}"

# CIDR Blocks
PRIMARY_VPC_A_CIDR="${PRIMARY_VPC_A_CIDR}"
PRIMARY_VPC_B_CIDR="${PRIMARY_VPC_B_CIDR}"
SECONDARY_VPC_A_CIDR="${SECONDARY_VPC_A_CIDR}"
SECONDARY_VPC_B_CIDR="${SECONDARY_VPC_B_CIDR}"

# Resource IDs (populated during deployment)
PRIMARY_TGW_ID="${PRIMARY_TGW_ID:-}"
SECONDARY_TGW_ID="${SECONDARY_TGW_ID:-}"
PRIMARY_VPC_A_ID="${PRIMARY_VPC_A_ID:-}"
PRIMARY_VPC_B_ID="${PRIMARY_VPC_B_ID:-}"
SECONDARY_VPC_A_ID="${SECONDARY_VPC_A_ID:-}"
SECONDARY_VPC_B_ID="${SECONDARY_VPC_B_ID:-}"
PRIMARY_SUBNET_A_ID="${PRIMARY_SUBNET_A_ID:-}"
PRIMARY_SUBNET_B_ID="${PRIMARY_SUBNET_B_ID:-}"
SECONDARY_SUBNET_A_ID="${SECONDARY_SUBNET_A_ID:-}"
SECONDARY_SUBNET_B_ID="${SECONDARY_SUBNET_B_ID:-}"
PRIMARY_ATTACHMENT_A_ID="${PRIMARY_ATTACHMENT_A_ID:-}"
PRIMARY_ATTACHMENT_B_ID="${PRIMARY_ATTACHMENT_B_ID:-}"
SECONDARY_ATTACHMENT_A_ID="${SECONDARY_ATTACHMENT_A_ID:-}"
SECONDARY_ATTACHMENT_B_ID="${SECONDARY_ATTACHMENT_B_ID:-}"
PEERING_ATTACHMENT_ID="${PEERING_ATTACHMENT_ID:-}"
PRIMARY_ROUTE_TABLE_ID="${PRIMARY_ROUTE_TABLE_ID:-}"
SECONDARY_ROUTE_TABLE_ID="${SECONDARY_ROUTE_TABLE_ID:-}"
PRIMARY_SG_A_ID="${PRIMARY_SG_A_ID:-}"
SECONDARY_SG_A_ID="${SECONDARY_SG_A_ID:-}"
EOF
    success "State saved to ${STATE_FILE}"
}

# Function to update state variable
update_state() {
    local var_name="$1"
    local var_value="$2"
    
    if [[ -f "$STATE_FILE" ]]; then
        sed -i.bak "s/^${var_name}=.*/${var_name}=\"${var_value}\"/" "$STATE_FILE"
        rm -f "${STATE_FILE}.bak"
    fi
}

# Function to create VPCs
create_vpcs() {
    log "Creating VPCs in both regions..."
    
    # Create VPCs in primary region
    log "Creating VPCs in primary region (${PRIMARY_REGION})..."
    
    PRIMARY_VPC_A_ID=$(aws ec2 create-vpc \
        --cidr-block "${PRIMARY_VPC_A_CIDR}" \
        --region "${PRIMARY_REGION}" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-primary-vpc-a},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'Vpc.VpcId' --output text)
    
    PRIMARY_VPC_B_ID=$(aws ec2 create-vpc \
        --cidr-block "${PRIMARY_VPC_B_CIDR}" \
        --region "${PRIMARY_REGION}" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-primary-vpc-b},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'Vpc.VpcId' --output text)
    
    # Wait for VPCs to be available
    aws ec2 wait vpc-available --vpc-ids "${PRIMARY_VPC_A_ID}" --region "${PRIMARY_REGION}"
    aws ec2 wait vpc-available --vpc-ids "${PRIMARY_VPC_B_ID}" --region "${PRIMARY_REGION}"
    
    # Create VPCs in secondary region
    log "Creating VPCs in secondary region (${SECONDARY_REGION})..."
    
    SECONDARY_VPC_A_ID=$(aws ec2 create-vpc \
        --cidr-block "${SECONDARY_VPC_A_CIDR}" \
        --region "${SECONDARY_REGION}" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-secondary-vpc-a},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'Vpc.VpcId' --output text)
    
    SECONDARY_VPC_B_ID=$(aws ec2 create-vpc \
        --cidr-block "${SECONDARY_VPC_B_CIDR}" \
        --region "${SECONDARY_REGION}" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-secondary-vpc-b},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'Vpc.VpcId' --output text)
    
    # Wait for VPCs to be available
    aws ec2 wait vpc-available --vpc-ids "${SECONDARY_VPC_A_ID}" --region "${SECONDARY_REGION}"
    aws ec2 wait vpc-available --vpc-ids "${SECONDARY_VPC_B_ID}" --region "${SECONDARY_REGION}"
    
    # Update state file
    update_state "PRIMARY_VPC_A_ID" "${PRIMARY_VPC_A_ID}"
    update_state "PRIMARY_VPC_B_ID" "${PRIMARY_VPC_B_ID}"
    update_state "SECONDARY_VPC_A_ID" "${SECONDARY_VPC_A_ID}"
    update_state "SECONDARY_VPC_B_ID" "${SECONDARY_VPC_B_ID}"
    
    success "Created VPCs in both regions"
    log "Primary VPC A: ${PRIMARY_VPC_A_ID}"
    log "Primary VPC B: ${PRIMARY_VPC_B_ID}"
    log "Secondary VPC A: ${SECONDARY_VPC_A_ID}"
    log "Secondary VPC B: ${SECONDARY_VPC_B_ID}"
}

# Function to create subnets
create_subnets() {
    log "Creating subnets in both regions..."
    
    # Create subnets in primary region
    PRIMARY_SUBNET_A_ID=$(aws ec2 create-subnet \
        --vpc-id "${PRIMARY_VPC_A_ID}" \
        --cidr-block "10.1.1.0/24" \
        --availability-zone "${PRIMARY_REGION}a" \
        --region "${PRIMARY_REGION}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-primary-subnet-a},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'Subnet.SubnetId' --output text)
    
    PRIMARY_SUBNET_B_ID=$(aws ec2 create-subnet \
        --vpc-id "${PRIMARY_VPC_B_ID}" \
        --cidr-block "10.2.1.0/24" \
        --availability-zone "${PRIMARY_REGION}a" \
        --region "${PRIMARY_REGION}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-primary-subnet-b},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'Subnet.SubnetId' --output text)
    
    # Create subnets in secondary region
    SECONDARY_SUBNET_A_ID=$(aws ec2 create-subnet \
        --vpc-id "${SECONDARY_VPC_A_ID}" \
        --cidr-block "10.3.1.0/24" \
        --availability-zone "${SECONDARY_REGION}a" \
        --region "${SECONDARY_REGION}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-secondary-subnet-a},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'Subnet.SubnetId' --output text)
    
    SECONDARY_SUBNET_B_ID=$(aws ec2 create-subnet \
        --vpc-id "${SECONDARY_VPC_B_ID}" \
        --cidr-block "10.4.1.0/24" \
        --availability-zone "${SECONDARY_REGION}a" \
        --region "${SECONDARY_REGION}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-secondary-subnet-b},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'Subnet.SubnetId' --output text)
    
    # Update state file
    update_state "PRIMARY_SUBNET_A_ID" "${PRIMARY_SUBNET_A_ID}"
    update_state "PRIMARY_SUBNET_B_ID" "${PRIMARY_SUBNET_B_ID}"
    update_state "SECONDARY_SUBNET_A_ID" "${SECONDARY_SUBNET_A_ID}"
    update_state "SECONDARY_SUBNET_B_ID" "${SECONDARY_SUBNET_B_ID}"
    
    success "Created subnets in both regions"
}

# Function to create Transit Gateways
create_transit_gateways() {
    log "Creating Transit Gateways in both regions..."
    
    # Create Transit Gateway in primary region
    PRIMARY_TGW_ID=$(aws ec2 create-transit-gateway \
        --description "Primary region Transit Gateway for ${PROJECT_NAME}" \
        --options DefaultRouteTableAssociation=enable,DefaultRouteTablePropagation=enable,AmazonSideAsn=64512 \
        --tag-specifications "ResourceType=transit-gateway,Tags=[{Key=Name,Value=${PRIMARY_TGW_NAME}},{Key=Project,Value=${PROJECT_NAME}}]" \
        --region "${PRIMARY_REGION}" \
        --query 'TransitGateway.TransitGatewayId' --output text)
    
    # Create Transit Gateway in secondary region
    SECONDARY_TGW_ID=$(aws ec2 create-transit-gateway \
        --description "Secondary region Transit Gateway for ${PROJECT_NAME}" \
        --options DefaultRouteTableAssociation=enable,DefaultRouteTablePropagation=enable,AmazonSideAsn=64513 \
        --tag-specifications "ResourceType=transit-gateway,Tags=[{Key=Name,Value=${SECONDARY_TGW_NAME}},{Key=Project,Value=${PROJECT_NAME}}]" \
        --region "${SECONDARY_REGION}" \
        --query 'TransitGateway.TransitGatewayId' --output text)
    
    # Wait for Transit Gateways to be available
    log "Waiting for Transit Gateways to be available..."
    aws ec2 wait transit-gateway-available --transit-gateway-ids "${PRIMARY_TGW_ID}" --region "${PRIMARY_REGION}"
    aws ec2 wait transit-gateway-available --transit-gateway-ids "${SECONDARY_TGW_ID}" --region "${SECONDARY_REGION}"
    
    # Update state file
    update_state "PRIMARY_TGW_ID" "${PRIMARY_TGW_ID}"
    update_state "SECONDARY_TGW_ID" "${SECONDARY_TGW_ID}"
    
    success "Created Transit Gateways in both regions"
    log "Primary Transit Gateway: ${PRIMARY_TGW_ID}"
    log "Secondary Transit Gateway: ${SECONDARY_TGW_ID}"
}

# Function to create VPC attachments
create_vpc_attachments() {
    log "Creating VPC attachments to Transit Gateways..."
    
    # Attach VPCs to primary Transit Gateway
    PRIMARY_ATTACHMENT_A_ID=$(aws ec2 create-transit-gateway-vpc-attachment \
        --transit-gateway-id "${PRIMARY_TGW_ID}" \
        --vpc-id "${PRIMARY_VPC_A_ID}" \
        --subnet-ids "${PRIMARY_SUBNET_A_ID}" \
        --region "${PRIMARY_REGION}" \
        --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)
    
    PRIMARY_ATTACHMENT_B_ID=$(aws ec2 create-transit-gateway-vpc-attachment \
        --transit-gateway-id "${PRIMARY_TGW_ID}" \
        --vpc-id "${PRIMARY_VPC_B_ID}" \
        --subnet-ids "${PRIMARY_SUBNET_B_ID}" \
        --region "${PRIMARY_REGION}" \
        --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)
    
    # Attach VPCs to secondary Transit Gateway
    SECONDARY_ATTACHMENT_A_ID=$(aws ec2 create-transit-gateway-vpc-attachment \
        --transit-gateway-id "${SECONDARY_TGW_ID}" \
        --vpc-id "${SECONDARY_VPC_A_ID}" \
        --subnet-ids "${SECONDARY_SUBNET_A_ID}" \
        --region "${SECONDARY_REGION}" \
        --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)
    
    SECONDARY_ATTACHMENT_B_ID=$(aws ec2 create-transit-gateway-vpc-attachment \
        --transit-gateway-id "${SECONDARY_TGW_ID}" \
        --vpc-id "${SECONDARY_VPC_B_ID}" \
        --subnet-ids "${SECONDARY_SUBNET_B_ID}" \
        --region "${SECONDARY_REGION}" \
        --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)
    
    # Update state file
    update_state "PRIMARY_ATTACHMENT_A_ID" "${PRIMARY_ATTACHMENT_A_ID}"
    update_state "PRIMARY_ATTACHMENT_B_ID" "${PRIMARY_ATTACHMENT_B_ID}"
    update_state "SECONDARY_ATTACHMENT_A_ID" "${SECONDARY_ATTACHMENT_A_ID}"
    update_state "SECONDARY_ATTACHMENT_B_ID" "${SECONDARY_ATTACHMENT_B_ID}"
    
    success "Created VPC attachments to Transit Gateways"
}

# Function to create cross-region peering
create_cross_region_peering() {
    log "Creating cross-region Transit Gateway peering..."
    
    # Create peering attachment from primary to secondary region
    PEERING_ATTACHMENT_ID=$(aws ec2 create-transit-gateway-peering-attachment \
        --transit-gateway-id "${PRIMARY_TGW_ID}" \
        --peer-transit-gateway-id "${SECONDARY_TGW_ID}" \
        --peer-account-id "${AWS_ACCOUNT_ID}" \
        --peer-region "${SECONDARY_REGION}" \
        --region "${PRIMARY_REGION}" \
        --query 'TransitGatewayPeeringAttachment.TransitGatewayAttachmentId' --output text)
    
    # Wait for peering attachment to be in pending state
    log "Waiting for peering attachment to be ready for acceptance..."
    sleep 30
    
    # Accept the peering attachment in secondary region
    aws ec2 accept-transit-gateway-peering-attachment \
        --transit-gateway-attachment-id "${PEERING_ATTACHMENT_ID}" \
        --region "${SECONDARY_REGION}"
    
    # Update state file
    update_state "PEERING_ATTACHMENT_ID" "${PEERING_ATTACHMENT_ID}"
    
    success "Created and accepted cross-region peering attachment: ${PEERING_ATTACHMENT_ID}"
}

# Function to create custom route tables
create_route_tables() {
    log "Creating custom route tables..."
    
    # Create custom route table for primary region
    PRIMARY_ROUTE_TABLE_ID=$(aws ec2 create-transit-gateway-route-table \
        --transit-gateway-id "${PRIMARY_TGW_ID}" \
        --tag-specifications "ResourceType=transit-gateway-route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-primary-rt},{Key=Project,Value=${PROJECT_NAME}}]" \
        --region "${PRIMARY_REGION}" \
        --query 'TransitGatewayRouteTable.TransitGatewayRouteTableId' --output text)
    
    # Create custom route table for secondary region
    SECONDARY_ROUTE_TABLE_ID=$(aws ec2 create-transit-gateway-route-table \
        --transit-gateway-id "${SECONDARY_TGW_ID}" \
        --tag-specifications "ResourceType=transit-gateway-route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-secondary-rt},{Key=Project,Value=${PROJECT_NAME}}]" \
        --region "${SECONDARY_REGION}" \
        --query 'TransitGatewayRouteTable.TransitGatewayRouteTableId' --output text)
    
    # Update state file
    update_state "PRIMARY_ROUTE_TABLE_ID" "${PRIMARY_ROUTE_TABLE_ID}"
    update_state "SECONDARY_ROUTE_TABLE_ID" "${SECONDARY_ROUTE_TABLE_ID}"
    
    success "Created custom route tables"
}

# Function to configure route table associations
configure_route_associations() {
    log "Configuring route table associations..."
    
    # Associate attachments with custom route tables in primary region
    aws ec2 associate-transit-gateway-route-table \
        --transit-gateway-attachment-id "${PRIMARY_ATTACHMENT_A_ID}" \
        --transit-gateway-route-table-id "${PRIMARY_ROUTE_TABLE_ID}" \
        --region "${PRIMARY_REGION}"
    
    aws ec2 associate-transit-gateway-route-table \
        --transit-gateway-attachment-id "${PRIMARY_ATTACHMENT_B_ID}" \
        --transit-gateway-route-table-id "${PRIMARY_ROUTE_TABLE_ID}" \
        --region "${PRIMARY_REGION}"
    
    # Associate peering attachment with primary route table
    aws ec2 associate-transit-gateway-route-table \
        --transit-gateway-attachment-id "${PEERING_ATTACHMENT_ID}" \
        --transit-gateway-route-table-id "${PRIMARY_ROUTE_TABLE_ID}" \
        --region "${PRIMARY_REGION}"
    
    # Associate attachments with custom route tables in secondary region
    aws ec2 associate-transit-gateway-route-table \
        --transit-gateway-attachment-id "${SECONDARY_ATTACHMENT_A_ID}" \
        --transit-gateway-route-table-id "${SECONDARY_ROUTE_TABLE_ID}" \
        --region "${SECONDARY_REGION}"
    
    aws ec2 associate-transit-gateway-route-table \
        --transit-gateway-attachment-id "${SECONDARY_ATTACHMENT_B_ID}" \
        --transit-gateway-route-table-id "${SECONDARY_ROUTE_TABLE_ID}" \
        --region "${SECONDARY_REGION}"
    
    # Associate peering attachment with secondary route table
    aws ec2 associate-transit-gateway-route-table \
        --transit-gateway-attachment-id "${PEERING_ATTACHMENT_ID}" \
        --transit-gateway-route-table-id "${SECONDARY_ROUTE_TABLE_ID}" \
        --region "${SECONDARY_REGION}"
    
    success "Configured route table associations"
}

# Function to create cross-region routes
create_cross_region_routes() {
    log "Creating cross-region routes..."
    
    # Create routes from primary to secondary region
    aws ec2 create-transit-gateway-route \
        --destination-cidr-block "${SECONDARY_VPC_A_CIDR}" \
        --transit-gateway-route-table-id "${PRIMARY_ROUTE_TABLE_ID}" \
        --transit-gateway-attachment-id "${PEERING_ATTACHMENT_ID}" \
        --region "${PRIMARY_REGION}"
    
    aws ec2 create-transit-gateway-route \
        --destination-cidr-block "${SECONDARY_VPC_B_CIDR}" \
        --transit-gateway-route-table-id "${PRIMARY_ROUTE_TABLE_ID}" \
        --transit-gateway-attachment-id "${PEERING_ATTACHMENT_ID}" \
        --region "${PRIMARY_REGION}"
    
    # Create routes from secondary to primary region
    aws ec2 create-transit-gateway-route \
        --destination-cidr-block "${PRIMARY_VPC_A_CIDR}" \
        --transit-gateway-route-table-id "${SECONDARY_ROUTE_TABLE_ID}" \
        --transit-gateway-attachment-id "${PEERING_ATTACHMENT_ID}" \
        --region "${SECONDARY_REGION}"
    
    aws ec2 create-transit-gateway-route \
        --destination-cidr-block "${PRIMARY_VPC_B_CIDR}" \
        --transit-gateway-route-table-id "${SECONDARY_ROUTE_TABLE_ID}" \
        --transit-gateway-attachment-id "${PEERING_ATTACHMENT_ID}" \
        --region "${SECONDARY_REGION}"
    
    success "Created cross-region routes"
}

# Function to create security groups
create_security_groups() {
    log "Creating security groups for cross-region access..."
    
    # Create security group in primary VPC A
    PRIMARY_SG_A_ID=$(aws ec2 create-security-group \
        --group-name "${PROJECT_NAME}-primary-sg-a" \
        --description "Security group for cross-region connectivity" \
        --vpc-id "${PRIMARY_VPC_A_ID}" \
        --region "${PRIMARY_REGION}" \
        --query 'GroupId' --output text)
    
    # Create security group in secondary VPC A
    SECONDARY_SG_A_ID=$(aws ec2 create-security-group \
        --group-name "${PROJECT_NAME}-secondary-sg-a" \
        --description "Security group for cross-region connectivity" \
        --vpc-id "${SECONDARY_VPC_A_ID}" \
        --region "${SECONDARY_REGION}" \
        --query 'GroupId' --output text)
    
    # Allow ICMP from remote regions for testing
    aws ec2 authorize-security-group-ingress \
        --group-id "${PRIMARY_SG_A_ID}" \
        --protocol icmp \
        --port -1 \
        --cidr "${SECONDARY_VPC_A_CIDR}" \
        --region "${PRIMARY_REGION}"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "${SECONDARY_SG_A_ID}" \
        --protocol icmp \
        --port -1 \
        --cidr "${PRIMARY_VPC_A_CIDR}" \
        --region "${SECONDARY_REGION}"
    
    # Update state file
    update_state "PRIMARY_SG_A_ID" "${PRIMARY_SG_A_ID}"
    update_state "SECONDARY_SG_A_ID" "${SECONDARY_SG_A_ID}"
    
    success "Created security groups for cross-region access"
}

# Function to set up CloudWatch monitoring
setup_monitoring() {
    if [[ "$ENABLE_MONITORING" == "true" ]]; then
        log "Setting up CloudWatch monitoring..."
        
        # Create CloudWatch dashboard for Transit Gateway monitoring
        aws cloudwatch put-dashboard \
            --dashboard-name "${PROJECT_NAME}-tgw-dashboard" \
            --dashboard-body "{
                \"widgets\": [
                    {
                        \"type\": \"metric\",
                        \"properties\": {
                            \"metrics\": [
                                [\"AWS/TransitGateway\", \"BytesIn\", \"TransitGateway\", \"${PRIMARY_TGW_ID}\"],
                                [\".\", \"BytesOut\", \".\", \".\"],
                                [\".\", \"PacketDropCount\", \".\", \".\"]
                            ],
                            \"period\": 300,
                            \"stat\": \"Sum\",
                            \"region\": \"${PRIMARY_REGION}\",
                            \"title\": \"Primary Transit Gateway Metrics\"
                        }
                    },
                    {
                        \"type\": \"metric\",
                        \"properties\": {
                            \"metrics\": [
                                [\"AWS/TransitGateway\", \"BytesIn\", \"TransitGateway\", \"${SECONDARY_TGW_ID}\"],
                                [\".\", \"BytesOut\", \".\", \".\"],
                                [\".\", \"PacketDropCount\", \".\", \".\"]
                            ],
                            \"period\": 300,
                            \"stat\": \"Sum\",
                            \"region\": \"${SECONDARY_REGION}\",
                            \"title\": \"Secondary Transit Gateway Metrics\"
                        }
                    }
                ]
            }" \
            --region "${PRIMARY_REGION}"
        
        success "Created CloudWatch dashboard for monitoring"
    else
        log "Monitoring disabled, skipping CloudWatch setup"
    fi
}

# Function to run validation tests
run_validation() {
    log "Running validation tests..."
    
    # Check Transit Gateway status
    log "Checking Transit Gateway status..."
    
    primary_state=$(aws ec2 describe-transit-gateways \
        --transit-gateway-ids "${PRIMARY_TGW_ID}" \
        --region "${PRIMARY_REGION}" \
        --query 'TransitGateways[0].State' --output text)
    
    secondary_state=$(aws ec2 describe-transit-gateways \
        --transit-gateway-ids "${SECONDARY_TGW_ID}" \
        --region "${SECONDARY_REGION}" \
        --query 'TransitGateways[0].State' --output text)
    
    if [[ "$primary_state" == "available" && "$secondary_state" == "available" ]]; then
        success "Transit Gateways are available"
    else
        error "Transit Gateways are not available: Primary: $primary_state, Secondary: $secondary_state"
        return 1
    fi
    
    # Check peering attachment status
    log "Checking peering attachment status..."
    
    peering_state=$(aws ec2 describe-transit-gateway-peering-attachments \
        --transit-gateway-attachment-ids "${PEERING_ATTACHMENT_ID}" \
        --region "${PRIMARY_REGION}" \
        --query 'TransitGatewayPeeringAttachments[0].State' --output text)
    
    if [[ "$peering_state" == "available" ]]; then
        success "Peering attachment is available"
    else
        error "Peering attachment is not available: $peering_state"
        return 1
    fi
    
    # Check route propagation
    log "Checking route propagation..."
    
    primary_routes=$(aws ec2 search-transit-gateway-routes \
        --transit-gateway-route-table-id "${PRIMARY_ROUTE_TABLE_ID}" \
        --filters "Name=state,Values=active" \
        --region "${PRIMARY_REGION}" \
        --query 'length(Routes)')
    
    secondary_routes=$(aws ec2 search-transit-gateway-routes \
        --transit-gateway-route-table-id "${SECONDARY_ROUTE_TABLE_ID}" \
        --filters "Name=state,Values=active" \
        --region "${SECONDARY_REGION}" \
        --query 'length(Routes)')
    
    if [[ "$primary_routes" -gt 0 && "$secondary_routes" -gt 0 ]]; then
        success "Route propagation is working (Primary: $primary_routes routes, Secondary: $secondary_routes routes)"
    else
        warning "Route propagation may need more time to complete"
    fi
    
    success "Validation tests completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================================="
    echo "Project Name: ${PROJECT_NAME}"
    echo "Primary Region: ${PRIMARY_REGION}"
    echo "Secondary Region: ${SECONDARY_REGION}"
    echo ""
    echo "Resources Created:"
    echo "  Primary Transit Gateway: ${PRIMARY_TGW_ID}"
    echo "  Secondary Transit Gateway: ${SECONDARY_TGW_ID}"
    echo "  Peering Attachment: ${PEERING_ATTACHMENT_ID}"
    echo "  VPCs: 4 (2 per region)"
    echo "  Subnets: 4 (2 per region)"
    echo "  Security Groups: 2 (1 per region)"
    echo ""
    echo "Next Steps:"
    echo "  1. Deploy test instances in each VPC to validate connectivity"
    echo "  2. Review CloudWatch dashboard: ${PROJECT_NAME}-tgw-dashboard"
    echo "  3. Customize security groups for your application requirements"
    echo "  4. Consider enabling VPC Flow Logs for detailed traffic analysis"
    echo ""
    echo "Cost Considerations:"
    echo "  - Transit Gateway hourly charges: ~$36-48/month"
    echo "  - Data processing charges: $0.02/GB"
    echo "  - Cross-region data transfer: $0.02/GB"
    echo ""
    echo "Cleanup:"
    echo "  Run './destroy.sh' to remove all resources"
    echo "=================================="
}

# Main deployment function
deploy() {
    log "Starting multi-region Transit Gateway deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN MODE - No resources will be created"
        return 0
    fi
    
    # Initialize state file
    save_state
    
    # Deploy infrastructure
    create_vpcs
    create_subnets
    create_transit_gateways
    create_vpc_attachments
    create_cross_region_peering
    create_route_tables
    configure_route_associations
    create_cross_region_routes
    create_security_groups
    setup_monitoring
    
    # Final state save
    save_state
    
    # Run validation
    run_validation
    
    # Display summary
    display_summary
    
    success "Multi-region Transit Gateway deployment completed successfully!"
    log "State file saved to: ${STATE_FILE}"
}

# Main script execution
main() {
    check_prerequisites
    set_environment_variables
    deploy
}

# Handle script interruption
trap 'error "Deployment interrupted. Check ${STATE_FILE} for current state."; exit 1' INT TERM

# Execute main function
main "$@"