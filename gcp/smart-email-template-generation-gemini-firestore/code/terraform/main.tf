# ============================================================================
# Smart Email Template Generation with Gemini and Firestore
# ============================================================================
# This Terraform configuration deploys an AI-powered email template generator
# using Vertex AI Gemini for intelligent content creation, Firestore for 
# storing user preferences and templates, and Cloud Functions for serverless 
# orchestration.
# ============================================================================

# Random ID generation for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# ============================================================================
# PROJECT CONFIGURATION
# ============================================================================

# Data source to get current project information
data "google_project" "project" {}

# Data source to get current client configuration
data "google_client_config" "default" {}

# ============================================================================
# API ENABLEMENT
# ============================================================================

# Enable required Google Cloud APIs for the solution
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "firestore.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# ============================================================================
# FIRESTORE DATABASE
# ============================================================================

# Create Firestore database for storing user preferences and templates
resource "google_firestore_database" "email_templates" {
  project     = var.project_id
  name        = "${var.database_name}-${random_id.suffix.hex}"
  location_id = var.firestore_location
  type        = "FIRESTORE_NATIVE"

  # Deletion protection to prevent accidental data loss
  deletion_policy = var.enable_deletion_protection ? "DELETE" : "ABANDON"

  depends_on = [
    google_project_service.required_apis["firestore.googleapis.com"]
  ]
}

# ============================================================================
# CLOUD STORAGE BUCKET FOR FUNCTION SOURCE
# ============================================================================

# Create Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-email-generator-source-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id

  # Enable versioning for source code management
  versioning {
    enabled = true
  }

  # Configure lifecycle management to clean up old versions
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Enable uniform bucket-level access for security
  uniform_bucket_level_access = true

  depends_on = [
    google_project_service.required_apis["cloudfunctions.googleapis.com"]
  ]
}

# ============================================================================
# CLOUD FUNCTION SOURCE CODE
# ============================================================================

# Create function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/email-template-function-${random_id.suffix.hex}.zip"
  
  source {
    content = templatefile("${path.module}/function/main.py", {
      database_id = google_firestore_database.email_templates.name
    })
    filename = "main.py"
  }

  source {
    content  = file("${path.module}/function/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "email-template-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# ============================================================================
# CLOUD FUNCTION FOR EMAIL TEMPLATE GENERATION
# ============================================================================

# Deploy Cloud Function for email template generation
resource "google_cloudfunctions2_function" "email_template_generator" {
  name        = "${var.function_name}-${random_id.suffix.hex}"
  location    = var.region
  project     = var.project_id
  description = "AI-powered email template generator using Vertex AI Gemini and Firestore"

  build_config {
    runtime     = "python311"
    entry_point = "generate_email_template"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = var.function_min_instances
    available_memory                 = var.function_memory
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 10
    available_cpu                    = "1"

    # Environment variables for the function
    environment_variables = {
      PROJECT_ID  = var.project_id
      DATABASE_ID = google_firestore_database.email_templates.name
      REGION      = var.region
    }

    # Configure ingress settings for security
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true

    # Service account for function execution
    service_account_email = google_service_account.function_sa.email
  }

  depends_on = [
    google_project_service.required_apis["cloudfunctions.googleapis.com"],
    google_project_service.required_apis["cloudbuild.googleapis.com"],
    google_storage_bucket_object.function_source,
    google_service_account.function_sa
  ]
}

# Function IAM policy to allow unauthenticated invocations (for demo purposes)
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  count = var.allow_unauthenticated_invocations ? 1 : 0

  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.email_template_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# ============================================================================
# SERVICE ACCOUNT AND IAM
# ============================================================================

# Service account for Cloud Function execution
resource "google_service_account" "function_sa" {
  account_id   = "email-template-fn-${random_id.suffix.hex}"
  display_name = "Email Template Generator Function Service Account"
  description  = "Service account for Cloud Function to access Firestore and Vertex AI"
  project      = var.project_id
}

# Grant Firestore access to the service account
resource "google_project_iam_member" "function_firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant Vertex AI access to the service account
resource "google_project_iam_member" "function_vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant logging permissions to the service account
resource "google_project_iam_member" "function_logs_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# ============================================================================
# FIRESTORE SAMPLE DATA INITIALIZATION (Optional)
# ============================================================================

# Cloud Function for initializing sample data in Firestore
resource "google_cloudfunctions2_function" "data_initializer" {
  count = var.initialize_sample_data ? 1 : 0

  name        = "firestore-data-initializer-${random_id.suffix.hex}"
  location    = var.region
  project     = var.project_id
  description = "Initialize sample data in Firestore for email template generation"

  build_config {
    runtime     = "python311"
    entry_point = "initialize_data"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.init_function_source[0].name
      }
    }
  }

  service_config {
    max_instance_count = 1
    min_instance_count = 0
    available_memory   = "256Mi"
    timeout_seconds    = 120

    environment_variables = {
      PROJECT_ID  = var.project_id
      DATABASE_ID = google_firestore_database.email_templates.name
    }

    service_account_email = google_service_account.function_sa.email
  }

  depends_on = [
    google_project_service.required_apis["cloudfunctions.googleapis.com"],
    google_storage_bucket_object.init_function_source
  ]
}

# Source code for data initialization function
data "archive_file" "init_function_source" {
  count = var.initialize_sample_data ? 1 : 0

  type        = "zip"
  output_path = "/tmp/init-function-${random_id.suffix.hex}.zip"

  source {
    content = templatefile("${path.module}/function/init_data.py", {
      database_id = google_firestore_database.email_templates.name
    })
    filename = "main.py"
  }

  source {
    content  = "google-cloud-firestore==2.16.0"
    filename = "requirements.txt"
  }
}

# Upload initialization function source to Cloud Storage
resource "google_storage_bucket_object" "init_function_source" {
  count = var.initialize_sample_data ? 1 : 0

  name   = "init-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.init_function_source[0].output_path

  depends_on = [data.archive_file.init_function_source]
}

# ============================================================================
# MONITORING AND ALERTING (Optional)
# ============================================================================

# Cloud Monitoring notification channel for alerts
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0

  display_name = "Email Template Generator Alerts"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.notification_email
  }
}

# Alert policy for function errors
resource "google_monitoring_alert_policy" "function_errors" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "Email Template Generator - High Error Rate"
  project      = var.project_id

  conditions {
    display_name = "Cloud Function error rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.email_template_generator.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.1

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []

  alert_strategy {
    auto_close = "86400s"
  }
}

# ============================================================================
# LABELS AND TAGS
# ============================================================================

# Apply labels to resources for organization and cost tracking
locals {
  common_labels = {
    environment = var.environment
    application = "email-template-generator"
    managed-by  = "terraform"
    recipe-id   = "f4a7b2c9"
  }
}

# Apply labels to major resources
resource "google_tags_tag_key" "environment" {
  count = var.enable_resource_tagging ? 1 : 0

  parent      = "projects/${var.project_id}"
  short_name  = "environment"
  description = "Environment tag for email template generator resources"
}

resource "google_tags_tag_value" "environment_value" {
  count = var.enable_resource_tagging ? 1 : 0

  parent      = google_tags_tag_key.environment[0].id
  short_name  = var.environment
  description = "Environment: ${var.environment}"
}