# Terraform and provider version constraints for GCP Infrastructure Cost Optimization
#
# This file defines the minimum required versions for Terraform and the Google Cloud
# provider to ensure compatibility with all resources used in the cost optimization solution.

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Google Cloud Provider for core GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.44"
    }

    # Google Cloud Beta Provider for preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.44"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Archive provider for packaging Cloud Function source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Enable request/response logging for debugging (optional)
  request_timeout = "60s"
}

# Configure the Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}