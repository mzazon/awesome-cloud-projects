# Main Terraform configuration for basic application logging with Cloud Functions
# This configuration creates a Cloud Function with structured logging capabilities

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Enable required Google Cloud APIs for the project
resource "google_project_service" "cloudfunctions" {
  count   = var.enable_functions ? 1 : 0
  project = var.project_id
  service = "cloudfunctions.googleapis.com"
  
  # Prevent disabling the API when the resource is destroyed
  disable_on_destroy = false
}

resource "google_project_service" "logging" {
  count   = var.enable_logging ? 1 : 0
  project = var.project_id
  service = "logging.googleapis.com"
  
  # Prevent disabling the API when the resource is destroyed
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  count   = var.enable_cloudbuild ? 1 : 0
  project = var.project_id
  service = "cloudbuild.googleapis.com"
  
  # Prevent disabling the API when the resource is destroyed
  disable_on_destroy = false
}

# Create Cloud Storage bucket for storing function source code
resource "google_storage_bucket" "function_source" {
  name                        = "${var.project_id}-function-source-${random_id.suffix.hex}"
  location                    = var.region
  uniform_bucket_level_access = true
  
  # Enable versioning for source code management
  versioning {
    enabled = true
  }
  
  # Lifecycle rule to clean up old versions
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = var.labels
  
  depends_on = [
    google_project_service.cloudfunctions
  ]
}

# Create the function source code as local files
resource "local_file" "main_py" {
  filename = "${path.module}/function_source/main.py"
  content  = <<-EOT
import logging
import functions_framework
from google.cloud.logging import Client


@functions_framework.http
def log_demo(request):
    """Cloud Function demonstrating structured logging capabilities."""
    
    # Initialize Cloud Logging client and setup integration
    logging_client = Client()
    logging_client.setup_logging()
    
    # Extract request information for logging context
    method = request.method
    path = request.path
    user_agent = request.headers.get('User-Agent', 'Unknown')
    
    # Create structured log entries with different severity levels
    logging.info("Function invocation started", extra={
        "json_fields": {
            "component": "log-demo-function",
            "request_method": method,
            "request_path": path,
            "event_type": "function_start"
        }
    })
    
    # Simulate application logic with informational logging
    logging.info("Processing user request", extra={
        "json_fields": {
            "component": "log-demo-function",
            "user_agent": user_agent,
            "processing_stage": "validation",
            "event_type": "request_processing"
        }
    })
    
    # Example warning log for demonstration
    if "test" in request.args.get('mode', '').lower():
        logging.warning("Running in test mode", extra={
            "json_fields": {
                "component": "log-demo-function",
                "mode": "test",
                "event_type": "configuration_warning"
            }
        })
    
    # Success completion log
    logging.info("Function execution completed successfully", extra={
        "json_fields": {
            "component": "log-demo-function",
            "status": "success",
            "event_type": "function_complete"
        }
    })
    
    return {
        "message": "Logging demonstration completed",
        "status": "success",
        "logs_generated": 4
    }
EOT
}

resource "local_file" "requirements_txt" {
  filename = "${path.module}/function_source/requirements.txt"
  content  = <<-EOT
functions-framework==3.8.0
google-cloud-logging==3.11.0
EOT
}

# Create archive of the function source code
data "archive_file" "function_source_zip" {
  type        = "zip"
  source_dir  = "${path.module}/function_source"
  output_path = "${path.module}/function_source.zip"
  
  depends_on = [
    local_file.main_py,
    local_file.requirements_txt
  ]
}

# Upload the function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source_zip" {
  name   = "function-source-${data.archive_file.function_source_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source_zip.output_path
  
  # Ensure the bucket exists before uploading
  depends_on = [
    google_storage_bucket.function_source,
    data.archive_file.function_source_zip
  ]
}

# Create the Cloud Function with structured logging
resource "google_cloudfunctions_function" "logging_demo" {
  name                  = "${var.function_name}-${random_id.suffix.hex}"
  description           = "Cloud Function demonstrating structured logging with Google Cloud Logging"
  region                = var.region
  runtime               = var.runtime
  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  entry_point          = "log_demo"
  labels               = var.labels
  
  # Configure environment variables
  environment_variables = var.environment_variables
  
  # Source code configuration
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source_zip.name
  
  # HTTP trigger configuration
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  depends_on = [
    google_project_service.cloudfunctions,
    google_project_service.logging,
    google_project_service.cloudbuild,
    google_storage_bucket_object.function_source_zip
  ]
}

# IAM binding to allow unauthenticated access (if enabled)
resource "google_cloudfunctions_function_iam_member" "invoker" {
  count          = var.allow_unauthenticated ? 1 : 0
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.logging_demo.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
  
  depends_on = [
    google_cloudfunctions_function.logging_demo
  ]
}

# Log sink for structured logs (optional - demonstrates log routing)
resource "google_logging_project_sink" "function_logs" {
  name        = "function-logs-sink-${random_id.suffix.hex}"
  description = "Log sink for Cloud Function structured logs"
  
  # Export logs to Cloud Logging (this is mainly for demonstration)
  destination = "logging.googleapis.com/projects/${var.project_id}/logs/function-structured-logs"
  
  # Filter for logs from our specific function
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${google_cloudfunctions_function.logging_demo.name}"
    jsonPayload.component="log-demo-function"
  EOT
  
  # Use a unique writer identity
  unique_writer_identity = true
  
  depends_on = [
    google_project_service.logging,
    google_cloudfunctions_function.logging_demo
  ]
}

# Log-based metric for monitoring function invocations
resource "google_logging_metric" "function_invocations" {
  name        = "function_invocations_${random_id.suffix.hex}"
  description = "Count of function invocations by event type"
  
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${google_cloudfunctions_function.logging_demo.name}"
    jsonPayload.event_type="function_start"
  EOT
  
  # Extract event type as a label
  label_extractors = {
    event_type = "EXTRACT(jsonPayload.event_type)"
  }
  
  # Count metric
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Function Invocations by Event Type"
    
    labels {
      key         = "event_type"
      value_type  = "STRING"
      description = "Type of event logged by the function"
    }
  }
  
  depends_on = [
    google_project_service.logging,
    google_cloudfunctions_function.logging_demo
  ]
}