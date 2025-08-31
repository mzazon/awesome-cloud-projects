# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for resource naming and configuration
locals {
  # Generate unique names for resources
  function_name_unique = var.function_name
  bucket_name = var.source_bucket_name != "" ? var.source_bucket_name : "${var.project_id}-weather-function-source-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    function = var.function_name
    created  = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Function source code files
  function_source_files = {
    "main.py" = templatefile("${path.module}/function-source/main.py", {
      weather_api_key = var.weather_api_key
      log_level      = var.log_level
    })
    "requirements.txt" = file("${path.module}/function-source/requirements.txt")
  }
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
}

# Create service account for the Cloud Function (if enabled)
resource "google_service_account" "weather_function_sa" {
  count = var.create_service_account ? 1 : 0
  
  account_id   = var.service_account_name
  display_name = "Weather API Function Service Account"
  description  = "Service account for the weather information API Cloud Function"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM role bindings for the service account
resource "google_project_iam_member" "function_sa_roles" {
  for_each = var.create_service_account ? toset([
    "roles/cloudsql.client",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent"
  ]) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.weather_function_sa[0].email}"
  
  depends_on = [google_service_account.weather_function_sa]
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Lifecycle management to clean up old versions
  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }
  
  # Versioning for source code tracking
  versioning {
    enabled = true
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create function source archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/weather-function-source.zip"
  
  dynamic "source" {
    for_each = local.function_source_files
    content {
      content  = source.value
      filename = source.key
    }
  }
  
  # Include a basic main.py if source files don't exist
  source {
    content = templatefile("${path.module}/templates/main.py.tpl", {
      weather_api_key = var.weather_api_key
      log_level      = var.log_level
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/templates/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = var.source_archive_object
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  # Ensure we upload a new version when source changes
  detect_md5hash = data.archive_file.function_source.output_md5
}

# Deploy the Cloud Function
resource "google_cloudfunctions_function" "weather_api" {
  name        = local.function_name_unique
  description = "Weather Information API using OpenWeatherMap"
  project     = var.project_id
  region      = var.region
  runtime     = var.function_runtime
  
  # Function source configuration
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  # Entry point for the function
  entry_point = "get_weather"
  
  # HTTP trigger configuration
  trigger {
    https_trigger {
      url = null # Will be generated
    }
  }
  
  # Resource configuration
  available_memory_mb = var.function_memory
  timeout             = var.function_timeout
  max_instances       = var.function_max_instances
  
  # Environment variables
  environment_variables = {
    WEATHER_API_KEY = var.weather_api_key
    LOG_LEVEL      = var.log_level
    CORS_ORIGINS   = join(",", var.cors_origins)
  }
  
  # Service account configuration
  service_account_email = var.create_service_account ? google_service_account.weather_function_sa[0].email : null
  
  # Networking configuration
  vpc_connector                 = var.vpc_connector
  ingress_settings             = var.ingress_settings
  
  # Labels for the function
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# IAM policy to allow public access (if enabled)
resource "google_cloudfunctions_function_iam_member" "public_access" {
  count = var.enable_public_access ? 1 : 0
  
  project        = var.project_id
  region         = google_cloudfunctions_function.weather_api.region
  cloud_function = google_cloudfunctions_function.weather_api.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create Cloud Logging sink for function logs (if logging is enabled)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_logging ? 1 : 0
  
  name        = "${var.function_name}-logs-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.function_source.name}/logs"
  filter      = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions_function.weather_api.name}\""
  
  # Use a unique writer identity
  unique_writer_identity = true
}

# Grant the logging sink permission to write to the bucket
resource "google_storage_bucket_iam_member" "logs_sink_writer" {
  count = var.enable_logging ? 1 : 0
  
  bucket = google_storage_bucket.function_source.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity
}

# Create monitoring uptime check for the function
resource "google_monitoring_uptime_check_config" "weather_api_uptime" {
  display_name = "${var.function_name} Uptime Check"
  timeout      = "10s"
  period       = "300s"
  
  http_check {
    path           = "/?city=London"
    port           = 443
    use_ssl        = true
    validate_ssl   = true
    request_method = "GET"
    
    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
  }
  
  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = split("/", google_cloudfunctions_function.weather_api.https_trigger_url)[2]
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.weather_api
  ]
}

# Create alerting policy for function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  display_name = "${var.function_name} Error Rate Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Function Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.label.function_name=\"${google_cloudfunctions_function.weather_api.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1 # 10% error rate
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields = [
          "resource.label.function_name"
        ]
      }
      
      trigger {
        count = 1
      }
    }
  }
  
  notification_channels = []
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.weather_api
  ]
}