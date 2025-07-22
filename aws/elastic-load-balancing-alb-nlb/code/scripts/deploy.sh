#!/bin/bash

# Deployment script for Elastic Load Balancing with Application and Network Load Balancers
# This script deploys the complete infrastructure for the load balancing recipe

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    log "Checking AWS CLI configuration..."
    
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "AWS CLI is configured"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    check_aws_config
    
    # Check required permissions (basic check)
    log "Verifying AWS permissions..."
    if ! aws iam get-user >/dev/null 2>&1 && ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "Unable to verify AWS identity. Please check your credentials."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_warning "AWS region not set in config. Using us-east-1 as default."
        export AWS_REGION="us-east-1"
    fi
    
    # Get AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    export PROJECT_NAME="elb-demo-${RANDOM_SUFFIX}"
    export VPC_NAME="${PROJECT_NAME}-vpc"
    export ALB_NAME="${PROJECT_NAME}-alb"
    export NLB_NAME="${PROJECT_NAME}-nlb"
    
    log_success "Environment variables set:"
    log "  Project Name: ${PROJECT_NAME}"
    log "  AWS Region: ${AWS_REGION}"
    log "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    
    # Create a state file to track resources
    STATE_FILE="deployment_state_${PROJECT_NAME}.json"
    cat > "$STATE_FILE" << EOF
{
    "project_name": "${PROJECT_NAME}",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "resources": {}
}
EOF
    
    log_success "State file created: $STATE_FILE"
}

# Function to update state file
update_state() {
    local resource_type="$1"
    local resource_id="$2"
    local resource_name="$3"
    
    # Update the state file with resource information
    python3 -c "
import json
import sys

try:
    with open('$STATE_FILE', 'r') as f:
        state = json.load(f)
    
    state['resources']['$resource_type'] = {
        'id': '$resource_id',
        'name': '$resource_name',
        'created_at': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
    }
    
    with open('$STATE_FILE', 'w') as f:
        json.dump(state, f, indent=2)
except Exception as e:
    print(f'Error updating state: {e}', file=sys.stderr)
    sys.exit(1)
"
}

# Function to get VPC information
setup_vpc() {
    log "Setting up VPC information..."
    
    # Get default VPC for this demo
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text)
    
    if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
        log_error "No default VPC found. Please create a VPC first."
        exit 1
    fi
    
    export VPC_ID
    log_success "Using VPC: ${VPC_ID}"
    
    # Get subnet IDs for load balancer placement
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query "Subnets[*].SubnetId" --output text | tr '\t' ',')
    
    if [ -z "$SUBNET_IDS" ]; then
        log_error "No subnets found in VPC ${VPC_ID}"
        exit 1
    fi
    
    export SUBNET_IDS
    log_success "Available subnets: ${SUBNET_IDS}"
    
    update_state "vpc" "$VPC_ID" "default-vpc"
}

# Function to create security groups
create_security_groups() {
    log "Creating security groups..."
    
    # Create security group for Application Load Balancer
    log "Creating ALB security group..."
    ALB_SG_ID=$(aws ec2 create-security-group \
        --group-name "${PROJECT_NAME}-alb-sg" \
        --description "Security group for Application Load Balancer" \
        --vpc-id ${VPC_ID} \
        --query GroupId --output text)
    
    # Allow HTTP and HTTPS traffic to ALB
    aws ec2 authorize-security-group-ingress \
        --group-id ${ALB_SG_ID} \
        --protocol tcp --port 80 --cidr 0.0.0.0/0
    
    aws ec2 authorize-security-group-ingress \
        --group-id ${ALB_SG_ID} \
        --protocol tcp --port 443 --cidr 0.0.0.0/0
    
    export ALB_SG_ID
    log_success "ALB Security Group created: ${ALB_SG_ID}"
    update_state "alb_security_group" "$ALB_SG_ID" "${PROJECT_NAME}-alb-sg"
    
    # Create security group for Network Load Balancer
    log "Creating NLB security group..."
    NLB_SG_ID=$(aws ec2 create-security-group \
        --group-name "${PROJECT_NAME}-nlb-sg" \
        --description "Security group for Network Load Balancer" \
        --vpc-id ${VPC_ID} \
        --query GroupId --output text)
    
    # Allow TCP traffic on port 80 for NLB
    aws ec2 authorize-security-group-ingress \
        --group-id ${NLB_SG_ID} \
        --protocol tcp --port 80 --cidr 0.0.0.0/0
    
    export NLB_SG_ID
    log_success "NLB Security Group created: ${NLB_SG_ID}"
    update_state "nlb_security_group" "$NLB_SG_ID" "${PROJECT_NAME}-nlb-sg"
    
    # Create security group for EC2 instances
    log "Creating EC2 security group..."
    EC2_SG_ID=$(aws ec2 create-security-group \
        --group-name "${PROJECT_NAME}-ec2-sg" \
        --description "Security group for EC2 instances behind load balancers" \
        --vpc-id ${VPC_ID} \
        --query GroupId --output text)
    
    # Allow traffic from ALB security group
    aws ec2 authorize-security-group-ingress \
        --group-id ${EC2_SG_ID} \
        --protocol tcp --port 80 \
        --source-group ${ALB_SG_ID}
    
    # Allow traffic from NLB security group
    aws ec2 authorize-security-group-ingress \
        --group-id ${EC2_SG_ID} \
        --protocol tcp --port 80 \
        --source-group ${NLB_SG_ID}
    
    # Allow SSH access for management
    aws ec2 authorize-security-group-ingress \
        --group-id ${EC2_SG_ID} \
        --protocol tcp --port 22 --cidr 0.0.0.0/0
    
    export EC2_SG_ID
    log_success "EC2 Security Group created: ${EC2_SG_ID}"
    update_state "ec2_security_group" "$EC2_SG_ID" "${PROJECT_NAME}-ec2-sg"
}

# Function to create EC2 instances
create_ec2_instances() {
    log "Creating EC2 instances..."
    
    # Get the latest Amazon Linux 2 AMI ID
    AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
        --query "Images|sort_by(@, &CreationDate)[-1].ImageId" \
        --output text)
    
    log "Using AMI: ${AMI_ID}"
    
    # Create user data script for web server setup
    cat > user-data.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>Hello from $(hostname -f)</h1>" > /var/www/html/index.html
echo "<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" >> /var/www/html/index.html
echo "<p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>" >> /var/www/html/index.html
echo "<p>Deployed at: $(date)</p>" >> /var/www/html/index.html
EOF
    
    # Launch first EC2 instance
    log "Launching first EC2 instance..."
    INSTANCE_1=$(aws ec2 run-instances \
        --image-id ${AMI_ID} \
        --count 1 \
        --instance-type t3.micro \
        --security-group-ids ${EC2_SG_ID} \
        --user-data file://user-data.sh \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-web-1},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query "Instances[0].InstanceId" --output text)
    
    # Launch second EC2 instance
    log "Launching second EC2 instance..."
    INSTANCE_2=$(aws ec2 run-instances \
        --image-id ${AMI_ID} \
        --count 1 \
        --instance-type t3.micro \
        --security-group-ids ${EC2_SG_ID} \
        --user-data file://user-data.sh \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-web-2},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query "Instances[0].InstanceId" --output text)
    
    export INSTANCE_1 INSTANCE_2
    log_success "EC2 instances launching: ${INSTANCE_1}, ${INSTANCE_2}"
    
    update_state "ec2_instance_1" "$INSTANCE_1" "${PROJECT_NAME}-web-1"
    update_state "ec2_instance_2" "$INSTANCE_2" "${PROJECT_NAME}-web-2"
    
    # Wait for instances to be running
    log "Waiting for EC2 instances to be running..."
    aws ec2 wait instance-running --instance-ids ${INSTANCE_1} ${INSTANCE_2}
    log_success "EC2 instances are running and ready"
    
    # Clean up temporary file
    rm -f user-data.sh
}

# Function to create target groups
create_target_groups() {
    log "Creating target groups..."
    
    # Create target group for Application Load Balancer
    log "Creating ALB target group..."
    ALB_TG_ARN=$(aws elbv2 create-target-group \
        --name "${PROJECT_NAME}-alb-tg" \
        --protocol HTTP \
        --port 80 \
        --vpc-id ${VPC_ID} \
        --health-check-path "/" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 5 \
        --tags Key=Name,Value="${PROJECT_NAME}-alb-tg" Key=Project,Value="${PROJECT_NAME}" \
        --query "TargetGroups[0].TargetGroupArn" --output text)
    
    # Create target group for Network Load Balancer
    log "Creating NLB target group..."
    NLB_TG_ARN=$(aws elbv2 create-target-group \
        --name "${PROJECT_NAME}-nlb-tg" \
        --protocol TCP \
        --port 80 \
        --vpc-id ${VPC_ID} \
        --health-check-protocol HTTP \
        --health-check-path "/" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 6 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 2 \
        --tags Key=Name,Value="${PROJECT_NAME}-nlb-tg" Key=Project,Value="${PROJECT_NAME}" \
        --query "TargetGroups[0].TargetGroupArn" --output text)
    
    export ALB_TG_ARN NLB_TG_ARN
    log_success "Target groups created:"
    log "  ALB Target Group: ${ALB_TG_ARN}"
    log "  NLB Target Group: ${NLB_TG_ARN}"
    
    update_state "alb_target_group" "$ALB_TG_ARN" "${PROJECT_NAME}-alb-tg"
    update_state "nlb_target_group" "$NLB_TG_ARN" "${PROJECT_NAME}-nlb-tg"
}

# Function to register targets
register_targets() {
    log "Registering EC2 instances with target groups..."
    
    # Register instances with ALB target group
    aws elbv2 register-targets \
        --target-group-arn ${ALB_TG_ARN} \
        --targets Id=${INSTANCE_1} Id=${INSTANCE_2}
    
    # Register instances with NLB target group
    aws elbv2 register-targets \
        --target-group-arn ${NLB_TG_ARN} \
        --targets Id=${INSTANCE_1} Id=${INSTANCE_2}
    
    log_success "Instances registered with target groups"
    
    # Wait for targets to become healthy
    log "Waiting for targets to pass health checks..."
    
    # Wait with timeout for ALB targets
    timeout 300 bash -c "
        while true; do
            healthy_count=\$(aws elbv2 describe-target-health \
                --target-group-arn ${ALB_TG_ARN} \
                --query 'TargetHealthDescriptions[?TargetHealth.State==\`healthy\`]' \
                --output text | wc -l)
            if [ \$healthy_count -eq 2 ]; then
                break
            fi
            echo 'Waiting for ALB targets to become healthy...'
            sleep 10
        done
    " || log_warning "ALB targets may not be fully healthy yet"
    
    # Wait with timeout for NLB targets
    timeout 300 bash -c "
        while true; do
            healthy_count=\$(aws elbv2 describe-target-health \
                --target-group-arn ${NLB_TG_ARN} \
                --query 'TargetHealthDescriptions[?TargetHealth.State==\`healthy\`]' \
                --output text | wc -l)
            if [ \$healthy_count -eq 2 ]; then
                break
            fi
            echo 'Waiting for NLB targets to become healthy...'
            sleep 10
        done
    " || log_warning "NLB targets may not be fully healthy yet"
    
    log_success "Target health checks completed"
}

# Function to create load balancers
create_load_balancers() {
    log "Creating load balancers..."
    
    # Create Application Load Balancer
    log "Creating Application Load Balancer..."
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name ${ALB_NAME} \
        --subnets $(echo ${SUBNET_IDS} | tr ',' ' ') \
        --security-groups ${ALB_SG_ID} \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --tags Key=Name,Value="${ALB_NAME}" Key=Project,Value="${PROJECT_NAME}" \
        --query "LoadBalancers[0].LoadBalancerArn" --output text)
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns ${ALB_ARN} \
        --query "LoadBalancers[0].DNSName" --output text)
    
    export ALB_ARN ALB_DNS
    log_success "Application Load Balancer created:"
    log "  ARN: ${ALB_ARN}"
    log "  DNS: ${ALB_DNS}"
    
    update_state "alb" "$ALB_ARN" "$ALB_NAME"
    update_state "alb_dns" "$ALB_DNS" "$ALB_NAME-dns"
    
    # Create Network Load Balancer
    log "Creating Network Load Balancer..."
    NLB_ARN=$(aws elbv2 create-load-balancer \
        --name ${NLB_NAME} \
        --subnets $(echo ${SUBNET_IDS} | tr ',' ' ') \
        --scheme internet-facing \
        --type network \
        --ip-address-type ipv4 \
        --tags Key=Name,Value="${NLB_NAME}" Key=Project,Value="${PROJECT_NAME}" \
        --query "LoadBalancers[0].LoadBalancerArn" --output text)
    
    # Get NLB DNS name
    NLB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns ${NLB_ARN} \
        --query "LoadBalancers[0].DNSName" --output text)
    
    export NLB_ARN NLB_DNS
    log_success "Network Load Balancer created:"
    log "  ARN: ${NLB_ARN}"
    log "  DNS: ${NLB_DNS}"
    
    update_state "nlb" "$NLB_ARN" "$NLB_NAME"
    update_state "nlb_dns" "$NLB_DNS" "$NLB_NAME-dns"
}

# Function to create listeners
create_listeners() {
    log "Creating load balancer listeners..."
    
    # Create listener for Application Load Balancer
    log "Creating ALB listener..."
    ALB_LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn ${ALB_ARN} \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn=${ALB_TG_ARN} \
        --tags Key=Name,Value="${PROJECT_NAME}-alb-listener" Key=Project,Value="${PROJECT_NAME}" \
        --query "Listeners[0].ListenerArn" --output text)
    
    # Create listener for Network Load Balancer
    log "Creating NLB listener..."
    NLB_LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn ${NLB_ARN} \
        --protocol TCP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn=${NLB_TG_ARN} \
        --tags Key=Name,Value="${PROJECT_NAME}-nlb-listener" Key=Project,Value="${PROJECT_NAME}" \
        --query "Listeners[0].ListenerArn" --output text)
    
    export ALB_LISTENER_ARN NLB_LISTENER_ARN
    log_success "Load balancer listeners configured:"
    log "  ALB Listener: ${ALB_LISTENER_ARN}"
    log "  NLB Listener: ${NLB_LISTENER_ARN}"
    
    update_state "alb_listener" "$ALB_LISTENER_ARN" "${PROJECT_NAME}-alb-listener"
    update_state "nlb_listener" "$NLB_LISTENER_ARN" "${PROJECT_NAME}-nlb-listener"
}

# Function to configure target group attributes
configure_target_group_attributes() {
    log "Configuring target group attributes..."
    
    # Configure ALB target group attributes
    aws elbv2 modify-target-group-attributes \
        --target-group-arn ${ALB_TG_ARN} \
        --attributes \
        Key=deregistration_delay.timeout_seconds,Value=30 \
        Key=stickiness.enabled,Value=true \
        Key=stickiness.type,Value=lb_cookie \
        Key=stickiness.lb_cookie.duration_seconds,Value=86400
    
    # Configure NLB target group attributes
    aws elbv2 modify-target-group-attributes \
        --target-group-arn ${NLB_TG_ARN} \
        --attributes \
        Key=deregistration_delay.timeout_seconds,Value=30 \
        Key=preserve_client_ip.enabled,Value=true
    
    log_success "Target group attributes optimized for performance"
}

# Function to perform basic validation
validate_deployment() {
    log "Validating deployment..."
    
    # Check load balancer status
    ALB_STATE=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns ${ALB_ARN} \
        --query "LoadBalancers[0].State.Code" --output text)
    
    NLB_STATE=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns ${NLB_ARN} \
        --query "LoadBalancers[0].State.Code" --output text)
    
    if [ "$ALB_STATE" = "active" ] && [ "$NLB_STATE" = "active" ]; then
        log_success "Load balancers are active"
    else
        log_warning "Load balancers may not be fully active yet (ALB: $ALB_STATE, NLB: $NLB_STATE)"
    fi
    
    # Check target health
    ALB_HEALTHY=$(aws elbv2 describe-target-health \
        --target-group-arn ${ALB_TG_ARN} \
        --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`]' \
        --output text | wc -l)
    
    NLB_HEALTHY=$(aws elbv2 describe-target-health \
        --target-group-arn ${NLB_TG_ARN} \
        --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`]' \
        --output text | wc -l)
    
    log_success "Validation completed:"
    log "  ALB healthy targets: ${ALB_HEALTHY}/2"
    log "  NLB healthy targets: ${NLB_HEALTHY}/2"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=================================="
    echo "DEPLOYMENT SUMMARY"
    echo "=================================="
    echo "Project Name: ${PROJECT_NAME}"
    echo "AWS Region: ${AWS_REGION}"
    echo "VPC ID: ${VPC_ID}"
    echo
    echo "LOAD BALANCERS:"
    echo "  Application Load Balancer:"
    echo "    ARN: ${ALB_ARN}"
    echo "    DNS: ${ALB_DNS}"
    echo "    URL: http://${ALB_DNS}"
    echo
    echo "  Network Load Balancer:"
    echo "    ARN: ${NLB_ARN}"
    echo "    DNS: ${NLB_DNS}"
    echo "    URL: http://${NLB_DNS}"
    echo
    echo "EC2 INSTANCES:"
    echo "  Instance 1: ${INSTANCE_1}"
    echo "  Instance 2: ${INSTANCE_2}"
    echo
    echo "TESTING:"
    echo "  Test ALB: curl http://${ALB_DNS}"
    echo "  Test NLB: curl http://${NLB_DNS}"
    echo
    echo "STATE FILE: ${STATE_FILE}"
    echo "  Use this file with destroy.sh to clean up resources"
    echo "=================================="
}

# Function to handle errors
handle_error() {
    log_error "Deployment failed at step: $1"
    log_error "Please check the error messages above and cleanup any partially created resources"
    log_error "You can use the destroy.sh script to clean up resources"
    exit 1
}

# Main deployment function
main() {
    log "Starting deployment of Elastic Load Balancing infrastructure..."
    
    # Trap errors
    trap 'handle_error "Unknown"' ERR
    
    # Check if running in dry-run mode
    if [ "${1:-}" = "--dry-run" ]; then
        log_warning "DRY RUN MODE - No resources will be created"
        export DRY_RUN=true
    fi
    
    # Execute deployment steps
    check_prerequisites || handle_error "Prerequisites check"
    setup_environment || handle_error "Environment setup"
    setup_vpc || handle_error "VPC setup"
    create_security_groups || handle_error "Security groups creation"
    create_ec2_instances || handle_error "EC2 instances creation"
    create_target_groups || handle_error "Target groups creation"
    register_targets || handle_error "Target registration"
    create_load_balancers || handle_error "Load balancers creation"
    create_listeners || handle_error "Listeners creation"
    configure_target_group_attributes || handle_error "Target group attributes configuration"
    validate_deployment || handle_error "Deployment validation"
    display_summary
    
    log_success "All steps completed successfully!"
    echo
    log_warning "Remember to run ./destroy.sh when you're done testing to avoid ongoing charges"
}

# Run main function
main "$@"