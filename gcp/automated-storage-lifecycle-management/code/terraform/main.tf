# Main Terraform configuration for Automated Storage Lifecycle Management
# This file creates the complete infrastructure for automated Cloud Storage lifecycle management

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for resource naming and configuration
locals {
  bucket_name      = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  logs_bucket_name = "${var.bucket_name_prefix}-logs-${random_id.suffix.hex}"
  job_name         = "lifecycle-cleanup-job-${random_id.suffix.hex}"
  
  common_labels = merge(var.labels, {
    terraform-managed = "true"
    creation-date     = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "storage_api" {
  service                    = "storage.googleapis.com"
  project                   = var.project_id
  disable_dependent_services = false
  disable_on_destroy        = false
}

resource "google_project_service" "scheduler_api" {
  service                    = "cloudscheduler.googleapis.com"
  project                   = var.project_id
  disable_dependent_services = false
  disable_on_destroy        = false
}

resource "google_project_service" "appengine_api" {
  service                    = "appengine.googleapis.com"
  project                   = var.project_id
  disable_dependent_services = false
  disable_on_destroy        = false
}

resource "google_project_service" "logging_api" {
  service                    = "logging.googleapis.com"
  project                   = var.project_id
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create App Engine application (required for Cloud Scheduler)
resource "google_app_engine_application" "app" {
  project       = var.project_id
  location_id   = var.region
  database_type = "CLOUD_DATASTORE_COMPATIBILITY"
  
  depends_on = [google_project_service.appengine_api]
}

# Main Cloud Storage bucket for lifecycle management
resource "google_storage_bucket" "lifecycle_bucket" {
  name                        = local.bucket_name
  location                    = var.region
  project                     = var.project_id
  storage_class               = var.storage_class
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  force_destroy               = true
  
  labels = local.common_labels
  
  # Lifecycle management configuration with automated transitions
  lifecycle_rule {
    # Transition to Nearline storage after specified days
    condition {
      age                   = var.lifecycle_rules.nearline_age_days
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    # Transition to Coldline storage after specified days
    condition {
      age                   = var.lifecycle_rules.coldline_age_days
      matches_storage_class = ["NEARLINE"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  lifecycle_rule {
    # Transition to Archive storage after specified days
    condition {
      age                   = var.lifecycle_rules.archive_age_days
      matches_storage_class = ["COLDLINE"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }
  
  lifecycle_rule {
    # Delete objects after specified days (compliance/retention)
    condition {
      age = var.lifecycle_rules.delete_age_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Optional versioning configuration
  dynamic "versioning" {
    for_each = var.enable_versioning ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Optional retention policy
  dynamic "retention_policy" {
    for_each = var.retention_policy_days > 0 ? [1] : []
    content {
      retention_period = var.retention_policy_days * 24 * 3600 # Convert days to seconds
    }
  }
  
  depends_on = [google_project_service.storage_api]
}

# Dedicated logging bucket for storing lifecycle events
resource "google_storage_bucket" "logs_bucket" {
  count                       = var.enable_monitoring ? 1 : 0
  name                        = local.logs_bucket_name
  location                    = var.region
  project                     = var.project_id
  storage_class               = "STANDARD"
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  force_destroy               = true
  
  labels = merge(local.common_labels, {
    purpose = "lifecycle-logs"
  })
  
  # Lifecycle rule for log retention (delete after 90 days)
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
  
  depends_on = [google_project_service.storage_api]
}

# Cloud Logging sink for capturing storage lifecycle events
resource "google_logging_project_sink" "storage_lifecycle_sink" {
  count                  = var.enable_monitoring ? 1 : 0
  name                   = "storage-lifecycle-sink"
  project               = var.project_id
  destination           = "storage.googleapis.com/${google_storage_bucket.logs_bucket[0].name}"
  unique_writer_identity = true
  
  # Filter for GCS bucket lifecycle events
  filter = <<-EOT
    resource.type="gcs_bucket" AND
    resource.labels.bucket_name="${google_storage_bucket.lifecycle_bucket.name}" AND
    (protoPayload.methodName="storage.objects.create" OR
     protoPayload.methodName="storage.objects.delete" OR
     protoPayload.methodName="storage.setObjectStorageClass")
  EOT
  
  depends_on = [google_project_service.logging_api]
}

# IAM binding for logging sink to write to the logs bucket
resource "google_storage_bucket_iam_member" "logs_bucket_sink_writer" {
  count  = var.enable_monitoring ? 1 : 0
  bucket = google_storage_bucket.logs_bucket[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.storage_lifecycle_sink[0].writer_identity
}

# Cloud Scheduler job for automated lifecycle reporting and governance
resource "google_cloud_scheduler_job" "lifecycle_job" {
  name        = local.job_name
  project     = var.project_id
  region      = var.region
  description = "Automated lifecycle management reporting and governance tasks"
  schedule    = var.scheduler_job_schedule
  time_zone   = "UTC"
  
  http_target {
    http_method = "POST"
    uri         = var.webhook_url
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      bucket             = google_storage_bucket.lifecycle_bucket.name
      action            = "lifecycle_report"
      timestamp         = timestamp()
      project_id        = var.project_id
      lifecycle_rules   = var.lifecycle_rules
      monitoring_enabled = var.enable_monitoring
    }))
  }
  
  # Retry configuration for reliability
  retry_config {
    retry_count          = 3
    max_retry_duration   = "60s"
    min_backoff_duration = "5s"
    max_backoff_duration = "3600s"
    max_doublings        = 5
  }
  
  depends_on = [
    google_project_service.scheduler_api,
    google_app_engine_application.app
  ]
}

# Sample data objects for testing lifecycle policies (optional)
resource "google_storage_bucket_object" "sample_files" {
  for_each = var.enable_sample_data ? {
    "critical-data.txt"   = "Critical business data - frequent access"
    "monthly-report.txt"  = "Monthly reports - moderate access"
    "archived-logs.txt"   = "Archived logs - rare access"
    "backup-data.txt"     = "Backup files - emergency access only"
  } : {}
  
  name         = each.key
  bucket       = google_storage_bucket.lifecycle_bucket.name
  content      = each.value
  storage_class = "STANDARD"
  
  metadata = {
    purpose      = "lifecycle-testing"
    created-by   = "terraform"
    access-pattern = each.key == "critical-data.txt" ? "frequent" : 
                    each.key == "monthly-report.txt" ? "moderate" :
                    each.key == "archived-logs.txt" ? "rare" : "emergency"
  }
}

# Optional: Custom timestamp for one sample file to simulate aged data
resource "google_storage_bucket_object" "aged_sample_file" {
  count        = var.enable_sample_data ? 1 : 0
  name         = "old-archived-logs.txt"
  bucket       = google_storage_bucket.lifecycle_bucket.name
  content      = "Old archived logs - simulated aged data for lifecycle testing"
  storage_class = "STANDARD"
  
  # Set custom time to simulate old data (60 days ago)
  custom_time = formatdate("YYYY-MM-DD'T'hh:mm:ss'Z'", timeadd(timestamp(), "-1440h"))
  
  metadata = {
    purpose        = "lifecycle-testing-aged"
    created-by     = "terraform"
    access-pattern = "archived"
    simulated-age  = "60-days"
  }
}