# =============================================================================
# Weather API with Cloud Functions - Terraform Configuration
# =============================================================================
# This Terraform configuration deploys a serverless weather API using Google
# Cloud Functions (2nd generation) with proper IAM, service enablement, and
# source code deployment.
# =============================================================================

# Data source to get the current project information
data "google_project" "current" {}

# Data source to get the current client configuration
data "google_client_config" "current" {}

# =============================================================================
# PROJECT SERVICES
# =============================================================================
# Enable required Google Cloud APIs for the weather API functionality

resource "google_project_service" "cloud_functions" {
  project = var.project_id
  service = "cloudfunctions.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = true
}

resource "google_project_service" "cloud_build" {
  project = var.project_id
  service = "cloudbuild.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = true
}

resource "google_project_service" "artifact_registry" {
  project = var.project_id
  service = "artifactregistry.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = true
}

resource "google_project_service" "cloud_logging" {
  project = var.project_id
  service = "logging.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = true
}

resource "google_project_service" "cloud_run" {
  project = var.project_id
  service = "run.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = true
}

# =============================================================================
# CLOUD STORAGE BUCKET FOR FUNCTION SOURCE CODE
# =============================================================================
# Create a bucket to store the Cloud Function source code
# This bucket will contain the zipped source code for deployment

resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-weather-api-source"
  location = var.region

  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true

  # Configure lifecycle to clean up old versions
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Add labels for resource management
  labels = {
    environment = var.environment
    purpose     = "cloud-function-source"
    service     = "weather-api"
  }

  depends_on = [
    google_project_service.cloud_functions
  ]
}

# =============================================================================
# FUNCTION SOURCE CODE ARCHIVE
# =============================================================================
# Create a zip archive of the function source code
# This includes main.py and requirements.txt

data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/weather-api-source.zip"
  
  source {
    content = templatefile("${path.module}/function_source/main.py", {
      # Template variables if needed in the future
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload the source code archive to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "weather-api-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  depends_on = [
    google_storage_bucket.function_source,
    data.archive_file.function_source
  ]
}

# =============================================================================
# SERVICE ACCOUNT FOR CLOUD FUNCTION
# =============================================================================
# Create a dedicated service account for the Cloud Function
# Following the principle of least privilege

resource "google_service_account" "weather_api_function" {
  account_id   = "${var.function_name}-sa"
  display_name = "Weather API Cloud Function Service Account"
  description  = "Service account for the weather API Cloud Function with minimal required permissions"
  project      = var.project_id

  depends_on = [
    google_project_service.cloud_functions
  ]
}

# Grant minimal required IAM roles to the service account
resource "google_project_iam_member" "function_invoker" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.weather_api_function.email}"

  depends_on = [
    google_service_account.weather_api_function
  ]
}

# =============================================================================
# CLOUD FUNCTION (2ND GENERATION)
# =============================================================================
# Deploy the weather API as a Cloud Function (2nd generation)
# with HTTP trigger and optimized configuration

resource "google_cloudfunctions2_function" "weather_api" {
  name        = var.function_name
  location    = var.region
  description = "Serverless Weather API that returns mock weather data for cities"
  project     = var.project_id

  build_config {
    runtime     = var.function_runtime
    entry_point = var.function_entry_point
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = var.max_instance_count
    min_instance_count    = var.min_instance_count
    available_memory      = var.memory_mb
    timeout_seconds       = var.timeout_seconds
    service_account_email = google_service_account.weather_api_function.email

    # Environment variables for the function
    environment_variables = var.environment_variables

    # Configure ingress settings for security
    ingress_settings = "ALLOW_ALL"
    
    # Enable all traffic for HTTP functions
    all_traffic_on_latest_revision = true
  }

  # Add labels for resource management and cost tracking
  labels = {
    environment = var.environment
    service     = "weather-api"
    runtime     = replace(var.function_runtime, ".", "-")
    version     = "v1"
  }

  depends_on = [
    google_project_service.cloud_functions,
    google_project_service.cloud_build,
    google_project_service.cloud_run,
    google_storage_bucket_object.function_source,
    google_service_account.weather_api_function
  ]
}

# =============================================================================
# CLOUD FUNCTION IAM POLICY
# =============================================================================
# Configure IAM policy to allow unauthenticated access to the function
# This enables public HTTP access as shown in the recipe

resource "google_cloudfunctions2_function_iam_member" "public_access" {
  project        = var.project_id
  location       = google_cloudfunctions2_function.weather_api.location
  cloud_function = google_cloudfunctions2_function.weather_api.name
  
  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"

  depends_on = [
    google_cloudfunctions2_function.weather_api
  ]
}

# =============================================================================
# MONITORING AND LOGGING (Optional)
# =============================================================================
# Configure log-based metrics for monitoring function performance

resource "google_logging_metric" "function_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "${var.function_name}-errors"
  filter = <<-EOF
    resource.type="cloud_function"
    resource.labels.function_name="${var.function_name}"
    severity>=ERROR
  EOF

  label_extractors = {
    function_name = "EXTRACT(resource.labels.function_name)"
  }

  metric_descriptor {
    metric_kind = "COUNTER"
    value_type  = "INT64"
    display_name = "Weather API Function Errors"
  }

  depends_on = [
    google_cloudfunctions2_function.weather_api,
    google_project_service.cloud_logging
  ]
}

# Log-based metric for function invocations
resource "google_logging_metric" "function_invocations" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "${var.function_name}-invocations"
  filter = <<-EOF
    resource.type="cloud_function"
    resource.labels.function_name="${var.function_name}"
    textPayload:"Function execution started"
  EOF

  metric_descriptor {
    metric_kind = "COUNTER"
    value_type  = "INT64"
    display_name = "Weather API Function Invocations"
  }

  depends_on = [
    google_cloudfunctions2_function.weather_api,
    google_project_service.cloud_logging
  ]
}