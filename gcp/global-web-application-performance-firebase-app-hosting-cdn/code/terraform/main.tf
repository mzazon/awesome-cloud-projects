# Global Web Application Performance with Firebase App Hosting and Cloud CDN
#
# This Terraform configuration creates a complete infrastructure stack for deploying
# high-performance web applications with global distribution capabilities.
#
# Architecture includes:
# - Firebase App Hosting for serverless web hosting
# - Cloud CDN for global content caching and distribution
# - Global Load Balancer for traffic management
# - Cloud Storage for static asset hosting
# - Cloud Functions for automated performance optimization
# - Cloud Monitoring for performance tracking and alerting

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Resource naming configuration
  suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix.hex
  
  # Common labels applied to all resources
  common_labels = merge({
    environment = var.environment
    recipe      = "global-web-app-performance"
    managed-by  = "terraform"
    created-by  = "firebase-app-hosting-recipe"
  }, var.labels)
  
  # Bucket name with unique suffix
  bucket_name = var.storage_bucket_name != "" ? var.storage_bucket_name : "${var.resource_prefix}-assets-${local.suffix}"
  
  # Function name with suffix
  function_name = "${var.resource_prefix}-optimizer-${local.suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of APIs
  disable_dependent_services = false
  disable_on_destroy        = false
}

# =============================================================================
# CLOUD STORAGE FOR STATIC ASSETS
# =============================================================================

# Cloud Storage bucket for static assets with CDN optimization
resource "google_storage_bucket" "web_assets" {
  name          = local.bucket_name
  location      = var.storage_location
  storage_class = var.storage_class
  project       = var.project_id
  
  # Enable versioning for asset management
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # CORS configuration for cross-origin requests
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["Content-Type", "Cache-Control", "Content-Length", "ETag"]
    max_age_seconds = 3600
  }
  
  # Uniform bucket-level access for security
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Make bucket objects publicly readable for web serving
resource "google_storage_bucket_iam_member" "public_access" {
  bucket = google_storage_bucket.web_assets.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# =============================================================================
# SERVICE ACCOUNTS AND IAM
# =============================================================================

# Service account for Firebase App Hosting
resource "google_service_account" "app_hosting" {
  account_id   = "${var.resource_prefix}-app-hosting-${local.suffix}"
  display_name = "Firebase App Hosting Service Account"
  description  = "Service account for Firebase App Hosting backend"
  project      = var.project_id
  
  depends_on = [google_project_service.apis]
}

# IAM role for Firebase App Hosting compute runner
resource "google_project_iam_member" "app_hosting_runner" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.app_hosting.email}"
}

# IAM role for Cloud Storage access
resource "google_project_iam_member" "app_hosting_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.app_hosting.email}"
}

# Service account for Cloud Functions
resource "google_service_account" "functions" {
  account_id   = "${var.resource_prefix}-functions-${local.suffix}"
  display_name = "Performance Optimization Functions Service Account"
  description  = "Service account for performance optimization Cloud Functions"
  project      = var.project_id
  
  depends_on = [google_project_service.apis]
}

# IAM roles for Cloud Functions monitoring access
resource "google_project_iam_member" "functions_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.functions.email}"
}

resource "google_project_iam_member" "functions_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.functions.email}"
}

# =============================================================================
# GLOBAL LOAD BALANCER AND CDN
# =============================================================================

# Global static IP address for load balancer
resource "google_compute_global_address" "web_app" {
  name         = "${var.resource_prefix}-global-ip-${local.suffix}"
  project      = var.project_id
  network_tier = var.network_tier
  
  depends_on = [google_project_service.apis]
}

# Managed SSL certificate for HTTPS
resource "google_compute_managed_ssl_certificate" "web_app" {
  count = var.domain_name != "" ? 1 : 0
  
  name    = "${var.ssl_certificate_name}-${local.suffix}"
  project = var.project_id
  
  managed {
    domains = concat([var.domain_name], var.additional_domains)
  }
  
  lifecycle {
    create_before_destroy = true
  }
  
  depends_on = [google_project_service.apis]
}

# Health check for backend services
resource "google_compute_health_check" "web_app" {
  name    = "${var.resource_prefix}-health-check-${local.suffix}"
  project = var.project_id
  
  timeout_sec         = 5
  check_interval_sec  = 30
  healthy_threshold   = 2
  unhealthy_threshold = 3
  
  http_health_check {
    port         = 8080
    request_path = var.uptime_check_path
  }
  
  depends_on = [google_project_service.apis]
}

# Backend bucket for static assets served through CDN
resource "google_compute_backend_bucket" "web_assets" {
  name        = "${var.resource_prefix}-backend-bucket-${local.suffix}"
  bucket_name = google_storage_bucket.web_assets.name
  project     = var.project_id
  
  # Enable CDN for static assets
  enable_cdn = var.enable_cdn
  
  # CDN configuration for optimal caching
  cdn_policy {
    cache_mode                   = var.cdn_cache_mode
    default_ttl                  = var.cdn_default_ttl
    max_ttl                      = var.cdn_max_ttl
    client_ttl                   = var.cdn_client_ttl
    negative_caching             = true
    negative_caching_policy {
      code = 404
      ttl  = 60
    }
    negative_caching_policy {
      code = 410
      ttl  = 60
    }
    serve_while_stale = 86400
    
    # Cache key policy for consistent caching
    cache_key_policy {
      include_host         = true
      include_protocol     = true
      include_query_string = false
      query_string_whitelist = [
        "v",           # Version parameter
        "utm_source",  # Analytics parameters
        "utm_medium",
        "utm_campaign"
      ]
    }
    
    # Bypass cache for certain paths
    bypass_cache_on_request_headers {
      header_name = "Authorization"
    }
    bypass_cache_on_request_headers {
      header_name = "Cookie"
    }
  }
  
  # Custom headers for performance tracking
  custom_response_headers = [
    "X-Cache-Hit: {cdn_cache_status}",
    "X-Cache-ID: {cdn_cache_id}",
    "X-Served-By: {server_name}"
  ]
  
  depends_on = [google_project_service.apis]
}

# Backend service for dynamic content (Firebase App Hosting)
resource "google_compute_backend_service" "web_app" {
  name                  = "${var.resource_prefix}-backend-service-${local.suffix}"
  project               = var.project_id
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30
  
  # Enable CDN for dynamic content
  enable_cdn = var.enable_cdn
  
  # CDN policy for dynamic content
  cdn_policy {
    cache_mode                   = "USE_ORIGIN_HEADERS"
    default_ttl                  = 0
    max_ttl                      = var.cdn_max_ttl
    client_ttl                   = 0
    negative_caching             = false
    serve_while_stale           = 0
    
    # Cache key policy for dynamic content
    cache_key_policy {
      include_host         = true
      include_protocol     = true
      include_query_string = true
    }
  }
  
  # Health check configuration
  health_checks = [google_compute_health_check.web_app.id]
  
  # Custom headers for geographic information
  custom_request_headers = [
    "X-Client-Region: {client_region}",
    "X-Client-City: {client_city}",
    "X-Client-Country: {client_country_code}"
  ]
  
  depends_on = [google_project_service.apis]
}

# URL map for routing traffic between static and dynamic content
resource "google_compute_url_map" "web_app" {
  name            = "${var.resource_prefix}-url-map-${local.suffix}"
  project         = var.project_id
  default_service = google_compute_backend_service.web_app.id
  
  # Route static assets to backend bucket
  path_matcher {
    name            = "static-assets"
    default_service = google_compute_backend_service.web_app.id
    
    path_rule {
      paths   = ["/static/*", "/assets/*", "/*.js", "/*.css", "/*.png", "/*.jpg", "/*.jpeg", "/*.gif", "/*.svg", "/*.ico", "/*.woff", "/*.woff2"]
      service = google_compute_backend_bucket.web_assets.id
    }
  }
  
  # Host rule for routing
  host_rule {
    hosts        = var.domain_name != "" ? [var.domain_name] : ["*"]
    path_matcher = "static-assets"
  }
  
  depends_on = [google_project_service.apis]
}

# Target HTTPS proxy
resource "google_compute_target_https_proxy" "web_app" {
  name    = "${var.resource_prefix}-https-proxy-${local.suffix}"
  project = var.project_id
  url_map = google_compute_url_map.web_app.id
  
  # Use managed SSL certificate if domain is provided
  ssl_certificates = var.domain_name != "" ? [google_compute_managed_ssl_certificate.web_app[0].id] : []
  
  depends_on = [google_project_service.apis]
}

# Target HTTP proxy for HTTP to HTTPS redirect
resource "google_compute_target_http_proxy" "web_app" {
  name    = "${var.resource_prefix}-http-proxy-${local.suffix}"
  project = var.project_id
  url_map = google_compute_url_map.web_app.id
  
  depends_on = [google_project_service.apis]
}

# Global forwarding rule for HTTPS traffic
resource "google_compute_global_forwarding_rule" "web_app_https" {
  name                  = "${var.resource_prefix}-https-forwarding-rule-${local.suffix}"
  project               = var.project_id
  target                = google_compute_target_https_proxy.web_app.id
  port_range           = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address           = google_compute_global_address.web_app.address
  network_tier         = var.network_tier
  
  depends_on = [google_project_service.apis]
}

# Global forwarding rule for HTTP traffic (redirect to HTTPS)
resource "google_compute_global_forwarding_rule" "web_app_http" {
  name                  = "${var.resource_prefix}-http-forwarding-rule-${local.suffix}"
  project               = var.project_id
  target                = google_compute_target_http_proxy.web_app.id
  port_range           = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address           = google_compute_global_address.web_app.address
  network_tier         = var.network_tier
  
  depends_on = [google_project_service.apis]
}

# =============================================================================
# CLOUD FUNCTIONS FOR PERFORMANCE OPTIMIZATION
# =============================================================================

# Pub/Sub topic for triggering performance optimization
resource "google_pubsub_topic" "performance_metrics" {
  name    = "${var.resource_prefix}-performance-metrics-${local.suffix}"
  project = var.project_id
  
  # Message retention for 7 days
  message_retention_duration = "604800s"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Cloud Scheduler job to trigger performance optimization
resource "google_cloud_scheduler_job" "performance_optimization" {
  name             = "${var.resource_prefix}-perf-optimizer-${local.suffix}"
  project          = var.project_id
  region           = var.region
  description      = "Trigger performance optimization analysis"
  schedule         = "*/15 * * * *"  # Every 15 minutes
  time_zone        = "UTC"
  attempt_deadline = "320s"
  
  pubsub_target {
    topic_name = google_pubsub_topic.performance_metrics.id
    data       = base64encode(jsonencode({
      project_id = var.project_id
      region     = var.region
    }))
  }
  
  depends_on = [google_project_service.apis]
}

# Create source code archive for Cloud Function
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/performance-optimizer-${local.suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "functions/performance-optimizer-${local.suffix}.zip"
  bucket = google_storage_bucket.web_assets.name
  source = data.archive_file.function_source.output_path
  
  # Trigger redeployment when source changes
  source_hash = data.archive_file.function_source.output_md5
}

# Cloud Function for performance optimization
resource "google_cloudfunctions2_function" "performance_optimizer" {
  name     = local.function_name
  location = var.region
  project  = var.project_id
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "optimize_performance"
    
    source {
      storage_source {
        bucket = google_storage_bucket.web_assets.name
        object = google_storage_bucket_object.function_source.name
      }
    }
    
    environment_variables = {
      BUILD_ENV = var.environment
    }
  }
  
  service_config {
    max_instance_count               = 10
    min_instance_count               = 0
    available_memory                 = var.function_memory
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID  = var.project_id
      ENVIRONMENT = var.environment
    }
    
    service_account_email = google_service_account.functions.email
    ingress_settings      = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.performance_metrics.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_storage_bucket_object.function_source
  ]
}

# =============================================================================
# CLOUD MONITORING AND ALERTING
# =============================================================================

# Notification channel for email alerts
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  display_name = "Email Notifications"
  project      = var.project_id
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.apis]
}

# Alert policy for high latency
resource "google_monitoring_alert_policy" "high_latency" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "High Latency Alert - ${var.resource_prefix}"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "HTTP request latency is too high"
    
    condition_threshold {
      filter         = "resource.type=\"gce_backend_service\" AND metric.type=\"loadbalancing.googleapis.com/https/request_latencies\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = var.alert_threshold_latency_ms
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_PERCENTILE_95"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.label.backend_service_name"]
      }
      
      trigger {
        count = 1
      }
    }
  }
  
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].name] : []
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  documentation {
    content = "High latency detected on web application. Check CDN cache hit rates and backend performance."
  }
  
  depends_on = [google_project_service.apis]
}

# Alert policy for high error rate
resource "google_monitoring_alert_policy" "high_error_rate" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "High Error Rate Alert - ${var.resource_prefix}"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "HTTP error rate is too high"
    
    condition_threshold {
      filter         = "resource.type=\"gce_backend_service\" AND metric.type=\"loadbalancing.googleapis.com/https/request_count\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = var.alert_threshold_error_rate
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.backend_service_name", "metric.label.response_code_class"]
      }
      
      trigger {
        count = 1
      }
    }
  }
  
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].name] : []
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  documentation {
    content = "High error rate detected on web application. Check application logs and backend health."
  }
  
  depends_on = [google_project_service.apis]
}

# Uptime check for web application availability
resource "google_monitoring_uptime_check_config" "web_app" {
  count = var.enable_monitoring && var.domain_name != "" ? 1 : 0
  
  display_name = "Web App Uptime Check - ${var.resource_prefix}"
  project      = var.project_id
  timeout      = "10s"
  period       = "60s"
  
  http_check {
    path         = var.uptime_check_path
    port         = "443"
    use_ssl      = true
    validate_ssl = true
    
    accepted_response_status_codes {
      status_value = 200
    }
    
    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
  }
  
  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.domain_name
    }
  }
  
  content_matchers {
    content = "<!DOCTYPE html>"
    matcher = "CONTAINS_STRING"
  }
  
  checker_type = "STATIC_IP_CHECKERS"
  
  depends_on = [google_project_service.apis]
}