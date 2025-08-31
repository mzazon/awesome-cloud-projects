#!/bin/bash

#=============================================================================
# AWS Cross-Account Database Sharing with VPC Lattice and RDS
# Deployment Script
#
# This script deploys a complete cross-account database sharing solution using:
# - VPC Lattice Resource Configurations and Service Networks
# - RDS MySQL Database with proper security groups
# - Cross-account IAM roles and policies
# - AWS RAM resource sharing
# - CloudWatch monitoring and logging
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Administrative permissions in Account A (database owner)
# - Account B ID for cross-account sharing
# - Appropriate IAM permissions for VPC Lattice, RDS, IAM, and RAM
#=============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check the logs above for details."
    log_warn "Some resources may have been created. Run destroy.sh to clean up."
    exit 1
}

trap cleanup_on_error ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"

# Start logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

log_info "Starting AWS Cross-Account Database Sharing deployment..."
log_info "Log file: ${LOG_FILE}"

#=============================================================================
# Prerequisites Check
#=============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "${AWS_CLI_VERSION}" | cut -d. -f1) -lt 2 ]]; then
        log_error "AWS CLI v2 is required. Current version: ${AWS_CLI_VERSION}"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check if Account B ID is provided
    if [[ -z "${AWS_ACCOUNT_B:-}" ]]; then
        log_warn "AWS_ACCOUNT_B environment variable not set."
        echo -n "Please enter Account B ID (12-digit AWS Account ID): "
        read -r AWS_ACCOUNT_B
        if [[ ! "${AWS_ACCOUNT_B}" =~ ^[0-9]{12}$ ]]; then
            log_error "Invalid AWS Account ID. Must be 12 digits."
            exit 1
        fi
        export AWS_ACCOUNT_B
    fi
    
    log_success "Prerequisites check completed"
}

#=============================================================================
# Environment Setup
#=============================================================================

setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS account and region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        log_warn "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_A=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set resource names
    export DB_INSTANCE_ID="shared-database-${RANDOM_SUFFIX}"
    export SERVICE_NETWORK_NAME="database-sharing-network-${RANDOM_SUFFIX}"
    export RESOURCE_CONFIG_NAME="rds-resource-config-${RANDOM_SUFFIX}"
    export RESOURCE_GATEWAY_NAME="rds-gateway-${RANDOM_SUFFIX}"
    
    # Create deployment state file
    STATE_FILE="${SCRIPT_DIR}/deployment_state.env"
    cat > "${STATE_FILE}" << EOF
# Deployment State - $(date)
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_A=${AWS_ACCOUNT_A}
AWS_ACCOUNT_B=${AWS_ACCOUNT_B}
DB_INSTANCE_ID=${DB_INSTANCE_ID}
SERVICE_NETWORK_NAME=${SERVICE_NETWORK_NAME}
RESOURCE_CONFIG_NAME=${RESOURCE_CONFIG_NAME}
RESOURCE_GATEWAY_NAME=${RESOURCE_GATEWAY_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment setup completed"
    log_info "Account A (Database Owner): ${AWS_ACCOUNT_A}"
    log_info "Account B (Database Consumer): ${AWS_ACCOUNT_B}"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
}

#=============================================================================
# VPC and Networking Setup
#=============================================================================

create_vpc_infrastructure() {
    log_info "Creating VPC infrastructure..."
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --query 'Vpc.VpcId' --output text)
    
    aws ec2 create-tags \
        --resources "${VPC_ID}" \
        --tags Key=Name,Value=database-owner-vpc-${RANDOM_SUFFIX}
    
    echo "VPC_ID=${VPC_ID}" >> "${STATE_FILE}"
    
    # Create internet gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
        --query 'InternetGateway.InternetGatewayId' --output text)
    
    aws ec2 attach-internet-gateway \
        --vpc-id "${VPC_ID}" \
        --internet-gateway-id "${IGW_ID}"
    
    echo "IGW_ID=${IGW_ID}" >> "${STATE_FILE}"
    
    # Create subnets for RDS (minimum 2 AZs required)
    SUBNET_A=$(aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --query 'Subnet.SubnetId' --output text)
    
    SUBNET_B=$(aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.2.0/24 \
        --availability-zone "${AWS_REGION}b" \
        --query 'Subnet.SubnetId' --output text)
    
    # Create subnet for resource gateway (/28 required)
    GATEWAY_SUBNET=$(aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.3.0/28 \
        --availability-zone "${AWS_REGION}a" \
        --query 'Subnet.SubnetId' --output text)
    
    aws ec2 create-tags \
        --resources "${SUBNET_A}" "${SUBNET_B}" "${GATEWAY_SUBNET}" \
        --tags Key=Name,Value=database-subnets-${RANDOM_SUFFIX}
    
    echo "SUBNET_A=${SUBNET_A}" >> "${STATE_FILE}"
    echo "SUBNET_B=${SUBNET_B}" >> "${STATE_FILE}"
    echo "GATEWAY_SUBNET=${GATEWAY_SUBNET}" >> "${STATE_FILE}"
    
    log_success "VPC infrastructure created"
    log_info "VPC ID: ${VPC_ID}"
}

#=============================================================================
# RDS Database Creation
#=============================================================================

create_rds_database() {
    log_info "Creating RDS database..."
    
    # Create DB subnet group
    aws rds create-db-subnet-group \
        --db-subnet-group-name "${DB_INSTANCE_ID}-subnet-group" \
        --db-subnet-group-description "Subnet group for shared database" \
        --subnet-ids "${SUBNET_A}" "${SUBNET_B}"
    
    # Create security group for RDS
    DB_SECURITY_GROUP=$(aws ec2 create-security-group \
        --group-name "${DB_INSTANCE_ID}-sg" \
        --description "Security group for shared RDS database" \
        --vpc-id "${VPC_ID}" \
        --query 'GroupId' --output text)
    
    # Allow inbound traffic from VPC CIDR
    aws ec2 authorize-security-group-ingress \
        --group-id "${DB_SECURITY_GROUP}" \
        --protocol tcp \
        --port 3306 \
        --cidr 10.0.0.0/16
    
    echo "DB_SECURITY_GROUP=${DB_SECURITY_GROUP}" >> "${STATE_FILE}"
    
    # Generate secure password
    DB_PASSWORD=$(aws secretsmanager get-random-password \
        --exclude-punctuation \
        --password-length 16 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Create RDS database
    aws rds create-db-instance \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --db-instance-class db.t3.micro \
        --engine mysql \
        --master-username admin \
        --master-user-password "${DB_PASSWORD}" \
        --allocated-storage 20 \
        --db-subnet-group-name "${DB_INSTANCE_ID}-subnet-group" \
        --vpc-security-group-ids "${DB_SECURITY_GROUP}" \
        --backup-retention-period 7 \
        --storage-encrypted
    
    log_info "Waiting for RDS database to become available (this may take 10-15 minutes)..."
    aws rds wait db-instance-available \
        --db-instance-identifier "${DB_INSTANCE_ID}"
    
    # Get database endpoint
    DB_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    DB_PORT=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --query 'DBInstances[0].Endpoint.Port' \
        --output text)
    
    echo "DB_ENDPOINT=${DB_ENDPOINT}" >> "${STATE_FILE}"
    echo "DB_PORT=${DB_PORT}" >> "${STATE_FILE}"
    
    log_success "RDS database created and available"
    log_info "Database endpoint: ${DB_ENDPOINT}:${DB_PORT}"
}

#=============================================================================
# VPC Lattice Resource Gateway
#=============================================================================

create_resource_gateway() {
    log_info "Creating VPC Lattice resource gateway..."
    
    # Create security group for resource gateway
    GATEWAY_SECURITY_GROUP=$(aws ec2 create-security-group \
        --group-name "${RESOURCE_GATEWAY_NAME}-sg" \
        --description "Security group for VPC Lattice resource gateway" \
        --vpc-id "${VPC_ID}" \
        --query 'GroupId' --output text)
    
    # Allow all traffic within VPC for resource gateway
    aws ec2 authorize-security-group-ingress \
        --group-id "${GATEWAY_SECURITY_GROUP}" \
        --protocol -1 \
        --cidr 10.0.0.0/16
    
    echo "GATEWAY_SECURITY_GROUP=${GATEWAY_SECURITY_GROUP}" >> "${STATE_FILE}"
    
    # Create resource gateway
    RESOURCE_GATEWAY_ID=$(aws vpc-lattice create-resource-gateway \
        --name "${RESOURCE_GATEWAY_NAME}" \
        --vpc-identifier "${VPC_ID}" \
        --subnet-ids "${GATEWAY_SUBNET}" \
        --security-group-ids "${GATEWAY_SECURITY_GROUP}" \
        --query 'id' --output text)
    
    echo "RESOURCE_GATEWAY_ID=${RESOURCE_GATEWAY_ID}" >> "${STATE_FILE}"
    
    log_success "Resource gateway created: ${RESOURCE_GATEWAY_ID}"
}

#=============================================================================
# VPC Lattice Service Network
#=============================================================================

create_service_network() {
    log_info "Creating VPC Lattice service network..."
    
    # Create VPC Lattice service network
    SERVICE_NETWORK_ID=$(aws vpc-lattice create-service-network \
        --name "${SERVICE_NETWORK_NAME}" \
        --auth-type AWS_IAM \
        --query 'id' --output text)
    
    # Associate VPC with service network
    aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier "${SERVICE_NETWORK_ID}" \
        --vpc-identifier "${VPC_ID}"
    
    echo "SERVICE_NETWORK_ID=${SERVICE_NETWORK_ID}" >> "${STATE_FILE}"
    
    log_success "Service network created: ${SERVICE_NETWORK_ID}"
}

#=============================================================================
# Resource Configuration
#=============================================================================

create_resource_configuration() {
    log_info "Creating resource configuration for RDS database..."
    
    # Create resource configuration
    RESOURCE_CONFIG_ID=$(aws vpc-lattice create-resource-configuration \
        --name "${RESOURCE_CONFIG_NAME}" \
        --type SINGLE \
        --resource-gateway-identifier "${RESOURCE_GATEWAY_ID}" \
        --resource-configuration-definition "{
            \"ipResource\": {
                \"ipAddress\": \"${DB_ENDPOINT}\"
            }
        }" \
        --protocol TCP \
        --port-ranges "${DB_PORT}" \
        --allow-association-to-shareable-service-network \
        --query 'id' --output text)
    
    echo "RESOURCE_CONFIG_ID=${RESOURCE_CONFIG_ID}" >> "${STATE_FILE}"
    
    # Associate resource configuration with service network
    aws vpc-lattice create-resource-configuration-association \
        --resource-configuration-identifier "${RESOURCE_CONFIG_ID}" \
        --service-network-identifier "${SERVICE_NETWORK_ID}"
    
    log_success "Resource configuration created and associated: ${RESOURCE_CONFIG_ID}"
}

#=============================================================================
# IAM Cross-Account Role
#=============================================================================

create_cross_account_iam() {
    log_info "Creating cross-account IAM role..."
    
    # Create trust policy file
    TRUST_POLICY_FILE="${SCRIPT_DIR}/database-access-role-trust-policy.json"
    cat > "${TRUST_POLICY_FILE}" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${AWS_ACCOUNT_B}:root"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "sts:ExternalId": "unique-external-id-12345"
                }
            }
        }
    ]
}
EOF
    
    ROLE_NAME="DatabaseAccessRole-${RANDOM_SUFFIX}"
    CROSS_ACCOUNT_ROLE_ARN=$(aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document "file://${TRUST_POLICY_FILE}" \
        --query 'Role.Arn' --output text)
    
    # Create access policy file
    ACCESS_POLICY_FILE="${SCRIPT_DIR}/database-access-policy.json"
    cat > "${ACCESS_POLICY_FILE}" << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "vpc-lattice:Invoke"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-name DatabaseAccessPolicy \
        --policy-document "file://${ACCESS_POLICY_FILE}"
    
    echo "CROSS_ACCOUNT_ROLE_ARN=${CROSS_ACCOUNT_ROLE_ARN}" >> "${STATE_FILE}"
    echo "ROLE_NAME=${ROLE_NAME}" >> "${STATE_FILE}"
    
    log_success "Cross-account IAM role created: ${CROSS_ACCOUNT_ROLE_ARN}"
}

#=============================================================================
# Service Network Authentication Policy
#=============================================================================

create_auth_policy() {
    log_info "Creating service network authentication policy..."
    
    # Create authentication policy file
    AUTH_POLICY_FILE="${SCRIPT_DIR}/service-network-auth-policy.json"
    cat > "${AUTH_POLICY_FILE}" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "${CROSS_ACCOUNT_ROLE_ARN}"
            },
            "Action": "vpc-lattice:Invoke",
            "Resource": "*"
        }
    ]
}
EOF
    
    aws vpc-lattice put-auth-policy \
        --resource-identifier "${SERVICE_NETWORK_ID}" \
        --policy "file://${AUTH_POLICY_FILE}"
    
    log_success "Service network authentication policy configured"
}

#=============================================================================
# AWS RAM Resource Share
#=============================================================================

create_resource_share() {
    log_info "Creating AWS RAM resource share..."
    
    RESOURCE_SHARE_NAME="DatabaseResourceShare-${RANDOM_SUFFIX}"
    RESOURCE_SHARE_ARN=$(aws ram create-resource-share \
        --name "${RESOURCE_SHARE_NAME}" \
        --resource-arns "arn:aws:vpc-lattice:${AWS_REGION}:${AWS_ACCOUNT_A}:resourceconfiguration/${RESOURCE_CONFIG_ID}" \
        --principals "${AWS_ACCOUNT_B}" \
        --query 'resourceShare.resourceShareArn' --output text)
    
    echo "RESOURCE_SHARE_ARN=${RESOURCE_SHARE_ARN}" >> "${STATE_FILE}"
    echo "RESOURCE_SHARE_NAME=${RESOURCE_SHARE_NAME}" >> "${STATE_FILE}"
    
    log_success "Resource share created: ${RESOURCE_SHARE_ARN}"
    log_info "Account B (${AWS_ACCOUNT_B}) can now accept the resource share"
}

#=============================================================================
# CloudWatch Monitoring
#=============================================================================

setup_monitoring() {
    log_info "Setting up CloudWatch monitoring..."
    
    # Create CloudWatch log group
    aws logs create-log-group \
        --log-group-name "/aws/vpc-lattice/servicenetwork/${SERVICE_NETWORK_ID}" || true
    
    # Create CloudWatch dashboard
    DASHBOARD_NAME="DatabaseSharingMonitoring-${RANDOM_SUFFIX}"
    DASHBOARD_FILE="${SCRIPT_DIR}/dashboard-definition.json"
    cat > "${DASHBOARD_FILE}" << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/VpcLattice", "RequestCount", "ServiceNetwork", "${SERVICE_NETWORK_ID}"],
                    [".", "ResponseTime", ".", "."],
                    [".", "ActiveConnectionCount", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Database Access Metrics"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body "file://${DASHBOARD_FILE}"
    
    echo "DASHBOARD_NAME=${DASHBOARD_NAME}" >> "${STATE_FILE}"
    
    log_success "CloudWatch monitoring configured"
}

#=============================================================================
# Validation
#=============================================================================

validate_deployment() {
    log_info "Validating deployment..."
    
    # Check service network status
    SERVICE_NETWORK_STATUS=$(aws vpc-lattice get-service-network \
        --service-network-identifier "${SERVICE_NETWORK_ID}" \
        --query 'status' --output text)
    
    if [[ "${SERVICE_NETWORK_STATUS}" != "ACTIVE" ]]; then
        log_warn "Service network status: ${SERVICE_NETWORK_STATUS}"
    else
        log_success "Service network is active"
    fi
    
    # Check resource gateway status
    RESOURCE_GATEWAY_STATUS=$(aws vpc-lattice get-resource-gateway \
        --resource-gateway-identifier "${RESOURCE_GATEWAY_ID}" \
        --query 'status' --output text)
    
    if [[ "${RESOURCE_GATEWAY_STATUS}" != "ACTIVE" ]]; then
        log_warn "Resource gateway status: ${RESOURCE_GATEWAY_STATUS}"
    else
        log_success "Resource gateway is active"
    fi
    
    # Check resource configuration associations
    ASSOCIATIONS=$(aws vpc-lattice list-resource-configuration-associations \
        --service-network-identifier "${SERVICE_NETWORK_ID}" \
        --query 'items[0].status' --output text)
    
    if [[ "${ASSOCIATIONS}" != "ACTIVE" ]]; then
        log_warn "Resource configuration association status: ${ASSOCIATIONS}"
    else
        log_success "Resource configuration association is active"
    fi
    
    # Check AWS RAM resource share
    SHARE_STATUS=$(aws ram get-resource-shares \
        --resource-owner SELF \
        --name "${RESOURCE_SHARE_NAME}" \
        --query 'resourceShares[0].status' --output text)
    
    if [[ "${SHARE_STATUS}" != "ACTIVE" ]]; then
        log_warn "Resource share status: ${SHARE_STATUS}"
    else
        log_success "Resource share is active"
    fi
    
    log_success "Deployment validation completed"
}

#=============================================================================
# Main Deployment Function
#=============================================================================

main() {
    log_info "==================================================================="
    log_info "AWS Cross-Account Database Sharing with VPC Lattice and RDS"
    log_info "Deployment started at: $(date)"
    log_info "==================================================================="
    
    check_prerequisites
    setup_environment
    create_vpc_infrastructure
    create_rds_database
    create_resource_gateway
    create_service_network
    create_resource_configuration
    create_cross_account_iam
    create_auth_policy
    create_resource_share
    setup_monitoring
    validate_deployment
    
    log_info "==================================================================="
    log_success "Deployment completed successfully!"
    log_info "==================================================================="
    
    echo
    log_info "Deployment Summary:"
    log_info "- Account A (Database Owner): ${AWS_ACCOUNT_A}"
    log_info "- Account B (Database Consumer): ${AWS_ACCOUNT_B}"
    log_info "- AWS Region: ${AWS_REGION}"
    log_info "- Database Instance: ${DB_INSTANCE_ID}"
    log_info "- Service Network: ${SERVICE_NETWORK_ID}"
    log_info "- Resource Configuration: ${RESOURCE_CONFIG_ID}"
    log_info "- Resource Share: ${RESOURCE_SHARE_ARN}"
    echo
    log_info "Next Steps for Account B:"
    log_info "1. Accept the AWS RAM resource share invitation"
    log_info "2. Associate your VPC with the shared service network"
    log_info "3. Configure applications to use the cross-account IAM role"
    echo
    log_info "State file saved to: ${STATE_FILE}"
    log_info "Log file saved to: ${LOG_FILE}"
    
    # Clean up temporary files
    rm -f "${SCRIPT_DIR}"/*.json
}

# Execute main function
main "$@"