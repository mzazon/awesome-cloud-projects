#!/bin/bash

# Edge Caching Performance with Cloud CDN and Memorystore - Deployment Script
# This script deploys the complete edge caching infrastructure on Google Cloud Platform

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
    exit 1
}

# Check if dry-run mode is enabled
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warn "Running in dry-run mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    log "$description"
    eval "$cmd"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "Google Cloud Storage utility (gsutil) is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
    fi
    
    # Check if project is set
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$PROJECT_ID" ]]; then
        error "No project is set. Please run 'gcloud config set project PROJECT_ID' first."
    fi
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "$PROJECT_ID" &>/dev/null; then
        warn "Unable to verify billing status. Ensure billing is enabled for project: $PROJECT_ID"
    fi
    
    success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Use existing project or create new one
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            export PROJECT_ID="intelligent-cdn-$(date +%s)"
            warn "No project set, would create: $PROJECT_ID"
        fi
    fi
    
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names with unique suffix
    export REDIS_INSTANCE_NAME="intelligent-cache-${RANDOM_SUFFIX}"
    export BUCKET_NAME="cdn-origin-content-${RANDOM_SUFFIX}"
    export BACKEND_SERVICE_NAME="cdn-backend-${RANDOM_SUFFIX}"
    export URL_MAP_NAME="cdn-url-map-${RANDOM_SUFFIX}"
    export TARGET_PROXY_NAME="cdn-target-proxy-${RANDOM_SUFFIX}"
    export FORWARDING_RULE_NAME="cdn-forwarding-rule-${RANDOM_SUFFIX}"
    export HEALTH_CHECK_NAME="cdn-health-check-${RANDOM_SUFFIX}"
    export NETWORK_NAME="cdn-network-${RANDOM_SUFFIX}"
    export SUBNET_NAME="cdn-subnet-${RANDOM_SUFFIX}"
    export IP_ADDRESS_NAME="cdn-ip-address-${RANDOM_SUFFIX}"
    
    # Create deployment log file
    export DEPLOYMENT_LOG="deployment-$(date +%Y%m%d-%H%M%S).log"
    
    success "Environment variables configured"
    log "Project ID: $PROJECT_ID"
    log "Region: $REGION"
    log "Zone: $ZONE"
    log "Resource suffix: $RANDOM_SUFFIX"
    log "Deployment log: $DEPLOYMENT_LOG"
}

# Configure project settings
configure_project() {
    log "Configuring project settings..."
    
    execute_command "gcloud config set project ${PROJECT_ID}" "Setting project"
    execute_command "gcloud config set compute/region ${REGION}" "Setting default region"
    execute_command "gcloud config set compute/zone ${ZONE}" "Setting default zone"
    
    success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "redis.googleapis.com"
        "storage.googleapis.com"
        "dns.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_command "gcloud services enable ${api}" "Enabling ${api}"
        sleep 2  # Brief pause to avoid rate limits
    done
    
    success "All required APIs enabled"
}

# Create VPC network and subnet
create_network() {
    log "Creating VPC network and subnet..."
    
    execute_command "gcloud compute networks create ${NETWORK_NAME} --subnet-mode regional" \
        "Creating VPC network: ${NETWORK_NAME}"
    
    execute_command "gcloud compute networks subnets create ${SUBNET_NAME} \
        --network ${NETWORK_NAME} \
        --range 10.0.0.0/24 \
        --region ${REGION}" \
        "Creating subnet: ${SUBNET_NAME}"
    
    success "VPC network and subnet created"
}

# Deploy Redis instance
deploy_redis() {
    log "Deploying Memorystore Redis instance..."
    
    execute_command "gcloud redis instances create ${REDIS_INSTANCE_NAME} \
        --size 5 \
        --region ${REGION} \
        --network ${NETWORK_NAME} \
        --redis-version redis_6_x \
        --tier standard \
        --enable-auth \
        --redis-config maxmemory-policy=allkeys-lru" \
        "Creating Redis instance: ${REDIS_INSTANCE_NAME}"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for Redis instance to be ready..."
        local max_attempts=30
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            local state=$(gcloud redis instances describe ${REDIS_INSTANCE_NAME} \
                --region ${REGION} \
                --format="value(state)" 2>/dev/null || echo "UNKNOWN")
            
            if [[ "$state" == "READY" ]]; then
                break
            fi
            
            log "Redis instance state: $state (attempt $attempt/$max_attempts)"
            sleep 30
            ((attempt++))
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            error "Redis instance failed to become ready within expected time"
        fi
        
        # Get Redis connection details
        export REDIS_HOST=$(gcloud redis instances describe ${REDIS_INSTANCE_NAME} \
            --region ${REGION} \
            --format="value(host)")
        export REDIS_PORT=$(gcloud redis instances describe ${REDIS_INSTANCE_NAME} \
            --region ${REGION} \
            --format="value(port)")
        
        success "Redis instance created at ${REDIS_HOST}:${REDIS_PORT}"
    else
        success "Redis instance would be created: ${REDIS_INSTANCE_NAME}"
    fi
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket for origin content..."
    
    execute_command "gsutil mb -p ${PROJECT_ID} -c STANDARD -l US gs://${BUCKET_NAME}" \
        "Creating storage bucket: ${BUCKET_NAME}"
    
    execute_command "gsutil versioning set on gs://${BUCKET_NAME}" \
        "Enabling versioning on bucket"
    
    # Create and upload sample content
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Creating sample content..."
        
        cat > index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Edge Caching Performance Test</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .timestamp { color: #666; font-size: 0.9em; }
        .cache-info { background: #f0f0f0; padding: 20px; border-radius: 5px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Edge Caching Performance Test</h1>
        <div class="cache-info">
            <h2>Cache Status</h2>
            <p>This content is served through Cloud CDN with Memorystore Redis caching.</p>
            <p class="timestamp">Generated: $(date)</p>
        </div>
        <p>This page demonstrates intelligent edge caching with geographic distribution.</p>
    </div>
</body>
</html>
EOF
        
        cat > api-response.json << EOF
{
    "message": "Edge caching API response",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "cached": true,
    "cache_layer": "memorystore_redis",
    "edge_location": "auto-detected",
    "performance": {
        "cache_hit_ratio": "95%",
        "avg_response_time": "50ms",
        "global_availability": "99.9%"
    }
}
EOF
        
        gsutil cp index.html gs://${BUCKET_NAME}/
        gsutil cp api-response.json gs://${BUCKET_NAME}/
        
        # Clean up local files
        rm -f index.html api-response.json
    fi
    
    execute_command "gsutil iam ch allUsers:objectViewer gs://${BUCKET_NAME}" \
        "Making bucket publicly readable"
    
    success "Origin content bucket created and populated"
}

# Create health check
create_health_check() {
    log "Creating health check for backend services..."
    
    execute_command "gcloud compute health-checks create http ${HEALTH_CHECK_NAME} \
        --port 80 \
        --request-path / \
        --check-interval 30s \
        --timeout 10s \
        --healthy-threshold 2 \
        --unhealthy-threshold 3" \
        "Creating health check: ${HEALTH_CHECK_NAME}"
    
    success "Health check configured"
}

# Create backend service
create_backend_service() {
    log "Creating backend service with CDN enabled..."
    
    execute_command "gcloud compute backend-services create ${BACKEND_SERVICE_NAME} \
        --protocol HTTP \
        --health-checks ${HEALTH_CHECK_NAME} \
        --enable-cdn \
        --cache-mode CACHE_ALL_STATIC \
        --default-ttl 3600 \
        --max-ttl 86400 \
        --client-ttl 3600 \
        --global" \
        "Creating backend service: ${BACKEND_SERVICE_NAME}"
    
    execute_command "gcloud compute backend-services add-backend ${BACKEND_SERVICE_NAME} \
        --backend-bucket ${BUCKET_NAME} \
        --global" \
        "Adding Cloud Storage bucket as backend"
    
    success "Backend service created with CDN enabled"
}

# Create URL map
create_url_map() {
    log "Creating URL map for traffic routing..."
    
    execute_command "gcloud compute url-maps create ${URL_MAP_NAME} \
        --default-backend-service ${BACKEND_SERVICE_NAME} \
        --global" \
        "Creating URL map: ${URL_MAP_NAME}"
    
    success "URL map configured with intelligent routing"
}

# Create static IP address
create_static_ip() {
    log "Creating static IP address..."
    
    execute_command "gcloud compute addresses create ${IP_ADDRESS_NAME} --global" \
        "Creating static IP address: ${IP_ADDRESS_NAME}"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export CDN_IP=$(gcloud compute addresses describe ${IP_ADDRESS_NAME} \
            --global --format="value(address)")
        success "Static IP address created: ${CDN_IP}"
    else
        success "Static IP address would be created: ${IP_ADDRESS_NAME}"
    fi
}

# Create target HTTP proxy (using HTTP for simplicity in this example)
create_target_proxy() {
    log "Creating target HTTP proxy..."
    
    execute_command "gcloud compute target-http-proxies create ${TARGET_PROXY_NAME} \
        --url-map ${URL_MAP_NAME} \
        --global" \
        "Creating target HTTP proxy: ${TARGET_PROXY_NAME}"
    
    success "Target HTTP proxy created"
}

# Create global forwarding rule
create_forwarding_rule() {
    log "Creating global forwarding rule..."
    
    execute_command "gcloud compute forwarding-rules create ${FORWARDING_RULE_NAME} \
        --address ${IP_ADDRESS_NAME} \
        --target-http-proxy ${TARGET_PROXY_NAME} \
        --ports 80 \
        --global" \
        "Creating forwarding rule: ${FORWARDING_RULE_NAME}"
    
    success "Global forwarding rule created"
}

# Create cache management scripts
create_cache_management() {
    log "Creating cache management scripts..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > cache_invalidation.py << 'EOF'
#!/usr/bin/env python3
"""
Cache Invalidation Script for Edge Caching Performance Solution
Provides intelligent cache invalidation for Cloud CDN and Memorystore Redis
"""

import os
import sys
import json
import time
import logging
from datetime import datetime
from typing import List, Dict, Optional

try:
    import redis
    from google.cloud import storage
    from google.cloud import logging as cloud_logging
except ImportError:
    print("Required packages not installed. Install with:")
    print("pip install redis google-cloud-storage google-cloud-logging")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class CacheInvalidator:
    def __init__(self, redis_host: str, redis_port: int, redis_auth: Optional[str] = None):
        """Initialize cache invalidator with Redis connection."""
        self.redis_host = redis_host
        self.redis_port = redis_port
        self.redis_auth = redis_auth
        self.redis_client = None
        self.storage_client = storage.Client()
        
    def connect_redis(self) -> bool:
        """Connect to Redis instance."""
        try:
            self.redis_client = redis.Redis(
                host=self.redis_host,
                port=self.redis_port,
                password=self.redis_auth,
                decode_responses=True
            )
            # Test connection
            self.redis_client.ping()
            logger.info(f"Connected to Redis at {self.redis_host}:{self.redis_port}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {e}")
            return False
    
    def invalidate_cache_key(self, cache_key: str) -> bool:
        """Invalidate specific cache key."""
        try:
            if self.redis_client.exists(cache_key):
                self.redis_client.delete(cache_key)
                logger.info(f"Invalidated cache key: {cache_key}")
                return True
            else:
                logger.info(f"Cache key not found: {cache_key}")
                return False
        except Exception as e:
            logger.error(f"Cache invalidation failed for {cache_key}: {e}")
            return False
    
    def invalidate_pattern(self, pattern: str) -> int:
        """Invalidate all keys matching pattern."""
        try:
            keys = self.redis_client.keys(pattern)
            if keys:
                deleted = self.redis_client.delete(*keys)
                logger.info(f"Invalidated {deleted} keys matching pattern: {pattern}")
                return deleted
            else:
                logger.info(f"No keys found matching pattern: {pattern}")
                return 0
        except Exception as e:
            logger.error(f"Pattern invalidation failed for {pattern}: {e}")
            return 0
    
    def invalidate_all_cache(self) -> bool:
        """Invalidate all cache entries (use with caution)."""
        try:
            self.redis_client.flushall()
            logger.info("Invalidated all cache entries")
            return True
        except Exception as e:
            logger.error(f"Failed to invalidate all cache: {e}")
            return False
    
    def get_cache_stats(self) -> Dict:
        """Get cache statistics."""
        try:
            info = self.redis_client.info()
            stats = {
                'total_keys': info.get('db0', {}).get('keys', 0),
                'memory_used': info.get('used_memory_human', 'N/A'),
                'hit_ratio': info.get('keyspace_hits', 0) / 
                           (info.get('keyspace_hits', 0) + info.get('keyspace_misses', 1)),
                'connected_clients': info.get('connected_clients', 0),
                'uptime': info.get('uptime_in_seconds', 0)
            }
            return stats
        except Exception as e:
            logger.error(f"Failed to get cache stats: {e}")
            return {}

def main():
    """Main function for cache invalidation."""
    # Get Redis connection details from environment
    redis_host = os.getenv('REDIS_HOST', 'localhost')
    redis_port = int(os.getenv('REDIS_PORT', 6379))
    redis_auth = os.getenv('REDIS_AUTH')
    
    if not redis_host or redis_host == 'localhost':
        logger.error("REDIS_HOST environment variable not set")
        sys.exit(1)
    
    # Initialize cache invalidator
    invalidator = CacheInvalidator(redis_host, redis_port, redis_auth)
    
    if not invalidator.connect_redis():
        logger.error("Failed to connect to Redis")
        sys.exit(1)
    
    # Get cache statistics
    stats = invalidator.get_cache_stats()
    logger.info(f"Cache stats: {json.dumps(stats, indent=2)}")
    
    # Default invalidation patterns
    invalidation_patterns = [
        'static:*',      # Static content
        'api:*',         # API responses
        'dynamic:*',     # Dynamic content
        'user:*',        # User-specific content
        'session:*'      # Session data
    ]
    
    total_invalidated = 0
    for pattern in invalidation_patterns:
        count = invalidator.invalidate_pattern(pattern)
        total_invalidated += count
    
    logger.info(f"Cache invalidation completed. Total keys invalidated: {total_invalidated}")
    
    # Get updated stats
    updated_stats = invalidator.get_cache_stats()
    logger.info(f"Updated cache stats: {json.dumps(updated_stats, indent=2)}")

if __name__ == "__main__":
    main()
EOF

        cat > monitoring_dashboard.json << 'EOF'
{
  "displayName": "CDN Cache Performance Dashboard",
  "description": "Monitoring dashboard for Edge Caching Performance solution",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Cache Hit Ratio",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_backend_service\"",
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
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Response Latency",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_backend_service\"",
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
        "width": 12,
        "height": 4,
        "widget": {
          "title": "Request Volume",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_backend_service\"",
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

        chmod +x cache_invalidation.py
        success "Cache management scripts created"
    else
        success "Cache management scripts would be created"
    fi
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > deployment_info.json << EOF
{
    "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "project_id": "${PROJECT_ID}",
    "region": "${REGION}",
    "zone": "${ZONE}",
    "resources": {
        "redis_instance": "${REDIS_INSTANCE_NAME}",
        "storage_bucket": "${BUCKET_NAME}",
        "backend_service": "${BACKEND_SERVICE_NAME}",
        "url_map": "${URL_MAP_NAME}",
        "target_proxy": "${TARGET_PROXY_NAME}",
        "forwarding_rule": "${FORWARDING_RULE_NAME}",
        "health_check": "${HEALTH_CHECK_NAME}",
        "network": "${NETWORK_NAME}",
        "subnet": "${SUBNET_NAME}",
        "ip_address": "${IP_ADDRESS_NAME}"
    },
    "endpoints": {
        "cdn_ip": "${CDN_IP:-not-available}",
        "redis_host": "${REDIS_HOST:-not-available}",
        "redis_port": "${REDIS_PORT:-not-available}"
    }
}
EOF
        
        success "Deployment information saved to deployment_info.json"
    fi
}

# Main deployment function
main() {
    log "Starting Edge Caching Performance deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Configure project
    configure_project
    
    # Enable APIs
    enable_apis
    
    # Create infrastructure
    create_network
    deploy_redis
    create_storage_bucket
    create_health_check
    create_backend_service
    create_url_map
    create_static_ip
    create_target_proxy
    create_forwarding_rule
    
    # Create management scripts
    create_cache_management
    
    # Save deployment info
    save_deployment_info
    
    success "Deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "🎉 Edge Caching Performance Solution Deployed!"
        echo "================================================"
        echo "CDN Endpoint: http://${CDN_IP:-pending}"
        echo "Redis Host: ${REDIS_HOST:-pending}"
        echo "Redis Port: ${REDIS_PORT:-pending}"
        echo "Storage Bucket: gs://${BUCKET_NAME}"
        echo ""
        echo "Next Steps:"
        echo "1. Wait a few minutes for DNS propagation"
        echo "2. Test the endpoint: curl http://${CDN_IP:-pending}"
        echo "3. Monitor performance in Cloud Console"
        echo "4. Use cache_invalidation.py for cache management"
        echo ""
        echo "Deployment details saved to: deployment_info.json"
    else
        echo ""
        echo "🎯 Dry-run completed successfully!"
        echo "================================"
        echo "All resources would be created as specified."
        echo "Run without --dry-run to actually deploy."
    fi
}

# Handle script interruption
cleanup_on_exit() {
    if [[ "$DRY_RUN" == "false" ]]; then
        warn "Deployment interrupted. You may need to run destroy.sh to clean up partially created resources."
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"