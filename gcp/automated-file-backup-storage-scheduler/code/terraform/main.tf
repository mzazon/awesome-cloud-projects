# Automated File Backup with Storage and Scheduler
# This Terraform configuration creates an automated backup system using
# Google Cloud Storage, Cloud Functions, and Cloud Scheduler

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent naming and tagging
locals {
  name_suffix = lower(random_id.suffix.hex)
  common_labels = merge(var.labels, {
    environment = var.environment
    created-by  = "terraform"
  })
  
  # Ensure globally unique bucket names
  primary_bucket_name = "${var.primary_bucket_name}-${local.name_suffix}"
  backup_bucket_name  = "${var.backup_bucket_name}-${local.name_suffix}"
  function_name       = "${var.function_name}-${local.name_suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Don't disable APIs on destroy to avoid breaking other resources
  disable_on_destroy = false
}

# Primary storage bucket for active data
resource "google_storage_bucket" "primary" {
  name     = local.primary_bucket_name
  location = var.region
  
  # Storage configuration
  storage_class               = var.primary_storage_class
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection
  versioning {
    enabled = var.enable_versioning
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
  
  # Security and compliance settings
  public_access_prevention = "enforced"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Backup storage bucket for archived data
resource "google_storage_bucket" "backup" {
  name     = local.backup_bucket_name
  location = var.region
  
  # Use cost-effective storage class for backups
  storage_class               = var.backup_storage_class
  uniform_bucket_level_access = true
  
  # Enable versioning for backup integrity
  versioning {
    enabled = var.enable_versioning
  }
  
  # Aggressive lifecycle management for backup data
  lifecycle_rule {
    condition {
      age = 60
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 180
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }
  
  # Optional: Auto-delete very old backups (uncomment if needed)
  # lifecycle_rule {
  #   condition {
  #     age = 2555  # ~7 years
  #   }
  #   action {
  #     type = "Delete"
  #   }
  # }
  
  # Security settings
  public_access_prevention = "enforced"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Service account for Cloud Function with minimal required permissions
resource "google_service_account" "backup_function" {
  account_id   = "backup-function-sa-${local.name_suffix}"
  display_name = "Backup Function Service Account"
  description  = "Service account for automated backup Cloud Function"
  
  depends_on = [google_project_service.apis]
}

# IAM binding for function to read from primary bucket
resource "google_storage_bucket_iam_member" "primary_reader" {
  bucket = google_storage_bucket.primary.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.backup_function.email}"
}

# IAM binding for function to write to backup bucket
resource "google_storage_bucket_iam_member" "backup_writer" {
  bucket = google_storage_bucket.backup.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.backup_function.email}"
}

# IAM binding for function to write logs
resource "google_project_iam_member" "function_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.backup_function.email}"
}

# Create the Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code.py", {
      primary_bucket = google_storage_bucket.primary.name
      backup_bucket  = google_storage_bucket.backup.name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/requirements.txt")
    filename = "requirements.txt"
  }
}

# Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = "function-source-${local.name_suffix}"
  location = var.region
  
  # Use standard storage for function source
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Upload function source code to storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  # Ensure source is recreated when function code changes
  lifecycle {
    replace_triggered_by = [data.archive_file.function_source]
  }
}

# Cloud Function for backup logic (2nd generation)
resource "google_cloudfunctions2_function" "backup_function" {
  name        = local.function_name
  location    = var.region
  description = "Automated file backup function"
  
  build_config {
    runtime     = "python311"
    entry_point = "backup_files"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 10
    min_instance_count               = 0
    available_memory                 = "${var.function_memory}Mi"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    # Environment variables for function configuration
    environment_variables = {
      PRIMARY_BUCKET = google_storage_bucket.primary.name
      BACKUP_BUCKET  = google_storage_bucket.backup.name
      ENVIRONMENT    = var.environment
    }
    
    # Use custom service account with minimal permissions
    service_account_email = google_service_account.backup_function.email
    
    # Security settings
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_storage_bucket_iam_member.primary_reader,
    google_storage_bucket_iam_member.backup_writer,
    google_project_iam_member.function_logs
  ]
}

# Service account for Cloud Scheduler
resource "google_service_account" "scheduler" {
  account_id   = "backup-scheduler-sa-${local.name_suffix}"
  display_name = "Backup Scheduler Service Account"
  description  = "Service account for Cloud Scheduler to invoke backup function"
  
  depends_on = [google_project_service.apis]
}

# IAM binding for scheduler to invoke Cloud Function
resource "google_cloudfunctions2_function_iam_member" "scheduler_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.backup_function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.scheduler.email}"
}

# Cloud Scheduler job for automated daily backups
resource "google_cloud_scheduler_job" "backup_schedule" {
  name        = var.scheduler_job_name
  description = "Daily automated backup job"
  schedule    = var.backup_schedule
  time_zone   = "UTC"
  region      = var.region
  
  # Retry configuration for reliability
  retry_config {
    retry_count          = 3
    max_retry_duration   = "600s"
    max_backoff_duration = "300s"
    min_backoff_duration = "60s"
    max_doublings        = 3
  }
  
  # HTTP target to invoke Cloud Function
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.backup_function.service_config[0].uri
    headers = {
      "Content-Type" = "application/json"
    }
    body = base64encode(jsonencode({
      source    = "cloud-scheduler"
      timestamp = "{{.timestamp}}"
    }))
    
    # Use service account for authentication
    oidc_token {
      service_account_email = google_service_account.scheduler.email
      audience              = google_cloudfunctions2_function.backup_function.service_config[0].uri
    }
  }
  
  depends_on = [
    google_project_service.apis,
    google_cloudfunctions2_function_iam_member.scheduler_invoker
  ]
}

# Create sample files for testing (optional)
resource "google_storage_bucket_object" "sample_files" {
  for_each = var.create_sample_files ? {
    "business-data.txt" = "Critical business data - Created by Terraform on ${timestamp()}"
    "config.json"       = jsonencode({
      application = "backup-demo"
      version     = "1.0"
      created     = timestamp()
      environment = var.environment
    })
    "users.csv" = "id,name,email,created_date\n1,John Doe,john@example.com,${timestamp()}\n2,Jane Smith,jane@example.com,${timestamp()}"
  } : {}
  
  name    = each.key
  bucket  = google_storage_bucket.primary.name
  content = each.value
  
  # Metadata for tracking
  metadata = {
    created-by = "terraform"
    purpose    = "sample-data"
  }
}

# Create function source files as local files for the archive
resource "local_file" "function_code" {
  filename = "${path.module}/function_code.py"
  content = templatefile("${path.root}/function_template.py.tpl", {
    primary_bucket = google_storage_bucket.primary.name
    backup_bucket  = google_storage_bucket.backup.name
  })
}

resource "local_file" "requirements" {
  filename = "${path.module}/requirements.txt"
  content  = <<EOF
google-cloud-storage==2.18.0
google-cloud-logging==3.11.0
functions-framework==3.5.0
EOF
}

# Log-based metric for monitoring backup success/failure
resource "google_logging_metric" "backup_errors" {
  name   = "backup_function_errors_${local.name_suffix}"
  filter = <<EOF
resource.type="cloud_function"
resource.labels.function_name="${google_cloudfunctions2_function.backup_function.name}"
severity="ERROR"
EOF
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Backup Function Errors"
  }
  
  label_extractors = {
    error_type = "EXTRACT(jsonPayload.error_type)"
  }
}

# Alerting policy for backup failures
resource "google_monitoring_alert_policy" "backup_failure_alert" {
  display_name = "Backup Function Failure Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Backup function error rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.label.function_name=\"${google_cloudfunctions2_function.backup_function.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  # Notification channels would be configured separately
  # notification_channels = [google_monitoring_notification_channel.email.id]
  
  alert_strategy {
    auto_close = "86400s"  # Auto-close after 24 hours
  }
}

# Create the function template file
resource "local_file" "function_template" {
  filename = "${path.root}/function_template.py.tpl"
  content  = <<EOF
import os
from google.cloud import storage, logging
from datetime import datetime
import json
import functions_framework

@functions_framework.http
def backup_files(request):
    """Cloud Function to backup files from primary to backup bucket."""
    
    # Initialize clients
    storage_client = storage.Client()
    logging_client = logging.Client()
    logger = logging_client.logger('backup-function')
    
    # Get bucket names from environment variables
    primary_bucket_name = os.environ.get('PRIMARY_BUCKET')
    backup_bucket_name = os.environ.get('BACKUP_BUCKET')
    environment = os.environ.get('ENVIRONMENT', 'unknown')
    
    if not primary_bucket_name or not backup_bucket_name:
        error_msg = "Missing required environment variables"
        logger.log_text(error_msg, severity='ERROR')
        return {'error': error_msg}, 400
    
    try:
        # Get bucket references
        primary_bucket = storage_client.bucket(primary_bucket_name)
        backup_bucket = storage_client.bucket(backup_bucket_name)
        
        # List and copy all files from primary to backup
        blobs = primary_bucket.list_blobs()
        copied_count = 0
        total_size = 0
        
        for blob in blobs:
            # Create backup file name with timestamp
            backup_name = f"backup-{datetime.now().strftime('%Y%m%d')}/{blob.name}"
            
            # Skip if backup already exists (avoid duplicates)
            if backup_bucket.blob(backup_name).exists():
                logger.log_text(f"Backup already exists for {blob.name}, skipping")
                continue
            
            # Copy blob to backup bucket
            backup_bucket.copy_blob(blob, backup_bucket, backup_name)
            copied_count += 1
            total_size += blob.size or 0
            
            logger.log_text(f"Copied {blob.name} to {backup_name} ({blob.size} bytes)")
        
        success_msg = f"Backup completed successfully. {copied_count} files copied, {total_size} bytes total."
        logger.log_text(success_msg, severity='INFO')
        
        return {
            'status': 'success',
            'files_copied': copied_count,
            'total_size_bytes': total_size,
            'primary_bucket': primary_bucket_name,
            'backup_bucket': backup_bucket_name,
            'environment': environment,
            'timestamp': datetime.now().isoformat()
        }
        
    except Exception as e:
        error_msg = f"Backup failed: {str(e)}"
        logger.log_text(error_msg, severity='ERROR', 
                      labels={'error_type': type(e).__name__})
        return {'error': error_msg, 'error_type': type(e).__name__}, 500
EOF
}