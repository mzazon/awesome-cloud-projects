# Terraform version and provider requirements for Solar Assessment infrastructure
# This file specifies the required Terraform version and provider constraints
# to ensure compatibility and reproducible deployments

terraform {
  required_version = ">= 1.0"

  required_providers {
    # Google Cloud provider for core GCP resources
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }

    # Google Cloud Beta provider for preview features and advanced configurations
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }

    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }

    # Archive provider for function source code packaging
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Configure the Google Cloud provider with project and region defaults
provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure the Google Cloud Beta provider for preview features
provider "google-beta" {
  project = var.project_id
  region  = var.region
}