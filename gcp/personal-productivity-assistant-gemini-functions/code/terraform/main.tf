# GCP Personal Productivity Assistant with Gemini and Functions
# Terraform Infrastructure as Code
# This configuration deploys a complete AI-powered email processing system

# Data source for current project information
data "google_project" "current" {}

# Data source for client configuration (for default region)
data "google_client_config" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Locals for consistent naming and configuration
locals {
  base_name = "productivity-assistant"
  name_suffix = random_id.suffix.hex
  
  # Common labels applied to all resources
  common_labels = {
    project     = "personal-productivity-assistant"
    environment = var.environment
    managed-by  = "terraform"
    recipe-id   = "b4f7e2a8"
  }
  
  # Required Google Cloud APIs
  required_apis = [
    "cloudfunctions.googleapis.com",
    "aiplatform.googleapis.com",
    "firestore.googleapis.com",
    "pubsub.googleapis.com",
    "cloudscheduler.googleapis.com",
    "gmail.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent destruction of APIs during cleanup
  disable_dependent_services = false
  disable_on_destroy         = false
  
  # Add a small delay between API enablement
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Firestore Database in Native Mode
# Provides NoSQL document storage for email analysis results and action items
resource "google_firestore_database" "productivity_db" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"
  
  # Enable point-in-time recovery for data protection
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  
  # App Engine integration mode for better performance
  app_engine_integration_mode = "DISABLED"
  
  depends_on = [google_project_service.apis]
}

# Cloud Storage bucket for function source code and temporary files
resource "google_storage_bucket" "function_source" {
  name     = "${local.base_name}-functions-${local.name_suffix}"
  project  = var.project_id
  location = var.region
  
  # Enable versioning for function deployments
  versioning {
    enabled = true
  }
  
  # Lifecycle management to control costs
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Security configurations
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Pub/Sub Topic for asynchronous email processing
resource "google_pubsub_topic" "email_processing" {
  name    = "email-processing-topic"
  project = var.project_id
  
  # Enable message retention for reliability
  message_retention_duration = "604800s" # 7 days
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Pub/Sub Subscription for email processing topic
resource "google_pubsub_subscription" "email_processing" {
  name    = "email-processing-sub"
  topic   = google_pubsub_topic.email_processing.name
  project = var.project_id
  
  # Configure message acknowledgment and retry behavior
  ack_deadline_seconds = 300
  
  # Dead letter configuration for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  # Exponential backoff retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
  
  # Enable exactly once delivery for critical email processing
  enable_exactly_once_delivery = true
  
  labels = local.common_labels
}

# Dead Letter Topic for failed message handling
resource "google_pubsub_topic" "dead_letter" {
  name    = "email-processing-dead-letter"
  project = var.project_id
  
  message_retention_duration = "604800s" # 7 days
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Service Account for Cloud Functions with least privilege permissions
resource "google_service_account" "function_sa" {
  account_id   = "${local.base_name}-function-sa"
  display_name = "Personal Productivity Assistant Function Service Account"
  description  = "Service account for Cloud Functions with AI and storage access"
  project      = var.project_id
  
  depends_on = [google_project_service.apis]
}

# IAM bindings for Function Service Account - Vertex AI access
resource "google_project_iam_member" "function_vertex_ai" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM bindings for Function Service Account - Firestore access
resource "google_project_iam_member" "function_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM bindings for Function Service Account - Pub/Sub publish
resource "google_project_iam_member" "function_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM bindings for Function Service Account - Pub/Sub subscriber
resource "google_project_iam_member" "function_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM bindings for Function Service Account - Logging
resource "google_project_iam_member" "function_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Archive file for email processing function source code
data "archive_file" "email_processor_source" {
  type        = "zip"
  output_path = "${path.module}/email-processor.zip"
  
  source {
    content = templatefile("${path.module}/function-source/main.py", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function-source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage object for email processing function source
resource "google_storage_bucket_object" "email_processor_source" {
  name   = "email-processor-${data.archive_file.email_processor_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.email_processor_source.output_path
  
  depends_on = [data.archive_file.email_processor_source]
}

# Main Email Processing Cloud Function (HTTP triggered)
resource "google_cloudfunctions_function" "email_processor" {
  name        = "email-processor"
  project     = var.project_id
  region      = var.region
  description = "AI-powered email processing using Gemini 2.5 Flash for action item extraction and response generation"
  
  runtime     = "python312"
  entry_point = "process_email"
  
  # Function source configuration
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.email_processor_source.name
  
  # HTTP trigger configuration
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  # Resource allocation for AI workloads
  available_memory_mb   = 1024
  timeout               = 300
  max_instances         = 100
  min_instances         = 0
  
  # Environment variables
  environment_variables = {
    GCP_PROJECT = var.project_id
    REGION      = var.region
  }
  
  # Service account configuration
  service_account_email = google_service_account.function_sa.email
  
  # Security and networking
  ingress_settings = "ALLOW_ALL"
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_storage_bucket_object.email_processor_source,
    google_project_iam_member.function_vertex_ai,
    google_project_iam_member.function_firestore,
    google_project_iam_member.function_pubsub_publisher
  ]
}

# Archive file for scheduled processing function
data "archive_file" "scheduled_processor_source" {
  type        = "zip"
  output_path = "${path.module}/scheduled-processor.zip"
  
  source {
    content = templatefile("${path.module}/function-source/scheduled_main.py", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function-source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage object for scheduled processing function source
resource "google_storage_bucket_object" "scheduled_processor_source" {
  name   = "scheduled-processor-${data.archive_file.scheduled_processor_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.scheduled_processor_source.output_path
  
  depends_on = [data.archive_file.scheduled_processor_source]
}

# Scheduled Email Processing Cloud Function (Pub/Sub triggered)
resource "google_cloudfunctions_function" "scheduled_processor" {
  name        = "scheduled-email-processor"
  project     = var.project_id
  region      = var.region
  description = "Scheduled email processing function triggered by Cloud Scheduler via Pub/Sub"
  
  runtime     = "python312"
  entry_point = "process_scheduled_emails"
  
  # Function source configuration
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.scheduled_processor_source.name
  
  # Pub/Sub trigger configuration
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.email_processing.id
    
    failure_policy {
      retry = true
    }
  }
  
  # Resource allocation
  available_memory_mb = 512
  timeout             = 180
  max_instances       = 10
  min_instances       = 0
  
  # Environment variables
  environment_variables = {
    GCP_PROJECT = var.project_id
    REGION      = var.region
  }
  
  # Service account configuration
  service_account_email = google_service_account.function_sa.email
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_storage_bucket_object.scheduled_processor_source,
    google_pubsub_topic.email_processing,
    google_project_iam_member.function_firestore,
    google_project_iam_member.function_pubsub_subscriber
  ]
}

# Cloud Scheduler Job for automated email processing
resource "google_cloud_scheduler_job" "email_processing_schedule" {
  name        = "email-processing-schedule"
  project     = var.project_id
  region      = var.region
  description = "Automated email processing trigger - runs every 15 minutes during business hours"
  
  # Schedule: Every 15 minutes from 8 AM to 6 PM, Monday to Friday (timezone configurable)
  schedule  = var.schedule_cron
  time_zone = var.schedule_timezone
  
  # Pub/Sub target configuration
  pubsub_target {
    topic_name = google_pubsub_topic.email_processing.id
    data       = base64encode(jsonencode({
      trigger    = "scheduled"
      timestamp  = "{{.timestamp}}"
      job_name   = "email-processing-schedule"
    }))
  }
  
  # Retry configuration for reliability
  retry_config {
    retry_count = 3
  }
  
  depends_on = [
    google_project_service.apis,
    google_pubsub_topic.email_processing
  ]
}

# Cloud Monitoring Alert Policy for function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Personal Productivity Assistant - High Error Rate"
  project      = var.project_id
  
  conditions {
    display_name = "Cloud Function error rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"email-processor\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1 # 10% error rate threshold
      duration        = "300s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields    = ["resource.labels.function_name"]
      }
    }
  }
  
  # Notification channels would be configured separately
  alert_strategy {
    notification_rate_limit {
      period = "300s" # Maximum one alert every 5 minutes
    }
    
    auto_close = "604800s" # Auto-close after 7 days
  }
  
  enabled = true
  
  depends_on = [google_project_service.apis]
}

# Cloud Monitoring Dashboard for productivity assistant metrics
resource "google_monitoring_dashboard" "productivity_dashboard" {
  count          = var.enable_monitoring ? 1 : 0
  project        = var.project_id
  dashboard_json = templatefile("${path.module}/monitoring/dashboard.json", {
    project_id = var.project_id
  })
  
  depends_on = [google_project_service.apis]
}

# IAM policy for allowing unauthenticated access to the HTTP function (if enabled)
resource "google_cloudfunctions_function_iam_member" "invoker" {
  count          = var.allow_unauthenticated_access ? 1 : 0
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.email_processor.name
  
  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}

# Security: Cloud Armor security policy (optional, for enhanced protection)
resource "google_compute_security_policy" "productivity_security_policy" {
  count   = var.enable_security_policy ? 1 : 0
  name    = "${local.base_name}-security-policy"
  project = var.project_id
  
  description = "Security policy for Personal Productivity Assistant API endpoints"
  
  # Default rule - allow all traffic (can be customized)
  rule {
    action   = "allow"
    priority = "2147483647"
    
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    
    description = "Default allow rule"
  }
  
  # Rate limiting rule
  rule {
    action   = "rate_based_ban"
    priority = "1000"
    
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      
      rate_limit_threshold {
        count        = 60
        interval_sec = 60
      }
      
      ban_duration_sec = 300
    }
    
    description = "Rate limiting: 60 requests per minute per IP"
  }
  
  depends_on = [google_project_service.apis]
}