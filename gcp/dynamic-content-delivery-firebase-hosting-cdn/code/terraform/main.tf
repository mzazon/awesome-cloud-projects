# ==========================================
# Dynamic Content Delivery with Firebase Hosting and Cloud CDN
# ==========================================
# This Terraform configuration deploys a comprehensive global content delivery
# architecture using Firebase Hosting, Cloud CDN, Cloud Functions, and Cloud Storage

# ==========================================
# Local Values and Data Sources
# ==========================================

# Generate random suffix for globally unique names
resource "random_id" "suffix" {
  count       = var.random_suffix == "" ? 1 : 0
  byte_length = 4
}

locals {
  # Generate unique suffix for resource naming
  suffix = var.random_suffix != "" ? var.random_suffix : random_id.suffix[0].hex
  
  # Construct resource names with consistent patterns
  base_name           = "${var.application_name}-${var.environment}"
  site_id            = var.site_id != "" ? var.site_id : "${local.base_name}-${local.suffix}"
  storage_bucket     = "${var.project_id}-${local.base_name}-media-${local.suffix}"
  source_bucket      = "${var.project_id}-${local.base_name}-source-${local.suffix}"
  log_bucket         = var.log_bucket != "" ? var.log_bucket : "${var.project_id}-${local.base_name}-logs-${local.suffix}"
  
  # Combine user labels with default labels
  common_labels = merge(var.labels, {
    deployment-id = local.suffix
    created-by    = "terraform"
    recipe-name   = "dynamic-content-delivery-firebase-hosting-cdn"
  })
}

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Get Cloud Functions service account for IAM bindings
data "google_app_engine_default_service_account" "default" {
  depends_on = [google_project_service.required_apis]
}

# ==========================================
# Enable Required APIs
# ==========================================

# Enable all required Google Cloud APIs for the infrastructure
resource "google_project_service" "required_apis" {
  for_each = toset([
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "compute.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "iamcredentials.googleapis.com",
    "serviceusage.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling on destroy to avoid breaking dependencies
  disable_on_destroy = false
}

# Wait for APIs to be fully enabled before proceeding
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

# ==========================================
# Service Accounts and IAM
# ==========================================

# Dedicated service account for Cloud Functions
resource "google_service_account" "function_sa" {
  depends_on = [time_sleep.wait_for_apis]
  
  account_id   = "${local.base_name}-functions-sa"
  display_name = "Service Account for Dynamic Content Functions"
  description  = "Service account used by Cloud Functions for dynamic content generation"
  project      = var.project_id
}

# Grant necessary permissions to the function service account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/storage.objectViewer",      # Read access to storage buckets
    "roles/monitoring.metricWriter",   # Write metrics to Cloud Monitoring
    "roles/logging.logWriter",         # Write logs to Cloud Logging
    "roles/cloudtrace.agent"          # Write traces for performance monitoring
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [google_service_account.function_sa]
}

# ==========================================
# Firebase Configuration
# ==========================================

# Initialize Firebase project (required for hosting)
resource "google_firebase_project" "default" {
  provider = google-beta
  project  = var.project_id
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create Firebase web app if enabled
resource "google_firebase_web_app" "default" {
  count = var.enable_firebase_web_app ? 1 : 0
  
  provider     = google-beta
  project      = var.project_id
  display_name = var.web_app_display_name
  
  depends_on = [google_firebase_project.default]
}

# Create Firebase hosting site
resource "google_firebase_hosting_site" "default" {
  provider = google-beta
  project  = var.project_id
  site_id  = local.site_id
  app_id   = var.enable_firebase_web_app ? google_firebase_web_app.default[0].app_id : null
  
  depends_on = [google_firebase_project.default]
}

# ==========================================
# Cloud Storage Buckets
# ==========================================

# Source code bucket for Cloud Functions
resource "google_storage_bucket" "source_bucket" {
  name     = local.source_bucket
  location = var.storage_location
  project  = var.project_id
  
  # Security and access configuration
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  force_destroy              = true
  
  # Versioning configuration
  dynamic "versioning" {
    for_each = var.enable_versioning ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Labels for resource management
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Media assets bucket with CDN optimization
resource "google_storage_bucket" "media_bucket" {
  name     = local.storage_bucket
  location = var.storage_location
  project  = var.project_id
  
  # Storage class and access configuration
  storage_class                   = var.storage_class
  uniform_bucket_level_access     = var.enable_uniform_bucket_level_access
  force_destroy                  = true
  
  # Versioning configuration
  dynamic "versioning" {
    for_each = var.enable_versioning ? [1] : []
    content {
      enabled = true
    }
  }
  
  # CORS configuration for web access
  cors {
    origin          = var.cors_origins
    method          = var.cors_methods
    response_header = ["*"]
    max_age_seconds = var.cors_max_age_seconds
  }
  
  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_age > 0 ? [1] : []
    content {
      condition {
        age = var.lifecycle_age
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Access logging configuration
  dynamic "logging" {
    for_each = var.enable_logging ? [1] : []
    content {
      log_bucket        = google_storage_bucket.access_logs[0].name
      log_object_prefix = "media-access-logs/"
    }
  }
  
  # Labels for resource management
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Access logs bucket (created only if logging is enabled)
resource "google_storage_bucket" "access_logs" {
  count = var.enable_logging ? 1 : 0
  
  name     = local.log_bucket
  location = var.storage_location
  project  = var.project_id
  
  # Configuration for log storage
  storage_class                   = "STANDARD"
  uniform_bucket_level_access     = true
  force_destroy                  = true
  
  # Lifecycle management for log retention
  lifecycle_rule {
    condition {
      age = 90  # Keep logs for 90 days
    }
    action {
      type = "Delete"
    }
  }
  
  # Labels for resource management
  labels = merge(local.common_labels, {
    purpose = "access-logging"
  })
  
  depends_on = [time_sleep.wait_for_apis]
}

# Make media bucket publicly readable for CDN access
resource "google_storage_bucket_iam_member" "media_bucket_public_read" {
  bucket = google_storage_bucket.media_bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
  
  depends_on = [google_storage_bucket.media_bucket]
}

# ==========================================
# Sample Function Source Code
# ==========================================

# Create ZIP archive for Cloud Functions source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/index.js", {
      project_id = var.project_id
    })
    filename = "index.js"
  }
  
  source {
    content = templatefile("${path.module}/function_code/package.json", {
      runtime = var.function_runtime
    })
    filename = "package.json"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.suffix}.zip"
  bucket = google_storage_bucket.source_bucket.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [
    google_storage_bucket.source_bucket,
    data.archive_file.function_source
  ]
}

# ==========================================
# Cloud Functions for Dynamic Content
# ==========================================

# Products API function for dynamic product catalog
resource "google_cloudfunctions2_function" "get_products" {
  name        = "${local.base_name}-get-products"
  location    = var.region
  description = "Function to serve dynamic product catalog with regional personalization"
  project     = var.project_id
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "getProducts"
    
    source {
      storage_source {
        bucket = google_storage_bucket.source_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = var.function_min_instances
    available_memory      = var.function_memory
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.function_sa.email
    
    # Environment variables for function configuration
    environment_variables = {
      PROJECT_ID     = var.project_id
      STORAGE_BUCKET = google_storage_bucket.media_bucket.name
      ENVIRONMENT    = var.environment
    }
    
    # Security configuration
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }
  
  # Labels for resource management
  labels = merge(local.common_labels, {
    function-type = "api"
    purpose      = "products"
  })
  
  depends_on = [
    google_storage_bucket_object.function_source,
    google_service_account.function_sa,
    google_project_iam_member.function_permissions
  ]
}

# Recommendations API function for personalized content
resource "google_cloudfunctions2_function" "get_recommendations" {
  name        = "${local.base_name}-get-recommendations"
  location    = var.region
  description = "Function to serve personalized recommendations based on user behavior"
  project     = var.project_id
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "getRecommendations"
    
    source {
      storage_source {
        bucket = google_storage_bucket.source_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = var.function_min_instances
    available_memory      = var.function_memory
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.function_sa.email
    
    # Environment variables for function configuration
    environment_variables = {
      PROJECT_ID     = var.project_id
      STORAGE_BUCKET = google_storage_bucket.media_bucket.name
      ENVIRONMENT    = var.environment
    }
    
    # Security configuration
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }
  
  # Labels for resource management
  labels = merge(local.common_labels, {
    function-type = "api"
    purpose      = "recommendations"
  })
  
  depends_on = [
    google_storage_bucket_object.function_source,
    google_service_account.function_sa,
    google_project_iam_member.function_permissions
  ]
}

# Allow public access to functions for web application
resource "google_cloudfunctions2_function_iam_member" "products_invoker" {
  project        = google_cloudfunctions2_function.get_products.project
  location       = google_cloudfunctions2_function.get_products.location
  cloud_function = google_cloudfunctions2_function.get_products.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloudfunctions2_function_iam_member" "recommendations_invoker" {
  project        = google_cloudfunctions2_function.get_recommendations.project
  location       = google_cloudfunctions2_function.get_recommendations.location
  cloud_function = google_cloudfunctions2_function.get_recommendations.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# ==========================================
# Load Balancer and Cloud CDN
# ==========================================

# Backend bucket for Cloud Storage CDN integration
resource "google_compute_backend_bucket" "media_backend" {
  name        = "${local.base_name}-media-backend"
  bucket_name = google_storage_bucket.media_bucket.name
  enable_cdn  = var.enable_cdn
  description = "Backend bucket for media assets with CDN optimization"
  project     = var.project_id
  
  # CDN policy configuration for optimal caching
  dynamic "cdn_policy" {
    for_each = var.enable_cdn ? [1] : []
    content {
      cache_mode  = var.cdn_cache_mode
      default_ttl = var.cdn_default_ttl
      max_ttl     = var.cdn_max_ttl
      
      # Enable negative caching for error responses
      negative_caching = true
      negative_caching_policy {
        code = 404
        ttl  = 300  # Cache 404s for 5 minutes
      }
      
      # Cache key policy for consistent caching
      cache_key_policy {
        include_http_headers = ["Origin"]
      }
      
      # Enable request coalescing to reduce origin load
      request_coalescing = true
    }
  }
  
  # Enable compression for better performance
  compression_mode = var.enable_compression ? "AUTOMATIC" : "DISABLED"
  
  depends_on = [
    google_storage_bucket.media_bucket,
    google_storage_bucket_iam_member.media_bucket_public_read
  ]
}

# URL map for routing traffic to appropriate backends
resource "google_compute_url_map" "main" {
  name            = "${local.base_name}-url-map"
  description     = "URL map for dynamic content delivery with CDN"
  default_service = google_compute_backend_bucket.media_backend.id
  project         = var.project_id
  
  # Path matcher for media content routing
  path_matcher {
    name            = "media-matcher"
    default_service = google_compute_backend_bucket.media_backend.id
    
    path_rule {
      paths   = ["/images/*", "/assets/*", "/media/*"]
      service = google_compute_backend_bucket.media_backend.id
    }
  }
  
  # Host rule for routing
  host_rule {
    hosts        = ["*"]
    path_matcher = "media-matcher"
  }
  
  depends_on = [google_compute_backend_bucket.media_backend]
}

# HTTP target proxy for load balancer
resource "google_compute_target_http_proxy" "main" {
  name    = "${local.base_name}-http-proxy"
  url_map = google_compute_url_map.main.id
  project = var.project_id
  
  depends_on = [google_compute_url_map.main]
}

# Global forwarding rule for external access
resource "google_compute_global_forwarding_rule" "main" {
  name       = "${local.base_name}-forwarding-rule"
  target     = google_compute_target_http_proxy.main.id
  port_range = "80"
  project    = var.project_id
  
  depends_on = [google_compute_target_http_proxy.main]
}

# ==========================================
# Monitoring and Alerting (Optional)
# ==========================================

# Cloud Monitoring notification channel (if monitoring is enabled)
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Email Notifications for ${local.base_name}"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = "admin@${var.project_id}.iam.gserviceaccount.com"
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Uptime check for Firebase hosting
resource "google_monitoring_uptime_check_config" "firebase_hosting" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Firebase Hosting Uptime Check"
  timeout      = "10s"
  period       = "300s"
  project      = var.project_id
  
  http_check {
    path         = "/"
    port         = "443"
    use_ssl      = true
    validate_ssl = true
  }
  
  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = google_firebase_hosting_site.default.default_url
    }
  }
  
  depends_on = [google_firebase_hosting_site.default]
}

# Alert policy for function errors
resource "google_monitoring_alert_policy" "function_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Cloud Function Error Rate Alert"
  project      = var.project_id
  
  conditions {
    display_name = "Function error rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 10
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = google_monitoring_notification_channel.email
    content {
      notification_channels = [notification_channels.value.id]
    }
  }
  
  depends_on = [
    google_cloudfunctions2_function.get_products,
    google_cloudfunctions2_function.get_recommendations
  ]
}