# Main Terraform configuration for Automated Code Review Pipeline
# This file defines all infrastructure resources for Firebase Studio and Cloud Build integration

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  # Resource naming convention
  resource_suffix = random_id.suffix.hex
  base_name       = "${var.resource_prefix}-${var.environment}"
  
  # Computed resource names
  repository_name     = var.repository_name != "" ? var.repository_name : "${local.base_name}-repo-${local.resource_suffix}"
  queue_name         = "${local.base_name}-queue-${local.resource_suffix}"
  function_name      = "${local.base_name}-handler-${local.resource_suffix}"
  metrics_function   = "${local.base_name}-metrics-${local.resource_suffix}"
  build_bucket       = "${var.project_id}-${local.base_name}-build-${local.resource_suffix}"
  metrics_bucket     = "${var.project_id}-${local.base_name}-metrics-${local.resource_suffix}"
  
  # Firebase project ID (use Google Cloud project if not specified)
  firebase_project = var.firebase_project_id != "" ? var.firebase_project_id : var.project_id
  
  # Default labels merged with additional labels
  default_labels = merge({
    environment   = var.environment
    recipe        = "automated-code-review"
    managed-by    = "terraform"
    deployed-by   = "terraform"
    cost-center   = "development"
  }, var.additional_labels)
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudbuild.googleapis.com",
    "cloudtasks.googleapis.com",
    "cloudfunctions.googleapis.com",
    "sourcerepo.googleapis.com",
    "firebase.googleapis.com",
    "aiplatform.googleapis.com",
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Cloud Source Repository for the code review pipeline
resource "google_sourcerepo_repository" "code_review_repo" {
  name       = local.repository_name
  project    = var.project_id
  depends_on = [google_project_service.required_apis]

  # Wait for Source Repositories API to be fully enabled
  timeouts {
    create = "5m"
    delete = "5m"
  }
}

# Create Cloud Storage bucket for build artifacts
resource "google_storage_bucket" "build_artifacts" {
  name          = local.build_bucket
  location      = var.storage_location
  project       = var.project_id
  storage_class = var.storage_class
  
  # Enable versioning for build artifact history
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Public access prevention
  public_access_prevention = "enforced"
  
  labels = local.default_labels
  
  depends_on = [google_project_service.required_apis]
  
  # Allow Terraform to destroy bucket with objects in development
  force_destroy = var.force_destroy_buckets
}

# Create Cloud Storage bucket for metrics data
resource "google_storage_bucket" "metrics_storage" {
  name          = local.metrics_bucket
  location      = var.storage_location
  project       = var.project_id
  storage_class = var.storage_class
  
  # Enable versioning for metrics history
  versioning {
    enabled = true
  }
  
  # Lifecycle management for metrics data
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Public access prevention
  public_access_prevention = "enforced"
  
  labels = local.default_labels
  
  depends_on = [google_project_service.required_apis]
  
  # Allow Terraform to destroy bucket with objects in development
  force_destroy = var.force_destroy_buckets
}

# Create Cloud Tasks queue for asynchronous code analysis
resource "google_cloud_tasks_queue" "code_review_queue" {
  name     = local.queue_name
  location = var.region
  project  = var.project_id
  
  # Configure rate limits for optimal performance
  rate_limits {
    max_concurrent_dispatches = var.task_queue_max_concurrent_dispatches
    max_dispatches_per_second = 10
  }
  
  # Configure retry settings for reliability
  retry_config {
    max_attempts       = var.task_queue_max_attempts
    max_retry_duration = var.task_queue_max_retry_duration
    max_backoff        = "60s"
    min_backoff        = "5s"
    max_doublings      = 3
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Functions
resource "google_service_account" "function_service_account" {
  account_id   = "${local.base_name}-function-sa"
  display_name = "Code Review Function Service Account"
  description  = "Service account for code review Cloud Functions with minimal required permissions"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary permissions to the function service account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/cloudtasks.enqueuer",
    "roles/storage.objectAdmin",
    "roles/cloudsql.client"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

# Grant AI Platform User role for Gemini integration
resource "google_project_iam_member" "ai_platform_user" {
  count = var.enable_gemini_integration ? 1 : 0
  
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

# Create source code archive for the code review function
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/code-review-function.zip"
  
  source {
    content = templatefile("${path.module}/function_code.py.tpl", {
      project_id    = var.project_id
      region        = var.region
      gemini_model  = var.gemini_model
      debug_mode    = var.enable_debug_mode
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/requirements.txt.tpl")
    filename = "requirements.txt"
  }
}

# Deploy Cloud Function for automated code review processing
resource "google_cloudfunctions2_function" "code_review_function" {
  name        = local.function_name
  location    = var.region
  project     = var.project_id
  description = "Automated code review function using Gemini AI for intelligent analysis"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "analyze_code"
    
    source {
      storage_source {
        bucket = google_storage_bucket.build_artifacts.name
        object = google_storage_bucket_object.function_archive.name
      }
    }
    
    environment_variables = {
      BUILD_CONFIG_TEST = "true"
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "${var.function_memory}Mi"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.function_service_account.email
    
    environment_variables = {
      PROJECT_ID         = var.project_id
      REGION            = var.region
      GEMINI_MODEL      = var.gemini_model
      GEMINI_ENABLED    = var.enable_gemini_integration
      DEBUG_MODE        = var.enable_debug_mode
      METRICS_BUCKET    = google_storage_bucket.metrics_storage.name
      QUEUE_NAME        = google_cloud_tasks_queue.code_review_queue.name
    }
    
    # Enable ingress from all sources for HTTP trigger
    ingress_settings = "ALLOW_ALL"
    
    # Enable all traffic to the latest revision
    all_traffic_on_latest_revision = true
  }
  
  labels = local.default_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_archive
  ]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_archive" {
  name   = "function-source/code-review-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.build_artifacts.name
  source = data.archive_file.function_source.output_path
  
  # Generate a new object version when the source changes
  detect_md5hash = data.archive_file.function_source.output_md5
}

# Create function source code archive for metrics collection
data "archive_file" "metrics_function_source" {
  type        = "zip"
  output_path = "${path.module}/metrics-function.zip"
  
  source {
    content = templatefile("${path.module}/metrics_function_code.py.tpl", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/metrics_requirements.txt.tpl")
    filename = "requirements.txt"
  }
}

# Upload metrics function source code to Cloud Storage
resource "google_storage_bucket_object" "metrics_function_archive" {
  name   = "function-source/metrics-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.build_artifacts.name
  source = data.archive_file.metrics_function_source.output_path
  
  # Generate a new object version when the source changes
  detect_md5hash = data.archive_file.metrics_function_source.output_md5
}

# Deploy Cloud Function for metrics collection
resource "google_cloudfunctions2_function" "metrics_function" {
  name        = local.metrics_function
  location    = var.region
  project     = var.project_id
  description = "Metrics collection function for code review pipeline analytics"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "collect_review_metrics"
    
    source {
      storage_source {
        bucket = google_storage_bucket.build_artifacts.name
        object = google_storage_bucket_object.metrics_function_archive.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 5
    min_instance_count    = 0
    available_memory      = "512Mi"
    timeout_seconds       = 120
    service_account_email = google_service_account.function_service_account.email
    
    environment_variables = {
      PROJECT_ID      = var.project_id
      METRICS_BUCKET  = google_storage_bucket.metrics_storage.name
    }
    
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }
  
  labels = local.default_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.metrics_function_archive
  ]
}

# Create Cloud Build triggers for automated pipeline execution
resource "google_cloudbuild_trigger" "main_branch_trigger" {
  name        = "${local.base_name}-main-trigger"
  description = "Automated code review pipeline for main branch"
  project     = var.project_id
  location    = var.region
  
  # Trigger configuration for Cloud Source Repository
  source_to_build {
    uri       = google_sourcerepo_repository.code_review_repo.url
    ref       = "refs/heads/main"
    repo_type = "CLOUD_SOURCE_REPOSITORIES"
  }
  
  # Git file source configuration
  git_file_source {
    path      = "cloudbuild.yaml"
    uri       = google_sourcerepo_repository.code_review_repo.url
    revision  = "refs/heads/main"
    repo_type = "CLOUD_SOURCE_REPOSITORIES"
  }
  
  # Build configuration
  build {
    timeout = var.build_timeout
    
    options {
      machine_type    = var.build_machine_type
      logging         = "CLOUD_LOGGING_ONLY"
      source_provenance_hash = ["SHA256"]
    }
    
    # Environment variables for the build
    substitutions = {
      _REPO_NAME     = google_sourcerepo_repository.code_review_repo.name
      _FUNCTION_URL  = google_cloudfunctions2_function.code_review_function.service_config[0].uri
      _QUEUE_NAME    = google_cloud_tasks_queue.code_review_queue.name
      _REGION        = var.region
      _PROJECT_ID    = var.project_id
    }
    
    # Build artifacts configuration
    artifacts {
      objects {
        location = "gs://${google_storage_bucket.build_artifacts.name}/artifacts"
        paths    = ["dist/**/*", "coverage/**/*", "lint-results.json"]
      }
    }
  }
  
  # Include files for triggering builds
  included_files = ["**/*"]
  ignored_files  = ["README.md", "docs/**/*", ".gitignore"]
  
  tags = ["main-branch", "automated-review"]
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.code_review_function
  ]
}

# Create Cloud Build trigger for feature branches
resource "google_cloudbuild_trigger" "feature_branch_trigger" {
  count = length(var.trigger_branches) > 1 ? 1 : 0
  
  name        = "${local.base_name}-feature-trigger"
  description = "Code review pipeline for feature branches"
  project     = var.project_id
  location    = var.region
  
  # Trigger for feature branches
  source_to_build {
    uri       = google_sourcerepo_repository.code_review_repo.url
    ref       = "refs/heads/feature/*"
    repo_type = "CLOUD_SOURCE_REPOSITORIES"
  }
  
  git_file_source {
    path      = "cloudbuild.yaml"
    uri       = google_sourcerepo_repository.code_review_repo.url
    revision  = "refs/heads/main"
    repo_type = "CLOUD_SOURCE_REPOSITORIES"
  }
  
  build {
    timeout = var.build_timeout
    
    options {
      machine_type = var.build_machine_type
      logging      = "CLOUD_LOGGING_ONLY"
    }
    
    substitutions = {
      _REPO_NAME    = google_sourcerepo_repository.code_review_repo.name
      _FUNCTION_URL = google_cloudfunctions2_function.code_review_function.service_config[0].uri
      _QUEUE_NAME   = google_cloud_tasks_queue.code_review_queue.name
      _REGION       = var.region
      _PROJECT_ID   = var.project_id
    }
    
    artifacts {
      objects {
        location = "gs://${google_storage_bucket.build_artifacts.name}/feature-artifacts"
        paths    = ["dist/**/*", "test-results/**/*"]
      }
    }
  }
  
  included_files = ["**/*"]
  ignored_files  = ["README.md", "docs/**/*"]
  
  tags = ["feature-branch", "automated-review"]
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.code_review_function
  ]
}

# Create Firebase project configuration (if Firebase Studio is enabled)
resource "google_firebase_project" "code_review_firebase" {
  count = var.enable_firebase_studio ? 1 : 0
  
  provider = google-beta
  project  = local.firebase_project
  
  depends_on = [google_project_service.required_apis]
}

# Create budget alert for cost management
resource "google_billing_budget" "code_review_budget" {
  count = var.enable_budget_alerts ? 1 : 0
  
  billing_account = data.google_billing_account.account.id
  display_name    = "${local.base_name} Budget Alert"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
    
    # Filter by labels to track only this recipe's costs
    labels = {
      environment = [var.environment]
      recipe      = ["automated-code-review"]
      managed-by  = ["terraform"]
    }
  }
  
  amount {
    specified_amount {
      amount = var.monthly_budget_amount
      units  = "USD"
    }
  }
  
  # Alert thresholds
  threshold_rules {
    threshold_percent = 0.5  # 50%
    spend_basis      = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 0.8  # 80%
    spend_basis      = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 1.0  # 100%
    spend_basis      = "CURRENT_SPEND"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Data source for billing account
data "google_billing_account" "account" {
  open = true
}

# Create Cloud Monitoring alert policies for the pipeline
resource "google_monitoring_alert_policy" "function_error_rate" {
  count = var.enable_cloud_monitoring ? 1 : 0
  
  display_name = "${local.base_name} Function Error Rate Alert"
  project      = var.project_id
  
  conditions {
    display_name = "Function error rate too high"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1  # 10% error rate
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  alert_strategy {
    auto_close = "1800s"  # 30 minutes
  }
  
  enabled = true
  
  depends_on = [google_project_service.required_apis]
}

# Create log sink for centralized logging
resource "google_logging_project_sink" "code_review_logs" {
  count = var.enable_cloud_logging ? 1 : 0
  
  name        = "${local.base_name}-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.metrics_storage.name}/logs"
  
  # Filter for code review related logs
  filter = "resource.type=\"cloud_function\" AND (resource.labels.function_name=\"${local.function_name}\" OR resource.labels.function_name=\"${local.metrics_function}\") OR resource.type=\"cloud_build\""
  
  # Use a unique writer identity
  unique_writer_identity = true
  
  depends_on = [google_project_service.required_apis]
}

# Grant the log sink permission to write to the storage bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_cloud_logging ? 1 : 0
  
  bucket = google_storage_bucket.metrics_storage.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.code_review_logs[0].writer_identity
}

# Output key resource information
output "repository_url" {
  description = "URL of the Cloud Source Repository"
  value       = google_sourcerepo_repository.code_review_repo.url
}

output "function_url" {
  description = "URL of the code review Cloud Function"
  value       = google_cloudfunctions2_function.code_review_function.service_config[0].uri
}

output "metrics_function_url" {
  description = "URL of the metrics collection Cloud Function"
  value       = google_cloudfunctions2_function.metrics_function.service_config[0].uri
}

output "build_artifacts_bucket" {
  description = "Name of the build artifacts storage bucket"
  value       = google_storage_bucket.build_artifacts.name
}

output "metrics_storage_bucket" {
  description = "Name of the metrics storage bucket"
  value       = google_storage_bucket.metrics_storage.name
}

output "task_queue_name" {
  description = "Name of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.code_review_queue.name
}

output "firebase_project_id" {
  description = "Firebase project ID for Studio integration"
  value       = local.firebase_project
}

output "cloud_build_triggers" {
  description = "List of Cloud Build trigger names"
  value = concat(
    [google_cloudbuild_trigger.main_branch_trigger.name],
    var.trigger_branches != null && length(var.trigger_branches) > 1 ? [google_cloudbuild_trigger.feature_branch_trigger[0].name] : []
  )
}