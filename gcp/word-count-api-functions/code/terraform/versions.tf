# Terraform provider version constraints and required providers
# This file defines the minimum Terraform version and provider requirements
# to ensure compatibility and access to necessary features

terraform {
  # Require Terraform version 1.3 or later for optimal Google Cloud provider support
  required_version = ">= 1.3"

  required_providers {
    # Google Cloud Platform provider for GCP resource management
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Archive provider for creating ZIP files for Cloud Function source code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Random provider for generating unique resource suffixes
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Google Cloud Provider with default settings
# The provider will use the default credentials from the environment
# or Google Cloud SDK configuration
provider "google" {
  project = var.project_id
  region  = var.region
}