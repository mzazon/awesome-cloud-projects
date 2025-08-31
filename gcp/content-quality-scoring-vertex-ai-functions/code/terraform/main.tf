# ================================================================
# Content Quality Scoring System with Vertex AI and Cloud Functions
# ================================================================
# This Terraform configuration deploys a complete content quality
# scoring system using Google Cloud services including:
# - Cloud Storage buckets for content and results
# - Cloud Functions for serverless processing
# - Vertex AI for content analysis
# - IAM roles and permissions
# ================================================================

# Configure Terraform and required providers
terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.44"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.44"
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

# Configure the Google Cloud provider
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for resource naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  content_bucket_name  = "${var.content_bucket_prefix}-${random_id.suffix.hex}"
  results_bucket_name  = "${var.results_bucket_prefix}-${random_id.suffix.hex}"
  function_name        = var.function_name
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment   = var.environment
    project       = "content-quality-scoring"
    managed-by    = "terraform"
    created-date  = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Required APIs for the solution
  required_apis = [
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com"
  ]
}

# ================================================================
# API ENABLEMENT
# ================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  service = each.key
  project = var.project_id
  
  # Prevent disabling APIs when destroying this terraform
  disable_dependent_services = false
  disable_on_destroy        = false
}

# ================================================================
# CLOUD STORAGE BUCKETS
# ================================================================

# Cloud Storage bucket for content uploads (trigger source)
resource "google_storage_bucket" "content_bucket" {
  name                        = local.content_bucket_name
  location                    = var.region
  project                     = var.project_id
  storage_class              = var.storage_class
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.content_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Lifecycle rule for transitioning to cheaper storage
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  # Security and compliance settings
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for analysis results
resource "google_storage_bucket" "results_bucket" {
  name                        = local.results_bucket_name
  location                    = var.region
  project                     = var.project_id
  storage_class              = var.storage_class
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  # Lifecycle management for long-term retention
  lifecycle_rule {
    condition {
      age = var.results_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Transition to archive storage for long-term retention
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# ================================================================
# IAM ROLES AND PERMISSIONS
# ================================================================

# Create custom service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa"
  display_name = "Content Quality Analysis Function Service Account"
  description  = "Service account for content quality scoring Cloud Function"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant Cloud Function access to read from content bucket
resource "google_storage_bucket_iam_member" "function_content_reader" {
  bucket = google_storage_bucket.content_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant Cloud Function access to write to results bucket
resource "google_storage_bucket_iam_member" "function_results_writer" {
  bucket = google_storage_bucket.results_bucket.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant Cloud Function access to Vertex AI
resource "google_project_iam_member" "function_vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant Cloud Function access to logging
resource "google_project_iam_member" "function_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# ================================================================
# CLOUD FUNCTION SOURCE CODE
# ================================================================

# Create function source code directory
resource "local_file" "function_main" {
  filename = "${path.module}/function-source/main.py"
  content = templatefile("${path.module}/templates/function_main.py.tpl", {
    project_id     = var.project_id
    region         = var.region
    results_bucket = google_storage_bucket.results_bucket.name
  })
  
  depends_on = [null_resource.create_function_dir]
}

# Create requirements.txt for function dependencies
resource "local_file" "function_requirements" {
  filename = "${path.module}/function-source/requirements.txt"
  content = templatefile("${path.module}/templates/requirements.txt.tpl", {
    functions_framework_version = var.functions_framework_version
    storage_version            = var.google_cloud_storage_version
    aiplatform_version         = var.google_cloud_aiplatform_version
    logging_version            = var.google_cloud_logging_version
  })
  
  depends_on = [null_resource.create_function_dir]
}

# Create function source directory
resource "null_resource" "create_function_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/function-source"
  }
}

# Create ZIP archive of function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  source_dir  = "${path.module}/function-source"
  
  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Upload function source to Cloud Storage for deployment
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.content_bucket.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# ================================================================
# CLOUD FUNCTION DEPLOYMENT
# ================================================================

# Deploy Cloud Function (2nd generation) with Cloud Storage trigger
resource "google_cloudfunctions2_function" "content_analyzer" {
  name        = local.function_name
  location    = var.region
  project     = var.project_id
  description = "Analyzes content quality using Vertex AI Gemini models"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = var.function_entry_point
    
    source {
      storage_source {
        bucket = google_storage_bucket.content_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
    
    environment_variables = {
      BUILD_CONFIG_TEST = "build_test"
    }
  }
  
  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = var.function_min_instances
    available_memory                 = var.function_memory
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = var.function_concurrency
    available_cpu                    = var.function_cpu
    
    environment_variables = {
      PROJECT_ID      = var.project_id
      REGION         = var.region
      RESULTS_BUCKET = google_storage_bucket.results_bucket.name
    }
    
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_sa.email
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.content_bucket.name
    }
    
    service_account_email = google_service_account.function_sa.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_service_account.function_sa,
    google_storage_bucket_iam_member.function_content_reader,
    google_storage_bucket_iam_member.function_results_writer,
    google_project_iam_member.function_vertex_ai_user
  ]
}

# ================================================================
# MONITORING AND ALERTING (OPTIONAL)
# ================================================================

# Cloud Monitoring notification channel for alerts
resource "google_monitoring_notification_channel" "email" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Content Quality System Email Alerts"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = var.alert_email
  }
}

# Alert policy for function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Content Analysis Function Error Rate"
  project      = var.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "Function error rate too high"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.1  # 10% error rate
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email[0].id]
  
  alert_strategy {
    auto_close = "604800s"  # 7 days
  }
}

# Alert policy for high function execution time
resource "google_monitoring_alert_policy" "function_latency" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Content Analysis Function High Latency"
  project      = var.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "Function execution time too high"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 300  # 5 minutes
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email[0].id]
  
  alert_strategy {
    auto_close = "604800s"  # 7 days
  }
}