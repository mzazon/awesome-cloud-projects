# Terraform provider version requirements for GCP automated API testing infrastructure
# This file defines the minimum required versions for Terraform and the Google Cloud provider

terraform {
  required_version = ">= 1.5"

  required_providers {
    # Google Cloud Platform provider for managing GCP resources
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 6.0"
    }

    # Google Cloud Platform Beta provider for accessing beta features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0, < 6.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = ">= 3.4"
    }

    # Archive provider for creating deployment packages
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Enable user project override for billing
  user_project_override = true

  # Set default labels for all resources
  default_labels = {
    environment   = var.environment
    project       = "api-testing"
    managed-by    = "terraform"
    recipe-id     = "a8f9e3d2"
  }
}

# Configure the Google Cloud Beta Provider for beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Enable user project override for billing
  user_project_override = true

  # Set default labels for all resources
  default_labels = {
    environment   = var.environment
    project       = "api-testing"
    managed-by    = "terraform"
    recipe-id     = "a8f9e3d2"
  }
}