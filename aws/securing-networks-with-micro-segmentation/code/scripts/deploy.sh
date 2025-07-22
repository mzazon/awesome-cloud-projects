#!/bin/bash

# Deployment script for Network Micro-Segmentation with NACLs and Advanced Security Groups
# This script implements a comprehensive micro-segmentation strategy using NACLs and security groups

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/microseg-deploy-$(date +%Y%m%d-%H%M%S).log"
TEMP_DIR="/tmp/microseg-deploy-$$"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${2:-$NC}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1" "$RED"
    cleanup_on_failure
    exit 1
}

# Success message
success() {
    log "SUCCESS: $1" "$GREEN"
}

# Warning message
warn() {
    log "WARNING: $1" "$YELLOW"
}

# Info message
info() {
    log "INFO: $1" "$BLUE"
}

# Cleanup function for failed deployments
cleanup_on_failure() {
    warn "Deployment failed. Attempting cleanup of partially created resources..."
    
    # Clean up temporary files
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    
    # If VPC_ID exists, attempt to clean up
    if [[ -n "${VPC_ID:-}" ]]; then
        warn "Attempting to clean up VPC resources..."
        ./destroy.sh --force 2>/dev/null || true
    fi
}

# Prerequisites check
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check required permissions
    info "Verifying AWS permissions..."
    
    # Test VPC permissions
    if ! aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text &>/dev/null; then
        error_exit "Insufficient permissions to manage VPC resources."
    fi
    
    # Test IAM permissions for Flow Logs
    if ! aws iam list-roles --query 'Roles[0].RoleName' --output text &>/dev/null; then
        error_exit "Insufficient permissions to manage IAM resources."
    fi
    
    # Test CloudWatch permissions
    if ! aws logs describe-log-groups --limit 1 &>/dev/null; then
        error_exit "Insufficient permissions to manage CloudWatch resources."
    fi
    
    success "Prerequisites check passed"
}

# Create temporary directory
create_temp_dir() {
    mkdir -p "$TEMP_DIR"
    info "Created temporary directory: $TEMP_DIR"
}

# Set environment variables
set_environment_variables() {
    info "Setting environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warn "No AWS region configured, using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export VPC_NAME="microseg-vpc-${RANDOM_SUFFIX}"
    export KEY_PAIR_NAME="microseg-key-${RANDOM_SUFFIX}"
    
    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "Resource suffix: $RANDOM_SUFFIX"
    
    # Store variables for cleanup
    cat > "$TEMP_DIR/environment.sh" << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export VPC_NAME="$VPC_NAME"
export KEY_PAIR_NAME="$KEY_PAIR_NAME"
EOF
}

# Create VPC infrastructure
create_vpc_infrastructure() {
    info "Creating VPC infrastructure..."
    
    # Create VPC
    aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}},{Key=Environment,Value=production},{Key=Purpose,Value=microsegmentation}]" \
        --query 'Vpc.VpcId' --output text > "$TEMP_DIR/vpc-id"
    
    export VPC_ID=$(cat "$TEMP_DIR/vpc-id")
    info "Created VPC: $VPC_ID"
    
    # Enable DNS hostnames and resolution
    aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
    aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support
    
    # Create Internet Gateway
    aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw}]" \
        --query 'InternetGateway.InternetGatewayId' --output text > "$TEMP_DIR/igw-id"
    
    export IGW_ID=$(cat "$TEMP_DIR/igw-id")
    info "Created Internet Gateway: $IGW_ID"
    
    # Attach Internet Gateway to VPC
    aws ec2 attach-internet-gateway \
        --internet-gateway-id "$IGW_ID" \
        --vpc-id "$VPC_ID"
    
    # Create key pair for EC2 instances
    aws ec2 create-key-pair \
        --key-name "$KEY_PAIR_NAME" \
        --key-type rsa \
        --query 'KeyMaterial' --output text > "$TEMP_DIR/${KEY_PAIR_NAME}.pem"
    
    chmod 400 "$TEMP_DIR/${KEY_PAIR_NAME}.pem"
    info "Created key pair: $KEY_PAIR_NAME"
    
    # Update environment file
    cat >> "$TEMP_DIR/environment.sh" << EOF
export VPC_ID="$VPC_ID"
export IGW_ID="$IGW_ID"
EOF
    
    success "VPC infrastructure created successfully"
}

# Create security zone subnets
create_security_zone_subnets() {
    info "Creating subnets for each security zone..."
    
    local subnets=(
        "dmz:10.0.1.0/24:DMZ subnet (public-facing)"
        "web:10.0.2.0/24:Web Tier subnet"
        "app:10.0.3.0/24:Application Tier subnet"
        "db:10.0.4.0/24:Database Tier subnet"
        "mgmt:10.0.5.0/24:Management subnet"
        "mon:10.0.6.0/24:Monitoring subnet"
    )
    
    for subnet_config in "${subnets[@]}"; do
        IFS=':' read -r zone_name cidr_block description <<< "$subnet_config"
        
        info "Creating $description..."
        
        aws ec2 create-subnet \
            --vpc-id "$VPC_ID" \
            --cidr-block "$cidr_block" \
            --availability-zone "${AWS_REGION}a" \
            --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${zone_name}-subnet},{Key=Zone,Value=${zone_name}}]" \
            --query 'Subnet.SubnetId' --output text > "$TEMP_DIR/${zone_name}-subnet-id"
        
        local subnet_id=$(cat "$TEMP_DIR/${zone_name}-subnet-id")
        info "Created ${zone_name} subnet: $subnet_id"
        
        # Enable auto-assign public IP for DMZ subnet
        if [[ "$zone_name" == "dmz" ]]; then
            aws ec2 modify-subnet-attribute \
                --subnet-id "$subnet_id" \
                --map-public-ip-on-launch
        fi
    done
    
    # Export subnet IDs
    export DMZ_SUBNET_ID=$(cat "$TEMP_DIR/dmz-subnet-id")
    export WEB_SUBNET_ID=$(cat "$TEMP_DIR/web-subnet-id")
    export APP_SUBNET_ID=$(cat "$TEMP_DIR/app-subnet-id")
    export DB_SUBNET_ID=$(cat "$TEMP_DIR/db-subnet-id")
    export MGMT_SUBNET_ID=$(cat "$TEMP_DIR/mgmt-subnet-id")
    export MON_SUBNET_ID=$(cat "$TEMP_DIR/mon-subnet-id")
    
    # Update environment file
    cat >> "$TEMP_DIR/environment.sh" << EOF
export DMZ_SUBNET_ID="$DMZ_SUBNET_ID"
export WEB_SUBNET_ID="$WEB_SUBNET_ID"
export APP_SUBNET_ID="$APP_SUBNET_ID"
export DB_SUBNET_ID="$DB_SUBNET_ID"
export MGMT_SUBNET_ID="$MGMT_SUBNET_ID"
export MON_SUBNET_ID="$MON_SUBNET_ID"
EOF
    
    success "Security zone subnets created successfully"
}

# Create custom NACLs
create_custom_nacls() {
    info "Creating custom NACLs for subnet-level control..."
    
    local zones=("dmz" "web" "app" "db" "mgmt" "mon")
    
    for zone in "${zones[@]}"; do
        info "Creating $zone NACL..."
        
        aws ec2 create-network-acl \
            --vpc-id "$VPC_ID" \
            --tag-specifications "ResourceType=network-acl,Tags=[{Key=Name,Value=${zone}-nacl},{Key=Zone,Value=${zone}}]" \
            --query 'NetworkAcl.NetworkAclId' --output text > "$TEMP_DIR/${zone}-nacl-id"
        
        local nacl_id=$(cat "$TEMP_DIR/${zone}-nacl-id")
        info "Created $zone NACL: $nacl_id"
    done
    
    # Export NACL IDs
    export DMZ_NACL_ID=$(cat "$TEMP_DIR/dmz-nacl-id")
    export WEB_NACL_ID=$(cat "$TEMP_DIR/web-nacl-id")
    export APP_NACL_ID=$(cat "$TEMP_DIR/app-nacl-id")
    export DB_NACL_ID=$(cat "$TEMP_DIR/db-nacl-id")
    export MGMT_NACL_ID=$(cat "$TEMP_DIR/mgmt-nacl-id")
    export MON_NACL_ID=$(cat "$TEMP_DIR/mon-nacl-id")
    
    # Update environment file
    cat >> "$TEMP_DIR/environment.sh" << EOF
export DMZ_NACL_ID="$DMZ_NACL_ID"
export WEB_NACL_ID="$WEB_NACL_ID"
export APP_NACL_ID="$APP_NACL_ID"
export DB_NACL_ID="$DB_NACL_ID"
export MGMT_NACL_ID="$MGMT_NACL_ID"
export MON_NACL_ID="$MON_NACL_ID"
EOF
    
    success "Custom NACLs created successfully"
}

# Configure DMZ NACL rules
configure_dmz_nacl_rules() {
    info "Configuring DMZ NACL rules (Internet-facing zone)..."
    
    # DMZ Inbound Rules
    aws ec2 create-network-acl-entry \
        --network-acl-id "$DMZ_NACL_ID" \
        --rule-number 100 \
        --protocol tcp \
        --port-range From=80,To=80 \
        --cidr-block 0.0.0.0/0 \
        --rule-action allow
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$DMZ_NACL_ID" \
        --rule-number 110 \
        --protocol tcp \
        --port-range From=443,To=443 \
        --cidr-block 0.0.0.0/0 \
        --rule-action allow
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$DMZ_NACL_ID" \
        --rule-number 120 \
        --protocol tcp \
        --port-range From=1024,To=65535 \
        --cidr-block 0.0.0.0/0 \
        --rule-action allow
    
    # DMZ Outbound Rules
    aws ec2 create-network-acl-entry \
        --network-acl-id "$DMZ_NACL_ID" \
        --rule-number 100 \
        --protocol tcp \
        --port-range From=80,To=80 \
        --cidr-block 10.0.2.0/24 \
        --rule-action allow \
        --egress
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$DMZ_NACL_ID" \
        --rule-number 110 \
        --protocol tcp \
        --port-range From=443,To=443 \
        --cidr-block 10.0.2.0/24 \
        --rule-action allow \
        --egress
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$DMZ_NACL_ID" \
        --rule-number 120 \
        --protocol tcp \
        --port-range From=1024,To=65535 \
        --cidr-block 0.0.0.0/0 \
        --rule-action allow \
        --egress
    
    success "DMZ NACL rules configured successfully"
}

# Configure Web Tier NACL rules
configure_web_nacl_rules() {
    info "Configuring Web Tier NACL rules..."
    
    # Web Tier Inbound Rules
    aws ec2 create-network-acl-entry \
        --network-acl-id "$WEB_NACL_ID" \
        --rule-number 100 \
        --protocol tcp \
        --port-range From=80,To=80 \
        --cidr-block 10.0.1.0/24 \
        --rule-action allow
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$WEB_NACL_ID" \
        --rule-number 110 \
        --protocol tcp \
        --port-range From=443,To=443 \
        --cidr-block 10.0.1.0/24 \
        --rule-action allow
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$WEB_NACL_ID" \
        --rule-number 120 \
        --protocol tcp \
        --port-range From=22,To=22 \
        --cidr-block 10.0.5.0/24 \
        --rule-action allow
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$WEB_NACL_ID" \
        --rule-number 130 \
        --protocol tcp \
        --port-range From=161,To=161 \
        --cidr-block 10.0.6.0/24 \
        --rule-action allow
    
    # Web Tier Outbound Rules
    aws ec2 create-network-acl-entry \
        --network-acl-id "$WEB_NACL_ID" \
        --rule-number 100 \
        --protocol tcp \
        --port-range From=8080,To=8080 \
        --cidr-block 10.0.3.0/24 \
        --rule-action allow \
        --egress
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$WEB_NACL_ID" \
        --rule-number 110 \
        --protocol tcp \
        --port-range From=1024,To=65535 \
        --cidr-block 10.0.1.0/24 \
        --rule-action allow \
        --egress
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$WEB_NACL_ID" \
        --rule-number 120 \
        --protocol tcp \
        --port-range From=443,To=443 \
        --cidr-block 0.0.0.0/0 \
        --rule-action allow \
        --egress
    
    success "Web Tier NACL rules configured successfully"
}

# Configure Application Tier NACL rules
configure_app_nacl_rules() {
    info "Configuring Application Tier NACL rules..."
    
    # App Tier Inbound Rules
    aws ec2 create-network-acl-entry \
        --network-acl-id "$APP_NACL_ID" \
        --rule-number 100 \
        --protocol tcp \
        --port-range From=8080,To=8080 \
        --cidr-block 10.0.2.0/24 \
        --rule-action allow
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$APP_NACL_ID" \
        --rule-number 110 \
        --protocol tcp \
        --port-range From=22,To=22 \
        --cidr-block 10.0.5.0/24 \
        --rule-action allow
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$APP_NACL_ID" \
        --rule-number 120 \
        --protocol tcp \
        --port-range From=161,To=161 \
        --cidr-block 10.0.6.0/24 \
        --rule-action allow
    
    # App Tier Outbound Rules
    aws ec2 create-network-acl-entry \
        --network-acl-id "$APP_NACL_ID" \
        --rule-number 100 \
        --protocol tcp \
        --port-range From=3306,To=3306 \
        --cidr-block 10.0.4.0/24 \
        --rule-action allow \
        --egress
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$APP_NACL_ID" \
        --rule-number 110 \
        --protocol tcp \
        --port-range From=1024,To=65535 \
        --cidr-block 10.0.2.0/24 \
        --rule-action allow \
        --egress
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$APP_NACL_ID" \
        --rule-number 120 \
        --protocol tcp \
        --port-range From=443,To=443 \
        --cidr-block 0.0.0.0/0 \
        --rule-action allow \
        --egress
    
    success "Application Tier NACL rules configured successfully"
}

# Configure Database Tier NACL rules
configure_db_nacl_rules() {
    info "Configuring Database Tier NACL rules (most restrictive)..."
    
    # Database Tier Inbound Rules
    aws ec2 create-network-acl-entry \
        --network-acl-id "$DB_NACL_ID" \
        --rule-number 100 \
        --protocol tcp \
        --port-range From=3306,To=3306 \
        --cidr-block 10.0.3.0/24 \
        --rule-action allow
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$DB_NACL_ID" \
        --rule-number 110 \
        --protocol tcp \
        --port-range From=22,To=22 \
        --cidr-block 10.0.5.0/24 \
        --rule-action allow
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$DB_NACL_ID" \
        --rule-number 120 \
        --protocol tcp \
        --port-range From=161,To=161 \
        --cidr-block 10.0.6.0/24 \
        --rule-action allow
    
    # Database Tier Outbound Rules
    aws ec2 create-network-acl-entry \
        --network-acl-id "$DB_NACL_ID" \
        --rule-number 100 \
        --protocol tcp \
        --port-range From=1024,To=65535 \
        --cidr-block 10.0.3.0/24 \
        --rule-action allow \
        --egress
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$DB_NACL_ID" \
        --rule-number 110 \
        --protocol tcp \
        --port-range From=443,To=443 \
        --cidr-block 0.0.0.0/0 \
        --rule-action allow \
        --egress
    
    success "Database Tier NACL rules configured successfully"
}

# Configure Management and Monitoring NACL rules
configure_mgmt_mon_nacl_rules() {
    info "Configuring Management and Monitoring NACL rules..."
    
    # Management NACL rules (allow administrative access)
    aws ec2 create-network-acl-entry \
        --network-acl-id "$MGMT_NACL_ID" \
        --rule-number 100 \
        --protocol tcp \
        --port-range From=22,To=22 \
        --cidr-block 10.0.0.0/8 \
        --rule-action allow
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$MGMT_NACL_ID" \
        --rule-number 110 \
        --protocol tcp \
        --port-range From=443,To=443 \
        --cidr-block 0.0.0.0/0 \
        --rule-action allow \
        --egress
    
    # Monitoring NACL rules (allow monitoring traffic)
    aws ec2 create-network-acl-entry \
        --network-acl-id "$MON_NACL_ID" \
        --rule-number 100 \
        --protocol tcp \
        --port-range From=161,To=161 \
        --cidr-block 10.0.0.0/16 \
        --rule-action allow
    
    aws ec2 create-network-acl-entry \
        --network-acl-id "$MON_NACL_ID" \
        --rule-number 110 \
        --protocol tcp \
        --port-range From=443,To=443 \
        --cidr-block 0.0.0.0/0 \
        --rule-action allow \
        --egress
    
    success "Management and Monitoring NACL rules configured successfully"
}

# Associate NACLs with subnets
associate_nacls_with_subnets() {
    info "Associating NACLs with respective subnets..."
    
    local associations=(
        "$DMZ_NACL_ID:$DMZ_SUBNET_ID:DMZ"
        "$WEB_NACL_ID:$WEB_SUBNET_ID:Web"
        "$APP_NACL_ID:$APP_SUBNET_ID:App"
        "$DB_NACL_ID:$DB_SUBNET_ID:Database"
        "$MGMT_NACL_ID:$MGMT_SUBNET_ID:Management"
        "$MON_NACL_ID:$MON_SUBNET_ID:Monitoring"
    )
    
    for association in "${associations[@]}"; do
        IFS=':' read -r nacl_id subnet_id zone_name <<< "$association"
        
        info "Associating $zone_name NACL with subnet..."
        aws ec2 associate-network-acl \
            --network-acl-id "$nacl_id" \
            --subnet-id "$subnet_id"
        
        info "Associated $zone_name NACL ($nacl_id) with subnet ($subnet_id)"
    done
    
    success "NACLs associated with respective subnets"
}

# Create advanced security groups
create_advanced_security_groups() {
    info "Creating advanced security groups with layered rules..."
    
    local security_groups=(
        "dmz-alb-sg:Security group for Application Load Balancer in DMZ:dmz"
        "web-tier-sg:Security group for Web Tier instances:web"
        "app-tier-sg:Security group for Application Tier instances:app"
        "db-tier-sg:Security group for Database Tier:database"
        "mgmt-sg:Security group for Management resources:management"
    )
    
    for sg_config in "${security_groups[@]}"; do
        IFS=':' read -r group_name description zone_name <<< "$sg_config"
        
        info "Creating $group_name security group..."
        
        aws ec2 create-security-group \
            --group-name "$group_name" \
            --description "$description" \
            --vpc-id "$VPC_ID" \
            --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${group_name}},{Key=Zone,Value=${zone_name}}]" \
            --query 'GroupId' --output text > "$TEMP_DIR/${group_name//-/_}_id"
        
        local sg_id=$(cat "$TEMP_DIR/${group_name//-/_}_id")
        info "Created $group_name: $sg_id"
    done
    
    # Export Security Group IDs
    export DMZ_SG_ID=$(cat "$TEMP_DIR/dmz_alb_sg_id")
    export WEB_SG_ID=$(cat "$TEMP_DIR/web_tier_sg_id")
    export APP_SG_ID=$(cat "$TEMP_DIR/app_tier_sg_id")
    export DB_SG_ID=$(cat "$TEMP_DIR/db_tier_sg_id")
    export MGMT_SG_ID=$(cat "$TEMP_DIR/mgmt_sg_id")
    
    # Update environment file
    cat >> "$TEMP_DIR/environment.sh" << EOF
export DMZ_SG_ID="$DMZ_SG_ID"
export WEB_SG_ID="$WEB_SG_ID"
export APP_SG_ID="$APP_SG_ID"
export DB_SG_ID="$DB_SG_ID"
export MGMT_SG_ID="$MGMT_SG_ID"
EOF
    
    success "Advanced security groups created successfully"
}

# Configure security group rules
configure_security_group_rules() {
    info "Configuring security group rules with source group references..."
    
    # DMZ Security Group Rules (ALB)
    aws ec2 authorize-security-group-ingress \
        --group-id "$DMZ_SG_ID" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$DMZ_SG_ID" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0
    
    # Web Tier Security Group Rules
    aws ec2 authorize-security-group-ingress \
        --group-id "$WEB_SG_ID" \
        --protocol tcp \
        --port 80 \
        --source-group "$DMZ_SG_ID"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$WEB_SG_ID" \
        --protocol tcp \
        --port 443 \
        --source-group "$DMZ_SG_ID"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$WEB_SG_ID" \
        --protocol tcp \
        --port 22 \
        --source-group "$MGMT_SG_ID"
    
    # App Tier Security Group Rules
    aws ec2 authorize-security-group-ingress \
        --group-id "$APP_SG_ID" \
        --protocol tcp \
        --port 8080 \
        --source-group "$WEB_SG_ID"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$APP_SG_ID" \
        --protocol tcp \
        --port 22 \
        --source-group "$MGMT_SG_ID"
    
    # Database Security Group Rules
    aws ec2 authorize-security-group-ingress \
        --group-id "$DB_SG_ID" \
        --protocol tcp \
        --port 3306 \
        --source-group "$APP_SG_ID"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$DB_SG_ID" \
        --protocol tcp \
        --port 22 \
        --source-group "$MGMT_SG_ID"
    
    # Management Security Group Rules
    aws ec2 authorize-security-group-ingress \
        --group-id "$MGMT_SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr 10.0.0.0/8
    
    success "Security group rules configured successfully"
}

# Set up VPC Flow Logs
setup_vpc_flow_logs() {
    info "Setting up VPC Flow Logs for traffic monitoring..."
    
    # Create IAM role for VPC Flow Logs
    aws iam create-role \
        --role-name VPCFlowLogsRole \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "vpc-flow-logs.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }'
    
    # Attach policy to role
    aws iam attach-role-policy \
        --role-name VPCFlowLogsRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/VPCFlowLogsDeliveryRolePolicy
    
    # Wait for role to be available
    sleep 10
    
    # Create CloudWatch Log Group
    aws logs create-log-group \
        --log-group-name /aws/vpc/microsegmentation/flowlogs
    
    # Enable VPC Flow Logs
    aws ec2 create-flow-logs \
        --resource-type VPC \
        --resource-ids "$VPC_ID" \
        --traffic-type ALL \
        --log-destination-type cloud-watch-logs \
        --log-group-name /aws/vpc/microsegmentation/flowlogs \
        --deliver-logs-permission-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/VPCFlowLogsRole" \
        --query 'FlowLogIds[0]' --output text > "$TEMP_DIR/flow-log-id"
    
    # Create CloudWatch alarm for rejected traffic
    aws cloudwatch put-metric-alarm \
        --alarm-name "VPC-Rejected-Traffic-High" \
        --alarm-description "High number of rejected packets in VPC" \
        --metric-name PacketsDropped \
        --namespace AWS/VPC \
        --statistic Sum \
        --period 300 \
        --threshold 1000 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=VpcId,Value="$VPC_ID"
    
    # Update environment file
    cat >> "$TEMP_DIR/environment.sh" << EOF
export FLOW_LOG_ID="$(cat "$TEMP_DIR/flow-log-id")"
EOF
    
    success "VPC Flow Logs and CloudWatch monitoring configured"
}

# Create route tables
create_route_tables() {
    info "Creating route tables for proper traffic routing..."
    
    # Create public route table for DMZ
    aws ec2 create-route-table \
        --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=public-rt}]" \
        --query 'RouteTable.RouteTableId' --output text > "$TEMP_DIR/public-rt-id"
    
    export PUBLIC_RT_ID=$(cat "$TEMP_DIR/public-rt-id")
    
    # Add route to Internet Gateway
    aws ec2 create-route \
        --route-table-id "$PUBLIC_RT_ID" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "$IGW_ID"
    
    # Associate public route table with DMZ subnet
    aws ec2 associate-route-table \
        --route-table-id "$PUBLIC_RT_ID" \
        --subnet-id "$DMZ_SUBNET_ID"
    
    # Update environment file
    cat >> "$TEMP_DIR/environment.sh" << EOF
export PUBLIC_RT_ID="$PUBLIC_RT_ID"
EOF
    
    success "Route tables created and configured"
}

# Save deployment information
save_deployment_info() {
    info "Saving deployment information..."
    
    # Copy environment file to a persistent location
    cp "$TEMP_DIR/environment.sh" "$SCRIPT_DIR/microseg-environment.sh"
    
    # Create deployment summary
    cat > "$SCRIPT_DIR/deployment-summary.txt" << EOF
Network Micro-Segmentation Deployment Summary
=============================================

Deployment Date: $(date)
AWS Region: $AWS_REGION
VPC ID: $VPC_ID
Internet Gateway ID: $IGW_ID

Subnets:
- DMZ Subnet: $DMZ_SUBNET_ID (10.0.1.0/24)
- Web Tier Subnet: $WEB_SUBNET_ID (10.0.2.0/24)
- App Tier Subnet: $APP_SUBNET_ID (10.0.3.0/24)
- Database Subnet: $DB_SUBNET_ID (10.0.4.0/24)
- Management Subnet: $MGMT_SUBNET_ID (10.0.5.0/24)
- Monitoring Subnet: $MON_SUBNET_ID (10.0.6.0/24)

NACLs:
- DMZ NACL: $DMZ_NACL_ID
- Web NACL: $WEB_NACL_ID
- App NACL: $APP_NACL_ID
- Database NACL: $DB_NACL_ID
- Management NACL: $MGMT_NACL_ID
- Monitoring NACL: $MON_NACL_ID

Security Groups:
- DMZ Security Group: $DMZ_SG_ID
- Web Tier Security Group: $WEB_SG_ID
- App Tier Security Group: $APP_SG_ID
- Database Security Group: $DB_SG_ID
- Management Security Group: $MGMT_SG_ID

Key Pair: $KEY_PAIR_NAME
Private Key: $SCRIPT_DIR/microseg-environment.sh (contains path)

Flow Logs: $(cat "$TEMP_DIR/flow-log-id" 2>/dev/null || echo "Not configured")

To clean up this deployment, run: ./destroy.sh
EOF
    
    success "Deployment information saved to $SCRIPT_DIR/deployment-summary.txt"
}

# Main deployment function
main() {
    log "Starting Network Micro-Segmentation deployment..." "$GREEN"
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        warn "Running as root is not recommended for security reasons"
    fi
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                info "Dry run mode enabled - no resources will be created"
                DRY_RUN=true
                shift
                ;;
            --help)
                echo "Usage: $0 [--dry-run] [--help]"
                echo "  --dry-run    Show what would be done without creating resources"
                echo "  --help       Show this help message"
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    create_temp_dir
    set_environment_variables
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "Dry run completed - no resources were created"
        exit 0
    fi
    
    create_vpc_infrastructure
    create_security_zone_subnets
    create_custom_nacls
    configure_dmz_nacl_rules
    configure_web_nacl_rules
    configure_app_nacl_rules
    configure_db_nacl_rules
    configure_mgmt_mon_nacl_rules
    associate_nacls_with_subnets
    create_advanced_security_groups
    configure_security_group_rules
    setup_vpc_flow_logs
    create_route_tables
    save_deployment_info
    
    # Cleanup temporary directory
    rm -rf "$TEMP_DIR"
    
    success "Network Micro-Segmentation deployment completed successfully!"
    info "Log file: $LOG_FILE"
    info "Deployment summary: $SCRIPT_DIR/deployment-summary.txt"
    info "Environment variables: $SCRIPT_DIR/microseg-environment.sh"
    
    echo -e "\n${GREEN}Next Steps:${NC}"
    echo "1. Review the deployment summary at: $SCRIPT_DIR/deployment-summary.txt"
    echo "2. Test network connectivity between tiers"
    echo "3. Monitor VPC Flow Logs in CloudWatch"
    echo "4. Deploy application instances in the appropriate subnets"
    echo "5. Run ./destroy.sh when ready to clean up resources"
    
    log "Deployment completed successfully!" "$GREEN"
}

# Set trap for cleanup on script exit
trap cleanup_on_failure ERR

# Run main function
main "$@"