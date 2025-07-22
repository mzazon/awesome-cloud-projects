# versions.tf
# Terraform and Provider Version Requirements for Data Privacy Compliance Solution

terraform {
  # Minimum Terraform version with support for GCP provider features
  required_version = ">= 1.3"

  required_providers {
    # Google Cloud Platform provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Beta provider for preview features and advanced configurations
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource names and identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
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
}

# Configure the Google Beta Provider for advanced features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}