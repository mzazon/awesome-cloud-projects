#!/bin/bash

# Service Discovery with Traffic Director and Cloud DNS - Deployment Script
# This script deploys the complete intelligent service discovery infrastructure
# using Traffic Director as the control plane and Cloud DNS for service resolution

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud SDK (gcloud) is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
    fi
    
    # Check required APIs are enabled or can be enabled
    log "Checking required APIs..."
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set environment variables for the project
    export PROJECT_ID="${PROJECT_ID:-intelligent-discovery-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE_A="${ZONE_A:-us-central1-a}"
    export ZONE_B="${ZONE_B:-us-central1-b}"
    export ZONE_C="${ZONE_C:-us-central1-c}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export SERVICE_NAME="microservice-${RANDOM_SUFFIX}"
    export DNS_ZONE_NAME="discovery-zone-${RANDOM_SUFFIX}"
    export DOMAIN_NAME="${SERVICE_NAME}.example.com"
    
    log "Project ID: ${PROJECT_ID}"
    log "Service Name: ${SERVICE_NAME}"
    log "DNS Zone: ${DNS_ZONE_NAME}"
    log "Domain: ${DOMAIN_NAME}"
    
    success "Environment variables configured"
}

# Function to create and configure project
setup_project() {
    log "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log "Project ${PROJECT_ID} already exists, using existing project"
    else
        log "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" || error "Failed to create project"
    fi
    
    # Set as default project
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    # Enable required APIs
    log "Enabling required APIs..."
    gcloud services enable compute.googleapis.com \
        dns.googleapis.com \
        trafficdirector.googleapis.com \
        container.googleapis.com \
        servicenetworking.googleapis.com || error "Failed to enable APIs"
    
    success "Project setup completed"
}

# Function to create VPC network
create_vpc_network() {
    log "Creating VPC network for service mesh..."
    
    # Create VPC network
    if ! gcloud compute networks describe service-mesh-vpc &>/dev/null; then
        gcloud compute networks create service-mesh-vpc \
            --subnet-mode=custom \
            --bgp-routing-mode=global || error "Failed to create VPC network"
        log "VPC network created"
    else
        log "VPC network already exists"
    fi
    
    # Create subnet
    if ! gcloud compute networks subnets describe service-mesh-subnet --region="${REGION}" &>/dev/null; then
        gcloud compute networks subnets create service-mesh-subnet \
            --network=service-mesh-vpc \
            --range=10.0.0.0/24 \
            --region="${REGION}" || error "Failed to create subnet"
        log "Subnet created"
    else
        log "Subnet already exists"
    fi
    
    success "VPC network setup completed"
}

# Function to create DNS zones
create_dns_zones() {
    log "Creating Cloud DNS zones for service discovery..."
    
    # Create private DNS zone
    if ! gcloud dns managed-zones describe "${DNS_ZONE_NAME}" &>/dev/null; then
        gcloud dns managed-zones create "${DNS_ZONE_NAME}" \
            --description="Private DNS zone for microservice discovery" \
            --dns-name="${DOMAIN_NAME}." \
            --visibility=private \
            --networks=service-mesh-vpc || error "Failed to create private DNS zone"
        log "Private DNS zone created"
    else
        log "Private DNS zone already exists"
    fi
    
    # Create public DNS zone
    if ! gcloud dns managed-zones describe "${DNS_ZONE_NAME}-public" &>/dev/null; then
        gcloud dns managed-zones create "${DNS_ZONE_NAME}-public" \
            --description="Public DNS zone for external service access" \
            --dns-name="${DOMAIN_NAME}." || error "Failed to create public DNS zone"
        log "Public DNS zone created"
    else
        log "Public DNS zone already exists"
    fi
    
    success "DNS zones created"
}

# Function to deploy service instances
deploy_service_instances() {
    log "Deploying service instances across multiple zones..."
    
    # Create instance template
    if ! gcloud compute instance-templates describe "${SERVICE_NAME}-template" &>/dev/null; then
        gcloud compute instance-templates create "${SERVICE_NAME}-template" \
            --machine-type=e2-medium \
            --network-interface=subnet=service-mesh-subnet \
            --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx

# Configure nginx as a simple web service
cat > /var/www/html/index.html << EOF
{
  "service": "'${SERVICE_NAME}'",
  "zone": "'$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)'",
  "instance": "'$(hostname)'",
  "timestamp": "'$(date)'",
  "health": "healthy"
}
EOF

# Enable health check endpoint
cat > /var/www/html/health << EOF
{"status": "healthy", "timestamp": "$(date)"}
EOF

systemctl enable nginx
systemctl start nginx' \
            --tags=http-server,service-mesh \
            --image-family=debian-11 \
            --image-project=debian-cloud || error "Failed to create instance template"
        log "Instance template created"
    else
        log "Instance template already exists"
    fi
    
    # Deploy instances in each zone
    for zone in "${ZONE_A}" "${ZONE_B}" "${ZONE_C}"; do
        for instance_num in 1 2; do
            instance_name="${SERVICE_NAME}-${zone}-${instance_num}"
            if ! gcloud compute instances describe "${instance_name}" --zone="${zone}" &>/dev/null; then
                gcloud compute instances create "${instance_name}" \
                    --source-instance-template="${SERVICE_NAME}-template" \
                    --zone="${zone}" || error "Failed to create instance ${instance_name}"
                log "Created instance: ${instance_name}"
            else
                log "Instance ${instance_name} already exists"
            fi
        done
    done
    
    # Wait for instances to be ready
    log "Waiting for instances to be ready..."
    sleep 30
    
    success "Service instances deployed"
}

# Function to create Network Endpoint Groups
create_network_endpoint_groups() {
    log "Creating Network Endpoint Groups for Traffic Director..."
    
    for zone in "${ZONE_A}" "${ZONE_B}" "${ZONE_C}"; do
        neg_name="${SERVICE_NAME}-neg-${zone}"
        
        # Create NEG
        if ! gcloud compute network-endpoint-groups describe "${neg_name}" --zone="${zone}" &>/dev/null; then
            gcloud compute network-endpoint-groups create "${neg_name}" \
                --network-endpoint-type=GCE_VM_IP_PORT \
                --zone="${zone}" \
                --network=service-mesh-vpc \
                --subnet=service-mesh-subnet || error "Failed to create NEG ${neg_name}"
            log "Created NEG: ${neg_name}"
        else
            log "NEG ${neg_name} already exists"
        fi
        
        # Add instance endpoints to NEGs
        for instance_num in 1 2; do
            instance_name="${SERVICE_NAME}-${zone}-${instance_num}"
            
            # Check if endpoint already exists
            if ! gcloud compute network-endpoint-groups list-network-endpoints "${neg_name}" \
                --zone="${zone}" --format="value(instance)" | grep -q "${instance_name}"; then
                
                gcloud compute network-endpoint-groups update "${neg_name}" \
                    --zone="${zone}" \
                    --add-endpoint=instance="${instance_name}",port=80 || warning "Failed to add endpoint ${instance_name} to NEG"
                log "Added endpoint: ${instance_name} to ${neg_name}"
            else
                log "Endpoint ${instance_name} already exists in ${neg_name}"
            fi
        done
    done
    
    success "Network Endpoint Groups created and populated"
}

# Function to create health check
create_health_check() {
    log "Creating health check for service monitoring..."
    
    # Create HTTP health check
    if ! gcloud compute health-checks describe "${SERVICE_NAME}-health-check" &>/dev/null; then
        gcloud compute health-checks create http "${SERVICE_NAME}-health-check" \
            --port=80 \
            --request-path="/health" \
            --check-interval=10s \
            --timeout=5s \
            --healthy-threshold=2 \
            --unhealthy-threshold=3 \
            --description="Health check for ${SERVICE_NAME} instances" || error "Failed to create health check"
        log "Health check created"
    else
        log "Health check already exists"
    fi
    
    # Create firewall rule for health checks
    if ! gcloud compute firewall-rules describe "allow-health-check-${RANDOM_SUFFIX}" &>/dev/null; then
        gcloud compute firewall-rules create "allow-health-check-${RANDOM_SUFFIX}" \
            --network=service-mesh-vpc \
            --source-ranges=130.211.0.0/22,35.191.0.0/16 \
            --target-tags=service-mesh \
            --allow=tcp:80 \
            --description="Allow Google Cloud health check traffic" || error "Failed to create firewall rule"
        log "Health check firewall rule created"
    else
        log "Health check firewall rule already exists"
    fi
    
    success "Health check configured"
}

# Function to configure Traffic Director backend service
configure_backend_service() {
    log "Configuring Traffic Director backend service..."
    
    # Create backend service
    if ! gcloud compute backend-services describe "${SERVICE_NAME}-backend" --global &>/dev/null; then
        gcloud compute backend-services create "${SERVICE_NAME}-backend" \
            --global \
            --load-balancing-scheme=INTERNAL_SELF_MANAGED \
            --protocol=HTTP \
            --health-checks="${SERVICE_NAME}-health-check" \
            --connection-draining-timeout=60s \
            --description="Backend service for intelligent service discovery" || error "Failed to create backend service"
        log "Backend service created"
    else
        log "Backend service already exists"
    fi
    
    # Add NEGs as backends
    for zone in "${ZONE_A}" "${ZONE_B}" "${ZONE_C}"; do
        neg_name="${SERVICE_NAME}-neg-${zone}"
        
        # Check if backend already exists
        if ! gcloud compute backend-services describe "${SERVICE_NAME}-backend" --global \
            --format="value(backends[].group)" | grep -q "${neg_name}"; then
            
            gcloud compute backend-services add-backend "${SERVICE_NAME}-backend" \
                --global \
                --network-endpoint-group="${neg_name}" \
                --network-endpoint-group-zone="${zone}" \
                --balancing-mode=RATE \
                --max-rate-per-endpoint=100 || warning "Failed to add backend ${neg_name}"
            log "Added backend: ${neg_name}"
        else
            log "Backend ${neg_name} already exists"
        fi
    done
    
    success "Backend service configured"
}

# Function to create URL map and HTTP proxy
create_url_map_and_proxy() {
    log "Creating URL map and HTTP proxy for traffic routing..."
    
    # Create URL map
    if ! gcloud compute url-maps describe "${SERVICE_NAME}-url-map" &>/dev/null; then
        gcloud compute url-maps create "${SERVICE_NAME}-url-map" \
            --default-service="${SERVICE_NAME}-backend" \
            --description="URL map for intelligent service discovery routing" || error "Failed to create URL map"
        log "URL map created"
    else
        log "URL map already exists"
    fi
    
    # Add path-based routing rules
    if ! gcloud compute url-maps describe "${SERVICE_NAME}-url-map" \
        --format="value(hostRules[].hosts[])" | grep -q "${DOMAIN_NAME}"; then
        
        gcloud compute url-maps add-path-matcher "${SERVICE_NAME}-url-map" \
            --path-matcher-name=service-matcher \
            --default-service="${SERVICE_NAME}-backend" \
            --new-hosts="${DOMAIN_NAME}" || warning "Failed to add path matcher"
        log "Path matcher added to URL map"
    else
        log "Path matcher already exists"
    fi
    
    # Create target HTTP proxy
    if ! gcloud compute target-http-proxies describe "${SERVICE_NAME}-proxy" &>/dev/null; then
        gcloud compute target-http-proxies create "${SERVICE_NAME}-proxy" \
            --url-map="${SERVICE_NAME}-url-map" \
            --description="HTTP proxy for Traffic Director service mesh" || error "Failed to create HTTP proxy"
        log "HTTP proxy created"
    else
        log "HTTP proxy already exists"
    fi
    
    success "URL map and HTTP proxy configured"
}

# Function to configure global forwarding rule
configure_forwarding_rule() {
    log "Configuring global forwarding rule for service access..."
    
    # Create global forwarding rule
    if ! gcloud compute forwarding-rules describe "${SERVICE_NAME}-forwarding-rule" --global &>/dev/null; then
        gcloud compute forwarding-rules create "${SERVICE_NAME}-forwarding-rule" \
            --global \
            --load-balancing-scheme=INTERNAL_SELF_MANAGED \
            --address=10.0.1.100 \
            --ports=80 \
            --target-http-proxy="${SERVICE_NAME}-proxy" \
            --network=service-mesh-vpc \
            --subnet=service-mesh-subnet || error "Failed to create forwarding rule"
        log "Forwarding rule created"
    else
        log "Forwarding rule already exists"
    fi
    
    # Get the assigned VIP
    SERVICE_VIP=$(gcloud compute forwarding-rules describe "${SERVICE_NAME}-forwarding-rule" \
        --global \
        --format="value(IPAddress)")
    
    export SERVICE_VIP
    log "Service VIP: ${SERVICE_VIP}"
    
    success "Global forwarding rule configured"
}

# Function to update DNS records
update_dns_records() {
    log "Updating DNS records for service discovery..."
    
    # Get the Service VIP
    SERVICE_VIP=$(gcloud compute forwarding-rules describe "${SERVICE_NAME}-forwarding-rule" \
        --global \
        --format="value(IPAddress)")
    
    if [[ -z "${SERVICE_VIP}" ]]; then
        error "Failed to get Service VIP"
    fi
    
    # Create DNS A record
    if ! gcloud dns record-sets describe "${DOMAIN_NAME}." --zone="${DNS_ZONE_NAME}" --type=A &>/dev/null; then
        gcloud dns record-sets create "${DOMAIN_NAME}." \
            --zone="${DNS_ZONE_NAME}" \
            --type=A \
            --ttl=300 \
            --rrdatas="${SERVICE_VIP}" || error "Failed to create A record"
        log "A record created"
    else
        log "A record already exists"
    fi
    
    # Create SRV record
    if ! gcloud dns record-sets describe "_http._tcp.${DOMAIN_NAME}." --zone="${DNS_ZONE_NAME}" --type=SRV &>/dev/null; then
        gcloud dns record-sets create "_http._tcp.${DOMAIN_NAME}." \
            --zone="${DNS_ZONE_NAME}" \
            --type=SRV \
            --ttl=300 \
            --rrdatas="10 5 80 ${DOMAIN_NAME}." || error "Failed to create SRV record"
        log "SRV record created"
    else
        log "SRV record already exists"
    fi
    
    # Create health check record
    if ! gcloud dns record-sets describe "health.${DOMAIN_NAME}." --zone="${DNS_ZONE_NAME}" --type=A &>/dev/null; then
        gcloud dns record-sets create "health.${DOMAIN_NAME}." \
            --zone="${DNS_ZONE_NAME}" \
            --type=A \
            --ttl=60 \
            --rrdatas="${SERVICE_VIP}" || error "Failed to create health record"
        log "Health record created"
    else
        log "Health record already exists"
    fi
    
    success "DNS records configured"
}

# Function to create test client
create_test_client() {
    log "Creating test client for validation..."
    
    TEST_INSTANCE="test-client-${RANDOM_SUFFIX}"
    
    if ! gcloud compute instances describe "${TEST_INSTANCE}" --zone="${ZONE_A}" &>/dev/null; then
        gcloud compute instances create "${TEST_INSTANCE}" \
            --zone="${ZONE_A}" \
            --machine-type=e2-micro \
            --subnet=service-mesh-subnet \
            --image-family=debian-11 \
            --image-project=debian-cloud \
            --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y curl jq dnsutils' || error "Failed to create test client"
        log "Test client created"
    else
        log "Test client already exists"
    fi
    
    # Wait for test client to be ready
    log "Waiting for test client to be ready..."
    sleep 30
    
    export TEST_INSTANCE
    success "Test client ready"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check backend service health
    log "Checking backend service health..."
    gcloud compute backend-services get-health "${SERVICE_NAME}-backend" --global || warning "Health check failed"
    
    # Check NEG endpoints
    for zone in "${ZONE_A}" "${ZONE_B}" "${ZONE_C}"; do
        log "Checking NEG endpoints in zone: ${zone}"
        gcloud compute network-endpoint-groups list-network-endpoints \
            "${SERVICE_NAME}-neg-${zone}" \
            --zone="${zone}" || warning "Failed to list NEG endpoints"
    done
    
    success "Deployment validation completed"
}

# Function to display deployment information
display_deployment_info() {
    log "Deployment Summary:"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Service Name: ${SERVICE_NAME}"
    echo "Domain Name: ${DOMAIN_NAME}"
    echo "DNS Zone: ${DNS_ZONE_NAME}"
    
    # Get Service VIP
    SERVICE_VIP=$(gcloud compute forwarding-rules describe "${SERVICE_NAME}-forwarding-rule" \
        --global \
        --format="value(IPAddress)" 2>/dev/null || echo "N/A")
    echo "Service VIP: ${SERVICE_VIP}"
    
    echo ""
    echo "Test Commands:"
    echo "=============="
    echo "# Test DNS resolution:"
    echo "gcloud compute ssh ${TEST_INSTANCE} --zone=${ZONE_A} --command=\"nslookup ${DOMAIN_NAME}\""
    echo ""
    echo "# Test load balancing:"
    echo "for i in {1..5}; do gcloud compute ssh ${TEST_INSTANCE} --zone=${ZONE_A} --command=\"curl -s http://${DOMAIN_NAME}/ | jq -r '.zone + \\\" - \\\" + .instance'\"; done"
    echo ""
    echo "# Check health status:"
    echo "gcloud compute backend-services get-health ${SERVICE_NAME}-backend --global"
    echo ""
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting Service Discovery with Traffic Director and Cloud DNS deployment..."
    
    check_prerequisites
    setup_environment
    setup_project
    create_vpc_network
    create_dns_zones
    deploy_service_instances
    create_network_endpoint_groups
    create_health_check
    configure_backend_service
    create_url_map_and_proxy
    configure_forwarding_rule
    update_dns_records
    create_test_client
    validate_deployment
    display_deployment_info
}

# Run main function
main "$@"