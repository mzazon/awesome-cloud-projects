#!/bin/bash
set -euo pipefail

# ========================================================================
# VPC Lattice TLS Passthrough Deployment Script
# 
# This script automates the deployment of the TLS passthrough solution
# using VPC Lattice, Certificate Manager, Route 53, and EC2.
# ========================================================================

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }
warn() { log "WARNING" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }

# Error handling
cleanup_on_error() {
    error "Deployment failed. Check $LOG_FILE for details."
    error "Run ./destroy.sh to clean up partial deployment."
    exit 1
}
trap cleanup_on_error ERR

# Save resource ID to state file
save_resource() {
    local key=$1
    local value=$2
    echo "${key}=${value}" >> "$STATE_FILE"
    info "Saved resource: $key = $value"
}

# Load resource ID from state file
load_resource() {
    local key=$1
    if [[ -f "$STATE_FILE" ]]; then
        grep "^${key}=" "$STATE_FILE" | cut -d'=' -f2 || echo ""
    else
        echo ""
    fi
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check required tools
    for tool in openssl curl; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    # Check if jq is available (optional but recommended)
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some output formatting may be limited."
    fi
    
    success "Prerequisites check passed"
}

# Get user inputs
get_user_inputs() {
    info "Getting deployment configuration..."
    
    # Set defaults or get from environment
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        read -p "Enter AWS region [us-east-1]: " AWS_REGION
        AWS_REGION=${AWS_REGION:-us-east-1}
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Custom domain configuration
    if [[ -z "${CUSTOM_DOMAIN:-}" ]]; then
        read -p "Enter your custom domain (e.g., api-service.example.com): " CUSTOM_DOMAIN
        if [[ -z "$CUSTOM_DOMAIN" ]]; then
            error "Custom domain is required for TLS passthrough"
            exit 1
        fi
    fi
    
    if [[ -z "${CERT_DOMAIN:-}" ]]; then
        # Extract base domain for wildcard certificate
        BASE_DOMAIN=$(echo "$CUSTOM_DOMAIN" | sed 's/^[^.]*\.//g')
        CERT_DOMAIN="*.${BASE_DOMAIN}"
        read -p "Enter certificate domain [$CERT_DOMAIN]: " USER_CERT_DOMAIN
        CERT_DOMAIN=${USER_CERT_DOMAIN:-$CERT_DOMAIN}
    fi
    
    # Generate random suffix
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    info "Configuration:"
    info "  AWS Region: $AWS_REGION"
    info "  AWS Account: $AWS_ACCOUNT_ID"
    info "  Custom Domain: $CUSTOM_DOMAIN"
    info "  Certificate Domain: $CERT_DOMAIN"
    info "  Random Suffix: $RANDOM_SUFFIX"
}

# Create VPC infrastructure
create_vpc_infrastructure() {
    info "Creating VPC infrastructure..."
    
    # Check if already exists
    VPC_ID=$(load_resource "VPC_ID")
    if [[ -n "$VPC_ID" ]]; then
        info "VPC already exists: $VPC_ID"
        return
    fi
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications \
        'ResourceType=vpc,Tags=[{Key=Name,Value=vpc-lattice-demo},{Key=Project,Value=tls-passthrough}]' \
        --query 'Vpc.VpcId' --output text)
    save_resource "VPC_ID" "$VPC_ID"
    
    # Create subnet
    SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications \
        'ResourceType=subnet,Tags=[{Key=Name,Value=lattice-targets},{Key=Project,Value=tls-passthrough}]' \
        --query 'Subnet.SubnetId' --output text)
    save_resource "SUBNET_ID" "$SUBNET_ID"
    
    # Create internet gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications \
        'ResourceType=internet-gateway,Tags=[{Key=Name,Value=lattice-demo-igw},{Key=Project,Value=tls-passthrough}]' \
        --query 'InternetGateway.InternetGatewayId' --output text)
    save_resource "IGW_ID" "$IGW_ID"
    
    # Attach internet gateway
    aws ec2 attach-internet-gateway \
        --internet-gateway-id "$IGW_ID" \
        --vpc-id "$VPC_ID"
    
    success "VPC infrastructure created: $VPC_ID"
}

# Create network configuration
create_network_configuration() {
    info "Creating network configuration..."
    
    # Load existing resources
    VPC_ID=$(load_resource "VPC_ID")
    SUBNET_ID=$(load_resource "SUBNET_ID")
    IGW_ID=$(load_resource "IGW_ID")
    
    # Check if already exists
    ROUTE_TABLE_ID=$(load_resource "ROUTE_TABLE_ID")
    if [[ -n "$ROUTE_TABLE_ID" ]]; then
        info "Route table already exists: $ROUTE_TABLE_ID"
    else
        # Create route table
        ROUTE_TABLE_ID=$(aws ec2 create-route-table \
            --vpc-id "$VPC_ID" \
            --tag-specifications \
            'ResourceType=route-table,Tags=[{Key=Name,Value=lattice-demo-rt},{Key=Project,Value=tls-passthrough}]' \
            --query 'RouteTable.RouteTableId' --output text)
        save_resource "ROUTE_TABLE_ID" "$ROUTE_TABLE_ID"
        
        # Add route to internet gateway
        aws ec2 create-route \
            --route-table-id "$ROUTE_TABLE_ID" \
            --destination-cidr-block 0.0.0.0/0 \
            --gateway-id "$IGW_ID"
        
        # Associate route table with subnet
        aws ec2 associate-route-table \
            --route-table-id "$ROUTE_TABLE_ID" \
            --subnet-id "$SUBNET_ID"
    fi
    
    # Check if security group exists
    SECURITY_GROUP_ID=$(load_resource "SECURITY_GROUP_ID")
    if [[ -n "$SECURITY_GROUP_ID" ]]; then
        info "Security group already exists: $SECURITY_GROUP_ID"
    else
        # Create security group
        SECURITY_GROUP_ID=$(aws ec2 create-security-group \
            --group-name "lattice-targets-sg-${RANDOM_SUFFIX}" \
            --description "Security group for VPC Lattice target instances" \
            --vpc-id "$VPC_ID" \
            --tag-specifications \
            'ResourceType=security-group,Tags=[{Key=Name,Value=lattice-targets-sg},{Key=Project,Value=tls-passthrough}]' \
            --query 'GroupId' --output text)
        save_resource "SECURITY_GROUP_ID" "$SECURITY_GROUP_ID"
        
        # Allow HTTPS traffic from VPC Lattice service network range
        aws ec2 authorize-security-group-ingress \
            --group-id "$SECURITY_GROUP_ID" \
            --protocol tcp \
            --port 443 \
            --cidr 10.0.0.0/8
    fi
    
    success "Network configuration completed"
}

# Request SSL certificate
request_ssl_certificate() {
    info "Requesting SSL/TLS certificate..."
    
    # Check if already exists
    CERT_ARN=$(load_resource "CERT_ARN")
    if [[ -n "$CERT_ARN" ]]; then
        info "Certificate already exists: $CERT_ARN"
        return
    fi
    
    # Request certificate
    CERT_ARN=$(aws acm request-certificate \
        --domain-name "$CERT_DOMAIN" \
        --validation-method DNS \
        --subject-alternative-names "$CUSTOM_DOMAIN" \
        --tags Key=Name,Value=lattice-tls-passthrough,Key=Project,Value=tls-passthrough \
        --query 'CertificateArn' --output text)
    save_resource "CERT_ARN" "$CERT_ARN"
    
    warn "Certificate validation required!"
    warn "Please complete DNS validation in ACM console:"
    warn "https://console.aws.amazon.com/acm/"
    warn "Certificate ARN: $CERT_ARN"
    
    # Wait for user confirmation
    read -p "Press Enter after completing certificate validation..."
    
    # Verify certificate status
    local max_attempts=30
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        CERT_STATUS=$(aws acm describe-certificate \
            --certificate-arn "$CERT_ARN" \
            --query 'Certificate.Status' --output text)
        
        if [[ "$CERT_STATUS" == "ISSUED" ]]; then
            success "Certificate validated successfully"
            return
        elif [[ "$CERT_STATUS" == "FAILED" ]]; then
            error "Certificate validation failed"
            exit 1
        fi
        
        info "Certificate status: $CERT_STATUS (attempt $attempt/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    error "Certificate validation timeout"
    exit 1
}

# Deploy target instances
deploy_target_instances() {
    info "Deploying target EC2 instances..."
    
    # Load existing resources
    SUBNET_ID=$(load_resource "SUBNET_ID")
    SECURITY_GROUP_ID=$(load_resource "SECURITY_GROUP_ID")
    
    # Check if instances already exist
    INSTANCE_1=$(load_resource "INSTANCE_1")
    INSTANCE_2=$(load_resource "INSTANCE_2")
    
    if [[ -n "$INSTANCE_1" && -n "$INSTANCE_2" ]]; then
        info "Target instances already exist: $INSTANCE_1, $INSTANCE_2"
        return
    fi
    
    # Get latest Amazon Linux 2023 AMI
    AMI_ID=$(aws ssm get-parameters \
        --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64 \
        --query 'Parameters[0].Value' --output text)
    
    # Create user data script
    cat > "${SCRIPT_DIR}/user-data.sh" << EOF
#!/bin/bash
dnf update -y
dnf install -y httpd mod_ssl openssl

# Generate self-signed certificate for target
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \\
    -keyout /etc/pki/tls/private/server.key \\
    -out /etc/pki/tls/certs/server.crt \\
    -subj "/C=US/ST=State/L=City/O=Organization/CN=${CUSTOM_DOMAIN}"

# Configure SSL virtual host
cat > /etc/httpd/conf.d/ssl.conf << 'SSLCONF'
LoadModule ssl_module modules/mod_ssl.so
Listen 443
<VirtualHost *:443>
    ServerName ${CUSTOM_DOMAIN}
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile /etc/pki/tls/certs/server.crt
    SSLCertificateKeyFile /etc/pki/tls/private/server.key
    SSLProtocol TLSv1.2 TLSv1.3
    SSLCipherSuite ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS
</VirtualHost>
SSLCONF

# Create simple HTTPS response with instance identification
INSTANCE_ID=\$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
echo "<h1>Target Instance Response - TLS Passthrough Success</h1>" > /var/www/html/index.html
echo "<p>Instance ID: \${INSTANCE_ID}</p>" >> /var/www/html/index.html
echo "<p>Timestamp: \$(date)</p>" >> /var/www/html/index.html

# Start Apache
systemctl enable httpd
systemctl start httpd
EOF
    
    if [[ -z "$INSTANCE_1" ]]; then
        # Launch first instance
        INSTANCE_1=$(aws ec2 run-instances \
            --image-id "$AMI_ID" \
            --instance-type t3.micro \
            --subnet-id "$SUBNET_ID" \
            --security-group-ids "$SECURITY_GROUP_ID" \
            --user-data "file://${SCRIPT_DIR}/user-data.sh" \
            --tag-specifications \
            'ResourceType=instance,Tags=[{Key=Name,Value=lattice-target-1},{Key=Project,Value=tls-passthrough}]' \
            --query 'Instances[0].InstanceId' --output text)
        save_resource "INSTANCE_1" "$INSTANCE_1"
    fi
    
    if [[ -z "$INSTANCE_2" ]]; then
        # Launch second instance
        INSTANCE_2=$(aws ec2 run-instances \
            --image-id "$AMI_ID" \
            --instance-type t3.micro \
            --subnet-id "$SUBNET_ID" \
            --security-group-ids "$SECURITY_GROUP_ID" \
            --user-data "file://${SCRIPT_DIR}/user-data.sh" \
            --tag-specifications \
            'ResourceType=instance,Tags=[{Key=Name,Value=lattice-target-2},{Key=Project,Value=tls-passthrough}]' \
            --query 'Instances[0].InstanceId' --output text)
        save_resource "INSTANCE_2" "$INSTANCE_2"
    fi
    
    # Wait for instances to be running
    info "Waiting for instances to be running..."
    aws ec2 wait instance-running --instance-ids "$INSTANCE_1" "$INSTANCE_2"
    
    success "Target instances deployed: $INSTANCE_1, $INSTANCE_2"
}

# Create VPC Lattice service network
create_service_network() {
    info "Creating VPC Lattice service network..."
    
    # Load existing resources
    VPC_ID=$(load_resource "VPC_ID")
    
    # Check if already exists
    SERVICE_NETWORK_ID=$(load_resource "SERVICE_NETWORK_ID")
    if [[ -n "$SERVICE_NETWORK_ID" ]]; then
        info "Service network already exists: $SERVICE_NETWORK_ID"
        return
    fi
    
    # Create service network
    SERVICE_NETWORK_ID=$(aws vpc-lattice create-service-network \
        --name "tls-passthrough-network-${RANDOM_SUFFIX}" \
        --auth-type "NONE" \
        --tags Key=Name,Value=tls-passthrough-network,Key=Project,Value=tls-passthrough \
        --query 'id' --output text)
    save_resource "SERVICE_NETWORK_ID" "$SERVICE_NETWORK_ID"
    
    # Associate VPC with service network
    aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier "$SERVICE_NETWORK_ID" \
        --vpc-identifier "$VPC_ID" \
        --tags Key=Name,Value=target-vpc-association,Key=Project,Value=tls-passthrough
    
    success "Service network created: $SERVICE_NETWORK_ID"
}

# Create target group
create_target_group() {
    info "Creating TCP target group for TLS passthrough..."
    
    # Load existing resources
    VPC_ID=$(load_resource "VPC_ID")
    INSTANCE_1=$(load_resource "INSTANCE_1")
    INSTANCE_2=$(load_resource "INSTANCE_2")
    
    # Check if already exists
    TARGET_GROUP_ARN=$(load_resource "TARGET_GROUP_ARN")
    if [[ -n "$TARGET_GROUP_ARN" ]]; then
        info "Target group already exists: $TARGET_GROUP_ARN"
        return
    fi
    
    # Create target group
    TARGET_GROUP_ARN=$(aws vpc-lattice create-target-group \
        --name "tls-passthrough-targets-${RANDOM_SUFFIX}" \
        --type "INSTANCE" \
        --protocol "TCP" \
        --port 443 \
        --vpc-identifier "$VPC_ID" \
        --health-check '{
            "enabled": true,
            "protocol": "TCP",
            "port": 443,
            "healthyThresholdCount": 2,
            "unhealthyThresholdCount": 2,
            "intervalSeconds": 30,
            "timeoutSeconds": 5
        }' \
        --tags Key=Name,Value=tls-passthrough-targets,Key=Project,Value=tls-passthrough \
        --query 'arn' --output text)
    save_resource "TARGET_GROUP_ARN" "$TARGET_GROUP_ARN"
    
    # Register target instances
    aws vpc-lattice register-targets \
        --target-group-identifier "$TARGET_GROUP_ARN" \
        --targets "id=${INSTANCE_1},port=443" "id=${INSTANCE_2},port=443"
    
    success "TCP target group created: $TARGET_GROUP_ARN"
}

# Create VPC Lattice service
create_lattice_service() {
    info "Creating VPC Lattice service with custom domain..."
    
    # Load existing resources
    SERVICE_NETWORK_ID=$(load_resource "SERVICE_NETWORK_ID")
    CERT_ARN=$(load_resource "CERT_ARN")
    
    # Check if already exists
    SERVICE_ARN=$(load_resource "SERVICE_ARN")
    if [[ -n "$SERVICE_ARN" ]]; then
        info "VPC Lattice service already exists: $SERVICE_ARN"
        return
    fi
    
    # Create service
    SERVICE_ARN=$(aws vpc-lattice create-service \
        --name "tls-passthrough-service-${RANDOM_SUFFIX}" \
        --custom-domain-name "$CUSTOM_DOMAIN" \
        --certificate-arn "$CERT_ARN" \
        --auth-type "NONE" \
        --tags Key=Name,Value=tls-passthrough-service,Key=Project,Value=tls-passthrough \
        --query 'arn' --output text)
    save_resource "SERVICE_ARN" "$SERVICE_ARN"
    
    # Associate service with service network
    aws vpc-lattice create-service-network-service-association \
        --service-network-identifier "$SERVICE_NETWORK_ID" \
        --service-identifier "$SERVICE_ARN" \
        --tags Key=Name,Value=service-association,Key=Project,Value=tls-passthrough
    
    success "VPC Lattice service created: $SERVICE_ARN"
}

# Configure TLS passthrough listener
configure_tls_listener() {
    info "Configuring TLS passthrough listener..."
    
    # Load existing resources
    SERVICE_ARN=$(load_resource "SERVICE_ARN")
    TARGET_GROUP_ARN=$(load_resource "TARGET_GROUP_ARN")
    
    # Check if already exists
    LISTENER_ARN=$(load_resource "LISTENER_ARN")
    if [[ -n "$LISTENER_ARN" ]]; then
        info "TLS listener already exists: $LISTENER_ARN"
        return
    fi
    
    # Create listener
    LISTENER_ARN=$(aws vpc-lattice create-listener \
        --service-identifier "$SERVICE_ARN" \
        --name "tls-passthrough-listener" \
        --protocol "TLS_PASSTHROUGH" \
        --port 443 \
        --default-action "{
            \"forward\": {
                \"targetGroups\": [
                    {
                        \"targetGroupIdentifier\": \"${TARGET_GROUP_ARN}\",
                        \"weight\": 100
                    }
                ]
            }
        }" \
        --tags Key=Name,Value=tls-passthrough-listener,Key=Project,Value=tls-passthrough \
        --query 'arn' --output text)
    save_resource "LISTENER_ARN" "$LISTENER_ARN"
    
    success "TLS passthrough listener created: $LISTENER_ARN"
}

# Configure DNS
configure_dns() {
    info "Configuring Route 53 DNS resolution..."
    
    # Load existing resources
    SERVICE_ARN=$(load_resource "SERVICE_ARN")
    
    # Get VPC Lattice service DNS name
    SERVICE_DNS=$(aws vpc-lattice get-service \
        --service-identifier "$SERVICE_ARN" \
        --query 'dnsEntry.domainName' --output text)
    save_resource "SERVICE_DNS" "$SERVICE_DNS"
    
    info "VPC Lattice service DNS: $SERVICE_DNS"
    
    # Extract base domain
    BASE_DOMAIN=$(echo "$CUSTOM_DOMAIN" | sed 's/^[^.]*\.//g')
    
    # Check if hosted zone exists
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
        --dns-name "$BASE_DOMAIN" \
        --query 'HostedZones[0].Id' --output text 2>/dev/null || echo "None")
    
    if [[ "$HOSTED_ZONE_ID" == "None" ]]; then
        warn "No hosted zone found for $BASE_DOMAIN"
        warn "Please create a hosted zone manually or update DNS configuration"
        warn "Point $CUSTOM_DOMAIN to $SERVICE_DNS"
        save_resource "HOSTED_ZONE_ID" "manual"
    else
        save_resource "HOSTED_ZONE_ID" "$HOSTED_ZONE_ID"
        
        # Create DNS record
        cat > "${SCRIPT_DIR}/dns-change.json" << EOF
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "${CUSTOM_DOMAIN}",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [
                    {
                        "Value": "${SERVICE_DNS}"
                    }
                ]
            }
        }
    ]
}
EOF
        
        CHANGE_ID=$(aws route53 change-resource-record-sets \
            --hosted-zone-id "$HOSTED_ZONE_ID" \
            --change-batch "file://${SCRIPT_DIR}/dns-change.json" \
            --query 'ChangeInfo.Id' --output text)
        save_resource "CHANGE_ID" "$CHANGE_ID"
        
        success "DNS configuration completed for $CUSTOM_DOMAIN"
    fi
}

# Validate deployment
validate_deployment() {
    info "Validating deployment..."
    
    # Load resources
    SERVICE_ARN=$(load_resource "SERVICE_ARN")
    TARGET_GROUP_ARN=$(load_resource "TARGET_GROUP_ARN")
    
    # Check service status
    SERVICE_STATUS=$(aws vpc-lattice get-service \
        --service-identifier "$SERVICE_ARN" \
        --query 'status' --output text)
    info "Service status: $SERVICE_STATUS"
    
    # Check target health
    info "Target health status:"
    aws vpc-lattice list-targets \
        --target-group-identifier "$TARGET_GROUP_ARN" \
        --query 'items[*].{Id:id,Status:status}' \
        --output table
    
    # Wait for DNS propagation
    info "Waiting 60 seconds for DNS propagation..."
    sleep 60
    
    # Test connectivity
    info "Testing HTTPS connectivity..."
    if curl -k -s --max-time 10 "https://${CUSTOM_DOMAIN}" > /dev/null; then
        success "HTTPS connectivity test passed"
    else
        warn "HTTPS connectivity test failed - this may be normal during initial deployment"
    fi
    
    success "Deployment validation completed"
}

# Main deployment function
main() {
    info "Starting VPC Lattice TLS Passthrough deployment..."
    info "Log file: $LOG_FILE"
    
    # Initialize log file
    echo "=== VPC Lattice TLS Passthrough Deployment ===" > "$LOG_FILE"
    echo "Started at: $(date)" >> "$LOG_FILE"
    
    check_prerequisites
    get_user_inputs
    
    # Create infrastructure step by step
    create_vpc_infrastructure
    create_network_configuration
    request_ssl_certificate
    deploy_target_instances
    create_service_network
    create_target_group
    create_lattice_service
    configure_tls_listener
    configure_dns
    validate_deployment
    
    success "Deployment completed successfully!"
    success "Custom domain: https://$CUSTOM_DOMAIN"
    success "State file: $STATE_FILE"
    success "Log file: $LOG_FILE"
    
    info "Next steps:"
    info "1. Wait 5-10 minutes for target instances to complete setup"
    info "2. Test the deployment with: curl -k https://$CUSTOM_DOMAIN"
    info "3. Check target health in VPC Lattice console"
    info "4. Run ./destroy.sh to clean up when done"
}

# Run main function
main "$@"