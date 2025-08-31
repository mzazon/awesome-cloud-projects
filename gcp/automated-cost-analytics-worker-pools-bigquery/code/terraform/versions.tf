# Terraform provider configuration for GCP Cost Analytics infrastructure
# This file defines the required providers and versions for the automated cost analytics solution

terraform {
  # Specify minimum Terraform version for compatibility with Google Cloud provider features
  required_version = ">= 1.0"

  # Define required providers and their version constraints
  required_providers {
    # Google Cloud Platform provider for managing GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Beta provider for accessing preview features and services
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Archive provider for creating deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure the Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}