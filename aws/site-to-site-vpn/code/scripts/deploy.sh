#!/bin/bash

# =============================================================================
# AWS Site-to-Site VPN Deployment Script
# =============================================================================
# This script deploys a complete AWS Site-to-Site VPN infrastructure
# including VPC, subnets, gateways, VPN connection, and monitoring
# =============================================================================

set -e
set -o pipefail

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS CLI configuration
validate_aws_cli() {
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    log "AWS CLI validation successful"
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    validate_aws_cli
    
    # Check required environment variables
    if [ -z "$CGW_PUBLIC_IP" ]; then
        warn "CGW_PUBLIC_IP not set. Using default example IP (203.0.113.12)"
        export CGW_PUBLIC_IP="203.0.113.12"
    fi
    
    if [ -z "$CGW_BGP_ASN" ]; then
        warn "CGW_BGP_ASN not set. Using default ASN (65000)"
        export CGW_BGP_ASN="65000"
    fi
    
    if [ -z "$AWS_BGP_ASN" ]; then
        warn "AWS_BGP_ASN not set. Using default ASN (64512)"
        export AWS_BGP_ASN="64512"
    fi
    
    log "Prerequisites validation complete"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "AWS region not configured. Using default: ${AWS_REGION}"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifier
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export VPC_NAME="vpn-demo-vpc-${RANDOM_SUFFIX}"
    export VGW_NAME="vpn-demo-vgw-${RANDOM_SUFFIX}"
    export CGW_NAME="vpn-demo-cgw-${RANDOM_SUFFIX}"
    export VPN_NAME="vpn-demo-connection-${RANDOM_SUFFIX}"
    export SG_NAME="${VPC_NAME}-vpn-sg"
    export DASHBOARD_NAME="VPN-Monitoring-${RANDOM_SUFFIX}"
    
    # Create state file to store resource IDs
    STATE_FILE="/tmp/vpn-deployment-state-${RANDOM_SUFFIX}.json"
    export STATE_FILE
    
    # Initialize state file
    cat > "$STATE_FILE" << EOF
{
    "deployment_id": "${RANDOM_SUFFIX}",
    "aws_region": "${AWS_REGION}",
    "vpc_name": "${VPC_NAME}",
    "cgw_public_ip": "${CGW_PUBLIC_IP}",
    "cgw_bgp_asn": "${CGW_BGP_ASN}",
    "aws_bgp_asn": "${AWS_BGP_ASN}",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log "Environment setup complete"
    info "Deployment ID: ${RANDOM_SUFFIX}"
    info "AWS Region: ${AWS_REGION}"
    info "VPC Name: ${VPC_NAME}"
    info "Customer Gateway IP: ${CGW_PUBLIC_IP}"
    info "State file: ${STATE_FILE}"
}

# Function to create VPC
create_vpc() {
    log "Creating VPC and networking infrastructure..."
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --region "$AWS_REGION" \
        --cidr-block 172.31.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}},{Key=Project,Value=vpn-demo},{Key=Environment,Value=development}]" \
        --query 'Vpc.VpcId' --output text)
    
    if [ $? -eq 0 ]; then
        log "VPC created successfully: ${VPC_ID}"
        # Update state file
        jq --arg vpc_id "$VPC_ID" '.vpc_id = $vpc_id' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    else
        error "Failed to create VPC"
    fi
    
    # Create Internet Gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
        --region "$AWS_REGION" \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw},{Key=Project,Value=vpn-demo}]" \
        --query 'InternetGateway.InternetGatewayId' --output text)
    
    if [ $? -eq 0 ]; then
        log "Internet Gateway created: ${IGW_ID}"
        jq --arg igw_id "$IGW_ID" '.igw_id = $igw_id' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    else
        error "Failed to create Internet Gateway"
    fi
    
    # Attach Internet Gateway to VPC
    aws ec2 attach-internet-gateway \
        --region "$AWS_REGION" \
        --internet-gateway-id "$IGW_ID" \
        --vpc-id "$VPC_ID"
    
    if [ $? -eq 0 ]; then
        log "Internet Gateway attached to VPC"
    else
        error "Failed to attach Internet Gateway to VPC"
    fi
}

# Function to create subnets
create_subnets() {
    log "Creating subnets and route tables..."
    
    # Create public subnet
    PUB_SUBNET_ID=$(aws ec2 create-subnet \
        --region "$AWS_REGION" \
        --vpc-id "$VPC_ID" \
        --cidr-block 172.31.0.0/20 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-public},{Key=Project,Value=vpn-demo}]" \
        --query 'Subnet.SubnetId' --output text)
    
    if [ $? -eq 0 ]; then
        log "Public subnet created: ${PUB_SUBNET_ID}"
        jq --arg pub_subnet_id "$PUB_SUBNET_ID" '.pub_subnet_id = $pub_subnet_id' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    else
        error "Failed to create public subnet"
    fi
    
    # Create private subnet
    PRIV_SUBNET_ID=$(aws ec2 create-subnet \
        --region "$AWS_REGION" \
        --vpc-id "$VPC_ID" \
        --cidr-block 172.31.16.0/20 \
        --availability-zone "${AWS_REGION}b" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-private},{Key=Project,Value=vpn-demo}]" \
        --query 'Subnet.SubnetId' --output text)
    
    if [ $? -eq 0 ]; then
        log "Private subnet created: ${PRIV_SUBNET_ID}"
        jq --arg priv_subnet_id "$PRIV_SUBNET_ID" '.priv_subnet_id = $priv_subnet_id' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    else
        error "Failed to create private subnet"
    fi
    
    # Create custom route table for VPN routes
    VPN_RT_ID=$(aws ec2 create-route-table \
        --region "$AWS_REGION" \
        --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-vpn-rt},{Key=Project,Value=vpn-demo}]" \
        --query 'RouteTable.RouteTableId' --output text)
    
    if [ $? -eq 0 ]; then
        log "VPN route table created: ${VPN_RT_ID}"
        jq --arg vpn_rt_id "$VPN_RT_ID" '.vpn_rt_id = $vpn_rt_id' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    else
        error "Failed to create VPN route table"
    fi
    
    # Associate private subnet with VPN route table
    aws ec2 associate-route-table \
        --region "$AWS_REGION" \
        --route-table-id "$VPN_RT_ID" \
        --subnet-id "$PRIV_SUBNET_ID" > /dev/null
    
    if [ $? -eq 0 ]; then
        log "Private subnet associated with VPN route table"
    else
        error "Failed to associate private subnet with VPN route table"
    fi
}

# Function to create Customer Gateway
create_customer_gateway() {
    log "Creating Customer Gateway..."
    
    CGW_ID=$(aws ec2 create-customer-gateway \
        --region "$AWS_REGION" \
        --type ipsec.1 \
        --public-ip "$CGW_PUBLIC_IP" \
        --bgp-asn "$CGW_BGP_ASN" \
        --tag-specifications "ResourceType=customer-gateway,Tags=[{Key=Name,Value=${CGW_NAME}},{Key=Project,Value=vpn-demo}]" \
        --query 'CustomerGateway.CustomerGatewayId' --output text)
    
    if [ $? -eq 0 ]; then
        log "Customer Gateway created: ${CGW_ID}"
        jq --arg cgw_id "$CGW_ID" '.cgw_id = $cgw_id' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        
        # Wait for customer gateway to be available
        info "Waiting for Customer Gateway to be available..."
        aws ec2 wait customer-gateway-available \
            --region "$AWS_REGION" \
            --customer-gateway-ids "$CGW_ID"
        
        if [ $? -eq 0 ]; then
            log "Customer Gateway is now available"
        else
            warn "Customer Gateway wait timed out, but continuing..."
        fi
    else
        error "Failed to create Customer Gateway"
    fi
}

# Function to create Virtual Private Gateway
create_vpn_gateway() {
    log "Creating Virtual Private Gateway..."
    
    VGW_ID=$(aws ec2 create-vpn-gateway \
        --region "$AWS_REGION" \
        --type ipsec.1 \
        --amazon-side-asn "$AWS_BGP_ASN" \
        --tag-specifications "ResourceType=vpn-gateway,Tags=[{Key=Name,Value=${VGW_NAME}},{Key=Project,Value=vpn-demo}]" \
        --query 'VpnGateway.VpnGatewayId' --output text)
    
    if [ $? -eq 0 ]; then
        log "Virtual Private Gateway created: ${VGW_ID}"
        jq --arg vgw_id "$VGW_ID" '.vgw_id = $vgw_id' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        
        # Wait for VPN gateway to be available
        info "Waiting for VPN Gateway to be available..."
        aws ec2 wait vpn-gateway-available \
            --region "$AWS_REGION" \
            --vpn-gateway-ids "$VGW_ID"
        
        if [ $? -eq 0 ]; then
            log "VPN Gateway is now available"
        else
            warn "VPN Gateway wait timed out, but continuing..."
        fi
        
        # Attach VPN gateway to VPC
        aws ec2 attach-vpn-gateway \
            --region "$AWS_REGION" \
            --vpn-gateway-id "$VGW_ID" \
            --vpc-id "$VPC_ID" > /dev/null
        
        if [ $? -eq 0 ]; then
            log "VPN Gateway attached to VPC"
        else
            error "Failed to attach VPN Gateway to VPC"
        fi
    else
        error "Failed to create Virtual Private Gateway"
    fi
}

# Function to create VPN connection
create_vpn_connection() {
    log "Creating Site-to-Site VPN connection..."
    
    VPN_ID=$(aws ec2 create-vpn-connection \
        --region "$AWS_REGION" \
        --type ipsec.1 \
        --customer-gateway-id "$CGW_ID" \
        --vpn-gateway-id "$VGW_ID" \
        --tag-specifications "ResourceType=vpn-connection,Tags=[{Key=Name,Value=${VPN_NAME}},{Key=Project,Value=vpn-demo}]" \
        --query 'VpnConnection.VpnConnectionId' --output text)
    
    if [ $? -eq 0 ]; then
        log "VPN Connection created: ${VPN_ID}"
        jq --arg vpn_id "$VPN_ID" '.vpn_id = $vpn_id' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        
        # Wait for VPN connection to be available
        info "Waiting for VPN connection to be available (this may take 5-10 minutes)..."
        aws ec2 wait vpn-connection-available \
            --region "$AWS_REGION" \
            --vpn-connection-ids "$VPN_ID"
        
        if [ $? -eq 0 ]; then
            log "VPN Connection is now available"
        else
            warn "VPN Connection wait timed out, but continuing..."
        fi
    else
        error "Failed to create VPN Connection"
    fi
}

# Function to configure routing
configure_routing() {
    log "Configuring route propagation..."
    
    # Enable route propagation from VPN gateway to route table
    aws ec2 enable-vgw-route-propagation \
        --region "$AWS_REGION" \
        --route-table-id "$VPN_RT_ID" \
        --gateway-id "$VGW_ID"
    
    if [ $? -eq 0 ]; then
        log "Route propagation enabled for VPN gateway"
    else
        error "Failed to enable route propagation"
    fi
    
    # Get main route table ID
    MAIN_RT_ID=$(aws ec2 describe-route-tables \
        --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
            "Name=association.main,Values=true" \
        --query 'RouteTables[0].RouteTableId' --output text)
    
    if [ "$MAIN_RT_ID" != "None" ] && [ -n "$MAIN_RT_ID" ]; then
        jq --arg main_rt_id "$MAIN_RT_ID" '.main_rt_id = $main_rt_id' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        
        # Add route to internet gateway in main route table
        aws ec2 create-route \
            --region "$AWS_REGION" \
            --route-table-id "$MAIN_RT_ID" \
            --destination-cidr-block 0.0.0.0/0 \
            --gateway-id "$IGW_ID" > /dev/null
        
        if [ $? -eq 0 ]; then
            log "Internet route added to main route table"
        else
            warn "Failed to add internet route (may already exist)"
        fi
    else
        warn "Could not find main route table"
    fi
}

# Function to create security group
create_security_group() {
    log "Creating security group for VPN access..."
    
    SG_ID=$(aws ec2 create-security-group \
        --region "$AWS_REGION" \
        --group-name "$SG_NAME" \
        --description "Security group for VPN testing" \
        --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${SG_NAME}},{Key=Project,Value=vpn-demo}]" \
        --query 'GroupId' --output text)
    
    if [ $? -eq 0 ]; then
        log "Security group created: ${SG_ID}"
        jq --arg sg_id "$SG_ID" '.sg_id = $sg_id' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        
        # Allow SSH from on-premises network
        aws ec2 authorize-security-group-ingress \
            --region "$AWS_REGION" \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 22 \
            --cidr 10.0.0.0/16 > /dev/null
        
        # Allow ICMP from on-premises network
        aws ec2 authorize-security-group-ingress \
            --region "$AWS_REGION" \
            --group-id "$SG_ID" \
            --protocol icmp \
            --port -1 \
            --cidr 10.0.0.0/16 > /dev/null
        
        # Allow all traffic from VPC
        aws ec2 authorize-security-group-ingress \
            --region "$AWS_REGION" \
            --group-id "$SG_ID" \
            --protocol -1 \
            --source-group "$SG_ID" > /dev/null
        
        log "Security group rules configured"
    else
        error "Failed to create security group"
    fi
}

# Function to create test instance
create_test_instance() {
    log "Creating test EC2 instance..."
    
    # Get Amazon Linux 2 AMI ID
    AMI_ID=$(aws ec2 describe-images \
        --region "$AWS_REGION" \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
            "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    if [ -z "$AMI_ID" ] || [ "$AMI_ID" == "None" ]; then
        warn "Could not find Amazon Linux 2 AMI, skipping test instance creation"
        return
    fi
    
    # Launch EC2 instance
    INSTANCE_ID=$(aws ec2 run-instances \
        --region "$AWS_REGION" \
        --image-id "$AMI_ID" \
        --instance-type t3.micro \
        --subnet-id "$PRIV_SUBNET_ID" \
        --security-group-ids "$SG_ID" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${VPC_NAME}-test-instance},{Key=Project,Value=vpn-demo}]" \
        --query 'Instances[0].InstanceId' --output text)
    
    if [ $? -eq 0 ]; then
        log "Test instance launched: ${INSTANCE_ID}"
        jq --arg instance_id "$INSTANCE_ID" '.instance_id = $instance_id' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        
        # Wait for instance to be running
        info "Waiting for test instance to be running..."
        aws ec2 wait instance-running \
            --region "$AWS_REGION" \
            --instance-ids "$INSTANCE_ID"
        
        if [ $? -eq 0 ]; then
            log "Test instance is now running"
            
            # Get instance private IP
            INSTANCE_IP=$(aws ec2 describe-instances \
                --region "$AWS_REGION" \
                --instance-ids "$INSTANCE_ID" \
                --query 'Reservations[0].Instances[0].PrivateIpAddress' \
                --output text)
            
            if [ -n "$INSTANCE_IP" ] && [ "$INSTANCE_IP" != "None" ]; then
                log "Test instance private IP: ${INSTANCE_IP}"
                jq --arg instance_ip "$INSTANCE_IP" '.instance_ip = $instance_ip' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
            fi
        else
            warn "Test instance wait timed out"
        fi
    else
        warn "Failed to create test instance"
    fi
}

# Function to create CloudWatch dashboard
create_monitoring() {
    log "Setting up CloudWatch monitoring..."
    
    # Create dashboard configuration
    cat > /tmp/dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "AWS/VPN", "VpnState", "VpnId", "${VPN_ID}" ],
                    [ ".", "VpnTunnelState", ".", "." ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "VPN Connection Status"
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "AWS/VPN", "VpnPacketsReceived", "VpnId", "${VPN_ID}" ],
                    [ ".", "VpnPacketsSent", ".", "." ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "VPN Traffic"
            }
        }
    ]
}
EOF
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --region "$AWS_REGION" \
        --dashboard-name "$DASHBOARD_NAME" \
        --dashboard-body file:///tmp/dashboard-config.json > /dev/null
    
    if [ $? -eq 0 ]; then
        log "CloudWatch dashboard created: ${DASHBOARD_NAME}"
        jq --arg dashboard_name "$DASHBOARD_NAME" '.dashboard_name = $dashboard_name' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    else
        warn "Failed to create CloudWatch dashboard"
    fi
    
    # Clean up temporary file
    rm -f /tmp/dashboard-config.json
}

# Function to download VPN configuration
download_vpn_config() {
    log "Downloading VPN configuration..."
    
    # Download customer gateway configuration
    aws ec2 describe-vpn-connections \
        --region "$AWS_REGION" \
        --vpn-connection-ids "$VPN_ID" \
        --query 'VpnConnections[0].CustomerGatewayConfiguration' \
        --output text > vpn-config.txt
    
    if [ $? -eq 0 ]; then
        log "VPN configuration downloaded to vpn-config.txt"
        info "Review this file to configure your on-premises VPN device"
    else
        warn "Failed to download VPN configuration"
    fi
    
    # Show tunnel status
    info "VPN Tunnel Status:"
    aws ec2 describe-vpn-connections \
        --region "$AWS_REGION" \
        --vpn-connection-ids "$VPN_ID" \
        --query 'VpnConnections[0].VgwTelemetry' \
        --output table
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Deployment ID: $(jq -r '.deployment_id' "$STATE_FILE")"
    echo "AWS Region: $(jq -r '.aws_region' "$STATE_FILE")"
    echo "VPC ID: $(jq -r '.vpc_id' "$STATE_FILE")"
    echo "VPN Connection ID: $(jq -r '.vpn_id' "$STATE_FILE")"
    echo "Customer Gateway ID: $(jq -r '.cgw_id' "$STATE_FILE")"
    echo "Virtual Private Gateway ID: $(jq -r '.vgw_id' "$STATE_FILE")"
    echo "Security Group ID: $(jq -r '.sg_id' "$STATE_FILE")"
    
    if [ "$(jq -r '.instance_id' "$STATE_FILE")" != "null" ]; then
        echo "Test Instance ID: $(jq -r '.instance_id' "$STATE_FILE")"
        echo "Test Instance IP: $(jq -r '.instance_ip' "$STATE_FILE")"
    fi
    
    echo "CloudWatch Dashboard: $(jq -r '.dashboard_name' "$STATE_FILE")"
    echo "State File: $STATE_FILE"
    echo ""
    echo "Next Steps:"
    echo "1. Configure your on-premises VPN device using vpn-config.txt"
    echo "2. Test connectivity from your on-premises network"
    echo "3. Monitor VPN status in CloudWatch dashboard"
    echo "4. Run destroy.sh to clean up resources when done"
}

# Main execution
main() {
    log "Starting AWS Site-to-Site VPN deployment..."
    
    # Check if jq is installed
    if ! command_exists jq; then
        error "jq is required but not installed. Please install jq first."
    fi
    
    validate_prerequisites
    setup_environment
    
    # Create infrastructure
    create_vpc
    create_subnets
    create_customer_gateway
    create_vpn_gateway
    create_vpn_connection
    configure_routing
    create_security_group
    create_test_instance
    create_monitoring
    download_vpn_config
    
    # Mark deployment as complete
    jq --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.completed_at = $completed_at' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    
    log "Deployment completed successfully!"
    display_summary
}

# Run main function
main "$@"