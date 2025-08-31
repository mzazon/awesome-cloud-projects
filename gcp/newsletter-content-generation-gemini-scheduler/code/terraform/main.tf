# Newsletter Content Generation with Gemini and Scheduler - Terraform Configuration
# This configuration deploys a serverless newsletter content generation system
# using Google Cloud Functions, Vertex AI Gemini, Cloud Scheduler, and Cloud Storage

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Computed values for consistent naming
  resource_suffix = random_id.suffix.hex
  function_name   = "${var.resource_prefix}-${var.function_name}-${local.resource_suffix}"
  bucket_name     = "${var.resource_prefix}-content-${var.project_id}-${local.resource_suffix}"
  job_name        = "${var.resource_prefix}-schedule-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    component   = "newsletter-generation"
    created_by  = "terraform"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "aiplatform.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com",
    "pubsub.googleapis.com"
  ])
  
  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Cloud Storage bucket for newsletter content storage
resource "google_storage_bucket" "newsletter_content" {
  name                        = local.bucket_name
  location                    = var.region
  storage_class              = var.bucket_storage_class
  uniform_bucket_level_access = true
  
  # Enable versioning for content history
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.lifecycle_age_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Lifecycle rule for moving old versions to cheaper storage
  dynamic "lifecycle_rule" {
    for_each = var.enable_versioning ? [1] : []
    content {
      condition {
        age                   = 7
        with_state           = "ARCHIVED"
        matches_storage_class = ["STANDARD"]
      }
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create folder structure in the bucket using objects
resource "google_storage_bucket_object" "content_folders" {
  for_each = toset([
    "templates/",
    "generated-content/",
    "logs/"
  ])
  
  name   = each.value
  bucket = google_storage_bucket.newsletter_content.name
  content = " " # Placeholder content for folder creation
}

# Upload content template to Cloud Storage
resource "google_storage_bucket_object" "content_template" {
  name   = "templates/content-template.json"
  bucket = google_storage_bucket.newsletter_content.name
  content = jsonencode({
    newsletter_template = {
      subject_line     = "Generate an engaging subject line about {topic}"
      intro           = "Write a brief introduction paragraph about {topic} in a professional yet friendly tone"
      main_content    = "Create 2-3 paragraphs of informative content about {topic}, including practical tips or insights"
      call_to_action  = "Write a compelling call-to-action related to {topic}"
      tone           = "professional, engaging, informative"
      target_audience = "business professionals and marketing teams"
      word_limit     = 300
    }
  })
  
  depends_on = [google_storage_bucket_object.content_folders]
}

# Service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_prefix}-function-sa-${local.resource_suffix}"
  display_name = "Newsletter Generation Function Service Account"
  description  = "Service account for the newsletter generation Cloud Function"
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for the service account to access Vertex AI
resource "google_project_iam_member" "function_vertex_ai" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for the service account to access Cloud Storage
resource "google_project_iam_member" "function_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Build to deploy functions
resource "google_project_iam_member" "cloudbuild_function_developer" {
  project = var.project_id
  role    = "roles/cloudfunctions.developer"
  member  = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
}

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Create the function source files locally for the archive
resource "local_file" "function_main" {
  content = templatefile("${path.module}/templates/main.py.tpl", {
    bucket_name = google_storage_bucket.newsletter_content.name
    project_id  = var.project_id
    location    = var.vertex_ai_location
  })
  filename = "${path.module}/function_code/main.py"
}

resource "local_file" "function_requirements" {
  content  = file("${path.module}/templates/requirements.txt")
  filename = "${path.module}/function_code/requirements.txt"
}

# Create source code archive for Cloud Function
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  source_dir  = "${path.module}/function_code"
  
  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source/newsletter-generator-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.newsletter_content.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Cloud Function for newsletter content generation
resource "google_cloudfunctions2_function" "newsletter_generator" {
  name        = local.function_name
  location    = var.region
  description = "Generates newsletter content using Gemini AI"
  
  build_config {
    runtime     = var.python_runtime
    entry_point = "generate_newsletter"
    
    source {
      storage_source {
        bucket = google_storage_bucket.newsletter_content.name
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
    
    environment_variables = {
      BUCKET_NAME        = google_storage_bucket.newsletter_content.name
      PROJECT_ID         = var.project_id
      VERTEX_AI_LOCATION = var.vertex_ai_location
    }
    
    ingress_settings               = var.enable_public_access ? "ALLOW_ALL" : "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_sa.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_project_iam_member.function_vertex_ai,
    google_project_iam_member.function_storage
  ]
}

# IAM binding for Cloud Function invocation
resource "google_cloudfunctions2_function_iam_member" "function_invoker" {
  count = var.enable_public_access ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.newsletter_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# IAM binding for specific members (when public access is disabled)
resource "google_cloudfunctions2_function_iam_member" "function_invoker_members" {
  for_each = var.enable_public_access ? toset([]) : toset(var.allowed_members)
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.newsletter_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = each.value
}

# Service account for Cloud Scheduler
resource "google_service_account" "scheduler_sa" {
  account_id   = "${var.resource_prefix}-scheduler-sa-${local.resource_suffix}"
  display_name = "Newsletter Scheduler Service Account"
  description  = "Service account for the newsletter generation scheduler"
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for scheduler to invoke Cloud Function
resource "google_cloudfunctions2_function_iam_member" "scheduler_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.newsletter_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

# Cloud Scheduler job for automated newsletter generation
resource "google_cloud_scheduler_job" "newsletter_schedule" {
  name             = local.job_name
  region           = var.region
  description      = "Automated newsletter content generation schedule"
  schedule         = var.schedule_cron
  time_zone        = var.schedule_timezone
  attempt_deadline = "300s"
  
  retry_config {
    retry_count          = 3
    max_retry_duration   = "60s"
    max_backoff_duration = "30s"
    min_backoff_duration = "5s"
  }
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.newsletter_generator.service_config[0].uri
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      topic = var.default_newsletter_topic
    }))
    
    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
      audience              = google_cloudfunctions2_function.newsletter_generator.service_config[0].uri
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.newsletter_generator,
    google_cloudfunctions2_function_iam_member.scheduler_invoker
  ]
}

# Conditional monitoring and alerting resources
resource "google_monitoring_notification_channel" "email_alert" {
  count = var.enable_monitoring && var.alert_email != "" ? 1 : 0
  
  display_name = "Newsletter Generation Email Alerts"
  type         = "email"
  
  labels = {
    email_address = var.alert_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alert policy for function failures
resource "google_monitoring_alert_policy" "function_failure_alert" {
  count = var.enable_monitoring && var.alert_email != "" ? 1 : 0
  
  display_name = "Newsletter Generation Function Failures"
  combiner     = "OR"
  
  conditions {
    display_name = "Function execution failures"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\" AND metric.type=\"logging.googleapis.com/user/function_execution_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email_alert[0].id]
  
  depends_on = [google_project_service.required_apis]
}