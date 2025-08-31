# Terraform version and provider requirements for BMI Calculator API
# This file defines the minimum Terraform version and required providers

terraform {
  # Require Terraform 1.0 or later for advanced features and stability
  required_version = ">= 1.0"

  # Define required providers with version constraints
  required_providers {
    # Google Cloud Platform provider for managing GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Platform Beta provider for accessing beta features
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
      version = "~> 3.5"
    }
  }
}

# Configure the Google Cloud Platform provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Configure the Google Cloud Platform Beta provider for beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}