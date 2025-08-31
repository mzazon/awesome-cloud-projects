# =============================================================================
# Terraform and Provider Version Requirements
# =============================================================================
# This file defines the minimum Terraform version and required providers
# for the Training Data Quality Assessment infrastructure.

terraform {
  # Minimum Terraform version required
  required_version = ">= 1.5.0"

  # Required providers with version constraints
  required_providers {
    # Google Cloud Platform provider
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Platform Beta provider (for preview features)
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Archive provider for creating ZIP files
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Local provider for local file operations
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }

    # Null provider for running local commands (if needed)
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # Optional: Configure remote state backend
  # Uncomment and customize the backend configuration below to store
  # Terraform state in a Google Cloud Storage bucket for team collaboration
  
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "training-data-quality"
  # }
}

# =============================================================================
# Provider Configuration
# =============================================================================

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Set user project override for billing quota
  user_project_override = true

  # Request-specific timeout settings
  request_timeout = "60s"

  # Default labels applied to all resources
  default_labels = merge(
    {
      managed-by        = "terraform"
      infrastructure    = "training-data-quality"
      terraform-version = "1.5+"
    },
    var.custom_labels
  )
}

# Configure the Google Cloud Beta Provider
# Used for accessing preview features and beta APIs
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Set user project override for billing quota
  user_project_override = true

  # Request-specific timeout settings
  request_timeout = "60s"

  # Default labels applied to all resources
  default_labels = merge(
    {
      managed-by        = "terraform"
      infrastructure    = "training-data-quality"
      terraform-version = "1.5+"
      provider-type     = "beta"
    },
    var.custom_labels
  )
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

# Configure the Null Provider
provider "null" {
  # No specific configuration required
}

# =============================================================================
# Google Cloud APIs that need to be enabled
# =============================================================================
# These APIs are automatically enabled when referenced by resources,
# but explicit enablement ensures proper dependency ordering

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",     # Cloud Functions API
    "aiplatform.googleapis.com",         # Vertex AI API
    "storage.googleapis.com",            # Cloud Storage API
    "cloudbuild.googleapis.com",         # Cloud Build API (for function deployment)
    "pubsub.googleapis.com",             # Pub/Sub API (for notifications)
    "monitoring.googleapis.com",         # Cloud Monitoring API
    "logging.googleapis.com",            # Cloud Logging API
    "iam.googleapis.com",                # Identity and Access Management API
    "cloudresourcemanager.googleapis.com", # Cloud Resource Manager API
    "serviceusage.googleapis.com",       # Service Usage API
    "storage-component.googleapis.com",   # Storage Component API
    "artifactregistry.googleapis.com",   # Artifact Registry API
  ])

  project = var.project_id
  service = each.value

  # Prevent disabling on destroy to avoid issues with dependent resources
  disable_dependent_services = false
  disable_on_destroy         = false

  # Add a timeout for API enablement
  timeouts {
    create = "30m"
    update = "40m"
    delete = "20m"
  }
}

# =============================================================================
# Data Sources for Provider Information
# =============================================================================

# Get available zones in the specified region
data "google_compute_zones" "available" {
  region = var.region
}

# Get the default compute service account
data "google_compute_default_service_account" "default" {
  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# Provider Feature Flags and Experimental Features
# =============================================================================

# Configure provider features and experimental options
# These settings control behavior of the Google Cloud provider

# Terraform configuration for experimental features
terraform {
  experiments = [
    # Enable provider functions (if available in your Terraform version)
    # provider_functions
  ]
}

# =============================================================================
# Validation and Constraints
# =============================================================================

# Validate that required APIs are available in the specified region
data "google_client_openid_userinfo" "me" {
  depends_on = [google_project_service.required_apis]
}

# Check if Vertex AI is available in the specified region
data "google_project" "current" {
  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# Local Values for Provider Configuration
# =============================================================================

locals {
  # Define regions where Vertex AI Gemini is available
  vertex_ai_regions = [
    "us-central1",
    "us-east1",
    "us-east4",
    "us-west1",
    "us-west4",
    "europe-west1",
    "europe-west4",
    "asia-northeast1",
    "asia-southeast1"
  ]

  # Validate that the selected region supports Vertex AI
  is_vertex_ai_region = contains(local.vertex_ai_regions, var.region)

  # Define regions where Cloud Functions Gen 2 is available
  cloud_functions_regions = [
    "us-central1",
    "us-east1",
    "us-east4",
    "us-west1",
    "us-west2",
    "us-west3",
    "us-west4",
    "europe-west1",
    "europe-west2",
    "europe-west3",
    "europe-west4",
    "europe-west6",
    "asia-east1",
    "asia-east2",
    "asia-northeast1",
    "asia-northeast2",
    "asia-northeast3",
    "asia-south1",
    "asia-southeast1",
    "asia-southeast2",
    "australia-southeast1"
  ]

  # Validate that the selected region supports Cloud Functions
  is_cloud_functions_region = contains(local.cloud_functions_regions, var.region)
}

# =============================================================================
# Provider Version Information Output
# =============================================================================

# Output provider version information for debugging
output "provider_versions" {
  description = "Information about provider versions and feature support"
  value = {
    terraform_version = "≥ 1.5.0"
    google_provider_version = "~> 6.0"
    google_beta_provider_version = "~> 6.0"
    random_provider_version = "~> 3.6"
    archive_provider_version = "~> 2.4"
    local_provider_version = "~> 2.5"
    null_provider_version = "~> 3.2"
    vertex_ai_supported = local.is_vertex_ai_region
    cloud_functions_supported = local.is_cloud_functions_region
    selected_region = var.region
  }
}

# =============================================================================
# Terraform Cloud/Enterprise Configuration (Optional)
# =============================================================================

# Uncomment and configure if using Terraform Cloud or Terraform Enterprise
# terraform {
#   cloud {
#     organization = "your-organization"
#     workspaces {
#       name = "training-data-quality"
#     }
#   }
# }

# =============================================================================
# Provider Aliases for Multi-Region Deployments (Optional)
# =============================================================================

# Uncomment if you need to deploy resources in multiple regions
# provider "google" {
#   alias   = "us_east1"
#   project = var.project_id
#   region  = "us-east1"
#   zone    = "us-east1-a"
# }

# provider "google" {
#   alias   = "europe_west1"
#   project = var.project_id
#   region  = "europe-west1"
#   zone    = "europe-west1-a"
# }