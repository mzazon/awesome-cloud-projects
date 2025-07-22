#!/bin/bash

# Deploy Multi-Region Traffic Optimization with Load Balancing and Performance Monitoring
# This script automates the deployment of a global load balancer with CDN and monitoring

set -euo pipefail

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
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handler
error_exit() {
    log_error "Script failed at line $1"
    log_error "Check the logs above for details"
    exit 1
}

trap 'error_exit $LINENO' ERR

# Display banner
echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                 GCP Multi-Region Traffic Optimization Deployment             ║
║                        with Load Balancing & Monitoring                      ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check prerequisites
log "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    log_error "No active Google Cloud authentication found. Please run 'gcloud auth login'"
    exit 1
fi

# Check if openssl is available for random generation
if ! command -v openssl &> /dev/null; then
    log_error "OpenSSL is required for generating random suffixes. Please install it."
    exit 1
fi

log_success "Prerequisites check completed"

# Configuration section
log "Setting up configuration..."

# Set environment variables for GCP resources
export PROJECT_ID="${PROJECT_ID:-traffic-optimization-$(date +%s)}"
export REGION_US="${REGION_US:-us-central1}"
export REGION_EU="${REGION_EU:-europe-west1}"
export REGION_APAC="${REGION_APAC:-asia-southeast1}"
export ZONE_US="${ZONE_US:-us-central1-a}"
export ZONE_EU="${ZONE_EU:-europe-west1-b}"
export ZONE_APAC="${ZONE_APAC:-asia-southeast1-a}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
export LB_NAME="global-lb-${RANDOM_SUFFIX}"
export CDN_NAME="global-cdn-${RANDOM_SUFFIX}"

log "Project ID: ${PROJECT_ID}"
log "Random suffix: ${RANDOM_SUFFIX}"
log "Regions: US(${REGION_US}), EU(${REGION_EU}), APAC(${REGION_APAC})"

# Confirm deployment
echo
read -p "$(echo -e ${YELLOW}Do you want to proceed with the deployment? [y/N]: ${NC})" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Deployment cancelled by user"
    exit 0
fi

# Check if project exists, create if it doesn't
log "Checking if project exists..."
if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
    log_warning "Project ${PROJECT_ID} already exists. Using existing project."
else
    log "Creating new project: ${PROJECT_ID}"
    gcloud projects create "${PROJECT_ID}" --name="Traffic Optimization Project"
    log_success "Project created successfully"
fi

# Set project and defaults
log "Configuring gcloud defaults..."
gcloud config set project "${PROJECT_ID}"
gcloud config set compute/region "${REGION_US}"
gcloud config set compute/zone "${ZONE_US}"

# Check billing account and link if needed
BILLING_ACCOUNT=$(gcloud billing accounts list --filter="open=true" --format="value(name)" | head -n1)
if [[ -z "$BILLING_ACCOUNT" ]]; then
    log_error "No active billing account found. Please ensure you have a billing account set up."
    exit 1
fi

log "Linking billing account to project..."
gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT}" || {
    log_warning "Failed to link billing account automatically. Please link manually if needed."
}

# Enable required APIs
log "Enabling required APIs..."
gcloud services enable \
    compute.googleapis.com \
    cloudbuild.googleapis.com \
    monitoring.googleapis.com \
    logging.googleapis.com \
    networkmanagement.googleapis.com \
    --project="${PROJECT_ID}"

log_success "Required APIs enabled"

# Wait for API propagation
log "Waiting for API propagation..."
sleep 30

# Step 1: Create VPC Network and Firewall Rules
log "Step 1: Creating VPC network and firewall rules..."

gcloud compute networks create global-app-vpc \
    --subnet-mode custom \
    --description="Global VPC for multi-region app" \
    --project="${PROJECT_ID}"

# Create subnets in each region
gcloud compute networks subnets create us-subnet \
    --network global-app-vpc \
    --range 10.1.0.0/24 \
    --region "${REGION_US}" \
    --project="${PROJECT_ID}"

gcloud compute networks subnets create eu-subnet \
    --network global-app-vpc \
    --range 10.2.0.0/24 \
    --region "${REGION_EU}" \
    --project="${PROJECT_ID}"

gcloud compute networks subnets create apac-subnet \
    --network global-app-vpc \
    --range 10.3.0.0/24 \
    --region "${REGION_APAC}" \
    --project="${PROJECT_ID}"

# Create firewall rules for HTTP/HTTPS and health checks
gcloud compute firewall-rules create allow-http-https \
    --network global-app-vpc \
    --allow tcp:80,tcp:443,tcp:8080 \
    --source-ranges 0.0.0.0/0 \
    --description="Allow HTTP/HTTPS traffic" \
    --project="${PROJECT_ID}"

gcloud compute firewall-rules create allow-health-checks \
    --network global-app-vpc \
    --allow tcp:8080 \
    --source-ranges 130.211.0.0/22,35.191.0.0/16 \
    --description="Allow Google health checks" \
    --project="${PROJECT_ID}"

log_success "VPC network and firewall rules created"

# Step 2: Deploy Application Instances Across Regions
log "Step 2: Deploying application instances across regions..."

# Create startup script for web servers
cat > startup-script.sh << 'EOF'
#!/bin/bash
apt-get update
apt-get install -y nginx

# Get instance metadata
INSTANCE_NAME=$(curl -H "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/name)
ZONE=$(curl -H "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d'/' -f4)

# Create custom index page with region info
cat > /var/www/html/index.html << EOL
<!DOCTYPE html>
<html>
<head><title>Global App - ${ZONE}</title></head>
<body>
<h1>Hello from ${INSTANCE_NAME}</h1>
<p>Serving from zone: ${ZONE}</p>
<p>Server time: $(date)</p>
<p>Load balancer working correctly!</p>
</body>
</html>
EOL

# Configure nginx to listen on port 8080
sed -i 's/listen 80/listen 8080/' /etc/nginx/sites-available/default
systemctl restart nginx
systemctl enable nginx
EOF

# Create instance template
gcloud compute instance-templates create "app-template-${RANDOM_SUFFIX}" \
    --machine-type e2-medium \
    --network-interface subnet=us-subnet,no-address \
    --metadata-from-file startup-script=startup-script.sh \
    --image-family debian-11 \
    --image-project debian-cloud \
    --tags http-server \
    --project="${PROJECT_ID}"

# Create managed instance groups in each region
gcloud compute instance-groups managed create "us-ig-${RANDOM_SUFFIX}" \
    --template "app-template-${RANDOM_SUFFIX}" \
    --size 2 \
    --zone "${ZONE_US}" \
    --project="${PROJECT_ID}"

gcloud compute instance-groups managed create "eu-ig-${RANDOM_SUFFIX}" \
    --template "app-template-${RANDOM_SUFFIX}" \
    --size 2 \
    --zone "${ZONE_EU}" \
    --project="${PROJECT_ID}"

gcloud compute instance-groups managed create "apac-ig-${RANDOM_SUFFIX}" \
    --template "app-template-${RANDOM_SUFFIX}" \
    --size 2 \
    --zone "${ZONE_APAC}" \
    --project="${PROJECT_ID}"

log_success "Application instances deployed across all regions"

# Wait for instances to be ready
log "Waiting for instances to be ready..."
sleep 60

# Step 3: Configure Health Checks
log "Step 3: Configuring health checks..."

gcloud compute health-checks create http "global-health-check-${RANDOM_SUFFIX}" \
    --port 8080 \
    --request-path "/" \
    --check-interval 10s \
    --timeout 5s \
    --healthy-threshold 2 \
    --unhealthy-threshold 3 \
    --description="Global health check for multi-region app" \
    --project="${PROJECT_ID}"

# Set named ports for instance groups
gcloud compute instance-groups managed set-named-ports "us-ig-${RANDOM_SUFFIX}" \
    --named-ports http:8080 \
    --zone "${ZONE_US}" \
    --project="${PROJECT_ID}"

gcloud compute instance-groups managed set-named-ports "eu-ig-${RANDOM_SUFFIX}" \
    --named-ports http:8080 \
    --zone "${ZONE_EU}" \
    --project="${PROJECT_ID}"

gcloud compute instance-groups managed set-named-ports "apac-ig-${RANDOM_SUFFIX}" \
    --named-ports http:8080 \
    --zone "${ZONE_APAC}" \
    --project="${PROJECT_ID}"

log_success "Health checks configured"

# Step 4: Create Backend Services
log "Step 4: Creating backend services..."

gcloud compute backend-services create "global-backend-${RANDOM_SUFFIX}" \
    --protocol HTTP \
    --health-checks "global-health-check-${RANDOM_SUFFIX}" \
    --global \
    --load-balancing-scheme EXTERNAL \
    --enable-cdn \
    --cache-mode CACHE_ALL_STATIC \
    --description="Global backend service with CDN" \
    --project="${PROJECT_ID}"

# Add instance groups as backends
gcloud compute backend-services add-backend "global-backend-${RANDOM_SUFFIX}" \
    --instance-group "us-ig-${RANDOM_SUFFIX}" \
    --instance-group-zone "${ZONE_US}" \
    --capacity-scaler 1.0 \
    --max-utilization 0.8 \
    --global \
    --project="${PROJECT_ID}"

gcloud compute backend-services add-backend "global-backend-${RANDOM_SUFFIX}" \
    --instance-group "eu-ig-${RANDOM_SUFFIX}" \
    --instance-group-zone "${ZONE_EU}" \
    --capacity-scaler 1.0 \
    --max-utilization 0.8 \
    --global \
    --project="${PROJECT_ID}"

gcloud compute backend-services add-backend "global-backend-${RANDOM_SUFFIX}" \
    --instance-group "apac-ig-${RANDOM_SUFFIX}" \
    --instance-group-zone "${ZONE_APAC}" \
    --capacity-scaler 1.0 \
    --max-utilization 0.8 \
    --global \
    --project="${PROJECT_ID}"

log_success "Backend services created"

# Step 5: Configure Global Load Balancer
log "Step 5: Configuring global load balancer..."

# Create URL map
gcloud compute url-maps create "global-url-map-${RANDOM_SUFFIX}" \
    --default-service "global-backend-${RANDOM_SUFFIX}" \
    --description="Global URL map for multi-region routing" \
    --project="${PROJECT_ID}"

# Create target HTTP proxy
gcloud compute target-http-proxies create "global-http-proxy-${RANDOM_SUFFIX}" \
    --url-map "global-url-map-${RANDOM_SUFFIX}" \
    --project="${PROJECT_ID}"

# Create global forwarding rule
gcloud compute forwarding-rules create "global-http-rule-${RANDOM_SUFFIX}" \
    --global \
    --target-http-proxy "global-http-proxy-${RANDOM_SUFFIX}" \
    --ports 80 \
    --project="${PROJECT_ID}"

# Get the external IP address
export GLOBAL_IP=$(gcloud compute forwarding-rules describe \
    "global-http-rule-${RANDOM_SUFFIX}" \
    --global --format="value(IPAddress)" \
    --project="${PROJECT_ID}")

log_success "Global load balancer configured"
log "Global IP Address: ${GLOBAL_IP}"

# Step 6: Configure CDN
log "Step 6: Configuring Cloud CDN..."

gcloud compute backend-services update "global-backend-${RANDOM_SUFFIX}" \
    --enable-cdn \
    --cache-mode CACHE_ALL_STATIC \
    --default-ttl 3600 \
    --max-ttl 86400 \
    --client-ttl 3600 \
    --enable-compression \
    --global \
    --project="${PROJECT_ID}"

# Configure cache key policy
gcloud compute backend-services update "global-backend-${RANDOM_SUFFIX}" \
    --cache-key-include-protocol \
    --cache-key-include-host \
    --cache-key-include-query-string \
    --global \
    --project="${PROJECT_ID}"

log_success "Cloud CDN configured"

# Step 7: Set Up Network Intelligence Center
log "Step 7: Setting up Network Intelligence Center monitoring..."

# Wait for instances to be fully running
log "Waiting for instances to be fully operational..."
sleep 120

# Get instance names for connectivity tests
US_INSTANCE=$(gcloud compute instances list --filter="name~us-ig-${RANDOM_SUFFIX}" --zones="${ZONE_US}" --format="value(name)" --project="${PROJECT_ID}" | head -1)
EU_INSTANCE=$(gcloud compute instances list --filter="name~eu-ig-${RANDOM_SUFFIX}" --zones="${ZONE_EU}" --format="value(name)" --project="${PROJECT_ID}" | head -1)
APAC_INSTANCE=$(gcloud compute instances list --filter="name~apac-ig-${RANDOM_SUFFIX}" --zones="${ZONE_APAC}" --format="value(name)" --project="${PROJECT_ID}" | head -1)

if [[ -n "$US_INSTANCE" && -n "$EU_INSTANCE" ]]; then
    gcloud network-management connectivity-tests create us-to-eu-test \
        --source-instance "$US_INSTANCE" \
        --source-instance-zone "${ZONE_US}" \
        --destination-instance "$EU_INSTANCE" \
        --destination-instance-zone "${ZONE_EU}" \
        --protocol TCP \
        --destination-port 8080 \
        --description="Test connectivity between US and EU regions" \
        --project="${PROJECT_ID}" || log_warning "Failed to create US-EU connectivity test"
fi

if [[ -n "$US_INSTANCE" && -n "$APAC_INSTANCE" ]]; then
    gcloud network-management connectivity-tests create us-to-apac-test \
        --source-instance "$US_INSTANCE" \
        --source-instance-zone "${ZONE_US}" \
        --destination-instance "$APAC_INSTANCE" \
        --destination-instance-zone "${ZONE_APAC}" \
        --protocol TCP \
        --destination-port 8080 \
        --description="Test connectivity between US and APAC regions" \
        --project="${PROJECT_ID}" || log_warning "Failed to create US-APAC connectivity test"
fi

log_success "Network Intelligence Center configured"

# Step 8: Configure Monitoring
log "Step 8: Configuring Cloud Monitoring..."

# Create uptime check
gcloud alpha monitoring uptime create "global-app-uptime-${RANDOM_SUFFIX}" \
    --hostname="${GLOBAL_IP}" \
    --path="/" \
    --port=80 \
    --protocol=HTTP \
    --timeout=10s \
    --period=60s \
    --display-name="Global App Availability Check" \
    --project="${PROJECT_ID}" || log_warning "Failed to create uptime check (alpha feature may not be available)"

log_success "Cloud Monitoring configured"

# Step 9: Advanced Traffic Optimization
log "Step 9: Implementing advanced traffic optimization..."

gcloud compute backend-services update "global-backend-${RANDOM_SUFFIX}" \
    --load-balancing-scheme EXTERNAL \
    --locality-lb-policy ROUND_ROBIN \
    --outlier-detection-consecutive-errors 5 \
    --outlier-detection-consecutive-gateway-failure 3 \
    --outlier-detection-interval 30s \
    --outlier-detection-base-ejection-time 30s \
    --outlier-detection-max-ejection-percent 10 \
    --global \
    --project="${PROJECT_ID}"

# Configure circuit breaker settings
gcloud compute backend-services update "global-backend-${RANDOM_SUFFIX}" \
    --circuit-breakers-max-requests 1000 \
    --circuit-breakers-max-pending-requests 100 \
    --circuit-breakers-max-retries 3 \
    --circuit-breakers-max-connections 1000 \
    --global \
    --project="${PROJECT_ID}"

log_success "Advanced traffic optimization configured"

# Step 10: CDN Optimization
log "Step 10: Optimizing CDN configuration..."

gcloud compute backend-services update "global-backend-${RANDOM_SUFFIX}" \
    --compression-mode AUTOMATIC \
    --global \
    --project="${PROJECT_ID}"

gcloud compute backend-services update "global-backend-${RANDOM_SUFFIX}" \
    --negative-caching \
    --negative-caching-policy "404=300,500=60" \
    --global \
    --project="${PROJECT_ID}"

gcloud compute backend-services update "global-backend-${RANDOM_SUFFIX}" \
    --cache-mode USE_ORIGIN_HEADERS \
    --serve-while-stale 86400 \
    --global \
    --project="${PROJECT_ID}"

log_success "CDN optimization completed"

# Save deployment information
log "Saving deployment information..."
cat > deployment-info.txt << EOF
Deployment Information
=====================
Project ID: ${PROJECT_ID}
Random Suffix: ${RANDOM_SUFFIX}
Global IP Address: ${GLOBAL_IP}
Deployment Date: $(date)

Resources Created:
- VPC Network: global-app-vpc
- Subnets: us-subnet, eu-subnet, apac-subnet
- Instance Template: app-template-${RANDOM_SUFFIX}
- Instance Groups: us-ig-${RANDOM_SUFFIX}, eu-ig-${RANDOM_SUFFIX}, apac-ig-${RANDOM_SUFFIX}
- Health Check: global-health-check-${RANDOM_SUFFIX}
- Backend Service: global-backend-${RANDOM_SUFFIX}
- URL Map: global-url-map-${RANDOM_SUFFIX}
- HTTP Proxy: global-http-proxy-${RANDOM_SUFFIX}
- Forwarding Rule: global-http-rule-${RANDOM_SUFFIX}

Access URL: http://${GLOBAL_IP}

Cleanup Command:
./destroy.sh

EOF

log_success "Deployment information saved to deployment-info.txt"

# Cleanup temporary files
rm -f startup-script.sh

# Final validation
log "Performing final validation..."
log "Waiting for load balancer to be fully operational..."
sleep 60

# Test global load balancer
log "Testing global load balancer accessibility..."
if curl -f -s -m 10 "http://${GLOBAL_IP}" > /dev/null; then
    log_success "Load balancer is responding successfully"
else
    log_warning "Load balancer may still be propagating. Try accessing http://${GLOBAL_IP} in a few minutes."
fi

# Display summary
echo
log_success "Deployment completed successfully!"
echo -e "${GREEN}"
cat << EOF
╔══════════════════════════════════════════════════════════════════════════════╗
║                           DEPLOYMENT SUMMARY                                 ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ Global Load Balancer IP: ${GLOBAL_IP}                                       ║
║ Project ID: ${PROJECT_ID}                              ║
║ CDN Enabled: Yes                                                             ║
║ Health Checks: Configured                                                    ║
║ Monitoring: Enabled                                                          ║
║                                                                              ║
║ Access your application: http://${GLOBAL_IP}                                ║
║                                                                              ║
║ Monitor performance:                                                         ║
║ https://console.cloud.google.com/monitoring                                 ║
║                                                                              ║
║ View Network Intelligence:                                                   ║
║ https://console.cloud.google.com/net-intelligence                           ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log "Deployment information saved in deployment-info.txt"
log "To clean up resources, run: ./destroy.sh"

exit 0