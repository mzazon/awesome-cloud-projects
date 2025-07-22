#!/bin/bash

# Gaming Backend Performance Cleanup Script
# Remove all Cloud Memorystore Redis, Compute Engine, and Cloud CDN infrastructure
# for high-performance gaming backend with global content delivery

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
error_exit() {
    log_error "$1"
    exit 1
}

# Banner
echo "=================================================================="
echo "  Gaming Backend Performance Cleanup"
echo "  Removing all gaming infrastructure resources"
echo "=================================================================="
echo

# Check prerequisites
log_info "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    error_exit "Google Cloud CLI (gcloud) is not installed. Please install it first."
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    error_exit "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
fi

# Get current project ID
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [[ -z "$CURRENT_PROJECT" ]]; then
    error_exit "No project set. Please run 'gcloud config set project PROJECT_ID'"
fi

log_success "Prerequisites check passed"

# Configuration variables
PROJECT_ID="${PROJECT_ID:-$CURRENT_PROJECT}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
REDIS_INSTANCE_NAME="${REDIS_INSTANCE_NAME:-gaming-redis-cluster}"
GAME_SERVER_NAME="${GAME_SERVER_NAME:-game-server}"

# Try to determine bucket name from existing resources or use pattern
if [[ -n "${BUCKET_NAME:-}" ]]; then
    BUCKET_NAME="${BUCKET_NAME}"
else
    # Try to find the bucket using the naming pattern
    EXISTING_BUCKETS=$(gsutil ls -p "${PROJECT_ID}" | grep "gaming-assets-" | head -1 | sed 's|gs://||' | sed 's|/||' || echo "")
    if [[ -n "$EXISTING_BUCKETS" ]]; then
        BUCKET_NAME="$EXISTING_BUCKETS"
        log_info "Found existing bucket: ${BUCKET_NAME}"
    else
        log_warning "Could not automatically detect bucket name. You may need to clean it up manually."
        BUCKET_NAME=""
    fi
fi

BACKEND_SERVICE_NAME="${BACKEND_SERVICE_NAME:-game-backend-service}"

# Display configuration
log_info "Cleanup configuration:"
echo "  Project ID: ${PROJECT_ID}"
echo "  Region: ${REGION}"
echo "  Zone: ${ZONE}"
echo "  Redis Instance: ${REDIS_INSTANCE_NAME}"
echo "  Game Server: ${GAME_SERVER_NAME}"
echo "  Assets Bucket: ${BUCKET_NAME:-<auto-detect>}"
echo "  Backend Service: ${BACKEND_SERVICE_NAME}"
echo

# Safety confirmation
log_warning "This will permanently delete ALL gaming backend infrastructure!"
log_warning "This action cannot be undone."
echo
read -p "Are you absolutely sure you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Cleanup cancelled by user"
    exit 0
fi

echo
log_info "Starting cleanup process..."

# Configure gcloud settings
gcloud config set project "${PROJECT_ID}"
gcloud config set compute/region "${REGION}"
gcloud config set compute/zone "${ZONE}"

# Step 1: Remove forwarding rules and frontend IP
log_info "Removing load balancer forwarding rules and frontend IP..."

# Remove HTTPS forwarding rule
if gcloud compute forwarding-rules describe game-https-rule --global &>/dev/null; then
    log_info "Deleting HTTPS forwarding rule..."
    gcloud compute forwarding-rules delete game-https-rule --global --quiet
    log_success "HTTPS forwarding rule deleted"
else
    log_warning "HTTPS forwarding rule not found"
fi

# Remove HTTP forwarding rule (fallback)
if gcloud compute forwarding-rules describe game-http-rule --global &>/dev/null; then
    log_info "Deleting HTTP forwarding rule..."
    gcloud compute forwarding-rules delete game-http-rule --global --quiet
    log_success "HTTP forwarding rule deleted"
else
    log_warning "HTTP forwarding rule not found"
fi

# Remove frontend IP address
if gcloud compute addresses describe game-frontend-ip --global &>/dev/null; then
    log_info "Releasing global frontend IP address..."
    gcloud compute addresses delete game-frontend-ip --global --quiet
    log_success "Frontend IP address released"
else
    log_warning "Frontend IP address not found"
fi

# Step 2: Remove target proxies
log_info "Removing target proxies..."

# Remove HTTPS target proxy
if gcloud compute target-https-proxies describe game-https-proxy &>/dev/null; then
    log_info "Deleting HTTPS target proxy..."
    gcloud compute target-https-proxies delete game-https-proxy --quiet
    log_success "HTTPS target proxy deleted"
else
    log_warning "HTTPS target proxy not found"
fi

# Remove HTTP target proxy (fallback)
if gcloud compute target-http-proxies describe game-http-proxy &>/dev/null; then
    log_info "Deleting HTTP target proxy..."
    gcloud compute target-http-proxies delete game-http-proxy --quiet
    log_success "HTTP target proxy deleted"
else
    log_warning "HTTP target proxy not found"
fi

# Remove SSL certificate
if gcloud compute ssl-certificates describe game-ssl-cert --global &>/dev/null; then
    log_info "Deleting SSL certificate..."
    gcloud compute ssl-certificates delete game-ssl-cert --global --quiet
    log_success "SSL certificate deleted"
else
    log_warning "SSL certificate not found"
fi

# Step 3: Remove URL map
log_info "Removing URL map..."
if gcloud compute url-maps describe game-backend-map &>/dev/null; then
    log_info "Deleting URL map..."
    gcloud compute url-maps delete game-backend-map --quiet
    log_success "URL map deleted"
else
    log_warning "URL map not found"
fi

# Step 4: Remove backend services
log_info "Removing backend services..."

# Remove backend service
if gcloud compute backend-services describe "${BACKEND_SERVICE_NAME}" --global &>/dev/null; then
    log_info "Deleting backend service..."
    gcloud compute backend-services delete "${BACKEND_SERVICE_NAME}" --global --quiet
    log_success "Backend service deleted"
else
    log_warning "Backend service not found"
fi

# Remove backend bucket
if gcloud compute backend-buckets describe game-assets-backend &>/dev/null; then
    log_info "Deleting backend bucket configuration..."
    gcloud compute backend-buckets delete game-assets-backend --quiet
    log_success "Backend bucket configuration deleted"
else
    log_warning "Backend bucket configuration not found"
fi

# Step 5: Remove instance groups and templates
log_info "Removing instance groups and templates..."

# Remove managed instance group
if gcloud compute instance-groups managed describe game-server-group --zone="${ZONE}" &>/dev/null; then
    log_info "Deleting managed instance group..."
    gcloud compute instance-groups managed delete game-server-group --zone="${ZONE}" --quiet
    log_success "Managed instance group deleted"
else
    log_warning "Managed instance group not found"
fi

# Remove instance template
if gcloud compute instance-templates describe game-server-template &>/dev/null; then
    log_info "Deleting instance template..."
    gcloud compute instance-templates delete game-server-template --quiet
    log_success "Instance template deleted"
else
    log_warning "Instance template not found"
fi

# Step 6: Remove standalone game server instance
log_info "Removing game server instance..."
if gcloud compute instances describe "${GAME_SERVER_NAME}" --zone="${ZONE}" &>/dev/null; then
    log_info "Deleting game server instance..."
    gcloud compute instances delete "${GAME_SERVER_NAME}" --zone="${ZONE}" --quiet
    log_success "Game server instance deleted"
else
    log_warning "Game server instance not found"
fi

# Step 7: Remove health checks
log_info "Removing health checks..."
if gcloud compute health-checks describe game-server-health &>/dev/null; then
    log_info "Deleting health check..."
    gcloud compute health-checks delete game-server-health --quiet
    log_success "Health check deleted"
else
    log_warning "Health check not found"
fi

# Step 8: Remove firewall rules
log_info "Removing firewall rules..."
if gcloud compute firewall-rules describe allow-game-server-traffic &>/dev/null; then
    log_info "Deleting firewall rule..."
    gcloud compute firewall-rules delete allow-game-server-traffic --quiet
    log_success "Firewall rule deleted"
else
    log_warning "Firewall rule not found"
fi

# Step 9: Remove Cloud Storage bucket and contents
if [[ -n "$BUCKET_NAME" ]]; then
    log_info "Removing Cloud Storage bucket and contents..."
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_info "Deleting all objects in bucket..."
        gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true
        
        log_info "Deleting storage bucket..."
        gsutil rb "gs://${BUCKET_NAME}"
        log_success "Storage bucket and contents deleted"
    else
        log_warning "Storage bucket not found"
    fi
else
    log_warning "Storage bucket name not specified - please check for any gaming-assets-* buckets manually"
    log_info "You can list buckets with: gsutil ls -p ${PROJECT_ID}"
fi

# Step 10: Remove Redis instance (this takes the longest)
log_info "Removing Cloud Memorystore Redis instance..."
if gcloud redis instances describe "${REDIS_INSTANCE_NAME}" --region="${REGION}" &>/dev/null; then
    log_info "Deleting Redis instance (this may take 5-10 minutes)..."
    log_warning "Redis deletion is running in the background..."
    
    gcloud redis instances delete "${REDIS_INSTANCE_NAME}" \
        --region="${REGION}" \
        --async \
        --quiet
    
    log_success "Redis instance deletion initiated"
    log_info "Note: Redis deletion will continue in the background and may take 5-10 minutes"
else
    log_warning "Redis instance not found"
fi

# Step 11: Clean up any remaining resources
log_info "Checking for any remaining gaming-related resources..."

# Check for any remaining instances with game-server tag
REMAINING_INSTANCES=$(gcloud compute instances list --filter="tags.items:game-server" --format="value(name,zone)" 2>/dev/null || echo "")
if [[ -n "$REMAINING_INSTANCES" ]]; then
    log_warning "Found remaining instances with game-server tag:"
    echo "$REMAINING_INSTANCES"
    log_info "Consider removing these manually if they were part of the gaming infrastructure"
fi

# Check for any remaining buckets with gaming-assets prefix
REMAINING_BUCKETS=$(gsutil ls -p "${PROJECT_ID}" | grep "gaming-assets-" || echo "")
if [[ -n "$REMAINING_BUCKETS" ]]; then
    log_warning "Found remaining storage buckets:"
    echo "$REMAINING_BUCKETS"
    log_info "Consider removing these manually if they were part of the gaming infrastructure"
fi

# Clean up local temporary files if they exist
log_info "Cleaning up local temporary files..."
rm -f /tmp/startup-script.sh
rm -f /tmp/redis-test.sh
rm -rf /tmp/game-assets

# Final verification
log_info "Performing final verification..."

# Check if Redis is still deleting
REDIS_STATE=$(gcloud redis instances describe "${REDIS_INSTANCE_NAME}" --region="${REGION}" --format="get(state)" 2>/dev/null || echo "NOT_FOUND")
if [[ "$REDIS_STATE" == "DELETING" ]]; then
    log_info "Redis instance is still being deleted in the background"
elif [[ "$REDIS_STATE" == "NOT_FOUND" ]]; then
    log_success "Redis instance deletion completed"
else
    log_warning "Redis instance is in unexpected state: ${REDIS_STATE}"
fi

# Cleanup summary
echo
echo "=================================================================="
echo "  CLEANUP COMPLETED"
echo "=================================================================="
echo
log_success "Gaming backend infrastructure cleanup completed!"
echo
echo "Resources Removed:"
echo "  ✅ Global Load Balancer and CDN configuration"
echo "  ✅ Frontend IP address and forwarding rules"
echo "  ✅ Target proxies and SSL certificates"
echo "  ✅ Backend services and URL mapping"
echo "  ✅ Compute Engine instances and instance groups"
echo "  ✅ Health checks and firewall rules"
echo "  ✅ Cloud Storage bucket and game assets"
echo "  ⏳ Redis instance (deletion in progress)"
echo
echo "Important Notes:"
echo "  • Redis instance deletion may take an additional 5-10 minutes"
echo "  • Check your Cloud Console to verify all resources are removed"
echo "  • Review your billing to ensure charges have stopped"
echo "  • Any custom domains or DNS records need manual cleanup"
echo
log_info "Monitor the Redis deletion progress with:"
echo "  gcloud redis instances list --region=${REGION}"
echo
echo "Check for any remaining gaming resources with:"
echo "  gcloud compute instances list --filter='tags.items:game-server'"
echo "  gsutil ls -p ${PROJECT_ID} | grep gaming-assets"
echo
log_success "Cleanup process completed successfully!"
echo "=================================================================="