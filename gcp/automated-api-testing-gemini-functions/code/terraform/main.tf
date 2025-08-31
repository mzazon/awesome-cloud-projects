# Main Terraform configuration for GCP automated API testing infrastructure
# This file provisions all resources needed for the AI-powered API testing solution

# ==============================================================================
# LOCAL VALUES AND DATA SOURCES
# ==============================================================================

# Generate random suffix for resource names to ensure uniqueness
resource "random_id" "suffix" {
  byte_length = var.random_suffix_length / 2
}

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Define local values for consistent resource naming and configuration
locals {
  # Resource naming
  suffix = random_id.suffix.hex
  
  # Service names with unique suffixes
  function_name     = "${var.resource_prefix}-orchestrator-${local.suffix}"
  cloud_run_name    = "${var.resource_prefix}-runner-${local.suffix}"
  bucket_name       = "${var.project_id}-test-results-${local.suffix}"
  
  # Location configuration
  vertex_ai_location = var.vertex_ai_location != "" ? var.vertex_ai_location : var.region
  
  # Merged labels for all resources
  common_labels = merge({
    environment    = var.environment
    project        = "api-testing"
    managed-by     = "terraform"
    recipe-id      = "a8f9e3d2"
    solution       = "automated-api-testing"
  }, var.custom_labels)
  
  # Required APIs for the solution
  required_apis = [
    "aiplatform.googleapis.com",
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com",
    "secretmanager.googleapis.com",
    "monitoring.googleapis.com",
    "cloudtrace.googleapis.com",
    "cloudprofiler.googleapis.com"
  ]
}

# ==============================================================================
# ENABLE REQUIRED APIS
# ==============================================================================

# Enable all required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent destruction of services when removing from Terraform
  disable_on_destroy = false
  
  # Wait for service enablement to complete
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# ==============================================================================
# IAM SERVICE ACCOUNTS
# ==============================================================================

# Service account for Cloud Function (test case generator)
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_prefix}-function-sa-${local.suffix}"
  display_name = "API Testing Function Service Account"
  description  = "Service account for Cloud Function that generates test cases using Vertex AI"
  project      = var.project_id
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Service account for Cloud Run (test runner)
resource "google_service_account" "cloud_run_sa" {
  account_id   = "${var.resource_prefix}-runner-sa-${local.suffix}"
  display_name = "API Testing Runner Service Account"
  description  = "Service account for Cloud Run service that executes API tests"
  project      = var.project_id
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# ==============================================================================
# IAM ROLE BINDINGS
# ==============================================================================

# Cloud Function IAM permissions
resource "google_project_iam_member" "function_vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Cloud Run IAM permissions
resource "google_project_iam_member" "cloud_run_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "cloud_run_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "cloud_run_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Optional: Secret Manager access if enabled
resource "google_project_iam_member" "function_secret_accessor" {
  count   = var.enable_secret_manager ? 1 : 0
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "cloud_run_secret_accessor" {
  count   = var.enable_secret_manager ? 1 : 0
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# ==============================================================================
# CLOUD STORAGE BUCKET
# ==============================================================================

# Main storage bucket for test results and artifacts
resource "google_storage_bucket" "test_results" {
  name                        = local.bucket_name
  location                    = var.region
  project                     = var.project_id
  storage_class              = var.storage_class
  uniform_bucket_level_access = true
  
  # Enable versioning for test result history
  versioning {
    enabled = var.versioning_enabled
  }
  
  # Configure lifecycle rules for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules_enabled ? [1] : []
    
    content {
      condition {
        age = var.test_results_retention_days
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Additional lifecycle rule for old versions
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules_enabled && var.versioning_enabled ? [1] : []
    
    content {
      condition {
        age                = 30
        with_state        = "ARCHIVED"
        num_newer_versions = 3
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # CORS configuration for web access
  cors {
    origin          = var.cors_origins
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  # Encryption configuration
  encryption {
    default_kms_key_name = var.enable_secret_manager ? google_kms_crypto_key.bucket_key[0].id : null
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Create initial folder structure in the bucket
resource "google_storage_bucket_object" "test_specifications_folder" {
  name    = "test-specifications/.keep"
  bucket  = google_storage_bucket.test_results.name
  content = "# This file maintains the test-specifications folder structure"
}

resource "google_storage_bucket_object" "test_results_folder" {
  name    = "test-results/.keep"
  bucket  = google_storage_bucket.test_results.name
  content = "# This file maintains the test-results folder structure"
}

resource "google_storage_bucket_object" "reports_folder" {
  name    = "reports/.keep"
  bucket  = google_storage_bucket.test_results.name
  content = "# This file maintains the reports folder structure"
}

# ==============================================================================
# KMS ENCRYPTION (Optional)
# ==============================================================================

# KMS key ring for bucket encryption
resource "google_kms_key_ring" "main" {
  count    = var.enable_secret_manager ? 1 : 0
  name     = "${var.resource_prefix}-keyring-${local.suffix}"
  location = var.region
  project  = var.project_id
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# KMS key for bucket encryption
resource "google_kms_crypto_key" "bucket_key" {
  count           = var.enable_secret_manager ? 1 : 0
  name            = "${var.resource_prefix}-bucket-key"
  key_ring        = google_kms_key_ring.main[0].id
  rotation_period = "7776000s"  # 90 days
  
  labels = local.common_labels
}

# ==============================================================================
# CLOUD FUNCTION SOURCE CODE
# ==============================================================================

# Create source code archive for Cloud Function
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      bucket_name    = local.bucket_name
      gemini_model   = var.gemini_model
      project_id     = var.project_id
      location       = local.vertex_ai_location
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.suffix}.zip"
  bucket = google_storage_bucket.test_results.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [
    data.archive_file.function_source
  ]
}

# ==============================================================================
# CLOUD FUNCTION
# ==============================================================================

# Cloud Function for test case generation using Vertex AI
resource "google_cloudfunctions2_function" "test_generator" {
  name        = local.function_name
  location    = var.region
  project     = var.project_id
  description = "AI-powered test case generator using Vertex AI Gemini"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "generate_test_cases"
    
    source {
      storage_source {
        bucket = google_storage_bucket.test_results.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count             = var.function_max_instances
    min_instance_count             = var.function_min_instances
    available_memory               = var.function_memory
    timeout_seconds                = var.function_timeout
    max_instance_request_concurrency = 1
    
    environment_variables = {
      BUCKET_NAME        = local.bucket_name
      GEMINI_MODEL       = var.gemini_model
      VERTEX_AI_LOCATION = local.vertex_ai_location
      FUNCTION_REGION    = var.region
    }
    
    service_account_email = google_service_account.function_sa.email
    
    # VPC connector configuration (optional)
    dynamic "vpc_connector" {
      for_each = var.enable_vpc_connector ? [1] : []
      content {
        name = var.vpc_connector_name
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# IAM policy for Cloud Function invocation
resource "google_cloudfunctions2_function_iam_member" "function_invoker" {
  count          = var.allow_unauthenticated_access ? 1 : 0
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.test_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# ==============================================================================
# CLOUD RUN SERVICE
# ==============================================================================

# Cloud Run service for test execution
resource "google_cloud_run_v2_service" "test_runner" {
  name     = local.cloud_run_name
  location = var.region
  project  = var.project_id
  
  template {
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }
    
    containers {
      image = "gcr.io/${var.project_id}/${local.cloud_run_name}:latest"
      
      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
      }
      
      env {
        name  = "BUCKET_NAME"
        value = local.bucket_name
      }
      
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      env {
        name  = "REGION"
        value = var.region
      }
      
      # Health check configuration
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 0
        timeout_seconds       = 1
        period_seconds        = 3
        failure_threshold     = 1
      }
      
      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 0
        timeout_seconds       = 1
        period_seconds        = 3
        failure_threshold     = 3
      }
    }
    
    max_instance_request_concurrency = var.cloud_run_concurrency
    execution_environment           = "EXECUTION_ENVIRONMENT_GEN2"
    timeout                        = "${var.cloud_run_timeout}s"
    
    service_account = google_service_account.cloud_run_sa.email
    
    # VPC connector configuration (optional)
    dynamic "vpc_access" {
      for_each = var.enable_vpc_connector ? [1] : []
      content {
        connector = var.vpc_connector_name
      }
    }
  }
  
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# IAM policy for Cloud Run invocation
resource "google_cloud_run_service_iam_member" "cloud_run_invoker" {
  count    = var.allow_unauthenticated_access ? 1 : 0
  project  = var.project_id
  location = var.region
  service  = google_cloud_run_v2_service.test_runner.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ==============================================================================
# CLOUD BUILD TRIGGER FOR CLOUD RUN
# ==============================================================================

# Cloud Build trigger for automated deployment
resource "google_cloudbuild_trigger" "cloud_run_deploy" {
  name        = "${var.resource_prefix}-deploy-trigger-${local.suffix}"
  project     = var.project_id
  description = "Trigger for building and deploying Cloud Run service"
  
  # Trigger on push to main branch (configure as needed)
  github {
    owner = "your-github-username"  # Configure this
    name  = "your-repo-name"        # Configure this
    push {
      branch = "^main$"
    }
  }
  
  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = ["build", "-t", "gcr.io/${var.project_id}/${local.cloud_run_name}:$COMMIT_SHA", "."]
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = ["push", "gcr.io/${var.project_id}/${local.cloud_run_name}:$COMMIT_SHA"]
    }
    
    step {
      name = "gcr.io/google.com/cloudsdktool/cloud-sdk"
      args = [
        "gcloud", "run", "deploy", local.cloud_run_name,
        "--image", "gcr.io/${var.project_id}/${local.cloud_run_name}:$COMMIT_SHA",
        "--region", var.region,
        "--platform", "managed"
      ]
    }
  }
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# ==============================================================================
# MONITORING AND ALERTING
# ==============================================================================

# Notification channel for alerts (email)
resource "google_monitoring_notification_channel" "email" {
  count        = var.enable_cloud_monitoring ? 1 : 0
  project      = var.project_id
  display_name = "API Testing Alerts"
  type         = "email"
  
  labels = {
    email_address = "admin@${var.project_id}.iam.gserviceaccount.com"
  }
}

# Alert policy for function errors
resource "google_monitoring_alert_policy" "function_errors" {
  count        = var.enable_cloud_monitoring ? 1 : 0
  project      = var.project_id
  display_name = "Cloud Function Error Rate"
  combiner     = "OR"
  
  conditions {
    display_name = "Function error rate too high"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email[0].id]
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Alert policy for Cloud Run errors
resource "google_monitoring_alert_policy" "cloud_run_errors" {
  count        = var.enable_cloud_monitoring ? 1 : 0
  project      = var.project_id
  display_name = "Cloud Run Error Rate"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Run error rate too high"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.cloud_run_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 10
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email[0].id]
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# ==============================================================================
# SECRET MANAGER (Optional)
# ==============================================================================

# Secret for storing API keys or other sensitive configuration
resource "google_secret_manager_secret" "api_config" {
  count     = var.enable_secret_manager ? 1 : 0
  project   = var.project_id
  secret_id = "${var.resource_prefix}-config-${local.suffix}"
  
  replication {
    auto {}
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Initial secret version with default configuration
resource "google_secret_manager_secret_version" "api_config_version" {
  count  = var.enable_secret_manager ? 1 : 0
  secret = google_secret_manager_secret.api_config[0].id
  
  secret_data = jsonencode({
    gemini_model = var.gemini_model
    test_types   = ["functional", "security", "performance"]
    timeout      = 30
  })
}