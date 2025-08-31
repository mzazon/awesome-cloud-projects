# Terraform version and provider requirements
# This file specifies the minimum Terraform version and required providers
# for the password generator Cloud Function deployment

terraform {
  # Require Terraform version 1.0 or higher for stability and latest features
  required_version = ">= 1.0"

  # Required providers with version constraints
  required_providers {
    # Google Cloud Platform provider
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Platform Beta provider for preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Archive provider for creating ZIP files for function source code
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

# Default Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels applied to all resources
  default_labels = {
    environment = var.environment
    managed-by  = "terraform"
    recipe      = "password-generator-cloud-functions"
  }
}

# Google Cloud Beta provider for accessing preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Default labels applied to all resources
  default_labels = {
    environment = var.environment
    managed-by  = "terraform"
    recipe      = "password-generator-cloud-functions"
  }
}