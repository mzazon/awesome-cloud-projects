# =============================================================================
# Weather API with Cloud Functions - Terraform Provider Configuration
# =============================================================================
# This file defines the required Terraform version and provider configurations
# for deploying the weather API infrastructure on Google Cloud Platform.
# =============================================================================

terraform {
  # Specify minimum Terraform version for compatibility
  required_version = ">= 1.5"

  # Define required providers with version constraints
  required_providers {
    # Google Cloud Platform provider for GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Platform Beta provider for preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Archive provider for creating zip files
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Random provider for generating unique suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Optional: Configure remote state backend
  # Uncomment and configure for production deployments
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "weather-api/terraform/state"
  # }
}

# =============================================================================
# GOOGLE CLOUD PROVIDER CONFIGURATION
# =============================================================================

# Configure the Google Cloud Provider with project and region defaults
provider "google" {
  # Project ID will be set via variable or environment variable GOOGLE_PROJECT
  project = var.project_id
  
  # Default region for resources
  region = var.region
  
  # Default zone (optional, will use region default if not specified)
  # zone = "${var.region}-a"

  # Optional: Specify credentials file path
  # credentials = file("path/to/service-account-key.json")
  
  # Enable request/response logging for debugging (disable in production)
  # request_timeout = "60s"
  
  # User agent prefix for API requests (helpful for tracking)
  user_project_override = true
  
  # Billing project for quota and billing purposes
  billing_project = var.project_id

  # Default labels applied to all resources (merged with resource-specific labels)
  default_labels = {
    managed_by    = "terraform"
    service       = "weather-api"
    environment   = var.environment
    cost_center   = var.cost_center != "" ? var.cost_center : "engineering"
    owner         = var.owner != "" ? var.owner : "platform-team"
    deployment    = "cloud-functions"
    resource_type = "serverless"
  }
}

# Configure the Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  
  # Enable the same configuration as the stable provider
  user_project_override = true
  billing_project       = var.project_id

  # Apply the same default labels
  default_labels = {
    managed_by    = "terraform"
    service       = "weather-api"
    environment   = var.environment
    cost_center   = var.cost_center != "" ? var.cost_center : "engineering"
    owner         = var.owner != "" ? var.owner : "platform-team"
    deployment    = "cloud-functions"
    resource_type = "serverless"
  }
}

# Configure the Archive provider (no specific configuration needed)
provider "archive" {
  # Archive provider doesn't require explicit configuration
}

# Configure the Random provider for generating unique identifiers
provider "random" {
  # Random provider doesn't require explicit configuration
}

# =============================================================================
# PROVIDER FEATURE FLAGS AND EXPERIMENTAL FEATURES
# =============================================================================

# Note: Google Cloud provider supports various feature flags
# These are typically used for experimental or beta features

# Example feature flags (uncomment if needed):
# provider "google" {
#   # Enable universe domain support for special GCP environments
#   universe_domain = "googleapis.com"
#   
#   # Enable impersonation for service account delegation
#   impersonate_service_account = "terraform@project.iam.gserviceaccount.com"
#   
#   # Configure custom endpoints (for testing or special environments)
#   cloud_functions_custom_endpoint = "https://cloudfunctions.googleapis.com/"
#   cloud_resource_manager_custom_endpoint = "https://cloudresourcemanager.googleapis.com/"
#   storage_custom_endpoint = "https://storage.googleapis.com/"
# }

# =============================================================================
# TERRAFORM CLOUD / TERRAFORM ENTERPRISE CONFIGURATION
# =============================================================================

# Uncomment and configure if using Terraform Cloud or Terraform Enterprise
# terraform {
#   cloud {
#     organization = "your-organization"
#     workspaces {
#       name = "weather-api-gcp"
#     }
#   }
# }

# =============================================================================
# LOCAL DEVELOPMENT CONFIGURATION
# =============================================================================

# For local development, ensure the following environment variables are set:
# - GOOGLE_PROJECT: Your GCP project ID
# - GOOGLE_APPLICATION_CREDENTIALS: Path to service account key file
# - GOOGLE_REGION: Default region for resources

# Alternatively, you can use gcloud authentication:
# gcloud auth application-default login
# gcloud config set project YOUR_PROJECT_ID

# =============================================================================
# PROVIDER VERSION COMPATIBILITY NOTES
# =============================================================================

# Google Provider v6.x Compatibility Notes:
# - Supports Cloud Functions Gen2 (google_cloudfunctions2_function)
# - Enhanced support for Cloud Run integration
# - Improved IAM and service account management
# - Better support for VPC connectors and networking
# - Enhanced monitoring and logging integration

# Archive Provider v2.4+ Features:
# - Support for multiple source files and directories
# - Improved compression algorithms
# - Better handling of file permissions and timestamps
# - Enhanced support for template files

# Random Provider v3.6+ Features:
# - Improved entropy sources
# - Better support for cryptographic randomness
# - Enhanced validation and constraints
# - Support for multiple random value types

# =============================================================================
# BACKWARDS COMPATIBILITY
# =============================================================================

# This configuration is compatible with:
# - Terraform >= 1.5.0
# - Google Provider >= 5.0, < 7.0
# - Google Beta Provider >= 5.0, < 7.0
# - Archive Provider >= 2.0, < 3.0
# - Random Provider >= 3.0, < 4.0

# Breaking changes from earlier versions:
# - google_cloudfunctions_function (v1) deprecated in favor of google_cloudfunctions2_function
# - Some IAM binding behaviors changed in Google Provider v5.0+
# - Archive provider output_path behavior changed in v2.3+

# Migration notes:
# - Cloud Functions v1 resources should be migrated to v2
# - Update IAM bindings to use newer syntax where applicable
# - Review archive provider configurations for path handling changes