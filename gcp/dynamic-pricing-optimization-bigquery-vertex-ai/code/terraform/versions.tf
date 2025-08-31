# Terraform version and provider requirements for GCP Dynamic Pricing Optimization
# This file defines the minimum Terraform version and required providers for the solution

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Google Cloud Platform provider for core infrastructure
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }

    # Google Cloud Platform Beta provider for advanced features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }

    # Archive provider for creating Cloud Function source code archives
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

# Google Cloud provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Google Cloud Beta provider configuration for advanced features
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}