# Currency Converter API with Google Cloud Functions and Secret Manager
# This Terraform configuration deploys a serverless currency conversion API

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed configurations
locals {
  # Use provided secret name or generate one with random suffix
  secret_name = var.secret_name != null ? var.secret_name : "exchange-api-key-${random_id.suffix.hex}"
  
  # Function source directory (relative to this terraform directory)
  function_source_dir = "${path.module}/../function-source"
  
  # Environment variables for the Cloud Function
  function_env_vars = {
    GCP_PROJECT  = var.project_id
    SECRET_NAME  = local.secret_name
  }
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    component = "currency-converter-api"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = var.enable_apis ? toset([
    "cloudfunctions.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]) : toset([])
  
  project                    = var.project_id
  service                    = each.key
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create Secret Manager secret for storing the exchange rate API key
resource "google_secret_manager_secret" "exchange_api_key" {
  secret_id = local.secret_name
  
  labels = local.common_labels
  
  replication {
    auto {}
  }
  
  depends_on = [google_project_service.apis]
}

# Store the exchange rate API key value in Secret Manager
resource "google_secret_manager_secret_version" "exchange_api_key_version" {
  secret      = google_secret_manager_secret.exchange_api_key.id
  secret_data = var.exchange_api_key
}

# Create function source directory with Python code
resource "local_file" "function_main" {
  filename = "${local.function_source_dir}/main.py"
  content = <<-EOF
import functions_framework
import requests
import json
from google.cloud import secretmanager

# Initialize Secret Manager client
secret_client = secretmanager.SecretManagerServiceClient()

def get_api_key():
    """Retrieve API key from Secret Manager"""
    import os
    project_id = os.environ.get('GCP_PROJECT')
    secret_name = os.environ.get('SECRET_NAME')
    
    name = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
    response = secret_client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

@functions_framework.http
def currency_converter(request):
    """HTTP Cloud Function for currency conversion"""
    
    # Set CORS headers for web browsers
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Parse request parameters
        if request.method == 'GET':
            from_currency = request.args.get('from', 'USD')
            to_currency = request.args.get('to', 'EUR')
            amount = float(request.args.get('amount', '1'))
        else:
            request_json = request.get_json()
            from_currency = request_json.get('from', 'USD')
            to_currency = request_json.get('to', 'EUR')
            amount = float(request_json.get('amount', '1'))
        
        # Get API key from Secret Manager
        api_key = get_api_key()
        
        # Call exchange rate API (use HTTPS for security)
        url = f"https://data.fixer.io/api/convert"
        params = {
            'access_key': api_key,
            'from': from_currency,
            'to': to_currency,
            'amount': amount
        }
        
        response = requests.get(url, params=params)
        data = response.json()
        
        if data.get('success'):
            result = {
                'success': True,
                'from': from_currency,
                'to': to_currency,
                'amount': amount,
                'result': data['result'],
                'rate': data['info']['rate'],
                'timestamp': data['date']
            }
        else:
            result = {
                'success': False,
                'error': data.get('error', {}).get('info', 'Unknown error')
            }
        
        return (json.dumps(result), 200, headers)
        
    except Exception as e:
        error_result = {
            'success': False,
            'error': f'Internal error: {str(e)}'
        }
        return (json.dumps(error_result), 500, headers)
EOF

  depends_on = [google_project_service.apis]
}

# Create requirements.txt for function dependencies
resource "local_file" "function_requirements" {
  filename = "${local.function_source_dir}/requirements.txt"
  content = <<-EOF
functions-framework>=3.0.0,<4.0.0
google-cloud-secret-manager>=2.16.0,<3.0.0
requests>=2.31.0,<3.0.0
EOF

  depends_on = [google_project_service.apis]
}

# Create a ZIP archive of the function source code
data "archive_file" "function_source_zip" {
  type        = "zip"
  source_dir  = local.function_source_dir
  output_path = "${path.module}/function-source.zip"
  
  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Create a Cloud Storage bucket for storing the function source code
resource "google_storage_bucket" "function_source_bucket" {
  name                        = "${var.project_id}-currency-converter-source-${random_id.suffix.hex}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy              = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Upload the function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source_object" {
  name   = "function-source-${data.archive_file.function_source_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.function_source_zip.output_path
  
  depends_on = [data.archive_file.function_source_zip]
}

# Deploy the Cloud Function with HTTP trigger
resource "google_cloudfunctions_function" "currency_converter" {
  name        = var.function_name
  description = "Serverless currency converter API using external exchange rate services"
  region      = var.region
  
  runtime               = var.function_runtime
  available_memory_mb   = var.function_memory
  timeout              = var.function_timeout
  entry_point          = "currency_converter"
  min_instances        = var.min_instances
  max_instances        = var.max_instances
  
  source_archive_bucket = google_storage_bucket.function_source_bucket.name
  source_archive_object = google_storage_bucket_object.function_source_object.name
  
  # Configure HTTP trigger
  trigger {
    http_trigger {}
  }
  
  # Set environment variables for the function
  environment_variables = local.function_env_vars
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_secret_manager_secret_version.exchange_api_key_version
  ]
}

# Grant the Cloud Function's service account access to the secret
resource "google_secret_manager_secret_iam_member" "function_secret_access" {
  secret_id = google_secret_manager_secret.exchange_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_cloudfunctions_function.currency_converter.service_account_email}"
  
  depends_on = [google_cloudfunctions_function.currency_converter]
}

# Configure IAM to allow public access to the HTTP function (if enabled)
resource "google_cloudfunctions_function_iam_member" "invoker" {
  count = var.allow_unauthenticated ? 1 : 0
  
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.currency_converter.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}