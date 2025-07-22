# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming
locals {
  resource_suffix = random_id.suffix.hex
  common_labels = merge(var.labels, {
    environment = var.environment
    region      = var.region
  })
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "healthcare.googleapis.com",
    "cloudtasks.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com"
  ])
  
  service = each.value
  
  disable_on_destroy = false
}

# Healthcare Dataset
resource "google_healthcare_dataset" "healthcare_dataset" {
  provider = google-beta
  
  name     = "${var.resource_prefix}-dataset-${local.resource_suffix}"
  location = var.healthcare_dataset_location
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# FHIR Store
resource "google_healthcare_fhir_store" "fhir_store" {
  provider = google-beta
  
  name    = "${var.resource_prefix}-fhir-store-${local.resource_suffix}"
  dataset = google_healthcare_dataset.healthcare_dataset.id
  version = var.fhir_version
  
  enable_update_create                = var.enable_update_create
  disable_referential_integrity       = var.disable_referential_integrity
  disable_resource_versioning         = false
  enable_history_import               = false
  
  labels = local.common_labels
  
  # Configure Pub/Sub notifications
  notification_config {
    pubsub_topic = google_pubsub_topic.fhir_changes.id
  }
  
  depends_on = [
    google_healthcare_dataset.healthcare_dataset,
    google_pubsub_topic.fhir_changes
  ]
}

# Pub/Sub Topic for FHIR Store Changes
resource "google_pubsub_topic" "fhir_changes" {
  name = "${var.resource_prefix}-fhir-changes-${local.resource_suffix}"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Pub/Sub Subscription for FHIR Events
resource "google_pubsub_subscription" "fhir_events_subscription" {
  name  = "${var.resource_prefix}-fhir-events-sub-${local.resource_suffix}"
  topic = google_pubsub_topic.fhir_changes.name
  
  message_retention_duration = var.pubsub_message_retention_duration
  ack_deadline_seconds       = tonumber(replace(var.pubsub_ack_deadline, "s", ""))
  
  labels = local.common_labels
  
  depends_on = [google_pubsub_topic.fhir_changes]
}

# Cloud Storage Bucket for Compliance Artifacts
resource "google_storage_bucket" "compliance_bucket" {
  name          = "${var.resource_prefix}-${var.project_id}-${local.resource_suffix}"
  location      = var.region
  storage_class = var.storage_class
  
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  labels = local.common_labels
  
  # Lifecycle management for compliance retention
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_nearline
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_coldline
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Enable versioning for audit trail
  versioning {
    enabled = true
  }
  
  # Enable logging for compliance
  logging {
    log_bucket        = google_storage_bucket.compliance_bucket.name
    log_object_prefix = "access-logs/"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Tasks Queue for Compliance Processing
resource "google_cloud_tasks_queue" "compliance_queue" {
  name     = "${var.resource_prefix}-queue-${local.resource_suffix}"
  location = var.region
  
  rate_limits {
    max_dispatches_per_second = var.task_queue_max_dispatches_per_second
    max_concurrent_dispatches = var.task_queue_max_concurrent_dispatches
  }
  
  retry_config {
    max_attempts   = var.task_queue_max_attempts
    min_backoff    = var.task_queue_min_backoff
    max_backoff    = var.task_queue_max_backoff
    max_doublings  = 16
  }
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery Dataset for Compliance Analytics
resource "google_bigquery_dataset" "compliance_dataset" {
  dataset_id  = "healthcare_compliance_${replace(local.resource_suffix, "-", "_")}"
  location    = var.bigquery_dataset_location
  description = var.bigquery_dataset_description
  
  labels = local.common_labels
  
  # Enable deletion protection
  delete_contents_on_destroy = false
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery Table for Compliance Events
resource "google_bigquery_table" "compliance_events" {
  dataset_id          = google_bigquery_dataset.compliance_dataset.dataset_id
  table_id            = "compliance_events"
  deletion_protection = var.bigquery_table_deletion_protection
  
  labels = local.common_labels
  
  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "resource_name"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "event_type"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "compliance_status"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "validation_result"
      type = "JSON"
      mode = "NULLABLE"
    },
    {
      name = "risk_score"
      type = "INTEGER"
      mode = "NULLABLE"
    },
    {
      name = "message_id"
      type = "STRING"
      mode = "NULLABLE"
    }
  ])
  
  depends_on = [google_bigquery_dataset.compliance_dataset]
}

# BigQuery Table for Audit Trail
resource "google_bigquery_table" "audit_trail" {
  dataset_id          = google_bigquery_dataset.compliance_dataset.dataset_id
  table_id            = "audit_trail"
  deletion_protection = var.bigquery_table_deletion_protection
  
  labels = local.common_labels
  
  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "user_id"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "resource_type"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "operation"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "phi_accessed"
      type = "BOOLEAN"
      mode = "NULLABLE"
    },
    {
      name = "compliance_level"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "session_id"
      type = "STRING"
      mode = "NULLABLE"
    }
  ])
  
  depends_on = [google_bigquery_dataset.compliance_dataset]
}

# Service Account for Cloud Functions
resource "google_service_account" "compliance_function_sa" {
  account_id   = "${var.resource_prefix}-func-sa-${local.resource_suffix}"
  display_name = "Healthcare Compliance Function Service Account"
  description  = "Service account for healthcare compliance processing functions"
}

# IAM Bindings for Function Service Account
resource "google_project_iam_member" "function_sa_healthcare_admin" {
  project = var.project_id
  role    = "roles/healthcare.dataEditor"
  member  = "serviceAccount:${google_service_account.compliance_function_sa.email}"
}

resource "google_project_iam_member" "function_sa_pubsub_editor" {
  project = var.project_id
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${google_service_account.compliance_function_sa.email}"
}

resource "google_project_iam_member" "function_sa_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.compliance_function_sa.email}"
}

resource "google_project_iam_member" "function_sa_bigquery_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.compliance_function_sa.email}"
}

resource "google_project_iam_member" "function_sa_tasks_editor" {
  project = var.project_id
  role    = "roles/cloudtasks.editor"
  member  = "serviceAccount:${google_service_account.compliance_function_sa.email}"
}

resource "google_project_iam_member" "function_sa_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.compliance_function_sa.email}"
}

# Cloud Storage Bucket for Function Source Code
resource "google_storage_bucket" "function_source_bucket" {
  name          = "${var.resource_prefix}-functions-${var.project_id}-${local.resource_suffix}"
  location      = var.region
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Function Source Code Archive
data "archive_file" "compliance_function_source" {
  type        = "zip"
  output_path = "${path.module}/compliance_function_source.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/compliance_processor.py", {
      project_id    = var.project_id
      region        = var.region
      bucket_name   = google_storage_bucket.compliance_bucket.name
      dataset_id    = google_bigquery_dataset.compliance_dataset.dataset_id
      queue_name    = google_cloud_tasks_queue.compliance_queue.name
      random_suffix = local.resource_suffix
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_templates/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload Function Source to Cloud Storage
resource "google_storage_bucket_object" "compliance_function_source" {
  name   = "compliance_function_source_${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.compliance_function_source.output_path
  
  depends_on = [
    google_storage_bucket.function_source_bucket,
    data.archive_file.compliance_function_source
  ]
}

# Cloud Function for Compliance Processing
resource "google_cloudfunctions_function" "compliance_processor" {
  name        = "${var.resource_prefix}-processor-${local.resource_suffix}"
  region      = var.region
  description = "Healthcare compliance processing function"
  
  runtime     = var.function_runtime
  entry_point = "process_fhir_event"
  
  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  max_instances         = var.function_max_instances
  service_account_email = google_service_account.compliance_function_sa.email
  
  source_archive_bucket = google_storage_bucket.function_source_bucket.name
  source_archive_object = google_storage_bucket_object.compliance_function_source.name
  
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.fhir_changes.name
    
    failure_policy {
      retry = true
    }
  }
  
  environment_variables = {
    GCP_PROJECT    = var.project_id
    FUNCTION_REGION = var.region
    BUCKET_NAME    = google_storage_bucket.compliance_bucket.name
    DATASET_ID     = google_bigquery_dataset.compliance_dataset.dataset_id
    QUEUE_NAME     = google_cloud_tasks_queue.compliance_queue.name
    RANDOM_SUFFIX  = local.resource_suffix
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.compliance_function_sa,
    google_storage_bucket_object.compliance_function_source
  ]
}

# Audit Function Source Code Archive
data "archive_file" "audit_function_source" {
  type        = "zip"
  output_path = "${path.module}/audit_function_source.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/compliance_audit.py", {
      project_id    = var.project_id
      region        = var.region
      bucket_name   = google_storage_bucket.compliance_bucket.name
      dataset_id    = google_bigquery_dataset.compliance_dataset.dataset_id
      random_suffix = local.resource_suffix
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_templates/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload Audit Function Source to Cloud Storage
resource "google_storage_bucket_object" "audit_function_source" {
  name   = "audit_function_source_${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.audit_function_source.output_path
  
  depends_on = [
    google_storage_bucket.function_source_bucket,
    data.archive_file.audit_function_source
  ]
}

# Cloud Function for Compliance Audit
resource "google_cloudfunctions_function" "compliance_audit" {
  name        = "${var.resource_prefix}-audit-${local.resource_suffix}"
  region      = var.region
  description = "Healthcare compliance audit function"
  
  runtime     = var.function_runtime
  entry_point = "compliance_audit"
  
  available_memory_mb   = 1024
  timeout               = var.function_timeout
  max_instances         = 5
  service_account_email = google_service_account.compliance_function_sa.email
  
  source_archive_bucket = google_storage_bucket.function_source_bucket.name
  source_archive_object = google_storage_bucket_object.audit_function_source.name
  
  https_trigger {
    url = "https://${var.region}-${var.project_id}.cloudfunctions.net/compliance-audit-${local.resource_suffix}"
  }
  
  environment_variables = {
    GCP_PROJECT   = var.project_id
    BUCKET_NAME   = google_storage_bucket.compliance_bucket.name
    DATASET_ID    = google_bigquery_dataset.compliance_dataset.dataset_id
    RANDOM_SUFFIX = local.resource_suffix
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.compliance_function_sa,
    google_storage_bucket_object.audit_function_source
  ]
}

# Monitoring Notification Channel
resource "google_monitoring_notification_channel" "compliance_email" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  display_name = "Compliance Email Notifications"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Monitoring Alert Policy for High-Risk Events
resource "google_monitoring_alert_policy" "high_risk_events" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  display_name = "High-Risk Healthcare Data Access"
  combiner     = "OR"
  
  conditions {
    display_name = "High risk score events"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND log_name=\"projects/${var.project_id}/logs/cloudfunctions.googleapis.com%2Fcloud-functions\""
      duration       = var.alert_duration
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = var.alert_threshold_value
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [
    google_monitoring_notification_channel.compliance_email[0].name
  ]
  
  alert_strategy {
    auto_close = "86400s"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_monitoring_notification_channel.compliance_email
  ]
}

# IAM Policy for Healthcare Service Account
resource "google_healthcare_fhir_store_iam_binding" "fhir_store_pubsub_publisher" {
  fhir_store_id = google_healthcare_fhir_store.fhir_store.id
  role          = "roles/pubsub.publisher"
  
  members = [
    "serviceAccount:service-${data.google_project.project.number}@gcp-sa-healthcare.iam.gserviceaccount.com"
  ]
}

# Data source for project information
data "google_project" "project" {
  project_id = var.project_id
}