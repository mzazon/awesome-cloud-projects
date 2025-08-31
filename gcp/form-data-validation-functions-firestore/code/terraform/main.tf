# Generate random suffix for resource uniqueness
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent resource naming
locals {
  function_name_with_suffix = "${var.resource_prefix}-${var.function_name}-${random_id.suffix.hex}"
  firestore_location        = var.firestore_location != "" ? var.firestore_location : var.region
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    terraform = "true"
    recipe    = "form-data-validation-functions-firestore"
  })
  
  # Function source files
  function_source_files = {
    "main.py" = <<-EOT
import functions_framework
import json
import re
from google.cloud import firestore
from google.cloud import logging as cloud_logging
import logging
from datetime import datetime

# Initialize Firestore client
db = firestore.Client()

# Initialize Cloud Logging
logging_client = cloud_logging.Client()
logging_client.setup_logging()

def validate_email(email):
    """Validate email format using regex pattern"""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return re.match(pattern, email) is not None

def validate_phone(phone):
    """Validate phone number (basic US format)"""
    # Remove all non-digits
    clean_phone = re.sub(r'\D', '', phone)
    return len(clean_phone) == 10

def sanitize_string(value, max_length=100):
    """Sanitize string input by trimming and limiting length"""
    if not isinstance(value, str):
        return ""
    return value.strip()[:max_length]

@functions_framework.http
def validate_form_data(request):
    """
    HTTP Cloud Function for form data validation and storage
    """
    # Set CORS headers for web browser compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    # Only accept POST requests for form submission
    if request.method != 'POST':
        return (json.dumps({'error': 'Method not allowed'}), 405, headers)
    
    try:
        # Parse JSON request body
        request_json = request.get_json(silent=True)
        if not request_json:
            return (json.dumps({'error': 'Invalid JSON payload'}), 400, headers)
        
        # Extract and validate form fields
        errors = []
        
        # Validate required name field
        name = sanitize_string(request_json.get('name', ''))
        if not name:
            errors.append('Name is required')
        elif len(name) < 2:
            errors.append('Name must be at least 2 characters')
        
        # Validate email field
        email = sanitize_string(request_json.get('email', ''))
        if not email:
            errors.append('Email is required')
        elif not validate_email(email):
            errors.append('Invalid email format')
        
        # Validate phone field (optional)
        phone = sanitize_string(request_json.get('phone', ''))
        if phone and not validate_phone(phone):
            errors.append('Invalid phone number format')
        
        # Validate message field
        message = sanitize_string(request_json.get('message', ''), 500)
        if not message:
            errors.append('Message is required')
        elif len(message) < 10:
            errors.append('Message must be at least 10 characters')
        
        # Return validation errors if any
        if errors:
            logging.warning(f'Form validation failed: {errors}')
            return (json.dumps({
                'success': False,
                'errors': errors
            }), 400, headers)
        
        # Create document data for Firestore
        form_data = {
            'name': name,
            'email': email.lower(),  # Normalize email to lowercase
            'phone': re.sub(r'\D', '', phone) if phone else None,
            'message': message,
            'submitted_at': datetime.utcnow(),
            'source': 'web_form'
        }
        
        # Store validated data in Firestore
        doc_ref = db.collection('form_submissions').add(form_data)
        document_id = doc_ref[1].id
        
        # Log successful submission
        logging.info(f'Form submitted successfully: {document_id}')
        
        # Return success response
        return (json.dumps({
            'success': True,
            'message': 'Form submitted successfully',
            'id': document_id
        }), 200, headers)
        
    except Exception as e:
        # Log error and return generic error response
        logging.error(f'Function error: {str(e)}')
        return (json.dumps({
            'success': False,
            'error': 'Internal server error'
        }), 500, headers)
EOT

    "requirements.txt" = <<-EOT
functions-framework==3.*
google-cloud-firestore>=2.0.0
google-cloud-logging>=3.0.0
EOT
  }
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_required_apis ? toset(var.required_apis) : toset([])
  
  project = var.project_id
  service = each.value
  
  # Don't disable the service when the resource is destroyed
  disable_on_destroy = false
  
  # Don't fail if the service is already enabled
  disable_dependent_services = false
}

# Create Firestore database
resource "google_firestore_database" "form_validation_db" {
  provider = google-beta
  
  project     = var.project_id
  name        = "(default)"
  location_id = local.firestore_location
  type        = var.firestore_database_type
  
  # Ensure APIs are enabled before creating database
  depends_on = [
    google_project_service.required_apis
  ]
  
  # Apply labels for resource management
  labels = local.common_labels
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name          = "${var.project_id}-${local.function_name_with_suffix}-source"
  location      = var.region
  force_destroy = true
  
  # Enable uniform bucket-level access for security
  uniform_bucket_level_access = true
  
  # Configure lifecycle management to clean up old versions
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Apply labels for resource management
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Create temporary directory for function source
resource "local_file" "function_source_files" {
  for_each = local.function_source_files
  
  filename = "${path.module}/temp/${each.key}"
  content  = each.value
}

# Create archive of function source code
data "archive_file" "function_source_zip" {
  type        = "zip"
  output_path = "${path.module}/temp/function-source.zip"
  
  dynamic "source" {
    for_each = local.function_source_files
    content {
      content  = source.value
      filename = source.key
    }
  }
  
  depends_on = [local_file.function_source_files]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source_zip" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source_zip.output_path
  
  # Detect changes in source code
  source_hash = data.archive_file.function_source_zip.output_md5
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_prefix}-function-sa-${random_id.suffix.hex}"
  display_name = "Service Account for Form Validation Function"
  description  = "Service account used by the form validation Cloud Function"
  project      = var.project_id
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Grant Firestore access to the function service account
resource "google_project_iam_member" "function_firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant Cloud Logging access to the function service account
resource "google_project_iam_member" "function_logging_writer" {
  count = var.enable_cloud_logging ? 1 : 0
  
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Deploy Cloud Function (Gen 2)
resource "google_cloudfunctions2_function" "form_validation_function" {
  name        = local.function_name_with_suffix
  location    = var.region
  description = "HTTP function for validating and storing form data in Firestore"
  project     = var.project_id
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "validate_form_data"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source_zip.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 100
    min_instance_count    = 0
    available_memory      = "${var.function_memory}M"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.function_sa.email
    
    # Environment variables for function configuration
    environment_variables = {
      GOOGLE_CLOUD_PROJECT = var.project_id
      FIRESTORE_DATABASE   = google_firestore_database.form_validation_db.name
    }
    
    # Configure ingress settings for security
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }
  
  # Apply labels for resource management
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_firestore_database.form_validation_db,
    google_storage_bucket_object.function_source_zip
  ]
}

# Create IAM binding to allow unauthenticated invocations (if enabled)
resource "google_cloudfunctions2_function_iam_member" "allow_unauthenticated" {
  count = var.allow_unauthenticated_invocations ? 1 : 0
  
  project        = var.project_id
  location       = google_cloudfunctions2_function.form_validation_function.location
  cloud_function = google_cloudfunctions2_function.form_validation_function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create Firestore security rules (basic rules for form submissions)
resource "google_firestore_database" "security_rules" {
  provider = google-beta
  
  # This creates a basic security rule for the database
  # In production, you should customize these rules based on your security requirements
  project     = var.project_id
  name        = google_firestore_database.form_validation_db.name
  location_id = google_firestore_database.form_validation_db.location_id
  type        = google_firestore_database.form_validation_db.type
  
  depends_on = [google_firestore_database.form_validation_db]
  
  lifecycle {
    ignore_changes = [
      # Ignore changes to prevent conflicts with existing database
      location_id,
      type
    ]
  }
}