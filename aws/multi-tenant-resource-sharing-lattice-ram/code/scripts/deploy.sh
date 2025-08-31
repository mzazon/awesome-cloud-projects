#!/bin/bash

# Multi-Tenant Resource Sharing with VPC Lattice and RAM - Deployment Script
# This script deploys a complete multi-tenant architecture using VPC Lattice and AWS RAM
# for secure cross-account resource sharing with RDS database

set -euo pipefail

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

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Script metadata
SCRIPT_NAME="Multi-Tenant VPC Lattice Deploy"
SCRIPT_VERSION="1.0"
RECIPE_ID="f7e9d2a8"

log "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION} (Recipe ID: ${RECIPE_ID})"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: ${aws_version}"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure' or set appropriate environment variables."
    fi
    
    # Check jq installation
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some optional features may not work properly."
    fi
    
    # Verify required AWS permissions (basic check)
    log "Verifying AWS permissions..."
    aws sts get-caller-identity > /dev/null || error "Failed to verify AWS identity"
    
    # Check if we can create IAM roles (basic permission check)
    if ! aws iam list-roles --max-items 1 &> /dev/null; then
        error "Insufficient IAM permissions. Ensure you have permissions for IAM, VPC Lattice, AWS RAM, RDS, and EC2 operations."
    fi
    
    success "Prerequisites check completed"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set AWS region and account
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        warning "No AWS region configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export SERVICE_NETWORK_NAME="multitenant-network-${RANDOM_SUFFIX}"
    export RDS_INSTANCE_ID="shared-db-${RANDOM_SUFFIX}"
    export RAM_SHARE_NAME="database-share-${RANDOM_SUFFIX}"
    
    # Get default VPC
    export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "")
    
    if [[ "${VPC_ID}" == "None" ]] || [[ -z "${VPC_ID}" ]]; then
        # If no default VPC, get the first available VPC
        export VPC_ID=$(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "")
        if [[ "${VPC_ID}" == "None" ]] || [[ -z "${VPC_ID}" ]]; then
            error "No VPC found. Please ensure you have a VPC available in the region."
        fi
        warning "No default VPC found, using VPC: ${VPC_ID}"
    fi
    
    log "Region: ${AWS_REGION}"
    log "Account ID: ${AWS_ACCOUNT_ID}"
    log "VPC ID: ${VPC_ID}"
    log "Resource suffix: ${RANDOM_SUFFIX}"
    
    success "Environment initialized"
}

# Create IAM role for VPC Lattice
create_lattice_role() {
    log "Creating VPC Lattice service role..."
    
    local role_name="VPCLatticeServiceRole-${RANDOM_SUFFIX}"
    
    # Check if role already exists
    if aws iam get-role --role-name "${role_name}" &> /dev/null; then
        warning "Role ${role_name} already exists, skipping creation"
        return 0
    fi
    
    aws iam create-role \
        --role-name "${role_name}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "vpc-lattice.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        --tags Key=Project,Value=MultiTenantLattice Key=CreatedBy,Value=DeployScript \
        > /dev/null
    
    success "VPC Lattice service role created: ${role_name}"
}

# Create VPC Lattice Service Network
create_service_network() {
    log "Creating VPC Lattice service network..."
    
    # Check if service network already exists
    local existing_network=$(aws vpc-lattice list-service-networks \
        --query "items[?name=='${SERVICE_NETWORK_NAME}'].id" --output text 2>/dev/null || echo "")
    
    if [[ -n "${existing_network}" ]]; then
        warning "Service network ${SERVICE_NETWORK_NAME} already exists"
        export SERVICE_NETWORK_ID="${existing_network}"
        export SERVICE_NETWORK_ARN="arn:aws:vpc-lattice:${AWS_REGION}:${AWS_ACCOUNT_ID}:servicenetwork/${SERVICE_NETWORK_ID}"
        return 0
    fi
    
    export SERVICE_NETWORK_ARN=$(aws vpc-lattice create-service-network \
        --name "${SERVICE_NETWORK_NAME}" \
        --auth-type IAM \
        --tags Key=Project,Value=MultiTenantLattice Key=CreatedBy,Value=DeployScript \
        --query "arn" --output text)
    
    export SERVICE_NETWORK_ID=$(echo "${SERVICE_NETWORK_ARN}" | awk -F'/' '{print $NF}')
    
    success "Service network created: ${SERVICE_NETWORK_ID}"
}

# Associate VPC with Service Network
associate_vpc() {
    log "Associating VPC with service network..."
    
    # Check if association already exists
    local existing_assoc=$(aws vpc-lattice list-service-network-vpc-associations \
        --service-network-identifier "${SERVICE_NETWORK_ID}" \
        --query "items[?vpcId=='${VPC_ID}'].id" --output text 2>/dev/null || echo "")
    
    if [[ -n "${existing_assoc}" ]]; then
        warning "VPC association already exists"
        export VPC_ASSOCIATION_ARN="arn:aws:vpc-lattice:${AWS_REGION}:${AWS_ACCOUNT_ID}:servicenetworkvpcassociation/${existing_assoc}"
        return 0
    fi
    
    export VPC_ASSOCIATION_ARN=$(aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier "${SERVICE_NETWORK_ID}" \
        --vpc-identifier "${VPC_ID}" \
        --tags Key=Project,Value=MultiTenantLattice Key=CreatedBy,Value=DeployScript \
        --query "arn" --output text)
    
    # Wait for association to complete
    log "Waiting for VPC association to complete..."
    local max_attempts=30
    local attempt=0
    
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        local status=$(aws vpc-lattice get-service-network-vpc-association \
            --service-network-vpc-association-identifier "${VPC_ASSOCIATION_ARN}" \
            --query "status" --output text 2>/dev/null || echo "CREATING")
        
        if [[ "${status}" == "ACTIVE" ]]; then
            break
        elif [[ "${status}" == "FAILED" ]]; then
            error "VPC association failed"
        fi
        
        log "Association status: ${status}. Waiting... (${attempt}/${max_attempts})"
        sleep 10
        ((attempt++))
    done
    
    if [[ ${attempt} -eq ${max_attempts} ]]; then
        error "Timeout waiting for VPC association to complete"
    fi
    
    success "VPC associated with service network"
}

# Create RDS resources
create_rds_resources() {
    log "Creating RDS database resources..."
    
    # Check if RDS instance already exists
    if aws rds describe-db-instances --db-instance-identifier "${RDS_INSTANCE_ID}" &> /dev/null; then
        warning "RDS instance ${RDS_INSTANCE_ID} already exists"
        return 0
    fi
    
    # Create DB subnet group
    local subnet_group_name="shared-db-subnet-${RANDOM_SUFFIX}"
    
    if ! aws rds describe-db-subnet-groups --db-subnet-group-name "${subnet_group_name}" &> /dev/null; then
        log "Creating DB subnet group..."
        
        local subnets=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query "Subnets[0:2].SubnetId" \
            --output text | tr '\t' ' ')
        
        if [[ -z "${subnets}" ]] || [[ "${subnets}" == "None" ]]; then
            error "No subnets found in VPC ${VPC_ID}"
        fi
        
        aws rds create-db-subnet-group \
            --db-subnet-group-name "${subnet_group_name}" \
            --db-subnet-group-description "Shared database subnet group" \
            --subnet-ids ${subnets} \
            --tags Key=Project,Value=MultiTenantLattice Key=CreatedBy,Value=DeployScript \
            > /dev/null
        
        success "DB subnet group created: ${subnet_group_name}"
    fi
    
    # Create security group for RDS
    local sg_name="shared-db-sg-${RANDOM_SUFFIX}"
    
    if ! aws ec2 describe-security-groups --filters "Name=group-name,Values=${sg_name}" &> /dev/null; then
        log "Creating security group for RDS..."
        
        export SG_ID=$(aws ec2 create-security-group \
            --group-name "${sg_name}" \
            --description "Security group for shared database" \
            --vpc-id "${VPC_ID}" \
            --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=MultiTenantLattice},{Key=CreatedBy,Value=DeployScript}]" \
            --query "GroupId" --output text)
        
        # Allow MySQL/Aurora access from within the VPC
        aws ec2 authorize-security-group-ingress \
            --group-id "${SG_ID}" \
            --protocol tcp \
            --port 3306 \
            --source-group "${SG_ID}" \
            > /dev/null
        
        success "Security group created: ${SG_ID}"
    else
        export SG_ID=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=${sg_name}" \
            --query "SecurityGroups[0].GroupId" --output text)
        warning "Security group ${sg_name} already exists: ${SG_ID}"
    fi
    
    # Create RDS instance
    log "Creating RDS instance (this may take several minutes)..."
    
    aws rds create-db-instance \
        --db-instance-identifier "${RDS_INSTANCE_ID}" \
        --db-instance-class db.t3.micro \
        --engine mysql \
        --master-username admin \
        --master-user-password "TempPassword123!" \
        --allocated-storage 20 \
        --vpc-security-group-ids "${SG_ID}" \
        --db-subnet-group-name "${subnet_group_name}" \
        --no-publicly-accessible \
        --storage-encrypted \
        --backup-retention-period 7 \
        --tags Key=Environment,Value=Multi-Tenant Key=Purpose,Value=SharedResource Key=Project,Value=MultiTenantLattice Key=CreatedBy,Value=DeployScript \
        > /dev/null
    
    success "RDS instance creation initiated: ${RDS_INSTANCE_ID}"
}

# Wait for RDS instance to be available
wait_for_rds() {
    log "Waiting for RDS instance to become available (this may take 5-10 minutes)..."
    
    # Check current status first
    local current_status=$(aws rds describe-db-instances \
        --db-instance-identifier "${RDS_INSTANCE_ID}" \
        --query "DBInstances[0].DBInstanceStatus" --output text 2>/dev/null || echo "creating")
    
    if [[ "${current_status}" == "available" ]]; then
        success "RDS instance is already available"
        return 0
    fi
    
    aws rds wait db-instance-available --db-instance-identifier "${RDS_INSTANCE_ID}"
    
    export RDS_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "${RDS_INSTANCE_ID}" \
        --query "DBInstances[0].Endpoint.Address" \
        --output text)
    
    success "RDS instance available at: ${RDS_ENDPOINT}"
}

# Create resource configuration
create_resource_configuration() {
    log "Creating resource configuration for RDS..."
    
    local resource_name="shared-database-${RANDOM_SUFFIX}"
    
    # Check if resource configuration already exists
    local existing_config=$(aws vpc-lattice list-resource-configurations \
        --query "items[?name=='${resource_name}'].id" --output text 2>/dev/null || echo "")
    
    if [[ -n "${existing_config}" ]]; then
        warning "Resource configuration ${resource_name} already exists"
        export RESOURCE_CONFIG_ID="${existing_config}"
        export RESOURCE_CONFIG_ARN="arn:aws:vpc-lattice:${AWS_REGION}:${AWS_ACCOUNT_ID}:resourceconfiguration/${RESOURCE_CONFIG_ID}"
        return 0
    fi
    
    export RESOURCE_CONFIG_ARN=$(aws vpc-lattice create-resource-configuration \
        --name "${resource_name}" \
        --type SINGLE \
        --resource-gateway-identifier "${VPC_ID}" \
        --resource-configuration-definition "ipResource={ipAddress=${RDS_ENDPOINT}}" \
        --port-ranges "3306" \
        --protocol TCP \
        --allow-association-to-shareable-service-network \
        --tags Key=Project,Value=MultiTenantLattice Key=CreatedBy,Value=DeployScript \
        --query "arn" --output text)
    
    export RESOURCE_CONFIG_ID=$(echo "${RESOURCE_CONFIG_ARN}" | awk -F'/' '{print $NF}')
    
    success "Resource configuration created: ${RESOURCE_CONFIG_ID}"
}

# Associate resource configuration with service network
associate_resource_config() {
    log "Associating resource configuration with service network..."
    
    # Check if association already exists
    local existing_assoc=$(aws vpc-lattice list-resource-configuration-associations \
        --resource-configuration-identifier "${RESOURCE_CONFIG_ID}" \
        --query "items[?serviceNetworkId=='${SERVICE_NETWORK_ID}'].id" --output text 2>/dev/null || echo "")
    
    if [[ -n "${existing_assoc}" ]]; then
        warning "Resource configuration association already exists"
        return 0
    fi
    
    export RESOURCE_ASSOC_ARN=$(aws vpc-lattice create-resource-configuration-association \
        --resource-configuration-identifier "${RESOURCE_CONFIG_ID}" \
        --service-network-identifier "${SERVICE_NETWORK_ID}" \
        --tags Key=Project,Value=MultiTenantLattice Key=CreatedBy,Value=DeployScript \
        --query "arn" --output text)
    
    # Wait for association to be ready
    log "Waiting for resource configuration association..."
    sleep 30
    
    success "Resource configuration associated with service network"
}

# Create AWS RAM resource share
create_ram_share() {
    log "Creating AWS RAM resource share..."
    
    # Check if resource share already exists
    local existing_share=$(aws ram get-resource-shares \
        --name "${RAM_SHARE_NAME}" \
        --resource-owner SELF \
        --query "resourceShares[0].resourceShareArn" --output text 2>/dev/null || echo "None")
    
    if [[ "${existing_share}" != "None" ]] && [[ -n "${existing_share}" ]]; then
        warning "Resource share ${RAM_SHARE_NAME} already exists"
        export RESOURCE_SHARE_ARN="${existing_share}"
        return 0
    fi
    
    # Get organization ID if available, otherwise use account ID
    local org_id=$(aws organizations describe-organization --query "Organization.Id" --output text 2>/dev/null || echo "")
    local principals
    
    if [[ -n "${org_id}" ]] && [[ "${org_id}" != "None" ]]; then
        principals="${org_id}"
        log "Using organization ID for sharing: ${org_id}"
    else
        principals="${AWS_ACCOUNT_ID}"
        warning "No organization found, sharing with current account only"
    fi
    
    export RESOURCE_SHARE_ARN=$(aws ram create-resource-share \
        --name "${RAM_SHARE_NAME}" \
        --resource-arns "${SERVICE_NETWORK_ARN}" \
        --principals "${principals}" \
        --allow-external-principals false \
        --tags Key=Purpose,Value=MultiTenantSharing Key=Project,Value=MultiTenantLattice Key=CreatedBy,Value=DeployScript \
        --query "resourceShare.resourceShareArn" --output text)
    
    success "AWS RAM resource share created: ${RESOURCE_SHARE_ARN}"
}

# Create authentication policy
create_auth_policy() {
    log "Creating authentication policy for multi-tenant access..."
    
    # Create comprehensive auth policy
    cat > /tmp/auth-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "vpc-lattice-svcs:Invoke",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:PrincipalTag/Team": ["TeamA", "TeamB"]
        },
        "DateGreaterThan": {
          "aws:CurrentTime": "2025-01-01T00:00:00Z"
        },
        "IpAddress": {
          "aws:SourceIp": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
      },
      "Action": "vpc-lattice-svcs:Invoke",
      "Resource": "*"
    }
  ]
}
EOF
    
    # Apply auth policy to service network
    aws vpc-lattice put-auth-policy \
        --resource-identifier "${SERVICE_NETWORK_ID}" \
        --policy file:///tmp/auth-policy.json \
        > /dev/null
    
    # Clean up temporary file
    rm -f /tmp/auth-policy.json
    
    success "Authentication policy applied to service network"
}

# Create IAM roles for different tenants
create_tenant_roles() {
    log "Creating IAM roles for different tenant teams..."
    
    # Create IAM role for Team A
    local team_a_role="TeamA-DatabaseAccess-${RANDOM_SUFFIX}"
    if ! aws iam get-role --role-name "${team_a_role}" &> /dev/null; then
        aws iam create-role \
            --role-name "${team_a_role}" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Principal": {"AWS": "arn:aws:iam::'${AWS_ACCOUNT_ID}':root"},
                    "Action": "sts:AssumeRole",
                    "Condition": {
                        "StringEquals": {
                            "sts:ExternalId": "TeamA-Access"
                        }
                    }
                }]
            }' \
            --tags Key=Team,Value=TeamA Key=Purpose,Value=DatabaseAccess Key=Project,Value=MultiTenantLattice Key=CreatedBy,Value=DeployScript \
            > /dev/null
        
        success "Team A role created: ${team_a_role}"
    else
        warning "Team A role already exists: ${team_a_role}"
    fi
    
    # Create IAM role for Team B
    local team_b_role="TeamB-DatabaseAccess-${RANDOM_SUFFIX}"
    if ! aws iam get-role --role-name "${team_b_role}" &> /dev/null; then
        aws iam create-role \
            --role-name "${team_b_role}" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Principal": {"AWS": "arn:aws:iam::'${AWS_ACCOUNT_ID}':root"},
                    "Action": "sts:AssumeRole",
                    "Condition": {
                        "StringEquals": {
                            "sts:ExternalId": "TeamB-Access"
                        }
                    }
                }]
            }' \
            --tags Key=Team,Value=TeamB Key=Purpose,Value=DatabaseAccess Key=Project,Value=MultiTenantLattice Key=CreatedBy,Value=DeployScript \
            > /dev/null
        
        success "Team B role created: ${team_b_role}"
    else
        warning "Team B role already exists: ${team_b_role}"
    fi
    
    # Attach VPC Lattice invoke policy to both roles
    aws iam attach-role-policy \
        --role-name "${team_a_role}" \
        --policy-arn arn:aws:iam::aws:policy/VPCLatticeServicesInvokeAccess \
        > /dev/null 2>&1 || warning "Policy already attached to Team A role"
    
    aws iam attach-role-policy \
        --role-name "${team_b_role}" \
        --policy-arn arn:aws:iam::aws:policy/VPCLatticeServicesInvokeAccess \
        > /dev/null 2>&1 || warning "Policy already attached to Team B role"
    
    success "IAM roles configured for tenant teams"
}

# Configure CloudTrail for audit logging
configure_cloudtrail() {
    log "Configuring CloudTrail for audit logging..."
    
    local trail_bucket="lattice-audit-logs-${RANDOM_SUFFIX}"
    local trail_name="VPCLatticeAuditTrail-${RANDOM_SUFFIX}"
    
    # Check if trail already exists
    if aws cloudtrail describe-trails --trail-name-list "${trail_name}" &> /dev/null; then
        warning "CloudTrail ${trail_name} already exists"
        return 0
    fi
    
    # Create S3 bucket for CloudTrail logs
    if ! aws s3api head-bucket --bucket "${trail_bucket}" &> /dev/null; then
        log "Creating S3 bucket for CloudTrail logs..."
        
        if [[ "${AWS_REGION}" == "us-east-1" ]]; then
            aws s3api create-bucket --bucket "${trail_bucket}"
        else
            aws s3api create-bucket \
                --bucket "${trail_bucket}" \
                --create-bucket-configuration LocationConstraint="${AWS_REGION}"
        fi
        
        # Apply bucket policy for CloudTrail access
        cat > /tmp/bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${trail_bucket}/AWSLogs/${AWS_ACCOUNT_ID}/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control"
                }
            }
        },
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:GetBucketAcl",
            "Resource": "arn:aws:s3:::${trail_bucket}"
        }
    ]
}
EOF
        
        # Apply the bucket policy
        aws s3api put-bucket-policy \
            --bucket "${trail_bucket}" \
            --policy file:///tmp/bucket-policy.json
        
        # Clean up policy file
        rm -f /tmp/bucket-policy.json
        
        success "S3 bucket created for CloudTrail: ${trail_bucket}"
    else
        warning "S3 bucket ${trail_bucket} already exists"
    fi
    
    # Create CloudTrail
    aws cloudtrail create-trail \
        --name "${trail_name}" \
        --s3-bucket-name "${trail_bucket}" \
        --include-global-service-events \
        --is-multi-region-trail \
        --enable-log-file-validation \
        --tags-list Key=Project,Value=MultiTenantLattice Key=CreatedBy,Value=DeployScript \
        > /dev/null
    
    # Start logging
    aws cloudtrail start-logging --name "${trail_name}" > /dev/null
    
    success "CloudTrail configured for comprehensive audit logging"
}

# Save deployment state
save_deployment_state() {
    log "Saving deployment state..."
    
    local state_file="/tmp/lattice-deployment-state-${RANDOM_SUFFIX}.json"
    
    cat > "${state_file}" << EOF
{
  "deployment_id": "${RANDOM_SUFFIX}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "aws_region": "${AWS_REGION}",
  "aws_account_id": "${AWS_ACCOUNT_ID}",
  "vpc_id": "${VPC_ID}",
  "service_network_name": "${SERVICE_NETWORK_NAME}",
  "service_network_id": "${SERVICE_NETWORK_ID:-}",
  "service_network_arn": "${SERVICE_NETWORK_ARN:-}",
  "rds_instance_id": "${RDS_INSTANCE_ID}",
  "rds_endpoint": "${RDS_ENDPOINT:-}",
  "ram_share_name": "${RAM_SHARE_NAME}",
  "resource_share_arn": "${RESOURCE_SHARE_ARN:-}",
  "resource_config_id": "${RESOURCE_CONFIG_ID:-}",
  "security_group_id": "${SG_ID:-}",
  "vpc_association_arn": "${VPC_ASSOCIATION_ARN:-}",
  "resource_assoc_arn": "${RESOURCE_ASSOC_ARN:-}"
}
EOF
    
    log "Deployment state saved to: ${state_file}"
    warning "Save this file - you'll need it for cleanup!"
}

# Deployment summary
deployment_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Service Network: ${SERVICE_NETWORK_NAME}"
    echo "Service Network ID: ${SERVICE_NETWORK_ID}"
    echo "RDS Instance: ${RDS_INSTANCE_ID}"
    echo "RDS Endpoint: ${RDS_ENDPOINT}"
    echo "RAM Share: ${RAM_SHARE_NAME}"
    echo "AWS Region: ${AWS_REGION}"
    echo "Deployment ID: ${RANDOM_SUFFIX}"
    echo "===================="
    
    success "Multi-tenant resource sharing architecture deployed successfully!"
    
    echo
    log "Next Steps:"
    echo "1. Test role assumption with: aws sts assume-role --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/TeamA-DatabaseAccess-${RANDOM_SUFFIX} --role-session-name test --external-id TeamA-Access"
    echo "2. Verify service network: aws vpc-lattice get-service-network --service-network-identifier ${SERVICE_NETWORK_ID}"
    echo "3. Check resource configuration: aws vpc-lattice list-resource-configurations"
    echo "4. Review CloudTrail logs for audit trails"
    echo "5. Run './destroy.sh' when you're done testing to clean up resources"
}

# Main deployment function
main() {
    log "Starting multi-tenant resource sharing deployment..."
    
    check_prerequisites
    initialize_environment
    create_lattice_role
    create_service_network
    associate_vpc
    create_rds_resources
    wait_for_rds
    create_resource_configuration
    associate_resource_config
    create_ram_share
    create_auth_policy
    create_tenant_roles
    configure_cloudtrail
    save_deployment_state
    deployment_summary
    
    success "Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may have been created. Check AWS console for cleanup."' INT TERM

# Run main function
main "$@"