# main.tf - Core infrastructure for Weather Dashboard with Cloud Functions and Storage
#
# This Terraform configuration deploys a serverless weather dashboard using:
# - Google Cloud Functions (2nd gen) for weather API proxy
# - Google Cloud Storage for static website hosting
# - IAM service accounts for secure resource access
# - Proper CORS and security configurations

# ============================================================================
# Local Values and Data Sources
# ============================================================================

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 8
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# Common labels applied to all resources
locals {
  common_labels = merge(var.labels, {
    environment     = var.environment
    project         = var.project_id
    region          = var.region
    deployment_tool = "terraform"
    created_by      = "weather-dashboard-recipe"
  })
  
  # Resource naming
  function_name    = "${var.application_name}-${var.function_name}-${random_string.suffix.result}"
  bucket_name      = "${var.application_name}-website-${random_string.suffix.result}"
  source_bucket    = "${var.application_name}-source-${random_string.suffix.result}"
  service_account  = "${var.application_name}-function-sa-${random_string.suffix.result}"
}

# Get current Google Cloud project information
data "google_project" "current" {
  project_id = var.project_id
}

# ============================================================================
# Enable Required APIs
# ============================================================================

# Enable Cloud Functions API
resource "google_project_service" "cloudfunctions" {
  project = var.project_id
  service = "cloudfunctions.googleapis.com"
  
  # Prevent accidental disabling during destroy
  disable_on_destroy = false
}

# Enable Cloud Storage API
resource "google_project_service" "storage" {
  project = var.project_id
  service = "storage.googleapis.com"
  
  disable_on_destroy = false
}

# Enable Cloud Build API (required for Cloud Functions deployment)
resource "google_project_service" "cloudbuild" {
  project = var.project_id
  service = "cloudbuild.googleapis.com"
  
  disable_on_destroy = false
}

# Enable Cloud Resource Manager API
resource "google_project_service" "cloudresourcemanager" {
  project = var.project_id
  service = "cloudresourcemanager.googleapis.com"
  
  disable_on_destroy = false
}

# Enable IAM API
resource "google_project_service" "iam" {
  project = var.project_id
  service = "iam.googleapis.com"
  
  disable_on_destroy = false
}

# ============================================================================
# IAM Service Account for Cloud Function
# ============================================================================

# Service account for the Cloud Function with least privilege access
resource "google_service_account" "function_sa" {
  account_id   = local.service_account
  display_name = "Weather Dashboard Function Service Account"
  description  = "Service account for the weather API Cloud Function with minimal required permissions"
  project      = var.project_id

  depends_on = [google_project_service.iam]
}

# Grant minimal required permissions to the service account
resource "google_project_iam_member" "function_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant logging permissions for function execution logs
resource "google_project_iam_member" "logs_writer" {
  count   = var.enable_function_logging ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# ============================================================================
# Cloud Storage for Function Source Code
# ============================================================================

# Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source_bucket" {
  name                        = local.source_bucket
  location                    = var.bucket_location
  project                     = var.project_id
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = var.force_destroy_bucket

  # Security configuration
  public_access_prevention = "enforced"

  # Lifecycle management for source artifacts
  lifecycle_rule {
    condition {
      age = 30 # Delete old source artifacts after 30 days
    }
    action {
      type = "Delete"
    }
  }

  # Labels for resource management
  labels = local.common_labels

  depends_on = [google_project_service.storage]
}

# Create the Cloud Function source code as a zip file
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/weather-function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      default_city     = var.default_city
      log_level        = var.log_level
      enable_debug     = var.enable_debug_mode
    })
    filename = "main.py"
  }
  
  source {
    content = templatefile("${path.module}/function_code/requirements.txt", {})
    filename = "requirements.txt"
  }
}

# Upload the function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name                = "weather-function-source-${random_string.suffix.result}.zip"
  bucket              = google_storage_bucket.function_source_bucket.name
  source              = data.archive_file.function_source.output_path
  content_disposition = "attachment"
  content_encoding    = "gzip"
  content_type        = "application/zip"

  # Regenerate when source code changes
  detect_md5hash = data.archive_file.function_source.output_md5

  depends_on = [data.archive_file.function_source]
}

# ============================================================================
# Cloud Function for Weather API
# ============================================================================

# Cloud Function (2nd generation) for weather API proxy
resource "google_cloudfunctions2_function" "weather_api" {
  name        = local.function_name
  location    = var.region
  project     = var.project_id
  description = "Serverless weather API proxy function for the weather dashboard application"

  # Build configuration
  build_config {
    runtime     = var.function_runtime
    entry_point = "get_weather"
    
    # Environment variables for build time
    environment_variables = {
      BUILD_ENV = var.environment
    }

    # Source code configuration
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }

    # Automatic security updates
    automatic_update_policy {}
  }

  # Service configuration
  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = var.function_min_instances
    available_memory                 = var.function_memory
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 10
    available_cpu                    = "1"
    
    # Runtime environment variables
    environment_variables = {
      WEATHER_API_KEY         = var.weather_api_key
      DEFAULT_CITY           = var.default_city
      LOG_LEVEL              = var.log_level
      ENVIRONMENT            = var.environment
      ENABLE_DEBUG           = tostring(var.enable_debug_mode)
      FUNCTION_TIMEOUT       = tostring(var.function_timeout)
      CORS_ORIGINS           = join(",", var.cors_origins)
    }
    
    # Security configuration
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_sa.email
  }

  # Resource labels
  labels = local.common_labels

  # Ensure APIs are enabled before deployment
  depends_on = [
    google_project_service.cloudfunctions,
    google_project_service.cloudbuild,
    google_storage_bucket_object.function_source,
    google_service_account.function_sa
  ]
}

# IAM policy to allow unauthenticated invocation (if enabled)
resource "google_cloudfunctions2_function_iam_member" "public_invoker" {
  count          = var.allow_unauthenticated_function_access ? 1 : 0
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.weather_api.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# ============================================================================
# Cloud Storage for Website Hosting
# ============================================================================

# Main storage bucket for website hosting
resource "google_storage_bucket" "website_bucket" {
  name                        = local.bucket_name
  location                    = var.bucket_location
  project                     = var.project_id
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  force_destroy               = var.force_destroy_bucket

  # Website configuration for static hosting
  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }

  # CORS configuration for browser access
  dynamic "cors" {
    for_each = var.enable_cors ? [1] : []
    content {
      origin          = var.cors_origins
      method          = var.cors_methods
      response_header = ["*"]
      max_age_seconds = 3600
    }
  }

  # Versioning configuration
  dynamic "versioning" {
    for_each = var.enable_versioning ? [1] : []
    content {
      enabled = true
    }
  }

  # Public access configuration
  public_access_prevention = var.enable_public_bucket_access ? "inherited" : "enforced"

  # Lifecycle management for website assets
  lifecycle_rule {
    condition {
      age = 90 # Clean up old versions after 90 days
    }
    action {
      type = "Delete"
    }
  }

  # Resource labels
  labels = local.common_labels

  depends_on = [google_project_service.storage]
}

# IAM policy for public bucket access (if enabled)
resource "google_storage_bucket_iam_member" "public_viewer" {
  count  = var.enable_public_bucket_access ? 1 : 0
  bucket = google_storage_bucket.website_bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# ============================================================================
# Website Content Upload
# ============================================================================

# Main dashboard HTML file
resource "google_storage_bucket_object" "index_html" {
  name         = "index.html"
  bucket       = google_storage_bucket.website_bucket.name
  content_type = "text/html"
  cache_control = "public, max-age=3600"
  
  # Generate HTML content with function URL
  content = templatefile("${path.module}/website_content/index.html", {
    function_url     = google_cloudfunctions2_function.weather_api.service_config[0].uri
    default_city     = var.default_city
    application_name = var.application_name
    environment      = var.environment
  })

  depends_on = [google_cloudfunctions2_function.weather_api]
}

# 404 error page
resource "google_storage_bucket_object" "error_html" {
  name         = "404.html"
  bucket       = google_storage_bucket.website_bucket.name
  content_type = "text/html"
  cache_control = "public, max-age=86400"
  
  content = templatefile("${path.module}/website_content/404.html", {
    application_name = var.application_name
  })
}

# ============================================================================
# Function Code Template Files
# ============================================================================

# Template for the main Python function code
resource "local_file" "function_main_py" {
  filename = "${path.module}/function_code/main.py"
  
  content = <<-EOF
"""
Weather Dashboard API Function

A Google Cloud Function that acts as a proxy to the OpenWeatherMap API,
providing CORS-enabled access to weather data for the frontend application.

Environment Variables:
- WEATHER_API_KEY: OpenWeatherMap API key
- DEFAULT_CITY: Default city for weather queries
- LOG_LEVEL: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
- ENVIRONMENT: Deployment environment (dev, staging, prod)
- ENABLE_DEBUG: Enable debug mode (true/false)
"""

import functions_framework
import requests
import json
import os
import logging
from flask import jsonify
from typing import Dict, Any, Tuple

# Configure logging
LOG_LEVEL = os.environ.get('LOG_LEVEL', '${log_level}').upper()
logging.basicConfig(level=getattr(logging, LOG_LEVEL))
logger = logging.getLogger(__name__)

# Configuration constants
DEFAULT_CITY = os.environ.get('DEFAULT_CITY', '${default_city}')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')
ENABLE_DEBUG = os.environ.get('ENABLE_DEBUG', '${enable_debug}').lower() == 'true'
TIMEOUT_SECONDS = 10

# OpenWeatherMap API configuration
WEATHER_API_BASE_URL = "https://api.openweathermap.org/data/2.5/weather"

@functions_framework.http
def get_weather(request):
    """
    HTTP Cloud Function to fetch weather data from OpenWeatherMap API.
    
    Query Parameters:
        city (str): City name for weather query (defaults to DEFAULT_CITY)
        
    Returns:
        JSON response with weather data or error message
    """
    
    # Handle CORS preflight requests
    if request.method == 'OPTIONS':
        headers = get_cors_headers()
        return ('', 204, headers)
    
    # Set CORS headers for actual request
    headers = get_cors_headers()
    
    try:
        # Extract city from query parameters
        city = request.args.get('city', DEFAULT_CITY).strip()
        
        if not city:
            logger.warning("Empty city parameter provided")
            return jsonify({'error': 'City parameter cannot be empty'}), 400, headers
        
        # Get API key from environment
        api_key = os.environ.get('WEATHER_API_KEY')
        if not api_key:
            logger.error("Weather API key not configured")
            return jsonify({'error': 'Weather API key not configured'}), 500, headers
        
        # Log request details (in debug mode)
        if ENABLE_DEBUG:
            logger.info(f"Weather request for city: {city}, environment: {ENVIRONMENT}")
        
        # Make request to OpenWeatherMap API
        weather_data = fetch_weather_data(city, api_key)
        
        if weather_data:
            # Transform and return weather data
            simplified_data = transform_weather_data(weather_data, city)
            logger.info(f"Successfully retrieved weather data for {city}")
            return jsonify(simplified_data), 200, headers
        else:
            logger.warning(f"Weather data not found for city: {city}")
            return jsonify({'error': f'Weather data not found for city: {city}'}), 404, headers
            
    except requests.exceptions.Timeout:
        logger.error(f"Timeout while fetching weather data for {city}")
        return jsonify({'error': 'Weather service temporarily unavailable'}), 503, headers
    except requests.exceptions.RequestException as e:
        logger.error(f"Network error while fetching weather data: {str(e)}")
        return jsonify({'error': 'Unable to fetch weather data'}), 503, headers
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        error_message = str(e) if ENABLE_DEBUG else 'Internal server error'
        return jsonify({'error': error_message}), 500, headers

def get_cors_headers() -> Dict[str, str]:
    """
    Generate CORS headers for cross-origin requests.
    
    Returns:
        Dictionary of CORS headers
    """
    cors_origins = os.environ.get('CORS_ORIGINS', '*')
    
    return {
        'Access-Control-Allow-Origin': cors_origins,
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Max-Age': '3600',
        'Content-Type': 'application/json'
    }

def fetch_weather_data(city: str, api_key: str) -> Dict[str, Any]:
    """
    Fetch weather data from OpenWeatherMap API.
    
    Args:
        city: City name for weather query
        api_key: OpenWeatherMap API key
        
    Returns:
        Weather data dictionary or None if request fails
    """
    try:
        # Construct API URL with parameters
        params = {
            'q': city,
            'appid': api_key,
            'units': 'imperial',  # Fahrenheit, mph, etc.
            'mode': 'json'
        }
        
        # Make API request with timeout
        response = requests.get(
            WEATHER_API_BASE_URL,
            params=params,
            timeout=TIMEOUT_SECONDS,
            headers={'User-Agent': f'WeatherDashboard/{ENVIRONMENT}'}
        )
        
        # Check response status
        if response.status_code == 200:
            return response.json()
        elif response.status_code == 404:
            logger.warning(f"City not found: {city}")
            return None
        else:
            logger.error(f"API error {response.status_code}: {response.text}")
            return None
            
    except requests.exceptions.RequestException as e:
        logger.error(f"Request failed for city {city}: {str(e)}")
        raise

def transform_weather_data(weather_data: Dict[str, Any], city: str) -> Dict[str, Any]:
    """
    Transform OpenWeatherMap API response into simplified format for frontend.
    
    Args:
        weather_data: Raw weather data from API
        city: Requested city name
        
    Returns:
        Simplified weather data dictionary
    """
    try:
        # Extract relevant data with safe defaults
        main_data = weather_data.get('main', {})
        weather_info = weather_data.get('weather', [{}])[0]
        wind_data = weather_data.get('wind', {})
        sys_data = weather_data.get('sys', {})
        
        transformed_data = {
            'city': weather_data.get('name', city),
            'country': sys_data.get('country', 'Unknown'),
            'temperature': round(main_data.get('temp', 0)),
            'feels_like': round(main_data.get('feels_like', 0)),
            'description': weather_info.get('description', 'Unknown').title(),
            'humidity': main_data.get('humidity', 0),
            'pressure': main_data.get('pressure', 0),
            'wind_speed': wind_data.get('speed', 0),
            'wind_direction': wind_data.get('deg', 0),
            'visibility': weather_data.get('visibility', 0) // 1000,  # Convert to km
            'icon': weather_info.get('icon', '01d'),
            'sunrise': sys_data.get('sunrise', 0),
            'sunset': sys_data.get('sunset', 0),
            'timestamp': weather_data.get('dt', 0),
            'timezone': weather_data.get('timezone', 0),
            'coordinates': {
                'lat': weather_data.get('coord', {}).get('lat', 0),
                'lon': weather_data.get('coord', {}).get('lon', 0)
            }
        }
        
        # Add debug information if enabled
        if ENABLE_DEBUG:
            transformed_data['_debug'] = {
                'environment': ENVIRONMENT,
                'api_response_keys': list(weather_data.keys()),
                'processing_time': 'calculated_by_frontend'
            }
        
        return transformed_data
        
    except Exception as e:
        logger.error(f"Error transforming weather data: {str(e)}")
        raise ValueError(f"Failed to process weather data: {str(e)}")

# Health check endpoint for monitoring
@functions_framework.http
def health_check(request):
    """Simple health check endpoint."""
    if request.path == '/health':
        return jsonify({
            'status': 'healthy',
            'environment': ENVIRONMENT,
            'version': '1.0.0'
        }), 200, get_cors_headers()
    
    # Default to weather endpoint
    return get_weather(request)
EOF
}

# Template for function requirements
resource "local_file" "function_requirements" {
  filename = "${path.module}/function_code/requirements.txt"
  
  content = <<-EOF
# Python dependencies for Weather Dashboard Cloud Function
# These packages provide HTTP handling, API requests, and Google Cloud integration

# Google Cloud Functions framework for HTTP triggers
functions-framework==3.*

# HTTP requests library for calling external APIs
requests==2.*

# Flask web framework (included with functions-framework but specified for clarity)
flask==2.*

# Additional packages for enhanced functionality
google-cloud-logging==3.*  # Structured logging integration
google-cloud-error-reporting==1.*  # Error tracking and reporting
EOF
}

# ============================================================================
# Website Content Template Files
# ============================================================================

# Template for the main HTML dashboard
resource "local_file" "website_index_html" {
  filename = "${path.module}/website_content/index.html"
  
  content = <<-EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="Real-time weather dashboard powered by Google Cloud">
    <meta name="keywords" content="weather, dashboard, cloud, serverless">
    <title>${application_name} - Weather Dashboard</title>
    
    <!-- Preconnect to external domains for performance -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link rel="preconnect" href="https://openweathermap.org">
    
    <style>
        /* CSS Variables for theming */
        :root {
            --primary-color: #74b9ff;
            --primary-dark: #0984e3;
            --secondary-color: #00b894;
            --error-color: #ff6b6b;
            --warning-color: #fdcb6e;
            --text-primary: #2d3436;
            --text-secondary: #636e72;
            --background-gradient: linear-gradient(135deg, var(--primary-color), var(--primary-dark));
            --card-background: rgba(255, 255, 255, 0.9);
            --border-radius: 20px;
            --box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
            --transition: all 0.3s ease;
        }
        
        /* Reset and base styles */
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Inter', 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: var(--background-gradient);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            line-height: 1.6;
            color: var(--text-primary);
        }
        
        /* Main dashboard container */
        .dashboard {
            background: var(--card-background);
            border-radius: var(--border-radius);
            padding: 2rem;
            box-shadow: var(--box-shadow);
            backdrop-filter: blur(10px);
            max-width: 600px;
            width: 90%;
            transition: var(--transition);
        }
        
        .dashboard:hover {
            transform: translateY(-5px);
            box-shadow: 0 12px 40px rgba(0, 0, 0, 0.15);
        }
        
        /* Header section */
        .header {
            text-align: center;
            margin-bottom: 2rem;
        }
        
        .header h1 {
            color: var(--text-primary);
            margin-bottom: 0.5rem;
            font-size: 2.5rem;
            font-weight: 700;
        }
        
        .header .subtitle {
            color: var(--text-secondary);
            font-size: 1rem;
            font-weight: 400;
        }
        
        /* Search box styles */
        .search-box {
            display: flex;
            margin-bottom: 2rem;
            gap: 0;
        }
        
        .search-box input {
            flex: 1;
            padding: 16px 20px;
            border: 2px solid #e9ecef;
            border-radius: 15px 0 0 15px;
            font-size: 16px;
            outline: none;
            transition: var(--transition);
            background: white;
        }
        
        .search-box input:focus {
            border-color: var(--primary-color);
            box-shadow: 0 0 0 3px rgba(116, 185, 255, 0.1);
        }
        
        .search-box button {
            padding: 16px 24px;
            background: var(--primary-dark);
            color: white;
            border: none;
            border-radius: 0 15px 15px 0;
            cursor: pointer;
            font-size: 16px;
            font-weight: 600;
            transition: var(--transition);
        }
        
        .search-box button:hover {
            background: #0663c7;
            transform: translateY(-1px);
        }
        
        .search-box button:active {
            transform: translateY(0);
        }
        
        /* Loading state */
        .loading {
            text-align: center;
            padding: 3rem 2rem;
            display: none;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        .loading-spinner {
            width: 40px;
            height: 40px;
            border: 4px solid #e3f2fd;
            border-top: 4px solid var(--primary-color);
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin: 0 auto 1rem;
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        
        /* Error styles */
        .error {
            background: var(--error-color);
            color: white;
            padding: 1rem 1.5rem;
            border-radius: 10px;
            margin: 1rem 0;
            display: none;
            animation: slideIn 0.3s ease;
        }
        
        @keyframes slideIn {
            from { transform: translateY(-10px); opacity: 0; }
            to { transform: translateY(0); opacity: 1; }
        }
        
        /* Weather info container */
        .weather-info {
            text-align: center;
            display: none;
            animation: fadeIn 0.5s ease;
        }
        
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        
        /* Temperature display */
        .temperature {
            font-size: 4.5rem;
            font-weight: 700;
            color: var(--text-primary);
            margin: 1rem 0;
            text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.1);
        }
        
        .feels-like {
            font-size: 1.1rem;
            color: var(--text-secondary);
            margin-bottom: 1rem;
        }
        
        /* Weather description */
        .description {
            font-size: 1.5rem;
            color: var(--text-secondary);
            margin-bottom: 1rem;
            font-weight: 500;
        }
        
        .city-info {
            font-size: 1.2rem;
            color: var(--text-primary);
            margin-bottom: 2rem;
            font-weight: 600;
        }
        
        /* Weather details grid */
        .details {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
            gap: 1rem;
            margin-top: 2rem;
        }
        
        .detail-item {
            background: rgba(116, 185, 255, 0.1);
            padding: 1.5rem 1rem;
            border-radius: 15px;
            text-align: center;
            transition: var(--transition);
            border: 1px solid rgba(116, 185, 255, 0.2);
        }
        
        .detail-item:hover {
            background: rgba(116, 185, 255, 0.15);
            transform: translateY(-2px);
        }
        
        .detail-label {
            font-size: 0.9rem;
            color: var(--text-secondary);
            margin-bottom: 0.5rem;
            font-weight: 500;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .detail-value {
            font-size: 1.3rem;
            font-weight: 700;
            color: var(--text-primary);
        }
        
        /* Footer info */
        .footer {
            text-align: center;
            margin-top: 2rem;
            padding-top: 1rem;
            border-top: 1px solid rgba(116, 185, 255, 0.2);
            color: var(--text-secondary);
            font-size: 0.9rem;
        }
        
        /* Responsive design */
        @media (max-width: 768px) {
            .dashboard {
                margin: 1rem;
                padding: 1.5rem;
            }
            
            .header h1 {
                font-size: 2rem;
            }
            
            .temperature {
                font-size: 3.5rem;
            }
            
            .details {
                grid-template-columns: repeat(2, 1fr);
            }
        }
        
        /* Accessibility improvements */
        .sr-only {
            position: absolute;
            width: 1px;
            height: 1px;
            padding: 0;
            margin: -1px;
            overflow: hidden;
            clip: rect(0, 0, 0, 0);
            white-space: nowrap;
            border: 0;
        }
        
        button:focus,
        input:focus {
            outline: 2px solid var(--primary-color);
            outline-offset: 2px;
        }
    </style>
</head>
<body>
    <div class="dashboard" role="main">
        <header class="header">
            <h1>🌤️ ${application_name}</h1>
            <p class="subtitle">Real-time weather information powered by Google Cloud</p>
        </header>
        
        <div class="search-box" role="search">
            <label for="cityInput" class="sr-only">Enter city name</label>
            <input 
                type="text" 
                id="cityInput" 
                placeholder="Enter city name..." 
                value="${default_city}"
                autocomplete="off"
                aria-describedby="search-help"
            >
            <button onclick="getWeather()" type="button">
                Get Weather
            </button>
        </div>
        
        <div id="search-help" class="sr-only">
            Enter a city name and press the Get Weather button or press Enter to fetch current weather information.
        </div>
        
        <div class="loading" id="loading" role="status" aria-live="polite">
            <div class="loading-spinner" aria-hidden="true"></div>
            <p>Loading weather data...</p>
        </div>
        
        <div class="error" id="error" role="alert" aria-live="assertive"></div>
        
        <div class="weather-info" id="weatherInfo" role="region" aria-label="Weather information">
            <div class="temperature" id="temperature" aria-label="Current temperature"></div>
            <div class="feels-like" id="feelsLike" aria-label="Feels like temperature"></div>
            <div class="description" id="description" aria-label="Weather description"></div>
            <div class="city-info" id="cityName" aria-label="City and country"></div>
            
            <div class="details" role="grid">
                <div class="detail-item" role="gridcell">
                    <div class="detail-label">Humidity</div>
                    <div class="detail-value" id="humidity" aria-label="Humidity percentage"></div>
                </div>
                <div class="detail-item" role="gridcell">
                    <div class="detail-label">Pressure</div>
                    <div class="detail-value" id="pressure" aria-label="Atmospheric pressure"></div>
                </div>
                <div class="detail-item" role="gridcell">
                    <div class="detail-label">Wind Speed</div>
                    <div class="detail-value" id="windSpeed" aria-label="Wind speed"></div>
                </div>
                <div class="detail-item" role="gridcell">
                    <div class="detail-label">Visibility</div>
                    <div class="detail-value" id="visibility" aria-label="Visibility distance"></div>
                </div>
                <div class="detail-item" role="gridcell">
                    <div class="detail-label">Last Updated</div>
                    <div class="detail-value" id="timestamp" aria-label="Last update time"></div>
                </div>
            </div>
        </div>
        
        <footer class="footer">
            <p>Environment: ${environment} | Powered by OpenWeatherMap API</p>
        </footer>
    </div>

    <script>
        // Configuration
        const CONFIG = {
            FUNCTION_URL: '${function_url}',
            DEFAULT_CITY: '${default_city}',
            ENVIRONMENT: '${environment}',
            REQUEST_TIMEOUT: 30000,
            RETRY_ATTEMPTS: 2,
            RETRY_DELAY: 1000
        };
        
        // DOM elements
        const elements = {
            cityInput: document.getElementById('cityInput'),
            loading: document.getElementById('loading'),
            error: document.getElementById('error'),
            weatherInfo: document.getElementById('weatherInfo'),
            temperature: document.getElementById('temperature'),
            feelsLike: document.getElementById('feelsLike'),
            description: document.getElementById('description'),
            cityName: document.getElementById('cityName'),
            humidity: document.getElementById('humidity'),
            pressure: document.getElementById('pressure'),
            windSpeed: document.getElementById('windSpeed'),
            visibility: document.getElementById('visibility'),
            timestamp: document.getElementById('timestamp')
        };
        
        /**
         * Main function to fetch and display weather data
         */
        async function getWeather() {
            const city = elements.cityInput.value.trim();
            
            if (!city) {
                showError('Please enter a city name');
                return;
            }
            
            // Show loading state
            showLoading(true);
            hideError();
            hideWeatherInfo();
            
            try {
                const weatherData = await fetchWeatherWithRetry(city);
                displayWeather(weatherData);
                
                // Update URL without page reload for better UX
                updateURLState(city);
                
            } catch (error) {
                console.error('Weather fetch error:', error);
                handleWeatherError(error);
            } finally {
                showLoading(false);
            }
        }
        
        /**
         * Fetch weather data with retry logic
         */
        async function fetchWeatherWithRetry(city, attempt = 1) {
            try {
                const controller = new AbortController();
                const timeoutId = setTimeout(() => controller.abort(), CONFIG.REQUEST_TIMEOUT);
                
                const url = `$${CONFIG.FUNCTION_URL}?city=$${encodeURIComponent(city)}`;
                const response = await fetch(url, {
                    method: 'GET',
                    headers: {
                        'Accept': 'application/json',
                        'Content-Type': 'application/json'
                    },
                    signal: controller.signal
                });
                
                clearTimeout(timeoutId);
                
                if (!response.ok) {
                    const errorData = await response.json().catch(() => ({}));
                    throw new Error(errorData.error || `HTTP $${response.status}: $${response.statusText}`);
                }
                
                return await response.json();
                
            } catch (error) {
                if (attempt < CONFIG.RETRY_ATTEMPTS && !error.name === 'AbortError') {
                    console.warn(`Attempt $${attempt} failed, retrying...`, error);
                    await new Promise(resolve => setTimeout(resolve, CONFIG.RETRY_DELAY * attempt));
                    return fetchWeatherWithRetry(city, attempt + 1);
                }
                throw error;
            }
        }
        
        /**
         * Display weather data in the UI
         */
        function displayWeather(data) {
            // Validate data structure
            if (!data || typeof data !== 'object') {
                throw new Error('Invalid weather data received');
            }
            
            // Update temperature display
            elements.temperature.textContent = `$${data.temperature || 0}°F`;
            elements.feelsLike.textContent = `Feels like $${data.feels_like || data.temperature || 0}°F`;
            elements.description.textContent = data.description || 'Unknown';
            elements.cityName.textContent = `$${data.city || 'Unknown'}, $${data.country || 'Unknown'}`;
            
            // Update detail values
            elements.humidity.textContent = `$${data.humidity || 0}%`;
            elements.pressure.textContent = `$${data.pressure || 0} hPa`;
            elements.windSpeed.textContent = `$${data.wind_speed || 0} mph`;
            elements.visibility.textContent = `$${data.visibility || 0} km`;
            elements.timestamp.textContent = new Date().toLocaleTimeString();
            
            // Show weather info
            showWeatherInfo();
            
            // Log successful fetch in debug mode
            if (CONFIG.ENVIRONMENT === 'dev' && data._debug) {
                console.log('Weather data debug info:', data._debug);
            }
        }
        
        /**
         * Handle different types of weather fetch errors
         */
        function handleWeatherError(error) {
            let errorMessage;
            
            if (error.name === 'AbortError') {
                errorMessage = 'Request timeout - please try again';
            } else if (error.message.includes('404') || error.message.includes('not found')) {
                errorMessage = 'City not found - please check the spelling';
            } else if (error.message.includes('403') || error.message.includes('401')) {
                errorMessage = 'Weather service temporarily unavailable';
            } else if (error.message.includes('network') || error.message.includes('fetch')) {
                errorMessage = 'Network error - please check your connection';
            } else {
                errorMessage = error.message || 'Unable to fetch weather data';
            }
            
            showError(errorMessage);
        }
        
        /**
         * UI state management functions
         */
        function showLoading(show) {
            elements.loading.style.display = show ? 'block' : 'none';
        }
        
        function showError(message) {
            elements.error.textContent = message;
            elements.error.style.display = 'block';
            elements.error.setAttribute('aria-live', 'assertive');
        }
        
        function hideError() {
            elements.error.style.display = 'none';
        }
        
        function showWeatherInfo() {
            elements.weatherInfo.style.display = 'block';
        }
        
        function hideWeatherInfo() {
            elements.weatherInfo.style.display = 'none';
        }
        
        /**
         * Update URL state for better UX and bookmarking
         */
        function updateURLState(city) {
            if (history.pushState) {
                const url = new URL(window.location);
                url.searchParams.set('city', city);
                history.replaceState({city}, `Weather for $${city}`, url.toString());
            }
        }
        
        /**
         * Initialize the application
         */
        function initializeApp() {
            // Load city from URL parameters if present
            const urlParams = new URLSearchParams(window.location.search);
            const cityParam = urlParams.get('city');
            
            if (cityParam) {
                elements.cityInput.value = cityParam;
            }
            
            // Set up event listeners
            elements.cityInput.addEventListener('keypress', function(event) {
                if (event.key === 'Enter') {
                    event.preventDefault();
                    getWeather();
                }
            });
            
            // Load default weather on page load
            getWeather();
            
            // Add error handling for global errors
            window.addEventListener('error', function(event) {
                console.error('Global error:', event.error);
                if (CONFIG.ENVIRONMENT === 'dev') {
                    showError(`Application error: $${event.error.message}`);
                }
            });
            
            // Service worker registration for PWA capabilities (future enhancement)
            if ('serviceWorker' in navigator && CONFIG.ENVIRONMENT === 'prod') {
                navigator.serviceWorker.register('/sw.js').catch(console.warn);
            }
        }
        
        // Initialize the application when DOM is ready
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', initializeApp);
        } else {
            initializeApp();
        }
        
        // Export functions for testing in development
        if (CONFIG.ENVIRONMENT === 'dev') {
            window.weatherApp = {
                getWeather,
                fetchWeatherWithRetry,
                displayWeather,
                CONFIG,
                elements
            };
        }
    </script>
</body>
</html>
EOF
}

# Template for 404 error page
resource "local_file" "website_404_html" {
  filename = "${path.module}/website_content/404.html"
  
  content = <<-EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found - ${application_name}</title>
    <style>
        :root {
            --primary-color: #74b9ff;
            --primary-dark: #0984e3;
            --error-color: #ff6b6b;
            --text-primary: #2d3436;
            --text-secondary: #636e72;
            --background-gradient: linear-gradient(135deg, var(--primary-color), var(--primary-dark));
            --card-background: rgba(255, 255, 255, 0.9);
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: var(--background-gradient);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            line-height: 1.6;
        }
        
        .error-container {
            background: var(--card-background);
            border-radius: 20px;
            padding: 3rem 2rem;
            text-align: center;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
            backdrop-filter: blur(10px);
            max-width: 500px;
            width: 90%;
        }
        
        .error-code {
            font-size: 8rem;
            font-weight: 700;
            color: var(--error-color);
            margin-bottom: 1rem;
            text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.1);
        }
        
        .error-title {
            font-size: 2rem;
            color: var(--text-primary);
            margin-bottom: 1rem;
            font-weight: 600;
        }
        
        .error-message {
            font-size: 1.2rem;
            color: var(--text-secondary);
            margin-bottom: 2rem;
            line-height: 1.6;
        }
        
        .back-button {
            background: var(--primary-dark);
            color: white;
            padding: 16px 32px;
            border: none;
            border-radius: 15px;
            font-size: 1.1rem;
            font-weight: 600;
            cursor: pointer;
            text-decoration: none;
            display: inline-block;
            transition: all 0.3s ease;
        }
        
        .back-button:hover {
            background: #0663c7;
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(6, 99, 199, 0.3);
        }
        
        .back-button:active {
            transform: translateY(0);
        }
        
        @media (max-width: 768px) {
            .error-container {
                padding: 2rem 1.5rem;
            }
            
            .error-code {
                font-size: 6rem;
            }
            
            .error-title {
                font-size: 1.5rem;
            }
            
            .error-message {
                font-size: 1rem;
            }
        }
    </style>
</head>
<body>
    <div class="error-container">
        <div class="error-code">404</div>
        <h1 class="error-title">Oops! Page Not Found</h1>
        <p class="error-message">
            The weather page you're looking for seems to have drifted away like a cloud. 
            Let's get you back to tracking the weather!
        </p>
        <a href="/" class="back-button">Return to Weather Dashboard</a>
    </div>
</body>
</html>
EOF
}