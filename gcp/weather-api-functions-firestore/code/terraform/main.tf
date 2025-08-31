# Weather API with Cloud Functions and Firestore
# This configuration deploys a serverless weather API using GCP services

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent naming and configuration
locals {
  resource_suffix = lower(random_id.suffix.hex)
  function_name_full = "${var.function_name}-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.function_labels, {
    environment = var.environment
    project     = var.project_id
    created-by  = "terraform"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "firestore.googleapis.com",
    "run.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of APIs
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Firestore database in Native mode
resource "google_firestore_database" "weather_cache" {
  provider = google-beta
  project  = var.project_id
  name     = "(default)"
  
  # Native mode provides better performance and features
  type                        = "FIRESTORE_NATIVE"
  location_id                = var.firestore_location
  concurrency_mode           = "OPTIMISTIC"
  app_engine_integration_mode = "DISABLED"
  
  # Ensure point-in-time recovery is enabled for production
  point_in_time_recovery_enablement = var.environment == "prod" ? "POINT_IN_TIME_RECOVERY_ENABLED" : "POINT_IN_TIME_RECOVERY_DISABLED"
  
  depends_on = [google_project_service.apis]
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "weather-api-sa-${local.resource_suffix}"
  display_name = "Weather API Function Service Account"
  description  = "Service account for weather API Cloud Function to access Firestore"
  project      = var.project_id
}

# Grant Firestore user permissions to the service account
resource "google_project_iam_member" "firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create a Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-function-source-${local.resource_suffix}"
  location = var.region
  project  = var.project_id
  
  # Enable versioning for source code management
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
  
  # Security settings
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create the function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    filename = "main.py"
    content = templatefile("${path.module}/function_source/main.py.tpl", {
      cache_ttl_minutes = var.cache_ttl_minutes
      enable_cors      = var.enable_cors
      allowed_origins  = jsonencode(var.allowed_origins)
    })
  }
  
  source {
    filename = "requirements.txt"
    content  = file("${path.module}/function_source/requirements.txt")
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  # Ensure we re-upload when source changes
  content_type = "application/zip"
}

# Deploy the Cloud Function (2nd generation)
resource "google_cloudfunctions2_function" "weather_api" {
  project  = var.project_id
  location = var.region
  name     = local.function_name_full
  
  description = "Serverless weather API with Firestore caching"
  labels      = local.common_labels
  
  build_config {
    runtime     = "python311"
    entry_point = "weather_api"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
    
    environment_variables = {
      BUILD_CONFIG_TEST = "build_test"
    }
  }
  
  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = "${var.function_memory}M"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 80
    available_cpu                    = var.function_memory >= 1024 ? "1" : "0.583"
    
    environment_variables = {
      WEATHER_API_KEY   = var.weather_api_key
      CACHE_TTL_MINUTES = tostring(var.cache_ttl_minutes)
      ENABLE_CORS       = tostring(var.enable_cors)
      ALLOWED_ORIGINS   = jsonencode(var.allowed_origins)
      ENVIRONMENT       = var.environment
    }
    
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_sa.email
  }
  
  depends_on = [
    google_project_service.apis,
    google_firestore_database.weather_cache,
    google_project_iam_member.firestore_user
  ]
}

# Create IAM policy to allow unauthenticated access (if enabled)
resource "google_cloudfunctions2_function_iam_member" "public_access" {
  count = var.enable_public_access ? 1 : 0
  
  project        = var.project_id
  location       = google_cloudfunctions2_function.weather_api.location
  cloud_function = google_cloudfunctions2_function.weather_api.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create Firestore indexes for optimal query performance
resource "google_firestore_index" "weather_cache_city_timestamp" {
  provider = google-beta
  project  = var.project_id
  database = google_firestore_database.weather_cache.name
  
  collection = "weather_cache"
  
  fields {
    field_path = "city"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "timestamp"
    order      = "DESCENDING"
  }
  
  depends_on = [google_firestore_database.weather_cache]
}

# Optional: Create monitoring alert policy for function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  count        = var.environment == "prod" ? 1 : 0
  project      = var.project_id
  display_name = "Weather API Function Error Rate"
  
  documentation {
    content = "Alert when weather API function error rate exceeds 5%"
  }
  
  conditions {
    display_name = "Function error rate condition"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name_full}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.05
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        
        group_by_fields = [
          "resource.labels.function_name"
        ]
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_cloudfunctions2_function.weather_api]
}