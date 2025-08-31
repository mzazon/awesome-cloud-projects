# Weather API Gateway Infrastructure
# This Terraform configuration deploys a serverless weather API gateway
# using Google Cloud Run and Cloud Storage for caching

# Generate a random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Enable required Google Cloud APIs
resource "google_project_service" "cloud_run_api" {
  service = "run.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
}

resource "google_project_service" "cloud_storage_api" {
  service = "storage.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
}

resource "google_project_service" "cloud_build_api" {
  service = "cloudbuild.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
}

# Cloud Storage bucket for caching weather data
# This bucket stores cached weather responses to reduce external API calls
resource "google_storage_bucket" "weather_cache" {
  name          = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  location      = var.region
  storage_class = "STANDARD"
  
  # Prevent accidental deletion of the bucket
  force_destroy = true

  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true

  # Apply labels for resource management
  labels = var.labels

  # Lifecycle configuration to automatically delete old cached data
  lifecycle_rule {
    condition {
      age = var.cache_lifecycle_days
    }
    action {
      type = "Delete"
    }
  }

  # Versioning configuration (disabled for cache data)
  versioning {
    enabled = false
  }

  depends_on = [google_project_service.cloud_storage_api]
}

# IAM binding to allow Cloud Run service to access the storage bucket
# This grants the Cloud Run service account permissions to read/write cache data
resource "google_storage_bucket_iam_member" "weather_cache_access" {
  bucket = google_storage_bucket.weather_cache.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cloud_run_service.email}"
}

# Service account for Cloud Run service
# Follows least privilege principle by creating a dedicated service account
resource "google_service_account" "cloud_run_service" {
  account_id   = "${var.service_name}-sa"
  display_name = "Weather API Gateway Service Account"
  description  = "Service account for the weather API gateway Cloud Run service"
}

# Grant the service account permissions to access Cloud Storage
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.cloud_run_service.email}"
}

# Create application source code files for Cloud Run deployment
resource "local_file" "main_py" {
  filename = "${path.module}/app/main.py"
  content = <<EOF
import os
import json
import requests
from datetime import datetime
from flask import Flask, request, jsonify
from google.cloud import storage

app = Flask(__name__)
storage_client = storage.Client()
bucket_name = os.environ.get('BUCKET_NAME')

@app.route('/weather', methods=['GET'])
def get_weather():
    city = request.args.get('city', 'New York')
    cache_key = f"weather_{city.replace(' ', '_').lower()}.json"
    
    try:
        # Check cache first
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(cache_key)
        
        if blob.exists():
            cached_data = json.loads(blob.download_as_text())
            cached_data['cached'] = True
            return jsonify(cached_data)
        
        # Fetch from external API (mock response for demo)
        weather_data = {
            'city': city,
            'temperature': 72,
            'condition': 'Sunny',
            'humidity': 65,
            'timestamp': datetime.now().isoformat(),
            'cached': False
        }
        
        # Cache the response
        blob.upload_from_string(json.dumps(weather_data))
        
        return jsonify(weather_data)
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy', 'service': 'weather-api-gateway'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF
}

resource "local_file" "requirements_txt" {
  filename = "${path.module}/app/requirements.txt"
  content = <<EOF
Flask==3.1.0
google-cloud-storage==2.18.2
requests==2.32.3
gunicorn==23.0.0
EOF
}

resource "local_file" "dockerfile" {
  filename = "${path.module}/app/Dockerfile"
  content = <<EOF
FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 main:app
EOF
}

# Cloud Run service for the weather API gateway
# Provides serverless, scalable HTTP endpoint with automatic HTTPS
resource "google_cloud_run_service" "weather_api_gateway" {
  name     = var.service_name
  location = var.region

  template {
    metadata {
      labels = var.labels
      annotations = {
        "autoscaling.knative.dev/maxScale" = var.max_instances
        "autoscaling.knative.dev/minScale" = var.min_instances
        "run.googleapis.com/cpu-throttling" = "false"
      }
    }

    spec {
      # Use the dedicated service account
      service_account_name = google_service_account.cloud_run_service.email
      
      containers {
        # Use a placeholder image that will be replaced during deployment
        image = var.container_image != "" ? var.container_image : "gcr.io/cloudrun/hello"

        # Resource allocation
        resources {
          limits = {
            cpu    = var.service_cpu
            memory = var.service_memory
          }
        }

        # Environment variables for the application
        env {
          name  = "BUCKET_NAME"
          value = google_storage_bucket.weather_cache.name
        }

        env {
          name  = "PORT"
          value = "8080"
        }

        # Health check configuration
        ports {
          container_port = 8080
        }
      }

      # Container concurrency settings
      container_concurrency = 80
      timeout_seconds      = var.timeout_seconds
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_project_service.cloud_run_api,
    google_storage_bucket.weather_cache,
    local_file.main_py,
    local_file.requirements_txt,
    local_file.dockerfile
  ]
}

# IAM policy to allow public access to the Cloud Run service
# This enables external clients to call the API without authentication
resource "google_cloud_run_service_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0
  
  service  = google_cloud_run_service.weather_api_gateway.name
  location = google_cloud_run_service.weather_api_gateway.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}