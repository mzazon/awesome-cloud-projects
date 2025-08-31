# Terraform version and provider requirements for automated code refactoring infrastructure
# This configuration specifies the minimum versions for Terraform and Google Cloud Provider

terraform {
  # Require Terraform version 1.0 or higher for consistent behavior
  required_version = ">= 1.0"

  # Required providers for GCP infrastructure
  required_providers {
    # Google Cloud Platform provider for core infrastructure
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Beta provider for preview features
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Google Cloud Provider with default settings
provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure the Google Cloud Beta Provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Configure the Random provider
provider "random" {}