# GCP Data Migration Workflows with Storage Bucket Relocation and Eventarc
# This Terraform configuration creates a comprehensive data migration solution
# that automates bucket relocation workflows using event-driven architecture

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "eventarc.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com"
  ])

  service = each.value
  project = var.project_id

  disable_on_destroy = false
}

# Data source for default compute service account
data "google_compute_default_service_account" "default" {
  project = var.project_id
}

# Data source for Google Cloud Storage service account
data "google_storage_project_service_account" "gcs_account" {
  project = var.project_id
}

# Create a service account for migration automation functions
resource "google_service_account" "migration_automation_sa" {
  account_id   = "migration-automation"
  display_name = "Migration Automation Service Account"
  description  = "Service account for automated data migration workflows"
  project      = var.project_id
}

# IAM binding for Cloud Functions invoker role
resource "google_project_iam_member" "function_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.migration_automation_sa.email}"
}

# IAM binding for Cloud Run invoker role
resource "google_project_iam_member" "run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.migration_automation_sa.email}"
}

# IAM binding for Eventarc event receiver role
resource "google_project_iam_member" "eventarc_event_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.migration_automation_sa.email}"
}

# IAM binding for Storage Admin role
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.migration_automation_sa.email}"
}

# IAM binding for Logging viewer role
resource "google_project_iam_member" "logging_viewer" {
  project = var.project_id
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${google_service_account.migration_automation_sa.email}"
}

# IAM binding for Monitoring metric writer role
resource "google_project_iam_member" "monitoring_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.migration_automation_sa.email}"
}

# Grant the GCS service account permission to publish to Pub/Sub topics
resource "google_project_iam_member" "gcs_pubsub_publishing" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
}

# Create source storage bucket with versioning and lifecycle management
resource "google_storage_bucket" "source_bucket" {
  name          = var.source_bucket_name
  location      = var.source_region
  force_destroy = var.force_destroy_buckets
  
  # Security configurations
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  
  # Versioning for data protection
  versioning {
    enabled = true
  }
  
  # Lifecycle policy for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Soft delete policy for data recovery
  soft_delete_policy {
    retention_duration_seconds = var.soft_delete_retention_days * 24 * 60 * 60
  }
  
  # Labels for resource organization
  labels = {
    environment = var.environment
    purpose     = "data-migration-source"
    managed-by  = "terraform"
  }
}

# Create destination storage bucket for migrated data
resource "google_storage_bucket" "destination_bucket" {
  name          = var.destination_bucket_name
  location      = var.destination_region
  force_destroy = var.force_destroy_buckets
  
  # Security configurations
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  
  # Versioning for data protection
  versioning {
    enabled = true
  }
  
  # Lifecycle policy for long-term storage
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
      storage_class = "ARCHIVE"
    }
  }
  
  # Soft delete policy
  soft_delete_policy {
    retention_duration_seconds = var.soft_delete_retention_days * 24 * 60 * 60
  }
  
  # Labels for resource organization
  labels = {
    environment = var.environment
    purpose     = "data-migration-destination"
    managed-by  = "terraform"
  }
}

# Create bucket for Cloud Function source code
resource "google_storage_bucket" "function_source_bucket" {
  name          = "${var.project_id}-migration-function-source"
  location      = var.region
  force_destroy = true
  
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  
  labels = {
    environment = var.environment
    purpose     = "function-source"
    managed-by  = "terraform"
  }
}

# Create pre-migration validation function source code
resource "google_storage_bucket_object" "pre_migration_function_source" {
  name   = "pre-migration-validator-source.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = var.pre_migration_function_source_path
}

# Create migration progress monitor function source code
resource "google_storage_bucket_object" "progress_monitor_function_source" {
  name   = "migration-progress-monitor-source.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = var.progress_monitor_function_source_path
}

# Create post-migration validation function source code
resource "google_storage_bucket_object" "post_migration_function_source" {
  name   = "post-migration-validator-source.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = var.post_migration_function_source_path
}

# Pre-migration validation Cloud Function
resource "google_cloudfunctions2_function" "pre_migration_validator" {
  name        = "pre-migration-validator"
  location    = var.region
  description = "Validates bucket configuration before migration"
  
  build_config {
    runtime     = "python311"
    entry_point = "validate_pre_migration"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.pre_migration_function_source.name
      }
    }
    
    environment_variables = {
      PROJECT_ID     = var.project_id
      SOURCE_BUCKET  = google_storage_bucket.source_bucket.name
      DEST_BUCKET    = google_storage_bucket.destination_bucket.name
    }
  }
  
  service_config {
    max_instance_count               = 10
    min_instance_count               = 0
    available_memory                 = "256M"
    timeout_seconds                  = 60
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID     = var.project_id
      SOURCE_BUCKET  = google_storage_bucket.source_bucket.name
      DEST_BUCKET    = google_storage_bucket.destination_bucket.name
    }
    
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.migration_automation_sa.email
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_invoker,
    google_project_iam_member.run_invoker,
    google_project_iam_member.eventarc_event_receiver,
    google_project_iam_member.storage_admin,
    google_project_iam_member.logging_viewer,
  ]
}

# Migration progress monitor Cloud Function
resource "google_cloudfunctions2_function" "migration_progress_monitor" {
  name        = "migration-progress-monitor"
  location    = var.region
  description = "Monitors bucket relocation progress and reports metrics"
  
  build_config {
    runtime     = "python311"
    entry_point = "monitor_migration_progress"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.progress_monitor_function_source.name
      }
    }
    
    environment_variables = {
      PROJECT_ID = var.project_id
    }
  }
  
  service_config {
    max_instance_count               = 10
    min_instance_count               = 0
    available_memory                 = "512M"
    timeout_seconds                  = 120
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID = var.project_id
    }
    
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.migration_automation_sa.email
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_invoker,
    google_project_iam_member.run_invoker,
    google_project_iam_member.eventarc_event_receiver,
    google_project_iam_member.storage_admin,
    google_project_iam_member.monitoring_metric_writer,
  ]
}

# Post-migration validation Cloud Function
resource "google_cloudfunctions2_function" "post_migration_validator" {
  name        = "post-migration-validator"
  location    = var.region
  description = "Validates bucket state after migration completion"
  
  build_config {
    runtime     = "python311"
    entry_point = "validate_post_migration"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.post_migration_function_source.name
      }
    }
    
    environment_variables = {
      PROJECT_ID = var.project_id
    }
  }
  
  service_config {
    max_instance_count               = 10
    min_instance_count               = 0
    available_memory                 = "512M"
    timeout_seconds                  = 180
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID = var.project_id
    }
    
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.migration_automation_sa.email
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_invoker,
    google_project_iam_member.run_invoker,
    google_project_iam_member.eventarc_event_receiver,
    google_project_iam_member.storage_admin,
    google_project_iam_member.logging_viewer,
  ]
}

# Eventarc trigger for bucket administrative events
resource "google_eventarc_trigger" "bucket_admin_trigger" {
  name     = "bucket-admin-trigger"
  location = var.region
  project  = var.project_id
  
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.audit.log.v1.written"
  }
  
  matching_criteria {
    attribute = "serviceName"
    value     = "storage.googleapis.com"
  }
  
  matching_criteria {
    attribute = "methodName"
    value     = "storage.buckets.patch"
  }
  
  destination {
    cloud_run_service {
      service = google_cloudfunctions2_function.migration_progress_monitor.name
      region  = var.region
    }
  }
  
  service_account = google_service_account.migration_automation_sa.email
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.eventarc_event_receiver,
    google_cloudfunctions2_function.migration_progress_monitor,
  ]
}

# Eventarc trigger for object-level events during migration
resource "google_eventarc_trigger" "object_event_trigger" {
  name     = "object-event-trigger"
  location = var.region
  project  = var.project_id
  
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.audit.log.v1.written"
  }
  
  matching_criteria {
    attribute = "serviceName"
    value     = "storage.googleapis.com"
  }
  
  matching_criteria {
    attribute = "methodName"
    value     = "storage.objects.create"
  }
  
  destination {
    cloud_run_service {
      service = google_cloudfunctions2_function.post_migration_validator.name
      region  = var.region
    }
  }
  
  service_account = google_service_account.migration_automation_sa.email
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.eventarc_event_receiver,
    google_cloudfunctions2_function.post_migration_validator,
  ]
}

# BigQuery dataset for migration audit logs
resource "google_bigquery_dataset" "migration_audit" {
  dataset_id  = "migration_audit"
  location    = var.region
  description = "Dataset for storing migration audit logs and analytics"
  
  labels = {
    environment = var.environment
    purpose     = "audit-logging"
    managed-by  = "terraform"
  }
  
  # Access control for the dataset
  access {
    role          = "OWNER"
    user_by_email = "serviceAccount:${google_service_account.migration_automation_sa.email}"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Log sink for capturing storage operations
resource "google_logging_project_sink" "migration_audit_sink" {
  name        = "migration-audit-sink"
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.migration_audit.dataset_id}"
  
  filter = <<-EOT
    protoPayload.serviceName="storage.googleapis.com" 
    AND (protoPayload.methodName:"storage.buckets" OR protoPayload.methodName:"storage.objects")
    AND (resource.labels.bucket_name="${google_storage_bucket.source_bucket.name}" OR resource.labels.bucket_name="${google_storage_bucket.destination_bucket.name}")
  EOT
  
  unique_writer_identity = true
}

# Grant BigQuery Data Editor role to the log sink service account
resource "google_project_iam_member" "log_sink_bigquery_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.migration_audit_sink.writer_identity
}

# Cloud Monitoring alert policy for migration events
resource "google_monitoring_alert_policy" "migration_alert_policy" {
  display_name = "Bucket Migration Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Storage bucket operation errors"
    
    condition_threshold {
      filter          = "resource.type=\"gcs_bucket\" AND log_name=\"projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Factivity\" AND protoPayload.methodName:\"storage.buckets\""
      comparison      = "COMPARISON_COUNT_GREATER_THAN"
      threshold_value = 0
      duration        = "300s"
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_COUNT"
      }
    }
  }
  
  alert_strategy {
    auto_close = "604800s"
  }
  
  enabled = true
  
  depends_on = [google_project_service.required_apis]
}

# Create sample data objects in the source bucket for testing
resource "google_storage_bucket_object" "sample_critical_data" {
  name     = "critical-data.txt"
  bucket   = google_storage_bucket.source_bucket.name
  content  = "Critical business data - ${formatdate("YYYY-MM-DD hh:mm:ss", timestamp())}"
  
  metadata = {
    data-classification = "critical"
  }
}

resource "google_storage_bucket_object" "sample_archive_data" {
  name     = "logs/archive-data.txt"
  bucket   = google_storage_bucket.source_bucket.name
  content  = "Archive data from last year - ${formatdate("YYYY-MM-DD hh:mm:ss", timestamp())}"
  
  metadata = {
    data-classification = "archive"
  }
}

resource "google_storage_bucket_object" "sample_application_log" {
  name     = "logs/application.log"
  bucket   = google_storage_bucket.source_bucket.name
  content  = "Log file entry - ${formatdate("YYYY-MM-DD hh:mm:ss", timestamp())}"
  
  metadata = {
    source = "application-logs"
  }
}