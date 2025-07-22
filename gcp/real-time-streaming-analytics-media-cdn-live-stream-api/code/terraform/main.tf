# GCP Real-Time Streaming Analytics Infrastructure
# This configuration deploys a comprehensive streaming analytics solution using
# Cloud Storage, BigQuery, Cloud Functions, Pub/Sub, and Load Balancer for CDN

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Use provided suffix or generate random one
  suffix = var.random_suffix != "" ? var.random_suffix : random_id.suffix.hex
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    created_by  = "terraform"
    suffix      = local.suffix
  })
  
  # Resource names with suffix
  bucket_name         = "streaming-content-${local.suffix}"
  function_name       = "stream-analytics-processor-${local.suffix}"
  dataset_name        = "streaming_analytics_${local.suffix}"
  pubsub_topic        = "stream-events-${local.suffix}"
  dead_letter_topic   = "stream-events-dlq-${local.suffix}"
  service_account     = "streaming-analytics-sa-${local.suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "compute.googleapis.com",
    "networkservices.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com"
  ])

  project = var.project_id
  service = each.key

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Service Account for streaming analytics components
resource "google_service_account" "streaming_analytics" {
  account_id   = local.service_account
  display_name = "Streaming Analytics Service Account"
  description  = "Service account for streaming analytics Cloud Functions and other components"
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for the service account
resource "google_project_iam_member" "streaming_analytics_roles" {
  for_each = toset([
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/pubsub.subscriber",
    "roles/pubsub.publisher",
    "roles/storage.objectViewer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.streaming_analytics.email}"
}

# Cloud Storage bucket for video content
resource "google_storage_bucket" "streaming_content" {
  name          = local.bucket_name
  location      = var.region
  storage_class = var.storage_class
  
  # Security settings
  uniform_bucket_level_access = var.enable_uniform_bucket_access
  public_access_prevention   = var.enable_public_access_prevention ? "enforced" : "inherited"
  
  # Versioning
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age_nearline
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age_delete
    }
    action {
      type = "Delete"
    }
  }
  
  # CORS configuration for web access
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["Content-Type", "Access-Control-Allow-Origin"]
    max_age_seconds = 3600
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Grant service account access to the bucket
resource "google_storage_bucket_iam_member" "streaming_content_access" {
  bucket = google_storage_bucket.streaming_content.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.streaming_analytics.email}"
}

# BigQuery dataset for analytics
resource "google_bigquery_dataset" "streaming_analytics" {
  dataset_id                  = local.dataset_name
  friendly_name              = "Streaming Analytics Dataset"
  description                = "Dataset for real-time streaming analytics and performance metrics"
  location                   = var.bigquery_location
  default_table_expiration_ms = var.bigquery_table_expiration_days * 24 * 60 * 60 * 1000
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery table for streaming events
resource "google_bigquery_table" "streaming_events" {
  dataset_id = google_bigquery_dataset.streaming_analytics.dataset_id
  table_id   = "streaming_events"
  
  description = "Real-time streaming events and viewer engagement metrics"
  
  # Time partitioning for performance and cost optimization
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
  
  # Clustering for query performance
  clustering = ["stream_id", "event_type", "location"]
  
  # Schema definition for streaming events
  schema = jsonencode([
    {
      name        = "timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Event timestamp"
    },
    {
      name        = "event_type"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Type of streaming event"
    },
    {
      name        = "viewer_id"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Unique viewer identifier"
    },
    {
      name        = "session_id"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Viewing session identifier"
    },
    {
      name        = "stream_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Live stream identifier"
    },
    {
      name        = "quality"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Video quality level"
    },
    {
      name        = "buffer_health"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Buffer health ratio (0.0 to 1.0)"
    },
    {
      name        = "latency_ms"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Stream latency in milliseconds"
    },
    {
      name        = "location"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Viewer geographic location"
    },
    {
      name        = "user_agent"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Client user agent string"
    },
    {
      name        = "bitrate"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Stream bitrate in bps"
    },
    {
      name        = "resolution"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Video resolution"
    },
    {
      name        = "cdn_cache_status"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "CDN cache hit/miss status"
    },
    {
      name        = "edge_location"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "CDN edge location"
    }
  ])
  
  labels = local.common_labels
}

# BigQuery table for CDN access logs
resource "google_bigquery_table" "cdn_access_logs" {
  dataset_id = google_bigquery_dataset.streaming_analytics.dataset_id
  table_id   = "cdn_access_logs"
  
  description = "CDN access logs and performance metrics"
  
  # Time partitioning
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
  
  # Clustering for query performance
  clustering = ["edge_location", "cache_status", "response_code"]
  
  # Schema for CDN access logs
  schema = jsonencode([
    {
      name        = "timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Request timestamp"
    },
    {
      name        = "client_ip"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Client IP address"
    },
    {
      name        = "request_method"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "HTTP request method"
    },
    {
      name        = "request_uri"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Requested URI path"
    },
    {
      name        = "response_code"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "HTTP response status code"
    },
    {
      name        = "response_size"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Response size in bytes"
    },
    {
      name        = "cache_status"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Cache hit/miss status"
    },
    {
      name        = "edge_location"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "CDN edge server location"
    },
    {
      name        = "user_agent"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Client user agent"
    },
    {
      name        = "referer"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "HTTP referer header"
    },
    {
      name        = "latency_ms"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Response latency in milliseconds"
    }
  ])
  
  labels = local.common_labels
}

# Pub/Sub topic for streaming events
resource "google_pubsub_topic" "stream_events" {
  name = local.pubsub_topic
  
  message_retention_duration = var.pubsub_message_retention_duration
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Dead letter topic for failed message processing
resource "google_pubsub_topic" "dead_letter" {
  name = local.dead_letter_topic
  
  message_retention_duration = var.pubsub_message_retention_duration
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create source archive for Cloud Function
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      dataset_name = local.dataset_name
      project_id   = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.suffix}.zip"
  bucket = google_storage_bucket.streaming_content.name
  source = data.archive_file.function_source.output_path
  
  # Ensure the function is redeployed when source changes
  depends_on = [data.archive_file.function_source]
}

# Cloud Function for real-time analytics processing (2nd Gen)
resource "google_cloudfunctions2_function" "stream_processor" {
  name        = local.function_name
  location    = var.region
  description = "Processes streaming events and stores analytics data"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "process_streaming_event"
    
    source {
      storage_source {
        bucket = google_storage_bucket.streaming_content.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = var.function_max_instances
    min_instance_count = 0
    available_memory   = var.function_memory
    timeout_seconds    = var.function_timeout
    
    # Environment variables for function configuration
    environment_variables = {
      PROJECT_ID   = var.project_id
      DATASET_NAME = local.dataset_name
      LOG_LEVEL    = var.log_level
      REGION       = var.region
    }
    
    # Service account for function execution
    service_account_email = google_service_account.streaming_analytics.email
    
    # Enable all traffic to latest revision
    ingress_settings = "ALLOW_INTERNAL_ONLY"
  }
  
  # Event trigger for Pub/Sub messages
  event_trigger {
    trigger_region        = var.region
    event_type           = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic         = google_pubsub_topic.stream_events.id
    retry_policy         = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.streaming_analytics.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# Pub/Sub subscription for BigQuery streaming inserts
resource "google_pubsub_subscription" "bq_subscription" {
  name  = "${local.pubsub_topic}-bq-subscription"
  topic = google_pubsub_topic.stream_events.name
  
  ack_deadline_seconds       = var.pubsub_ack_deadline_seconds
  message_retention_duration = "604800s" # 7 days
  
  # Dead letter policy
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = var.dead_letter_max_delivery_attempts
  }
  
  # Retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Enable message ordering
  enable_message_ordering = false
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Backend bucket for CDN (Cloud Storage origin)
resource "google_compute_backend_bucket" "streaming_origin" {
  name        = "streaming-origin-${local.suffix}"
  description = "Backend bucket for streaming content CDN"
  bucket_name = google_storage_bucket.streaming_content.name
  
  # Enable Cloud CDN
  enable_cdn = true
  
  # CDN configuration
  cdn_policy {
    cache_mode                   = var.cdn_cache_mode
    default_ttl                 = var.cdn_default_ttl
    max_ttl                     = var.cdn_max_ttl
    client_ttl                  = var.cdn_default_ttl
    negative_caching            = true
    negative_caching_policy {
      code = 404
      ttl  = 60
    }
    
    # Cache key policy for streaming content
    cache_key_policy {
      include_host         = true
      include_protocol     = true
      include_query_string = false
      include_http_headers = ["Range"]
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# URL map for CDN routing
resource "google_compute_url_map" "streaming_cdn" {
  name        = "streaming-cdn-${local.suffix}"
  description = "URL map for streaming content CDN"
  
  default_service = google_compute_backend_bucket.streaming_origin.id
  
  # Host rules and path matchers for streaming content
  host_rule {
    hosts        = ["streaming-${local.suffix}.example.com"]
    path_matcher = "streaming-matcher"
  }
  
  path_matcher {
    name            = "streaming-matcher"
    default_service = google_compute_backend_bucket.streaming_origin.id
    
    # Path rules for different content types
    path_rule {
      paths   = ["/live-stream/*"]
      service = google_compute_backend_bucket.streaming_origin.id
      
      route_action {
        # CORS policy for streaming content
        cors_policy {
          allow_origins      = ["*"]
          allow_methods      = ["GET", "HEAD", "OPTIONS"]
          allow_headers      = ["Content-Type", "Range", "Accept-Encoding"]
          expose_headers     = ["Content-Length", "Content-Range"]
          max_age            = 3600
          allow_credentials  = false
        }
      }
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Target HTTP proxy for CDN
resource "google_compute_target_http_proxy" "streaming_proxy" {
  name    = "streaming-proxy-${local.suffix}"
  url_map = google_compute_url_map.streaming_cdn.id
  
  depends_on = [google_project_service.required_apis]
}

# Global forwarding rule for CDN
resource "google_compute_global_forwarding_rule" "streaming_forwarding_rule" {
  name       = "streaming-forwarding-rule-${local.suffix}"
  target     = google_compute_target_http_proxy.streaming_proxy.id
  port_range = "80"
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery views for analytics insights
resource "google_bigquery_table" "viewer_engagement_metrics" {
  dataset_id = google_bigquery_dataset.streaming_analytics.dataset_id
  table_id   = "viewer_engagement_metrics"
  
  description = "Aggregated viewer engagement metrics"
  
  view {
    query = <<-EOF
      SELECT
        DATE(timestamp) as date,
        stream_id,
        COUNT(DISTINCT viewer_id) as unique_viewers,
        COUNT(DISTINCT session_id) as total_sessions,
        AVG(buffer_health) as avg_buffer_health,
        AVG(latency_ms) as avg_latency_ms,
        COUNT(CASE WHEN event_type = 'buffer_start' THEN 1 END) as buffer_events,
        COUNT(CASE WHEN event_type = 'quality_change' THEN 1 END) as quality_changes,
        COUNT(*) as total_events
      FROM `${var.project_id}.${local.dataset_name}.streaming_events`
      WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
      GROUP BY date, stream_id
      ORDER BY date DESC, unique_viewers DESC
    EOF
    use_legacy_sql = false
  }
  
  labels = local.common_labels
}

resource "google_bigquery_table" "cdn_performance_metrics" {
  dataset_id = google_bigquery_dataset.streaming_analytics.dataset_id
  table_id   = "cdn_performance_metrics"
  
  description = "CDN performance and caching metrics"
  
  view {
    query = <<-EOF
      SELECT
        edge_location,
        COUNT(*) as total_requests,
        COUNT(CASE WHEN response_code = 200 THEN 1 END) as successful_requests,
        COUNT(CASE WHEN cache_status = 'HIT' THEN 1 END) as cache_hits,
        ROUND(AVG(latency_ms), 2) as avg_response_latency,
        SUM(response_size) as total_bytes_served,
        ROUND(COUNT(CASE WHEN cache_status = 'HIT' THEN 1 END) * 100.0 / COUNT(*), 2) as cache_hit_ratio
      FROM `${var.project_id}.${local.dataset_name}.cdn_access_logs`
      WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
      GROUP BY edge_location
      ORDER BY total_requests DESC
    EOF
    use_legacy_sql = false
  }
  
  labels = local.common_labels
}