# Terraform provider version requirements for License Compliance Scanner
# This file specifies the minimum Terraform version and required providers

terraform {
  # Require Terraform version 1.0 or higher for modern features and stability
  required_version = ">= 1.0"

  # Define required providers with version constraints
  required_providers {
    # Google Cloud Platform provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Platform beta provider for experimental features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Archive provider for creating ZIP files for Cloud Functions
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Local provider for local file operations
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Enable request/response logging for debugging (disable in production)
  request_timeout = "60s"

  # Default labels to apply to all resources
  default_labels = {
    environment = var.environment
    managed-by  = "terraform"
    project     = "license-compliance-scanner"
  }
}

# Configure the Google Cloud Beta Provider for experimental features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Enable request/response logging for debugging (disable in production)
  request_timeout = "60s"

  # Default labels to apply to all resources
  default_labels = {
    environment = var.environment
    managed-by  = "terraform"
    project     = "license-compliance-scanner"
  }
}