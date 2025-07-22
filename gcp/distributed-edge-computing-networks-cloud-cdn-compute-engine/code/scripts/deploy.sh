#!/bin/bash

# Distributed Edge Computing Networks Deployment Script
# Deploys global edge computing infrastructure with Cloud CDN and Compute Engine
# Author: Generated from recipe distributed-edge-computing-networks-cloud-cdn-compute-engine
# Version: 1.0

set -euo pipefail

# Color codes for output
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

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
handle_error() {
    log_error "Deployment failed at line $1"
    log_error "Command that failed: $BASH_COMMAND"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Configuration variables
DEFAULT_PROJECT_ID="edge-network-$(date +%s)"
DEFAULT_DOMAIN="edge-example.com"
REGIONS=("us-central1" "europe-west1" "asia-southeast1")
ZONES=("us-central1-a" "europe-west1-b" "asia-southeast1-a")

# Script banner
echo -e "${BLUE}"
echo "================================================================"
echo "     Distributed Edge Computing Networks Deployment"
echo "================================================================"
echo -e "${NC}"

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud CLI first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Please authenticate with Google Cloud: gcloud auth login"
        exit 1
    fi
    
    # Check if required APIs can be enabled (requires project)
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_warning "PROJECT_ID not set. Using default: ${DEFAULT_PROJECT_ID}"
    fi
    
    log_success "Prerequisites check completed"
}

# Prompt for configuration
get_configuration() {
    log_info "Gathering deployment configuration..."
    
    # Project ID
    read -p "Enter Google Cloud Project ID [${DEFAULT_PROJECT_ID}]: " input_project
    export PROJECT_ID="${input_project:-$DEFAULT_PROJECT_ID}"
    
    # Domain name
    read -p "Enter domain name for DNS configuration [${DEFAULT_DOMAIN}]: " input_domain
    export DOMAIN_NAME="${input_domain:-$DEFAULT_DOMAIN}"
    
    # Generate unique suffix
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export NETWORK_NAME="edge-network-${RANDOM_SUFFIX}"
    export BACKEND_SERVICE_NAME="edge-backend-${RANDOM_SUFFIX}"
    
    log_info "Configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Domain Name: ${DOMAIN_NAME}"
    log_info "  Network Name: ${NETWORK_NAME}"
    log_info "  Backend Service: ${BACKEND_SERVICE_NAME}"
    log_info "  Random Suffix: ${RANDOM_SUFFIX}"
    
    # Confirmation
    read -p "Proceed with deployment? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

# Setup project and enable APIs
setup_project() {
    log_info "Setting up project and enabling APIs..."
    
    # Set default project
    gcloud config set project "${PROJECT_ID}" || {
        log_error "Failed to set project. Please ensure project exists and you have access."
        exit 1
    }
    
    # Set default region and zone
    gcloud config set compute/region "${REGIONS[0]}"
    gcloud config set compute/zone "${ZONES[0]}"
    
    # Enable required APIs
    log_info "Enabling required Google Cloud APIs..."
    gcloud services enable \
        compute.googleapis.com \
        dns.googleapis.com \
        storage.googleapis.com \
        logging.googleapis.com \
        monitoring.googleapis.com \
        --quiet
    
    log_success "Project setup completed"
}

# Create global VPC network
create_network() {
    log_info "Creating global VPC network and subnets..."
    
    # Create global VPC network
    log_info "Creating VPC network: ${NETWORK_NAME}"
    gcloud compute networks create "${NETWORK_NAME}" \
        --subnet-mode=custom \
        --bgp-routing-mode=global \
        --quiet
    
    # Create regional subnets
    for i in "${!REGIONS[@]}"; do
        REGION=${REGIONS[$i]}
        SUBNET_RANGE="10.$((i+1)).0.0/16"
        
        log_info "Creating subnet in ${REGION} with range ${SUBNET_RANGE}"
        gcloud compute networks subnets create "${NETWORK_NAME}-${REGION}" \
            --network="${NETWORK_NAME}" \
            --region="${REGION}" \
            --range="${SUBNET_RANGE}" \
            --enable-private-ip-google-access \
            --quiet
    done
    
    log_success "VPC network and subnets created"
}

# Configure firewall rules
create_firewall_rules() {
    log_info "Configuring firewall rules..."
    
    # Allow HTTP/HTTPS traffic
    gcloud compute firewall-rules create "${NETWORK_NAME}-allow-web" \
        --network="${NETWORK_NAME}" \
        --allow=tcp:80,tcp:443,tcp:8080 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=edge-server \
        --quiet
    
    # Allow health check traffic
    gcloud compute firewall-rules create "${NETWORK_NAME}-allow-health-check" \
        --network="${NETWORK_NAME}" \
        --allow=tcp:80,tcp:443,tcp:8080 \
        --source-ranges=130.211.0.0/22,35.191.0.0/16 \
        --target-tags=edge-server \
        --quiet
    
    # Allow internal communication
    gcloud compute firewall-rules create "${NETWORK_NAME}-allow-internal" \
        --network="${NETWORK_NAME}" \
        --allow=tcp:1-65535,udp:1-65535,icmp \
        --source-ranges=10.0.0.0/8 \
        --target-tags=edge-server \
        --quiet
    
    log_success "Firewall rules configured"
}

# Deploy compute engine clusters
deploy_compute_clusters() {
    log_info "Deploying regional Compute Engine clusters..."
    
    for i in "${!REGIONS[@]}"; do
        REGION=${REGIONS[$i]}
        ZONE=${ZONES[$i]}
        
        log_info "Deploying cluster in ${REGION}..."
        
        # Create instance template
        gcloud compute instance-templates create "edge-template-${REGION}-${RANDOM_SUFFIX}" \
            --machine-type=e2-standard-2 \
            --network-interface="network=${NETWORK_NAME},subnet=${NETWORK_NAME}-${REGION},no-address" \
            --image-family=ubuntu-2404-lts \
            --image-project=ubuntu-os-cloud \
            --tags=edge-server \
            --scopes=https://www.googleapis.com/auth/cloud-platform \
            --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx

# Configure nginx for edge processing
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head><title>Edge Node - $(hostname)</title></head>
<body>
    <h1>Edge Computing Node</h1>
    <p>Server: $(hostname)</p>
    <p>Region: $(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor: Google" | cut -d/ -f4)</p>
    <p>Timestamp: $(date)</p>
    <p>Processing dynamic content at the edge</p>
</body>
</html>
EOF

systemctl start nginx
systemctl enable nginx' \
            --quiet
        
        # Create managed instance group
        gcloud compute instance-groups managed create "edge-group-${REGION}" \
            --template="edge-template-${REGION}-${RANDOM_SUFFIX}" \
            --size=2 \
            --zone="${ZONE}" \
            --quiet
        
        # Configure autoscaling
        gcloud compute instance-groups managed set-autoscaling "edge-group-${REGION}" \
            --zone="${ZONE}" \
            --max-num-replicas=5 \
            --min-num-replicas=2 \
            --target-cpu-utilization=0.7 \
            --quiet
        
        log_info "Waiting for instances to become available in ${REGION}..."
        sleep 30
    done
    
    log_success "Compute clusters deployed in all regions"
}

# Create storage origins
create_storage_origins() {
    log_info "Creating Cloud Storage origins..."
    
    for i in "${!REGIONS[@]}"; do
        REGION=${REGIONS[$i]}
        BUCKET_NAME="edge-origin-${REGION}-${RANDOM_SUFFIX}"
        
        log_info "Creating bucket: ${BUCKET_NAME}"
        
        # Create bucket
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}"
        
        # Enable uniform bucket-level access
        gsutil uniformbucketlevelaccess set on "gs://${BUCKET_NAME}"
        
        # Upload sample content
        echo "<h1>Static Content from ${REGION}</h1><p>Served via Cloud CDN</p>" | \
            gsutil cp - "gs://${BUCKET_NAME}/index.html"
        
        # Make bucket publicly readable
        gsutil iam ch allUsers:objectViewer "gs://${BUCKET_NAME}"
    done
    
    log_success "Storage origins created"
}

# Configure load balancer
create_load_balancer() {
    log_info "Creating global load balancer..."
    
    # Create health check
    gcloud compute health-checks create http edge-health-check \
        --port=80 \
        --request-path="/" \
        --check-interval=10s \
        --timeout=5s \
        --healthy-threshold=2 \
        --unhealthy-threshold=3 \
        --quiet
    
    # Create backend service with CDN
    gcloud compute backend-services create "${BACKEND_SERVICE_NAME}" \
        --protocol=HTTP \
        --health-checks=edge-health-check \
        --global \
        --load-balancing-scheme=EXTERNAL_MANAGED \
        --enable-cdn \
        --quiet
    
    # Add regional backends
    for i in "${!REGIONS[@]}"; do
        REGION=${REGIONS[$i]}
        ZONE=${ZONES[$i]}
        
        log_info "Adding ${REGION} backend to load balancer..."
        gcloud compute backend-services add-backend "${BACKEND_SERVICE_NAME}" \
            --instance-group="edge-group-${REGION}" \
            --instance-group-zone="${ZONE}" \
            --balancing-mode=UTILIZATION \
            --max-utilization=0.8 \
            --capacity-scaler=1.0 \
            --global \
            --quiet
    done
    
    log_success "Load balancer configured"
}

# Enable CDN and create routing
configure_cdn_routing() {
    log_info "Configuring Cloud CDN and routing..."
    
    # Update CDN settings
    gcloud compute backend-services update "${BACKEND_SERVICE_NAME}" \
        --enable-cdn \
        --cache-mode=CACHE_ALL_STATIC \
        --default-ttl=3600 \
        --max-ttl=86400 \
        --client-ttl=1800 \
        --negative-caching \
        --negative-caching-policy=404=60,500=10 \
        --global \
        --quiet
    
    # Create URL map
    gcloud compute url-maps create edge-url-map \
        --default-service="${BACKEND_SERVICE_NAME}" \
        --global \
        --quiet
    
    # Create HTTP proxy
    gcloud compute target-http-proxies create edge-http-proxy \
        --url-map=edge-url-map \
        --global \
        --quiet
    
    # Reserve global IP
    gcloud compute addresses create edge-global-ip \
        --global \
        --quiet
    
    # Get the IP address
    GLOBAL_IP=$(gcloud compute addresses describe edge-global-ip \
        --global --format="value(address)")
    export GLOBAL_IP
    
    # Create forwarding rule
    gcloud compute forwarding-rules create edge-forwarding-rule \
        --address=edge-global-ip \
        --global \
        --target-http-proxy=edge-http-proxy \
        --ports=80 \
        --quiet
    
    log_success "CDN and routing configured with IP: ${GLOBAL_IP}"
}

# Configure DNS
configure_dns() {
    log_info "Configuring Cloud DNS..."
    
    # Create DNS zone
    gcloud dns managed-zones create edge-zone \
        --description="Edge computing network DNS zone" \
        --dns-name="${DOMAIN_NAME}." \
        --visibility=public \
        --quiet
    
    # Create A record
    gcloud dns record-sets create "${DOMAIN_NAME}." \
        --zone=edge-zone \
        --type=A \
        --ttl=300 \
        --data="${GLOBAL_IP}" \
        --quiet
    
    # Create www subdomain
    gcloud dns record-sets create "www.${DOMAIN_NAME}." \
        --zone=edge-zone \
        --type=CNAME \
        --ttl=300 \
        --data="${DOMAIN_NAME}." \
        --quiet
    
    # Get nameservers
    NAME_SERVERS=$(gcloud dns managed-zones describe edge-zone \
        --format="value(nameServers[].join(' '))")
    
    log_success "DNS configured for ${DOMAIN_NAME}"
    log_info "Configure your domain registrar with these nameservers:"
    echo "${NAME_SERVERS}"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check network
    log_info "Checking VPC network..."
    if gcloud compute networks describe "${NETWORK_NAME}" --quiet > /dev/null 2>&1; then
        log_success "VPC network is operational"
    else
        log_error "VPC network validation failed"
        return 1
    fi
    
    # Check instance groups
    log_info "Checking instance groups..."
    for i in "${!REGIONS[@]}"; do
        REGION=${REGIONS[$i]}
        ZONE=${ZONES[$i]}
        
        INSTANCE_COUNT=$(gcloud compute instance-groups managed list-instances \
            "edge-group-${REGION}" --zone="${ZONE}" --format="value(name)" | wc -l)
        
        if [[ ${INSTANCE_COUNT} -ge 2 ]]; then
            log_success "Instance group in ${REGION}: ${INSTANCE_COUNT} instances"
        else
            log_warning "Instance group in ${REGION}: only ${INSTANCE_COUNT} instances"
        fi
    done
    
    # Check load balancer
    log_info "Checking load balancer health..."
    sleep 60  # Wait for health checks to stabilize
    
    HEALTHY_BACKENDS=$(gcloud compute backend-services get-health "${BACKEND_SERVICE_NAME}" \
        --global --format="value(status.healthStatus[].healthState)" | grep -c "HEALTHY" || echo "0")
    
    if [[ ${HEALTHY_BACKENDS} -gt 0 ]]; then
        log_success "Load balancer has ${HEALTHY_BACKENDS} healthy backends"
    else
        log_warning "No healthy backends detected yet. This may be normal for new deployments."
    fi
    
    # Test global IP
    log_info "Testing global IP response..."
    if curl -s -f -m 10 "http://${GLOBAL_IP}/" > /dev/null; then
        log_success "Global IP ${GLOBAL_IP} is responding"
    else
        log_warning "Global IP may not be ready yet. This is normal for new deployments."
    fi
    
    log_success "Deployment validation completed"
}

# Deployment summary
deployment_summary() {
    echo -e "${GREEN}"
    echo "================================================================"
    echo "              DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "================================================================"
    echo -e "${NC}"
    echo "Infrastructure Details:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Global IP: ${GLOBAL_IP}"
    echo "  Domain: ${DOMAIN_NAME}"
    echo "  Network: ${NETWORK_NAME}"
    echo ""
    echo "Regional Clusters:"
    for region in "${REGIONS[@]}"; do
        echo "  - ${region}"
    done
    echo ""
    echo "Next Steps:"
    echo "1. Configure your domain registrar with the provided nameservers"
    echo "2. Wait 10-15 minutes for DNS propagation"
    echo "3. Test your edge computing network at http://${DOMAIN_NAME}"
    echo "4. Monitor performance in Google Cloud Console"
    echo ""
    echo "Cleanup:"
    echo "Run ./destroy.sh to remove all resources when no longer needed"
}

# Main deployment flow
main() {
    log_info "Starting distributed edge computing networks deployment..."
    
    check_prerequisites
    get_configuration
    setup_project
    create_network
    create_firewall_rules
    deploy_compute_clusters
    create_storage_origins
    create_load_balancer
    configure_cdn_routing
    configure_dns
    validate_deployment
    deployment_summary
    
    log_success "Deployment script completed successfully!"
}

# Run main function
main "$@"