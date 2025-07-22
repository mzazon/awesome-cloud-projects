# =============================================================================
# Edge-to-Cloud Video Analytics with Media CDN and Vertex AI
# Terraform Configuration for GCP
# =============================================================================

# Local variables for resource configuration
locals {
  # Generate unique suffix for resource names to avoid conflicts
  random_suffix = random_id.suffix.hex
  
  # Function source files configuration
  function_source_files = {
    "video-processor" = {
      filename    = "video-processor.zip"
      output_path = "${path.module}/function-source/video-processor.zip"
    }
    "advanced-analytics" = {
      filename    = "advanced-analytics.zip"
      output_path = "${path.module}/function-source/advanced-analytics.zip"
    }
    "results-processor" = {
      filename    = "results-processor.zip"
      output_path = "${path.module}/function-source/results-processor.zip"
    }
  }
  
  # Labels for resource management and billing
  common_labels = {
    environment     = var.environment
    project        = "video-analytics"
    managed-by     = "terraform"
    recipe-version = "1.0"
  }
  
  # Media CDN configuration
  media_cdn_config = {
    cache_mode            = "CACHE_ALL_STATIC"
    default_ttl          = "3600s"    # 1 hour
    max_ttl              = "86400s"   # 24 hours
    negative_caching     = true
    negative_caching_ttl = "120s"     # 2 minutes
  }
}

# Random ID for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# =============================================================================
# Google Cloud APIs
# =============================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "aiplatform.googleapis.com",
    "videointelligence.googleapis.com",
    "eventarc.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "compute.googleapis.com",
    "networkconnectivity.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of critical APIs
  disable_dependent_services = false
}

# =============================================================================
# Cloud Storage Infrastructure
# =============================================================================

# Primary bucket for video content storage and CDN origin
resource "google_storage_bucket" "video_content" {
  name          = "${var.bucket_prefix}-content-${local.random_suffix}"
  location      = var.region
  project       = var.project_id
  storage_class = "STANDARD"
  
  # Enable uniform bucket-level access for security
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90  # days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 365  # days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }
  
  # Configure CORS for web access
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  # Public access prevention for security
  public_access_prevention = "enforced"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Bucket for analytics results and processed insights
resource "google_storage_bucket" "analytics_results" {
  name          = "${var.bucket_prefix}-results-${local.random_suffix}"
  location      = var.region
  project       = var.project_id
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  # Lifecycle management for analytics results
  lifecycle_rule {
    condition {
      age = 30  # days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 180  # days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  public_access_prevention = "enforced"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Bucket for Cloud Functions source code
resource "google_storage_bucket" "function_source" {
  name          = "${var.bucket_prefix}-functions-${local.random_suffix}"
  location      = var.region
  project       = var.project_id
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# Service Accounts and IAM
# =============================================================================

# Service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "video-analytics-functions-${local.random_suffix}"
  display_name = "Video Analytics Functions Service Account"
  description  = "Service account for video analytics Cloud Functions"
  project      = var.project_id
}

# IAM permissions for the function service account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/storage.objectAdmin",           # Full access to storage buckets
    "roles/aiplatform.user",              # Vertex AI access
    "roles/videointelligence.admin",      # Video Intelligence API access
    "roles/eventarc.eventReceiver",       # Eventarc trigger access
    "roles/artifactregistry.reader",      # Read container images
    "roles/logging.logWriter",            # Write logs
    "roles/monitoring.metricWriter",      # Write metrics
    "roles/cloudsql.client"               # CloudSQL access if needed
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [google_service_account.function_sa]
}

# Service account for Vertex AI operations
resource "google_service_account" "vertex_ai_sa" {
  account_id   = "vertex-ai-video-${local.random_suffix}"
  display_name = "Vertex AI Video Analytics Service Account"
  description  = "Service account for Vertex AI video analytics operations"
  project      = var.project_id
}

# IAM permissions for Vertex AI service account
resource "google_project_iam_member" "vertex_ai_permissions" {
  for_each = toset([
    "roles/aiplatform.serviceAgent",      # Vertex AI service agent
    "roles/storage.objectAdmin",          # Storage access for datasets
    "roles/videointelligence.admin",      # Video Intelligence access
    "roles/bigquery.dataEditor"           # BigQuery access for results
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.vertex_ai_sa.email}"
  
  depends_on = [google_service_account.vertex_ai_sa]
}

# =============================================================================
# Function Source Code Archive Creation
# =============================================================================

# Create function source archives
data "archive_file" "function_sources" {
  for_each = local.function_source_files
  
  type        = "zip"
  output_path = each.value.output_path
  
  source {
    content = templatefile("${path.module}/function-templates/${each.key}.py", {
      project_id      = var.project_id
      region         = var.region
      results_bucket = google_storage_bucket.analytics_results.name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function-templates/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source archives to Cloud Storage
resource "google_storage_bucket_object" "function_sources" {
  for_each = local.function_source_files
  
  name   = each.value.filename
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_sources[each.key].output_path
  
  depends_on = [data.archive_file.function_sources]
}

# =============================================================================
# Vertex AI Configuration
# =============================================================================

# Vertex AI dataset for video analytics
resource "google_vertex_ai_dataset" "video_dataset" {
  display_name          = "video-analytics-dataset-${local.random_suffix}"
  metadata_schema_uri   = "gs://google-cloud-aiplatform/schema/dataset/metadata/video_1.0.0.yaml"
  region               = var.region
  project              = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# Cloud Functions for Video Processing Pipeline
# =============================================================================

# Primary video processing function triggered by Cloud Storage uploads
resource "google_cloudfunctions2_function" "video_processor" {
  name        = "video-processor-${local.random_suffix}"
  location    = var.region
  project     = var.project_id
  description = "Processes uploaded videos and triggers analytics workflows"
  
  build_config {
    runtime     = "python39"
    entry_point = "process_video"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_sources["video-processor"].name
      }
    }
    
    environment_variables = {
      BUILD_CONFIG_ENV = "production"
    }
  }
  
  service_config {
    max_instance_count               = var.max_instances
    min_instance_count              = var.min_instances
    available_memory                = "1Gi"
    timeout_seconds                 = 540
    max_instance_request_concurrency = 1
    available_cpu                   = "1"
    
    environment_variables = {
      PROJECT_ID      = var.project_id
      REGION         = var.region
      RESULTS_BUCKET = google_storage_bucket.analytics_results.name
      DATASET_ID     = google_vertex_ai_dataset.video_dataset.name
    }
    
    service_account_email          = google_service_account.function_sa.email
    ingress_settings              = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }
  
  # Event trigger for Cloud Storage uploads
  event_trigger {
    trigger_region        = var.region
    event_type           = "google.cloud.storage.object.v1.finalized"
    retry_policy         = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.function_sa.email
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.video_content.name
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_sources,
    google_project_iam_member.function_permissions
  ]
}

# Advanced video analytics function with Vertex AI integration
resource "google_cloudfunctions2_function" "advanced_analytics" {
  name        = "advanced-analytics-${local.random_suffix}"
  location    = var.region
  project     = var.project_id
  description = "Advanced video analytics using Vertex AI Video Intelligence"
  
  build_config {
    runtime     = "python39"
    entry_point = "analyze_video_content"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_sources["advanced-analytics"].name
      }
    }
    
    environment_variables = {
      BUILD_CONFIG_ENV = "production"
    }
  }
  
  service_config {
    max_instance_count               = var.max_instances
    min_instance_count              = 0
    available_memory                = "2Gi"
    timeout_seconds                 = 540
    max_instance_request_concurrency = 1
    available_cpu                   = "2"
    
    environment_variables = {
      PROJECT_ID      = var.project_id
      REGION         = var.region
      RESULTS_BUCKET = google_storage_bucket.analytics_results.name
      DATASET_ID     = google_vertex_ai_dataset.video_dataset.name
    }
    
    service_account_email          = google_service_account.function_sa.email
    ingress_settings              = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }
  
  # Event trigger for video processing requests
  event_trigger {
    trigger_region        = var.region
    event_type           = "google.cloud.storage.object.v1.finalized"
    retry_policy         = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.function_sa.email
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.video_content.name
    }
    
    # Filter for video files only
    event_filters {
      attribute = "name"
      value     = "*.{mp4,mov,avi,mkv,webm}"
      operator  = "match-path-pattern"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_sources,
    google_project_iam_member.function_permissions
  ]
}

# Results processing function for analytics insights
resource "google_cloudfunctions2_function" "results_processor" {
  name        = "results-processor-${local.random_suffix}"
  location    = var.region
  project     = var.project_id
  description = "Processes completed video analytics results and generates insights"
  
  build_config {
    runtime     = "python39"
    entry_point = "process_analytics_results"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_sources["results-processor"].name
      }
    }
    
    environment_variables = {
      BUILD_CONFIG_ENV = "production"
    }
  }
  
  service_config {
    max_instance_count               = var.max_instances
    min_instance_count              = 0
    available_memory                = "1Gi"
    timeout_seconds                 = 300
    max_instance_request_concurrency = 10
    available_cpu                   = "1"
    
    environment_variables = {
      PROJECT_ID      = var.project_id
      REGION         = var.region
      CONTENT_BUCKET = google_storage_bucket.video_content.name
    }
    
    service_account_email          = google_service_account.function_sa.email
    ingress_settings              = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }
  
  # Event trigger for analytics results
  event_trigger {
    trigger_region        = var.region
    event_type           = "google.cloud.storage.object.v1.finalized"
    retry_policy         = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.function_sa.email
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.analytics_results.name
    }
    
    # Filter for analysis result files
    event_filters {
      attribute = "name"
      value     = "analysis/*_analysis.json"
      operator  = "match-path-pattern"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_sources,
    google_project_iam_member.function_permissions
  ]
}

# =============================================================================
# Media CDN Configuration (Edge Caching)
# =============================================================================

# Backend bucket for Media CDN
resource "google_compute_backend_bucket" "video_backend" {
  name        = "video-cdn-backend-${local.random_suffix}"
  project     = var.project_id
  bucket_name = google_storage_bucket.video_content.name
  description = "Backend bucket for video content delivery via Media CDN"
  
  # Enable Cloud CDN
  enable_cdn = true
  
  cdn_policy {
    cache_mode                   = local.media_cdn_config.cache_mode
    default_ttl                 = local.media_cdn_config.default_ttl
    max_ttl                     = local.media_cdn_config.max_ttl
    negative_caching            = local.media_cdn_config.negative_caching
    negative_caching_policy {
      code = 404
      ttl  = local.media_cdn_config.negative_caching_ttl
    }
    negative_caching_policy {
      code = 410
      ttl  = local.media_cdn_config.negative_caching_ttl
    }
    
    # Cache key policy for video content
    cache_key_policy {
      include_host         = true
      include_protocol     = true
      include_query_string = false
    }
    
    # Serve stale content while revalidating
    serve_while_stale = 86400  # 24 hours
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket.video_content
  ]
}

# URL map for Media CDN
resource "google_compute_url_map" "video_cdn" {
  name            = "video-cdn-${local.random_suffix}"
  project         = var.project_id
  description     = "URL map for video content delivery"
  default_service = google_compute_backend_bucket.video_backend.id
  
  # Path-based routing for different content types
  path_matcher {
    name            = "video-paths"
    default_service = google_compute_backend_bucket.video_backend.id
    
    path_rule {
      paths   = ["/videos/*"]
      service = google_compute_backend_bucket.video_backend.id
    }
    
    path_rule {
      paths   = ["/thumbnails/*"]
      service = google_compute_backend_bucket.video_backend.id
    }
  }
  
  host_rule {
    hosts        = ["*"]
    path_matcher = "video-paths"
  }
}

# HTTPS proxy for secure delivery
resource "google_compute_target_https_proxy" "video_cdn_proxy" {
  name    = "video-cdn-proxy-${local.random_suffix}"
  project = var.project_id
  url_map = google_compute_url_map.video_cdn.id
  
  # Use Google-managed SSL certificate
  ssl_certificates = [google_compute_managed_ssl_certificate.video_cdn_cert.id]
}

# Managed SSL certificate
resource "google_compute_managed_ssl_certificate" "video_cdn_cert" {
  name    = "video-cdn-cert-${local.random_suffix}"
  project = var.project_id
  
  managed {
    domains = [var.cdn_domain_name]
  }
  
  # Certificate lifecycle management
  lifecycle {
    create_before_destroy = true
  }
}

# Global forwarding rule for HTTPS traffic
resource "google_compute_global_forwarding_rule" "video_cdn_https" {
  name       = "video-cdn-https-${local.random_suffix}"
  project    = var.project_id
  target     = google_compute_target_https_proxy.video_cdn_proxy.id
  port_range = "443"
  ip_address = google_compute_global_address.video_cdn_ip.id
}

# Global HTTP to HTTPS redirect
resource "google_compute_url_map" "video_cdn_redirect" {
  name    = "video-cdn-redirect-${local.random_suffix}"
  project = var.project_id
  
  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "video_cdn_http_proxy" {
  name    = "video-cdn-http-proxy-${local.random_suffix}"
  project = var.project_id
  url_map = google_compute_url_map.video_cdn_redirect.id
}

resource "google_compute_global_forwarding_rule" "video_cdn_http" {
  name       = "video-cdn-http-${local.random_suffix}"
  project    = var.project_id
  target     = google_compute_target_http_proxy.video_cdn_http_proxy.id
  port_range = "80"
  ip_address = google_compute_global_address.video_cdn_ip.id
}

# Reserved global IP address for CDN
resource "google_compute_global_address" "video_cdn_ip" {
  name         = "video-cdn-ip-${local.random_suffix}"
  project      = var.project_id
  address_type = "EXTERNAL"
  description  = "Global IP address for video CDN"
}

# =============================================================================
# Monitoring and Alerting
# =============================================================================

# Cloud Monitoring notification channel
resource "google_monitoring_notification_channel" "email" {
  count        = var.notification_email != "" ? 1 : 0
  display_name = "Video Analytics Email Alerts"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alert policy for function failures
resource "google_monitoring_alert_policy" "function_failures" {
  count               = var.enable_monitoring ? 1 : 0
  display_name        = "Video Analytics Function Failures"
  project             = var.project_id
  combiner           = "OR"
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
  
  conditions {
    display_name = "Cloud Function Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\" AND metric.label.status=\"error\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  alert_strategy {
    auto_close = "1800s"  # 30 minutes
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alert policy for high storage usage
resource "google_monitoring_alert_policy" "storage_usage" {
  count               = var.enable_monitoring ? 1 : 0
  display_name        = "High Storage Usage"
  project             = var.project_id
  combiner           = "OR"
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
  
  conditions {
    display_name = "Storage Usage Threshold"
    
    condition_threshold {
      filter          = "resource.type=\"gcs_bucket\" AND metric.type=\"storage.googleapis.com/storage/total_bytes\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.storage_alert_threshold_gb * 1073741824  # Convert GB to bytes
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner  = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields     = ["resource.label.bucket_name"]
      }
    }
  }
  
  alert_strategy {
    auto_close = "3600s"  # 1 hour
  }
  
  depends_on = [google_project_service.required_apis]
}