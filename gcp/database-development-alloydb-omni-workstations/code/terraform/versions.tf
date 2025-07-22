# Terraform version and provider requirements for GCP database development workflow
# This configuration defines the required providers for Cloud Workstations, 
# Cloud Build, Cloud Source Repositories, and related infrastructure

terraform {
  required_version = ">= 1.5"

  required_providers {
    # Google Cloud provider for general resources
    google = {
      source  = "hashicorp/google"
      version = ">= 6.44.0"
    }

    # Google Beta provider for Cloud Workstations (currently in beta)
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.44.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = ">= 3.4"
    }

    # Time provider for resource dependencies
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}

# Default Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels for all resources
  default_labels = {
    environment = var.environment
    project     = "database-development"
    managed-by  = "terraform"
  }
}

# Google Beta provider for Cloud Workstations
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels for all beta resources
  default_labels = {
    environment = var.environment
    project     = "database-development"
    managed-by  = "terraform"
  }
}