# ============================================================================
# Data Pipeline Recovery with Dataform and Cloud Tasks
# ============================================================================
#
# This Terraform configuration deploys a comprehensive data pipeline recovery
# system that automatically detects Dataform workflow failures and orchestrates
# intelligent remediation through Cloud Tasks and Cloud Functions.
#
# Architecture Components:
# - Dataform repository for ELT workflows
# - BigQuery datasets for data storage and monitoring
# - Cloud Tasks queue for reliable recovery task execution
# - Cloud Functions for pipeline controller, recovery worker, and notifications
# - Cloud Monitoring for failure detection and alerting
# - Pub/Sub for notification distribution
# - IAM service accounts with least privilege access
#
# ============================================================================

# Configure the Google Cloud Provider
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Data source for current project information
data "google_project" "current" {}

# Data source for compute default service account
data "google_compute_default_service_account" "default" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  resource_suffix    = random_id.suffix.hex
  dataform_repo     = "${var.dataform_repository_name}-${local.resource_suffix}"
  task_queue        = "${var.task_queue_name}-${local.resource_suffix}"
  dataset_name      = "${var.bigquery_dataset_name}_${local.resource_suffix}"
  controller_function = "${var.controller_function_name}-${local.resource_suffix}"
  worker_function    = "${var.worker_function_name}-${local.resource_suffix}"
  notify_function   = "${var.notification_function_name}-${local.resource_suffix}"
  pubsub_topic      = "${var.pubsub_topic_name}-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    solution    = "data-pipeline-recovery"
    managed_by  = "terraform"
    created     = timestamp()
  })
  
  # Service account email formats
  dataform_sa_email = "service-${data.google_project.current.number}@gcp-sa-dataform.iam.gserviceaccount.com"
}

# ============================================================================
# ENABLE REQUIRED GOOGLE CLOUD APIS
# ============================================================================

# Enable required Google Cloud APIs for the solution
resource "google_project_service" "required_apis" {
  for_each = toset([
    "dataform.googleapis.com",
    "cloudtasks.googleapis.com",
    "cloudfunctions.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com",
    "secretmanager.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent accidental deletion of critical APIs
  disable_dependent_services = false
  disable_on_destroy         = false

  timeouts {
    create = "30m"
    update = "40m"
  }
}

# ============================================================================
# IAM SERVICE ACCOUNTS AND PERMISSIONS
# ============================================================================

# Service account for Cloud Functions
resource "google_service_account" "pipeline_controller_sa" {
  account_id   = "pipeline-controller-${local.resource_suffix}"
  display_name = "Pipeline Controller Service Account"
  description  = "Service account for pipeline controller and recovery functions"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Grant necessary permissions to the pipeline controller service account
resource "google_project_iam_member" "controller_permissions" {
  for_each = toset([
    "roles/dataform.admin",
    "roles/cloudtasks.admin",
    "roles/logging.logWriter",
    "roles/monitoring.alertPolicyEditor",
    "roles/pubsub.publisher",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.pipeline_controller_sa.email}"

  depends_on = [google_service_account.pipeline_controller_sa]
}

# ============================================================================
# BIGQUERY INFRASTRUCTURE
# ============================================================================

# BigQuery dataset for pipeline data and monitoring
resource "google_bigquery_dataset" "pipeline_dataset" {
  dataset_id    = local.dataset_name
  friendly_name = "Pipeline Recovery Dataset"
  description   = "Dataset for data pipeline recovery demonstration and monitoring"
  location      = var.region
  project       = var.project_id

  # Data retention and lifecycle management
  default_table_expiration_ms = var.bigquery_table_expiration_days * 24 * 60 * 60 * 1000

  # Access controls
  access {
    role          = "OWNER"
    user_by_email = google_service_account.pipeline_controller_sa.email
  }

  access {
    role          = "WRITER"
    special_group = "projectWriters"
  }

  access {
    role          = "READER"
    special_group = "projectReaders"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_service_account.pipeline_controller_sa
  ]
}

# Source table for pipeline input data
resource "google_bigquery_table" "source_data" {
  dataset_id = google_bigquery_dataset.pipeline_dataset.dataset_id
  table_id   = "source_data"
  project    = var.project_id

  description = "Source table containing raw data for pipeline processing"

  schema = jsonencode([
    {
      name = "id"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Unique identifier for the record"
    },
    {
      name = "name"
      type = "STRING"
      mode = "REQUIRED"
      description = "Name field for the record"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when the record was created"
    },
    {
      name = "status"
      type = "STRING"
      mode = "REQUIRED"
      description = "Processing status of the record"
    }
  ])

  labels = local.common_labels

  depends_on = [google_bigquery_dataset.pipeline_dataset]
}

# Target table for processed pipeline output
resource "google_bigquery_table" "processed_data" {
  dataset_id = google_bigquery_dataset.pipeline_dataset.dataset_id
  table_id   = "processed_data"
  project    = var.project_id

  description = "Target table containing processed data from pipeline"

  schema = jsonencode([
    {
      name = "id"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Unique identifier for the record"
    },
    {
      name = "processed_name"
      type = "STRING"
      mode = "REQUIRED"
      description = "Processed name field"
    },
    {
      name = "processing_time"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when the record was processed"
    },
    {
      name = "batch_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Batch identifier for processing group"
    }
  ])

  labels = local.common_labels

  depends_on = [google_bigquery_dataset.pipeline_dataset]
}

# ============================================================================
# DATAFORM REPOSITORY CONFIGURATION
# ============================================================================

# Dataform repository for ELT workflow definitions
resource "google_dataform_repository" "pipeline_repo" {
  provider = google-beta

  name         = local.dataform_repo
  region       = var.region
  project      = var.project_id
  display_name = "Pipeline Recovery Repository"

  # Workspace compilation overrides for consistent environments
  workspace_compilation_overrides {
    default_database = var.project_id
    schema_suffix    = "_${var.environment}"
    table_prefix     = "${var.environment}_"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_bigquery_dataset.pipeline_dataset
  ]
}

# ============================================================================
# PUB/SUB NOTIFICATION INFRASTRUCTURE
# ============================================================================

# Pub/Sub topic for pipeline notifications and recovery events
resource "google_pubsub_topic" "pipeline_notifications" {
  name    = local.pubsub_topic
  project = var.project_id

  # Message retention for reliability
  message_retention_duration = "604800s" # 7 days

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for notification processing
resource "google_pubsub_subscription" "notification_subscription" {
  name    = "${local.pubsub_topic}-subscription"
  topic   = google_pubsub_topic.pipeline_notifications.name
  project = var.project_id

  # Message delivery configuration
  ack_deadline_seconds = 20
  retain_acked_messages = false
  message_retention_duration = "604800s" # 7 days

  # Dead letter queue configuration
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter_topic.id
    max_delivery_attempts = 5
  }

  # Exponential backoff retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  labels = local.common_labels

  depends_on = [google_pubsub_topic.pipeline_notifications]
}

# Dead letter topic for failed notification processing
resource "google_pubsub_topic" "dead_letter_topic" {
  name    = "${local.pubsub_topic}-dead-letter"
  project = var.project_id

  message_retention_duration = "604800s" # 7 days

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# CLOUD TASKS QUEUE FOR RECOVERY ORCHESTRATION
# ============================================================================

# Cloud Tasks queue for reliable recovery task execution
resource "google_cloud_tasks_queue" "recovery_queue" {
  name     = local.task_queue
  location = var.region
  project  = var.project_id

  # Rate limiting configuration to prevent overwhelming systems
  rate_limits {
    max_dispatches_per_second = var.task_queue_max_dispatches_per_second
    max_concurrent_dispatches = var.task_queue_max_concurrent_dispatches
  }

  # Comprehensive retry configuration for reliability
  retry_config {
    max_attempts       = var.task_queue_max_attempts
    max_retry_duration = "${var.task_queue_max_retry_duration_hours}h"
    min_backoff        = "${var.task_queue_min_backoff_seconds}s"
    max_backoff        = "${var.task_queue_max_backoff_seconds}s"
    max_doublings      = var.task_queue_max_doublings
  }

  # Enhanced logging for observability
  stackdriver_logging_config {
    sampling_ratio = var.task_queue_logging_sampling_ratio
  }

  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# CLOUD FUNCTIONS FOR PIPELINE ORCHESTRATION
# ============================================================================

# Archive the pipeline controller function source code
data "archive_file" "controller_function_source" {
  type        = "zip"
  output_path = "/tmp/controller-function-${local.resource_suffix}.zip"
  source {
    content = templatefile("${path.module}/function_code/controller/index.js", {
      project_id = var.project_id
      region     = var.region
      task_queue = local.task_queue
    })
    filename = "index.js"
  }
  source {
    content = templatefile("${path.module}/function_code/controller/package.json", {})
    filename = "package.json"
  }
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source_bucket" {
  name     = "pipeline-recovery-functions-${local.resource_suffix}"
  location = var.region
  project  = var.project_id

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Security configuration
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Upload controller function source to Cloud Storage
resource "google_storage_bucket_object" "controller_function_source" {
  name   = "controller-function-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.controller_function_source.output_path

  depends_on = [
    google_storage_bucket.function_source_bucket,
    data.archive_file.controller_function_source
  ]
}

# Pipeline Controller Cloud Function (2nd Generation)
resource "google_cloudfunctions2_function" "pipeline_controller" {
  name     = local.controller_function
  location = var.region
  project  = var.project_id

  description = "Pipeline failure detection and recovery orchestration function"

  build_config {
    runtime     = "nodejs18"
    entry_point = "handlePipelineAlert"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.controller_function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = var.function_min_instances
    available_memory      = "256Mi"
    timeout_seconds       = 540
    ingress_settings      = "ALLOW_ALL"
    all_traffic_on_latest_revision = true

    # Service account configuration
    service_account_email = google_service_account.pipeline_controller_sa.email

    # Environment variables for function configuration
    environment_variables = {
      PROJECT_ID              = var.project_id
      REGION                  = var.region
      TASK_QUEUE              = local.task_queue
      DATAFORM_REPO          = local.dataform_repo
      NOTIFICATION_TOPIC     = local.pubsub_topic
      WORKER_FUNCTION_URL    = "" # Will be updated after worker function deployment
    }
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_service_account.pipeline_controller_sa,
    google_project_iam_member.controller_permissions,
    google_storage_bucket_object.controller_function_source,
    google_cloud_tasks_queue.recovery_queue
  ]
}

# Archive the recovery worker function source code
data "archive_file" "worker_function_source" {
  type        = "zip"
  output_path = "/tmp/worker-function-${local.resource_suffix}.zip"
  source {
    content = templatefile("${path.module}/function_code/worker/index.js", {
      project_id     = var.project_id
      region         = var.region
      dataform_repo  = local.dataform_repo
      pubsub_topic   = local.pubsub_topic
    })
    filename = "index.js"
  }
  source {
    content = templatefile("${path.module}/function_code/worker/package.json", {})
    filename = "package.json"
  }
}

# Upload worker function source to Cloud Storage
resource "google_storage_bucket_object" "worker_function_source" {
  name   = "worker-function-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.worker_function_source.output_path

  depends_on = [
    google_storage_bucket.function_source_bucket,
    data.archive_file.worker_function_source
  ]
}

# Recovery Worker Cloud Function (2nd Generation)
resource "google_cloudfunctions2_function" "recovery_worker" {
  name     = local.worker_function
  location = var.region
  project  = var.project_id

  description = "Pipeline recovery execution and Dataform workflow retry function"

  build_config {
    runtime     = "nodejs18"
    entry_point = "executeRecovery"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.worker_function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = var.function_min_instances
    available_memory      = "512Mi"
    timeout_seconds       = 540
    ingress_settings      = "ALLOW_ALL"
    all_traffic_on_latest_revision = true

    # Service account configuration
    service_account_email = google_service_account.pipeline_controller_sa.email

    # Environment variables for function configuration
    environment_variables = {
      PROJECT_ID         = var.project_id
      REGION             = var.region
      DATAFORM_REPO      = local.dataform_repo
      NOTIFICATION_TOPIC = local.pubsub_topic
      DATASET_NAME       = local.dataset_name
    }
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_service_account.pipeline_controller_sa,
    google_project_iam_member.controller_permissions,
    google_storage_bucket_object.worker_function_source,
    google_dataform_repository.pipeline_repo
  ]
}

# Archive the notification handler function source code
data "archive_file" "notification_function_source" {
  type        = "zip"
  output_path = "/tmp/notification-function-${local.resource_suffix}.zip"
  source {
    content = templatefile("${path.module}/function_code/notifications/index.js", {
      notification_recipients = join(",", var.notification_recipients)
    })
    filename = "index.js"
  }
  source {
    content = templatefile("${path.module}/function_code/notifications/package.json", {})
    filename = "package.json"
  }
}

# Upload notification function source to Cloud Storage
resource "google_storage_bucket_object" "notification_function_source" {
  name   = "notification-function-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.notification_function_source.output_path

  depends_on = [
    google_storage_bucket.function_source_bucket,
    data.archive_file.notification_function_source
  ]
}

# Notification Handler Cloud Function (2nd Generation)
resource "google_cloudfunctions2_function" "notification_handler" {
  name     = local.notify_function
  location = var.region
  project  = var.project_id

  description = "Pipeline recovery notification and stakeholder communication function"

  build_config {
    runtime     = "nodejs18"
    entry_point = "handleNotification"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.notification_function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = var.function_min_instances
    available_memory      = "256Mi"
    timeout_seconds       = 300
    ingress_settings      = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true

    # Service account configuration
    service_account_email = google_service_account.pipeline_controller_sa.email

    # Environment variables for function configuration
    environment_variables = {
      PROJECT_ID               = var.project_id
      REGION                   = var.region
      NOTIFICATION_RECIPIENTS  = join(",", var.notification_recipients)
    }
  }

  # Pub/Sub trigger for notification processing
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.pipeline_notifications.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_service_account.pipeline_controller_sa,
    google_project_iam_member.controller_permissions,
    google_storage_bucket_object.notification_function_source,
    google_pubsub_topic.pipeline_notifications
  ]
}

# ============================================================================
# CLOUD MONITORING AND ALERTING
# ============================================================================

# Notification channel for webhook alerts to pipeline controller
resource "google_monitoring_notification_channel" "webhook_channel" {
  display_name = "Pipeline Recovery Webhook"
  type         = "webhook_tokenauth"
  project      = var.project_id

  labels = {
    url = google_cloudfunctions2_function.pipeline_controller.service_config[0].uri
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.pipeline_controller
  ]
}

# Log-based metric for tracking Dataform pipeline failures
resource "google_logging_metric" "pipeline_failure_metric" {
  name    = "dataform_pipeline_failures_${local.resource_suffix}"
  project = var.project_id

  description = "Tracks Dataform pipeline execution failures for automated recovery"
  
  filter = <<-EOT
    resource.type="dataform_repository"
    severity>=ERROR
    jsonPayload.status="FAILED"
  EOT

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Dataform Pipeline Failures"
  }

  depends_on = [
    google_project_service.required_apis,
    google_dataform_repository.pipeline_repo
  ]
}

# Alert policy for automatic pipeline failure detection
resource "google_monitoring_alert_policy" "pipeline_failure_alert" {
  display_name = "Dataform Pipeline Failure Alert - ${local.resource_suffix}"
  project      = var.project_id

  description = "Monitors Dataform pipelines for failures and triggers automated recovery"

  # Combine log-based and error rate conditions
  combiner = "OR"

  conditions {
    display_name = "Dataform workflow failure condition"
    
    condition_threshold {
      filter          = "resource.type=\"dataform_repository\" AND severity>=ERROR"
      duration        = "60s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  # Notification configuration
  notification_channels = [
    google_monitoring_notification_channel.webhook_channel.name
  ]

  # Alert strategy
  alert_strategy {
    auto_close = "1800s" # 30 minutes
  }

  # Documentation for on-call teams
  documentation {
    content = "Dataform pipeline failure detected. Automated recovery has been initiated. Monitor recovery progress in Cloud Functions logs."
  }

  enabled = var.enable_monitoring_alerts

  depends_on = [
    google_project_service.required_apis,
    google_monitoring_notification_channel.webhook_channel,
    google_logging_metric.pipeline_failure_metric
  ]
}

# ============================================================================
# UPDATE CONTROLLER FUNCTION WITH WORKER URL
# ============================================================================

# Update the pipeline controller function with the worker function URL
resource "google_cloudfunctions2_function" "pipeline_controller_updated" {
  name     = local.controller_function
  location = var.region
  project  = var.project_id

  description = "Pipeline failure detection and recovery orchestration function"

  build_config {
    runtime     = "nodejs18"
    entry_point = "handlePipelineAlert"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.controller_function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = var.function_min_instances
    available_memory      = "256Mi"
    timeout_seconds       = 540
    ingress_settings      = "ALLOW_ALL"
    all_traffic_on_latest_revision = true

    # Service account configuration
    service_account_email = google_service_account.pipeline_controller_sa.email

    # Environment variables with worker function URL
    environment_variables = {
      PROJECT_ID              = var.project_id
      REGION                  = var.region
      TASK_QUEUE              = local.task_queue
      DATAFORM_REPO          = local.dataform_repo
      NOTIFICATION_TOPIC     = local.pubsub_topic
      WORKER_FUNCTION_URL    = google_cloudfunctions2_function.recovery_worker.service_config[0].uri
    }
  }

  labels = local.common_labels

  depends_on = [
    google_cloudfunctions2_function.pipeline_controller,
    google_cloudfunctions2_function.recovery_worker
  ]
}