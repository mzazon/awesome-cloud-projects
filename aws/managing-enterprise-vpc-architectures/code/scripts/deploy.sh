#!/bin/bash

# Deploy script for Multi-VPC Architectures with Transit Gateway
# This script deploys a complete multi-VPC architecture with Transit Gateway
# and custom route table management for network segmentation

set -euo pipefail

# Color codes for output
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
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Cleanup function for failed deployments
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    
    # Attempt to clean up any created resources
    if [[ -f "/tmp/deployment_state.json" ]]; then
        log "Attempting to clean up partially created resources..."
        
        # Read state file and clean up in reverse order
        if [[ -s "/tmp/deployment_state.json" ]]; then
            # This would contain cleanup logic based on what was created
            # For now, we'll just log the failure and exit
            log_warning "Please run destroy.sh to clean up any created resources"
        fi
    fi
    
    exit 1
}

# Set error trap
trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or you're not authenticated."
        log_error "Please run 'aws configure' first."
        exit 1
    fi
    
    # Check IAM permissions (basic check)
    if ! aws ec2 describe-vpcs --max-items 1 &> /dev/null; then
        log_error "Insufficient IAM permissions for EC2 operations."
        exit 1
    fi
    
    if ! aws ec2 describe-transit-gateways --max-items 1 &> /dev/null; then
        log_error "Insufficient IAM permissions for Transit Gateway operations."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "AWS region not set, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    # Set resource names
    export TGW_NAME="enterprise-tgw-${RANDOM_SUFFIX}"
    export PROD_VPC_NAME="prod-vpc-${RANDOM_SUFFIX}"
    export DEV_VPC_NAME="dev-vpc-${RANDOM_SUFFIX}"
    export TEST_VPC_NAME="test-vpc-${RANDOM_SUFFIX}"
    export SHARED_VPC_NAME="shared-vpc-${RANDOM_SUFFIX}"
    
    # Create state file for tracking deployment
    cat > /tmp/deployment_state.json << EOF
{
    "deployment_id": "${RANDOM_SUFFIX}",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "resources_created": []
}
EOF
    
    log_success "Environment setup complete"
    log "Region: $AWS_REGION"
    log "Account ID: $AWS_ACCOUNT_ID"
    log "Deployment ID: $RANDOM_SUFFIX"
}

# Create VPCs
create_vpcs() {
    log "Creating VPCs for multi-VPC architecture..."
    
    # Create Production VPC
    export PROD_VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROD_VPC_NAME}},{Key=Environment,Value=production},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'Vpc.VpcId' --output text)
    echo "PROD_VPC_ID=${PROD_VPC_ID}" >> /tmp/deployment_vars.env
    
    # Create Development VPC
    export DEV_VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.1.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${DEV_VPC_NAME}},{Key=Environment,Value=development},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'Vpc.VpcId' --output text)
    echo "DEV_VPC_ID=${DEV_VPC_ID}" >> /tmp/deployment_vars.env
    
    # Create Test VPC
    export TEST_VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.2.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${TEST_VPC_NAME}},{Key=Environment,Value=test},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'Vpc.VpcId' --output text)
    echo "TEST_VPC_ID=${TEST_VPC_ID}" >> /tmp/deployment_vars.env
    
    # Create Shared Services VPC
    export SHARED_VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.3.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${SHARED_VPC_NAME}},{Key=Environment,Value=shared},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'Vpc.VpcId' --output text)
    echo "SHARED_VPC_ID=${SHARED_VPC_ID}" >> /tmp/deployment_vars.env
    
    log_success "Created VPCs:"
    log "  Production VPC: $PROD_VPC_ID (10.0.0.0/16)"
    log "  Development VPC: $DEV_VPC_ID (10.1.0.0/16)"
    log "  Test VPC: $TEST_VPC_ID (10.2.0.0/16)"
    log "  Shared Services VPC: $SHARED_VPC_ID (10.3.0.0/16)"
}

# Create subnets
create_subnets() {
    log "Creating subnets in each VPC..."
    
    # Create Production subnet
    export PROD_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id $PROD_VPC_ID \
        --cidr-block 10.0.1.0/24 \
        --availability-zone ${AWS_REGION}a \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=prod-subnet-a},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'Subnet.SubnetId' --output text)
    echo "PROD_SUBNET_ID=${PROD_SUBNET_ID}" >> /tmp/deployment_vars.env
    
    # Create Development subnet
    export DEV_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id $DEV_VPC_ID \
        --cidr-block 10.1.1.0/24 \
        --availability-zone ${AWS_REGION}a \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=dev-subnet-a},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'Subnet.SubnetId' --output text)
    echo "DEV_SUBNET_ID=${DEV_SUBNET_ID}" >> /tmp/deployment_vars.env
    
    # Create Test subnet
    export TEST_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id $TEST_VPC_ID \
        --cidr-block 10.2.1.0/24 \
        --availability-zone ${AWS_REGION}a \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=test-subnet-a},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'Subnet.SubnetId' --output text)
    echo "TEST_SUBNET_ID=${TEST_SUBNET_ID}" >> /tmp/deployment_vars.env
    
    # Create Shared Services subnet
    export SHARED_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id $SHARED_VPC_ID \
        --cidr-block 10.3.1.0/24 \
        --availability-zone ${AWS_REGION}a \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=shared-subnet-a},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'Subnet.SubnetId' --output text)
    echo "SHARED_SUBNET_ID=${SHARED_SUBNET_ID}" >> /tmp/deployment_vars.env
    
    log_success "Created subnets in all VPCs"
}

# Create Transit Gateway
create_transit_gateway() {
    log "Creating Transit Gateway..."
    
    export TGW_ID=$(aws ec2 create-transit-gateway \
        --description "Enterprise Multi-VPC Transit Gateway" \
        --options AmazonSideAsn=64512,AutoAcceptSharedAttachments=disable,DefaultRouteTableAssociation=disable,DefaultRouteTablePropagation=disable,VpnEcmpSupport=enable,DnsSupport=enable \
        --tag-specifications "ResourceType=transit-gateway,Tags=[{Key=Name,Value=${TGW_NAME}},{Key=Environment,Value=production},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'TransitGateway.TransitGatewayId' --output text)
    echo "TGW_ID=${TGW_ID}" >> /tmp/deployment_vars.env
    
    log "Waiting for Transit Gateway to become available..."
    aws ec2 wait transit-gateway-available --transit-gateway-ids $TGW_ID
    
    log_success "Created Transit Gateway: $TGW_ID"
}

# Create custom route tables
create_route_tables() {
    log "Creating custom route tables for network segmentation..."
    
    # Create Production Route Table
    export PROD_RT_ID=$(aws ec2 create-transit-gateway-route-table \
        --transit-gateway-id $TGW_ID \
        --tag-specifications "ResourceType=transit-gateway-route-table,Tags=[{Key=Name,Value=prod-route-table},{Key=Environment,Value=production},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'TransitGatewayRouteTable.TransitGatewayRouteTableId' --output text)
    echo "PROD_RT_ID=${PROD_RT_ID}" >> /tmp/deployment_vars.env
    
    # Create Development Route Table
    export DEV_RT_ID=$(aws ec2 create-transit-gateway-route-table \
        --transit-gateway-id $TGW_ID \
        --tag-specifications "ResourceType=transit-gateway-route-table,Tags=[{Key=Name,Value=dev-route-table},{Key=Environment,Value=development},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'TransitGatewayRouteTable.TransitGatewayRouteTableId' --output text)
    echo "DEV_RT_ID=${DEV_RT_ID}" >> /tmp/deployment_vars.env
    
    # Create Shared Services Route Table
    export SHARED_RT_ID=$(aws ec2 create-transit-gateway-route-table \
        --transit-gateway-id $TGW_ID \
        --tag-specifications "ResourceType=transit-gateway-route-table,Tags=[{Key=Name,Value=shared-route-table},{Key=Environment,Value=shared},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'TransitGatewayRouteTable.TransitGatewayRouteTableId' --output text)
    echo "SHARED_RT_ID=${SHARED_RT_ID}" >> /tmp/deployment_vars.env
    
    log_success "Created custom route tables for network segmentation"
}

# Create VPC attachments
create_vpc_attachments() {
    log "Creating VPC attachments to Transit Gateway..."
    
    # Attach Production VPC
    export PROD_ATTACHMENT_ID=$(aws ec2 create-transit-gateway-vpc-attachment \
        --transit-gateway-id $TGW_ID \
        --vpc-id $PROD_VPC_ID \
        --subnet-ids $PROD_SUBNET_ID \
        --tag-specifications "ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=prod-attachment},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)
    echo "PROD_ATTACHMENT_ID=${PROD_ATTACHMENT_ID}" >> /tmp/deployment_vars.env
    
    # Attach Development VPC
    export DEV_ATTACHMENT_ID=$(aws ec2 create-transit-gateway-vpc-attachment \
        --transit-gateway-id $TGW_ID \
        --vpc-id $DEV_VPC_ID \
        --subnet-ids $DEV_SUBNET_ID \
        --tag-specifications "ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=dev-attachment},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)
    echo "DEV_ATTACHMENT_ID=${DEV_ATTACHMENT_ID}" >> /tmp/deployment_vars.env
    
    # Attach Test VPC
    export TEST_ATTACHMENT_ID=$(aws ec2 create-transit-gateway-vpc-attachment \
        --transit-gateway-id $TGW_ID \
        --vpc-id $TEST_VPC_ID \
        --subnet-ids $TEST_SUBNET_ID \
        --tag-specifications "ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=test-attachment},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)
    echo "TEST_ATTACHMENT_ID=${TEST_ATTACHMENT_ID}" >> /tmp/deployment_vars.env
    
    # Attach Shared Services VPC
    export SHARED_ATTACHMENT_ID=$(aws ec2 create-transit-gateway-vpc-attachment \
        --transit-gateway-id $TGW_ID \
        --vpc-id $SHARED_VPC_ID \
        --subnet-ids $SHARED_SUBNET_ID \
        --tag-specifications "ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=shared-attachment},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)
    echo "SHARED_ATTACHMENT_ID=${SHARED_ATTACHMENT_ID}" >> /tmp/deployment_vars.env
    
    log "Waiting for all attachments to become available..."
    for attachment_id in $PROD_ATTACHMENT_ID $DEV_ATTACHMENT_ID $TEST_ATTACHMENT_ID $SHARED_ATTACHMENT_ID; do
        aws ec2 wait transit-gateway-attachment-available --transit-gateway-attachment-ids $attachment_id
    done
    
    log_success "Created VPC attachments to Transit Gateway"
}

# Configure route table associations
configure_route_associations() {
    log "Configuring route table associations..."
    
    # Associate Production VPC with Production Route Table
    aws ec2 associate-transit-gateway-route-table \
        --transit-gateway-attachment-id $PROD_ATTACHMENT_ID \
        --transit-gateway-route-table-id $PROD_RT_ID
    
    # Associate Development VPC with Development Route Table
    aws ec2 associate-transit-gateway-route-table \
        --transit-gateway-attachment-id $DEV_ATTACHMENT_ID \
        --transit-gateway-route-table-id $DEV_RT_ID
    
    # Associate Test VPC with Development Route Table
    aws ec2 associate-transit-gateway-route-table \
        --transit-gateway-attachment-id $TEST_ATTACHMENT_ID \
        --transit-gateway-route-table-id $DEV_RT_ID
    
    # Associate Shared Services VPC with Shared Route Table
    aws ec2 associate-transit-gateway-route-table \
        --transit-gateway-attachment-id $SHARED_ATTACHMENT_ID \
        --transit-gateway-route-table-id $SHARED_RT_ID
    
    log_success "Configured route table associations for network segmentation"
}

# Configure route propagation
configure_route_propagation() {
    log "Configuring route propagation for controlled access..."
    
    # Enable Production to access Shared Services
    aws ec2 enable-transit-gateway-route-table-propagation \
        --transit-gateway-route-table-id $PROD_RT_ID \
        --transit-gateway-attachment-id $SHARED_ATTACHMENT_ID
    
    # Enable Development/Test to access Shared Services
    aws ec2 enable-transit-gateway-route-table-propagation \
        --transit-gateway-route-table-id $DEV_RT_ID \
        --transit-gateway-attachment-id $SHARED_ATTACHMENT_ID
    
    # Enable Shared Services to access all environments
    aws ec2 enable-transit-gateway-route-table-propagation \
        --transit-gateway-route-table-id $SHARED_RT_ID \
        --transit-gateway-attachment-id $PROD_ATTACHMENT_ID
    
    aws ec2 enable-transit-gateway-route-table-propagation \
        --transit-gateway-route-table-id $SHARED_RT_ID \
        --transit-gateway-attachment-id $DEV_ATTACHMENT_ID
    
    aws ec2 enable-transit-gateway-route-table-propagation \
        --transit-gateway-route-table-id $SHARED_RT_ID \
        --transit-gateway-attachment-id $TEST_ATTACHMENT_ID
    
    log_success "Configured route propagation for controlled access patterns"
}

# Create static routes
create_static_routes() {
    log "Creating static routes for specific network policies..."
    
    # Create blackhole route to block direct Dev-to-Prod communication
    aws ec2 create-transit-gateway-route \
        --destination-cidr-block 10.0.0.0/16 \
        --transit-gateway-route-table-id $DEV_RT_ID \
        --blackhole || log_warning "Blackhole route may already exist"
    
    # Create specific routes for shared services access
    aws ec2 create-transit-gateway-route \
        --destination-cidr-block 10.3.0.0/16 \
        --transit-gateway-route-table-id $PROD_RT_ID \
        --transit-gateway-attachment-id $SHARED_ATTACHMENT_ID || log_warning "Route may already exist"
    
    aws ec2 create-transit-gateway-route \
        --destination-cidr-block 10.3.0.0/16 \
        --transit-gateway-route-table-id $DEV_RT_ID \
        --transit-gateway-attachment-id $SHARED_ATTACHMENT_ID || log_warning "Route may already exist"
    
    log_success "Created static routes for specific network policies"
}

# Configure monitoring
configure_monitoring() {
    log "Configuring network monitoring and logging..."
    
    # Create CloudWatch Log Group for Transit Gateway monitoring
    aws logs create-log-group \
        --log-group-name /aws/transitgateway/flowlogs || log_warning "Log group may already exist"
    
    # Create CloudWatch alarm for monitoring Transit Gateway data processing
    aws cloudwatch put-metric-alarm \
        --alarm-name "TransitGateway-DataProcessing-High-${RANDOM_SUFFIX}" \
        --alarm-description "High data processing on Transit Gateway" \
        --metric-name BytesIn \
        --namespace AWS/TransitGateway \
        --statistic Sum \
        --period 300 \
        --threshold 10000000000 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=TransitGateway,Value=$TGW_ID || log_warning "Alarm may already exist"
    
    echo "ALARM_NAME=TransitGateway-DataProcessing-High-${RANDOM_SUFFIX}" >> /tmp/deployment_vars.env
    
    log_success "Configured network monitoring and logging"
}

# Update VPC route tables
update_vpc_route_tables() {
    log "Updating VPC route tables to use Transit Gateway..."
    
    # Get default route table IDs for each VPC
    export PROD_RT_VPC_ID=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$PROD_VPC_ID" \
        --query 'RouteTables[0].RouteTableId' --output text)
    
    export DEV_RT_VPC_ID=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$DEV_VPC_ID" \
        --query 'RouteTables[0].RouteTableId' --output text)
    
    export TEST_RT_VPC_ID=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$TEST_VPC_ID" \
        --query 'RouteTables[0].RouteTableId' --output text)
    
    export SHARED_RT_VPC_ID=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$SHARED_VPC_ID" \
        --query 'RouteTables[0].RouteTableId' --output text)
    
    # Add routes to Transit Gateway from each VPC
    aws ec2 create-route \
        --route-table-id $PROD_RT_VPC_ID \
        --destination-cidr-block 10.3.0.0/16 \
        --transit-gateway-id $TGW_ID || log_warning "Route may already exist"
    
    aws ec2 create-route \
        --route-table-id $DEV_RT_VPC_ID \
        --destination-cidr-block 10.3.0.0/16 \
        --transit-gateway-id $TGW_ID || log_warning "Route may already exist"
    
    aws ec2 create-route \
        --route-table-id $TEST_RT_VPC_ID \
        --destination-cidr-block 10.3.0.0/16 \
        --transit-gateway-id $TGW_ID || log_warning "Route may already exist"
    
    aws ec2 create-route \
        --route-table-id $SHARED_RT_VPC_ID \
        --destination-cidr-block 10.0.0.0/8 \
        --transit-gateway-id $TGW_ID || log_warning "Route may already exist"
    
    log_success "Updated VPC route tables to use Transit Gateway"
}

# Create security groups
create_security_groups() {
    log "Creating security groups for Transit Gateway traffic control..."
    
    # Create security group for production environment
    export PROD_SG_ID=$(aws ec2 create-security-group \
        --group-name "prod-tgw-sg-${RANDOM_SUFFIX}" \
        --description "Security group for production Transit Gateway traffic" \
        --vpc-id $PROD_VPC_ID \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=prod-tgw-sg},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'GroupId' --output text)
    echo "PROD_SG_ID=${PROD_SG_ID}" >> /tmp/deployment_vars.env
    
    # Add ingress rules for shared services access
    aws ec2 authorize-security-group-ingress \
        --group-id $PROD_SG_ID \
        --protocol tcp \
        --port 443 \
        --source-group $PROD_SG_ID || log_warning "Rule may already exist"
    
    aws ec2 authorize-security-group-ingress \
        --group-id $PROD_SG_ID \
        --protocol tcp \
        --port 53 \
        --cidr 10.3.0.0/16 || log_warning "Rule may already exist"
    
    aws ec2 authorize-security-group-ingress \
        --group-id $PROD_SG_ID \
        --protocol udp \
        --port 53 \
        --cidr 10.3.0.0/16 || log_warning "Rule may already exist"
    
    # Create security group for development environment
    export DEV_SG_ID=$(aws ec2 create-security-group \
        --group-name "dev-tgw-sg-${RANDOM_SUFFIX}" \
        --description "Security group for development Transit Gateway traffic" \
        --vpc-id $DEV_VPC_ID \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=dev-tgw-sg},{Key=DeploymentId,Value=${RANDOM_SUFFIX}}]" \
        --query 'GroupId' --output text)
    echo "DEV_SG_ID=${DEV_SG_ID}" >> /tmp/deployment_vars.env
    
    # Add ingress rules for development inter-VPC communication
    aws ec2 authorize-security-group-ingress \
        --group-id $DEV_SG_ID \
        --protocol tcp \
        --port 80 \
        --cidr 10.1.0.0/16 || log_warning "Rule may already exist"
    
    aws ec2 authorize-security-group-ingress \
        --group-id $DEV_SG_ID \
        --protocol tcp \
        --port 443 \
        --cidr 10.1.0.0/16 || log_warning "Rule may already exist"
    
    aws ec2 authorize-security-group-ingress \
        --group-id $DEV_SG_ID \
        --protocol tcp \
        --port 22 \
        --cidr 10.2.0.0/16 || log_warning "Rule may already exist"
    
    log_success "Created security groups for Transit Gateway traffic control"
}

# Validation function
validate_deployment() {
    log "Validating deployment..."
    
    # Check Transit Gateway status
    TGW_STATE=$(aws ec2 describe-transit-gateways \
        --transit-gateway-ids $TGW_ID \
        --query 'TransitGateways[0].State' --output text)
    
    if [[ "$TGW_STATE" == "available" ]]; then
        log_success "Transit Gateway is available"
    else
        log_error "Transit Gateway is not available. Current state: $TGW_STATE"
        return 1
    fi
    
    # Verify all VPC attachments are available
    ATTACHMENT_COUNT=$(aws ec2 describe-transit-gateway-vpc-attachments \
        --transit-gateway-attachment-ids $PROD_ATTACHMENT_ID $DEV_ATTACHMENT_ID $TEST_ATTACHMENT_ID $SHARED_ATTACHMENT_ID \
        --query 'length(TransitGatewayVpcAttachments[?State==`available`])' --output text)
    
    if [[ "$ATTACHMENT_COUNT" == "4" ]]; then
        log_success "All VPC attachments are available"
    else
        log_error "Not all VPC attachments are available. Available count: $ATTACHMENT_COUNT"
        return 1
    fi
    
    # Check route table associations
    PROD_ASSOC=$(aws ec2 get-transit-gateway-route-table-associations \
        --transit-gateway-route-table-id $PROD_RT_ID \
        --query 'length(Associations[?State==`associated`])' --output text)
    
    if [[ "$PROD_ASSOC" == "1" ]]; then
        log_success "Production route table associations are correct"
    else
        log_error "Production route table associations are incorrect"
        return 1
    fi
    
    log_success "Deployment validation completed successfully"
}

# Generate summary
generate_summary() {
    log "Generating deployment summary..."
    
    cat > /tmp/deployment_summary.txt << EOF
=== Multi-VPC Transit Gateway Deployment Summary ===

Deployment ID: ${RANDOM_SUFFIX}
AWS Region: ${AWS_REGION}
AWS Account ID: ${AWS_ACCOUNT_ID}

Resources Created:
==================

Transit Gateway:
- ID: ${TGW_ID}
- Name: ${TGW_NAME}

VPCs:
- Production VPC: ${PROD_VPC_ID} (10.0.0.0/16)
- Development VPC: ${DEV_VPC_ID} (10.1.0.0/16)
- Test VPC: ${TEST_VPC_ID} (10.2.0.0/16)
- Shared Services VPC: ${SHARED_VPC_ID} (10.3.0.0/16)

Subnets:
- Production Subnet: ${PROD_SUBNET_ID} (10.0.1.0/24)
- Development Subnet: ${DEV_SUBNET_ID} (10.1.1.0/24)
- Test Subnet: ${TEST_SUBNET_ID} (10.2.1.0/24)
- Shared Services Subnet: ${SHARED_SUBNET_ID} (10.3.1.0/24)

Transit Gateway Route Tables:
- Production Route Table: ${PROD_RT_ID}
- Development Route Table: ${DEV_RT_ID}
- Shared Services Route Table: ${SHARED_RT_ID}

VPC Attachments:
- Production Attachment: ${PROD_ATTACHMENT_ID}
- Development Attachment: ${DEV_ATTACHMENT_ID}
- Test Attachment: ${TEST_ATTACHMENT_ID}
- Shared Services Attachment: ${SHARED_ATTACHMENT_ID}

Security Groups:
- Production Security Group: ${PROD_SG_ID}
- Development Security Group: ${DEV_SG_ID}

Monitoring:
- CloudWatch Alarm: TransitGateway-DataProcessing-High-${RANDOM_SUFFIX}
- Log Group: /aws/transitgateway/flowlogs

Network Segmentation:
=====================
- Production environment isolated from Development/Test
- All environments can access Shared Services
- Shared Services can access all environments
- Blackhole route prevents direct Dev-to-Prod communication

Cost Estimation:
===============
- Transit Gateway: ~$36/month
- VPC Attachments: ~$36/month (4 attachments × $0.05/hour)
- Data Processing: Variable based on usage (~$0.02/GB)
- Estimated Total: $75-150/month depending on data transfer

Next Steps:
===========
1. Deploy applications in respective VPCs
2. Configure shared services (DNS, monitoring, security)
3. Set up cross-region peering if needed
4. Implement additional security controls
5. Monitor costs and optimize as needed

To clean up this deployment, run: ./destroy.sh

EOF
    
    log_success "Deployment completed successfully!"
    log ""
    log "Summary saved to: /tmp/deployment_summary.txt"
    log "Environment variables saved to: /tmp/deployment_vars.env"
    log ""
    cat /tmp/deployment_summary.txt
}

# Main execution
main() {
    log "Starting Multi-VPC Transit Gateway deployment..."
    log "==============================================="
    
    check_prerequisites
    setup_environment
    create_vpcs
    create_subnets
    create_transit_gateway
    create_route_tables
    create_vpc_attachments
    configure_route_associations
    configure_route_propagation
    create_static_routes
    configure_monitoring
    update_vpc_route_tables
    create_security_groups
    validate_deployment
    generate_summary
    
    log_success "Multi-VPC Transit Gateway deployment completed successfully!"
}

# Run main function
main "$@"