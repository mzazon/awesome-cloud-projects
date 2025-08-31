# Terraform Provider Configuration for Unit Converter API
# This file defines the required Terraform and provider versions

terraform {
  # Specify minimum Terraform version for compatibility
  required_version = ">= 1.0"

  required_providers {
    # Google Cloud Provider - Official provider for Google Cloud Platform resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Beta Provider - For accessing beta features and resources
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Random Provider - For generating random values (bucket suffixes, etc.)
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    # Archive Provider - For creating ZIP archives of function source code
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
}

# Configure the Google Cloud Beta Provider for beta features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}