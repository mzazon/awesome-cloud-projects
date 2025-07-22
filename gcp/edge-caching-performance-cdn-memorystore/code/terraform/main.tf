# Main Terraform configuration for GCP Edge Caching Performance
# This file creates the complete infrastructure for intelligent edge caching
# using Cloud CDN and Memorystore for Redis

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming
  resource_suffix = random_id.suffix.hex
  
  # Resource names with consistent naming convention
  network_name           = "${var.resource_prefix}-network-${local.resource_suffix}"
  subnet_name           = "${var.resource_prefix}-subnet-${local.resource_suffix}"
  redis_name            = "${var.resource_prefix}-cache-${local.resource_suffix}"
  bucket_name           = "${var.resource_prefix}-origin-content-${local.resource_suffix}"
  health_check_name     = "${var.resource_prefix}-health-check-${local.resource_suffix}"
  backend_service_name  = "${var.resource_prefix}-backend-${local.resource_suffix}"
  url_map_name          = "${var.resource_prefix}-url-map-${local.resource_suffix}"
  target_proxy_name     = "${var.resource_prefix}-target-proxy-${local.resource_suffix}"
  forwarding_rule_name  = "${var.resource_prefix}-forwarding-rule-${local.resource_suffix}"
  ssl_certificate_name  = "${var.resource_prefix}-ssl-cert-${local.resource_suffix}"
  
  # Common labels with additional context
  common_labels = merge(var.labels, {
    deployment-id = local.resource_suffix
    recipe        = "edge-caching-performance-cdn-memorystore"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_required_apis ? toset([
    "compute.googleapis.com",
    "redis.googleapis.com",
    "storage.googleapis.com",
    "dns.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "certificatemanager.googleapis.com"
  ]) : []
  
  service            = each.value
  project            = var.project_id
  disable_on_destroy = false
}

# Create VPC Network for secure communication
resource "google_compute_network" "cdn_network" {
  name                    = local.network_name
  auto_create_subnetworks = false
  routing_mode           = "REGIONAL"
  description            = "VPC network for CDN and cache infrastructure"
  
  depends_on = [google_project_service.required_apis]
}

# Create subnet for cache infrastructure
resource "google_compute_subnetwork" "cdn_subnet" {
  name          = local.subnet_name
  network       = google_compute_network.cdn_network.id
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  description   = "Subnet for CDN and cache infrastructure"
  
  # Enable private Google access for secure communication
  private_ip_google_access = true
  
  # Enable flow logs for monitoring
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling       = 0.5
    metadata           = "INCLUDE_ALL_METADATA"
  }
}

# Create Memorystore Redis instance for high-performance caching
resource "google_redis_instance" "cache_instance" {
  name           = local.redis_name
  memory_size_gb = var.redis_memory_size_gb
  region         = var.region
  
  # Network configuration
  authorized_network = google_compute_network.cdn_network.id
  
  # Redis configuration
  redis_version    = var.redis_version
  tier            = var.redis_tier
  auth_enabled    = var.redis_auth_enabled
  
  # Enable transit encryption for security
  transit_encryption_mode = var.redis_transit_encryption_mode
  
  # Redis configuration for optimal cache performance
  redis_configs = {
    maxmemory-policy = "allkeys-lru"
    timeout         = "300"
    tcp-keepalive   = "60"
  }
  
  # Maintenance configuration
  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 2
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }
  
  display_name = "Intelligent Cache Instance"
  labels       = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for origin content
resource "google_storage_bucket" "origin_content" {
  name          = local.bucket_name
  location      = var.storage_location
  storage_class = var.storage_class
  
  # Enable uniform bucket-level access for security
  uniform_bucket_level_access = true
  
  # Enable versioning for content management
  versioning {
    enabled = var.enable_versioning
  }
  
  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Enable website configuration for static content
  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
  
  # CORS configuration for web applications
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create sample content for testing
resource "google_storage_bucket_object" "sample_index" {
  name   = "index.html"
  bucket = google_storage_bucket.origin_content.name
  content = templatefile("${path.module}/templates/index.html", {
    timestamp = timestamp()
  })
  content_type = "text/html"
}

resource "google_storage_bucket_object" "sample_api_response" {
  name   = "api-response.json"
  bucket = google_storage_bucket.origin_content.name
  content = jsonencode({
    message   = "API response"
    timestamp = timestamp()
    cached    = true
  })
  content_type = "application/json"
}

# Make bucket content publicly accessible
resource "google_storage_bucket_iam_member" "public_access" {
  bucket = google_storage_bucket.origin_content.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Create health check for backend services
resource "google_compute_health_check" "cdn_health_check" {
  name        = local.health_check_name
  description = "Health check for CDN backend services"
  
  timeout_sec         = var.health_check_timeout
  check_interval_sec  = var.health_check_interval
  healthy_threshold   = var.health_check_healthy_threshold
  unhealthy_threshold = var.health_check_unhealthy_threshold
  
  http_health_check {
    request_path = var.health_check_path
    port         = var.health_check_port
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create backend service with Cloud CDN enabled
resource "google_compute_backend_service" "cdn_backend_service" {
  name        = local.backend_service_name
  description = "Backend service for CDN with intelligent caching"
  
  protocol         = "HTTP"
  port_name        = "http"
  timeout_sec      = 30
  enable_cdn       = true
  
  health_checks = [google_compute_health_check.cdn_health_check.id]
  
  # CDN configuration for optimal performance
  cdn_policy {
    cache_mode       = var.cdn_cache_mode
    default_ttl      = var.cdn_default_ttl
    max_ttl          = var.cdn_max_ttl
    client_ttl       = var.cdn_client_ttl
    negative_caching = true
    
    # Cache key policy for intelligent caching
    cache_key_policy {
      include_host         = true
      include_protocol     = true
      include_query_string = false
      query_string_whitelist = []
    }
    
    # Negative caching policy
    negative_caching_policy {
      code = 404
      ttl  = 120
    }
    
    negative_caching_policy {
      code = 500
      ttl  = 30
    }
  }
  
  # Load balancing configuration
  load_balancing_scheme = "EXTERNAL"
  
  # Add Cloud Storage bucket as backend
  backend {
    group = google_compute_backend_bucket.storage_backend.id
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create backend bucket for Cloud Storage
resource "google_compute_backend_bucket" "storage_backend" {
  name        = "${local.backend_service_name}-bucket"
  description = "Backend bucket for Cloud Storage origin"
  bucket_name = google_storage_bucket.origin_content.name
  enable_cdn  = true
  
  # CDN configuration for static content
  cdn_policy {
    cache_mode   = "CACHE_ALL_STATIC"
    default_ttl  = 3600
    max_ttl      = 86400
    client_ttl   = 3600
    negative_caching = true
    
    # Optimized cache key policy
    cache_key_policy {
      include_host         = true
      include_protocol     = true
      include_query_string = false
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create URL map for intelligent traffic routing
resource "google_compute_url_map" "cdn_url_map" {
  name            = local.url_map_name
  description     = "URL map for CDN with intelligent routing"
  default_service = google_compute_backend_service.cdn_backend_service.id
  
  # Path-based routing for different content types
  path_matcher {
    name            = "api-matcher"
    default_service = google_compute_backend_service.cdn_backend_service.id
    
    # API endpoints with different caching strategy
    path_rule {
      paths   = ["/api/*"]
      service = google_compute_backend_service.cdn_backend_service.id
    }
    
    # Static content with aggressive caching
    path_rule {
      paths   = ["/static/*", "/*.css", "/*.js", "/*.png", "/*.jpg", "/*.gif"]
      service = google_compute_backend_service.cdn_backend_service.id
    }
  }
  
  host_rule {
    hosts        = ["*"]
    path_matcher = "api-matcher"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create SSL certificate if SSL is enabled
resource "google_compute_managed_ssl_certificate" "cdn_ssl_cert" {
  count = var.enable_ssl ? 1 : 0
  
  name = local.ssl_certificate_name
  
  managed {
    domains = var.ssl_certificate_domains
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create target HTTPS proxy
resource "google_compute_target_https_proxy" "cdn_target_proxy" {
  count = var.enable_ssl ? 1 : 0
  
  name    = local.target_proxy_name
  url_map = google_compute_url_map.cdn_url_map.id
  
  ssl_certificates = [google_compute_managed_ssl_certificate.cdn_ssl_cert[0].id]
  
  # Enable QUIC for improved performance
  quic_override = "ENABLE"
  
  depends_on = [google_project_service.required_apis]
}

# Create target HTTP proxy for non-SSL traffic
resource "google_compute_target_http_proxy" "cdn_target_proxy_http" {
  count = var.enable_ssl ? 0 : 1
  
  name    = local.target_proxy_name
  url_map = google_compute_url_map.cdn_url_map.id
  
  depends_on = [google_project_service.required_apis]
}

# Reserve static IP address for CDN
resource "google_compute_global_address" "cdn_ip_address" {
  name        = "${local.resource_suffix}-cdn-ip"
  description = "Static IP address for CDN endpoint"
  
  depends_on = [google_project_service.required_apis]
}

# Create global forwarding rule for HTTPS
resource "google_compute_global_forwarding_rule" "cdn_forwarding_rule_https" {
  count = var.enable_ssl ? 1 : 0
  
  name       = "${local.forwarding_rule_name}-https"
  target     = google_compute_target_https_proxy.cdn_target_proxy[0].id
  port_range = "443"
  ip_address = google_compute_global_address.cdn_ip_address.address
  
  depends_on = [google_project_service.required_apis]
}

# Create global forwarding rule for HTTP
resource "google_compute_global_forwarding_rule" "cdn_forwarding_rule_http" {
  name       = "${local.forwarding_rule_name}-http"
  target     = var.enable_ssl ? google_compute_target_https_proxy.cdn_target_proxy[0].id : google_compute_target_http_proxy.cdn_target_proxy_http[0].id
  port_range = "80"
  ip_address = google_compute_global_address.cdn_ip_address.address
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Monitoring dashboard for performance tracking
resource "google_monitoring_dashboard" "cdn_performance_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "CDN Cache Performance Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Cache Hit Ratio"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_backend_service\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_MEAN"
                      }
                    }
                  }
                }
              ]
              yAxis = {
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Request Latency"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_backend_service\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_DELTA"
                        crossSeriesReducer = "REDUCE_PERCENTILE_95"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width  = 12
          height = 4
          widget = {
            title = "Redis Memory Usage"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"redis_instance\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
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
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create alerting policy for low cache hit ratio
resource "google_monitoring_alert_policy" "low_cache_hit_ratio" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Low Cache Hit Ratio Alert"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Cache hit ratio below 80%"
    
    condition_threshold {
      filter         = "resource.type=\"gce_backend_service\""
      duration       = "300s"
      comparison     = "COMPARISON_LESS_THAN"
      threshold_value = 0.8
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Logging sink for CDN logs
resource "google_logging_project_sink" "cdn_logs_sink" {
  count = var.enable_logging ? 1 : 0
  
  name        = "${local.resource_suffix}-cdn-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.origin_content.name}/cdn-logs"
  
  # Export CDN and load balancer logs
  filter = "resource.type=\"gce_backend_service\" OR resource.type=\"http_load_balancer\""
  
  # Use unique writer identity
  unique_writer_identity = true
  
  depends_on = [google_project_service.required_apis]
}

# Create firewall rules for secure access
resource "google_compute_firewall" "allow_health_check" {
  name    = "${local.resource_suffix}-allow-health-check"
  network = google_compute_network.cdn_network.name
  
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  
  # Google Cloud health check source ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["cdn-backend"]
  
  depends_on = [google_project_service.required_apis]
}

resource "google_compute_firewall" "allow_cdn_traffic" {
  name    = "${local.resource_suffix}-allow-cdn-traffic"
  network = google_compute_network.cdn_network.name
  
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["cdn-backend"]
  
  depends_on = [google_project_service.required_apis]
}

# Create NAT gateway for secure outbound access
resource "google_compute_router" "cdn_router" {
  name    = "${local.resource_suffix}-router"
  region  = var.region
  network = google_compute_network.cdn_network.id
  
  bgp {
    asn = 64514
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_compute_router_nat" "cdn_nat" {
  name   = "${local.resource_suffix}-nat"
  router = google_compute_router.cdn_router.name
  region = var.region
  
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
  
  depends_on = [google_project_service.required_apis]
}