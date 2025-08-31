# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ==============================================================================
# DATA SOURCES AND LOCALS
# ==============================================================================

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Resource naming convention: {prefix}-{component}-{environment}-{random}
  name_suffix = "${var.environment}-${random_id.suffix.hex}"
  
  # Function names
  encoder_function_name = "${var.resource_prefix}-encoder-${local.name_suffix}"
  decoder_function_name = "${var.resource_prefix}-decoder-${local.name_suffix}"
  
  # Storage bucket name (globally unique)
  bucket_name = "${var.resource_prefix}-files-${local.name_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    created-by  = "terraform"
    timestamp   = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Source code directory structure
  source_dir = "${path.module}/../function-source"
}

# ==============================================================================
# GOOGLE CLOUD APIs
# ==============================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com", 
    "storage.googleapis.com",
    "logging.googleapis.com",
    "run.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling these APIs during destroy to avoid service disruption
  disable_dependent_services = false
  disable_on_destroy         = false
}

# ==============================================================================
# CLOUD STORAGE RESOURCES
# ==============================================================================

# Cloud Storage bucket for storing function source code and file operations
resource "google_storage_bucket" "function_bucket" {
  name          = local.bucket_name
  project       = var.project_id
  location      = var.storage_location
  storage_class = var.storage_class
  
  # Security and access configuration
  uniform_bucket_level_access = var.uniform_bucket_level_access
  force_destroy              = true # Allow Terraform to delete bucket with objects
  
  # Versioning configuration
  dynamic "versioning" {
    for_each = var.enable_versioning ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle ? [1] : []
    content {
      condition {
        age = var.lifecycle_age_days
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # CORS configuration for web browser access
  cors {
    origin          = var.cors_origins
    method          = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  # Resource labels for organization and billing
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# ==============================================================================
# FUNCTION SOURCE CODE CREATION
# ==============================================================================

# Create encoder function source code directory
resource "local_file" "encoder_main_py" {
  filename = "${local.source_dir}/encoder/main.py"
  
  content = <<-EOF
import base64
import json
import logging
from google.cloud import storage
import functions_framework

# Configure logging for monitoring and debugging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def encode_base64(request):
    """
    HTTP Cloud Function to encode text or files to Base64.
    
    Supports multiple input methods:
    - GET requests with 'text' query parameter
    - POST requests with JSON payload containing 'text' field
    - POST requests with file upload via form data
    
    Returns JSON response with encoded data and metadata.
    """
    
    # Set CORS headers for cross-origin browser compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Content-Type': 'application/json'
    }
    
    # Handle preflight CORS requests
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        if request.method == 'POST':
            # Handle JSON input for text encoding
            if request.is_json:
                data = request.get_json()
                text_input = data.get('text', '')
                
                if not text_input:
                    return (json.dumps({'error': 'Text input required'}), 400, headers)
                
                # Encode text to Base64
                encoded = base64.b64encode(text_input.encode('utf-8')).decode('utf-8')
                
                response = {
                    'success': True,
                    'encoded': encoded,
                    'original_length': len(text_input),
                    'encoded_length': len(encoded),
                    'type': 'text'
                }
                
                logger.info(f"Successfully encoded {len(text_input)} characters")
                return (json.dumps(response), 200, headers)
            
            # Handle form data for file uploads
            elif 'file' in request.files:
                file = request.files['file']
                if file.filename == '':
                    return (json.dumps({'error': 'No file selected'}), 400, headers)
                    
                file_content = file.read()
                
                # Encode file content to Base64
                encoded = base64.b64encode(file_content).decode('utf-8')
                
                response = {
                    'success': True,
                    'encoded': encoded,
                    'filename': file.filename,
                    'original_size': len(file_content),
                    'encoded_size': len(encoded),
                    'type': 'file'
                }
                
                logger.info(f"Successfully encoded file: {file.filename} ({len(file_content)} bytes)")
                return (json.dumps(response), 200, headers)
            
            else:
                return (json.dumps({'error': 'Invalid POST request format'}), 400, headers)
        
        # Handle GET requests with query parameters
        elif request.method == 'GET':
            query_text = request.args.get('text', '')
            
            if not query_text:
                # Return usage information if no text provided
                usage_info = {
                    'error': 'Text parameter required',
                    'usage': {
                        'GET': 'Add ?text=your_text_here to the URL',
                        'POST_JSON': 'Send JSON with {"text": "your_text_here"}',
                        'POST_FILE': 'Upload file using form data with "file" field'
                    }
                }
                return (json.dumps(usage_info), 400, headers)
            
            # Encode query text to Base64
            encoded = base64.b64encode(query_text.encode('utf-8')).decode('utf-8')
            
            response = {
                'success': True,
                'encoded': encoded,
                'original_length': len(query_text),
                'encoded_length': len(encoded),
                'type': 'text'
            }
            
            logger.info(f"Successfully encoded query text ({len(query_text)} characters)")
            return (json.dumps(response), 200, headers)
        
        else:
            return (json.dumps({'error': 'Method not allowed'}), 405, headers)
        
    except Exception as e:
        logger.error(f"Encoding error: {str(e)}")
        return (json.dumps({
            'success': False,
            'error': 'Internal server error',
            'message': 'Failed to process encoding request'
        }), 500, headers)
EOF
  
  # Create directory if it doesn't exist
  depends_on = [google_project_service.required_apis]
}

# Create encoder function requirements
resource "local_file" "encoder_requirements" {
  filename = "${local.source_dir}/encoder/requirements.txt"
  
  content = <<-EOF
functions-framework==3.*
google-cloud-storage==2.*
EOF
  
  depends_on = [local_file.encoder_main_py]
}

# Create decoder function source code
resource "local_file" "decoder_main_py" {
  filename = "${local.source_dir}/decoder/main.py"
  
  content = <<-EOF
import base64
import json
import logging
from google.cloud import storage
import functions_framework

# Configure logging for monitoring and debugging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def decode_base64(request):
    """
    HTTP Cloud Function to decode Base64 text back to original format.
    
    Supports multiple input methods:
    - GET requests with 'encoded' query parameter
    - POST requests with JSON payload containing 'encoded' field
    
    Returns JSON response with decoded data and metadata.
    """
    
    # Set CORS headers for cross-origin browser compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Content-Type': 'application/json'
    }
    
    # Handle preflight CORS requests
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        base64_input = ''
        
        if request.method == 'POST' and request.is_json:
            data = request.get_json()
            base64_input = data.get('encoded', '')
        elif request.method == 'GET':
            base64_input = request.args.get('encoded', '')
        else:
            return (json.dumps({'error': 'Invalid request method or format'}), 400, headers)
        
        if not base64_input:
            usage_info = {
                'error': 'Base64 encoded input required',
                'usage': {
                    'GET': 'Add ?encoded=your_base64_here to the URL',
                    'POST_JSON': 'Send JSON with {"encoded": "your_base64_here"}'
                }
            }
            return (json.dumps(usage_info), 400, headers)
        
        # Validate and decode Base64 input
        try:
            # Remove any whitespace and validate Base64 format
            base64_input = base64_input.strip()
            decoded_bytes = base64.b64decode(base64_input, validate=True)
            
            # Attempt to decode as UTF-8 text
            try:
                decoded_text = decoded_bytes.decode('utf-8')
                is_text = True
                is_printable = decoded_text.isprintable()
            except UnicodeDecodeError:
                decoded_text = None
                is_text = False
                is_printable = False
            
            response = {
                'success': True,
                'decoded': decoded_text if is_text else None,
                'is_text': is_text,
                'is_printable': is_printable,
                'decoded_size_bytes': len(decoded_bytes),
                'original_base64_length': len(base64_input)
            }
            
            if not is_text:
                response['message'] = 'Content appears to be binary data'
                response['binary_size'] = len(decoded_bytes)
            elif not is_printable:
                response['message'] = 'Content contains non-printable characters'
            
            logger.info(f"Successfully decoded {len(base64_input)} Base64 characters to {len(decoded_bytes)} bytes")
            return (json.dumps(response), 200, headers)
            
        except Exception as decode_error:
            logger.warning(f"Base64 decode error: {str(decode_error)}")
            return (json.dumps({
                'success': False,
                'error': 'Invalid Base64 input',
                'details': 'Input must be valid Base64 encoded data',
                'provided_length': len(base64_input)
            }), 400, headers)
        
    except Exception as e:
        logger.error(f"Decoder error: {str(e)}")
        return (json.dumps({
            'success': False,
            'error': 'Internal server error',
            'message': 'Failed to process decoding request'
        }), 500, headers)
EOF
  
  depends_on = [local_file.encoder_requirements]
}

# Create decoder function requirements
resource "local_file" "decoder_requirements" {
  filename = "${local.source_dir}/decoder/requirements.txt"
  
  content = <<-EOF
functions-framework==3.*
google-cloud-storage==2.*
EOF
  
  depends_on = [local_file.decoder_main_py]
}

# ==============================================================================
# FUNCTION SOURCE CODE ARCHIVES
# ==============================================================================

# Create ZIP archive for encoder function
data "archive_file" "encoder_source" {
  type        = "zip"
  source_dir  = "${local.source_dir}/encoder"
  output_path = "${path.module}/encoder-source.zip"
  
  depends_on = [
    local_file.encoder_main_py,
    local_file.encoder_requirements
  ]
}

# Create ZIP archive for decoder function
data "archive_file" "decoder_source" {
  type        = "zip"
  source_dir  = "${local.source_dir}/decoder"
  output_path = "${path.module}/decoder-source.zip"
  
  depends_on = [
    local_file.decoder_main_py,
    local_file.decoder_requirements
  ]
}

# ==============================================================================
# STORAGE OBJECTS FOR FUNCTION SOURCE
# ==============================================================================

# Upload encoder function source to Cloud Storage
resource "google_storage_bucket_object" "encoder_source" {
  name   = "encoder-source-${data.archive_file.encoder_source.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.encoder_source.output_path
  
  # Ensure source code changes trigger redeployment
  content_type = "application/zip"
  
  depends_on = [data.archive_file.encoder_source]
}

# Upload decoder function source to Cloud Storage
resource "google_storage_bucket_object" "decoder_source" {
  name   = "decoder-source-${data.archive_file.decoder_source.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.decoder_source.output_path
  
  # Ensure source code changes trigger redeployment
  content_type = "application/zip"
  
  depends_on = [data.archive_file.decoder_source]
}

# ==============================================================================
# CLOUD FUNCTIONS
# ==============================================================================

# Base64 Encoder Cloud Function
resource "google_cloudfunctions2_function" "encoder" {
  name        = local.encoder_function_name
  project     = var.project_id
  location    = var.region
  description = "Base64 encoder function - converts text and files to Base64 format"
  
  # Build configuration
  build_config {
    runtime     = var.function_runtime
    entry_point = "encode_base64"
    
    # Source code configuration
    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.encoder_source.name
      }
    }
    
    # Environment variables for build process
    environment_variables = {
      BUILD_CONFIG_TYPE = "encoder"
    }
    
    # Enable automatic base image updates for security
    automatic_update_policy {}
  }
  
  # Service configuration
  service_config {
    max_instance_count    = var.max_instances
    min_instance_count    = var.min_instances
    available_memory      = var.function_memory
    timeout_seconds       = var.function_timeout
    
    # Environment variables for runtime
    environment_variables = {
      FUNCTION_TYPE = "encoder"
      BUCKET_NAME   = google_storage_bucket.function_bucket.name
    }
    
    # Security settings
    ingress_settings                = var.enable_public_access ? "ALLOW_ALL" : "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }
  
  # Resource labels
  labels = merge(local.common_labels, {
    function-type = "encoder"
  })
  
  depends_on = [
    google_storage_bucket_object.encoder_source,
    google_project_service.required_apis
  ]
}

# Base64 Decoder Cloud Function
resource "google_cloudfunctions2_function" "decoder" {
  name        = local.decoder_function_name
  project     = var.project_id
  location    = var.region
  description = "Base64 decoder function - converts Base64 data back to original format"
  
  # Build configuration
  build_config {
    runtime     = var.function_runtime
    entry_point = "decode_base64"
    
    # Source code configuration
    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.decoder_source.name
      }
    }
    
    # Environment variables for build process
    environment_variables = {
      BUILD_CONFIG_TYPE = "decoder"
    }
    
    # Enable automatic base image updates for security
    automatic_update_policy {}
  }
  
  # Service configuration
  service_config {
    max_instance_count    = var.max_instances
    min_instance_count    = var.min_instances
    available_memory      = var.function_memory
    timeout_seconds       = var.function_timeout
    
    # Environment variables for runtime
    environment_variables = {
      FUNCTION_TYPE = "decoder"
      BUCKET_NAME   = google_storage_bucket.function_bucket.name
    }
    
    # Security settings
    ingress_settings                = var.enable_public_access ? "ALLOW_ALL" : "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }
  
  # Resource labels
  labels = merge(local.common_labels, {
    function-type = "decoder"
  })
  
  depends_on = [
    google_storage_bucket_object.decoder_source,
    google_project_service.required_apis
  ]
}

# ==============================================================================
# IAM PERMISSIONS FOR PUBLIC ACCESS
# ==============================================================================

# Allow unauthenticated access to encoder function (if enabled)
resource "google_cloudfunctions2_function_iam_member" "encoder_invoker" {
  count = var.enable_public_access ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.encoder.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Allow unauthenticated access to decoder function (if enabled)
resource "google_cloudfunctions2_function_iam_member" "decoder_invoker" {
  count = var.enable_public_access ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.decoder.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Allow unauthenticated access to Cloud Run services (if enabled)
resource "google_cloud_run_service_iam_member" "encoder_run_invoker" {
  count = var.enable_public_access ? 1 : 0
  
  project  = var.project_id
  location = var.region
  service  = google_cloudfunctions2_function.encoder.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "decoder_run_invoker" {
  count = var.enable_public_access ? 1 : 0
  
  project  = var.project_id
  location = var.region
  service  = google_cloudfunctions2_function.decoder.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}