# Main Terraform Configuration for GCP Unit Converter API
# This file defines all the infrastructure resources for the serverless unit conversion API

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])

  project = var.project_id
  service = each.key

  # Prevent deletion of APIs to avoid breaking dependencies
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Cloud Storage bucket for conversion history
resource "google_storage_bucket" "conversion_history" {
  name     = "${var.project_id}-${var.bucket_name_prefix}-${random_string.suffix.result}"
  location = var.region

  # Storage configuration
  storage_class               = var.storage_class
  uniform_bucket_level_access = var.enable_uniform_bucket_access

  # Security and compliance settings
  public_access_prevention = "enforced"
  
  # Versioning for data protection
  versioning {
    enabled = true
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

  # Labels for resource organization
  labels = var.labels

  # Ensure APIs are enabled before creating bucket
  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Function
resource "google_service_account" "function_service_account" {
  account_id   = "${var.function_name}-sa"
  display_name = "Service Account for ${var.function_name} Cloud Function"
  description  = "Service account used by the unit converter Cloud Function for secure access to Cloud Storage"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Grant Cloud Function service account access to the storage bucket
resource "google_storage_bucket_iam_member" "function_storage_access" {
  bucket = google_storage_bucket.conversion_history.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.function_service_account.email}"

  # Ensure bucket exists before granting permissions
  depends_on = [google_storage_bucket.conversion_history]
}

# Create local directory for function source code
resource "local_file" "function_main" {
  filename = "${path.module}/function_source/main.py"
  content  = <<-EOF
import json
import datetime
from google.cloud import storage
import os

# Initialize Cloud Storage client with automatic authentication
storage_client = storage.Client()
BUCKET_NAME = os.environ.get('BUCKET_NAME')

def convert_units(request):
    """
    HTTP Cloud Function for unit conversion with history storage.
    Supports temperature, weight, and length conversions.
    """
    
    # Set CORS headers for web browser compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight CORS requests
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Parse JSON request data
        request_json = request.get_json(silent=True)
        
        if not request_json:
            return ({'error': 'Invalid JSON in request body'}, 400, headers)
        
        # Extract conversion parameters
        value = float(request_json.get('value', 0))
        from_unit = request_json.get('from_unit', '').lower()
        to_unit = request_json.get('to_unit', '').lower()
        
        # Perform unit conversion using business logic
        result = perform_conversion(value, from_unit, to_unit)
        
        if result is None:
            return ({'error': 'Unsupported unit conversion'}, 400, headers)
        
        # Create conversion record for audit trail
        conversion_record = {
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'input_value': value,
            'from_unit': from_unit,
            'to_unit': to_unit,
            'result': result,
            'conversion_type': get_conversion_type(from_unit, to_unit)
        }
        
        # Store conversion history in Cloud Storage
        store_conversion_history(conversion_record)
        
        # Return successful conversion result
        response = {
            'original_value': value,
            'original_unit': from_unit,
            'converted_value': round(result, 4),
            'converted_unit': to_unit,
            'timestamp': conversion_record['timestamp']
        }
        
        return (response, 200, headers)
        
    except Exception as e:
        return ({'error': f'Conversion failed: {str(e)}'}, 500, headers)

def perform_conversion(value, from_unit, to_unit):
    """Convert between different unit types with precise calculations."""
    
    # Temperature conversions
    if from_unit == 'celsius' and to_unit == 'fahrenheit':
        return (value * 9/5) + 32
    elif from_unit == 'fahrenheit' and to_unit == 'celsius':
        return (value - 32) * 5/9
    elif from_unit == 'celsius' and to_unit == 'kelvin':
        return value + 273.15
    elif from_unit == 'kelvin' and to_unit == 'celsius':
        return value - 273.15
    
    # Length conversions
    elif from_unit == 'meters' and to_unit == 'feet':
        return value * 3.28084
    elif from_unit == 'feet' and to_unit == 'meters':
        return value * 0.3048
    elif from_unit == 'kilometers' and to_unit == 'miles':
        return value * 0.621371
    elif from_unit == 'miles' and to_unit == 'kilometers':
        return value * 1.60934
    
    # Weight conversions
    elif from_unit == 'kilograms' and to_unit == 'pounds':
        return value * 2.20462
    elif from_unit == 'pounds' and to_unit == 'kilograms':
        return value * 0.453592
    elif from_unit == 'grams' and to_unit == 'ounces':
        return value * 0.035274
    elif from_unit == 'ounces' and to_unit == 'grams':
        return value * 28.3495
    
    # Same unit conversions
    elif from_unit == to_unit:
        return value
    
    return None

def get_conversion_type(from_unit, to_unit):
    """Categorize conversion type for analytics purposes."""
    temp_units = ['celsius', 'fahrenheit', 'kelvin']
    length_units = ['meters', 'feet', 'kilometers', 'miles']
    weight_units = ['kilograms', 'pounds', 'grams', 'ounces']
    
    if from_unit in temp_units and to_unit in temp_units:
        return 'temperature'
    elif from_unit in length_units and to_unit in length_units:
        return 'length'
    elif from_unit in weight_units and to_unit in weight_units:
        return 'weight'
    
    return 'unknown'

def store_conversion_history(record):
    """Store conversion record in Cloud Storage for audit trail."""
    try:
        bucket = storage_client.bucket(BUCKET_NAME)
        
        # Create filename with timestamp for easy sorting
        filename = f"conversions/{record['timestamp']}-{record['conversion_type']}.json"
        blob = bucket.blob(filename)
        
        # Upload JSON record to Cloud Storage
        blob.upload_from_string(
            json.dumps(record, indent=2),
            content_type='application/json'
        )
        
    except Exception as e:
        print(f"Failed to store conversion history: {e}")
        # Continue processing even if storage fails
EOF
}

# Create requirements.txt for Python dependencies
resource "local_file" "function_requirements" {
  filename = "${path.module}/function_source/requirements.txt"
  content  = "google-cloud-storage==2.18.0\n"
}

# Create ZIP archive of function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function_source.zip"
  source_dir  = "${path.module}/function_source"
  
  # Ensure source files are created before archiving
  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_string.suffix.result}.zip"
  bucket = google_storage_bucket.conversion_history.name
  source = data.archive_file.function_source.output_path

  # Ensure archive is created before upload
  depends_on = [data.archive_file.function_source]
}

# Deploy Cloud Function for unit conversion API
resource "google_cloudfunctions_function" "unit_converter" {
  name        = var.function_name
  description = "Serverless HTTP API for unit conversions with history tracking"
  runtime     = var.function_runtime
  region      = var.region

  # Function source configuration
  source_archive_bucket = google_storage_bucket.conversion_history.name
  source_archive_object = google_storage_bucket_object.function_source.name
  entry_point          = "convert_units"

  # HTTP trigger configuration
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  # Resource allocation
  available_memory_mb = var.function_memory
  timeout            = var.function_timeout

  # Environment variables
  environment_variables = {
    BUCKET_NAME = google_storage_bucket.conversion_history.name
  }

  # Service account for secure access
  service_account_email = google_service_account.function_service_account.email

  # Labels for resource organization
  labels = var.labels

  # Ensure all dependencies are ready
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_storage_bucket_iam_member.function_storage_access
  ]
}

# Allow public access to Cloud Function if enabled
resource "google_cloudfunctions_function_iam_member" "public_access" {
  count = var.enable_public_access ? 1 : 0

  project        = google_cloudfunctions_function.unit_converter.project
  region         = google_cloudfunctions_function.unit_converter.region
  cloud_function = google_cloudfunctions_function.unit_converter.name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}

# Create Cloud Logging sink for function logs (optional monitoring enhancement)
resource "google_logging_project_sink" "function_logs" {
  name        = "${var.function_name}-logs-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.conversion_history.name}"
  filter      = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${var.function_name}\""

  # Use a unique writer identity for the sink
  unique_writer_identity = true

  depends_on = [google_cloudfunctions_function.unit_converter]
}

# Grant logging sink write access to the bucket
resource "google_storage_bucket_iam_member" "logging_sink_access" {
  bucket = google_storage_bucket.conversion_history.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs.writer_identity

  depends_on = [google_logging_project_sink.function_logs]
}