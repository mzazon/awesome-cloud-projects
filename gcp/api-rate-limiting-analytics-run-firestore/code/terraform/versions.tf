# Terraform and provider version requirements
# This file defines the minimum versions for Terraform and required providers
# to ensure compatibility and access to the latest features

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Google Cloud Platform provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Beta provider for preview/beta features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Time provider for resource creation delays
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure the Google Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}