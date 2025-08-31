#!/bin/bash

# Energy-Efficient Web Hosting with C4A and Hyperdisk - Deployment Script
# This script deploys the complete infrastructure for energy-efficient web hosting
# using GCP C4A instances with Axion processors and Hyperdisk storage

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

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud CLI first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        error "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
    fi
    
    # Check if required APIs can be enabled (requires billing account)
    local PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$PROJECT_ID" ]]; then
        error "No active Google Cloud project set. Please run 'gcloud config set project PROJECT_ID' first."
    fi
    
    # Check for required commands
    for cmd in openssl curl; do
        if ! command -v "$cmd" &> /dev/null; then
            error "$cmd is required but not installed."
        fi
    done
    
    success "Prerequisites check passed"
}

# Environment setup function
setup_environment() {
    log "Setting up environment variables..."
    
    # Set environment variables for GCP resources
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="us-central1"
    export ZONE="us-central1-a"
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set project and region configuration
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Zone: ${ZONE}"
    log "Resource suffix: ${RANDOM_SUFFIX}"
    
    success "Environment configured"
}

# API enablement function
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local APIS=(
        "compute.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${APIS[@]}"; do
        log "Enabling ${api}..."
        if gcloud services enable "$api" --quiet; then
            success "Enabled ${api}"
        else
            error "Failed to enable ${api}"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Network infrastructure function
create_network_infrastructure() {
    log "Creating network infrastructure..."
    
    # Create VPC network
    log "Creating VPC network..."
    if gcloud compute networks create "energy-web-vpc-${RANDOM_SUFFIX}" \
        --subnet-mode regional \
        --description "VPC for energy-efficient web hosting" \
        --quiet; then
        success "VPC network created"
    else
        error "Failed to create VPC network"
    fi
    
    # Create subnet
    log "Creating subnet..."
    if gcloud compute networks subnets create "energy-web-subnet-${RANDOM_SUFFIX}" \
        --network "energy-web-vpc-${RANDOM_SUFFIX}" \
        --range 10.0.0.0/24 \
        --region "${REGION}" \
        --quiet; then
        success "Subnet created"
    else
        error "Failed to create subnet"
    fi
    
    success "Network infrastructure created"
}

# Firewall rules function
create_firewall_rules() {
    log "Creating firewall rules..."
    
    # Allow HTTP traffic
    log "Creating HTTP firewall rule..."
    if gcloud compute firewall-rules create "allow-http-${RANDOM_SUFFIX}" \
        --network "energy-web-vpc-${RANDOM_SUFFIX}" \
        --action allow \
        --direction ingress \
        --source-ranges 0.0.0.0/0 \
        --rules tcp:80 \
        --target-tags web-server \
        --quiet; then
        success "HTTP firewall rule created"
    else
        error "Failed to create HTTP firewall rule"
    fi
    
    # Allow HTTPS traffic
    log "Creating HTTPS firewall rule..."
    if gcloud compute firewall-rules create "allow-https-${RANDOM_SUFFIX}" \
        --network "energy-web-vpc-${RANDOM_SUFFIX}" \
        --action allow \
        --direction ingress \
        --source-ranges 0.0.0.0/0 \
        --rules tcp:443 \
        --target-tags web-server \
        --quiet; then
        success "HTTPS firewall rule created"
    else
        error "Failed to create HTTPS firewall rule"
    fi
    
    # Allow health check traffic
    log "Creating health check firewall rule..."
    if gcloud compute firewall-rules create "allow-health-checks-${RANDOM_SUFFIX}" \
        --network "energy-web-vpc-${RANDOM_SUFFIX}" \
        --action allow \
        --direction ingress \
        --source-ranges 130.211.0.0/22,35.191.0.0/16 \
        --rules tcp:80 \
        --target-tags web-server \
        --quiet; then
        success "Health check firewall rule created"
    else
        error "Failed to create health check firewall rule"
    fi
    
    success "Firewall rules created"
}

# Hyperdisk creation function
create_hyperdisk_volumes() {
    log "Creating Hyperdisk volumes..."
    
    for i in {1..3}; do
        log "Creating Hyperdisk volume ${i}..."
        if gcloud compute disks create "web-data-disk-${i}-${RANDOM_SUFFIX}" \
            --type hyperdisk-balanced \
            --size 50GB \
            --zone "${ZONE}" \
            --provisioned-iops 3000 \
            --provisioned-throughput 140 \
            --quiet; then
            success "Hyperdisk volume ${i} created"
        else
            error "Failed to create Hyperdisk volume ${i}"
        fi
    done
    
    # Verify disk creation
    log "Verifying disk creation..."
    if gcloud compute disks list --filter="zone:(${ZONE}) AND name~web-data-disk.*${RANDOM_SUFFIX}" \
        --format="table(name,sizeGb,type,provisionedIops)" | grep -q "web-data-disk"; then
        success "All Hyperdisk volumes created successfully"
    else
        error "Failed to verify Hyperdisk volumes"
    fi
}

# Startup script creation function
create_startup_script() {
    log "Creating startup script for C4A instances..."
    
    cat > /tmp/startup-script-${RANDOM_SUFFIX}.sh << 'EOF'
#!/bin/bash
apt-get update
apt-get install -y nginx htop fio

# Create a simple energy-efficient web page
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Energy-Efficient Web Hosting</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; }
        .eco-badge { background: #34A853; color: white; padding: 5px 10px; border-radius: 20px; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌱 Energy-Efficient Web Hosting</h1>
        <p><span class="eco-badge">60% More Energy Efficient</span></p>
        <p>This website is powered by Google Cloud C4A instances with Axion processors and Hyperdisk storage.</p>
        <p>Server: <strong>$(hostname)</strong></p>
        <p>Architecture: <strong>ARM64 (Axion)</strong></p>
        <p>Timestamp: <strong>$(date)</strong></p>
    </div>
</body>
</html>
HTML

systemctl enable nginx
systemctl start nginx
EOF
    
    success "Startup script created"
}

# C4A instances creation function
create_c4a_instances() {
    log "Creating C4A instances with Axion processors..."
    
    create_startup_script
    
    for i in {1..3}; do
        log "Creating C4A instance ${i}..."
        if gcloud compute instances create "web-server-${i}-${RANDOM_SUFFIX}" \
            --machine-type c4a-standard-4 \
            --zone "${ZONE}" \
            --network "energy-web-vpc-${RANDOM_SUFFIX}" \
            --subnet "energy-web-subnet-${RANDOM_SUFFIX}" \
            --disk "name=web-data-disk-${i}-${RANDOM_SUFFIX},device-name=data-disk" \
            --image-family ubuntu-2004-lts \
            --image-project ubuntu-os-cloud \
            --tags web-server \
            --metadata-from-file "startup-script=/tmp/startup-script-${RANDOM_SUFFIX}.sh" \
            --maintenance-policy MIGRATE \
            --scopes "https://www.googleapis.com/auth/monitoring.write" \
            --quiet; then
            success "C4A instance ${i} created"
        else
            error "Failed to create C4A instance ${i}"
        fi
    done
    
    # Wait for instances to be ready
    log "Waiting for instances to be ready..."
    sleep 60
    
    success "All C4A instances created"
}

# Load balancer configuration function
configure_load_balancer() {
    log "Configuring load balancer..."
    
    # Create instance group
    log "Creating instance group..."
    if gcloud compute instance-groups unmanaged create "web-instance-group-${RANDOM_SUFFIX}" \
        --zone "${ZONE}" \
        --description "Instance group for energy-efficient web servers" \
        --quiet; then
        success "Instance group created"
    else
        error "Failed to create instance group"
    fi
    
    # Add instances to the group
    log "Adding instances to group..."
    for i in {1..3}; do
        if gcloud compute instance-groups unmanaged add-instances "web-instance-group-${RANDOM_SUFFIX}" \
            --zone "${ZONE}" \
            --instances "web-server-${i}-${RANDOM_SUFFIX}" \
            --quiet; then
            success "Instance ${i} added to group"
        else
            error "Failed to add instance ${i} to group"
        fi
    done
    
    # Create health check
    log "Creating health check..."
    if gcloud compute health-checks create http "web-health-check-${RANDOM_SUFFIX}" \
        --port 80 \
        --check-interval 30s \
        --timeout 10s \
        --healthy-threshold 2 \
        --unhealthy-threshold 3 \
        --request-path "/" \
        --quiet; then
        success "Health check created"
    else
        error "Failed to create health check"
    fi
    
    # Create backend service
    log "Creating backend service..."
    if gcloud compute backend-services create "web-backend-service-${RANDOM_SUFFIX}" \
        --protocol HTTP \
        --health-checks "web-health-check-${RANDOM_SUFFIX}" \
        --global \
        --quiet; then
        success "Backend service created"
    else
        error "Failed to create backend service"
    fi
    
    # Add instance group to backend service
    log "Adding instance group to backend service..."
    if gcloud compute backend-services add-backend "web-backend-service-${RANDOM_SUFFIX}" \
        --instance-group "web-instance-group-${RANDOM_SUFFIX}" \
        --instance-group-zone "${ZONE}" \
        --global \
        --quiet; then
        success "Instance group added to backend service"
    else
        error "Failed to add instance group to backend service"
    fi
    
    success "Load balancer backend configured"
}

# URL map and HTTP proxy function
create_url_map_and_proxy() {
    log "Creating URL map and HTTP proxy..."
    
    # Create URL map
    log "Creating URL map..."
    if gcloud compute url-maps create "web-url-map-${RANDOM_SUFFIX}" \
        --default-service "web-backend-service-${RANDOM_SUFFIX}" \
        --description "URL map for energy-efficient web hosting" \
        --quiet; then
        success "URL map created"
    else
        error "Failed to create URL map"
    fi
    
    # Create HTTP proxy
    log "Creating HTTP proxy..."
    if gcloud compute target-http-proxies create "web-http-proxy-${RANDOM_SUFFIX}" \
        --url-map "web-url-map-${RANDOM_SUFFIX}" \
        --quiet; then
        success "HTTP proxy created"
    else
        error "Failed to create HTTP proxy"
    fi
    
    # Create forwarding rule
    log "Creating forwarding rule..."
    if gcloud compute forwarding-rules create "web-forwarding-rule-${RANDOM_SUFFIX}" \
        --global \
        --target-http-proxy "web-http-proxy-${RANDOM_SUFFIX}" \
        --ports 80 \
        --quiet; then
        success "Forwarding rule created"
    else
        error "Failed to create forwarding rule"
    fi
    
    # Get load balancer IP
    log "Getting load balancer IP address..."
    export LB_IP=$(gcloud compute forwarding-rules describe "web-forwarding-rule-${RANDOM_SUFFIX}" \
        --global \
        --format="value(IPAddress)")
    
    if [[ -n "$LB_IP" ]]; then
        success "HTTP Load Balancer created successfully"
        success "Load Balancer IP: ${LB_IP}"
    else
        error "Failed to get load balancer IP"
    fi
}

# Cloud monitoring setup function
setup_cloud_monitoring() {
    log "Setting up Cloud Monitoring..."
    
    # Create monitoring dashboard configuration
    cat > /tmp/dashboard-config-${RANDOM_SUFFIX}.json << EOF
{
  "displayName": "Energy-Efficient Web Hosting Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "C4A Instance CPU Utilization",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Hyperdisk Performance Metrics",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_disk\" AND metric.type=\"compute.googleapis.com/instance/disk/read_ops_count\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
EOF
    
    # Create the monitoring dashboard
    log "Creating monitoring dashboard..."
    if gcloud monitoring dashboards create --config-from-file="/tmp/dashboard-config-${RANDOM_SUFFIX}.json" --quiet; then
        success "Cloud Monitoring dashboard created"
    else
        warning "Failed to create monitoring dashboard (optional component)"
    fi
}

# Validation function
validate_deployment() {
    log "Validating deployment..."
    
    # Check instance status
    log "Checking C4A instance status..."
    local instance_count=$(gcloud compute instances list --filter="name~web-server.*${RANDOM_SUFFIX}" --format="value(name)" | wc -l)
    if [[ "$instance_count" -eq 3 ]]; then
        success "All 3 C4A instances are running"
    else
        error "Expected 3 instances, found ${instance_count}"
    fi
    
    # Check load balancer health
    log "Checking load balancer health..."
    local healthy_backends=$(gcloud compute backend-services get-health "web-backend-service-${RANDOM_SUFFIX}" \
        --global \
        --format="value(status.healthStatus[].healthState)" | grep -c "HEALTHY" || echo "0")
    
    if [[ "$healthy_backends" -gt 0 ]]; then
        success "Load balancer has ${healthy_backends} healthy backends"
    else
        warning "Load balancer backends are still initializing (this may take a few minutes)"
    fi
    
    # Test load balancer response
    if [[ -n "$LB_IP" ]]; then
        log "Testing load balancer response..."
        sleep 30  # Wait for load balancer to be ready
        
        if curl -s --connect-timeout 10 "http://${LB_IP}" | grep -q "Energy-Efficient Web Hosting"; then
            success "Load balancer is responding correctly"
        else
            warning "Load balancer may still be initializing (check in a few minutes)"
        fi
    fi
    
    success "Deployment validation completed"
}

# Save deployment info function
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > "/tmp/deployment-info-${RANDOM_SUFFIX}.txt" << EOF
Energy-Efficient Web Hosting Deployment Information
==================================================

Project ID: ${PROJECT_ID}
Region: ${REGION}
Zone: ${ZONE}
Resource Suffix: ${RANDOM_SUFFIX}

Load Balancer IP: ${LB_IP}
Web URL: http://${LB_IP}

Resources Created:
- VPC Network: energy-web-vpc-${RANDOM_SUFFIX}
- Subnet: energy-web-subnet-${RANDOM_SUFFIX}
- Firewall Rules: allow-http-${RANDOM_SUFFIX}, allow-https-${RANDOM_SUFFIX}, allow-health-checks-${RANDOM_SUFFIX}
- Hyperdisk Volumes: web-data-disk-1-${RANDOM_SUFFIX}, web-data-disk-2-${RANDOM_SUFFIX}, web-data-disk-3-${RANDOM_SUFFIX}
- C4A Instances: web-server-1-${RANDOM_SUFFIX}, web-server-2-${RANDOM_SUFFIX}, web-server-3-${RANDOM_SUFFIX}
- Instance Group: web-instance-group-${RANDOM_SUFFIX}
- Health Check: web-health-check-${RANDOM_SUFFIX}
- Backend Service: web-backend-service-${RANDOM_SUFFIX}
- URL Map: web-url-map-${RANDOM_SUFFIX}
- HTTP Proxy: web-http-proxy-${RANDOM_SUFFIX}
- Forwarding Rule: web-forwarding-rule-${RANDOM_SUFFIX}

Cleanup Command:
./destroy.sh ${RANDOM_SUFFIX}

Deployment Time: $(date)
EOF
    
    success "Deployment information saved to /tmp/deployment-info-${RANDOM_SUFFIX}.txt"
    echo
    log "📋 Deployment Summary:"
    log "🌐 Web URL: http://${LB_IP}"
    log "📊 Monitoring: https://console.cloud.google.com/monitoring/dashboards"
    log "🧹 Cleanup: ./destroy.sh ${RANDOM_SUFFIX}"
    echo
}

# Cleanup temporary files function
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f "/tmp/startup-script-${RANDOM_SUFFIX}.sh"
    rm -f "/tmp/dashboard-config-${RANDOM_SUFFIX}.json"
    
    success "Temporary files cleaned up"
}

# Main deployment function
main() {
    echo "🚀 Energy-Efficient Web Hosting with C4A and Hyperdisk - Deployment Script"
    echo "============================================================================"
    echo
    
    check_prerequisites
    setup_environment
    enable_apis
    create_network_infrastructure
    create_firewall_rules
    create_hyperdisk_volumes
    create_c4a_instances
    configure_load_balancer
    create_url_map_and_proxy
    setup_cloud_monitoring
    validate_deployment
    save_deployment_info
    cleanup_temp_files
    
    echo
    echo "🎉 Deployment completed successfully!"
    echo "🌱 Your energy-efficient web hosting infrastructure is ready!"
    echo
    echo "Next steps:"
    echo "1. Visit http://${LB_IP} to see your energy-efficient website"
    echo "2. Monitor performance at https://console.cloud.google.com/monitoring"
    echo "3. When done testing, run './destroy.sh ${RANDOM_SUFFIX}' to clean up"
    echo
    echo "🌿 This infrastructure uses ARM-based C4A instances for up to 60% better energy efficiency!"
}

# Error handling
trap 'error "Deployment failed at line $LINENO. Check the logs above for details."' ERR

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi