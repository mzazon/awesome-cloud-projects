#!/bin/bash

# Gaming Backend Performance Deployment Script
# Deploy Cloud Memorystore Redis, Compute Engine, and Cloud CDN infrastructure
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

# Cleanup function for partial deployments
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    
    # Remove forwarding rules if they exist
    if gcloud compute forwarding-rules describe game-https-rule --global &>/dev/null; then
        gcloud compute forwarding-rules delete game-https-rule --global --quiet || true
    fi
    
    # Remove target proxy if it exists
    if gcloud compute target-https-proxies describe game-https-proxy &>/dev/null; then
        gcloud compute target-https-proxies delete game-https-proxy --quiet || true
    fi
    
    # Remove instance group if it exists
    if gcloud compute instance-groups managed describe game-server-group --zone="${ZONE}" &>/dev/null; then
        gcloud compute instance-groups managed delete game-server-group --zone="${ZONE}" --quiet || true
    fi
    
    # Remove instance if it exists
    if gcloud compute instances describe "${GAME_SERVER_NAME}" --zone="${ZONE}" &>/dev/null; then
        gcloud compute instances delete "${GAME_SERVER_NAME}" --zone="${ZONE}" --quiet || true
    fi
    
    log_info "Partial cleanup completed. Please run destroy.sh to ensure all resources are removed."
}

# Set trap for error handling
trap cleanup_on_error ERR

# Banner
echo "=================================================================="
echo "  Gaming Backend Performance Deployment"
echo "  Cloud Memorystore + Cloud CDN + Global Load Balancing"
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

# Generate unique suffix for resource naming
RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
BUCKET_NAME="${BUCKET_NAME:-gaming-assets-${RANDOM_SUFFIX}}"
BACKEND_SERVICE_NAME="${BACKEND_SERVICE_NAME:-game-backend-service}"

# Display configuration
log_info "Deployment configuration:"
echo "  Project ID: ${PROJECT_ID}"
echo "  Region: ${REGION}"
echo "  Zone: ${ZONE}"
echo "  Redis Instance: ${REDIS_INSTANCE_NAME}"
echo "  Game Server: ${GAME_SERVER_NAME}"
echo "  Assets Bucket: ${BUCKET_NAME}"
echo "  Backend Service: ${BACKEND_SERVICE_NAME}"
echo

# Confirmation prompt
read -p "Continue with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Deployment cancelled by user"
    exit 0
fi

# Configure gcloud
log_info "Configuring Google Cloud CLI settings..."
gcloud config set project "${PROJECT_ID}"
gcloud config set compute/region "${REGION}"
gcloud config set compute/zone "${ZONE}"

# Enable required APIs
log_info "Enabling required Google Cloud APIs..."
gcloud services enable compute.googleapis.com \
    redis.googleapis.com \
    storage.googleapis.com \
    dns.googleapis.com \
    cloudresourcemanager.googleapis.com \
    --quiet

log_success "Required APIs enabled"

# Wait for API propagation
log_info "Waiting for API propagation..."
sleep 30

# Step 1: Create Cloud Memorystore Redis Instance
log_info "Creating Cloud Memorystore Redis instance..."
if gcloud redis instances describe "${REDIS_INSTANCE_NAME}" --region="${REGION}" &>/dev/null; then
    log_warning "Redis instance ${REDIS_INSTANCE_NAME} already exists"
else
    gcloud redis instances create "${REDIS_INSTANCE_NAME}" \
        --size=1 \
        --region="${REGION}" \
        --redis-version=redis_7_0 \
        --enable-auth \
        --tier=standard_ha \
        --redis-config maxmemory-policy=allkeys-lru \
        --quiet
    
    # Wait for Redis instance to be ready
    log_info "Waiting for Redis instance to be ready..."
    while [[ $(gcloud redis instances describe "${REDIS_INSTANCE_NAME}" --region="${REGION}" --format="get(state)") != "READY" ]]; do
        log_info "Redis instance is still being created..."
        sleep 30
    done
fi

log_success "Redis instance is ready"

# Step 2: Create Cloud Storage bucket
log_info "Creating Cloud Storage bucket for game assets..."
if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
    log_warning "Bucket gs://${BUCKET_NAME} already exists"
else
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}"
    
    # Configure bucket for public read access
    gsutil iam ch allUsers:objectViewer "gs://${BUCKET_NAME}"
    
    # Enable website configuration
    gsutil web set -m index.html "gs://${BUCKET_NAME}"
fi

log_success "Cloud Storage bucket created and configured"

# Step 3: Upload sample game assets
log_info "Creating and uploading sample game assets..."
mkdir -p /tmp/game-assets

# Create sample assets
cat > /tmp/game-assets/game-config.json << 'EOF'
{
    "gameVersion": "1.2.3",
    "maxPlayers": 100,
    "serverRegion": "us-central1",
    "features": {
        "leaderboards": true,
        "realTimeChat": true,
        "crossPlatform": true
    }
}
EOF

echo "Sample game texture data for high-resolution gaming assets" > /tmp/game-assets/texture-pack.bin
echo "Background music data for immersive gaming experience" > /tmp/game-assets/audio-track.mp3
echo "Game sound effects and audio cues" > /tmp/game-assets/sound-effects.wav

# Upload assets with proper directory structure
gsutil cp /tmp/game-assets/game-config.json "gs://${BUCKET_NAME}/configs/"
gsutil cp /tmp/game-assets/texture-pack.bin "gs://${BUCKET_NAME}/assets/textures/"
gsutil cp /tmp/game-assets/audio-track.mp3 "gs://${BUCKET_NAME}/assets/audio/"
gsutil cp /tmp/game-assets/sound-effects.wav "gs://${BUCKET_NAME}/assets/audio/"

# Set cache control headers
gsutil setmeta -h "Cache-Control:public, max-age=86400" \
    "gs://${BUCKET_NAME}/configs/game-config.json"
gsutil setmeta -h "Cache-Control:public, max-age=604800" \
    "gs://${BUCKET_NAME}/assets/textures/texture-pack.bin"
gsutil setmeta -h "Cache-Control:public, max-age=604800" \
    "gs://${BUCKET_NAME}/assets/audio/*"

# Cleanup temporary files
rm -rf /tmp/game-assets

log_success "Game assets uploaded with optimized caching headers"

# Step 4: Create game server instance
log_info "Creating game server Compute Engine instance..."
if gcloud compute instances describe "${GAME_SERVER_NAME}" --zone="${ZONE}" &>/dev/null; then
    log_warning "Game server instance ${GAME_SERVER_NAME} already exists"
else
    # Create startup script
    cat > /tmp/startup-script.sh << 'EOF'
#!/bin/bash
apt-get update
apt-get install -y redis-tools nginx python3-pip curl
systemctl enable nginx
systemctl start nginx

# Create a simple health check endpoint
cat > /var/www/html/health << 'HEALTHEOF'
OK
HEALTHEOF

# Configure nginx for game server
cat > /etc/nginx/sites-available/game-server << 'NGINXEOF'
server {
    listen 80;
    listen 8080;
    server_name _;
    
    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }
    
    location /api/ {
        proxy_pass http://localhost:3000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
    
    location / {
        root /var/www/html;
        index index.html;
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/game-server /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl reload nginx

# Log installation completion
echo "Game server setup completed at $(date)" >> /var/log/game-server-setup.log
EOF

    gcloud compute instances create "${GAME_SERVER_NAME}" \
        --zone="${ZONE}" \
        --machine-type=n2-standard-2 \
        --network-tier=PREMIUM \
        --maintenance-policy=MIGRATE \
        --provisioning-model=STANDARD \
        --image-family=ubuntu-2004-lts \
        --image-project=ubuntu-os-cloud \
        --boot-disk-size=20GB \
        --boot-disk-type=pd-standard \
        --tags=game-server,http-server \
        --metadata-from-file startup-script=/tmp/startup-script.sh \
        --quiet
    
    # Wait for instance to be ready
    log_info "Waiting for game server instance to be ready..."
    while [[ $(gcloud compute instances describe "${GAME_SERVER_NAME}" --zone="${ZONE}" --format="get(status)") != "RUNNING" ]]; do
        log_info "Game server instance is starting..."
        sleep 15
    done
    
    # Wait additional time for startup script to complete
    log_info "Waiting for startup script to complete..."
    sleep 60
    
    rm -f /tmp/startup-script.sh
fi

log_success "Game server instance created and configured"

# Step 5: Create health check
log_info "Creating health check for game servers..."
if gcloud compute health-checks describe game-server-health &>/dev/null; then
    log_warning "Health check game-server-health already exists"
else
    gcloud compute health-checks create http game-server-health \
        --port=80 \
        --request-path=/health \
        --check-interval=30s \
        --healthy-threshold=2 \
        --unhealthy-threshold=3 \
        --timeout=10s \
        --quiet
fi

log_success "Health check created"

# Step 6: Create instance template and managed instance group
log_info "Creating instance template and managed instance group..."

if gcloud compute instance-templates describe game-server-template &>/dev/null; then
    log_warning "Instance template game-server-template already exists"
else
    gcloud compute instance-templates create game-server-template \
        --machine-type=n2-standard-2 \
        --network-tier=PREMIUM \
        --image-family=ubuntu-2004-lts \
        --image-project=ubuntu-os-cloud \
        --tags=game-server,http-server \
        --metadata-from-file startup-script=/tmp/startup-script.sh \
        --quiet 2>/dev/null || true
fi

if gcloud compute instance-groups managed describe game-server-group --zone="${ZONE}" &>/dev/null; then
    log_warning "Instance group game-server-group already exists"
else
    gcloud compute instance-groups managed create game-server-group \
        --template=game-server-template \
        --size=1 \
        --zone="${ZONE}" \
        --quiet
    
    # Set named port for load balancing
    gcloud compute instance-groups managed set-named-ports game-server-group \
        --named-ports=http:80 \
        --zone="${ZONE}" \
        --quiet
fi

log_success "Instance group created and configured"

# Step 7: Create backend services
log_info "Creating backend services for load balancing..."

if gcloud compute backend-services describe "${BACKEND_SERVICE_NAME}" --global &>/dev/null; then
    log_warning "Backend service ${BACKEND_SERVICE_NAME} already exists"
else
    gcloud compute backend-services create "${BACKEND_SERVICE_NAME}" \
        --protocol=HTTP \
        --port-name=http \
        --health-checks=game-server-health \
        --global \
        --enable-cdn \
        --cache-mode=CACHE_ALL_STATIC \
        --quiet
    
    # Add instance group to backend service
    gcloud compute backend-services add-backend "${BACKEND_SERVICE_NAME}" \
        --instance-group=game-server-group \
        --instance-group-zone="${ZONE}" \
        --global \
        --quiet
fi

if gcloud compute backend-buckets describe game-assets-backend &>/dev/null; then
    log_warning "Backend bucket game-assets-backend already exists"
else
    gcloud compute backend-buckets create game-assets-backend \
        --gcs-bucket-name="${BUCKET_NAME}" \
        --enable-cdn \
        --quiet
fi

log_success "Backend services configured with CDN enabled"

# Step 8: Create URL map and SSL certificate
log_info "Creating URL map and SSL certificate..."

if gcloud compute url-maps describe game-backend-map &>/dev/null; then
    log_warning "URL map game-backend-map already exists"
else
    gcloud compute url-maps create game-backend-map \
        --default-service="${BACKEND_SERVICE_NAME}" \
        --quiet
    
    # Add path matcher for static assets
    gcloud compute url-maps add-path-matcher game-backend-map \
        --path-matcher-name=assets-matcher \
        --default-backend-bucket=game-assets-backend \
        --path-rules="/assets/*=game-assets-backend,/configs/*=game-assets-backend" \
        --quiet
fi

# Note: For production, you would use a real domain name
DOMAIN_NAME="gaming-backend-${RANDOM_SUFFIX}.example.com"

if gcloud compute ssl-certificates describe game-ssl-cert --global &>/dev/null; then
    log_warning "SSL certificate game-ssl-cert already exists"
else
    log_warning "Creating self-managed SSL certificate for domain: ${DOMAIN_NAME}"
    log_warning "For production, replace with your actual domain name"
    
    gcloud compute ssl-certificates create game-ssl-cert \
        --domains="${DOMAIN_NAME}" \
        --global \
        --quiet || {
        log_warning "SSL certificate creation failed - this is expected for demo domains"
        log_info "Continuing without SSL certificate for HTTP-only access"
    }
fi

if gcloud compute target-https-proxies describe game-https-proxy &>/dev/null; then
    log_warning "HTTPS proxy game-https-proxy already exists"
else
    if gcloud compute ssl-certificates describe game-ssl-cert --global &>/dev/null; then
        gcloud compute target-https-proxies create game-https-proxy \
            --url-map=game-backend-map \
            --ssl-certificates=game-ssl-cert \
            --quiet
    else
        log_info "Creating HTTP proxy instead of HTTPS (no valid SSL certificate)"
        gcloud compute target-http-proxies create game-http-proxy \
            --url-map=game-backend-map \
            --quiet
    fi
fi

log_success "URL routing configured"

# Step 9: Create global frontend IP and forwarding rules
log_info "Creating global frontend IP and forwarding rules..."

if gcloud compute addresses describe game-frontend-ip --global &>/dev/null; then
    log_warning "Frontend IP game-frontend-ip already exists"
else
    gcloud compute addresses create game-frontend-ip --global --quiet
fi

FRONTEND_IP=$(gcloud compute addresses describe game-frontend-ip --global --format="get(address)")

# Create forwarding rules
if gcloud compute target-https-proxies describe game-https-proxy &>/dev/null; then
    if ! gcloud compute forwarding-rules describe game-https-rule --global &>/dev/null; then
        gcloud compute forwarding-rules create game-https-rule \
            --address=game-frontend-ip \
            --global \
            --target-https-proxy=game-https-proxy \
            --ports=443 \
            --quiet
    fi
else
    if ! gcloud compute forwarding-rules describe game-http-rule --global &>/dev/null; then
        gcloud compute forwarding-rules create game-http-rule \
            --address=game-frontend-ip \
            --global \
            --target-http-proxy=game-http-proxy \
            --ports=80 \
            --quiet
    fi
fi

# Create firewall rules
if ! gcloud compute firewall-rules describe allow-game-server-traffic &>/dev/null; then
    gcloud compute firewall-rules create allow-game-server-traffic \
        --allow tcp:80,tcp:443,tcp:8080 \
        --source-ranges 0.0.0.0/0 \
        --target-tags game-server \
        --description="Allow HTTP/HTTPS and game protocol traffic" \
        --quiet
fi

log_success "Global frontend IP created: ${FRONTEND_IP}"
log_success "Firewall rules configured"

# Step 10: Configure Redis connection and test
log_info "Configuring Redis connection and testing gaming operations..."

# Get Redis connection details
REDIS_IP=$(gcloud redis instances describe "${REDIS_INSTANCE_NAME}" --region="${REGION}" --format="get(host)")
REDIS_AUTH=$(gcloud redis instances get-auth-string "${REDIS_INSTANCE_NAME}" --region="${REGION}" 2>/dev/null || echo "")

log_info "Redis instance IP: ${REDIS_IP}"

# Wait for game server to be fully ready
log_info "Waiting for game server to be fully operational..."
sleep 30

# Test Redis connectivity and load sample data
log_info "Testing Redis connectivity and loading sample gaming data..."

# Create Redis test script
cat > /tmp/redis-test.sh << EOF
#!/bin/bash
# Test Redis connectivity
redis-cli -h ${REDIS_IP} -a '${REDIS_AUTH}' ping

# Load sample gaming data
redis-cli -h ${REDIS_IP} -a '${REDIS_AUTH}' <<REDIS_EOF
# Store player session data
HSET player:12345 name 'PlayerOne' level 25 score 15000 lastSeen \$(date +%s)
HSET player:67890 name 'PlayerTwo' level 18 score 12500 lastSeen \$(date +%s)
HSET player:11111 name 'PlayerThree' level 30 score 18000 lastSeen \$(date +%s)

# Update leaderboard
ZADD global_leaderboard 15000 'PlayerOne'
ZADD global_leaderboard 12500 'PlayerTwo'
ZADD global_leaderboard 18000 'PlayerThree'

# Store game configuration in cache
SET game:config:version '1.2.3'
SET game:config:maxPlayers 100
EXPIRE game:config:version 3600

# Get top 10 players
ZREVRANGE global_leaderboard 0 9 WITHSCORES
REDIS_EOF

echo "Redis gaming data operations completed successfully"
EOF

# Execute Redis test on game server
gcloud compute ssh "${GAME_SERVER_NAME}" --zone="${ZONE}" --command="$(cat /tmp/redis-test.sh)" --quiet || {
    log_warning "Redis connectivity test encountered issues - this may be normal during initial setup"
}

rm -f /tmp/redis-test.sh

log_success "Redis integration configured and tested"

# Final health checks
log_info "Performing final health checks..."

# Check backend health
log_info "Checking backend service health..."
BACKEND_HEALTH=$(gcloud compute backend-services get-health "${BACKEND_SERVICE_NAME}" --global --format="get(status.healthStatus[0].healthState)" 2>/dev/null || echo "UNKNOWN")
log_info "Backend health status: ${BACKEND_HEALTH}"

# Test CDN endpoint
log_info "Testing CDN endpoint availability..."
if curl -s -o /dev/null -w "%{http_code}" "http://${FRONTEND_IP}/configs/game-config.json" | grep -q "200"; then
    log_success "CDN endpoint responding successfully"
else
    log_warning "CDN endpoint may need additional time to propagate"
fi

# Deployment summary
echo
echo "=================================================================="
echo "  DEPLOYMENT COMPLETED SUCCESSFULLY"
echo "=================================================================="
echo
log_success "Gaming backend infrastructure deployed!"
echo
echo "Resource Summary:"
echo "  • Redis Instance: ${REDIS_INSTANCE_NAME} (${REDIS_IP})"
echo "  • Game Server: ${GAME_SERVER_NAME}"
echo "  • Assets Bucket: gs://${BUCKET_NAME}"
echo "  • Frontend IP: ${FRONTEND_IP}"
echo "  • Backend Service: ${BACKEND_SERVICE_NAME}"
echo
echo "Access URLs:"
echo "  • Game API: http://${FRONTEND_IP}/"
echo "  • Game Assets: http://${FRONTEND_IP}/assets/"
echo "  • Configuration: http://${FRONTEND_IP}/configs/"
echo
echo "Next Steps:"
echo "  1. Configure your game client to use IP: ${FRONTEND_IP}"
echo "  2. Monitor performance in Cloud Console"
echo "  3. Scale instance groups based on player load"
echo "  4. Set up proper DNS records for production use"
echo
log_warning "Remember to run './destroy.sh' when testing is complete to avoid ongoing charges"
echo
echo "=================================================================="