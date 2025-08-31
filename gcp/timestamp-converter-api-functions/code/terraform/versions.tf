# Terraform and Provider Version Constraints
# This file specifies the minimum Terraform version and required provider versions

terraform {
  # Minimum Terraform version required for this configuration
  required_version = ">= 1.5"

  # Required provider specifications with version constraints
  required_providers {
    # Google Cloud Platform provider for GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Beta provider for beta/preview GCP features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
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
  }
}

# Default Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
}

# Google Beta provider configuration for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}