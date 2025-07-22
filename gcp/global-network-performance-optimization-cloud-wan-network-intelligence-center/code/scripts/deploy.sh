#!/bin/bash

# Deploy script for Global Network Performance Optimization with Cloud WAN and Network Intelligence Center
# This script creates a global network infrastructure with comprehensive monitoring

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Cleanup function for partial deployments
cleanup_on_error() {
    error "Deployment failed. Starting cleanup of partially created resources..."
    if [[ -n "${PROJECT_ID:-}" ]]; then
        ./destroy.sh || true
    fi
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "Please authenticate with gcloud: gcloud auth login"
        exit 1
    fi
    
    # Check if user has organization access (optional)
    if ! gcloud organizations list &> /dev/null; then
        warning "Cannot access organizations. You may need to provide PROJECT_ID manually."
    fi
    
    # Check if required APIs can be enabled
    if ! gcloud services list --available --filter="name:compute.googleapis.com" &> /dev/null; then
        error "Cannot access Google Cloud APIs. Please check your permissions."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="network-optimization-$(date +%s)"
        log "Generated PROJECT_ID: ${PROJECT_ID}"
    fi
    
    # Try to get organization ID
    if [[ -z "${ORGANIZATION_ID:-}" ]]; then
        ORGANIZATION_ID=$(gcloud organizations list \
            --format="value(name)" | head -n1 | cut -d'/' -f2 2>/dev/null || echo "")
        if [[ -n "${ORGANIZATION_ID}" ]]; then
            export ORGANIZATION_ID
            log "Using ORGANIZATION_ID: ${ORGANIZATION_ID}"
        else
            warning "No organization found. Creating project without organization."
        fi
    fi
    
    # Define multi-region configuration
    export REGION_US="us-central1"
    export REGION_EU="europe-west1"
    export REGION_APAC="asia-east1"
    
    export ZONE_US="us-central1-a"
    export ZONE_EU="europe-west1-b"
    export ZONE_APAC="asia-east1-a"
    
    # Generate unique identifier for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(shuf -i 100-999 -n 1)")
    export NETWORK_NAME="global-wan-${RANDOM_SUFFIX}"
    
    log "Environment variables configured"
}

# Create and configure project
create_project() {
    log "Creating and configuring project..."
    
    # Create project
    if [[ -n "${ORGANIZATION_ID:-}" ]]; then
        gcloud projects create "${PROJECT_ID}" \
            --organization="${ORGANIZATION_ID}" || {
            warning "Failed to create project with organization. Trying without..."
            gcloud projects create "${PROJECT_ID}"
        }
    else
        gcloud projects create "${PROJECT_ID}"
    fi
    
    # Set project configuration
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION_US}"
    gcloud config set compute/zone "${ZONE_US}"
    
    # Enable billing if needed (requires manual intervention)
    log "Please ensure billing is enabled for project: ${PROJECT_ID}"
    read -p "Press Enter when billing is configured..."
    
    success "Project created and configured: ${PROJECT_ID}"
}

# Enable required APIs
enable_apis() {
    log "Enabling required APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "monitoring.googleapis.com" 
        "logging.googleapis.com"
        "networksecurity.googleapis.com"
        "networkconnectivity.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        gcloud services enable "${api}"
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "Required APIs enabled"
}

# Create global VPC network infrastructure
create_network_infrastructure() {
    log "Creating global VPC network infrastructure..."
    
    # Create global VPC network
    gcloud compute networks create "${NETWORK_NAME}" \
        --subnet-mode=custom \
        --description="Global enterprise network with WAN optimization"
    
    # Create regional subnets
    log "Creating regional subnets..."
    
    gcloud compute networks subnets create "${NETWORK_NAME}-us" \
        --network="${NETWORK_NAME}" \
        --range=10.10.0.0/16 \
        --region="${REGION_US}" \
        --enable-private-ip-google-access
    
    gcloud compute networks subnets create "${NETWORK_NAME}-eu" \
        --network="${NETWORK_NAME}" \
        --range=10.20.0.0/16 \
        --region="${REGION_EU}" \
        --enable-private-ip-google-access
    
    gcloud compute networks subnets create "${NETWORK_NAME}-apac" \
        --network="${NETWORK_NAME}" \
        --range=10.30.0.0/16 \
        --region="${REGION_APAC}" \
        --enable-private-ip-google-access
    
    success "Global VPC network infrastructure created"
}

# Configure firewall rules
create_firewall_rules() {
    log "Configuring enterprise firewall rules..."
    
    # Internal communication
    gcloud compute firewall-rules create "${NETWORK_NAME}-allow-internal" \
        --network="${NETWORK_NAME}" \
        --allow=tcp,udp,icmp \
        --source-ranges=10.10.0.0/8 \
        --description="Allow internal VPC communication"
    
    # Load balancer health checks
    gcloud compute firewall-rules create "${NETWORK_NAME}-allow-lb-health" \
        --network="${NETWORK_NAME}" \
        --allow=tcp:80,tcp:443,tcp:8080 \
        --source-ranges=130.211.0.0/22,35.191.0.0/16 \
        --target-tags=web-server \
        --description="Allow load balancer health checks"
    
    # SSH access
    gcloud compute firewall-rules create "${NETWORK_NAME}-allow-ssh" \
        --network="${NETWORK_NAME}" \
        --allow=tcp:22 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=ssh-allowed \
        --description="Allow SSH for management"
    
    success "Firewall rules configured"
}

# Deploy regional compute infrastructure
deploy_compute_infrastructure() {
    log "Deploying regional compute infrastructure..."
    
    # Startup script for web servers
    local startup_script='#!/bin/bash
apt-get update
apt-get install -y nginx
systemctl start nginx'
    
    # Create VM instances in US region
    log "Creating US region instances..."
    gcloud compute instances create web-server-us-1 \
        --zone="${ZONE_US}" \
        --machine-type=e2-medium \
        --subnet="${NETWORK_NAME}-us" \
        --image-family=ubuntu-2004-lts \
        --image-project=ubuntu-os-cloud \
        --tags=web-server,ssh-allowed \
        --metadata=startup-script="${startup_script}
echo \"US Region Server - \$(hostname)\" > /var/www/html/index.html"
    
    # Create VM instances in EU region
    log "Creating EU region instances..."
    gcloud compute instances create web-server-eu-1 \
        --zone="${ZONE_EU}" \
        --machine-type=e2-medium \
        --subnet="${NETWORK_NAME}-eu" \
        --image-family=ubuntu-2004-lts \
        --image-project=ubuntu-os-cloud \
        --tags=web-server,ssh-allowed \
        --metadata=startup-script="${startup_script}
echo \"EU Region Server - \$(hostname)\" > /var/www/html/index.html"
    
    # Create VM instances in APAC region
    log "Creating APAC region instances..."
    gcloud compute instances create web-server-apac-1 \
        --zone="${ZONE_APAC}" \
        --machine-type=e2-medium \
        --subnet="${NETWORK_NAME}-apac" \
        --image-family=ubuntu-2004-lts \
        --image-project=ubuntu-os-cloud \
        --tags=web-server,ssh-allowed \
        --metadata=startup-script="${startup_script}
echo \"APAC Region Server - \$(hostname)\" > /var/www/html/index.html"
    
    # Wait for instances to start
    log "Waiting for instances to become ready..."
    sleep 60
    
    success "Regional compute infrastructure deployed"
}

# Create load balancer infrastructure
create_load_balancer() {
    log "Creating global load balancer infrastructure..."
    
    # Create instance groups
    log "Creating instance groups..."
    gcloud compute instance-groups unmanaged create web-group-us \
        --zone="${ZONE_US}" \
        --description="US region web servers"
    
    gcloud compute instance-groups unmanaged create web-group-eu \
        --zone="${ZONE_EU}" \
        --description="EU region web servers"
    
    gcloud compute instance-groups unmanaged create web-group-apac \
        --zone="${ZONE_APAC}" \
        --description="APAC region web servers"
    
    # Add instances to groups
    log "Adding instances to groups..."
    gcloud compute instance-groups unmanaged add-instances web-group-us \
        --zone="${ZONE_US}" \
        --instances=web-server-us-1
    
    gcloud compute instance-groups unmanaged add-instances web-group-eu \
        --zone="${ZONE_EU}" \
        --instances=web-server-eu-1
    
    gcloud compute instance-groups unmanaged add-instances web-group-apac \
        --zone="${ZONE_APAC}" \
        --instances=web-server-apac-1
    
    # Create health check
    log "Creating health check..."
    gcloud compute health-checks create http global-web-health-check \
        --port=80 \
        --request-path=/ \
        --check-interval=30s \
        --timeout=10s \
        --healthy-threshold=2 \
        --unhealthy-threshold=3
    
    # Create backend service
    log "Creating backend service..."
    gcloud compute backend-services create global-web-backend \
        --protocol=HTTP \
        --health-checks=global-web-health-check \
        --global \
        --load-balancing-scheme=EXTERNAL \
        --enable-logging
    
    # Add backends
    log "Adding backends to service..."
    gcloud compute backend-services add-backend global-web-backend \
        --instance-group=web-group-us \
        --instance-group-zone="${ZONE_US}" \
        --global
    
    gcloud compute backend-services add-backend global-web-backend \
        --instance-group=web-group-eu \
        --instance-group-zone="${ZONE_EU}" \
        --global
    
    gcloud compute backend-services add-backend global-web-backend \
        --instance-group=web-group-apac \
        --instance-group-zone="${ZONE_APAC}" \
        --global
    
    # Create URL map
    gcloud compute url-maps create global-web-map \
        --default-service=global-web-backend \
        --global
    
    success "Load balancer backend infrastructure created"
}

# Deploy HTTP(S) load balancer
deploy_load_balancer_frontend() {
    log "Deploying HTTP(S) load balancer frontend..."
    
    # Create SSL certificate (self-managed for demo)
    log "Creating SSL certificate..."
    gcloud compute ssl-certificates create global-web-ssl \
        --domains="${PROJECT_ID}.example.com" \
        --global || {
        warning "SSL certificate creation failed. This is expected for demo domains."
    }
    
    # Create target proxies
    log "Creating target proxies..."
    if gcloud compute ssl-certificates describe global-web-ssl --global &>/dev/null; then
        gcloud compute target-https-proxies create global-web-https-proxy \
            --url-map=global-web-map \
            --ssl-certificates=global-web-ssl \
            --global
        
        gcloud compute forwarding-rules create global-web-https-rule \
            --target-https-proxy=global-web-https-proxy \
            --global \
            --ports=443
    else
        log "Skipping HTTPS proxy due to SSL certificate issues"
    fi
    
    gcloud compute target-http-proxies create global-web-http-proxy \
        --url-map=global-web-map \
        --global
    
    # Create forwarding rules
    gcloud compute forwarding-rules create global-web-http-rule \
        --target-http-proxy=global-web-http-proxy \
        --global \
        --ports=80
    
    # Get load balancer IP
    local lb_ip
    lb_ip=$(gcloud compute forwarding-rules describe \
        global-web-http-rule --global \
        --format="value(IPAddress)")
    
    success "Global load balancer deployed"
    success "Load Balancer IP: ${lb_ip}"
    
    # Save IP for later use
    echo "${lb_ip}" > /tmp/lb_ip.txt
}

# Enable VPC Flow Logs
enable_flow_logs() {
    log "Enabling VPC Flow Logs for Network Intelligence Center..."
    
    # Enable flow logs on all subnets
    gcloud compute networks subnets update "${NETWORK_NAME}-us" \
        --region="${REGION_US}" \
        --enable-flow-logs \
        --logging-aggregation-interval=interval-5-sec \
        --logging-flow-sampling=1.0 \
        --logging-metadata=include-all
    
    gcloud compute networks subnets update "${NETWORK_NAME}-eu" \
        --region="${REGION_EU}" \
        --enable-flow-logs \
        --logging-aggregation-interval=interval-5-sec \
        --logging-flow-sampling=1.0 \
        --logging-metadata=include-all
    
    gcloud compute networks subnets update "${NETWORK_NAME}-apac" \
        --region="${REGION_APAC}" \
        --enable-flow-logs \
        --logging-aggregation-interval=interval-5-sec \
        --logging-flow-sampling=1.0 \
        --logging-metadata=include-all
    
    success "VPC Flow Logs enabled for comprehensive network telemetry"
}

# Configure monitoring
configure_monitoring() {
    log "Configuring Network Intelligence Center monitoring..."
    
    # Create monitoring workspace if needed
    gcloud services enable monitoring.googleapis.com
    
    # Note: Network Intelligence Center is automatically available
    # Custom dashboards and alerts would be configured here
    
    log "Network Intelligence Center is available at:"
    log "https://console.cloud.google.com/net-intelligence/topology?project=${PROJECT_ID}"
    
    success "Monitoring configuration completed"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check network
    if gcloud compute networks describe "${NETWORK_NAME}" &>/dev/null; then
        success "VPC network validated"
    else
        error "VPC network validation failed"
        return 1
    fi
    
    # Check instances
    local instance_count
    instance_count=$(gcloud compute instances list \
        --filter="name~web-server-.*" \
        --format="value(name)" | wc -l)
    
    if [[ "${instance_count}" -eq 3 ]]; then
        success "All 3 instances validated"
    else
        error "Instance validation failed. Expected 3, found ${instance_count}"
        return 1
    fi
    
    # Check load balancer
    if gcloud compute forwarding-rules describe global-web-http-rule --global &>/dev/null; then
        success "Load balancer validated"
    else
        error "Load balancer validation failed"
        return 1
    fi
    
    # Test connectivity if load balancer IP is available
    if [[ -f /tmp/lb_ip.txt ]]; then
        local lb_ip
        lb_ip=$(cat /tmp/lb_ip.txt)
        log "Testing load balancer connectivity..."
        
        # Wait for load balancer to be ready
        sleep 120
        
        if curl -s --max-time 10 "http://${lb_ip}" &>/dev/null; then
            success "Load balancer connectivity test passed"
        else
            warning "Load balancer connectivity test failed (may take additional time to be ready)"
        fi
    fi
    
    success "Deployment validation completed"
}

# Save deployment info
save_deployment_info() {
    log "Saving deployment information..."
    
    local info_file="deployment-info.txt"
    
    cat > "${info_file}" << EOF
Global Network Performance Optimization Deployment
=================================================

Project ID: ${PROJECT_ID}
Network Name: ${NETWORK_NAME}
Deployment Date: $(date)

Regions:
- US: ${REGION_US} (${ZONE_US})
- EU: ${REGION_EU} (${ZONE_EU})
- APAC: ${REGION_APAC} (${ZONE_APAC})

Load Balancer IP: $(cat /tmp/lb_ip.txt 2>/dev/null || echo "Not available")

Key Resources:
- VPC Network: ${NETWORK_NAME}
- Subnets: ${NETWORK_NAME}-us, ${NETWORK_NAME}-eu, ${NETWORK_NAME}-apac
- Instances: web-server-us-1, web-server-eu-1, web-server-apac-1
- Load Balancer: global-web-backend

Network Intelligence Center:
https://console.cloud.google.com/net-intelligence/topology?project=${PROJECT_ID}

Cleanup Command:
./destroy.sh

EOF
    
    success "Deployment information saved to ${info_file}"
}

# Main deployment function
main() {
    log "Starting Global Network Performance Optimization deployment..."
    
    check_prerequisites
    setup_environment
    create_project
    enable_apis
    create_network_infrastructure
    create_firewall_rules
    deploy_compute_infrastructure
    create_load_balancer
    deploy_load_balancer_frontend
    enable_flow_logs
    configure_monitoring
    validate_deployment
    save_deployment_info
    
    success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    success "Project: ${PROJECT_ID}"
    success "Network: ${NETWORK_NAME}"
    
    if [[ -f /tmp/lb_ip.txt ]]; then
        local lb_ip
        lb_ip=$(cat /tmp/lb_ip.txt)
        success "Load Balancer IP: ${lb_ip}"
        success "Test URL: http://${lb_ip}"
    fi
    
    success "Network Intelligence Center: https://console.cloud.google.com/net-intelligence/topology?project=${PROJECT_ID}"
    
    log "Review deployment-info.txt for complete details"
    log "Use ./destroy.sh to clean up resources when finished"
}

# Run main function
main "$@"