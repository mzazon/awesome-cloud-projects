# Personalized Recommendation APIs with Vertex AI and Cloud Run - Main Configuration
# This Terraform configuration creates a complete ML recommendation system using:
# - Cloud Storage for data and model artifacts
# - BigQuery for user interaction analytics
# - Vertex AI for ML model training and serving
# - Cloud Run for scalable API endpoints
# - Service accounts and IAM for secure access

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent naming and configuration
locals {
  # Resource naming convention
  resource_prefix = "${var.environment}-ml-rec"
  
  # Common labels for all resources
  common_labels = {
    environment = var.environment
    project     = "ml-recommendation-system"
    team        = "ml-engineering"
    managed_by  = "terraform"
  }
  
  # Service account names
  ml_api_sa_name     = "${local.resource_prefix}-api-sa"
  ml_vertex_sa_name  = "${local.resource_prefix}-vertex-sa"
  cloudbuild_sa_name = "${local.resource_prefix}-build-sa"
  
  # Storage bucket names (must be globally unique)
  training_data_bucket = "${local.resource_prefix}-training-data-${random_id.suffix.hex}"
  model_artifacts_bucket = "${local.resource_prefix}-models-${random_id.suffix.hex}"
  
  # BigQuery dataset and table names
  dataset_id = replace("${local.resource_prefix}_user_interactions", "-", "_")
  
  # Vertex AI resources
  model_name = "${local.resource_prefix}-model"
  endpoint_name = "${local.resource_prefix}-endpoint"
  
  # Cloud Run service name
  api_service_name = "${local.resource_prefix}-api"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "aiplatform.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "cloudbuild.googleapis.com",
    "containerregistry.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])
  
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
  
  # Ensure APIs are enabled before creating resources
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service accounts for different components
resource "google_service_account" "ml_api_sa" {
  depends_on = [google_project_service.required_apis]
  
  account_id   = local.ml_api_sa_name
  display_name = "ML API Service Account"
  description  = "Service account for ML prediction API running on Cloud Run"
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_service_account" "ml_vertex_sa" {
  depends_on = [google_project_service.required_apis]
  
  account_id   = local.ml_vertex_sa_name
  display_name = "ML Vertex AI Service Account"
  description  = "Service account for Vertex AI training and serving operations"
  
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_service_account" "cloudbuild_sa" {
  depends_on = [google_project_service.required_apis]
  
  account_id   = local.cloudbuild_sa_name
  display_name = "Cloud Build Service Account"
  description  = "Service account for Cloud Build CI/CD operations"
  
  lifecycle {
    prevent_destroy = true
  }
}

# Cloud Storage buckets for ML data and artifacts
resource "google_storage_bucket" "training_data" {
  depends_on = [google_project_service.required_apis]
  
  name     = local.training_data_bucket
  location = var.region
  
  # Enable versioning for data lineage
  versioning {
    enabled = true
  }
  
  # Uniform bucket-level access for security
  uniform_bucket_level_access = true
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
  
  labels = local.common_labels
}

resource "google_storage_bucket" "model_artifacts" {
  depends_on = [google_project_service.required_apis]
  
  name     = local.model_artifacts_bucket
  location = var.region
  
  # Enable versioning for model artifact management
  versioning {
    enabled = true
  }
  
  # Uniform bucket-level access for security
  uniform_bucket_level_access = true
  
  # Lifecycle management for model artifacts
  lifecycle_rule {
    condition {
      age = 60
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
  
  labels = local.common_labels
}

# BigQuery dataset for user interaction data
resource "google_bigquery_dataset" "user_interactions" {
  depends_on = [google_project_service.required_apis]
  
  dataset_id  = local.dataset_id
  description = "Dataset for storing user interaction data for ML recommendation system"
  location    = var.region
  
  # Data retention and partitioning
  default_table_expiration_ms = 7776000000 # 90 days
  
  # Access control
  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }
  
  access {
    role   = "READER"
    user_by_email = google_service_account.ml_vertex_sa.email
  }
  
  access {
    role   = "WRITER"
    user_by_email = google_service_account.ml_api_sa.email
  }
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
  
  labels = local.common_labels
}

# BigQuery table for user interactions
resource "google_bigquery_table" "interactions" {
  depends_on = [google_bigquery_dataset.user_interactions]
  
  dataset_id = google_bigquery_dataset.user_interactions.dataset_id
  table_id   = "interactions"
  
  # Schema for user interaction data
  schema = jsonencode([
    {
      name = "user_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the user"
    },
    {
      name = "item_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the item"
    },
    {
      name = "interaction_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of interaction (view, purchase, rating, cart_add)"
    },
    {
      name = "rating"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Rating value (1.0 to 5.0) for rating interactions"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp of the interaction"
    },
    {
      name = "category"
      type = "STRING"
      mode = "NULLABLE"
      description = "Product category"
    },
    {
      name = "features"
      type = "JSON"
      mode = "NULLABLE"
      description = "Additional interaction features in JSON format"
    }
  ])
  
  # Time partitioning for query performance
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
  
  # Clustering for query optimization
  clustering = ["user_id", "interaction_type"]
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
  
  labels = local.common_labels
}

# Vertex AI dataset for ML training
resource "google_vertex_ai_dataset" "ml_dataset" {
  depends_on = [google_project_service.required_apis]
  
  display_name = "${local.resource_prefix}-dataset"
  
  # Use tabular data schema for recommendation systems
  metadata_schema_uri = "gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml"
  
  region = var.region
  
  labels = local.common_labels
}

# Vertex AI model for serving recommendations
resource "google_vertex_ai_model" "recommendation_model" {
  depends_on = [google_project_service.required_apis]
  
  display_name = local.model_name
  description  = "Collaborative filtering recommendation model"
  
  # Model will be uploaded after training
  # artifact_uri would be set during model training job
  
  # Container specification for TensorFlow models
  container_spec {
    image_uri = "gcr.io/cloud-aiplatform/prediction/tf2-cpu.2-12:latest"
    
    # Health check configuration
    health_route = "/v1/models/${local.model_name}"
    predict_route = "/v1/models/${local.model_name}:predict"
    
    # Resource requirements
    env {
      name  = "MODEL_NAME"
      value = local.model_name
    }
  }
  
  # Encryption configuration
  encryption_spec {
    kms_key_name = var.kms_key_name != null ? var.kms_key_name : null
  }
  
  region = var.region
  
  labels = local.common_labels
}

# Vertex AI endpoint for model serving
resource "google_vertex_ai_endpoint" "ml_endpoint" {
  depends_on = [google_project_service.required_apis]
  
  display_name = local.endpoint_name
  description  = "Endpoint for serving ML recommendation model"
  location     = var.region
  
  # Network configuration for security
  network = var.vpc_network_name != null ? var.vpc_network_name : null
  
  # Encryption configuration
  encryption_spec {
    kms_key_name = var.kms_key_name != null ? var.kms_key_name : null
  }
  
  labels = local.common_labels
}

# Cloud Run service for recommendation API
resource "google_cloud_run_service" "ml_api" {
  depends_on = [google_project_service.required_apis]
  
  name     = local.api_service_name
  location = var.region
  
  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = "100"
        "autoscaling.knative.dev/minScale" = "1"
        "run.googleapis.com/cpu-throttling" = "false"
        "run.googleapis.com/execution-environment" = "gen2"
      }
      
      labels = local.common_labels
    }
    
    spec {
      service_account_name = google_service_account.ml_api_sa.email
      
      # Container configuration
      containers {
        # Placeholder image - will be updated by Cloud Build
        image = "gcr.io/cloudrun/hello"
        
        # Resource limits
        resources {
          limits = {
            cpu    = "2000m"
            memory = "4Gi"
          }
          
          requests = {
            cpu    = "1000m"
            memory = "2Gi"
          }
        }
        
        # Environment variables
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        
        env {
          name  = "REGION"
          value = var.region
        }
        
        env {
          name  = "ENDPOINT_ID"
          value = google_vertex_ai_endpoint.ml_endpoint.name
        }
        
        env {
          name  = "DATASET_ID"
          value = google_bigquery_dataset.user_interactions.dataset_id
        }
        
        env {
          name  = "MODEL_BUCKET"
          value = google_storage_bucket.model_artifacts.name
        }
        
        # Health check configuration
        liveness_probe {
          http_get {
            path = "/"
            port = 8080
          }
          initial_delay_seconds = 30
          timeout_seconds       = 5
          period_seconds        = 10
          failure_threshold     = 3
        }
        
        readiness_probe {
          http_get {
            path = "/"
            port = 8080
          }
          initial_delay_seconds = 5
          timeout_seconds       = 5
          period_seconds        = 5
          failure_threshold     = 3
        }
      }
      
      # Timeout configuration
      timeout_seconds = 300
      
      # Container concurrency
      container_concurrency = 1000
    }
  }
  
  traffic {
    percent         = 100
    latest_revision = true
  }
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
  
  metadata {
    labels = local.common_labels
    
    annotations = {
      "run.googleapis.com/ingress" = "all"
    }
  }
}

# Cloud Build trigger for CI/CD
resource "google_cloudbuild_trigger" "ml_api_build" {
  depends_on = [google_project_service.required_apis]
  
  name        = "${local.resource_prefix}-build-trigger"
  description = "Build and deploy ML API service"
  
  # GitHub repository configuration (optional)
  dynamic "github" {
    for_each = var.github_repo_name != null ? [1] : []
    content {
      owner = var.github_owner
      name  = var.github_repo_name
      push {
        branch = "^main$"
      }
    }
  }
  
  # Build configuration
  build {
    # Build the Docker image
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "gcr.io/${var.project_id}/${local.api_service_name}:$COMMIT_SHA",
        "-t", "gcr.io/${var.project_id}/${local.api_service_name}:latest",
        "."
      ]
    }
    
    # Push the image to Container Registry
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "gcr.io/${var.project_id}/${local.api_service_name}:$COMMIT_SHA"
      ]
    }
    
    # Deploy to Cloud Run
    step {
      name = "gcr.io/cloud-builders/gcloud"
      args = [
        "run", "deploy", local.api_service_name,
        "--image", "gcr.io/${var.project_id}/${local.api_service_name}:$COMMIT_SHA",
        "--region", var.region,
        "--service-account", google_service_account.ml_api_sa.email,
        "--allow-unauthenticated"
      ]
    }
    
    # Build options
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
  }
  
  # Service account for Cloud Build
  service_account = google_service_account.cloudbuild_sa.id
  
  # Trigger configuration
  included_files = ["**"]
  ignored_files  = ["README.md", "docs/**"]
}

# IAM roles for ML API service account
resource "google_project_iam_member" "ml_api_vertex_user" {
  depends_on = [google_service_account.ml_api_sa]
  
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.ml_api_sa.email}"
}

resource "google_project_iam_member" "ml_api_bigquery_user" {
  depends_on = [google_service_account.ml_api_sa]
  
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.ml_api_sa.email}"
}

resource "google_project_iam_member" "ml_api_storage_viewer" {
  depends_on = [google_service_account.ml_api_sa]
  
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.ml_api_sa.email}"
}

# IAM roles for Vertex AI service account
resource "google_project_iam_member" "ml_vertex_ai_admin" {
  depends_on = [google_service_account.ml_vertex_sa]
  
  project = var.project_id
  role    = "roles/aiplatform.admin"
  member  = "serviceAccount:${google_service_account.ml_vertex_sa.email}"
}

resource "google_project_iam_member" "ml_vertex_storage_admin" {
  depends_on = [google_service_account.ml_vertex_sa]
  
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.ml_vertex_sa.email}"
}

resource "google_project_iam_member" "ml_vertex_bigquery_admin" {
  depends_on = [google_service_account.ml_vertex_sa]
  
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.ml_vertex_sa.email}"
}

# IAM roles for Cloud Build service account
resource "google_project_iam_member" "cloudbuild_run_developer" {
  depends_on = [google_service_account.cloudbuild_sa]
  
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

resource "google_project_iam_member" "cloudbuild_storage_admin" {
  depends_on = [google_service_account.cloudbuild_sa]
  
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

resource "google_project_iam_member" "cloudbuild_logs_writer" {
  depends_on = [google_service_account.cloudbuild_sa]
  
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# Cloud Run service IAM policy for public access
resource "google_cloud_run_service_iam_binding" "ml_api_public" {
  depends_on = [google_cloud_run_service.ml_api]
  
  service  = google_cloud_run_service.ml_api.name
  location = google_cloud_run_service.ml_api.location
  role     = "roles/run.invoker"
  
  members = [
    "allUsers"
  ]
}

# Storage bucket IAM for training data access
resource "google_storage_bucket_iam_binding" "training_data_access" {
  depends_on = [google_storage_bucket.training_data]
  
  bucket = google_storage_bucket.training_data.name
  role   = "roles/storage.objectViewer"
  
  members = [
    "serviceAccount:${google_service_account.ml_vertex_sa.email}",
    "serviceAccount:${google_service_account.ml_api_sa.email}"
  ]
}

# Storage bucket IAM for model artifacts
resource "google_storage_bucket_iam_binding" "model_artifacts_access" {
  depends_on = [google_storage_bucket.model_artifacts]
  
  bucket = google_storage_bucket.model_artifacts.name
  role   = "roles/storage.objectAdmin"
  
  members = [
    "serviceAccount:${google_service_account.ml_vertex_sa.email}",
    "serviceAccount:${google_service_account.ml_api_sa.email}"
  ]
}