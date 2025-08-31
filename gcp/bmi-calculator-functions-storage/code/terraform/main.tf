# Main Terraform configuration for BMI Calculator API
# This file contains the core infrastructure resources for the serverless BMI calculator

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Construct unique names for resources
  bucket_name = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  
  # Common labels to apply to all resources
  common_labels = merge(var.labels, {
    project     = "bmi-calculator"
    terraform   = "true"
    created_by  = "terraform"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]) : toset([])

  project = var.project_id
  service = each.value

  # Prevent accidental deletion of APIs
  disable_on_destroy = false

  # Wait for each API to be fully enabled
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Cloud Storage bucket for storing BMI calculation history
resource "google_storage_bucket" "bmi_history" {
  name     = local.bucket_name
  location = var.region
  
  # Storage configuration
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  force_destroy              = true

  # Versioning for data protection
  versioning {
    enabled = true
  }

  # CORS configuration for web browser access
  cors {
    origin          = var.cors_origins
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lifecycle_rule.value.action.storage_class
      }
      condition {
        age                   = lifecycle_rule.value.condition.age
        created_before        = lifecycle_rule.value.condition.created_before
        with_state           = lifecycle_rule.value.condition.with_state
        matches_storage_class = lifecycle_rule.value.condition.matches_storage_class
      }
    }
  }

  # Apply labels for resource management
  labels = local.common_labels

  # Ensure APIs are enabled before creating the bucket
  depends_on = [google_project_service.required_apis]
}

# Create a dedicated service account for the Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa"
  display_name = "Service Account for BMI Calculator Function"
  description  = "Service account used by the BMI Calculator Cloud Function for secure access to Cloud Storage"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Grant the Cloud Function service account necessary permissions to write to Cloud Storage
resource "google_storage_bucket_iam_member" "function_storage_access" {
  bucket = google_storage_bucket.bmi_history.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.function_sa.email}"

  depends_on = [google_storage_bucket.bmi_history, google_service_account.function_sa]
}

# Create the function source code files locally
resource "local_file" "function_main" {
  filename = "${path.module}/function-source/main.py"
  content = <<-EOF
import functions_framework
import json
from datetime import datetime
from google.cloud import storage
import os

@functions_framework.http
def calculate_bmi(request):
    """HTTP Cloud Function that calculates BMI and stores history."""
    
    # Set CORS headers for web browser compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight OPTIONS request for CORS
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    # Parse JSON request body
    try:
        request_json = request.get_json(silent=True)
        if not request_json:
            return json.dumps({
                'error': 'Request must contain JSON data'
            }), 400, headers
        
        height = float(request_json.get('height', 0))
        weight = float(request_json.get('weight', 0))
        
        if height <= 0 or weight <= 0:
            return json.dumps({
                'error': 'Height and weight must be positive numbers'
            }), 400, headers
        
    except (ValueError, TypeError):
        return json.dumps({
            'error': 'Height and weight must be valid numbers'
        }), 400, headers
    
    # Calculate BMI using standard formula
    bmi = weight / (height ** 2)
    
    # Determine BMI category based on WHO standards
    if bmi < 18.5:
        category = 'Underweight'
    elif bmi < 25:
        category = 'Normal weight'
    elif bmi < 30:
        category = 'Overweight'
    else:
        category = 'Obese'
    
    # Create calculation record
    calculation = {
        'timestamp': datetime.utcnow().isoformat(),
        'height': height,
        'weight': weight,
        'bmi': round(bmi, 2),
        'category': category
    }
    
    # Store calculation in Cloud Storage
    try:
        bucket_name = os.environ.get('BUCKET_NAME')
        if bucket_name:
            client = storage.Client()
            bucket = client.bucket(bucket_name)
            
            # Create unique filename with timestamp
            filename = f"calculations/{datetime.utcnow().strftime('%Y%m%d_%H%M%S_%f')}.json"
            blob = bucket.blob(filename)
            blob.upload_from_string(json.dumps(calculation))
            
    except Exception as e:
        # Log error but don't fail the request
        print(f"Error storing calculation: {str(e)}")
    
    # Return BMI calculation result
    return json.dumps(calculation), 200, headers
EOF

  depends_on = [google_storage_bucket.bmi_history]
}

# Create requirements.txt for the Cloud Function
resource "local_file" "function_requirements" {
  filename = "${path.module}/function-source/requirements.txt"
  content = <<-EOF
functions-framework==3.*
google-cloud-storage==2.*
EOF
}

# Create ZIP archive of the function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  source_dir  = "${path.module}/function-source"

  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Upload the function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.bmi_history.name
  source = data.archive_file.function_source.output_path

  # Ensure the ZIP file is created before uploading
  depends_on = [data.archive_file.function_source]
}

# Deploy the Cloud Function (2nd generation)
resource "google_cloudfunctions2_function" "bmi_calculator" {
  name     = var.function_name
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = var.function_runtime
    entry_point = "calculate_bmi"
    
    source {
      storage_source {
        bucket = google_storage_bucket.bmi_history.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 100
    min_instance_count    = 0
    available_memory      = "${var.function_memory}M"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.function_sa.email

    # Environment variables for the function
    environment_variables = {
      BUCKET_NAME = google_storage_bucket.bmi_history.name
    }

    # Ingress settings for security
    ingress_settings = "ALLOW_ALL"
    
    # VPC settings (optional - using default network)
    vpc_connector_egress_settings = "PRIVATE_RANGES_ONLY"
  }

  # Apply labels for resource management
  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_service_account.function_sa
  ]
}

# IAM policy to allow unauthenticated access to the function (if enabled)
resource "google_cloudfunctions2_function_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0

  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.bmi_calculator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"

  depends_on = [google_cloudfunctions2_function.bmi_calculator]
}

# Create a Cloud Storage notification for monitoring (optional)
resource "google_storage_notification" "calculation_notification" {
  bucket         = google_storage_bucket.bmi_history.name
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.calculation_events.id
  object_name_prefix = "calculations/"
  
  event_types = [
    "OBJECT_FINALIZE"
  ]

  depends_on = [google_pubsub_topic_iam_member.storage_publisher]
}

# Create Pub/Sub topic for calculation events (optional for monitoring)
resource "google_pubsub_topic" "calculation_events" {
  name    = "${var.function_name}-calculation-events"
  project = var.project_id

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# IAM permission for Cloud Storage to publish to Pub/Sub
resource "google_pubsub_topic_iam_member" "storage_publisher" {
  topic  = google_pubsub_topic.calculation_events.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"

  depends_on = [google_pubsub_topic.calculation_events]
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Create Cloud Monitoring alert policy for function errors (optional)
resource "google_monitoring_alert_policy" "function_error_rate" {
  display_name = "BMI Calculator Function Error Rate"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Cloud Function error rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" resource.labels.function_name=\"${var.function_name}\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1 # 10% error rate
      duration        = "300s"
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []

  documentation {
    content = "The BMI Calculator Cloud Function is experiencing a high error rate. Please check the function logs for details."
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.bmi_calculator
  ]
}