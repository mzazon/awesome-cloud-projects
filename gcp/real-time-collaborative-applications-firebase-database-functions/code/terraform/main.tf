# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent naming
locals {
  project_suffix    = random_id.suffix.hex
  bucket_name      = "${var.resource_prefix}-functions-${local.project_suffix}"
  hosting_site_id  = var.hosting_site_id != null ? var.hosting_site_id : var.project_id
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "firebase.googleapis.com",
    "firestore.googleapis.com",
    "firebasedatabase.googleapis.com",
    "firebasehosting.googleapis.com",
    "identitytoolkit.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent accidental deletion of APIs
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Firebase project
resource "google_firebase_project" "default" {
  provider = google-beta
  project  = var.project_id

  depends_on = [
    google_project_service.required_apis["firebase.googleapis.com"]
  ]
}

# Configure Firebase project location
resource "google_firebase_project_location" "default" {
  provider    = google-beta
  project     = var.project_id
  location_id = var.region

  depends_on = [google_firebase_project.default]
}

# Create Firebase Realtime Database
resource "google_firebase_database_instance" "default" {
  provider    = google-beta
  project     = var.project_id
  region      = var.database_region
  instance_id = var.database_instance_id
  type        = "DEFAULT_DATABASE"

  depends_on = [
    google_firebase_project.default,
    google_project_service.required_apis["firebasedatabase.googleapis.com"]
  ]
}

# Create GCS bucket for Cloud Functions source code
resource "google_storage_bucket" "functions_source" {
  name     = var.functions_source_bucket != null ? var.functions_source_bucket : local.bucket_name
  location = var.region
  project  = var.project_id

  # Versioning for function deployments
  versioning {
    enabled = true
  }

  # Lifecycle management for old versions
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Security settings
  uniform_bucket_level_access = true
  
  # Force destruction for cleanup
  force_destroy = true

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis["storage.googleapis.com"]
  ]
}

# Create ZIP archive for Cloud Functions source code
data "archive_file" "functions_source" {
  type        = "zip"
  output_path = "${path.module}/functions-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/index.js", {
      project_id = var.project_id
    })
    filename = "index.js"
  }
  
  source {
    content = file("${path.module}/function_code/package.json")
    filename = "package.json"
  }
}

# Upload function source to GCS
resource "google_storage_bucket_object" "functions_source" {
  name   = "functions-source-${data.archive_file.functions_source.output_md5}.zip"
  bucket = google_storage_bucket.functions_source.name
  source = data.archive_file.functions_source.output_path

  depends_on = [data.archive_file.functions_source]
}

# Cloud Function: Create Document
resource "google_cloudfunctions2_function" "create_document" {
  name     = "${var.resource_prefix}-create-document"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = var.nodejs_runtime
    entry_point = "createDocument"
    
    source {
      storage_source {
        bucket = google_storage_bucket.functions_source.name
        object = google_storage_bucket_object.functions_source.name
      }
    }
  }

  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = "${var.function_memory}Mi"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"

    environment_variables = {
      PROJECT_ID = var.project_id
    }

    ingress_settings = "ALLOW_ALL"
    
    service_account_email = google_service_account.functions_sa.email
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis["cloudfunctions.googleapis.com"],
    google_storage_bucket_object.functions_source
  ]
}

# Cloud Function: Add Collaborator
resource "google_cloudfunctions2_function" "add_collaborator" {
  name     = "${var.resource_prefix}-add-collaborator"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = var.nodejs_runtime
    entry_point = "addCollaborator"
    
    source {
      storage_source {
        bucket = google_storage_bucket.functions_source.name
        object = google_storage_bucket_object.functions_source.name
      }
    }
  }

  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = "${var.function_memory}Mi"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"

    environment_variables = {
      PROJECT_ID = var.project_id
    }

    ingress_settings = "ALLOW_ALL"
    
    service_account_email = google_service_account.functions_sa.email
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis["cloudfunctions.googleapis.com"],
    google_storage_bucket_object.functions_source
  ]
}

# Cloud Function: Get User Documents
resource "google_cloudfunctions2_function" "get_user_documents" {
  name     = "${var.resource_prefix}-get-user-documents"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = var.nodejs_runtime
    entry_point = "getUserDocuments"
    
    source {
      storage_source {
        bucket = google_storage_bucket.functions_source.name
        object = google_storage_bucket_object.functions_source.name
      }
    }
  }

  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = "${var.function_memory}Mi"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"

    environment_variables = {
      PROJECT_ID = var.project_id
    }

    ingress_settings = "ALLOW_ALL"
    
    service_account_email = google_service_account.functions_sa.email
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis["cloudfunctions.googleapis.com"],
    google_storage_bucket_object.functions_source
  ]
}

# Service Account for Cloud Functions
resource "google_service_account" "functions_sa" {
  account_id   = "${var.resource_prefix}-functions-sa"
  display_name = "Service Account for Collaborative App Functions"
  project      = var.project_id
}

# IAM binding for Functions service account
resource "google_project_iam_member" "functions_sa_roles" {
  for_each = toset([
    "roles/firebasedatabase.admin",
    "roles/firebase.admin",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.functions_sa.email}"
}

# Firebase Web App
resource "google_firebase_web_app" "default" {
  provider     = google-beta
  project      = var.project_id
  display_name = var.firebase_project_display_name
  
  depends_on = [google_firebase_project.default]
}

# Firebase Web App Config
resource "google_firebase_web_app_config" "default" {
  provider   = google-beta
  project    = var.project_id
  web_app_id = google_firebase_web_app.default.app_id

  depends_on = [google_firebase_web_app.default]
}

# Firebase Hosting Site
resource "google_firebase_hosting_site" "default" {
  provider = google-beta
  project  = var.project_id
  site_id  = local.hosting_site_id

  depends_on = [
    google_firebase_project.default,
    google_project_service.required_apis["firebasehosting.googleapis.com"]
  ]
}

# Enable Firebase Authentication
resource "google_identity_platform_config" "auth" {
  provider = google-beta
  project  = var.project_id

  # Enable email/password authentication
  sign_in {
    allow_duplicate_emails = false

    email {
      enabled           = contains(var.auth_providers, "email")
      password_required = true
    }
  }

  depends_on = [
    google_firebase_project.default,
    google_project_service.required_apis["identitytoolkit.googleapis.com"]
  ]
}

# Configure OAuth providers for Firebase Auth
resource "google_identity_platform_default_supported_idp_config" "google_sign_in" {
  count    = contains(var.auth_providers, "google.com") ? 1 : 0
  provider = google-beta
  project  = var.project_id

  idp_id        = "google.com"
  client_id     = "your-google-oauth-client-id"  # Replace with actual client ID
  client_secret = "your-google-oauth-client-secret"  # Replace with actual client secret
  enabled       = true

  depends_on = [google_identity_platform_config.auth]
}

# Monitoring: Log-based metrics for collaborative features
resource "google_logging_metric" "document_modifications" {
  name   = "${var.resource_prefix}-document-modifications"
  filter = "resource.type=\"cloud_function\" AND textPayload:\"Document modified\""

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Document Modifications"
  }

  project = var.project_id

  depends_on = [
    google_project_service.required_apis["logging.googleapis.com"]
  ]
}

# Monitoring: Alerting policy for high function error rates
resource "google_monitoring_alert_policy" "function_error_rate" {
  display_name = "${var.resource_prefix} Function Error Rate Alert"
  project      = var.project_id

  conditions {
    display_name = "Function error rate too high"

    condition_threshold {
      filter          = "resource.type=\"cloud_function\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1  # 10% error rate

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []  # Add notification channels as needed

  alert_strategy {
    auto_close = "1800s"  # 30 minutes
  }

  depends_on = [
    google_project_service.required_apis["monitoring.googleapis.com"]
  ]
}

# IAM binding for invoking Cloud Functions (for authenticated users)
resource "google_cloudfunctions2_function_iam_member" "create_document_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.create_document.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allAuthenticatedUsers"
}

resource "google_cloudfunctions2_function_iam_member" "add_collaborator_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.add_collaborator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allAuthenticatedUsers"
}

resource "google_cloudfunctions2_function_iam_member" "get_user_documents_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.get_user_documents.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allAuthenticatedUsers"
}