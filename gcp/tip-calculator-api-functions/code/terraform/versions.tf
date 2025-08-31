# Terraform and provider version constraints for GCP tip calculator API
# This file defines the minimum versions required for reliable deployment

terraform {
  # Require Terraform 1.0 or higher for stability and feature compatibility
  required_version = ">= 1.0"

  required_providers {
    # Google Cloud Provider - official provider for GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Archive provider for creating ZIP files from source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Google Cloud Provider with default settings
# Project and region can be overridden via variables
provider "google" {
  project = var.project_id
  region  = var.region
}