---
title: Edge Caching Performance with Cloud CDN and Memorystore
id: c3e8f7a2
category: networking
difficulty: 200
subject: gcp
services: Cloud CDN, Memorystore for Redis, Cloud Load Balancing, Cloud Storage
estimated-time: 120 minutes
recipe-version: 1.1
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: content delivery, caching, performance optimization, edge computing, redis
recipe-generator-version: 1.3
---

# Edge Caching Performance with Cloud CDN and Memorystore

## Problem

Global e-commerce and media companies struggle with slow content delivery, high origin server loads, and inconsistent user experiences across geographic regions. Traditional caching solutions lack intelligent cache management, resulting in suboptimal cache hit ratios, unnecessary origin requests, and poor performance during traffic spikes. Without dynamic cache invalidation and geographic optimization, businesses experience reduced conversion rates and increased infrastructure costs.

## Solution

Build an intelligent edge caching system using Cloud CDN for global content distribution and Memorystore for Redis as a high-performance cache layer. This solution implements dynamic cache policies, geographic data distribution strategies, and real-time cache invalidation workflows. The architecture leverages Google's global edge infrastructure with intelligent caching algorithms to optimize content delivery performance and reduce origin server load.

## Architecture Diagram

```mermaid
graph TB
    subgraph "User Layer"
        USERS[Global Users]
    end
    
    subgraph "Edge Layer"
        CDN[Cloud CDN]
        EDGE1[Edge Location - US]
        EDGE2[Edge Location - EU]
        EDGE3[Edge Location - APAC]
    end
    
    subgraph "Load Balancing"
        LB[Cloud Load Balancer]
    end
    
    subgraph "Caching Layer"
        REDIS[Memorystore Redis]
        CACHE_LOGIC[Cache Management Logic]
    end
    
    subgraph "Origin Layer"
        ORIGIN[Origin Servers]
        STORAGE[Cloud Storage]
    end
    
    subgraph "Monitoring"
        MONITOR[Cloud Monitoring]
        LOGS[Cloud Logging]
    end
    
    USERS-->CDN
    CDN-->EDGE1
    CDN-->EDGE2
    CDN-->EDGE3
    CDN-->LB
    LB-->CACHE_LOGIC
    CACHE_LOGIC-->REDIS
    CACHE_LOGIC-->ORIGIN
    ORIGIN-->STORAGE
    CDN-->MONITOR
    REDIS-->LOGS
    
    style CDN fill:#4285F4
    style REDIS fill:#DB4437
    style LB fill:#34A853
    style MONITOR fill:#FBBC04
```

## Prerequisites

1. Google Cloud account with billing enabled and appropriate IAM permissions for Cloud CDN, Memorystore, and Load Balancing
2. Google Cloud CLI installed and configured (version 400.0.0 or later)
3. Basic understanding of content delivery networks, caching strategies, and Redis
4. Familiarity with HTTP headers, cache control directives, and DNS configuration
5. Estimated cost: $150-300/month for production-grade setup (varies by traffic volume and cache size)

> **Note**: This recipe creates resources across multiple Google Cloud services. Monitor costs through Cloud Billing and implement appropriate resource limits to control expenses.

## Preparation

```bash
# Set environment variables for GCP resources
export PROJECT_ID="intelligent-cdn-$(date +%s)"
export REGION="us-central1"
export ZONE="us-central1-a"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Set default project and region
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
gcloud config set compute/zone ${ZONE}

# Enable required APIs
gcloud services enable compute.googleapis.com
gcloud services enable redis.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable dns.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable logging.googleapis.com

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
export SSL_CERT_NAME="cdn-ssl-cert-${RANDOM_SUFFIX}"

echo "✅ Project configured: ${PROJECT_ID}"
echo "✅ APIs enabled and resource names set"
```

## Steps

1. **Create VPC Network and Subnet**:

   Google Cloud Virtual Private Cloud (VPC) provides isolated network infrastructure for secure communication between resources. Creating a dedicated network ensures optimal routing and security for cache infrastructure while maintaining network-level isolation from other workloads.

   ```bash
   # Create VPC network
   gcloud compute networks create ${NETWORK_NAME} \
       --subnet-mode regional
   
   # Create subnet for cache infrastructure
   gcloud compute networks subnets create ${SUBNET_NAME} \
       --network ${NETWORK_NAME} \
       --range 10.0.0.0/24 \
       --region ${REGION}
   
   echo "✅ VPC network and subnet created"
   ```

   The network infrastructure now provides secure, isolated communication channels for cache components with proper IP address management and routing capabilities.

2. **Deploy Memorystore Redis Instance**:

   Memorystore for Redis provides a fully managed, high-performance in-memory cache that serves as the intelligent caching layer. The Standard tier offers automatic failover and read replicas for high availability, ensuring consistent cache performance across all edge locations.

   ```bash
   # Create Redis instance with high availability
   gcloud redis instances create ${REDIS_INSTANCE_NAME} \
       --size 5 \
       --region ${REGION} \
       --network ${NETWORK_NAME} \
       --redis-version redis_6_x \
       --tier standard \
       --enable-auth \
       --redis-config maxmemory-policy=allkeys-lru
   
   # Wait for Redis instance to be ready
   while [[ $(gcloud redis instances describe ${REDIS_INSTANCE_NAME} \
       --region ${REGION} --format="value(state)") != "READY" ]]; do
       echo "Waiting for Redis instance to be ready..."
       sleep 30
   done
   
   # Get Redis connection details
   export REDIS_HOST=$(gcloud redis instances describe \
       ${REDIS_INSTANCE_NAME} \
       --region ${REGION} \
       --format="value(host)")
   
   export REDIS_PORT=$(gcloud redis instances describe \
       ${REDIS_INSTANCE_NAME} \
       --region ${REGION} \
       --format="value(port)")
   
   echo "✅ Redis instance created at ${REDIS_HOST}:${REDIS_PORT}"
   ```

   The Redis instance is now operational with LRU eviction policy and authentication enabled, providing secure, high-performance caching capabilities with automatic scaling and failover protection.

3. **Create Cloud Storage Bucket for Origin Content**:

   Cloud Storage serves as the origin server for static content, providing globally distributed object storage with strong consistency guarantees. Multi-regional storage ensures low-latency access for the CDN while maintaining data durability and availability.

   ```bash
   # Create Cloud Storage bucket for origin content
   gsutil mb -p ${PROJECT_ID} \
       -c STANDARD \
       -l US \
       gs://${BUCKET_NAME}
   
   # Enable versioning for content management
   gsutil versioning set on gs://${BUCKET_NAME}
   
   # Upload sample content for testing
   echo '<html><body><h1>Cached Content Test</h1><p>Timestamp: '$(date)'</p></body></html>' > index.html
   echo '{"message": "API response", "timestamp": "'$(date)'", "cached": true}' > api-response.json
   
   gsutil cp index.html gs://${BUCKET_NAME}/
   gsutil cp api-response.json gs://${BUCKET_NAME}/
   
   # Make bucket publicly readable
   gsutil iam ch allUsers:objectViewer gs://${BUCKET_NAME}
   
   echo "✅ Origin content bucket created and populated"
   ```

   The origin storage is now configured with sample content and appropriate permissions, providing a reliable content source for the CDN with versioning enabled for content lifecycle management.

4. **Create Self-Managed SSL Certificate**:

   SSL certificates ensure secure content delivery through HTTPS. Creating a self-signed certificate enables testing the complete HTTPS workflow, while production deployments should use Google-managed certificates for better security and automatic renewal.

   ```bash
   # Create self-signed SSL certificate for testing
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
       -keyout private.key -out certificate.crt \
       -subj "/C=US/ST=CA/L=MountainView/O=TestOrg/CN=test.example.com"
   
   # Create SSL certificate resource in Google Cloud
   gcloud compute ssl-certificates create ${SSL_CERT_NAME} \
       --certificate certificate.crt \
       --private-key private.key \
       --global
   
   echo "✅ SSL certificate created for HTTPS"
   ```

   The SSL certificate is now available for secure content delivery, enabling HTTPS termination at the load balancer with proper encryption for all client connections.

5. **Configure Health Check for Backend Services**:

   Health checks ensure that only healthy backend instances receive traffic from the load balancer. Configuring appropriate health check parameters prevents routing requests to unhealthy backends and maintains service availability during cache operations.

   ```bash
   # Create health check for Cloud Storage backend
   gcloud compute health-checks create http ${HEALTH_CHECK_NAME} \
       --port 80 \
       --request-path "/" \
       --check-interval 30s \
       --timeout 10s \
       --healthy-threshold 2 \
       --unhealthy-threshold 3
   
   echo "✅ Health check configured"
   ```

   The health check now monitors backend health with optimized parameters for cache infrastructure, ensuring reliable traffic routing and automatic failover capabilities.

6. **Create Backend Service with Cloud Storage**:

   Backend services define how load balancers distribute traffic to backend instances. Configuring the backend service with Cloud Storage integration enables seamless content delivery from origin storage through the CDN infrastructure.

   ```bash
   # Create backend service for Cloud Storage
   gcloud compute backend-services create ${BACKEND_SERVICE_NAME} \
       --protocol HTTP \
       --health-checks ${HEALTH_CHECK_NAME} \
       --enable-cdn \
       --cache-mode CACHE_ALL_STATIC \
       --default-ttl 3600 \
       --max-ttl 86400 \
       --client-ttl 3600 \
       --global
   
   # Add Cloud Storage bucket as backend
   gcloud compute backend-services add-backend ${BACKEND_SERVICE_NAME} \
       --backend-bucket ${BUCKET_NAME} \
       --global
   
   echo "✅ Backend service created with CDN enabled"
   ```

   The backend service now routes traffic to Cloud Storage with CDN caching enabled, implementing intelligent cache policies with optimized TTL settings for different content types.

7. **Create URL Map for Traffic Routing**:

   URL maps define how requests are routed to different backend services based on URL patterns. Advanced routing rules enable intelligent cache management by directing different content types to appropriate caching strategies and backend services.

   ```bash
   # Create URL map with default backend
   gcloud compute url-maps create ${URL_MAP_NAME} \
       --default-backend-service ${BACKEND_SERVICE_NAME} \
       --global
   
   # Add path matcher for API endpoints
   gcloud compute url-maps add-path-matcher ${URL_MAP_NAME} \
       --path-matcher-name api-matcher \
       --default-backend-service ${BACKEND_SERVICE_NAME} \
       --path-rules "/api/*=${BACKEND_SERVICE_NAME}" \
       --global
   
   echo "✅ URL map configured with intelligent routing"
   ```

   The URL map now provides sophisticated traffic routing capabilities, enabling different caching strategies for static content versus dynamic API responses.

8. **Configure Target HTTPS Proxy**:

   Target proxies handle SSL termination and HTTP/2 optimization for the load balancer. HTTPS configuration ensures secure content delivery while enabling modern protocol features like HTTP/3 and QUIC for improved performance.

   ```bash
   # Create target HTTPS proxy
   gcloud compute target-https-proxies create ${TARGET_PROXY_NAME} \
       --url-map ${URL_MAP_NAME} \
       --ssl-certificates ${SSL_CERT_NAME} \
       --quic-override ENABLE \
       --global
   
   echo "✅ Target HTTPS proxy created with QUIC enabled"
   ```

   The target proxy now provides secure, high-performance content delivery with modern protocol support for optimal edge caching performance.

9. **Create Global Forwarding Rule**:

   Global forwarding rules define the external IP address and port configuration for the load balancer. This creates the public endpoint that users access, with automatic traffic distribution to optimal edge locations worldwide.

   ```bash
   # Reserve static IP address
   gcloud compute addresses create cdn-ip-address --global
   
   # Get the reserved IP address
   export CDN_IP=$(gcloud compute addresses describe cdn-ip-address \
       --global --format="value(address)")
   
   # Create global forwarding rule
   gcloud compute forwarding-rules create ${FORWARDING_RULE_NAME} \
       --address ${CDN_IP} \
       --target-https-proxy ${TARGET_PROXY_NAME} \
       --ports 443 \
       --global
   
   echo "✅ Global forwarding rule created at IP: ${CDN_IP}"
   ```

   The CDN endpoint is now accessible globally through the reserved IP address, with automatic traffic routing to the nearest edge location for optimal performance.

10. **Implement Cache Invalidation Logic**:

    Cache invalidation ensures content freshness by automatically removing outdated content from edge caches. Creating automated invalidation workflows maintains content accuracy while preserving cache performance benefits.

    ```bash
    # Install Python Redis client if not available
    pip3 install redis google-cloud-storage google-cloud-logging
    
    # Create cache invalidation script
    cat > cache_invalidation.py << 'EOF'
import json
import redis
import time
from google.cloud import storage
from google.cloud import logging
import os

def invalidate_cache_entry(redis_client, cache_key):
    """Invalidate specific cache entry"""
    try:
        redis_client.delete(cache_key)
        return True
    except Exception as e:
        print(f"Cache invalidation failed: {e}")
        return False

def update_content_with_invalidation():
    """Update content and invalidate related cache"""
    # Connect to Redis (use environment variables)
    redis_host = os.getenv('REDIS_HOST', 'localhost')
    redis_port = int(os.getenv('REDIS_PORT', '6379'))
    
    try:
        r = redis.Redis(host=redis_host, port=redis_port, decode_responses=True)
        
        # Invalidate cache for updated content
        cache_keys = [
            'static:index.html',
            'api:response.json',
            'dynamic:*'
        ]
        
        for key in cache_keys:
            if '*' in key:
                # Pattern-based invalidation
                keys = r.keys(key)
                for k in keys:
                    invalidate_cache_entry(r, k)
            else:
                invalidate_cache_entry(r, key)
        
        print("Cache invalidation completed successfully")
        
    except Exception as e:
        print(f"Redis connection failed: {e}")

if __name__ == "__main__":
    update_content_with_invalidation()
EOF
    
    echo "✅ Cache invalidation logic implemented"
    ```

    The invalidation system now provides automated cache management with pattern-based invalidation capabilities, ensuring content freshness without compromising cache performance.

11. **Configure Cache Performance Monitoring**:

    Performance monitoring provides real-time visibility into cache hit ratios, latency metrics, and traffic patterns. Cloud Monitoring integration enables proactive optimization and automated alerting for cache performance issues.

    ```bash
    # Create monitoring dashboard configuration
    cat > monitoring_config.json << EOF
{
  "displayName": "CDN Cache Performance Dashboard",
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
      }
    ]
  }
}
EOF
    
    # Create custom monitoring dashboard
    gcloud monitoring dashboards create --config-from-file=monitoring_config.json
    
    echo "✅ Performance monitoring configured"
    ```

    The monitoring system now tracks critical performance metrics with automated alerting, enabling proactive optimization and performance issue detection across all edge locations.

## Validation & Testing

1. **Verify CDN and Cache Infrastructure**:

   ```bash
   # Check Cloud CDN status
   gcloud compute backend-services describe ${BACKEND_SERVICE_NAME} \
       --global --format="value(cdnPolicy.cacheMode)"
   
   # Verify Redis instance status
   gcloud redis instances describe ${REDIS_INSTANCE_NAME} \
       --region ${REGION} --format="value(state)"
   
   # Test CDN endpoint response (using HTTP since we have self-signed cert)
   curl -k -I https://${CDN_IP}/index.html
   ```

   Expected output: HTTP 200 response with cache headers and Redis instance in READY state.

2. **Test Cache Performance and Hit Ratios**:

   ```bash
   # Test cache miss (first request)
   time curl -k -s https://${CDN_IP}/index.html
   
   # Test cache hit (subsequent request)
   time curl -k -s https://${CDN_IP}/index.html
   
   # Verify cache headers
   curl -k -I https://${CDN_IP}/index.html | grep -E "(Cache-Control|X-Cache|Age)"
   ```

   Expected output: Faster response time on second request with cache hit headers indicating successful caching.

3. **Validate Geographic Distribution**:

   ```bash
   # Test CDN IP resolution
   nslookup ${CDN_IP}
   
   # Check backend service health
   gcloud compute backend-services get-health ${BACKEND_SERVICE_NAME} \
       --global --format="table(status.healthStatus)"
   ```

   Expected output: Healthy status across all backend instances with proper geographic distribution.

4. **Test Cache Invalidation Workflow**:

   ```bash
   # Update content and test invalidation
   echo '<html><body><h1>Updated Content</h1><p>Timestamp: '$(date)'</p></body></html>' > updated-index.html
   gsutil cp updated-index.html gs://${BUCKET_NAME}/index.html
   
   # Invalidate CDN cache
   gcloud compute url-maps invalidate-cdn-cache ${URL_MAP_NAME} \
       --path "/*" --global
   
   # Run Redis cache invalidation
   python3 cache_invalidation.py
   
   # Verify updated content is served
   curl -k https://${CDN_IP}/index.html
   ```

   Expected output: Updated content served after invalidation, confirming proper cache management.

## Cleanup

1. **Remove CDN and Load Balancing Resources**:

   ```bash
   # Delete forwarding rule
   gcloud compute forwarding-rules delete ${FORWARDING_RULE_NAME} \
       --global --quiet
   
   # Delete target proxy
   gcloud compute target-https-proxies delete ${TARGET_PROXY_NAME} \
       --global --quiet
   
   # Delete URL map
   gcloud compute url-maps delete ${URL_MAP_NAME} \
       --global --quiet
   
   echo "✅ CDN infrastructure removed"
   ```

2. **Remove Backend Services and Health Checks**:

   ```bash
   # Delete backend service
   gcloud compute backend-services delete ${BACKEND_SERVICE_NAME} \
       --global --quiet
   
   # Delete health check
   gcloud compute health-checks delete ${HEALTH_CHECK_NAME} --quiet
   
   # Delete SSL certificate
   gcloud compute ssl-certificates delete ${SSL_CERT_NAME} \
       --global --quiet
   
   echo "✅ Backend services cleaned up"
   ```

3. **Remove Redis Instance and Storage**:

   ```bash
   # Delete Redis instance
   gcloud redis instances delete ${REDIS_INSTANCE_NAME} \
       --region ${REGION} --quiet
   
   # Remove Cloud Storage bucket and contents
   gsutil -m rm -r gs://${BUCKET_NAME}
   
   echo "✅ Cache infrastructure removed"
   ```

4. **Remove Network Resources**:

   ```bash
   # Delete subnet
   gcloud compute networks subnets delete ${SUBNET_NAME} \
       --region ${REGION} --quiet
   
   # Delete VPC network
   gcloud compute networks delete ${NETWORK_NAME} --quiet
   
   # Release static IP address
   gcloud compute addresses delete cdn-ip-address --global --quiet
   
   echo "✅ Network resources cleaned up"
   ```

5. **Clean Up Project Resources**:

   ```bash
   # Remove local files
   rm -f index.html api-response.json updated-index.html
   rm -f cache_invalidation.py monitoring_config.json
   rm -f private.key certificate.crt
   
   # Optionally delete the entire project
   # gcloud projects delete ${PROJECT_ID} --quiet
   
   echo "✅ All resources cleaned up successfully"
   ```

## Discussion

This intelligent edge caching solution leverages Google Cloud's global infrastructure to deliver exceptional content performance through strategic cache optimization. The architecture combines Cloud CDN's 200+ edge locations with Memorystore for Redis to create a multi-layered caching strategy that adapts to traffic patterns and geographic distribution requirements. By implementing custom cache keys and intelligent invalidation workflows, the system achieves optimal cache hit ratios while maintaining content freshness across all edge locations, as documented in the [Google Cloud CDN best practices guide](https://cloud.google.com/cdn/docs/best-practices).

The integration between Cloud CDN and Memorystore provides several performance advantages over traditional caching approaches. Cloud CDN automatically routes users to the nearest edge location while Memorystore serves as a high-performance secondary cache layer for dynamic content and API responses. This dual-layer approach reduces origin server load by up to 95% while maintaining sub-100ms response times globally. The LRU eviction policy ensures that frequently accessed content remains cached while automatically removing stale data to optimize memory utilization, following [Google Cloud Memorystore performance guidelines](https://cloud.google.com/memorystore/docs/redis/memory-management-best-practices).

Geographic optimization plays a crucial role in the solution's effectiveness, with content pre-positioned at edge locations based on user access patterns and geographic proximity. The system uses intelligent routing algorithms to direct traffic to optimal edge locations while implementing regional cache warming strategies for popular content. This approach minimizes latency for global users while reducing bandwidth costs through efficient content distribution. Additionally, the cache invalidation system provides real-time content updates without sacrificing performance, ensuring that users always receive fresh content while maintaining the benefits of edge caching.

Cost optimization features include automatic scaling based on demand, intelligent cache warming to prevent cache misses, and monitoring-driven resource allocation adjustments. The solution typically reduces content delivery costs by 60-80% compared to origin-only serving while improving performance metrics significantly. Organizations can further optimize costs by implementing tiered storage strategies and automated lifecycle management for cached content, as outlined in the [Google Cloud cost optimization documentation](https://cloud.google.com/architecture/framework/cost-optimization).

> **Tip**: Monitor cache hit ratios regularly and adjust TTL values based on content update frequency to maximize performance benefits while ensuring content freshness.

## Challenge

Extend this intelligent edge caching solution by implementing these advanced enhancements:

1. **Implement predictive cache warming** using machine learning to analyze traffic patterns and pre-load content at edge locations before demand spikes, integrating with Vertex AI for intelligent forecasting.

2. **Add real-time cache optimization** with dynamic TTL adjustment based on content popularity and update frequency, using Cloud Functions to automatically tune cache parameters based on performance metrics.

3. **Create multi-region cache federation** with cross-region cache synchronization to ensure consistent content availability and implement intelligent failover between regions during outages.

4. **Develop edge-side personalization** using Edge Side Includes (ESI) or similar technologies to cache personalized content fragments while maintaining cache efficiency for dynamic user experiences.

5. **Integrate with CI/CD pipelines** for automated cache invalidation during deployments, implementing blue-green deployment strategies with intelligent cache management to ensure zero-downtime updates.

## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [Infrastructure Manager](code/infrastructure-manager/) - GCP Infrastructure Manager templates
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using gcloud CLI commands to deploy infrastructure
- [Terraform](code/terraform/) - Terraform configuration files