# Terraform version and provider requirements for Smart City Infrastructure Monitoring
# This configuration specifies the minimum required versions for Terraform and providers

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Google Cloud Provider for all GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Beta Provider for accessing preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource names
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
  zone    = var.zone

  # Enable user project override for better quota attribution
  user_project_override = true

  # Default labels to apply to all resources
  default_labels = {
    environment = var.environment
    project     = "smart-city-monitoring"
    managed-by  = "terraform"
    recipe-id   = "3c7d9f8a"
  }
}

# Configure the Google Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Enable user project override for better quota attribution
  user_project_override = true

  # Default labels to apply to all resources
  default_labels = {
    environment = var.environment
    project     = "smart-city-monitoring"
    managed-by  = "terraform"
    recipe-id   = "3c7d9f8a"
  }
}