# Terraform and Provider Version Requirements
# This file defines the minimum Terraform version and required providers
# for the Weather API Service with Cloud Functions recipe

terraform {
  # Require Terraform version 1.0 or higher for stability and feature support
  required_version = ">= 1.0"

  # Define required providers with specific version constraints
  required_providers {
    # Google Cloud Provider - official provider for GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Beta Provider - for accessing beta features if needed
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Random Provider - for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Archive Provider - for creating ZIP files for Cloud Functions
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Default Google Cloud Provider Configuration
provider "google" {
  project = var.project_id
  region  = var.region
}

# Google Cloud Beta Provider Configuration
provider "google-beta" {
  project = var.project_id
  region  = var.region
}