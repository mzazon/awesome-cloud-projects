#!/bin/bash

# Multi-Regional API Gateways with Apigee and Cloud Armor - Deployment Script
# This script deploys a comprehensive multi-regional API security architecture
# using Apigee X, Cloud Armor, and Cloud Load Balancing

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "No active Google Cloud authentication found. Please run 'gcloud auth login'"
    fi
    
    # Check if project is set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [[ -z "$PROJECT_ID" ]]; then
            error "No project ID found. Please set PROJECT_ID environment variable or run 'gcloud config set project PROJECT_ID'"
        fi
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is required for generating random suffixes. Please install it."
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project)}
    export REGION_US=${REGION_US:-"us-central1"}
    export REGION_EU=${REGION_EU:-"europe-west1"}
    export NETWORK_NAME=${NETWORK_NAME:-"apigee-network"}
    export SUBNET_US=${SUBNET_US:-"apigee-subnet-us"}
    export SUBNET_EU=${SUBNET_EU:-"apigee-subnet-eu"}
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=${RANDOM_SUFFIX:-$(openssl rand -hex 3)}
    export APIGEE_ORG_NAME=${APIGEE_ORG_NAME:-"${PROJECT_ID}"}
    export ARMOR_POLICY_NAME=${ARMOR_POLICY_NAME:-"api-security-policy-${RANDOM_SUFFIX}"}
    export LB_NAME=${LB_NAME:-"global-api-lb-${RANDOM_SUFFIX}"}
    export DOMAIN_NAME=${DOMAIN_NAME:-"api-${RANDOM_SUFFIX}.example.com"}
    
    # Save configuration for cleanup script
    cat > .deploy_config << EOF
PROJECT_ID=${PROJECT_ID}
REGION_US=${REGION_US}
REGION_EU=${REGION_EU}
NETWORK_NAME=${NETWORK_NAME}
SUBNET_US=${SUBNET_US}
SUBNET_EU=${SUBNET_EU}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
APIGEE_ORG_NAME=${APIGEE_ORG_NAME}
ARMOR_POLICY_NAME=${ARMOR_POLICY_NAME}
LB_NAME=${LB_NAME}
DOMAIN_NAME=${DOMAIN_NAME}
EOF
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION_US}"
    
    success "Environment variables configured"
    log "Project ID: ${PROJECT_ID}"
    log "Random Suffix: ${RANDOM_SUFFIX}"
    log "Domain Name: ${DOMAIN_NAME}"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "apigee.googleapis.com"
        "compute.googleapis.com"
        "servicenetworking.googleapis.com"
        "dns.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        if gcloud services enable "$api" --quiet; then
            success "Enabled ${api}"
        else
            error "Failed to enable ${api}"
        fi
    done
    
    success "All required APIs enabled"
}

# Create VPC network and subnets
create_network() {
    log "Creating global VPC network with regional subnets..."
    
    # Create global VPC network
    log "Creating global VPC network: ${NETWORK_NAME}"
    if gcloud compute networks create "${NETWORK_NAME}" \
        --subnet-mode=custom \
        --bgp-routing-mode=global \
        --quiet; then
        success "Global VPC network created"
    else
        error "Failed to create global VPC network"
    fi
    
    # Create subnet in US region
    log "Creating US subnet: ${SUBNET_US}"
    if gcloud compute networks subnets create "${SUBNET_US}" \
        --network="${NETWORK_NAME}" \
        --range=10.1.0.0/16 \
        --region="${REGION_US}" \
        --quiet; then
        success "US subnet created"
    else
        error "Failed to create US subnet"
    fi
    
    # Create subnet in EU region
    log "Creating EU subnet: ${SUBNET_EU}"
    if gcloud compute networks subnets create "${SUBNET_EU}" \
        --network="${NETWORK_NAME}" \
        --range=10.2.0.0/16 \
        --region="${REGION_EU}" \
        --quiet; then
        success "EU subnet created"
    else
        error "Failed to create EU subnet"
    fi
    
    success "Global VPC network and regional subnets created"
}

# Provision Apigee X organization
provision_apigee() {
    log "Provisioning Apigee X organization..."
    warning "This process typically takes 30-45 minutes to complete"
    
    # Check if organization already exists
    if gcloud apigee organizations describe "${PROJECT_ID}" &>/dev/null; then
        warning "Apigee organization already exists, skipping provisioning"
        return 0
    fi
    
    # Create Apigee organization
    log "Starting Apigee organization provisioning..."
    if gcloud apigee organizations provision \
        --runtime-type=CLOUD \
        --billing-type=PAYG \
        --network="${NETWORK_NAME}" \
        --authorized-network="${PROJECT_ID}" \
        --quiet; then
        
        log "Waiting for Apigee organization provisioning to complete..."
        local max_attempts=90  # 45 minutes with 30-second intervals
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            local state=$(gcloud apigee organizations describe "${PROJECT_ID}" \
                --format="value(state)" 2>/dev/null || echo "UNKNOWN")
            
            if [[ "$state" == "ACTIVE" ]]; then
                success "Apigee X organization provisioned successfully"
                return 0
            elif [[ "$state" == "PROVISIONING" ]]; then
                log "Provisioning in progress... (attempt $((attempt + 1))/$max_attempts)"
                sleep 30
                ((attempt++))
            else
                error "Apigee organization provisioning failed with state: $state"
            fi
        done
        
        error "Apigee organization provisioning timed out after 45 minutes"
    else
        error "Failed to start Apigee organization provisioning"
    fi
}

# Create Cloud Armor security policy
create_cloud_armor() {
    log "Creating Cloud Armor security policy..."
    
    # Create Cloud Armor security policy
    log "Creating security policy: ${ARMOR_POLICY_NAME}"
    if gcloud compute security-policies create "${ARMOR_POLICY_NAME}" \
        --description="Multi-regional API security policy" \
        --type=CLOUD_ARMOR \
        --quiet; then
        success "Cloud Armor security policy created"
    else
        error "Failed to create Cloud Armor security policy"
    fi
    
    # Add geographic blocking rule
    log "Adding geographic blocking rule..."
    if gcloud compute security-policies rules create 1000 \
        --security-policy="${ARMOR_POLICY_NAME}" \
        --expression="origin.region_code == 'CN' || origin.region_code == 'RU'" \
        --action=deny-403 \
        --description="Block traffic from high-risk regions" \
        --quiet; then
        success "Geographic blocking rule added"
    else
        warning "Failed to add geographic blocking rule"
    fi
    
    # Add rate limiting rule
    log "Adding rate limiting rule..."
    if gcloud compute security-policies rules create 2000 \
        --security-policy="${ARMOR_POLICY_NAME}" \
        --expression="true" \
        --action=rate-based-ban \
        --rate-limit-threshold-count=100 \
        --rate-limit-threshold-interval-sec=60 \
        --ban-duration-sec=600 \
        --description="Rate limiting for DDoS protection" \
        --quiet; then
        success "Rate limiting rule added"
    else
        warning "Failed to add rate limiting rule"
    fi
    
    # Add SQL injection protection
    log "Adding SQL injection protection rule..."
    if gcloud compute security-policies rules create 3000 \
        --security-policy="${ARMOR_POLICY_NAME}" \
        --expression="evaluatePreconfiguredExpr('sqli-stable')" \
        --action=deny-403 \
        --description="Block SQL injection attacks" \
        --quiet; then
        success "SQL injection protection rule added"
    else
        warning "Failed to add SQL injection protection rule"
    fi
    
    success "Cloud Armor security policy configured with protection rules"
}

# Deploy Apigee instances
deploy_apigee_instances() {
    log "Deploying Apigee instances in multiple regions..."
    
    # Create Apigee instance in US region
    log "Creating Apigee instance in US region..."
    if gcloud apigee instances create us-instance \
        --location="${REGION_US}" \
        --network="${NETWORK_NAME}" \
        --organization="${PROJECT_ID}" \
        --quiet; then
        success "US Apigee instance created"
    else
        error "Failed to create US Apigee instance"
    fi
    
    # Create Apigee instance in EU region
    log "Creating Apigee instance in EU region..."
    if gcloud apigee instances create eu-instance \
        --location="${REGION_EU}" \
        --network="${NETWORK_NAME}" \
        --organization="${PROJECT_ID}" \
        --quiet; then
        success "EU Apigee instance created"
    else
        error "Failed to create EU Apigee instance"
    fi
    
    # Create environment groups
    log "Creating environment groups..."
    if gcloud apigee envgroups create prod-us \
        --hostnames="${DOMAIN_NAME}" \
        --organization="${PROJECT_ID}" \
        --quiet; then
        success "US environment group created"
    else
        warning "Failed to create US environment group"
    fi
    
    if gcloud apigee envgroups create prod-eu \
        --hostnames="eu-${DOMAIN_NAME}" \
        --organization="${PROJECT_ID}" \
        --quiet; then
        success "EU environment group created"
    else
        warning "Failed to create EU environment group"
    fi
    
    # Create environments
    log "Creating environments..."
    if gcloud apigee environments create production-us \
        --organization="${PROJECT_ID}" \
        --quiet; then
        success "US environment created"
    else
        warning "Failed to create US environment"
    fi
    
    if gcloud apigee environments create production-eu \
        --organization="${PROJECT_ID}" \
        --quiet; then
        success "EU environment created"
    else
        warning "Failed to create EU environment"
    fi
    
    success "Apigee instances deployed in US and EU regions"
}

# Create global load balancer
create_load_balancer() {
    log "Creating global load balancer with Cloud Armor integration..."
    
    # Create global static IP address
    log "Creating global static IP address..."
    if gcloud compute addresses create "${LB_NAME}-ip" \
        --global \
        --quiet; then
        success "Global static IP created"
    else
        error "Failed to create global static IP"
    fi
    
    # Get the allocated IP address
    export GLOBAL_IP=$(gcloud compute addresses describe "${LB_NAME}-ip" \
        --global --format="value(address)")
    
    # Save IP to config file
    echo "GLOBAL_IP=${GLOBAL_IP}" >> .deploy_config
    
    # Create health check
    log "Creating health check..."
    if gcloud compute health-checks create http api-health-check \
        --port=80 \
        --request-path=/health \
        --quiet; then
        success "Health check created"
    else
        error "Failed to create health check"
    fi
    
    # Create backend services
    log "Creating backend services..."
    if gcloud compute backend-services create apigee-backend-us \
        --protocol=HTTPS \
        --health-checks=api-health-check \
        --global \
        --quiet; then
        success "US backend service created"
    else
        error "Failed to create US backend service"
    fi
    
    if gcloud compute backend-services create apigee-backend-eu \
        --protocol=HTTPS \
        --health-checks=api-health-check \
        --global \
        --quiet; then
        success "EU backend service created"
    else
        error "Failed to create EU backend service"
    fi
    
    # Attach Cloud Armor policy to backend services
    log "Attaching Cloud Armor policy to backend services..."
    if gcloud compute backend-services update apigee-backend-us \
        --security-policy="${ARMOR_POLICY_NAME}" \
        --global \
        --quiet; then
        success "Cloud Armor policy attached to US backend"
    else
        warning "Failed to attach Cloud Armor policy to US backend"
    fi
    
    if gcloud compute backend-services update apigee-backend-eu \
        --security-policy="${ARMOR_POLICY_NAME}" \
        --global \
        --quiet; then
        success "Cloud Armor policy attached to EU backend"
    else
        warning "Failed to attach Cloud Armor policy to EU backend"
    fi
    
    success "Global load balancer components created"
    log "Global IP: ${GLOBAL_IP}"
}

# Configure SSL and URL mapping
configure_ssl_routing() {
    log "Configuring SSL certificate and URL routing..."
    
    # Create managed SSL certificate
    log "Creating managed SSL certificate..."
    if gcloud compute ssl-certificates create api-ssl-cert \
        --domains="${DOMAIN_NAME},eu-${DOMAIN_NAME}" \
        --global \
        --quiet; then
        success "Managed SSL certificate created"
    else
        error "Failed to create SSL certificate"
    fi
    
    # Create URL map
    log "Creating URL map..."
    if gcloud compute url-maps create "${LB_NAME}-url-map" \
        --default-service=apigee-backend-us \
        --global \
        --quiet; then
        success "URL map created"
    else
        error "Failed to create URL map"
    fi
    
    # Add path matcher for EU traffic
    log "Adding EU path matcher..."
    if gcloud compute url-maps add-path-matcher "${LB_NAME}-url-map" \
        --path-matcher-name=eu-matcher \
        --default-service=apigee-backend-eu \
        --path-rules="/eu/*=apigee-backend-eu" \
        --global \
        --quiet; then
        success "EU path matcher added"
    else
        warning "Failed to add EU path matcher"
    fi
    
    # Create target HTTPS proxy
    log "Creating target HTTPS proxy..."
    if gcloud compute target-https-proxies create "${LB_NAME}-proxy" \
        --ssl-certificates=api-ssl-cert \
        --url-map="${LB_NAME}-url-map" \
        --global \
        --quiet; then
        success "Target HTTPS proxy created"
    else
        error "Failed to create target HTTPS proxy"
    fi
    
    # Create global forwarding rule
    log "Creating global forwarding rule..."
    if gcloud compute forwarding-rules create "${LB_NAME}-rule" \
        --target-https-proxy="${LB_NAME}-proxy" \
        --global \
        --address="${LB_NAME}-ip" \
        --ports=443 \
        --quiet; then
        success "Global forwarding rule created"
    else
        error "Failed to create global forwarding rule"
    fi
    
    success "SSL certificate and URL routing configured"
    warning "Configure DNS: ${DOMAIN_NAME} -> ${GLOBAL_IP}"
}

# Configure API proxy
configure_api_proxy() {
    log "Configuring API proxy deployment..."
    
    # Attach environments to instances
    log "Attaching environments to instances..."
    if gcloud apigee environments attach "${PROJECT_ID}" \
        --environment=production-us \
        --instance=us-instance \
        --quiet; then
        success "US environment attached to instance"
    else
        warning "Failed to attach US environment to instance"
    fi
    
    if gcloud apigee environments attach "${PROJECT_ID}" \
        --environment=production-eu \
        --instance=eu-instance \
        --quiet; then
        success "EU environment attached to instance"
    else
        warning "Failed to attach EU environment to instance"
    fi
    
    success "API proxy deployment configuration completed"
    log "Deploy actual API proxies through Apigee console or API"
}

# Add advanced Cloud Armor rules
add_advanced_armor_rules() {
    log "Configuring advanced Cloud Armor rules..."
    
    # Add XSS protection
    log "Adding XSS protection rule..."
    if gcloud compute security-policies rules create 4000 \
        --security-policy="${ARMOR_POLICY_NAME}" \
        --expression="evaluatePreconfiguredExpr('xss-stable')" \
        --action=deny-403 \
        --description="Block cross-site scripting attacks" \
        --quiet; then
        success "XSS protection rule added"
    else
        warning "Failed to add XSS protection rule"
    fi
    
    # Add LFI protection
    log "Adding local file inclusion protection..."
    if gcloud compute security-policies rules create 5000 \
        --security-policy="${ARMOR_POLICY_NAME}" \
        --expression="evaluatePreconfiguredExpr('lfi-stable')" \
        --action=deny-403 \
        --description="Block local file inclusion attacks" \
        --quiet; then
        success "LFI protection rule added"
    else
        warning "Failed to add LFI protection rule"
    fi
    
    # Add bot protection
    log "Adding bot protection rule..."
    if gcloud compute security-policies rules create 6000 \
        --security-policy="${ARMOR_POLICY_NAME}" \
        --expression="request.headers['user-agent'].contains('BadBot')" \
        --action=deny-403 \
        --description="Block known malicious user agents" \
        --quiet; then
        success "Bot protection rule added"
    else
        warning "Failed to add bot protection rule"
    fi
    
    # Enable verbose logging
    log "Enabling verbose logging..."
    if gcloud compute security-policies update "${ARMOR_POLICY_NAME}" \
        --log-level=VERBOSE \
        --quiet; then
        success "Verbose logging enabled"
    else
        warning "Failed to enable verbose logging"
    fi
    
    success "Advanced Cloud Armor security rules configured"
}

# Validation checks
run_validation() {
    log "Running validation checks..."
    
    # Check security policy
    log "Validating Cloud Armor policy..."
    if gcloud compute security-policies describe "${ARMOR_POLICY_NAME}" --quiet > /dev/null; then
        success "Cloud Armor policy validation passed"
    else
        warning "Cloud Armor policy validation failed"
    fi
    
    # Check backend services
    log "Validating backend services..."
    if gcloud compute backend-services describe apigee-backend-us --global --quiet > /dev/null; then
        success "US backend service validation passed"
    else
        warning "US backend service validation failed"
    fi
    
    if gcloud compute backend-services describe apigee-backend-eu --global --quiet > /dev/null; then
        success "EU backend service validation passed"
    else
        warning "EU backend service validation failed"
    fi
    
    # Check SSL certificate
    log "Checking SSL certificate status..."
    local ssl_status=$(gcloud compute ssl-certificates describe api-ssl-cert \
        --global --format="value(managed.status)" 2>/dev/null || echo "UNKNOWN")
    
    if [[ "$ssl_status" == "ACTIVE" ]]; then
        success "SSL certificate is active"
    elif [[ "$ssl_status" == "PROVISIONING" ]]; then
        warning "SSL certificate is still provisioning"
    else
        warning "SSL certificate status: $ssl_status"
    fi
    
    # Check Apigee instances
    log "Validating Apigee instances..."
    local us_instance_status=$(gcloud apigee instances describe us-instance \
        --organization="${PROJECT_ID}" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    local eu_instance_status=$(gcloud apigee instances describe eu-instance \
        --organization="${PROJECT_ID}" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    
    if [[ "$us_instance_status" == "ACTIVE" ]]; then
        success "US Apigee instance is active"
    else
        warning "US Apigee instance status: $us_instance_status"
    fi
    
    if [[ "$eu_instance_status" == "ACTIVE" ]]; then
        success "EU Apigee instance is active"
    else
        warning "EU Apigee instance status: $eu_instance_status"
    fi
    
    success "Validation checks completed"
}

# Print deployment summary
print_summary() {
    log "Deployment Summary"
    echo "=================================================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Domain Name: ${DOMAIN_NAME}"
    echo "Global IP: ${GLOBAL_IP:-'Not allocated'}"
    echo "Cloud Armor Policy: ${ARMOR_POLICY_NAME}"
    echo "Load Balancer: ${LB_NAME}"
    echo "Network: ${NETWORK_NAME}"
    echo "=================================================="
    echo ""
    success "Multi-Regional API Gateway deployment completed!"
    echo ""
    warning "Next Steps:"
    echo "1. Configure DNS: ${DOMAIN_NAME} -> ${GLOBAL_IP:-'TBD'}"
    echo "2. Wait for SSL certificate provisioning (can take up to 60 minutes)"
    echo "3. Deploy API proxies through Apigee console"
    echo "4. Test API endpoints once DNS propagates"
    echo ""
    log "Configuration saved to .deploy_config for cleanup script"
}

# Main deployment function
main() {
    log "Starting Multi-Regional API Gateways deployment..."
    
    check_prerequisites
    setup_environment
    enable_apis
    create_network
    provision_apigee
    create_cloud_armor
    deploy_apigee_instances
    create_load_balancer
    configure_ssl_routing
    configure_api_proxy
    add_advanced_armor_rules
    run_validation
    print_summary
    
    success "Deployment script completed successfully!"
}

# Execute main function
main "$@"