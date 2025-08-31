#!/bin/bash

# Standardized Service Deployment with VPC Lattice and Service Catalog - Deployment Script
# This script deploys a complete Service Catalog portfolio with VPC Lattice service templates

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly TEMP_DIR=$(mktemp -d)
readonly DRY_RUN=${DRY_RUN:-false}

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "${TEMP_DIR}"
}

# Error handler
error_handler() {
    local line_no=$1
    log_error "Script failed at line ${line_no}"
    cleanup
    exit 1
}

# Set error trap
trap 'error_handler ${LINENO}' ERR
trap cleanup EXIT

# Help function
show_help() {
    cat << EOF
Standardized Service Deployment with VPC Lattice and Service Catalog - Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deployed without making changes
    -r, --region REGION    AWS region (default: from AWS CLI config)
    -p, --prefix PREFIX    Resource name prefix (default: auto-generated)
    -v, --verbose          Enable verbose logging

ENVIRONMENT VARIABLES:
    DRY_RUN                Set to 'true' to enable dry-run mode
    AWS_REGION             AWS region override
    RESOURCE_PREFIX        Resource name prefix override

EXAMPLES:
    $0                                    # Deploy with defaults
    $0 --dry-run                         # Preview deployment
    $0 --region us-west-2 --prefix test  # Deploy to specific region with prefix
    DRY_RUN=true $0                      # Dry run using environment variable

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -p|--prefix)
                RESOURCE_PREFIX="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version (require v2)
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ "${aws_version:0:1}" != "2" ]]; then
        log_warning "AWS CLI v2 is recommended. You have version ${aws_version}"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check required AWS CLI commands
    local required_commands=("servicecatalog" "vpc-lattice" "s3" "iam" "cloudformation")
    for cmd in "${required_commands[@]}"; do
        if ! aws "${cmd}" help &> /dev/null; then
            log_error "AWS CLI command '${cmd}' not available"
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "${AWS_REGION}" ]]; then
        log_error "AWS region not set. Configure with 'aws configure' or set AWS_REGION"
        exit 1
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix if prefix not provided
    if [[ -z "${RESOURCE_PREFIX:-}" ]]; then
        local random_suffix
        random_suffix=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            openssl rand -hex 3)
        export RESOURCE_PREFIX="vpclattice-${random_suffix}"
    fi
    
    # Set resource names
    export PORTFOLIO_NAME="vpc-lattice-services-${RESOURCE_PREFIX}"
    export SERVICE_PRODUCT_NAME="standardized-lattice-service"
    export NETWORK_PRODUCT_NAME="standardized-service-network"
    export BUCKET_NAME="service-catalog-templates-${RESOURCE_PREFIX}"
    export LAUNCH_ROLE_NAME="ServiceCatalogVpcLatticeRole-${RESOURCE_PREFIX}"
    
    log_info "Environment configured:"
    log_info "  AWS Region: ${AWS_REGION}"
    log_info "  AWS Account: ${AWS_ACCOUNT_ID}"
    log_info "  Resource Prefix: ${RESOURCE_PREFIX}"
    log_info "  S3 Bucket: ${BUCKET_NAME}"
}

# Create CloudFormation templates
create_templates() {
    log_info "Creating CloudFormation templates..."
    
    # Service Network Template
    cat > "${TEMP_DIR}/service-network-template.yaml" << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Standardized VPC Lattice Service Network'

Parameters:
  NetworkName:
    Type: String
    Default: 'standard-service-network'
    Description: 'Name for the VPC Lattice service network'
  
  AuthType:
    Type: String
    Default: 'AWS_IAM'
    AllowedValues: ['AWS_IAM', 'NONE']
    Description: 'Authentication type for the service network'

Resources:
  ServiceNetwork:
    Type: AWS::VpcLattice::ServiceNetwork
    Properties:
      Name: !Ref NetworkName
      AuthType: !Ref AuthType
      Tags:
        - Key: 'Purpose'
          Value: 'StandardizedDeployment'
        - Key: 'ManagedBy'
          Value: 'ServiceCatalog'

  ServiceNetworkPolicy:
    Type: AWS::VpcLattice::AuthPolicy
    Properties:
      ResourceIdentifier: !Ref ServiceNetwork
      Policy:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal: '*'
            Action: 'vpc-lattice-svcs:Invoke'
            Resource: '*'
            Condition:
              StringEquals:
                'aws:PrincipalAccount': !Ref 'AWS::AccountId'

Outputs:
  ServiceNetworkId:
    Description: 'Service Network ID'
    Value: !Ref ServiceNetwork
    Export:
      Name: !Sub '${AWS::StackName}-ServiceNetworkId'
  
  ServiceNetworkArn:
    Description: 'Service Network ARN'
    Value: !GetAtt ServiceNetwork.Arn
    Export:
      Name: !Sub '${AWS::StackName}-ServiceNetworkArn'
EOF

    # VPC Lattice Service Template
    cat > "${TEMP_DIR}/lattice-service-template.yaml" << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Standardized VPC Lattice Service with Target Group'

Parameters:
  ServiceName:
    Type: String
    Description: 'Name for the VPC Lattice service'
  
  ServiceNetworkId:
    Type: String
    Description: 'Service Network ID to associate with'
  
  TargetType:
    Type: String
    Default: 'IP'
    AllowedValues: ['IP', 'LAMBDA', 'ALB']
    Description: 'Type of targets for the target group'
  
  VpcId:
    Type: AWS::EC2::VPC::Id
    Description: 'VPC ID for the target group'
  
  Port:
    Type: Number
    Default: 80
    MinValue: 1
    MaxValue: 65535
    Description: 'Port for the service listener'
  
  Protocol:
    Type: String
    Default: 'HTTP'
    AllowedValues: ['HTTP', 'HTTPS']
    Description: 'Protocol for the service listener'

Resources:
  TargetGroup:
    Type: AWS::VpcLattice::TargetGroup
    Properties:
      Name: !Sub '${ServiceName}-targets'
      Type: !Ref TargetType
      Port: !Ref Port
      Protocol: !Ref Protocol
      VpcIdentifier: !Ref VpcId
      HealthCheck:
        Enabled: true
        HealthCheckIntervalSeconds: 30
        HealthCheckTimeoutSeconds: 5
        HealthyThresholdCount: 2
        UnhealthyThresholdCount: 3
        Matcher:
          HttpCode: '200'
        Path: '/health'
        Port: !Ref Port
        Protocol: !Ref Protocol
      Tags:
        - Key: 'Purpose'
          Value: 'StandardizedDeployment'
        - Key: 'ManagedBy'
          Value: 'ServiceCatalog'

  Service:
    Type: AWS::VpcLattice::Service
    Properties:
      Name: !Ref ServiceName
      AuthType: 'AWS_IAM'
      Tags:
        - Key: 'Purpose'
          Value: 'StandardizedDeployment'
        - Key: 'ManagedBy'
          Value: 'ServiceCatalog'

  Listener:
    Type: AWS::VpcLattice::Listener
    Properties:
      ServiceIdentifier: !Ref Service
      Name: 'default-listener'
      Port: !Ref Port
      Protocol: !Ref Protocol
      DefaultAction:
        Forward:
          TargetGroups:
            - TargetGroupIdentifier: !Ref TargetGroup
              Weight: 100

  ServiceNetworkAssociation:
    Type: AWS::VpcLattice::ServiceNetworkServiceAssociation
    Properties:
      ServiceIdentifier: !Ref Service
      ServiceNetworkIdentifier: !Ref ServiceNetworkId

Outputs:
  ServiceId:
    Description: 'VPC Lattice Service ID'
    Value: !Ref Service
  
  ServiceArn:
    Description: 'VPC Lattice Service ARN'
    Value: !GetAtt Service.Arn
  
  TargetGroupId:
    Description: 'Target Group ID'
    Value: !Ref TargetGroup
  
  TargetGroupArn:
    Description: 'Target Group ARN'
    Value: !GetAtt TargetGroup.Arn
EOF

    log_success "CloudFormation templates created"
}

# Create S3 bucket and upload templates
setup_s3_bucket() {
    log_info "Setting up S3 bucket for templates..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create S3 bucket: ${BUCKET_NAME}"
        return 0
    fi
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        log_warning "S3 bucket ${BUCKET_NAME} already exists"
    else
        # Create bucket with region-specific configuration
        if [[ "${AWS_REGION}" == "us-east-1" ]]; then
            aws s3api create-bucket --bucket "${BUCKET_NAME}"
        else
            aws s3api create-bucket --bucket "${BUCKET_NAME}" \
                --create-bucket-configuration LocationConstraint="${AWS_REGION}"
        fi
        
        # Enable versioning for template management
        aws s3api put-bucket-versioning --bucket "${BUCKET_NAME}" \
            --versioning-configuration Status=Enabled
        
        log_success "S3 bucket created: ${BUCKET_NAME}"
    fi
    
    # Upload templates
    aws s3 cp "${TEMP_DIR}/service-network-template.yaml" \
        "s3://${BUCKET_NAME}/service-network-template.yaml"
    
    aws s3 cp "${TEMP_DIR}/lattice-service-template.yaml" \
        "s3://${BUCKET_NAME}/lattice-service-template.yaml"
    
    log_success "Templates uploaded to S3"
}

# Create IAM role for Service Catalog launches
create_iam_role() {
    log_info "Creating IAM role for Service Catalog launches..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create IAM role: ${LAUNCH_ROLE_NAME}"
        return 0
    fi
    
    # Check if role already exists
    if aws iam get-role --role-name "${LAUNCH_ROLE_NAME}" &>/dev/null; then
        log_warning "IAM role ${LAUNCH_ROLE_NAME} already exists"
        return 0
    fi
    
    # Create trust policy
    cat > "${TEMP_DIR}/trust-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "servicecatalog.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    # Create permissions policy
    cat > "${TEMP_DIR}/permissions-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "vpc-lattice:*",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "cloudformation:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF

    # Create role
    aws iam create-role \
        --role-name "${LAUNCH_ROLE_NAME}" \
        --assume-role-policy-document "file://${TEMP_DIR}/trust-policy.json" \
        --description "Service Catalog launch role for VPC Lattice services"
    
    # Attach permissions policy
    aws iam put-role-policy \
        --role-name "${LAUNCH_ROLE_NAME}" \
        --policy-name "VpcLatticePermissions" \
        --policy-document "file://${TEMP_DIR}/permissions-policy.json"
    
    # Wait for role to be available
    aws iam wait role-exists --role-name "${LAUNCH_ROLE_NAME}"
    
    log_success "IAM role created: ${LAUNCH_ROLE_NAME}"
}

# Create Service Catalog portfolio and products
create_service_catalog() {
    log_info "Creating Service Catalog portfolio and products..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Service Catalog portfolio: ${PORTFOLIO_NAME}"
        return 0
    fi
    
    # Create portfolio
    local portfolio_id
    portfolio_id=$(aws servicecatalog create-portfolio \
        --display-name "${PORTFOLIO_NAME}" \
        --description "Standardized VPC Lattice service deployment templates" \
        --provider-name "Platform Engineering Team" \
        --query 'PortfolioDetail.Id' --output text)
    
    log_success "Portfolio created: ${portfolio_id}"
    
    # Get launch role ARN
    local launch_role_arn
    launch_role_arn=$(aws iam get-role --role-name "${LAUNCH_ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    
    # Create service network product
    local network_product_id
    network_product_id=$(aws servicecatalog create-product \
        --name "${NETWORK_PRODUCT_NAME}" \
        --description "Standardized VPC Lattice Service Network" \
        --owner "Platform Engineering Team" \
        --product-type "CLOUD_FORMATION_TEMPLATE" \
        --provisioning-artifact-parameters \
        "Name=v1.0,Description=Initial version,Info={\"LoadTemplateFromURL\":\"https://s3.${AWS_REGION}.amazonaws.com/${BUCKET_NAME}/service-network-template.yaml\"}" \
        --query 'ProductViewDetail.ProductViewSummary.ProductId' --output text)
    
    log_success "Network product created: ${network_product_id}"
    
    # Create lattice service product
    local service_product_id
    service_product_id=$(aws servicecatalog create-product \
        --name "${SERVICE_PRODUCT_NAME}" \
        --description "Standardized VPC Lattice Service with Target Group" \
        --owner "Platform Engineering Team" \
        --product-type "CLOUD_FORMATION_TEMPLATE" \
        --provisioning-artifact-parameters \
        "Name=v1.0,Description=Initial version,Info={\"LoadTemplateFromURL\":\"https://s3.${AWS_REGION}.amazonaws.com/${BUCKET_NAME}/lattice-service-template.yaml\"}" \
        --query 'ProductViewDetail.ProductViewSummary.ProductId' --output text)
    
    log_success "Service product created: ${service_product_id}"
    
    # Associate products with portfolio
    aws servicecatalog associate-product-with-portfolio \
        --product-id "${network_product_id}" \
        --portfolio-id "${portfolio_id}"
    
    aws servicecatalog associate-product-with-portfolio \
        --product-id "${service_product_id}" \
        --portfolio-id "${portfolio_id}"
    
    # Create launch constraints
    aws servicecatalog create-constraint \
        --portfolio-id "${portfolio_id}" \
        --product-id "${network_product_id}" \
        --parameters "RoleArn=${launch_role_arn}" \
        --type "LAUNCH" \
        --description "IAM role for VPC Lattice service network deployment"
    
    aws servicecatalog create-constraint \
        --portfolio-id "${portfolio_id}" \
        --product-id "${service_product_id}" \
        --parameters "RoleArn=${launch_role_arn}" \
        --type "LAUNCH" \
        --description "IAM role for VPC Lattice service deployment"
    
    # Grant current user access to portfolio
    local current_user_arn
    current_user_arn=$(aws sts get-caller-identity --query 'Arn' --output text)
    
    aws servicecatalog associate-principal-with-portfolio \
        --portfolio-id "${portfolio_id}" \
        --principal-arn "${current_user_arn}" \
        --principal-type "IAM"
    
    log_success "Service Catalog setup completed"
    
    # Save deployment information
    cat > "${SCRIPT_DIR}/deployment-info.json" << EOF
{
  "portfolioId": "${portfolio_id}",
  "networkProductId": "${network_product_id}",
  "serviceProductId": "${service_product_id}",
  "launchRoleArn": "${launch_role_arn}",
  "bucketName": "${BUCKET_NAME}",
  "resourcePrefix": "${RESOURCE_PREFIX}",
  "deploymentTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

# Test deployment with sample resources
test_deployment() {
    log_info "Testing deployment with sample resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would test Service Catalog deployment"
        return 0
    fi
    
    # Get default VPC for testing
    local default_vpc_id
    default_vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
    
    if [[ "${default_vpc_id}" == "None" || -z "${default_vpc_id}" ]]; then
        log_warning "No default VPC found. Skipping test deployment."
        log_warning "You can manually test using the Service Catalog console."
        return 0
    fi
    
    # Load deployment info
    local portfolio_id network_product_id
    portfolio_id=$(jq -r '.portfolioId' "${SCRIPT_DIR}/deployment-info.json")
    network_product_id=$(jq -r '.networkProductId' "${SCRIPT_DIR}/deployment-info.json")
    
    # Test network deployment
    log_info "Testing service network deployment..."
    local test_network_name="test-network-${RESOURCE_PREFIX}"
    
    local network_provisioned_id
    network_provisioned_id=$(aws servicecatalog provision-product \
        --product-id "${network_product_id}" \
        --provisioned-product-name "${test_network_name}" \
        --provisioning-artifact-name "v1.0" \
        --provisioning-parameters \
        "Key=NetworkName,Value=${test_network_name}" \
        "Key=AuthType,Value=AWS_IAM" \
        --query 'RecordDetail.ProvisionedProductId' --output text)
    
    log_info "Test network deployment initiated: ${network_provisioned_id}"
    log_info "Monitor deployment status in the Service Catalog console"
    
    # Update deployment info with test resources
    jq --arg networkId "$network_provisioned_id" \
       --arg networkName "$test_network_name" \
       '. + {testNetworkId: $networkId, testNetworkName: $networkName}' \
       "${SCRIPT_DIR}/deployment-info.json" > "${SCRIPT_DIR}/deployment-info.tmp" \
       && mv "${SCRIPT_DIR}/deployment-info.tmp" "${SCRIPT_DIR}/deployment-info.json"
    
    log_success "Test deployment completed"
}

# Display deployment summary
show_summary() {
    log_info "Deployment Summary"
    echo "=================================="
    echo "AWS Region: ${AWS_REGION}"
    echo "Resource Prefix: ${RESOURCE_PREFIX}"
    echo "S3 Bucket: ${BUCKET_NAME}"
    echo "IAM Role: ${LAUNCH_ROLE_NAME}"
    echo "Portfolio: ${PORTFOLIO_NAME}"
    echo ""
    echo "Next Steps:"
    echo "1. Access AWS Service Catalog console"
    echo "2. Navigate to 'Products list' under 'End user'"
    echo "3. Launch products from the '${PORTFOLIO_NAME}' portfolio"
    echo "4. Use the deployment-info.json file for cleanup"
    echo ""
    echo "Log file: ${LOG_FILE}"
    echo "Deployment info: ${SCRIPT_DIR}/deployment-info.json"
    echo "=================================="
}

# Main execution
main() {
    log_info "Starting Standardized Service Deployment with VPC Lattice and Service Catalog"
    
    # Parse arguments
    parse_args "$@"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_templates
    setup_s3_bucket
    create_iam_role
    create_service_catalog
    test_deployment
    
    log_success "Deployment completed successfully!"
    show_summary
}

# Execute main function with all arguments
main "$@"