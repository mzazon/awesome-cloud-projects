# Multi-Language Content Optimization with Cloud Translation and Cloud Run Worker Pools
# This configuration deploys a complete serverless content optimization system

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique resource names with prefix and random suffix
  resource_suffix = lower(random_id.suffix.hex)
  
  # Storage bucket names (must be globally unique)
  source_bucket_name     = "${var.resource_prefix}-${var.source_bucket_name}-${local.resource_suffix}"
  translated_bucket_name = "${var.resource_prefix}-${var.translated_bucket_name}-${local.resource_suffix}"
  models_bucket_name     = "${var.resource_prefix}-${var.models_bucket_name}-${local.resource_suffix}"
  
  # Other resource names
  pubsub_topic_name      = "${var.resource_prefix}-${var.pubsub_topic_name}-${local.resource_suffix}"
  worker_pool_name       = "${var.resource_prefix}-${var.worker_pool_name}-${local.resource_suffix}"
  bigquery_dataset_name  = replace("${var.resource_prefix}_${var.bigquery_dataset_name}_${local.resource_suffix}", "-", "_")
  service_account_name   = "${var.resource_prefix}-${var.service_account_name}-${local.resource_suffix}"
  vpc_network_name       = "${var.resource_prefix}-${var.vpc_network_name}-${local.resource_suffix}"
  subnet_name           = "${var.resource_prefix}-${var.subnet_name}-${local.resource_suffix}"
  
  # Common labels with environment and resource suffix
  common_labels = merge(var.common_labels, {
    environment     = var.environment
    resource-suffix = local.resource_suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.additional_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when Terraform is destroyed
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create VPC Network for secure communication
resource "google_compute_network" "translation_network" {
  name                    = local.vpc_network_name
  auto_create_subnetworks = false
  mtu                     = 1460
  
  depends_on = [google_project_service.required_apis]
  
  labels = local.common_labels
}

# Create subnet for Cloud Run worker pool
resource "google_compute_subnetwork" "translation_subnet" {
  name          = local.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.translation_network.id
  
  # Enable private Google access for accessing Google APIs without external IPs
  private_ip_google_access = var.enable_private_google_access
  
  # Configure flow logs if enabled
  dynamic "log_config" {
    for_each = var.enable_vpc_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_10_MIN"
      flow_sampling        = 0.5
      metadata            = "INCLUDE_ALL_METADATA"
    }
  }
}

# Create Cloud Storage bucket for source content
resource "google_storage_bucket" "source_content" {
  name     = local.source_bucket_name
  location = var.bucket_location
  
  # Enable versioning for content management
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
  
  # Security configuration
  uniform_bucket_level_access = true
  
  labels = merge(local.common_labels, {
    purpose = "source-content"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for translated content
resource "google_storage_bucket" "translated_content" {
  name     = local.translated_bucket_name
  location = var.bucket_location
  
  # Configure storage class for cost optimization
  storage_class = var.bucket_storage_class
  
  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 180
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
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
  
  # Security configuration
  uniform_bucket_level_access = true
  
  labels = merge(local.common_labels, {
    purpose = "translated-content"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for custom translation models
resource "google_storage_bucket" "custom_models" {
  name     = local.models_bucket_name
  location = var.bucket_location
  
  # Configure for model storage
  storage_class = "STANDARD"
  
  # Enable versioning for model management
  versioning {
    enabled = true
  }
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
  
  # Security configuration
  uniform_bucket_level_access = true
  
  labels = merge(local.common_labels, {
    purpose = "translation-models"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub topic for content processing events
resource "google_pubsub_topic" "content_processing" {
  name = local.pubsub_topic_name
  
  # Configure message retention
  message_retention_duration = var.pubsub_message_retention_duration
  
  labels = merge(local.common_labels, {
    purpose = "content-events"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for worker pool
resource "google_pubsub_subscription" "worker_subscription" {
  name  = "${local.pubsub_topic_name}-sub"
  topic = google_pubsub_topic.content_processing.name
  
  # Configure acknowledgment deadline
  ack_deadline_seconds = var.pubsub_subscription_ack_deadline
  
  # Configure message retention
  message_retention_duration = var.pubsub_message_retention_duration
  
  # Configure retry policy for reliable processing
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Configure dead letter policy
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  # Enable exactly once delivery for data consistency
  enable_exactly_once_delivery = true
  
  labels = merge(local.common_labels, {
    purpose = "worker-subscription"
  })
}

# Create dead letter topic for failed messages
resource "google_pubsub_topic" "dead_letter" {
  name = "${local.pubsub_topic_name}-dlq"
  
  labels = merge(local.common_labels, {
    purpose = "dead-letter-queue"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create dead letter subscription for monitoring
resource "google_pubsub_subscription" "dead_letter_subscription" {
  name  = "${local.pubsub_topic_name}-dlq-sub"
  topic = google_pubsub_topic.dead_letter.name
  
  # Longer retention for manual inspection
  message_retention_duration = "1209600s" # 14 days
  
  labels = merge(local.common_labels, {
    purpose = "dead-letter-monitoring"
  })
}

# Create BigQuery dataset for analytics
resource "google_bigquery_dataset" "content_analytics" {
  dataset_id  = local.bigquery_dataset_name
  location    = var.bigquery_dataset_location
  description = "Content optimization analytics dataset"
  
  # Configure default table expiration if specified
  dynamic "default_table_expiration_ms" {
    for_each = var.bigquery_table_expiration_ms != null ? [var.bigquery_table_expiration_ms] : []
    content {
      default_table_expiration_ms = default_table_expiration_ms.value
    }
  }
  
  labels = merge(local.common_labels, {
    purpose = "analytics"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create BigQuery table for engagement metrics
resource "google_bigquery_table" "engagement_metrics" {
  dataset_id = google_bigquery_dataset.content_analytics.dataset_id
  table_id   = "engagement_metrics"
  
  description = "Content engagement metrics for optimization"
  
  # Define schema for engagement data
  schema = jsonencode([
    {
      name = "content_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for content"
    },
    {
      name = "language"
      type = "STRING"
      mode = "REQUIRED"
      description = "Target language code"
    },
    {
      name = "region"
      type = "STRING"
      mode = "NULLABLE"
      description = "Geographic region"
    },
    {
      name = "engagement_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Content engagement score (0.0 - 1.0)"
    },
    {
      name = "translation_quality"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Translation quality score (0.0 - 1.0)"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Event timestamp"
    }
  ])
  
  # Configure clustering for performance
  clustering = ["language", "region"]
  
  labels = merge(local.common_labels, {
    purpose = "engagement-metrics"
  })
}

# Create BigQuery table for translation performance
resource "google_bigquery_table" "translation_performance" {
  dataset_id = google_bigquery_dataset.content_analytics.dataset_id
  table_id   = "translation_performance"
  
  description = "Translation operation performance metrics"
  
  # Define schema for performance data
  schema = jsonencode([
    {
      name = "batch_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Translation batch identifier"
    },
    {
      name = "source_language"
      type = "STRING"
      mode = "REQUIRED"
      description = "Source language code"
    },
    {
      name = "target_language"
      type = "STRING"
      mode = "REQUIRED"
      description = "Target language code"
    },
    {
      name = "content_type"
      type = "STRING"
      mode = "NULLABLE"
      description = "Type of content being translated"
    },
    {
      name = "processing_time"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Processing time in seconds"
    },
    {
      name = "quality_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Translation quality score"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Processing timestamp"
    }
  ])
  
  # Configure clustering for performance
  clustering = ["source_language", "target_language"]
  
  labels = merge(local.common_labels, {
    purpose = "translation-performance"
  })
}

# Create IAM service account for translation workers
resource "google_service_account" "translation_worker" {
  account_id   = local.service_account_name
  display_name = "Translation Worker Service Account"
  description  = "Service account for Cloud Run translation workers"
}

# Grant Translation API permissions
resource "google_project_iam_member" "translation_editor" {
  project = var.project_id
  role    = "roles/translate.editor"
  member  = "serviceAccount:${google_service_account.translation_worker.email}"
}

# Grant Cloud Storage permissions
resource "google_project_iam_member" "storage_object_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.translation_worker.email}"
}

# Grant BigQuery permissions
resource "google_project_iam_member" "bigquery_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.translation_worker.email}"
}

# Grant Pub/Sub subscriber permissions
resource "google_project_iam_member" "pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.translation_worker.email}"
}

# Grant monitoring permissions if enabled
resource "google_project_iam_member" "monitoring_writer" {
  count = var.enable_monitoring ? 1 : 0
  
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.translation_worker.email}"
}

# Grant logging permissions if enabled
resource "google_project_iam_member" "logging_writer" {
  count = var.enable_logging ? 1 : 0
  
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.translation_worker.email}"
}

# Create Cloud Build trigger for worker image
resource "google_cloudbuild_trigger" "worker_build" {
  count = var.container_image == "" ? 1 : 0
  
  name     = "${local.worker_pool_name}-build"
  location = var.region
  
  description = "Build trigger for translation worker container image"
  
  # Configure trigger from source repository
  source_to_build {
    uri       = "https://github.com/your-org/translation-worker"
    ref       = "refs/heads/main"
    repo_type = "GITHUB"
  }
  
  # Configure build steps
  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", 
        "gcr.io/${var.project_id}/translation-worker:latest",
        "."
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "gcr.io/${var.project_id}/translation-worker:latest"
      ]
    }
    
    images = ["gcr.io/${var.project_id}/translation-worker:latest"]
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Run Worker Pool for translation processing
resource "google_cloud_run_v2_job" "translation_worker_pool" {
  name     = local.worker_pool_name
  location = var.region
  
  template {
    # Configure job template
    template {
      # Configure container specification
      containers {
        image = var.container_image != "" ? var.container_image : "gcr.io/${var.project_id}/translation-worker:latest"
        
        # Resource configuration
        resources {
          limits = {
            cpu    = var.worker_pool_cpu
            memory = var.worker_pool_memory
          }
        }
        
        # Environment variables
        env {
          name  = "GOOGLE_CLOUD_PROJECT"
          value = var.project_id
        }
        
        env {
          name  = "GOOGLE_CLOUD_REGION"
          value = var.region
        }
        
        env {
          name  = "DATASET_NAME"
          value = local.bigquery_dataset_name
        }
        
        env {
          name  = "SOURCE_BUCKET"
          value = local.source_bucket_name
        }
        
        env {
          name  = "TRANSLATED_BUCKET"
          value = local.translated_bucket_name
        }
        
        env {
          name  = "MODELS_BUCKET"
          value = local.models_bucket_name
        }
        
        env {
          name  = "PUBSUB_SUBSCRIPTION"
          value = google_pubsub_subscription.worker_subscription.name
        }
      }
      
      # Service account configuration
      service_account = google_service_account.translation_worker.email
      
      # Configure max retries
      max_retries = 3
      
      # Configure timeout
      task_timeout = "3600s" # 1 hour
    }
    
    # Scaling configuration
    parallelism = var.worker_pool_min_instances
    task_count  = var.worker_pool_max_instances
  }
  
  labels = merge(local.common_labels, {
    purpose = "translation-worker-pool"
  })
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.translation_worker,
    google_pubsub_subscription.worker_subscription
  ]
}

# Create Cloud Scheduler job to trigger worker pool
resource "google_cloud_scheduler_job" "worker_trigger" {
  name        = "${local.worker_pool_name}-trigger"
  region      = var.region
  description = "Periodic trigger for translation worker pool"
  
  # Schedule to run every 5 minutes
  schedule  = "*/5 * * * *"
  time_zone = "UTC"
  
  # Configure retry policy
  retry_config {
    retry_count = 3
  }
  
  # Configure HTTP target to trigger Cloud Run job
  http_target {
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.translation_worker_pool.name}:run"
    http_method = "POST"
    
    # Configure authentication
    oauth_token {
      service_account_email = google_service_account.translation_worker.email
      scope                = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloud_run_v2_job.translation_worker_pool
  ]
}

# Create monitoring alert policies if monitoring is enabled
resource "google_monitoring_alert_policy" "worker_pool_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Translation Worker Pool Errors"
  combiner     = "OR"
  
  conditions {
    display_name = "High error rate in worker pool"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${google_cloud_run_v2_job.translation_worker_pool.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  # Configure notification channels (customize as needed)
  notification_channels = []
  
  depends_on = [google_project_service.required_apis]
}

# Create log sink for BigQuery analytics
resource "google_logging_project_sink" "translation_logs" {
  count = var.enable_logging ? 1 : 0
  
  name        = "${local.worker_pool_name}-logs"
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.content_analytics.dataset_id}"
  
  # Filter for translation worker logs
  filter = "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${google_cloud_run_v2_job.translation_worker_pool.name}\""
  
  # Grant BigQuery data editor role to the log sink's writer identity
  unique_writer_identity = true
}

# Grant BigQuery data editor to log sink
resource "google_project_iam_member" "log_sink_bigquery" {
  count = var.enable_logging ? 1 : 0
  
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.translation_logs[0].writer_identity
}