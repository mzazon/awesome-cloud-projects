# Terraform version and provider requirements
# This configuration defines the minimum Terraform version and required providers
# for deploying a multi-container Cloud Run application on Google Cloud Platform

terraform {
  # Require Terraform version 1.5.0 or higher for stable functionality
  required_version = ">= 1.5.0"

  required_providers {
    # Google Cloud Platform provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 6.14.0"
    }

    # Google Beta provider for preview features and advanced configurations
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.14.0"
    }

    # Random provider for generating secure passwords and unique identifiers
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }

    # Time provider for resource delays and time-based operations
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12.0"
    }
  }
}

# Primary Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels applied to all resources created by this provider
  default_labels = {
    environment = var.environment
    managed-by  = "terraform"
    application = "multi-container-app"
  }
}

# Google Beta provider for advanced features and preview APIs
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Apply consistent labeling across all resources
  default_labels = {
    environment = var.environment
    managed-by  = "terraform"
    application = "multi-container-app"
  }
}