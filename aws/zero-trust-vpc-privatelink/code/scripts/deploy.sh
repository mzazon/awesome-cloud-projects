#!/bin/bash

################################################################################
# Deploy Zero Trust Network Architecture with VPC Endpoints and PrivateLink
# 
# This script automates the deployment of a zero trust network architecture
# using AWS VPC endpoints and PrivateLink services for secure, private
# connectivity without internet exposure.
#
# Usage: ./deploy.sh [OPTIONS]
#
# OPTIONS:
#   --dry-run    Show what would be deployed without making changes
#   --verbose    Enable verbose logging
#   --help       Show this help message
#
# Prerequisites:
#   - AWS CLI v2 installed and configured
#   - Appropriate IAM permissions for VPC, EC2, ELB, Route53, IAM, and Logs
#   - Valid AWS credentials configured
#
################################################################################

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
DRY_RUN=false
VERBOSE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Deployment failed. Check $LOG_FILE for details."
    exit 1
}

# Cleanup on script exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Script exited with error code $exit_code"
        log "INFO" "To clean up any partial deployment, run: ./destroy.sh"
    fi
}
trap cleanup EXIT

# Display help
show_help() {
    cat << EOF
Deploy Zero Trust Network Architecture with VPC Endpoints and PrivateLink

USAGE:
    ./deploy.sh [OPTIONS]

OPTIONS:
    --dry-run    Show what would be deployed without making changes
    --verbose    Enable verbose logging
    --help       Show this help message

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Appropriate IAM permissions for VPC, EC2, ELB, Route53, IAM, and Logs
    - Valid AWS credentials configured

ESTIMATED COST:
    - VPC Endpoints: ~\$7.20/month each (3 endpoints = ~\$21.60/month)
    - Network Load Balancer: ~\$16.20/month
    - Data processing charges: ~\$0.01/GB
    - CloudWatch Logs: ~\$0.50/GB ingested
    Total estimated cost: \$40-60/month depending on usage

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Initialize logging
mkdir -p "$(dirname "$LOG_FILE")"
log "INFO" "Starting deployment of Zero Trust Network Architecture"
log "INFO" "Log file: $LOG_FILE"
log "INFO" "Dry run mode: $DRY_RUN"

# Prerequisites checking
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "DEBUG" "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured or invalid. Run 'aws configure' to set up credentials."
    fi
    
    # Get account and region info
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    
    if [[ -z "$AWS_REGION" ]]; then
        error_exit "AWS region not configured. Set region with 'aws configure set region <region>'"
    fi
    
    log "INFO" "AWS Account ID: $AWS_ACCOUNT_ID"
    log "INFO" "AWS Region: $AWS_REGION"
    
    # Check required permissions by attempting to describe VPCs
    if ! aws ec2 describe-vpcs --max-items 1 &> /dev/null; then
        error_exit "Insufficient permissions. This script requires VPC, EC2, ELB, Route53, IAM, and CloudWatch Logs permissions."
    fi
    
    log "INFO" "Prerequisites check completed successfully"
}

# AWS CLI wrapper for dry run support
aws_exec() {
    local service="$1"
    shift
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would execute: aws $service $*"
        return 0
    else
        log "DEBUG" "Executing: aws $service $*"
        aws "$service" "$@"
    fi
}

# Wait for resource to be available
wait_for_resource() {
    local waiter_type="$1"
    local resource_id="$2"
    local timeout="${3:-300}"  # Default 5 minutes
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would wait for $waiter_type: $resource_id"
        return 0
    fi
    
    log "INFO" "Waiting for $waiter_type to be available: $resource_id"
    
    case "$waiter_type" in
        "vpc-endpoint")
            aws ec2 wait vpc-endpoint-available --vpc-endpoint-ids "$resource_id" --cli-read-timeout $timeout || \
                error_exit "Timeout waiting for VPC endpoint $resource_id to be available"
            ;;
        "load-balancer")
            aws elbv2 wait load-balancer-available --load-balancer-arns "$resource_id" --cli-read-timeout $timeout || \
                error_exit "Timeout waiting for load balancer $resource_id to be available"
            ;;
        *)
            log "WARN" "Unknown waiter type: $waiter_type"
            ;;
    esac
}

# Generate unique resource names
generate_resource_names() {
    log "INFO" "Generating unique resource names..."
    
    local random_suffix
    if [[ "$DRY_RUN" == "true" ]]; then
        random_suffix="dry123"
    else
        random_suffix=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    fi
    
    export VPC_NAME="zero-trust-vpc-${random_suffix}"
    export PROVIDER_VPC_NAME="provider-vpc-${random_suffix}"
    export ENDPOINT_SERVICE_NAME="zero-trust-service-${random_suffix}"
    export RANDOM_SUFFIX="$random_suffix"
    
    log "INFO" "Resource suffix: $random_suffix"
    log "DEBUG" "VPC Name: $VPC_NAME"
    log "DEBUG" "Provider VPC Name: $PROVIDER_VPC_NAME"
}

# Create foundational VPCs
create_vpcs() {
    log "INFO" "Creating foundational VPCs for zero trust architecture..."
    
    # Create consumer VPC
    export VPC_ID=$(aws_exec ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --enable-dns-support \
        --enable-dns-hostnames \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}},{Key=Environment,Value=ZeroTrust},{Key=Project,Value=ZeroTrustArchitecture}]" \
        --query 'Vpc.VpcId' --output text)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "INFO" "Created consumer VPC: $VPC_ID"
    fi
    
    # Create provider VPC
    export PROVIDER_VPC_ID=$(aws_exec ec2 create-vpc \
        --cidr-block 10.1.0.0/16 \
        --enable-dns-support \
        --enable-dns-hostnames \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROVIDER_VPC_NAME}},{Key=Environment,Value=Provider},{Key=Project,Value=ZeroTrustArchitecture}]" \
        --query 'Vpc.VpcId' --output text)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "INFO" "Created provider VPC: $PROVIDER_VPC_ID"
    fi
}

# Create private subnets
create_subnets() {
    log "INFO" "Creating private subnets for zero trust architecture..."
    
    # Create first private subnet in consumer VPC
    export PRIVATE_SUBNET_1=$(aws_exec ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=ZeroTrust-Private-1},{Key=Type,Value=Private},{Key=Project,Value=ZeroTrustArchitecture}]" \
        --query 'Subnet.SubnetId' --output text)
    
    # Create second private subnet for multi-AZ deployment
    export PRIVATE_SUBNET_2=$(aws_exec ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.2.0/24 \
        --availability-zone "${AWS_REGION}b" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=ZeroTrust-Private-2},{Key=Type,Value=Private},{Key=Project,Value=ZeroTrustArchitecture}]" \
        --query 'Subnet.SubnetId' --output text)
    
    # Create provider subnet
    export PROVIDER_SUBNET=$(aws_exec ec2 create-subnet \
        --vpc-id "${PROVIDER_VPC_ID}" \
        --cidr-block 10.1.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Provider-Subnet},{Key=Type,Value=Private},{Key=Project,Value=ZeroTrustArchitecture}]" \
        --query 'Subnet.SubnetId' --output text)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "INFO" "Created private subnets: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2, $PROVIDER_SUBNET"
    fi
}

# Create security groups with least privilege access
create_security_groups() {
    log "INFO" "Creating security groups with least privilege access..."
    
    # Create security group for VPC endpoints
    export ENDPOINT_SG=$(aws_exec ec2 create-security-group \
        --group-name "zero-trust-endpoint-sg-${RANDOM_SUFFIX}" \
        --description "Zero Trust VPC Endpoint Security Group" \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=ZeroTrustEndpointSG},{Key=Project,Value=ZeroTrustArchitecture}]" \
        --query 'GroupId' --output text)
    
    # Allow HTTPS traffic only from VPC CIDR
    aws_exec ec2 authorize-security-group-ingress \
        --group-id "${ENDPOINT_SG}" \
        --protocol tcp \
        --port 443 \
        --cidr 10.0.0.0/16
    
    # Create security group for application servers
    export APP_SG=$(aws_exec ec2 create-security-group \
        --group-name "zero-trust-app-sg-${RANDOM_SUFFIX}" \
        --description "Zero Trust Application Security Group" \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=ZeroTrustAppSG},{Key=Project,Value=ZeroTrustArchitecture}]" \
        --query 'GroupId' --output text)
    
    # Allow outbound HTTPS to VPC endpoints only
    aws_exec ec2 authorize-security-group-egress \
        --group-id "${APP_SG}" \
        --protocol tcp \
        --port 443 \
        --source-group "${ENDPOINT_SG}"
    
    # Remove default outbound rule
    aws_exec ec2 revoke-security-group-egress \
        --group-id "${APP_SG}" \
        --protocol all \
        --port all \
        --cidr 0.0.0.0/0 || true  # Don't fail if rule doesn't exist
    
    # Create provider security group
    export PROVIDER_SG=$(aws_exec ec2 create-security-group \
        --group-name "provider-service-sg-${RANDOM_SUFFIX}" \
        --description "Provider Service Security Group" \
        --vpc-id "${PROVIDER_VPC_ID}" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=ProviderServiceSG},{Key=Project,Value=ZeroTrustArchitecture}]" \
        --query 'GroupId' --output text)
    
    aws_exec ec2 authorize-security-group-ingress \
        --group-id "${PROVIDER_SG}" \
        --protocol tcp \
        --port 443 \
        --cidr 10.0.0.0/16
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "INFO" "Created security groups: $ENDPOINT_SG (endpoint), $APP_SG (app), $PROVIDER_SG (provider)"
    fi
}

# Create VPC endpoints for AWS services
create_vpc_endpoints() {
    log "INFO" "Creating interface VPC endpoints for AWS services..."
    
    # Create S3 interface endpoint
    export S3_ENDPOINT=$(aws_exec ec2 create-vpc-endpoint \
        --vpc-id "${VPC_ID}" \
        --service-name "com.amazonaws.${AWS_REGION}.s3" \
        --vpc-endpoint-type Interface \
        --subnet-ids "${PRIVATE_SUBNET_1}" "${PRIVATE_SUBNET_2}" \
        --security-group-ids "${ENDPOINT_SG}" \
        --private-dns-enabled \
        --policy-document "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Principal\": \"*\",
                    \"Action\": [
                        \"s3:GetObject\",
                        \"s3:PutObject\",
                        \"s3:ListBucket\"
                    ],
                    \"Resource\": \"*\",
                    \"Condition\": {
                        \"StringEquals\": {
                            \"aws:PrincipalAccount\": \"${AWS_ACCOUNT_ID}\"
                        }
                    }
                }
            ]
        }" \
        --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=S3-Endpoint},{Key=Service,Value=S3},{Key=Project,Value=ZeroTrustArchitecture}]" \
        --query 'VpcEndpoint.VpcEndpointId' --output text)
    
    # Create Lambda interface endpoint
    export LAMBDA_ENDPOINT=$(aws_exec ec2 create-vpc-endpoint \
        --vpc-id "${VPC_ID}" \
        --service-name "com.amazonaws.${AWS_REGION}.lambda" \
        --vpc-endpoint-type Interface \
        --subnet-ids "${PRIVATE_SUBNET_1}" "${PRIVATE_SUBNET_2}" \
        --security-group-ids "${ENDPOINT_SG}" \
        --private-dns-enabled \
        --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=Lambda-Endpoint},{Key=Service,Value=Lambda},{Key=Project,Value=ZeroTrustArchitecture}]" \
        --query 'VpcEndpoint.VpcEndpointId' --output text)
    
    # Create CloudWatch Logs endpoint
    export LOGS_ENDPOINT=$(aws_exec ec2 create-vpc-endpoint \
        --vpc-id "${VPC_ID}" \
        --service-name "com.amazonaws.${AWS_REGION}.logs" \
        --vpc-endpoint-type Interface \
        --subnet-ids "${PRIVATE_SUBNET_1}" "${PRIVATE_SUBNET_2}" \
        --security-group-ids "${ENDPOINT_SG}" \
        --private-dns-enabled \
        --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=Logs-Endpoint},{Key=Service,Value=CloudWatchLogs},{Key=Project,Value=ZeroTrustArchitecture}]" \
        --query 'VpcEndpoint.VpcEndpointId' --output text)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "INFO" "Created VPC endpoints: S3 ($S3_ENDPOINT), Lambda ($LAMBDA_ENDPOINT), Logs ($LOGS_ENDPOINT)"
        
        # Wait for endpoints to be available
        wait_for_resource "vpc-endpoint" "$S3_ENDPOINT"
        wait_for_resource "vpc-endpoint" "$LAMBDA_ENDPOINT"
        wait_for_resource "vpc-endpoint" "$LOGS_ENDPOINT"
    fi
}

# Create Network Load Balancer for PrivateLink
create_load_balancer() {
    log "INFO" "Creating Network Load Balancer for PrivateLink service..."
    
    # Create Network Load Balancer
    export NLB_ARN=$(aws_exec elbv2 create-load-balancer \
        --name "zero-trust-nlb-${RANDOM_SUFFIX}" \
        --type network \
        --scheme internal \
        --subnets "${PROVIDER_SUBNET}" \
        --security-groups "${PROVIDER_SG}" \
        --tags "Key=Name,Value=ZeroTrustNLB" "Key=Project,Value=ZeroTrustArchitecture" \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    # Create target group
    export TARGET_GROUP_ARN=$(aws_exec elbv2 create-target-group \
        --name "zero-trust-tg-${RANDOM_SUFFIX}" \
        --protocol TCP \
        --port 443 \
        --vpc-id "${PROVIDER_VPC_ID}" \
        --target-type ip \
        --health-check-protocol TCP \
        --health-check-port 443 \
        --tags "Key=Name,Value=ZeroTrustTargetGroup" "Key=Project,Value=ZeroTrustArchitecture" \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    # Create listener
    export LISTENER_ARN=$(aws_exec elbv2 create-listener \
        --load-balancer-arn "${NLB_ARN}" \
        --protocol TCP \
        --port 443 \
        --default-actions "Type=forward,TargetGroupArn=${TARGET_GROUP_ARN}" \
        --tags "Key=Name,Value=ZeroTrustListener" "Key=Project,Value=ZeroTrustArchitecture" \
        --query 'Listeners[0].ListenerArn' --output text)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "INFO" "Created Network Load Balancer: $NLB_ARN"
        wait_for_resource "load-balancer" "$NLB_ARN"
    fi
}

# Create VPC endpoint service
create_endpoint_service() {
    log "INFO" "Creating VPC endpoint service configuration..."
    
    # Create endpoint service
    export SERVICE_CONFIG=$(aws_exec ec2 create-vpc-endpoint-service-configuration \
        --network-load-balancer-arns "${NLB_ARN}" \
        --acceptance-required \
        --tag-specifications "ResourceType=vpc-endpoint-service,Tags=[{Key=Name,Value=ZeroTrustEndpointService},{Key=Project,Value=ZeroTrustArchitecture}]" \
        --query 'ServiceConfiguration.ServiceName' --output text)
    
    # Get service ID
    export SERVICE_ID=$(aws_exec ec2 describe-vpc-endpoint-service-configurations \
        --filters "Name=service-name,Values=${SERVICE_CONFIG}" \
        --query 'ServiceConfigurations[0].ServiceId' --output text)
    
    # Add permissions for consumer account
    aws_exec ec2 modify-vpc-endpoint-service-permissions \
        --service-id "${SERVICE_ID}" \
        --add-allowed-principals "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "INFO" "Created VPC endpoint service: $SERVICE_CONFIG"
    fi
}

# Create VPC endpoint to connect to PrivateLink service
create_custom_endpoint() {
    log "INFO" "Creating VPC endpoint for custom PrivateLink service..."
    
    # Create VPC endpoint for custom service
    export CUSTOM_ENDPOINT=$(aws_exec ec2 create-vpc-endpoint \
        --vpc-id "${VPC_ID}" \
        --service-name "${SERVICE_CONFIG}" \
        --vpc-endpoint-type Interface \
        --subnet-ids "${PRIVATE_SUBNET_1}" "${PRIVATE_SUBNET_2}" \
        --security-group-ids "${ENDPOINT_SG}" \
        --private-dns-enabled \
        --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=Custom-Service-Endpoint},{Key=Service,Value=CustomPrivateLink},{Key=Project,Value=ZeroTrustArchitecture}]" \
        --query 'VpcEndpoint.VpcEndpointId' --output text)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        wait_for_resource "vpc-endpoint" "$CUSTOM_ENDPOINT"
        
        # Accept the endpoint connection
        aws_exec ec2 accept-vpc-endpoint-connections \
            --service-id "${SERVICE_ID}" \
            --vpc-endpoint-ids "${CUSTOM_ENDPOINT}"
        
        log "INFO" "Created and accepted custom VPC endpoint: $CUSTOM_ENDPOINT"
    fi
}

# Configure private DNS resolution
configure_dns() {
    log "INFO" "Configuring private DNS resolution..."
    
    # Create private hosted zone
    export HOSTED_ZONE_ID=$(aws_exec route53 create-hosted-zone \
        --name "zero-trust-service.internal" \
        --caller-reference "zero-trust-$(date +%s)" \
        --vpc "VPCRegion=${AWS_REGION},VPCId=${VPC_ID}" \
        --hosted-zone-config "PrivateZone=true,Comment=Zero Trust Private DNS Zone" \
        --query 'HostedZone.Id' --output text | cut -d'/' -f3)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Get VPC endpoint DNS name
        export ENDPOINT_DNS=$(aws ec2 describe-vpc-endpoints \
            --vpc-endpoint-ids "${CUSTOM_ENDPOINT}" \
            --query 'VpcEndpoints[0].DnsEntries[0].DnsName' --output text)
        
        # Create DNS record for service discovery
        aws_exec route53 change-resource-record-sets \
            --hosted-zone-id "${HOSTED_ZONE_ID}" \
            --change-batch "{
                \"Changes\": [
                    {
                        \"Action\": \"CREATE\",
                        \"ResourceRecordSet\": {
                            \"Name\": \"api.zero-trust-service.internal\",
                            \"Type\": \"CNAME\",
                            \"TTL\": 300,
                            \"ResourceRecords\": [
                                {
                                    \"Value\": \"${ENDPOINT_DNS}\"
                                }
                            ]
                        }
                    }
                ]
            }"
        
        log "INFO" "Configured private DNS resolution with hosted zone: $HOSTED_ZONE_ID"
    fi
}

# Configure route tables
configure_routing() {
    log "INFO" "Configuring route tables with no internet access..."
    
    # Create custom route table for consumer VPC
    export ROUTE_TABLE_ID=$(aws_exec ec2 create-route-table \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=ZeroTrust-RouteTable},{Key=Project,Value=ZeroTrustArchitecture}]" \
        --query 'RouteTable.RouteTableId' --output text)
    
    # Associate route table with private subnets
    aws_exec ec2 associate-route-table \
        --route-table-id "${ROUTE_TABLE_ID}" \
        --subnet-id "${PRIVATE_SUBNET_1}"
    
    aws_exec ec2 associate-route-table \
        --route-table-id "${ROUTE_TABLE_ID}" \
        --subnet-id "${PRIVATE_SUBNET_2}"
    
    # Create provider route table
    export PROVIDER_ROUTE_TABLE=$(aws_exec ec2 create-route-table \
        --vpc-id "${PROVIDER_VPC_ID}" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=Provider-RouteTable},{Key=Project,Value=ZeroTrustArchitecture}]" \
        --query 'RouteTable.RouteTableId' --output text)
    
    aws_exec ec2 associate-route-table \
        --route-table-id "${PROVIDER_ROUTE_TABLE}" \
        --subnet-id "${PROVIDER_SUBNET}"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "INFO" "Configured route tables: $ROUTE_TABLE_ID (consumer), $PROVIDER_ROUTE_TABLE (provider)"
    fi
}

# Enable VPC Flow Logs
enable_flow_logs() {
    log "INFO" "Enabling VPC Flow Logs for network monitoring..."
    
    # Create IAM role for VPC Flow Logs
    export FLOW_LOGS_ROLE=$(aws_exec iam create-role \
        --role-name "VPCFlowLogsRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Principal\": {
                        \"Service\": \"vpc-flow-logs.amazonaws.com\"
                    },
                    \"Action\": \"sts:AssumeRole\"
                }
            ]
        }" \
        --tags "Key=Name,Value=VPCFlowLogsRole" "Key=Project,Value=ZeroTrustArchitecture" \
        --query 'Role.Arn' --output text)
    
    # Attach policy for CloudWatch Logs
    aws_exec iam attach-role-policy \
        --role-name "VPCFlowLogsRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/VPCFlowLogsDeliveryRolePolicy"
    
    # Create CloudWatch log group
    export LOG_GROUP_NAME="/aws/vpc/zero-trust-flowlogs-${RANDOM_SUFFIX}"
    aws_exec logs create-log-group \
        --log-group-name "${LOG_GROUP_NAME}" \
        --tags "Project=ZeroTrustArchitecture,Component=VPCFlowLogs"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Wait for IAM role to propagate
        sleep 10
        
        # Create VPC Flow Logs
        export FLOW_LOGS_ID=$(aws_exec ec2 create-flow-logs \
            --resource-type VPC \
            --resource-ids "${VPC_ID}" \
            --traffic-type ALL \
            --log-destination-type cloud-watch-logs \
            --log-group-name "${LOG_GROUP_NAME}" \
            --deliver-logs-permission-arn "${FLOW_LOGS_ROLE}" \
            --tag-specifications "ResourceType=vpc-flow-log,Tags=[{Key=Name,Value=ZeroTrustFlowLogs},{Key=Project,Value=ZeroTrustArchitecture}]" \
            --query 'FlowLogIds[0]' --output text)
        
        log "INFO" "Enabled VPC Flow Logs: $FLOW_LOGS_ID"
    fi
}

# Create test Lambda function
create_test_function() {
    log "INFO" "Creating test Lambda function for validation..."
    
    # Create Lambda execution role
    export LAMBDA_ROLE=$(aws_exec iam create-role \
        --role-name "ZeroTrustLambdaRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Principal\": {
                        \"Service\": \"lambda.amazonaws.com\"
                    },
                    \"Action\": \"sts:AssumeRole\"
                }
            ]
        }" \
        --tags "Key=Name,Value=ZeroTrustLambdaRole" "Key=Project,Value=ZeroTrustArchitecture" \
        --query 'Role.Arn' --output text)
    
    # Attach VPC execution policy
    aws_exec iam attach-role-policy \
        --role-name "ZeroTrustLambdaRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
    
    # Attach S3 read policy for testing
    aws_exec iam attach-role-policy \
        --role-name "ZeroTrustLambdaRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Create Lambda function code
        local temp_dir=$(mktemp -d)
        cat > "${temp_dir}/lambda_function.py" << 'EOF'
import json
import boto3
import urllib3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Test function to validate zero trust connectivity"""
    results = {
        'message': 'Zero Trust validation complete',
        's3_access': False,
        'internet_access': False,
        'vpc_endpoint_working': False
    }
    
    try:
        # Test S3 access through VPC endpoint
        s3_client = boto3.client('s3')
        buckets = s3_client.list_buckets()
        results['s3_access'] = len(buckets['Buckets']) >= 0
        results['vpc_endpoint_working'] = True
        logger.info(f"S3 access successful: {len(buckets['Buckets'])} buckets found")
        
    except Exception as e:
        logger.error(f"S3 access failed: {str(e)}")
        results['s3_access'] = False
    
    try:
        # Test external HTTP request (should fail in zero trust)
        http = urllib3.PoolManager()
        response = http.request('GET', 'https://httpbin.org/get', timeout=5)
        results['internet_access'] = True
        logger.warning("Internet access successful - zero trust policy violation!")
        
    except Exception as e:
        logger.info(f"Internet access blocked as expected: {str(e)}")
        results['internet_access'] = False
    
    return {
        'statusCode': 200,
        'body': json.dumps(results, indent=2)
    }
EOF
        
        # Create deployment package
        cd "${temp_dir}" && zip lambda_function.zip lambda_function.py
        
        # Wait for IAM role to propagate
        sleep 15
        
        export LAMBDA_FUNCTION_NAME="zero-trust-test-${RANDOM_SUFFIX}"
        
        # Deploy Lambda function
        aws_exec lambda create-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime python3.9 \
            --role "${LAMBDA_ROLE}" \
            --handler lambda_function.lambda_handler \
            --code "fileb://${temp_dir}/lambda_function.zip" \
            --vpc-config "SubnetIds=${PRIVATE_SUBNET_1},SecurityGroupIds=${APP_SG}" \
            --timeout 30 \
            --tags "Project=ZeroTrustArchitecture,Component=TestFunction" \
            --description "Test function for zero trust connectivity validation"
        
        # Cleanup temp directory
        rm -rf "${temp_dir}"
        
        log "INFO" "Created test Lambda function: $LAMBDA_FUNCTION_NAME"
    fi
}

# Save deployment state
save_deployment_state() {
    local state_file="${SCRIPT_DIR}/deployment-state.json"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would save deployment state to: $state_file"
        return
    fi
    
    log "INFO" "Saving deployment state to: $state_file"
    
    cat > "$state_file" << EOF
{
    "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "aws_region": "${AWS_REGION}",
    "random_suffix": "${RANDOM_SUFFIX}",
    "vpc_id": "${VPC_ID}",
    "provider_vpc_id": "${PROVIDER_VPC_ID}",
    "private_subnet_1": "${PRIVATE_SUBNET_1}",
    "private_subnet_2": "${PRIVATE_SUBNET_2}",
    "provider_subnet": "${PROVIDER_SUBNET}",
    "endpoint_sg": "${ENDPOINT_SG}",
    "app_sg": "${APP_SG}",
    "provider_sg": "${PROVIDER_SG}",
    "s3_endpoint": "${S3_ENDPOINT}",
    "lambda_endpoint": "${LAMBDA_ENDPOINT}",
    "logs_endpoint": "${LOGS_ENDPOINT}",
    "nlb_arn": "${NLB_ARN}",
    "target_group_arn": "${TARGET_GROUP_ARN}",
    "listener_arn": "${LISTENER_ARN}",
    "service_config": "${SERVICE_CONFIG}",
    "service_id": "${SERVICE_ID}",
    "custom_endpoint": "${CUSTOM_ENDPOINT}",
    "hosted_zone_id": "${HOSTED_ZONE_ID}",
    "endpoint_dns": "${ENDPOINT_DNS}",
    "route_table_id": "${ROUTE_TABLE_ID}",
    "provider_route_table": "${PROVIDER_ROUTE_TABLE}",
    "flow_logs_role": "${FLOW_LOGS_ROLE}",
    "log_group_name": "${LOG_GROUP_NAME}",
    "flow_logs_id": "${FLOW_LOGS_ID}",
    "lambda_role": "${LAMBDA_ROLE}",
    "lambda_function_name": "${LAMBDA_FUNCTION_NAME}"
}
EOF
    
    log "INFO" "Deployment state saved successfully"
}

# Main deployment function
main() {
    log "INFO" "========================================="
    log "INFO" "Zero Trust Network Architecture Deployment"
    log "INFO" "========================================="
    
    check_prerequisites
    generate_resource_names
    
    log "INFO" "Starting infrastructure deployment..."
    
    create_vpcs
    create_subnets
    create_security_groups
    create_vpc_endpoints
    create_load_balancer
    create_endpoint_service
    create_custom_endpoint
    configure_dns
    configure_routing
    enable_flow_logs
    create_test_function
    
    save_deployment_state
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "========================================="
        log "INFO" "DRY RUN COMPLETED SUCCESSFULLY"
        log "INFO" "========================================="
        log "INFO" "No resources were actually created."
        log "INFO" "Run without --dry-run to deploy the infrastructure."
    else
        log "INFO" "========================================="
        log "INFO" "DEPLOYMENT COMPLETED SUCCESSFULLY"
        log "INFO" "========================================="
        log "INFO" "Zero trust network architecture has been deployed successfully!"
        log "INFO" ""
        log "INFO" "Key Resources Created:"
        log "INFO" "  - Consumer VPC: $VPC_ID"
        log "INFO" "  - Provider VPC: $PROVIDER_VPC_ID"
        log "INFO" "  - VPC Endpoints: S3, Lambda, CloudWatch Logs, Custom Service"
        log "INFO" "  - Network Load Balancer: $NLB_ARN"
        log "INFO" "  - Test Lambda Function: $LAMBDA_FUNCTION_NAME"
        log "INFO" ""
        log "INFO" "Next Steps:"
        log "INFO" "  1. Test the deployment: aws lambda invoke --function-name $LAMBDA_FUNCTION_NAME response.json"
        log "INFO" "  2. Review VPC Flow Logs in CloudWatch"
        log "INFO" "  3. Validate zero trust connectivity patterns"
        log "INFO" ""
        log "INFO" "To clean up resources: ./destroy.sh"
        log "INFO" "Estimated monthly cost: \$40-60 (see --help for details)"
    fi
}

# Run main function
main "$@"