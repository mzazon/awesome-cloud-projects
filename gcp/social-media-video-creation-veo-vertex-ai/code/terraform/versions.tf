# Terraform and Provider Version Requirements
# Social Media Video Creation with Veo 3 and Vertex AI

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # Google Cloud Provider - primary provider for GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Beta Provider - for preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Random Provider - for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Archive Provider - for creating zip files of function source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Local Provider - for local file operations
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }

    # Time Provider - for time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  # Optional: Configure backend for remote state storage
  # Uncomment and configure as needed for your environment
  #
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "terraform/state/video-generation"
  # }
  #
  # backend "remote" {
  #   organization = "your-terraform-cloud-org"
  #   workspaces {
  #     name = "video-generation-pipeline"
  #   }
  # }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region

  # Enable batching for improved performance
  batching {
    enable_batching = true
    send_after      = "5s"
  }

  # Default labels to apply to all resources
  default_labels = merge(var.labels, {
    managed-by = "terraform"
    component  = "video-generation"
    terraform-module = "social-media-video-creation"
  })

  # Request timeout configuration
  request_timeout = "60s"

  # User project override for quotas and billing
  user_project_override = true
}

# Configure the Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region

  # Enable batching for improved performance
  batching {
    enable_batching = true
    send_after      = "5s"
  }

  # Default labels to apply to all resources
  default_labels = merge(var.labels, {
    managed-by = "terraform"
    component  = "video-generation"
    terraform-module = "social-media-video-creation"
  })

  # Request timeout configuration
  request_timeout = "60s"

  # User project override for quotas and billing
  user_project_override = true
}

# Configure the Random Provider
provider "random" {
  # No specific configuration required
}

# Configure the Archive Provider
provider "archive" {
  # No specific configuration required
}

# Configure the Local Provider
provider "local" {
  # No specific configuration required
}

# Configure the Time Provider
provider "time" {
  # No specific configuration required
}

# Provider feature flags and experimental features
locals {
  # Provider feature configuration
  provider_features = {
    # Enable specific Google Cloud provider features
    enable_cloud_functions_v2 = true
    enable_vertex_ai          = true
    enable_cloud_storage      = true
    enable_iam_conditions     = true
  }

  # Supported regions for this deployment
  supported_regions = [
    "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
    "us-east4", "us-south1", "northamerica-northeast1", "northamerica-northeast2",
    "southamerica-east1", "southamerica-west1", "europe-central2", "europe-north1",
    "europe-southwest1", "europe-west1", "europe-west2", "europe-west3", "europe-west4",
    "europe-west6", "europe-west8", "europe-west9", "europe-west10", "europe-west12",
    "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
    "asia-south1", "asia-south2", "asia-southeast1", "asia-southeast2", "australia-southeast1",
    "australia-southeast2", "me-central1", "me-central2", "me-west1"
  ]

  # Required APIs for this deployment
  required_apis = [
    "cloudfunctions.googleapis.com",   # Cloud Functions for serverless compute
    "storage.googleapis.com",          # Cloud Storage for video storage
    "aiplatform.googleapis.com",       # Vertex AI for AI models
    "cloudbuild.googleapis.com",       # Cloud Build for function builds
    "logging.googleapis.com",          # Cloud Logging for observability
    "monitoring.googleapis.com",       # Cloud Monitoring for metrics
    "run.googleapis.com",              # Cloud Run (backend for Cloud Functions v2)
    "iam.googleapis.com",              # Identity and Access Management
    "cloudresourcemanager.googleapis.com", # Resource Manager API
    "serviceusage.googleapis.com"      # Service Usage API
  ]

  # Provider version compatibility matrix
  compatibility_matrix = {
    terraform_min_version = "1.0.0"
    google_provider_min   = "5.0.0"
    google_provider_max   = "7.0.0"
    python_runtime        = "python311"
    cloud_functions_gen   = "2nd generation"
  }
}

# Data sources for provider validation
data "google_client_config" "current" {}

data "google_project" "current" {
  project_id = var.project_id
}

# Validation checks
locals {
  # Validate that required APIs are available in the project
  validation_checks = {
    project_exists = data.google_project.current.project_id == var.project_id
    region_valid   = contains(local.supported_regions, var.region)
    # Add more validation checks as needed
  }
}

# Terraform version check (informational output)
output "terraform_version_info" {
  description = "Terraform version and provider information"
  value = {
    terraform_version    = ">=1.0"
    google_provider      = "~> 6.0"
    google_beta_provider = "~> 6.0"
    random_provider      = "~> 3.4"
    archive_provider     = "~> 2.4"
    local_provider       = "~> 2.4"
    time_provider        = "~> 0.9"
    current_project      = data.google_project.current.project_id
    current_region       = var.region
    deployment_timestamp = timestamp()
  }
}