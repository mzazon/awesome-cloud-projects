#!/bin/bash

# GCP Secure Multi-Cloud Connectivity Deployment Script
# Recipe: Secure Multi-Cloud Connectivity with Cloud NAT and Network Connectivity Center
# Provider: Google Cloud Platform
# Version: 1.0

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found"
        log "Please run: gcloud auth login"
        exit 1
    fi
}

# Function to check project billing
check_billing() {
    local project_id=$1
    if ! gcloud billing projects describe "$project_id" >/dev/null 2>&1; then
        log_warning "Unable to verify billing status for project: $project_id"
        log_warning "Please ensure billing is enabled for this project"
    fi
}

# Function to enable required APIs
enable_apis() {
    local project_id=$1
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "networkconnectivity.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling API: $api"
        if gcloud services enable "$api" --project="$project_id"; then
            log_success "Enabled $api"
        else
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    sleep 30
}

# Function to create VPC networks and subnets
create_vpc_networks() {
    log "Creating VPC networks and subnets..."
    
    # Create hub VPC network
    log "Creating hub VPC network: $VPC_HUB_NAME"
    gcloud compute networks create "$VPC_HUB_NAME" \
        --subnet-mode custom \
        --description "Hub VPC for Network Connectivity Center" \
        --project="$PROJECT_ID"
    
    # Create hub subnet
    gcloud compute networks subnets create hub-subnet \
        --network "$VPC_HUB_NAME" \
        --range 10.1.0.0/24 \
        --region "$REGION" \
        --project="$PROJECT_ID"
    
    # Create production VPC network
    log "Creating production VPC network: $VPC_PROD_NAME"
    gcloud compute networks create "$VPC_PROD_NAME" \
        --subnet-mode custom \
        --description "Production workloads VPC" \
        --project="$PROJECT_ID"
    
    # Create production subnet
    gcloud compute networks subnets create prod-subnet \
        --network "$VPC_PROD_NAME" \
        --range 192.168.1.0/24 \
        --region "$REGION" \
        --project="$PROJECT_ID"
    
    # Create development VPC network
    log "Creating development VPC network: $VPC_DEV_NAME"
    gcloud compute networks create "$VPC_DEV_NAME" \
        --subnet-mode custom \
        --description "Development workloads VPC" \
        --project="$PROJECT_ID"
    
    # Create development subnet
    gcloud compute networks subnets create dev-subnet \
        --network "$VPC_DEV_NAME" \
        --range 192.168.2.0/24 \
        --region "$REGION" \
        --project="$PROJECT_ID"
    
    # Create shared services VPC network
    log "Creating shared services VPC network: $VPC_SHARED_NAME"
    gcloud compute networks create "$VPC_SHARED_NAME" \
        --subnet-mode custom \
        --description "Shared services VPC" \
        --project="$PROJECT_ID"
    
    # Create shared services subnet
    gcloud compute networks subnets create shared-subnet \
        --network "$VPC_SHARED_NAME" \
        --range 192.168.3.0/24 \
        --region "$REGION" \
        --project="$PROJECT_ID"
    
    log_success "VPC networks and subnets created successfully"
}

# Function to create Network Connectivity Center hub
create_ncc_hub() {
    log "Creating Network Connectivity Center hub..."
    
    gcloud network-connectivity hubs create "$HUB_NAME" \
        --description "Multi-cloud connectivity hub for enterprise workloads" \
        --global \
        --project="$PROJECT_ID"
    
    # Wait for hub to be fully created
    sleep 10
    
    log_success "Network Connectivity Center hub created: $HUB_NAME"
}

# Function to create VPC spokes
create_vpc_spokes() {
    log "Creating VPC spokes for Network Connectivity Center..."
    
    # Create VPC spoke for production network
    gcloud network-connectivity spokes create prod-spoke \
        --hub "$HUB_NAME" \
        --description "Production VPC spoke" \
        --vpc-network "projects/$PROJECT_ID/global/networks/$VPC_PROD_NAME" \
        --global \
        --project="$PROJECT_ID"
    
    # Create VPC spoke for development network
    gcloud network-connectivity spokes create dev-spoke \
        --hub "$HUB_NAME" \
        --description "Development VPC spoke" \
        --vpc-network "projects/$PROJECT_ID/global/networks/$VPC_DEV_NAME" \
        --global \
        --project="$PROJECT_ID"
    
    # Create VPC spoke for shared services network
    gcloud network-connectivity spokes create shared-spoke \
        --hub "$HUB_NAME" \
        --description "Shared services VPC spoke" \
        --vpc-network "projects/$PROJECT_ID/global/networks/$VPC_SHARED_NAME" \
        --global \
        --project="$PROJECT_ID"
    
    log_success "VPC spokes created and attached to hub"
}

# Function to create Cloud Router
create_cloud_router() {
    log "Creating Cloud Router for BGP management..."
    
    gcloud compute routers create hub-router \
        --network "$VPC_HUB_NAME" \
        --region "$REGION" \
        --description "BGP router for hybrid connectivity" \
        --asn 64512 \
        --project="$PROJECT_ID"
    
    log_success "Cloud Router created with ASN 64512"
}

# Function to create VPN Gateway
create_vpn_gateway() {
    log "Creating Cloud VPN Gateway for hybrid connectivity..."
    
    gcloud compute vpn-gateways create hub-vpn-gateway \
        --network "$VPC_HUB_NAME" \
        --region "$REGION" \
        --description "HA VPN gateway for multi-cloud connectivity" \
        --project="$PROJECT_ID"
    
    # Get VPN gateway IPs for external configuration
    VPN_GW_IP1=$(gcloud compute vpn-gateways describe hub-vpn-gateway \
        --region "$REGION" \
        --project="$PROJECT_ID" \
        --format="value(vpnInterfaces[0].ipAddress)")
    VPN_GW_IP2=$(gcloud compute vpn-gateways describe hub-vpn-gateway \
        --region "$REGION" \
        --project="$PROJECT_ID" \
        --format="value(vpnInterfaces[1].ipAddress)")
    
    log_success "HA VPN Gateway created"
    log "VPN Gateway IP 1: $VPN_GW_IP1"
    log "VPN Gateway IP 2: $VPN_GW_IP2"
    log_warning "Configure these IPs in your external VPN gateways"
}

# Function to configure Cloud NAT
configure_cloud_nat() {
    log "Configuring Cloud NAT for secure outbound internet access..."
    
    # Create Cloud NAT gateway for hub VPC
    gcloud compute routers nats create hub-nat-gateway \
        --router hub-router \
        --region "$REGION" \
        --nat-all-subnet-ip-ranges \
        --auto-allocate-nat-external-ips \
        --enable-logging \
        --log-filter ALL \
        --project="$PROJECT_ID"
    
    # Configure NAT for production VPC
    gcloud compute routers create prod-router \
        --network "$VPC_PROD_NAME" \
        --region "$REGION" \
        --asn 64513 \
        --project="$PROJECT_ID"
    
    gcloud compute routers nats create prod-nat-gateway \
        --router prod-router \
        --region "$REGION" \
        --nat-all-subnet-ip-ranges \
        --auto-allocate-nat-external-ips \
        --enable-logging \
        --log-filter ALL \
        --project="$PROJECT_ID"
    
    # Configure NAT for development VPC
    gcloud compute routers create dev-router \
        --network "$VPC_DEV_NAME" \
        --region "$REGION" \
        --asn 64514 \
        --project="$PROJECT_ID"
    
    gcloud compute routers nats create dev-nat-gateway \
        --router dev-router \
        --region "$REGION" \
        --nat-all-subnet-ip-ranges \
        --auto-allocate-nat-external-ips \
        --enable-logging \
        --log-filter ALL \
        --project="$PROJECT_ID"
    
    # Configure NAT for shared services VPC
    gcloud compute routers create shared-router \
        --network "$VPC_SHARED_NAME" \
        --region "$REGION" \
        --asn 64515 \
        --project="$PROJECT_ID"
    
    gcloud compute routers nats create shared-nat-gateway \
        --router shared-router \
        --region "$REGION" \
        --nat-all-subnet-ip-ranges \
        --auto-allocate-nat-external-ips \
        --enable-logging \
        --log-filter ALL \
        --project="$PROJECT_ID"
    
    log_success "Cloud NAT gateways configured for all VPC networks"
}

# Function to create firewall rules
create_firewall_rules() {
    log "Creating firewall rules for inter-VPC communication..."
    
    # Create firewall rules for hub VPC (VPN and management traffic)
    gcloud compute firewall-rules create hub-allow-vpn \
        --network "$VPC_HUB_NAME" \
        --allow tcp:22,tcp:179,udp:500,udp:4500,esp \
        --source-ranges 10.0.0.0/8,172.16.0.0/12 \
        --description "Allow VPN and BGP traffic" \
        --project="$PROJECT_ID"
    
    # Create firewall rules for production VPC
    gcloud compute firewall-rules create prod-allow-internal \
        --network "$VPC_PROD_NAME" \
        --allow tcp:22,tcp:80,tcp:443,icmp \
        --source-ranges 192.168.0.0/16,10.1.0.0/24 \
        --description "Allow internal communication and management" \
        --project="$PROJECT_ID"
    
    # Create firewall rules for development VPC
    gcloud compute firewall-rules create dev-allow-internal \
        --network "$VPC_DEV_NAME" \
        --allow tcp:22,tcp:80,tcp:443,tcp:8080,icmp \
        --source-ranges 192.168.0.0/16,10.1.0.0/24 \
        --description "Allow internal communication and development traffic" \
        --project="$PROJECT_ID"
    
    # Create firewall rules for shared services VPC
    gcloud compute firewall-rules create shared-allow-internal \
        --network "$VPC_SHARED_NAME" \
        --allow tcp:22,tcp:53,tcp:80,tcp:443,udp:53,icmp \
        --source-ranges 192.168.0.0/16,10.1.0.0/24,10.0.0.0/16 \
        --description "Allow shared services access" \
        --project="$PROJECT_ID"
    
    # Create explicit egress rules for internet access
    gcloud compute firewall-rules create prod-allow-egress \
        --network "$VPC_PROD_NAME" \
        --direction EGRESS \
        --action ALLOW \
        --rules tcp:80,tcp:443,tcp:53,udp:53 \
        --destination-ranges 0.0.0.0/0 \
        --description "Allow outbound internet access for production" \
        --project="$PROJECT_ID"
    
    log_success "Firewall rules configured for secure communication"
}

# Function to configure hybrid spoke (example configuration)
configure_hybrid_spoke() {
    log "Configuring hybrid spoke for external cloud connectivity..."
    
    # Create external VPN gateway representation (for external cloud provider)
    gcloud compute external-vpn-gateways create external-cloud-gateway \
        --interfaces 0=172.16.1.1 \
        --description "External cloud provider VPN gateway" \
        --project="$PROJECT_ID"
    
    # Create VPN tunnel to external cloud provider
    gcloud compute vpn-tunnels create tunnel-to-external-cloud \
        --peer-external-gateway external-cloud-gateway \
        --peer-external-gateway-interface 0 \
        --vpn-gateway hub-vpn-gateway \
        --vpn-gateway-interface 0 \
        --ike-version 2 \
        --shared-secret "${SHARED_SECRET:-your-shared-secret-here}" \
        --router hub-router \
        --region "$REGION" \
        --description "VPN tunnel to external cloud provider" \
        --project="$PROJECT_ID"
    
    # Add BGP peer for external cloud provider
    gcloud compute routers add-bgp-peer hub-router \
        --peer-name external-cloud-peer \
        --interface tunnel-to-external-cloud \
        --peer-ip-address 169.254.1.2 \
        --peer-asn 65001 \
        --region "$REGION" \
        --project="$PROJECT_ID"
    
    # Create hybrid spoke for external connectivity
    gcloud network-connectivity spokes create external-cloud-spoke \
        --hub "$HUB_NAME" \
        --description "Hybrid spoke for external cloud connectivity" \
        --vpn-tunnel "projects/$PROJECT_ID/regions/$REGION/vpnTunnels/tunnel-to-external-cloud" \
        --global \
        --project="$PROJECT_ID"
    
    log_success "Hybrid spoke configured for external cloud connectivity"
    log_warning "Please configure the corresponding VPN gateway in your external cloud provider"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check hub status
    local hub_state
    hub_state=$(gcloud network-connectivity hubs describe "$HUB_NAME" \
        --global \
        --project="$PROJECT_ID" \
        --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    
    if [[ "$hub_state" == "ACTIVE" ]]; then
        log_success "Network Connectivity Center hub is ACTIVE"
    else
        log_warning "Hub state: $hub_state (may need time to become ACTIVE)"
    fi
    
    # Count spokes
    local spoke_count
    spoke_count=$(gcloud network-connectivity spokes list \
        --hub "$HUB_NAME" \
        --global \
        --project="$PROJECT_ID" \
        --format="value(name)" | wc -l)
    
    log_success "Found $spoke_count spokes attached to hub"
    
    # Check VPC networks
    local vpc_count
    vpc_count=$(gcloud compute networks list \
        --filter="name:($VPC_HUB_NAME OR $VPC_PROD_NAME OR $VPC_DEV_NAME OR $VPC_SHARED_NAME)" \
        --project="$PROJECT_ID" \
        --format="value(name)" | wc -l)
    
    if [[ "$vpc_count" -eq 4 ]]; then
        log_success "All 4 VPC networks created successfully"
    else
        log_warning "Expected 4 VPC networks, found $vpc_count"
    fi
}

# Function to display next steps
display_next_steps() {
    log_success "Deployment completed successfully!"
    echo
    log "Next Steps:"
    echo "1. Configure your external VPN gateways with the following IPs:"
    echo "   - VPN Gateway IP 1: $VPN_GW_IP1"
    echo "   - VPN Gateway IP 2: $VPN_GW_IP2"
    echo
    echo "2. Update the shared secret in the VPN tunnel configuration"
    echo "3. Configure BGP peering in your external cloud providers"
    echo "4. Test connectivity between VPC networks"
    echo "5. Deploy your workloads to the appropriate VPC networks"
    echo
    log "To clean up all resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting GCP Secure Multi-Cloud Connectivity deployment..."
    
    # Prerequisites check
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    check_gcloud_auth
    
    # Set environment variables with defaults
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export HUB_NAME="${HUB_NAME:-multi-cloud-hub}"
    
    # Validate required variables
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID is not set. Please set it or configure gcloud project."
        exit 1
    fi
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 6)
    export VPC_HUB_NAME="${VPC_HUB_NAME:-hub-vpc-${RANDOM_SUFFIX}}"
    export VPC_PROD_NAME="${VPC_PROD_NAME:-prod-vpc-${RANDOM_SUFFIX}}"
    export VPC_DEV_NAME="${VPC_DEV_NAME:-dev-vpc-${RANDOM_SUFFIX}}"
    export VPC_SHARED_NAME="${VPC_SHARED_NAME:-shared-vpc-${RANDOM_SUFFIX}}"
    
    # Display configuration
    log "Configuration:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Zone: $ZONE"
    echo "  Random Suffix: $RANDOM_SUFFIX"
    echo "  Hub Name: $HUB_NAME"
    echo
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    check_billing "$PROJECT_ID"
    
    # Execute deployment steps
    enable_apis "$PROJECT_ID"
    create_vpc_networks
    create_ncc_hub
    create_vpc_spokes
    create_cloud_router
    create_vpn_gateway
    configure_cloud_nat
    create_firewall_rules
    configure_hybrid_spoke
    
    # Wait for resources to stabilize
    log "Waiting for resources to stabilize..."
    sleep 30
    
    verify_deployment
    display_next_steps
}

# Trap errors and cleanup
trap 'log_error "Deployment failed. Check the logs above for details."' ERR

# Run main function
main "$@"