# Main Terraform configuration for AI-Powered App Development with Firebase Studio and Gemini
# This file creates the complete infrastructure for the Firebase Studio application

# Generate random suffix for unique resource naming
resource "random_hex" "suffix" {
  length = 3
}

# Local values for consistent resource naming and configuration
locals {
  resource_suffix = random_hex.suffix.hex
  app_id         = "${var.app_name}-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.resource_labels, {
    environment = var.environment
    app-name    = var.app_name
    created-by  = "terraform"
  })
  
  # Required APIs for Firebase Studio and Gemini integration
  required_apis = [
    "firebase.googleapis.com",
    "firestore.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "aiplatform.googleapis.com",
    "artifactregistry.googleapis.com",
    "developerconnect.googleapis.com",
    "firebasehosting.googleapis.com",
    "identitytoolkit.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

# Enable required Google Cloud APIs for Firebase Studio
resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying to avoid dependency issues
  disable_dependent_services = false
  disable_on_destroy         = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for APIs to be fully enabled before proceeding
resource "time_sleep" "api_enablement" {
  depends_on = [google_project_service.apis]
  
  create_duration = "30s"
}

# Create Firebase project resource
resource "google_firebase_project" "default" {
  provider = google-beta
  project  = var.project_id
  
  depends_on = [
    time_sleep.api_enablement
  ]
  
  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

# Create Firebase web app for Studio integration
resource "google_firebase_web_app" "studio_app" {
  provider = google-beta
  project  = var.project_id
  
  display_name   = "${var.app_name} Web App"
  deletion_policy = var.deletion_protection ? "ABANDON" : "DELETE"
  
  depends_on = [google_firebase_project.default]
}

# Configure Firestore database for real-time data
resource "google_firestore_database" "database" {
  count    = var.enable_firestore ? 1 : 0
  provider = google-beta
  project  = var.project_id
  
  name                        = "(default)"
  location_id                 = var.firestore_location
  type                        = "FIRESTORE_NATIVE"
  concurrency_mode           = "OPTIMISTIC"
  app_engine_integration_mode = "DISABLED"
  
  # Enable point-in-time recovery for production environments
  point_in_time_recovery_enablement = var.environment == "prod" ? "POINT_IN_TIME_RECOVERY_ENABLED" : "POINT_IN_TIME_RECOVERY_DISABLED"
  
  # Deletion protection for production
  deletion_policy = var.deletion_protection ? "ABANDON" : "DELETE"
  
  depends_on = [
    google_firebase_project.default,
    time_sleep.api_enablement
  ]
  
  timeouts {
    create = "15m"
    update = "10m"
    delete = "15m"
  }
}

# Create composite indexes for optimized AI-enhanced queries
resource "google_firestore_index" "tasks_by_user_priority" {
  count    = var.enable_firestore ? 1 : 0
  provider = google-beta
  project  = var.project_id
  database = google_firestore_database.database[0].name
  
  collection = "tasks"
  
  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "priority"
    order      = "DESCENDING"
  }
  
  fields {
    field_path = "createdAt"
    order      = "ASCENDING"
  }
  
  depends_on = [google_firestore_database.database]
}

resource "google_firestore_index" "ai_suggestions" {
  count    = var.enable_firestore ? 1 : 0
  provider = google-beta
  project  = var.project_id
  database = google_firestore_database.database[0].name
  
  collection = "tasks"
  
  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "aiGenerated"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "suggestionScore"
    order      = "DESCENDING"
  }
  
  depends_on = [google_firestore_database.database]
}

resource "google_firestore_index" "task_status_due_date" {
  count    = var.enable_firestore ? 1 : 0
  provider = google-beta
  project  = var.project_id
  database = google_firestore_database.database[0].name
  
  collection = "tasks"
  
  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "status"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "dueDate"
    order      = "ASCENDING"
  }
  
  depends_on = [google_firestore_database.database]
}

# Create Secret Manager secret for Gemini API key
resource "google_secret_manager_secret" "gemini_api_key" {
  count     = var.enable_secret_manager ? 1 : 0
  provider  = google-beta
  project   = var.project_id
  secret_id = "gemini-api-key"
  
  labels = local.common_labels
  
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
  
  depends_on = [time_sleep.api_enablement]
}

# Store Gemini API key value (if provided)
resource "google_secret_manager_secret_version" "gemini_api_key_version" {
  count   = var.enable_secret_manager && var.gemini_api_key != "" ? 1 : 0
  provider = google-beta
  
  secret      = google_secret_manager_secret.gemini_api_key[0].id
  secret_data = var.gemini_api_key
  
  depends_on = [google_secret_manager_secret.gemini_api_key]
}

# Configure Firebase Authentication
resource "google_identity_platform_config" "auth_config" {
  provider = google-beta
  project  = var.project_id
  
  autodelete_anonymous_users = true
  
  # Configure sign-in methods
  sign_in {
    allow_duplicate_emails = false
    
    dynamic "anonymous" {
      for_each = contains(var.authentication_providers, "anonymous") ? [1] : []
      content {
        enabled = true
      }
    }
    
    email {
      enabled           = contains(var.authentication_providers, "password")
      password_required = contains(var.authentication_providers, "password")
    }
  }
  
  # Configure blocking functions for custom logic
  blocking_functions {
    triggers {
      event_type = "beforeCreate"
      function_uri = "https://${var.region}-${var.project_id}.cloudfunctions.net/beforeCreate"
    }
  }
  
  depends_on = [
    google_firebase_project.default,
    time_sleep.api_enablement
  ]
}

# Configure OAuth providers for social authentication
resource "google_identity_platform_default_supported_idp_config" "google_oauth" {
  count    = contains(var.authentication_providers, "google.com") ? 1 : 0
  provider = google-beta
  project  = var.project_id
  
  idp_id    = "google.com"
  client_id = "your-google-oauth-client-id"  # Replace with actual client ID
  enabled   = true
  
  depends_on = [google_identity_platform_config.auth_config]
}

resource "google_identity_platform_default_supported_idp_config" "github_oauth" {
  count    = contains(var.authentication_providers, "github.com") ? 1 : 0
  provider = google-beta
  project  = var.project_id
  
  idp_id        = "github.com"
  client_id     = "your-github-oauth-client-id"  # Replace with actual client ID
  client_secret = "your-github-oauth-client-secret"  # Replace with actual client secret
  enabled       = true
  
  depends_on = [google_identity_platform_config.auth_config]
}

# Create Cloud Storage bucket for Firebase Storage
resource "google_storage_bucket" "firebase_storage" {
  provider = google-beta
  project  = var.project_id
  
  name     = "${var.project_id}.appspot.com"
  location = var.region
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = var.backup_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Enable versioning for file recovery
  versioning {
    enabled = true
  }
  
  # Configure CORS for web app access
  cors {
    origin          = var.cors_allowed_origins
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  labels = local.common_labels
  
  depends_on = [time_sleep.api_enablement]
}

# Create Artifact Registry repository for container images
resource "google_artifact_registry_repository" "container_registry" {
  count    = var.enable_app_hosting ? 1 : 0
  provider = google-beta
  project  = var.project_id
  
  location      = var.region
  repository_id = "${var.app_name}-containers"
  description   = "Container registry for ${var.app_name} application"
  format        = "DOCKER"
  
  labels = local.common_labels
  
  depends_on = [time_sleep.api_enablement]
}

# Create service account for Cloud Build
resource "google_service_account" "cloud_build_sa" {
  count    = var.enable_cloud_build ? 1 : 0
  provider = google-beta
  project  = var.project_id
  
  account_id   = "${var.app_name}-build-sa"
  display_name = "Cloud Build Service Account for ${var.app_name}"
  description  = "Service account for Cloud Build CI/CD pipelines"
}

# Grant necessary permissions to Cloud Build service account
resource "google_project_iam_member" "cloud_build_permissions" {
  for_each = var.enable_cloud_build ? toset([
    "roles/cloudbuild.builds.builder",
    "roles/artifactregistry.writer",
    "roles/run.admin",
    "roles/secretmanager.secretAccessor",
    "roles/firebase.admin"
  ]) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_build_sa[0].email}"
  
  depends_on = [google_service_account.cloud_build_sa]
}

# Create Cloud Run service for backend API
resource "google_cloud_run_v2_service" "api_service" {
  provider = google-beta
  project  = var.project_id
  
  name     = "${var.app_name}-api"
  location = var.region
  
  template {
    containers {
      # Placeholder image - replace with actual application image
      image = "gcr.io/cloudrun/hello"
      
      # Configure resource limits
      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
        cpu_idle = true
      }
      
      # Environment variables for Firebase integration
      env {
        name  = "FIREBASE_PROJECT_ID"
        value = var.project_id
      }
      
      env {
        name = "GEMINI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = var.enable_secret_manager ? google_secret_manager_secret.gemini_api_key[0].secret_id : "gemini-api-key"
            version = "latest"
          }
        }
      }
      
      # Configure health checks
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds       = 5
        period_seconds        = 3
        failure_threshold     = 3
      }
      
      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds       = 5
        period_seconds        = 30
        failure_threshold     = 3
      }
    }
    
    # Configure scaling
    scaling {
      min_instance_count = 0
      max_instance_count = 100
    }
    
    # Configure service account
    service_account = var.enable_cloud_build ? google_service_account.cloud_build_sa[0].email : null
    
    labels = local.common_labels
  }
  
  # Configure traffic allocation
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  depends_on = [
    time_sleep.api_enablement,
    google_service_account.cloud_build_sa
  ]
}

# Allow unauthenticated access to Cloud Run service (adjust as needed)
resource "google_cloud_run_service_iam_member" "public_access" {
  provider = google-beta
  project  = var.project_id
  
  location = google_cloud_run_v2_service.api_service.location
  service  = google_cloud_run_v2_service.api_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Create Cloud Monitoring notification channel
resource "google_monitoring_notification_channel" "email_alerts" {
  count    = var.enable_monitoring && length(var.notification_emails) > 0 ? length(var.notification_emails) : 0
  provider = google-beta
  project  = var.project_id
  
  display_name = "Email Alert ${count.index + 1}"
  type         = "email"
  
  labels = {
    email_address = var.notification_emails[count.index]
  }
  
  depends_on = [time_sleep.api_enablement]
}

# Create uptime check for the API service
resource "google_monitoring_uptime_check_config" "api_uptime_check" {
  count    = var.enable_monitoring ? 1 : 0
  provider = google-beta
  project  = var.project_id
  
  display_name = "${var.app_name} API Uptime Check"
  timeout      = "10s"
  period       = "60s"
  
  http_check {
    path           = "/health"
    port           = 443
    use_ssl        = true
    validate_ssl   = true
    request_method = "GET"
  }
  
  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = google_cloud_run_v2_service.api_service.uri
    }
  }
  
  content_matchers {
    content = "healthy"
    matcher = "CONTAINS_STRING"
  }
  
  depends_on = [
    google_cloud_run_v2_service.api_service,
    time_sleep.api_enablement
  ]
}

# Create alerting policy for API downtime
resource "google_monitoring_alert_policy" "api_downtime_alert" {
  count    = var.enable_monitoring && length(var.notification_emails) > 0 ? 1 : 0
  provider = google-beta
  project  = var.project_id
  
  display_name = "${var.app_name} API Downtime Alert"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "API Uptime Check Failed"
    
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\""
      duration        = "300s"
      comparison      = "COMPARISON_EQUAL"
      threshold_value = 0
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_FRACTION_TRUE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.label.project_id"]
      }
    }
  }
  
  notification_channels = google_monitoring_notification_channel.email_alerts[*].id
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [
    google_monitoring_uptime_check_config.api_uptime_check,
    google_monitoring_notification_channel.email_alerts
  ]
}

# Create budget alert for cost monitoring
resource "google_billing_budget" "project_budget" {
  count           = var.enable_monitoring && var.budget_amount > 0 ? 1 : 0
  provider        = google-beta
  billing_account = data.google_project.project.billing_account
  display_name    = "${var.app_name} Monthly Budget"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(floor(var.budget_amount))
      nanos         = (var.budget_amount - floor(var.budget_amount)) * 1000000000
    }
  }
  
  threshold_rules {
    threshold_percent = 0.8
    spend_basis      = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 1.0
    spend_basis      = "CURRENT_SPEND"
  }
  
  all_updates_rule {
    monitoring_notification_channels = length(var.notification_emails) > 0 ? [google_monitoring_notification_channel.email_alerts[0].id] : []
    disable_default_iam_recipients   = false
  }
  
  depends_on = [google_monitoring_notification_channel.email_alerts]
}

# Data source to get project information
data "google_project" "project" {
  project_id = var.project_id
}