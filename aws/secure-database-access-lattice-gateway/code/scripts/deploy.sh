#!/bin/bash

# Secure Database Access with VPC Lattice Resource Gateway - Deployment Script
# This script automates the deployment of a secure cross-account database access solution
# using AWS VPC Lattice Resource Gateway, RDS, IAM, and AWS RAM

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging configuration
LOG_FILE="deployment_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_NAME="secure-database-access-lattice"
TIMEOUT_SECONDS=1800  # 30 minutes

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handler
error_exit() {
    print_error "Deployment failed at line $1. Check logs for details."
    print_error "Log file: $LOG_FILE"
    exit 1
}

trap 'error_exit $LINENO' ERR

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION 2.0.0" | tr " " "\n" | sort -V | head -n1) != "2.0.0" ]]; then
        print_error "AWS CLI version 2.0.0 or higher is required"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi
    
    # Check required tools
    for tool in mysql-client jq; do
        if ! command -v $tool &> /dev/null; then
            print_warning "$tool is not installed (optional for testing)"
        fi
    done
    
    print_success "Prerequisites check completed"
}

# Setup environment variables
setup_environment() {
    print_status "Setting up environment variables..."
    
    # AWS environment
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        print_error "AWS region not configured"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Resource names
    export DB_OWNER_ACCOUNT_ID=${AWS_ACCOUNT_ID}
    export CONSUMER_ACCOUNT_ID=${CONSUMER_ACCOUNT_ID:-""}
    export VPC_ID=${VPC_ID:-""}
    export SUBNET_ID=${SUBNET_ID:-""}
    export SUBNET_ID_2=${SUBNET_ID_2:-""}
    export DB_SUBNET_GROUP_NAME="lattice-db-subnet-group-${RANDOM_SUFFIX}"
    export DB_INSTANCE_ID="lattice-shared-db-${RANDOM_SUFFIX}"
    export RESOURCE_CONFIG_NAME="rds-config-${RANDOM_SUFFIX}"
    export SERVICE_NETWORK_NAME="lattice-network-${RANDOM_SUFFIX}"
    export DB_PASSWORD=${DB_PASSWORD:-"SecurePassword123!"}
    
    # Validate required environment variables
    if [[ -z "$CONSUMER_ACCOUNT_ID" ]]; then
        print_error "CONSUMER_ACCOUNT_ID environment variable is required"
        exit 1
    fi
    
    if [[ -z "$VPC_ID" ]]; then
        print_error "VPC_ID environment variable is required"
        exit 1
    fi
    
    if [[ -z "$SUBNET_ID" ]] || [[ -z "$SUBNET_ID_2" ]]; then
        print_error "SUBNET_ID and SUBNET_ID_2 environment variables are required"
        exit 1
    fi
    
    # Save environment to file for cleanup
    cat > "${SCRIPT_DIR}/deployment_env.sh" << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export DB_OWNER_ACCOUNT_ID="${DB_OWNER_ACCOUNT_ID}"
export CONSUMER_ACCOUNT_ID="${CONSUMER_ACCOUNT_ID}"
export VPC_ID="${VPC_ID}"
export SUBNET_ID="${SUBNET_ID}"
export SUBNET_ID_2="${SUBNET_ID_2}"
export DB_SUBNET_GROUP_NAME="${DB_SUBNET_GROUP_NAME}"
export DB_INSTANCE_ID="${DB_INSTANCE_ID}"
export RESOURCE_CONFIG_NAME="${RESOURCE_CONFIG_NAME}"
export SERVICE_NETWORK_NAME="${SERVICE_NETWORK_NAME}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF
    
    print_success "Environment configured"
    print_status "Deployment ID: ${RANDOM_SUFFIX}"
}

# Create RDS database and security groups
create_database() {
    print_status "Creating RDS database and security groups..."
    
    # Create security group for RDS database
    export RDS_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "lattice-rds-sg-${RANDOM_SUFFIX}" \
        --description "Security group for VPC Lattice RDS database" \
        --vpc-id "${VPC_ID}" \
        --query 'GroupId' --output text)
    
    # Get VPC CIDR for security group rules
    VPC_CIDR=$(aws ec2 describe-vpcs \
        --vpc-ids "${VPC_ID}" \
        --query 'Vpcs[0].CidrBlock' --output text)
    
    # Allow MySQL traffic from VPC CIDR
    aws ec2 authorize-security-group-ingress \
        --group-id "${RDS_SECURITY_GROUP_ID}" \
        --protocol tcp \
        --port 3306 \
        --cidr "${VPC_CIDR}"
    
    # Create DB subnet group
    aws rds create-db-subnet-group \
        --db-subnet-group-name "${DB_SUBNET_GROUP_NAME}" \
        --db-subnet-group-description "Subnet group for VPC Lattice shared database" \
        --subnet-ids "${SUBNET_ID}" "${SUBNET_ID_2}" \
        --tags "Key=Purpose,Value=VPCLatticeDemo" "Key=DeploymentId,Value=${RANDOM_SUFFIX}"
    
    # Create RDS instance
    aws rds create-db-instance \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --db-instance-class db.t3.micro \
        --engine mysql \
        --master-username admin \
        --master-user-password "${DB_PASSWORD}" \
        --allocated-storage 20 \
        --db-subnet-group-name "${DB_SUBNET_GROUP_NAME}" \
        --vpc-security-group-ids "${RDS_SECURITY_GROUP_ID}" \
        --no-publicly-accessible \
        --storage-encrypted \
        --backup-retention-period 7 \
        --tags "Key=Purpose,Value=VPCLatticeDemo" "Key=DeploymentId,Value=${RANDOM_SUFFIX}"
    
    # Update environment file
    echo "export RDS_SECURITY_GROUP_ID=\"${RDS_SECURITY_GROUP_ID}\"" >> "${SCRIPT_DIR}/deployment_env.sh"
    
    print_success "RDS database creation initiated"
}

# Wait for database availability and create resource gateway security group
wait_for_database() {
    print_status "Waiting for RDS instance to become available..."
    
    # Wait for RDS instance with timeout
    timeout_start=$(date +%s)
    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - timeout_start))
        
        if [[ $elapsed -gt $TIMEOUT_SECONDS ]]; then
            print_error "Timeout waiting for RDS instance to become available"
            exit 1
        fi
        
        db_status=$(aws rds describe-db-instances \
            --db-instance-identifier "${DB_INSTANCE_ID}" \
            --query 'DBInstances[0].DBInstanceStatus' --output text)
        
        if [[ "$db_status" == "available" ]]; then
            break
        fi
        
        print_status "Database status: $db_status (elapsed: ${elapsed}s)"
        sleep 30
    done
    
    # Get RDS endpoint
    export RDS_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    # Create security group for resource gateway
    export RESOURCE_GW_SG_ID=$(aws ec2 create-security-group \
        --group-name "lattice-resource-gateway-sg-${RANDOM_SUFFIX}" \
        --description "Security group for VPC Lattice resource gateway" \
        --vpc-id "${VPC_ID}" \
        --query 'GroupId' --output text)
    
    # Configure security group rules
    aws ec2 authorize-security-group-egress \
        --group-id "${RESOURCE_GW_SG_ID}" \
        --protocol tcp \
        --port 3306 \
        --source-group "${RDS_SECURITY_GROUP_ID}"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "${RDS_SECURITY_GROUP_ID}" \
        --protocol tcp \
        --port 3306 \
        --source-group "${RESOURCE_GW_SG_ID}"
    
    # Update environment file
    echo "export RDS_ENDPOINT=\"${RDS_ENDPOINT}\"" >> "${SCRIPT_DIR}/deployment_env.sh"
    echo "export RESOURCE_GW_SG_ID=\"${RESOURCE_GW_SG_ID}\"" >> "${SCRIPT_DIR}/deployment_env.sh"
    
    print_success "Database available at: ${RDS_ENDPOINT}"
}

# Create VPC Lattice service network
create_service_network() {
    print_status "Creating VPC Lattice service network..."
    
    export SERVICE_NETWORK_ARN=$(aws vpc-lattice create-service-network \
        --name "${SERVICE_NETWORK_NAME}" \
        --auth-type AWS_IAM \
        --query 'arn' --output text)
    
    # Associate service network with VPC
    export SERVICE_NETWORK_VPC_ASSOCIATION_ARN=$(aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier "${SERVICE_NETWORK_ARN}" \
        --vpc-identifier "${VPC_ID}" \
        --security-group-ids "${RESOURCE_GW_SG_ID}" \
        --query 'arn' --output text)
    
    # Update environment file
    echo "export SERVICE_NETWORK_ARN=\"${SERVICE_NETWORK_ARN}\"" >> "${SCRIPT_DIR}/deployment_env.sh"
    echo "export SERVICE_NETWORK_VPC_ASSOCIATION_ARN=\"${SERVICE_NETWORK_VPC_ASSOCIATION_ARN}\"" >> "${SCRIPT_DIR}/deployment_env.sh"
    
    print_success "Service network created: ${SERVICE_NETWORK_ARN}"
}

# Create resource gateway
create_resource_gateway() {
    print_status "Creating VPC Lattice resource gateway..."
    
    export RESOURCE_GATEWAY_ARN=$(aws vpc-lattice create-resource-gateway \
        --name "db-gateway-${RANDOM_SUFFIX}" \
        --vpc-identifier "${VPC_ID}" \
        --subnet-ids "${SUBNET_ID}" "${SUBNET_ID_2}" \
        --security-group-ids "${RESOURCE_GW_SG_ID}" \
        --ip-address-type IPV4 \
        --query 'arn' --output text)
    
    export RESOURCE_GATEWAY_ID=$(echo "${RESOURCE_GATEWAY_ARN}" | awk -F'/' '{print $NF}')
    
    # Update environment file
    echo "export RESOURCE_GATEWAY_ARN=\"${RESOURCE_GATEWAY_ARN}\"" >> "${SCRIPT_DIR}/deployment_env.sh"
    echo "export RESOURCE_GATEWAY_ID=\"${RESOURCE_GATEWAY_ID}\"" >> "${SCRIPT_DIR}/deployment_env.sh"
    
    print_success "Resource gateway created: ${RESOURCE_GATEWAY_ID}"
}

# Create resource configuration
create_resource_configuration() {
    print_status "Creating resource configuration for RDS database..."
    
    export RESOURCE_CONFIG_ARN=$(aws vpc-lattice create-resource-configuration \
        --name "${RESOURCE_CONFIG_NAME}" \
        --type SINGLE \
        --resource-configuration-definition "dnsResource={domainName=${RDS_ENDPOINT},ipAddressType=IPV4}" \
        --resource-gateway-identifier "${RESOURCE_GATEWAY_ID}" \
        --protocol TCP \
        --port-ranges '3306' \
        --query 'arn' --output text)
    
    # Associate resource configuration with service network
    export RESOURCE_CONFIG_ASSOCIATION_ARN=$(aws vpc-lattice create-resource-configuration-association \
        --resource-configuration-identifier "${RESOURCE_CONFIG_ARN}" \
        --service-network-identifier "${SERVICE_NETWORK_ARN}" \
        --query 'arn' --output text)
    
    # Update environment file
    echo "export RESOURCE_CONFIG_ARN=\"${RESOURCE_CONFIG_ARN}\"" >> "${SCRIPT_DIR}/deployment_env.sh"
    echo "export RESOURCE_CONFIG_ASSOCIATION_ARN=\"${RESOURCE_CONFIG_ASSOCIATION_ARN}\"" >> "${SCRIPT_DIR}/deployment_env.sh"
    
    print_success "Resource configuration created and associated"
}

# Configure IAM policy for cross-account access
configure_iam_policy() {
    print_status "Configuring IAM policy for cross-account database access..."
    
    # Create IAM policy document
    cat > "${SCRIPT_DIR}/lattice-db-access-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    "arn:aws:iam::${CONSUMER_ACCOUNT_ID}:root"
                ]
            },
            "Action": [
                "vpc-lattice-svcs:Invoke"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "vpc-lattice-svcs:SourceAccount": "${CONSUMER_ACCOUNT_ID}"
                }
            }
        }
    ]
}
EOF
    
    # Apply IAM policy to service network
    aws vpc-lattice put-auth-policy \
        --resource-identifier "${SERVICE_NETWORK_ARN}" \
        --policy "file://${SCRIPT_DIR}/lattice-db-access-policy.json"
    
    print_success "IAM policy configured for cross-account access"
}

# Share resource configuration using AWS RAM
share_resource_configuration() {
    print_status "Sharing resource configuration using AWS RAM..."
    
    export RESOURCE_SHARE_ARN=$(aws ram create-resource-share \
        --name "lattice-db-access-${RANDOM_SUFFIX}" \
        --resource-arns "${RESOURCE_CONFIG_ARN}" \
        --principals "${CONSUMER_ACCOUNT_ID}" \
        --allow-external-principals \
        --query 'resourceShare.resourceShareArn' --output text)
    
    # Update environment file
    echo "export RESOURCE_SHARE_ARN=\"${RESOURCE_SHARE_ARN}\"" >> "${SCRIPT_DIR}/deployment_env.sh"
    
    print_success "Resource configuration shared via AWS RAM"
    print_warning "Consumer account ${CONSUMER_ACCOUNT_ID} must accept the RAM invitation"
}

# Validate deployment
validate_deployment() {
    print_status "Validating deployment..."
    
    # Check resource gateway status
    RESOURCE_GATEWAY_STATUS=$(aws vpc-lattice get-resource-gateway \
        --resource-gateway-identifier "${RESOURCE_GATEWAY_ID}" \
        --query 'status' --output text)
    
    if [[ "$RESOURCE_GATEWAY_STATUS" != "ACTIVE" ]]; then
        print_warning "Resource gateway status: $RESOURCE_GATEWAY_STATUS"
    else
        print_success "Resource gateway is active"
    fi
    
    # Check resource configuration associations
    ASSOCIATION_COUNT=$(aws vpc-lattice list-resource-configuration-associations \
        --resource-configuration-identifier "${RESOURCE_CONFIG_ARN}" \
        --query 'length(items)' --output text)
    
    if [[ "$ASSOCIATION_COUNT" -eq 0 ]]; then
        print_error "No resource configuration associations found"
        exit 1
    fi
    
    print_success "Resource configuration associations verified"
    
    # Get VPC Lattice DNS name
    export LATTICE_DNS_NAME=$(aws vpc-lattice get-resource-configuration \
        --resource-configuration-identifier "${RESOURCE_CONFIG_ARN}" \
        --query 'dnsEntry.domainName' --output text)
    
    if [[ -n "$LATTICE_DNS_NAME" ]]; then
        echo "export LATTICE_DNS_NAME=\"${LATTICE_DNS_NAME}\"" >> "${SCRIPT_DIR}/deployment_env.sh"
        print_success "VPC Lattice DNS name: ${LATTICE_DNS_NAME}"
    fi
    
    print_success "Deployment validation completed"
}

# Print deployment summary
print_summary() {
    print_success "=== Deployment Summary ==="
    echo "Deployment ID: ${RANDOM_SUFFIX}"
    echo "AWS Region: ${AWS_REGION}"
    echo "Database Account: ${DB_OWNER_ACCOUNT_ID}"
    echo "Consumer Account: ${CONSUMER_ACCOUNT_ID}"
    echo "RDS Endpoint: ${RDS_ENDPOINT}"
    echo "VPC Lattice DNS: ${LATTICE_DNS_NAME:-'Not available yet'}"
    echo "Service Network: ${SERVICE_NETWORK_ARN}"
    echo "Resource Share: ${RESOURCE_SHARE_ARN}"
    echo ""
    print_status "Environment variables saved to: ${SCRIPT_DIR}/deployment_env.sh"
    print_status "Deployment log saved to: $LOG_FILE"
    echo ""
    print_warning "Next steps:"
    echo "1. Consumer account must accept RAM invitation"
    echo "2. Consumer account must associate their VPC with the service network"
    echo "3. Test database connectivity using the VPC Lattice DNS name"
    echo ""
    print_status "To clean up resources, run: ./destroy.sh"
}

# Main execution
main() {
    print_status "Starting secure database access deployment..."
    print_status "Deployment started at: $(date)"
    
    check_prerequisites
    setup_environment
    create_database
    wait_for_database
    create_service_network
    create_resource_gateway
    create_resource_configuration
    configure_iam_policy
    share_resource_configuration
    validate_deployment
    print_summary
    
    print_success "Deployment completed successfully!"
}

# Help function
show_help() {
    cat << EOF
Secure Database Access with VPC Lattice Resource Gateway - Deployment Script

Usage: $0 [OPTIONS]

Required Environment Variables:
  CONSUMER_ACCOUNT_ID    AWS account ID that will consume the shared database
  VPC_ID                 VPC ID where resources will be created
  SUBNET_ID              First subnet ID for multi-AZ deployment
  SUBNET_ID_2            Second subnet ID in different AZ

Optional Environment Variables:
  AWS_REGION             AWS region (default: from AWS CLI config)
  DB_PASSWORD            RDS database password (default: SecurePassword123!)

Options:
  -h, --help             Show this help message
  -v, --version          Show script version

Example:
  export CONSUMER_ACCOUNT_ID="123456789012"
  export VPC_ID="vpc-xxxxxxxxx"
  export SUBNET_ID="subnet-xxxxxxxxx"
  export SUBNET_ID_2="subnet-yyyyyyyyy"
  $0

EOF
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -v|--version)
        echo "Secure Database Access Deployment Script v1.0"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac