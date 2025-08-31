# Main Terraform configuration for QR Code Generator with Cloud Run and Storage
# This file defines all the infrastructure resources needed for the QR code generation service

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed configurations
locals {
  bucket_name = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  
  # Default container image if not provided
  default_image = "gcr.io/cloudrun/hello"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    service = var.service_name
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = var.enable_apis ? toset([
    "run.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ]) : toset([])

  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create Cloud Storage bucket for QR code images
resource "google_storage_bucket" "qr_codes" {
  name     = local.bucket_name
  location = var.region
  
  # Storage configuration
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  
  # Prevent accidental deletion
  force_destroy = false
  
  # Versioning configuration
  versioning {
    enabled = false
  }
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
  
  # CORS configuration for web access
  cors {
    origin          = ["*"]
    method          = ["GET"]
    response_header = ["Content-Type"]
    max_age_seconds = 3600
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Make the bucket publicly readable for QR code images
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.qr_codes.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Create a service account for the Cloud Run service
resource "google_service_account" "cloudrun_sa" {
  account_id   = "${var.service_name}-sa"
  display_name = "Cloud Run Service Account for ${var.service_name}"
  description  = "Service account used by the QR Code Generator Cloud Run service"
}

# Grant the service account permission to manage objects in the bucket
resource "google_storage_bucket_iam_member" "cloudrun_storage_admin" {
  bucket = google_storage_bucket.qr_codes.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cloudrun_sa.email}"
}

# Deploy the Cloud Run service
resource "google_cloud_run_service" "qr_code_api" {
  name     = var.service_name
  location = var.region
  
  template {
    metadata {
      labels = local.common_labels
      annotations = {
        "autoscaling.knative.dev/maxScale" = tostring(var.max_instances)
        "autoscaling.knative.dev/minScale" = "0"
        "run.googleapis.com/cpu-throttling" = "true"
        "run.googleapis.com/execution-environment" = "gen2"
      }
    }
    
    spec {
      # Service account configuration
      service_account_name = google_service_account.cloudrun_sa.email
      
      # Container configuration
      containers {
        # Use provided image or default placeholder
        image = var.container_image != "" ? var.container_image : local.default_image
        
        # Resource limits
        resources {
          limits = {
            memory = var.service_memory
            cpu    = var.service_cpu
          }
        }
        
        # Environment variables
        env {
          name  = "BUCKET_NAME"
          value = google_storage_bucket.qr_codes.name
        }
        
        env {
          name  = "GCP_PROJECT"
          value = var.project_id
        }
        
        env {
          name  = "GCP_REGION"
          value = var.region
        }
        
        # Health check port
        ports {
          container_port = 8080
        }
        
        # Startup probe for better cold start handling
        startup_probe {
          http_get {
            path = "/"
            port = 8080
          }
          initial_delay_seconds = 0
          timeout_seconds       = 1
          period_seconds        = 3
          failure_threshold     = 1
        }
        
        # Liveness probe
        liveness_probe {
          http_get {
            path = "/"
            port = 8080
          }
          initial_delay_seconds = 0
          timeout_seconds       = 1
          period_seconds        = 10
          failure_threshold     = 3
        }
      }
      
      # Concurrency settings
      container_concurrency = var.concurrency
      
      # Timeout settings
      timeout_seconds = 300
    }
  }
  
  traffic {
    percent         = 100
    latest_revision = true
  }
  
  # Prevent deletion protection
  lifecycle {
    ignore_changes = [
      # Ignore changes to the image tag for CI/CD deployments
      template[0].spec[0].containers[0].image,
    ]
  }
  
  depends_on = [
    google_project_service.apis,
    google_service_account.cloudrun_sa,
    google_storage_bucket.qr_codes
  ]
}

# Configure IAM policy for public access (if enabled)
resource "google_cloud_run_service_iam_member" "public_access" {
  count = var.allow_public_access ? 1 : 0
  
  service  = google_cloud_run_service.qr_code_api.name
  location = google_cloud_run_service.qr_code_api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Data source to get the current project information
data "google_project" "current" {}

# Data source to get the default compute service account
data "google_compute_default_service_account" "default" {}

# Output values that might be useful for other configurations or verification