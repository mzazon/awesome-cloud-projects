# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  count   = var.enable_apis ? length(var.required_apis) : 0
  project = var.project_id
  service = var.required_apis[count.index]

  # Disable the service when the resource is destroyed
  disable_on_destroy = false

  # Don't fail if the service is already enabled
  disable_dependent_services = false
}

# Create the function source code files
resource "local_file" "main_py" {
  filename = "${var.source_directory}/main.py"
  content = <<-EOT
import functions_framework
import json

# Unit conversion formulas
CONVERSIONS = {
    'temperature': {
        'celsius_to_fahrenheit': lambda c: (c * 9/5) + 32,
        'fahrenheit_to_celsius': lambda f: (f - 32) * 5/9,
        'celsius_to_kelvin': lambda c: c + 273.15,
        'kelvin_to_celsius': lambda k: k - 273.15,
        'fahrenheit_to_kelvin': lambda f: (f - 32) * 5/9 + 273.15,
        'kelvin_to_fahrenheit': lambda k: (k - 273.15) * 9/5 + 32
    },
    'distance': {
        'meters_to_feet': lambda m: m * 3.28084,
        'feet_to_meters': lambda f: f / 3.28084,
        'kilometers_to_miles': lambda km: km * 0.621371,
        'miles_to_kilometers': lambda mi: mi / 0.621371,
        'inches_to_centimeters': lambda i: i * 2.54,
        'centimeters_to_inches': lambda cm: cm / 2.54
    },
    'weight': {
        'kilograms_to_pounds': lambda kg: kg * 2.20462,
        'pounds_to_kilograms': lambda lb: lb / 2.20462,
        'grams_to_ounces': lambda g: g * 0.035274,
        'ounces_to_grams': lambda oz: oz / 0.035274,
        'tons_to_pounds': lambda t: t * 2000,
        'pounds_to_tons': lambda lb: lb / 2000
    }
}

@functions_framework.http
def convert_units(request):
    """HTTP Cloud Function for unit conversion.
    Args:
        request (flask.Request): The request object.
    Returns:
        The response text, or any set of values that can be turned into a
        Response object using `make_response`.
    """
    
    # Set CORS headers for web browser compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight requests
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Parse request data
        if request.method == 'GET':
            # Handle GET requests with query parameters
            category = request.args.get('category', '').lower()
            conversion_type = request.args.get('type', '').lower()
            value = float(request.args.get('value', 0))
        elif request.method == 'POST':
            # Handle POST requests with JSON body
            request_json = request.get_json(silent=True)
            if not request_json:
                return (json.dumps({'error': 'Invalid JSON in request body'}), 400, headers)
            
            category = request_json.get('category', '').lower()
            conversion_type = request_json.get('type', '').lower()
            value = float(request_json.get('value', 0))
        else:
            return (json.dumps({'error': 'Method not allowed'}), 405, headers)
        
        # Validate input parameters
        if not category or not conversion_type:
            return (json.dumps({
                'error': 'Missing required parameters: category and type',
                'available_categories': list(CONVERSIONS.keys()),
                'example': {
                    'category': 'temperature',
                    'type': 'celsius_to_fahrenheit',
                    'value': 25
                }
            }), 400, headers)
        
        # Check if category exists
        if category not in CONVERSIONS:
            return (json.dumps({
                'error': f'Unknown category: {category}',
                'available_categories': list(CONVERSIONS.keys())
            }), 400, headers)
        
        # Check if conversion type exists
        if conversion_type not in CONVERSIONS[category]:
            return (json.dumps({
                'error': f'Unknown conversion type: {conversion_type}',
                'available_types': list(CONVERSIONS[category].keys())
            }), 400, headers)
        
        # Perform conversion
        conversion_func = CONVERSIONS[category][conversion_type]
        result = conversion_func(value)
        
        # Return successful response
        response_data = {
            'input': {
                'category': category,
                'type': conversion_type,
                'value': value
            },
            'result': round(result, 6),
            'success': True
        }
        
        return (json.dumps(response_data), 200, headers)
        
    except ValueError as e:
        return (json.dumps({'error': f'Invalid value: {str(e)}'}), 400, headers)
    except Exception as e:
        return (json.dumps({'error': f'Internal server error: {str(e)}'}), 500, headers)
EOT

  # Ensure the directory exists
  depends_on = [local_file.requirements_txt]
}

resource "local_file" "requirements_txt" {
  filename = "${var.source_directory}/requirements.txt"
  content  = "functions-framework==3.*\n"
}

# Create a zip archive of the function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${var.source_directory}/function-source.zip"
  source_dir  = var.source_directory
  excludes    = ["function-source.zip"]

  depends_on = [
    local_file.main_py,
    local_file.requirements_txt
  ]
}

# Create a Cloud Storage bucket for the function source code
resource "google_storage_bucket" "function_source_bucket" {
  name     = "${var.project_id}-function-source-${random_id.suffix.hex}"
  location = var.region
  
  # Prevent accidental deletion of the bucket
  force_destroy = true
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = merge(var.labels, {
    purpose = "cloud-function-source"
  })

  depends_on = [google_project_service.required_apis]
}

# Upload the function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source_zip" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.function_source.output_path

  # Update the object when the source changes
  content_type = "application/zip"
}

# Create the Cloud Function (Gen 2)
resource "google_cloudfunctions2_function" "unit_converter" {
  name        = "${var.function_name}-${random_id.suffix.hex}"
  location    = var.region
  description = var.function_description

  build_config {
    runtime     = var.python_runtime
    entry_point = "convert_units"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.function_source_zip.name
      }
    }
  }

  service_config {
    max_instance_count = var.max_instances
    min_instance_count = var.min_instances
    available_memory   = "${var.function_memory}Mi"
    timeout_seconds    = var.function_timeout
    
    # Configure environment variables if needed
    environment_variables = {
      FUNCTION_REGION = var.region
      FUNCTION_NAME   = var.function_name
    }

    # Enable Cloud Functions insights
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
    
    # Configure service account (uses default Compute Engine service account)
    service_account_email = "${data.google_project.current.number}-compute@developer.gserviceaccount.com"
  }

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Create IAM policy to allow unauthenticated access (if enabled)
resource "google_cloudfunctions2_function_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0
  
  project        = var.project_id
  location       = google_cloudfunctions2_function.unit_converter.location
  cloud_function = google_cloudfunctions2_function.unit_converter.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create Cloud Run service IAM policy for public access (Gen 2 functions use Cloud Run)
resource "google_cloud_run_service_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0
  
  project  = var.project_id
  location = google_cloudfunctions2_function.unit_converter.location
  service  = google_cloudfunctions2_function.unit_converter.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}