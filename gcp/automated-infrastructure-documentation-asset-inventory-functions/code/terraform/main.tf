# Main Terraform configuration for GCP Asset Inventory Documentation System
# This creates an automated infrastructure documentation system using:
# - Cloud Asset Inventory for resource discovery
# - Cloud Functions for processing and documentation generation
# - Cloud Storage for storing generated documentation
# - Cloud Scheduler for automated execution
# - Pub/Sub for event-driven architecture

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming and tagging
  resource_suffix = random_id.suffix.hex
  common_name     = "${var.resource_prefix}-${local.resource_suffix}"
  
  # Merge common labels with user-provided labels
  common_labels = merge(var.labels, {
    environment = var.environment
    created-by  = "terraform"
    project     = var.project_id
  })
  
  # Cloud Function source code archive
  function_source_path = "${path.module}/function-source.zip"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "cloudasset.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]) : []
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of APIs
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Cloud Storage bucket for documentation artifacts
resource "google_storage_bucket" "documentation_bucket" {
  name          = "${local.common_name}-docs"
  location      = var.storage_bucket_location
  project       = var.project_id
  storage_class = var.storage_class
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Enable versioning for change tracking
  versioning {
    enabled = var.enable_versioning
  }
  
  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.lifecycle_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  # Additional lifecycle rule for long-term archival
  lifecycle_rule {
    condition {
      age = var.lifecycle_age_days * 3  # 90 days default
    }
    action {
      type          = "SetStorageClass" 
      storage_class = "COLDLINE"
    }
  }
  
  # Prevent public access
  dynamic "public_access_prevention" {
    for_each = var.enable_public_access_prevention ? [1] : []
    content {
      enforced = true
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create bucket folders for organization
resource "google_storage_bucket_object" "reports_folder" {
  name    = "reports/.gitkeep"
  bucket  = google_storage_bucket.documentation_bucket.name
  content = "# Reports folder for generated documentation"
}

resource "google_storage_bucket_object" "exports_folder" {
  name    = "exports/.gitkeep"
  bucket  = google_storage_bucket.documentation_bucket.name
  content = "# Exports folder for JSON data"
}

resource "google_storage_bucket_object" "templates_folder" {
  name    = "templates/.gitkeep"
  bucket  = google_storage_bucket.documentation_bucket.name
  content = "# Templates folder for custom documentation templates"
}

# Create Pub/Sub topic for event-driven processing
resource "google_pubsub_topic" "asset_inventory_trigger" {
  name    = "${local.common_name}-trigger"
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = local.function_source_path
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id   = var.project_id
      bucket_name  = google_storage_bucket.documentation_bucket.name
    })
    filename = "main.py"
  }
  
  source {
    content = templatefile("${path.module}/function_code/requirements.txt", {})
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source/asset-doc-generator-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.documentation_bucket.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Create service account for Cloud Function with least privilege
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_prefix}-fn-sa-${local.resource_suffix}"
  display_name = "Asset Documentation Generator Service Account"
  description  = "Service account for Cloud Function that generates infrastructure documentation"
  project      = var.project_id
}

# Grant Cloud Asset Viewer role to the function service account
resource "google_project_iam_member" "function_asset_viewer" {
  project = var.project_id
  role    = "roles/cloudasset.viewer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant Storage Object Admin role for documentation uploads
resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant basic Cloud Function execution permissions
resource "google_project_iam_member" "function_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Deploy Cloud Function with Pub/Sub trigger
resource "google_cloudfunctions2_function" "asset_doc_generator" {
  name        = "${local.common_name}-generator"
  location    = var.region
  description = "Generates infrastructure documentation from Cloud Asset Inventory"
  project     = var.project_id
  
  build_config {
    runtime     = "python313"
    entry_point = "generate_asset_documentation"
    
    source {
      storage_source {
        bucket = google_storage_bucket.documentation_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = var.function_max_instances
    min_instance_count = 0
    available_memory   = "${var.function_memory}Mi"
    timeout_seconds    = var.function_timeout
    
    # Configure environment variables
    environment_variables = {
      GCP_PROJECT    = var.project_id
      STORAGE_BUCKET = google_storage_bucket.documentation_bucket.name
      ENVIRONMENT    = var.environment
    }
    
    # Use custom service account
    service_account_email = google_service_account.function_sa.email
  }
  
  # Configure Pub/Sub trigger
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.asset_inventory_trigger.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_project_iam_member.function_asset_viewer,
    google_project_iam_member.function_storage_admin
  ]
}

# Create Cloud Scheduler job for automated execution
resource "google_cloud_scheduler_job" "daily_documentation" {
  name        = "${local.common_name}-scheduler"
  description = "Daily infrastructure documentation generation"
  schedule    = var.schedule_cron
  time_zone   = var.schedule_timezone
  region      = var.region
  project     = var.project_id
  
  pubsub_target {
    topic_name = google_pubsub_topic.asset_inventory_trigger.id
    data       = base64encode(jsonencode({
      trigger   = "scheduled"
      timestamp = timestamp()
    }))
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_pubsub_topic.asset_inventory_trigger
  ]
}

# Create log sink for function monitoring (optional)
resource "google_logging_project_sink" "function_logs" {
  name        = "${local.common_name}-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.documentation_bucket.name}/logs"
  
  # Filter for function-specific logs
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${google_cloudfunctions2_function.asset_doc_generator.name}"
    severity>=INFO
  EOT
  
  # Create unique writer identity
  unique_writer_identity = true
}

# Grant log sink permission to write to bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.documentation_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs.writer_identity
}

# Optional: Create monitoring alert policy for function failures
resource "google_monitoring_alert_policy" "function_error_alert" {
  count        = var.notification_email != "" ? 1 : 0
  display_name = "Asset Documentation Function Errors"
  project      = var.project_id
  
  conditions {
    display_name = "Cloud Function error rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" resource.label.function_name=\"${google_cloudfunctions2_function.asset_doc_generator.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = []  # Would need to create notification channel separately
  
  alert_strategy {
    auto_close = "86400s"  # 24 hours
  }
  
  depends_on = [google_project_service.required_apis]
}