# Code Review Automation Infrastructure
# This file defines the main infrastructure components for AI-powered code review automation
# using Firebase Studio, Cloud Source Repositories, Vertex AI, and Cloud Functions

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming and tagging
  name_prefix = "${var.environment}-${var.repository_name}"
  random_suffix = random_id.suffix.hex
  
  # Enhanced labels with generated values
  common_labels = merge(var.labels, {
    environment     = var.environment
    deployment-id   = local.random_suffix
    creation-date   = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Required Google Cloud APIs for the solution
  required_apis = [
    "sourcerepo.googleapis.com",
    "cloudfunctions.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "firebase.googleapis.com",
    "eventarc.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Cloud Source Repository for code review system
resource "google_sourcerepo_repository" "code_review_repo" {
  name    = "${var.repository_name}-${local.random_suffix}"
  project = var.project_id
  
  depends_on = [google_project_service.required_apis]
  
  # Note: Cloud Source Repositories don't support labels directly
  # Labels are applied through project-level metadata
}

# Create Cloud Storage bucket for function source code and artifacts
resource "google_storage_bucket" "function_source" {
  name     = "${local.name_prefix}-function-source-${local.random_suffix}"
  location = var.region
  project  = var.project_id
  
  # Enable versioning for source code management
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
  
  # Security configurations
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for analysis results and logs
resource "google_storage_bucket" "analysis_results" {
  name     = "${local.name_prefix}-analysis-${local.random_suffix}"
  location = var.region
  project  = var.project_id
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Service Account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa-${local.random_suffix}"
  display_name = "Code Review Function Service Account"
  description  = "Service account for automated code review Cloud Function"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for the Cloud Function service account
resource "google_project_iam_member" "function_sa_roles" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/source.reader",
    "roles/storage.objectAdmin",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/secretmanager.secretAccessor",
    "roles/eventarc.eventReceiver"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [google_service_account.function_sa]
}

# Secret Manager secret for Vertex AI configuration
resource "google_secret_manager_secret" "vertex_ai_config" {
  secret_id = "${var.agent_name}-config-${local.random_suffix}"
  project   = var.project_id
  
  labels = local.common_labels
  
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Store the Vertex AI configuration in Secret Manager
resource "google_secret_manager_secret_version" "vertex_ai_config_data" {
  secret = google_secret_manager_secret.vertex_ai_config.name
  
  secret_data = jsonencode({
    model              = var.vertex_ai_model
    temperature        = var.code_analysis_config.temperature
    max_tokens         = var.code_analysis_config.max_tokens
    analysis_depth     = var.code_analysis_config.analysis_depth
    include_suggestions = var.code_analysis_config.include_suggestions
    check_security     = var.code_analysis_config.check_security
    check_performance  = var.code_analysis_config.check_performance
    check_best_practices = var.code_analysis_config.check_best_practices
    supported_languages = var.supported_languages
  })
}

# Create the Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function-source/index.js", {
      project_id = var.project_id
      region     = var.region
      model_name = var.vertex_ai_model
      secret_name = google_secret_manager_secret.vertex_ai_config.secret_id
      analysis_bucket = google_storage_bucket.analysis_results.name
    })
    filename = "index.js"
  }
  
  source {
    content = templatefile("${path.module}/function-source/package.json", {
      function_name = var.function_name
    })
    filename = "package.json"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Create Cloud Function for code review automation
resource "google_cloudfunctions2_function" "code_review_trigger" {
  name     = "${var.function_name}-${local.random_suffix}"
  location = var.region
  project  = var.project_id
  
  description = "AI-powered code review automation function"
  
  build_config {
    runtime     = "nodejs20"
    entry_point = "codeReviewTrigger"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = var.max_concurrent_reviews
    min_instance_count               = 0
    available_memory                 = var.function_memory
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID              = var.project_id
      REGION                  = var.region
      VERTEX_AI_MODEL         = var.vertex_ai_model
      AGENT_NAME              = var.agent_name
      SECRET_NAME             = google_secret_manager_secret.vertex_ai_config.secret_id
      ANALYSIS_BUCKET         = google_storage_bucket.analysis_results.name
      REPOSITORY_NAME         = google_sourcerepo_repository.code_review_repo.name
      ENABLE_SECURITY_SCAN    = var.enable_security_scanning
      MAX_CONCURRENT_REVIEWS  = var.max_concurrent_reviews
    }
    
    service_account_email = google_service_account.function_sa.email
    
    ingress_settings = "ALLOW_ALL"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_project_iam_member.function_sa_roles
  ]
}

# Create Eventarc trigger for repository events
resource "google_eventarc_trigger" "repo_events" {
  name     = "${var.repository_name}-events-${local.random_suffix}"
  location = var.region
  project  = var.project_id
  
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.source.repositories.v1.revisionCreated"
  }
  
  matching_criteria {
    attribute = "source"
    value     = "//source.googleapis.com/projects/${var.project_id}/repos/${google_sourcerepo_repository.code_review_repo.name}"
  }
  
  destination {
    cloud_function = google_cloudfunctions2_function.code_review_trigger.name
  }
  
  service_account = google_service_account.function_sa.email
  
  labels = local.common_labels
  
  depends_on = [
    google_cloudfunctions2_function.code_review_trigger,
    google_project_service.required_apis
  ]
}

# Firebase project configuration (if Firebase Studio is enabled)
resource "google_firebase_project" "code_review_firebase" {
  count = var.enable_firebase_studio ? 1 : 0
  
  provider = google-beta
  project  = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Firebase Studio workspace configuration
resource "google_firebase_hosting_site" "studio_workspace" {
  count = var.enable_firebase_studio ? 1 : 0
  
  provider = google-beta
  project  = var.project_id
  site_id  = "${var.agent_name}-workspace-${local.random_suffix}"
  
  depends_on = [google_firebase_project.code_review_firebase]
}

# Cloud Monitoring notification channel (if monitoring is enabled)
resource "google_monitoring_notification_channel" "email_alerts" {
  count = var.enable_monitoring && length(var.notification_channels) > 0 ? length(var.notification_channels) : 0
  
  display_name = "Code Review Alert Channel ${count.index + 1}"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = var.notification_channels[count.index]
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring alert policy for function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Code Review Function High Error Rate"
  project      = var.project_id
  
  conditions {
    display_name = "Function error rate above threshold"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.code_review_trigger.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = var.enable_monitoring && length(var.notification_channels) > 0 ? google_monitoring_notification_channel.email_alerts[*].name : []
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Logging sink for structured analysis logs
resource "google_logging_project_sink" "analysis_logs" {
  name        = "${var.function_name}-analysis-logs-${local.random_suffix}"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.analysis_results.name}"
  
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.code_review_trigger.name}\" AND jsonPayload.analysis_type EXISTS"
  
  unique_writer_identity = true
  
  depends_on = [google_project_service.required_apis]
}

# Grant the logging service account permission to write to the bucket
resource "google_storage_bucket_iam_member" "logging_sink_writer" {
  bucket = google_storage_bucket.analysis_results.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.analysis_logs.writer_identity
  
  depends_on = [google_logging_project_sink.analysis_logs]
}

# Create function source files in the local directory for deployment
resource "local_file" "function_index_js" {
  content = templatefile("${path.module}/templates/index.js.tpl", {
    project_id      = var.project_id
    region          = var.region
    model_name      = var.vertex_ai_model
    secret_name     = google_secret_manager_secret.vertex_ai_config.secret_id
    analysis_bucket = google_storage_bucket.analysis_results.name
  })
  filename = "${path.module}/function-source/index.js"
}

resource "local_file" "function_package_json" {
  content = templatefile("${path.module}/templates/package.json.tpl", {
    function_name = var.function_name
  })
  filename = "${path.module}/function-source/package.json"
}