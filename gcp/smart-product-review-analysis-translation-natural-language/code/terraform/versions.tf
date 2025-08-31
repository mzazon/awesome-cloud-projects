# Terraform and provider version requirements
# This file defines the required Terraform version and provider configurations
# for the smart product review analysis infrastructure

terraform {
  # Require Terraform version 1.0 or higher for stability and modern features
  required_version = ">= 1.0"

  # Define required providers with version constraints
  required_providers {
    # Google Cloud Platform provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Beta provider for preview features and services
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
      version = "~> 3.6"
    }
  }
}

# Configure the Google Cloud provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels to apply to all resources for cost tracking and management
  default_labels = {
    environment = var.environment
    application = "review-analysis"
    managed-by  = "terraform"
  }
}

# Configure the Google Beta provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels to apply to all resources
  default_labels = {
    environment = var.environment
    application = "review-analysis"
    managed-by  = "terraform"
  }
}