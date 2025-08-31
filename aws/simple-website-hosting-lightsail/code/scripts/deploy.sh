#!/bin/bash

# AWS Lightsail WordPress Deployment Script
# This script deploys a complete WordPress hosting solution using AWS Lightsail
# Includes instance creation, static IP allocation, and firewall configuration

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output formatting
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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if Lightsail is available in the current region
    local region=$(aws configure get region 2>/dev/null || echo "us-east-1")
    if [[ -z "$region" ]]; then
        warning "No default region set. Using us-east-1"
        export AWS_DEFAULT_REGION="us-east-1"
    fi
    
    success "Prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    export AWS_DEFAULT_REGION=${AWS_REGION}
    
    # Generate unique identifier for resources
    local random_suffix
    if command -v aws secretsmanager &> /dev/null; then
        random_suffix=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    else
        random_suffix="$(date +%s | tail -c 6)"
    fi
    
    # Set Lightsail resource names
    export INSTANCE_NAME="wordpress-site-${random_suffix}"
    export STATIC_IP_NAME="wordpress-ip-${random_suffix}"
    
    # Save environment to file for cleanup script
    cat > .lightsail_env << EOF
export INSTANCE_NAME="${INSTANCE_NAME}"
export STATIC_IP_NAME="${STATIC_IP_NAME}"
export AWS_REGION="${AWS_REGION}"
EOF
    
    success "Environment configured"
    log "Instance name: ${INSTANCE_NAME}"
    log "Static IP name: ${STATIC_IP_NAME}"
    log "AWS Region: ${AWS_REGION}"
}

# Function to create WordPress Lightsail instance
create_wordpress_instance() {
    log "Creating WordPress Lightsail instance..."
    
    # Check if instance already exists
    if aws lightsail get-instance --instance-name "${INSTANCE_NAME}" &>/dev/null; then
        warning "Instance ${INSTANCE_NAME} already exists. Skipping creation."
        return 0
    fi
    
    # Create WordPress instance
    aws lightsail create-instances \
        --instance-names "${INSTANCE_NAME}" \
        --availability-zone "${AWS_REGION}a" \
        --blueprint-id "wordpress" \
        --bundle-id "nano_3_0" \
        --tags key=Purpose,value=WebsiteHosting \
               key=Environment,value=Production \
               key=CreatedBy,value=LightsailDeployScript
    
    success "WordPress instance ${INSTANCE_NAME} creation initiated"
}

# Function to wait for instance to become available
wait_for_instance() {
    log "Waiting for instance to become available..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local instance_state=$(aws lightsail get-instance \
            --instance-name "${INSTANCE_NAME}" \
            --query 'instance.state.name' \
            --output text 2>/dev/null || echo "unknown")
        
        if [ "$instance_state" = "running" ]; then
            success "Instance is now running"
            return 0
        else
            log "Instance state: $instance_state - waiting... (attempt $attempt/$max_attempts)"
            sleep 20
        fi
        
        ((attempt++))
    done
    
    error "Instance failed to start within expected time"
}

# Function to create and attach static IP
setup_static_ip() {
    log "Setting up static IP address..."
    
    # Check if static IP already exists
    if aws lightsail get-static-ip --static-ip-name "${STATIC_IP_NAME}" &>/dev/null; then
        warning "Static IP ${STATIC_IP_NAME} already exists."
    else
        # Allocate static IP address
        aws lightsail allocate-static-ip --static-ip-name "${STATIC_IP_NAME}"
        success "Static IP ${STATIC_IP_NAME} allocated"
    fi
    
    # Check if already attached
    local attached_instance=$(aws lightsail get-static-ip \
        --static-ip-name "${STATIC_IP_NAME}" \
        --query 'staticIp.attachedTo' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$attached_instance" = "${INSTANCE_NAME}" ]; then
        warning "Static IP already attached to instance"
    else
        # Attach static IP to the WordPress instance
        aws lightsail attach-static-ip \
            --static-ip-name "${STATIC_IP_NAME}" \
            --instance-name "${INSTANCE_NAME}"
        success "Static IP attached to instance"
    fi
    
    # Get the static IP address
    local static_ip=$(aws lightsail get-static-ip \
        --static-ip-name "${STATIC_IP_NAME}" \
        --query 'staticIp.ipAddress' \
        --output text)
    
    # Save static IP to environment file
    echo "export STATIC_IP=\"${static_ip}\"" >> .lightsail_env
    
    success "Static IP ${static_ip} configured"
}

# Function to configure firewall rules
configure_firewall() {
    log "Configuring firewall rules for web traffic..."
    
    # Open HTTP, HTTPS, and SSH ports
    aws lightsail put-instance-public-ports \
        --instance-name "${INSTANCE_NAME}" \
        --port-infos fromPort=80,toPort=80,protocol=TCP,cidrSources=0.0.0.0/0 \
                     fromPort=443,toPort=443,protocol=TCP,cidrSources=0.0.0.0/0 \
                     fromPort=22,toPort=22,protocol=TCP,cidrSources=0.0.0.0/0
    
    success "Firewall configured for web traffic (HTTP/HTTPS/SSH)"
}

# Function to display access information
display_access_info() {
    local static_ip=$(aws lightsail get-static-ip \
        --static-ip-name "${STATIC_IP_NAME}" \
        --query 'staticIp.ipAddress' \
        --output text)
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    success "WordPress deployment completed successfully!"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "WordPress Access Information:"
    echo "  🌐 Website URL: http://${static_ip}"
    echo "  🔧 Admin URL: http://${static_ip}/wp-admin"
    echo "  👤 Username: user"
    echo "  🔑 Password: Connect via SSH to retrieve"
    echo ""
    echo "SSH Access:"
    echo "  📡 SSH Command: ssh -i ~/.ssh/your-key-pair.pem bitnami@${static_ip}"
    echo "  🔑 Password Command: sudo cat /home/bitnami/bitnami_application_password"
    echo ""
    echo "Resource Information:"
    echo "  📦 Instance: ${INSTANCE_NAME}"
    echo "  🌐 Static IP: ${STATIC_IP_NAME} (${static_ip})"
    echo "  📍 Region: ${AWS_REGION}"
    echo ""
    echo "Next Steps:"
    echo "  1. Connect via SSH to retrieve the WordPress admin password"
    echo "  2. Access the WordPress admin panel to configure your site"
    echo "  3. Consider setting up a custom domain via Lightsail DNS"
    echo "  4. Enable automatic backups in the Lightsail console"
    echo ""
    echo "💰 Estimated Cost: \$5-12 USD/month (3 months free with AWS Free Tier)"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo "═══════════════════════════════════════════════════════════════"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check instance status
    local instance_info=$(aws lightsail get-instance \
        --instance-name "${INSTANCE_NAME}" \
        --query 'instance.{Name:name,State:state.name,IP:publicIpAddress}' \
        --output table 2>/dev/null || echo "Failed to get instance info")
    
    if [[ "$instance_info" == *"running"* ]]; then
        success "Instance validation passed"
    else
        error "Instance validation failed"
    fi
    
    # Test web server response
    local static_ip=$(aws lightsail get-static-ip \
        --static-ip-name "${STATIC_IP_NAME}" \
        --query 'staticIp.ipAddress' \
        --output text)
    
    # Give the web server time to start
    log "Testing web server response (this may take a moment)..."
    sleep 30
    
    if curl -sSf --max-time 10 "http://${static_ip}" >/dev/null 2>&1; then
        success "Web server is responding"
    else
        warning "Web server test failed - this may be normal if WordPress is still starting up"
        log "You can test manually by visiting: http://${static_ip}"
    fi
    
    # Verify firewall configuration
    local port_states=$(aws lightsail get-instance-port-states \
        --instance-name "${INSTANCE_NAME}" \
        --query 'portStates[?state==`open`].{Port:fromPort,Protocol:protocol}' \
        --output table 2>/dev/null || echo "Failed to get port states")
    
    if [[ "$port_states" == *"80"* ]] && [[ "$port_states" == *"443"* ]]; then
        success "Firewall validation passed"
    else
        warning "Firewall validation failed - ports may not be configured correctly"
    fi
}

# Main execution function
main() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "          AWS Lightsail WordPress Deployment Script"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    check_prerequisites
    setup_environment
    create_wordpress_instance
    wait_for_instance
    setup_static_ip
    configure_firewall
    validate_deployment
    display_access_info
}

# Handle script interruption
trap 'error "Script interrupted. Run ./destroy.sh to clean up any created resources."' INT TERM

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi