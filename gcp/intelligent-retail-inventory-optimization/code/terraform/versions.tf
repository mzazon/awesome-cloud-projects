# Terraform version and provider requirements for intelligent retail inventory optimization
# This configuration uses the latest stable Google Cloud provider with support for
# advanced services like Vertex AI, Cloud Optimization, and Fleet Engine

terraform {
  # Require Terraform 1.0 or later for stable features and improved error handling
  required_version = ">= 1.0"

  required_providers {
    # Google Cloud Platform provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44"
    }

    # Google Beta provider for access to preview features and services
    # Required for some advanced Vertex AI and optimization features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.44"
    }

    # Random provider for generating unique resource suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Time provider for managing time-based resources and delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Optional: Backend configuration for remote state storage
  # Uncomment and configure for production deployments
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "intelligent-retail-inventory-optimization"
  # }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Enable request/response logging for debugging (disable in production)
  request_timeout = "60s"
  
  # Default labels applied to all resources that support them
  default_labels = {
    environment   = var.environment
    project       = "intelligent-retail-inventory"
    managed-by    = "terraform"
    created-date  = formatdate("YYYY-MM-DD", timestamp())
  }
}

# Configure the Google Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels for beta resources
  default_labels = {
    environment   = var.environment
    project       = "intelligent-retail-inventory"
    managed-by    = "terraform"
    provider      = "google-beta"
  }
}

# Configure the Random provider
provider "random" {}

# Configure the Time provider
provider "time" {}