# Age Calculator API with Cloud Run and Storage - Main Infrastructure
# This file contains the primary infrastructure resources for the serverless API

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed names and configurations
locals {
  bucket_name           = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  service_account_email = "${var.service_account_name}@${var.project_id}.iam.gserviceaccount.com"
  
  # Lifecycle rules configuration
  lifecycle_rules = var.lifecycle_rules ? [
    {
      condition = {
        age = 30
      }
      action = {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    },
    {
      condition = {
        age = 90
      }
      action = {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
    }
  ] : []
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "run.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com"
  ]) : toset([])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying resources
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Wait for APIs to be fully enabled before creating resources
resource "time_sleep" "wait_for_apis" {
  count = var.enable_apis ? 1 : 0
  
  depends_on = [google_project_service.required_apis]
  
  create_duration = "30s"
}

# Create service account for Cloud Run service
resource "google_service_account" "cloud_run_sa" {
  account_id   = var.service_account_name
  display_name = "Service Account for Age Calculator API"
  description  = "Service account used by Cloud Run service for accessing Cloud Storage"
  project      = var.project_id
  
  depends_on = [time_sleep.wait_for_apis]
}

# Cloud Storage bucket for request logging
resource "google_storage_bucket" "request_logs" {
  name                        = local.bucket_name
  location                    = var.region
  project                     = var.project_id
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = local.lifecycle_rules
    content {
      condition {
        age = lifecycle_rule.value.condition.age
      }
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lifecycle_rule.value.action.storage_class
      }
    }
  }
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false
  }
  
  labels = merge(var.labels, {
    purpose = "request-logging"
    service = "age-calculator-api"
  })
  
  depends_on = [time_sleep.wait_for_apis]
}

# IAM binding for service account to access Cloud Storage bucket
resource "google_storage_bucket_iam_member" "cloud_run_storage_access" {
  bucket = google_storage_bucket.request_logs.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cloud_run_sa.email}"
  
  depends_on = [google_storage_bucket.request_logs]
}

# Cloud Run service for the Age Calculator API
resource "google_cloud_run_service" "age_calculator_api" {
  name     = var.service_name
  location = var.region
  project  = var.project_id
  
  template {
    spec {
      # Use custom service account
      service_account_name = google_service_account.cloud_run_sa.email
      
      # Configure container specifications
      containers {
        # Use provided image or default placeholder
        image = var.container_image != "" ? var.container_image : "gcr.io/cloudrun/hello"
        
        # Resource limits
        resources {
          limits = {
            cpu    = var.cpu
            memory = var.memory
          }
        }
        
        # Environment variables
        env {
          name  = "BUCKET_NAME"
          value = google_storage_bucket.request_logs.name
        }
        
        env {
          name  = "GOOGLE_CLOUD_PROJECT"
          value = var.project_id
        }
        
        env {
          name  = "GOOGLE_CLOUD_REGION"
          value = var.region
        }
        
        # Container port
        ports {
          container_port = 8080
        }
      }
      
      # Scaling configuration
      container_concurrency = var.concurrency
      timeout_seconds       = var.timeout_seconds
    }
    
    # Template metadata
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = tostring(var.max_instances)
        "autoscaling.knative.dev/minScale" = "0"
        "run.googleapis.com/execution-environment" = "gen2"
        # Enable CPU allocation only during request processing
        "run.googleapis.com/cpu-throttling" = "true"
      }
      
      labels = merge(var.labels, {
        service = "age-calculator-api"
        version = "v1"
      })
    }
  }
  
  # Service metadata
  metadata {
    labels = merge(var.labels, {
      service = "age-calculator-api"
    })
    
    annotations = {
      "run.googleapis.com/ingress" = "all"
    }
  }
  
  # Ensure APIs are enabled and service account exists
  depends_on = [
    time_sleep.wait_for_apis,
    google_service_account.cloud_run_sa,
    google_storage_bucket_iam_member.cloud_run_storage_access
  ]
  
  # Manage traffic allocation
  traffic {
    percent         = 100
    latest_revision = true
  }
}

# IAM policy to allow public access (if enabled)
resource "google_cloud_run_service_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0
  
  service  = google_cloud_run_service.age_calculator_api.name
  location = google_cloud_run_service.age_calculator_api.location
  project  = var.project_id
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Optional: Create a custom domain mapping (commented out by default)
# Uncomment and configure if you have a custom domain
/*
resource "google_cloud_run_domain_mapping" "custom_domain" {
  location = var.region
  name     = "api.yourdomain.com"
  project  = var.project_id

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_service.age_calculator_api.name
  }
}
*/

# Create a sample application source (commented out - for reference)
# This shows how you could include the application code deployment
/*
resource "google_storage_bucket_object" "app_source" {
  name   = "app-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.request_logs.name
  
  # In a real scenario, you would upload your application source code
  content = "# Application source code would go here"
  
  content_type = "application/zip"
}
*/