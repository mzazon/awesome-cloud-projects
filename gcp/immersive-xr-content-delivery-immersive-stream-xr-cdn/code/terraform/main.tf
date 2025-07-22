# Main Terraform configuration for Immersive XR Content Delivery Platform
# This configuration deploys a complete XR streaming platform with Cloud CDN and storage

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  # Resource naming with prefix and random suffix
  bucket_name      = "${var.resource_prefix}-assets-${random_id.suffix.hex}"
  cdn_name         = "${var.resource_prefix}-cdn-${random_id.suffix.hex}"
  stream_name      = "${var.resource_prefix}-stream-${random_id.suffix.hex}"
  sa_name          = "${var.resource_prefix}-streaming-sa-${random_id.suffix.hex}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    region      = var.region
  })
  
  # Content types and cache configurations
  cache_settings = {
    models    = { max_age = 3600, cache_control = "public,max-age=3600" }
    textures  = { max_age = 86400, cache_control = "public,max-age=86400" }
    configs   = { max_age = 1800, cache_control = "public,max-age=1800" }
    app       = { max_age = 3600, cache_control = "public,max-age=3600" }
  }
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when resource is destroyed
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Cloud Storage bucket for XR assets
resource "google_storage_bucket" "xr_assets" {
  name     = local.bucket_name
  location = var.region
  
  # Storage configuration
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  
  # Enable versioning for asset management
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # CORS configuration for XR applications
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  # Website configuration for static hosting
  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create IAM binding for public read access (if enabled)
resource "google_storage_bucket_iam_member" "public_read" {
  count = var.bucket_public_access ? 1 : 0
  
  bucket = google_storage_bucket.xr_assets.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Upload sample XR assets and configurations
resource "google_storage_bucket_object" "app_config" {
  name   = "configs/app-config.json"
  bucket = google_storage_bucket.xr_assets.name
  
  content = jsonencode({
    version     = "1.0"
    environment = var.environment
    rendering = {
      quality    = "high"
      fps        = 60
      resolution = "1920x1080"
    }
    features = {
      ar_enabled = true
      multi_user = false
      analytics  = true
    }
    cdn = {
      enabled     = true
      cache_modes = local.cache_settings
    }
  })
  
  content_type = "application/json"
  
  # Set cache control headers
  metadata = {
    "Cache-Control" = local.cache_settings.configs.cache_control
  }
}

# Upload sample web application files
resource "google_storage_bucket_object" "web_app_html" {
  name   = "app/index.html"
  bucket = google_storage_bucket.xr_assets.name
  
  content = templatefile("${path.module}/templates/index.html.tpl", {
    project_id   = var.project_id
    environment  = var.environment
    cdn_endpoint = "http://${google_compute_global_forwarding_rule.cdn.ip_address}"
  })
  
  content_type = "text/html"
  
  metadata = {
    "Cache-Control" = local.cache_settings.app.cache_control
  }
  
  depends_on = [google_compute_global_forwarding_rule.cdn]
}

resource "google_storage_bucket_object" "web_app_js" {
  name   = "app/xr-client.js"
  bucket = google_storage_bucket.xr_assets.name
  
  source       = "${path.module}/templates/xr-client.js"
  content_type = "application/javascript"
  
  metadata = {
    "Cache-Control" = local.cache_settings.app.cache_control
  }
}

# Create service account for XR streaming
resource "google_service_account" "xr_streaming" {
  account_id   = local.sa_name
  display_name = "XR Streaming Service Account"
  description  = "Service account for Immersive Stream for XR operations"
  
  depends_on = [google_project_service.apis]
}

# Grant necessary IAM permissions to service account
resource "google_project_iam_member" "xr_storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.xr_streaming.email}"
}

resource "google_project_iam_member" "xr_stream_agent" {
  project = var.project_id
  role    = "roles/stream.serviceAgent"
  member  = "serviceAccount:${google_service_account.xr_streaming.email}"
}

# Create service account key (optional, for external access)
resource "google_service_account_key" "xr_streaming_key" {
  service_account_id = google_service_account.xr_streaming.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# Create Cloud CDN backend bucket
resource "google_compute_backend_bucket" "cdn_backend" {
  name        = "${local.cdn_name}-backend"
  bucket_name = google_storage_bucket.xr_assets.name
  
  # CDN configuration
  enable_cdn = true
  
  cdn_policy {
    cache_mode        = var.cdn_cache_mode
    default_ttl       = var.cdn_default_ttl
    max_ttl           = var.cdn_max_ttl
    client_ttl        = var.cdn_default_ttl
    negative_caching  = true
    
    # Cache key policy for optimal caching
    cache_key_policy {
      include_host           = true
      include_protocol       = true
      include_query_string   = false
      query_string_whitelist = []
    }
    
    # Negative caching policy
    negative_caching_policy {
      code = 404
      ttl  = 300
    }
    
    negative_caching_policy {
      code = 410
      ttl  = 300
    }
  }
  
  depends_on = [google_project_service.apis]
}

# Note: Immersive Stream for XR is currently in preview and may not be available in all regions
# This is a placeholder configuration that would be used when the service becomes GA
resource "google_compute_backend_service" "xr_streaming" {
  name        = "${local.stream_name}-backend"
  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 30
  
  # Health check configuration
  health_checks = [google_compute_http_health_check.xr_health_check.id]
  
  # Load balancing configuration
  load_balancing_scheme = "EXTERNAL"
  
  # Session affinity for consistent XR streaming
  session_affinity = "CLIENT_IP"
  
  # Connection draining timeout
  connection_draining_timeout_sec = 60
  
  depends_on = [google_project_service.apis]
}

# HTTP health check for XR streaming service
resource "google_compute_http_health_check" "xr_health_check" {
  name         = "${local.stream_name}-health-check"
  description  = "Health check for XR streaming service"
  
  request_path         = "/health"
  port                 = 80
  check_interval_sec   = 30
  timeout_sec          = 10
  healthy_threshold    = 2
  unhealthy_threshold  = 3
}

# Create URL map with path-based routing
resource "google_compute_url_map" "unified_urlmap" {
  name            = "${local.cdn_name}-urlmap"
  default_service = google_compute_backend_bucket.cdn_backend.id
  
  # Path-based routing for XR streaming
  path_matcher {
    name            = "xr-streaming"
    default_service = google_compute_backend_bucket.cdn_backend.id
    
    path_rule {
      paths   = ["/stream/*"]
      service = google_compute_backend_service.xr_streaming.id
    }
    
    path_rule {
      paths   = ["/api/*"]
      service = google_compute_backend_service.xr_streaming.id
    }
  }
  
  host_rule {
    hosts        = ["*"]
    path_matcher = "xr-streaming"
  }
}

# Create HTTP(S) target proxy
resource "google_compute_target_http_proxy" "cdn_proxy" {
  name    = "${local.cdn_name}-proxy"
  url_map = google_compute_url_map.unified_urlmap.id
}

# Create SSL certificate (if SSL is enabled)
resource "google_compute_managed_ssl_certificate" "cdn_ssl" {
  count = var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? 1 : 0
  
  name = "${local.cdn_name}-ssl-cert"
  
  managed {
    domains = var.ssl_certificate_domains
  }
}

# Create HTTPS target proxy (if SSL is enabled)
resource "google_compute_target_https_proxy" "cdn_https_proxy" {
  count = var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? 1 : 0
  
  name             = "${local.cdn_name}-https-proxy"
  url_map          = google_compute_url_map.unified_urlmap.id
  ssl_certificates = [google_compute_managed_ssl_certificate.cdn_ssl[0].id]
}

# Create global forwarding rule for HTTP
resource "google_compute_global_forwarding_rule" "cdn" {
  name       = "${local.cdn_name}-rule"
  target     = google_compute_target_http_proxy.cdn_proxy.id
  port_range = "80"
}

# Create global forwarding rule for HTTPS (if SSL is enabled)
resource "google_compute_global_forwarding_rule" "cdn_https" {
  count = var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? 1 : 0
  
  name       = "${local.cdn_name}-https-rule"
  target     = google_compute_target_https_proxy.cdn_https_proxy[0].id
  port_range = "443"
}

# Create custom metrics for XR streaming monitoring
resource "google_logging_metric" "xr_session_starts" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "xr_session_starts"
  filter = "resource.type=\"immersive_stream_xr_service\" AND jsonPayload.event_type=\"session_start\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "XR Session Starts"
  }
  
  value_extractor = "1"
  
  depends_on = [google_project_service.apis]
}

resource "google_logging_metric" "xr_session_duration" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "xr_session_duration"
  filter = "resource.type=\"immersive_stream_xr_service\" AND jsonPayload.event_type=\"session_end\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    display_name = "XR Session Duration"
  }
  
  value_extractor = "jsonPayload.session_duration"
  
  depends_on = [google_project_service.apis]
}

# Create alerting policy for high GPU utilization
resource "google_monitoring_alert_policy" "xr_gpu_utilization" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "XR Service High GPU Utilization"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "GPU utilization above 85%"
    
    condition_threshold {
      filter          = "resource.type=\"immersive_stream_xr_service\""
      comparison      = "COMPARISON_GT"
      threshold_value = 85
      duration        = "300s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.apis]
}

# Create Cloud Armor security policy (optional)
resource "google_compute_security_policy" "xr_security_policy" {
  name        = "${local.cdn_name}-security-policy"
  description = "Security policy for XR content delivery"
  
  # Default rule to allow traffic
  rule {
    action   = "allow"
    priority = "2147483647"
    
    match {
      versioned_expr = "SRC_IPS_V1"
      
      config {
        src_ip_ranges = ["*"]
      }
    }
    
    description = "Default allow rule"
  }
  
  # Rate limiting rule
  rule {
    action   = "rate_based_ban"
    priority = "1000"
    
    match {
      versioned_expr = "SRC_IPS_V1"
      
      config {
        src_ip_ranges = ["*"]
      }
    }
    
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
      
      ban_duration_sec = 300
    }
    
    description = "Rate limiting rule"
  }
}

# Apply security policy to backend service
resource "google_compute_backend_service_iam_binding" "xr_security_binding" {
  backend_service = google_compute_backend_service.xr_streaming.name
  role           = "roles/compute.securityAdmin"
  members        = ["serviceAccount:${google_service_account.xr_streaming.email}"]
}