#!/bin/bash

# Advanced Request Routing with VPC Lattice and ALB - Deployment Script
# This script deploys the complete infrastructure for the advanced request routing recipe
# Author: AWS Recipe Generator
# Version: 1.0

set -e  # Exit on error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Error handling function
handle_error() {
    local line_num=$1
    local error_code=$2
    log_error "An error occurred at line $line_num with exit code $error_code"
    log_error "Deployment failed. Check the log file for details: ${LOG_FILE}"
    exit $error_code
}

# Set error trap
trap 'handle_error ${LINENO} $?' ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Initialize log file
echo "=== Advanced Request Routing with VPC Lattice and ALB Deployment ===" > "${LOG_FILE}"
echo "Deployment started at: $(date)" >> "${LOG_FILE}"

log_info "Starting deployment of Advanced Request Routing with VPC Lattice and ALB"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $aws_version"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check required permissions by testing a simple operation
    if ! aws ec2 describe-vpcs --max-items 1 &> /dev/null; then
        log_error "Insufficient permissions to access EC2 service."
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some operations may be less reliable."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region is not configured. Please set it using 'aws configure'."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Define resource names
    export LATTICE_NETWORK_NAME="advanced-routing-network-${random_suffix}"
    export LATTICE_SERVICE_NAME="api-gateway-service-${random_suffix}"
    export ALB1_NAME="api-service-alb-${random_suffix}"
    export ALB2_NAME="backend-service-alb-${random_suffix}"
    export RANDOM_SUFFIX="${random_suffix}"
    
    # Get default VPC for initial setup
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text)
    
    if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
        log_error "No default VPC found. Please create a default VPC or specify a VPC ID."
        exit 1
    fi
    
    # Save state
    cat > "${STATE_FILE}" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
LATTICE_NETWORK_NAME=${LATTICE_NETWORK_NAME}
LATTICE_SERVICE_NAME=${LATTICE_SERVICE_NAME}
ALB1_NAME=${ALB1_NAME}
ALB2_NAME=${ALB2_NAME}
VPC_ID=${VPC_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment configured with VPC: ${VPC_ID}"
    log_info "Resource suffix: ${RANDOM_SUFFIX}"
}

# Function to create VPC Lattice service network
create_lattice_network() {
    log_info "Creating VPC Lattice service network..."
    
    LATTICE_NETWORK_ID=$(aws vpc-lattice create-service-network \
        --name "${LATTICE_NETWORK_NAME}" \
        --auth-type "AWS_IAM" \
        --query "id" --output text)
    
    echo "LATTICE_NETWORK_ID=${LATTICE_NETWORK_ID}" >> "${STATE_FILE}"
    
    log_success "VPC Lattice service network created: ${LATTICE_NETWORK_ID}"
}

# Function to create target VPC and associate with service network
create_target_vpc() {
    log_info "Creating target VPC and associating with service network..."
    
    # Create additional VPC for multi-VPC demonstration
    TARGET_VPC_ID=$(aws ec2 create-vpc \
        --cidr-block "10.1.0.0/16" \
        --tag-specifications \
        "ResourceType=vpc,Tags=[{Key=Name,Value=lattice-target-vpc-${RANDOM_SUFFIX}}]" \
        --query "Vpc.VpcId" --output text)
    
    # Create subnet in target VPC
    TARGET_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "${TARGET_VPC_ID}" \
        --cidr-block "10.1.1.0/24" \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications \
        "ResourceType=subnet,Tags=[{Key=Name,Value=lattice-subnet-${RANDOM_SUFFIX}}]" \
        --query "Subnet.SubnetId" --output text)
    
    # Associate default VPC with service network
    aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier "${LATTICE_NETWORK_ID}" \
        --vpc-identifier "${VPC_ID}" > /dev/null
    
    # Associate target VPC with service network
    aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier "${LATTICE_NETWORK_ID}" \
        --vpc-identifier "${TARGET_VPC_ID}" > /dev/null
    
    echo "TARGET_VPC_ID=${TARGET_VPC_ID}" >> "${STATE_FILE}"
    echo "TARGET_SUBNET_ID=${TARGET_SUBNET_ID}" >> "${STATE_FILE}"
    
    log_success "VPCs associated with service network"
}

# Function to create and configure internal ALB
create_alb() {
    log_info "Creating and configuring internal Application Load Balancer..."
    
    # Get default subnets for ALB (requires at least 2 AZs)
    local subnets=($(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" "Name=default-for-az,Values=true" \
        --query "Subnets[].SubnetId" --output text))
    
    if [[ ${#subnets[@]} -lt 2 ]]; then
        log_error "Need at least 2 subnets in different AZs for ALB. Found: ${#subnets[@]}"
        exit 1
    fi
    
    DEFAULT_SUBNET_ID1=${subnets[0]}
    DEFAULT_SUBNET_ID2=${subnets[1]}
    
    # Create security group for ALBs
    ALB_SG_ID=$(aws ec2 create-security-group \
        --group-name "lattice-alb-sg-${RANDOM_SUFFIX}" \
        --description "Security group for VPC Lattice ALB targets" \
        --vpc-id "${VPC_ID}" \
        --query "GroupId" --output text)
    
    # Allow HTTP/HTTPS traffic to ALB from VPC Lattice
    aws ec2 authorize-security-group-ingress \
        --group-id "${ALB_SG_ID}" \
        --protocol tcp --port 80 --cidr 10.0.0.0/8 > /dev/null
    
    aws ec2 authorize-security-group-ingress \
        --group-id "${ALB_SG_ID}" \
        --protocol tcp --port 443 --cidr 10.0.0.0/8 > /dev/null
    
    # Create first internal ALB for API services
    ALB1_ARN=$(aws elbv2 create-load-balancer \
        --name "${ALB1_NAME}" \
        --subnets "${DEFAULT_SUBNET_ID1}" "${DEFAULT_SUBNET_ID2}" \
        --security-groups "${ALB_SG_ID}" \
        --scheme internal \
        --type application \
        --query "LoadBalancers[0].LoadBalancerArn" --output text)
    
    echo "DEFAULT_SUBNET_ID1=${DEFAULT_SUBNET_ID1}" >> "${STATE_FILE}"
    echo "DEFAULT_SUBNET_ID2=${DEFAULT_SUBNET_ID2}" >> "${STATE_FILE}"
    echo "ALB_SG_ID=${ALB_SG_ID}" >> "${STATE_FILE}"
    echo "ALB1_ARN=${ALB1_ARN}" >> "${STATE_FILE}"
    
    log_success "Internal ALB created: ${ALB1_ARN}"
}

# Function to launch EC2 instances
launch_ec2_instances() {
    log_info "Launching EC2 instances as ALB targets..."
    
    # Create user data script for web servers
    cat > /tmp/userdata.sh << 'EOF'
#!/bin/bash
dnf update -y
dnf install -y httpd
systemctl start httpd
systemctl enable httpd

# Create different content for routing demonstration
mkdir -p /var/www/html/api/v1
echo "<h1>API V1 Service</h1><p>Path: /api/v1/</p>" > /var/www/html/api/v1/index.html
echo "<h1>Default Service</h1><p>Default routing target</p>" > /var/www/html/index.html
echo "<h1>Beta Service</h1><p>X-Service-Version: beta</p>" > /var/www/html/beta.html

# Configure virtual hosts for header-based routing
cat >> /etc/httpd/conf/httpd.conf << 'VHOST'
<VirtualHost *:80>
    DocumentRoot /var/www/html
    RewriteEngine On
    RewriteCond %{HTTP:X-Service-Version} beta
    RewriteRule ^(.*)$ /beta.html [L]
</VirtualHost>
VHOST

systemctl restart httpd
EOF
    
    # Get latest Amazon Linux 2023 AMI ID using SSM parameter
    AL2023_AMI_ID=$(aws ssm get-parameter \
        --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
        --query "Parameter.Value" --output text)
    
    # Launch EC2 instances for ALB targets
    INSTANCE_ID1=$(aws ec2 run-instances \
        --image-id "${AL2023_AMI_ID}" \
        --instance-type t3.micro \
        --subnet-id "${DEFAULT_SUBNET_ID1}" \
        --security-group-ids "${ALB_SG_ID}" \
        --user-data file:///tmp/userdata.sh \
        --tag-specifications \
        "ResourceType=instance,Tags=[{Key=Name,Value=api-service-${RANDOM_SUFFIX}}]" \
        --query "Instances[0].InstanceId" --output text)
    
    echo "INSTANCE_ID1=${INSTANCE_ID1}" >> "${STATE_FILE}"
    
    log_success "EC2 instance launched: ${INSTANCE_ID1}"
}

# Function to create ALB target groups and register instances
create_target_groups() {
    log_info "Creating ALB target groups and registering instances..."
    
    # Create target group for API services
    API_TG_ARN=$(aws elbv2 create-target-group \
        --name "api-tg-${RANDOM_SUFFIX}" \
        --protocol HTTP --port 80 \
        --vpc-id "${VPC_ID}" \
        --health-check-path "/" \
        --health-check-interval-seconds 10 \
        --healthy-threshold-count 2 \
        --query "TargetGroups[0].TargetGroupArn" --output text)
    
    # Wait for instance to be running
    log_info "Waiting for EC2 instance to be running..."
    aws ec2 wait instance-running --instance-ids "${INSTANCE_ID1}"
    
    # Register instance with target group
    aws elbv2 register-targets \
        --target-group-arn "${API_TG_ARN}" \
        --targets Id="${INSTANCE_ID1}" > /dev/null
    
    # Create ALB listener
    LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn "${ALB1_ARN}" \
        --protocol HTTP --port 80 \
        --default-actions Type=forward,TargetGroupArn="${API_TG_ARN}" \
        --query "Listeners[0].ListenerArn" --output text)
    
    echo "API_TG_ARN=${API_TG_ARN}" >> "${STATE_FILE}"
    echo "LISTENER_ARN=${LISTENER_ARN}" >> "${STATE_FILE}"
    
    log_success "ALB target group configured and instances registered"
}

# Function to create VPC Lattice service and target groups
create_lattice_service() {
    log_info "Creating VPC Lattice service and target groups..."
    
    # Create VPC Lattice service
    LATTICE_SERVICE_ID=$(aws vpc-lattice create-service \
        --name "${LATTICE_SERVICE_NAME}" \
        --auth-type "AWS_IAM" \
        --query "id" --output text)
    
    # Associate service with service network
    aws vpc-lattice create-service-network-service-association \
        --service-network-identifier "${LATTICE_NETWORK_ID}" \
        --service-identifier "${LATTICE_SERVICE_ID}" > /dev/null
    
    # Create VPC Lattice target group for ALB
    LATTICE_TG_ID=$(aws vpc-lattice create-target-group \
        --name "alb-targets-${RANDOM_SUFFIX}" \
        --type "ALB" \
        --config VpcIdentifier="${VPC_ID}" \
        --query "id" --output text)
    
    # Register ALB as target
    aws vpc-lattice register-targets \
        --target-group-identifier "${LATTICE_TG_ID}" \
        --targets Id="${ALB1_ARN}" > /dev/null
    
    echo "LATTICE_SERVICE_ID=${LATTICE_SERVICE_ID}" >> "${STATE_FILE}"
    echo "LATTICE_TG_ID=${LATTICE_TG_ID}" >> "${STATE_FILE}"
    
    log_success "VPC Lattice service and target groups created"
}

# Function to create HTTP listener with default rule
create_http_listener() {
    log_info "Creating HTTP listener with default rule..."
    
    # Create HTTP listener for VPC Lattice service
    LATTICE_LISTENER_ID=$(aws vpc-lattice create-listener \
        --service-identifier "${LATTICE_SERVICE_ID}" \
        --name "http-listener" \
        --protocol "HTTP" \
        --port 80 \
        --default-action "Type=forward,TargetGroupIdentifier=${LATTICE_TG_ID}" \
        --query "id" --output text)
    
    echo "LATTICE_LISTENER_ID=${LATTICE_LISTENER_ID}" >> "${STATE_FILE}"
    
    log_success "HTTP listener created with default routing rule"
}

# Function to configure advanced routing rules
configure_routing_rules() {
    log_info "Configuring advanced path-based and header-based routing rules..."
    
    # Create header-based routing rule for service versioning (highest priority)
    aws vpc-lattice create-rule \
        --service-identifier "${LATTICE_SERVICE_ID}" \
        --listener-identifier "${LATTICE_LISTENER_ID}" \
        --name "beta-header-rule" \
        --priority 5 \
        --match '{"httpMatch":{"headerMatches":[{"name":"X-Service-Version","match":{"exact":"beta"}}]}}' \
        --action "Type=forward,TargetGroupIdentifier=${LATTICE_TG_ID}" > /dev/null
    
    # Create path-based routing rule for API v1
    aws vpc-lattice create-rule \
        --service-identifier "${LATTICE_SERVICE_ID}" \
        --listener-identifier "${LATTICE_LISTENER_ID}" \
        --name "api-v1-path-rule" \
        --priority 10 \
        --match '{"httpMatch":{"pathMatch":{"match":{"prefix":"/api/v1"}}}}' \
        --action "Type=forward,TargetGroupIdentifier=${LATTICE_TG_ID}" > /dev/null
    
    # Create method-based routing rule for POST requests
    aws vpc-lattice create-rule \
        --service-identifier "${LATTICE_SERVICE_ID}" \
        --listener-identifier "${LATTICE_LISTENER_ID}" \
        --name "post-method-rule" \
        --priority 15 \
        --match '{"httpMatch":{"method":"POST"}}' \
        --action "Type=forward,TargetGroupIdentifier=${LATTICE_TG_ID}" > /dev/null
    
    # Create path-based routing rule for admin endpoints (blocks access)
    aws vpc-lattice create-rule \
        --service-identifier "${LATTICE_SERVICE_ID}" \
        --listener-identifier "${LATTICE_LISTENER_ID}" \
        --name "admin-path-rule" \
        --priority 20 \
        --match '{"httpMatch":{"pathMatch":{"match":{"exact":"/admin"}}}}' \
        --action '{"fixedResponse":{"statusCode":403}}' > /dev/null
    
    log_success "Advanced routing rules configured"
}

# Function to configure IAM authentication policy
configure_iam_auth() {
    log_info "Configuring IAM authentication policy..."
    
    # Create IAM auth policy for VPC Lattice service
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
                    "aws:PrincipalAccount": "${AWS_ACCOUNT_ID}"
                }
            }
        },
        {
            "Effect": "Deny",
            "Principal": "*",
            "Action": "vpc-lattice-svcs:Invoke",
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "vpc-lattice-svcs:RequestPath": "/admin"
                }
            }
        }
    ]
}
EOF

    # Apply auth policy to VPC Lattice service
    aws vpc-lattice put-auth-policy \
        --resource-identifier "${LATTICE_SERVICE_ID}" \
        --policy file:///tmp/auth-policy.json > /dev/null
    
    log_success "IAM authentication policy configured"
}

# Function to perform validation tests
validate_deployment() {
    log_info "Performing deployment validation..."
    
    # Wait for targets to be healthy
    log_info "Waiting for ALB targets to become healthy..."
    
    # Check target health with timeout
    local max_attempts=30
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local healthy_targets=$(aws elbv2 describe-target-health \
            --target-group-arn "${API_TG_ARN}" \
            --query "TargetHealthDescriptions[?TargetHealth.State=='healthy']" \
            --output json | jq length 2>/dev/null || echo "0")
        
        if [[ "$healthy_targets" -gt 0 ]]; then
            log_success "ALB targets are healthy"
            break
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            log_warning "Timeout waiting for healthy targets. Continuing with deployment..."
            break
        fi
        
        log_info "Waiting for targets to be healthy... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    # Get VPC Lattice service domain name
    SERVICE_DOMAIN=$(aws vpc-lattice get-service \
        --service-identifier "${LATTICE_SERVICE_ID}" \
        --query "dnsEntry.domainName" --output text)
    
    echo "SERVICE_DOMAIN=${SERVICE_DOMAIN}" >> "${STATE_FILE}"
    
    log_success "VPC Lattice service domain: ${SERVICE_DOMAIN}"
    
    # Verify service network status
    local network_status=$(aws vpc-lattice get-service-network \
        --service-network-identifier "${LATTICE_NETWORK_ID}" \
        --query "status" --output text)
    
    if [[ "$network_status" == "ACTIVE" ]]; then
        log_success "VPC Lattice service network is ACTIVE"
    else
        log_warning "VPC Lattice service network status: ${network_status}"
    fi
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo ""
    echo "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo ""
    echo "Resource Details:"
    echo "- Region: ${AWS_REGION}"
    echo "- VPC Lattice Network: ${LATTICE_NETWORK_NAME}"
    echo "- VPC Lattice Service: ${LATTICE_SERVICE_NAME}"
    echo "- Service Domain: ${SERVICE_DOMAIN}"
    echo "- ALB Name: ${ALB1_NAME}"
    echo "- Resource Suffix: ${RANDOM_SUFFIX}"
    echo ""
    echo "Testing Commands:"
    echo "# Test default routing:"
    echo "curl -v \"http://${SERVICE_DOMAIN}/\""
    echo ""
    echo "# Test API v1 path routing:"
    echo "curl -v \"http://${SERVICE_DOMAIN}/api/v1/\""
    echo ""
    echo "# Test beta version header routing:"
    echo "curl -v -H \"X-Service-Version: beta\" \"http://${SERVICE_DOMAIN}/\""
    echo ""
    echo "# Test blocked admin endpoint:"
    echo "curl -v \"http://${SERVICE_DOMAIN}/admin\""
    echo ""
    echo "State file: ${STATE_FILE}"
    echo "Log file: ${LOG_FILE}"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo "=== END DEPLOYMENT SUMMARY ==="
}

# Main deployment function
main() {
    log_info "Advanced Request Routing with VPC Lattice and ALB - Deployment Started"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_lattice_network
    create_target_vpc
    create_alb
    launch_ec2_instances
    create_target_groups
    create_lattice_service
    create_http_listener
    configure_routing_rules
    configure_iam_auth
    validate_deployment
    display_summary
    
    # Mark deployment as complete
    echo "DEPLOYMENT_COMPLETE=true" >> "${STATE_FILE}"
    echo "DEPLOYMENT_DATE=$(date)" >> "${STATE_FILE}"
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"